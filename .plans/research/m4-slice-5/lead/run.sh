#!/bin/sh
# run.sh [OUT]: the lead's plants of M4 slice 5, in the container, from the
# worktree's root, OUT by default build/lead-mut. On the host first:
#   python3 -I .plans/research/m4-slice-5/lead/plant.py . .plans/research/m4-slice-5/lead/plants.json OUT
#   sh .plans/research/m4-slice-5/lead/old-close.sh "$PWD" "$PWD/OUT"
# Then: scripts/guix-env sh .plans/research/m4-slice-5/lead/run.sh OUT
# Each plant's suites run on Guix's library, and test-fts5 on the FTS5 build
# and test-json on the floor where the plant touches them; X-old-close runs
# test-fts5 on Guix's, the FTS5 build and 3.45.1 with every module. One line
# a run: the plant, the suite, the library, the counts, and the FAIL lines.
wt=$PWD
out=${1:-build/lead-mut}
lib() { [ "$1" = guix ] && echo "" || echo "$wt/build/$1/lib/libsqlite3.so.0"; }
one() { # one DIR SUITE LIBRARY
  l=$(lib "$3")
  res=$(cd "$1" && CHEZ_SQLITE3_LIBRARY=${l:-$CHEZ_SQLITE3_LIBRARY} timeout 300 \
          "$CHEZ" --libdirs src:tests:"$wt/build/scheme-libs" --program "tests/$2.sps" 2>&1)
  rc=$?
  p=$(printf '%s\n' "$res" | awk '/^# of expected passes/ {print $NF}')
  f=$(printf '%s\n' "$res" | awk '/^# of unexpected failures/ {print $NF}')
  echo "${1##*/} $2 $3: exit $rc, pass ${p:-0}, fail ${f:-0}"
  printf '%s\n' "$res" | grep '^FAIL' | cut -c1-120 | sed 's/^/    /'
}
for d in "$wt/$out"/LR*; do
  case ${d##*/} in
    LR01*|LR02*|LR03*) one "$d" test-fts5 guix; one "$d" test-fts5 m4-current-fts5 ;;
    LR04*) one "$d" test-json guix; one "$d" test-json m3-floor ;;
    LR05*) one "$d" test-json guix; one "$d" test-json m3-floor
           one "$d" test-fts5 guix; one "$d" test-fts5 m4-current-fts5 ;;
  esac
done
d=$wt/$out/X-old-close
for l in guix m4-current-fts5 m4cf-floor-vtab; do one "$d" test-fts5 "$l"; done
