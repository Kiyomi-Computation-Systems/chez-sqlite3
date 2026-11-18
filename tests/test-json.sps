#!r6rs
;;; The suite for SQLite's JSON functions through (chez-sqlite3) (the M4
;;; plan, section 4.5; ADR-0003, amended). JSON is built in by default since
;;; SQLite 3.38.0, so every library at the floor has it, and every row runs on
;;; every lane:
;;;
;;;   the option     (sqlite-compile-option? "OMIT_JSON") is #f, beside
;;;                  THREADSAFE's #t, so a library without JSON fails by name
;;;                  and a predicate that answers #f to everything fails too
;;;   the text       json() minifying, a literal and a bound string; malformed
;;;                  JSON, text or a bound BLOB, at step, code error
;;;   the operators  -> answering JSON text, ->> the SQL value: a string, a
;;;                  flonum, an exact integer
;;;   json_each      its rows, each key, value and type
;;;   JSONB          jsonb()'s BLOB as a bytevector, and a bound bytevector
;;;                  read by json() as JSON
;;;   the numbers    json_extract answering +inf.0 and -inf.0 for 1e400 and
;;;                  -1e400, and a flonum for 9223372036854775808, where
;;;                  9223372036854775807 stays an exact integer
;;;
;;; Every value a row asserts is the research's (.plans/research/m4-plan/,
;;; F3), the same on all four libraries it read: the floor's 3.45.1, Guix's
;;; 3.53.1 and 3.54.1, plain and with FTS5. No row uses json_pretty, which
;;; 3.45.1 lacks. The rows go through the conveniences and the statement
;;; verbs, so they test the values' path through the library, not SQLite: a
;;; row's REAL reads as a flonum, its INTEGER as an exact integer, its TEXT as
;;; a string and its BLOB as a bytevector, and each is asserted whole.
;;;
;;; The library is reached through eval, under a guard, as
;;; tests/test-conveniences.sps reaches it. Every computation that can raise
;;; runs under a guard that answers what was raised; no actual expression
;;; can answer #f for a raise. Effects run in order, through let*, never map
;;; (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) sqlite-error? sqlite-error-code sqlite-error-extended-code
              sqlite-error-sql sqlite-error-offset))

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

;; --- reached through eval -------------------------------------------------------------

