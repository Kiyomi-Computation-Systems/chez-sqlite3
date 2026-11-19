#!/bin/sh
# run-suites.sh DIR OUT SUITE...: inside the container. Runs each SUITE
# (a tests/ file name) from inside the copy DIR, outside the gate, writing
# its whole output to OUT/<name>.log, and prints one line per suite:
# NAME exit N passes P failures F TIME.
dir=$1; out=$2; shift 2
mkdir -p "$out"
cd "$dir" || exit 1
make deps >/dev/null 2>&1 || { echo "deps failed in $dir"; exit 1; }
for s in "$@"; do
  name=$(basename "$s" .sps)
  log=$out/$name.log
  start=$(date +%s)
  timeout 300 "$CHEZ" --libdirs src:tests:build/scheme-libs --program "tests/$name.sps" >"$log" 2>&1
  rc=$?
  p=$(sed -n 's/^# of expected passes *//p' "$log"); f=$(sed -n 's/^# of unexpected failures *//p' "$log")
  echo "$name exit $rc passes ${p:-0} failures ${f:-0} $(( $(date +%s) - start ))s"
done
