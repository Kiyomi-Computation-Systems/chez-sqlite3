#!r6rs
;;; The suite for one query-fold's runs interleaved (ADR-0016, amended in M3
;;; slice 5's part D; the maintainer's "Guard every call", ADR-0016, amended in
;;; M3 slice 3), in (chez-sqlite3 private conveniences): one remainder of the
;;; call, R, resumed again while an earlier resume of it, R1, is pending. The
;;; schedule, the tell, the bound and the judge are (conveniences-pending)'s,
;;; tests/conveniences-pending.sls, shared with the other conveniences' suites,
;;; one a convenience, so each stays well under the memory gate's limit.
;;;
;;;   the tell     one query-fold outside any engine: the authorizer notes its
;;;                select prepared once, and the cache keeps its statement,
;;;                ready
;;;   interleaved  query-fold of a sum over t's three rows, cold: R taken at
;;;                every fuel from 1 until the call completes without expiring;
;;;                R resumed at every later fuel until that resume completes,
;;;                R1 taken where it expires; then R resumed again to its end,
;;;                then R1. After every trial: each run answers the sum, 6, or
;;;                &sqlite-closed from query-fold, or call-with-open-handle's
;;;                refusal of a re-entry: the fold does not survive a
;;;                preemption; the select was prepared once, twice only for a
;;;                whole new call, below the sweep's first refusal before the
;;;                call's first section; no statement is tracked
;;;                outside the cache, none at a row, the cache holding the
;;;                call's statement, ready, or none, an expiry inside the
;;;                fold's wind having finalized it; nothing is counted once the
;;;                connection is closed. Enough trials interleave past the
;;;                call's first section, and both past it
;;;   a timer      a timer handler that raises, at every tick until the call
;;;                completes before it runs: the raise reaches the caller, the
;;;                fold's wind finishing its statement
;;;
;;; The fold keeps slice 3's flag: an expiry inside its wind finishes the
;;; statement and sets the flag, so no second run reaches a statement another
;;; holds. Its code is unchanged by part D, and the row holds it so.
;;;
;;; Its low pass, the interleaved row under a collect trip of 256 bytes, is
;;; tests/test-conveniences-pending-fold-low.sps, a suite of its own: this one
;;; took 73 to 85 s on CI under the memory gate, and the low pass costs more.
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

(test-begin "conveniences-pending-fold")

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

(let* ((name "the tell: one query-fold outside any engine answers the sum of t's rows, the authorizer noting its select prepared once; the cache keeps its statement, ready, and nothing is counted once the connection is closed")
       (noted? (tell-kept? registration name "count of the prepares the authorizer noted")))
  (test-equal name
    (list 6 (tell-noted noted? 1) '(1 2 3) '(("select x from t where x > ?" . ready)) 1 zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (clean-call 'query-fold noted?))))

(let ((name "query-fold's remainder R, taken at every fuel from 1 until the call completes without expiring, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1: each run answers the sum or &sqlite-closed from query-fold, or a re-entry's refusal; the select is prepared once, twice only for a whole new call, below the sweep's first refusal before the call's first section; no statement is tracked outside the cache, none at a row, the cache holding the call's statement, ready, or none, an expiry inside the fold's wind having finalized it; nothing is counted once each connection is closed; and at least three trials a fuel on average interleave past the call's first section, and as many both past it"))
  (tell-available! registration name)
  (test-equal name
    (list '() 'interleavings-reached 'refused-at-half-the-fuels 'whole-new-calls-below-a-refusal zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (reported 'query-fold 'every 'high past-a-fuel both-a-fuel))))

(let* ((name "a timer handler that raises, at every tick from 1 until query-fold completes before it runs, the raise reaching the caller from between two of the call's sections: the call answers, or the raise reaches the caller, the very symbol; the statement is prepared at most once; no statement is tracked outside the cache, none at a row, the cache holding the call's statement, ready, or none, the raise having finalized it; nothing is counted once each connection is closed")
       (prepares? (tell-kept? registration name "check that the statement is prepared at most once, as the authorizer noted")))
  (test-equal name
    (list '() 'some-raised zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (timer-reported 'query-fold (timer-sweep 'query-fold prepares?)))))

(let ((name "the entry point is unregistered once the sweep is done: a select prepared after it is not noted"))
  (tell-available! registration name)
  (test-equal name
    '(reset 0)
    (tell-reset)))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "conveniences-pending-fold")

(exit (suite-exit-status runner))
