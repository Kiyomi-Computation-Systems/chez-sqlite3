(library (chez-sqlite3 private d) (export run) (import (rnrs) (only (chezscheme) $primitive))
  (define (run) (($primitive eval) (quote (let () (import (chez-sqlite3 private target)) (hello))))))
