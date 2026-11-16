#!r6rs
;;; (chez-sqlite3 private transaction-plan): the pure core of with-transaction
;;; (ADR-0017). Data in, data out: no foreign code, and nothing here loads
;;; libsqlite3.
;;;
;;;   transaction-mode           a mode checked, before anything reaches C
;;;   begin-plan                 from autocommit, the connection's depth and
;;;                              the mode, the level and its statement
;;;   exit-plan                  from the way out, the flags begun and ended
;;;                              and autocommit read after the body, what to
;;;                              issue or raise
;;;   failed-commit-plan         a COMMIT or RELEASE that failed: the level
;;;                              rolled back while it is still there
;;;   raise-transaction-refusal  an unknown mode as an assertion violation
;;;
;;; A level is outer, a transaction this level began with BEGIN, or
;;; (savepoint N), one it began with SAVEPOINT chez_sqlite3_N inside a
;;; transaction already open. Its statements (ADR-0017, decision 4):
;;;
;;;   level           begin                   commit                  roll back
;;;   outer           BEGIN DEFERRED,         COMMIT                  ROLLBACK
;;;                   IMMEDIATE or EXCLUSIVE
;;;   (savepoint N)   SAVEPOINT chez_sqlite3_N  RELEASE chez_sqlite3_N  ROLLBACK TO chez_sqlite3_N,
;;;                                                                   then RELEASE chez_sqlite3_N
;;;
;;; Autocommit is read as C reads sqlite3_get_autocommit's int: 0 is a
;;; transaction open, every other value none. It is the one test of whether a
;;; level is still there (ADR-0017's context), for a savepoint as for the
;;; outer level.
;;;
;;; Each procedure but raise-transaction-refusal answers data for any argument
;;; of its stated type and raises nothing, so slice 4 may call any of them
;;; inside a critical section; raise-transaction-refusal is called after it.
(library (chez-sqlite3 private transaction-plan)
  (export transaction-modes transaction-mode begin-plan exit-plan failed-commit-plan
          raise-transaction-refusal)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (only (chez-sqlite3 private conditions) shown-value))

  ;; transaction-modes : (Listof Symbol)
  ;; with-transaction's modes, in ADR-0017's order.
  (define transaction-modes '(deferred immediate exclusive))

  ;; begin-statements : (Listof (Pairof Symbol String))
  (define begin-statements
    '((deferred . "BEGIN DEFERRED") (immediate . "BEGIN IMMEDIATE") (exclusive . "BEGIN EXCLUSIVE")))

  ;; transaction-mode : Any -> (U (List 'mode Mode) Mode-Refusal)
  ;; Mode = (U 'deferred 'immediate 'exclusive)
  ;; Mode-Refusal = (List 'refused 'unknown-mode Any)
  ;; M, a mode: (mode M) when it is one of transaction-modes, else
  ;; (refused unknown-mode V), V by shown-value. Total.
  (define (transaction-mode m)
    (if (memq m transaction-modes)
        (list 'mode m)
        (list 'refused 'unknown-mode (shown-value m))))

  ;; savepoint : Natural -> String
  ;; The name of the savepoint at depth N: chez_sqlite3_N, N in decimal, an
  ;; ASCII identifier that needs no quoting.
  (define (savepoint n) (string-append "chez_sqlite3_" (number->string n)))

  ;; begin-plan : (case-> (Any Natural -> Begin) (Any Natural Any -> (U Begin Mode-Refusal)))
  ;; Begin = (List 'begin Level String)
  ;; Level = (U 'outer (List 'savepoint Natural))
  ;; The level a with-transaction begins, and its statement, from AUTOCOMMIT
  ;; read before it, DEPTH, the levels with-transaction holds open on the
  ;; connection, and the mode, immediate when absent (Q5). At an AUTOCOMMIT
  ;; other than 0: outer, BEGIN with the mode, DEPTH no part of it. At 0:
  ;; (savepoint DEPTH), SAVEPOINT chez_sqlite3_DEPTH, the mode no part of
  ;; it. A mode that is none is refused at either, as transaction-mode
  ;; refuses it.
  (define begin-plan
    (case-lambda
      ((autocommit depth) (begin-plan autocommit depth 'immediate))
      ((autocommit depth m)
       (let ((checked (transaction-mode m)))
         (cond ((eq? (car checked) 'refused) checked)
               ((eqv? autocommit 0)
                (list 'begin (list 'savepoint depth)
                      (string-append "SAVEPOINT " (savepoint depth))))
               (else (list 'begin 'outer (cdr (assq m begin-statements)))))))))

  ;; commit-of : Level -> (List 'commit String)
  (define (commit-of level)
    (if (eq? level 'outer)
        (list 'commit "COMMIT")
        (list 'commit (string-append "RELEASE " (savepoint (cadr level))))))

  ;; rollback-of : Level -> (Pairof 'rollback (Listof String))
  ;; A savepoint is rolled back by ROLLBACK TO, which leaves it open, then
  ;; RELEASE (ADR-0017's context).
  (define (rollback-of level)
    (if (eq? level 'outer)
        (list 'rollback "ROLLBACK")
        (let ((name (savepoint (cadr level))))
          (list 'rollback (string-append "ROLLBACK TO " name) (string-append "RELEASE " name)))))

  ;; exit-plan : Any Any Any Any Level -> Exit-Plan
  ;; Exit-Plan = (U (List 'commit String) Rollback (List 'nothing) (List 'transaction-ended))
  ;; Rollback = (Pairof 'rollback (Listof String))
  ;; What an exit from LEVEL's extent does (ADR-0017, decisions 5 to 7). HOW
  ;; is return for a normal return, and anything else, raise or escape, is a
  ;; raise or an escape: only a return commits. BEGUN and ENDED are the flags,
  ;; set when not #f; AUTOCOMMIT is read after the body.
  ;;   - ENDED set, a later exit: a return is (transaction-ended), raised with
  ;;     nothing issued, never a second COMMIT or RELEASE; any other exit is
  ;;     (nothing);
  ;;   - BEGUN not set, the begin never answered: nothing to roll back, so
  ;;     (nothing), and a return, which the shape never makes, is
  ;;     (transaction-ended), never answered as committed;
  ;;   - BEGUN set and ENDED not, the first exit: at AUTOCOMMIT 0, the level
  ;;     still there, a return is (commit S), COMMIT or RELEASE, and any other
  ;;     exit (rollback S ...); at any other AUTOCOMMIT the transaction ended
  ;;     under the body, so a return is (transaction-ended) and any other
  ;;     exit (nothing).
  ;; Every plan, once carried out, leaves ENDED set, but a commit's, which sets
  ;; it when its statement succeeds; failed-commit-plan's sets it otherwise.
  ;; Total for every LEVEL begin-plan answers.
  (define (exit-plan how begun ended autocommit level)
    (cond ((or ended (not begun))
           (if (eq? how 'return) (list 'transaction-ended) (list 'nothing)))
          ((eq? how 'return)
           (if (eqv? autocommit 0) (commit-of level) (list 'transaction-ended)))
          ((eqv? autocommit 0) (rollback-of level))
          (else (list 'nothing))))

  ;; failed-commit-plan : Any Level -> (U Rollback (List 'nothing))
  ;; After the COMMIT or RELEASE exit-plan answered for LEVEL failed, from
  ;; AUTOCOMMIT read after it: at 0, the level still open, (rollback S ...),
  ;; as a raise's (Q6); otherwise (nothing). The commit's failure is raised
  ;; after either. Total for every LEVEL begin-plan answers.
  (define (failed-commit-plan autocommit level)
    (if (eqv? autocommit 0) (rollback-of level) (list 'nothing)))

  ;; raise-transaction-refusal : Symbol Mode-Refusal -> Nothing
  ;; An assertion violation from WHO for REFUSAL, as transaction-mode or
  ;; begin-plan answered it: its irritants are unknown-mode, then the mode as
  ;; shown. A WHO that is no symbol, checked first, is an assertion violation
  ;; from raise-transaction-refusal, (who V); a REFUSAL that is none,
  ;; (not-a-refusal V); each V by shown-value.
  (define (raise-transaction-refusal who refusal)
    (unless (symbol? who)
      (assertion-violation 'raise-transaction-refusal "not a symbol" 'who (shown-value who)))
    (unless (and (list? refusal) (= (length refusal) 3) (eq? (car refusal) 'refused)
                 (eq? (cadr refusal) 'unknown-mode))
      (assertion-violation 'raise-transaction-refusal "not a refusal of a mode"
                           'not-a-refusal (shown-value refusal)))
    (apply assertion-violation who "not a mode: deferred, immediate or exclusive"
           (cdr refusal))))
