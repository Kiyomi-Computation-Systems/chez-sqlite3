#!r6rs
(library (chez-sqlite3 private native)
  (export open)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define open
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_open_v2" (uptr uptr int uptr) int)))))