(define public-load
  (guard (e (#t (list 'raised (describe e))))
    (eval '(sqlite-version) (environment '(chez-sqlite3)))
    'loaded))

;; reach : Symbol -> Procedure
;; NAME's procedure in (chez-sqlite3); when it cannot be reached, one that
;; raises that, naming NAME, every time it is called.
(define (reach name)
  (guard (e (#t (lambda args (error name "could not be reached" (describe e)))))
    (eval name (environment '(chez-sqlite3)))))

(define call-with-database (reach 'call-with-database))
(define query (reach 'query))
(define query-row (reach 'query-row))
(define call-with-statement (reach 'call-with-statement))
(define bind-all! (reach 'bind-all!))
(define step! (reach 'step!))
(define sqlite-compile-option? (reach 'sqlite-compile-option?))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
;; A &sqlite-error as its who, code, extended code, SQL and offset, never its
;; message; anything else as its text.
(define (what-raised e)
  (if (sqlite-error? e)
      (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
            (sqlite-error-sql e) (sqlite-error-offset e))
      (list 'raised (describe e))))

;; answer : (-> A) -> (U A (List 'sqlite-error ...) (List 'raised String))
(define (answer thunk)
  (guard (e (#t (what-raised e)))
    (thunk)))

;; with-db : (Database -> A) -> A
(define (with-db proc)
  (call-with-database ":memory:" proc))

;; row-of : String Value ... -> (U Row #f (List 'sqlite-error ...) (List 'raised String))
;; query-row's answer for SQL and VALUES, on a fresh :memory: database.
(define (row-of sql . values)
  (answer (lambda () (with-db (lambda (db) (apply query-row db sql values))))))

;; stepped : String Value ... -> Any
;; SQL prepared on a fresh :memory: database, VALUES bound, then stepped
;; once: (prepared row) or (prepared done); (prepared step-raised RAISED)
;; when the step raised; or what the prepare raised.
(define (stepped sql . values)
  (answer
   (lambda ()
     (with-db
      (lambda (db)
        (call-with-statement db sql
          (lambda (st)
            (apply bind-all! st values)
            (guard (e (#t (list 'prepared 'step-raised (what-raised e))))
              (list 'prepared (if (step! st) 'row 'done))))))))))

;; step-error : String -> Any
;; What stepped answers when the step of SQL raises SQLite's error, code 1.
(define (step-error sql)
  (list 'prepared 'step-raised (list 'sqlite-error 'step! 'error 'error sql #f)))

(test-begin "json")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-equal "the library has JSON: OMIT_JSON is not among its options, where THREADSAFE is"
  '(#f #t)
  (answer
   (lambda ()
     (let* ((omit-json (sqlite-compile-option? "OMIT_JSON"))
            (threadsafe (sqlite-compile-option? "THREADSAFE")))
       (list omit-json threadsafe)))))

(test-equal "json() minifies: a literal's white space dropped, its numbers, string, null and true kept"
  '#("{\"a\":[1,2.5,\"x\",null,true]}")
  (row-of "select json(' { \"a\" : [1, 2.5, \"x\", null, true] } ')"))

(test-equal "json() minifies a bound string, and json_valid() answers 1 for it"
  '#("[1,2]" 1)
  (row-of "select json(?1), json_valid(?1)" "[1, 2]"))

(test-equal "malformed JSON prepares, then raises &sqlite-error at its step, code error"
  (step-error "select json('{')")
  (stepped "select json('{')"))

(test-equal "malformed JSON through query-row raises &sqlite-error from query-row, code error, with its SQL and no place"
  '(sqlite-error query-row error error "select json('{')" #f)
  (row-of "select json('{')"))

(test-equal "a bound BLOB that is no JSONB, x'0102', prepares, then raises &sqlite-error at its step, code error"
  (step-error "select json(?1)")
  (stepped "select json(?1)" (u8-list->bytevector '(1 2))))

(test-equal "-> answers JSON text, the string quoted; ->> the SQL value, the string itself, both UTF-8"
  '#("\"é\"" "é")
  (row-of "select '{\"a\":\"é\"}' -> '$.a', '{\"a\":\"é\"}' ->> '$.a'"))

(test-equal "->> answers a REAL as a flonum and an INTEGER as an exact integer"
  '#(2.5 8)
  (row-of "select '{\"a\":2.5}' ->> 'a', '[7,8]' ->> 1"))

(test-equal "json_each answers a row for each key, its value as SQL's and its type, in key order"
  '(#("x" 1 "integer") #("y" "[2]" "array") #("z" "s" "text"))
  (answer
   (lambda ()
     (with-db
      (lambda (db)
        (query db "select key, value, type from json_each('{\"x\":1,\"y\":[2],\"z\":\"s\"}') order by key"))))))

(test-equal "jsonb() answers a BLOB, read as the bytevector #vu8(76 23 97 19 49) for {\"a\":1}, where json() answers TEXT"
  '#(#vu8(76 23 97 19 49) "blob" "text")
  (row-of "select jsonb('{\"a\":1}'), typeof(jsonb('{}')), typeof(json('{}'))"))

(test-equal "a bound bytevector #vu8(12), JSONB's empty object, binds as a BLOB that json() reads as {}"
  '#("{}" 1 "blob")
  (row-of "select json(?1), json_valid(?1, 4), typeof(?1)" (u8-list->bytevector '(12))))

(test-equal "json_extract answers 1e400 and -1e400 as the flonums +inf.0 and -inf.0"
  '#(+inf.0 -inf.0)
  (row-of "select json_extract('[1e400]', '$[0]'), json_extract('[-1e400]', '$[0]')"))

(test-equal "json_extract answers 9223372036854775807 as an exact integer, and 9223372036854775808, past 64 bits, as a flonum"
  (vector 9223372036854775807 (inexact 9223372036854775808))
  (row-of "select json_extract('[9223372036854775807]', '$[0]'), json_extract('[9223372036854775808]', '$[0]')"))

(test-equal "every count is zero after the rows"
  zero-counts
  (native-counts))

(test-end "json")

(exit (suite-exit-status runner))
