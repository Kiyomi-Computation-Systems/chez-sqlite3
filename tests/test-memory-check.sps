#!r6rs
;;; The suite for (chez-sqlite3 private memory-check): the sqlite3_memory_used
;;; check a suite's end runs, with its positive control (ADR-0005, amended).
;;;
;;;   memory-check-outcome  the verdict, from the baseline and the three
;;;                         counts the control reads, on synthetic counts
;;;   make-memory-check     the control's calls and their order, through
;;;                         stub bindings that log each call
;;;
;;; Nothing here loads libsqlite3: test-chez-sqlite3-testing's children run
;;; the check that native registers, on the library. Each expected value is
;;; one the code under test cannot produce by failing: SRFI-64 makes #f of a
;;; raise in the actual expression, so none is #f.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) library-exports)
        (chez-sqlite3-testing)
        (chez-sqlite3 private memory-check))

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
;; THUNK's answer as (no-raise VALUE), or what it raised: (assertion-violation
;; WHO IRRITANTS), or (other TEXT).
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other (describe e))))
    (list 'no-raise (thunk))))

(define (sorted-names names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

;; The outcomes' texts, written out here and not read from the library.
(define (pass-text baseline)
  (string-append "the count is back at its baseline, " (number->string baseline)
                 " bytes, after the control's :memory: open and close"))
(define (fail-text after baseline)
  (string-append "the count is " (number->string after)
                 " bytes after the control's :memory: open and close, not its baseline, "
                 (number->string baseline)
                 " bytes: SQLite still holds memory that a suite's end must have freed"))
(define (unavailable-text before open)
  (string-append "the count was " (number->string before)
                 " bytes before the control's :memory: open and " (number->string open)
                 " while it was open, so this libsqlite3 keeps no memory count"))

(test-begin "memory-check")

(test-equal "(chez-sqlite3 private memory-check) exports exactly memory-check-outcome and make-memory-check"
  (sorted-names '(memory-check-outcome make-memory-check))
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3 private memory-check)))))

;; --- memory-check-outcome: BASELINE BEFORE OPEN AFTER ---------------------------
;; Every base is built from counts that differ, so only the rule under test
;; can give the verdict: a pass whose count before the control was not the
;; baseline, a failure whose count before it was.

