#!r6rs
;;; (chez-sqlite3 private verify): what a loaded libsqlite3 must offer
;;; (ADR-0002, ADR-0003, ADR-0010).
;;;
;;; Pure: the native layer reads sqlite3_libversion_number and
;;; sqlite3_threadsafe and hands their answers here, so
;;; tests/test-verify.sps can make every decision on synthetic inputs. Each
;;; check takes the library's report too, and every refusal carries it. Which
;;; runs first, the floor and then threadsafe, is native's order
;;; (ADR-0002, amended).
;;;
;;;   check-version     the version number at least the floor, else
;;;                     below-floor
;;;   check-threadsafe  sqlite3_threadsafe() not 0, else not-threadsafe
;;;
;;; The floor is held to packaging/floors.sexp by behaviour, in
;;; tests/test-verify.sps (ADR-0008, decision 4).
(library (chez-sqlite3 private verify)
  (export sqlite-floor check-version check-threadsafe version-number->string)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (chez-sqlite3 private conditions)
          (chez-sqlite3 private libsqlite3-info))

  ;; sqlite-floor : Natural
  ;; The oldest SQLite chez-sqlite3 loads, 3.45.1, as sqlite3_libversion_number
  ;; encodes it: X*1000000 + Y*1000 + Z (ADR-0003).
  (define sqlite-floor 3045001)

  ;; natural? : Any -> Boolean
  (define (natural? x)
    (and (exact-integer? x) (>= x 0)))

  ;; exact-integer? : Any -> Boolean
  (define (exact-integer? x)
    (and (number? x) (exact? x) (integer? x)))

  ;; check-version : String Integer String Symbol Libsqlite3-Info -> #t
  ;; #t when VERSION-NUM is at least the floor. Otherwise, any integer below
  ;; it, a negative one too, since sqlite3_libversion_number returns a C int,
  ;; raises &sqlite-library-unavailable, reason below-floor, carrying PATH,
  ;; SOURCE, VERSION-STRING as its detail, and LIBRARY. A VERSION-NUM that is
  ;; no exact integer, or a VERSION-STRING that is no string, is an assertion
  ;; violation.
  (define (check-version version-string version-num path source library)
    (unless (string? version-string)
      (assertion-violation 'check-version "the version string is not a string"
                           (shown-value version-string)))
    (unless (exact-integer? version-num)
      (assertion-violation 'check-version "the version number is not an exact integer"
                           (shown-value version-num)))
    (cond
      ((< version-num sqlite-floor)
       (refuse 'below-floor path source library version-string
               (string-append "libsqlite3 " version-string " is older than chez-sqlite3's floor, "
                              (version-number->string sqlite-floor)
                              "; name a newer one with CHEZ_SQLITE3_LIBRARY")))
      (else #t)))

  ;; check-threadsafe : Integer String Symbol Libsqlite3-Info -> #t
  ;; #t when ANSWER, what sqlite3_threadsafe answered, is not 0. SQLite answers
  ;; 0 if and only if its mutexes were compiled out. Otherwise raises
  ;; &sqlite-library-unavailable, reason not-threadsafe, detail 0, carrying
  ;; PATH, SOURCE and LIBRARY. An ANSWER that is no exact integer is an
  ;; assertion violation: 0 is truthy, and a flag cannot stand for it.
  (define (check-threadsafe answer path source library)
    (unless (exact-integer? answer)
      (assertion-violation 'check-threadsafe "the answer is not an exact integer"
                           (shown-value answer)))
    (cond
      ((= answer 0)
       (refuse 'not-threadsafe path source library 0
               "libsqlite3 was built without mutexes (THREADSAFE=0); name another with CHEZ_SQLITE3_LIBRARY"))
      (else #t)))

  ;; version-number->string : Natural -> String
  ;; X*1000000 + Y*1000 + Z as "X.Y.Z", each part in its own digits.
  (define (version-number->string num)
    (unless (natural? num)
      (assertion-violation 'version-number->string "not a natural" (shown-value num)))
    (string-append (number->string (div num 1000000)) "."
                   (number->string (div (mod num 1000000) 1000)) "."
                   (number->string (mod num 1000))))

  ;; refuse : Symbol String Symbol Libsqlite3-Info Any String -> Nothing
  (define (refuse reason path source library detail message)
    (raise-library-unavailable reason path source detail '() library message (list path))))
