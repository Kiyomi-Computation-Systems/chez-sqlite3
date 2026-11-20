#!/bin/sh
# plants.sh [NAME...] : from the worktree's root, on the host. Copies the tree into
# build/m5s4-checks3/plants/NAME for each plant (all of them with no NAME), replays the
# plant's edit there, each edit's match counted (exactly one), then runs test-docs and
# check-site in each copy inside the container, and prints each copy's failing rows.
# With BEFORE=1 each copy runs the suite as it was at ef357a2 instead
# (build/m5s4-checks3/test-docs.orig.sps), to show what a plant slipped past.
set -e
ROOT=$(pwd)
S=build/m5s4-checks3
P=$S/plants
# The docs review's plants (p, x) and mutants (m01-m20, m01 and m03 rewritten for the
# new whole-program? and text-after), then this round's page plants (n) and mutants
# (m21-).
OLD="control p01 p28 p02 p08 p25 p03 p24 p32 p19b p04 p06 p07 p17 p29
     x01 x02 x03 x04 x05 x06 x07 x08
     m01 m02 m03 m03b m04 m05 m06 m07 m08 m09 m10 m11 m12 m13 m14 m15 m16 m17 m18 m19 m20"
NEW="n01 n02 n03 n04 n05 n06 n07 n08 n09 n10 n11 n12
     m21 m22 m23 m24 m25 m26 m27 m28"
ALL="$OLD $NEW"
NAMES=${*:-$ALL}
NAMES=$(echo $NAMES)

replace() { # FILE OLD NEW : exactly one match, else stop
  python3 -I - "$1" "$2" "$3" <<'EOF'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
n = text.count(old)
if n != 1:
    sys.exit("plant: %r occurs %d times in %s, not once" % (old, n, path))
open(path, "w", encoding="utf-8").write(text.replace(old, new))
EOF
}

# The quick start's first program, its first line, and its stated output.
FIRST='```scheme
(import (rnrs) (chez-sqlite3))'
OUT='
(#("bird" 2) #("cat" 4))
'
WRONG='
(#("bird" 2) #("cat" 5))
'

for n in $NAMES; do
  d=$P/$n
  rm -rf "$d"; mkdir -p "$d/build"
  rsync -a --exclude=/build --exclude=/.git ./ "$d/"
  rsync -a build/akku "$d/build/"
  cd "$d"
  case $n in
    control) ;;
    p01) replace docs/finding-sqlite.md '| `below-floor` | The library is older' '| `too-old` | The library is older' ;;
    p28) replace docs/finding-sqlite.md '| `missing-api` | The library lacks a function chez-sqlite3 needs. |
' '' ;;
    p02) replace docs/finding-sqlite.md '| `macos-system` |' '| `mac-system` |' ;;
    p08) replace docs/finding-sqlite.md '`/usr/lib64`, then `/usr/lib` |' '`/usr/lib`, then `/usr/lib64` |' ;;
    p25) replace docs/finding-sqlite.md '`$GUIX_ENVIRONMENT`, `$GUIX_PROFILE`,' '`$GUIX_PROFILE`, `$GUIX_ENVIRONMENT`,' ;;
    p03) replace docs/quickstart.md 'export CHEZ_SQLITE3_LIBRARY=/opt/homebrew' 'export CHEZ_SQLITE_LIBRARY=/opt/homebrew' ;;
    p24) replace README.org '=CHEZ_SQLITE3_LIBRARY= names' '=CHEZ_SQLITE_LIBRARY= names' ;;
    p32) replace docs/finding-sqlite.md 'export CHEZ_SQLITE3_LIBRARY=/opt/sqlite' 'export CHEZ_SQLITE3_LIBRARY=opt/sqlite' ;;
    p19b) replace docs/libraries.md '# What varies by library
