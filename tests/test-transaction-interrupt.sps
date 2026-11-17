#!r6rs
;;; with-transaction beside an interrupted statement (ADR-0017's context:
;;; an interrupted write ends the transaction and its savepoints, and an
;;; interrupted SELECT doesn't; concurrency I5, trap 3), in
;;; (chez-sqlite3 private transaction).
;;;
;;; The body runs a long statement through execute!, while a watchdog thread
;;; calls native's sqlite3_interrupt on the connection's handle, read once
;;; through call-with-open-handle, until the convenience has returned, or
;;; until 120 s of wall-clock time have passed since the interrupted call
;;; began. The owner waits for the watchdog's end as long, from its own
;;; return, and the row fails by name when it does not end. The body raises
;;; what execute! raised past with-transaction, at the outer level and
;;; nested.
;;;
;;;   a long write   insert ... with recursive: the interrupt ends the
;;;                  transaction, autocommit 1 at once; with-transaction
;;;                  issues nothing, and the markers are gone
;;;   a long read    select ... from k, src: it keeps the transaction,
;;;                  autocommit 0; with-transaction rolls the level back
;;;
;;; The watchdog is tests/test-interrupt-reach.sps's device, copied and
;;; adapted: a program keeps its own code. Valgrind runs one thread at a
;;; time, and a thread running C keeps it: slice 4's watchdog, a plain thread
;;; waking every 5 ms, sent its first interrupt 16.5 s into a step, and the
;;; suite took 31 to 318 s on CI and 429 to 434 s under the gate here
;;; (.plans/traps.md; ADR-0005's slice 6 amendment). A thread blocked on a
;;; mutex lets the others run. So the watchdog takes SQLite's own memory
;;; mutex, SQLITE_MUTEX_STATIC_MEM, which sqlite3_malloc and sqlite3_free
;;; take while memory statistics are on, as they are on both libraries. The
;;; statement allocates as it runs, calling randomblob for each row, so it
;;; blocks inside SQLite while the watchdog holds it.
;;;
;;; An interrupt stops the step only from inside it: SQLite clears the
;;; connection's interrupt as a statement starts with none active. So the
;;; first round is the handshake: holding the mutex, the watchdog
;;; interrupts before the statement starts, which it then may; reads the
;;; flag each 1 ms until it reads clear, which only the step's start does,
;;; the step then held at its next allocation; interrupts again, inside the
;;; step; and lets the mutex go. Each later round takes the mutex, sleeps
;;; 1 ms holding it, interrupts, lets it go, and sleeps 1 ms. Slice 6's
;;; first round, without the handshake, could interrupt before the step's
;;; clear, and a later round then had to win the CPU from Valgrind: with the
;;; call made 200 ms late, this suite took 11 to 22 s under the gate, and
;;; tests/test-interrupt-close.sps 10 to 45 s, four runs each, where with the
;;; handshake each took 11 s every time (tests/test-interrupt-reach.sps's
;;; header).
;;;
;;; The handshake holds the mutex through the owner's whole way into its
;;; step, so each call the owner makes while the watchdog may hold the mutex
;;; takes nothing of SQLite's memory, or is __collect_safe: so the owner never
;;; blocks on the mutex in a call that keeps another thread's collection
;;; waiting, which the watchdog, holding it, might start. execute! there is
;;; a check-out from the cache, a bind of an integer over a NULL, the step,
;;; the failure's reads of the code and message, and the finalize. So the
;;; long statement takes its bound as a parameter and is run once, with a
;;; bound of 1, before with-transaction begins: the watched execute! finds
;;; it in the cache, with no prepare. A prepare is __collect_safe too, but
;;; its parse clears the interrupt and its tokenizer checks it, so the
;;; handshake would stop the prepare, leaving the write unstarted and its
;;; transaction open. The owner touches
;;; nothing more until the watchdog has ended, so has let the mutex go.
;;;
;;; A raise anywhere in a round is the watchdog's answer, never its end:
;;; the round's handler lets the mutex go if the round took it, notes the
;;; raise, counts the watchdog started, sleeps 1 ms, and the next round
;;; follows, until the statement is done or the deadline has passed, for a
;;; thread that dies on a raise leaves the statement uninterrupted, or
;;; blocked inside SQLite for good, and the suite hung, naming no row
;;; (AGENTS.md). The one raise it can't answer is a mutex-leave that raises
;;; every time: the mutex is then held, and the statement's next allocation
;;; blocks for good. The deadline bounds the watchdog's life, never the
;;; interrupt's latency.
;;;
;;; Every wait is bounded. Every computation that can raise runs under a
;;; guard with a sentinel of its own. Effects run in order (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure fork-thread thread-join make-mutex make-condition
              with-mutex condition-wait condition-broadcast sleep make-time current-time
              add-duration time-difference time>=?)
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

;; --- bindings made here, after the load ------------------------------------------------

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; sqlite3_mutex *sqlite3_mutex_alloc(int), void sqlite3_mutex_enter(sqlite3_mutex*),
;; void sqlite3_mutex_leave(sqlite3_mutex*)
(define mutex-alloc (bound 'sqlite3_mutex_alloc (foreign-procedure "sqlite3_mutex_alloc" (int) uptr)))
(define mutex-enter (bound 'sqlite3_mutex_enter (foreign-procedure "sqlite3_mutex_enter" (uptr) void)))
(define mutex-leave (bound 'sqlite3_mutex_leave (foreign-procedure "sqlite3_mutex_leave" (uptr) void)))

;; int sqlite3_is_interrupted(sqlite3*), from 3.41.0, so at the floor
(define is-interrupted (bound 'sqlite3_is_interrupted (foreign-procedure "sqlite3_is_interrupted" (uptr) int)))

;; SQLITE_MUTEX_STATIC_MEM, sqlite3.h's 3: the mutex sqlite3_malloc takes. A
;; static mutex is SQLite's own, never freed.
(define memory-mutex (guard (e (#t 0)) (mutex-alloc 3)))

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

;; --- the watchdog --------------------------------------------------------------------------

;; duration : Natural -> Time
;; MS milliseconds as a time-duration, its nanoseconds below 10^9.
(define (duration ms)
  (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000)))

;; await : Mutex Condition (-> Boolean) Natural -> Boolean
;; With MUTEX held: wait on CONDITION until READY? holds, #t, or MS
;; milliseconds have passed, #f. Every wait is bounded by the deadline.
(define (await mutex condition ready? ms)
  (let ((deadline (add-duration (current-time 'time-monotonic) (duration ms))))
    (let loop ()
      (let ((now (current-time 'time-monotonic)))
        (cond ((ready?) #t)
              ((time>=? now deadline) #f)
              (else (condition-wait condition mutex (time-difference deadline now))
                    (loop)))))))

;; How long this thread waits for the watchdog's first round.
(define answer-ms 30000)
;; The watchdog's bound, and the owner's wait for its end, in milliseconds.
(define bound-ms 120000)
(define one-ms (duration 1))

;; interrupted : Database (-> Any) -> (List Any Symbol Any)
;; THUNK run on this thread while a watchdog thread interrupts DB, by
;; native's sqlite3_interrupt on its handle, from before THUNK starts until
;; it has returned or raised, or bound-ms have passed since the call began.
;; Each round the watchdog takes SQLite's memory mutex, sleeps 1 ms holding
;; it, interrupts, lets the mutex go, and sleeps 1 ms, the first round the
;; handshake; THUNK starts once that holds the mutex and has interrupted
;; (the suite's header). Answers what
;; THUNK raised, as (raised-object E), E the object itself, or no-raise;
;; interrupts-sent or no-interrupt-sent; and the watchdog's end:
;; the-watchdog-ended, the-watchdog-did-not-end, or (the-watchdog-raised
;; WHAT ... END), the first three of its raises, which are its answer,
;; never its end. A watchdog that never took its first round within
;; answer-ms answers (the-watchdog-never-started R) for R.
(define (interrupted db thunk)
  (let* ((handle (call-with-open-handle 'test-transaction-interrupt db (lambda (h) h)))
         (m (make-mutex))
         (c (make-condition))
         (started #f)
         (done #f)
         (ended #f)
         (sent 0)
         (raises '())
         (by (add-duration (current-time 'time-monotonic) (duration bound-ms)))
         (past? (lambda () (time>=? (current-time 'time-monotonic) by)))
         (note! (lambda (what) (with-mutex m (when (< (length raises) 3) (set! raises (cons what raises))))))
         (start! (lambda () (with-mutex m (unless started (set! started #t) (condition-broadcast c)))))
         ;; holding: whether this round took SQLite's mutex and has not let
         ;; it go. Only the watchdog's thread reads or sets it.
         (holding #f)
         ;; let-go! : -> Void
         ;; The mutex let go, if this round took it. A mutex-leave that
         ;; raises has not let it go, so HOLDING stays set, the handler
         ;; tries again, and the next round takes it no second time.
         (let-go! (lambda () (when holding (mutex-leave memory-mutex) (set! holding #f))))
         ;; interrupt : -> Any
         ;; sqlite3_interrupt on the handle: void, or (raised WHAT).
         (interrupt (lambda ()
                      (guard (e (#t (list 'raised (what-raised e))))
                        (sqlite3-interrupt handle)
                        'void)))
         ;; send! : -> Void
         ;; The interrupt sent, counted, what it answers but void noted.
         (send! (lambda ()
                  (let ((verb (interrupt)))
                    (with-mutex m (set! sent (+ sent 1)))
                    (unless (eq? verb 'void) (note! verb)))))
         ;; handshaken: whether the first round has been tried.
         (handshaken #f)
         ;; handshake! : -> 'again
         ;; The first round, tests/test-interrupt-reach.sps's: SQLite's mutex
         ;; taken and the interrupt sent before THUNK starts, so the flag
         ;; reads set; then, the mutex held, the flag read each 1 ms until it
         ;; reads clear, which only THUNK's step does, at its statement's
         ;; start; then the interrupt sent again, landing inside the step,
         ;; and the mutex let go. Tried once, whatever it raises: a second
         ;; try could wait, holding the mutex, for a clear that came already.
         (handshake!
          (lambda ()
            (set! handshaken #t)
            (mutex-enter memory-mutex)
            (set! holding #t)
            (send!)
            (unless (eqv? (is-interrupted handle) 1) (note! 'the-first-interrupt-left-the-flag-clear))
            (start!)
            (let wait ()
              (unless (or (with-mutex m done) (past?))
                (sleep one-ms)
                (if (eqv? (is-interrupted handle) 0)
                    (send!)
                    (wait))))
            (let-go!)
            'again))
         ;; round! : -> (U 'again 'stop)
         ;; One round, the first a handshake; what it raises is raised, to
         ;; the loop's handler.
         (round!
          (lambda ()
            (cond
              ((or (with-mutex m done) (past?)) 'stop)
              ((not handshaken) (handshake!))
              (else
                (unless holding (mutex-enter memory-mutex) (set! holding #t))
                (start!)
                (sleep one-ms)
                (let ((verb (interrupt)))
                  (let-go!)
                  (with-mutex m (set! sent (+ sent 1)))
                  (unless (eq? verb 'void) (note! verb)))
                (sleep one-ms)
                'again))))
         (watchdog
          (fork-thread
           (lambda ()
             (let loop ()
               (let ((next (guard (e (#t (guard (x (#t #f)) (let-go!))
                                         (guard (x (#t #f)) (note! (list 'a-round-raised (what-raised e))))
                                         (guard (x (#t #f)) (start!))
                                         (guard (x (#t #f)) (sleep one-ms))
                                         'again))
                             (round!))))
                 (when (eq? next 'again) (loop))))
             (with-mutex m
               (set! started #t)
               (set! ended #t)
               (condition-broadcast c)))))
         (ready (with-mutex m (await m c (lambda () started) answer-ms)))
         (r (guard (e (#t (list 'raised-object e))) (thunk) 'no-raise))
         (stopped (with-mutex m
                    (set! done #t)
                    (if (await m c (lambda () ended) bound-ms)
                        'the-watchdog-ended
                        'the-watchdog-did-not-end)))
         (n (with-mutex m sent))
         (raised (with-mutex m (reverse raises))))
    (when (eq? stopped 'the-watchdog-ended) (thread-join watchdog))
    (list (if ready r (list 'the-watchdog-never-started r))
          (if (> n 0) 'interrupts-sent 'no-interrupt-sent)
          (if (null? raised) stopped (list 'the-watchdog-raised raised stopped)))))

;; --- the cases -----------------------------------------------------------------------------

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

;; long-write, long-read : String
;; A recursive CTE of ?1 rows, each calling randomblob, which allocates, so
;; the watchdog's hold blocks the step inside SQLite (the header): inserted
;; into b, a write; counted beside src's three rows, a read.
(define long-write "insert into b with recursive k(i) as (select 1 union all select i + 1 from k where i < ?1) select i from k where length(randomblob(16)) = 16")
(define long-read "with recursive k(i) as (select 1 union all select i + 1 from k where i < ?1) select count(*) from k, src where length(randomblob(16)) = 16")

;; long-rows : Positive-Integer
;; The CTE's bound when watched: uninterrupted, about 5 s plain on the
;; container's host each way, and 10 s beside the watchdog's holds, so a
;; mutant that never interrupts fails its row by name; the write's file
;; then grows by about 230 MB before the rollback.
(define long-rows 20000000)

;; interrupted-row : String Boolean -> Any
;; SQL through execute!, interrupted, inside with-transaction, deferred,
;; after a marker; NESTED, inside an inner with-transaction after a second
;; marker, whose raise the outer body catches before it returns. SQL is run
;; once first, its bound 1, before with-transaction, so the watched call
;; finds it in the cache (the header). The body records what execute!
;; raised, the watchdog's two answers and autocommit straight after, and
;; raises execute!'s condition. Then what with-transaction raised, the
;; inner's and the outer's when nested; in-transaction?; the markers on DB
;; and DB2; the statements it issued.
(define (interrupted-row sql nested)
  (with-case
   (lambda (db db2)
     (let* ((cached (execute! db sql 1))
            (recorded #f) (inner 'not-nested)
            (body (lambda ()
                    (let* ((i (interrupted db (lambda () (execute! db sql long-rows))))
                           (raised (and (pair? (car i)) (eq? (car (car i)) 'raised-object) (cadr (car i))))
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

(test-equal "SQLite's memory mutex is had"
  'a-mutex
  (if (and (integer? memory-mutex) (> memory-mutex 0)) 'a-mutex memory-mutex))

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
