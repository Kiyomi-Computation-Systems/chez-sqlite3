#!/bin/sh
# gate-plants.sh OUT: inside the container. The gate's plants, each in its
# copy under OUT/LAYOUT/NAME, under make test-memory: G1 every loading suite
# of the layout, G2 the suite that holds lacks-sqlite3_sourceid's row.
out=$1
OLD="tests/test-library-loading-real.sps tests/test-library-loading-decoys.sps tests/test-library-loading-missing.sps"
NEW="tests/test-library-loading-missing-1.sps tests/test-library-loading-missing-2.sps tests/test-library-loading-missing-3.sps tests/test-library-loading-missing-4.sps tests/test-library-loading-real.sps tests/test-library-loading-preflight.sps tests/test-library-loading-extension.sps tests/test-library-loading-decoys.sps tests/test-library-loading-combined.sps"
run() {
  ( cd "$out/$1/$2" && make test-memory MEMORY_SUITES="$3" > .gate.log 2>&1; echo "$1 $2 exit $?" )
}
run old G1-gated-command-unchanged "$OLD" &
run new G1-gated-command-unchanged "$NEW" &
run old G2-one-child-ungated tests/test-library-loading-missing.sps &
run new G2-one-child-ungated tests/test-library-loading-missing-3.sps &
wait
