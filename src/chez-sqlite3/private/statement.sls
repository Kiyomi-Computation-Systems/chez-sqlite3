#!r6rs
;;; (chez-sqlite3 private statement): prepared statements, from prepare to
;;; finalize, owned by their connection (ADR-0014; ADR-0010).
;;; (chez-sqlite3) exports its public verbs; call-with-statement-handle, the
;;; one way to a statement's handle, is (chez-sqlite3 private
;;; statement-values)' too, and statement-state and sql-length-fits? are
;;; exported for the suites.
;;;
;;; A statement is a statement record, opaque and sealed, holding the
;;; sqlite3_stmt* as an integer, #f once finalized; its database; a copy of
;;; the SQL it was given; and its live state, ready, row, done or failed
;;; (ADR-0014). The handle alone says it is finalized: a record that kept a
;;; freed address would pass every check. No accessor of its handle escapes
;;; this library but call-with-statement-handle, which checks first.
;;;
;;; Every verb checks, in order, before anything reaches C:
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
;;; change together. Nothing raises in it. It answers data, and the raise
;;; follows it, so a with-exception-handler handler of a verb's raise runs
;;; with interrupts enabled (ADR-0012). prepare-statement holds the SQL's C
;;; string, its two out-parameters, the prepare, the tail's scan and the
;;; statement's tracking in that one section, so no engine's expiry frees a
;;; block between them (ADR-0011).
;;;
;;;   prepare   the SQL copied, then checked: a string; no U+0000, which C
;;;             would read as its end; at most 2^31-2 bytes of UTF-8, so its
;;;             nByte, the bytes and their NUL, fits C's int (ADR-0011).
;;;             Each before anything is allocated. Then
;;;             sqlite3_prepare_v3, with no flags; a failure raises
;;;             &sqlite-error with the SQL and the offset as a character
;;;             index, #f for -1; a NULL statement is refused, no-statement;
;;;             the tail is scanned (sql-tail-statement), never prepared, and
;;;             anything there is refused, more-than-one-statement, at its
;;;             character index, once the statement is finalized. Else the
;;;             statement is counted, tracked by its connection, and ready.
;;;   step!     sqlite3_step: row gives #t, done #f, anything else failed and
;;;             &sqlite-error from the step's own code, which is extended,
;;;             with the statement's SQL and no offset
;;;   reset!    sqlite3_reset, then ready whatever it answered; a failure of
;;;             its own, by finish-failure, raises
;;;   finalize  sqlite3_finalize, then the handle cleared, the statement
;;;             finalized, untracked and counted down whatever it answered;
;;;             then a failure of its own, by finish-failure, raises
;;;
;;; Every refusal of a caller's mistake is an assertion violation whose
;;; irritants begin with a symbol naming its rule, then the value by
;;; shown-value, never a string's text (ADR-0013).
;;;
;;; The internals (ADR-0013; ADR-0014). Each takes a WHO, the procedure its
;;; caller's caller called, and everything it raises names it; the public
;;; verbs above are thin wrappers passing their own names:
;;;
;;;   prepared, finalized    prepare-statement's and finalize-statement!'s
;;;                          work for a WHO
;;;   step!/who, reset!/who, column-count/who
;;;                          step!'s, reset!'s and column-count's
;;;   prepared-at            one statement prepared from a byte offset of a C
;;;                          string its caller holds, with flags 0 or
;;;                          SQLITE_PREPARE_PERSISTENT, answered as data with
;;;                          its tail's byte offset: never refused for a tail,
;;;                          nor for holding no statement
;;;   checked-out, returned  the statement cache's use (ADR-0020): a
;;;                          statement for SQL, the cache's or a fresh one,
;;;                          and the same statement given back
;;;   while-held             a section around one of the accessor's, that
;;;                          reads a convenience's flag before the accessor's
;;;                          checks (below)
;;;
;;; checked-sql, prepare-statement's checks of its SQL, is exported for
;;; prepared-at's callers, which check a whole script once.
;;;
;;; A convenience's call holds a flag, set once its statement leaves the
;;; call, given back to the cache or finalized: Chez's engine remainders are
;;; multi-shot, and a timer's or keyboard's handler can capture a
;;; continuation between any two sections, so a call can be resumed, or
;;; re-entered, after its statement has gone back to the cache, and another
;;; caller may hold it by then. Every section that touches the call's
;;; statement reads the flag first, through LEFT?, the call's check, a
;;; procedure of no arguments or #f for none: checked-out's and the miss's
;;; prepare's, prepared-at's, and, through while-held, a bind's, a step's
;;; and a read's. When LEFT? answers true, the section touches nothing, and
;;; &sqlite-closed is raised from WHO after it.
(library (chez-sqlite3 private statement)
  (export prepare-statement finalize-statement! call-with-statement statement?
          statement-sql parameter-count step! reset! column-count
          call-with-statement-handle statement-state sql-length-fits?
          prepared finalized step!/who reset!/who column-count/who
          checked-sql prepared-at checked-out returned while-held)
  (import (chez-sqlite3 private require-threaded)
          (except (rnrs) dynamic-wind)
          (only (chezscheme) critical-section dynamic-wind)
          (chez-sqlite3 private native)
          (chez-sqlite3 private counters)
          (only (chez-sqlite3 private constants) sqlite-result-codes sqlite-prepare-persistent)
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
  ;; beyond, inside the prepare's section (ADR-0011). Pure, total.
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
  ;; handle, the statement's, and the statement's SQL, once ST is checked
  ;; for VERB, one of statement-verbs, in order:
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
  ;; state its step leaves, reset! ready, and a column read that SQLite
  ;; answered with a failure can answer failed. Anything else as the first
  ;; answer, or no answer at all, is an assertion violation from
  ;; call-with-statement-handle, not-a-live-state, naming it, raised after
  ;; the section with ST's state unchanged and PROC's other answers dropped:
  ;; finalized among it, since only a finalize, clearing the handle, makes a
  ;; statement finalized. A refusal before PROC never changes the state.
  ;;
  ;; The SQL PROC is given is the copy made at prepare, which never changes:
  ;; a failure PROC answers carries it, with no read of ST after the section,
  ;; which a finalize by another engine could refuse (ADR-0013).
  ;;
  ;; PROC runs inside the connection's call-with-open-handle, in its critical
  ;; section, with the third and fourth checks: no engine, interrupt or
  ;; other verb on this thread can finalize ST, or close its connection,
  ;; between the checks and PROC's use of the handles. PROC runs with
  ;; interrupts disabled, so it keeps to its C calls and their reads, and
  ;; answers data: a raise is raised again after the section, as the same
  ;; object, and the state is left as it was. Every refusal here is raised
  ;; after the section. (chez-sqlite3 private statement-values)' verbs call
  ;; it, each reading the column count in PROC, with the read it guards.
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
                 ;; SQLite has freed the statement: clear the handle before
                 ;; anything that could raise reads the message.
                 (cleared (set-statement-handle! st #f))
                 (failure (finish-failure state answer))
                 (message (and failure (message-of connection answer))))
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
      (raise-finalize-outcome who outcome)))

  ;; raise-finalize-outcome : Symbol (U 'finalized Finalize-Outcome) -> Void
  ;; OUTCOME, finalize-handle!'s, raised from WHO when it is a failure.
  (define (raise-finalize-outcome who outcome)
    (cond ((not (pair? outcome)) (if #f #f))
          ((eq? (car outcome) 'failed) (raise-failure who outcome))
          (else (raise (cadr outcome)))))

  ;; finalize-statement! : Statement -> Void
  ;; ST finalized, whatever its state, and no longer tracked by its
  ;; connection; nothing when it is finalized already, or its connection
  ;; closed. A failure of the finalize's own, such as the commit of an
  ;; insert ... returning stepped once, then raises &sqlite-error; a failed
  ;; step's code, which the finalize repeats, does not (ADR-0014).
  (define (finalize-statement! st)
    (finalized 'finalize-statement! st))

  ;; --- preparing ------------------------------------------------------------------------

  ;; checked-sql : Symbol Any -> (Values String Bytevector)
  ;; SQL, copied, and the copy's UTF-8, once checked, for WHO: a SQL that is
  ;; no string, a copy holding U+0000, and one of more than sql-max-bytes
  ;; bytes, are assertion violations from WHO, before anything is allocated.
  ;; The caller's string is copied first and the copy alone is checked and
  ;; prepared, so another thread cannot change it between the two
  ;; (ADR-0011).
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

  ;; prepare-flags? : Any -> Boolean
  ;; Whether FLAGS is a prepare's flags in v1: 0, or SQLITE_PREPARE_PERSISTENT,
  ;; which the statement cache's statements take (ADR-0020).
  (define (prepare-flags? flags)
    (or (eqv? flags 0) (eqv? flags sqlite-prepare-persistent)))

  ;; prepare-call : Symbol Positive-Integer Positive-Integer Positive-Integer Natural
  ;;                -> (Values Natural (Pairof Integer (Listof Any)) Natural)
  ;; sqlite3_prepare_v3 on CONNECTION of the NBYTE bytes at ADDRESS, their NUL
  ;; counted, with FLAGS, inside its caller's section: the statement's and
  ;; the tail's out-parameters made, used and freed here, and
  ;; sqlite3_errmsg and sqlite3_error_offset read straight after a failure.
  ;; Answers the statement, 0 for none; the answer, (CODE) or (CODE MESSAGE
  ;; OFFSET); and the tail's address.
  (define (prepare-call who connection address nbyte flags)
    (let-values (((inner tail)
                  (call-with-out-pointer who
                    (lambda (tail-slot)
                      (let-values (((answer statement)
                                    (call-with-out-pointer who
                                      (lambda (statement-slot)
                                        (let ((rc (sqlite3-prepare-v3 connection address nbyte
                                                                      flags statement-slot tail-slot)))
                                          (if (eqv? rc sqlite-ok)
                                              (list rc)
                                              (list rc (message-of connection rc)
                                                    (sqlite3-error-offset connection))))))))
                        (cons statement answer))))))
      (values (car inner) (cdr inner) tail)))

  ;; prepare-outcome : Symbol Database String Bytevector Natural (U (Statement -> Any) #f)
  ;;                   (U (-> Any) #f)
  ;;   -> (U (List 'prepared Statement) (List 'failed Integer String (U Natural #f))
  ;;         (List 'empty) (List 'more Natural) (List 'left))
  ;; COPY prepared on DB with FLAGS, BYTES its UTF-8, in
  ;; call-with-open-handle's section: LEFT?, when a procedure, evaluated
  ;; first, and left when it answers true, nothing allocated or prepared;
  ;; else the C string, prepare-call, the count, the tail's scan, and either
  ;; the finalize of a statement with more after it, or the record, its
  ;; tracking and ON-MADE called with it, which call-with-statement uses to
  ;; learn of it in the same section. Answers the statement; or the
  ;; failure's code, message and character offset; or empty for a NULL
  ;; statement; or more, with the byte offset of what the tail holds.
  (define (prepare-outcome who db copy bytes flags on-made left?)
    (call-with-open-handle who db
      (lambda (connection)
        (if (and left? (left?))
            '(left)
            (call-with-c-string who copy
              (lambda (c-sql)
                (let-values (((statement answer tail)
                              (prepare-call who connection c-sql (+ (bytevector-length bytes) 1) flags)))
                  (made-outcome who db copy bytes on-made statement answer (- tail c-sql)))))))))

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

  ;; prepared-checked : Symbol Database String Bytevector Natural (U (Statement -> Any) #f)
  ;;                    (U (-> Any) #f) -> Statement
  ;; COPY, checked by checked-sql, BYTES its UTF-8, prepared on DB with FLAGS
  ;; for WHO, DB checked to be a database on its owning thread: DB open, in
  ;; the section, then LEFT?, a call's check, true there raising
  ;; &sqlite-closed after it, nothing prepared; the prepare's failure, a
  ;; NULL statement and a tail holding more, each raised after it.
  (define (prepared-checked who db copy bytes flags on-made left?)
    (let ((outcome (prepare-outcome who db copy bytes flags on-made left?)))
      (case (car outcome)
        ((prepared) (cadr outcome))
        ((left) (raise-closed who))
        ((failed) (raise-sqlite-error who (cadr outcome) (caddr outcome) copy (cadddr outcome)))
        ((empty)
         (assertion-violation who "SQL holding no statement" 'no-statement (shown-value copy)))
        (else
         (assertion-violation who "SQL holding more than one statement"
                              'more-than-one-statement
                              (utf8-offset->index bytes (cadr outcome)))))))

  ;; prepared : Symbol Any Any (U (Statement -> Any) #f) -> Statement
  ;; SQL prepared on DB, for WHO, with no flags, by the checks in order: DB a
  ;; database, on its owning thread; SQL by checked-sql; DB open, in the
  ;; section. Each refusal, and the prepare's failure, raised after the
  ;; section. ON-MADE, when a procedure, is called with the statement inside
  ;; the prepare's section (call-with-statement's hand-over).
  (define (prepared who db sql on-made)
    (check-database-owner who db)
    (let-values (((copy bytes) (checked-sql who sql)))
      (prepared-checked who db copy bytes 0 on-made #f)))

  ;; --- preparing from a C string the caller holds --------------------------------------
  ;;
  ;; A script's statements are prepared one at a time from one block, the
  ;; script's whole C string, which execute-script! holds for its loop
  ;; (ADR-0016): so the script is copied once, not once a
  ;; statement, and each prepare passes the address of its statement's start.
  ;; The script is checked once, by checked-sql, before its block is made.

  ;; check-on-made : Symbol Any -> Void
  (define (check-on-made who on-made)
    (unless (or (not on-made) (procedure? on-made))
      (assertion-violation who "on-made is a procedure or #f" 'not-a-procedure
                           (shown-value on-made))))

  ;; check-left : Symbol Any -> Void
  ;; A call's check, LEFT?, is a procedure of no arguments or #f, else an
  ;; assertion violation from WHO, not-a-procedure.
  (define (check-left who left?)
    (unless (or (not left?) (procedure? left?))
      (assertion-violation who "a call's check is a procedure or #f" 'not-a-procedure
                           (shown-value left?))))

  ;; first-outcome : Database String Bytevector (U (Statement -> Any) #f) Natural Natural
  ;;                 (Pairof Integer (Listof Any)) Natural
  ;;   -> (U (List 'prepared Statement Natural) (List 'empty Natural)
  ;;         (List 'failed Integer String Integer))
  ;; What prepared-at answers once its prepare, from byte START of BYTES,
  ;; SQL's UTF-8, returned STATEMENT, ANSWER and TAIL, the tail's byte
  ;; offset. Inside the same section: the count, the record, holding the
  ;; statement's own text, its tracking and ON-MADE.
  (define (first-outcome db sql bytes on-made start statement answer tail)
    (cond
      ((not (eqv? (car answer) sqlite-ok))
       (list 'failed (car answer) (cadr answer) (caddr answer)))
      ((eqv? statement 0) (list 'empty tail))
      (else
       (count-up! 'statement)
       (let ((st (make-statement statement db (own-text sql bytes start tail) 'ready)))
         (track-statement! db st (lambda (connection) (finalize-handle! st connection)))
         (when on-made (on-made st))
         (list 'prepared st tail)))))

  ;; own-text : String Bytevector Natural Natural -> String
  ;; The text SQLite compiled, bytes START to TAIL of BYTES, SQL's UTF-8,
  ;; decoded strictly: linear in the statement's length, so a script's loop
  ;; stays linear in the script's. SQLite starts and ends a statement on a
  ;; character's boundary, so the bytes are well-formed; were they not, SQL
  ;; whole. Raises nothing for a TAIL within START to BYTES' length.
  (define (own-text sql bytes start tail)
    (let* ((n (if (<= start tail (bytevector-length bytes)) (- tail start) 0))
           (slice (make-bytevector n)))
      (bytevector-copy! bytes start slice 0 n)
      (let ((decoded (strict-utf8->string slice)))
        (if (string? decoded) decoded sql))))

  ;; prepared-at : Symbol Any String Bytevector Positive-Integer Natural Natural
  ;;               (U (Statement -> Any) #f) (U (-> Any) #f)
  ;;   -> (U (List 'prepared Statement Natural) (List 'empty Natural)
  ;;         (List 'failed Integer String Integer))
  ;; The first statement from byte START of BYTES prepared on DB with FLAGS,
  ;; for WHO. SQL is a copy checked by checked-sql and BYTES its UTF-8, as
  ;; checked-sql answered them; BLOCK is the address of their C string, held
  ;; by the caller through call-with-c-string for as long as it calls this.
  ;; nByte is the bytes from START with the NUL. Answers, as data:
  ;;   (prepared ST TAIL)  ST live, ready, counted and tracked by DB, its SQL
  ;;                       the text SQLite compiled, START to TAIL; ON-MADE
  ;;                       called with it in the prepare's section; TAIL the
  ;;                       byte offset in BYTES where the rest begins, never
  ;;                       scanned or refused
  ;;   (empty TAIL)        SQLite found no statement from START: only
  ;;                       whitespace, comments and semicolons, or nothing
  ;;   (failed CODE MESSAGE OFFSET)
  ;;                       the prepare failed: its extended code,
  ;;                       sqlite3_errmsg and sqlite3_error_offset read
  ;;                       straight after it, OFFSET in bytes from START, or
  ;;                       -1, for script-prepare-offset
  ;; The checks, in order, each an assertion violation before the section:
  ;; WHO a symbol, from prepared-at; FLAGS 0 or SQLITE_PREPARE_PERSISTENT,
  ;; from prepared-at, not-prepare-flags; ON-MADE and LEFT? each a procedure
  ;; or #f, from WHO; DB a database, from WHO, on its owning thread, else
  ;; &sqlite-wrong-thread; SQL a string, BYTES a bytevector of at most
  ;; 2^31-2 bytes, BLOCK an exact positive integer, from prepared-at,
  ;; not-checked-sql; START within 0 to BYTES' length, from WHO,
  ;; start-out-of-range. Then DB open, in the section, else &sqlite-closed
  ;; from WHO, raised after it; then LEFT?, a call's check, when a
  ;; procedure: true, the section prepares nothing, and &sqlite-closed is
  ;; raised from WHO after it. execute-script! passes every prepare a check
  ;; that claims the statement's byte offset, and refuses one the call has
  ;; passed, so no run of a call, re-entered before its block or jumped back
  ;; inside it, prepares a statement again. The section holds the
  ;; out-parameters, the prepare, the reads after a failure, the count and
  ;; the tracking (ADR-0014).
  (define (prepared-at who db sql bytes block start flags on-made left?)
    (check-who 'prepared-at who)
    (unless (prepare-flags? flags)
      (assertion-violation 'prepared-at "a prepare's flags are 0 or SQLITE_PREPARE_PERSISTENT"
                           'not-prepare-flags (shown-value flags)))
    (check-on-made who on-made)
    (check-left who left?)
    (check-database-owner who db)
    (unless (and (string? sql) (bytevector? bytes) (sql-length-fits? (bytevector-length bytes))
                 (integer? block) (exact? block) (> block 0))
      (assertion-violation 'prepared-at "SQL, its UTF-8 and its C string, as checked-sql and call-with-c-string made them"
                           'not-checked-sql))
    (unless (and (integer? start) (exact? start) (<= 0 start (bytevector-length bytes)))
      (assertion-violation who "a statement's start is a byte offset into its SQL"
                           'start-out-of-range (shown-value start) (bytevector-length bytes)))
    (let ((outcome
           (call-with-open-handle who db
             (lambda (connection)
               (if (and left? (left?))
                   '(left)
                   (let-values (((statement answer tail)
                                 (prepare-call who connection (+ block start)
                                               (+ (- (bytevector-length bytes) start) 1) flags)))
                     (first-outcome db sql bytes on-made start statement answer (- tail block))))))))
      (if (eq? (car outcome) 'left)
          (raise-closed who)
          outcome)))

  ;; --- prepare-statement ---------------------------------------------------------------

  ;; prepare-statement : Database String -> Statement
  ;; SQL, one statement, prepared on DB, ready and tracked by DB until it is
  ;; finalized. SQL holding no statement, or more than one, is refused, the
  ;; second once its first statement is prepared, so that statement's
  ;; prepare-time effects stand: pragma cache_size = 7; select 1 sets the
  ;; cache size (ADR-0014).
  (define (prepare-statement db sql)
    (prepared 'prepare-statement db sql #f))

  ;; --- call-with-statement ------------------------------------------------------------

  ;; call-with-statement : Database String (Statement -> A ...) -> A ...
  ;; PROC's answers, PROC given SQL prepared on DB (ADR-0014).
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

  ;; column-count/who : Symbol Statement -> Natural
  ;; column-count's work for WHO, which everything it raises names.
  (define (column-count/who who st)
    (call-with-statement-handle who st 'column-count
      (lambda (connection handle sql) (values #f (sqlite3-column-count handle)))))

  ;; column-count : Statement -> Natural
  ;; How many columns ST's rows have now, sqlite3_column_count's answer, read
  ;; afresh at every call: another connection's change to a table changes it
  ;; at the next step (ADR-0014).
  (define (column-count st)
    (column-count/who 'column-count st))

  ;; step!/who : Symbol Statement -> Boolean
  ;; step!'s work for WHO, which everything it raises names.
  (define (step!/who who st)
    (let ((outcome
           (call-with-statement-handle who st 'step!
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
            (else (raise-failure who outcome)))))

  ;; step! : Statement -> Boolean
  ;; #t when sqlite3_step has a row ready, the state row; #f when it has
  ;; finished, done. Any other answer leaves ST failed and raises
  ;; &sqlite-error from the step's own code, with ST's SQL. Allowed in ready
  ;; and row only: a done or failed statement is refused until reset!.
  (define (step! st)
    (step!/who 'step! st))

  ;; reset-outcome : Statement Positive-Integer Positive-Integer String
  ;;                 -> (U (List 'failed Integer String String) #f)
  ;; sqlite3_reset of ST, HANDLE its handle, inside the accessor's section:
  ;; a failure of the reset's own, by finish-failure, with sqlite3_errmsg
  ;; read straight after and a copy of SQL; #f when there is none.
  (define (reset-outcome st connection handle sql)
    (let* ((state (unchecked-statement-state st))
           (answer (sqlite3-reset handle))
           (failure (finish-failure state answer))
           (message (and failure (message-of connection answer))))
      (and failure (list 'failed failure message (string-copy sql)))))

  ;; reset!/who : Symbol Statement -> Void
  ;; reset!'s work for WHO, which everything it raises names.
  (define (reset!/who who st)
    (let ((outcome
           (call-with-statement-handle who st 'reset!
             (lambda (connection handle sql)
               (values 'ready (reset-outcome st connection handle sql))))))
      (when outcome (raise-failure who outcome))))

  ;; reset! : Statement -> Void
  ;; ST rewound, ready again, its bindings kept, whatever sqlite3_reset
  ;; answered. A failure of the reset's own, such as the commit of an insert
  ;; ... returning stepped once, then raises &sqlite-error; a failed step's
  ;; code, which the reset repeats, does not (ADR-0014).
  (define (reset! st)
    (reset!/who 'reset! st))

  ;; --- the statement cache (ADR-0020) ------------------------------------------------------
  ;;
  ;; The cache is the connection's, in its record (connection.sls), and holds
  ;; only ready statements prepared SQLITE_PREPARE_PERSISTENT, each filed
  ;; under its own SQL copy, which never changes. A statement is checked out
  ;; while in use, and out of the cache meanwhile. Both changes are made
  ;; inside call-with-open-handle's section, which raises nothing and answers
  ;; data: before it, the database is checked to be one, on its owner's
  ;; thread, and the SQL checked and copied, so the table's lookup cannot
  ;; raise and its key cannot change; after it, a statement the return evicts,
  ;; or refuses to file, is finalized by finalized, and its failure raised
  ;; (ADR-0020). A finalized statement is a miss, in the cache or checked out:
  ;; it is never handed out, nor filed.

  ;; checked-out : Symbol Any Any (U (Statement -> Any) #f) (U (-> Any) #f) -> Statement
  ;; A ready statement for SQL on DB, for WHO: the one DB's cache holds under
  ;; SQL's text, checked out, or else one prepared afresh, by
  ;; prepare-statement's rules, with SQLITE_PREPARE_PERSISTENT while the
  ;; cache's capacity is above 0, and with no flags at 0 (ADR-0020). ON-MADE,
  ;; a procedure or #f, is called with it inside the section that checks it
  ;; out or prepares it, so no escaping interrupt falls between its hand-over
  ;; and the caller's knowing of it (ADR-0016). A held statement that is not
  ;; ready, finalized above all, is a miss: dropped from the cache, never
  ;; handed out; one finalized already needs nothing more, and one a suite
  ;; moved through tracked-statements stays tracked until it is finalized or
  ;; DB closes.
  ;; LEFT?, the call's check, a procedure of no arguments or #f for none, is
  ;; evaluated first in the check-out's section, before the table is read,
  ;; and in a miss's prepare's, before it prepares: when it answers true,
  ;; that section touches nothing, and &sqlite-closed is raised from WHO
  ;; after it. So a convenience's call resumed, or re-entered, after its
  ;; statement has gone back to the cache checks out nothing again.
  ;; with-transaction's own statements pass a check of their own: the
  ;; level's ENDED. The checks, in order:
  ;; ON-MADE and LEFT?, from WHO; DB a database on its owning thread; SQL by
  ;; checked-sql; DB open, in the section. Each refusal, and the miss's
  ;; prepare failing, holding no statement or more than one, raised after
  ;; its section, from WHO.
  (define (checked-out who db sql on-made left?)
    (check-who 'checked-out who)
    (check-on-made who on-made)
    (check-left who left?)
    (check-database-owner who db)
    (let-values (((copy bytes) (checked-sql who sql)))
      (let* ((flags (if (> (database-cache-capacity db) 0) sqlite-prepare-persistent 0))
             (outcome
              (call-with-open-handle who db
                (lambda (connection)
                  (if (and left? (left?))
                      '(left)
                      (let ((found (database-cache-check-out! db copy)))
                        (if (and (eq? (car found) 'hit) (eq? (state-of (cadr found)) 'ready))
                            (begin (when on-made (on-made (cadr found))) found)
                            '(miss))))))))
        (case (car outcome)
          ((hit) (cadr outcome))
          ((left) (raise-closed who))
          (else (prepared-checked who db copy bytes flags on-made left?))))))

  ;; while-held : Symbol (U (-> Any) #f) (-> A ...) -> A ...
  ;; THUNK's answers, THUNK making one section through the accessor, a
  ;; bind's, a step's or a read's, for a convenience's call, WHO its name.
  ;; LEFT?, the call's check, is evaluated first, in a critical section
  ;; around THUNK, so before the accessor's checks of the statement's state:
  ;; when it answers true, the call's statement has left it, THUNK never
  ;; runs, and &sqlite-closed is raised from WHO after the section. What
  ;; THUNK raises, after the accessor's section, is caught in this one and
  ;; raised again after it, the same object, so nothing raises inside it.
  ;; With LEFT? #f, THUNK is called plainly. A LEFT? that is neither is an
  ;; assertion violation from WHO, not-a-procedure.
  (define (while-held who left? thunk)
    (check-left who left?)
    (if (not left?)
        (thunk)
        (let ((outcome (critical-section
                        (if (left?)
                            '(left)
                            (guard (c (#t (list 'raised c)))
                              (call-with-values thunk (lambda answers (cons 'answered answers))))))))
          (case (car outcome)
            ((answered) (apply values (cdr outcome)))
            ((left) (raise-closed who))
            (else (raise (cadr outcome)))))))

  ;; returned : Symbol Any -> Void
  ;; ST, a statement checked-out answered, given back to its connection's
  ;; cache, for WHO, in one section, through the accessor, whose checks come
  ;; first: a statement, on its connection's owning thread. Then, by its
  ;; state, read in that section:
  ;;   - finalized, or its connection closed: nothing, a miss;
  ;;   - failed, by its step or a read: finalized there, never kept, so the
  ;;     next prepare reads the schema afresh (ADR-0020); the
  ;;     finalize repeats the failure's code, which raises nothing again;
  ;;   - else reset, its bindings cleared, and filed as the cache's most
  ;;     recent, under its own SQL copy. The table answers what to finalize:
  ;;     the least recently used, evicted from a full cache; or ST itself,
  ;;     at a capacity of 0, or when the cache holds its SQL already. Each is
  ;;     finalized after the section, and a failure of its own raised.
  ;;   - a reset or a clear that fails: ST finalized in the section, not
  ;;     kept, and that failure raised after it, &sqlite-error from WHO with
  ;;     ST's SQL. The reset that commits an insert ... returning stepped
  ;;     once can answer BUSY, rolling the insert back (ADR-0014).
  ;; Whether the caller is already raising, and its condition wins, is the
  ;; caller's to know (ADR-0016).
  (define (returned who st)
    (let ((outcome
           (call-with-statement-handle who st 'finalize-statement!
             (lambda (connection handle sql)
               (let ((db (unchecked-statement-database st)))
                 (if (eq? (unchecked-statement-state st) 'failed)
                     (let ((finalize (finalize-handle! st connection)))
                       (untrack-statement! db st)
                       (values #f (list 'discarded finalize)))
                     (let* ((reset (reset-outcome st connection handle sql))
                            (cleared (or reset (cleared-outcome connection handle sql))))
                       (if cleared
                           (let ((finalize (finalize-handle! st connection)))
                             (untrack-statement! db st)
                             (values #f (list 'not-kept cleared finalize)))
                           ;; The accessor sets ready, in this section, before
                           ;; anything can check the statement out.
                           (values 'ready (cons 'filed (database-cache-return! db sql st)))))))))))
      (when (pair? outcome)
        (case (car outcome)
          ((discarded) (raise-finalize-outcome who (cadr outcome)))
          ((not-kept) (raise-failure who (cadr outcome)))
          (else (finalize-each who (cdr outcome)))))))

  ;; cleared-outcome : Positive-Integer Positive-Integer String
  ;;                   -> (U (List 'failed Integer String String) #f)
  ;; sqlite3_clear_bindings of HANDLE, inside the accessor's section: a
  ;; failure, with sqlite3_errmsg read straight after, or #f.
  (define (cleared-outcome connection handle sql)
    (let ((code (sqlite3-clear-bindings handle)))
      (and (not (eqv? code sqlite-ok))
           (list 'failed code (message-of connection code) (string-copy sql)))))

  ;; finalize-each : Symbol (Listof Statement) -> Void
  ;; Each of STATEMENTS finalized by finalized, for WHO, in order; then the
  ;; first failure any raised, raised again, once all are finalized.
  (define (finalize-each who statements)
    (let loop ((rest statements) (first #f))
      (if (null? rest)
          (when first (raise (car first)))
          (let ((failure (guard (c (#t (list c))) (finalized who (car rest)) #f)))
            (loop (cdr rest) (or first failure)))))))
