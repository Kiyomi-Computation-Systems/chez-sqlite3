#!r6rs
;; Probe: test-conveniences-engines' "one value a section" row judges binds
;; by "50 parameters expire at least 49 times more than 1, at fuel 1". The
;; statement tier's bind-all! binds every value in ONE critical section
;; (statement-values.sls, bind-all!/who). If bind-all! of 50 values also
;; expires at least 49 times more than of 1 value, the row's criterion is
;; met by a binder that binds in one section: the per-value work outside
;; any section (plans-of) makes the expiries, not the per-value sections.
(import (rnrs)
        (only (chezscheme) make-engine)
        (only (chez-sqlite3) open-database close-database!)
        (only (chez-sqlite3 private statement) prepare-statement finalize-statement!)
        (only (chez-sqlite3 private statement-values) bind-all!))

(define (expiries thunk)
  (let loop ((e (make-engine thunk)) (n 0))
    (let ((next (e 1 (lambda (left . vals) (list 'completed (car vals))) (lambda (more) more))))
      (cond ((pair? next) (list (cadr next) n))
            ((>= n 1000000) (list 'never-completed n))
            (else (loop next (+ n 1)))))))

(define (numbered make n separator)
  (let loop ((i n) (parts '()))
    (if (= i 0)
        (fold-left (lambda (acc part) (if (string=? acc "") part (string-append acc separator part))) "" parts)
        (loop (- i 1) (cons (make (number->string i)) parts)))))

(define db (open-database ":memory:"))
(define sum-50 (string-append "select " (numbered (lambda (i) (string-append "?" i)) 50 " + ")))
(define sum-1 (string-append "select ?1" (make-string (- (string-length sum-50) (string-length "select ?1")) #\space)))
(define given (let loop ((i 50) (acc '())) (if (= i 0) acc (loop (- i 1) (cons i acc)))))

(define st50 (prepare-statement db sum-50))
(define st1 (prepare-statement db sum-1))

(define e50 (expiries (lambda () (apply bind-all! st50 given) 'bound)))
(define e1 (expiries (lambda () (bind-all! st1 1) 'bound)))

(display "bind-all! (one section) of 50 values at fuel 1: ") (write e50) (newline)
(display "bind-all! (one section) of 1 value at fuel 1:   ") (write e1) (newline)
(display "difference: ") (write (- (cadr e50) (cadr e1)))
(display (if (>= (- (cadr e50) (cadr e1)) 49) "  -- meets the row's at-least-49-more criterion" "  -- below 49"))
(newline)
(finalize-statement! st50)
(finalize-statement! st1)
(close-database! db)
