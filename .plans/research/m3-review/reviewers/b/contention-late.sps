#!r6rs
;;; Probe: test-contention's "the default" row, its two-thread bounded wait.
;;; The suite's `contended`, copied, with one change: the second thread
;;; sleeps LATE-MS after it hears first-read and before it calls RUN, as a
;;; thread the scheduler wakes late would. Run with 'deferred (what a
;;; library whose with-transaction default were deferred would do): does
;;; the outcome equal the row's expected outcome for the immediate default?
(import (rnrs)
        (only (chezscheme) fork-thread thread-join make-mutex with-mutex make-condition
              condition-wait condition-broadcast make-time current-time time-difference
              add-duration time>=? sleep real-time)
        (chez-sqlite3-testing)
        (chez-sqlite3))

(define (duration ms) (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000)))
(define (await mutex condition ready? ms)
  (let ((deadline (add-duration (current-time 'time-monotonic) (duration ms))))
    (let loop ()
      (let ((now (current-time 'time-monotonic)))
        (cond ((ready?) #t)
              ((time>=? now deadline) #f)
              (else (condition-wait condition mutex (time-difference deadline now)) (loop)))))))
(define long-ms 10000)
(define answer-ms 30000)
(define window-ms 500)
(define (start-thread thunk)
  (let* ((m (make-mutex)) (c (make-condition)) (done #f) (answer 'unfinished)
         (thread (fork-thread
                  (lambda ()
                    (let ((a (guard (e (#t (list 'raised (describe e)))) (thunk))))
                      (with-mutex m (set! answer a) (set! done #t) (condition-broadcast c)))))))
    (lambda (ms)
      (if (with-mutex m (await m c (lambda () done) ms))
          (begin (thread-join thread) (with-mutex m answer))
          'unfinished))))
(define (make-board) (vector (make-mutex) (make-condition) '()))
(define (say! board word value)
  (with-mutex (vector-ref board 0)
    (vector-set! board 2 (cons (cons word value) (vector-ref board 2)))
    (condition-broadcast (vector-ref board 1))))
(define (said-within? board word ms)
  (let ((m (vector-ref board 0)))
    (with-mutex m
      (await m (vector-ref board 1) (lambda () (and (assq word (vector-ref board 2)) #t)) ms))))
(define (word board name)
  (with-mutex (vector-ref board 0)
    (let ((said (assq name (vector-ref board 2)))) (if said (cdr said) 'not-said))))
(define (hear board name)
  (if (said-within? board name long-ms) (word board name) (error 'hear "never said" name)))
(define wal-1500 '((journal-mode . wal) (busy-timeout . 1500)))
(define (pragma db name)
  (let ((row (query-row db (string-append "PRAGMA " name))))
    (if (vector? row) (vector-ref row 0) (list 'no-row row))))
(define (premise db) (list (pragma db "journal_mode") (pragma db "busy_timeout")))
(define (rows db) (query-row db "select count(*) from t"))
(define (mode-of db) (guard (e (#t 'raised)) (if (in-transaction? db) 'in-a-transaction 'autocommit)))
(define (connected path settings proc)
  (let ((db (open-database path settings)))
    (dynamic-wind (lambda () #f) (lambda () (proc db)) (lambda () (guard (e (#t #f)) (close-database! db))))))
(define (wal-file dir name)
  (let ((path (string-append dir "/" name)))
    (connected path '((journal-mode . wal))
      (lambda (db) (execute! db "create table t (x)") (execute! db "insert into t values (1), (2), (3)")))
    path))
(define (counted path) (connected path '() rows))

(define (contended path run late-ms)
  (let* ((b (make-board))
         (first (start-thread
                 (lambda ()
                   (connected path wal-1500
                     (lambda (db)
                       (say! b 'first-premise (premise db))
                       (hear b 'second-open)
                       (dynamic-wind
                         (lambda () #f)
                         (lambda ()
                           (run db (lambda ()
                                     (let ((n (rows db)))
                                       (say! b 'first-read #t)
                                       (let ((saw (if (said-within? b 'second-read window-ms)
                                                      'saw-the-second-read 'no-second-read)))
                                         (execute! db "insert into t values ('first')")
                                         (list n saw))))))
                         (lambda () (say! b 'first-ended (mode-of db)))))))))
         (second (start-thread
                  (lambda ()
                    (connected path wal-1500
                      (lambda (db)
                        (say! b 'second-premise (premise db))
                        (say! b 'second-open #t)
                        (hear b 'first-read)
                        (sleep (duration late-ms))   ; the probe's one change: a late thread
                        (let ((t0 (real-time)))
                          (dynamic-wind
                            (lambda () #f)
                            (lambda ()
                              (run db (lambda ()
                                        (let ((n (rows db)))
                                          (say! b 'second-read (- (real-time) t0))
                                          (hear b 'first-ended)
                                          (execute! db "insert into t values ('second')")
                                          n))))
                            (lambda () (say! b 'second-ended (mode-of db))))))))))
         (f (first answer-ms))
         (s (second answer-ms)))
    (list f s
          (list (word b 'first-premise) (word b 'first-ended)
                (word b 'second-premise) (word b 'second-ended)))))

(define (deferred-run db body) (with-transaction db 'deferred body))
(define (default-run db body) (with-transaction db body))

;; The row's expected outcome for the immediate default, as the suite writes it.
(define immediate-expected
  (list '(#(3) no-second-read) '#(4) '(("wal" 1500) autocommit ("wal" 1500) autocommit) '#(5)))
(define deferred-expected
  (list '(#(3) saw-the-second-read) 'busy-snapshot-raised))

(for-each
 (lambda (late)
   (call-with-temp-directory
    (lambda (dir)
      (let* ((p (wal-file dir (string-append "late-" (number->string late) ".db")))
             (d (contended p deferred-run late))
             (got (list (car d) (cadr d) (caddr d) (counted p))))
        (display "late-ms ") (display late) (display ", 'deferred: ") (write got) (newline)
        (display "  equals the row's expected immediate outcome? ")
        (write (equal? got immediate-expected)) (newline)))))
 '(0 700))
(exit 0)
