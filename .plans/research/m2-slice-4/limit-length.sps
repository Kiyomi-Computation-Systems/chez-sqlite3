;;; M2 slice 4's research, item 2: what sqlite3_limit(db, SQLITE_LIMIT_LENGTH,
;;; n) answers and keeps, the smallest limit each library keeps, and binds of
;;; the limit's length and one byte more at that limit.
;;;
;;; Each row of the spread opens a fresh :memory: connection (EXRESCODE), so
;;; the call answers the default as the old value; a read with -1 follows.
;;; Then a scan of n from 0 to 64, each on a fresh connection; then one
;;; connection set three times, to show each call answers the value before
;;; it. The limit ids are the headers': LENGTH 0, SQL_LENGTH 1,
;;; VARIABLE_NUMBER 9; 3.53.1's header adds PARSER_DEPTH 12, the floor's ends
;;; at WORKER_THREADS 11.
;;;
;;; Every effect is ordered by let*, a named let or for-each (AGENTS.md).
;;;
;;;   scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-slice-4/limit-length.sps'
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define libversion (foreign-procedure "sqlite3_libversion" () uptr))
(define sourceid (foreign-procedure "sqlite3_sourceid" () uptr))
(define compileoption-get (foreign-procedure "sqlite3_compileoption_get" (int) uptr))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (uptr uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare-v3 (foreign-procedure "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define step (foreign-procedure "sqlite3_step" (uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define bind-text64 (foreign-procedure "sqlite3_bind_text64" (uptr int uptr unsigned-64 uptr unsigned-8) int))
(define bind-blob64 (foreign-procedure "sqlite3_bind_blob64" (uptr int uptr unsigned-64 uptr) int))
(define column-type (foreign-procedure "sqlite3_column_type" (uptr int) int))
(define column-text (foreign-procedure "sqlite3_column_text" (uptr int) uptr))
(define column-bytes (foreign-procedure "sqlite3_column_bytes" (uptr int) int))
(define errmsg (foreign-procedure "sqlite3_errmsg" (uptr) uptr))
(define limit (foreign-procedure "sqlite3_limit" (uptr int int) int))

(define READWRITE #x2)
(define CREATE #x4)
(define MEMORY #x80)
(define EXRESCODE #x02000000)
(define UTF8 1)
(define LENGTH 0)
(define SQL-LENGTH 1)
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
    (list rc st)))

(printf "libversion: ~a~n" (shown (c-bytes (libversion))))
(printf "sourceid: ~a~n" (shown (c-bytes (sourceid))))

;; The compile options, read through the FFI, from 0 to the first NULL.
(let loop ([i 0] [acc '()])
  (let ([p (compileoption-get i)])
    (if (= p 0)
        (printf "compile options (~a): ~a~n" i
                (apply string-append
                       (let join ([xs (reverse acc)])
                         (cond [(null? xs) '()]
                               [(null? (cdr xs)) (list (car xs))]
                               [else (cons (car xs) (cons " " (join (cdr xs))))]))))
        (loop (+ i 1) (cons (shown (c-bytes p)) acc)))))

;; Each limit id's default, and what a read of an id past the last answers.
(let* ([db (open-memory)])
  (let loop ([id -1])
    (when (<= id 13)
      (printf "limit id ~a: default ~a~n" id (limit db id -1))
      (loop (+ id 1))))
  (close db))

;; 2a. The spread: each n on a fresh connection.
(define hard
  (let* ([db (open-memory)]
         [was (limit db LENGTH 2147483647)]
         [now (limit db LENGTH -1)])
    (close db)
    now))
(printf "LENGTH's hard maximum, read after setting 2147483647: ~a~n" hard)
(for-each
 (lambda (n)
   (let* ([db (open-memory)]
          [old (limit db LENGTH n)]
          [new (limit db LENGTH -1)]
          [sql-len (limit db SQL-LENGTH -1)]
          [c (close db)])
     (printf "set LENGTH ~a: answered ~a, then reads ~a; SQL_LENGTH reads ~a~n" n old new sql-len)))
 (list -2147483648 -2 -1 0 1 2 10 29 30 31 32 100 1000 (- hard 1) hard (+ hard 1) 2147483647))

;; 2b. The scan: the value kept for each n from 0 to 64, and the smallest kept.
(define kept
  (let loop ([n 0] [acc '()])
    (if (> n 64)
        (reverse acc)
        (let* ([db (open-memory)]
               [old (limit db LENGTH n)]
               [new (limit db LENGTH -1)]
               [c (close db)])
          (loop (+ n 1) (cons (cons n new) acc))))))
(printf "scan, n then the value kept: ~s~n" kept)
(define smallest
  (let loop ([ks kept])
    (cond [(null? ks) #f]
          [(= (caar ks) (cdar ks)) (caar ks)]
          [else (loop (cdr ks))])))
(printf "smallest n kept as itself: ~a~n" smallest)

;; 2c. One connection, set three times: each call answers the value before it.
(let* ([db (open-memory)]
       [a (limit db LENGTH 500)]
       [b (limit db LENGTH 50)]
       [c (limit db LENGTH 5)]
       [d (limit db LENGTH -1)]
       [e (limit db LENGTH -7)]
       [f (limit db LENGTH -1)]
       [g (close db)])
  (printf "one connection: set 500 answered ~a; set 50 answered ~a; set 5 answered ~a; read ~a; set -7 answered ~a; read ~a~n"
          a b c d e f))

;; 2d. Binds of the limit's length, one byte less and one byte more, as TEXT
;; and as a BLOB, at a limit L: the bind's code, then the step's, the value's
;; type and byte count. The statement is "select ?", whose one column is
;; named "?", one byte, so its prepare is under any limit; a statement that
;; failed to prepare is never bound or stepped.
(define (bind-at lim)
  (let* ([db (open-memory)]
         [was (limit db LENGTH lim)]
         [is (limit db LENGTH -1)])
    (printf "at limit ~a (set, reads ~a), \"select ?\":~n" lim is)
    (for-each
     (lambda (kind)
       (for-each
        (lambda (n)
          (let* ([p (prep db "select ?")]
                 [st (cadr p)])
            (if (= st 0)
                (printf "  ~a of ~a bytes: prepare ~a (errmsg ~a), not bound~n"
                        kind n (car p) (shown (c-bytes (errmsg db))))
                (let* ([bv (make-bytevector n 65)]
                       [blk (block-of bv)]
                       [rc (if (eq? kind 'text)
                               (bind-text64 st 1 blk n TRANSIENT UTF8)
                               (bind-blob64 st 1 blk n TRANSIENT))]
                       [freed (foreign-free blk)]
                       [msg (c-bytes (errmsg db))]
                       [s (step st)]
                       [ty (if (= s ROW) (column-type st 0) 'none)]
                       [nb (if (= s ROW) (column-bytes st 0) 'none)]
                       [f (finalize st)])
                  (printf "  ~a of ~a bytes: prepare ~a, bind ~a (errmsg ~a), step ~a, type ~a, bytes ~a~n"
                          kind n (car p) rc (shown msg) s ty nb)))))
        (list (- is 1) is (+ is 1))))
     '(text blob))
    (close db)))
(bind-at smallest)
(bind-at 30)
(bind-at 100)

;; 2e. What else the length limit holds, at a limit of 30, by prepare and by
;; step: SQL longer than 30 bytes; a column name of 30 and of 31 bytes (an
;; alias, and an expression's own text); a literal of 31 bytes under a short
;; alias; and "select ?1", the name slice 4's row may use.
(let* ([db (open-memory)]
       [was (limit db LENGTH 30)]
       [is (limit db LENGTH -1)])
  (printf "at limit 30 (reads ~a), what prepare and step answer:~n" is)
  (for-each
   (lambda (sql)
     (let* ([p (prep db sql)]
            [pmsg (c-bytes (errmsg db))]
            [st (cadr p)])
       (if (= st 0)
           (printf "  ~s (~a bytes): prepare ~a (errmsg ~a)~n"
                   sql (bytevector-length (string->utf8 sql)) (car p) (shown pmsg))
           (let* ([s (step st)]
                  [smsg (c-bytes (errmsg db))]
                  [f (finalize st)])
             (printf "  ~s (~a bytes): prepare ~a, step ~a (errmsg ~a)~n"
                     sql (bytevector-length (string->utf8 sql)) (car p) s (shown smsg))))))
   (list (string-append "select 1 as x -- " (make-string 100 #\c))
         (string-append "select 1 as " (make-string 30 #\n))
         (string-append "select 1 as " (make-string 31 #\n))
         (string-append "select '" (make-string 28 #\a) "'")
         (string-append "select '" (make-string 29 #\a) "'")
         (string-append "select '" (make-string 31 #\a) "' as x")
         "select ?1"))
  (close db))

;; 2f. "select ?1", whose column is named "?1", two bytes, prepared with the
;; limit set to 1 and to 2: the name is held to the limit at prepare.
(for-each
 (lambda (n)
   (let* ([db (open-memory)]
          [was (limit db LENGTH n)]
          [is (limit db LENGTH -1)]
          [p (prep db "select ?1")]
          [msg (c-bytes (errmsg db))]
          [f (if (= (cadr p) 0) 'none (finalize (cadr p)))]
          [c (close db)])
     (printf "limit set to ~a, reads ~a: \"select ?1\" prepare ~a (errmsg ~a), statement null? ~a~n"
             n is (car p) (shown msg) (= (cadr p) 0))))
 '(1 2))
