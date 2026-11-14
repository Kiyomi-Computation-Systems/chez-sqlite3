#!r6rs
(library (chez-sqlite3 private native)
  (export free)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define free (foreign-procedure "sqlite3_free" (uptr) void)))
