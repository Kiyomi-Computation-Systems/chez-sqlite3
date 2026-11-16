#!r6rs
;;; nomem-rig.sps: a prototype of M3 slice 4's NOMEM rows (the M3 plan,
;;; section 5 item 4), through the library as the suites load it.
;;;
;;;   CHEZ_SQLITE3_LIBRARY=LIB $CHEZ --libdirs src:tests:build/scheme-libs \
;;;     --program nomem-rig.sps DIR NUMBER SOURCE-ID
;;;
;;; DIR is a fresh directory for the databases; NUMBER and SOURCE-ID are the
;;; header's, and the probe refuses a library that answers others.
;;;
;;; As test-statement-values-nomem does, it reaches (chez-sqlite3) and its
;;; private libraries through eval, and binds sqlite3_hard_heap_limit64
;;; itself, after the load, as M2's suites bind sqlite3_limit. It binds
;;; sqlite3_soft_heap_limit64 too: lifting the hard limit alone leaves
;;; SQLite's memory pressure on for the process (row X1 below, and
;;; peer-view.c J1 against J2), so the rig lifts both, hard then soft.
;;;
;;; Inside a transaction, BEGIN IMMEDIATE and a marker row (nested: then
;;; SAVEPOINT chez_sqlite3_1 and a second marker), the limit is set to
;;; sqlite3_memory_used plus 1,000 bytes around exactly one call:
;;;
;;;   S rows   step! of a statement prepared before the limit was set
;;;            (single txn-special N1 to N4; T12)
;;;   R rows   column-value of a statement stepped to its row before; 100,000
;;;            bytes of TEXT bound with their length, which sqlite3_column_text
;;;            must copy to add its NUL (M2 slice 4's heap-limit.c; single G2
;;;            to G5 read by sqlite3_column_text, as the library reads TEXT)
;;;
;;; For each: what the call raised; whether the limit read straight after the
;;; call is still the one set (it was in force across the call, the step's
;;; own statement rollback among it: single T12); the limits read once
;;; lifted; the statement's state; autocommit straight after the call; then
;;; the statement finished, as a convenience or call-with-statement would,
;;; by reset! or finalize-statement!, and what that raised; autocommit after
;;; it; then what with-transaction's exit would do, by ADR-0017: autocommit
;;; 0, the level rolled back; else nothing; and what this connection and a
;;; second one see.
;;;
;;; Where SQLite keeps no memory count, as on a build with
;;; SQLITE_DEFAULT_MEMSTATUS=0, like Apple's, the limit is kept but not
;;; enforced (M2 slice 4's research). The probe tells by the memory check's
;;; own control: the count read while a :memory: connection is open is above
;;; 0, or not. Where it is not, every row is named UNAVAILABLE and none runs;
;;; the probe shows instead that the limit is kept and the read under it
;;; comes back whole.
;;;
;;; Effects run in order, through let*; nothing asserted depends on the order
;;; of a call's arguments (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (only (chezscheme) foreign-procedure command-line-arguments)
        (only (chez-sqlite3-testing) describe)
        (chez-sqlite3 private counters))

(define (say . xs)
  (for-each (lambda (x) (if (string? x) (display x) (write x))) xs)
  (newline))

;; --- reached through eval, as the suites reach them --------------------------------------

