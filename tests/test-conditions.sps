#!r6rs
;;; The suite for (chez-sqlite3 private conditions): the root every library
;;; condition sits under, and the four M1 raises (ADR-0013, ADR-0002).
;;;
;;;   &chez-sqlite3-error           the fieldless root, under &error
;;;   &sqlite-library-unavailable   libsqlite3 was refused: six reasons, what
;;;                                 the refusal is about, and the library's own
;;;                                 report once its version was read
;;;   &sqlite-error                 SQLite answered a code: its names, from the
;;;                                 integer, its message, sql and offset
;;;   &sqlite-wrong-thread          a verb off its connection's thread: the
;;;                                 owner's and the caller's ids
;;;   &sqlite-closed                a verb on a closed connection
;;;   &sqlite-busy, &sqlite-constraint, &sqlite-read-only
;;;                                 the three subtypes of &sqlite-error, no
;;;                                 fields of their own, made by
;;;                                 make-sqlite-error from the primary code's
;;;                                 name (sqlite-error-subtype)
;;;   &sqlite-invalid-text          a TEXT value or column name that is not
;;;                                 well-formed UTF-8, under the root: the
;;;                                 column's index and the byte offset of the
;;;                                 first ill-formed subpart
;;;   &sqlite-interrupt             M3: a fourth subtype of &sqlite-error, no
;;;                                 field of its own, made by make-sqlite-error
;;;                                 from the primary code interrupt
;;;   &sqlite-setting-mismatch      M3: a setting read back differs, under the
;;;                                 root: the setting's name, the value asked
;;;                                 for and the value read
;;;   &sqlite-transaction-ended     M3: a body returned after its transaction
;;;                                 ended, under the root, no field
;;;   &sqlite-extensions-unavailable
;;;                                 M4: an open that opts in to extension
;;;                                 loading on a library without
;;;                                 sqlite3_load_extension, under the root, no
;;;                                 field, neither an &sqlite-error nor an
;;;                                 &sqlite-library-unavailable
;;;
;;; Then kind-of, shown-value and checked-accessor, which name a caller's
;;; value by its kind where a refusal would print it, and the agreement of
;;; (chez-sqlite3 private libsqlite3-info)'s private copy of shown-value's
;;; rule with shown-value's own.
;;;
;;; The kinds are held as a whole matrix, so no type can sit under another.
;;; A refusal is asserted by its who and its irritants, never its message;
;;; each new refusal names the field or the rule first among its irritants.
;;;
;;; Each expected value is one the code under test cannot produce by failing.
;;; SRFI-64 turns a raise in the actual expression into #f, so no expected
;;; value here is #f, and every refusal is compared against a no-raise
;;; sentinel. Each fixture field holds a value no other field holds, so an
;;; accessor that read the wrong field cannot pass.
(import (rnrs)
        (rnrs mutable-pairs)
        (rnrs records inspection)
        (only (chezscheme) library-exports)
        (srfi :64)
        (chez-sqlite3-testing)
        (chez-sqlite3 private libsqlite3-info)
        (chez-sqlite3 private constants)
        (chez-sqlite3 private conditions))

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
;; What THUNK raised: (assertion-violation WHO IRRITANTS), (other TEXT) for
;; any other raise, or (no-raise VALUE). The message is a condition's type,
;; not its text: its wording is no contract (ADR-0013, decision 9).
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e)
                  (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other (describe e))))
    (list 'no-raise (thunk))))

;; contains? : String String -> Boolean
(define (contains? text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i k) n) (or (string=? (substring text i (+ i k)) part) (loop (+ i 1)))))))

;; kinds : Any -> (List Boolean Boolean Boolean)
;; Which of error?, chez-sqlite3-error? and sqlite-library-unavailable? hold.
(define (kinds c)
  (list (error? c) (chez-sqlite3-error? c) (sqlite-library-unavailable? c)))

;; A report whose every field differs from the refusal's fields below. Built
;; under a guard: a raise at top level would end the suite with no test named,
;; so a constructor that raises leaves a symbol, and the row after this
;; definition names it.
(define a-report
  (guard (e (#t 'report-constructor-raised))
    (make-libsqlite3-info "/opt/sqlite/lib/libsqlite3.so.0.8.6" 'guix-profile "3.37.2" 3037002
                          "2022-01-06 13:25:41 report-source-id")))

;; A refusal whose every field differs from every other field.
(define (a-library-unavailable)
  (make-sqlite-library-unavailable 'below-floor
                                   "/opt/sqlite/lib/libsqlite3.so.0"
                                   'override
                                   "libm.so.6: cannot open shared object file"
                                   '("/opt/sqlite/lib/libsqlite3.so.0" "/usr/lib/libsqlite3.so.0")
                                   a-report))

(define reasons '(invalid-override not-found load-failed below-floor not-threadsafe missing-api))

(define secret "Pr0xyS3cr3t")

(define (sorted-names names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

(test-begin "conditions")

(test-equal "(chez-sqlite3 private conditions) exports exactly these names, written out"
  (sorted-names
   '(&chez-sqlite3-error make-chez-sqlite3-error chez-sqlite3-error?
     &sqlite-library-unavailable make-sqlite-library-unavailable sqlite-library-unavailable?
     sqlite-library-unavailable-reason sqlite-library-unavailable-path
     sqlite-library-unavailable-source sqlite-library-unavailable-detail
     sqlite-library-unavailable-candidates sqlite-library-unavailable-library
     sqlite-library-unavailable-reasons raise-library-unavailable
     &sqlite-error make-sqlite-error sqlite-error? sqlite-error-code sqlite-error-extended-code
     sqlite-error-message sqlite-error-sql sqlite-error-offset raise-sqlite-error
     &sqlite-wrong-thread make-sqlite-wrong-thread sqlite-wrong-thread?
     sqlite-wrong-thread-owner sqlite-wrong-thread-caller raise-wrong-thread
     &sqlite-closed make-sqlite-closed sqlite-closed? raise-closed
     kind-of shown-value checked-accessor
     &sqlite-busy sqlite-busy? &sqlite-constraint sqlite-constraint? &sqlite-read-only
     sqlite-read-only? sqlite-error-subtype &sqlite-invalid-text make-sqlite-invalid-text
     sqlite-invalid-text? sqlite-invalid-text-column sqlite-invalid-text-offset
     raise-invalid-text
     &sqlite-interrupt sqlite-interrupt?
     &sqlite-setting-mismatch make-sqlite-setting-mismatch sqlite-setting-mismatch?
     sqlite-setting-mismatch-setting sqlite-setting-mismatch-expected
     sqlite-setting-mismatch-actual raise-setting-mismatch
     &sqlite-transaction-ended make-sqlite-transaction-ended sqlite-transaction-ended?
     raise-transaction-ended
     &sqlite-extensions-unavailable make-sqlite-extensions-unavailable
     sqlite-extensions-unavailable? raise-extensions-unavailable))
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3 private conditions)))))

(test-equal "the report fixture is a libsqlite3-info"
  #t
  (libsqlite3-info? a-report))

;; --- &chez-sqlite3-error ---------------------------------------------------

(test-equal "make-chez-sqlite3-error: an error and a chez-sqlite3-error, and not a library-unavailable"
  '(#t #t #f)
  (kinds (make-chez-sqlite3-error)))

