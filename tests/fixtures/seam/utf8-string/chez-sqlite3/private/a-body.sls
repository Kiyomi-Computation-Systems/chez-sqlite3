#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private a-body)
  (export decode)
  (import (rnrs))
  (define (decode b) (let loop ((x b)) (utf8->string x))))
