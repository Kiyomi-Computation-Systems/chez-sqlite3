#!r6rs
;;; The close's order: sqlite3_close first, sqlite3_next_stmt counted only
;;; when it fails (ADR-0012). close-database! finalizes the
;;; statements it tracks and empties its cache, then calls sqlite3_close:
;;; SQLITE_OK gives the close's outcomes as before; any other answer leaves
;;; the connection open and counted, and only then are the statements left
;;; on it counted, an assertion violation naming the count when there are
;;; some, the close's own &sqlite-error when there are none.
;;;
;;; Why the order matters. A virtual table's module prepares statements of
;;; its own on the connection, for its shadow tables, and finalizes them only
;;; when the table is disconnected. sqlite3_close disconnects every virtual
;;; table, and rolls back each one in a transaction, before it checks for
;;; statements (SQLite's sqlite3Close: "the v-table implementation may be
;;; storing some prepared statements internally"). Counted before the close,
;;; they were refused as untracked: an FTS5 table, made and nothing more,
;;; left 2 (3 at 3.45.1); an RTREE table 8; FTS3 and FTS4 left theirs once
;;; queried, 10 for FTS4 after an insert and a search, which FTS5's left 7.
;;;
;;;   the modules    each module's rows chosen by what the library reports:
;;;                  fts5 by sqlite-compile-option? "ENABLE_FTS5", fts4 by
;;;                  "ENABLE_FTS3", which "ENABLE_FTS4" implies and which
;;;                  registers both fts3 and fts4, rtree by "ENABLE_RTREE",
;;;                  each held to pragma_module_list by a row of its own.
;;;                  Where the library lacks a module, the suite prints that
;;;                  its rows are unavailable and asserts the refusal in their
;;;                  place: the create prepares, so its SQL is well formed,
;;;                  then its step raises &sqlite-error, code error, and no
;;;                  table is made. So the suite runs on every lane
;;;   closing        a :memory: connection that made a table, and one that
;;;                  also wrote and searched it, close, every count back to
;;;                  0; a file's table made, closed, reopened and searched,
;;;                  closes and keeps its rows; call-with-database's close
;;;   left open      an untracked statement, made here with a raw
;;;                  sqlite3_prepare_v2, still raises untracked-statements
;;;                  N, now after sqlite3_close answered SQLITE_BUSY: the
;;;                  connection's extended code reads busy after the
;;;                  refusal, where it read error, from a failed prepare,
;;;                  before it. The connection stays open and counted, the
;;;                  latch interruptible again, and once the statement is
;;;                  finalized a second close closes. Beside an FTS5 table,
;;;                  the count is the raw statement's alone. A backup, alone
;;;                  and beside an FTS5 table: SQLite's own refusal, with
;;;                  nothing counted, &sqlite-error busy, its message the
;;;                  connection's own, sqlite3_errmsg's after the refusal.
;;;                  The library binds no backup, so this is the one way to a
;;;                  failing sqlite3_close with nothing left to count:
;;;                  SQLite refuses a close only for a statement or a backup
;;;                  (sqlite3Close's connectionIsBusy)
;;;   a transaction  what a close that sqlite3_close refuses does to an open
;;;                  transaction that wrote a plain table and an FTS5 table:
;;;                  the transaction stays open, the plain table's write and
;;;                  the FTS5 table's content stay, but the module's own
;;;                  rollback discards its index's pending terms, so a search
;;;                  no longer finds the row. A commit after it writes an
;;;                  index that the module's integrity check calls corrupt,
;;;                  corrupt-vtab; a rollback after it leaves both tables as
;;;                  they were (measured on 3.53.1, 3.54.1 and 3.45.1,
;;;                  failed-close-txn.sps). After a refusal a backup made, the
;;;                  FTS5 table takes writes again, in and out of a
;;;                  transaction, intact, and the file reopened keeps them
;;;   the boundary   the close vouches only for what chez-sqlite3 tracks
;;;                  A refusal means work something else left open, from a
;;;                  defect or foreign code; what SQLite's close does to that
;;;                  work is SQLite's. These rows hold it as measured, so a
;;;                  change in SQLite shows, and endorse none of it: an
;;;                  untracked INSERT ... RETURNING into FTS5, stepped once
;;;                  in autocommit, commits its row without its index terms
;;;                  once finalized, an index its integrity check calls
;;;                  corrupt; an untracked SELECT held at its row is refused
;;;                  the same way, with no module and over FTS5. Each refusal
;;;                  names every statement left, as this suite counts them
;;;                  after it, a module's among them while the leftover
;;;                  statement holds its table
;;;
;;; The latch's probe is tests/test-interrupt-database.sps's: an interrupt
;;; that reaches sqlite3_interrupt while no statement runs leaves
;;; sqlite3_is_interrupted reading 1 until the next statement starts, so a
;;; row reads clear, calls interrupt-database!, and reads set when the verb
;;; reached SQLite. This suite binds sqlite3_is_interrupted,
;;; sqlite3_extended_errcode, sqlite3_errmsg, sqlite3_prepare_v2,
;;; sqlite3_step, sqlite3_finalize, sqlite3_next_stmt and the backup's two
;;; calls itself, after the load.
;;;
;;; The loading procedures are reached through eval, under a guard, so a
;;; refused library fails the rows by name. Every computation that can raise
;;; runs under a guard with a sentinel of its own; no expected value is #f.
;;; Effects run in order, through let* and named lets, never map. Every row
;;; that leaves a connection, a statement or a backup open on purpose undoes
;;; it under dynamic-wind, a virtual table dropped first when its close was
;;; refused (ADR-0005).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-error-message sqlite-closed? sqlite-wrong-thread?))

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

