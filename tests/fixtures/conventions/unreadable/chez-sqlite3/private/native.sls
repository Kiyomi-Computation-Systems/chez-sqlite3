#!r6rs
(library (chez-sqlite3 private native)
  (export a)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define a (foreign-procedure "sqlite3_errcode" (uptr) int))
