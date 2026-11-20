#!/bin/sh
# Plants one defect per copy of what the site's checks read, under
# build/m5s2/plants/, and requires the check each plant targets to fail,
# naming it. Run inside the container, from the repository root, after
# make check-site has passed once (so build/akku and build/scheme-libs
# exist), on a build/m5s2/plants/ that does not exist yet:
#
#   scripts/guix-env sh .plans/research/m5-slice-2/plants.sh
#
# Prints one line per plant: "watched-fail" when the check failed and said
# what was expected, "NOT-WATCHED" otherwise; one per control, which must
# pass; then a count. Exits 1 unless every plant was watched failing and
# every control passed.
set -u
root=$(pwd)
cmark="$root/build/akku/chez-cmark-gfm/src"
srfi="$root/build/scheme-libs"
plants="$root/build/m5s2/plants"
mkdir "$plants" || { echo "plants: $plants exists; remove it first" >&2; exit 2; }

watched=0; missed=0

# copy DIR: a copy of what the site's checks read, at $plants/DIR.
copy() {
  mkdir "$plants/$1"
  cp -R site build-site.sps tests docs src README.org "$plants/$1/"
}

# replace DIR FILE OLD NEW: the first line of the copy's FILE holding OLD, as
# fixed text, has it replaced by NEW; the plant is noted, in DIR.notes, as
# one that did not apply when no line holds OLD. ENVIRON passes both untouched by awk's
# escapes.
replace() {
  f=$plants/$1/$2
  OLD=$3 NEW=$4 awk '!done && (i = index($0, ENVIRON["OLD"])) {
      $0 = substr($0, 1, i - 1) ENVIRON["NEW"] substr($0, i + length(ENVIRON["OLD"])); done = 1 }
    { print } END { exit !done }' "$f" >"$f.tmp" \
    || echo "plants: the mutation did not apply in $1: $2" >>"$plants/$1.notes"
  mv "$f.tmp" "$f"
}

# two_pages DIR: the copy gains a second page, second.md, in docs/, in
# (site pages) after the reference and in README.org's links after it: a
# whole site of two pages, which the controls show passes.
two_pages() {
  printf '# Second\n\nText.\n' >"$plants/$1/docs/second.md"
  replace "$1" site/pages.sls '(("reference.md" . "API reference")))' \
    '(("reference.md" . "API reference") ("second.md" . "Second")))'
  replace "$1" README.org 'lists every name the library exports.' \
    'lists every name the library exports. See also [[file:docs/second.md][Second]].'
}

# site_check DIR: runs tests/check-site.sps in the copy, as make check-site does.
site_check() {
  (cd "$plants/$1" && "$CHEZ" --libdirs ".:$cmark" --program tests/check-site.sps) \
    >"$plants/$1.out" 2>"$plants/$1.err"
}

# site_unit DIR: runs tests/site-unit.sps in the copy, with no chez-cmark-gfm.
site_unit() {
  (cd "$plants/$1" && "$CHEZ" --libdirs ".:tests:$srfi" --program tests/site-unit.sps) \
    >"$plants/$1.out" 2>"$plants/$1.err"
}

# site_render DIR: runs tests/site-render-unit.sps in the copy.
site_render() {
  (cd "$plants/$1" &&
     "$CHEZ" --libdirs ".:$cmark:tests:$srfi" --program tests/site-render-unit.sps) \
    >"$plants/$1.out" 2>"$plants/$1.err"
}

# expect NAME STATUS WANT: the plant's command exited STATUS; WANT must be in
# its stderr or stdout, and STATUS must not be 0.
expect() {
  if [ "$2" -ne 0 ] && grep -Fq -- "$3" "$plants/$1.err" "$plants/$1.out" \
     && [ ! -s "$plants/$1.notes" ]; then
    echo "watched-fail $1 (exit $2): $3"; watched=$((watched + 1))
  else
    echo "NOT-WATCHED $1 (exit $2), wanted: $3"; missed=$((missed + 1))
    cat "$plants/$1.notes" 2>/dev/null | sed 's/^/    /'
    head -n 3 "$plants/$1.err" | sed 's/^/    /'
  fi
}

