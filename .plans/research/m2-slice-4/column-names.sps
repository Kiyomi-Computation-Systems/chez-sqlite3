;;; M2 slice 4's research, item 4: sqlite3_column_name's bytes and pointer
;;; after prepare, after a step, after a reset and after a second step, and
;;; sqlite3_column_count.
;;;
;;; Every SQL is written with \x escapes or built from raw bytes, and every
;;; name is read as raw bytes up to its NUL and printed in hex, never decoded
;;; (Chez's utf8->string drops a leading U+FEFF). A pointer is compared as an
;;; integer only; a pointer is read only straight after the call that
;;; answered it, never after a later call.
;;;
;;; Every effect is ordered by let*, a named let or for-each (AGENTS.md).
;;;
;;;   scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-slice-4/column-names.sps'
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
(define column-count (foreign-procedure "sqlite3_column_count" (uptr) int))
(define column-name (foreign-procedure "sqlite3_column_name" (uptr int) uptr))
(define errmsg (foreign-procedure "sqlite3_errmsg" (uptr) uptr))

(define READWRITE #x2)
(define CREATE #x4)
(define MEMORY #x80)
(define EXRESCODE #x02000000)

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
  (let loop ([i 0] [acc '()])
    (if (= i (bytevector-length bv))
        (apply string-append "[" (reverse (cons "]" acc)))
        (loop (+ i 1) (cons (string-append (if (= i 0) "" " ") (hex2 (bytevector-u8-ref bv i))) acc)))))
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
(define (shown+hex bv) (if bv (string-append (shown bv) " " (hex bv)) "NULL"))

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
(define (prepare db bv)
  (let* ([sql (block-of bv)]
         [cell (foreign-alloc 8)]
         [zero (foreign-set! 'uptr cell 0 0)]
         [rc (prepare-v3 db sql (bytevector-length bv) 0 cell 0)]
         [st (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (foreign-free sql)
    (list rc st)))
(define (exec db bv)
  (let* ([p (prepare db bv)]
         [msg (c-bytes (errmsg db))]
         [s (if (= (cadr p) 0) 'none (step (cadr p)))]
         [f (if (= (cadr p) 0) 'none (finalize (cadr p)))])
    (unless (and (= (car p) 0) (eqv? s 101))
      (error 'probe "exec failed" (shown bv) (car p) s (shown msg)))
    (list (car p) s f)))

;; names : Address -> (Listof (Pair Address (U Bytevector #f))), each read
;; straight after its call
(define (names st)
  (let loop ([i 0] [acc '()])
    (if (= i (column-count st))
        (reverse acc)
        (let* ([p (column-name st i)]
               [b (c-bytes p)])
          (loop (+ i 1) (cons (cons p b) acc))))))

(define (same? xs ys key)
  (and (= (length xs) (length ys))
       (let loop ([xs xs] [ys ys])
         (or (null? xs)
             (and (equal? (key (car xs)) (key (car ys))) (loop (cdr xs) (cdr ys)))))))

;; names-case : Address String Bytevector -> Void
(define (names-case db label bv)
  (let* ([p (prepare db bv)]
         [msg (c-bytes (errmsg db))]
         [st (cadr p)])
    (printf "[~a] SQL ~a~n" label (shown+hex bv))
    (if (= st 0)
        (printf "  prepare ~a, errmsg ~a~n" (car p) (shown msg))
        (let* ([n0 (column-count st)]
               [a (names st)]
               [s1 (step st)]
               [n1 (column-count st)]
               [b (names st)]
               [r (reset st)]
               [n2 (column-count st)]
               [c (names st)]
               [s2 (step st)]
               [d (names st)]
               [f (finalize st)])
          (printf "  prepare ~a, column_count ~a; step ~a, count ~a; reset ~a, count ~a; step ~a~n"
                  (car p) n0 s1 n1 r n2 s2)
          (let loop ([i 0] [xs a])
            (unless (null? xs)
              (printf "  name ~a: ~a~n" i (shown+hex (cdar xs)))
              (loop (+ i 1) (cdr xs))))
          (printf "  same bytes after step, reset, step: ~a ~a ~a; same pointers: ~a ~a ~a~n"
                  (same? a b cdr) (same? a c cdr) (same? a d cdr)
                  (same? a b car) (same? a c car) (same? a d car))))))

;; u8 : (U String (Listof Byte)) ... -> Bytevector, strings as UTF-8, lists as bytes
(define (u8 . parts)
  (u8-list->bytevector
   (apply append
          (map (lambda (x) (if (string? x) (bytevector->u8-list (string->utf8 x)) x)) parts))))

(printf "libversion: ~a~n" (shown (c-bytes (libversion))))
(printf "sourceid: ~a~n" (shown (c-bytes (sourceid))))

(let ([db (open-memory)])
  (exec db (u8 "create table t (a integer, \"b c\" text, \"\xE9;\" text, \"\xFEFF;x\" text)"))
  (exec db (u8 "insert into t values (1, 'two', 'three', 'four')"))
  (exec db (u8 "create table u (\"" '(#xff) "\")"))
  (exec db (u8 "insert into u values (5)"))
  (for-each
   (lambda (c) (names-case db (car c) (cdr c)))
   (list (cons "bare expressions" (u8 "select 1+1, 1 + 1, (1+1)"))
         (cons "expressions' text" (u8 "select x'00', 'a' || 'b', -  1"))
         (cons "a column of a table" (u8 "select a from t"))
         (cons "* over a table" (u8 "select * from t"))
         (cons "a multibyte alias, quoted" (u8 "select 1 as \"\xE9;\x540D;\""))
         (cons "a multibyte alias, bare" (u8 "select 1 as \xE9;\x540D;"))
         (cons "an alias starting with U+FEFF, quoted" (u8 "select 1 as \"\xFEFF;id\""))
         (cons "an alias starting with U+FEFF, bare" (u8 "select 1 as \xFEFF;id"))
         (cons "an alias holding U+FEFF, quoted" (u8 "select 1 as \"a\xFEFF;b\""))
         (cons "an alias holding U+FEFF, bare" (u8 "select 1 as a\xFEFF;b"))
         (cons "duplicate aliases" (u8 "select 1 as a, 2 as a"))
         (cons "a column twice" (u8 "select a, a from t"))
         (cons "* over a join of t with itself" (u8 "select * from t, t as x"))
         (cons "an alias holding a doubled quote" (u8 "select 1 as \"a\"\"b\""))
         (cons "an alias as a string literal" (u8 "select 1 as 'lit'"))
         (cons "an alias of the byte FF, not UTF-8" (u8 "select 1 as \"" '(#xff) "\""))
         (cons "* over a table whose column is named FF" (u8 "select * from u"))
         (cons "a step that answers done" (u8 "select a as \xE9; from t where 0"))))
  (close db))

;; A reprepare: the same connection adds a column between prepare and step.
;; The old pointers are compared as integers, never read.
(let* ([db (open-memory)]
       [e1 (exec db (u8 "create table r (a)"))]
       [e2 (exec db (u8 "insert into r values (1)"))]
       [p (prepare db (u8 "select * from r"))]
       [st (cadr p)]
       [n0 (column-count st)]
       [a (names st)]
       [e3 (exec db (u8 "alter table r add column \xFEFF;z"))]
       [s (step st)]
       [n1 (column-count st)]
       [b (names st)]
       [f (finalize st)]
       [c (close db)])
  (printf "[a reprepare: another statement adds a column before the step]~n")
  (printf "  prepare ~a, column_count ~a: ~a~n" (car p) n0 (map (lambda (x) (shown+hex (cdr x))) a))
  (printf "  step ~a, column_count ~a: ~a~n" s n1 (map (lambda (x) (shown+hex (cdr x))) b))
  (printf "  column 0's pointer the same after the reprepare: ~a~n" (= (caar a) (caar b))))
