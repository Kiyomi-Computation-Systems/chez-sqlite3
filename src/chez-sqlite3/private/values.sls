#!r6rs
;;; (chez-sqlite3 private values): the pure core of binding a value and of
;;; reading a column (ADR-0015). Data in, data out: no foreign code, and
;;; nothing here loads libsqlite3.
;;;
;;;   sql-null            SQL's NULL, the one instance of a record type
;;;                       nobody else can make an instance of
;;;   bind-plan           how a Scheme value binds, or the rule that refuses it
;;;   raise-bind-refusal  a refusal as an assertion violation, naming the
;;;                       value's kind, never the value
;;;   read-column-bytes, read-column-name
;;;                       what a column read does with a NULL pointer, with
;;;                       the foreign calls it orders passed as procedures
;;;
;;; Slices 3 and 4 call bind-plan and the readers inside critical sections,
;;; where nothing may raise: they answer data for every value of their stated
;;; type, a refusal included, and raise-bind-refusal is the one that raises,
;;; called after the section.
(library (chez-sqlite3 private values)
  (export sql-null sql-null? bind-plan bind-refusal-rules raise-bind-refusal
          read-column-bytes read-column-name)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (only (chez-sqlite3 private conditions) kind-of shown-value))

  ;; --- sql-null ------------------------------------------------------------------

  ;; The type is generative (no nongenerative clause: no other definition can
  ;; name it), sealed and opaque (record-rtd refuses its instance, so no one
  ;; can rebuild another from its type). Neither it nor its constructor is
  ;; exported: the one instance below is the only one there is.
  (define-record-type sql-null-type (sealed #t) (opaque #t))

  ;; sql-null : SqlNull
  (define sql-null (make-sql-null-type))

  ;; sql-null? : Any -> Boolean
  (define (sql-null? x) (eq? x sql-null))

  ;; --- the bind plan ---------------------------------------------------------------

  ;; exact-integer? : Any -> Boolean
  (define (exact-integer? x) (and (integer? x) (exact? x)))

  ;; bind-refusal-rules : (Listof Symbol)
  ;; The rules bind-plan refuses a value by:
  ;;
  ;;   integer-out-of-range  an exact integer outside -2^63 to 2^63-1
  ;;   nan                   any NaN
  ;;   boolean               #t and #f (D5)
  ;;   not-a-value           anything else
  (define bind-refusal-rules '(integer-out-of-range nan boolean not-a-value))

  ;; bind-plan : Any -> (U (List 'int64 Integer) (List 'double Flonum)
  ;;                       (List 'text Bytevector) (List 'blob Bytevector)
  ;;                       (List 'null) (List 'refused Symbol))
  ;; How a value binds, or the rule that refuses it. Total: it raises
  ;; nothing, for any value. An integer is int64 from -2^63 to 2^63-1 (Chez's
  ;; own integer-64 check wraps 2^63 and raises at 2^64, so the check is
  ;; ours); a flonum that is no NaN, +inf.0, -inf.0 and -0.0 included, is a
  ;; double; a string is text, a fresh bytevector of its UTF-8, a U+0000
  ;; kept; a bytevector is a blob, a fresh copy, never the caller's object;
  ;; sql-null is null.
  (define (bind-plan v)
    (cond ((sql-null? v) (list 'null))
          ((string? v) (list 'text (string->utf8 v)))
          ((bytevector? v) (list 'blob (bytevector-copy v)))
          ((exact-integer? v)
           (if (and (>= v (- (expt 2 63))) (< v (expt 2 63)))
               (list 'int64 v)
               (list 'refused 'integer-out-of-range)))
          ((flonum? v)
           (if (nan? v) (list 'refused 'nan) (list 'double v)))
          ((boolean? v) (list 'refused 'boolean))
          (else (list 'refused 'not-a-value))))

  ;; refusal-advice : Symbol -> String
  ;; What to do about a refusal by RULE: the message says it.
  (define (refusal-advice rule)
    (case rule
      ((integer-out-of-range)
       "an integer binds as 64 bits, -2^63 to 2^63-1: pass a smaller one, or a string or a blob")
      ((nan) "SQLite stores no NaN: pass sql-null for a missing value")
      ((boolean) "SQL has no boolean: pass 1 or 0")
      (else "pass an exact integer, a flonum, a string, a bytevector or sql-null")))

  ;; raise-bind-refusal : Symbol (U Positive-Integer String) Any Symbol -> Nothing
  ;; A WHO that is no symbol is an assertion violation from
  ;; raise-bind-refusal, checked first, its irritants (who V) with V by
  ;; shown-value. Else an assertion violation from WHO for the value a bind refused: its
  ;; irritants are RULE, PARAMETER (itself when an exact positive integer,
  ;; else (kind K) of its kind) and (kind K) of VALUE's kind. The value is
  ;; never shown: a bound value can be a secret (ADR-0015, decision 2). A
  ;; RULE outside bind-refusal-rules is an assertion violation from
  ;; raise-bind-refusal, led by not-a-rule.
  (define (raise-bind-refusal who parameter value rule)
    (unless (symbol? who)
      (assertion-violation 'raise-bind-refusal "not a symbol" 'who (shown-value who)))
    (unless (memq rule bind-refusal-rules)
      (assertion-violation 'raise-bind-refusal "not a rule bind-plan refuses by"
                           'not-a-rule (if (symbol? rule) rule (list 'kind (kind-of rule)))))
    (assertion-violation who (refusal-advice rule)
                         rule
                         (if (and (exact-integer? parameter) (> parameter 0))
                             parameter
                             (list 'kind (kind-of parameter)))
                         (list 'kind (kind-of value))))

  ;; --- the column readers ----------------------------------------------------------

  ;; read-column-bytes : (-> Natural) (-> Integer) (-> String) (-> Natural)
  ;;                      (Natural Natural -> Bytevector)
  ;;                      -> (U Bytevector (List 'nomem Integer String))
  ;; POINTER stands for sqlite3_column_text or _blob, ERRCODE for
  ;; sqlite3_extended_errcode, ERRMSG for sqlite3_errmsg, BYTES for
  ;; sqlite3_column_bytes and COPY for a copy out of a pointer. POINTER is
  ;; called first. When it answers 0, ERRCODE is called at once, before
  ;; anything else: a code whose low byte is 7 (NOMEM) then calls ERRMSG, right
  ;; after the code, and answers (nomem CODE MESSAGE); any other code answers
  ;; an empty bytevector, and ERRMSG is never called. BYTES and COPY are never
  ;; called on a 0 pointer. Otherwise BYTES is called, then (COPY pointer n)
  ;; answered, and ERRCODE and ERRMSG never (ADR-0015, decision 7). It raises
  ;; nothing itself; the order is the let*'s, never an argument order.
  (define (read-column-bytes pointer errcode errmsg bytes copy)
    (let ((p (pointer)))
      (if (eqv? p 0)
          (let ((code (errcode)))
            (if (= (bitwise-and code 255) 7)
                (let ((message (errmsg)))
                  (list 'nomem code message))
                (make-bytevector 0 0)))
          (let ((n (bytes)))
            (copy p n)))))

  ;; read-column-name : (-> Natural) (Natural -> Bytevector)
  ;;                    -> (U Bytevector 'nomem)
  ;; NAME stands for sqlite3_column_name, COPY-C-STRING for a copy of a C
  ;; string out of a pointer. A 0 pointer answers nomem and calls nothing
  ;; else: SQLite sets no error code for this NULL (ADR-0015, decision 9).
  ;; Any other answers (COPY-C-STRING pointer).
  (define (read-column-name name copy-c-string)
    (let ((p (name)))
      (if (eqv? p 0)
          'nomem
          (copy-c-string p)))))
