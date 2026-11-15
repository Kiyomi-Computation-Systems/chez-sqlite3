#!r6rs
;;; (chez-sqlite3 private statement): prepared statements, from prepare to
;;; finalize, owned by their connection (ADR-0014; ADR-0010, decision 2).
;;; (chez-sqlite3) exports its public verbs; call-with-statement-handle, the
;;; one way to a statement's handle, is slice 4's too, and statement-state and
;;; sql-length-fits? are exported for the suites.
;;;
;;; A statement is a statement record, opaque and sealed, holding the
;;; sqlite3_stmt* as an integer, #f once finalized; its database; a copy of
;;; the SQL it was given; and its live state, ready, row, done or failed
;;; (ADR-0014, decisions 2 and 5). The handle alone says it is finalized: a
;;; record that kept a freed address would pass every check. No accessor of
;;; its handle escapes this library but call-with-statement-handle, which
;;; checks first.
;;;
;;; Every verb checks, in order, before anything reaches C (decision 3):
;;;
;;;   1. a statement        else an assertion violation, not-a-statement
;;;   2. the owning thread  the connection's, else &sqlite-wrong-thread
;;;   3. not finalized      else &sqlite-closed, its who the verb; a
;;;                         statement whose connection is closed is
;;;                         finalized too, and refused the same way
;;;   4. the state          by statement-verb-check, else an assertion
;;;                         violation naming the state, the state unchanged
;;;
;;; finalize-statement! makes the first two alone: on a finalized statement
;;; it does nothing.
;;;
;;; A verb reaches its connection's handle only through the connection's
;;; call-with-open-handle, and a statement's only through
;;; call-with-statement-handle, which runs inside it: so each verb holds one
;;; critical section, in which the checks 3 and 4, the C call, sqlite3_errmsg
;;; read straight after it, the state's change, the tracking and the count
;;; change together (decision 10). Nothing raises in it. It answers data, and
;;; the raise follows it, so a with-exception-handler handler of a verb's
;;; raise runs with interrupts enabled (ADR-0012, amended). prepare-statement
;;; holds the SQL's C string, its two out-parameters, the prepare, the tail's
;;; scan and the statement's tracking in that one section, so no engine's
;;; expiry frees a block between them (ADR-0011, amended).
;;;
;;;   prepare   the SQL copied, then checked: a string; no U+0000, which C
;;;             would read as its end; at most 2^31-2 bytes of UTF-8, so its
;;;             nByte, the bytes and their NUL, fits C's int (ADR-0011,
;;;             amended). Each before anything is allocated. Then
;;;             sqlite3_prepare_v3, with no flags; a failure raises
;;;             &sqlite-error with the SQL and the offset as a character
;;;             index, #f for -1; a NULL statement is refused, no-statement;
;;;             the tail is scanned (sql-tail-statement), never prepared, and
;;;             anything there is refused, more-than-one-statement, at its
;;;             character index, once the statement is finalized. Else the
;;;             statement is counted, tracked by its connection, and ready.
;;;   step!     sqlite3_step: row gives #t, done #f, anything else failed and
;;;             &sqlite-error from the step's own code, which is extended,
;;;             with the statement's SQL and no offset (decision 6)
;;;   reset!    sqlite3_reset, then ready whatever it answered; a failure of
;;;             its own, by finish-failure, raises (decision 7)
;;;   finalize  sqlite3_finalize, then the handle cleared, the statement
;;;             finalized, untracked and counted down whatever it answered;
;;;             then a failure of its own, by finish-failure, raises
;;;
;;; Every refusal of a caller's mistake is an assertion violation whose
;;; irritants begin with a symbol naming its rule, then the value by
;;; shown-value, never a string's text (ADR-0013, decisions 7 and 9).
(library (chez-sqlite3 private statement)
  (export prepare-statement finalize-statement! call-with-statement statement?
          statement-sql parameter-count step! reset! column-count
          call-with-statement-handle statement-state sql-length-fits?)
  (import (chez-sqlite3 private require-threaded)
          (except (rnrs) dynamic-wind)
          (only (chezscheme) dynamic-wind)
          (chez-sqlite3 private native)
          (chez-sqlite3 private counters)
          (only (chez-sqlite3 private constants) sqlite-result-codes)
          (chez-sqlite3 private conditions)
          (chez-sqlite3 private connection)
          (chez-sqlite3 private statement-state)
          (chez-sqlite3 private sql-tail)
          (chez-sqlite3 private utf8))

  (define sqlite-ok (cdr (assq 'ok sqlite-result-codes)))

  ;; statement? : Any -> Boolean
  ;; Opaque, so record-rtd on a statement raises, and sealed, so no type
  ;; extends it; not nongenerative, so no other definition makes its type.
  (define-record-type statement
    (fields (mutable handle unchecked-statement-handle set-statement-handle!)
            (immutable database unchecked-statement-database)
            (immutable sql unchecked-statement-sql)
            (mutable state unchecked-statement-state set-statement-state!))
    (sealed #t)
    (opaque #t))

  ;; --- the checks ------------------------------------------------------------------

  ;; check-who : Symbol Any -> Void
  (define (check-who helper who)
    (unless (symbol? who)
      (assertion-violation helper "a who is a symbol" 'not-a-who (shown-value who))))

  ;; check-statement : Symbol Any -> Void
  (define (check-statement who st)
    (unless (statement? st)
      (assertion-violation who "not a statement" 'not-a-statement (shown-value st))))

  ;; state-of : Statement -> Symbol
  ;; ST's state in statement-states: finalized when its handle is #f, else
  ;; its live state.
  (define (state-of st)
    (if (unchecked-statement-handle st) (unchecked-statement-state st) 'finalized))

  ;; statement-state : Statement -> Symbol
  ;; ST's state: ready, row, done, failed or finalized. A ST that is no
  ;; statement is an assertion violation from statement-state. It makes no
  ;; other check, and reaches no C: for the suites, which assert a verb's
  ;; whole outcome, its state among it.
  (define (statement-state st)
    (check-statement 'statement-state st)
    (state-of st))

  ;; sql-max-bytes : Natural
  ;; The most UTF-8 bytes a statement's SQL may have: prepare passes them and
  ;; their NUL as nByte, a C int, whose largest value is 2^31-1.
  (define sql-max-bytes (- (expt 2 31) 2))

  ;; sql-length-fits? : Any -> Boolean
  ;; Whether SQL of N bytes of UTF-8, passed with its NUL as nByte, fits C's
  ;; int: N an exact natural no greater than 2^31-2. Chez's int would take up
  ;; to 2^32-1, handing 2^31 and above to C as negative numbers, and raise
  ;; beyond, inside the prepare's section (ADR-0011, amended). Pure, total.
  (define (sql-length-fits? n)
    (and (integer? n) (exact? n) (<= 0 n sql-max-bytes)))

  ;; holds-nul? : String -> Boolean
  (define (holds-nul? s)
    (let loop ((i 0))
      (and (< i (string-length s))
           (or (char=? (string-ref s i) #\nul) (loop (+ i 1))))))

  ;; --- the one accessor of a statement's handle -------------------------------------

  ;; call-with-statement-handle : Symbol Any Symbol
  ;;   (Positive-Integer Positive-Integer String -> (Values (U Live-State #f) A ...)) -> A ...
  ;; Live-State = (U 'ready 'row 'done 'failed)
  ;; The answers PROC gives after its first, PROC given the connection's
  ;; handle, the statement's, and the statement's SQL, once ST is checked for VERB, one of
  ;; statement-verbs, by decision 3, in order:
  ;;   - a statement, else an assertion violation from WHO, not-a-statement;
  ;;   - on its connection's owning thread, else &sqlite-wrong-thread from WHO;
  ;;   - not finalized, else &sqlite-closed from WHO; a statement whose
  ;;     connection is closed is finalized, since the close finalized it;
  ;;   - VERB allowed in its state, by statement-verb-check, else an
  ;;     assertion violation from WHO, not-allowed-in-state, naming the state.
  ;; For finalize-statement!, which statement-verb-check allows in every
  ;; state and makes a no-op once finalized, the third check is none: a
  ;; finalized statement, or one whose connection is closed, answers one
  ;; unspecified value, and PROC never runs. A WHO that is no symbol and a VERB that is
  ;; none are assertion violations from call-with-statement-handle, and a
  ;; PROC that is no procedure one from WHO, before anything else.
  ;;
  ;; PROC's first answer is the state SQLite's answers leave ST in: #f leaves
  ;; it as it was; ready, row, done or failed becomes ST's state, set in the
  ;; same section, before anything else can see ST. So step! answers the
  ;; state its step leaves, reset! ready, and a slice 4 read that SQLite
  ;; answered with a failure can answer failed. Anything else as the first
  ;; answer, or no answer at all, is an assertion violation from
  ;; call-with-statement-handle, not-a-live-state, naming it, raised after
  ;; the section with ST's state unchanged and PROC's other answers dropped:
  ;; finalized among it, since only a finalize, clearing the handle, makes a
  ;; statement finalized. A refusal before PROC never changes the state.
  ;;
  ;; The SQL PROC is given is the copy made at prepare, which never changes:
  ;; a failure PROC answers carries it, with no read of ST after the section,
  ;; which a finalize by another engine could refuse (ADR-0013, amended).
  ;;
  ;; PROC runs inside the connection's call-with-open-handle, in its critical
  ;; section, with the third and fourth checks: no engine, interrupt or
  ;; other verb on this thread can finalize ST, or close its connection,
  ;; between the checks and PROC's use of the handles. PROC runs with
  ;; interrupts disabled, so it keeps to its C calls and their reads, and
  ;; answers data: a raise is raised again after the section, as the same
  ;; object, and the state is left as it was. Every refusal here is raised
  ;; after the section. Slice 4's verbs call it, each reading the column
  ;; count in PROC, with the read it guards.
  (define (call-with-statement-handle who st verb proc)
    (check-who 'call-with-statement-handle who)
    (unless (memq verb statement-verbs)
      (assertion-violation 'call-with-statement-handle "not a statement verb"
                           'not-a-statement-verb (shown-value verb)))
    (unless (procedure? proc)
      (assertion-violation who "not a procedure" 'not-a-procedure (shown-value proc)))
    (check-statement who st)
    (let ((outcome (open-outcome who st verb proc)))
      (case (car outcome)
        ((answered) (apply values (cdr outcome)))
        ((finalized) (raise-closed who))
        ((refused)
         (assertion-violation who "the statement's state does not allow this verb"
                              'not-allowed-in-state (cadr outcome)))
        ((not-a-live-state)
         (assertion-violation 'call-with-statement-handle
                              "a procedure's first answer is the state it leaves, or #f"
                              'not-a-live-state (cadr outcome)))
        (else (if #f #f)))))

  ;; live-states : (Listof Symbol)
  ;; The states a procedure may give a statement: all but finalized.
  (define live-states '(ready row done failed))

  ;; moved : Statement (Listof Any)
  ;;         -> (U (Pairof 'answered (Listof Any)) (List 'not-a-live-state Any))
  ;; ANSWERS, PROC's, taken in the section: its first set as ST's state when
  ;; it is a live state, nothing when it is #f; then the rest answered. A
  ;; first answer that is neither, or none, is refused, by shown-value.
  (define (moved st answers)
    (cond ((null? answers) (list 'not-a-live-state 'no-answer))
          ((not (car answers)) (cons 'answered (cdr answers)))
          ((memq (car answers) live-states)
           (set-statement-state! st (car answers))
           (cons 'answered (cdr answers)))
          (else (list 'not-a-live-state (shown-value (car answers))))))

  ;; open-outcome : Symbol Statement Symbol Procedure
  ;;                -> (U (Pairof 'answered (Listof Any)) (List 'finalized)
  ;;                      (List 'refused Symbol) (List 'not-a-live-state Any)
  ;;                      (List 'no-op))
  ;; What call-with-open-handle's section decided for ST and VERB, PROC's
  ;; answers among it. A closed connection is &sqlite-closed from
  ;; call-with-open-handle, raised after its section; for a VERB that is a
  ;; no-op once finalized it is no-op, caught here, outside any section.
  (define (open-outcome who st verb proc)
    (let ((no-op-when-finalized (eq? (statement-verb-check verb 'finalized) 'no-op)))
      (guard (c ((and no-op-when-finalized (sqlite-closed? c)) '(no-op)))
        (call-with-open-handle who (unchecked-statement-database st)
          (lambda (connection)
            (let ((check (statement-verb-check verb (state-of st))))
              (cond ((eq? check 'allowed)
                     (call-with-values (lambda () (proc connection (unchecked-statement-handle st)
                                                      (unchecked-statement-sql st)))
                       (lambda answers (moved st answers))))
                    ((eq? check 'no-op) '(no-op))
                    ((eq? check 'closed) '(finalized))
                    (else check))))))))

  ;; --- what SQLite said --------------------------------------------------------------

  ;; message-of : Positive-Integer Integer -> String
  ;; sqlite3_errmsg of CONNECTION, read straight after the call that answered
  ;; CODE, on the owning thread; sqlite3_errstr of CODE when errmsg answers
  ;; NULL; empty when that does too.
  (define (message-of connection code)
    (or (c-string->string (sqlite3-errmsg connection))
        (c-string->string (sqlite3-errstr code))
        ""))

  ;; raise-failure : Symbol (List 'failed Integer String String) -> Nothing
  ;; A statement's failure, (failed CODE MESSAGE SQL), as an &sqlite-error
  ;; from WHO carrying SQL and no offset, classed by raise-sqlite-error.
  (define (raise-failure who failure)
    (raise-sqlite-error who (cadr failure) (caddr failure) (cadddr failure) #f))

  ;; --- finalizing ----------------------------------------------------------------------

  ;; finalize-handle! : Statement Positive-Integer
  ;;                    -> (U 'finalized (List 'failed Integer String String)
  ;;                          (List 'raised Any))
  ;; ST finalized, CONNECTION its connection's handle, inside a critical
  ;; section that holds both: sqlite3_finalize, then, whatever it answered,
  ;; since SQLite has freed the statement, the handle cleared, which makes it
  ;; finalized, and the count down. It answers finalized; or (failed CODE
  ;; MESSAGE SQL) when finish-failure finds the answer a failure of the
  ;; finalize's own, MESSAGE read straight after it; or (raised C) for
  ;; count-down!'s double free. A statement finalized already answers
  ;; finalized and reaches no C. It raises nothing, and leaves the tracking
  ;; to its caller. It is the connection's entry for ST: the close calls it
  ;; for each statement it tracks (connection.sls).
  (define (finalize-handle! st connection)
    (let ((handle (unchecked-statement-handle st)))
      (if (not handle)
          'finalized
          (let* ((state (unchecked-statement-state st))
                 (answer (sqlite3-finalize handle))
                 (failure (finish-failure state answer))
                 (message (and failure (message-of connection answer))))
            (set-statement-handle! st #f)
            (let ((double-free (guard (c (#t c)) (count-down! 'statement) #f)))
              (cond (failure (list 'failed failure message (string-copy (unchecked-statement-sql st))))
                    (double-free (list 'raised double-free))
                    (else 'finalized)))))))

  ;; finalized : Symbol Statement -> Void
  ;; ST finalized, for WHO, and untracked by its connection, in one section;
  ;; then its failure, if any, raised from WHO. The first two checks alone.
  (define (finalized who st)
    (let ((outcome
           (call-with-statement-handle who st 'finalize-statement!
             (lambda (connection handle sql)
               (let ((outcome (finalize-handle! st connection)))
                 (untrack-statement! (unchecked-statement-database st) st)
                 (values #f outcome))))))
      (cond ((not (pair? outcome)) (if #f #f))
            ((eq? (car outcome) 'failed) (raise-failure who outcome))
            (else (raise (cadr outcome))))))

  ;; finalize-statement! : Statement -> Void
  ;; ST finalized, whatever its state, and no longer tracked by its
  ;; connection; nothing when it is finalized already, or its connection
  ;; closed. A failure of the finalize's own, such as the commit of an
  ;; insert ... returning stepped once, then raises &sqlite-error; a failed
  ;; step's code, which the finalize repeats, does not (ADR-0014, decision 7).
  (define (finalize-statement! st)
    (finalized 'finalize-statement! st))

  ;; --- preparing ------------------------------------------------------------------------

  ;; checked-sql : Symbol Any -> (Values String Bytevector)
  ;; SQL, copied, and the copy's UTF-8, once checked, for WHO: a SQL that is
  ;; no string, a copy holding U+0000, and one of more than sql-max-bytes
  ;; bytes, are assertion violations from WHO, before anything is allocated.
  ;; The caller's string is copied first and the copy alone is checked and
  ;; prepared, so another thread cannot change it between the two (ADR-0011,
  ;; decision 2).
  (define (checked-sql who sql)
    (unless (string? sql)
      (assertion-violation who "SQL is a string" 'not-a-string (shown-value sql)))
    (let ((copy (string-copy sql)))
      (when (holds-nul? copy)
        (assertion-violation who "SQL holding U+0000, where C would read its end"
                             'sql-holds-nul (shown-value copy)))
      (let ((bytes (string->utf8 copy)))
        (unless (sql-length-fits? (bytevector-length bytes))
          (assertion-violation who "SQL longer than 2^31-2 bytes of UTF-8, which C's int cannot count"
                               'sql-too-long (bytevector-length bytes)))
        (values copy bytes))))

  ;; prepare-outcome : Symbol Database String Bytevector (U (Statement -> Any) #f)
  ;;   -> (U (List 'prepared Statement) (List 'failed Integer String (U Natural #f))
  ;;         (List 'empty) (List 'more Natural))
  ;; COPY prepared on DB, BYTES its UTF-8, in call-with-open-handle's section:
  ;; the C string, the statement's and the tail's out-parameters, the
  ;; prepare, sqlite3_errmsg and sqlite3_error_offset read straight after a
  ;; failure, the count, the tail's scan, and either the finalize of a
  ;; statement with more after it, or the record, its tracking and ON-MADE
  ;; called with it, which call-with-statement uses to learn of it in the
  ;; same section. Answers the statement; or the failure's code, message and
  ;; character offset; or empty for a NULL statement; or more, with the byte
  ;; offset of what the tail holds.
  (define (prepare-outcome who db copy bytes on-made)
    (call-with-open-handle who db
      (lambda (connection)
        (call-with-c-string who copy
          (lambda (c-sql)
            (let-values (((inner tail)
                          (call-with-out-pointer who
                            (lambda (tail-slot)
                              (let-values (((answer statement)
                                            (call-with-out-pointer who
                                              (lambda (statement-slot)
                                                (let ((rc (sqlite3-prepare-v3 connection c-sql
                                                                              (+ (bytevector-length bytes) 1)
                                                                              0 statement-slot tail-slot)))
                                                  (if (eqv? rc sqlite-ok)
                                                      (list rc)
                                                      (list rc (message-of connection rc)
                                                            (sqlite3-error-offset connection))))))))
                                (cons statement answer))))))
              (made-outcome who db copy bytes on-made (car inner) (cdr inner) (- tail c-sql))))))))

  ;; made-outcome : Symbol Database String Bytevector (U Procedure #f) Natural
  ;;                (Pairof Integer (Listof Any)) Integer -> Prepare-Outcome
  ;; What prepare-outcome answers, once the prepare has returned STATEMENT,
  ;; ANSWER its code and, for a failure, the message and offset, and TAIL the
  ;; tail's byte offset. Inside the same section.
  (define (made-outcome who db copy bytes on-made statement answer tail)
    (cond
      ((not (eqv? (car answer) sqlite-ok))
       (list 'failed (car answer) (cadr answer) (utf8-offset->index bytes (caddr answer))))
      ((eqv? statement 0) '(empty))
      (else
       (count-up! 'statement)
       (let ((more (sql-tail-statement bytes tail)))
         (if more
             ;; Never stepped, so its finalize has nothing to commit, and
             ;; answers SQLITE_OK.
             (begin (sqlite3-finalize statement)
                    (count-down! 'statement)
                    (list 'more more))
             (let ((st (make-statement statement db copy 'ready)))
               (track-statement! db st (lambda (connection) (finalize-handle! st connection)))
               (when on-made (on-made st))
               (list 'prepared st)))))))

  ;; prepared : Symbol Any Any (U (Statement -> Any) #f) -> Statement
  ;; SQL prepared on DB, for WHO, by the checks in order: DB a database, on
  ;; its owning thread; SQL by checked-sql; DB open, in the section. Each
  ;; refusal, and the prepare's failure, raised after the section.
  (define (prepared who db sql on-made)
    (check-database-owner who db)
    (let-values (((copy bytes) (checked-sql who sql)))
      (let ((outcome (prepare-outcome who db copy bytes on-made)))
        (case (car outcome)
          ((prepared) (cadr outcome))
          ((failed) (raise-sqlite-error who (cadr outcome) (caddr outcome) copy (cadddr outcome)))
          ((empty)
           (assertion-violation who "SQL holding no statement" 'no-statement (shown-value copy)))
          (else
           (assertion-violation who "SQL holding more than one statement"
                                'more-than-one-statement
                                (utf8-offset->index bytes (cadr outcome))))))))

  ;; prepare-statement : Database String -> Statement
  ;; SQL, one statement, prepared on DB, ready and tracked by DB until it is
  ;; finalized. SQL holding no statement, or more than one, is refused, the
  ;; second once its first statement is prepared, so that statement's
  ;; prepare-time effects stand: pragma cache_size = 7; select 1 sets the
  ;; cache size (ADR-0014, consequences).
  (define (prepare-statement db sql)
    (prepared 'prepare-statement db sql #f))

  ;; --- call-with-statement ------------------------------------------------------------

  ;; call-with-statement : Database String (Statement -> A ...) -> A ...
  ;; PROC's answers, PROC given SQL prepared on DB (ADR-0014, decision 7).
  ;; PROC is checked first, then prepare-statement's checks, before anything
  ;; is prepared. Then:
  ;;   - PROC returns, or leaves through a continuation: the statement is
  ;;     finalized, and that finalize's failure raises;
  ;;   - PROC raises: the statement is finalized, and PROC's condition
  ;;     reaches the caller unchanged; a failure of that finalize is not
  ;;     raised over it;
  ;;   - a continuation that re-enters PROC finds the statement finalized.
  ;; The statement is freed either way. As call-with-database tells a raise
  ;; from an escape: a handler around PROC records a raise and hands it on
  ;; in place, with raise-continuable, and PROC's return, or a handler
  ;; outside that returns, clears it; the before thunks do nothing. The
  ;; prepare learns its statement inside its own section, so no interrupt
  ;; falls between the prepare and the after thunk's knowing of it; the
  ;; winder is Chez's critical form, and its after thunk finalizes, recording
  ;; a failure and raising nothing; a plain winder around it raises that
  ;; failure once the critical one is left, unless PROC is raising. An
  ;; engine's expiry is an escape: the statement does not survive one.
  ;; Everything raised names call-with-statement.
  (define (call-with-statement db sql proc)
    (let ((who 'call-with-statement))
      (unless (procedure? proc)
        (assertion-violation who "the procedure is no procedure" 'not-a-procedure
                             (shown-value proc)))
      (let ((st #f) (raising #f) (finalize-failure #f))
        (dynamic-wind
          (lambda () #f)
          (lambda ()
            (dynamic-wind #t
              (lambda () #f)
              (lambda ()
                (prepared who db sql (lambda (made) (set! st made)))
                (with-exception-handler
                 (lambda (c)
                   (set! raising (list c))
                   (call-with-values
                    (lambda () (raise-continuable c))
                    (lambda answers (set! raising #f) (apply values answers))))
                 (lambda ()
                   (call-with-values
                    (lambda () (proc st))
                    (lambda answers (set! raising #f) (apply values answers))))))
              (lambda ()
                (when st
                  (set! finalize-failure
                        (guard (e (#t (list e)))
                          (finalized who st)
                          #f))))))
          (lambda ()
            (let ((failure finalize-failure))
              (set! finalize-failure #f)
              (when (and failure (not raising))
                (raise (car failure)))))))))

  ;; --- the verbs -------------------------------------------------------------------------

  ;; statement-sql : Statement -> String
  ;; A fresh copy of the SQL ST was prepared from.
  (define (statement-sql st)
    (call-with-statement-handle 'statement-sql st 'statement-sql
      (lambda (connection handle sql) (values #f #t)))
    (string-copy (unchecked-statement-sql st)))

  ;; parameter-count : Statement -> Natural
  ;; ST's largest parameter index, sqlite3_bind_parameter_count's answer.
  (define (parameter-count st)
    (call-with-statement-handle 'parameter-count st 'parameter-count
      (lambda (connection handle sql) (values #f (sqlite3-bind-parameter-count handle)))))

  ;; column-count : Statement -> Natural
  ;; How many columns ST's rows have now, sqlite3_column_count's answer, read
  ;; afresh at every call: another connection's change to a table changes it
  ;; at the next step (ADR-0014, decision 5).
  (define (column-count st)
    (call-with-statement-handle 'column-count st 'column-count
      (lambda (connection handle sql) (values #f (sqlite3-column-count handle)))))

  ;; step! : Statement -> Boolean
  ;; #t when sqlite3_step has a row ready, the state row; #f when it has
  ;; finished, done. Any other answer leaves ST failed and raises
  ;; &sqlite-error from the step's own code, with ST's SQL. Allowed in ready
  ;; and row only: a done or failed statement is refused until reset!.
  (define (step! st)
    (let ((outcome
           (call-with-statement-handle 'step! st 'step!
             (lambda (connection handle sql)
               (let* ((answer (sqlite3-step handle))
                      (state (state-after-step answer)))
                 (values state
                         (if (eq? state 'failed)
                             (list 'failed answer (message-of connection answer)
                                   (string-copy sql))
                             state)))))))
      (cond ((eq? outcome 'row) #t)
            ((eq? outcome 'done) #f)
            (else (raise-failure 'step! outcome)))))

  ;; reset! : Statement -> Void
  ;; ST rewound, ready again, its bindings kept, whatever sqlite3_reset
  ;; answered. A failure of the reset's own, such as the commit of an insert
  ;; ... returning stepped once, then raises &sqlite-error; a failed step's
  ;; code, which the reset repeats, does not (ADR-0014, decision 7).
  (define (reset! st)
    (let ((outcome
           (call-with-statement-handle 'reset! st 'reset!
             (lambda (connection handle sql)
               (let* ((state (unchecked-statement-state st))
                      (answer (sqlite3-reset handle))
                      (failure (finish-failure state answer))
                      (message (and failure (message-of connection answer))))
                 (values 'ready
                         (and failure
                              (list 'failed failure message (string-copy sql)))))))))
      (when outcome (raise-failure 'reset! outcome)))))
