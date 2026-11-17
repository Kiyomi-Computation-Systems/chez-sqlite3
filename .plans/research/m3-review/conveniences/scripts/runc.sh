#!/bin/sh
# runc.sh COPY TAG SUITE... : run suites inside build/c/COPY, plain, logs in build/c/logs.
copy=$1; tag=$2; shift 2
root=$PWD
cd build/c/$copy || exit 2
if [ "${FLOOR:-0}" = 1 ]; then
  export CHEZ_SQLITE3_LIBRARY="$PWD/build/m3-floor/lib/libsqlite3.so.0"
  export C_INCLUDE_PATH="$PWD/build/m3-floor/include"
fi
for t in "$@"; do
  n=$(basename "$t" .sps)
  s=$(date +%s%N)
  $CHEZ --libdirs src:tests:build/scheme-libs --program "$t" > "$root/build/c/logs/$n.$copy-$tag.log" 2>&1
  rc=$?
  e=$(date +%s%N)
  printf '%s %s %s rc=%s %sms %s\n' "$copy" "$tag" "$n" "$rc" "$(( (e - s) / 1000000 ))" "$(grep -c '^FAIL' "$root/build/c/logs/$n.$copy-$tag.log") FAIL"
done
