#!/bin/sh
# twenty.sh OUT LIB SUITE: from the worktree's root, inside scripts/guix-env, SUITE run 20
# times against LIB (src, or a plant's copy build/plant/NAME/src): ten at once, then ten one
# after another, Chez alone; OUT/par-<i>.out and OUT/seq-<i>.out, and OUT/summary.txt each
# run's exit code and failing rows. Parallel runs meet another heap layout than sequential
# ones, and a catch the layout decides moves between them.
set -u
out=$1; lib=$2; suite=$3
mkdir -p "$out"
: > "$out/summary.txt"
make deps >/dev/null
for i in 1 2 3 4 5 6 7 8 9 10; do
  ( timeout 3000 $CHEZ --libdirs "$lib:tests:build/scheme-libs" --program "tests/$suite.sps" > "$out/par-$i.out" 2>&1
    echo "par $i rc=$? fails: $(grep -c '^FAIL' "$out/par-$i.out")" >> "$out/summary.txt" ) &
done
wait
for i in 1 2 3 4 5 6 7 8 9 10; do
  timeout 3000 $CHEZ --libdirs "$lib:tests:build/scheme-libs" --program "tests/$suite.sps" > "$out/seq-$i.out" 2>&1
  echo "seq $i rc=$? fails: $(grep -c '^FAIL' "$out/seq-$i.out")" >> "$out/summary.txt"
done
