#!/bin/sh
# run-mutants.sh: inside the container, from the worktree's root. Runs each
# mutant's suites and make targets in its own copy, build/mut/NAME, and
# prints one line per run: NAME WHAT exit N passes P failures F TIME.
# A mutant's .env, when there is one, is sourced first. Arguments: the
# mutants' names; none for every one with a .mutant file.
cd build/mut3 || exit 1
names=$*
[ -n "$names" ] || names=$(for d in */; do [ -f "$d.mutant" ] && printf '%s ' "${d%/}"; done)
for name in $names; do
  (
    cd "$name" || exit 0
    [ -f .env ] && . ./.env
    make deps >/dev/null 2>&1
    suites=$(sed -n 1p .mutant)
    targets=$(sed -n 2p .mutant)
    for s in $suites; do
      log=../logs/$name.$(basename "$s" .sps).log
      start=$(date +%s)
      timeout 300 "$CHEZ" --libdirs src:tests:build/scheme-libs --program "$s" >"$log" 2>&1
      rc=$?
      p=$(sed -n 's/^# of expected passes *//p' "$log"); f=$(sed -n 's/^# of unexpected failures *//p' "$log")
      echo "$name $(basename "$s" .sps) exit $rc passes ${p:-0} failures ${f:-0} $(( $(date +%s) - start ))s"
    done
    for t in $targets; do
      log=../logs/$name.make-$t.log
      make "$t" >"$log" 2>&1
      echo "$name make-$t exit $?"
    done
  )
done
