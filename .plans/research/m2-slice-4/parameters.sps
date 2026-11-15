;;; M2 slice 4's research, item 3: sqlite3_bind_parameter_index, _count and
;;; _name, and the largest ?NNN each library's prepare accepts.
;;;
;;; Every SQL and every name looked up is written with \x escapes, never as
;;; literal non-ASCII source, and printed as its raw UTF-8 bytes in hex, so
;;; nothing is decoded on the way out (U+FEFF among them: Chez's utf8->string
;;; drops a leading one). For each SQL: the prepare's code, the count, the
;;; name at every index from 0 to count+1 (raw bytes, or NULL), and the index
;;; each lookup answers.
;;;
;;; Every effect is ordered by let*, a named let or for-each (AGENTS.md).
;;;
;;;   scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-slice-4/parameters.sps'
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define libversion (foreign-procedure "sqlite3_libversion" () uptr))
(define sourceid (foreign-procedure "sqlite3_sourceid" () uptr))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (uptr uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare-v3 (foreign-procedure "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define parameter-count (foreign-procedure "sqlite3_bind_parameter_count" (uptr) int))
(define parameter-index (foreign-procedure "sqlite3_bind_parameter_index" (uptr uptr) int))
(define parameter-name (foreign-procedure "sqlite3_bind_parameter_name" (uptr int) uptr))
(define bind-int64 (foreign-procedure "sqlite3_bind_int64" (uptr int integer-64) int))
(define errmsg (foreign-procedure "sqlite3_errmsg" (uptr) uptr))
(define error-offset (foreign-procedure "sqlite3_error_offset" (uptr) int))
(define limit (foreign-procedure "sqlite3_limit" (uptr int int) int))

(define READWRITE #x2)
(define CREATE #x4)
(define MEMORY #x80)
(define EXRESCODE #x02000000)
(define VARIABLE-NUMBER 9)

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

;; index-of : Address Bytevector -> Integer, from a NUL-terminated copy
(define (index-of st name)
  (let* ([p (block-of name)]
         [i (parameter-index st p)])
    (foreign-free p)
    i))

;; param-case : String String (Listof String) -> Void
(define (param-case label sql lookups)
  (let* ([db (open-memory)]
         [bv (string->utf8 sql)]
         [p (prepare db bv)]
         [msg (c-bytes (errmsg db))]
         [st (cadr p)])
    (printf "[~a] SQL ~a~n" label (shown+hex bv))
    (if (= st 0)
        (printf "  prepare ~a, errmsg ~a~n" (car p) (shown msg))
        (let ([n (parameter-count st)])
          (printf "  prepare ~a, count ~a~n" (car p) n)
          (let loop ([i 0])
            (when (<= i (+ n 1))
              (printf "  name ~a: ~a~n" i (shown+hex (c-bytes (parameter-name st i))))
              (loop (+ i 1))))
          (for-each
           (lambda (name)
             (let ([nb (string->utf8 name)])
               (printf "  index of ~a: ~a~n" (shown+hex nb) (index-of st nb))))
           lookups)
          (finalize st)))
    (close db)))

(printf "libversion: ~a~n" (shown (c-bytes (libversion))))
(printf "sourceid: ~a~n" (shown (c-bytes (sourceid))))

;; 3a. Names and indexes.
(param-case "each prefix" "select ?, ?5, :name, @name, $name"
      '("?" "?1" "?5" "?6" ":name" "@name" "$name" "name" ":NAME" "" ":"))
(param-case "names that differ only in prefix" "select :a, @a, $a" '(":a" "@a" "$a" "a"))
(param-case "a name used three times" "select :a, :a, @a, :a" '(":a" "@a"))
(param-case "?1 used twice" "select ?1, ?1, ?2" '("?1" "?2"))
(param-case ":a, then ?1" "select :a, ?1" '(":a" "?1"))
(param-case "?1, then :a" "select ?1, :a" '(":a" "?1" "?2"))
(param-case "?2, then :a" "select ?2, :a" '("?1" "?2" ":a" "?3"))
(param-case "names that differ only in case" "select :a, :A" '(":a" ":A"))
(param-case "multibyte names" "select :\xE9;, @\x540D;\x524D;, $\x3C0;"
      '(":\xE9;" "@\x540D;\x524D;" "$\x3C0;" ":\xC9;" ":e\x301;" ":"))
(param-case "U+FEFF inside a name, and just after its prefix" "select :a\xFEFF;b, :\xFEFF;a"
      '(":a\xFEFF;b" ":ab" ":\xFEFF;a" ":a"))
(param-case "U+FEFF before a name's prefix" "select \xFEFF;:a" '(":a" "\xFEFF;:a"))
(param-case "Tcl-style $ names" "select $a::b, $c(xy)" (quote ("$a::b" "$c(xy)" "$a" "$c")))
(param-case "a space inside a Tcl-style name" "select $c(x y)" (quote ("$c(x y)")))
(param-case "?NNN with leading zeros" "select ?0005, ?5" '("?5" "?0005" "?05"))
(param-case "a name of digits" "select :1, ?1" '(":1" "?1"))
(param-case "one anonymous ?" "select ?" '("?" "" "?1"))
(param-case "no parameters" "select 1" '(":a" ""))

;; 3b. ?NNN against SQLITE_LIMIT_VARIABLE_NUMBER.
(define (nnn db n)
  (let* ([bv (string->utf8 (string-append "select ?" n))]
         [p (prepare db bv)]
         [msg (c-bytes (errmsg db))]
         [off (error-offset db)]
         [st (cadr p)])
    (if (= st 0)
        (printf "  \"select ?~a\": prepare ~a, errmsg ~a, offset ~a~n" n (car p) (shown msg) off)
        (let* ([count (parameter-count st)]
               [b-last (bind-int64 st count 1)]
               [b-past (bind-int64 st (+ count 1) 1)]
               [f (finalize st)])
          (printf "  \"select ?~a\": prepare ~a, count ~a, bind at the count ~a, at count+1 ~a~n"
                  n (car p) count b-last b-past)))))

;; many : Address Symbol Natural -> Void, N parameters, anonymous or named;
;; with N below 1, nothing.
(define (many db what n)
  (if (< n 1)
      (printf "  ~a ~a parameters: not tried~n" n what)
      (many-of db what n)))
(define (many-of db what n)
  (let* ([sql (let loop ([i 1] [acc "select "])
                (if (> i n)
                    acc
                    (loop (+ i 1)
                          (string-append acc (if (= i 1) "" ", ")
                                         (if (eq? what 'anonymous) "?" (string-append ":p" (number->string i)))))))]
         [p (prepare db (string->utf8 sql))]
         [msg (c-bytes (errmsg db))]
         [st (cadr p)]
         [count (if (= st 0) 'none (parameter-count st))]
         [f (if (= st 0) 'none (finalize st))])
    (printf "  ~a ~a parameters: prepare ~a, count ~a, errmsg ~a~n" n what (car p) count (shown msg))))

(let* ([db (open-memory)]
       [lv (limit db VARIABLE-NUMBER -1)]
       [s (lambda (k) (number->string k))])
  (printf "VARIABLE_NUMBER reads ~a~n" lv)
  (for-each (lambda (n) (nnn db n))
            (list (s (- lv 1)) (s lv) (s (+ lv 1)) "0" "00" "2147483648" "99999999999999999999"))
  (close db))
(let* ([db (open-memory)]
       [was (limit db VARIABLE-NUMBER 2147483647)]
       [is (limit db VARIABLE-NUMBER -1)])
  (printf "VARIABLE_NUMBER set to 2147483647: answered ~a, reads ~a~n" was is)
  (nnn db (number->string (+ is 1)))
  (close db))
(for-each
 (lambda (lim)
   (let* ([db (open-memory)]
          [was (limit db VARIABLE-NUMBER lim)]
          [is (limit db VARIABLE-NUMBER -1)])
     (printf "VARIABLE_NUMBER set to ~a: answered ~a, reads ~a~n" lim was is)
     (for-each (lambda (n) (nnn db n))
               (list (number->string (max is 1)) (number->string (+ is 1))))
     (many db 'anonymous is)
     (many db 'anonymous (+ is 1))
     (many db 'named is)
     (many db 'named (+ is 1))
     (close db)))
 '(10 1 0))
