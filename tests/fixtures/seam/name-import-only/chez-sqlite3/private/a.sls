(library (chez-sqlite3 private a) (export run) (import (rnrs) (only (chezscheme) import-only))
  (define (run) (let () (import-only (chez-sqlite3 private target)) (hello))))
