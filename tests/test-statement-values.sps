#!r6rs
;;; The suite for a statement's values, (chez-sqlite3 private statement-values):
;;; bind!, bind-all!, clear-bindings!, column-value, column-bytevector and
;;; column-name (ADR-0015; ADR-0014, decisions 3 and 5, amended).
;;;
;;;   binding        every row of the M2 plan's section 4.3 on a real library:
;;;                  the integer boundaries, bound and refused by their rule;
;;;                  the infinities, -0.0 through select ? and a REAL column,
;;;                  NaN refused; booleans, an exact non-integer, a complex, a
;;;                  symbol and a character refused; strings of two-, three- and
;;;                  four-byte sequences, U+0000, a leading U+FEFF and none,
;;;                  read back with their bytes; bytevectors, none among them;
;;;                  sql-null. Each refusal leaves the sentinel bound before it
;;;   parameters     by index; by each sigil's name; a name used twice; a name
;;;                  no parameter has; U+0000 in a name; index 0 and count+1;
;;;                  bind-all! with the wrong count, and with a bad value among
;;;                  good ones, binding nothing; the checks' order
;;;   SQLite refuses SQLITE_LIMIT_LENGTH lowered to 30 through the suite's own
;;;                  sqlite3_limit: 31 bytes raise toobig, the parameter is then
;;;                  NULL and the state ready, and the error has no offset after
;;;                  an earlier prepare's; bind-all! refused midway
;;;   clear-bindings!
;;;                  every kind made NULL, in ready; refused in row, the row's
;;;                  5,000-byte value read back whole after
;;;   the states     each of the six verbs in every state, finalized included;
;;;                  not a statement, and another thread
;;;   reading        the type from sqlite3_column_type, never the declared
;;;                  type: BOOLEAN reads 1 and 0; the index against the count,
;;;                  read afresh after an alter table; column-bytevector's
;;;                  refusals; a UTF-16 database, where the accessor tells
;;;   not UTF-8      &sqlite-invalid-text from a real table holding raw bytes,
;;;                  column-bytevector reading the same bytes, and column-name
;;;                  for a name made from raw bytes
;;;   after the section
;;;                  every verb's raises reach a with-exception-handler handler
;;;                  at depth 1, against a no-raise sentinel
;;;
;;; NOMEM is tests/test-statement-values-nomem.sps's, since its heap limit is
;;; process-wide, and the two-engine sweeps tests/test-statement-values-sections.sps's.
;;;
;;; The loading procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them: a refused library fails the rows
;;; by name. SQLite's answers are the research's (.plans/research/m2-slice-4/)
;;; or measured on both libraries before a row asserts them (build/m2s4/probes/).
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure fork-thread make-mutex with-mutex sleep make-time
              get-thread-id disable-interrupts enable-interrupts library-exports)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3 private conditions) sqlite-invalid-text? sqlite-invalid-text-column
              sqlite-invalid-text-offset)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-error-message sqlite-error-sql sqlite-error-offset
              sqlite-wrong-thread? sqlite-wrong-thread-owner sqlite-wrong-thread-caller
              sqlite-closed?))

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

;; --- reached through eval -------------------------------------------------------------

