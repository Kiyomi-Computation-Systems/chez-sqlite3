;; timer-probe.sps: exit-probe.sps's sections at a trip of 256 bytes, the engine's
;; timer read through $tc-field at the end of each collect request's handler.
;; Each fuel prints whether its remainder lay at a section's exit (EXIT) or later,
;; and the timer's readings, newest last: every EXIT fuel's last reading is #f,
;; the ticks spent in the handler, and every later fuel's a number. So a handler
;; that reads #f knows the engine expires at that section's exit. Run: scheme
;; --script timer-probe.sps. M4's closing review, builder D.
(import (chezscheme))
(define tc-field (eval (list (string->symbol "$primitive") (string->symbol "$tc-field")) (scheme-environment)))
(define tc (eval (list (string->symbol "$primitive") (string->symbol "$tc")) (scheme-environment)))
(define (ticks) (tc-field (quote timer-ticks) (tc)))
(define sink #f)
(define where 0)
(define seen-ticks '())
(define old (collect-request-handler))
(define (handler) (old) (set! seen-ticks (cons (ticks) seen-ticks)))
(define (f x) (+ x 1))
(define (work)
  (let loop ((i 0) (acc 0))
    (if (= i 6) acc
        (begin
          (critical-section (set! where (+ (* 2 i) 1)) (set! sink (make-bytevector 32768)))
          (set! where (+ (* 2 i) 2))
          (loop (+ i 1) (f (f (f acc))))))))
(define (slice e fuel) (e fuel (lambda (left . v) 'done) (lambda (k) k)))
(let loop ((fuel 1) (seen '()))
  (collect) (collect-trip-bytes 256) (collect-request-handler handler) (set! where 0) (set! seen-ticks '())
  (let* ((r (slice (make-engine work) fuel)) (w where) (t seen-ticks))
    (collect-trip-bytes (expt 2 27)) (collect-request-handler old)
    (if (eq? r 'done)
        (printf "done at ~s\n~s\n" fuel (reverse seen))
        (loop (+ fuel 1) (cons (list fuel (if (odd? w) 'EXIT 'later) (reverse t)) seen)))))
