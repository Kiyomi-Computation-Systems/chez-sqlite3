#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private two-a)
  (export a)
  (import (rnrs))
  (define a 1))
(library (chez-sqlite3 private two-b) (export b) (import (rnrs) (chezscheme)) (define b 1))
