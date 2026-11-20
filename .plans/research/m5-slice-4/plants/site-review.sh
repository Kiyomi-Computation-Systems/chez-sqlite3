#!/bin/sh
# Slice 2's review's site plants, on the four real pages: each must fail
# check-site once docs/ holds more than one page; R-f, every page after the
# home written to pages.html, waits on a site-unit row of its own. Run inside
# scripts/guix-env from the worktree root.
set -u
base=build/m5s4/plants/site
rm -rf "$base"; mkdir -p "$base"
fresh() {
  d="$base/$1"; mkdir -p "$d/build"
  tar --exclude=./build --exclude=./.git -cf - . | (cd "$d" && tar -xf -)
  cp -a build/akku build/scheme-libs "$d/build/"
}
# plant NAME FILE FROM TO: sed one fixed replacement, failing unless it hit once
plant() {
  before=$(grep -cF -- "$3" "$base/$1/$2")
  [ "$before" = 1 ] || { echo "$1: '$3' is on $before lines of $2"; return 1; }
  awk -v from="$3" -v to="$4" '{ i = index($0, from); if (i) $0 = substr($0, 1, i - 1) to substr($0, i + length(from)); print }' \
    "$base/$1/$2" > "$base/$1/x" && mv "$base/$1/x" "$base/$1/$2"
}
site() { (cd "$base/$1" && make -s check-site > ../$1.log 2>&1; echo "$1: check-site rc=$?"); grep '^FAIL\|check-site:' "$base/$1.log" | head -3; }
fresh control; site control
fresh Ra; plant Ra site/render.sls '(define nav pages)' '(define nav (reverse pages))' && site Ra
fresh Rb; plant Rb site/render.sls '((prev next) (neighbors nav name))' '((prev next) (neighbors (reverse nav) name))' && site Rb
fresh Rc; plant Rc site/render.sls '(define nav pages)' '(define nav (list (car pages)))' && site Rc
fresh Rd; plant Rd site/pages.sls '(if (string=? name (car (car pages)))' '(if (string=? name (car (car (reverse pages))))' && site Rd
fresh P1; plant P1 site/pages.sls '(if (string=? name (car (car pages)))' '(if (assoc name pages)' && site P1
fresh Rf; plant Rf site/pages.sls '(if (string=? name (car (car pages)))' '(if (assoc name (cdr pages)) "pages.html" (if (string=? name (car (car pages)))' && plant Rf site/pages.sls '".html"))))' '".html")))))' && site Rf
