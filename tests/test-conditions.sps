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
        (srfi :64)
        (chez-sqlite3-testing)
        (chez-sqlite3 private libsqlite3-info)
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

(test-begin "conditions")

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

(test-end "conditions")

(exit (suite-exit-status runner))
