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
(define column-text-ptr (foreign-procedure "sqlite3_column_text" (uptr int) uptr))
(define column-bytes (foreign-procedure "sqlite3_column_bytes" (uptr int) int))
(define (read-text st i)
  (let* ([p (column-text-ptr st i)] [n (column-bytes st i)] [bv (make-bytevector n)])
    (let loop ([k 0]) (when (< k n) (bytevector-u8-set! bv k (foreign-ref 'unsigned-8 p k)) (loop (+ k 1))))
    (utf8->string bv)))
(define (one db sql)
  (let* ([p (prep db sql)] [st (cadr p)] [s (step st)] [v (read-text st 0)] [f (finalize st)]) v))
;; prepare-only: compile SQL, never step it, finalize it.
(define (prepare-only db sql)
  (let* ([p (prep db sql)] [f (if (= (cadr p) 0) 'none (finalize (cadr p)))]) (list (car p) (not (= (cadr p) 0)))))
(let* ([db (open ":memory:")]
       [cache-before (one db "pragma cache_size")]
       [enc-before (one db "pragma encoding")]
       [like-before (one db "select 'a' like 'A'")]
       [p1 (prepare-only db "pragma cache_size = 7")]
       [p2 (prepare-only db "pragma encoding = 'UTF-16le'")]
       [p3 (prepare-only db "pragma case_sensitive_like = 1")]
       [cache-after (one db "pragma cache_size")]
       [enc-after (one db "pragma encoding")]
       [like-after (one db "select 'a' like 'A'")]
       [c (close db)])
  (show "P. prepared, never stepped: cache_size before/after, encoding before/after, 'a' like 'A' before/after"
        (list (list cache-before cache-after) (list enc-before enc-after) (list like-before like-after) p1 p2 p3)))
