#!r6rs
;;; The suite for execute-script! (ADR-0016), in (chez-sqlite3 private
;;; conveniences): a script run as a loop of prepares, each from the tail of
;;; the one before, over one block holding the whole script. Each case is
;;; measured, run on a fresh file, alike on 3.53.1 and 3.45.1. Its raises'
;;; who and depth are tests/test-conveniences-who.sps's, its re-entry rows
;;; tests/test-conveniences-reentry.sps's, and its engine rows
;;; tests/test-conveniences-engines.sps's.
;;;
;;;   the loop      every statement in turn, its rows dropped, each prepared
;;;                 only once the one before it has run; PRAGMAs in order; a
;;;                 statement with no semicolon at its end
;;;   no statement  empty SQL, only semicolons, only comments or whitespace:
;;;                 no error; a NULL statement ends the loop, and leading
;;;                 semicolons and comments belong to the next statement
;;;   the first error
;;;                 stops the loop, the statements before it standing; no
;;;                 transaction begun, ended or rolled back by the runner: one
;;;                 the script began is left open, one its error ended is
;;;                 ended
;;;   the error     rebuilt: the whole script as its sql, its offset in
;;;                 characters at the token SQLite points at for a prepare's
;;;                 error, at the failing statement's first token for a
;;;                 prepare's error with no offset and for a step's error;
;;;                 its class from the primary code, a busy step still
;;;                 &sqlite-busy, its message the field
;;;   the checks    a database first, then the SQL: U+0000 refused before
;;;                 any block is allocated, a timer's handler counting none
;;;                 at any tick of the call, so nothing runs; a closed
;;;                 connection refused even for an empty script
;;;   no cache      a script's statements are never cached, nor is a cached
;;;                 statement of the same SQL touched; they are prepared with
;;;                 no flags, read through lookaside
;;;   code-number   a step's failure's extended code back to its number, for
;;;                 the rebuilt error: an integer itself, a name its number,
;;;                 anything else #f
;;;
;;; The loading procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them. What a row reads back it reads
;;; through the statement tier.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure foreign-alloc foreign-free foreign-ref foreign-set! set-timer
              timer-interrupt-handler)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3 private conditions) sqlite-busy? sqlite-constraint?)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-error-message sqlite-error-sql sqlite-error-offset
              sqlite-closed?))

(define runner (test-runner-simple))
(test-runner-current runner)

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

