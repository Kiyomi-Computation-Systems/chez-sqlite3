;;; M2 slice 1: which NUL-free SQL of 1, 2 and 3 bytes does SQLite's prepare
;;; leave empty? Each of the 255 + 65,025 + 16,581,375 inputs is prepared
;;; alone with its byte length; "empty" is SQLITE_OK with a NULL statement, as
;;; in tail.sps. The accepted ones are printed as lines of #x bytes, in order
;;; (the 1- and 2-byte ones, then the 3-byte ones), and the counts are printed
;;; last. tests/test-sql-tail.sps holds the lists as literals and holds the
;;; tail scanner to them. The 3-byte pass takes a few minutes.
;;; Every effect is ordered by let* or a named loop.
;;;
;;;   scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-slice-1/tail-accepted.sps'
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare-v3 (foreign-procedure "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define libversion (foreign-procedure "sqlite3_libversion" () string))

(define db
  (let* ([cell (foreign-alloc 8)]
         [rc (open-v2 ":memory:" cell (logior #x2 #x4 #x02000000) 0)]
         [h (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (unless (= rc 0) (error 'probe "open failed" rc))
    h))

(define sql-block (foreign-alloc 8))
(define stmt-cell (foreign-alloc 8))
(define tail-cell (foreign-alloc 8))

;; empty? : (Listof Byte) -> Boolean
(define (empty? bytes)
  (let loop ([i 0] [bs bytes])
    (unless (null? bs)
      (foreign-set! 'unsigned-8 sql-block i (car bs))
      (loop (+ i 1) (cdr bs))))
  (foreign-set! 'uptr stmt-cell 0 0)
  (foreign-set! 'uptr tail-cell 0 0)
  (let* ([rc (prepare-v3 db sql-block (length bytes) 0 stmt-cell tail-cell)]
         [st (foreign-ref 'uptr stmt-cell 0)])
    (unless (= st 0) (finalize st))
    (and (= rc 0) (= st 0))))

(define (hex b) (string-append "#x" (if (< b 16) "0" "") (number->string b 16)))

(define accepted-1 0)
(define accepted-2 0)
(define accepted-3 0)

(printf "libversion ~a\n" (libversion))
(let loop ([a 1])
  (when (< a 256)
    (when (empty? (list a))
      (set! accepted-1 (+ accepted-1 1))
      (printf "(~a)\n" (hex a)))
    (loop (+ a 1))))
(let loop ([a 1])
  (when (< a 256)
    (let inner ([b 1])
      (when (< b 256)
        (when (empty? (list a b))
          (set! accepted-2 (+ accepted-2 1))
          (printf "(~a ~a)\n" (hex a) (hex b)))
        (inner (+ b 1))))
    (loop (+ a 1))))
;; The 3-byte inputs, after a marker line.
(printf "3-byte\n")
(let loop ([a 1])
  (when (< a 256)
    (let mid ([b 1])
      (when (< b 256)
        (let inner ([c 1])
          (when (< c 256)
            (when (empty? (list a b c))
              (set! accepted-3 (+ accepted-3 1))
              (printf "(~a ~a ~a)\n" (hex a) (hex b) (hex c)))
            (inner (+ c 1))))
        (mid (+ b 1))))
    (loop (+ a 1))))
(printf "accepted: ~a of 1 byte, ~a of 2 bytes, ~a of 3 bytes\n" accepted-1 accepted-2 accepted-3)
(close db)
