#!r6rs
;; M3 slice 6, probe P5, direct: sqlite3_interrupt on a connection that
;; sqlite3_close has freed, to see whether Valgrind reports it. Undefined
;; behaviour: it writes into freed memory, so run it only under Valgrind,
;; as the README shows, and never as part of a suite.
(import (rnrs) (rnrs eval))
(define (reach lib name) (eval name (environment lib)))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define sqlite3-interrupt (reach '(chez-sqlite3 private native) 'sqlite3-interrupt))
(define db (open-database ":memory:"))
(define h (call-with-open-handle 'p5 db (lambda (h) h)))
(close-database! db)
(sqlite3-interrupt h)
(display "interrupted a freed connection") (newline)
