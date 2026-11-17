;; Probe (M3's closing review, the transaction builder): a thunk that
;; counts its entry, then calls wt, whose work, transaction, makes a claim
;; by its first expression and notes it, as with-transaction's does. At
;; each fuel the first remainder is resumed to its end twice. At fuel 2 the
;; first slice had counted the entry and made no claim, and both resumes
;; made claims: the procedure entries between a caller's count and a
;; callee's first expression are ticks an engine stops at.
;; Run: $CHEZ --libdirs . --program window.sps (probe-lib.sls beside it).
;; Output: window.out.
(import (chezscheme) (probe-lib))
(define (run e fuel) (e fuel (lambda (t . v) (cons 'done v)) (lambda (r) (list 'expired r))))
(let loop ((f 1))
  (let* ((n 0)
         (thunk (lambda () (set! n (+ n 1)) (wt 'db 'deferred (lambda () 42))))
         (_ (clear-marks!))
         (first (run (make-engine thunk) f)))
    (if (eq? (car first) 'done)
        (printf "completes at ~a\n" f)
        (let* ((r (cadr first))
               (n0 n) (m0 (length (marks)))
               (r1 (run r 100000)) (n1 n) (m1 (length (marks)))
               (r2 (run r 100000)) (n2 n) (m2 (length (marks))))
          (printf "fuel ~a: entries after first ~a r1 ~a r2 ~a; claims after first ~a r1 ~a r2 ~a\n" f n0 n1 n2 m0 m1 m2)
          (loop (+ f 1))))))
