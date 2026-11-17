#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. sqlite3_db_config
;;; bound __collect_safe beside its variadic convention: it never waits, so
;;; it is plain (ADR-0011, amended 2026-11-17).
(library (chez-sqlite3 private native)
  (export db-config)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define db-config
    (load-step
     (bind-required report
       (foreign-procedure __collect_safe (__varargs_after 2) "sqlite3_db_config" (uptr int int uptr) int)))))
