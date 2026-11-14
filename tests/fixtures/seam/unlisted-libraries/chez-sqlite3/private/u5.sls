#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private u5)
  (export u5)
  (import (rnrs) (chez-sqlite3-testing))
  (define u5 1))
