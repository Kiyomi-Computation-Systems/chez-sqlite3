#!r6rs
;;; interrupt-database! after a close that left the connection open, and
;;; against opens and closes on another thread (ADR-0019).
;;;
;;;   left open   a close refused for an untracked statement, and one that
;;;               sqlite3_close itself refuses, busy beside an unfinished
;;;               backup: after either, a long step on the connection is
;;;               stopped from another thread, &sqlite-interrupt from step!
;;;   the race    one thread interrupts whatever connection the other has
;;;               published, while that one opens a file's connection,
;;;               publishes it and closes it, again and again, the closed one
;;;               left published until the next is: every interrupt answers
;;;               void and raises nothing, some land on a closed connection,
;;;               nothing is counted after. Under make test-memory, Valgrind
;;;               reads every access the race makes
;;;
;;; The watchdog of the left-open rows is tests/test-interrupt-reach.sps's,
;;; whose header says why it holds SQLite's memory mutex across each round:
;;; under Valgrind a thread running C keeps the CPU from every other; and why
;;; its first round is a handshake: SQLite clears the interrupt as the step
;;; starts, so the watchdog interrupts again only once it has read the flag
;;; clear, the step then held at its next allocation.
;;;
;;; The race's interrupter makes its calls in bursts of ten, and sleeps 1
;;; microsecond after each burst, a system call that lets the owner run under
;;; Valgrind, which runs one thread at a time; the owner's opens and closes
;;; of a file make system calls of their own. A mutant that calls
;;; sqlite3_interrupt whatever the flag says fails the race row by name: the
;;; close clears the record's handle, so the mutant's call on a closed
;;; connection is refused on #f before it reaches C, and Valgrind saw no
;;; error against it over 1, 20 and 200 rounds. A second mutant reads the
;;; handle before the latch and calls whenever it is not #f, ignoring the
;;; flag: the race passed it over 200 rounds under the gate, with no error,
;;; though Valgrind reports sqlite3_interrupt on a freed connection when a
;;; stale handle reaches C. So the race row sees no missing exclusion.
;;; tests/test-interrupt-database.sps fails both mutants on one thread, with
;;; no timing: its rows inside the close, and its engine row through a
;;; stand-in, whose call comes after the close, on #f for the first and on
;;; the live handle for the second. Its engine row through the verb raises on
;;; the first's #f, and under make test-memory Valgrind reports the second's
;;; call on the freed connection there. Its two-thread row fails the second,
;;; and tests/test-interrupt.sps fails a latch without its mutex.
;;;
;;; A thread this suite forks answers whatever it raises, and every wait for
;;; it is bounded. The loading procedures are reached through eval, under a
;;; guard. Every computation that can raise runs under a guard with a
;;; sentinel of its own; no expected value is #f. Effects run in order,
;;; through let* and named lets, never map.
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
(define bind! (public 'bind!))
(define query-row (public 'query-row))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-out-pointer (reach '(chez-sqlite3 private native) 'call-with-out-pointer))

;; --- bindings made here, after the load ------------------------------------------------

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_prepare_v2(sqlite3*, const char *zSql, int nByte, sqlite3_stmt **, const char **pzTail)
(define prepare-v2 (bound 'sqlite3_prepare_v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int)))
;; int sqlite3_finalize(sqlite3_stmt*)
(define finalize (bound 'sqlite3_finalize (foreign-procedure "sqlite3_finalize" (uptr) int)))
;; sqlite3_backup *sqlite3_backup_init(sqlite3 *pDest, const char *zDestName,
;;                                     sqlite3 *pSource, const char *zSourceName)
(define backup-init (bound 'sqlite3_backup_init (foreign-procedure "sqlite3_backup_init" (uptr uptr uptr uptr) uptr)))
;; int sqlite3_backup_finish(sqlite3_backup*)
(define backup-finish (bound 'sqlite3_backup_finish (foreign-procedure "sqlite3_backup_finish" (uptr) int)))
;; sqlite3_mutex *sqlite3_mutex_alloc(int), void sqlite3_mutex_enter(sqlite3_mutex*),
;; void sqlite3_mutex_leave(sqlite3_mutex*)
(define mutex-alloc (bound 'sqlite3_mutex_alloc (foreign-procedure "sqlite3_mutex_alloc" (int) uptr)))
(define mutex-enter (bound 'sqlite3_mutex_enter (foreign-procedure "sqlite3_mutex_enter" (uptr) void)))
(define mutex-leave (bound 'sqlite3_mutex_leave (foreign-procedure "sqlite3_mutex_leave" (uptr) void)))

;; int sqlite3_is_interrupted(sqlite3*), from 3.41.0, so at the floor
(define is-interrupted (bound 'sqlite3_is_interrupted (foreign-procedure "sqlite3_is_interrupted" (uptr) int)))

;; SQLITE_MUTEX_STATIC_MEM, sqlite3.h's 3: the mutex sqlite3_malloc takes.
(define memory-mutex (guard (e (#t 0)) (mutex-alloc 3)))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

;; counts-with : (Listof (Pairof Symbol Integer)) -> (Listof (Pairof Symbol Integer))
(define (counts-with changes)
  (map (lambda (entry) (cond ((assq (car entry) changes) => (lambda (c) c)) (else entry)))
       zero-counts))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
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

(define (answered thunk)
  (let ((r (attempt thunk)))
    (if (eq? r (if #f #f)) 'void (list 'answered r))))

(define (interrupt! db) (answered (lambda () (interrupt-database! db))))

(define (with-handle db proc) (call-with-open-handle 'test-interrupt-close db proc))

(define (close-quietly db) (guard (e (#t #f)) (close-database! db)))

;; prepare! : Database String -> Positive-Integer
;; A statement of SQL on DB, made here with the raw sqlite3_prepare_v2, so the
;; connection does not track it.
(define (prepare! db sql)
  (with-handle db
    (lambda (h)
      (call-with-c-string 'test-interrupt-close sql
        (lambda (text)
          (let-values (((rc statement)
                        (call-with-out-pointer 'test-interrupt-close
                          (lambda (slot) (prepare-v2 h text -1 slot 0)))))
            (if (and (eqv? rc 0) (not (eqv? statement 0)))
                statement
                (error 'prepare! "sqlite3_prepare_v2 did not answer a statement" rc))))))))

;; --- threads -------------------------------------------------------------------------------

(define (duration ms)
  (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000)))

(define (await mutex condition ready? ms)
  (let ((deadline (add-duration (current-time 'time-monotonic) (duration ms))))
    (let loop ()
      (let ((now (current-time 'time-monotonic)))
        (cond ((ready?) #t)
              ((time>=? now deadline) #f)
              (else (condition-wait condition mutex (time-difference deadline now))
                    (loop)))))))

(define answer-ms 30000)
(define bound-ms 120000)
(define one-ms (duration 1))
(define one-microsecond (make-time 'time-duration 1000 0))

;; watched : Database (-> Any) -> (List Any Symbol Any)
;; THUNK run on this thread while a watchdog thread interrupts DB, from
;; before THUNK starts until it has returned or raised, or bound-ms have
;; passed since the call began. Each round the watchdog takes SQLite's
;; memory mutex, sleeps 1 ms holding it, calls interrupt-database!, lets the
;; mutex go, and sleeps 1 ms, the first round the handshake; THUNK starts
;; once that holds the mutex and has interrupted. Answers what THUNK
;; answered, or (raised WHAT); interrupts-sent or no-interrupt-sent; and the
;; watchdog's end: the-watchdog-ended, the-watchdog-did-not-end, or
;; (the-watchdog-raised WHAT ... END), the first three of its raises, which
;; are its answer, never its end. A raise anywhere in a round, from
;; mutex-enter, sleep or the bookkeeping as much as from the verb, is noted
;; so: the round's handler lets SQLite's mutex go if the round took it,
;; counts the watchdog started, sleeps 1 ms, and the next round follows,
;; until THUNK is done or the deadline has passed. A thread that died
;; holding the mutex would leave THUNK blocked inside SQLite for good. The
;; one raise the device can't answer is a mutex-leave that raises every
;; time.
(define (watched db thunk)
  (let* ((handle (with-handle db (lambda (h) h)))
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
         ;; send! : -> Void
         ;; interrupt-database! on DB, counted, what it answers but void noted.
         (send! (lambda ()
                  (let ((verb (interrupt! db)))
                    (with-mutex m (set! sent (+ sent 1)))
                    (unless (eq? verb 'void) (note! verb)))))
         ;; handshaken: whether the first round has been tried.
         (handshaken #f)
         ;; handshake! : -> 'again
         ;; The first round, tests/test-interrupt-reach.sps's: SQLite's mutex
         ;; taken and the interrupt sent before THUNK starts, so the flag
         ;; reads set; then, the mutex held, the flag read each 1 ms until it
         ;; reads clear, which only THUNK's call does, at its statement's
         ;; start; then the interrupt sent again, landing inside the call,
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
                (let ((verb (interrupt! db)))
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
         (r (attempt thunk))
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

;; long-step : String
;; A recursive CTE of ? rows, each calling randomblob, which allocates
;; (tests/test-interrupt-reach.sps): at long-rows, about 19 s uninterrupted.
(define long-step
  "with recursive k(i) as (select 1 union all select i + 1 from k where i < ?) select count(*) from k where length(randomblob(16)) = 16")
(define long-rows 100000000)

;; stopped-step : Database -> (List Any Symbol Any)
;; The long step prepared on DB and stepped by step!, watched.
(define (stopped-step db)
  (let ((st (prepare-statement db long-step)))
    (bind! st 1 long-rows)
    (let ((w (watched db (lambda () (step! st)))))
      (finalize-statement! st)
      w)))

(define stopped '((raised (sqlite-interrupt step! interrupt interrupt)) interrupts-sent
                  the-watchdog-ended))

(define temp-dir (guard (e (#t #f)) (make-process-temp-directory)))

(test-begin "interrupt-close")

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

;; --- left open -------------------------------------------------------------------------------

(test-equal "after a close refused for an untracked statement, a long step on the connection is stopped from another thread: step! raises &sqlite-interrupt; once the statement is finalized the connection closes"
  (list '(raised (assertion-violation close-database! (untracked-statements 1)))
        (counts-with '((connection . 1))) stopped 0 'closed zero-counts)
  (let ((db #f) (raw #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let* ((made (set! raw (prepare! db "select 1")))
                  (refused (attempt (lambda () (close-database! db) 'closed)))
                  (counts (native-counts))
                  (w (stopped-step db))
                  (code (let ((c (finalize raw))) (set! raw #f) c))
                  (closed (attempt (lambda () (close-database! db) 'closed))))
             (list refused counts w code closed (native-counts))))))
      (lambda ()
        (when raw (guard (e (#t #f)) (finalize raw)))
        (when db (close-quietly db))))))

(test-equal "after a close that sqlite3_close refuses, busy beside an unfinished backup, a long step on the connection is stopped from another thread: step! raises &sqlite-interrupt; once the backup is finished both connections close"
  (list 'backup '(raised (sqlite-busy close-database! busy busy)) (counts-with '((connection . 2)))
        stopped 0 'closed 'closed zero-counts)
  (let ((source #f) (target #f) (backup #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! source (open-database ":memory:"))
           (set! target (open-database ":memory:"))
           (let* ((made (begin
                          (set! backup
                                (with-handle target
                                  (lambda (t)
                                    (with-handle source
                                      (lambda (s)
                                        (call-with-c-string 'test-interrupt-close "main"
                                          (lambda (main) (backup-init t main s main))))))))
                          (if (eqv? backup 0) 'no-backup 'backup)))
                  (refused (attempt (lambda () (close-database! source) 'closed)))
                  (counts (native-counts))
                  (w (stopped-step source))
                  (finished (let ((code (backup-finish backup))) (set! backup #f) code))
                  (a (attempt (lambda () (close-database! source) 'closed)))
                  (b (attempt (lambda () (close-database! target) 'closed))))
             (list made refused counts w finished a b (native-counts))))))
      (lambda ()
        (when (and backup (not (eqv? backup 0))) (guard (e (#t #f)) (backup-finish backup)))
        (for-each (lambda (db) (when db (close-quietly db))) (list source target))))))

;; --- the race --------------------------------------------------------------------------------

;; race-rounds : Positive-Integer
;; The owner's opens and closes. The first mutant fails the row from 1, by
;; the closed connection its last call is made certain to land on; Valgrind
;; saw nothing at 1, 20 or 200.
(define race-rounds 20)

;; raced : String Positive-Integer -> (List Any Any Any Any Any Any)
;; The owner, this thread, opens PATH ROUNDS times: each connection
;; published, then closed, and marked closed, left published until the
;; next. The interrupter, a thread of its own, takes the published
;; connection and whether it was closed, under the board's mutex; calls
;; interrupt-database! on it outside the mutex; notes the call, and what
;; it answered but void, or what its turn raised; sleeps 1 microsecond
;; after every tenth call; and
;; goes on until told to stop,
;; or bound-ms have passed. The owner begins once the interrupter has made
;; a call, and tells it to stop once its rounds are done and a call has
;; landed on a closed connection, or answer-ms have passed. Answers the
;; owner's rounds, or what it raised; whether calls were made; whether one
;; landed on a closed connection; the first three answers but void; the interrupter's
;; end; and the counts after.
(define (raced path rounds)
  (let* ((m (make-mutex))
         (c (make-condition))
         (current #f)
         (closed? #f)
         (stop #f)
         (ended #f)
         (calls 0)
         (closed-calls 0)
         (others '())
         (by (add-duration (current-time 'time-monotonic) (duration bound-ms)))
         (past? (lambda () (time>=? (current-time 'time-monotonic) by)))
         (interrupter
          (fork-thread
           (lambda ()
             (let loop ((burst 0))
               (let ((next
                      ;; A raise in a call's turn, the bookkeeping's or the
                      ;; sleep's as much as the verb's, is an answer among
                      ;; the others, and the next turn follows.
                      (guard (e (#t (guard (x (#t #f))
                                      (with-mutex m
                                        (when (< (length others) 3)
                                          (set! others (cons (list 'a-turn-raised (what-raised e)) others)))
                                        (condition-broadcast c)))
                                    'again))
                        (if (or (with-mutex m stop) (past?))
                            'stop
                            (let* ((taken (with-mutex m (cons current closed?)))
                                   (verb (if (car taken) (interrupt! (car taken)) 'nothing-published)))
                              (with-mutex m
                                (set! calls (+ calls 1))
                                (when (cdr taken) (set! closed-calls (+ closed-calls 1)))
                                (unless (or (memq verb '(void nothing-published)) (>= (length others) 3))
                                  (set! others (cons verb others)))
                                (condition-broadcast c))
                              (when (= burst 9) (sleep one-microsecond))
                              'again)))))
                 (when (eq? next 'again) (loop (if (= burst 9) 0 (+ burst 1))))))
             (with-mutex m
               (set! ended #t)
               (condition-broadcast c)))))
         (ready (with-mutex m (await m c (lambda () (> calls 0)) answer-ms)))
         (owner
          (attempt
           (lambda ()
             (let loop ((i 0))
               (if (= i rounds)
                   (list 'rounds i)
                   (let ((db (open-database path)))
                     (with-mutex m (set! current db) (set! closed? #f))
                     (close-database! db)
                     (with-mutex m (set! closed? #t))
                     (loop (+ i 1))))))))
         (landed (with-mutex m (await m c (lambda () (> closed-calls 0)) answer-ms)))
         (end (with-mutex m
                (set! stop #t)
                (if (await m c (lambda () ended) bound-ms) 'the-interrupter-ended
                    'the-interrupter-did-not-end))))
    (when (eq? end 'the-interrupter-ended) (thread-join interrupter))
    (with-mutex m
      (display "    the race: ")
      (display calls)
      (display " interrupts, ")
      (display closed-calls)
      (display " on a closed connection, over ")
      (display rounds)
      (display " opens and closes")
      (newline))
    (list owner
          (if (and ready (> calls 0)) 'calls-made 'no-call-made)
          (if landed 'some-on-a-closed-connection 'none-on-a-closed-connection)
          (with-mutex m (reverse others))
          end
          (native-counts))))

(test-equal "the race: interrupts from one thread against opens and closes of a file on another; every interrupt answers void, some land on a closed connection, the interrupter ends, and nothing is counted"
  (list (list 'rounds race-rounds) 'calls-made 'some-on-a-closed-connection '() 'the-interrupter-ended
        zero-counts)
  (let ((path (string-append (or temp-dir "/nonexistent") "/race.db")))
    (raced path race-rounds)))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "interrupt-close")

(exit (suite-exit-status runner))
