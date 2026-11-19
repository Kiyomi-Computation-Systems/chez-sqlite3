#!/usr/bin/env python3
"""M4's closing review, builder E1 (the no-load CI lane): the plants.

Each plant is a copy of the worktree under build/e1/plants/NAME, made
without .git, build/ and .plans/, with a list of edits, each checked to
match its file's text exactly once before it is written, and the suite it
must fail. It writes build/e1/plants/NAME/RUN.sh, which the container runs
from the worktree's root: make deps in the copy, then the suite under
timeout 300, by Chez directly, since make test would stop at check-ci, a
prerequisite, before the suite.

  python3 -I plants.py WORKTREE [NAME ...]

The rows a plant fails are read from the suite's FAIL lines and counts by
summarize.py, never by eye.
"""
import os, shutil, subprocess, sys

WT = sys.argv[1]
ONLY = set(sys.argv[2:])

CCI = 'tests/check-ci.sh'
TCI = 'tests/test-check-ci.sps'
BLD = 'scripts/ci/build-sqlite.sh'
CHK = 'scripts/ci/check-sqlite.sh'
TCS = 'tests/test-ci-sqlite.sps'

P = []


def plant(name, guards, edits, suite):
    P.append((name, guards, edits, suite))


# --- check-ci.sh: each new rule taken out ------------------------------------
plant('C01', "the no-load build's run line is required (only the first build's)",
      [(CCI, '      n++; rq[n] = lanebld[b]; rqk[n] = "bld"; rqb[n] = b\n',
        '      if (k == 1) { n++; rq[n] = lanebld[b]; rqk[n] = "bld"; rqb[n] = b }\n')], TCI)
plant('C02', "the no-load check's run line is required (only the first build's)",
      [(CCI, '      n++; rq[n] = lanechk[b]; rqk[n] = "chk"; rqb[n] = b\n',
        '      if (k == 1) { n++; rq[n] = lanechk[b]; rqk[n] = "chk"; rqb[n] = b }\n')], TCI)
plant('C03', "a line required n times is run by n steps (n or more)",
      [(CCI, '    if (c != rqn[x]) {', '    if (c < rqn[x]) {')], TCI)
plant('C04', "the kth time a line is required is its kth step (always the first)",
      [(CCI, '    at = hit[x, oc[x]]\n', '    at = hit[x, 1]\n')], TCI)
plant('C05', "each build's env values are held (the second build's not)",
      [(CCI, '        envval(at, "CHEZ_SQLITE3_LIBRARY", lanelib[b]); envval(at, "C_INCLUDE_PATH", laneinc[b])\n',
        '        if (bidx[b] == 1) { envval(at, "CHEZ_SQLITE3_LIBRARY", lanelib[b]); envval(at, "C_INCLUDE_PATH", laneinc[b]) }\n')], TCI)
plant('C06', "each build's env values are held (none)",
      [(CCI, '        envval(at, "CHEZ_SQLITE3_LIBRARY", lanelib[b]); envval(at, "C_INCLUDE_PATH", laneinc[b])\n', '')], TCI)
plant('C07', "the second build's steps must carry the two names (not held)",
      [(CCI, '        needenv(at, x, "CHEZ_SQLITE3_LIBRARY"); needenv(at, x, "C_INCLUDE_PATH")\n',
        '        if (bidx[b] == 1) { needenv(at, x, "CHEZ_SQLITE3_LIBRARY"); needenv(at, x, "C_INCLUDE_PATH") }\n')], TCI)
plant('C08', "the second build's steps must carry CHEZ (not held)",
      [(CCI, '      if (k == "bld" || k == "chk" || k == "build" || k == "test") needenv(at, x, "CHEZ")\n',
        '      if ((k == "bld" || k == "chk" || k == "build" || k == "test") && bidx[b] == 1) needenv(at, x, "CHEZ")\n')], TCI)
plant('C09', "a build's if stands on the step that names its directory (on any build-sqlite.sh step, as before)",
      [(CCI, '    else if (b != "" && !(argof(sn, "build-sqlite.sh", b) || (savep && S_path[sn] == sqp[b])))',
        '    else if (b != "" && !(S_run[sn] ~ /^run: scripts\\/ci\\/build-sqlite\\.sh( |$)/ || (savep && S_path[sn] == sqp[b])))')], TCI)
