#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. A keyword alias
;;; hides a binding: no form is headed by foreign-procedure, but the symbol
;;; is used.
(library (chez-sqlite3 private native)
  (export sneaky-errstr)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define-syntax fp (identifier-syntax foreign-procedure))
  (define sneaky-errstr (fp "sqlite3_errstr" (int) string)))
