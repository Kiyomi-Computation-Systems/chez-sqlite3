;;; M2 slice 4's research, item 6: the claims of SQLite behaviour in the M2
;;; plan's sections 4.3 and 4.4 and in ADR-0015 that no earlier probe
;;; measured, each measured here. The README lists every claim checked.
;;;   S1  a column declared BOOLEAN reads back 1 and 0; TRUE and FALSE are 1
;;;       and 0 (plan 4.4; ADR-0015, context and decision 7)
;;;   S2  sqlite3_errcode against sqlite3_extended_errcode, opened with and
;;;       without SQLITE_OPEN_EXRESCODE (ADR-0015's amendment)
;;;   S3  a column read that answers a NULL pointer sets no code: the code
;;;       read straight after is whatever the last call left (plan 4.4;
;;;       ADR-0015 decision 7)
;;;   S4  the type read first, then the matching accessor: no conversion,
;;;       the type and the pointer unchanged (ADR-0015 decision 7)
;;;   S5  sqlite3_clear_bindings makes every parameter NULL, whatever it held
;;;       (ADR-0015 decision 6)
;;;   S6  a NULL pointer binds NULL whatever the length given (ADR-0015,
;;;       context; the plan 4.3)
;;;
;;; Every effect is ordered by let*, a named let or for-each (AGENTS.md).
;;;
;;;   scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-slice-4/sweep.sps'
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define libversion (foreign-procedure "sqlite3_libversion" () uptr))
(define sourceid (foreign-procedure "sqlite3_sourceid" () uptr))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (uptr uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare-v3 (foreign-procedure "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define step (foreign-procedure "sqlite3_step" (uptr) int))
(define reset (foreign-procedure "sqlite3_reset" (uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define clear-bindings (foreign-procedure "sqlite3_clear_bindings" (uptr) int))
(define bind-text64 (foreign-procedure "sqlite3_bind_text64" (uptr int uptr unsigned-64 uptr unsigned-8) int))
(define bind-blob64 (foreign-procedure "sqlite3_bind_blob64" (uptr int uptr unsigned-64 uptr) int))
(define bind-int64 (foreign-procedure "sqlite3_bind_int64" (uptr int integer-64) int))
(define bind-double (foreign-procedure "sqlite3_bind_double" (uptr int double) int))
(define column-count (foreign-procedure "sqlite3_column_count" (uptr) int))
(define column-type (foreign-procedure "sqlite3_column_type" (uptr int) int))
(define column-int64 (foreign-procedure "sqlite3_column_int64" (uptr int) integer-64))
(define column-double (foreign-procedure "sqlite3_column_double" (uptr int) double))
(define column-text (foreign-procedure "sqlite3_column_text" (uptr int) uptr))
(define column-blob (foreign-procedure "sqlite3_column_blob" (uptr int) uptr))
(define column-bytes (foreign-procedure "sqlite3_column_bytes" (uptr int) int))
(define errcode (foreign-procedure "sqlite3_errcode" (uptr) int))
(define extended-errcode (foreign-procedure "sqlite3_extended_errcode" (uptr) int))
(define errmsg (foreign-procedure "sqlite3_errmsg" (uptr) uptr))
(define limit (foreign-procedure "sqlite3_limit" (uptr int int) int))

(define READWRITE #x2)
(define CREATE #x4)
(define MEMORY #x80)
(define EXRESCODE #x02000000)
(define UTF8 1)
(define ROW 100)
(define TRANSIENT (- (expt 2 (* 8 (foreign-sizeof 'uptr))) 1))

(define (block-of bv)
  (let ([p (foreign-alloc (+ 1 (bytevector-length bv)))])
    (let loop ([i 0])
      (when (< i (bytevector-length bv))
        (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bv i))
        (loop (+ i 1))))
    (foreign-set! 'unsigned-8 p (bytevector-length bv) 0)
    p))
(define (bytes-at p n)
  (let ([bv (make-bytevector n 0)])
    (let loop ([i 0])
      (when (< i n)
        (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 p i))
        (loop (+ i 1))))
    bv))
(define (c-bytes p)
  (if (= p 0)
      #f
      (let loop ([n 0])
        (if (= (foreign-ref 'unsigned-8 p n) 0) (bytes-at p n) (loop (+ n 1))))))
(define (hex2 b) (string-append (if (< b 16) "0" "") (number->string b 16)))
(define (shown bv)
  (if (not bv)
      "NULL"
      (let loop ([i 0] [acc '()])
        (if (= i (bytevector-length bv))
            (apply string-append "\"" (reverse (cons "\"" acc)))
            (let ([b (bytevector-u8-ref bv i)])
              (loop (+ i 1)
                    (cons (if (and (>= b 32) (< b 127) (not (= b 34)) (not (= b 92)))
                              (string (integer->char b))
                              (string-append "\\x" (hex2 b)))
                          acc)))))))

(define (open-with flags)
  (let* ([name (block-of (string->utf8 ":memory:"))]
         [cell (foreign-alloc 8)]
         [zero (foreign-set! 'uptr cell 0 0)]
         [rc (open-v2 name cell flags 0)]
         [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (foreign-free name)
    (unless (= rc 0) (error 'probe "open failed" rc))
    db))
(define (open-memory) (open-with (logior READWRITE CREATE MEMORY EXRESCODE)))
(define (prepare db text)
  (let* ([bv (string->utf8 text)]
         [sql (block-of bv)]
         [cell (foreign-alloc 8)]
         [zero (foreign-set! 'uptr cell 0 0)]
         [rc (prepare-v3 db sql (bytevector-length bv) 0 cell 0)]
         [st (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (foreign-free sql)
    (list rc st)))
(define (prep db text)
  (let ([p (prepare db text)])
    (unless (= (car p) 0) (error 'probe "prepare failed" text (car p) (shown (c-bytes (errmsg db)))))
    (cadr p)))
(define (exec db text)
  (let* ([st (prep db text)]
         [s (step st)]
         [f (finalize st)])
    (unless (= s 101) (error 'probe "exec failed" text s))
    s))
(define (state db)
  (let* ([code (errcode db)]
         [ext (extended-errcode db)]
         [msg (c-bytes (errmsg db))])
    (format "errcode ~a, extended ~a, errmsg ~a" code ext (shown msg))))

;; value-of : Address Natural -> String, by the column's type, read first
(define (value-of st i)
  (let ([ty (column-type st i)])
    (case ty
      [(1) (format "INTEGER ~a" (column-int64 st i))]
      [(2) (format "FLOAT ~a" (column-double st i))]
      [(3) (let* ([p (column-text st i)] [n (column-bytes st i)]) (format "TEXT ~a" (shown (bytes-at p n))))]
      [(4) (let* ([p (column-blob st i)] [n (column-bytes st i)]) (format "BLOB ~a" (if (= p 0) "NULL" (shown (bytes-at p n)))))]
      [(5) "NULL"]
      [else (format "type ~a" ty)])))

(printf "libversion: ~a~n" (shown (c-bytes (libversion))))
(printf "sourceid: ~a~n" (shown (c-bytes (sourceid))))

;; S1. BOOLEAN.
(let ([db (open-memory)])
  (exec db "create table b (id integer primary key, flag BOOLEAN)")
  (exec db "insert into b (flag) values (TRUE), (FALSE), (1), (0), ('1'), ('0'), ('true'), (1.0), (0.0), ('yes'), (2)")
  (let ([st (prep db "select flag, typeof(flag) from b order by id")])
    (let loop ([s (step st)] [k 1])
      (when (= s ROW)
        (let* ([v (value-of st 0)]
               [t (value-of st 1)])
          (printf "S1. BOOLEAN row ~a: ~a, typeof ~a~n" k v t))
        (loop (step st) (+ k 1))))
    (finalize st))
  (let* ([st (prep db "select TRUE, FALSE, typeof(TRUE), TRUE = 1, FALSE = 0")]
         [s (step st)]
         [a (value-of st 0)]
         [b (value-of st 1)]
         [c (value-of st 2)]
         [d (value-of st 3)]
         [e (value-of st 4)]
         [f (finalize st)])
    (printf "S1. select TRUE, FALSE, typeof(TRUE), TRUE = 1, FALSE = 0: ~a; ~a; ~a; ~a; ~a~n" a b c d e))
  (close db))

;; S2. errcode and extended errcode, with and without EXRESCODE.
(for-each
 (lambda (flags name)
   (let* ([db (open-with flags)]
          [e1 (exec db "create table u (x unique)")]
          [e2 (exec db "insert into u values (1)")]
          [st (prep db "insert into u values (1)")]
          [s (step st)]
          [after (state db)]
          [f (finalize st)]
          [after-finalize (state db)]
          [c (close db)])
     (printf "S2. ~a: a UNIQUE failure's step answered ~a; ~a; finalize answered ~a; ~a~n"
             name s after f after-finalize)))
 (list (logior READWRITE CREATE MEMORY EXRESCODE) (logior READWRITE CREATE MEMORY))
 (list "opened with EXRESCODE" "opened without EXRESCODE"))

;; S3. A column read answering NULL leaves the code as the last call left it.
(let* ([db (open-memory)]
       [st (prep db "select x'', '', NULL, 7")]
       [s (step st)]
       [after-step (state db)]
       [pb (column-blob st 0)]
       [x1 (extended-errcode db)]
       [pt (column-blob st 1)]
       [x2 (extended-errcode db)]
       [pn (column-text st 2)]
       [x3 (extended-errcode db)]
       [failed (prepare db "select nosuch_col")]
       [after-failed (state db)]
       [pb2 (column-blob st 0)]
       [x4 (extended-errcode db)]
       [pn2 (column-blob st 2)]
       [x5 (extended-errcode db)]
       [ok (prepare db "select 1")]
       [after-ok (state db)]
       [pb3 (column-blob st 0)]
       [x6 (extended-errcode db)]
       [f1 (finalize (cadr ok))]
       [f (finalize st)]
       [c (close db)])
  (printf "S3. after the step (~a): ~a~n" s after-step)
  (printf "S3. column_blob of x'' null? ~a, then extended ~a; column_blob of '' null? ~a, then ~a; column_text of NULL null? ~a, then ~a~n"
          (= pb 0) x1 (= pt 0) x2 (= pn 0) x3)
  (printf "S3. another statement's failed prepare (rc ~a): ~a~n" (car failed) after-failed)
  (printf "S3. then column_blob of x'' null? ~a, extended ~a; column_blob of NULL null? ~a, extended ~a~n"
          (= pb2 0) x4 (= pn2 0) x5)
  (printf "S3. another statement's successful prepare (rc ~a): ~a; then column_blob of x'' null? ~a, extended ~a~n"
          (car ok) after-ok (= pb3 0) x6))

;; S4. The type first, then the matching accessor, twice: the type and the
;; pointer stay; against an accessor that doesn't match, which converts.
(let ([db (open-memory)])
  (exec db "create table v (i, r, t, b)")
  (exec db "insert into v values (42, 1.5, 'text', x'0102')")
  (let* ([st (prep db "select i, r, t, b, t, b, i from v")]
         [s (step st)]
         [t2a (column-type st 2)]
         [p2a (column-text st 2)]
         [n2a (column-bytes st 2)]
         [p2b (column-text st 2)]
         [t2b (column-type st 2)]
         [t3a (column-type st 3)]
         [p3a (column-blob st 3)]
         [n3a (column-bytes st 3)]
         [p3b (column-blob st 3)]
         [t3b (column-type st 3)]
         [t0a (column-type st 0)]
         [i0 (column-int64 st 0)]
         [t0b (column-type st 0)]
         [t1a (column-type st 1)]
         [r1 (column-double st 1)]
         [t1b (column-type st 1)]
         [t4a (column-type st 4)]
         [p4 (column-blob st 4)]
         [t4b (column-type st 4)]
         [t5a (column-type st 5)]
         [p5 (column-text st 5)]
         [t5b (column-type st 5)]
         [t6a (column-type st 6)]
         [p6 (column-text st 6)]
         [t6b (column-type st 6)]
         [f (finalize st)])
    (printf "S4. TEXT: type ~a, column_text twice same pointer? ~a, bytes ~a, type after ~a~n" t2a (= p2a p2b) n2a t2b)
    (printf "S4. BLOB: type ~a, column_blob twice same pointer? ~a, bytes ~a, type after ~a~n" t3a (= p3a p3b) n3a t3b)
    (printf "S4. INTEGER: type ~a, column_int64 ~a, type after ~a; FLOAT: type ~a, column_double ~a, type after ~a~n"
            t0a i0 t0b t1a r1 t1b)
    (printf "S4. against: TEXT read by column_blob, type ~a then ~a; BLOB read by column_text, type ~a then ~a; INTEGER read by column_text, type ~a then ~a~n"
            t4a t4b t5a t5b t6a t6b))
  (close db))

;; S5. clear_bindings over parameters of every kind, after a reset.
(let* ([db (open-memory)]
       [st (prep db "select typeof(?1), typeof(?2), typeof(?3), typeof(?4), typeof(?5)")]
       [p (block-of (string->utf8 "text"))]
       [b1 (bind-int64 st 1 7)]
       [b2 (bind-double st 2 1.5)]
       [b3 (bind-text64 st 3 p 4 TRANSIENT UTF8)]
       [b4 (bind-blob64 st 4 p 4 TRANSIENT)]
       [freed (foreign-free p)]
       [s1 (step st)]
       [before (list (value-of st 0) (value-of st 1) (value-of st 2) (value-of st 3) (value-of st 4))]
       [r (reset st)]
       [cl (clear-bindings st)]
       [s2 (step st)]
       [after (list (value-of st 0) (value-of st 1) (value-of st 2) (value-of st 3) (value-of st 4))]
       [f (finalize st)]
       [c (close db)])
  (printf "S5. binds ~a ~a ~a ~a; step ~a: ~a~n" b1 b2 b3 b4 s1 before)
  (printf "S5. reset ~a, clear_bindings ~a, step ~a: ~a~n" r cl s2 after))

;; S6. A NULL pointer with a length: 0, 5, and one past a lowered limit.
(let* ([db (open-memory)]
       [lim (limit db 0 100)]
       [st (prep db "select typeof(?1), typeof(?2), typeof(?3), typeof(?4), typeof(?5), typeof(?6)")]
       [t0 (bind-text64 st 1 0 0 TRANSIENT UTF8)]
       [t5 (bind-text64 st 2 0 5 TRANSIENT UTF8)]
       [t101 (bind-text64 st 3 0 101 TRANSIENT UTF8)]
       [b0 (bind-blob64 st 4 0 0 TRANSIENT)]
       [b5 (bind-blob64 st 5 0 5 TRANSIENT)]
       [b101 (bind-blob64 st 6 0 101 TRANSIENT)]
       [s (step st)]
       [types (list (value-of st 0) (value-of st 1) (value-of st 2) (value-of st 3) (value-of st 4) (value-of st 5))]
       [f (finalize st)]
       [c (close db)])
  (printf "S6. NULL pointer, limit 100: text64 lengths 0, 5, 101 answer ~a ~a ~a; blob64 lengths 0, 5, 101 answer ~a ~a ~a; step ~a: ~a~n"
          t0 t5 t101 b0 b5 b101 s types))
