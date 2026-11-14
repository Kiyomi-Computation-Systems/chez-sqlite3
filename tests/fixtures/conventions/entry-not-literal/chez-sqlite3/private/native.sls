#!r6rs
(library (chez-sqlite3 private native)
  (export a b c d e)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define a (foreign-procedure entry-name (uptr) int))
  (define b (foreign-procedure (string-append "sqlite3_" "close") (uptr) int))
  (define c (foreign-procedure 'sqlite3_close (uptr) int))
  (define d (foreign-procedure __collect_safe (uptr) int))
  (define e (foreign-procedure)))
