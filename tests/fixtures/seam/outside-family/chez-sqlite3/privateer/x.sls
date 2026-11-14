#!r6rs
;;; Fixture for tests/test-check-seam.sps: a legal library, so the file under test is the only fault.
(library (chez-sqlite3 privateer x)
  (export p)
  (import (rnrs))
  (define p 1))
