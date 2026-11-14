#!/bin/sh
# scripts/ci/build-sqlite.sh PREFIX [--current]
#
# Builds SQLite from sqlite.org's source and installs it into PREFIX, for
# .github/workflows/ci.yml's floor and current lanes (ADR-0003, decision 3:
# CI tests the floor against an amalgamation it compiles itself). Without
# --current it builds the floor, the one packaging/floors.sexp holds
# (ADR-0008), read by scripts/ci/floor.sh, which fails closed on a file that
# does not give exactly one well-formed SQLite version. With --current it
# builds the pinned current release below and reads no floors file. Nothing
# a workflow says, an env key or a matrix value, can change which: the
# version, its year and its pins are set here, whatever the environment
# holds.
#
# It downloads sqlite-autoconf-NNNNNNN.tar.gz, whose number is computed
# from the version, X then Y and Z in two digits each then 00, and checks
# its SHA3-256 against the role's pin before anything is unpacked. It
# unpacks only sqlite3.c, sqlite3.h and sqlite3ext.h, and checks sqlite3.c's
# SHA3-256 against the one sqlite.org's release log publishes. It compiles
# the amalgamation once, with SQLite's defaults and these flags:
#
#   -shared -fPIC           a shared object, PREFIX/lib/libsqlite3.so.0,
#                           named as discovery would name it
#   -O2                     SQLite's usual optimisation; it changes no option
#   -DSQLITE_THREADSAFE=1   serialized, SQLite's default, written so the
#                           build depends on no default: the load refuses 0
#                           (ADR-0010)
#   -Wl,-z,defs             an unresolved symbol fails the build, not a load
#   -lpthread -lm           SQLite's documented link line
#
# and copies the two headers into PREFIX/include. Afterwards
# scripts/ci/check-sqlite.sh checks what was built, with
# CHEZ_SQLITE3_LIBRARY and C_INCLUDE_PATH naming PREFIX's library and
# headers for that call only: its version, its source id and every compile
# option, whole. A build that came out other than this script asks is no
# build, and is never saved to a cache.
#
# PREFIX must be an absolute path. Nothing is installed outside PREFIX. Of
# the environment it reads CC, the C compiler, cc by default; CHEZ, the Chez
# check-sqlite.sh reads the library with; TMPDIR, for its work directory;
# and C_INCLUDE_PATH, which the check gets after PREFIX/include. None of
# them names what is built.
#
# The pins are keyed by role, not by version: the floor's version is never
# written in scripts/ci (make check-floors), so its pins are the floor's,
# whatever version packaging/floors.sexp gives. Raising the floor, or
# changing current_version, is a reviewed change of that role's pins:
#   year      the directory of sqlite.org the archive is in;
#   archive   the SHA3-256 of sqlite-autoconf-NNNNNNN.tar.gz, as fetched
#             and read by two implementations, and as sqlite.org's download
#             page lists it while the release is current;
#   source    the SHA3-256 of its sqlite3.c, as the release log at
#             https://sqlite.org/releaselog/X_Y_Z.html publishes it;
# and check-sqlite.sh's source id and options move with them. Until the
# pins move, the new floor's download fails, or fails its SHA3-256 check.
set -eu

usage() {
  echo "usage: build-sqlite.sh PREFIX [--current]" >&2
  exit 2
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
prefix=$1
role=floor
if [ "$#" -eq 2 ]; then
  [ "$2" = "--current" ] || usage
  role=current
fi

case $prefix in
  /?*) ;;
  *) echo "build-sqlite.sh: PREFIX must be an absolute path, not '$prefix'" >&2; exit 2 ;;
esac

fail() {
  printf 'build-sqlite.sh: %s\n' "$*" >&2
  exit 1
}

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# current_version: the current SQLite, built with --current: sqlite.org's
# newest release on 2026-11-14, chosen that day (the M1 plan, section 7). It
# is no floor, so it is not in packaging/floors.sexp.
current_version=3.54.1

