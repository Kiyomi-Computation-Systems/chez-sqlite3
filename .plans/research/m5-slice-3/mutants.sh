#!/bin/sh
# Mutants of tests/check-ci.sh: each loosens one rule the slice added, in a
# copy under build/m5s3/mutants/NAME/, and runs a copy of
# tests/test-check-ci.sps against it, with CHECK_CI_ROOT at the repository
# root so the execute-bit rows read the real scripts/ci. Run inside the
# container, from the repository root, after make deps, on a
# build/m5s3/mutants/ that does not exist yet:
#
#   scripts/guix-env sh .plans/research/m5-slice-3/mutants.sh
#
# Each mutant names one row it must fail. Prints one line per mutant: "killed"
# when the suite exited 1 with that row among its failures, with how many rows
# failed, or "SURVIVED"; then the control, the copy unmutated, which must pass
# every row; then a count. Exits 1 unless every mutant was killed and the
# control passed. Each mutant's log is its directory's log.
set -u
root=$(pwd)
mut=$root/build/m5s3/mutants
mkdir "$mut" || { echo "mutants: $mut exists; remove it first" >&2; exit 2; }
killed=0; survived=0

# prepare NAME OLD NEW: NAME's copy of tests/check-ci.sh, its first line that
# holds OLD, as fixed text, with it replaced by NEW (OLD empty: no change),
# and a copy of the suite that runs it. Fails when OLD is on no line.
prepare() {
  d=$mut/$1
  mkdir "$d"
  OLD=$2 NEW=$3 awk 'ENVIRON["OLD"] == "" { print; next }
    !done && (i = index($0, ENVIRON["OLD"])) {
      $0 = substr($0, 1, i - 1) ENVIRON["NEW"] substr($0, i + length(ENVIRON["OLD"]))
      done = 1 }
    { print } END { exit !(done || ENVIRON["OLD"] == "") }' tests/check-ci.sh >"$d/check-ci.sh" ||
    { echo "mutants: $1: the mutation did not apply"; return 1; }
  sed "s|^(define script \"tests/check-ci.sh\")\$|(define script \"$d/check-ci.sh\")|" \
    tests/test-check-ci.sps >"$d/suite.sps"
  grep -q "^(define script \"$d/check-ci.sh\")\$" "$d/suite.sps" ||
    { echo "mutants: $1: the suite's copy does not run the mutant"; return 1; }
}

# run NAME: the suite's copy on NAME's mutant; its status, and its failures
# in NAME/failed.
run() {
  d=$mut/$1
  CHECK_CI_ROOT=$root $CHEZ --libdirs src:tests:build/scheme-libs --program "$d/suite.sps" \
    >"$d/log" 2>&1
  st=$?
  sed -n 's/^FAIL //p' "$d/log" >"$d/failed"
  return $st
}

# mutant NAME TARGET OLD NEW
mutant() {
  if ! prepare "$1" "$3" "$4"; then survived=$((survived + 1)); return; fi
  if run "$1"; then
    echo "SURVIVED $1: the suite passed"; survived=$((survived + 1))
  elif grep -qxF "$2" "$mut/$1/failed"; then
    echo "killed $1: $(wc -l <"$mut/$1/failed" | tr -d ' ') rows failed, among them \"$2\""
    killed=$((killed + 1))
  else
    echo "SURVIVED $1: \"$2\" passed ($(wc -l <"$mut/$1/failed" | tr -d ' ') rows failed)"
    survived=$((survived + 1))
  fi
}

# --- the directory ---
mutant dir-any "a third workflow in the directory" \
  '      ci.yml | pages.yml) ;;' '      *) ;;'
mutant pages-link "pages.yml is a link" \
  'if [ -L "$pages" ] || [ ! -f "$pages" ]; then' 'if [ ! -f "$pages" ]; then'
mutant pages-missing "pages.yml is missing" \
  'note "$pages: is not a regular file: a link, a directory or nothing there"' ':'

# --- pages.yml's lines (the copy reader, which job site's install step shares) ---
mutant pages-no-compare "pages.yml: a line changed, the trigger widened to every tag" \
  'if (s != cpc[cp_held]) {' 'if (0) {'
mutant pages-no-early "pages.yml: the last line dropped" \
  'if (cp_held < nc) {' 'if (0) {'
mutant pages-no-extra "pages.yml: a line added at the end" \
  'if (cp_held > cp_nc) {' 'if (0) {'
mutant pages-every-line "pages.yml: a line dropped, the deploy job's needs" \
  'if (!cpline(s, cpfl[i])) return 1' 'cpline(s, cpfl[i])'
mutant pages-any-hash "the unedited file passes" \
  '(blank || (!inb && s ~ /^ *#/))' '(blank || (!inb && s ~ /#/))'
mutant pages-comment-tab "pages.yml: a tab in a comment" \
  'if (index($0, "\t") > 0) prob(FNR,' 'if (index($0, "\t") > 0 && $0 !~ /^ *#/) prob(FNR,'
mutant pages-comment-odd "pages.yml: a line separator, U+2028, in a comment" \
  'if (odd($0)) prob(FNR,' 'if (odd($0) && $0 !~ /^ *#/) prob(FNR,'
mutant pages-no-odd "pages.yml: a character beyond ASCII in a held line" \
  'if (odd($0)) prob(FNR,' 'if (0) prob(FNR,'

# --- ci.yml's comments ---
mutant ci-comment-skipped "a line separator, U+2028, in a comment" \
  'if (!content && substr(raw, ind + 1, 1) == "#") {' \
  'if (!content && substr(raw, ind + 1, 1) == "#") { next'

