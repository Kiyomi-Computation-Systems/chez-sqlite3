#!/bin/sh
# plants.sh [NAME...] : from the worktree's root, on the host. Copies the tree into
# build/m5s4-checks2/plants/NAME for each plant (all of them with no NAME), replays the
# review's edit there, each edit's match counted (exactly one), then runs test-docs and
# check-site in each copy inside the container, and prints each copy's failing rows.
set -e
ROOT=$(pwd)
S=build/m5s4-checks2
P=$S/plants
# The review's plants, then extra page plants (x) for rows they do not reach, then
# mutants (m) of the suite's own readers, each watched failing its own row.
ALL="control p01 p28 p02 p08 p25 p03 p24 p32 p19b p04 p06 p07 p17 p29
     x01 x02 x03 x04 x05 x06 x07 x08
     m01 m02 m03 m04 m05 m06 m07 m08 m09 m10 m11 m12 m13 m14 m15 m16 m17 m18 m19 m20"
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
    p07) replace docs/quickstart.md '
(#("bird" 2) #("cat" 4))
' '
(#("bird" 2) #("cat" 5))
' ;;
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
    m01) replace tests/test-docs.sps '(and (pair? nonblank) (starts? (trim (car nonblank)) "(import"))' '(and (pair? nonblank) (starts? (car nonblank) "(import"))' ;;
    m02) replace tests/test-docs.sps '  (and (not org?)
       (string=? (block-language b) "scheme")' '  (and (string=? (block-language b) "scheme")' ;;
    m03) replace tests/test-docs.sps '         (string=? (block-language (cadr rest)) "text")
' '' ;;
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
    *) echo "plants.sh: no plant $n" >&2; exit 2 ;;
  esac
  cd "$ROOT"
done

scripts/guix-env sh -c '
for n in '"$NAMES"'; do
  cd '"$ROOT/$P"'/$n
  make deps >/dev/null
  $CHEZ --libdirs src:tests:build/scheme-libs --program tests/test-docs.sps > test-docs.out 2>&1; a=$?
  make -s check-site > check-site.out 2>&1; b=$?
  echo "=== $n: test-docs exit $a, check-site exit $b"
  grep "^FAIL" test-docs.out | sed "s/^/  docs: /"
  grep "^check-site:" check-site.out | grep -v "all green" | sed "s/^/  site: /"
done'
