#!r6rs
(library (chez-sqlite3 private other)
  (export errcode)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define errcode (foreign-procedure "sqlite3_errcode" (uptr) int)))
