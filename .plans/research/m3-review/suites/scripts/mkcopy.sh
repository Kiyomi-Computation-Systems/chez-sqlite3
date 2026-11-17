#!/bin/sh
# mkcopy.sh NAME: a copy of the worktree at build/s/NAME, with the floor.
set -eu
root=$(pwd)  # run from the worktree's root
rsync -a --exclude .git --exclude build "$root/" "$root/build/s/$1/"
mkdir -p "$root/build/s/$1/build"
cp -a "$root/build/m3-floor" "$root/build/s/$1/build/"
cp "$root/build/s/plain-times.sh" "$root/build/s/gate-times.sh" "$root/build/s/$1/"