(test-equal "chez-sqlite3-error? is false for a plain error, a message, a symbol and #f"
  '(#f #f #f #f)
  (map chez-sqlite3-error? (list (make-error) (make-message-condition "m") 'x #f)))

;; --- &sqlite-library-unavailable --------------------------------------------

(test-equal "library-unavailable: an error, a chez-sqlite3-error and a library-unavailable"
  '(#t #t #t)
  (kinds (a-library-unavailable)))

(test-equal "library-unavailable carries its reason, path, source, detail, candidates and library"
  '(below-floor
    "/opt/sqlite/lib/libsqlite3.so.0"
    override
    "libm.so.6: cannot open shared object file"
    ("/opt/sqlite/lib/libsqlite3.so.0" "/usr/lib/libsqlite3.so.0")
    the-report)
  (let ((c (a-library-unavailable)))
    (list (sqlite-library-unavailable-reason c)
          (sqlite-library-unavailable-path c)
          (sqlite-library-unavailable-source c)
          (sqlite-library-unavailable-detail c)
          (sqlite-library-unavailable-candidates c)
          (let ((library (sqlite-library-unavailable-library c)))
            (if (eq? library a-report) 'the-report library)))))

(test-equal "library-unavailable's library may be #f: no report was read"
  'no-report
  (let ((library (sqlite-library-unavailable-library
                  (make-sqlite-library-unavailable 'not-found #f #f #f '() #f))))
    (if (eq? library #f) 'no-report library)))

(test-equal "the reasons are exactly ADR-0002's six, amended, in order"
  '(invalid-override not-found load-failed below-floor not-threadsafe missing-api)
  sqlite-library-unavailable-reasons)

;; Written out here, not taken from the export: a reason dropped from the
;; exported list must fail this test, not shrink it.
(test-equal "the constructor takes each of the six reasons"
  '(invalid-override not-found load-failed below-floor not-threadsafe missing-api)
  (map (lambda (reason)
         (sqlite-library-unavailable-reason
          (make-sqlite-library-unavailable reason #f #f #f '() #f)))
       '(invalid-override not-found load-failed below-floor not-threadsafe missing-api)))

;; One refusal of each reason, with the fields that reason carries (ADR-0002,
;; ADR-0013): each field read back, none a default.
(test-equal "each reason, built with the fields it carries, answers every field"
  '((invalid-override #f override "lib/x.so" () no-report)
    (not-found #f #f #f ("/a/libsqlite3.so.0" "/b/libsqlite3.so.0") no-report)
    (load-failed "/c/libsqlite3.so.0" guix-home "cannot open shared object file" () no-report)
    (below-floor "/d/libsqlite3.so.0" system "3.37.2" () the-report)
    (not-threadsafe "/e/libsqlite3.so.0" system 0 () the-report)
    (missing-api "/f/libsqlite3.so.0" guix-system "sqlite3_open_v2" () the-report))
  (map (lambda (c)
         (list (sqlite-library-unavailable-reason c)
               (sqlite-library-unavailable-path c)
               (sqlite-library-unavailable-source c)
               (sqlite-library-unavailable-detail c)
               (sqlite-library-unavailable-candidates c)
               (let ((library (sqlite-library-unavailable-library c)))
                 (cond ((eq? library a-report) 'the-report)
                       ((eq? library #f) 'no-report)
                       (else library)))))
       (list
        (make-sqlite-library-unavailable 'invalid-override #f 'override "lib/x.so" '() #f)
        (make-sqlite-library-unavailable 'not-found #f #f #f
                                         '("/a/libsqlite3.so.0" "/b/libsqlite3.so.0") #f)
        (make-sqlite-library-unavailable 'load-failed "/c/libsqlite3.so.0" 'guix-home
                                         "cannot open shared object file" '() #f)
        (make-sqlite-library-unavailable 'below-floor "/d/libsqlite3.so.0" 'system "3.37.2" '()
                                         a-report)
        (make-sqlite-library-unavailable 'not-threadsafe "/e/libsqlite3.so.0" 'system 0 '()
                                         a-report)
        (make-sqlite-library-unavailable 'missing-api "/f/libsqlite3.so.0" 'guix-system
                                         "sqlite3_open_v2" '() a-report))))

(test-equal "the constructor refuses a symbol that is not a reason"
  '(assertion-violation make-sqlite-library-unavailable (library-missing))
  (raised (lambda ()
            (make-sqlite-library-unavailable 'library-missing #f #f #f '() #f))))

(test-equal "the constructor refuses chez-curl's no-ssl, #f, a number, () and a reason spelled as a string"
  '((assertion-violation make-sqlite-library-unavailable (no-ssl))
    (assertion-violation make-sqlite-library-unavailable (#f))
    (assertion-violation make-sqlite-library-unavailable (5))
    (assertion-violation make-sqlite-library-unavailable (()))
    (assertion-violation make-sqlite-library-unavailable ((kind string))))
  (map (lambda (r)
         (raised (lambda () (make-sqlite-library-unavailable r #f #f #f '() #f))))
       (list 'no-ssl #f 5 '() "not-found")))

;; The allowlist against its whole complement, for each of the six: the
;; symbol upper-cased, with a suffix, and missing its last character; the
;; string; and a char, a vector and a condition besides. A reason matched
;; case-insensitively, by prefix, or as text takes one of these.
(define near-reasons
  '(INVALID-OVERRIDE NOT-FOUND LOAD-FAILED BELOW-FLOOR NOT-THREADSAFE MISSING-API
    invalid-override-x not-found-x load-failed-x below-floor-x not-threadsafe-x missing-api-x
    invalid-overrid not-foun load-faile below-floo not-threadsaf missing-ap))

(test-equal "the constructor refuses each reason upper-cased, with a suffix, or missing its last character"
  (map (lambda (r) (list 'assertion-violation 'make-sqlite-library-unavailable (list r)))
       near-reasons)
  (map (lambda (r)
         (raised (lambda () (make-sqlite-library-unavailable r #f #f #f '() #f))))
       near-reasons))

(test-equal "the constructor refuses each of the six reasons spelled as a string, naming it by its kind"
  (map (lambda (r)
         '(assertion-violation make-sqlite-library-unavailable ((kind string))))
       '(1 2 3 4 5 6))
  (map (lambda (r)
         (raised (lambda () (make-sqlite-library-unavailable r #f #f #f '() #f))))
       '("invalid-override" "not-found" "load-failed" "below-floor" "not-threadsafe"
         "missing-api")))

(test-equal "the constructor refuses a char, a vector and a condition as a reason"
  '((assertion-violation make-sqlite-library-unavailable (#\n))
    (assertion-violation make-sqlite-library-unavailable ((kind vector)))
    (assertion-violation make-sqlite-library-unavailable ((kind other))))
  (map (lambda (r)
         (raised (lambda () (make-sqlite-library-unavailable r #f #f #f '() #f))))
       (list #\n (vector 'not-found) (make-error))))

(test-equal "the constructor refuses a library that is neither a libsqlite3-info nor #f, a string among them, naming it by its kind"
  '((assertion-violation make-sqlite-library-unavailable ((kind string))))
  (list (raised (lambda ()
                  (make-sqlite-library-unavailable 'below-floor "/usr/lib/libsqlite3.so.0"
                                                   'system "3.37.2" '() "3.45.1")))))

(test-equal "the constructor refuses #t, a symbol, a list and a condition as a library"
  '((assertion-violation make-sqlite-library-unavailable (#t))
    (assertion-violation make-sqlite-library-unavailable (libsqlite3-info))
    (assertion-violation make-sqlite-library-unavailable ((a b)))
    (assertion-violation make-sqlite-library-unavailable ((kind other))))
  (map (lambda (library)
         (raised (lambda () (make-sqlite-library-unavailable 'not-found #f #f #f '() library))))
       (list #t 'libsqlite3-info '(a b) (make-error))))

;; --- raise-library-unavailable -----------------------------------------------------

;; refused : (-> Any) -> Any
;; What THUNK raised, as the whole condition: its type, who, message
;; (whether there is one, never its text), irritants and six fields; or
;; (other-raise ...) or (no-raise) when it raised something else or nothing.
(define (refused thunk)
  (guard (e ((sqlite-library-unavailable? e)
             (list 'refused
                   (kinds e)
                   (serious-condition? e)
                   (and (who-condition? e) (condition-who e))
                   (message-condition? e)
                   (and (irritants-condition? e) (condition-irritants e))
                   (sqlite-library-unavailable-reason e)
                   (sqlite-library-unavailable-path e)
                   (sqlite-library-unavailable-source e)
                   (sqlite-library-unavailable-detail e)
                   (sqlite-library-unavailable-candidates e)
                   (let ((library (sqlite-library-unavailable-library e)))
                     (if (eq? library a-report) 'the-report library))))
            ((and (assertion-violation? e) (who-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other-raise (describe e))))
    (thunk)
    'no-raise))

(test-equal "raise-library-unavailable raises the whole condition: the types, who chez-sqlite3, a message, the irritants as given and the six fields, with the report"
  '(refused (#t #t #t) #t chez-sqlite3 #t ("/p" lib 3)
    below-floor "/opt/p/libsqlite3.so.0" guix-system "3.1.0" ("/c1" "/c2") the-report)
  (refused (lambda ()
             (raise-library-unavailable 'below-floor "/opt/p/libsqlite3.so.0" 'guix-system "3.1.0"
                                        '("/c1" "/c2") a-report "any message" '("/p" lib 3)))))

(test-equal "raise-library-unavailable with no path, source or report, and no irritants"
  '(refused (#t #t #t) #t chez-sqlite3 #t ()
    not-found #f #f #f ("/a") #f)
  (refused (lambda ()
             (raise-library-unavailable 'not-found #f #f #f '("/a") #f "another message" '()))))

;; A handler that returns must not make the raise return: the load would go on
;; as if the library were accepted.
(test-equal "raise-library-unavailable never returns: a handler that returns gets nothing back, and the raise goes on to the next handler"
  'raised-on
  (guard (e (#t 'raised-on))
    (with-exception-handler
     (lambda (c) 'handled)
     (lambda () (raise-library-unavailable 'not-found #f #f #f '() #f "m" '())))
    'returned-normally))

(test-equal "raise-library-unavailable takes each of the six reasons"
  '(invalid-override not-found load-failed below-floor not-threadsafe missing-api)
  (map (lambda (r)
         (let ((c (refused (lambda ()
                             (raise-library-unavailable r #f #f #f '() #f "m" '())))))
           (if (and (pair? c) (eq? (car c) 'refused)) (list-ref c 6) c)))
       '(invalid-override not-found load-failed below-floor not-threadsafe missing-api)))

(test-equal "raise-library-unavailable refuses a reason or a library the constructor refuses, with an assertion violation from the constructor"
  '((assertion-violation make-sqlite-library-unavailable (no-ssl))
    (assertion-violation make-sqlite-library-unavailable ((kind string))))
  (list (refused (lambda ()
                   (raise-library-unavailable 'no-ssl #f #f #f '() #f "m" '())))
        (refused (lambda ()
                   (raise-library-unavailable 'not-found #f #f #f '() "3.45.1" "m" '())))))

;; The six accessors, each refusing what is not a refusal by its kind.
(define lib-accessors
  (list (cons 'sqlite-library-unavailable-reason sqlite-library-unavailable-reason)
        (cons 'sqlite-library-unavailable-path sqlite-library-unavailable-path)
        (cons 'sqlite-library-unavailable-source sqlite-library-unavailable-source)
        (cons 'sqlite-library-unavailable-detail sqlite-library-unavailable-detail)
        (cons 'sqlite-library-unavailable-candidates sqlite-library-unavailable-candidates)
        (cons 'sqlite-library-unavailable-library sqlite-library-unavailable-library)))

;; refusal : Symbol Any -> List
(define (refusal who shown)
  (list 'assertion-violation who (list shown)))

(test-equal "every accessor refuses a string by its kind, naming the accessor, not the string"
  (map (lambda (a) (refusal (car a) '(kind string))) lib-accessors)
  (map (lambda (a) (raised (lambda () ((cdr a) secret)))) lib-accessors))

(test-equal "every accessor refuses a plain error, the root alone, a message, #f, a number, a list holding a string and a vector holding one"
  (map (lambda (a)
         (list (refusal (car a) '(kind other))
               (refusal (car a) '(kind other))
               (refusal (car a) '(kind other))
               (refusal (car a) #f)
               (refusal (car a) 5)
               (refusal (car a) '(kind list))
               (refusal (car a) '(kind vector))))
       lib-accessors)
  (map (lambda (a)
         (map (lambda (v) (raised (lambda () ((cdr a) v))))
              (list (make-error) (make-chez-sqlite3-error) (make-message-condition secret) #f 5
                    (list "u" secret) (vector secret))))
       lib-accessors))

(test-equal "no accessor prints the secret it refused, bare, in a list or in a vector"
  (map (lambda (a) '(absent absent absent)) lib-accessors)
  (map (lambda (a)
         (map (lambda (v)
                (let ((text (guard (e (#t (describe e)))
                              ((cdr a) v)
                              'no-raise)))
                  (cond ((eq? text 'no-raise) 'no-raise)
                        ((contains? text secret) 'printed)
                        (else 'absent))))
              (list secret (list "u" secret) (vector secret))))
       lib-accessors))

;; --- checked-accessor --------------------------------------------------------

(test-equal "checked-accessor answers the accessor's value for what the predicate holds, and refuses the rest, from WHO, naming it by shown-value, a pair or a vector holding a string by its kind"
  '((no-raise 11)
    (assertion-violation my-who ((kind string)))
    (assertion-violation my-who (7))
    (assertion-violation my-who ((kind list)))
    (assertion-violation my-who ((kind vector))))
  (let ((get (checked-accessor 'my-who (lambda (x) (and (pair? x) (number? (car x)))) "a thing"
                               (lambda (x) (+ 1 (car x))))))
    (list (raised (lambda () (get '(10))))
          (raised (lambda () (get secret)))
          (raised (lambda () (get 7)))
          (raised (lambda () (get (list "u" secret))))
          (raised (lambda () (get (vector secret)))))))

;; --- a caller's value, as a refusal names it ---------------------------------

;; circular : List
;; A list whose last pair points back at its first.
(define circular (let ((l (list 1 2))) (set-cdr! (cdr l) l) l))

(test-equal "kind-of, written out: a string, a list, () among them, a number, exact and inexact, a boolean, a char, a symbol, a bytevector, a vector, a procedure, and anything else, a hashtable"
  '(string list list number number boolean char symbol bytevector vector procedure other)
  (map kind-of (list "s" '(a) '() 5 1.5 #t #\a 'x (make-bytevector 1 0) (vector 1) car (make-eq-hashtable))))

(define shown-values
  (list 'x 5 #f #\a '() '(429 503) '(get post)
        secret (list "u" secret) '(1 . 2) circular
        (make-bytevector 1 0) (vector secret) car (make-eq-hashtable)))

(test-equal "shown-value, written out against the whole complement of what it shows: a symbol, a number, a boolean, a char, (), and a proper list of them, as given; a string, a list holding a string, an improper list, a circular one, a bytevector, a vector, a procedure and a hashtable by their kind"
  (list 'x 5 #f #\a '() '(429 503) '(get post)
        '(kind string) '(kind list) '(kind list) '(kind list) '(kind bytevector) '(kind vector)
        '(kind procedure) '(kind other))
  (map shown-value shown-values))

;; (chez-sqlite3 private libsqlite3-info) cannot import shown-value, since
;; this library imports it, so it carries a copy of the rule. The copy is
;; read through an accessor's refusal.
(test-equal "libsqlite3-info's own copy of the rule agrees with shown-value on every kind"
  ;; Written out, not computed with shown-value: a shown-value that raised
  ;; would end the suite with no test named.
  '((assertion-violation libsqlite3-info-path (x))
    (assertion-violation libsqlite3-info-path (5))
    (assertion-violation libsqlite3-info-path (#f))
    (assertion-violation libsqlite3-info-path (#\a))
    (assertion-violation libsqlite3-info-path (()))
    (assertion-violation libsqlite3-info-path ((429 503)))
    (assertion-violation libsqlite3-info-path ((get post)))
    (assertion-violation libsqlite3-info-path ((kind string)))
    (assertion-violation libsqlite3-info-path ((kind list)))
    (assertion-violation libsqlite3-info-path ((kind list)))
    (assertion-violation libsqlite3-info-path ((kind list)))
    (assertion-violation libsqlite3-info-path ((kind bytevector)))
    (assertion-violation libsqlite3-info-path ((kind vector)))
    (assertion-violation libsqlite3-info-path ((kind procedure)))
    (assertion-violation libsqlite3-info-path ((kind other))))
  (map (lambda (v) (raised (lambda () (libsqlite3-info-path v)))) shown-values))

;; --- &sqlite-error, &sqlite-wrong-thread and &sqlite-closed (M1 slice 4) ----------------------
;; Each fixture field holds a value no other field holds. Every refusal names
;; the field or the rule it broke first among its irritants, so two refusals
;; from one who are told apart without their message (ADR-0013, decision 9).

;; an-sqlite-error, a-wrong-thread, a-closed : -> Condition
(define (an-sqlite-error)
  (make-sqlite-error 'busy 'busy-snapshot "fixture message" "SELECT fixture" 7))
(define (a-wrong-thread) (make-sqlite-wrong-thread 3 5))
(define (a-closed) (make-sqlite-closed))

;; kinds-of : Any -> (Listof Boolean)
;; error?, assertion-violation?, chez-sqlite3-error?, sqlite-error?,
;; sqlite-library-unavailable?, sqlite-wrong-thread? and sqlite-closed?.
(define (kinds-of c)
  (list (error? c) (assertion-violation? c) (chez-sqlite3-error? c) (sqlite-error? c)
        (sqlite-library-unavailable? c) (sqlite-wrong-thread? c) (sqlite-closed? c)))

;; built : (-> Any) -> Any
;; THUNK's answer, or (raised TEXT): a constructor that raises names its row.
(define (built thunk)
  (guard (e (#t (list 'raised (describe e)))) (thunk)))

(test-equal "the kinds, whole: each of the four library conditions is an error and a chez-sqlite3-error, of its own type alone, and no assertion violation; the root alone is no type below it; an assertion violation and a plain error are no library condition"
  '((#t #f #t #t #f #f #f)
    (#t #f #t #f #t #f #f)
    (#t #f #t #f #f #t #f)
    (#t #f #t #f #f #f #t)
    (#t #f #t #f #f #f #f)
    (#f #t #f #f #f #f #f)
    (#t #f #f #f #f #f #f))
  (map (lambda (thunk) (let ((c (built thunk))) (if (condition? c) (kinds-of c) c)))
       (list an-sqlite-error a-library-unavailable a-wrong-thread a-closed make-chez-sqlite3-error
             make-assertion-violation make-error)))

(test-equal "an sqlite-error carries its code, extended code, message, sql and offset"
  '(busy busy-snapshot "fixture message" "SELECT fixture" 7)
  (built (lambda ()
           (let ((c (an-sqlite-error)))
             (list (sqlite-error-code c) (sqlite-error-extended-code c) (sqlite-error-message c)
                   (sqlite-error-sql c) (sqlite-error-offset c))))))

(test-equal "an sqlite-error's codes may be integers, a code no table row names, and its sql and offset absent, compared as the symbol none"
  '(29 25358 "m" none none)
  (built (lambda ()
           (let ((c (make-sqlite-error 29 25358 "m" #f #f)))
             (list (sqlite-error-code c) (sqlite-error-extended-code c) (sqlite-error-message c)
                   (if (eq? (sqlite-error-sql c) #f) 'none 'some)
                   (if (eq? (sqlite-error-offset c) #f) 'none 'some))))))

(test-equal "a wrong-thread carries its owner and its caller"
  '(3 5)
  (built (lambda ()
           (let ((c (a-wrong-thread)))
             (list (sqlite-wrong-thread-owner c) (sqlite-wrong-thread-caller c))))))

(define new-accessors
  (list (cons 'sqlite-error-code sqlite-error-code)
        (cons 'sqlite-error-extended-code sqlite-error-extended-code)
        (cons 'sqlite-error-message sqlite-error-message)
        (cons 'sqlite-error-sql sqlite-error-sql)
        (cons 'sqlite-error-offset sqlite-error-offset)
        (cons 'sqlite-wrong-thread-owner sqlite-wrong-thread-owner)
        (cons 'sqlite-wrong-thread-caller sqlite-wrong-thread-caller)))

(test-equal "every new accessor refuses another type's condition, the root alone, a string by its kind, a number and a list holding a string, from the accessor, by shown-value"
  (map (lambda (a)
         (list (refusal (car a) '(kind other))
               (refusal (car a) '(kind other))
               (refusal (car a) '(kind other))
               (refusal (car a) '(kind string))
               (refusal (car a) 5)
               (refusal (car a) '(kind list))))
       new-accessors)
  (map (lambda (a)
         (map (lambda (v) (raised (lambda () ((cdr a) v))))
              (list (if (memq (car a) '(sqlite-wrong-thread-owner sqlite-wrong-thread-caller))
                        (an-sqlite-error)
                        (a-wrong-thread))
                    (a-closed) (make-chez-sqlite3-error) secret 5 (list "u" secret))))
       new-accessors))

(test-equal "make-sqlite-error refuses each field it is not given the right kind of, naming the field and the value by shown-value"
  '((assertion-violation make-sqlite-error (code (kind string)))
    (assertion-violation make-sqlite-error (code 1.5))
    (assertion-violation make-sqlite-error (extended-code (kind string)))
    (assertion-violation make-sqlite-error (extended-code #f))
    (assertion-violation make-sqlite-error (message 5))
    (assertion-violation make-sqlite-error (message #f))
    (assertion-violation make-sqlite-error (sql 5))
    (assertion-violation make-sqlite-error (offset -1))
    (assertion-violation make-sqlite-error (offset (kind string))))
  (list (raised (lambda () (make-sqlite-error "busy" 'busy "m" #f #f)))
        (raised (lambda () (make-sqlite-error 1.5 'busy "m" #f #f)))
        (raised (lambda () (make-sqlite-error 'busy "busy" "m" #f #f)))
        (raised (lambda () (make-sqlite-error 'busy #f "m" #f #f)))
        (raised (lambda () (make-sqlite-error 'busy 'busy 5 #f #f)))
        (raised (lambda () (make-sqlite-error 'busy 'busy #f #f #f)))
        (raised (lambda () (make-sqlite-error 'busy 'busy "m" 5 #f)))
        (raised (lambda () (make-sqlite-error 'busy 'busy "m" #f -1)))
        (raised (lambda () (make-sqlite-error 'busy 'busy "m" #f "7")))))

(test-equal "make-sqlite-wrong-thread refuses an owner or a caller that is no exact natural, naming which"
  '((assertion-violation make-sqlite-wrong-thread (owner -1))
    (assertion-violation make-sqlite-wrong-thread (owner (kind string)))
    (assertion-violation make-sqlite-wrong-thread (caller 1.5))
    (assertion-violation make-sqlite-wrong-thread (caller #f)))
  (list (raised (lambda () (make-sqlite-wrong-thread -1 5)))
        (raised (lambda () (make-sqlite-wrong-thread "3" 5)))
        (raised (lambda () (make-sqlite-wrong-thread 3 1.5)))
        (raised (lambda () (make-sqlite-wrong-thread 3 #f)))))

;; --- the raise helpers -------------------------------------------------------------------

;; compound : (-> Any) -> Any
;; What THUNK raised, as the whole compound: its kinds, its who, whether it
;; has a message and irritants (never the text), and its own fields; an
;; assertion violation as (assertion-violation WHO IRRITANTS); or no-raise.
(define (compound thunk)
  (guard (e ((chez-sqlite3-error? e)
             (append (list (kinds-of e)
                           (and (who-condition? e) (condition-who e))
                           (if (message-condition? e) 'message 'no-message)
                           (if (irritants-condition? e) 'irritants 'no-irritants))
                     (cond ((sqlite-error? e)
                            (list (sqlite-error-code e) (sqlite-error-extended-code e)
                                  (sqlite-error-message e)
                                  (if (and (message-condition? e)
                                           (equal? (condition-message e) (sqlite-error-message e)))
                                      'message-is-the-field
                                      'message-differs)
                                  (or (sqlite-error-sql e) 'none) (or (sqlite-error-offset e) 'none)))
                           ((sqlite-wrong-thread? e)
                            (list (sqlite-wrong-thread-owner e) (sqlite-wrong-thread-caller e)))
                           (else '()))))
            ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other-raise (describe e))))
    (thunk)
    'no-raise))

(test-equal "raise-sqlite-error raises the whole condition: an sqlite-error from the who given, with a message that is the message field, no irritants, its sql and offset as given"
  '((#t #f #t #t #f #f #f) open-database message no-irritants
    cantopen cantopen-symlink "unable to open database file" message-is-the-field "SELECT 1" 4)
  (compound (lambda ()
              (raise-sqlite-error 'open-database 1550 "unable to open database file" "SELECT 1" 4))))

;; The names, from the integer: primary and extended, a code with no
;; extension, the floor's newest, an extended code no row names, and a
;; primary no row names.
(test-equal "raise-sqlite-error names the code and the extended code from the integer, by constants' table, whole"
  '((cantopen cantopen) (cantopen cantopen-symlink) (constraint constraint-unique) (busy busy)
    (busy busy-snapshot) (ioerr ioerr-in-page) (cantopen 25358) (29 29) (error error-missing-collseq))
  (map (lambda (code)
         (let ((c (compound (lambda () (raise-sqlite-error 'w code "m" #f #f)))))
           (if (and (list? c) (> (length c) 5) (pair? (car c)))
               (list (list-ref c 4) (list-ref c 5))
               c)))
       '(14 1550 2067 5 517 8714 25358 29 257)))

(test-equal "raise-sqlite-error refuses a code that is no error, ok, row and done and the extended codes of ok, and one that is no exact integer, naming the rule"
  '((assertion-violation raise-sqlite-error (not-an-error 0))
    (assertion-violation raise-sqlite-error (not-an-error 100))
    (assertion-violation raise-sqlite-error (not-an-error 101))
    (assertion-violation raise-sqlite-error (not-an-error 256))
    (assertion-violation raise-sqlite-error (not-an-error 512))
    (assertion-violation raise-sqlite-error (extended-code 1.5))
    (assertion-violation raise-sqlite-error (extended-code busy))
    (assertion-violation raise-sqlite-error (extended-code (kind string))))
  (map (lambda (code) (compound (lambda () (raise-sqlite-error 'w code "m" #f #f))))
       (list 0 100 101 256 512 1.5 'busy "14")))

(test-equal "raise-sqlite-error refuses a who that is no symbol, and a message the constructor refuses, from the constructor"
  '((assertion-violation raise-sqlite-error (who (kind string)))
    (assertion-violation make-sqlite-error (message 5)))
  (list (compound (lambda () (raise-sqlite-error "w" 14 "m" #f #f)))
        (compound (lambda () (raise-sqlite-error 'w 14 5 #f #f)))))

(test-equal "raise-wrong-thread raises a wrong-thread from the who given, with a message, no irritants, and its owner and caller"
  '((#t #f #t #f #f #t #f) close-database! message no-irritants 11 13)
  (compound (lambda () (raise-wrong-thread 'close-database! 11 13))))

(test-equal "raise-closed raises a closed from the who given, with a message, no irritants and no fields"
  '((#t #f #t #f #f #f #t) call-with-open-handle message no-irritants)
  (compound (lambda () (raise-closed 'call-with-open-handle))))

(test-equal "raise-wrong-thread and raise-closed refuse a who that is no symbol; raise-wrong-thread an id the constructor refuses, from the constructor"
  '((assertion-violation raise-wrong-thread (who (kind string)))
    (assertion-violation raise-closed (who 5))
    (assertion-violation make-sqlite-wrong-thread (owner -2)))
  (list (compound (lambda () (raise-wrong-thread "close-database!" 1 2)))
        (compound (lambda () (raise-closed 5)))
        (compound (lambda () (raise-wrong-thread 'w -2 2)))))

(test-equal "no raise helper returns: a handler that returns gets nothing back, and what goes on to the next handler is the &non-continuable R6RS raises for it"
  '(non-continuable non-continuable non-continuable)
  (map (lambda (thunk)
         (guard (e ((non-continuable-violation? e) 'non-continuable)
                   (#t (list 'other-raise (describe e))))
           (with-exception-handler (lambda (c) 'handled) thunk)
           'returned-normally))
       (list (lambda () (raise-sqlite-error 'w 14 "m" #f #f))
             (lambda () (raise-wrong-thread 'w 1 2))
             (lambda () (raise-closed 'w)))))

;; --- M2 slice 1: the subtypes of &sqlite-error, and &sqlite-invalid-text --------------------

;; none-if-false : Any -> Any
;; An answer of #f as the symbol none: no row here expects #f.
(define (none-if-false x) (if (eq? x #f) 'none x))

;; subtype-of : Any -> Any
;; sqlite-error-subtype's answer, #f as none, or (raised TEXT).
(define (subtype-of x)
  (guard (e (#t (list 'raised (describe e)))) (none-if-false (sqlite-error-subtype x))))

;; Written out, never read from the code under test: the primary names that class.
(define busy-names '(busy locked))
(define constraint-names '(constraint))
(define read-only-names '(readonly))
(define interrupt-names '(interrupt))

;; expected-subtype : Any -> Symbol
(define (expected-subtype name)
  (cond ((memq name busy-names) 'busy)
        ((memq name constraint-names) 'constraint)
        ((memq name read-only-names) 'read-only)
        ((memq name interrupt-names) 'interrupt)
        (else 'none)))

(define every-name (map car sqlite-result-codes))

(test-equal "the table holds 108 names, so the rows below cover all of them"
  108
  (length every-name))

(test-equal "sqlite-error-subtype over every name in sqlite-result-codes, extended names too, as one list"
  (map expected-subtype every-name)
  (map subtype-of every-name))

(test-equal "sqlite-error-subtype classes exactly the names busy, locked, constraint, readonly and interrupt: the whole answer for the five, and none for each extended name of theirs"
  '(busy busy constraint read-only interrupt none none none none none)
  (map subtype-of '(busy locked constraint readonly interrupt busy-snapshot busy-recovery
                    locked-sharedcache constraint-unique readonly-recovery)))

(test-equal "sqlite-error-subtype gives none for every integer, the codes of busy, locked, readonly, interrupt and constraint among them, and for every non-symbol"
  (append (map (lambda (i) 'none) '(0 5 6 8 9 19 261 2067 -1 1.5 100000000000000000000))
          (map (lambda (i) 'none) '(1 2 3 4 5 6 7 8 9 10 11 12 13)))
  (append (map subtype-of '(0 5 6 8 9 19 261 2067 -1 1.5 100000000000000000000))
          (map subtype-of (list "busy" #f #t '(busy) (vector 'busy) #\b car (make-bytevector 1 0)
                                '() (make-eq-hashtable) (make-error) (string->symbol "")
                                "interrupt"))))

(test-equal "sqlite-error-subtype reads case: BUSY, Busy, busy-x, INTERRUPT, Interrupt and interrupt-x are none, busy is busy and interrupt is interrupt"
  '(none none none busy none none none interrupt)
  (map subtype-of '(BUSY Busy busy-x busy INTERRUPT Interrupt interrupt-x interrupt)))

;; subtype-kinds : (-> Any) -> (U (List Boolean Boolean Boolean Boolean Boolean) (raised ...))
;; sqlite-error?, then the four subtype predicates, of what THUNK builds.
(define (subtype-kinds thunk)
  (guard (e (#t (list 'raised (describe e))))
    (let ((c (thunk)))
      (list (sqlite-error? c) (sqlite-busy? c) (sqlite-constraint? c) (sqlite-read-only? c)
            (sqlite-interrupt? c)))))

(define (expected-kinds name)
  (case (expected-subtype name)
    ((busy) '(#t #t #f #f #f))
    ((constraint) '(#t #f #t #f #f))
    ((read-only) '(#t #f #f #t #f))
    ((interrupt) '(#t #f #f #f #t))
    (else '(#t #f #f #f #f))))

(define primary-names
  (map car (filter (lambda (row) (< (cdr row) 256)) sqlite-result-codes)))

(test-equal "the table holds 31 primary names, ok through warning, row and done among them"
  31
  (length primary-names))

(test-equal "make-sqlite-error builds, for each primary code's name, the subtype sqlite-error-subtype gives, whole"
  (map expected-kinds primary-names)
  (map (lambda (name)
         (subtype-kinds (lambda () (make-sqlite-error name name "m" #f #f))))
       primary-names))

(test-equal "exactly one primary code's name builds an &sqlite-interrupt: interrupt"
  '(interrupt)
  (filter (lambda (name)
            (guard (e (#t #f)) (sqlite-interrupt? (make-sqlite-error name name "m" #f #f))))
          primary-names))

(test-equal "make-sqlite-error classes by the primary code alone: an extended name or an integer as the code gives a plain &sqlite-error, whatever the extended code is"
  '((#t #f #f #f #f) (#t #f #f #f #f) (#t #f #f #f #f) (#t #f #f #f #f) (#t #t #f #f #f)
    (#t #f #t #f #f) (#t #f #f #f #f) (#t #f #f #f #t) (#t #t #f #f #f) (#t #f #f #f #f))
  (map subtype-kinds
       (list (lambda () (make-sqlite-error 'busy-snapshot 'busy-snapshot "m" #f #f))
             (lambda () (make-sqlite-error 517 'busy "m" #f #f))
             (lambda () (make-sqlite-error 5 5 "m" #f #f))
             (lambda () (make-sqlite-error 'error 'busy-snapshot "m" #f #f))
             (lambda () (make-sqlite-error 'busy 'error "m" #f #f))
             (lambda () (make-sqlite-error 'constraint 'constraint-unique "m" #f #f))
             (lambda () (make-sqlite-error 9 'interrupt "m" #f #f))
             (lambda () (make-sqlite-error 'interrupt 'busy "m" #f #f))
             (lambda () (make-sqlite-error 'busy 'interrupt "m" #f #f))
             (lambda () (make-sqlite-error 'error 'interrupt "m" #f #f)))))

(test-equal "a subtype keeps every field of &sqlite-error, read back whole"
  '((busy busy-snapshot "fixture message" "SELECT fixture" 7)
    (constraint constraint-unique "other message" #f 0)
    (readonly readonly-dbmoved "third" "SQL 3" #f)
    (interrupt interrupt "interrupted" "select 4" 3))
  (map (lambda (c)
         (list (sqlite-error-code c) (sqlite-error-extended-code c) (sqlite-error-message c)
               (sqlite-error-sql c) (sqlite-error-offset c)))
       (list (make-sqlite-error 'busy 'busy-snapshot "fixture message" "SELECT fixture" 7)
             (make-sqlite-error 'constraint 'constraint-unique "other message" #f 0)
             (make-sqlite-error 'readonly 'readonly-dbmoved "third" "SQL 3" #f)
             (make-sqlite-error 'interrupt 'interrupt "interrupted" "select 4" 3))))

(test-equal "make-sqlite-error checks the same fields in the same order for a subtype's code: the code is checked before the message"
  '((assertion-violation make-sqlite-error (code (kind string)))
    (assertion-violation make-sqlite-error (message 5))
    (assertion-violation make-sqlite-error (extended-code #f))
    (assertion-violation make-sqlite-error (offset -1)))
  (list (raised (lambda () (make-sqlite-error "busy" 'busy 5 #f #f)))
        (raised (lambda () (make-sqlite-error 'busy 'busy 5 #f #f)))
        (raised (lambda () (make-sqlite-error 'busy #f "m" #f #f)))
        (raised (lambda () (make-sqlite-error 'constraint 'constraint "m" #f -1)))))

(define low-byte-codes
  (map cdr (filter (lambda (row) (not (memv (bitwise-and (cdr row) 255) '(0 100 101))))
                   sqlite-result-codes)))

(test-equal "the table holds 103 codes whose low byte is not 0, 100 or 101: 108 less ok, row, done and the extended codes of ok"
  103
  (length low-byte-codes))

;; Written out: the low bytes of busy, locked, constraint, readonly and
;; interrupt.
(define (expected-kinds-of-code code)
  (case (bitwise-and code 255)
    ((5 6) '(#t #t #f #f #f))
    ((19) '(#t #f #t #f #f))
    ((8) '(#t #f #f #t #f))
    ((9) '(#t #f #f #f #t))
    (else '(#t #f #f #f #f))))

(test-equal "raise-sqlite-error over every code of the table with a low byte of an error raises the subtype of its primary code, whole"
  (map expected-kinds-of-code low-byte-codes)
  (map (lambda (code)
         (guard (e ((sqlite-error? e)
                    (list (sqlite-error? e) (sqlite-busy? e) (sqlite-constraint? e)
                          (sqlite-read-only? e) (sqlite-interrupt? e)))
                   (#t (list 'other-raise (describe e))))
           (raise-sqlite-error 'w code "m" #f #f)
           'no-raise))
       low-byte-codes))

(test-equal "raise-sqlite-error's subtype is still compounded with its who and message, and its codes by name"
  '((#t #t #f #f #f) w "m" busy busy-snapshot)
  (guard (e ((sqlite-error? e)
             (list (list (sqlite-error? e) (sqlite-busy? e) (sqlite-constraint? e)
                         (sqlite-read-only? e) (sqlite-interrupt? e))
                   (condition-who e) (condition-message e)
                   (sqlite-error-code e) (sqlite-error-extended-code e)))
            (#t (list 'other-raise (describe e))))
    (raise-sqlite-error 'w 517 "m" #f #f)
    'no-raise))

(test-equal "raise-sqlite-error of 9 raises an &sqlite-interrupt, compounded with its who and message, its codes by name, its sql and offset as given"
  '((#t #f #f #f #t) step! "interrupted" interrupt interrupt "select 1; select 2" 10)
  (guard (e ((sqlite-error? e)
             (list (list (sqlite-error? e) (sqlite-busy? e) (sqlite-constraint? e)
                         (sqlite-read-only? e) (sqlite-interrupt? e))
                   (condition-who e) (condition-message e)
                   (sqlite-error-code e) (sqlite-error-extended-code e)
                   (sqlite-error-sql e) (sqlite-error-offset e)))
            (#t (list 'other-raise (describe e))))
    (raise-sqlite-error 'step! 9 "interrupted" "select 1; select 2" 10)
    'no-raise))

;; invalid-text : -> &sqlite-invalid-text
(define (an-invalid-text) (make-sqlite-invalid-text 3 5))

;; a-setting-mismatch, a-transaction-ended : -> Condition
;; Each field holds a value no other field holds.
(define (a-setting-mismatch) (make-sqlite-setting-mismatch 'journal-mode "wal" "memory"))
(define (a-transaction-ended) (make-sqlite-transaction-ended))

;; an-extensions-unavailable : -> Condition
(define (an-extensions-unavailable) (make-sqlite-extensions-unavailable))

;; matrix-kinds : Any -> (Listof Boolean)
;; error?, assertion-violation?, chez-sqlite3-error?, sqlite-error?, busy?,
;; constraint?, read-only?, interrupt?, invalid-text?, setting-mismatch?,
;; transaction-ended?, extensions-unavailable?, library-unavailable?,
;; wrong-thread?, closed?.
(define (matrix-kinds c)
  (list (error? c) (assertion-violation? c) (chez-sqlite3-error? c) (sqlite-error? c)
        (sqlite-busy? c) (sqlite-constraint? c) (sqlite-read-only? c) (sqlite-interrupt? c)
        (sqlite-invalid-text? c) (sqlite-setting-mismatch? c) (sqlite-transaction-ended? c)
        (sqlite-extensions-unavailable? c)
        (sqlite-library-unavailable? c) (sqlite-wrong-thread? c) (sqlite-closed? c)))

(test-equal "the matrix, whole: every type against every predicate, so none sits under the wrong parent"
  '(;; root
    (#t #f #t #f #f #f #f #f #f #f #f #f #f #f #f)
    ;; plain &sqlite-error
    (#t #f #t #t #f #f #f #f #f #f #f #f #f #f #f)
    ;; &sqlite-busy
    (#t #f #t #t #t #f #f #f #f #f #f #f #f #f #f)
    ;; &sqlite-constraint
    (#t #f #t #t #f #t #f #f #f #f #f #f #f #f #f)
    ;; &sqlite-read-only
    (#t #f #t #t #f #f #t #f #f #f #f #f #f #f #f)
    ;; &sqlite-interrupt
    (#t #f #t #t #f #f #f #t #f #f #f #f #f #f #f)
    ;; &sqlite-invalid-text: under the root, not under &sqlite-error
    (#t #f #t #f #f #f #f #f #t #f #f #f #f #f #f)
    ;; &sqlite-setting-mismatch and &sqlite-transaction-ended: under the root
    (#t #f #t #f #f #f #f #f #f #t #f #f #f #f #f)
    (#t #f #t #f #f #f #f #f #f #f #t #f #f #f #f)
    ;; &sqlite-extensions-unavailable: under the root, neither an
    ;; &sqlite-error nor an &sqlite-library-unavailable
    (#t #f #t #f #f #f #f #f #f #f #f #t #f #f #f)
    ;; library-unavailable, wrong-thread, closed
    (#t #f #t #f #f #f #f #f #f #f #f #f #t #f #f)
    (#t #f #t #f #f #f #f #f #f #f #f #f #f #t #f)
    (#t #f #t #f #f #f #f #f #f #f #f #f #f #f #t)
    ;; an assertion violation, a plain error
    (#f #t #f #f #f #f #f #f #f #f #f #f #f #f #f)
    (#t #f #f #f #f #f #f #f #f #f #f #f #f #f #f))
  (map (lambda (thunk) (let ((c (built thunk))) (if (condition? c) (matrix-kinds c) c)))
       (list make-chez-sqlite3-error
             (lambda () (make-sqlite-error 'error 'error "m" #f #f))
             (lambda () (make-sqlite-error 'busy 'busy "m" #f #f))
             (lambda () (make-sqlite-error 'constraint 'constraint "m" #f #f))
             (lambda () (make-sqlite-error 'readonly 'readonly "m" #f #f))
             (lambda () (make-sqlite-error 'interrupt 'interrupt "m" #f #f))
             an-invalid-text
             a-setting-mismatch a-transaction-ended
             an-extensions-unavailable
             a-library-unavailable a-wrong-thread a-closed
             make-assertion-violation make-error)))

(test-equal "locked is a busy too, and no other type holds more than its own predicates"
  '(#t #f #f #f)
  (let ((c (make-sqlite-error 'locked 'locked-sharedcache "m" #f #f)))
    (list (sqlite-busy? c) (sqlite-constraint? c) (sqlite-read-only? c) (sqlite-interrupt? c))))

(test-equal "the eight predicates are false for a symbol, #f, a string, a number and a message"
  '((#f #f #f #f #f #f #f #f) (#f #f #f #f #f #f #f #f) (#f #f #f #f #f #f #f #f)
    (#f #f #f #f #f #f #f #f) (#f #f #f #f #f #f #f #f))
  (map (lambda (v)
         (list (sqlite-busy? v) (sqlite-constraint? v) (sqlite-read-only? v)
               (sqlite-invalid-text? v) (sqlite-interrupt? v) (sqlite-setting-mismatch? v)
               (sqlite-transaction-ended? v) (sqlite-extensions-unavailable? v)))
       (list 'busy #f "busy" 5 (make-message-condition "busy"))))

(test-equal "sqlite-extensions-unavailable? is false for every value that is no condition and for every other condition: a symbol, #f, #t, (), a string, a number, a char, a vector, a procedure; a message, a who, an irritants, a plain error, an assertion violation, a serious condition, and a compound of a message and a who"
  '(#f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f)
  (map (lambda (v) (sqlite-extensions-unavailable? v))
       (list 'sqlite-extensions-unavailable #f #t '() "extensions" 5 #\e
             (vector (make-sqlite-extensions-unavailable)) car
             (make-message-condition "m") (make-who-condition 'open-database)
             (make-irritants-condition '()) (make-error) (make-assertion-violation)
             (make-serious-condition)
             (condition (make-message-condition "m") (make-who-condition 'open-database)))))

(test-equal "the exported types sit where the matrix says: each subtype's parent is &sqlite-error; &sqlite-invalid-text's, &sqlite-setting-mismatch's, &sqlite-transaction-ended's and &sqlite-extensions-unavailable's is the root"
  '(#t #t #t #t #t #t #t #t)
  (list (eq? (record-type-parent (record-type-descriptor &sqlite-busy)) (record-type-descriptor &sqlite-error))
        (eq? (record-type-parent (record-type-descriptor &sqlite-constraint)) (record-type-descriptor &sqlite-error))
        (eq? (record-type-parent (record-type-descriptor &sqlite-read-only)) (record-type-descriptor &sqlite-error))
        (eq? (record-type-parent (record-type-descriptor &sqlite-interrupt)) (record-type-descriptor &sqlite-error))
        (eq? (record-type-parent (record-type-descriptor &sqlite-invalid-text)) (record-type-descriptor &chez-sqlite3-error))
        (eq? (record-type-parent (record-type-descriptor &sqlite-setting-mismatch)) (record-type-descriptor &chez-sqlite3-error))
        (eq? (record-type-parent (record-type-descriptor &sqlite-transaction-ended)) (record-type-descriptor &chez-sqlite3-error))
        (eq? (record-type-parent (record-type-descriptor &sqlite-extensions-unavailable)) (record-type-descriptor &chez-sqlite3-error))))

(test-equal "the types' own fields: none for the subtypes; &sqlite-invalid-text's are column and offset; &sqlite-setting-mismatch's setting, expected and actual; &sqlite-transaction-ended's none; &sqlite-extensions-unavailable's none"
  '(#() #() #() #() #(column offset) #(setting expected actual) #() #())
  (list (record-type-field-names (record-type-descriptor &sqlite-busy)) (record-type-field-names (record-type-descriptor &sqlite-constraint))
        (record-type-field-names (record-type-descriptor &sqlite-read-only))
        (record-type-field-names (record-type-descriptor &sqlite-interrupt))
        (record-type-field-names (record-type-descriptor &sqlite-invalid-text))
        (record-type-field-names (record-type-descriptor &sqlite-setting-mismatch))
        (record-type-field-names (record-type-descriptor &sqlite-transaction-ended))
        (record-type-field-names (record-type-descriptor &sqlite-extensions-unavailable))))

;; --- &sqlite-invalid-text ----------------------------------------------------------------

(test-equal "an invalid-text carries its column and its byte offset"
  '(3 5)
  (built (lambda ()
           (let ((c (an-invalid-text)))
             (list (sqlite-invalid-text-column c) (sqlite-invalid-text-offset c))))))

(test-equal "an invalid-text takes 0 and a number beyond a fixnum, each field alone"
  '((0 7) (8 0) (100000000000000000000 100000000000000000001))
  (map (lambda (p)
         (built (lambda ()
                  (let ((c (make-sqlite-invalid-text (car p) (cdr p))))
                    (list (sqlite-invalid-text-column c) (sqlite-invalid-text-offset c))))))
       '((0 . 7) (8 . 0) (100000000000000000000 . 100000000000000000001))))

(test-equal "make-sqlite-invalid-text refuses a column or an offset that is no exact natural, naming which field and the value by shown-value"
  '((assertion-violation make-sqlite-invalid-text (column -1))
    (assertion-violation make-sqlite-invalid-text (column (kind string)))
    (assertion-violation make-sqlite-invalid-text (column 1.5))
    (assertion-violation make-sqlite-invalid-text (column #f))
    (assertion-violation make-sqlite-invalid-text (offset -1))
    (assertion-violation make-sqlite-invalid-text (offset (kind string)))
    (assertion-violation make-sqlite-invalid-text (offset 2.0))
    (assertion-violation make-sqlite-invalid-text (offset x))
    (assertion-violation make-sqlite-invalid-text (column -1)))
  (list (raised (lambda () (make-sqlite-invalid-text -1 0)))
        (raised (lambda () (make-sqlite-invalid-text "3" 0)))
        (raised (lambda () (make-sqlite-invalid-text 1.5 0)))
        (raised (lambda () (make-sqlite-invalid-text #f 0)))
        (raised (lambda () (make-sqlite-invalid-text 0 -1)))
        (raised (lambda () (make-sqlite-invalid-text 0 secret)))
        (raised (lambda () (make-sqlite-invalid-text 0 2.0)))
        (raised (lambda () (make-sqlite-invalid-text 0 'x)))
        (raised (lambda () (make-sqlite-invalid-text -1 -1)))))

(define invalid-text-accessors
  (list (cons 'sqlite-invalid-text-column sqlite-invalid-text-column)
        (cons 'sqlite-invalid-text-offset sqlite-invalid-text-offset)))

(test-equal "each invalid-text accessor refuses another type's condition, a sqlite-error, the root, a string by its kind, a number and a list holding a string, from the accessor"
  (map (lambda (a)
         (list (refusal (car a) '(kind other))
               (refusal (car a) '(kind other))
               (refusal (car a) '(kind other))
               (refusal (car a) '(kind string))
               (refusal (car a) 5)
               (refusal (car a) '(kind list))))
       invalid-text-accessors)
  (map (lambda (a)
         (map (lambda (v) (raised (lambda () ((cdr a) v))))
              (list (an-sqlite-error) (a-closed) (make-chez-sqlite3-error) secret 5
                    (list "u" secret))))
       invalid-text-accessors))

;; invalid-text-compound : (-> Any) -> Any
;; What THUNK raised: its kinds, who, whether it has a message and irritants
;; (never the text), and the column and offset; an assertion violation as
;; (assertion-violation WHO IRRITANTS); or no-raise.
(define (invalid-text-compound thunk)
  (guard (e ((sqlite-invalid-text? e)
             (list (matrix-kinds e)
                   (and (who-condition? e) (condition-who e))
                   (if (message-condition? e) 'message 'no-message)
                   (if (irritants-condition? e) 'irritants 'no-irritants)
                   (sqlite-invalid-text-column e) (sqlite-invalid-text-offset e)))
            ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other-raise (describe e))))
    (thunk)
    'no-raise))

(test-equal "raise-invalid-text raises the whole condition: an invalid-text from the who given, with a message, no irritants, its column and offset"
  '((#t #f #t #f #f #f #f #f #t #f #f #f #f #f #f) column-value message no-irritants 4 9)
  (invalid-text-compound (lambda () (raise-invalid-text 'column-value 4 9))))

(test-equal "raise-invalid-text names its who, and takes column 0 and offset 0"
  '(column-name column-bytevector)
  (map (lambda (who)
         (let ((c (invalid-text-compound (lambda () (raise-invalid-text who 0 0)))))
           (if (and (list? c) (> (length c) 1)) (cadr c) c)))
       '(column-name column-bytevector)))

(test-equal "raise-invalid-text refuses a who that is no symbol, before it checks the fields, and a field the constructor refuses, from the constructor"
  '((assertion-violation raise-invalid-text (who (kind string)))
    (assertion-violation raise-invalid-text (who 5))
    (assertion-violation raise-invalid-text (who (kind string)))
    (assertion-violation make-sqlite-invalid-text (column -1))
    (assertion-violation make-sqlite-invalid-text (offset (kind string))))
  (list (invalid-text-compound (lambda () (raise-invalid-text "column-value" 1 2)))
        (invalid-text-compound (lambda () (raise-invalid-text 5 1 2)))
        (invalid-text-compound (lambda () (raise-invalid-text "w" -1 "x")))
        (invalid-text-compound (lambda () (raise-invalid-text 'w -1 2)))
        (invalid-text-compound (lambda () (raise-invalid-text 'w 1 "2")))))

(test-equal "raise-invalid-text never returns: a handler that returns gets the &non-continuable R6RS raises for it"
  'non-continuable
  (guard (e ((non-continuable-violation? e) 'non-continuable)
            (#t (list 'other-raise (describe e))))
    (with-exception-handler (lambda (c) 'handled) (lambda () (raise-invalid-text 'w 1 2)))
    'returned-normally))

;; --- M3 slice 1: &sqlite-setting-mismatch and &sqlite-transaction-ended -------------------
;; The interrupt's class is held above, with the other classes of
;; &sqlite-error, over every primary code.

(test-equal "a setting-mismatch carries its setting, the value asked for and the value read"
  '(journal-mode "wal" "memory")
  (built (lambda ()
           (let ((c (a-setting-mismatch)))
             (list (sqlite-setting-mismatch-setting c) (sqlite-setting-mismatch-expected c)
                   (sqlite-setting-mismatch-actual c))))))

;; Expected and actual are Scheme values of any kind, compared as given: the
;; very objects, eq?, so neither is copied or converted.
(test-equal "a setting-mismatch's expected and actual are any Scheme values, the very objects: a number, #t and #f, a list, a symbol, a string"
  '((busy-timeout same same) (foreign-keys same same) (synchronous same same)
    (temp-store same same))
  (map (lambda (fields)
         (built (lambda ()
                  (let ((c (apply make-sqlite-setting-mismatch fields)))
                    (list (sqlite-setting-mismatch-setting c)
                          (if (eq? (sqlite-setting-mismatch-expected c) (cadr fields)) 'same 'differs)
                          (if (eq? (sqlite-setting-mismatch-actual c) (caddr fields)) 'same 'differs))))))
       (list (list 'busy-timeout 2000 0)
             (list 'foreign-keys #t #f)
             (list 'synchronous (list 'normal 1) 'full)
             (list 'temp-store 'memory (string #\f #\i #\l #\e)))))

(test-equal "make-sqlite-setting-mismatch refuses a setting that is no symbol, naming the field and the value by shown-value"
  '((assertion-violation make-sqlite-setting-mismatch (setting (kind string)))
    (assertion-violation make-sqlite-setting-mismatch (setting 5))
    (assertion-violation make-sqlite-setting-mismatch (setting #f))
    (assertion-violation make-sqlite-setting-mismatch (setting (journal-mode)))
    (assertion-violation make-sqlite-setting-mismatch (setting (kind list))))
  (list (raised (lambda () (make-sqlite-setting-mismatch "journal-mode" "wal" "memory")))
        (raised (lambda () (make-sqlite-setting-mismatch 5 "wal" "memory")))
        (raised (lambda () (make-sqlite-setting-mismatch #f "wal" "memory")))
        (raised (lambda () (make-sqlite-setting-mismatch '(journal-mode) "wal" "memory")))
        (raised (lambda () (make-sqlite-setting-mismatch (list secret) "wal" "memory")))))

(define setting-mismatch-accessors
  (list (cons 'sqlite-setting-mismatch-setting sqlite-setting-mismatch-setting)
        (cons 'sqlite-setting-mismatch-expected sqlite-setting-mismatch-expected)
        (cons 'sqlite-setting-mismatch-actual sqlite-setting-mismatch-actual)))

(test-equal "each setting-mismatch accessor refuses an sqlite-error, a closed, a transaction-ended, the root, a string by its kind, a number and a list holding a string, from the accessor"
  (map (lambda (a)
         (list (refusal (car a) '(kind other))
               (refusal (car a) '(kind other))
               (refusal (car a) '(kind other))
               (refusal (car a) '(kind other))
               (refusal (car a) '(kind string))
               (refusal (car a) 5)
               (refusal (car a) '(kind list))))
       setting-mismatch-accessors)
  (map (lambda (a)
         (map (lambda (v) (raised (lambda () ((cdr a) v))))
              (list (an-sqlite-error) (a-closed) (a-transaction-ended) (make-chez-sqlite3-error)
                    secret 5 (list "u" secret))))
       setting-mismatch-accessors))

(test-equal "no setting-mismatch accessor prints the secret it refused, bare, in a list or in a vector"
  (map (lambda (a) '(absent absent absent)) setting-mismatch-accessors)
  (map (lambda (a)
         (map (lambda (v)
                (let ((text (guard (e (#t (describe e)))
                              ((cdr a) v)
                              'no-raise)))
                  (cond ((eq? text 'no-raise) 'no-raise)
                        ((contains? text secret) 'printed)
                        (else 'absent))))
              (list secret (list "u" secret) (vector secret))))
       setting-mismatch-accessors))

;; m3-compound : (-> Any) -> Any
;; What THUNK raised, as the whole compound: matrix-kinds, its who, whether
;; it has a message and irritants (never the text), and, for a
;; setting-mismatch, its three fields; an assertion violation as
;; (assertion-violation WHO IRRITANTS); or no-raise.
(define (m3-compound thunk)
  (guard (e ((chez-sqlite3-error? e)
             (append (list (matrix-kinds e)
                           (and (who-condition? e) (condition-who e))
                           (if (message-condition? e) 'message 'no-message)
                           (if (irritants-condition? e) 'irritants 'no-irritants))
                     (if (sqlite-setting-mismatch? e)
                         (list (sqlite-setting-mismatch-setting e)
                               (sqlite-setting-mismatch-expected e)
                               (sqlite-setting-mismatch-actual e))
                         '())))
            ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other-raise (describe e))))
    (thunk)
    'no-raise))

(test-equal "raise-setting-mismatch raises the whole condition: a setting-mismatch from the who given, with a message, no irritants, its setting, expected and actual"
  '((#t #f #t #f #f #f #f #f #f #t #f #f #f #f #f) open-database message no-irritants
    busy-timeout 1500 0)
  (m3-compound (lambda () (raise-setting-mismatch 'open-database 'busy-timeout 1500 0))))

(test-equal "raise-setting-mismatch refuses a who that is no symbol, before it checks the setting, and a setting the constructor refuses, from the constructor"
  '((assertion-violation raise-setting-mismatch (who (kind string)))
    (assertion-violation raise-setting-mismatch (who 5))
    (assertion-violation raise-setting-mismatch (who (kind string)))
    (assertion-violation make-sqlite-setting-mismatch (setting (kind string))))
  (list (m3-compound (lambda () (raise-setting-mismatch "open-database" 'busy-timeout 1 0)))
        (m3-compound (lambda () (raise-setting-mismatch 5 'busy-timeout 1 0)))
        (m3-compound (lambda () (raise-setting-mismatch "w" "busy-timeout" 1 0)))
        (m3-compound (lambda () (raise-setting-mismatch 'w "busy-timeout" 1 0)))))

(test-equal "an sqlite-transaction-ended is a chez-sqlite3-error of its own type alone, with no fields"
  '(#t #f #t #f #f #f #f #f #f #f #t #f #f #f #f)
  (let ((c (built a-transaction-ended)))
    (if (condition? c) (matrix-kinds c) c)))

(test-equal "raise-transaction-ended raises the whole condition: a transaction-ended from the who given, with a message and no irritants"
  '((#t #f #t #f #f #f #f #f #f #f #t #f #f #f #f) with-transaction message no-irritants)
  (m3-compound (lambda () (raise-transaction-ended 'with-transaction))))

(test-equal "raise-transaction-ended refuses a who that is no symbol"
  '((assertion-violation raise-transaction-ended (who (kind string)))
    (assertion-violation raise-transaction-ended (who 5))
    (assertion-violation raise-transaction-ended (who #f)))
  (list (m3-compound (lambda () (raise-transaction-ended "with-transaction")))
        (m3-compound (lambda () (raise-transaction-ended 5)))
        (m3-compound (lambda () (raise-transaction-ended #f)))))

(test-equal "neither M3 raise helper returns: a handler that returns gets the &non-continuable R6RS raises for it"
  '(non-continuable non-continuable)
  (map (lambda (thunk)
         (guard (e ((non-continuable-violation? e) 'non-continuable)
                   (#t (list 'other-raise (describe e))))
           (with-exception-handler (lambda (c) 'handled) thunk)
           'returned-normally))
       (list (lambda () (raise-setting-mismatch 'w 'busy-timeout 1 0))
             (lambda () (raise-transaction-ended 'w)))))

;; --- M4 slice 1: &sqlite-extensions-unavailable (ADR-0021, decision 10) -------------------
;; Its kinds against every other type are held in the matrix above, and its
;; parent and its fields with the other types'.

(test-equal "an sqlite-extensions-unavailable is a chez-sqlite3-error of its own type alone, with no fields: neither an sqlite-error nor a library-unavailable"
  '(#t #f #t #f #f #f #f #f #f #f #f #t #f #f #f)
  (let ((c (built an-extensions-unavailable)))
    (if (condition? c) (matrix-kinds c) c)))

(test-equal "raise-extensions-unavailable raises the whole condition: an extensions-unavailable from the who given, with a message and no irritants"
  '((#t #f #t #f #f #f #f #f #f #f #f #t #f #f #f) open-database message no-irritants)
  (m3-compound (lambda () (raise-extensions-unavailable 'open-database))))

(test-equal "raise-extensions-unavailable names the who it is given: open-database and call-with-database"
  '(open-database call-with-database)
  (map (lambda (who)
         (let ((c (m3-compound (lambda () (raise-extensions-unavailable who)))))
           (if (and (list? c) (> (length c) 1)) (cadr c) c)))
       '(open-database call-with-database)))

;; simple-kinds : (-> Any) -> Any
;; The simple conditions of what THUNK raised, each by its kind, in order;
;; (other-raise TEXT) for a raise that is no condition, or no-raise.
(define (simple-kinds thunk)
  (guard (e ((condition? e)
             (map (lambda (s)
                    (cond ((sqlite-extensions-unavailable? s) 'extensions-unavailable)
                          ((who-condition? s) 'who)
                          ((message-condition? s) 'message)
                          ((irritants-condition? s) 'irritants)
                          (else 'other)))
                  (simple-conditions e)))
            (#t (list 'other-raise (describe e))))
    (thunk)
    'no-raise))

(test-equal "raise-extensions-unavailable's condition is exactly three simple conditions: the type, its &who and its &message, nothing else"
  '(extensions-unavailable who message)
  (simple-kinds (lambda () (raise-extensions-unavailable 'open-database))))

;; message-of : (-> Any) -> Any
;; The &message text of what THUNK raised, for comparing two raises, never
;; with a text of the suite's; (no-message TEXT) or no-raise.
(define (message-of thunk)
  (guard (e ((message-condition? e) (condition-message e))
            (#t (list 'no-message (describe e))))
    (thunk)
    'no-raise))

(test-equal "raise-extensions-unavailable's message is fixed: the same string from each open verb"
  'same
  (let* ((a (message-of (lambda () (raise-extensions-unavailable 'open-database))))
         (b (message-of (lambda () (raise-extensions-unavailable 'call-with-database)))))
    (if (and (string? a) (string? b) (string=? a b)) 'same (list 'differs a b))))

;; Each raise helper whose &message is fixed: the message is all a fieldless
;; type carries beside its who. raise-library-unavailable and
;; raise-sqlite-error carry the caller's text instead.
(define fixed-message-raises
  (list (cons 'raise-invalid-text (lambda () (raise-invalid-text 'w 1 2)))
        (cons 'raise-wrong-thread (lambda () (raise-wrong-thread 'w 1 2)))
        (cons 'raise-closed (lambda () (raise-closed 'w)))
        (cons 'raise-setting-mismatch (lambda () (raise-setting-mismatch 'w 'busy-timeout 1 0)))
        (cons 'raise-transaction-ended (lambda () (raise-transaction-ended 'w)))
        (cons 'raise-extensions-unavailable (lambda () (raise-extensions-unavailable 'w)))))

;; message-shape : Any -> Any
;; text for a string that is not empty, empty for "", else what message-of
;; answered; the text itself is never read.
(define (message-shape m)
  (cond ((and (string? m) (> (string-length m) 0)) 'text)
        ((string? m) 'empty)
        (else (list 'no-text m))))

(test-equal "each fixed &message is a string, not empty, and its helper's own: no other raise helper's is equal to it, so neither raise-extensions-unavailable's nor raise-transaction-ended's is none or another type's, never compared with a text of the suite's"
  (map (lambda (r) (list (car r) 'text 'its-own)) fixed-message-raises)
  (let ((messages (map (lambda (r) (cons (car r) (message-of (cdr r)))) fixed-message-raises)))
    (map (lambda (m)
           (let ((same (filter (lambda (o) (and (not (eq? (car o) (car m))) (equal? (cdr o) (cdr m))))
                               messages)))
             (list (car m) (message-shape (cdr m))
                   (if (null? same) 'its-own (cons 'shared-with (map car same))))))
         messages)))

(test-equal "raise-extensions-unavailable refuses a who that is no symbol, naming it by shown-value"
  '((assertion-violation raise-extensions-unavailable (who (kind string)))
    (assertion-violation raise-extensions-unavailable (who 5))
    (assertion-violation raise-extensions-unavailable (who #f)))
  (list (m3-compound (lambda () (raise-extensions-unavailable "open-database")))
        (m3-compound (lambda () (raise-extensions-unavailable 5)))
        (m3-compound (lambda () (raise-extensions-unavailable #f)))))

(test-equal "raise-extensions-unavailable never returns: a handler that returns gets the &non-continuable R6RS raises for it"
  'non-continuable
  (guard (e ((non-continuable-violation? e) 'non-continuable)
            (#t (list 'other-raise (describe e))))
    (with-exception-handler (lambda (c) 'handled)
                            (lambda () (raise-extensions-unavailable 'open-database)))
    'returned-normally))

(test-equal "every accessor of another type refuses an extensions-unavailable, from the accessor, by its kind: it carries no field of &sqlite-error's, &sqlite-library-unavailable's, &sqlite-wrong-thread's, &sqlite-invalid-text's or &sqlite-setting-mismatch's"
  (map (lambda (a) (refusal (car a) '(kind other)))
       (append lib-accessors new-accessors invalid-text-accessors setting-mismatch-accessors))
  (map (lambda (a) (raised (lambda () ((cdr a) (an-extensions-unavailable)))))
       (append lib-accessors new-accessors invalid-text-accessors setting-mismatch-accessors)))

(test-end "conditions")

(exit (suite-exit-status runner))
