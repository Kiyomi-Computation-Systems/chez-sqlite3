#!/bin/sh
# Reproduces, on Linux, the Mac's S3 case in tests/test-transaction-nomem.sps:
# SQLite 3.54.1's amalgamation compiled six ways, the suite run on each.
#
#   defaults     CI's current lane's line (scripts/ci/build-sqlite.sh)
#   brew-all     that line plus every option Homebrew's 3.54.1 lists and the
#                lane's lacks (census-mac-brew-3.54.1.txt, in M4's pre-work)
#   brew-no-mm   brew-all without -DSQLITE_ENABLE_MEMORY_MANAGEMENT
#   mm           the lane's line plus -DSQLITE_ENABLE_MEMORY_MANAGEMENT alone
#   stat4        the lane's line plus -DSQLITE_ENABLE_STAT4 alone
#   mm-page64k   mm plus -DSQLITE_DEFAULT_PAGE_SIZE=65536, which the PR's
#                review found takes S2's, R3's, R4's and [F]'s NOMEM away
#
# Usage, inside scripts/guix-env, from the repository's root:
#   sh .plans/research/m3-mac/memory-management.sh AMALGAMATION-DIR [SUITE]
# AMALGAMATION-DIR holds sqlite3.c, sqlite3.h and sqlite3ext.h from
# sqlite-autoconf-3540100.tar.gz, downloaded on the host and checked against
# build-sqlite.sh's current_archive and current_source pins. SUITE defaults
# to tests/test-transaction-nomem.sps. Builds go under build/s3-brew/.
set -eu
a=$1
suite=${2:-tests/test-transaction-nomem.sps}
b=build/s3-brew
no_mm="-DSQLITE_ENABLE_API_ARMOR -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_DBSTAT_VTAB
 -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_GEOPOLY
 -DSQLITE_ENABLE_MATH_FUNCTIONS -DSQLITE_ENABLE_PERCENTILE
 -DSQLITE_ENABLE_PREUPDATE_HOOK -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_SESSION -DSQLITE_ENABLE_STAT4
 -DSQLITE_ENABLE_UNLOCK_NOTIFY -DSQLITE_MAX_VARIABLE_NUMBER=250000 -DSQLITE_USE_URI=1"
all="$no_mm -DSQLITE_ENABLE_MEMORY_MANAGEMENT"
build() {
  n=$1
  shift
  mkdir -p "$b/$n/lib" "$b/$n/include"
  cp "$a/sqlite3.h" "$a/sqlite3ext.h" "$b/$n/include/"
  "$CC" -shared -fPIC -O2 -DSQLITE_THREADSAFE=1 "$@" -Wl,-z,defs \
    -o "$b/$n/lib/libsqlite3.so.0" "$a/sqlite3.c" -lpthread -lm
}
build defaults
# shellcheck disable=SC2086
build brew-all $all
# shellcheck disable=SC2086
build brew-no-mm $no_mm
build mm -DSQLITE_ENABLE_MEMORY_MANAGEMENT
build stat4 -DSQLITE_ENABLE_STAT4
build mm-page64k -DSQLITE_ENABLE_MEMORY_MANAGEMENT -DSQLITE_DEFAULT_PAGE_SIZE=65536
for n in defaults brew-all brew-no-mm mm stat4 mm-page64k; do
  echo "== $n"
  C_INCLUDE_PATH=$PWD/$b/$n/include CHEZ_SQLITE3_LIBRARY=$PWD/$b/$n/lib/libsqlite3.so.0 \
    make test SUITES="$suite" 2>&1 | grep -E '^    S3|^FAIL|^  actual|^test: ran' || true
done
