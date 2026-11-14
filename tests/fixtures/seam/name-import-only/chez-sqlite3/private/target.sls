(library (chez-sqlite3 private target) (export hello) (import (rnrs))
  (define (hello) (quote reached-target)))
