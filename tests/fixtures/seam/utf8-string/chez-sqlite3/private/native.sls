#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private native)
  (export decode)
  (import (rnrs))
  (define (decode b) (utf8->string b)))
