#!r6rs
;;; The suite for (chez-sqlite3 private verify): what a loaded libsqlite3 must
;;; offer (ADR-0002, ADR-0003, ADR-0010), decided here on synthetic inputs.
;;;
;;;   check-version        the floor, 3045001 (3.45.1), else below-floor
;;;   check-threadsafe     sqlite3_threadsafe() not 0, else not-threadsafe
;;;   version-number->string  a version number as M.m.p, for the remedy
;;;
;;; The numbers are written out here, never taken from the library, so a
;;; wrong constant fails here. The floor is also held to
;;; packaging/floors.sexp, the one file that writes it: sqlite-floor must
;;; equal that file's SQLite floor as sqlite3_libversion_number writes it,
;;; and check-version must accept it and refuse the number one below it
;;; (ADR-0008, decision 4). A file and a library that disagree fail here, by
;;; name. The literal rows stay, so a floor changed in both places at once is
;;; a decision a reader of this suite sees.
;;;
;;; Which check runs first is native's order, not verify's (slice 2).
;;;
;;; Each expected value is one the code under test cannot produce by failing.
;;; SRFI-64 turns a raise in the actual expression into #f, so no expected
;;; value here is #f: every call goes through `outcome`, which names what
;;; was raised or returned.
(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
        (chez-sqlite3 private conditions)
        (chez-sqlite3 private libsqlite3-info)
        (chez-sqlite3 private verify)
        (floors))

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

;; The report every call below passes. No field of it equals an argument
;; the checks take, so only the report itself can be carried as itself.
(define report
  (make-libsqlite3-info "/gnu/store/report-path/lib/libsqlite3.so.0" 'guix-home "report-version"
                        1 "report-source-id"))

