#!r6rs
;; Probe: what a critical section does to sleep, with-mutex and collect
;; requests, on this Chez. Effects ordered by let*.
(import (chezscheme))
(define (ms n) (make-time 'time-duration (* n 1000000) 0))
(define (now) (real-time))
(define (spin-alloc n) (let loop ((i 0) (acc '())) (if (< i n) (loop (+ i 1) (cons (make-vector 8 i) (if (> (length* acc) 1000) '() acc))) 'done)))
(define (length* l) (if (pair? l) (+ 1 (length* (cdr l))) 0))
;; 1. a collect request inside a section waits for its end
(let* ((c0 (collections))
       (inside (critical-section
                (let* ((a (bytes-allocated)))
                  (let loop ((i 0)) (when (< i 200000) (make-vector 64 i) (loop (+ i 1))))
                  (list (- (bytes-allocated) a) (collections)))))
       (c1 (collections)))
  (printf "1. collections before ~a, at the section's end ~a (after allocating ~a bytes, trip ~a), just after ~a\n"
          c0 (cadr inside) (car inside) (collect-trip-bytes) c1))
;; 2. sleep inside a section blocks for its time
(let* ((t0 (now)) (r (critical-section (sleep (ms 200)) 'slept)) (t1 (now)))
  (printf "2. sleep 200 ms inside a section: ~a after ~a ms\n" r (- t1 t0)))
;; 3. with-mutex inside a section waits for another thread's hold
(let* ((m (make-mutex)) (held (make-condition)) (hm (make-mutex)) (h #f)
       (t (fork-thread (lambda () (with-mutex m (with-mutex hm (set! h #t) (condition-broadcast held)) (sleep (ms 300)))))))
  (with-mutex hm (let w () (unless h (condition-wait held hm) (w))))
  (let* ((t0 (now)) (r (critical-section (with-mutex m 'acquired))) (t1 (now)))
    (printf "3. with-mutex inside a section, another thread holding it 300 ms: ~a after ~a ms\n" r (- t1 t0))))
;; 4. another thread's collection while this one sleeps inside a section
(let* ((m (make-mutex)) (cv (make-condition)) (in #f) (out #f)
       (t (fork-thread (lambda ()
                         (critical-section
                          (with-mutex m (set! in #t) (condition-broadcast cv))
                          (sleep (ms 500)))
                         (with-mutex m (set! out (now)) (condition-broadcast cv))))))
  (with-mutex m (let w () (unless in (condition-wait cv m) (w))))
  (let* ((t0 (now)) (c0 (collections)) (r (collect-rendezvous)) (t1 (now)))
    (with-mutex m (let w () (unless out (condition-wait cv m) (w))))
    (printf "4. (collect-rendezvous) on main while the other sleeps 500 ms inside a section: returned after ~a ms; the section ended ~a ms after the collect began\n"
            (- t1 t0) (- out t0))))
;; 5. another thread's collection while this one spins inside a section
(let* ((m (make-mutex)) (cv (make-condition)) (in #f) (out #f)
       (t (fork-thread (lambda ()
                         (critical-section
                          (with-mutex m (set! in #t) (condition-broadcast cv))
                          (let ((t0 (now))) (let loop () (when (< (- (now) t0) 500) (loop)))))
                         (with-mutex m (set! out (now)) (condition-broadcast cv))))))
  (with-mutex m (let w () (unless in (condition-wait cv m) (w))))
  (let* ((t0 (now)) (r (collect-rendezvous)) (t1 (now)))
    (with-mutex m (let w () (unless out (condition-wait cv m) (w))))
    (printf "5. (collect-rendezvous) on main while the other spins 500 ms inside a section: returned after ~a ms; the section ended ~a ms after the collect began\n"
            (- t1 t0) (- out t0))))
