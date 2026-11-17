#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. Each binder,
;;; bind-required and bind-optional, has one (syntax foreign-procedure) in
;;; its fender, and binds one form; with the import entry and the forms'
;;; heads, that is all there is. No violation.
(library (chez-sqlite3 private native)
  (export errcode load-extension)
  (import (rnrs) (only (chezscheme) foreign-entry? foreign-procedure))
  (define-syntax bind-required
    (lambda (x)
      (syntax-case x ()
        ((_ library (fp convention ... entry (arg ...) result))
         (and (identifier? #'fp)
              (free-identifier=? #'fp #'foreign-procedure))
         #'(begin
             (required-entry entry library)
             (fp convention ... entry (arg ...) result))))))
  (define-syntax bind-optional
    (lambda (x)
      (syntax-case x ()
        ((_ (fp convention ... entry (arg ...) result))
         (and (identifier? #'fp)
              (free-identifier=? #'fp #'foreign-procedure))
         #'(and (foreign-entry? entry)
                (fp convention ... entry (arg ...) result))))))
  (define errcode
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_errcode" (uptr) int))))
  (define load-extension
    (load-step
     (bind-optional
       (foreign-procedure __collect_safe "sqlite3_load_extension" (uptr uptr uptr uptr) int)))))
