#!r6rs
;;; The suite for (chez-sqlite3-testing): suite-exit-form, suite-exit-status
;;; and describe.
;;;
;;; Each expected value is one the code under test cannot produce by failing.
;;; SRFI-64 turns a raise in the actual expression into #f, so no expected
;;; value here is #f, and a refusal is compared, who and irritants, against a
;;; no-raise sentinel.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) parameterize record-writer)
        ;; Chez's own current-error-port is a parameter; (rnrs)'s takes no
        ;; argument, and reads the same port.
        (prefix (only (chezscheme) current-error-port) chez:)
        (chez-sqlite3 private counters)
        (chez-sqlite3-testing))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) (quote (fail xpass)))
        (display "  expected: ")
        (write (test-result-ref r (quote expected-value)))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r (quote actual-value)))
        (newline)))))

;; raised : (-> Any) -> Any
;; What THUNK raised: (assertion-violation WHO IRRITANTS) for an assertion
;; violation, (other-raise TEXT) for any other raise, and the symbol no-raise
;; if THUNK returned.
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other-raise (describe e))))
    (thunk)
    'no-raise))

(test-begin "chez-sqlite3-testing")

;; --- suite-exit-form ------------------------------------------------------

(test-equal "suite-exit-form is exactly the datum (exit (suite-exit-status runner))"
  ;; Built, not quoted: make check-suites refuses a quoted exit form.
  (list (string->symbol "exit") (list 'suite-exit-status 'runner))
  suite-exit-form)

;; --- suite-exit-status: the verdict behind the shared exit form -----------
;; Each runner below is a fresh null runner, which prints nothing and which
;; this suite's own runner never sees. Each base holds the outcomes the rule
;; under test must ignore, so that only that rule can produce the expected
;; verdict.

;; runner-after : (-> Any) -> Test-Runner
(define (runner-after thunk)
  (let ((r (test-runner-null)))
    (test-with-runner r
      (test-begin "inner")
      (thunk)
      (test-end "inner"))
    r))

;; verdict : Test-Runner -> (List Integer String)
;; suite-exit-status's answer, then everything it wrote to the error port.
(define (verdict r)
  (let-values (((port contents) (open-string-output-port)))
    (let ((status (parameterize ((chez:current-error-port port))
                    (suite-exit-status r))))
      (list status (contents)))))

(define runner-tail "): a suite needs a pass, and no fail or xpass\n")

