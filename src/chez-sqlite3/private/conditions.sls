#!r6rs
;;; (chez-sqlite3 private conditions): chez-sqlite3's condition types. Every
;;; one is a &chez-sqlite3-error, so a caller can catch the family or one
;;; member (ADR-0013).
;;;
;;;   &chez-sqlite3-error          the root, fieldless, under &error
;;;   &sqlite-library-unavailable  libsqlite3 was refused (ADR-0002)
;;;   &sqlite-error                SQLite answered a code that is an error
;;;   &sqlite-wrong-thread         a connection used off the thread that
;;;                                opened it (ADR-0010)
;;;   &sqlite-closed               a connection used once closed (ADR-0012)
;;;
;;; A raise may compound one with &who, &message and &irritants, so that the
;;; default handler prints readable text. Tests assert the reason symbol and
;;; the fields, never that text.
(library (chez-sqlite3 private conditions)
  (export &chez-sqlite3-error make-chez-sqlite3-error chez-sqlite3-error?

          &sqlite-library-unavailable make-sqlite-library-unavailable
          sqlite-library-unavailable?
          sqlite-library-unavailable-reason sqlite-library-unavailable-path
          sqlite-library-unavailable-source sqlite-library-unavailable-detail
          sqlite-library-unavailable-candidates
          sqlite-library-unavailable-library
          sqlite-library-unavailable-reasons

          raise-library-unavailable

          &sqlite-error make-sqlite-error sqlite-error?
          sqlite-error-code sqlite-error-extended-code sqlite-error-message
          sqlite-error-sql sqlite-error-offset
          raise-sqlite-error

          &sqlite-wrong-thread make-sqlite-wrong-thread sqlite-wrong-thread?
          sqlite-wrong-thread-owner sqlite-wrong-thread-caller
          raise-wrong-thread

          &sqlite-closed make-sqlite-closed sqlite-closed?
          raise-closed

          kind-of shown-value checked-accessor)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (chez-sqlite3 private libsqlite3-info)
          (only (chez-sqlite3 private constants) sqlite-result-code-name sqlite-primary-code-name))

  ;; make-chez-sqlite3-error : -> &chez-sqlite3-error
  ;; chez-sqlite3-error? : Any -> Boolean
  (define-condition-type &chez-sqlite3-error &error
    make-chez-sqlite3-error chez-sqlite3-error?)

  ;; --- a caller's value, as a refusal names it -------------------------------------

  ;; kind-of : Any -> Symbol
  ;; X's kind: string, list, number, boolean, char, symbol, bytevector,
  ;; vector, procedure or other. Pure.
  (define (kind-of x)
    (cond ((string? x) 'string)
          ((or (pair? x) (null? x)) 'list)
          ((number? x) 'number)
          ((boolean? x) 'boolean)
          ((char? x) 'char)
          ((symbol? x) 'symbol)
          ((bytevector? x) 'bytevector)
          ((vector? x) 'vector)
          ((procedure? x) 'procedure)
          (else 'other)))

  ;; shown-atom? : Any -> Boolean
  ;; Whether X is a symbol, a number, a boolean, a char or (): none holds a
  ;; filename, a URI or a key.
  (define (shown-atom? x)
    (or (symbol? x) (number? x) (boolean? x) (char? x) (null? x)))

  ;; shown-value : Any -> Any
  ;; X as a refusal or an assertion names a caller's value where another
  ;; belongs: itself when it is shown-atom?, or a proper list of them; else
  ;; (kind K), K its kind-of, never the value: a string, or a list holding
  ;; one, can be a filename or a URI that holds a key. Pure.
  (define (shown-value x)
    (if (or (shown-atom? x) (and (list? x) (for-all shown-atom? x)))
        x
        (list 'kind (kind-of x))))

  ;; checked-accessor : Symbol (Any -> Boolean) String (Any -> Any) -> (Any -> Any)
  ;; ACCESSOR, a record's or a condition type's, for WHO: called on what
  ;; PREDICATE holds; anything else an assertion violation from WHO, "not
  ;; WHAT", naming it by shown-value, never the value. Chez's own check named
  ;; what it refused (chez-curl ADR-0036).
  (define (checked-accessor who predicate what accessor)
    (lambda (x)
      (unless (predicate x)
        (assertion-violation who (string-append "not " what) (shown-value x)))
      (accessor x)))

  ;; --- &sqlite-library-unavailable ---------------------------------------------

  ;; sqlite-library-unavailable-reasons : (Listof Symbol)
  ;; Why a libsqlite3 was refused. They are the contract: tests and CI assert
  ;; these symbols, never the message (ADR-0002, amended).
  ;;
  ;;   invalid-override  CHEZ_SQLITE3_LIBRARY is set, but not to an absolute path
  ;;   not-found         no candidate exists
  ;;   load-failed       the loader refused the chosen path
  ;;   below-floor       the library is older than the floor
  ;;   not-threadsafe    sqlite3_threadsafe() answered 0: no mutexes
  ;;   missing-api       a required entry point is absent
  (define sqlite-library-unavailable-reasons
    '(invalid-override not-found load-failed below-floor not-threadsafe missing-api))

  ;; The fields:
  ;;
  ;;   reason      one of sqlite-library-unavailable-reasons
  ;;   path        (U String #f): the library refused, #f when none was chosen
  ;;   source      (U Symbol #f): where the path came from, one of
  ;;               (chez-sqlite3 private discovery)'s libsqlite3-sources, or #f
  ;;   detail      by reason: the override's value (invalid-override), the
  ;;               loader's message, the C name of an entry point that
  ;;               answered NULL, or the code sqlite3_initialize answered
  ;;               when it was not SQLITE_OK (load-failed), the version string
  ;;               (below-floor), 0 (not-threadsafe), the entry point's C name
  ;;               (missing-api), #f (not-found)
  ;;   candidates  (Listof String): every path checked, in order (not-found)
  ;;   library     (U Libsqlite3-Info #f): what the library reported, for a
  ;;               refusal made after its version was read (below-floor,
  ;;               not-threadsafe, missing-api, and load-failed from
  ;;               sqlite3_initialize); #f before that, and for a missing-api
  ;;               refusal of a report entry point, which is refused before
  ;;               the report exists
  (define-condition-type &sqlite-library-unavailable &chez-sqlite3-error
    unchecked-make-sqlite-library-unavailable sqlite-library-unavailable?
    (reason unchecked-sqlite-library-unavailable-reason)
    (path unchecked-sqlite-library-unavailable-path)
    (source unchecked-sqlite-library-unavailable-source)
    (detail unchecked-sqlite-library-unavailable-detail)
    (candidates unchecked-sqlite-library-unavailable-candidates)
    (library unchecked-sqlite-library-unavailable-library))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by shown-value, never printed, as
  ;; Chez's own check printed it.
  (define sqlite-library-unavailable-reason
    (checked-accessor 'sqlite-library-unavailable-reason sqlite-library-unavailable?
                      "a &sqlite-library-unavailable" unchecked-sqlite-library-unavailable-reason))
  (define sqlite-library-unavailable-path
    (checked-accessor 'sqlite-library-unavailable-path sqlite-library-unavailable?
                      "a &sqlite-library-unavailable" unchecked-sqlite-library-unavailable-path))
  (define sqlite-library-unavailable-source
    (checked-accessor 'sqlite-library-unavailable-source sqlite-library-unavailable?
                      "a &sqlite-library-unavailable" unchecked-sqlite-library-unavailable-source))
  (define sqlite-library-unavailable-detail
    (checked-accessor 'sqlite-library-unavailable-detail sqlite-library-unavailable?
                      "a &sqlite-library-unavailable" unchecked-sqlite-library-unavailable-detail))
  (define sqlite-library-unavailable-candidates
    (checked-accessor 'sqlite-library-unavailable-candidates sqlite-library-unavailable?
                      "a &sqlite-library-unavailable"
                      unchecked-sqlite-library-unavailable-candidates))
  (define sqlite-library-unavailable-library
    (checked-accessor 'sqlite-library-unavailable-library sqlite-library-unavailable?
                      "a &sqlite-library-unavailable" unchecked-sqlite-library-unavailable-library))

  ;; make-sqlite-library-unavailable : Symbol (U String #f) (U Symbol #f) Any
  ;;                                   (Listof String) (U Libsqlite3-Info #f)
  ;;                                   -> &sqlite-library-unavailable
  ;; Refuses a REASON that is not one of the six, and a LIBRARY that is
  ;; neither a libsqlite3-info nor #f, with an assertion violation, so a
  ;; misspelt reason cannot reach a caller who tests for the right one.
  (define (make-sqlite-library-unavailable reason path source detail candidates library)
    (unless (memq reason sqlite-library-unavailable-reasons)
      (assertion-violation 'make-sqlite-library-unavailable
                           "not a reason chez-sqlite3 refuses a libsqlite3 for"
                           (shown-value reason)))
    (unless (or (not library) (libsqlite3-info? library))
      (assertion-violation 'make-sqlite-library-unavailable
                           "a refusal's library is a libsqlite3-info or #f"
                           (shown-value library)))
    (unchecked-make-sqlite-library-unavailable reason path source detail candidates library))

  ;; raise-library-unavailable : Symbol (U String #f) (U Symbol #f) Any (Listof String)
  ;;                              (U Libsqlite3-Info #f) String (Listof Any) -> Nothing
  ;; The one way a private caller refuses a libsqlite3: raises a
  ;; &sqlite-library-unavailable built with REASON, PATH, SOURCE, DETAIL,
  ;; CANDIDATES and LIBRARY, compounded with &who chez-sqlite3, a &message
  ;; holding MESSAGE and &irritants holding IRRITANTS, so that the default
  ;; handler prints readable text. A REASON or LIBRARY the constructor
  ;; refuses is an assertion violation.
  (define (raise-library-unavailable reason path source detail candidates library
                                     message irritants)
    (raise (condition (make-sqlite-library-unavailable reason path source detail
                                                       candidates library)
                      (make-who-condition 'chez-sqlite3)
                      (make-message-condition message)
                      (make-irritants-condition irritants))))

  ;; --- &sqlite-error (ADR-0013, decision 3) -------------------------------------
  ;;
  ;;   code           the primary code's name: its C name without SQLITE_,
  ;;                  lower-cased, _ turned to -, by (chez-sqlite3 private
  ;;                  constants)' table; the integer when no row names it
  ;;   extended-code  the extended code's name by the same rule; a primary
  ;;                  code with no extension is its own
  ;;   message        sqlite3_errmsg for the connection, or sqlite3_errstr of
  ;;                  the code when there is none
  ;;   sql, offset    the statement's text and its error offset, from M2's
  ;;                  prepare; #f otherwise, as in all of M1
  (define-condition-type &sqlite-error &chez-sqlite3-error
    unchecked-make-sqlite-error sqlite-error?
    (code unchecked-sqlite-error-code)
    (extended-code unchecked-sqlite-error-extended-code)
    (message unchecked-sqlite-error-message)
    (sql unchecked-sqlite-error-sql)
    (offset unchecked-sqlite-error-offset))

  (define sqlite-error-code
    (checked-accessor 'sqlite-error-code sqlite-error? "an &sqlite-error"
                      unchecked-sqlite-error-code))
  (define sqlite-error-extended-code
    (checked-accessor 'sqlite-error-extended-code sqlite-error? "an &sqlite-error"
                      unchecked-sqlite-error-extended-code))
  (define sqlite-error-message
    (checked-accessor 'sqlite-error-message sqlite-error? "an &sqlite-error"
                      unchecked-sqlite-error-message))
  (define sqlite-error-sql
    (checked-accessor 'sqlite-error-sql sqlite-error? "an &sqlite-error"
                      unchecked-sqlite-error-sql))
  (define sqlite-error-offset
    (checked-accessor 'sqlite-error-offset sqlite-error? "an &sqlite-error"
                      unchecked-sqlite-error-offset))

  ;; exact-integer? : Any -> Boolean
  (define (exact-integer? x) (and (integer? x) (exact? x)))

  ;; exact-natural? : Any -> Boolean
  (define (exact-natural? x) (and (exact-integer? x) (>= x 0)))

  ;; refuse-field : Symbol Symbol String Any -> Nothing
  ;; WHO's refusal of VALUE for FIELD: an assertion violation, "not WHAT",
  ;; whose irritants are FIELD, then VALUE by shown-value, so two refusals
  ;; from one WHO are told apart without their message.
  (define (refuse-field who field what value)
    (assertion-violation who (string-append "not " what) field (shown-value value)))

  ;; make-sqlite-error : (U Symbol Integer) (U Symbol Integer) String (U String #f)
  ;;                     (U Natural #f) -> &sqlite-error
  ;; Each field checked, in order; a field of the wrong kind is refused by
  ;; refuse-field.
  (define (make-sqlite-error code extended-code message sql offset)
    (unless (or (symbol? code) (exact-integer? code))
      (refuse-field 'make-sqlite-error 'code "a code's name or an exact integer" code))
    (unless (or (symbol? extended-code) (exact-integer? extended-code))
      (refuse-field 'make-sqlite-error 'extended-code "a code's name or an exact integer"
                    extended-code))
    (unless (string? message)
      (refuse-field 'make-sqlite-error 'message "a string" message))
    (unless (or (not sql) (string? sql))
      (refuse-field 'make-sqlite-error 'sql "a string or #f" sql))
    (unless (or (not offset) (exact-natural? offset))
      (refuse-field 'make-sqlite-error 'offset "an exact natural or #f" offset))
    (unchecked-make-sqlite-error code extended-code message sql offset))

  ;; check-raise-who : Symbol Any -> Void
  ;; HELPER's refusal of a WHO that is no symbol.
  (define (check-raise-who helper who)
    (unless (symbol? who)
      (refuse-field helper 'who "a symbol" who)))

  ;; raise-sqlite-error : Symbol Integer String (U String #f) (U Natural #f) -> Nothing
  ;; The one way a private caller raises SQLite's answer: an &sqlite-error
  ;; whose code and extended code are EXTENDED's names, from constants' table,
  ;; with MESSAGE, SQL and OFFSET, compounded with &who WHO and a &message
  ;; holding MESSAGE, so the default handler prints SQLite's text. A WHO that
  ;; is no symbol, an EXTENDED that is no exact integer, and one whose low
  ;; byte is SQLITE_OK, SQLITE_ROW or SQLITE_DONE, which are no errors, are
  ;; assertion violations from raise-sqlite-error; a field the constructor
  ;; refuses, one from make-sqlite-error.
  (define (raise-sqlite-error who extended message sql offset)
    (check-raise-who 'raise-sqlite-error who)
    (unless (exact-integer? extended)
      (refuse-field 'raise-sqlite-error 'extended-code "an exact integer" extended))
    (when (memv (bitwise-and extended 255) '(0 100 101))
      (assertion-violation 'raise-sqlite-error "not a code SQLite answers for an error"
                           'not-an-error extended))
    (let* ((c (make-sqlite-error (sqlite-primary-code-name extended)
                                 (sqlite-result-code-name extended) message sql offset))
           (compound (condition c (make-who-condition who) (make-message-condition message))))
      (raise compound)))

  ;; --- &sqlite-wrong-thread (ADR-0010, decision 1; ADR-0013, decision 6) ---------
  ;;
  ;;   owner   the get-thread-id of the thread that opened the connection
  ;;   caller  the get-thread-id of the thread that used it
  (define-condition-type &sqlite-wrong-thread &chez-sqlite3-error
    unchecked-make-sqlite-wrong-thread sqlite-wrong-thread?
    (owner unchecked-sqlite-wrong-thread-owner)
    (caller unchecked-sqlite-wrong-thread-caller))

  (define sqlite-wrong-thread-owner
    (checked-accessor 'sqlite-wrong-thread-owner sqlite-wrong-thread? "an &sqlite-wrong-thread"
                      unchecked-sqlite-wrong-thread-owner))
  (define sqlite-wrong-thread-caller
    (checked-accessor 'sqlite-wrong-thread-caller sqlite-wrong-thread? "an &sqlite-wrong-thread"
                      unchecked-sqlite-wrong-thread-caller))

  ;; make-sqlite-wrong-thread : Natural Natural -> &sqlite-wrong-thread
  ;; OWNER and CALLER checked, each an exact natural, as a thread id is.
  (define (make-sqlite-wrong-thread owner caller)
    (unless (exact-natural? owner)
      (refuse-field 'make-sqlite-wrong-thread 'owner "a thread id" owner))
    (unless (exact-natural? caller)
      (refuse-field 'make-sqlite-wrong-thread 'caller "a thread id" caller))
    (unchecked-make-sqlite-wrong-thread owner caller))

  ;; raise-wrong-thread : Symbol Natural Natural -> Nothing
  ;; An &sqlite-wrong-thread of OWNER and CALLER, compounded with &who WHO and
  ;; a &message. A WHO that is no symbol is an assertion violation from
  ;; raise-wrong-thread; an id the constructor refuses, one from it.
  (define (raise-wrong-thread who owner caller)
    (check-raise-who 'raise-wrong-thread who)
    (let* ((c (make-sqlite-wrong-thread owner caller))
           (compound (condition c (make-who-condition who)
                                (make-message-condition
                                 "a connection belongs to the thread that opened it, and is used on that thread alone"))))
      (raise compound)))

  ;; --- &sqlite-closed (ADR-0012, decision 7; ADR-0013, decision 6) ----------------

  ;; make-sqlite-closed : -> &sqlite-closed
  ;; sqlite-closed? : Any -> Boolean
  (define-condition-type &sqlite-closed &chez-sqlite3-error
    make-sqlite-closed sqlite-closed?)

  ;; raise-closed : Symbol -> Nothing
  ;; An &sqlite-closed, compounded with &who WHO and a &message. A WHO that is
  ;; no symbol is an assertion violation from raise-closed.
  (define (raise-closed who)
    (check-raise-who 'raise-closed who)
    (raise (condition (make-sqlite-closed) (make-who-condition who)
                      (make-message-condition "the connection is closed"))))

  ;; sqlite-error? : Any -> Boolean
  ;; sqlite-error-code : &sqlite-error -> (U Symbol Integer)
  ;; sqlite-error-extended-code : &sqlite-error -> (U Symbol Integer)
  ;; sqlite-error-message : &sqlite-error -> String
  ;; sqlite-error-sql : &sqlite-error -> (U String #f)
  ;; sqlite-error-offset : &sqlite-error -> (U Natural #f)
  ;; sqlite-wrong-thread? : Any -> Boolean
  ;; sqlite-wrong-thread-owner : &sqlite-wrong-thread -> Natural
  ;; sqlite-wrong-thread-caller : &sqlite-wrong-thread -> Natural
  ;; sqlite-library-unavailable? : Any -> Boolean
  ;; sqlite-library-unavailable-reason : &sqlite-library-unavailable -> Symbol
  ;; sqlite-library-unavailable-path : &sqlite-library-unavailable -> (U String #f)
  ;; sqlite-library-unavailable-source : &sqlite-library-unavailable -> (U Symbol #f)
  ;; sqlite-library-unavailable-detail : &sqlite-library-unavailable -> Any
  ;; sqlite-library-unavailable-candidates : &sqlite-library-unavailable
  ;;                                         -> (Listof String)
  ;; sqlite-library-unavailable-library : &sqlite-library-unavailable
  ;;                                      -> (U Libsqlite3-Info #f)
  )
