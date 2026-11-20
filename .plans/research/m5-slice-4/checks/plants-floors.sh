#!/bin/sh
# Plants for check-floors' docs input. Run from the worktree root, inside the
# container:  scripts/guix-env sh build/m5s4-checks/plants-floors.sh
#
# Library mutants: a mutated copy of tests/floors.sls in a directory of its
# own, put first on the suite's library path, so the suite's pure rows load
# it (its program rows still run the tree's (floors), as make does).
# Program mutants: a mutated copy of tests/check-floors.sps, and a copy of the
# suite whose program is that copy. The Makefile plant and the tree plants
# change Makefile, README.org or docs/ in place, restored from a backup taken
# first, on exit too. A last run on the restored tree must pass.
set -u
out=build/m5s4-checks/floors
mkdir -p "$out"
for f in Makefile README.org docs/quickstart.md; do cp "$f" "$out/$(basename "$f").orig"; done
restore() {
  for f in Makefile README.org docs/quickstart.md; do cp "$out/$(basename "$f").orig" "$f"; done
  rm -f docs/plant.md
}
trap restore EXIT

make deps >/dev/null || exit 1

suite() { # name libdir-or-empty suite-path
  if [ -n "$2" ]; then libs="$2:src:tests:build/scheme-libs"; else libs="src:tests:build/scheme-libs"; fi
  $CHEZ --libdirs "$libs" --program "$3" >"$out/$1.log" 2>&1
  rc=$?
  echo "=== $1: exit $rc, $(grep -c '^FAIL' "$out/$1.log") FAIL"
  grep -A2 '^FAIL' "$out/$1.log" | cut -c1-400 | head -12
}

lib_mutant() { # name, with the sed script on stdin
  mkdir -p "$out/$1"
  cat >"$out/$1.sed"
  sed -f "$out/$1.sed" tests/floors.sls >"$out/$1/floors.sls"
  if cmp -s tests/floors.sls "$out/$1/floors.sls"; then echo "=== $1: THE MUTANT CHANGED NOTHING"; return; fi
  suite "$1" "$out/$1" tests/test-check-floors.sps
}

prog_mutant() { # name, with the sed script on stdin
  cat >"$out/$1.sed"
  sed -f "$out/$1.sed" tests/check-floors.sps >"$out/$1.sps"
  if cmp -s tests/check-floors.sps "$out/$1.sps"; then echo "=== $1: THE MUTANT CHANGED NOTHING"; return; fi
  sed "s|^(define program \"tests/check-floors.sps\")\$|(define program \"$out/$1.sps\")|" \
    tests/test-check-floors.sps >"$out/$1-suite.sps"
  cmp -s tests/test-check-floors.sps "$out/$1-suite.sps" && echo "=== $1: THE SUITE STILL RUNS THE TREE'S PROGRAM"
  suite "$1" "" "$out/$1-suite.sps"
}

