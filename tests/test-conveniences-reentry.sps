#!r6rs
;;; The suite for the conveniences' re-entries (ADR-0016), in (chez-sqlite3
;;; private conveniences). A guard whose clauses do not match re-enters the
;;; raise's extent to raise again, so a before thunk that refused would put
;;; its own condition in the caller's place; and query-fold's finish is not
;;; idempotent, since the statement it gives back to the cache may be
;;; another caller's by then, so it acts once, behind a flag, and the loop
;;; reads the flag.
;;;
;;;   the body's own  each convenience, under a guard whose clauses do not
;;;                   match inside one that catches everything, delivers its
;;;                   body's own condition: its failure, or the fold's
;;;                   procedure's raise, a condition or not, with a finish that
;;;                   fails beside it; execute-script!'s rebuilt error, its
;;;                   block freed once
;;;   once            the fold's statement is finished once: after its normal
;;;                   return, the suite checks the cached statement out and
;;;                   holds it at a row; a continuation that re-enters the fold
;;;                   then raises &sqlite-closed, and the held statement is
;;;                   neither reset nor filed again
;;;   resumed         a fold whose procedure an outer handler resumes, through
;;;                   a raise-continuable, after a guard re-entered past its
;;;                   extent, raises &sqlite-closed, its procedure not called
;;;                   again
;;;   re-entered      a fold re-entered through a continuation after its
;;;                   normal return raises &sqlite-closed, and the statement
;;;                   the cache holds stays ready and unstepped, read through
;;;                   tracked-statements and statement-state
;;;   its own failure a fold's own step that fails raises its own condition;
;;;                   and a read of its own that fails is raised, not the
;;;                   finish's failure beside it
;;;   jumped back     execute-script! jumped back inside its own call: a
;;;                   timer's handler captures a continuation at each tick
;;;                   once the script's first row stands, and calls it once
;;;                   another row stands. The jump stays inside the block's
;;;                   extent, crossing no winder, so call-with-block's
;;;                   refusal never runs; the call's claim refuses the
;;;                   script's next prepare instead, and no statement runs
;;;                   twice. Then again under a collect trip of 256 bytes,
;;;                   SQLite's trace and an authorizer allocating 32 KiB inside
;;;                   each section that prepares or steps, so the timer's
;;;                   handler runs at a section's exit too, where a claim set
;;;                   just after the prepare's section let the jump prepare a
;;;                   statement again. It fails by name unless collect
;;;                   requests fell in its trials, each such section met its
;;;                   request before the next, which a trip slipped to 256 KiB
;;;                   does not, and some capture was made at such a section's
;;;                   exit, which the high pass never does
;;;
;;; The loading procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) set-timer timer-interrupt-handler collect collect-trip-bytes
              collect-request-handler foreign-procedure foreign-callable foreign-callable-entry-point
              lock-object unlock-object scheme-environment)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3 private conditions) sqlite-invalid-text? sqlite-invalid-text-column
              sqlite-invalid-text-offset)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-error-sql sqlite-error-offset sqlite-closed?))

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

