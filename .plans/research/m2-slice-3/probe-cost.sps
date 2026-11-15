;;; M2 slice 3's third probe: what a prepare costs, plainly and under the
;;; gate's Valgrind, to size the tail oracle. N times: "select 1;" and a
;;; one-byte tail prepared and finalized, then the tail alone. Prints the
;;; milliseconds for N pairs.
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare (foreign-procedure __collect_safe "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define finalize (foreign-procedure __collect_safe "sqlite3_finalize" (uptr) int))
(define db (let* ([cell (foreign-alloc 8)] [rc (open-v2 ":memory:" cell 6 0)] [h (foreign-ref 'uptr cell 0)]) (foreign-free cell) h))
(define (prep bv)
  (let* ([n (bytevector-length bv)] [p (foreign-alloc (+ n 1))]
         [fill (let loop ([i 0]) (when (< i n) (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bv i)) (loop (+ i 1))))]
         [nul (foreign-set! 'unsigned-8 p n 0)]
         [cell (foreign-alloc 8)] [tail (foreign-alloc 8)] [z (foreign-set! 'uptr cell 0 0)]
         [rc (prepare db p (+ n 1) 0 cell tail)] [st (foreign-ref 'uptr cell 0)])
    (unless (= st 0) (finalize st))
    (foreign-free cell) (foreign-free tail) (foreign-free p) rc))
(define (bytevector-append a b) (let* ([n (bytevector-length a)] [m (bytevector-length b)] [r (make-bytevector (+ n m))]) (bytevector-copy! a 0 r 0 n) (bytevector-copy! b 0 r n m) r))
(define (ms) (let ([t (current-time 'time-monotonic)]) (+ (* 1000 (time-second t)) (quotient (time-nanosecond t) 1000000))))
(define n (string->number (or (getenv "N") "1000")))
(let* ([t0 (ms)])
  (let loop ([i 0])
    (when (< i n)
      (let* ([b (mod i 256)]
             [a (prep (bytevector-append (string->utf8 "select 1;") (bytevector b)))]
             [c (prep (bytevector b))])
        (loop (+ i 1)))))
  (printf "~a pairs of prepares: ~a ms~n" n (- (ms) t0)))
(close db)
