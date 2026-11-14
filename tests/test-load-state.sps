#!r6rs
;;; The suite for (chez-sqlite3 private load-state): the load's first failure,
;;; kept for the life of the process, and load-step, which records it.
;;;
;;; The state is the process's own, so the tests run in order and build on
;;; each other: nothing recorded, then a first failure, then later ones that
;;; must not replace it.
;;;
;;; Each expected value is one the code under test cannot produce by
;;; failing, and none is #f: SRFI-64 makes #f of a raise in the actual
;;; expression. A library body that raises is reached only through eval,
;;; since a guard in a program cannot catch a raise from an imported
;;; library's body (AGENTS.md).
(import (rnrs)
        (srfi :64)
        (only (chezscheme) eval environment interaction-environment)
        (chez-sqlite3-testing)
        (chez-sqlite3 private conditions)
        (chez-sqlite3 private load-state))

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

;; caught : (-> Any) -> Any
;; What THUNK raised, or the symbol no-raise.
(define (caught thunk)
  (guard (e (#t e))
    (thunk)
    'no-raise))

(define (recorded) (if (load-failure) 'recorded 'none))

;; made-serious : Any -> Any
;; For a condition as-serious made of something else: whether it is
;; serious, an error and a chez-sqlite3-error, its who, and its irritants.
(define (made-serious c)
  (if (condition? c)
      (list (serious-condition? c) (error? c) (chez-sqlite3-error? c)
            (and (who-condition? c) (condition-who c))
            (and (irritants-condition? c) (condition-irritants c)))
      (list 'not-a-condition c)))

(test-begin "load-state")

(test-equal "nothing is recorded at first"
  'none
  (recorded))

(test-equal "load-step answers its expression's value, and records nothing"
  '(42 none)
  (let ((value (load-step (+ 40 2))))
    (list value (recorded))))

;; --- as-serious --------------------------------------------------------------------

(test-equal "as-serious answers a serious condition itself"
  '(same same same same)
  (map (lambda (c) (if (eq? (as-serious c) c) 'same 'different))
       (list (make-serious-condition) (make-error) (make-assertion-violation)
             (condition (make-error) (make-message-condition "refused")))))

(test-equal "as-serious makes a symbol or a number a chez-sqlite3-error from chez-sqlite3, carrying it"
  '((#t #t #t chez-sqlite3 (boom)) (#t #t #t chez-sqlite3 (42)))
  (map (lambda (obj) (made-serious (as-serious obj))) '(boom 42)))

(test-equal "as-serious makes #f, a string, a list and () such an error too, carrying each as its one irritant"
  '((#t #t #t chez-sqlite3 (#f)) (#t #t #t chez-sqlite3 ("text"))
    (#t #t #t chez-sqlite3 ((1 2))) (#t #t #t chez-sqlite3 (())))
  (map (lambda (obj) (made-serious (as-serious obj))) (list #f "text" '(1 2) '())))

(test-equal "as-serious makes a warning or a bare message an error, carrying it"
  '(carried carried)
  (map (lambda (c)
         (let ((made (as-serious c)))
           (if (and (serious-condition? made) (chez-sqlite3-error? made)
                    (irritants-condition? made)
                    (equal? (condition-irritants made) (list c)))
               'carried
               (made-serious made))))
       (list (make-warning) (make-message-condition "not serious"))))

(test-equal "as-serious gives a non-serious condition that has its own who the who chez-sqlite3, whatever it held, and carries it"
  '((chez-sqlite3 carried) (chez-sqlite3 carried))
  (map (lambda (c)
         (let ((made (as-serious c)))
           (list (and (who-condition? made) (condition-who made))
                 (if (and (irritants-condition? made) (equal? (condition-irritants made) (list c)))
                     'carried
                     'not-carried))))
       (list (condition (make-warning) (make-who-condition 'someone-else))
             (make-who-condition 'someone-else))))

;; --- recording -------------------------------------------------------------------

;; first : Any
;; What load-step raised for a symbol: the load's first failure from here on.
(define first (caught (lambda () (load-step (raise 'boom)))))

(test-equal "load-step raises a symbol made serious, carrying it"
  '(#t #t #t chez-sqlite3 (boom))
  (made-serious first))

(test-equal "load-step records what it raised"
  'recorded-what-was-raised
  (if (eq? (load-failure) first) 'recorded-what-was-raised (recorded)))

;; later-failures : -> (Listof Condition)
;; Later failures, a plain error and a refusal among them: neither replaces
;; the first. A fresh one is made for each row.
(define (later-failures)
  (list (make-error) (make-sqlite-library-unavailable 'not-found #f #f #f '() #f)))

(test-equal "a later load-step raises its own serious condition, unchanged, and the first stays recorded, whether the later one is a plain error or a refusal"
  '((raised-itself first-kept) (raised-itself first-kept))
  (map (lambda (later)
         (let ((raised (caught (lambda () (load-step (raise later))))))
           (list (if (eq? raised later) 'raised-itself 'raised-something-else)
                 (if (eq? (load-failure) first) 'first-kept 'replaced))))
       (later-failures)))

(test-equal "record-load-failure! keeps the first failure, and raises nothing, for a later plain error and a later refusal"
  '((no-raise first-kept) (no-raise first-kept))
  (map (lambda (later)
         (let* ((result (caught (lambda () (record-load-failure! later))))
                (kept (if (eq? (load-failure) first) 'first-kept 'replaced)))
           (list (if (eq? result 'no-raise) 'no-raise result) kept)))
       (later-failures)))

(test-equal "record-load-failure! refuses a condition that is not serious"
  'refused
  (let ((raised (caught (lambda () (record-load-failure! (make-warning))))))
    (if (and (assertion-violation? raised) (who-condition? raised)
             (eq? (condition-who raised) 'record-load-failure!))
        'refused
        (if (condition? raised) (describe raised) raised))))

;; A handler that returns must not make load-step return: a failure is raised,
;; never continued. With raise-continuable, load-step would answer the
;; handler's value, and the load would go on as if it had succeeded.
(test-equal "load-step raises its failure, not continuably: a handler that returns gets nothing back, and the raise goes on to the next handler"
  'raised-on
  (guard (e (#t 'raised-on))
    (with-exception-handler
     (lambda (c) 'handled)
     (lambda () (load-step (raise 'boom-continued))))
    'returned-normally))

;; --- a library body that raises -----------------------------------------------------
;; Chez runs a library body that raised a serious condition again at the
;; next reference, and wedges one that raised anything else: every later
;; reference raises "cyclic dependency involving invocation of library".
;; Each library below is defined here with eval, and referenced twice.

(define (string-prefix? prefix s)
  (and (>= (string-length s) (string-length prefix))
       (string=? (substring s 0 (string-length prefix)) prefix)))

;; reference : (Listof Symbol) -> Any
;; What a reference to the library NAME's export v did: wedged, a serious
;; condition raised (the body ran again), the symbol it raised, or no-raise.
(define (reference name)
  (guard (e ((and (message-condition? e)
                  (string-prefix? "cyclic dependency" (condition-message e)))
             'wedged)
            ((serious-condition? e) 'raised-serious)
            ((symbol? e) (list 'raised e))
            (#t (list 'other (describe e))))
    (eval 'v (environment name))
    'no-raise))

;; twice : (Listof Symbol) Any -> (List Any Any)
;; Defines the library NAME, whose one definition is v, as BODY, then
;; references it twice.
(define (twice name body)
  (eval `(library ,name
           (export v)
           (import (rnrs) (chez-sqlite3 private load-state))
           (define v ,body))
        (interaction-environment))
  (let* ((one (reference name))
         (two (reference name)))
    (list one two)))

(test-equal "Chez wedges a library whose body raised a symbol (the reason for load-step)"
  '((raised boom) wedged)
  (twice '(load-state-fixture bare) '(raise 'boom)))

(test-equal "through load-step, the same raise is serious, so the body runs again, never wedged"
  '(raised-serious raised-serious)
  (twice '(load-state-fixture stepped) '(load-step (raise 'boom))))

(test-equal "through load-step, a raised warning is serious too, never wedged"
  '(raised-serious raised-serious)
  (twice '(load-state-fixture warned) '(load-step (raise (make-warning)))))

(test-end "load-state")

(exit (suite-exit-status runner))
