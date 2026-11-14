#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private u3)
  (export u3)
  (import (rnrs) (only ($system) eval))
  (define u3 1))
