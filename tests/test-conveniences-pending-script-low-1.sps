#!r6rs
;;; The suite for one execute-script!'s runs interleaved under a collect trip
;;; of 256 bytes, at the fuels whose remainder by 4 is 1 (ADR-0016, amended in
;;; M3 slice 5's part D and in M4 slice 4; M4's closing review, reviewer B's
;;; B1), in (chez-sqlite3 private conveniences): a quarter of the low pass of
;;; the interleaved row of tests/test-conveniences-pending-script-even.sps and
;;; -odd.sps. The four suites tests/test-conveniences-pending-script-low-0.sps
;;; to -3.sps deal the fuels by their remainder by 4: each runs every G at its
;;; own, and G = 1 alone at the rest, which tells where the call completes.
;;; The high row's two halves took 119 to 196 s on CI under the memory gate,
;;; and two low halves 167 and 169 s here, half again as costly. The
;;; schedule, the tell, the bound, the judge and the two passes are
;;; (conveniences-pending)'s, tests/conveniences-pending.sls.
;;;
;;;   interleaved  the high row, its trials at those fuels, each under a
;;;                collect trip of 256 bytes from its start to its end, its
;;;                connection carrying the profile trace, which allocates
;;;                32 KiB as a statement finishes: a request due inside a
;;;                critical section is handled at its exit and costs the
;;;                engine ticks there, so R1 is taken at a section's exit too.
;;;                The same verdicts, each trial judged by itself and bounded
;;;                by the sweep's own refusals; and it fails by name unless
;;;                collect requests fell in its trials, and unless some trial
;;;                had R before the give-back and R1 past it
;;;
;;; Where this libsqlite3 refuses sqlite3_auto_extension, as Apple's does,
;;; there is no tell, and the row is skipped through (conveniences-pending)'s
;;; tell-available!, which prints UNAVAILABLE, so nothing is unavailable
;;; silently.
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

(test-begin "conveniences-pending-script-low-1")

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

(let ((name (string-append "the same, its trials under a collect trip of 256 bytes, each trial's connection carrying the profile trace, which allocates 32 KiB as a statement finishes, so a collect request falls due inside the section that finishes it and is handled at its exit: the same verdicts, each trial judged by itself and bounded by the sweep's own refusals; some trial has R before the give-back and R1 past it; and collect requests met in the trials. " "execute-script!'s remainder R, taken at every fuel whose remainder by 4 is 1 until the call completes without expiring, the other fuels the three other suites', resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1: each run answers no value or &sqlite-closed from execute-script!, or the block's refusal of a re-entry; each insert is prepared at most once and its first once, its rows a prefix of the script's, none twice, each twice only for a whole new call, below the sweep's first refusal before the call's first section; no statement is tracked, none at a row; nothing is counted once each connection is closed; and at least three trials a fuel on average interleave past the call's first section, none both past it, every section of the script lying inside its block")))
  (tell-available! registration name)
  (test-equal name
    (list '() 'interleavings-reached 'refused-at-half-the-fuels 'whole-new-calls-below-a-refusal
          'straddled-the-give-back 'collect-requests-met zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (reported 'execute-script! '(mod 4 1) 'low past-a-fuel both-a-fuel))))

(let ((name "the entry point is unregistered once the sweep is done: a select prepared after it is not noted"))
  (tell-available! registration name)
  (test-equal name
    '(reset 0)
    (tell-reset)))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "conveniences-pending-script-low-1")

(exit (suite-exit-status runner))
