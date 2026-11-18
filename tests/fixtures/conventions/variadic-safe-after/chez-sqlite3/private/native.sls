#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. The same two
;;; conventions, the other way round.
(library (chez-sqlite3 private native)
  (export db-config)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define db-config
    (load-step
     (bind-required report
       (foreign-procedure (__varargs_after 2) __collect_safe "sqlite3_db_config" (uptr int int uptr) int)))))
