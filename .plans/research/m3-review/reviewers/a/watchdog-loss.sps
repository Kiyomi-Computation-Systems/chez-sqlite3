#!r6rs
;; Probe: once a tight watchdog has left with-transaction's transaction open,
;; and the watchdog has stopped, does a later with-transaction that returns
;; normally commit its write? Closed and reopened, is the write there?
(import (chezscheme) (chez-sqlite3))
(define dir "build/m3cr-a/probes/tmp")
(system (string-append "mkdir -p " dir))
(define path (string-append dir "/wd3.db"))
(system (string-append "rm -f " path " " path "-journal " path "-wal " path "-shm"))
(define db (open-database path '((journal-mode . wal))))
(execute! db "create table if not exists t(x)")
(define done #f)
(define m (make-mutex)) (define c (make-condition)) (define finished #f)
(fork-thread (lambda ()
               (let loop () (unless done (interrupt-database! db) (loop)))
               (with-mutex m (set! finished #t) (condition-signal c))))
(define (stop-watchdog!)
  (set! done #t)
  (with-mutex m (let w () (unless finished (condition-wait c m) (w)))))
(define left-open-at
  (let loop ((i 0))
    (cond ((>= i 50000) #f)
          (else
           (guard (e (#t #f))
             (with-transaction db 'deferred
               (lambda () (execute! db "insert into t values (1)") (raise 'boom))))
           (if (in-transaction? db) i (loop (+ i 1)))))))
(stop-watchdog!)
(printf "transaction left open by with-transaction at trial ~a; in-transaction? ~a\n" left-open-at (in-transaction? db))
(define answer (with-transaction db (lambda () (execute! db "insert into t values (999)") 'committed?)))
(printf "a later with-transaction answered ~a; in-transaction? after it ~a\n" answer (in-transaction? db))
(close-database! db)
(define db2 (open-database path))
(printf "after close and reopen, rows of 999: ~a\n" (query-row db2 "select count(*) from t where x = 999"))
(close-database! db2)
