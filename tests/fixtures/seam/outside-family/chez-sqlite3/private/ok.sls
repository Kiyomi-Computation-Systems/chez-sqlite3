#!r6rs
;;; Fixture for tests/test-check-seam.sps: a legal library, so the file under test is the only fault.
(library (chez-sqlite3 private ok)
  (export ok)
  (import (rnrs))
  (define ok 1))
