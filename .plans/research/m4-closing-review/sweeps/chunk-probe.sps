;; chunk-probe.sps: under a collect trip of 256 bytes, how often a critical
;; section that allocates K bytes meets a collect request at its exit, of 100
;; tries each. Run inside scripts/guix-env: $CHEZ --program <this file>.
;; M4 closing review, builder D: 1000 bytes 6 of 100, 8000 49, 16000 50,
;; 32000 and more 100.
(import (chezscheme))
(define n 0)
(define old (collect-request-handler))
(define (try k)
  (collect)
  (collect-trip-bytes 256)
  (set! n 0)
  (collect-request-handler (lambda () (set! n (+ n 1)) (collect)))
  (let loop ((i 0) (hits 0))
    (if (= i 100)
        (begin (collect-trip-bytes (expt 2 27)) (collect-request-handler old) hits)
        (let ((before n))
          (critical-section (make-bytevector k))
          (loop (+ i 1) (if (> n before) (+ hits 1) hits))))))
(for-each (lambda (k) (printf "~s bytes: requests at the exit in ~s of 100\n" k (try k))) '(1000 8000 16000 32000 40000 70000))
