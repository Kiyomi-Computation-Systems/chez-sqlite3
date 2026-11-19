#!/bin/sh
# run-plants.sh JOBS DIR...: inside the container, from the worktree's root.
# Runs one-plant.sh on each plant copy DIR, JOBS at a time.
jobs=$1; shift
here=$(cd "$(dirname "$0")" && pwd)
printf '%s\n' "$@" | xargs -P "$jobs" -n 1 sh "$here/one-plant.sh"
echo "run-plants: $# done"
