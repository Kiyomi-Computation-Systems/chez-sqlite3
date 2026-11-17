;;; number-interleaved: Chez's number->string inside an engine, one remainder
;;; R resumed while an earlier resume of it is pending (M3 slice 5, part C).
;;; It loads no SQLite.
;;;
;;; At each fuel F until the work completes unexpired, R is taken at F; R is
;;; resumed at each fuel G until that resume completes, R1 taken where it
;;; expires; then R is resumed to its end, then R1. Prints each distinct pair
;;; of answers that differs from the whole string, with the first (F G) that
;;; gave it.
(import (chezscheme))

(define (slice e fuel)
  (e fuel (lambda (left . vals) (list 'completed (car vals))) (lambda (more) (list 'expired more))))

(define (finish e)
  (let ((r (slice e 1000000)))
    (if (eq? (car r) 'completed) (cadr r) (finish (cadr r)))))

(define (work) (string-append "PRAGMA busy_timeout = " (number->string 1234)))
(define whole (work))

(let floop ((f 1) (seen '()))
  (let ((r (slice (make-engine work) f)))
    (if (eq? (car r) 'completed)
        (begin
          (printf "completed unexpired at fuel ~s; answers other than the whole string:~%" f)
          (for-each (lambda (s) (printf "  ~s~%" s)) (reverse seen)))
        (let gloop ((g 1) (seen seen))
          (let ((r1 (slice (cadr r) g)))
            (if (eq? (car r1) 'completed)
                (floop (+ f 1) seen)
                (let* ((second (finish (cadr r)))
                       (third (finish (cadr r1)))
                       (pair (list second third)))
                  (gloop (+ g 1)
                         (if (or (and (equal? second whole) (equal? third whole))
                                 (assoc pair (map (lambda (s) (cons (cadr s) s)) seen)))
                             seen
                             (cons (list (list f g) pair) seen))))))))))
