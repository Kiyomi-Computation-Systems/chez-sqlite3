#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private h)
  (export h critical-section)
  (import (chez-sqlite3) (rnrs) (only (chezscheme) critical-section))
  (define h 1))
