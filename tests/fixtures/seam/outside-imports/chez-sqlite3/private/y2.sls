#!r6rs
;;; Fixture for tests/test-check-seam.sps: imports (chez-sqlite3 util2), which this tree defines: rule (h) is satisfied.
(library (chez-sqlite3 private y2)
  (export y2)
  (import (rnrs) (chez-sqlite3 util2))
  (define y2 1))
