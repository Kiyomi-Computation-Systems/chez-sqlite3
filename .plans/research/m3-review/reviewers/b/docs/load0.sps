#!r6rs
(import (rnrs) (rnrs eval) (chez-sqlite3))
(display "started\n")
(write (guard (e ((sqlite-library-unavailable? e) (list 'no-sqlite (sqlite-library-unavailable-reason e))))
  (eval '(sqlite-version) (environment '(chez-sqlite3)))))
(newline)
