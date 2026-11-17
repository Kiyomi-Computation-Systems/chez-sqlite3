#!r6rs
;;; Two connections to one WAL file under a busy timeout, each opened, used
;;; and closed on a thread of its own (ADR-0019, decisions 8 to 11, amended
;;; in M3 slice 5; ADR-0017, decision 2; ADR-0010; the M3 plan, sections 4.5
;;; and 5, slice 6; M3's research, concurrency B3 to B6, and slice-0 P3).
;;; Each connection opens with ((journal-mode . wal) (busy-timeout . 1500)),
;;; or 250 for the short wait, and says both as read back, ("wal" 1500).
;;;
;;;   waits out      BEGIN IMMEDIATE, under the other's BEGIN IMMEDIATE and
;;;                  write, waits out the 1500 ms timeout, at least 1000 ms
;;;                  and under 3000, or 2000 on a whole-second build, then
;;;                  raises &sqlite-busy, busy and busy,
;;;                  and leaves the waiter in autocommit (B3, B6)
;;;   the default    the same through with-transaction with no mode, so
;;;   waits out      BEGIN IMMEDIATE: it waits the timeout out once, raises
;;;                  &sqlite-busy from with-transaction, begins nothing, the
;;;                  depth 0, and never runs its body (ADR-0019, decision 8)
;;;   mid-wait       BEGIN IMMEDIATE as in waits out, the other committing
;;;                  500 ms into the wait: it succeeds after the commit and
;;;                  before its timeout's end, and sees the other's row (P3)
;;;   the upgrade    a deferred transaction reads, the other commits a write,
;;;                  and its own write raises &sqlite-busy, busy and
;;;                  busy-snapshot, at once, and again when tried again; the
;;;                  transaction stays open, reading its old snapshot; rolled
;;;                  back, a new transaction's write commits (B5)
;;;   the snapshot   a reader in a transaction reads the rows as they were at
;;;                  its first read, while the other commits a write, holds
;;;                  one open and commits it, each at once; ended, it reads
;;;                  them all (B4)
;;;   the default    with-transaction with no mode, so immediate, on both
;;;                  threads, each body reading then writing: the second
;;;                  waits for the first's commit, never reading inside it,
;;;                  and both commit. With 'deferred the same bodies both
;;;                  read, the first commits, and the second's write raises
;;;                  &sqlite-busy, busy-snapshot (ADR-0017, decision 2; Q5)
;;;   the grain      probe P4: BEGIN IMMEDIATE with a 250 ms timeout raises
;;;                  &sqlite-busy, busy and busy, under 500 ms, and the row
;;;                  prints whether the library sleeps in milliseconds or in
;;;                  whole seconds
;;;
;;; A wait is told from none by 1000 ms, and from a retry by twice what one
;;; wait of its 1500 ms timeout takes: 3000 ms on a build that sleeps in
;;; milliseconds; 2000 on one without nanosleep, which sleeps whole seconds,
;;; so waits 1000 of it (AGENTS.md; concurrency B3; ADR-0019, amended). The
;;; suite reads the grain before any row, the short wait's way, on one
;;; thread, and bounds the waits by it. A wait the other ends mid-wait is
;;; asserted only as before its timeout's end. The short wait asserts only
;;; what holds on either grain: busy, under twice its timeout, which a
;;; whole-second build answers at once and a millisecond one after about
;;; 250 ms (B3). Each timed wait prints its milliseconds for a reader of the
;;; run, CI's main lane among them, whose log is where P4 is read. Every wait
;;; SQLite times is a sleep in its busy handler, which under Valgrind lets
;;; the other threads run: slice 5's 1500 ms waits ran 1509 to 1526 ms there.
;;;
;;; No connection that waits on a lock holds a read of its own: each of its
;;; statements has finished before the wait (AGENTS.md; slice-0 P12).
;;;
;;; The threads. A row's two threads say what they have done on a board, and
;;; each waits up to long-ms for the other's word, raising, naming the word,
;;; when it never comes. Whatever a thread raises is its answer, the busy
;;; conditions the rows expect among them. This thread waits up to answer-ms
;;; for each answer, and one not given by then is unfinished, so a row fails
;;; by name and never hangs (AGENTS.md). The one wait meant to run out is the
;;; default row's: its first body waits window-ms for the second's read,
;;; which immediate never lets happen, from the second's word that it runs,
;;; so the window holds no wake-up of the second's. With 'deferred the second
;;; reads at once, a with-transaction's BEGIN and one query-row on a thread
;;; of its own, while the first waits on a condition. Each row's file is in a
;;; directory of its own, removed after it: a thread that dies on a raise
;;; runs the base exception handler, where make-process-temp-directory's
;;; hook removes the directory it made, so a directory the rows shared would
;;; fail every later row at its open (.plans/m3-slice-6-mutation-log.md).
;;;
;;; The loading procedures are reached through eval, under a guard. Every
;;; computation that can raise runs under a guard with a sentinel of its own,
;;; and no expected value is #f. Effects run in order, through let* and named
;;; lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) fork-thread thread-join make-mutex with-mutex make-condition
              condition-wait condition-broadcast make-time current-time time-difference
              add-duration time>=? sleep real-time)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-error-sql sqlite-busy? sqlite-closed?
              sqlite-wrong-thread?))

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

