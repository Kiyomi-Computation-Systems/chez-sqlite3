#!r6rs
;;; The suite for execute!, query, query-row and query-fold (ADR-0016; the M3
;;; plan, section 4.1), in (chez-sqlite3 private conveniences), and the
;;; statement cache through them (ADR-0020; the plan, section 4.6). The
;;; raises' who and depth are tests/test-conveniences-who.sps's, the re-entry
;;; rows tests/test-conveniences-reentry.sps's, the engines
;;; tests/test-conveniences-engines.sps's, the counters through them
;;; tests/test-conveniences-counters.sps's, and execute-script!
;;; tests/test-execute-script.sps's.
;;;
;;;   the shapes    execute! binds its parameters by position and answers no
;;;                 value, stepping to done and dropping any rows; query
;;;                 answers every row in order, each a vector in column order;
;;;                 query-row the first or #f, the rest never stepped to;
;;;                 query-fold calls (proc acc row) in order, from its seed
;;;   the rows      a row's columns are read at the row, after its step: a
;;;                 cached select * answers the column an alter table added
;;;   the binds     every value checked before any is bound
;;;   the cache     the statement count after each convenience at the
;;;                 default, at 0 and at 1, set privately; the very statement
;;;                 reused; a PRAGMA cached as any other (slice 0's P1);
;;;                 foreign_keys = 1 re-preparing the rest (slice 0's P13),
;;;                 and trusted_schema = 0 and = 1 each (slice 0's P13b); a
;;;                 return into a full cache evicting the least recently used;
;;;                 a failed step never kept; a reset's failure on return
;;;                 raised, through query-row on a multi-row insert ...
;;;                 returning under another's read
;;;   every path    after a refused bind, a failed step and a failed read, no
;;;                 statement is left at a row: it is cached and ready, or
;;;                 finalized; query-fold's statement, left by a raise or an
;;;                 escape, is finalized, and by a normal return cached
;;;   at a row      by SQLite's own account: after each convenience returns or
;;;                 raises, an interrupt is lost and the next prepare runs,
;;;                 where a statement held at a row makes it answer 9 (the
;;;                 M3 plan's section 4.8; concurrency I3)
;;;
;;; The loading procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them. What a row reads back it reads
;;; through M2's statement tier, never through the convenience it tests.
;;; SQLite's answers here were measured on 3.53.1 and 3.45.1 alike
;;; (.plans/research/m3-slice-3/conveniences-answers.sps, and the research
;;; each row cites) before a row asserts them.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3 private values) sql-null sql-null?)
        (only (chez-sqlite3 private conditions) sqlite-invalid-text? sqlite-invalid-text-column
              sqlite-invalid-text-offset)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-error-sql sqlite-error-offset sqlite-closed?))

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

