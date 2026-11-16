#!r6rs
;;; The suite for the statement cache in its connection's record (ADR-0020;
;;; the M3 plan, section 4.6), through M3's internals: (chez-sqlite3 private
;;; connection)'s record, its private opener and its close, and (chez-sqlite3
;;; private statement)'s checked-out and returned. The pure table is slice 1's,
;;; held by tests/test-statement-cache.sps; the raises' who and depth are
;;; tests/test-statement-who.sps's.
;;;
;;;   the capacity  32 from open-database and call-with-database; the opener
;;;                 of a given capacity takes 0, 1 and 1024 and refuses
;;;                 -1, 1025, 32.0, "32" and #t by the settings' rule, before
;;;                 anything opens
;;;   the flags     a miss prepares SQLITE_PREPARE_PERSISTENT while the
;;;                 capacity is above 0, and with no flags at 0, read through
;;;                 lookaside (M3's research, single K1)
;;;   reuse         a return files the statement reset, its bindings cleared;
;;;                 the next check-out of its SQL answers that very statement;
;;;                 at 0 every return finalizes; at 1 and 2 the least
;;;                 recently used goes first (A, B, A, C leaves A and C); 33
;;;                 distinct statements leave 32 at the default, 0 at 0, 1 at
;;;                 1; the same SQL checked out twice keeps one; what a
;;;                 return evicts or refuses is finalized
;;;   not kept      a statement whose step failed; one whose reset failed, an
;;;                 insert ... returning under another's read, which rolls
;;;                 the insert back
;;;   a miss        a cached statement finalized, or moved by a suite, is
;;;                 never handed out
;;;   the close     empties the cache whether or not the connection closes:
;;;                 a close a backup makes fail, and one refused for an
;;;                 untracked statement, leave it empty, and the next
;;;                 check-out on the still-open connection prepares afresh
;;;   the section   two engines on one thread, each checking out, stepping,
;;;                 reading and returning the same SQL, at every fuel from 1
;;;                 until both complete without expiring: no statement is
;;;                 handed out twice, each answer is right, and one statement
;;;                 is left, cached
;;;
;;; The loading procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them. SQLite's answers here were measured
;;; on 3.53.1 and 3.45.1 alike (.plans/research/m3-slice-3/) before a row
;;; asserts them.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure foreign-alloc foreign-free foreign-ref foreign-set!
              make-engine)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-error-sql sqlite-error-offset sqlite-closed?))

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

