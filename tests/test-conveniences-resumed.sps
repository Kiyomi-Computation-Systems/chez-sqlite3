#!r6rs
;;; The suite for a convenience re-entered after its statement has left it
;;; (ADR-0016, decision 6; ADR-0020, decision 7; the maintainer's choice of
;;; 2026-11-16, after M3 slice 3's review), in (chez-sqlite3 private
;;; conveniences). Chez's engine remainders are multi-shot, and a timer's,
;;; keyboard's or collect request's handler can capture a continuation
;;; between any two critical sections. So each call of a convenience holds a
;;; flag, set once its statement leaves the call, given back to the cache or
;;; finalized, and every section that touches the statement reads it first:
;;; set, the section touches nothing, and the convenience raises
;;; &sqlite-closed after it.
;;;
;;;   resumed twice   for execute!, query and query-row, at every fuel from 1
;;;                   until the call completes without expiring: an engine's
;;;                   remainder, resumed to its end, then resumed again,
;;;                   warm, while another engine holds the statement at its
;;;                   row; and cold, alone. A remainder taken while the call
;;;                   held its statement raises &sqlite-closed the second time;
;;;                   any other raises it or answers again, touching nothing.
;;;                   One taken inside the library's own wind, the
;;;                   call-with-open-handle a check-out runs in, is refused by
;;;                   that wind, re-entered, before any flag is read
;;;                   The other engine answers its own rows, and the cache ends
;;;                   holding the one statement, ready
;;;   a failed return query-row's return failing, its reset of an insert ...
;;;                   returning answering busy under another's read: the
;;;                   failure has set the flag, so a remainder resumed again
;;;                   raises &sqlite-closed, never the row of the insert the
;;;                   failure rolled back
;;;   the fold        query-fold's remainder resumed twice, at every fuel: an
;;;                   expiry before the hand-over leaves the fold to complete,
;;;                   one inside its wind finalizes the statement; the second
;;;                   resume raises &sqlite-closed or answers again, touching
;;;                   nothing; no statement is left out of the cache or at a
;;;                   row
;;;   the timer       a timer handler captures a continuation at every tick of
;;;                   a fold, and the row re-enters each, with the statement
;;;                   cached, then while the suite holds it at its row: none
;;;                   that the fold had begun calls the procedure again or
;;;                   touches the statement
;;;   the script      execute-script!'s remainder resumed twice: one taken
;;;                   before the script's block refuses, &sqlite-closed, rather
;;;                   than running the script again; one inside it is refused
;;;                   by the block's own wind, re-entered
;;;   two passes      the resumed-twice rows, the failed return's, the fold's
;;;                   and the script's twice: with no collect request in a
;;;                   trial, and under a collect trip of 256 bytes, where a
;;;                   request due inside a critical section is handled at its
;;;                   exit and costs the engine ticks there, so a remainder is
;;;                   taken at a section's exit too, past the call's last
;;;                   section among them: a claim advanced just after its
;;;                   section, not inside it, stepped a statement twice there
;;;                   (M4's closing review, reviewer B's B1). SQLite's trace
;;;                   allocates 32 KiB inside each section that steps a row
;;;                   or finishes a statement, so a request falls due there.
;;;                   Each low row fails by name unless collect requests fell
;;;                   in its trials, unless each such section met its request
;;;                   before the next, which a trip slipped to 256 KiB does
;;;                   not, and unless some first slice expired at such a
;;;                   section's exit, which the high pass never does;
;;;                   execute!'s, query's and query-row's unless a remainder
;;;                   past the return answered again at some fuel, warm or
;;;                   cold
;;;
;;; A remainder taken before the call's first expression is the caller's own:
;;; resumed again, it makes a whole new call, with a flag of its own. Each
;;; trial is judged by what it saw itself: for execute!, query and query-row,
;;; where E1's remainder lay at its expiry, held, past the return or before
;;; the check-out, read from the cache and the statement's runs,
;;; sqlite3_stmt_status's count, which this suite binds; and whether the
;;; second resume stepped the statement. A whole new call steps it, and so
;;; must lie below the first fuel at which a remainder taken past the call's
;;; first expression and before its first section was refused: each trial
;;; begins with a collection, so its first slice runs as every trial's at
;;; that fuel does, unless a collect request falls in it, and a remainder
;;; lies further into the call's first
;;; expressions at each fuel than at the one before. A request that falls in
;;; the first slice costs the engine ticks there, so such a trial's remainder
;;; lies earlier than its fuel says: the bound reads only the trials where
;;; none fell. A bound from the call refused at its first check, slice 3's,
;;; was loose: its raise costs ticks of its own, and it completed at fuel
;;; 75, the script's whole new calls ending at 7 (M3's closing review,
;;; reviewer B). A bound from the last fuel at which the call held its
;;; statement assumed the fuels in order past the first expressions, which a
;;; low trip breaks (M4's closing review, reviewer B's B3).
;;;
;;; The loading procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) make-engine set-timer timer-interrupt-handler collect collect-trip-bytes
              collect-request-handler foreign-procedure foreign-callable foreign-callable-entry-point
              lock-object unlock-object scheme-environment)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
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
(define values-library '(chez-sqlite3 private statement-values))
(define execute! (reach conveniences 'execute!))
(define query (reach conveniences 'query))
(define query-row (reach conveniences 'query-row))
(define query-fold (reach conveniences 'query-fold))
(define execute-script! (reach conveniences 'execute-script!))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define database-cache-count (reach connection-library 'database-cache-count))
(define tracked-statements (reach connection-library 'tracked-statements))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define step! (reach statement-library 'step!))
(define statement-sql (reach statement-library 'statement-sql))
(define statement-state (reach statement-library 'statement-state))
(define checked-out (reach statement-library 'checked-out))
(define returned (reach statement-library 'returned))
(define bind-all! (reach values-library 'bind-all!))
(define column-value (reach values-library 'column-value))
(define made-claim (reach conveniences 'made-claim))
(define call-with-statement-handle (reach statement-library 'call-with-statement-handle))

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_stmt_status(sqlite3_stmt*, int op, int reset), never bound by
;; chez-sqlite3; SQLITE_STMTSTATUS_RUN is 6, at the floor and since. It
;; counts a run when a step starts the statement's program, the first step
;; after a prepare or a reset, as tests/test-transaction-engine.sps reads it.
(define stmt-status (bound 'sqlite3_stmt_status (foreign-procedure "sqlite3_stmt_status" (uptr int int) int)))
(define stmtstatus-run 6)

;; runs : Statement -> Natural
(define (runs st)
  (call-with-statement-handle 'test-conveniences-resumed st 'statement-sql
    (lambda (connection handle sql) (values #f (stmt-status handle stmtstatus-run 0)))))

;; --- the profile trace: a collect request due inside a statement's step -----------------------
;; SQLite's trace fires, with SQLITE_TRACE_ROW, as a step answers a row, and,
;; with SQLITE_TRACE_PROFILE, as a statement finishes: inside the step that
;; reaches done, for query, execute!, query-fold and each statement of a
;; script, and inside the return's reset for query-row (part D's keyboard-in
;; reads it so). In the low pass the callback allocates 32 KiB
;; there, past which a collect request always fell inside a critical
;; section under the low trip, so one falls due inside that section and is
;; handled at its exit, where it costs the engine ticks. Without it a
;; request fell where the call's allocation crossed a chunk, the same point
;; at every fuel once each trial collects first: query-row's and execute!'s
;; low sweeps took no remainder past the return. The callback is
;; __collect_safe: SQLite calls it inside sqlite3_step and sqlite3_reset,
;; which are. It answers 0 and raises nothing. Every connection the engine
;; rows open carries it; it is locked from here to the suite's end.

;; int (*xCallback)(unsigned, void *pCtx, void *P, void *X)
(define profile
  (foreign-callable __collect_safe
    (lambda (mask ctx p x)
      (force!)
      0)
    (unsigned-32 uptr uptr uptr) int))

;; int sqlite3_trace_v2(sqlite3*, unsigned uMask, int(*xCallback)(...), void *pCtx)
(define trace-v2
  (bound 'sqlite3_trace_v2 (foreign-procedure "sqlite3_trace_v2" (uptr unsigned-32 uptr uptr) int)))

;; sqlite-trace-profile, sqlite-trace-row : Natural
;; SQLITE_TRACE_PROFILE, as a statement finishes, and SQLITE_TRACE_ROW, as a
;; step answers a row: each inside the one section that steps or resets the
;; statement, never two in one section.
(define sqlite-trace-profile 2)
(define sqlite-trace-row 4)

(define call-with-open-handle (reach connection-library 'call-with-open-handle))

;; profile-locked : Any
(define profile-locked (guard (e (#t (list 'raised (describe e)))) (lock-object profile) 'locked))

;; traced! : Database -> Void
;; DB given the profile trace, its answer required 0.
(define (traced! db)
  (let ((rc (call-with-open-handle 'test-conveniences-resumed db
              (lambda (h) (trace-v2 h (+ sqlite-trace-profile sqlite-trace-row)
                                    (foreign-callable-entry-point profile) 0)))))
    (unless (eqv? rc 0) (error 'traced! "sqlite3_trace_v2 did not answer 0" rc))))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (sqlite-error-sql e) (sqlite-error-offset e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define void-value (if #f #f))
(define (no-value x) (if (eq? x void-value) 'no-value x))

(define (closed name) (list 'raised (list 'closed name)))

;; re-entered : Symbol -> Any
;; What call-with-open-handle's, or call-with-block's, refusal of a re-entry
;; looks like, from NAME.
(define (re-entered name) (list 'raised (list 'assertion-violation name '(re-entered))))

(define (statement-count) (cdr (assq 'statement (native-counts))))

;; states : Database -> (Listof (Pairof String Symbol))
(define (states db)
  (list-sort (lambda (a b) (string<? (car a) (car b)))
             (let loop ((rest (tracked-statements db)) (found '()))
               (if (null? rest)
                   found
                   (loop (cdr rest)
                         (cons (cons (statement-sql (car rest)) (statement-state (car rest))) found))))))

;; tier-run : Database String -> (Listof Any)
;; SQL run through M2's statement tier: each row's first column, in order.
(define (tier-run db sql)
  (let ((st (prepare-statement db sql)))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let loop ((rows '()))
          (if (step! st)
              (loop (cons (column-value st 0) rows))
              (reverse rows))))
      (lambda () (finalize-statement! st)))))

;; with-fresh : (Database -> Any) -> Any
;; PROC's answer, or what it raised, given a fresh :memory: database holding
;; table n, its rows 1, 2 and 3, and table s, empty, the profile trace on
;; it (below); closed after.
(define (with-fresh proc)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt (lambda ()
                   (set! db (open-database ":memory:"))
                   (traced! db)
                   (tier-run db "create table n (x)")
                   (tier-run db "insert into n values (1), (2), (3)")
                   (tier-run db "create table s (x)")
                   (proc db))))
      (lambda () (when db (guard (e (#t #f)) (close-database! db)))))))

;; quieted! : -> Void
;; A collection now, at a trial's start, with collect-trip-bytes raised to
;; 128 MiB, far above what one trial's runs allocate, so no collect request
;; falls in a trial of the high pass: one costs a run up to a tick
;; (.plans/research/m3-slice-5/, gc-ticks.sps).
(define (quieted!)
  (collect-trip-bytes (expt 2 27))
  (collect))

;; Pass = (U 'high 'low)
;; Each trial of the two passes begins with begun!: quieted!'s collection,
;; then PASS's trip. In the high pass it stays at 2^27. In the low pass it
;; is 256 bytes, below what one call allocates, until the trial ends: a
;; request then falls due all through it, and one due inside a critical
;; section is handled at the section's exit, where it costs the engine
;; ticks, so an expiry can fall at a section's exit, past the call's last
;; among them, where no procedure call follows (.plans/traps.md). Every
;; request the trials meet goes through counted-request, which counts it.

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

;; --- where a remainder lies: at a forced section's exit ----------------------------------------
;; SQLite's trace calls back inside one of the library's critical sections,
;; once a section: each step that answers a row, the step that finishes a
;; statement, and query-row's return (the profile trace, above).
;; In the low pass force! allocates 32 KiB there, so a collect request falls
;; due inside the section and is handled at its exit, the first event check
;; once the section enables interrupts again. The handler's own work costs
;; the engine ticks. Where they run out in it, the engine's timer reads #f
;; at its end, and the engine expires as the handler returns: the remainder
;; lies at that section's exit, before anything after it. A probe's marker,
;; set inside a section and overwritten just after it, read the section's
;; at exactly those fuels, three a section, at the low trip, and at none at
;; the high trip or at 256 KiB (M4's closing review, builder D's
;; exit-probe.sps). So a low row fails by name unless every forced section met
;; its request before the next forced section or its slice's end, which a
;; trip slipped to 256 KiB breaks, a 32 KiB allocation then meeting one
;; about one time in eight; and unless some first slice expired at a forced
;; section's exit, which the high pass, forcing none, never does. Each first
;; slice numbers the forced sections it passes, from 1, and the row shows
;; whose exits were met. The timer is read through Chez's own $tc-field,
;; reached through eval.

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
;; times of 100 (chunk-probe.sps), so it is due as the section ends.
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

;; expired-slice? : Any -> Boolean
;; Whether R, a slice's answer, is an expiry's: (expired E), or E itself.
(define (expired-slice? r) (or (procedure? r) (and (pair? r) (eq? (car r) 'expired))))

;; first-slice : Engine Positive-Integer -> (U (List 'completed Any) (List 'expired Engine))
;; slice, its forced sections numbered and its exit noted for the pass.
(define (first-slice e fuel)
  (set! forced-k 0)
  (set! exit-k #f)
  (set! numbering #t)
  (let ((r (slice e fuel)))
    (set! numbering #f)
    (set! pass-k (max pass-k forced-k))
    (when (and exit-k (expired-slice? r) (not (memv exit-k pass-exits)))
      (set! pass-exits (cons exit-k pass-exits)))
    r))

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

;; requests-judged : Pass Tally -> (Listof Any)
;; In the low pass, low-checks' three, each failing by name.
(define (requests-judged pass tally)
  (if (eq? pass 'low) (low-judged tally) '()))

(define (kind-count kinds k) (let ((p (assq k kinds))) (if p (cdr p) 0)))

;; counted-up : Symbol (Listof (Pairof Symbol Natural)) -> (Listof (Pairof Symbol Natural))
(define (counted-up k kinds)
  (cond ((null? kinds) (list (cons k 1)))
        ((eq? (car (car kinds)) k) (cons (cons k (+ (cdr (car kinds)) 1)) (cdr kinds)))
        (else (cons (car kinds) (counted-up k (cdr kinds))))))

;; summarized : (Listof Any) -> Any
;; () for no deviation; else how many, and the first three.
(define (summarized deviations)
  (if (null? deviations)
      '()
      (list (length deviations)
            (let loop ((rest deviations) (n 0) (kept '()))
              (if (or (null? rest) (= n 3)) (reverse kept) (loop (cdr rest) (+ n 1) (cons (car rest) kept)))))))

;; --- engines ------------------------------------------------------------------------------

;; slice : Engine Positive-Integer -> (U (List 'completed Any) (List 'expired Engine))
;; Each slice's forced sections are judged met or unmet.
(define (slice e fuel)
  (slice-begun!)
  (let ((r (e fuel (lambda (left . vals) (list 'completed (car vals))) (lambda (more) (list 'expired more)))))
    (slice-ended!)
    r))

;; finish : Engine -> Any
;; E's answer, resumed with a large fuel until it completes, at most 1000
;; times.
(define (finish e)
  (let loop ((e e) (n 0))
    (let ((r (slice e 1000000)))
      (cond ((eq? (car r) 'completed) (cadr r))
            ((>= n 1000) 'never-completed)
            (else (loop (cadr r) (+ n 1)))))))

;; until-holding : Engine (-> Boolean) -> (U Engine #f)
;; E resumed one tick at a time until it expires with HOLDING? true: its
;; remainder; #f when it completes first, or after 100000 ticks.
(define (until-holding e holding?)
  (let loop ((e e) (n 0))
    (let ((r (slice e 1)))
      (cond ((eq? (car r) 'completed) #f)
            ((holding?) (cadr r))
            ((>= n 100000) #f)
            (else (loop (cadr r) (+ n 1)))))))

;; sweep : (Positive-Integer -> (List Boolean Boolean (Listof Any))) -> (List Any (Listof Any) Natural)
;; CHECK at each fuel from 1 until the call completes without expiring, at
;; most 5000: that fuel, or no-completion; each fuel's deviations, in order;
;; and how many fuels CHECK found the call holding its statement at the
;; expiry. CHECK answers whether the call expired, whether it held its
;; statement then, and what deviated.
(define (sweep check)
  (let loop ((fuel 1) (deviations '()) (held 0))
    (let* ((r (check fuel))
           (deviations (if (null? (caddr r)) deviations (cons (cons fuel (caddr r)) deviations)))
           (held (if (cadr r) (+ held 1) held)))
      (cond ((not (car r)) (list fuel (reverse deviations) held))
            ((>= fuel 5000) (list 'no-completion-by-5000 (reverse deviations) held))
            (else (loop (+ fuel 1) deviations held))))))

;; named : String (List Any (Listof Any) Natural) -> (List Any Any)
;; RUN's deviations, summarized, and whether it held its statement at some
;; fuel; its completing fuel printed, naming WHAT.
(define (named what run)
  (display "  ")
  (display what)
  (if (integer? (car run))
      (begin (display " completed without expiring at fuel ") (display (car run)))
      (begin (display ": ") (write (car run))))
  (newline)
  (list (if (integer? (car run)) (summarized (cadr run)) (list (car run) (summarized (cadr run))))
        (if (> (caddr run) 0) 'held-at-some-fuel 'never-held)))

;; --- the claim, pure -------------------------------------------------------------------------
;; execute!, query and query-row each hold a claim, made-claim's, made by the
;; call's first expression. The sweeps below and (conveniences-pending)'s
;; hold it through the calls; a claim taken again once its call has ended,
;; position 0 above all, which any remainder taken before the check-out
;; carries, passed them all (M3's closing review, reviewer B's N1: execute!'s
;; remainder at fuels 8 to 14, resumed twice, inserted twice). So these rows
;; hold it whole.

;; claimed : (Listof (List (U Natural #f) Boolean)) -> (Listof Boolean)
;; A fresh claim given each of STEPS, a position and LAST?, in order: what
;; it answered each time.
(define (claimed steps)
  (let ((claim (made-claim)))
    (let loop ((rest steps) (found '()))
      (if (null? rest)
          (reverse found)
          (loop (cdr rest) (cons (claim (car (car rest)) (cadr (car rest))) found))))))

;; after-the-end : (Listof (List (U Natural #f) Boolean))
;; Every kind of claim a run can make once its call has ended: position 0,
;; the check-out's; one the call made; one past it; none, #f, a raise's
;; give-back; each with LAST? and without.
(define after-the-end
  '((0 #f) (0 #t) (1 #f) (2 #f) (3 #f) (4 #f) (4 #t) (#f #f) (#f #t) (0 #f)))

(define (refusals steps) (let loop ((rest steps) (found '())) (if (null? rest) found (loop (cdr rest) (cons #f found)))))

(test-equal "a call's claim, made-claim's, claims each position once, in order, the next whatever it is when given none, and ends at its last: 0, then 0 again refused, 2 refused before 1, 1, none claiming 2, 2 refused, then 3 as the last; once ended, every position is refused, 0 and none included, by a run carrying any"
  (append '(#t #f #f #t #t #f #t) (refusals after-the-end))
  (guard (e (#t (list 'raised (what-raised e))))
    (claimed (append '((0 #f) (0 #f) (2 #f) (1 #f) (#f #f) (2 #f) (3 #t)) after-the-end))))

(test-equal "a claim ended by a raise's give-back, a claim of none as the last, and one ended at its first section: each then refuses every position, 0 included"
  (list (append '(#t #t) (refusals after-the-end))
        (append '(#t) (refusals after-the-end)))
  (guard (e (#t (list 'raised (what-raised e))))
    (let* ((given-back (claimed (append '((0 #f) (#f #t)) after-the-end)))
           (at-first (claimed (append '((0 #t)) after-the-end))))
      (list given-back at-first))))

;; --- execute!, query and query-row: a remainder resumed twice ---------------------------------

(define X "select x + ?1 from n order by x")

;; x-runs : Database -> Natural
;; The runs of every statement DB tracks for X, summed, read through
;; sqlite3_stmt_status: a whole call steps one, and a run past its return
;; none.
(define (x-runs db)
  (let loop ((rest (tracked-statements db)) (n 0))
    (if (null? rest)
        n
        (loop (cdr rest) (if (equal? (statement-sql (car rest)) X) (+ n (runs (car rest))) n)))))

;; phase-at : Database Natural -> (U 'held 'past 'before 'other)
;; Where E1's remainder lay when it was taken, by what it left, BASE the
;; runs of X's statements before E1: held, its statement checked out of the
;; cache, the one tracked; past its return, the statement back in the
;; cache, ready, its runs grown by E1's one; before its check-out, the
;; statement untouched, cached with BASE runs, warm, or none tracked, cold;
;; else other, which no call leaves.
(define (phase-at db base)
  (let ((cached (database-cache-count db)) (tracked (length (tracked-statements db))))
    (cond ((and (= cached 0) (= tracked 1)) 'held)
          ((and (= cached 1) (equal? (states db) (list (cons X 'ready))) (= (x-runs db) (+ base 1))) 'past)
          ((or (and (= tracked 0) (= base 0))
               (and (= cached 1) (equal? (states db) (list (cons X 'ready))) (= (x-runs db) base)))
           'before)
          (else 'other))))

;; Twice = (List Boolean Symbol (Listof Any) Symbol Boolean)
;; Whether the call expired; phase-at's phase, at the expiry; what deviated;
;; the second resume's kind, judged by the trial itself: refused,
;; &sqlite-closed or the library wind's re-entered refusal, stepping
;; nothing; again, its call's answer once more, stepping nothing, taken past
;; the return; new, a whole new call, its answer, stepping X once, taken
;; before the check-out; other, a deviation; none where it completed; and
;; whether no collect request fell in E1's first slice, so the sweep's bound
;; reads it.

;; other-holding : Database (Database Integer -> Any) Pass -> (U Engine #f)
;; E2, RUN with 20 on DB as an engine, run a tick at a time until it holds
;; X's statement at its row: its remainder, or #f. E2 is the suite's
;; instrument, so it runs with the trip raised and the profile trace's
;; allocation off, then PASS's put back: under the low trip it once never
;; reached its row at a warm fuel.
(define (other-holding db run pass)
  (collect-trip-bytes (expt 2 27))
  (set! forcing #f)
  (let ((e (until-holding
            (make-engine (lambda () (attempt (lambda () (no-value (run db 20))))))
            (lambda () (and (= (database-cache-count db) 0)
                            (equal? (states db) (list (cons X 'row))))))))
    (when (eq? pass 'low)
      (set! forcing #t)
      (collect-trip-bytes low-trip))
    e))

;; resumed-twice : Pass Symbol (Database Integer -> Any) Any Any Boolean Positive-Integer -> Twice
;; On a fresh database, in PASS, RUN with 10 as an engine, E1, one slice of
;; FUEL. Expired, its remainder is resumed to its end, answering FIRST, due
;; MINE; then, when WARM, the cache warmed by RUN with 0 before E1, a second
;; engine, E2, RUN with 20, is run a tick at a time until it holds the
;; statement at its row; then E1's remainder is resumed again, answering
;; SECOND, its steps counted by x-runs; then E2 is resumed to its end, due
;; THEIRS. The cache ends holding the one statement, ready, and counted. A
;; second resume that steps X is a whole new call, which the sweep bounds.
(define (resumed-twice pass name run mine theirs warm fuel)
  (begun! pass)
  (let ((outcome
         (with-fresh
          (lambda (db)
            (when warm (run db 0))
            (let* ((base (x-runs db))
                   (met requests)
                   (r (first-slice (make-engine (lambda () (attempt (lambda () (no-value (run db 10)))))) fuel))
                   (clean (= requests met)))
              (if (eq? (car r) 'completed)
                  (list #f 'none (if (equal? (cadr r) mine) '() (list (list 'completed (cadr r)))) 'none clean)
                  (let* ((more (cadr r))
                         (phase (phase-at db base))
                         (first (finish more))
                         (other (and warm (other-holding db run pass)))
                         (before-second (x-runs db))
                         (second (finish more))
                         (stepped (- (x-runs db) before-second))
                         (theirs-answer (cond ((not warm) 'none) (other (finish other)) (else 'never-held-at-a-row)))
                         (end (list (states db) (database-cache-count db) (statement-count)))
                         (kind (cond ((and (member second (list (closed name) (re-entered name))) (eqv? stepped 0))
                                      'refused)
                                     ((and (equal? second mine) (eqv? stepped 0) (eq? phase 'past)) 'again)
                                     ((and (equal? second mine) (eqv? stepped 1) (eq? phase 'before)) 'new)
                                     (else 'other))))
                    (list #t phase
                          (append (if (equal? first mine) '() (list (list 'first first)))
                                  (if (eq? phase 'other) (list (list 'phase (states db))) '())
                                  (if (eq? kind 'other) (list (list 'second phase second 'stepped stepped)) '())
                                  (if (or (not warm) (equal? theirs-answer theirs)) '() (list (list 'theirs theirs-answer)))
                                  (if (equal? end (list (list (cons X 'ready)) 1 1)) '() (list (list 'end end))))
                          kind clean))))))))
    (ended!)
    (if (and (pair? outcome) (eq? (car outcome) 'raised))
        (list #f 'none (list outcome) 'none #t)
        outcome)))

;; twice-sweep : (Positive-Integer -> Twice) -> (List Any (Listof Any) (Listof (Pairof Symbol Natural)) Natural (U Natural #f) Natural)
;; CHECK at every fuel from 1 until the call completes without expiring, at
;; most 5000: that fuel; each fuel's deviations; how many fuels each kind of
;; second resume came at; how many held the statement at the expiry; the
;; first fuel at which one taken before the check-out was refused, the
;; sweep's own bound, a whole new call past it a deviation unless a collect
;; request fell in its first slice; and how many of those. Each trial is
;; judged by itself: a claim taken again once its call had ended, by a
;; remainder between the call's first expression and its check-out,
;; answered again there, and passed every row of this suite (M3's closing
;; review, reviewer B's N1). A bound across fuels, the last at which the
;; call held its statement, failed correct code under a low trip, which
;; orders no fuels (M4's closing review, reviewer B's B3).
(define (twice-sweep check)
  (let loop ((fuel 1) (deviations '()) (kinds '()) (held 0) (refused-at #f) (moved 0))
    (let* ((r (check fuel))
           (kind (list-ref r 3))
           (late (and (eq? kind 'new) refused-at))
           (found (if (and late (list-ref r 4)) (cons (list 'new-past-a-refusal refused-at) (caddr r)) (caddr r)))
           (deviations (if (null? found) deviations (cons (cons fuel found) deviations)))
           (kinds (if (car r) (counted-up kind kinds) kinds))
           (held (if (eq? (cadr r) 'held) (+ held 1) held))
           (refused-at (or refused-at (and (eq? kind 'refused) (eq? (cadr r) 'before) fuel)))
           (moved (if (and late (not (list-ref r 4))) (+ moved 1) moved)))
      (cond ((not (car r)) (list fuel (reverse deviations) kinds held refused-at moved))
            ((>= fuel 5000) (list 'no-completion-by-5000 (reverse deviations) kinds held refused-at moved))
            (else (loop (+ fuel 1) deviations kinds held refused-at moved))))))

;; twice-reported : String Pass (Positive-Integer -> Twice) -> (Values (Listof Any) Natural (Listof (Pairof Symbol Natural)))
;; twice-sweep of CHECK in PASS, printed, naming WHAT, and judged: no
;; deviation; the statement held at some fuel; a refusal before the
;; check-out at some fuel, every whole new call below the first; and, in
;; the low pass, low-judged's three, each failing by name. Then how many second resumes answered again past the return, and the
;; kinds, for both-ways to judge.
(define (twice-reported what pass check)
  (let-values (((r met) (counted-pass (lambda () (twice-sweep check)))))
    (let ((kinds (caddr r)))
      (display "  ")
      (display what)
      (display ": completed without expiring at fuel ")
      (write (car r))
      (display "; second resumes ")
      (write kinds)
      (display "; held at ")
      (write (cadddr r))
      (display " fuels; refused before the check-out first at fuel ")
      (write (list-ref r 4))
      (display "; whole new calls past it, a collect request in the first slice, ")
      (write (list-ref r 5))
      (tally-shown met)
      (newline)
      (values
       (append
        (list (if (integer? (car r)) (summarized (cadr r)) (list (car r) (summarized (cadr r))))
              (if (> (cadddr r) 0) 'held-at-some-fuel 'never-held)
              (if (list-ref r 4) 'refused-before-the-check-out (list 'no-refusal-before-the-check-out kinds)))
        (requests-judged pass met))
       (kind-count kinds 'again)
       kinds))))

;; both-ways : Pass Symbol String (Database Integer -> Any) Any Any -> (Listof Any)
;; The warm sweep's judgments, then the cold's; and, in the low pass, a
;; remainder past the return answering again at some fuel, warm or cold,
;; by name. The return is the same code in both, which differ at the
;; check-out alone; and where a remainder lands past it moved with the
;; heap: query's warm sweep completed at fuel 88 and took none past it in 3
;; of 13 trees whose src/ differed only in transaction.sls, which
;; (chez-sqlite3) loads too, its cold sweep 2 in every tree (M4's closing
;; review, builder D).
(define (both-ways pass name what run mine theirs)
  (let*-values (((suffix) (if (eq? pass 'low) ", low trip" ""))
                ((warm warm-again warm-kinds)
                 (twice-reported (string-append what ", warm, another engine holding its statement at a row" suffix)
                                 pass (lambda (fuel) (resumed-twice pass name run mine theirs #t fuel))))
                ((cold cold-again cold-kinds)
                 (twice-reported (string-append what ", cold, alone" suffix)
                                 pass (lambda (fuel) (resumed-twice pass name run mine theirs #f fuel)))))
    (append warm cold
            (if (eq? pass 'low)
                (list (if (> (+ warm-again cold-again) 0)
                          'answered-again-past-the-return
                          (list 'none-answered-again-past-the-return warm-kinds cold-kinds)))
                '()))))

(define resumed-expected
  (let ((one '(() held-at-some-fuel refused-before-the-check-out)))
    (append one one)))

(define resumed-low-expected
  (let ((one (append '(() held-at-some-fuel refused-before-the-check-out) low-checks)))
    (append one one '(answered-again-past-the-return))))

(define low-said
  "the same, its trials under a collect trip of 256 bytes, so a request falls due in every run and one due inside a section costs ticks at its exit: the same verdicts; a remainder past the return answers again at some fuel, warm or cold; and collect requests met in the trials, each forced section's request met before the next, and some first slice expired at a forced section's exit. ")

(test-begin "conveniences-resumed")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(define query-name
  "query, an engine's remainder resumed twice, at every fuel from 1 until it completes without expiring, warm while another engine holds the statement at its row, and cold alone: the first resume answers its rows; the second, of a remainder taken while it held its statement, raises &sqlite-closed, or re-entered inside the library's own wind, stepping nothing; taken past the return, its statement back in the cache, ready, its runs grown, it raises one of those or answers again, stepping nothing; taken before the check-out, it is refused, or makes a whole new call, stepping the statement once, only below the first fuel at which one taken before the check-out was refused; each trial judged by what it saw itself; the other engine answers its own rows; the cache ends holding the one statement, ready")

(test-equal query-name
  resumed-expected
  (both-ways 'high 'query "query" (lambda (db v) (query db X v))
             '(#(11) #(12) #(13)) '(#(21) #(22) #(23))))

(test-equal (string-append low-said query-name)
  resumed-low-expected
  (both-ways 'low 'query "query" (lambda (db v) (query db X v))
             '(#(11) #(12) #(13)) '(#(21) #(22) #(23))))

(define query-row-name
  "query-row, an engine's remainder resumed twice, at every fuel until it completes without expiring, warm while another engine holds the statement at its row, and cold alone: the second resume of a remainder taken while it held its statement raises &sqlite-closed, or re-entered inside the library's own wind; one past the return answers again, stepping nothing; one before the check-out is refused, or makes a whole new call only below the first fuel at which one was refused; the other engine answers its own first row; the cache ends holding the one statement, ready")

(test-equal query-row-name
  resumed-expected
  (both-ways 'high 'query-row "query-row" (lambda (db v) (query-row db X v)) '#(11) '#(21)))

(test-equal (string-append low-said query-row-name)
  resumed-low-expected
  (both-ways 'low 'query-row "query-row" (lambda (db v) (query-row db X v)) '#(11) '#(21)))

(define execute-name
  "execute!, an engine's remainder resumed twice, at every fuel until it completes without expiring, warm while another engine holds the statement at its row, and cold alone: the second resume of a remainder taken while it held its statement raises &sqlite-closed, or re-entered inside the library's own wind; one past the return answers again, stepping nothing; one before the check-out is refused, or makes a whole new call only below the first fuel at which one was refused; the other engine runs its statement to its end; the cache ends holding the one statement, ready")

(test-equal execute-name
  resumed-expected
  (both-ways 'high 'execute! "execute!" (lambda (db v) (no-value (execute! db X v))) 'no-value 'no-value))

(test-equal (string-append low-said execute-name)
  resumed-low-expected
  (both-ways 'low 'execute! "execute!" (lambda (db v) (no-value (execute! db X v))) 'no-value 'no-value))

;; --- query-row, its return failing: a remainder resumed twice ----------------------------------
;; A return that fails finalizes the statement, and has set the call's flag
;; all the same: the statement has left the call. query-row of a multi-row
;; insert ... returning, under another connection's read, answers its first
;; row, then its reset commits, answers busy, and rolls the insert back
;; (part A's busy-reset.sps).

(define returning "insert into t values (1), (2) returning x")

;; failed-return-resumed-twice : Pass Positive-Integer -> (List Boolean Boolean (Listof Any))
;; On a fresh file holding t, x unique, its one row 0, and a second
;; connection holding a read of it, query-row of RETURNING as an engine,
;; one slice of FUEL: whether it expired; whether it then held its
;; statement; and what deviated. Its remainder resumed to its end raises
;; the reset's busy; resumed again, &sqlite-closed, or re-entered, and,
;; taken while the call did not hold its statement, the busy again, of the
;; same call's tail or of a whole new call; never the row. Nothing is left
;; tracked or cached, and t holds 0 alone. In PASS.
(define (failed-return-resumed-twice pass fuel)
  (begun! pass)
  (let ((outcome
         (guard (e (#t (list 'raised (what-raised e))))
           (call-with-temp-directory
            (lambda (dir)
              (let* ((path (string-append dir "/t.db"))
                     (db (open-database path))
                     (reader #f)
                     (held-read #f))
                (dynamic-wind
                  (lambda () #f)
                  (lambda ()
                    (tier-run db "create table t (x unique)")
                    (tier-run db "insert into t values (0)")
                    (traced! db)
                    (set! reader (open-database path))
                    (set! held-read (prepare-statement reader "select x from t"))
                    (step! held-read)
                    (let* ((busy (list 'raised (list 'sqlite-error 'query-row 'busy 'busy returning #f)))
                           (r (first-slice (make-engine (lambda () (attempt (lambda () (query-row db returning))))) fuel)))
                      (if (eq? (car r) 'completed)
                          (list #f #f (if (equal? (cadr r) busy) '() (list (list 'completed (cadr r)))))
                          (let* ((more (cadr r))
                                 (held (and (= (database-cache-count db) 0) (= (length (tracked-statements db)) 1)))
                                 (first (finish more))
                                 (second (finish more))
                                 (end (list (states db) (database-cache-count db) (tier-run db "select x from t"))))
                            (list #t held
                                  (append (if (equal? first busy) '() (list (list 'first first)))
                                          (if (or (member second (list (closed 'query-row) (re-entered 'query-row)))
                                                  (and (not held) (equal? second busy)))
                                              '()
                                              (list (list 'second (if held 'held 'not-held) second)))
                                          (if (equal? end '(() 0 (0))) '() (list (list 'end end)))))))))
                  (lambda ()
                    (when held-read (guard (e (#t #f)) (finalize-statement! held-read)))
                    (when reader (guard (e (#t #f)) (close-database! reader)))
                    (guard (e (#t #f)) (close-database! db))))))))))
    (ended!)
    (if (and (pair? outcome) (eq? (car outcome) 'raised))
        (list #f #f (list outcome))
        outcome)))

;; passed : String Pass (Pass Positive-Integer -> (List Boolean Boolean (Listof Any))) -> (Listof Any)
;; sweep of CHECK in PASS, named WHAT, and, in the low pass, its tally
;; shown and low-judged's three.
(define (passed what pass check)
  (let-values (((run met) (counted-pass (lambda () (sweep (lambda (fuel) (check pass fuel)))))))
    (when (eq? pass 'low)
      (display "  ")
      (display what)
      (display ", low trip")
      (tally-shown met)
      (newline))
    (append (named (if (eq? pass 'low) (string-append what ", low trip") what) run)
            (requests-judged pass met))))

(define failed-return-name
  "query-row, its return failing, an engine's remainder resumed twice, at every fuel from 1 until it completes without expiring: an insert ... returning under another connection's read answers its row, then its reset answers busy, the insert rolled back; the second resume of a remainder taken while it held its statement raises &sqlite-closed, or re-entered, never the row again, the failed return having set the flag; nothing is left tracked or cached")

(test-equal failed-return-name
  (list '() 'held-at-some-fuel)
  (passed "query-row, its return failing, resumed twice" 'high failed-return-resumed-twice))

(test-equal (string-append "the same, its trials under a collect trip of 256 bytes: the same verdicts, and collect requests met in the trials, each forced section's request met before the next, and some first slice expired at a forced section's exit. " failed-return-name)
  (append (list '() 'held-at-some-fuel) low-checks)
  (passed "query-row, its return failing, resumed twice" 'low failed-return-resumed-twice))

;; --- query-fold: a remainder resumed twice ----------------------------------------------------

(define (sum acc row) (+ acc (vector-ref row 0)))

;; fold-resumed-twice : Pass Positive-Integer -> (List Boolean Boolean (Listof Any))
;; On a fresh database whose cache holds X's statement, query-fold of X with
;; 10 as an engine, one slice of FUEL: whether it expired; whether its
;; statement was then finalized, an expiry inside the fold's wind having
;; finished it, or else cached, ready, the expiry before the hand-over or
;; after the return; and what deviated. Its remainder resumed to its end
;; answers the fold, 36, when the statement was cached, and &sqlite-closed
;; when it was finalized, or 36 when the expiry fell past the loop's last
;; section, the fold done; resumed again, &sqlite-closed, or the library's
;; own wind's re-entered, or 36 again where the first resume answered it.
;; The cache ends as the first resume left it: holding the one statement,
;; ready, or none. In PASS.
(define (fold-resumed-twice pass fuel)
  (begun! pass)
  (let ((outcome
         (with-fresh
          (lambda (db)
            (query-fold db X sum 0 0)
            (let ((r (first-slice (make-engine (lambda () (attempt (lambda () (query-fold db X sum 0 10))))) fuel)))
              (if (eq? (car r) 'completed)
                  (list #f #f (if (equal? (cadr r) 36) '() (list (list 'completed (cadr r)))))
                  (let* ((more (cadr r))
                         (finalized (and (= (database-cache-count db) 0) (null? (states db))))
                         (cached (and (= (database-cache-count db) 1) (equal? (states db) (list (cons X 'ready)))))
                         (first (finish more))
                         (second (finish more))
                         (end (list (states db) (database-cache-count db) (statement-count))))
                    (list #t finalized
                          (append (if (or finalized cached) '() (list (list 'phase (states db))))
                                  (if (or (equal? first 36) (and finalized (equal? first (closed 'query-fold))))
                                      '()
                                      (list (list 'first (if finalized 'finalized 'cached) first)))
                                  (if (or (member second (list (closed 'query-fold) (re-entered 'query-fold)))
                                          (and (equal? first 36) (equal? second 36)))
                                      '()
                                      (list (list 'second second)))
                                  (if (equal? end (if finalized '(() 0 0) (list (list (cons X 'ready)) 1 1)))
                                      '()
                                      (list (list 'end end))))))))))))
    (ended!)
    (if (and (pair? outcome) (eq? (car outcome) 'raised))
        (list #f #f (list outcome))
        outcome)))

(define fold-name
  "query-fold, an engine's remainder resumed twice, at every fuel from 1 until it completes without expiring: an expiry before the hand-over leaves the fold to complete, 36, and one inside its wind finalizes the statement, so the resume raises &sqlite-closed, unless the loop had done; the second resume raises &sqlite-closed, or re-entered inside the library's own wind, or answers 36 again where the first did; the cache ends holding the one statement, ready, or none, and nothing is left out of it")

(test-equal fold-name
  (list '() 'held-at-some-fuel)
  (passed "query-fold, resumed twice" 'high fold-resumed-twice))

(test-equal (string-append "the same, its trials under a collect trip of 256 bytes: the same verdicts, and collect requests met in the trials, each forced section's request met before the next, and some first slice expired at a forced section's exit. " fold-name)
  (append (list '() 'held-at-some-fuel) low-checks)
  (passed "query-fold, resumed twice" 'low fold-resumed-twice))

;; --- query-fold: every continuation a timer handler captured --------------------------------
;; A timer handler is the caller's code, and runs between any two critical
;; sections: it captures a continuation at every tick of a normal fold, with
;; the phase it was taken in. Every one is re-entered after the fold has
;; returned, first while the cache holds the statement, then while the suite
;; holds it, checked out, at its first row, 101. A continuation taken before
;; the hand-over, head, raises &sqlite-closed, or re-entered inside the
;; check-out's own wind, or, taken before the call's
;; first expression, makes a whole new fold: 36, the procedure called three
;; times. One taken while the fold held its statement, held, raises
;; &sqlite-closed, or call-with-open-handle's re-entered, or, past the
;; fold's last section, answers 36 again; one after the return, tail, answers
;; 36 again. None but a whole new fold calls the procedure: a call is counted
;; by the row it is given, a fresh vector each, so a continuation taken
;; inside the procedure, re-entered, finishes that call, and calls nothing.

;; timer-reentries : Database -> (List Any Natural (Listof (List Symbol Any Natural)) (Listof ...) Any Any)
(define (timer-reentries db)
  (let ((rows (make-eq-hashtable)) (capturing #f) (saved '()) (return-to #f)
        (old (timer-interrupt-handler)))
    ;; calls : -> Natural
    ;; How many calls of the procedure the folds made: the rows it was given.
    (define (calls) (hashtable-size rows))
    (define (counted acc row) (hashtable-set! rows row #t) (sum acc row))
    (define (phase)
      (cond ((= (database-cache-count db) 0) 'held)
            ((= (calls) 0) 'head)
            (else 'tail)))
    (define (fold-once)
      (set! capturing #t)
      (set-timer 1)
      (let ((r (attempt (lambda () (query-fold db X counted 0 10)))))
        (set! capturing #f)
        (set-timer 0)
        (if return-to (return-to r) r)))
    (define (re-enter-each)
      (let loop ((rest (reverse saved)) (outcomes '()))
        (if (null? rest)
            (reverse outcomes)
            (let* ((before (calls))
                   (r (call/cc (lambda (back) (set! return-to back) ((car (car rest)) #f))))
                   (delta (- (calls) before)))
              (loop (cdr rest) (cons (list (cdr (car rest)) r delta) outcomes))))))
    (dynamic-wind
      (lambda ()
        (timer-interrupt-handler
         (lambda ()
           (when capturing
             (let ((now (phase)))
               (call/cc (lambda (k) (set! saved (cons (cons k now) saved))))
               (when capturing (set-timer 1)))))))
      (lambda ()
        (let* ((first (fold-once))
               (first-calls (calls))
               (cached-pass (re-enter-each))
               (held (checked-out 'the-suite db X #f #f))
               (bound (bind-all! held 100))
               (stepped (step! held))
               (held-pass (re-enter-each))
               (held-after (list (statement-state held) (column-value held 0)))
               (given-back (returned 'the-suite held)))
          (list first first-calls cached-pass held-pass held-after
                (list (states db) (database-cache-count db) (statement-count)))))
      (lambda ()
        (set! capturing #f)
        (set-timer 0)
        (timer-interrupt-handler old)))))

;; reentry-deviations : (Listof (List Symbol Any Natural)) -> (Listof Any)
(define (reentry-deviations outcomes)
  (filter (lambda (o)
            (let ((phase (car o)) (r (cadr o)) (delta (caddr o)))
              (not (case phase
                     ((head) (or (and (member r (list (closed 'query-fold) (re-entered 'query-fold))) (= delta 0))
                                 (and (equal? r 36) (= delta 3))))
                     ((held) (and (= delta 0)
                                  (or (equal? r (closed 'query-fold)) (equal? r (re-entered 'query-fold))
                                      (equal? r 36))))
                     (else (and (equal? r 36) (= delta 0)))))))
          outcomes))

;; refused-held : (Listof (List Symbol Any Natural)) -> Symbol
(define (refused-held outcomes)
  (if (exists (lambda (o) (and (eq? (car o) 'held) (equal? (cadr o) (closed 'query-fold)))) outcomes)
      'some-held-refused
      'no-held-refused))

(test-equal "query-fold re-entered through every continuation a timer handler captured at each tick of a normal fold, after it returned, the statement cached and then held by the suite at its row: none the fold had begun calls the procedure again or touches the statement; those it held raise &sqlite-closed or re-entered, or answer 36 again past its last section; the suite's statement stays at its first row, and the cache ends holding the one statement, ready"
  (list 36 3 '() 'some-held-refused '() 'some-held-refused '(row 101) (list (list (cons X 'ready)) 1 1))
  (let ((r (with-fresh
            (lambda (db)
              (query-fold db X sum 0 0)
              (timer-reentries db)))))
    (if (and (pair? r) (eq? (car r) 'raised))
        r
        (let ((cached-pass (caddr r)) (held-pass (cadddr r)))
          (display "  continuations captured: ")
          (display (length cached-pass))
          (newline)
          (list (car r) (cadr r)
                (summarized (reentry-deviations cached-pass)) (refused-held cached-pass)
                (summarized (reentry-deviations held-pass)) (refused-held held-pass)
                (list-ref r 4) (list-ref r 5))))))

;; --- execute-script!: a remainder resumed twice ----------------------------------------------

(define S "insert into s values (1); insert into s values (2); insert into s values (3)")

;; script-resumed-twice : Pass Positive-Integer -> (List Boolean Boolean (Listof Any) Boolean Boolean Boolean)
;; On a fresh database, in PASS, execute-script! of S as an engine, one
;; slice of FUEL: whether it expired; #f; what deviated; whether its second
;; resume made a whole new call; whether it raised &sqlite-closed, the rows
;; as the first left them; and whether no collect request fell in the first
;; slice, so the sweep's bound reads it. Its remainder resumed to its end completes,
;; the rows (1 2 3), or is refused by the block's wind, re-entered, the
;; statements before the expiry standing. Resumed again, it raises
;; &sqlite-closed, or re-entered, or answers again past the block, each
;; leaving the rows as they were; or, taken before the call's first
;; expression, makes a whole new call, the script's rows twice.
(define (script-resumed-twice pass fuel)
  (begun! pass)
  (let ((outcome
         (with-fresh
          (lambda (db)
            (let* ((met requests)
                   (r (first-slice (make-engine (lambda () (attempt (lambda () (no-value (execute-script! db S)))))) fuel))
                   (clean (= requests met))
                   (rows (lambda () (tier-run db "select x from s order by x"))))
              (if (eq? (car r) 'completed)
                  (list #f #f (if (and (equal? (cadr r) 'no-value) (equal? (rows) '(1 2 3)))
                                  '()
                                  (list (list 'completed (cadr r) (rows))))
                        #f #f clean)
                  (let* ((more (cadr r))
                         (first (finish more))
                         (rows1 (rows))
                         (second (finish more))
                         (rows2 (rows))
                         (whole-new (and (equal? second 'no-value)
                                         (equal? rows2 (list-sort < (append rows1 '(1 2 3)))))))
                    (list #t #f
                          (append (if (or (and (equal? first 'no-value) (equal? rows1 '(1 2 3)))
                                          (and (equal? first (re-entered* 'execute-script!))
                                               (member rows1 '(() (1) (1 2) (1 2 3)))))
                                      '()
                                      (list (list 'first first rows1)))
                                  (if (or whole-new
                                          (and (member second (list (closed 'execute-script!)
                                                                    (re-entered* 'execute-script!)
                                                                    'no-value))
                                               (equal? rows2 rows1)))
                                      '()
                                      (list (list 'second second rows2)))
                                  (let ((counts (native-counts)))
                                    (if (equal? counts '((block . 0) (connection . 1) (statement . 0)))
                                        '()
                                        (list (list 'counts counts)))))
                          whole-new
                          (and (equal? second (closed 'execute-script!)) (equal? rows2 rows1))
                          clean))))))))
    (ended!)
    (if (and (pair? outcome) (eq? (car outcome) 'raised))
        (list #f #f (list outcome) #f #f #t)
        outcome)))

;; re-entered* : Symbol -> Any
;; call-with-block's refusal of a re-entry, from NAME, its irritants none.
(define (re-entered* name) (list 'raised (list 'assertion-violation name '())))

;; script-reported : Pass -> (Listof Any)
;; script-resumed-twice swept in PASS, printed, and judged: no deviation;
;; every whole new call, of a trial whose first slice met no collect
;; request, below the first fuel at which the second resume raised
;; &sqlite-closed; and, in the low pass, low-judged's three.
(define (script-reported pass)
  (let* ((whole-new '())
         (moved 0)
         (refused-at #f))
    (let-values (((run met)
                  (counted-pass
                   (lambda ()
                     (sweep (lambda (fuel)
                              (let ((r (script-resumed-twice pass fuel)))
                                (when (cadddr r)
                                  (if (list-ref r 5)
                                      (set! whole-new (cons fuel whole-new))
                                      (set! moved (+ moved 1))))
                                (when (and (car (cddddr r)) (not refused-at)) (set! refused-at fuel))
                                (list (car r) (cadr r) (caddr r)))))))))
      (display "  execute-script!, resumed twice")
      (when (eq? pass 'low) (display ", low trip"))
      (display ", completed without expiring at fuel ")
      (display (car run))
      (display "; whole new calls at fuels ")
      (write (reverse whole-new))
      (display "; refused with &sqlite-closed first at fuel ")
      (write refused-at)
      (display "; whole new calls left out, a collect request in the first slice, ")
      (write moved)
      (tally-shown met)
      (newline)
      (append
       (list (if (integer? (car run)) (summarized (cadr run)) (list (car run) (summarized (cadr run))))
             (if (and refused-at (for-all (lambda (f) (< f refused-at)) whole-new))
                 'whole-new-calls-only-below-a-refusal
                 (list 'whole-new-calls-at (reverse whole-new) 'refused-first-at refused-at)))
       (requests-judged pass met)))))

(define script-name
  "execute-script!, an engine's remainder resumed twice, at every fuel from 1 until it completes without expiring: the first resume completes or is refused by the block's wind; the second, of a remainder taken before the block, raises &sqlite-closed rather than running the script again, and of one inside the block is refused; a whole new call comes only from a remainder taken before the call's first expression, at a fuel below the first at which the second resume raised &sqlite-closed")

(test-equal script-name
  (list '() 'whole-new-calls-only-below-a-refusal)
  (script-reported 'high))

(test-equal (string-append "the same, its trials under a collect trip of 256 bytes: the same verdicts, and collect requests met in the trials, each forced section's request met before the next, and some first slice expired at a forced section's exit. " script-name)
  (append (list '() 'whole-new-calls-only-below-a-refusal) low-checks)
  (script-reported 'low))

(test-equal "the profile trace's callback was locked at the load, and is unlocked once every connection is closed"
  '(locked unlocked)
  (list profile-locked
        (guard (e (#t (list 'raised (describe e))))
          (unlock-object profile)
          'unlocked)))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "conveniences-resumed")

(exit (suite-exit-status runner))
