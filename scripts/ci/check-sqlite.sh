#!/bin/sh
# scripts/ci/check-sqlite.sh PREFIX [--current]
#
# Fails unless PREFIX holds the SQLite a CI lane needs, and the lane's
# environment points at it: the floor, for the floor lane, read from
# packaging/floors.sexp by scripts/ci/floor.sh (ADR-0008); or, with
# --current, the pinned current release, which reads no floors file.
# scripts/ci/build-sqlite.sh runs it on what it built, before a cache saves
# it, and each lane runs it again after restoring SQLite from a cache, so a
# cache that serves another build is caught before any suite runs on it.
#
# It checks, in order, stopping at the first problem:
#
#   1. PREFIX/lib/libsqlite3.so.0 and PREFIX/include/sqlite3.h are regular
#      files;
#   2. CHEZ_SQLITE3_LIBRARY is exactly PREFIX/lib/libsqlite3.so.0, so that
#      make build and make test load the library checked here (ADR-0002's
#      override, loaded as given);
#   3. the compiler, in this environment, finds <sqlite3.h> at exactly
#      PREFIX/include/sqlite3.h, as $CC -E -M lists it: the header the
#      constants check compiles against (-M, not -MM, since C_INCLUDE_PATH's
#      directories count as system ones);
#   4. that header defines the release's SQLITE_VERSION,
#      SQLITE_VERSION_NUMBER and SQLITE_SOURCE_ID;
#   5. the library, read through Chez's FFI by a probe of its own, never
#      through chez-sqlite3 and never from a sqlite3 command (AGENTS.md),
#      answers the release's version, number and source id, answers 1,
#      serialized, to sqlite3_threadsafe(), and lists every compile option
#      the release lists when build-sqlite.sh builds it, line for line, in
#      SQLite's order, and no other. A lane tests SQLite's defaults, built
#      here with known flags: so a build with DEFAULT_MEMSTATUS=0, which
#      ADR-0005's memory check cannot read, or with THREADSAFE=0, fails.
#
# The release's version number is computed from its version, X*1000000 +
# Y*1000 + Z, never written. Its source id is the one sqlite.org's release
# log publishes. The options were read from the library build-sqlite.sh
# builds, with one entry computed here: SQLite lists the compiler that built
# it, COMPILER=gcc-<__VERSION__> or COMPILER=clang-<major.minor.patch>, so
# this script asks the same compiler, ${CC:-cc}, by SQLite's own
# preprocessor test (sqlite3.c's ctime.c). An option at its default may go
# unlisted: DEFAULT_MEMSTATUS=1 never shows. The floor's options are the
# floor's, whatever version packaging/floors.sexp gives: raise the floor,
# and floor_source_id and floor_options below must move with it, as
# build-sqlite.sh's pins must.
#
# current_version is written here, in build-sqlite.sh, and in
# tests/test-ci-sqlite.sps: a change to one that misses another fails at
# build-sqlite.sh's own call to this script, before any cache is saved.
#
# CHEZ and CC name the Chez binary and the C compiler, scheme and cc by
# default. It prints what it checked on stdout and exits 0, or says what is
# wrong on stderr and exits 1, or 2 on a usage error.
set -eu

usage() {
  echo "usage: check-sqlite.sh PREFIX [--current]" >&2
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
  *) echo "check-sqlite.sh: PREFIX must be an absolute path, not '$prefix'" >&2; exit 2 ;;
esac

fail() {
  printf 'check-sqlite.sh: %s\n' "$*" >&2
  exit 1
}

# Bytes, not characters, in every sed and grep below.
LC_ALL=C
export LC_ALL

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# current_version: the current SQLite, built with --current: sqlite.org's
# newest release on 2026-11-14, chosen that day (the M1 plan, section 7). It
# is no floor, so it is not in packaging/floors.sexp.
current_version=3.54.1

# The source ids sqlite.org's release logs publish, by role
# (https://sqlite.org/releaselog/X_Y_Z.html).
floor_source_id='2024-01-30 16:01:20 e876e51a0ed5c5b3126f52e532044363a014bc594cfefa87ffb5b82257cc467a'
current_source_id='2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76'

