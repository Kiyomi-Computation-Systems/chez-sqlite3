#!r6rs
;;; interrupt-rig.sps: a prototype of M3 slice 4's interrupted-write rows
;;; (concurrency I5, trap 3), through the library as the suites load it,
;;; before slice 6's interrupt-database! exists.
;;;
;;;   CHEZ_SQLITE3_LIBRARY=LIB $CHEZ --libdirs src:tests:build/scheme-libs \
;;;     --program interrupt-rig.sps DIR NUMBER SOURCE-ID
;;;
;;; Concurrency I5 interrupted each write with another statement R active,
;;; and says none of its cases shows an interrupted write with no other
;;; statement active; with-transaction's case has none, since the
;;; conveniences finish theirs. trap-interrupt-rollback.c had none, in C.
;;; This runs it through the library: inside BEGIN IMMEDIATE and a marker
;;; (nested: SAVEPOINT chez_sqlite3_1 and a second marker), a long write's
;;; step! on the owner thread, while a watchdog thread calls native's
;;; sqlite3-interrupt on the handle every 5 ms until the step has returned,
;;; so the row doesn't depend on how fast the step runs (the M3 plan's
;;; section 4.7 pattern). Then what the step raised, autocommit, the
;;; statement finalized, with-transaction's exit by ADR-0017, and what a
;;; second connection sees. A SELECT reading a table, interrupted the same
;;; way, is the control.
;;;
;;; Every wait is bounded: the watchdog stops at the step's return or after
;;; 20 s, and the owner waits for the watchdog's end at most 5 s.
(import (rnrs)
        (rnrs eval)
        (only (chezscheme) command-line-arguments fork-thread make-mutex make-condition
              with-mutex condition-wait condition-signal sleep make-time)
        (only (chez-sqlite3-testing) describe)
        (chez-sqlite3 private counters))

(define (say . xs)
  (for-each (lambda (x) (if (string? x) (display x) (write x))) xs)
  (newline))

