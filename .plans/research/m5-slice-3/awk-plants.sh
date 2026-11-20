#!/bin/sh
# The slice's check-ci plants, each in a copy of .github/workflows under
# build/m5s3/awk-plants/NAME/, run through tests/check-ci.sh by two awks:
# the container's gawk, and mawk, which CI's Ubuntu runs. From the
# repository root:
#
#   scripts/guix-env sh .plans/research/m5-slice-3/awk-plants.sh build
#   scripts/guix-env sh .plans/research/m5-slice-3/awk-plants.sh run gawk
#   docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/w" -w /w ubuntu:24.04 \
#     sh .plans/research/m5-slice-3/awk-plants.sh run mawk
#   scripts/guix-env sh .plans/research/m5-slice-3/awk-plants.sh compare
#
# build makes the copies, with GNU sed; run AWK writes each one's check, its
# exit status then its output, to NAME.AWK, and fails unless the awk on the
# path is AWK; compare prints each plant's problems, and exits 1 unless every
# plant failed, the control passed, and the two awks wrote the same bytes.
set -u
root=$(pwd)
p=$root/build/m5s3/awk-plants

# plant NAME FILE SED-SCRIPT: a copy whose FILE, ci.yml or pages.yml, is
# edited by the script, which must change it.
plant() {
  mkdir "$p/$1"
  cp .github/workflows/ci.yml .github/workflows/pages.yml "$p/$1/"
  sed "$3" ".github/workflows/$2" >"$p/$1/$2"
  if cmp -s ".github/workflows/$2" "$p/$1/$2"; then echo "plant $1 changed nothing"; exit 1; fi
}

case ${1:-} in
build)
  mkdir "$p" || { echo "awk-plants: $p exists; remove it first" >&2; exit 2; }
  mkdir "$p/control"
  cp .github/workflows/ci.yml .github/workflows/pages.yml "$p/control/"
  mkdir "$p/third-file"
  cp .github/workflows/ci.yml .github/workflows/pages.yml "$p/third-file/"
  echo 'on: push' >"$p/third-file/other.yml"
  mkdir "$p/pages-link"
  cp .github/workflows/ci.yml "$p/pages-link/"
  cp .github/workflows/pages.yml "$p/pages-link/real-pages.yml.tmp"
  ln -s real-pages.yml.tmp "$p/pages-link/pages.yml"
  plant pages-changed pages.yml 's/tags: \["v\*"\]/tags: ["*"]/'
  plant pages-dropped pages.yml '/^    needs: build$/d'
  plant pages-added pages.yml 's/^      id-token: write$/&\n      contents: write/'
  plant pages-moved pages.yml '/^      pages: write$/{N;s/\(.*\)\n\(.*\)/\2\n\1/}'
  plant pages-comment-tab pages.yml 's/^# One deployment/#\tOne deployment/'
  plant pages-comment-ls pages.yml 's/^# One deployment/# One\xe2\x80\xa8deployment/'
  plant ci-comment-tab ci.yml 's/^# One workflow/#\tOne workflow/'
  plant site-dropped ci.yml '/^  # The docs site/,$d'
  plant site-check-dropped ci.yml \
    '/^      - name: Gate the site$/,/^        run: make check-site$/d'
  plant site-check-moved ci.yml \
    's/^        run: make check-site$/MOVED/
     s/^        run: make site$/        run: make check-site/
     s/^MOVED$/        run: make site/'
  plant site-other-chez ci.yml \
    '/^      - name: Build the site$/,/^        run: make site$/ s/CHEZ: chezscheme/CHEZ: scheme/'
  plant site-cache ci.yml '/^      - name: Get chez-cmark-gfm as Akku.lock pins it$/i\
      - name: Restore\
        uses: actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0\
        with:\
          path: x\
          key: y\
'
  echo "awk-plants: built $(ls -d "$p"/*/ | wc -l) copies"
  ;;
run)
  want=${2:?run needs an awk name}
  got=$(awk -W version 2>/dev/null | head -n 1; awk --version 2>/dev/null | head -n 1)
  case $got in
    *[Gg][Nn][Uu]\ [Aa]wk*) have=gawk ;;
    *mawk*) have=mawk ;;
    *) have=unknown ;;
  esac
  [ "$have" = "$want" ] ||
    { echo "awk-plants: the awk here is $have, not $want: $got" >&2; exit 2; }
  for d in "$p"/*/; do
    n=$(basename "$d")
    # Run from the plants' directory, so each problem names its copy by a
    # path that is the same wherever the tree is.
    (cd "$p" && CHECK_CI_ROOT=$root sh "$root/tests/check-ci.sh" "$n") >"$p/$n.$want" 2>&1
    st=$?
    { echo "exit $st"; cat "$p/$n.$want"; } >"$p/$n.$want.tmp" && mv "$p/$n.$want.tmp" "$p/$n.$want"
  done
  echo "awk-plants: ran $(ls -d "$p"/*/ | wc -l) copies under $want ($got)"
  ;;
compare)
  bad=0
  for d in "$p"/*/; do
    n=$(basename "$d")
    if ! cmp -s "$p/$n.gawk" "$p/$n.mawk"; then echo "DIFFER $n"; bad=1; fi
    first=$(head -n 1 "$p/$n.gawk")
    case $n:$first in
      control:"exit 0" | *:"exit 1") ;;
      *) echo "WRONG $n: $first"; bad=1 ;;
    esac
    echo "--- $n: $first"
    sed -n '2,$p' "$p/$n.gawk" | sed "s|$p/||"
  done
  [ "$bad" -eq 0 ] && echo "awk-plants: every plant failed, the control passed, gawk and mawk agree"
  exit "$bad"
  ;;
*)
  echo "usage: awk-plants.sh build | run gawk|mawk | compare" >&2
  exit 2
  ;;
esac
