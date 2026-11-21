(import (chezscheme) (chez-sqlite3))

;; A single-shot round-robin scheduler: each remainder is resumed exactly
;; once, first slice FIRST ticks, every later slice NEXT ticks. The work runs
;; plain statement verbs only: prepare, step, column read, finalize.
(define (run-engine thunk first next)
  (let loop ((eng (make-engine thunk)) (fuel first) (slices 0))
    (if (> slices 100000)
        '(too-many-slices)
        (eng fuel
             (lambda (left . vals) (cons 'done vals))
             (lambda (rest) (loop rest next (+ slices 1)))))))

(define (describe c)
  (cond ((and (assertion-violation? c) (irritants-condition? c))
         (list 'assertion (and (who-condition? c) (condition-who c))
               (condition-irritants c)))
        ((sqlite-closed? c) 'closed)
        ((condition? c) (list 'condition (and (message-condition? c) (condition-message c))))
        (else (list 'raised c))))

(define (work db)
  (lambda ()
    (guard (c (#t (list 'raised (describe c))))
      (let loop ((i 0) (acc 0))
        (if (= i 20)
            acc
            (let ((st (prepare-statement db "select 1")))
              (step! st)
              (let ((v (column-value st 0)))
                (finalize-statement! st)
                (loop (+ i 1) (+ acc v)))))))))

(define counts '())
(define (note! k)
  (let ((p (assoc k counts)))
    (if p (set-cdr! p (+ (cdr p) 1)) (set! counts (cons (cons k 1) counts)))))

(for-each
 (lambda (next)
   (do ((first 1 (+ first 1))) ((> first 400))
     (let ((db (open-database ":memory:")))
       (let ((r (run-engine (work db) first next)))
         (note! (list 'next next r)))
       (close-database! db))))
 '(1 2 3 4 5 8 13 50))

(for-each (lambda (p) (write p) (newline)) (reverse counts))
