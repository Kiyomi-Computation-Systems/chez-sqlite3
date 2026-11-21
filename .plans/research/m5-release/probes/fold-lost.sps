(import (chezscheme) (chez-sqlite3))

(define file "build/m5fixrev/cws-lost.db")
(when (file-exists? file) (delete-file file))

(define (describe c)
  (cond ((sqlite-busy? c) (list 'busy (sqlite-error-extended-code c)))
        ((sqlite-closed? c) 'closed)
        ((sqlite-error? c) (list 'sqlite (sqlite-error-code c)))
        ((and (assertion-violation? c) (irritants-condition? c))
         (list 'assertion (and (message-condition? c) (condition-message c)) (condition-irritants c)))
        ((condition? c) (list 'condition (and (message-condition? c) (condition-message c))))
        (else (list 'raised c))))

(define (spin n) (let loop ((i 0)) (when (< i n) (loop (+ i 1)))))

;; ENTER: a thunk run in an engine of 50 ticks a slice, each remainder
;; resumed once. Its answer, or what escaped the engine's caller.
(define first 50)
(define (under-engine thunk)
  (guard (c (#t (list 'caller-got (describe c))))
    (let loop ((eng (make-engine thunk)) (slices 0))
      (eng (if (= slices 0) first 50)
           (lambda (left . vals) (list 'done slices vals))
           (lambda (rest) (loop rest (+ slices 1)))))))

(define (trial label body)
  (when (file-exists? file) (delete-file file))
  (call-with-database file
    (lambda (setup) (execute! setup "create table t (x)")))
  (let* ((writer (open-database file))
         (reader (open-database file)))
    (execute! reader "insert into t values (0)")
    (let ((held (prepare-statement reader "select x from t")))
      (step! held)            ; the reader holds a shared lock
      (let ((r (under-engine (lambda () (body writer)))))
        (write (list label r)) (newline)
        (finalize-statement! held)
        (write (list label 'rows-after (query reader "select x from t order by x")
                     'writer-tracks (guard (c (#t (describe c))) (begin (close-database! writer) 'closed-ok))))
        (newline)
        (close-database! reader)))))

;; call-with-statement: an insert ... returning stepped once, then the
;; procedure spins until the engine expires inside it.
(trial 'call-with-statement
  (lambda (db)
    (guard (c (#t (list 'body-got (describe c))))
      (call-with-statement db "insert into t values (1), (2) returning x"
        (lambda (st) (step! st) (spin 100000) 'proc-returned)))))

;; The reference's advice: prepare-statement, finalize it yourself.
(trial 'prepare-statement
  (lambda (db)
    (guard (c (#t (list 'body-got (describe c))))
      (let ((st (prepare-statement db "insert into t values (1), (2) returning x")))
        (step! st)
        (spin 100000)
        (finalize-statement! st)
        'finalized))))

;; query-fold, for comparison, as its entry documents the lost engine.
(trial 'query-fold
  (lambda (db)
    (guard (c (#t (list 'body-got (describe c))))
      (query-fold db "insert into t values (1), (2) returning x"
                  (lambda (acc row) (spin 100000) (+ acc 1)) 0))))

(for-each
 (lambda (f)
   (set! first f)
   (trial (list 'query-fold-first f)
     (lambda (db)
       (guard (c (#t (list 'body-got (describe c))))
         (query-fold db "insert into t values (1), (2) returning x"
                     (lambda (acc row) (spin 100000) (+ acc 1)) 0))))
   (trial (list 'call-with-statement-first f)
     (lambda (db)
       (guard (c (#t (list 'body-got (describe c))))
         (call-with-statement db "insert into t values (1), (2) returning x"
           (lambda (st) (step! st) (spin 100000) 'proc-returned))))))
 '(100 200 400 800 1600 3200 20000))
