#!/bin/sh
# Slice 4's checks on the real pages: each plant in a fresh copy of the
# worktree, the check that must catch it, and the lines it printed. Run
# inside scripts/guix-env from the worktree root.
set -u
base=build/m5s4/plants/real
rm -rf "$base"; mkdir -p "$base"
fresh() {
  d="$base/$1"; mkdir -p "$d/build"
  tar --exclude=./build --exclude=./.git -cf - . | (cd "$d" && tar -xf -)
  cp -a build/akku build/scheme-libs "$d/build/"
}
# swap NAME FILE OLD NEW: replace the one line OLD with NEW, failing unless
# OLD is there exactly once.
swap() {
  n=$(grep -cxF -- "$3" "$base/$1/$2")
  [ "$n" = 1 ] || { echo "$1: expected one line '$3' in $2, found $n"; return 1; }
  awk -v old="$3" -v new="$4" '$0 == old { print new; next } { print }' "$base/$1/$2" > "$base/$1/$2.new" &&
    mv "$base/$1/$2.new" "$base/$1/$2"
}
suite() { (cd "$base/$1" && $CHEZ --libdirs src:tests:build/scheme-libs --program "tests/$2.sps" > ../$1.log 2>&1; echo "$1: $2 rc=$?"); grep '^FAIL' "$base/$1.log" | head -3; }
floors() { (cd "$base/$1" && make -s check-floors > ../$1.log 2>&1; echo "$1: check-floors rc=$?"); grep 'contains\|FAILED' "$base/$1.log" | head -4; }

fresh twin-off; swap twin-off README.org '    (execute! db "insert into pets values (?, ?)" "cat" 4)' '    (execute! db "insert into pets values (?, ?)" "cat" 5)' && suite twin-off test-docs
fresh twin-plain; swap twin-plain docs/quickstart.md '```scheme run' '```scheme' && suite twin-plain test-docs
fresh clone-branch; swap clone-branch docs/quickstart.md 'git clone https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git' 'git clone --branch v0.1.0 https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git' && suite clone-branch test-manifest
fresh clone-second; printf '\n```sh\ngit clone https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git\n```\n' >> "$base/clone-second/docs/libraries.md"; suite clone-second test-manifest
fresh floor-page; printf '\nUbuntu 24.04 ships SQLite 3.45.1.\n' >> "$base/floor-page/docs/libraries.md"; floors floor-page
fresh floor-number; printf '\nIts number is 3045001.\n' >> "$base/floor-number/docs/finding-sqlite.md"; floors floor-number
fresh floor-status; swap floor-status README.org '- macOS 26 on arm64, on Apple'"'"'s 3.51.0 and on Homebrew'"'"'s 3.54.1.' '- macOS 26 on arm64, on Apple'"'"'s 3.51.0, on Homebrew'"'"'s 3.54.1, and Chez 10.4.0.' && floors floor-status
fresh nodoc; swap nodoc README.org '** Documentation' '** The pages' && (cd "$base/nodoc" && make -s check-site > ../nodoc.log 2>&1; echo "nodoc: check-site rc=$?"); grep 'check-site:' "$base/nodoc.log" | tail -1
