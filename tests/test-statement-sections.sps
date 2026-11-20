#!r6rs
;;; ADR-0014's "change together", held by behaviour. A verb's C call, its tracking and its state's
;;; change share one critical section; a verb that made one of them after the section left
;;; a window where an engine's expiry let another engine, on the same thread,
;;; see the statement half made. Three sweeps, each a first engine A that
;;; expires once, at every fuel from 1 to 60, and a second thread of control B
;;; that runs at A's first expiry, on the same thread; then A finishes:
;;;
;;;   prepare against close   A prepares, B closes the connection. A's
;;;                           statement is tracked in the prepare's section,
;;;                           so the close finalizes it: no fuel ends in a
;;;                           refused close or an open connection
;;;   step against step       A steps an insert, B steps it too. The state is
;;;                           set in the accessor's section, so B finds it
;;;                           done and is refused, or runs first and A is
;;;                           refused: the table holds one row, at every fuel
;;;   finalize against        A finalizes, B reads what the connection tracks
;;;   tracked-statements      and the statement's state. Untracked in the
;;;                           finalize's section, so a finalized statement is
;;;                           never listed, and a listed one is never finalized
;;;
;;; The fuel range: the windows the mutants open fall at fuels 25 to 39 of A's
;;; first slice, on both libraries: the tracking made after the section at 27
;;; to 30, the state's change at 25 and 26, the untracking at 34 to 39. 60 passes the last of them
;;; with room, and is the range the other engine sweeps use.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. Effects run in order, through let* and named lets.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) make-engine)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) sqlite-closed? sqlite-error? sqlite-error-code))

