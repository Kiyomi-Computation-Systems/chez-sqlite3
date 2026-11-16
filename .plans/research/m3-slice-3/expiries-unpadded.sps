;; M3 slice 3, part B's probe: how many times an engine of fuel 1 expires
;; through query, for 50 parameters against 1 and for 50 columns against 1,
;; in SQL of different lengths: the first draft of the engines suite's
;; one-value-a-section row. checked-sql reads each character outside any
;; critical section, so a longer SQL costs ticks of its own, and the row pads
;; its one-value SQL to its twin's length. Run from the repository's root:
;;   $CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-3/expiries-unpadded.sps
(import (rnrs) (only (chezscheme) make-engine) (chez-sqlite3) (chez-sqlite3 private conveniences))
(define (expiries thunk)
  (let loop ((e (make-engine thunk)) (n 0))
    (let ((next (e 1 (lambda (left . vals) (list 'completed (car vals))) (lambda (more) more))))
      (cond ((pair? next) (list (cadr next) n)) (else (loop next (+ n 1)))))))
(define db (open-database ":memory:"))
(define (nums n) (let loop ((i n) (acc '())) (if (= i 0) acc (loop (- i 1) (cons i acc)))))
(define (joined make n sep) (let loop ((i n) (parts '())) (if (= i 0) (fold-left (lambda (a p) (if (string=? a "") p (string-append a sep p))) "" parts) (loop (- i 1) (cons (make (number->string i)) parts)))))
(define sum50 (string-append "select " (joined (lambda (i) (string-append "?" i)) 50 " + ")))
(define cols50 (string-append "select " (joined (lambda (i) i) 50 ", ")))
(query db "select 1") (query db "select ?1" 1) (apply query db sum50 (nums 50)) (query db cols50)
(for-each (lambda (x) (write (cadr x)) (newline))
  (list (expiries (lambda () (apply query db sum50 (nums 50))))
        (expiries (lambda () (query db "select ?1" 1)))
        (expiries (lambda () (query db cols50)))
        (expiries (lambda () (query db "select 1")))))
(close-database! db)
