#!/bin/sh
# Test fixture: a floor.sh that writes no floor. Its lines hold a backslash
# after a double quote, and an odd number of double quotes, which are shell.
set -eu
fail() { printf 'floor.sh: %s\n' "$*" >&2; exit 1; }
[ "$#" -eq 1 ] || fail "it is not one list of (key \"version\") entries"
grep -q -E '^ *\( *(\( *[a-z]+ +"[^"]*" *\) *)+\) *$' "$1" || fail "x"
