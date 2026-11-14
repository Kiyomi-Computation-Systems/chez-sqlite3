#!r6rs
;;; tests/preflight.sps: what `make build` runs. chez-sqlite3 compiles nothing
;;; (ADR-0001), so build answers the question an install raises instead:
;;; which libsqlite3 would chez-sqlite3 load here, and does it accept it?
;;;
;;; Accepted: it prints the path and its source, the version and its number,
;;; and the source id, on stdout, and exits 0. Refused: it prints
;;; (reason . SYMBOL), then the path, the source, the detail, the version and
;;; source id when the refusal came after the library said what it is, every
;;; candidate checked and a one-line remedy, on stderr, and exits 1. The
;;; reason is the contract; the rest is for the reader (ADR-0002). Anything
;;; else raised is a bug, not a refusal, and is left to Chez's default
;;; handler, which exits non-zero. The report's accessors live in
;;; (chez-sqlite3 private libsqlite3-info), whose body cannot raise, so
;;; reading a refusal's report never runs the load again.
;;;
;;; It does not import (chez-sqlite3 private native): Chez would run native's
;;; body, which is the load, before this program's guard could catch a
;;; refusal (AGENTS.md). It evaluates (loaded-libsqlite3) in native's
;;; environment inside the guard instead. Until M1 slice 4 there is no public
;;; library to load through.
(import (rnrs)
        (only (chezscheme) eval environment)
        (chez-sqlite3 private conditions)
        (chez-sqlite3 private libsqlite3-info))

;; say : Output-Port Any ... -> Void
;; PARTS displayed, then a newline.
(define (say port . parts)
  (for-each (lambda (part) (display part port)) parts)
  (newline port))

(define (or-none value) (or value "none"))

(guard (e ((sqlite-library-unavailable? e)
           (let ((err (current-error-port))
                 (candidates (sqlite-library-unavailable-candidates e))
                 (library (sqlite-library-unavailable-library e)))
             (say err "chez-sqlite3: libsqlite3 refused")
             (write (cons 'reason (sqlite-library-unavailable-reason e)) err)
             (newline err)
             (say err "  path:       " (or-none (sqlite-library-unavailable-path e)))
             (say err "  source:     " (or-none (sqlite-library-unavailable-source e)))
             (say err "  detail:     " (or-none (sqlite-library-unavailable-detail e)))
             (when library
               (say err "  version:    " (libsqlite3-info-version library)
                    " (" (libsqlite3-info-version-number library) ")")
               (say err "  source id:  " (libsqlite3-info-source-id library)))
             (if (null? candidates)
                 (say err "  candidates: none")
                 (begin
                   (say err "  candidates:")
                   (for-each (lambda (path) (say err "    " path)) candidates)))
             (say err "  remedy:     " (if (message-condition? e)
                                            (condition-message e)
                                            "name a usable libsqlite3 with CHEZ_SQLITE3_LIBRARY, an absolute path"))
             (exit 1))))
  (let ((info (eval '(loaded-libsqlite3) (environment '(chez-sqlite3 private native))))
        (out (current-output-port)))
    (say out "chez-sqlite3: libsqlite3 loaded and accepted")
    (say out "  path:       " (libsqlite3-info-path info) " (" (libsqlite3-info-source info) ")")
    (say out "  version:    " (libsqlite3-info-version info)
         " (" (libsqlite3-info-version-number info) ")")
    (say out "  source id:  " (libsqlite3-info-source-id info))
    (exit 0)))
