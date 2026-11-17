#!/bin/sh
# Time each named suite plain; LIB=floor runs against build/m3-floor.
cd "$(dirname "$0")/../../../../.."  # the tree's root; it was build/t/ in the worktree
if [ "${LIB:-}" = floor ]; then
  export CHEZ_SQLITE3_LIBRARY="$PWD/build/m3-floor/lib/libsqlite3.so.0"
  export C_INCLUDE_PATH="$PWD/build/m3-floor/include"
fi
for t in "$@"; do
  log="build/t/logs/$(basename $t .sps).${LIB:-current}.log"
  s=$(date +%s%N)
  timeout 600 $CHEZ --libdirs src:tests:build/scheme-libs --program "$t" > "$log" 2>&1
  rc=$?
  e=$(date +%s%N)
  printf '%s %s rc=%s %sms %s\n' "${LIB:-current}" "$t" "$rc" "$(( (e - s) / 1000000 ))" "$(grep -E '^# of (expected passes|unexpected failures)' "$log" | tr -s ' ' | tr '\n' ' ')"
done
