#!/bin/sh
# plant.sh NAME : a fresh copy of the worktree in build/c/NAME, its deps made
# inside the container, ready for a plant. Run from the worktree's root, on
# the host.
set -e
name=$1
dest=build/c/$name
mkdir -p "$dest"
rsync -a --delete --exclude .git --exclude build ./ "$dest/"
mkdir -p "$dest/build"
cp -a build/m3-floor "$dest/build/"
scripts/guix-env sh -c "cd $dest && make deps > build/deps.log 2>&1" && echo "copy $dest ready"
