;;; A plain-bound sqlite3_reset blocked in the busy handler: does another
;;; thread's collect hang, or wait out the busy timeout? Effects by let*.
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare-v3 (foreign-procedure "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define step (foreign-procedure "sqlite3_step" (uptr) int))
(define reset-plain (foreign-procedure "sqlite3_reset" (uptr) int))
(define reset-safe (foreign-procedure __collect_safe "sqlite3_reset" (uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define (open name)
  (let* ([cell (foreign-alloc 8)] [rc (open-v2 name cell (logior #x2 #x4 #x02000000) 0)] [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell) db))
(define (prep db text)
  (let* ([bv (string->utf8 text)] [n (bytevector-length bv)] [sql (foreign-alloc (+ n 1))]
         [fill (let loop ([i 0]) (when (< i n) (foreign-set! 'unsigned-8 sql i (bytevector-u8-ref bv i)) (loop (+ i 1))))]
         [nul (foreign-set! 'unsigned-8 sql n 0)] [cell (foreign-alloc 8)]
         [rc (prepare-v3 db sql n 0 cell 0)] [stmt (foreign-ref 'uptr cell 0)])
    (foreign-free cell) (foreign-free sql) stmt))
(define (exec db text) (let* ([st (prep db text)] [s (step st)] [f (finalize st)]) s))
(define (ms) (let ([t (current-time 'time-monotonic)]) (+ (* 1000 (time-second t)) (quotient (time-nanosecond t) 1000000))))
(define (run label reset)
  (let* ([path "build/rev2/tmp-plain.db"]
         [rm (when (file-exists? path) (delete-file path))]
         [db1 (open path)] [db2 (open path)]
         [e1 (exec db1 "create table t (x)")] [e2 (exec db1 "insert into t values (0)")]
         [e3 (exec db1 "pragma busy_timeout = 1500")]
         [rs (prep db2 "select x from t")] [r-step (step rs)]
         [st (prep db1 "insert into t values (1) returning x")] [s (step st)]
         [m (make-mutex)] [cv (make-condition)] [done #f] [answer #f]
         [t0 (ms)]
         [th (fork-thread (lambda () (let ([a (reset st)]) (with-mutex m (set! answer a) (set! done (ms)) (condition-broadcast cv)))))]
         [pause (sleep (make-time 'time-duration 100000000 0))]
         [c0 (ms)] [col (collect-rendezvous)] [c1 (ms)]
         [call-done-before-collect-returned (with-mutex m done)]
         [wait (with-mutex m (let loop () (unless done (condition-wait cv m (make-time 'time-duration 0 5)) (loop))))]
         [f (finalize st)] [rf (finalize rs)] [x1 (close db1)] [x2 (close db2)])
    (printf "~a: reset answered ~s after ~s ms; collect took ~s ms; the call had returned before the collect did: ~s~n"
            label answer (- done t0) (- c1 c0) (and call-done-before-collect-returned #t))))
(run "plain" reset-plain)
(run "collect-safe" reset-safe)