;; outcome : (-> Any) -> (U (List 'returned Any)
;;                          (List 'refused Symbol Any Any Any Any Any)
;;                          (List 'assertion-violation Any)
;;                          (List 'other-raise String))
;; What THUNK did: returned a value, raised &sqlite-library-unavailable (its
;; reason, path, source, detail, candidates, and the-report when it
;; carries the report, else what it carries), raised an assertion
;; violation (its who), or raised something else.
(define (outcome thunk)
  (guard (e ((sqlite-library-unavailable? e)
             (list 'refused
                   (sqlite-library-unavailable-reason e)
                   (sqlite-library-unavailable-path e)
                   (sqlite-library-unavailable-source e)
                   (sqlite-library-unavailable-detail e)
                   (sqlite-library-unavailable-candidates e)
                   (let ((library (sqlite-library-unavailable-library e)))
                     (if (eq? library report) 'the-report library))))
            ((and (assertion-violation? e) (who-condition? e))
             (list 'assertion-violation (condition-who e)))
            (#t (list 'other-raise (describe e))))
    (list 'returned (thunk))))

;; readable : (-> Any) -> List
;; What THUNK raised, as the default handler would show it: its type, its
;; who, and whether it holds a message; no-raise when it returned.
(define (readable thunk)
  (guard (e ((sqlite-library-unavailable? e)
             (list (chez-sqlite3-error? e) (and (who-condition? e) (condition-who e))
                   (message-condition? e)))
            (#t 'other-raise))
    (thunk)
    'no-raise))

(define path "/usr/lib/aarch64-linux-gnu/libsqlite3.so.0")

;; --- the floor, from packaging/floors.sexp -----------------------------------

;; Each value is computed under a guard, and is a symbol when the file cannot
;; give it: a raise at top level would end the suite with no test named, and
;; one in an expected expression would escape SRFI-64.

;; floor-text-of-file : String or Symbol
;; The SQLite floor of packaging/floors.sexp, as text.
(define floor-text-of-file
  (guard (e (#t 'floors-file-unreadable))
    (floor-text (read-floors) 'sqlite)))

;; floor-num : Natural or Symbol
;; That floor as sqlite3_libversion_number writes it, X*1000000 + Y*1000 +
;; Z: three numbers, the last two under 1000.
(define floor-num
  (guard (e (#t 'floors-file-unreadable))
    (let ((parts (floor-numbers (read-floors) 'sqlite)))
      (if (and (= (length parts) 3) (for-all (lambda (n) (< n 1000)) (cdr parts)))
          (+ (* 1000000 (car parts)) (* 1000 (cadr parts)) (caddr parts))
          'not-a-version-number))))

;; below-num : Natural or Symbol
;; The version number one below the floor.
(define below-num
  (if (and (integer? floor-num) (> floor-num 0)) (- floor-num 1) 'no-version-below))

;; num->text : (U Natural Symbol) -> (U String Symbol)
;; A version number as M.m.p, written here and not by the library.
(define (num->text num)
  (if (integer? num)
      (string-append (number->string (div num 1000000)) "."
                     (number->string (div (mod num 1000000) 1000)) "."
                     (number->string (mod num 1000)))
      num))

(test-begin "verify")

;; --- check-version: the floor ------------------------------------------------

(test-equal "the floor is 3.45.1, 3045001"
  3045001
  sqlite-floor)

(test-equal "the floor is the SQLite floor of packaging/floors.sexp, as a version number"
  floor-num
  sqlite-floor)

(test-equal "check-version: the floor of packaging/floors.sexp is accepted"
  '(returned #t)
  (outcome (lambda () (check-version floor-text-of-file floor-num path 'system report))))

(test-equal "check-version: one below the floor of packaging/floors.sexp is below-floor, with that version"
  `(refused below-floor ,path system ,(num->text below-num) () the-report)
  (outcome (lambda () (check-version (num->text below-num) below-num path 'system report))))

(test-equal "check-version: the floor itself, 3045001, is accepted"
  '(returned #t)
  (outcome (lambda () (check-version "3.45.1" 3045001 path 'system report))))

(test-equal "check-version: 3.45.0, 3045000, is below-floor, with the version, path, source and report"
  `(refused below-floor ,path guix-home "3.45.0" () the-report)
  (outcome (lambda () (check-version "3.45.0" 3045000 path 'guix-home report))))

;; The boundary at the units, the thousands and the millions digit: a
;; comparison of the wrong parts, or of text, gets one of these wrong.
(test-equal "check-version: at and above the floor, every digit: accepted"
  (map (lambda (n) '(returned #t)) '(3045001 3045002 3045999 3046000 3099999 3100000 4000000 10000000))
  (map (lambda (n) (outcome (lambda () (check-version "v" n path 'override report))))
       '(3045001 3045002 3045999 3046000 3099999 3100000 4000000 10000000)))

(test-equal "check-version: below the floor, every digit: below-floor, whatever the other digits"
  (map (lambda (n) `(refused below-floor ,path override "v" () the-report))
       '(0 1 2999999 3037002 3044001 3044999 3045000))
  (map (lambda (n) (outcome (lambda () (check-version "v" n path 'override report))))
       '(0 1 2999999 3037002 3044001 3044999 3045000)))

(test-equal "check-version: a version number that is no natural is an assertion violation, naming no value"
  (map (lambda (v) '(assertion-violation check-version)) '(1 2 3 4 5))
  (map (lambda (v) (outcome (lambda () (check-version "v" v path 'system report))))
       (list "3045001" #f -1 3045001.0 'x)))

;; --- check-threadsafe: sqlite3_threadsafe() ----------------------------------

(test-equal "check-threadsafe: 0, mutexes compiled out, is not-threadsafe, detail 0, with the path, source and report"
  `(refused not-threadsafe ,path override 0 () the-report)
  (outcome (lambda () (check-threadsafe 0 path 'override report))))

(test-equal "check-threadsafe: 1, serialized, and 2, multi-thread, are accepted, and so is any other integer"
  (map (lambda (n) '(returned #t)) '(1 2 -1 3 1000))
  (map (lambda (n) (outcome (lambda () (check-threadsafe n path 'system report))))
       '(1 2 -1 3 1000)))

;; 0 is truthy in Scheme, and 1.0 is an integer: neither a boolean nor an
;; inexact number may stand for an answer.
(test-equal "check-threadsafe: an answer that is no exact integer is an assertion violation: #f, #t, (), \"1\", a symbol, 0.0, 1.0, 1/2"
  (map (lambda (v) '(assertion-violation check-threadsafe)) '(1 2 3 4 5 6 7 8))
  (map (lambda (v) (outcome (lambda () (check-threadsafe v path 'system report))))
       (list #f #t '() "1" 'one 0.0 1.0 1/2)))

;; --- both checks ---------------------------------------------------------------

(test-equal "every refusal is a chez-sqlite3-error from who chez-sqlite3, with a message, for the default handler"
  '((#t chez-sqlite3 #t) (#t chez-sqlite3 #t))
  (list (readable (lambda () (check-version "3.45.0" 3045000 path 'system report)))
        (readable (lambda () (check-threadsafe 0 path 'system report)))))

;; Native runs them in its own order. Called on one report, in either order,
;; each decides alone.
(test-equal "the two checks decide alone: a pass of one never hides the refusal of the other, in either order"
  '(((returned #t) (refused not-threadsafe "/p" system 0 () the-report))
    ((returned #t) (refused below-floor "/p" system "3.1.0" () the-report)))
  (let* ((v1 (outcome (lambda () (check-version "3.45.1" 3045001 "/p" 'system report))))
         (t1 (outcome (lambda () (check-threadsafe 0 "/p" 'system report))))
         (t2 (outcome (lambda () (check-threadsafe 1 "/p" 'system report))))
         (v2 (outcome (lambda () (check-version "3.1.0" 3001000 "/p" 'system report)))))
    (list (list v1 t1) (list (list 'returned (cadr t2)) v2))))

;; --- version-number->string -----------------------------------------------------

(test-equal "version-number->string: M.m.p from X*1000000 + Y*1000 + Z, each part its own digits"
  '("3.45.1" "3.45.0" "3.50.0" "3.0.0" "0.0.0" "3.999.999" "3.0.1" "4.0.0" "10.0.0" "3.7.17"
    "3.44.999")
  (map version-number->string
       '(3045001 3045000 3050000 3000000 0 3999999 3000001 4000000 10000000 3007017 3044999)))

(test-equal "version-number->string: a number that is no natural is an assertion violation"
  (map (lambda (v) '(assertion-violation version-number->string)) '(1 2 3 4))
  (map (lambda (v) (outcome (lambda () (version-number->string v))))
       (list "3045001" #f -1 3045001.5)))

(test-end "verify")

(exit (suite-exit-status runner))
