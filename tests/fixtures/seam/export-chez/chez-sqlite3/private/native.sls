#!r6rs
;;; Fixture for tests/test-check-seam.sps: plain, and through a rename spec: each named in export order.
(library (chez-sqlite3 private native)
  (export foreign-procedure (rename (foreign-ref raw-ref)))
  (import (chez-sqlite3 private require-threaded) (rnrs) (only (chezscheme) foreign-procedure foreign-ref))
  (define native 1))