;; public-load : (U 'loaded (List 'raised String))
(define public-load
  (guard (e (#t (list 'raised (describe e))))
    (eval '(sqlite-version) (environment '(chez-sqlite3)))
    'loaded))

;; reach : (Listof Symbol) Symbol -> Procedure
;; NAME's procedure in LIBRARY; when it cannot be reached, one that raises
;; that, naming NAME, every time it is called.
(define (reach library name)
  (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
    (eval name (environment library))))

(define values-library '(chez-sqlite3 private statement-values))
(define statement-library '(chez-sqlite3 private statement))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define step! (reach statement-library 'step!))
(define reset! (reach statement-library 'reset!))
(define column-count (reach statement-library 'column-count))
(define parameter-count (reach statement-library 'parameter-count))
(define statement-state (reach statement-library 'statement-state))
(define bind! (reach values-library 'bind!))
(define bind-all! (reach values-library 'bind-all!))
(define clear-bindings! (reach values-library 'clear-bindings!))
(define column-value (reach values-library 'column-value))
(define column-bytevector (reach values-library 'column-bytevector))
(define column-name (reach values-library 'column-name))
(define sql-null? (reach '(chez-sqlite3 private values) 'sql-null?))
(define call-with-bytes (reach '(chez-sqlite3 private native) 'call-with-bytes))
(define sqlite3-errmsg (reach '(chez-sqlite3 private native) 'sqlite3-errmsg))
(define c-string->string (reach '(chez-sqlite3 private native) 'c-string->string))
(define sql-null (guard (e (#t (list 'unreachable 'sql-null)))
                   (eval 'sql-null (environment '(chez-sqlite3 private values)))))

;; --- bindings made here, after the load ------------------------------------------------
;; foreign-procedure resolves its entry when it is evaluated, so each is made
;; once the load above has run; one that cannot be made raises when called.

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_limit(sqlite3*, int id, int newVal): the old value; -1 reads it.
(define limit (bound 'sqlite3_limit (foreign-procedure "sqlite3_limit" (uptr int int) int)))
;; int sqlite3_exec(sqlite3*, const char *sql, callback, void *, char **errmsg)
(define raw-exec (bound 'sqlite3_exec (foreign-procedure "sqlite3_exec" (uptr uptr uptr uptr uptr) int)))

;; SQLITE_LIMIT_LENGTH, sqlite3.h's limit id 0: the largest string or BLOB.
(define limit-length 0)

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

;; counts-with : (Listof (Pairof Symbol Integer)) -> (Listof (Pairof Symbol Integer))
(define (counts-with changes)
  (map (lambda (entry) (cond ((assq (car entry) changes) => (lambda (c) c)) (else entry)))
       zero-counts))

(define one-connection (counts-with '((connection . 1))))
(define (with-statements n) (counts-with (list '(connection . 1) (cons 'statement n))))

;; who-of : Condition -> Any
(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; message-of : Condition -> Symbol
;; Whether E has a message, never its text.
(define (message-of e) (if (message-condition? e) 'message 'no-message))

;; what-raised : Any -> Any
;; A raised object as this suite compares it: an &sqlite-error by its who,
;; code, extended code, SQL, offset, and whether its &message is its message
;; field; &sqlite-invalid-text by its who, column and offset; another library
;; condition by its type and who; an assertion violation by its who and
;; irritants; anything else as text.
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (sqlite-error-sql e) (sqlite-error-offset e)
               (if (and (message-condition? e) (string? (sqlite-error-message e))
                        (equal? (condition-message e) (sqlite-error-message e)))
                   'message-is-the-field
                   'message-differs)))
        ((sqlite-invalid-text? e)
         (list 'invalid-text (who-of e) (sqlite-invalid-text-column e) (sqlite-invalid-text-offset e)
               (message-of e)))
        ((sqlite-wrong-thread? e)
         (list 'wrong-thread (who-of e) (message-of e)
               (sqlite-wrong-thread-owner e) (sqlite-wrong-thread-caller e)))
        ((sqlite-closed? e) (list 'closed (who-of e) (message-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

;; sqlite-failure : Symbol Symbol Symbol (U String #f) -> List
;; What what-raised gives for an &sqlite-error with these fields and no offset.
(define (sqlite-failure who code extended sql)
  (list 'sqlite-error who code extended sql #f 'message-is-the-field))

(define (closed who) (list 'closed who 'message))
(define (refused who . irritants) (list 'assertion-violation who irritants))
(define (invalid who column offset) (list 'invalid-text who column offset 'message))
(define (not-allowed who state) (refused who 'not-allowed-in-state state))

;; attempt : (-> Any) -> Any
;; THUNK's answer, or (raised WHAT) for what it raised.
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define void-value (if #f #f))
(define (no-value x) (if (eq? x void-value) 'no-value x))

;; shown : Any -> Any
;; X, with sql-null written as the symbol sql-null.
(define (shown x) (if (and (not (pair? sql-null)) (eq? x sql-null)) 'sql-null x))

;; interrupt-depth : -> Positive-Integer
;; How many critical sections this thread is inside, plus one.
(define (interrupt-depth)
  (let ((n (disable-interrupts)))
    (enable-interrupts)
    n))

;; handler-depth : (-> Any) -> (U (List 'raised-at-depth Symbol Any) (List 'no-raise Any))
;; The depth a with-exception-handler handler runs at for the first thing
;; THUNK raises, written depth-N, and what it raised; the handler escapes.
;; (no-raise VALUE) when THUNK raises nothing.
(define (handler-depth thunk)
  (call/cc
   (lambda (k)
     (with-exception-handler
      (lambda (c)
        (let* ((depth (interrupt-depth))
               (what (what-raised c)))
          (k (list 'raised-at-depth
                   (string->symbol (string-append "depth-" (number->string depth)))
                   what))))
      (lambda ()
        (list 'no-raise (shown (no-value (thunk)))))))))

(define (at-depth-1 what) (list 'raised-at-depth 'depth-1 what))

;; at-raise : (-> Any) -> (List Any Any)
;; What THUNK raised, and the counts at the moment of the raise, read by a
;; handler that runs before any dynamic-wind's after thunk; (no-raise VALUE)
;; when it raised nothing.
(define raised-tag (list 'raised))
(define (at-raise thunk)
  (let* ((seen 'no-raise)
         (r (guard (e (#t (cons raised-tag e)))
              (with-exception-handler
               (lambda (c) (when (eq? seen 'no-raise) (set! seen (native-counts))) (raise c))
               thunk))))
    (if (and (pair? r) (eq? (car r) raised-tag))
        (list (what-raised (cdr r)) seen)
        (list (list 'no-raise (no-value r)) seen))))

;; undo! : (Listof Any) (Listof Any) -> Void
;; What a row left open on purpose, undone however it ends: STATEMENTS
;; finalized, then each of DATABASES closed. Nothing here raises.
(define (undo! statements databases)
  (for-each (lambda (s) (guard (e (#t #f)) (finalize-statement! s))) statements)
  (for-each (lambda (db) (guard (e (#t #f)) (close-database! db))) databases))

;; with-memory-db : (Database -> Any) -> Any
;; PROC's answer, or what it raised, given a fresh :memory: database that is
;; closed after, however PROC ends.
(define (with-memory-db proc)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda () (attempt (lambda () (set! db (open-database ":memory:")) (proc db))))
      (lambda () (when db (undo! '() (list db)))))))

;; in-dir : (String -> Any) -> Any
(define (in-dir proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory proc)))

;; with-handle : Any (Positive-Integer -> A) -> A
(define (with-handle db proc) (call-with-open-handle 'test-statement-values db proc))

;; exec! : Database String -> Any
;; SQL prepared, stepped once and finalized: what step! answered.
(define (exec! db sql)
  (let* ((st (prepare-statement db sql))
         (answer (guard (e (#t (finalize-statement! st) (raise e))) (step! st))))
    (finalize-statement! st)
    answer))

;; exec-bytes! : Database Bytevector -> Integer
;; SQL given as raw bytes, which no Scheme string can hold when they are no
;; UTF-8, run by the suite's own sqlite3_exec: its answer.
(define (exec-bytes! db bytes)
  (with-handle db
    (lambda (h)
      (call-with-bytes 'test-statement-values
                       (u8-list->bytevector (append (bytevector->u8-list bytes) '(0)))
        (lambda (sql) (raw-exec h sql 0 0 0))))))

;; columns : Statement -> (Listof Any)
;; Every column of ST's row by column-value, first to last, each answer or
;; what it raised, sql-null shown as such.
(define (columns st)
  (let ((n (column-count st)))
    (let loop ((i 0) (found '()))
      (if (= i n)
          (reverse found)
          (let ((v (shown (attempt (lambda () (column-value st i))))))
            (loop (+ i 1) (cons v found)))))))

;; read-back : String (Statement -> Any) -> Any
;; SQL prepared on a fresh :memory: database, BIND applied to the
;; statement, stepped once: what BIND answered or raised, what step!
;; answered, every column by column-value, the state, and the counts while
;; the statement lives.
(define (read-back sql bind)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db sql))
            (b (no-value (attempt (lambda () (bind st)))))
            (s (attempt (lambda () (step! st))))
            (cols (columns st))
            (state (statement-state st))
            (counts (native-counts)))
       (finalize-statement! st)
       (list b s cols state counts)))))

;; read-row : (List Any Any) Symbol -> List
;; What read-back gives for a bind that answered BOUND and a row of COLS.
(define (read-row bound cols) (list bound #t cols 'row (with-statements 1)))

;; hex-of : Bytevector -> String
;; BYTES as SQLite's hex() writes them: two upper-case digits each.
(define (hex-of bytes)
  (apply string-append
         (map (lambda (b)
                (let ((s (string-upcase (number->string b 16))))
                  (if (< b 16) (string-append "0" s) s)))
              (bytevector->u8-list bytes))))

;; long-bytes : Bytevector
;; 5,000 bytes, each its index modulo 256: bigger than SQLite's lookaside
;; slots, so Valgrind sees a free of it (ADR-0005, amended).
(define long-bytes
  (let ((b (make-bytevector 5000 0)))
    (let loop ((i 0))
      (when (< i 5000)
        (bytevector-u8-set! b i (mod i 256))
        (loop (+ i 1))))
    b))

;; in-thread : (-> Any) -> Any
;; THUNK's answer on a forked thread, as (answer VALUE THREAD-ID), whatever it
;; raised being its answer; the-thread-hung when it gives none within 120 s.
(define (in-thread thunk)
  (let ((m (make-mutex)) (answer #f))
    (fork-thread
     (lambda ()
       (let ((a (guard (e (#t (list 'answer (list 'raised (what-raised e)) (get-thread-id))))
                  (list 'answer (thunk) (get-thread-id)))))
         (with-mutex m (set! answer a)))))
    (if (eq? (run-until (lambda () (sleep (make-time 'time-duration 10000000 0)))
                        (lambda () (with-mutex m answer)) 12000)
             'satisfied)
        (with-mutex m answer)
        'the-thread-hung)))

;; ids : Any Integer Integer -> Any
;; X with MAIN written main and THREAD written the-thread, wherever they are.
(define (ids x main thread)
  (cond ((eqv? x main) 'main)
        ((eqv? x thread) 'the-thread)
        ((pair? x) (cons (ids (car x) main thread) (ids (cdr x) main thread)))
        (else x)))

;; from-another-thread : (-> Any) -> Any
;; What THUNK answered or raised on a forked thread, with the ids named.
(define (from-another-thread thunk)
  (let* ((main (get-thread-id))
         (a (in-thread (lambda () (attempt thunk)))))
    (if (and (list? a) (= (length a) 3) (not (eqv? (caddr a) main)))
        (ids (cadr a) main (caddr a))
        (list 'not-another-thread a))))

;; the six verbs, each given a statement, with their names.
(define value-verbs
  (list (cons 'bind! (lambda (st) (bind! st 1 5)))
        (cons 'bind-all! (lambda (st) (bind-all! st 5)))
        (cons 'clear-bindings! (lambda (st) (clear-bindings! st)))
        (cons 'column-value (lambda (st) (column-value st 0)))
        (cons 'column-bytevector (lambda (st) (column-bytevector st 0)))
        (cons 'column-name (lambda (st) (column-name st 0)))))

(test-begin "statement-values")

;; --- the load -------------------------------------------------------------------------------

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-equal "(chez-sqlite3 private statement-values) exports exactly its six verbs"
  '(bind! bind-all! clear-bindings! column-bytevector column-name column-value)
  (guard (e (#t (list 'raised (describe e))))
    (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
               (library-exports values-library))))

;; --- binding: what binds, and what is refused --------------------------------------------------

(define typed-sql "select ?1, typeof(?1)")

(test-equal "an exact integer binds through sqlite3_bind_int64 at its boundaries, 2^63-1 and -2^63, and at 0, 1 and -1, each read back exact and INTEGER"
  (list (read-row 'no-value (list 9223372036854775807 "integer"))
        (read-row 'no-value (list -9223372036854775808 "integer"))
        (read-row 'no-value (list 0 "integer"))
        (read-row 'no-value (list 1 "integer"))
        (read-row 'no-value (list -1 "integer")))
  (let* ((a (read-back typed-sql (lambda (st) (bind! st 1 (- (expt 2 63) 1)))))
         (b (read-back typed-sql (lambda (st) (bind! st 1 (- (expt 2 63))))))
         (c (read-back typed-sql (lambda (st) (bind! st 1 0))))
         (d (read-back typed-sql (lambda (st) (bind! st 1 1))))
         (e (read-back typed-sql (lambda (st) (bind! st 1 -1)))))
    (list a b c d e)))

;; refused-over : Any Any -> Any
;; read-back of a bind of VALUE refused over SENTINEL, bound first.
(define (refused-over sentinel value)
  (read-back typed-sql (lambda (st) (bind! st 1 sentinel) (bind! st 1 value))))

(define (refused-row rule kind sentinel type)
  (read-row (list 'raised (refused 'bind! rule 1 (list 'kind kind))) (list sentinel type)))

(test-equal "2^63, 2^64-1 and -2^63-1 are refused by integer-out-of-range, naming parameter 1 and the value by its kind; each parameter keeps the sentinel bound before it"
  (list (refused-row 'integer-out-of-range 'number 101 "integer")
        (refused-row 'integer-out-of-range 'number 102 "integer")
        (refused-row 'integer-out-of-range 'number 103 "integer"))
  (let* ((a (refused-over 101 (expt 2 63)))
         (b (refused-over 102 (- (expt 2 64) 1)))
         (c (refused-over 103 (- (- (expt 2 63)) 1))))
    (list a b c)))

(test-equal "+inf.0 and -inf.0 bind as REAL and read back; -0.0 reads back -0.0 through select ?, REAL; 2.5 reads back 2.5"
  (list (read-row 'no-value (list +inf.0 "real"))
        (read-row 'no-value (list -inf.0 "real"))
        (read-row 'no-value (list -0.0 "real"))
        (read-row 'no-value (list 2.5 "real")))
  (let* ((a (read-back typed-sql (lambda (st) (bind! st 1 +inf.0))))
         (b (read-back typed-sql (lambda (st) (bind! st 1 -inf.0))))
         (c (read-back typed-sql (lambda (st) (bind! st 1 -0.0))))
         (d (read-back typed-sql (lambda (st) (bind! st 1 2.5)))))
    (list a b c d)))

(test-equal "-0.0 bound into a column declared REAL reads back 0.0, REAL, its sign lost, as SQLite stores it (measured)"
  (list #f #f (list 0.0 "real") 'row)
  (with-memory-db
   (lambda (db)
     (let* ((a (exec! db "create table r (x real)"))
            (ins (prepare-statement db "insert into r values (?1)"))
            (b (begin (bind! ins 1 -0.0) (step! ins)))
            (f (finalize-statement! ins))
            (st (prepare-statement db "select x, typeof(x) from r"))
            (s (step! st))
            (cols (columns st))
            (state (statement-state st)))
       (finalize-statement! st)
       (list a b cols state)))))

(test-equal "+nan.0, and a NaN made by arithmetic, are refused by nan (D4); each parameter keeps its sentinel"
  (list (refused-row 'nan 'number 201 "integer")
        (refused-row 'nan 'number 202 "integer"))
  (let* ((a (refused-over 201 +nan.0))
         (b (refused-over 202 (/ 0.0 0.0))))
    (list a b)))

(test-equal "#t and #f are refused by boolean (D5); an exact non-integer, an exact complex, an inexact complex, a symbol, a character, a list and a vector by not-a-value, each named by its kind; each parameter keeps its sentinel"
  (list (refused-row 'boolean 'boolean 301 "integer")
        (refused-row 'boolean 'boolean 302 "integer")
        (refused-row 'not-a-value 'number 303 "integer")
        (refused-row 'not-a-value 'number 304 "integer")
        (refused-row 'not-a-value 'number 305 "integer")
        (refused-row 'not-a-value 'symbol 306 "integer")
        (refused-row 'not-a-value 'char 307 "integer")
        (refused-row 'not-a-value 'list 308 "integer")
        (refused-row 'not-a-value 'vector 309 "integer"))
  (let* ((a (refused-over 301 #t))
         (b (refused-over 302 #f))
         (c (refused-over 303 1/2))
         (d (refused-over 304 1+2i))
         (e (refused-over 305 1.0+2.0i))
         (f (refused-over 306 'one))
         (g (refused-over 307 #\1))
         (h (refused-over 308 '(1)))
         (i (refused-over 309 (vector 1))))
    (list a b c d e f g h i)))

(define text-sql "select ?1, typeof(?1), hex(?1)")

;; text-row : String -> List
;; What read-back gives for S bound: S, text, and its UTF-8 in hex.
(define (text-row s) (read-row 'no-value (list s "text" (hex-of (string->utf8 s)))))

(test-equal "a string binds as UTF-8 TEXT with its byte length and reads back the same, its bytes as written: e-acute C3 A9, the euro sign E2 82 AC, U+1F600 F0 9F 98 80, U+0000 inside 61 00 62, a leading U+FEFF EF BB BF 78, and the empty string, TEXT and not NULL"
  (list (read-row 'no-value (list "\xE9;" "text" "C3A9"))
        (read-row 'no-value (list "\x20AC;" "text" "E282AC"))
        (read-row 'no-value (list "\x1F600;" "text" "F09F9880"))
        (read-row 'no-value (list "a\x0;b" "text" "610062"))
        (read-row 'no-value (list "\xFEFF;x" "text" "EFBBBF78"))
        (read-row 'no-value (list "" "text" ""))
        (text-row "a\xE9;\x20AC;\x1F600;\x0;\xFEFF;z"))
  (let* ((a (read-back text-sql (lambda (st) (bind! st 1 "\xE9;"))))
         (b (read-back text-sql (lambda (st) (bind! st 1 "\x20AC;"))))
         (c (read-back text-sql (lambda (st) (bind! st 1 "\x1F600;"))))
         (d (read-back text-sql (lambda (st) (bind! st 1 "a\x0;b"))))
         (e (read-back text-sql (lambda (st) (bind! st 1 "\xFEFF;x"))))
         (f (read-back text-sql (lambda (st) (bind! st 1 ""))))
         (g (read-back text-sql (lambda (st) (bind! st 1 "a\xE9;\x20AC;\x1F600;\x0;\xFEFF;z")))))
    (list a b c d e f g)))

(test-equal "a bytevector binds as a BLOB with its length and reads back a fresh copy: the empty one BLOB and not NULL, 00, 01 02 FF, and 5,000 bytes whole"
  (list (read-row 'no-value (list #vu8() "blob" ""))
        (read-row 'no-value (list #vu8(0) "blob" "00"))
        (read-row 'no-value (list #vu8(1 2 #xFF) "blob" "0102FF"))
        (read-row 'no-value (list 'same "blob" 'same)))
  (let* ((a (read-back text-sql (lambda (st) (bind! st 1 #vu8()))))
         (b (read-back text-sql (lambda (st) (bind! st 1 #vu8(0)))))
         (c (read-back text-sql (lambda (st) (bind! st 1 #vu8(1 2 #xFF)))))
         (d (read-back text-sql (lambda (st) (bind! st 1 long-bytes)))))
    (list a b c
          (if (and (list? d) (= (length d) 5) (list? (caddr d)) (= (length (caddr d)) 3))
              (let ((cols (caddr d)))
                (list (car d) (cadr d)
                      (list (if (equal? (car cols) long-bytes) 'same (car cols))
                            (cadr cols)
                            (if (equal? (caddr cols) (hex-of long-bytes)) 'same 'differs))
                      (cadddr d) (car (cddddr d))))
              d))))

(test-equal "the bytevector a column gives is fresh: changing it leaves the next read, and two reads are two bytevectors"
  (list #vu8(1 2 3) 'two)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select ?1"))
            (b (bind! st 1 #vu8(1 2 3)))
            (s (step! st))
            (first (column-value st 0))
            (changed (bytevector-u8-set! first 0 9))
            (second (column-value st 0))
            (third (column-value st 0)))
       (finalize-statement! st)
       (list second (if (eq? second third) 'one 'two))))))

(test-equal "sql-null binds NULL over a sentinel, and an unbound parameter's NULL reads back sql-null"
  (list (read-row 'no-value (list 'sql-null "null"))
        (read-row 'no-value (list 'sql-null "null")))
  (let* ((a (read-back typed-sql (lambda (st) (bind! st 1 7) (bind! st 1 sql-null))))
         (b (read-back typed-sql (lambda (st) (if #f #f)))))
    (list a b)))

(test-equal "a column declared BOOLEAN reads back 1 and 0, exact integers by their storage class, never booleans: TRUE, FALSE and 1 and 0 bound"
  (list (list 1 "integer") (list 0 "integer") (list 1 "integer") (list 0 "integer"))
  (with-memory-db
   (lambda (db)
     (let* ((a (exec! db "create table b (k integer primary key, x boolean)"))
            (c (exec! db "insert into b (x) values (TRUE), (FALSE)"))
            (ins (prepare-statement db "insert into b (x) values (?1)"))
            (d (begin (bind! ins 1 1) (step! ins) (reset! ins) (bind! ins 1 0) (step! ins)))
            (f (finalize-statement! ins))
            (st (prepare-statement db "select x, typeof(x) from b order by k")))
       (let loop ((found '()))
         (if (step! st)
             (let ((row (columns st))) (loop (cons row found)))
             (begin (finalize-statement! st) (reverse found))))))))

;; --- parameters ------------------------------------------------------------------------------

(test-equal "bind! by index, 1 to the count, in any order: select ?1, ?2, ?3 reads back 1, 2.5 and c"
  (read-row 'no-value (list 1 2.5 "c"))
  (read-back "select ?1, ?2, ?3"
             (lambda (st) (bind! st 3 "c") (bind! st 1 1) (bind! st 2 2.5))))

(test-equal "bind! by each sigil's name, the name as the SQL writes it: ?5 at 5, :a at 6, @b at 7 and $c at 8, of 8 parameters"
  (list 8 (read-row 'no-value (list 1 "two" 3.5 #vu8(4))))
  (list (with-memory-db
         (lambda (db)
           (let* ((st (prepare-statement db "select ?5, :a, @b, $c"))
                  (n (parameter-count st)))
             (finalize-statement! st)
             n)))
        (read-back "select ?5, :a, @b, $c"
                   (lambda (st) (bind! st "$c" #vu8(4)) (bind! st "?5" 1) (bind! st ":a" "two")
                           (bind! st "@b" 3.5)))))

(test-equal "a name used twice is one parameter: select :a, :a has 1, and :a bound reads back in both columns; :a's index is 1"
  (list 1 (read-row 'no-value (list 9 9)) (read-row 'no-value (list 8 8)))
  (list (with-memory-db
         (lambda (db)
           (let* ((st (prepare-statement db "select :a, :a")) (n (parameter-count st)))
             (finalize-statement! st)
             n)))
        (read-back "select :a, :a" (lambda (st) (bind! st ":a" 9)))
        (read-back "select :a, :a" (lambda (st) (bind! st 1 8)))))

(define named-sql "select :a, typeof(:a)")
(define (named-sentinel st) (bind! st ":a" 401))

(test-equal "a name no parameter has is refused by no-such-parameter, by its kind: :nope, a without its sigil, :A in the wrong case, the empty name; each leaves the sentinel"
  (let ((r (read-row (list 'raised (refused 'bind! 'no-such-parameter '(kind string)))
                     (list 401 "integer"))))
    (list r r r r))
  (let* ((a (read-back named-sql (lambda (st) (named-sentinel st) (bind! st ":nope" 1))))
         (b (read-back named-sql (lambda (st) (named-sentinel st) (bind! st "a" 1))))
         (c (read-back named-sql (lambda (st) (named-sentinel st) (bind! st ":A" 1))))
         (d (read-back named-sql (lambda (st) (named-sentinel st) (bind! st "" 1)))))
    (list a b c d)))

;; nul-name : String -> (List Any Any Any)
;; A bind by NAME over the sentinel: what was raised and the counts at the
;; raise, then the column read after.
(define (nul-name name)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db named-sql))
            (s (named-sentinel st))
            (r (at-raise (lambda () (bind! st name 1))))
            (step (step! st))
            (v (column-value st 0)))
       (finalize-statement! st)
       (list r v)))))

(test-equal "a name holding U+0000, first, inside and last, is refused by parameter-name-holds-nul, by its kind, with no block allocated at the raise; the sentinel stays"
  (let ((r (list (list (refused 'bind! 'parameter-name-holds-nul '(kind string)) (with-statements 1))
                 401)))
    (list r r r))
  (let* ((a (nul-name "\x0;:a"))
         (b (nul-name ":\x0;a"))
         (c (nul-name ":a\x0;")))
    (list a b c)))

(define two-sql "select ?1, ?2")
(define (two-sentinels st) (bind! st 1 501) (bind! st 2 502))

(test-equal "an index outside 1 to the count is refused by parameter-out-of-range, naming the index and the count: 0, 3 of 2, -1 and 2^64; what is no index nor name by not-a-parameter: 1.5, a symbol, #t, a list by its kind; each leaves the sentinels"
  (map (lambda (irritants) (read-row (list 'raised (apply refused 'bind! irritants)) (list 501 502)))
       (list '(parameter-out-of-range 0 2) '(parameter-out-of-range 3 2)
             '(parameter-out-of-range -1 2) (list 'parameter-out-of-range (expt 2 64) 2)
             '(not-a-parameter 1.5) '(not-a-parameter x) '(not-a-parameter #t)
             '(not-a-parameter (kind list))))
  (let* ((a (read-back two-sql (lambda (st) (two-sentinels st) (bind! st 0 1))))
         (b (read-back two-sql (lambda (st) (two-sentinels st) (bind! st 3 1))))
         (c (read-back two-sql (lambda (st) (two-sentinels st) (bind! st -1 1))))
         (d (read-back two-sql (lambda (st) (two-sentinels st) (bind! st (expt 2 64) 1))))
         (e (read-back two-sql (lambda (st) (two-sentinels st) (bind! st 1.5 1))))
         (f (read-back two-sql (lambda (st) (two-sentinels st) (bind! st 'x 1))))
         (g (read-back two-sql (lambda (st) (two-sentinels st) (bind! st #t 1))))
         (h (read-back two-sql (lambda (st) (two-sentinels st) (bind! st '(":a") 1)))))
    (list a b c d e f g h)))

(test-equal "bind!'s checks come in order: the state before the parameter, the parameter before the value; a value refused by an index in range names it"
  (list (list 'raised (not-allowed 'bind! 'row))
        (list 'raised (refused 'bind! 'parameter-out-of-range 9 2))
        (list 'raised (refused 'bind! 'no-such-parameter '(kind string)))
        (list 'raised (refused 'bind! 'boolean 2 '(kind boolean)))
        (list 'raised (refused 'bind! 'boolean '(kind string) '(kind boolean))))
  (with-memory-db
   (lambda (db)
     (let* ((row (prepare-statement db "select ?1, ?2"))
            (s (step! row))
            (a (attempt (lambda () (bind! row 9 #t))))
            (st (prepare-statement db "select :x, ?2"))
            (b (attempt (lambda () (bind! st 9 #t))))
            (c (attempt (lambda () (bind! st ":y" #t))))
            (d (attempt (lambda () (bind! st 2 #t))))
            (e (attempt (lambda () (bind! st ":x" #t)))))
       (finalize-statement! row)
       (finalize-statement! st)
       (list a b c d e)))))

(test-equal "bind-all! binds every parameter, 1 to n, in order: select ?1, ?2 reads back 1 and b; select 1 takes no values"
  (list (read-row 'no-value (list 1 "b")) (read-row 'no-value (list 1)))
  (let* ((a (read-back two-sql (lambda (st) (bind-all! st 1 "b"))))
         (b (read-back "select 1" (lambda (st) (bind-all! st)))))
    (list a b)))

(test-equal "bind-all! with the wrong count is refused by value-count-mismatch, naming the count given and the parameter count: none, 1 and 3 values for 2, binding nothing"
  (map (lambda (n) (read-row (list 'raised (refused 'bind-all! 'value-count-mismatch n 2)) (list 501 502)))
       '(0 1 3))
  (let* ((a (read-back two-sql (lambda (st) (two-sentinels st) (bind-all! st))))
         (b (read-back two-sql (lambda (st) (two-sentinels st) (bind-all! st 1))))
         (c (read-back two-sql (lambda (st) (two-sentinels st) (bind-all! st 1 2 3)))))
    (list a b c)))

(test-equal "bind-all! with a bad value among good ones binds nothing: #t second, by boolean naming parameter 2; NaN third, by nan naming 3; the count checked before the values"
  (list (read-row (list 'raised (refused 'bind-all! 'boolean 2 '(kind boolean))) (list 601 602 603))
        (read-row (list 'raised (refused 'bind-all! 'nan 3 '(kind number))) (list 601 602 603))
        (read-row (list 'raised (refused 'bind-all! 'value-count-mismatch 1 3)) (list 601 602 603)))
  (let* ((three (lambda (st) (bind! st 1 601) (bind! st 2 602) (bind! st 3 603)))
         (a (read-back "select ?1, ?2, ?3" (lambda (st) (three st) (bind-all! st 1 #t "x"))))
         (b (read-back "select ?1, ?2, ?3" (lambda (st) (three st) (bind-all! st 1 "y" +nan.0))))
         (c (read-back "select ?1, ?2, ?3" (lambda (st) (three st) (bind-all! st #t)))))
    (list a b c)))

;; --- a bind SQLite refuses -----------------------------------------------------------------------
;; SQLITE_LIMIT_LENGTH is lowered after the prepare, since it holds the
;; statement's column names at prepare too (the research's trap), and to 30,
;; the smallest 3.53.1 keeps; the floor keeps it too. 30 bytes then bind on
;; both, and 31 answer SQLITE_TOOBIG (the research, item 2).

(define (text-of n) (make-string n #\a))
(define (bytes-of n) (make-bytevector n 98))

;; limited : String (Database Statement -> Any) -> Any
;; SQL prepared on a fresh :memory: database, a failed prepare made first so
;; the connection holds an error offset, 7, then SQLITE_LIMIT_LENGTH lowered
;; to 30: the limit read back, and PROC's answer given the statement.
(define (limited sql proc)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db sql))
            (failed (attempt (lambda () (prepare-statement db "select nosuch_col"))))
            (old (with-handle db (lambda (h) (limit h limit-length 30))))
            (now (with-handle db (lambda (h) (limit h limit-length -1))))
            (r (proc db st)))
       (finalize-statement! st)
       (list now r)))))

;; refused-bind : Database Statement (-> Any) -> List
;; THUNK's raise, whether its message is sqlite3_errmsg's straight after, the
;; state, and the row the statement then reads.
(define (refused-bind db st thunk)
  (let* ((r (guard (e (#t (cons raised-tag e))) (thunk) 'no-raise))
         (now (with-handle db (lambda (h) (c-string->string (sqlite3-errmsg h)))))
         (what (if (and (pair? r) (eq? (car r) raised-tag))
                   (list (what-raised (cdr r))
                         (if (and (sqlite-error? (cdr r)) (equal? (sqlite-error-message (cdr r)) now))
                             'the-message-after-the-bind
                             'another-message))
                   (list 'no-raise r)))
         (state (statement-state st))
         (s (step! st))
         (cols (columns st)))
    (reset! st)
    (list what state cols)))

(test-equal "over SQLITE_LIMIT_LENGTH lowered to 30, a 31-byte TEXT and a 31-byte BLOB each raise &sqlite-error toobig from bind!, with the SQL, no offset though a failed prepare left one, and sqlite3_errmsg's message straight after; the parameter is NULL, not the sentinel, and the state ready; 30 bytes bind"
  (list 30
        (list (list (list (sqlite-failure 'bind! 'toobig 'toobig "select ?1") 'the-message-after-the-bind)
                    'ready '(sql-null))
              (list (list (sqlite-failure 'bind! 'toobig 'toobig "select ?1") 'the-message-after-the-bind)
                    'ready '(sql-null))
              (list (list 'no-raise 'no-raise) 'ready (list (text-of 30)))
              (list (list 'no-raise 'no-raise) 'ready (list (bytes-of 30)))))
  (limited "select ?1"
           (lambda (db st)
             (let* ((a (refused-bind db st (lambda () (bind! st 1 "old") (bind! st 1 (text-of 31)))))
                    (b (refused-bind db st (lambda () (bind! st 1 "old") (bind! st 1 (bytes-of 31)))))
                    (c (refused-bind db st (lambda () (bind! st 1 (text-of 30)))))
                    (d (refused-bind db st (lambda () (bind! st 1 (bytes-of 30))))))
               (list a b c d)))))

(test-equal "bind-all! refused by SQLite midway: ?1 bound first, then ?2's 31 bytes raise toobig from bind-all!; ?1 reads back first and ?2 NULL, not its sentinel; the state ready"
  (list 30 (list (list (sqlite-failure 'bind-all! 'toobig 'toobig "select ?1, ?2") 'the-message-after-the-bind)
                 'ready (list "first" 'sql-null)))
  (limited "select ?1, ?2"
           (lambda (db st)
             (refused-bind db st (lambda () (bind! st 1 "s1") (bind! st 2 "s2")
                                         (bind-all! st "first" (text-of 31)))))))

;; --- clear-bindings! -----------------------------------------------------------------------------

(test-equal "clear-bindings! makes every kind NULL again, in ready: an INTEGER, a REAL, a TEXT, a BLOB and a NULL"
  (list (read-row 'no-value (list 7 2.5 "t" #vu8(1) 'sql-null))
        (read-row 'no-value (list 'sql-null 'sql-null 'sql-null 'sql-null 'sql-null)))
  (list (read-back "select ?1, ?2, ?3, ?4, ?5"
                   (lambda (st) (bind-all! st 7 2.5 "t" #vu8(1) sql-null)))
        (read-back "select ?1, ?2, ?3, ?4, ?5"
                   (lambda (st) (bind-all! st 7 2.5 "t" #vu8(1) sql-null) (clear-bindings! st)))))

(test-equal "clear-bindings! is refused while a row is ready, naming row: the row's 5,000-byte BLOB, which SQLite would free, reads back whole after, and the state stays row"
  (list (list 'raised (not-allowed 'clear-bindings! 'row)) 'same 'row)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select ?1"))
            (b (bind! st 1 long-bytes))
            (s (step! st))
            (r (attempt (lambda () (clear-bindings! st))))
            (v (column-value st 0))
            (state (statement-state st)))
       (finalize-statement! st)
       (list r (if (equal? v long-bytes) 'same 'differs) state)))))

;; --- the state table ---------------------------------------------------------------------------
;; Each state reached by SQL on t, x unique, holding the row 0: ready, a
;; select of one parameter and two columns prepared; row, it stepped once;
;; done, twice; failed, an insert ... returning of 0 stepped; finalized, the
;; select finalized.

(define ready-sql "select 'v' || x as v, ?1 as p from t")
(define failing-sql "insert into t values (coalesce(?1, 0)) returning x as v")

;; in-state : Database Symbol -> Statement
(define (in-state db state)
  (case state
    ((ready) (prepare-statement db ready-sql))
    ((row) (let ((st (prepare-statement db ready-sql))) (step! st) st))
    ((done) (let ((st (prepare-statement db ready-sql))) (step! st) (step! st) st))
    ((failed) (let ((st (prepare-statement db failing-sql)))
                (guard (e (#t #f)) (step! st))
                st))
    (else (let ((st (prepare-statement db ready-sql))) (finalize-statement! st) st))))

(define states '(ready row done failed finalized))

;; with-table-db : (Database -> Any) -> Any
;; PROC given a :memory: database holding t, x unique, with the row 0.
(define (with-table-db proc)
  (with-memory-db
   (lambda (db)
     (exec! db "create table t (x unique)")
     (exec! db "insert into t values (0)")
     (proc db))))

;; cell : (Statement -> Any) Symbol -> (List Symbol Any Symbol Natural)
;; VERB on a statement in STATE: the state, what VERB answered or raised,
;; the state after, and the statement count.
(define (cell verb state)
  (with-table-db
   (lambda (db)
     (let* ((st (in-state db state))
            (answer (shown (no-value (attempt (lambda () (verb st))))))
            (after (statement-state st))
            (counted (cdr (assq 'statement (native-counts)))))
       (finalize-statement! st)
       (list state answer after counted)))))

;; row-of : (Statement -> Any) -> (Listof Any)
;; VERB's cell in each state, first to last.
(define (row-of verb)
  (let loop ((rest states) (found '()))
    (if (null? rest)
        (reverse found)
        (let ((c (cell verb (car rest)))) (loop (cdr rest) (cons c found))))))

;; ready-only : Symbol Any -> (Listof Any)
;; The expected row of a verb allowed in ready alone, answering ANSWER there.
(define (ready-only who answer)
  (list (list 'ready answer 'ready 1)
        (list 'row (list 'raised (not-allowed who 'row)) 'row 1)
        (list 'done (list 'raised (not-allowed who 'done)) 'done 1)
        (list 'failed (list 'raised (not-allowed who 'failed)) 'failed 1)
        (list 'finalized (list 'raised (closed who)) 'finalized 0)))

;; row-only : Symbol Any -> (Listof Any)
(define (row-only who answer)
  (list (list 'ready (list 'raised (not-allowed who 'ready)) 'ready 1)
        (list 'row answer 'row 1)
        (list 'done (list 'raised (not-allowed who 'done)) 'done 1)
        (list 'failed (list 'raised (not-allowed who 'failed)) 'failed 1)
        (list 'finalized (list 'raised (closed who)) 'finalized 0)))

(test-equal "bind!, bind-all! and clear-bindings! in every state: allowed in ready alone, raising nothing and leaving it ready; row, done and failed refused by the rule, naming the state, which stays; finalized &sqlite-closed"
  (list (ready-only 'bind! 'no-value) (ready-only 'bind-all! 'no-value)
        (ready-only 'clear-bindings! 'no-value))
  (let* ((a (row-of (lambda (st) (bind! st 1 5))))
         (b (row-of (lambda (st) (bind-all! st 5))))
         (c (row-of (lambda (st) (clear-bindings! st)))))
    (list a b c)))

(test-equal "column-value and column-bytevector in every state: allowed in row alone, reading v0 and its bytes 76 30; ready, done and failed refused, naming the state; finalized &sqlite-closed"
  (list (row-only 'column-value "v0") (row-only 'column-bytevector #vu8(#x76 #x30)))
  (let* ((a (row-of (lambda (st) (column-value st 0))))
         (b (row-of (lambda (st) (column-bytevector st 0)))))
    (list a b)))

(test-equal "column-name in every state but finalized answers the name, v, leaving the state; finalized &sqlite-closed"
  (list (list 'ready "v" 'ready 1) (list 'row "v" 'row 1) (list 'done "v" 'done 1)
        (list 'failed "v" 'failed 1) (list 'finalized (list 'raised (closed 'column-name)) 'finalized 0))
  (row-of (lambda (st) (column-name st 0))))

(test-equal "every verb refuses what is no statement, from the verb, by not-a-statement and shown-value: a symbol, a string by its kind"
  (map (lambda (v) (list (car v) (list 'raised (refused (car v) 'not-a-statement 'x))
                         (list 'raised (refused (car v) 'not-a-statement '(kind string)))))
       value-verbs)
  (let loop ((rest value-verbs) (found '()))
    (if (null? rest)
        (reverse found)
        (let* ((v (car rest))
               (a (attempt (lambda () ((cdr v) 'x))))
               (b (attempt (lambda () ((cdr v) "st")))))
          (loop (cdr rest) (cons (list (car v) a b) found))))))

(test-equal "every verb on another thread raises &sqlite-wrong-thread from the verb, the owner the main thread and the caller the other, before its state is checked; the statement stays ready, and its sentinel bound"
  (list (map (lambda (v) (list (car v) (list 'raised (list 'wrong-thread (car v) 'message 'main 'the-thread))))
             value-verbs)
        'ready (read-row 'no-value (list "v0" 701)))
  (with-table-db
   (lambda (db)
     (let* ((st (prepare-statement db ready-sql))
            (b (bind! st 1 701))
            (r (let loop ((rest value-verbs) (found '()))
                 (if (null? rest)
                     (reverse found)
                     (let ((a (from-another-thread (lambda () ((cdr (car rest)) st)))))
                       (loop (cdr rest) (cons (list (car (car rest)) a) found))))))
            (state (statement-state st))
            (s (step! st))
            (cols (columns st))
            (after (statement-state st))
            (counts (native-counts)))
       (finalize-statement! st)
       (list r state (list 'no-value s cols after counts))))))

;; --- reading ------------------------------------------------------------------------------------

;; index-refusals : Symbol (Statement Any -> Any) -> List
;; READ of a two-column row at -1, 2, 1.5 and a symbol: each refusal, then
;; the state.
(define (index-refusals read)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select 1, 2"))
            (s (step! st))
            (a (attempt (lambda () (read st -1))))
            (b (attempt (lambda () (read st 2))))
            (c (attempt (lambda () (read st 1.5))))
            (d (attempt (lambda () (read st 'x))))
            (state (statement-state st)))
       (finalize-statement! st)
       (list a b c d state)))))

(define (index-row who)
  (list (list 'raised (refused who 'column-out-of-range -1 2))
        (list 'raised (refused who 'column-out-of-range 2 2))
        (list 'raised (refused who 'not-a-column-index 1.5))
        (list 'raised (refused who 'not-a-column-index 'x))
        'row))

(test-equal "a column's index is checked against the column count, read in the read's section: -1 and 2 of 2 by column-out-of-range, naming the index and the count; 1.5 and a symbol by not-a-column-index; for each read, the state left row"
  (list (index-row 'column-value) (index-row 'column-bytevector) (index-row 'column-name))
  (let* ((a (index-refusals column-value))
         (b (index-refusals column-bytevector))
         (c (index-refusals column-name)))
    (list a b c)))

(test-equal "the column count is read afresh at every read: a held select * of two columns reads its third, 9, after an alter table on its connection and the next step; then, after a drop column, the third is refused, 2 of 2"
  (list 2 3 9 (list 'raised (refused 'column-value 'column-out-of-range 2 2)))
  (with-memory-db
   (lambda (db)
     (let* ((a (exec! db "create table d (a, b)"))
            (b (exec! db "insert into d values (1, 2)"))
            (st (prepare-statement db "select * from d"))
            (before (column-count st))
            (c (exec! db "alter table d add column c default 9"))
            (s (step! st))
            (after (column-count st))
            (v (column-value st 2))
            (r (reset! st))
            (e (exec! db "alter table d drop column c"))
            (s2 (step! st))
            (gone (attempt (lambda () (column-value st 2)))))
       (finalize-statement! st)
       (list before after v gone)))))

(test-equal "column-bytevector: TEXT as its UTF-8 bytes, BLOB as a fresh copy, NULL sql-null; an INTEGER and a FLOAT refused by not-text-or-blob, naming the column and integer or float; the state left row"
  (list #vu8(#xC3 #xA9) #vu8(1 2) 'sql-null #vu8()
        (list 'raised (refused 'column-bytevector 'not-text-or-blob 4 'integer))
        (list 'raised (refused 'column-bytevector 'not-text-or-blob 5 'float))
        'row)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select '\xE9;', x'0102', null, '', 7, 2.5"))
            (s (step! st))
            (a (attempt (lambda () (column-bytevector st 0))))
            (b (attempt (lambda () (column-bytevector st 1))))
            (c (shown (attempt (lambda () (column-bytevector st 2)))))
            (d (attempt (lambda () (column-bytevector st 3))))
            (e (attempt (lambda () (column-bytevector st 4))))
            (f (attempt (lambda () (column-bytevector st 5))))
            (state (statement-state st)))
       (finalize-statement! st)
       (list a b c d e f state)))))

(test-equal "column-value by sqlite3_column_type: an INTEGER past a double's precision exact, a REAL a flonum, a TEXT a string, a BLOB a bytevector, the empty TEXT and BLOB, NULL sql-null"
  (list 9007199254740993 0.5 "t" #vu8(#xFF 0) "" #vu8() 'sql-null)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select 9007199254740993, 0.5, 't', x'ff00', '', x'', null"))
            (s (step! st))
            (cols (columns st)))
       (finalize-statement! st)
       cols))))

;; utf16-reads : -> Any
;; In a UTF-16le database, a table holding TEXT 'é', 'aé' and '' and BLOB
;; x'4100': each read by column-value and by column-bytevector, on a step
;; of its own, so no read follows another's conversion.
(define (utf16-reads)
  (with-memory-db
   (lambda (db)
     (exec! db "pragma encoding = 'UTF-16le'")
     (exec! db "create table w (k integer primary key, x)")
     (exec! db "insert into w (x) values ('\xE9;'), ('a\xE9;'), (''), (x'4100')")
     (let ((one (lambda (k read)
                  (let* ((st (prepare-statement db (string-append "select x from w where k = "
                                                                  (number->string k))))
                         (s (step! st))
                         (v (attempt (lambda () (read st 0)))))
                    (finalize-statement! st)
                    v))))
       (let loop ((k 1) (found '()))
         (if (> k 4)
             (reverse found)
             (let* ((v (one k column-value))
                    (b (one k column-bytevector)))
               (loop (+ k 1) (cons (list v b) found)))))))))

(test-equal "in a UTF-16le database, TEXT is read through sqlite3_column_text, converted to UTF-8: e-acute and a e-acute read back, and column-bytevector gives C3 A9 and 61 C3 A9, not the stored E9 00; the empty TEXT reads empty; a BLOB, through sqlite3_column_blob, reads 41 00 by both, never column_text's 41 (measured on both libraries)"
  (list (list "\xE9;" #vu8(#xC3 #xA9))
        (list "a\xE9;" #vu8(#x61 #xC3 #xA9))
        (list "" #vu8())
        (list #vu8(#x41 0) #vu8(#x41 0)))
  (utf16-reads))

;; --- TEXT that is not UTF-8 ------------------------------------------------------------------
;; SQLite stores bytes that are no UTF-8 as TEXT: cast(x'..' as text). Each
;; is read from a table's row, on a step of its own.

;; bad-text : String -> Any
;; The TEXT cast from HEX, stored in a table and read back: column-value's
;; raise, the type SQL gives, column-bytevector's bytes, and the state.
(define (bad-text hex)
  (with-memory-db
   (lambda (db)
     (exec! db "create table v (x)")
     (exec! db (string-append "insert into v values (cast(x'" hex "' as text))"))
     (let* ((st (prepare-statement db "select typeof(x), x from v"))
            (s (step! st))
            (type (column-value st 0))
            (v (attempt (lambda () (column-value st 1))))
            (b (column-bytevector st 1))
            (state (statement-state st)))
       (finalize-statement! st)
       (list type v b state)))))

(define (bad-row offset bytes)
  (list "text" (list 'raised (invalid 'column-value 1 offset)) bytes 'row))

(test-equal "TEXT that is not well-formed UTF-8, from a real table, raises &sqlite-invalid-text from column-value, naming column 1 and the offset of its first ill-formed part; column-bytevector reads the same bytes, and the state stays row: FF, 61 FF, 61 C3 A9 FF 62, the overlong E0 80 80 and C0 AF, C2 41, a final 61 E1 80, the surrogate ED A0 80, F4 90 80 80 past U+10FFFF"
  (list (bad-row 0 #vu8(#xFF))
        (bad-row 1 #vu8(#x61 #xFF))
        (bad-row 3 #vu8(#x61 #xC3 #xA9 #xFF #x62))
        (bad-row 0 #vu8(#xE0 #x80 #x80))
        (bad-row 0 #vu8(#xC0 #xAF))
        (bad-row 0 #vu8(#xC2 #x41))
        (bad-row 1 #vu8(#x61 #xE1 #x80))
        (bad-row 0 #vu8(#xED #xA0 #x80))
        (bad-row 0 #vu8(#xF4 #x90 #x80 #x80)))
  (let* ((a (bad-text "FF"))
         (b (bad-text "61FF"))
         (c (bad-text "61C3A9FF62"))
         (d (bad-text "E08080"))
         (e (bad-text "C0AF"))
         (f (bad-text "C241"))
         (g (bad-text "61E180"))
         (h (bad-text "EDA080"))
         (i (bad-text "F4908080")))
    (list a b c d e f g h i)))

(test-equal "well-formed TEXT from a real table decodes whole: a leading U+FEFF kept, U+0000 kept, and the four lengths of sequence"
  (list (list "text" "\xFEFF;id" #vu8(#xEF #xBB #xBF #x69 #x64) 'row)
        (list "text" "a\x0;b" #vu8(#x61 0 #x62) 'row)
        (list "text" "a\xE9;\x20AC;\x1F600;" (string->utf8 "a\xE9;\x20AC;\x1F600;") 'row))
  (let* ((a (bad-text "EFBBBF6964"))
         (b (bad-text "610062"))
         (c (bad-text (hex-of (string->utf8 "a\xE9;\x20AC;\x1F600;")))))
    (list a b c)))

(test-equal "column-name raises &sqlite-invalid-text for a name made from raw bytes, naming the column and the offset: FF at 0, 61 FF 62 at 1, through valid SQL, select * from u; a third column, ok, reads; the state is left, ready then row"
  (list 0 (list (list 'raised (invalid 'column-name 0 0)) (list 'raised (invalid 'column-name 1 1)) "ok" 'ready)
        (list (list 'raised (invalid 'column-name 0 0)) (list 'raised (invalid 'column-name 1 1)) "ok" 'row))
  (with-memory-db
   (lambda (db)
     (let* ((made (exec-bytes! db (u8-list->bytevector
                                   (append (bytevector->u8-list (string->utf8 "create table u (\""))
                                           '(#xFF)
                                           (bytevector->u8-list (string->utf8 "\", \"a"))
                                           '(#xFF)
                                           (bytevector->u8-list (string->utf8 "b\", ok); insert into u values (1, 2, 3)"))))))
            (st (prepare-statement db "select * from u"))
            (names (lambda ()
                     (let* ((a (attempt (lambda () (column-name st 0))))
                            (b (attempt (lambda () (column-name st 1))))
                            (c (attempt (lambda () (column-name st 2))))
                            (state (statement-state st)))
                       (list a b c state))))
            (before (names))
            (s (step! st))
            (after (names)))
       (finalize-statement! st)
       (list made before after)))))

(test-equal "column-name decodes names strictly and whole: an alias of e-acute and a CJK character, one quoted with a leading U+FEFF, which is kept, and an expression's text as written"
  (list "\xE9;\x540D;" "\xFEFF;id" "1 + 1")
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select 1 as \"\xE9;\x540D;\", 2 as \"\xFEFF;id\", 1 + 1"))
            (a (column-name st 0))
            (b (column-name st 1))
            (c (column-name st 2)))
       (finalize-statement! st)
       (list a b c)))))

;; --- every raise after its section ----------------------------------------------------------
;; A with-exception-handler handler of a raise made inside a critical section
;; runs with interrupts disabled, at depth 2; after it, at depth 1. Each row's
;; handler reads its depth, and what was raised. The no-raise sentinel,
;; (no-raise VALUE), is no depth.

(test-equal "bind! raises after its section: the state, the index, a name holding U+0000, a name no parameter has, a value, SQLite's toobig, a finalized statement, and the wrong thread each reach a handler at depth 1; a bind that succeeds reaches none"
  (list (at-depth-1 (not-allowed 'bind! 'row))
        (at-depth-1 (refused 'bind! 'parameter-out-of-range 0 1))
        (at-depth-1 (refused 'bind! 'parameter-name-holds-nul '(kind string)))
        (at-depth-1 (refused 'bind! 'no-such-parameter '(kind string)))
        (at-depth-1 (refused 'bind! 'boolean 1 '(kind boolean)))
        (at-depth-1 (sqlite-failure 'bind! 'toobig 'toobig "select ?1"))
        (at-depth-1 (closed 'bind!))
        (at-depth-1 (list 'wrong-thread 'bind! 'message 'main 'the-thread))
        (list 'no-raise 'no-value))
  (with-memory-db
   (lambda (db)
     (let* ((row (prepare-statement db "select ?1"))
            (s (step! row))
            (a (handler-depth (lambda () (bind! row 1 1))))
            (st (prepare-statement db "select ?1"))
            (b (handler-depth (lambda () (bind! st 0 1))))
            (c (handler-depth (lambda () (bind! st ":a\x0;" 1))))
            (d (handler-depth (lambda () (bind! st ":a" 1))))
            (e (handler-depth (lambda () (bind! st 1 #t))))
            (old (with-handle db (lambda (h) (limit h limit-length 30))))
            (f (handler-depth (lambda () (bind! st 1 (text-of 31)))))
            (gone (prepare-statement db "select ?1"))
            (g (begin (finalize-statement! gone) (handler-depth (lambda () (bind! gone 1 1)))))
            (h (from-another-thread (lambda () (handler-depth (lambda () (bind! st 1 1))))))
            (i (handler-depth (lambda () (bind! st 1 1)))))
       (finalize-statement! row)
       (finalize-statement! st)
       (list a b c d e f g h i)))))

(test-equal "bind-all! raises after its section: the count, a value, and SQLite's toobig midway each reach a handler at depth 1"
  (list (at-depth-1 (refused 'bind-all! 'value-count-mismatch 1 2))
        (at-depth-1 (refused 'bind-all! 'boolean 2 '(kind boolean)))
        (at-depth-1 (sqlite-failure 'bind-all! 'toobig 'toobig "select ?1, ?2"))
        (list 'no-raise 'no-value))
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select ?1, ?2"))
            (a (handler-depth (lambda () (bind-all! st 1))))
            (b (handler-depth (lambda () (bind-all! st 1 #t))))
            (old (with-handle db (lambda (h) (limit h limit-length 30))))
            (c (handler-depth (lambda () (bind-all! st 1 (text-of 31)))))
            (d (handler-depth (lambda () (bind-all! st 1 2)))))
       (finalize-statement! st)
       (list a b c d)))))

(test-equal "clear-bindings! raises after its section: the state and a finalized statement each reach a handler at depth 1"
  (list (at-depth-1 (not-allowed 'clear-bindings! 'row))
        (at-depth-1 (closed 'clear-bindings!))
        (list 'no-raise 'no-value))
  (with-memory-db
   (lambda (db)
     (let* ((row (prepare-statement db "select 1"))
            (s (step! row))
            (a (handler-depth (lambda () (clear-bindings! row))))
            (gone (prepare-statement db "select 1"))
            (b (begin (finalize-statement! gone) (handler-depth (lambda () (clear-bindings! gone)))))
            (st (prepare-statement db "select ?1"))
            (c (handler-depth (lambda () (clear-bindings! st)))))
       (finalize-statement! row)
       (finalize-statement! st)
       (list a b c)))))

(test-equal "column-value, column-bytevector and column-name raise after their sections: the state, the index, invalid TEXT, a value column-bytevector refuses, an invalid name and a finalized statement each reach a handler at depth 1"
  (list (at-depth-1 (not-allowed 'column-value 'ready))
        (at-depth-1 (refused 'column-value 'column-out-of-range 3 3))
        (at-depth-1 (invalid 'column-value 0 0))
        (list 'no-raise 7)
        (at-depth-1 (refused 'column-bytevector 'not-text-or-blob 1 'integer))
        (at-depth-1 (refused 'column-bytevector 'not-a-column-index 'x))
        (list 'no-raise #vu8(#xFF))
        (at-depth-1 (refused 'column-name 'column-out-of-range 9 3))
        (at-depth-1 (invalid 'column-name 0 0))
        (at-depth-1 (closed 'column-name))
        (list 'no-raise "x"))
  (with-memory-db
   (lambda (db)
     (let* ((made (exec-bytes! db (u8-list->bytevector
                                   (append (bytevector->u8-list (string->utf8 "create table n (\""))
                                           '(#xFF)
                                           (bytevector->u8-list (string->utf8 "\")"))))))
            (st (prepare-statement db "select cast(x'ff' as text), 7, 'x' as x"))
            (a (handler-depth (lambda () (column-value st 0))))
            (s (step! st))
            (b (handler-depth (lambda () (column-value st 3))))
            (c (handler-depth (lambda () (column-value st 0))))
            (d (handler-depth (lambda () (column-value st 1))))
            (e (handler-depth (lambda () (column-bytevector st 1))))
            (f (handler-depth (lambda () (column-bytevector st 'x))))
            (g (handler-depth (lambda () (column-bytevector st 0))))
            (h (handler-depth (lambda () (column-name st 9))))
            (named (prepare-statement db "select * from n"))
            (i (handler-depth (lambda () (column-name named 0))))
            (gone (prepare-statement db "select 1"))
            (j (begin (finalize-statement! gone) (handler-depth (lambda () (column-name gone 0)))))
            (k (handler-depth (lambda () (column-name st 2)))))
       (finalize-statement! st)
       (finalize-statement! named)
       (list a b c d e f g h i j k)))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "statement-values")

(exit (suite-exit-status runner))
