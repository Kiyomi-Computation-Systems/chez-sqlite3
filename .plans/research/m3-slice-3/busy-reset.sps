;; M3 slice 3, part A's probe 2: what sqlite3_finalize answers after
;; sqlite3_reset failed with its own BUSY (an insert ... returning stepped
;; once under another's read), and whether the rows stand; and
;; sqlite3_clear_bindings' answer after it. Its database is build/'s, made
;; afresh and removed after; it runs from the repository's root:
;;   $CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-3/busy-reset.sps
(import (rnrs) (rnrs eval)
        (only (chezscheme) printf)
        (chez-sqlite3 private native)
        (chez-sqlite3 private connection)
        (chez-sqlite3 private statement))

(printf "version ~a\n" (eval '(sqlite-version) (environment '(chez-sqlite3))))
(define path "build/m3-slice-3-busy-reset.db")

;; remove! : -> Void
;; The probe's database deleted, if it is there.
(define (remove!) (guard (e ((i/o-error? e) #f)) (delete-file path)))

(remove!)

(define (exec! db sql) (let ((st (prepare-statement db sql))) (step! st) (finalize-statement! st)))

(define (count db)
  (call-with-statement db "select count(*) from t"
    (lambda (st) (step! st)
      (call-with-statement-handle 'p st 'column-value (lambda (c h s) (values #f (sqlite3-column-int64 h 0)))))))

(let ((db (open-database path)))
  (exec! db "create table t (x unique)")
  (exec! db "insert into t values (0)")
  (let* ((other (open-database path))
         (r (prepare-statement other "select x from t")))
    (step! r)
    (let* ((st (prepare-statement db "insert into t values (1), (2) returning x"))
           (a (step! st))
           (raw (call-with-statement-handle 'p st 'finalize-statement!
                  (lambda (c h s)
                    (let* ((reset (sqlite3-reset h))
                           (clear (sqlite3-clear-bindings h)))
                      (values 'ready (list 'reset reset 'clear clear))))))
           (fin (guard (e (#t (list 'finalize-raised (condition-who e)
                                    (eval `(sqlite-error-extended-code ',e) (environment '(chez-sqlite3))))))
                  (finalize-statement! st) 'finalize-ok)))
      (printf "after a stepped returning under a read: ~s then ~s\n" raw fin)
      (finalize-statement! r)
      (close-database! other)
      (printf "rows now: ~a\n" (count db))))
  (close-database! db))
(remove!)
