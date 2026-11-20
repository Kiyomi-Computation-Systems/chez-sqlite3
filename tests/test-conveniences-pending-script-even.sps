#!r6rs
;;; The suite for one execute-script!'s runs interleaved, at the even fuels
;;; (ADR-0016), in (chez-sqlite3 private conveniences): one remainder of the
;;; call, R, resumed again while an earlier resume of it, R1, is pending. The
;;; schedule, the tell, the bound and the judge are (conveniences-pending)'s,
;;; tests/conveniences-pending.sls, shared with the other conveniences' suites,
;;; one a convenience, so each stays well under the memory gate's limit.
;;;
;;;   the tell     one execute-script! outside any engine: the authorizer notes
;;;                each of its two inserts prepared once, its rows inserted
;;;                once, and nothing is tracked or cached
;;;   interleaved  execute-script! of two inserts into t, cold: R taken at
;;;                every even fuel until the call completes without expiring; R
;;;                resumed at every later fuel until that resume completes, R1
;;;                taken where it expires; then R resumed again to its end,
;;;                then R1. After every trial: each run answers no value or
;;;                &sqlite-closed from execute-script!, or call-with-block's
;;;                refusal of a re-entry: the script does not survive a
;;;                preemption; each insert was prepared at most once, and its
;;;                rows are a prefix of the script's, in order, none twice,
;;;                each twice only for a whole new call, below the sweep's
;;;                first refusal before the call's first section; no
;;;                statement is tracked, none at a row; nothing is counted once
;;;                the connection is closed. Enough trials interleave past the
;;;                call's first section
;;;
;;; The script's sweep makes about 52,000 trials, about 225 s under the memory
;;; gate in one suite, so it is split by the parity of R's fuel: this suite
;;; runs every G at the even fuels, and G = 1 alone at the odd, which tells
;;; where the call completes; tests/test-conveniences-pending-script-odd.sps
;;; runs the rest. Every section of the script lies inside its block, and an
;;; expiry there frees the block, so no trial has both runs past its first
;;; section. The rows hold it so.
;;;
;;; Its low pass, the interleaved row under a collect trip of 256 bytes, is
;;; four suites of their own, tests/test-conveniences-pending-script-low-0.sps
;;; to -3.sps, dealt by R's fuel modulo 4, for both halves at once: this one
;;; took 119 to 194 s on CI under the memory gate, and the low pass costs more.
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

;; past-a-fuel : Natural
;; both-a-fuel : 'none
;; The fewest trials a fuel on average, over the fuels up to the one at which the call
;; completes, that interleave past the call's first section, for a sweep
;; that reaches anything: a sweep that reused one R across every G makes at
;; most one a fuel. None is both past it, and the row holds that none is:
;; every section of the script lies inside its block, and an expiry there
;; frees the block, so R taken past the first prepare is refused by
;; call-with-block as it resumes.
(define past-a-fuel 3)
(define both-a-fuel 'none)

(test-begin "conveniences-pending-script-even")

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

(let* ((name "the tell: one execute-script! outside any engine inserts its two rows once, the authorizer noting each of its two inserts prepared once; nothing is tracked or cached, and nothing is counted once the connection is closed")
       (noted? (tell-kept? registration name "count of the prepares the authorizer noted")))
  (test-equal name
    (list 'no-value (tell-noted noted? 2) '(1 2 3 7 8) '() 0 zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (clean-call 'execute-script! noted?))))

(let ((name "execute-script!'s remainder R, taken at every even fuel from 2 until the call completes without expiring, the odd fuels the other suite's, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1: each run answers no value or &sqlite-closed from execute-script!, or the block's refusal of a re-entry; each insert is prepared at most once and its first once, its rows a prefix of the script's, none twice, each twice only for a whole new call, below the sweep's first refusal before the call's first section; no statement is tracked, none at a row; nothing is counted once each connection is closed; and at least three trials a fuel on average interleave past the call's first section, none both past it, every section of the script lying inside its block"))
  (tell-available! registration name)
  (test-equal name
    (list '() 'interleavings-reached 'refused-at-half-the-fuels 'whole-new-calls-below-a-refusal zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (reported 'execute-script! 'even 'high past-a-fuel both-a-fuel))))

(let ((name "the entry point is unregistered once the sweep is done: a select prepared after it is not noted"))
  (tell-available! registration name)
  (test-equal name
    '(reset 0)
    (tell-reset)))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "conveniences-pending-script-even")

(exit (suite-exit-status runner))
