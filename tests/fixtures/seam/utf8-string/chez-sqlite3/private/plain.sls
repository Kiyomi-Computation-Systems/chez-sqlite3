#!r6rs
;;; Fixture for tests/test-check-seam.sps
;;; Near names, a string and a comment, none of them a reference: utf8->string
(library (chez-sqlite3 private plain)
  (export strict-utf8->string)
  (import (rnrs))
  (define (strict-utf8->string b) (list "utf8->string" 'utf8->string! 'string->utf8 b)))
