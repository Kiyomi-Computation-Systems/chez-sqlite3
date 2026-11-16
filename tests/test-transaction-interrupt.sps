#!r6rs
;;; with-transaction beside an interrupted statement (ADR-0017's context:
;;; an interrupted write ends the transaction and its savepoints, and an
;;; interrupted SELECT doesn't; concurrency I5, trap 3), in
;;; (chez-sqlite3 private transaction).
;;;
;;; The body runs a long statement through execute!, while a watchdog thread
;;; calls native's sqlite3_interrupt on the connection's handle, read once
;;; through call-with-open-handle, every 5 ms until the convenience has
;;; returned, or until 120 s of wall-clock time have passed since the
;;; interrupted call began; a raise in the watchdog is its answer, and it
;;; keeps interrupting after it. So no row depends on how fast the step runs. The owner
;;; waits for the watchdog's end as long, 120 s of wall-clock time from
;;; its own return, and the row fails by name when it does not end. The body
;;; raises what execute! raised past with-transaction, at the outer level and
;;; nested.
;;;
;;; The interrupt comes from a second thread, since the row is about one
;;; landing in the middle of a write. Under the memory gate the latency is
;;; the scheduler's: Valgrind runs one thread at a time, and the watchdog's
;;; 5 ms wake-ups wait while the owner's sqlite3_step holds the CPU, so one
;;; call took 57 s, and whole runs 12 s to 99 s (M3 slice 4's review and its
;;; fix). A watchdog that first wakes after its deadline still sends its
;;; interrupt before it ends, so the deadline bounds the watchdog's life,
;;; never the interrupt's latency.
;;;
;;;   a long write   insert ... with recursive: the interrupt ends the
;;;                  transaction, autocommit 1 at once; with-transaction
;;;                  issues nothing, and the markers are gone
;;;   a long read    select ... from k, src: it keeps the transaction,
;;;                  autocommit 0; with-transaction rolls the level back
;;;
;;; Every wait is bounded. Every computation that can raise runs under a
;;; guard with a sentinel of its own. Effects run in order (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) fork-thread make-mutex make-condition with-mutex condition-wait
              condition-signal sleep make-time current-time add-duration time>=?)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) sqlite-error? sqlite-error-code sqlite-error-extended-code
              sqlite-closed? sqlite-transaction-ended?)
        (only (chez-sqlite3 private conditions) sqlite-interrupt?))

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

;; --- reached through eval -------------------------------------------------------------

