#!/bin/sh
# run-plants.sh LIB SUITE NAME...   in the container, from the worktree's
#                                   root: in each plant's copy,
#                                   build/cr-code/NAME/ (plants.py), make
#                                   deps, then SUITE, without tests/ and
#                                   .sps, under timeout 300, on LIB's
#                                   library: guix for the container's own,
#                                   or a directory under build/ holding
#                                   lib/libsqlite3.so.0 and include/, set
#                                   as CHEZ_SQLITE3_LIBRARY and
#                                   C_INCLUDE_PATH. Prints the library's
#                                   version, the suite's exit, passes and
#                                   failures, read from its own counts, the
#                                   rows that failed, and its UNAVAILABLE
#                                   lines.
# Logs go to build/cr-code/NAME.LIB.SUITE.log, beside the copies.
root=$(pwd)
out=$root/build/cr-code
lib=$1; shift
t=$1; shift
for name in "$@"; do
  cd "$out/$name" || exit 2
  make deps >/dev/null 2>&1 || { echo "$name: make deps failed"; continue; }
  if [ "$lib" != guix ]; then
    CHEZ_SQLITE3_LIBRARY=$PWD/build/$lib/lib/libsqlite3.so.0
    C_INCLUDE_PATH=$PWD/build/$lib/include
    export CHEZ_SQLITE3_LIBRARY C_INCLUDE_PATH
  fi
  version=$(echo '(import (chez-sqlite3)) (display (sqlite-version))' | $CHEZ --libdirs src -q 2>&1)
  log=$out/$name.$lib.$t.log
  start=$(date +%s)
  timeout 300 $CHEZ --libdirs src:tests:build/scheme-libs --program tests/$t.sps > "$log" 2>&1
  rc=$?
  end=$(date +%s)
  pass=$(grep '^# of expected passes' "$log" | awk '{print $NF}')
  fail=$(grep '^# of unexpected failures' "$log" | awk '{print $NF}')
  echo "$name $lib ($version) $t: exit $rc, pass ${pass:-0}, fail ${fail:-0}, $((end - start)) s"
  grep '^FAIL' "$log" | cut -c1-140 | sed 's/^/    /'
  grep '^UNAVAILABLE' "$log" | cut -c1-140 | sed 's/^/    /'
done
