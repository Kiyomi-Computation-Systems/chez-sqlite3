#!r6rs
;;; Read as data by tests/test-conventions.sps, never loaded.
;;; sqlite3_load_extension bound plain, through bind-optional: the form is
;;; read as one bind-required wraps is, and held to its row.
(library (chez-sqlite3 private native)
  (export load-extension)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define load-extension
    (load-step
     (bind-optional
       (foreign-procedure "sqlite3_load_extension" (uptr uptr uptr uptr) int)))))
