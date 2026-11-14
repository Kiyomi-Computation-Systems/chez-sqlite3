#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private w6)
  (export w6)
  (import (rnrs) (for (only (chezscheme) threaded?) expand))
  (define w6 1))
