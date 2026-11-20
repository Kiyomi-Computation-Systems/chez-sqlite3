#!r6rs
;;; The suite for one query-row's runs interleaved (ADR-0016), in (chez-sqlite3
;;; private conveniences): one remainder of the call, R, resumed again while an
;;; earlier resume of it, R1, is pending. The schedule, the tell, the bound and
;;; the judge are (conveniences-pending)'s, tests/conveniences-pending.sls,
;;; shared with the other conveniences' suites, one a convenience, so each
;;; stays well under the memory gate's limit.
;;;
;;;   the tell     one query-row outside any engine: the authorizer notes its
;;;                select prepared once, and the cache keeps its statement,
;;;                ready
;;;   interleaved  query-row of a select on t's three rows, cold: R taken at
;;;                every fuel from 1 until the call completes without expiring;
;;;                R resumed at every later fuel until that resume completes,
;;;                R1 taken where it expires; then R resumed again to its end,
;;;                then R1. After every trial: each run answers the first row
;;;                or &sqlite-closed from query-row; the select was prepared
;;;                once, twice only for a whole new call, below the sweep's first
;;;                refusal before the call's first section;
;;;                no statement is tracked outside the cache, none at a row,
;;;                the cache holding the call's statement, ready; nothing is
;;;                counted once the connection is closed. Enough trials
;;;                interleave past the call's first section, and both past it
;;;   low trip     the interleaved row again under a collect trip of 256
;;;                bytes, where a request due inside a critical section is
;;;                handled at its exit and costs the engine ticks there, so R1
;;;                is taken at a section's exit too: a claim advanced just
;;;                after its section, not inside it, inserted execute!'s row
;;;                twice there. SQLite's trace allocates 32 KiB inside each
;;;                section that steps a row or finishes a statement, so a
;;;                request falls due there.
;;;                Each fails by name unless collect requests fell in its
;;;                trials, unless some trial had R before the give-back and R1
;;;                past it, unless each such section met its request before
;;;                the next, and unless some first slice expired at such a
;;;                section's exit
;;;   a timer      a timer handler that raises, at every tick until the call
;;;                completes before it runs: the raise reaches the caller, the
;;;                statement given back, ready, by the call's claim of whatever
;;;                position is next
;;;   taken        a timer handler that takes a statement for the call's SQL,
;;;                steps it to its row and raises, at every tick: the call's
;;;                give-back leaves the taken statement alone, still at its row
;;;   a keyboard   a keyboard interrupt pending inside query-row's check-out,
;;;                SIGINT raised from SQLite's authorizer as the miss's prepare
;;;                runs: its handler raises before the call has its statement
;;;                in hand, and the call gives it back all the same; and one
;;;                pending inside query-row's return,
;;;                SIGINT raised from SQLite's profile trace: its handler takes
;;;                the statement the return filed and raises, and the call, its
;;;                claim ended, gives nothing back
;;;
;;; Where this libsqlite3 refuses sqlite3_auto_extension, as Apple's does,
;;; there is no tell. A row whose every check needs it is skipped, through
;;; (conveniences-pending)'s tell-available!; a row with one check that
;;; reads it runs its others, through tell-kept?. Either prints UNAVAILABLE,
;;; so nothing is unavailable silently.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise.
(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (conveniences-pending))

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

;; past-a-fuel, both-a-fuel : Natural
;; The fewest trials a fuel on average, over the fuels up to the one at which the call
;; completes, that interleave past the call's first section, and that are
;; both past it, for a sweep that reaches anything: a sweep that reused one
;; R across every G makes at most one a fuel.
(define past-a-fuel 3)
(define both-a-fuel 3)

(test-begin "conveniences-pending-query-row")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

