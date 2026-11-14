(library (chez-sqlite3 private b) (export run) (import (rnrs) (only (chezscheme) top-level-value))
  (define (run) ((top-level-value (quote eval)) (quote (let () (import (chez-sqlite3 private target)) (hello))))))
