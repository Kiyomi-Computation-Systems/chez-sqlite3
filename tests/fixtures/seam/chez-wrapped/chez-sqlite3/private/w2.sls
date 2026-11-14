#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private w2)
  (export w2)
  (import (rnrs) (prefix (chezscheme) c:))
  (define w2 1))
