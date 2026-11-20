#!r6rs
;;; The suite for with-transaction under engines (ADR-0017), in (chez-sqlite3
;;; private transaction). An engine spends no ticks inside a critical section,
;;; so each expiry falls between sections; each is an escape, which runs
;;; with-transaction's after thunks, and the resume runs the before thunks
;;; again.
;;;
;;;   the sweeps     an engine around with-transaction, at the outer level
;;;                  and nested, at every fuel from 1 until the call
;;;                  completes without expiring, on a fresh connection each
;;;                  fuel, resumed to the end after each expiry: it commits
;;;                  once, or raises &sqlite-transaction-ended, never
;;;                  anything else; its level begins once; it never commits
;;;                  what an expiry rolled back, and never steps a COMMIT,
;;;                  RELEASE or rollback once ENDED is set, read by each
;;;                  statement's runs, sqlite3_stmt_status's count, and the
;;;                  extended code. The fuels are printed: where each outcome
;;;                  begins, and the fuel that completes; each outcome must be
;;;                  seen, and the completing fuel's must commit
;;;   before begun   an expiry before the BEGIN's step answers rolls nothing
;;;                  back, and the resume begins and commits
;;;   a second resume
;;;                  a remainder resumed again once its call has ended, at
;;;                  every fuel's first expiry, the second resume sliced one
;;;                  tick at a time: it checks out, steps and returns none
;;;                  of with-transaction's statements, read between every
;;;                  slice by the cache's count and the statements' states
;;;                  and runs, and at its end by the extended code. This is
;;;                  the row that settles ADR-0017's open question: ENDED is
;;;                  checked-out's check
;;;   no cut SQL     every fuel's first remainder resumed to its end, then
;;;                  again: the connection tracks no SQL but the allowed, its
;;;                  savepoints named in full, and the extended code is 0. A
;;;                  remainder resumed twice from inside number->string
;;;                  answers "" on Chez 10.4.0
;;;   once           O7 nested, a failed RELEASE rolled back, under an engine
;;;                  at every fuel: the rollback is tried once, read by the
;;;                  tracked statements, the extended code and the runs
;;;   left behind    O7 nested, under an engine at every fuel, once the outer
;;;                  call has returned: none of with-transaction's statements
;;;                  is tracked failed or checked out and left, the depth is
;;;                  0, and a later with-transaction commits
;;;   the siblings   an engine taken inside an outer call and resumed inside a
;;;                  sibling level: the resume leaves the sibling, which rolls
;;;                  back and raises the ended condition
;;;   the claim      every fuel's first remainder resumed to its end, then
;;;                  again: a second level only from a whole new call, the
;;;                  call's claim, made by its first expression, refusing a
;;;                  second run at the BEGIN
;;;   low passes     the resumed-while-pending row, the claim's row and its
;;;                  re-entry row again, each trial under a collect trip of
;;;                  256 bytes from its start to its end, its connection
;;;                  carrying SQLite's trace, which allocates 32 KiB as a step
;;;                  answers a row or a statement finishes, the BEGIN inside
;;;                  its own section among them: a request due inside a
;;;                  critical section is handled at its exit and costs the
;;;                  engine ticks there, so a remainder, or a timer's
;;;                  continuation, is taken at the BEGIN's exit too, where a
;;;                  claim taken just after the section, not inside it,
;;;                  passes both rows. Each low row fails by name unless
;;;                  collect requests fell in its trials, unless each section
;;;                  the trace forces met its request before the next, which
;;;                  a trip slipped to 256 KiB does not, and unless some
;;;                  first slice, or timer, ran out at such a section's exit,
;;;                  which the high pass never does. A whole-suite trip of
;;;                  256 bytes fails four rows on correct code, so the low
;;;                  passes are built row by row
;;;   the plan       another engine's BEGIN at the call's first expiry: the
;;;                  resumed call plans its level in the BEGIN's own section,
;;;                  so it makes a savepoint, never a refused BEGIN that takes
;;;                  its lock
;;;   the refusal    a timer that steps the caller's tracked select to its
;;;                  row at any tick: the inner call is refused, or begins,
;;;                  never a SAVEPOINT failed beside the row, the refusal's
;;;                  pass sharing the BEGIN's section; and with an untracked
;;;                  select, a begin that failed rolls nothing back
;;;
;;; Every sweep takes a fresh connection, and a fresh engine, at every fuel,
;;; and fails by name when too few of its trials reached past the call's
;;; first section.
;;;
;;; Reached through eval under a guard. Every computation that can raise
;;; runs under a guard with a sentinel of its own. Effects run in order,
;;; through let* and named lets, never map.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) make-engine foreign-procedure timer-interrupt-handler set-timer list-head
              disable-interrupts enable-interrupts collect collect-trip-bytes collect-request-handler
              foreign-callable foreign-callable-entry-point lock-object unlock-object scheme-environment)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-closed? sqlite-transaction-ended?))

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
(define connection-library '(chez-sqlite3 private connection))
(define statement-library '(chez-sqlite3 private statement))
(define with-transaction (reach public 'with-transaction))
(define open-database (reach public 'open-database))
(define close-database! (reach public 'close-database!))
(define execute! (reach public 'execute!))
(define query-row (reach public 'query-row))
(define in-transaction? (reach public 'in-transaction?))
(define statement-sql (reach public 'statement-sql))
(define statement-state (reach statement-library 'statement-state))
(define call-with-statement-handle (reach statement-library 'call-with-statement-handle))
(define tracked-statements (reach connection-library 'tracked-statements))
(define call-with-open-handle (reach connection-library 'call-with-open-handle))
(define database-cache-count (reach connection-library 'database-cache-count))
(define database-depth (reach connection-library 'database-depth))
(define prepare-statement (reach public 'prepare-statement))
(define finalize-statement! (reach public 'finalize-statement!))
(define step! (reach public 'step!))
(define query (reach public 'query))
(define sqlite3-extended-errcode (reach '(chez-sqlite3 private native) 'sqlite3-extended-errcode))
(define database-cache-check-out! (reach connection-library 'database-cache-check-out!))
(define database-cache-return! (reach connection-library 'database-cache-return!))
(define sqlite3-interrupt (reach '(chez-sqlite3 private native) 'sqlite3-interrupt))

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_stmt_status(sqlite3_stmt*, int op, int reset), never bound by
;; chez-sqlite3; SQLITE_STMTSTATUS_RUN is 6, at the floor and since. It
;; counts a run when a step starts the statement's program, the first step
;; after a prepare or a reset. A step that fails at its entry, as an
;; interrupted one does beside a held row, starts none and counts none, so
;; no row reads runs where an interrupt may land, and none here is
;; interrupted.
(define stmt-status (bound 'sqlite3_stmt_status (foreign-procedure "sqlite3_stmt_status" (uptr int int) int)))
(define stmtstatus-run 6)

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

(define (what-raised e)
  (cond ((sqlite-transaction-ended? e) (list 'transaction-ended (who-of e)))
        ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        ((condition? e) (list 'other (describe e)))
        (else (list 'value e))))

(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define (extended db) (call-with-open-handle 'test-transaction-engine db sqlite3-extended-errcode))

(define (runs st)
  (call-with-statement-handle 'test-transaction-engine st 'statement-sql
    (lambda (connection handle sql) (values #f (stmt-status handle stmtstatus-run 0)))))

(define (prefix? p s) (and (<= (string-length p) (string-length s))
                           (string=? p (substring s 0 (string-length p)))))

(define (own-sql? s)
  (or (member s '("BEGIN DEFERRED" "BEGIN IMMEDIATE" "BEGIN EXCLUSIVE" "COMMIT" "ROLLBACK"))
      (prefix? "SAVEPOINT chez_sqlite3_" s) (prefix? "RELEASE chez_sqlite3_" s)
      (prefix? "ROLLBACK TO chez_sqlite3_" s)))

;; own-statements : Database -> (Listof (List String Symbol Integer))
;; with-transaction's statements DB tracks, oldest first, with their states
;; and runs.
(define (own-statements db)
  (let loop ((rest (tracked-statements db)) (found '()))
    (if (null? rest)
        (reverse found)
        (let ((sql (statement-sql (car rest))))
          (loop (cdr rest)
                (if (own-sql? sql)
                    (cons (list sql (statement-state (car rest)) (runs (car rest))) found)
                    found))))))

;; runs-of : (Listof (List String Symbol Integer)) String -> Integer
;; The runs of SQL's tracked statement, 0 when none is tracked.
(define (runs-of statements sql)
  (let ((found (filter (lambda (s) (string=? (car s) sql)) statements)))
    (if (null? found) 0 (caddr (car found)))))

;; own-runs : Database -> (Listof (List String Integer Statement))
;; with-transaction's statements DB tracks, with their runs and themselves.
(define (own-runs db)
  (let loop ((rest (tracked-statements db)) (found '()))
    (if (null? rest)
        (reverse found)
        (let ((sql (statement-sql (car rest))))
          (loop (cdr rest)
                (if (own-sql? sql) (cons (list sql (runs (car rest)) (car rest)) found) found))))))

;; not-ready : (Listof (List String Symbol Integer)) -> (Listof Any)
(define (not-ready statements)
  (filter (lambda (s) (not (eq? (cadr s) 'ready))) statements))

(define temp-dir (guard (e (#t #f)) (make-process-temp-directory)))
(define case-number 0)
(define (fresh-path)
  (set! case-number (+ case-number 1))
  (string-append (or temp-dir "/nonexistent") "/case-" (number->string case-number) ".db"))

;; with-files : (Database Database -> Any) -> Any
;; PROC's answer, or what it raised, given two connections to a fresh file
;; holding t; both closed after.
(define (with-files proc)
  (let ((db #f) (db2 #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt (lambda ()
                   (let ((path (fresh-path)))
                     (set! db (open-database path))
                     (execute! db "create table t (x)")
                     (set! db2 (open-database path))
                     (proc db db2)))))
      (lambda ()
        (when db2 (guard (e (#t #f)) (close-database! db2)))
        (when db (guard (e (#t #f)) (close-database! db)))))))

;; complete, expire : the engine's procedures: a completion's answer, and
;; the remainder.
(define (complete left . vals) (list 'completed (car vals)))
(define (expire more) more)

;; slice : Engine Positive-Integer -> (U (List 'completed Any) Engine)
;; E run for FUEL ticks, its forced sections judged met or unmet.
(define (slice e fuel)
  (slice-begun!)
  (let ((r (e fuel complete expire)))
    (slice-ended!)
    r))

;; finish : Engine Positive-Integer -> Any
;; The answer of E, an engine's remainder, resumed with FUEL a slice until
;; it completes, at most 100000 times.
(define (finish e fuel)
  (let loop ((e e) (n 0))
    (let ((next (slice e fuel)))
      (cond ((pair? next) (cadr next))
            ((>= n 100000) 'never-completed)
            (else (loop next (+ n 1)))))))

;; engine-run : (-> Any) Positive-Integer -> (List Any Boolean)
;; THUNK's answer, run in an engine of FUEL ticks a slice and resumed with
;; FUEL again after each expiry, at most 100000 times; and whether it
;; expired at all.
(define (engine-run thunk fuel)
  (let loop ((e (make-engine thunk)) (expired #f) (n 0))
    (let ((next (e fuel (lambda (left . vals) (list 'completed (car vals))) (lambda (more) more))))
      (cond ((pair? next) (list (cadr next) expired))
            ((>= n 100000) (list 'never-completed #t))
            (else (loop next #t (+ n 1)))))))

;; sweep : (Positive-Integer -> (List Boolean Any Any)) Positive-Integer
;;         -> (List Any (Listof Any) (Listof (List Positive-Integer Any)))
;; CHECK at each fuel from 1, until a fuel at which the call completed
;; without expiring, at most CAP: that fuel, each fuel's deviation, in
;; order, and the fuels at which the outcome's kind changed, with the kind.
;; CHECK answers whether the call expired, #f or what deviated, and the
;; outcome's kind.
(define (sweep check cap)
  (let loop ((fuel 1) (found '()) (kinds '()) (last #f))
    (let* ((r (check fuel))
           (more (if (cadr r) (cons (list fuel (cadr r)) found) found))
           (kinds* (if (equal? (caddr r) last) kinds (cons (list fuel (caddr r)) kinds))))
      (cond ((not (car r)) (list fuel (reverse more) (reverse kinds*)))
            ((>= fuel cap) (list (list 'no-completion-by cap) (reverse more) (reverse kinds*)))
            (else (loop (+ fuel 1) more kinds* (caddr r)))))))

;; named : String (List Any (Listof Any) (Listof Any)) -> (Listof Any)
;; RUN's deviations, its completing fuel and its outcomes' first fuels
;; printed, naming WHAT.
(define (named what run)
  (display "  ")
  (display what)
  (display ": completed without expiring at fuel ")
  (write (car run))
  (display "; each outcome from the fuel ")
  (write (caddr run))
  (newline)
  (if (integer? (car run)) (cadr run) (cons (car run) (cadr run))))

;; named-kinds : String (List Any (Listof Any) (Listof Any)) -> (List (Listof Any) (Listof Symbol) Any)
;; named's deviations; then the kinds the sweep saw, each once, sorted;
;; and the kind at the fuel that completed, the last the sweep saw.
(define (named-kinds what run)
  (let* ((deviations (named what run))
         (kinds (let loop ((rest (caddr run)) (seen '()))
                  (cond ((null? rest) (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) seen))
                        ((memq (cadr (car rest)) seen) (loop (cdr rest) seen))
                        (else (loop (cdr rest) (cons (cadr (car rest)) seen))))))
         (last (if (null? (caddr run)) 'none (cadr (list-ref (caddr run) (- (length (caddr run)) 1))))))
    (list deviations kinds last)))

;; checked-trial : Positive-Integer Any -> (List Boolean Any Any)
;; R, a sweep's check's answer at FUEL, made on a connection of its own; a
;; trial that raised, so answering no such list, as a deviation of no kind
;; that ends the sweep there, so a broken call costs one trial, not one a
;; fuel to the cap.
(define (checked-trial fuel r)
  (if (and (list? r) (= (length r) 3))
      r
      (list #f (list fuel 'the-trial-raised r) 'no-kind)))

;; with-memory : (Database -> Any) -> Any
;; PROC's answer, or what it raised, given a connection to a fresh in-memory
;; database holding t; closed after.
(define (with-memory proc)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt (lambda ()
                   (set! db (open-database ":memory:"))
                   (execute! db "create table t (x)")
                   (proc db))))
      (lambda () (when db (guard (e (#t #f)) (close-database! db)))))))

;; --- the low passes -----------------------------------------------------------------------------
;; Pass = (U 'high 'low)
;; The low passes of the pending and claim rows, below. Each trial begins
;; with begun!: a collection, then PASS's trip, 2^27 in the high pass and 256
;; bytes in the low, until the trial ends. A request then falls due all
;; through a low trial, and one due inside a critical section is handled at
;; the section's exit, where it costs the engine ticks.
;; A request fell only where a call's allocation crossed a chunk, the same
;; point at every fuel once each trial collects first, so in the low pass
;; each trial's connection also carries SQLite's trace, whose callback
;; allocates 32 KiB as a step answers a row and as a statement finishes:
;; inside the BEGIN's section, the one its claim is taken in, among the
;; rest. Past 32 KiB a
;; collect request always fell inside a critical section under the low
;; trip. The callback is __collect_safe, as sqlite3_step is; it answers 0
;; and raises nothing; it is locked from here to the suite's end. Every
;; request the trials meet goes through counted-request, which counts it,
;; and the low rows judge where they fell (where a remainder lies, below).
;; The high rows run as before, with no collection of their own.

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
;; statement, the BEGIN's among them (the low passes, above).
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

;; timer-armed!, timer-fired!, timer-done! : -> Void
;; A re-entry row's timer, in place of a first slice: from its setting,
;; its forced sections numbered; as its handler runs, whether its ticks ran
;; out in a forced request's handler, its continuation taken at that
;; section's exit, noted for the pass; once the call is over, a forced
;; section's request still due counted unmet. Past the handler the timer is
;; off, its reading #f, so every forced callback after it reads as one
;; section's, and the unmet count runs only to there.
(define (timer-armed!)
  (set! forced-k 0)
  (set! exit-k #f)
  (set! numbering #t)
  (slice-begun!))
(define (timer-fired!)
  (when numbering
    (set! numbering #f)
    (set! pass-k (max pass-k forced-k))
    (when (and exit-k (not (memv exit-k pass-exits)))
      (set! pass-exits (cons exit-k pass-exits)))))
(define (timer-done!)
  (set! numbering #f)
  (slice-ended!))


;; int (*xCallback)(unsigned, void *pCtx, void *P, void *X)
(define profile
  (foreign-callable __collect_safe
    (lambda (mask ctx p x)
      (force!)
      0)
    (unsigned-32 uptr uptr uptr) int))

;; profile-locked : Any
(define profile-locked (guard (e (#t (list 'raised (describe e)))) (lock-object profile) 'locked))

;; int sqlite3_trace_v2(sqlite3*, unsigned uMask, int(*xCallback)(...), void *pCtx)
(define trace-v2
  (bound 'sqlite3_trace_v2 (foreign-procedure "sqlite3_trace_v2" (uptr unsigned-32 uptr uptr) int)))

;; sqlite-trace-profile, sqlite-trace-row : Natural
;; SQLITE_TRACE_PROFILE, as a statement finishes, and SQLITE_TRACE_ROW, as a
;; step answers a row.
(define sqlite-trace-profile 2)
(define sqlite-trace-row 4)

;; traced! : Database -> Void
;; DB given the trace, a row's and a finish's, its answer required 0.
(define (traced! db)
  (let ((rc (call-with-open-handle 'test-transaction-engine db
              (lambda (h) (trace-v2 h (+ sqlite-trace-profile sqlite-trace-row)
                                    (foreign-callable-entry-point profile) 0)))))
    (unless (eqv? rc 0) (error 'traced! "sqlite3_trace_v2 did not answer 0" rc))))

;; begun! : Pass -> Void
(define (begun! pass)
  (collect-trip-bytes (expt 2 27))
  (collect)
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

;; low-reported : String Tally -> (Listof Any)
;; TALLY shown for the low row WHAT, and low-judged's three.
(define (low-reported what tally)
  (display "  ")
  (display what)
  (display ", low trip")
  (tally-shown tally)
  (newline)
  (low-judged tally))

;; --- the sweeps -------------------------------------------------------------------------------

;; outcome-kind : Any Integer -> Symbol
;; What a fuel's call did: committed, answering 42 with its row seen once;
;; rolled-back, &sqlite-transaction-ended with the row absent; or
;; ended-after-a-later-write, &sqlite-transaction-ended with the row present,
;; the expiry's rollback having fallen before the body's insert, which then
;; autocommitted (ADR-0017's consequences). Anything else is no kind.
(define (outcome-kind answer seen)
  (cond ((and (eqv? answer 42) (eqv? seen 1)) 'committed)
        ((and (equal? answer '(raised (transaction-ended with-transaction))) (eqv? seen 0)) 'rolled-back)
        ((and (equal? answer '(raised (transaction-ended with-transaction))) (eqv? seen 1))
         'ended-after-a-later-write)
        (else 'no-kind)))

;; delta : (Listof Any) (Listof Any) (Listof String) -> (Listof Integer)
;; How many times each of SQLS ran between BEFORE and AFTER, two own-runs
;; readings: over every statement of that SQL tracked after, its runs, less
;; its runs before when it was tracked then. A statement the cache gave up for
;; another of the same SQL, as when the after thunk prepared its own while
;; the commit held the cached one, counts the new one's runs; the one given
;; up is finalized, unread, and a step of it that failed shows in the
;; extended code.
(define (delta before after sqls)
  (let loop ((rest sqls) (out '()))
    (if (null? rest)
        (reverse out)
        (let* ((sql (car rest))
               (n (fold-left
                   (lambda (sum a)
                     (if (string=? (car a) sql)
                         (let ((b (filter (lambda (b) (eq? (caddr b) (caddr a))) before)))
                           (+ sum (if (null? b) (cadr a) (- (cadr a) (cadr (car b))))))
                         sum))
                   0 after)))
          (loop (cdr rest) (cons n out))))))

(test-begin "transaction-engine")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-assert "a temporary directory for the suite's databases"
  (string? temp-dir))

(test-equal "the outer sweep: an engine around with-transaction, deferred, whose body inserts the fuel and answers 42, at every fuel from 1 until it completes without expiring, on a fresh file and connections each fuel, resumed after each expiry: it commits once, its row seen once by db2, BEGIN, then COMMIT, run once each; or raises &sqlite-transaction-ended, BEGIN and ROLLBACK run once each and COMMIT never, the row absent, or present when the rollback fell before the insert, which autocommitted; never another outcome; with-transaction's statements all ready, in-transaction? #f and the extended code 0 after every fuel; all three outcomes seen, the completing fuel's a commit"
  '(() (committed ended-after-a-later-write rolled-back) committed)
  (named-kinds "the outer sweep"
            (sweep (lambda (fuel)
                    (checked-trial fuel
                     (with-files
                      (lambda (db db2)
                     (let* ((before (own-runs db))
                            (r (engine-run (lambda ()
                                             (attempt (lambda ()
                                                        (with-transaction db 'deferred
                                                          (lambda () (execute! db "insert into t values (?)" fuel) 42)))))
                                           fuel))
                            (code (extended db))
                            (in (in-transaction? db))
                            (after (own-runs db))
                            (states (own-statements db))
                            (seen (attempt (lambda () (vector-ref (query-row db2 "select count(*) from t where x = ?" fuel) 0))))
                            (kind (outcome-kind (car r) seen))
                            (runs (delta before after '("BEGIN DEFERRED" "COMMIT" "ROLLBACK")))
                            (expected-runs (if (eq? kind 'committed) '(1 1 0) '(1 0 1)))
                            (whole (list kind runs (not-ready states) in code)))
                       (list (cadr r)
                             (and (or (eq? kind 'no-kind)
                                      (not (equal? whole (list kind expected-runs '() #f 0))))
                                  (list (car r) seen whole))
                             kind))))))
                   5000)))

(test-equal "the nested sweep: inside an outer with-transaction, an engine around a nested one whose body inserts the fuel and answers 42, on a fresh file and connections each fuel: at every fuel it commits once, SAVEPOINT and RELEASE run once each and ROLLBACK TO never; or raises &sqlite-transaction-ended, SAVEPOINT, ROLLBACK TO and RELEASE run once each; never another outcome; the outer level stays open throughout and commits, so db2 then sees the row once, or not, by the same rule; all three outcomes seen, the completing fuel's a commit"
  '(() (committed ended-after-a-later-write rolled-back) committed)
  (named-kinds "the nested sweep"
            (sweep (lambda (fuel)
                    (checked-trial fuel
                     (with-files
                      (lambda (db db2)
                     (let* ((inside #f)
                            (before (own-runs db))
                            (r (with-transaction db 'deferred
                                 (lambda ()
                                   (let ((r (engine-run (lambda ()
                                                          (attempt (lambda ()
                                                                     (with-transaction db
                                                                       (lambda () (execute! db "insert into t values (?)" fuel) 42)))))
                                                        fuel)))
                                     (set! inside (in-transaction? db))
                                     r))))
                            (code (extended db))
                            (in (in-transaction? db))
                            (after (own-runs db))
                            (states (own-statements db))
                            (seen (attempt (lambda () (vector-ref (query-row db2 "select count(*) from t where x = ?" fuel) 0))))
                            (kind (outcome-kind (car r) seen))
                            (runs (delta before after '("SAVEPOINT chez_sqlite3_1" "RELEASE chez_sqlite3_1"
                                                        "ROLLBACK TO chez_sqlite3_1")))
                            (expected-runs (if (eq? kind 'committed) '(1 1 0) '(1 1 1)))
                            (whole (list kind runs (not-ready states) inside in code)))
                       (list (cadr r)
                             (and (or (eq? kind 'no-kind)
                                      (not (equal? whole (list kind expected-runs '() #t #f 0))))
                                  (list (car r) seen whole))
                             kind))))))
                   5000)))

;; --- an expiry before begun ----------------------------------------------------------------

;; before-begun : Database Database Positive-Integer String String String -> (U #f Any)
;; The call, inserting a row of its own, given a first slice of FUEL ticks;
;; #f when that slice began the level, BEGIN-SQL having run, or completed
;; the call. Else, resumed with fuel to spare: its answer, the row's count
;; as DB2 sees it, and the runs of BEGIN-SQL, COMMIT-SQL and ROLLBACK-SQL
;; since before the call.
(define (before-begun db db2 fuel nested begin-sql commit-sql rollback-sql)
  (let* ((row (string-append (if nested "nested-before-" "outer-before-") (number->string fuel)))
         (call (lambda ()
                 (attempt (lambda ()
                            (with-transaction db 'deferred
                              (lambda () (execute! db "insert into t values (?)" row) 42))))))
         (run (lambda ()
                (let* ((before (own-runs db))
                       (first ((make-engine call) fuel complete expire)))
                  (cond ((not (procedure? first)) #f)
                        ((> (car (delta before (own-runs db) (list begin-sql))) 0)
                         (finish first 1000000)
                         #f)
                        (else
                         (let* ((answer (first 1000000 (lambda (left . vals) (car vals)) (lambda (more) 'expired-again)))
                                (after (own-runs db)))
                           (list answer (delta before after (list begin-sql commit-sql rollback-sql)))))))))
         (r (if nested (with-transaction db 'deferred run) (run))))
    (and r (list (car r)
                 (attempt (lambda () (vector-ref (query-row db2 "select count(*) from t where x = ?" row) 0)))
                 (cadr r)))))

;; before-sweep : Boolean String String String -> (List Natural (Listof Any))
;; before-begun at every fuel from 1 until a first slice begins the level,
;; on a fresh file and connections each fuel: how many fuels expired before
;; it, and those whose outcome differs from 42, the row seen once, and the
;; runs (1 1 0).
(define (before-sweep nested begin-sql commit-sql rollback-sql)
  (let loop ((fuel 1) (found '()))
    (let ((r (with-files
              (lambda (db db2)
                (list (before-begun db db2 fuel nested begin-sql commit-sql rollback-sql))))))
      (cond ((not (and (pair? r) (null? (cdr r)))) (list 'the-trial-raised (reverse (cons (list fuel r) found))))
            ((not (car r)) (list (- fuel 1) (reverse found)))
            ((>= fuel 5000) (list 'no-begin-by-5000 (reverse found)))
            ((equal? (car r) '(42 1 (1 1 0))) (loop (+ fuel 1) found))
            (else (loop (+ fuel 1) (cons (list fuel (car r)) found)))))))

(test-equal "an expiry before the BEGIN's step answers rolls nothing back: at every fuel from 1 until a first slice begins the level, on a fresh file and connections each fuel, that slice expiring before begun is set and the call then resumed with fuel to spare, it begins once and commits: 42, the row seen once, BEGIN and COMMIT run once each, ROLLBACK never; nested, SAVEPOINT and RELEASE once, ROLLBACK TO never"
  '((many ()) (many ()))
  (let* ((outer (before-sweep #f "BEGIN DEFERRED" "COMMIT" "ROLLBACK"))
         (nested (before-sweep #t "SAVEPOINT chez_sqlite3_1" "RELEASE chez_sqlite3_1"
                               "ROLLBACK TO chez_sqlite3_1"))
         (shown (lambda (what r)
                  (display "  ")
                  (display what)
                  (display ": first slices that expired before begun: ")
                  (write (car r))
                  (newline)
                  (list (if (and (integer? (car r)) (> (car r) 1)) 'many (car r)) (cadr r)))))
    (list (shown "the outer level" outer) (shown "nested" nested))))

;; --- a remainder resumed a second time ------------------------------------------------------

;; snapshot : Database -> (List Natural (Listof Any))
;; The cache's count, and with-transaction's statements with their states
;; and runs.
(define (snapshot db) (list (database-cache-count db) (own-statements db)))


;; after-ended : Database (-> Any) Positive-Integer String -> (U 'completed (Listof Engine))
;; THUNK, a with-transaction on DB, given a first slice of FUEL ticks. When
;; that slice expired after BEGIN-SQL ran, its level begun, every expiry
;; from there falls with ENDED set: that one's after thunk rolled the level
;; back, or the commit had set it. Then the call is resumed one tick a slice
;; to its end, and every remainder it made is answered, the first slice's
;; first. completed when the first slice completed the call. Otherwise
;; none, the call finished with fuel to spare: a remainder taken before
;; the call's first expression makes a whole new call when resumed, and one
;; taken after it, before the BEGIN, is refused by the call's claim.
(define (after-ended db thunk fuel begin-sql)
  (let* ((before (own-runs db))
         (first ((make-engine thunk) fuel complete expire))
         (begun (and (procedure? first)
                     (> (car (delta before (own-runs db) (list begin-sql))) 0))))
    (cond ((not (procedure? first)) 'completed)
          ((not begun) (finish first 1000000) '())
          (else
           (let loop ((e first) (rs (list first)) (n 0))
             (let ((next (e 1 complete expire)))
               (cond ((pair? next) (reverse rs))
                     ((>= n 100000) (reverse rs))
                     (else (loop next (cons next rs) (+ n 1))))))))))

;; resumed-again : Database Engine -> (Listof Any)
;; R, a remainder whose call has ended, resumed a second time, one tick a
;; slice: (answered A), A R's answer, when the cache's count read between
;; every slice, and DB's snapshot and extended code read at its end, are
;; those before it; else what differed, and R's answer.
(define (resumed-again db r)
  (let* ((base (snapshot db))
         (code (extended db)))
    (let loop ((e r) (n 0) (dips '()))
      (let* ((next (e 1 complete expire))
             (count (database-cache-count db))
             (dips* (if (eqv? count (car base)) dips (cons (list n count) dips))))
        (cond ((pair? next)
               (let ((now (snapshot db)) (code* (extended db)))
                 (if (or (pair? dips*) (not (equal? now base)) (not (eqv? code code*)))
                     (list 'cache-count-between-slices (reverse dips*) 'before base 'after now
                           'extended code code* 'answer (cadr next))
                     (list 'answered (cadr next)))))
              ((>= n 100000) (list 'never-completed))
              (else (loop next (+ n 1) dips*)))))))

;; allowed-second-answers : (Listof Any)
;; What a remainder resumed a second time may answer: the body's value, the
;; refusal of a re-entry, or the ended level's condition. Never an
;; &sqlite-error: that is a COMMIT or RELEASE that reached SQLite with the
;; level over. The cache's snapshot cannot see it, for a second resume takes,
;; steps and returns a statement within one slice.
(define allowed-second-answers
  '(42
    (raised (assertion-violation with-transaction (re-entered)))
    (raised (transaction-ended with-transaction))))

;; twice-at : Boolean Positive-Integer -> (U 'completed (List (Listof Any) Boolean Natural (Listof Any)))
;; At FUEL, on a fresh in-memory connection whose cache an earlier call has
;; primed with both levels' statements, nested inside an outer
;; with-transaction, deferred, when NESTED: each remainder after-ended
;; answers, resumed again. 'completed when the first slice completed the
;; call; else the remainders that touched a statement of
;; with-transaction's, whether the first slice began the level, how many
;; remainders were resumed twice, and the answers they gave, each once.
(define (twice-at nested? fuel)
  (with-memory
   (lambda (db)
     (with-transaction db 'deferred (lambda () (with-transaction db (lambda () 'primed))))
     (let ((go (lambda ()
                 (let ((rs (after-ended db
                                        (lambda ()
                                          (attempt (lambda ()
                                                     (if nested?
                                                         (with-transaction db (lambda () 42))
                                                         (with-transaction db 'deferred (lambda () 42))))))
                                        fuel
                                        (if nested? "SAVEPOINT chez_sqlite3_1" "BEGIN DEFERRED"))))
                   (if (eq? rs 'completed)
                       'completed
                       (let inner ((rest rs) (k 0) (found '()) (answers '()))
                         (if (null? rest)
                             (list (reverse found) (pair? rs) (length rs) answers)
                             (let* ((d (resumed-again db (car rest)))
                                    (answered (and (pair? d) (eq? (car d) 'answered))))
                               (inner (cdr rest) (+ k 1)
                                      (if answered found (cons (list fuel k d) found))
                                      (if (and answered (not (member (cadr d) answers)))
                                          (cons (cadr d) answers)
                                          answers))))))))))
       (if nested? (with-transaction db 'deferred go) (go))))))

;; twice : String Boolean -> (Listof Any)
;; twice-at at every fuel from 1 until the call completes without
;; expiring: the fuels and remainders that touched a statement of
;; with-transaction's, and any answer outside the allowed. Prints how many
;; fuels began their level in the first slice, how many remainders were
;; resumed twice, and the answers they gave. Fewer than one fuel in five
;; beginning its level, or fewer than two remainders a fuel swept, is itself
;; a deviation, the sweep having reached nothing past the BEGIN.
(define (twice what nested?)
  (let loop ((fuel 1) (found '()) (checked 0) (remainders 0) (answers '()))
    (let* ((r (twice-at nested? fuel))
           (completes (eq? r 'completed)))
      (cond
        ((or completes (>= fuel 5000))
         (display "  ")
         (display what)
         (display ": fuels 1 to ")
         (write fuel)
         (display "; first slices that began the level: ")
         (write checked)
         (display "; remainders resumed twice: ")
         (write remainders)
         (display "; their second answers: ")
         (write answers)
         (display "; that touched a statement: ")
         (write (length found))
         (newline)
         (let ((bad (filter (lambda (a) (not (member a allowed-second-answers))) answers))
               (found* (reverse found)))
           (append (if completes found* (cons 'no-completion-by-5000 found*))
                   (if (null? bad) '() (list (list 'second-answers-outside-the-allowed bad)))
                   (if (< (* 5 checked) fuel) (list (list 'too-few-first-slices-began-the-level checked 'of fuel)) '())
                   (if (< remainders (* 2 fuel)) (list (list 'too-few-remainders remainders 'of fuel)) '()))))
        ((not (and (list? r) (= (length r) 4)))
         (loop (+ fuel 1) (cons (list fuel 'the-trial-raised r) found) checked remainders answers))
        (else
         (loop (+ fuel 1)
               (append (reverse (car r)) found)
               (if (cadr r) (+ checked 1) checked)
               (+ remainders (caddr r))
               (fold-left (lambda (acc a) (if (member a acc) acc (cons a acc))) answers (cadddr r))))))))

(test-equal "a remainder captured once ENDED is set, resumed a second time once its call has ended, checks out, steps and returns none of with-transaction's statements: at every fuel until the call completes unexpired whose first slice began the level, on a fresh connection each fuel, each remainder from that expiry on, resumed again one tick a slice, leaves the cache's count unchanged between every slice, and each statement's state and runs, and the extended code, at its end, and answers 42, the re-entry's refusal or &sqlite-transaction-ended, never an &sqlite-error; at the outer level and nested; at least one fuel in five begins its level in its first slice, and two remainders a fuel are resumed"
  '(() ())
  (list (twice "the outer level" #f) (twice "nested" #t)))

;; --- no cut or wrong SQL reaches SQLite -----------------------------------------------------
;;
;; On Chez 10.4.0 an engine's remainder resumed a second time from inside
;; number->string answers "". with-transaction builds its savepoints' names
;; from N, so its plans, which build them, are made inside
;; call-with-open-handle's sections, where no expiry lands. This row holds
;; that: no statement but the allowed ones is ever tracked, and the extended
;; code stays 0, after either resume.

;; sql-texts : Database -> (Listof String)
;; The SQL of every statement DB tracks, the cache's among them, each once,
;; sorted.
(define (sql-texts db)
  (let loop ((rest (tracked-statements db)) (found '()))
    (if (null? rest)
        (list-sort string<? found)
        (let ((sql (statement-sql (car rest))))
          (loop (cdr rest) (if (member sql found) found (cons sql found)))))))

;; resumed-twice-at : Boolean Positive-Integer (Listof String) -> (U 'completed (List (Listof Any) Boolean))
;; At FUEL, on a fresh in-memory connection, nested inside an outer
;; with-transaction, deferred, when NESTED: 'completed when the first slice
;; completed the call; else its remainder resumed to its end, then resumed
;; again to its end, and after each, every SQL the connection tracks one of
;; ALLOWED and the extended code 0: the resumes where either is not, with
;; what was found; and whether the first slice had begun the level.
(define (resumed-twice-at nested? fuel allowed)
  (with-memory
   (lambda (db)
     (let ((go (lambda ()
                 (let* ((before (own-runs db))
                        (first ((make-engine
                                 (lambda ()
                                   (attempt (lambda ()
                                              (if nested?
                                                  (with-transaction db (lambda () 42))
                                                  (with-transaction db 'deferred (lambda () 42)))))))
                                fuel complete expire)))
                   (if (not (procedure? first))
                       'completed
                       (let* ((past (> (car (delta before (own-runs db)
                                                   (list (if nested? "SAVEPOINT chez_sqlite3_1" "BEGIN DEFERRED"))))
                                       0))
                              (check (lambda (which)
                                       (let* ((texts (sql-texts db))
                                              (other (filter (lambda (t) (not (member t allowed))) texts))
                                              (code (extended db)))
                                         (and (or (pair? other) (not (eqv? code 0)))
                                              (list fuel which other code)))))
                              (a1 (finish first 1000000))
                              (c1 (check 'first))
                              (a2 (finish first 1000000))
                              (c2 (check 'second)))
                         (list (filter (lambda (c) c) (list c1 c2)) past)))))))
       (if nested? (with-transaction db 'deferred go) (go))))))

;; resumed-twice : String Boolean (Listof String) -> (Listof Any)
;; resumed-twice-at at every fuel from 1 until the first slice completes
;; the call: the resumes that tracked other SQL or left a code. Prints how
;; many remainders were resumed twice, and how many of them were taken past
;; the BEGIN; fewer than one fuel in five past it is itself a deviation.
(define (resumed-twice what nested? allowed)
  (let loop ((fuel 1) (found '()) (past 0))
    (let ((r (resumed-twice-at nested? fuel allowed)))
      (cond
        ((or (eq? r 'completed) (>= fuel 5000))
         (display "  ")
         (display what)
         (display ": every first remainder, fuels 1 to ")
         (write (- fuel 1))
         (display ", resumed twice; ")
         (write past)
         (display " of them taken past the BEGIN; resumes that tracked other SQL or left a code: ")
         (write (length found))
         (newline)
         (append (reverse found)
                 (if (eq? r 'completed) '() '(no-completion-by-5000))
                 (if (< (* 5 past) fuel) (list (list 'too-few-past-the-begin past 'of fuel)) '())))
        ((not (and (list? r) (= (length r) 2)))
         (loop (+ fuel 1) (cons (list fuel 'the-trial-raised r) found) past))
        (else (loop (+ fuel 1) (append (reverse (car r)) found) (if (cadr r) (+ past 1) past)))))))

(define allowed-outer '("BEGIN DEFERRED" "COMMIT" "ROLLBACK" "create table t (x)"))
(define allowed-nested
  (append allowed-outer '("SAVEPOINT chez_sqlite3_1" "RELEASE chez_sqlite3_1" "ROLLBACK TO chez_sqlite3_1")))

(test-equal "no cut or wrong SQL reaches SQLite: at every fuel until the call completes unexpired, on a fresh connection each fuel, its first remainder resumed to its end and then a second time, at the outer level and nested, a whole new call among them where the remainder was taken before the call began, the connection tracks no SQL but with-transaction's own, its savepoints named in full, and the extended code is 0 after each; at least one fuel in five taken past the BEGIN"
  '(() ())
  (list (resumed-twice "the outer level" #f allowed-outer)
        (resumed-twice "nested" #t allowed-nested)))

;; --- a failed commit's rollback, tried once under any expiry ----------------------------------
;;
;; O7 nested: the inner level's RELEASE answers busy beside the body's own
;; insert ... returning held at its row, so the failed commit is rolled back,
;; ROLLBACK TO answering done, then RELEASE busy again. An engine whose ticks
;; run out inside that rollback escapes, and its exit must not issue again
;; what the rollback already issued. Counted through the statements the
;; connection tracks and the extended code, and the runs of the tracked
;; ROLLBACK TO, the one thing they cannot show: a ROLLBACK TO the rollback
;; took and the exit's own are two tracked statements, the first left at done,
;; or left ready when its step never came; one cached and stepped again is
;; one, which only the runs would show.

(define release-1 "RELEASE chez_sqlite3_1")
(define rollback-to-1 "ROLLBACK TO chez_sqlite3_1")

;; states-of : (Listof (List String Symbol Integer)) String -> (Listof Symbol)
;; The states of the tracked statements of SQL, oldest first.
(define (states-of statements sql)
  (let loop ((rest statements) (out '()))
    (cond ((null? rest) (reverse out))
          ((string=? (car (car rest)) sql) (loop (cdr rest) (cons (cadr (car rest)) out)))
          (else (loop (cdr rest) out)))))

;; engine-lost? : Any -> Boolean
;; Whether E is what an engine's run raises when an exit's failure is raised
;; as the engine runs out: Chez's own error, "no engine active".
(define (engine-lost? e)
  (and (condition? e) (message-condition? e) (equal? (condition-message e) "no engine active")))

;; o7-engine : Positive-Integer -> (List Boolean Any Symbol)
;; At FUEL: inside an outer with-transaction, deferred, on a fresh file, an
;; engine of FUEL ticks a slice around the inner with-transaction, whose body
;; writes inner, holds insert ... returning at its row, and returns; resumed
;; to its end after each expiry. Whether the first slice expired; #f, or
;; what deviated; and the run's kind, ended, busy or lost, read from its
;; answer. A run's whole outcome: its kind; the extended code straight
;; after it; the states of the tracked ROLLBACK TO and RELEASE; the depth
;; inside the outer; then the outer's answer, in-transaction? and the depth
;; after it. Expected, by kind: ended, the exit's rollback ran before the
;; held step, which then answered its row, 100, one ROLLBACK TO and one
;; RELEASE, ready; busy, the commit's failure raised once its rollback ran,
;; the RELEASE's busy, 5, one ROLLBACK TO, ready, and no RELEASE, its failed
;; ones finalized; lost, the exit's own RELEASE failed as the engine ran
;; out, 5, one ROLLBACK TO, ready, and no RELEASE, the lost engine leaving
;; none checked out. Always depth 1 inside, and the outer
;; commits. The tracked ROLLBACK TO has run once, at every kind.
(define (o7-engine fuel)
  (let ((r (with-files
            (lambda (db db2)
              (execute! db "create table r (x)")
              (let* ((held #f) (inside #f)
                     (w (with-transaction db 'deferred
                          (lambda ()
                            (execute! db "insert into t values ('outer')")
                            (let* ((run (guard (e ((engine-lost? e) 'the-engine-was-lost)
                                                  (#t (list 'raised (what-raised e))))
                                           (engine-run
                                            (lambda ()
                                              (attempt
                                               (lambda ()
                                                 (with-transaction db
                                                   (lambda ()
                                                     (execute! db "insert into t values ('inner')")
                                                     (set! held (prepare-statement db "insert into r values (6), (7) returning x"))
                                                     (step! held)
                                                     'inner-returned)))))
                                            fuel)))
                                   (code (extended db))
                                   (own (own-statements db))
                                   (depth (database-depth db)))
                              (when held (finalize-statement! held))
                              (set! inside (list run code own depth))
                              'outer-returned))))
                     (in (in-transaction? db))
                     (depth (database-depth db)))
                (list inside w in depth))))))
    (if (not (and (list? r) (= (length r) 4) (list? (car r))))
        (list #t (list fuel 'the-case-raised r) 'no-kind)
        (let* ((inside (car r))
               (run (car inside))
               (lost (eq? run 'the-engine-was-lost))
               (expired (or lost (and (list? run) (= (length run) 2) (cadr run))))
               (answer (and (not lost) (list? run) (car run)))
               (kind (cond (lost 'lost)
                           ((equal? answer '(raised (transaction-ended with-transaction))) 'ended)
                           ((equal? answer '(raised (sqlite-error with-transaction busy busy))) 'busy)
                           (else 'no-kind)))
               (rollbacks (states-of (caddr inside) rollback-to-1))
               (releases (states-of (caddr inside) release-1))
               (whole (list kind (cadr inside) rollbacks
                            releases
                            (cadddr inside) (cadr r) (caddr r) (cadddr r)
                            (runs-of (caddr inside) rollback-to-1)))
               (expected (case kind
                           ((ended) (list 'ended 100 '(ready) '(ready) 1 'outer-returned #f 0 1))
                           ((busy) (list 'busy 5 '(ready) '() 1 'outer-returned #f 0 1))
                           ((lost) (list 'lost 5 '(ready) '() 1 'outer-returned #f 0 1))
                           (else 'no-kind))))
          (list expired (and (not (equal? whole expected)) (list fuel run whole)) kind)))))

(test-equal "a failed commit's rollback is tried once under any expiry: O7 nested, its RELEASE busy beside the body's held insert ... returning, under an engine at every fuel from 1 until it completes without expiring, resumed after each expiry: at every fuel the connection tracks one ROLLBACK TO chez_sqlite3_1, ready, never a second beside one at done or one left unstepped, and the extended code is the last step's; the call raises &sqlite-transaction-ended when the expiry's rollback came before the held step, its RELEASE kept; the commit's busy once the rollback ran; or loses the engine, Chez's no engine active, when the expiry's own RELEASE failed; the outer level stays open, depth 1, and commits"
  '()
  (named "O7 nested under an engine" (sweep o7-engine 5000)))

;; --- a statement of with-transaction's own, never left behind by an expiry --------------------
;;
;; The same O7 nested, the inner RELEASE failing beside a held insert ...
;; returning. Each of with-transaction's statements is taken from the cache,
;; stepped and given back in one critical section, so no expiry lands between
;; the three: none can be left checked out, or failed and tracked, for a later
;; with-transaction to be refused by. Read once the outer call has returned.

;; distinct-sql : (Listof (List String Symbol Integer)) -> (Listof (List String Symbol Integer))
;; STATEMENTS without a second of the same SQL.
(define (distinct-sql statements)
  (let loop ((rest statements) (seen '()))
    (cond ((null? rest) (reverse seen))
          ((member (car (car rest)) (map car seen)) (loop (cdr rest) seen))
          (else (loop (cdr rest) (cons (car rest) seen))))))

;; o7-orphan : Positive-Integer -> (List Boolean Any Symbol)
;; At FUEL: O7 nested under an engine as o7-engine runs it. Whether the first
;; slice expired; #f, or what deviated; and the kind of the engine's run,
;; lost or not. Once the outer with-transaction has returned, expected: of
;; with-transaction's own statements the connection tracks none that is not
;; ready, none twice, and every statement it tracks is in the cache, so none is
;; checked out or failed and left; depth 0; and a later with-transaction on the
;; connection commits, answering later.
(define (o7-orphan fuel)
  (let ((r (with-files
            (lambda (db db2)
              (execute! db "create table r (x)")
              (let* ((held #f)
                     (run #f)
                     (w (attempt
                         (lambda ()
                           (with-transaction db 'deferred
                             (lambda ()
                               (execute! db "insert into t values ('outer')")
                               (set! run (guard (e ((engine-lost? e) 'the-engine-was-lost)
                                                   (#t (list 'raised (what-raised e))))
                                           (engine-run
                                            (lambda ()
                                              (attempt
                                               (lambda ()
                                                 (with-transaction db
                                                   (lambda ()
                                                     (execute! db "insert into t values ('inner')")
                                                     (set! held (prepare-statement db "insert into r values (6), (7) returning x"))
                                                     (step! held)
                                                     'inner-returned)))))
                                            fuel)))
                               (when held (finalize-statement! held))
                               'outer-returned)))))
                     (own (own-statements db))
                     (left-out (list (length (not-ready own))
                                     (- (length own) (length (distinct-sql own)))
                                     (- (length (tracked-statements db)) (database-cache-count db))))
                     (depth (database-depth db))
                     (later (attempt (lambda () (with-transaction db (lambda () 'later))))))
                (list run w left-out depth later))))))
    (if (not (and (list? r) (= (length r) 5)))
        (list #t (list fuel 'the-case-raised r) 'no-kind)
        (let* ((run (car r))
               (lost (eq? run 'the-engine-was-lost))
               (expired (or lost (and (list? run) (= (length run) 2) (cadr run))))
               (whole (list (cadr r) (caddr r) (cadddr r) (car (cddddr r))))
               (expected (list 'outer-returned '(0 0 0) 0 'later)))
          (list expired (and (not (equal? whole expected)) (list fuel whole)) (if lost 'lost 'not-lost))))))

(test-equal "a statement of with-transaction's own is never left behind by an expiry: O7 nested under an engine at every fuel from 1 until it completes without expiring, resumed after each expiry: once the outer with-transaction has returned, none of with-transaction's own statements the connection tracks is not ready or tracked twice, every statement it tracks is in the cache, the depth is 0, and a later with-transaction on the connection commits"
  '()
  (named "O7 nested, nothing left behind" (sweep o7-orphan 5000)))

;; --- a body re-entered by a timer interrupt, the rollback tried once ---------------------------
;;
;; O7 nested again, with no engine: as the inner body returns, a timer
;; interrupt is set whose handler calls a continuation captured at the inner
;; body's start. That re-enters the body from inside the call's extent, no
;; wind crossed, at whichever point of the commit the tick lands. Swept over
;; the ticks. ROLLBACK TO chez_sqlite3_1, the failed commit's rollback, must
;; run at most once whatever the tick: the sections that take, step and
;; return it are what keep a re-entered body from stepping a second one.

;; rollback-runs : (Listof (List String Symbol Integer)) -> Integer
;; The runs of every tracked ROLLBACK TO chez_sqlite3_1, summed.
(define (rollback-runs statements)
  (let loop ((rest statements) (n 0))
    (cond ((null? rest) n)
          ((string=? (car (car rest)) rollback-to-1) (loop (cdr rest) (+ n (caddr (car rest)))))
          (else (loop (cdr rest) n)))))

;; reenter-case : Positive-Integer -> (List Boolean Any)
;; At TICKS: whether the handler fired, and #f or what deviated: the case's
;; raise, or the runs of ROLLBACK TO chez_sqlite3_1, when over one, with the
;; own statements.
(define (reenter-case ticks)
  (let* ((fired (vector #f))
         (old (timer-interrupt-handler))
         (r (with-files
             (lambda (db db2)
               (execute! db "create table r (x)")
               (let* ((again #f) (entries 0) (held '())
                      (w (with-transaction db 'deferred
                           (lambda ()
                             (execute! db "insert into t values ('outer')")
                             (let* ((inner (attempt
                                            (lambda ()
                                              (with-transaction db
                                                (lambda ()
                                                  (call/cc (lambda (k) (set! again k)))
                                                  (set! entries (+ entries 1))
                                                  (execute! db "insert into t values ('inner')")
                                                  (let ((h (prepare-statement db "insert into r values (6), (7) returning x")))
                                                    (set! held (cons h held))
                                                    (step! h))
                                                  (when (= entries 1)
                                                    (timer-interrupt-handler
                                                     (lambda ()
                                                       (timer-interrupt-handler old)
                                                       (vector-set! fired 0 #t)
                                                       (again #f)))
                                                    (set-timer ticks))
                                                  'inner-returned)))))
                                    (off (set-timer 0))
                                    (restored (timer-interrupt-handler old))
                                    (own (own-statements db)))
                               (for-each finalize-statement! held)
                               (list inner entries own))))))
                 w)))))
    (set-timer 0)
    (timer-interrupt-handler old)
    (list (vector-ref fired 0)
          (cond ((not (and (list? r) (= (length r) 3))) (list ticks 'the-case-raised r))
                ((> (rollback-runs (caddr r)) 1) (list ticks (rollback-runs (caddr r)) (caddr r)))
                (else #f)))))

;; reenters : -> (Listof Any)
;; Every tick count from 1 until four in a row do not fire the handler: the
;; ticks' deviations. Prints how many ticks fired it; fewer than 20 is itself
;; a deviation, the sweep having reached nothing.
(define (reenters)
  (let loop ((ticks 1) (unfired 0) (fired 0) (found '()))
    (if (or (> unfired 3) (>= ticks 2000))
        (begin
          (display "  the re-entries: the handler fired at ")
          (write fired)
          (display " of ")
          (write (- ticks 1))
          (display " ticks")
          (newline)
          (append (reverse found) (if (< fired 20) (list (list 'too-few-ticks-fired fired)) '())))
        (let ((r (reenter-case ticks)))
          (loop (+ ticks 1) (if (car r) 0 (+ unfired 1)) (if (car r) (+ fired 1) fired)
                (if (cadr r) (cons (cadr r) found) found))))))

(test-equal "a body re-entered by a timer interrupt as it returns steps ROLLBACK TO chez_sqlite3_1 at most once: O7 nested, its RELEASE busy beside the body's held insert ... returning, a timer interrupt set as the inner body returns whose handler calls a continuation captured at the body's start, at every tick count from 1 until four in a row do not fire it, and at least 20 do: the tracked ROLLBACK TO chez_sqlite3_1 statements' runs sum to at most one"
  '()
  (reenters))

;; --- a nested begin that fails ------------------------------------------------------------------
;;
;; Inside an outer with-transaction, a timer interrupt at T1 ticks steps the
;; caller's select to a row and calls sqlite3_interrupt, which stays while the
;; select is held, and a second at T2 ticks later finalizes it. The refusal's
;; pass and the BEGIN share one section, so a select the connection tracks,
;; stepped before the inner call's BEGIN, is refused there, and one stepped
;; after cannot reach the BEGIN: no timer falls between the two. A select
;; prepared outside the library, which the connection does not track and the
;; refusal cannot see, still makes the SAVEPOINT fail, and so tests,
;; untracked, what a tracked select can no longer reach: a begin that failed
;; rolls nothing back.

;; raw-prepare! : Database String -> Positive-Integer
;; A statement of SQL on DB, made with the raw sqlite3_prepare_v2, so the
;; connection does not track it and the refusal's pass cannot see it.
(define prepare-v2 (bound 'sqlite3_prepare_v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int)))
(define raw-step (bound 'sqlite3_step (foreign-procedure "sqlite3_step" (uptr) int)))
(define raw-finalize (bound 'sqlite3_finalize (foreign-procedure "sqlite3_finalize" (uptr) int)))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-out-pointer (reach '(chez-sqlite3 private native) 'call-with-out-pointer))
(define (raw-prepare! db sql)
  (call-with-open-handle 'test-transaction-engine db
    (lambda (h)
      (call-with-c-string 'test-transaction-engine sql
        (lambda (text)
          (let-values (((rc statement)
                        (call-with-out-pointer 'test-transaction-engine
                          (lambda (slot) (prepare-v2 h text -1 slot 0)))))
            (if (and (eqv? rc 0) (not (eqv? statement 0)))
                statement
                (error 'raw-prepare! "sqlite3_prepare_v2 did not answer a statement" rc))))))))

;; held-select : Database Boolean -> (List (-> Any) (-> Any))
;; The caller's select, tracked through prepare-statement when TRACKED,
;; else made by raw-prepare!: a procedure that steps it to its row, and one
;; that finalizes it, once, however often called.
(define (held-select db tracked)
  (let ((sql "select 1 union all select 2"))
    (if tracked
        (let ((st (prepare-statement db sql)))
          (list (lambda () (step! st))
                (lambda () (guard (e (#t #f)) (finalize-statement! st)))))
        (let ((st (raw-prepare! db sql)) (live #t))
          (list (lambda () (when live (raw-step st)))
                (lambda () (when live (set! live #f) (raw-finalize st))))))))

;; failed-begin-case : Boolean Positive-Integer (U Positive-Integer #f) -> (List Boolean Boolean Any)
;; At T1 and T2, the caller's select TRACKED or not: whether each timer
;; fired, and the inner call's answer, with-transaction's statements, the
;; depth and the extended code straight after it. With T2 #f there is no
;; second timer: the select stays at its row until the inner call is over.
(define (failed-begin-case tracked t1 t2)
  (let* ((fired (vector #f #f))
         (old (timer-interrupt-handler))
         (r (with-files
             (lambda (db db2)
               (let* ((held (held-select db tracked))
                      (step-it (car held))
                      (finalize-it (cadr held))
                      (w (dynamic-wind
                           (lambda () #f)
                           (lambda ()
                             (with-transaction db 'deferred
                               (lambda ()
                                 (execute! db "insert into t values ('outer')")
                                 (timer-interrupt-handler
                                  (lambda ()
                                    (vector-set! fired 0 #t)
                                    (step-it)
                                    (call-with-open-handle 'test-transaction-engine db sqlite3-interrupt)
                                    (if t2
                                        (begin
                                          (timer-interrupt-handler
                                           (lambda ()
                                             (timer-interrupt-handler old)
                                             (vector-set! fired 1 #t)
                                             (finalize-it)))
                                          (set-timer t2))
                                        (begin
                                          (timer-interrupt-handler old)
                                          (vector-set! fired 1 #t)))))
                                 (set-timer t1)
                                 (let* ((inner (attempt (lambda () (with-transaction db (lambda () 'inner-returned)))))
                                        (off (set-timer 0))
                                        (restored (timer-interrupt-handler old))
                                        (own (own-statements db))
                                        (depth (database-depth db))
                                        (code (extended db)))
                                   (finalize-it)
                                   (list inner own depth code)))))
                           (lambda () (set-timer 0) (timer-interrupt-handler old) (finalize-it)))))
                 w)))))
    (set-timer 0)
    (timer-interrupt-handler old)
    (list (vector-ref fired 0) (vector-ref fired 1) r)))

;; begin-failed? : Any -> Boolean
;; Whether R, a failed-begin-case's outcome, is a nested begin that failed
;; interrupted: the inner call raised &sqlite-error interrupt and no
;; SAVEPOINT of with-transaction's is tracked.
(define (begin-failed? r)
  (and (list? r) (= (length r) 4)
       (equal? (car r) '(raised (sqlite-error with-transaction interrupt interrupt)))
       (null? (filter (lambda (t) (prefix? "SAVEPOINT" (car t))) (cadr r)))))

;; refused-beside-the-row? : Any -> Boolean
;; Whether R, a failed-begin-case's outcome, is the inner call refused
;; beside the caller's tracked select at its row.
(define (refused-beside-the-row? r)
  (and (list? r) (= (length r) 4)
       (equal? (car r) '(raised (assertion-violation with-transaction
                                 (statement-not-finished row "select 1 union all select 2"))))))

;; failed-begins : Boolean -> (List Natural Natural (Listof Any))
;; failed-begin-case, the caller's select TRACKED or not, at every T1 from
;; 1 until four in a row fire no interrupt, and, untracked, every T2 from 1
;; until four in a row fire no finalize, both fired; tracked, with no T2,
;; the select held to the end, since a select the refusal sees is refused
;; or comes after the BEGIN, whenever it is finalized. How many cases
;; failed the nested begin, how many were refused beside the row, and the
;; cases that deviated, a begin that failed after which with-transaction
;; tracked a ROLLBACK TO or RELEASE, or the extended code is neither 0 nor
;; 9, interrupt: a ROLLBACK TO behind no SAVEPOINT answers 1.
(define (failed-begins tracked)
  (let loop ((t1 1) (u1 0) (found '()) (failed 0) (refused 0))
    (if (or (> u1 3) (>= t1 300))
        (begin
          (display (if tracked "  the refusal beside a tracked row: " "  the failed begins: "))
          (display "cases that failed the nested begin: ")
          (write failed)
          (display "; refused beside the row: ")
          (write refused)
          (newline)
          (list failed refused (reverse found)))
        (let inner ((t2 1) (u2 0) (any #f) (found found) (failed failed) (refused refused))
          (if (or (> u2 3) (>= t2 300) (and tracked (> t2 1)))
              (loop (+ t1 1) (if any 0 (+ u1 1)) found failed refused)
              (let* ((r (failed-begin-case tracked t1 (and (not tracked) t2)))
                     (both (and (car r) (cadr r)))
                     (o (caddr r))
                     (fb (and both (begin-failed? o)))
                     (bad (and fb
                               (or (pair? (filter (lambda (t) (not (own-sql-is-begin? (car t)))) (cadr o)))
                                   (not (member (cadddr o) '(0 9)))))))
                (inner (+ t2 1) (if (cadr r) 0 (+ u2 1)) (or any (car r))
                       (if bad (cons (list t1 t2 o) found) found)
                       (if fb (+ failed 1) failed)
                       (if (and both (refused-beside-the-row? o)) (+ refused 1) refused))))))))

;; own-sql-is-begin? : String -> Boolean
(define (own-sql-is-begin? sql) (string=? sql "BEGIN DEFERRED"))

(test-equal "a nested begin that fails leaves nothing to roll back: inside an outer with-transaction, deferred, a timer interrupt at T1 ticks steps the caller's select, made outside the library so the connection does not track it, to a row and calls sqlite3_interrupt, which stays while the select is held, and a second at T2 ticks later finalizes it, at every T1 and T2 until four in a row do not fire: in the at least 100 cases where the inner with-transaction raises &sqlite-error interrupt with no SAVEPOINT tracked, only BEGIN DEFERRED is tracked of with-transaction's statements and the extended code is 0 or 9, never the 1 of a ROLLBACK TO behind no SAVEPOINT"
  '(many ())
  (let ((r (failed-begins #f)))
    (list (if (>= (car r) 100) 'many (list 'too-few-failed-begins (car r))) (caddr r))))

(test-equal "the refusal's pass and the BEGIN share one section: the same timer at every T1, with the caller's select tracked and held to the end, so no timer falls between the refusal and the SAVEPOINT: no nested begin fails beside the row, and at least three cases are refused, statement-not-finished"
  '(0 many ())
  (let ((r (failed-begins #t)))
    (list (car r) (if (>= (cadr r) 3) 'many (list 'too-few-refused (cadr r))) (caddr r))))

;; --- a remainder resumed while an earlier resume of it is pending ---------------------------
;;
;; At fuel F the call's first remainder R. R is resumed with fuel G until it
;; expires, as R1. Then R is resumed to its end, then R1 to its end: the
;; second resume of R's call begins while R1, its earlier one, is still
;; pending. Swept over F from 1 until the call completes unexpired, and over
;; G from 1 until R completes within G, at the outer level and nested, inside
;; an outer with-transaction whose body runs the engines. A flag set only
;; when a call ends breaks under that schedule. After both runs: the depth
;; is restored, in-transaction? is #f once the outer level is over, a later
;; with-transaction commits, and none of with-transaction's own statements
;; is tracked other than ready, or outside the cache; nor is any statement,
;; the body's included, tracked outside the cache. The body's execute! holds
;; a claim on its call, made by its first expression. With a flag set when
;; the call ends in its place, the body's insert is left tracked outside the
;; cache from F 29, G 46: measured, this row failed 960 of 8,210 trials at
;; the outer level and 959 nested.

;; cached? : Database String -> Boolean
;; Whether DB's cache holds a statement under SQL, read by taking it out and
;; putting it back, inside the connection's section.
(define (cached? db sql)
  (call-with-open-handle 'test-transaction-engine db
    (lambda (handle)
      (let ((r (database-cache-check-out! db sql)))
        (when (eq? (car r) 'hit) (database-cache-return! db sql (cadr r)))
        (eq? (car r) 'hit)))))

;; body-sql : String
;; The pending row's body's one statement.
(define body-sql "insert into t values (1)")

;; body-held : Database -> (U Symbol #f)
;; Read between two slices: the state of the body's statement while its
;; execute! holds it out of DB's cache, ready before its step, done after
;; it; #f when the call holds none.
(define (body-held db)
  (and (> (length (tracked-statements db)) (database-cache-count db))
       (not (cached? db body-sql))
       (let loop ((rest (tracked-statements db)))
         (cond ((null? rest) #f)
               ((string=? (statement-sql (car rest)) body-sql) (statement-state (car rest)))
               (else (loop (cdr rest)))))))

;; pending-answers : (Listof Any)
;; What each run of a pending trial may answer: the body's 42; the ended
;; condition; &sqlite-closed from the body's execute!, its claim refusing a
;; second run's section; or with-transaction's refusal of a re-entry. A
;; second run that steps the body's statement again, its claim's advance
;; split from its section, answers the statement tier's refusal of a step
;; at done.
(define pending-answers
  (list 42 '(raised (transaction-ended with-transaction)) '(raised (closed execute!))
        '(raised (assertion-violation with-transaction (re-entered)))))

;; straddles : Natural
;; The trials of the pending sweep under way whose R held the body's
;; statement ready, whose R1 was taken at its step's exit, the step done,
;; and whose R's second run was refused by the body's claim, &sqlite-closed
;; from execute!: it reached the step's section once R1's run had made it.
;; A claim whose advance is split from its section, just after it, lets
;; that run step the statement again, which the statement tier refuses, at
;; done: an answer pending-answers lacks. So every such trial of correct
;; code is one the split would fail by name, whatever the heap's layout,
;; and the low row requires some at each level.
(define straddles 0)

;; own-left : Database -> (Listof Any)
;; Of with-transaction's own statements DB tracks: those not ready, those
;; tracked twice, and those whose SQL the cache does not hold.
(define (own-left db)
  (let ((own (own-statements db)))
    (append (map (lambda (s) (list 'not-ready (car s) (cadr s))) (not-ready own))
            (map (lambda (s) (list 'tracked-twice (car s)))
                 (filter (lambda (s) (> (length (filter (lambda (o) (string=? (car o) (car s))) own)) 1))
                         (distinct-sql own)))
            (map (lambda (s) (list 'outside-the-cache (car s)))
                 (filter (lambda (s) (not (cached? db (car s)))) (distinct-sql own))))))

;; pending-trial : Pass Boolean Positive-Integer Positive-Integer
;;                 -> (U 'completed-at-f 'r-completed-at-g (Listof Any))
;; One (F, G) on a fresh in-memory database, in PASS: 'completed-at-f when
;; the call completed within F, 'r-completed-at-g when R completed within G,
;; else the deviations, '() for none. R's and R1's runs each answer one of
;; pending-answers. A trial whose R held the body's statement ready, whose
;; R1, taken at a forced section's exit, held it done, and whose R's second
;; run the body's claim refused, is counted in straddles.
(define (pending-trial pass nested? f g)
  (let ((db #f))
    (dynamic-wind
      (lambda () (begun! pass))
      (lambda ()
        (let ((r (attempt
                  (lambda ()
                    (set! db (open-database ":memory:"))
                    (when (eq? pass 'low) (traced! db))
                    (execute! db "create table t (x)")
                    (let* ((inside #f)
                           (run (lambda ()
                                  (let ((first (first-slice
                                                (make-engine
                                                 (lambda ()
                                                   (attempt (lambda ()
                                                              (with-transaction db
                                                                (lambda ()
                                                                  (execute! db "insert into t values (1)")
                                                                  42))))))
                                                f)))
                                    (if (pair? first)
                                        'completed-at-f
                                        (let* ((r-held (body-held db))
                                               (second (first-slice first g))
                                               (r1-exit exit-k))
                                          (if (pair? second)
                                              'r-completed-at-g
                                              (let* ((r1-held (body-held db))
                                                     (a (finish first 1000000))
                                                     (b (finish second 1000000)))
                                                (when (and (eq? r-held 'ready) r1-exit (eq? r1-held 'done)
                                                           (equal? a '(raised (closed execute!))))
                                                  (set! straddles (+ straddles 1)))
                                                (list 'ran a b))))))))
                           (outcome
                            (if nested?
                                (let ((w (with-transaction db 'deferred
                                           (lambda ()
                                             (let ((x (run)))
                                               (set! inside (list (database-depth db) (own-left db)))
                                               x)))))
                                  w)
                                (run))))
                      (if (memq outcome '(completed-at-f r-completed-at-g))
                          outcome
                          (let* ((answers (cdr outcome))
                                 (depth (database-depth db))
                                 (in (in-transaction? db))
                                 (left (own-left db))
                                 (stray (- (length (tracked-statements db)) (database-cache-count db)))
                                 (later (attempt (lambda () (with-transaction db (lambda () 'later-committed))))))
                            (append
                             (if (for-all (lambda (a) (member a pending-answers)) answers)
                                 '()
                                 (list (cons 'answers answers)))
                             (if (and nested? (not (equal? inside '(1 ())))) (list (list 'inside inside)) '())
                             (if (eqv? depth 0) '() (list (list 'depth depth)))
                             (if in (list 'in-transaction-after) '())
                             (if (eq? later 'later-committed) '() (list (list 'later later)))
                             (if (null? left) '() (list (list 'left left)))
                             (if (> stray 0) (list (list 'stray stray)) '())))))))))
          (cond ((symbol? r) r)
                ((and (pair? r) (eq? (car r) 'raised)) (list (list 'the-trial-raised r)))
                (else r))))
      (lambda ()
        (when db (guard (e (#t #f)) (close-database! db)))
        (ended!)))))

;; pending-stride : Positive-Integer
;; G steps by this, from 1: every G, since an engine's fuel names no fixed
;; point in the code. The sweep of F ends where the call completes unexpired,
;; a fuel the suite prints.
(define pending-stride 1)

;; pending : Pass Boolean -> (Listof Any)
;; In PASS, pending-trial at every F from 1 until the call completes unexpired, and G
;; from 1 by pending-stride until R completes within G: the (F G deviation ...) of the trials
;; that deviated. Prints the trials made, each with R1 existing; fewer than
;; ten a fuel on average, or any other collapse of the whole sweep, is
;; itself a deviation, the sweep having reached nothing. An average: a
;; collapse over a stretch of fuels can pass it. A count fixed in trials broke when part
;; D made the call cheaper: 647 at every fourth G.
(define (pending pass nested?)
  (set! straddles 0)
  (let floop ((f 1) (found '()) (trials 0))
    (let gloop ((g 1) (found found) (trials trials))
      (let ((r (pending-trial pass nested? f g)))
        (cond ((eq? r 'completed-at-f)
               (display (if nested? "  pending, nested" "  pending, the outer level"))
               (display (if (eq? pass 'low) ", low trip: " ": "))
               (write trials)
               (display " trials, the call completed unexpired at fuel ")
               (write f)
               (display "; R holding the body's statement ready, R1 at its step's exit and R's second run refused by the body's claim in ")
               (write straddles)
               (newline)
               (append (reverse found)
                       (if (< trials (* 10 f)) (list (list 'too-few-trials-with-r1 trials 'fuel f)) '())))
              ((eq? r 'r-completed-at-g)
               (if (>= f 5000) (reverse (cons 'no-completion found)) (floop (+ f 1) found trials)))
              ((>= g 1000) (floop (+ f 1) (cons (list f g 'r-never-completed) found) trials))
              (else (gloop (+ g pending-stride) (if (null? r) found (cons (cons f (cons g r)) found)) (+ trials 1))))))))

(define pending-name
  "a remainder resumed while an earlier resume of it is pending leaves the level and its statements whole: at fuel F the call's first remainder R, resumed with fuel G until it expires as R1, then R to its end, then R1 to its end, at every F until the call completes unexpired and every G until R completes within G, at the outer level and nested in an outer with-transaction: the depth is restored, in-transaction? is #f after the outer level, a later with-transaction commits, none of with-transaction's own statements is tracked other than ready, tracked twice, or outside the cache, and no statement, the body's included, is tracked outside the cache; each run answers 42, the ended condition, &sqlite-closed from the body's execute!, or the re-entry's refusal; at least ten trials a fuel on average")

(test-equal pending-name
  '(() ())
  (let* ((outer (pending 'high #f))
         (nested (pending 'high #t)))
    (list outer nested)))

(test-equal (string-append "the same, its trials under a collect trip of 256 bytes, each trial's connection carrying SQLite's trace, which allocates 32 KiB as a step answers a row or a statement finishes, the BEGIN in its own section among them, so a request falls due inside the section and is handled at its exit: the same verdicts, and collect requests met in the trials, each forced section's request met before the next, and some first slice expired at a forced section's exit; and, at the outer level and nested, some trial with R holding the body's statement ready, R1 taken at its step's exit, and R's second run refused by the body's claim there, &sqlite-closed from execute!, the step R1's run had made. " pending-name)
  (append '(() () refused-at-the-step-r1-made) low-checks)
  (let-values (((r tally) (counted-pass (lambda ()
                                          (let* ((outer (pending 'low #f))
                                                 (outer-straddles straddles)
                                                 (nested (pending 'low #t))
                                                 (nested-straddles straddles))
                                            (list outer nested
                                                  (if (and (> outer-straddles 0) (> nested-straddles 0))
                                                      'refused-at-the-step-r1-made
                                                      (list 'refused-at-the-step-r1-made outer-straddles
                                                            nested-straddles))))))))
    (append r (low-reported "pending" tally))))

;; --- the call's claim: a remainder resumed twice begins one level ------------------------------
;;
;; Each with-transaction call holds a claim, made by its first expression,
;; which the BEGIN's section takes, first in that section: a run of the call
;; that reaches it once another has taken it begins nothing and raises
;; &sqlite-transaction-ended. With the flags made after the plan's section,
;; a remainder taken between the call's first expression and them, resumed
;; a second time once the call has ended, makes flags of its own, begins
;; again, runs the body and commits again: measured at fuels 9 to 11, 15
;; and 16.
;;
;; At fuel F, on a fresh connection: an engine whose thunk counts its own
;; entries, then calls with-transaction, whose body inserts F and answers
;; 42; its first remainder R resumed to its end, then again. A remainder
;; taken before the call's first expression makes a whole new call, which
;; begins and commits again: one taken before the thunk's count re-runs
;; that count, and so is told by it. One taken after the count but before
;; the claim cannot be told from outside the call: the entries of
;; with-transaction and of its work, two procedure calls, lie between, and
;; an engine can expire at each, a count of ticks that moves with the code:
;; a whole new call is never bounded by a caller's own count. So a second
;; level is allowed only where the first slice began nothing, and R re-ran
;; the count, or lay below the first fuel at which the sweep saw R refused
;; by the claim, which a remainder taken past the claim's making meets. A
;; claim that never refuses passes this bound: the flags' check moves its
;; own first refusal past its extra level, and the claim's re-entry row
;; catches it. A window of two fuels past the count saw it, but a window is
;; a caller's own count.

;; claim-trial : Pass Boolean Positive-Integer -> (U 'completed (List Any ...))
;; One trial at FUEL, in PASS, on a fresh in-memory connection, nested
;; inside an outer with-transaction, deferred, when NESTED: 'completed when
;; the first slice completed the call; else the entries counted by the first
;; slice and by the end; the levels the first slice began; R's two answers;
;; the levels begun and committed over the trial; the rows of FUEL; the
;; depth and in-transaction? after it, the outer level over; and whether no
;; collect request fell in the first slice.
(define (claim-trial pass nested? fuel)
  (let ((db #f) (clean #t))
    (dynamic-wind
      (lambda () (begun! pass))
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (when (eq? pass 'low) (traced! db))
           (execute! db "create table t (x)")
           (let* ((begin-sql (if nested? "SAVEPOINT chez_sqlite3_1" "BEGIN DEFERRED"))
                  (entries 0)
                  (thunk (lambda ()
                           (attempt (lambda ()
                                      (set! entries (+ entries 1))
                                      (with-transaction db 'deferred
                                        (lambda () (execute! db "insert into t values (?)" fuel) 42))))))
                  (run (lambda ()
                         (let* ((met requests)
                                (first (first-slice (make-engine thunk) fuel)))
                           (set! clean (= requests met))
                           (if (pair? first)
                               'completed
                               (let* ((e0 entries)
                                      (b0 (car (delta '() (own-runs db) (list begin-sql))))
                                      (a1 (finish first 1000000))
                                      (a2 (finish first 1000000))
                                      (runs (delta '() (own-runs db)
                                                   (if nested?
                                                       '("SAVEPOINT chez_sqlite3_1" "RELEASE chez_sqlite3_1"
                                                         "ROLLBACK TO chez_sqlite3_1")
                                                       '("BEGIN DEFERRED" "COMMIT")))))
                                 (list e0 entries b0 a1 a2 (car runs)
                                       (if nested? (- (cadr runs) (caddr runs)) (cadr runs))))))))
                  (r (if nested? (with-transaction db 'deferred run) (run))))
             (if (eq? r 'completed)
                 'completed
                 (append r
                         (list (vector-ref (query-row db "select count(*) from t where x = ?" fuel) 0)
                               (database-depth db)
                               (if (in-transaction? db) 'open 'closed)
                               clean)))))))
      (lambda ()
        (when db (guard (e (#t #f)) (close-database! db)))
        (ended!)))))

;; claim-sweep : Pass Boolean -> (Listof Any)
;; claim-trial in PASS at every fuel from 1 until the first slice completes
;; the call: the fuels that deviated. A deviation is a second level not
;; allowed above, more commits than levels, a first answer but 42 or the ended
;; condition, a second but those, the re-entry's refusal or the body's
;; execute! refused by its own claim, &sqlite-closed, fewer rows than commits,
;; a depth but 0, or a transaction left open. Prints the fuels at which R
;; made a whole new call, was refused by the claim, and lay past the BEGIN;
;; fewer than three refused, or than three past, is itself a deviation, the
;; sweep having reached nothing. A second level is allowed only where R
;; re-ran the count, or below the first fuel at which the sweep saw R
;; refused by the claim, or, in the low pass, where a collect request fell
;; in the first slice, its remainder earlier than its fuel says.
(define (claim-sweep pass nested?)
  (let loop ((fuel 1) (counted #f) (found '()) (new '()) (refused '()) (past 0))
    (let ((r (claim-trial pass nested? fuel)))
      (cond
        ((or (eq? r 'completed) (>= fuel 5000))
         (display (if nested? "  the claim, nested" "  the claim, the outer level"))
         (display (if (eq? pass 'low) ", low trip: " ": "))
         (display "completed unexpired at fuel ")
         (write fuel)
         (display "; the thunk's count first made at fuel ")
         (write counted)
         (display "; whole new calls at ")
         (write (reverse new))
         (display "; refused by the claim at ")
         (write (reverse refused))
         (display "; past the BEGIN at ")
         (write past)
         (display " fuels")
         (newline)
         (append (reverse found)
                 (if (eq? r 'completed) '() '(no-completion))
                 (if (< (length refused) 3) (list (list 'too-few-refused (length refused))) '())
                 (if (< past 3) (list (list 'too-few-past-the-begin past)) '())))
        ((not (and (list? r) (= (length r) 11)))
         (loop (+ fuel 1) counted (cons (list fuel 'the-trial-raised r) found) new refused past))
        (else
         (let* ((e0 (list-ref r 0)) (e (list-ref r 1)) (b0 (list-ref r 2))
                (a1 (list-ref r 3)) (a2 (list-ref r 4)) (begins (list-ref r 5)) (commits (list-ref r 6))
                (rows (list-ref r 7)) (depth (list-ref r 8)) (open (list-ref r 9)) (clean (list-ref r 10))
                (counted* (or counted (and (eqv? e0 1) fuel)))
                (ended '(raised (transaction-ended with-transaction)))
                (whole-new (eqv? begins 2))
                (allowed-new (and (eqv? b0 0) (or (eqv? e 2) (not clean) (null? refused))))
                (bad (append
                      (if (and whole-new (not allowed-new)) '(a-second-level) '())
                      (if (memv begins '(1 2)) '() (list (list 'levels begins)))
                      (if (> commits begins) (list (list 'commits commits 'levels begins)) '())
                      (if (member a1 (list 42 ended)) '() (list (list 'first a1)))
                      (if (member a2 (list 42 ended '(raised (assertion-violation with-transaction (re-entered)))
                                           '(raised (closed execute!))))
                          '()
                          (list (list 'second a2)))
                      (if (<= commits rows) '() (list (list 'rows rows 'commits commits)))
                      (if (eqv? depth 0) '() (list (list 'depth depth)))
                      (if (eq? open 'closed) '() (list 'left-open)))))
           (loop (+ fuel 1) counted*
                 (if (null? bad) found (cons (cons fuel (cons bad r)) found))
                 (if whole-new (cons fuel new) new)
                 (if (and (eqv? b0 0) (not whole-new) (equal? a2 ended)) (cons fuel refused) refused)
                 (if (> b0 0) (+ past 1) past))))))))

;; interrupt-depth : -> Positive-Integer
;; How many critical sections this thread is inside, plus one: what
;; disable-interrupts answers, put back at once.
(define (interrupt-depth)
  (let ((n (disable-interrupts)))
    (enable-interrupts)
    n))

;; handler-depth : (-> Any) -> (U (List 'raised-at-depth Symbol Any) (List 'no-raise Any))
;; The depth a with-exception-handler handler runs at for the first thing
;; THUNK raises, read before anything else, as depth-N, and what it raised,
;; as what-raised names it. The handler escapes, so nothing returns into the
;; raise.
(define (handler-depth thunk)
  (call/cc
   (lambda (k)
     (with-exception-handler
      (lambda (c)
        (let ((depth (interrupt-depth)))
          (k (list 'raised-at-depth
                   (string->symbol (string-append "depth-" (number->string depth)))
                   (what-raised c)))))
      (lambda () (list 'no-raise (thunk)))))))

;; claim-depths : -> (List Natural (Listof Any))
;; At every fuel from 1 until the call completes unexpired, on a fresh
;; connection: an engine around handler-depth around with-transaction,
;; deferred, whose body answers 42, its first remainder resumed to its end,
;; then again. How many second resumes of a remainder taken before the
;; BEGIN ran raised the ended condition, the claim's refusal, read by a
;; handler at depth 1; and every answer of either resume that is neither 42
;; nor a raise read at depth 1.
(define (claim-depths)
  (let loop ((fuel 1) (refused 0) (found '()))
    (let ((r (with-memory
              (lambda (db)
                (let ((first ((make-engine
                               (lambda ()
                                 (handler-depth (lambda () (with-transaction db 'deferred (lambda () 42))))))
                              fuel complete expire)))
                  (if (pair? first)
                      'completed
                      (let* ((b0 (car (delta '() (own-runs db) '("BEGIN DEFERRED"))))
                             (a1 (finish first 1000000))
                             (a2 (finish first 1000000)))
                        (list b0 a1 a2))))))))
      (cond ((or (eq? r 'completed) (>= fuel 5000))
             (display "  the claim's refusal, read by a handler: second resumes refused at depth 1: ")
             (write refused)
             (newline)
             (list refused (reverse found)))
            ((not (and (list? r) (= (length r) 3)))
             (loop (+ fuel 1) refused (cons (list fuel 'the-trial-raised r) found)))
            (else
             (let ((odd (filter (lambda (a)
                                  (not (or (equal? a '(no-raise 42))
                                           (and (pair? a) (eq? (car a) 'raised-at-depth)
                                                (eq? (cadr a) 'depth-1)))))
                                (cdr r))))
               (loop (+ fuel 1)
                     (if (and (eqv? (car r) 0)
                              (equal? (caddr r) '(raised-at-depth depth-1 (transaction-ended with-transaction))))
                         (+ refused 1)
                         refused)
                     (if (null? odd) found (cons (list fuel odd) found)))))))))

(test-equal "the claim's refusal is raised outside any critical section: at every fuel, a second resume's raise, the ended condition where the claim refused it, is read by a handler at depth 1, and at least three are"
  '(many ())
  (let ((r (claim-depths)))
    (list (if (>= (car r) 3) 'many (list 'too-few-refused (car r))) (cadr r))))

(define claim-name
  "the call's claim: at every fuel from 1 until the call completes unexpired, on a fresh connection, its first remainder resumed to its end and then again, at the outer level and nested: a second level is begun only by a whole new call, from a remainder taken before the call's first expression, told by the thunk's own count or below the sweep's first refusal by the claim; never more commits than levels; each answer 42 or the ended condition, the second also the re-entry's refusal or the body's execute! refused by its own claim; the depth 0 and nothing left open; at least three fuels refused by the claim, and three past the BEGIN")

(test-equal claim-name
  '(() ())
  (let* ((outer (claim-sweep 'high #f))
         (nested (claim-sweep 'high #t)))
    (list outer nested)))

(test-equal (string-append "the same, its trials under a collect trip of 256 bytes, each trial's connection carrying SQLite's trace, so a request falls due inside the BEGIN's section and is handled at its exit: the same verdicts, a whole new call also allowed where a collect request fell in its first slice, and collect requests met in the trials, each forced section's request met before the next, and some first slice expired at a forced section's exit. " claim-name)
  (append '(() ()) low-checks)
  (let-values (((r tally) (counted-pass (lambda ()
                                          (let* ((outer (claim-sweep 'low #f))
                                                 (nested (claim-sweep 'low #t)))
                                            (list outer nested))))))
    (append r (low-reported "the claim" tally))))

;; claim-reentry-case : Pass Boolean Positive-Integer -> (List Boolean Boolean Any)
;; In PASS, at TICKS, on a fresh in-memory connection, nested inside an outer
;; with-transaction, deferred, when NESTED: a timer of TICKS set just
;; before with-transaction, deferred, whose handler takes a continuation K
;; once; the body inserts 1 and, on its first entry, when K was taken, calls
;; it, so the call is re-entered from inside its own level, with no wind
;; crossed when K lies inside the call's wind. Whether the handler fired;
;; whether the body called K; and the call's answer, with-transaction's
;; BEGIN or SAVEPOINT runs, the extended code, the depth and in-transaction?
;; after it, the outer level over.
(define (claim-reentry-case pass nested? ticks)
  (let* ((old (timer-interrupt-handler))
         (fired #f)
         (called #f)
         (r (dynamic-wind
             (lambda () (begun! pass))
             (lambda ()
              (with-memory
               (lambda (db)
                (when (eq? pass 'low) (traced! db))
                (let* ((k #f) (entries 0)
                      (begin-sql (if nested? "SAVEPOINT chez_sqlite3_1" "BEGIN DEFERRED"))
                      (call (lambda ()
                              (timer-interrupt-handler
                               (lambda ()
                                 (timer-interrupt-handler old)
                                 (timer-fired!)
                                 (set! fired #t)
                                 (call/cc (lambda (c) (set! k c)))))
                              (timer-armed!)
                              (set-timer ticks)
                              (let ((a (attempt
                                        (lambda ()
                                          (with-transaction db 'deferred
                                            (lambda ()
                                              (set! entries (+ entries 1))
                                              (when (and k (= entries 1) (not called))
                                                (set! called #t)
                                                (k #f))
                                              (execute! db "insert into t values (1)")
                                              42))))))
                                (set-timer 0)
                                (timer-done!)
                                (timer-interrupt-handler old)
                                a)))
                      (answer (if nested? (with-transaction db 'deferred call) (call))))
                 (list answer (car (delta '() (own-runs db) (list begin-sql))) (extended db)
                       (database-depth db) (if (in-transaction? db) 'open 'closed))))))
             ended!)))
    (set-timer 0)
    (timer-interrupt-handler old)
    (list fired called r)))

;; claim-reentries : Pass Boolean -> (Listof Any)
;; claim-reentry-case in PASS at every tick from 1 until four in a row do not fire
;; the handler: the ticks whose call answered other than 42 or the ended
;; condition, left a code, a depth or a transaction. Prints how many
;; re-entered the call; fewer than ten is itself a deviation.
(define (claim-reentries pass nested?)
  (let loop ((ticks 1) (unfired 0) (reentered 0) (found '()))
    (if (or (> unfired 3) (>= ticks 2000))
        (begin
          (display (if nested? "  the claim re-entered, nested" "  the claim re-entered, the outer level"))
          (display (if (eq? pass 'low) ", low trip: " ": "))
          (write reentered)
          (display " of ")
          (write (- ticks 1))
          (display " ticks re-entered the call from its body")
          (newline)
          (append (reverse found) (if (< reentered 10) (list (list 'too-few-reentries reentered)) '())))
        (let* ((c (claim-reentry-case pass nested? ticks))
               (r (caddr c))
               (ok (and (list? r) (= (length r) 5)
                        (member (car r) '(42 (raised (transaction-ended with-transaction))))
                        (memv (cadr r) '(1 2))
                        (eqv? (caddr r) 0)
                        (eqv? (cadddr r) (if nested? 0 0))
                        (eq? (list-ref r 4) 'closed))))
          (loop (+ ticks 1) (if (car c) 0 (+ unfired 1)) (if (cadr c) (+ reentered 1) reentered)
                (if ok found (cons (list ticks c) found)))))))

(define reentry-name
  "the claim is read in the BEGIN's own section: a continuation a timer's handler took inside the call, called from the body's first entry while the level is open, at every tick until four in a row do not fire, at the outer level and nested: the call answers 42 or the ended condition, never SQLite's refused BEGIN; the extended code is 0, the depth 0 and nothing left open; at least ten ticks re-enter")

(test-equal reentry-name
  '(() ())
  (let* ((outer (claim-reentries 'high #f))
         (nested (claim-reentries 'high #t)))
    (list outer nested)))

(test-equal (string-append "the same, each case under a collect trip of 256 bytes, its connection carrying SQLite's trace, so a request falls due inside the BEGIN's section and is handled at its exit, where the timer's ticks can run out and its handler take the continuation: the same verdicts, and collect requests met in the cases, each forced section's request met before the next, until the timer fired, and some timer run out at a forced section's exit. " reentry-name)
  (append '(() ()) low-checks)
  (let-values (((r tally) (counted-pass (lambda ()
                                          (let* ((outer (claim-reentries 'low #f))
                                                 (nested (claim-reentries 'low #t)))
                                            (list outer nested))))))
    (append r (low-reported "the claim re-entered" tally))))

;; --- the BEGIN's plan, read in the BEGIN's section --------------------------------------------
;;
;; Autocommit, the depth and the refusal's pass are read in the BEGIN's own
;; section, so no expiry splits the plan from the step. An expiry between
;; them would let another engine begin a transaction on the connection, and
;; the resumed call step BEGIN IMMEDIATE inside it, which SQLite refuses,
;; "cannot start a transaction within a transaction", after taking its lock:
;; a second connection's BEGIN IMMEDIATE answers busy (ADR-0017, "no BEGIN
;; is ever issued inside a transaction").

;; stale-trial : Positive-Integer -> (U 'completed (List Any ...))
;; At FUEL, on a fresh file and two connections to it, the second with no
;; busy timeout: engine A runs with-transaction, immediate, its body noting
;; that it ran and answering 42, for one slice; 'completed when that slice
;; completed it. Else the connection's own BEGIN, run to its end by engine
;; B; then A resumed to its end. A's answer; whether its body ran; the
;; second connection's BEGIN IMMEDIATE, then its rollback, began or what it
;; raised; in-transaction?, B's transaction still open; B's answer; B's
;; transaction rolled back; and the runs of SAVEPOINT chez_sqlite3_0, A's
;; level inside B's transaction.
(define (stale-trial fuel)
  (with-files
   (lambda (db db2)
     (let* ((ran 'not-run)
            (first ((make-engine (lambda ()
                                   (attempt (lambda ()
                                              (with-transaction db 'immediate
                                                (lambda () (set! ran 'ran) 42))))))
                    fuel complete expire)))
       (if (pair? first)
           'completed
           (let* ((b ((make-engine (lambda () (attempt (lambda () (execute! db "begin") 'began))))
                      1000000 complete (lambda (more) 'b-expired)))
                  (a (finish first 1000000))
                  (inside-b (car (delta '() (own-runs db) '("SAVEPOINT chez_sqlite3_0"))))
                  (other (attempt (lambda () (execute! db2 "begin immediate") (execute! db2 "rollback") 'began)))
                  (in (if (in-transaction? db) 'open 'closed))
                  (rolled (attempt (lambda () (execute! db "rollback") 'rolled-back))))
             (list a ran other in (cadr b) rolled inside-b)))))))

(test-equal "the BEGIN's plan is read in the BEGIN's own section: at every fuel from 1 until engine A's with-transaction, immediate, completes in its first slice, the connection's own BEGIN run by engine B at A's first expiry, then A resumed: A answers 42 from a savepoint inside B's transaction, or the ended condition when its expiry fell inside its level, its body run either way; never SQLite's refused BEGIN; the second connection's BEGIN IMMEDIATE begins, so no lock was taken; B's transaction stays open"
  '()
  (let loop ((fuel 1) (found '()) (savepoints 0))
    (let ((r (stale-trial fuel)))
      (cond ((or (eq? r 'completed) (>= fuel 5000))
             (display "  the stale plan: A completed in its first slice at fuel ")
             (write fuel)
             (display "; A's resumes that began a savepoint inside B's transaction and answered 42: ")
             (write savepoints)
             (newline)
             (append (reverse found)
                     (if (eq? r 'completed) '() '(no-completion))
                     (if (< savepoints 3) (list (list 'too-few-savepoints savepoints)) '())))
            ((and (list? r) (= (length r) 7)
                  (member (car r) '(42 (raised (transaction-ended with-transaction))))
                  (equal? (list-head (cdr r) 5) '(ran began open began rolled-back)))
             (loop (+ fuel 1) found
                   (if (and (eqv? (car r) 42) (eqv? (list-ref r 6) 1)) (+ savepoints 1) savepoints)))
            (else (loop (+ fuel 1) (cons (list fuel r) found) savepoints))))))

;; --- an engine taken outside the call, resumed inside a sibling -------------------------------
;;
;; Inside an outer W, an engine runs a nested level A for one slice; then
;; W's body runs a sibling B, and inside B's body resumes A to its end.
;; Chez runs B's after thunk, then its before thunk, on the resume, as for any
;; continuation taken outside B: B's level is rolled back as the resume leaves
;; it, and B's return raises the ended condition.

;; siblings : Database Positive-Integer -> (List Any ...)
;; At FUEL: whether A's first slice expired, or its answer; A's answer once
;; resumed inside B; B's; W's; the extended code, the depth after W, the
;; markers, and the SAVEPOINTs the connection tracks.
(define (siblings db fuel)
  (let* ((a-first #f) (a-answer 'a-not-resumed) (b-answer #f)
         (w (attempt
             (lambda ()
               (with-transaction db 'deferred
                 (lambda ()
                   (execute! db "insert into t values ('w')")
                   (let ((rem ((make-engine
                                (lambda ()
                                  (attempt (lambda ()
                                             (with-transaction db
                                               (lambda () (execute! db "insert into t values ('a')") 42))))))
                               fuel complete expire)))
                     (set! a-first (if (procedure? rem) 'expired (cadr rem)))
                     (set! b-answer
                           (attempt (lambda ()
                                      (with-transaction db
                                        (lambda ()
                                          (execute! db "insert into t values ('b')")
                                          (when (procedure? rem) (set! a-answer (finish rem 1000000)))
                                          'b-returned)))))
                     'w-returned))))))
         (code (extended db))
         (depth (database-depth db))
         (rows (attempt (lambda ()
                          (let loop ((rest (query db "select x from t order by x")) (out '()))
                            (if (null? rest) (reverse out) (loop (cdr rest) (cons (vector-ref (car rest) 0) out)))))))
         (savepoints (filter (lambda (s) (prefix? "SAVEPOINT" s)) (sql-texts db))))
    (list a-first a-answer b-answer w code depth rows savepoints)))

(test-equal "an engine taken outside a call and resumed inside a sibling leaves the sibling: inside W, nested A runs one slice in an engine, then sibling B resumes A inside its body. At every fuel from 1 until A's first slice completes, B's level is rolled back as the resume leaves it, so B's return raises &sqlite-transaction-ended and B's row is gone, while A answers 42 or the ended condition; W commits; the depth is 0 after W, the extended code 0, and the only savepoint ever tracked is SAVEPOINT chez_sqlite3_1. At the completing fuel, B commits its row"
  '()
  (let loop ((fuel 1) (found '()))
    (let* ((r (with-files (lambda (db db2) (siblings db fuel))))
           (ok (and (list? r) (= (length r) 8)))
           (expired (and ok (eq? (car r) 'expired)))
           (deviation
            (cond ((not ok) (list fuel 'the-case-raised r))
                  (expired
                   (and (not (and (member (cadr r) '(42 (raised (transaction-ended with-transaction))))
                                  (member (list-ref r 6) '(("a" "w") ("w")))
                                  (equal? (cddr r) (list '(raised (transaction-ended with-transaction)) 'w-returned 0 0
                                                         (list-ref r 6) '("SAVEPOINT chez_sqlite3_1")))))
                        (list fuel r)))
                  (else
                   (and (not (equal? r '(42 a-not-resumed b-returned w-returned 0 0 ("a" "b" "w")
                                         ("SAVEPOINT chez_sqlite3_1"))))
                        (list fuel r)))))
           (found* (if deviation (cons deviation found) found)))
      (cond ((and ok (not expired))
             (display "  the siblings: A's first slice expired at fuels 1 to ")
             (write (- fuel 1))
             (display ", and completed at fuel ")
             (write fuel)
             (newline)
             (if (> fuel 2) (reverse found*) (cons 'too-few-expiring-fuels (reverse found*))))
            ((or (not ok) (>= fuel 5000)) (cons 'no-completion (reverse found*)))
            (else (loop (+ fuel 1) found*))))))

(test-equal "the profile trace's callback was locked at the load, and is unlocked once every connection is closed"
  '(locked unlocked)
  (list profile-locked
        (guard (e (#t (list 'raised (describe e))))
          (unlock-object profile)
          'unlocked)))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "transaction-engine")

(exit (suite-exit-status runner))
