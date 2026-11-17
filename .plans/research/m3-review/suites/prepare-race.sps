#!r6rs
;;; Probe: test-interrupt-reach's long-prepare row, alone, TRIALS times in
;;; one process, with either watchdog round, to measure how often a prepare
;;; runs unstopped. Run from a tree's root, under the gate's Valgrind or
;;; plain:
;;;   $CHEZ --libdirs src:tests:build/scheme-libs --program PROBE DEVICE ITEMS DELAY-MS TRIALS
;;; DEVICE    old: the round as at e590fdc: take SQLite's memory mutex, start
;;;           the owner, sleep 1 ms holding it, interrupt, let it go, sleep
;;;           1 ms
;;;           handshake: the first round interrupts holding the mutex before
;;;           the owner starts, then holds it, polling sqlite3_is_interrupted
;;;           each 1 ms, until the flag reads clear, which only the owner's
;;;           parse (or a statement's start) does; then interrupts again and
;;;           lets it go. Later rounds are the old ones.
;;; ITEMS     the IN list's length: 1000000 is the suite's SQL
;;; DELAY-MS  the owner sleeps this long inside the watched thunk before it
;;;           calls prepare-statement, so the first round can end first
;;; Each trial prints whether the prepare was stopped, how many interrupts
;;; were sent, the milliseconds the call took, and how many sends after the
;;; first found the flag clear, so came after a clear, with the ms from the
;;; call's start of the first of them; then the counts.
(import (rnrs) (rnrs eval)
        (only (chezscheme) foreign-procedure fork-thread thread-join make-mutex with-mutex
              make-condition condition-wait condition-broadcast make-time current-time
              time-difference add-duration time>=? sleep real-time)
        (only (chez-sqlite3 private conditions) sqlite-interrupt?))

(define env (environment '(chez-sqlite3)))
(define loaded (eval '(sqlite-version) env))
(define (pub name) (eval name env))
(define open-database (pub 'open-database))
(define close-database! (pub 'close-database!))
(define prepare-statement (pub 'prepare-statement))
(define finalize-statement! (pub 'finalize-statement!))
(define interrupt-database! (pub 'interrupt-database!))
(define call-with-open-handle (eval 'call-with-open-handle (environment '(chez-sqlite3 private connection))))

(define is-interrupted (foreign-procedure "sqlite3_is_interrupted" (uptr) int))
(define mutex-alloc (foreign-procedure "sqlite3_mutex_alloc" (int) uptr))
(define mutex-enter (foreign-procedure "sqlite3_mutex_enter" (uptr) void))
(define mutex-leave (foreign-procedure "sqlite3_mutex_leave" (uptr) void))
(define memory-mutex (mutex-alloc 3))

(define args (cdr (command-line)))
(define device (string->symbol (list-ref args 0)))
(define items (string->number (list-ref args 1)))
(define delay-ms (string->number (list-ref args 2)))
(define trials (string->number (list-ref args 3)))

(define (duration ms) (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000)))
(define one-ms (duration 1))
(define (await m c ready? ms)
  (let ((deadline (add-duration (current-time 'time-monotonic) (duration ms))))
    (let loop ()
      (let ((now (current-time 'time-monotonic)))
        (cond ((ready?) #t)
              ((time>=? now deadline) #f)
              (else (condition-wait c m (time-difference deadline now)) (loop)))))))

(define sql
  (call-with-string-output-port
   (lambda (p)
     (put-string p "select 1 in (")
     (let loop ((i 0)) (when (< i items) (put-string p "1, ") (loop (+ i 1))))
     (put-string p "1)"))))

;; watched : Database (-> Any) -> (List Any Natural Natural)
;; THUNK under the chosen device: what it answered, or raised as a symbol;
;; the interrupts sent; its milliseconds.
(define (watched db thunk)
  (let* ((handle (call-with-open-handle 'probe db (lambda (h) h)))
         (m (make-mutex)) (c (make-condition))
         (started #f) (done #f) (ended #f) (sent 0) (after-clear 0) (first-clear-ms #f) (t0 #f)
         (by (add-duration (current-time 'time-monotonic) (duration 120000)))
         (past? (lambda () (time>=? (current-time 'time-monotonic) by)))
         (start! (lambda () (with-mutex m (unless started (set! started #t) (condition-broadcast c)))))
         ;; send! counts, besides each send, each one after the first that
         ;; found the flag clear: one sent since the connection's last clear,
         ;; a statement's start or the parser's.
         (send! (lambda ()
                  (let ((clear (eqv? (is-interrupted handle) 0)))
                    (interrupt-database! db)
                    (with-mutex m
                      (when (and clear (> sent 0))
                        (set! after-clear (+ after-clear 1))
                        (unless first-clear-ms (set! first-clear-ms (and t0 (- (real-time) t0)))))
                      (set! sent (+ sent 1))))))
         (stop? (lambda () (or (with-mutex m done) (past?))))
         (watchdog
          (fork-thread
           (lambda ()
             (when (eq? device 'handshake)
               (mutex-enter memory-mutex)
               (send!)
               (start!)
               (let wait ()
                 (unless (stop?)
                   (sleep one-ms)
                   (if (eqv? (is-interrupted handle) 0)
                       (send!)
                       (wait))))
               (mutex-leave memory-mutex))
             (let round ()
               (unless (stop?)
                 (mutex-enter memory-mutex)
                 (start!)
                 (sleep one-ms)
                 (send!)
                 (mutex-leave memory-mutex)
                 (sleep one-ms)
                 (round)))
             (with-mutex m (set! started #t) (set! ended #t) (condition-broadcast c)))))
         (ready (with-mutex m (await m c (lambda () started) 30000)))
         (t00 (with-mutex m (set! t0 (real-time)) t0))
         (r (guard (e ((sqlite-interrupt? e) 'stopped) (#t (list 'raised (if (message-condition? e) (condition-message e) 'no-message))))
              (thunk)))
         (took (- (real-time) t00)))
    (with-mutex m (set! done #t) (await m c (lambda () ended) 120000))
    (thread-join watchdog)
    (list r (with-mutex m sent) took (with-mutex m (list after-clear first-clear-ms)))))

(define (trial)
  (let ((db (open-database ":memory:")))
    (let ((w (watched db (lambda ()
                           (when (> delay-ms 0) (sleep (duration delay-ms)))
                           (prepare-statement db sql)))))
      (let ((r (car w)))
        (unless (symbol? r) (when (not (pair? r)) (finalize-statement! r))))
      (close-database! db)
      (list (if (eq? (car w) 'stopped) 'stopped (if (pair? (car w)) (car w) 'prepared))
            (cadr w) (caddr w) (cons 'after-a-clear (cadddr w))))))

(let loop ((i 1) (stopped 0) (prepared 0))
  (if (> i trials)
      (begin (display (list 'device device 'items items 'delay-ms delay-ms
                            'stopped stopped 'prepared prepared 'of trials))
             (newline))
      (let ((t (trial)))
        (write (cons i t)) (newline)
        (loop (+ i 1)
              (if (eq? (car t) 'stopped) (+ stopped 1) stopped)
              (if (eq? (car t) 'prepared) (+ prepared 1) prepared)))))
