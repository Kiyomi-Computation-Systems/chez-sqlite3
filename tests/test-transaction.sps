#!r6rs
;;; The suite for with-transaction (ADR-0017, amended in M3 slices 1 and 3;
;;; the M3 plan, section 4.2), in (chez-sqlite3 private transaction). Its
;;; NOMEM rows are tests/test-transaction-nomem.sps's, its engine rows
;;; tests/test-transaction-engine.sps's, and its interrupted writes
;;; tests/test-transaction-interrupt.sps's.
;;;
;;;   the surface   the body, then the mode, then the database checked before
;;;                 anything reaches C; a BEGIN that fails, raised
;;;   [A]           the errors that end a transaction, and those that don't,
;;;                 at the outer level and nested: with-transaction reads
;;;                 autocommit and rolls back only a level still there
;;;   [B]           nesting through the caller's own BEGIN
;;;   [C]           a failed COMMIT or RELEASE rolled back (Q6), once
;;;   [D]           a body that returns after its transaction ended (Q7)
;;;   [E]           the sticky interrupt's failed rollback and RELEASE, after
;;;                 a raise, a return or an escape
;;;   [F]           the refusal beside a statement at a row or failed
;;;   [G]           a fold inside with-transaction, writing at once
;;;   [H]           a resumed body, a continuation called after the commit, a
;;;                 nested level re-entered; a handler before the unwind that
;;;                 begins a transaction, rolled back with the body's, unless
;;;                 the call had already ended its level
;;;   the plants    the M3 plan's section 4.8, each by its row
;;;
;;; Each row builds its base from values other than the defaults: a marker
;;; row, a second connection's view, a mode other than immediate where the
;;; mode is not the point. Each asserts the whole outcome: what
;;; with-transaction raised or answered, in-transaction? after, the markers
;;; as this connection and a second one see them, and where it reads them,
;;; the connection's extended code, through native's
;;; sqlite3-extended-errcode and call-with-open-handle, and the statements
;;; with-transaction issued, as the connection tracks them: a statement whose
;;; step failed is finalized, never kept, so a ready one in the cache stepped
;;; and answered done.
;;;
;;; Reached through eval under a guard, as the conveniences' suites reach
;;; them. Every computation that can raise runs under a guard with a sentinel
;;; of its own. No expected value is #f where the actual could raise.
;;; Effects run in order, through let* and named lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) fork-thread make-mutex make-condition with-mutex condition-wait
              condition-signal make-time foreign-procedure)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-closed? sqlite-busy? sqlite-constraint?
              sqlite-transaction-ended? sqlite-wrong-thread?)
        (only (chez-sqlite3 private conditions) sqlite-interrupt?))

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

