#!r6rs
;;; The suite for (chez-sqlite3 private transaction-plan): the pure core of
;;; with-transaction (ADR-0017). It loads no libsqlite3: the library holds no
;;; foreign code, and the shell that runs the statements, keeps the flags and
;;; reads autocommit is M3 slice 4's.
;;;
;;;   the mode         deferred, immediate or exclusive; anything else
;;;                    refused, every name (chezscheme) exports among it
;;;   the begin        from autocommit, the connection's depth and the mode,
;;;                    absent among them: BEGIN with the mode, or a savepoint
;;;                    named by the depth, every statement written out here
;;;   the exits        a return, a raise and an escape, by the flags begun
;;;                    and ended and autocommit read after the body, at every
;;;                    level a begin answers, against a model of ADR-0017's
;;;                    decisions 5 to 7 written in this suite
;;;   a failed commit  the level rolled back while it is still there
;;;   the walks        §4.2's cases carried through the plans as slice 4
;;;                    carries the flags
;;;   the refusal      an unknown mode as an assertion violation from WHO
;;;
;;; Every procedure but raise-transaction-refusal answers data and raises
;;; nothing, so every call is made under a guard with a sentinel of its own,
;;; (raised TEXT). No expected value is #f.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) environment environment-symbols library-exports)
        (chez-sqlite3-testing)
        (only (chez-sqlite3 private conditions) shown-value)
        (chez-sqlite3 private transaction-plan))

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

;; --- helpers -----------------------------------------------------------------------------

