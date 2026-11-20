#!r6rs
;;; Gap 2: query-fold under an engine, resumed after each expiry, at every
;;; fuel from 1 until one slice completes it, each fuel on a fresh :memory:
;;; connection, cold (a miss) then warm (a hit). Each run is judged by what it
;;; saw itself: at each expiry, how many times the procedure had been
;;; entered, the statements the connection tracks with their states, and the
;;; cache's count. Then the run's answer: the fold, 6, or what it raised.
;;;
;;; Each run is keyed by its phase, its answer and, when it expired, the
;;; procedure's entries and the fold's statement's tracked states at its
;;; last expiry: () is none tracked, not yet prepared or already finalized;
;;; (ready) is cached and ready. So an expired run answering 6 whose last
;;; expiry came at 3 calls expired past the last row's procedure, and a
;;; closed one at 3 calls expired between that procedure and the last step.
(import (rnrs) (rnrs eval) (rnrs mutable-pairs) (only (chezscheme) make-engine) (chez-sqlite3-testing)
        (chez-sqlite3 private counters))

(define (reach library name) (eval name (environment library)))
(define public '(chez-sqlite3))
(define query-fold (reach public 'query-fold))
(define execute! (reach public 'execute!))
(define open-database (reach public 'open-database))
(define close-database! (reach public 'close-database!))
(define closed? (reach public 'sqlite-closed?))
(define tracked-statements (reach '(chez-sqlite3 private connection) 'tracked-statements))
(define database-cache-count (reach '(chez-sqlite3 private connection) 'database-cache-count))
(define statement-sql (reach '(chez-sqlite3 private statement) 'statement-sql))
(define statement-state (reach '(chez-sqlite3 private statement) 'statement-state))

(define (list-head* l n) (if (or (= n 0) (null? l)) '() (cons (car l) (list-head* (cdr l) (- n 1)))))
(define (format-key k)
  (call-with-string-output-port (lambda (p) (write k p))))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))
(define (attempt thunk)
  (guard (e ((closed? e) (list 'raised 'closed (who-of e)))
            (#t (list 'raised (describe e))))
    (thunk)))

;; snapshot : Database -> (List (Listof Symbol) Symbol Boolean)
;; The fold's own statement as the connection sees it: the states of those
;; it tracks whose SQL is the fold's, and whether the cache holds one ready.
(define (snapshot db)
  (let loop ((rest (tracked-statements db)) (found '()))
    (if (null? rest)
        (list (reverse found))
        (loop (cdr rest)
              (if (string=? (statement-sql (car rest)) "select x from n")
                  (cons (statement-state (car rest)) found)
                  found)))))

;; run-at : Database Positive-Integer -> (List Any (Listof Any))
;; The fold's answer, and at each expiry, in order, (calls . snapshot).
(define (run-at db fuel)
  (let* ((calls 0)
         (expiries '())
         (thunk (lambda ()
                  (attempt (lambda ()
                             (query-fold db "select x from n"
                                         (lambda (acc row)
                                           (set! calls (+ calls 1))
                                           (+ acc (vector-ref row 0)))
                                         0))))))
    (let loop ((e (make-engine thunk)) (n 0))
      (let ((next (e fuel (lambda (left . vals) (list 'completed (car vals))) (lambda (more) more))))
        (cond ((pair? next) (list (cadr next) (reverse expiries)))
              ((>= n 100000) (list 'never-completed (reverse expiries)))
              (else
               (let ((now calls))
                 (set! expiries (cons (cons now (snapshot db)) expiries)))
               (loop next (+ n 1))))))))

(define (kind-of phase answer expiries)
  (if (null? expiries)
      'unexpired
      (let ((last (list-ref expiries (- (length expiries) 1))))
        (list 'expired 'last-expiry-at-calls (car last) 'fold-statement-then (cadr last)))))

(define (with-db proc)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda () (attempt (lambda ()
                            (set! db (open-database ":memory:"))
                            (execute! db "create table n (x)")
                            (execute! db "insert into n values (1), (2), (3)")
                            (proc db))))
      (lambda () (when db (guard (e (#t #f)) (close-database! db)))))))

(define tally '())
(define (note! key fuel)
  (let ((hit (assoc key tally)))
    (if hit
        (set-cdr! hit (cons fuel (cdr hit)))
        (set! tally (cons (list key fuel) tally)))))

(define examples '())
(define (example! key x)
  (unless (assoc key examples) (set! examples (cons (cons key x) examples))))

;; brief : (Listof Any) -> Any
;; An expiry list as its length, its first and its last.
(define (brief expiries)
  (if (null? expiries)
      '(none)
      (list 'count (length expiries) 'first (car expiries) 'last (list-ref expiries (- (length expiries) 1)))))

(define completed-at
  (let loop ((fuel 1))
    (let* ((r (with-db
               (lambda (db)
                 (let* ((cold (run-at db fuel))
                        (warm (begin (query-fold db "select x from n" (lambda (a r) a) 0)
                                     (run-at db fuel))))
                   (list cold warm)))))
           (both-unexpired
            (and (pair? r) (not (eq? (car r) 'raised))
                 (let* ((cold (car r)) (warm (cadr r)))
                   (for-each
                    (lambda (phase run)
                      (let* ((answer (car run)) (kind (kind-of phase answer (cadr run))))
                        (note! (list phase answer kind) fuel)
                        (example! (list phase answer kind) (list 'fuel fuel 'expiries (brief (cadr run))))))
                    (list 'cold 'warm) (list cold warm))
                   (and (null? (cadr cold)) (null? (cadr warm)))))))
      (cond ((and (pair? r) (eq? (car r) 'raised)) (display "raised: ") (write r) (newline) fuel)
            (both-unexpired fuel)
            ((>= fuel 5000) (list 'no-completion-by fuel))
            (else (loop (+ fuel 1)))))))

(display "library: ") (write (eval '(sqlite-version) (environment public))) (newline)
(display "completed without expiring at fuel ") (write completed-at) (newline)
(for-each
 (lambda (entry)
   (let ((fuels (reverse (cdr entry))))
     (write (car entry)) (display ": ") (write (length fuels)) (display " fuels, ")
     (write (if (> (length fuels) 12) (append (list-head* fuels 12) '(...)) fuels)) (newline)))
 (list-sort (lambda (a b) (string<? (format-key (car a)) (format-key (car b)))) tally))
(newline)
(display "the first fuel of each, its expiries as (calls (states of the fold's statement, tracked)):") (newline)
(for-each (lambda (x) (write x) (newline))
          (list-sort (lambda (a b) (string<? (format-key (car a)) (format-key (car b)))) examples))
(display "counts at the end: ") (write (native-counts)) (newline)
