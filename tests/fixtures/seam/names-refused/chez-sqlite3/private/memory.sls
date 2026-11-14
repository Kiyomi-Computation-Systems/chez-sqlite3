#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private memory)
  (export memory)
  (import (rnrs) (only (chezscheme) define-ftype lock-object foreign-callable foreign-callable-entry-point fork-thread condition-wait mutex-acquire))
  (define memory 1))
