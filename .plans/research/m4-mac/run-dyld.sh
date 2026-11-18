#!/bin/sh
# Whether the environment can redirect an absolute path to a library or an
# extension, for M4's Mac run after slice 5 (slices-3-5.md). Each case runs
# dyld.sps in a Chez of its own, since dyld reads its variables at launch.
#
#   CHEZ=... sh .plans/research/m4-mac/run-dyld.sh LOADER INCLUDE OTHER-DIR OUT
#
# Run it from the clone's root, on main with slice 4 merged. LOADER is an
# absolute libsqlite3 that has sqlite3_load_extension, for the load cases;
# INCLUDE holds its sqlite3ext.h. OTHER-DIR holds a libsqlite3 of the same
# leaf name as the one the library cases load, at another version. The
# library cases load CHEZ_SQLITE3_LIBRARY as the caller's environment has it,
# unset meaning discovery. OUT must not exist; it gets dyld.txt, and the two
# extensions under OUT/scratch. In dyld.txt, OUT is written "OUT" and $HOME
# "~".
#
# On Darwin the variables are DYLD_LIBRARY_PATH, searched by leaf name before
# the path given, and DYLD_FALLBACK_LIBRARY_PATH, searched after it fails, by
# dlopen(3). Elsewhere LD_LIBRARY_PATH stands for both, as a control: glibc's
# dlopen searches nothing for a path holding a slash.
set -u

[ $# -eq 4 ] || { echo "usage: CHEZ=... sh run-dyld.sh LOADER INCLUDE OTHER-DIR OUT" >&2; exit 2; }
loader=$1; inc=$2; other=$3; out=$4
cc=${CC:-cc}
[ -n "${CHEZ:-}" ] || { echo "run-dyld.sh: set CHEZ to Chez Scheme" >&2; exit 2; }
[ -f tests/extension.c ] || { echo "run-dyld.sh: run it from the clone's root, with slice 4 merged" >&2; exit 2; }
[ -f "$loader" ] || { echo "run-dyld.sh: no library $loader" >&2; exit 2; }
[ -f "$inc/sqlite3ext.h" ] || { echo "run-dyld.sh: no sqlite3ext.h in $inc" >&2; exit 2; }
[ -d "$other" ] || { echo "run-dyld.sh: no directory $other" >&2; exit 2; }
[ ! -e "$out" ] || { echo "run-dyld.sh: $out exists; name a new directory" >&2; exit 2; }

case $(uname -s) in
  Darwin) shared=-dynamiclib; suf=dylib; first=DYLD_LIBRARY_PATH; fallback=DYLD_FALLBACK_LIBRARY_PATH ;;
  *) shared="-shared -fPIC"; suf=so; first=LD_LIBRARY_PATH; fallback=LD_LIBRARY_PATH ;;
esac

mkdir -p "$out/scratch/a" "$out/scratch/b" || exit 2
abs=$(cd "$out" && pwd -P) || exit 2
a=$abs/scratch/a; b=$abs/scratch/b
txt=$abs/dyld.txt
probe=.plans/research/m4-mac/dyld.sps

# masked: stdin with OUT and $HOME named.
masked() { sed -e "s#$abs#OUT#g" -e "s#$HOME#~#g"; }

# run LABEL NAME=VALUE... -- ARG...: one Chez, its answer and exit status on
# a line. The variables are set by this shell's own prefix assignment, never
# through /usr/bin/env, which macOS protects: launching a protected binary
# strips DYLD_* from its environment. A VALUE holds no single quote.
run() {
  label=$1; shift
  envs=
  while [ "$1" != "--" ]; do envs="$envs ${1%%=*}='${1#*=}'"; shift; done
  shift
  answer=$(eval "$envs \"\$CHEZ\" --libdirs src --program \"\$probe\" \"\$@\"" 2>&1)
  echo "$label [$envs ]: $answer (exit $?)" | masked >>"$txt"
}

{
  echo "uname: $(uname -s -r -m)"
  if command -v sw_vers >/dev/null 2>&1; then sw_vers | tr '\n' ' '; echo; fi
  echo "commit: $(git log -1 --format='%h %s' 2>/dev/null)"
  echo "CHEZ_SQLITE3_LIBRARY: ${CHEZ_SQLITE3_LIBRARY:-(unset)}"
  echo "loader: $loader"
  echo "other: $other"
} | masked >"$txt"

for v in "a -DEXT_FAILING" "b"; do
  set -- $v
  dir=$abs/scratch/$1; shift
  if ! "$cc" -Wall $shared -I"$inc" -o "$dir/ext.$suf" tests/extension.c "$@" >>"$txt" 2>&1; then
    echo "compile of $dir/ext.$suf failed" | masked >>"$txt"
  fi
done

echo "-- the library, as CHEZ_SQLITE3_LIBRARY or discovery gives it" >>"$txt"
run "L0, as given" -- library
run "L1, $first naming OTHER" "$first=$other" -- library

echo "-- the extension: a/ext.$suf refuses (failing), b/ext.$suf registers chez_half" >>"$txt"
run "E0, b's path" "CHEZ_SQLITE3_LIBRARY=$loader" -- load "$b/ext.$suf"
run "E1, b's path, $first naming a" "CHEZ_SQLITE3_LIBRARY=$loader" "$first=$a" -- load "$b/ext.$suf"
run "E2, a path no file stands at, $fallback naming b" "CHEZ_SQLITE3_LIBRARY=$loader" "$fallback=$b" -- load "$abs/scratch/none/ext.$suf"
run "E3, a's path, as a control" "CHEZ_SQLITE3_LIBRARY=$loader" -- load "$a/ext.$suf"

echo "run-dyld.sh: done" | tee -a "$txt"
