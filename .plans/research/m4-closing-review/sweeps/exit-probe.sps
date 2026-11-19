;; exit-probe.sps: where an engine's remainder lies when a collect request falls due
;; inside a critical section. Six sections, each allocating 32 KiB, a marker set
;; inside each (odd) and overwritten just after it (even); at every fuel the
;; marker read at the expiry. Run: scheme --script exit-probe.sps. Guix's Chez
;; 10.4.0: at a trip of 256 bytes three fuels a section expire at its exit (odd);
;; at 2^27 and at 256 KiB, none. M4's closing review, builder D.
(import (chezscheme))
;; where, by a marker the work writes after each section, the remainder lies:
;; right after a section (marker = section's number, odd) or later (even)
(define sink #f)
(define where 0)
(define old (collect-request-handler))
(define (f x) (+ x 1))
(define (work)
  (let loop ((i 0) (acc 0))
    (if (= i 6) acc
        (begin
          (critical-section (set! where (+ (* 2 i) 1)) (set! sink (make-bytevector 32768)))
          (set! where (+ (* 2 i) 2))
          (loop (+ i 1) (f (f (f acc))))))))
(define (slice e fuel) (e fuel (lambda (left . v) 'done) (lambda (k) k)))
(define (run trip)
  (let loop ((fuel 1) (seen '()))
    (collect) (collect-trip-bytes trip)
    (set! where 0)
    (let* ((r (slice (make-engine work) fuel)) (w where))
      (collect-trip-bytes (expt 2 27))
      (if (eq? r 'done)
          (printf "trip ~s: done at ~s; at-exit (odd marker) at fuels ~s\n" trip fuel (reverse seen))
          (loop (+ fuel 1) (if (odd? w) (cons fuel seen) seen))))))
(run 256) (run (expt 2 27)) (run 262144)
