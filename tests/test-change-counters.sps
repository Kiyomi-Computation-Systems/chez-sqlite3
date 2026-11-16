#!r6rs
;;; The suite for the change counters and in-transaction? (ADR-0016, decision
;;; 8; the M3 plan, section 4.1), in (chez-sqlite3 private connection): every
;;; case of M3's research, single B2, through them, and single B1's items 1
;;; and 2 through in-transaction?. Not yet exported from (chez-sqlite3), whose
;;; names and docs come with the conveniences.
;;;
;;;   the cases   as the research's counters.c runs them: before each
;;;               statement, an INSERT OR REPLACE of two rows into z sets
;;;               changes to 2 and last-insert-rowid to 7777, values no
;;;               statement measured gives by itself; the statement runs to
;;;               its end, and the three counters are read after its last
;;;               step and again after its finalize, total-changes as its
;;;               move across the statement. Each row asserts what the
;;;               research's output gives, alike on 3.53.1 and 3.45.1
;;;   the raises  each counter checks, in order, a database, its owning
;;;               thread and that it is open, naming itself, at depth 1
;;;
;;; The loading procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them. Statements run through M2's
;;; statement tier, the conveniences being part B's.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) fork-thread make-mutex with-mutex sleep make-time get-thread-id
              disable-interrupts enable-interrupts)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-wrong-thread? sqlite-wrong-thread-owner
              sqlite-wrong-thread-caller sqlite-closed?))

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
(define changes (reach connection-library 'changes))
(define total-changes (reach connection-library 'total-changes))
(define last-insert-rowid (reach connection-library 'last-insert-rowid))
(define in-transaction? (reach connection-library 'in-transaction?))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define step! (reach statement-library 'step!))
(define reset! (reach statement-library 'reset!))
(define column-value (reach '(chez-sqlite3 private statement-values) 'column-value))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))
(define (message-of e) (if (message-condition? e) 'message 'no-message))

;; what-raised : Any -> Any
(define (what-raised e)
  (cond ((sqlite-error? e) (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)))
        ((sqlite-wrong-thread? e)
         (list 'wrong-thread (who-of e) (message-of e)
               (sqlite-wrong-thread-owner e) (sqlite-wrong-thread-caller e)))
        ((sqlite-closed? e) (list 'closed (who-of e) (message-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

;; undo! : (Listof Any) (Listof Any) -> Void
(define (undo! statements databases)
  (for-each (lambda (s) (guard (e (#t #f)) (finalize-statement! s))) statements)
  (for-each (lambda (db) (guard (e (#t #f)) (close-database! db))) databases))

;; exec! : Database String -> Any
;; SQL prepared, stepped to its end and finalized.
(define (exec! db sql)
  (let ((st (prepare-statement db sql)))
    (guard (e (#t (finalize-statement! st) (raise e)))
      (let loop () (when (step! st) (loop))))
    (finalize-statement! st)))

;; setup! : Database (Listof String) -> Void
;; Each of STATEMENTS run by exec!, in order.
(define (setup! db statements)
  (for-each (lambda (sql) (exec! db sql)) statements))

;; in-dir : (String -> Any) -> Any
(define (in-dir proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory proc)))

;; with-counters-db : (List String) (String Database -> Any) -> Any
;; PROC's answer, or what it raised, given a file c.db in a temporary
;; directory, made with the research's tables z and t and then SETUP, and a
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
         (lambda () (when db (undo! '() (list db)))))))))

;; prime! : Database -> Void
;; changes 2 and last-insert-rowid 7777 (counters.c's prime).
(define (prime! db)
  (exec! db "insert or replace into z(rowid, v) values (7776, 'p'), (7777, 'p')"))

;; counters : Database Integer -> (List Integer Integer Integer)
;; changes, total-changes' move since BEFORE, and last-insert-rowid, read in
;; that order.
(define (counters db before)
  (let* ((c (changes db))
         (t (- (total-changes db) before))
         (r (last-insert-rowid db)))
    (list c t r)))

;; measure : Database String -> (List Any (List Integer Integer Integer) Any)
;; counters.c's measure: DB primed, SQL prepared and stepped to its end; how
;; the steps ended, done or the failure's extended code; the counters after
;; the last step; and after the finalize, same when they did not move.
(define (measure db sql)
  (prime! db)
  (let* ((before (total-changes db))
         (st (prepare-statement db sql))
         (ended (let loop ()
                  (let ((r (attempt (lambda () (step! st)))))
                    (cond ((eq? r #t) (loop))
                          ((eq? r #f) 'done)
                          ((and (pair? r) (pair? (cadr r)) (eq? (car (cadr r)) 'sqlite-error))
                           (list-ref (cadr r) 3))
                          (else r)))))
         (after-step (counters db before))
         (finalized (attempt (lambda () (finalize-statement! st))))
         (after-finalize (counters db before)))
    (list ended after-step (if (equal? after-step after-finalize) 'same after-finalize))))

;; measured : Database (Listof String) -> (Listof Any)
;; measure of each of STATEMENTS, in order.
(define (measured db statements)
  (let loop ((rest statements) (found '()))
    (if (null? rest)
        (reverse found)
        (loop (cdr rest) (cons (measure db (car rest)) found)))))

(define (done c t r) (list 'done (list c t r) 'same))
(define (failed code c t r) (list code (list c t r) 'same))

;; interrupt-depth : -> Positive-Integer
(define (interrupt-depth)
  (let ((n (disable-interrupts)))
    (enable-interrupts)
    n))

;; handler-depth : (-> Any) -> (U (List 'raised-at-depth Symbol Any) (List 'no-raise Any))
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
      (lambda () (list 'no-raise (thunk)))))))

(define (at-depth-1 what) (list 'raised-at-depth 'depth-1 what))

;; in-thread : (-> Any) -> Any
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
(define (ids x main thread)
  (cond ((eqv? x main) 'main)
        ((eqv? x thread) 'the-thread)
        ((pair? x) (cons (ids (car x) main thread) (ids (cdr x) main thread)))
        (else x)))

;; from-another-thread : (-> Any) -> Any
(define (from-another-thread thunk)
  (let* ((main (get-thread-id))
         (a (in-thread (lambda () (attempt thunk)))))
    (if (and (list? a) (= (length a) 3) (not (eqv? (caddr a) main)))
        (ids (cadr a) main (caddr a))
        (list 'not-another-thread a))))

(test-begin "change-counters")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

;; --- single B2, case by case ------------------------------------------------------------------
;; Each row's expected values are the research's output for its case, on
;; 3.53.1 and 3.45.1 alike (.plans/research/m3-plan/single/counters-*.txt).

(test-equal "C0: a fresh connection's counters are 0, 0 and 0"
  '(0 0 0)
  (in-dir (lambda (dir)
            (let ((db (open-database (string-append dir "/c.db"))))
              (let ((r (attempt (lambda () (list (changes db) (total-changes db) (last-insert-rowid db))))))
                (undo! '() (list db))
                r)))))

(test-equal "C1: an INSERT of 3 rows counts 3 and names its last row; an UPDATE of 3, then of none, counts 3, then 0; a DELETE of 2 counts 2; an INSERT ... SELECT of 5 counts 5 and names its last row; neither UPDATE nor DELETE moves last-insert-rowid"
  (list (done 3 3 103) (done 3 3 7777) (done 0 0 7777) (done 2 2 7777) (done 5 5 205))
  (with-counters-db '()
    (lambda (path db)
      (measured db (list "insert into t(rowid, x) values (101, 1), (102, 2), (103, 3)"
                         "update t set x = x + 10"
                         "update t set x = x where x > 1000"
                         "delete from t where x > 11"
                         "insert into t(rowid, x) select 200 + value, value from (with recursive n(value) as (select 1 union all select value + 1 from n where value < 5) select value from n)")))))

(test-equal "C2: DELETE FROM t with no WHERE counts the 6 rows it deleted, and 0 on an empty table"
  (list (done 6 6 7777) (done 0 0 7777))
  (with-counters-db '("insert into t values (1), (2), (3), (4), (5), (6)")
    (lambda (path db)
      (measured db (list "delete from t" "delete from t")))))

(test-equal "C3: DDL leaves changes and last-insert-rowid as they were, and moves total-changes by nothing: CREATE TABLE, CREATE INDEX, ADD COLUMN, CREATE VIEW, DROP TABLE of 4 rows, DROP INDEX"
  (list (done 2 0 7777) (done 2 0 7777) (done 2 0 7777) (done 2 0 7777) (done 2 0 7777) (done 2 0 7777))
  (with-counters-db '("insert into t values (1), (2), (3)")
    (lambda (path db)
      (let* ((a (measured db (list "create table d(x)" "create index ti on t(x)" "alter table t add column y"
                                   "create view vw as select x from t")))
             (s (exec! db "insert into d values (1), (2), (3), (4)"))
             (b (measured db (list "drop table d" "drop index ti"))))
        (append a b)))))

(test-equal "C4: a SELECT, PRAGMA user_version = 5, BEGIN and COMMIT leave every counter as it was"
  (list (done 2 0 7777) (done 2 0 7777) (done 2 0 7777) (done 2 0 7777))
  (with-counters-db '("insert into t values (1), (2), (3)")
    (lambda (path db)
      (measured db (list "select x from t" "pragma user_version = 5" "begin" "commit")))))

(test-equal "C5: an INSERT failing at its 3rd row of 4 counts 0, and last-insert-rowid names 302, a row it rolled back; INSERT OR FAIL failing at its 3rd counts the 2 that stand, 402 last; a one-row INSERT and an UPDATE that fail move nothing"
  (list (failed 'constraint-unique 0 0 302) (failed 'constraint-unique 2 2 402)
        (failed 'constraint-unique 0 0 7777) (failed 'constraint-unique 0 0 7777))
  (with-counters-db '("create table f(x unique)" "insert into f(rowid, x) values (1, 1)")
    (lambda (path db)
      (measured db (list "insert into f(rowid, x) values (301, 31), (302, 32), (303, 1), (304, 34)"
                         "insert or fail into f(rowid, x) values (401, 41), (402, 42), (403, 1), (404, 44)"
                         "insert into f(rowid, x) values (501, 1)"
                         "update f set x = 1 where x > 40")))))

(test-equal "C6: INSERT OR IGNORE that ignores its one row counts 0 and leaves last-insert-rowid; one that ignores 1 of 2 counts 1 and names the row it inserted"
  (list (done 0 0 7777) (done 1 1 603))
  (with-counters-db '("create table f(x unique)" "insert into f(rowid, x) values (1, 1)")
    (lambda (path db)
      (measured db (list "insert or ignore into f(rowid, x) values (601, 1)"
                         "insert or ignore into f(rowid, x) values (602, 1), (603, 63)")))))

(test-equal "C7: INSERT OR REPLACE replacing one row, by its key, by a UNIQUE, or two at once, counts 1 and names the new row"
  (list (done 1 1 1) (done 1 1 9) (done 1 1 3))
  (with-counters-db '("create table r(id integer primary key, u unique)"
                      "insert into r values (1, 'a'), (2, 'b'), (3, 'c')")
    (lambda (path db)
      (measured db (list "insert or replace into r values (1, 'a2')"
                         "insert or replace into r values (9, 'b')"
                         "insert or replace into r values (3, 'a2')")))))

(test-equal "C8: an upsert's DO UPDATE counts 1 and leaves last-insert-rowid; DO NOTHING counts 0; an update and an insert count 2 and name the inserted row; two updates count 2 and leave it"
  (list (done 1 1 7777) (done 0 0 7777) (done 2 2 15) (done 2 2 7777))
  (with-counters-db '("create table up(k unique, v)" "insert into up(rowid, k, v) values (11, 1, 'one')")
    (lambda (path db)
      (measured db (list "insert into up(rowid, k, v) values (12, 1, 'uno') on conflict(k) do update set v = excluded.v"
                         "insert into up(rowid, k, v) values (13, 1, 'eins') on conflict(k) do nothing"
                         "insert into up(rowid, k, v) values (14, 1, 'un'), (15, 5, 'cinq') on conflict(k) do update set v = excluded.v"
                         "insert into up(rowid, k, v) values (16, 5, 'fem'), (17, 1, 'en') on conflict(k) do update set v = excluded.v")))))

(test-equal "C9: triggers' own writes count in total-changes alone: an INSERT of 2 rows firing triggers that write 6 counts 2 and moves the total by 8, naming the outer statement's last row; an UPDATE of 2 firing triggers that write 2 counts 2 and moves it by 4"
  (list (done 2 8 501) (done 2 4 7777))
  (with-counters-db '("create table tg(x)" "create table lg(tag, new_rowid, lir, ch)"
                      "create trigger tg_bi before insert on tg begin insert into lg(rowid, tag, new_rowid, lir, ch) values (null, 'before', new.rowid, last_insert_rowid(), changes()); end"
                      "create trigger tg_ai after insert on tg begin insert into lg(tag, new_rowid, lir, ch) values ('after 1', new.rowid, last_insert_rowid(), changes()); insert into lg(tag, new_rowid, lir, ch) values ('after 2', new.rowid, last_insert_rowid(), changes()); end"
                      "create trigger tg_au after update on tg begin insert into lg(tag, new_rowid, lir, ch) values ('update', new.rowid, last_insert_rowid(), changes()); end")
    (lambda (path db)
      (measured db (list "insert into tg(rowid, x) values (500, 'a'), (501, 'b')"
                         "update tg set x = x || '!'")))))

(test-equal "C10: a foreign key's cascade counts in total-changes alone: a DELETE of 1 parent and 3 children counts 1 and moves the total by 4; an UPDATE of 1 parent and 1 child counts 1 and moves it by 2"
  (list (done 1 4 7777) (done 1 2 7777))
  (with-counters-db '("pragma foreign_keys = on"
                      "create table p(id integer primary key)"
                      "create table ch(pid references p(id) on delete cascade on update cascade)"
                      "insert into p values (1), (2)"
                      "insert into ch values (1), (1), (1), (2)")
    (lambda (path db)
      (measured db (list "delete from p where id = 1" "update p set id = 20 where id = 2")))))

(test-equal "C11: a WITHOUT ROWID table's INSERT of 2, UPDATE of 2 and REPLACE count 2, 2 and 1, and leave last-insert-rowid as it was"
  (list (done 2 2 7777) (done 2 2 7777) (done 1 1 7777))
  (with-counters-db '("create table wr(k primary key, v) without rowid")
    (lambda (path db)
      (measured db (list "insert into wr values ('a', 1), ('b', 2)"
                         "update wr set v = v + 1"
                         "insert or replace into wr values ('a', 9)")))))

(test-equal "C12: an INSERT ... RETURNING of 3 rows names its last row at its first step, and moves changes and total-changes only at the step that answers done; a reset after then leaves them"
  (list '(2 0 7777) (list #t '(2 0 903)) (list #t '(2 0 903)) (list #t '(2 0 903)) (list #f '(3 3 903))
        '(3 3 903))
  (with-counters-db '()
    (lambda (path db)
      (prime! db)
      (let* ((before (total-changes db))
             (st (prepare-statement db "insert into t(rowid, x) values (901, 'r1'), (902, 'r2'), (903, 'r3') returning rowid"))
             (prepared (counters db before))
             (s1 (let ((r (step! st))) (list r (counters db before))))
             (s2 (let ((r (step! st))) (list r (counters db before))))
             (s3 (let ((r (step! st))) (list r (counters db before))))
             (s4 (let ((r (step! st))) (list r (counters db before))))
             (rs (begin (reset! st) (counters db before))))
        (finalize-statement! st)
        (list prepared s1 s2 s3 s4 rs)))))

(test-equal "C12b and C12c: an INSERT ... RETURNING of 3 stepped once, then reset, moves the counters at the reset, its 3 rows standing; a DELETE ... RETURNING of 3 stepped once moves them at its finalize"
  (list (list '(2 0 913) '(3 3 913) 3) (list '(2 0 7777) '(3 3 7777)))
  (with-counters-db '()
    (lambda (path db)
      (let* ((b (begin
                  (prime! db)
                  (let* ((before (total-changes db))
                         (st (prepare-statement db "insert into t(rowid, x) values (911, 'r1'), (912, 'r2'), (913, 'r3') returning rowid"))
                         (s1 (begin (step! st) (counters db before)))
                         (rs (begin (reset! st) (counters db before))))
                    (finalize-statement! st)
                    (let* ((q (prepare-statement db "select count(*) from t where rowid between 911 and 913"))
                           (n (begin (step! q) (column-value q 0))))
                      (finalize-statement! q)
                      (list s1 rs n)))))
             (c (begin
                  (prime! db)
                  (let* ((before (total-changes db))
                         (st (prepare-statement db "delete from t where rowid between 911 and 913 returning rowid"))
                         (s1 (begin (step! st) (counters db before)))
                         (fin (begin (finalize-statement! st) (counters db before))))
                    (list s1 fin)))))
        (list b c)))))

(test-equal "C13: another connection's writes move none of this connection's counters, while its own count them"
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
                   (i (exec! db2 "insert into t(rowid, x) values (8001, 1), (8002, 2), (8003, 3)"))
                   (after-insert (counters db before))
                   (itself (counters db2 before2))
                   (d (exec! db2 "delete from t where rowid > 8000"))
                   (after-delete (counters db before)))
              (list after-insert itself after-delete)))
          (lambda () (undo! '() (list db2))))))))

(test-equal "C14: a SELECT that answers no row, and an INSERT prepared and finalized unstepped, leave every counter as it was"
  (list (done 2 0 7777) '(2 0 7777))
  (with-counters-db '()
    (lambda (path db)
      (let* ((a (measure db "select 1 where 0"))
             (b (begin
                  (prime! db)
                  (let* ((before (total-changes db))
                         (st (prepare-statement db "insert into t values (1)")))
                    (finalize-statement! st)
                    (counters db before)))))
        (list a b)))))

(test-equal "C15: rows written in a transaction then rolled back stay in total-changes, and last-insert-rowid names 7002, a row the ROLLBACK undid"
  (list '(2 2 7002) '(2 2 7002))
  (with-counters-db '()
    (lambda (path db)
      (prime! db)
      (let* ((before (total-changes db))
             (b (exec! db "begin"))
             (i (exec! db "insert into t(rowid, x) values (7001, 1), (7002, 2)"))
             (after-insert (counters db before))
             (r (exec! db "rollback"))
             (after-rollback (counters db before)))
        (list after-insert after-rollback)))))

;; --- in-transaction?, by single B1's items 1 and 2 ------------------------------------------------

(test-equal "in-transaction? is #f in autocommit, #t after a deferred BEGIN that has read nothing, #f after COMMIT; #t after BEGIN IMMEDIATE, #f after ROLLBACK; #t after a SAVEPOINT outside a transaction, #f after its RELEASE"
  '(#f #t #f #t #f #t #f)
  (with-counters-db '()
    (lambda (path db)
      (let* ((a (in-transaction? db))
             (b (begin (exec! db "begin") (in-transaction? db)))
             (c (begin (exec! db "commit") (in-transaction? db)))
             (d (begin (exec! db "begin immediate") (in-transaction? db)))
             (e (begin (exec! db "rollback") (in-transaction? db)))
             (f (begin (exec! db "savepoint a") (in-transaction? db)))
             (g (begin (exec! db "release a") (in-transaction? db))))
        (list a b c d e f g)))))

(test-equal "in-transaction? is #f while an autocommit SELECT holds a read at a row, and #t while one holds a row inside BEGIN"
  '(#t #f #t)
  (with-counters-db '("insert into t values (1), (2)")
    (lambda (path db)
      (let* ((st (prepare-statement db "select x from t"))
             (row (step! st))
             (holding (in-transaction? db))
             (f (finalize-statement! st))
             (b (exec! db "begin"))
             (st2 (prepare-statement db "select x from t"))
             (row2 (step! st2))
             (inside (in-transaction? db)))
        (finalize-statement! st2)
        (exec! db "commit")
        (list row holding inside)))))

;; --- the raises ---------------------------------------------------------------------------------

(test-equal "each counter, and in-transaction?, checks a database, its owning thread and that it is open, in that order, each raise naming it, at depth 1"
  (list (list (at-depth-1 '(assertion-violation changes (not-a-database x)))
              (at-depth-1 '(wrong-thread changes message main the-thread))
              (at-depth-1 '(closed changes message)))
        (list (at-depth-1 '(assertion-violation total-changes (not-a-database x)))
              (at-depth-1 '(wrong-thread total-changes message main the-thread))
              (at-depth-1 '(closed total-changes message)))
        (list (at-depth-1 '(assertion-violation last-insert-rowid (not-a-database x)))
              (at-depth-1 '(wrong-thread last-insert-rowid message main the-thread))
              (at-depth-1 '(closed last-insert-rowid message)))
        (list (at-depth-1 '(assertion-violation in-transaction? (not-a-database x)))
              (at-depth-1 '(wrong-thread in-transaction? message main the-thread))
              (at-depth-1 '(closed in-transaction? message)))
        zero-counts)
  (let ((row (lambda (counter)
               (let* ((a (handler-depth (lambda () (counter 'x))))
                      (db (open-database ":memory:"))
                      (b (from-another-thread (lambda () (handler-depth (lambda () (counter db))))))
                      (c (begin (close-database! db) (handler-depth (lambda () (counter db))))))
                 (list a b c)))))
    (let* ((a (row changes))
           (b (row total-changes))
           (c (row last-insert-rowid))
           (d (row in-transaction?)))
      (list a b c d (native-counts)))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "change-counters")

(exit (suite-exit-status runner))
