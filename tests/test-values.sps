#!r6rs
;;; The suite for (chez-sqlite3 private values): the pure core of binding and
;;; of reading a column (ADR-0015). It loads no libsqlite3: the library holds
;;; no foreign code, and takes the foreign calls it orders as arguments.
;;;
;;;   sql-null       the one instance of a record type nobody can make
;;;                  another of: opaque, so record-rtd refuses it
;;;   bind-plan      a value's plan: int64, double, text, blob or null, or a
;;;                  refusal naming its rule; the integer boundary rows each
;;;                  asserting the rule's symbol, since Chez's own integer-64
;;;                  check would wrap 2^63 and raise its own error at 2^64
;;;   raise-bind-refusal
;;;                  the assertion violation a refusal becomes: the rule, the
;;;                  parameter, and the value's kind, never the value
;;;   read-column-bytes, read-column-name
;;;                  the NULL-pointer readers, on stand-ins that record each
;;;                  call: the call log and the answer are asserted whole
;;;
;;; bind-plan and the readers answer data and raise nothing, so every call is
;;; made under a guard with a sentinel of its own. SRFI-64 turns a raise in the
;;; actual expression into #f, so an expected #f is read as the symbol none.
;;; The readers' call orders come from the stand-ins' log, which the library's
;;; own sequencing writes: no row here relies on argument evaluation order.
(import (rnrs)
        (rnrs mutable-pairs)
        (rnrs records inspection)
        (srfi :64)
        (only (chezscheme) library-exports)
        (chez-sqlite3-testing)
        (chez-sqlite3 private conditions)
        (chez-sqlite3 private values))

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

;; raised : (-> Any) -> Any
;; What THUNK raised: (assertion-violation WHO IRRITANTS), (other TEXT) for
;; any other raise, or (no-raise VALUE).
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e)
                  (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other (describe e))))
    (list 'no-raise (thunk))))

;; contains? : String String -> Boolean
(define (contains? text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i k) n) (or (string=? (substring text i (+ i k)) part) (loop (+ i 1)))))))

