#!r6rs
;;; (chez-sqlite3 private sql-tail): the scan of what follows a prepared
;;; statement's first statement (ADR-0014). prepare compiles the first
;;; statement and leaves the rest, so a caller who gave one statement's SQL
;;; needs to know that the rest holds nothing: only whitespace, comments and
;;; semicolons, as SQLite's tokenizer counts them. Pure, total, and it raises
;;; nothing: it is called where nothing may raise.
;;;
;;; What the scan lets pass, each as a token of its own:
;;;
;;;   a whitespace run   starts on 20 09 0A 0C 0D and continues on those or 0B
;;;   EF BB BF           U+FEFF, wherever it stands
;;;   --                 up to the next 0A, which is not consumed, or the end
;;;   /*                 with at least one byte after it, to just past the
;;;                      first */ whose * is at or after the byte following
;;;                      the /*, or to the end
;;;   ;
;;;
;;; Anything else, a 0B or a 00 among it, is where the scan answers. SQL
;;; holding U+0000 is refused before it is scanned (ADR-0011).
(library (chez-sqlite3 private sql-tail)
  (export sql-tail-statement)
  (import (chez-sqlite3 private require-threaded)
          (rnrs))

  ;; blank-start? : Byte -> Boolean
  ;; Whether a whitespace run may start on BYTE: space, tab, newline, form
  ;; feed, carriage return.
  (define (blank-start? b) (and (memv b '(#x20 #x09 #x0a #x0c #x0d)) #t))

  ;; blank-continue? : Byte -> Boolean
  ;; Whether a whitespace run goes on over BYTE: the five, and 0B.
  (define (blank-continue? b) (or (blank-start? b) (= b #x0b)))

  ;; sql-tail-statement : Bytevector Natural -> (U Natural #f)
  ;; #f when everything of BV from START on is whitespace, U+FEFF, comments
  ;; and semicolons; else the offset of the first byte that starts anything
  ;; else. A START at or past the length gives #f.
  (define (sql-tail-statement bv start)
    (let ((n (bytevector-length bv)))
      (define (at i) (bytevector-u8-ref bv i))
      (let loop ((i start))
        (if (>= i n)
            #f
            (let ((b (at i)))
              (cond
                ((= b #x3b) (loop (+ i 1)))
                ((blank-start? b)
                 (let run ((j (+ i 1)))
                   (if (and (< j n) (blank-continue? (at j))) (run (+ j 1)) (loop j))))
                ((and (= b #xef) (< (+ i 2) n) (= (at (+ i 1)) #xbb) (= (at (+ i 2)) #xbf))
                 (loop (+ i 3)))
                ((and (= b #x2d) (< (+ i 1) n) (= (at (+ i 1)) #x2d))
                 (let line ((j (+ i 2)))
                   (if (or (= j n) (= (at j) #x0a)) (loop j) (line (+ j 1)))))
                ((and (= b #x2f) (< (+ i 2) n) (= (at (+ i 1)) #x2a))
                 (let block ((j (+ i 2)))
                   (cond ((>= (+ j 1) n) (loop n))
                         ((and (= (at j) #x2a) (= (at (+ j 1)) #x2f)) (loop (+ j 2)))
                         (else (block (+ j 1))))))
                (else i))))))))
