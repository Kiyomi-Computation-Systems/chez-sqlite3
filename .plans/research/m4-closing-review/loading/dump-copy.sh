#!/bin/sh
# dump-copy.sh SRC DEST: a whole copy of the tree SRC at DEST (no build/, no
# .git), each loading suite's on-test-end hook made to print every row as
# ROW (KIND NAME EXPECTED), for comparing the layouts' rows.
set -eu
src=$1; dest=$2
mkdir -p "$dest"
(cd "$src" && tar --exclude=./build --exclude=./.git -cf - .) | (cd "$dest" && tar xf -)
n=0
for f in "$dest"/tests/test-library-loading-*.sps; do
  python3 - "$f" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "      (simple-end r)\n"
new = old + "      (display \"ROW \") (write (list (test-result-kind r) (test-runner-test-name r) (test-result-ref r 'expected-value))) (newline)\n"
assert s.count(old) == 1, (p, s.count(old))
open(p, 'w').write(s.replace(old, new))
PY
  n=$((n + 1))
done
echo "dump-copy: $n suites patched in $dest"
