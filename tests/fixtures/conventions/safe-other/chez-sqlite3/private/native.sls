#!r6rs
(library (chez-sqlite3 private native)
  (export errmsg)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define errmsg
    (load-step
     (bind-required report
       (foreign-procedure __collect_safe "sqlite3_errmsg" (uptr) uptr)))))