(test-equal "back at the baseline after the control, which raised the count: pass, naming the baseline"
  (list 'pass (pass-text 1200))
  (memory-check-outcome 1200 1500 60000 1200))

(test-equal "above the baseline after the control: fail, naming the count and the baseline"
  (list 'fail (fail-text 1500 1200))
  (memory-check-outcome 1200 1200 60000 1500))

(test-equal "below the baseline after the control: fail too, since the baseline is a count to return to, not a ceiling"
  (list 'fail (fail-text 900 1200))
  (memory-check-outcome 1200 1500 60000 900))

(test-equal "a rise of one byte is a rise: the check runs"
  (list (list 'pass (pass-text 700)) (list 'fail (fail-text 701 700)))
  (list (memory-check-outcome 700 700 701 700)
        (memory-check-outcome 700 700 701 701)))

;; A library that keeps no count answers one number throughout, as Apple's
;; answers 0 (ADR-0005, amended). Unavailable whatever the baseline, since a
;; count that never moves can say nothing about one.
(test-equal "the count did not rise while the control was open: unavailable, never a pass, at 0 and at any other count, and when it fell"
  (list (list 'unavailable (unavailable-text 0 0))
        (list 'unavailable (unavailable-text 700 700))
        (list 'unavailable (unavailable-text 700 650))
        (list 'unavailable (unavailable-text 0 0)))
  (list (memory-check-outcome 0 0 0 0)
        (memory-check-outcome 1200 700 700 700)
        (memory-check-outcome 700 700 650 700)
        (memory-check-outcome 1200 0 0 0)))

;; --- make-memory-check: the control, through stub bindings ------------------------
;; Each stub logs its call. The C string is at 4096, the out-pointer's slot at
;; 8192, and the handle the slot holds is given per row.

;; control-run : Integer (Listof Integer) Integer Natural Integer -> (List Any (Listof Any))
;; The check made with BASELINE run once: its answer, and the calls it made,
;; in order. memory-used answers COUNTS in turn, open-v2 answers OPEN-RC with
;; HANDLE in the slot, close answers CLOSE-RC.
(define (control-run baseline counts open-rc handle close-rc)
  (let* ((log '())
         (note! (lambda (call) (set! log (cons call log))))
         (memory-used (lambda ()
                        (note! '(memory-used))
                        (if (null? counts)
                            (error 'memory-used "no count left")
                            (let ((n (car counts))) (set! counts (cdr counts)) n))))
         (with-c-string (lambda (who s proc) (note! (list 'c-string who s)) (proc 4096)))
         (with-out-pointer (lambda (who proc)
                             (note! (list 'out-pointer who))
                             (let ((answer (proc 8192))) (values answer handle))))
         (open-v2 (lambda (name slot flags vfs) (note! (list 'open name slot flags vfs)) open-rc))
         (close (lambda (h) (note! (list 'close h)) close-rc))
         (check (make-memory-check baseline memory-used with-c-string with-out-pointer
                                   open-v2 close))
         (answer (raised check)))
    (list answer (reverse log))))

;; The calls of a control that opens and closes: the count before, the open of
;; :memory: read-write and create (6), the count while open, the close, the
;; count after.
(define (full-control handle)
  (list '(memory-used)
        '(c-string memory-check ":memory:")
        '(out-pointer memory-check)
        '(open 4096 8192 6 0)
        '(memory-used)
        (list 'close handle)
        '(memory-used)))

(test-equal "the control: the count, an open of :memory: read-write and create, the count while open, the close of that handle, the count after; then the verdict"
  (list (list 'no-raise (list 'pass (pass-text 300))) (full-control 5150))
  (control-run 300 '(310 60310 300) 0 5150 0))

(test-equal "the baseline is the one the check was made with, never a count it reads: a control that comes back to where it began fails a baseline below it"
  (list (list 'no-raise (list 'fail (fail-text 310 300))) (full-control 5150))
  (control-run 300 '(310 60310 310) 0 5150 0))

(test-equal "a control whose count does not rise: unavailable, after the whole control"
  (list (list 'no-raise (list 'unavailable (unavailable-text 0 0))) (full-control 5150))
  (control-run 0 '(0 0 0) 0 5150 0))

(test-equal "a control whose open fails with a handle: the handle is closed, the count is read no further, and the check fails, naming the code"
  (list (list 'no-raise (list 'fail "the control's open of :memory: answered code 7"))
        (list '(memory-used)
              '(c-string memory-check ":memory:")
              '(out-pointer memory-check)
              '(open 4096 8192 6 0)
              '(close 5150)))
  (control-run 300 '(310) 7 5150 0))

(test-equal "a control whose open answers no handle: nothing is closed, and the check fails, naming the code"
  (list (list 'no-raise (list 'fail "the control's open of :memory: answered code 7 and no handle"))
        (list '(memory-used)
              '(c-string memory-check ":memory:")
              '(out-pointer memory-check)
              '(open 4096 8192 6 0)))
  (control-run 300 '(310) 7 0 0))

(test-equal "a control whose close fails: the check fails, naming the code, whatever the counts"
  (list (list 'no-raise (list 'fail "the control's close of :memory: answered code 5"))
        (full-control 5150))
  (control-run 300 '(310 60310 300) 0 5150 5))

(test-equal "the check runs its control afresh at every call"
  (list (list 'no-raise (list 'pass (pass-text 300)))
        (list 'no-raise (list 'fail (fail-text 900 300))))
  (let* ((counts (list 310 60310 300 300 60900 900))
         (check (make-memory-check
                 300
                 (lambda () (let ((n (car counts))) (set! counts (cdr counts)) n))
                 (lambda (who s proc) (proc 4096))
                 (lambda (who proc) (let ((answer (proc 8192))) (values answer 5150)))
                 (lambda (name slot flags vfs) 0)
                 (lambda (h) 0)))
         (first (raised check))
         (second (raised check)))
    (list first second)))

(test-end "memory-check")

(exit (suite-exit-status runner))
