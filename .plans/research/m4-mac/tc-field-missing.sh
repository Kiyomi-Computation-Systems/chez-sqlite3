#!/bin/sh
# tc-field-missing.sh OUT: from the worktree's root, inside scripts/guix-env, a Chez whose
# $tc-field can't be reached, stood in on Linux. tests/ is copied to OUT/tests, and in each of
# the seven files that define tc-field, `(string->symbol "$tc-field")` names
# `$tc-field-missing`, so the suite's guard answers #f, as it would on a Chez without the
# field. The six suites that print a low tally and the eleven pending suites then run against
# src/, in parallel; OUT/summary.txt holds each one's exit code and FAIL lines. Every low row
# must fail by name, `(none-taken-at-a-forced-exit ())`, and no other row. Run in M4's
# closing review's Mac step, on Guix's 3.53.1 and Chez 10.4.0:
# out/closing-review/tc-field-missing-linux.txt. The M4 session found the method.
set -u
out=$1
if [ -e "$out" ]; then echo "tc-field-missing.sh: $out exists" >&2; exit 1; fi
mkdir -p "$out"
cp -R tests "$out/tests"
before=$(grep -l '(string->symbol "\$tc-field")' "$out"/tests/*.sps "$out"/tests/*.sls | wc -l)
sed -i 's/(string->symbol "\$tc-field")/(string->symbol "$tc-field-missing")/' "$out"/tests/*.sps "$out"/tests/*.sls
after=$(grep -l '"\$tc-field-missing"' "$out"/tests/*.sps "$out"/tests/*.sls | wc -l)
if [ "$before" -ne 7 ] || [ "$after" -ne 7 ]; then
  echo "tc-field-missing.sh: expected 7 files defining tc-field, found $before, changed $after" >&2
  exit 1
fi
suites="test-conveniences-reentry test-conveniences-resumed test-open-db-config-engines test-open-engines test-open-interleave test-transaction-engine"
for f in tests/test-conveniences-pending-*.sps; do
  suites="$suites $(basename "$f" .sps)"
done
make deps >/dev/null
: > "$out/summary.txt"
for t in $suites; do
  ( timeout 3000 $CHEZ --libdirs "$out/tests:src:build/scheme-libs" --program "$out/tests/$t.sps" > "$out/$t.out" 2>&1
    echo "$t rc=$? fail=$(grep -c '^FAIL' "$out/$t.out")" >> "$out/summary.txt" ) &
done
wait
echo "FAIL $(cat "$out"/*.out | grep -c '^FAIL'), low $(cat "$out"/*.out | grep '^FAIL' | grep -c 'collect trip of 256 bytes'), none-taken $(cat "$out"/*.out | grep -c 'none-taken-at-a-forced-exit ()')" >> "$out/summary.txt"
