#!/bin/sh
# The self-test's cmark-gfm assertions, and its tar and xz tool paths,
# watched failing. Run on the host, from the repository root, which has git:
#
#   sh .plans/research/m5-slice-2/selftest-plants.sh [BASE]
#
# It cuts the self-test's last assertion, make check-help and make test, into
# a copy under build/m5s2/selftest/, so that each run takes seconds. Then:
#
#   - inside the container, it runs the copy under each planted
#     CHEZ_CMARK_GFM_LIBS: unset, empty, naming no file, the two in the other
#     order, the core alone, three paths, and the core then nothing; and the
#     control, the variable as scripts/guix-env-enter exports it;
#   - in the container of BASE (default fb4e183, the commit before
#     cmark-gfm, tar and xz), built from BASE's manifest.scm and entry
#     script under build/m5s2/oldenv/, it runs the copy unplanted.
#
# It prints each run's cmark-gfm and tar and xz lines, the profile's path
# written $P, and its exit status. Each plant must fail; the control must
# pass; the base's run must fail tar, xz and both cmark-gfm assertions.
set -u
base=${1:-fb4e183}
out=build/m5s2/selftest
mkdir -p "$out"
awk '/^# Assertion 10:/ {skip=1} /^if \[ "\$fail" -eq 0 \]; then$/ {skip=0} !skip' \
  scripts/guix-env-selftest >"$out/selftest-no-make.sh"

cat >"$out/run.sh" <<'EOF'
#!/bin/sh
s=build/m5s2/selftest/selftest-no-make.sh
lib=$GUIX_ENVIRONMENT/lib
run() {
  label=$1; shift
  result=$("$@" sh "$s" 2>&1); st=$?
  echo "== $label: exit $st"
  printf '%s\n' "$result" | grep -E 'cmark-gfm|ALL CHECKS|tool-path\[-lc\] \((tar|xz)' \
    | sed "s#$GUIX_ENVIRONMENT#\$P#g; s/^/   /"
}
run control env
run unset env -u CHEZ_CMARK_GFM_LIBS
run empty env CHEZ_CMARK_GFM_LIBS=
run no-file env \
  CHEZ_CMARK_GFM_LIBS=/nonexistent/libcmark-gfm.so:/nonexistent/libcmark-gfm-extensions.so
run other-order env CHEZ_CMARK_GFM_LIBS="$lib/libcmark-gfm-extensions.so:$lib/libcmark-gfm.so"
run core-alone env CHEZ_CMARK_GFM_LIBS="$lib/libcmark-gfm.so"
run three-paths env \
  CHEZ_CMARK_GFM_LIBS="$lib/libcmark-gfm.so:$lib/libcmark-gfm-extensions.so:$lib/libcmark-gfm.so"
run core-then-empty env CHEZ_CMARK_GFM_LIBS="$lib/libcmark-gfm.so:"
EOF
scripts/guix-env sh "$out/run.sh"

old=build/m5s2/oldenv
rm -rf "$old"
mkdir -p "$old/scripts"
cp scripts/guix-env "$old/scripts/"
git show "$base:scripts/guix-env-enter" >"$old/scripts/guix-env-enter"
git show "$base:manifest.scm" >"$old/manifest.scm"
cp channels.scm "$out/selftest-no-make.sh" "$old/"
result=$(cd "$old" && scripts/guix-env sh selftest-no-make.sh 2>&1); st=$?
echo "== the container of $base: exit $st"
printf '%s\n' "$result" | grep -E 'FAILED|ALL CHECKS' \
  | sed 's#/gnu/store/[a-z0-9]*-profile#$P#g; s/^/   /'
