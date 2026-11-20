;; datums.sps BEFORE AFTER: exit 0 when the two files read, by Chez's read, as the same datums,
;; equal?, and 1 otherwise, printing the first datum that differs. A file that can't be read
;; whole is a difference, so two unreadable files never pass as alike. sweep-check.sh runs it
;; on each edited .sps and .sls.
(import (chezscheme))

;; datums : String -> (U (Listof Any) (List 'unreadable String))
(define (datums path)
  (guard (e (#t (list 'unreadable
                      (if (message-condition? e) (condition-message e) "no message"))))
    (call-with-input-file path
      (lambda (p)
        (let loop ((acc '()))
          (let ((d (read p)))
            (if (eof-object? d) (reverse acc) (loop (cons d acc)))))))))

;; first-difference : List List Natural -> (U Natural #f)
(define (first-difference a b i)
  (cond ((and (null? a) (null? b)) #f)
        ((or (null? a) (null? b) (not (equal? (car a) (car b)))) i)
        (else (first-difference (cdr a) (cdr b) (+ i 1)))))

(let* ((args (command-line-arguments))
       (before (datums (car args)))
       (after (datums (cadr args))))
  (cond ((or (and (pair? before) (eq? (car before) 'unreadable))
             (and (pair? after) (eq? (car after) 'unreadable)))
         (display "unreadable: ")
         (write (list before after))
         (newline)
         (exit 1))
        ((equal? before after) (exit 0))
        (else
         (let ((i (first-difference before after 0)))
           (display "datum ")
           (write i)
           (display " differs: ")
           (write (and (< i (length before)) (list-ref before i)))
           (display " became ")
           (write (and (< i (length after)) (list-ref after i)))
           (newline)
           (exit 1)))))
