#!r6rs
;;; Fixture for tests/test-check-seam.sps: imports (chez-sqlite3 private extra), which rule (h) finds defined: only rule (i) names where it stands.
(library (chez-sqlite3 private x)
  (export x)
  (import (rnrs) (chez-sqlite3 private extra))
  (define x 1))
