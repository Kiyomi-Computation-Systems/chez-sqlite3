#!/bin/sh
# run-mutants.sh NAME...: each mutant's RUN.sh, six at once, each logged to
# build/mut/NAME.log, from the worktree's root inside the container.
wt=$PWD
printf '%s\n' "$@" | xargs -P 6 -I{} sh -c 'sh "$1/build/mut/$2/RUN.sh" "$1" > "$1/build/mut/$2.log" 2>&1' sh "$wt" {}
