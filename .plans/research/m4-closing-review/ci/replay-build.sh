#!/bin/sh
# replay-build.sh: build-sqlite.sh --no-load, end to end, in the container,
# which has no network, tar or openssl, through M4 slice 5's three shims
# (research/m4-slice-5/replay/): curl copies build/m4-dl's archive, openssl
# answers the host's digests only for files byte for byte the ones they were
# computed of, and tar copies the host's extraction. The compile and the check
# are the real ones. From the worktree's root:
#   scripts/guix-env sh .plans/research/m4-closing-review/ci/replay-build.sh
# It builds into build/e1/sqlite-no-load, which must not exist yet.
R=$PWD
[ ! -e "$R/build/e1/sqlite-no-load" ] || { echo "replay-build.sh: build/e1/sqlite-no-load exists" >&2; exit 1; }
PATH=$R/.plans/research/m4-slice-5/replay:$PATH \
  SHIM_DL=$R/build/m4-dl SHIM_X=$R/build/m4-dl \
  SHIM_DIGESTS=$R/.plans/research/m4-slice-5/replay/digests \
  scripts/ci/build-sqlite.sh "$R/build/e1/sqlite-no-load" --no-load
echo "(exit $?)"
