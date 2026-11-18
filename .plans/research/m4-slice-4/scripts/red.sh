#!/bin/sh
# M4 slice 4's red copies, run from the worktree's root.
#
#   sh red.sh prepare   on the host, which has git: build/mut/red, this tree
#                       with c92d397's src/ and docs/, and build/mut/base-own,
#                       c92d397 whole, its chez-srfi copied from this tree's
#   sh red.sh run       inside scripts/guix-env: the slice's seven suites in
#                       each, each log beside it, then each suite's counts
#
# c92d397 is main before the slice. A suite a copy lacks is skipped.
set -eu
base=c92d397
suites="test-load-extension test-load-extension-engines test-public test-reference test-never-loads test-library-loading-real test-docs"
case "${1:-}" in
  prepare)
    for d in red base-own; do rm -rf "build/mut/$d"; mkdir -p "build/mut/$d"; done
    tar -C . --exclude=./build --exclude=./.git -cf - . | tar -C build/mut/red -xf -
    rm -rf build/mut/red/src build/mut/red/docs
    git archive "$base" src docs | tar -C build/mut/red -xf -
    git archive "$base" | tar -C build/mut/base-own -xf -
    rm -rf build/mut/base-own/vendor/chez-srfi
    cp -R vendor/chez-srfi build/mut/base-own/vendor/chez-srfi
    ;;
  run)
    for d in red base-own; do
      (cd "build/mut/$d" && make deps > logs-deps.txt 2>&1 || echo "$d: deps failed"
       for s in $suites; do
         [ -f "tests/$s.sps" ] || continue
         timeout 600 "$CHEZ" --libdirs src:tests:build/scheme-libs --program "tests/$s.sps" > "log-$s.txt" 2>&1 || true
       done)
      for s in $suites; do
        f="build/mut/$d/log-$s.txt"
        [ -f "$f" ] || { echo "$d $s: none"; continue; }
        echo "$d $s: $(grep -E '^# of (expected passes|unexpected failures)' "$f" | awk '{print $NF}' | paste -sd' ' -)"
      done
    done
    ;;
  *) echo "usage: sh red.sh prepare|run" >&2; exit 2 ;;
esac