(define conveniences '(chez-sqlite3 private conveniences))
(define connection-library '(chez-sqlite3 private connection))
(define statement-library '(chez-sqlite3 private statement))
(define execute! (reach conveniences 'execute!))
(define query (reach conveniences 'query))
(define query-row (reach conveniences 'query-row))
(define query-fold (reach conveniences 'query-fold))
(define execute-script! (reach conveniences 'execute-script!))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define total-changes (reach '(chez-sqlite3) 'total-changes))
(define database-cache-count (reach connection-library 'database-cache-count))
(define tracked-statements (reach connection-library 'tracked-statements))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define step! (reach statement-library 'step!))
(define statement-sql (reach statement-library 'statement-sql))
(define statement-state (reach statement-library 'statement-state))
(define checked-out (reach statement-library 'checked-out))
(define returned (reach statement-library 'returned))
(define column-value (reach '(chez-sqlite3 private statement-values) 'column-value))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (sqlite-error-sql e) (sqlite-error-offset e)))
        ((sqlite-invalid-text? e)
         (list 'invalid-text (who-of e) (sqlite-invalid-text-column e) (sqlite-invalid-text-offset e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        ((symbol? e) (list 'the-symbol e))
        (else (list 'other (describe e)))))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

;; nested : (-> Any) -> Any
;; THUNK under a guard whose one clause never matches, inside a guard that
;; catches everything: (outer WHAT) for what the outer one caught, or
;; (returned VALUE).
(define (nested thunk)
  (guard (c (#t (list 'outer (what-raised c))))
    (guard (c ((eq? c 'a-symbol-nothing-raises) 'inner))
      (list 'returned (thunk)))))

(define (statement-count) (cdr (assq 'statement (native-counts))))

;; summarized : (Listof Any) -> Any
;; () for no deviation; else how many, and the first three.
(define (summarized deviations)
  (if (null? deviations)
      '()
      (list (length deviations)
            (let loop ((rest deviations) (n 0) (kept '()))
              (if (or (null? rest) (= n 3)) (reverse kept) (loop (cdr rest) (+ n 1) (cons (car rest) kept)))))))

;; states : Database -> (Listof (Pairof String Symbol))
(define (states db)
  (list-sort (lambda (a b) (string<? (car a) (car b)))
             (let loop ((rest (tracked-statements db)) (found '()))
               (if (null? rest)
                   found
                   (loop (cdr rest)
                         (cons (cons (statement-sql (car rest)) (statement-state (car rest))) found))))))

;; cached-statement : Database String -> (U Statement #f)
(define (cached-statement db sql)
  (let ((found (filter (lambda (st) (string=? (statement-sql st) sql)) (tracked-statements db))))
    (and (= (length found) 1) (car found))))

;; undo! : (Listof Any) (Listof Any) -> Void
(define (undo! statements databases)
  (for-each (lambda (s) (guard (e (#t #f)) (finalize-statement! s))) statements)
  (for-each (lambda (db) (guard (e (#t #f)) (close-database! db))) databases))

;; with-db : (-> Database) (Database -> Any) -> Any
(define (with-db open proc)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda () (attempt (lambda () (set! db (open)) (proc db))))
      (lambda () (when db (undo! '() (list db)))))))

;; in-dir : (String -> Any) -> Any
(define (in-dir proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory proc)))

;; tier-run : Database String -> (Listof (Vectorof Any))
(define (tier-run db sql)
  (let ((st (prepare-statement db sql)))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let loop ((rows '()))
          (if (step! st)
              (loop (cons (vector (column-value st 0)) rows))
              (reverse rows))))
      (lambda () (finalize-statement! st)))))

;; with-n : (Database -> Any) -> Any
;; PROC's answer, or what it raised, given a :memory: database holding table
;; n, its rows 1, 2 and 3, made through the statement tier.
(define (with-n proc)
  (with-db (lambda () (open-database ":memory:"))
    (lambda (db)
      (tier-run db "create table n (x)")
      (tier-run db "insert into n values (1), (2), (3)")
      (proc db))))

;; with-file-db : (String Database -> Any) -> Any
;; PROC's answer given a file holding table t, x unique, its one row 0, and
;; a connection to it, closed after.
(define (with-file-db proc)
  (in-dir (lambda (dir)
            (let ((path (string-append dir "/t.db")) (db #f))
              (dynamic-wind
                (lambda () #f)
                (lambda ()
                  (attempt (lambda ()
                             (set! db (open-database path))
                             (tier-run db "create table t (x unique)")
                             (tier-run db "insert into t values (0)")
                             (proc path db))))
                (lambda () (when db (undo! '() (list db)))))))))

;; under-reader : String (-> Any) -> Any
;; THUNK's answer while a second connection to PATH holds a read.
(define (under-reader path thunk)
  (let ((reader #f) (st #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (set! reader (open-database path))
        (set! st (prepare-statement reader "select x from t"))
        (step! st)
        (thunk))
      (lambda () (undo! (if st (list st) '()) (if reader (list reader) '()))))))

(define (sum acc row) (+ acc (vector-ref row 0)))

(define overflow-sql "select abs(-9223372036854775807 - 1)")
(define returning-sql "insert into t values (1), (2) returning x")

(test-begin "conveniences-reentry")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

;; --- the body's own condition -----------------------------------------------------------

(test-equal "execute!, query, query-row and execute-script!, each under a guard whose clauses do not match inside one that catches everything, deliver their body's own condition to the outer guard, never a refusal of a re-entry; none leaves a statement at a row, and the script's block is freed once; a closed connection's refusal, raised inside the script's block, reaches the outer guard as itself"
  (list (list 'outer (list 'sqlite-error 'execute! 'constraint 'constraint-unique "insert into t values (?)" #f))
        (list 'outer (list 'sqlite-error 'query 'error 'error overflow-sql #f))
        (list 'outer (list 'sqlite-error 'query-row 'error 'error overflow-sql #f))
        (list 'outer (list 'sqlite-error 'execute-script! 'constraint 'constraint-unique
                           "insert into t values (5); insert into t values (0)" 26))
        '()
        '((block . 0) (connection . 1) (statement . 0))
        (list 'outer '(closed execute-script!)))
  (with-file-db
   (lambda (path db)
     (let* ((a (nested (lambda () (execute! db "insert into t values (?)" 0))))
            (b (nested (lambda () (query db overflow-sql))))
            (c (nested (lambda () (query-row db overflow-sql))))
            (d (nested (lambda () (execute-script! db "insert into t values (5); insert into t values (0)"))))
            ;; each failed step's statement finalized, the script's too
            (left (states db))
            (counts (native-counts))
            ;; a raise that is no SQLite failure, from inside the block too
            (e (let ((closed (open-database ":memory:")))
                 (close-database! closed)
                 (nested (lambda () (execute-script! closed "select 1"))))))
       (list a b c d left counts e)))))

(test-equal "query-fold under a guard whose clauses do not match inside one that catches everything delivers its body's own condition: its procedure's condition, the very object; its procedure's raise of a symbol; its own failed step; and its procedure's raise while the finish beside it fails, an insert ... returning at its row under another's read, the insert rolled back; each statement finalized, none left at a row"
  (list (list 'outer 'the-procedures-condition)
        (list 'outer '(the-symbol boom))
        (list 'outer (list 'sqlite-error 'query-fold 'error 'error overflow-sql #f))
        (list 'outer '(the-symbol boom)) '() '(#(1)))
  (with-file-db
   (lambda (path db)
     (let* ((mine (condition (make-error) (make-message-condition "the caller's own")))
            (a (guard (c (#t (list 'outer (if (eq? c mine) 'the-procedures-condition (what-raised c)))))
                 (guard (c ((eq? c 'a-symbol-nothing-raises) 'inner))
                   (query-fold db "select x from t" (lambda (acc row) (raise mine)) 0))))
            (b (nested (lambda () (query-fold db "select x from t" (lambda (acc row) (raise 'boom)) 0))))
            (c (nested (lambda () (query-fold db overflow-sql sum 0))))
            (d (under-reader path
                 (lambda ()
                   (nested (lambda () (query-fold db returning-sql (lambda (acc row) (raise 'boom)) 0))))))
            (left (filter (lambda (s) (not (eq? (cdr s) 'ready))) (states db))))
       (list a b c d left (tier-run db "select count(*) from t"))))))

;; --- once ----------------------------------------------------------------------------------

(test-equal "query-fold's statement is finished once: after the fold's normal return the suite checks its cached statement out and holds it at a row; a continuation that re-enters the fold raises &sqlite-closed, and the held statement is still at its row, not reset, nor filed in the cache again"
  (list (list 6 (list 'raised '(closed query-fold))) 'the-folds-statement 'row 0)
  (with-n
   (lambda (db)
     (let ((k #f) (outcomes '()) (cached #f) (held #f))
       (let ((r (attempt (lambda ()
                           (query-fold db "select x from n"
                                       (lambda (acc row)
                                         (unless k (call/cc (lambda (c) (set! k c))))
                                         (sum acc row))
                                       0)))))
         (set! outcomes (cons r outcomes))
         (if (= (length outcomes) 1)
             (begin
               (set! cached (cached-statement db "select x from n"))
               (set! held (checked-out 'the-suite db "select x from n" #f #f))
               (step! held)
               (k #f))
             (let* ((state (statement-state held))
                    (in-cache (database-cache-count db)))
               (returned 'the-suite held)
               (list (reverse outcomes) (if (and cached (eq? held cached)) 'the-folds-statement 'another)
                     state in-cache))))))))

;; --- resumed -------------------------------------------------------------------------------

(test-equal "a fold whose procedure an outer handler resumes, through a raise-continuable, after a guard whose clauses do not match has re-entered past the fold's extent, raises &sqlite-closed once the procedure returns: the procedure got the handler's answer, was called once, and the statement was finalized"
  (list (list 'caught '(closed query-fold)) '(resumed) 1 '())
  (with-n
   (lambda (db)
     (let* ((calls 0)
            (got '())
            (r (guard (c (#t (list 'caught (what-raised c))))
                 (with-exception-handler
                  (lambda (c) (if (eq? c 'resume-me) 'resumed (raise-continuable c)))
                  (lambda ()
                    (guard (c ((eq? c 'a-symbol-nothing-raises) 'inner))
                      (query-fold db "select x from n"
                                  (lambda (acc row)
                                    (set! calls (+ calls 1))
                                    (set! got (cons (raise-continuable 'resume-me) got))
                                    (sum acc row))
                                  0)))))))
       (list r got calls (states db))))))

(test-equal "an outer handler's return clears the fold's raise record: after its procedure's raise-continuable is resumed, the procedure escapes through a continuation with an insert ... returning at its row under another's read, and the finalize's busy is raised as the escape leaves"
  (list (list 'raised (list 'sqlite-error 'query-fold 'busy 'busy returning-sql #f)) '(noted) '(#(1)))
  (with-file-db
   (lambda (path db)
     (let* ((got '())
            (r (under-reader path
                 (lambda ()
                   (attempt
                    (lambda ()
                      (with-exception-handler
                       (lambda (c) (if (eq? c 'note) 'noted (raise-continuable c)))
                       (lambda ()
                         (call/cc
                          (lambda (k)
                            (query-fold db returning-sql
                                        (lambda (acc row)
                                          (set! got (cons (raise-continuable 'note) got))
                                          (k 'escaped))
                                        0)))))))))))
       (list r got (tier-run db "select count(*) from t"))))))

;; --- re-entered ----------------------------------------------------------------------------

(test-equal "a fold re-entered through a continuation after its normal return raises &sqlite-closed, never restarting from the first row: its procedure was called three times, and the statement the cache holds is still ready and unstepped, so the next query of its SQL answers every row"
  (list (list 6 (list 'raised '(closed query-fold))) 3 'ready 1 '(#(1) #(2) #(3)))
  (with-n
   (lambda (db)
     (let ((k #f) (calls 0) (outcomes '()))
       (let ((r (attempt (lambda ()
                           (query-fold db "select x from n"
                                       (lambda (acc row)
                                         (set! calls (+ calls 1))
                                         (unless k (call/cc (lambda (c) (set! k c))))
                                         (sum acc row))
                                       0)))))
         (set! outcomes (cons r outcomes))
         (if (= (length outcomes) 1)
             (k #f)
             (let* ((cached (cached-statement db "select x from n"))
                    (state (if cached (statement-state cached) 'not-cached))
                    (in-cache (database-cache-count db))
                    (again (attempt (lambda () (query db "select x from n")))))
               (list (reverse outcomes) calls state in-cache again))))))))

;; --- its own failure -----------------------------------------------------------------------

(test-equal "a fold's own step that fails raises its own condition, from query-fold, its procedure called for the row before it; the statement is finalized"
  (list (list 'raised (list 'sqlite-error 'query-fold 'error 'error "select 1 union all select abs(-9223372036854775807 - 1)" #f))
        '(#(1)) '())
  (with-n
   (lambda (db)
     (let* ((rows '())
            (r (attempt (lambda ()
                          (query-fold db "select 1 union all select abs(-9223372036854775807 - 1)"
                                      (lambda (acc row) (set! rows (cons row rows)) acc)
                                      0)))))
       (list r (reverse rows)
             (filter (lambda (s) (string=? (car s) "select 1 union all select abs(-9223372036854775807 - 1)"))
                     (states db)))))))

;; Measured on both libraries: an insert ... returning stepped once under
;; another's read answers a row, and its finalize busy.
(test-equal "a read of the fold's own that fails is raised, and the finish's failure beside it is not: an insert ... returning whose second column is not well-formed TEXT, under another's read, raises &sqlite-invalid-text from query-fold, never the finalize's busy; the procedure was never called, and the insert is rolled back"
  (list (list 'raised '(invalid-text query-fold 1 0)) 0 '(#(1)))
  (with-file-db
   (lambda (path db)
     (let* ((calls 0)
            (r (under-reader path
                 (lambda ()
                   (attempt (lambda ()
                              (query-fold db "insert into t values (1), (2) returning x, cast(x'ff' as text)"
                                          (lambda (acc row) (set! calls (+ calls 1)) acc)
                                          0)))))))
       (list r calls (tier-run db "select count(*) from t"))))))

;; --- the two passes ------------------------------------------------------------------------
;; Pass = (U 'high 'low)
;; The jumped-back row runs twice. Each trial begins with begun!: a
;; collection, then PASS's trip, 2^27 in the high pass and 256 bytes in the
;; low, until the trial ends. In the low pass a request falls due all through
;; the trial, and one due inside a critical section is handled at the
;; section's exit, where it costs ticks, so the timer's handler runs there
;; too, before anything after it, and its continuation is taken there: a claim
;; set just after the prepare's section, not inside it, lets the jump prepare
;; a statement again. A request fell only where the call's allocation crossed
;; a chunk, so in the low pass each trial's connection also carries SQLite's
;; trace and an authorizer, whose callbacks allocate 32 KiB: inside each
;; section that prepares a statement, steps a row or finishes one. Both are
;; __collect_safe, as sqlite3_prepare_v3 and sqlite3_step are; both answer 0
;; and raise nothing; both are locked from here to the suite's end. Every
;; request goes through counted-request, which counts it.

(define low-trip 256)

;; default-request-handler : (-> Any)
(define default-request-handler (collect-request-handler))

;; requests : Natural
;; The collect requests the trials of the pass under way met.
(define requests 0)

(define (counted-request)
  (set! requests (+ requests 1))
  (default-request-handler)
  (exit-noted!))

;; quieted! : -> Void
;; A collection now, the trip at 2^27, far above what one trial allocates.
(define (quieted!)
  (collect-trip-bytes (expt 2 27))
  (collect))

;; --- where a remainder lies: at a forced section's exit ----------------------------------------
;; SQLite's trace and authorizer call back inside the library's critical
;; sections: each prepare, each step that answers a row, and the step that
;; finishes a statement (the two passes, above). The jumped-back row's timer
;; fires at every tick, so its ticks run out in every forced request's
;; handler, and it fires at that section's exit.
;; In the low pass force! allocates 32 KiB there, so a collect request falls
;; due inside the section and is handled at its exit, the first event check
;; once the section enables interrupts again. The handler's own work costs the
;; engine ticks. Where they run out in it, the engine's timer reads #f at its
;; end, and the engine expires as the handler returns: the remainder lies at
;; that section's exit, before anything after it. A marker set inside a
;; section and overwritten just after it reads the section's value at exactly
;; those fuels, three a section, at the low trip, and at none at the high trip
;; or at 256 KiB. So a low row fails by name unless every forced section met
;; its request before the next forced section or its slice's end, which a trip
;; slipped to 256 KiB breaks, a 32 KiB allocation then meeting one about one
;; time in eight; and unless some first slice expired at a forced section's
;; exit, which the high pass, forcing none, never does. Each first slice
;; numbers the forced sections it passes, from 1, and the row shows whose
;; exits were met. The timer is read through Chez's own $tc-field, reached
;; through eval.

;; tc-field, tc : (U Procedure #f)
(define tc-field
  (guard (e (#t #f))
    (eval (list (string->symbol "$primitive") (string->symbol "$tc-field")) (scheme-environment))))
(define tc
  (guard (e (#t #f))
    (eval (list (string->symbol "$primitive") (string->symbol "$tc")) (scheme-environment))))

;; ticks-now : -> (U Natural #f)
;; The running engine's timer: its ticks left, #f once they are spent.
(define (ticks-now) (and tc-field tc (tc-field 'timer-ticks (tc))))

;; ticks-spent? : -> Boolean
(define (ticks-spent?) (and tc-field tc (not (ticks-now)) #t))

;; forcing : Boolean
;; Whether force! allocates: in the low pass's trials alone.
(define forcing #f)

;; sink : Any
;; Where force!'s allocation is kept, so no compiler drops it.
(define sink #f)

;; forced-pending : Boolean
;; A forced section's allocation made inside a slice, its request not yet
;; handled.
(define forced-pending #f)

;; forced, unmet : Natural
;; The pass's forced sections inside an engine's slice, and those whose
;; request was not handled before the next forced section or the slice's
;; end. A forced callback whose timer reads as the last one's is in the same
;; section: an engine spends no ticks inside one, and one section can fire
;; two, as a close's finalizes do.
(define forced 0)
(define unmet 0)

;; slicing, numbering : Boolean
;; Whether an engine's slice runs now; whether a first slice does, numbering
;; the forced sections it passes.
(define slicing #f)
(define numbering #f)

;; forced-at : Any
;; The timer as the last forced section read it.
(define forced-at 'none)

;; forced-k : Natural
;; The forced sections the first slice under way has passed.
(define forced-k 0)

;; exit-k : (U Natural #f)
;; The forced section at whose exit the first slice's ticks ran out.
(define exit-k #f)

;; pass-k, pass-exits : Natural (Listof Natural)
;; The most forced sections a first slice of the pass passed, and the
;; forced sections a first slice of it expired at the exit of.
(define pass-k 0)
(define pass-exits '())

;; force! : -> Void
;; In the low pass, 32 KiB allocated; inside a slice, a new section counted,
;; and numbered inside a first slice, the last one counted unmet if its
;; request is still due.
(define (force!)
  (when forcing
    (when slicing
      (let ((t (ticks-now)))
        (unless (and forced-pending (eqv? t forced-at))
          (when forced-pending (set! unmet (+ unmet 1)))
          (set! forced (+ forced 1))
          (when numbering (set! forced-k (+ forced-k 1)))
          (set! forced-pending #t)
          (set! forced-at t))))
    (set! sink (make-bytevector 32768))))

;; exit-noted! : -> Void
;; In the request handler, once a request is handled: the forced section's
;; request met; and, inside a first slice whose ticks it spent, where the
;; section's callback found the engine's timer running, the section's
;; number noted, the first so noted. An expiry's unwinding runs after
;; thunks, a ROLLBACK's step among them, with the timer already off: a
;; section forced there is no exit a remainder was taken at. The request
;; handled is the forced section's own, at its exit: a 32 KiB allocation
;; always met a request inside its section at a trip of 256 bytes, 100
;; times of 100, so it is due as the section ends.
(define (exit-noted!)
  (when forced-pending
    (set! forced-pending #f)
    (when (and numbering (not exit-k) (number? forced-at) (ticks-spent?))
      (set! exit-k forced-k))))

;; slice-begun!, slice-ended! : -> Void
;; Around each slice: at its end, a forced section's request still due
;; counted unmet.
(define (slice-begun!)
  (set! forced-pending #f)
  (set! forced-at 'none)
  (set! slicing #t))
(define (slice-ended!)
  (set! slicing #f)
  (when forced-pending
    (set! unmet (+ unmet 1))
    (set! forced-pending #f)))

;; Tally = (List Natural Natural Natural Natural (Listof Natural))
;; A pass's collect requests, its forced sections, those unmet, the most a
;; first slice passed, and those a first slice expired at the exit of.

;; pass-reset! : -> Void
(define (pass-reset!)
  (set! requests 0)
  (set! forced 0)
  (set! unmet 0)
  (set! pass-k 0)
  (set! pass-exits '())
  (set! forced-pending #f))

;; pass-tally : -> Tally
(define (pass-tally) (list requests forced unmet pass-k (list-sort < pass-exits)))

;; low-judged : Tally -> (Listof Any)
;; low-checks' three, each failing by name.
(define (low-judged tally)
  (let ((met (car tally)) (forced (cadr tally)) (unmet (caddr tally)) (exits (list-ref tally 4)))
    (list (if (> met 0) 'collect-requests-met (list 'no-collect-request-met met))
          (if (and (> forced 0) (= unmet 0))
              'every-forced-section-met-its-request
              (list 'forced-sections forced 'unmet unmet))
          (if (pair? exits) 'taken-at-a-forced-exit (list 'none-taken-at-a-forced-exit exits)))))

;; low-checks : (Listof Symbol)
(define low-checks '(collect-requests-met every-forced-section-met-its-request taken-at-a-forced-exit))

;; tally-shown : Tally -> Void
(define (tally-shown tally)
  (display "; collect requests met ")
  (write (car tally))
  (display "; forced sections ")
  (write (cadr tally))
  (display ", unmet ")
  (write (caddr tally))
  (display "; a first slice's forced sections ")
  (write (cadddr tally))
  (display ", remainders at the exit of ")
  (write (list-ref tally 4)))

;; call-begun!, call-ended! : -> Void
;; Around a re-entry row's call, its timer firing at every tick, in place of
;; a first slice: its forced sections numbered, and once it is over, the
;; count kept for the pass and a forced section's request still due counted
;; unmet.
(define (call-begun!)
  (set! forced-k 0)
  (set! exit-k #f)
  (set! numbering #t)
  (slice-begun!))
(define (call-ended!)
  (set! numbering #f)
  (set! pass-k (max pass-k forced-k))
  (slice-ended!))

;; ticked! : -> (U Natural #f)
;; At each fire of such a timer: the forced section at whose exit its ticks
;; ran out, if they did, cleared for the next fire.
(define (ticked!)
  (let ((k exit-k))
    (set! exit-k #f)
    k))

;; captured-at! : (U Natural #f) -> Void
;; A capture made at forced section K's exit noted for the pass.
(define (captured-at! k)
  (when (and k (not (memv k pass-exits)))
    (set! pass-exits (cons k pass-exits))))

;; begun! : Pass -> Void
(define (begun! pass)
  (quieted!)
  (collect-request-handler counted-request)
  (set! forcing (eq? pass 'low))
  (when (eq? pass 'low) (collect-trip-bytes low-trip)))

;; ended! : -> Void
(define (ended!)
  (set! forcing #f)
  (collect-trip-bytes (expt 2 27))
  (collect-request-handler default-request-handler))

;; counted-pass : (-> A) -> (Values A Tally)
;; RUN's answer, a pass's sweep, and its tally, the trip and the handler
;; put back however it leaves.
(define (counted-pass run)
  (pass-reset!)
  (let ((r (dynamic-wind (lambda () #f) run ended!)))
    (values r (pass-tally))))

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int (*xCallback)(unsigned, void *pCtx, void *P, void *X)
(define profile
  (foreign-callable __collect_safe
    (lambda (mask ctx p x)
      (force!)
      0)
    (unsigned-32 uptr uptr uptr) int))

;; int (*xAuth)(void *pUserData, int action, const char *, const char *, const char *, const char *)
(define authorizer
  (foreign-callable __collect_safe
    (lambda (data action a b c d)
      (force!)
      0)
    (uptr int uptr uptr uptr uptr) int))

;; callbacks-locked : Any
(define callbacks-locked
  (guard (e (#t (list 'raised (describe e))))
    (lock-object profile)
    (lock-object authorizer)
    'locked))

;; int sqlite3_trace_v2(sqlite3*, unsigned uMask, int(*xCallback)(...), void *pCtx)
(define trace-v2
  (bound 'sqlite3_trace_v2 (foreign-procedure "sqlite3_trace_v2" (uptr unsigned-32 uptr uptr) int)))

;; int sqlite3_set_authorizer(sqlite3*, int (*xAuth)(...), void *pUserData)
(define set-authorizer
  (bound 'sqlite3_set_authorizer (foreign-procedure "sqlite3_set_authorizer" (uptr uptr uptr) int)))

;; sqlite-trace-profile, sqlite-trace-row : Natural
;; SQLITE_TRACE_PROFILE, as a statement finishes, and SQLITE_TRACE_ROW, as a
;; step answers a row.
(define sqlite-trace-profile 2)
(define sqlite-trace-row 4)

(define call-with-open-handle (reach connection-library 'call-with-open-handle))

;; traced! : Database -> Void
;; DB given the trace and the authorizer, each answer required 0.
(define (traced! db)
  (let ((rc (call-with-open-handle 'test-conveniences-reentry db
              (lambda (h)
                (let* ((t (trace-v2 h (+ sqlite-trace-profile sqlite-trace-row)
                                    (foreign-callable-entry-point profile) 0))
                       (a (set-authorizer h (foreign-callable-entry-point authorizer) 0)))
                  (list t a))))))
    (unless (equal? rc '(0 0)) (error 'traced! "sqlite3_trace_v2 or sqlite3_set_authorizer did not answer 0" rc))))

;; --- jumped back -----------------------------------------------------------------------------
;; A timer's handler is the caller's code, run between any two critical
;; sections, inside the script's block too. A continuation it captures there,
;; called by a later fire of the same call, jumps back within the block's
;; extent and crosses no winder: call-with-block never sees it. Each
;; statement's prepare claims its byte offset, inside its section, and refuses
;; one the call has passed, so the jump never prepares a statement again (629
;; of 2804 trials returned with a row twice before the claim). A jump inside
;; one statement's own extent meets the statement tier's state, at done, which
;; refuses a second step; one into a section's own wind,
;; call-with-open-handle's refusal.

(define jump-script "insert into j values (1); insert into j values (2)")

;; jumped-at : Pass Positive-Integer -> (U 'no-capture (List Any Any Natural Boolean))
;; In PASS, execute-script! of jump-script on a fresh :memory: connection
;; holding j, empty, a timer's handler run at every tick. At the Ith tick at which some
;; row of j stands it captures a continuation, noting the rows then, by the
;; connection's total-changes; at the first later tick at which more stand,
;; it calls it, once. Answers no-capture when the call returned before that
;; tick; else what the call answered, j's rows in the order inserted, how
;; many stood at the capture, and whether the jump came.
(define (jumped-at pass i)
  (begun! pass)
  (let ((db (open-database ":memory:")))
    (when (eq? pass 'low) (traced! db))
    (tier-run db "create table j (x)")
    (let* ((base (total-changes db))
           (seen 0) (k #f) (at-capture #f) (jumped #f)
           (old (timer-interrupt-handler))
           (answer
            (dynamic-wind
              (lambda ()
                (timer-interrupt-handler
                 (lambda ()
                   (let ((now (- (total-changes db) base))
                         (at-exit (ticked!)))
                     (cond ((and (not k) (> now 0))
                            (set! seen (+ seen 1))
                            (when (= seen i)
                              (captured-at! at-exit)
                              (set! at-capture now)
                              (call/cc (lambda (c) (set! k c)))))
                           ((and k (not jumped) (> now at-capture))
                            (set! jumped #t)
                            (k #f))))
                   (set-timer 1))))
              (lambda ()
                (attempt (lambda ()
                           (call-begun!)
                           (set-timer 1)
                           (let ((r (execute-script! db jump-script)))
                             (set-timer 0)
                             (if (eq? r (if #f #f)) 'no-value r)))))
              (lambda ()
                (set-timer 0)
                (call-ended!)
                (timer-interrupt-handler old))))
           (rows (let loop ((rest (tier-run db "select x from j order by rowid")) (found '()))
                   (if (null? rest) (reverse found) (loop (cdr rest) (cons (vector-ref (car rest) 0) found))))))
      (close-database! db)
      (ended!)
      (if k (list answer rows at-capture jumped) 'no-capture))))

;; jump-kind : (List Any Any Natural Boolean) -> (U Symbol (List 'deviation Any))
;; A trial's outcome: answered, the call answering no value with the
;; script's two rows once each; refused, &sqlite-closed from execute-script!;
;; state-refused, a second step of a statement at done refused by the
;; statement tier; wind-refused, call-with-open-handle's refusal of a
;; re-entry; each of the last three with j's rows a prefix of the script's,
;; none twice, holding those at the capture. Anything else a deviation.
(define (jump-kind r)
  (let ((answer (car r)) (rows (cadr r)) (at (caddr r)))
    (let ((prefix (and (member rows '((1) (1 2))) (>= (length rows) at))))
      (cond ((and (eq? answer 'no-value) (equal? rows '(1 2))) 'answered)
            ((and prefix (equal? answer '(raised (closed execute-script!)))) 'refused)
            ((and prefix (equal? answer '(raised (assertion-violation execute-script! (not-allowed-in-state done)))))
             'state-refused)
            ((and prefix (equal? answer '(raised (assertion-violation execute-script! (re-entered)))))
             'wind-refused)
            (else (list 'deviation r))))))

;; jump-swept : Pass -> (List Any Any Counts)
;; jumped-at in PASS at each I from 1 until the call returns before its Ith
;; capture: the deviations; whether a quarter of the captures were refused
;; at a prepare; and the counts at the end.
(define (jump-swept pass)
  (let loop ((i 1) (kinds '()) (deviations '()))
    (let ((r (guard (e (#t (list 'raised (what-raised e)))) (jumped-at pass i))))
      (if (or (eq? r 'no-capture) (>= i 20000))
          (begin
            (display "  execute-script! jumped back")
            (display (if (eq? pass 'low) ", low trip: captures at " ": captures at "))
            (write (- i 1))
            (display " ticks; kinds ")
            (write kinds)
            (newline)
            (let ((refused (let ((p (assq 'refused kinds))) (if p (cdr p) 0))))
              (list (if (< i 20000) (summarized (reverse deviations)) (list 'no-end-by-20000 (summarized (reverse deviations))))
                    (if (>= (* 4 refused) (- i 1))
                        'a-quarter-refused-at-a-prepare
                        (list 'refused refused 'of (- i 1)))
                    (native-counts))))
          (let ((kind (if (eq? (car r) 'raised) (list 'deviation r) (jump-kind r))))
            (loop (+ i 1)
                  (if (symbol? kind)
                      (let ((p (assq kind kinds)))
                        (if p (cons (cons kind (+ (cdr p) 1)) (remq p kinds)) (cons (cons kind 1) kinds)))
                      kinds)
                  (if (symbol? kind) deviations (cons (cons i (cdr kind)) deviations))))))))

(define jump-name
  "execute-script! jumped back inside its own call, through a continuation a timer's handler captured at each tick from the first at which the script's first row stands until the call returns, and called at the first tick after another row stands: the jump never runs a statement again: the call answers with the script's rows once each, or is refused, with &sqlite-closed at the script's next prepare, or inside a statement's own extent by the statement tier's state or a section's own wind, the rows a prefix of the script's, none twice; at least a quarter of the captures are refused at a prepare; nothing is left counted")

(test-equal jump-name
  (list '() 'a-quarter-refused-at-a-prepare zero-counts)
  (jump-swept 'high))

(test-equal (string-append "the same, its trials under a collect trip of 256 bytes, each connection carrying SQLite's trace and an authorizer, which allocate 32 KiB inside each section that prepares, steps a row or finishes a statement, so a request falls due there and is handled at its exit, where the timer's handler runs: the same verdicts, and collect requests met in the trials, each forced section's request met before the next, and some capture made at a forced section's exit. " jump-name)
  (append (list '() 'a-quarter-refused-at-a-prepare) low-checks (list zero-counts))
  (let-values (((r tally) (counted-pass (lambda () (jump-swept 'low)))))
    (display "  execute-script! jumped back, low trip")
    (tally-shown tally)
    (newline)
    (append (list (car r) (cadr r)) (low-judged tally) (list (caddr r)))))

(test-equal "the trace's and the authorizer's callbacks were locked at the load, and are unlocked once every connection is closed"
  '(locked unlocked)
  (list callbacks-locked
        (guard (e (#t (list 'raised (describe e))))
          (unlock-object authorizer)
          (unlock-object profile)
          'unlocked)))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "conveniences-reentry")

(exit (suite-exit-status runner))
