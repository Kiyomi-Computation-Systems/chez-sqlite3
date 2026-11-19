#!/bin/sh
# gate-run.sh: inside the container, from the worktree's root. The nine new
# suites under make test-memory, then the three old ones in the copy of
# main's tree, each with make build's version line first.
W=$PWD
NEW="tests/test-library-loading-missing-1.sps tests/test-library-loading-missing-2.sps tests/test-library-loading-missing-3.sps tests/test-library-loading-missing-4.sps tests/test-library-loading-real.sps tests/test-library-loading-preflight.sps tests/test-library-loading-extension.sps tests/test-library-loading-decoys.sps tests/test-library-loading-combined.sps"
OLD="tests/test-library-loading-real.sps tests/test-library-loading-decoys.sps tests/test-library-loading-missing.sps"
echo "lib: $CHEZ_SQLITE3_LIBRARY; inc: ${C_INCLUDE_PATH-unset}"
make build
date +%s
make test-memory MEMORY_SUITES="$NEW"
echo "new exit $?"
for s in $NEW; do n=$(basename $s .sps); echo "children $n $(ls build/memory/$n.children 2>/dev/null | wc -l)"; done
date +%s
cd build/e2/base-old && make build && make test-memory MEMORY_SUITES="$OLD"
echo "old exit $?"
for s in $OLD; do n=$(basename $s .sps); echo "children-old $n $(ls build/memory/$n.children 2>/dev/null | wc -l)"; done
date +%s
