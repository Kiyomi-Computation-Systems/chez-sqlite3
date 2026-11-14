#!r6rs
;;; Fixture for tests/test-check-seam.sps: the listed library re-exports foreign-alloc, so a library that may not import it gets it from here.
(library (chez-sqlite3 private memory)
  (export allocate foreign-alloc)
  (import (chez-sqlite3 private require-threaded) (rnrs) (only (chezscheme) foreign-alloc))
  (define allocate 1))