# control NAME STATUS: the unchanged copy's command passed, saying all green.
control() {
  if [ "$2" -eq 0 ] && grep -Fq "all green" "$plants/$1.out" && [ ! -s "$plants/$1.notes" ]; then
    echo "control $1 passes (exit 0, all green)"
  else
    echo "CONTROL FAILED $1 (exit $2)"; missed=$((missed + 1))
    head -n 3 "$plants/$1.err" | sed 's/^/    /'
  fi
}

# --- check-site's invariants ------------------------------------------------

nav_not="the nav is not README.org's list of the pages."
api='(reference.md . API reference)'
sec2='(second.md . Second)'
ref_link='[[file:docs/reference.md][API reference]]'
home_md='(values (string-append (page-file-name target-page) (or anchor ""))'

copy control; site_check control; control control $?
copy control2; two_pages control2; site_check control2; control control2 $?

# C1 (1): a docs page on disk that the nav does not name.
copy c1; printf '# New\n' >"$plants/c1/docs/new.md"; site_check c1
expect c1 $? 'missing-from-site/pages.sls=(new.md)'

# C2 (1): a page dropped from the nav, two pages on disk.
copy c2; two_pages c2; replace c2 site/pages.sls ' ("second.md" . "Second")' ''; site_check c2
expect c2 $? 'missing-from-site/pages.sls=(second.md)'

# C3 (7): a label changed in the nav alone.
copy c3; replace c3 site/pages.sls '"API reference")' '"Reference")'; site_check c3
expect c3 $? "$nav_not listed=($api) nav=((reference.md . Reference))"

# C4 (7): two pages swapped in the nav, the set and labels unchanged.
copy c4; two_pages c4
replace c4 site/pages.sls '(("reference.md" . "API reference") ("second.md" . "Second"))' \
  '(("second.md" . "Second") ("reference.md" . "API reference"))'
site_check c4
expect c4 $? "$nav_not listed=($api $sec2) nav=($sec2 $api)"

# C5 (7): README.org's link to a page has no label.
copy c5; replace c5 README.org "$ref_link" '[[file:docs/reference.md]]'
site_check c5
expect c5 $? 'README.org links docs/reference.md with no label'

# C6 (7): README.org's link to a page whose label no ]] closes on its line.
copy c6; replace c6 README.org "$ref_link" '[[file:docs/reference.md][API reference'
site_check c6
expect c6 $? 'has a label that no ]] closes on its line'

# A Documentation section is read in place of the whole file: its links in
# the nav's order pass, with the intro's in the other order, and a later
# section's link to a page is not read; the same section in the other order
# fails, and so does one that leaves a page out.
documentation() {  # DIR ITEM...: the copy's README.org gains the section
  d=$1; shift
  printf '\n** Documentation\n\n' >>"$plants/$d/README.org"
  for item in "$@"; do printf -- '- %s\n' "$item" >>"$plants/$d/README.org"; done
  printf '\n** License\n\nSee [[file:docs/second.md][the second page]].\n' >>"$plants/$d/README.org"
}
ref='[[file:docs/reference.md][API reference]]: every export.'
sec='[[file:docs/second.md][Second]].'
copy control3; two_pages control3
replace control3 README.org "The $ref_link lists" 'The API reference lists'
replace control3 README.org 'See also [[file:docs/second.md][Second]].' \
  'See [[file:docs/second.md][the second page]], then [[file:docs/reference.md][the reference]].'
documentation control3 "$ref" "$sec"
site_check control3; control control3 $?

# C16 (7): the section runs on past the next heading, into License.
cp -R "$plants/control3" "$plants/c16"
replace c16 tests/check-site.sps '(if (or (null? ls) (org-heading? (car ls)))' '(if (null? ls)'
site_check c16
expect c16 $? "listed=($api $sec2 (second.md . the second page))"

