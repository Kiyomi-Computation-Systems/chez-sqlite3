;; Does a forked thread's unguarded raise remove make-process-temp-directory's directory?
(import (chezscheme) (chez-sqlite3-testing))
(define dir (make-process-temp-directory))
(define m (make-mutex))
(define c (make-condition))
(define done #f)
(display (list 'before (file-directory? dir))) (newline)
(fork-thread
  (lambda ()
    (dynamic-wind
      (lambda () #f)
      (lambda () (raise 'boom))
      (lambda () (with-mutex m (set! done #t) (condition-broadcast c))))))
(with-mutex m (let loop () (unless done (condition-wait c m) (loop))))
(sleep (make-time 'time-duration 100000000 0))
(display (list 'after (file-directory? dir))) (newline)
(exit 0)
