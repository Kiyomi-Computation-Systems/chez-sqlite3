#!/bin/sh
# For each export of (chez-sqlite3): does a program that names it, with no
# loadable library, start? Prints "starts" or "dies at startup".
cd "$(dirname "$0")"
printf '(import (chezscheme) (chez-sqlite3))\n(for-each (lambda (n) (display n) (newline)) (library-exports (quote (chez-sqlite3))))\n' > names.sps
CHEZ_SQLITE3_LIBRARY=/nonexistent/libsqlite3.so.0 $CHEZ --libdirs ../../../src --program names.sps > names.txt 2>&1
while read -r n; do
  printf '#!r6rs\n(import (rnrs) (chez-sqlite3))\n(display "started\\n")\n(define (never x) (%s x))\n' "$n" > one.sps
  if CHEZ_SQLITE3_LIBRARY=/nonexistent/libsqlite3.so.0 $CHEZ --libdirs ../../../src --program one.sps 2>/dev/null | grep -q started; then echo "starts $n"; else echo "dies $n"; fi
done < names.txt