(define (sorted-names names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

;; mode : Any -> Any
(define (mode m)
  (guard (e (#t (list 'raised (describe e)))) (transaction-mode m)))

;; begin* : Any Any [Any] -> Any
;; begin-plan's answer, with the mode absent when none is given, or (raised TEXT).
(define begin*
  (case-lambda
    ((autocommit depth)
     (guard (e (#t (list 'raised (describe e)))) (begin-plan autocommit depth)))
    ((autocommit depth m)
     (guard (e (#t (list 'raised (describe e)))) (begin-plan autocommit depth m)))))

;; exit* : Any Any Any Any Any -> Any
(define (exit* how begun ended autocommit level)
  (guard (e (#t (list 'raised (describe e)))) (exit-plan how begun ended autocommit level)))

;; failed* : Any Any Any -> Any
(define (failed* ended autocommit level)
  (guard (e (#t (list 'raised (describe e)))) (failed-commit-plan ended autocommit level)))

;; raised : (-> Any) -> Any
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e)
                  (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other (describe e))))
    (list 'no-raise (thunk))))

;; differences : (Listof A) (A -> B) (A -> B) -> (Listof (List A B B))
(define (differences items want got)
  (filter (lambda (row) row)
          (map (lambda (x)
                 (let ((w (want x)) (g (got x)))
                   (and (not (equal? w g)) (list x w g))))
               items)))

;; cross : (Listof A) ... -> (Listof (Listof A))
;; Every combination, one item from each list.
(define (cross . lists)
  (if (null? lists)
      '(())
      (let ((rest (apply cross (cdr lists))))
        (apply append (map (lambda (x) (map (lambda (r) (cons x r)) rest)) (car lists))))))

(define-record-type a-thing (fields x))

;; --- the model, from ADR-0017 -------------------------------------------------------------

;; The statements of ADR-0017's decision 4, written out for a level.
(define (savepoint-name n) (string-append "chez_sqlite3_" (number->string n)))

(define (commit-of level)
  (if (eq? level 'outer)
      '(commit "COMMIT")
      (list 'commit (string-append "RELEASE " (savepoint-name (cadr level))))))

(define (rollback-of level)
  (if (eq? level 'outer)
      '(rollback "ROLLBACK")
      (list 'rollback
            (string-append "ROLLBACK TO " (savepoint-name (cadr level)))
            (string-append "RELEASE " (savepoint-name (cadr level))))))

;; exit-table : (Listof (List Symbol Boolean Boolean Integer Symbol))
;; ADR-0017's decisions 5 to 7 and the plan's §4.2, one row per case: HOW,
;; BEGUN, ENDED, AUTOCOMMIT after the body, and the plan, as a kind. A kind
;; commit is COMMIT or RELEASE for the level, rollback its rollback; the
;; others are the plans themselves.
;;   - ended, a later exit (decision 7): a return is told the transaction
;;     ended, issuing nothing; a raise or an escape does nothing more;
;;   - never begun (decision 5): nothing to roll back, whatever autocommit
;;     says; a return, which the shape never makes, is told it ended;
;;   - begun, not ended, the first exit: a return commits while autocommit is
;;     0 (decision 6), and is told it ended otherwise; a raise or an escape
;;     rolls back while it is 0 (decision 5), and does nothing otherwise.
(define exit-table
  '((return  #t #t 0 transaction-ended) (return  #t #t 1 transaction-ended)
    (raise   #t #t 0 nothing)           (raise   #t #t 1 nothing)
    (escape  #t #t 0 nothing)           (escape  #t #t 1 nothing)
    (return  #f #t 0 transaction-ended) (return  #f #t 1 transaction-ended)
    (raise   #f #t 0 nothing)           (raise   #f #t 1 nothing)
    (escape  #f #t 0 nothing)           (escape  #f #t 1 nothing)
    (return  #f #f 0 transaction-ended) (return  #f #f 1 transaction-ended)
    (raise   #f #f 0 nothing)           (raise   #f #f 1 nothing)
    (escape  #f #f 0 nothing)           (escape  #f #f 1 nothing)
    (return  #t #f 0 commit)            (return  #t #f 1 transaction-ended)
    (raise   #t #f 0 rollback)          (raise   #t #f 1 nothing)
    (escape  #t #f 0 rollback)          (escape  #t #f 1 nothing)))

;; model-exit : Symbol Boolean Boolean Integer Level -> Plan
;; The exit-table's row for the case, its kind made a plan for LEVEL.
(define (model-exit how begun ended autocommit level)
  (let ((row (filter (lambda (r) (equal? (list (car r) (cadr r) (caddr r) (cadddr r))
                                         (list how begun ended autocommit)))
                     exit-table)))
    (if (= (length row) 1)
        (let ((kind (car (cddddr (car row)))))
          (case kind
            ((commit) (commit-of level))
            ((rollback) (rollback-of level))
            (else (list kind))))
        (list 'no-row how begun ended autocommit))))

(test-begin "transaction-plan")

(test-equal "(chez-sqlite3 private transaction-plan) exports exactly the modes, the mode's check, the three plans and the refusal's raise"
  (sorted-names '(transaction-modes transaction-mode begin-plan exit-plan failed-commit-plan
                  raise-transaction-refusal))
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3 private transaction-plan)))))

(test-equal "transaction-modes, written out, in ADR-0017's order"
  '(deferred immediate exclusive)
  transaction-modes)

;; --- the mode ------------------------------------------------------------------------------

(test-equal "each mode is a mode"
  '((mode deferred) (mode immediate) (mode exclusive))
  (map mode '(deferred immediate exclusive)))

(define near-modes
  '(IMMEDIATE Immediate DEFERRED Deferred EXCLUSIVE Exclusive immediately defer exclusively
    begin commit rollback savepoint release nested outer read write read-only exclusive-lock
    shared reserved pending wal default none transaction))

(test-equal "every near name is refused as an unknown mode, naming it"
  (map (lambda (m) (list 'refused 'unknown-mode m)) near-modes)
  (map mode near-modes))

(define chez-names
  (guard (e (#t (list 'raised (describe e))))
    (remp (lambda (s) (memq s '(deferred immediate exclusive)))
          (environment-symbols (environment '(chezscheme))))))

(test-equal "(chezscheme) gives names to refuse, in the hundreds"
  'many
  (if (and (list? chez-names) (> (length chez-names) 500)) 'many chez-names))

(test-equal "every name (chezscheme) exports is refused as an unknown mode, naming it"
  '()
  (if (list? chez-names)
      (differences chez-names (lambda (s) (list 'refused 'unknown-mode s)) mode)
      chez-names))

(test-equal "a mode that is no symbol is refused, named by shown-value: a string by its kind, a list holding one by its kind, a number, a boolean, (), a list of a mode, a vector, a procedure"
  '((refused unknown-mode (kind string)) (refused unknown-mode (kind list))
    (refused unknown-mode 1) (refused unknown-mode #t) (refused unknown-mode #f)
    (refused unknown-mode ()) (refused unknown-mode (immediate)) (refused unknown-mode (kind vector))
    (refused unknown-mode (kind procedure)) (refused unknown-mode (kind other)))
  (map mode (list "immediate" (list "immediate") 1 #t #f '() '(immediate) (vector 'immediate) car
                  (make-a-thing 'immediate))))

;; --- the begin ---------------------------------------------------------------------------

(test-equal "the begin at autocommit 1, at depths 0, 1 and 12, with the mode absent, deferred, immediate and exclusive, written out: BEGIN with the mode, immediate when absent; the depth no part of it"
  '((begin outer "BEGIN IMMEDIATE") (begin outer "BEGIN DEFERRED") (begin outer "BEGIN IMMEDIATE")
    (begin outer "BEGIN EXCLUSIVE")
    (begin outer "BEGIN IMMEDIATE") (begin outer "BEGIN DEFERRED") (begin outer "BEGIN IMMEDIATE")
    (begin outer "BEGIN EXCLUSIVE")
    (begin outer "BEGIN IMMEDIATE") (begin outer "BEGIN DEFERRED") (begin outer "BEGIN IMMEDIATE")
    (begin outer "BEGIN EXCLUSIVE"))
  (apply append
         (map (lambda (depth)
                (list (begin* 1 depth) (begin* 1 depth 'deferred) (begin* 1 depth 'immediate)
                      (begin* 1 depth 'exclusive)))
              '(0 1 12))))

(test-equal "the begin at autocommit 0, at depths 0, 1 and 12, with every mode and none, written out: a savepoint named by the depth, the mode no part of it"
  '((begin (savepoint 0) "SAVEPOINT chez_sqlite3_0") (begin (savepoint 0) "SAVEPOINT chez_sqlite3_0")
    (begin (savepoint 0) "SAVEPOINT chez_sqlite3_0") (begin (savepoint 0) "SAVEPOINT chez_sqlite3_0")
    (begin (savepoint 1) "SAVEPOINT chez_sqlite3_1") (begin (savepoint 1) "SAVEPOINT chez_sqlite3_1")
    (begin (savepoint 1) "SAVEPOINT chez_sqlite3_1") (begin (savepoint 1) "SAVEPOINT chez_sqlite3_1")
    (begin (savepoint 12) "SAVEPOINT chez_sqlite3_12") (begin (savepoint 12) "SAVEPOINT chez_sqlite3_12")
    (begin (savepoint 12) "SAVEPOINT chez_sqlite3_12") (begin (savepoint 12) "SAVEPOINT chez_sqlite3_12"))
  (apply append
         (map (lambda (depth)
                (list (begin* 0 depth) (begin* 0 depth 'deferred) (begin* 0 depth 'immediate)
                      (begin* 0 depth 'exclusive)))
              '(0 1 12))))

(test-equal "a large depth names its savepoint in decimal"
  '((begin (savepoint 1000000) "SAVEPOINT chez_sqlite3_1000000")
    (begin (savepoint 4294967296) "SAVEPOINT chez_sqlite3_4294967296"))
  (list (begin* 0 1000000 'exclusive) (begin* 0 4294967296)))

(test-equal "autocommit is read as C reads an int: 0 is a transaction open, and every other value, 2 and -1 among them, none"
  '((begin outer "BEGIN DEFERRED") (begin outer "BEGIN EXCLUSIVE") (begin outer "BEGIN IMMEDIATE")
    (begin (savepoint 3) "SAVEPOINT chez_sqlite3_3"))
  (list (begin* 2 3 'deferred) (begin* -1 3 'exclusive) (begin* 255 3) (begin* 0 3 'deferred)))

(test-equal "an unknown mode is refused by the begin too, at autocommit 1 and 0, naming it by shown-value"
  '((refused unknown-mode IMMEDIATE) (refused unknown-mode IMMEDIATE)
    (refused unknown-mode (kind string)) (refused unknown-mode #f))
  (list (begin* 1 0 'IMMEDIATE) (begin* 0 2 'IMMEDIATE) (begin* 1 0 "immediate") (begin* 0 0 #f)))

;; --- the exits ---------------------------------------------------------------------------

;; Every begin: autocommit 1 and 0, depths 0, 1 and 12, the mode absent and
;; each of the three. Its level is what the exits are planned for.
(define begins
  (map (lambda (c)
         (let ((b (if (eq? (caddr c) 'absent)
                      (begin* (car c) (cadr c))
                      (begin* (car c) (cadr c) (caddr c)))))
           (cons c b)))
       (cross '(1 0) '(0 1 12) '(absent deferred immediate exclusive))))


;; level-of : (Pairof Any Any) -> Any
;; The level a begin of BEGINS answered: (begin LEVEL STATEMENT)'s LEVEL.
(define (level-of b) (if (and (pair? (cdr b)) (pair? (cddr b))) (cadr (cdr b)) (list 'no-level b)))

(test-equal "24 begins, each answering a level"
  '(24 24)
  (list (length begins)
        (length (filter (lambda (b) (and (pair? (cdr b)) (eq? (cadr b) 'begin))) begins))))

;; Every exit of every begin: a return, a raise and an escape; begun and
;; ended each set or not; autocommit after the body 0 or 1.
(define exits
  (apply append
         (map (lambda (b)
                (map (lambda (e) (cons (level-of b) e))
                     (cross '(return raise escape) '(#t #f) '(#t #f) '(0 1))))
              begins)))

(test-equal "576 exits: 24 begins, 3 ways out, 2 flags and 2 readings of autocommit"
  576
  (length exits))

(test-equal "every exit of every begin is planned as ADR-0017 decides it: no combination differs from the model"
  '()
  (differences exits
               (lambda (x) (apply model-exit (append (cdr x) (list (car x)))))
               (lambda (x) (apply exit* (append (cdr x) (list (car x)))))))

(test-equal "the first exit, begun and not ended, written out for the outer level: a return commits, or is told the transaction ended; a raise and an escape roll back, or do nothing"
  '((commit "COMMIT") (transaction-ended)
    (rollback "ROLLBACK") (nothing)
    (rollback "ROLLBACK") (nothing))
  (list (exit* 'return #t #f 0 'outer) (exit* 'return #t #f 1 'outer)
        (exit* 'raise #t #f 0 'outer) (exit* 'raise #t #f 1 'outer)
        (exit* 'escape #t #f 0 'outer) (exit* 'escape #t #f 1 'outer)))

(test-equal "the first exit, begun and not ended, written out for a savepoint: RELEASE to commit; ROLLBACK TO then RELEASE to roll back"
  '((commit "RELEASE chez_sqlite3_4") (transaction-ended)
    (rollback "ROLLBACK TO chez_sqlite3_4" "RELEASE chez_sqlite3_4") (nothing)
    (rollback "ROLLBACK TO chez_sqlite3_4" "RELEASE chez_sqlite3_4") (nothing))
  (list (exit* 'return #t #f 0 '(savepoint 4)) (exit* 'return #t #f 1 '(savepoint 4))
        (exit* 'raise #t #f 0 '(savepoint 4)) (exit* 'raise #t #f 1 '(savepoint 4))
        (exit* 'escape #t #f 0 '(savepoint 4)) (exit* 'escape #t #f 1 '(savepoint 4))))

(test-equal "a later exit, ended set, issues nothing at either level and either autocommit: a return is told the transaction ended, a raise and an escape do nothing more"
  '((transaction-ended) (transaction-ended) (transaction-ended) (transaction-ended)
    (nothing) (nothing) (nothing) (nothing) (nothing) (nothing) (nothing) (nothing))
  (append (map (lambda (l a) (exit* 'return #t #t a l)) '(outer outer (savepoint 1) (savepoint 1)) '(0 1 0 1))
          (map (lambda (l a) (exit* 'raise #t #t a l)) '(outer outer (savepoint 1) (savepoint 1)) '(0 1 0 1))
          (map (lambda (l a) (exit* 'escape #t #t a l)) '(outer outer (savepoint 1) (savepoint 1)) '(0 1 0 1))))

(test-equal "an exit before the begin answered, begun not set, rolls nothing back, even at autocommit 0 inside the caller's transaction; a return there is told the transaction ended, never committed"
  '((nothing) (nothing) (nothing) (nothing) (transaction-ended) (transaction-ended))
  (list (exit* 'escape #f #f 0 'outer) (exit* 'raise #f #f 0 '(savepoint 2))
        (exit* 'escape #f #f 1 '(savepoint 2)) (exit* 'raise #f #f 1 'outer)
        (exit* 'return #f #f 0 'outer) (exit* 'return #f #f 0 '(savepoint 2))))

(test-equal "only a return commits: any other way out named, a misspelt return among them, is planned as a raise"
  '((rollback "ROLLBACK") (rollback "ROLLBACK") (rollback "ROLLBACK") (rollback "ROLLBACK"))
  (list (exit* 'retrun #t #f 0 'outer) (exit* #f #t #f 0 'outer) (exit* "return" #t #f 0 'outer)
        (exit* 'engine-expired #t #f 0 'outer)))

(test-equal "autocommit after the body is read as C reads an int: only 0 keeps the level there"
  '((transaction-ended) (transaction-ended) (nothing) (commit "RELEASE chez_sqlite3_0"))
  (list (exit* 'return #t #f 2 'outer) (exit* 'return #t #f -1 '(savepoint 0))
        (exit* 'raise #t #f 2 '(savepoint 0)) (exit* 'return #t #f 0 '(savepoint 0))))

;; --- a failed commit ---------------------------------------------------------------------

(test-equal "a commit or release that fails with its level still there, autocommit 0, rolls the level back; with it gone, it issues nothing; its failure is raised after either"
  '((rollback "ROLLBACK") (nothing) (nothing)
    (rollback "ROLLBACK TO chez_sqlite3_0" "RELEASE chez_sqlite3_0") (nothing)
    (rollback "ROLLBACK TO chez_sqlite3_1" "RELEASE chez_sqlite3_1") (nothing)
    (rollback "ROLLBACK TO chez_sqlite3_12" "RELEASE chez_sqlite3_12") (nothing))
  (list (failed* #f 0 'outer) (failed* #f 1 'outer) (failed* #f 2 'outer)
        (failed* #f 0 '(savepoint 0)) (failed* #f 1 '(savepoint 0))
        (failed* #f 0 '(savepoint 1)) (failed* #f 1 '(savepoint 1))
        (failed* #f 0 '(savepoint 12)) (failed* #f 1 '(savepoint 12))))

(test-equal "a failed commit whose level already ended, ended set, issues nothing at either level and any autocommit, 0 included: never a second rollback"
  '((nothing) (nothing) (nothing) (nothing) (nothing) (nothing) (nothing) (nothing))
  (append (map (lambda (l) (failed* #t 0 l)) '(outer (savepoint 0) (savepoint 1) (savepoint 12)))
          (map (lambda (l) (failed* #t 1 l)) '(outer (savepoint 0) (savepoint 1) (savepoint 12)))))

(test-equal "a failed commit's rollback is the raise's rollback at the same level, for every begin"
  '()
  (differences begins
               (lambda (b) (exit* 'raise #t #f 0 (level-of b)))
               (lambda (b) (failed* #f 0 (level-of b)))))

;; --- the walks ---------------------------------------------------------------------------

;; walk : Any Natural Any (Listof (U (List 'leave Symbol Integer) (List 'commit-fails Integer)))
;;        -> (Listof Any)
;; with-transaction carried through the plans as M3 slice 4 keeps its flags:
;; the begin answered sets begun; a commit that succeeds, a failed commit's
;; plan carried out, and the after thunk's plan for a raise or an escape,
;; whatever it issued, set ended. Each event is an
;; exit, (leave HOW AUTOCOMMIT), its way out and autocommit after the body,
;; or the commit just planned failing, with autocommit after it. The tag is
;; leave, never exit: make check-suites reads every datum, and refuses one
;; shaped as an exit form. The answer is every plan, in
;; order.
(define (walk autocommit depth m events)
  (let* ((b (if m (begin* autocommit depth m) (begin* autocommit depth)))
         (level (if (and (pair? b) (pair? (cdr b))) (cadr b) (list 'no-level b))))
    (let loop ((events events) (begun #t) (ended #f) (out (list b)))
      (if (null? events)
          (reverse out)
          (let ((ev (car events)))
            (case (car ev)
              ((leave)
               (let ((p (exit* (cadr ev) begun ended (caddr ev) level)))
                 (loop (cdr events) begun
                       (cond ((not (eq? (cadr ev) 'return)) #t)
                             ((and (pair? p) (eq? (car p) 'commit))
                              (not (and (pair? (cdr events))
                                        (eq? (car (cadr events)) 'commit-fails))))
                             (else ended))
                       (cons p out))))
              ((commit-fails)
               (loop (cdr events) begun #t (cons (failed* ended (cadr ev) level) out)))
              (else (reverse (cons (list 'bad-event ev) out)))))))))

(test-equal "a body that returns: BEGIN IMMEDIATE, then COMMIT"
  '((begin outer "BEGIN IMMEDIATE") (commit "COMMIT"))
  (walk 1 0 #f '((leave return 0))))

(test-equal "a continuation called after the commit makes the body return again: transaction-ended, and no second COMMIT"
  '((begin outer "BEGIN DEFERRED") (commit "COMMIT") (transaction-ended) (transaction-ended))
  (walk 1 0 'deferred '((leave return 0) (leave return 1) (leave return 0))))

(test-equal "a body resumed past a guard that re-entered: its raise rolled back, its later statements autocommitted, and its return is told the transaction ended"
  '((begin (savepoint 2) "SAVEPOINT chez_sqlite3_2")
    (rollback "ROLLBACK TO chez_sqlite3_2" "RELEASE chez_sqlite3_2")
    (nothing) (transaction-ended))
  (walk 0 2 'immediate '((leave raise 0) (leave raise 0) (leave return 0))))

(test-equal "an engine's expiry after the begin is an escape that rolls back; the resumed body's return is told the transaction ended"
  '((begin outer "BEGIN EXCLUSIVE") (rollback "ROLLBACK") (transaction-ended))
  (walk 1 5 'exclusive '((leave escape 0) (leave return 0))))

(test-equal "a commit that fails with the transaction open is rolled back, then raised; the raise on the way out does nothing more"
  '((begin outer "BEGIN IMMEDIATE") (commit "COMMIT") (rollback "ROLLBACK") (nothing))
  (walk 1 0 'immediate '((leave return 0) (commit-fails 0) (leave raise 0))))

(test-equal "a release that fails with its savepoint open, as a sticky interrupt makes one, is rolled back; one that fails with the transaction gone issues nothing"
  '(((begin (savepoint 1) "SAVEPOINT chez_sqlite3_1") (commit "RELEASE chez_sqlite3_1")
     (rollback "ROLLBACK TO chez_sqlite3_1" "RELEASE chez_sqlite3_1") (nothing))
    ((begin (savepoint 1) "SAVEPOINT chez_sqlite3_1") (commit "RELEASE chez_sqlite3_1")
     (nothing) (nothing)))
  (list (walk 0 1 #f '((leave return 0) (commit-fails 0) (leave raise 0)))
        (walk 0 1 #f '((leave return 0) (commit-fails 1) (leave raise 1)))))

(test-equal "a raise whose failure ended the transaction issues nothing, and a return after it is told so"
  '((begin outer "BEGIN IMMEDIATE") (nothing) (transaction-ended))
  (walk 1 0 #f '((leave raise 1) (leave return 1))))

;; --- every statement ------------------------------------------------------------------------

;; The statements of every plan above, and of the begins: each is one of
;; ADR-0017's decision 4, written out, for depths 0, 1 and 12.
(define every-statement
  (append '("BEGIN DEFERRED" "BEGIN IMMEDIATE" "BEGIN EXCLUSIVE" "COMMIT" "ROLLBACK")
          (apply append
                 (map (lambda (n)
                        (list (string-append "SAVEPOINT chez_sqlite3_" n)
                              (string-append "RELEASE chez_sqlite3_" n)
                              (string-append "ROLLBACK TO chez_sqlite3_" n)))
                      '("0" "1" "12")))))

(define (statements-of plan)
  (cond ((not (pair? plan)) (list (list 'not-a-plan plan)))
        ((eq? (car plan) 'begin) (cddr plan))
        (else (cdr plan))))

(test-equal "every statement every plan issues is one of ADR-0017's, and each of them is issued by some plan"
  (list '() (length every-statement))
  (let ((issued (apply append
                       (map statements-of
                            (append (map cdr begins)
                                    (map (lambda (x) (apply exit* (append (cdr x) (list (car x)))))
                                         exits)
                                    (map (lambda (b) (failed* #f 0 (level-of b))) begins))))))
    (list (filter (lambda (s) (not (member s every-statement))) issued)
          (length (filter (lambda (s) (member s issued)) every-statement)))))

;; --- raise-transaction-refusal -------------------------------------------------------------

(test-equal "raise-transaction-refusal raises an unknown mode's refusal as an assertion violation from WHO, its irritants the rule and the mode as shown"
  '((assertion-violation with-transaction (unknown-mode IMMEDIATE))
    (assertion-violation with-transaction (unknown-mode (kind string)))
    (assertion-violation with-transaction (unknown-mode #f)))
  (list (raised (lambda () (raise-transaction-refusal 'with-transaction (mode 'IMMEDIATE))))
        (raised (lambda () (raise-transaction-refusal 'with-transaction (mode "Pr0xyS3cr3t"))))
        (raised (lambda () (raise-transaction-refusal 'with-transaction (begin* 1 0 #f))))))

(test-equal "raise-transaction-refusal's raise is no continuable one"
  'non-continuable
  (guard (e ((non-continuable-violation? e) 'non-continuable)
            (#t (list 'other (describe e))))
    (with-exception-handler
     (lambda (c) 'handler-returned)
     (lambda () (raise-transaction-refusal 'with-transaction (mode 'nosuch)) 'returned))))

(test-equal "raise-transaction-refusal refuses a WHO that is no symbol, first, and what is no refusal, each named by shown-value"
  '((assertion-violation raise-transaction-refusal (who (kind string)))
    (assertion-violation raise-transaction-refusal (who 5))
    (assertion-violation raise-transaction-refusal (not-a-refusal (mode immediate)))
    (assertion-violation raise-transaction-refusal (not-a-refusal stub))
    (assertion-violation raise-transaction-refusal (not-a-refusal (refused)))
    (assertion-violation raise-transaction-refusal (not-a-refusal (refused unknown-setting x)))
    (assertion-violation raise-transaction-refusal (not-a-refusal (refused unknown-mode)))
    (assertion-violation raise-transaction-refusal (not-a-refusal (kind list))))
  (list (raised (lambda () (raise-transaction-refusal "with-transaction" (mode 'nosuch))))
        (raised (lambda () (raise-transaction-refusal 5 'stub)))
        (raised (lambda () (raise-transaction-refusal 'with-transaction (mode 'immediate))))
        (raised (lambda () (raise-transaction-refusal 'with-transaction 'stub)))
        (raised (lambda () (raise-transaction-refusal 'with-transaction '(refused))))
        (raised (lambda () (raise-transaction-refusal 'with-transaction '(refused unknown-setting x))))
        (raised (lambda () (raise-transaction-refusal 'with-transaction '(refused unknown-mode))))
        (raised (lambda () (raise-transaction-refusal 'with-transaction
                                                      '(refused unknown-mode x . y))))))

(test-equal "raise-transaction-refusal raises from the WHO it is given, and refuses a refusal with a detail too many"
  '((assertion-violation a-caller (unknown-mode x))
    (assertion-violation raise-transaction-refusal (not-a-refusal (refused unknown-mode x y))))
  (list (raised (lambda () (raise-transaction-refusal 'a-caller (mode 'x))))
        (raised (lambda () (raise-transaction-refusal 'with-transaction '(refused unknown-mode x y))))))

;; --- total ----------------------------------------------------------------------------

(define junk (list #t #f 0 1 -1 2.5 'outer 'return "x" '() '(savepoint) '(savepoint x) (vector)
                   car (make-a-thing 1)))

(test-equal "the mode's check and the begin raise nothing for any mode, and the plans nothing for any exit, flags or autocommit at every level"
  '()
  (filter (lambda (r) (and (pair? r) (eq? (car r) 'raised)))
          (append (map mode junk)
                  (map (lambda (j) (begin* 1 0 j)) junk)
                  (map (lambda (j) (begin* 0 3 j)) junk)
                  (map (lambda (j) (begin* j 0)) junk)
                  (apply append
                         (map (lambda (j)
                                (apply append
                                       (map (lambda (l)
                                              (list (exit* j j j j l) (exit* 'return #t #f j l)
                                                    (exit* 'raise #t #f j l) (exit* j #t #f 0 l)
                                                    (failed* j j l) (failed* #f j l)))
                                            '(outer (savepoint 0) (savepoint 7)))))
                              junk)))))

(test-end "transaction-plan")

(exit (suite-exit-status runner))
