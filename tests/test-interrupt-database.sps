#!r6rs
;;; interrupt-database!, the one verb any thread may call, and the close's
;;; exclusion of it, through the real connection record (ADR-0019, decisions
;;; 1 to 5; ADR-0010 and ADR-0012, amended in M3's plan). The record holds
;;; slice 1's latch: the open sets its flag, the close clears it before it
;;; finalizes anything, and a close that leaves the connection open sets it
;;; again. tests/test-interrupt.sps holds the latch itself on stand-ins.
;;;
;;; The probe. An interrupt that reaches sqlite3_interrupt while no statement
;;; runs is lost for what follows, but leaves sqlite3_is_interrupted reading 1
;;; until the next statement starts (M3's research, concurrency I1 and I2).
;;; This suite binds sqlite3_is_interrupted itself, after the load, as the
;;; library never does (ADR-0019, decision 7): it reads clear before an
;;; interrupt, and set after one that reached sqlite3_interrupt. So each row
;;; reads whether the verb called SQLite, on one thread, with no statement
;;; running and nothing timed.
;;;
;;;   the verb       a value that is no database, from this thread and
;;;                  another: an assertion violation from the verb; from
;;;                  another thread, no owner check: the verb answers, and
;;;                  the probe reads set; on a closed connection, from either
;;;                  thread, it does nothing and raises nothing, after a second
;;;                  close too, and after a close that closed and raised a
;;;                  finalize's failure, M2's R1
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
;;;   the others     slice 5's close of a connection whose setting failed,
;;;                  reached through applied-settings!, and
;;;                  call-with-database's close: each clears the flag inside,
;;;                  and each that is left open sets it again
;;;
;;; tests/test-interrupt-reach.sps holds what the verb reaches, and
;;; tests/test-interrupt-close.sps a running step after a failed close and the
;;; race under the gate.
;;;
;;; A thread this suite forks answers whatever it raises, and every wait for
;;; it is bounded (AGENTS.md). The loading procedures are reached through
;;; eval, under a guard, so a refused library or a missing name fails rows by
;;; name. Every computation that can raise runs under a guard with a sentinel
;;; of its own; no expected value is #f. Effects run in order, through let*
;;; and named lets, never map.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure fork-thread thread-join make-mutex with-mutex
              make-condition condition-wait condition-broadcast make-time current-time
              time-difference add-duration time>=?)
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
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define track-statement! (reach '(chez-sqlite3 private connection) 'track-statement!))
(define applied-settings! (reach '(chez-sqlite3 private open) 'applied-settings!))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-out-pointer (reach '(chez-sqlite3 private native) 'call-with-out-pointer))

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
;; answers, Void (ADR-0019, decision 1).
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
;; the oldest, so the first the close finalizes (ADR-0014, decision 8).
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
;; raises that first failure (M2's R1; tests/test-statement.sps).
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

;; --- the other closes: slice 5's failed setting, call-with-database's -------------------------

;; A step whose set statement fails to prepare: applied-settings! closes the
;; connection, then raises the prepare's condition (ADR-0018, decision 7).
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

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "interrupt-database")

(exit (suite-exit-status runner))
