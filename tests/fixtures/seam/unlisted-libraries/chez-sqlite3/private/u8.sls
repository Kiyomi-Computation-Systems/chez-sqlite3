#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private u8)
  (export u8)
  (import (rnrs) (sqlite3))
  (define u8 1))
