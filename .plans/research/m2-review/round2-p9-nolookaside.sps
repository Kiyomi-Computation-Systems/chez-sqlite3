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
(define clear-bindings (foreign-procedure "sqlite3_clear_bindings" (uptr) int))
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


(define db-config (foreign-procedure (__varargs_after 2) "sqlite3_db_config" (uptr int uptr int int) int))
(define bind-text64 (foreign-procedure "sqlite3_bind_blob64" (uptr int uptr unsigned-64 iptr) int))
(define column-text-ptr (foreign-procedure "sqlite3_column_blob" (uptr int) uptr))
(define column-bytes (foreign-procedure "sqlite3_column_bytes" (uptr int) int))
(define (read-bytes p n)
  (let loop ([i 0] [acc '()])
    (if (= i n) (reverse acc) (loop (+ i 1) (cons (foreign-ref 'unsigned-8 p i) acc)))))
(let* ([db (open ":memory:")] [la (db-config db 1001 0 0 0)] [lashow (printf "lookaside off rc: ~s~n" la)]
       [p (prep db "select ?1")]
       [st (cadr p)]
       [n 200]
       [blk (foreign-alloc n)]
       [fill (let loop ([i 0]) (when (< i n) (foreign-set! 'unsigned-8 blk i 65) (loop (+ i 1))))]
       [b (bind-text64 st 1 blk n -1)]
       [s (step st)]
       [ptr-before (column-text-ptr st 0)]
       [cl (clear-bindings st)]
       [ptr-after (column-text-ptr st 0)]
       [len (column-bytes st 0)]
       [first (read-bytes ptr-after 4)]
       [f (finalize st)]
       [c (close db)])
  (foreign-free blk)
  (show "Q. bind a 200-byte BLOB, step, clear_bindings in the row state: bind, step, clear rc, same pointer?, bytes, first 4 read after"
        (list b s cl (= ptr-before ptr-after) len first)))
