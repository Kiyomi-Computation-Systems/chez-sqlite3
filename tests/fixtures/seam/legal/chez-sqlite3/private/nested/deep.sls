#!r6rs
;;; Fixture for tests/test-check-seam.sps: a private library below another directory, importing a sibling.
(library (chez-sqlite3 private nested deep)
  (export deep)
  (import (chez-sqlite3 private thing) (rnrs))
  (define deep thing))
