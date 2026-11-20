#!r6rs
;;; The suite for (chez-sqlite3 private utf8): the strict UTF-8 decoder
;;; and SQLite's byte offsets as character indexes. It loads no
;;; libsqlite3: the library is pure.
;;;
;;;   the offsets    utf8-ill-formed-offset: #f for a well-formed bytevector,
;;;                  else where the first maximal ill-formed subpart starts
;;;                  (Unicode 3.9, Table 3-7), the way Python reports it
;;;   1 and 2 bytes  every input of one byte (256) and of two (65,536)
;;;                  against an oracle built without the range table: a
;;;                  2-byte input is well-formed when both bytes are below
;;;                  80, or it is string->utf8 of one scalar value
;;;   3 and 4 bytes  each form's range edges: for every row of the table and
;;;                  every byte position, min-1, min, max and max+1, the
;;;                  other bytes at a valid mid value, against an oracle that
;;;                  re-encodes what it decodes
;;;   every position each form, ill-formed and well-formed, at every offset
;;;                  0 to 19 of a run of ASCII, with a suffix and without
;;;   strict-utf8->string
;;;                  the string, or (invalid OFFSET): round trips over the
;;;                  boundary scalar values, and Chez's utf8->string, which
;;;                  replaces bad bytes with U+FFFD, shown to differ
;;;   utf8-offset->index
;;;                  a byte offset as a character index, at every offset of a
;;;                  string of 1-, 2-, 3- and 4-byte characters
;;;
;;; Every function here is total, so every call is made under a guard that
;;; answers a symbol of its own. An answer of #f is read as the symbol none:
;;; SRFI-64 turns a raise in the actual expression into #f.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) library-exports)
        (chez-sqlite3-testing)
        (chez-sqlite3 private utf8))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (write (test-result-ref r 'expected-value))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r 'actual-value))
        (newline)))))

