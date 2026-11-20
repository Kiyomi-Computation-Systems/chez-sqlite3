#!/bin/sh
# Plants one defect per copy of what test-manifest reads, under
# build/m5s2/manifest-plants/, and requires test-manifest to fail exactly the
# rows named, in order. Run inside the container, from the repository root,
# after make deps, on a build/m5s2/manifest-plants/ that does not exist yet:
#
#   scripts/guix-env sh .plans/research/m5-slice-2/manifest-plants.sh
#
# Prints one line per plant: "watched-fail" when exactly the named rows
# failed, "NOT-WATCHED" otherwise, with the rows wanted and got; one for the
# control, which must pass; then a count. Exits 1 unless every plant was
# watched failing and the control passed.
set -u
root=$(pwd)
srfi="$root/build/scheme-libs"
plants="$root/build/m5s2/manifest-plants"
mkdir "$plants" || { echo "manifest-plants: $plants exists; remove it first" >&2; exit 2; }
watched=0; missed=0

# copy DIR: a copy of what test-manifest reads, at $plants/DIR.
copy() {
  mkdir "$plants/$1"
  cp -R src tests docs README.org CHANGELOG.md Akku.manifest Akku.lock .gitattributes \
    "$plants/$1/"
}

# replace DIR FILE OLD NEW: the first line of the copy's FILE holding OLD, as
# fixed text, has it replaced by NEW; the plant is noted, in DIR.notes, as
# one that did not apply when no line holds OLD.
replace() {
  f=$plants/$1/$2
  OLD=$3 NEW=$4 awk '!done && (i = index($0, ENVIRON["OLD"])) {
      $0 = substr($0, 1, i - 1) ENVIRON["NEW"] substr($0, i + length(ENVIRON["OLD"])); done = 1 }
    { print } END { exit !done }' "$f" >"$f.tmp" \
    || echo "manifest-plants: the mutation did not apply in $1: $2" >>"$plants/$1.notes"
  mv "$f.tmp" "$f"
}

# run DIR: test-manifest in the copy, as make test runs it.
run() {
  (cd "$plants/$1" && "$CHEZ" --libdirs "src:tests:$srfi" --program tests/test-manifest.sps) \
    >"$plants/$1.out" 2>"$plants/$1.err"
}

# expect NAME STATUS ROW...: the run failed, and its failing rows are
# exactly ROW..., in order.
expect() {
  name=$1 st=$2; shift 2
  got=$(sed -n 's/^FAIL //p' "$plants/$name.out")
  want=$(printf '%s\n' "$@")
  if [ "$st" -ne 0 ] && [ "$got" = "$want" ] && [ ! -s "$plants/$name.notes" ]; then
    echo "watched-fail $name (exit $st): $(printf '%s' "$want" | tr '\n' '|')"
    watched=$((watched + 1))
  else
    echo "NOT-WATCHED $name (exit $st)"; missed=$((missed + 1))
    printf '%s\n' "$want" | sed 's/^/    wanted: /'
    printf '%s\n' "$got" | sed 's/^/    got:    /'
    cat "$plants/$name.notes" 2>/dev/null | sed 's/^/    /'
  fi
}

# The rows, by name.
ga='.gitattributes marks /.plans and /AGENTS.md export-ignore, in that order, and nothing else'
reader1='attribute-lines: a comment, a blank line and an indented comment are no line;'
reader1="$reader1 blanks and tabs split words"
reader2='attribute-lines: a pattern alone is a line, and so is a # past a pattern'
dev="Akku.manifest's depends/dev is exactly chez-srfi, in the range that names the pinned"
dev="$dev version, and chez-cmark-gfm at ^2.0.0"
two="Akku.lock holds exactly two projects, chez-cmark-gfm then chez-srfi"
curl="Akku.lock's chez-cmark-gfm url holds the version Akku.manifest asks for, and the pinned one"
whole="Akku.lock's chez-cmark-gfm project is the archive make site-deps fetches, and its sha256"
sha="Akku.lock's every project carries a sha256 of 64 hex digits"

copy control; run control; st=$?
if [ "$st" -eq 0 ] && ! grep -q '^FAIL' "$plants/control.out"; then
  echo "control passes (exit 0)"
else
  echo "CONTROL FAILED (exit $st)"; missed=$((missed + 1))
fi

# --- .gitattributes ---------------------------------------------------------

plans='/.plans     export-ignore'
agents='/AGENTS.md  export-ignore'

