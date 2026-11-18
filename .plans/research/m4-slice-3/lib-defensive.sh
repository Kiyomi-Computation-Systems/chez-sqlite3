#!/bin/sh
# lib-defensive.sh SRC OUT: SQLite 3.54.1 built with -DSQLITE_DEFAULT_DEFENSIVE,
# which opens every connection with DEFENSIVE on, as Apple's library does, into
# OUT/lib/libsqlite3.so.0 with its headers in OUT/include. SRC is the pinned
# current release's autoconf tree, sqlite-autoconf-3540100 (build-sqlite.sh's
# current_archive, checked by its digests). Run inside scripts/guix-env, which
# exports CC. M4 slice 5's review built build/m4s5-lib-defensive this way, and
# slice 3 ran on it: its compile options list no DEFAULT_DEFENSIVE, and its -1
# read of DEFENSIVE answers (0 1) (traps.md).
set -e
src=$1; out=$2
mkdir -p "$out/lib" "$out/include"
cp "$src/sqlite3.h" "$src/sqlite3ext.h" "$out/include/"
"$CC" -shared -fPIC -O0 -DSQLITE_THREADSAFE=1 -DSQLITE_ENABLE_FTS5 -DSQLITE_DEFAULT_DEFENSIVE \
  -Wl,-z,defs -o "$out/lib/libsqlite3.so.0" "$src/sqlite3.c" -lpthread -lm