(define connection-library '(chez-sqlite3 private connection))
(define statement-library '(chez-sqlite3 private statement))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define call-with-database (reach '(chez-sqlite3) 'call-with-database))
(define open-database-with-cache-capacity (reach connection-library 'open-database-with-cache-capacity))
(define database-cache-capacity (reach connection-library 'database-cache-capacity))
(define database-cache-count (reach connection-library 'database-cache-count))
(define call-with-open-handle (reach connection-library 'call-with-open-handle))
(define tracked-statements (reach connection-library 'tracked-statements))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define step! (reach statement-library 'step!))
(define statement-sql (reach statement-library 'statement-sql))
(define statement-state (reach statement-library 'statement-state))
(define checked-out (reach statement-library 'checked-out))
(define returned (reach statement-library 'returned))
(define bind! (reach '(chez-sqlite3 private statement-values) 'bind!))
(define column-value (reach '(chez-sqlite3 private statement-values) 'column-value))
(define sql-null? (reach '(chez-sqlite3 private values) 'sql-null?))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-out-pointer (reach '(chez-sqlite3 private native) 'call-with-out-pointer))

;; --- bindings made here, after the load ------------------------------------------------

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_db_status(sqlite3*, int op, int *pCur, int *pHiwtr, int resetFlg)
(define db-status (bound 'sqlite3_db_status (foreign-procedure "sqlite3_db_status" (uptr int uptr uptr int) int)))
;; int sqlite3_prepare_v2(sqlite3*, const char *zSql, int nByte, sqlite3_stmt **, const char **pzTail)
(define prepare-v2 (bound 'sqlite3_prepare_v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int)))
;; int sqlite3_finalize(sqlite3_stmt*)
(define raw-finalize (bound 'sqlite3_finalize (foreign-procedure "sqlite3_finalize" (uptr) int)))
;; sqlite3_backup *sqlite3_backup_init(sqlite3 *pDest, const char *zDestName,
;;                                     sqlite3 *pSource, const char *zSourceName)
(define backup-init (bound 'sqlite3_backup_init (foreign-procedure "sqlite3_backup_init" (uptr uptr uptr uptr) uptr)))
;; int sqlite3_backup_finish(sqlite3_backup*)
(define backup-finish (bound 'sqlite3_backup_finish (foreign-procedure "sqlite3_backup_finish" (uptr) int)))

;; SQLITE_DBSTATUS_LOOKASIDE_USED, sqlite3.h's 0.
(define lookaside-used-op 0)

;; --- helpers ------------------------------------------------------------------------------

(define the-who 'the-convenience)

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

;; counts-with : (Listof (Pairof Symbol Integer)) -> (Listof (Pairof Symbol Integer))
(define (counts-with changes)
  (map (lambda (entry) (cond ((assq (car entry) changes) => (lambda (c) c)) (else entry)))
       zero-counts))

(define (with-statements n) (counts-with (list '(connection . 1) (cons 'statement n))))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (sqlite-error-sql e) (sqlite-error-offset e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

(define (refused who . irritants) (list 'assertion-violation who irritants))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define void-value (if #f #f))
(define (no-value x) (if (eq? x void-value) 'no-value x))

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

;; with-capacity : Natural (Database -> Any) -> Any
;; with-db on a :memory: database whose cache holds CAPACITY.
(define (with-capacity capacity proc)
  (with-db (lambda () (open-database-with-cache-capacity capacity ":memory:")) proc))

(define (with-memory-db proc) (with-db (lambda () (open-database ":memory:")) proc))

;; in-dir : (String -> Any) -> Any
(define (in-dir proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory proc)))

;; with-handle : Any (Positive-Integer -> A) -> A
(define (with-handle db proc) (call-with-open-handle 'test-connection-cache db proc))

;; exec! : Database String -> Any
(define (exec! db sql)
  (let* ((st (prepare-statement db sql))
         (answer (guard (e (#t (finalize-statement! st) (raise e))) (step! st))))
    (finalize-statement! st)
    answer))

;; query-int : Database String -> Integer
(define (query-int db sql)
  (let* ((st (prepare-statement db sql))
         (answer (guard (e (#t (finalize-statement! st) (raise e)))
                   (step! st)
                   (column-value st 0))))
    (finalize-statement! st)
    answer))

;; make-table! : String -> Any
;; The database at PATH, made with table t, x unique, holding the one row 0.
(define (make-table! path)
  (let ((db (open-database path)))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (exec! db "create table t (x unique)")
        (exec! db "insert into t values (0)"))
      (lambda () (undo! '() (list db))))))

;; reader! : String -> (Pairof Database Statement)
(define (reader! path)
  (let* ((db (open-database path))
         (st (prepare-statement db "select x from t")))
    (step! st)
    (cons db st)))

;; release! : Any -> Void
(define (release! reader)
  (when (pair? reader) (undo! (list (cdr reader)) (list (car reader)))))

;; raw-prepare! : Database String -> Positive-Integer
;; A statement of SQL on DB, made with the raw sqlite3_prepare_v2, so the
;; connection does not track it.
(define (raw-prepare! db sql)
  (with-handle db
    (lambda (h)
      (call-with-c-string 'test-connection-cache sql
        (lambda (text)
          (let-values (((rc statement)
                        (call-with-out-pointer 'test-connection-cache
                          (lambda (slot) (prepare-v2 h text -1 slot 0)))))
            (if (and (eqv? rc 0) (not (eqv? statement 0)))
                statement
                (error 'raw-prepare! "sqlite3_prepare_v2 did not answer a statement" rc))))))))

;; lookaside-used : Database -> Integer
(define (lookaside-used db)
  (with-handle db
    (lambda (h)
      (let ((cur (foreign-alloc 8)) (hi (foreign-alloc 8)))
        (foreign-set! 'int cur 0 0)
        (foreign-set! 'int hi 0 0)
        (let* ((rc (db-status h lookaside-used-op cur hi 0))
               (n (foreign-ref 'int cur 0)))
          (foreign-free cur)
          (foreign-free hi)
          (if (eqv? rc 0) n (list 'db-status-failed rc)))))))

;; use! : Database String -> Any
;; SQL checked out on DB, stepped once, its first column read when it
;; answered a row, and given back: the column, or done.
(define (use! db sql)
  (let* ((st (checked-out the-who db sql #f #f))
         (row (step! st))
         (v (if row (column-value st 0) 'done)))
    (returned the-who st)
    v))

;; cached-sql : Database -> (Listof String)
;; The SQL of every statement DB tracks, oldest first, each a statement the
;; cache holds when nothing else is live.
(define (cached-sql db)
  (let loop ((rest (tracked-statements db)) (found '()))
    (if (null? rest)
        (reverse found)
        (loop (cdr rest) (cons (statement-sql (car rest)) found)))))

;; distinct-sql : Natural -> String
(define (distinct-sql i) (string-append "select " (number->string i)))

;; use-distinct! : Database Natural -> Void
;; N distinct statements, select 0 to select N-1, each used once, in order.
(define (use-distinct! db n)
  (let loop ((i 0))
    (when (< i n)
      (use! db (distinct-sql i))
      (loop (+ i 1)))))

(test-begin "connection-cache")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

;; --- the capacity -----------------------------------------------------------------------

(test-equal "the cache's capacity is 32 from open-database and from call-with-database, and the capacity given to the private opener: 0, 1 and 1024"
  '(32 32 0 1 1024)
  (list (with-memory-db database-cache-capacity)
        (attempt (lambda () (call-with-database ":memory:" database-cache-capacity)))
        (with-capacity 0 database-cache-capacity)
        (with-capacity 1 database-cache-capacity)
        (with-capacity 1024 database-cache-capacity)))

(test-equal "the private opener refuses a capacity outside 0 to 1024 by the settings' rule, -1, 1025, 32.0, \"32\" by its kind and #t, before anything opens; then open-database's own checks, naming the opener"
  (list (list 'raised (refused 'open-database-with-cache-capacity 'setting-out-of-domain 'statement-cache -1))
        (list 'raised (refused 'open-database-with-cache-capacity 'setting-out-of-domain 'statement-cache 1025))
        (list 'raised (refused 'open-database-with-cache-capacity 'setting-out-of-domain 'statement-cache 32.0))
        (list 'raised (refused 'open-database-with-cache-capacity 'setting-out-of-domain 'statement-cache '(kind string)))
        (list 'raised (refused 'open-database-with-cache-capacity 'setting-out-of-domain 'statement-cache #t))
        (list 'raised (refused 'open-database-with-cache-capacity 'not-a-string 42))
        (list 'raised (refused 'open-database-with-cache-capacity 'unknown-option 'bogus))
        zero-counts)
  (let* ((a (attempt (lambda () (open-database-with-cache-capacity -1 ":memory:"))))
         (b (attempt (lambda () (open-database-with-cache-capacity 1025 ":memory:"))))
         (c (attempt (lambda () (open-database-with-cache-capacity 32.0 ":memory:"))))
         (d (attempt (lambda () (open-database-with-cache-capacity "32" ":memory:"))))
         (e (attempt (lambda () (open-database-with-cache-capacity #t ":memory:"))))
         (f (attempt (lambda () (open-database-with-cache-capacity 1 42))))
         (g (attempt (lambda () (open-database-with-cache-capacity 1 ":memory:" 'bogus)))))
    (list a b c d e f g (native-counts))))

(test-equal "the private opener checks its capacity first: with a capacity and a filename both refused, the capacity's refusal is the one raised"
  (list 'raised (refused 'open-database-with-cache-capacity 'setting-out-of-domain 'statement-cache -1))
  (attempt (lambda () (open-database-with-cache-capacity -1 42))))

(test-equal "database-cache-capacity and database-cache-count refuse no database, and database-cache-count reads 0 once the connection is closed"
  (list (list 'raised (refused 'database-cache-capacity 'not-a-database 'x))
        (list 'raised (refused 'database-cache-count 'not-a-database 'x))
        '(1 0))
  (list (attempt (lambda () (database-cache-capacity 'x)))
        (attempt (lambda () (database-cache-count 'x)))
        (let* ((db (open-database ":memory:"))
               (u (use! db "select 1"))
               (before (database-cache-count db))
               (c (close-database! db)))
          (list before (database-cache-count db)))))

;; --- the flags a miss prepares with -------------------------------------------------------------
;; Measured (.plans/research/m3-slice-3/lookaside-tails.sps), on both
;; libraries: ten held statements prepared with no flags take 70 lookaside
;; slots, and SQLITE_PREPARE_PERSISTENT ones none.

;; held-lookaside : Natural -> Any
;; Ten statements of distinct SQL checked out and held on a connection of
;; CAPACITY: the lookaside slots they take.
(define (held-lookaside capacity)
  (with-capacity capacity
    (lambda (db)
      (let loop ((i 0) (held '()))
        (if (< i 10)
            (loop (+ i 1) (cons (checked-out the-who db (string-append "select 1, 2 where ?1 = " (number->string i)) #f #f) held))
            (let ((used (lookaside-used db)))
              (for-each finalize-statement! held)
              used))))))

(test-equal "a miss prepares SQLITE_PREPARE_PERSISTENT while the capacity is above 0, so ten held statements take no lookaside, at 32 and at 1; at 0 it prepares with no flags, and they take some"
  (list 0 0 'some)
  (let* ((at-32 (held-lookaside 32))
         (at-1 (held-lookaside 1))
         (at-0 (held-lookaside 0)))
    (list at-32 at-1 (if (and (integer? at-0) (> at-0 0)) 'some at-0))))

;; --- reuse ---------------------------------------------------------------------------------

(test-equal "a returned statement is filed, reset and its bindings cleared: the next check-out of its SQL answers that very statement, ready, its parameter NULL again, while one statement is counted"
  (list 5 'the-very-statement 'ready 'null 1 (with-statements 1))
  (with-memory-db
   (lambda (db)
     (let* ((st (checked-out the-who db "select ?1" #f #f))
            (b (bind! st 1 5))
            (s (step! st))
            (first (column-value st 0))
            (r (returned the-who st))
            (again (checked-out the-who db "select ?1" #f #f))
            (state (statement-state again))
            (s2 (step! again))
            (second (column-value again 0))
            (r2 (returned the-who again)))
       (list first (if (eq? again st) 'the-very-statement 'another) state
             (if (sql-null? second) 'null second)
             (database-cache-count db) (native-counts))))))

(test-equal "at a capacity of 0 every return finalizes: after each use no statement is counted or tracked, the cache holds none, and a statement returned is finalized"
  (list '(1 0 0 0) '(2 0 0 0) 'finalized)
  (with-capacity 0
    (lambda (db)
      (let* ((a (use! db "select 1"))
             (after-a (list a (database-cache-count db) (length (tracked-statements db))
                            (cdr (assq 'statement (native-counts)))))
             (b (use! db "select 2"))
             (after-b (list b (database-cache-count db) (length (tracked-statements db))
                            (cdr (assq 'statement (native-counts)))))
             (st (checked-out the-who db "select 3" #f #f))
             (r (returned the-who st)))
        (list after-a after-b (statement-state st))))))

(test-equal "at a capacity of 1, a return into the full cache evicts the least recently used, finalized and untracked; the next check-out of the evicted SQL prepares afresh"
  (list 'finalized '("select 2") 'another-statement 'ready)
  (with-capacity 1
    (lambda (db)
      (let* ((a (checked-out the-who db "select 1" #f #f))
             (ra (returned the-who a))
             (b (checked-out the-who db "select 2" #f #f))
             (rb (returned the-who b))
             (state (statement-state a))
             (held (cached-sql db))
             (again (checked-out the-who db "select 1" #f #f))
             (fresh (if (eq? again a) 'the-evicted-statement 'another-statement))
             (state-again (statement-state again)))
        (returned the-who again)
        (list state held fresh state-again)))))

(test-equal "at a capacity of 2, the statements A, B, A, C leave A and C: A's reuse makes B the least recently used, and C evicts it"
  (list '("select 'a'" "select 'c'") 2 "a" "c")
  (with-capacity 2
    (lambda (db)
      (let* ((a (use! db "select 'a'"))
             (b (use! db "select 'b'"))
             (a2 (use! db "select 'a'"))
             (c (use! db "select 'c'")))
        (list (list-sort string<? (cached-sql db)) (database-cache-count db) a2 c)))))

(test-equal "33 distinct statements, each used once, leave the cache full and no more counted: 32 at the default, 1 at 1, 0 at 0"
  (list (list 32 32) (list 1 1) (list 0 0))
  (let ((after-33 (lambda (open)
                    (with-db open
                      (lambda (db)
                        (use-distinct! db 33)
                        (list (database-cache-count db) (cdr (assq 'statement (native-counts)))))))))
    (list (after-33 (lambda () (open-database ":memory:")))
          (after-33 (lambda () (open-database-with-cache-capacity 1 ":memory:")))
          (after-33 (lambda () (open-database-with-cache-capacity 0 ":memory:"))))))

(test-equal "the same SQL checked out twice, while the first is out, gives two statements; returned, the first is kept and the second, its SQL held already, finalized"
  (list 'two-statements 'ready 'finalized 1 (with-statements 1))
  (with-memory-db
   (lambda (db)
     (let* ((a (checked-out the-who db "select 1" #f #f))
            (b (checked-out the-who db "select 1" #f #f))
            (two (if (eq? a b) 'one-statement 'two-statements))
            (ra (returned the-who a))
            (rb (returned the-who b)))
       (list two (statement-state a) (statement-state b) (database-cache-count db) (native-counts))))))

;; --- not kept ----------------------------------------------------------------------------------

(test-equal "a statement whose step failed is finalized on its return, never kept: the cache holds none, and nothing is counted but the connection"
  (list (list 'raised (list 'sqlite-error 'step! 'constraint 'constraint-unique "insert into t values (0)" #f))
        'finalized 0 (with-statements 0))
  (in-dir
   (lambda (dir)
     (let ((path (string-append dir "/t.db")))
       (make-table! path)
       (with-db (lambda () (open-database path))
         (lambda (db)
           (let* ((st (checked-out the-who db "insert into t values (0)" #f #f))
                  (s (attempt (lambda () (step! st))))
                  (r (returned the-who st)))
             (list s (statement-state st) (database-cache-count db) (native-counts)))))))))

(test-equal "a statement whose reset fails on its return is finalized, not kept, and the failure raised: an insert ... returning stepped once under another's read answers busy, and the insert is rolled back"
  (list (list 'raised (list 'sqlite-error the-who 'busy 'busy "insert into t values (1), (2) returning x" #f))
        'finalized 0 1)
  (in-dir
   (lambda (dir)
     (let ((path (string-append dir "/t.db")))
       (make-table! path)
       (with-db (lambda () (open-database path))
         (lambda (db)
           (let ((reader #f))
             (dynamic-wind
               (lambda () #f)
               (lambda ()
                 (set! reader (reader! path))
                 (let* ((st (checked-out the-who db "insert into t values (1), (2) returning x" #f #f))
                        (s (step! st))
                        (r (attempt (lambda () (returned the-who st))))
                        (state (statement-state st))
                        (held (database-cache-count db)))
                   (release! reader)
                   (set! reader #f)
                   (list r state held (query-int db "select count(*) from t"))))
               (lambda () (release! reader))))))))))

;; --- a miss ---------------------------------------------------------------------------------------

(test-equal "a cached statement that is finalized is a miss: the next check-out of its SQL prepares afresh, never handing out the finalized one"
  (list 'finalized 'another-statement 'ready 1)
  (with-memory-db
   (lambda (db)
     (let* ((u (use! db "select 1"))
            (held (car (tracked-statements db)))
            (f (finalize-statement! held))
            (again (checked-out the-who db "select 1" #f #f))
            (fresh (if (eq? again held) 'the-finalized-statement 'another-statement))
            (state (statement-state again))
            (r (returned the-who again)))
       (list (statement-state held) fresh state (database-cache-count db))))))

(test-equal "a cached statement a suite moved through tracked-statements, stepped to a row, is a miss: a fresh one is handed out, and the moved one stays tracked as it was"
  (list 'another-statement 'row 2)
  (with-memory-db
   (lambda (db)
     (let* ((u (use! db "select 1"))
            (held (car (tracked-statements db)))
            (s (step! held))
            (again (checked-out the-who db "select 1" #f #f))
            (fresh (if (eq? again held) 'the-moved-statement 'another-statement))
            (r (returned the-who again))
            (tracked (length (tracked-statements db))))
       (list fresh (statement-state held) tracked)))))

;; --- the close ----------------------------------------------------------------------------------

(test-equal "a close that succeeds finalizes the cache's statements and leaves it empty"
  (list 'finalized 'finalized 0 zero-counts)
  (let* ((db (open-database ":memory:"))
         (a (checked-out the-who db "select 1" #f #f))
         (ra (returned the-who a))
         (b (checked-out the-who db "select 2" #f #f))
         (rb (returned the-who b))
         (c (close-database! db)))
    (list (statement-state a) (statement-state b) (database-cache-count db) (native-counts))))

;; Measured (build/m2s3/probe-close.sps, M2 slice 3), on both libraries: a
;; backup reading from the connection makes sqlite3_close answer 5.
(test-equal "a close that fails, held by a backup, empties the cache all the same: the close raises busy, the connection stays open, the cached statement is finalized, the cache holds none, and the next check-out of its SQL prepares afresh, ready"
  (list 'backup (list 'raised (list 'sqlite-error 'close-database! 'busy 'busy #f #f))
        'finalized 0 'another-statement 'ready 'closed zero-counts)
  (in-dir
   (lambda (dir)
     (let ((path (string-append dir "/t.db")) (db #f) (target #f) (backup #f))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (attempt
            (lambda ()
              (make-table! path)
              (set! db (open-database path))
              (set! target (open-database ":memory:"))
              (let* ((st (checked-out the-who db "select x from t" #f #f))
                     (r (returned the-who st)))
                (set! backup
                      (with-handle target
                        (lambda (t)
                          (with-handle db
                            (lambda (s)
                              (call-with-c-string 'test-connection-cache "main"
                                (lambda (main) (backup-init t main s main))))))))
                (let* ((made (if (eqv? backup 0) 'no-backup 'backup))
                       (c (attempt (lambda () (close-database! db) 'closed)))
                       (state (statement-state st))
                       (held (database-cache-count db))
                       (again (checked-out the-who db "select x from t" #f #f))
                       (fresh (if (eq? again st) 'the-finalized-statement 'another-statement))
                       (state-again (statement-state again))
                       (r2 (returned the-who again))
                       (finished (let ((code (backup-finish backup))) (set! backup #f) code))
                       (closed (attempt (lambda () (close-database! db) 'closed)))
                       (last (begin (close-database! target) (native-counts))))
                  (list made c state held fresh state-again closed last))))))
         (lambda ()
           (when (and backup (not (eqv? backup 0))) (guard (e (#t #f)) (backup-finish backup)))
           (undo! '() (filter (lambda (x) x) (list db target)))))))))

(test-equal "a close refused for an untracked statement empties the cache all the same: the cached statement is finalized, the cache holds none, and the next check-out of its SQL on the still-open connection prepares afresh, ready"
  (list (list 'raised (refused 'close-database! 'untracked-statements 1))
        'finalized 0 'another-statement 'ready 'closed zero-counts)
  (let ((db #f) (raw #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let* ((st (checked-out the-who db "select 1" #f #f))
                  (r (returned the-who st)))
             (set! raw (raw-prepare! db "select 2"))
             (let* ((c (attempt (lambda () (close-database! db) 'closed)))
                    (state (statement-state st))
                    (held (database-cache-count db))
                    (again (checked-out the-who db "select 1" #f #f))
                    (fresh (if (eq? again st) 'the-finalized-statement 'another-statement))
                    (state-again (statement-state again))
                    (r2 (returned the-who again))
                    (freed (begin (raw-finalize raw) (set! raw #f)))
                    (closed (attempt (lambda () (close-database! db) 'closed))))
               (list c state held fresh state-again closed (native-counts)))))))
      (lambda ()
        (when raw (raw-finalize raw))
        (undo! '() (if db (list db) '()))))))

;; --- the section: two engines on one thread ---------------------------------------------------------
;; A and B each check out select 7, step it, read its column and give it
;; back, as engines of FUEL ticks a slice, taking turns until both are done,
;; on a connection whose cache already holds select 7. A check-out and a
;; return change the table inside call-with-open-handle's section, where an
;; engine never expires, so neither engine can see the other's change half
;; made. Each engine notes the statement it holds, from its check-out's
;; hand-over to its return; a hand-over of a statement the other holds is
;; handed-out-twice.

;; race : Positive-Integer -> (U 'completed Any)
(define (race fuel)
  (with-memory-db
   (lambda (db)
     (let* ((warm (use! db "select 7"))
            (holding (vector #f #f))
            (twice #f)
            (expired #f)
            (run (lambda (me other)
                   (lambda ()
                     (attempt
                      (lambda ()
                        (let ((st (checked-out the-who db "select 7"
                                               (lambda (s)
                                                 (when (eq? s (vector-ref holding other)) (set! twice #t))
                                                 (vector-set! holding me s)) #f)))
                          (step! st)
                          (let ((v (column-value st 0)))
                            (vector-set! holding me #f)
                            (returned the-who st)
                            v)))))))
            (answers (vector 'unfinished 'unfinished)))
       (let loop ((engines (list (cons 0 (make-engine (run 0 1))) (cons 1 (make-engine (run 1 0)))))
                  (turns 0))
         (when (and (pair? engines) (< turns 100000))
           (let* ((me (car (car engines)))
                  (next ((cdr (car engines)) fuel
                         (lambda (left . v) (vector-set! answers me (car v)) #f)
                         (lambda (more) (set! expired #t) more))))
             (loop (if next (append (cdr engines) (list (cons me next))) (cdr engines))
                   (+ turns 1)))))
       (let ((outcome (list (vector-ref answers 0) (vector-ref answers 1)
                            (if twice 'handed-out-twice 'never-twice)
                            (database-cache-count db) (length (tracked-statements db))
                            (cdr (assq 'statement (native-counts))))))
         (if (and (not expired) (equal? outcome '(7 7 never-twice 1 1 1)))
             'completed
             outcome))))))

(test-equal "two engines on one thread, each checking out, stepping, reading and returning the same SQL, at every fuel from 1 until both complete without expiring: each answers 7, no statement is handed out twice, and one statement is left, cached and counted"
  '()
  (let ((run (let loop ((fuel 1) (found '()))
               (let ((answer (race fuel)))
                 (cond ((eq? answer 'completed) (list fuel (reverse found)))
                       ((>= fuel 3000) (list 'no-completion-by 3000 (reverse found)))
                       (else (loop (+ fuel 1)
                                   (if (equal? answer '(7 7 never-twice 1 1 1))
                                       found
                                       (cons (list fuel answer) found)))))))))
    (when (integer? (car run))
      (display "  the race completed without expiring at fuel ")
      (display (car run))
      (newline))
    (if (integer? (car run)) (cadr run) run)))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "connection-cache")

(exit (suite-exit-status runner))
