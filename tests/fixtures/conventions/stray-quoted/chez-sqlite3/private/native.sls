#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded. The symbol in a
;;; quoted list, which a macro could be handed.
(library (chez-sqlite3 private native)
  (export keywords)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define keywords '(foreign-entry? foreign-procedure foreign-ref)))
