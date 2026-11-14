#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private w)
  (export w)
  (import (rnrs) (chezscheme))
  (define w 1))
