#!/bin/sh
# old-close.sh WORKTREE [OUT]: a copy of WORKTREE at OUT/X-old-close, OUT
# by default WORKTREE/build/lead-mut,
# made without ./build and ./.git, with src/chez-sqlite3/private/connection.sls
# as it was at d1792e4, before the close fix (PR #36). Run on the host, since
# it needs git. run.sh runs test-fts5 in it.
wt=$1
d=${2:-$wt/build/lead-mut}/X-old-close
if [ -e "$d" ]; then echo "old-close.sh: $d exists" >&2; exit 1; fi
mkdir -p "$d" || exit 1
(cd "$wt" && tar --exclude=./build --exclude=./.git -cf - .) | tar -C "$d" -xf - || exit 1
git -C "$wt" show d1792e4:src/chez-sqlite3/private/connection.sls \
  > "$d/src/chez-sqlite3/private/connection.sls"