plant('C10', "a build's if stands on its own save (on any save)",
      [(CCI, '    else if (b != "" && !(argof(sn, "build-sqlite.sh", b) || (savep && S_path[sn] == sqp[b])))',
        '    else if (b != "" && !(argof(sn, "build-sqlite.sh", b) || savep))')], TCI)
plant('C11', "the second build's step has its if (not held)",
      [(CCI, '      if (S_if[at] == "") prob(S_ln[at], "job " job "\'s step that runs \\"" x "\\" has no if")',
        '      if (S_if[at] == "" && rqb[i] != "no-load") prob(S_ln[at], "job " job "\'s step that runs \\"" x "\\" has no if")')], TCI)
plant('C12', "a SQLite restore's id is held (not held)",
      [(CCI, '    if (S_id[sn] != id) prob(', '    if (0) prob(')], TCI)
plant('C13', "the second build's restore key is held (not held)",
      [(CCI, '    if (S_key[sn] != lanekey[b]) prob(', '    if (S_key[sn] != lanekey[b] && bidx[b] == 1) prob(')], TCI)
plant('C14', "a save is keyed by its own restore's id (or by sqlite's)",
      [(CCI, '    if (S_key[sn] != want) prob(S_keyln[sn] ? S_keyln[sn] : S_ln[sn], "the cache key of the save',
        '    if (S_key[sn] != want && S_key[sn] != "${{ steps.sqlite.outputs.cache-primary-key }}") prob(S_keyln[sn] ? S_keyln[sn] : S_ln[sn], "the cache key of the save')], TCI)
plant('C15', "each build's cache has one restore (not counted)",
      [(CCI, '      if (nr != 1) prob(', '      if (0) prob(')], TCI)
plant('C16', "each build's cache has one save (not counted)",
      [(CCI, '      if (ns != 1) prob(', '      if (0) prob(')], TCI)
plant('C17', "the second build's cache is held in order (skipped)",
      [(CCI, '      sb = pathbuild(S_path[s])\n      if (sb == "") continue\n',
        '      sb = pathbuild(S_path[s])\n      if (sb == "" || bidx[sb] > 1) continue\n')], TCI)
plant('C18', "a later build's restore comes after the build before it's make test (not held)",
      [(CCI, '      if (attest[pb] && s < attest[pb])', '      if (0)')], TCI)
plant('C19', "each build's restore comes after the compiler step (the first build's only)",
      [(CCI, '    if (restore && sb != "" && atrun[CCLINE] && s < atrun[CCLINE])',
        '    if (restore && sb != "" && bidx[sb] == 1 && atrun[CCLINE] && s < atrun[CCLINE])')], TCI)
plant('C20', "the two names stand only on the steps of a build's check, make build and make test (on any step after the first make test)",
      [(CCI, '      okstep = (S_run[s] in okrun)\n',
        '      okstep = ((S_run[s] in okrun) || (attest[jb[job, 1]] && s > attest[jb[job, 1]]))\n')], TCI)
plant('C21', "a lane's cache paths are its own builds' (any build's)",
      [(CCI, 'function pathbuild(p,   k) {\n', 'function pathbuild(p,   k) {\n  if (p == sqp["no-load"]) return "no-load"\n')], TCI)
plant('C22', "a lane's ifs are its own builds' (any build's)",
      [(CCI, 'function ifbuild(v,   k) {\n', 'function ifbuild(v,   k) {\n  if (v == ifsql["no-load"]) return "no-load"\n')], TCI)
plant('C23', "an out-of-order line is named against the last line in order (the line required before it)",
      [(CCI, '    else { lastp = pos; lastx = x }\n', '    else lastp = pos\n    lastx = x\n')], TCI)
plant('C24', "a line required twice says not two (not one)",
      [(CCI, 'cnt[1] = "one"; cnt[2] = "two"', 'cnt[1] = "one"; cnt[2] = "one"')], TCI)
plant('C25', "current's problems list its three ifs and three paths (with or between each)",
      [(CCI, '      sep = (k == nb[j]) ? " or " : ", "', '      sep = " or "')], TCI)
plant('C26', "a no-load cache is a SQLite cache (the old path pattern)",
      [(CCI, '  if (pth ~ /\\/sqlite-(floor|current|no-load)$/) return "SQLite"',
        '  if (pth ~ /\\/sqlite-(floor|current)$/) return "SQLite"')], TCI)
