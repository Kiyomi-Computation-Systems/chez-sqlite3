#!r6rs
;;; Review probe: with-transaction modelled exactly as ADR-0017 decision 7 and
;;; the M3 plan 4.2 shape it, driven by slice 1's transaction-plan, over a
;;; fake connection. Each statement runs as execute! will: some plain Scheme
;;; work (the check-out, the copy, the checks), then the step in a critical
;;; section of its own, which sets a flag when asked. The commit is planned
;;; "with ended still unset, the autocommit read, then COMMIT or RELEASE".
;;; An engine runs the call at each fuel; at its first expiry it is resumed
;;; to the end, as the records' sweep does.
(import (except (rnrs) dynamic-wind)
        (only (chezscheme) make-engine critical-section display-condition dynamic-wind)
        (chez-sqlite3 private transaction-plan))

;; --- a fake connection: autocommit and the savepoint stack ---------------
(define autocommit 1)
(define savepoints '())     ; newest first
(define sp-began-tx #f)
(define trail '())
(define (note! x) (set! trail (cons x trail)))

(define (prefix? p s) (and (>= (string-length s) (string-length p))
                           (string=? (substring s 0 (string-length p)) p)))
(define (after p s) (substring s (string-length p) (string-length s)))

;; step : String -> (U 'ok (List 'error String))
(define (step sql)
  (note! sql)
  (cond ((prefix? "BEGIN" sql)
         (if (eqv? autocommit 0) '(error "cannot start a transaction within a transaction")
             (begin (set! autocommit 0) 'ok)))
        ((string=? sql "COMMIT")
         (if (eqv? autocommit 1) '(error "cannot commit - no transaction is active")
             (begin (set! autocommit 1) (set! savepoints '()) 'ok)))
        ((string=? sql "ROLLBACK")
         (if (eqv? autocommit 1) '(error "cannot rollback - no transaction is active")
             (begin (set! autocommit 1) (set! savepoints '()) 'ok)))
        ((prefix? "SAVEPOINT " sql)
         (when (eqv? autocommit 1) (set! autocommit 0) (set! sp-began-tx #t))
         (set! savepoints (cons (after "SAVEPOINT " sql) savepoints)) 'ok)
        ((prefix? "ROLLBACK TO " sql)
         (let ((m (member (after "ROLLBACK TO " sql) savepoints)))
           (if m (begin (set! savepoints m) 'ok) (list 'error "no such savepoint"))))
        ((prefix? "RELEASE " sql)
         (let ((m (member (after "RELEASE " sql) savepoints)))
           (if m
               (begin (set! savepoints (cdr m))
                      (when (and (null? savepoints) sp-began-tx)
                        (set! autocommit 1) (set! sp-began-tx #f))
                      'ok)
               (list 'error "no such savepoint"))))
        (else 'ok)))

(define (spin n) (let loop ((i 0)) (when (< i n) (loop (+ i 1)))))

;; execute : String (-> Void) -> Void
;; execute!'s shape: plain work, then the step in its own section, which
;; calls ON-OK inside it; a failure raised after the section.
(define (execute sql on-ok)
  (spin 30)                                   ; check-out, copy, checks
  (let ((r (critical-section (let ((r (step sql))) (when (eq? r 'ok) (on-ok)) r))))
    (spin 30)                                 ; return to the cache
    (unless (eq? r 'ok) (raise (list 'sqlite-error sql (cadr r))))))

(define depth 0)

;; with-tx : (-> Any) -> Any
(define (with-tx body)
  (let ((begun #f) (ended #f) (level #f) (raising #f) (failure #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (dynamic-wind #t
          (lambda () #f)
          (lambda ()
            (with-exception-handler
             (lambda (c) (set! raising (list c)) (raise-continuable c))
             (lambda ()
               (let ((b (critical-section (begin-plan autocommit depth))))
                 (set! level (cadr b))
                 (execute (caddr b) (lambda () (set! begun #t))))
               (call-with-values body
                 (lambda answers
                   ;; the commit: ended unset, autocommit read, then COMMIT or RELEASE
                   (let ((p (critical-section (exit-plan 'return begun ended autocommit level))))
                     (case (car p)
                       ((commit)
                        (guard (c (#t
                                   (let ((f (critical-section (failed-commit-plan ended autocommit level))))
                                     (when (eq? (car f) 'rollback)
                                       (for-each (lambda (s) (guard (x (#t #f)) (execute s (lambda () #f))))
                                                 (cdr f)))
                                     (set! ended #t)
                                     (raise c))))
                          (execute (cadr p) (lambda () (set! ended #t))))
                        (apply values answers))
                       ((transaction-ended) (raise 'transaction-ended))
                       (else (raise (list 'unexpected p))))))))))
          (lambda ()                        ; the critical after thunk
            (when (and begun (not ended))
              (let ((p (exit-plan 'escape begun ended autocommit level)))
                (when (eq? (car p) 'rollback)
                  (for-each (lambda (s) (note! (list 'after-thunk s))
                                (guard (x (#t (set! failure x))) (critical-section (step s))))
                            (cdr p)))
                (set! ended #t))))))
      (lambda () #f))))

(define (reset! ac)
  (set! autocommit ac) (set! savepoints '()) (set! sp-began-tx #f) (set! trail '()))

;; run-at : Natural Natural -> (List Natural Any (Listof Any))
;; One with-transaction at FUEL, from autocommit AC (0: the caller's BEGIN
;; first), resumed to its end after its first expiry.
(define (run-at fuel ac)
  (reset! ac)
  (when (eqv? ac 0) (set! trail '()))
  (let ((answer
         (guard (c (#t (list 'raised c)))
           ((make-engine (lambda () (with-tx (lambda () (execute "INSERT" (lambda () #f)) 42))))
            fuel
            (lambda (left . vals) (cons 'answered vals))
            (lambda (next)
              (note! 'expired)
              (next 100000000 (lambda (left . vals) (cons 'answered-after-resume vals))
                    (lambda (again) 'expired-again)))))))
    (list fuel answer (reverse trail) (list 'autocommit autocommit 'savepoints savepoints))))

(define (interesting? r)
  ;; a statement of with-transaction's own issued after the after thunk's
  ;; rollback, outside it (each (after-thunk S) is followed by S's own note)
  (let loop ((l (caddr r)) (seen-after #f))
    (cond ((null? l) #f)
          ((and (pair? (car l)) (eq? (caar l) 'after-thunk)) (loop (cddr l) #t))
          ((and seen-after (string? (car l)) (not (string=? (car l) "INSERT"))) #t)
          (else (loop (cdr l) seen-after)))))

(define (sweep ac)
  (let loop ((fuel 1) (found '()))
    (if (> fuel 400)
        (reverse found)
        (let ((r (run-at fuel ac)))
          (loop (+ fuel 1) (if (interesting? r) (cons r found) found))))))

(for-each (lambda (ac)
            (display "=== from autocommit ") (display ac)
            (display (if (eqv? ac 1) " (outer level)" " (the caller's BEGIN: a savepoint)")) (newline)
            (let ((found (sweep ac)))
              (display "fuels issuing a statement after the after thunk's rollback: ")
              (display (map car found)) (newline)
              (unless (null? found)
                (write (car found)) (newline))))
          '(1 0))
(for-each (lambda (f) (write (run-at f 1)) (newline)) '(1 5 20 40 60 80 100 120 140 160 200))
(guard (c (#t (display-condition c) (newline)))
  (reset! 1)
  (with-tx (lambda () (execute "INSERT" (lambda () #f)) 42)))
;; Variant: between the expiry and the resume, another engine on the same
;; connection begins its own with-transaction at the same depth, which the
;; ended level no longer holds, and is mid-body.
(define (run-other-at fuel)
  (reset! 0)
  (let ((answer
         (guard (c (#t (list 'raised c)))
           ((make-engine (lambda () (with-tx (lambda () (execute "INSERT" (lambda () #f)) 42))))
            fuel
            (lambda (left . vals) (cons 'answered vals))
            (lambda (next)
              (note! 'expired)
              (critical-section (step "SAVEPOINT chez_sqlite3_0") (step "INSERT-B"))
              (next 100000000 (lambda (left . vals) (cons 'answered-after-resume vals))
                    (lambda (again) 'expired-again)))))))
    (list fuel answer (reverse trail) (list 'autocommit autocommit 'savepoints savepoints))))
(display "=== another engine's savepoint at the same depth, fuel 140") (newline)
(write (run-other-at 140)) (newline)
