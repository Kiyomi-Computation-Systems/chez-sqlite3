#!r6rs
(import (rnrs) (chez-sqlite3))
(define (describe c)
  (cond ((sqlite-transaction-ended? c) 'ended)
        ((sqlite-closed? c) 'closed)
        ((sqlite-error? c) (list 'sqlite (sqlite-error-extended-code c) (sqlite-error-message c)))
        ((assertion-violation? c) (cons 'assert (if (irritants-condition? c) (condition-irritants c) '())))
        ((symbol? c) c)
        (else (list 'other c))))
(define-syntax try
  (syntax-rules ()
    ((_ body ...) (guard (c (#t (list 'raised (describe c)))) (list 'ok (begin body ...))))))
(define (show label v) (write label) (display " => ") (write v) (newline))
(define (fresh path) (when (file-exists? path) (delete-file path)) path)

;; D4 again: nested level (chez_sqlite3_1) raised beside its own held insert ... returning
(define (d4 name)
  (call-with-database name
    (lambda (db)
      (execute! db "create table w (x)")
      (let* ((st #f) (inner #f) (in-inner #f) (next #f) (fin #f) (release #f)
             (outer (try (with-transaction db
                           (lambda ()
                             (execute! db "insert into w values (0)")
                             (set! inner (try (with-transaction db
                                                (lambda ()
                                                  (set! st (prepare-statement db "insert into w values (1), (2), (3) returning x"))
                                                  (step! st)
                                                  (raise 'boom)))))
                             (set! next (try (and (step! st) (column-value st 0))))
                             (set! fin (try (finalize-statement! st)))
                             (set! release (try (execute! db "release chez_sqlite3_1")))
                             (query db "select x from w order by x")))))
             (rows (query db "select x from w order by x")))
        (list 'inner inner 'next-step next 'finalize fin 'release-chez_sqlite3_1-after release
              'outer outer 'in (in-transaction? db) 'rows rows)))))
(show 'D4-memory (d4 ":memory:"))
(show 'D4-file (d4 (fresh "build/m3cr-b/docs/p-d4.db")))

;; D4c: the commit path: the nested body RETURNS beside its held insert ... returning
(define (d4c name)
  (call-with-database name
    (lambda (db)
      (execute! db "create table w (x)")
      (let* ((st #f) (inner #f) (fin #f) (release #f) (in-after #f)
             (outer (try (with-transaction db
                           (lambda ()
                             (execute! db "insert into w values (0)")
                             (set! inner (try (with-transaction db
                                                (lambda ()
                                                  (set! st (prepare-statement db "insert into w values (1), (2), (3) returning x"))
                                                  (step! st)
                                                  'inner-returned))))
                             (set! fin (try (finalize-statement! st)))
                             (set! release (try (execute! db "release chez_sqlite3_1")))
                             (query db "select x from w order by x")))))
             (rows (query db "select x from w order by x")))
        (list 'inner inner 'finalize fin 'release-chez_sqlite3_1-after release
              'outer outer 'in (in-transaction? db) 'rows rows)))))
(show 'D4c-memory (d4c ":memory:"))
(show 'D4c-file (d4c (fresh "build/m3cr-b/docs/p-d4c.db")))

;; D3c: outer level commit beside a held insert ... returning
(show 'D3c-outer-commit-beside-held-write
  (call-with-database ":memory:"
    (lambda (db)
      (execute! db "create table w (x)")
      (let* ((st #f)
             (r (try (with-transaction db
                       (lambda ()
                         (set! st (prepare-statement db "insert into w values (1), (2) returning x"))
                         (step! st)
                         'returned))))
             (in (in-transaction? db))
             (fin (try (finalize-statement! st)))
             (n (query-row db "select count(*) from w")))
        (list r 'in in 'finalize fin 'count n)))))
