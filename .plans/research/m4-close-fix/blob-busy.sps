#!r6rs
;;; blob-busy.sps: what an open sqlite3_blob looks like to sqlite3_next_stmt:
;;; a plain table's row opened as a blob with the suite's own binding of
;;; sqlite3_blob_open, then each statement's SQL, NULL as #f, and
;;; sqlite3_stmt_busy. Run from the repository's root, in the container:
;;;   $CHEZ --libdirs src:build/scheme-libs --program .plans/research/m4-close-fix/blob-busy.sps
(import (chezscheme)
        (chez-sqlite3)
        (only (chez-sqlite3 private connection) call-with-open-handle)
        (only (chez-sqlite3 private native) call-with-c-string call-with-out-pointer c-string->string))
(define blob-open (foreign-procedure "sqlite3_blob_open" (uptr uptr uptr uptr integer-64 int uptr) int))
(define blob-close (foreign-procedure "sqlite3_blob_close" (uptr) int))
(define next-stmt (foreign-procedure "sqlite3_next_stmt" (uptr uptr) uptr))
(define stmt-sql (foreign-procedure "sqlite3_sql" (uptr) uptr))
(define stmt-busy (foreign-procedure "sqlite3_stmt_busy" (uptr) int))
(define (walk h)
  (let loop ((s (next-stmt h 0)) (acc '()))
    (if (eqv? s 0) (reverse acc)
        (loop (next-stmt h s) (cons (list (c-string->string (stmt-sql s)) (stmt-busy s)) acc)))))
(define db (open-database ":memory:"))
(execute! db "create table t(b)")
(execute! db "insert into t values (x'00112233')")
(define blob
  (call-with-open-handle 'probe db
    (lambda (h)
      (call-with-c-string 'probe "main"
        (lambda (main)
          (call-with-c-string 'probe "t"
            (lambda (t)
              (call-with-c-string 'probe "b"
                (lambda (b)
                  (let-values (((rc p) (call-with-out-pointer 'probe (lambda (slot) (blob-open h main t b 1 1 slot)))))
                    p))))))))))
(write (list 'blob-open (call-with-open-handle 'probe db walk))) (newline)
(blob-close blob)
(write (list 'blob-closed (call-with-open-handle 'probe db walk))) (newline)
(close-database! db)
