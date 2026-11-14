#!r6rs
;;; Fixture for tests/test-check-seam.sps: imports the test helpers: the import allowlist, rule (e).
(library (chez-sqlite3 private y3)
  (export y3)
  (import (rnrs) (chez-sqlite3-testing))
  (define y3 1))
