#!/bin/sh
# Brief D7, on a Mac: runs probe.sps once for Apple's libsqlite3, and once
# more for each Homebrew SQLite present, each in a process of its own, since
# Chez binds a name to the library loaded last (ADR-0002).
#
# Usage: sh run.sh [CHEZ] > mac-d7.txt
#
# CHEZ defaults to $CHEZ, then scheme, then chez on PATH. Nothing is written
# but standard output.
set -u
here=$(cd "$(dirname "$0")" && pwd)
chez=${1:-${CHEZ:-}}
if [ -z "$chez" ]; then
  chez=$(command -v scheme || command -v chez || true)
fi
if [ -z "$chez" ]; then
  echo "run.sh: no Chez found; give its path as the first argument" >&2
  exit 2
fi

printf '(macos %s %s)\n' "\"$(sw_vers -productVersion 2>/dev/null || echo unknown)\"" \
  "\"$(sw_vers -buildVersion 2>/dev/null || echo unknown)\""
printf '(uname-m "%s")\n' "$(uname -m)"
printf '(chez-binary "%s")\n' "$chez"

# Apple's lives in the dyld shared cache, with no file on disk, so it is
# always tried. Homebrew's are tried only where a file is there.
for lib in /usr/lib/libsqlite3.dylib \
           /opt/homebrew/opt/sqlite/lib/libsqlite3.dylib \
           /usr/local/opt/sqlite/lib/libsqlite3.dylib; do
  case $lib in
    /usr/lib/*) ;;
    *) if [ ! -e "$lib" ]; then printf '(absent "%s")\n' "$lib"; continue; fi ;;
  esac
  printf ';; %s\n' "$lib"
  "$chez" --program "$here/probe.sps" "$lib"
  printf '(probe-exit %s)\n' "$?"
done