(test-equal "a pass beside an expected failure and a skip: exit 0, and nothing said"
  '(0 "")
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-expect-fail 1)
                           (test-assert "fails, as expected" #f)
                           (test-skip 1)
                           (test-assert "skipped" #t)))))

(test-equal "two failures beside a pass: exit 1, not a count, since exit statuses wrap at 256"
  (list 1 (string-append "suite-exit-status: exit 1 (pass 1, fail 2, xpass 0" runner-tail))
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-assert "fails" #f)
                           (test-assert "fails too" #f)))))

(test-equal "256 failures beside a pass: exit 1, since a count of 256 would wrap to 0"
  (list 1 (string-append "suite-exit-status: exit 1 (pass 1, fail 256, xpass 0" runner-tail))
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (do ((i 0 (+ i 1))) ((= i 256))
                             (test-assert "fails" #f))))))

(test-equal "an unexpected pass beside a pass: exit 1"
  (list 1 (string-append "suite-exit-status: exit 1 (pass 1, fail 0, xpass 1" runner-tail))
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-expect-fail 1)
                           (test-assert "passes unexpectedly" #t)))))

(test-equal "an expected failure and a skip, but no pass: exit 1"
  (list 1 (string-append "suite-exit-status: exit 1 (pass 0, fail 0, xpass 0" runner-tail))
  (verdict (runner-after (lambda ()
                           (test-expect-fail 1)
                           (test-assert "fails, as expected" #f)
                           (test-skip 1)
                           (test-assert "skipped" #t)))))

(test-equal "no test at all: exit 1"
  (list 1 (string-append "suite-exit-status: exit 1 (pass 0, fail 0, xpass 0" runner-tail))
  (verdict (runner-after (lambda () 'no-tests))))

(test-equal "suite-exit-status refuses what is not a runner"
  '(assertion-violation suite-exit-status ("not a runner"))
  (raised (lambda () (suite-exit-status "not a runner"))))

;; --- the counters' rule (ADR-0005) ----------------------------------------
;; Each raises counts on purpose, and lowers them again under dynamic-wind,
;; so this suite's own exit, which reads the same counts, sees zero.

;; with-counts : (Listof Symbol) (-> Any) -> Any
;; THUNK's answer, with one more of each kind in KINDS counted while it runs.
(define (with-counts kinds thunk)
  (dynamic-wind
    (lambda () (for-each count-up! kinds))
    thunk
    (lambda () (for-each count-down! kinds))))

(define counts-tail "): every native object a suite makes must be freed by its end\n")

(define (passing-verdict)
  (verdict (runner-after (lambda () (test-assert "passes" #t)))))

(test-equal "a pass, and native objects left: exit 1, one line naming each count not zero, in the counters' order"
  (list 1 (string-append "suite-exit-status: exit 1 (native objects left: block 1, statement 2"
                         counts-tail))
  (with-counts '(statement block statement) passing-verdict))

;; Each kind alone fails a suite that passed: a gate that read some kinds
;; only passes a test of two. Written out here, not read from native-kinds.
(for-each
 (lambda (kind)
   (test-equal (string-append "a pass, and one " (symbol->string kind)
                              " left alone: exit 1, the line naming it")
     (list 1 (string-append "suite-exit-status: exit 1 (native objects left: "
                            (symbol->string kind) " 1" counts-tail))
     (with-counts (list kind) passing-verdict)))
 '(block connection statement))

(test-equal "every kind left is named, each with its count"
  (list 1 (string-append "suite-exit-status: exit 1 (native objects left: block 1, connection 3, statement 1"
                         counts-tail))
  (with-counts '(connection statement block connection connection) passing-verdict))

(test-equal "a failure, and a native object left: both lines, the runner's first"
  (list 1 (string-append
           "suite-exit-status: exit 1 (pass 1, fail 1, xpass 0" runner-tail
           "suite-exit-status: exit 1 (native objects left: connection 1" counts-tail))
  (with-counts '(connection)
    (lambda () (verdict (runner-after (lambda ()
                                        (test-assert "passes" #t)
                                        (test-assert "fails" #f)))))))

(test-equal "the counts are back at zero once with-counts returns: a pass exits 0, and nothing is said"
  (list '((block . 0) (connection . 0) (statement . 0))
        '(0 ""))
  (list (native-counts) (passing-verdict)))

;; --- describe -------------------------------------------------------------

(define-record-type unprintable (fields x))
(record-writer (record-type-descriptor unprintable)
  (lambda (r port wr) (error 'unprintable "this record cannot be printed")))

(test-equal "describe: a condition, as display-condition shows it"
  "Exception in f: bad thing with irritants (1 \"two\")"
  (describe (condition (make-error)
                       (make-who-condition 'f)
                       (make-message-condition "bad thing")
                       (make-irritants-condition '(1 "two")))))

(test-equal "describe: anything else is written, so a string keeps its quotes"
  "(1 \"two\" three)"
  (describe '(1 "two" three)))

(test-equal "describe: an object whose printing raises gets a fixed text, not a raise"
  "<the raised object could not be printed>"
  (describe (make-unprintable 1)))

(test-end "chez-sqlite3-testing")

;; This suite tests suite-exit-status, so its exit cannot rest on it alone:
;; a suite-exit-status that ignored failures would pass this suite, and
;; make test with it. Any failure here exits 1 first.
(when (or (positive? (test-runner-fail-count runner))
          (positive? (test-runner-xpass-count runner)))
  (exit 1))

(exit (suite-exit-status runner))
