#!r6rs
;;; Fixture for tests/test-check-seam.sps: outside the family, and importing a private library: refused once, for being outside.
(library (util)
  (export u)
  (import (rnrs) (chez-sqlite3 private require-threaded))
  (define u 1))
