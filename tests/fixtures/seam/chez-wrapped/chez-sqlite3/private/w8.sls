#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private w8)
  (export w8)
  (import (rnrs) (only (library (chezscheme)) threaded?))
  (define w8 1))
