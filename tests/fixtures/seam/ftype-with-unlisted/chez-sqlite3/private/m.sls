#!r6rs
;;; Fixture for tests/test-check-seam.sps: rules (f) and (c) in one import set.
(library (chez-sqlite3 private m)
  (export m)
  (import (rnrs) (only (chezscheme) foreign-alloc eval $primitive))
  (define m 1))
