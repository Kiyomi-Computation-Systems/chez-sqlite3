#!r6rs
;;; The suite for the who-taking internals in (chez-sqlite3 private
;;; statement) and (chez-sqlite3 private statement-values) (ADR-0013;
;;; ADR-0014 and ADR-0016).
;;; A convenience reaches the statement verbs through these, so each raise
;;; must name the procedure the caller called, never the verb.
;;;
;;;   the who        at every raise site of every internal, the raise names
;;;                  the WHO it was given, here the-convenience, a name no
;;;                  verb has; and reaches a with-exception-handler handler at
;;;                  depth 1, after the section, against a no-raise sentinel.
;;;                  The internals: prepared, finalized, step!/who,
;;;                  reset!/who, column-count/who, prepared-at, checked-out,
;;;                  returned, bind!/who, bind-all!/who, bind-each!/who,
;;;                  clear-bindings!/who, column-value/who,
;;;                  column-bytevector/who and column-name/who. A WHO that is
;;;                  no symbol is the internal's own refusal
;;;   prepared-at    one statement from a byte offset of a C string the
;;;                  caller holds, answered as data with its tail's offset:
;;;                  every statement of a script in turn, a statement's own
;;;                  text kept whole (a two-byte character, a leading U+FEFF),
;;;                  no statement, a failure with SQLite's own offset from the
;;;                  start; its statement handed over inside the section; its
;;;                  flags reaching SQLite, read through lookaside
;;;   bind-each!/who bind-all!'s rule, with each value bound in a section of
;;;                  its own: a second engine on this thread steps the
;;;                  statement between two binds at some fuel, and reads the
;;;                  first value bound and the rest NULL
;;;   the call's check
;;;                  LEFT?, a convenience's flag, read first in each section
;;;                  that touches its statement: checked-out's and a miss's
;;;                  prepare's, prepared-at's, bind-each!/who's count's and
;;;                  each value's, and while-held's, around a step or a read.
;;;                  Answering true, the section touches nothing, and
;;;                  &sqlite-closed is raised from the who at depth 1; a check
;;;                  that is no procedure is the internal's own refusal
;;;
;;; NOMEM, which a column read raises only under a heap limit, is
;;; tests/test-statement-values-nomem.sps's, and the cache's behaviour, beyond
;;; its raises, tests/test-connection-cache.sps's.
;;;
;;; The loading procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them: a refused library fails the rows by
;;; name. SQLite's answers here were measured on 3.53.1 and 3.45.1 alike
;;; before a row asserts them.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure foreign-alloc foreign-free foreign-ref foreign-set!
              fork-thread make-mutex with-mutex sleep make-time get-thread-id disable-interrupts
              enable-interrupts make-engine)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3 private conditions) sqlite-busy? sqlite-constraint? sqlite-invalid-text?
              sqlite-invalid-text-column sqlite-invalid-text-offset)
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

