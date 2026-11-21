#!/bin/sh
# run-plants.sh: runs each plant tree's suite, in scripts/guix-env, from the worktree's root,
# after plants.py build. test-docs for a docs plant; check-site's last check for a site plant.
# Each tree gets plant.log and plant.status.
set -u
root=$PWD
while read -r name suite; do
  cd "$root/build/plants/$name" || exit 1
  case $suite in
    docs) $CHEZ --libdirs src:tests:build/scheme-libs --program tests/test-docs.sps >plant.log 2>&1 ;;
    site) $CHEZ --libdirs .:build/akku/chez-cmark-gfm/src --program tests/check-site.sps >plant.log 2>&1 ;;
  esac
  echo "exit $?" >plant.status
  echo "$name: $(cat plant.status)"
done <"$root/build/plants/suites.txt"
