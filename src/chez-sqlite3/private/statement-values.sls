#!r6rs
;;; (chez-sqlite3 private statement-values): a statement's values, bound to
;;; its parameters and read from its columns (ADR-0015; ADR-0014, decisions
;;; 3 and 5, amended). (chez-sqlite3) exports its six verbs.
;;;
;;; Every verb goes through (chez-sqlite3 private statement)'s
;;; call-with-statement-handle, with its own verb's name from
;;; statement-verbs, so the accessor makes decision 3's checks, in order, and
;;; the state's, before anything reaches C. The accessor's procedure runs in
;;; the connection's critical section: there each verb reads the count it
;;; checks an index against, makes its C calls, reads sqlite3_errmsg straight
;;; after a failure, and answers data, the state the call leaves first, #f
;;; for unchanged. Nothing raises in it. Every refusal and failure is raised
;;; after the section, from that data (ADR-0014, decision 10).
;;;
;;; Binding (ADR-0015, decisions 2 to 6):
;;;
;;;   the value      bind-plan decides it, before the section: it is pure,
;;;                  and a string's encoding then runs outside the section.
;;;                  A refusal is raise-bind-refusal's, after the section
;;;   by index       1 to sqlite3_bind_parameter_count, read in the bind's
;;;                  section; outside it, parameter-out-of-range
;;;   by name        a string, sigil included. It is copied and checked for
;;;                  U+0000 before anything is allocated,
;;;                  parameter-name-holds-nul; its C string is made, used and
;;;                  freed in the section, and sqlite3_bind_parameter_index
;;;                  answering 0 is no-such-parameter
;;;   TEXT, BLOB     call-with-bytes's counted block of at least one byte,
;;;                  made in the section, bound with the bytes' length,
;;;                  sqlite-utf8 for text, and sqlite-transient
;;;   SQLite refuses an &sqlite-error from the bind's code, sqlite3_errmsg
;;;                  read straight after, the statement's SQL and no offset:
;;;                  sqlite3_error_offset can be an earlier prepare's (the
;;;                  research's trap). The state stays ready
;;;
;;; The checks of a bind come in this order: the accessor's (a statement, its
;;; thread, not finalized, ready), then the parameter, then the value; and
;;; for bind-all!, the count, then every value, before any bind.
;;;
;;; Reading (ADR-0015, decisions 7 to 9): a column's index is checked against
;;; sqlite3_column_count, read in the read's section, never cached. The type
;;; is read first, then the matching accessor: TEXT through
;;; sqlite3_column_text and BLOB through sqlite3_column_blob, each by
;;; read-column-bytes, then sqlite3_column_bytes, copied out by
;;; foreign-bytes. TEXT is decoded by strict-utf8->string after the section,
;;; and ill-formed bytes raise &sqlite-invalid-text with the column and the
;;; byte offset. A NOMEM read moves the statement to failed, by the
;;; maintainer's choice (ADR-0014, amended): it raises &sqlite-error nomem
;;; once, and reads and step! are refused until reset!, whose repeat of the
;;; code raises nothing.
;;;
;;; Every refusal of a caller's mistake is an assertion violation whose
;;; irritants begin with a symbol naming its rule, then the value by
;;; shown-value, never a string's text (ADR-0013, decisions 7 and 9):
;;;
;;;   not-a-parameter          a parameter that is neither an exact integer
;;;                            nor a string
;;;   parameter-out-of-range   an index outside 1 to the parameter count,
;;;                            then the count
;;;   parameter-name-holds-nul a name holding U+0000, by its kind
;;;   no-such-parameter        a name no parameter has, by its kind
;;;   value-count-mismatch     bind-all!'s values, counted, then the
;;;                            parameter count
;;;   not-a-column-index       a column that is no exact integer
;;;   column-out-of-range      an index outside 0 below the column count,
;;;                            then the count
;;;   not-text-or-blob         column-bytevector of an INTEGER or FLOAT
;;;                            value: the column, then integer or float
;;;
;;; and a value bind-plan refuses, by raise-bind-refusal's rule.
;;;
;;; M3's internals (ADR-0013, decision 2; ADR-0016, decisions 3 and 9; the
;;; M3 plan, finding F11): each verb's work for a WHO, which everything it
;;; raises names, the verb itself a thin wrapper passing its own name:
;;; bind!/who, bind-all!/who, clear-bindings!/who, column-value/who,
;;; column-bytevector/who and column-name/who. And bind-each!/who, which the
;;; conveniences bind through: bind-all!'s rule, every value checked before
;;; any is bound, with each value bound in a critical section of its own
;;; (the maintainer's answer to the M3 plan's Q15, "One value each"), each
;;; of its sections reading the convenience's call's flag first, through
;;; (chez-sqlite3 private statement)'s while-held. And bind-each!/at, its
;;; work as data, each section made by its caller's sectioner: execute!,
;;; query and query-row's claim on their call, at the run's position
;;; (ADR-0016, amended in M3 slice 5's part D); bind-each!/who is it, each
;;; section by while-held.
(library (chez-sqlite3 private statement-values)
  (export bind! bind-all! clear-bindings! column-value column-bytevector column-name
          bind!/who bind-all!/who bind-each!/who bind-each!/at clear-bindings!/who
          column-value/who column-bytevector/who column-name/who)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (only (chez-sqlite3 private native)
                sqlite3-errmsg sqlite3-errstr sqlite3-extended-errcode
                sqlite3-clear-bindings sqlite3-bind-parameter-count sqlite3-bind-parameter-index
                sqlite3-bind-null sqlite3-bind-int64 sqlite3-bind-double sqlite3-bind-text64
                sqlite3-bind-blob64 sqlite3-column-count sqlite3-column-name sqlite3-column-type
                sqlite3-column-int64 sqlite3-column-double sqlite3-column-text sqlite3-column-blob
                sqlite3-column-bytes sqlite-transient
                call-with-c-string c-string->string call-with-bytes foreign-bytes
                c-string->bytevector)
          (only (chez-sqlite3 private constants)
                sqlite-integer sqlite-float sqlite-text sqlite-blob sqlite-null sqlite-utf8
                sqlite-result-codes)
          (only (chez-sqlite3 private conditions)
                raise-sqlite-error raise-invalid-text shown-value)
          (only (chez-sqlite3 private statement) call-with-statement-handle while-held)
          (chez-sqlite3 private values)
          (only (chez-sqlite3 private utf8) strict-utf8->string))

  (define sqlite-ok (cdr (assq 'ok sqlite-result-codes)))
  (define sqlite-nomem (cdr (assq 'nomem sqlite-result-codes)))

  ;; exact-integer? : Any -> Boolean
  (define (exact-integer? x) (and (integer? x) (exact? x)))

  ;; --- what SQLite said -----------------------------------------------------------

  ;; message-of : Positive-Integer Integer -> String
  ;; sqlite3_errmsg of CONNECTION, read straight after the call that answered
  ;; CODE; sqlite3_errstr of CODE when errmsg answers NULL; empty when that
  ;; does too. SQLite's own text, so c-string->string reads it.
  (define (message-of connection code)
    (or (c-string->string (sqlite3-errmsg connection))
        (c-string->string (sqlite3-errstr code))
        ""))

  ;; failure : Positive-Integer Integer String -> (List 'failed Integer String String)
  ;; The data of a failure SQLite answered CODE for, inside the section: the
  ;; code, its message read now, and a copy of the statement's SQL.
  (define (failure connection code sql)
    (list 'failed code (message-of connection code) (string-copy sql)))

  ;; --- after the section -----------------------------------------------------------

  ;; refusal-message : Symbol -> String
  (define (refusal-message rule)
    (case rule
      ((not-a-parameter) "a parameter is an index from 1, or a name with its sigil")
      ((parameter-out-of-range) "a parameter's index runs from 1 to the statement's parameter count")
      ((parameter-name-holds-nul) "a parameter's name holding U+0000, where C would read its end")
      ((no-such-parameter) "no parameter of the statement has this name, its sigil included")
      ((value-count-mismatch) "bind-all! takes one value for each of the statement's parameters")
      ((not-a-column-index) "a column's index is an exact integer, from 0")
      ((column-out-of-range) "a column's index runs from 0 below the statement's column count")
      ((not-text-or-blob)
       "column-bytevector reads a TEXT or BLOB value, or NULL: read this one with column-value")
      (else "refused")))

  ;; finish : Symbol Outcome -> Any
  ;; Outcome = (U (List 'done) (List 'value Any) (List 'text Natural Bytevector)
  ;;              (List 'name Natural Bytevector) (Pairof 'refused (Pairof Symbol (Listof Any)))
  ;;              (List 'refused-value (U Positive-Integer String) Any Symbol)
  ;;              (List 'failed Integer String String))
  ;; What a verb's section decided, answered or raised from WHO, after the
  ;; section: nothing; a value; TEXT or a name decoded strictly, else
  ;; &sqlite-invalid-text with the column and the byte offset; an assertion
  ;; violation, its rule leading its irritants; raise-bind-refusal's; or an
  ;; &sqlite-error with the SQL and no offset.
  (define (finish who outcome)
    (case (car outcome)
      ((done) (if #f #f))
      ((value) (cadr outcome))
      ((text name)
       (let ((decoded (strict-utf8->string (caddr outcome))))
         (if (string? decoded)
             decoded
             (raise-invalid-text who (cadr outcome) (cadr decoded)))))
      ((refused)
       (apply assertion-violation who (refusal-message (cadr outcome)) (cdr outcome)))
      ((refused-value)
       (raise-bind-refusal who (cadr outcome) (caddr outcome) (cadddr outcome)))
      (else (raise-sqlite-error who (cadr outcome) (caddr outcome) (cadddr outcome) #f))))

  ;; --- binding ------------------------------------------------------------------------

  ;; parameter-form : Any -> (U (List 'index Integer) (List 'name String)
  ;;                            (List 'refused Symbol Any))
  ;; PARAMETER as a bind reads it, before the section: an exact integer is
  ;; an index, its range checked in the section; a string is a name, copied,
  ;; the copy checked for U+0000; anything else not-a-parameter. Pure, total.
  (define (parameter-form parameter)
    (cond ((exact-integer? parameter) (list 'index parameter))
          ((string? parameter)
           (let ((copy (string-copy parameter)))
             (if (holds-nul? copy)
                 (list 'refused 'parameter-name-holds-nul (shown-value copy))
                 (list 'name copy))))
          (else (list 'refused 'not-a-parameter (shown-value parameter)))))

  ;; holds-nul? : String -> Boolean
  (define (holds-nul? s)
    (let loop ((i 0))
      (and (< i (string-length s))
           (or (char=? (string-ref s i) #\nul) (loop (+ i 1))))))

  ;; parameter-index : Symbol Positive-Integer (List Symbol Any ...)
  ;;                   -> (U (List 'index Positive-Integer) (Pairof 'refused (Listof Any)))
  ;; FORM's index on HANDLE, in the section: an index within 1 to
  ;; sqlite3_bind_parameter_count, read now; a name's, by
  ;; sqlite3_bind_parameter_index on its C string, made, used and freed here;
  ;; else the refusal, as data.
  (define (parameter-index who handle form)
    (case (car form)
      ((index)
       (let ((count (sqlite3-bind-parameter-count handle))
             (index (cadr form)))
         (if (<= 1 index count)
             form
             (list 'refused 'parameter-out-of-range index count))))
      ((name)
       (let ((index (call-with-c-string who (cadr form)
                      (lambda (c-name) (sqlite3-bind-parameter-index handle c-name)))))
         (if (> index 0)
             (list 'index index)
             (list 'refused 'no-such-parameter (shown-value (cadr form))))))
      (else form)))

  ;; bind-code : Symbol Positive-Integer Positive-Integer Bind-Plan -> Integer
  ;; PLAN, no refusal, bound to INDEX of HANDLE, in the section: SQLite's
  ;; answer. TEXT and BLOB are copied into call-with-bytes's counted block,
  ;; at least one byte, so never NULL, and bound with their length and
  ;; sqlite-transient, so SQLite makes its own copy before the block is freed.
  (define (bind-code who handle index plan)
    (case (car plan)
      ((null) (sqlite3-bind-null handle index))
      ((int64) (sqlite3-bind-int64 handle index (cadr plan)))
      ((double) (sqlite3-bind-double handle index (cadr plan)))
      ((text)
       (let ((bytes (cadr plan)))
         (call-with-bytes who bytes
           (lambda (block)
             (sqlite3-bind-text64 handle index block (bytevector-length bytes)
                                  sqlite-transient sqlite-utf8)))))
      (else
       (let ((bytes (cadr plan)))
         (call-with-bytes who bytes
           (lambda (block)
             (sqlite3-bind-blob64 handle index block (bytevector-length bytes)
                                  sqlite-transient)))))))

  ;; bound-outcome : Symbol Statement Parameter-Form Bind-Plan Any Any -> Outcome
  ;; One bind's outcome, through the accessor, for WHO, in bind!'s section:
  ;; FORM's index found and checked against the count read there, then PLAN
  ;; bound to it; PARAMETER and VALUE, the caller's, name a refused value.
  (define (bound-outcome who st form plan parameter value)
    (call-with-statement-handle who st 'bind!
      (lambda (connection handle sql)
        (values #f
                (let ((found (parameter-index who handle form)))
                  (cond ((eq? (car found) 'refused) found)
                        ((eq? (car plan) 'refused)
                         (list 'refused-value parameter value (cadr plan)))
                        (else
                         (let ((code (bind-code who handle (cadr found) plan)))
                           (if (eqv? code sqlite-ok)
                               '(done)
                               (failure connection code sql))))))))))

  ;; bind!/who : Symbol Statement (U Positive-Integer String) Value -> Void
  ;; bind!'s work for WHO, which everything it raises names.
  (define (bind!/who who st parameter value)
    (let ((form (parameter-form parameter))
          (plan (bind-plan value)))
      (finish who (bound-outcome who st form plan parameter value))))

  ;; bind! : Statement (U Positive-Integer String) Value -> Void
  ;; VALUE bound to ST's PARAMETER: an index from 1 to (parameter-count ST),
  ;; or a name with its sigil, ":name", as the SQL writes it. Allowed in
  ;; ready only (ADR-0014, decision 5). A parameter or value refused is an
  ;; assertion violation before C, by its rule; a bind SQLite refuses, such
  ;; as TOOBIG over its length limit, raises &sqlite-error with ST's SQL,
  ;; the parameter then NULL and the state ready (ADR-0015, decisions 2 and
  ;; 6).
  (define (bind! st parameter value)
    (bind!/who 'bind! st parameter value))

  ;; first-refused : (Listof Bind-Plan) (Listof Any)
  ;;                 -> (U (List 'refused-value Positive-Integer Any Symbol) #f)
  ;; The first of PLANS, from parameter 1, that refuses its value, one of
  ;; GIVEN, as data.
  (define (first-refused plans given)
    (let loop ((plans plans) (given given) (index 1))
      (cond ((null? plans) #f)
            ((eq? (car (car plans)) 'refused)
             (list 'refused-value index (car given) (cadr (car plans))))
            (else (loop (cdr plans) (cdr given) (+ index 1))))))

  ;; plans-of : (Listof Any) -> (Listof Bind-Plan)
  ;; GIVEN's bind plans, in order, by a named let: never map, whose order of
  ;; calls is not fixed (AGENTS.md). Pure.
  (define (plans-of given)
    (let loop ((rest given) (found '()))
      (if (null? rest)
          (reverse found)
          (loop (cdr rest) (cons (bind-plan (car rest)) found)))))

  ;; bind-all!/who : Symbol Statement (Listof Value) -> Void
  ;; bind-all!'s work for WHO, which everything it raises names, GIVEN the
  ;; values: every parameter bound in one section.
  (define (bind-all!/who who st given)
    (let ((plans (plans-of given)))
      (finish who
        (call-with-statement-handle who st 'bind-all!
          (lambda (connection handle sql)
            (values #f
                    (let ((count (sqlite3-bind-parameter-count handle))
                          (n (length plans)))
                      (cond ((not (= n count))
                             (list 'refused 'value-count-mismatch n count))
                            ((first-refused plans given))
                            (else
                             (let loop ((plans plans) (index 1))
                               (if (null? plans)
                                   '(done)
                                   (let ((code (bind-code who handle index (car plans))))
                                     (if (eqv? code sqlite-ok)
                                         (loop (cdr plans) (+ index 1))
                                         (failure connection code sql))))))))))))))

  ;; bind-all! : Statement Value ... -> Void
  ;; Every parameter of ST bound, 1 to n, from GIVEN, n values. Allowed in
  ;; ready only. A count other than (parameter-count ST), read in the
  ;; section, is value-count-mismatch, and every value is checked, before
  ;; anything is bound: a refusal of ours binds nothing. A bind SQLite
  ;; refuses midway raises &sqlite-error, and leaves the parameters before it
  ;; bound (ADR-0015, decision 6).
  (define (bind-all! st . given)
    (bind-all!/who 'bind-all! st given))

  ;; bind-each!/who : Symbol Statement (Listof Value) (U (-> Any) #f) -> Void
  ;; Every parameter of ST bound, 1 to n, from GIVEN, n values, for WHO, by
  ;; bind-all!'s rule, each value in a critical section of its own (the M3
  ;; plan's Q15). GIVEN is planned first, outside any section, so a string
  ;; is encoded once. Then, in order:
  ;;   - the count, read in a section of its own by the accessor for
  ;;     bind-all!, so its checks come first: a statement, on its
  ;;     connection's owning thread, not finalized, ready;
  ;;   - a count other than n is value-count-mismatch, and the first value
  ;;     refused is raise-bind-refusal's, each before anything is bound;
  ;;   - each value bound to its index in a section of its own, by bind!'s,
  ;;     the index checked against the count read there and the state
  ;;     against ready, so this thread is held off for one value's copy at
  ;;     most. A bind SQLite refuses raises &sqlite-error, the parameters
  ;;     before it bound.
  ;; LEFT?, a convenience's call's check, or #f for none, is read first in
  ;; each of those sections, the count's and each value's, by while-held:
  ;; when it answers true, the section binds nothing, and &sqlite-closed is
  ;; raised from WHO after it. query-fold's flag; bind-each!/at's work, each
  ;; section by held-sectioner, what it answers raised.
  (define (bind-each!/who who st given left?)
    (let ((run (bind-each!/at who st given (held-sectioner who left?) 0)))
      (unless (eq? (car run) 'done) (raise (caddr run)))))

  ;; Section = (U (List 'answered Natural A ...) (List 'raised Natural Any) (List 'refused))
  ;; Sectioner = Natural (-> A ...) -> Section
  ;; Run = (U (List 'done Natural Any) (List 'raised Natural Any) (List 'refused))
  ;; A section a run of a convenience's call makes at position N, the
  ;; Sectioner's, as data: THUNK's answers, or what it raised, each with the
  ;; run's next position; or refused, THUNK never run. How the run's work
  ;; ended: done, its next position and its answer; a raise, with its next
  ;; position; or a section refused, the run's work over (the conveniences'
  ;; header).

  ;; held-sectioner : Symbol (U (-> Any) #f) -> Sectioner
  ;; THUNK's section by while-held, for WHO, reading LEFT? first: its
  ;; answers, or what it raised, &sqlite-closed when LEFT? answered true
  ;; among it, caught after while-held's section. Never refused.
  (define (held-sectioner who left?)
    (lambda (n thunk)
      (guard (c (#t (list 'raised (+ n 1) c)))
        (call-with-values (lambda () (while-held who left? thunk))
          (lambda answers (cons 'answered (cons (+ n 1) answers)))))))

  ;; finished-at : Symbol Natural Outcome -> Run
  ;; OUTCOME, a count's refusal or a bind's, finished by finish for WHO,
  ;; outside any section, a run at position N: done when it raises nothing,
  ;; else what it raised.
  (define (finished-at who n outcome)
    (guard (c (#t (list 'raised n c)))
      (finish who outcome)
      (list 'done n 'bound)))

  ;; bind-each!/at : Symbol Statement (Listof Value) Sectioner Natural -> Run
  ;; bind-each!/who's work for a run of a convenience's call at position N,
  ;; each of its sections made by SECTION, which execute!, query and
  ;; query-row's claim makes: the count's at N, then each value's, in order
  ;; (the conveniences' header). Done, answering bound, at the position
  ;; after the last value's; a refusal of the count or a value, or a bind's
  ;; failure, raised, with the run's next position; a section refused, the
  ;; run's work over, nothing bound by it. GIVEN is planned before any
  ;; section, so a string is encoded once, and every value is checked before
  ;; any is bound. Raises nothing.
  (define (bind-each!/at who st given section n)
    (let* ((plans (plans-of given))
           (counted (section n (lambda ()
                                 (call-with-statement-handle who st 'bind-all!
                                   (lambda (connection handle sql)
                                     (values #f (sqlite3-bind-parameter-count handle))))))))
      (if (not (eq? (car counted) 'answered))
          counted
          (let ((n (cadr counted)) (count (caddr counted)) (k (length plans)))
            (cond ((not (= k count))
                   (finished-at who n (list 'refused 'value-count-mismatch k count)))
                  ((first-refused plans given) => (lambda (refused) (finished-at who n refused)))
                  (else
                   (let loop ((plans plans) (rest given) (index 1) (n n))
                     (if (null? plans)
                         (list 'done n 'bound)
                         (let ((s (section n (lambda ()
                                               (bound-outcome who st (list 'index index) (car plans)
                                                              index (car rest))))))
                           (if (not (eq? (car s) 'answered))
                               s
                               (let ((bound (finished-at who (cadr s) (caddr s))))
                                 (if (eq? (car bound) 'done)
                                     (loop (cdr plans) (cdr rest) (+ index 1) (cadr bound))
                                     bound))))))))))))

  ;; clear-bindings!/who : Symbol Statement -> Void
  ;; clear-bindings!'s work for WHO, which everything it raises names.
  (define (clear-bindings!/who who st)
    (finish who
      (call-with-statement-handle who st 'clear-bindings!
        (lambda (connection handle sql)
          (let ((code (sqlite3-clear-bindings handle)))
            (values #f (if (eqv? code sqlite-ok) '(done) (failure connection code sql))))))))

  ;; clear-bindings! : Statement -> Void
  ;; Every parameter of ST NULL again, by sqlite3_clear_bindings. Allowed in
  ;; ready only: SQLite allows it while a row is ready, and then frees what
  ;; the row still reads (ADR-0014, decision 5).
  (define (clear-bindings! st)
    (clear-bindings!/who 'clear-bindings! st))

  ;; --- reading -----------------------------------------------------------------------

  ;; column-index : Positive-Integer Any -> (U (List 'index Natural) (Pairof 'refused (Listof Any)))
  ;; COLUMN checked against sqlite3_column_count, read now, in the section:
  ;; an exact integer from 0 below it, else the refusal, as data. A column
  ;; that is no exact integer is refused before the count is read.
  (define (column-index handle column)
    (if (not (exact-integer? column))
        (list 'refused 'not-a-column-index (shown-value column))
        (let ((count (sqlite3-column-count handle)))
          (if (and (<= 0 column) (< column count))
              (list 'index column)
              (list 'refused 'column-out-of-range column count)))))

  ;; column-bytes : Positive-Integer Positive-Integer Natural (Positive-Integer Integer -> Natural)
  ;;                -> (U Bytevector (List 'nomem Integer String))
  ;; Column COLUMN's bytes, through POINTER, sqlite3_column_text or _blob, by
  ;; read-column-bytes: the pointer, then sqlite3_column_bytes, then the copy;
  ;; or, for a NULL pointer, sqlite3_extended_errcode at once; on a code of
  ;; 7, sqlite3_column_type again, which a real NOMEM turned to NULL, an
  ;; empty value's does not; and on NOMEM, sqlite3_errmsg straight after.
  (define (column-bytes connection handle column pointer)
    (read-column-bytes (lambda () (pointer handle column))
                       (lambda () (sqlite3-extended-errcode connection))
                       (lambda () (sqlite3-column-type handle column))
                       (lambda () (message-of connection sqlite-nomem))
                       (lambda () (sqlite3-column-bytes handle column))
                       foreign-bytes))

  ;; read-outcome : Symbol Positive-Integer Positive-Integer String Any
  ;;                -> (Values (U 'failed #f) Outcome)
  ;; Column COLUMN of HANDLE's row, for column-value (VERB value) or
  ;; column-bytevector (VERB bytes), in the section: the index checked, then
  ;; the type, then the matching accessor. A NOMEM read answers failed first,
  ;; the state it leaves.
  (define (read-outcome verb connection handle sql column)
    (let ((found (column-index handle column)))
      (if (eq? (car found) 'refused)
          (values #f found)
          (let ((type (sqlite3-column-type handle column)))
            (cond
              ((eqv? type sqlite-null) (values #f (list 'value sql-null)))
              ((eqv? type sqlite-integer)
               (if (eq? verb 'value)
                   (values #f (list 'value (sqlite3-column-int64 handle column)))
                   (values #f (list 'refused 'not-text-or-blob column 'integer))))
              ((eqv? type sqlite-float)
               (if (eq? verb 'value)
                   (values #f (list 'value (sqlite3-column-double handle column)))
                   (values #f (list 'refused 'not-text-or-blob column 'float))))
              (else
               (let ((read (column-bytes connection handle column
                                         (if (eqv? type sqlite-text)
                                             sqlite3-column-text
                                             sqlite3-column-blob))))
                 (cond ((bytevector? read)
                        (values #f (if (and (eq? verb 'value) (eqv? type sqlite-text))
                                       (list 'text column read)
                                       (list 'value read))))
                       (else
                        (values 'failed
                                (list 'failed (cadr read) (caddr read) (string-copy sql))))))))))))

  ;; column-value : Statement Natural -> Value
  ;; Column COLUMN of ST's row, counted from 0, by its storage class,
  ;; sqlite3_column_type, never the declared type: INTEGER an exact integer,
  ;; FLOAT a flonum, TEXT a string decoded strictly, BLOB a fresh bytevector,
  ;; NULL sql-null. Allowed in row only. TEXT that is not well-formed UTF-8
  ;; raises &sqlite-invalid-text, and column-bytevector reads its bytes. A
  ;; read SQLite answers with NOMEM leaves ST failed and raises
  ;; &sqlite-error nomem, once (ADR-0015, decision 7; ADR-0014, amended).
  (define (column-value st column)
    (column-value/who 'column-value st column))

  ;; column-value/who : Symbol Statement Natural -> Value
  ;; column-value's work for WHO, which everything it raises names: the
  ;; conveniences read a row one column a section through it (Q15).
  (define (column-value/who who st column)
    (finish who
      (call-with-statement-handle who st 'column-value
        (lambda (connection handle sql)
          (read-outcome 'value connection handle sql column)))))

  ;; column-bytevector : Statement Natural -> (U Bytevector SqlNull)
  ;; Column COLUMN of ST's row as bytes, undecoded: TEXT through
  ;; sqlite3_column_text, so the bytes a TEXT value decodes from, BLOB
  ;; through sqlite3_column_blob, each a fresh bytevector; NULL sql-null; an
  ;; INTEGER or FLOAT value is not-text-or-blob. Allowed in row only. NOMEM
  ;; as column-value (ADR-0015, decision 8).
  (define (column-bytevector st column)
    (column-bytevector/who 'column-bytevector st column))

  ;; column-bytevector/who : Symbol Statement Natural -> (U Bytevector SqlNull)
  ;; column-bytevector's work for WHO, which everything it raises names.
  (define (column-bytevector/who who st column)
    (finish who
      (call-with-statement-handle who st 'column-bytevector
        (lambda (connection handle sql)
          (read-outcome 'bytes connection handle sql column)))))

  ;; column-name : Statement Natural -> String
  ;; Column COLUMN's name, counted from 0, decoded strictly: one that is not
  ;; well-formed UTF-8 raises &sqlite-invalid-text with the column's index.
  ;; Allowed in every state but finalized. sqlite3_column_name answering NULL
  ;; means an allocation failed, and SQLite sets no code for it, so it raises
  ;; &sqlite-error nomem with sqlite3_errstr's message. That leaves the
  ;; state as it was: no code sticks to the statement, so nothing else a
  ;; statement does fails for it, unlike a value's NOMEM (ADR-0015, decision
  ;; 9).
  (define (column-name st column)
    (column-name/who 'column-name st column))

  ;; column-name/who : Symbol Statement Natural -> String
  ;; column-name's work for WHO, which everything it raises names.
  (define (column-name/who who st column)
    (finish who
      (call-with-statement-handle who st 'column-name
        (lambda (connection handle sql)
          (values #f
                  (let ((found (column-index handle column)))
                    (if (eq? (car found) 'refused)
                        found
                        (let ((read (read-column-name (lambda () (sqlite3-column-name handle column))
                                                      c-string->bytevector)))
                          (if (bytevector? read)
                              (list 'name column read)
                              (list 'failed sqlite-nomem
                                    (or (c-string->string (sqlite3-errstr sqlite-nomem)) "")
                                    (string-copy sql))))))))))))
