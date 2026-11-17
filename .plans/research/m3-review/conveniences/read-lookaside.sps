#!r6rs
;; Probe: can a column read be seen from outside the call? In a UTF-16
;; database, sqlite3_column_text converts a TEXT value to UTF-8 into the
;; result's own memory. If that takes a lookaside slot, the connection's
;; SQLITE_DBSTATUS_LOOKASIDE_USED rises once a column read, and a timer's
;; handler run at every tick of query can count the columns read so far,
;; as sqlite3_expanded_sql counts the parameters bound.
(import (rnrs) (rnrs eval)
        (only (chezscheme) foreign-procedure foreign-alloc foreign-free foreign-ref foreign-set!
              set-timer timer-interrupt-handler printf))
(define env (environment '(chez-sqlite3) '(chez-sqlite3 private connection)))
(define open-database (eval 'open-database env))
(define close-database! (eval 'close-database! env))
(define execute! (eval 'execute! env))
(define query (eval 'query env))
(define call-with-open-handle (eval 'call-with-open-handle env))
(define db-status (foreign-procedure "sqlite3_db_status" (uptr int uptr uptr int) int))
(define (used db)
  (call-with-open-handle 'probe db
    (lambda (h)
      (let ((cur (foreign-alloc 8)) (hi (foreign-alloc 8)))
        (foreign-set! 'int cur 0 0) (foreign-set! 'int hi 0 0)
        (db-status h 0 cur hi 0)
        (let ((n (foreign-ref 'int cur 0))) (foreign-free cur) (foreign-free hi) n)))))
(define (columns n)
  (let loop ((i n) (acc '()))
    (if (= i 0) acc (loop (- i 1) (cons (string-append "'v" (number->string i) "'") acc)))))
(define (joined parts) (fold-left (lambda (a p) (if (string=? a "") p (string-append a ", " p))) "" parts))
(for-each
 (lambda (encoding)
   (let ((db (open-database ":memory:")))
     (execute! db (string-append "pragma encoding = '" encoding "'"))
     (execute! db "create table t (x)")
     (let* ((sql (string-append "select " (joined (columns 50)) " from t union all select " (joined (columns 50))))
            (seen '()) (old (timer-interrupt-handler))
            (rows (dynamic-wind
                    (lambda () (timer-interrupt-handler
                                (lambda () (let ((u (used db))) (unless (memv u seen) (set! seen (cons u seen)))) (set-timer 1))))
                    (lambda () (set-timer 1) (let ((r (query db sql))) (set-timer 0) r))
                    (lambda () (set-timer 0) (timer-interrupt-handler old)))))
       (printf "~a: rows ~a, lookaside levels seen ~a: ~s\n" encoding (length rows) (length seen) (list-sort < seen)))
     (close-database! db)))
 '("UTF-8" "UTF-16le"))