# M1: the file gone.
copy m1; rm "$plants/m1/.gitattributes"; run m1; expect m1 $? "$ga"
# M2: its /.plans line gone, made a comment.
copy m2; replace m2 .gitattributes "$plans" "# $plans"; run m2; expect m2 $? "$ga"
# M3: its /AGENTS.md line gone.
copy m3; replace m3 .gitattributes "$agents" ''; run m3; expect m3 $? "$ga"
# M4: a third line.
copy m4; printf '/docs export-ignore\n' >>"$plants/m4/.gitattributes"; run m4; expect m4 $? "$ga"
# M5: the two lines swapped.
copy m5; printf '# swapped\n%s\n%s\n' "$agents" "$plans" >"$plants/m5/.gitattributes"
run m5; expect m5 $? "$ga"
# M6: another attribute.
copy m6; replace m6 .gitattributes "$agents" '/AGENTS.md  export-subst'; run m6; expect m6 $? "$ga"
# M7: a second attribute beside it.
copy m7; replace m7 .gitattributes "$agents" "$agents -diff"; run m7; expect m7 $? "$ga"
# M8: another pattern, one that names the directory's contents.
copy m8; replace m8 .gitattributes "$plans" '/.plans/    export-ignore'; run m8; expect m8 $? "$ga"

# M9: the reader keeps comments: its own row fails, and so does the real
# file's.
copy m9
replace m9 tests/test-manifest.sps \
  '(if (or (null? words) (char=? (string-ref (car words) 0) #\#))' '(if (null? words)'
run m9; expect m9 $? "$reader1" "$ga"
# M10: the reader splits on spaces alone: a tab-separated line is one word.
copy m10
replace m10 tests/test-manifest.sps \
  '(map (lambda (piece) (cut-at piece #\tab))' '(map (lambda (piece) (list piece))'
run m10; expect m10 $? "$reader1"
# M11: the reader reads a # anywhere as a comment.
copy m11
replace m11 tests/test-manifest.sps '(char=? (string-ref (car words) 0) #\#)' \
  '(exists (lambda (w) (char=? (string-ref w 0) #\#)) words)'
run m11; expect m11 $? "$reader2"

# --- the lock and the manifest ------------------------------------------------

lock_cmark='"bb647e07c03f103600ceb29d5545787bf0ba54563b1bbd98f3be7ac778305159"'

# L1: chez-cmark-gfm's sha256 one digit off.
copy l1
replace l1 Akku.lock '"bb647e07c03f' '"cb647e07c03f'
run l1; expect l1 $? "$whole"
# L2: its sha256 cut short.
copy l2; replace l2 Akku.lock "$lock_cmark" '"bb647e07"'; run l2; expect l2 $? "$whole" "$sha"
# L3: its url naming another version.
copy l3; replace l3 Akku.lock 'chez-cmark-gfm_2.0.0_repack' 'chez-cmark-gfm_2.0.1_repack'
run l3; expect l3 $? "$curl" "$whole"
# L4: the manifest asking for another version.
copy l4; replace l4 Akku.manifest '("chez-cmark-gfm" "^2.0.0")' '("chez-cmark-gfm" "^2.0.1")'
run l4; expect l4 $? "$dev" "$curl"
# L5: the manifest asking for no chez-cmark-gfm.
copy l5; replace l5 Akku.manifest ' ("chez-cmark-gfm" "^2.0.0")' ''
run l5; expect l5 $? "$dev" "$curl"
# L6: the lock's two projects in the other order.
copy l6
cat >"$plants/l6/Akku.lock" <<'EOF'
#!r6rs ; -*- mode: scheme; coding: utf-8 -*-
;; This file is automatically generated - do not change it by hand.
(import (akku format lockfile))
(projects
 ((name "chez-srfi")
  (location
   (url "https://archive.akkuscm.org/archive/pkg/c/chez-srfi_0.0.0-akku.181.7879b52_repack.tar.xz"))
  (content
   (sha256 "f002bc7fc669b5980c885a5fb6770f8e016b06761e8e9755154bfa3a4f578fcb")))
 ((name "chez-cmark-gfm")
  (location
   (url "https://archive.akkuscm.org/archive/pkg/c/chez-cmark-gfm_2.0.0_repack.tar.xz"))
  (content
   (sha256 "bb647e07c03f103600ceb29d5545787bf0ba54563b1bbd98f3be7ac778305159"))))
EOF
run l6; expect l6 $? "$two"
# L7: a third project.
copy l7
replace l7 Akku.lock ' ((name "chez-srfi")' ' ((name "other")
  (location (url "https://example.invalid/other_1.0.0_repack.tar.xz"))
  (content (sha256 "0000")))
 ((name "chez-srfi")'
run l7; expect l7 $? "$two" "$sha"
# L8: the manifest and the lock as they were before chez-cmark-gfm.
copy l8
cat >"$plants/l8/Akku.lock" <<'EOF'
#!r6rs ; -*- mode: scheme; coding: utf-8 -*-
;; This file is automatically generated - do not change it by hand.
(import (akku format lockfile))
(projects
 ((name "chez-srfi")
  (location
   (url "https://archive.akkuscm.org/archive/pkg/c/chez-srfi_0.0.0-akku.181.7879b52_repack.tar.xz"))
  (content
   (sha256 "f002bc7fc669b5980c885a5fb6770f8e016b06761e8e9755154bfa3a4f578fcb"))))
EOF
replace l8 Akku.manifest ' ("chez-cmark-gfm" "^2.0.0")' ''
run l8; expect l8 $? "$dev" "$two" "$curl" "$whole" "$sha"

echo "manifest-plants: $watched watched failing, $missed not"
[ "$missed" -eq 0 ]
