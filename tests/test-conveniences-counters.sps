#!r6rs
;;; The suite for the change counters and in-transaction? through the conveniences
;;; (ADR-0016): every counter case run by execute!, as
;;; tests/test-change-counters.sps runs them through the statement tier, and the
;;; in-transaction? cases through in-transaction?. The cases
;;; tests/test-change-counters.sps alone can reach stay there: a fresh connection's
;;; counters (C0), a statement finalized unstepped (C14's second half), and an
;;; insert ... returning read step by step (C12), which no convenience stops
;;; between steps.
;;;
;;;   the cases     as measured: before each
;;;                 statement, an INSERT OR REPLACE of two rows into z, run by
;;;                 execute!, sets changes to 2 and last-insert-rowid to 7777;
;;;                 the statement runs by execute!, to done, reset and cached;
;;;                 then changes, total-changes' move across it, and
;;;                 last-insert-rowid are read. Each row asserts what was
;;;                 measured, alike on 3.53.1 and 3.45.1
;;;   RETURNING     execute! of an insert ... returning of 3 counts at its
;;;                 done; query-row's of 3, and of a delete ... returning,
;;;                 count at the reset after the first row (C12b, C12c)
;;;   in-transaction?
;;;                 through execute!'s BEGIN, COMMIT, ROLLBACK, SAVEPOINT and
;;;                 RELEASE; and #f in a fold's procedure while its
;;;                 autocommit read is held, #t inside BEGIN
;;;
;;; The loading procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-closed?))

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
(define execute! (reach conveniences 'execute!))
(define query (reach conveniences 'query))
(define query-row (reach conveniences 'query-row))
(define query-fold (reach conveniences 'query-fold))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define changes (reach connection-library 'changes))
(define total-changes (reach connection-library 'total-changes))
(define last-insert-rowid (reach connection-library 'last-insert-rowid))
(define in-transaction? (reach connection-library 'in-transaction?))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
(define (what-raised e)
  (cond ((sqlite-error? e) (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define void-value (if #f #f))

;; setup! : Database (Listof String) -> Void
;; Each of STATEMENTS run by execute!, in order.
(define (setup! db statements)
  (for-each (lambda (sql) (execute! db sql)) statements))

;; in-dir : (String -> Any) -> Any
(define (in-dir proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory proc)))

;; with-counters-db : (List String) (String Database -> Any) -> Any
;; PROC's answer, or what it raised, given a file c.db in a temporary
;; directory, made with the tables z and t and then SETUP, and a
;; connection to it, closed after.
(define (with-counters-db setup proc)
  (in-dir
   (lambda (dir)
     (let ((path (string-append dir "/c.db")) (db #f))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (attempt
            (lambda ()
              (set! db (open-database path))
              (setup! db (append '("create table z(v)" "create table t(x)") setup))
              (proc path db))))
         (lambda () (when db (guard (e (#t #f)) (close-database! db)))))))))

;; prime! : Database -> Void
;; changes 2 and last-insert-rowid 7777.
(define (prime! db)
  (execute! db "insert or replace into z(rowid, v) values (7776, 'p'), (7777, 'p')"))

;; counters : Database Integer -> (List Integer Integer Integer)
;; changes, total-changes' move since BEFORE, and last-insert-rowid.
(define (counters db before)
  (let* ((c (changes db))
         (t (- (total-changes db) before))
         (r (last-insert-rowid db)))
    (list c t r)))

;; measure : Database String -> (List Any (List Integer Integer Integer))
;; The measure, through execute!: DB primed, SQL run by execute!;
;; done, or the failure's extended code; then the counters.
(define (measure db sql)
  (prime! db)
  (let* ((before (total-changes db))
         (r (attempt (lambda () (execute! db sql))))
         (ended (cond ((eq? r void-value) 'done)
                      ((and (pair? r) (pair? (cadr r)) (eq? (car (cadr r)) 'sqlite-error))
                       (list-ref (cadr r) 3))
                      (else r))))
    (list ended (counters db before))))

;; measured : Database (Listof String) -> (Listof Any)
(define (measured db statements)
  (let loop ((rest statements) (found '()))
    (if (null? rest)
        (reverse found)
        (loop (cdr rest) (cons (measure db (car rest)) found)))))

(define (done c t r) (list 'done (list c t r)))
(define (failed code c t r) (list code (list c t r)))

(test-begin "conveniences-counters")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

;; --- case by case, through execute! ---------------------------------------------------------
;; Each row's expected values are measured for its case, on 3.53.1 and 3.45.1 alike, as
;; tests/test-change-counters.sps reads them after the last step.

(test-equal "C1, by execute!: an INSERT of 3 rows counts 3 and names its last row; an UPDATE of 3, then of none, counts 3, then 0; a DELETE of 2 counts 2; an INSERT ... SELECT of 5 counts 5 and names its last row"
  (list (done 3 3 103) (done 3 3 7777) (done 0 0 7777) (done 2 2 7777) (done 5 5 205))
  (with-counters-db '()
    (lambda (path db)
      (measured db (list "insert into t(rowid, x) values (101, 1), (102, 2), (103, 3)"
                         "update t set x = x + 10"
                         "update t set x = x where x > 1000"
                         "delete from t where x > 11"
                         "insert into t(rowid, x) select 200 + value, value from (with recursive n(value) as (select 1 union all select value + 1 from n where value < 5) select value from n)")))))

(test-equal "C2, by execute!: DELETE FROM t with no WHERE counts the 6 rows it deleted, and 0 on an empty table"
  (list (done 6 6 7777) (done 0 0 7777))
  (with-counters-db '("insert into t values (1), (2), (3), (4), (5), (6)")
    (lambda (path db)
      (measured db (list "delete from t" "delete from t")))))

(test-equal "C3, by execute!: DDL leaves changes and last-insert-rowid as they were, and moves total-changes by nothing"
  (list (done 2 0 7777) (done 2 0 7777) (done 2 0 7777) (done 2 0 7777) (done 2 0 7777) (done 2 0 7777))
  (with-counters-db '("insert into t values (1), (2), (3)")
    (lambda (path db)
      (let* ((a (measured db (list "create table d(x)" "create index ti on t(x)" "alter table t add column y"
                                   "create view vw as select x from t")))
             (s (execute! db "insert into d values (1), (2), (3), (4)"))
             (b (measured db (list "drop table d" "drop index ti"))))
        (append a b)))))

(test-equal "C4, by execute!: a SELECT, PRAGMA user_version = 5, BEGIN and COMMIT leave every counter as it was"
  (list (done 2 0 7777) (done 2 0 7777) (done 2 0 7777) (done 2 0 7777))
  (with-counters-db '("insert into t values (1), (2), (3)")
    (lambda (path db)
      (measured db (list "select x from t" "pragma user_version = 5" "begin" "commit")))))

(test-equal "C5, by execute!: an INSERT failing at its 3rd row of 4 counts 0, and last-insert-rowid names 302, a row it rolled back; INSERT OR FAIL failing at its 3rd counts the 2 that stand; a one-row INSERT and an UPDATE that fail move nothing"
  (list (failed 'constraint-unique 0 0 302) (failed 'constraint-unique 2 2 402)
        (failed 'constraint-unique 0 0 7777) (failed 'constraint-unique 0 0 7777))
  (with-counters-db '("create table f(x unique)" "insert into f(rowid, x) values (1, 1)")
    (lambda (path db)
      (measured db (list "insert into f(rowid, x) values (301, 31), (302, 32), (303, 1), (304, 34)"
                         "insert or fail into f(rowid, x) values (401, 41), (402, 42), (403, 1), (404, 44)"
                         "insert into f(rowid, x) values (501, 1)"
                         "update f set x = 1 where x > 40")))))

(test-equal "C6, by execute!: INSERT OR IGNORE that ignores its one row counts 0; one that ignores 1 of 2 counts 1 and names the row it inserted"
  (list (done 0 0 7777) (done 1 1 603))
  (with-counters-db '("create table f(x unique)" "insert into f(rowid, x) values (1, 1)")
    (lambda (path db)
      (measured db (list "insert or ignore into f(rowid, x) values (601, 1)"
                         "insert or ignore into f(rowid, x) values (602, 1), (603, 63)")))))

(test-equal "C7, by execute!: INSERT OR REPLACE replacing one row, by its key, by a UNIQUE, or two at once, counts 1 and names the new row"
  (list (done 1 1 1) (done 1 1 9) (done 1 1 3))
  (with-counters-db '("create table r(id integer primary key, u unique)"
                      "insert into r values (1, 'a'), (2, 'b'), (3, 'c')")
    (lambda (path db)
      (measured db (list "insert or replace into r values (1, 'a2')"
                         "insert or replace into r values (9, 'b')"
                         "insert or replace into r values (3, 'a2')")))))

(test-equal "C8, by execute!: an upsert's DO UPDATE counts 1 and leaves last-insert-rowid; DO NOTHING counts 0; an update and an insert count 2 and name the inserted row; two updates count 2 and leave it"
  (list (done 1 1 7777) (done 0 0 7777) (done 2 2 15) (done 2 2 7777))
  (with-counters-db '("create table up(k unique, v)" "insert into up(rowid, k, v) values (11, 1, 'one')")
    (lambda (path db)
      (measured db (list "insert into up(rowid, k, v) values (12, 1, 'uno') on conflict(k) do update set v = excluded.v"
                         "insert into up(rowid, k, v) values (13, 1, 'eins') on conflict(k) do nothing"
                         "insert into up(rowid, k, v) values (14, 1, 'un'), (15, 5, 'cinq') on conflict(k) do update set v = excluded.v"
                         "insert into up(rowid, k, v) values (16, 5, 'fem'), (17, 1, 'en') on conflict(k) do update set v = excluded.v")))))

(test-equal "C9, by execute!: triggers' own writes count in total-changes alone: an INSERT of 2 rows firing triggers that write 6 counts 2 and moves the total by 8; an UPDATE of 2 firing triggers that write 2 counts 2 and moves it by 4"
  (list (done 2 8 501) (done 2 4 7777))
  (with-counters-db '("create table tg(x)" "create table lg(tag, new_rowid, lir, ch)"
                      "create trigger tg_bi before insert on tg begin insert into lg(rowid, tag, new_rowid, lir, ch) values (null, 'before', new.rowid, last_insert_rowid(), changes()); end"
                      "create trigger tg_ai after insert on tg begin insert into lg(tag, new_rowid, lir, ch) values ('after 1', new.rowid, last_insert_rowid(), changes()); insert into lg(tag, new_rowid, lir, ch) values ('after 2', new.rowid, last_insert_rowid(), changes()); end"
                      "create trigger tg_au after update on tg begin insert into lg(tag, new_rowid, lir, ch) values ('update', new.rowid, last_insert_rowid(), changes()); end")
    (lambda (path db)
      (measured db (list "insert into tg(rowid, x) values (500, 'a'), (501, 'b')"
                         "update tg set x = x || '!'")))))

(test-equal "C10, by execute!: a foreign key's cascade counts in total-changes alone: a DELETE of 1 parent and 3 children counts 1 and moves the total by 4; an UPDATE of 1 parent and 1 child counts 1 and moves it by 2"
  (list (done 1 4 7777) (done 1 2 7777))
  (with-counters-db '("pragma foreign_keys = on"
                      "create table p(id integer primary key)"
                      "create table ch(pid references p(id) on delete cascade on update cascade)"
                      "insert into p values (1), (2)"
                      "insert into ch values (1), (1), (1), (2)")
    (lambda (path db)
      (measured db (list "delete from p where id = 1" "update p set id = 20 where id = 2")))))

(test-equal "C11, by execute!: a WITHOUT ROWID table's INSERT of 2, UPDATE of 2 and REPLACE count 2, 2 and 1, and leave last-insert-rowid as it was"
  (list (done 2 2 7777) (done 2 2 7777) (done 1 1 7777))
  (with-counters-db '("create table wr(k primary key, v) without rowid")
    (lambda (path db)
      (measured db (list "insert into wr values ('a', 1), ('b', 2)"
                         "update wr set v = v + 1"
                         "insert or replace into wr values ('a', 9)")))))

(test-equal "C12, by execute!, which steps to done: an INSERT ... RETURNING of 3 rows counts 3 and names its last row"
  (list (done 3 3 903))
  (with-counters-db '()
    (lambda (path db)
      (measured db (list "insert into t(rowid, x) values (901, 'r1'), (902, 'r2'), (903, 'r3') returning rowid")))))

(test-equal "C12b and C12c, by query-row, which resets after the first row: an INSERT ... RETURNING of 3 answers its first row, then counts 3 at the reset, its 3 rows standing; a DELETE ... RETURNING of 3 counts 3 at the reset"
  (list (list '#(911) '(3 3 913) '#(3)) (list '#(911) '(3 3 7777) '#(0)))
  (with-counters-db '()
    (lambda (path db)
      (let* ((b (begin
                  (prime! db)
                  (let* ((before (total-changes db))
                         (row (query-row db "insert into t(rowid, x) values (911, 'r1'), (912, 'r2'), (913, 'r3') returning rowid"))
                         (after (counters db before)))
                    (list row after (query-row db "select count(*) from t where rowid between 911 and 913")))))
             (c (begin
                  (prime! db)
                  (let* ((before (total-changes db))
                         (row (query-row db "delete from t where rowid between 911 and 913 returning rowid"))
                         (after (counters db before)))
                    (list row after (query-row db "select count(*) from t where rowid between 911 and 913"))))))
        (list b c)))))

(test-equal "C13, by execute!: another connection's writes move none of this connection's counters, while its own count them"
  (list '(2 0 7777) '(3 3 8003) '(2 0 7777))
  (with-counters-db '()
    (lambda (path db)
      (let ((db2 (open-database path)))
        (dynamic-wind
          (lambda () #f)
          (lambda ()
            (prime! db)
            (let* ((before (total-changes db))
                   (before2 (total-changes db2))
                   (i (execute! db2 "insert into t(rowid, x) values (8001, 1), (8002, 2), (8003, 3)"))
                   (after-insert (counters db before))
                   (itself (counters db2 before2))
                   (d (execute! db2 "delete from t where rowid > 8000"))
                   (after-delete (counters db before)))
              (list after-insert itself after-delete)))
          (lambda () (guard (e (#t #f)) (close-database! db2))))))))

(test-equal "C14, by query: a SELECT that answers no row leaves every counter as it was"
  (list '() '(2 0 7777))
  (with-counters-db '()
    (lambda (path db)
      (prime! db)
      (let* ((before (total-changes db))
             (rows (query db "select 1 where 0")))
        (list rows (counters db before))))))

(test-equal "C15, by execute!: rows written in a transaction then rolled back stay in total-changes, and last-insert-rowid names 7002, a row the ROLLBACK undid"
  (list '(2 2 7002) '(2 2 7002))
  (with-counters-db '()
    (lambda (path db)
      (prime! db)
      (let* ((before (total-changes db))
             (b (execute! db "begin"))
             (i (execute! db "insert into t(rowid, x) values (7001, 1), (7002, 2)"))
             (after-insert (counters db before))
             (r (execute! db "rollback"))
             (after-rollback (counters db before)))
        (list after-insert after-rollback)))))

;; --- in-transaction? ----------------------------------------------------------------

(test-equal "in-transaction?, around execute!: #f in autocommit, #t after a deferred BEGIN that has read nothing, #f after COMMIT; #t after BEGIN IMMEDIATE, #f after ROLLBACK; #t after a SAVEPOINT outside a transaction, #f after its RELEASE"
  '(#f #t #f #t #f #t #f)
  (with-counters-db '()
    (lambda (path db)
      (let* ((a (in-transaction? db))
             (b (begin (execute! db "begin") (in-transaction? db)))
             (c (begin (execute! db "commit") (in-transaction? db)))
             (d (begin (execute! db "begin immediate") (in-transaction? db)))
             (e (begin (execute! db "rollback") (in-transaction? db)))
             (f (begin (execute! db "savepoint a") (in-transaction? db)))
             (g (begin (execute! db "release a") (in-transaction? db))))
        (list a b c d e f g)))))

(test-equal "in-transaction? is #f in a fold's procedure while its autocommit read is held at a row, and #t there inside BEGIN"
  '((#f #f) (#t #t))
  (with-counters-db '("insert into t values (1), (2)")
    (lambda (path db)
      (let* ((seen (lambda (acc row) (cons (in-transaction? db) acc)))
             (outside (query-fold db "select x from t" seen '()))
             (b (execute! db "begin"))
             (inside (query-fold db "select x from t" seen '()))
             (c (execute! db "commit")))
        (list outside inside)))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "conveniences-counters")

(exit (suite-exit-status runner))
