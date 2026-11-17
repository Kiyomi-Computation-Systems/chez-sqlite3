#!r6rs
;;; What interrupt-database! reaches, and what it doesn't (ADR-0019, decisions
;;; 5 and 6; the M3 plan, section 4.4; M3's research, concurrency I1 to I7,
;;; and trap 1 and 2). Each interrupt comes from another thread.
;;;
;;;   a long step     a recursive CTE stepped by step!, and by query-row from
;;;                   the cache, stopped by a watchdog: &sqlite-interrupt from
;;;                   the verb that stepped, and the connection goes on
;;;   a long prepare  three megabytes of SQL, stopped by a watchdog that
;;;                   repeats the interrupt until the prepare returns:
;;;                   &sqlite-interrupt from prepare-statement
;;;   a busy wait     not stopped: under another connection's BEGIN
;;;                   IMMEDIATE, with a busy timeout of 1500 ms and interrupts
;;;                   all through the wait, BEGIN IMMEDIATE still waits at
;;;                   least 1000 ms and under 3000, then raises &sqlite-busy
;;;   a held row      the interrupt sticks: every later statement fails until
;;;                   the held one is reset, then one runs
;;;   between         an interrupt that lands while no statement runs is
;;;   statements      lost: a fresh connection, a statement prepared and not
;;;                   yet stepped, and one run to its end each go on
;;;
;;; The watchdog. Valgrind runs one thread at a time, and a thread running C
;;; keeps it: a watchdog meant to interrupt every 5 ms sent its first
;;; interrupt 16.5 s into a step (.plans/traps.md), and against a prepare of
;;; 4 MB of comments, about 3.8 to 4 s under Valgrind, a watchdog stopped
;;; none of 18 prepares: interrupting with no sleep, it sent no interrupt in
;;; 14 of 15 and 125 in the other; sleeping 1 ms a round, none in 3
;;; (.plans/m3-slice-6-mutation-log.md, part A, and
;;; .plans/research/m3-slice-6/output.txt). A thread
;;; blocked on a mutex lets the others run. So the watchdog, each round,
;;; takes SQLite's own memory mutex, SQLITE_MUTEX_STATIC_MEM, which
;;; sqlite3_malloc and sqlite3_free take while memory statistics are on, as
;;; they are on both libraries; sleeps 1 ms holding it; calls the verb; lets
;;; it go; sleeps 1 ms. The step and the prepare allocate as they run, so
;;; each blocks inside SQLite, and the watchdog's interrupt lands there, on
;;; any scheduler. Its SQL is chosen for it: the step calls randomblob for
;;; each row, and the prepare's IN list makes an expression for each item,
;;; where comments make none. The watchdog repeats until the call has
;;; returned, or a deadline 120 s away has passed, which bounds its life and
;;; never fails a row by itself. Each call the owner makes while the
;;; watchdog may hold the mutex takes nothing of SQLite's memory, as a bind
;;; of an integer over a NULL does, or is __collect_safe, as the step, the
;;; prepare and the finalize are: so the owner never blocks on the mutex in
;;; a call that keeps another thread's collection waiting, which the
;;; watchdog, holding it, might start. The hold is no critical section:
;;; inside one, a collection the owner starts waits for the section's end,
;;; so the watchdog lets the mutex go before the owner's call begins, and
;;; the long prepare ran unstopped under the gate, four runs of four
;;; (.plans/m3-slice-6-mutation-log.md).
;;; The busy wait's watchdog takes no mutex: the owner sleeps in the busy
;;; handler, which lets it run.
;;;
;;; The probe. sqlite3_is_interrupted, bound here after the load, reads 1
;;; once an interrupt reached SQLite, until the next statement starts
;;; (concurrency I2): the rows between statements read it set before their
;;; next statement, so the interrupt they lose did reach SQLite; the busy
;;; wait's row reads it set after the wait, which started no statement.
;;;
;;; A thread this suite forks answers whatever it raises, and every wait for
;;; it is bounded (AGENTS.md). The loading procedures are reached through
;;; eval, under a guard. Every computation that can raise runs under a guard
;;; with a sentinel of its own; no expected value is #f. Effects run in
;;; order, through let* and named lets, never map.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure fork-thread thread-join make-mutex with-mutex
              make-condition condition-wait condition-broadcast make-time current-time
              time-difference add-duration time>=? sleep real-time)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-busy? sqlite-closed? sqlite-wrong-thread?)
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

