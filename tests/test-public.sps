#!r6rs
;;; The suite for (chez-sqlite3), the public library, as a whole (ADR-0009,
;;; ADR-0013), and for (chez-sqlite3 private report), its report procedures.
;;;
;;;   the exports    (chez-sqlite3)'s, written out whole, so nothing private,
;;;                  no raw binding of native's among it, can pass through
;;;                  unseen: check-seam's rule (g) holds (chezscheme)'s names
;;;                  alone. connection's and report's too
;;;   re-exports     src/chez-sqlite3.sls, read as data, is one library form
;;;                  with no body; every public name is the very procedure its
;;;                  private library defines, eq?, so referencing a condition
;;;                  predicate runs conditions' body alone and loads nothing
;;;   the report     the version, its number, the source id, the path and its
;;;                  source, whole, against (chez-sqlite3 private native)'s
;;;                  loaded-libsqlite3; each string and list a fresh copy
;;;   compile options
;;;                  sqlite-compile-options against native's raw loop, whole,
;;;                  in order; sqlite-compile-option? against native's raw
;;;                  sqlite3_compileoption_used for every name and its
;;;                  variants; its refusals by who and irritants
;;;
;;; Reached through eval under a guard, as tests/test-native.sps reaches
;;; native, so a refused library fails rows by name. No expected value is #f:
;;; a boolean is compared as the symbol yes or no.
(import (rnrs)
        (rnrs eval)
        (rnrs mutable-pairs)
        (rnrs mutable-strings)
        (srfi :64)
        (only (chezscheme) library-exports)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (chez-sqlite3 private libsqlite3-info))

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

