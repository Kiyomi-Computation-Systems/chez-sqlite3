#!r6rs
;;; (chez-sqlite3 private transaction): with-transaction (ADR-0017), the
;;; shell over the pure core, (chez-sqlite3 private transaction-plan).
;;; (chez-sqlite3) exports it.
;;;
;;; A call begins a level, runs its body, and commits the level when the body
;;; returns, or rolls it back when the body raises or leaves. The level is
;;; outer, BEGIN with the mode, when sqlite3_get_autocommit reads 1, and a
;;; savepoint, SAVEPOINT chez_sqlite3_N, inside a transaction already open,
;;; N the levels with-transaction holds open outside it, kept in the
;;; connection's record: N drops when the call's level ends, whatever SQLite
;;; kept.
;;;
;;; The shape is call-with-database's:
;;;   - the call's claim, made by its first expression, before any check:
;;;     the BEGIN's section takes it, so one run of the call alone reaches
;;;     the BEGIN. Chez's engine remainders are multi-shot, and a timer's
;;;     handler can take a continuation between any two sections; a run
;;;     that reaches the BEGIN's section once another has taken the claim
;;;     steps nothing and raises &sqlite-transaction-ended. Without the
;;;     claim, a remainder taken before the flags are made, resumed a second
;;;     time once the call has ended, would begin, run the body and commit
;;;     again;
;;;   - before anything reaches C, the body, then the mode, then the
;;;     database and its owner are checked;
;;;   - a plain dynamic-wind around a critical one, both before thunks doing
;;;     nothing, so a re-entry goes through: a guard whose clauses do not
;;;     match re-enters the raise's extent to raise again;
;;;   - in the wind's body, a handler that records a raise and hands it on in
;;;     place, with raise-continuable, around the begin, the body and the
;;;     commit, so the begin's and the commit's failures count as raises; a
;;;     failed commit's rollback runs there too, in one critical section with
;;;     its plan, so no expiry falls inside it;
;;;   - the begin is one critical section: the claim, then the refusal and
;;;     the plan, then the BEGIN or SAVEPOINT taken, stepped and given back.
;;;     No statement of the connection may be at a row or failed, read
;;;     through tracked-statements and statement-state; then autocommit and
;;;     the depth are read for begin-plan, which builds the savepoint's name
;;;     there. So nothing splits the plan from its step:
;;;     another engine's BEGIN between them would make SQLite refuse the
;;;     planned BEGIN IMMEDIATE inside its transaction, after taking its
;;;     lock. The refusal is raised after that section, before anything else
;;;     reaches C, its irritants statement-not-finished, the state and the
;;;     statement's own SQL, both read in that section;
;;;   - the critical after thunk acts only when BEGUN is set and ENDED is
;;;     not: it reads autocommit, rolls the level back while it is there,
;;;     and sets ENDED, recording a failure and raising nothing; the plain
;;;     after thunk raises that failure, unless a raise is under way.
;;;
;;; The two flags are with-transaction's own. BEGUN is set in the section of
;;; the step that answered the BEGIN or SAVEPOINT; ENDED in the section of
;;; the step that commits, or of a rollback's last step taken, whatever it
;;; answered, or in the section that plans nothing more. Each step that
;;; could end the level, and the begin's, reads ENDED in its own section
;;; before it steps, and with it set steps nothing; the begin's takes the
;;; claim first. The flags are made after the claim, so a run that makes
;;; flags of its own never passes the BEGIN's section, and every run past it
;;; shares the one that took the claim's. A later
;;; exit issues nothing: a later return raises &sqlite-transaction-ended,
;;; and a later raise or escape does nothing more.
;;;
;;; The rollback, ROLLBACK, or ROLLBACK TO then RELEASE, a raise's or a
;;; failed commit's, runs with the connection's interrupt latch shut, by
;;; call-with-latch-shut, so an interrupt-database! sent while it runs, from
;;; any thread, is dropped. SQLite clears an interrupt as a statement starts
;;; with none active, and checks it after: without the shut, a watchdog that
;;; kept interrupting would stop the ROLLBACK, and the transaction would
;;; outlive the call. The COMMIT, and the RELEASE that commits a savepoint,
;;; stay interruptible, and an interrupted one is rolled back under the
;;; shut. One case stays: an
;;; interrupt sent before the shut while a statement of the connection is at
;;; a row still stops the rollback, since SQLite keeps it while a statement
;;; is active: the sticky interrupt (ADR-0017).
;;;
;;; Each statement goes through the conveniences' path and the cache, taken
;;; from the cache, stepped and given back in one critical section, so no
;;; expiry lands between the three, and none of the call's statements is left
;;; checked out or failed. The section reads ENDED first, through checked-out's
;;; check, so a remainder resumed once the level has ended checks out none of
;;; the call's statements (tests/test-transaction-engine.sps).
;;;
;;; Everything raised names with-transaction, and is raised after every
;;; critical section. The body's own conditions reach the caller unchanged.
(library (chez-sqlite3 private transaction)
  (export with-transaction)
  (import (chez-sqlite3 private require-threaded)
          (except (rnrs) dynamic-wind)
          (only (chezscheme) critical-section dynamic-wind)
          (only (chez-sqlite3 private native) sqlite3-get-autocommit)
          (only (chez-sqlite3 private conditions) raise-transaction-ended shown-value)
          (only (chez-sqlite3 private connection) call-with-open-handle check-database-owner
                tracked-statements database-depth set-database-depth! call-with-latch-shut)
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
  ;; with-transaction's work, for WHO. Its first expression makes the call's
  ;; claim, before any check: a variable and a procedure, no call, so no
  ;; expiry falls between the call's entry and the claim's making but the
  ;; entry's own. A remainder taken before it is the caller's: resumed, it
  ;; makes a whole new call, with a claim of its own.
  (define (transaction who db mode body)
    (let* ((taken #f)
           (claim! (lambda () (and (not taken) (begin (set! taken #t) #t)))))
      (unless (procedure? body)
        (assertion-violation who "the body is no procedure" 'not-a-procedure (shown-value body)))
      (let ((checked (transaction-mode mode)))
        (unless (eq? (car checked) 'mode)
          (raise-transaction-refusal who checked)))
      (check-database-owner who db)
      (run-level who db mode body claim!)))

  ;; run-level : Symbol Database Mode (-> A ...) (-> Boolean) -> A ...
  ;; The level begun for MODE, BODY run inside it, and its exits, by the
  ;; flags; CLAIM!, the call's claim, taken by the BEGIN's section: #t the
  ;; first time it is called, #f after. LEVEL, as begin-plan answers it, is
  ;; set with BEGUN, in the section of the BEGIN's step.
  ;; Level = (U 'outer (List 'savepoint Natural))
  (define (run-level who db mode body claim!)
    (let ((begun #f) (ended #f) (level #f) (raising #f) (rollback-failure #f))
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
      ;; answered. The first failure, or #f. All of them run with the
      ;; connection's interrupt latch shut, in its one critical section, so
      ;; an interrupt-database! sent while they run is dropped. One sent
      ;; before, while a statement of the connection is at a row, still
      ;; stops them: SQLite keeps an interrupt while a statement is active,
      ;; and clears it at a statement's start only when none is. Called
      ;; inside a critical section, the after thunk's or failed-commit!'s;
      ;; raises nothing, issued answering data.
      (define (rolled-back! statements)
        (call-with-latch-shut db
          (lambda ()
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
                          (else (cadr outcome)))))))))
      ;; failed-commit! : -> Void
      ;; After the COMMIT or RELEASE failed: the level rolled back while it
      ;; is still there and ENDED is unset (failed-commit-plan); ENDED set
      ;; in the section that plans nothing more. The plan and every step of
      ;; the rollback run in one critical section, where no expiry lands, so
      ;; an engine's exit never falls between ROLLBACK TO and RELEASE to
      ;; issue either again: the rollback is tried once, under any
      ;; interleaving (tests/test-transaction-engine.sps). Each part answers
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
      ;; In one critical section: CLAIM! taken; then, in
      ;; call-with-open-handle's, the refusal's pass, held-state, and the
      ;; plan, begin-plan from autocommit, the depth and MODE; then the
      ;; plan's BEGIN or SAVEPOINT issued, BEGUN and LEVEL set and the depth
      ;; one more in its step's section. After the section: a claim another
      ;; run had taken, and a level that ended under a resumed remainder,
      ;; raise &sqlite-transaction-ended, nothing stepped; the refusal is an
      ;; assertion violation, statement-not-finished; the BEGIN's failure,
      ;; or the handle's, is raised.
      (define (begun!)
        (let ((outcome
               (critical-section
                (if (not (claim!))
                    '(claimed)
                    (let ((plan (guard (c (#t (list 'raised c)))
                                  (call-with-open-handle who db
                                    (lambda (handle)
                                      (let ((held (held-state db)))
                                        (if held
                                            (cons 'not-finished held)
                                            (begin-plan (sqlite3-get-autocommit handle) (database-depth db)
                                                        mode))))))))
                      (if (eq? (car plan) 'begin)
                          (issued who db (caddr plan) ended?
                                  (lambda (o)
                                    (when (eq? o 'stepped)
                                      (set! level (cadr plan))
                                      (set! begun #t)
                                      (set-database-depth! db (+ (database-depth db) 1)))))
                          plan))))))
          (cond ((eq? outcome 'stepped) (if #f #f))
                ((eq? outcome 'ended) (raise-transaction-ended who))
                ((eq? (car outcome) 'claimed) (raise-transaction-ended who))
                ((eq? (car outcome) 'not-finished)
                 (assertion-violation who "a statement of the connection is at a row or failed; reset or finalize it first"
                                      'statement-not-finished (cadr outcome) (caddr outcome)))
                ((eq? (car outcome) 'refused) (raise-transaction-refusal who outcome))
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