' '# What differs by library
' ;;
    p04) replace docs/quickstart.md '(sqlite-library-unavailable-path e))))' '(sqlite-library-unavailable-file e))))' ;;
    p06) replace docs/quickstart.md '     (execute! db "insert into pets values (?, ?)" "cat" 4)' '     (execute! db "insert into pets values (?, ?)" "cat" 3)' ;;
    p07) replace docs/quickstart.md "$OUT" "$WRONG" ;;
    p17) replace docs/quickstart.md "   (eval '(list (sqlite-version) (sqlite-library-path) (sqlite-library-source))
         (environment '(rnrs) '(chez-sqlite3)))))" '   (list (sqlite-version) (sqlite-library-path) (sqlite-library-source))))' ;;
    p29) replace docs/quickstart.md '(import (rnrs) (rnrs eval) (chez-sqlite3))' '(import (rnrs) (chez-sqlite3))' ;;
    x01) replace docs/finding-sqlite.md '| A Mac | Apple'"'"'s `/usr/lib/libsqlite3.dylib` | `macos-system` |
' '' ;;
    x02) replace docs/finding-sqlite.md 'and `override` for' 'and `overriden` for' ;;
    x03) replace docs/finding-sqlite.md '| Reason | Why |' '| Reasons | Why |' ;;
    x04) replace docs/finding-sqlite.md 'on arm64)' 'on aarch64)' ;;
    x05) replace docs/quickstart.md '(query db "select name, legs from pets order by legs"))))
(newline)' '(query db "select name, legs from pets order by legs"))))
(display "note" (current-error-port))
(newline)' ;;
    x06) replace docs/finding-sqlite.md '| Any other system | nothing | |' '| Any other system | `/usr/lib/libsqlite3.so` | `system` |' ;;
    x07) replace README.org '- [[file:docs/libraries.md][What varies by library]]' '- [[file:docs/libraries.md][What changes by library]]'
         replace site/pages.sls '("libraries.md" . "What varies by library")' '("libraries.md" . "What changes by library")' ;;
    x08) mv docs/finding-sqlite.md docs/finding-sqlite-moved.md ;;
    # m01 and m03 hold the rewritten readers: whole-program? reads only the block's
    # first line; text-after walks past a Scheme block; m03b takes any block as text.
    m01) replace tests/test-docs.sps '(first-datum (joined (block-lines b)))' "(first-datum (car (append (block-lines b) '(\"\"))))" ;;
    m02) replace tests/test-docs.sps '  (and (not org?)
       (string=? (block-language b) "scheme")' '  (and (string=? (block-language b) "scheme")' ;;
    m03) replace tests/test-docs.sps '                 ((string=? (block-language (car rest)) "scheme") #f)
