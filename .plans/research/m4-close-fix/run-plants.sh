#!/bin/sh
# run-plants.sh LIB NAME...   in the container, from the worktree's root: in
#                             each plant's copy, build/mut/NAME/ (plants.py),
#                             make deps, then the close's suites plain, each
#                             under timeout 300, on LIB's library: guix for
#                             the container's own, or a directory under
#                             build/ holding lib/libsqlite3.so.0 and include/,
#                             set as CHEZ_SQLITE3_LIBRARY and C_INCLUDE_PATH.
#                             Prints each suite's exit, passes and failures,
#                             read from the suite's own counts, and the names
#                             of the rows that failed.
# SUITES, when set, names the suites to run, without tests/ and .sps.
# Logs go to build/mut/NAME.LIB.SUITE.log, beside the copies.
root=$(pwd)
out=$root/build/mut
lib=$1; shift
suites=${SUITES:-"test-connection-close test-connection test-connection-cache test-interrupt-close test-interrupt-database test-interrupt test-open-settings test-open-engines test-transaction-engine test-statement test-statement-who"}
for name in "$@"; do
  cd "$out/$name" || exit 2
  make deps >/dev/null 2>&1 || { echo "$name: make deps failed"; continue; }
  if [ "$lib" = guix ]; then
    :
  else
    CHEZ_SQLITE3_LIBRARY=$PWD/build/$lib/lib/libsqlite3.so.0
    C_INCLUDE_PATH=$PWD/build/$lib/include
    export CHEZ_SQLITE3_LIBRARY C_INCLUDE_PATH
  fi
  for t in $suites; do
    log=$out/$name.$lib.$t.log
    start=$(date +%s)
    timeout 300 $CHEZ --libdirs src:tests:build/scheme-libs --program tests/$t.sps > "$log" 2>&1
    rc=$?
    end=$(date +%s)
    pass=$(grep '^# of expected passes' "$log" | awk '{print $NF}')
    fail=$(grep '^# of unexpected failures' "$log" | awk '{print $NF}')
    echo "$name $lib $t: exit $rc, pass ${pass:-0}, fail ${fail:-0}, $((end - start)) s"
    grep '^FAIL' "$log" | cut -c1-110 | sed 's/^/    /'
  done
done
