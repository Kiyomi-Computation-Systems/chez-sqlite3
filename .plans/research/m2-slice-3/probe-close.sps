;;; M2 slice 3's second probe: what can make sqlite3_close fail once every
;;; statement is finalized. SQLite's documentation names three holders:
;;; unfinalized statements, unfinished backups and open BLOB handles. M2
;;; binds neither of the last two, so a suite binds sqlite3_backup_init
;;; itself, as test-connection does. Measured:
;;;   A. a backup reading from the connection, no statement: close's answer
;;;   B. an insert ... returning stepped once under another connection's read,
;;;      and a backup from the same connection: finalize's answer, then
;;;      close's, then close's once the backup is finished
;;;   C. two such inserts, finalized oldest first, then newest first: which
;;;      finalize answers BUSY, and the rows left
;;; Effects ordered by let*.
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define libversion (foreign-procedure "sqlite3_libversion" () string))
(define prepare (foreign-procedure __collect_safe "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define step (foreign-procedure __collect_safe "sqlite3_step" (uptr) int))
(define finalize (foreign-procedure __collect_safe "sqlite3_finalize" (uptr) int))
(define next-stmt (foreign-procedure "sqlite3_next_stmt" (uptr uptr) uptr))
(define backup-init (foreign-procedure "sqlite3_backup_init" (uptr string uptr string) uptr))
(define backup-finish (foreign-procedure "sqlite3_backup_finish" (uptr) int))
(define column-int (foreign-procedure "sqlite3_column_int" (uptr int) int))

(define (open name)
  (let* ([cell (foreign-alloc 8)]
         [rc (open-v2 name cell (logior #x2 #x4 #x02000000) 0)]
         [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (unless (= rc 0) (error 'probe "open failed" rc))
    db))
(define (prep db text)
  (let* ([bv (string->utf8 text)] [n (bytevector-length bv)] [p (foreign-alloc (+ n 1))]
         [fill (let loop ([i 0]) (when (< i n) (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bv i)) (loop (+ i 1))))]
         [nul (foreign-set! 'unsigned-8 p n 0)]
         [cell (foreign-alloc 8)] [z (foreign-set! 'uptr cell 0 0)]
         [rc (prepare db p (+ n 1) 0 cell 0)] [st (foreign-ref 'uptr cell 0)])
    (foreign-free cell) (foreign-free p) st))
(define (exec db text) (let* ([st (prep db text)] [s (step st)] [f (finalize st)]) (list s f)))
(define (count db) (let* ([st (prep db "select count(*) from t")] [s (step st)] [n (column-int st 0)] [f (finalize st)]) n))
(define (show label v) (printf "~a: ~s~n" label v))
(define path "build/m2s3/close.db")
(define (fresh!)
  (for-each (lambda (p) (when (file-exists? p) (delete-file p))) (list path (string-append path "-journal")))
  (let* ([db (open path)] [a (exec db "create table t (x)")] [b (exec db "insert into t values (0)")]) (close db)))

(show "libversion" (libversion))

(let* ([src (open ":memory:")] [dst (open ":memory:")]
       [b (backup-init dst "main" src "main")]
       [c (close src)] [stmts (next-stmt src 0)]
       [f (backup-finish b)] [c2 (close src)] [c3 (close dst)])
  (show "A. a backup reads from the connection, no statement: close, statements found, backup_finish, close again, the other's close"
        (list c stmts f c2 c3)))

(let* ([fr (fresh!)] [db1 (open path)] [db2 (open path)]
       [rs (prep db2 "select x from t")] [r (step rs)]
       [st (prep db1 "insert into t values (1), (2) returning x")] [s (step st)]
       [dst (open ":memory:")]
       [b (backup-init dst "main" db1 "main")]
       [fin (finalize st)] [stmts (next-stmt db1 0)]
       [c (close db1)]
       [bf (backup-finish b)] [c2 (close db1)]
       [frs (finalize rs)] [n (count db2)] [c3 (close db2)] [c4 (close dst)])
  (show "B. insert ... returning stepped once under a read, and a backup from it: backup made?, finalize, statements found, close, backup_finish, close again, rows after"
        (list (if (eqv? b 0) 'no-backup 'backup) fin stmts c bf c2 n)))

(define (two order)
  (let* ([fr (fresh!)] [db1 (open path)] [db2 (open path)]
         [rs (prep db2 "select x from t")] [r (step rs)]
         [a (prep db1 "insert into t values (1) returning 'a'")] [sa (step a)]
         [b (prep db1 "insert into t values (2) returning 'b'")] [sb (step b)]
         [first (if (eq? order 'oldest-first) a b)] [second (if (eq? order 'oldest-first) b a)]
         [f1 (finalize first)] [f2 (finalize second)]
         [frs (finalize rs)] [n (count db2)] [c1 (close db1)] [c2 (close db2)])
    (show (format "C. two inserts stepped once under a read, finalized ~a: steps, first finalize, second, rows after" order)
          (list sa sb f1 f2 n))))
(two 'oldest-first)
(two 'newest-first)
