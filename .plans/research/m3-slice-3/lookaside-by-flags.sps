;; M3 slice 3, part B's probe: lookaside by a prepare's flags, through the
;; suites' own sqlite3_db_status, LOOKASIDE_USED's current and high-water
;; values, the high-water mark reset first: a select of 200 columns run by
;; execute-script!, once and twice; prepared-at with no flags and
;; SQLITE_PREPARE_PERSISTENT, never stepped; and query's miss, prepared
;; PERSISTENT at the default capacity and with no flags at capacity 0.
;; Run from the repository's root:
;;   $CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-3/lookaside-by-flags.sps
(import (rnrs) (only (chezscheme) foreign-procedure foreign-alloc foreign-free foreign-ref foreign-set!)
        (chez-sqlite3) (chez-sqlite3 private conveniences)
        (only (chez-sqlite3 private connection) call-with-open-handle open-database-with-cache-capacity)
        (only (chez-sqlite3 private statement) checked-sql prepared-at finalize-statement!)
        (only (chez-sqlite3 private native) call-with-c-string))
(sqlite-version)
(define db-status (foreign-procedure "sqlite3_db_status" (uptr int uptr uptr int) int))
(define (hiwater db reset)
  (call-with-open-handle 'p db
    (lambda (h)
      (let ((cur (foreign-alloc 8)) (hi (foreign-alloc 8)))
        (foreign-set! 'int cur 0 0) (foreign-set! 'int hi 0 0)
        (db-status h 0 cur hi reset)
        (let ((r (list (foreign-ref 'int cur 0) (foreign-ref 'int hi 0)))) (foreign-free cur) (foreign-free hi) r)))))
(define (joined n) (let loop ((i n) (parts '())) (if (= i 0) (fold-left (lambda (a p) (if (string=? a "") p (string-append a ", " p))) "" parts) (loop (- i 1) (cons (number->string i) parts)))))
(define sql (string-append "select " (joined 200)))
(define (measure label thunk)
  (let ((db (open-database ":memory:")))
    (hiwater db 1)
    (thunk db)
    (write (list label (hiwater db 0))) (newline)
    (close-database! db)))
(measure 'script (lambda (db) (execute-script! db sql)))
(measure 'script-twice (lambda (db) (execute-script! db (string-append sql "; " sql))))
(define (prepared-with flags)
  (lambda (db)
    (let-values (((copy bytes) (checked-sql 'p sql)))
      (call-with-c-string 'p copy
        (lambda (block)
          (let ((o (prepared-at 'p db copy bytes block 0 flags #f #f)))
            (finalize-statement! (cadr o))))))))
(measure 'prepared-at-0 (prepared-with 0))
(measure 'prepared-at-persistent (prepared-with 1))
(measure 'query-persistent (lambda (db) (query db sql)))

(let ((db (open-database-with-cache-capacity 0 ":memory:")))
  (hiwater db 1) (query db sql) (write (list 'query-at-capacity-0 (hiwater db 0))) (newline) (close-database! db))
