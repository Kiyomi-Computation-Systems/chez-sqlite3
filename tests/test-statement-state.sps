#!r6rs
;;; The suite for (chez-sqlite3 private statement-state): the state table of
;;; ADR-0014, as pure functions. It loads no libsqlite3.
;;;
;;;   the lists            the five states and the twelve verbs, in order
;;;   statement-verb-check the whole matrix, every verb against every state,
;;;                        written out here as one value, and `unknown` for
;;;                        a verb or a state outside the lists, a non-symbol
;;;                        and a near-miss among them
;;;   state-after-step     100 is row, 101 is done, anything else is failed
;;;   finish-failure       what reset! or finalize-statement! raises, given
;;;                        the state it ran in and SQLite's answer: nothing
;;;                        for a code that is no error, nothing from failed,
;;;                        else the answer
;;;
;;; Every function is total: each call is made under a guard that answers a
;;; symbol of its own, and an answer of #f is read as none.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) library-exports)
        (chez-sqlite3-testing)
        (chez-sqlite3 private statement-state))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
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

;; sorted-names : (Listof Symbol) -> (Listof Symbol)
(define (sorted-names names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

;; check : Any Any -> Any
;; statement-verb-check's answer, or (raised TEXT).
(define (check verb state)
  (guard (e (#t (list 'raised (describe e)))) (statement-verb-check verb state)))

;; after-step : Any -> Any
(define (after-step answer)
  (guard (e (#t (list 'raised (describe e)))) (state-after-step answer)))

;; finish : Any Any -> Any
;; finish-failure's answer, #f as none.
(define (finish state answer)
  (guard (e (#t (list 'raised (describe e))))
    (let ((r (finish-failure state answer))) (if (eq? r #f) 'none r))))

;; iota : Natural -> (Listof Natural)
(define (iota n)
  (let loop ((i (- n 1)) (acc '()))
    (if (< i 0) acc (loop (- i 1) (cons i acc)))))

(test-begin "statement-state")

(test-equal "(chez-sqlite3 private statement-state) exports exactly the two lists and the three functions"
  (sorted-names '(statement-states statement-verbs statement-verb-check state-after-step
                  finish-failure))
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3 private statement-state)))))

(test-equal "the states are ready, row, done, failed and finalized, in that order"
  '(ready row done failed finalized)
  statement-states)

(test-equal "the verbs are the twelve of ADR-0014, in order"
  '(bind! bind-all! clear-bindings! step! reset! column-value column-bytevector column-count
    column-name statement-sql parameter-count finalize-statement!)
  statement-verbs)

;; The matrix, written out: one row per verb, in statement-verbs' order, one
;; column per state, in statement-states' order: ready row done failed finalized.
(define matrix
  '(;; bind!
    (allowed (refused row) (refused done) (refused failed) closed)
    ;; bind-all!
    (allowed (refused row) (refused done) (refused failed) closed)
    ;; clear-bindings!
    (allowed (refused row) (refused done) (refused failed) closed)
    ;; step!
    (allowed allowed (refused done) (refused failed) closed)
    ;; reset!
    (allowed allowed allowed allowed closed)
    ;; column-value
    ((refused ready) allowed (refused done) (refused failed) closed)
    ;; column-bytevector
    ((refused ready) allowed (refused done) (refused failed) closed)
    ;; column-count
    (allowed allowed allowed allowed closed)
    ;; column-name
    (allowed allowed allowed allowed closed)
    ;; statement-sql
    (allowed allowed allowed allowed closed)
    ;; parameter-count
    (allowed allowed allowed allowed closed)
    ;; finalize-statement!
    (allowed allowed allowed allowed no-op)))

(test-equal "the whole matrix, every verb against every state, as one value"
  matrix
  (map (lambda (verb)
         (map (lambda (state) (check verb state))
              '(ready row done failed finalized)))
       '(bind! bind-all! clear-bindings! step! reset! column-value column-bytevector
         column-count column-name statement-sql parameter-count finalize-statement!)))

(test-equal "the matrix is 12 rows of 5 cells, 60 in all, and the verbs and states walked are the exported lists"
  '(12 5 60 #t)
  (list (length matrix) (length (car matrix)) (apply + (map length matrix))
        (and (equal? statement-verbs '(bind! bind-all! clear-bindings! step! reset! column-value
                                       column-bytevector column-count column-name statement-sql
                                       parameter-count finalize-statement!))
             (equal? statement-states '(ready row done failed finalized)))))

(test-equal "the matrix, walked through the exported lists, is the same value"
  matrix
  (map (lambda (verb) (map (lambda (state) (check verb state)) statement-states))
       statement-verbs))

(test-equal "a verb or a state outside the lists is unknown, whatever the other is, valid or not"
  (map (lambda (x) (quote unknown)) (iota 23))
  (append
   ;; a verb outside the list, against each valid state
   (map (lambda (s) (check 'bogus s)) statement-states)
   ;; a valid verb against a state outside the list
   (map (lambda (v) (check v 'bogus)) '(bind! step! reset! column-value finalize-statement!))
   ;; neither valid
   (list (check 'bogus 'bogus) (check 'ready 'bind!) (check 'row 'step!))
   ;; near-misses
   (list (check 'bind 'ready) (check 'Bind! 'ready) (check 'bind! 'Ready) (check 'bind! 'ready1)
         (check 'finalize! 'ready) (check 'bind! 'finalize) (check 'bind! 'closed))
   (list (check 'step! 'steps) (check 'step 'row) (check 'reset 'done))))

(test-equal "a non-symbol verb or state is unknown: a string, #f, a number, a list, () and a symbol-like string"
  (map (lambda (x) 'unknown) (iota 12))
  (list (check "bind!" 'ready) (check 'bind! "ready") (check #f 'ready) (check 'bind! #f)
        (check 5 'ready) (check 'bind! 5) (check '(bind!) 'ready) (check 'bind! '(ready))
        (check '() 'ready) (check 'bind! '()) (check #\b 'ready) (check 'step! (vector 'row))))

(test-equal "the answer for a refused pair names the state, and only the state"
  '((refused done) (refused failed) (refused row) (refused ready))
  (list (check 'bind! 'done) (check 'step! 'failed) (check 'bind-all! 'row)
        (check 'column-value 'ready)))

;; --- state-after-step ---------------------------------------------------------------------

(test-equal "100 (SQLITE_ROW) gives row and 101 (SQLITE_DONE) gives done"
  '(row done)
  (list (after-step 100) (after-step 101)))

(test-equal "every other integer from -2 to 700 gives failed: ok, error, busy, the extended codes of row and done, and the codes of row and done plus 256"
  '()
  (filter (lambda (c) (not (eq? (after-step c) 'failed)))
          (filter (lambda (c) (not (memv c '(100 101)))) (map (lambda (i) (- i 2)) (iota 703)))))

(test-equal "an extended code whose low byte is 100 or 101 is failed, not row or done: 356 and 357"
  '(failed failed)
  (list (after-step 356) (after-step 357)))

(test-equal "a code whose low byte is 0, 100 or 101 but that is not exactly 100 or 101 is failed too: 0, 256, 356 and 357"
  '(failed failed failed failed)
  (list (after-step 0) (after-step 256) (after-step 356) (after-step 357)))

(test-equal "a non-integer, an inexact 100, a symbol and a string give failed"
  '(failed failed failed failed failed failed)
  (list (after-step 100.0) (after-step 'row) (after-step "100") (after-step #f) (after-step '())
        (after-step 101.0)))

(test-equal "the answer is a symbol of the five states or none"
  'ok
  (if (for-all (lambda (c) (memq (after-step c) statement-states)) '(0 1 5 100 101 256 -1 2067))
      'ok
      'not-a-state))

;; --- finish-failure -----------------------------------------------------------------------

(test-equal "a code whose low byte is 0, 100 or 101 is no error: none, in every state"
  (map (lambda (s) '(none none none none none none none none none)) statement-states)
  (map (lambda (state)
         (map (lambda (code) (finish state code)) '(0 100 101 256 356 357 512 612 613)))
       '(ready row done failed finalized)))

(test-equal "in failed, the answer repeats the step's code, raised already: none for every error code"
  '(none none none none none none)
  (map (lambda (code) (finish 'failed code)) '(1 5 19 517 2067 -1)))

(test-equal "in every other state an error code is the answer, as it is: ready, row, done and finalized"
  (map (lambda (s) '(1 5 19 517 2067 -1 3082)) '(ready row done finalized))
  (map (lambda (state)
         (map (lambda (code) (finish state code)) '(1 5 19 517 2067 -1 3082)))
       '(ready row done finalized)))

(test-equal "the three cases at once, one error code over the five states: only failed gives none"
  '(2067 2067 2067 none 2067)
  (map (lambda (state) (finish state 2067)) '(ready row done failed finalized)))

(test-equal "every code from 0 to 600 in ready: its low byte 0, 100 or 101 gives none, any other the code itself"
  '()
  (filter (lambda (c)
            (not (equal? (finish 'ready c)
                         (if (memv (bitwise-and c 255) '(0 100 101)) 'none c))))
          (iota 601)))

(test-equal "every code from 0 to 600 in failed gives none"
  '()
  (filter (lambda (c) (not (eq? (finish 'failed c) 'none))) (iota 601)))

(test-equal "an answer that is no exact integer is no error code to raise: none, from any state, and it raises nothing"
  '(none none none none none)
  (list (finish 'ready 1.5) (finish 'row 'busy) (finish 'done "5") (finish 'finalized #f)
        (finish 'ready 5.0)))

(test-equal "a state outside the five, and a non-symbol, is no failed: the answer is the error code"
  '(5 5 5)
  (list (finish 'bogus 5) (finish #f 5) (finish "failed" 5)))

(test-end "statement-state")

(exit (suite-exit-status runner))
