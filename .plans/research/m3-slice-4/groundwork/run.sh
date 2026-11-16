#!/bin/sh
# Builds and runs this directory's C probes on both libraries, after
# .plans/research/m3-plan/single/run.sh.
#
#   scripts/guix-env sh -c 'cd build/m3s4-groundwork/tree && \
#     d=$(mktemp -d ../scratch/run.XXXXXX) && sh ../probes/run.sh "$d" ../probes/out PROBE...'
#
# Run inside the container, from the tree copy's root. Each C probe is
# compiled against each library's own header and linked to that library by
# path, with an rpath, and refuses to run unless the runtime version number
# and source id equal the header's.
set -eu

[ $# -ge 3 ] || { echo "usage: run.sh SCRATCH OUT PROBE..." >&2; exit 2; }
scratch=$1; out=$2; shift 2
here=$(dirname "$0")
[ -d "$scratch" ] || { echo "run.sh: no directory $scratch" >&2; exit 2; }
mkdir -p "$out"

for lib in guix floor; do
  case $lib in
    guix)  inc=$GUIX_ENVIRONMENT/include; libdir=$GUIX_ENVIRONMENT/lib; tag=guix-3.53.1 ;;
    floor) inc=$PWD/build/m3-floor/include; libdir=$PWD/build/m3-floor/lib; tag=floor-3.45.1 ;;
  esac
  so=$libdir/libsqlite3.so.0
  for p in "$@"; do
    mkdir "$scratch/$p-$lib.d"
    $CC -O2 -Wall -Werror -I"$inc" -o "$scratch/$p-$lib" "$here/$p.c" \
      "$so" -Wl,-rpath,"$libdir" -lpthread -lm
    timeout 300 "$scratch/$p-$lib" "$scratch/$p-$lib.d" > "$out/$p-$tag.txt"
  done
done
