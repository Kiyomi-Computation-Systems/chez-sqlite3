#!/bin/sh
# run-probes.sh before|after   in the container, from the worktree's root:
#   before  vtab-close.sps on the old order, in plant p01's copy,
#           build/mut/p01-count-first/ (plants.py), on Guix's library,
#           build/m4-current-fts5 and build/m4cf-floor-vtab
#   after   every probe here but stmt-busy.sps and blob-busy.sps, whose
#           output is stmt-busy.txt, on the worktree's code, on those three,
#           build/m4cf-current-vtab and build/m3-floor, where only
#           vtab-close.sps and one failed-close-txn.sps run, the others
#           needing FTS5
# Each command is printed before its output, with $PWD and $CHEZ unexpanded;
# output.txt is both parts.
P=.plans/research/m4-close-fix
mode=$1
case $mode in
  before) cd build/mut/p01-count-first || exit 2; libs="guix m4-current-fts5 m4cf-floor-vtab" ;;
  after) libs="guix m4-current-fts5 m4cf-floor-vtab m4cf-current-vtab m3-floor" ;;
  *) echo "run-probes.sh: before or after" >&2; exit 2 ;;
esac
for lib in $libs; do
  if [ $mode = before ]; then
    list="vtab-close.sps"
  elif [ $lib = m3-floor ]; then
    list="vtab-close.sps|failed-close-txn.sps verb commit"
  else
    list="vtab-close.sps|untracked-vtab.sps|failed-close-txn.sps raw commit|failed-close-txn.sps raw rollback|failed-close-txn.sps verb commit|failed-close-txn.sps verb rollback|rebuild.sps"
  fi
  echo "$list" | tr '|' '\n' | while read f rest; do
    if [ $lib = guix ]; then
      echo "\$ \$CHEZ --libdirs src:build/scheme-libs --program $P/$f $rest"
      $CHEZ --libdirs src:build/scheme-libs --program $P/$f $rest 2>&1
    else
      echo "\$ CHEZ_SQLITE3_LIBRARY=\$PWD/build/$lib/lib/libsqlite3.so.0 C_INCLUDE_PATH=\$PWD/build/$lib/include \$CHEZ --libdirs src:build/scheme-libs --program $P/$f $rest"
      CHEZ_SQLITE3_LIBRARY=$PWD/build/$lib/lib/libsqlite3.so.0 C_INCLUDE_PATH=$PWD/build/$lib/include $CHEZ --libdirs src:build/scheme-libs --program $P/$f $rest 2>&1
    fi
    echo
  done
done
