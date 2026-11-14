#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private u1)
  (export u1)
  (import (rnrs) (srfi :1))
  (define u1 1))