# --- (floors) ---------------------------------------------------------------
lib_mutant fm-docs-never-fires <<'EOF'
s/^  (define (docs-problems fpath ddir pages floors)$/  (define (docs-problems fpath ddir pages floors) '())\n  (define (docs-problems-unused fpath ddir pages floors)/
EOF
lib_mutant fm-readme-other-lines-unheld <<'EOF'
s/^                 (readme-line-problems rpath lines fpath (floor-rows floors)))))))$/                 '())))))/
EOF
lib_mutant fm-requirements-prose-exempt <<'EOF'
s/^                  ((and in? (list-line? line)) (loop (cdr rest) (+ n 1) #t found))$/                  (in? (loop (cdr rest) (+ n 1) #t found))/
EOF
lib_mutant fm-list-lines-exempt-anywhere <<'EOF'
s/^                  ((and in? (list-line? line)) (loop (cdr rest) (+ n 1) #t found))$/                  ((list-line? line) (loop (cdr rest) (+ n 1) in? found))/
EOF
lib_mutant fm-a-heading-keeps-the-section <<'EOF'
s/^                  ((heading? line) (loop (cdr rest) (+ n 1) #f (cons complaints found)))$/                  ((heading? line) (loop (cdr rest) (+ n 1) in? (cons complaints found)))/
EOF
lib_mutant fm-docs-names-unheld <<'EOF'
s/^                         (name-problems ddir (car entry) fpath rows docs-who)$/                         '()/
EOF
lib_mutant fm-docs-unsorted <<'EOF'
s/^          (sorted (list-sort (lambda (a b) (string<? (car a) (car b))) pages)))$/          (sorted pages))/
EOF
lib_mutant fm-docs-empty-passes <<'EOF'
s/^          (list (string-append ddir ": it holds no file, but must hold the docs' pages"))$/          '()/
EOF
lib_mutant fm-docs-lines-joined <<'EOF'
s/^                             (let loop ((rest (split (cadr entry) #\\newline)) (n 1))$/                             (let loop ((rest (map (lambda (l) (or l "")) (joined-lines (split (cadr entry) #\\newline)))) (n 1))/
EOF
lib_mutant fm-docs-yaml-rules <<'EOF'
s/^                                   (append (floor-complaints (car entry) (string-append "line " (number->string n))$/                                   (append (line-problems (car entry) fpath (list (car rest)) rows) (floor-complaints (car entry) (string-append "line " (number->string n))/
EOF

# --- check-floors.sps ---------------------------------------------------------
prog_mutant pm-docs-unheld <<'EOF'
s/^                 (if (and pages (null? (floors-problems fpath (cadr f))))$/                 (if #f/
EOF
prog_mutant pm-docs-unreadable-unnamed <<'EOF'
s/^            (unreadable d))))$/            '())))/
EOF
prog_mutant pm-four-arguments <<'EOF'
s/^  (if (not (= (length args) 5))$/  (if (not (memv (length args) '(4 5)))/
s/^             (ddir (car (cddddr args)))$/             (ddir (if (= (length args) 5) (car (cddddr args)) "docs"))/
EOF

# --- the Makefile without the docs argument -----------------------------------
sed 's|^\(	@$(CHEZ) --libdirs tests --program tests/check-floors.sps packaging/floors.sexp README.org .github/workflows scripts/ci\) docs$|\1|' \
  "$out/Makefile.orig" >Makefile
cmp -s Makefile "$out/Makefile.orig" && echo "PLANT CHANGED NOTHING in Makefile"
make check-floors >"$out/p-makefile-no-docs.log" 2>&1; echo "=== p-makefile-no-docs: make check-floors exit $?"; cat "$out/p-makefile-no-docs.log"
restore

# --- the plants of the M5 plan's 4.10, on the stand-ins -----------------------
cat >docs/plant.md <<'EOF'
# A planted page

3.45.1 at the start of a line
in the middle 3.45.1 of a line
at the end of a line 3.45.1
3045001 at the start of a line
in the middle 3045001 of a line
at the end of a line 3045001
3450100 at the start of a line
in the middle 3450100 of a line
at the end of a line 3450100
beside letters x3.45.1x x3045001x x3450100x
beside digits 13.45.11 130450011 134501001
beside punctuation (3.45.1) (3045001) (3450100)
beside spaces  3.45.1  3045001  3450100
EOF
make check-floors >"$out/p-page-sqlite-floor.all" 2>&1; echo "=== p-page-sqlite-floor: make check-floors exit $?"
grep '^check-floors: ' "$out/p-page-sqlite-floor.all" >"$out/p-page-sqlite-floor.log"
w='which no page may write: a page links to README.org'"'"'s Requirements, which state it from packaging/floors.sexp'
v='3045001, the version-number form of the SQLite floor 3.45.1'
a='3450100, the amalgamation form of the SQLite floor 3.45.1'
{
  for n in 3 4 5; do echo "check-floors: docs/plant.md: line $n contains the SQLite floor 3.45.1, $w"; done
  for n in 6 7 8; do echo "check-floors: docs/plant.md: line $n contains $v, $w"; done
  for n in 9 10 11; do echo "check-floors: docs/plant.md: line $n contains $a, $w"; done
  echo "check-floors: docs/plant.md: line 12 contains the SQLite floor 3.45.1, $w"
  echo "check-floors: docs/plant.md: line 13 contains the SQLite floor 3.45.1, $w"
  echo "check-floors: docs/plant.md: line 14 contains the SQLite floor 3.45.1, $w"
  echo "check-floors: docs/plant.md: line 14 contains $v, $w"
  echo "check-floors: docs/plant.md: line 14 contains $a, $w"
  echo "check-floors: docs/plant.md: line 15 contains the SQLite floor 3.45.1, $w"
  echo "check-floors: docs/plant.md: line 15 contains $v, $w"
  echo "check-floors: docs/plant.md: line 15 contains $a, $w"
  echo "check-floors: FAILED (problems: 17)"
} >"$out/p-page-sqlite-floor.want"
if cmp -s "$out/p-page-sqlite-floor.log" "$out/p-page-sqlite-floor.want"; then
  echo "    its check-floors lines are exactly the 17 expected (lines 12 and 13: the dotted text only, beside letters and digits)"
else
  echo "    STDERR DIFFERS:"; diff "$out/p-page-sqlite-floor.want" "$out/p-page-sqlite-floor.log"
fi
head -2 "$out/p-page-sqlite-floor.log"; tail -1 "$out/p-page-sqlite-floor.log"
restore

awk '{print} $0 == "** Status" {getline; print; print "It runs on Chez Scheme 10.4.0, built with threads."}' "$out/README.org.orig" >README.org
cmp -s README.org "$out/README.org.orig" && echo "PLANT CHANGED NOTHING in README.org"
make check-floors >"$out/p-readme-status-chez.log" 2>&1; echo "=== p-readme-status-chez: make check-floors exit $?"; cat "$out/p-readme-status-chez.log"
restore

awk '{print} /^```sh$/ && !done {getline; print; print "sqlite3 --version   # 3.45.1"; done=1}' "$out/quickstart.md.orig" >docs/quickstart.md
cmp -s docs/quickstart.md "$out/quickstart.md.orig" && echo "PLANT CHANGED NOTHING in docs/quickstart.md"
make check-floors >"$out/p-page-code-block.log" 2>&1; echo "=== p-page-code-block: make check-floors exit $?"; cat "$out/p-page-code-block.log"
restore

# --- the restored tree --------------------------------------------------------
make check-floors; echo "=== restored: make check-floors exit $?"
suite restored "" tests/test-check-floors.sps
tail -1 "$out/restored.log"
