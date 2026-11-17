#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. sqlite3_db_config
;;; bound plain: on Apple arm64 its variadic arguments go where the callee
;;; never reads them.
(library (chez-sqlite3 private native)
  (export db-config)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define db-config
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_db_config" (uptr int int uptr) int)))))
