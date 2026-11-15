#!/bin/sh
# Builds and runs this directory's probes on both libraries.
#
#   scripts/guix-env sh -c 'd=$(mktemp -d build/m3plan/run.XXXXXX) && \
#     sh .plans/research/m3-plan/slice-0/run.sh "$d" "$d/out" PROBE...'
#
# Run inside the container, from the worktree's root. SCRATCH must be a fresh
# directory: each probe's databases go in a directory of its own under it.
# OUT receives PROBE-guix-3.53.1.txt and PROBE-floor-3.45.1.txt for each
# PROBE named, or for every probe when none is, and PROBE-timing-….txt for a
# probe that times anything.
#
# Each probe is compiled against its library's own header and linked to that
# library by path, with an rpath, and refuses to run unless the runtime
# version number and source id equal the header's.
set -eu

[ $# -ge 2 ] || { echo "usage: run.sh SCRATCH OUT [PROBE...]" >&2; exit 2; }
scratch=$1; out=$2; shift 2
here=.plans/research/m3-plan/slice-0
[ -d "$scratch" ] || { echo "run.sh: no directory $scratch" >&2; exit 2; }
mkdir -p "$out"

all="p1-pragma-reuse p2-settings-locks p3-wait-release p7-rollback-sticky p9-begin-beside-read p11-null-tail p12-held-read p13-pragma-expire p14-wal-on-wal"
[ $# -gt 0 ] || set -- $all

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
    # A probe that times nothing never opens its timing file.
    "$scratch/$p-$lib" "$scratch/$p-$lib.d" "$out/$p-timing-$tag.txt" > "$out/$p-$tag.txt"
  done
done