(define public-load
  (guard (e (#t (list 'raised (describe e))))
    (eval '(sqlite-version) (environment '(chez-sqlite3)))
    'loaded))

(define (reach library name)
  (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
    (eval name (environment library))))

(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define sqlite-version (reach '(chez-sqlite3) 'sqlite-version))
(define sqlite-version-number (reach '(chez-sqlite3) 'sqlite-version-number))
(define sqlite-source-id (reach '(chez-sqlite3) 'sqlite-source-id))
(define sqlite-error? (reach '(chez-sqlite3) 'sqlite-error?))
(define sqlite-error-code (reach '(chez-sqlite3) 'sqlite-error-code))
(define sqlite-error-extended-code (reach '(chez-sqlite3) 'sqlite-error-extended-code))
(define sqlite-interrupt? (reach '(chez-sqlite3 private conditions) 'sqlite-interrupt?))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define prepare-statement (reach '(chez-sqlite3 private statement) 'prepare-statement))
(define finalize-statement! (reach '(chez-sqlite3 private statement) 'finalize-statement!))
(define step! (reach '(chez-sqlite3 private statement) 'step!))
(define column-value (reach '(chez-sqlite3 private statement-values) 'column-value))
(define sqlite3-interrupt (reach '(chez-sqlite3 private native) 'sqlite3-interrupt))
(define sqlite3-get-autocommit (reach '(chez-sqlite3 private native) 'sqlite3-get-autocommit))

(define (what-raised e)
  (cond ((sqlite-error? e)
         (list (if (sqlite-interrupt? e) 'sqlite-interrupt 'sqlite-error)
               (if (who-condition? e) (condition-who e) 'no-who)
               (sqlite-error-code e) (sqlite-error-extended-code e)))
        (else (list 'other (describe e)))))

(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (let ((v (thunk)))
      (if (eq? v (if #f #f)) 'no-value (list 'answered v)))))

(define (autocommit db) (call-with-open-handle 'interrupt-rig db sqlite3-get-autocommit))

(define (exec! db sql)
  (let* ((st (prepare-statement db sql))
         (r (guard (e (#t (finalize-statement! st) (raise e)))
              (let loop () (when (step! st) (loop))))))
    (finalize-statement! st)))

(define (one-value db sql)
  (let* ((st (prepare-statement db sql))
         (v (guard (e (#t (finalize-statement! st) (raise e)))
              (step! st)
              (column-value st 0))))
    (finalize-statement! st)
    v))

(define (markers db)
  (attempt (lambda () (one-value db "select coalesce(group_concat(x, ','), '(none)') from (select x from t order by x)"))))

(define (ms n) (make-time 'time-duration (* n 1000000) 0))

;; interrupted-step : Database Statement -> (List Any Integer Symbol)
;; ST's step! on this thread, while a watchdog thread interrupts DB every
;; 5 ms until the step has returned, or 20 s have passed. What step!
;; answered or raised, how many interrupts were sent, and whether the
;; watchdog ended within the 5 s this thread waits for it.
(define (interrupted-step db st)
  (let* ((handle (call-with-open-handle 'interrupt-rig db (lambda (h) h)))
         (m (make-mutex))
         (c (make-condition))
         (done #f)
         (ended #f)
         (sent 0)
         (watchdog
          (fork-thread
           (lambda ()
             (let loop ((i 0))
               (let ((stop (with-mutex m done)))
                 (if (or stop (>= i 4000))
                     (with-mutex m (set! ended #t) (condition-signal c))
                     (begin
                       (sleep (ms 5))
                       (unless (with-mutex m done)
                         (sqlite3-interrupt handle)
                         (with-mutex m (set! sent (+ sent 1))))
                       (loop (+ i 1)))))))))
         (r (attempt (lambda () (step! st))))
         (stopped (with-mutex m (set! done #t)
                    (let wait ((tries 0))
                      (cond (ended 'the-watchdog-ended)
                            ((>= tries 50) 'the-watchdog-did-not-end)
                            (else (condition-wait c m (ms 100)) (wait (+ tries 1)))))))
         (n (with-mutex m sent)))
    (list r (if (> n 0) 'interrupts-sent 'no-interrupt-sent) stopped)))

(define dir (car (command-line-arguments)))
(define counter 0)
(define (fresh-path)
  (set! counter (+ counter 1))
  (string-append dir "/case-" (number->string counter) ".db"))

(define long-write "insert into b with recursive k(i) as (select 1 union all select i + 1 from k where i < 2000000000) select i from k")
(define long-read "with recursive k(i) as (select 1 union all select i + 1 from k where i < 2000000000) select count(*) from k, src")

(define (run-case label sql nested)
  (let* ((path (fresh-path))
         (db (open-database path))
         (setup (begin (exec! db "create table t (x)")
                       (exec! db "create table b (x)")
                       (exec! db "create table src (x)")
                       (exec! db "insert into src values (1), (2), (3)")))
         (db2 (open-database path))
         (begun (begin (exec! db "BEGIN IMMEDIATE")
                       (exec! db "insert into t values ('outer')")
                       (when nested
                         (exec! db "SAVEPOINT chez_sqlite3_1")
                         (exec! db "insert into t values ('inner')"))))
         (st (prepare-statement db sql))
         (step (interrupted-step db st))
         (a (autocommit db))
         (f (attempt (lambda () (finalize-statement! st))))
         (a2 (autocommit db))
         (issued (if (eqv? a2 0)
                     (if nested
                         (list 'rolled-back (attempt (lambda () (exec! db "ROLLBACK TO chez_sqlite3_1")))
                               (attempt (lambda () (exec! db "RELEASE chez_sqlite3_1"))))
                         (list 'rolled-back (attempt (lambda () (exec! db "ROLLBACK")))))
                     '(nothing-issued)))
         (a3 (autocommit db))
         (seen (markers db))
         (seen2 (markers db2))
         (outer (if (eqv? a3 0)
                    (let* ((c (attempt (lambda () (exec! db "COMMIT"))))
                           (s2 (markers db2)))
                      (list 'the-caller-commits-the-outer-level c 'db2-then s2))
                    '())))
    (close-database! db2)
    (close-database! db)
    (say "")
    (say label ", " (if nested "nested" "outer") ": " sql)
    (for-each (lambda (x) (display "  ") (write x) (newline))
              (list (cons 'the-step step) (list 'autocommit-straight-after a)
                    (list 'finalize-statement! f) (list 'autocommit-after-it a2)
                    (list 'the-exit issued) (list 'autocommit-after a3)
                    (list 'db-sees seen) (list 'db2-sees seen2) outer))))

(say "libversion: " (sqlite-version))
(say "sourceid: " (sqlite-source-id))
(let ((args (command-line-arguments)))
  (unless (and (= (length args) 3)
               (equal? (cadr args) (number->string (sqlite-version-number)))
               (equal? (caddr args) (sqlite-source-id)))
    (say "REFUSED: the library is not the header's: " args)
    (exit 2)))
(say "load: " public-load)
(run-case "W1" long-write #f)
(run-case "W1" long-write #t)
(run-case "Q1" long-read #f)
(run-case "Q1" long-read #t)
(say "")
(say "the counts at the end: " (native-counts))
(exit 0)
