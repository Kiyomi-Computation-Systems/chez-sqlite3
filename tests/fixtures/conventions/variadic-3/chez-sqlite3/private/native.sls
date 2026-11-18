#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. sqlite3_db_config
;;; bound with three named parameters, where its prototype has two.
(library (chez-sqlite3 private native)
  (export db-config)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define db-config
    (load-step
     (bind-required report
       (foreign-procedure (__varargs_after 3) "sqlite3_db_config" (uptr int int uptr) int)))))