(define public-load
  (guard (e (#t (list 'raised (describe e))))
    (eval '(sqlite-version) (environment '(chez-sqlite3)))
    'loaded))

(define (reach library name)
  (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
    (eval name (environment library))))

(define statement-library '(chez-sqlite3 private statement))
(define values-library '(chez-sqlite3 private statement-values))
(define native-library '(chez-sqlite3 private native))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define sqlite-version-number (reach '(chez-sqlite3) 'sqlite-version-number))
(define sqlite-source-id (reach '(chez-sqlite3) 'sqlite-source-id))
(define sqlite-version (reach '(chez-sqlite3) 'sqlite-version))
(define sqlite-error? (reach '(chez-sqlite3) 'sqlite-error?))
(define sqlite-busy? (reach '(chez-sqlite3) 'sqlite-busy?))
(define sqlite-error-code (reach '(chez-sqlite3) 'sqlite-error-code))
(define sqlite-error-extended-code (reach '(chez-sqlite3) 'sqlite-error-extended-code))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define step! (reach statement-library 'step!))
(define reset! (reach statement-library 'reset!))
(define statement-state (reach statement-library 'statement-state))
(define bind! (reach values-library 'bind!))
(define column-value (reach values-library 'column-value))
(define sqlite3-memory-used (reach native-library 'sqlite3-memory-used))
(define sqlite3-get-autocommit (reach native-library 'sqlite3-get-autocommit))
(define sqlite3-extended-errcode (reach native-library 'sqlite3-extended-errcode))

;; --- bound here, after the load ------------------------------------------------------------

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this probe could not bind it" (describe e)))))
       form))))

;; sqlite3_int64 sqlite3_hard_heap_limit64(sqlite3_int64 N): the limit before;
;; a negative N reads it; 0 is no limit.
(define hard-limit (bound 'sqlite3_hard_heap_limit64
                          (foreign-procedure "sqlite3_hard_heap_limit64" (integer-64) integer-64)))
;; sqlite3_int64 sqlite3_soft_heap_limit64(sqlite3_int64 N): the same, soft.
(define soft-limit (bound 'sqlite3_soft_heap_limit64
                          (foreign-procedure "sqlite3_soft_heap_limit64" (integer-64) integer-64)))

;; --- helpers -------------------------------------------------------------------------------

(define (what-raised e)
  (cond ((sqlite-error? e)
         (list (if (sqlite-busy? e) 'sqlite-busy 'sqlite-error)
               (if (who-condition? e) (condition-who e) 'no-who)
               (sqlite-error-code e) (sqlite-error-extended-code e)))
        ((assertion-violation? e)
         (list 'assertion-violation (if (who-condition? e) (condition-who e) 'no-who)
               (if (irritants-condition? e) (condition-irritants e) '())))
        (else (list 'other (describe e)))))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (let ((v (thunk)))
      (if (eq? v (if #f #f)) 'no-value (list 'answered v)))))

(define (with-handle db proc) (call-with-open-handle 'nomem-rig db proc))
(define (autocommit db) (with-handle db sqlite3-get-autocommit))
(define (extended db) (with-handle db sqlite3-extended-errcode))

;; exec! : Database String -> Void
(define (exec! db sql)
  (let* ((st (prepare-statement db sql))
         (r (guard (e (#t (finalize-statement! st) (raise e)))
              (let loop () (when (step! st) (loop))))))
    (finalize-statement! st)))

;; one-value : Database String -> Any
(define (one-value db sql)
  (let* ((st (prepare-statement db sql))
         (v (guard (e (#t (finalize-statement! st) (raise e)))
              (step! st)
              (column-value st 0))))
    (finalize-statement! st)
    v))

(define (markers db)
  (attempt (lambda () (one-value db "select coalesce(group_concat(x, ','), '(none)') from (select x from t order by x)"))))

(define big-text (make-string 100000 #\a))

;; around-one-call : (-> Any) -> (List Any Symbol (List 'hard Integer 'soft Integer))
;; THUNK's answer or raise, run with the hard heap limit at the memory used
;; now plus 1,000; whether the limit read straight after THUNK is the one
;; set; and both limits read after both are lifted, hard then soft, however
;; THUNK ends.
(define (around-one-call thunk)
  (let ((target #f) (kept #f))
    (let* ((r (dynamic-wind
                (lambda () (set! target (+ (sqlite3-memory-used) 1000)) (hard-limit target))
                (lambda ()
                  (let ((v (attempt thunk)))
                    (set! kept (hard-limit -1))
                    v))
                (lambda () (hard-limit 0) (soft-limit 0))))
           (hard (hard-limit -1))
           (soft (soft-limit -1)))
      (list r
            (if (eqv? kept target) 'the-limit-in-force-when-the-call-returned 'the-limit-changed)
            (list 'hard hard 'soft soft)))))

;; --- whether the limit is enforced here ------------------------------------------------------

;; memory-kept : (U Boolean (List 'raised String))
;; The memory check's control: #t when SQLite's count is above 0 while a
;; :memory: connection is open; #f where it keeps no count.
(define memory-kept
  (guard (e (#t (list 'raised (describe e))))
    (let* ((db (open-database ":memory:"))
           (used (sqlite3-memory-used)))
      (close-database! db)
      (> used 0))))

;; --- the cases ---------------------------------------------------------------------------------

(define dir (car (command-line-arguments)))
(define counter 0)
(define (fresh-path)
  (set! counter (+ counter 1))
  (string-append dir "/case-" (number->string counter) ".db"))

;; with-case : Symbol (Database Database -> Any) -> Any
;; A fresh file: t, b and src, 10 rows of 3,000 bytes; DB and DB2 on it,
;; both closed after PROC.
(define (with-case nested proc)
  (let* ((path (fresh-path))
         (db (open-database path))
         (setup (begin (exec! db "create table t (x)")
                       (exec! db "create table b (x)")
                       (exec! db "create table src (x)")
                       (exec! db "insert into src select replace(hex(zeroblob(1500)), '0', 'a') from (with recursive n(i) as (select 1 union all select i + 1 from n where i < 10) select i from n)")))
         (db2 (open-database path))
         (begun (begin (exec! db "BEGIN IMMEDIATE")
                       (exec! db "insert into t values ('outer')")
                       (when nested
                         (exec! db "SAVEPOINT chez_sqlite3_1")
                         (exec! db "insert into t values ('inner')"))))
         (r (guard (e (#t (list 'case-raised (describe e)))) (proc db db2))))
    (guard (e (#t #f)) (close-database! db2))
    (guard (e (#t #f)) (close-database! db))
    r))

;; the-exit : Database Boolean -> (Listof Any)
;; What with-transaction would issue after the body raised: autocommit 0, the
;; level rolled back; else nothing. Then, nested, the caller's outer level
;; committed when it is still open.
(define (the-exit db db2 nested)
  (let* ((a (autocommit db))
         (issued (if (eqv? a 0)
                     (if nested
                         (list 'rolled-back
                               (attempt (lambda () (exec! db "ROLLBACK TO chez_sqlite3_1")))
                               (attempt (lambda () (exec! db "RELEASE chez_sqlite3_1"))))
                         (list 'rolled-back (attempt (lambda () (exec! db "ROLLBACK")))))
                     '(nothing-issued)))
         (after (autocommit db))
         (seen (markers db))
         (seen2 (markers db2))
         (outer (if (and nested (eqv? after 0))
                    (let* ((c (attempt (lambda () (exec! db "COMMIT"))))
                           (s2 (markers db2)))
                      (list 'the-caller-commits-the-outer-level c 'db2-then s2))
                    '())))
    (list (list 'autocommit-read a) issued (list 'autocommit-after after)
          (list 'db-sees seen) (list 'db2-sees seen2) outer)))

(define (step-case label sql nested)
  (with-case nested
    (lambda (db db2)
      (let* ((st (prepare-statement db sql))
             (call (around-one-call (lambda () (step! st))))
             (state (statement-state st))
             (a (autocommit db))
             (finish (attempt (lambda () (finalize-statement! st))))
             (a2 (autocommit db))
             (ex (the-exit db db2 nested)))
        (list label (if nested 'nested 'outer) sql
              (list 'the-step (car call)) (cadr call) (caddr call)
              (list 'state state) (list 'autocommit-straight-after a)
              (list 'finalize-statement! finish) (list 'autocommit-after-it a2)
              (cons 'the-exit ex))))))

(define (read-case label sql finish-name nested)
  (with-case nested
    (lambda (db db2)
      (let* ((st (prepare-statement db sql))
             (b (bind! st 1 big-text))
             (s (step! st))
             (call (around-one-call (lambda () (column-value st 0))))
             (state (statement-state st))
             (a (autocommit db))
             (finish (attempt (lambda () (if (eq? finish-name 'reset!) (reset! st) (finalize-statement! st)))))
             (a2 (autocommit db))
             (done (when (eq? finish-name 'reset!) (finalize-statement! st)))
             (ex (the-exit db db2 nested)))
        (list label (if nested 'nested 'outer) sql
              (list 'the-read (car call)) (cadr call) (caddr call)
              (list 'state state) (list 'autocommit-straight-after a)
              (list finish-name finish) (list 'autocommit-after-it a2)
              (cons 'the-exit ex))))))

(define (show-case c)
  (if (and (pair? c) (string? (car c)))
      (begin
        (say "")
        (say (car c) ", " (cadr c) ": " (caddr c))
        (for-each (lambda (item) (display "  ") (write item) (newline)) (cdddr c)))
      (begin (say "") (say "CASE RAISED: " c))))

;; X1, X2: the trap. A NOMEM in a :memory: connection of its own; the hard
;; limit lifted, and in X2 the soft limit set to 0 after it. Then a fresh
;; file set up, a second connection, BEGIN IMMEDIATE and a write that then
;; reads src, and the second connection's read beside it (peer-view.c's
;; J1 and J2, through the library). The NOMEM comes first: a cache that
;; already holds src's pages, clean, fetches none, and spills nothing.
(define (trap-case label soft-too)
  (let* ((m (open-database ":memory:"))
         (st (prepare-statement m "select randomblob(100000)"))
         (target (+ (sqlite3-memory-used) 1000))
         (set (hard-limit target))
         (nomem (attempt (lambda () (step! st))))
         (lift (hard-limit 0))
         (lift-soft (when soft-too (soft-limit 0)))
         (limits (list 'hard (hard-limit -1) 'soft (soft-limit -1)))
         (f (finalize-statement! st))
         (c (close-database! m))
         (path (fresh-path))
         (db (open-database path))
         (setup (begin (exec! db "create table t (x)")
                       (exec! db "create table src (x)")
                       (exec! db "insert into src select replace(hex(zeroblob(1500)), '0', 'a') from (with recursive n(i) as (select 1 union all select i + 1 from n where i < 10) select i from n)")))
         (db2 (open-database path))
         (begun (exec! db "BEGIN IMMEDIATE"))
         (w (exec! db "insert into t values ('outer')"))
         (before (attempt (lambda () (one-value db2 "select count(*) from t"))))
         (r (attempt (lambda () (one-value db "select count(*) from src"))))
         (peer (attempt (lambda () (one-value db2 "select count(*) from t"))))
         (end (exec! db "ROLLBACK"))
         (peer-after (attempt (lambda () (one-value db2 "select count(*) from t"))))
         (soft-anyway (soft-limit 0)))
    (close-database! db2)
    (close-database! db)
    (list label 'outer
          (if soft-too
              "a NOMEM, then sqlite3_hard_heap_limit64(0) and sqlite3_soft_heap_limit64(0)"
              "a NOMEM, then sqlite3_hard_heap_limit64(0) alone")
          (list 'the-nomem nomem) (cons 'limits-after-the-lift limits)
          (list 'db2-reads-t-after-the-write peer-before-label before)
          (list 'db-in-begin-immediate-reads-src r)
          (list 'db2-reads-t-then peer)
          (list 'db2-reads-t-after-the-rollback peer-after))))

(define peer-before-label 'before-db-reads-src)

;; --- the run ------------------------------------------------------------------------------------

(say "libversion: " (sqlite-version))
(say "sourceid: " (sqlite-source-id))
(let ((args (command-line-arguments)))
  (unless (and (= (length args) 3)
               (equal? (cadr args) (number->string (sqlite-version-number)))
               (equal? (caddr args) (sqlite-source-id)))
    (say "REFUSED: the library is not the header's: " args)
    (exit 2)))
(say "load: " public-load)
(say "the memory count: "
     (cond ((eq? memory-kept #t) "kept: the count is above 0 while a :memory: connection is open")
           ((eq? memory-kept #f) "NOT kept: the count is 0 while a :memory: connection is open")
           (else memory-kept)))

(define rows
  (list (list 'step "S1" "select randomblob(100000) from src limit 1")
        (list 'step "S2" "select randomblob(100000)")
        (list 'step "S3" "insert into b select randomblob(100000) from src limit 3")
        (list 'step "S4" "insert into b values (randomblob(100000))")
        (list 'read "R1" "select ?1 from src limit 1" 'reset!)
        (list 'read "R2" "select ?1 from src limit 1" 'finalize-statement!)
        (list 'read "R3" "select ?1" 'reset!)
        (list 'read "R4" "select ?1" 'finalize-statement!)))

(if (eq? memory-kept #t)
    (begin
      (for-each
       (lambda (nested)
         (for-each
          (lambda (row)
            (show-case
             (if (eq? (car row) 'step)
                 (step-case (cadr row) (caddr row) nested)
                 (read-case (cadr row) (caddr row) (cadddr row) nested))))
          rows))
       '(#f #t))
      (show-case (trap-case "X1" #f))
      (show-case (trap-case "X2" #t)))
    (begin
      (for-each
       (lambda (row)
         (say "UNAVAILABLE " (cadr row) ": this libsqlite3 keeps no memory count, so a hard heap limit is not enforced"))
       rows)
      (say "UNAVAILABLE X1, X2: the same")
      (say "")
      (say "what the limit does here:")
      (let* ((db (open-database ":memory:"))
             (st (prepare-statement db "select ?1"))
             (b (bind! st 1 big-text))
             (s (step! st))
             (used (sqlite3-memory-used))
             (call (around-one-call (lambda () (string-length (column-value st 0)))))
             (f (finalize-statement! st)))
        (close-database! db)
        (say "  sqlite3_memory_used with a statement at its row: " used)
        (say "  column-value of the 100,000 bytes under a limit of that plus 1,000: " (car call))
        (say "  " (cadr call) "; once lifted: " (caddr call)))))

(say "")
(say "the limits at the end: " (list 'hard (hard-limit -1) 'soft (soft-limit -1)))
(say "the counts at the end: " (native-counts))
(exit 0)