;; direct : (U Integer (List 'raised Any))
;; What sqlite3_auto_extension answered for an entry point that does
;; nothing, registered straight through the FFI before the tell, then reset:
;; the gate's independent reading.
(define direct (tell-direct))

;; registration : (U 'registered (List 'auto-extension-answered Integer) (List 'raised Any))
;; The tell's registration, which every row that depends on the tell is
;; gated by, through tell-available! or tell-kept?.
(define registration (tell-registered))

(test-equal "the authorizer is registered for every new connection, through sqlite3_auto_extension, or the call is refused with its code; registering raises nothing"
  'registered-or-refused
  (if (tell-answered? registration) 'registered-or-refused registration))

(test-equal "the gate refuses the tell exactly when sqlite3_auto_extension, given an entry point that does nothing straight through the FFI, answers 21, and registers it exactly when that answers 0"
  'gate-held
  (tell-gate-held registration direct))

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(let* ((name "the tell: one query-row outside any engine answers t's first row, the authorizer noting its select prepared once; the cache keeps its statement, ready, and nothing is counted once the connection is closed")
       (noted? (tell-kept? registration name "count of the prepares the authorizer noted")))
  (test-equal name
    (list '#(1) (tell-noted noted? 1) '(1 2 3) '(("select x from t where x > ?" . ready)) 1 zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (clean-call 'query-row noted?))))

(let ((name "query-row's remainder R, taken at every fuel from 1 until the call completes without expiring, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1: each run answers the first row or &sqlite-closed from query-row; the select is prepared once, twice only for a whole new call, below the sweep's first refusal before the call's first section; no statement is tracked outside the cache, none at a row, the cache holding the call's statement, ready; nothing is counted once each connection is closed; and at least three trials a fuel on average interleave past the call's first section, and as many both past it"))
  (tell-available! registration name)
  (test-equal name
    (list '() 'interleavings-reached 'refused-at-half-the-fuels 'whole-new-calls-below-a-refusal zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (reported 'query-row 'every 'high past-a-fuel both-a-fuel))))

(let ((name (string-append "the same, its trials under a collect trip of 256 bytes, each trial's connection carrying SQLite's trace and the tell's authorizer, which allocate 32 KiB as a step answers a row, a statement finishes, or a statement is prepared, so a collect request falls due inside the section that steps or prepares it and is handled at its exit: the same verdicts, each trial judged by itself and bounded by the sweep's own refusals; some trial has R before the give-back and R1 past it; and collect requests met in the trials, each forced section's request met before the next, and some first slice expired at a forced section's exit. " "query-row's remainder R, taken at every fuel from 1 until the call completes without expiring, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1: each run answers the first row or &sqlite-closed from query-row; the select is prepared once, twice only for a whole new call, below the sweep's first refusal before the call's first section; no statement is tracked outside the cache, none at a row, the cache holding the call's statement, ready; nothing is counted once each connection is closed; and at least three trials a fuel on average interleave past the call's first section, and as many both past it")))
  (tell-available! registration name)
  (test-equal name
    (list '() 'interleavings-reached 'refused-at-half-the-fuels 'whole-new-calls-below-a-refusal
          'straddled-the-give-back 'collect-requests-met
          'every-forced-section-met-its-request 'taken-at-a-forced-exit zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (reported 'query-row 'every 'low past-a-fuel both-a-fuel))))

(let* ((name "a timer handler that raises, at every tick from 1 until query-row completes before it runs, the raise reaching the caller from between two of the call's sections: the call answers, or the raise reaches the caller, the very symbol; the statement is prepared at most once and its effect made at most once; no statement is tracked outside the cache, none at a row, the cache holding the call's statement, ready, or none where the raise came before its check-out, and the statement given back wherever one was counted as the handler raised, a reading that needs no tell; nothing is counted once each connection is closed")
       (prepares? (tell-kept? registration name "check that the statement is prepared at most once, as the authorizer noted")))
  (test-equal name
    (list '() 'some-raised zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (timer-reported 'query-row (timer-sweep 'query-row prepares?)))))

(test-equal "a timer handler that takes a statement for query-row's SQL from the cache, or a fresh one, steps it to its row, then raises, at every tick from 1 until the call completes before it runs: the call answers, or the raise reaches the caller; the taken statement is still at its row, left alone by the call's give-back, even once the call has given its own back and the handler took that one; once the trial gives it back, the cache holds the call's statement, ready, nothing at a row, and nothing is counted once each connection is closed"
  (list '() 'some-raised zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (timer-reported 'query-row (taken-sweep 'query-row))))

(test-equal "a keyboard interrupt that comes pending inside query-row's return, SIGINT raised from SQLite's profile trace as the return's reset finishes the statement: the keyboard handler, run as the return's section ends, takes the statement the return has just filed, binds and steps it to its row, and raises; the raise reaches the caller, and the call, its claim ended with the return, gives nothing back: the taken statement stays at its row, out of the cache; given back, it is the cache's one statement, ready, and nothing is counted once the connection is closed"
  (list 'interrupt 'row 0 '(("select x from t where x > ?" . ready)) 1 'counts-kept)
  (keyboard-in 'query-row 'return))

(let ((name "a keyboard interrupt that comes pending inside query-row's check-out, SIGINT raised from SQLite's authorizer as the miss's prepare runs: the keyboard handler, run as the check-out's section ends, raises before the call has its statement in hand; the raise reaches the caller, and the call gives the statement back all the same, noted inside the section: the cache holds it, ready, and nothing is counted once the connection is closed"))
  (tell-available! registration name)
  (test-equal name
    (list 'interrupt #f 1 '(("select x from t where x > ?" . ready)) 1 'counts-kept)
    (keyboard-in 'query-row 'check-out)))

(let ((name "the entry point is unregistered once the sweep is done: a select prepared after it is not noted"))
  (tell-available! registration name)
  (test-equal name
    '(reset 0)
    (tell-reset)))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "conveniences-pending-query-row")

(exit (suite-exit-status runner))
