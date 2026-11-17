#!r6rs
;;; The suite for one execute!'s runs interleaved (ADR-0016, amended in M3
;;; slice 5's part D; the maintainer's "Guard every call", ADR-0016, amended in
;;; M3 slice 3), in (chez-sqlite3 private conveniences): one remainder of the
;;; call, R, resumed again while an earlier resume of it, R1, is pending. The
;;; schedule, the tell, the control and the judge are (conveniences-pending)'s,
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
;;;                row inserted once, each twice only where the control makes a
;;;                whole new call; no statement is tracked outside the cache,
;;;                none at a row, the cache holding the call's statement,
;;;                ready; nothing is counted once the connection is closed.
;;;                Enough trials interleave past the call's first section, and
;;;                both past it
;;;   a timer      a timer handler that raises, at every tick until the call
;;;                completes before it runs: the raise reaches the caller, the
;;;                statement given back, ready, by the call's claim of whatever
;;;                position is next
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

(test-equal "the authorizer is registered for every new connection, through sqlite3_auto_extension"
  'registered
  (tell-registered))

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-equal "the tell: one execute! outside any engine inserts its row once, the authorizer noting its insert prepared once; the cache keeps its statement, ready, and nothing is counted once the connection is closed"
  (list 'no-value 1 '(1 2 3 9) '(("insert into t values (?)" . ready)) 1 zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (clean-call 'execute!)))

(test-equal "execute!'s remainder R, taken at every fuel from 1 until the call completes without expiring, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1: each run answers no value or &sqlite-closed from execute!; the insert is prepared once and its row inserted once, each twice only where the control makes a whole new call; no statement is tracked outside the cache, none at a row, the cache holding the call's statement, ready; nothing is counted once each connection is closed; and at least three trials a fuel on average interleave past the call's first section, and as many both past it"
  (list '() 'interleavings-reached zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (reported 'execute! (sweep 'execute! 'every) past-a-fuel both-a-fuel)))

(test-equal "a timer handler that raises, at every tick from 1 until execute! completes before it runs, the raise reaching the caller from between two of the call's sections: the call answers, or the raise reaches the caller, the very symbol; the statement is prepared at most once and its effect made at most once; no statement is tracked outside the cache, none at a row, the cache holding the call's statement, ready, or none where the raise came before its check-out; nothing is counted once each connection is closed"
  (list '() 'some-raised zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (timer-reported 'execute! (timer-sweep 'execute!))))

(test-equal "the entry point is unregistered once the sweep is done: a select prepared after it is not noted"
  '(reset 0)
  (tell-reset))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "conveniences-pending-execute")

(exit (suite-exit-status runner))
