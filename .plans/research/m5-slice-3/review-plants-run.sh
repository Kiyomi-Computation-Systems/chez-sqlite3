#!/bin/sh
# tests/check-ci.sh on every plant under build/m5s3/r2/rvp/p, the review's and
# review-plants-extra.py's, each from that directory, so a problem names its
# plant by a path that is the same wherever the tree is. Each answer, its exit
# status first, goes to out-AWK/NAME beside p/. From the repository root:
#
#   scripts/guix-env sh .plans/research/m5-slice-3/review-plants-run.sh gawk
#   docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/w" -w /w ubuntu:24.04 \
#     sh .plans/research/m5-slice-3/review-plants-run.sh mawk
#   diff -r build/m5s3/r2/rvp/out-gawk build/m5s3/r2/rvp/out-mawk
#
# It fails unless the awk on the path is AWK.
set -u
want=$1
root=$(pwd)
p=$root/build/m5s3/r2/rvp/p
out=$root/build/m5s3/r2/rvp/out-$want
got=$(awk -W version 2>/dev/null | head -n 1; awk --version 2>/dev/null | head -n 1)
case $got in
  *[Gg][Nn][Uu]\ [Aa]wk*) have=gawk ;;
  *mawk*) have=mawk ;;
  *) have=unknown ;;
esac
[ "$have" = "$want" ] || { echo "run: the awk here is $have, not $want" >&2; exit 2; }
rm -rf "$out"
mkdir -p "$out"
for d in "$p"/*/; do
  n=$(basename "$d")
  (cd "$p" && CHECK_CI_ROOT=$root sh "$root/tests/check-ci.sh" "$n") >"$out/$n" 2>&1
  st=$?
  { echo "exit $st"; cat "$out/$n"; } >"$out/$n.tmp" && mv "$out/$n.tmp" "$out/$n"
done
echo "run: $(ls "$p" | wc -l) plants under $want ($(echo "$got" | head -n 1))"
