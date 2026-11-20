#!r6rs
;;; interrupt-database!, the one verb any thread may call, and the close's
;;; exclusion of it, through the real connection record (ADR-0019; ADR-0010
;;; and ADR-0012). The record holds the latch: the open sets its flag, the
;;; close clears it before it finalizes anything, and a close that leaves
;;; the connection open sets it again. tests/test-interrupt.sps holds the
;;; latch itself on stand-ins.
;;;
;;; The probe. An interrupt that reaches sqlite3_interrupt while no statement
;;; runs is lost for what follows, but leaves sqlite3_is_interrupted reading 1
;;; until the next statement starts. This suite binds sqlite3_is_interrupted
;;; itself, after the load, as the library never does (ADR-0019): it reads
;;; clear before an interrupt, and set after one that reached
;;; sqlite3_interrupt. So each row reads whether the verb called SQLite, on
;;; one thread, with no statement running and nothing timed.
;;;
;;;   the verb       a value that is no database, from this thread and
;;;                  another: an assertion violation from the verb; from
;;;                  another thread, no owner check: the verb answers, and
;;;                  the probe reads set; on a closed connection, from either
;;;                  thread, it does nothing and raises nothing, after a second
;;;                  close too, and after a close that closed and raised a
;;;                  finalize's failure
;;;   the open       open-database, with settings and without, and
;;;                  call-with-database each leave the connection
;;;                  interruptible
;;;   the close      clears the flag before its first finalize: a tracked
;;;                  entry of this suite's own, the oldest, so the first the
;;;                  close finalizes, calls the verb from inside the close,
;;;                  and the probe there reads clear
;;;   left open      a close refused for an untracked statement, and one
;;;                  where sqlite3_close itself answers busy beside an
;;;                  unfinished backup, each leave the flag set again: after
;;;                  either, the verb reaches SQLite. The library binds no
;;;                  backup; this suite binds sqlite3_backup_init and
;;;                  sqlite3_backup_finish, as tests/test-connection.sps does
;;;   the others     the close of a connection whose setting failed,
;;;                  reached through applied-settings!, and
;;;                  call-with-database's close: each clears the flag inside,
;;;                  and each that is left open sets it again
;;;   engines        the call inside the latch: an interrupt run in an engine,
;;;                  the connection closed at its first expiry, then the
;;;                  remainder resumed, at every fuel from 1 until it
;;;                  completes unexpired. Through interrupt-database/with, the
;;;                  record's procedure that takes the foreign call, a
;;;                  stand-in is never called after the close; through
;;;                  interrupt-database!, no trial raises, and under make
;;;                  test-memory Valgrind reads every call it makes to C
;;;   two threads    a stand-in in flight on another thread, through the
;;;                  record: the close's work starts only once it has ended
;;;   the shut       with-transaction's ROLLBACK, and the ROLLBACK TO and
;;;                  RELEASE of its failure path, drop an interrupt sent as
;;;                  each starts, from SQLite's statement trace; its COMMIT
;;;                  and the RELEASE that commits do not, and are rolled back
;;;                  under the shut; the flag is put back after; and an
;;;                  interrupt sent before the shut, beside a held row, still
;;;                  stops the ROLLBACK
;;;
;;; tests/test-interrupt-reach.sps holds what the verb reaches, and
;;; tests/test-interrupt-close.sps a running step after a failed close and the
;;; race under the gate.
;;;
;;; The engine rows run with collect-trip-bytes at a gigabyte, and no low
;;; pass. The gigabyte is for coverage: no collect request falls in a sweep,
;;; so each fuel stops the call at one point of its code, and the sweep passes
;;; every point it has. A low pass is what a call that holds a claim needs,
;;; since a request due inside a section costs the engine ticks at the
;;; section's exit, and a claim advanced just after its section is split from
;;; it only there. This verb holds no claim: the latch's one section reads the
;;; flag and the handle and makes the call, and nothing follows that section
;;; but the verb's return, so a remainder taken at its exit does nothing more
;;; when resumed, once or twice.
;;;
;;; A thread this suite forks answers whatever it raises, and every wait for
;;; it is bounded. The loading procedures are reached through eval, under a
;;; guard, so a refused library or a missing name fails rows by name. Every
;;; computation that can raise runs under a guard with a sentinel of its own;
;;; no expected value is #f. Effects run in order, through let* and named
;;; lets, never map.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure fork-thread thread-join make-mutex with-mutex
              make-condition condition-wait condition-broadcast make-time current-time
              time-difference add-duration time>=? make-engine collect collect-trip-bytes
              collections parameterize foreign-callable foreign-callable-entry-point
              lock-object unlock-object)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-closed? sqlite-wrong-thread?))

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

;; --- reached through eval -------------------------------------------------------------

