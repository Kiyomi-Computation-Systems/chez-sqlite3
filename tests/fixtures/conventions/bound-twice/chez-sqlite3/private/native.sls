#!r6rs
(library (chez-sqlite3 private native)
  (export a b)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define a (foreign-procedure "sqlite3_errcode" (uptr) int))
  (define b (foreign-procedure "sqlite3_errcode" (uptr) int)))
