#!r6rs
;; Probe: the statement-cache row "string keys of other shapes" as written,
;; out! traced with the table's count before each call, in a --program, as
;; make test runs it. Shows the order the seven check-outs run in, and
;; what the table holds when each near spelling is tried.
(import (rnrs) (chez-sqlite3 private statement-cache))

(define trace '())
(define (make n) (make-statement-cache n))
(define (ret! c k s) (statement-cache-return! c k s))
(define (out! c k)
  (let ((before (statement-cache-count c)))
    (let ((r (statement-cache-check-out! c k)))
      (set! trace (cons (list (if (> (string-length k) 10) (list 'long-key (string-ref k (- (string-length k) 1))) k)
                              'count-before before r)
                        trace))
      r)))

(define answer
  (let* ((c (make 8)) (long (make-string 5000 #\a)))
    (ret! c "" "e") (ret! c "a\x0;b" "nul") (ret! c long "long") (ret! c "caf\xe9;" "uni")
    (list (out! c "") (out! c (string-copy "a\x0;b")) (out! c (string-copy long))
          (out! c (string-copy "caf\xe9;"))
          (out! c "a") (out! c "cafe") (out! c (string-append (make-string 4999 #\a) "b")))))

(write answer) (newline)
(for-each (lambda (t) (write t) (newline)) (reverse trace))
