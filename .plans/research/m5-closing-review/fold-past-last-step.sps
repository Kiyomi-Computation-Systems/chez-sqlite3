#!r6rs
;;; query-fold under an engine, resumed after each expiry, at every fuel from 1 until no run
;;; expires, each fuel on fresh :memory: connections: the cache's default, cold then warm, and
;;; the cache at 0. Each run is keyed by (cache phase answer at-last-expiry end end-cached):
;;; its answer, 6 or closed; at its last expiry, how many times the procedure had been
;;; entered and the fold's statement's tracked states, #f when it never expired; and at its
;;; end, those states again and the cache's count, which holds the setup's two statements at
;;; the default. From the repository root, in the container, after make deps:
;;;
;;;   $CHEZ --libdirs src:tests:build/scheme-libs \
;;;     --program .plans/research/m5-closing-review/fold-past-last-step.sps
(import (rnrs) (rnrs eval) (rnrs mutable-pairs) (only (chezscheme) make-engine)
        (chez-sqlite3-testing) (chez-sqlite3 private counters))

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

(define (attempt thunk)
  (guard (e ((closed? e) 'closed) (#t (list 'raised (describe e)))) (thunk)))

;; The states of the fold's statements the connection tracks.
(define (snapshot db)
  (let loop ((rest (tracked-statements db)) (found '()))
    (if (null? rest)
        (reverse found)
        (loop (cdr rest)
              (if (string=? (statement-sql (car rest)) "select x from n")
                  (cons (statement-state (car rest)) found)
                  found)))))

(define (run-at db fuel)
  (let* ((calls 0) (last #f) (expired #f)
         (thunk (lambda ()
                  (attempt (lambda ()
                             (query-fold db "select x from n"
                                         (lambda (acc row)
                                           (set! calls (+ calls 1))
                                           (+ acc (vector-ref row 0)))
                                         0))))))
    (let loop ((e (make-engine thunk)) (n 0))
      (let ((next (e fuel (lambda (left . vals) (list 'completed (car vals)))
                     (lambda (more) more))))
        (cond ((pair? next)
               (list (cadr next) (and expired last) (snapshot db) (database-cache-count db)))
              ((>= n 100000) (list 'never))
              (else (set! expired #t)
                    (set! last (list calls (snapshot db)))
                    (loop next (+ n 1))))))))

(define (with-db settings proc)
  (let ((db (open-database ":memory:" settings)))
    (execute! db "create table n (x)")
    (execute! db "insert into n values (1), (2), (3)")
    (let ((r (proc db))) (close-database! db) r)))

(define tally '())
(define (note! key fuel)
  (let ((hit (assoc key tally)))
    (if hit (set-cdr! hit (cons fuel (cdr hit))) (set! tally (cons (list key fuel) tally)))))
(define (key cache phase r) (list cache phase (car r) (cadr r) (caddr r) (cadddr r)))

(define done
  (let loop ((fuel 1))
    (let* ((c (with-db '()
                       (lambda (db)
                         (let* ((cold (run-at db fuel))
                                (warm (begin (query-fold db "select x from n" (lambda (a r) a) 0)
                                             (run-at db fuel))))
                           (list cold warm)))))
           (z (with-db '((statement-cache . 0)) (lambda (db) (run-at db fuel)))))
      (note! (key 32 'cold (car c)) fuel)
      (note! (key 32 'warm (cadr c)) fuel)
      (note! (key 0 'cold z) fuel)
      (if (or (and (not (cadr (car c))) (not (cadr (cadr c))) (not (cadr z))) (>= fuel 5000))
          fuel
          (loop (+ fuel 1))))))

(display "completed at ") (write done) (newline)
(for-each (lambda (e)
            (let ((fs (cdr e)))
              (write (car e)) (display ": ") (write (length fs)) (display " ")
              (write (if (> (length fs) 10)
                         (list (car fs) '... (list-ref fs (- (length fs) 1)))
                         fs))
              (newline)))
          (list-sort (lambda (a b) (< (cadr a) (cadr b)))
                     (map (lambda (e) (cons (car e) (reverse (cdr e)))) tally)))
(write (native-counts)) (newline)