# The pins of each build, by role.
floor_year=2024
floor_archive=a54395aa2cf76b5b973fa420715b6108afedc4d8c0209c763fd2c1b517f8ad9f
floor_source=0474604df9e1b69a5544295dd046aad954749279780d557da80f44b958100295
current_year=2026
current_archive=b6ced585c750916b1052667239a12c25a7ff34e7f06e1e6e01ecb0427657d9c4
current_source=e2b869d3003b33c942b7dd7063604fbc53553e1b66609570df39b9b7b558ee81

if [ "$role" = current ]; then
  version=$current_version
  year=$current_year
  archive_pin=$current_archive
  source_pin=$current_source
else
  version=$(sh "$here/floor.sh" sqlite) || fail "no SQLite floor to build"
  year=$floor_year
  archive_pin=$floor_archive
  source_pin=$floor_source
fi

# floor.sh gives three naturals with no leading zero; so is current_version.
major=${version%%.*}
rest=${version#*.}
minor=${rest%%.*}
patch=${rest#*.}
name=sqlite-autoconf-$(printf '%d%02d%02d00' "$major" "$minor" "$patch")
url=https://sqlite.org/$year/$name.tar.gz

# The tools, each named when it is missing, before anything is downloaded.
cc=${CC:-cc}
missing=
need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "build-sqlite.sh: cannot find $1, which $2" >&2
    missing=yes
  fi
}
need curl "downloads the archive"
need openssl "checks the SHA3-256 of the archive and of its sqlite3.c"
need tar "unpacks the archive"
need "$cc" "is the C compiler CC names, cc by default, and compiles sqlite3.c"
[ -z "$missing" ] || exit 1

work=$(mktemp -d "${TMPDIR:-/tmp}/build-sqlite.XXXXXX")
trap 'rm -rf "$work"' EXIT

# sha3_of FILE: the SHA3-256 of FILE, in hex.
sha3_of() {
  digest=$(openssl dgst -sha3-256 -r "$1") || fail "openssl could not read $1"
  printf '%s\n' "$digest" | awk '{ print $1 }'
}

archive=$work/$name.tar.gz
if ! curl -fsSL --retry 3 -o "$archive" "$url"; then
  if [ "$role" = current ]; then
    fail "could not download $url: if current_version was changed, current_year, current_archive and current_source in this script may still be the old release's"
  fi
  fail "could not download $url: if the SQLite floor in packaging/floors.sexp was raised, floor_year, floor_archive and floor_source in this script may still be the old floor's"
fi

got=$(sha3_of "$archive") || exit 1
[ "$got" = "$archive_pin" ] ||
  fail "$name.tar.gz has SHA3-256 $got, but ${role}_archive in this script pins $archive_pin"

tar xzf "$archive" -C "$work" "$name/sqlite3.c" "$name/sqlite3.h" "$name/sqlite3ext.h"
src=$work/$name

got=$(sha3_of "$src/sqlite3.c") || exit 1
[ "$got" = "$source_pin" ] ||
  fail "$name/sqlite3.c has SHA3-256 $got, but ${role}_source in this script pins $source_pin, the digest sqlite.org's release log publishes"

mkdir -p "$prefix/lib" "$prefix/include"
"$cc" -shared -fPIC -O2 -DSQLITE_THREADSAFE=1 -Wl,-z,defs -o "$prefix/lib/libsqlite3.so.0" \
  "$src/sqlite3.c" -lpthread -lm
cp "$src/sqlite3.h" "$src/sqlite3ext.h" "$prefix/include/"

# Check what was built, with the lane's env for this call only.
if [ "$role" = current ]; then
  CHEZ_SQLITE3_LIBRARY=$prefix/lib/libsqlite3.so.0 \
    C_INCLUDE_PATH=$prefix/include${C_INCLUDE_PATH:+:$C_INCLUDE_PATH} \
    sh "$here/check-sqlite.sh" "$prefix" --current
else
  CHEZ_SQLITE3_LIBRARY=$prefix/lib/libsqlite3.so.0 \
    C_INCLUDE_PATH=$prefix/include${C_INCLUDE_PATH:+:$C_INCLUDE_PATH} \
    sh "$here/check-sqlite.sh" "$prefix"
fi
echo "build-sqlite.sh: SQLite $version built into $prefix"
