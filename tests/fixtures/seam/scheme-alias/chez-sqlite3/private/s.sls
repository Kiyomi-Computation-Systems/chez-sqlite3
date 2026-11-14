#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private s)
  (export s)
  (import (rnrs) (scheme))
  (define s 1))
