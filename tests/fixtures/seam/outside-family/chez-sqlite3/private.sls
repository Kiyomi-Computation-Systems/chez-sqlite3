#!r6rs
;;; Fixture for tests/test-check-seam.sps: a legal library, so the file under test is the only fault.
(library (chez-sqlite3 private)
  (export b)
  (import (rnrs))
  (define b 1))
