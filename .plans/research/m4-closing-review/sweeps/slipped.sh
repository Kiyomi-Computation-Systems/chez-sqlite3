#!/bin/sh
# slipped.sh OUT: from the worktree's root, inside scripts/guix-env, the trip-slip plant: each
# of builder D's suites copied under build/slip/tests with its low trip, 256 bytes, slipped to
# 262144, 256 KiB, then run against src/, in parallel, Chez alone; OUT/<suite>.out their
# outputs, and OUT/summary.txt each run's exit code and failing rows' count. Every low row
# must fail by name, and no other row. For the floor, set CHEZ_SQLITE3_LIBRARY and
# C_INCLUDE_PATH to its build first, as make test's floor runs do.
set -u
out=$1
suites="test-open-engines test-open-db-config-engines test-open-interleave test-conveniences-resumed test-conveniences-pending-execute test-conveniences-pending-query test-conveniences-pending-query-row test-conveniences-pending-fold test-conveniences-pending-fold-low test-conveniences-pending-script-even test-conveniences-pending-script-odd test-conveniences-pending-script-low-0 test-conveniences-pending-script-low-1 test-conveniences-pending-script-low-2 test-conveniences-pending-script-low-3 test-transaction-engine test-conveniences-reentry"
mkdir -p build/slip/tests "$out"
for f in tests/conveniences-pending.sls; do
  sed 's/(define low-trip 256)/(define low-trip 262144)/' "$f" > "build/slip/$f"
done
for t in $suites; do
  sed 's/(define low-trip 256)/(define low-trip 262144)/' "tests/$t.sps" > "build/slip/tests/$t.sps"
done
make deps >/dev/null
: > "$out/summary.txt"
for t in $suites; do
  ( timeout 3000 $CHEZ --libdirs "build/slip/tests:src:tests:build/scheme-libs" --program "build/slip/tests/$t.sps" > "$out/$t.out" 2>&1
    echo "$t rc=$? fails: $(grep -c '^FAIL' "$out/$t.out")" >> "$out/summary.txt" ) &
done
wait
