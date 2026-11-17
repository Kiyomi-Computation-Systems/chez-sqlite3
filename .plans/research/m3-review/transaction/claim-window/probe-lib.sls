#!r6rs
(library (probe-lib)
  (export wt marks clear-marks!)
  (import (rnrs) (only (chezscheme) critical-section))
  (define m '())
  (define (marks) m)
  (define (clear-marks!) (set! m '()))
  (define (made-claim) (let ((taken #f)) (lambda () (if taken #f (begin (set! taken #t) #t)))))
  (define wt
    (case-lambda
      ((db body) (transaction 'w db 'immediate body))
      ((db mode body) (transaction 'w db mode body))))
  (define (transaction who db mode body)
    (let ((claim (made-claim)))
      (set! m (cons 'claimed m))
      (unless (procedure? body) (assertion-violation who "no" body))
      (body))))