' '' ;;
    m03b) replace tests/test-docs.sps '((string=? (block-language (car rest)) "text") (block-lines (car rest)))' '(#t (block-lines (car rest)))' ;;
    m04) replace tests/test-docs.sps "(equal? (car clause)
                                         (list 'sqlite-library-unavailable? (car (cadr x))))))" "(pair? (car clause)) (eq? (car (car clause)) 'sqlite-library-unavailable?)))" ;;
    m05) replace tests/test-docs.sps '(string=? text (string-append (shown (car d)) "\n")))' '#t)' ;;
    m06) replace tests/test-docs.sps '                         ((and (char=? (car cs) #\\) (pair? (cdr cs)) (char=? (cadr cs) #\|))
                          (loop (cddr cs) (cons #\| piece) out))
' '' ;;
    m07) replace tests/test-docs.sps '(and (> (string-length c) 0)
                         (for-all' '(and #t
                         (for-all' ;;
    m08) replace tests/test-docs.sps '(if (and (pair? (cdr lines)) (delimiter-row? (pipe-cells (cadr lines))))' '(if (pair? (cdr lines))' ;;
    m09) replace tests/test-docs.sps '(if (and (= (length ranges) 1) (= (caar ranges) 0) (= (cdar ranges) (string-length cell)))' '(if (= (length ranges) 1)' ;;
    m10) replace tests/test-docs.sps '(mine (find (lambda (a) (string=? (alternative-word cell a) machine)) alternatives))' '(mine (find (lambda (a) #t) alternatives))' ;;
    m11) replace tests/test-docs.sps '((starts? (substring cell (cadr (car at)) (string-length cell)) " in ")' '(#t' ;;
    m12) replace tests/test-docs.sps '(let ((flat (list->string (map (lambda (c) (if (char=? c #\newline) #\space c)) (string->list text)))))' '(let ((flat text))' ;;
    m13) replace tests/test-docs.sps '((member (car rest) out) (loop (cdr rest) out))' '(#f #f)' ;;
    m14) replace tests/test-docs.sps '(if (string=? name "HOME") "~" (string-append "$" name))' '(string-append "$" name)' ;;
    m15) replace tests/test-docs.sps '(loop j (if (search w "CHEZ_" 0) (cons w out) out))' '(loop j (if (starts? w "CHEZ_") (cons w out) out))' ;;
    m16) replace tests/test-docs.sps '(if (and (< k (string-length line)) (not (blank? (string-ref line k)))) (e (+ k 1)) k)' '(if (< k (string-length line)) (e (+ k 1)) k)' ;;
    m17) replace tests/test-docs.sps '(and (<= indent 3) (< indent (string-length line)) (char=? (string-ref line indent) #\|))' '(and (< indent (string-length line)) (char=? (string-ref line indent) #\|))' ;;
    m18) replace tests/test-docs.sps '(define (page-lines p) (numbered (text-lines (text-or-empty p))))' "(define (page-lines p) '())" ;;
    m19) replace tests/test-docs.sps '(filter (lambda (b) (whole-program? b (org-page? p))) bs)' "'()" ;;
    m20) replace tests/test-docs.sps 'out) out))))
            (else (loop (+ i 1) out))))))' 'out) out))))
            (else (loop (+ i 2) out))))))' ;;
    # The fixes' page plants.
    # n01: a comment line before the first program's import, and its stated output wrong.
    n01) replace docs/quickstart.md "$FIRST" '```scheme
;; app.sps
(import (rnrs) (chez-sqlite3))'
         replace docs/quickstart.md "$OUT" "$WRONG" ;;
    # n02: #!r6rs before the first program's import, and its stated output wrong.
    n02) replace docs/quickstart.md "$FIRST" '```scheme
#!r6rs
(import (rnrs) (chez-sqlite3))'
         replace docs/quickstart.md "$OUT" "$WRONG" ;;
    # n03: an sh block between the first program and its text block, and its stated output wrong.
    n03) replace docs/quickstart.md 'Run it with the command above. It prints:' 'Run it:

```sh
scheme --libdirs chez-sqlite3/src --program app.sps
```

It prints:'
         replace docs/quickstart.md "$OUT" "$WRONG" ;;
    # n04: the first program imports a library the reader's --libdirs src lacks.
    n04) replace docs/quickstart.md "$FIRST" '```scheme
(import (rnrs) (chez-sqlite3) (srfi :64))' ;;
    # n05: the guard program's loaded list names the source id where the page says the source.
    n05) replace docs/quickstart.md '(sqlite-library-source)' '(sqlite-source-id)' ;;
    # n06: the override shown as a command's prefix, a bare name.
    n06) replace docs/finding-sqlite.md 'export CHEZ_SQLITE3_LIBRARY=/opt/sqlite/lib/libsqlite3.so.0' 'CHEZ_SQLITE3_LIBRARY=libsqlite3.so.0 scheme --program app.sps' ;;
    # n07: the discovery table's first two labels swapped.
    n07) replace docs/finding-sqlite.md '| Linux, when Chez runs on Guix'"'"'s C library, as Guix'"'"'s Chez does |' '| Other Linux |'
         replace docs/finding-sqlite.md '| Other Linux | `libsqlite3.so.0`' '| Linux, when Chez runs on Guix'"'"'s C library, as Guix'"'"'s Chez does | `libsqlite3.so.0`' ;;
    # n08: a second level-1 heading in libraries.md.
    n08) replace docs/libraries.md '## Extension loading
