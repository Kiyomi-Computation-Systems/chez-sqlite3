#!r6rs
;;; Wordings a and b: what an engine's caller gets when an exit's failure is
;;; raised as the engine runs out.
;;;
;;;   close  call-with-database on a fresh file; its procedure makes a
;;;          statement the connection does not track (raw sqlite3_prepare_v2,
;;;          as an extension would leave one), so the close fails, then spins
;;;          until the engine runs out inside it
;;;   rollback  inside an outer with-transaction, deferred, an inner
;;;          with-transaction whose body writes, holds a two-row insert ...
;;;          returning at its row, then spins until the engine runs out: the
;;;          inner level's rollback, ROLLBACK TO then RELEASE, fails at RELEASE
;;;
;;; Each in two layouts, one engine of FUEL ticks, a fuel large enough that
;;; the first slice reaches the spin:
;;;   inner  a guard inside the engine's thunk, around the call, notes what
;;;          reaches it; a guard around the engine's call notes what the
;;;          caller gets
;;;   outer  only the guard around the engine's call
;;; Then: the condition the caller got, by its simple conditions' kinds, its
;;; who, message and irritants; whether the engine answered through its
;;; complete or expire procedure; the connection's state; and whether a later
;;; stretch of work, outside any engine, met another raise (the engine's timer
;;; left running).
(import (rnrs) (rnrs eval)
        (only (chezscheme) make-engine foreign-procedure set-timer record-type-name record-rtd)
        (chez-sqlite3-testing) (chez-sqlite3 private counters))

