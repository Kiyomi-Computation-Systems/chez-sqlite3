#!r6rs
;;; The four statement calls that can block, held by behaviour: prepare,
;;; step, reset and finalize are __collect_safe (ADR-0011, amended), so
;;; another thread's collection runs while one waits in SQLite's busy handler.
;;;
;;; Each row makes the call block, on a thread of its own, with a busy
;;; timeout of 4000 ms and a second connection's lock: a prepare on a fresh
;;; connection, under another's begin exclusive; a plain insert's step, under
;;; another's read; and the reset and the finalize of an insert ... returning
;;; stepped once, under another's read. Measured on 3.53.1 and 3.45.1 alike
;;; (build/m2s3/probe-block.sps, at 1500 ms): each waited the timeout and
;;; answered 5. Bound plain, another thread's collect-rendezvous took the
;;; rest of the timeout, and ended after the call had returned; bound
;;; __collect_safe, it took 0 or 1 ms, while the call was still blocked.
;;;
;;; So each row, 1000 ms into the block, collects on this thread, and asserts
;;; that the collection ended within 1500 ms: by 2500 ms into a block of
;;; 4000, so while the call was still blocked. Then the call's own outcome,
;;; &sqlite-busy from the verb, and every count zero. A plain binding fails
;;; it: its collection waits out the rest of the timeout, ending after the
;;; call. The row also reads a flag the blocking thread sets as soon as its
;;; call answers, but that flag cannot tell: bound plain, the thread joined
;;; the collection before it could set it, and the flag read unset after
;;; every plain binding's collection (measured; .plans/m2-slice-3-mutation-log.md).
;;; The time is what tells.
;;;
;;; Every wait is bounded, and whatever the blocking thread raises is its
;;; answer (AGENTS.md). Effects run in order, through let*.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) fork-thread make-mutex with-mutex sleep make-time current-time
              time-second time-nanosecond collect-rendezvous)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3 private conditions) sqlite-busy?)
        (only (chez-sqlite3) sqlite-error? sqlite-error-code sqlite-error-extended-code
              sqlite-error-sql sqlite-error-offset sqlite-wrong-thread? sqlite-closed?))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (write (test-result-ref r 'expected-value))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r 'actual-value))
        (newline)))))

;; reach : (Listof Symbol) Symbol -> Procedure
(define (reach library name)
  (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
    (eval name (environment library))))

