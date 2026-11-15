#!r6rs
;;; The tail scan against SQLite's own prepare, R2's oracle (ADR-0014,
;;; decision 4, amended). For each SQL: prepare-statement refuses it as more
;;; than one statement exactly when SQLite, preparing the SQL alone, leaves a
;;; tail whose own prepare, alone, gives a statement or an error. SQLite is
;;; asked live, on the library loaded, through native's sqlite3_prepare_v3,
;;; never through (chez-sqlite3 private statement).
;;;
;;; The SQL is "select 1;" and a tail, the tail being:
;;;   - every character of one byte, U+0001 to U+007F;
;;;   - every two characters over those 127, U+FEFF, U+0085 and U+00A0, a set
;;;     the gate's budget allows: the whole suite, 20,602 inputs of three
;;;     prepares each, took 21 s under make test-memory (M2 slice 3);
;;;   - every two and every three characters over a 14-character alphabet: the ten ASCII
;;;     bytes the scan's rules name (space, \t, \n, \v, \f, \r, ;, -, /, *),
;;;     A, U+FEFF, and U+0085 and U+00A0, which SQLite does not count as
;;;     whitespace (measured);
;;;   - every input of M2 slice 1's two literals of what SQLite leaves empty,
;;;     read from tests/test-sql-tail.sps as data, that is a string: well-formed
;;;     UTF-8 with no NUL;
;;; and then each edge ADR-0014 names, as whole SQL, first statements without
;;; a semicolon among them.
;;;
;;; A prepare-statement takes a string, so its SQL is well-formed UTF-8: the
;;; bytes 80 to FF reach the scan only inside a character's encoding, and
;;; slice 1's byte-level oracle, tests/test-sql-tail.sps, holds the scan on
;;; every byte. SQL holding U+0000 is refused before it is scanned.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) sqlite-error?)
        (only (chez-sqlite3 private utf8) strict-utf8->string))

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

;; reach : (Listof Symbol) Symbol -> Procedure
(define (reach library name)
  (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
    (eval name (environment library))))

(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define prepare-statement (reach '(chez-sqlite3 private statement) 'prepare-statement))
(define finalize-statement! (reach '(chez-sqlite3 private statement) 'finalize-statement!))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-out-pointer (reach '(chez-sqlite3 private native) 'call-with-out-pointer))
(define sqlite3-prepare-v3 (reach '(chez-sqlite3 private native) 'sqlite3-prepare-v3))
(define sqlite3-finalize (reach '(chez-sqlite3 private native) 'sqlite3-finalize))

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

;; --- SQLite's answer --------------------------------------------------------------------

;; sqlite-prepare : Database String Natural -> (List Integer Boolean Natural)
;; SQL prepared by SQLite from its byte K, with the bytes after it and the NUL
;; as nByte: the code, whether a statement came back (finalized at once), and
;; the tail's byte offset from the start of SQL. K is 0 for the SQL itself,
;; and a tail's offset for the tail, prepared in place: SQLite reads its own
;; bytes at their own address, never a decoded and re-encoded copy, which
;; would drop a leading U+FEFF.
(define (sqlite-prepare db sql k)
  (call-with-open-handle 'test-statement-tail db
    (lambda (h)
      (call-with-c-string 'test-statement-tail sql
        (lambda (text)
          (let-values (((inner tail)
                        (call-with-out-pointer 'test-statement-tail
                          (lambda (tail-slot)
                            (let-values (((rc statement)
                                          (call-with-out-pointer 'test-statement-tail
                                            (lambda (slot)
                                              (sqlite3-prepare-v3 h (+ text k)
                                                                  (- (+ (bytevector-length (string->utf8 sql)) 1) k)
                                                                  0 slot tail-slot)))))
                              (unless (eqv? statement 0) (sqlite3-finalize statement))
                              (cons rc (not (eqv? statement 0))))))))
            (list (car inner) (cdr inner) (- tail text))))))))