;; reach : (Listof Symbol) Symbol -> Procedure
(define (reach library name)
  (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
    (eval name (environment library))))

(define (public name) (reach '(chez-sqlite3) name))

(define open-database (public 'open-database))
(define close-database! (public 'close-database!))
(define execute! (public 'execute!))
(define query-row (public 'query-row))
(define in-transaction? (public 'in-transaction?))
(define with-transaction (public 'with-transaction))
(define sqlite-version (public 'sqlite-version))
(define database-depth (reach '(chez-sqlite3 private connection) 'database-depth))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
;; E as the rows compare it: an &sqlite-error by its who, codes and SQL, and
;; whether &sqlite-busy holds; &sqlite-closed and &sqlite-wrong-thread by
;; their who; an assertion violation by its who and irritants.
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (sqlite-error-sql e) (if (sqlite-busy? e) 'sqlite-busy 'not-sqlite-busy)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((sqlite-wrong-thread? e) (list 'wrong-thread (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

;; busy : Symbol String -> Any
;; What attempt answers for &sqlite-busy from execute! on SQL, its extended
;; code EXTENDED.
(define (busy extended sql)
  (list 'raised (list 'sqlite-error 'execute! 'busy extended sql 'sqlite-busy)))

(define (close-quietly db) (guard (e (#t #f)) (close-database! db)))

(define wal-1500 '((journal-mode . wal) (busy-timeout . 1500)))
(define wal-250 '((journal-mode . wal) (busy-timeout . 250)))

;; pragma : Database String -> Any
;; The first column of PRAGMA NAME's row on DB, by query-row, which finishes
;; its statement.
(define (pragma db name)
  (let ((row (query-row db (string-append "PRAGMA " name))))
    (if (vector? row) (vector-ref row 0) (list 'no-row row))))

;; premise : Database -> (List Any Any)
;; DB's journal mode and busy timeout as read back: ("wal" 1500) for wal-1500.
(define (premise db) (list (pragma db "journal_mode") (pragma db "busy_timeout")))

;; rows : Database -> Any
;; How many rows t holds as DB reads it: #(3) for a fresh file.
(define (rows db) (query-row db "select count(*) from t"))

;; mode-of : Database -> Any
;; autocommit or in-a-transaction, by in-transaction?, or what it raised.
(define (mode-of db)
  (guard (e (#t (list 'raised (what-raised e))))
    (if (in-transaction? db) 'in-a-transaction 'autocommit)))

;; depth-of : Database -> Any
;; How many with-transaction levels DB has open, by the connection's private
;; database-depth, as test-transaction-engine reads it, or what it raised.
(define (depth-of db)
  (guard (e (#t (list 'raised (what-raised e))))
    (database-depth db)))

;; connected : String Settings (Database -> A ...) -> A ...
;; PROC given a connection to PATH opened with SETTINGS on this thread,
;; closed after however PROC ends.
(define (connected path settings proc)
  (let ((db (open-database path settings)))
    (dynamic-wind
      (lambda () #f)
      (lambda () (proc db))
      (lambda () (close-quietly db)))))

;; wal-file : String String -> String
;; DIR/NAME, made fresh in WAL, holding t with three rows, its connection
;; closed. WAL stays in the file.
(define (wal-file dir name)
  (let ((path (string-append dir "/" name)))
    (connected path '((journal-mode . wal))
      (lambda (db)
        (execute! db "create table t (x)")
        (execute! db "insert into t values (1), (2), (3)")))
    path))

;; counted : String -> Any
;; The rows t holds at PATH, read by a fresh connection on this thread.
(define (counted path)
  (connected path '() rows))

;; grain-ms : -> Any
;; The milliseconds a BEGIN IMMEDIATE with a 250 ms busy timeout takes to
;; answer busy, under another connection's BEGIN IMMEDIATE and write on a
;; fresh WAL file, both on this thread: about 250 where the build sleeps in
;; milliseconds, 0 where it sleeps whole seconds (B3). Else what it
;; answered, or raised.
(define (grain-ms)
  (attempt
   (lambda ()
     (call-with-temp-directory
      (lambda (dir)
        (let ((path (wal-file dir "grain.db")))
          (connected path wal-1500
            (lambda (holder)
              (execute! holder "begin immediate")
              (execute! holder "insert into t values (4)")
              (let ((ms (connected path wal-250
                          (lambda (waiter)
                            (let* ((t0 (real-time))
                                   (r (attempt (lambda () (execute! waiter "begin immediate"))))
                                   (t1 (real-time)))
                              (if (equal? r (busy 'busy "begin immediate"))
                                  (- t1 t0)
                                  (list 'not-busy r)))))))
                (execute! holder "rollback")
                ms)))))))))

;; grain : (U 'milliseconds 'whole-seconds (List 'unread Any))
;; The build's busy-wait grain, read once, before any row: milliseconds from
;; 125 ms, half the timeout, as the grain row tells them apart.
(define grain
  (let ((ms (guard (e (#t (list 'raised (describe e)))) (grain-ms))))
    (cond ((not (integer? ms)) (list 'unread ms))
          ((>= ms 125) 'milliseconds)
          (else 'whole-seconds))))

;; retry-ms : Natural
;; Where a 1500 ms timeout's wait is too long: a retry waits at least 2000
;; ms on a whole-second build, and 3000 on any other; an unread grain takes
;; the looser bound, and its row fails.
(define retry-ms (if (eq? grain 'whole-seconds) 2000 3000))

;; how-long : Natural -> Symbol
;; MS as waited, at least 1000 and under retry-ms; too-long, from retry-ms;
;; or at-once. A busy timeout of 1500 ms waits 1000 of it on a build without
;; nanosleep and 1500 on one with it; a retry in Scheme waits it out twice,
;; at least 2000 or 3000, which is too long.
(define (how-long ms) (cond ((>= ms retry-ms) 'too-long) ((>= ms 1000) 'waited) (else 'at-once)))

;; timed : (-> Any) -> Natural
;; THUNK run; the milliseconds it took. What it raises is raised.
(define (timed thunk)
  (let* ((t0 (real-time))
         (done (thunk))
         (t1 (real-time)))
    (- t1 t0)))

;; note-time! : String Any -> Void
;; A timed case's milliseconds, printed for a reader of the run.
(define (note-time! label ms)
  (display "    timed: ")
  (display label)
  (display ": ")
  (display ms)
  (display " ms")
  (newline))

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

;; A thread's wait for the other's word, and this thread's for an answer:
;; each elapses only when something is wrong.
(define long-ms 10000)
(define answer-ms 30000)
;; mid-wait: the holder commits this long after it is told the wait begins.
(define release-ms 500)
;; the default row: the first body's wait for the second's read.
(define window-ms 500)

;; start-thread : (-> Any) -> (Natural -> Any)
;; THUNK run on a thread of its own. Its answer, or (raised WHAT) for what it
;; raised, by what-raised, is the thread's answer. Answers a procedure that
;; waits up to MS milliseconds for that answer, joins the thread once it has
;; answered and answers it, or answers unfinished, joining nothing.
(define (start-thread thunk)
  (let* ((m (make-mutex))
         (c (make-condition))
         (done #f)
         (answer 'unfinished)
         (thread (fork-thread
                  (lambda ()
                    (let ((a (guard (e (#t (list 'raised (what-raised e)))) (thunk))))
                      (with-mutex m
                        (set! answer a)
                        (set! done #t)
                        (condition-broadcast c)))))))
    (lambda (ms)
      (if (with-mutex m (await m c (lambda () done) ms))
          (begin (thread-join thread) (with-mutex m answer))
          'unfinished))))

;; A board is where a row's threads say what they have done: a mutex, a
;; condition, and each word said, with its value, the newest first.

;; make-board : -> Board
(define (make-board) (vector (make-mutex) (make-condition) '()))

;; say! : Board Symbol Any -> Void
;; WORD said on BOARD, with VALUE.
(define (say! board word value)
  (with-mutex (vector-ref board 0)
    (vector-set! board 2 (cons (cons word value) (vector-ref board 2)))
    (condition-broadcast (vector-ref board 1))))

;; said-within? : Board Symbol Natural -> Boolean
;; Whether WORD is said on BOARD, waiting up to MS milliseconds for it.
(define (said-within? board word ms)
  (let ((m (vector-ref board 0)))
    (with-mutex m
      (await m (vector-ref board 1) (lambda () (and (assq word (vector-ref board 2)) #t)) ms))))

;; word : Board Symbol -> Any
;; WORD's value on BOARD, or not-said.
(define (word board name)
  (with-mutex (vector-ref board 0)
    (let ((said (assq name (vector-ref board 2))))
      (if said (cdr said) 'not-said))))

;; hear : Board Symbol -> Any
;; WORD's value once it is said on BOARD, waiting up to long-ms; raises,
;; naming WORD, when it is not said by then.
(define (hear board name)
  (if (said-within? board name long-ms)
      (word board name)
      (error 'hear "never said" name)))

;; --- the rows' threads ---------------------------------------------------------------------

;; waited-out : String Settings (Database Board -> Any) -> (List Any Any Any Any Any)
;; The holder, on a thread of its own, opens PATH, begins immediate, writes,
;; and says held; it waits for the waiter's word, then commits. The waiter,
;; on another, told held, opens PATH with SETTINGS, says its premise, and
;; runs CALL on its connection and the board, whose raise is its answer; as
;; the call unwinds, it says the milliseconds it took, its mode and its
;; with-transaction depth. Answers the waiter's answer, its premise, (MS MODE
;; DEPTH), the holder's answer, and the word body-ran, which CALL may say.
(define (waited-out path settings call)
  (let* ((b (make-board))
         (holder (start-thread
                  (lambda ()
                    (connected path wal-1500
                      (lambda (db)
                        (let ((p (premise db)))
                          (execute! db "begin immediate")
                          (execute! db "insert into t values (4)")
                          (say! b 'held #t)
                          (let ((told (said-within? b 'waited long-ms)))
                            (execute! db "commit")
                            (list p (if told 'committed 'committed-untold)))))))))
         (waiter (start-thread
                  (lambda ()
                    (hear b 'held)
                    (connected path settings
                      (lambda (db)
                        (say! b 'premise (premise db))
                        (let ((t0 (real-time)))
                          (dynamic-wind
                            (lambda () #f)
                            (lambda () (call db b))
                            (lambda ()
                              (say! b 'waited (list (- (real-time) t0) (mode-of db) (depth-of db)))))))))))
         (w (waiter answer-ms))
         (h (holder answer-ms)))
    (list w (word b 'premise) (word b 'waited) h (word b 'body-ran))))

;; begin-immediate : Database Board -> Any
;; BEGIN IMMEDIATE through execute!.
(define (begin-immediate db b) (execute! db "begin immediate") 'began)

;; default-transaction : Database Board -> Any
;; with-transaction with no mode, its body saying body-ran.
(define (default-transaction db b)
  (with-transaction db (lambda () (say! b 'body-ran #t) 'ran)))

;; ended-mid-wait : String -> (List Any Any Any)
;; The holder, on a thread of its own, opens PATH, begins immediate, writes,
;; and says held. The waiter, on another, told held, opens PATH, says it
;; begins, and runs BEGIN IMMEDIATE; then counts the rows and commits. The
;; holder, told, sleeps release-ms, says the time, and commits. Answers the
;; waiter's answer, (PREMISE began T0 T1 ROWS), T0 and T1 the real time
;; around its BEGIN IMMEDIATE; the holder's; and the time it said.
(define (ended-mid-wait path)
  (let* ((b (make-board))
         (holder (start-thread
                  (lambda ()
                    (connected path wal-1500
                      (lambda (db)
                        (let ((p (premise db)))
                          (execute! db "begin immediate")
                          (execute! db "insert into t values (4)")
                          (say! b 'held #t)
                          (hear b 'begins)
                          (sleep (duration release-ms))
                          (say! b 'committing (real-time))
                          (execute! db "commit")
                          (list p 'committed)))))))
         (waiter (start-thread
                  (lambda ()
                    (hear b 'held)
                    (connected path wal-1500
                      (lambda (db)
                        (let* ((p (premise db))
                               (t0 (begin (say! b 'begins #t) (real-time)))
                               (began (begin (execute! db "begin immediate") 'began))
                               (t1 (real-time))
                               (seen (rows db)))
                          (execute! db "commit")
                          (list p began t0 t1 seen)))))))
         (w (waiter answer-ms))
         (h (holder answer-ms)))
    (list w h (word b 'committing))))

;; upgraded : String -> (List Any Any)
;; The reader, on a thread of its own, opens PATH, begins a deferred
;; transaction, counts the rows, and says read. The other, on another, told
;; read, writes a row in autocommit and says so. The reader, told, writes,
;; timed, then writes again; then reads its mode and the rows, rolls back,
;; and runs a new transaction that writes first, and counts again. Answers
;; the reader's answer, (PREMISE ROWS WRITE MS AGAIN MODE ROWS COMMITTED
;; ROWS), and the other's.
(define (upgraded path)
  (let* ((b (make-board))
         (other (start-thread
                 (lambda ()
                   (connected path wal-1500
                     (lambda (db)
                       (let ((p (premise db)))
                         (hear b 'read)
                         (execute! db "insert into t values (4)")
                         (say! b 'written #t)
                         (list p 'committed)))))))
         (reader (start-thread
                  (lambda ()
                    (connected path wal-1500
                      (lambda (db)
                        (let* ((p (premise db))
                               (before (begin (execute! db "begin") (rows db)))
                               (heard (begin (say! b 'read #t) (hear b 'written)))
                               (t0 (real-time))
                               (wrote (attempt (lambda () (execute! db "insert into t values (5)"))))
                               (ms (- (real-time) t0))
                               (again (attempt (lambda () (execute! db "insert into t values (5)"))))
                               (mode (mode-of db))
                               (still (rows db))
                               (fresh (begin (execute! db "rollback")
                                             (execute! db "begin")
                                             (execute! db "insert into t values (5)")
                                             (execute! db "commit")
                                             'committed))
                               (after (rows db)))
                          (list p before wrote ms again mode still fresh after)))))))
         (r (reader answer-ms))
         (o (other answer-ms)))
    (list r o)))

;; kept-snapshot : String -> (List Any Any)
;; The reader, on a thread of its own, opens PATH, begins, counts the rows,
;; and says reading. The writer, on another, then writes in autocommit; then
;; begins immediate and writes; then commits; each timed, each said, and
;; after each the reader, told, counts again. The reader then reads its
;; mode, commits, and counts. Answers the reader's answer, (PREMISE ROWS
;; ROWS ROWS ROWS MODE ROWS), and the writer's, (PREMISE MS MS MS ROWS).
(define (kept-snapshot path)
  (let* ((b (make-board))
         (reader (start-thread
                  (lambda ()
                    (connected path wal-1500
                      (lambda (db)
                        (let* ((p (premise db))
                               (first (begin (execute! db "begin") (rows db)))
                               (after-autocommit (begin (say! b 'reading #t)
                                                        (hear b 'autocommitted)
                                                        (rows db)))
                               (beside-open (begin (say! b 'read-1 #t)
                                                   (hear b 'writing)
                                                   (rows db)))
                               (after-commit (begin (say! b 'read-2 #t)
                                                    (hear b 'committed)
                                                    (rows db)))
                               (mode (mode-of db))
                               (last (begin (execute! db "commit") (rows db))))
                          (list p first after-autocommit beside-open after-commit mode last)))))))
         (writer (start-thread
                  (lambda ()
                    (connected path wal-1500
                      (lambda (db)
                        (let* ((p (premise db))
                               (a (begin (hear b 'reading)
                                         (timed (lambda () (execute! db "insert into t values (4)")))))
                               (c (begin (say! b 'autocommitted #t)
                                         (hear b 'read-1)
                                         (timed (lambda ()
                                                  (execute! db "begin immediate")
                                                  (execute! db "insert into t values (5)")))))
                               (d (begin (say! b 'writing #t)
                                         (hear b 'read-2)
                                         (timed (lambda () (execute! db "commit"))))))
                          (say! b 'committed #t)
                          (list p a c d (rows db))))))))
         (r (reader answer-ms))
         (w (writer answer-ms)))
    (list r w)))

;; contended : String (Database (-> Any) -> Any) -> (List Any Any Any)
;; Two threads, first and second, each open PATH and say so, and each runs
;; RUN, with-transaction in some mode, on a body that counts the rows, says
;; it read, and writes a row. The second, once told the first read, says it
;; runs, and runs RUN; its body, once its read is said, waits for the first's
;; RUN to end, then writes, answering the rows. The first's body, once its
;; read is said, waits for the second to say it runs, then up to window-ms
;; for the second's read, then writes, answering the rows and whether it saw
;; that read. The window starts where the second says it acts, so it holds
;; no thread's wake-up: a second woken late, its window started on the
;; first's read, met a deferred default only once the first had committed,
;; and read and wrote as immediate's does (.plans/traps.md, M3 slice 1's
;; review). Each says its premise, and its mode as its RUN unwinds. Answers
;; each thread's answer; each premise and mode; and the milliseconds from
;; the second's RUN to its read.
(define (contended path run)
  (let* ((b (make-board))
         (first (start-thread
                 (lambda ()
                   (connected path wal-1500
                     (lambda (db)
                       (say! b 'first-premise (premise db))
                       (hear b 'second-open)
                       (dynamic-wind
                         (lambda () #f)
                         (lambda ()
                           (run db (lambda ()
                                     (let* ((n (rows db))
                                            (told (begin (say! b 'first-read #t)
                                                         (hear b 'second-runs)))
                                            (saw (if (said-within? b 'second-read window-ms)
                                                     'saw-the-second-read
                                                     'no-second-read)))
                                       (execute! db "insert into t values ('first')")
                                       (list n saw)))))
                         (lambda () (say! b 'first-ended (mode-of db)))))))))
         (second (start-thread
                  (lambda ()
                    (connected path wal-1500
                      (lambda (db)
                        (say! b 'second-premise (premise db))
                        (say! b 'second-open #t)
                        (hear b 'first-read)
                        (say! b 'second-runs #t)
                        (let ((t0 (real-time)))
                          (dynamic-wind
                            (lambda () #f)
                            (lambda ()
                              (run db (lambda ()
                                        (let ((n (rows db)))
                                          (say! b 'second-read (- (real-time) t0))
                                          (hear b 'first-ended)
                                          (execute! db "insert into t values ('second')")
                                          n))))
                            (lambda () (say! b 'second-ended (mode-of db))))))))))
         (f (first answer-ms))
         (s (second answer-ms)))
    (list f s
          (list (word b 'first-premise) (word b 'first-ended)
                (word b 'second-premise) (word b 'second-ended))
          (word b 'second-read))))

(define (default-run db body) (with-transaction db body))
(define (deferred-run db body) (with-transaction db 'deferred body))

;; the-waited : Any -> (List Any Any Any)
;; (MS MODE DEPTH) as waited-out said it, or (not-said not-said not-said).
(define (the-waited w)
  (if (and (list? w) (= (length w) 3)) w (list w w w)))

;; in-dir : (String -> Any) -> Any
;; PROC given a fresh directory, by call-with-temp-directory, under attempt:
;; one a row, so a thread that dies takes no other row's file with it (the
;; header).
(define (in-dir proc)
  (attempt (lambda () (call-with-temp-directory proc))))

(test-begin "contention")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-equal "the busy wait's grain is read before any row, on one thread: a 250 ms busy timeout under another's BEGIN IMMEDIATE and write answers busy after 125 ms or more, milliseconds, or before, whole seconds; a 1500 ms timeout's wait is too long from 3000 ms on the first, and from 2000 on the second"
  'read
  (begin
    (display "    the grain: ")
    (write grain)
    (display ", a wait too long from ")
    (display retry-ms)
    (display " ms")
    (newline)
    (cond ((and (eq? grain 'milliseconds) (= retry-ms 3000)) 'read)
          ((and (eq? grain 'whole-seconds) (= retry-ms 2000)) 'read)
          (else (list grain retry-ms)))))

;; --- waits out -----------------------------------------------------------------------------

(test-equal "BEGIN IMMEDIATE under the other's BEGIN IMMEDIATE and write waits out the 1500 ms busy timeout, at least 1000 ms and under 3000, or 2000 on a whole-second build, then raises &sqlite-busy, busy and busy, from execute!; the waiter is left in autocommit, and only the holder's row is committed"
  (list (busy 'busy "begin immediate") '("wal" 1500) 'waited 'autocommit
        '(("wal" 1500) committed) '#(4) zero-counts)
  (in-dir
   (lambda (dir)
     (let* ((path (wal-file dir "waits-out.db"))
            (r (waited-out path wal-1500 begin-immediate))
            (waited (the-waited (caddr r))))
       (note-time! "BEGIN IMMEDIATE, waited out" (car waited))
       (list (car r) (cadr r) (if (integer? (car waited)) (how-long (car waited)) (car waited))
             (cadr waited) (cadddr r) (counted path) (native-counts))))))

;; --- the default waits out -----------------------------------------------------------------

(test-equal "with-transaction with no mode, so BEGIN IMMEDIATE, under the other's BEGIN IMMEDIATE and write, waits out the 1500 ms busy timeout once, at least 1000 ms and under 3000, or 2000 on a whole-second build, then raises &sqlite-busy, busy and busy, from with-transaction, naming its BEGIN IMMEDIATE; nothing is begun, in-transaction? false and the depth 0, and its body never runs"
  (list (list 'raised (list 'sqlite-error 'with-transaction 'busy 'busy "BEGIN IMMEDIATE" 'sqlite-busy))
        '("wal" 1500) 'waited 'autocommit 0 'not-said
        '(("wal" 1500) committed) '#(4) zero-counts)
  (in-dir
   (lambda (dir)
     (let* ((path (wal-file dir "default-waits-out.db"))
            (r (waited-out path wal-1500 default-transaction))
            (waited (the-waited (caddr r))))
       (note-time! "with-transaction, waited out" (car waited))
       (list (car r) (cadr r) (if (integer? (car waited)) (how-long (car waited)) (car waited))
             (cadr waited) (caddr waited) (list-ref r 4) (cadddr r) (counted path)
             (native-counts))))))

;; --- mid-wait ------------------------------------------------------------------------------

(test-equal "BEGIN IMMEDIATE under the other's BEGIN IMMEDIATE and write, the other committing 500 ms into the wait: it succeeds after the commit and before its timeout's end, and the waiter then sees the other's row"
  (list (list '("wal" 1500) 'began 'after-the-commit 'before-the-timeout '#(4))
        '(("wal" 1500) committed) '#(4) zero-counts)
  (in-dir
   (lambda (dir)
     (let* ((path (wal-file dir "mid-wait.db"))
            (r (ended-mid-wait path))
            (w (car r))
            (committing (caddr r)))
       (if (not (and (list? w) (= (length w) 5) (integer? committing)))
           (list w (cadr r) committing)
           (let ((t0 (caddr w)) (t1 (cadddr w)))
             (note-time! "BEGIN IMMEDIATE, ended mid-wait" (- t1 t0))
             (note-time! "BEGIN IMMEDIATE, from the other's commit to its return" (- t1 committing))
             (list (list (car w) (cadr w)
                         (if (>= t1 committing) 'after-the-commit 'before-the-commit)
                         (if (< (- t1 t0) 1500) 'before-the-timeout 'not-before-the-timeout)
                         (list-ref w 4))
                   (cadr r) (counted path) (native-counts))))))))

;; --- the upgrade ---------------------------------------------------------------------------

(test-equal "a deferred transaction that has read, after the other commits a write: its own write raises &sqlite-busy, busy and busy-snapshot, at once under its 1500 ms busy timeout, and again when tried again; the transaction stays open and reads its old snapshot; rolled back, a new transaction's write commits"
  (list (list '("wal" 1500) '#(3) (busy 'busy-snapshot "insert into t values (5)") 'at-once
              (busy 'busy-snapshot "insert into t values (5)") 'in-a-transaction '#(3)
              'committed '#(5))
        '(("wal" 1500) committed) '#(5) zero-counts)
  (in-dir
   (lambda (dir)
     (let* ((path (wal-file dir "upgrade.db"))
            (r (upgraded path))
            (w (car r)))
       (if (not (and (list? w) (= (length w) 9) (integer? (list-ref w 3))))
           (list w (cadr r))
           (begin
             (note-time! "the deferred upgrade, after the other's commit" (list-ref w 3))
             (list (append (list (car w) (cadr w) (caddr w) (how-long (list-ref w 3)))
                           (list-tail w 4))
                   (cadr r) (counted path) (native-counts))))))))

;; --- the snapshot --------------------------------------------------------------------------

(test-equal "a reader in a transaction reads the three rows it first read while the other connection commits a write in autocommit, holds one open in BEGIN IMMEDIATE, and commits it, each at once; once it has committed, it reads all five"
  (list (list '("wal" 1500) '#(3) '#(3) '#(3) '#(3) 'in-a-transaction '#(5))
        (list '("wal" 1500) 'at-once 'at-once 'at-once '#(5))
        '#(5) zero-counts)
  (in-dir
   (lambda (dir)
     (let* ((path (wal-file dir "snapshot.db"))
            (r (kept-snapshot path))
            (w (cadr r)))
       (if (not (and (list? w) (= (length w) 5) (for-all integer? (list (cadr w) (caddr w) (cadddr w)))))
           (list (car r) w)
           (begin
             (note-time! "the writer's autocommit insert, beside the read" (cadr w))
             (note-time! "the writer's BEGIN IMMEDIATE and insert, beside the read" (caddr w))
             (note-time! "the writer's COMMIT, beside the read" (cadddr w))
             (list (car r)
                   (list (car w) (how-long (cadr w)) (how-long (caddr w)) (how-long (cadddr w))
                         (list-ref w 4))
                   (counted path) (native-counts))))))))

;; --- the default ---------------------------------------------------------------------------

(test-equal "with-transaction's default mode, immediate, under contention: two threads each run a body that reads then writes; the second's BEGIN waits for the first's commit, so the first never sees the second read, the second reads the first's row, and both commit; with 'deferred the same bodies both read three rows, the first commits, and the second's write raises &sqlite-busy, busy-snapshot, its transaction rolled back"
  (list (list '(#(3) no-second-read) '#(4)
              '(("wal" 1500) autocommit ("wal" 1500) autocommit)
              '#(5))
        (list '(#(3) saw-the-second-read) (busy 'busy-snapshot "insert into t values ('second')")
              '(("wal" 1500) autocommit ("wal" 1500) autocommit)
              '#(4))
        zero-counts)
  (in-dir
   (lambda (dir)
     (let* ((default-path (wal-file dir "default.db"))
            (d (contended default-path default-run))
            (d-rows (counted default-path))
            (deferred-path (wal-file dir "deferred.db"))
            (e (contended deferred-path deferred-run))
            (e-rows (counted deferred-path)))
       (note-time! "with-transaction, immediate: the second's call to its first read" (cadddr d))
       (note-time! "with-transaction, deferred: the second's call to its first read" (cadddr e))
       (list (list (car d) (cadr d) (caddr d) d-rows)
             (list (car e) (cadr e) (caddr e) e-rows)
             (native-counts))))))

;; --- the grain -----------------------------------------------------------------------------

(test-equal "probe P4, the busy wait's grain: BEGIN IMMEDIATE under the other's BEGIN IMMEDIATE and write, with a 250 ms busy timeout, raises &sqlite-busy, busy and busy, under 500 ms, twice its timeout, on either grain; the waiter is left in autocommit"
  (list (busy 'busy "begin immediate") '("wal" 250) 'under-twice-the-timeout 'autocommit
        '(("wal" 1500) committed) '#(4) zero-counts)
  (in-dir
   (lambda (dir)
     (let* ((path (wal-file dir "grain.db"))
            (r (waited-out path wal-250 begin-immediate))
            (waited (the-waited (caddr r)))
            (ms (car waited)))
       (note-time! "BEGIN IMMEDIATE, a 250 ms timeout waited out" ms)
       (when (integer? ms)
         (display "    P4: SQLite ")
         (display (guard (e (#t "(unread)")) (sqlite-version)))
         (display " sleeps in ")
         (display (if (>= ms 125) "milliseconds" "whole seconds"))
         (display ": a 250 ms busy timeout answered busy after ")
         (display ms)
         (display " ms")
         (newline))
       (list (car r) (cadr r)
             (cond ((not (integer? ms)) ms)
                   ((< ms 500) 'under-twice-the-timeout)
                   (else 'not-under-twice-the-timeout))
             (cadr waited) (cadddr r) (counted path) (native-counts))))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "contention")

(exit (suite-exit-status runner))
