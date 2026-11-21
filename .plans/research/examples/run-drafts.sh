#!/bin/sh
# Runs each program of DIR on three libraries, each in a fresh directory, twice, and says
# whether each printed the same on all three, and the same the second time. The floor's
# build is build/m3-floor (3.45.1), a current one build/m4-current (3.54.1); Guix's is the
# container's own. Usage, from the worktree root, inside scripts/guix-env:
#   sh .plans/research/examples/run-drafts.sh examples
set -u
root=$PWD
dir=$1
out=$root/build/examples-probe/out
rm -rf "$out"; mkdir -p "$out"
for lib in floor guix current; do
  case $lib in
    floor) l=$root/build/m3-floor/lib/libsqlite3.so.0 ;;
    guix) l=$CHEZ_SQLITE3_LIBRARY ;;
    current) l=$root/build/m4-current/lib/libsqlite3.so.0 ;;
  esac
  for f in "$root/$dir"/*.sps; do
    n=$(basename "$f" .sps)
    w=$out/$lib-$n.d; mkdir -p "$w"
    for i in 1 2; do
      (cd "$w" && CHEZ_SQLITE3_LIBRARY=$l "$CHEZ" --libdirs "$root/src" --program "$f" >"$out/$lib-$n.$i.out" 2>"$out/$lib-$n.$i.err"; echo "exit $?" >>"$out/$lib-$n.$i.err")
    done
    echo "$lib $n: $(cat "$out/$lib-$n.1.err" | tr '\n' ' ') rerun-same=$(cmp -s "$out/$lib-$n.1.out" "$out/$lib-$n.2.out" && echo yes || echo NO) left=$(ls "$w" | tr '\n' ' ')"
  done
done
for f in "$root/$dir"/*.sps; do
  n=$(basename "$f" .sps)
  if cmp -s "$out/floor-$n.1.out" "$out/guix-$n.1.out" && cmp -s "$out/floor-$n.1.out" "$out/current-$n.1.out"; then echo "$n: same on all three"; else echo "$n: DIFFERS"; fi
done
