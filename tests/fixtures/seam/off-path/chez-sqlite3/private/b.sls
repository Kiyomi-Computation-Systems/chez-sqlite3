#!r6rs
;;; Fixture for tests/test-check-seam.sps: the one library in a file named for another.
(library (chez-sqlite3 private c)
  (export c)
  (import (rnrs))
  (define c 1))
