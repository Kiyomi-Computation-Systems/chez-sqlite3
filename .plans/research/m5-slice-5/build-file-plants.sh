#!/bin/sh
# build-file-plants.sh [NAME...]: from the worktree's root, inside scripts/guix-env, after
# extract-base.sh has unpacked the swept commit to build/base on the host. Each
# plant is a fresh copy of build/base, changed by its mutate_NAME, then sweep-check.sh run from
# the copy's root against build/base (or the plant's own base). One line a plant: its exit
# status, its problems joined by " | ", and the checker's last line. A plant whose change did
# not apply says so, and runs nothing.
set -u
root=$(pwd)
chk=$root/.plans/research/m5-slice-5
work=$root/build/m5s5/plants/t
mkdir -p "$work"

# changed F: fails unless F differs from the base's copy, so a plant that missed is seen.
changed() { ! cmp -s "$pbase/$1" "$1"; }
# edit F SED: sed -i on F, then changed F.
edit() { sed -i "$2" "$1" && changed "$1"; }

# --- the earlier plants (the slice's log) -------------------------------------------
mutate_control() { true; }
mutate_comments() {
  edit tests/test-docs.sps "2s/held for README.org and every docs/held for README.org and each docs/" &&
  edit tests/check-ci.sh "166s/read by both checks' awk/read by the two checks' awk/" &&
  edit tests/extension.c "1s|^/\* tests/extension.c: the loadable SQLite extension the load-extension!$|/* tests/extension.c: the loadable SQLite extension\n * the load-extension!|"
}
mutate_datum() { edit tests/site-unit.sps '231s/"index.html"/"Index.html"/'; }
mutate_shcode2() { edit tests/check-ci.sh '131s/^dir=\$1$/dir=${1:-.}/'; }
mutate_ctoken2() { edit tests/extension.c '85s/"chez_inits", 0,/"chez_inits", 1,/'; }
mutate_added() { printf '(import (rnrs))\n' > tests/new-file.sps; }
mutate_unread() { printf '(unclosed\n' >> tests/site-unit.sps && changed tests/site-unit.sps; }
mutate_cA() { edit tests/decoy-libsqlite3.c '97s|present only in a build with DECOY_MARKER|in a DECOY_MARKER build alone|'; }
mutate_cB() { edit tests/decoy-libsqlite3.c '100s/  return 1;/  return 2;/'; }
mutate_cC() {
  edit tests/decoy-libsqlite3.c '97s|present only in a build with DECOY_MARKER|in a DECOY_MARKER build alone|' &&
  edit tests/decoy-libsqlite3.c '2s|suites only,|suites alone,|' &&
  edit tests/decoy-libsqlite3.c '36s|^ \*$| *  (none)|'
}
mutate_heredoc() { edit tests/check-memory-gate.sh '497i #;(exit 1)'; }
mutate_contin() { edit tests/check-ci.sh '998a\
'; }
mutate_shebang() { edit tests/guix-env-launcher.sh '1s|^#!/bin/sh$|#!/bin/false|'; }
mutate_mode() { chmod 664 tests/guix-env-launcher.sh; }
mutate_cslash() { edit tests/extension.c '92i \  // registered answers \\'; }
mutate_cspace() { edit tests/extension.c '105s/"chez_failing refused"/"chez_failing  refused"/'; }
mutate_rnrs() { edit tests/check-suites.sps '1s/^#!r6rs$/#!chezscheme/'; }
mutate_hashsemi() { edit tests/check-suites.sps '2i #;(exit 1)'; }
mutate_squote() { edit tests/check-dev.sh '101a #;(newline)'; }
mutate_awkcode() { edit tests/check-ci.sh '170s/^  n = 0$/#  n = 0/'; }
mutate_allowlist() { edit tests/check-ci.sh '168s/how many spaces s starts with/the number of spaces s starts with/'; }

