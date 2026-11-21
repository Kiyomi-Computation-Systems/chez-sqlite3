#!/bin/sh
# live-check.sh BASE [TAG]: whether the docs site at BASE, a URL ending in /, is TAG's,
# v0.1.0 unless given. The release's step 7 runs it on the host against the deployed site,
# https://kiyomi-computation-systems.github.io/chez-sqlite3/, once the tag's Pages run is
# green. Three clauses, each named when it fails:
#
#   pages  each page and the stylesheet answers 200;
#   links  a link names a repository file at TAG, blob/TAG/, and every link into the
#          repository is one, or the repository's home, or its clone URL;
#   clone  the quick start, index.html, holds git clone, and each is the tag's clone line.
#
# Exits 0 naming the site, 1 when a clause fails, 2 on a usage error. It writes only under
# a directory mktemp makes, in TMPDIR when set, and removes it.
set -u

usage() { echo "usage: live-check.sh BASE [TAG], BASE a URL ending in /" >&2; exit 2; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
base=$1
tag=${2:-v0.1.0}
case $base in http://*/ | https://*/) ;; *) usage ;; esac
case $tag in v[0-9]*.[0-9]*.[0-9]*) ;; *) usage ;; esac

repo=https://github.com/Kiyomi-Computation-Systems/chez-sqlite3
pages="index.html examples.html finding-sqlite.html libraries.html reference.html style.css"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/live-check.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT
fail=0

# pages: each answers 200, no redirect followed.
for p in $pages; do
  code=$(curl -s --max-time 30 -o "$tmp/$p" -w '%{http_code}' "$base$p")
  [ "$code" = 200 ] || { echo "live-check: pages: $p answered $code, not 200"; fail=1; }
done

# links: every link into the repository, in every page, cut at a quote, a bracket or a space.
cat "$tmp"/*.html 2>/dev/null \
  | grep -o 'https://github\.com/Kiyomi-Computation-Systems/chez-sqlite3[^"<> ]*' \
  | sort -u > "$tmp/links"
awk -v repo="$repo" -v tag="$tag" '
  $0 == repo || $0 == repo ".git" { next }
  index($0, repo "/blob/" tag "/") == 1 { files++; next }
  { print "live-check: links: not a file at " tag ": " substr($0, length(repo) + 2); bad = 1 }
  END {
    if (!files) print "live-check: links: no link names a repository file at blob/" tag "/"
    exit (bad || !files)
  }' "$tmp/links" || fail=1

# clone: each git clone of the quick start, cut at the next tag or the line's end.
want="git clone --branch $tag $repo.git"
grep -o 'git clone[^<]*' "$tmp/index.html" 2>/dev/null > "$tmp/clones"
awk -v want="$want" -v tag="$tag" '
  $0 != want {
    print "live-check: clone: this git clone is not --branch " tag ":"
    print "  " $0
    bad = 1
  }
  END {
    if (NR == 0) print "live-check: clone: the quick start holds no git clone"
    exit (bad || NR == 0)
  }' "$tmp/clones" || fail=1

[ $fail = 0 ] && echo "live-check: $base is $tag's site"
exit $fail
