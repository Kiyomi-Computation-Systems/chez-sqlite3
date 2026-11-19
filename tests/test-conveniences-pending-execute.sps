#!r6rs
;;; The suite for one execute!'s runs interleaved (ADR-0016, amended in M3
;;; slice 5's part D; the maintainer's "Guard every call", ADR-0016, amended in
;;; M3 slice 3), in (chez-sqlite3 private conveniences): one remainder of the
;;; call, R, resumed again while an earlier resume of it, R1, is pending. The
;;; schedule, the tell, the bound and the judge are (conveniences-pending)'s,
;;; tests/conveniences-pending.sls, shared with the other conveniences' suites,
;;; one a convenience, so each stays well under the memory gate's limit.
;;;
;;;   the tell     one execute! outside any engine: the authorizer notes its
;;;                insert prepared once, its row inserted once, and the cache
;;;                keeps its statement, ready
;;;   interleaved  execute! of an insert into t, cold: R taken at every fuel
;;;                from 1 until the call completes without expiring; R resumed
;;;                at every later fuel until that resume completes, R1 taken
;;;                where it expires; then R resumed again to its end, then R1.
;;;                After every trial: each run answers no value or &sqlite-
;;;                closed from execute!; the insert was prepared once and its
;;;                row inserted once, each twice only for a whole new call,
;;;                below the sweep's first refusal before the call's first
;;;                section; no statement is tracked outside the cache,
;;;                none at a row, the cache holding the call's statement,
;;;                ready; nothing is counted once the connection is closed.
;;;                Enough trials interleave past the call's first section, and
;;;                both past it
;;;   low trip     the interleaved row again under a collect trip of 256
;;;                bytes, where a request due inside a critical section is
;;;                handled at its exit and costs the engine ticks there, so R1
;;;                is taken at a section's exit too: a claim advanced just
;;;                after its section, not inside it, inserted execute!'s row
;;;                twice there (M4's closing review, reviewer B's B1). SQLite's
;;;                trace allocates 32 KiB inside each section that steps a
;;;                row or finishes a statement, so a request falls due there.
;;;                Each fails by name unless collect requests fell in its
;;;                trials, unless some trial had R before the give-back and R1
;;;                past it, unless each such section met its request before
;;;                the next, and unless some first slice expired at such a
;;;                section's exit
;;;   a timer      a timer handler that raises, at every tick until the call
;;;                completes before it runs: the raise reaches the caller, the
;;;                statement given back, ready, by the call's claim of whatever
;;;                position is next
;;;
;;; Where this libsqlite3 refuses sqlite3_auto_extension, as Apple's does,
;;; there is no tell. A row whose every check needs it is skipped, through
;;; (conveniences-pending)'s tell-available!; a row with one check that
;;; reads it runs its others, through tell-kept?. Either prints UNAVAILABLE,
;;; so nothing is unavailable silently.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise (AGENTS.md).
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

(test-begin "conveniences-pending-execute")

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

(let* ((name "the tell: one execute! outside any engine inserts its row once, the authorizer noting its insert prepared once; the cache keeps its statement, ready, and nothing is counted once the connection is closed")
       (noted? (tell-kept? registration name "count of the prepares the authorizer noted")))
  (test-equal name
    (list 'no-value (tell-noted noted? 1) '(1 2 3 9) '(("insert into t values (?)" . ready)) 1 zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (clean-call 'execute! noted?))))

(let ((name "execute!'s remainder R, taken at every fuel from 1 until the call completes without expiring, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1: each run answers no value or &sqlite-closed from execute!; the insert is prepared once and its row inserted once, each twice only for a whole new call, below the sweep's first refusal before the call's first section; no statement is tracked outside the cache, none at a row, the cache holding the call's statement, ready; nothing is counted once each connection is closed; and at least three trials a fuel on average interleave past the call's first section, and as many both past it"))
  (tell-available! registration name)
  (test-equal name
    (list '() 'interleavings-reached 'refused-at-half-the-fuels 'whole-new-calls-below-a-refusal zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (reported 'execute! 'every 'high past-a-fuel both-a-fuel))))

(let ((name (string-append "the same, its trials under a collect trip of 256 bytes, each trial's connection carrying SQLite's trace and the tell's authorizer, which allocate 32 KiB as a step answers a row, a statement finishes, or a statement is prepared, so a collect request falls due inside the section that steps or prepares it and is handled at its exit: the same verdicts, each trial judged by itself and bounded by the sweep's own refusals; some trial has R before the give-back and R1 past it; and collect requests met in the trials, each forced section's request met before the next, and some first slice expired at a forced section's exit. " "execute!'s remainder R, taken at every fuel from 1 until the call completes without expiring, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1: each run answers no value or &sqlite-closed from execute!; the insert is prepared once and its row inserted once, each twice only for a whole new call, below the sweep's first refusal before the call's first section; no statement is tracked outside the cache, none at a row, the cache holding the call's statement, ready; nothing is counted once each connection is closed; and at least three trials a fuel on average interleave past the call's first section, and as many both past it")))
  (tell-available! registration name)
  (test-equal name
    (list '() 'interleavings-reached 'refused-at-half-the-fuels 'whole-new-calls-below-a-refusal
          'straddled-the-give-back 'collect-requests-met
          'every-forced-section-met-its-request 'taken-at-a-forced-exit zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (reported 'execute! 'every 'low past-a-fuel both-a-fuel))))

(let* ((name "a timer handler that raises, at every tick from 1 until execute! completes before it runs, the raise reaching the caller from between two of the call's sections: the call answers, or the raise reaches the caller, the very symbol; the statement is prepared at most once and its effect made at most once; no statement is tracked outside the cache, none at a row, the cache holding the call's statement, ready, or none where the raise came before its check-out, and the statement given back wherever one was counted as the handler raised, a reading that needs no tell; nothing is counted once each connection is closed")
       (prepares? (tell-kept? registration name "check that the statement is prepared at most once, as the authorizer noted")))
  (test-equal name
    (list '() 'some-raised zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (timer-reported 'execute! (timer-sweep 'execute! prepares?)))))

(let ((name "the entry point is unregistered once the sweep is done: a select prepared after it is not noted"))
  (tell-available! registration name)
  (test-equal name
    '(reset 0)
    (tell-reset)))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "conveniences-pending-execute")

(exit (suite-exit-status runner))
