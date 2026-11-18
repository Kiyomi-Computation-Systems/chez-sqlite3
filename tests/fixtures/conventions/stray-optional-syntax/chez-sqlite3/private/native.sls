#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. bind-optional
;;; has the one (syntax foreign-procedure) in its fender, which is allowed,
;;; and a second, in the same fender, which is not; bind-required has none,
;;; so its allowance cannot cover the second.
(library (chez-sqlite3 private native)
  (export load-extension)
  (import (rnrs) (only (chezscheme) foreign-entry? foreign-procedure))
  (define-syntax bind-optional
    (lambda (x)
      (syntax-case x ()
        ((_ (fp convention ... entry (arg ...) result))
         (and (identifier? #'fp)
              (free-identifier=? #'fp #'foreign-procedure)
              (free-identifier=? #'fp #'foreign-procedure))
         #'(and (foreign-entry? entry)
                (fp convention ... entry (arg ...) result))))))
  (define load-extension
    (load-step
     (bind-optional
       (foreign-procedure __collect_safe "sqlite3_load_extension" (uptr uptr uptr uptr) int)))))
