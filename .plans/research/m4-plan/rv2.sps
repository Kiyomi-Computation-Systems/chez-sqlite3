;;; rv2.sps: M4's plan review's probe, rerun here (the M4 plan, section 8;
;;; run-review.sh runs it, with --libdirs src). It loads no libsqlite3:
;;; (chez-sqlite3 private conditions) imports none.
(import (rnrs) (chez-sqlite3 private conditions))
;; What raise-sqlite-error does with the extended code failure-details would
;; read from a fresh connection after a refused db_config set (D3: 0).
(define (try extended)
  (guard (c ((assertion-violation? c) (list 'assertion-violation (condition-who c) (condition-irritants c)))
            ((sqlite-error? c) (list 'sqlite-error (sqlite-error-code c) (sqlite-error-extended-code c))))
    (raise-sqlite-error 'open-database extended "SQL logic error" #f #f)
    'no-raise))
(for-each (lambda (e) (write (list e (try e))) (newline)) '(0 1 5 261))
