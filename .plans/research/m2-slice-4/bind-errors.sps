;;; M2 slice 4's research, item 1: what the connection says after a bind
;;; SQLite refuses, and whether the statement's bindings survive it.
;;;
;;; Every row opens its own :memory: connection, with SQLITE_OPEN_EXRESCODE as
;;; chez-sqlite3 opens one, prepares "select ?1, typeof(?1), ?2, typeof(?2)",
;;; binds ?1 to the TEXT 'old' and ?2 to the INTEGER 42, then puts one of
;;; three controls on the connection before the refused bind:
;;;   none     nothing; the connection holds what the last call left
;;;   error    a failed prepare, "select nosuch_col": code 1, its own message
;;;            and an offset of 7
;;;   success  a successful prepare, "select 1", finalized at the row's end
;;; and reads errcode, extended errcode, errmsg (as raw bytes) and the error
;;; offset before and after the refused bind. Then it steps, or for a bind
;;; made while a row is ready or after done, resets and steps, and reads ?1
;;; and ?2 back.
;;;
;;; A length past the buffer's is never passed: the 2^31- and 2^32+1-byte
;;; values are bound from an anonymous, read-only, MAP_NORESERVE mapping of
;;; that many bytes (Linux), which reads as zeros and costs no memory.
;;;
;;; Every effect is ordered by let*, a named let or for-each (AGENTS.md).
;;;
;;;   scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-slice-4/bind-errors.sps'
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
(define bind-int64 (foreign-procedure "sqlite3_bind_int64" (uptr int integer-64) int))
(define bind-double (foreign-procedure "sqlite3_bind_double" (uptr int double) int))
(define bind-null (foreign-procedure "sqlite3_bind_null" (uptr int) int))
(define column-type (foreign-procedure "sqlite3_column_type" (uptr int) int))
(define column-int64 (foreign-procedure "sqlite3_column_int64" (uptr int) integer-64))
(define column-text (foreign-procedure "sqlite3_column_text" (uptr int) uptr))
(define column-bytes (foreign-procedure "sqlite3_column_bytes" (uptr int) int))
(define errcode (foreign-procedure "sqlite3_errcode" (uptr) int))
(define extended-errcode (foreign-procedure "sqlite3_extended_errcode" (uptr) int))
(define errmsg (foreign-procedure "sqlite3_errmsg" (uptr) uptr))
(define errstr (foreign-procedure "sqlite3_errstr" (int) uptr))
(define error-offset (foreign-procedure "sqlite3_error_offset" (uptr) int))
(define limit (foreign-procedure "sqlite3_limit" (uptr int int) int))
(define mmap (foreign-procedure "mmap" (uptr size_t int int int long) uptr))
(define munmap (foreign-procedure "munmap" (uptr size_t) int))