# C17 (7): the whole file read, though it has a Documentation section.
cp -R "$plants/control3" "$plants/c17"
replace c17 tests/check-site.sps '(if tail' '(if #f'
site_check c17
expect c17 $? "listed=((second.md . the second page) (reference.md . the reference)"

copy c7; two_pages c7; documentation c7 "$sec" "$ref"; site_check c7
expect c7 $? "$nav_not listed=($sec2 $api)"

copy c8; two_pages c8; documentation c8 "$ref"; site_check c8
expect c8 $? "$nav_not listed=($api) nav="

# C15 (7): a README.org with no Documentation section and no link to a page.
copy c15; replace c15 README.org "The $ref_link lists" 'The API reference lists'
site_check c15
expect c15 $? "$nav_not listed=() nav=($api)"

# C9 (2): a link to an anchor no heading has.
copy c9; printf '\n[x](#nonesuch)\n' >>"$plants/c9/docs/reference.md"; site_check c9
expect c9 $? 'anchor resolution FAILED. danglers=((reference.md . #nonesuch))'

# C10 (2): a link to a page's anchor that page lacks.
copy c10; two_pages c10
printf '\n[x](reference.md#nonesuch)\n' >>"$plants/c10/docs/second.md"; site_check c10
expect c10 $? 'anchor resolution FAILED. danglers=((second.md . reference.md#nonesuch))'

# C11 (3): the rewrite leaves every .md link as it is, and a page links one.
copy c11; two_pages c11; printf '\n[s](second.md)\n' >>"$plants/c11/docs/reference.md"
replace c11 site/links.sls "$home_md" '(values target'
site_check c11
expect c11 $? 'a relative .md link leaked into reference.md: (second.md)'

# C12 (4): the serializer indents each line of text after the first.
copy c12
replace c12 site/serializer.sls "(escape s '((#\\& . \"&amp;\")" \
  "(escape s '((#\\newline . \"\\n  \") (#\\& . \"&amp;\")"
site_check c12
expect c12 $? 'check-site: <pre> reflow FAILED'

# C13 (5): the wordmark links a file the site never writes.
copy c13
replace c13 site/template.sls '(a (^ (class "mark") (href "index.html")) "chez-sqlite3")' \
  '(a (^ (class "mark") (href "home.html")) "chez-sqlite3")'
site_check c13
expect c13 $? 'a link names a file the site does not write, in reference.md: (home.html)'

# C14 (6): a link out to a repository file that does not exist.
copy c14; printf '\n[x](../nonesuch.org)\n' >>"$plants/c14/docs/reference.md"; site_check c14
expect c14 $? 'a link out to the repository names no file in it, in reference.md'

# --- the home's rule ----------------------------------------------------------

# H1: a link to the home page left as its .md, and a page that links it:
# check-site's (3) names it, and site-unit's rows do, with no page linking it.
home_md_left='(values (string-append (if (string=? (page-file-name target-page) "index.html")'
home_md_left="$home_md_left"' path (page-file-name target-page)) (or anchor ""))'
copy h1; printf '\n[top](reference.md)\n' >>"$plants/h1/docs/reference.md"
replace h1 site/links.sls "$home_md" "$home_md_left"
site_check h1
expect h1 $? 'a relative .md link leaked into reference.md: (reference.md)'
copy h1u; replace h1u site/links.sls "$home_md" "$home_md_left"
site_unit h1u
expect h1u $? 'FAIL a link to the home page becomes index.html, the file it is written to'

# H2: the home page written under its own name, not index.html: check-site's
# (5) names the wordmark's link, and site-unit's rows fail.
copy h2; replace h2 site/pages.sls '(if (string=? name (car (car pages)))' '(if #f'
site_check h2
expect h2 $? 'a link names a file the site does not write, in reference.md: (index.html)'
cp -R "$plants/h2" "$plants/h2u"; site_unit h2u
expect h2u $? 'FAIL the home page, the first of pages, is written as index.html'

# --- (site render) ------------------------------------------------------------

