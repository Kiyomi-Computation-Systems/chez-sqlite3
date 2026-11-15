#!/bin/sh
# Builds and runs the concurrency probes against one library. Run it inside
# the Guix container, from the repository root:
#
#   scripts/guix-env sh .plans/research/m3-plan/concurrency/run.sh LIB [check]
#
# LIB is one of:
#   guix              Guix's 3.53.1, the container's own
#   floor             the floor, 3.45.1, at build/m3-floor (CI's floor build)
#   floor-nanosleep0  the floor's sqlite3.c built as CI builds it, plus
#                     -DHAVE_NANOSLEEP=0; busy.c only
#
# Without `check`, the outputs are written beside this script. With `check`,
# they are written to a fresh directory under build/m3rc/, and every output
# that isn't a timing is compared byte for byte with the one beside this
# script; the script exits 1 on a difference.
#
# Scratch, databases included, goes in a fresh directory under the
# git-ignored build/m3rc/ on every run (M3RC_SCRATCH names another directory
# under the repository root). C probes are compiled against the
# library's own header, linked to that .so by its directory (-rpath), and
# refuse to run unless the runtime version and source id equal the header's.
set -eu

here=.plans/research/m3-plan/concurrency
[ -f "$here/run.sh" ] || { echo "run.sh: run it from the repository root" >&2; exit 2; }
[ -n "${GUIX_ENVIRONMENT:-}" ] || { echo "run.sh: run it inside scripts/guix-env" >&2; exit 2; }

lib=${1:-}
mode=${2:-write}
root=${M3RC_SCRATCH:-build/m3rc}
mkdir -p "$root"
run=$(mktemp -d "$PWD/$root/run-$lib.XXXXXX")

case $lib in
  guix)
    inc=$GUIX_ENVIRONMENT/include libdir=$GUIX_ENVIRONMENT/lib tag=guix-3.53.1 ;;
  floor)
    inc=$PWD/build/m3-floor/include libdir=$PWD/build/m3-floor/lib tag=floor-3.45.1 ;;
  floor-nanosleep0)
    inc=$PWD/build/m3-floor/include libdir=$run/lib tag=floor-3.45.1-nanosleep0
    mkdir "$libdir"
    "$CC" -shared -fPIC -O2 -DSQLITE_THREADSAFE=1 -DHAVE_NANOSLEEP=0 -Wl,-z,defs \
      -o "$libdir/libsqlite3.so.0" \
      build/m3-floor-dl/sqlite-autoconf-3450100/sqlite3.c -lpthread -lm ;;
  *)
    echo "usage: run.sh guix|floor|floor-nanosleep0 [check]" >&2; exit 2 ;;
esac

case $mode in
  write) out=$here ;;
  check) out=$run/out; mkdir "$out" ;;
  *) echo "usage: run.sh LIB [check]" >&2; exit 2 ;;
esac

if [ "$lib" = floor-nanosleep0 ]; then
  probes=busy traps=
else
  probes="interrupt busy sweep"
  traps="trap-interrupt-busy-wait trap-interrupt-sticks trap-interrupt-rollback trap-deferred-upgrade trap-journal-mode-stale"
fi

build() {
  "$CC" -O2 -Wall -Wextra -Wno-unused-function -I"$inc" -o "$run/$1" "$here/$1.c" \
    -L"$libdir" -l:libsqlite3.so.0 -Wl,-rpath,"$libdir" -lpthread
}

compared=
if [ "$lib" != floor-nanosleep0 ]; then
  build options
  "$run/options" > "$out/options-$tag.txt"
  compared="$compared options-$tag.txt"
fi

for p in $probes; do
  build "$p"
  mkdir "$run/$p.d"
  echo "run.sh: $p on $tag" >&2
  timeout 900 "$run/$p" "$run/$p.d" "$out/$p-timing-$tag.txt" > "$out/$p-$tag.txt"
  compared="$compared $p-$tag.txt"
done

for p in $traps; do
  build "$p"
  mkdir "$run/$p.d"
  echo "run.sh: $p on $tag" >&2
  timeout 120 "$run/$p" "$run/$p.d" > "$out/$p-$tag.txt"
  compared="$compared $p-$tag.txt"
done

if [ "$lib" != floor-nanosleep0 ]; then
  sid=$(sed -n 's/^#define SQLITE_SOURCE_ID *"\(.*\)"$/\1/p' "$inc/sqlite3.h")
  mkdir "$run/chez.d"
  echo "run.sh: chez-interrupt on $tag" >&2
  timeout 900 "$CHEZ" --program "$here/chez-interrupt.sps" "$libdir/libsqlite3.so.0" "$sid" \
    "$run/chez.d" "$out/chez-interrupt-timing-$tag.txt" > "$out/chez-interrupt-$tag.txt"
  compared="$compared chez-interrupt-$tag.txt"
fi

if [ "$mode" = check ]; then
  status=0
  for f in $compared; do
    if cmp -s "$out/$f" "$here/$f"; then
      echo "same: $f"
    else
      echo "DIFFERENT: $f"
      diff "$here/$f" "$out/$f" || true
      status=1
    fi
  done
  exit $status
fi
echo "run.sh: wrote$compared, and the timing files" >&2
