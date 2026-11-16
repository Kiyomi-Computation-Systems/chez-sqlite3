#!/bin/sh
# Runs a Chez probe of this directory on Guix's library, the floor, and the
# floor built with SQLITE_DEFAULT_MEMSTATUS=0, through the tree copy's src/.
#
#   scripts/guix-env sh -c 'cd build/m3s4-groundwork/tree && \
#     d=$(mktemp -d ../scratch/run.XXXXXX) && sh ../probes/run-chez.sh "$d" ../probes/out PROBE...'
#
# Each run is handed its library's header's version number and source id,
# read with -dM -E, and the probe refuses a library that answers others.
set -eu
[ $# -ge 3 ] || { echo "usage: run-chez.sh SCRATCH OUT PROBE..." >&2; exit 2; }
scratch=$1; out=$2; shift 2
here=$(dirname "$0")
mkdir -p "$out"
header_macro() {
  printf '#include <sqlite3.h>\n' | $CC -I"$1" -dM -E -x c - | sed -n "s/^#define $2 //p"
}
for lib in guix floor floor-memstatus-off; do
  case $lib in
    guix)  inc=$GUIX_ENVIRONMENT/include; so=$GUIX_ENVIRONMENT/lib/libsqlite3.so.0; tag=guix-3.53.1 ;;
    floor) inc=$PWD/build/m3-floor/include; so=$PWD/build/m3-floor/lib/libsqlite3.so.0; tag=floor-3.45.1 ;;
    floor-memstatus-off)
      inc=$PWD/../floor-memstatus-off/include; so=$PWD/../floor-memstatus-off/lib/libsqlite3.so.0
      tag=floor-memstatus-off-3.45.1 ;;
  esac
  number=$(header_macro "$inc" SQLITE_VERSION_NUMBER)
  source_id=$(header_macro "$inc" SQLITE_SOURCE_ID | tr -d '"')
  for p in "$@"; do
    mkdir "$scratch/$p-$lib.d"
    CHEZ_SQLITE3_LIBRARY=$so timeout 300 $CHEZ --libdirs src:tests:build/scheme-libs \
      --program "$here/$p.sps" "$scratch/$p-$lib.d" "$number" "$source_id" > "$out/$p-$tag.txt" 2>&1 \
      || echo "run-chez.sh: $p on $lib exited $?" >> "$out/$p-$tag.txt"
  done
done
