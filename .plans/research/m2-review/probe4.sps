;;; Reviewer's third probe: can sqlite3_reset or sqlite3_finalize wait in the
;;; busy handler? Effects ordered by let*.
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare-v3 (foreign-procedure "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define step (foreign-procedure __collect_safe "sqlite3_step" (uptr) int))
(define reset (foreign-procedure "sqlite3_reset" (uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define column-count (foreign-procedure "sqlite3_column_count" (uptr) int))
(define libversion (foreign-procedure "sqlite3_libversion" () string))
(define EXRESCODE #x02000000)
(define (open name)
  (let* ([cell (foreign-alloc 8)]
         [rc (open-v2 name cell (logior #x2 #x4 EXRESCODE) 0)]
         [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (unless (= rc 0) (error 'probe "open failed" rc))
    db))
(define (prep db text)
  (let* ([bv (string->utf8 text)]
         [n (bytevector-length bv)]
         [sql (foreign-alloc (+ n 1))]
         [fill (let loop ([i 0]) (when (< i n) (foreign-set! 'unsigned-8 sql i (bytevector-u8-ref bv i)) (loop (+ i 1))))]
         [nul (foreign-set! 'unsigned-8 sql n 0)]
         [cell (foreign-alloc 8)]
         [rc (prepare-v3 db sql n 0 cell 0)]
         [stmt (foreign-ref 'uptr cell 0)])
    (foreign-free cell) (foreign-free sql)
    (list rc stmt)))
(define (exec db text)
  (let* ([p (prep db text)]
         [s (if (= (cadr p) 0) 'none (step (cadr p)))]
         [f (if (= (cadr p) 0) 'none (finalize (cadr p)))])
    (list (car p) s f)))
(define (show label value) (printf "~a: ~s~n" label value))
(define (ms) (let ([t (current-time 'time-monotonic)]) (+ (* 1000 (time-second t)) (quotient (time-nanosecond t) 1000000))))
(show "libversion" (libversion))

;; One run: VERB is reset or finalize, applied to an INSERT ... RETURNING
;; stepped once, while a second connection holds a read.
(define (run label verb)
  (let* ([path "build/review/tmp-busy.db"]
         [rm (when (file-exists? path) (delete-file path))]
         [db1 (open path)]
         [db2 (open path)]
         [e1 (exec db1 "create table t (x)")]
         [e2 (exec db1 "insert into t values (0)")]
         [e3 (exec db1 "pragma busy_timeout = 1500")]
         [r (prep db2 "select x from t")]
         [rs (cadr r)]
         [r-step (step rs)]
         [p (prep db1 "insert into t values (1), (2) returning x")]
         [st (cadr p)]
         [s (step st)]
         [t0 (ms)]
         [answer (verb st)]
         [t1 (ms)]
         [after (if (eq? label 'reset) (finalize st) 'n/a)]
         [rf (finalize rs)]
         [c1 (close db1)]
         [c2 (close db2)])
    (show (format "~a of an INSERT ... RETURNING after one step (100 ROW), a reader holding a read lock: first step, answer, elapsed ms" label)
          (list r-step s answer (- t1 t0)))))
(run 'reset reset)
(run 'finalize finalize)

;; N. Column count after another connection drops a column.
(let* ([path "build/review/tmp-n.db"]
       [rm (when (file-exists? path) (delete-file path))]
       [db1 (open path)]
       [db2 (open path)]
       [e1 (exec db1 "create table t (a, b)")]
       [e2 (exec db1 "insert into t values (1, 2)")]
       [p (prep db1 "select * from t")]
       [st (cadr p)]
       [before (column-count st)]
       [e3 (exec db2 "alter table t drop column b")]
       [s (step st)]
       [after (column-count st)]
       [f (finalize st)]
       [c1 (close db1)]
       [c2 (close db2)])
  (show "N. column_count before, step rc, after another connection drops a column" (list e3 before s after)))
