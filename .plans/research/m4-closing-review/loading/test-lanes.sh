#!/bin/sh
# test-lanes.sh OUT: inside the container, from the worktree's root. make test
# on Guix's library, then on each of build/'s three, each run's library and
# headers set here and its version line, make build's, first. Writes
# OUT/test-LANE.log and prints one line a lane.
out=$1
mkdir -p "$out"
lane() {
  name=$1
  { echo "lane $name: CHEZ_SQLITE3_LIBRARY=$CHEZ_SQLITE3_LIBRARY C_INCLUDE_PATH=${C_INCLUDE_PATH-unset}"
    make build
    make test
    echo "lane $name: make test exit $?"
  } > "$out/test-$name.log" 2>&1
  printf '%s: %s; %s\n' "$name" "$(grep -m1 '  version:' "$out/test-$name.log")" "$(grep -E '^test: ran|make test exit' "$out/test-$name.log" | tr '\n' ' ')"
}
lane guix
for b in m3-floor m4-current m4-noload; do
  ( export CHEZ_SQLITE3_LIBRARY=$PWD/build/$b/lib/libsqlite3.so.0 C_INCLUDE_PATH=$PWD/build/$b/include
    lane "$b" )
done
