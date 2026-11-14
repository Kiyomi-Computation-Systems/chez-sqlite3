#!r6rs
(library (chez-sqlite3 private native)
  (export c)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define c (foreign-procedure "sqlite3_errcode" (uptr) int)))
