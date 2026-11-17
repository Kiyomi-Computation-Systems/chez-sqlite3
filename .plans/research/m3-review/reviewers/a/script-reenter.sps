#!r6rs
;; Probe: a timer handler's continuation, taken inside execute-script!'s block
;; and called from a later timer interrupt in the same call, re-runs later
;; statements of the script? Sweeps (T1, T2): first fire at T1 ticks captures
;; k and re-arms at T2; the second fire calls k once.
(import (chezscheme) (chez-sqlite3))

(define n-stmts 8)
(define script
  (let loop ((i 1) (acc ""))
    (if (> i n-stmts) acc
        (loop (+ i 1) (string-append acc "insert into t values(" (number->string i) ");")))))

(define (trial t1 t2)
  (let ((db (open-database ":memory:")))
    (execute! db "create table t(x)")
    (let* ((k1 #f) (fired 0) (used #f)
           (outcome
            (guard (e (#t (list 'raised (if (condition? e)
                                            (list (and (who-condition? e) (condition-who e))
                                                  (and (message-condition? e) (condition-message e))
                                                  (if (sqlite-error? e) (sqlite-error-code e) '-)
                                                  (sqlite-closed? e))
                                            e))))
              (timer-interrupt-handler
               (lambda ()
                 (set! fired (+ fired 1))
                 (cond ((= fired 1)
                        (call/cc (lambda (k) (set! k1 k)))
                        (set-timer t2))
                       ((and (>= fired 2) (not used))
                        (set! used #t)
                        (k1 #f)))))
              (set-timer t1)
              (execute-script! db script)
              (set-timer 0)
              'returned)))
      (set-timer 0)
      (let ((rows (map (lambda (r) (vector-ref r 0)) (query db "select x from t order by rowid"))))
        (close-database! db)
        (list t1 t2 fired used outcome rows)))))

(define dups 0)
(define kinds (make-hashtable equal-hash equal?))
(define trials 0)
(let loop1 ((t1 1))
  (when (<= t1 400)
    (let loop2 ((t2 1))
      (when (<= t2 400)
        (let ((r (trial t1 t2)))
          (set! trials (+ trials 1))
          (hashtable-update! kinds (list (list-ref r 3) (let ((o (list-ref r 4))) (if (pair? o) (cadr o) o)) (length (list-ref r 5))) (lambda (n) (+ n 1)) 0)
          (let ((rows (list-ref r 5)))
            (when (> (length rows) n-stmts)
              (set! dups (+ dups 1))
              (when (< dups 6) (write r) (newline)))))
        (loop2 (+ t2 13))))
    (loop1 (+ t1 7))))
(let-values (((ks vs) (hashtable-entries kinds))) (vector-for-each (lambda (k v) (write (list k v)) (newline)) ks vs))
(printf "trials ~a, with a statement run twice ~a\n" trials dups)
