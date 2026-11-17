#!r6rs
(import (rnrs) (chez-sqlite3))
(define (describe c)
  (cond ((sqlite-transaction-ended? c) 'ended)
        ((sqlite-setting-mismatch? c) (list 'mismatch (sqlite-setting-mismatch-actual c)))
        ((sqlite-error? c) (list 'sqlite (sqlite-error-extended-code c) (sqlite-error-message c)))
        ((assertion-violation? c) (cons 'assert (if (irritants-condition? c) (condition-irritants c) '())))
        (else (list 'other c))))
(define-syntax try
  (syntax-rules ()
    ((_ body ...) (guard (c (#t (list 'raised (describe c)))) (list 'ok (begin body ...))))))
(define (show label v) (write label) (display " => ") (write v) (newline))
(define (fresh path) (when (file-exists? path) (delete-file path)) path)

;; G1: "On a file already in WAL, (journal-mode . wal) runs at once beside anything"
(define p (fresh "build/m3cr-b/docs/p-wal.db"))
(let ((db (open-database p '((journal-mode . wal))))) (execute! db "create table t (x)") (close-database! db))
(let* ((a (open-database p)))
  (execute! a "pragma locking_mode = exclusive")
  (execute! a "insert into t values (1)")
  (show 'G1-wal-on-wal-beside-exclusive-locking-mode
        (try (let ((b (open-database p '((journal-mode . wal))))) (close-database! b) 'opened)))
  (show 'G1b-same-with-busy-timeout-250
        (try (let ((b (open-database p '((busy-timeout . 250) (journal-mode . wal))))) (close-database! b) 'opened)))
  (close-database! a))

;; G2: a handler that retries on sqlite-transaction-ended?, as the entry's
;; "Nothing was committed by that call" invites
(show 'G2-retry-on-ended
  (call-with-database ":memory:"
    (lambda (db)
      (execute! db "create table t (x unique)")
      (execute! db "create table log (msg)")
      (execute! db "insert into t values (1)")
      (let ((body (lambda ()
                    (guard (e ((sqlite-error? e) 'caught))
                      (execute! db "insert or rollback into t values (1)"))
                    (execute! db "insert into log values ('after the end')")
                    'returned)))
        (let* ((first (try (with-transaction db body)))
               (second (try (with-transaction db body))))
          (list first second (query db "select msg from log")))))))
