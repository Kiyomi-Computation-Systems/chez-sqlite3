#!r6rs
;;; The suite for (chez-sqlite3 private script): where execute-script!'s
;;; error points, in characters of the whole script (ADR-0016, decision 7;
;;; ADR-0013, amended for M3; the M3 plan, section 4.1). It loads no
;;; libsqlite3: the loop that calls these is M3 slice 3's.
;;;
;;;   script-prepare-offset  a prepare that started at byte START of the
;;;                          script's UTF-8 and failed with SQLite's byte
;;;                          OFFSET from START: the character it points at;
;;;                          for -1, which points at none, the statement's
;;;                          first token, as script-step-offset answers it
;;;   script-step-offset     a step that failed, of the statement whose
;;;                          prepare started at START: its first token, past
;;;                          the whitespace, U+FEFF, comments and semicolons
;;;                          before it, by ADR-0014's scan
;;;
;;; The oracles are written out by hand: each byte's character, and each
;;; START's first token, over one script that mixes ASCII with characters of
;;; two, three and four bytes, a U+FEFF, comments of both kinds and runs of
;;; semicolons, so a byte offset and a character offset differ almost
;;; everywhere. Then slice 0's measured cases: P11's leading semicolons and
;;; comments, which belong to the next statement, and P11's tail at byte 30;
;;; single script X5's offset of 1 from byte 26, and X6's and X8's -1.
;;;
;;; Both procedures are total and raise nothing, for slice 3 calls them where
;;; nothing may raise. Each call is made under a guard that answers a symbol
;;; of its own, and an answer of #f is read as none: SRFI-64 turns a raise in
;;; the actual expression into #f, so no expected value is #f.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) library-exports)
        (chez-sqlite3-testing)
        (chez-sqlite3 private script))

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