plant('C27', "a step names a build's directory only when nothing but a space follows it (anything may)",
      [(CCI, '  return (t == "" || substr(t, 1, 1) == " ")\n', '  return 1\n')], TCI)
plant('C28', "CHEZ is held at its line (not held)",
      [(CCI, '    if (key == "CHEZ" && val != want) prob(', '    if (0) prob(')], TCI)

plant('C29', "the Chez cache's if stands only on the Chez build and save, in a lane (anywhere)",
      [(CCI, '    else if (S_if[sn] == IFLINE && !(S_run[sn] ~ /^run: scripts\\/ci\\/build-chez\\.sh( |$)/ || (savep && S_path[sn] == CHEZP)))',
        '    else if (0)')], TCI)
plant('C30', "the second build's save is keyed exactly (not held)",
      [(CCI, '    if (S_key[sn] != want) prob(S_keyln[sn] ? S_keyln[sn] : S_ln[sn], "the cache key of the save',
        '    if (S_key[sn] != want && b != "no-load") prob(S_keyln[sn] ? S_keyln[sn] : S_ln[sn], "the cache key of the save')], TCI)
plant('C31', "the second build's check is counted (its count not told)",
      [(CCI, '      if (oc[x] == 1) prob(jln, "job " job " has " c " steps',
        '      if (oc[x] == 1 && !(rqk[i] == "chk" && bidx[rqb[i]] > 1)) prob(jln, "job " job " has " c " steps')], TCI)
plant('C32', "every job is there (current not held)",
      [(CCI, '    for (i = 1; i <= 6; i++)\n      if (!(jn[i] in jobseen))', '    for (i = 1; i <= 5; i++)\n      if (!(jn[i] in jobseen))')], TCI)
plant('C33', "no job but the six (any job)",
      [(CCI, '    if (!(key in wantjob)) { prob(ln,', '    if (0) { prob(ln,')], TCI)
plant('C34', "every step that runs a script by its path is read for its execute bit (the first 560 lines only)",
      [(CCI, "    grep -n -E '^( {8}| {6}- )run: scripts/ci/[A-Za-z0-9._-]+( |$)' \"$file\" >\"$tmp/runs\" || :",
        "    head -n 560 \"$file\" | grep -n -E '^( {8}| {6}- )run: scripts/ci/[A-Za-z0-9._-]+( |$)' >\"$tmp/runs\" || :")], TCI)
plant('C35', "C_INCLUDE_PATH is a name no line may hold (it may)",
      [(CCI, 'CHEZ_SQLITE3_GATE_CHILD CC C_INCLUDE_PATH CPATH', 'CHEZ_SQLITE3_GATE_CHILD CC CPATH')], TCI)

# --- the scripts' --no-load ----------------------------------------------------
plant('S01', "check --no-load holds the no-load list (current's)",
      [(CHK, "  no-load) no_load_options | sed '/^$/d' >\"$work/expected\" ;;",
        "  no-load) current_options | sed '/^$/d' >\"$work/expected\" ;;")], TCS)
plant('S02', "check --current holds current's list (the no-load one)",
      [(CHK, "  current) current_options | sed '/^$/d' >\"$work/expected\" ;;",
        "  current) no_load_options | sed '/^$/d' >\"$work/expected\" ;;")], TCS)
plant('S03', "check --no-load names its own role (current's)",
      [(CHK, '    what="the pinned no-load SQLite" ;;', '    what="the pinned current SQLite" ;;')], TCS)
plant('S04', "check --no-load holds the current release's identity (the floor's source id)",
      [(CHK, '  no-load)\n    version=$current_version\n    source_id=$current_source_id\n',
        '  no-load)\n    version=$current_version\n    source_id=$floor_source_id\n')], TCS)
plant('S05', "check --no-load's list holds OMIT_LOAD_EXTENSION (dropped)",
      [(CHK, 'MUTEX_PTHREADS\nOMIT_LOAD_EXTENSION\nSYSTEM_MALLOC\n', 'MUTEX_PTHREADS\nSYSTEM_MALLOC\n')], TCS)
plant('S06', "check takes --no-load alone (--noload too)",
      [(CHK, '    --no-load) role=no-load ;;', '    --no-load|--noload) role=no-load ;;')], TCS)
