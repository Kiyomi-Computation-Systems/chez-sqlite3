#!r6rs
;;; (chez-sqlite3 private libsqlite3-info): what a loaded libsqlite3 reports
;;; about itself (ADR-0002). (chez-sqlite3 private native) builds one when it
;;; has read sqlite3_libversion_number, sqlite3_libversion and
;;; sqlite3_sourceid; every refusal made after that read carries it, as
;;; &sqlite-library-unavailable's library.
;;;
;;; It is a library of its own because a refusal's report must be readable
;;; after the refusal. Reading an accessor runs the library that defines it,
;;; and native's body raises its refusal again at every reference. This
;;; library's body defines a record type and procedures only, so it cannot
;;; raise.
(library (chez-sqlite3 private libsqlite3-info)
  (export make-libsqlite3-info libsqlite3-info?
          libsqlite3-info-path libsqlite3-info-source libsqlite3-info-version
          libsqlite3-info-version-number libsqlite3-info-source-id)
  (import (chez-sqlite3 private require-threaded)
          (rnrs))

  ;; make-libsqlite3-info : String Symbol String Natural String -> Libsqlite3-Info
  ;; Private, and built by native alone from what the library answered, so it
  ;; checks nothing: it answers what it was given.
  ;; libsqlite3-info? : Any -> Boolean
  ;; libsqlite3-info-path : Libsqlite3-Info -> String
  ;;   the path loaded, absolute
  ;; libsqlite3-info-source : Libsqlite3-Info -> Symbol
  ;;   where the path came from: one of (chez-sqlite3 private discovery)'s
  ;;   libsqlite3-sources
  ;; libsqlite3-info-version : Libsqlite3-Info -> String
  ;;   sqlite3_libversion, "3.45.1"
  ;; libsqlite3-info-version-number : Libsqlite3-Info -> Natural
  ;;   sqlite3_libversion_number, 3045001
  ;; libsqlite3-info-source-id : Libsqlite3-Info -> String
  ;;   sqlite3_sourceid
  ;; Opaque, so that record-rtd on a report raises. Its type, once read, builds
  ;; a report holding any path and version, which libsqlite3-info? and the
  ;; accessors then take for a genuine one.
  (define-record-type libsqlite3-info
    (fields (immutable path unchecked-libsqlite3-info-path)
            (immutable source unchecked-libsqlite3-info-source)
            (immutable version unchecked-libsqlite3-info-version)
            (immutable version-number unchecked-libsqlite3-info-version-number)
            (immutable source-id unchecked-libsqlite3-info-source-id))
    (sealed #t)
    (opaque #t))

  ;; shown : Any -> Any
  ;; X as an accessor's refusal names it: (chez-sqlite3 private conditions)'
  ;; shown-value's rule, which this library cannot import, since that one
  ;; imports this: a symbol, a number, a boolean, a char, (), or a proper
  ;; list of them, as itself; anything else (kind K), never the value.
  ;; tests/test-conditions.sps holds the two alike. Pure.
  (define (shown x)
    (define (atom? y) (or (symbol? y) (number? y) (boolean? y) (char? y) (null? y)))
    (cond ((or (atom? x) (and (list? x) (for-all atom? x))) x)
          ((string? x) '(kind string))
          ((pair? x) '(kind list))
          ((bytevector? x) '(kind bytevector))
          ((vector? x) '(kind vector))
          ((procedure? x) '(kind procedure))
          (else '(kind other))))

  ;; checked : Symbol (Libsqlite3-Info -> Any) -> (Any -> Any)
  ;; ACCESSOR for WHO, called on a report alone; anything else an assertion
  ;; violation from WHO naming it by shown, never the value: Chez's own check
  ;; printed what it refused (chez-curl ADR-0036). A procedure is all this
  ;; makes, so the body still cannot raise.
  (define (checked who accessor)
    (lambda (x)
      (unless (libsqlite3-info? x)
        (assertion-violation who "not a libsqlite3-info" (shown x)))
      (accessor x)))

  (define libsqlite3-info-path (checked 'libsqlite3-info-path unchecked-libsqlite3-info-path))
  (define libsqlite3-info-source (checked 'libsqlite3-info-source unchecked-libsqlite3-info-source))
  (define libsqlite3-info-version
    (checked 'libsqlite3-info-version unchecked-libsqlite3-info-version))
  (define libsqlite3-info-version-number
    (checked 'libsqlite3-info-version-number unchecked-libsqlite3-info-version-number))
  (define libsqlite3-info-source-id
    (checked 'libsqlite3-info-source-id unchecked-libsqlite3-info-source-id)))