(define statement-library '(chez-sqlite3 private statement))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define step! (reach statement-library 'step!))
(define reset! (reach statement-library 'reset!))
(define statement-state (reach statement-library 'statement-state))

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

;; who-of : Condition -> Any
(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (sqlite-error-sql e) (sqlite-error-offset e) (if (sqlite-busy? e) 'busy 'no-subtype)))
        ((sqlite-wrong-thread? e) (list 'wrong-thread (who-of e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

;; ms : -> Integer
(define (ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* 1000 (time-second t)) (div (time-nanosecond t) 1000000))))

(define (pause ms) (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; wait-until : (-> Any) Natural -> (U 'satisfied 'iterations-exhausted)
;; DONE? asked every 10 ms, at most STEPS times.
(define (wait-until done? steps)
  (run-until (lambda () (pause 10)) done? steps))

(define busy-timeout 4000)
(define into-the-block 1000)
(define collection-bound 1500)

;; exec! : Database String -> Any
(define (exec! db sql)
  (let* ((st (prepare-statement db sql))
         (answer (guard (e (#t (finalize-statement! st) (raise e))) (step! st))))
    (finalize-statement! st)
    answer))

;; make-table! : String -> Void
(define (make-table! path)
  (let ((db (open-database path)))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (exec! db "create table t (x)")
        (exec! db "insert into t values (0)"))
      (lambda () (guard (e (#t #f)) (close-database! db))))))

;; collect-during : Mutex (-> Boolean) (-> Any) -> (List Symbol Symbol)
;; Once the blocking thread is about to make its call, by READY?, and
;; into-the-block ms after: this thread's collect-rendezvous, timed, and
;; whether the call had returned, by RETURNED?, when the collection did.
(define (collect-during ready? returned?)
  (let* ((ready (wait-until ready? 3000))
         (wait (pause into-the-block))
         (c0 (ms))
         (collected (collect-rendezvous))
         (c1 (ms))
         (returned (returned?)))
    (list (if (eq? ready 'satisfied) 'ready 'never-ready)
          (if (<= (- c1 c0) collection-bound) 'within-the-bound (list 'took (- c1 c0)))
          (if returned 'after-the-call-returned 'while-the-call-was-blocked))))

;; blocking-row : String (Database -> Void) (Database -> Any) (Database -> Any)
;;                -> List
;; A temporary directory's t.db, made by make-table!. LOCK! takes the lock on
;; this thread's connection; a thread of its own opens a connection, sets
;; the busy timeout, runs SETUP, then CALL, the verb that blocks, whatever it
;; raises being its answer. Answers what collect-during saw, the call's
;; answer, and the counts once everything is closed: a list of three.
(define (blocking-row lock! setup call)
  (let ((r (blocking-run lock! setup call)))
    (if (and (pair? r) (eq? (car r) 'raised))
        r
        (append r (list (native-counts))))))

;; blocking-run : like blocking-row, answering what collect-during saw and the
;; call's answer, once the lock is undone.
(define (blocking-run lock! setup call)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let* ((path (string-append dir "/t.db"))
              (made (make-table! path))
              (m (make-mutex))
              (ready #f)
              (answer #f)
              (returned #f)
              (locker (open-database path))
              (held #f)
              (configured #f))
         (dynamic-wind
           (lambda () #f)
           (lambda ()
             (fork-thread
              (lambda ()
                (let ((a (guard (e (#t (list 'thread-raised (what-raised e))))
                           (let ((db (open-database path)))
                             (dynamic-wind
                               (lambda () #f)
                               (lambda ()
                                 (exec! db (string-append "pragma busy_timeout = "
                                                          (number->string busy-timeout)))
                                 (with-mutex m (set! configured #t))
                                 (wait-until (lambda () (with-mutex m held)) 3000)
                                 (let* ((state (setup db))
                                        (r (with-mutex m (set! ready #t)))
                                        (outcome (attempt (lambda () (call state)))))
                                   (with-mutex m (set! returned #t))
                                   outcome))
                               (lambda () (guard (e (#t #f)) (close-database! db))))))))
                  (with-mutex m (set! answer (list 'answer a))))))
             (let* ((c (wait-until (lambda () (with-mutex m configured)) 3000))
                    (lock (lock! locker))
                    (h (with-mutex m (set! held #t)))
                    (seen (collect-during (lambda () (with-mutex m ready))
                                          (lambda () (with-mutex m returned))))
                    (got (wait-until (lambda () (with-mutex m answer)) 3000))
                    (a (with-mutex m answer)))
               (list seen (if a (cadr a) 'the-thread-hung))))
           (lambda ()
             (guard (e (#t #f)) (close-database! locker)))))))))

;; read-lock! : Database -> Void
;; A select of t stepped to its row: a read held until the close.
(define (read-lock! db)
  (step! (prepare-statement db "select x from t")))

(define seen-blocked '(ready within-the-bound while-the-call-was-blocked))

(test-begin "statement-block")

(test-equal "every count is zero at the start"
  zero-counts
  (native-counts))

(test-equal "step!: a plain insert under another connection's read waits in the busy handler, and another thread's collection ends within its bound while the step is still blocked; the step then raises &sqlite-busy from step!, with the SQL"
  (list seen-blocked
        (list 'raised (list 'sqlite-error 'step! 'busy 'busy "insert into t values (1)" #f 'busy))
        zero-counts)
  (blocking-row read-lock!
                (lambda (db) (prepare-statement db "insert into t values (1)"))
                (lambda (st) (guard (e (#t (finalize-statement! st) (raise e))) (step! st)))))

(test-equal "prepare-statement: a fresh connection's prepare under another's begin exclusive waits, and the collection ends while it is blocked; it then raises &sqlite-busy from prepare-statement, with the SQL and no offset"
  (list seen-blocked
        (list 'raised (list 'sqlite-error 'prepare-statement 'busy 'busy "select x from t" #f 'busy))
        zero-counts)
  (blocking-row (lambda (db) (exec! db "begin exclusive"))
                (lambda (db) db)
                (lambda (db) (let ((st (prepare-statement db "select x from t")))
                               (finalize-statement! st)
                               'prepared))))

(test-equal "reset!: an insert ... returning stepped once, reset under another's read, waits, and the collection ends while it is blocked; the reset then raises &sqlite-busy from reset!, and the statement is ready"
  (list seen-blocked
        (list (list 'raised (list 'sqlite-error 'reset! 'busy 'busy "insert into t values (1), (2) returning x" #f 'busy))
              'ready)
        zero-counts)
  (blocking-row read-lock!
                (lambda (db) (let ((st (prepare-statement db "insert into t values (1), (2) returning x")))
                               (step! st)
                               st))
                (lambda (st) (let* ((r (attempt (lambda () (reset! st))))
                                    (state (statement-state st)))
                               (finalize-statement! st)
                               (list r state)))))

(test-equal "finalize-statement!: the same insert, finalized under another's read, waits, and the collection ends while it is blocked; the finalize then raises &sqlite-busy from finalize-statement!, and the statement is finalized"
  (list seen-blocked
        (list (list 'raised (list 'sqlite-error 'finalize-statement! 'busy 'busy "insert into t values (1), (2) returning x" #f 'busy))
              'finalized)
        zero-counts)
  (blocking-row read-lock!
                (lambda (db) (let ((st (prepare-statement db "insert into t values (1), (2) returning x")))
                               (step! st)
                               st))
                (lambda (st) (let* ((r (attempt (lambda () (finalize-statement! st))))
                                    (state (statement-state st)))
                               (list r state)))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "statement-block")

(exit (suite-exit-status runner))
