#!/bin/sh
# Plants for test-docs' twin rule. Run from the worktree root, inside the
# container:  scripts/guix-env sh build/m5s4-checks/plants-twin.sh
# Code mutants run on a copy of the suite under build/; tree plants change
# README.org or docs/quickstart.md in place and restore them from a backup
# taken first, on exit too. Each prints the suite's FAIL lines with their
# values, and its exit status. A last run on the restored tree must pass.
set -u
out=build/m5s4-checks/twin
mkdir -p "$out"
cp README.org "$out/README.org.orig"
cp docs/quickstart.md "$out/quickstart.md.orig"
restore() { cp "$out/README.org.orig" README.org; cp "$out/quickstart.md.orig" docs/quickstart.md; }
trap restore EXIT

make deps >/dev/null || exit 1

run() { # name program
  $CHEZ --libdirs src:tests:build/scheme-libs --program "$2" >"$out/$1.log" 2>&1
  rc=$?
  echo "=== $1: exit $rc"
  grep -A2 '^FAIL' "$out/$1.log" | cut -c1-400
}

mutant() { # name, with the sed script on stdin
  cat >"$out/$1.sed"
  sed -f "$out/$1.sed" tests/test-docs.sps >"$out/$1.sps"
  if cmp -s tests/test-docs.sps "$out/$1.sps"; then echo "=== $1: THE MUTANT CHANGED NOTHING"; return; fi
  run "$1" "$out/$1.sps"
}

mutant m-never-fires <<'EOF'
s/(list (list name 'no-scheme-block))/'()/
s/(list (list name (block-line b) 'no-twin))/'()/
EOF
mutant m-always-fires <<'EOF'
s/^    (if (null? blocks)$/    (if #t/
EOF
mutant m-any-scheme-block <<'EOF'
s/(eq? (scheme-mark b #f) 'run)/#t/
EOF
mutant m-lines-trimmed <<'EOF'
s/(equal? (block-lines b) (block-lines r))/(equal? (map trim (block-lines b)) (map trim (block-lines r)))/
EOF
mutant m-prefix-is-twin <<'EOF'
s/(equal? (block-lines b) (block-lines r))/(let ((n (length (block-lines b))) (rl (block-lines r))) (and (<= n (length rl)) (equal? (block-lines b) (reverse (list-tail (reverse rl) (- (length rl) n))))))/
EOF
mutant m-first-block-only <<'EOF'
s/^                    blocks)))))$/                    (list (car blocks)))))))/
EOF

# The plants of the M5 plan's 4.10, on the stand-ins.
sed 's/^    (execute! db "insert into t values (?)" 42)$/    (execute! db "insert into t values (?)" 43)/' "$out/README.org.orig" >README.org
cmp -s README.org "$out/README.org.orig" && echo "PLANT CHANGED NOTHING"
run p-readme-one-char-off tests/test-docs.sps
restore

sed 's/^```scheme run$/```scheme/' "$out/quickstart.md.orig" >docs/quickstart.md
cmp -s docs/quickstart.md "$out/quickstart.md.orig" && echo "PLANT CHANGED NOTHING"
run p-twin-fence-plain-scheme tests/test-docs.sps
restore

awk '/^```scheme run$/{skip=1} !skip{print} skip && /^```$/{skip=0}' "$out/quickstart.md.orig" >docs/quickstart.md
cmp -s docs/quickstart.md "$out/quickstart.md.orig" && echo "PLANT CHANGED NOTHING"
run p-twin-deleted tests/test-docs.sps
restore

awk '/^#\+begin_src scheme$/{skip=1} !skip{print} skip && /^#\+end_src$/{skip=0}' "$out/README.org.orig" >README.org
cmp -s README.org "$out/README.org.orig" && echo "PLANT CHANGED NOTHING"
run p-readme-no-scheme-block tests/test-docs.sps
restore

awk '{print} /^\*\* A taste$/{t=1} t && /^#\+end_src$/{print ""; print "#+begin_src scheme"; print "(sqlite-version)"; print "#+end_src"; t=0}' "$out/README.org.orig" >README.org
cmp -s README.org "$out/README.org.orig" && echo "PLANT CHANGED NOTHING"
run p-readme-second-block-no-twin tests/test-docs.sps
restore

run restored tests/test-docs.sps
tail -3 "$out/restored.log"
