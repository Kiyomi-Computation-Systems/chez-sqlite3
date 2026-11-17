#!/bin/sh
# Runs M4's plan review's three probes, rv1.c, rv2.sps and rv3.c, and the
# research's check of the two 3.54.1 builds (the M4 plan, section 8).
#
#   scripts/guix-env sh -c 'd=$(mktemp -d "$PWD/build/m4plan/review.XXXXXX") && \
#     sh .plans/research/m4-plan/run-review.sh "$d" "$PWD/.plans/research/m4-plan/out"'
#
# Run inside the container, from the worktree's root, after make deps.
# SCRATCH is a fresh directory, named by an absolute path. Into OUT:
#   rv1-LABEL.txt   rv1 on floor-3.45.1, guix-3.53.1 and current-3.54.1, run
#                   from SCRATCH/LABEL with its files in SCRATCH/LABEL/DIR,
#                   ext.so built there from ext.c against the label's header
#   rv2.txt         rv2.sps on the tree's conditions library
#   rv3-LABEL.txt   rv3 with a bare name, from a working directory that does
#                   not hold ext.so: without LD_LIBRARY_PATH, then with it
#                   naming the directory that does
#   check-sqlite-current-3.54.1.txt, check-sqlite-current-fts5-3.54.1.txt
#                   scripts/ci/check-sqlite.sh --current on each 3.54.1
#                   build, with its lane's env, the worktree written ROOT
set -u
[ $# -eq 2 ] || { echo "usage: run-review.sh SCRATCH OUT" >&2; exit 2; }
d=$1; out=$2
here=$PWD/.plans/research/m4-plan
case $d in /*) ;; *) echo "run-review.sh: SCRATCH must be absolute" >&2; exit 2 ;; esac
mkdir -p "$out"
status=0

for lib in floor guix current; do
  case $lib in
    guix)  inc=$GUIX_ENVIRONMENT/include; libdir=$GUIX_ENVIRONMENT/lib; tag=guix-3.53.1 ;;
    floor) inc=$PWD/build/m3-floor/include; libdir=$PWD/build/m3-floor/lib; tag=floor-3.45.1 ;;
    current) inc=$PWD/build/m4plan/current/include; libdir=$PWD/build/m4plan/current/lib
             tag=current-3.54.1 ;;
  esac
  w=$d/$tag
  mkdir -p "$w/DIR" "$w/elsewhere"
  $CC -O2 -Wall -Werror -shared -fPIC -I"$inc" -o "$w/DIR/ext.so" "$here/ext.c" || exit 1
  for p in rv1 rv3; do
    $CC -O2 -Wall -Werror -I"$inc" -o "$w/$p" "$here/$p.c" "$libdir/libsqlite3.so.0" \
      -Wl,-rpath,"$libdir" || exit 1
  done
  ( cd "$w" && ./rv1 DIR ) >"$out/rv1-$tag.txt" 2>&1 || status=1
  {
    for name in ext.so ext; do
      echo "(working directory: elsewhere, no LD_LIBRARY_PATH)"
      ( cd "$w/elsewhere" && env -u LD_LIBRARY_PATH ../rv3 "$name" )
      echo "(working directory: elsewhere, LD_LIBRARY_PATH: DIR)"
      ( cd "$w/elsewhere" && LD_LIBRARY_PATH="$w/DIR" ../rv3 "$name" )
    done
  } 2>&1 | sed "s|$w|W|g" >"$out/rv3-$tag.txt"
done

"$CHEZ" --libdirs "$PWD/src" --program "$here/rv2.sps" >"$out/rv2.txt" 2>&1 || status=1

for v in current current-fts5; do
  CHEZ_SQLITE3_LIBRARY=$PWD/build/m4plan/$v/lib/libsqlite3.so.0 \
    C_INCLUDE_PATH=$PWD/build/m4plan/$v/include \
    sh scripts/ci/check-sqlite.sh "$PWD/build/m4plan/$v" --current >"$d/cs-$v.txt" 2>&1
  echo "(exit $?)" >>"$d/cs-$v.txt"
  sed "s|$PWD|ROOT|g" "$d/cs-$v.txt" >"$out/check-sqlite-$v-3.54.1.txt"
done
exit $status
