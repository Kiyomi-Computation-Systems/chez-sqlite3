#!/bin/sh
# The memory gate's first measurement (M0 slice 3). Run from the repository
# root, inside the container: scripts/guix-env sh .plans/research/memory-gate/measure.sh
# Valgrind gets the gate's own options (ADR-0005) and no suppression.
set -u
here=.plans/research/memory-gate
out=build/memory-research
rm -rf "$out"
mkdir -p build
echo "valgrind: $(valgrind --version)"
echo "chez: $CHEZ -> $(readlink -f "$CHEZ")"
echo "lib: $CHEZ_SQLITE3_LIBRARY -> $(readlink -f "$CHEZ_SQLITE3_LIBRARY")"
gate() {
  log=$1; shift
  start=$(date +%s)
  valgrind -v --command-line-only=yes "--log-file=$log" --error-exitcode=9 \
    --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite \
    "$CHEZ" --libdirs src:tests:build/scheme-libs --program "$@"
  rc=$?
  echo "exit $rc, $(( $(date +%s) - start ))s"
  grep -E '== (ERROR SUMMARY|   definitely lost|   indirectly lost|   possibly lost|   still reachable|   suppressed)' "$log" | sed 's/^==[0-9]*== //'
  sed -n 's/^--[0-9]*-- Reading suppressions file: /suppressions: /p' "$log"
  sed -n 's/^--[0-9]*-- used_suppression: */used: /p' "$log"
  sed -n 's/^--[0-9]*-- Reading syms from //p' "$log" | head -n 1 | sed 's/^/first syms: /'
}
logs=build/memory-research-logs
rm -rf "$logs"
mkdir -p "$logs"
for case in plain forget hold wrap; do
  echo "== $case"
  if [ "$case" = plain ]; then set --; else set -- "$case"; fi
  echo "-- without valgrind"
  "$CHEZ" --program "$here/open-close.sps" "$@"; echo "exit $?"
  rm -rf "$out"
  echo "-- under the gate's valgrind"
  gate "$logs/$case.valgrind" "$here/open-close.sps" "$@"
  rm -rf "$out"
done
for t in tests/test-*.sps; do
  echo "== $t"
  gate "$logs/$(basename "$t" .sps).valgrind" "$t" >"$logs/$(basename "$t" .sps).log" 2>&1
  tail -n 9 "$logs/$(basename "$t" .sps).log"
done