# --- the build files' plants ----------------------------------------------------------
mutate_bcomments() {
  edit Makefile '1s/^# chez-sqlite3$/# chez-sqlite3: its Makefile/' &&
  edit scripts/guix-env '2s/The pinned Guix development container/The pinned Guix container for development/' &&
  edit scripts/ci/floor.sh '6s/two directories above this script/two directories up from this script/' &&
  edit packaging/debian-prereqs.txt '1s/to build and test/to build and to test/' &&
  edit packaging/floors.sexp '1s/^;; The oldest Chez/;; The earliest Chez/' &&
  edit .gitignore '1s/^# Scratch written/# Scratch made/' &&
  edit .gitattributes '1s/^# The design records/# The records/'
}
mutate_mkcode() { edit Makefile '37s/^TEST_TIMEOUT ?= 300$/TEST_TIMEOUT ?= 301/'; }
mutate_mkrecipe() { edit Makefile '254a \	# a comment the shell reads'; }
mutate_mkspace() { edit Makefile '2s/^#$/ # an indented line/'; }
mutate_mkcontin() { edit Makefile '78a # inside the list'; }
mutate_mkendslash() { edit Makefile '9s/spawns this one\.$/spawns this one. \\/'; }
mutate_mkdefine() { edit Makefile '/^define PLANT_BODY$/a # a comment in the block'; }
base_mkdefine() { printf 'define PLANT_BODY\nline one\nendef\n' >> Makefile; }
mutate_mkopen() { edit Makefile '1s/^# chez-sqlite3$/# chez-sqlite3: its Makefile/'; }
base_mkopen() { printf 'define PLANT_OPEN\nline one\n' >> Makefile; }
mutate_shnoext() { edit scripts/guix-env '15s/^set -eu$/set -u/'; }
mutate_shkind() { edit scripts/require-tools '1s|^#!/bin/sh$|#!/usr/bin/env python3|'; }
mutate_shciheredoc() { edit scripts/ci/check-sqlite.sh '331a # note'; }
mutate_txtcode() { edit packaging/debian-prereqs.txt '29a git'; }
mutate_txtindent() { edit packaging/debian-site-prereqs.txt '1s/^#/ #/'; }
mutate_gicode() { edit .gitignore 's|^/build/$|/build|'; }
mutate_gaout() { edit .gitattributes 's|^/AGENTS.md  export-ignore$|#/AGENTS.md  export-ignore|'; }
mutate_sexpdatum() { edit packaging/floors.sexp 's/(sqlite "3.45.1")/(sqlite "3.45.2")/'; }
mutate_sexphash() { edit packaging/floors.sexp '2a #;(chez "9.5.8")'; }
mutate_modeci() { chmod 664 scripts/ci/floor.sh; }
mutate_modemk() { chmod 775 Makefile; }
mutate_addedci() { printf '#!/bin/sh\n' > scripts/ci/new.sh; }
mutate_removedpkg() { rm packaging/debian-site-prereqs.txt; }

# plant NAME [CHECKER]: one plant's run, with CHECKER's sweep-check.sh, the real one by default.
plant() {
  name=$1
  checker=${2:-$chk}
  d=$work/$name
  rm -rf "$d" "$d.base"
  pbase=$root/build/base
  if command -v "base_$name" > /dev/null 2>&1; then
    cp -a "$root/build/base" "$d.base"
    (cd "$d.base" && "base_$name")
    pbase=$d.base
  fi
  cp -a "$pbase" "$d"
  if ! (cd "$d" && "mutate_$name"); then echo "$name: the plant did not apply"; return; fi
  (cd "$d" && sh "$checker/sweep-check.sh" "$pbase") > "$work/$name.out" 2>&1
  status=$?
  problems=$(grep -v '^sweep-check: FAILED\|^sweep-check: ok' "$work/$name.out" |
               sed 's/^sweep-check: //' | awk 'NR > 1 { printf " | " } { printf "%s", $0 }')
  echo "$name: exit $status :: ${problems:-none} :: $(tail -n 1 "$work/$name.out")" | cut -c1-600
}

if [ $# -eq 0 ]; then
  set -- control comments datum shcode2 ctoken2 added unread cA cB cC heredoc contin shebang \
    mode cslash cspace rnrs hashsemi squote awkcode allowlist \
    bcomments mkcode mkrecipe mkspace mkcontin mkendslash mkdefine mkopen shnoext shkind \
    shciheredoc \
    txtcode txtindent gicode gaout sexpdatum sexphash modeci modemk addedci removedpkg
fi
for p in "$@"; do plant "$p"; done
# allowlist, again, with the heredoc allowlist emptied in a copy of the checker.
case " $* " in
  *" allowlist "*)
    rm -rf "$work/chk-empty"
    cp -a "$chk" "$work/chk-empty"
    sed -i "s|^awk_heredocs='tests/check-ci.sh:AWKPROGRAM'$|awk_heredocs=''|" "$work/chk-empty/sweep-check.sh"
    if cmp -s "$chk/sweep-check.sh" "$work/chk-empty/sweep-check.sh"; then
      echo "allowlist-empty: the checker's copy did not change"
    else
      plant allowlist "$work/chk-empty" | sed 's/^allowlist:/allowlist-empty:/'
    fi ;;
esac
