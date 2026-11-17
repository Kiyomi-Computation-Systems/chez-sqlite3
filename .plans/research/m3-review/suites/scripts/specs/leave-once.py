# The device's limit: mutex-leave raises on its first call, the mutex held.
EDITS = [("tests/test-interrupt-reach.sps",
'(define mutex-leave (bound \'sqlite3_mutex_leave (foreign-procedure "sqlite3_mutex_leave" (uptr) void)))',
'''(define mutex-leave
  (let ((real (bound 'sqlite3_mutex_leave (foreign-procedure "sqlite3_mutex_leave" (uptr) void)))
        (calls 0))
    (lambda (m)
      (set! calls (+ calls 1))
      (if (= calls 1) (error 'mutex-leave "planted: raises on its first call") (real m)))))''')]
