#!/bin/sh
# Runs the M4 plan's two load probes against one SQLite, for the plan's open
# item "The Mac's load" (section 7). The Mac's runbook is mac.md.
#
#   CHEZ=... sh .plans/research/m4-mac/run-mac.sh LIBRARY INCLUDE-DIR OUT
#
# Run it from the clone's root. CHEZ names Chez Scheme, and CC the C
# compiler, cc when unset. LIBRARY is the libsqlite3 the probes link and
# load, and INCLUDE-DIR holds its sqlite3.h and sqlite3ext.h. OUT must not
# exist. It gets:
#   system.txt         the machine, the tools, the commit, the library's hash
#   compile.txt        every compile line, and what the compiler said
#   l1-SUF.txt         l1-load-extension.c's output with its objects named
#   l1-timing-SUF.txt  .SUF, and its times
#   x1-MODE-SUF.txt    x1-ffi-load.sps's output in the modes gate, gate-leak
#                      and gate-none, run without Valgrind
# Each probe's file ends in its exit status. SUF is each of SUFFIXES:
# "dylib so" on Darwin, whose SQLite retries a path with ".dylib", and "so"
# elsewhere. Each extension is built with -dynamiclib on Darwin, as SQLite's
# documentation builds one there, and with -shared -fPIC elsewhere. Compiles
# warn but never fail on a warning: a Mac run is one try. The objects go
# under OUT/scratch. In every file, OUT/scratch is written "SCRATCH" and
# $HOME "~"; the probes write each object's directory "DIR" themselves.
set -u

[ $# -eq 3 ] || { echo "usage: CHEZ=... sh run-mac.sh LIBRARY INCLUDE-DIR OUT" >&2; exit 2; }
lib=$1; inc=$2; out=$3
here=.plans/research/m4-plan
cc=${CC:-cc}
[ -n "${CHEZ:-}" ] || { echo "run-mac.sh: set CHEZ to Chez Scheme" >&2; exit 2; }
[ -f "$here/l1-load-extension.c" ] || { echo "run-mac.sh: run it from the clone's root" >&2; exit 2; }
[ -f "$lib" ] || { echo "run-mac.sh: no library $lib" >&2; exit 2; }
[ -f "$inc/sqlite3.h" ] && [ -f "$inc/sqlite3ext.h" ] ||
  { echo "run-mac.sh: no sqlite3.h and sqlite3ext.h in $inc" >&2; exit 2; }
[ ! -e "$out" ] || { echo "run-mac.sh: $out exists; name a new directory" >&2; exit 2; }

case $(uname -s) in
  Darwin) shared=-dynamiclib; suffixes=${SUFFIXES:-dylib so} ;;
  *) shared="-shared -fPIC"; suffixes=${SUFFIXES:-so} ;;
esac

mkdir -p "$out/scratch" || exit 2
abs=$(cd "$out" && pwd -P) || exit 2
scratch=$abs/scratch

# build ARG...: one compile, its line and its messages kept in compile.txt.
build() {
  echo "\$ $cc $*" >>"$abs/compile.txt"
  if "$cc" "$@" >>"$abs/compile.txt" 2>&1; then
    return 0
  fi
  echo "(compile failed)" >>"$abs/compile.txt"
  return 1
}

{
  echo "uname: $(uname -s -r -m)"
  if command -v sw_vers >/dev/null 2>&1; then sw_vers; fi
  echo "chez: $CHEZ"
  "$CHEZ" --version 2>&1
  echo "(machine-type)" | "$CHEZ" -q 2>&1
  "$cc" --version 2>&1 | head -1
  if command -v git >/dev/null 2>&1; then echo "commit: $(git rev-parse HEAD)"; fi
  echo "library: $lib"
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$lib"; else shasum -a 256 "$lib"; fi
  echo "include: $inc"
  echo "suffixes: $suffixes"
  echo "shared: $shared"
} >"$abs/system.txt" 2>&1

: >"$abs/compile.txt"
l1=$scratch/l1-load-extension
build -O2 -Wall -I"$inc" -o "$l1" "$here/l1-load-extension.c" "$lib" \
  -Wl,-rpath,"$(dirname "$lib")" -lpthread -lm || l1=

for suf in $suffixes; do
  d=$scratch/l1-$suf.d
  mkdir "$d" || exit 2
  # shellcheck disable=SC2086
  if build -O2 -Wall $shared -I"$inc" -o "$d/ext.$suf" "$here/ext.c" &&
     build -O2 -Wall $shared -I"$inc" -DEXT_NAMED -o "$d/ext-named.$suf" "$here/ext.c" &&
     build -O2 -Wall $shared -I"$inc" -DEXT_DERIVED -o "$d/libchezext.$suf" "$here/ext.c" &&
     build -O2 -Wall $shared -I"$inc" -DEXT_FAILING -o "$d/ext-failing.$suf" "$here/ext.c" &&
     build -O2 -Wall $shared -o "$d/noentry.$suf" "$here/noentry.c"; then
    : >"$d/empty.$suf"
    mkdir "$d/dir.$suf"
    if [ -n "$l1" ]; then
      "$l1" "$d" "$abs/l1-timing-$suf.txt" "$suf" >"$abs/l1-$suf.txt" 2>&1
      echo "(exit $?)" >>"$abs/l1-$suf.txt"
    else
      echo "(not run: l1-load-extension.c didn't compile; see compile.txt)" >"$abs/l1-$suf.txt"
    fi
    for m in gate gate-leak gate-none; do
      "$CHEZ" --program "$here/x1-ffi-load.sps" "$lib" "$d" "$m" "$suf" >"$abs/x1-$m-$suf.txt" 2>&1
      echo "(exit $?)" >>"$abs/x1-$m-$suf.txt"
    done
  else
    echo "(not run: an extension didn't compile; see compile.txt)" >"$abs/l1-$suf.txt"
  fi
done

for f in "$abs"/*.txt; do
  if [ -n "${HOME:-}" ] && [ "$HOME" != / ]; then
    sed "s|$scratch|SCRATCH|g; s|$HOME|~|g" "$f" >"$f.tmp"
  else
    sed "s|$scratch|SCRATCH|g" "$f" >"$f.tmp"
  fi
  mv "$f.tmp" "$f"
done
echo "run-mac.sh: done; the results are $out/*.txt"
