#!r6rs
;;; (chez-sqlite3 private open): the open verbs, open-database and
;;; call-with-database, and the settings list they take (ADR-0012, decisions
;;; 3 and 8; ADR-0018). (chez-sqlite3) exports the two; applied-settings! is
;;; exported for the suites.
;;;
;;; They live here, not in (chez-sqlite3 private connection), because the
;;; settings run statements through M2's statement tier, (chez-sqlite3
;;; private statement) and (chez-sqlite3 private statement-values), which
;;; import the connection's library. The connection's library keeps the
;;; open's parts: prepared-open, connection-outcome, opened-database and
;;; close-connection.
;;;
;;; At most one of the arguments after the filename is a settings list, any
;;; pair or (), an association list from a setting's name to its value; the
;;; rest are the options, symbols (ADR-0018, decision 1, amended). Every check
;;; comes before anything is allocated, and every refusal names the verb the
;;; caller called, in the order the open uses its arguments:
;;;
;;;   1. the split       the options told from the list: a second list is
;;;                      refused, second-settings-list
;;;   2. M2's checks     prepared-open's, in M2's order: the filename a
;;;                      string, the options, a file: name without uri
;;;   3. the list        settings-plan's rules: its shape, then each entry's
;;;                      name, a repeat, its value's domain
;;;
;;; The split comes first, since it is what tells an option from the list.
;;; M2's checks come next, so each of M2's refusals stands as it was, with a
;;; list or without one. The list's come last: its settings run only once the
;;; connection is open (M3 slice 5's choice; ADR-0018, amended in slice 1).
;;; The three run in one critical section, what they raise caught there and
;;; raised again after it, so no engine's expiry and no timer's handler falls
;;; inside them (below).
;;;
;;; Then the open, its statement cache of the list's statement-cache, 32 when
;;; it gives none, fixed in the record when it is made, before any PRAGMA
;;; runs (ADR-0018, decision 4; ADR-0020, decision 1). Then each of SQLite's
;;; settings the list gives, busy-timeout first, then the rest in the list's
;;; order (decision 5): set by one statement, then read back by a second,
;;; PRAGMA and its name, and compared by settings' read-back-comparison
;;; (decision 4). Each statement is prepared with no flags through the
;;; statement tier, never the cache (ADR-0020, decision 3), run, and
;;; finalized before the next is prepared. A mismatch raises
;;; &sqlite-setting-mismatch, its setting, the value asked for and the value
;;; read; a statement's failure raises its own condition, &sqlite-busy under
;;; another's lock among them. Either way the connection is closed first,
;;; then the condition raised (decision 7). A close that fails then is not
;;; raised over it: the setting's condition reaches the caller, and the
;;; connection stays open and counted, for the gate to see, as
;;; call-with-database's close is not raised over its procedure's raise
;;; (ADR-0012, decision 8). call-with-database runs the settings inside its
;;; wind's body, after the open, and never calls its procedure when one
;;; fails.
;;;
;;; One call, many runs. Chez's engine remainders are multi-shot, and a
;;; timer's handler can capture a continuation between any two critical
;;; sections, so one call can have several runs pending at once, each going
;;; on from where its remainder was taken: R, taken before the open and
;;; resumed until it expires again after it, is R1; R resumed again then
;;; opened a second connection, and R1 the first, which nothing returned or
;;; closed; or, R taken after the open, the second run applied the settings
;;; again and left the first's statement at a row on the connection it
;;; returned (the slice's review). A flag set once the connection leaves the
;;; call cannot tell two pending runs apart; a position each run carries in
;;; its own continuation can.
;;;
;;; So each call holds a claim, the position of the next section any run of
;;; it may make, made by the call's first expression; each run carries its
;;; own position, an argument, never assigned, so a continuation holds it as
;;; it was. Every section of the call compares the two, inside the section,
;;; and claims it by advancing the call's: the open's, at 0; then each of the
;;; settings', in order: a statement's prepare, each step, the read, the
;;; finalize; and a failure's close. A run whose position the call has passed
;;; is refused there: the section touches nothing, and the run raises
;;; &sqlite-closed after it, from the verb, and makes no section after (the
;;; maintainer's "Guard every call", ADR-0016, amended in M3 slice 3). So each
;;; section runs once a call, by whichever run reaches it first: one open, each
;;; setting applied once, each statement finalized once, and a refused run
;;; opens, prepares and closes nothing. A section's
;;; outcome is data; a run's next position is the one after its last
;;; section claimed, so a failure's close is claimed by the run whose section
;;; failed.
;;;
;;; The checks' section keeps the plan's SQL from being computed twice from
;;; inside: Chez's own number->string keeps state outside the continuation,
;;; and a remainder taken inside it, resumed a second time, answered "" or the
;;; digits twice, "12341234" (.plans/research/m3-slice-5/, number-twice.sps).
;;; A run that overtakes the first reaches the open first, so a claim cannot
;;; refuse what it computed: the section is what keeps any remainder out of
;;; the checks. A remainder taken before the call's first expression is the
;;; caller's own: resumed, it makes a whole new call, with a claim of its own.
;;;
;;; open-database holds no dynamic-wind around the settings, so an engine's
;;; expiry between two of their sections suspends the open, and the resume
;;; goes on (ADR-0018, consequences). call-with-database's connection does not
;;; survive an expiry, as before (ADR-0012, amended): the extent owns it, and
;;; any run that leaves the extent, refused or not, closes it.
;;;
;;; Every refusal of a caller's mistake is an assertion violation whose
;;; irritants begin with a symbol naming its rule, then the value by
;;; shown-value, never a string's text (ADR-0013, decisions 7 and 9).
(library (chez-sqlite3 private open)
  (export open-database call-with-database applied-settings!)
  (import (chez-sqlite3 private require-threaded)
          (except (rnrs) dynamic-wind)
          (only (chezscheme) critical-section dynamic-wind)
          (only (chez-sqlite3 private conditions) shown-value raise-closed raise-setting-mismatch)
          (only (chez-sqlite3 private connection) prepared-open connection-outcome opened-database
                close-connection)
          (only (chez-sqlite3 private settings) split-open-arguments settings-plan
                raise-setting-refusal read-back-comparison)
          (only (chez-sqlite3 private statement) prepared finalized step!/who)
          (only (chez-sqlite3 private statement-values) column-value/who))

  ;; --- the checks ----------------------------------------------------------------------

  ;; checked-open : Symbol Any (Listof Any)
  ;;                -> (Values String Natural Natural (Listof Setting-Step))
  ;; Setting-Step = (List Symbol String String Any)
  ;; FILENAME and ARGUMENTS, open's arguments after it, checked for WHO, in
  ;; the order the library's header gives: the split, then prepared-open's,
  ;; then settings-plan's, each refusal an assertion violation from WHO
  ;; before anything is allocated. Answers the filename's copy, the open's
  ;; flags, the statement cache's capacity, and the settings' steps,
  ;; busy-timeout's first.
  (define (checked-open who filename arguments)
    (let ((split (split-open-arguments arguments)))
      (unless (eq? (car split) 'split)
        (raise-setting-refusal who split))
      (let-values (((name flags) (prepared-open who filename (cadr split))))
        (let ((plan (settings-plan (caddr split))))
          (unless (eq? (car plan) 'settings)
            (raise-setting-refusal who plan))
          (values name flags (cadr plan) (caddr plan))))))

  ;; checked : Symbol Any (Listof Any)
  ;;           -> (Values String Natural Natural (Listof Setting-Step))
  ;; checked-open's answers, its work in one critical section; what it
  ;; raised, a refusal, caught there and raised again after it, the same
  ;; object. So no remainder is taken inside the checks, and none computes
  ;; the plan's SQL a second time (the library's header).
  (define (checked who filename arguments)
    (let ((outcome
           (critical-section
            (guard (c (#t (list 'raised c)))
              (call-with-values (lambda () (checked-open who filename arguments))
                (lambda answers (cons 'checked answers)))))))
      (if (eq? (car outcome) 'checked)
          (apply values (cdr outcome))
          (raise (cadr outcome)))))

  ;; --- the call's claim ----------------------------------------------------------------

  ;; Claim = Natural -> Boolean
  ;; made-claim : -> Claim
  ;; A call's claim: the position of the next section any run of the call
  ;; may make, 0 at first, held by the procedure answered. Given N, a run's
  ;; position, and called inside that run's section: #t, the call's position
  ;; advanced to N + 1, when the call's is N; else #f, nothing changed. Raises
  ;; nothing.
  (define (made-claim)
    (let ((at 0))
      (lambda (n)
        (and (eqv? at n)
             (begin (set! at (+ n 1)) #t)))))

  ;; Section = (U (List 'answered Natural A ...) (List 'raised Natural Any) (List 'refused))
  ;; in-section : Claim Natural (-> A ...) -> Section
  ;; THUNK's work as the section at position N of its call, in one critical
  ;; section, CLAIM given N first: refused, THUNK never runs; claimed,
  ;; THUNK's answers, or what it raised, caught there, each with N + 1, the
  ;; run's next position. Raises nothing.
  (define (in-section claim n thunk)
    (critical-section
     (if (claim n)
         (guard (c (#t (list 'raised (+ n 1) c)))
           (call-with-values thunk (lambda answers (cons 'answered (cons (+ n 1) answers)))))
         '(refused))))

  ;; --- the settings ----------------------------------------------------------------------

  ;; Run = (U (List 'done Natural Any) (List 'raised Natural Any)
  ;;          (List 'mismatch Natural (List 'mismatch Symbol Any Any)) (List 'refused))
  ;; How a run's work ended: done, its next position and its answer; a
  ;; section's raise, or a mismatch, with the run's next position; or a
  ;; section refused, the run's work over.

  ;; stepped : Symbol Statement Claim Natural -> Run
  ;; ST stepped to done for WHO, a section a step from position N: done,
  ;; answering none.
  (define (stepped who st claim n)
    (let loop ((n n))
      (let ((s (in-section claim n (lambda () (step!/who who st)))))
        (cond ((not (eq? (car s) 'answered)) s)
              ((caddr s) (loop (cadr s)))
              (else (list 'done (cadr s) 'none))))))

  ;; read-once : Symbol Statement Claim Natural -> Run
  ;; ST stepped once for WHO, in the section at N; at a row, its first
  ;; column read, as column-value reads it, in the next: done, answering
  ;; (row V), or none for no row.
  (define (read-once who st claim n)
    (let ((s (in-section claim n (lambda () (step!/who who st)))))
      (cond ((not (eq? (car s) 'answered)) s)
            ((not (caddr s)) (list 'done (cadr s) 'none))
            (else
             (let ((v (in-section claim (cadr s) (lambda () (column-value/who who st 0)))))
               (if (eq? (car v) 'answered)
                   (list 'done (cadr v) (list 'row (caddr v)))
                   v))))))

  ;; ran : Symbol Database String Claim Natural Boolean -> Run
  ;; SQL, one statement of the library's own, prepared on DB for WHO by the
  ;; statement tier, with no flags, never through the cache (ADR-0020,
  ;; decision 3), in the section at N; then stepped to done, when READ? is
  ;; #f, or once and read, when READ? is #t; then finalized, in a section of
  ;; its own. Each its own section, in order. A raise or a refusal ends the
  ;; run's work there, the statement left tracked, for the close to
  ;; finalize: a refused run's twin, which claimed what it was refused, holds
  ;; it.
  (define (ran who db sql claim n read?)
    (let ((made (in-section claim n (lambda () (prepared who db sql #f)))))
      (if (not (eq? (car made) 'answered))
          made
          (let* ((st (caddr made))
                 (used (if read?
                           (read-once who st claim (cadr made))
                           (stepped who st claim (cadr made)))))
            (if (not (eq? (car used) 'done))
                used
                (let ((gone (in-section claim (cadr used) (lambda () (finalized who st)))))
                  (if (eq? (car gone) 'answered)
                      (list 'done (cadr gone) (caddr used))
                      gone)))))))

  ;; step-applied : Symbol Database Setting-Step Claim Natural -> Run
  ;; STEP's setting set on DB by its set statement, then read back by its
  ;; read statement, each by ran, for WHO, from position N, the set's
  ;; finalized before the read is prepared; then compared by
  ;; read-back-comparison, the set's own row never the check (ADR-0018,
  ;; decision 4): done, answering match, or a mismatch.
  (define (step-applied who db step claim n)
    (let ((set (ran who db (cadr step) claim n #f)))
      (if (not (eq? (car set) 'done))
          set
          (let ((read (ran who db (caddr step) claim (cadr set) #t)))
            (if (not (eq? (car read) 'done))
                read
                (let* ((n (cadr read))
                       (comparison (guard (c (#t (list 'raised c)))
                                     (read-back-comparison (car step) (cadddr step) (caddr read)))))
                  (cond ((eq? comparison 'match) (list 'done n 'match))
                        ((eq? (car comparison) 'raised) (list 'raised n (cadr comparison)))
                        (else (list 'mismatch n comparison)))))))))

  ;; settled : Symbol Database (Listof Setting-Step) Claim Natural -> Void
  ;; Each of STEPS applied to DB for WHO, in order, by step-applied, a run
  ;; from position N of CLAIM's call. Every one matching, nothing more. A
  ;; section refused: &sqlite-closed from WHO, nothing touched. Else, at the
  ;; first mismatch, or the first raise, the connection is closed by
  ;; close-connection, in the section at the run's next position, a failure
  ;; of that close caught and dropped, the connection then left open and
  ;; counted; then the mismatch raised as &sqlite-setting-mismatch from WHO,
  ;; or the raise raised again, the same object. That section refused, its
  ;; twin closed it, and &sqlite-closed is raised.
  (define (settled who db steps claim n)
    (let loop ((rest steps) (n n))
      (unless (null? rest)
        (let ((r (step-applied who db (car rest) claim n)))
          (case (car r)
            ((done) (loop (cdr rest) (cadr r)))
            ((refused) (raise-closed who))
            (else
             (let ((closed (in-section claim (cadr r) (lambda () (close-connection who db)))))
               (cond ((eq? (car closed) 'refused) (raise-closed who))
                     ((eq? (car r) 'raised) (raise (caddr r)))
                     (else
                      (let ((m (caddr r)))
                        (raise-setting-mismatch who (cadr m) (caddr m) (cadddr m))))))))))))

  ;; applied-settings! : Symbol Database (Listof Setting-Step) -> Void
  ;; STEPS applied to DB, an open connection, for WHO, as the open verbs
  ;; apply their list's, by settled, with a claim of its own: each set, read
  ;; back and compared; a failure or a mismatch closes DB, then raises. For
  ;; the suites, which give it steps no list makes, to reach each setting's
  ;; mismatch, and a connection whose close fails. STEPS are as settings-plan
  ;; answers them; nothing here checks them.
  (define (applied-settings! who db steps)
    (settled who db steps (made-claim) 0))

  ;; --- open-database -------------------------------------------------------------------

  ;; open-database : String (U Symbol Settings) ... -> Database
  ;; Settings = (Listof (Pairof Symbol Any))
  ;; FILENAME opened with the options among ARGUMENTS (open-options' table;
  ;; ADR-0012, decision 3), owned by the calling thread, its statement cache
  ;; of the settings list's statement-cache, 32 when it gives none; then the
  ;; list's settings applied, busy-timeout first, each read back (ADR-0018).
  ;; The call's claim is its first expression; the open is its section 0,
  ;; the settings' from 1 (the library's header).
  (define (open-database filename . arguments)
    (let* ((claim (made-claim))
           (who 'open-database))
      (let-values (((name flags capacity steps) (checked who filename arguments)))
        (let ((db (opened-database who (connection-outcome who name flags capacity
                                                           (lambda () (not (claim 0)))))))
          (settled who db steps claim 1)
          db))))

  ;; --- call-with-database ------------------------------------------------------------------

  ;; split-last : (Pairof Any (Listof Any)) -> (Values (Listof Any) Any)
  (define (split-last items)
    (let loop ((rest items) (before '()))
      (if (null? (cdr rest))
          (values (reverse before) (car rest))
          (loop (cdr rest) (cons (car rest) before)))))

  ;; call-with-database : String (U Symbol Settings) ... (Database -> A ...) -> A ...
  ;; PROC's answers, PROC given FILENAME opened with the options before it,
  ;; and the settings list among them applied (ADR-0012, decision 8;
  ;; ADR-0018). Every check comes before anything opens: that PROC, the last
  ;; argument, is a procedure, then open-database's. Then:
  ;;   - a setting fails, or mismatches: the connection is closed, then the
  ;;     setting's condition raised, and PROC is never called;
  ;;   - PROC returns, or leaves through a continuation: the connection is
  ;;     closed, and that close's failure raises;
  ;;   - PROC raises: the connection is closed, and PROC's condition reaches
  ;;     the caller unchanged; a failure of that close is not raised over it,
  ;;     and the connection stays open and counted, for the gate to see;
  ;;   - a continuation that re-enters PROC finds the connection closed.
  ;; A raise is told from an escape by a handler around the open, the
  ;; settings and PROC that records it and hands it on in place, with
  ;; raise-continuable; PROC's return, or a handler outside that returns,
  ;; clears it. So a failure of the close is not raised over a setting's
  ;; failure, nor over a refused run's &sqlite-closed. The before thunks do
  ;; nothing, and never clear it: a guard whose clauses do not match
  ;; re-enters the extent to raise again, and the close on the way out again
  ;; must still be contained. The open sits in the body with the variable
  ;; the after thunk reads, in one critical section that answers the open's
  ;; outcome, raised after it; and the winder is Chez's critical form, so no
  ;; interrupt that escapes falls between the open and the close. Its after
  ;; thunk closes and records a close's failure, raising nothing; a plain
  ;; winder around it raises that failure once the critical one is left,
  ;; unless a raise is marked. The call's claim, as open-database's, is
  ;; claimed by the open's section and the settings': a continuation a
  ;; timer's handler took inside them, re-entered while PROC runs, is refused
  ;; at its next section, and leaves the extent, which closes the
  ;; connection. An engine's expiry is an escape: the connection does not
  ;; survive one. Everything raised names call-with-database.
  (define (call-with-database filename . rest)
    (let* ((claim (made-claim))
           (who 'call-with-database))
      (when (null? rest)
        (assertion-violation who "the procedure, the last argument, is missing" 'no-procedure))
      (let-values (((arguments proc) (split-last rest)))
        (unless (procedure? proc)
          (assertion-violation who "the last argument is the procedure" 'not-a-procedure
                               (shown-value proc)))
        (let-values (((name flags capacity steps) (checked who filename arguments)))
          (let ((db #f) (raising #f) (close-failure #f))
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
                       (opened-database who
                                        (critical-section
                                         (let ((outcome (connection-outcome
                                                         who name flags capacity
                                                         (lambda () (not (claim 0))))))
                                           (when (eq? (car outcome) 'opened)
                                             (set! db (cadr outcome)))
                                           outcome)))
                       (settled who db steps claim 1)
                       (call-with-values
                        (lambda () (proc db))
                        (lambda answers (set! raising #f) (apply values answers))))))
                  (lambda ()
                    (when db
                      (set! close-failure
                            (guard (e (#t (list e)))
                              (close-connection who db)
                              #f))))))
              (lambda ()
                (let ((failure close-failure))
                  (set! close-failure #f)
                  (when (and failure (not raising))
                    (raise (car failure))))))))))))
