#!r6rs
;;; The suite for (chez-sqlite3 private memory): counted foreign blocks
;;; (ADR-0005, ADR-0011). A block is malloc'd memory, counted as a block in
;;; (chez-sqlite3 private counters) while it lives, and kept in a table of
;;; live blocks, so that freeing any other address raises before free runs.
;;;
;;; Memory never loads libsqlite3, so this suite imports it, as it imports the
;;; counters. A refusal names a caller's value by shown-value: a number as
;;; itself, a string as (kind string), never its text (ADR-0013, decision 7).
;;;
;;; The dead-address row runs a child Chez: a free that ran anyway would make
;;; glibc abort, and a child's abort fails that row by name, not the whole
;;; suite with SIGABRT. The child runs outside Valgrind, which follows no
;;; child, and reaches malloc and free only: it never loads libsqlite3. It
;;; prints its counts, and this suite asserts them zero (ADR-0005, decision
;;; 4). How a child runs under the gate is M1 slice 3's choice.
;;;
;;; A test that raises a count on purpose lowers it again under dynamic-wind,
;;; and this suite exits through suite-exit-status, which fails it if any
;;; count is left. Each expected value is one the code under test cannot
;;; produce by failing: SRFI-64 makes #f of a raise in the actual expression,
;;; so none is #f, and each refusal is compared, who and irritants,
;;; against a no-raise sentinel.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) foreign-ref foreign-set! getenv library-exports)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (chez-sqlite3 private memory))

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

