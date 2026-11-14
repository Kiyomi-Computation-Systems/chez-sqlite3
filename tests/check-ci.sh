#!/bin/sh
# check-ci: hold .github/workflows/ci.yml to the one shape this check reads.
#
#   sh tests/check-ci.sh DIR
#
# DIR must hold ci.yml alone, a regular file and no link: a second workflow
# would run jobs this check does not read. On a pass it prints one line on
# stdout and exits 0. On a failure it prints each problem on stderr, as
# "check-ci: FILE:LINE: problem", then "check-ci: FAILED (problems: N)", and
# exits 1. A usage error exits 2.
#
# The workflow is read as text, line by line, with awk (POSIX: nothing gawk
# only; CI's Ubuntu runs mawk), and it fails closed: a spelling that a text
# reader could misread is a problem, whatever it means to YAML. It checks:
#
#   - on every line, a block scalar's content included: a tab, or a character
#     beyond ASCII. Comments and blank lines are skipped;
#   - on every line that is not a block scalar's content: an explicit key (?),
#     an alias or anchor where a key goes (* or &, then a letter, digit, _ or
#     -: a shell case pattern *) and && are none), a quoted key, white space
#     between a key and its colon, a flow mapping ({ outside a quoted scalar
#     and a ${{ }} expression), a quoted scalar left open, and a backslash after
#     a double quote;
#   - the shape: the top-level keys, the three blocks `on`, `permissions` and
#     `concurrency` line for line, the five jobs (main, memory, nothreads,
#     floor and current) and each key in them, each
#     step's keys, with: and env: keys, the one if: and where it may be, the
#     cache keys, the checks each job must run, each as one step's whole run
#     line, in order, and the CHEZ each job runs with; in job main, ADR-0002's
#     install check, make build, as one step's whole run line, after its
#     check-chez step and before its make step; and in job main, between its
#     check-chez step and its make step, the steps "Report the versions this
#     run uses" (its run block, line for line) and "Report the runner's
#     SQLite" (its run line, and its env CHEZ), in that order;
#   - in jobs floor and current, which build SQLite and run the suites against
#     it (ADR-0003, decision 3), and nowhere else: the checkout with
#     submodules first; the steps that name the compiler (with id: cc), build
#     SQLite (under its own if), check it, run make build and run make test,
#     each as one step's whole run line, in order, after check-chez; the SQLite
#     cache's path and key, held whole, and its save keyed by its own
#     cache-primary-key; its if only on its build and its save, and the Chez
#     cache's if only on the Chez build and save; and the env keys
#     CHEZ_SQLITE3_LIBRARY and C_INCLUDE_PATH, each with exactly its job's
#     value, on the steps that run the check, make build and make test, each of
#     which must carry both and CHEZ, and on no other step;
#   - in every job: a uses: step may only be actions/checkout@,
#     actions/cache/restore@ or actions/cache/save@; each cache's restore comes
#     before its build, and its save after the build and before the cache's
#     check (a cache is told by its path, the Chez cache's or the SQLite
#     cache's); and in the lanes the SQLite restore comes after the step that
#     names the compiler;
#   - the names no line may hold: GITHUB_ENV, GITHUB_PATH, and as words the
#     variables that would steer a check (MAKEFLAGS, VALGRIND_*, ...), the
#     compiler's and the loader's among them (CC, C_INCLUDE_PATH, CPATH,
#     LD_LIBRARY_PATH, LD_PRELOAD), which could steer test-constants or the
#     load. CHEZ_SQLITE3_LIBRARY and C_INCLUDE_PATH are the one exception, as
#     an env key of floor and current, above. Job main is the one job that
#     tests discovery, so there, in memory and in nothreads they stay refused;
#     and
#     check-memory-gate, test-memory and check-nothreads anywhere but as the
#     whole run line of the step that runs them.
#
# A block scalar starts at a key whose value is | or > and holds every later
# line that is blank or indented deeper than that key (a "- " counts toward the
# key's column). Its lines are text, not YAML structure.
#
# Every rule is held by a row of tests/test-check-ci.sps, which plants it in a
# copy of the real workflow. A change to ci.yml changes this file with it.

usage() {
  printf 'check-ci: usage: sh tests/check-ci.sh DIR\n' >&2
  exit 2
}

[ $# -eq 1 ] || usage
dir=$1

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-ci.XXXXXX") || {
  printf 'check-ci: cannot make a scratch directory\n' >&2
  exit 1
}
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM

problems=$tmp/problems
: >"$problems"

# note TEXT: one problem, with no line.
note() {
  printf 'check-ci: %s\n' "$1" >>"$problems"
}

file=$dir/ci.yml

if [ ! -d "$dir" ]; then
  note "$dir: is not a directory"
