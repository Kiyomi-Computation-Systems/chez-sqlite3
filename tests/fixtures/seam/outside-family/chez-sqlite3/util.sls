#!r6rs
;;; Fixture for tests/test-check-seam.sps: a legal library, so the file under test is the only fault.
(library (chez-sqlite3 util)
  (export u2)
  (import (rnrs))
  (define u2 1))
