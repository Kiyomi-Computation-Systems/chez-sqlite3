#!r6rs
(import (rnrs) (rnrs eval) (only (chezscheme) disable-interrupts enable-interrupts printf))
(define env (environment '(chez-sqlite3)))
(define open-database (eval 'open-database env))
(define close-database! (eval 'close-database! env))
(define execute! (eval 'execute! env))
(define with-transaction (eval 'with-transaction env))
(define sqlite-error-code (eval 'sqlite-error-code env))
(define (depth) (let ((d (disable-interrupts))) (enable-interrupts) d))
(let ((db (open-database ":memory:" '((foreign-keys . #t)))))
  (execute! db "create table p (id integer primary key)")
  (execute! db "create table c (p integer references p (id) deferrable initially deferred)")
  (let ((seen
         (call/cc
          (lambda (k)
            (with-exception-handler
             (lambda (e) (k (list 'handler-depth (depth) 'code (sqlite-error-code e))))
             (lambda ()
               (with-transaction db (lambda () (execute! db "insert into c values (1)")))
               'no-raise))))))
    (printf "outside: depth ~a; ~s\n" (depth) seen))
  (close-database! db))