;; sqlite-verdict : Database String -> (U 'accepted 'refused 'error)
;; SQLite's verdict on SQL as one statement: error when its prepare of the
;; SQL fails; refused when the tail it leaves, prepared alone, gives a
;; statement or an error; else accepted.
(define (sqlite-verdict db sql)
  (let ((first (sqlite-prepare db sql 0)))
    (if (not (eqv? (car first) 0))
        'error
        (let ((tail (sqlite-prepare db sql (caddr first))))
          (if (or (not (eqv? (car tail) 0)) (cadr tail)) 'refused 'accepted)))))

;; ours : Database String -> (U 'accepted 'refused 'error (List 'other Any))
;; prepare-statement's verdict: accepted, its statement finalized; refused,
;; more-than-one-statement; error, an &sqlite-error.
(define (ours db sql)
  (guard (e ((and (assertion-violation? e) (irritants-condition? e)
                  (pair? (condition-irritants e))
                  (eq? (car (condition-irritants e)) 'more-than-one-statement))
             'refused)
            ((sqlite-error? e) 'error)
            (#t (list 'other (describe e))))
    (finalize-statement! (prepare-statement db sql))
    'accepted))

;; mismatches : Database (Listof String) -> (List Natural Natural Natural (Listof Any))
;; Each SQL's verdicts compared: how many SQLite accepts, refuses and fails,
;; and every SQL where prepare-statement's differs, with both.
(define (mismatches db sqls)
  (let loop ((rest sqls) (accepted 0) (refused 0) (errors 0) (bad '()))
    (if (null? rest)
        (list accepted refused errors (reverse bad))
        (let* ((sql (car rest))
               (theirs (sqlite-verdict db sql))
               (mine (ours db sql)))
          (loop (cdr rest)
                (if (eq? theirs 'accepted) (+ accepted 1) accepted)
                (if (eq? theirs 'refused) (+ refused 1) refused)
                (if (eq? theirs 'error) (+ errors 1) errors)
                (if (equal? theirs mine) bad (cons (list sql 'sqlite theirs 'ours mine) bad)))))))

;; --- the inputs --------------------------------------------------------------------------

(define prefix "select 1;")

;; one-byte : (Listof String)
;; Every character of one byte but U+0000.
(define one-byte
  (let loop ((i 127) (found '()))
    (if (= i 0) found (loop (- i 1) (cons (string (integer->char i)) found)))))

(define alphabet
  (list #\space #\tab #\newline #\vtab #\page #\return #\; #\- #\/ #\* #\A
        #\xFEFF #\x85 #\xA0))

;; two-char : (Listof String)
(define two-char
  (apply append
         (map (lambda (a) (map (lambda (b) (string a b)) alphabet)) alphabet)))

;; three-char : (Listof String)
(define three-char
  (apply append
         (map (lambda (a) (apply append (map (lambda (b) (map (lambda (c) (string a b c)) alphabet)) alphabet)))
              alphabet)))

;; wide : (Listof Char)
;; Every character of one byte but U+0000, and the three of more that the
;; scan's rules name: U+FEFF, U+0085 and U+00A0.
(define wide
  (append (map (lambda (s) (string-ref s 0)) one-byte) (list #\xFEFF #\x85 #\xA0)))

;; two-wide : (Listof String)
;; Every two characters over WIDE: 130 by 130.
(define two-wide
  (apply append (map (lambda (a) (map (lambda (b) (string a b)) wide)) wide)))

;; literal : String Symbol -> (Listof (Listof Byte))
;; The quoted list NAME's define binds in the suite at PATH, read as data.
(define (literal path name)
  (guard (e (#t (list (list 'raised (describe e)))))
    (call-with-input-file path
      (lambda (port)
        (let loop ()
          (let ((datum (get-datum port)))
            (cond ((eof-object? datum) (list (list 'not-found name)))
                  ((and (pair? datum) (eq? (car datum) 'define) (pair? (cdr datum))
                        (eq? (cadr datum) name) (pair? (cddr datum))
                        (pair? (caddr datum)) (eq? (car (caddr datum)) 'quote))
                   (cadr (caddr datum)))
                  (else (loop)))))))))

(define literal-1-2 (literal "tests/test-sql-tail.sps" 'sqlite-accepted))
(define literal-3 (literal "tests/test-sql-tail.sps" 'sqlite-accepted-3))
(define slice-1-literals (append literal-1-2 literal-3))

;; as-string : (Listof Byte) -> (U String #f)
;; BYTES as a string when they are well-formed UTF-8 holding no NUL.
(define (as-string bytes)
  (and (list? bytes) (for-all (lambda (b) (and (integer? b) (< 0 b 256))) bytes)
       (let ((s (strict-utf8->string (u8-list->bytevector bytes))))
         (and (string? s) s))))

(define literal-strings
  (filter (lambda (s) s) (map as-string slice-1-literals)))

;; spelled : String -> String
;; SQL with {vt} as U+000B, {bom} as U+FEFF, {nel} as U+0085, {nbsp} as
;; U+00A0 and {e} as U+00E9.
(define (spelled sql)
  (let ((names (list (cons "{vt}" (string #\vtab)) (cons "{bom}" (string #\xFEFF))
                     (cons "{nel}" (string #\x85)) (cons "{nbsp}" (string #\xA0))
                     (cons "{e}" (string #\xE9)))))
    (let loop ((i 0) (out '()))
      (if (= i (string-length sql))
          (apply string-append (reverse out))
          (let ((hit (find (lambda (n)
                             (let ((k (string-length (car n))))
                               (and (<= (+ i k) (string-length sql))
                                    (string=? (substring sql i (+ i k)) (car n)))))
                           names)))
            (if hit
                (loop (+ i (string-length (car hit))) (cons (cdr hit) out))
                (loop (+ i 1) (cons (string (string-ref sql i)) out))))))))

;; The edges ADR-0014 names, as whole SQL: \v alone, after whitespace, after a
;; line comment's newline, straight after ; or */; U+FEFF anywhere; -- to the
;; end of the line or of the SQL; /* with a byte after it, unterminated, and
;; as the last two bytes; */ closing; U+0085 and U+00A0; semicolons; and the
;; tail starting after a first statement's semicolon, wherever that falls.
(define edges
  (map (lambda (sql) (spelled sql))
       '("select 1;{vt}" "select 1; {vt}" "select 1; -- c\n{vt}" "select 1;/* c */{vt}"
         "select 1; /* c */ {vt}" "select 1;{bom};" "select 1;{bom};x" "select 1; {bom} {bom} "
         "select 1;{bom};{bom}" "select 1;{bom}" "select 1;x{bom}" "select 1{bom}; x"
         "select 1; -- c" "select 1; -- c\n" "select 1; -- c\nx" "select 1; -- c\n-- d" "select 1;--"
         "select 1;/*" "select 1;/* " "select 1;/*x" "select 1;/**/" "select 1;/*/" "select 1;/**/x"
         "select 1;/* * / */x" "select 1;/* c */;" "select 1;{nel};" "select 1;{nbsp};" "select 1; {nel}"
         "select 1;;;" "select 1; ; ; " "select 1; select 2" "select 1;x"
         "select 1" "select 1 " "select 1 -- c" "select 1 -- c\n; x" "select 1 -- c\n;" "select 1/* c */; x"
         "select 1/* c */;" "select 1 ; x" "select 1 ;" "select 1;\t{vt}\f\r\n" "select '{e}';{bom}"
         "select '{e}'; x" "select 1 /* c */ -- d\n ;  /* e */ ; -- f")))

(test-begin "statement-tail")

(test-equal "every count is zero at the start"
  zero-counts
  (native-counts))

(test-equal "slice 1's literals are read whole, 48 inputs of 1 and 2 bytes and 798 of 3; the strings among them number 48 and 542"
  '(48 798 48 542)
  (list (length literal-1-2) (length literal-3)
        (length (filter as-string literal-1-2)) (length (filter as-string literal-3))))

;; on-fresh-db : (Database -> Any) -> Any
(define (on-fresh-db proc)
  (guard (e (#t (list 'raised (describe e))))
    (let ((db (open-database ":memory:")))
      (dynamic-wind
        (lambda () #f)
        (lambda () (proc db))
        (lambda () (guard (e (#t #f)) (close-database! db)))))))

(define (with-prefix tails) (map (lambda (t) (string-append prefix t)) tails))

(test-equal "every character of one byte after select 1;, U+0001 to U+007F: prepare-statement refuses exactly the tails SQLite refuses; SQLite accepts 6, the five whitespace and the semicolon, and refuses 121"
  '(6 121 0 ())
  (on-fresh-db (lambda (db) (mismatches db (with-prefix one-byte)))))

(test-equal "every two characters over the 14-character alphabet after select 1;, 196 of them: no mismatch; SQLite accepts 55 and refuses 141"
  '(55 141 0 ())
  (on-fresh-db (lambda (db) (mismatches db (with-prefix two-char)))))

(test-equal "every three characters over the 14-character alphabet after select 1;, 2,744 of them: no mismatch; SQLite accepts 453 and refuses 2,291"
  '(453 2291 0 ())
  (on-fresh-db (lambda (db) (mismatches db (with-prefix three-char)))))

(test-equal "every two characters after select 1;, each of one byte but U+0000, or U+FEFF, U+0085 or U+00A0, 16,900 of them: no mismatch; SQLite accepts 55, the same as over the alphabet, and refuses 16,845"
  '(55 16845 0 ())
  (on-fresh-db (lambda (db) (mismatches db (with-prefix two-wide)))))

(test-equal "every input of slice 1's literals that is a string, after select 1;, 590 of them: SQLite accepts each, and so does prepare-statement"
  '(590 0 0 ())
  (on-fresh-db (lambda (db) (mismatches db (with-prefix literal-strings)))))

(test-equal "each edge ADR-0014 names, as whole SQL, 45 of them: no mismatch; SQLite accepts 27, refuses 17, and fails one, U+FEFF straight after a number"
  '(27 17 1 ())
  (on-fresh-db (lambda (db) (mismatches db edges))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "statement-tail")

(exit (suite-exit-status runner))
