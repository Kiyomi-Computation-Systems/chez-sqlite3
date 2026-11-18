#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. The count's two
;;; words written bare, outside their list, and the list written twice.
(library (chez-sqlite3 private native)
  (export db-config db-config-twice)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define db-config
    (load-step
     (bind-required report
       (foreign-procedure __varargs_after 2 "sqlite3_db_config" (uptr int int uptr) int))))
  (define db-config-twice
    (load-step
     (bind-required report
       (foreign-procedure (__varargs_after 2) (__varargs_after 2) "sqlite3_errcode" (uptr) int)))))
