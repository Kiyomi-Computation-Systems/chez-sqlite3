#!r6rs
;;; Fixture for tests/test-check-seam.sps: exports the rule passes. car comes from (rnrs). my-with is exported as with-mutex, a name (chezscheme) has whose binding here is the library own. getenv is defined here, and not imported.
(library (chez-sqlite3 private ok)
  (export car (rename (my-with with-mutex)) getenv)
  (import (chez-sqlite3 private require-threaded) (rnrs) (only (chezscheme) with-mutex))
  (define (my-with x) (with-mutex x)) (define getenv 1))
