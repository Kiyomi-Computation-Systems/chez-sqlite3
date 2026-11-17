;; Probe (M3's closing review, the transaction builder): reviewer A's
;; script-reenter4.sps, a timer's handler taking a continuation at its
;; first fire and calling it at its second, while execute-script! runs,
;; over 2804 (T1, T2). Run against a copy of the tree with
;; window-probe.patch applied to connection.sls, which marks
;; call-with-open-handle's window between FINISHED's set! and the wind's
;; exit: the tally keys each outcome by whether the first fire found the
;; window marked, and the first line counts every fire that found it so.
;; Run from the copy: $CHEZ --libdirs src:tests:build/scheme-libs --program window-probe.sps
;; Output: window-probe.out.
#!r6rs
(import (chezscheme) (chez-sqlite3) (only (chez-sqlite3 private connection) probe-in-window))
(define n-stmts 8)
(define script
  (let loop ((i 1) (acc ""))
    (if (> i n-stmts) acc
        (loop (+ i 1) (string-append acc "insert into t values(" (number->string i) ");")))))
(define (trial t1 t2)
  (let ((db (open-database ":memory:")))
    (execute! db "create table t(x)")
    (let* ((k1 #f) (fired 0) (used #f) (trace '()) (where 'unset)
           (base (total-changes db))
           (outcome
            (guard (e (#t (list 'raised (and (condition? e) (who-condition? e) (condition-who e)) (sqlite-closed? e) (and (message-condition? e) (condition-message e)) (and (irritants-condition? e) (condition-irritants e)))))
              (timer-interrupt-handler
               (lambda ()
                 (set! fired (+ fired 1))
                 (when (probe-in-window) (set! in-window-fires (+ in-window-fires 1)))
                 (set! trace (cons (- (total-changes db) base) trace))
                 (cond ((= fired 1)
                        (set! where (probe-in-window))
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
        (list t1 t2 fired (reverse trace) outcome rows where)))))
(define in-window-fires 0)
(define tally (make-hashtable equal-hash equal?))
(define shown 0)
(for-each (lambda (t2)
(let loop ((t1 950))
  (when (<= t1 1650)
    (let* ((r (trial t1 t2))
           (key (list (list-ref r 4) (list-ref r 6))))
      (hashtable-update! tally key (lambda (n) (+ n 1)) 0)
      (when (and (> (length (list-ref r 5)) n-stmts) (< shown 6))
        (set! shown (+ shown 1)) (write r) (newline)))
    (loop (+ t1 1)))))
 '(40 80 150 230))
(printf "timer fires inside the window: ~a\n" in-window-fires)
(let-values (((ks vs) (hashtable-entries tally))) (vector-for-each (lambda (k v) (write (list k v)) (newline)) ks vs))