;; public-load : (U 'loaded (List 'raised String))
(define public-load
  (guard (e (#t (list 'raised (describe e))))
    (eval '(sqlite-version) (environment '(chez-sqlite3)))
    'loaded))

;; reach : (Listof Symbol) Symbol -> Any
;; NAME's value in LIBRARY, or a procedure that raises that it could not be
;; reached, every time it is called.
(define (reach library name)
  (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
    (eval name (environment library))))

(define (public name) (reach '(chez-sqlite3) name))

(define sqlite-version (public 'sqlite-version))
(define sqlite-version-number (public 'sqlite-version-number))
(define sqlite-source-id (public 'sqlite-source-id))
(define sqlite-library-path (public 'sqlite-library-path))
(define sqlite-library-source (public 'sqlite-library-source))
(define sqlite-compile-option? (public 'sqlite-compile-option?))
(define sqlite-compile-options (public 'sqlite-compile-options))

(define loaded-libsqlite3 (reach '(chez-sqlite3 private native) 'loaded-libsqlite3))
(define sqlite3-compileoption-get (reach '(chez-sqlite3 private native) 'sqlite3-compileoption-get))
(define sqlite3-compileoption-used (reach '(chez-sqlite3 private native) 'sqlite3-compileoption-used))
(define c-string->string (reach '(chez-sqlite3 private native) 'c-string->string))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (sorted-names names)
  (guard (e (#t (list 'unsortable names)))
    (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names)))

;; attempt : (-> Any) -> Any
;; THUNK's answer; an assertion violation as (assertion-violation WHO
;; IRRITANTS), anything else raised as (raised TEXT).
(define (attempt thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'raised (describe e))))
    (thunk)))

(define (yes-no x) (cond ((eq? x #t) 'yes) ((eq? x #f) 'no) (else (list 'neither x))))

;; --- what each name is, written out ----------------------------------------------------------

;; public-names : (Listof (Pairof Symbol (Listof Symbol)))
;; Each public name with the private library that defines it.
(define public-names
  '((open-database chez-sqlite3 private connection)
    (close-database! chez-sqlite3 private connection)
    (call-with-database chez-sqlite3 private connection)
    (database? chez-sqlite3 private connection)
    (sqlite-version chez-sqlite3 private report)
    (sqlite-version-number chez-sqlite3 private report)
    (sqlite-source-id chez-sqlite3 private report)
    (sqlite-library-path chez-sqlite3 private report)
    (sqlite-library-source chez-sqlite3 private report)
    (sqlite-compile-option? chez-sqlite3 private report)
    (sqlite-compile-options chez-sqlite3 private report)
    (chez-sqlite3-error? chez-sqlite3 private conditions)
    (sqlite-error? chez-sqlite3 private conditions)
    (sqlite-error-code chez-sqlite3 private conditions)
    (sqlite-error-extended-code chez-sqlite3 private conditions)
    (sqlite-error-message chez-sqlite3 private conditions)
    (sqlite-error-sql chez-sqlite3 private conditions)
    (sqlite-error-offset chez-sqlite3 private conditions)
    (sqlite-library-unavailable? chez-sqlite3 private conditions)
    (sqlite-library-unavailable-reason chez-sqlite3 private conditions)
    (sqlite-library-unavailable-path chez-sqlite3 private conditions)
    (sqlite-library-unavailable-source chez-sqlite3 private conditions)
    (sqlite-library-unavailable-detail chez-sqlite3 private conditions)
    (sqlite-library-unavailable-candidates chez-sqlite3 private conditions)
    (sqlite-wrong-thread? chez-sqlite3 private conditions)
    (sqlite-wrong-thread-owner chez-sqlite3 private conditions)
    (sqlite-wrong-thread-caller chez-sqlite3 private conditions)
    (sqlite-closed? chez-sqlite3 private conditions)))

(test-begin "public")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "(chez-sqlite3) names 28 exports"
  28
  (length public-names))

(test-equal "(chez-sqlite3) exports exactly the connections, the report, the compile options, the root's predicate and each condition's predicate and accessors, sqlite-library-unavailable-library aside: no type name, no constructor, nothing raw"
  (sorted-names (map car public-names))
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3)))))

(test-equal "(chez-sqlite3 private connection) exports exactly the four public procedures, call-with-open-handle and failure-details"
  (sorted-names '(open-database close-database! call-with-database database? call-with-open-handle
                  failure-details))
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3 private connection)))))

(test-equal "(chez-sqlite3 private report) exports exactly the seven report procedures"
  (sorted-names '(sqlite-version sqlite-version-number sqlite-source-id sqlite-library-path
                  sqlite-library-source sqlite-compile-option? sqlite-compile-options))
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3 private report)))))

;; --- re-exports ------------------------------------------------------------------------------

(define public-source "src/chez-sqlite3.sls")

;; public-data : (U (Listof Any) (List 'unreadable String))
(define public-data
  (guard (e (#t (list 'unreadable (describe e))))
    (call-with-port
     (open-file-input-port public-source (file-options) (buffer-mode block)
                           (make-transcoder (utf-8-codec)))
     (lambda (port)
       (let loop ((found '()))
         (let ((datum (read port)))
           (if (eof-object? datum) (reverse found) (loop (cons datum found)))))))))

(test-equal "src/chez-sqlite3.sls is one library form, (chez-sqlite3), with an export clause, an import clause, and no body: every name is a re-export"
  '(one-form (chez-sqlite3) export import no-body)
  (if (and (list? public-data) (= (length public-data) 1) (list? (car public-data))
           (>= (length (car public-data)) 4) (eq? (car (car public-data)) 'library))
      (let ((form (car public-data)))
        (list 'one-form (cadr form) (car (caddr form)) (car (cadddr form))
              (if (null? (cddddr form)) 'no-body (list 'body (cddddr form)))))
      public-data))

(test-equal "each public name is the procedure its private library defines, eq?: nothing is wrapped"
  (map (lambda (entry) (list (car entry) 'same)) public-names)
  (map (lambda (entry)
         (list (car entry)
               (guard (e (#t (list 'raised (describe e))))
                 (if (eq? (eval (car entry) (environment '(chez-sqlite3)))
                          (eval (car entry) (environment (cdr entry))))
                     'same
                     'different))))
       public-names))

;; --- the report ---------------------------------------------------------------------------------

(define info
  (guard (e (#t (list 'raised (describe e))))
    (loaded-libsqlite3)))

(test-equal "the report, whole: the version, its number, the source id, the path and its source are native's"
  (guard (e (#t (list 'no-report (describe e))))
    (list (libsqlite3-info-version info) (libsqlite3-info-version-number info)
          (libsqlite3-info-source-id info) (libsqlite3-info-path info)
          (libsqlite3-info-source info)))
  (attempt (lambda ()
             (let* ((version (sqlite-version))
                    (number (sqlite-version-number))
                    (source-id (sqlite-source-id))
                    (path (sqlite-library-path))
                    (source (sqlite-library-source)))
               (list version number source-id path source)))))

(test-equal "the report's version is a string, its number an exact natural, its source a symbol"
  '(string natural symbol)
  (attempt (lambda ()
             (let* ((v (sqlite-version)) (n (sqlite-version-number)) (s (sqlite-library-source)))
               (list (if (string? v) 'string v)
                     (if (and (integer? n) (exact? n) (>= n 0)) 'natural n)
                     (if (symbol? s) 'symbol s))))))

;; scribbled : (-> String) -> Any
;; THUNK's answer after its last answer had every character overwritten:
;; the same as before when each answer is a fresh copy.
(define (scribbled thunk)
  (attempt (lambda ()
             (let* ((first (thunk))
                    (kept (string-copy first)))
               (string-fill! first #\X)
               (let ((second (thunk)))
                 (if (equal? second kept) 'unchanged (list 'changed kept second)))))))

(test-equal "each string the report answers is a fresh copy: one overwritten leaves the next answer as it was"
  '(unchanged unchanged unchanged)
  (list (scribbled sqlite-version) (scribbled sqlite-source-id) (scribbled sqlite-library-path)))

;; --- compile options ------------------------------------------------------------------------------

;; raw-options : (U (Listof String) (List 'raised String))
;; native's sqlite3_compileoption_get from 0 to its first NULL, in order,
;; capped so a binding that never answers NULL ends.
(define raw-options
  (guard (e (#t (list 'raised (describe e))))
    (let loop ((i 0) (found '()))
      (if (= i 1000)
          (cons 'too-many (reverse found))
          (let ((address (sqlite3-compileoption-get i)))
            (if (eqv? address 0)
                (reverse found)
                (loop (+ i 1) (cons (c-string->string address) found))))))))

(test-equal "native lists compile options, as strings"
  'strings
  (if (and (pair? raw-options) (for-all string? raw-options)) 'strings raw-options))

(test-equal "sqlite-compile-options is native's list, whole, in order"
  raw-options
  (attempt sqlite-compile-options))

(test-equal "sqlite-compile-options answers a fresh list of fresh strings: the last one changed leaves the next as it was"
  'unchanged
  (attempt (lambda ()
             (let* ((first (sqlite-compile-options)))
               (when (pair? first)
                 (string-fill! (car first) #\X)
                 (set-car! first "CHANGED"))
               (if (equal? (sqlite-compile-options) raw-options) 'unchanged 'changed)))))

;; option-name : String -> String
;; An option as sqlite3_compileoption_get gives it, up to its first =.
(define (option-name option)
  (let loop ((i 0))
    (cond ((= i (string-length option)) option)
          ((char=? (string-ref option i) #\=) (substring option 0 i))
          (else (loop (+ i 1))))))

;; names-to-ask : (Listof String)
;; Each listed option's name; for the first, its lower-cased and SQLITE_
;; spellings; and a name no build has.
(define names-to-ask
  (if (and (pair? raw-options) (for-all string? raw-options))
      (let ((first (option-name (car raw-options))))
        (append (map option-name raw-options)
                (list (string-downcase first) (string-append "SQLITE_" first)
                      "CHEZ_SQLITE3_NO_SUCH_OPTION")))
      '("CHEZ_SQLITE3_NO_SUCH_OPTION")))

(test-equal "sqlite-compile-option? answers as native's sqlite3_compileoption_used does, for every listed name, its variants and a name no build has"
  (guard (e (#t (list 'no-expectation (describe e))))
    (let loop ((names names-to-ask) (found '()))
      (if (null? names)
          (reverse found)
          (let ((answer (call-with-c-string 'test-public (car names) sqlite3-compileoption-used)))
            (loop (cdr names) (cons (cons (car names) (if (eqv? answer 1) 'yes 'no)) found))))))
  (guard (e (#t (list 'raised (describe e))))
    (let loop ((names names-to-ask) (found '()))
      (if (null? names)
          (reverse found)
          (let ((answer (yes-no (sqlite-compile-option? (car names)))))
            (loop (cdr names) (cons (cons (car names) answer) found)))))))

(test-equal "sqlite-compile-option? says yes for every listed name, and no for a name no build has"
  '(yes no)
  (attempt (lambda ()
             (list (if (for-all (lambda (o) (eq? (sqlite-compile-option? (option-name o)) #t)) raw-options)
                       'yes 'no)
                   (yes-no (sqlite-compile-option? "CHEZ_SQLITE3_NO_SUCH_OPTION"))))))

(test-equal "sqlite-compile-option? refuses what is no string by its rule, and U+0000 naming its kind, from sqlite-compile-option?; nothing is left allocated"
  (list '(assertion-violation sqlite-compile-option? (not-a-string 42))
        '(assertion-violation sqlite-compile-option? (not-a-string threadsafe))
        '(assertion-violation sqlite-compile-option? ((kind string)))
        zero-counts)
  (let* ((a (attempt (lambda () (sqlite-compile-option? 42))))
         (b (attempt (lambda () (sqlite-compile-option? 'threadsafe))))
         (c (attempt (lambda () (sqlite-compile-option? "THREAD\x0;SAFE")))))
    (list a b c (native-counts))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "public")

(exit (suite-exit-status runner))