else
  read_ok=0
  if [ -L "$file" ] || [ ! -f "$file" ]; then
    note "$file: is not a regular file: a link, a directory or nothing there"
  else
    read_ok=1
  fi
  ls -A -- "$dir" >"$tmp/entries"
  while IFS= read -r name; do
    [ "$name" = ci.yml ] || note "$dir: $name is not ci.yml: the directory must hold ci.yml alone"
  done <"$tmp/entries"

  if [ "$read_ok" -eq 1 ]; then
    # The three blocks the file must hold, line for line.
    cat >"$tmp/expected" <<'EXPECTED'
on:
  push:
    branches: [main]
    tags: ["v*"]
  pull_request:
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.run_id }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
EXPECTED

    cat >"$tmp/check.awk" <<'AWKPROGRAM'
function prob(n, m) { printf "check-ci: %s:%d: %s\n", F, n, m }

# odd(s): whether s holds a byte that is not printable ASCII (a tab apart).
function odd(s,   i, n, c) {
  n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c != "\t" && index(ascii, c) == 0) return 1
  }
  return 0
}

# colonpos(s): where the first colon followed by a space or the end is, or 0.
function colonpos(s,   i, n) {
  n = length(s)
  for (i = 1; i <= n; i++)
    if (substr(s, i, 1) == ":" && (i == n || substr(s, i + 1, 1) == " ")) return i
  return 0
}

# flowscan(s): 1 for a { outside a quoted scalar and a ${{ }} expression, 2 for
# a quoted scalar left open, else 0. A trailing comment ends the scan.
function flowscan(s,   i, n, c, q, prev, j) {
  n = length(s); q = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") {
      if (q == "\"" && c == "\\") { i++; continue }
      if (c == q) q = ""
      continue
    }
    if (c == "$" && substr(s, i, 3) == "${{") {
      j = index(substr(s, i + 3), "}}")
      if (j == 0) return 1
      i = i + 3 + j
      continue
    }
    prev = (i == 1) ? " " : substr(s, i - 1, 1)
    if ((c == "\"" || c == "'") && (prev == " " || prev == "[" || prev == "," || prev == ":")) { q = c; continue }
    if (c == "{") return 1
    if (c == "#" && prev == " ") return 0
  }
  if (q != "") return 2
  return 0
}

function addblk(k) {
  an[k]++
  al[k, an[k]] = raw
  aln[k, an[k]] = ln
}

function closeblock(k,   i, top) {
  top = (an[k] > en[k]) ? an[k] : en[k]
  for (i = 1; i <= top; i++) {
    if (i > an[k]) { prob(aln[k, an[k]], "the \"" k "\" block ends early: expected \"" el[k, i] "\""); return }
    if (i > en[k]) { prob(aln[k, i], "the \"" k "\" block has a line it must not: \"" al[k, i] "\""); return }
    if (al[k, i] != el[k, i]) {
      prob(aln[k, i], "the \"" k "\" block differs from the one check-ci holds: expected \"" el[k, i] "\", found \"" al[k, i] "\"")
      return
    }
  }
}

# isl(j): whether j is one of the two SQLite lanes, floor and current.
function isl(j) { return (j == "floor" || j == "current") }

# nreq(j): fills rq[1..n] with the run lines job j must run, in order.
function nreq(j) {
  if (j == "main") {
    rq[1] = CHKT; rq[2] = BUILDLINE; rq[3] = MAKELINE; rq[4] = LAUNCHER; return 4
  }
  if (j == "memory") {
    rq[1] = CHKT; rq[2] = "make check-memory-gate"; rq[3] = "make test-memory"; return 3
  }
  if (isl(j)) {
    rq[1] = CHKT; rq[2] = CCLINE; rq[3] = lanebld[j]; rq[4] = lanechk[j]; rq[5] = BUILDLINE; rq[6] = TESTLINE
    return 6
  }
  rq[1] = BLDN; rq[2] = CHKN; rq[3] = "make check-nothreads"; return 3
}

function cachekey_ok(v,   want, tail) {
  if (v == "${{ steps.chez.outputs.cache-primary-key }}") return 1
  want = prefix[job] "${{ hashFiles(" HASHLIST ") }}"
  if (substr(v, 1, length(want)) != want) return 0
  tail = substr(v, length(want) + 1)
  return (tail == "" || substr(tail, 1, 1) == "-")
}