(define conveniences '(chez-sqlite3 private conveniences))
(define connection-library '(chez-sqlite3 private connection))
(define statement-library '(chez-sqlite3 private statement))
(define execute! (reach conveniences 'execute!))
(define query (reach conveniences 'query))
(define query-row (reach conveniences 'query-row))
(define query-fold (reach conveniences 'query-fold))
(define execute-script! (reach conveniences 'execute-script!))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define open-database-with-cache-capacity (reach connection-library 'open-database-with-cache-capacity))
(define database-cache-count (reach connection-library 'database-cache-count))
(define tracked-statements (reach connection-library 'tracked-statements))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define step! (reach statement-library 'step!))
(define column-count (reach statement-library 'column-count))
(define statement-sql (reach statement-library 'statement-sql))
(define statement-state (reach statement-library 'statement-state))
(define call-with-statement-handle (reach statement-library 'call-with-statement-handle))
(define column-value (reach '(chez-sqlite3 private statement-values) 'column-value))
(define call-with-open-handle (reach connection-library 'call-with-open-handle))
(define sqlite3-interrupt (reach '(chez-sqlite3 private native) 'sqlite3-interrupt))

;; --- bindings made here, after the load ------------------------------------------------

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_stmt_status(sqlite3_stmt*, int op, int resetFlg)
(define stmt-status (bound 'sqlite3_stmt_status (foreign-procedure "sqlite3_stmt_status" (uptr int int) int)))

;; SQLITE_STMTSTATUS_REPREPARE, sqlite3.h's 5.
(define stmtstatus-reprepare 5)

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (sqlite-error-sql e) (sqlite-error-offset e)))
        ((sqlite-invalid-text? e)
         (list 'invalid-text (who-of e) (sqlite-invalid-text-column e) (sqlite-invalid-text-offset e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        ((symbol? e) (list 'the-symbol e))
        (else (list 'other (describe e)))))

(define (refused who . irritants) (list 'assertion-violation who irritants))

;; attempt : (-> Any) -> Any
;; THUNK's answer, or (raised WHAT) for what it raised.
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define void-value (if #f #f))
(define (no-value x) (if (eq? x void-value) 'no-value x))

;; shown : Any -> Any
;; X with sql-null written null, inside vectors and lists too. Pure.
(define (shown x)
  (cond ((sql-null? x) 'null)
        ((vector? x) (list->vector (map shown (vector->list x))))
        ((pair? x) (cons (shown (car x)) (shown (cdr x))))
        (else x)))

(define (statement-count) (cdr (assq 'statement (native-counts))))

;; states : Database -> (Listof (Pairof String Symbol))
;; Every statement DB tracks, as its SQL and its state, ordered by SQL.
(define (states db)
  (list-sort (lambda (a b) (string<? (car a) (car b)))
             (let loop ((rest (tracked-statements db)) (found '()))
               (if (null? rest)
                   found
                   (loop (cdr rest)
                         (cons (cons (statement-sql (car rest)) (statement-state (car rest))) found))))))

;; cached-statement : Database String -> (U Statement #f)
;; The one statement of SQL DB tracks, when there is exactly one.
(define (cached-statement db sql)
  (let ((found (filter (lambda (st) (string=? (statement-sql st) sql)) (tracked-statements db))))
    (and (= (length found) 1) (car found))))

;; cache : Database -> (List Natural Natural)
;; The statements counted, and the cache's count of DB.
(define (cache db) (list (statement-count) (database-cache-count db)))

;; reprepare-count : Statement -> Integer
;; SQLITE_STMTSTATUS_REPREPARE of ST, through the suite's own
;; sqlite3_stmt_status, on its handle through the one accessor.
(define (reprepare-count st)
  (call-with-statement-handle 'test-conveniences st 'column-count
    (lambda (connection handle sql) (values #f (stmt-status handle stmtstatus-reprepare 0)))))

;; undo! : (Listof Any) (Listof Any) -> Void
(define (undo! statements databases)
  (for-each (lambda (s) (guard (e (#t #f)) (finalize-statement! s))) statements)
  (for-each (lambda (db) (guard (e (#t #f)) (close-database! db))) databases))

;; with-db : (-> Database) (Database -> Any) -> Any
;; PROC's answer, or what it raised, given the database OPEN makes, closed
;; after, however PROC ends.
(define (with-db open proc)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda () (attempt (lambda () (set! db (open)) (proc db))))
      (lambda () (when db (undo! '() (list db)))))))

(define (with-memory-db proc) (with-db (lambda () (open-database ":memory:")) proc))

(define (with-capacity capacity proc)
  (with-db (lambda () (open-database-with-cache-capacity capacity ":memory:")) proc))

;; in-dir : (String -> Any) -> Any
(define (in-dir proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory proc)))

;; tier-run : Database String -> (Listof (Vectorof Any))
;; SQL run through M2's statement tier: prepared, stepped to its end, each
;; row read whole, finalized; its rows, shown.
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
                (loop (cons (shown row) rows)))
              (reverse rows))))
      (lambda () (finalize-statement! st)))))

;; make-table! : String -> Any
;; The database at PATH, made with table t, x unique, holding the one row 0,
;; and table u, with no constraint.
(define (make-table! path)
  (let ((db (open-database path)))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (tier-run db "create table t (x unique)")
        (tier-run db "insert into t values (0)")
        (tier-run db "create table u (x)"))
      (lambda () (undo! '() (list db))))))

;; with-file-db : (String Database -> Any) -> Any
(define (with-file-db proc)
  (in-dir (lambda (dir)
            (let ((path (string-append dir "/t.db")) (db #f))
              (dynamic-wind
                (lambda () #f)
                (lambda ()
                  (attempt (lambda ()
                             (make-table! path)
                             (set! db (open-database path))
                             (proc path db))))
                (lambda () (when db (undo! '() (list db)))))))))

;; under-reader : String (-> Any) -> Any
;; THUNK's answer while a second connection to PATH holds a read, its
;; select stepped to a row; the read released after, however THUNK ends.
(define (under-reader path thunk)
  (let ((reader #f) (st #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (set! reader (open-database path))
        (set! st (prepare-statement reader "select x from t"))
        (step! st)
        (thunk))
      (lambda () (undo! (if st (list st) '()) (if reader (list reader) '()))))))

(define returning-sql "insert into t values (1), (2) returning x")

;; interrupt! : Database -> Void
;; sqlite3_interrupt on DB's handle, native's binding through the one
;; accessor, as the suites reach native.
(define (interrupt! db)
  (call-with-open-handle 'test-conveniences db (lambda (handle) (sqlite3-interrupt handle))))

;; after-interrupt : (Database -> Any) -> (List Any Any)
;; On a fresh :memory: database holding table n, its rows 1, 2 and 3: what
;; PROC answered, or raised; then, after sqlite3_interrupt on the
;; connection, what select 7 answers through the statement tier. While no
;; statement of the connection holds a row the interrupt is lost, and it
;; answers (#(7)); while one does, the interrupt sticks, and its prepare
;; answers SQLite's interrupt, 9 (M3's research, concurrency I2, I3).
(define (after-interrupt proc)
  (with-memory-db
   (lambda (db)
     (tier-run db "create table n (x)")
     (tier-run db "insert into n values (1), (2), (3)")
     (let* ((answer (attempt (lambda () (proc db))))
            (interrupted (interrupt! db))
            (next (attempt (lambda () (tier-run db "select 7")))))
       (list answer next)))))

(test-begin "conveniences")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

;; --- the shapes ---------------------------------------------------------------------------

(test-equal "execute! runs one statement with its values bound to its parameters by position, numbered and named ones by their index, and answers no value; each value reads back through the statement tier"
  (list '(no-value no-value no-value no-value no-value)
        '(#(1 "one") #(2 2.5) #(3 #vu8(1 2 3)) #(4 null)))
  (with-memory-db
   (lambda (db)
     (let* ((a (no-value (execute! db "create table t (k integer primary key, v)")))
            (b (no-value (execute! db "insert into t values (?, ?)" 1 "one")))
            (c (no-value (execute! db "insert into t values (?2, ?1)" 2.5 2)))
            (d (no-value (execute! db "insert into t values (:k, :v)" 3 (u8-list->bytevector (list 1 2 3)))))
            (e (no-value (execute! db "insert into t values (?, ?)" 4 sql-null))))
       (list (list a b c d e) (tier-run db "select k, v from t order by k"))))))

(test-equal "query answers every row, in order, each a vector of its values in column order, every storage class as ADR-0015 reads it; () when there is no row; its values bound by position"
  (list '(#(1 1) #(2 4) #(3 9) #(4 16) #(5 25))
        '(#(1 2.5 "λ" #vu8(1 2) null))
        '()
        '(#(5 "x")))
  (with-memory-db
   (lambda (db)
     (let* ((a (query db "with recursive n(i) as (select 1 union all select i + 1 from n where i < 5) select i, i * i from n"))
            (b (query db "select 1, 2.5, 'λ', x'0102', null"))
            (c (query db "select 1 where 0"))
            (d (query db "select ?1 + ?2, :s" 2 3 "x")))
       (shown (list a b c d))))))

(test-equal "query-row answers the first row of several and #f for none, and never steps to a second row: one whose step fails raises nothing, where query, stepping to it, raises its integer overflow"
  (list '#(1) #f '#(1) '#(5)
        (list 'raised (list 'sqlite-error 'query 'error 'error "select 1 union all select abs(-9223372036854775807 - 1)" #f)))
  (with-memory-db
   (lambda (db)
     (let* ((a (query-row db "with recursive n(i) as (select 1 union all select i + 1 from n where i < 5) select i from n"))
            (b (query-row db "select 1 where 0"))
            (c (query-row db "select 1 union all select abs(-9223372036854775807 - 1)"))
            (d (query-row db "select ?1 + ?2" 2 3))
            (e (attempt (lambda () (query db "select 1 union all select abs(-9223372036854775807 - 1)")))))
       (list a b c d e)))))

(test-equal "query-fold calls (proc acc row) on every row, in order, from its seed, as fold-left calls its procedure, answering the last; the seed itself for no row, the procedure never called; its values bound by position"
  (list '(4 3 2 1) 'the-seed '(a #(1 2)))
  (with-memory-db
   (lambda (db)
     (let* ((a (query-fold db "with recursive n(i) as (select 1 union all select i + 1 from n where i < ?1) select i from n"
                           (lambda (acc row) (cons (vector-ref row 0) acc)) '() 4))
            (b (query-fold db "select 1 where 0" (lambda (acc row) 'called) 'the-seed))
            (c (query-fold db "select 1, 2" (lambda (acc row) (list acc row)) 'a)))
       (list a b c)))))

(test-equal "execute! steps its statement to done and drops its rows: an insert ... returning of three rows inserts all three; a select answers no value, and one whose second row's step fails raises it; a PRAGMA's set, which answers a row, applies"
  (list 'no-value '(#(1) #(2) #(3)) 'no-value
        (list 'raised (list 'sqlite-error 'execute! 'error 'error "select 1 union all select abs(-9223372036854775807 - 1)" #f))
        'no-value '(#("truncate")))
  (in-dir
   (lambda (dir)
     (with-db (lambda () (open-database (string-append dir "/j.db")))
       (lambda (db)
         (let* ((m (execute! db "create table r (x)"))
                (a (no-value (execute! db "insert into r values (1), (2), (3) returning x")))
                (rows (tier-run db "select x from r order by x"))
                (b (no-value (execute! db "select x from r")))
                (d (attempt (lambda () (execute! db "select 1 union all select abs(-9223372036854775807 - 1)"))))
                (c (no-value (execute! db "pragma journal_mode = truncate"))))
           (list a rows b d c (tier-run db "pragma journal_mode"))))))))

;; Measured by M3's research (.plans/research/m3-plan/single/cache.c, K2.2),
;; on both libraries: a held select * reads its new column at the step that
;; re-prepares it.
(test-equal "a row's columns are read at the row, after its step: once alter table has added a column, the cached select * answers it, and is the very statement cached before"
  (list '(#(1)) '(#(1 9)) 'the-very-statement)
  (with-memory-db
   (lambda (db)
     (let* ((m (execute! db "create table w (a)"))
            (i (execute! db "insert into w values (1)"))
            (before (query db "select * from w"))
            (held (cached-statement db "select * from w"))
            (alter (execute! db "alter table w add column b default 9"))
            (after (query db "select * from w")))
       (list before after (if (and held (eq? held (cached-statement db "select * from w")))
                              'the-very-statement
                              'another))))))

(test-equal "every value is checked before any is bound: a refused value binds nothing and the statement goes back to the cache, ready, its next call binding afresh; a count other than the parameters' is refused"
  (list (list 'raised (refused 'execute! 'boolean 2 '(kind boolean)))
        '(#(0)) 'ready 'no-value '(#(1 2))
        (list 'raised (refused 'query 'value-count-mismatch 1 2)))
  (with-memory-db
   (lambda (db)
     (let* ((m (execute! db "create table t (a, b)"))
            (a (attempt (lambda () (execute! db "insert into t values (?, ?)" 1 #t))))
            (n (tier-run db "select count(*) from t"))
            (st (cached-statement db "insert into t values (?, ?)"))
            (state (and st (statement-state st)))
            (b (no-value (execute! db "insert into t values (?, ?)" 1 2)))
            (rows (tier-run db "select a, b from t"))
            (c (attempt (lambda () (query db "select ?1, ?2" 1)))))
       (list a n state b rows c)))))

;; --- the cache, through the conveniences -------------------------------------------------------

;; each-convenience! : Database -> (Listof (List Natural Natural))
;; execute! twice, query, query-row and query-fold on new SQL, then
;; execute-script!, then execute! and query again on SQL used already: the
;; statements counted and cached after each.
(define (each-convenience! db)
  (let* ((a (begin (execute! db "create table t (x)") (cache db)))
         (b (begin (execute! db "insert into t values (?)" 1) (cache db)))
         (c (begin (query db "select x from t") (cache db)))
         (d (begin (query-row db "select count(*) from t") (cache db)))
         (e (begin (query-fold db "select x + 1 from t" (lambda (acc row) acc) 0) (cache db)))
         (f (begin (execute-script! db "insert into t values (2); insert into t values (3)") (cache db)))
         (g (begin (execute! db "insert into t values (?)" 4) (cache db)))
         (h (begin (query db "select x from t") (cache db))))
    (list a b c d e f g h)))

(test-equal "at the default capacity each convenience on new SQL leaves one more statement, counted and cached, ready; execute-script! leaves none; the same SQL again reuses the very statement"
  (list '((1 1) (2 2) (3 3) (4 4) (5 5) (5 5) (5 5) (5 5))
        '(("create table t (x)" . ready) ("insert into t values (?)" . ready)
          ("select count(*) from t" . ready) ("select x + 1 from t" . ready) ("select x from t" . ready))
        'the-very-statements)
  (with-memory-db
   (lambda (db)
     (let* ((counts (each-convenience! db))
            (insert (cached-statement db "insert into t values (?)"))
            (select (cached-statement db "select x from t"))
            (again (begin (execute! db "insert into t values (?)" 5) (query db "select x from t")
                          (and insert select
                               (eq? insert (cached-statement db "insert into t values (?)"))
                               (eq? select (cached-statement db "select x from t"))))))
       (list counts (states db) (if again 'the-very-statements 'others))))))

(test-equal "at a capacity of 0, set privately, each convenience leaves no statement: every return finalizes"
  (list '((0 0) (0 0) (0 0) (0 0) (0 0) (0 0) (0 0) (0 0)) '() '(#(1) #(2) #(3) #(4)))
  (with-capacity 0
    (lambda (db)
      (let* ((counts (each-convenience! db)))
        (list counts (states db) (tier-run db "select x from t order by x"))))))

(test-equal "at a capacity of 1, set privately, each convenience leaves one statement, the last one's, and execute-script! leaves the one before it"
  (list '((1 1) (1 1) (1 1) (1 1) (1 1) (1 1) (1 1) (1 1)) '(("select x from t" . ready)))
  (with-capacity 1
    (lambda (db)
      (let* ((counts (each-convenience! db)))
        (list counts (states db))))))

;; Measured by M3 slice 0's research (P1), on both libraries: a PRAGMA's set,
;; reset and stepped again, applies again, SQLite re-preparing it at that
;; step.
(test-equal "a PRAGMA statement is cached as any other: user_version = 5, then 6, then the very cached 5 again applies 5, re-prepared once at its second step"
  (list '(#(6)) '(#(5)) 'the-very-statement 1)
  (with-memory-db
   (lambda (db)
     (let* ((a (execute! db "pragma user_version = 5"))
            (held (cached-statement db "pragma user_version = 5"))
            (b (execute! db "pragma user_version = 6"))
            (six (tier-run db "pragma user_version"))
            (c (execute! db "pragma user_version = 5"))
            (five (tier-run db "pragma user_version")))
       (list six five
             (if (and held (eq? held (cached-statement db "pragma user_version = 5"))) 'the-very-statement 'another)
             (and held (reprepare-count held)))))))

;; Measured by M3 slice 0's research (P13), on both libraries: any set of
;; foreign_keys expires every other statement; a set of cache_size none.
(test-equal "foreign_keys = 1, run by execute!, makes every other cached statement re-prepare once at its next use, answering rightly, where cache_size = 100 made none: each is the very statement cached before"
  (list '(0 0) '(0 0) '(1 1) '((#(1)) (#(1))) 'the-very-statements)
  (with-memory-db
   (lambda (db)
     (let* ((m (execute! db "create table t (x)"))
            (i (execute! db "insert into t values (1)"))
            (q1 (query db "select x from t"))
            (q2 (query-row db "select count(*) from t"))
            (a (cached-statement db "select x from t"))
            (b (cached-statement db "select count(*) from t"))
            (counts (lambda () (list (reprepare-count a) (reprepare-count b))))
            (fresh (counts))
            (cs (execute! db "pragma cache_size = 100"))
            (r1 (query db "select x from t"))
            (r2 (query-row db "select count(*) from t"))
            (after-cache-size (counts))
            (fk (execute! db "pragma foreign_keys = 1"))
            (s1 (query db "select x from t"))
            (s2 (query-row db "select count(*) from t"))
            (after-foreign-keys (counts)))
       (list fresh after-cache-size after-foreign-keys (list s1 (list s2))
             (if (and (eq? a (cached-statement db "select x from t"))
                      (eq? b (cached-statement db "select count(*) from t")))
                 'the-very-statements
                 'others))))))

;; Measured by M3 slice 0's research (P13b), on both libraries: any set of
;; trusted_schema, 0 or 1, expires every other statement, with the value
;; changed and with it already so.
(test-equal "trusted_schema = 0, then = 1, each run by execute!, makes every other cached statement re-prepare once at its next use, answering rightly: each is the very statement cached before"
  (list '(0 0) '(1 1) '(2 2) '((#(1)) (#(1))) 'the-very-statements)
  (with-memory-db
   (lambda (db)
     (let* ((m (execute! db "create table t (x)"))
            (i (execute! db "insert into t values (1)"))
            (q1 (query db "select x from t"))
            (q2 (query-row db "select count(*) from t"))
            (a (cached-statement db "select x from t"))
            (b (cached-statement db "select count(*) from t"))
            (counts (lambda () (list (reprepare-count a) (reprepare-count b))))
            (fresh (counts))
            (t0 (execute! db "pragma trusted_schema = 0"))
            (r1 (query db "select x from t"))
            (r2 (query-row db "select count(*) from t"))
            (after-0 (counts))
            (t1 (execute! db "pragma trusted_schema = 1"))
            (s1 (query db "select x from t"))
            (s2 (query-row db "select count(*) from t"))
            (after-1 (counts)))
       (list fresh after-0 after-1 (list s1 (list s2))
             (if (and (eq? a (cached-statement db "select x from t"))
                      (eq? b (cached-statement db "select count(*) from t")))
                 'the-very-statements
                 'others))))))

(test-equal "at a capacity of 2, the statements A, B, A, C, run by execute!, query, query-row and query-fold, leave A and C: A's reuse makes B the least recently used, and C's return evicts it"
  (list '(("select 'a'" . ready) ("select 'c'" . ready)) '(2 2))
  (with-capacity 2
    (lambda (db)
      (let* ((a (execute! db "select 'a'"))
             (b (query db "select 'b'"))
             (a2 (query-row db "select 'a'"))
             (c (query-fold db "select 'c'" (lambda (acc row) acc) 0)))
        (list (states db) (cache db))))))

(test-equal "a statement whose step failed is finalized on its return, never kept: execute!'s failed insert leaves none of its SQL, and its next call prepares afresh and runs"
  (list (list 'raised (list 'sqlite-error 'execute! 'constraint 'constraint-unique "insert into t values (?)" #f))
        '() 'no-value '(("insert into t values (?)" . ready)) '(#(0) #(1)))
  (with-file-db
   (lambda (path db)
     (let* ((a (attempt (lambda () (execute! db "insert into t values (?)" 0))))
            (left (states db))
            (b (no-value (execute! db "insert into t values (?)" 1))))
       (list a left b (states db) (tier-run db "select x from t order by x"))))))

;; Measured (.plans/research/m3-slice-3/busy-reset.sps, part A's;
;; .plans/research/m2-slice-3/probe-block.sps), on both libraries: an
;; insert ... returning stepped once
;; under another's read answers busy at its reset, and the insert is rolled
;; back.
(test-equal "a reset's failure on return is raised: query-row on a multi-row insert ... returning, under another connection's read, answers its first row, then its reset commits and answers busy, raised from query-row; the statement is finalized, not kept, and the insert rolled back"
  (list (list 'raised (list 'sqlite-error 'query-row 'busy 'busy returning-sql #f))
        '() '(#(1)))
  (with-file-db
   (lambda (path db)
     (let* ((r (under-reader path (lambda () (attempt (lambda () (query-row db returning-sql)))))))
       (list r (states db) (tier-run db "select count(*) from t"))))))

;; --- every path ------------------------------------------------------------------------------

(test-equal "execute!, query and query-row finish their statement on every path: after a refused bind, a failed step and a failed read none is left at a row; a refused bind and a failed read leave it cached and ready, a failed step finalized; and the next call of each SQL answers"
  (list (list 'raised (refused 'execute! 'boolean 1 '(kind boolean)))
        (list 'raised (list 'sqlite-error 'query 'error 'error "select abs(?1 - 1)" #f))
        (list 'raised (list 'invalid-text 'query-row 0 0))
        (list 'raised (list 'invalid-text 'query 0 0))
        '(("select ?1 + 0" . ready) ("select cast(?1 as text)" . ready)
          ("select x'ff' || ?1" . ready))
        (list 'no-value '(#(2)) '#("y") '(#(3)) '(#(1))))
  (with-memory-db
   (lambda (db)
     (let* ((a (attempt (lambda () (execute! db "select ?1 + 0" #t))))
            (b (attempt (lambda () (query db "select abs(?1 - 1)" -9223372036854775807))))
            (c (attempt (lambda () (query-row db "select cast(?1 as text)" (u8-list->bytevector (list #xff))))))
            (d (attempt (lambda () (query db "select x'ff' || ?1" ""))))
            (left (states db))
            (e (list (no-value (execute! db "select ?1 + 0" 1))
                     (query db "select ?1 + 0" 2)
                     (query-row db "select cast(?1 as text)" "y")
                     (query db "select ?1 + 0" 3)
                     (query db "select abs(?1 - 1)" 0))))
       (list a b c d left e)))))

(test-equal "a convenience's own condition reaches the caller unchanged, a failure of the return beside it dropped: query-row and query, reading an insert ... returning whose second column is not well-formed TEXT under another's read, raise &sqlite-invalid-text, never the reset's busy; each statement is finalized, its reset having failed, and each insert rolled back"
  (list (list 'raised (list 'invalid-text 'query-row 1 0)) (list 'raised (list 'invalid-text 'query 1 0))
        '() '(#(1)))
  (with-file-db
   (lambda (path db)
     (let* ((r (under-reader path
                 (lambda ()
                   (let* ((a (attempt (lambda () (query-row db "insert into t values (1), (2) returning x, cast(x'ff' as text)"))))
                          (b (attempt (lambda () (query db "insert into t values (3), (4) returning x, cast(x'ff' as text)")))))
                     (list a b))))))
       (append r (list (states db) (tier-run db "select count(*) from t")))))))

(test-equal "query-fold finishes its statement on every path: a normal return caches it, ready; the procedure's raise, its escape through a continuation, its own failed step and its own failed read each leave it finalized; none is left at a row"
  (list 6 '(("select x from n" . ready))
        (list 'raised '(the-symbol boom)) '(("select x from n" . ready))
        'escaped '(("select x from n" . ready))
        (list 'raised (list 'sqlite-error 'query-fold 'error 'error "select 1 union all select abs(-9223372036854775807 - 1)" #f))
        (list 'raised (list 'invalid-text 'query-fold 0 0))
        '(("select x from n" . ready)))
  (with-memory-db
   (lambda (db)
     (let* ((m (execute! db "create table n (x)"))
            (i (execute! db "insert into n values (1), (2), (3)"))
            (sum (lambda (acc row) (+ acc (vector-ref row 0))))
            (a (query-fold db "select x from n" sum 0))
            (after-a (filter (lambda (s) (string=? (car s) "select x from n")) (states db)))
            (b (attempt (lambda () (query-fold db "select x * 2 from n" (lambda (acc row) (raise 'boom)) 0))))
            (after-b (filter (lambda (s) (not (member (car s) '("create table n (x)" "insert into n values (1), (2), (3)"))))
                             (states db)))
            (c (call/cc (lambda (k) (query-fold db "select x * 3 from n" (lambda (acc row) (k 'escaped)) 0))))
            (after-c (filter (lambda (s) (not (member (car s) '("create table n (x)" "insert into n values (1), (2), (3)"))))
                             (states db)))
            (d (attempt (lambda () (query-fold db "select 1 union all select abs(-9223372036854775807 - 1)" sum 0))))
            (e (attempt (lambda () (query-fold db "select cast(x'ff' as text)" (lambda (acc row) acc) 0))))
            (after-e (filter (lambda (s) (not (member (car s) '("create table n (x)" "insert into n values (1), (2), (3)"))))
                             (states db))))
       (list a after-a b after-b c after-c d e after-e)))))

;; SQLite's own account of a statement at a row, never this library's state:
;; while any statement of a connection holds one, an interrupt sticks, and
;; every new prepare answers 9 (M3's research, concurrency I3; slice 0's
;; P7). So the row reads what the cache's states cannot show, a statement
;; filed ready that SQLite still holds at its row.
(test-equal "no convenience leaves its statement at a row, by SQLite's own account: after each returns or raises, an interrupt on its connection is lost and the next prepare runs, where a statement the suite holds at a row makes that prepare answer interrupt"
  (list (list 'held (list 'raised (list 'sqlite-error 'prepare-statement 'interrupt 'interrupt "select 7" #f)))
        '(#(1) (#(7)))
        '((#(1) #(2) #(3)) (#(7)))
        '(no-value (#(7)))
        '(6 (#(7)))
        '(no-value (#(7)))
        (list (list 'raised (list 'invalid-text 'query-row 1 0)) '(#(7)))
        (list (list 'raised (list 'invalid-text 'query 1 0)) '(#(7)))
        (list (list 'raised '(the-symbol boom)) '(#(7)))
        '(escaped (#(7)))
        (list (list 'raised (list 'invalid-text 'query-fold 1 0)) '(#(7))))
  (let* ((sum (lambda (acc row) (+ acc (vector-ref row 0))))
         (bad "select x, cast(x'ff' as text) from n")
         (control (after-interrupt
                   (lambda (db)
                     (let ((st (prepare-statement db "select x from n")))
                       (step! st)
                       'held))))
         (a (after-interrupt (lambda (db) (query-row db "select x from n"))))
         (b (after-interrupt (lambda (db) (query db "select x from n"))))
         (c (after-interrupt (lambda (db) (no-value (execute! db "insert into n values (4) returning x")))))
         (d (after-interrupt (lambda (db) (query-fold db "select x from n" sum 0))))
         (e (after-interrupt (lambda (db) (no-value (execute-script! db "select x from n; select 1")))))
         (f (after-interrupt (lambda (db) (query-row db bad))))
         (g (after-interrupt (lambda (db) (query db bad))))
         (h (after-interrupt (lambda (db) (query-fold db "select x from n" (lambda (acc row) (raise 'boom)) 0))))
         (i (after-interrupt
             (lambda (db)
               (call/cc (lambda (k) (query-fold db "select x from n" (lambda (acc row) (k 'escaped)) 0))))))
         (j (after-interrupt (lambda (db) (query-fold db bad sum 0)))))
    (list control a b c d e f g h i j)))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "conveniences")

(exit (suite-exit-status runner))
