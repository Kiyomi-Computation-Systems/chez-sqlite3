#!r6rs
;;; Gap 1: whether an out-of-memory ends a transaction, read through the
;;; public verbs alone. On a fresh file holding t, b and src (ten rows of
;;; 3,000 bytes): execute! "begin", a marker row in t, then one call under
;;; the hard heap limit (SQLite's memory in use plus 1,000 bytes, lifted,
;;; hard then soft, however the call ends), as test-transaction-nomem sets
;;; it. Then what the call raised, in-transaction? straight after, the
;;; finish (finalize-statement!, or for a read reset! then finalize) and
;;; in-transaction? after it, and whether the marker is still there.
;;;
;;;   step  a step! of: a select reading a table; one reading none; a
;;;         multi-row insert ... select; a one-row insert
;;;   read  a column-value of 100,000 bound bytes, by a select reading a
;;;         table, and by one reading none
;;;
;;; Each call is guarded with its own sentinel; effects run through let*.
(import (rnrs) (rnrs eval) (only (chezscheme) foreign-procedure) (chez-sqlite3-testing)
        (chez-sqlite3 private counters))

(define env (environment '(chez-sqlite3)))
(define (reach name) (eval name env))
(define open-database (reach 'open-database))
(define close-database! (reach 'close-database!))
(define execute! (reach 'execute!))
(define query-row (reach 'query-row))
(define in-transaction? (reach 'in-transaction?))
(define prepare-statement (reach 'prepare-statement))
(define finalize-statement! (reach 'finalize-statement!))
(define step! (reach 'step!))
(define reset! (reach 'reset!))
(define bind! (reach 'bind!))
(define column-value (reach 'column-value))
(define sqlite-error? (reach 'sqlite-error?))
(define sqlite-error-code (reach 'sqlite-error-code))
(define sqlite-version (reach 'sqlite-version))
(define memory-used (eval 'sqlite3-memory-used (environment '(chez-sqlite3 private native))))

(define hard-limit (foreign-procedure "sqlite3_hard_heap_limit64" (integer-64) integer-64))
(define soft-limit (foreign-procedure "sqlite3_soft_heap_limit64" (integer-64) integer-64))

(define (attempt thunk)
  (guard (e ((sqlite-error? e) (list 'raised (sqlite-error-code e)))
            (#t (list 'raised (describe e))))
    (let ((v (thunk))) (if (eq? v (if #f #f)) 'no-value v))))

(define (limited thunk)
  (dynamic-wind
    (lambda () (hard-limit (+ (memory-used) 1000)))
    (lambda () (attempt thunk))
    (lambda () (hard-limit 0) (soft-limit 0))))

(define temp (make-process-temp-directory))
(define n 0)
(define (fresh-path)
  (set! n (+ n 1))
  (string-append temp "/case-" (number->string n) ".db"))

(define (state db) (if (in-transaction? db) 'in-transaction 'ended))

(define (one kind sql)
  (let ((db (open-database (fresh-path))))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (execute! db "create table t (x)")
           (execute! db "create table b (x)")
           (execute! db "create table src (x)")
           (execute! db "insert into src select replace(hex(zeroblob(1500)), '0', 'a') from (with recursive n(i) as (select 1 union all select i + 1 from n where i < 10) select i from n)")
           (execute! db "begin")
           (execute! db "insert into t values ('marker')")
           (let* ((st (prepare-statement db sql))
                  (ready (when (eq? kind 'read) (bind! st 1 (make-string 100000 #\a)) (step! st)))
                  (call (limited (lambda () (if (eq? kind 'read) (column-value st 0) (step! st)))))
                  (after-call (state db))
                  (finish (if (eq? kind 'read)
                              (let* ((r (attempt (lambda () (reset! st))))
                                     (f (attempt (lambda () (finalize-statement! st)))))
                                (list 'reset r 'finalize f))
                              (list 'finalize (attempt (lambda () (finalize-statement! st))))))
                  (after-finish (state db))
                  (marker (vector-ref (query-row db "select count(*) from t") 0)))
             (when (in-transaction? db) (execute! db "rollback"))
             (list (if (and (pair? call) (eq? (car call) 'raised)) call (list 'answered 'a-value))
                   'then after-call finish 'then after-finish 'marker-rows marker)))))
      (lambda () (close-database! db)))))

(display "library: ") (write (sqlite-version)) (newline)
(for-each
 (lambda (c)
   (let ((r (one (car c) (cadr c))))
     (display (car c)) (display " ") (write (cadr c)) (newline)
     (display "    => ") (write r) (newline)))
 '((step "select randomblob(100000) from src limit 1")
   (step "select randomblob(100000)")
   (step "insert into b select randomblob(100000) from src limit 3")
   (step "insert into b values (randomblob(100000))")
   (read "select ?1 from src limit 1")
   (read "select ?1")))
(display "limits after: ") (write (list (hard-limit -1) (soft-limit -1))) (newline)
(display "counts at the end: ") (write (native-counts)) (newline)
