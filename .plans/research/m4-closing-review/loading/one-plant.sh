#!/bin/sh
# one-plant.sh DIR: inside the container. Runs the plant copy DIR's suites
# and make targets, named in DIR/.plant, from inside DIR, outside the gate,
# writing each one's output to DIR/.logs/ and one line each to
# DIR/.summary: suite NAME exit N passes P failures F, or target NAME exit N.
dir=$1
cd "$dir" || exit 0
mkdir -p .logs
: > .summary
make deps >.logs/deps.log 2>&1 || { echo "deps exit $?" >> .summary; exit 0; }
suites=$(sed -n 1p .plant)
targets=$(sed -n 2p .plant)
for s in $suites; do
  log=.logs/$s.log
  timeout 300 "$CHEZ" --libdirs src:tests:build/scheme-libs --program "tests/$s.sps" >"$log" 2>&1
  rc=$?
  p=$(sed -n 's/^# of expected passes *//p' "$log"); f=$(sed -n 's/^# of unexpected failures *//p' "$log")
  echo "suite $s exit $rc passes ${p:-none} failures ${f:-0}" >> .summary
done
for t in $targets; do
  make "$t" >".logs/make-$t.log" 2>&1
  echo "target $t exit $?" >> .summary
done
