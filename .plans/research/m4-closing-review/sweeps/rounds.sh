#!/bin/sh
# rounds.sh OUT ROUNDS: from the worktree's root, inside scripts/guix-env, each plant of
# Proposal 1 against the suites whose low rows exist for it, ROUNDS times, the plants and their
# suites in parallel, Chez alone; OUT/<round>/<plant>/<suite>.out their outputs, and
# OUT/summary.txt each run's exit code and failing rows' count. Make the copies first, on the
# host, with planted.sh, as plants.sh says.
set -u
out=$1; rounds=$2
make deps >/dev/null
mkdir -p "$out"
: > "$out/summary.txt"
for r in $(seq 1 "$rounds"); do
  for spec in "P-open-advance-after:test-open-engines test-open-db-config-engines test-open-interleave" \
              "P-conv-advance-after:test-conveniences-resumed test-conveniences-pending-execute test-conveniences-pending-query test-conveniences-pending-query-row test-transaction-engine" \
              "P-fold-left-after:test-conveniences-pending-fold-low test-conveniences-resumed" \
              "P-script-claim-after:test-conveniences-pending-script-low-0 test-conveniences-pending-script-low-1 test-conveniences-pending-script-low-2 test-conveniences-pending-script-low-3 test-conveniences-resumed test-conveniences-reentry" \
              "P-tx-take-after:test-transaction-engine"; do
    p=${spec%%:*}; suites=${spec#*:}
    mkdir -p "$out/$r/$p"
    for t in $suites; do
      ( timeout 3000 $CHEZ --libdirs "build/plant/$p/src:tests:build/scheme-libs" --program "tests/$t.sps" > "$out/$r/$p/$t.out" 2>&1
        echo "$r $p $t rc=$? fails: $(grep -c '^FAIL' "$out/$r/$p/$t.out")" >> "$out/summary.txt" ) &
    done
  done
  wait
done
