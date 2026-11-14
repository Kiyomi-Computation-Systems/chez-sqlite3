#!r6rs
;;; Fixture for tests/test-check-seam.sps: (chez-sqlite3 private extra) is defined nowhere in this tree.
(library (chez-sqlite3 private x)
  (export x)
  (import (rnrs) (chez-sqlite3 private y) (prefix (chez-sqlite3 private extra) e:))
  (define x 1))