plant('S07', "build --no-load compiles without extension loading (the flag dropped)",
      [(BLD, ' -DSQLITE_ENABLE_FTS5 -DSQLITE_OMIT_LOAD_EXTENSION \\', ' -DSQLITE_ENABLE_FTS5 \\')], TCS)
plant('S08', "build --no-load keeps FTS5 (dropped)",
      [(BLD, ' -DSQLITE_ENABLE_FTS5 -DSQLITE_OMIT_LOAD_EXTENSION \\', ' -DSQLITE_OMIT_LOAD_EXTENSION \\')], TCS)
plant('S09', "build --no-load checks with --no-load (--current)",
      [(BLD, '  *) set -- "$prefix" "--$role" ;;', '  *) set -- "$prefix" --current ;;')], TCS)
plant('S10', "build --no-load names the current release's pins (by its role, no-load_archive)",
      [(BLD, '  fail "$name.tar.gz has SHA3-256 $got, but ${pins}_archive', '  fail "$name.tar.gz has SHA3-256 $got, but ${role}_archive'),
       (BLD, '  fail "$name/sqlite3.c has SHA3-256 $got, but ${pins}_source', '  fail "$name/sqlite3.c has SHA3-256 $got, but ${role}_source')], TCS)
plant('S11', "build --no-load builds the current release (the floor, by floors.sexp)",
      [(BLD, 'if [ "$role" = floor ]; then\n  pins=floor\n', 'if [ "$role" != current ]; then\n  pins=floor\n')], TCS)
plant('S12', "build --no-load's download failure names the current release's pins (the floor's)",
      [(BLD, '  if [ "$pins" = current ]; then', '  if [ "$role" = current ]; then')], TCS)
plant('S13', "build takes --no-load alone (--noload too)",
      [(BLD, '    --no-load) role=no-load ;;', '    --no-load|--noload) role=no-load ;;')], TCS)
plant('S14', "the suite's no-load copy holds OMIT_LOAD_EXTENSION (dropped from the copy)",
      [(TCS, '     "MUTEX_PTHREADS"\n     "OMIT_LOAD_EXTENSION"\n', '     "MUTEX_PTHREADS"\n')], TCS)
plant('S15', "the suite's no-load copy is current's and one line (a second extra line)",
      [(TCS, '     "OMIT_LOAD_EXTENSION"\n', '     "OMIT_LOAD_EXTENSION"\n     "OMIT_SHARED_CACHE"\n'),
       (CHK, 'OMIT_LOAD_EXTENSION\nSYSTEM_MALLOC\n', 'OMIT_LOAD_EXTENSION\nOMIT_SHARED_CACHE\nSYSTEM_MALLOC\n')], TCS)

ROOT = os.path.join(WT, 'build', 'e1', 'plants')
os.makedirs(ROOT, exist_ok=True)
for name, guards, edits, suite in P:
    if ONLY and name not in ONLY:
        continue
    dst = os.path.join(ROOT, name)
    if os.path.exists(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    # The tree, without .git, build/ and .plans/.
    subprocess.run(['tar', '-C', WT, '--exclude=./.git', '--exclude=./build', '--exclude=./.plans',
                    '-cf', os.path.join(ROOT, name + '.tar'), '.'], check=True)
    subprocess.run(['tar', '-C', dst, '-xf', os.path.join(ROOT, name + '.tar')], check=True)
    os.remove(os.path.join(ROOT, name + '.tar'))
    for f, old, new in edits:
        path = os.path.join(dst, f)
        text = open(path).read()
        n = text.count(old)
        if n != 1:
            sys.exit(f'{name}: {f}: the old text occurs {n} times, not once: {old!r}')
        open(path, 'w').write(text.replace(old, new))
    with open(os.path.join(dst, 'RUN.sh'), 'w') as r:
        r.write('# ' + name + ': ' + guards + '\n')
        r.write('cd "$1/build/e1/plants/' + name + '" || exit 1\n')
        r.write('make deps >/dev/null || exit 1\n')
        r.write('echo "=== ' + suite + '"\n')
        r.write('timeout 300 "$CHEZ" --libdirs src:tests:build/scheme-libs --program ' + suite + '\n')
        r.write('echo "exit $?"\n')
    print(name, guards)
