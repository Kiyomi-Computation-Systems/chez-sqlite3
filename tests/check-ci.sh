#!/bin/sh
# check-ci: hold .github/workflows/ci.yml to the one shape this check reads,
# and pages.yml to the copy it holds.
#
#   sh tests/check-ci.sh DIR
#
# DIR must hold ci.yml and pages.yml alone, each a regular file and no link: a
# third workflow would run jobs this check does not read. Its entries are read
# by a glob, so a name that holds a newline is one name, shown with a ? for
# each byte that is not printable ASCII. On a pass it prints one line on stdout
# and exits 0. On a failure it prints each problem on stderr, as "check-ci:
# FILE:LINE: problem", then "check-ci: FAILED (problems: N)", and exits 1. A
# usage error exits 2.
#
# The workflows are read as text, line by line, with awk (POSIX: nothing gawk
# only; CI's Ubuntu runs mawk), and the check fails closed: a spelling that a
# text reader could misread is a problem, whatever it means to YAML. In ci.yml
# it checks:
#
#   - on every line, a comment and a block scalar's content included: a tab,
#     or a character beyond ASCII, which a YAML reader may also take for a
#     line break, so a comment's line could end early and a key follow it.
#     Blank lines hold neither;
#   - on every line that is not a block scalar's content: an explicit key (?),
#     an alias or anchor where a key goes (* or &, then a letter, digit, _ or
#     -: a shell case pattern *) and && are none), a quoted key, white space
#     between a key and its colon, a flow mapping ({ outside a quoted scalar
#     and a ${{ }} expression), a quoted scalar left open, and a backslash after
#     a double quote;
#   - the shape: the top-level keys, the three blocks `on`, `permissions` and
#     `concurrency` line for line, the seven jobs (main, memory-1, memory-2,
#     nothreads, floor, current and site) and each key in them, each
#     step's keys, with: and env: keys, the one if: and where it may be, the
#     cache keys, the checks each job must run, each as one step's whole run
#     line, in order, and the CHEZ each job runs with; in job main, ADR-0002's
#     install check, make build, as one step's whole run line, after its
#     check-chez step and before its make step; and in job main, between its
#     check-chez step and its make step, the steps "Report the versions this
#     run uses" (its run block, line for line) and "Report the runner's
#     SQLite" (its run line, and its env CHEZ), in that order;
#   - in jobs floor and current, which build SQLite and run the suites against
#     it (ADR-0003), and nowhere else: the checkout with submodules first;
#     then, after check-chez, the step that names the compiler (with id: cc),
#     and for each SQLite build the job makes, in turn, the steps that build
#     it (under its own if), check it, run make build (for the job's first
#     build alone) and run make test, each as one step's whole run line, in
#     order. Job floor makes one build, floor; job current makes two, current
#     and then no-load, built without extension loading, so it runs make test
#     twice, the first for current and the second for no-load. Each build's
#     cache has one restore and one save, its path and key held whole, the
#     restore's id held (sqlite, or sqlite-no-load), and the save keyed by
#     that id's cache-primary-key; each build's if, which names that id,
#     stands only on its build and its save, and the Chez cache's if only on
#     the Chez build and save; and the env keys CHEZ_SQLITE3_LIBRARY and
#     C_INCLUDE_PATH, each with exactly its build's value, stand on the steps
#     that run a build's check, make build and make test, each of which must
#     carry both and CHEZ, and on no other step;
#   - in job site, the docs site, on Ubuntu's Chez (ADR-0022): six steps;
#     the checkout with submodules first; the install step second, held line
#     for line, from its first line to the next step's, to the copy below
#     that pages.yml's install step is held to, by the rule pages.yml is held
#     by, so the two cannot drift; then make check-site-deps, make site-deps,
#     make check-site and make site, each one step's whole run line, in that
#     order, each with env CHEZ chezscheme; no step that uses an action but
#     actions/checkout@, so no cache; and no if: on any step, since there is
#     no cache for one to guard;
#   - in every other job: a uses: step may only be actions/checkout@,
#     actions/cache/restore@ or actions/cache/save@; each cache's restore comes
#     before its build, and its save after the build and before the cache's
#     check (a cache is told by its path: the Chez cache's, or a SQLite
#     build's, whose build and check in the lanes are the steps that name its
#     directory); and in the lanes each SQLite restore comes after the step
#     that names the compiler, and a later build's after the make test of the
#     build before it;
#   - every step whose whole run line begins scripts/ci/NAME: that file exists
#     and is executable, under CHECK_CI_ROOT (the repository root if unset);
#     floor.sh is run with sh by the others, so it needs no bit and is not held;
#   - no other line names scripts/, a comment apart: it is a step's whole run
#     line in that form, or a cache key's hashFiles( list;
#   - in jobs memory-1 and memory-2, the memory gate's two shards (ADR-0005):
#     make check-memory-gate, then make test-memory MEMORY_SHARD=1 in memory-1
#     and =2 in memory-2, each one step's whole run line, with no if: on
#     either; so neither job runs the other's shard, and no job runs a third;
#   - the names no line but a comment may hold: GITHUB_ENV, GITHUB_PATH, and
#     as words the variables that would steer a check (MAKEFLAGS, VALGRIND_*,
#     MEMORY_*, ...), the compiler's and the loader's among them (CC,
#     C_INCLUDE_PATH, CPATH, LD_LIBRARY_PATH, LD_PRELOAD), which could steer
#     test-constants or the load, the site's (SITE_REF, CHEZ_CMARK_GFM_LIBS),
#     which could steer the links it writes or the cmark-gfm it loads, and
#     CHECK_CI_ROOT, which would point this check's execute-bit rule at
#     another tree. There are two exceptions. CHEZ_SQLITE3_LIBRARY and
#     C_INCLUDE_PATH may stand as an env key of floor and current, above: job
#     main is the one job that tests discovery, so there, in the memory jobs
#     and in nothreads they stay refused. And MEMORY_SHARD may stand on the
#     one line that runs a memory job's own shard, above, and on no other; and
#   - check-memory-gate, test-memory and check-nothreads anywhere but as the
#     whole run line of a step that runs them: check-memory-gate in either
#     memory job, test-memory only as a memory job's own shard's line, and
#     check-nothreads in job nothreads.
#
# A block scalar starts at a key whose value is | or > and holds every later
# line that is blank or indented deeper than that key (a "- " counts toward the
# key's column). Its lines are text, not YAML structure: a line there that
# begins with # is no comment but the script's text, which GitHub expands and
# the shell runs, so it is held to the rules of the block's other lines (the
# names, the gates and scripts/ among them), and no comment's rule frees it.
#
# pages.yml deploys the site, and needs what that shape refuses: needs:, a
# job's own permissions: and environment:, and two actions beside the
# checkout. It has no part that varies, so it is held to a copy, below: every
# line of it must equal the copy's next line, in order, and the file must end
# where the copy does, but a comment or a blank line (spaces, then # or
# nothing) outside a block scalar's content, which is no part of what GitHub
# runs. A line is a block scalar's content when the copy's next line is, so a
# line the copy's block is cut by is held, or when it is blank or indented
# deeper than the key of a block the file holds open; a blank line there is
# held when content follows it, and dropped, as YAML drops it, when none does.
# A problem names the first held line that differs, and only it. The text
# rules hold on every line of pages.yml, a comment's among them.
#
# Every rule is held by a row of tests/test-check-ci.sps, which plants it in a
# copy of the real workflows. A change to ci.yml or pages.yml changes this file
# with it.

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
pages=$dir/pages.yml

