;;; section-end: where Chez handles an interrupt that came pending inside a
;;; critical section (M3 slice 5, part C): a keyboard interrupt raised by
;;; SIGINT from C inside the section; a timer whose ticks would run out
;;; inside it; an engine whose fuel would. It loads no SQLite, and loads
;;; glibc's libc.so.6 by name for raise(3), so it runs on Linux.
(import (chezscheme))
(load-shared-object "libc.so.6")
(define c-raise (foreign-procedure "raise" (int) int))
(define (spin n) (let loop ((i 0)) (when (< i n) (loop (+ i 1)))))
;; a keyboard interrupt, raised by SIGINT from C inside the section
(define kb #f)
(keyboard-interrupt-handler (lambda () (set! kb #t)))
(define kb-seen
  (let ((x 'unset))
    (critical-section (c-raise 2))
    (set! x kb)
    x))
(printf "keyboard: handled before the next expression ~s; by now ~s~%" kb-seen kb)
;; a timer whose ticks run out inside the section, if ticks are spent there
(define tm #f)
(timer-interrupt-handler (lambda () (set! tm #t)))
(define tm-seen
  (let ((x 'unset))
    (set-timer 10)
    (critical-section (spin 1000))
    (set! x tm)
    x))
(printf "timer: handled before the next expression ~s; by now ~s; ticks left ~s~%" tm-seen tm (set-timer 0))
;; an engine whose fuel runs out inside the section: where does it expire?
(define where
  ((make-engine (lambda () (let ((a 'before)) (critical-section (spin 1000)) (set! a 'after-section) (spin 5) 'done)))
   10 (lambda (left v) (list 'completed v left)) (lambda (more) 'expired)))
(printf "engine of fuel 10 around a section of 1000 calls: ~s~%" where)
