#!/bin/sh
# plants.sh OUT: from the worktree's root, inside scripts/guix-env, each of
# builder D's suites run against each plant's copy and against src/ itself,
# in parallel, Chez alone; OUT/<plant>/<suite>.out their outputs, and
# OUT/summary.txt each run's exit code and failing rows' count. Make the
# copies first, on the host, which has python3, where the container has none:
#   sh .plans/research/m4-closing-review/sweeps/planted.sh <every plant below>
# A copy planted.sh could not plant is a plain copy of src/, and passes.
set -u
out=$1
here=$(dirname -- "$0")
plants="P-open-advance-after P-conv-advance-after P-tx-take-after P-fold-left-after P-script-claim-after C-open-settings-unclaimed C-open-open-unclaimed C-conv-unclaimed C-fold-unflagged C-script-unclaimed C-tx-unclaimed C-tx-unclaimed-unended"
suites="test-open-engines test-open-db-config-engines test-open-interleave test-conveniences-resumed test-conveniences-pending-execute test-conveniences-pending-query test-conveniences-pending-query-row test-conveniences-pending-fold test-conveniences-pending-fold-low test-conveniences-pending-script-even test-conveniences-pending-script-odd test-conveniences-pending-script-low-0 test-conveniences-pending-script-low-1 test-conveniences-pending-script-low-2 test-conveniences-pending-script-low-3 test-transaction-engine"
for p in $plants; do
  if diff -rq src "build/plant/$p/src" >/dev/null; then
    echo "plants.sh: build/plant/$p/src is src/ unplanted; run planted.sh on the host" >&2; exit 2
  fi
done
make deps >/dev/null
mkdir -p "$out"
: > "$out/summary.txt"
for p in none $plants; do
  if [ "$p" = none ]; then lib=src; else lib=build/plant/$p/src; fi
  mkdir -p "$out/$p"
  for t in $suites; do
    ( timeout 3000 $CHEZ --libdirs "$lib:tests:build/scheme-libs" --program tests/$t.sps > "$out/$p/$t.out" 2>&1
      echo "$p $t rc=$? fails: $(grep -c '^FAIL' "$out/$p/$t.out")" >> "$out/summary.txt" ) &
  done
  wait
done
