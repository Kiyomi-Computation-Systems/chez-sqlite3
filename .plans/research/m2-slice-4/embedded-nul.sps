;;; M2 slice 4's research, item 5: TEXT and BLOB holding U+0000, bound with
;;; their byte length, read back three ways: sqlite3_column_text then
;;; sqlite3_column_bytes; sqlite3_column_blob then sqlite3_column_bytes; and
;;; strlen of sqlite3_column_text's pointer. Each way runs on its own step of
;;; a fresh run of the statement, so no read converts the value before
;;; another. Also sqlite3_column_type, and SQL's length(), octet_length(),
;;; typeof() and hex() of the same value. Bytes are read only up to
;;; sqlite3_column_bytes, and printed in hex.
;;;
;;; Every effect is ordered by let*, a named let or for-each (AGENTS.md).
;;;
;;;   scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-slice-4/embedded-nul.sps'
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
(define bind-text64 (foreign-procedure "sqlite3_bind_text64" (uptr int uptr unsigned-64 uptr unsigned-8) int))
(define bind-blob64 (foreign-procedure "sqlite3_bind_blob64" (uptr int uptr unsigned-64 uptr) int))
(define column-type (foreign-procedure "sqlite3_column_type" (uptr int) int))
(define column-int64 (foreign-procedure "sqlite3_column_int64" (uptr int) integer-64))
(define column-text (foreign-procedure "sqlite3_column_text" (uptr int) uptr))
(define column-blob (foreign-procedure "sqlite3_column_blob" (uptr int) uptr))
(define column-bytes (foreign-procedure "sqlite3_column_bytes" (uptr int) int))
(define errmsg (foreign-procedure "sqlite3_errmsg" (uptr) uptr))
(define strlen (foreign-procedure "strlen" (uptr) size_t))

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
(define (hex bv)
  (if (not bv)
      "NULL"
      (let loop ([i 0] [acc '()])
        (if (= i (bytevector-length bv))
            (apply string-append "[" (reverse (cons "]" acc)))
            (loop (+ i 1) (cons (string-append (if (= i 0) "" " ") (hex2 (bytevector-u8-ref bv i))) acc))))))
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

(define (open-memory)
  (let* ([name (block-of (string->utf8 ":memory:"))]
         [cell (foreign-alloc 8)]
         [zero (foreign-set! 'uptr cell 0 0)]
         [rc (open-v2 name cell (logior READWRITE CREATE MEMORY EXRESCODE) 0)]
         [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (foreign-free name)
    (unless (= rc 0) (error 'probe "open failed" rc))
    db))
(define (prep db text)
  (let* ([bv (string->utf8 text)]
         [sql (block-of bv)]
         [cell (foreign-alloc 8)]
         [zero (foreign-set! 'uptr cell 0 0)]
         [rc (prepare-v3 db sql (bytevector-length bv) 0 cell 0)]
         [st (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (foreign-free sql)
    (unless (= rc 0) (error 'probe "prepare failed" text rc (shown (c-bytes (errmsg db)))))
    st))
(define (exec db text)
  (let* ([st (prep db text)]
         [s (step st)]
         [f (finalize st)])
    (unless (= s 101) (error 'probe "exec failed" text s))
    s))

;; bind-value : Address Natural Symbol Bytevector -> rc, from a counted copy
(define (bind-value st i kind bv)
  (let* ([p (block-of bv)]
         [rc (if (eq? kind 'text)
                 (bind-text64 st i p (bytevector-length bv) TRANSIENT UTF8)
                 (bind-blob64 st i p (bytevector-length bv) TRANSIENT))]
         [f (foreign-free p)])
    rc))

;; The three ways, each on its own run of ST, which is reset before each.
(define (text-way st)
  (let* ([r (reset st)]
         [s (step st)]
         [ty (column-type st 0)]
         [p (column-text st 0)]
         [n (column-bytes st 0)]
         [bv (if (= p 0) #f (bytes-at p n))]
         [nul-after (if (= p 0) 'none (foreign-ref 'unsigned-8 p n))]
         [len (if (= p 0) 'none (strlen p))]
         [ty-after (column-type st 0)])
    (format "type ~a; column_text then column_bytes: ~a bytes ~a, the byte at [bytes] ~a, strlen ~a; type after ~a"
            ty n (hex bv) nul-after len ty-after)))
(define (blob-way st)
  (let* ([r (reset st)]
         [s (step st)]
         [ty (column-type st 0)]
         [p (column-blob st 0)]
         [n (column-bytes st 0)]
         [bv (if (= p 0) #f (bytes-at p n))]
         [ty-after (column-type st 0)])
    (format "type ~a; column_blob then column_bytes: ~a bytes ~a; type after ~a" ty n (hex bv) ty-after)))
(define (strlen-way st)
  (let* ([r (reset st)]
         [s (step st)]
         [p (column-text st 0)]
         [len (if (= p 0) 'none (strlen p))])
    (format "column_text, then strlen alone: ~a" len)))
(define (sql-way st)
  (let* ([r (reset st)]
         [s (step st)]
         [len (column-int64 st 1)]
         [oct (column-int64 st 2)]
         [tp (column-text st 3)]
         [tn (column-bytes st 3)]
         [ty (bytes-at tp tn)]
         [hp (column-text st 4)]
         [hn (column-bytes st 4)]
         [hx (bytes-at hp hn)])
    (format "length() ~a, octet_length() ~a, typeof() ~a, hex() ~a" len oct (shown ty) (shown hx))))

(define values-tried
  (list (cons 'text (u8-list->bytevector '(#x61 #x00 #x62)))
        (cons 'text (u8-list->bytevector '(#x00)))
        (cons 'text (u8-list->bytevector '(#x61 #x62 #x00)))
        (cons 'text (u8-list->bytevector '(#x00 #x61 #x62)))
        (cons 'text (u8-list->bytevector '(#xC3 #xA9 #x00 #xE2 #x82 #xAC)))
        (cons 'blob (u8-list->bytevector '(#x61 #x00 #x62)))
        (cons 'blob (u8-list->bytevector '(#x00)))))

(printf "libversion: ~a~n" (shown (c-bytes (libversion))))
(printf "sourceid: ~a~n" (shown (c-bytes (sourceid))))

;; 5a. Through a table: inserted with select ?'s bind, read from the row.
(let ([db (open-memory)])
  (exec db "create table n (id integer primary key, x)")
  (for-each
   (lambda (v)
     (let* ([ins (prep db "insert into n (x) values (?1)")]
            [b (bind-value ins 1 (car v) (cdr v))]
            [s (step ins)]
            [f (finalize ins)]
            [st (prep db "select x, length(x), octet_length(x), typeof(x), hex(x) from n where id = last_insert_rowid()")])
       (printf "[table, ~a ~a] bind ~a, insert step ~a~n" (car v) (hex (cdr v)) b s)
       (printf "  ~a~n" (text-way st))
       (printf "  ~a~n" (blob-way st))
       (printf "  ~a~n" (strlen-way st))
       (printf "  ~a~n" (sql-way st))
       (finalize st)))
   values-tried)
  (close db))

;; 5b. Straight through select ?1: no table, the bound value itself.
(let ([db (open-memory)])
  (for-each
   (lambda (v)
     (let* ([st (prep db "select ?1, length(?1), octet_length(?1), typeof(?1), hex(?1)")]
            [b (bind-value st 1 (car v) (cdr v))])
       (printf "[select ?1, ~a ~a] bind ~a~n" (car v) (hex (cdr v)) b)
       (printf "  ~a~n" (text-way st))
       (printf "  ~a~n" (blob-way st))
       (printf "  ~a~n" (strlen-way st))
       (printf "  ~a~n" (sql-way st))
       (finalize st)))
   values-tried)
  (close db))