# The compile options each role's library lists, in SQLite's order, as
# build-sqlite.sh builds it, with $compiler where SQLite lists the compiler.
floor_options() {
  cat <<EOF
ATOMIC_INTRINSICS=1
$compiler
DEFAULT_AUTOVACUUM
DEFAULT_CACHE_SIZE=-2000
DEFAULT_FILE_FORMAT=4
DEFAULT_JOURNAL_SIZE_LIMIT=-1
DEFAULT_MMAP_SIZE=0
DEFAULT_PAGE_SIZE=4096
DEFAULT_PCACHE_INITSZ=20
DEFAULT_RECURSIVE_TRIGGERS
DEFAULT_SECTOR_SIZE=4096
DEFAULT_SYNCHRONOUS=2
DEFAULT_WAL_AUTOCHECKPOINT=1000
DEFAULT_WAL_SYNCHRONOUS=2
DEFAULT_WORKER_THREADS=0
DIRECT_OVERFLOW_READ
MALLOC_SOFT_LIMIT=1024
MAX_ATTACHED=10
MAX_COLUMN=2000
MAX_COMPOUND_SELECT=500
MAX_DEFAULT_PAGE_SIZE=8192
MAX_EXPR_DEPTH=1000
MAX_FUNCTION_ARG=127
MAX_LENGTH=1000000000
MAX_LIKE_PATTERN_LENGTH=50000
MAX_MMAP_SIZE=0x7fff0000
MAX_PAGE_COUNT=0xfffffffe
MAX_PAGE_SIZE=65536
MAX_SQL_LENGTH=1000000000
MAX_TRIGGER_DEPTH=1000
MAX_VARIABLE_NUMBER=32766
MAX_VDBE_OP=250000000
MAX_WORKER_THREADS=8
MUTEX_PTHREADS
SYSTEM_MALLOC
TEMP_STORE=1
THREADSAFE=1
EOF
}

current_options() {
  cat <<EOF
ATOMIC_INTRINSICS=1
$compiler
DEFAULT_AUTOVACUUM
DEFAULT_CACHE_SIZE=-2000
DEFAULT_FILE_FORMAT=4
DEFAULT_JOURNAL_SIZE_LIMIT=-1
DEFAULT_MMAP_SIZE=0
DEFAULT_PAGE_SIZE=4096
DEFAULT_PCACHE_INITSZ=20
DEFAULT_RECURSIVE_TRIGGERS
DEFAULT_SECTOR_SIZE=4096
DEFAULT_SYNCHRONOUS=2
DEFAULT_WAL_AUTOCHECKPOINT=1000
DEFAULT_WAL_SYNCHRONOUS=2
DEFAULT_WORKER_THREADS=0
DIRECT_OVERFLOW_READ
MALLOC_SOFT_LIMIT=1024
MAX_ATTACHED=10
MAX_COLUMN=2000
MAX_COMPOUND_SELECT=500
MAX_DEFAULT_PAGE_SIZE=8192
MAX_EXPR_DEPTH=1000
MAX_FUNCTION_ARG=1000
MAX_LENGTH=1000000000
MAX_LIKE_PATTERN_LENGTH=50000
MAX_MMAP_SIZE=0x7fff0000
MAX_PAGE_COUNT=0xfffffffe
MAX_PAGE_SIZE=65536
MAX_SCHEMA=10000000
MAX_SQL_LENGTH=1000000000
MAX_TRIGGER_DEPTH=1000
MAX_VARIABLE_NUMBER=32766
MAX_VDBE_OP=250000000
MAX_WORKER_THREADS=8
MUTEX_PTHREADS
SYSTEM_MALLOC
TEMP_STORE=1
THREADSAFE=1
EOF
}

if [ "$role" = current ]; then
  version=$current_version
  source_id=$current_source_id
  what="the pinned current SQLite"
else
  version=$(sh "$here/floor.sh" sqlite) || fail "no SQLite floor to check against"
  source_id=$floor_source_id
  what="the SQLite floor"
fi