(define (reach library name) (eval name (environment library)))
(define public '(chez-sqlite3))
(define call-with-database (reach public 'call-with-database))
(define open-database (reach public 'open-database))
(define close-database! (reach public 'close-database!))
(define with-transaction (reach public 'with-transaction))
(define execute! (reach public 'execute!))
(define query-row (reach public 'query-row))
(define prepare-statement (reach public 'prepare-statement))
(define finalize-statement! (reach public 'finalize-statement!))
(define step! (reach public 'step!))
(define in-transaction? (reach public 'in-transaction?))
(define sqlite-error? (reach public 'sqlite-error?))
(define sqlite-error-code (reach public 'sqlite-error-code))
(define sqlite-closed? (reach public 'sqlite-closed?))
(define sqlite-version (reach public 'sqlite-version))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-out-pointer (reach '(chez-sqlite3 private native) 'call-with-out-pointer))
(define database-depth (reach '(chez-sqlite3 private connection) 'database-depth))

(define prepare-v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int))
(define raw-finalize (foreign-procedure "sqlite3_finalize" (uptr) int))

(define (raw-prepare! db sql)
  (call-with-open-handle 'probe db
    (lambda (h)
      (call-with-c-string 'probe sql
        (lambda (text)
          (let-values (((rc statement)
                        (call-with-out-pointer 'probe (lambda (slot) (prepare-v2 h text -1 slot 0)))))
            (if (and (eqv? rc 0) (not (eqv? statement 0)))
                statement
                (error 'raw-prepare! "no statement" rc))))))))

;; kinds : Condition -> (Listof Symbol)
(define (kinds e)
  (let loop ((rest (simple-conditions e)) (out '()))
    (if (null? rest)
        (reverse out)
        (loop (cdr rest) (cons (record-type-name (record-rtd (car rest))) out)))))

;; shown : Any -> Any
(define (shown e)
  (cond ((sqlite-closed? e) (list 'sqlite-closed (if (who-condition? e) (condition-who e) 'no-who)))
        ((sqlite-error? e) (list 'sqlite-error (sqlite-error-code e)
                                 (if (who-condition? e) (condition-who e) 'no-who)))
        ((condition? e)
         (list 'condition (kinds e)
               'assertion-violation? (assertion-violation? e)
               'error? (error? e)
               'who (if (who-condition? e) (condition-who e) 'no-who)
               'message (if (message-condition? e) (condition-message e) 'no-message)
               'irritants (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'value e))))

(define (spin) (let loop ((i 0)) (when (< i 50000000) (loop (+ i 1)))) 'spun)

;; later : -> Any
;; A stretch of work outside any engine, long enough for a timer left
;; running to fire: what it raised, or done.
(define (later)
  (guard (e (#t (list 'raised-later (shown e))))
    (let loop ((i 0) (acc 0))
      (if (< i 20000000) (loop (+ i 1) (+ acc 1)) 'nothing-raised-later))))

;; run-engine : (-> Any) Positive-Integer -> Any
;; The engine's one slice, the caller's guard around it.
(define (run-engine thunk fuel)
  (guard (e (#t (list 'caller-got (shown e))))
    ((make-engine thunk) fuel
     (lambda (left . vals) (list 'completed vals))
     (lambda (more) 'expired))))

(define temp (make-process-temp-directory))
(define counter 0)
(define (fresh-path)
  (set! counter (+ counter 1))
  (string-append temp "/p" (number->string counter) ".db"))

;; --- close -------------------------------------------------------------------------------------

(define (close-case layout fuel)
  (let* ((path (fresh-path)) (db #f) (raw #f) (inner-saw 'nothing)
         (call (lambda ()
                 (call-with-database path
                   (lambda (d)
                     (set! db d)
                     (set! raw (raw-prepare! d "select 1"))
                     (spin)))))
         (thunk (if (eq? layout 'inner)
                    (lambda () (guard (e (#t (set! inner-saw (shown e)) 'inner-guard-returned)) (call)))
                    call))
         (got (run-engine thunk fuel))
         (after (later))
         (open? (and db (guard (e ((sqlite-closed? e) 'closed) (#t (list 'raised (shown e))))
                          (in-transaction? db)
                          'open)))
         (counted (native-counts)))
    (when raw (raw-finalize raw))
    (when db (guard (e (#t #f)) (close-database! db)))
    (list 'layout layout 'caller got 'inner-guard inner-saw 'later after
          'connection open? 'counts-then counted 'counts-after-cleanup (native-counts))))

;; --- rollback ----------------------------------------------------------------------------------

(define (rollback-case layout fuel)
  (let* ((db (open-database (fresh-path))) (held #f) (inner-saw 'nothing) (got #f) (after #f) (state #f))
    (execute! db "create table t (x)")
    (execute! db "create table r (x)")
    (let ((outer
           (guard (e (#t (list 'outer-raised (shown e))))
             (with-transaction db 'deferred
               (lambda ()
                 (execute! db "insert into t values ('outer')")
                 (let* ((call (lambda ()
                                (with-transaction db
                                  (lambda ()
                                    (execute! db "insert into t values ('inner')")
                                    (set! held (prepare-statement db "insert into r values (6), (7) returning x"))
                                    (step! held)
                                    (spin)))))
                        (thunk (if (eq? layout 'inner)
                                   (lambda () (guard (e (#t (set! inner-saw (shown e)) 'inner-guard-returned)) (call)))
                                   call)))
                   (set! got (run-engine thunk fuel))
                   (set! after (later))
                   (set! state (list 'in-transaction (in-transaction? db) 'depth (database-depth db)))
                   (when held (finalize-statement! held))
                   'outer-returned))))))
      (let ((rows (query-row db "select group_concat(x, ',') from (select x from t order by x)"))
            (in (in-transaction? db)))
        (close-database! db)
        (list 'layout layout 'caller got 'inner-guard inner-saw 'later after
              'inside-outer-after state 'outer outer 'then-in-transaction in 't rows
              'counts (native-counts))))))

;; --- fold --------------------------------------------------------------------------------------
;; query-fold of a two-row insert ... returning, outside a transaction, while
;; a second connection holds a select at its row; the procedure spins at the
;; first row. The expiry finalizes the statement, whose commit is busy under
;; the read.

(define query-fold (reach public 'query-fold))

(define (fold-case layout fuel)
  (let* ((path (fresh-path))
         (db (open-database path))
         (db2 (open-database path))
         (inner-saw 'nothing))
    (execute! db "create table r (x)")
    (execute! db "insert into r values (0)")
    (let* ((reader (prepare-statement db2 "select x from r"))
           (read (step! reader))
           (call (lambda ()
                   (query-fold db "insert into r values (6), (7) returning x"
                               (lambda (acc row) (spin) (+ acc 1)) 0)))
           (thunk (if (eq? layout 'inner)
                      (lambda () (guard (e (#t (set! inner-saw (shown e)) 'inner-guard-returned)) (call)))
                      call))
           (got (run-engine thunk fuel))
           (after (later)))
      (finalize-statement! reader)
      (let ((rows (query-row db "select count(*) from r")))
        (close-database! db2)
        (close-database! db)
        (list 'layout layout 'caller got 'inner-guard inner-saw 'later after
              'rows-in-r rows 'counts (native-counts))))))

(display "library: ") (write (sqlite-version)) (newline)
(for-each
 (lambda (layout)
   (display "fold     ") (write (fold-case layout 100000)) (newline))
 '(inner outer))
(for-each
 (lambda (layout)
   (display "close    ") (write (close-case layout 100000)) (newline))
 '(inner outer))
(for-each
 (lambda (layout)
   (display "rollback ") (write (rollback-case layout 100000)) (newline))
 '(inner outer))
