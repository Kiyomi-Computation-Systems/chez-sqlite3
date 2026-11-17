#!/bin/sh
# Inside the container, from the worktree: make deps in each planted copy
# named, then run its SUITES, each under timeout 300, printing each suite's
# counts and FAIL lines to build/t/mut/NAME.log.
cd "$(dirname "$0")/../../../../.."  # the tree's root; it was build/t/ in the worktree
root=$PWD
for name in "$@"; do
  d="build/t/mut/$name"
  log="$root/build/t/mut/$name.log"
  ( cd "$d" && make deps > /dev/null 2>&1
    for t in $(cat SUITES); do
      out=$(timeout 300 $CHEZ --libdirs src:tests:build/scheme-libs --program "$t" 2>&1)
      rc=$?
      echo "== $t rc=$rc $(printf '%s\n' "$out" | grep -E '^# of (expected passes|unexpected failures)' | tr -s ' ' | tr '\n' ' ')"
      printf '%s\n' "$out" | grep -E '^FAIL|^Exception' | cut -c1-160
    done ) > "$log" 2>&1
  echo "$name: $(grep -c '^FAIL' "$log") failed rows; $(grep -E 'rc=[^0]' "$log" | wc -l) suites not 0"
done
