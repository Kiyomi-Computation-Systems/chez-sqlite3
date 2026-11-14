#!r6rs
;;; Fixture for tests/test-check-seam.sps: two names imported from (chezscheme) exported, one plain and one renamed. r, its own definition, is not named.
(library (chez-sqlite3 private r)
  (export r with-mutex (rename (make-mutex mk)))
  (import (chez-sqlite3 private require-threaded) (rnrs) (only (chezscheme) with-mutex make-mutex))
  (define r 1))
