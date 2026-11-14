#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private w4)
  (export w4)
  (import (rnrs) (for (chezscheme) expand))
  (define w4 1))