# The site's install step: ci.yml's site job and pages.yml's build job each
# hold it, line for line, so the two cannot drift.
cat >"$tmp/install" <<'INSTALL'
      - name: Install the packages in packaging/debian-site-prereqs.txt
        run: |
          pkgs=$(grep -v -e '^#' -e '^$' packaging/debian-site-prereqs.txt | tr '\n' ' ')
          if [ -z "$pkgs" ]; then
            echo "::error::packaging/debian-site-prereqs.txt yielded no packages: a broken step, not an empty list"
            exit 1
          fi
          sudo apt-get update -qq
          # shellcheck disable=SC2086
          sudo apt-get install -y --no-install-recommends $pkgs
INSTALL

# The copy reader, read by both checks' awk: a text's lines, held to a copy.
cat >"$tmp/copy.awk" <<'AWKPROGRAM'
# indent(s): how many spaces s starts with.
function indent(s,   n) {
  n = 0
  while (substr(s, n + 1, 1) == " ") n++
  return n
}

# keycol(s): the column of s's key: its indent, then each "- " before the key
# and the spaces after it.
function keycol(s,   c, r) {
  c = indent(s); r = substr(s, c + 1)
  while (r == "-" || substr(r, 1, 2) == "- ") {
    r = substr(r, 2); c++
    while (substr(r, 1, 1) == " ") { r = substr(r, 2); c++ }
  }
  return c
}