# floor.sh gives three naturals with no leading zero; so is current_version.
major=${version%%.*}
rest=${version#*.}
minor=${rest%%.*}
patch=${rest#*.}
number=$((major * 1000000 + minor * 1000 + patch))

lib=$prefix/lib/libsqlite3.so.0
header=$prefix/include/sqlite3.h

# 1. The files.
[ -f "$lib" ] || fail "no library at $lib: it is not a regular file"
[ -f "$header" ] || fail "no header at $header: it is not a regular file"

# 2. The override names that library.
why="the library this checks, so that make build and make test load it"
[ -n "${CHEZ_SQLITE3_LIBRARY+set}" ] || fail "CHEZ_SQLITE3_LIBRARY is unset, but must be $lib, $why"
[ "$CHEZ_SQLITE3_LIBRARY" = "$lib" ] ||
  fail "CHEZ_SQLITE3_LIBRARY is '$CHEZ_SQLITE3_LIBRARY', but must be $lib, $why"

cc=${CC:-cc}
chez=${CHEZ:-scheme}

work=$(mktemp -d "${TMPDIR:-/tmp}/check-sqlite.XXXXXX")
trap 'rm -rf "$work"' EXIT

# cc_failed WHAT: says the compiler could not do WHAT, then the compiler's
# own words, whole, and exits 1.
cc_failed() {
  echo "check-sqlite.sh: $cc could not $1:" >&2
  cat "$work/cc.err" >&2
  exit 1
}

# 3. The header the compiler finds. -M lists the source, then each header
# in the order it is read, as make rules: a backslash ends each line but the
# last, and a space in a path is written "\ ". The first sqlite3.h listed is
# the one <sqlite3.h> names.
printf '#include <sqlite3.h>\n' >"$work/find.c"
"$cc" -E -M "$work/find.c" >"$work/find.d" 2>"$work/cc.err" ||
  cc_failed "preprocess a file that includes <sqlite3.h>"
found=$(awk '
  { text = text $0 "\n" }
  END {
    gsub(/\\\n/, " ", text)
    gsub(/\\ /, "\001", text)
    n = split(text, words, /[ \t\n]+/)
    for (i = 1; i <= n; i++) {
      word = words[i]
      gsub(/\001/, " ", word)
      if (word ~ /(^|\/)sqlite3\.h$/) { print word; exit }
    }
  }' "$work/find.d")
[ -n "$found" ] || fail "$cc lists no sqlite3.h among the files #include <sqlite3.h> reads"
[ "$found" = "$header" ] ||
  fail "$cc finds <sqlite3.h> at $found, not $header: C_INCLUDE_PATH must name $prefix/include first, so that the suites compile against the library's own header"

# 4. What the header defines, as the compiler reads it: -dM lists each
# macro's definition once, its body's white space made single spaces.
"$cc" -dM -E "$work/find.c" >"$work/macros" 2>"$work/cc.err" ||
  cc_failed "list the macros <sqlite3.h> defines"
header_version=$(sed -n 's/^#define SQLITE_VERSION //p' "$work/macros")
header_number=$(sed -n 's/^#define SQLITE_VERSION_NUMBER //p' "$work/macros")
header_source_id=$(sed -n 's/^#define SQLITE_SOURCE_ID //p' "$work/macros")
expected="\"$version\", $number and \"$source_id\""
if [ "$header_version" != "\"$version\"" ] || [ "$header_number" != "$number" ] ||
   [ "$header_source_id" != "\"$source_id\"" ]; then
  fail "$header defines SQLITE_VERSION $header_version, SQLITE_VERSION_NUMBER $header_number and SQLITE_SOURCE_ID $header_source_id, but $what is $expected"
fi

# The compiler's own entry, by SQLite's test: clang first, then MSVC, then
# gcc, each macro stringified as SQLite stringifies it. -P keeps each line
# whole. The pieces are C string literals side by side, joined here as C
# joins them. A compiler SQLite names in none of the three has no entry.
cat >"$work/compiler.c" <<'EOF'
#define CHEZ_SQLITE3_VAL_(x) #x
#define CHEZ_SQLITE3_VAL(x) CHEZ_SQLITE3_VAL_(x)
#if defined(__clang__) && defined(__clang_major__)
chez_sqlite3_compiler "COMPILER=clang-" CHEZ_SQLITE3_VAL(__clang_major__) "." CHEZ_SQLITE3_VAL(__clang_minor__) "." CHEZ_SQLITE3_VAL(__clang_patchlevel__)
#elif defined(_MSC_VER)
chez_sqlite3_compiler "COMPILER=msvc-" CHEZ_SQLITE3_VAL(_MSC_VER)
#elif defined(__GNUC__) && defined(__VERSION__)
chez_sqlite3_compiler "COMPILER=gcc-" __VERSION__
#else
chez_sqlite3_compiler
#endif
EOF
"$cc" -E -P "$work/compiler.c" >"$work/compiler.i" 2>"$work/cc.err" ||
  cc_failed "preprocess SQLite's test of which compiler it is"
[ "$(grep -c '^chez_sqlite3_compiler' "$work/compiler.i" || true)" -eq 1 ] ||
  fail "$cc did not answer SQLite's test of which compiler it is with one line"
compiler=$(sed -n 's/^chez_sqlite3_compiler//p' "$work/compiler.i" |
  sed -e 's/^ *//' -e 's/" *"//g' -e 's/^"//' -e 's/"$//')

if [ "$role" = current ]; then
  current_options | sed '/^$/d' >"$work/expected"
else
  floor_options | sed '/^$/d' >"$work/expected"
fi
count=$(grep -c '' "$work/expected")

# 5. The library, through the FFI: its identity, threadsafe, then each
# compile option until sqlite3_compileoption_get answers NULL.
cat >"$work/read.ss" <<'EOF'
(let ((lib (car (command-line-arguments))))
  (load-shared-object lib)
  (let ((version (foreign-procedure "sqlite3_libversion" () string))
        (number (foreign-procedure "sqlite3_libversion_number" () int))
        (source-id (foreign-procedure "sqlite3_sourceid" () string))
        (threadsafe (foreign-procedure "sqlite3_threadsafe" () int))
        (option (foreign-procedure "sqlite3_compileoption_get" (int) string)))
    (let* ((v (version))
           (n (number))
           (s (source-id))
           (t (threadsafe)))
      (printf "version ~a~%number ~a~%source ~a~%threadsafe ~a~%" v n s t))
    (let loop ((i 0))
      (let ((o (option i)))
        (when o
          (printf "option ~a~%" o)
          (loop (+ i 1)))))))
EOF
if ! "$chez" -q --script "$work/read.ss" "$lib" >"$work/library" 2>"$work/library.err"; then
  echo "check-sqlite.sh: $chez could not read $lib:" >&2
  cat "$work/library.err" >&2
  exit 1
fi
lib_version=$(sed -n 's/^version //p' "$work/library")
lib_number=$(sed -n 's/^number //p' "$work/library")
lib_source_id=$(sed -n 's/^source //p' "$work/library")
lib_threadsafe=$(sed -n 's/^threadsafe //p' "$work/library")
sed -n 's/^option //p' "$work/library" >"$work/options"

if [ "$lib_version" != "$version" ] || [ "$lib_number" != "$number" ] ||
   [ "$lib_source_id" != "$source_id" ]; then
  fail "$lib answers \"$lib_version\", $lib_number and \"$lib_source_id\" to sqlite3_libversion(), sqlite3_libversion_number() and sqlite3_sourceid(), but $what is $expected"
fi
[ "$lib_threadsafe" = 1 ] ||
  fail "$lib answers $lib_threadsafe to sqlite3_threadsafe(), but a lane's SQLite must answer 1: serialized, SQLite's default"

if ! cmp -s "$work/expected" "$work/options"; then
  echo "check-sqlite.sh: $lib's compile options are not the $count of $what, line for line:" >&2
  # diff exits 1 on a difference; its first two lines name the work files.
  { diff -u "$work/expected" "$work/options" || true; } |
    sed -e '1s/.*/--- expected/' -e '2s/.*/+++ library/' >&2
  exit 1
fi

echo "check-sqlite.sh: $lib is SQLite $version ($number), source id $source_id: $what"
echo "check-sqlite.sh: it is threadsafe (1), and its $count compile options are $what's, line for line:"
sed 's/^/  /' "$work/options"
echo "check-sqlite.sh: $cc finds <sqlite3.h> at $header, which declares the same release, and CHEZ_SQLITE3_LIBRARY names the library"