# --- the site job ---
mutant site-not-missed "site: the job deleted" \
  'for (i = 1; i <= 7; i++)' 'for (i = 1; i <= 6; i++)'
mutant site-no-checks "site: the step that runs make check-site deleted" \
  'if (j == "site") {' 'if (j == "site") { return 0'
mutant site-any-order "site: make check-site before make site-deps" \
  'if (pos <= lastp) prob(' 'if (pos <= lastp && job != "site") prob('
mutant site-no-env "site: the step that runs make site without CHEZ" \
  'if (job == "site") needenv(at, x, "CHEZ")' 'if (0) needenv(at, x, "CHEZ")'
mutant site-any-chez \
  "site: the step that runs make check-site with CHEZ /usr/bin/chezscheme" \
  'if (key == "CHEZ" && val != want) prob(' \
  'if (key == "CHEZ" && val != want && job != "site") prob('
mutant site-if-ok "site: an if on the install step" \
  'if (S_if[sn] != "") prob(S_ifln[sn], "job site takes no if' \
  'if (0) prob(S_ifln[sn], "job site takes no if'
mutant site-cache-ok "site: a Chez cache restored before the install step" \
  'if (S_uses[s] != "" && !(S_uses[s] ~ /^actions\/checkout@/))' \
  'if (S_uses[s] != "" && !(S_uses[s] ~ /^actions\/(checkout|cache\/restore|cache\/save)@/))'
mutant site-no-checkout "site: the checkout without submodules" \
  'if (job == "main" || isl(job) || job == "site") {' 'if (job == "main" || isl(job)) {'
mutant site-key-held "site: a Chez cache restored before the install step" \
  '!isl(job) && job != "site" && !cachekey_ok(val)' '!isl(job) && !cachekey_ok(val)'
mutant site-names-free "site: make site with SITE_REF on its run line" \
  ' SITE_REF CHEZ_CMARK_GFM_LIBS", bw, " ")' '", bw, " ")'

# --- round 2: the review's three survivors, its glob reverted, and the new rules ---
mutant run-block-free "pages.yml: a line of the run block changed, exit 1 to true" \
  'if (s != cpc[cp_held]) {' 'if (!cpb[cp_held] && s != cpc[cp_held]) {'
mutant indent-free "pages.yml: a held line's indent changed" \
  'if (s != cpc[cp_held]) {' \
  'w1 = cpc[cp_held]; s1 = s; sub(/^ +/, "", w1); sub(/^ +/, "", s1); if (s1 != w1) {'
mutant content-comment-free "a character beyond ASCII, U+0085, in a comment line of a run block" \
  'if (!content && substr(raw, ind + 1, 1) == "#") {' \
  'if (content && substr(raw, ind + 1, 1) == "#") next; if (substr(raw, ind + 1, 1) == "#") {'
mutant content-names-free \
  "an expression in a comment line of a run block names GITHUB_ENV and MAKEFLAGS" \
  'if (!content && substr(raw, ind + 1, 1) == "#") {' 'if (substr(raw, ind + 1, 1) == "#") {'
mutant content-scripts-free "a comment line of a run block names scripts/" \
  'if (content && substr(raw, ind + 1, 1) == "#" && index(raw, "scripts/") > 0)' \
  'if (0)'
mutant block-by-copy-only \
  "pages.yml: an expression in a comment line after the run block's last line" \
  'if (!cpb[cp_held] && opens(s)) { inb = 1; col = keycol(s) }' 'if (0) { inb = 1 }'
mutant block-by-file-only "pages.yml: a comment at column 0 inside the run block" \
  'if (!(cp_held < nc && cpb[cp_held + 1]) && (blank' 'if ((blank'
mutant blanks-never-held \
  "pages.yml: a blank line, then a comment line, after the run block's last line" \
  'for (j = 1; j <= np; j++) if (!cpline' 'for (j = 1; j <= 0; j++) if (!cpline'
mutant blanks-always-held "pages.yml: blank lines between the run block and the next step pass" \
  'if (inb && !blank && indent(s) <= col) { inb = 0; np = 0 }' \
  'if (inb && !blank && indent(s) <= col) { inb = 0 }'
mutant literal-blind "the unedited file passes" \
  's ~ /: [|>][-+0-9]*( +#.*)?$/' 's ~ /: [>][-+0-9]*( +#.*)?$/'
mutant site-any-count "site: a seventh step links /bin/true over chezscheme" \
  'if (n != 6) prob(' 'if (0) prob('
mutant site-install-free "site: the install line gains a package" \
  'cpcheck(k, ninst, "job site' '0 && cpcheck(k, ninst, "job site'
mutant name-raw "a third file named pages.yml, a newline, ci.yml" \
  'shown=$(printf' 'shown=$name; : $(printf'
mutant dir-ls "a third file named ci.yml, a newline, pages.yml" \
  'for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do' \
  'ls -A -- "$dir" | while IFS= read -r e; do entry=$dir/$e'

# --- the control: the copy unmutated ---
control=bad
if prepare control '' '' && run control && [ ! -s "$mut/control/failed" ]; then
  control=ok
  n=$(sed -n 's/^# of expected passes *//p' "$mut/control/log")
  echo "control: the unmutated copy passes: $n rows"
else
  echo "CONTROL FAILED: see $mut/control/log"
fi

echo "mutants: $killed killed, $survived survived; control $control"
[ "$survived" -eq 0 ] && [ "$control" = ok ]
