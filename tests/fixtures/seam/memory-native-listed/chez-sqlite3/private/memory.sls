#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private memory)
  (export allocate)
  (import (chez-sqlite3 private require-threaded) (rnrs) (only (chezscheme) foreign-alloc foreign-free critical-section make-mutex with-mutex))
  (define allocate 1))