;; raised : (-> Any) -> Any
;; What THUNK raised: (assertion-violation WHO IRRITANTS), (other TEXT)
;; for any other raise, or (no-raise VALUE).
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e)
                  (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other (describe e))))
    (list 'no-raise (thunk))))

;; A refusal is compared by its kind, who and irritants, never its message
;; text (ADR-0013, decision 9).

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

;; counts-with : (Listof (Pairof Symbol Integer)) -> (Listof (Pairof Symbol Integer))
;; zero-counts, with each kind in CHANGES at its count.
(define (counts-with changes)
  (map (lambda (entry) (cond ((assq (car entry) changes) => (lambda (c) c)) (else entry)))
       zero-counts))

;; poke! : Natural (Listof Natural) -> Void
(define (poke! address bytes)
  (let loop ((i 0) (bytes bytes))
    (unless (null? bytes)
      (foreign-set! 'unsigned-8 address i (car bytes))
      (loop (+ i 1) (cdr bytes)))))

;; peek : Natural Natural -> (Listof Natural)
(define (peek address n)
  (let loop ((i (- n 1)) (found '()))
    (if (< i 0) found (loop (- i 1) (cons (foreign-ref 'unsigned-8 address i) found)))))

;; iota-from : Natural Natural -> (Listof Natural)
(define (iota-from start n)
  (if (= n 0) '() (cons start (iota-from (+ start 1) (- n 1)))))

;; with-block : Natural (Natural -> Any) -> Any
;; PROC's answer, given a counted block of SIZE bytes, freed after.
(define (with-block size proc)
  (let ((block (foreign-block size)))
    (dynamic-wind
      (lambda () #f)
      (lambda () (proc block))
      (lambda () (free-foreign-block! block)))))

(define (sorted-names names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

(test-begin "blocks")

;; No back door to the table: the library exports exactly these, written out.
(test-equal "(chez-sqlite3 private memory) exports exactly foreign-block and free-foreign-block!"
  (sorted-names '(foreign-block free-foreign-block!))
  (sorted-names (library-exports '(chez-sqlite3 private memory))))

(test-equal "foreign-block: an address, counted as a block while it lives; free-foreign-block! frees it, and the count is zero after"
  (list 'address (counts-with '((block . 1))) zero-counts)
  (let* ((block (foreign-block 16))
         (inside (native-counts)))
    (free-foreign-block! block)
    (list (if (and (integer? block) (exact? block) (> block 0)) 'address block)
          inside (native-counts))))

(test-equal "a block is writable over its whole size"
  (iota-from 1 16)
  (with-block 16 (lambda (block) (poke! block (iota-from 1 16)) (peek block 16))))

(test-equal "foreign-block refuses a size that is no positive exact integer: 0, -1, 1.5, 8.0, and \"8\" named by its kind, counting nothing"
  (list (list 'assertion-violation 'foreign-block '(0))
        (list 'assertion-violation 'foreign-block '(-1))
        (list 'assertion-violation 'foreign-block '(1.5))
        (list 'assertion-violation 'foreign-block '(8.0))
        (list 'assertion-violation 'foreign-block '((kind string)))
        zero-counts)
  (let* ((a (raised (lambda () (foreign-block 0))))
         (b (raised (lambda () (foreign-block -1))))
         (c (raised (lambda () (foreign-block 1.5))))
         (d (raised (lambda () (foreign-block 8.0))))
         (e (raised (lambda () (foreign-block "8")))))
    (list a b c d e (native-counts))))

;; The live table holds every block, not the last one alone: two live at
;; once, each freed, in the order they were made, then a third after.
(test-equal "two blocks live at once are both counted, and each frees, the first made first; a block of 1 byte is one too"
  (list (counts-with '((block . 2))) (counts-with '((block . 1))) zero-counts
        (counts-with '((block . 1))) zero-counts)
  (let* ((first (foreign-block 8))
         (second (foreign-block 8))
         (both (native-counts))
         (one-left (begin (free-foreign-block! first) (native-counts)))
         (none (begin (free-foreign-block! second) (native-counts)))
         (tiny (foreign-block 1))
         (tiny-live (native-counts)))
    (free-foreign-block! tiny)
    (list both one-left none tiny-live (native-counts))))

(test-equal "free-foreign-block! refuses what is no address at all, a symbol as itself and a string by its kind, and counts nothing"
  (list (list 'assertion-violation 'free-foreign-block! '(x))
        (list 'assertion-violation 'free-foreign-block! '((kind string)))
        zero-counts)
  (let* ((a (raised (lambda () (free-foreign-block! 'x))))
         (b (raised (lambda () (free-foreign-block! "4096")))))
    (list a b (native-counts))))

;; A dead address: freed already, or never one of memory's. Freeing either
;; would make glibc abort the process, or worse, so the refusal must come
;; before free runs. A child Chez does it, so that free running anyway
;; fails this test by name, not the whole suite with SIGABRT. The child
;; prints its counts, and they must be zero.
(define dead-address-program
  (string-append
   "(import (rnrs) (chez-sqlite3 private memory) (chez-sqlite3 private counters))\n"
   "(define block (foreign-block 16))\n"
   "(free-foreign-block! block)\n"
   "(define (try thunk)\n"
   "  (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e)\n"
   "                  (irritants-condition? e))\n"
   "             (list (condition-who e)\n"
   "                   (if (equal? (condition-irritants e) (list block)) 'that-block (condition-irritants e)))))\n"
   "    (thunk)\n"
   "    'no-raise))\n"
   "(let* ((again (try (lambda () (free-foreign-block! block))))\n"
   "       (never (try (lambda () (free-foreign-block! 4096)))))\n"
   "  (write (list again never (native-counts)))\n"
   "  (newline))\n"))

(test-equal "free-foreign-block! refuses a dead address, freed already or never allocated, before free runs: in a child Chez, which goes on to print its counts, all zero"
  (list 0
        (string-append
         "((free-foreign-block! that-block) (free-foreign-block! (4096)) "
         "((block . 0) (connection . 0) (statement . 0)))\n")
        "")
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((program (string-append dir "/dead-address.sps")))
         (call-with-port (open-file-output-port program (file-options) (buffer-mode block)
                                                (make-transcoder (utf-8-codec)))
           (lambda (p) (put-string p dead-address-program)))
         (capture-command (list (getenv "CHEZ") "--libdirs" "src:tests:build/scheme-libs"
                                "--program" program)))))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "blocks")

(exit (suite-exit-status runner))
