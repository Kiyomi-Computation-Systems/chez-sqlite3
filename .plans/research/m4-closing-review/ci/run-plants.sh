#!/bin/sh
# run-plants.sh NAME...: each plant's RUN.sh, six at once, each logged to
# build/e1/plants/NAME.log, from the worktree's root inside the container:
#   scripts/guix-env sh .plans/research/m4-closing-review/ci/run-plants.sh C01 C02 ...
wt=$PWD
printf '%s\n' "$@" | xargs -P 6 -I{} sh -c 'sh "$1/build/e1/plants/$2/RUN.sh" "$1" > "$1/build/e1/plants/$2.log" 2>&1' sh "$wt" {}
