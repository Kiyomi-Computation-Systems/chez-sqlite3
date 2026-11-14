#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. The three
;;; places foreign-procedure may appear besides a form's head: the import
;;; clause, bind-required's fender, and nowhere else. No violation.
(library (chez-sqlite3 private native)
  (export errcode)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define-syntax bind-required
    (lambda (x)
      (syntax-case x ()
        ((_ library (fp convention ... entry (arg ...) result))
         (and (identifier? #'fp)
              (free-identifier=? #'fp #'foreign-procedure))
         #'(begin
             (required-entry entry library)
             (fp convention ... entry (arg ...) result))))))
  (define errcode
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_errcode" (uptr) int)))))
