#!/bin/sh
# Plants for test-manifest's clone check. Run from the worktree root, inside
# the container:  scripts/guix-env sh build/m5s4-checks/plants-clone.sh
# Code mutants run on a copy of the suite under build/; tree plants change
# README.org, docs/quickstart.md, Akku.manifest and CHANGELOG.md in place, or
# add docs/plant.md, and restore them from a backup taken first, on exit too.
# Each prints the suite's FAIL lines with their values, and its exit status.
# A last run on the restored tree must pass.
set -u
out=build/m5s4-checks/clone
mkdir -p "$out"
for f in README.org docs/quickstart.md Akku.manifest CHANGELOG.md; do
  cp "$f" "$out/$(basename "$f").orig"
done
restore() {
  for f in README.org docs/quickstart.md Akku.manifest CHANGELOG.md; do
    cp "$out/$(basename "$f").orig" "$f"
  done
  rm -f docs/plant.md
}
trap restore EXIT

make deps >/dev/null || exit 1

run() { # name program
  $CHEZ --libdirs src:tests:build/scheme-libs --program "$2" >"$out/$1.log" 2>&1
  rc=$?
  echo "=== $1: exit $rc"
  grep -A2 '^FAIL' "$out/$1.log" | cut -c1-700
}

mutant() { # name, with the sed script on stdin
  cat >"$out/$1.sed"
  sed -f "$out/$1.sed" tests/test-manifest.sps >"$out/$1.sps"
  if cmp -s tests/test-manifest.sps "$out/$1.sps"; then echo "=== $1: THE MUTANT CHANGED NOTHING"; return; fi
  run "$1" "$out/$1.sps"
}

changed() { # file
  cmp -s "$1" "$out/$(basename "$1").orig" && echo "PLANT CHANGED NOTHING in $1"
}

url=https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git
line="git clone $url"

# Code mutants.
mutant cm-never-fires <<'EOF'
s/^(define (clone-problems root version)$/(define (clone-problems root version) '())\n(define (clone-problems-unused root version)/
EOF
mutant cm-no-count <<'EOF'
s/^   (cond ((null? lines)$/   (cond (#f/
s/^         ((pair? (cdr lines))$/         (#f/
EOF
mutant cm-contains-not-equal <<'EOF'
s/^                   (if (string=? text want)$/                   (if (contains? (cdr line) want)/
EOF
mutant cm-every-page-a-home <<'EOF'
s/^                     (if (member rel clone-homes)$/                     (if #t/
EOF
mutant cm-version-ignored <<'EOF'
s/^  (let\* ((want (clone-line version))$/  (let* ((want (clone-line "0.0.0"))/
EOF
mutant cm-quickstart-may-be-missing <<'EOF'
s/^     (if (member "docs\/quickstart.md" rels)$/     (if #t/
EOF

# The plants of the M5 plan's 4.10, on the stand-ins, at 0.0.0.
sed "s|^$line\$|git clone --branch v0.2.0 $url|" "$out/README.org.orig" >README.org; changed README.org
run p-another-version tests/test-manifest.sps; restore

sed "s|^$line\$|git clone https://github.com/Kiyomi-Computation-Systems/chez-sqlite3|" "$out/README.org.orig" >README.org; changed README.org
run p-another-url tests/test-manifest.sps; restore

sed "s|^$line\$|git clone --branch v0.0.0 $url|" "$out/quickstart.md.orig" >docs/quickstart.md; changed docs/quickstart.md
run p-branch-at-0.0.0 tests/test-manifest.sps; restore

awk -v l="$line" '{print} $0 == l {print l}' "$out/quickstart.md.orig" >docs/quickstart.md; changed docs/quickstart.md
run p-second-line-in-the-quick-start tests/test-manifest.sps; restore

printf '# Plant\n\n```sh\n%s\n```\n' "$line" >docs/plant.md
run p-a-line-in-another-page tests/test-manifest.sps; restore

awk -v l="$line" '$0 != l' "$out/quickstart.md.orig" >docs/quickstart.md; changed docs/quickstart.md
run p-none-in-the-quick-start tests/test-manifest.sps; restore

# A release: the manifest and the changelog at 0.1.0.
release() {
  sed 's/^(akku-package ("chez-sqlite3" "0.0.0")$/(akku-package ("chez-sqlite3" "0.1.0")/' "$out/Akku.manifest.orig" >Akku.manifest
  changed Akku.manifest
  awk '{print} $0 == "## [Unreleased]" {print ""; print "## [0.1.0] - 2026-11-20"; print ""; print "### Added"; print ""; print "- The first release."}' "$out/CHANGELOG.md.orig" >CHANGELOG.md
  changed CHANGELOG.md
}
tagged() { # file
  sed "s|^$line\$|git clone --branch v0.1.0 $url|" "$out/$(basename "$1").orig" >"$1"; changed "$1"
}

release; tagged README.org; tagged docs/quickstart.md
run c-release-whole-passes tests/test-manifest.sps; restore

release
run p-none-at-0.1.0 tests/test-manifest.sps; restore

release; tagged README.org
sed "s|^$line\$|git clone --branch v0.2.0 $url|" "$out/quickstart.md.orig" >docs/quickstart.md; changed docs/quickstart.md
run p-another-version-at-0.1.0 tests/test-manifest.sps; restore

sed 's/^(akku-package ("chez-sqlite3" "0.0.0")$/(akku-package ("chez-sqlite3" "0.1.0")/' "$out/Akku.manifest.orig" >Akku.manifest; changed Akku.manifest
run p-manifest-bumped-alone tests/test-manifest.sps; restore

run restored tests/test-manifest.sps
tail -2 "$out/restored.log"