;; public-load : (U 'loaded (List 'raised String))
(define public-load
  (guard (e (#t (list 'raised (describe e))))
    (eval '(sqlite-version) (environment '(chez-sqlite3)))
    'loaded))

;; reach : (Listof Symbol) Symbol -> Procedure
;; NAME's procedure in LIBRARY; when it cannot be reached, one that raises
;; that, naming NAME, every time it is called.
(define (reach library name)
  (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
    (eval name (environment library))))

(define (public name) (reach '(chez-sqlite3) name))

(define interrupt-database! (public 'interrupt-database!))
(define open-database (public 'open-database))
(define close-database! (public 'close-database!))
(define call-with-database (public 'call-with-database))
(define prepare-statement (public 'prepare-statement))
(define finalize-statement! (public 'finalize-statement!))
(define step! (public 'step!))
(define query-row (public 'query-row))
(define execute! (public 'execute!))
(define with-transaction (public 'with-transaction))
(define in-transaction? (public 'in-transaction?))
(define reset! (public 'reset!))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define interrupt-database/with (reach '(chez-sqlite3 private connection) 'interrupt-database/with))
(define track-statement! (reach '(chez-sqlite3 private connection) 'track-statement!))
(define applied-settings! (reach '(chez-sqlite3 private open) 'applied-settings!))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-out-pointer (reach '(chez-sqlite3 private native) 'call-with-out-pointer))
(define c-string->string (reach '(chez-sqlite3 private native) 'c-string->string))

;; --- bindings made here, after the load ------------------------------------------------
;; foreign-procedure resolves its entry when it is evaluated, so each is made
;; once the load above has run; one that cannot be made raises when called.

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_is_interrupted(sqlite3*), from 3.41.0, so at the floor
(define is-interrupted (bound 'sqlite3_is_interrupted (foreign-procedure "sqlite3_is_interrupted" (uptr) int)))
;; int sqlite3_prepare_v2(sqlite3*, const char *zSql, int nByte, sqlite3_stmt **, const char **pzTail)
(define prepare-v2 (bound 'sqlite3_prepare_v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int)))
;; int sqlite3_finalize(sqlite3_stmt*)
(define finalize (bound 'sqlite3_finalize (foreign-procedure "sqlite3_finalize" (uptr) int)))
;; sqlite3_backup *sqlite3_backup_init(sqlite3 *pDest, const char *zDestName,
;;                                     sqlite3 *pSource, const char *zSourceName)
(define backup-init (bound 'sqlite3_backup_init (foreign-procedure "sqlite3_backup_init" (uptr uptr uptr uptr) uptr)))
;; int sqlite3_backup_finish(sqlite3_backup*)
(define backup-finish (bound 'sqlite3_backup_finish (foreign-procedure "sqlite3_backup_finish" (uptr) int)))
;; int sqlite3_trace_v2(sqlite3*, unsigned uMask,
;;                      int (*xCallback)(unsigned, void *pCtx, void *P, void *X), void *pCtx),
;; from 3.14.0, so at the floor
(define trace-v2 (bound 'sqlite3_trace_v2 (foreign-procedure "sqlite3_trace_v2" (uptr unsigned-32 uptr uptr) int)))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

;; counts-with : (Listof (Pairof Symbol Integer)) -> (Listof (Pairof Symbol Integer))
(define (counts-with changes)
  (map (lambda (entry) (cond ((assq (car entry) changes) => (lambda (c) c)) (else entry)))
       zero-counts))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
;; E as the rows compare it: an assertion violation by its who and
;; irritants; an &sqlite-error by its who and codes; &sqlite-closed and
;; &sqlite-wrong-thread by their who.
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((sqlite-wrong-thread? e) (list 'wrong-thread (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

;; attempt : (-> Any) -> Any
;; THUNK's answer, or (raised WHAT) for what it raised.
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

;; answered : (-> Any) -> Any
;; What THUNK answered, by attempt, the void object as void: what the verb
;; answers, Void (ADR-0019).
(define (answered thunk)
  (let ((r (attempt thunk)))
    (if (eq? r (if #f #f)) 'void (list 'answered r))))

;; interrupt! : Any -> Any
;; interrupt-database! called on DB, by answered.
(define (interrupt! db) (answered (lambda () (interrupt-database! db))))

;; with-handle : Database (Positive-Integer -> A) -> A
(define (with-handle db proc) (call-with-open-handle 'test-interrupt-database db proc))

;; flag-of : Positive-Integer -> Symbol
;; sqlite3_is_interrupted on HANDLE: set for 1, clear for 0.
(define (flag-of handle)
  (let ((n (is-interrupted handle)))
    (cond ((eqv? n 1) 'set) ((eqv? n 0) 'clear) (else (list 'neither n)))))

;; flag : Database -> Any
;; The probe on DB, through its handle, by attempt.
(define (flag db) (attempt (lambda () (with-handle db flag-of))))

;; still-open : Database -> Any
;; open-and-counted when DB's handle can be had; else what refused it.
(define (still-open db) (attempt (lambda () (with-handle db (lambda (h) 'open)))))

;; prepare! : Database String -> Positive-Integer
;; A statement of SQL on DB, made here with the raw sqlite3_prepare_v2, so the
;; connection does not track it.
(define (prepare! db sql)
  (with-handle db
    (lambda (h)
      (call-with-c-string 'test-interrupt-database sql
        (lambda (text)
          (let-values (((rc statement)
                        (call-with-out-pointer 'test-interrupt-database
                          (lambda (slot) (prepare-v2 h text -1 slot 0)))))
            (if (and (eqv? rc 0) (not (eqv? statement 0)))
                statement
                (error 'prepare! "sqlite3_prepare_v2 did not answer a statement" rc))))))))

;; close-quietly : Any -> Void
(define (close-quietly db) (guard (e (#t #f)) (close-database! db)))

;; probed! : Database -> (-> Any)
;; An entry of this suite's own tracked by DB, with a finalize that, called
;; inside the close's critical section with DB's handle, reads the probe,
;; calls interrupt-database! on DB, reads the probe again, and answers
;; finalized, raising nothing. Tracked when DB tracks nothing else, it is
;; the oldest, so the first the close finalizes (ADR-0014).
;; Answers a reader of what the finalize saw, (BEFORE VERB AFTER), or
;; not-finalized when it was never called.
(define (probed! db)
  (let ((seen 'not-finalized))
    (track-statement! db (list 'this-suites-entry)
                      (lambda (handle)
                        (let* ((before (guard (e (#t (list 'raised (describe e)))) (flag-of handle)))
                               (verb (interrupt! db))
                               (after (guard (e (#t (list 'raised (describe e)))) (flag-of handle))))
                          (set! seen (list before verb after))
                          'finalized)))
    (lambda () seen)))

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

;; on-another-thread : (-> Any) -> Any
;; THUNK run on a thread of its own: its answer, or (raised TEXT) for what
;; it raised, which is the thread's answer; unfinished when it has not
;; answered within answer-ms, joining nothing.
(define answer-ms 30000)
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

;; start-thread : (-> Any) -> (Natural -> Any)
;; THUNK run on a thread of its own: its answer, or (raised TEXT) for what
;; it raised, is the thread's answer. Answers a procedure that waits up to
;; MS milliseconds for that answer, joins the thread once it has answered
;; and answers it, or answers unfinished, joining nothing.
(define (start-thread thunk)
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
    (lambda (ms)
      (if (with-mutex m (await m c (lambda () done) ms))
          (begin (thread-join thread) (with-mutex m answer))
          'unfinished))))

(define temp-dir (guard (e (#t #f)) (make-process-temp-directory)))
(define case-number 0)
;; fresh-path : -> String
(define (fresh-path)
  (set! case-number (+ case-number 1))
  (string-append (or temp-dir "/nonexistent") "/case-" (number->string case-number) ".db"))

(test-begin "interrupt-database")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-assert "a temporary directory for the suite's databases"
  (string? temp-dir))

;; --- the verb ------------------------------------------------------------------------------

(test-equal "interrupt-database! refuses what is no database, by its rule and shown-value: a symbol, a number, #f, a string by its kind, a statement by its kind; and from another thread the same, before anything else"
  '((raised (assertion-violation interrupt-database! (not-a-database x)))
    (raised (assertion-violation interrupt-database! (not-a-database 42)))
    (raised (assertion-violation interrupt-database! (not-a-database #f)))
    (raised (assertion-violation interrupt-database! (not-a-database (kind string))))
    (raised (assertion-violation interrupt-database! (not-a-database (kind other))))
    (raised (assertion-violation interrupt-database! (not-a-database x))))
  (let ((db #f) (st #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (set! st (prepare-statement db "select 1"))
           (let* ((a (attempt (lambda () (interrupt-database! 'x))))
                  (b (attempt (lambda () (interrupt-database! 42))))
                  (c (attempt (lambda () (interrupt-database! #f))))
                  (d (attempt (lambda () (interrupt-database! "app.db"))))
                  (e (attempt (lambda () (interrupt-database! st))))
                  (f (on-another-thread (lambda () (attempt (lambda () (interrupt-database! 'x)))))))
             (list a b c d e f)))))
      (lambda () (when db (close-quietly db))))))

(test-equal "from another thread, interrupt-database! makes no owner check: it answers void, where close-database! from the same thread raises &sqlite-wrong-thread, and the probe on the owner then reads set"
  '(clear (void (raised (wrong-thread close-database!))) set)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let* ((before (flag db))
                  (there (on-another-thread
                          (lambda ()
                            (let* ((verb (interrupt! db))
                                   (close (attempt (lambda () (close-database! db)))))
                              (list verb close)))))
                  (after (flag db)))
             (list before there after)))))
      (lambda () (when db (close-quietly db))))))

(test-equal "on a closed connection interrupt-database! does nothing and raises nothing, from the owner and from another thread, again and again; nothing is counted"
  (list '(raised (closed test-interrupt-database)) 'void 'void 'void 'void zero-counts)
  (let* ((db (attempt (lambda () (open-database ":memory:"))))
         (closed (begin (close-quietly db) (still-open db)))
         (a (interrupt! db))
         (b (on-another-thread (lambda () (interrupt! db))))
         (c (interrupt! db))
         (d (on-another-thread (lambda () (interrupt! db)))))
    (list closed a b c d (native-counts))))

(test-equal "a second close leaves the connection closed to interrupts: closed, closed again, then interrupt-database! from the owner and from another thread does nothing and raises nothing"
  (list 'closed 'closed-again '(raised (closed test-interrupt-database)) 'void 'void zero-counts)
  (let* ((db (attempt (lambda () (open-database ":memory:"))))
         (first (attempt (lambda () (close-database! db) 'closed)))
         (second (attempt (lambda () (close-database! db) 'closed-again)))
         (closed (still-open db))
         (a (interrupt! db))
         (b (on-another-thread (lambda () (interrupt! db)))))
    (list first second closed a b (native-counts))))

;; A statement's own unfinished write fails its finalize at the close: an
;; insert ... returning stepped once, under another connection's read, can't
;; commit, and its finalize answers busy. The close goes on, closes, and
;; raises that first failure (tests/test-statement.sps).
(test-equal "a close that closes and then raises a finalize's failure, M2's R1: the verb did nothing from inside it; close-database! raises the insert's busy; the connection is closed, and interrupt-database! from the owner and from another thread does nothing and raises nothing"
  (list '(raised (sqlite-error close-database! busy busy)) '(clear void clear)
        '(raised (closed test-interrupt-database)) 'void 'void zero-counts)
  (let ((db #f) (reader #f) (held #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (let ((path (fresh-path)))
             (set! db (open-database path))
             (let* ((inside (probed! db))
                    (made (begin (execute! db "create table t (x unique)")
                                 (execute! db "insert into t values (0)")))
                    (opened (set! reader (open-database path)))
                    (read (set! held (prepare-statement reader "select x from t")))
                    (reading (step! held))
                    (st (prepare-statement db "insert into t values (1), (2) returning x"))
                    (row (step! st))
                    (r (attempt (lambda () (close-database! db) 'closed)))
                    (closed (still-open db))
                    (a (interrupt! db))
                    (b (on-another-thread (lambda () (interrupt! db))))
                    (let-go (begin (finalize-statement! held)
                                   (set! held #f)
                                   (close-database! reader)
                                   (set! reader #f))))
               (list r (inside) closed a b (native-counts)))))))
      (lambda ()
        (when held (guard (e (#t #f)) (finalize-statement! held)))
        (for-each (lambda (d) (when d (close-quietly d))) (list reader db))))))

;; --- the open ------------------------------------------------------------------------------

;; opened-flags : Database -> (List Any Any Any)
;; The probe on DB, the verb's answer, the probe again.
(define (opened-flags db)
  (let* ((before (flag db))
         (verb (interrupt! db))
         (after (flag db)))
    (list before verb after)))

(test-equal "the open makes the connection interruptible: open-database, open-database with a settings list, and call-with-database's connection each read clear, the verb answers void, then set; the next statement starts and clears it"
  '((clear void set) (clear void set) (clear void set) (#(1) clear) zero-counts)
  (let ((a #f) (b #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! a (open-database ":memory:"))
           (set! b (open-database ":memory:" '((busy-timeout . 250) (foreign-keys . #t))))
           (let* ((one (opened-flags a))
                  (two (opened-flags b))
                  (three (attempt (lambda () (call-with-database ":memory:" opened-flags))))
                  (next (attempt (lambda () (query-row a "select 1"))))
                  (cleared (flag a)))
             (close-database! a)
             (close-database! b)
             (list one two three (list next cleared)
                   (if (equal? (native-counts) zero-counts) 'zero-counts (native-counts)))))))
      (lambda () (for-each (lambda (db) (when db (close-quietly db))) (list a b))))))

;; --- the close -----------------------------------------------------------------------------

(test-equal "the close clears the flag before it finalizes anything: the verb reaches SQLite before the close (set, then a statement clears it); called from inside the close's first finalize it does nothing (clear, void, clear); the close then finalizes the rest and closes, nothing counted"
  (list '(clear set #(1) clear) '(clear void clear) 'closed zero-counts)
  (let ((db #f) (st #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let* ((inside (probed! db))
                  (before (flag db))
                  (verb (begin (interrupt-database! db) (flag db)))
                  (run (attempt (lambda () (query-row db "select 1"))))
                  (cleared (flag db))
                  (held (begin (set! st (prepare-statement db "select 2"))
                               (step! st)
                               'held))
                  (closed (attempt (lambda () (close-database! db) 'closed))))
             (list (list before verb run cleared) (inside) closed (native-counts))))))
      (lambda () (when db (close-quietly db))))))

(test-equal "a close refused for an untracked statement leaves the flag set again: the close raises its assertion violation; the verb did nothing from inside it; after it the probe reads clear, the verb answers void, then set; once the statement is finalized the connection closes"
  (list '(raised (assertion-violation close-database! (untracked-statements 1)))
        '(clear void clear) (counts-with '((connection . 1))) '(clear void set) 0 'closed zero-counts)
  (let ((db #f) (raw #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let* ((inside (probed! db))
                  (made (set! raw (prepare! db "select 1")))
                  (refused (attempt (lambda () (close-database! db) 'closed)))
                  (counts (native-counts))
                  (after (opened-flags db))
                  (code (let ((c (finalize raw))) (set! raw #f) c))
                  (closed (attempt (lambda () (close-database! db) 'closed))))
             (list refused (inside) counts after code closed (native-counts))))))
      (lambda ()
        (when raw (guard (e (#t #f)) (finalize raw)))
        (when db (close-quietly db))))))

;; A backup reading from a connection makes sqlite3_close answer SQLITE_BUSY
;; with no statement open (tests/test-connection.sps): SQLite's own refusal,
;; the close's second path that leaves the connection open.
(test-equal "a close that sqlite3_close itself refuses, busy beside an unfinished backup, leaves the flag set again: close-database! raises &sqlite-error busy; the verb did nothing from inside it; after it the probe reads clear, the verb answers void, then set; once the backup is finished both connections close"
  (list 'backup '(raised (sqlite-error close-database! busy busy)) '(clear void clear)
        (counts-with '((connection . 2))) '(clear void set) 0 'closed 'closed zero-counts)
  (let ((source #f) (target #f) (backup #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! source (open-database ":memory:"))
           (set! target (open-database ":memory:"))
           (let* ((inside (probed! source))
                  (made (begin
                          (set! backup
                                (with-handle target
                                  (lambda (t)
                                    (with-handle source
                                      (lambda (s)
                                        (call-with-c-string 'test-interrupt-database "main"
                                          (lambda (main) (backup-init t main s main))))))))
                          (if (eqv? backup 0) 'no-backup 'backup)))
                  (refused (attempt (lambda () (close-database! source) 'closed)))
                  (counts (native-counts))
                  (after (opened-flags source))
                  (finished (let ((code (backup-finish backup))) (set! backup #f) code))
                  (a (attempt (lambda () (close-database! source) 'closed)))
                  (b (attempt (lambda () (close-database! target) 'closed))))
             (list made refused (inside) counts after finished a b (native-counts))))))
      (lambda ()
        (when (and backup (not (eqv? backup 0))) (guard (e (#t #f)) (backup-finish backup)))
        (for-each (lambda (db) (when db (close-quietly db))) (list source target))))))

;; --- the other closes: a failed setting, call-with-database's ---------------------------------

;; A step whose set statement fails to prepare: applied-settings! closes the
;; connection, then raises the prepare's condition (ADR-0018).
(define failing-step '(busy-timeout "select * from no_such_table" "pragma busy_timeout" 0))

(test-equal "slice 5's close of a connection whose setting failed, through applied-settings!: the verb did nothing from inside it; it closes, and raises the setting's own condition; left open by an untracked statement, the flag is set again: the probe reads clear, the verb answers void, then set"
  (list (list '(raised (sqlite-error the-suite error error)) '(clear void clear)
              '(raised (closed test-interrupt-database)) zero-counts)
        (list '(raised (sqlite-error the-suite error error)) '(clear void clear)
              (counts-with '((connection . 1))) '(clear void set) 0 'closed zero-counts))
  (let* ((closes
          (let ((db #f))
            (dynamic-wind
              (lambda () #f)
              (lambda ()
                (attempt
                 (lambda ()
                   (set! db (open-database ":memory:"))
                   (let* ((inside (probed! db))
                          (r (attempt (lambda () (applied-settings! 'the-suite db (list failing-step))
                                              'applied)))
                          (after (still-open db)))
                     (list r (inside) after (native-counts))))))
              (lambda () (when db (close-quietly db))))))
         (left-open
          (let ((db #f) (raw #f))
            (dynamic-wind
              (lambda () #f)
              (lambda ()
                (attempt
                 (lambda ()
                   (set! db (open-database ":memory:"))
                   (let* ((inside (probed! db))
                          (made (set! raw (prepare! db "select 1")))
                          (r (attempt (lambda () (applied-settings! 'the-suite db (list failing-step))
                                              'applied)))
                          (counts (native-counts))
                          (after (opened-flags db))
                          (code (let ((c (finalize raw))) (set! raw #f) c))
                          (closed (attempt (lambda () (close-database! db) 'closed))))
                     (list r (inside) counts after code closed (native-counts))))))
              (lambda ()
                (when raw (guard (e (#t #f)) (finalize raw)))
                (when db (close-quietly db)))))))
    (list closes left-open)))

(test-equal "call-with-database's close: the verb did nothing from inside it, and the procedure's answer comes back; left open by an untracked statement, the close's assertion violation is raised from call-with-database and the flag is set again: the probe reads clear, the verb answers void, then set"
  (list (list 'returned '(clear void clear) zero-counts)
        (list '(raised (assertion-violation call-with-database (untracked-statements 1)))
              '(clear void clear) (counts-with '((connection . 1))) '(clear void set) 0 'closed
              zero-counts))
  (let* ((closes
          (let* ((inside (lambda () 'never-tracked))
                 (r (attempt (lambda ()
                               (call-with-database ":memory:"
                                 (lambda (db) (set! inside (probed! db)) 'returned))))))
            (list r (inside) (native-counts))))
         (left-open
          (let ((kept #f) (raw #f) (inside (lambda () 'never-tracked)))
            (dynamic-wind
              (lambda () #f)
              (lambda ()
                (let* ((r (attempt (lambda ()
                                     (call-with-database ":memory:"
                                       (lambda (db)
                                         (set! kept db)
                                         (set! inside (probed! db))
                                         (set! raw (prepare! db "select 1"))
                                         'returned)))))
                       (counts (native-counts))
                       (after (if kept (opened-flags kept) 'no-database))
                       (code (if raw (let ((c (finalize raw))) (set! raw #f) c) 'no-statement))
                       (closed (if kept (attempt (lambda () (close-database! kept) 'closed)) 'no-database)))
                  (list r (inside) counts after code closed (native-counts))))
              (lambda ()
                (when raw (guard (e (#t #f)) (finalize raw)))
                (when kept (close-quietly kept)))))))
    (list closes left-open)))

;; --- engines: the call inside the latch -----------------------------------------------------
;; interrupt-latch-interrupt!'s one critical section holds the flag's read and the call
;; together (ADR-0019), and an engine spends no ticks inside a section. So an expiry comes
;; before the section, and a close then clears the flag, so the remainder calls nothing; or
;; after the call, which the close then follows. How the record hands its call to the latch is
;; these rows' to hold: tests/test-interrupt.sps holds the latch alone, on stand-ins. A call
;; made after the latch returns, the handle read inside it, can expire between the two with the
;; live handle in hand, and its remainder, resumed after the close, calls on a freed
;; connection.
;;
;; Each trial takes a fresh connection and a fresh engine, closes the
;; connection at the engine's first expiry, and resumes the remainder to its
;; end. A fuel names no fixed point in the code, so the fuels run from 1
;; until a trial completes without expiring, and a sweep with no trial
;; resumed after a close fails by name. A collect request costs an engine's
;; ticks, so each sweep collects first, with collect-trip-bytes raised far
;; above what it allocates, and fails by name when a collection ran during
;; it: each fuel then stops at one point of the code, and the sweep passes
;; every point the call has.

;; max-fuel : Positive-Integer
;; Where a sweep gives up: far past the fuel at which the call completes.
(define max-fuel 500)

;; split-trial : Positive-Integer (Database Positive-Integer (Any -> Void) -> Any)
;;               -> (U (List 'completed Any Any (Listof Any)) (List 'resumed Any (Listof Any))
;;                     (List 'raised Any (Listof Any)))
;; One trial at FUEL: a fresh connection, and (CALL db live note!) run in a
;; fresh engine, its answer read by answered inside the engine; LIVE is the
;; connection's handle, and NOTE! adds to the trial's notes. Completed
;; unexpired: completed, the answer, the probe read before the close, and
;; the notes. Expired: the connection closed, noted closed, and the
;; remainder resumed to its end: resumed, the answer, and the notes. raised,
;; for what the open or a close raised, and the notes.
(define (split-trial fuel call)
  (let ((db #f) (notes '()))
    (let* ((note! (lambda (n) (set! notes (cons n notes))))
           (close! (lambda () (close-database! db) (note! 'closed)))
           (outcome
            (dynamic-wind
              (lambda () #f)
              (lambda ()
                (attempt
                 (lambda ()
                   (set! db (open-database ":memory:"))
                   (let ((live (with-handle db (lambda (h) h))))
                     ((make-engine (lambda () (answered (lambda () (call db live note!)))))
                      fuel
                      (lambda (left answer)
                        (let ((seen (flag db)))
                          (close!)
                          (list 'completed answer seen)))
                      (lambda (next)
                        (close!)
                        (let resume ((next next))
                          (next 100000000
                                (lambda (left answer) (list 'resumed answer))
                                resume))))))))
              (lambda () (when db (close-quietly db))))))
      (append outcome (list (reverse notes))))))

;; sweep : String (Database Positive-Integer (Any -> Void) -> Any)
;;         -> (List (Listof (Pairof Positive-Integer Any)) Any)
;; split-trial of CALL at each fuel from 1, until a trial is not resumed or
;; max-fuel is reached: each trial by its fuel, in order; and
;; no-collection-during-the-sweep, or how many ran. It collects first, and
;; runs with collect-trip-bytes at a gigabyte. Prints, naming WHAT, the fuel
;; it stopped at and how many trials it resumed.
(define (sweep what call)
  (collect)
  (let* ((before (collections))
         (trials (parameterize ((collect-trip-bytes (* 1024 1024 1024)))
                   (let loop ((fuel 1) (trials '()))
                     (let* ((trial (split-trial fuel call))
                            (trials (cons (cons fuel trial) trials)))
                       (if (and (eq? (car trial) 'resumed) (< fuel max-fuel))
                           (loop (+ fuel 1) trials)
                           (reverse trials))))))
         (after (collections))
         (last (list-ref trials (- (length trials) 1))))
    (display "  ")
    (display what)
    (display ": stopped at fuel ")
    (display (car last))
    (display ", ")
    (display (cadr last))
    (display ", after ")
    (display (length (filter (lambda (t) (eq? (cadr t) 'resumed)) trials)))
    (display " trials resumed after a close")
    (newline)
    (list trials (if (= before after) 'no-collection-during-the-sweep (list 'collections (- after before))))))

;; notes-of : (Pairof Positive-Integer (Listof Any)) -> (Listof Any)
;; A trial's notes, its last element.
(define (notes-of trial) (list-ref trial (- (length trial) 1)))

;; called-after-the-close? : (Listof Any) -> Boolean
;; Whether NOTES hold anything after closed.
(define (called-after-the-close? notes)
  (let ((after (memq 'closed notes)))
    (and after (pair? (cdr after)))))

;; read-sweep : (List (Listof (Pairof Positive-Integer Any)) Any) ((Pairof Positive-Integer Any) -> Boolean)
;;              -> (List Any Symbol Any Any)
;; RUN read whole: its trials FINE? refuses, by fuel, or none-went-wrong;
;; resumed-after-a-close, or no-trial-resumed; its last trial, the fuel
;; dropped; and whether a collection ran during it.
(define (read-sweep run fine?)
  (let ((trials (car run)))
    (list (let ((wrong (filter (lambda (t) (not (fine? t))) trials)))
            (if (null? wrong) 'none-went-wrong wrong))
          (if (exists (lambda (t) (eq? (cadr t) 'resumed)) trials)
              'resumed-after-a-close
              'no-trial-resumed)
          (cdr (list-ref trials (- (length trials) 1)))
          (cadr run))))

;; spin : Natural -> Void
;; N turns of a loop, each a tick an engine counts outside a critical
;; section.
(define (spin n) (let loop ((i 0)) (when (< i n) (loop (+ i 1)))))

;; stand-in : Positive-Integer (Any -> Void) -> (Any -> Void)
;; A stand-in for sqlite3_interrupt that spins 20 turns, then notes its
;; call: called-live when it is handed LIVE, else (called HANDLE). It calls
;; nothing. The spin gives an engine ticks to stop it at: a stand-in that
;; only notes its call may cost none, and then no fuel stops a call made
;; after the latch returns before its note. Against that, a probe with such
;; a stand-in expired after the latch at no fuel, and this suite's at one
;; fuel of 14; with the spin, the probe at 20 fuels of 26 and this suite at
;; 21 of 34. Inside the latch's section the spin costs no tick.
(define (stand-in live note!)
  (lambda (h)
    (spin 20)
    (note! (if (eqv? h live) 'called-live (list 'called h)))))

;; stand-in-fine? : (Pairof Positive-Integer (Listof Any)) -> Boolean
;; Whether a trial completed or was resumed, the call answering void, its
;; stand-in called at most once, with the live handle, and never after the
;; close.
(define (stand-in-fine? trial)
  (let ((notes (notes-of trial)))
    (and (memq (cadr trial) '(completed resumed))
         (eq? (caddr trial) 'void)
         (not (called-after-the-close? notes))
         (for-all (lambda (n) (memq n '(called-live closed))) notes)
         (<= (length (filter (lambda (n) (eq? n 'called-live)) notes)) 1))))

(test-equal "interrupt-database/with in an engine, at every fuel from 1 until it completes unexpired, each trial a fresh connection and engine, the connection closed at the first expiry and the remainder resumed to its end: no trial calls its stand-in after the close; some trial was resumed after a close; the trial that completed called it once, with the live handle, and SQLite never; no collection ran"
  '(none-went-wrong resumed-after-a-close (completed void clear (called-live closed))
                    no-collection-during-the-sweep)
  (read-sweep (sweep "interrupt-database/with"
                     (lambda (db live note!) (interrupt-database/with db (stand-in live note!))))
              stand-in-fine?))

;; Plain, a call on a freed connection is silent: sqlite3_interrupt writes
;; one int into the freed block, and nothing reads it. So plain, this row
;; reads only what the verb answers and raises, and a verb that calls
;; sqlite3_interrupt after the latch returns, the latch handing it the
;; handle, passes it. Under make test-memory, Valgrind sees the write: at
;; each fuel that stops such a verb between the latch and its call, the
;; suite's .valgrind log reports "Invalid write of size 4 at
;; sqlite3_interrupt", 408 bytes inside a block sqlite3_close freed, of 840
;; bytes on 3.53.1 and 792 at the floor, and the gate fails the suite.
(test-equal "interrupt-database! in an engine, swept the same way: every trial answers void and raises nothing; some trial was resumed after a close; the trial that completed reached SQLite, the probe reading set; no collection ran"
  '(none-went-wrong resumed-after-a-close (completed void set (closed))
                    no-collection-during-the-sweep)
  (read-sweep (sweep "interrupt-database!" (lambda (db live note!) (interrupt-database! db)))
              (lambda (trial)
                (and (memq (cadr trial) '(completed resumed))
                     (eq? (caddr trial) 'void)
                     (equal? (notes-of trial) '(closed))))))

;; --- two threads: the call under the latch's mutex ------------------------------------------
;; A critical section keeps out only its own thread's engines and interrupts; between threads
;; the latch's mutex is the exclusion (ADR-0019). A call made inside a section of the record's
;; own, after the latch has let its mutex go, passes the engine rows, since no expiry splits
;; the section, and the rows inside the close, where the flag reads clear;
;; tests/test-interrupt.sps's race holds the latch alone. This row holds a stand-in in flight
;; on another thread while the owner closes, and the close's first finalize, an entry of this
;; suite's own, notes when the work starts.

;; The waits: in-flight-ms, the stand-in's wait for the close's work to
;; start, elapses whole when the record is right, so it is short; the other
;; elapses only when something is wrong.
(define in-flight-ms 200)
(define long-ms 5000)

;; race-through-the-record : -> Any
;; A fresh connection tracking an entry of this suite's own, whose finalize
;; notes work-start, and two threads with one board of notes:
;;   - the interrupter calls interrupt-database/with, whose stand-in notes
;;     interrupt-start, when handed the live handle, else what it was
;;     handed; says it is in flight; waits up to long-ms for the owner to say
;;     it is calling the close, then up to in-flight-ms for the close's work
;;     to start; and notes interrupt-end;
;;   - the owner, this thread, waits up to long-ms for the stand-in to be in
;;     flight, says it is calling the close, and closes.
;; The notes, in order; the interrupter's answer, by answered; the close's;
;; and the counts.
(define (race-through-the-record)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let* ((live (with-handle db (lambda (h) h)))
                  (m (make-mutex))
                  (c (make-condition))
                  (notes '())
                  (in-flight #f)
                  (calling-close #f)
                  (work-started #f)
                  (note! (lambda (n) (set! notes (cons n notes))))
                  (tracked (track-statement! db (list 'this-suites-entry)
                                             (lambda (handle)
                                               (with-mutex m
                                                 (note! 'work-start)
                                                 (set! work-started #t)
                                                 (condition-broadcast c))
                                               'finalized)))
                  (interrupter
                   (start-thread
                    (lambda ()
                      (answered
                       (lambda ()
                         (interrupt-database/with
                          db
                          (lambda (h)
                            (with-mutex m
                              (note! (if (eqv? h live) 'interrupt-start (list 'interrupt-start h)))
                              (set! in-flight #t)
                              (condition-broadcast c)
                              (await m c (lambda () calling-close) long-ms)
                              (await m c (lambda () work-started) in-flight-ms)
                              (note! 'interrupt-end)))))))))
                  (ready (with-mutex m (await m c (lambda () in-flight) long-ms)))
                  (calling (with-mutex m
                             (set! calling-close #t)
                             (condition-broadcast c)))
                  (closed (attempt (lambda () (close-database! db) 'closed)))
                  (interrupted (interrupter answer-ms)))
             (list (with-mutex m (reverse notes)) interrupted closed (native-counts))))))
      (lambda () (when db (close-quietly db))))))

(test-equal "a stand-in in flight on another thread, through interrupt-database/with, when the owner closes: the close's work starts only once the stand-in has ended; the interrupter answers void, the close closes, nothing is counted"
  (list '(interrupt-start interrupt-end work-start) 'void 'closed zero-counts)
  (race-through-the-record))

;; --- with-transaction's exits: the latch shut ---------------------------------------------
;;
;; with-transaction steps its own ROLLBACK, and the ROLLBACK TO and RELEASE
;; of its failure path, with the connection's latch shut, so an
;; interrupt-database! sent while one runs is dropped; its COMMIT, and the
;; RELEASE that commits a savepoint, stay interruptible, and an interrupted
;; commit is rolled back under the shut. The flag the shut found is put back
;; after. Before, a watchdog that kept interrupting stopped the ROLLBACK as
;; it started, and the transaction outlived the call.
;;
;; SQLite's statement trace, SQLITE_TRACE_STMT, calls this suite's callback
;; as each statement starts its program, after SQLite has cleared any
;; earlier interrupt, inside the step: the callback calls
;; interrupt-database! there, on the real record, for each statement it is
;; set to, and reads the probe straight after. So each row reads, on one
;; thread with nothing timed, whether the verb reached SQLite during that
;; statement, through with-transaction's own wiring, never a stand-in's.
;; Reached, the interrupt stops the statement at its first jump, as a
;; watchdog's would.

;; sqlite-trace-stmt : Natural
;; SQLITE_TRACE_STMT, the trace's mask for a statement's start.
(define sqlite-trace-stmt 1)

;; The callback's state: the connection it interrupts, the SQL it
;; interrupts, and its notes, newest first.
(define trace-db #f)
(define trace-targets '())
(define trace-notes '())

;; tracer : int (*)(unsigned, void *pCtx, void *P, void *X)
;; As a statement of trace-targets starts, X its SQL and pCtx the
;; connection's handle: interrupt-database! on trace-db, then the probe on
;; the handle, noted (SQL VERB PROBE). Whatever it raises is noted too, and
;; nothing reaches C.
(define tracer
  (foreign-callable __collect_safe
    (lambda (mask ctx p x)
      (guard (e (#t (set! trace-notes (cons (list 'raised (describe e)) trace-notes))))
        (let ((sql (c-string->string x)))
          (when (member sql trace-targets)
            (let* ((verb (interrupt! trace-db))
                   (probe (flag-of ctx)))
              (set! trace-notes (cons (list sql verb probe) trace-notes))))))
      0)
    (unsigned-32 uptr uptr uptr) int))

;; traced : Database (Listof String) (-> Any) -> (List Any (Listof Any))
;; THUNK's answer, by attempt, with the callback set on DB for TARGETS, and
;; its notes, in order. The callback is locked while SQLite holds it, and
;; let go, once, after the trace is cleared.
(define (traced db targets thunk)
  (let ((handle (with-handle db (lambda (h) h))))
    (dynamic-wind
      (lambda ()
        (set! trace-db db)
        (set! trace-targets targets)
        (set! trace-notes '())
        (lock-object tracer)
        (trace-v2 handle sqlite-trace-stmt (foreign-callable-entry-point tracer) handle))
      (lambda ()
        (let* ((r (attempt thunk))
               (notes (reverse trace-notes)))
          (list r notes)))
      (lambda ()
        (trace-v2 handle 0 0 0)
        (unlock-object tracer)
        (set! trace-targets '())
        (set! trace-db #f)))))

;; yes-no : Any -> Any
(define (yes-no x) (cond ((eq? x #t) 'yes) ((eq? x #f) 'no) (else x)))

;; markers : Database -> Any
;; t's rows, in order, joined by commas, or (none).
(define (markers db)
  (attempt (lambda ()
             (vector-ref (query-row db "select coalesce(group_concat(x, ','), '(none)') from (select x from t order by x)")
                         0))))

;; shut-case : (Listof String) (Database -> Any) -> Any
;; On a fresh connection holding t: CALL, traced for TARGETS, and the
;; notes; then in-transaction?, t's rows, and the verb and the probe once
;; the call is over, with no statement running: with the latch put back,
;; the verb reaches SQLite and the probe reads set. Then the counts, the
;; connection closed.
(define (shut-case targets call)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (execute! db "create table t (x)")
           (let* ((r (traced db targets (lambda () (call db))))
                  (in (yes-no (in-transaction? db)))
                  (rows (markers db))
                  (verb (interrupt! db))
                  (probe (flag db))
                  (closed (begin (close-database! db) (set! db #f) 'closed)))
             (list (car r) (cadr r) in rows (list verb probe) (native-counts))))))
      (lambda () (when db (close-quietly db))))))

(define interrupted-by-the-verb '(raised (sqlite-error with-transaction interrupt interrupt)))

(test-equal "with-transaction's ROLLBACK runs with the latch shut: the body raises, and an interrupt-database! sent as the ROLLBACK starts is dropped, the probe clear; the ROLLBACK succeeds, the body's condition reaches the caller, nothing is open or written, and after the call the verb reaches SQLite again"
  (list 'the-body-raised '(("ROLLBACK" void clear)) 'no "(none)" '(void set) zero-counts)
  (shut-case '("ROLLBACK")
             (lambda (db)
               (guard (e ((eq? e 'the-body-raised) e))
                 (with-transaction db 'deferred
                   (lambda ()
                     (execute! db "insert into t values ('inner')")
                     (raise 'the-body-raised)))))))

(test-equal "nested, with-transaction's ROLLBACK TO and RELEASE run with the latch shut: the inner body raises, and the verb sent as each starts is dropped; the inner level is rolled back and released, and the outer commits its own marker alone"
  (list 'outer-returned
        '(("ROLLBACK TO chez_sqlite3_1" void clear) ("RELEASE chez_sqlite3_1" void clear))
        'no "outer" '(void set) zero-counts)
  (shut-case '("ROLLBACK TO chez_sqlite3_1" "RELEASE chez_sqlite3_1")
             (lambda (db)
               (with-transaction db 'deferred
                 (lambda ()
                   (execute! db "insert into t values ('outer')")
                   (guard (e ((eq? e 'the-body-raised) e))
                     (with-transaction db
                       (lambda ()
                         (execute! db "insert into t values ('inner')")
                         (raise 'the-body-raised))))
                   'outer-returned)))))

(test-equal "with-transaction's COMMIT stays interruptible, and an interrupted COMMIT is rolled back with the latch shut: the verb sent as the COMMIT starts reaches SQLite, the probe set, and the COMMIT answers interrupt; the ROLLBACK after it drops the verb, and succeeds; &sqlite-interrupt from with-transaction, nothing open or written"
  (list interrupted-by-the-verb '(("COMMIT" void set) ("ROLLBACK" void clear)) 'no "(none)" '(void set)
        zero-counts)
  (shut-case '("COMMIT" "ROLLBACK")
             (lambda (db)
               (with-transaction db 'deferred
                 (lambda () (execute! db "insert into t values ('inner')") 42)))))

(test-equal "nested, the RELEASE that commits stays interruptible, and its rollback runs with the latch shut: the verb reaches SQLite as the first RELEASE starts, which answers interrupt; ROLLBACK TO and the RELEASE after it drop the verb; the inner raises &sqlite-interrupt, and the outer commits its own marker alone"
  (list (list interrupted-by-the-verb 'outer-returned)
        '(("RELEASE chez_sqlite3_1" void set) ("ROLLBACK TO chez_sqlite3_1" void clear)
          ("RELEASE chez_sqlite3_1" void clear))
        'no "outer" '(void set) zero-counts)
  (shut-case '("RELEASE chez_sqlite3_1" "ROLLBACK TO chez_sqlite3_1")
             (lambda (db)
               (let* ((inner #f)
                      (outer (with-transaction db 'deferred
                               (lambda ()
                                 (execute! db "insert into t values ('outer')")
                                 (set! inner (attempt (lambda ()
                                                        (with-transaction db
                                                          (lambda () (execute! db "insert into t values ('inner')") 42)))))
                                 'outer-returned))))
                 (list inner outer)))))

(test-equal "the case the shut leaves: an interrupt-database! sent from the body before the shut, while the body's own statement holds a row, still stops the ROLLBACK, since SQLite keeps an interrupt while a statement is active; the body's condition reaches the caller, the transaction stays open, and once the statement is reset a plain rollback ends it"
  '(the-body-raised yes void void no)
  (let ((db #f) (held #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (execute! db "create table t (x)")
           (execute! db "insert into t values (1), (2)")
           (let* ((r (guard (e ((eq? e 'the-body-raised) e))
                       (with-transaction db 'deferred
                         (lambda ()
                           (execute! db "insert into t values (3)")
                           (set! held (prepare-statement db "select x from t"))
                           (step! held)
                           (interrupt-database! db)
                           (raise 'the-body-raised)))))
                  (in (yes-no (in-transaction? db)))
                  (reset (answered (lambda () (reset! held))))
                  (rolled (answered (lambda () (execute! db "rollback"))))
                  (after (yes-no (in-transaction? db))))
             (list r in reset rolled after)))))
      (lambda ()
        (when held (guard (e (#t #f)) (finalize-statement! held)))
        (when db (close-quietly db))))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "interrupt-database")

(exit (suite-exit-status runner))
