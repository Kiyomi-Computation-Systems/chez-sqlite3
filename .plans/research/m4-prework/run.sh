#!/bin/sh
# run.sh LABEL LIBRARY [INCLUDE-DIR]: M4's pre-work probes on one libsqlite3.
#
# Run it in the Guix container, from the repository's root, e.g.
#   scripts/guix-env sh .plans/research/m4-prework/run.sh floor \
#     "$PWD/build/m3-floor/lib/libsqlite3.so.0" "$PWD/build/m3-floor/include"
#
# It writes, into OUT (default .plans/research/m4-prework/out):
#   varargs-LABEL.txt    varargs.sps's output, mode all
#   census-LABEL.txt     census.sps's output
# and, given INCLUDE-DIR, the header that describes LIBRARY:
#   constants-LABEL.txt  constants.c, compiled against that header, on each
#                        probe's output
#   oracle-LABEL.txt     varargs.c, compiled against that header and linked
#                        to LIBRARY
#   compare-LABEL.txt    the probe's varargs lines against the oracle's, and
#                        its plain lines against the oracle's round trips,
#                        verdicts and unknown op
# Binaries go to build/m4pre/bin. It exits 1 when a probe, a check or a
# comparison fails, after writing everything it can.
#
# CHEZ and CC name Chez and the C compiler, as the container exports them.
set -u
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { echo "usage: run.sh LABEL LIBRARY [INCLUDE-DIR]" >&2; exit 2; }
label=$1
lib=$2
inc=${3:-}
here=.plans/research/m4-prework
out=${OUT:-$here/out}
bin=build/m4pre/bin
chez=${CHEZ:-scheme}
cc=${CC:-cc}
mkdir -p "$out" "$bin"
status=0

"$chez" --program "$here/varargs.sps" "$lib" >"$out/varargs-$label.txt" 2>&1 || status=1
"$chez" --program "$here/census.sps" "$lib" >"$out/census-$label.txt" 2>&1 || status=1

if [ -n "$inc" ]; then
  "$cc" -Wall -Wextra -Werror -I"$inc" -o "$bin/constants-$label" "$here/constants.c" || exit 1
  {
    echo ";; varargs.sps"
    "$bin/constants-$label" <"$out/varargs-$label.txt" || status=1
    echo ";; census.sps"
    "$bin/constants-$label" <"$out/census-$label.txt" || status=1
  } >"$out/constants-$label.txt"

  "$cc" -Wall -Wextra -Werror -I"$inc" -o "$bin/varargs-$label" "$here/varargs.c" "$lib" \
    -Wl,-rpath,"$(dirname "$lib")" || exit 1
  "$bin/varargs-$label" >"$out/oracle-$label.txt" 2>&1 || status=1

  work=build/m4pre/compare-$label
  mkdir -p "$work"
  sed -n 's/^(varargs /(/p' "$out/varargs-$label.txt" >"$work/varargs"
  sed -n 's/^(plain /(/p' "$out/varargs-$label.txt" >"$work/plain"
  sed -n 's/^(c /(/p' "$out/oracle-$label.txt" >"$work/c"
  grep -E '^\((round-trip|verdict|unknown-op) ' "$work/c" >"$work/c-round-trips"
  {
    for pair in "varargs c" "plain c-round-trips"; do
      set -- $pair
      n=$(grep -c '' "$work/$1")
      if [ "$n" -gt 0 ] && cmp -s "$work/$1" "$work/$2"; then
        echo "($1 identical-to-$2 $n lines)"
      else
        echo "($1 differs-from-$2 $n lines)"
        diff "$work/$2" "$work/$1"
        status=1
      fi
    done
  } >"$out/compare-$label.txt"
fi
exit $status
