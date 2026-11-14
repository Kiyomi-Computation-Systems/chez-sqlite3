;;; Reviewer's second probe. Effects ordered by let* and named loops.
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare-v3 (foreign-procedure "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define step (foreign-procedure __collect_safe "sqlite3_step" (uptr) int))
(define reset (foreign-procedure "sqlite3_reset" (uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define bind-text64 (foreign-procedure "sqlite3_bind_text64" (uptr int uptr unsigned-64 iptr unsigned-8) int))
(define column-type (foreign-procedure "sqlite3_column_type" (uptr int) int))
(define column-count (foreign-procedure "sqlite3_column_count" (uptr) int))
(define column-int64 (foreign-procedure "sqlite3_column_int64" (uptr int) integer-64))
(define column-text-ptr (foreign-procedure "sqlite3_column_text" (uptr int) uptr))
(define column-blob-ptr (foreign-procedure "sqlite3_column_blob" (uptr int) uptr))
(define column-bytes (foreign-procedure "sqlite3_column_bytes" (uptr int) int))
(define limit (foreign-procedure "sqlite3_limit" (uptr int int) int))
(define libversion (foreign-procedure "sqlite3_libversion" () string))
(define EXRESCODE #x02000000)
(define TRANSIENT -1)
(define (open name)
  (let* ([cell (foreign-alloc 8)]
         [rc (open-v2 name cell (logior #x2 #x4 EXRESCODE) 0)]
         [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (unless (= rc 0) (error 'probe "open failed" rc))
    db))
(define (bytes->block bv)
  (let ([p (foreign-alloc (+ 1 (bytevector-length bv)))])
    (let loop ([i 0])
      (when (< i (bytevector-length bv))
        (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bv i))
        (loop (+ i 1))))
    (foreign-set! 'unsigned-8 p (bytevector-length bv) 0)
    p))
(define (prep db text)
  (let* ([bv (string->utf8 text)]
         [sql (bytes->block bv)]
         [cell (foreign-alloc 8)]
         [tail (foreign-alloc 8)]
         [rc (prepare-v3 db sql (bytevector-length bv) 0 cell tail)]
         [stmt (foreign-ref 'uptr cell 0)])
    (foreign-free cell) (foreign-free tail) (foreign-free sql)
    (list rc stmt)))
(define (exec db text)
  (let* ([p (prep db text)]
         [s (if (= (cadr p) 0) 'none (step (cadr p)))]
         [f (if (= (cadr p) 0) 'none (finalize (cadr p)))])
    (list (car p) s f)))
(define (show label value) (printf "~a: ~s~n" label value))
(define (read-bytes p n)
  (let loop ([i 0] [acc '()])
    (if (= i n) (reverse acc) (loop (+ i 1) (cons (foreign-ref 'unsigned-8 p i) acc)))))
(show "libversion" (libversion))

;; H. UTF-16 database, blob read first.
(let* ([db (open ":memory:")]
       [e1 (exec db "pragma encoding = 'UTF-16le'")]
       [e2 (exec db "create table u (x)")]
       [e3 (exec db "insert into u values ('é')")]
       [p (prep db "select x from u")]
       [st (cadr p)]
       [s (step st)]
       [bp (column-blob-ptr st 0)]
       [bn (column-bytes st 0)]
       [bb (read-bytes bp bn)]
       [f (finalize st)]
       [c (close db)])
  (show "H. UTF-16 db, column_blob first on 'é': bytes" bb))

;; I. NaN payloads and eqv?.
(define (nan-of bits) (let ([bv (make-bytevector 8)]) (bytevector-u64-set! bv 0 bits (endianness big)) (bytevector-ieee-double-ref bv 0 (endianness big))))
(let* ([a (nan-of #x7FF8000000000000)]
       [b (nan-of #x7FF0000000000001)]
       [c (nan-of #xFFF8000000000001)])
  (show "I. eqv? +nan.0 with 7FF8..0, 7FF0..1, FFF8..1; nan? of each"
        (list (eqv? +nan.0 a) (eqv? +nan.0 b) (eqv? +nan.0 c) (nan? a) (nan? b) (nan? c)))
  (show "I. equal? / = / fl=?" (list (equal? +nan.0 a) (= +nan.0 +nan.0) (memv a (list +nan.0)))))

;; J. A refused bind at the limit: what the parameter holds after.
(let* ([db (open ":memory:")]
       [old (limit db 0 10)]
       [now (limit db 0 -1)]
       [p (prep db "select typeof(?1), ?1")]
       [st (cadr p)]
       [short (bytes->block (string->utf8 "old"))]
       [long (bytes->block (make-bytevector 100 65))]
       [b1 (bind-text64 st 1 short 3 TRANSIENT 1)]
       [b2 (bind-text64 st 1 long 100 TRANSIENT 1)]
       [s (step st)]
       [ty (read-bytes (column-text-ptr st 0) (column-bytes st 0))]
       [n (column-bytes st 1)]
       [f (finalize st)]
       [c (close db)])
  (foreign-free short) (foreign-free long)
  (show "J. limit was, is; bind 'old', bind 100 bytes, step; typeof, bytes"
        (list old now b1 b2 s (utf8->string (u8-list->bytevector ty)) n)))

;; K. What Chez raises for an integer-64 argument out of its range.
(let* ([f (foreign-procedure "llabs" (integer-64) integer-64)]
       [e (guard (e (#t e)) (f (expt 2 64)))])
  (show "K. assertion-violation? error? message" (list (assertion-violation? e) (error? e) (and (message-condition? e) (condition-message e)))))

;; L. Interrupts inside a handler for a raise from inside critical-section.
(let* ([outside (let ([n (disable-interrupts)]) (enable-interrupts) n)]
       [inside (with-exception-handler
                (lambda (c) (let ([n (disable-interrupts)]) (enable-interrupts) n))
                (lambda () (critical-section (raise-continuable 'x))))])
  (show "L. disable count probed outside, and in a handler of a raise inside critical-section" (list outside inside)))

;; M. Column count after another connection changes the schema.
(let* ([path "build/review/tmp-m.db"]
       [rm (when (file-exists? path) (delete-file path))]
       [db1 (open path)]
       [db2 (open path)]
       [e1 (exec db1 "create table t (a)")]
       [e2 (exec db1 "insert into t values (1)")]
       [p (prep db1 "select * from t")]
       [st (cadr p)]
       [before (column-count st)]
       [e3 (exec db2 "alter table t add column b")]
       [s (step st)]
       [after (column-count st)]
       [f (finalize st)]
       [c1 (close db1)]
       [c2 (close db2)])
  (show "M. column_count before, step rc, column_count after another connection adds a column" (list before s after)))
