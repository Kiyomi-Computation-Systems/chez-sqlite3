#!r6rs
;; Probe: an engine around with-transaction, expiring first at fuel F; its
;; remainder R resumed to its end (R1), then R resumed again to its end (R2).
;; Does R2 commit the body a second time, answering 42?
(import (chezscheme) (chez-sqlite3))

(define (run-engine e fuel)
  (e fuel (lambda (ticks . vals) (cons 'completed vals)) (lambda (r) (list 'expired r))))
(define (describe e)
  (cond ((sqlite-transaction-ended? e) 'transaction-ended)
        ((sqlite-closed? e) 'closed)
        ((sqlite-error? e) (list 'sqlite-error (sqlite-error-code e)))
        ((and (condition? e) (message-condition? e)) (list 'other (condition-message e)))
        (else (list 'other e))))
(define (guarded thunk) (lambda () (guard (e (#t (list 'raised (describe e)))) (thunk))))

;; F0: the fuel at which a call refused at its first check completes.
(define f0
  (let loop ((f 1))
    (let ((db (open-database ":memory:")))
      (let ((r (run-engine (make-engine (guarded (lambda () (with-transaction db 'deferred 42)))) f)))
        (close-database! db)
        (if (eq? (car r) 'completed) f (loop (+ f 1)))))))
(printf "a call refused at its first check completes at fuel ~a\n" f0)

(define (trial f)
  (let ((db (open-database ":memory:")))
    (execute! db "create table t(x)")
    (let* ((body (lambda () (execute! db "insert into t values (?)" f) 42))
           (e (make-engine (guarded (lambda () (with-transaction db 'deferred body)))))
           (first (run-engine e f)))
      (if (eq? (car first) 'completed)
          (begin (close-database! db) 'completed-unexpired)
          (let* ((r (cadr first))
                 (r1 (run-engine r 100000000))
                 (r2 (run-engine r 100000000))
                 (rows (length (query db "select x from t")))
                 (open? (in-transaction? db)))
            (close-database! db)
            (list f (cdr r1) (cdr r2) 'rows rows 'open open?))))))

(let loop ((f 1) (doubles 0))
  (let ((r (trial f)))
    (cond ((eq? r 'completed-unexpired)
           (printf "completed unexpired at fuel ~a; fuels whose second resume committed again: ~a\n" f doubles))
          (else
           (let ((double? (= (list-ref r 4) 2)))
             (when (or double? (<= f 3)) (write r) (newline))
             (loop (+ f 1) (if double? (+ doubles 1) doubles)))))))
