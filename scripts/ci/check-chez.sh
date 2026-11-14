#!/bin/sh
# scripts/ci/check-chez.sh PREFIX [--nothreads]
#
# Fails unless PREFIX/bin/scheme is the Chez a CI job needs: the floor that
# packaging/floors.sexp holds (ADR-0008), read by scripts/ci/floor.sh, and
# threaded, or not threaded with --nothreads. It asks the installed scheme
# for (scheme-version-number) and (threaded?), and compares the answer
# whole. scripts/ci/build-chez.sh runs it on what it built, and every job
# runs it again after restoring Chez from a cache, so a cache that serves
# another build is caught before any check runs on it.
#
# It prints one line and exits 0, or says what is wrong on stderr and exits
# 1, or 2 on a usage error.
set -eu

usage() {
  echo "usage: check-chez.sh PREFIX [--nothreads]" >&2
  exit 2
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
prefix=$1
want=yes
mode=threaded
if [ "$#" -eq 2 ]; then
  [ "$2" = "--nothreads" ] || usage
  want=no
  mode="without threads"
fi

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
version=$(sh "$here/floor.sh" chez) || {
  echo "check-chez.sh: no Chez floor to check against" >&2
  exit 1
}

scheme=$prefix/bin/scheme
[ -x "$scheme" ] || {
  echo "check-chez.sh: $scheme is not an executable file" >&2
  exit 1
}

work=$(mktemp -d "${TMPDIR:-/tmp}/check-chez.XXXXXX")
trap 'rm -rf "$work"' EXIT

# scheme-version-number answers three values, major, minor and patch; a
# threaded build answers #t to (threaded?).
probe=$work/probe.ss
cat >"$probe" <<'EOF'
(let-values (((major minor patch) (scheme-version-number)))
  (display (list major minor patch (if (threaded?) 'yes 'no))))
EOF
asked=$("$scheme" --script "$probe") || {
  echo "check-chez.sh: $scheme could not run the probe" >&2
  exit 1
}
expected="($(printf '%s' "$version" | tr . ' ') $want)"
if [ "$asked" != "$expected" ]; then
  echo "check-chez.sh: $scheme answers $asked, but (scheme-version-number) and (threaded?) should answer $expected" >&2
  exit 1
fi
echo "check-chez.sh: $scheme is Chez $version, $mode: $asked"