(define runner (test-runner-simple))
(test-runner-current runner)

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
(define tracked-statements (reach '(chez-sqlite3 private connection) 'tracked-statements))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define statement? (reach statement-library 'statement?))
(define step! (reach statement-library 'step!))
(define statement-state (reach statement-library 'statement-state))
(define call-with-statement-handle (reach statement-library 'call-with-statement-handle))
(define sqlite3-column-int64 (reach '(chez-sqlite3 private native) 'sqlite3-column-int64))

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

;; what-raised : Any -> Any
;; A raised object as this suite compares it, never by a message's words.
(define (what-raised e)
  (cond ((sqlite-closed? e) (list 'closed (if (who-condition? e) (condition-who e) 'no-who)))
        ((sqlite-error? e) (list 'sqlite-error (sqlite-error-code e)))
        ((assertion-violation? e)
         (list 'assertion-violation (if (who-condition? e) (condition-who e) 'no-who)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

;; attempt : (-> Any) -> Any
;; THUNK's answer, or (raised WHAT).
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

;; fuels : Positive-Integer -> (Listof Positive-Integer)
(define (fuels n)
  (let loop ((i n) (found '()))
    (if (= i 0) found (loop (- i 1) (cons i found)))))

;; finish! : (U Engine #f) -> Void
;; E run to its end, bounded.
(define (finish! e)
  (let loop ((e e) (n 0))
    (when (and e (< n 100000))
      (loop (e 1000000 (lambda (left . v) #f) (lambda (next) next)) (+ n 1)))))

;; interleave : (-> Any) (-> Any) Positive-Integer -> (List Any Any)
;; A's thunk run in an engine of FUEL ticks; at its first expiry B's thunk
;; runs, on this thread, once; then A finishes. A's answer, or 'a-not-finished,
;; and B's, or 'a-finished-first when A completed before it expired.
(define (interleave a-thunk b-thunk fuel)
  (let* ((a-answer 'a-not-finished)
         (a (make-engine (lambda () (set! a-answer (attempt a-thunk)) 'a)))
         (a2 (a fuel (lambda (left . v) #f) (lambda (next) next)))
         (b (if a2 (attempt b-thunk) 'a-finished-first)))
    (finish! a2)
    (list a-answer b)))

;; exec! : Database String -> Any
(define (exec! db sql)
  (let ((st (prepare-statement db sql)))
    (step! st)
    (finalize-statement! st)))

;; count-rows : Database -> Integer
(define (count-rows db)
  (let ((st (prepare-statement db "select count(*) from t")))
    (step! st)
    (let ((n (call-with-statement-handle 'test-statement-sections st 'column-value
               (lambda (connection handle sql) (values #f (sqlite3-column-int64 handle 0))))))
      (finalize-statement! st)
      n)))

;; undo! : (Listof Any) (Listof Any) -> Void
(define (undo! statements databases)
  (for-each (lambda (s) (guard (e (#t #f)) (finalize-statement! s))) statements)
  (for-each (lambda (db) (guard (e (#t #f)) (close-database! db))) databases))

;; sweep : (Positive-Integer -> Any) -> (Listof (List Positive-Integer Any))
;; PROC at each fuel from 1 to 60, under a guard.
(define (sweep proc)
  (map (lambda (fuel) (list fuel (attempt (lambda () (proc fuel))))) (fuels 60)))

;; all-ok : -> (Listof (List Positive-Integer Symbol))
(define (all-ok) (map (lambda (fuel) (list fuel 'ok)) (fuels 60)))

(test-begin "statement-sections")

;; --- prepare against close ----------------------------------------------------------------

;; prepare-vs-close : Positive-Integer -> Any
;; ok when B's close answered, or A finished first; A's answer is a statement
;; the close finalized, or &sqlite-closed from the prepare; a second close
;; then does nothing, so the connection was closed; every count is zero.
(define (prepare-vs-close fuel)
  (let* ((db (open-database ":memory:"))
         (st #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let* ((r (interleave (lambda () (let ((s (prepare-statement db "select 1")))
                                           (set! st s)
                                           'prepared))
                              (lambda () (close-database! db) 'closed)
                              fuel))
               (a (car r))
               (b (cadr r))
               (state (and st (statement-state st)))
               (again (attempt (lambda () (close-database! db) 'closed-again)))
               (counts (native-counts)))
          (cond ((not (and (memq b '(closed a-finished-first)) (eq? again 'closed-again)))
                 (list 'wrong 'close b again))
                ((and (eq? b 'closed) (not (or (equal? a '(raised (closed prepare-statement)))
                                               (and (eq? a 'prepared) (eq? state 'finalized)))))
                 (list 'wrong 'a-or-state a state))
                ((not (equal? counts zero-counts)) (list 'wrong 'counts counts))
                (else 'ok))))
      (lambda () (undo! (if st (list st) '()) (list db))))))

(test-equal "prepare against close, at every fuel from 1 to 60: the close answers or A finished first, A's statement is finalized by the close or A's prepare raised &sqlite-closed, the connection is closed, and every count is zero"
  (all-ok)
  (sweep prepare-vs-close))

;; --- step against step ---------------------------------------------------------------------

;; step-vs-step : Positive-Integer -> Any
;; ok when the insert ran once: one row, the statement done, and the answers
;; one #f and one refusal naming done (or A finished first and B none).
(define (step-vs-step fuel)
  (let* ((db (open-database ":memory:")))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (exec! db "create table t (x)")
        (let* ((st (prepare-statement db "insert into t values (1)"))
               (r (interleave (lambda () (step! st)) (lambda () (step! st)) fuel))
               (state (statement-state st))
               (refusal '(raised (assertion-violation step!
                                  (not-allowed-in-state done))))
               (rows (begin (finalize-statement! st) (count-rows db)))
               (a (car r))
               (b (cadr r)))
          (cond ((not (eqv? rows 1)) (list 'wrong 'rows rows a b))
                ((not (eq? state 'done)) (list 'wrong 'state state))
                ((not (or (and (eq? a #f) (eq? b 'a-finished-first))
                          (and (eq? a #f) (equal? b refusal))
                          (and (equal? a refusal) (eq? b #f))))
                 (list 'wrong 'answers a b))
                (else 'ok))))
      (lambda () (undo! '() (list db))))))

(test-equal "step against step on one insert, at every fuel from 1 to 60: it runs once, the table holds one row, the statement is done, and the other step is refused naming done"
  (all-ok)
  (sweep step-vs-step))

;; --- finalize against tracked-statements ---------------------------------------------------

;; finalize-vs-tracked : Positive-Integer -> Any
;; ok when B's reading is consistent: ST is listed exactly when it is not
;; finalized; and after A, ST is neither listed nor live, and every count but
;; the connection's is zero.
(define (finalize-vs-tracked fuel)
  (let* ((db (open-database ":memory:")))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let* ((st (prepare-statement db "select 1"))
               (r (interleave (lambda () (finalize-statement! st) 'finalized)
                              (lambda () (list (and (memq st (tracked-statements db)) #t)
                                               (statement-state st)))
                              fuel))
               (a (car r))
               (b (cadr r))
               (after (list (length (tracked-statements db)) (statement-state st)))
               (counts (native-counts)))
          (cond ((not (equal? a (if (eq? b 'a-finished-first) a 'finalized)))
                 (list 'wrong 'a a))
                ((not (or (eq? b 'a-finished-first)
                          (equal? b '(#t ready))
                          (equal? b '(#f finalized))))
                 (list 'wrong 'b b))
                ((not (equal? after '(0 finalized))) (list 'wrong 'after after))
                ((not (equal? counts (list '(block . 0) '(connection . 1) '(statement . 0))))
                 (list 'wrong 'counts counts))
                (else 'ok))))
      (lambda () (undo! '() (list db))))))

(test-equal "finalize against tracked-statements, at every fuel from 1 to 60: a finalized statement is never listed and a listed one never finalized; afterwards it is neither listed nor live, and no statement is counted"
  (all-ok)
  (sweep finalize-vs-tracked))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "statement-sections")

(exit (suite-exit-status runner))
