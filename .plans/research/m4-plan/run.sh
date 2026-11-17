#!/bin/sh
# Builds and runs this directory's C probes on each library (the M4 plan,
# section 8).
#
#   scripts/guix-env sh -c 'd=$(mktemp -d "$PWD/build/m4plan/run.XXXXXX") && \
#     sh .plans/research/m4-plan/run.sh "$d" "$d/out" PROBE...'
#
# Run inside the container, from the worktree's root. SCRATCH must be a
# fresh directory, named by an absolute path: each probe's files go in a
# directory of its own under it. OUT receives PROBE-LABEL.txt for each PROBE
# named, or for every probe when none is, and PROBE-timing-LABEL.txt for a
# probe that times anything.
#
# The libraries, by label:
#   guix-3.53.1          the container's, $GUIX_ENVIRONMENT's
#   floor-3.45.1         build/m3-floor, CI's floor lane's build
#   current-3.54.1       build/m4plan/current, CI's current lane's build today
#   current-fts5-3.54.1  build/m4plan/current-fts5, the same with
#                        -DSQLITE_ENABLE_FTS5, as Q1's answer builds it
# f1-fts5-json runs on all four; d1 and l1 on the first three.
#
# Each probe is compiled against its library's own header and linked to that
# library by path, with an rpath, and refuses to run unless the runtime
# version number and source id equal the header's. For l1, ext.c and
# noentry.c are compiled into the probe's directory first, against the same
# header, and the time of the first compile is written to
# ext-compile-timing-LABEL.txt.
set -eu

[ $# -ge 2 ] || { echo "usage: run.sh SCRATCH OUT [PROBE...]" >&2; exit 2; }
scratch=$1; out=$2; shift 2
here=.plans/research/m4-plan
case $scratch in /*) ;; *) echo "run.sh: SCRATCH must be absolute" >&2; exit 2 ;; esac
[ -d "$scratch" ] || { echo "run.sh: no directory $scratch" >&2; exit 2; }
mkdir -p "$out"

all="d1-db-config-open l1-load-extension f1-fts5-json"
[ $# -gt 0 ] || set -- $all

# extensions DIR INC LABEL: the shared objects l1 loads, built into DIR.
extensions() {
  d=$1; inc=$2; label=$3
  t0=$(date +%s%N)
  $CC -O2 -Wall -Werror -shared -fPIC -I"$inc" -o "$d/ext.so" "$here/ext.c"
  t1=$(date +%s%N)
  echo "ext.c, one compile: $(( (t1 - t0) / 1000000 )) ms" >"$out/ext-compile-timing-$label.txt"
  $CC -O2 -Wall -Werror -shared -fPIC -I"$inc" -DEXT_NAMED -o "$d/ext-named.so" "$here/ext.c"
  $CC -O2 -Wall -Werror -shared -fPIC -I"$inc" -DEXT_DERIVED -o "$d/libchezext.so" "$here/ext.c"
  $CC -O2 -Wall -Werror -shared -fPIC -I"$inc" -DEXT_FAILING -o "$d/ext-failing.so" "$here/ext.c"
  $CC -O2 -Wall -Werror -shared -fPIC -o "$d/noentry.so" "$here/noentry.c"
  : >"$d/empty.so"
  mkdir "$d/dir.so"
}

for lib in guix floor current current-fts5; do
  case $lib in
    guix)  inc=$GUIX_ENVIRONMENT/include; libdir=$GUIX_ENVIRONMENT/lib; tag=guix-3.53.1 ;;
    floor) inc=$PWD/build/m3-floor/include; libdir=$PWD/build/m3-floor/lib; tag=floor-3.45.1 ;;
    current) inc=$PWD/build/m4plan/current/include; libdir=$PWD/build/m4plan/current/lib
             tag=current-3.54.1 ;;
    current-fts5) inc=$PWD/build/m4plan/current-fts5/include
                  libdir=$PWD/build/m4plan/current-fts5/lib; tag=current-fts5-3.54.1 ;;
  esac
  so=$libdir/libsqlite3.so.0
  for p in "$@"; do
    if [ "$lib" = current-fts5 ] && [ "$p" != f1-fts5-json ]; then continue; fi
    mkdir "$scratch/$p-$lib.d"
    if [ "$p" = l1-load-extension ]; then extensions "$scratch/$p-$lib.d" "$inc" "$tag"; fi
    $CC -O2 -Wall -Werror -I"$inc" -o "$scratch/$p-$lib" "$here/$p.c" \
      "$so" -Wl,-rpath,"$libdir" -lpthread -lm
    "$scratch/$p-$lib" "$scratch/$p-$lib.d" "$out/$p-timing-$tag.txt" >"$out/$p-$tag.txt"
  done
done
