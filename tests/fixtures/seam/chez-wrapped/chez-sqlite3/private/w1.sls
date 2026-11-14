#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private w1)
  (export w1)
  (import (rnrs) (except (chezscheme) car))
  (define w1 1))
