;;; number-twice: Chez's number->string inside an engine, its remainder
;;; resumed twice, at every fuel until the work completes unexpired (M3 slice
;;; 5, part A). It loads no SQLite.
;;;
;;; At each fuel, the engine runs until it expires; its remainder is then
;;; resumed to its end twice, and the two answers compared. The same is done
;;; for string-append alone, the control.
(import (chezscheme))

;; slice : Engine Natural -> (U (List 'completed Any) (List 'expired Engine))
(define (slice e fuel)
  (e fuel
     (lambda (left . vals) (list 'completed (car vals)))
     (lambda (more) (list 'expired more))))

;; finish : Engine -> Any
;; E resumed, a million ticks at a time, until it completes: its answer.
(define (finish e)
  (let ((r (slice e 1000000)))
    (if (eq? (car r) 'completed) (cadr r) (finish (cadr r)))))

;; sweep : String (-> Any) -> Void
;; WORK at every fuel from 1 until it completes unexpired: that fuel, and
;; every fuel whose remainder, resumed twice, answered differently.
(define (sweep label work)
  (let loop ((fuel 1) (odd '()))
    (let ((r (slice (make-engine work) fuel)))
      (if (eq? (car r) 'completed)
          (printf "~a: completed unexpired at fuel ~s; second resumes that differ: ~s~%"
                  label fuel (reverse odd))
          (let* ((first (finish (cadr r)))
                 (second (finish (cadr r))))
            (loop (+ fuel 1)
                  (if (equal? first second) odd (cons (list fuel first second) odd))))))))

(sweep "number->string"
       (lambda () (string-append "PRAGMA busy_timeout = " (number->string 1234))))
(sweep "string-append alone"
       (lambda () (string-append "PRAGMA busy_timeout = " "1234")))