(define READWRITE #x2)
(define CREATE #x4)
(define MEMORY #x80)
(define EXRESCODE #x02000000)
(define UTF8 1)
(define LIMIT-LENGTH 0)
(define ROW 100)
(define TRANSIENT (- (expt 2 (* 8 (foreign-sizeof 'uptr))) 1))
(define MAP-FAILED TRANSIENT)

;; --- bytes ---------------------------------------------------------------------

;; block-of : Bytevector -> Address, a NUL-terminated copy
(define (block-of bv)
  (let ([p (foreign-alloc (+ 1 (bytevector-length bv)))])
    (let loop ([i 0])
      (when (< i (bytevector-length bv))
        (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bv i))
        (loop (+ i 1))))
    (foreign-set! 'unsigned-8 p (bytevector-length bv) 0)
    p))

;; bytes-at : Address Natural -> Bytevector
(define (bytes-at p n)
  (let ([bv (make-bytevector n 0)])
    (let loop ([i 0])
      (when (< i n)
        (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 p i))
        (loop (+ i 1))))
    bv))

;; c-bytes : Address -> (U Bytevector #f), the bytes up to the NUL, #f for NULL
(define (c-bytes p)
  (if (= p 0)
      #f
      (let loop ([n 0])
        (if (= (foreign-ref 'unsigned-8 p n) 0) (bytes-at p n) (loop (+ n 1))))))

(define (hex2 b) (string-append (if (< b 16) "0" "") (number->string b 16)))

;; shown : (U Bytevector #f) -> String, printable ASCII as itself, every
;; other byte as \xHH, inside double quotes; NULL for #f. Nothing is decoded.
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

;; --- SQLite --------------------------------------------------------------------

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

;; prep : Address String -> (List rc stmt)
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

;; state : Address -> String, the connection's error state, read in order
(define (state db)
  (let* ([code (errcode db)]
         [ext (extended-errcode db)]
         [msg (c-bytes (errmsg db))]
         [off (error-offset db)])
    (format "errcode ~a, extended ~a, errmsg ~a, offset ~a" code ext (shown msg) off)))

;; bind-bytes : (Address Address Natural -> rc) Bytevector -> rc, from a copy
(define (bind-bytes bind! bv)
  (let* ([p (block-of bv)]
         [rc (bind! p (bytevector-length bv))])
    (foreign-free p)
    rc))

;; with-mapping : Natural (Address -> A) -> A, PROC given SIZE readable bytes
(define (with-mapping size proc)
  (let ([p (mmap 0 size 1 (logior #x2 #x20 #x4000) -1 0)])
    (when (= p MAP-FAILED) (error 'probe "mmap failed" size))
    (let ([answer (proc p)])
      (munmap p size)
      answer)))

;; read-back : Address -> String, ?1 and ?2 as the step's row reads them
(define (read-back st)
  (let* ([t0 (column-type st 0)]
         [p0 (column-text st 0)]
         [n0 (column-bytes st 0)]
         [v0 (if (= p0 0) #f (bytes-at p0 n0))]
         [p1 (column-text st 1)]
         [n1 (column-bytes st 1)]
         [ty1 (bytes-at p1 n1)]
         [v2 (column-int64 st 2)]
         [p3 (column-text st 3)]
         [n3 (column-bytes st 3)]
         [ty3 (bytes-at p3 n3)])
    (format "?1 type ~a bytes ~a typeof ~a; ?2 ~a typeof ~a" t0 (shown v0) (shown ty1) v2 (shown ty3))))

;; --- controls --------------------------------------------------------------------

;; Each answers the statement to finalize at the row's end, or 0.
(define controls
  (list (cons "none" (lambda (db) (cons "nothing" 0)))
        (cons "error" (lambda (db)
                        (let ([p (prep db "select nosuch_col")])
                          (cons (format "prepare of \"select nosuch_col\" rc ~a" (car p)) (cadr p)))))
        (cons "success" (lambda (db)
                          (let ([p (prep db "select 1")])
                            (cons (format "prepare of \"select 1\" rc ~a" (car p)) (cadr p)))))))

;; row : String Natural Symbol (Address -> rc) -> Void
;; LIMIT is the length limit to set, or #f to keep the default. WHEN is
;; ready (bind before any step), row (after a step answered a row) or done
;; (after a second step answered done).
(define (row label lim when bind!)
  (for-each
   (lambda (control)
     (let* ([db (open-memory)]
            [lim-was (if lim (limit db LIMIT-LENGTH lim) (limit db LIMIT-LENGTH -1))]
            [lim-now (limit db LIMIT-LENGTH -1)]
            [p (prep db "select ?1, typeof(?1), ?2, typeof(?2)")]
            [st (cadr p)]
            [b1 (bind-bytes (lambda (a n) (bind-text64 st 1 a n TRANSIENT UTF8)) (string->utf8 "old"))]
            [b2 (bind-int64 st 2 42)]
            [s1 (if (eq? when 'ready) 'none (step st))]
            [s2 (if (eq? when 'done) (step st) 'none)]
            [ctl ((cdr control) db)]
            [before (state db)]
            [rc (bind! st)]
            [after (state db)]
            [es (c-bytes (errstr rc))]
            [r (if (eq? when 'ready) 'none (reset st))]
            [s (step st)]
            [back (if (= s ROW) (read-back st) "no row")]
            [f (finalize st)]
            [fc (if (= (cdr ctl) 0) 'none (finalize (cdr ctl)))]
            [c (close db)])
       (printf "[~a] control ~a: ~a~n" label (car control) (car ctl))
       (printf "  limit length was ~a, is ~a; prepare rc ~a; bind 'old' rc ~a, bind 42 rc ~a; steps before the bind ~a ~a~n"
               lim-was lim-now (car p) b1 b2 s1 s2)
       (printf "  before: ~a~n" before)
       (printf "  refused bind rc ~a, errstr(rc) ~a~n" rc (shown es))
       (printf "  after:  ~a~n" after)
       (printf "  reset ~a, step ~a: ~a; finalize ~a, close ~a~n" r s back f c)))
   controls))

(define (long-value n) (make-bytevector n 65))

(printf "libversion: ~a~n" (shown (c-bytes (libversion))))
(printf "sourceid: ~a~n" (shown (c-bytes (sourceid))))
(printf "errstr 18 ~a, 21 ~a, 25 ~a~n"
        (shown (c-bytes (errstr 18))) (shown (c-bytes (errstr 21))) (shown (c-bytes (errstr 25))))

;; 1a. TOOBIG over a lowered limit, then past 31 and 32 bits.
(row "TOOBIG text64, 101 bytes over a limit of 100" 100 'ready
     (lambda (st) (bind-bytes (lambda (a n) (bind-text64 st 1 a n TRANSIENT UTF8)) (long-value 101))))
(row "TOOBIG blob64, 101 bytes over a limit of 100" 100 'ready
     (lambda (st) (bind-bytes (lambda (a n) (bind-blob64 st 1 a n TRANSIENT)) (long-value 101))))
(for-each
 (lambda (size size-name)
   (for-each
    (lambda (lim lim-name)
      (row (format "TOOBIG text64, ~a mapped bytes, ~a" size-name lim-name) lim 'ready
           (lambda (st) (with-mapping size (lambda (a) (bind-text64 st 1 a size TRANSIENT UTF8)))))
      (row (format "TOOBIG blob64, ~a mapped bytes, ~a" size-name lim-name) lim 'ready
           (lambda (st) (with-mapping size (lambda (a) (bind-blob64 st 1 a size TRANSIENT))))))
    (list 100 #f)
    (list "limit 100" "default limit")))
 (list (expt 2 31) (+ (expt 2 32) 1))
 (list "2^31" "2^32+1"))

;; 1b. RANGE at index 0 and at count+1 (3), by every bind M2 uses.
(define (range-binds index)
  (list (cons "text64" (lambda (st) (bind-bytes (lambda (a n) (bind-text64 st index a n TRANSIENT UTF8)) (string->utf8 "new"))))
        (cons "blob64" (lambda (st) (bind-bytes (lambda (a n) (bind-blob64 st index a n TRANSIENT)) (string->utf8 "new"))))
        (cons "int64" (lambda (st) (bind-int64 st index 7)))
        (cons "double" (lambda (st) (bind-double st index 1.5)))
        (cons "null" (lambda (st) (bind-null st index)))))
(for-each
 (lambda (index)
   (for-each
    (lambda (b) (row (format "RANGE ~a at index ~a of 2" (car b) index) #f 'ready (cdr b)))
    (range-binds index)))
 '(0 3))

;; 1c. MISUSE: a bind of ?1 while a row is ready, then after done.
(for-each
 (lambda (b) (row (format "MISUSE ~a of ?1 while a row is ready" (car b)) #f 'row (cdr b)))
 (range-binds 1))
(for-each
 (lambda (b) (row (format "MISUSE ~a of ?1 after done, before a reset" (car b)) #f 'done (cdr b)))
 (list (car (range-binds 1)) (caddr (range-binds 1))))

;; 1d. The order of two refusals: RANGE, then TOOBIG, on one connection.
(let* ([db (open-memory)]
       [lim (limit db LIMIT-LENGTH 100)]
       [p (prep db "select ?1, typeof(?1), ?2, typeof(?2)")]
       [st (cadr p)]
       [r1 (bind-int64 st 3 1)]
       [s1 (state db)]
       [r2 (bind-bytes (lambda (a n) (bind-text64 st 1 a n TRANSIENT UTF8)) (long-value 101))]
       [s2 (state db)]
       [r3 (bind-int64 st 2 5)]
       [s3 (state db)]
       [f (finalize st)]
       [c (close db)])
  (printf "[one connection: RANGE, then TOOBIG, then a clean bind]~n")
  (printf "  RANGE rc ~a: ~a~n" r1 s1)
  (printf "  TOOBIG rc ~a: ~a~n" r2 s2)
  (printf "  clean bind rc ~a: ~a~n" r3 s3))

;; 1e. bind-all!'s order: ?1 bound, then ?2 refused (TOOBIG over a limit of
;; 100), then the step: ?1 keeps its value, ?2 is NULL.
(let* ([db (open-memory)]
       [lim (limit db LIMIT-LENGTH 100)]
       [p (prep db "select ?1, typeof(?1), ?2, typeof(?2)")]
       [st (cadr p)]
       [r1 (bind-bytes (lambda (a n) (bind-text64 st 1 a n TRANSIENT UTF8)) (string->utf8 "first"))]
       [r2 (bind-bytes (lambda (a n) (bind-text64 st 2 a n TRANSIENT UTF8)) (long-value 101))]
       [after (state db)]
       [s (step st)]
       [t0 (column-type st 0)]
       [p0 (column-text st 0)]
       [n0 (column-bytes st 0)]
       [v0 (if (= p0 0) #f (bytes-at p0 n0))]
       [t2 (column-type st 2)]
       [f (finalize st)]
       [c (close db)])
  (printf "[bind-all!'s order: ?1 bound, then ?2 refused]~n")
  (printf "  bind ?1 rc ~a, bind ?2 (101 bytes) rc ~a: ~a~n" r1 r2 after)
  (printf "  step ~a: ?1 type ~a bytes ~a; ?2 type ~a~n" s t0 (shown v0) t2))