(define public-load
  (guard (e (#t (list 'raised (describe e))))
    (eval '(sqlite-version) (environment '(chez-sqlite3)))
    'loaded))

;; reach : (Listof Symbol) Symbol -> Procedure
(define (reach library name)
  (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
    (eval name (environment library))))

(define conveniences '(chez-sqlite3 private conveniences))
(define connection-library '(chez-sqlite3 private connection))
(define statement-library '(chez-sqlite3 private statement))
(define execute-script! (reach conveniences 'execute-script!))
(define query (reach conveniences 'query))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define database-cache-count (reach connection-library 'database-cache-count))
(define tracked-statements (reach connection-library 'tracked-statements))
(define in-transaction? (reach connection-library 'in-transaction?))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define step! (reach statement-library 'step!))
(define column-count (reach statement-library 'column-count))
(define statement-sql (reach statement-library 'statement-sql))
(define statement-state (reach statement-library 'statement-state))
(define column-value (reach '(chez-sqlite3 private statement-values) 'column-value))
(define call-with-open-handle (reach connection-library 'call-with-open-handle))

;; --- bindings made here, after the load ------------------------------------------------

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_db_status(sqlite3*, int op, int *pCur, int *pHiwtr, int resetFlg)
(define db-status (bound 'sqlite3_db_status (foreign-procedure "sqlite3_db_status" (uptr int uptr uptr int) int)))

;; SQLITE_DBSTATUS_LOOKASIDE_USED, sqlite3.h's 0.
(define lookaside-used-op 0)

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; class-of : Condition -> Symbol
;; The class of an &sqlite-error this suite looks for.
(define (class-of e)
  (cond ((sqlite-busy? e) 'busy-class)
        ((sqlite-constraint? e) 'constraint-class)
        (else 'no-subclass)))

;; what-raised : Any -> Any
;; An &sqlite-error by its who, class, code, extended code, SQL and offset,
;; and whether its &message is its message field, never the text.
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (class-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (sqlite-error-sql e) (sqlite-error-offset e)
               (if (and (message-condition? e) (string? (sqlite-error-message e))
                        (equal? (condition-message e) (sqlite-error-message e)))
                   'message-is-the-field
                   'message-differs)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

;; failed : Symbol Symbol Symbol String (U Natural #f) -> List
(define (failed class code extended sql offset)
  (list 'raised (list 'sqlite-error 'execute-script! class code extended sql offset 'message-is-the-field)))

(define (refused who . irritants) (list 'assertion-violation who irritants))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define void-value (if #f #f))
(define (no-value x) (if (eq? x void-value) 'no-value x))

(define (statement-count) (cdr (assq 'statement (native-counts))))

;; undo! : (Listof Any) (Listof Any) -> Void
(define (undo! statements databases)
  (for-each (lambda (s) (guard (e (#t #f)) (finalize-statement! s))) statements)
  (for-each (lambda (db) (guard (e (#t #f)) (close-database! db))) databases))

;; tier-run : Database String -> (Listof (Vectorof Any))
;; SQL run through the statement tier: prepared, stepped to its end, each
;; row read whole, finalized; its rows.
(define (tier-run db sql)
  (let ((st (prepare-statement db sql)))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let loop ((rows '()))
          (if (step! st)
              (let* ((n (column-count st))
                     (row (make-vector n)))
                (let fill ((i 0))
                  (when (< i n)
                    (vector-set! row i (column-value st i))
                    (fill (+ i 1))))
                (loop (cons row rows)))
              (reverse rows))))
      (lambda () (finalize-statement! st)))))

;; xs : Database -> (Listof Any)
;; The x of every row of s, in order.
(define (xs db)
  (let loop ((rows (tier-run db "select x from s order by x")) (found '()))
    (if (null? rows) (reverse found) (loop (cdr rows) (cons (vector-ref (car rows) 0) found)))))

;; in-dir : (String -> Any) -> Any
(define (in-dir proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory proc)))

;; with-script-db : (List String) (String Database -> Any) -> Any
;; PROC's answer, or what it raised, given a fresh file s.db made with SETUP,
;; each run through the statement tier, and a connection to it, closed
;; after, however PROC ends.
(define (with-script-db setup proc)
  (in-dir
   (lambda (dir)
     (let ((path (string-append dir "/s.db")) (db #f))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (attempt
            (lambda ()
              (set! db (open-database path))
              (for-each (lambda (sql) (tier-run db sql)) setup)
              (proc path db))))
         (lambda () (when db (undo! '() (list db)))))))))

(define s-table '("create table s (x unique)"))

(test-begin "execute-script")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

;; --- the loop ------------------------------------------------------------------------------

(test-equal "a script runs each statement in turn and answers no value, its rows dropped: each is prepared only once the one before it has run, so an insert into the table its script made prepares; nothing is left counted or cached"
  (list 'no-value '(#(1) #(2)) 0 0 '())
  (with-script-db '()
    (lambda (path db)
      (let* ((a (no-value (execute-script! db "create table q (x); insert into q values (1); select x from q; insert into q select x + 1 from q")))
             (rows (tier-run db "select x from q order by x")))
        (list a rows (statement-count) (database-cache-count db) (tracked-statements db))))))

(test-equal "X7, X13 and X14: statements that answer rows among writes run, their rows dropped; a last statement with no semicolon runs; PRAGMAs run in order; statements with nothing between them each run from the tail of the one before"
  (list 'no-value '(60 61) 'no-value '(60 61 90) 'no-value '(9 60 61 90) 'no-value '(1 2 9 60 61 90))
  (with-script-db s-table
    (lambda (path db)
      (let* ((a (no-value (execute-script! db "SELECT 1; INSERT INTO s VALUES (60); SELECT x FROM s; INSERT INTO s VALUES (61); SELECT count(*) FROM s;")))
             (after-a (xs db))
             (b (no-value (execute-script! db "INSERT INTO s VALUES (90)")))
             (after-b (xs db))
             (c (no-value (execute-script! db "PRAGMA foreign_keys = ON; PRAGMA user_version = 9; INSERT INTO s SELECT user_version FROM pragma_user_version;")))
             (after-c (xs db))
             (d (no-value (execute-script! db "insert into s values (1);insert into s values (2)"))))
        (list a after-a b after-b c after-c d (xs db))))))

;; --- no statement ------------------------------------------------------------------------

(test-equal "X9 to X12: SQL holding no statement is no error: empty, only semicolons, only a comment, only whitespace, a block comment, and a trailing comment after a statement"
  (list '(no-value no-value no-value no-value no-value no-value) '(80))
  (with-script-db s-table
    (lambda (path db)
      (let* ((a (no-value (execute-script! db "")))
             (b (no-value (execute-script! db ";;;")))
             (c (no-value (execute-script! db "-- nothing")))
             (d (no-value (execute-script! db "  \n\t ")))
             (e (no-value (execute-script! db "/* c */")))
             (f (no-value (execute-script! db "INSERT INTO s VALUES (80);  -- done\n  "))))
        (list (list a b c d e f) (xs db))))))

;; Measured on both libraries: a NULL statement's tail is the input's end, and
;; leading semicolons and comments go into the next statement.
(test-equal "a NULL statement ends the loop, and the semicolons and comments before a statement belong to it, so none is skipped: ; after a statement, ;; before one, a comment then ; before one, and U+FEFF then ; before one"
  (list '(no-value no-value no-value no-value) '(1 2 3 4))
  (with-script-db s-table
    (lambda (path db)
      (let* ((a (no-value (execute-script! db "insert into s values (1); ;")))
             (b (no-value (execute-script! db ";; insert into s values (2)")))
             (c (no-value (execute-script! db "-- c\n; insert into s values (3)")))
             (d (no-value (execute-script! db "\xFEFF;; insert into s values (4)"))))
        (list (list a b c d) (xs db))))))

;; --- the first error -----------------------------------------------------------------------

(define x1 "CREATE TABLE s(x UNIQUE); INSERT INTO s VALUES (1); INSERT INTO s VALUES (2); INSERT INTO s VALUES (1); INSERT INTO s VALUES (3);")
(define x2 "BEGIN; INSERT INTO s VALUES (10); INSERT INTO s VALUES (10); INSERT INTO s VALUES (11); COMMIT;")
(define x4 "BEGIN; INSERT INTO s VALUES (30); INSERT OR ROLLBACK INTO s VALUES (30); INSERT INTO s VALUES (31); COMMIT;")
(define x16 "BEGIN; INSERT INTO s VALUES (110); INSERT INTO c VALUES (7); COMMIT; INSERT INTO s VALUES (111);")

(test-equal "X1: a constraint failure midway in autocommit stops the script, the statements before it standing; its error carries the whole script and the failing statement's first token, at character 78, and is a constraint by class; no transaction is left"
  (list (failed 'constraint-class 'constraint 'constraint-unique x1 78) '(1 2) #f)
  (with-script-db '()
    (lambda (path db)
      (let* ((a (attempt (lambda () (execute-script! db x1)))))
        (list a (xs db) (in-transaction? db))))))

(test-equal "X2 and X4: a failure inside the script's own BEGIN stops it, the transaction left open with the statement before it, never rolled back by the runner; an INSERT OR ROLLBACK's failure ends the transaction itself"
  (list (failed 'constraint-class 'constraint 'constraint-unique x2 34) #t '(10) '()
        (failed 'constraint-class 'constraint 'constraint-unique x4 34) #f '())
  (with-script-db s-table
    (lambda (path db)
      (let* ((a (attempt (lambda () (execute-script! db x2))))
             (open (in-transaction? db))
             (inside (xs db))
             (r (execute-script! db "rollback"))
             (after (xs db))
             (b (attempt (lambda () (execute-script! db x4))))
             (ended (in-transaction? db)))
        (list a open inside after b ended (xs db))))))

(test-equal "X16: a COMMIT that fails on a deferred foreign key stops the script at the COMMIT's first token, character 61, the transaction left open"
  (list (failed 'constraint-class 'constraint 'constraint-foreignkey x16 61) #t '(110) '())
  (with-script-db '("create table s (x unique)" "create table p (id integer primary key)"
                    "create table c (pid references p(id) deferrable initially deferred)"
                    "pragma foreign_keys = on")
    (lambda (path db)
      (let* ((a (attempt (lambda () (execute-script! db x16))))
             (open (in-transaction? db))
             (inside (xs db))
             (r (execute-script! db "rollback")))
        (list a open inside (xs db))))))

;; --- the error's offset ----------------------------------------------------------------------

(define x5 "INSERT INTO s VALUES (40); SELEKT 1; INSERT INTO s VALUES (41);")
(define x6 "INSERT INTO s VALUES (50);\nINSERT INTO nosuch VALUES (1);\nINSERT INTO s VALUES (51);")
(define x8 "INSERT INTO s VALUES (70); INSERT INTO s VALUES (")
(define x15 "INSERT INTO s VALUES (100); SELECT abs(-9223372036854775807 - 1); INSERT INTO s VALUES (101);")

(test-equal "X5, X6 and X8: a prepare's error points at the token SQLite names, character 27 for SELEKT, and 36 for a column no table has, past the statement's first token; one SQLite gives no offset, no such table and incomplete input, at the failing statement's first token, 27 each; the statements before stand"
  (list (failed 'no-subclass 'error 'error x5 27) '(40)
        (failed 'no-subclass 'error 'error x6 27) '(40 50)
        (failed 'no-subclass 'error 'error x8 27) '(40 50 70)
        (failed 'no-subclass 'error 'error "insert into s values (2); select 1, nosuchcol" 36) '(2 40 50 70))
  (with-script-db s-table
    (lambda (path db)
      (let* ((a (attempt (lambda () (execute-script! db x5))))
             (after-a (xs db))
             (b (attempt (lambda () (execute-script! db x6))))
             (after-b (xs db))
             (c (attempt (lambda () (execute-script! db x8))))
             (after-c (xs db))
             (d (attempt (lambda () (execute-script! db "insert into s values (2); select 1, nosuchcol")))))
        (list a after-a b after-b c after-c d (xs db))))))

(test-equal "X15: a step's error, which SQLite gives no offset, points at the failing statement's first token, character 28; past a comment and a semicolon before it, character 34"
  (list (failed 'no-subclass 'error 'error x15 28) '(100)
        (failed 'no-subclass 'error 'error "insert into s values (1); -- c\n ; select abs(-9223372036854775807 - 1)" 34)
        '(1 100))
  (with-script-db s-table
    (lambda (path db)
      (let* ((a (attempt (lambda () (execute-script! db x15))))
             (after-a (xs db))
             (b (attempt (lambda () (execute-script! db "insert into s values (1); -- c\n ; select abs(-9223372036854775807 - 1)")))))
        (list a after-a b (xs db))))))

(test-equal "the offset counts characters of the script, not bytes: after two two-byte characters, a prepare's error at character 29 and a step's at 29"
  (list (failed 'no-subclass 'error 'error "insert into s values ('λλ'); selekt 1" 29)
        (failed 'constraint-class 'constraint 'constraint-unique "insert into s values ('μμ'); insert into s values ('μμ')" 29))
  (with-script-db s-table
    (lambda (path db)
      (let* ((a (attempt (lambda () (execute-script! db "insert into s values ('λλ'); selekt 1"))))
             (b (attempt (lambda () (execute-script! db "insert into s values ('μμ'); insert into s values ('μμ')")))))
        (list a b)))))

(test-equal "a step that answers busy, under another connection's write lock, is rebuilt as &sqlite-busy still, its offset at the statement's first token; nothing it wrote stands"
  (list (failed 'busy-class 'busy 'busy " insert into s values (1)" 1) '())
  (with-script-db s-table
    (lambda (path db)
      (let ((other (open-database path)))
        (dynamic-wind
          (lambda () #f)
          (lambda ()
            (tier-run other "begin immediate")
            (let ((a (attempt (lambda () (execute-script! db " insert into s values (1)")))))
              (tier-run other "rollback")
              (list a (xs db))))
          (lambda () (undo! '() (list other))))))))

;; --- the checks ----------------------------------------------------------------------------

;; most-blocks : (-> Any) -> (List Any Natural Natural)
;; THUNK's answer, a timer's handler run at every tick of it counting the
;; foreign blocks held: the most it counted, and at how many ticks. The
;; count after THUNK cannot tell a block allocated and freed on the way out
;; from none: a script that allocates before its checks, and frees the
;; block as the refusal leaves, passes a row that reads it then.
(define (most-blocks thunk)
  (let ((most 0) (ticks 0) (old (timer-interrupt-handler)))
    (let ((answer
           (dynamic-wind
             (lambda ()
               (timer-interrupt-handler
                (lambda ()
                  (set! ticks (+ ticks 1))
                  (set! most (max most (cdr (assq 'block (native-counts)))))
                  (set-timer 1))))
             (lambda () (set-timer 1) (let ((r (thunk))) (set-timer 0) r))
             (lambda () (set-timer 0) (timer-interrupt-handler old)))))
      (list answer most ticks))))

(test-equal "a script holding U+0000 is refused before any block is allocated: a timer's handler, run at every tick of the call, at least 20 ticks, counts none; so nothing in it runs; no database is refused before the SQL is read; a closed connection is refused even for an empty script"
  (list (list 'raised (refused 'execute-script! 'sql-holds-nul '(kind string))) 0 'at-least-20-ticks '()
        (list 'raised (refused 'execute-script! 'not-a-database 'x))
        (list 'raised (list 'closed 'execute-script!)))
  (let* ((r (with-script-db s-table
              (lambda (path db)
                (let* ((m (most-blocks (lambda () (attempt (lambda () (execute-script! db "insert into s values (1);\x0;")))))))
                  (list (car m) (cadr m) (if (>= (caddr m) 20) 'at-least-20-ticks (list 'ticks (caddr m)))
                        (xs db))))))
         (b (attempt (lambda () (execute-script! 'x 42))))
         (c (let ((db (open-database ":memory:")))
              (close-database! db)
              (attempt (lambda () (execute-script! db ""))))))
    (append r (list b c))))

;; --- no cache --------------------------------------------------------------------------------

(test-equal "execute-script! uses no cache: its statements are never cached, and the statement query cached for the same SQL stays the very one, ready"
  (list 1 '(("select x from s" . ready)) 'the-very-statement 1)
  (with-script-db '("create table s (x unique)" "insert into s values (5)")
    (lambda (path db)
      (let* ((q (query db "select x from s"))
             (held (car (tracked-statements db)))
             (a (execute-script! db "select x from s; select x from s"))
             (listed (let loop ((rest (tracked-statements db)) (found '()))
                       (if (null? rest)
                           (reverse found)
                           (loop (cdr rest) (cons (cons (statement-sql (car rest)) (statement-state (car rest))) found))))))
        (list (database-cache-count db) listed
              (if (eq? held (car (tracked-statements db))) 'the-very-statement 'another)
              (statement-count))))))

(define two-hundred-columns
  (let loop ((i 200) (parts '()))
    (if (= i 0)
        (fold-left (lambda (acc part) (if (string=? acc "") part (string-append acc ", " part))) "" parts)
        (loop (- i 1) (cons (number->string i) parts)))))

;; lookaside-high : Database (Database -> Any) -> Integer
;; SQLITE_DBSTATUS_LOOKASIDE_USED's high-water mark across THUNK's run on DB,
;; through the suite's own sqlite3_db_status, reset before it.
(define (lookaside-high db thunk)
  (let ((read (lambda (reset)
                (call-with-open-handle 'test-execute-script db
                  (lambda (h)
                    (let ((cur (foreign-alloc 8)) (hi (foreign-alloc 8)))
                      (foreign-set! 'int cur 0 0)
                      (foreign-set! 'int hi 0 0)
                      (let* ((rc (db-status h lookaside-used-op cur hi reset))
                             (n (foreign-ref 'int hi 0)))
                        (foreign-free cur)
                        (foreign-free hi)
                        (if (eqv? rc 0) n (list 'db-status-failed rc)))))))))
    (read 1)
    (thunk db)
    (read 0)))

;; Measured on both libraries: a select of 200 columns prepared with no flags
;; fills the connection's lookaside, 123 slots at its high-water mark, and
;; prepared SQLITE_PREPARE_PERSISTENT takes none, stepped and read or not.
(test-equal "execute-script! prepares with no flags: a script of one select of 200 columns takes lookaside, as query does at a capacity of 0, set by the statement-cache setting, where query's miss, prepared SQLITE_PREPARE_PERSISTENT above 0, takes none"
  (list 'some 'some 0)
  (let* ((sql (string-append "select " two-hundred-columns))
         (high (lambda (open run)
                 (let ((db (open)))
                   (dynamic-wind
                     (lambda () #f)
                     (lambda () (guard (e (#t (list 'raised (what-raised e)))) (lookaside-high db run)))
                     (lambda () (undo! '() (list db)))))))
         (script (high (lambda () (open-database ":memory:")) (lambda (db) (execute-script! db sql))))
         (at-0 (high (lambda () (open-database ":memory:" '((statement-cache . 0)))) (lambda (db) (query db sql))))
         (cached (high (lambda () (open-database ":memory:")) (lambda (db) (query db sql))))
         (some (lambda (n) (if (and (integer? n) (> n 0)) 'some n))))
    (list (some script) (some at-0) cached)))

;; --- code-number: a step's failure's code, back to its number -------------------------------
;; The step's &sqlite-error names its extended code; the script rebuilds the
;; error from the number. A code newer than the constants' table is named by
;; the integer itself, which no SQLite these suites run answers, so the row
;; holds every branch on synthetic inputs.

(define code-number (reach conveniences 'code-number))

(test-equal "code-number answers an exact integer, as an error names a code the constants' table lacks, itself; every name in the table, its number; anything else #f: a name the table lacks, a string naming a code, an inexact integer, #f and a list"
  (list 123456789 5 2067 'every-name-its-number '(#f #f #f #f #f))
  (guard (e (#t (list 'raised (what-raised e))))
    (let ((table (eval 'sqlite-result-codes (environment '(chez-sqlite3 private constants)))))
      (list (code-number 123456789)
            (code-number 5)
            (code-number 'constraint-unique)
            (if (for-all (lambda (row) (eqv? (code-number (car row)) (cdr row))) table)
                'every-name-its-number
                (list 'names-otherwise
                      (filter (lambda (row) (not (eqv? (code-number (car row)) (cdr row)))) table)))
            (let* ((a (code-number 'no-such-code))
                   (b (code-number "busy"))
                   (c (code-number 5.0))
                   (d (code-number #f))
                   (e (code-number '(busy))))
              (list a b c d e))))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "execute-script")

(exit (suite-exit-status runner))
