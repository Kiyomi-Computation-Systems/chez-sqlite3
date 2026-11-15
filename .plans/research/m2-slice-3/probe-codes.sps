;;; M2 slice 3's fourth probe: the codes the subtype rows and prepare's rows
;;; rest on, through bare FFI, on a connection opened with EXRESCODE as
;;; chez-sqlite3's are. Effects ordered by let*.
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define libversion (foreign-procedure "sqlite3_libversion" () string))
(define errmsg (foreign-procedure "sqlite3_errmsg" (uptr) string))
(define extended (foreign-procedure "sqlite3_extended_errcode" (uptr) int))
(define offset (foreign-procedure "sqlite3_error_offset" (uptr) int))
(define prepare (foreign-procedure __collect_safe "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define step (foreign-procedure __collect_safe "sqlite3_step" (uptr) int))
(define reset (foreign-procedure __collect_safe "sqlite3_reset" (uptr) int))
(define finalize (foreign-procedure __collect_safe "sqlite3_finalize" (uptr) int))
(define column-text (foreign-procedure "sqlite3_column_text" (uptr int) string))
(define param-count (foreign-procedure "sqlite3_bind_parameter_count" (uptr) int))
(define column-count (foreign-procedure "sqlite3_column_count" (uptr) int))

(define (open name flags)
  (let* ([cell (foreign-alloc 8)]
         [rc (open-v2 name cell (logior flags #x02000000) 0)]
         [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (unless (= rc 0) (error 'probe "open failed" rc))
    db))
;; prep : Integer Bytevector -> (List rc stmt tail-offset)
(define (prep* db bv)
  (let* ([n (bytevector-length bv)] [p (foreign-alloc (+ n 1))]
         [fill (let loop ([i 0]) (when (< i n) (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bv i)) (loop (+ i 1))))]
         [nul (foreign-set! 'unsigned-8 p n 0)]
         [cell (foreign-alloc 8)] [tail (foreign-alloc 8)] [z (foreign-set! 'uptr cell 0 0)]
         [rc (prepare db p (+ n 1) 0 cell tail)] [st (foreign-ref 'uptr cell 0)]
         [t (- (foreign-ref 'uptr tail 0) p)])
    (foreign-free cell) (foreign-free tail) (foreign-free p) (list rc st t)))
(define (prep db text) (cadr (prep* db (string->utf8 text))))
(define (exec db text) (let* ([st (prep db text)] [s (step st)] [f (finalize st)]) (list s f)))
(define (show label v) (printf "~a: ~s~n" label v))
(define path "build/m2s3/codes.db")
(define (fresh!)
  (for-each (lambda (p) (when (file-exists? p) (delete-file p))) (list path (string-append path "-journal")))
  (let* ([db (open path 6)] [a (exec db "create table t (x unique)")] [b (exec db "insert into t values (0)")]) (close db)))

(show "libversion" (libversion))

(let* ([f (fresh!)] [db (open path 6)]
       [st (prep db "insert into t values (0)")]
       [s (step st)] [x (extended db)] [m (errmsg db)] [r1 (reset st)] [r2 (reset st)] [fi (finalize st)]
       [c (close db)])
  (show "constraint: step, extended_errcode, message, reset, reset again, finalize" (list s x m r1 r2 fi)))

(let* ([f (fresh!)] [db (open path 1)]
       [p (prep* db (string->utf8 "insert into t values (1)"))]
       [st (cadr p)]
       [s (step st)] [x (extended db)] [m (errmsg db)] [fi (finalize st)] [c (close db)])
  (show "read-only: prepare rc, step, extended_errcode, message, finalize" (list (car p) s x m fi)))

(let* ([f (fresh!)] [db1 (open path 6)] [db2 (open path 6)]
       [rs (prep db2 "select x from t")] [r (step rs)]
       [st (prep db1 "insert into t values (5)")]
       [s (step st)] [x (extended db1)] [m (errmsg db1)] [fi (finalize st)]
       [rf (finalize rs)] [c1 (close db1)] [c2 (close db2)])
  (show "a plain insert under another's read, no busy timeout: reader's step, step, extended_errcode, message, finalize" (list r s x m fi)))

(let* ([f (fresh!)] [db1 (open path 6)] [db2 (open path 6)]
       [rs (prep db2 "select x from t")] [r (step rs)]
       [st (prep db1 "insert into t values (5), (6) returning x")]
       [s (step st)] [rr (reset st)] [x (extended db1)] [m (errmsg db1)] [rr2 (reset st)] [fi (finalize st)]
       [rf (finalize rs)] [c1 (close db1)] [c2 (close db2)])
  (show "insert ... returning stepped once under a read, no busy timeout: step, reset, extended_errcode, message, reset again, finalize" (list s rr x m rr2 fi)))

(let* ([db (open ":memory:" 6)])
  (for-each
   (lambda (sql)
     (let* ([p (prep* db (string->utf8 sql))] [x (extended db)] [o (offset db)] [m (errmsg db)])
       (unless (= (cadr p) 0) (finalize (cadr p)))
       (show "prepare: sql, rc, null?, extended_errcode, offset, message"
             (list sql (car p) (= (cadr p) 0) x o m))))
   '("select 'a' < 'b' collate no_such_collation" "select 1, nosuchcol" "select 'é', nosuchcol"
     "selectx 1" "select 1 +" "select (" "select é," "select 'éé' from nosuchtable"))
  (for-each
   (lambda (sql)
     (let* ([st (prep db sql)] [pc (param-count st)] [cc (column-count st)] [f (finalize st)])
       (show "parameter count, column count" (list sql pc cc))))
   '("select 1" "select ?, ?" "select :a, ?7, $b" "select 1, 2, 3" "create table u (a, b)"))
  (close db))