(define public-load
  (guard (e (#t (list 'raised (describe e))))
    (eval '(sqlite-version) (environment '(chez-sqlite3)))
    'loaded))

(define (reach library name)
  (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
    (eval name (environment library))))

(define public '(chez-sqlite3))
(define with-transaction (reach public 'with-transaction))
(define open-database (reach public 'open-database))
(define close-database! (reach public 'close-database!))
(define execute! (reach public 'execute!))
(define query-row (reach public 'query-row))
(define in-transaction? (reach public 'in-transaction?))
(define statement-sql (reach public 'statement-sql))
(define statement-state (reach '(chez-sqlite3 private statement) 'statement-state))
(define tracked-statements (reach '(chez-sqlite3 private connection) 'tracked-statements))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define sqlite3-interrupt (reach '(chez-sqlite3 private native) 'sqlite3-interrupt))
(define sqlite3-get-autocommit (reach '(chez-sqlite3 private native) 'sqlite3-get-autocommit))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

(define (what-raised e)
  (cond ((sqlite-transaction-ended? e) (list 'transaction-ended (who-of e)))
        ((sqlite-error? e)
         (list (if (sqlite-interrupt? e) 'sqlite-interrupt 'sqlite-error)
               (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((condition? e) (list 'other (describe e)))
        (else (list 'value e))))

(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define (autocommit db) (call-with-open-handle 'test-transaction-interrupt db sqlite3-get-autocommit))

(define (prefix? p s) (and (<= (string-length p) (string-length s))
                           (string=? p (substring s 0 (string-length p)))))
(define (own-sql? s)
  (or (member s '("BEGIN DEFERRED" "BEGIN IMMEDIATE" "BEGIN EXCLUSIVE" "COMMIT" "ROLLBACK"))
      (prefix? "SAVEPOINT chez_sqlite3_" s) (prefix? "RELEASE chez_sqlite3_" s)
      (prefix? "ROLLBACK TO chez_sqlite3_" s)))
(define (issued db)
  (let loop ((rest (tracked-statements db)) (found '()))
    (if (null? rest)
        (reverse found)
        (let ((sql (statement-sql (car rest))))
          (loop (cdr rest)
                (if (own-sql? sql) (cons (cons sql (statement-state (car rest))) found) found))))))

(define (markers db)
  (attempt (lambda ()
             (vector-ref (query-row db "select coalesce(group_concat(x, ','), '(none)') from (select x from t order by x)")
                         0))))

(define (ms n) (make-time 'time-duration (* n 1000000) 0))

;; bound-seconds : Positive-Integer
;; The watchdog's bound, and the owner's wait for its end, in seconds of
;; wall-clock time.
(define bound-seconds 120)

;; deadline : -> Time
;; bound-seconds of wall-clock time from now, by the monotonic clock.
(define (deadline) (add-duration (current-time 'time-monotonic) (make-time 'time-duration 0 bound-seconds)))

;; past? : Time -> Boolean
(define (past? t) (time>=? (current-time 'time-monotonic) t))

;; interrupted : Database (-> Any) -> (List Any Symbol Any)
;; THUNK run on this thread, while a watchdog thread interrupts DB every
;; 5 ms until THUNK has returned or raised, or its deadline, bound-seconds
;; from this call's start, has passed, each wake sending its interrupt
;; before it reads the deadline: what THUNK raised, kept as the object
;; itself, or answered; whether any interrupt was sent; and whether the
;; watchdog ended within the bound-seconds this thread then waits for it:
;; 'the-watchdog-ended, 'the-watchdog-did-not-end, or, when the watchdog
;; raised, (the-watchdog-raised WHAT-IT-RAISED ... ENDED?), so the row
;; fails by name. A raise in the watchdog is its answer, not its end: it
;; keeps interrupting, 5 ms after each raise, until THUNK is done or the
;; deadline has passed, for a thread that dies on a raise leaves THUNK's
;; statement uninterrupted and the suite hung, naming no row (AGENTS.md).
(define (interrupted db thunk)
  (let* ((handle (call-with-open-handle 'test-transaction-interrupt db (lambda (h) h)))
         (m (make-mutex))
         (c (make-condition))
         (done #f)
         (ended #f)
         (sent 0)
         (raises '())
         (by (deadline))
         ;; watch : -> Void
         ;; Wakes every 5 ms, interrupts unless THUNK is done, and returns
         ;; once it is, or once the deadline has passed.
         (watch
          (lambda ()
            (let loop ()
              (unless (with-mutex m done)
                (sleep (ms 5))
                (with-mutex m
                  (unless done
                    (sqlite3-interrupt handle)
                    (set! sent (+ sent 1))))
                (unless (past? by) (loop))))))
         (note-raise!
          (lambda (e)
            (let ((what (guard (x (#t 'unreadable)) (what-raised e))))
              (with-mutex m (set! raises (cons what raises))))))
         (watchdog
          (fork-thread
           (lambda ()
             (let try ()
               (let ((outcome (guard (e (#t (note-raise! e) 'raised))
                                (watch)
                                'returned)))
                 (when (and (eq? outcome 'raised) (not (with-mutex m done)) (not (past? by)))
                   (sleep (ms 5))
                   (try))))
             (with-mutex m (set! ended #t) (condition-signal c)))))
         (r (guard (e (#t (list 'raised-object e))) (thunk) 'no-raise))
         (stopped (with-mutex m
                    (set! done #t)
                    (let ((wait-by (deadline)))
                      (let wait ()
                        (cond (ended 'the-watchdog-ended)
                              ((past? wait-by) 'the-watchdog-did-not-end)
                              (else (condition-wait c m (ms 100)) (wait)))))))
         (n (with-mutex m sent))
         (raised (with-mutex m (reverse raises))))
    (list r
          (if (> n 0) 'interrupts-sent 'no-interrupt-sent)
          (if (null? raised) stopped (list 'the-watchdog-raised raised stopped)))))

(define temp-dir (guard (e (#t #f)) (make-process-temp-directory)))
(define case-number 0)
(define (fresh-path)
  (set! case-number (+ case-number 1))
  (string-append (or temp-dir "/nonexistent") "/case-" (number->string case-number) ".db"))

(define (with-case proc)
  (let ((db #f) (db2 #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt (lambda ()
                   (let ((path (fresh-path)))
                     (set! db (open-database path))
                     (execute! db "create table t (x)")
                     (execute! db "create table b (x)")
                     (execute! db "create table src (x)")
                     (execute! db "insert into src values (1), (2), (3)")
                     (set! db2 (open-database path))
                     (proc db db2)))))
      (lambda ()
        (when db2 (guard (e (#t #f)) (close-database! db2)))
        (when db (guard (e (#t #f)) (close-database! db)))))))

(define long-write "insert into b with recursive k(i) as (select 1 union all select i + 1 from k where i < 2000000000) select i from k")
(define long-read "with recursive k(i) as (select 1 union all select i + 1 from k where i < 2000000000) select count(*) from k, src")

;; interrupted-row : String Boolean -> Any
;; SQL through execute!, interrupted, inside with-transaction, deferred,
;; after a marker; NESTED, inside an inner with-transaction after a second
;; marker, whose raise the outer body catches before it returns. The body
;; records what execute! raised, the watchdog's two answers and autocommit
;; straight after, and raises execute!'s condition. Then what
;; with-transaction raised, the inner's and the outer's when nested;
;; in-transaction?; the markers on DB and DB2; the statements it issued.
(define (interrupted-row sql nested)
  (with-case
   (lambda (db db2)
     (let* ((recorded #f) (inner 'not-nested)
            (body (lambda ()
                    (let* ((i (interrupted db (lambda () (execute! db sql))))
                           (raised (and (pair? (car i)) (cadr (car i))))
                           (a (autocommit db)))
                      (set! recorded (list (if raised (what-raised raised) (car i)) (cadr i) (caddr i) a))
                      (raise (or raised 'execute!-raised-nothing)))))
            (r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda ()
                              (execute! db "insert into t values ('outer')")
                              (if nested
                                  (begin
                                    (set! inner (attempt (lambda ()
                                                           (with-transaction db
                                                             (lambda ()
                                                               (execute! db "insert into t values ('inner')")
                                                               (body))))))
                                    'outer-returned)
                                  (body)))))))
            (in (if (in-transaction? db) 'yes 'no)))
       (list recorded inner r in (markers db) (markers db2) (issued db))))))

(define interrupt '(sqlite-interrupt execute! interrupt interrupt))
(define watched '(interrupts-sent the-watchdog-ended))

(test-begin "transaction-interrupt")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-assert "a temporary directory for the suite's databases"
  (string? temp-dir))

(test-equal "an interrupted write, outer: execute! raises &sqlite-interrupt, interrupt and interrupt, and the transaction has ended, autocommit 1 straight after; with-transaction issues nothing, the body's condition reaches the caller, and the marker is gone from both connections"
  (list (cons interrupt (append watched '(1))) 'not-nested (list 'raised interrupt) 'no "(none)" "(none)"
        '(("BEGIN DEFERRED" . ready)))
  (interrupted-row long-write #f))

(test-equal "an interrupted write, nested: the same raise and autocommit 1; the inner issues nothing and raises execute!'s condition; the outer, its body catching it and returning, raises &sqlite-transaction-ended, and both markers are gone"
  (list (cons interrupt (append watched '(1))) (list 'raised interrupt)
        '(raised (transaction-ended with-transaction)) 'no "(none)" "(none)"
        '(("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready)))
  (interrupted-row long-write #t))

(test-equal "an interrupted read, outer: the same raise, but autocommit 0: with-transaction rolls back, ROLLBACK kept, and the marker is gone"
  (list (cons interrupt (append watched '(0))) 'not-nested (list 'raised interrupt) 'no "(none)" "(none)"
        '(("BEGIN DEFERRED" . ready) ("ROLLBACK" . ready)))
  (interrupted-row long-read #f))

(test-equal "an interrupted read, nested: autocommit 0; the inner rolls back, ROLLBACK TO and RELEASE kept, and the outer commits its own marker, which db2 sees"
  (list (cons interrupt (append watched '(0))) (list 'raised interrupt) 'outer-returned 'no "outer" "outer"
        '(("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready) ("ROLLBACK TO chez_sqlite3_1" . ready)
          ("RELEASE chez_sqlite3_1" . ready) ("COMMIT" . ready)))
  (interrupted-row long-read #t))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "transaction-interrupt")

(exit (suite-exit-status runner))