# R1: a page's neighbours swapped.
copy r1; replace r1 site/render.sls '(values prev (if (null? (cdr ps)) #f (cadr ps)))' \
  '(values (if (null? (cdr ps)) #f (cadr ps)) prev)'
site_render r1
expect r1 $? "FAIL the first page's neighbours: none before it, and the next after"

# R2: the home page left out of the nav, as a home that is no page of the
# docs is.
copy r2; replace r2 site/render.sls '(define nav pages)' '(define nav (cdr pages))'
r2_row='FAIL on the home page, index.html is linked by the wordmark'
site_render r2
expect r2 $? "$r2_row and by its own nav entry, marked"

# R3: the first page in the nav given itself as its previous page: on
# today's one page, the rendered site's footer row sees it.
copy r3; replace r3 site/render.sls '(values prev (if (null? (cdr ps)) #f (cadr ps)))' \
  '(values (or prev (car ps)) (if (null? (cdr ps)) #f (cadr ps)))'
site_render r3
expect r3 $? "FAIL each page's footer links its neighbours in the nav, or is absent with none"

# R4: render-site asks no page's neighbours, so no footer is drawn. On one
# page there is none to draw; on two, the footer row sees it.
call='((prev next) (neighbors nav name))'
nocall='((prev next) (neighbors nav "no such page"))'
copy r4; two_pages r4; replace r4 site/render.sls "$call" "$nocall"
site_render r4
expect r4 $? "FAIL each page's footer links its neighbours in the nav, or is absent with none"
copy r4one; replace r4one site/render.sls "$call" "$nocall"
site_render r4one
if [ "$?" -eq 0 ]; then
  echo "survives r4one (exit 0): on one page the mutant draws what the page has, no footer"
else
  echo "NOT-EXPECTED r4one: it failed on one page"; missed=$((missed + 1))
fi

# --- the site's suites --------------------------------------------------------

# S1: a pure library of the site's that imports (cmark gfm): site-unit, with
# no chez-cmark-gfm on its path, fails at import.
copy s1; replace s1 site/slug.sls '(import (rnrs))' '(import (rnrs) (cmark gfm))'; site_unit s1
expect s1 $? '(cmark gfm)'

# S2: slugify keeps a "!", which GitHub drops: site-unit fails, and exits 1.
copy s2
replace s2 site/slug.sls '(or (char-alphabetic? c)' '(or (char=? c #\!) (char-alphabetic? c)'
site_unit s2
expect s2 $? 'FAIL close-database!'

# S3: a site suite that imports (chez-sqlite3-testing) fails at import, src/
# being on no site suite's path, as Ubuntu's Chez would refuse it below the
# floor.
copy s3; replace s3 tests/site-unit.sps '(import (rnrs) (srfi :64) (site-testing)' \
  '(import (rnrs) (srfi :64) (site-testing) (chez-sqlite3-testing)'
site_unit s3
expect s3 $? '(chez-sqlite3 private'

# S9: (site-testing) itself imports (chez-sqlite3-testing): every site
# suite imports it, so site-unit fails at import, src/ being on no site
# suite's path.
copy s9
replace s9 tests/site-testing.sls '  (import (rnrs) (srfi :64))' \
  '  (import (rnrs) (srfi :64) (chez-sqlite3-testing))'
site_unit s9
expect s9 $? '(chez-sqlite3 private'

# S4: a site-exit-status that ignores an unexpected pass: test-site-testing
# fails its row, and exits 1.
copy s4
replace s4 tests/site-testing.sls '(and (> pass 0) (= fail 0) (= xpass 0))' \
  '(and (> pass 0) (= fail 0))'
(cd "$plants/s4" && "$CHEZ" --libdirs "src:tests:$srfi" --program tests/test-site-testing.sps) \
  >"$plants/s4.out" 2>"$plants/s4.err"
expect s4 $? 'FAIL an unexpected pass beside a pass: exit 1'

# S5: a site-exit-form of the test suites' form: test-site-testing fails.
copy s5
replace s5 tests/site-testing.sls "(define site-exit-form '(exit (site-exit-status runner)))" \
  "(define site-exit-form '(exit (suite-exit-status runner)))"
