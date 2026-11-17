#!r6rs
;;; The suite for tests/check-memory-shards.sh, the check behind `make
;;; check-memory-shards`, which make test runs: it holds the memory gate's two
;;; shards, the Makefile's MEMORY_SUITES_1 and MEMORY_SUITES_2, to every suite
;;; once between them (ADR-0005, amended in M3 slice 6). Without this suite,
;;; loosening a rule would leave `make test` green: the real lists break none.
;;;
;;; Every row runs the script on three lists written here, the suites and the
;;; two shards, and asserts its exit status, its whole stdout and its whole
;;; stderr, each problem written out by hand, never read back from the script.
;;; tests/check-test-fails.sh holds that make test runs it on the Makefile's
;;; own lists. The script reads no file, so no row needs a tree; the rows of a
;;; broken awk put one first on PATH, in a directory of this process.
(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
        (only (chezscheme) getenv))

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

(define script "tests/check-memory-shards.sh")

;; --- the lists ------------------------------------------------------------------

;; s : String -> String
;; The suite named X, as make test names it.
(define (s x) (string-append "tests/test-" x ".sps"))

;; words : String ... -> String
;; The arguments, one space between each.
(define (words . ws)
  (if (null? ws)
      ""
      (fold-left (lambda (acc w) (string-append acc " " w)) (car ws) (cdr ws))))

(define a (s "a"))
(define b (s "b"))
(define c (s "c"))
(define d (s "d"))
(define e (s "e"))
(define gone (s "gone"))
(define other (s "other"))
(define abc (words a b c))

;; --- the answers, written by hand -----------------------------------------------

(define (line text) (string-append "check-memory-shards: " text "\n"))

(define (passes n)
  (list 0
        (line (string-append "MEMORY_SUITES_1 and MEMORY_SUITES_2 run each of the "
                             (number->string n) " suites once between them"))
        ""))

;; fails : String ... -> (List Integer String String)
;; Each problem in order, then the count.
(define (fails . problems)
  (list 1 ""
        (string-append (apply string-append (map line problems))
                       (line (string-append "FAILED (problems: "
                                            (number->string (length problems)) ")")))))

(define (neither t)
  (string-append t " is in neither MEMORY_SUITES_1 nor MEMORY_SUITES_2, so no memory job "
                 "runs it under the gate: add it to the shard whose suites take less time "
                 "(Makefile; ADR-0005)"))
(define (both t)
  (string-append t " is in both MEMORY_SUITES_1 and MEMORY_SUITES_2, so both memory jobs "
                 "run it: keep it in one"))
(define (times list t n)
  (string-append t " is in " list " " (number->string n) " times: write it once"))
(define (stray list t)
  (string-append list " names " t ", which is not one of the suites make test runs: "
                 "remove it, or spell it as make test does, tests/test-NAME.sps"))

(define usage
  (list 2 "" (line "usage: sh tests/check-memory-shards.sh SUITES ONE TWO")))

;; --- running it -----------------------------------------------------------------

