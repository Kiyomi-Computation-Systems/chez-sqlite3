#!/bin/sh
# scripts/ci/report-sqlite.sh
#
# Reports the SQLite a CI lane tests: CI's main job runs it on the runner's
# own SQLite, so each run records it (harness plan, section 5). It prints the
# library's path, its version and number, the version and number of the
# sqlite3.h the compiler finds, the SQLite floor, and every compile option,
# one per line. It reads the library through Chez's FFI, never from a sqlite3
# command, which can carry its own copy of SQLite (AGENTS.md).
#
# It reports and checks nothing. M1 holds a library to its floor (discovery's
# below-floor refusal, and the floor lane's assertions) and to its header
# (the constants check), with tests of their own.
#
# The library is the one CHEZ_SQLITE3_LIBRARY names, an absolute path, when
# that is set, as in the Guix container (ADR-0002). Otherwise it is the one
# file the libsqlite3-0 package installs as libsqlite3.so.0, as dpkg lists it.
#
# It fails, saying why on stderr, only when it cannot make the report:
# CHEZ_SQLITE3_LIBRARY is set but is not an absolute path; dpkg lists no
# libsqlite3.so.0 for libsqlite3-0, or more than one; Chez cannot load the
# library or read its version; the compiler cannot build a program against
# sqlite3.h; or scripts/ci/floor.sh gives no floor.
#
# CHEZ and CC name the Chez binary and the C compiler, scheme and cc by
# default. It exits 0 or 1, or 2 on a usage error.
set -eu

[ "$#" -eq 0 ] || { echo "usage: report-sqlite.sh" >&2; exit 2; }

fail() {
  printf 'report-sqlite: %s\n' "$*" >&2
  exit 1
}

chez=${CHEZ:-scheme}
cc=${CC:-cc}
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

if [ -n "${CHEZ_SQLITE3_LIBRARY+set}" ]; then
  lib=$CHEZ_SQLITE3_LIBRARY
  case $lib in
    /?*) ;;
    *) fail "CHEZ_SQLITE3_LIBRARY is '$lib', not an absolute path" ;;
  esac
else
  listed=$(dpkg -L libsqlite3-0 2>/dev/null | grep '/libsqlite3\.so\.0$' || true)
  [ -n "$listed" ] || fail "dpkg lists no libsqlite3.so.0 for libsqlite3-0"
  [ "$(printf '%s\n' "$listed" | grep -c '')" -eq 1 ] ||
    fail "dpkg lists more than one libsqlite3.so.0 for libsqlite3-0: $(printf '%s' "$listed" | tr '\n' ' ')"
  lib=$listed
fi

floor=$(sh "$here/floor.sh" sqlite) || fail "no SQLite floor to report"

work=$(mktemp -d "${TMPDIR:-/tmp}/report-sqlite.XXXXXX")
trap 'rm -rf "$work"' EXIT

# The library, read through the FFI: its version, its number, then each
# compile option, one per line, until sqlite3_compileoption_get answers NULL.
cat >"$work/read.ss" <<'EOF'
(let ((lib (car (command-line-arguments))))
  (load-shared-object lib)
  (let ((version (foreign-procedure "sqlite3_libversion" () string))
        (number (foreign-procedure "sqlite3_libversion_number" () int))
        (option (foreign-procedure "sqlite3_compileoption_get" (int) string)))
    (let* ((v (version))
           (n (number)))
      (printf "version ~a ~a~%" v n))
    (let loop ((i 0))
      (let ((o (option i)))
        (when o
          (printf "option ~a~%" o)
          (loop (+ i 1)))))))
EOF
"$chez" -q --script "$work/read.ss" "$lib" >"$work/library" 2>"$work/library.err" ||
  fail "Chez could not read $lib: $(head -n 1 "$work/library.err")"
lib_line=$(grep '^version ' "$work/library" || true)
[ -n "$lib_line" ] || fail "Chez printed no version for $lib"
lib_version=$(printf '%s\n' "$lib_line" | awk '{ print $2 }')
lib_number=$(printf '%s\n' "$lib_line" | awk '{ print $3 }')

cat >"$work/header.c" <<'EOF'
#include <stdio.h>
#include <sqlite3.h>
int main(void) { printf("%s %d\n", SQLITE_VERSION, SQLITE_VERSION_NUMBER); return 0; }
EOF
"$cc" -o "$work/header" "$work/header.c" 2>"$work/cc.err" ||
  fail "$cc could not compile a program against sqlite3.h: $(head -n 1 "$work/cc.err")"
header=$("$work/header")
header_version=${header% *}
header_number=${header##* }

echo "libsqlite3: $lib -> $(readlink -f "$lib")"
echo "version: $lib_version ($lib_number)"
echo "sqlite3.h: $header_version ($header_number)"
echo "floor: $floor"
echo "compile options:"
sed -n 's/^option /  /p' "$work/library"
