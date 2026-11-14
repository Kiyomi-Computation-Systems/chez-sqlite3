#!r6rs
;;; The suite for (chez-sqlite3 private counters): a count per kind of native
;;; object, behind one mutex, with no reset (ADR-0005). A count-down below
;;; zero is a double free, and raises. And the exit checks registered there,
;;; which this process never registers: a child does.
;;;
;;; A test that raises a count on purpose lowers it again under
;;; dynamic-wind, and this suite exits through suite-exit-status, which
;;; fails it if any count is left. Each expected value is one the code under
;;; test cannot produce by failing: SRFI-64 makes #f of a raise in the
;;; actual expression, so none is #f, and each refusal is compared, who and
;;; irritants, against a no-raise sentinel.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) fork-thread make-mutex with-mutex sleep make-time
              library-exports getenv)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters))

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
;; What THUNK raised: (assertion-violation WHO MESSAGE IRRITANTS), (other TEXT)
;; for any other raise, or (no-raise VALUE).
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e)
                  (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-message e)
                   (condition-irritants e)))
            (#t (list 'other (describe e))))
    (list 'no-raise (thunk))))

;; The two messages, whole, written here and not read from the library.
(define not-a-kind "not a kind of native object chez-sqlite3 counts")
(define double-free "more objects of this kind freed than made: a double free")

;; refused : (-> Any) -> (U (List 'assertion-violation Symbol (Listof Any)) (List 'other String) (List 'no-raise Any))
;; THUNK's assertion violation as its who and irritants alone, never its message.
(define (refused thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other (describe e))))
    (list 'no-raise (thunk))))

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

;; counts-with : (Listof (Pairof Symbol Integer)) -> (Listof (Pairof Symbol Integer))
;; zero-counts, with each kind in CHANGES at its count.
(define (counts-with changes)
  (map (lambda (entry) (cond ((assq (car entry) changes) => (lambda (c) c)) (else entry)))
       zero-counts))

;; with-counts : (Listof Symbol) (-> Any) -> Any
;; THUNK's answer, with one more of each kind in KINDS counted while it runs.
(define (with-counts kinds thunk)
  (dynamic-wind
    (lambda () (for-each count-up! kinds))
    thunk
    (lambda () (for-each count-down! kinds))))

;; repeat : Natural Any -> (Listof Any)
(define (repeat n x) (if (= n 0) '() (cons x (repeat (- n 1) x))))

(define (sorted-names names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

(test-begin "counters")

(test-equal "(chez-sqlite3 private counters) exports exactly native-kinds, count-up!, count-down!, native-counts, register-exit-check! and exit-checks: no reset, and no way to drop a check"
  (sorted-names '(native-kinds count-up! count-down! native-counts register-exit-check! exit-checks))
  (sorted-names (library-exports '(chez-sqlite3 private counters))))

(test-equal "native-kinds: block, connection and statement, in that order"
  '(block connection statement)
  native-kinds)

(test-equal "native-counts: every kind, in native-kinds' order, each zero at the start"
  zero-counts
  (native-counts))

(test-equal "count-up! raises its kind's count by one, and count-down! lowers it, each kind apart"
  (list (counts-with '((connection . 1))) (counts-with '((connection . 2) (statement . 1))) zero-counts)
  (let* ((one (with-counts '(connection) native-counts))
         (two (with-counts '(connection connection statement) native-counts)))
    (list one two (native-counts))))

(test-equal "count-up! and count-down! refuse a symbol that is no kind, as an assertion violation, and count nothing"
  (list (list 'assertion-violation 'count-up! not-a-kind '(blocks))
        (list 'assertion-violation 'count-down! not-a-kind '(blocks))
        (list 'assertion-violation 'count-up! not-a-kind '("block"))
        (list 'assertion-violation 'count-down! not-a-kind '(conn))
        zero-counts)
  (let* ((a (raised (lambda () (count-up! 'blocks))))
         (b (raised (lambda () (count-down! 'blocks))))
         (c (raised (lambda () (count-up! "block"))))
         (d (raised (lambda () (count-down! 'conn)))))
    (list a b c d (native-counts))))

(test-equal "a count-down below zero, a double free, raises an assertion violation and leaves the count at zero"
  (list (list 'assertion-violation 'count-down! double-free '(statement)) zero-counts
        (counts-with '((statement . 1))) zero-counts)
  (let* ((refused (raised (lambda () (count-down! 'statement))))
         (after (native-counts))
         (up (with-counts '(statement) native-counts)))
    (list refused after up (native-counts))))

;; An unknown kind with a count standing at one: a count-down! that fell back
;; to some kind's slot would take that count to zero, and still raise at the
;; double free; the count held at one gives it away.
(test-equal "count-down! and count-up! of a symbol that is no kind leave every count where it stood"
  (list (list 'assertion-violation 'count-down! not-a-kind '(blocks))
        (list 'assertion-violation 'count-up! not-a-kind '(blocks))
        (counts-with '((block . 1) (connection . 1) (statement . 1))))
  (with-counts '(block connection statement)
    (lambda ()
      (let* ((down (raised (lambda () (count-down! 'blocks))))
             (up (raised (lambda () (count-up! 'blocks)))))
        (list down up (native-counts))))))

;; Every kind, each alone: a counter that lost one kind's index, or raised
;; below zero for some kinds only, passes a test of one or two. Written out
;; here, not read from native-kinds.
(for-each
 (lambda (kind)
   (test-equal (string-append "count-up! of " (symbol->string kind)
                              " counts that kind alone, and count-down! takes it back")
     (list (counts-with (list (cons kind 1))) zero-counts)
     (let ((during (with-counts (list kind) native-counts)))
       (list during (native-counts))))
   (test-equal (string-append "count-down! of " (symbol->string kind)
                              " at zero raises, a double free, and leaves every count at zero")
     (list (list 'assertion-violation 'count-down! double-free (list kind)) zero-counts)
     (let ((r (raised (lambda () (count-down! kind)))))
       (list r (native-counts)))))
 '(block connection statement))

;; Several threads count one kind up, all of them, and then down, many times
;; each. Without the mutex, two threads read the same count and each writes
;; it plus one, losing one: the ups fall short, the downs reach zero early
;; and raise, or the count ends above zero.
(define thread-count 8)
(define steps 20000)

;; run-threads : (Symbol -> Void) -> (Listof Any)
;; THREAD-COUNT threads each call STEP on connection STEPS times. Each thread's
;; answer is no-raise or what it raised; the wait is bounded, at 120000 steps of
;; 1 ms or more (run-until), and a thread that never answered is never-ran.
(define (run-threads step)
  (let ((mx (make-mutex)) (results (make-vector thread-count 'never-ran)))
    (do ((i 0 (+ i 1))) ((= i thread-count))
      (let ((i i))
        (fork-thread
         (lambda ()
           (let ((r (guard (e (#t (list 'raised (describe e))))
                      (do ((n 0 (+ n 1))) ((= n steps)) (step 'connection))
                      'no-raise)))
             (with-mutex mx (vector-set! results i r)))))))
    ;; At most 120000 steps of 1 ms or more each. Whether it ended in time or
    ;; not, a thread that never answered stays never-ran in the answer.
    (run-until (lambda () (sleep (make-time 'time-duration 1000000 0)))
               (lambda () (with-mutex mx (not (memq 'never-ran (vector->list results)))))
               120000)
    (with-mutex mx (vector->list results))))

(test-equal "the mutex: 8 threads count connection up 20000 times each, then down as often, with no raise, and the count is 160000 between and zero after"
  (list (repeat thread-count 'no-raise) (* thread-count steps)
        (repeat thread-count 'no-raise) zero-counts)
  ;; Nothing here lowers a count the ups raised and the downs did not: if a
  ;; thread raises, the count stays above zero, this row fails, and so does
  ;; the suite, which exits through suite-exit-status.
  (let* ((ups (run-threads count-up!))
         (between (cdr (assq 'connection (native-counts))))
         (downs (run-threads count-down!)))
    (list ups between downs (native-counts))))

;; --- the exit checks ------------------------------------------------------
;; A check is registered for good, and suite-exit-status runs every one at
;; this suite's end, so this process registers none: the refusals register
;; nothing, and a child registers the rest.

(test-equal "a process that loaded no libsqlite3 has no exit check"
  '()
  (exit-checks))

(test-equal "register-exit-check! refuses a name that is no symbol, and a check that is no procedure, as assertion violations naming who and irritants, never the text, and registers nothing"
  (list (list 'assertion-violation 'register-exit-check! '(not-a-name "memory"))
        (list 'assertion-violation 'register-exit-check! '(not-a-procedure memory (pass "x")))
        '())
  (let* ((a (refused (lambda () (register-exit-check! "memory" (lambda () '(pass "x"))))))
         (b (refused (lambda () (register-exit-check! 'memory '(pass "x")))))
         (after (exit-checks)))
    (list a b after)))

(define chez (getenv "CHEZ"))

;; registered-in-child : (List Integer String String)
;; A child that registers checks named zeta, alpha and zeta, and prints what
;; exit-checks answers: each name, and whether its procedure is the one
;; registered under it, then that a second call answers a fresh list. It
;; exits 0 itself, so suite-exit-status never runs them.
(define registered-in-child
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (base)
       (let ((program (string-append base "/child.sps")))
         (call-with-port (open-file-output-port program (file-options no-fail) (buffer-mode block)
                                                (make-transcoder (utf-8-codec)))
           (lambda (p)
             (put-string p
               (string-append
                "#!r6rs\n"
                "(import (rnrs) (chez-sqlite3 private counters))\n"
                "(define first (lambda () '(pass \"one\")))\n"
                "(define second (lambda () '(fail \"two\")))\n"
                "(define third (lambda () '(unavailable \"three\")))\n"
                "(register-exit-check! 'zeta first)\n"
                "(register-exit-check! 'alpha second)\n"
                "(register-exit-check! 'zeta third)\n"
                "(define checks (exit-checks))\n"
                "(write (list (map car checks)\n"
                "             (map (lambda (entry proc) (eq? (cdr entry) proc)) checks (list first second third))\n"
                "             (if (eq? checks (exit-checks)) 'same-list 'fresh-list)))\n"
                "(newline)\n"
                "(exit 0)\n"))))
         (capture-command (list chez "--libdirs" "src:tests:build/scheme-libs" "--program" program)))))))

(test-equal "exit-checks answers every check registered, in the order registered, a name given twice twice, each with its own procedure, in a fresh list"
  '(0 "((zeta alpha zeta) (#t #t #t) fresh-list)\n" "")
  registered-in-child)

(test-end "counters")

(exit (suite-exit-status runner))
