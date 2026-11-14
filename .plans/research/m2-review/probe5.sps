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


(define column-int64 (foreign-procedure "sqlite3_column_int64" (uptr int) integer-64))
(define (count-rows db)
  (let* ([p (prep db "select count(*) from t")]
         [s (step (cadr p))]
         [n (column-int64 (cadr p) 0)]
         [f (finalize (cadr p))])
    n))
(define (run label verb contended)
  (let* ([path "build/review/tmp-busy2.db"]
         [rm (when (file-exists? path) (delete-file path))]
         [db1 (open path)]
         [db2 (open path)]
         [e1 (exec db1 "create table t (x)")]
         [e2 (exec db1 "insert into t values (0)")]
         [r (prep db2 "select x from t")]
         [rs (cadr r)]
         [r-step (if contended (step rs) 'no-reader)]
         [p (prep db1 "insert into t values (1), (2) returning x")]
         [st (cadr p)]
         [s (step st)]
         [answer (verb st)]
         [after (if (eq? label 'reset) (finalize st) 'n/a)]
         [rf (finalize rs)]
         [rows (count-rows db1)]
         [c1 (close db1)]
         [c2 (close db2)])
    (show (format "~a, reader ~a: step, answer, rows in t after (1 before, 3 if the insert stood)" label contended)
          (list s answer rows))))
(run 'reset reset #t)
(run 'finalize finalize #t)
(run 'reset reset #f)
(run 'finalize finalize #f)
