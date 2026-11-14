#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. A (syntax
;;; foreign-procedure) in the fender of a macro that is not bind-required.
(library (chez-sqlite3 private native)
  (export errcode)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define-syntax other-required
    (lambda (x)
      (syntax-case x ()
        ((_ fp)
         (free-identifier=? #'fp #'foreign-procedure)
         #'(begin)))))
  (define errcode
    (load-step
     (other-required report
       (foreign-procedure "sqlite3_errcode" (uptr) int)))))
