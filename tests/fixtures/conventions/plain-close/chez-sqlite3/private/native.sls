#!r6rs
(library (chez-sqlite3 private native)
  (export close)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define close
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_close" (uptr) int)))))
