#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. The keyword
;;; bound to a variable.
(library (chez-sqlite3 private native)
  (export fp)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define fp foreign-procedure))
