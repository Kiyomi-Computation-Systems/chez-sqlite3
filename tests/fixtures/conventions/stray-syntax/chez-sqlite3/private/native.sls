#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. bind-required
;;; has the one (syntax foreign-procedure) in its fender, which is allowed,
;;; and a second, in the same fender, which is not.
(library (chez-sqlite3 private native)
  (export errcode)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define-syntax bind-required
    (lambda (x)
      (syntax-case x ()
        ((_ library (fp convention ... entry (arg ...) result))
         (and (identifier? #'fp)
              (free-identifier=? #'fp #'foreign-procedure)
              (free-identifier=? #'fp #'foreign-procedure))
         #'(begin
             (required-entry entry library)
             (fp convention ... entry (arg ...) result))))))
  (define errcode
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_errcode" (uptr) int)))))