;; run : String ... -> (U (List Integer String String) (List 'raised String))
(define (run . args)
  (guard (x (#t (list 'raised (describe x))))
    (capture-command (append (list "sh" script) args))))

;; run-with : String String String String -> (U (List Integer String String) ...)
;; As run, with DIR first on PATH.
(define (run-with dir suites one two)
  (guard (x (#t (list 'raised (describe x))))
    (capture-command (list "env" (string-append "PATH=" dir ":" (getenv "PATH"))
                           "sh" script suites one two))))

;; --- the rows -------------------------------------------------------------------

(test-begin "check-memory-shards")

;; passes
(test-equal "a partition passes" (passes 3) (run abc (words a c) b))
(test-equal "the lists' own order is not held" (passes 3) (run abc (words c a) b))
(test-equal "no suites and no lists pass" (passes 0) (run "" "" ""))
(test-equal "white space of any kind and length splits the lists"
            (passes 3)
            (run (string-append a "\t" b "\n " c) (string-append "  " a "   " c " ") (string-append "\t" b "\n")))

;; a suite in neither, at each position
(test-equal "a suite in neither list, first" (fails (neither a)) (run abc b c))
(test-equal "a suite in neither list, in the middle" (fails (neither b)) (run abc a c))
(test-equal "a suite in neither list, last" (fails (neither c)) (run abc a b))
(test-equal "no lists: every suite is in neither"
            (fails (neither a) (neither b) (neither c))
            (run abc "" ""))

;; a suite in both, or twice in one
(test-equal "a suite in both lists" (fails (both c)) (run abc (words a c) (words b c)))
(test-equal "a suite in both lists, first in each" (fails (both a)) (run abc (words a c) (words a b)))
(test-equal "a suite twice in MEMORY_SUITES_1"
            (fails (times "MEMORY_SUITES_1" a 2))
            (run abc (words a c a) b))
(test-equal "a suite three times in MEMORY_SUITES_2"
            (fails (times "MEMORY_SUITES_2" b 3))
            (run abc a (words b c b b)))
(test-equal "a suite in both lists, and twice in one"
            (fails (both a) (times "MEMORY_SUITES_1" a 2))
            (run abc (words a a) (words a b c)))

;; a path in a list that is no suite
(test-equal "MEMORY_SUITES_1 names a suite that is not there"
            (fails (stray "MEMORY_SUITES_1" gone))
            (run abc (words a gone c) b))
(test-equal "MEMORY_SUITES_2 names one first"
            (fails (stray "MEMORY_SUITES_2" gone))
            (run abc (words a c) (words gone b)))
(test-equal "one named twice is told once"
            (fails (stray "MEMORY_SUITES_1" gone))
            (run abc (words a gone c gone) b))
(test-equal "each list names one, each told in its list's order"
            (fails (stray "MEMORY_SUITES_1" gone) (stray "MEMORY_SUITES_2" other))
            (run abc (words a gone) (words b c other)))
(test-equal "a suite spelt ./tests/: the suite is in neither, and the path is no suite"
            (fails (neither a) (stray "MEMORY_SUITES_1" (string-append "./" a)))
            (run abc (words (string-append "./" a) c) b))
(test-equal "a suite without its directory"
            (fails (neither a) (stray "MEMORY_SUITES_2" "test-a.sps"))
            (run abc c (words "test-a.sps" b)))
(test-equal "no suites, and a list names one"
            (fails (stray "MEMORY_SUITES_1" a))
            (run "" a ""))

;; the order of several problems
(test-equal "several problems: the suites' in their order, then each list's strays"
            (fails (neither b) (both c) (times "MEMORY_SUITES_1" c 2) (times "MEMORY_SUITES_2" d 2)
                   (neither e) (stray "MEMORY_SUITES_1" gone) (stray "MEMORY_SUITES_2" other))
            (run (words a b c d e) (words a c gone c) (words c d other d)))

;; the lists reach the check as they are
(let ((odd "tests/test-a\\b.sps"))
  (test-equal "a backslash in a path reaches the check unchanged"
              (fails (neither odd))
              (run odd "" "")))

;; usage
(test-equal "no argument is a usage error" usage (run))
(test-equal "two arguments are a usage error" usage (run abc a))
(test-equal "four arguments are a usage error" usage (run abc a b c))

;; a broken awk, first on PATH: no verdict is a failure
(define base
  (guard (x (#t (display "test-check-memory-shards: no temporary directory: ")
                (display (describe x))
                (newline)
                (exit 1)))
    (make-process-temp-directory)))

;; fake-awk : String String -> (U String (List 'raised String))
;; A directory holding an awk that runs BODY, a shell script's body.
(define (fake-awk name body)
  (guard (x (#t (list 'raised (describe x))))
    (let ((dir (string-append base "/" name)))
      (let ((made (capture-command
                   (list "sh" "-c" "mkdir \"$1\" && printf '#!/bin/sh\\n%s\\n' \"$2\" >\"$1/awk\" && chmod +x \"$1/awk\""
                         "sh" dir body))))
        (unless (equal? made '(0 "" "")) (error 'fake-awk "the stand-in was not made" made))
        dir))))

(let ((dir (fake-awk "fails" "echo boom >&2; exit 2")))
  (test-equal "an awk that fails, printing nothing, fails the check, naming it"
              (fails "the check (awk) exited 2: boom")
              (if (string? dir) (run-with dir abc (words a c) b) dir)))
(let ((dir (fake-awk "silent" "exit 0")))
  (test-equal "an awk that exits 0, printing nothing, fails the check, naming it"
              (fails "the check (awk) printed nothing")
              (if (string? dir) (run-with dir abc (words a c) b) dir)))
(let ((dir (fake-awk "garbled" "echo 'ok 3x'")))
  (test-equal "an awk whose verdict holds no count fails the check, its line told"
              (fails "the check (awk) printed \"ok 3x\", which is neither a problem nor its verdict")
              (if (string? dir) (run-with dir abc (words a c) b) dir)))

(test-end "check-memory-shards")

(exit (suite-exit-status runner))