(define statement-library '(chez-sqlite3 private statement))
(define values-library '(chez-sqlite3 private statement-values))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define tracked-statements (reach '(chez-sqlite3 private connection) 'tracked-statements))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define step! (reach statement-library 'step!))
(define statement-sql (reach statement-library 'statement-sql))
(define statement-state (reach statement-library 'statement-state))
(define prepared (reach statement-library 'prepared))
(define finalized (reach statement-library 'finalized))
(define step!/who (reach statement-library 'step!/who))
(define reset!/who (reach statement-library 'reset!/who))
(define column-count/who (reach statement-library 'column-count/who))
(define checked-sql (reach statement-library 'checked-sql))
(define prepared-at (reach statement-library 'prepared-at))
(define checked-out (reach statement-library 'checked-out))
(define returned (reach statement-library 'returned))
(define bind!/who (reach values-library 'bind!/who))
(define bind-all!/who (reach values-library 'bind-all!/who))
(define bind-each!/who (reach values-library 'bind-each!/who))
(define clear-bindings!/who (reach values-library 'clear-bindings!/who))
(define column-value/who (reach values-library 'column-value/who))
(define column-bytevector/who (reach values-library 'column-bytevector/who))
(define column-name/who (reach values-library 'column-name/who))
(define column-value (reach values-library 'column-value))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-bytes (reach '(chez-sqlite3 private native) 'call-with-bytes))
(define sqlite-prepare-persistent
  (guard (e (#t 'unreachable))
    (eval 'sqlite-prepare-persistent (environment '(chez-sqlite3 private constants)))))

;; --- bindings made here, after the load ------------------------------------------------
;; foreign-procedure resolves its entry when it is evaluated, so each is made
;; once the load above has run; one that cannot be made raises when called.

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_limit(sqlite3*, int id, int newVal): the old value.
(define limit (bound 'sqlite3_limit (foreign-procedure "sqlite3_limit" (uptr int int) int)))
;; int sqlite3_exec(sqlite3*, const char *sql, callback, void *, char **errmsg)
(define raw-exec (bound 'sqlite3_exec (foreign-procedure "sqlite3_exec" (uptr uptr uptr uptr uptr) int)))
;; int sqlite3_db_status(sqlite3*, int op, int *pCur, int *pHiwtr, int resetFlg)
(define db-status (bound 'sqlite3_db_status (foreign-procedure "sqlite3_db_status" (uptr int uptr uptr int) int)))

;; SQLITE_LIMIT_LENGTH, sqlite3.h's limit id 0; SQLITE_DBSTATUS_LOOKASIDE_USED, 0.
(define limit-length 0)
(define lookaside-used-op 0)

;; --- helpers ------------------------------------------------------------------------------

(define the-who 'the-convenience)

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

;; who-of : Condition -> Any
(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; message-of : Condition -> Symbol
;; Whether E has a message, never its text.
(define (message-of e) (if (message-condition? e) 'message 'no-message))

;; what-raised : Any -> Any
;; A raised object as this suite compares it: an &sqlite-error by its who,
;; code, extended code, SQL and offset, and whether its &message is its
;; message field; &sqlite-invalid-text by its who, column and offset;
;; &sqlite-wrong-thread by its who, owner and caller; &sqlite-closed by its
;; who; an assertion violation by its who and irritants; anything else as
;; text.
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

;; sqlite-failure : Symbol Symbol Symbol (U String #f) (U Natural #f) -> List
(define (sqlite-failure who code extended sql offset)
  (list 'sqlite-error who code extended sql offset 'message-is-the-field))

(define (closed who) (list 'closed who 'message))
(define (refused who . irritants) (list 'assertion-violation who irritants))
(define (invalid who column offset) (list 'invalid-text who column offset 'message))
(define (not-allowed who state) (refused who 'not-allowed-in-state state))
(define (wrong-thread who) (list 'wrong-thread who 'message 'main 'the-thread))

;; attempt : (-> Any) -> Any
;; THUNK's answer, or (raised WHAT) for what it raised.
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define void-value (if #f #f))
(define (no-value x) (if (eq? x void-value) 'no-value x))

;; interrupt-depth : -> Positive-Integer
;; How many critical sections this thread is inside, plus one.
(define (interrupt-depth)
  (let ((n (disable-interrupts)))
    (enable-interrupts)
    n))

;; handler-depth : (-> Any) -> (U (List 'raised-at-depth Symbol Any) (List 'no-raise Any))
;; The depth a with-exception-handler handler runs at for the first thing
;; THUNK raises, written depth-N, and what it raised; the handler escapes.
;; (no-raise VALUE) when THUNK raises nothing, a statement written statement.
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
        (let ((v (thunk)))
          (list 'no-raise (if (guard (e (#t #f)) (statement-state v) #t) 'statement (no-value v)))))))))

(define (at-depth-1 what) (list 'raised-at-depth 'depth-1 what))

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
(define (with-handle db proc) (call-with-open-handle 'test-statement-who db proc))

;; exec! : Database String -> Any
;; SQL prepared, stepped once and finalized: what step! answered.
(define (exec! db sql)
  (let* ((st (prepare-statement db sql))
         (answer (guard (e (#t (finalize-statement! st) (raise e))) (step! st))))
    (finalize-statement! st)
    answer))

;; exec-bytes! : Database Bytevector -> Integer
;; SQL given as raw bytes, run by the suite's own sqlite3_exec: its answer.
(define (exec-bytes! db bytes)
  (with-handle db
    (lambda (h)
      (call-with-bytes 'test-statement-who
                       (u8-list->bytevector (append (bytevector->u8-list bytes) '(0)))
        (lambda (sql) (raw-exec h sql 0 0 0))))))

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

;; with-file-db : (String Database -> Any) -> Any
;; PROC's answer, or what it raised, given a temporary directory's database
;; file, made by make-table!, and a connection to it, closed after.
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

;; reader! : String -> (Pairof Database Statement)
;; A second connection to PATH holding a read: its select stepped to a row.
(define (reader! path)
  (let* ((db (open-database path))
         (st (prepare-statement db "select x from t")))
    (step! st)
    (cons db st)))

;; release! : Any -> Void
(define (release! reader)
  (when (pair? reader) (undo! (list (cdr reader)) (list (car reader)))))

;; under-reader : String Database (Database -> Any) -> Any
;; PROC's answer given DB, while a second connection to PATH holds a read.
(define (under-reader path db proc)
  (let ((reader #f))
    (dynamic-wind
      (lambda () #f)
      (lambda () (set! reader (reader! path)) (proc db))
      (lambda () (release! reader)))))

(define insert-sql "insert into t values (0)")
(define returning-sql "insert into t values (1), (2) returning x")

;; wait-until : (-> Any) Natural -> (U 'satisfied 'iterations-exhausted)
;; DONE? asked every 10 ms, at most STEPS times.
(define (wait-until done? steps)
  (run-until (lambda () (sleep (make-time 'time-duration 10000000 0))) done? steps))

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
    (if (eq? (wait-until (lambda () (with-mutex m answer)) 12000) 'satisfied)
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

;; text-of : Natural -> String
(define (text-of n) (make-string n #\a))

;; lookaside-used : Database -> Integer
;; SQLITE_DBSTATUS_LOOKASIDE_USED's current value for DB, through the suite's
;; own sqlite3_db_status: the lookaside slots the connection's statements
;; hold now.
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

;; with-script : Database String (String Bytevector Positive-Integer -> Any) -> Any
;; PROC given SQL's checked copy, its UTF-8 and its C string's address, the
;; block held for PROC's extent, as execute-script! will hold it.
(define (with-script db sql proc)
  (let-values (((copy bytes) (checked-sql 'test-statement-who sql)))
    (call-with-c-string 'test-statement-who copy
      (lambda (block) (proc copy bytes block)))))

;; shown-outcome : Any -> Any
;; prepared-at's answer as this suite compares it: a statement by its SQL and
;; state, then finalized.
(define (shown-outcome outcome)
  (if (and (pair? outcome) (eq? (car outcome) 'prepared))
      (let* ((st (cadr outcome))
             (sql (statement-sql st))
             (state (statement-state st)))
        (finalize-statement! st)
        (list 'prepared sql state (caddr outcome)))
      outcome))

;; fuels-until-complete : (Positive-Integer -> (U 'completed Any)) Positive-Integer -> (List Natural (Listof Any))
;; RUN at each fuel from 1, until it answers completed, at most CAP fuels:
;; the last fuel run, and every other answer, in order of fuel.
(define (fuels-until-complete run cap)
  (let loop ((fuel 1) (found '()))
    (let ((answer (run fuel)))
      (cond ((eq? answer 'completed) (list fuel (reverse found)))
            ((>= fuel cap) (list 'no-completion-by cap (reverse found)))
            (else (loop (+ fuel 1) (cons answer found)))))))

(test-begin "statement-who")

;; --- the load -------------------------------------------------------------------------------

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

;; --- statement.sls's internals: each raise names the who, at depth 1 --------------------------
;; A with-exception-handler handler of a raise made inside a critical section
;; runs with interrupts disabled, at depth 2; after it, at depth 1. Each row's
;; handler reads its depth and what was raised. The no-raise sentinel,
;; (no-raise VALUE), is no depth.

(test-equal "step!/who names its who at every raise: a failed step, a refusal in done, a finalized statement, no statement, the wrong thread, each at depth 1; a who that is no symbol is call-with-statement-handle's refusal; a step that answers raises nothing"
  (list (at-depth-1 (sqlite-failure the-who 'constraint 'constraint-unique insert-sql #f))
        (at-depth-1 (not-allowed the-who 'done))
        (at-depth-1 (closed the-who))
        (at-depth-1 (refused the-who 'not-a-statement 'x))
        (at-depth-1 (wrong-thread the-who))
        (at-depth-1 (refused 'call-with-statement-handle 'not-a-who '(kind string)))
        (list 'no-raise #t))
  (with-file-db
   (lambda (path db)
     (let* ((failing (prepare-statement db insert-sql))
            (a (handler-depth (lambda () (step!/who the-who failing))))
            (done (prepare-statement db "select 1"))
            (b (begin (step! done) (step! done) (handler-depth (lambda () (step!/who the-who done)))))
            (gone (prepare-statement db "select 1"))
            (c (begin (finalize-statement! gone) (handler-depth (lambda () (step!/who the-who gone)))))
            (d (handler-depth (lambda () (step!/who the-who 'x))))
            (live (prepare-statement db "select 1"))
            (e (from-another-thread (lambda () (handler-depth (lambda () (step!/who the-who live))))))
            (f (handler-depth (lambda () (step!/who "who" live))))
            (g (handler-depth (lambda () (step!/who the-who live)))))
       (undo! (list failing done live) '())
       (list a b c d e f g)))))

(test-equal "reset!/who names its who: its own failure, an insert ... returning stepped once under another's read, busy; a finalized statement; no statement; the wrong thread; each at depth 1; a reset that succeeds raises nothing"
  (list (at-depth-1 (sqlite-failure the-who 'busy 'busy returning-sql #f))
        (at-depth-1 (closed the-who))
        (at-depth-1 (refused the-who 'not-a-statement 'x))
        (at-depth-1 (wrong-thread the-who))
        (list 'no-raise 'no-value))
  (with-file-db
   (lambda (path db)
     (let* ((a (under-reader path db
                 (lambda (db)
                   (let* ((st (prepare-statement db returning-sql))
                          (s (step! st))
                          (r (handler-depth (lambda () (reset!/who the-who st)))))
                     (finalize-statement! st)
                     r))))
            (gone (prepare-statement db "select 1"))
            (b (begin (finalize-statement! gone) (handler-depth (lambda () (reset!/who the-who gone)))))
            (c (handler-depth (lambda () (reset!/who the-who 'x))))
            (live (prepare-statement db "select 1"))
            (d (from-another-thread (lambda () (handler-depth (lambda () (reset!/who the-who live))))))
            (e (handler-depth (lambda () (reset!/who the-who live)))))
       (finalize-statement! live)
       (list a b c d e)))))

(test-equal "finalized names its who: its own failure, busy; no statement; the wrong thread; each at depth 1; a finalized statement finalized again raises nothing"
  (list (at-depth-1 (sqlite-failure the-who 'busy 'busy returning-sql #f))
        (at-depth-1 (refused the-who 'not-a-statement 'x))
        (at-depth-1 (wrong-thread the-who))
        (list 'no-raise 'no-value))
  (with-file-db
   (lambda (path db)
     (let* ((st #f)
            (a (under-reader path db
                 (lambda (db)
                   (set! st (prepare-statement db returning-sql))
                   (step! st)
                   (handler-depth (lambda () (finalized the-who st))))))
            (b (handler-depth (lambda () (finalized the-who 'x))))
            (live (prepare-statement db "select 1"))
            (c (from-another-thread (lambda () (handler-depth (lambda () (finalized the-who live))))))
            (d (handler-depth (lambda () (finalized the-who st)))))
       (finalize-statement! live)
       (list a b c d)))))

(test-equal "column-count/who names its who: a finalized statement, no statement, the wrong thread, each at depth 1; a count raises nothing"
  (list (at-depth-1 (closed the-who))
        (at-depth-1 (refused the-who 'not-a-statement 'x))
        (at-depth-1 (wrong-thread the-who))
        (list 'no-raise 2))
  (with-memory-db
   (lambda (db)
     (let* ((gone (prepare-statement db "select 1"))
            (a (begin (finalize-statement! gone) (handler-depth (lambda () (column-count/who the-who gone)))))
            (b (handler-depth (lambda () (column-count/who the-who 'x))))
            (live (prepare-statement db "select 1, 2"))
            (c (from-another-thread (lambda () (handler-depth (lambda () (column-count/who the-who live))))))
            (d (handler-depth (lambda () (column-count/who the-who live)))))
       (finalize-statement! live)
       (list a b c d)))))

(test-equal "prepared names its who: a failed prepare, with the SQL and its offset; no statement; more than one; U+0000; no string; a closed connection; no database; the wrong thread; each at depth 1; a prepare raises nothing"
  (list (at-depth-1 (sqlite-failure the-who 'error 'error "select 1, nosuchcol" 10))
        (at-depth-1 (refused the-who 'no-statement '(kind string)))
        (at-depth-1 (refused the-who 'more-than-one-statement 10))
        (at-depth-1 (refused the-who 'sql-holds-nul '(kind string)))
        (at-depth-1 (refused the-who 'not-a-string 42))
        (at-depth-1 (wrong-thread the-who))
        (at-depth-1 (closed the-who))
        (at-depth-1 (refused the-who 'not-a-database 'x))
        (list 'no-raise 'statement)
        zero-counts)
  (let* ((db (guard (e (#t #f)) (open-database ":memory:")))
         (r (list (handler-depth (lambda () (prepared the-who db "select 1, nosuchcol" #f)))))
         (r2 (cons (handler-depth (lambda () (prepared the-who db ";" #f))) r))
         (r3 (cons (handler-depth (lambda () (prepared the-who db "select 1; select 2" #f))) r2))
         (r4 (cons (handler-depth (lambda () (prepared the-who db "select\x0;1" #f))) r3))
         (r5 (cons (handler-depth (lambda () (prepared the-who db 42 #f))) r4))
         (r6 (cons (from-another-thread (lambda () (handler-depth (lambda () (prepared the-who db "select 1" #f))))) r5))
         (c (guard (e (#t #f)) (close-database! db)))
         (r7 (cons (handler-depth (lambda () (prepared the-who db "select 1" #f))) r6))
         (r8 (cons (handler-depth (lambda () (prepared the-who 'x "select 1" #f))) r7))
         (live (guard (e (#t #f)) (open-database ":memory:")))
         (r9 (cons (handler-depth (lambda () (prepared the-who live "select 1" #f))) r8))
         (c2 (guard (e (#t #f)) (close-database! live))))
    (append (reverse r9) (list (native-counts)))))

(test-equal "prepared-at names its who: no database, the wrong thread, a closed connection, a start outside the SQL, an on-made that is no procedure, each at depth 1; the flags, a who that is no symbol, and SQL that checked-sql did not make are prepared-at's own refusals; a prepare raises nothing"
  (list (at-depth-1 (refused the-who 'not-a-database 'x))
        (at-depth-1 (wrong-thread the-who))
        (at-depth-1 (refused the-who 'start-out-of-range 9 8))
        (at-depth-1 (refused the-who 'start-out-of-range -1 8))
        (at-depth-1 (refused the-who 'not-a-procedure 'x))
        (at-depth-1 (refused 'prepared-at 'not-prepare-flags 2))
        (at-depth-1 (refused 'prepared-at 'not-a-who '(kind string)))
        (at-depth-1 (refused 'prepared-at 'not-checked-sql))
        (at-depth-1 (refused 'prepared-at 'not-checked-sql))
        (list 'no-raise (list 'prepared "select 1" 'ready 8))
        (at-depth-1 (closed the-who))
        zero-counts)
  (let* ((db (guard (e (#t #f)) (open-database ":memory:")))
         (r (with-script db "select 1"
              (lambda (sql bytes block)
                (let* ((a (handler-depth (lambda () (prepared-at the-who 'x sql bytes block 0 0 #f #f))))
                       (b (from-another-thread
                           (lambda () (handler-depth (lambda () (prepared-at the-who db sql bytes block 0 0 #f #f))))))
                       (c (handler-depth (lambda () (prepared-at the-who db sql bytes block 9 0 #f #f))))
                       (d (handler-depth (lambda () (prepared-at the-who db sql bytes block -1 0 #f #f))))
                       (e (handler-depth (lambda () (prepared-at the-who db sql bytes block 0 0 'x #f))))
                       (f (handler-depth (lambda () (prepared-at the-who db sql bytes block 0 2 #f #f))))
                       (g (handler-depth (lambda () (prepared-at "who" db sql bytes block 0 0 #f #f))))
                       (h (handler-depth (lambda () (prepared-at the-who db sql 'bytes block 0 0 #f #f))))
                       (i (handler-depth (lambda () (prepared-at the-who db sql bytes 0 0 0 #f #f))))
                       (j (let ((o (attempt (lambda () (prepared-at the-who db sql bytes block 0 0 #f #f)))))
                            (list 'no-raise (shown-outcome o))))
                       (k (begin (close-database! db)
                                 (handler-depth (lambda () (prepared-at the-who db sql bytes block 0 0 #f #f))))))
                  (list a b c d e f g h i j k))))))
    (append r (list (native-counts)))))

(test-equal "checked-out names its who: an on-made that is no procedure, no database, the wrong thread, no string, U+0000, a failed prepare, no statement, more than one, a closed connection, each at depth 1; a who that is no symbol is checked-out's own refusal; a check-out raises nothing"
  (list (at-depth-1 (refused the-who 'not-a-procedure 'x))
        (at-depth-1 (refused the-who 'not-a-database 'x))
        (at-depth-1 (wrong-thread the-who))
        (at-depth-1 (refused the-who 'not-a-string 42))
        (at-depth-1 (refused the-who 'sql-holds-nul '(kind string)))
        (at-depth-1 (sqlite-failure the-who 'error 'error "select 1, nosuchcol" 10))
        (at-depth-1 (refused the-who 'no-statement '(kind string)))
        (at-depth-1 (refused the-who 'more-than-one-statement 10))
        (at-depth-1 (refused 'checked-out 'not-a-who '(kind string)))
        (list 'no-raise 'statement)
        (at-depth-1 (closed the-who))
        zero-counts)
  (let* ((db (guard (e (#t #f)) (open-database ":memory:")))
         (a (handler-depth (lambda () (checked-out the-who db "select 1" 'x #f))))
         (b (handler-depth (lambda () (checked-out the-who 'x "select 1" #f #f))))
         (c (from-another-thread (lambda () (handler-depth (lambda () (checked-out the-who db "select 1" #f #f))))))
         (d (handler-depth (lambda () (checked-out the-who db 42 #f #f))))
         (e (handler-depth (lambda () (checked-out the-who db "select\x0;1" #f #f))))
         (f (handler-depth (lambda () (checked-out the-who db "select 1, nosuchcol" #f #f))))
         (g (handler-depth (lambda () (checked-out the-who db ";" #f #f))))
         (h (handler-depth (lambda () (checked-out the-who db "select 1; select 2" #f #f))))
         (i (handler-depth (lambda () (checked-out "who" db "select 1" #f #f))))
         (j (handler-depth (lambda () (checked-out the-who db "select 1" #f #f))))
         (k (begin (guard (e (#t #f)) (close-database! db))
                   (handler-depth (lambda () (checked-out the-who db "select 1" #f #f))))))
    (list a b c d e f g h i j k (native-counts))))

(test-equal "returned names its who: a reset's own failure, an insert ... returning stepped once under another's read, busy, the statement then finalized, not kept; no statement; the wrong thread; each at depth 1; a who that is no symbol is call-with-statement-handle's refusal; a return, and a finalized statement's, raise nothing"
  (list (list (at-depth-1 (sqlite-failure the-who 'busy 'busy returning-sql #f)) 'finalized 0)
        (at-depth-1 (refused the-who 'not-a-statement 'x))
        (at-depth-1 (wrong-thread the-who))
        (at-depth-1 (refused 'call-with-statement-handle 'not-a-who '(kind string)))
        (list 'no-raise 'no-value)
        (list 'no-raise 'no-value))
  (with-file-db
   (lambda (path db)
     (let* ((a (under-reader path db
                 (lambda (db)
                   (let* ((st (checked-out the-who db returning-sql #f #f))
                          (s (step! st))
                          (r (handler-depth (lambda () (returned the-who st))))
                          (state (statement-state st)))
                     (list r state (length (tracked-statements db)))))))
            (b (handler-depth (lambda () (returned the-who 'x))))
            (live (checked-out the-who db "select 1" #f #f))
            (c (from-another-thread (lambda () (handler-depth (lambda () (returned the-who live))))))
            (d (handler-depth (lambda () (returned "who" live))))
            (e (handler-depth (lambda () (returned the-who live))))
            (gone (prepare-statement db "select 2"))
            (f (begin (finalize-statement! gone) (handler-depth (lambda () (returned the-who gone))))))
       (list a b c d e f)))))

;; --- statement-values.sls's internals -----------------------------------------------------------

(test-equal "bind!/who names its who: the state, the index, a name holding U+0000, a name no parameter has, a parameter of no kind, a value, SQLite's toobig, a finalized statement, no statement, the wrong thread, each at depth 1; a bind that succeeds raises nothing"
  (list (at-depth-1 (not-allowed the-who 'row))
        (at-depth-1 (refused the-who 'parameter-out-of-range 0 1))
        (at-depth-1 (refused the-who 'parameter-name-holds-nul '(kind string)))
        (at-depth-1 (refused the-who 'no-such-parameter '(kind string)))
        (at-depth-1 (refused the-who 'not-a-parameter 1.5))
        (at-depth-1 (refused the-who 'boolean 1 '(kind boolean)))
        (at-depth-1 (sqlite-failure the-who 'toobig 'toobig "select ?1" #f))
        (at-depth-1 (closed the-who))
        (at-depth-1 (refused the-who 'not-a-statement 'x))
        (at-depth-1 (wrong-thread the-who))
        (list 'no-raise 'no-value))
  (with-memory-db
   (lambda (db)
     (let* ((row (prepare-statement db "select ?1"))
            (s (step! row))
            (a (handler-depth (lambda () (bind!/who the-who row 1 1))))
            (st (prepare-statement db "select ?1"))
            (b (handler-depth (lambda () (bind!/who the-who st 0 1))))
            (c (handler-depth (lambda () (bind!/who the-who st ":a\x0;" 1))))
            (d (handler-depth (lambda () (bind!/who the-who st ":a" 1))))
            (e (handler-depth (lambda () (bind!/who the-who st 1.5 1))))
            (f (handler-depth (lambda () (bind!/who the-who st 1 #t))))
            (old (with-handle db (lambda (h) (limit h limit-length 30))))
            (g (handler-depth (lambda () (bind!/who the-who st 1 (text-of 31)))))
            (gone (prepare-statement db "select ?1"))
            (h (begin (finalize-statement! gone) (handler-depth (lambda () (bind!/who the-who gone 1 1)))))
            (i (handler-depth (lambda () (bind!/who the-who 'x 1 1))))
            (j (from-another-thread (lambda () (handler-depth (lambda () (bind!/who the-who st 1 1))))))
            (k (handler-depth (lambda () (bind!/who the-who st 1 1)))))
       (undo! (list row st) '())
       (list a b c d e f g h i j k)))))

(test-equal "bind-all!/who names its who: the count, a value, SQLite's toobig midway, the state, a finalized statement, the wrong thread, each at depth 1; a bind that succeeds raises nothing"
  (list (at-depth-1 (refused the-who 'value-count-mismatch 1 2))
        (at-depth-1 (refused the-who 'boolean 2 '(kind boolean)))
        (at-depth-1 (sqlite-failure the-who 'toobig 'toobig "select ?1, ?2" #f))
        (at-depth-1 (not-allowed the-who 'row))
        (at-depth-1 (closed the-who))
        (at-depth-1 (wrong-thread the-who))
        (list 'no-raise 'no-value))
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select ?1, ?2"))
            (a (handler-depth (lambda () (bind-all!/who the-who st '(1)))))
            (b (handler-depth (lambda () (bind-all!/who the-who st '(1 #t)))))
            (old (with-handle db (lambda (h) (limit h limit-length 30))))
            (c (handler-depth (lambda () (bind-all!/who the-who st (list 1 (text-of 31))))))
            (row (prepare-statement db "select ?1"))
            (s (step! row))
            (d (handler-depth (lambda () (bind-all!/who the-who row '(1)))))
            (gone (prepare-statement db "select ?1"))
            (e (begin (finalize-statement! gone) (handler-depth (lambda () (bind-all!/who the-who gone '(1))))))
            (f (from-another-thread (lambda () (handler-depth (lambda () (bind-all!/who the-who st '(1 2)))))))
            (g (handler-depth (lambda () (bind-all!/who the-who st '(1 2))))))
       (undo! (list st row) '())
       (list a b c d e f g)))))

(test-equal "bind-each!/who names its who: the count, a value, SQLite's toobig midway, the state, a finalized statement, no statement, the wrong thread, each at depth 1; a bind that succeeds raises nothing"
  (list (at-depth-1 (refused the-who 'value-count-mismatch 1 2))
        (at-depth-1 (refused the-who 'boolean 2 '(kind boolean)))
        (at-depth-1 (sqlite-failure the-who 'toobig 'toobig "select ?1, ?2" #f))
        (at-depth-1 (not-allowed the-who 'row))
        (at-depth-1 (closed the-who))
        (at-depth-1 (refused the-who 'not-a-statement 'x))
        (at-depth-1 (wrong-thread the-who))
        (list 'no-raise 'no-value))
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select ?1, ?2"))
            (a (handler-depth (lambda () (bind-each!/who the-who st '(1) #f))))
            (b (handler-depth (lambda () (bind-each!/who the-who st '(1 #t) #f))))
            (old (with-handle db (lambda (h) (limit h limit-length 30))))
            (c (handler-depth (lambda () (bind-each!/who the-who st (list 1 (text-of 31)) #f))))
            (row (prepare-statement db "select ?1"))
            (s (step! row))
            (d (handler-depth (lambda () (bind-each!/who the-who row '(1) #f))))
            (gone (prepare-statement db "select ?1"))
            (e (begin (finalize-statement! gone) (handler-depth (lambda () (bind-each!/who the-who gone '(1) #f)))))
            (f (handler-depth (lambda () (bind-each!/who the-who 'x '(1) #f))))
            (g (from-another-thread (lambda () (handler-depth (lambda () (bind-each!/who the-who st '(1 2) #f))))))
            (h (handler-depth (lambda () (bind-each!/who the-who st '(1 2) #f)))))
       (undo! (list st row) '())
       (list a b c d e f g h)))))

(test-equal "clear-bindings!/who names its who: the state, a finalized statement, no statement, the wrong thread, each at depth 1; a clear raises nothing"
  (list (at-depth-1 (not-allowed the-who 'row))
        (at-depth-1 (closed the-who))
        (at-depth-1 (refused the-who 'not-a-statement 'x))
        (at-depth-1 (wrong-thread the-who))
        (list 'no-raise 'no-value))
  (with-memory-db
   (lambda (db)
     (let* ((row (prepare-statement db "select 1"))
            (s (step! row))
            (a (handler-depth (lambda () (clear-bindings!/who the-who row))))
            (gone (prepare-statement db "select 1"))
            (b (begin (finalize-statement! gone) (handler-depth (lambda () (clear-bindings!/who the-who gone)))))
            (c (handler-depth (lambda () (clear-bindings!/who the-who 'x))))
            (st (prepare-statement db "select ?1"))
            (d (from-another-thread (lambda () (handler-depth (lambda () (clear-bindings!/who the-who st))))))
            (e (handler-depth (lambda () (clear-bindings!/who the-who st)))))
       (undo! (list row st) '())
       (list a b c d e)))))

(test-equal "column-value/who, column-bytevector/who and column-name/who name their who: the state, the index, invalid TEXT, no index, a value column-bytevector refuses, an invalid name, a finalized statement, the wrong thread, each at depth 1; a read raises nothing"
  (list (at-depth-1 (not-allowed the-who 'ready))
        (at-depth-1 (refused the-who 'column-out-of-range 3 3))
        (at-depth-1 (invalid the-who 0 0))
        (list 'no-raise 7)
        (at-depth-1 (closed the-who))
        (at-depth-1 (wrong-thread the-who))
        (at-depth-1 (not-allowed the-who 'ready))
        (at-depth-1 (refused the-who 'not-text-or-blob 1 'integer))
        (at-depth-1 (refused the-who 'not-a-column-index 'x))
        (at-depth-1 (closed the-who))
        (at-depth-1 (wrong-thread the-who))
        (list 'no-raise #vu8(#xFF))
        (at-depth-1 (refused the-who 'column-out-of-range 9 3))
        (at-depth-1 (invalid the-who 0 0))
        (at-depth-1 (closed the-who))
        (at-depth-1 (wrong-thread the-who))
        (list 'no-raise "x"))
  (with-memory-db
   (lambda (db)
     (let* ((made (exec-bytes! db (u8-list->bytevector
                                   (append (bytevector->u8-list (string->utf8 "create table n (\""))
                                           '(#xFF)
                                           (bytevector->u8-list (string->utf8 "\")"))))))
            (st (prepare-statement db "select cast(x'ff' as text), 7, 'x' as x"))
            (gone (prepare-statement db "select 1"))
            (f0 (finalize-statement! gone))
            (a (handler-depth (lambda () (column-value/who the-who st 0))))
            (g (handler-depth (lambda () (column-bytevector/who the-who st 0))))
            (s (step! st))
            (b (handler-depth (lambda () (column-value/who the-who st 3))))
            (c (handler-depth (lambda () (column-value/who the-who st 0))))
            (d (handler-depth (lambda () (column-value/who the-who st 1))))
            (e (handler-depth (lambda () (column-value/who the-who gone 0))))
            (f (from-another-thread (lambda () (handler-depth (lambda () (column-value/who the-who st 1))))))
            (h (handler-depth (lambda () (column-bytevector/who the-who st 1))))
            (i (handler-depth (lambda () (column-bytevector/who the-who st 'x))))
            (j (handler-depth (lambda () (column-bytevector/who the-who gone 0))))
            (k (from-another-thread (lambda () (handler-depth (lambda () (column-bytevector/who the-who st 0))))))
            (l (handler-depth (lambda () (column-bytevector/who the-who st 0))))
            (m (handler-depth (lambda () (column-name/who the-who st 9))))
            (named (prepare-statement db "select * from n"))
            (n (handler-depth (lambda () (column-name/who the-who named 0))))
            (o (handler-depth (lambda () (column-name/who the-who gone 0))))
            (p (from-another-thread (lambda () (handler-depth (lambda () (column-name/who the-who st 2))))))
            (q (handler-depth (lambda () (column-name/who the-who st 2)))))
       (undo! (list st named) '())
       (list a b c d e f g h i j k l m n o p q)))))

;; --- prepared-at: one statement from an offset, as data -------------------------------------------
;; Measured on 3.53.1 and 3.45.1 alike
;;: the tail of select 1;
;; select 2 is 9; of ;; select 2 is 11, one statement holding the semicolons
;; before it; of -- c alone 5, with no statement.

;; script-run : Database String -> (Listof Any)
;; Every statement of SQL in turn, by prepared-at from each one's tail, each
;; answer shown, until one answers empty or failed, or 10 are prepared.
(define (script-run db sql)
  (with-script db sql
    (lambda (copy bytes block)
      (let loop ((start 0) (found '()) (n 0))
        (let ((o (prepared-at the-who db copy bytes block start 0 #f #f)))
          (if (and (eq? (car o) 'prepared) (< n 10))
              (let ((tail (caddr o)))
                (loop tail (cons (shown-outcome o) found) (+ n 1)))
              (reverse (cons (shown-outcome o) found))))))))

(test-equal "prepared-at answers each statement of a script in turn, from the tail of the one before, with its own text and its tail's byte offset, ready; then empty at the end: select 1; select 2 gives select 1 at 9, then  select 2 at 18, then empty at 18; ;; select 2 is one statement; -- c alone is empty at 5; empty SQL is empty at 0; and no statement is left counted"
  (list (list (list 'prepared "select 1;" 'ready 9) (list 'prepared " select 2" 'ready 18) '(empty 18))
        (list (list 'prepared ";; select 2" 'ready 11) '(empty 11))
        (list '(empty 5))
        (list '(empty 0))
        (list '(connection . 1) '(statement . 0)))
  (with-memory-db
   (lambda (db)
     (let* ((a (script-run db "select 1; select 2"))
            (b (script-run db ";; select 2"))
            (c (script-run db " -- c"))
            (d (script-run db ""))
            (counts (native-counts)))
       (list a b c d (list (assq 'connection counts) (assq 'statement counts)))))))

(test-equal "prepared-at keeps a statement's own text whole: a two-byte character before the tail moves its byte offset, and a statement that starts with U+FEFF keeps it"
  (list (list (list 'prepared "select 'λ';" 'ready 12) (list 'prepared " select 2" 'ready 21) '(empty 21))
        (list (list 'prepared "\xFEFF;select 1" 'ready 11) '(empty 11)))
  (with-memory-db
   (lambda (db)
     (let* ((a (script-run db "select 'λ'; select 2"))
            (b (script-run db "\xFEFF;select 1")))
       (list a b)))))

(test-equal "prepared-at answers a failure as data, SQLite's extended code and its offset in bytes from the start, never raised; the statement before it stood, prepared and finalized"
  (list (list (list 'prepared "select 1;" 'ready 9) (list 'failed 1 'message 1))
        (list (list 'failed 1 'message -1)))
  (with-memory-db
   (lambda (db)
     (let* ((shown (lambda (run)
                     (map (lambda (o) (if (eq? (car o) 'failed)
                                          (list 'failed (cadr o) (if (string? (caddr o)) 'message 'no-message)
                                                (cadddr o))
                                          o))
                          run)))
            (a (shown (script-run db "select 1; selectx 2")))
            (b (shown (script-run db "select * from nosuchtable"))))
       (list a b)))))

(test-equal "prepared-at hands its statement to on-made inside the prepare's section, at depth 2, the very statement it answers"
  (list 'depth-2 'the-very-statement)
  (with-memory-db
   (lambda (db)
     (with-script db "select 1"
       (lambda (sql bytes block)
         (let* ((seen #f)
                (depth #f)
                (o (prepared-at the-who db sql bytes block 0 0
                                (lambda (st) (set! depth (interrupt-depth)) (set! seen st)) #f))
                (same (and (eq? (car o) 'prepared) (eq? (cadr o) seen))))
           (when (eq? (car o) 'prepared) (finalize-statement! (cadr o)))
           (list (string->symbol (string-append "depth-" (number->string depth)))
                 (if same 'the-very-statement 'another))))))))

(test-equal "prepared-at's statement is tracked and counted by its connection, as prepare-statement's is, and the close finalizes it"
  (list 'tracked (list '(connection . 1) '(statement . 1)) 'finalized zero-counts)
  (let* ((db (open-database ":memory:"))
         (r (with-script db "select 1"
              (lambda (sql bytes block) (prepared-at the-who db sql bytes block 0 0 #f #f))))
         (st (and (pair? r) (eq? (car r) 'prepared) (cadr r)))
         (tracked (if (and st (memq st (tracked-statements db))) 'tracked 'untracked))
         (counts (native-counts))
         (c (close-database! db)))
    (list tracked (list (assq 'connection counts) (assq 'statement counts))
          (and st (statement-state st)) (native-counts))))

;; handed-over : Database String -> (List Symbol Symbol)
;; checked-out of SQL on DB with an on-made that reads its depth: the depth,
;; and whether on-made was given the very statement checked-out answers.
(define (handed-over db sql)
  (let* ((seen #f)
         (depth #f)
         (st (checked-out the-who db sql (lambda (s) (set! depth (interrupt-depth)) (set! seen s)) #f)))
    (list (if depth (string->symbol (string-append "depth-" (number->string depth))) 'not-called)
          (if (and st (eq? st seen)) 'the-very-statement 'another))))

(test-equal "checked-out hands its statement to on-made inside the section that prepares it, on a miss, and inside the one that checks it out, on a hit: at depth 2, the very statement it answers"
  (list (list 'depth-2 'the-very-statement) (list 'depth-2 'the-very-statement))
  (with-memory-db
   (lambda (db)
     (let* ((miss (handed-over db "select 1"))
            (r (returned the-who (car (tracked-statements db))))
            (hit (handed-over db "select 1")))
       (list miss hit)))))

;; Measured on both libraries:
;; ten held statements of select 1, 2 where ?1 prepared with no flags take 70
;; of the connection's lookaside slots, and with SQLITE_PREPARE_PERSISTENT
;; none, so their memory comes from the heap.
(test-equal "prepared-at's flags reach SQLite: ten statements held, prepared with no flags, take lookaside slots; prepared with SQLITE_PREPARE_PERSISTENT, none"
  (list 'some 0)
  (let ((held-by (lambda (flags)
                   (with-memory-db
                    (lambda (db)
                      (with-script db "select 1, 2 where ?1"
                        (lambda (sql bytes block)
                          (let loop ((i 0) (held '()))
                            (if (< i 10)
                                (let ((o (prepared-at the-who db sql bytes block 0 flags #f #f)))
                                  (loop (+ i 1) (if (eq? (car o) 'prepared) (cons (cadr o) held) held)))
                                (let ((used (lookaside-used db)))
                                  (for-each finalize-statement! held)
                                  used))))))))))
    (let* ((plain (held-by 0))
           (persistent (held-by sqlite-prepare-persistent)))
      (list (if (and (integer? plain) (> plain 0)) 'some plain) persistent))))

(test-equal "bind-each!/who binds nothing when its count or a value is refused, as bind-all!'s rule has it: the statement then reads NULL at every parameter; and binds every value when none is"
  (list (list (list 'raised (refused the-who 'boolean 2 '(kind boolean))) '(null null))
        (list (list 'raised (refused the-who 'value-count-mismatch 1 2)) '(null null))
        (list 'no-value '(1 2)))
  (with-memory-db
   (lambda (db)
     (let ((after (lambda (given)
                    (let* ((st (prepare-statement db "select ?1, ?2"))
                           (b (no-value (attempt (lambda () (bind-each!/who the-who st given #f)))))
                           (s (step! st))
                           (x (column-value st 0))
                           (y (column-value st 1)))
                      (finalize-statement! st)
                      (list b (list (if (integer? x) x 'null) (if (integer? y) y 'null)))))))
       (let* ((a (after '(1 #t)))
              (b (after '(1)))
              (c (after '(1 2))))
         (list a b c))))))

;; --- bind-each!/who: one value a section ------------------------------------------------------
;; A runs bind-each!/who of three values in an engine of FUEL ticks; at its
;; first expiry B, on this thread, steps the statement and reads its row; then
;; A finishes. A section never expires, so B can come only between two of A's
;; sections: before the count, before a bind, or after the last. Where A binds
;; each value in a section of its own, some fuel puts B between two binds, and
;; B reads the values bound before it and NULL after, and A's next bind is
;; refused in row; bound in one section, B reads none or all.

;; between-binds : Database Positive-Integer -> (U 'completed (List Any Any))
(define (between-binds db fuel)
  (let* ((st (prepare-statement db "select ?1, ?2, ?3"))
         (a-answer 'a-not-finished)
         (a (make-engine (lambda () (set! a-answer (attempt (lambda () (no-value (bind-each!/who the-who st '(1 2 3) #f))))) 'a)))
         (a2 (a fuel (lambda (left . v) #f) (lambda (next) next)))
         (b (and a2 (attempt (lambda ()
                               (step! st)
                               (let* ((x (column-value st 0)) (y (column-value st 1)) (z (column-value st 2)))
                                 (map (lambda (v) (if (integer? v) v 'null)) (list x y z))))))))
    (let loop ((e a2) (n 0))
      (when (and e (< n 100000))
        (loop (e 1000000 (lambda (left . v) #f) (lambda (next) next)) (+ n 1))))
    (finalize-statement! st)
    (if a2 (list b a-answer) 'completed)))

(test-equal "bind-each!/who binds each value in a critical section of its own: over every fuel from 1 until A completes without expiring, B steps between the count and the binds, between each two binds, and after the last, reading the values bound before it, each time A refused at its next bind"
  (list (list '(null null null) (list 'raised (not-allowed the-who 'row)))
        (list '(1 null null) (list 'raised (not-allowed the-who 'row)))
        (list '(1 2 null) (list 'raised (not-allowed the-who 'row)))
        (list '(1 2 3) 'no-value))
  (with-memory-db
   (lambda (db)
     (let* ((run (fuels-until-complete (lambda (fuel) (between-binds db fuel)) 5000))
            (seen (cadr run)))
       (when (integer? (car run))
         (display "  bind-each!/who completed without expiring at fuel ")
         (display (car run))
         (newline))
       (if (not (integer? (car run)))
           run
           (let loop ((rest seen) (distinct '()))
             (cond ((null? rest)
                    (list-sort (lambda (a b) (< (length (filter integer? (car a))) (length (filter integer? (car b)))))
                               distinct))
                   ((member (car rest) distinct) (loop (cdr rest) distinct))
                   (else (loop (cdr rest) (cons (car rest) distinct))))))))))

;; --- the call's check: a convenience's flag, read first in each section --------------------------
;; A check answers true once the call's statement has left it. These checks
;; count their calls, and some answer #f until their Nth, so a row can set
;; the flag between two sections of one call.

;; check-after : Natural -> (Values (-> Boolean) (-> Natural))
;; A check answering #f for its first N calls and #t after, and how many
;; calls it has had.
(define (check-after n)
  (let ((calls 0))
    (values (lambda () (set! calls (+ calls 1)) (> calls n))
            (lambda () calls))))

(define while-held (reach statement-library 'while-held))
(define database-cache-count (reach '(chez-sqlite3 private connection) 'database-cache-count))

(define (statement-count) (cdr (assq 'statement (native-counts))))

;; states-of : Database -> (Listof (Pairof String Symbol))
;; Every statement DB tracks, as its SQL and its state, ordered by SQL.
(define (states-of db)
  (list-sort (lambda (a b) (string<? (car a) (car b)))
             (let loop ((rest (tracked-statements db)) (found '()))
               (if (null? rest)
                   found
                   (loop (cdr rest)
                         (cons (cons (statement-sql (car rest)) (statement-state (car rest))) found))))))

(test-equal "checked-out reads its call's check first in the check-out's section and in a miss's prepare's: answering true at the check-out, it raises &sqlite-closed from its who, at depth 1, on a hit and on a miss, the cache's statement left in it, ready, and nothing prepared; answering #f at a miss's check-out and true at its prepare, the same, nothing prepared; a check that is no procedure is refused from its who before the database is checked; a check answering #f checks out the cached statement"
  (list (list (at-depth-1 (closed the-who)) 1 '(("select 1" . ready)) 1 1)
        (list (at-depth-1 (closed the-who)) 1 '(("select 1" . ready)) 1 1)
        (list (at-depth-1 (closed the-who)) 2 '(("select 1" . ready)) 1 1)
        (at-depth-1 (refused the-who 'not-a-procedure 'x))
        (list (list 'no-raise 'statement) 1 0))
  (with-memory-db
   (lambda (db)
     (returned the-who (checked-out the-who db "select 1" #f #f))
     (let* ((after (lambda (r calls)
                     (list r (calls) (states-of db) (statement-count) (database-cache-count db))))
            (a (let-values (((check calls) (check-after 0)))
                 (after (handler-depth (lambda () (checked-out the-who db "select 1" #f check))) calls)))
            (b (let-values (((check calls) (check-after 0)))
                 (after (handler-depth (lambda () (checked-out the-who db "select 2" #f check))) calls)))
            (c (let-values (((check calls) (check-after 1)))
                 (after (handler-depth (lambda () (checked-out the-who db "select 2" #f check))) calls)))
            (d (handler-depth (lambda () (checked-out the-who 'x "select 1" #f 'x))))
            (e (let-values (((check calls) (check-after 1)))
                 (let* ((r (handler-depth (lambda () (checked-out the-who db "select 1" #f check))))
                        (out (database-cache-count db)))
                   (guard (x (#t #f)) (returned the-who (car (tracked-statements db))))
                   (list r (calls) out)))))
       (list a b c d e)))))

(test-equal "prepared-at reads its call's check first in its section: answering true, it raises &sqlite-closed from its who, at depth 1, nothing prepared, the check called once; a check that is no procedure is refused from its who before the database is checked; one answering #f prepares"
  (list (list (at-depth-1 (closed the-who)) 1 0)
        (at-depth-1 (refused the-who 'not-a-procedure 'x))
        (list (list 'no-raise (list 'prepared "select 1" 'ready 8)) 1))
  (with-memory-db
   (lambda (db)
     (with-script db "select 1"
       (lambda (sql bytes block)
         (let* ((a (let-values (((check calls) (check-after 0)))
                     (list (handler-depth (lambda () (prepared-at the-who db sql bytes block 0 0 #f check)))
                           (calls) (statement-count))))
                (b (handler-depth (lambda () (prepared-at the-who 'x sql bytes block 0 0 #f 'x))))
                (c (let-values (((check calls) (check-after 1)))
                     (let ((o (attempt (lambda () (prepared-at the-who db sql bytes block 0 0 #f check)))))
                       (list (list 'no-raise (shown-outcome o)) (calls))))))
           (list a b c)))))))

(test-equal "bind-each!/who reads its call's check first in the count's section and in each value's: answering true at the count, it raises &sqlite-closed from its who, at depth 1, nothing bound; true at the first value's, the same; true at the second's, the first value bound and the second not; a check that is no procedure is refused from its who; one answering #f binds both"
  (list (list (at-depth-1 (closed the-who)) 1 '(null null))
        (list (at-depth-1 (closed the-who)) 2 '(null null))
        (list (at-depth-1 (closed the-who)) 3 '(1 null))
        (at-depth-1 (refused the-who 'not-a-procedure 'x))
        (list (list 'no-raise 'no-value) 3 '(1 2)))
  (with-memory-db
   (lambda (db)
     (let ((bound-after
            (lambda (n)
              (let-values (((check calls) (check-after n)))
                (let* ((st (prepare-statement db "select ?1, ?2"))
                       (r (handler-depth (lambda () (bind-each!/who the-who st '(1 2) check))))
                       (s (step! st))
                       (read (lambda (i) (let ((v (column-value st i))) (if (integer? v) v 'null))))
                       (x (read 0))
                       (y (read 1)))
                  (finalize-statement! st)
                  (list r (calls) (list x y)))))))
       (let* ((a (bound-after 0))
              (b (bound-after 1))
              (c (bound-after 2))
              (d (let ((st (prepare-statement db "select ?1")))
                   (let ((r (handler-depth (lambda () (bind-each!/who the-who st '(1) 'x)))))
                     (finalize-statement! st)
                     r)))
              (e (bound-after 3)))
         (list a b c d e))))))

(test-equal "while-held reads its call's check first, in a critical section around its thunk: answering true, it raises &sqlite-closed from its who, at depth 1, the thunk never run; answering #f, the thunk runs inside the section, at depth 2, and its answers come back, all of them; what the thunk raises comes back the same object, at depth 1; with no check, the thunk runs plainly, at depth 1; a check that is no procedure is refused from its who"
  (list (list (at-depth-1 (closed the-who)) 'thunk-not-run)
        (list '(1 2 depth-2) 'the-same-object)
        (at-depth-1 (refused 'the-thunk 'raised))
        '(3 depth-1)
        (at-depth-1 (refused the-who 'not-a-procedure 'x)))
  (let* ((ran #f)
         (depth (lambda () (string->symbol (string-append "depth-" (number->string (interrupt-depth))))))
         (a (let-values (((check calls) (check-after 0)))
              (list (handler-depth (lambda () (while-held the-who check (lambda () (set! ran #t) 1))))
                    (if ran 'thunk-ran 'thunk-not-run))))
         (mine (make-who-condition 'mine))
         (b (let-values (((check calls) (check-after 1)))
              (list (call-with-values (lambda () (while-held the-who check (lambda () (values 1 2 (depth))))) list)
                    (guard (c (#t (if (eq? c mine) 'the-same-object 'another)))
                      (let-values (((check calls) (check-after 1)))
                        (while-held the-who check (lambda () (raise mine))))))))
         (c (let-values (((check calls) (check-after 1)))
              (handler-depth (lambda () (while-held the-who check
                                          (lambda () (assertion-violation 'the-thunk "raised" 'raised)))))))
         (d (call-with-values (lambda () (while-held the-who #f (lambda () (values 3 (depth))))) list))
         (e (handler-depth (lambda () (while-held the-who 'x (lambda () 4))))))
    (list a b c d e)))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "statement-who")

(exit (suite-exit-status runner))
