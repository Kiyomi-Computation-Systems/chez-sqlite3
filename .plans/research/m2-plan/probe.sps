;;; Facts the M2 plan's questions rest on, read through bare FFI from the
;;; library CHEZ_SQLITE3_LIBRARY names. Every effect is ordered by let* or
;;; for-each: Chez fixes no order for a call's arguments (AGENTS.md).
;;;   1. a step after SQLITE_DONE, with no reset, runs the statement again
;;;   2. reset and finalize answer the failed step's code again
;;;   3. a NULL pointer with length 0 binds NULL, for text and for a blob
;;;   4. -0.0 bound and read back
;;;   5. prepare's tail: a second statement, a comment, and empty SQL
;;;   6. sqlite3_error_offset counts bytes, not characters
;;;   7. a NUL inside the SQL, its byte length given
;;;   8. the codes for a bind out of range, and a bind while a row is ready
;;;   9. what a failed step answers on a connection opened with EXRESCODE
;;;  10. TEXT that isn't UTF-8, and a declared BOOLEAN holding text
;;;  11. the pointers an empty TEXT and an empty BLOB read back as
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare-v3 (foreign-procedure "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define step (foreign-procedure "sqlite3_step" (uptr) int))
(define reset (foreign-procedure "sqlite3_reset" (uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define bind-text (foreign-procedure "sqlite3_bind_text" (uptr int uptr int iptr) int))
(define bind-blob (foreign-procedure "sqlite3_bind_blob" (uptr int uptr int iptr) int))
(define bind-double (foreign-procedure "sqlite3_bind_double" (uptr int double) int))
(define bind-int64 (foreign-procedure "sqlite3_bind_int64" (uptr int integer-64) int))
(define column-type (foreign-procedure "sqlite3_column_type" (uptr int) int))
(define column-double (foreign-procedure "sqlite3_column_double" (uptr int) double))
(define column-int64 (foreign-procedure "sqlite3_column_int64" (uptr int) integer-64))
(define error-offset (foreign-procedure "sqlite3_error_offset" (uptr) int))
(define libversion (foreign-procedure "sqlite3_libversion" () string))
(define READWRITE #x2)
(define CREATE #x4)
(define MEMORY #x80)
(define EXRESCODE #x02000000)
(define TRANSIENT -1)

(define (open)
  (let* ([cell (foreign-alloc 8)]
         [rc (open-v2 ":memory:" cell (logior READWRITE CREATE MEMORY EXRESCODE) 0)]
         [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (unless (= rc 0) (error 'probe "open failed" rc))
    db))

;; bytes->block : Bytevector -> Address, NUL-terminated
(define (bytes->block bv)
  (let ([p (foreign-alloc (+ 1 (bytevector-length bv)))])
    (let loop ([i 0])
      (when (< i (bytevector-length bv))
        (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bv i))
        (loop (+ i 1))))
    (foreign-set! 'unsigned-8 p (bytevector-length bv) 0)
    p))

;; prepare : Address Bytevector -> (List rc stmt tail-offset)
(define (prepare db bv)
  (let* ([sql (bytes->block bv)]
         [cell (foreign-alloc 8)]
         [tail (foreign-alloc 8)]
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
         [s (step (cadr p))]
         [f (finalize (cadr p))])
    (list (car p) s f)))

(define (count-rows db)
  (let* ([p (prep db "select count(*) from t")]
         [s (step (cadr p))]
         [n (column-int64 (cadr p) 0)]
         [f (finalize (cadr p))])
    n))

(define (show label value) (printf "~a: ~s~n" label value))

(show "libversion" (libversion))

;; 1. A step after DONE, with no reset.
(let* ([db (open)]
       [made (exec db "create table t (x)")]
       [p (prep db "insert into t values (1)")]
       [st (cadr p)]
       [first (step st)]
       [second (step st)]
       [rows (count-rows db)]
       [f (finalize st)]
       [c (close db)])
  (show "1. step, step again without reset (101 is DONE)" (list first second))
  (show "1. rows after two steps of one insert" rows))

;; 2. reset and finalize after a failed step.
(let* ([db (open)]
       [made (exec db "create table t (x unique)")]
       [one (exec db "insert into t values (1)")]
       [p (prep db "insert into t values (1)")]
       [st (cadr p)]
       [failed (step st)]
       [r1 (reset st)]
       [r2 (reset st)]
       [again (step st)]
       [f (finalize st)]
       [c (close db)])
  (show "2/9. failed step's code (2067 is CONSTRAINT_UNIQUE, 19 CONSTRAINT)" failed)
  (show "2. reset, reset again, step again, finalize" (list r1 r2 again f)))

;; 3. NULL pointers with length 0, against non-NULL ones.
(let* ([db (open)]
       [p (prep db "select typeof(?1), typeof(?2), typeof(?3), typeof(?4)")]
       [st (cadr p)]
       [one-byte (foreign-alloc 1)]
       [b1 (bind-text st 1 0 0 TRANSIENT)]
       [b2 (bind-blob st 2 0 0 TRANSIENT)]
       [b3 (bind-text st 3 one-byte 0 TRANSIENT)]
       [b4 (bind-blob st 4 one-byte 0 TRANSIENT)]
       [s (step st)]
       [col-text (foreign-procedure "sqlite3_column_text" (uptr int) string)]
       [names (let loop ([i 0] [acc '()])
                (if (= i 4) (reverse acc) (loop (+ i 1) (cons (col-text st i) acc))))]
       [f (finalize st)]
       [c (close db)])
  (foreign-free one-byte)
  (show "3. bind rcs" (list b1 b2 b3 b4))
  (show "3. typeof: NULL-pointer text, NULL-pointer blob, empty text, empty blob" names))

;; 4. -0.0 round trip.
(let* ([db (open)]
       [made (exec db "create table r (x real)")]
       [p (prep db "insert into r values (?)")]
       [st (cadr p)]
       [b (bind-double st 1 -0.0)]
       [s (step st)]
       [f (finalize st)]
       [q (prep db "select x, typeof(x) from r")]
       [qs (cadr q)]
       [s2 (step qs)]
       [ty (column-type qs 0)]
       [x (column-double qs 0)]
       [f2 (finalize qs)]
       [p2 (prep db "select ?")]
       [st2 (cadr p2)]
       [b2 (bind-double st2 1 -0.0)]
       [s3 (step st2)]
       [ty2 (column-type st2 0)]
       [y (column-double st2 0)]
       [f3 (finalize st2)]
       [c (close db)])
  (show "4. -0.0 through a REAL column: type (2 FLOAT), value" (list ty x))
  (show "4. -0.0 through select ?: type, value" (list ty2 y)))

;; 5. prepare's tail.
(let* ([db (open)]
       [cases '("select 1; select 2" "select 1;   -- a comment" "select 1;" "" "   -- only a comment")]
       [results (let loop ([cs cases] [acc '()])
                  (if (null? cs)
                      (reverse acc)
                      (let* ([p (prep db (car cs))]
                             [f (if (= (cadr p) 0) 'no-statement (finalize (cadr p)))])
                        (loop (cdr cs) (cons (list (car cs) 'rc (car p) 'stmt-null? (= (cadr p) 0)
                                                   'tail-at (caddr p))
                                             acc)))))]
       [tail (prep db "   -- a comment")]
       [c (close db)])
  (for-each (lambda (r) (show "5. prepare" r)) results))

;; 6. sqlite3_error_offset on non-ASCII SQL.
(let* ([db (open)]
       [sql "select 'é', nosuchcol"]
       [p (prep db sql)]
       [off (error-offset db)]
       [c (close db)])
  (show "6. rc (1 ERROR), offset" (list (car p) off))
  (show "6. nosuchcol's index in characters, in bytes"
        (list 12 (- (bytevector-length (string->utf8 sql)) (string-length "nosuchcol")))))

;; 7. A NUL inside the SQL, its byte length given.
(let* ([db (open)]
       [bv (let ([b (string->utf8 "select 1  garbage")]) (bytevector-u8-set! b 8 0) b)]
       [p (prepare db bv)]
       [f (if (= (cadr p) 0) 'no-statement (finalize (cadr p)))]
       [c (close db)])
  (show "7. 'select 1' NUL ' garbage': rc, stmt-null?, tail-at, length" (list (car p) (= (cadr p) 0) (caddr p) (bytevector-length bv))))

;; 8. bind out of range, and bind while a row is ready.
(let* ([db (open)]
       [p (prep db "select ?1 union all select 2")]
       [st (cadr p)]
       [out (bind-int64 st 2 5)]
       [in (bind-int64 st 1 5)]
       [s (step st)]
       [mid (bind-int64 st 1 6)]
       [f (finalize st)]
       [c (close db)])
  (show "8. bind index 2 of 1 (25 RANGE), bind 1, step, bind while a row is ready (21 MISUSE)"
        (list out in s mid)))

;; 10. TEXT that isn't UTF-8, and a declared BOOLEAN holding text.
;; 11. The pointers an empty TEXT and an empty BLOB read back as.
(define column-text-ptr (foreign-procedure "sqlite3_column_text" (uptr int) uptr))
(define column-blob-ptr (foreign-procedure "sqlite3_column_blob" (uptr int) uptr))
(define column-bytes (foreign-procedure "sqlite3_column_bytes" (uptr int) int))
(let* ([db (open)]
       [made (exec db "create table b (flag BOOLEAN)")]
       [put (exec db "insert into b values ('yes')")]
       [p (prep db "select cast(x'ff41' as text), (select flag from b), '', x''")]
       [st (cadr p)]
       [s (step st)]
       [t0 (column-type st 0)]
       [p0 (column-text-ptr st 0)]
       [n0 (column-bytes st 0)]
       [b0 (let loop ([i 0] [acc '()])
             (if (= i n0) (reverse acc) (loop (+ i 1) (cons (foreign-ref 'unsigned-8 p0 i) acc))))]
       [t1 (column-type st 1)]
       [t2 (column-type st 2)]
       [p2 (column-text-ptr st 2)]
       [n2 (column-bytes st 2)]
       [t3 (column-type st 3)]
       [p3 (column-blob-ptr st 3)]
       [n3 (column-bytes st 3)]
       [f (finalize st)]
       [c (close db)])
  (show "10. cast(x'ff41' as text): type (3 TEXT), bytes" (list t0 b0))
  (show "10. 'yes' in a BOOLEAN column: type (3 TEXT)" t1)
  (show "11. '': type, pointer null?, bytes" (list t2 (= p2 0) n2))
  (show "11. x'': type (4 BLOB), pointer null?, bytes" (list t3 (= p3 0) n3)))
