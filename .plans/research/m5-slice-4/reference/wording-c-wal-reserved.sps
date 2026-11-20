#!r6rs
;;; Wording c: open-database with ((busy-timeout . 1500) (journal-mode . wal))
;;; on a file in the default journal mode, beside a holder, a second
;;; connection of the same thread, that has:
;;;   none                 nothing open: the control, which opens
;;;   reading              a select held at its row
;;;   immediate            begin immediate, nothing written
;;;   immediate-written    begin immediate, then an insert
;;;   deferred-written     begin, then an insert (its write takes the lock)
;;;   exclusive            begin exclusive, nothing written
;;; Each case on a fresh file holding t; the opener a fresh connection that
;;; holds no read of its own. For each: what the open answered (the mode read
;;; back) or raised (code, extended code), and its milliseconds; then the
;;; holder rolled back and closed, and the file's mode read by a third
;;; connection. The build's busy-wait grain is read first: a 250 ms timeout
;;; on a begin immediate beside another's begin immediate answers busy after
;;; about 250 ms where SQLite sleeps in milliseconds, at once where it sleeps
;;; whole seconds. A wait is at least 1000 ms; at once is under 1000.
(import (rnrs) (rnrs eval) (only (chezscheme) real-time) (chez-sqlite3-testing)
        (chez-sqlite3 private counters))

(define env (environment '(chez-sqlite3)))
(define (reach name) (eval name env))
(define open-database (reach 'open-database))
(define close-database! (reach 'close-database!))
(define execute! (reach 'execute!))
(define query-row (reach 'query-row))
(define prepare-statement (reach 'prepare-statement))
(define finalize-statement! (reach 'finalize-statement!))
(define step! (reach 'step!))
(define in-transaction? (reach 'in-transaction?))
(define sqlite-busy? (reach 'sqlite-busy?))
(define sqlite-error? (reach 'sqlite-error?))
(define sqlite-error-code (reach 'sqlite-error-code))
(define sqlite-error-extended-code (reach 'sqlite-error-extended-code))
(define sqlite-error-sql (reach 'sqlite-error-sql))
(define sqlite-version (reach 'sqlite-version))

(define temp (make-process-temp-directory))
(define counter 0)
(define (fresh-file)
  (set! counter (+ counter 1))
  (let ((path (string-append temp "/w" (number->string counter) ".db")))
    (let ((db (open-database path)))
      (execute! db "create table t (x)")
      (execute! db "insert into t values (1), (2)")
      (close-database! db))
    path))

(define (timed thunk)
  (let* ((start (real-time))
         (r (guard (e ((sqlite-error? e)
                       (list 'raised (sqlite-error-code e) (sqlite-error-extended-code e) (sqlite-error-sql e)))
                      (#t (list 'raised (describe e))))
              (thunk)))
         (ms (- (real-time) start)))
    (list r ms)))

;; hold! : Database Symbol -> (U Statement #f)
(define (hold! db how)
  (case how
    ((none) #f)
    ((reading) (let ((st (prepare-statement db "select x from t"))) (step! st) st))
    ((immediate) (execute! db "begin immediate") #f)
    ((immediate-written) (execute! db "begin immediate") (execute! db "insert into t values (9)") #f)
    ((deferred-written) (execute! db "begin") (execute! db "insert into t values (9)") #f)
    ((exclusive) (execute! db "begin exclusive") #f)
    (else (error 'hold! "no such holder" how))))

(define grain
  (let* ((path (fresh-file))
         (holder (open-database path))
         (held (hold! holder 'immediate))
         (other (open-database path '((busy-timeout . 250))))
         (r (timed (lambda () (execute! other "begin immediate") 'began))))
    (close-database! other)
    (execute! holder "rollback")
    (close-database! holder)
    (list (if (>= (cadr r) 125) 'milliseconds 'whole-seconds) r)))

(define (case-of how)
  (let* ((path (fresh-file))
         (holder (open-database path))
         (held (hold! holder how))
         (r (timed (lambda ()
                     (let* ((db (open-database path '((busy-timeout . 1500) (journal-mode . wal))))
                            (mode (vector-ref (query-row db "pragma journal_mode") 0)))
                       (close-database! db)
                       (list 'opened mode))))))
    (when held (finalize-statement! held))
    (when (in-transaction? holder) (execute! holder "rollback"))
    (close-database! holder)
    (let* ((third (open-database path))
           (mode (vector-ref (query-row third "pragma journal_mode") 0)))
      (close-database! third)
      (list how (car r) (cadr r)
            (cond ((< (cadr r) 1000) 'at-once)
                  ((< (cadr r) (if (eq? (car grain) 'milliseconds) 3000 2000)) 'waited-once)
                  (else 'too-long))
            'file-mode-after mode))))

(display "library: ") (write (sqlite-version)) (newline)
(display "grain: ") (write grain) (newline)
(for-each (lambda (how) (write (case-of how)) (newline))
          '(none reading immediate immediate-written deferred-written exclusive))
(display "counts at the end: ") (write (native-counts)) (newline)
