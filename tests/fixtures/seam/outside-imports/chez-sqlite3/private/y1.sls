#!r6rs
;;; Fixture for tests/test-check-seam.sps: imports (chez-sqlite3 util), defined nowhere: rule (h).
(library (chez-sqlite3 private y1)
  (export y1)
  (import (rnrs) (chez-sqlite3 util))
  (define y1 1))
