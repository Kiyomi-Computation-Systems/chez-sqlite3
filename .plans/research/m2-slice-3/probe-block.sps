;;; M2 slice 3's first probe: each of the four calls that can block, made to
;;; block by a second connection's lock and busy_timeout = 1500, bound plain
;;; and bound __collect_safe. For each: the call's answer and how long it took,
;;; and how long another thread's collect-rendezvous took, started 100 ms into
;;; the block, and whether the call had returned before the collection did.
;;; Effects ordered by let*.
;;;
;;;   scripts/guix-env sh -c '$CHEZ --script build/m2s3/probe-block.sps'
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define libversion (foreign-procedure "sqlite3_libversion" () string))
(define errmsg (foreign-procedure "sqlite3_errmsg" (uptr) string))
(define prepare-plain (foreign-procedure "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define prepare-safe (foreign-procedure __collect_safe "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define step-plain (foreign-procedure "sqlite3_step" (uptr) int))
(define step-safe (foreign-procedure __collect_safe "sqlite3_step" (uptr) int))
(define reset-plain (foreign-procedure "sqlite3_reset" (uptr) int))
(define reset-safe (foreign-procedure __collect_safe "sqlite3_reset" (uptr) int))
(define finalize-plain (foreign-procedure "sqlite3_finalize" (uptr) int))
(define finalize-safe (foreign-procedure __collect_safe "sqlite3_finalize" (uptr) int))
(define step step-safe)
(define finalize finalize-safe)

(define (open name)
  (let* ([cell (foreign-alloc 8)]
         [rc (open-v2 name cell (logior #x2 #x4 #x02000000) 0)]
         [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (unless (= rc 0) (error 'probe "open failed" rc))
    db))
(define (c-string text)
  (let* ([bv (string->utf8 text)] [n (bytevector-length bv)] [p (foreign-alloc (+ n 1))])
    (let loop ([i 0]) (when (< i n) (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bv i)) (loop (+ i 1))))
    (foreign-set! 'unsigned-8 p n 0)
    (cons p (+ n 1))))
;; prep-with : Procedure Integer String -> (List rc stmt)
(define (prep-with prepare db text)
  (let* ([s (c-string text)] [cell (foreign-alloc 8)]
         [z (foreign-set! 'uptr cell 0 0)]
         [rc (prepare db (car s) (cdr s) 0 cell 0)]
         [st (foreign-ref 'uptr cell 0)])
    (foreign-free cell) (foreign-free (car s))
    (list rc st)))
(define (prep db text) (cadr (prep-with prepare-safe db text)))
(define (exec db text) (let* ([st (prep db text)] [s (step st)] [f (finalize st)]) (list s f)))
(define (ms) (let ([t (current-time 'time-monotonic)]) (+ (* 1000 (time-second t)) (quotient (time-nanosecond t) 1000000))))

;; blocked : (-> Integer) -> (List answer call-ms collect-ms returned-first?)
;; CALL run on a forked thread; 100 ms in, this thread's collect-rendezvous.
(define (blocked call)
  (let* ([m (make-mutex)] [cv (make-condition)] [done #f] [answer #f]
         [t0 (ms)]
         [th (fork-thread (lambda () (let ([a (call)]) (with-mutex m (set! answer a) (set! done (ms)) (condition-broadcast cv)))))]
         [pause (sleep (make-time 'time-duration 100000000 0))]
         [c0 (ms)] [col (collect-rendezvous)] [c1 (ms)]
         [returned-first (with-mutex m (and done #t))]
         [wait (with-mutex m (let loop () (unless done (condition-wait cv m (make-time 'time-duration 0 5)) (loop))))])
    (list answer (- done t0) (- c1 c0) returned-first)))

(define path "build/m2s3/block.db")
(define (fresh!)
  (for-each (lambda (p) (when (file-exists? p) (delete-file p)))
            (list path (string-append path "-journal")))
  (let* ([db (open path)] [a (exec db "create table t (x)")] [b (exec db "insert into t values (0)")] [c (close db)]) c))

(define (show label v) (printf "~a: ~s~n" label v))
(show "libversion" (libversion))

;; step: a plain insert, under another connection's read.
(define (step-run label step-fn)
  (let* ([f (fresh!)] [db1 (open path)] [db2 (open path)]
         [bt (exec db1 "pragma busy_timeout = 1500")]
         [rs (prep db2 "select x from t")] [r (step rs)]
         [st (prep db1 "insert into t values (1)")]
         [result (blocked (lambda () (step-fn st)))]
         [msg (errmsg db1)]
         [fs (finalize st)] [fr (finalize rs)]
         [count-st (prep db1 "select count(*) from t")]
         [cs (step count-st)]
         [n ((foreign-procedure "sqlite3_column_int" (uptr int) int) count-st 0)]
         [fc (finalize count-st)]
         [c1 (close db1)] [c2 (close db2)])
    (show (format "step, ~a: answer, ms, collect ms, the call returned before the collect did; message; finalize after; rows after" label)
          (list result msg fs n))))
(step-run "plain" step-plain)
(step-run "collect-safe" step-safe)

;; prepare: a fresh connection, under another's begin exclusive.
(define (prepare-run label prepare)
  (let* ([f (fresh!)] [db1 (open path)] [db2 (open path)]
         [bt (exec db2 "pragma busy_timeout = 1500")]
         [ex (exec db1 "begin exclusive")]
         [result (blocked (lambda () (car (prep-with prepare db2 "select x from t"))))]
         [msg (errmsg db2)]
         [cm (exec db1 "commit")]
         [c1 (close db1)] [c2 (close db2)])
    (show (format "prepare, ~a: answer, ms, collect ms, returned first; message" label) (list result msg))))
(prepare-run "plain" prepare-plain)
(prepare-run "collect-safe" prepare-safe)

;; reset and finalize: an insert ... returning stepped once, under a read.
(define (finish-run label verb fn)
  (let* ([f (fresh!)] [db1 (open path)] [db2 (open path)]
         [bt (exec db1 "pragma busy_timeout = 1500")]
         [rs (prep db2 "select x from t")] [r (step rs)]
         [st (prep db1 "insert into t values (1), (2) returning x")]
         [s (step st)]
         [result (blocked (lambda () (fn st)))]
         [msg (errmsg db1)]
         [after (if (eq? verb 'reset) (finalize st) 'freed)]
         [fr (finalize rs)]
         [c1 (close db1)] [c2 (close db2)])
    (show (format "~a, ~a: first step; answer, ms, collect ms, returned first; message; finalize after a reset" verb label)
          (list s result msg after))))
(finish-run "plain" 'reset reset-plain)
(finish-run "collect-safe" 'reset reset-safe)
(finish-run "plain" 'finalize finalize-plain)
(finish-run "collect-safe" 'finalize finalize-safe)
