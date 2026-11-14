;;; M2 slice 1's planning probe: does ADR-0014 decision 4's tail model
;;; match SQLite's prepare over every 1-, 2- and 3-byte SQL? Each SQL is
;;; prepared alone, with its byte length; "empty" is SQLITE_OK with a NULL
;;; statement. Two models are checked: the record's as accepted, whose
;;; whitespace is exactly space, \t, \n, \f and \r, and the amended one, in
;;; which \v (0x0B) also continues a run that one of those five started, and
;;; U+FEFF's three bytes, EF BB BF, are whitespace wherever they stand, as
;;; the tokenizer's CC_BOM case makes them. Then every string of 4 to 6 bytes
;;; over the 14 bytes the rules name, with A for anything else.
;;; Every effect is ordered by let* or a named loop.
;;;
;;;   scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-slice-1/tail.sps'
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

(define sql-block (foreign-alloc 64))
(define stmt-cell (foreign-alloc 8))
(define tail-cell (foreign-alloc 8))

;; sqlite-answer : Bytevector -> (List rc empty? tail-offset)
(define (sqlite-answer bv)
  (let loop ([i 0])
    (when (< i (bytevector-length bv))
      (foreign-set! 'unsigned-8 sql-block i (bytevector-u8-ref bv i))
      (loop (+ i 1))))
  (foreign-set! 'uptr stmt-cell 0 0)
  (foreign-set! 'uptr tail-cell 0 0)
  (let* ([rc (prepare-v3 db sql-block (bytevector-length bv) 0 stmt-cell tail-cell)]
         [st (foreign-ref 'uptr stmt-cell 0)]
         [tail (foreign-ref 'uptr tail-cell 0)])
    (unless (= st 0) (finalize st))
    (list rc (and (= rc 0) (= st 0)) (if (= tail 0) #f (- tail sql-block)))))

(define ws '(#x20 #x09 #x0a #x0c #x0d))

;; model-empty? : (Listof Byte) Boolean -> Bytevector -> Boolean
;; ADR-0014 decision 4's scan. A whitespace run starts on a byte of WS and
;; continues on a byte of RUN; with BOM?, EF BB BF is whitespace too.
(define (model-empty? run bom?)
  (lambda (bv)
    (let ([n (bytevector-length bv)])
      (define (at i) (bytevector-u8-ref bv i))
      (let loop ([i 0])
        (cond
          [(= i n) #t]
          [(= (at i) #x3b) (loop (+ i 1))]
          [(and bom? (< (+ i 2) n) (= (at i) #xef) (= (at (+ i 1)) #xbb) (= (at (+ i 2)) #xbf))
           (loop (+ i 3))]
          [(memv (at i) ws)
           (let skip ([j (+ i 1)])
             (if (and (< j n) (memv (at j) run)) (skip (+ j 1)) (loop j)))]
          [(and (= (at i) #x2d) (< (+ i 1) n) (= (at (+ i 1)) #x2d))
           (let skip ([j (+ i 2)])
             (cond [(= j n) #t]
                   [(= (at j) #x0a) (loop j)]
                   [else (skip (+ j 1))]))]
          [(and (= (at i) #x2f) (< (+ i 2) n) (= (at (+ i 1)) #x2a))
           (let find ([j (+ i 2)])
             (cond [(>= (+ j 1) n) #t]
                   [(and (= (at j) #x2a) (= (at (+ j 1)) #x2f)) (loop (+ j 2))]
                   [else (find (+ j 1))]))]
          [else #f])))))

(define models
  (list (cons 'as-accepted (model-empty? ws #f))
        (cons 'amended (model-empty? (cons #x0b ws) #t))))

(define (has-nul? bv)
  (let loop ([i 0])
    (and (< i (bytevector-length bv))
         (or (= (bytevector-u8-ref bv i) 0) (loop (+ i 1))))))

;; A tally per model: (name checked mismatches nul-mismatches shown)
(define (fresh-tallies) (map (lambda (m) (vector (car m) 0 0 0 '())) models))
(define tallies (fresh-tallies))

(define (check! bv)
  (let ([sqlite-empty (cadr (sqlite-answer bv))])
    (for-each
     (lambda (m t)
       (let ([model ((cdr m) bv)])
         (vector-set! t 1 (+ (vector-ref t 1) 1))
         (unless (eq? sqlite-empty model)
           (if (has-nul? bv)
               (vector-set! t 3 (+ (vector-ref t 3) 1))
               (begin
                 (vector-set! t 2 (+ (vector-ref t 2) 1))
                 (when (< (length (vector-ref t 4)) 12)
                   (vector-set! t 4 (cons (list (bytevector->u8-list bv) 'sqlite sqlite-empty)
                                          (vector-ref t 4)))))))))
     models tallies)))

(define (report! label)
  (for-each
   (lambda (t)
     (printf "~a, model ~a: checked ~a, mismatches ~a (+ ~a holding a NUL)\n"
             label (vector-ref t 0) (vector-ref t 1) (vector-ref t 2) (vector-ref t 3))
     (for-each (lambda (m) (printf "  ~s\n" m)) (reverse (vector-ref t 4))))
   tallies))

(printf "libversion ~a\n" (libversion))
(let loop ([a 0]) (when (< a 256) (check! (u8-list->bytevector (list a))) (loop (+ a 1))))
(let loop ([a 0])
  (when (< a 256)
    (let inner ([b 0]) (when (< b 256) (check! (u8-list->bytevector (list a b))) (inner (+ b 1))))
    (loop (+ a 1))))
(report! "1- and 2-byte")

(set! tallies (fresh-tallies))
(let loop ([a 0])
  (when (< a 256)
    (let mid ([b 0])
      (when (< b 256)
        (let inner ([c 0]) (when (< c 256) (check! (u8-list->bytevector (list a b c))) (inner (+ c 1))))
        (mid (+ b 1))))
    (loop (+ a 1))))
(report! "3-byte")

;; Every string of 4 to 6 bytes over the bytes the rules name.
(define alphabet '(#x20 #x09 #x0a #x0b #x0c #x0d #x3b #x2d #x2f #x2a #xef #xbb #xbf #x41))
(set! tallies (fresh-tallies))
(let length-loop ([len 4])
  (when (<= len 6)
    (let build ([k len] [acc '()])
      (if (= k 0)
          (check! (u8-list->bytevector acc))
          (for-each (lambda (b) (build (- k 1) (cons b acc))) alphabet)))
    (length-loop (+ len 1))))
(report! "4- to 6-byte, over 14 bytes")

;; Where the tail starts after a first statement.
(for-each (lambda (s)
            (let ([a (sqlite-answer (string->utf8 s))])
              (printf "tail of ~s: rc ~a, tail offset ~a\n" s (car a) (caddr a))))
          '("select 1; select 2" "select 1 ; x" "select 1;;" "select 1 -- c\n; x" "select 1/* c */; x"
            "select 1" "select 1;" "select 1; \v" "select 1;\v"))
(close db)
