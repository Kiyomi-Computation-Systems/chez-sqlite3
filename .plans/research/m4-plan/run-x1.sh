#!/bin/sh
# Runs x1-ffi-load.sps on one library (the M4 plan, section 8).
#
#   scripts/guix-env sh -c 'd=$(mktemp -d "$PWD/build/m4plan/x1.XXXXXX") && \
#     sh .plans/research/m4-plan/run-x1.sh "$d" LABEL LIBRARY INCLUDE-DIR OUT'
#
# Run inside the container, from the worktree's root. SCRATCH is a fresh
# directory, named by an absolute path. It builds ext.so and ext-failing.so
# from ext.c against INCLUDE-DIR, then writes into OUT:
#   x1-gate-LABEL.txt, x1-gate-leak-LABEL.txt, x1-gate-none-LABEL.txt
#                         the probe's output in each gate mode, under
#                         Valgrind with the memory gate's flags, and the
#                         exit status Valgrind gave
#   x1-gate-valgrind-LABEL.txt, x1-gate-leak-valgrind-LABEL.txt,
#   x1-gate-none-valgrind-LABEL.txt
#                         Valgrind's logs, with SCRATCH written as "DIR"
#   x1-fifo-LABEL.txt     both FIFO modes, each with a fresh FIFO and a
#                         writer from outside the process after 1.5 s, each
#                         under a 30 s timeout
# Given a sixth argument, fifo, it runs the FIFO modes alone.
set -u
[ $# -eq 5 ] || [ $# -eq 6 ] ||
  { echo "usage: run-x1.sh SCRATCH LABEL LIBRARY INCLUDE-DIR OUT [fifo]" >&2; exit 2; }
d=$1; label=$2; lib=$3; inc=$4; out=$5; only=${6:-}
here=.plans/research/m4-plan
mkdir -p "$out"
$CC -O2 -Wall -Werror -shared -fPIC -I"$inc" -o "$d/ext.so" "$here/ext.c" || exit 1
$CC -O2 -Wall -Werror -shared -fPIC -I"$inc" -DEXT_FAILING -o "$d/ext-failing.so" "$here/ext.c" || exit 1

gates="gate gate-leak gate-none"
[ "$only" = fifo ] && gates=
for m in $gates; do
  valgrind --command-line-only=yes "--log-file=$d/$m.valgrind" --error-exitcode=9 \
    --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite \
    "$CHEZ" --program "$here/x1-ffi-load.sps" "$lib" "$d" "$m" >"$out/x1-$m-$label.txt" 2>&1
  echo "(valgrind-exit $?)" >>"$out/x1-$m-$label.txt"
  sed "s|$d|DIR|g; s|$PWD|ROOT|g" "$d/$m.valgrind" >"$out/x1-$m-valgrind-$label.txt"
done

: >"$out/x1-fifo-$label.txt"
for m in fifo-plain fifo-safe; do
  rm -f "$d/fifo.so"
  mkfifo "$d/fifo.so"
  ( sleep 1.5; timeout 10 sh -c 'echo >"$1"' sh "$d/fifo.so" ) &
  timeout 30 "$CHEZ" --program "$here/x1-ffi-load.sps" "$lib" "$d" "$m" >>"$out/x1-fifo-$label.txt" 2>&1
  echo "(exit $m $?)" >>"$out/x1-fifo-$label.txt"
  wait
done
