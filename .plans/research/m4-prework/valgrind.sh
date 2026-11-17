#!/bin/sh
# valgrind.sh LABEL LIBRARY: varargs.sps, mode all, under Valgrind with the
# memory gate's flags (the Makefile's test-memory line), on one libsqlite3.
#
# Run it in the Guix container, from the repository's root. Valgrind's log
# goes to OUT/valgrind-LABEL.txt (OUT defaults to .plans/research/m4-prework/out)
# and the probe's output to build/m4pre/valgrind/LABEL.out, which should be
# the same as varargs-LABEL.txt. It exits with Valgrind's status: 9 on an
# error or a definite leak.
set -u
[ "$#" -eq 2 ] || { echo "usage: valgrind.sh LABEL LIBRARY" >&2; exit 2; }
out=${OUT:-.plans/research/m4-prework/out}
mkdir -p "$out" build/m4pre/valgrind
valgrind --command-line-only=yes "--log-file=$out/valgrind-$1.txt" --error-exitcode=9 \
  --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite \
  "${CHEZ:-scheme}" --program .plans/research/m4-prework/varargs.sps "$2" \
  >"build/m4pre/valgrind/$1.out" 2>&1
