;; M3 slice 3, part B's probe: whether an engine spends ticks inside a
;; critical section. Each part counts the expiries of an engine of fuel 1:
;; a loop of 1000 iterations, plain and inside one section; and 100 calls of
;; a ten-iteration loop, plain and inside one section. Pure Chez: it loads
;; no libsqlite3. Run from the repository's root:
;;   $CHEZ --program .plans/research/m3-slice-3/section-ticks.sps
(import (rnrs) (only (chezscheme) make-engine critical-section))
(define (expiries thunk)
  (let loop ((e (make-engine thunk)) (n 0))
    (let ((next (e 1 (lambda (left . vals) (list 'completed (car vals))) (lambda (more) more))))
      (cond ((pair? next) (list (cadr next) n)) (else (loop next (+ n 1)))))))
(define (work n) (let loop ((i 0) (acc 0)) (if (= i n) acc (loop (+ i 1) (+ acc i)))))
(define (calls n) (let loop ((i 0)) (when (< i n) (work 10) (loop (+ i 1)))))
(write (list 'plain (cadr (expiries (lambda () (work 1000))))
             'section (cadr (expiries (lambda () (critical-section (work 1000)))))
             'calls-plain (cadr (expiries (lambda () (calls 100))))
             'calls-section (cadr (expiries (lambda () (critical-section (calls 100)))))))
(newline)
