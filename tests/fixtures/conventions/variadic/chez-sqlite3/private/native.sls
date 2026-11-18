#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. sqlite3_db_config
;;; bound as the M4 plan's section 4.2 writes it: no violation.
(library (chez-sqlite3 private native)
  (export db-config)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define db-config
    (load-step
     (bind-required report
       (foreign-procedure (__varargs_after 2) "sqlite3_db_config" (uptr int int uptr) int)))))
