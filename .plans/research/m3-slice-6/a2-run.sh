#!/bin/sh
# a2-run.sh plain NAME...         in the container: in each plant's copy,
#                                 build/a2/final/NAME/ (a2-plants.py), make
#                                 deps, then six suites plain, each under
#                                 timeout 300: each suite's counts, and the
#                                 rows that failed in test-interrupt-database
# a2-run.sh gate [floor] DIR...   in the container: in each DIR, make
#                                 test-memory MEMORY_SUITES=tests/test-interrupt-database.sps,
#                                 on Guix's library, or with floor the floor's,
#                                 CHEZ_SQLITE3_LIBRARY and C_INCLUDE_PATH both:
#                                 the gate's verdict and time, Valgrind's
#                                 error summary, the freed block, the library
#                                 Valgrind read, and the sweeps' lines
# Logs go to build/a2/final/, beside the copies.
root=/home/kishu/src/chez-sqlite3-wt-m3s6
out=$root/build/a2/final
mode=$1; shift
case $mode in
  plain)
    for name in "$@"; do
      cd "$out/$name" || exit 2
      make deps >/dev/null 2>&1 || { echo "$name: make deps failed"; continue; }
      for t in test-interrupt-database test-interrupt-reach test-interrupt-close test-interrupt test-connection test-public; do
        log=$out/$name.$t.log
        timeout 300 $CHEZ --libdirs src:tests:build/scheme-libs --program tests/$t.sps > "$log" 2>&1
        rc=$?
        pass=$(grep '^# of expected passes' "$log" | awk '{print $NF}')
        fail=$(grep '^# of unexpected failures' "$log" | awk '{print $NF}')
        echo "$name $t: exit $rc, pass ${pass:-0}, fail ${fail:-0}"
      done
      grep -E '^FAIL|^  interrupt-database' "$out/$name.test-interrupt-database.log" | cut -c1-100 | sed 's/^/    /'
    done ;;
  gate)
    floor=no
    [ "$1" = floor ] && { floor=yes; shift; }
    for dir in "$@"; do
      cd "$dir" || exit 2
      tag=$(basename "$dir"); [ $floor = yes ] && tag=$tag.floor
      if [ $floor = yes ]; then
        CHEZ_SQLITE3_LIBRARY=$PWD/build/m3-floor/lib/libsqlite3.so.0 C_INCLUDE_PATH=$PWD/build/m3-floor/include \
          make test-memory MEMORY_SUITES=tests/test-interrupt-database.sps > "$out/$tag.gate.out" 2>&1
      else
        make test-memory MEMORY_SUITES=tests/test-interrupt-database.sps > "$out/$tag.gate.out" 2>&1
      fi
      rc=$?
      v=build/memory/test-interrupt-database.valgrind
      cp build/memory/test-interrupt-database.log "$out/$tag.gate.log"
      cp $v "$out/$tag.gate.valgrind"
      echo "$tag: make exit $rc"
      grep -E '^test-memory: (pass|FAIL)|time:' "$out/$tag.gate.out" | sed 's/^ */    /'
      echo "    $(grep -m1 'ERROR SUMMARY' $v | sed 's/^==[0-9]*== //')"
      grep -m1 'Invalid write' $v | sed 's/^==[0-9]*== */    /'
      grep -m1 'bytes inside a block' $v | sed 's/^==[0-9]*== */    /'
      echo "    library: $(grep -m1 -o 'Reading syms from [^ ]*libsqlite3[^ ]*' $v | sed 's/Reading syms from //')"
      grep -E '^  interrupt-database|^# of' build/memory/test-interrupt-database.log | sed 's/^ */    /'
    done ;;
  *) echo "a2-run.sh: plain NAME... or gate [floor] DIR..." >&2; exit 2 ;;
esac
