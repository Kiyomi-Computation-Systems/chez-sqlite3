#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private w3)
  (export w3)
  (import (rnrs) (rename (chezscheme) (car kar)))
  (define w3 1))
