#!r6rs
;;; (chez-sqlite3 private conditions): chez-sqlite3's condition types. Every
;;; one is a &chez-sqlite3-error, so a caller can catch the family or one
;;; member (ADR-0013).
;;;
;;;   &chez-sqlite3-error          the root, fieldless, under &error
;;;   &sqlite-library-unavailable  libsqlite3 was refused (ADR-0002)
;;;
;;; &sqlite-error, &sqlite-wrong-thread and &sqlite-closed join them in later
;;; slices.
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

          kind-of shown-value checked-accessor)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (chez-sqlite3 private libsqlite3-info))

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
  ;;               loader's message (load-failed), the version string
  ;;               (below-floor), 0 (not-threadsafe), the entry point's C name
  ;;               (missing-api), #f (not-found)
  ;;   candidates  (Listof String): every path checked, in order (not-found)
  ;;   library     (U Libsqlite3-Info #f): what the library reported, for a
  ;;               refusal made after its version was read (below-floor,
  ;;               not-threadsafe, missing-api); #f before that
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
                           reason))
    (unless (or (not library) (libsqlite3-info? library))
      (assertion-violation 'make-sqlite-library-unavailable
                           "a refusal's library is a libsqlite3-info or #f"
                           library))
    (unchecked-make-sqlite-library-unavailable reason path source detail candidates library))

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
