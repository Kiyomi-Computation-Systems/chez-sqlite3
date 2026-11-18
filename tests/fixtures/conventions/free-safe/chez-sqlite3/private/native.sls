#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. sqlite3_free
;;; bound __collect_safe.
(library (chez-sqlite3 private native)
  (export free)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define free
    (load-step
     (bind-required report
       (foreign-procedure __collect_safe "sqlite3_free" (uptr) void)))))
