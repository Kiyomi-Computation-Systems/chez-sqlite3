#!/bin/sh
# The review's mutant A2, exactly: twin-problems keeps only each page's last
# runnable block. Run inside scripts/guix-env from the worktree root.
set -u
d=build/m5s4/plants/fixes/twinA2x
rm -rf "$d"; mkdir -p "$d/build"
tar --exclude=./build --exclude=./.git -cf - . | (cd "$d" && tar -xf -)
cp -a build/akku build/scheme-libs "$d/build/"
awk '
  $0 == "                                (filter (lambda (b) (and (string=? (block-language b) \"scheme\")" && !done {
    print "                                (let ((rs (filter (lambda (b) (and (string=? (block-language b) \"scheme\")"; m = 1; next }
  m == 1 && $0 == "                                        (car (markdown t))))" {
    print "                                        (car (markdown t)))))"
    print "                                  (if (null? rs) (quote ()) (list (car (reverse rs))))))"
    m = 0; done = 1; next }
  { print }' "$d/tests/test-docs.sps" > "$d/x" && mv "$d/x" "$d/tests/test-docs.sps"
grep -c 'car (reverse rs)' "$d/tests/test-docs.sps"
(cd "$d" && $CHEZ --libdirs src:tests:build/scheme-libs --program tests/test-docs.sps > ../twinA2x.log 2>&1; echo "twinA2x: test-docs rc=$?")
grep '^FAIL\|expected passes' build/m5s4/plants/fixes/twinA2x.log
