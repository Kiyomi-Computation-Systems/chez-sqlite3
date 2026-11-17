#!/bin/sh
# race.sh LIB DEVICE ITEMS DELAY TRIALS LABEL: the probe under the gate's
# Valgrind options, LIB guix or floor; its output in build/s/race/LABEL.out.
lib=$1; shift
if [ "$lib" = floor ]; then
  export CHEZ_SQLITE3_LIBRARY=$PWD/build/m3-floor/lib/libsqlite3.so.0 C_INCLUDE_PATH=$PWD/build/m3-floor/include
fi
label=$5
valgrind -v --command-line-only=yes --log-file=$PWD/build/s/race/$label.valgrind --error-exitcode=9 \
  --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite --child-silent-after-fork=yes \
  $CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-review/suites/prepare-race.sps $1 $2 $3 $4 \
  > build/s/race/$label.out 2>&1
echo "$label exit $? $(tail -1 build/s/race/$label.out)"