;; iota : Natural -> (Listof Natural)
(define (iota n)
  (let loop ((i (- n 1)) (acc '()))
    (if (< i 0) acc (loop (- i 1) (cons i acc)))))

;; none-if-false : Any -> Any
(define (none-if-false x) (if (eq? x #f) 'none x))

;; prepare-at : Any Any Any -> (U Natural 'none (List 'raised String))
;; script-prepare-offset's answer, #f as none.
(define (prepare-at bytes start offset)
  (guard (e (#t (list 'raised (describe e))))
    (none-if-false (script-prepare-offset bytes start offset))))

;; step-at : Any Any -> (U Natural 'none (List 'raised String))
;; script-step-offset's answer, #f as none.
(define (step-at bytes start)
  (guard (e (#t (list 'raised (describe e))))
    (none-if-false (script-step-offset bytes start))))

;; The script, built from its characters, never from a \x escape: an R6RS \x
;; escape ends at its own semicolon (.plans/traps.md), and this script has
;; semicolons beside its U+FEFF. By hand, character (byte):
;;
;;   s0(0) e1(1) l2(2) e3(3) c4(4) t5(5) _6(6) '7(7) é8(8-9) '9(10) ;10(11)
;;   ;11(12) U+FEFF12(13-15) ;13(16) _14(17) -15(18) -16(19) _17(20)
;;   ü18(21-22) \n19(23) /20(24) *21(25) _22(26) U+1D11E23(27-30) _24(31)
;;   *25(32) /26(33) ;27(34) ;28(35) s29(36) e30(37) l31(38) e32(39)
;;   c33(40) t34(41) _35(42) 2 36(43)
;;
;; 37 characters, 44 bytes: é and ü of two bytes, U+FEFF of three, U+1D11E
;; (a G clef) of four.
(define script
  (string-append "select '" (string #\xE9) "';;" (string #\xFEFF) "; -- " (string #\xFC)
                 "\n/* " (string (integer->char #x1D11E)) " */;;select 2"))

(define script-bytes (string->utf8 script))

;; Each byte's character, by hand from the layout above: a continuation
;; byte belongs to the character it continues; the end, byte 44, is 37.
(define char-of-byte
  '#(0 1 2 3 4 5 6 7 8 8 9 10 11 12 12 12 13 14 15 16 17 18 18 19 20 21 22 23 23 23 23 24 25 26
     27 28 29 30 31 32 33 34 35 36 37))

;; Each START's first token, by hand: the character where the scan from
;; START, a fresh token, stops, or none past the last token.
(define first-token-at
  '(0 1 2 3 4 5 7 7 8 8 9 29 29 29 12 12 29 29 29 16 18 18 18 29 29 21 23 23 23 23 23 25 25 26
    29 29 29 30 31 32 33 34 36 36 none))

(test-begin "script")

(test-equal "(chez-sqlite3 private script) exports exactly the two offsets"
  '(script-prepare-offset script-step-offset)
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3 private script)))))

(test-equal "the script is 37 characters and 44 bytes, and the tables cover every byte offset, 0 to 44"
  '(37 44 45 45)
  (list (string-length script) (bytevector-length script-bytes) (vector-length char-of-byte)
        (length first-token-at)))

(test-equal "the script's encoding: é, ü, U+FEFF and U+1D11E at the bytes the layout says"
  '((#xc3 #xa9) (#xef #xbb #xbf) (#xc3 #xbc) (#xf0 #x9d #x84 #x9e))
  (map (lambda (range)
         (map (lambda (i) (bytevector-u8-ref script-bytes i)) range))
       '((8 9) (13 14 15) (21 22) (27 28 29 30))))

;; --- a prepare's offset -------------------------------------------------------------------

(test-equal "a prepare's offset at every START from 0 to 44 and every OFFSET from 0 to what is left: the character of byte START + OFFSET, mismatches listed"
  '(() 1035)
  (let ((bad '()) (count 0))
    (for-each
     (lambda (start)
       (for-each
        (lambda (offset)
          (set! count (+ count 1))
          (let ((expected (vector-ref char-of-byte (+ start offset)))
                (actual (prepare-at script-bytes start offset)))
            (unless (equal? actual expected)
              (when (< (length bad) 8)
                (set! bad (cons (list start offset expected actual) bad))))))
        (iota (- 45 start))))
     (iota 45))
    (list (reverse bad) count)))

(test-equal "SQLite's -1 points at no token, so it answers the statement's first token, what a step's offset answers from the same START, at every START 0 to 44: the table written out by hand"
  first-token-at
  (map (lambda (start) (prepare-at script-bytes start -1)) (iota 45)))

(test-equal "-1 answers the first token only for a START in the script: a START below 0, past the end or no exact integer, and BYTES that are no bytevector answer none"
  '(none none none none none none)
  (list (prepare-at script-bytes -1 -1) (prepare-at script-bytes 45 -1)
        (prepare-at script-bytes 1.0 -1) (prepare-at script-bytes 'start -1)
        (prepare-at script -1 -1) (prepare-at #f 0 -1)))

(test-equal "-1 answers none when the statement has no first token, whatever its START: a script of nothing but whitespace, comments and semicolons, and the empty one"
  '(none none none none)
  (let ((b (string->utf8 " ;-- c\n/* d */;; \t")))
    (list (prepare-at b 0 -1) (prepare-at b (bytevector-length b) -1)
          (prepare-at #vu8() 0 -1) (prepare-at (string->utf8 "  ") 1 -1))))

(test-equal "an OFFSET past the script's end, or below -1, answers none at every START: the end plus one, the end plus 100, -2 and -100"
  (map (lambda (s) '(none none none none)) (iota 45))
  (map (lambda (start)
         (list (prepare-at script-bytes start (- 45 start))
               (prepare-at script-bytes start (- 144 start))
               (prepare-at script-bytes start -2)
               (prepare-at script-bytes start -100)))
       (iota 45)))

(test-equal "the second statement starts at byte 12; SQLite pointing 24 bytes on, at its select, is character 29, not the byte 36 or the 24 it counted"
  29
  (prepare-at script-bytes 12 24))

(test-equal "a START or an OFFSET that is no exact integer, a START below 0 or past the end, and BYTES that are no bytevector answer none, raising nothing"
  '(none none none none none none none none none)
  (list (prepare-at script-bytes 1.0 1) (prepare-at script-bytes 1 1.0)
        (prepare-at script-bytes 'start 1) (prepare-at script-bytes 1 "1")
        (prepare-at script-bytes -1 2) (prepare-at script-bytes 45 0)
        (prepare-at script-bytes 100000000000000000000 0)
        (prepare-at script 0 1) (prepare-at #f 0 1)))

;; Slice 0's measurement, single script X5: the loop's prepare at byte 26
;; answered offset 1 for SELEKT, at byte 27 of the script. X6 and X8, no such
;; table and incomplete input, answered -1 there.
(define x5 "INSERT INTO s VALUES (40); SELEKT 1; INSERT INTO s VALUES (41);")
(define x6 "INSERT INTO s VALUES (50);\nINSERT INTO nosuch VALUES (1);\nINSERT INTO s VALUES (51);")
(define x8 "INSERT INTO s VALUES (70); INSERT INTO s VALUES (")

(test-equal "single script X5: from byte 26, SQLite's 1 points at SELEKT, character 27 of the script; X6's and X8's -1 from byte 26 point at the statement, INSERT, character 27 of each"
  '(27 27 27)
  (list (prepare-at (string->utf8 x5) 26 1) (prepare-at (string->utf8 x6) 26 -1)
        (prepare-at (string->utf8 x8) 26 -1)))

(test-equal "a prepare from byte 0 of an empty script, offset 0, points at the end, character 0; offset 1 answers none, and -1, with no statement, none"
  '(0 none none)
  (list (prepare-at #vu8() 0 0) (prepare-at #vu8() 0 1) (prepare-at #vu8() 0 -1)))

;; --- a step's offset ----------------------------------------------------------------------

(test-equal "a step's offset at every START from 0 to 44: the first token's character, written out by hand, none past the last"
  first-token-at
  (map (lambda (start) (step-at script-bytes start)) (iota 45)))

(test-equal "the script's two statements, as SQLite's tails cut it, start at bytes 0 and 12: their first tokens are characters 0 and 29"
  '(0 29)
  (list (step-at script-bytes 0) (step-at script-bytes 12)))

(test-equal "a START past the end, below 0 or no exact integer, and BYTES that are no bytevector answer none, raising nothing"
  '(none none none none none none none)
  (list (step-at script-bytes 45) (step-at script-bytes 100000000000000000000)
        (step-at script-bytes -1) (step-at script-bytes 12.0) (step-at script-bytes 'twelve)
        (step-at script 12) (step-at #f 0)))

;; By hand: _0 ;1 U+FEFF(2-4) -5 -6 _7 c8 \n9 /10 *11 _12 d13 _14 *15 /16 ;17
;; ;18 _19 \t20, 21 bytes; a token starts at 0, 1, 2, 5, 9, 10, 17, 18, 19
;; and 20, and the end is 21.
(test-equal "a script of nothing but whitespace, U+FEFF, comments and semicolons, 21 bytes, has no first token from any token's start or its end"
  '(21 (none none none none none none none none none none none))
  (let ((b (string->utf8 (string-append " ;" (string #\xFEFF) "-- c\n/* d */;; \t"))))
    (list (bytevector-length b)
          (map (lambda (start) (step-at b start)) '(0 1 2 5 9 10 17 18 19 20 21)))))

;; Slice 0's P11, by prepare_v3 and prepare_v2 on both libraries: a NULL
;; statement came only for nothing but semicolons, whitespace and comments;
;; leading semicolons and comments went into the next statement's text, its
;; tail at the end. So the statement prepared from START begins with them,
;; and its first token is past them.

;; with-feff : String -> String
;; U+FEFF, then TEXT.
(define (with-feff text) (string-append (string #\xFEFF) text))

(test-equal "P11's cases, each prepared from byte 0 as one statement: ;; select 2, -- c\\n; select 2 and U+FEFF then ; select 2 have their first token at characters 3, 7 and 3"
  '(3 7 3)
  (map (lambda (s) (step-at (string->utf8 s) 0))
       (list ";; select 2" "-- c\n; select 2" (with-feff "; select 2"))))

(test-equal "P11's other cases from byte 0: ; select 2, ; ;select 2, /* c */ ; select 2, -- c\\nselect 2 and /* c */ select 2 at characters 2, 3, 10, 5 and 8"
  '(2 3 10 5 8)
  (map (lambda (s) (step-at (string->utf8 s) 0))
       (list "; select 2" "; ;select 2" "/* c */ ; select 2" "-- c\nselect 2" "/* c */ select 2")))

(define p11-long ";;; -- c\n /* d */ ; select 2 ; select 3")

(test-equal "P11's long case: 39 bytes; its first statement's first token at 20, and its measured tail, byte 30, starts a statement whose first token is at 31"
  '(39 20 31)
  (let ((b (string->utf8 p11-long)))
    (list (bytevector-length b) (step-at b 0) (step-at b 30))))

(test-equal "P11's cases as a later statement, after select 'é'; whose tail is byte 12, character 11: the leading ;; and -- c\\n; belong to the next statement, whose first token is character 14 and 20"
  '(14 20)
  (map (lambda (s) (step-at (string->utf8 s) 12))
       (list (string-append "select '" (string #\xE9) "';;; select 2")
             (string-append "select '" (string #\xE9) "';; -- c\n; select 2"))))

(test-equal "U+FEFF then ; select 2 as a later statement, after select 'é'; : the first token is character 14, byte 17"
  14
  (step-at (string->utf8 (string-append "select '" (string #\xE9) "';" (with-feff "; select 2"))) 12))

(test-equal "single script X5's second statement, from byte 26: its first token, SELEKT, is character 27"
  27
  (step-at (string->utf8 x5) 26))

(test-end "script")

(exit (suite-exit-status runner))
