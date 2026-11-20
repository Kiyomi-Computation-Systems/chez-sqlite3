#!/bin/sh
# The neighbours plant on the real four-page nav: render-site asks for the
# neighbours of a page no nav holds, so no page draws a footer. Run inside
# scripts/guix-env from the worktree root.
set -u
dir=build/m5s4/plants/r4
rm -rf "$dir"; mkdir -p "$dir/build"
tar --exclude=./build --exclude=./.git -cf - . | (cd "$dir" && tar -xf -)
cp -a build/akku "$dir/build/akku"
cp -a build/scheme-libs "$dir/build/scheme-libs"
call='((prev next) (neighbors nav name))'
nocall='((prev next) (neighbors nav "no such page"))'
n=$(grep -cF "$call" "$dir/site/render.sls")
[ "$n" = 1 ] || { echo "plant r4: expected 1 match, found $n"; exit 2; }
sed -i "s|((prev next) (neighbors nav name))|((prev next) (neighbors nav \"no such page\"))|" "$dir/site/render.sls"
grep -cF "(define (neighbors nav name)" "$dir/site/render.sls"
grep -cF "$nocall" "$dir/site/render.sls"
cd "$dir" && make check-site > ../r4.log 2>&1
echo "r4 check-site rc=$?"
grep -n 'FAIL\|fail' ../r4.log | head -5
