;;; Trap repro: SQLITE_LIMIT_LENGTH holds a statement's column names at
;;; prepare, so lowering it to test a refused bind can refuse the prepare
;;; first. A column's name is its alias, or the expression's own text.
;;;   - at 30, an alias of 30 bytes prepares and one of 31 answers TOOBIG, and
;;;     so does "select '<29 a's>'", whose name is the literal's 31 bytes;
;;;   - set to 1, "select ?1" (its name "?1", 2 bytes) answers TOOBIG at the
;;;     floor, which keeps 1, and prepares on 3.53.1, which keeps 30.
;;;
;;;   scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-slice-4/trap-limit-names.sps'
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define libversion (foreign-procedure "sqlite3_libversion" () string))
(define sourceid (foreign-procedure "sqlite3_sourceid" () string))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare-v3 (foreign-procedure "sqlite3_prepare_v3" (uptr string int unsigned-int uptr uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define errmsg (foreign-procedure "sqlite3_errmsg" (uptr) string))
(define limit (foreign-procedure "sqlite3_limit" (uptr int int) int))

;; Every SQL and message here is ASCII, so Chez's string type reads it whole.
(define (open)
  (let* ([cell (foreign-alloc 8)]
         [rc (open-v2 ":memory:" cell (logior #x2 #x4 #x80 #x02000000) 0)]
         [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    db))
(define (try lim sql)
  (let* ([db (open)]
         [was (limit db 0 lim)]
         [is (limit db 0 -1)]
         [cell (foreign-alloc 8)]
         [zero (foreign-set! 'uptr cell 0 0)]
         [rc (prepare-v3 db sql -1 0 cell 0)]
         [msg (errmsg db)]
         [st (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (unless (= st 0) (finalize st))
    (close db)
    (printf "limit set ~a, reads ~a: ~s (~a bytes) prepare ~a, ~s~n" lim is sql (string-length sql) rc msg)))

(printf "libversion: ~a~nsourceid: ~a~n" (libversion) (sourceid))
(try 30 (string-append "select 1 as " (make-string 30 #\n)))
(try 30 (string-append "select 1 as " (make-string 31 #\n)))
(try 30 (string-append "select '" (make-string 29 #\a) "'"))
(try 1 "select ?1")
(try 1 "select ?")