(define public '(chez-sqlite3))
(define connection-library '(chez-sqlite3 private connection))
(define statement-library '(chez-sqlite3 private statement))
(define native-library '(chez-sqlite3 private native))
(define with-transaction (reach public 'with-transaction))
(define open-database (reach public 'open-database))
(define close-database! (reach public 'close-database!))
(define execute! (reach public 'execute!))
(define query (reach public 'query))
(define query-row (reach public 'query-row))
(define query-fold (reach public 'query-fold))
(define in-transaction? (reach public 'in-transaction?))
(define prepare-statement (reach public 'prepare-statement))
(define finalize-statement! (reach public 'finalize-statement!))
(define step! (reach public 'step!))
(define reset! (reach public 'reset!))
(define bind! (reach public 'bind!))
(define column-value (reach public 'column-value))
(define statement-sql (reach public 'statement-sql))
(define statement-state (reach statement-library 'statement-state))
(define tracked-statements (reach connection-library 'tracked-statements))
(define call-with-open-handle (reach connection-library 'call-with-open-handle))
(define database-cache-count (reach connection-library 'database-cache-count))
(define open-database-with-cache-capacity (reach connection-library 'open-database-with-cache-capacity))
(define sqlite3-extended-errcode (reach native-library 'sqlite3-extended-errcode))
(define sqlite3-interrupt (reach native-library 'sqlite3-interrupt))
(define call-with-statement-handle (reach statement-library 'call-with-statement-handle))

;; --- bound here, after the load --------------------------------------------------------------

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_stmt_status(sqlite3_stmt*, int op, int reset), never bound by
;; chez-sqlite3. With SQLITE_STMTSTATUS_RUN, 6 in sqlite3.h at the floor and
;; since, it counts a run when a step starts the statement's program: the
;; first step after a prepare or a reset. A step that fails at its entry, as
;; an interrupted one does beside a held row, starts none and counts none
;; (M3 slice 4's review), so the interrupted rows, [E]'s, read no runs. The
;; runs row below holds its meaning by a control.
(define stmt-status (bound 'sqlite3_stmt_status (foreign-procedure "sqlite3_stmt_status" (uptr int int) int)))
(define stmtstatus-run 6)

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
;; An &sqlite-error as its class, who, code and extended code; the others
;; by their kind and who; a raised value that is no condition as itself.
(define (what-raised e)
  (cond ((sqlite-transaction-ended? e) (list 'transaction-ended (who-of e)))
        ((sqlite-error? e)
         (list (cond ((sqlite-busy? e) 'sqlite-busy)
                     ((sqlite-constraint? e) 'sqlite-constraint)
                     ((sqlite-interrupt? e) 'sqlite-interrupt)
                     (else 'sqlite-error))
               (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((sqlite-wrong-thread? e) (list 'wrong-thread (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        ((condition? e) (list 'other (describe e)))
        (else (list 'value e))))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define void-value (if #f #f))
(define (no-value x) (if (eq? x void-value) 'no-value x))

(define (with-handle db proc) (call-with-open-handle 'test-transaction db proc))

;; extended : Database -> Integer
;; The connection's extended code, read now.
(define (extended db) (with-handle db sqlite3-extended-errcode))

;; interrupt! : Database -> Void
;; sqlite3_interrupt on DB's handle, from this thread, while no step runs.
(define (interrupt! db) (with-handle db sqlite3-interrupt))

(define (prefix? p s) (and (<= (string-length p) (string-length s))
                           (string=? p (substring s 0 (string-length p)))))

;; own-sql? : String -> Boolean
;; Whether SQL is one of with-transaction's own statements (ADR-0017,
;; decision 4).
(define (own-sql? s)
  (or (member s '("BEGIN DEFERRED" "BEGIN IMMEDIATE" "BEGIN EXCLUSIVE" "COMMIT" "ROLLBACK"))
      (prefix? "SAVEPOINT chez_sqlite3_" s) (prefix? "RELEASE chez_sqlite3_" s)
      (prefix? "ROLLBACK TO chez_sqlite3_" s)))

;; issued : Database -> (Listof (Pairof String Symbol))
;; with-transaction's statements DB tracks, oldest first, each with its
;; state.
(define (issued db)
  (let loop ((rest (tracked-statements db)) (found '()))
    (if (null? rest)
        (reverse found)
        (let ((sql (statement-sql (car rest))))
          (loop (cdr rest)
                (if (own-sql? sql) (cons (cons sql (statement-state (car rest))) found) found))))))

;; runs : Statement -> Integer
;; How many times ST has run, by sqlite3_stmt_status, read through the
;; accessor.
(define (runs st)
  (call-with-statement-handle 'test-transaction st 'statement-sql
    (lambda (connection handle sql) (values #f (stmt-status handle stmtstatus-run 0)))))

;; issued-runs : Database -> (Listof (List String Symbol Integer))
;; issued, each statement with how many times it has run.
(define (issued-runs db)
  (let loop ((rest (tracked-statements db)) (found '()))
    (if (null? rest)
        (reverse found)
        (let ((sql (statement-sql (car rest))))
          (loop (cdr rest)
                (if (own-sql? sql)
                    (cons (list sql (statement-state (car rest)) (runs (car rest))) found)
                    found))))))

;; markers : Database -> Any
;; The rows of t, in order, joined by commas, or (none), as DB sees them.
(define (markers db)
  (attempt (lambda ()
             (vector-ref (query-row db "select coalesce(group_concat(x, ','), '(none)') from (select x from t order by x)")
                         0))))

;; schema : (Listof String)
;; t, the markers; b, bn, u, uc, ua, uf, ui, src, p, c, ci, r: the tables
;; each failure writes to, its constraint or trigger with it; src holds ten
;; rows of 3,000 bytes.
(define schema
  '("pragma foreign_keys = on"
    "create table t (x)" "create table b (x)" "create table r (x)"
    "create table u (x unique)" "insert into u values (1), (2)"
    "create table src (x)"
    "insert into src select replace(hex(zeroblob(1500)), '0', 'a') from (with recursive n(i) as (select 1 union all select i + 1 from n where i < 10) select i from n)"
    "create table p (id integer primary key)"
    "create table c (pid references p(id) deferrable initially deferred)"
    "create trigger tr before insert on u when new.x = 99 begin select raise(rollback, 'trigger said rollback'); end"
    "create table bn (x not null)"
    "create table uc (x unique not null check (x < 1000))" "insert into uc values (1)"
    "create table ua (x)"
    "create trigger ta before insert on ua when new.x = 99 begin select raise(abort, 'trigger said abort'); end"
    "create table uf (x)"
    "create trigger tf before insert on uf when new.x = 99 begin select raise(fail, 'trigger said fail'); end"
    "create table ui (x)"
    "create trigger ti before insert on ui when new.x = 99 begin select raise(ignore); end"
    "create table ci (pid references p(id))"))

(define temp-dir (guard (e (#t #f)) (make-process-temp-directory)))
(define case-number 0)

;; fresh-path : -> String
(define (fresh-path)
  (set! case-number (+ case-number 1))
  (string-append (or temp-dir "/nonexistent") "/case-" (number->string case-number) ".db"))

;; with-case : (Database Database -> Any) -> Any
;; PROC's answer, or what it raised, given DB and DB2, two connections to a
;; fresh file holding the schema; both closed after.
(define (with-case proc)
  (let ((db #f) (db2 #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt (lambda ()
                   (let ((path (fresh-path)))
                     (set! db (open-database path))
                     (for-each (lambda (sql) (execute! db sql)) schema)
                     (set! db2 (open-database path))
                     (proc db db2)))))
      (lambda ()
        (when db2 (guard (e (#t #f)) (close-database! db2)))
        (when db (guard (e (#t #f)) (close-database! db)))))))

;; open-uncached : String -> Database
;; A connection to PATH whose statement cache holds nothing, capacity 0, so
;; with-transaction prepares each of its statements afresh. The suite's one
;; call of the private opener, which M3 slice 5's statement-cache setting
;; replaces.
(define (open-uncached path) (open-database-with-cache-capacity 0 path))

;; with-uncached : (Database Database -> Any) -> Any
;; with-case, and a third connection to its file at capacity 0, closed after.
(define (with-uncached proc)
  (with-case
   (lambda (db db2)
     (let ((u (open-uncached (string-append temp-dir "/case-" (number->string case-number) ".db"))))
       (dynamic-wind
         (lambda () #f)
         (lambda () (proc u db2))
         (lambda () (guard (e (#t #f)) (close-database! u))))))))

;; full! : Database -> Void
;; The file held to the pages it has: PRAGMA max_page_count set to
;; page_count.
(define (full! db)
  (let ((pages (vector-ref (query-row db "pragma page_count") 0)))
    (query-row db (string-append "pragma max_page_count = " (number->string pages)))
    (if #f #f)))

;; failing : Symbol String -> (Database -> Any)
;; The body's failing statement: SQL through execute!, after full! when
;; METHOD is full.
(define (failing method sql)
  (lambda (db)
    (when (eq? method 'full) (full! db))
    (execute! db sql)))

;; outer-row : (Database -> Any) -> Any
;; with-transaction, deferred, around a marker and FAIL: what it raised,
;; then, in order, the extended code, in-transaction?, the markers on DB
;; and DB2, and with-transaction's statements.
(define (outer-row fail)
  (with-case
   (lambda (db db2)
     (let* ((r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda () (execute! db "insert into t values ('outer')") (fail db))))))
            (code (extended db))
            (in (in-transaction? db))
            (mine (markers db))
            (theirs (markers db2)))
       (list r code in mine theirs (issued db))))))

;; nested-row : (Database -> Any) -> Any
;; The same inside an outer with-transaction, deferred, whose body writes
;; its marker, catches what the inner raised, and returns: what the inner
;; raised; the extended code, in-transaction? and the markers on DB, all
;; straight after it; then what the outer answered or raised, in-transaction?
;; and the markers on DB and DB2 after it, and with-transaction's
;; statements.
(define (nested-row fail)
  (with-case
   (lambda (db db2)
     (let* ((inner #f)
            (outer (attempt (lambda ()
                              (with-transaction db 'deferred
                                (lambda ()
                                  (execute! db "insert into t values ('outer')")
                                  (let* ((r (attempt (lambda ()
                                                       (with-transaction db
                                                         (lambda ()
                                                           (execute! db "insert into t values ('inner')")
                                                           (fail db))))))
                                         (code (extended db))
                                         (in (in-transaction? db))
                                         (mine (markers db)))
                                    (set! inner (list r code in mine))
                                    'outer-returned))))))
            (in (in-transaction? db))
            (mine (markers db))
            (theirs (markers db2)))
       (list inner outer in mine theirs (issued db))))))

(define (failure class who code extended) (list 'raised (list class who code extended)))

;; ended-outer, open-outer, ended-nested, open-nested : ... -> Any
;; The whole outcomes [A] expects: ended, nothing issued and the body's
;; extended code standing; open, rolled back, ROLLBACK, or ROLLBACK TO and
;; RELEASE, each kept, so each answered done.
(define (ended-outer f code)
  (list f code 'no "(none)" "(none)" '(("BEGIN DEFERRED" . ready))))
(define (open-outer f)
  (list f 0 'no "(none)" "(none)" '(("BEGIN DEFERRED" . ready) ("ROLLBACK" . ready))))
(define (ended-nested f code)
  (list (list f code 'no "(none)")
        '(raised (transaction-ended with-transaction)) 'no "(none)" "(none)"
        '(("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready))))
(define (open-nested f)
  (list (list f 0 'yes "outer")
        'outer-returned 'no "outer" "outer"
        '(("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready)
          ("ROLLBACK TO chez_sqlite3_1" . ready) ("RELEASE chez_sqlite3_1" . ready)
          ("COMMIT" . ready))))

(define (yes-no-row r)
  ;; in-transaction? as yes or no, so no expected value is #f.
  (define (yn x) (cond ((eq? x #t) 'yes) ((eq? x #f) 'no) (else x)))
  (cond ((and (list? r) (= (length r) 6) (list? (car r)) (= (length (car r)) 4))
         ;; nested
         (list (list (car (car r)) (cadr (car r)) (yn (caddr (car r))) (cadddr (car r)))
               (cadr r) (yn (caddr r)) (cadddr r) (list-ref r 4) (list-ref r 5)))
        ((and (list? r) (= (length r) 6))
         (list (car r) (cadr r) (yn (caddr r)) (cadddr r) (list-ref r 4) (list-ref r 5)))
        (else r)))

(test-begin "transaction")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-assert "a temporary directory for the suite's databases"
  (string? temp-dir))

(test-equal "the runs sensor: a statement never stepped has run 0 times; stepped to done, once; reset and stepped again, twice; stepped to a row and reset unstepped, still twice"
  '(0 1 2 2)
  (with-case
   (lambda (db db2)
     (let* ((st (prepare-statement db "select x from src"))
            (a (runs st))
            (s1 (let loop () (when (step! st) (loop))))
            (b (runs st))
            (r1 (reset! st))
            (s2 (step! st))
            (c (runs st))
            (r2 (reset! st))
            (d (runs st)))
       (finalize-statement! st)
       (list a b c d)))))

;; --- the surface ----------------------------------------------------------------------------

(test-equal "with-transaction checks the body first, then the mode, then the database, each an assertion violation from with-transaction naming its rule, before anything reaches C: the extended code and in-transaction? stay as they were"
  (list '(raised (assertion-violation with-transaction (not-a-procedure (kind string))))
        '(raised (assertion-violation with-transaction (not-a-procedure 7)))
        '(raised (assertion-violation with-transaction (unknown-mode IMMEDIATE)))
        '(raised (assertion-violation with-transaction (unknown-mode (kind string))))
        '(raised (assertion-violation with-transaction (not-a-database x)))
        2067 'yes)
  (with-case
   (lambda (db db2)
     (let* ((begun (execute! db "begin"))
            (set-code (attempt (lambda () (execute! db "insert into u values (1)"))))
            (a (attempt (lambda () (with-transaction 'x 'nosuch "body"))))
            (b (attempt (lambda () (with-transaction db 7))))
            (c (attempt (lambda () (with-transaction 'x 'IMMEDIATE (lambda () 'ran)))))
            (d (attempt (lambda () (with-transaction db "immediate" (lambda () 'ran)))))
            (e (attempt (lambda () (with-transaction 'x 'deferred (lambda () 'ran)))))
            (code (extended db))
            (in (if (in-transaction? db) 'yes 'no)))
       (execute! db "rollback")
       (list a b c d e code in)))))

(test-equal "with-transaction on a closed connection raises &sqlite-closed from with-transaction, and runs no body"
  '((raised (closed with-transaction)) not-run)
  (with-case
   (lambda (db db2)
     (let* ((other (open-database ":memory:"))
            (closed (close-database! other))
            (ran 'not-run)
            (r (attempt (lambda () (with-transaction other 'deferred (lambda () (set! ran 'ran)))))))
       (list r ran)))))

(test-equal "with-transaction from a thread that did not open the connection raises &sqlite-wrong-thread from with-transaction, and runs no body; the wait for the thread is bounded"
  '((raised (wrong-thread with-transaction)) not-run)
  (with-case
   (lambda (db db2)
     (let* ((m (make-mutex)) (c (make-condition)) (answer #f) (ran 'not-run))
       (fork-thread
        (lambda ()
          (let ((r (attempt (lambda () (with-transaction db 'deferred (lambda () (set! ran 'ran)))))))
            (with-mutex m (set! answer (list r)) (condition-signal c)))))
       (with-mutex m
         (let wait ((tries 0))
           (cond (answer (list (car answer) ran))
                 ((>= tries 50) 'the-thread-did-not-answer-in-5-s)
                 (else (condition-wait c m (make-time 'time-duration 100000000 0))
                       (wait (+ tries 1))))))))))

(test-equal "with-transaction answers every value the body returns, and commits: db2 sees the marker"
  '((a b c) no "outer" "outer" (("BEGIN EXCLUSIVE" . ready) ("COMMIT" . ready)))
  (with-case
   (lambda (db db2)
     (let* ((r (attempt (lambda ()
                          (call-with-values
                           (lambda () (with-transaction db 'exclusive
                                        (lambda () (execute! db "insert into t values ('outer')") (values 'a 'b 'c))))
                           list))))
            (in (if (in-transaction? db) 'yes 'no)))
       (list r in (markers db) (markers db2) (issued db))))))

(test-equal "with no mode, with-transaction begins immediate: db2's BEGIN IMMEDIATE answers busy inside the body, before any write"
  '((raised (sqlite-busy execute! busy busy)) (("BEGIN IMMEDIATE" . ready) ("COMMIT" . ready)))
  (with-case
   (lambda (db db2)
     (let ((inside (attempt (lambda ()
                              (with-transaction db (lambda () (attempt (lambda () (execute! db2 "begin immediate")))))))))
       (list inside (issued db))))))

(test-equal "a BEGIN that fails: db2 holds begin immediate, and no busy timeout is set, so with-transaction's BEGIN IMMEDIATE answers busy at once: with-transaction raises &sqlite-busy from with-transaction, the body never runs, in-transaction? stays #f, the failed BEGIN finalized, and nothing is written"
  '((raised (sqlite-busy with-transaction busy busy)) not-run no 5 () "(none)")
  (with-case
   (lambda (db db2)
     (let* ((lock (execute! db2 "begin immediate"))
            (ran 'not-run)
            (r (attempt (lambda ()
                          (with-transaction db 'immediate
                            (lambda () (set! ran 'ran) (execute! db "insert into t values ('outer')") 'committed)))))
            (in (if (in-transaction? db) 'yes 'no))
            (code (extended db))
            (own (issued db))
            (unlock (execute! db2 "rollback")))
       (list r ran in code own (markers db2))))))

;; --- [A] the errors that end a transaction, and those that don't ------------------------------

;; ended-cases, open-cases : (Listof (List String Symbol String Any))
;; ID, METHOD (plain or full), SQL and the failure execute! raises.
(define ended-cases
  (list (list "E4" 'plain "insert or rollback into u values (1)"
              (failure 'sqlite-constraint 'execute! 'constraint 'constraint-unique))
        (list "E7" 'plain "update or rollback u set x = 1 where x = 2"
              (failure 'sqlite-constraint 'execute! 'constraint 'constraint-unique))
        (list "E8" 'plain "insert into u values (99)"
              (failure 'sqlite-constraint 'execute! 'constraint 'constraint-trigger))
        (list "E15, F5" 'full "insert into b values (zeroblob(100000))"
              (failure 'sqlite-error 'execute! 'full 'full))
        (list "E17" 'full "insert into bn values (zeroblob(100000))"
              (failure 'sqlite-error 'execute! 'full 'full))
        (list "F1" 'full "insert into b select x from src"
              (failure 'sqlite-error 'execute! 'full 'full))
        (list "F6" 'full "update src set x = x || x"
              (failure 'sqlite-error 'execute! 'full 'full))))

(define codes '((constraint-unique . 2067) (constraint-trigger . 1811) (full . 13)))
(define (code-of f) (cdr (assq (list-ref (cadr f) 3) codes)))

(define open-cases
  (list (list "E1" 'plain "insert into u values (1)"
              (failure 'sqlite-constraint 'execute! 'constraint 'constraint-unique))
        (list "E2" 'plain "insert into u values (20), (21), (1), (22)"
              (failure 'sqlite-constraint 'execute! 'constraint 'constraint-unique))
        (list "E3, not null" 'plain "insert into bn values (null)"
              (failure 'sqlite-constraint 'execute! 'constraint 'constraint-notnull))
        (list "E3, check" 'plain "insert into uc values (5000)"
              (failure 'sqlite-constraint 'execute! 'constraint 'constraint-check))
        (list "E6" 'plain "insert or fail into u values (30), (31), (1), (32)"
              (failure 'sqlite-constraint 'execute! 'constraint 'constraint-unique))
        (list "E9" 'plain "insert into ua values (40), (41), (99), (42)"
              (failure 'sqlite-constraint 'execute! 'constraint 'constraint-trigger))
        (list "E10" 'plain "insert into uf values (50), (51), (99), (52)"
              (failure 'sqlite-constraint 'execute! 'constraint 'constraint-trigger))
        (list "E12" 'plain "insert into ci values (7)"
              (failure 'sqlite-constraint 'execute! 'constraint 'constraint-foreignkey))
        (list "E14" 'plain
              "insert into b select case when v = 3 then abs(-9223372036854775807 - 1) else 100 + v end from (select 1 as v union all select 2 union all select 3 union all select 4)"
              (failure 'sqlite-error 'execute! 'error 'error))
        (list "E16" 'full
              "insert into b select zeroblob(3000) from (with recursive n(i) as (select 1 union all select i + 1 from n where i < 100) select i from n)"
              (failure 'sqlite-error 'execute! 'full 'full))
        (list "E18" 'full
              "insert into bn select zeroblob(3000) from (with recursive n(i) as (select 1 union all select i + 1 from n where i < 100) select i from n)"
              (failure 'sqlite-error 'execute! 'full 'full))
        (list "E19" 'full
              "insert into uc select 100 + i from (with recursive n(i) as (select 1 union all select i + 1 from n where i < 800) select i from n)"
              (failure 'sqlite-error 'execute! 'full 'full))
        (list "F2" 'full "insert into b select lower(x) from src"
              (failure 'sqlite-error 'execute! 'full 'full))
        (list "F3" 'full "insert into bn select x from src"
              (failure 'sqlite-error 'execute! 'full 'full))
        (list "F4" 'full "insert into b select zeroblob(3000) from src"
              (failure 'sqlite-error 'execute! 'full 'full))
        (list "F7" 'full "update src set x = lower(x || x)"
              (failure 'sqlite-error 'execute! 'full 'full))
        (list "F8" 'full "update src set x = zeroblob(9000)"
              (failure 'sqlite-error 'execute! 'full 'full))
        (list "E24" 'plain "insert into nosuch values (1)"
              (failure 'sqlite-error 'execute! 'error 'error))))

;; case-rows : (Listof ...) (Any -> Any) (Any -> Any) (Any -> Any) -> (Listof (List String Any Any))
;; Each case's ID, what it expects, and what it measured, at both levels.
(define (case-rows cases expect-outer expect-nested)
  (let loop ((rest cases) (out '()))
    (if (null? rest)
        (reverse out)
        (let* ((c (car rest))
               (fail (failing (cadr c) (caddr c)))
               (o (yes-no-row (outer-row fail)))
               (n (yes-no-row (nested-row fail))))
          (loop (cdr rest)
                (cons (list (car c) 'nested (expect-nested c) n)
                      (cons (list (car c) 'outer (expect-outer c) o) out)))))))

;; deviations : (Listof (List String Symbol Any Any)) -> (Listof Any)
(define (deviations rows)
  (filter (lambda (row) (not (equal? (caddr row) (cadddr row)))) rows))

(test-equal "[A] the failures that end the transaction, E4, E7, E8, and FULL in a statement with no statement journal, E15, E17, F1, F5, F6: with-transaction issues nothing, the body's condition from execute! reaches the caller, the extended code stays the body's, and the marker is gone from both connections; nested, the inner raises the body's condition, and the outer, its body catching it and returning, raises &sqlite-transaction-ended"
  '()
  (deviations (case-rows ended-cases
                         (lambda (c) (ended-outer (cadddr c) (code-of (cadddr c))))
                         (lambda (c) (ended-nested (cadddr c) (code-of (cadddr c)))))))

(test-equal "[A] the failures that leave it open, E1, E2, E3, E6, E9, E10, E12, E14, FULL with a statement journal, E16, E18, E19, F2, F3, F4, F7, F8, and E24, refused at prepare: with-transaction rolls the level back, ROLLBACK, or ROLLBACK TO then RELEASE, each kept, so each answered done; the body's condition reaches the caller; outer, the marker gone; nested, the outer marker only, and the outer commits it, which db2 then sees"
  '()
  (deviations (case-rows open-cases
                         (lambda (c) (open-outer (cadddr c)))
                         (lambda (c) (open-nested (cadddr c))))))

(test-equal "[A] E11, RAISE(IGNORE): no raise; the body returns and the level commits, outer and nested, and db2 sees the marker and the rows the trigger kept"
  '(((a-value) no "outer" "outer" "60,61,62" (("BEGIN DEFERRED" . ready) ("COMMIT" . ready)))
    ((a-value) inner-value no "inner,outer" "inner,outer" "60,61,62"
     (("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready) ("RELEASE chez_sqlite3_1" . ready)
      ("COMMIT" . ready))))
  (let* ((ui (lambda (db) (attempt (lambda ()
                                     (vector-ref (query-row db "select group_concat(x, ',') from (select x from ui order by x)") 0)))))
         (outer (with-case
                 (lambda (db db2)
                   (let* ((r (attempt (lambda ()
                                        (with-transaction db 'deferred
                                          (lambda ()
                                            (execute! db "insert into t values ('outer')")
                                            (execute! db "insert into ui values (60), (61), (99), (62)")
                                            (list 'a-value))))))
                          (in (if (in-transaction? db) 'yes 'no)))
                     (list r in (markers db) (markers db2) (ui db2) (issued db))))))
         (nested (with-case
                  (lambda (db db2)
                    (let* ((inner #f)
                           (r (attempt (lambda ()
                                         (with-transaction db 'deferred
                                           (lambda ()
                                             (execute! db "insert into t values ('outer')")
                                             (set! inner (with-transaction db
                                                           (lambda ()
                                                             (execute! db "insert into t values ('inner')")
                                                             (execute! db "insert into ui values (60), (61), (99), (62)")
                                                             'inner-value)))
                                             (list 'a-value))))))
                           (in (if (in-transaction? db) 'yes 'no)))
                      (list r inner in (markers db) (markers db2) (ui db2) (issued db)))))))
    (list outer nested)))

;; tables : Database -> Any
(define (tables db)
  (attempt (lambda () (query db "select name from sqlite_master where name in ('d', 'dn') order by name"))))

(test-equal "[A] DDL rolls back with the rest: a table the body created, and its row, are gone after the body raises, outer and nested; nested, the outer's own table stands"
  '(((raised (value boom)) no () () "(none)")
    ((raised (value boom)) outer-returned no (#("d")) (#("d")) "outer"))
  (let* ((outer (with-case
                 (lambda (db db2)
                   (let* ((r (attempt (lambda ()
                                        (with-transaction db 'deferred
                                          (lambda ()
                                            (execute! db "insert into t values ('outer')")
                                            (execute! db "create table d (x)")
                                            (execute! db "insert into d values (1)")
                                            (raise 'boom))))))
                          (in (if (in-transaction? db) 'yes 'no)))
                     (list r in (tables db) (tables db2) (markers db2))))))
         (nested (with-case
                  (lambda (db db2)
                    (let* ((inner #f)
                           (r (attempt (lambda ()
                                         (with-transaction db 'deferred
                                           (lambda ()
                                             (execute! db "insert into t values ('outer')")
                                             (execute! db "create table d (x)")
                                             (set! inner (attempt (lambda ()
                                                                    (with-transaction db
                                                                      (lambda ()
                                                                        (execute! db "create table dn (x)")
                                                                        (execute! db "insert into dn values (1)")
                                                                        (raise 'boom))))))
                                             'outer-returned)))))
                           (in (if (in-transaction? db) 'yes 'no)))
                      (list inner r in (tables db) (tables db2) (markers db2)))))))
    (list outer nested)))

(test-equal "[A] at capacity 0, with-transaction prepares each of its statements afresh and keeps none: a commit, a rollback, and a nested level each, the cache empty and none of its statements tracked after, the markers as at capacity 32"
  '((committed rolled-back (raised (value inner-raised)) outer-committed) 0 () "inner-kept,outer,outer-kept")
  (with-uncached
   (lambda (u db2)
     (let* ((a (with-transaction u 'deferred (lambda () (execute! u "insert into t values ('outer')") 'committed)))
            (b (attempt (lambda ()
                          (with-transaction u 'deferred
                            (lambda () (execute! u "insert into t values ('undone')") (raise 'rolled-back))))))
            (inner #f)
            (c (with-transaction u 'deferred
                 (lambda ()
                   (execute! u "insert into t values ('outer-kept')")
                   (set! inner (attempt (lambda ()
                                          (with-transaction u
                                            (lambda () (execute! u "insert into t values ('inner-undone')")
                                                    (raise 'inner-raised))))))
                   (with-transaction u (lambda () (execute! u "insert into t values ('inner-kept')")))
                   'outer-committed))))
       (list (list a (if (equal? b '(raised (value rolled-back))) 'rolled-back b) inner c)
             (database-cache-count u) (issued u) (markers db2))))))

;; --- [B] nesting through the caller's own BEGIN ------------------------------------------------

(test-equal "[B] inside the caller's own BEGIN, with-transaction's level is SAVEPOINT chez_sqlite3_0, and its RELEASE commits nothing: db2 sees nothing until the caller's COMMIT"
  '(inner-value yes "inner,outer" "(none)" "inner,outer"
    (("SAVEPOINT chez_sqlite3_0" . ready) ("RELEASE chez_sqlite3_0" . ready)))
  (with-case
   (lambda (db db2)
     (let* ((b (execute! db "begin"))
            (m (execute! db "insert into t values ('outer')"))
            (r (attempt (lambda ()
                          (with-transaction db 'exclusive
                            (lambda () (execute! db "insert into t values ('inner')") 'inner-value)))))
            (in (if (in-transaction? db) 'yes 'no))
            (mine (markers db))
            (before (markers db2))
            (c (execute! db "commit"))
            (after (markers db2)))
       (list r in mine before after (issued db))))))

(test-equal "[B] a nested mode has no effect: exclusive inside a deferred transaction that holds no lock yet begins nothing new, so db2 still reads inside the inner body, where BEGIN EXCLUSIVE's lock, taken even when SQLite refuses the BEGIN inside a transaction, would make it busy; the outer writes its marker after the inner call"
  '((inner-value "(none)") outer-value "inner,outer"
    (("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready) ("RELEASE chez_sqlite3_1" . ready)
     ("COMMIT" . ready)))
  (with-case
   (lambda (db db2)
     (let* ((inner #f)
            (r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda ()
                              (set! inner (with-transaction db 'exclusive
                                            (lambda ()
                                              (execute! db "insert into t values ('inner')")
                                              (list 'inner-value (markers db2)))))
                              (execute! db "insert into t values ('outer')")
                              'outer-value))))))
       (list inner r (markers db2) (issued db))))))

(test-equal "[B] with-transaction never issues BEGIN inside a transaction: inside the caller's deferred BEGIN, immediate and exclusive take no lock, so db2's BEGIN IMMEDIATE succeeds inside the body, and the extended code after is 0, never a refused BEGIN's 1"
  '((no-value no-value) 0 (("SAVEPOINT chez_sqlite3_0" . ready) ("RELEASE chez_sqlite3_0" . ready)))
  (with-case
   (lambda (db db2)
     (let* ((b (execute! db "begin"))
            (seen '())
            (one (lambda (mode)
                   (with-transaction db mode
                     (lambda ()
                       (let ((r (attempt (lambda () (no-value (execute! db2 "begin immediate"))))))
                         (execute! db2 "rollback")
                         (set! seen (cons r seen)))))))
            (i (attempt (lambda () (one 'immediate))))
            (x (attempt (lambda () (one 'exclusive))))
            (code (extended db))
            (c (execute! db "rollback")))
       (list (reverse seen) code (issued db))))))

;; --- [C] a failed COMMIT rolled back (Q6) -------------------------------------------------------

(test-equal "[C] E13, outer: a child with a deferred foreign key; COMMIT answers 787, so with-transaction rolls back, ROLLBACK kept, the failed COMMIT finalized, and raises &sqlite-constraint from with-transaction, extended 787; in-transaction? #f; the marker gone"
  '((raised (sqlite-constraint with-transaction constraint constraint-foreignkey)) no "(none)" "(none)"
    (("BEGIN DEFERRED" . ready) ("ROLLBACK" . ready)))
  (with-case
   (lambda (db db2)
     (let* ((r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda ()
                              (execute! db "insert into t values ('outer')")
                              (execute! db "insert into c values (7)"))))))
            (in (if (in-transaction? db) 'yes 'no)))
       (list r in (markers db) (markers db2) (issued db))))))

(test-equal "[C] E13, nested: the inner RELEASE succeeds, a deferred key being checked at COMMIT alone; the outer's COMMIT answers 787, is rolled back, and raised"
  '(inner-value (raised (sqlite-constraint with-transaction constraint constraint-foreignkey)) no "(none)" "(none)"
    (("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready) ("RELEASE chez_sqlite3_1" . ready)
     ("ROLLBACK" . ready)))
  (with-case
   (lambda (db db2)
     (let* ((inner #f)
            (r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda ()
                              (execute! db "insert into t values ('outer')")
                              (set! inner (with-transaction db
                                            (lambda () (execute! db "insert into c values (7)") 'inner-value)))
                              'outer-value)))))
            (in (if (in-transaction? db) 'yes 'no)))
       (list inner r in (markers db) (markers db2) (issued db))))))

(test-equal "[C] O7, outer: an insert ... returning held at its row; COMMIT answers busy, ROLLBACK succeeds beside it, and with-transaction raises &sqlite-busy, extended busy; in-transaction? #f; the marker gone; the held statement's next step! answers its row"
  '((raised (sqlite-busy with-transaction busy busy)) no "(none)" "(none)"
    (("BEGIN DEFERRED" . ready) ("ROLLBACK" . ready)) yes)
  (with-case
   (lambda (db db2)
     (let* ((held #f)
            (r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda ()
                              (execute! db "insert into t values ('outer')")
                              (set! held (prepare-statement db "insert into r values (6), (7) returning x"))
                              (step! held)
                              'returned)))))
            (in (if (in-transaction? db) 'yes 'no))
            (mine (markers db))
            (theirs (markers db2))
            (own (issued db))
            (next (attempt (lambda () (if (step! held) 'yes 'no)))))
       (finalize-statement! held)
       (list r in mine theirs own next)))))

;; o7-nested : Boolean -> Any
;; O7 inside an outer with-transaction, deferred: the inner body writes
;; inner, holds the insert ... returning at its row, and returns. Then the
;; outer body writes between, inside the savepoint the inner left open;
;; when FINISH, finalizes the held statement; runs a sibling at the same
;; depth that writes sibling and raises, then one that writes kept and
;; returns; and returns. What the inner raised, with the extended code,
;; in-transaction? and the markers straight after; each sibling's answer and
;; the markers after it; what the outer answered or raised; in-transaction?;
;; the markers on DB and DB2; with-transaction's statements; and the held
;; statement's next step, when it is still held.
(define (o7-nested finish)
  (with-case
   (lambda (db db2)
     (let* ((held #f) (inner #f) (siblings #f)
            (r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda ()
                              (execute! db "insert into t values ('outer')")
                              (let* ((i (attempt (lambda ()
                                                   (with-transaction db
                                                     (lambda ()
                                                       (execute! db "insert into t values ('inner')")
                                                       (set! held (prepare-statement db "insert into r values (6), (7) returning x"))
                                                       (step! held)
                                                       'inner-returned)))))
                                     (code (extended db))
                                     (in (if (in-transaction? db) 'yes 'no))
                                     (mine (markers db)))
                                (set! inner (list i code in mine)))
                              (execute! db "insert into t values ('between')")
                              (when finish (finalize-statement! held))
                              (let* ((s1 (attempt (lambda ()
                                                    (with-transaction db
                                                      (lambda ()
                                                        (execute! db "insert into t values ('sibling')")
                                                        (raise 'sibling-raised))))))
                                     (m1 (markers db))
                                     (s2 (attempt (lambda ()
                                                    (with-transaction db
                                                      (lambda ()
                                                        (execute! db "insert into t values ('kept')")
                                                        'sibling-returned)))))
                                     (m2 (markers db)))
                                (set! siblings (list s1 m1 s2 m2)))
                              'outer-returned)))))
            (in (if (in-transaction? db) 'yes 'no))
            (mine (markers db))
            (theirs (markers db2))
            (own (issued-runs db))
            (next (if finish 'finished (attempt (lambda () (if (step! held) 'yes 'no))))))
       (unless finish (finalize-statement! held))
       (list inner siblings r in mine theirs own next)))))

(test-equal "[C] O7, nested, the held statement finished before the siblings: RELEASE answers busy, ROLLBACK TO succeeds, its RELEASE answers busy again, and then nothing more: &sqlite-busy from with-transaction, the inner level's writes undone, its savepoint left open and in-transaction? #t; the inner's ROLLBACK TO ran once, never again from the after thunk. By Reuse N, a sibling at the same depth issues SAVEPOINT chez_sqlite3_1 again and acts only on its own: one that raises rolls back its own write alone, between, written inside the savepoint left open, standing; one that returns keeps kept; the outer commits them, and db2 sees them"
  '(((raised (sqlite-busy with-transaction busy busy)) 5 yes "outer")
    ((raised (value sibling-raised)) "between,outer" sibling-returned "between,kept,outer")
    outer-returned no "between,kept,outer" "between,kept,outer"
    (("BEGIN DEFERRED" ready 1) ("SAVEPOINT chez_sqlite3_1" ready 3) ("ROLLBACK TO chez_sqlite3_1" ready 2)
     ("RELEASE chez_sqlite3_1" ready 2) ("COMMIT" ready 1))
    finished)
  (o7-nested #t))

(test-equal "[C] O7, nested, the held statement still held: the same inner outcome; each sibling is refused beside the held row, an assertion violation from with-transaction; the outer's COMMIT answers busy, is rolled back, and raised; db2 sees nothing, and the held statement's next step! answers its row; ROLLBACK TO and ROLLBACK each ran once"
  '(((raised (sqlite-busy with-transaction busy busy)) 5 yes "outer")
    ((raised (assertion-violation with-transaction (statement-not-finished row "insert into r values (6), (7) returning x")))
     "between,outer"
     (raised (assertion-violation with-transaction (statement-not-finished row "insert into r values (6), (7) returning x")))
     "between,outer")
    (raised (sqlite-busy with-transaction busy busy)) no "(none)" "(none)"
    (("BEGIN DEFERRED" ready 1) ("SAVEPOINT chez_sqlite3_1" ready 1) ("ROLLBACK TO chez_sqlite3_1" ready 1)
     ("ROLLBACK" ready 1))
    yes)
  (o7-nested #f))

;; --- [D] a body that returns after its transaction ended (Q7) ----------------------------------

(test-equal "[D] L1, outer: the body catches insert or rollback's constraint-unique and writes again; that write autocommits, and db2 sees it at once; the body's return raises &sqlite-transaction-ended from with-transaction, no COMMIT issued, the extended code the later write's"
  '((raised (transaction-ended with-transaction)) "after" 0 no "after" (("BEGIN DEFERRED" . ready)))
  (with-case
   (lambda (db db2)
     (let* ((seen #f)
            (r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda ()
                              (execute! db "insert into t values ('outer')")
                              (attempt (lambda () (execute! db "insert or rollback into u values (1)")))
                              (execute! db "insert into t values ('after')")
                              (set! seen (markers db2))
                              'returned)))))
            (code (extended db))
            (in (if (in-transaction? db) 'yes 'no)))
       (list r seen code in (markers db2) (issued db))))))

(test-equal "[D] L1, nested: the inner body's later write autocommits, the inner's return raises &sqlite-transaction-ended, no RELEASE issued, and the outer, its body returning after it, raises it too, no COMMIT issued"
  '((raised (transaction-ended with-transaction)) "after"
    (raised (transaction-ended with-transaction)) no "after"
    (("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready)))
  (with-case
   (lambda (db db2)
     (let* ((seen #f) (inner #f)
            (r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda ()
                              (execute! db "insert into t values ('outer')")
                              (set! inner (attempt (lambda ()
                                                     (with-transaction db
                                                       (lambda ()
                                                         (execute! db "insert into t values ('inner')")
                                                         (attempt (lambda () (execute! db "insert or rollback into u values (1)")))
                                                         (execute! db "insert into t values ('after')")
                                                         (set! seen (markers db2))
                                                         'returned)))))
                              'outer-returned)))))
            (in (if (in-transaction? db) 'yes 'no)))
       (list inner seen r in (markers db2) (issued db))))))

;; --- [E] the sticky interrupt -------------------------------------------------------------------

;; sticky : Boolean Symbol Boolean -> Any
;; The body, at NESTED's level, writes inner, holds a statement of its own
;; at a row, select x from t, then sqlite3_interrupt is called on the handle
;; while no step runs, and the body raises or returns, by HOW. When CACHED,
;; an earlier with-transaction at each level has left its statements in the
;; cache, rolled back. Nested, the outer body writes outer, catches the
;; inner's raise, and raises outer-raised. What with-transaction raised,
;; the inner's too when nested; the extended code; in-transaction?; db2's
;; count of t, the three base rows; with-transaction's statements; then,
;; once the caller has reset its statement, a plain rollback and
;; in-transaction? after it.
(define (sticky nested how cached)
  (with-case
   (lambda (db db2)
     (let* ((base (execute! db "insert into t values (1), (2), (3)"))
            (primed (when cached
                      (attempt (lambda ()
                                 (with-transaction db 'deferred
                                   (lambda ()
                                     (attempt (lambda ()
                                                (with-transaction db (lambda () (execute! db "insert into t values (9)") (raise 'primed)))))
                                     (with-transaction db (lambda () 'primed))
                                     (raise 'primed)))))))
            (held #f)
            (inner #f)
            (body (lambda ()
                    (execute! db "insert into t values ('inner')")
                    (set! held (prepare-statement db "select x from t"))
                    (step! held)
                    (interrupt! db)
                    (if (eq? how 'raise) (raise 'the-body-raised) 'the-body-returned)))
            (r (attempt (lambda ()
                          (if nested
                              (with-transaction db 'deferred
                                (lambda ()
                                  (execute! db "insert into t values ('outer')")
                                  (set! inner (attempt (lambda () (with-transaction db body))))
                                  (raise 'outer-raised)))
                              (with-transaction db 'deferred body)))))
            (code (extended db))
            (in (if (in-transaction? db) 'yes 'no))
            (count (attempt (lambda () (vector-ref (query-row db2 "select count(*) from t") 0))))
            (own (issued db))
            (reset (no-value (attempt (lambda () (reset! held)))))
            (rolled (no-value (attempt (lambda () (execute! db "rollback")))))
            (after (if (in-transaction? db) 'yes 'no)))
       (finalize-statement! held)
       (list inner r code in count own reset rolled after)))))

(define primed-outer '(("BEGIN DEFERRED" . ready)))
(define begun-nested '(("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready)))
(define primed-nested
  '(("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready) ("ROLLBACK TO chez_sqlite3_1" . ready)
    ("RELEASE chez_sqlite3_1" . ready)))

(test-equal "[E] the sticky interrupt, the body raising, outer: the body's own condition reaches the caller; ROLLBACK fails, at its prepare uncached, at its step cached, where it is finalized and leaves the cache; the transaction stays open, extended interrupt, and db2 counts the base rows; once the caller resets its statement, a plain rollback ends it"
  (list (list #f '(raised (value the-body-raised)) 9 'yes 3 primed-outer 'no-value 'no-value 'no)
        (list #f '(raised (value the-body-raised)) 9 'yes 3 primed-nested 'no-value 'no-value 'no))
  (list (sticky #f 'raise #f) (sticky #f 'raise #t)))

(test-equal "[E] the sticky interrupt, the body returning, outer: COMMIT fails with interrupt, at its prepare or its step, and is rolled back, which fails the same way; the COMMIT's &sqlite-interrupt is raised from with-transaction with the transaction open"
  (list (list #f '(raised (sqlite-interrupt with-transaction interrupt interrupt)) 9 'yes 3 primed-outer
              'no-value 'no-value 'no)
        (list #f '(raised (sqlite-interrupt with-transaction interrupt interrupt)) 9 'yes 3 primed-nested
              'no-value 'no-value 'no))
  (list (sticky #f 'return #f) (sticky #f 'return #t)))

(test-equal "[E] the sticky interrupt, nested: the inner's ROLLBACK TO fails, its RELEASE never issued after it, the cached one still ready; or the inner's RELEASE fails, then its ROLLBACK TO, cached at their steps and finalized; the savepoint and the outer stay open, the outer's own ROLLBACK failing as well, and db2 counts the base rows"
  (list (list '(raised (value the-body-raised)) '(raised (value outer-raised)) 9 'yes 3 begun-nested
              'no-value 'no-value 'no)
        (list '(raised (value the-body-raised)) '(raised (value outer-raised)) 9 'yes 3
              '(("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready) ("RELEASE chez_sqlite3_1" . ready))
              'no-value 'no-value 'no)
        (list '(raised (sqlite-interrupt with-transaction interrupt interrupt)) '(raised (value outer-raised)) 9
              'yes 3 begun-nested 'no-value 'no-value 'no)
        (list '(raised (sqlite-interrupt with-transaction interrupt interrupt)) '(raised (value outer-raised)) 9
              'yes 3 begun-nested 'no-value 'no-value 'no))
  (list (sticky #t 'raise #f) (sticky #t 'raise #t) (sticky #t 'return #f) (sticky #t 'return #t)))

;; sticky-escape : Boolean -> Any
;; The body, outer, writes inner, holds select x from t at a row, and
;; sqlite3_interrupt is called on the handle while no step runs; then the
;; body leaves through a continuation taken outside the call: an escape, no
;; raise. When RESUMED, the body first raises warning with raise-continuable,
;; which a handler around the call answers, so the body goes on. What the
;; call answered or raised; the extended code; in-transaction?; db2's count
;; of t, the three base rows; with-transaction's statements; then, once the
;; caller has reset its statement, a plain rollback and in-transaction?
;; after it.
(define (sticky-escape resumed)
  (with-case
   (lambda (db db2)
     (let* ((base (execute! db "insert into t values (1), (2), (3)"))
            (held #f)
            (r (attempt (lambda ()
                          (call/cc
                           (lambda (k)
                             (with-exception-handler
                              (lambda (c) (if (eq? c 'warning) 'resumed (raise c)))
                              (lambda ()
                                (with-transaction db 'deferred
                                  (lambda ()
                                    (when resumed (raise-continuable 'warning))
                                    (execute! db "insert into t values ('inner')")
                                    (set! held (prepare-statement db "select x from t"))
                                    (step! held)
                                    (interrupt! db)
                                    (k 'escaped-and-nothing-raised))))))))))
            (code (extended db))
            (in (if (in-transaction? db) 'yes 'no))
            (count (attempt (lambda () (vector-ref (query-row db2 "select count(*) from t") 0))))
            (own (issued db))
            (reset (no-value (attempt (lambda () (reset! held)))))
            (rolled (no-value (attempt (lambda () (execute! db "rollback")))))
            (after (if (in-transaction? db) 'yes 'no)))
       (finalize-statement! held)
       (list r code in count own reset rolled after)))))

(define escape-failed
  (list '(raised (sqlite-interrupt with-transaction interrupt interrupt)) 9 'yes 3 primed-outer
        'no-value 'no-value 'no))

(test-equal "[E] the sticky interrupt, the body escaping through a continuation, no raise: the rollback fails, at its prepare, and with-transaction raises its &sqlite-interrupt from with-transaction, never leaving silently; the transaction stays open, and db2 counts the base rows"
  escape-failed
  (sticky-escape #f))

(test-equal "[E] the same escape after a raise-continuable whose handler resumed the body: the resumed raise is over, so the rollback's &sqlite-interrupt is raised from with-transaction, the transaction open"
  escape-failed
  (sticky-escape #t))

(test-equal "[E] at capacity 0, where nothing is kept, the sticky interrupt's ROLLBACK fails at its prepare even after an earlier call issued it: the body's condition, the transaction open, and with-transaction keeps none of its statements; a plain rollback once the statement is reset"
  '((raised (value primed)) (raised (value the-body-raised)) 9 yes 0 () no)
  (with-uncached
   (lambda (u db2)
     (let* ((primed (attempt (lambda () (with-transaction u 'deferred (lambda () (raise 'primed))))))
            (held #f)
            (r (attempt (lambda ()
                          (with-transaction u 'deferred
                            (lambda ()
                              (execute! u "insert into t values ('inner')")
                              (set! held (prepare-statement u "select x from src"))
                              (step! held)
                              (interrupt! u)
                              (raise 'the-body-raised))))))
            (code (extended u))
            (in (if (in-transaction? u) 'yes 'no))
            (count (database-cache-count u))
            (own (issued u))
            (reset (reset! held))
            (rolled (execute! u "rollback")))
       (finalize-statement! held)
       (list primed r code in count own (if (in-transaction? u) 'yes 'no))))))

;; --- [F] the refusal ---------------------------------------------------------------------------

;; refusal : (Database -> Any) -> Any
;; SETUP makes the connection's state; then with-transaction, deferred,
;; whose body writes a marker: what it raised or answered, the extended code
;; and in-transaction? straight after, against their values before, and
;; whether the body ran.
(define (refusal setup)
  (with-case
   (lambda (db db2)
     (let* ((s (attempt (lambda () (setup db))))
            (code-before (extended db))
            (in-before (in-transaction? db))
            (ran 'not-run)
            (r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda () (set! ran 'ran) (execute! db "insert into t values ('outer')") 'committed)))))
            (code-after (extended db))
            (in-after (in-transaction? db)))
       (list r ran (if (equal? code-before code-after) 'extended-code-unchanged (list code-before code-after))
             (if (eq? in-before in-after) 'in-transaction-unchanged (list in-before in-after))
             (markers db2))))))

(define (refused state sql)
  (list (list 'raised (list 'assertion-violation 'with-transaction (list 'statement-not-finished state sql)))
        'not-run 'extended-code-unchanged 'in-transaction-unchanged "(none)"))

(define held-statements '())
(define (hold! st) (set! held-statements (cons st held-statements)) st)
(define (release-held!)
  (for-each (lambda (st) (guard (e (#t #f)) (finalize-statement! st))) held-statements)
  (set! held-statements '()))

(define big-text (make-string 100000 #\a))

(test-equal "[F] with-transaction refuses to begin beside a statement of its connection at a row, and beside one failed by a constraint: an assertion violation from with-transaction, statement-not-finished, the state and the statement's own SQL, raised before anything reaches C, the body never run"
  (list (refused 'row "select x from src") (refused 'failed "insert into u values (1)"))
  (let* ((row (refusal (lambda (db)
                         (let ((st (hold! (prepare-statement db "select x from src"))))
                           (step! st)))))
         (failed (refusal (lambda (db)
                            (let ((st (hold! (prepare-statement db "insert into u values (1)"))))
                              (attempt (lambda () (step! st))))))))
    (release-held!)
    (list row failed)))

(test-equal "[F] with-transaction refuses to begin from inside a query-fold's procedure, whose statement is at its row; the fold's own procedure gets the refusal"
  (list '(raised (assertion-violation with-transaction (statement-not-finished row "select x from src"))) 'not-run
        "(none)")
  (with-case
   (lambda (db db2)
     (let* ((ran 'not-run)
            (r (attempt (lambda ()
                          (query-fold db "select x from src"
                                      (lambda (acc row)
                                        (with-transaction db 'deferred (lambda () (set! ran 'ran) 'x)))
                                      0)))))
       (list r ran (markers db2))))))

(test-equal "[F] nested, with-transaction refuses inside a body that holds a statement at a row; the outer level is still there, and rolls back when its body raises the refusal on"
  (list '(raised (assertion-violation with-transaction (statement-not-finished row "select x from src"))) 'not-run
        '(raised (assertion-violation with-transaction (statement-not-finished row "select x from src"))) 'no
        "(none)")
  (with-case
   (lambda (db db2)
     (let* ((ran 'not-run) (inner #f)
            (r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda ()
                              (execute! db "insert into t values ('outer')")
                              (let ((st (hold! (prepare-statement db "select x from src"))))
                                (step! st)
                                (set! inner (attempt (lambda () (with-transaction db (lambda () (set! ran 'ran))))))
                                (with-transaction db (lambda () (set! ran 'ran))))))))))
       (release-held!)
       (list inner ran r (if (in-transaction? db) 'yes 'no) (markers db2))))))

(test-equal "[F] the controls: beside a statement at done, one reset after a row, and none at all, with-transaction begins, runs its body and commits"
  '((committed ran in-transaction-unchanged "outer")
    (committed ran in-transaction-unchanged "outer")
    (committed ran in-transaction-unchanged "outer"))
  (let* ((control (lambda (r)
                    ;; The begin's and the commit's steps change the extended
                    ;; code, which only the refusal leaves alone.
                    (if (and (list? r) (= (length r) 5))
                        (list (car r) (cadr r) (cadddr r) (list-ref r 4))
                        r)))
         (done (control (refusal (lambda (db)
                                   (let ((st (hold! (prepare-statement db "select 1 where 0"))))
                                     (step! st))))))
         (reset (control (refusal (lambda (db)
                                    (let ((st (hold! (prepare-statement db "select x from src"))))
                                      (step! st)
                                      (reset! st))))))
         (none (control (refusal (lambda (db) 'nothing)))))
    (release-held!)
    (list done reset none)))

;; --- [G] a fold inside with-transaction --------------------------------------------------------

(test-equal "[G] with-transaction, immediate, around a query-fold whose procedure inserts through execute!: the write lock is taken before the fold's read, so db2's BEGIN IMMEDIATE at the first row answers busy and db2 holds nothing; each insert succeeds at once, beside the fold's held read; db2 sees none of them until the commit lands, then every one"
  '((10 ((raised (sqlite-busy execute! busy busy)) 0)) 10 no (("BEGIN IMMEDIATE" . ready) ("COMMIT" . ready)))
  (with-case
   (lambda (db db2)
     (let* ((peer #f)
            (r (attempt (lambda ()
                          (with-transaction db 'immediate
                            (lambda ()
                              (let ((n (query-fold db "select rowid from src"
                                                   (lambda (acc row)
                                                     (when (= acc 0)
                                                       (let ((b (attempt (lambda () (execute! db2 "begin immediate")))))
                                                         (set! peer b)))
                                                     (execute! db "insert into b values (?)" (vector-ref row 0))
                                                     (+ acc 1))
                                                   0)))
                                (list n (list peer (vector-ref (query-row db2 "select count(*) from b") 0)))))))))
            (in (if (in-transaction? db) 'yes 'no))
            (seen (attempt (lambda () (vector-ref (query-row db2 "select count(*) from b") 0)))))
       (when (in-transaction? db2) (execute! db2 "rollback"))
       (list r seen in (issued db))))))

(test-equal "a body that closes its connection: returning, with-transaction raises &sqlite-closed from with-transaction, and its rollback's failure, closed too, is not raised over it; raising, the body's condition reaches the caller; nothing committed"
  '((raised (closed with-transaction)) (raised (value closed-and-raised)) "(none)" "(none)")
  (with-case
   (lambda (db db2)
     (let* ((path-db (lambda ()
                       (let ((c (open-database (string-append temp-dir "/case-" (number->string case-number) ".db"))))
                         c)))
            (a (let ((c (path-db)))
                 (attempt (lambda ()
                            (with-transaction c 'deferred
                              (lambda () (execute! c "insert into t values ('returned')") (close-database! c) 'x))))))
            (b (let ((c (path-db)))
                 (attempt (lambda ()
                            (with-transaction c 'deferred
                              (lambda () (execute! c "insert into t values ('raised')") (close-database! c)
                                      (raise 'closed-and-raised))))))))
       (list a b (markers db) (markers db2))))))

;; --- [H] the exits ------------------------------------------------------------------------------

(test-equal "[H] a resumed body's return: the body raises with raise-continuable past a guard whose clauses don't match, under an outer handler that returns 42; the guard's first exit rolls the level back, so the body's later write autocommits; its return raises &sqlite-transaction-ended, caught by the outer handler; db2 sees the later write alone"
  '((caught (transaction-ended with-transaction)) 42 no "after" (("BEGIN DEFERRED" . ready) ("ROLLBACK" . ready)))
  (with-case
   (lambda (db db2)
     (let* ((resumed #f)
            (r (call/cc
                (lambda (k)
                  (with-exception-handler
                   (lambda (c)
                     (if (eq? c 'resume-me)
                         42
                         (k (list 'caught (what-raised c)))))
                   (lambda ()
                     (guard (e ((string? e) 'no-match))
                       (with-transaction db 'deferred
                         (lambda ()
                           (execute! db "insert into t values ('outer')")
                           (let ((v (raise-continuable 'resume-me)))
                             (set! resumed v)
                             (execute! db "insert into t values ('after')")
                             v))))))))))
       (list r resumed (if (in-transaction? db) 'yes 'no) (markers db2) (issued db))))))

(test-equal "[H] a continuation captured in the body, called after the commit: the second return raises &sqlite-transaction-ended; no second COMMIT, the extended code unchanged and the cached COMMIT ready, run once; db2 sees the marker once"
  '((return 1) (raised (transaction-ended with-transaction)) extended-code-unchanged
    (("BEGIN DEFERRED" ready 1) ("COMMIT" ready 1)) "outer")
  (with-case
   (lambda (db db2)
     (let* ((k #f) (returns 0) (code #f) (first #f) (called #f)
            (r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda ()
                              (call/cc (lambda (c) (set! k c)))
                              (set! returns (+ returns 1))
                              (when (= returns 1) (execute! db "insert into t values ('outer')"))
                              (list 'return returns)))))))
       ;; k is called once: were the re-entry refused, the refusal would
       ;; land here again, and the row fails by name.
       (if (and (= returns 1) (not called))
           (begin (set! called #t) (set! code (extended db)) (set! first r) (k 'again))
           (list first r
                 (if (eqv? code (extended db)) 'extended-code-unchanged (list code (extended db)))
                 (issued-runs db) (markers db2)))))))

(test-equal "[H] at a nested level whose outer stays open, a re-entry by a non-matching guard issues no second rollback, and a continuation called after the RELEASE issues no second RELEASE: the extended code and the cached ROLLBACK TO and RELEASE as the first exit left them, ROLLBACK TO run once and RELEASE twice, once for each level, and the outer commits its own marker"
  '((raised (value inner-raised)) extended-code-unchanged
    (raised (transaction-ended with-transaction)) extended-code-unchanged
    outer-returned "again,outer"
    (("BEGIN DEFERRED" ready 1) ("SAVEPOINT chez_sqlite3_1" ready 2) ("ROLLBACK TO chez_sqlite3_1" ready 1)
     ("RELEASE chez_sqlite3_1" ready 2) ("COMMIT" ready 1)))
  (with-case
   (lambda (db db2)
     (let* ((guarded #f) (code1 #f) (continued #f) (code2 #f)
            (r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda ()
                              (execute! db "insert into t values ('outer')")
                              ;; A re-entry: the inner guard doesn't match, the outer one does.
                              (set! guarded
                                    (attempt (lambda ()
                                               (guard (e ((string? e) 'no-match))
                                                 (with-transaction db
                                                   (lambda ()
                                                     (execute! db "insert into t values ('inner')")
                                                     (raise 'inner-raised)))))))
                              (set! code1 (extended db))
                              (let* ((k #f) (n 0) (called #f)
                                     (v (attempt (lambda ()
                                                   (with-transaction db
                                                     (lambda ()
                                                       (call/cc (lambda (c) (set! k c)))
                                                       (set! n (+ n 1))
                                                       (when (= n 1) (execute! db "insert into t values ('again')"))
                                                       n))))))
                                (when (and (= n 1) (not called))
                                  (set! called #t)
                                  (set! code2 (extended db))
                                  (k 'again))
                                (set! continued v))
                              'outer-returned)))))
            (code-now (extended db)))
       (list guarded (if (eqv? code1 0) 'extended-code-unchanged code1)
             continued (if (eqv? code2 code-now) 'extended-code-unchanged (list code2 code-now))
             r (markers db2) (issued-runs db))))))

;; handler-begins : (Database -> Any) -> Any
;; with-transaction, deferred, whose body writes outer and then runs BODY,
;; under a with-exception-handler handler that begins a transaction with
;; execute! and escapes through a continuation taken outside the call. The
;; handler runs before the unwind, inside the call. What escaped; whether
;; the handler's transaction is open after; the extended code; db2's markers;
;; with-transaction's statements.
(define (handler-begins body)
  (with-case
   (lambda (db db2)
     (let* ((r (attempt (lambda ()
                          (call/cc
                           (lambda (k)
                             (with-exception-handler
                              (lambda (c)
                                (execute! db "begin")
                                (k (list 'the-handler-began-and-escaped (what-raised c))))
                              (lambda ()
                                (with-transaction db 'deferred
                                  (lambda ()
                                    (execute! db "insert into t values ('outer')")
                                    (body db))))))))))
            (in (if (in-transaction? db) 'yes 'no))
            (code (extended db))
            (own (issued db))
            (theirs (markers db2)))
       (when (in-transaction? db) (execute! db "rollback"))
       (list r in code theirs own)))))

(test-equal "[H] a handler before the unwind is part of the body: E4 ends the transaction and is raised past the body; a with-exception-handler handler begins a transaction and escapes; the escape's exit reads autocommit 0 and rolls that transaction back, since autocommit can't tell transactions apart"
  '((the-handler-began-and-escaped (sqlite-constraint execute! constraint constraint-unique)) no 0 "(none)"
    (("BEGIN DEFERRED" . ready) ("ROLLBACK" . ready)))
  (handler-begins (lambda (db) (execute! db "insert or rollback into u values (1)"))))

(test-equal "[H] once with-transaction has ended its level itself, a handler's transaction stands: L1's return raises &sqlite-transaction-ended, which a with-exception-handler handler catches before the unwind, begins a transaction and escapes; the escape issues nothing, and the handler's transaction stays open"
  '((the-handler-began-and-escaped (transaction-ended with-transaction)) yes 0 "(none)"
    (("BEGIN DEFERRED" . ready)))
  (handler-begins (lambda (db)
                    (attempt (lambda () (execute! db "insert or rollback into u values (1)")))
                    'returned)))

;; --- the plants (the M3 plan, section 4.8) ---------------------------------------------------------

;; primed-case : (Database Database -> Any) -> Any
;; with-case, its cache holding with-transaction's statements from earlier
;; calls at both levels, each rolled back once and committed once.
(define (primed-case proc)
  (with-case
   (lambda (db db2)
     (attempt (lambda ()
                (with-transaction db 'deferred
                  (lambda ()
                    (attempt (lambda () (with-transaction db (lambda () (execute! db "insert into b values (1)") (raise 'primed)))))
                    (with-transaction db (lambda () 'primed))
                    (raise 'primed)))))
     (with-transaction db 'deferred (lambda () 'primed))
     (proc db db2))))

(define primed-statements
  '(("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready) ("ROLLBACK TO chez_sqlite3_1" . ready)
    ("RELEASE chez_sqlite3_1" . ready) ("ROLLBACK" . ready) ("COMMIT" . ready)))

(test-equal "[pE4] E4 under a cache that holds ROLLBACK and ROLLBACK TO from earlier calls: with-transaction reads autocommit and issues nothing, so the extended code after its raise is the insert's 2067, and the cached ROLLBACK, and ROLLBACK TO, are still tracked and ready; a mutant that rolls back unread answers 1 and finalizes them"
  (list (list '(raised (sqlite-constraint execute! constraint constraint-unique)) 2067 primed-statements)
        (list '(raised (transaction-ended with-transaction)) 2067 primed-statements))
  (let* ((outer (primed-case
                 (lambda (db db2)
                   (let* ((r (attempt (lambda ()
                                        (with-transaction db 'deferred
                                          (lambda ()
                                            (execute! db "insert into t values ('outer')")
                                            (execute! db "insert or rollback into u values (1)"))))))
                          (code (extended db)))
                     (list r code (issued db))))))
         (nested (primed-case
                  (lambda (db db2)
                    (let* ((r (attempt (lambda ()
                                         (with-transaction db 'deferred
                                           (lambda ()
                                             (execute! db "insert into t values ('outer')")
                                             (attempt (lambda ()
                                                        (with-transaction db
                                                          (lambda () (execute! db "insert or rollback into u values (1)")))))
                                             'outer-returned)))))
                           (code (extended db)))
                      (list r code (issued db)))))))
    (list outer nested)))

(test-equal "[pH1] under a guard whose clauses don't match, inside one that catches everything, the outer guard catches the body's own condition, at both levels: with-transaction's before thunks let the re-entry through"
  '((caught the-body-condition) (caught the-body-condition))
  (with-case
   (lambda (db db2)
     (let* ((catch (lambda (thunk)
                     (guard (e (#t (list 'caught (if (symbol? e) e (what-raised e)))))
                       (guard (e ((string? e) 'no-match))
                         (thunk)))))
            (outer (catch (lambda () (with-transaction db 'deferred (lambda () (raise 'the-body-condition))))))
            (nested (attempt (lambda ()
                               (with-transaction db 'deferred
                                 (lambda ()
                                   (catch (lambda () (with-transaction db (lambda () (raise 'the-body-condition)))))))))))
       (list outer nested)))))

(test-equal "[p2n] a nested level re-entered by a non-matching guard acts once: the extended code stays the rollback's, and the cached ROLLBACK TO is still tracked and ready, run once by this call after the cache's earlier one; a mutant whose after thunk acts twice issues a second ROLLBACK TO, which answers 1, no such savepoint, and is finalized"
  '((raised (value the-body-condition)) 0
    (("BEGIN DEFERRED" ready 3) ("SAVEPOINT chez_sqlite3_1" ready 3) ("ROLLBACK TO chez_sqlite3_1" ready 2)
     ("RELEASE chez_sqlite3_1" ready 3) ("ROLLBACK" ready 1) ("COMMIT" ready 2))
    yes)
  (primed-case
   (lambda (db db2)
     (let* ((r #f) (code #f) (in #f)
            (outer (attempt (lambda ()
                              (with-transaction db 'deferred
                                (lambda ()
                                  (execute! db "insert into t values ('outer')")
                                  (set! r (attempt (lambda ()
                                                     (guard (e ((string? e) 'no-match))
                                                       (with-transaction db
                                                         (lambda ()
                                                           (execute! db "insert into t values ('inner')")
                                                           (raise 'the-body-condition)))))))
                                  (set! code (extended db))
                                  (set! in (if (in-transaction? db) 'yes 'no))
                                  'outer-returned)))))
            (own (issued-runs db)))
       (list r code own in)))))

(test-equal "[p2g] a guard clause's test that begins a transaction between with-transaction's two exits keeps it: the second exit issues nothing, and in-transaction? is #t; a mutant whose after thunk acts twice rolls the guard's transaction back"
  '((raised (value the-body-condition)) yes no)
  (with-case
   (lambda (db db2)
     (let* ((r (attempt (lambda ()
                          (guard (e ((begin (execute! db "begin") #f) 'no-match))
                            (with-transaction db 'deferred
                              (lambda ()
                                (execute! db "insert into t values ('outer')")
                                (raise 'the-body-condition)))))))
            (in (if (in-transaction? db) 'yes 'no))
            (c (attempt (lambda () (execute! db "rollback")))))
       (list r in (if (in-transaction? db) 'yes 'no))))))

(test-equal "[pLE] a later exit is decided by the flags, never by autocommit. A resumed body's return, past a guard whose clause's test begins the caller's own transaction once: &sqlite-transaction-ended, the caller's transaction still open. A continuation's return after the commit, the caller's transaction begun meanwhile: the same. Nested, a continuation's return after the RELEASE, the outer still open: the same, the extended code the RELEASE's, the cached RELEASE ready, and the outer commits its marker. A mutant that decides by autocommit commits the caller's transaction, or steps RELEASE on the released savepoint, which answers 1"
  '(((caught (transaction-ended with-transaction)) yes)
    ((return 1) (raised (transaction-ended with-transaction)) yes)
    (((raised (transaction-ended with-transaction)) 0) "outer"
     (("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready) ("RELEASE chez_sqlite3_1" . ready)
      ("COMMIT" . ready))))
  (let* ((resumed
          (with-case
           (lambda (db db2)
             (let* ((began #f)
                    (r (call/cc
                        (lambda (k)
                          (with-exception-handler
                           (lambda (c) (if (eq? c 'resume-me) 42 (k (list 'caught (what-raised c)))))
                           (lambda ()
                             (guard (e ((begin (unless began (set! began #t) (execute! db "begin")) #f) 'no-match))
                               (with-transaction db 'deferred (lambda () (raise-continuable 'resume-me)))))))))
                    (in (if (in-transaction? db) 'yes 'no)))
               (execute! db "rollback")
               (list r in)))))
         (continued
          (with-case
           (lambda (db db2)
             (let* ((k #f) (returns 0) (first #f) (called #f)
                    (r (attempt (lambda ()
                                  (with-transaction db 'deferred
                                    (lambda ()
                                      (call/cc (lambda (c) (set! k c)))
                                      (set! returns (+ returns 1))
                                      (list 'return returns)))))))
               (if (and (= returns 1) (not called))
                   (begin (set! called #t) (set! first r) (execute! db "begin") (k 'again))
                   (let ((in (if (in-transaction? db) 'yes 'no)))
                     (execute! db "rollback")
                     (list first r in)))))))
         (nested
          (with-case
           (lambda (db db2)
             (let ((r (attempt (lambda ()
                                 (with-transaction db 'deferred
                                   (lambda ()
                                     (execute! db "insert into t values ('outer')")
                                     (let* ((k #f) (n 0) (called #f)
                                            (inner (attempt (lambda ()
                                                              (with-transaction db
                                                                (lambda ()
                                                                  (call/cc (lambda (c) (set! k c)))
                                                                  (set! n (+ n 1))
                                                                  n))))))
                                       (when (and (= n 1) (not called)) (set! called #t) (k 'again))
                                       (list inner (extended db)))))))))
               (list r (markers db2) (issued db)))))))
    (list resumed continued nested)))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "transaction")

(exit (suite-exit-status runner))
