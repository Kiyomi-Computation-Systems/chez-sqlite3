#!/bin/sh
# run-lanes.sh LANE...: make build, then make test, on each lane's library,
# one at a time, from the worktree's root inside the container, each logged
# to build/e1/lanes/LANE.log:
#   scripts/guix-env sh .plans/research/m4-closing-review/ci/run-lanes.sh guix m3-floor ...
# guix is the container's own library, with its own CHEZ_SQLITE3_LIBRARY and
# C_INCLUDE_PATH; any other LANE is build/LANE, both names set to it, as a
# CI lane's env sets them. make build's lines name the library a run loaded.
R=$PWD
mkdir -p "$R/build/e1/lanes"
for lane in "$@"; do
  log=$R/build/e1/lanes/$(printf '%s' "$lane" | tr / -).log
  start=$(date +%s)
  if [ "$lane" = guix ]; then
    { make build && make test; } >"$log" 2>&1
  else
    { CHEZ_SQLITE3_LIBRARY=$R/build/$lane/lib/libsqlite3.so.0 C_INCLUDE_PATH=$R/build/$lane/include make build &&
      CHEZ_SQLITE3_LIBRARY=$R/build/$lane/lib/libsqlite3.so.0 C_INCLUDE_PATH=$R/build/$lane/include make test; } >"$log" 2>&1
  fi
  rc=$?
  echo "lane $lane: exit $rc in $(( $(date +%s) - start )) s" >>"$log"
  tail -n 1 "$log"
done
