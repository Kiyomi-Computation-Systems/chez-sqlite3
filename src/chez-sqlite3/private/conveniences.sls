#!r6rs
;;; (chez-sqlite3 private conveniences): the conveniences, each running its
;;; SQL as one statement at a time and finishing it on every path before it
;;; returns or raises (ADR-0016). (chez-sqlite3) exports its five verbs.
;;;
;;;   execute!         one statement, with parameters, stepped to done, its
;;;                    rows dropped; answers nothing
;;;   query            one statement's every row, in order
;;;   query-row        one statement's first row, or #f, the rest never read
;;;   query-fold       (proc acc row) over one statement's rows, as R6RS
;;;                    fold-left calls its procedure
;;;   execute-script!  a script, with no parameters: its statements prepared
;;;                    one at a time, each run to done, until the first error
;;;
;;; A row is a vector of the row's values, in column order (the M3 plan's
;;; Q2). Its column count is read once, at the row, after its step, and each
;;; value is read by M2's who-taking column read, in a critical section of
;;; its own (Q15); parameters are positional, bound by bind-each!/who,
;;; every value checked before any is bound, then one value a section
;;; (ADR-0015, decision 6).
;;;
;;; Everything raised names the convenience the caller called: each reaches
;;; M2's statement tier through part A's internals, which take a WHO
;;; (ADR-0013, decision 2; ADR-0016, decision 9), and raises after their
;;; critical sections, so a with-exception-handler handler of a convenience's
;;; raise runs at depth 1.
;;;
;;; Chez's engine remainders are multi-shot, and a timer's, keyboard's or
;;; collect request's handler can capture a continuation between any two
;;; critical sections, so one call can have several runs pending at once,
;;; each going on from where its remainder was taken: R, taken before the
;;; check-out and resumed until it expires again after it, is R1, and R can
;;; then be resumed again while R1 holds the statement (M3 slice 5's part D,
;;; the M2 session's sweep). Slice 3's flag, set once the statement left the
;;; call, could not tell two pending runs apart: R found R1's statement out
;;; of the cache, prepared a second, gave it back and set the flag, and R1
;;; was refused at its next section still holding the first, left out of the
;;; cache, at a row for query and query-row; and two runs both past the
;;; check-out both stepped the one statement, one answering rows the other
;;; had stepped past. So execute!, query and query-row hold a claim on their
;;; call, as the open verbs do (ADR-0018, amended in M3 slice 5): the
;;; position of the next section any run of the call may make, made by the
;;; call's first expression. Each run carries its own position, an argument,
;;; never assigned, so a continuation holds it as it was, and every section
;;; of the call claims it inside the section, advancing the call's:
;;;
;;;   0         the check-out, and a miss's prepare, in one section, so the
;;;             call makes its statement once, by one run
;;;   1 ...     each bind's, the count's and each value's, by bind-each!/at
;;;             (Q15, "One value each"); then each step's; at a row, the
;;;             column count's and each column's read
;;;   the last  the return, by returned, which ends the claim
;;;
;;; A run the call has passed is refused at its next section: the section
;;; touches nothing, and the run raises &sqlite-closed from the verb, and
;;; makes no section after (the maintainer's "Guard every call", ADR-0016,
;;; amended in M3 slice 3). So each section runs once a call, by whichever
;;; run reaches it first, and a refused run holds nothing: no two runs of
;;; one call each hold a statement, nor step one twice. Every section claims
;;; its position, not only the two that make or hand out the statement:
;;; with the flag kept for the rest, two runs both past the check-out would
;;; share the statement and pass every section. A section's outcome is data,
;;; with the run's next position, so a raise in one gives the statement back
;;; at the position after it. A raise no section caught, a timer's or a
;;; keyboard handler's between two sections, gives the statement back by a
;;; claim of whatever position is next, unless the call has ended, so a
;;; raise always finishes it, whichever run then held it.
;;;
;;; query-fold and execute-script! keep slice 3's flag, which their winds
;;; make enough: an engine's expiry inside the fold's wind finishes its
;;; statement and sets its flag, and one inside the script's block frees the
;;; block, so neither survives a preemption, and no second run reaches a
;;; statement another holds. Every critical section that touches the call's
;;; statement reads the flag first: the check-out's, before the table is
;;; read; a miss's prepare, before it prepares, both through checked-out's
;;; LEFT?; each bind's, through bind-each!/who's; each step's and each
;;; column read's, through while-held; and the return's or the finalize's,
;;; which also sets it. Set, the section touches nothing, and the
;;; convenience raises &sqlite-closed after it. A re-entry inside the
;;; library's own winds, call-with-open-handle's, around a check-out or a
;;; prepare, and call-with-block's, around a script, is refused by those
;;; winds, an assertion violation, re-entered, before any flag is read.
;;;
;;; A remainder taken before a call's first expression is the caller's:
;;; resumed, it makes a whole new call, with a claim or a flag of its own.
;;;
;;; The four that take parameters check out a statement from the
;;; connection's statement cache, a fresh one prepared
;;; SQLITE_PREPARE_PERSISTENT on a miss above a capacity of 0, and give it
;;; back by returned: reset, its bindings cleared and filed; or finalized,
;;; when it failed, the capacity is 0, its SQL is held already, or its reset
;;; failed (ADR-0020, decision 5). Only a statement checked-out answered is
;;; given back. execute-script! uses no cache, and prepares with no flags.
;;;
;;;   execute!, query, query-row
;;;       call no procedure of the caller's and hold no dynamic-wind: a raise
;;;       inside one is caught, the statement given back, and the raise made
;;;       again, the same object. A failure of that return is dropped then,
;;;       so the convenience's own condition reaches the caller unchanged; a
;;;       return that fails after a convenience's own work raises its failure:
;;;       query-row's reset of an insert ... returning that commits under
;;;       another's read, or the finalize of a statement the return evicted.
;;;       Under an engine each completes: an expiry falls only between
;;;       critical sections, and nothing but the convenience reaches its
;;;       checked-out statement; a run resumed once another has passed it,
;;;       before the return or after, raises &sqlite-closed at its next
;;;       section, touching nothing. A way out that is no raise, an escaping
;;;       timer or keyboard handler, or an engine never resumed, leaves the
;;;       statement out of the cache until the close (ADR-0016, decision 6).
;;;   query-fold
;;;       M2's call-with-statement's shape, with a flag of M3's own (ADR-0016,
;;;       decision 6), below.
;;;   execute-script!
;;;       one block, the script's C string, held for the loop by
;;;       call-with-c-string, whose before thunk refuses a re-entry; so
;;;       nothing raises out of the block's extent, and everything raised in
;;;       it is caught there and raised after call-with-c-string returns
;;;       (ADR-0016, decision 7). Its flag says the call's run has begun,
;;;       marked by its first prepare's section, which reads it first: so a
;;;       call re-entered before its block refuses, &sqlite-closed, rather
;;;       than running the script again. Below.
;;;
;;; code-number is exported for the suites, which hold its branches.
(library (chez-sqlite3 private conveniences)
  (export execute! query query-row query-fold execute-script! code-number)
  (import (chez-sqlite3 private require-threaded)
          (except (rnrs) dynamic-wind)
          (only (chezscheme) critical-section dynamic-wind)
          (only (chez-sqlite3 private native) call-with-c-string)
          (only (chez-sqlite3 private constants) sqlite-result-codes)
          (only (chez-sqlite3 private conditions) raise-sqlite-error raise-closed shown-value
                sqlite-error? sqlite-error-extended-code sqlite-error-message)
          (only (chez-sqlite3 private connection) check-database-owner)
          (only (chez-sqlite3 private statement) checked-out returned finalized step!/who
                column-count/who checked-sql prepared-at while-held)
          (only (chez-sqlite3 private statement-values) bind-each!/who bind-each!/at column-value/who)
          (only (chez-sqlite3 private script) script-prepare-offset script-step-offset))

  ;; --- query-fold's row and step ------------------------------------------------------

  ;; row-of : Symbol Statement (-> Boolean) -> (Vectorof Value)
  ;; ST's row, at a row, for WHO: its column count read once, now, after the
  ;; step (single K2.1, K2.2, K2.7), then each column from 0, in order, by
  ;; column-value/who, each in a critical section of its own (Q15), each
  ;; reading the call's flag, LEFT?, first, by while-held. A named let,
  ;; never map, whose order of calls is not fixed (AGENTS.md).
  (define (row-of who st left?)
    (let* ((n (while-held who left? (lambda () (column-count/who who st))))
           (row (make-vector n)))
      (let loop ((i 0))
        (when (< i n)
          (vector-set! row i (while-held who left? (lambda () (column-value/who who st i))))
          (loop (+ i 1))))
      row))

  ;; stepped : Symbol Statement (-> Boolean) -> Boolean
  ;; ST stepped by step!/who, for WHO, in a section that reads the call's
  ;; flag, LEFT?, first.
  (define (stepped who st left?)
    (while-held who left? (lambda () (step!/who who st))))

  ;; --- execute!, query and query-row: the call's claim -----------------------------------

  ;; Claim = (U Natural #f) Boolean -> Boolean
  ;; made-claim : -> Claim
  ;; A call's claim: the position of the next section any run of the call
  ;; may make, 0 at first, or #f once its last section is made, held by the
  ;; procedure answered. Given N, a run's position, and LAST?, called inside
  ;; that run's section: #t when the call's position is N, or N is #f and
  ;; the call has not ended, the call's position then advanced past N, or
  ;; ended when LAST?; else #f, nothing changed. Raises nothing.
  (define (made-claim)
    (let ((at 0))
      (lambda (n last?)
        (and at
             (or (not n) (eqv? at n))
             (begin (set! at (if last? #f (+ at 1))) #t)))))

  ;; in-section : Claim (U Natural #f) Boolean (-> A ...) -> Section
  ;; THUNK's work as the section at position N of its call, in one critical
  ;; section, CLAIM given N and LAST? first: refused, THUNK never runs;
  ;; claimed, THUNK's answers, or what it raised, caught there, each with
  ;; the run's next position, N + 1, #f for none. Section is
  ;; (chez-sqlite3 private statement-values)'s. Raises nothing.
  (define (in-section claim n last? thunk)
    (critical-section
     (if (claim n last?)
         (let ((next (and n (+ n 1))))
           (guard (c (#t (list 'raised next c)))
             (call-with-values thunk (lambda answers (cons 'answered (cons next answers))))))
         '(refused))))

  ;; sectioner : Claim -> Sectioner
  ;; A run's sections for bind-each!/at, each claiming its position.
  (define (sectioner claim)
    (lambda (n thunk) (in-section claim n #f thunk)))

  ;; and-then : Run (Natural Any -> Run) -> Run
  ;; NEXT given RUN's next position and answer, when RUN is done; else RUN.
  (define (and-then run next)
    (if (eq? (car run) 'done) (next (cadr run) (caddr run)) run))

  ;; step-at : Symbol Statement Claim Natural -> Section
  ;; ST stepped by step!/who, for WHO, the section at N: answering #t at a
  ;; row, #f at done.
  (define (step-at who st claim n)
    (in-section claim n #f (lambda () (step!/who who st))))

  ;; row-at : Symbol Statement Claim Natural -> Run
  ;; ST's row, at a row, for WHO, from position N: its column count read
  ;; once, in the section at N, after the step (single K2.1, K2.2, K2.7),
  ;; then each column from 0, in order, by column-value/who, each in a
  ;; section of its own (Q15). A named let, never map, whose order of calls
  ;; is not fixed (AGENTS.md). Done, answering the row.
  (define (row-at who st claim n)
    (let ((counted (in-section claim n #f (lambda () (column-count/who who st)))))
      (if (not (eq? (car counted) 'answered))
          counted
          (let* ((count (caddr counted))
                 (row (make-vector count)))
            (let loop ((i 0) (n (cadr counted)))
              (if (= i count)
                  (list 'done n row)
                  (let ((read (in-section claim n #f (lambda () (column-value/who who st i)))))
                    (if (eq? (car read) 'answered)
                        (begin (vector-set! row i (caddr read))
                               (loop (+ i 1) (cadr read)))
                        read))))))))

  ;; with-checked-out : Symbol Claim Any Any (Statement Natural -> Run) -> A
  ;; WORK's answer, WORK given a statement for SQL on DB checked out of DB's
  ;; cache, for WHO, and the run's position after the check-out, once the
  ;; statement is given back to it. CLAIM is the call's, made by its first
  ;; expression. The sections, each claiming its position:
  ;;   - the check-out, and a miss's prepare, one section at 0, by
  ;;     checked-out with no check of its own; the statement noted in HELD,
  ;;     inside it, by on-made;
  ;;   - WORK's, each bind's, step's and read's, in order;
  ;;   - the return, by returned, at the run's next position, the call's
  ;;     last.
  ;; A section refused: the run touches nothing more, and &sqlite-closed is
  ;; raised from WHO. Else the check-out's refusal, or its prepare's failure,
  ;; raises, no statement out. A raise in WORK's sections: the statement
  ;; given back, any failure of that return dropped, and the raise raised
  ;; again, the same object. WORK done: the return's own failure raises,
  ;; else WORK's answer. A raise no section caught, a timer's or keyboard
  ;; handler's between two sections, gives back HELD, the call's statement,
  ;; by a claim of whatever position is next, unless the call has ended,
  ;; and is raised again: whichever run held it then is refused at its next
  ;; section. Everything is raised after every section. WORK is the
  ;; convenience's own, and calls nothing of the caller's; there is no
  ;; dynamic-wind (ADR-0016, decision 6).
  (define (with-checked-out who claim db sql work)
    (let* ((held #f)
           (outcome
            (guard (c (#t (list 'escaped c)))
              (let* ((out (in-section claim 0 #f
                            (lambda () (checked-out who db sql (lambda (st) (set! held st)) #f))))
                     (run (if (eq? (car out) 'answered) (work (caddr out) (cadr out)) out)))
                (if (and held (memq (car run) '(done raised)))
                    (list 'given run
                          (in-section claim (cadr run) #t (lambda () (returned who held))))
                    (list 'kept run))))))
      (case (car outcome)
        ((given)
         (let ((run (cadr outcome)) (back (caddr outcome)))
           (cond ((eq? (car back) 'refused) (raise-closed who))
                 ((eq? (car run) 'raised) (raise (caddr run)))
                 ((eq? (car back) 'raised) (raise (caddr back)))
                 (else (caddr run)))))
        ((kept)
         (let ((run (cadr outcome)))
           (if (eq? (car run) 'raised) (raise (caddr run)) (raise-closed who))))
        (else
         (when held (in-section claim #f #t (lambda () (returned who held))))
         (raise (cadr outcome))))))

  ;; execute! : Database String Value ... -> Void
  ;; SQL, one statement, run on DB with GIVEN bound to its parameters, 1 to
  ;; n: stepped to done, any rows it answers dropped, as sqlite3_exec drops
  ;; them (M3's research, single script X7), a PRAGMA's set among them.
  ;; Answers nothing: changes says what it counts (ADR-0016, decision 4).
  ;; The call's claim is its first expression.
  (define (execute! db sql . given)
    (let ((claim (made-claim)))
      (with-checked-out 'execute! claim db sql
        (lambda (st n)
          (and-then (bind-each!/at 'execute! st given (sectioner claim) n)
                    (lambda (n bound)
                      (let loop ((n n))
                        (let ((s (step-at 'execute! st claim n)))
                          (cond ((not (eq? (car s) 'answered)) s)
                                ((caddr s) (loop (cadr s)))
                                (else (list 'done (cadr s) 'stepped)))))))))
      (if #f #f)))

  ;; query : Database String Value ... -> (Listof Row)
  ;; Every row SQL answers on DB, GIVEN bound to its parameters, in order,
  ;; each a vector of its values in column order. The call's claim is its
  ;; first expression.
  (define (query db sql . given)
    (let ((claim (made-claim)))
      (with-checked-out 'query claim db sql
        (lambda (st n)
          (and-then (bind-each!/at 'query st given (sectioner claim) n)
                    (lambda (n bound)
                      (let loop ((n n) (rows '()))
                        (let ((s (step-at 'query st claim n)))
                          (cond ((not (eq? (car s) 'answered)) s)
                                ((caddr s)
                                 (and-then (row-at 'query st claim (cadr s))
                                           (lambda (n row) (loop n (cons row rows)))))
                                (else (list 'done (cadr s) (reverse rows))))))))))))

  ;; query-row : Database String Value ... -> (U Row #f)
  ;; The first row SQL answers on DB, GIVEN bound to its parameters, or #f
  ;; when it answers none; a second row is never stepped to, and the
  ;; statement is reset after the first (the M3 plan's Q3). The reset that
  ;; commits a multi-row insert ... returning in autocommit can fail, BUSY
  ;; under another's read, rolling the insert back, and that raises
  ;; (ADR-0016, decision 5). The call's claim is its first expression.
  (define (query-row db sql . given)
    (let ((claim (made-claim)))
      (with-checked-out 'query-row claim db sql
        (lambda (st n)
          (and-then (bind-each!/at 'query-row st given (sectioner claim) n)
                    (lambda (n bound)
                      (let ((s (step-at 'query-row st claim n)))
                        (cond ((not (eq? (car s) 'answered)) s)
                              ((caddr s) (row-at 'query-row st claim (cadr s)))
                              (else (list 'done (cadr s) #f))))))))))

  ;; --- query-fold ------------------------------------------------------------------------

  ;; query-fold : Database String (A Row -> A) A Value ... -> A
  ;; (PROC acc row) over every row SQL answers on DB, GIVEN bound to its
  ;; parameters, from SEED, in order, as R6RS fold-left calls its procedure;
  ;; the last answer, SEED when there is no row. PROC is checked first, an
  ;; assertion violation not-a-procedure, then checked-out's checks. PROC
  ;; runs with the statement at its row, so the connection holds the fold's
  ;; read meanwhile (ADR-0016, decision 6; slice 0's P12).
  ;;
  ;; M2's call-with-statement's shape (statement.sls), where it holds:
  ;;   - a plain dynamic-wind around a critical one, both before thunks
  ;;     doing nothing, so a re-entry goes through: a guard whose clauses do
  ;;     not match re-enters the raise's extent to raise again, and a before
  ;;     thunk that refused would put its own condition in the caller's place;
  ;;   - the statement, a cache hit or a fresh prepare, is put in ST inside
  ;;     the section that checks it out or prepares it, by checked-out's
  ;;     on-made, so no escaping interrupt falls between the check-out and the
  ;;     after thunk's knowing of it;
  ;;   - a handler records a raise and hands it on in place, with
  ;;     raise-continuable, over the wind's whole body, the fold's own
  ;;     check-out, binds, steps and reads as well as PROC: so a failure of
  ;;     the fold's own counts as a raise, and the finish's failure is never
  ;;     raised over it. A handler outside that returns, or the body's own
  ;;     return, clears the record;
  ;;   - the critical after thunk finishes the statement, under a guard that
  ;;     records its failure and raises nothing, and the plain after thunk
  ;;     raises that failure, unless a raise is under way.
  ;; And M3's own, since the fold's finish is not idempotent: a statement
  ;; given back to the cache may be another caller's by then:
  ;;   - the critical after thunk finishes once, on the first exit that holds
  ;;     the statement, and sets LEFT, the call's flag. An exit before the
  ;;     hand-over, an engine's expiry inside checked-out, finds no
  ;;     statement, and leaves LEFT unset, so the resumed fold checks one
  ;;     out and runs;
  ;;   - on a normal return the statement is at done, and goes back to the
  ;;     cache; on any other exit, a raise or an escape, it is finalized,
  ;;     never kept (ADR-0020, decision 5);
  ;;   - every section that touches the statement reads LEFT first: the
  ;;     check-out's and a miss's prepare's, through checked-out's LEFT?;
  ;;     each bind's; and every step's, the column count's read's and every
  ;;     column's, through while-held; and the loop reads it again after
  ;;     every call of PROC. Once it is set the fold raises &sqlite-closed
  ;;     from query-fold, never touching the statement, which may be in the
  ;;     cache by then, or another caller's: so a fold re-entered after any
  ;;     exit, through a continuation captured in PROC or in a timer's
  ;;     handler, or a PROC resumed by an outer handler returning to a
  ;;     raise-continuable past a guard that re-entered, or an engine's
  ;;     remainder resumed a second time, is refused at once, and never
  ;;     restarts from the first row nor checks the statement out again.
  ;;     Read in the step's own section, no engine's expiry falls between
  ;;     the read and the step it guards (ADR-0017, amended in M3 slice 1).
  ;;     A re-entry past the loop's last section meets only the critical
  ;;     after thunk, which finds LEFT set and does nothing, and answers the
  ;;     fold again;
  ;; An escape that is no raise, PROC leaving through a continuation, raises
  ;; the finish's failure from the plain after thunk, as call-with-statement
  ;; raises its finalize's. An engine's expiry inside the wind is such an
  ;; escape, and finalizes the statement, so the resumed loop raises
  ;; &sqlite-closed: query-fold does not survive an engine's preemption.
  (define (query-fold db sql proc seed . given)
    (let ((who 'query-fold))
      (unless (procedure? proc)
        (assertion-violation who "the procedure is no procedure" 'not-a-procedure
                             (shown-value proc)))
      (let ((st #f) (left #f) (normal #f) (raising #f) (finish-failure #f))
        ;; left? : -> Boolean
        ;; The call's check: whether its statement has left it.
        (define (left?) left)
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
                   (call-with-values
                    (lambda ()
                      (checked-out who db sql (lambda (made) (set! st made)) left?)
                      (bind-each!/who who st given left?)
                      (let loop ((acc seed))
                        (if (stepped who st left?)
                            (let ((next (proc acc (row-of who st left?))))
                              (when left (raise-closed who))
                              (loop next))
                            acc)))
                    (lambda answers
                      (set! raising #f)
                      (set! normal #t)
                      (apply values answers))))))
              (lambda ()
                (when (and st (not left))
                  (set! left #t)
                  (set! finish-failure
                        (guard (e (#t (list e)))
                          (if normal (returned who st) (finalized who st))
                          #f))))))
          (lambda ()
            (let ((failure finish-failure))
              (set! finish-failure #f)
              (when (and failure (not raising))
                (raise (car failure)))))))))

  ;; --- execute-script! ------------------------------------------------------------------

  ;; code-number : Any -> (U Integer #f)
  ;; The extended code an &sqlite-error's field names: the integer itself,
  ;; for a code the constants' table lacks, else the table's number for the
  ;; name; #f for anything else. Pure, total. A step's failure raised by
  ;; raise-sqlite-error always names a code, so the #f branch hands that
  ;; condition on unchanged; the integer branch is reached only by a code
  ;; newer than the table, which no suite can make SQLite answer, so
  ;; test-execute-script holds the branches here, on synthetic inputs.
  (define (code-number code)
    (cond ((and (integer? code) (exact? code)) code)
          ((and (symbol? code) (assq code sqlite-result-codes)) => cdr)
          (else #f)))

  ;; execute-script! : Database String -> Void
  ;; SQL, a script, run on DB statement by statement, with no parameters
  ;; (ADR-0016, decision 7; the M3 plan's Q4). The checks first: DB a
  ;; database, on its owning thread; SQL by checked-sql, a string holding no
  ;; U+0000, refused before anything is allocated; DB open, at the first
  ;; prepare's section. Then a loop of prepares, never sqlite3_exec, each
  ;; from the tail of the statement before it, through prepared-at, with no
  ;; flags and no cache, from one block holding the whole script's C string:
  ;; each statement is prepared only once the one before it has run, since
  ;; preparing a PRAGMA applies it (single P3), stepped to done, its rows
  ;; dropped, and finalized. The loop ends at the script's end, or at a NULL
  ;; statement, whose tail was the input's end in every case measured
  ;; (slice 0's P11): so SQL holding no statement is no error. It stops at
  ;; the first error, the statements before it standing, and begins, ends or
  ;; rolls back no transaction of its own (single script X1 to X4, X16).
  ;;
  ;; Its &sqlite-error carries the whole script, as checked, as sql, and an
  ;; offset into it, in characters, that says which statement failed,
  ;; rebuilt by raise-sqlite-error from the failure's extended code and
  ;; message, so its class comes from the primary code again: for a
  ;; prepare's, script-prepare-offset of SQLite's offset from the
  ;; statement's start; for a step's, which SQLite gives no offset,
  ;; script-step-offset, the failing statement's first token (ADR-0016,
  ;; decision 7, amended in M3 slice 1).
  ;;
  ;; The call's flag, BEGUN, is made first, unset, and marked by the first
  ;; prepare's section, which reads it first: so a call re-entered before
  ;; its block, through a continuation or an engine's remainder resumed a
  ;; second time, makes a block of its own, and its first prepare refuses,
  ;; &sqlite-closed from execute-script!, rather than running the script
  ;; again. Inside the block, call-with-block refuses a re-entry itself.
  ;;
  ;; Nothing raises out of the block's extent: call-with-block refuses a
  ;; re-entry, so a non-matching guard's re-raise there would be replaced by
  ;; its refusal. Every raise in the loop is caught inside the extent and
  ;; answered as data, and raised after call-with-c-string returns: SQLite's
  ;; failures rebuilt, anything else as the same object. Each statement is
  ;; finished on every way out of its own critical dynamic-wind, finalized by
  ;; its after thunk unless the loop finalized it already, and the after
  ;; thunk raises nothing. An engine's expiry inside the block's extent is
  ;; such a way out: it finalizes the statement, and frees the block, so the
  ;; engine's resume is refused by call-with-block, from execute-script!:
  ;; execute-script! does not survive an engine's preemption.
  (define (execute-script! db sql)
    (let ((who 'execute-script!) (begun #f))
      ;; begin! : -> Boolean
      ;; Whether the call's run had begun, marking it begun: the first
      ;; prepare's check, evaluated in its section.
      (define (begin!) (let ((was begun)) (set! begun #t) was))
      (check-database-owner who db)
      (let-values (((copy bytes) (checked-sql who sql)))
        (let ((outcome (call-with-c-string who copy
                         (lambda (block)
                           (guard (c (#t (list 'raised c)))
                             (script-run who db copy bytes block begin!))))))
          (case (car outcome)
            ((done) (if #f #f))
            ((prepare-failed)
             (let ((failed (cdr outcome)))
               ;; (CODE MESSAGE START OFFSET)
               (raise-sqlite-error who (car failed) (cadr failed) copy
                                   (script-prepare-offset bytes (caddr failed) (cadddr failed)))))
            ((step-failed)
             (let* ((c (cadr outcome))
                    (code (code-number (sqlite-error-extended-code c))))
               (if code
                   (raise-sqlite-error who code (sqlite-error-message c) copy
                                       (script-step-offset bytes (caddr outcome)))
                   (raise c))))
            (else (raise (cadr outcome))))))))

  ;; script-run : Symbol Database String Bytevector Positive-Integer (-> Boolean)
  ;;   -> (U (List 'done) (List 'prepare-failed Integer String Natural Integer)
  ;;         (List 'step-failed Condition Natural))
  ;; The script SQL, BYTES its UTF-8 and BLOCK its C string, run statement
  ;; by statement, from byte 0, for WHO: done at the script's end or at a
  ;; NULL statement; else the first failure, as data. What anything else
  ;; raises reaches the caller's guard, inside the block's extent. The first
  ;; prepare always runs, so a closed DB is refused even for an empty script,
  ;; and its section evaluates BEGIN!, the call's check, first: the run
  ;; marked begun, or &sqlite-closed when it had begun already. The later
  ;; prepares take no check: call-with-block refuses a re-entry into the
  ;; block's extent, so none is reached again.
  (define (script-run who db sql bytes block begin!)
    (let ((end (bytevector-length bytes)))
      (let loop ((start 0) (check begin!))
        (let ((next (script-statement who db sql bytes block start check)))
          (cond ((pair? next) next)
                ((>= next end) '(done))
                (else (loop next #f)))))))

  ;; script-statement : Symbol Database String Bytevector Positive-Integer Natural
  ;;                    (U (-> Boolean) #f)
  ;;   -> (U Natural (List 'done) (List 'prepare-failed Integer String Natural Integer)
  ;;         (List 'step-failed Condition Natural))
  ;; The statement from byte START prepared by prepared-at, with no flags
  ;; and CHECK, the call's check or #f, handed to ST inside the prepare's
  ;; section; stepped to done, its rows
  ;; dropped, and finalized: the tail's byte offset, where the next begins.
  ;; done for a NULL statement; (prepare-failed CODE MESSAGE START OFFSET)
  ;; for a failed prepare, its answers as prepared-at gives them; and
  ;; (step-failed C START) for a step that raised C, an &sqlite-error, once
  ;; the statement is finalized, which repeats the step's code and raises
  ;; nothing. The critical wind's after thunk finalizes ST on every other
  ;; way out, and raises nothing: a finalize of a finalized statement does
  ;; nothing, so no flag is needed.
  (define (script-statement who db sql bytes block start check)
    (let ((st #f))
      (dynamic-wind #t
        (lambda () #f)
        (lambda ()
          (let ((made (prepared-at who db sql bytes block start 0 (lambda (s) (set! st s)) check)))
            (case (car made)
              ((empty) '(done))
              ((failed)
               (list 'prepare-failed (cadr made) (caddr made) start (cadddr made)))
              (else
               (let ((failure (guard (c ((sqlite-error? c) c))
                                (let steps () (when (step!/who who st) (steps)))
                                #f)))
                 (finalized who st)
                 (if failure
                     (list 'step-failed failure start)
                     (caddr made)))))))
        (lambda ()
          (when st
            (guard (e (#t #f)) (finalized who st))))))))
