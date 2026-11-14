;;; Reviewer's probe. Every effect ordered by let* or named loops; no map
;;; or argument order carries an effect.
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare-v3 (foreign-procedure "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define step (foreign-procedure "sqlite3_step" (uptr) int))
(define reset (foreign-procedure "sqlite3_reset" (uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define bind-text (foreign-procedure "sqlite3_bind_text" (uptr int uptr int iptr) int))
(define bind-text64 (foreign-procedure "sqlite3_bind_text64" (uptr int uptr unsigned-64 iptr unsigned-8) int))
(define bind-double (foreign-procedure "sqlite3_bind_double" (uptr int double) int))
(define bind-int64 (foreign-procedure "sqlite3_bind_int64" (uptr int integer-64) int))
(define column-type (foreign-procedure "sqlite3_column_type" (uptr int) int))
(define column-count (foreign-procedure "sqlite3_column_count" (uptr) int))
(define column-int64 (foreign-procedure "sqlite3_column_int64" (uptr int) integer-64))
(define column-text-ptr (foreign-procedure "sqlite3_column_text" (uptr int) uptr))
(define column-blob-ptr (foreign-procedure "sqlite3_column_blob" (uptr int) uptr))
(define column-bytes (foreign-procedure "sqlite3_column_bytes" (uptr int) int))
(define errcode (foreign-procedure "sqlite3_errcode" (uptr) int))
(define error-offset (foreign-procedure "sqlite3_error_offset" (uptr) int))
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

(define (prepare db bv)
  (let* ([sql (bytes->block bv)]
         [cell (foreign-alloc 8)]
         [tail (foreign-alloc 8)]
         [z1 (foreign-set! 'uptr cell 0 0)]
         [z2 (foreign-set! 'uptr tail 0 0)]
         [rc (prepare-v3 db sql (bytevector-length bv) 0 cell tail)]
         [stmt (foreign-ref 'uptr cell 0)]
         [rest (- (foreign-ref 'uptr tail 0) sql)])
    (foreign-free cell)
    (foreign-free tail)
    (foreign-free sql)
    (list rc stmt rest)))
(define (prep db text) (prepare db (string->utf8 text)))
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

;; A. Tails that hold only semicolons, or a second statement after an empty one.
(let* ([db (open ":memory:")]
       [cases '(";" " ; select 2" "select 1;;" ";;")]
       [results (let loop ([cs cases] [acc '()])
                  (if (null? cs) (reverse acc)
                      (let* ([p (prep db (car cs))]
                             [f (if (= (cadr p) 0) 'none (finalize (cadr p)))])
                        (loop (cdr cs) (cons (list (car cs) 'rc (car p) 'null? (= (cadr p) 0) 'tail (caddr p)) acc)))))]
       [c (close db)])
  (for-each (lambda (r) (show "A. prepare" r)) results))

;; B. column_blob on an empty TEXT, and on a TEXT; errcode after a ROW.
(let* ([db (open ":memory:")]
       [p (prep db "select '', 'ab', x''")]
       [st (cadr p)]
       [s (step st)]
       [ec (errcode db)]
       [b0 (column-blob-ptr st 0)]
       [n0 (column-bytes st 0)]
       [t0 (column-type st 0)]
       [b1 (column-blob-ptr st 1)]
       [n1 (column-bytes st 1)]
       [f (finalize st)]
       [c (close db)])
  (show "B. step rc, errcode right after it" (list s ec))
  (show "B. column_blob on '' (TEXT): type, null?, bytes" (list t0 (= b0 0) n0))
  (show "B. column_blob on 'ab' (TEXT): null?, bytes" (list (= b1 0) n1)))

;; C. Chez's integer-64 and int at their edges, through sqlite3_bind_int64 and select ?.
(define (round-trip-int64 v)
  (let* ([db (open ":memory:")]
         [p (prep db "select ?")]
         [st (cadr p)]
         [b (guard (e (#t (list 'raised (condition-message e)))) (bind-int64 st 1 v))]
         [s (step st)]
         [back (column-int64 st 0)]
         [f (finalize st)]
         [c (close db)])
    (list v 'bind b 'back back)))
(show "C. 2^63-1" (round-trip-int64 (- (expt 2 63) 1)))
(show "C. 2^63" (round-trip-int64 (expt 2 63)))
(show "C. 2^64-1" (round-trip-int64 (- (expt 2 64) 1)))
(show "C. 2^64" (round-trip-int64 (expt 2 64)))
(show "C. -2^63-1" (round-trip-int64 (- (- (expt 2 63)) 1)))

;; D. NaNs: Chez's view, and what SQLite stores for each.
(define neg-nan (fl/ 0.0 0.0))
(define (bits x) (let ([bv (make-bytevector 8)]) (bytevector-ieee-double-set! bv 0 x (endianness big)) (bytevector-u64-ref bv 0 (endianness big))))
(show "D. bits of +nan.0, of (fl/ 0.0 0.0), of (fl- +nan.0)" (list (number->string (bits +nan.0) 16) (number->string (bits neg-nan) 16) (number->string (bits (fl- +nan.0)) 16)))
(show "D. eqv? +nan.0 (fl/ 0.0 0.0); eqv? +nan.0 (fl- +nan.0); nan? of each" (list (eqv? +nan.0 neg-nan) (eqv? +nan.0 (fl- +nan.0)) (nan? neg-nan) (nan? (fl- +nan.0))))
(let* ([db (open ":memory:")]
       [p (prep db "select typeof(?)")]
       [st (cadr p)]
       [b (bind-double st 1 neg-nan)]
       [s (step st)]
       [ty (read-bytes (column-text-ptr st 0) (column-bytes st 0))]
       [f (finalize st)]
       [c (close db)])
  (show "D. bind (fl/ 0.0 0.0): rc, typeof" (list b (utf8->string (u8-list->bytevector ty)))))

;; E. A bind SQLite refuses keeps the value bound before it.
(let* ([db (open ":memory:")]
       [old (limit db 0 10)]
       [p (prep db "select ?")]
       [st (cadr p)]
       [short (bytes->block (string->utf8 "old"))]
       [long (bytes->block (string->utf8 "a value longer than ten bytes"))]
       [b1 (bind-text64 st 1 short 3 TRANSIENT 1)]
       [b2 (bind-text64 st 1 long 29 TRANSIENT 1)]
       [s (step st)]
       [v (read-bytes (column-text-ptr st 0) (column-bytes st 0))]
       [f (finalize st)]
       [c (close db)])
  (foreign-free short)
  (foreign-free long)
  (show "E. limit length 10: bind 'old' rc, bind 29 bytes rc (18 TOOBIG), step rc, value read" (list b1 b2 s (utf8->string (u8-list->bytevector v)))))

;; F. Error offsets: incomplete input, and an error at the very end.
(let* ([db (open ":memory:")]
       [cases '("select (" "select 1 +" "select é," "selectx")]
       [results (let loop ([cs cases] [acc '()])
                  (if (null? cs) (reverse acc)
                      (let* ([p (prep db (car cs))]
                             [off (error-offset db)]
                             [f (if (= (cadr p) 0) 'none (finalize (cadr p)))])
                        (loop (cdr cs) (cons (list (car cs) 'bytes (bytevector-length (string->utf8 (car cs))) 'rc (car p) 'offset off) acc)))))]
       [c (close db)])
  (for-each (lambda (r) (show "F. prepare" r)) results))

;; G. A UTF-16 database: column_text converts; column_blob gives UTF-16 bytes.
(let* ([db (open ":memory:")]
       [e1 (exec db "pragma encoding = 'UTF-16le'")]
       [e2 (exec db "create table u (x)")]
       [e3 (exec db "insert into u values ('é'), (cast(x'00d8' as text)), (cast(x'00d84100' as text))")]
       [p (prep db "select x from u")]
       [st (cadr p)]
       [rows (let loop ([acc '()])
               (let ([s (step st)])
                 (if (= s 100)
                     (let* ([t (column-type st 0)]
                            [tp (column-text-ptr st 0)]
                            [tn (column-bytes st 0)]
                            [tb (read-bytes tp tn)]
                            [bp (column-blob-ptr st 0)]
                            [bn (column-bytes st 0)]
                            [bb (read-bytes bp bn)])
                       (loop (cons (list 'type t 'text-bytes tb 'blob-bytes bb) acc)))
                     (reverse acc))))]
       [f (finalize st)]
       [c (close db)])
  (show "G. encoding pragma, create, insert" (list e1 e2 e3))
  (for-each (lambda (r) (show "G. row" r)) rows))