# opens(s): whether s is a key whose value is | or >, a block scalar.
function opens(s) {
  return (s !~ /^ *#/ && s ~ /: [|>][-+0-9]*( +#.*)?$/)
}

# cpline(s, n): s, line n, is held, and must be the copy's next line. Answers
# 0, having named it, when it is not.
function cpline(s, n) {
  cp_held++
  if (cp_held > cp_nc) {
    prob(n, cp_what " has a line the copy check-ci holds does not: \"" s "\"")
    return 0
  }
  if (s != cpc[cp_held]) {
    prob(n, cp_what " differs from the copy check-ci holds: expected \"" cpc[cp_held] "\", found \"" s "\"")
    return 0
  }
  return 1
}

# cpcheck(nf, nc, what, endn): the text's lines cpf[1..nf], numbered
# cpfl[1..nf], held to the copy cpc[1..nc], as the header says: a comment or
# a blank line outside a block scalar's content is skipped, and every other
# line must be the copy's next. Names the first line that differs, alone, or
# line endn (0: the file) when the text ends first. Answers 1 when it named
# one. what names the text in the problem.
function cpcheck(nf, nc, what, endn,   i, j, s, inc, ccol, inb, col, np, blank) {
  # Which of the copy's lines are a block scalar's content.
  inc = 0
  for (j = 1; j <= nc; j++) {
    cpb[j] = (inc && indent(cpc[j]) > ccol)
    if (!cpb[j]) { inc = opens(cpc[j]); if (inc) ccol = keycol(cpc[j]) }
  }
  cp_held = 0; cp_nc = nc; cp_what = what; inb = 0; np = 0
  for (i = 1; i <= nf; i++) {
    s = cpf[i]; blank = (s ~ /^ *$/)
    # A line indented no deeper than the open block's key ends it, and the
    # blank lines before it are dropped.
    if (inb && !blank && indent(s) <= col) { inb = 0; np = 0 }
    if (!(cp_held < nc && cpb[cp_held + 1]) && (blank || (!inb && s ~ /^ *#/))) {
      if (blank && inb) cppend[++np] = i
      continue
    }
    for (j = 1; j <= np; j++) if (!cpline(cpf[cppend[j]], cpfl[cppend[j]])) return 1
    np = 0
    if (!cpline(s, cpfl[i])) return 1
    if (!cpb[cp_held] && opens(s)) { inb = 1; col = keycol(s) }
  }
  if (cp_held < nc) {
    prob(endn, what " ends early: expected \"" cpc[cp_held + 1] "\"")
    return 1
  }
  return 0
}
AWKPROGRAM

if [ ! -d "$dir" ]; then
  note "$dir: is not a directory"
else
  read_ok=0
  if [ -L "$file" ] || [ ! -f "$file" ]; then
    note "$file: is not a regular file: a link, a directory or nothing there"
  else
    read_ok=1
  fi
  pages_ok=0
  if [ -L "$pages" ] || [ ! -f "$pages" ]; then
    note "$pages: is not a regular file: a link, a directory or nothing there"
  else
    pages_ok=1
  fi
  # Read by a glob, never by lines of ls: a name may hold a newline.
  for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name=${entry##*/}
    case $name in
      ci.yml | pages.yml) ;;
      *)
        shown=$(printf '%s' "$name" | LC_ALL=C tr -c '[:print:]' '[?*]')
        note "$dir: $shown is neither ci.yml nor pages.yml: the directory must hold those two alone" ;;
    esac
  done

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

# ismem(j): whether j is one of the two memory jobs, memory-1 and memory-2.
function ismem(j) { return (j == "memory-1" || j == "memory-2") }

# gaterun(g, j): the one rest of a line that may name gate g in job j, its
# step's whole run line, or "" where no line may name it.
function gaterun(g, j) {
  if (g == "check-memory-gate" && ismem(j)) return "run: make check-memory-gate"
  if (g == "test-memory" && ismem(j)) return "run: " shardrun[j]
  if (g == "check-nothreads" && j == "nothreads") return "run: make check-nothreads"
  return ""
}

# nreq(j): fills rq[1..n] with the run lines job j must run, in order, and in
# a lane rqk[i] and rqb[i] with what each one is (cc, bld, chk, build or
# test) and the SQLite build it is for. A line may be required more than
# once: a lane's make test, once for each build.
function nreq(j,   n, k, b) {
  split("", rqk); split("", rqb)
  if (j == "site") {
    rq[1] = "make check-site-deps"; rq[2] = "make site-deps"; rq[3] = "make check-site"; rq[4] = "make site"
    return 4
  }
  if (j == "main") {
    rq[1] = CHKT; rq[2] = BUILDLINE; rq[3] = MAKELINE; rq[4] = LAUNCHER; return 4
  }
  if (ismem(j)) {
    rq[1] = CHKT; rq[2] = "make check-memory-gate"; rq[3] = shardrun[j]; return 3
  }
  if (isl(j)) {
    n = 1; rq[1] = CHKT
    n++; rq[n] = CCLINE; rqk[n] = "cc"
    for (k = 1; k <= nb[j]; k++) {
      b = jb[j, k]
      n++; rq[n] = lanebld[b]; rqk[n] = "bld"; rqb[n] = b
      n++; rq[n] = lanechk[b]; rqk[n] = "chk"; rqb[n] = b
      if (k == 1) { n++; rq[n] = BUILDLINE; rqk[n] = "build"; rqb[n] = b }
      n++; rq[n] = TESTLINE; rqk[n] = "test"; rqb[n] = b
    }
    return n
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
    S_id[sn] = val; S_idln[sn] = ln
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
    if (key == "key" && !isl(job) && job != "site" && !cachekey_ok(val))
      prob(ln, "the cache key in job " job " does not begin with " prefix[job] "${{ hashFiles(" HASHLIST ") }}")
  } else {
    if (isl(job)) {
      if (!(key in laneenv)) { prob(ln, "env key \"" key "\" is not one of CHEZ, CHEZ_SQLITE3_LIBRARY, C_INCLUDE_PATH"); return }
    } else if (key != "CHEZ") { prob(ln, "env key \"" key "\" is not CHEZ"); return }
    if (key in eseen) { prob(ln, "env key \"" key "\" is written twice in one step"); return }
    eseen[key] = 1; S_env[sn] = 1
    S_ev[sn, key] = 1; S_evln[sn, key] = ln; S_evv[sn, key] = val
    # CHEZ is held here. The two names are held at the job's end, by the
    # build of the step that carries them, which a line can't tell.
    want = chezpath[job]
    if (key == "CHEZ" && val != want) prob(ln, "env " key " in job " job " is not " want)
  }
}

# pathbuild(p): the SQLite build of the lane job whose cache path is p, or "".
function pathbuild(p,   k) {
  for (k = 1; k <= nb[job]; k++) if (p == sqp[jb[job, k]]) return jb[job, k]
  return ""
}

# ifbuild(v): the SQLite build of the lane job whose if is v, or "".
function ifbuild(v,   k) {
  for (k = 1; k <= nb[job]; k++) if (v == ifsql[jb[job, k]]) return jb[job, k]
  return ""
}

# argof(s, script, b): whether step s runs scripts/ci/SCRIPT on build b's
# directory, "$RUNNER_TEMP/sqlite-B", with or without more arguments: the
# step that builds or checks that build's cache, whatever its flag.
function argof(s, script, b,   w, t) {
  w = "run: scripts/ci/" script " \"$RUNNER_TEMP/sqlite-" b "\""
  if (substr(S_run[s], 1, length(w)) != w) return 0
  t = substr(S_run[s], length(w) + 1)
  return (t == "" || substr(t, 1, 1) == " ")
}

# lanestep(): a SQLite lane's if and cache rules, for the step just ended.
function lanestep(   pth, want, id, savep, b) {
  savep = (S_uses[sn] ~ /^actions\/cache\/save@/)
  if (S_if[sn] != "") {
    b = ifbuild(S_if[sn])
    if (S_if[sn] != IFLINE && b == "")
      prob(S_ifln[sn], "if is not one of " lanifs[job])
    else if (S_if[sn] == IFLINE && !(S_run[sn] ~ /^run: scripts\/ci\/build-chez\.sh( |$)/ || (savep && S_path[sn] == CHEZP)))
      prob(S_ifln[sn], "the Chez cache's if is on a step that is neither the Chez build nor the Chez cache's save")
    else if (b != "" && !(argof(sn, "build-sqlite.sh", b) || (savep && S_path[sn] == sqp[b])))
      prob(S_ifln[sn], "the " label[b] " cache's if is on a step that is neither the " label[b] " build nor the " label[b] " cache's save")
  }
  if (!(savep || S_uses[sn] ~ /^actions\/cache\/restore@/)) return
  pth = S_path[sn]
  b = pathbuild(pth)
  if (pth != CHEZP && b == "") {
    prob(S_pathln[sn] ? S_pathln[sn] : S_ln[sn], "the cache path in job " job " is not one of " lanpaths[job])
    return
  }
  id = (pth == CHEZP) ? "chez" : sqid[b]
  if (savep) {
    want = "${{ steps." id ".outputs.cache-primary-key }}"
    if (S_key[sn] != want) prob(S_keyln[sn] ? S_keyln[sn] : S_ln[sn], "the cache key of the save in job " job " is not exactly " want)
  } else if (pth == CHEZP) {
    if (!cachekey_ok(S_key[sn])) prob(S_keyln[sn] ? S_keyln[sn] : S_ln[sn], "the cache key in job " job " does not begin with " prefix[job] "${{ hashFiles(" HASHLIST ") }}")
  } else {
    # The id names the restore's outputs, which the build's if and the save's
    # key read.
    if (S_id[sn] != id) prob(S_idln[sn] ? S_idln[sn] : S_ln[sn], "the " label[b] " cache's restore in job " job " is not id: " id)
    if (S_key[sn] != lanekey[b]) prob(S_keyln[sn] ? S_keyln[sn] : S_ln[sn], "the cache key in job " job " is not exactly " lanekey[b])
  }
}

function endstep() {
  if (!instep) return
  instep = 0
  if (isl(job)) { lanestep(); return }
  if (job == "site") {
    if (S_if[sn] != "") prob(S_ifln[sn], "job site takes no if: it has no cache")
    return
  }
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

# envval(at, k, want): env key k of step at, when it has one, holds want.
function envval(at, k, want) {
  if (((at, k) in S_ev) && S_evv[at, k] != want) prob(S_evln[at, k], "env " k " in job " job " is not " want)
}

# cachekind(s): "Chez" or "SQLite" for a cache restore or save step by its path,
# else "".
function cachekind(s,   pth) {
  if (!(S_uses[s] ~ /^actions\/cache\/(restore|save)@/)) return ""
  pth = S_path[s]
  if (pth ~ /\/chez-(threads|nothreads)$/) return "Chez"
  if (pth ~ /\/sqlite-(floor|current|no-load)$/) return "SQLite"
  return ""
}

# runs(s, what, prog): whether step s runs scripts/ci/WHAT-PROG.sh.
function runs(s, what, prog) {
  return (S_run[s] ~ ("^run: scripts/ci/" what "-" prog "\\.sh( |$)"))
}

# cacheorder(first, last): each cache's restore before its build, its save after
# the build and before its check, and in the lanes each SQLite restore after the
# step that names the compiler, and a later build's after the make test of the
# build before it. In a lane a SQLite cache is a build's, by its path, and its
# build and check are the steps that name that build's directory.
function cacheorder(first, last,   s, t, k, kk, sb, restore, isbld, ischk, pb) {
  for (s = first; s <= last; s++) {
    if (job == "site") {
      if (S_uses[s] != "" && !(S_uses[s] ~ /^actions\/checkout@/))
        prob(S_ln[s], "job site has a step that uses \"" S_uses[s] "\", which is not actions/checkout@: it has no cache")
      continue
    }
    if (S_uses[s] != "" && !(S_uses[s] ~ /^actions\/(checkout|cache\/restore|cache\/save)@/))
      prob(S_ln[s], "job " job " has a step that uses \"" S_uses[s] "\", which is not actions/checkout@, actions/cache/restore@ or actions/cache/save@")
    k = cachekind(s)
    if (k == "") continue
    kk = tolower(k); sb = ""
    if (k == "SQLite" && isl(job)) {
      sb = pathbuild(S_path[s])
      if (sb == "") continue
      k = label[sb]
    }
    restore = (S_uses[s] ~ /^actions\/cache\/restore@/)
    for (t = first; t <= last; t++) {
      isbld = (sb != "") ? argof(t, "build-sqlite.sh", sb) : runs(t, "build", kk)
      ischk = (sb != "") ? argof(t, "check-sqlite.sh", sb) : runs(t, "check", kk)
      if (isbld) {
        if (restore && s > t) prob(S_ln[s], "job " job " restores the " k " cache after the " k " build, and must restore it before")
        if (!restore && s < t) prob(S_ln[s], "job " job " saves the " k " cache before the " k " build, and must save it after")
      }
      if (!restore && ischk && s > t)
        prob(S_ln[s], "job " job " saves the " k " cache after the " k " check, and must save it before")
    }
    if (restore && sb != "" && atrun[CCLINE] && s < atrun[CCLINE])
      prob(S_ln[s], "job " job " restores the " k " cache before the step that names the C compiler, and must restore it after")
    if (restore && sb != "" && bidx[sb] > 1) {
      pb = jb[job, bidx[sb] - 1]
      if (attest[pb] && s < attest[pb])
        prob(S_ln[s], "job " job " restores the " k " cache before the " label[pb] " build's make test, and must restore it after")
    }
  }
}

# sitesteps(first, last): job site holds six steps, and its second is the
# install step, held to the copy from its first line to the line before the
# next step's (or the line that ends the job).
function sitesteps(first, last,   n, a, z, i, k) {
  n = last - first + 1
  if (n != 6) prob(jln, "job site has " n " steps, not six: its checkout, its install step and its four checks")
  if (n < 2) return
  a = S_ln[first + 1]; z = (n >= 3) ? S_ln[first + 2] : endln
  k = 0
  for (i = 1; i <= nsraw; i++)
    if (srawln[i] >= a && srawln[i] < z) { k++; cpf[k] = sraw[i]; cpfl[k] = srawln[i] }
  for (i = 1; i <= ninst; i++) cpc[i] = inst[i]
  cpcheck(k, ninst, "job site's install step", cpfl[k])
}

function endjob(   i, k, s, c, at, pos, lastp, m, x, lastx, first, last, isb, okstep, b, nr, ns) {
  if (job == "") return
  endstep()
  for (i = 1; i <= 4; i++)
    if (!jbad && !(jk2[i] in jkseen)) prob(jln, "job " job " has no key \"" jk2[i] "\"")
  first = jfirst; last = sn; lastp = 0; lastx = "the start"
  if (job == "main" || isl(job) || job == "site") {
    if (first > last || !(S_uses[first] ~ /^actions\/checkout@/ && S_sub[first] == "recursive" && S_run[first] == "" && S_if[first] == ""))
      prob((first <= last) ? S_ln[first] : jln, "job " job "'s first step is not uses: actions/checkout@ with submodules: recursive")
  }
  if (job == "site") sitesteps(first, last)
  if (job == "main") {
    if (first + 1 > last || S_run[first + 1] != "run: " PINRUN)
      prob((first + 1 <= last) ? S_ln[first + 1] : jln, "job main's second step is not run: " PINRUN)
    lastp = 2; lastx = PINRUN
  }
  m = nreq(job)
  # A line required n times must be the run line of n steps, the kth time
  # the kth of them; a problem names it once.
  split("", rqn); split("", oc); split("", hn); split("", hit); split("", okrun); split("", attest)
  for (i = 1; i <= m; i++) rqn[rq[i]]++
  for (s = first; s <= last; s++) {
    x = substr(S_run[s], 6)
    if (substr(S_run[s], 1, 5) == "run: " && (x in rqn)) { hn[x]++; hit[x, hn[x]] = s }
  }
  for (i = 1; i <= m; i++) {
    x = rq[i]; oc[x]++
    if (oc[x] == 1) atrun[x] = 0
    if (rqk[i] == "chk" || rqk[i] == "build" || rqk[i] == "test") okrun["run: " x] = 1
    c = hn[x] + 0
    if (c != rqn[x]) {
      if (oc[x] == 1) prob(jln, "job " job " has " c " steps that run \"" x "\", not " cnt[rqn[x]])
      continue
    }
    at = hit[x, oc[x]]
    if (oc[x] == 1) atrun[x] = at
    pos = at - first + 1
    if (pos <= lastp) prob(S_runln[at], "job " job " runs \"" x "\" before \"" lastx "\", and must run it after")
    else { lastp = pos; lastx = x }
    isb = ((job == "nothreads" && i == 1) || rqk[i] == "bld")
    if (isb) {
      if (S_if[at] == "") prob(S_ln[at], "job " job "'s step that runs \"" x "\" has no if")
    } else if (S_if[at] != "") prob(S_ifln[at], "job " job "'s step that runs \"" x "\" has an if")
    if (job == "site") needenv(at, x, "CHEZ")
    if (isl(job)) {
      k = rqk[i]; b = rqb[i]
      if (k == "cc" && S_id[at] != "cc") prob(S_ln[at], "job " job "'s step that runs \"" x "\" has no id: cc")
      if (k == "bld" || k == "chk" || k == "build" || k == "test") needenv(at, x, "CHEZ")
      if (k == "chk" || k == "build" || k == "test") {
        needenv(at, x, "CHEZ_SQLITE3_LIBRARY"); needenv(at, x, "C_INCLUDE_PATH")
        envval(at, "CHEZ_SQLITE3_LIBRARY", lanelib[b]); envval(at, "C_INCLUDE_PATH", laneinc[b])
      }
      if (k == "test") attest[b] = at
    }
  }
  cacheorder(first, last)
  if (isl(job)) {
    # Each build's cache: one restore and one save.
    for (k = 1; k <= nb[job]; k++) {
      b = jb[job, k]; nr = 0; ns = 0
      for (s = first; s <= last; s++) {
        if (S_path[s] != sqp[b]) continue
        if (S_uses[s] ~ /^actions\/cache\/restore@/) nr++
        if (S_uses[s] ~ /^actions\/cache\/save@/) ns++
      }
      if (nr != 1) prob(jln, "job " job " has " nr " restores of the " label[b] " cache, not one")
      if (ns != 1) prob(jln, "job " job " has " ns " saves of the " label[b] " cache, not one")
    }
    # The two names are for the steps that run a build's check, make build and
    # make test, and for no other step of the lane.
    for (s = first; s <= last; s++) {
      okstep = (S_run[s] in okrun)
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
    for (i = 1; i <= 7; i++)
      if (!(jn[i] in jobseen)) prob(jobsln, "job \"" jn[i] "\" is missing")
  sec = ""
}

BEGIN {
  F = ENVIRON["CI_FILE"]
  for (i = 32; i < 127; i++) ascii = ascii sprintf("%c", i)
  # The site's install step, which its job's second step must be.
  INSTF = ENVIRON["INSTALL_FILE"]
  while ((getline l < INSTF) > 0) inst[++ninst] = l
  close(INSTF)
  TABMSG = "holds a tab, which YAML may read as white space beside a key"
  ODDMSG = "holds a character beyond ASCII, which GitHub may fold into a key's letters"
  TOPS = "name, on, permissions, concurrency, jobs"
  split("name on permissions concurrency jobs", tk, " ")
  for (i = 1; i <= 5; i++) topidx[tk[i]] = i
  isblock["on"] = 1; isblock["permissions"] = 1; isblock["concurrency"] = 1
  JOBS = "main, memory-1, memory-2, nothreads, floor, current, site"
  split("main memory-1 memory-2 nothreads floor current site", jn, " ")
  for (i = 1; i <= 7; i++) wantjob[jn[i]] = 1
  JOBKEYS = "name, runs-on, timeout-minutes, steps"
  split("name runs-on timeout-minutes steps", jk2, " ")
  for (i = 1; i <= 4; i++) jobkey[jk2[i]] = 1
  STEPKEYS = "name, id, uses, with, run, env, if"
  split("name id uses with run env if", sk, " ")
  for (i = 1; i <= 7; i++) stepkeys[sk[i]] = 1
  WITHKEYS = "submodules, path, key"
  split("submodules path key", wk, " ")
  for (i = 1; i <= 3; i++) withkeys[wk[i]] = 1
  gname[1] = "check-memory-gate"; gname[2] = "test-memory"; gname[3] = "check-nothreads"
  shardrun["memory-1"] = "make test-memory MEMORY_SHARD=1"
  shardrun["memory-2"] = "make test-memory MEMORY_SHARD=2"
  nbw = split("MAKEFLAGS MFLAGS GNUMAKEFLAGS VALGRIND MEMORY_SUITES MEMORY_TIMEOUT TEST_TIMEOUT LIBDIRS TIMEOUT SUITES CHEZ_SQLITE3_LIBRARY CHEZ_SQLITE3_DECOY CHEZ_SQLITE3_GATE_CHILD CC C_INCLUDE_PATH CPATH LD_LIBRARY_PATH LD_PRELOAD CHECK_CI_ROOT SITE_REF CHEZ_CMARK_GFM_LIBS", bw, " ")
  for (i = 1; i <= nbw; i++) banned[bw[i]] = 1
  HASHLIST = "'packaging/floors.sexp', 'scripts/ci/floor.sh', 'scripts/ci/build-chez.sh', 'scripts/ci/check-chez.sh'"
  IFLINE = "if: steps.chez.outputs.cache-hit != 'true'"
  TESTLINE = "make test"
  CHEZP = "${{ runner.temp }}/chez-threads"
  CCLINE = "echo \"id=$(cc --version | head -n 1 | tr -c '[:alnum:].' '-')\" >> \"$GITHUB_OUTPUT\""
  # The SQLite builds, each by its name, and the lanes that make them, in
  # order: floor makes floor, and current makes current, then no-load.
  # A build's tables are keyed by its name, never its job's.
  laneflag["floor"] = ""; laneflag["current"] = " --current"; laneflag["no-load"] = " --no-load"
  lanehash["floor"] = "'packaging/floors.sexp', 'scripts/ci/floor.sh', 'scripts/ci/build-sqlite.sh', 'scripts/ci/check-sqlite.sh'"
  lanehash["current"] = "'scripts/ci/build-sqlite.sh', 'scripts/ci/check-sqlite.sh'"
  lanehash["no-load"] = lanehash["current"]
  sqid["floor"] = "sqlite"; sqid["current"] = "sqlite"; sqid["no-load"] = "sqlite-no-load"
  label["floor"] = "SQLite"; label["current"] = "SQLite"; label["no-load"] = "no-load SQLite"
  nbl = split("floor current no-load", lj, " ")
  for (i = 1; i <= nbl; i++) {
    b = lj[i]
    sqp[b] = "${{ runner.temp }}/sqlite-" b
    lanelib[b] = sqp[b] "/lib/libsqlite3.so.0"
    laneinc[b] = sqp[b] "/include"
    lanebld[b] = "scripts/ci/build-sqlite.sh \"$RUNNER_TEMP/sqlite-" b "\"" laneflag[b]
    lanechk[b] = "scripts/ci/check-sqlite.sh \"$RUNNER_TEMP/sqlite-" b "\"" laneflag[b]
    lanekey[b] = "sqlite-" b "-${{ hashFiles(" lanehash[b] ") }}-${{ steps.image.outputs.id }}-${{ steps.cc.outputs.id }}"
    ifsql[b] = "if: steps." sqid[b] ".outputs.cache-hit != 'true'"
  }
  nb["floor"] = 1; jb["floor", 1] = "floor"; bidx["floor"] = 1
  nb["current"] = 2; jb["current", 1] = "current"; bidx["current"] = 1
  jb["current", 2] = "no-load"; bidx["no-load"] = 2
  # What a lane's problems list: the ifs it may hold, and the cache paths.
  split("floor current", lj, " ")
  for (i = 1; i <= 2; i++) {
    j = lj[i]
    lanifs[j] = "\"" IFLINE "\""; lanpaths[j] = CHEZP
    for (k = 1; k <= nb[j]; k++) {
      sep = (k == nb[j]) ? " or " : ", "
      lanifs[j] = lanifs[j] sep "\"" ifsql[jb[j, k]] "\""
      lanpaths[j] = lanpaths[j] sep sqp[jb[j, k]]
    }
  }
  cnt[1] = "one"; cnt[2] = "two"
  laneenv["CHEZ"] = 1; laneenv["CHEZ_SQLITE3_LIBRARY"] = 1; laneenv["C_INCLUDE_PATH"] = 1
  PINRUN = "scripts/ci/check-action-pins.sh .github/workflows"
  CHKT = "scripts/ci/check-chez.sh \"$RUNNER_TEMP/chez-threads\""
  CHKN = "scripts/ci/check-chez.sh \"$RUNNER_TEMP/chez-nothreads\" --nothreads"
  BLDN = "scripts/ci/build-chez.sh \"$RUNNER_TEMP/chez-nothreads\" --nothreads"
  BUILDLINE = "make build"
  MAKELINE = "make check-help check-suites check-pins check-floors check-ci test check-test-fails check-variadic check-dev check-clean"
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
  chezpath["memory-1"] = chezpath["main"]; chezpath["memory-2"] = chezpath["main"]
  chezpath["nothreads"] = "${{ runner.temp }}/chez-nothreads/bin/scheme"
  chezpath["floor"] = chezpath["main"]; chezpath["current"] = chezpath["main"]
  chezpath["site"] = "chezscheme"
  prefix["main"] = "chez-threads-"; prefix["memory-1"] = "chez-threads-"; prefix["memory-2"] = "chez-threads-"
  prefix["nothreads"] = "chez-nothreads-"
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
  ln = FNR; lastline = FNR; raw = $0; endln = ln
  # Every line of job site, a blank or a comment one among them: its install
  # step is held whole, at the job's end.
  if (job == "site") { nsraw++; sraw[nsraw] = raw; srawln[nsraw] = ln }
  if (raw ~ /^ *$/) next
  ind = 0
  while (substr(raw, ind + 1, 1) == " ") ind++
  content = 0
  if (inblock) { if (ind > blockcol) content = 1; else inblock = 0 }
  if (content && instep) { bn[sn]++; bl[sn, bn[sn]] = raw; bln[sn, bn[sn]] = ln }
  # A comment's line is held to the text rules, and to nothing else. A line of
  # a block scalar's content that begins with # is no comment: it goes on.
  if (!content && substr(raw, ind + 1, 1) == "#") {
    if (index(raw, "\t") > 0) prob(ln, TABMSG)
    if (odd(raw)) prob(ln, ODDMSG)
    next
  }

  bad = 0
  if (index(raw, "\t") > 0) { prob(ln, TABMSG); bad = 1 }
  if (odd(raw)) { prob(ln, ODDMSG); bad = 1 }

  rest = ""; col = ind; dashed = 0
  if (!content) {
    rest = substr(raw, ind + 1)
    while (rest == "-" || substr(rest, 1, 2) == "- ") {
      dashed++; rest = substr(rest, 2); col++
      while (substr(rest, 1, 1) == " ") { rest = substr(rest, 2); col++ }
    }
  }

  # The names no line but a comment may hold, a block scalar's content
  # included.
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
  # The other: MEMORY_SHARD, on the one line that runs a memory job's own
  # shard. Its number is that line's argument, and no other line's.
  shardok = (!content && ismem(job) && rest == "run: " shardrun[job])
  w = raw; gsub(/[^A-Za-z0-9_]+/, " ", w)
  nw = split(w, ws, " "); split("", seen)
  for (k = 1; k <= nw; k++) {
    x = ws[k]
    if (k == 1 && ealk != "" && x == ealk) continue
    if (shardok && x == "MEMORY_SHARD") continue
    if (!(x in seen) && ((x in banned) || x ~ /^VALGRIND_/ || x ~ /^MEMORY_/)) {
      seen[x] = 1
      prob(ln, "names " x ", which could steer a check or a later step")
    }
  }
  for (g = 1; g <= 3; g++)
    if (index(raw, gname[g]) > 0 && !(!content && (gr = gaterun(gname[g], job)) != "" && rest == gr))
      prob(ln, "names " gname[g] " other than as the whole run line of the one step that runs it")

  # The shell's rule for scripts/, after this program, reads no line that
  # begins with #: here, a block scalar's line that does.
  if (content && substr(raw, ind + 1, 1) == "#" && index(raw, "scripts/") > 0)
    prob(ln, "names scripts/ other than as a step's whole run line of scripts/ci/ or a cache key's hashed files")

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
    S_id[sn] = ""; S_idln[sn] = 0; S_path[sn] = ""; S_pathln[sn] = 0; S_key[sn] = ""; S_keyln[sn] = 0
    if (!bad) stepkey()
    next
  }
  if (ind == 8 && dashed == 0 && instep) { if (!bad) stepkey(); next }
  if (ind == 10 && dashed == 0 && instep && (subk == "with" || subk == "env")) { if (!bad) subkey(); next }
  if (!bad) prob(ln, PLACE)
}

END {
  endln = lastline + 1
  endsec()
  for (i = 1; i <= 5; i++)
    if (!(tk[i] in topseen)) prob(lastline, "top-level key \"" tk[i] "\" is missing")
}
AWKPROGRAM

    CI_FILE=$file INSTALL_FILE=$tmp/install LC_ALL=C awk -f "$tmp/copy.awk" -f "$tmp/check.awk" \
      "$tmp/expected" "$file" >>"$problems" 2>"$tmp/awkerr"
    status=$?
    if [ "$status" -ne 0 ]; then
      note "$file: the check (awk) exited $status: $(cat "$tmp/awkerr")"
    fi

    # A step whose whole run line begins scripts/ci/NAME runs that file by its
    # path, so the file must be there and carry the execute bit: a runner
    # fails the step otherwise, and nothing else here would see it. The files
    # are read under CHECK_CI_ROOT, which is the repository root when unset
    # (tests/test-check-ci.sps points it at a copy). scripts/ci/floor.sh is
    # no such step's script: the other scripts run it with sh, so it needs no
    # bit and is not held.
    root=${CHECK_CI_ROOT:-$(dirname "$0")/..}
    grep -n -E '^( {8}| {6}- )run: scripts/ci/[A-Za-z0-9._-]+( |$)' "$file" >"$tmp/runs" || :
    while IFS= read -r entry; do
      lineno=${entry%%:*}
      cmd=${entry#*run: }
      name=${cmd%% *}
      if [ ! -f "$root/$name" ] || [ ! -x "$root/$name" ]; then
        note "$file:$lineno: runs $name, which is missing or not executable: a step runs it by its path, so it must be there and carry the execute bit"
      fi
    done <"$tmp/runs"

    # The rule above reads one spelling of a step that runs a script of
    # scripts/ci/. A line that names scripts/ci/ in any other spelling (a
    # quoted path, a block scalar, ./scripts/ci/, scripts/ci//, a path with a
    # slash after the directory, a command after the name, or a path to the
    # directory that holds no scripts/ci/, such as scripts/./ci/) would run a
    # script the rule never held, so it is a problem itself: bar a comment, a
    # line of the workflow that names scripts/ is a step's whole run line, in
    # the form the rule reads, or a cache key's hashFiles( list.
    grep -n 'scripts/' "$file" |
      grep -v -E '^[0-9]+: *#' |
      grep -v -E '^[0-9]+:( {8}| {6}- )run: scripts/ci/[A-Za-z0-9._-]+( |$)' |
      grep -v -E '^[0-9]+: +key: .*hashFiles\(' >"$tmp/stray" || :
    while IFS= read -r entry; do
      lineno=${entry%%:*}
      note "$file:$lineno: names scripts/ other than as a step's whole run line of scripts/ci/ or a cache key's hashed files"
    done <"$tmp/stray"
  fi

  # pages.yml: every line, line for line and in order, is the copy here, but a
  # comment or a blank one outside a block scalar's content, and every line of
  # it keeps the text rules. The copy's install step is the site job's.
  if [ "$pages_ok" -eq 1 ]; then
    {
      cat <<'PAGES_HEAD'
name: Pages
on:
  push:
    tags: ["v*"]
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: pages
  cancel-in-progress: false
jobs:
  build:
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
          submodules: recursive
PAGES_HEAD
      cat "$tmp/install"
      cat <<'PAGES_TAIL'
      - name: Get chez-cmark-gfm as Akku.lock pins it
        env:
          CHEZ: chezscheme
        run: make site-deps
      - name: Gate the site
        env:
          CHEZ: chezscheme
          SITE_REF: ${{ github.ref_name }}
        run: make check-site
      - name: Build the site
        env:
          CHEZ: chezscheme
          SITE_REF: ${{ github.ref_name }}
        run: make site
      - uses: actions/upload-pages-artifact@fc324d3547104276b827a68afc52ff2a11cc49c9 # v5.0.0
        with:
          path: build/site
  deploy:
    needs: build
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    permissions:
      pages: write
      id-token: write
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@368f82528645a54fb793d4d04e342629a3f51346 # v5.0.1
PAGES_TAIL
    } >"$tmp/pages"

    cat >"$tmp/pages.awk" <<'AWKPROGRAM'
# prob(n, m): a problem on line n, or on the file when n is 0.
function prob(n, m) {
  if (n > 0) printf "check-ci: %s:%d: %s\n", F, n, m
  else printf "check-ci: %s: %s\n", F, m
}

# odd(s): whether s holds a byte that is not printable ASCII (a tab apart).
function odd(s,   i, n, c) {
  n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c != "\t" && index(ascii, c) == 0) return 1
  }
  return 0
}

BEGIN {
  F = ENVIRON["PAGES_FILE"]
  for (i = 32; i < 127; i++) ascii = ascii sprintf("%c", i)
  last = 0; nc = 0; nf = 0
}

FNR == 1 { fileno++ }

# The first file: the copy.
fileno == 1 { cpc[++nc] = $0; next }

# The second file: pages.yml, every line held to the text rules, and kept.
{
  last = FNR
  if (index($0, "\t") > 0) prob(FNR, "holds a tab, which YAML may read as white space beside a key")
  if (odd($0)) prob(FNR, "holds a character beyond ASCII, which GitHub may fold into a key's letters")
  cpf[++nf] = $0; cpfl[nf] = FNR
}

END { cpcheck(nf, nc, "pages.yml", last) }
AWKPROGRAM

    PAGES_FILE=$pages LC_ALL=C awk -f "$tmp/copy.awk" -f "$tmp/pages.awk" "$tmp/pages" "$pages" \
      >>"$problems" 2>"$tmp/awkerr"
    status=$?
    if [ "$status" -ne 0 ]; then
      note "$pages: the check (awk) exited $status: $(cat "$tmp/awkerr")"
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
