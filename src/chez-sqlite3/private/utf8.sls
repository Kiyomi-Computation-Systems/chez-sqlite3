#!r6rs
;;; (chez-sqlite3 private utf8): the strict UTF-8 decoder, and SQLite's byte
;;; offsets as character indexes (ADR-0015; ADR-0014). Pure: bytes in, data
;;; out, and no function here raises for a value of its stated type, for
;;; they are called where nothing may raise.
;;;
;;; Chez's utf8->string replaces bad bytes with U+FFFD, which hides the bad
;;; text from the caller, so a TEXT value is checked first, by Unicode's
;;; Table 3-7 (Unicode 15, section 3.9), byte by byte:
;;;
;;;   00..7F
;;;   C2..DF   80..BF
;;;   E0       A0..BF   80..BF
;;;   E1..EC   80..BF   80..BF
;;;   ED       80..9F   80..BF
;;;   EE..EF   80..BF   80..BF
;;;   F0       90..BF   80..BF   80..BF
;;;   F1..F3   80..BF   80..BF   80..BF
;;;   F4       80..8F   80..BF   80..BF
;;;
;;; U+0000 is well-formed. An ill-formed sequence's offset is where it starts:
;;; the first byte of the maximal ill-formed subpart, as Python reports it.
(library (chez-sqlite3 private utf8)
  (export utf8-ill-formed-offset strict-utf8->string utf8-offset->index)
  (import (chez-sqlite3 private require-threaded)
          (rnrs))

  ;; sequence-length : Bytevector Natural Natural -> Natural
  ;; The length of the well-formed sequence starting at I of B, whose length
  ;; is N; 0 when the bytes there are no well-formed sequence.
  (define (sequence-length b i n)
    (define (byte k) (bytevector-u8-ref b (+ i k)))
    (define (cont? k lo hi)
      (and (< (+ i k) n) (>= (byte k) lo) (<= (byte k) hi)))
    (let ((lead (byte 0)))
      (cond ((<= lead #x7f) 1)
            ((< lead #xc2) 0)
            ((<= lead #xdf) (if (cont? 1 #x80 #xbf) 2 0))
            ((= lead #xe0)
             (if (and (cont? 1 #xa0 #xbf) (cont? 2 #x80 #xbf)) 3 0))
            ((= lead #xed)
             (if (and (cont? 1 #x80 #x9f) (cont? 2 #x80 #xbf)) 3 0))
            ((<= lead #xef)
             (if (and (cont? 1 #x80 #xbf) (cont? 2 #x80 #xbf)) 3 0))
            ((= lead #xf0)
             (if (and (cont? 1 #x90 #xbf) (cont? 2 #x80 #xbf) (cont? 3 #x80 #xbf)) 4 0))
            ((<= lead #xf3)
             (if (and (cont? 1 #x80 #xbf) (cont? 2 #x80 #xbf) (cont? 3 #x80 #xbf)) 4 0))
            ((= lead #xf4)
             (if (and (cont? 1 #x80 #x8f) (cont? 2 #x80 #xbf) (cont? 3 #x80 #xbf)) 4 0))
            (else 0))))

  ;; utf8-ill-formed-offset : Bytevector -> (U Natural #f)
  ;; #f when B is well-formed UTF-8 by Table 3-7; else the offset where the
  ;; first maximal ill-formed subpart starts: everything before it is
  ;; well-formed, so it is the start of the first sequence that fails.
  (define (utf8-ill-formed-offset b)
    (let ((n (bytevector-length b)))
      (let loop ((i 0))
        (if (= i n)
            #f
            (let ((len (sequence-length b i n)))
              (if (= len 0) i (loop (+ i len))))))))

  ;; strict-utf8->string : Bytevector -> (U String (List 'invalid Natural))
  ;; (utf8->string B) when B is well-formed, where Chez's is exact except that
  ;; it drops one leading U+FEFF (EF BB BF), measured on 10.4.0: then the
  ;; character is put back. Else (invalid OFFSET) by utf8-ill-formed-offset.
  (define (strict-utf8->string b)
    (let ((offset (utf8-ill-formed-offset b)))
      (cond (offset (list 'invalid offset))
            ((and (>= (bytevector-length b) 3)
                  (= (bytevector-u8-ref b 0) #xef)
                  (= (bytevector-u8-ref b 1) #xbb)
                  (= (bytevector-u8-ref b 2) #xbf))
             (string-append (string #\xFEFF) (utf8->string b)))
            (else (utf8->string b)))))

  ;; utf8-offset->index : Bytevector Integer -> (U Natural #f)
  ;; SQLite's byte OFFSET into the SQL whose UTF-8 is B as a character index
  ;; into the SQL's string. B should be well-formed, being string->utf8
  ;; of the SQL. An offset at a character's first byte, or at the end,
  ;; answers the characters before it; at a continuation byte, the index of
  ;; the character it belongs to. #f for -1, for any other offset below 0 or
  ;; above the length, and for a non-integer. On ill-formed bytes it still
  ;; answers its type: a continuation byte with no lead before it belongs to
  ;; no character, and answers #f.
  (define (utf8-offset->index b offset)
    (let ((n (bytevector-length b)))
      (and (integer? offset) (exact? offset) (>= offset 0) (<= offset n)
           (let loop ((i 0) (starts 0))
             (if (= i offset)
                 (if (and (< offset n) (continuation? (bytevector-u8-ref b offset)))
                     (and (> starts 0) (- starts 1))
                     starts)
                 (loop (+ i 1)
                       (if (continuation? (bytevector-u8-ref b i)) starts (+ starts 1))))))))

  ;; continuation? : Byte -> Boolean
  (define (continuation? byte) (= (bitwise-and byte #xc0) #x80)))