;; planned : Any -> Any
;; bind-plan's answer, or (raised TEXT): it must raise nothing.
(define (planned v)
  (guard (e (#t (list 'raised (describe e)))) (bind-plan v)))

;; sorted-names : (Listof Symbol) -> (Listof Symbol)
(define (sorted-names names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

;; bytevector : Byte ... -> Bytevector
(define (bytevector . bytes) (u8-list->bytevector bytes))

;; iota : Natural -> (Listof Natural)
(define (iota n)
  (let loop ((i (- n 1)) (acc '()))
    (if (< i 0) acc (loop (- i 1) (cons i acc)))))

(define secret "Pr0xyS3cr3t")

(define-record-type a-thing (fields x))

(define two63 (expt 2 63))
(define two64 (expt 2 64))

(test-begin "values")

(test-equal "(chez-sqlite3 private values) exports exactly sql-null, the bind plan, the refusal and the two readers"
  (sorted-names '(sql-null sql-null? bind-plan bind-refusal-rules raise-bind-refusal
                  read-column-bytes read-column-name))
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3 private values)))))

;; --- sql-null ------------------------------------------------------------------------------

(test-equal "sql-null? holds for sql-null, and for nothing else of a spread of values, as yes and no"
  '(yes no no no no no no no no no no no no)
  (map (lambda (v) (guard (e (#t 'raised)) (if (sql-null? v) 'yes 'no)))
       (list sql-null #f '() 0 'sql-null "sql-null" (make-bytevector 0 0) #\n (vector)
             (make-eq-hashtable) (make-a-thing 1) (list sql-null) (cons 'null '()))))

(test-equal "sql-null is one value: eq? to itself, and it is no record to Chez"
  '(same not-a-record)
  (list (if (eq? sql-null sql-null) 'same 'different) (if (record? sql-null) 'record 'not-a-record)))

;; A record that record-rtd opens can be rebuilt from its type, and a second
;; null made. Opaque, it raises instead.
(test-equal "sql-null is opaque: record-rtd refuses it"
  '(assertion-violation record-rtd)
  (guard (e ((and (assertion-violation? e) (who-condition? e))
             (list 'assertion-violation (condition-who e)))
            (#t (list 'other-raise (describe e))))
    (list 'no-raise (record-type-name (record-rtd sql-null)))))

(test-equal "a record of another type is no sql-null, even one with the same name, sql-null-type, and no fields, and sql-null prints under that name"
  '(no "sql-null-type" #t)
  (let ()
    (define-record-type sql-null-type (fields))
    (list (if (sql-null? (make-sql-null-type)) 'yes 'no)
          (symbol->string (record-type-name (record-type-descriptor sql-null-type)))
          (let ((text (guard (e (#t "raised"))
                        (call-with-string-output-port
                          (lambda (port) (display sql-null port))))))
            (and (contains? text "#<sql-null-type>") #t)))))

;; --- bind-plan: each plan --------------------------------------------------------------------

(test-equal "an exact integer is an int64 plan: zero, small, negative and a large one"
  '((int64 0) (int64 1) (int64 -1) (int64 255) (int64 4294967296) (int64 -4294967297)
    (int64 1234567890123))
  (map planned '(0 1 -1 255 4294967296 -4294967297 1234567890123)))

(test-equal "the int64 boundary: 2^63-1 and -2^63 are accepted, as themselves"
  (list (list 'int64 (- two63 1)) (list 'int64 (- two63)) (list 'int64 (- two63 2))
        (list 'int64 (+ (- two63) 1)))
  (map planned (list (- two63 1) (- two63) (- two63 2) (+ (- two63) 1))))

(test-equal "past the boundary: 2^63, 2^64-1, 2^64 and -2^63-1 are refused, each by its rule symbol, and so is a bignum beyond them"
  '((refused integer-out-of-range) (refused integer-out-of-range) (refused integer-out-of-range)
    (refused integer-out-of-range) (refused integer-out-of-range) (refused integer-out-of-range)
    (refused integer-out-of-range))
  (map planned (list two63 (- two64 1) two64 (- (- two63) 1) (expt 10 30) (- (expt 10 30))
                     (+ two64 1))))

(test-equal "a flonum is a double plan: ordinary, zero, -0.0 (kept signed), +inf.0 and -inf.0"
  '((double 1.5) (double 0.0) (double -0.0) (double +inf.0) (double -inf.0) (double -2.25)
    (double 1e300) (double 5e-324))
  (map planned (list 1.5 0.0 -0.0 +inf.0 -inf.0 -2.25 1e300 5e-324)))

(test-equal "a flonum with an integer value is a double, not an int64: 3.0, and 1e18"
  '((double 3.0) (double 1e18))
  (map planned (list 3.0 1e18)))

(test-equal "every NaN is refused by the rule nan: +nan.0, -nan.0, inf minus inf and 0.0 over 0.0"
  '((refused nan) (refused nan) (refused nan) (refused nan))
  (map planned (list +nan.0 -nan.0 (- +inf.0 +inf.0) (/ 0.0 0.0))))

(test-equal "a string is a text plan holding its UTF-8, a U+0000 kept: empty, ASCII, NUL, 2-, 3- and 4-byte characters"
  (list '(text #vu8()) '(text #vu8(97 98 99)) '(text #vu8(97 0 98)) '(text #vu8(0))
        '(text #vu8(#xc3 #xa9)) '(text #vu8(#xe2 #x82 #xac)) '(text #vu8(#xf0 #x9d #x84 #x9e))
        '(text #vu8(#xef #xbf #xbd)) '(text #vu8(#xf4 #x8f #xbf #xbf)))
  (map planned (list "" "abc" "a\x0;b" "\x0;" "\xe9;" "\x20ac;" "\x1d11e;" "\xfffd;" "\x10ffff;")))

(test-equal "a bytevector is a blob plan holding its bytes: empty, one, every byte value, and a NUL"
  (list '(blob #vu8()) '(blob #vu8(0)) '(blob #vu8(255)) '(blob #vu8(1 0 2))
        (list 'blob (u8-list->bytevector (iota 256))))
  (map planned (list (make-bytevector 0 0) (make-bytevector 1 0) (make-bytevector 1 255)
                     (bytevector 1 0 2) (u8-list->bytevector (iota 256)))))

(test-equal "sql-null is the null plan"
  '(null)
  (planned sql-null))

;; --- bind-plan: the buffers are fresh ---------------------------------------------------------

(test-equal "a blob plan's bytes are a copy: not the caller's object, and a later change to the caller's bytes does not reach it"
  '(not-shared (blob #vu8(1 2 3)))
  (let* ((original (bytevector 1 2 3))
         (plan (planned original))
         (shared (if (eq? (cadr plan) original) 'shared 'not-shared)))
    (bytevector-u8-set! original 0 99)
    (list shared plan)))

(test-equal "a blob plan's bytes are a fresh copy each call, and a change to the plan's bytes does not reach the caller's"
  '(fresh #vu8(1 2 3))
  (let* ((original (bytevector 1 2 3))
         (one (planned original))
         (two (planned original)))
    (bytevector-u8-set! (cadr one) 0 99)
    (list (if (eq? (cadr one) (cadr two)) 'same 'fresh) original)))

(test-equal "a text plan's bytes are fresh each call"
  '(fresh (text #vu8(97 98)))
  (let* ((one (planned "ab")) (two (planned "ab")))
    (bytevector-u8-set! (cadr one) 0 99)
    (list (if (eq? (cadr one) (cadr two)) 'same 'fresh) two)))

;; --- bind-plan: the refusals, whole ---------------------------------------------------------

(test-equal "#t and #f are refused by the rule boolean (D5)"
  '((refused boolean) (refused boolean))
  (map planned '(#t #f)))

(test-equal "everything else is refused by the rule not-a-value: an exact non-integer, a complex, a symbol, a char, a list, () , a vector, a procedure, a record, a condition, a hashtable, a pair, the eof object, a number-like symbol and a string-like one"
  (map (lambda (v) '(refused not-a-value))
       '(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18))
  (map planned (list 1/2 -7/3 1+2i 1.5+2.5i 'x #\a '(1 2) '() (vector 1) car (make-a-thing 1)
                     (make-error) (make-eq-hashtable) (cons 1 2) (eof-object) (string->symbol "1") 'sql-null
                     (list sql-null))))

(test-equal "bind-plan raises nothing for any of the values of this suite, and for a circular list"
  'ok
  (let ((circular (let ((l (list 1 2))) (set-cdr! (cdr l) l) l)))
    (if (for-all (lambda (v)
                   (let ((p (planned v)))
                     (and (list? p) (memq (car p) '(int64 double text blob null refused)) #t)))
                 (list circular 0 -0.0 "" (make-bytevector 0 0) #t sql-null +nan.0 two64))
        'ok
        'raised)))

(test-equal "bind-refusal-rules are the four, in order"
  '(integer-out-of-range nan boolean not-a-value)
  bind-refusal-rules)

(test-equal "every rule a refusal can name is one of bind-refusal-rules"
  '(#t #t #t #t)
  (map (lambda (v) (and (memq (cadr (planned v)) bind-refusal-rules) #t))
       (list two63 +nan.0 #t 'x)))

;; --- raise-bind-refusal ----------------------------------------------------------------------

(test-equal "raise-bind-refusal: an assertion violation from WHO, irritants the rule, the parameter and the value's kind"
  '(assertion-violation bind! (boolean 2 (kind boolean)))
  (raised (lambda () (raise-bind-refusal 'bind! 2 #t 'boolean))))

(test-equal "each of the four rules, with a value of its own kind, by its symbol first"
  '((assertion-violation bind! (integer-out-of-range 1 (kind number)))
    (assertion-violation bind! (nan 1 (kind number)))
    (assertion-violation bind! (boolean 1 (kind boolean)))
    (assertion-violation bind! (not-a-value 1 (kind symbol))))
  (map (lambda (rule v) (raised (lambda () (raise-bind-refusal 'bind! 1 v rule))))
       '(integer-out-of-range nan boolean not-a-value)
       (list two63 +nan.0 #f 'x)))

(test-equal "the parameter is itself when it is an exact positive integer: 1, 7 and a bignum"
  '((assertion-violation bind-all! (boolean 1 (kind boolean)))
    (assertion-violation bind-all! (boolean 7 (kind boolean)))
    (assertion-violation bind-all! (boolean 100000000000000000000 (kind boolean))))
  (map (lambda (p) (raised (lambda () (raise-bind-refusal 'bind-all! p #t 'boolean))))
       '(1 7 100000000000000000000)))

(test-equal "any other parameter is shown by its kind, never itself: a name, 0, a negative, a flonum, a symbol and a list"
  '((assertion-violation bind! (boolean (kind string) (kind boolean)))
    (assertion-violation bind! (boolean (kind number) (kind boolean)))
    (assertion-violation bind! (boolean (kind number) (kind boolean)))
    (assertion-violation bind! (boolean (kind number) (kind boolean)))
    (assertion-violation bind! (boolean (kind symbol) (kind boolean)))
    (assertion-violation bind! (boolean (kind list) (kind boolean))))
  (map (lambda (p) (raised (lambda () (raise-bind-refusal 'bind! p #t 'boolean))))
       (list ":name" 0 -1 1.0 'name '(1))))

(test-equal "the value is shown by its kind: a string, a list, a number, a char, a bytevector, a vector, a procedure and a record"
  '(string list number char bytevector vector procedure other)
  (map (lambda (v)
         (let ((r (raised (lambda () (raise-bind-refusal 'bind! 1 v 'not-a-value)))))
           (cadr (list-ref (list-ref r 2) 2))))
       (list "s" '(1) 1/2 #\a (make-bytevector 1 0) (vector) car (make-a-thing 1))))

(test-equal "the value is never shown: a secret string, a secret in a list, in a vector, as a parameter name, never appears in the raised text"
  '(absent absent absent absent)
  (map (lambda (args)
         (let ((text (guard (e (#t (describe e)))
                       (raise-bind-refusal 'bind! (car args) (cadr args) 'not-a-value)
                       "no-raise")))
           (if (contains? text secret) 'printed 'absent)))
       (list (list 1 secret) (list 1 (list secret)) (list 1 (vector secret)) (list secret 'x))))

(test-equal "a rule outside bind-refusal-rules is an assertion violation from raise-bind-refusal, led by not-a-rule"
  '((assertion-violation raise-bind-refusal (not-a-rule bogus))
    (assertion-violation raise-bind-refusal (not-a-rule (kind string)))
    (assertion-violation raise-bind-refusal (not-a-rule (kind number)))
    (assertion-violation raise-bind-refusal (not-a-rule (kind boolean)))
    (assertion-violation raise-bind-refusal (not-a-rule BOOLEAN)))
  (map (lambda (rule) (raised (lambda () (raise-bind-refusal 'bind! 1 #t rule))))
       (list 'bogus "boolean" 5 #f 'BOOLEAN)))

(test-equal "raise-bind-refusal refuses a WHO that is no symbol first, before its rule: an assertion violation from raise-bind-refusal, irritants (who V) by shown-value"
  '((assertion-violation raise-bind-refusal (who (kind string)))
    (assertion-violation raise-bind-refusal (who 5))
    (assertion-violation raise-bind-refusal (who #f))
    (assertion-violation raise-bind-refusal (who (kind string)))
    (assertion-violation raise-bind-refusal (who (kind list))))
  (list (raised (lambda () (raise-bind-refusal "bind!" 1 #t 'boolean)))
        (raised (lambda () (raise-bind-refusal 5 1 #t 'boolean)))
        (raised (lambda () (raise-bind-refusal #f 1 #t 'bogus)))
        (raised (lambda () (raise-bind-refusal "bind!" 1 #t 'bogus)))
        (raised (lambda () (raise-bind-refusal (list "x") 1 #t 'boolean)))))

(test-equal "raise-bind-refusal never returns: a handler that returns gets the &non-continuable R6RS raises for it"
  'non-continuable
  (guard (e ((non-continuable-violation? e) 'non-continuable)
            (#t (list 'other-raise (describe e))))
    (with-exception-handler (lambda (c) 'handled)
      (lambda () (raise-bind-refusal 'bind! 1 #t 'boolean)))
    'returned-normally))

;; --- the readers, on stand-ins that log each call ---------------------------------------------

;; run-reader : ((Listof Symbol) -> Any) -> (List Log Answer)
;; Calls (MAKE log!) for the stand-ins, where log! records a symbol, and
;; answers the call log, in order, and the answer, whole. A raise is the
;; answer (raised TEXT).
(define (run-reader make)
  (let* ((log '())
         (log! (lambda (entry) (set! log (cons entry log))))
         (answer (guard (e (#t (list 'raised (describe e)))) (make log!))))
    (list (reverse log) answer)))

;; read-bytes : Natural Integer Integer Natural Bytevector -> (List Log Answer)
;; read-column-bytes with stand-ins answering POINTER, ERRCODE, TYPE, ERRMSG
;; ("the message"), BYTES and a copy that answers COPIED, each logging its
;; call.
(define (read-bytes pointer errcode type bytes copied)
  (run-reader
   (lambda (log!)
     (read-column-bytes (lambda () (log! 'pointer) pointer)
                        (lambda () (log! 'errcode) errcode)
                        (lambda () (log! 'type) type)
                        (lambda () (log! 'errmsg) "the message")
                        (lambda () (log! 'bytes) bytes)
                        (lambda (p n) (log! (list 'copy p n)) copied)))))

(define copied-bytes (bytevector 7 8 9))

(test-equal "a non-zero pointer: POINTER, BYTES, then COPY of the pointer and the length; ERRCODE, TYPE and ERRMSG are never called; the answer is the copy"
  '((pointer bytes (copy 4096 3)) #vu8(7 8 9))
  (read-bytes 4096 7 5 3 copied-bytes))

(test-equal "a non-zero pointer with a code that would be NOMEM and a type that would be NULL is still read: the code and the type are never asked"
  '((pointer bytes (copy 1 0)) #vu8(7 8 9))
  (read-bytes 1 7 5 0 copied-bytes))

(test-equal "a non-zero pointer: the pointer and the length are passed on as they are, a large pointer among them"
  '((pointer bytes (copy 140737488355327 65536)) #vu8(7 8 9))
  (read-bytes 140737488355327 5 5 65536 copied-bytes))

(test-equal "a zero pointer, NOMEM (7) and a NULL type (5): POINTER, ERRCODE at once, then TYPE, then ERRMSG; BYTES and COPY never; the answer is (nomem 7 MESSAGE)"
  '((pointer errcode type errmsg) (nomem 7 "the message"))
  (read-bytes 0 7 5 3 copied-bytes))

(test-equal "a zero pointer, a code of 7 and a type that is not NULL, over every other type (1 to 4, and 0, 6): a stale 7, so an empty bytevector; ERRMSG never called, BYTES and COPY never"
  '(() ())
  (list (filter (lambda (t) (not (equal? (read-bytes 0 7 t 3 copied-bytes)
                                         '((pointer errcode type) #vu8()))))
                '(0 1 2 3 4 6))
        (filter (lambda (t) (not (equal? (read-bytes 0 519 t 3 copied-bytes)
                                         '((pointer errcode type) #vu8()))))
                '(1 2 3 4))))

(test-equal "a zero pointer and an extended NOMEM, low byte 7 (263, 519), with a NULL type: the answer is (nomem CODE MESSAGE) with the code as given"
  '(((pointer errcode type errmsg) (nomem 263 "the message"))
    ((pointer errcode type errmsg) (nomem 519 "the message")))
  (list (read-bytes 0 263 5 3 copied-bytes) (read-bytes 0 519 5 3 copied-bytes)))

(test-equal "a zero pointer and ioerr-nomem (3082, low byte 10): not NOMEM, so a fresh empty bytevector, TYPE and ERRMSG never called, even with a NULL type"
  '((pointer errcode) #vu8())
  (read-bytes 0 3082 5 3 copied-bytes))

(test-equal "a zero pointer and the code after a row (100) or 0 (an empty value): an empty bytevector, ERRCODE asked once, TYPE and ERRMSG never, nothing else"
  '(((pointer errcode) #vu8()) ((pointer errcode) #vu8()) ((pointer errcode) #vu8()))
  (list (read-bytes 0 100 4 3 copied-bytes) (read-bytes 0 0 4 3 copied-bytes)
        (read-bytes 0 101 4 3 copied-bytes)))

(test-equal "a zero pointer and every code whose low byte is not 7, over 0 to 300: an empty bytevector, TYPE never asked; and every one whose low byte is 7, with a NULL type: nomem; with a BLOB type (4): an empty bytevector"
  '(() () ())
  (list (filter (lambda (c) (not (equal? (read-bytes 0 c 5 3 copied-bytes)
                                         '((pointer errcode) #vu8()))))
                (filter (lambda (c) (not (= (bitwise-and c 255) 7))) (iota 300)))
        (filter (lambda (c) (not (equal? (read-bytes 0 c 5 3 copied-bytes)
                                         (list '(pointer errcode type errmsg)
                                               (list 'nomem c "the message")))))
                (filter (lambda (c) (= (bitwise-and c 255) 7)) (iota 300)))
        (filter (lambda (c) (not (equal? (read-bytes 0 c 4 3 copied-bytes)
                                         '((pointer errcode type) #vu8()))))
                (filter (lambda (c) (= (bitwise-and c 255) 7)) (iota 300)))))

;; read-name : Natural Bytevector -> (List Log Answer)
(define (read-name pointer copied)
  (run-reader
   (lambda (log!)
     (read-column-name (lambda () (log! 'name) pointer)
                       (lambda (p) (log! (list 'copy-c-string p)) copied)))))

(test-equal "a non-zero name pointer: NAME, then COPY-C-STRING of the pointer, whose answer is the answer"
  '((name (copy-c-string 8192)) #vu8(7 8 9))
  (read-name 8192 copied-bytes))

(test-equal "a zero name pointer: NAME alone, nothing else called, and the answer is nomem"
  '((name) nomem)
  (read-name 0 copied-bytes))

(test-end "values")

(exit (suite-exit-status runner))