;; sorted-names : (Listof Symbol) -> (Listof Symbol)
(define (sorted-names names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

;; bv : Byte ... -> Bytevector
(define (bv . bytes) (u8-list->bytevector bytes))

;; offset-of : Bytevector -> (U Natural 'none (raised TEXT))
;; utf8-ill-formed-offset's answer, #f as none.
(define (offset-of b)
  (guard (e (#t (list 'raised (describe e))))
    (let ((o (utf8-ill-formed-offset b))) (if (eq? o #f) 'none o))))

;; index-of : Bytevector Integer -> (U Natural 'none (raised TEXT))
(define (index-of b off)
  (guard (e (#t (list 'raised (describe e))))
    (let ((o (utf8-offset->index b off))) (if (eq? o #f) 'none o))))

;; iota : Natural -> (Listof Natural)
(define (iota n)
  (let loop ((i (- n 1)) (acc '()))
    (if (< i 0) acc (loop (- i 1) (cons i acc)))))

;; ascii-run : Natural -> Bytevector
;; N bytes of ASCII, none of them a continuation or a lead.
(define (ascii-run n) (make-bytevector n 97))

;; bv-append : Bytevector ... -> Bytevector
(define (bv-append . parts)
  (u8-list->bytevector (apply append (map bytevector->u8-list parts))))

;; --- the independent oracle: re-encoding ---------------------------------------------------

;; lead-length : Byte -> (U 1 2 3 4 #f)
;; How many bytes a lead byte claims; #f for a continuation byte and for F8 to FF.
(define (lead-length b)
  (cond ((< b #x80) 1) ((< b #xc0) #f) ((< b #xe0) 2) ((< b #xf0) 3) ((< b #xf8) 4) (else #f)))

;; scalar? : Natural -> Boolean
(define (scalar? cp) (and (<= cp #x10ffff) (not (and (>= cp #xd800) (<= cp #xdfff)))))

;; decodes-at? : Bytevector Natural -> (U Natural #f)
;; The length of the character at I when the bytes there, as the lead says,
;; have the right structure bits, give a scalar value, and string->utf8 of
;; that one character gives the same bytes back (no overlong form); else #f.
(define (decodes-at? b i)
  (let* ((n (bytevector-length b))
         (len (lead-length (bytevector-u8-ref b i))))
    (and len
         (<= (+ i len) n)
         (let loop ((k 1))
           (or (= k len)
               (and (= (bitwise-and (bytevector-u8-ref b (+ i k)) #xc0) #x80) (loop (+ k 1)))))
         (let* ((lead (bytevector-u8-ref b i))
                (cp (let loop ((k 1)
                               (acc (bitwise-and lead (case len ((1) #x7f) ((2) #x1f) ((3) #x0f)
                                                        (else #x07)))))
                      (if (= k len)
                          acc
                          (loop (+ k 1)
                                (bitwise-ior (bitwise-arithmetic-shift-left acc 6)
                                             (bitwise-and (bytevector-u8-ref b (+ i k)) #x3f)))))))
           (and (scalar? cp)
                (let ((again (string->utf8 (string (integer->char cp)))))
                  (and (= (bytevector-length again) len)
                       (let loop ((k 0))
                         (or (= k len)
                             (and (= (bytevector-u8-ref again k) (bytevector-u8-ref b (+ i k)))
                                  (loop (+ k 1)))))))
                len)))))

;; oracle-offset : Bytevector -> (U Natural 'none)
;; The first offset whose character does not decode, else none.
(define (oracle-offset b)
  (let ((n (bytevector-length b)))
    (let loop ((i 0))
      (cond ((= i n) 'none)
            ((decodes-at? b i) => (lambda (len) (loop (+ i len))))
            (else i)))))

(test-begin "utf8")

(test-equal "(chez-sqlite3 private utf8) exports exactly the offset, the string decoder and the index conversion"
  (sorted-names '(utf8-ill-formed-offset strict-utf8->string utf8-offset->index))
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3 private utf8)))))

;; --- the brief's expected offsets ---------------------------------------------------------------

(test-equal "E0 80 80, C2 41, a final E1 80, a lone 80 and F5 are ill-formed at 0; 41 80 at 1"
  '(0 0 0 0 0 1)
  (map offset-of (list (bv #xe0 #x80 #x80) (bv #xc2 #x41) (bv #xe1 #x80) (bv #x80) (bv #xf5)
                       (bv #x41 #x80))))

(test-equal "the empty bytevector, U+0000 and ASCII are well-formed"
  '(none none none none)
  (map offset-of (list (bv) (bv 0) (bv 0 0 0) (string->utf8 "select 1 from t"))))

(test-equal "each table row's smallest and largest well-formed sequence is well-formed"
  (map (lambda (b) 'none)
       '(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22))
  (map offset-of
       (list (bv #x7f) (bv #xc2 #x80) (bv #xdf #xbf) (bv #xe0 #xa0 #x80) (bv #xe0 #xbf #xbf)
             (bv #xe1 #x80 #x80) (bv #xec #xbf #xbf) (bv #xed #x80 #x80) (bv #xed #x9f #xbf)
             (bv #xee #x80 #x80) (bv #xef #xbf #xbf) (bv #xf0 #x90 #x80 #x80)
             (bv #xf0 #xbf #xbf #xbf) (bv #xf1 #x80 #x80 #x80) (bv #xf3 #xbf #xbf #xbf)
             (bv #xf4 #x80 #x80 #x80) (bv #xf4 #x8f #xbf #xbf) (bv #xef #xbf #xbe)
             (bv #xef #xbf #xbd) (bv #xef #xbf #xbf) (bv #xf4 #x8f #xbf #xbe)
             (bv #xc2 #xbf))))

(test-equal "the neighbours of each row, one past its edge, are ill-formed at 0: overlong E0 9F, ED A0 surrogate, F0 8F, F4 90, C1, F5, C0 80"
  '(0 0 0 0 0 0 0 0 0 0 0)
  (map offset-of
       (list (bv #xe0 #x9f #xbf) (bv #xed #xa0 #x80) (bv #xed #xbf #xbf) (bv #xf0 #x8f #xbf #xbf)
             (bv #xf4 #x90 #x80 #x80) (bv #xc1 #xbf) (bv #xf5 #x80 #x80 #x80) (bv #xc0 #x80)
             (bv #xff) (bv #xfe) (bv #xf8 #x88 #x80 #x80 #x80))))

(test-equal "a maximal ill-formed subpart: the offset is where the failing sequence starts, not where its first bad byte is"
  '(1 1 1 2 2 3 3 4)
  (map offset-of
       (list (bv 97 #xe1 #x41) (bv 97 #xe1 #x80 #x41) (bv 97 #xf0 #x90 #x41)
             (bv 97 98 #xc2 #xc2) (bv 97 98 #xf4 #x90) (bv 97 98 99 #xed #xa0)
             (bv 97 98 99 #xc1) (bv 97 98 99 100 #xe0 #x80))))

;; --- every 1-byte input and every 2-byte input ---------------------------------------------------

(test-equal "every 1-byte input: well-formed exactly when below 80, else ill-formed at 0"
  '()
  (let loop ((b 0) (bad '()))
    (if (= b 256)
        (reverse bad)
        (loop (+ b 1)
              (if (equal? (offset-of (bv b)) (if (< b #x80) 'none 0)) bad (cons b bad))))))

;; The 2-byte inputs a well-formed 2-byte sequence can be: string->utf8 of each
;; scalar value from U+0080 to U+07FF, built with no range table.
(define two-byte-scalars (make-vector 65536 #f))
(let loop ((cp #x80))
  (when (<= cp #x7ff)
    (let ((e (string->utf8 (string (integer->char cp)))))
      (vector-set! two-byte-scalars (+ (* 256 (bytevector-u8-ref e 0)) (bytevector-u8-ref e 1)) #t))
    (loop (+ cp 1))))

(test-equal "the oracle's own set holds exactly the 1,920 two-byte forms of U+0080 to U+07FF"
  1920
  (let loop ((i 0) (n 0))
    (if (= i 65536) n (loop (+ i 1) (if (vector-ref two-byte-scalars i) (+ n 1) n)))))

;; expected-2 : Byte Byte -> (U Natural 'none)
(define (expected-2 a b)
  (cond ((and (< a #x80) (< b #x80)) 'none)
        ((vector-ref two-byte-scalars (+ (* 256 a) b)) 'none)
        ((< a #x80) 1)
        (else 0)))

(test-equal "every 2-byte input, 65,536 of them: the offset agrees with the scalar-value oracle, mismatches listed"
  '()
  (let outer ((a 0) (bad '()))
    (if (= a 256)
        (reverse bad)
        (outer (+ a 1)
               (let inner ((b 0) (bad bad))
                 (if (= b 256)
                     bad
                     (inner (+ b 1)
                            (if (equal? (offset-of (bv a b)) (expected-2 a b))
                                bad
                                (if (< (length bad) 8) (cons (list a b) bad) bad)))))))))

(test-equal "the 2-byte oracle itself: 1,920 + 16,384 (both below 80) well-formed, of 65,536"
  (+ 1920 (* 128 128))
  (let outer ((a 0) (n 0))
    (if (= a 256)
        n
        (outer (+ a 1)
               (let inner ((b 0) (n n))
                 (if (= b 256) n (inner (+ b 1) (if (eq? (expected-2 a b) 'none) (+ n 1) n))))))))

;; --- the range edges of every row of Table 3-7 -----------------------------------------------------

;; A row: the byte ranges of its positions, (min . max) each.
(define rows
  '(((#xe0 . #xe0) (#xa0 . #xbf) (#x80 . #xbf))
    ((#xe1 . #xec) (#x80 . #xbf) (#x80 . #xbf))
    ((#xed . #xed) (#x80 . #x9f) (#x80 . #xbf))
    ((#xee . #xef) (#x80 . #xbf) (#x80 . #xbf))
    ((#xf0 . #xf0) (#x90 . #xbf) (#x80 . #xbf) (#x80 . #xbf))
    ((#xf1 . #xf3) (#x80 . #xbf) (#x80 . #xbf) (#x80 . #xbf))
    ((#xf4 . #xf4) (#x80 . #x8f) (#x80 . #xbf) (#x80 . #xbf))
    ((#xc2 . #xdf) (#x80 . #xbf))))

;; mid : (Pair Byte Byte) -> Byte
(define (mid range) (div (+ (car range) (cdr range)) 2))

;; edge-inputs : Row -> (Listof Bytevector)
;; For each position, min-1, min, max and max+1 where they lie in 00..FF, the
;; other positions at their range's mid.
(define (edge-inputs row)
  (let ((mids (map mid row)))
    (let loop ((p 0) (acc '()))
      (if (= p (length row))
          (reverse acc)
          (let* ((r (list-ref row p))
                 (values (filter (lambda (v) (and (>= v 0) (<= v 255)))
                                 (list (- (car r) 1) (car r) (cdr r) (+ (cdr r) 1)))))
            (loop (+ p 1)
                  (append (reverse
                           (map (lambda (v)
                                  (u8-list->bytevector
                                   (let fill ((k 0) (ms mids))
                                     (if (null? ms)
                                         '()
                                         (cons (if (= k p) v (car ms)) (fill (+ k 1) (cdr ms)))))))
                                values))
                          acc)))))))

(test-equal "a row's edge set: the 3-byte row E1..EC has 4 values at each of 3 positions, 12 inputs"
  12
  (length (edge-inputs (cadr rows))))

(test-equal "the edge sets of the 8 rows: four inputs for each position, so 12 for a 3-byte row, 16 for a 4-byte row and 8 for the 2-byte one"
  '(12 12 12 12 16 16 16 8)
  (map (lambda (row) (length (edge-inputs row))) rows))

(test-equal "every edge input of every row: the offset agrees with the re-encoding oracle, mismatches listed"
  '()
  (let loop ((inputs (apply append (map edge-inputs rows))) (bad '()))
    (if (null? inputs)
        (reverse bad)
        (loop (cdr inputs)
              (if (equal? (offset-of (car inputs)) (oracle-offset (car inputs)))
                  bad
                  (cons (bytevector->u8-list (car inputs)) bad))))))

(test-equal "the edge inputs hold both kinds: well-formed ones, and ill-formed ones at 0 and at a later offset"
  '(#t #t #t)
  (let* ((inputs (apply append (map edge-inputs rows)))
         (offsets (map offset-of inputs)))
    (list (and (memq 'none offsets) #t) (and (memv 0 offsets) #t)
          (and (exists (lambda (o) (and (number? o) (> o 0))) offsets) #t))))

(test-equal "the oracle agrees with the 2-byte set it was not built from, on every 2-byte input"
  '()
  (let outer ((a 0) (bad '()))
    (if (= a 256)
        (reverse bad)
        (outer (+ a 1)
               (let inner ((b 0) (bad bad))
                 (if (= b 256)
                     bad
                     (inner (+ b 1)
                            (if (equal? (oracle-offset (bv a b)) (expected-2 a b))
                                bad
                                (if (< (length bad) 8) (cons (list a b) bad) bad)))))))))

;; --- every position -------------------------------------------------------------------------------

;; Forms, each with the offset of its first ill-formed subpart inside it, or
;; none, written out by hand from Table 3-7.
(define forms
  (list
   ;; well-formed
   (cons (bv #x41) 'none) (cons (bv 0) 'none) (cons (bv #x7f) 'none)
   (cons (bv #xc2 #x80) 'none) (cons (bv #xdf #xbf) 'none)
   (cons (bv #xe0 #xa0 #x80) 'none) (cons (bv #xe0 #xbf #xbf) 'none)
   (cons (bv #xe1 #x80 #x80) 'none) (cons (bv #xec #xbf #xbf) 'none)
   (cons (bv #xed #x80 #x80) 'none) (cons (bv #xed #x9f #xbf) 'none)
   (cons (bv #xee #x80 #x80) 'none) (cons (bv #xef #xbf #xbf) 'none)
   (cons (bv #xf0 #x90 #x80 #x80) 'none) (cons (bv #xf0 #xbf #xbf #xbf) 'none)
   (cons (bv #xf1 #x80 #x80 #x80) 'none) (cons (bv #xf3 #xbf #xbf #xbf) 'none)
   (cons (bv #xf4 #x80 #x80 #x80) 'none) (cons (bv #xf4 #x8f #xbf #xbf) 'none)
   ;; ill-formed
   (cons (bv #x80) 0) (cons (bv #xbf) 0) (cons (bv #xc0 #x80) 0) (cons (bv #xc1 #xbf) 0)
   (cons (bv #xc2 #x41) 0) (cons (bv #xc2 #xc0) 0) (cons (bv #xdf #x7f) 0)
   (cons (bv #xe0 #x80 #x80) 0) (cons (bv #xe0 #x9f #xbf) 0) (cons (bv #xe0 #xa0 #x41) 0)
   (cons (bv #xe1 #x7f #x80) 0) (cons (bv #xe1 #x80 #xc0) 0) (cons (bv #xe1 #x80) 0)
   (cons (bv #xed #xa0 #x80) 0) (cons (bv #xed #xbf #xbf) 0) (cons (bv #xee #xc0 #x80) 0)
   (cons (bv #xef #xbf #x41) 0)
   (cons (bv #xf0 #x80 #x80 #x80) 0) (cons (bv #xf0 #x8f #xbf #xbf) 0)
   (cons (bv #xf0 #x90 #x80 #x41) 0) (cons (bv #xf1 #x80 #x80 #x41) 0)
   (cons (bv #xf4 #x90 #x80 #x80) 0) (cons (bv #xf4 #x80 #x80 #xc0) 0)
   (cons (bv #xf5 #x80 #x80 #x80) 0) (cons (bv #xf8) 0) (cons (bv #xff) 0)
   (cons (bv #xf0 #x90 #x80) 0) (cons (bv #xf4 #x8f) 0) (cons (bv #xe1) 0) (cons (bv #xc2) 0)
   ;; ill-formed after a well-formed start
   (cons (bv #x41 #x80) 1) (cons (bv #xc2 #x80 #x80) 2) (cons (bv #xe1 #x80 #x80 #x80) 3)
   (cons (bv #xf1 #x80 #x80 #x80 #xbf) 4) (cons (bv #x41 #x42 #xe0 #x80) 2)))

(define wf-forms (filter (lambda (f) (eq? (cdr f) 'none)) forms))
(define bad-forms (filter (lambda (f) (not (eq? (cdr f) 'none))) forms))

(test-equal "the forms: 19 well-formed and 35 ill-formed"
  '(19 35)
  (list (length wf-forms) (length bad-forms)))

(test-equal "the hand-written offsets agree with the re-encoding oracle on every form"
  '()
  (filter (lambda (f) (not (equal? (oracle-offset (car f)) (cdr f)))) forms))

;; embedded : Bytevector Natural Bytevector -> Bytevector
;; FORM after K bytes of ASCII, then SUFFIX.
(define (embedded form k suffix) (bv-append (ascii-run k) form suffix))

(define positions (iota 20))

(test-equal "every form at every offset 0 to 19 of a run of ASCII, no suffix: the form's own offset plus the run's, mismatches listed"
  '()
  (let loop ((fs forms) (bad '()))
    (if (null? fs)
        (reverse bad)
        (loop (cdr fs)
              (append (filter
                       (lambda (x) x)
                       (map (lambda (k)
                              (let ((expected (if (eq? (cdar fs) 'none) 'none (+ k (cdar fs))))
                                    (got (offset-of (embedded (caar fs) k (bv)))))
                                (and (not (equal? got expected))
                                     (list (bytevector->u8-list (caar fs)) k got))))
                            positions))
                      bad)))))

(test-equal "every form at every offset 0 to 19, with an ASCII suffix: the same offsets, a suffix changing none"
  '()
  (let loop ((fs forms) (bad '()))
    (if (null? fs)
        (reverse bad)
        (loop (cdr fs)
              (append (filter
                       (lambda (x) x)
                       (map (lambda (k)
                              (let ((expected (if (eq? (cdar fs) 'none) 'none (+ k (cdar fs))))
                                    (got (offset-of (embedded (caar fs) k (string->utf8 "zz")))))
                                (and (not (equal? got expected))
                                     (list (bytevector->u8-list (caar fs)) k got))))
                            positions))
                      bad)))))

(test-equal "a well-formed form followed by an ill-formed one gives the second one's offset, at every position of both"
  '()
  (let loop ((ws wf-forms) (bad '()))
    (if (null? ws)
        (reverse bad)
        (loop (cdr ws)
              (append
               (filter
                (lambda (x) x)
                (apply append
                       (map (lambda (b)
                              (map (lambda (k)
                                     (let ((expected (+ k (bytevector-length (caar ws)) (cdr b)))
                                           (got (offset-of (embedded (bv-append (caar ws) (car b))
                                                                     k (bv)))))
                                       (and (not (equal? got expected))
                                            (list (bytevector->u8-list (caar ws))
                                                  (bytevector->u8-list (car b)) k got))))
                                   '(0 1 2 5 17)))
                            bad-forms)))
               bad)))))

(test-equal "two ill-formed forms in a row: the first one's offset"
  '(0 3 4)
  (map offset-of (list (bv #x80 #x80) (bv 97 98 99 #xc0 #x80 #xe0) (bv 97 98 99 100 #xff #x80))))

;; --- strict-utf8->string ------------------------------------------------------------------------------

;; strict : Bytevector -> Any
(define (strict b) (guard (e (#t (list 'raised (describe e)))) (strict-utf8->string b)))

(define boundary-scalars
  '(#x0 #x7f #x80 #x7ff #x800 #xd7ff #xe000 #xfeff #xfffd #xfffe #xffff #x10000 #x10ffff))

;; U+FEFF, the byte order mark, is the one scalar value Chez's utf8->string
;; does not decode alone: it drops one leading EF BB BF (measured on 10.4.0).

(test-equal "strict-utf8->string round trips each boundary scalar value, alone"
  (map (lambda (cp) (string (integer->char cp))) boundary-scalars)
  (map (lambda (cp) (strict (string->utf8 (string (integer->char cp))))) boundary-scalars))

(test-equal "strict-utf8->string round trips each boundary scalar value at the start, the middle and the end of a string"
  (map (lambda (cp)
         (let ((c (string (integer->char cp))))
           (list (string-append c "ab") (string-append "a" c "b") (string-append "ab" c))))
       boundary-scalars)
  (map (lambda (cp)
         (let ((c (string (integer->char cp))))
           (map (lambda (s) (strict (string->utf8 s)))
                (list (string-append c "ab") (string-append "a" c "b") (string-append "ab" c)))))
       boundary-scalars))

(test-equal "strict-utf8->string keeps every U+FEFF, leading ones included: alone, repeated, first, last and apart"
  (list "\xFEFF;" "\xFEFF;a" "\xFEFF;\xFEFF;a" "a\xFEFF;" "\xFEFF;\xFEFF;" "\xFEFF;a\xFEFF;"
        "\xFEFF;\xFEFF;\xFEFF;")
  (map (lambda (s) (strict (string->utf8 s)))
       (list "\xFEFF;" "\xFEFF;a" "\xFEFF;\xFEFF;a" "a\xFEFF;" "\xFEFF;\xFEFF;" "\xFEFF;a\xFEFF;"
             "\xFEFF;\xFEFF;\xFEFF;")))

(test-equal "strict-utf8->string of the bytes EF BB BF alone is one character, not the empty string"
  (list (string (integer->char #xfeff)) 1)
  (let ((s (strict (bv #xef #xbb #xbf)))) (list s (if (string? s) (string-length s) s))))

(test-equal "strict-utf8->string round trips every scalar value alone, U+0000 to U+10FFFF, surrogates excluded"
  '()
  (let loop ((cp 0) (bad '()))
    (cond ((> cp #x10ffff) (reverse bad))
          ((and (>= cp #xd800) (<= cp #xdfff)) (loop (+ cp 1) bad))
          (else
           (let ((s (string (integer->char cp))))
             (loop (+ cp 1) (if (equal? (strict (string->utf8 s)) s) bad (cons cp bad))))))))

(test-equal "strict-utf8->string round trips the boundary values together, and between ASCII"
  (list (list->string (map integer->char boundary-scalars))
        (string-append "a" (list->string (map integer->char boundary-scalars)) "z"))
  (list (strict (string->utf8 (list->string (map integer->char boundary-scalars))))
        (strict (string->utf8 (string-append "a" (list->string (map integer->char boundary-scalars))
                                             "z")))))

(test-equal "strict-utf8->string round trips a spread of scalar values, every 257th from 0 to U+10FFFF, surrogates skipped"
  '()
  (let loop ((cp 0) (bad '()))
    (cond ((> cp #x10ffff) (reverse bad))
          ((and (>= cp #xd800) (<= cp #xdfff)) (loop (+ cp 257) bad))
          (else
           (let ((s (string (integer->char cp))))
             (loop (+ cp 257) (if (equal? (strict (string->utf8 s)) s) bad (cons cp bad))))))))

(test-equal "strict-utf8->string answers the empty string for no bytes, and keeps a U+0000"
  '("" "a\x0;b" "\x0;")
  (map strict (list (bv) (bv 97 0 98) (bv 0))))

(test-equal "strict-utf8->string answers (invalid OFFSET) for ill-formed input, the offset utf8-ill-formed-offset gives"
  '((invalid 0) (invalid 1) (invalid 0) (invalid 3) (invalid 2))
  (map strict (list (bv #xc3 #x28) (bv #x41 #x80) (bv #xed #xa0 #x80) (bv 97 98 99 #xff)
                    (bv 97 98 #xe2 #x82))))

;; Chez's utf8->string replaces what it cannot decode with U+FFFD (measured).
(test-equal "utf8->string replaces bad bytes with U+FFFD and answers a string; strict-utf8->string answers the refusal instead"
  '(("\xfffd;(" (invalid 0)) ("a\xfffd;" (invalid 1)) ("\xfffd;" (invalid 0)))
  (map (lambda (b) (list (guard (e (#t (list 'raised (describe e)))) (utf8->string b)) (strict b)))
       (list (bv #xc3 #x28) (bv 97 #x80) (bv #xed #xa0))))

(test-equal "on well-formed input strict-utf8->string is utf8->string: ASCII, 2-, 3- and 4-byte characters"
  (list "select 1" "\xe9;\x20ac;\x1d11e;" "\x10ffff;")
  (map (lambda (b) (let ((s (strict b)) (u (utf8->string b))) (if (equal? s u) s (list s u))))
       (list (string->utf8 "select 1") (string->utf8 "\xe9;\x20ac;\x1d11e;")
             (string->utf8 "\x10ffff;"))))

;; --- utf8-offset->index --------------------------------------------------------------------------------

;; The brief's example: SQLite's error offset for "select 'é', nosuchcol"
;; is 13 (bytes), the token at character 12.
(define sql-e (string->utf8 "select '\xe9;', nosuchcol"))

(test-equal "a token after a 2-byte character: byte 13 is character 12; the SQL is 22 bytes and 21 characters; the é starts at byte 8, continues at 9, and byte 10 is character 9"
  '(12 22 21 21 8 8 9)
  (list (index-of sql-e 13) (bytevector-length sql-e) (string-length "select '\xe9;', nosuchcol")
        (index-of sql-e 22) (index-of sql-e 8) (index-of sql-e 9) (index-of sql-e 10)))

;; One character of each length, then ASCII: "a" "é" "€" "𝄞" "z".
(define mixed (string->utf8 "a\xe9;\x20ac;\x1d11e;z"))

(test-equal "the mixed string is 1 + 2 + 3 + 4 + 1 = 11 bytes"
  11
  (bytevector-length mixed))

;; Offsets 0 to 11: 0 a, 1 é-lead, 2 é-cont, 3 €-lead, 4 €-cont, 5 €-cont,
;; 6 𝄞-lead, 7, 8, 9 𝄞-conts, 10 z, 11 the end.
(test-equal "every offset of the mixed string: a first byte answers the characters before it, a continuation byte the character it belongs to, the end the length"
  '(0 1 1 2 2 2 3 3 3 3 4 5)
  (map (lambda (o) (index-of mixed o)) (iota 12)))

;; The continuation bytes at both ends of 80..BF: U+0080 is C2 80, U+00BF is
;; C2 BF, U+07FF is DF BF, U+FFFF is EF BF BF.
(define edges (string->utf8 "\x80;\xbf;\x7ff;\xffff;"))

(test-equal "the continuation bytes 80 and BF count as continuations: every offset of U+0080, U+00BF, U+07FF and U+FFFF, 9 bytes"
  '(9 (0 0 1 1 2 2 3 3 3 4))
  (list (bytevector-length edges) (map (lambda (o) (index-of edges o)) (iota 10))))

(test-equal "an offset below -1, -1 itself, past the length and one past it answer none"
  '(none none none none none none)
  (list (index-of mixed -1) (index-of mixed -2) (index-of mixed -100) (index-of mixed 12)
        (index-of mixed 13) (index-of mixed 100000000000000000000)))

(test-equal "the empty string: offset 0 is character 0, and 1 and -1 are none"
  '(0 none none)
  (list (index-of (bv) 0) (index-of (bv) 1) (index-of (bv) -1)))

(test-equal "ASCII: an offset is its own index, at every offset and at the end"
  (iota 9)
  (map (lambda (o) (index-of (string->utf8 "select 1") o)) (iota 9)))

(test-equal "a string of 2-byte characters: offsets 0 to 6 answer 0 0 1 1 2 2 3"
  '(0 0 1 1 2 2 3)
  (map (lambda (o) (index-of (string->utf8 "\xe9;\xe9;\xe9;") o)) (iota 7)))

(test-equal "a string of 4-byte characters: offsets 0 to 8 answer 0 0 0 0 1 1 1 1 2"
  '(0 0 0 0 1 1 1 1 2)
  (map (lambda (o) (index-of (string->utf8 "\x1d11e;\x1d11e;") o)) (iota 9)))

(test-equal "a non-integer or inexact offset answers none and raises nothing: 1.5, 2.0, a symbol, #f, a string"
  '(none none none none none)
  (list (index-of mixed 1.5) (index-of mixed 2.0) (index-of mixed 'x) (index-of mixed #f)
        (index-of mixed "1")))

;; Ill-formed bytes are outside the function's contract, but it still answers
;; its stated type: a continuation byte with no lead before it has no
;; character, so #f, never -1.
(test-equal "a continuation byte with no lead before it answers none, not -1: 80 at 0, 80 80 at 0 and 1, BF at 0"
  '(none none none none)
  (list (index-of (bv #x80) 0) (index-of (bv #x80 #x80) 0) (index-of (bv #x80 #x80) 1)
        (index-of (bv #xbf) 0)))

(test-end "utf8")

(exit (suite-exit-status runner))
