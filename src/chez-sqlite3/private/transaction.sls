#!r6rs
;;; (chez-sqlite3 private transaction): with-transaction (ADR-0017, amended
;;; in M3 slices 1 and 3), the shell over the pure core, (chez-sqlite3
;;; private transaction-plan). (chez-sqlite3) exports it.
;;;
;;; A call begins a level, runs its body, and commits the level when the body
;;; returns, or rolls it back when the body raises or leaves. The level is
;;; outer, BEGIN with the mode, when sqlite3_get_autocommit reads 1, and a
;;; savepoint, SAVEPOINT chez_sqlite3_N, inside a transaction already open,
;;; N the levels with-transaction holds open outside it, kept in the
;;; connection's record (decisions 2 and 3; slice 3's "Reuse N": N drops when
;;; the call's level ends, whatever SQLite kept).
;;;
;;; The shape is M2's call-with-database's (decision 7):
;;;   - before anything reaches C, the body, then the mode, then the
;;;     database and its owner are checked; then, in one section, the
;;;     refusal and the begin's plan: no statement of the connection may be
;;;     at a row or failed (decision 1), read through tracked-statements and
;;;     statement-state, then autocommit and the depth read for begin-plan.
;;;     The refusal is raised after that section, its irritants
;;;     statement-not-finished, the state and the statement's own SQL, both
;;;     read in that section (the maintainer, 2026-11-16);
;;;   - a plain dynamic-wind around a critical one, both before thunks doing
;;;     nothing, so a re-entry goes through: a guard whose clauses do not
;;;     match re-enters the raise's extent to raise again;
;;;   - in the wind's body, a handler that records a raise and hands it on in
;;;     place, with raise-continuable, around the begin, the body and the
;;;     commit, so the begin's and the commit's failures count as raises; a
;;;     failed commit's rollback runs there too, in one critical section with
;;;     its plan, so no expiry falls inside it;
;;;   - the critical after thunk acts only when BEGUN is set and ENDED is
;;;     not: it reads autocommit, rolls the level back while it is there,
;;;     and sets ENDED, recording a failure and raising nothing; the plain
;;;     after thunk raises that failure, unless a raise is under way.
;;;
;;; The two flags are M3's own. BEGUN is set in the section of the step that
;;; answered the BEGIN or SAVEPOINT; ENDED in the section of the step that
;;; commits, or of a rollback's last step taken, whatever it answered (slice
;;; 3's "Once"), or in the section that plans nothing more. Each step that
;;; could end the level, and the begin's, reads ENDED in its own section
;;; before it steps, and with it set steps nothing (slice 1's amendment).
;;; A later exit issues nothing: a later return raises
;;; &sqlite-transaction-ended, and a later raise or escape does nothing more.
;;;
;;; Each statement goes through the conveniences' path and the cache, taken
;;; from the cache, stepped and given back in one critical section, so no
;;; expiry lands between the three, and none of the call's statements is left
;;; checked out or failed. The section reads ENDED first, through checked-out's
;;; check, so a remainder resumed once the level has ended checks out none of
;;; the call's statements (slice 3's open question, settled by
;;; tests/test-transaction-engine.sps).
;;;
;;; Everything raised names with-transaction, and is raised after every
;;; critical section (decision 8). The body's own conditions reach the
;;; caller unchanged.
(library (chez-sqlite3 private transaction)
  (export with-transaction)
  (import (chez-sqlite3 private require-threaded)
          (except (rnrs) dynamic-wind)
          (only (chezscheme) critical-section dynamic-wind)
          (only (chez-sqlite3 private native) sqlite3-get-autocommit)
          (only (chez-sqlite3 private conditions) raise-transaction-ended shown-value)
          (only (chez-sqlite3 private connection) call-with-open-handle check-database-owner
                tracked-statements database-depth set-database-depth!)
          (only (chez-sqlite3 private statement) checked-out returned step!/who statement-state statement-sql)
          (chez-sqlite3 private transaction-plan))

  ;; held-state : Database -> (U (List Symbol String) #f)
  ;; The state and the SQL of the first statement DB tracks, oldest first,
  ;; that is at a row or failed; #f when none is. A pass in Scheme that
  ;; reaches no C, called inside call-with-open-handle's section, so the two
  ;; are read in one section.
  (define (held-state db)
    (let loop ((rest (tracked-statements db)))
      (cond ((null? rest) #f)
            ((memq (statement-state (car rest)) '(row failed))
             (list (statement-state (car rest)) (statement-sql (car rest))))
            (else (loop (cdr rest))))))

  ;; issued : Symbol Database String (-> Boolean) (Symbol -> Any)
  ;;          -> (U 'stepped 'ended (List 'failed Any))
  ;; SQL, one of with-transaction's own statements, run once on DB for WHO,
  ;; in one critical section, where no expiry lands:
  ;;   - the check-out, through checked-out, the cache's or a fresh prepare,
  ;;     its check ENDED?: set, it touches nothing, and the answer is ended.
  ;;     A check-out that fails, a refused prepare, answers (failed C), MARK!
  ;;     called with failed;
  ;;   - the step, which calls MARK! with stepped or failed;
  ;;   - the return, by returned: kept, or finalized when its step failed. A
  ;;     failure of the return is dropped: the step's outcome is the answer.
  ;; Everything inside answers data, and nothing raises out of the section.
  (define (issued who db sql ended? mark!)
    (critical-section
     (let* ((refused #f)
            (check (lambda ()
                     (cond ((ended?) (set! refused #t) #t)
                           (else #f))))
            (out (guard (c (#t (if refused
                                   '(ended)
                                   (begin (mark! 'failed) (list 'failed c)))))
                   (list 'out (checked-out who db sql #f check)))))
       (if (not (eq? (car out) 'out))
           (if (eq? (car out) 'ended) 'ended out)
           (let* ((st (cadr out))
                  (stepped (let ((r (guard (c (#t (list 'failed c)))
                                      (step!/who who st)
                                      'stepped)))
                             (mark! (if (pair? r) 'failed 'stepped))
                             r)))
             (guard (c (#t #f)) (returned who st))
             stepped)))))

  ;; with-transaction : (case-> (Database (-> A ...) -> A ...) (Database Mode (-> A ...) -> A ...))
  ;; Mode = (U 'deferred 'immediate 'exclusive)
  ;; BODY's answers, run inside a level of DB's transaction, which commits
  ;; when BODY returns and is rolled back when it raises or leaves; the mode
  ;; immediate when absent, and of no effect at a nested level.
  (define with-transaction
    (case-lambda
      ((db body) (transaction 'with-transaction db 'immediate body))
      ((db mode body) (transaction 'with-transaction db mode body))))

  ;; transaction : Symbol Any Any Any -> A ...
  ;; with-transaction's work, for WHO.
  (define (transaction who db mode body)
    (unless (procedure? body)
      (assertion-violation who "the body is no procedure" 'not-a-procedure (shown-value body)))
    (let ((checked (transaction-mode mode)))
      (unless (eq? (car checked) 'mode)
        (raise-transaction-refusal who checked)))
    (check-database-owner who db)
    (let ((plan (call-with-open-handle who db
                  (lambda (handle)
                    (let ((held (held-state db)))
                      (if held
                          (list 'refused held)
                          (begin-plan (sqlite3-get-autocommit handle) (database-depth db) mode)))))))
      (when (eq? (car plan) 'refused)
        (assertion-violation who "a statement of the connection is at a row or failed; reset or finalize it first"
                             'statement-not-finished (car (cadr plan)) (cadr (cadr plan))))
      (run-level who db (cadr plan) (caddr plan) body)))

  ;; run-level : Symbol Database Level String (-> A ...) -> A ...
  ;; Level = (U 'outer (List 'savepoint Natural)), as begin-plan answers it
  ;; The level LEVEL begun by BEGIN-SQL, BODY run inside it, and its exits,
  ;; by the flags.
  (define (run-level who db level begin-sql body)
    (let ((begun #f) (ended #f) (raising #f) (rollback-failure #f))
      ;; ended? : -> Boolean
      (define (ended?) ended)
      ;; end-level! : -> Void
      ;; ENDED set, and the depth one less, once; called inside a section.
      (define (end-level!)
        (unless ended
          (set! ended #t)
          (set-database-depth! db (- (database-depth db) 1))))
      ;; autocommit-plan : Symbol -> Exit-Plan
      ;; exit-plan for HOW, from the flags and autocommit read now, in
      ;; call-with-open-handle's section.
      (define (autocommit-plan how)
        (call-with-open-handle who db
          (lambda (handle)
            (exit-plan how begun ended (sqlite3-get-autocommit handle) level))))
      ;; rolled-back! : (Listof String) -> (U Any #f)
      ;; STATEMENTS issued in turn, stopping at the first that does not
      ;; step; ENDED set in the section of the last step taken, whatever it
      ;; answered. The first failure, or #f.
      (define (rolled-back! statements)
        (let loop ((rest statements))
          (if (null? rest)
              #f
              (let* ((last? (null? (cdr rest)))
                     (outcome (issued who db (car rest) ended?
                                      (lambda (o)
                                        (when (or last? (not (eq? o 'stepped)))
                                          (end-level!))))))
                (cond ((eq? outcome 'stepped) (loop (cdr rest)))
                      ((eq? outcome 'ended) #f)
                      (else (cadr outcome)))))))
      ;; failed-commit! : -> Void
      ;; After the COMMIT or RELEASE failed: the level rolled back while it
      ;; is still there and ENDED is unset (Q6, failed-commit-plan); ENDED set
      ;; in the section that plans nothing more. The plan and every step of
      ;; the rollback run in one critical section, where no expiry lands, so
      ;; an engine's exit never falls between ROLLBACK TO and RELEASE to
      ;; issue either again: the rollback is tried once ("Once", under any
      ;; interleaving; tests/test-transaction-engine.sps). Each part answers
      ;; data, and nothing raises out of the section. Its failures are
      ;; dropped: the commit's failure is raised after it.
      (define (failed-commit!)
        (critical-section
         (let ((plan (guard (e (#t '(nothing)))
                       (call-with-open-handle who db
                         (lambda (handle)
                           (let ((p (failed-commit-plan ended (sqlite3-get-autocommit handle) level)))
                             (when (eq? (car p) 'nothing) (end-level!))
                             p))))))
           (when (eq? (car plan) 'rollback)
             (guard (e (#t #f)) (rolled-back! (cdr plan)))))))
      ;; committed! : -> Void
      ;; The first return's commit, in the wind's body: autocommit read, then
      ;; COMMIT or RELEASE, whose step reads ENDED in its own section; a
      ;; level already ended raises &sqlite-transaction-ended, issuing
      ;; nothing; a failed commit is rolled back, then its failure raised.
      (define (committed!)
        (let ((plan (call-with-open-handle who db
                      (lambda (handle)
                        (let ((p (exit-plan 'return begun ended (sqlite3-get-autocommit handle) level)))
                          (when (and begun (eq? (car p) 'transaction-ended)) (end-level!))
                          p)))))
          (if (eq? (car plan) 'commit)
              (let ((outcome (issued who db (cadr plan) ended?
                                     (lambda (o) (when (eq? o 'stepped) (end-level!))))))
                (cond ((eq? outcome 'stepped) (if #f #f))
                      ((eq? outcome 'ended) (raise-transaction-ended who))
                      (else (failed-commit!) (raise (cadr outcome)))))
              (raise-transaction-ended who))))
      ;; begun! : -> Void
      ;; BEGIN-SQL issued, BEGUN set and the depth one more in its step's
      ;; section; its failure raised, and a level that ended under a
      ;; resumed remainder raises &sqlite-transaction-ended.
      (define (begun!)
        (let ((outcome (issued who db begin-sql ended?
                               (lambda (o)
                                 (when (eq? o 'stepped)
                                   (set! begun #t)
                                   (set-database-depth! db (+ (database-depth db) 1)))))))
          (cond ((eq? outcome 'stepped) (if #f #f))
                ((eq? outcome 'ended) (raise-transaction-ended who))
                (else (raise (cadr outcome))))))
      (dynamic-wind
        (lambda () #f)
        (lambda ()
          (dynamic-wind #t
            (lambda () #f)
            (lambda ()
              (with-exception-handler
               (lambda (c)
                 (set! raising (list c))
                 (call-with-values
                  (lambda () (raise-continuable c))
                  (lambda answers (set! raising #f) (apply values answers))))
               (lambda ()
                 (begun!)
                 (call-with-values body
                   (lambda answers
                     (committed!)
                     (set! raising #f)
                     (apply values answers))))))
            (lambda ()
              (when (and begun (not ended))
                (set! rollback-failure
                      (guard (e (#t (list e)))
                        (let ((plan (autocommit-plan 'raise)))
                          (and (eq? (car plan) 'rollback)
                               (let ((failure (rolled-back! (cdr plan))))
                                 (and failure (list failure)))))))
                (end-level!)))))
        (lambda ()
          (let ((failure rollback-failure))
            (set! rollback-failure #f)
            (when (and failure (not raising))
              (raise (car failure)))))))))
