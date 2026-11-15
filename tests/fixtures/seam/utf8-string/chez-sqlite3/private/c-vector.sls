#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private c-vector)
  (export table)
  (import (rnrs))
  (define table '#((1 . utf8->string))))
