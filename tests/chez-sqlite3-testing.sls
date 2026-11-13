#!r6rs
;;; (chez-sqlite3-testing): what every suite shares (ADR-0007).
;;;
;;;   suite-exit-form    the last datum of every tests/test-*.sps
;;;   suite-exit-status  the verdict that form exits with: the runner's
;;;                      counts, and (chez-sqlite3 private counters)' native
;;;                      counts
;;;   describe           a raised object as text, for evidence
;;;
;;; Each helper comes with its first consumer. chez-curl's (curl-testing) has
;;; more, such as capture-command, temporary directories and run-until; each
;;; joins this library with the suite that first needs it.
;;;
;;; Test-only: it lives in tests/, which make test puts on Chez's library
;;; path, not in src/. Its own suite is tests/test-chez-sqlite3-testing.sps.
(library (chez-sqlite3-testing)
  (export suite-exit-form suite-exit-status describe)
  (import (rnrs)
          (srfi :64)
          (chez-sqlite3 private counters)
          (only (chezscheme) display-condition))

  ;; --- the shared exit form ------------------------------------------------

  ;; suite-exit-form : Sexp
  ;; The last datum of every tests/test-*.sps, exactly: make check-suites
  ;; reads each suite as data and compares its last datum with this one.
  ;; `runner` is the suite's own binding for the runner it makes current. A
  ;; suite that never makes it current leaves it with no test, and fails.
  (define suite-exit-form '(exit (suite-exit-status runner)))

  ;; suite-exit-status : Test-Runner -> (U 0 1)
  ;; 0 when RUNNER saw a pass, and no failure and no unexpected pass, and every
  ;; count of (chez-sqlite3 private counters) is zero. Otherwise 1, after a
  ;; line on the error port for each rule broken: the runner's counts, then
  ;; each native count that is not zero, in native-kinds order (ADR-0005: a
  ;; native object a suite made and never freed is a leak, which Valgrind sees
  ;; as still reachable when a Chez object held its address). Expected failures
  ;; and skips count neither way. SRFI-64 sets no exit status of its own. The
  ;; answer is 0 or 1, never a count: exit statuses wrap at 256, so 256
  ;; failures would exit 0.
  (define (suite-exit-status runner)
    (unless (test-runner? runner)
      (assertion-violation 'suite-exit-status "not a SRFI-64 test runner" runner))
    (let* ((pass (test-runner-pass-count runner))
           (fail (test-runner-fail-count runner))
           (xpass (test-runner-xpass-count runner))
           (runner-ok? (and (> pass 0) (= fail 0) (= xpass 0)))
           (left (filter (lambda (entry) (not (eqv? (cdr entry) 0))) (native-counts))))
      (if (and runner-ok? (null? left))
          0
          (let ((err (current-error-port)))
            ;; The runner's own summary, on stdout, comes first.
            (flush-output-port (current-output-port))
            (unless runner-ok?
              (put-string err
                (string-append "suite-exit-status: exit 1 (pass " (number->string pass)
                               ", fail " (number->string fail)
                               ", xpass " (number->string xpass)
                               "): a suite needs a pass, and no fail or xpass\n")))
            (unless (null? left)
              (put-string err
                (string-append "suite-exit-status: exit 1 (native objects left: "
                               (join-words*
                                (map (lambda (entry)
                                       (string-append (symbol->string (car entry)) " "
                                                      (number->string (cdr entry))))
                                     left))
                               "): every native object a suite makes must be freed by its end\n")))
            (flush-output-port err)
            1))))

  ;; join-words* : (Listof String) -> String
  ;; WORDS joined with ", ", or "none" for no words.
  (define (join-words* words)
    (if (null? words)
        "none"
        (fold-left (lambda (line word) (string-append line ", " word)) (car words) (cdr words))))

  ;; --- describe ------------------------------------------------------------

  ;; describe : Any -> String
  ;; OBJ as text: a condition as Chez displays it, anything else as written.
  ;; A raise while printing gives a fixed string instead, so evidence never
  ;; raises.
  (define (describe obj)
    (guard (e (#t "<the raised object could not be printed>"))
      (call-with-string-output-port
       (lambda (p)
         (if (condition? obj) (display-condition obj p) (write obj p)))))))
