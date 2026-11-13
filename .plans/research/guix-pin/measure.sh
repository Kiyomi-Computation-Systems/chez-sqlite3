set -e
echo "scheme: $(scheme --version 2>&1)"
echo "gcc: $(gcc --version | head -1)"
echo "valgrind: $(valgrind --version)"
echo "sqlite3 cli: $(sqlite3 --version | cut -d' ' -f1)"
ls -l "$GUIX_ENVIRONMENT/lib/libsqlite3.so.0" | sed 's/.*-> /lib -> /'
ls "$GUIX_ENVIRONMENT/include/sqlite3.h"
cat > probe.ss <<'P'
(load-shared-object (string-append (getenv "GUIX_ENVIRONMENT") "/lib/libsqlite3.so.0"))
(let* ([v ((foreign-procedure "sqlite3_libversion" () string))]
       [n ((foreign-procedure "sqlite3_libversion_number" () int))]
       [ts ((foreign-procedure "sqlite3_threadsafe" () int))])
  (printf "libversion ~a number ~a threadsafe ~a threaded? ~a machine ~a~n" v n ts (threaded?) (machine-type)))
(let ([get (foreign-procedure "sqlite3_compileoption_get" (int) string)])
  (let loop ([i 0] [acc '()])
    (let ([s (get i)])
      (if s (loop (+ i 1) (cons s acc))
          (printf "compile options: ~{~a ~}~n" (reverse acc))))))
(printf "load_extension entry: ~a~n" (foreign-entry? "sqlite3_load_extension"))
P
scheme -q --script probe.ss
