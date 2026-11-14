#!r6rs
;;; Fixture for tests/test-check-seam.sps
(library (chez-sqlite3 private native)
  (export bind)
  (import (chez-sqlite3 private require-threaded) (rnrs) (only (chezscheme) load-shared-object foreign-procedure foreign-entry foreign-entry? foreign-ref foreign-set! getenv machine-type make-mutex with-mutex))
  (define bind 1))