function stepkey(   u) {
  subk = ""
  if (p == 0) { prob(ln, NOKEY); return }
  if (!(key in stepkeys)) { prob(ln, "step key \"" key "\" is not one of " STEPKEYS); return }
  if (key in sseen) { prob(ln, "step key \"" key "\" is written twice in one step"); return }
  sseen[key] = 1
  if (key == "with" || key == "env") {
    subk = key
    if (val != "") prob(ln, HASVAL)
  } else if (key == "if") {
    S_if[sn] = rest; S_ifln[sn] = ln
  } else if (key == "name") {
    S_name[sn] = rest
  } else if (key == "run") {
    S_run[sn] = rest; S_runln[sn] = ln
  } else if (key == "uses") {
    u = val; sub(/ +#.*$/, "", u); S_uses[sn] = u
  } else if (key == "id") {
    S_id[sn] = val
  }
}

function subkey(   want) {
  if (p == 0) { prob(ln, NOKEY); return }
  if (subk == "with") {
    if (!(key in withkeys)) { prob(ln, "with key \"" key "\" is not one of " WITHKEYS); return }
    if (key in wseen) { prob(ln, "with key \"" key "\" is written twice in one step"); return }
    wseen[key] = 1
    if (key == "submodules") S_sub[sn] = val
    if (key == "path") { S_path[sn] = val; S_pathln[sn] = ln }
    if (key == "key") { S_key[sn] = val; S_keyln[sn] = ln }
    if (key == "key" && !isl(job) && !cachekey_ok(val))
      prob(ln, "the cache key in job " job " does not begin with " prefix[job] "${{ hashFiles(" HASHLIST ") }}")
  } else {
    if (isl(job)) {
      if (!(key in laneenv)) { prob(ln, "env key \"" key "\" is not one of CHEZ, CHEZ_SQLITE3_LIBRARY, C_INCLUDE_PATH"); return }
    } else if (key != "CHEZ") { prob(ln, "env key \"" key "\" is not CHEZ"); return }
    if (key in eseen) { prob(ln, "env key \"" key "\" is written twice in one step"); return }
    eseen[key] = 1; S_env[sn] = 1
    S_ev[sn, key] = 1; S_evln[sn, key] = ln
    want = chezpath[job]
    if (key == "CHEZ_SQLITE3_LIBRARY") want = lanelib[job]
    if (key == "C_INCLUDE_PATH") want = laneinc[job]
    if (val != want) prob(ln, "env " key " in job " job " is not " want)
  }
}

# lanestep(): a SQLite lane's if and cache rules, for the step just ended.
function lanestep(   pth, want, id, savep) {
  savep = (S_uses[sn] ~ /^actions\/cache\/save@/)
  if (S_if[sn] != "") {
    if (S_if[sn] != IFLINE && S_if[sn] != IFSQL)
      prob(S_ifln[sn], "if is not one of \"" IFLINE "\" or \"" IFSQL "\"")
    else if (S_if[sn] == IFLINE && !(S_run[sn] ~ /^run: scripts\/ci\/build-chez\.sh( |$)/ || (savep && S_path[sn] == CHEZP)))
      prob(S_ifln[sn], "the Chez cache's if is on a step that is neither the Chez build nor the Chez cache's save")
    else if (S_if[sn] == IFSQL && !(S_run[sn] ~ /^run: scripts\/ci\/build-sqlite\.sh( |$)/ || (savep && S_path[sn] == sqp[job])))
      prob(S_ifln[sn], "the SQLite cache's if is on a step that is neither the SQLite build nor the SQLite cache's save")
  }
  if (!(savep || S_uses[sn] ~ /^actions\/cache\/restore@/)) return
  pth = S_path[sn]
  if (pth != CHEZP && pth != sqp[job]) {
    prob(S_pathln[sn] ? S_pathln[sn] : S_ln[sn], "the cache path in job " job " is not one of " CHEZP " or " sqp[job])
    return
  }
  id = (pth == CHEZP) ? "chez" : "sqlite"
  if (savep) {
    want = "${{ steps." id ".outputs.cache-primary-key }}"
    if (S_key[sn] != want) prob(S_keyln[sn] ? S_keyln[sn] : S_ln[sn], "the cache key of the save in job " job " is not exactly " want)
  } else if (pth == CHEZP) {
    if (!cachekey_ok(S_key[sn])) prob(S_keyln[sn] ? S_keyln[sn] : S_ln[sn], "the cache key in job " job " does not begin with " prefix[job] "${{ hashFiles(" HASHLIST ") }}")
  } else if (S_key[sn] != lanekey[job]) {
    prob(S_keyln[sn] ? S_keyln[sn] : S_ln[sn], "the cache key in job " job " is not exactly " lanekey[job])
  }
}

function endstep() {
  if (!instep) return
  instep = 0
  if (isl(job)) { lanestep(); return }
  if (S_if[sn] != "") {
    if (S_if[sn] != IFLINE) prob(S_ifln[sn], "if is not exactly \"" IFLINE "\"")
    if (!(S_run[sn] ~ /^run: scripts\/ci\/build-chez\.sh( |$)/ || S_uses[sn] ~ /^actions\/cache\/save@/))
      prob(S_ifln[sn], "if is on a step that neither runs scripts/ci/build-chez.sh nor uses actions/cache/save")
  }
}

# stepnamed(nm, first, last): the one step of job main named nm, or 0 (and a
# problem) when there is not exactly one.
function stepnamed(nm, first, last,   s, c, at) {
  c = 0; at = 0
  for (s = first; s <= last; s++) if (S_name[s] == "name: " nm) { c++; at = s }
  if (c != 1) { prob(jln, "job main has " c " steps named \"" nm "\", not one"); return 0 }
  return at
}

# mainsteps(first, last): the two report steps of job main. atrun[CHKT] and
# atrun[MAKELINE] are the steps that run check-chez and the make line, or 0 when
# one is missing (a problem already told).
function mainsteps(first, last,   v, q, i, n, m, w, rl) {
  v = stepnamed(VERS, first, last)
  q = stepnamed(SQLN, first, last)
  if (v && atrun[CHKT] && v < atrun[CHKT]) prob(S_ln[v], "job main runs step \"" VERS "\" before \"" CHKT "\", and must run it after")
  if (v && atrun[MAKELINE] && v > atrun[MAKELINE]) prob(S_ln[v], "job main runs step \"" VERS "\" after \"" MAKELINE "\", and must run it before")
  if (q && atrun[CHKT] && q < atrun[CHKT]) prob(S_ln[q], "job main runs step \"" SQLN "\" before \"" CHKT "\", and must run it after")
  if (q && atrun[MAKELINE] && q > atrun[MAKELINE]) prob(S_ln[q], "job main runs step \"" SQLN "\" after \"" MAKELINE "\", and must run it before")
  if (v && q && q < v) prob(S_ln[q], "job main's step \"" SQLN "\" comes before step \"" VERS "\", and must come after")
  if (v) {
    rl = S_runln[v] ? S_runln[v] : S_ln[v]
    if (S_run[v] != "run: |") prob(rl, "job main's step \"" VERS "\" does not run a block: it must be run: |")
    else {
      n = bn[v]
      m = (n > nvl) ? n : nvl
      for (i = 1; i <= m; i++) {
        if (i > n) { prob(bln[v, n] ? bln[v, n] : rl, "job main's step \"" VERS "\" has a run block that ends early: expected \"" vl[i] "\""); break }
        if (i > nvl) { prob(bln[v, i], "job main's step \"" VERS "\" has a run line it must not: \"" bl[v, i] "\""); break }
        if (bl[v, i] != vl[i]) {
          prob(bln[v, i], "job main's step \"" VERS "\" has a run line that differs from the one check-ci holds: expected \"" vl[i] "\", found \"" bl[v, i] "\"")
          break
        }
      }
    }
  }
  if (q) {
    rl = S_runln[q] ? S_runln[q] : S_ln[q]
    if (S_run[q] != "run: " SQLRUN) prob(rl, "job main's step \"" SQLN "\" is not run: " SQLRUN)
    if (!S_env[q]) prob(S_ln[q], "job main's step \"" SQLN "\" has no env CHEZ")
  }
}

function needenv(at, x, k) {
  if (!((at, k) in S_ev)) prob(S_ln[at], "job " job "'s step that runs \"" x "\" has no env " k)
}

# cachekind(s): "Chez" or "SQLite" for a cache restore or save step by its path,
# else "".
function cachekind(s,   pth) {
  if (!(S_uses[s] ~ /^actions\/cache\/(restore|save)@/)) return ""
  pth = S_path[s]
  if (pth ~ /\/chez-(threads|nothreads)$/) return "Chez"
  if (pth ~ /\/sqlite-(floor|current)$/) return "SQLite"
  return ""
}

# runs(s, what, prog): whether step s runs scripts/ci/WHAT-PROG.sh.
function runs(s, what, prog) {
  return (S_run[s] ~ ("^run: scripts/ci/" what "-" prog "\\.sh( |$)"))
}

# cacheorder(first, last): each cache's restore before its build, its save after
# the build and before its check, and in the lanes the SQLite restore after the
# step that names the compiler.
function cacheorder(first, last,   s, b, k, kk, cn, restore) {
  for (s = first; s <= last; s++) {
    if (S_uses[s] != "" && !(S_uses[s] ~ /^actions\/(checkout|cache\/restore|cache\/save)@/))
      prob(S_ln[s], "job " job " has a step that uses \"" S_uses[s] "\", which is not actions/checkout@, actions/cache/restore@ or actions/cache/save@")
    k = cachekind(s)
    if (k == "") continue
    kk = tolower(k)
    restore = (S_uses[s] ~ /^actions\/cache\/restore@/)
    for (b = first; b <= last; b++) {
      if (runs(b, "build", kk)) {
        if (restore && s > b) prob(S_ln[s], "job " job " restores the " k " cache after the " k " build, and must restore it before")
        if (!restore && s < b) prob(S_ln[s], "job " job " saves the " k " cache before the " k " build, and must save it after")
      }
      if (!restore && runs(b, "check", kk) && s > b)
        prob(S_ln[s], "job " job " saves the " k " cache after the " k " check, and must save it before")
    }
    if (restore && k == "SQLite" && isl(job) && atrun[CCLINE] && s < atrun[CCLINE])
      prob(S_ln[s], "job " job " restores the SQLite cache before the step that names the C compiler, and must restore it after")
  }
}

function endjob(   i, k, s, c, at, pos, lastp, m, x, before, first, last, isb, okstep) {
  if (job == "") return
  endstep()
  for (i = 1; i <= 4; i++)
    if (!jbad && !(jk2[i] in jkseen)) prob(jln, "job " job " has no key \"" jk2[i] "\"")
  first = jfirst; last = sn; lastp = 0; before = "the start"
  if (job == "main" || isl(job)) {
    if (first > last || !(S_uses[first] ~ /^actions\/checkout@/ && S_sub[first] == "recursive" && S_run[first] == "" && S_if[first] == ""))
      prob((first <= last) ? S_ln[first] : jln, "job " job "'s first step is not uses: actions/checkout@ with submodules: recursive")
  }
  if (job == "main") {
    if (first + 1 > last || S_run[first + 1] != "run: " PINRUN)
      prob((first + 1 <= last) ? S_ln[first + 1] : jln, "job main's second step is not run: " PINRUN)
    lastp = 2; before = PINRUN
  }
  m = nreq(job)
  for (i = 1; i <= m; i++) {
    x = rq[i]; c = 0; at = 0; atrun[x] = 0
    for (s = first; s <= last; s++) if (S_run[s] == "run: " x) { c++; at = s }
    if (c != 1) { prob(jln, "job " job " has " c " steps that run \"" x "\", not one"); before = x; continue }
    atrun[x] = at
    pos = at - first + 1
    if (pos <= lastp) prob(S_runln[at], "job " job " runs \"" x "\" before \"" before "\", and must run it after")
    else lastp = pos
    isb = ((job == "nothreads" && i == 1) || (isl(job) && i == 3))
    if (isb) {
      if (S_if[at] == "") prob(S_ln[at], "job " job "'s step that runs \"" x "\" has no if")
    } else if (S_if[at] != "") prob(S_ifln[at], "job " job "'s step that runs \"" x "\" has an if")
    if (isl(job)) {
      if (i == 2 && S_id[at] != "cc") prob(S_ln[at], "job " job "'s step that runs \"" x "\" has no id: cc")
      if (i >= 3) needenv(at, x, "CHEZ")
      if (i >= 4) { needenv(at, x, "CHEZ_SQLITE3_LIBRARY"); needenv(at, x, "C_INCLUDE_PATH") }
    }
    before = x
  }
  cacheorder(first, last)
  if (isl(job)) {
    # The two names are for the three steps that run the check, make build and
    # make test, and for no other step of the lane.
    for (s = first; s <= last; s++) {
      okstep = (S_run[s] == "run: " rq[4] || S_run[s] == "run: " rq[5] || S_run[s] == "run: " rq[6])
      if (okstep) continue
      if ((s, "CHEZ_SQLITE3_LIBRARY") in S_ev)
        prob(S_evln[s, "CHEZ_SQLITE3_LIBRARY"], "env key \"CHEZ_SQLITE3_LIBRARY\" is only for the steps that run the SQLite check, make build and make test")
      if ((s, "C_INCLUDE_PATH") in S_ev)
        prob(S_evln[s, "C_INCLUDE_PATH"], "env key \"C_INCLUDE_PATH\" is only for the steps that run the SQLite check, make build and make test")
    }
  }
  if (job == "main") mainsteps(first, last)
  job = ""
}

function endsec(   i) {
  endjob()
  if (curblk != "") { closeblock(curblk); curblk = "" }
  if (sec == "jobs")
    for (i = 1; i <= 5; i++)
      if (!(jn[i] in jobseen)) prob(jobsln, "job \"" jn[i] "\" is missing")
  sec = ""
}

BEGIN {
  F = ENVIRON["CI_FILE"]
  for (i = 32; i < 127; i++) ascii = ascii sprintf("%c", i)
  TOPS = "name, on, permissions, concurrency, jobs"
  split("name on permissions concurrency jobs", tk, " ")
  for (i = 1; i <= 5; i++) topidx[tk[i]] = i
  isblock["on"] = 1; isblock["permissions"] = 1; isblock["concurrency"] = 1
  JOBS = "main, memory, nothreads, floor, current"
  split("main memory nothreads floor current", jn, " ")
  for (i = 1; i <= 5; i++) wantjob[jn[i]] = 1
  JOBKEYS = "name, runs-on, timeout-minutes, steps"
  split("name runs-on timeout-minutes steps", jk2, " ")
  for (i = 1; i <= 4; i++) jobkey[jk2[i]] = 1
  STEPKEYS = "name, id, uses, with, run, env, if"
  split("name id uses with run env if", sk, " ")
  for (i = 1; i <= 7; i++) stepkeys[sk[i]] = 1
  WITHKEYS = "submodules, path, key"
  split("submodules path key", wk, " ")
  for (i = 1; i <= 3; i++) withkeys[wk[i]] = 1
  gname[1] = "check-memory-gate"; gjob[1] = "memory"
  gname[2] = "test-memory";       gjob[2] = "memory"
  gname[3] = "check-nothreads";   gjob[3] = "nothreads"
  nbw = split("MAKEFLAGS MFLAGS GNUMAKEFLAGS VALGRIND MEMORY_SUITES MEMORY_TIMEOUT TEST_TIMEOUT LIBDIRS TIMEOUT SUITES CHEZ_SQLITE3_LIBRARY CHEZ_SQLITE3_DECOY CHEZ_SQLITE3_GATE_CHILD CC C_INCLUDE_PATH CPATH LD_LIBRARY_PATH LD_PRELOAD", bw, " ")
  for (i = 1; i <= nbw; i++) banned[bw[i]] = 1
  HASHLIST = "'packaging/floors.sexp', 'scripts/ci/floor.sh', 'scripts/ci/build-chez.sh', 'scripts/ci/check-chez.sh'"
  IFLINE = "if: steps.chez.outputs.cache-hit != 'true'"
  IFSQL = "if: steps.sqlite.outputs.cache-hit != 'true'"
  TESTLINE = "make test"
  CHEZP = "${{ runner.temp }}/chez-threads"
  CCLINE = "echo \"id=$(cc --version | head -n 1 | tr -c '[:alnum:].' '-')\" >> \"$GITHUB_OUTPUT\""
  laneflag["floor"] = ""; laneflag["current"] = " --current"
  lanehash["floor"] = "'packaging/floors.sexp', 'scripts/ci/floor.sh', 'scripts/ci/build-sqlite.sh', 'scripts/ci/check-sqlite.sh'"
  lanehash["current"] = "'scripts/ci/build-sqlite.sh', 'scripts/ci/check-sqlite.sh'"
  split("floor current", lj, " ")
  for (i = 1; i <= 2; i++) {
    j = lj[i]
    sqp[j] = "${{ runner.temp }}/sqlite-" j
    lanelib[j] = sqp[j] "/lib/libsqlite3.so.0"
    laneinc[j] = sqp[j] "/include"
    lanebld[j] = "scripts/ci/build-sqlite.sh \"$RUNNER_TEMP/sqlite-" j "\"" laneflag[j]
    lanechk[j] = "scripts/ci/check-sqlite.sh \"$RUNNER_TEMP/sqlite-" j "\"" laneflag[j]
    lanekey[j] = "sqlite-" j "-${{ hashFiles(" lanehash[j] ") }}-${{ steps.image.outputs.id }}-${{ steps.cc.outputs.id }}"
  }
  laneenv["CHEZ"] = 1; laneenv["CHEZ_SQLITE3_LIBRARY"] = 1; laneenv["C_INCLUDE_PATH"] = 1
  PINRUN = "scripts/ci/check-action-pins.sh .github/workflows"
  CHKT = "scripts/ci/check-chez.sh \"$RUNNER_TEMP/chez-threads\""
  CHKN = "scripts/ci/check-chez.sh \"$RUNNER_TEMP/chez-nothreads\" --nothreads"
  BLDN = "scripts/ci/build-chez.sh \"$RUNNER_TEMP/chez-nothreads\" --nothreads"
  BUILDLINE = "make build"
  MAKELINE = "make check-help check-suites check-pins check-floors check-ci test check-test-fails check-dev check-clean"
  LAUNCHER = "sh tests/guix-env-launcher.sh"
  VERS = "Report the versions this run uses"
  SQLN = "Report the runner's SQLite"
  SQLRUN = "scripts/ci/report-sqlite.sh"
  nvl = 5
  vl[1] = "          \"$RUNNER_TEMP/chez-threads/bin/scheme\" --version"
  vl[2] = "          cc --version | head -n 1"
  vl[3] = "          valgrind --version"
  vl[4] = "          echo \"image: ${ImageOS:-unknown} ${ImageVersion:-unknown}\""
  vl[5] = "          echo \"kernel: $(uname -r)\""
  chezpath["main"] = "${{ runner.temp }}/chez-threads/bin/scheme"
  chezpath["memory"] = chezpath["main"]
  chezpath["nothreads"] = "${{ runner.temp }}/chez-nothreads/bin/scheme"
  chezpath["floor"] = chezpath["main"]; chezpath["current"] = chezpath["main"]
  prefix["main"] = "chez-threads-"; prefix["memory"] = "chez-threads-"; prefix["nothreads"] = "chez-nothreads-"
  prefix["floor"] = "chez-threads-"; prefix["current"] = "chez-threads-"
  HASVAL = "this key must hold a block, not a value"
  NOKEY = "is not a key line check-ci reads"
  PLACE = "is not a line check-ci reads at this place"
  job = ""; sec = ""; curblk = ""; lastidx = 0
}

FNR == 1 { fileno++ }

# The first file: the blocks the workflow must hold, line for line.
fileno == 1 {
  if ($0 ~ /^[^ ]/) { ek = $0; sub(/:.*/, "", ek) }
  en[ek]++
  el[ek, en[ek]] = $0
  next
}

# The second file: the workflow.
{
  ln = FNR; lastline = FNR; raw = $0
  if (raw ~ /^ *$/) next
  ind = 0
  while (substr(raw, ind + 1, 1) == " ") ind++
  content = 0
  if (inblock) { if (ind > blockcol) content = 1; else inblock = 0 }
  if (content && instep) { bn[sn]++; bl[sn, bn[sn]] = raw; bln[sn, bn[sn]] = ln }
  if (substr(raw, ind + 1, 1) == "#") next

  bad = 0
  if (index(raw, "\t") > 0) { prob(ln, "holds a tab, which YAML may read as white space beside a key"); bad = 1 }
  if (odd(raw)) { prob(ln, "holds a character beyond ASCII, which GitHub may fold into a key's letters"); bad = 1 }

  rest = ""; col = ind; dashed = 0
  if (!content) {
    rest = substr(raw, ind + 1)
    while (rest == "-" || substr(rest, 1, 2) == "- ") {
      dashed++; rest = substr(rest, 2); col++
      while (substr(rest, 1, 1) == " ") { rest = substr(rest, 2); col++ }
    }
  }

  # The names no line may hold, a block scalar's content included.
  if (index(raw, "GITHUB_ENV") > 0) prob(ln, "names GITHUB_ENV, which could steer a check or a later step")
  if (index(raw, "GITHUB_PATH") > 0) prob(ln, "names GITHUB_PATH, which could steer a check or a later step")
  # The one place in the file the two names may stand: as the key of an env
  # line, at its own indent, in a step of the floor or current job. Its value
  # is held exactly, and the steps that may carry it are held, at the job's end.
  ealk = ""
  if (!content && dashed == 0 && ind == 10 && instep && subk == "env" && isl(job)) {
    if (substr(rest, 1, 22) == "CHEZ_SQLITE3_LIBRARY: ") ealk = "CHEZ_SQLITE3_LIBRARY"
    else if (substr(rest, 1, 16) == "C_INCLUDE_PATH: ") ealk = "C_INCLUDE_PATH"
  }
  w = raw; gsub(/[^A-Za-z0-9_]+/, " ", w)
  nw = split(w, ws, " "); split("", seen)
  for (k = 1; k <= nw; k++) {
    x = ws[k]
    if (k == 1 && ealk != "" && x == ealk) continue
    if (!(x in seen) && ((x in banned) || x ~ /^VALGRIND_/)) {
      seen[x] = 1
      prob(ln, "names " x ", which could steer a check or a later step")
    }
  }
  for (g = 1; g <= 3; g++)
    if (index(raw, gname[g]) > 0 && !(!content && rest == "run: make " gname[g] && job == gjob[g]))
      prob(ln, "names " gname[g] " other than as the whole run line of the one step that runs it")

  if (content) next

  # Spellings that a text reader could misread.
  p = colonpos(rest); key = ""; val = ""
  if (p > 0) { key = substr(rest, 1, p - 1); val = (p < length(rest)) ? substr(rest, p + 2) : "" }
  if (rest ~ /^\?( |$)/) { prob(ln, "writes an explicit key, with ?, whose colon may be on another line"); bad = 1 }
  if (rest ~ /^[*&][A-Za-z0-9_-]/) { prob(ln, "puts an alias or an anchor where a key goes"); bad = 1 }
  if (rest ~ /^["']/) { prob(ln, "writes a quoted key"); bad = 1 }
  if (p > 1 && substr(rest, p - 1, 1) == " ") { prob(ln, "has white space between a key and its colon"); bad = 1 }
  fl = flowscan(raw)
  if (fl == 1) { prob(ln, "holds a flow mapping, with {, outside a quoted scalar and a ${{ }} expression"); bad = 1 }
  if (fl == 2) { prob(ln, "holds a quoted scalar that runs past the line's end"); bad = 1 }
  q = index(raw, "\"")
  if (q > 0 && index(substr(raw, q + 1), "\\") > 0) { prob(ln, "holds a backslash after a double quote, which YAML may read as an escape"); bad = 1 }

  if (!bad && p > 0 && val ~ /^[|>][-+0-9]*( +#.*)?$/) { inblock = 1; blockcol = col }

  # The shape.
  if (ind == 0 && dashed == 0) {
    endsec(); sec = "ignore"; curblk = ""
    if (bad) next
    if (p == 0) { prob(ln, NOKEY); next }
    if (!(key in topidx)) { prob(ln, "top-level key \"" key "\" is not one of " TOPS); next }
    if (key in topseen) { prob(ln, "top-level key \"" key "\" is written twice"); next }
    topseen[key] = 1
    if (topidx[key] < lastidx) prob(ln, "top-level key \"" key "\" comes out of order: the order is " TOPS)
    else lastidx = topidx[key]
    sec = key
    if (key in isblock) { curblk = key; addblk(key) }
    if (key == "jobs") { jobsln = ln; if (val != "") prob(ln, HASVAL) }
    next
  }
  if (curblk != "") { addblk(curblk); next }
  if (sec != "jobs") next

  if (ind == 2 && dashed == 0) {
    endjob()
    if (bad) next
    if (p == 0) { prob(ln, NOKEY); next }
    if (!(key in wantjob)) { prob(ln, "job \"" key "\" is not one of " JOBS); next }
    if (key in jobseen) { prob(ln, "job \"" key "\" is written twice"); next }
    jobseen[key] = 1; job = key; jln = ln; jfirst = sn + 1
    split("", jkseen); curjk = ""; instep = 0; jbad = 0
    if (val != "") prob(ln, HASVAL)
    next
  }
  if (job == "") next

  if (ind == 4 && dashed == 0) {
    endstep(); curjk = ""
    if (bad) { jbad = 1; next }
    if (p == 0) { prob(ln, NOKEY); next }
    if (!(key in jobkey)) { prob(ln, "job " job " has the key \"" key "\", which is not one of " JOBKEYS); next }
    if (key in jkseen) { prob(ln, "job " job " has the key \"" key "\" twice"); next }
    jkseen[key] = 1; curjk = key
    if (key == "runs-on" && val != "ubuntu-24.04") prob(ln, "job " job " has runs-on other than ubuntu-24.04")
    if (key == "timeout-minutes" && val !~ /^[0-9]+$/) prob(ln, "job " job " has a timeout-minutes that is not a whole number")
    if (key == "steps" && val != "") prob(ln, HASVAL)
    next
  }
  if (ind == 6 && dashed == 1 && col == 8 && curjk == "steps") {
    endstep(); sn++; instep = 1; subk = ""
    split("", sseen); split("", wseen); split("", eseen)
    S_ln[sn] = ln; S_run[sn] = ""; S_runln[sn] = 0; S_if[sn] = ""; S_ifln[sn] = 0; S_uses[sn] = ""; S_sub[sn] = ""
    S_id[sn] = ""; S_path[sn] = ""; S_pathln[sn] = 0; S_key[sn] = ""; S_keyln[sn] = 0
    if (!bad) stepkey()
    next
  }
  if (ind == 8 && dashed == 0 && instep) { if (!bad) stepkey(); next }
  if (ind == 10 && dashed == 0 && instep && (subk == "with" || subk == "env")) { if (!bad) subkey(); next }
  if (!bad) prob(ln, PLACE)
}

END {
  endsec()
  for (i = 1; i <= 5; i++)
    if (!(tk[i] in topseen)) prob(lastline, "top-level key \"" tk[i] "\" is missing")
}
AWKPROGRAM

    CI_FILE=$file LC_ALL=C awk -f "$tmp/check.awk" "$tmp/expected" "$file" >>"$problems" 2>"$tmp/awkerr"
    status=$?
    if [ "$status" -ne 0 ]; then
      note "$file: the check (awk) exited $status: $(cat "$tmp/awkerr")"
    fi
  fi
fi

count=$(wc -l <"$problems" | tr -d ' ')
if [ "$count" -eq 0 ]; then
  printf 'check-ci: %s has the one shape check-ci reads\n' "$file"
  exit 0
fi
cat "$problems" >&2
printf 'check-ci: FAILED (problems: %s)\n' "$count" >&2
exit 1
