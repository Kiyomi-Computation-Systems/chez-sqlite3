#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. It names the
;;; word foreign-procedure everywhere it is not a form, and three times where
;;; it is: (foreign-procedure "sqlite3_close" (uptr) int) in this comment is no form.
(library (chez-sqlite3 private native)
  (export open errstr used)
  (import (rnrs)
          (only (chezscheme) foreign-entry? foreign-procedure foreign-ref))

  (define text "(foreign-procedure \"sqlite3_close\" (uptr) int)")
  (define quoted-name 'foreign-procedure)
  (define the-syntax (lambda (x) #'foreign-procedure))
  (define a-tail '(this list ends in the tail foreign-procedure))

  (define open
    (load-step
     (bind-required report
       (foreign-procedure __collect_safe "sqlite3_open_v2" (uptr uptr int uptr) int))))

  (define errstr
    (let ((unused 1))
      (lambda ()
        (let loop ()
          (foreign-procedure "sqlite3_errstr" (int) uptr)))))

  (define used
    '#((foreign-procedure "sqlite3_memory_used" () integer-64))))
