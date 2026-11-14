#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private w5)
  (export w5)
  (import (rnrs) (library (chezscheme)))
  (define w5 1))