(define (public name) (reach '(chez-sqlite3) name))

(define open-database (public 'open-database))
(define close-database! (public 'close-database!))
(define call-with-database (public 'call-with-database))
(define execute! (public 'execute!))
(define query (public 'query))
(define query-row (public 'query-row))
(define prepare-statement (public 'prepare-statement))
(define step! (public 'step!))
(define finalize-statement! (public 'finalize-statement!))
(define statement? (public 'statement?))
(define with-transaction (public 'with-transaction))
(define in-transaction? (public 'in-transaction?))
(define interrupt-database! (public 'interrupt-database!))
(define sqlite-compile-option? (public 'sqlite-compile-option?))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-out-pointer (reach '(chez-sqlite3 private native) 'call-with-out-pointer))
(define c-string->string (reach '(chez-sqlite3 private native) 'c-string->string))

;; --- bindings made here, after the load ------------------------------------------------
;; foreign-procedure resolves its entry when it is evaluated, so each is made
;; once the load above has run; one that cannot be made raises when called.

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_prepare_v2(sqlite3*, const char *zSql, int nByte, sqlite3_stmt **, const char **pzTail)
(define prepare-v2 (bound 'sqlite3_prepare_v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int)))
;; int sqlite3_finalize(sqlite3_stmt*)
(define finalize (bound 'sqlite3_finalize (foreign-procedure "sqlite3_finalize" (uptr) int)))
;; int sqlite3_step(sqlite3_stmt*)
(define raw-step (bound 'sqlite3_step (foreign-procedure "sqlite3_step" (uptr) int)))
;; sqlite3_stmt *sqlite3_next_stmt(sqlite3 *pDb, sqlite3_stmt *pStmt)
(define next-stmt (bound 'sqlite3_next_stmt (foreign-procedure "sqlite3_next_stmt" (uptr uptr) uptr)))
;; int sqlite3_extended_errcode(sqlite3*)
(define extended-errcode (bound 'sqlite3_extended_errcode (foreign-procedure "sqlite3_extended_errcode" (uptr) int)))
;; int sqlite3_is_interrupted(sqlite3*), from 3.41.0, so at the floor
(define is-interrupted (bound 'sqlite3_is_interrupted (foreign-procedure "sqlite3_is_interrupted" (uptr) int)))
;; sqlite3_backup *sqlite3_backup_init(sqlite3 *pDest, const char *zDestName,
;;                                     sqlite3 *pSource, const char *zSourceName)
(define backup-init (bound 'sqlite3_backup_init (foreign-procedure "sqlite3_backup_init" (uptr uptr uptr uptr) uptr)))
;; int sqlite3_backup_finish(sqlite3_backup*)
(define backup-finish (bound 'sqlite3_backup_finish (foreign-procedure "sqlite3_backup_finish" (uptr) int)))
;; const char *sqlite3_errmsg(sqlite3*)
(define errmsg (bound 'sqlite3_errmsg (foreign-procedure "sqlite3_errmsg" (uptr) uptr)))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

;; counts-with : (Listof (Pairof Symbol Integer)) -> (Listof (Pairof Symbol Integer))
(define (counts-with changes)
  (map (lambda (entry) (cond ((assq (car entry) changes) => (lambda (c) c)) (else entry)))
       zero-counts))

(define while-open (counts-with '((connection . 1))))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
;; E as the rows compare it: an assertion violation by its who and
;; irritants; an &sqlite-error by its who and codes; &sqlite-closed and
;; &sqlite-wrong-thread by their who.
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((sqlite-wrong-thread? e) (list 'wrong-thread (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

;; attempt : (-> Any) -> Any
;; THUNK's answer, or (raised WHAT) for what it raised.
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

;; raised-tag : a pair no answer is: a caught raise, (raised-tag . E).
(define raised-tag (list 'raised))

;; done : (-> Any) -> Any
;; THUNK run for its effect, by attempt: done, or (raised WHAT).
(define (done thunk) (attempt (lambda () (thunk) 'done)))

;; closed : Any -> Any
;; close-database! on DB, by attempt: closed, or (raised WHAT).
(define (closed db) (attempt (lambda () (close-database! db) 'closed)))

;; with-handle : Database (Positive-Integer -> A) -> A
(define (with-handle db proc) (call-with-open-handle 'test-connection-close db proc))

;; still-open : Database -> Any
;; open when DB's handle can be had; else what refused it.
(define (still-open db) (attempt (lambda () (with-handle db (lambda (h) 'open)))))

;; extended-code : Database -> Any
;; sqlite3_extended_errcode on DB's handle, by attempt: busy for 5, error
;; for 1, else the number.
(define (extended-code db)
  (attempt
   (lambda ()
     (let ((n (with-handle db extended-errcode)))
       (cond ((eqv? n 5) 'busy) ((eqv? n 1) 'error) (else n))))))

;; flag : Database -> Any
;; sqlite3_is_interrupted on DB, by attempt: set for 1, clear for 0.
(define (flag db)
  (attempt
   (lambda ()
     (let ((n (with-handle db is-interrupted)))
       (cond ((eqv? n 1) 'set) ((eqv? n 0) 'clear) (else (list 'neither n)))))))

;; latch : Database -> (List Any Any Any)
;; The probe read, interrupt-database! called, the probe read again: (clear
;; void set) when the verb reached SQLite, so the latch is interruptible.
(define (latch db)
  (let* ((before (flag db))
         (verb (let ((r (attempt (lambda () (interrupt-database! db)))))
                 (if (eq? r (if #f #f)) 'void (list 'answered r))))
         (after (flag db)))
    (list before verb after)))

;; prepare! : Database String -> Positive-Integer
;; A statement of SQL on DB, made here with the raw sqlite3_prepare_v2, so the
;; connection does not track it.
(define (prepare! db sql)
  (with-handle db
    (lambda (h)
      (call-with-c-string 'test-connection-close sql
        (lambda (text)
          (let-values (((rc statement)
                        (call-with-out-pointer 'test-connection-close
                          (lambda (slot) (prepare-v2 h text -1 slot 0)))))
            (if (and (eqv? rc 0) (not (eqv? statement 0)))
                statement
                (error 'prepare! "sqlite3_prepare_v2 did not answer a statement" rc))))))))

;; undo! : (Listof Positive-Integer) (Listof Any) -> Void
;; What a row left open on purpose, undone however it ends: STATEMENTS
;; finalized, then each of DATABASES closed; one whose close is refused,
;; as a virtual table's own statements made code that counted before the
;; close refuse it, has its table v dropped, then is closed. Nothing here
;; raises.
(define (undo! statements databases)
  (for-each (lambda (s) (guard (e (#t #f)) (finalize s))) statements)
  (for-each (lambda (db)
              (guard (e (#t #f))
                (unless (eq? (closed db) 'closed)
                  (guard (e (#t #f)) (execute! db "drop table v"))
                  (close-database! db))))
            databases))

;; with-undo : ((Database -> Database) (Integer -> Integer) (Integer -> Integer) -> A) -> Any
;; PROC's answer by attempt, given DB!, which notes a database it opened,
;; ST!, which notes a raw statement it made, and FIN!, which finalizes a
;; noted statement and answers sqlite3_finalize's code: whatever is still
;; noted is undone by undo! however PROC ends.
(define (with-undo proc)
  (let ((dbs '()) (sts '()))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (proc (lambda (db) (set! dbs (cons db dbs)) db)
                 (lambda (st) (set! sts (cons st sts)) st)
                 (lambda (st) (set! sts (remv st sts)) (finalize st))))))
      (lambda () (undo! sts dbs)))))

(define temp-dir (guard (e (#t #f)) (make-process-temp-directory)))
(define case-number 0)
;; fresh-path : -> String
(define (fresh-path)
  (set! case-number (+ case-number 1))
  (string-append (or temp-dir "/nonexistent") "/case-" (number->string case-number) ".db"))

;; --- the modules --------------------------------------------------------------------------

;; A module: its name, the compile option that brings it, its create, its
;; insert, its search and its plain read, and what the two read once the
;; insert has run.
(define-record-type vtab
  (fields name option create insert search read searched rows))

(define fts5
  (make-vtab 'fts5 "ENABLE_FTS5"
               "create virtual table v using fts5(body)"
               "insert into v(body) values ('hello world')"
               "select count(*) from v where v match 'hello'"
               "select body from v"
               '#(1) '(#("hello world"))))

(define fts4
  (make-vtab 'fts4 "ENABLE_FTS3"
               "create virtual table v using fts4(body)"
               "insert into v(body) values ('hello world')"
               "select count(*) from v where v match 'hello'"
               "select body from v"
               '#(1) '(#("hello world"))))

(define rtree
  (make-vtab 'rtree "ENABLE_RTREE"
               "create virtual table v using rtree(id, x0, x1)"
               "insert into v values (1, 0.0, 1.0)"
               "select count(*) from v where x0 >= 0.0 and x1 <= 1.0"
               "select id, x0, x1 from v"
               '#(1) '(#(1 0.0 1.0))))

;; option-and-listing : Vtab -> (List Any Any)
;; What the library reports of M: sqlite-compile-option? of its option, and
;; how many rows of pragma_module_list name it, each by attempt.
(define (option-and-listing m)
  (let* ((option (attempt (lambda () (if (sqlite-compile-option? (vtab-option m)) 'option 'no-option))))
         (listed (attempt
                  (lambda ()
                    (let ((db (open-database ":memory:")))
                      (dynamic-wind
                        (lambda () #f)
                        (lambda ()
                          (vector-ref (query-row db "select count(*) from pragma_module_list where name = ?"
                                                 (symbol->string (vtab-name m)))
                                      0))
                        (lambda () (guard (e (#t #f)) (close-database! db)))))))))
    (list option listed)))

(define modules (list fts5 fts4 rtree))

;; reports : (Listof (Pairof Symbol (List Any Any)))
;; Each module's option-and-listing, read once, in order.
(define reports
  (let loop ((rest modules) (found '()))
    (if (null? rest)
        (reverse found)
        (loop (cdr rest) (cons (cons (vtab-name (car rest)) (option-and-listing (car rest))) found)))))

;; available? : Vtab -> Boolean
;; Whether the library reports M both ways: its option, and one listing.
(define (available? m)
  (equal? (cdr (assq (vtab-name m) reports)) '(option 1)))

;; unavailable-refusal : Vtab -> Any
;; Where the library lacks M: its create on a :memory: connection,
;; prepared, which succeeds, so the SQL is well formed; then stepped, which
;; raises &sqlite-error, code error, as SQLite refuses a module it lacks
;; only once the create runs; then finalized, and no table v in the schema;
;; then the connection's close, and the counts, each by attempt.
(define (unavailable-refusal m)
  (with-undo
   (lambda (db! st! fin!)
     (let* ((db (db! (open-database ":memory:")))
            (st (attempt (lambda () (prepare-statement db (vtab-create m)))))
            (prepared (if (guard (e (#t #f)) (statement? st)) 'prepared st))
            (stepped (if (eq? prepared 'prepared) (attempt (lambda () (step! st))) 'not-prepared))
            (finalized (if (eq? prepared 'prepared) (done (lambda () (finalize-statement! st))) 'not-prepared))
            (made (attempt (lambda () (query-row db "select count(*) from sqlite_schema where name = 'v'")))))
       (list prepared stepped finalized made (closed db) (native-counts))))))

(define refused-at-step
  (list 'prepared '(raised (sqlite-error step! error error)) 'done '#(0) 'closed zero-counts))

;; per-module : Vtab String Any (-> Any) -> Void
;; One row for M: where the library has it, THUNK's answer against
;; EXPECTED; where it lacks it, the rows are named unavailable, and the
;; refusal at the create's step asserted in their place.
(define (per-module m name expected thunk)
  (if (available? m)
      (test-equal name expected (thunk))
      (begin
        (display "  ")
        (display (vtab-name m))
        (display " unavailable: the library lacks it; the refusal at its create's step is asserted in place of: ")
        (display name)
        (newline)
        (test-equal (string-append (symbol->string (vtab-name m))
                                   " unavailable: its create prepares, then raises &sqlite-error, code error, at its step, and makes no table; the connection closes")
          refused-at-step
          (unavailable-refusal m)))))

(test-begin "connection-close")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-assert "a temporary directory for the suite's databases"
  (string? temp-dir))

(test-equal "each module's compile option agrees with pragma_module_list: fts5 by ENABLE_FTS5, fts4 by ENABLE_FTS3, which ENABLE_FTS4 implies, rtree by ENABLE_RTREE; both say yes, or both say no"
  '(agree agree agree)
  (let loop ((rest modules) (found '()))
    (if (null? rest)
        (reverse found)
        (let* ((m (car rest))
               (r (cdr (assq (vtab-name m) reports))))
          (display "  ")
          (display (vtab-name m))
          (display (cond ((equal? r '(option 1)) ": available, its rows run")
                         ((equal? r '(no-option 0)) ": unavailable, its refusal is asserted in its rows' place")
                         (else ": the option and pragma_module_list disagree")))
          (newline)
          (loop (cdr rest)
                (cons (if (or (equal? r '(option 1)) (equal? r '(no-option 0)))
                          'agree
                          (list 'disagree (vtab-name m) r))
                      found))))))

;; --- closing --------------------------------------------------------------------------------

;; in-memory : Vtab -> Any
;; A :memory: connection that makes M's table, then closes; another that
;; makes it, inserts and searches, then closes: each close's answer and the
;; counts after it.
(define (in-memory m)
  (let* ((made (with-undo
                (lambda (db! st! fin!)
                  (let ((db (db! (open-database ":memory:"))))
                    (execute! db (vtab-create m))
                    (let* ((c (closed db))
                           (counts (native-counts)))
                      (list c counts))))))
         (searched (with-undo
                    (lambda (db! st! fin!)
                      (let ((db (db! (open-database ":memory:"))))
                        (execute! db (vtab-create m))
                        (execute! db (vtab-insert m))
                        (let* ((found (query-row db (vtab-search m)))
                               (c (closed db))
                               (counts (native-counts)))
                          (list found c counts)))))))
    (list made searched)))

(define (in-memory-expected m)
  (list (list 'closed zero-counts) (list (vtab-searched m) 'closed zero-counts)))

(for-each
 (lambda (m)
   (per-module m
     (string-append "a :memory: connection that made a " (symbol->string (vtab-name m))
                    " table closes, every count back to 0; so does one that also wrote and searched it")
     (in-memory-expected m)
     (lambda () (in-memory m))))
 modules)

;; on-file : Vtab -> Any
;; A file's M table made and written, then closed; the file reopened, its
;; table searched and read, then closed: each close's answer, what the
;; reopened connection read, and the counts after.
(define (on-file m)
  (let ((path (fresh-path)))
    (with-undo
     (lambda (db! st! fin!)
       (let* ((first (db! (open-database path)))
              (made (begin (execute! first (vtab-create m))
                           (execute! first (vtab-insert m))
                           (closed first)))
              (second (db! (open-database path)))
              (found (attempt (lambda () (query-row second (vtab-search m)))))
              (rows (attempt (lambda () (query second (vtab-read m)))))
              (again (closed second)))
         (list made found rows again (native-counts)))))))

(define (on-file-expected m)
  (list 'closed (vtab-searched m) (vtab-rows m) 'closed zero-counts))

(for-each
 (lambda (m)
   (per-module m
     (string-append "a file whose " (symbol->string (vtab-name m))
                    " table was made and written closes; reopened and searched, it keeps its rows, and closes again, every count back to 0")
     (on-file-expected m)
     (lambda () (on-file m))))
 modules)

(per-module fts5
  "call-with-database: a procedure that makes, writes and searches an fts5 table gives its answer, and the close closes, every count back to 0"
  (list '#(1) zero-counts)
  (lambda ()
    (let ((r (attempt (lambda ()
                        (call-with-database ":memory:"
                          (lambda (db)
                            (execute! db (vtab-create fts5))
                            (execute! db (vtab-insert fts5))
                            (query-row db (vtab-search fts5))))))))
      (list r (native-counts)))))

;; --- left open ------------------------------------------------------------------------------

(test-equal "an untracked statement: sqlite3_close runs first and answers busy, then the count is named: close-database! raises untracked-statements 1, and the extended code, error from a failed prepare before, reads busy; the connection stays open and counted, the latch interruptible again: the probe reads clear, the verb answers void, then set; once the statement is finalized a second close closes, every count back to 0"
  (list '(raised (sqlite-error execute! error error)) 'error
        '(raised (assertion-violation close-database! (untracked-statements 1)))
        'busy while-open 'open '(clear void set) 0 'closed zero-counts)
  (with-undo
   (lambda (db! st! fin!)
     (let* ((db (db! (open-database ":memory:")))
            (raw (st! (prepare! db "select 1")))
            (failed (done (lambda () (execute! db "select * from no_such_table"))))
            (before (extended-code db))
            (refused (closed db))
            (after (extended-code db))
            (counts (native-counts))
            (open (still-open db))
            (latched (latch db))
            (code (fin! raw))
            (again (closed db)))
       (list failed before refused after counts open latched code again (native-counts))))))

(per-module fts5
  "an untracked statement beside an fts5 table: sqlite3_close disconnects the table, finalizing fts5's own statements, then answers busy, so the count named is the raw statement's alone, 1; the extended code reads busy; the connection stays open and counted, the latch interruptible again; once the statement is finalized the connection closes, every count back to 0"
  (list '(raised (assertion-violation close-database! (untracked-statements 1)))
        'busy while-open '(clear void set) 0 'closed zero-counts)
  (lambda ()
    (with-undo
     (lambda (db! st! fin!)
       (let* ((db (db! (open-database ":memory:")))
              (made (begin (execute! db (vtab-create fts5))
                           (execute! db (vtab-insert fts5))
                           (query-row db (vtab-search fts5))))
              (raw (st! (prepare! db "select 1")))
              (refused (closed db))
              (after (extended-code db))
              (counts (native-counts))
              (latched (latch db))
              (code (fin! raw))
              (again (closed db)))
         (list refused after counts latched code again (native-counts)))))))

;; A backup reading from a connection makes sqlite3_close answer SQLITE_BUSY
;; with no statement open (tests/test-connection.sps): SQLite's own refusal,
;; with nothing left to count, so sqlite3_close's failure is the one raised.

;; message-of-the-connection : Database Any -> Any
;; Whether E, an &sqlite-error, carries DB's own message, sqlite3_errmsg's
;; read after it, never its text: message-is-errmsg or message-differs.
(define (message-of-the-connection db e)
  (attempt
   (lambda ()
     (let ((m (with-handle db (lambda (h) (c-string->string (errmsg h))))))
       (if (and (sqlite-error? e) (equal? (sqlite-error-message e) m))
           'message-is-errmsg
           'message-differs)))))

;; backup-close : Boolean -> Any
;; A :memory: source, with an fts5 table made, written and searched when
;; WITH-V, read by a backup into a :memory: target; the source's close,
;; refused; then what it raised, whether its message is the connection's,
;; the extended code, the counts and the latch; then the backup finished,
;; and both connections closed.
(define (backup-close with-v)
  (with-undo
   (lambda (db! st! fin!)
     (let* ((source (db! (open-database ":memory:")))
            (target (db! (open-database ":memory:")))
            (backup #f))
       ;; The backup is finished, however the row ends, before with-undo
       ;; closes the two connections, which it would keep open.
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (let* ((made (begin
                          (when with-v
                            (execute! source (vtab-create fts5))
                            (execute! source (vtab-insert fts5))
                            (query-row source (vtab-search fts5)))
                          (set! backup
                                (with-handle target
                                  (lambda (t)
                                    (with-handle source
                                      (lambda (s)
                                        (call-with-c-string 'test-connection-close "main"
                                          (lambda (main) (backup-init t main s main))))))))
                          (if (eqv? backup 0) 'no-backup 'backup)))
                  (raised (guard (e (#t (cons raised-tag e))) (close-database! source) 'closed))
                  (refused (if (and (pair? raised) (eq? (car raised) raised-tag))
                               (list 'raised (what-raised (cdr raised)))
                               raised))
                  (message (if (pair? raised) (message-of-the-connection source (cdr raised)) 'no-raise))
                  (after (extended-code source))
                  (counts (native-counts))
                  (latched (latch source))
                  (finished (let ((code (backup-finish backup))) (set! backup #f) code))
                  (a (closed source))
                  (b (closed target)))
             (list made refused message after counts latched finished a b (native-counts))))
         (lambda ()
           (when (and backup (not (eqv? backup 0))) (guard (e (#t #f)) (backup-finish backup)))))))))

(define refused-busy
  (list 'backup '(raised (sqlite-error close-database! busy busy)) 'message-is-errmsg 'busy
        (counts-with '((connection . 2))) '(clear void set) 0 'closed 'closed zero-counts))

(test-equal "a backup reading from a connection: sqlite3_close refuses, busy, and with no statement left to count, close-database! raises its &sqlite-error, busy and busy, its message the connection's own, sqlite3_errmsg's after the refusal; the extended code reads busy; the connection stays open and counted, the latch interruptible again; once the backup is finished both connections close"
  refused-busy
  (backup-close #f))

(per-module fts5
  "a backup reading from a connection with an fts5 table: sqlite3_close finalizes fts5's statements, then refuses, busy, for the backup, and close-database! raises its &sqlite-error, busy and busy, nothing counted untracked, its message the connection's own; the connection stays open and counted, the latch interruptible again; once the backup is finished both connections close"
  refused-busy
  (lambda () (backup-close #t)))

;; --- a transaction --------------------------------------------------------------------------

;; views : Database Boolean -> (Listof Any)
;; What DB reads: t's rows, and, WITH-V, v's rows read plainly and through
;; its search, each count by attempt.
(define (views db with-v)
  (let* ((count (lambda (sql) (attempt (lambda () (vector-ref (query-row db sql) 0)))))
         (t (count "select count(*) from t")))
    (if with-v
        (let* ((v (count "select count(*) from v"))
               (found (count "select count(*) from v where v match 'hello'")))
          (list t v found))
        (list t))))

;; integrity : Database -> Any
;; fts5's own integrity check of v, by attempt: intact when it passes.
(define (integrity db)
  (attempt (lambda () (execute! db "insert into v(v) values ('integrity-check')") 'intact)))

(define (transaction-state with-v end)
  (let ((path (fresh-path)))
    (with-undo
     (lambda (db! st! fin!)
       (let* ((db (db! (open-database path)))
              (made (begin (execute! db "create table t(x)")
                           (when with-v (execute! db (vtab-create fts5)))
                           (execute! db "begin")
                           (execute! db "insert into t values (1)")
                           (when with-v (execute! db (vtab-insert fts5)))
                           'made))
              (before (views db with-v))
              (raw (st! (prepare! db "select 1")))
              (refused (closed db))
              (inside (attempt (lambda () (if (in-transaction? db) 'in-transaction 'autocommit))))
              (after (views db with-v))
              (code (fin! raw))
              (ended (done (lambda () (execute! db end))))
              (outside (attempt (lambda () (if (in-transaction? db) 'in-transaction 'autocommit))))
              (then (views db with-v))
              (checked (if with-v (integrity db) 'no-check))
              (other (db! (open-database path)))
              (seen (views other with-v))
              (other-checked (if with-v (integrity other) 'no-check))
              (c1 (closed other))
              (c2 (closed db)))
         (list before refused inside after code ended outside then checked seen other-checked
               c1 c2 (native-counts)))))))

(define refused-untracked '(raised (assertion-violation close-database! (untracked-statements 1))))
(define corrupt '(raised (sqlite-error execute! corrupt corrupt-vtab)))

(per-module fts5
  "a transaction that wrote a plain table and an fts5 table, then a close that sqlite3_close refuses: the transaction stays open, the plain table's row and the fts5 table's content stay, but fts5's own rollback discards its index's pending terms, so its search finds 0; a commit then writes an index the integrity check calls corrupt, corrupt-vtab, as another connection sees it too; a rollback then leaves both tables empty and intact"
  (list (list '(1 1 1) refused-untracked 'in-transaction '(1 1 0) 0 'done 'autocommit
              '(1 1 0) corrupt '(1 1 0) corrupt 'closed 'closed zero-counts)
        (list '(1 1 1) refused-untracked 'in-transaction '(1 1 0) 0 'done 'autocommit
              '(0 0 0) 'intact '(0 0 0) 'intact 'closed 'closed zero-counts))
  (lambda ()
    (let* ((committed (transaction-state #t "commit"))
           (rolled-back (transaction-state #t "rollback")))
      (list committed rolled-back))))

(test-equal "a transaction that wrote a plain table, then a close that sqlite3_close refuses: the transaction stays open with its row; a commit keeps it, as another connection sees, and a rollback undoes it"
  (list (list '(1) refused-untracked 'in-transaction '(1) 0 'done 'autocommit '(1) 'no-check '(1)
              'no-check 'closed 'closed zero-counts)
        (list '(1) refused-untracked 'in-transaction '(1) 0 'done 'autocommit '(0) 'no-check '(0)
              'no-check 'closed 'closed zero-counts))
  (let* ((committed (transaction-state #f "commit"))
         (rolled-back (transaction-state #f "rollback")))
    (list committed rolled-back)))

;; --- after a refusal: the table takes writes again ----------------------------------------

;; count-of : Database String -> Any
;; The one count SQL reads on DB, by attempt.
(define (count-of db sql) (attempt (lambda () (vector-ref (query-row db sql) 0))))

(define search "select count(*) from v where v match 'hello'")

;; backup-of : Database Database -> Natural
;; A backup reading SOURCE's main into TARGET's: its pointer, 0 for none.
(define (backup-of target source)
  (with-handle target
    (lambda (t)
      (with-handle source
        (lambda (s)
          (call-with-c-string 'test-connection-close "main"
            (lambda (main) (backup-init t main s main))))))))

(per-module fts5
  "after a close that a backup refused, the connection's fts5 table takes writes again: an insert, then its search, a with-transaction insert, then its search, and the integrity check, intact; once the backup is finished both connections close, and the file reopened finds every row, intact"
  (list '(raised (sqlite-error close-database! busy busy)) 'done 2 'done 3 'intact 0 'closed 'closed 3
        'intact 'closed zero-counts)
  (lambda ()
    (let ((path (fresh-path)))
      (with-undo
       (lambda (db! st! fin!)
         (let* ((source (db! (open-database path)))
                (target (db! (open-database ":memory:")))
                (backup #f))
           ;; The backup is finished, however the row ends, before with-undo
           ;; closes the connections.
           (dynamic-wind
             (lambda () #f)
             (lambda ()
               (let* ((made (begin (execute! source (vtab-create fts5))
                                   (execute! source "insert into v(body) values ('hello one')")
                                   (set! backup (backup-of target source))
                                   'made))
                      (refused (closed source))
                      (inserted (done (lambda () (execute! source "insert into v(body) values ('hello two')"))))
                      (found (count-of source search))
                      (in-one (done (lambda ()
                                      (with-transaction source
                                        (lambda ()
                                          (execute! source "insert into v(body) values ('hello three')"))))))
                      (found-again (count-of source search))
                      (checked (integrity source))
                      (finished (let ((code (backup-finish backup))) (set! backup #f) code))
                      (a (closed source))
                      (b (closed target))
                      (other (db! (open-database path)))
                      (reopened (count-of other search))
                      (checked-again (integrity other))
                      (c (closed other)))
                 (list refused inserted found in-one found-again checked finished a b reopened
                       checked-again c (native-counts))))
             (lambda ()
               (when (and backup (not (eqv? backup 0))) (guard (e (#t #f)) (backup-finish backup)))))))))))

;; --- the boundary ---------------------------------------------------------------------------
;; The close vouches only for the statements chez-sqlite3 tracks: it
;; finalizes them, calls
;; sqlite3_close and reports its answer, and judges no statement it did not
;; make. Work something else left open on the connection, a statement, a
;; blob or a backup, from a defect or from foreign code such as a loaded
;; extension, makes sqlite3_close refuse, after it has disconnected the
;; virtual tables and rolled back each one a transaction wrote. What that
;; does to the other work is SQLite's, and the other work's owner's. These
;; rows hold what SQLite does there, as measured, so a change in SQLite
;; shows: they document it, they don't endorse it. After a refusal the count
;; is a diagnostic, every statement left, those a module keeps for a table
;; the leftover statement holds among them.

;; statements-left : Database -> Any
;; How many statements sqlite3_next_stmt finds on DB, by attempt.
(define (statements-left db)
  (attempt
   (lambda ()
     (with-handle db
       (lambda (h)
         (let loop ((st (next-stmt h 0)) (n 0))
           (if (eqv? st 0) n (loop (next-stmt h st) (+ n 1)))))))))

;; named-what-is-left : Any Any -> Any
;; Whether REFUSED, what close-database! raised, is its assertion violation
;; naming LEFT, the count this suite read after it: and then, whether LEFT
;; counts more than the one raw statement, a module's among them, or the
;; raw one alone.
(define (named-what-is-left refused left)
  (cond ((not (and (integer? left)
                   (equal? refused
                           (list 'raised (list 'assertion-violation 'close-database!
                                               (list 'untracked-statements left))))))
         (list 'named-otherwise refused left))
        ((> left 1) 'every-statement-left-a-modules-among-them)
        ((= left 1) 'the-one-statement-left)
        (else (list 'none-left left))))

(define (mode-of db)
  (attempt (lambda () (if (in-transaction? db) 'in-transaction 'autocommit))))

(per-module fts5
  "the boundary, as SQLite draws it: an untracked insert ... returning into an fts5 table, stepped once in autocommit, is work the close does not judge: sqlite3_close refuses, busy, once it has rolled the table back, and close-database! names every statement left, fts5's among them; the connection stays open and counted; once the statement is finalized its row commits without its index terms: the row is read, the search finds 0, and the integrity check calls the index corrupt; a second close closes"
  (list 'row 'every-statement-left-a-modules-among-them 'busy 'autocommit while-open 0 'autocommit
        '(1 0) corrupt 'closed zero-counts)
  (lambda ()
    (with-undo
     (lambda (db! st! fin!)
       (let* ((db (db! (open-database (fresh-path))))
              (made (execute! db (vtab-create fts5)))
              (raw (st! (prepare! db "insert into v(body) values ('hello world') returning rowid")))
              (stepped (let ((rc (raw-step raw))) (if (eqv? rc 100) 'row (list 'stepped rc))))
              (refused (closed db))
              (left (statements-left db))
              (named (named-what-is-left refused left))
              (after (extended-code db))
              (mode (mode-of db))
              (counts (native-counts))
              (code (fin! raw))
              (then (mode-of db))
              (reads (list (count-of db "select count(*) from v") (count-of db search)))
              (checked (integrity db))
              (again (closed db)))
         (list stepped named after mode counts code then reads checked again (native-counts)))))))

(test-equal "the boundary: an untracked select held at its row, with no module: sqlite3_close refuses, busy, and close-database! names the one statement left; the connection stays open and counted; once the statement is finalized a second close closes"
  (list 'row 'the-one-statement-left 'busy while-open 0 'closed zero-counts)
  (with-undo
   (lambda (db! st! fin!)
     (let* ((db (db! (open-database ":memory:")))
            (raw (st! (prepare! db "select 1")))
            (stepped (let ((rc (raw-step raw))) (if (eqv? rc 100) 'row (list 'stepped rc))))
            (refused (closed db))
            (named (named-what-is-left refused (statements-left db)))
            (after (extended-code db))
            (counts (native-counts))
            (code (fin! raw))
            (again (closed db)))
       (list stepped named after counts code again (native-counts))))))

(per-module fts5
  "the boundary: an untracked select of an fts5 table held at its row keeps the table connected: sqlite3_close refuses, busy, and close-database! names every statement left, fts5's among them; the connection stays open and counted; once the statement is finalized a second close closes"
  (list 'row 'every-statement-left-a-modules-among-them 'busy while-open 0 'closed zero-counts)
  (lambda ()
    (with-undo
     (lambda (db! st! fin!)
       (let* ((db (db! (open-database ":memory:")))
              (made (begin (execute! db (vtab-create fts5)) (execute! db (vtab-insert fts5))))
              (raw (st! (prepare! db "select body from v where v match 'hello'")))
              (stepped (let ((rc (raw-step raw))) (if (eqv? rc 100) 'row (list 'stepped rc))))
              (refused (closed db))
              (named (named-what-is-left refused (statements-left db)))
              (after (extended-code db))
              (counts (native-counts))
              (code (fin! raw))
              (again (closed db)))
         (list stepped named after counts code again (native-counts)))))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "connection-close")

(exit (suite-exit-status runner))
