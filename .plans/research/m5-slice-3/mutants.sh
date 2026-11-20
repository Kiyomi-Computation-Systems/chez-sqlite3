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

# --- pages.yml's lines ---
mutant pages-no-compare "pages.yml: a line changed, the trigger widened to every tag" \
  '} else if ($0 != want[held]) {' '} else if (0) {'
mutant pages-no-early "pages.yml: the last line dropped" \
  'if (!done && held < nwant) prob(' 'if (0) prob('
mutant pages-no-extra "pages.yml: a line added at the end" \
  'if (held > nwant) {' 'if (0) {'
mutant pages-every-line "pages.yml: a line dropped, the deploy job's needs" \
  'if ($0 ~ /^ *$/ || $0 ~ /^ *#/ || done) next' 'if ($0 ~ /^ *$/ || $0 ~ /^ *#/) next'
mutant pages-any-hash "the unedited file passes" \
  'if ($0 ~ /^ *$/ || $0 ~ /^ *#/ || done) next' 'if ($0 ~ /^ *$/ || $0 ~ /#/ || done) next'
mutant pages-comment-tab "pages.yml: a tab in a comment" \
  'if (index($0, "\t") > 0) prob(FNR,' 'if (index($0, "\t") > 0 && $0 !~ /^ *#/) prob(FNR,'
mutant pages-comment-odd "pages.yml: a line separator, U+2028, in a comment" \
  'if (odd($0)) prob(FNR,' 'if (odd($0) && $0 !~ /^ *#/) prob(FNR,'
mutant pages-no-odd "pages.yml: a character beyond ASCII in a held line" \
  'if (odd($0)) prob(FNR,' 'if (0) prob(FNR,'

# --- ci.yml's comments ---
mutant ci-comment-skipped "a line separator, U+2028, in a comment" \
  'if (substr(raw, ind + 1, 1) == "#") {' 'if (substr(raw, ind + 1, 1) == "#") { next'

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
