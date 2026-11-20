#!/bin/sh
# The checks review's survivors, against the fixed checks: each mutant or
# plant in a fresh copy of the worktree, and what caught it. Run inside
# scripts/guix-env from the worktree root.
set -u
base=build/m5s4/plants/fixes
rm -rf "$base"; mkdir -p "$base"
fresh() {
  d="$base/$1"; mkdir -p "$d/build"
  tar --exclude=./build --exclude=./.git -cf - . | (cd "$d" && tar -xf -)
  cp -a build/akku build/scheme-libs "$d/build/"
}
swap() {
  n=$(grep -cxF -- "$3" "$base/$1/$2")
  [ "$n" = 1 ] || { echo "$1: expected one line '$3' in $2, found $n"; return 1; }
  awk -v old="$3" -v new="$4" '$0 == old { print new; next } { print }' "$base/$1/$2" > "$base/$1/$2.new" &&
    mv "$base/$1/$2.new" "$base/$1/$2"
}
suite() { (cd "$base/$1" && $CHEZ --libdirs src:tests:build/scheme-libs --program "tests/$2.sps" > ../$1.log 2>&1; echo "$1: $2 rc=$?"); grep '^FAIL\|expected passes' "$base/$1.log" | head -4; }
site() { (cd "$base/$1" && make -s check-site > ../$1.log 2>&1; echo "$1: check-site rc=$?"); grep 'check-site:' "$base/$1.log" | tail -1; }

fresh control; suite control test-docs; suite control test-manifest; site control
fresh twinA1; swap twinA1 tests/test-docs.sps '                              md-texts))))' "                              (if (null? md-texts) '() (list (car (reverse md-texts))))))))" && suite twinA1 test-docs
fresh twinA2; swap twinA2 tests/test-docs.sps '                                        (car (markdown t))))' '                                        (let ((bs (car (markdown t)))) (if (null? bs) bs (list (car (reverse bs)))))))' && suite twinA2 test-docs
fresh twinFirst; swap twinFirst tests/test-docs.sps '                                        (car (markdown t))))' '                                        (let ((bs (car (markdown t)))) (if (null? bs) bs (list (car bs))))))' && suite twinFirst test-docs
fresh quote; printf '\n#+begin_quote\n#+begin_src scheme\n(display "no twin")\n#+end_src\n#+end_quote\n' >> "$base/quote/README.org"; suite quote test-docs
fresh dup2; printf '\n** Documentation\n\n- [[file:docs/libraries.md][Old label]]\n' >> "$base/dup2/README.org"; site dup2
fresh clone-ok-other; printf '\n```sh\ngit clone https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git\n```\n' >> "$base/clone-ok-other/docs/libraries.md"; suite clone-ok-other test-manifest
fresh clone-bad-other; printf '\n```sh\ngit clone --branch v0.1.0 https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git\n```\n' >> "$base/clone-bad-other/docs/libraries.md"; suite clone-bad-other test-manifest; grep -A2 '^FAIL' "$base/clone-bad-other.log" | grep 'actual' | cut -c1-220
