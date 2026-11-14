;;; Two INSERT ... RETURNING statements, each stepped once, on one connection,
;;; under another's read: what does each finalize answer, in each order?
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare-v3 (foreign-procedure "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define step (foreign-procedure "sqlite3_step" (uptr) int))
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
(define (exec db text) (let* ([st (prep db text)] [s (step st)] [f (finalize st)]) (list s f)))
(define (run reader?)
  (let* ([path "build/rev2/tmp-two.db"]
         [rm (when (file-exists? path) (delete-file path))]
         [db1 (open path)] [db2 (open path)]
         [e1 (exec db1 "create table t (x)")]
         [rs (prep db2 "select count(*) from sqlite_schema")] [r-step (if reader? (step rs) 'none)]
         [a (prep db1 "insert into t values (1) returning x")] [sa (step a)]
         [b (prep db1 "insert into t values (2) returning x")] [sb (step b)]
         [fa (finalize a)]
         [fb (finalize b)]
         [rf (finalize rs)]
         [x1 (close db1)] [x2 (close db2)])
    (printf "reader ~s: steps ~s ~s; finalize first ~s, finalize second ~s~n" reader? sa sb fa fb)))
(run #t)
(run #f)
