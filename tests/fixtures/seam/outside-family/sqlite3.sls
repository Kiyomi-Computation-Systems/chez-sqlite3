#!r6rs
;;; Fixture for tests/test-check-seam.sps: a legal library, so the file under test is the only fault.
(library (sqlite3)
  (export s)
  (import (rnrs))
  (define s 1))
