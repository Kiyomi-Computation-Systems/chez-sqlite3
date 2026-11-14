#!r6rs
(library (chez-sqlite3 private native)
  (export a b c d e)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define a (foreign-procedure "sqlite3_close" argument-types int))
  (define b (foreign-procedure "sqlite3_errcode" (uptr . uptr) int))
  (define c (foreign-procedure "sqlite3_errmsg" (uptr) "uptr"))
  (define d (foreign-procedure "sqlite3_errstr" (7) uptr))
  (define e (foreign-procedure "sqlite3_next_stmt" #(uptr uptr) uptr)))
