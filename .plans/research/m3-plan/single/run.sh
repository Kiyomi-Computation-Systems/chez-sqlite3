#!/bin/sh
# Builds and runs this directory's probes on both libraries.
#
#   scripts/guix-env sh -c 'd=$(mktemp -d build/m3rs/run.XXXXXX) && \
#     sh .plans/research/m3-plan/single/run.sh "$d" "$d/out" PROBE...'
#
# Run inside the container, from the worktree's root. SCRATCH must be a fresh
# directory: each probe's databases go in a directory of its own under it.
# OUT receives PROBE-guix-3.53.1.txt and PROBE-floor-3.45.1.txt for each
# PROBE named, or for every probe when none is.
#
# A C probe is compiled against each library's own header and linked to that
# library by path, with an rpath, and refuses to run unless the runtime
# version number and source id equal the header's. A Chez probe is given the
# header's version number and source id, and refuses the same way.
set -eu

[ $# -ge 2 ] || { echo "usage: run.sh SCRATCH OUT [PROBE...]" >&2; exit 2; }
scratch=$1; out=$2; shift 2
here=.plans/research/m3-plan/single
[ -d "$scratch" ] || { echo "run.sh: no directory $scratch" >&2; exit 2; }
mkdir -p "$out"

c_probes="options txn txn-errors txn-special txn-open-stmts counters pragmas cache script b5 traps cost"
chez_probes="entry-points cost-chez"
[ $# -gt 0 ] || set -- $c_probes $chez_probes

# header_macro HEADER NAME: a macro's value, read with -dM (.plans/traps.md).
header_macro() {
  printf '#include <sqlite3.h>\n' | $CC -I"$1" -dM -E -x c - \
    | sed -n "s/^#define $2 //p"
}

for lib in guix floor; do
  case $lib in
    guix)  inc=$GUIX_ENVIRONMENT/include; libdir=$GUIX_ENVIRONMENT/lib; tag=guix-3.53.1 ;;
    floor) inc=$PWD/build/m3-floor/include; libdir=$PWD/build/m3-floor/lib; tag=floor-3.45.1 ;;
  esac
  so=$libdir/libsqlite3.so.0
  number=$(header_macro "$inc" SQLITE_VERSION_NUMBER)
  source_id=$(header_macro "$inc" SQLITE_SOURCE_ID | tr -d '"')
  for p in "$@"; do
    mkdir "$scratch/$p-$lib.d"
    case " $chez_probes " in
      *" $p "*)
        CHEZ_SQLITE3_LIBRARY=$so $CHEZ --script "$here/$p.sps" \
          "$scratch/$p-$lib.d" "$number" "$source_id" > "$out/$p-$tag.txt" ;;
      *)
        $CC -O2 -Wall -Werror -I"$inc" -o "$scratch/$p-$lib" "$here/$p.c" \
          "$so" -Wl,-rpath,"$libdir" -lpthread -lm
        "$scratch/$p-$lib" "$scratch/$p-$lib.d" > "$out/$p-$tag.txt" ;;
    esac
  done
done
