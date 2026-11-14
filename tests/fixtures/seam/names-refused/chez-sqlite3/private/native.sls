#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private native)
  (export native)
  (import (rnrs) (only (chezscheme) define-ftype lock-object foreign-callable foreign-callable-entry-point fork-thread condition-wait mutex-acquire))
  (define native 1))