(cd "$plants/s5" && "$CHEZ" --libdirs "src:tests:$srfi" --program tests/test-site-testing.sps) \
  >"$plants/s5.out" 2>"$plants/s5.err"
expect s5 $? 'FAIL a site suite ends with (exit (site-exit-status runner)), not the shared form'

# copy_full DIR: the whole tree but .git and build/, with the fetched
# chez-cmark-gfm, so make runs in it and fetches nothing.
copy_full() {
  mkdir "$plants/$1"
  for e in * .gitattributes .github .gitmodules; do
    [ "$e" = build ] || cp -R "$e" "$plants/$1/"
  done
  mkdir "$plants/$1/build"
  cp -R build/akku "$plants/$1/build/akku"
}

site_form='(exit (site-exit-status runner))'
extra_suite='#!r6rs
(import (rnrs) (srfi :64) (site-testing))
(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "site-extra")
(test-assert "fails" #f)
(test-end "site-extra")
'

# S6: a new site suite that fails: make check-site runs every
# tests/site-*.sps, so it fails, and never reaches tests/check-site.sps.
copy_full s6
printf '%s(exit (site-exit-status runner))\n' "$extra_suite" >"$plants/s6/tests/site-extra.sps"
make --no-print-directory -C "$plants/s6" check-site >"$plants/s6.out" 2>"$plants/s6.err"
st=$?
if grep -Fq 'all green' "$plants/s6.out"; then
  echo "S6: check-site.sps ran" >>"$plants/s6.err"; st=0
fi
expect s6 $st 'site-exit-status: exit 1 (pass 0, fail 1, xpass 0)'

# S7: the same new suite ending with (exit 0): make check-suites names it.
copy_full s7
printf '%s(exit 0)\n' "$extra_suite" >"$plants/s7/tests/site-extra.sps"
make --no-print-directory -C "$plants/s7" check-suites >"$plants/s7.out" 2>"$plants/s7.err"
expect s7 $? "tests/site-extra.sps: its last datum is (exit 0), not $site_form"

# S8: check-site with no site suite at all refuses to pass.
copy_full s8; rm -f "$plants/s8"/tests/site-*.sps
make --no-print-directory -C "$plants/s8" check-site >"$plants/s8.out" 2>"$plants/s8.err"
expect s8 $? 'check-site: no suites: nothing matches tests/site-*.sps'

# --- check-test-fails' site cases, against their plants -----------------------

# T1: the Makefile names no site suite to check-suites: check-test-fails'
# two site cases fail, make test passing each. The other cases fail too,
# their check-suites line counting the tree's site suites.
copy_full t1
replace t1 Makefile 'check-suites.sps $(SUITES) $(SITE_SUITES)' 'check-suites.sps $(SUITES)'
(cd "$plants/t1" && sh tests/check-test-fails.sh) >"$plants/t1.out" 2>"$plants/t1.err"
st=$?
no_exit='check-test-fails: FAILED site-no-exit: check-suites names a site suite with no exit'
no_exit="$no_exit form, and no suite runs: make test exited 0"
grep -Fq "$no_exit" "$plants/t1.err" \
  || { echo "T1: site-no-exit did not fail for make test's exit" >>"$plants/t1.notes"; }
exit_line='check-test-fails: FAILED site-exit-line: check-suites names a site suite that ends'
exit_line="$exit_line with the test suites' exit form, and no suite runs: make test exited 0"
expect t1 $st "$exit_line"

# T2: check-suites holds a site suite to the test suites' form: every case
# fails, the tree's own site suites named in each.
copy_full t2; replace t2 tests/check-suites.sps '        site-exit-form' '        suite-exit-form'
(cd "$plants/t2" && sh tests/check-test-fails.sh) >"$plants/t2.out" 2>"$plants/t2.err"
expect t2 $? 'check-test-fails: FAILED site-no-exit'

echo "plants: $watched watched failing, $missed not"
[ "$missed" -eq 0 ]
