#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private utf8)
  (export decode)
  (import (only (rnrs bytevectors) utf8->string))
  (define (decode b) (utf8->string b)))
