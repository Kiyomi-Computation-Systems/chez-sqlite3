#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private w9)
  (export w9)
  (import (rnrs) (only (scheme) threaded?))
  (define w9 1))