' '# Another

## Extension loading
' ;;
    # n09: a blank line before libraries.md's heading, so its one level-1 heading is not its first line.
    n09) replace docs/libraries.md '# What varies by library
' '
# What varies by library
' ;;
    # n10: the first program's output block made an sh block, so no text block holds a whole program's output.
    n10) replace docs/quickstart.md '```text
(#("bird" 2) #("cat" 4))' '```sh
(#("bird" 2) #("cat" 4))' ;;
    # n11: the override set through env, a relative path, in an indented block.
    n11) replace docs/quickstart.md '  export CHEZ_SQLITE3_LIBRARY=/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib' '  env CHEZ_SQLITE3_LIBRARY=opt/homebrew/opt/sqlite/lib/libsqlite3.dylib scheme --program app.sps' ;;
    # n12: the Mac row's label says macOS, which holds no Mac.
    n12) replace docs/finding-sqlite.md '| A Mac | Apple' '| macOS | Apple' ;;
    # This round's mutants of the suite's own readers and rows.
    # m21: every CHEZ_SQLITE3_LIBRARY= sets it, after = or a backtick too.
    m21) replace tests/test-docs.sps '(if (or (= j 0) (blank? (string-ref line (- j 1))))' '(if #t' ;;
    # m22: one at the line's very start sets nothing.
    m22) replace tests/test-docs.sps '(if (or (= j 0) (blank? (string-ref line (- j 1))))' '(if (and (> j 0) (blank? (string-ref line (- j 1))))' ;;
    # m23: a label that must hold a word must begin with it.
    m23) replace tests/test-docs.sps '(and (search cell (cadr rule) 0) #t)' '(starts? cell (cadr rule))' ;;
    # m24: a heading of any level counts as level 1.
    m24) replace tests/test-docs.sps '(and h (= (car h) 1))' 'h' ;;
    # m25: a fragment whose first datum is any list is a whole program.
    m25) replace tests/test-docs.sps "(eq? (caar d) 'import)" '#t' ;;
    # m26: the suite reads the source id, not the library's source.
    m26) replace tests/test-docs.sps "(sqlite-library-path) (sqlite-library-source)) run-env)" "(sqlite-library-path) (sqlite-source-id)) run-env)" ;;
    # m27: the label rule for Guix's row asks it to begin with Guix.
    m27) replace tests/test-docs.sps '(tarm64le . "arm64")) (holds "Guix"))' '(tarm64le . "arm64")) (begins "Guix"))' ;;
    # m28: the loaded line is written without its newline.
    m28) replace tests/test-docs.sps '(sqlite-library-source)) run-env))
                   "\n")' '(sqlite-library-source)) run-env))
                   "")' ;;
    *) echo "plants.sh: no plant $n" >&2; exit 2 ;;
  esac
  if [ "${BEFORE:-}" = 1 ]; then cp "$ROOT/$S/test-docs.orig.sps" tests/test-docs.sps; fi
  cd "$ROOT"
done

scripts/guix-env sh -c '
for n in '"$NAMES"'; do
  cd '"$ROOT/$P"'/$n
  make deps >/dev/null
  $CHEZ --libdirs src:tests:build/scheme-libs --program tests/test-docs.sps > test-docs.out 2>&1; a=$?
  make -s check-site > check-site.out 2>&1; b=$?
  echo "=== $n: test-docs exit $a, check-site exit $b, $(grep "expected passes" test-docs.out | tr -s " ")"
  grep "^FAIL" test-docs.out | sed "s/^/  docs: /"
  grep "^check-site:" check-site.out | grep -v "all green" | sed "s/^/  site: /"
done'