(define (public name) (reach '(chez-sqlite3) name))

(define interrupt-database! (public 'interrupt-database!))
(define open-database (public 'open-database))
(define close-database! (public 'close-database!))
(define prepare-statement (public 'prepare-statement))
(define finalize-statement! (public 'finalize-statement!))
(define step! (public 'step!))
(define reset! (public 'reset!))
(define bind! (public 'bind!))
(define column-value (public 'column-value))
(define execute! (public 'execute!))
(define query-row (public 'query-row))
(define statement-state (reach '(chez-sqlite3 private statement) 'statement-state))
(define database-cache-count (reach '(chez-sqlite3 private connection) 'database-cache-count))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))

;; --- bindings made here, after the load ------------------------------------------------

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_is_interrupted(sqlite3*), from 3.41.0, so at the floor
(define is-interrupted (bound 'sqlite3_is_interrupted (foreign-procedure "sqlite3_is_interrupted" (uptr) int)))
;; sqlite3_mutex *sqlite3_mutex_alloc(int), void sqlite3_mutex_enter(sqlite3_mutex*),
;; void sqlite3_mutex_leave(sqlite3_mutex*)
(define mutex-alloc (bound 'sqlite3_mutex_alloc (foreign-procedure "sqlite3_mutex_alloc" (int) uptr)))
(define mutex-enter (bound 'sqlite3_mutex_enter (foreign-procedure "sqlite3_mutex_enter" (uptr) void)))
(define mutex-leave (bound 'sqlite3_mutex_leave (foreign-procedure "sqlite3_mutex_leave" (uptr) void)))

;; SQLITE_MUTEX_STATIC_MEM, sqlite3.h's 3: the mutex sqlite3_malloc takes. A
;; static mutex is SQLite's own, never freed.
(define memory-mutex (guard (e (#t 0)) (mutex-alloc 3)))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
;; E as the rows compare it: an &sqlite-error by its class, who and codes,
;; the class sqlite-interrupt, sqlite-busy or sqlite-error; &sqlite-closed
;; and &sqlite-wrong-thread by their who; an assertion violation by its who
;; and irritants.
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list (cond ((sqlite-interrupt? e) 'sqlite-interrupt)
                     ((sqlite-busy? e) 'sqlite-busy)
                     (else 'sqlite-error))
               (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((sqlite-wrong-thread? e) (list 'wrong-thread (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

;; answered : (-> Any) -> Any
;; What THUNK answered, by attempt, the void object as void.
(define (answered thunk)
  (let ((r (attempt thunk)))
    (if (eq? r (if #f #f)) 'void (list 'answered r))))

(define (interrupt! db) (answered (lambda () (interrupt-database! db))))

;; flag : Database -> Any
;; sqlite3_is_interrupted on DB's handle: set for 1, clear for 0.
(define (flag db)
  (attempt (lambda ()
             (call-with-open-handle 'test-interrupt-reach db
               (lambda (h)
                 (let ((n (is-interrupted h)))
                   (cond ((eqv? n 1) 'set) ((eqv? n 0) 'clear) (else (list 'neither n)))))))))

(define (close-quietly db) (guard (e (#t #f)) (close-database! db)))

;; with-db : (Database -> Any) -> Any
;; PROC given a fresh :memory: connection, by attempt, closed after however
;; PROC ends.
(define (with-db proc)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda () (attempt (lambda () (set! db (open-database ":memory:")) (proc db))))
      (lambda () (when db (close-quietly db))))))

;; --- threads -------------------------------------------------------------------------------

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

(define answer-ms 30000)

;; on-another-thread : (-> Any) -> Any
;; THUNK run on a thread of its own: its answer, or (raised TEXT) for what
;; it raised; unfinished when it has not answered within answer-ms.
(define (on-another-thread thunk)
  (let* ((m (make-mutex))
         (c (make-condition))
         (done #f)
         (answer 'unfinished)
         (thread (fork-thread
                  (lambda ()
                    (let ((a (guard (e (#t (list 'raised (describe e)))) (thunk))))
                      (with-mutex m
                        (set! answer a)
                        (set! done #t)
                        (condition-broadcast c)))))))
    (if (with-mutex m (await m c (lambda () done) answer-ms))
        (begin (thread-join thread) (with-mutex m answer))
        'unfinished)))

;; The watchdog's bound, and the owner's wait for its end, in milliseconds.
(define bound-ms 120000)
(define one-ms (duration 1))

;; watched : Database (-> Any) Boolean [Natural]
;;           -> (List Any Natural Symbol Any (Listof Natural))
;; THUNK run on this thread while a watchdog thread interrupts DB, from
;; before THUNK starts, or from QUIET-MS milliseconds after it starts when
;; QUIET-MS is given, until it has returned or raised, or bound-ms have
;; passed since the call began. A quiet round sends nothing, and sleeps
;; 1 ms. Each round, when HOLD?, the watchdog takes
;; SQLite's memory mutex and sleeps 1 ms holding it, calls interrupt-database!,
;; lets the mutex go; then it sleeps 1 ms (the suite's header). THUNK starts
;; only once the watchdog holds the mutex for its first round. Answers what
;; THUNK answered, or (raised WHAT); the milliseconds THUNK took;
;; interrupts-sent or no-interrupt-sent; the watchdog's end:
;; the-watchdog-ended, the-watchdog-did-not-end, or (the-watchdog-raised
;; WHAT ... END), the first three of its raises, which are its answer,
;; never its end; and the
;; milliseconds, from THUNK's start, at which each interrupt was sent.
(define watched
  (case-lambda
    ((db thunk hold?) (watched db thunk hold? 0))
    ((db thunk hold? quiet-ms) (watched/quiet db thunk hold? quiet-ms))))

(define (watched/quiet db thunk hold? quiet-ms)
  (let* ((m (make-mutex))
         (c (make-condition))
         (started #f)
         (done #f)
         (ended #f)
         (sends '())
         (raises '())
         (by (add-duration (current-time 'time-monotonic) (duration bound-ms)))
         (past? (lambda () (time>=? (current-time 'time-monotonic) by)))
         (t0 #f)
         (note! (lambda (what) (with-mutex m (when (< (length raises) 3) (set! raises (cons what raises))))))
         (watchdog
          (fork-thread
           (lambda ()
             (let round ()
               (cond
                 ((or (with-mutex m done) (past?)))
                 ((and (> quiet-ms 0)
                       (with-mutex m
                         (unless started (set! started #t) (condition-broadcast c))
                         (or (not t0) (< (- (real-time) t0) quiet-ms))))
                  (sleep one-ms)
                  (round))
                 (else
                   (when hold? (mutex-enter memory-mutex))
                   (with-mutex m
                     (unless started (set! started #t) (condition-broadcast c)))
                   (when hold? (sleep one-ms))
                   (let ((verb (interrupt! db)))
                     (when hold? (mutex-leave memory-mutex))
                     (unless (eq? verb 'void) (note! verb)))
                   (with-mutex m (when t0 (set! sends (cons (- (real-time) t0) sends))))
                   (sleep one-ms)
                   (round))))
             (with-mutex m
               (set! started #t)
               (set! ended #t)
               (condition-broadcast c)))))
         (ready (with-mutex m (await m c (lambda () started) answer-ms)))
         (r (begin (with-mutex m (set! t0 (real-time)))
                   (attempt thunk)))
         (took (- (real-time) t0))
         (stopped (with-mutex m
                    (set! done #t)
                    (if (await m c (lambda () ended) bound-ms)
                        'the-watchdog-ended
                        'the-watchdog-did-not-end)))
         (sent (with-mutex m (reverse sends)))
         (raised (with-mutex m (reverse raises))))
    (when (eq? stopped 'the-watchdog-ended) (thread-join watchdog))
    (list (if ready r (list 'the-watchdog-never-started r))
          took
          (if (null? sent) 'no-interrupt-sent 'interrupts-sent)
          (if (null? raised) stopped (list 'the-watchdog-raised raised stopped))
          sent)))

;; watched-outcome : (List Any Natural Symbol Any (Listof Natural)) -> (List Any Symbol Any)
;; What watched answered, without its times.
(define (watched-outcome w) (list (car w) (caddr w) (cadddr w)))

;; --- the SQL -------------------------------------------------------------------------------

;; long-step : String
;; A recursive CTE of ? rows, each calling randomblob, which allocates: at
;; 100,000,000, about 19 s uninterrupted on the container's host, so a
;; mutant that never interrupts fails its row by name.
(define long-step
  "with recursive k(i) as (select 1 union all select i + 1 from k where i < ?) select count(*) from k where length(randomblob(16)) = 16")
(define long-rows 100000000)

;; long-prepare : (U String (List 'raised String))
;; select 1 in (1, 1, ..., 1), a million and one items, 3,000,015 characters:
;; the parser makes an expression for each, and the tokenizer checks the
;; interrupt at each space (concurrency I7).
(define long-prepare
  (guard (e (#t (list 'raised (describe e))))
    (call-with-string-output-port
     (lambda (p)
       (put-string p "select 1 in (")
       (let loop ((i 0))
         (when (< i 1000000)
           (put-string p "1, ")
           (loop (+ i 1))))
       (put-string p "1)")))))

(define interrupted-by (lambda (who) (list 'raised (list 'sqlite-interrupt who 'interrupt 'interrupt))))
(define watched-well '(interrupts-sent the-watchdog-ended))

(define temp-dir (guard (e (#t #f)) (make-process-temp-directory)))

(test-begin "interrupt-reach")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-assert "a temporary directory for the suite's databases"
  (string? temp-dir))

(test-equal "SQLite's memory mutex is had, and the long prepare's SQL is 3,000,015 characters"
  '(a-mutex 3000015)
  (list (if (and (integer? memory-mutex) (> memory-mutex 0)) 'a-mutex memory-mutex)
        (if (string? long-prepare) (string-length long-prepare) long-prepare)))

;; --- a long step -----------------------------------------------------------------------------

(test-equal "a long step, stopped from another thread: step! raises &sqlite-interrupt, interrupt and interrupt; the statement is failed; the connection then runs a statement"
  (append (list (interrupted-by 'step!)) watched-well (list 'failed '#(1)))
  (with-db
   (lambda (db)
     (let* ((st (prepare-statement db long-step))
            (bound (bind! st 1 long-rows))
            (w (watched-outcome (watched db (lambda () (step! st)) #t)))
            (state (attempt (lambda () (statement-state st))))
            (next (attempt (lambda () (query-row db "select 1")))))
       (append w (list state next))))))

(test-equal "a long step through query-row, its statement from the cache: query-row raises &sqlite-interrupt, interrupt and interrupt; the statement whose step failed leaves the cache; the connection then runs a statement"
  (append (list '#(1) 1) (list (interrupted-by 'query-row)) watched-well (list 0 '#(1)))
  (with-db
   (lambda (db)
     (let* ((first (query-row db long-step 1))
            (cached (database-cache-count db))
            (w (watched-outcome (watched db (lambda () (query-row db long-step long-rows)) #t)))
            (after (attempt (lambda () (database-cache-count db))))
            (next (attempt (lambda () (query-row db "select 1")))))
       (append (list first cached) w (list after next))))))

;; --- a long prepare ------------------------------------------------------------------------

(test-equal "a prepare of three megabytes of SQL, stopped by a watchdog that repeats the interrupt until the prepare returns: prepare-statement raises &sqlite-interrupt, interrupt and interrupt; nothing is prepared or counted; the connection then runs a statement"
  (append (list (interrupted-by 'prepare-statement)) watched-well
          (list (list '(block . 0) '(connection . 1) '(statement . 0)) '#(1)))
  (with-db
   (lambda (db)
     (let* ((w (watched-outcome (watched db (lambda () (prepare-statement db long-prepare)) #t)))
            (counts (native-counts))
            (next (attempt (lambda () (query-row db "select 1")))))
       (append w (list counts next))))))

;; --- a busy wait ---------------------------------------------------------------------------

;; how-long : Natural -> Symbol
;; MS as waited, at least 1000 and under 3000; too-long, from 3000; or
;; at-once. The wait's busy timeout is 1500 ms: a build without nanosleep
;; sleeps whole seconds, 1000 ms of it, which still waited; a retry in Scheme
;; waits it out twice (AGENTS.md; ADR-0019, amended).
(define (how-long ms) (cond ((>= ms 3000) 'too-long) ((>= ms 1000) 'waited) (else 'at-once)))

;; during-the-wait : (Listof Natural) -> Symbol
;; Whether an interrupt was sent from 250 to 1000 ms into a wait of at
;; least 1000: well inside the busy handler, past the statement's start.
(define (during-the-wait sends)
  (if (exists (lambda (ms) (<= 250 ms 1000)) sends)
      'interrupted-during-the-wait
      (list 'no-interrupt-during-the-wait sends)))

;; The watchdog stays quiet for the wait's first quiet-ms. SQLite clears a
;; connection's interrupt when a statement starts with none running, and an
;; interrupt that lands after that, before the statement reaches its busy
;; wait, stops the statement at once: plain, the watchdog's first interrupt,
;; sent as the step began, did so in 2 runs of 30, BEGIN IMMEDIATE raising
;; &sqlite-interrupt at 0 ms (the slice's mutation log, the lead's checks of
;; follow-up 2). That is the interrupt stopping a statement, as it should;
;; this row holds the wait, which no interrupt stops, so its interrupts start
;; well inside it, and during-the-wait still requires one from 250 ms.
(define quiet-ms 200)

(test-equal "a busy wait it doesn't stop: under another connection's BEGIN IMMEDIATE, with a busy timeout of 1500 ms and interrupts from 200 ms into the wait to its end, which reach SQLite, BEGIN IMMEDIATE waits at least 1000 ms and under 3000, then step! raises &sqlite-busy, busy and busy"
  (list '(raised (sqlite-busy step! busy busy)) 'interrupts-sent 'the-watchdog-ended 'waited
        'interrupted-during-the-wait 'set zero-counts)
  (let ((holder #f) (waiter #f) (st #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (let ((path (string-append (or temp-dir "/nonexistent") "/busy.db")))
             (set! holder (open-database path))
             (execute! holder "create table t (x)")
             (execute! holder "begin immediate")
             (set! waiter (open-database path '((busy-timeout . 1500))))
             (set! st (prepare-statement waiter "begin immediate"))
             (let* ((w (watched waiter (lambda () (step! st)) #f quiet-ms))
                    (ms (cadr w))
                    (reached (flag waiter)))
               (display "    timed: the busy wait, interrupted: ")
               (display ms)
               (display " ms")
               (newline)
               (finalize-statement! st)
               (set! st #f)
               (execute! holder "rollback")
               (close-database! waiter)
               (set! waiter #f)
               (close-database! holder)
               (set! holder #f)
               (list (car w) (caddr w) (cadddr w) (how-long ms) (during-the-wait (list-ref w 4))
                     reached (native-counts)))))))
      (lambda ()
        (when st (guard (e (#t #f)) (finalize-statement! st)))
        (for-each (lambda (db) (when db (close-quietly db))) (list waiter holder))))))

;; --- a held row ----------------------------------------------------------------------------

(test-equal "a statement held at a row: an interrupt from another thread sticks, so prepare-statement, execute! and query-row each raise &sqlite-interrupt from itself, until the held statement is reset; then a statement runs"
  (list 'void (interrupted-by 'prepare-statement) (interrupted-by 'execute!)
        (interrupted-by 'query-row) 'reset '#(4))
  (with-db
   (lambda (db)
     (let* ((held (prepare-statement db "select 1 union all select 2"))
            (row (step! held))
            (there (on-another-thread (lambda () (interrupt! db))))
            (a (attempt (lambda () (prepare-statement db "select 2"))))
            (b (attempt (lambda () (execute! db "create table t (x)"))))
            (c (attempt (lambda () (query-row db "select 3"))))
            (reset (attempt (lambda () (reset! held) 'reset)))
            (d (attempt (lambda () (query-row db "select 4")))))
       (finalize-statement! held)
       (list there a b c reset d)))))

;; --- between statements --------------------------------------------------------------------

(test-equal "an interrupt that lands between statements is lost: on a fresh connection, from another thread, it reaches SQLite, and the next statement runs, clearing it"
  '(void set #(1) clear)
  (with-db
   (lambda (db)
     (let* ((there (on-another-thread (lambda () (interrupt! db))))
            (before (flag db))
            (next (attempt (lambda () (query-row db "select 1"))))
            (after (flag db)))
       (list there before next after)))))

(test-equal "an interrupt that lands while a statement is prepared and not yet stepped is lost: it reaches SQLite, and the statement steps to its row"
  '(void set #t 7 clear)
  (with-db
   (lambda (db)
     (let* ((st (prepare-statement db "select 7"))
            (there (on-another-thread (lambda () (interrupt! db))))
            (before (flag db))
            (row (attempt (lambda () (step! st))))
            (value (attempt (lambda () (column-value st 0))))
            (after (flag db)))
       (finalize-statement! st)
       (list there before row value after)))))

(test-equal "an interrupt that lands after a statement ran to its end, unreset, is lost: it reaches SQLite, and the next statement runs"
  '(done void set #(1) clear)
  (with-db
   (lambda (db)
     (let* ((made (execute! db "create table t (x)"))
            (st (prepare-statement db "insert into t values (1)"))
            (ran (attempt (lambda () (if (eq? (step! st) #f) 'done 'a-row))))
            (there (on-another-thread (lambda () (interrupt! db))))
            (before (flag db))
            (next (attempt (lambda () (query-row db "select count(*) from t"))))
            (after (flag db)))
       (finalize-statement! st)
       (list ran there before next after)))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "interrupt-reach")

(exit (suite-exit-status runner))
