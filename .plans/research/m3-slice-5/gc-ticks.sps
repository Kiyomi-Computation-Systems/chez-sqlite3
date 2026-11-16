;;; gc-ticks: whether a collect request shifts an engine's ticks (M3 slice 5,
;;; part C). The fuel at which an engine of 300 allocating calls first
;;; completes, with no collection pending, with a collection every 4 KiB, and
;;; with collect-request handlers that loop, or do nothing. It loads no
;;; SQLite.
(import (chezscheme))
(define (work n) (let loop ((i 0) (acc '())) (if (= i n) (length acc) (loop (+ i 1) (cons (make-vector 64 i) acc)))))
(define (completing thunk)
  (let loop ((fuel 1))
    (if ((make-engine thunk) fuel (lambda (left . v) #t) (lambda (more) #f)) fuel (loop (+ fuel 1)))))
(define (f) (completing (lambda () (work 300))))
(collect-request-handler (lambda () (collect)))
(let ((a (begin (collect) (f))) (b (begin (collect-trip-bytes 4096) (f))) (c (begin (collect-trip-bytes (expt 2 26)) (f))))
  (printf "no gc pressure: ~s; a collection every 4 KiB: ~s; again none: ~s~%" a b c))
(define calls 0)
(collect-request-handler (lambda () (set! calls (+ calls 1)) (let loop ((i 0)) (when (< i 50) (loop (+ i 1)))) (collect)))
(collect-trip-bytes 4096)
(printf "a handler that loops 50 times first: ~s, handler runs ~s~%" (f) calls)
(collect-request-handler void)
(collect-trip-bytes 4096)
(printf "a handler that does nothing: ~s~%" (f))
(collect-request-handler (lambda () (collect)))
(collect-trip-bytes (expt 2 26))
(collect)
(printf "back, no pressure: ~s~%" (f))
(printf "default trip bytes was set; bytes allocated now ~s~%" (bytes-allocated))
