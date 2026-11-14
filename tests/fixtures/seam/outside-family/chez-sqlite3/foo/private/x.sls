#!r6rs
;;; Fixture for tests/test-check-seam.sps: a legal library, so the file under test is the only fault.
(library (chez-sqlite3 foo private x)
  (export f)
  (import (rnrs))
  (define f 1))
