#!/bin/sh
# extract-base.sh COMMIT OUT: on the host (the container has no git or tar), the swept commit's
# src/ and tests/, and its build files, the Makefile, scripts/, packaging/, .gitignore and
# .gitattributes, unpacked under OUT, the BASE sweep-check.sh compares against. OUT must not
# exist.
set -eu
commit=$1
out=$2
if [ -e "$out" ]; then echo "extract-base.sh: $out exists" >&2; exit 1; fi
mkdir -p "$out"
git archive "$commit" src tests Makefile scripts packaging .gitignore .gitattributes |
  tar -x -C "$out"
echo "extract-base.sh: $commit's src/, tests/ and build files in $out"
