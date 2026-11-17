#!r6rs
;; Part A, follow-up 2: each trial of an engine sweep of interrupt-database/with
;; on a stand-in, as tests/test-interrupt-database.sps sweeps it. Each trial
;; opens a fresh :memory: connection, runs the call in a fresh engine of FUEL
;; ticks, closes the connection at the first expiry and resumes the remainder
;; to its end; the sweep runs from fuel 1 until a trial completes unexpired,
;; after one collection, with collect-trip-bytes at a gigabyte. Prints the
;; library's version, then each trial: its fuel, how it ended, and the
;; stand-in's calls in order with the close, called-live for a call handed
;; the connection's handle. With "wrapped", the call runs inside a guard, as
;; the suite's answered runs it. With "spin", the stand-in runs a loop of 20
;; turns before it notes its call: a loop's every turn is a tick an engine
;; counts. No foreign call is made on a closed connection: the stand-in
;; calls nothing.
(import (chezscheme))
(define (reach lib name) (eval name (environment lib)))
(define sqlite-version (reach '(chez-sqlite3) 'sqlite-version))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define interrupt-database/with (reach '(chez-sqlite3 private connection) 'interrupt-database/with))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define wrapped (member "wrapped" (command-line-arguments)))
(define spinning (member "spin" (command-line-arguments)))
(define (spin n) (let loop ((i 0)) (when (< i n) (loop (+ i 1)))))
(display (sqlite-version))
(display (if wrapped ", wrapped" ", bare"))
(display (if spinning ", the stand-in spinning first" ""))
(newline)
(define (trial fuel)
  (let* ((db (open-database ":memory:"))
         (live (call-with-open-handle 'probe db (lambda (h) h)))
         (notes '())
         (note! (lambda (n) (set! notes (cons n notes))))
         (call (lambda ()
                 (interrupt-database/with
                  db (lambda (h)
                       (when spinning (spin 20))
                       (note! (if (eqv? h live) 'called-live (list 'called h)))))))
         (e (make-engine (if wrapped
                             (lambda () (guard (c (#t (list 'raised c))) (call) 'void))
                             (lambda () (call) 'void)))))
    (let ((how (e fuel
                  (lambda (left v) (close-database! db) (note! 'closed) 'completed)
                  (lambda (rest)
                    (close-database! db)
                    (note! 'closed)
                    (let resume ((rest rest))
                      (rest 100000000 (lambda (left v) 'resumed) resume))))))
      (list fuel how (reverse notes)))))
(collect)
(parameterize ((collect-trip-bytes (* 1024 1024 1024)))
  (let loop ((fuel 1))
    (let ((t (trial fuel)))
      (write t)
      (newline)
      (unless (or (eq? (cadr t) 'completed) (>= fuel 500))
        (loop (+ fuel 1))))))
