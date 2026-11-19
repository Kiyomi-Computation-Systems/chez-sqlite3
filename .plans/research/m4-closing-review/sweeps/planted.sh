#!/bin/sh
# planted.sh NAME...: for each plant NAME, a copy of the tree's src/ under
# build/plant/NAME/src with plant.py's NAME applied, made from the worktree's
# root. A suite runs against it as make test runs it, with the copy first on
# the library path: --libdirs build/plant/NAME/src:tests:build/scheme-libs.
# It needs python3, which the guix-env container lacks: run it on the host.
set -eu
here=$(dirname -- "$0")
for name in "$@"; do
  dir=build/plant/$name
  mkdir -p "$dir"
  rm -rf "$dir/src"
  cp -R src "$dir/src"
  python3 "$here/plant.py" "$dir" "$name"
done
