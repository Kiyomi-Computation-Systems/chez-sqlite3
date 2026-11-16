#!r6rs
;;; The suite for prepared statements, (chez-sqlite3 private statement), and
;;; the connection's tracking of them in (chez-sqlite3 private connection)
;;; (ADR-0014; ADR-0012 and ADR-0013, amended).
;;;
;;;   prepare        a statement, ready, counted and tracked; statement-sql a
;;;                  copy; the parameter and column counts SQLite gives
;;;                  (measured on 3.53.1 and 3.45.1); SQL holding no
;;;                  statement, more than one, U+0000, or no string, each
;;;                  refused by its rule; the length check on numbers, never
;;;                  on 2 GiB; a failure's code, SQL and character offset, #f
;;;                  for SQLite's -1; a refused SQL's first statement prepared,
;;;                  so pragma cache_size = 7; select 1 sets the cache size
;;;   decision 3     a non-statement, the wrong thread, a finalized statement,
;;;                  in that order, for every verb; finalize-statement! twice
;;;   the states     every verb in every state, and call-with-statement-handle
;;;                  for every verb of the table in every state, slice 4's too
;;;   step           #t then #f; done and failed refused until reset!; a
;;;                  failed step's extended code; the subtypes by real SQL: a
;;;                  constraint, a read-only database, another's lock
;;;   reset, finalize
;;;                  each one's own failure, an insert ... returning stepped
;;;                  once under another connection's read, raised; a failed
;;;                  step's code, which they repeat, not raised again
;;;   the close      every tracked statement finalized, oldest first: the one
;;;                  failure the measured case reaches raised, with the SQL
;;;                  of the statement finalized last, the connection closed;
;;;                  a statement kept past the close refused; a close that
;;;                  fails, held by a backup, raising its own failure; an
;;;                  untracked statement refused; first-finalize-failure on
;;;                  synthetic outcomes
;;;   call-with-statement
;;;                  as call-with-database: return, raise, escape, re-entry,
;;;                  a warning, and a finalize that fails after each
;;;   the docs       what docs/reference.md says of a statement, each by a row: a
;;;                  call-with-statement's prepare carries an offset; column-count
;;;                  moves at the next step after an alter table; a commit
;;;                  refused mid-row is busy; reset! keeps its bindings
;;;   the accessor   the record opaque; the SQL handed to the procedure; a
;;;                  message's leading U+FEFF kept
;;;   after the section
;;;                  every verb's raises, read by a with-exception-handler
;;;                  handler at depth 1, against a no-raise sentinel
;;;   engines        two engines on one thread, one stepping and the other
;;;                  finalizing or closing, at every fuel from 1 to 60; a
;;;                  prepare, step and finalize at every fuel; and whether
;;;                  call-with-statement survives an engine's preemption
;;;
;;; The four __collect_safe calls are held by behaviour in
;;; tests/test-statement-block.sps, the tail scan against SQLite's own
;;; prepare in tests/test-statement-tail.sps, and decision 10's "change
;;; together", an engine's expiry between a verb's section and its tracking or
;;; state, in tests/test-statement-sections.sps.
;;;
;;; The loading procedures are reached through eval, under a guard, as
;;; tests/test-connection.sps reaches them: a refused library fails the rows
;;; by name. SQLite's measured answers (build/m2s3/'s probes, on both
;;; libraries) are written out where a row expects them. A column is read
;;; here through call-with-statement-handle and native's sqlite3_column_int64,
;;; since the column verbs are slice 4's.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets; a row that leaves a connection or a
;;; statement open on purpose undoes it under dynamic-wind (ADR-0005).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure fork-thread make-mutex with-mutex sleep make-time
              get-thread-id disable-interrupts enable-interrupts make-engine library-exports
              string-set!)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3 private conditions) sqlite-busy? sqlite-constraint? sqlite-read-only?)
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
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define call-with-database (reach '(chez-sqlite3) 'call-with-database))
(define database? (reach '(chez-sqlite3) 'database?))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define tracked-statements (reach '(chez-sqlite3 private connection) 'tracked-statements))
(define first-finalize-failure (reach '(chez-sqlite3 private connection) 'first-finalize-failure))
(define track-statement! (reach '(chez-sqlite3 private connection) 'track-statement!))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define call-with-statement (reach statement-library 'call-with-statement))
(define statement? (reach statement-library 'statement?))
(define statement-sql (reach statement-library 'statement-sql))
(define parameter-count (reach statement-library 'parameter-count))
(define step! (reach statement-library 'step!))
(define reset! (reach statement-library 'reset!))
(define column-count (reach statement-library 'column-count))
(define call-with-statement-handle (reach statement-library 'call-with-statement-handle))
(define statement-state (reach statement-library 'statement-state))
(define sql-length-fits? (reach statement-library 'sql-length-fits?))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-out-pointer (reach '(chez-sqlite3 private native) 'call-with-out-pointer))
(define sqlite3-column-int64 (reach '(chez-sqlite3 private native) 'sqlite3-column-int64))
(define sqlite3-bind-int64 (reach '(chez-sqlite3 private native) 'sqlite3-bind-int64))
(define sqlite3-errmsg (reach '(chez-sqlite3 private native) 'sqlite3-errmsg))
(define c-string->string (reach '(chez-sqlite3 private native) 'c-string->string))
(define statement-verbs (guard (e (#t '())) (eval 'statement-verbs (environment '(chez-sqlite3 private statement-state)))))

;; --- bindings made here, after the load ------------------------------------------------

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_prepare_v2(sqlite3*, const char *zSql, int nByte, sqlite3_stmt **, const char **pzTail)
(define prepare-v2 (bound 'sqlite3_prepare_v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int)))
;; int sqlite3_finalize(sqlite3_stmt*)
(define raw-finalize (bound 'sqlite3_finalize (foreign-procedure "sqlite3_finalize" (uptr) int)))
;; sqlite3_backup *sqlite3_backup_init(sqlite3 *pDest, const char *zDestName,
;;                                     sqlite3 *pSource, const char *zSourceName)
(define backup-init (bound 'sqlite3_backup_init (foreign-procedure "sqlite3_backup_init" (uptr uptr uptr uptr) uptr)))
;; int sqlite3_backup_finish(sqlite3_backup*)
(define backup-finish (bound 'sqlite3_backup_finish (foreign-procedure "sqlite3_backup_finish" (uptr) int)))

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

;; subtype-of : Condition -> Symbol
(define (subtype-of e)
  (cond ((sqlite-busy? e) 'busy)
        ((sqlite-constraint? e) 'constraint)
        ((sqlite-read-only? e) 'read-only)
        (else 'no-subtype)))

;; what-raised : Any -> Any
;; A raised object as this suite compares it: an &sqlite-error by its who,
;; code, extended code, SQL, offset, class, and whether its &message is its
;; message field; a library condition by its type, who and fields; an
;; assertion violation by its who and irritants; anything else as text.
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (sqlite-error-sql e) (sqlite-error-offset e) (subtype-of e)
               (if (and (message-condition? e) (string? (sqlite-error-message e))
                        (equal? (condition-message e) (sqlite-error-message e)))
                   'message-is-the-field
                   'message-differs)))
        ((sqlite-wrong-thread? e)
         (list 'wrong-thread (who-of e) (message-of e)
               (sqlite-wrong-thread-owner e) (sqlite-wrong-thread-caller e)))
        ((sqlite-closed? e) (list 'closed (who-of e) (message-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

;; sqlite-failure : Symbol Symbol Symbol (U String #f) (U Natural #f) Symbol -> List
;; What what-raised gives for an &sqlite-error with these fields.
(define (sqlite-failure who code extended sql offset subtype)
  (list 'sqlite-error who code extended sql offset subtype 'message-is-the-field))

(define (closed who) (list 'closed who 'message))
(define (refused who . irritants) (list 'assertion-violation who irritants))

;; attempt : (-> Any) -> Any
;; THUNK's answer, or (raised WHAT) for what it raised.
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

;; void? : Any -> Boolean
(define void-value (if #f #f))
(define (no-value x) (if (eq? x void-value) 'no-value x))

;; errmsg-after : Database (-> Any) -> Any
;; What THUNK raised, and whether its &sqlite-error's message is the one
;; sqlite3_errmsg gives for DB straight after, read here with nothing between:
;; the message read after the failing call, not before it, by comparing two
;; readings, never a message's words. (no-raise VALUE) when nothing raised.
(define (errmsg-after db thunk)
  (let ((r (guard (e (#t (cons raised-tag e))) (thunk))))
    (if (and (pair? r) (eq? (car r) raised-tag))
        (let* ((e (cdr r))
               (now (with-handle db (lambda (h) (c-string->string (sqlite3-errmsg h))))))
          (list (what-raised e)
                (if (and (sqlite-error? e) (equal? (sqlite-error-message e) now))
                    'the-message-after-the-call
                    (list 'another-message (and (sqlite-error? e) (sqlite-error-message e)) now))))
        (list 'no-raise r))))

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
        (list 'no-raise (no-value (thunk))))))))

(define (at-depth-1 what) (list 'raised-at-depth 'depth-1 what))

;; in-dir : (String -> Any) -> Any
(define (in-dir proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory proc)))

;; with-handle : Any (Positive-Integer -> A) -> A
(define (with-handle db proc) (call-with-open-handle 'test-statement db proc))

;; exec! : Database String -> Any
;; SQL prepared, stepped once and finalized: what step! answered.
(define (exec! db sql)
  (let* ((st (prepare-statement db sql))
         (answer (guard (e (#t (finalize-statement! st) (raise e))) (step! st))))
    (finalize-statement! st)
    answer))

;; column-int : Statement Natural -> Integer
;; Column I of ST's row, read through sqlite3_column_int64 inside
;; call-with-statement-handle, as slice 4's column-value will.
(define (column-int st i)
  (call-with-statement-handle 'test-statement st 'column-value
    (lambda (connection handle sql) (values #f (sqlite3-column-int64 handle i)))))

;; query-int : Database String -> Integer
;; The first column of SQL's first row.
(define (query-int db sql)
  (let* ((st (prepare-statement db sql))
         (answer (guard (e (#t (finalize-statement! st) (raise e)))
                   (step! st)
                   (column-int st 0))))
    (finalize-statement! st)
    answer))

;; make-table! : String -> Any
;; The database at PATH, made with table t, x unique, holding the one row 0.
(define (make-table! path)
  (attempt
   (lambda ()
     (let ((db (open-database path)))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (exec! db "create table t (x unique)")
           (exec! db "insert into t values (0)"))
         (lambda () (undo! '() (list db))))
       'made))))

;; undo! : (Listof Any) (Listof Any) -> Void
;; What a row left open on purpose, undone however it ends: STATEMENTS
;; finalized, then each of DATABASES closed. Nothing here raises.
(define (undo! statements databases)
  (for-each (lambda (s) (guard (e (#t #f)) (finalize-statement! s))) statements)
  (for-each (lambda (db) (guard (e (#t #f)) (close-database! db))) databases))

;; closing : (List (Listof Any)) (-> Any) -> Any
;; THUNK's answer, or what it raised, with every database in the list BOX
;; holds closed after, however it ends.
(define (closing box thunk)
  (dynamic-wind
    (lambda () #f)
    (lambda () (attempt thunk))
    (lambda () (undo! '() (car box)))))

;; with-memory-db : (Database -> Any) -> Any
;; PROC's answer, or what it raised, given a fresh :memory: database that is
;; closed after, however PROC ends.
(define (with-memory-db proc)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda () (attempt (lambda () (set! db (open-database ":memory:")) (proc db))))
      (lambda () (when db (undo! '() (list db)))))))

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

;; nul-at : String Natural -> String
;; S with U+0000 put at index I.
(define (nul-at s i)
  (string-append (substring s 0 i) "\x0;" (substring s i (string-length s))))

;; raw-prepare! : Database String -> Positive-Integer
;; A statement of SQL on DB, made here with the raw sqlite3_prepare_v2, so the
;; connection does not track it.
(define (raw-prepare! db sql)
  (with-handle db
    (lambda (h)
      (call-with-c-string 'test-statement sql
        (lambda (text)
          (let-values (((rc statement)
                        (call-with-out-pointer 'test-statement
                          (lambda (slot) (prepare-v2 h text -1 slot 0)))))
            (if (and (eqv? rc 0) (not (eqv? statement 0)))
                statement
                (error 'raw-prepare! "sqlite3_prepare_v2 did not answer a statement" rc))))))))

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

;; fuels : Positive-Integer -> (Listof Positive-Integer)
;; 1 to N.
(define (fuels n)
  (let loop ((i n) (found '()))
    (if (= i 0) found (loop (- i 1) (cons i found)))))

;; run-engine : (-> Any) Positive-Integer Positive-Integer -> (U (List Any Natural) (List 'unfinished Natural))
;; THUNK run in an engine of FUEL ticks a slice, resumed each time it expires
;; until it completes: its answer and how many times it expired; or
;; (unfinished CAP) once it has expired CAP times.
(define (run-engine thunk fuel cap)
  (let loop ((engine (make-engine thunk)) (expired 0))
    (if (>= expired cap)
        (list 'unfinished cap)
        (engine fuel
                (lambda (left . answers) (list (car answers) expired))
                (lambda (next) (loop next (+ expired 1)))))))

;; the verbs of this slice that take a statement alone, with their names.
(define statement-verb-procedures
  (list (cons 'finalize-statement! (lambda (st) (finalize-statement! st)))
        (cons 'statement-sql (lambda (st) (statement-sql st)))
        (cons 'parameter-count (lambda (st) (parameter-count st)))
        (cons 'step! (lambda (st) (step! st)))
        (cons 'reset! (lambda (st) (reset! st)))
        (cons 'column-count (lambda (st) (column-count st)))))

(test-begin "statement")

;; --- the load -------------------------------------------------------------------------------

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-equal "(chez-sqlite3 private statement) exports exactly its verbs, the accessor, statement-state and sql-length-fits?, and M3's internals: the who-taking verbs, checked-sql, prepared-at, the cache's checked-out and returned, and while-held, the section that reads a convenience's flag"
  '(call-with-statement call-with-statement-handle checked-out checked-sql column-count
    column-count/who finalize-statement! finalized parameter-count prepare-statement prepared
    prepared-at reset! reset!/who returned sql-length-fits? statement-sql statement-state
    statement? step! step!/who while-held)
  (guard (e (#t (list 'raised (describe e))))
    (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
               (library-exports statement-library))))

;; --- prepare ------------------------------------------------------------------------------

(test-equal "statement? holds for a live and a finalized statement, and for nothing else: a symbol, a string, a number, a database, a list holding a statement"
  '(statement statement not not not not not)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select 1"))
            (live (if (statement? st) 'statement 'not))
            (finalized (begin (finalize-statement! st) (if (statement? st) 'statement 'not))))
       (append (list live finalized)
               (map (lambda (x) (if (statement? x) 'statement 'not))
                    (list 'x "select 1" 42 db (list st))))))))

;; A record that record-rtd opens can be rebuilt from its type, and one that is
;; not sealed extended, so a caller could make a statement holding any handle.
;; Opaque, record-rtd raises instead; sealed cannot be held from here, since an
;; opaque record's type is out of reach, so nothing can name it as a parent
;; (the mutation log argues it).
(test-equal "a statement is opaque: record-rtd refuses it, from record-rtd, and record? says it is no record"
  '((assertion-violation record-rtd) #f)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select 1"))
            (r (guard (e ((and (assertion-violation? e) (who-condition? e))
                          (list 'assertion-violation (condition-who e)))
                         (#t (list 'other-raise (describe e))))
                 (list 'no-raise (record-type-name (record-rtd st)))))
            (is-record (record? st)))
       (finalize-statement! st)
       (list r is-record)))))

(test-equal "call-with-statement-handle gives its procedure the statement's SQL as a third argument: the copy made at prepare, equal to the SQL prepared and not the caller's string, ready and in a row alike"
  (list "select 1 /* sql */" #f "select 1 /* sql */" #f)
  (with-memory-db
   (lambda (db)
     (let* ((given (string-copy "select 1 /* sql */"))
            (st (prepare-statement db given))
            (a (call-with-statement-handle 'test-statement st 'column-count
                 (lambda (c h sql) (values #f sql))))
            (b (call-with-statement-handle 'test-statement st 'column-count
                 (lambda (c h sql) (values #f (eq? sql given)))))
            (stepped (step! st))
            (c (call-with-statement-handle 'test-statement st 'column-count
                 (lambda (c h sql) (values #f sql))))
            (d (call-with-statement-handle 'test-statement st 'column-count
                 (lambda (c h sql) (values #f (eq? sql given))))))
       (finalize-statement! st)
       (list a b c d)))))

(test-equal "prepare-statement: a statement, ready, tracked by its connection, counted; its SQL, no parameter, one column; finalized, it is untracked and counted down"
  (list 'statement 'ready 'tracked (with-statements 1) "select 1" 0 1
        'no-value 'finalized '() one-connection)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select 1"))
            (is (if (statement? st) 'statement 'not))
            (state (statement-state st))
            (tracked (if (equal? (tracked-statements db) (list st)) 'tracked (tracked-statements db)))
            (counts (native-counts))
            (sql (statement-sql st))
            (parameters (parameter-count st))
            (columns (column-count st))
            (f (no-value (finalize-statement! st)))
            (after (statement-state st))
            (tracked-after (tracked-statements db)))
       (list is state tracked counts sql parameters columns f after tracked-after (native-counts))))))

(test-equal "statement-sql is a copy: the caller's string changed after the prepare leaves it, and so does the string it answered, changed; two answers are two strings"
  '("select 1" "select 1" "select 1" two-strings)
  (with-memory-db
   (lambda (db)
     (let* ((given (string-copy "select 1"))
            (st (prepare-statement db given))
            (changed (begin (string-set! given 7 #\2) given))
            (first (statement-sql st))
            (seen (string-copy first))
            (changed-answer (begin (string-set! first 7 #\3) first))
            (second (statement-sql st))
            (third (statement-sql st)))
       (finalize-statement! st)
       (list seen second (if (string=? changed "select 2") third (list 'not-changed changed))
             (if (eq? second third) 'one-string 'two-strings))))))

(test-equal "parameter-count and column-count, as SQLite counts them: select ?, ? has 2 and 2; select :a, ?7, $b 8 and 3; select 1, 2, 3 0 and 3; create table 0 and 0"
  '(("select ?, ?" 2 2) ("select :a, ?7, $b" 8 3) ("select 1, 2, 3" 0 3) ("create table u (a, b)" 0 0))
  (with-memory-db
   (lambda (db)
     (let loop ((rest '("select ?, ?" "select :a, ?7, $b" "select 1, 2, 3" "create table u (a, b)"))
                (found '()))
       (if (null? rest)
           (reverse found)
           (let* ((st (prepare-statement db (car rest)))
                  (p (parameter-count st))
                  (c (column-count st)))
             (finalize-statement! st)
             (loop (cdr rest) (cons (list (car rest) p c) found))))))))

;; refusal-row : Any -> Any
;; What prepare-statement raised for SQL on a fresh :memory:, the counts at
;; the raise and after, and what the connection tracks after.
(define (refusal-row sql)
  (with-memory-db
   (lambda (db)
     (let* ((r (at-raise (lambda () (prepare-statement db sql))))
            (after (native-counts))
            (tracked (tracked-statements db)))
       (list r after tracked)))))

(define (refused-row irritants)
  (list (list (list 'assertion-violation 'prepare-statement irritants) one-connection)
        one-connection '()))

(test-equal "SQL holding no statement is refused by its rule, naming the SQL by its kind: empty, whitespace, a line comment, a block comment, a semicolon, two, a semicolon in whitespace, U+FEFF and one; nothing is counted or tracked"
  (map (lambda (sql) (refused-row '(no-statement (kind string))))
       '("" " \t\n\f\r" "-- c" "/* c */" ";" ";;" " ; " "\xFEFF;;"))
  (map refusal-row '("" " \t\n\f\r" "-- c" "/* c */" ";" ";;" " ; " "\xFEFF;;")))

(test-equal "SQL holding more than one statement is refused by its rule, at the tail's character index: 10 in select 1; select 2, 12 in select 'é'; x, past the é's two bytes; the first statement is finalized, so nothing is counted or tracked"
  (list (refused-row '(more-than-one-statement 10))
        (refused-row '(more-than-one-statement 12))
        (refused-row '(more-than-one-statement 9))
        (refused-row '(more-than-one-statement 16)))
  (map refusal-row '("select 1; select 2" "select 'é'; x" "select 1;x" "select 1 -- c\n; x")))

(test-equal "a refused SQL's first statement has been prepared: pragma cache_size = 7; select 1 is refused at index 23, and cache_size is 7 after, from a base of 11 the row sets first, since a build's default differs (Apple's is 2000, Guix's -2000); the connection then closes, nothing left on it"
  (list 11 (list (list 'assertion-violation 'prepare-statement '(more-than-one-statement 23))
                 one-connection)
        7 'closed zero-counts)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (call-with-statement db "pragma cache_size = 11" step!)
           (let* ((before (query-int db "pragma cache_size"))
                  (r (at-raise (lambda () (prepare-statement db "pragma cache_size = 7; select 1"))))
                  (after (query-int db "pragma cache_size"))
                  (closed (attempt (lambda () (close-database! db) 'closed))))
             (list before r after closed (native-counts))))))
      (lambda () (undo! '() (if db (list db) '()))))))

(test-equal "prepare passes no flags (ADR-0014, decision 4): a table-valued function, which SQLITE_PREPARE_NO_VTAB refuses, prepares and steps through prepare-statement: pragma_table_info('t') of a two-column table gives two rows then done, and counts 2; only the connection is counted"
  (list (list #t #t #f) 2 one-connection)
  (with-memory-db
   (lambda (db)
     (exec! db "create table t (a, b)")
     (let* ((st (prepare-statement db "select name from pragma_table_info('t')"))
            (steps (guard (e (#t (finalize-statement! st) (raise e)))
                     (let* ((one (step! st)) (two (step! st)) (three (step! st)))
                       (list one two three)))))
       (finalize-statement! st)
       (let ((rows (query-int db "select count(*) from pragma_table_info('t')")))
         (list steps rows (native-counts)))))))

(test-equal "SQL holding U+0000, first, in the middle and last, is refused by its rule, naming it by its kind, before anything is allocated: no block at the raise"
  (map (lambda (i) (refused-row '(sql-holds-nul (kind string)))) '(0 4 8))
  (map (lambda (i) (refusal-row (nul-at "select 1" i))) '(0 4 8)))

(test-equal "SQL that is no string is refused by its rule and shown-value: a symbol, a number, a list holding a string by its kind"
  (list (refused-row '(not-a-string x)) (refused-row '(not-a-string 42))
        (refused-row '(not-a-string (kind list))))
  (map refusal-row (list 'x 42 (list "select 1"))))

(test-equal "sql-length-fits?, on numbers: 0, 1, 2^31-3 and 2^31-2 bytes fit an nByte of the bytes and their NUL; 2^31-1, 2^31, 2^32-1, 2^32 and 2^64 do not, nor -1, 1.5, 2^31-2 inexact, a symbol, a string"
  '(#t #t #t #t #f #f #f #f #f #f #f #f #f #f)
  (map (lambda (n) (guard (e (#t (list 'raised (what-raised e)))) (sql-length-fits? n)))
       (list 0 1 (- (expt 2 31) 3) (- (expt 2 31) 2) (- (expt 2 31) 1) (expt 2 31) (- (expt 2 32) 1)
             (expt 2 32) (expt 2 64) -1 1.5 (inexact (- (expt 2 31) 2)) 'x "2")))

(test-equal "prepare-statement checks in order: what is no database first, before SQL that is no string; then the thread, before the SQL; a closed connection is refused &sqlite-closed, after the SQL's own checks"
  (list (refused 'prepare-statement 'not-a-database 'x)
        (list 'raised (list 'wrong-thread 'prepare-statement 'message 'main 'the-thread))
        (list 'raised (closed 'prepare-statement))
        (list 'raised (refused 'prepare-statement 'sql-holds-nul '(kind string)))
        zero-counts)
  (let* ((a (what-raised (guard (e (#t e)) (prepare-statement 'x 42))))
         (db (guard (e (#t #f)) (open-database ":memory:")))
         (b (from-another-thread (lambda () (prepare-statement db 42))))
         (closed (begin (guard (e (#t #f)) (close-database! db)) db))
         (c (attempt (lambda () (prepare-statement closed "select 1"))))
         (d (attempt (lambda () (prepare-statement closed "select\x0;1")))))
    (list a b c d (native-counts))))

;; failed-prepare-on : Database String -> Any
;; What prepare-statement raised for SQL on DB, the counts at the raise, and
;; whether the SQL field is the caller's string or a copy.
(define (failed-prepare-on db sql)
  (let* ((given (string-copy sql))
         (seen #f)
         (r (at-raise (lambda ()
                        (guard (e ((sqlite-error? e) (set! seen (sqlite-error-sql e)) (raise e)))
                          (prepare-statement db given))))))
    (list r (if (eq? seen given) 'the-callers-string 'a-copy))))

;; failed-prepare : String -> Any
;; SQL's failure on a fresh :memory:, its first prepare, then on the same
;; connection once it has prepared and finalized select 1: some offsets
;; differ by that on some builds (the coordinator's measurement, from slice
;; 4's research: select ?0), so a row keeps to inputs alike on both.
(define (failed-prepare sql)
  (with-memory-db
   (lambda (db)
     (let* ((fresh (failed-prepare-on db sql))
            (warm (finalize-statement! (prepare-statement db "select 1")))
            (used (failed-prepare-on db sql)))
       (list fresh used)))))

(define (failed-prepare-row sql extended offset)
  (let ((once (list (list (sqlite-failure 'prepare-statement 'error extended sql offset 'no-subtype)
                          one-connection)
                    'a-copy)))
    (list once once)))

;; Measured on 3.53.1 and 3.45.1 alike, on a fresh connection and a used one
;; (build/m2s3/probe-codes.sps and this row; M2 slice 2's log):
;; sqlite3_error_offset is 10 for nosuchcol after select 1, 13 bytes after
;; 'é', 0 for selectx, and -1 where SQLite gives none: an error at the end of
;; the SQL, a missing table, and a missing collation, whose code is the
;; extended 257.
(test-equal "a failed prepare raises &sqlite-error from prepare-statement, with a copy of the SQL and SQLite's offset in characters, #f for -1, the code prepare answered, extended, and nothing counted at the raise; alike on a connection's first prepare and on a used one"
  (list (failed-prepare-row "select 1, nosuchcol" 'error 10)
        (failed-prepare-row "select 'é', nosuchcol" 'error 12)
        (failed-prepare-row "selectx 1" 'error 0)
        (failed-prepare-row "select 1 +" 'error #f)
        (failed-prepare-row "select (" 'error #f)
        (failed-prepare-row "select é," 'error #f)
        (failed-prepare-row "select 'éé' from nosuchtable" 'error #f)
        (failed-prepare-row "select 'a' < 'b' collate no_such_collation" 'error-missing-collseq #f))
  (map failed-prepare
       '("select 1, nosuchcol" "select 'é', nosuchcol" "selectx 1" "select 1 +" "select (" "select é,"
         "select 'éé' from nosuchtable" "select 'a' < 'b' collate no_such_collation")))

;; --- decision 3's checks, in order --------------------------------------------------------

(test-equal "every verb refuses what is no statement, by its rule and shown-value, from the verb: a symbol, a number, a string by its kind, a database by its kind, a list holding a statement by its kind"
  (map (lambda (v)
         (list (car v)
               (map (lambda (irritant) (list 'raised (refused (car v) 'not-a-statement irritant)))
                    '(x 42 (kind string) (kind other) (kind list)))))
       statement-verb-procedures)
  (with-memory-db
   (lambda (db)
     (let ((st (prepare-statement db "select 1")))
       (map (lambda (v)
              (list (car v)
                    (map (lambda (x) (attempt (lambda () ((cdr v) x))))
                         (list 'x 42 "select 1" db (list st)))))
            statement-verb-procedures)))))

(test-equal "every verb on another thread raises &sqlite-wrong-thread from the verb, with a message, the owner the main thread and the caller the other; the statement is left as it was, ready and tracked"
  (append (map (lambda (v) (list (car v) (list 'raised (list 'wrong-thread (car v) 'message 'main 'the-thread))))
               statement-verb-procedures)
          (list 'ready 'tracked (with-statements 1)))
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select 1"))
            (r (map (lambda (v) (list (car v) (from-another-thread (lambda () ((cdr v) st)))))
                    statement-verb-procedures))
            (state (statement-state st))
            (tracked (if (equal? (tracked-statements db) (list st)) 'tracked 'untracked))
            (counts (native-counts)))
       (finalize-statement! st)
       (append r (list state tracked counts))))))

(test-equal "every verb on another thread refuses a finalized statement &sqlite-wrong-thread, not &sqlite-closed, and finalize-statement! too: the thread is checked before the statement is"
  (map (lambda (v) (list (car v) (list 'raised (list 'wrong-thread (car v) 'message 'main 'the-thread))))
       statement-verb-procedures)
  (with-memory-db
   (lambda (db)
     (let ((st (prepare-statement db "select 1")))
       (finalize-statement! st)
       (map (lambda (v) (list (car v) (from-another-thread (lambda () ((cdr v) st)))))
            statement-verb-procedures)))))

(test-equal "every verb but finalize-statement! refuses a finalized statement &sqlite-closed, from the verb, with a message; finalize-statement! does nothing, a second time and a third, and nothing is counted down twice"
  (list (map (lambda (v)
               (list (car v) (if (eq? (car v) 'finalize-statement!)
                                 'no-value
                                 (list 'raised (closed (car v))))))
             statement-verb-procedures)
        'no-value 'finalized one-connection)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select 1"))
            (f (finalize-statement! st))
            (r (map (lambda (v) (list (car v) (no-value (attempt (lambda () ((cdr v) st))))))
                    statement-verb-procedures))
            (again (no-value (attempt (lambda () (finalize-statement! st))))))
       (list r again (statement-state st) (native-counts))))))

(test-equal "a statement kept past its connection's close is finalized: every verb but finalize-statement! raises &sqlite-closed from the verb, and finalize-statement! does nothing"
  (list 'closed 'finalized
        (map (lambda (v)
               (list (car v) (if (eq? (car v) 'finalize-statement!)
                                 'no-value
                                 (list 'raised (closed (car v))))))
             statement-verb-procedures)
        zero-counts)
  (let* ((db (guard (e (#t #f)) (open-database ":memory:")))
         (st (guard (e (#t #f)) (prepare-statement db "select 1")))
         (c (attempt (lambda () (close-database! db) 'closed)))
         (state (attempt (lambda () (statement-state st))))
         (r (map (lambda (v) (list (car v) (no-value (attempt (lambda () ((cdr v) st))))))
                 statement-verb-procedures)))
    (list c state r (native-counts))))

;; --- the state table ----------------------------------------------------------------------
;; Each state reached by SQL on t, x unique, holding the row 0: ready, a
;; select prepared; row, it stepped once; done, twice; failed, an insert of
;; 0 stepped; finalized, a select finalized.

;; in-state : Database Symbol -> Statement
(define (in-state db state)
  (case state
    ((ready) (prepare-statement db "select x from t"))
    ((row) (let ((st (prepare-statement db "select x from t"))) (step! st) st))
    ((done) (let ((st (prepare-statement db "select x from t"))) (step! st) (step! st) st))
    ((failed) (let ((st (prepare-statement db "insert into t values (0)")))
                (guard (e (#t #f)) (step! st))
                st))
    (else (let ((st (prepare-statement db "select x from t"))) (finalize-statement! st) st))))

(define states '(ready row done failed finalized))

;; cell : (Statement -> Any) Symbol -> (List Symbol Any Symbol Natural)
;; VERB on a statement in STATE, in a fresh copy of the table: the state,
;; what VERB answered or raised, the state after, and the statement count.
(define (cell verb state)
  (with-file-db
   (lambda (path db)
     (let* ((st (in-state db state))
            (answer (no-value (attempt (lambda () (verb st)))))
            (after (statement-state st))
            (counted (cdr (assq 'statement (native-counts)))))
       (finalize-statement! st)
       (list state answer after counted)))))

(define (row-of verb) (map (lambda (state) (cell verb state)) states))

(define insert-sql "insert into t values (0)")
(define select-sql "select x from t")

(test-equal "step! in every state: ready gives #t and row; row gives #f, since t holds one row, and done; done and failed are refused by the rule, naming the state, and left so; finalized raises &sqlite-closed"
  (list (list 'ready #t 'row 1)
        (list 'row #f 'done 1)
        (list 'done (list 'raised (refused 'step! 'not-allowed-in-state 'done)) 'done 1)
        (list 'failed (list 'raised (refused 'step! 'not-allowed-in-state 'failed)) 'failed 1)
        (list 'finalized (list 'raised (closed 'step!)) 'finalized 0))
  (row-of step!))

(test-equal "reset! in every state gives ready, raising nothing: in failed, the reset repeats the step's code, 2067, and it is not raised again; finalized raises &sqlite-closed"
  (list (list 'ready 'no-value 'ready 1)
        (list 'row 'no-value 'ready 1)
        (list 'done 'no-value 'ready 1)
        (list 'failed 'no-value 'ready 1)
        (list 'finalized (list 'raised (closed 'reset!)) 'finalized 0))
  (row-of reset!))

(test-equal "finalize-statement! in every state finalizes, raising nothing, and counts the statement down: in failed, the finalize repeats the step's code, and it is not raised again; finalized does nothing"
  (list (list 'ready 'no-value 'finalized 0)
        (list 'row 'no-value 'finalized 0)
        (list 'done 'no-value 'finalized 0)
        (list 'failed 'no-value 'finalized 0)
        (list 'finalized 'no-value 'finalized 0))
  (row-of finalize-statement!))

(test-equal "statement-sql, parameter-count and column-count in every state answer, leaving the state; finalized raises &sqlite-closed"
  (list (list (list 'ready select-sql 'ready 1) (list 'row select-sql 'row 1) (list 'done select-sql 'done 1)
              (list 'failed insert-sql 'failed 1) (list 'finalized (list 'raised (closed 'statement-sql)) 'finalized 0))
        (list (list 'ready 0 'ready 1) (list 'row 0 'row 1) (list 'done 0 'done 1)
              (list 'failed 0 'failed 1) (list 'finalized (list 'raised (closed 'parameter-count)) 'finalized 0))
        (list (list 'ready 1 'ready 1) (list 'row 1 'row 1) (list 'done 1 'done 1)
              (list 'failed 0 'failed 1) (list 'finalized (list 'raised (closed 'column-count)) 'finalized 0)))
  (list (row-of statement-sql) (row-of parameter-count) (row-of column-count)))

;; The accessor's own table, for every verb statement-state knows, slice 4's
;; among them: PROC runs where the verb is allowed, and answers the two
;; handles' kinds; elsewhere the refusal, the state left as it was.
(define (accessor-cell verb state)
  (with-file-db
   (lambda (path db)
     (let* ((st (in-state db state))
            (answer (no-value
                     (attempt
                      (lambda ()
                        (call-with-statement-handle 'test-statement st verb
                          (lambda (connection handle sql)
                            (values #f
                                    (if (and (integer? connection) (positive? connection)
                                             (integer? handle) (positive? handle)
                                             (not (= connection handle)))
                                        'ran
                                        (list 'ran-with connection handle)))))))))
            (after (statement-state st)))
       (finalize-statement! st)
       (list answer after)))))

;; allowed-in : Symbol -> (Listof Symbol)
;; ADR-0014 decision 5's table, written out: where each verb is allowed.
(define (allowed-in verb)
  (case verb
    ((bind! bind-all! clear-bindings!) '(ready))
    ((step!) '(ready row))
    ((column-value column-bytevector) '(row))
    (else '(ready row done failed))))

(test-equal "from another thread, every verb in every state raises &sqlite-wrong-thread from the verb, finalize-statement! too: the thread is checked before the state and before finalized; each statement is left in its state"
  (map (lambda (state)
         (list state
               (map (lambda (v) (list (car v) (list 'raised (list 'wrong-thread (car v) 'message 'main 'the-thread))))
                    statement-verb-procedures)
               state))
       states)
  (map (lambda (state)
         (with-file-db
          (lambda (path db)
            (let* ((st (in-state db state))
                   (r (map (lambda (v) (list (car v) (from-another-thread (lambda () ((cdr v) st)))))
                           statement-verb-procedures))
                   (after (statement-state st)))
              (finalize-statement! st)
              (list state r after)))))
       states))

(test-equal "call-with-statement-handle, for each of the 12 verbs in each of the 5 states: its procedure runs, given two handles and the SQL, where decision 5 allows the verb; elsewhere it is refused, naming the state, which stays; finalized is &sqlite-closed, and nothing for finalize-statement!"
  (map (lambda (verb)
         (list verb
               (map (lambda (state)
                      (cond ((eq? state 'finalized)
                             (list (if (eq? verb 'finalize-statement!)
                                       'no-value
                                       (list 'raised (closed 'test-statement)))
                                   'finalized))
                            ((memq state (allowed-in verb)) (list 'ran state))
                            (else (list (list 'raised (refused 'test-statement 'not-allowed-in-state state))
                                        state))))
                    states)))
       '(bind! bind-all! clear-bindings! step! reset! column-value column-bytevector
         column-count column-name statement-sql parameter-count finalize-statement!))
  (map (lambda (verb) (list verb (map (lambda (state) (accessor-cell verb state)) states)))
       statement-verbs))

(test-equal "call-with-statement-handle checks its who, its verb and its procedure before the statement: each from itself or its who, by its rule"
  (list (list 'raised (refused 'call-with-statement-handle 'not-a-who '(kind string)))
        (list 'raised (refused 'call-with-statement-handle 'not-a-statement-verb 'no-such-verb))
        (list 'raised (refused 'test-statement 'not-a-procedure 'x))
        (list 'raised (refused 'test-statement 'not-a-statement 'x)))
  (list (attempt (lambda () (call-with-statement-handle "who" 'x 'step! (lambda (c h sql) 'ran))))
        (attempt (lambda () (call-with-statement-handle 'test-statement 'x 'no-such-verb (lambda (c h sql) 'ran))))
        (attempt (lambda () (call-with-statement-handle 'test-statement 'x 'step! 'x)))
        (attempt (lambda () (call-with-statement-handle 'test-statement 'x 'step! (lambda (c h sql) 'ran))))))

(test-equal "call-with-statement-handle answers every value its procedure answers after its first, the state, #f to leave it"
  '(1 2 3)
  (with-memory-db
   (lambda (db)
     (let ((st (prepare-statement db "select 1")))
       (call-with-values
        (lambda () (call-with-statement-handle 'test-statement st 'step! (lambda (c h sql) (values #f 1 2 3))))
        (lambda answers (finalize-statement! st) answers))))))

;; moved-to : Symbol Any -> Any
;; A ready statement given NEW as its procedure's first answer: what the
;; accessor answered or raised, and the state after.
(define (moved-to verb new)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select 1"))
            (r (no-value (attempt (lambda ()
                                    (call-with-statement-handle 'test-statement st verb
                                      (lambda (c h sql) (values new 'answer)))))))
            (after (statement-state st)))
       (finalize-statement! st)
       (list r after)))))

(test-equal "call-with-statement-handle sets the state its procedure answers first, in the same section: from ready, each of ready, row, done and failed becomes the statement's state, and #f leaves it ready"
  '((answer ready) (answer row) (answer done) (answer failed) (answer ready))
  (map (lambda (new) (moved-to 'column-count new)) '(ready row done failed #f)))

(test-equal "call-with-statement-handle refuses a first answer that is no live state, finalized among them, or no answer at all, by its rule, naming it, after the section; the state is left as it was"
  (list (list (list 'raised (refused 'call-with-statement-handle 'not-a-live-state 'finalized)) 'ready)
        (list (list 'raised (refused 'call-with-statement-handle 'not-a-live-state 'bogus)) 'ready)
        (list (list 'raised (refused 'call-with-statement-handle 'not-a-live-state #t)) 'ready)
        (list (list 'raised (refused 'call-with-statement-handle 'not-a-live-state '(kind string))) 'ready)
        (list (list 'raised (refused 'call-with-statement-handle 'not-a-live-state 'no-answer)) 'ready)
        (at-depth-1 (refused 'call-with-statement-handle 'not-a-live-state 'bogus)))
  (append
   (map (lambda (new) (moved-to 'column-count new)) (list 'finalized 'bogus #t "row"))
   (list (with-memory-db
          (lambda (db)
            (let* ((st (prepare-statement db "select 1"))
                   (r (attempt (lambda () (call-with-statement-handle 'test-statement st 'column-count
                                            (lambda (c h sql) (values))))))
                   (after (statement-state st)))
             (finalize-statement! st)
             (list r after))))
         (with-memory-db
          (lambda (db)
            (let* ((st (prepare-statement db "select 1"))
                   (r (handler-depth (lambda () (call-with-statement-handle 'test-statement st 'column-count
                                                  (lambda (c h sql) (values 'bogus 'answer)))))))
             (finalize-statement! st)
             r))))))

(test-equal "a moved state is the statement's for every verb after: a column read that answers failed leaves step! refused, naming failed, until reset!"
  (list 'failed (list 'raised (refused 'step! 'not-allowed-in-state 'failed)) 'no-value 'ready #t)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select 1"))
            (s (step! st))
            (m (call-with-statement-handle 'test-statement st 'column-value (lambda (c h sql) (values 'failed 'read))))
            (state (statement-state st))
            (a (attempt (lambda () (step! st))))
            (r (no-value (reset! st)))
            (sr (statement-state st))
            (b (step! st)))
       (finalize-statement! st)
       (list state a r sr b)))))

;; --- step ----------------------------------------------------------------------------------

(test-equal "step! on select 1: #t and row, then #f and done; refused there until reset!, after which #t again"
  (list #t 'row #f 'done (list 'raised (refused 'step! 'not-allowed-in-state 'done)) 'done
        'no-value 'ready #t 'row)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select 1"))
            (a (step! st)) (sa (statement-state st))
            (b (step! st)) (sb (statement-state st))
            (c (attempt (lambda () (step! st)))) (sc (statement-state st))
            (r (no-value (reset! st))) (sr (statement-state st))
            (d (step! st)) (sd (statement-state st)))
       (finalize-statement! st)
       (list a sa b sb c sc r sr d sd)))))

;; Measured on 3.53.1 and 3.45.1 alike (build/m2s3/probe-codes.sps): a unique
;; violation answers the extended 2067; a reset after it 2067, then 0.
(test-equal "a failed step raises &sqlite-error from step!, its code the step's own, extended: constraint and constraint-unique, a &sqlite-constraint, with the SQL and no offset; the statement is failed, step! is refused, reset! raises nothing, and the step fails again"
  (list (list 'raised (sqlite-failure 'step! 'constraint 'constraint-unique insert-sql #f 'constraint))
        'failed
        (list 'raised (refused 'step! 'not-allowed-in-state 'failed))
        'no-value 'ready
        (list 'raised (sqlite-failure 'step! 'constraint 'constraint-unique insert-sql #f 'constraint))
        1)
  (with-file-db
   (lambda (path db)
     (let* ((st (prepare-statement db insert-sql))
            (a (attempt (lambda () (step! st))))
            (sa (statement-state st))
            (b (attempt (lambda () (step! st))))
            (r (no-value (attempt (lambda () (reset! st)))))
            (sr (statement-state st))
            (c (attempt (lambda () (step! st)))))
       (finalize-statement! st)
       (list a sa b r sr c (query-int db "select count(*) from t"))))))

;; A trigger's RAISE(ABORT, text) reaches the message as the text, whose own
;; leading U+FEFF the lenient decoding of Chez's utf8->string would drop
;; (found by the review, build/m2s3-verify/feff-errmsg.sps; native's
;; c-string->string keeps it). The text is the SQL's own, so the row asserts
;; it whole, with a second message that has no U+FEFF as the control.
(test-equal "a failed step's message keeps a leading U+FEFF of the trigger's own text, and a text without one is unchanged"
  (list (list 'sqlite-error 'constraint 'constraint-trigger "\xFEFF;boom")
        (list 'sqlite-error 'constraint 'constraint-trigger "boom"))
  (with-memory-db
   (lambda (db)
     (let* ((made (begin (exec! db "create table t (x)")
                         (exec! db "create trigger tr before insert on t when new.x = 1 begin select raise(abort, '\xFEFF;boom'); end")
                         (exec! db "create trigger tq before insert on t when new.x = 2 begin select raise(abort, 'boom'); end")))
            (message-of-insert
             (lambda (sql)
               (guard (e ((sqlite-error? e)
                          (list 'sqlite-error (sqlite-error-code e) (sqlite-error-extended-code e)
                                (sqlite-error-message e)))
                         (#t (list 'other (describe e))))
                 (call-with-statement db sql (lambda (st) (step! st)))
                 'no-raise)))
            (a (message-of-insert "insert into t values (1)"))
            (b (message-of-insert "insert into t values (2)")))
       (list a b)))))

;; Measured (build/m2s3/probe-codes.sps): on a connection opened read-only, an
;; insert prepares, and its step answers 8, SQLITE_READONLY, with no extension.
(test-equal "a write to a database opened read-only: the insert prepares, and its step raises &sqlite-error, readonly and readonly, a &sqlite-read-only, with the SQL; the statement is failed, and its finalize, repeating the code, raises nothing"
  (list 'ready
        (list 'raised (sqlite-failure 'step! 'readonly 'readonly "insert into t values (1)" #f 'read-only))
        'failed 'no-value 'finalized)
  (with-file-db
   (lambda (path db)
     (let ((ro #f))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (set! ro (open-database path 'read-only))
           (let* ((st (prepare-statement ro "insert into t values (1)"))
                  (s0 (statement-state st))
                  (a (attempt (lambda () (step! st))))
                  (sa (statement-state st))
                  (f (no-value (attempt (lambda () (finalize-statement! st))))))
             (list s0 a sa f (statement-state st))))
         (lambda () (undo! '() (if ro (list ro) '()))))))))

;; reader! : String -> (Pairof Database Statement)
;; A second connection to PATH holding a read: a select of t stepped to its
;; row, until release! finalizes it and closes the connection.
(define (reader! path)
  (let* ((db (open-database path))
         (st (prepare-statement db "select x from t")))
    (step! st)
    (cons db st)))

(define (release! reader)
  (when (pair? reader) (undo! (list (cdr reader)) (list (car reader)))))

;; Measured (build/m2s3/probe-codes.sps): under another connection's read,
;; with no busy timeout, a plain insert's step answers 5 at once.
(test-equal "a lock held by a second connection: under its read, an insert's step raises &sqlite-error, busy and busy, a &sqlite-busy, with the SQL; the statement is failed, and the table keeps its one row"
  (list (list 'raised (sqlite-failure 'step! 'busy 'busy "insert into t values (5)" #f 'busy))
        'failed 1)
  (with-file-db
   (lambda (path db)
     (let ((reader #f))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (set! reader (reader! path))
           (let* ((st (prepare-statement db "insert into t values (5)"))
                  (a (attempt (lambda () (step! st))))
                  (sa (statement-state st)))
             (finalize-statement! st)
             (release! reader)
             (set! reader #f)
             (list a sa (query-int db "select count(*) from t"))))
         (lambda () (release! reader)))))))

;; --- reset's and finalize's own failures -----------------------------------------------------
;; An insert ... returning stepped once answers a row, and its commit runs at
;; its reset or finalize. Under another connection's read, with no busy
;; timeout, each answers 5 and the insert is rolled back (measured: M2 slice
;; 0's review, and build/m2s3/probe-codes.sps); a reset or finalize after a
;; reset that failed answers 0.

(define returning-sql "insert into t values (1), (2) returning x")

;; own-failure : (Statement -> Any) -> Any
;; FINISH on an insert ... returning stepped once under a reader: the first
;; step, what FINISH raised, the state after, a reset and a finalize after
;; that, the rows left, and the counts.
(define (own-failure finish)
  (with-file-db
   (lambda (path db)
     (let ((reader #f))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (set! reader (reader! path))
           (let* ((st (prepare-statement db returning-sql))
                  (s (step! st))
                  (a (no-value (attempt (lambda () (finish st)))))
                  (sa (statement-state st))
                  (again (no-value (attempt (lambda () (reset! st)))))
                  (f (no-value (attempt (lambda () (finalize-statement! st)))))
                  (sf (statement-state st)))
             (release! reader)
             (set! reader #f)
             (list s a sa again f sf (query-int db "select count(*) from t") (native-counts))))
         (lambda () (release! reader)))))))

(test-equal "reset!'s own failure: the insert ... returning's commit under a read raises &sqlite-error from reset!, busy, a &sqlite-busy, with the SQL; the statement is ready, a second reset and the finalize raise nothing, and the insert was rolled back"
  (list #t (list 'raised (sqlite-failure 'reset! 'busy 'busy returning-sql #f 'busy)) 'ready
        'no-value 'no-value 'finalized 1 one-connection)
  (own-failure reset!))

(test-equal "finalize-statement!'s own failure: the commit under a read raises &sqlite-error from finalize-statement!, busy, a &sqlite-busy, with the SQL; the statement is finalized, untracked and counted down all the same, and the insert was rolled back"
  (list #t (list 'raised (sqlite-failure 'finalize-statement! 'busy 'busy returning-sql #f 'busy))
        'finalized (list 'raised (closed 'reset!)) 'no-value 'finalized 1 one-connection)
  (own-failure finalize-statement!))

(test-equal "with no reader, the same reset! and finalize-statement! raise nothing, and the insert stands: 3 rows"
  (list (list #t 'no-value 'ready 'no-value 'no-value 'finalized 3 one-connection)
        (list #t 'no-value 'finalized (list 'raised (closed 'reset!)) 'no-value 'finalized 3 one-connection))
  (map (lambda (finish)
         (with-file-db
          (lambda (path db)
            (let* ((st (prepare-statement db returning-sql))
                   (s (step! st))
                   (a (no-value (attempt (lambda () (finish st)))))
                   (sa (statement-state st))
                   (again (no-value (attempt (lambda () (reset! st)))))
                   (f (no-value (attempt (lambda () (finalize-statement! st)))))
                   (sf (statement-state st)))
              (list s a sa again f sf (query-int db "select count(*) from t") (native-counts))))))
       (list reset! finalize-statement!)))

(test-equal "each verb's &sqlite-error carries the message sqlite3_errmsg gives straight after its call: a failed prepare, a failed step, reset's own failure and finalize's own"
  (list (list (sqlite-failure 'prepare-statement 'error 'error "select 1, nosuchcol" 10 'no-subtype) 'the-message-after-the-call)
        (list (sqlite-failure 'step! 'constraint 'constraint-unique insert-sql #f 'constraint) 'the-message-after-the-call)
        (list (sqlite-failure 'reset! 'busy 'busy returning-sql #f 'busy) 'the-message-after-the-call)
        (list (sqlite-failure 'finalize-statement! 'busy 'busy returning-sql #f 'busy) 'the-message-after-the-call))
  (with-file-db
   (lambda (path db)
     (let ((reader #f))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (let* ((a (errmsg-after db (lambda () (prepare-statement db "select 1, nosuchcol"))))
                  (st (prepare-statement db insert-sql))
                  (b (errmsg-after db (lambda () (step! st))))
                  (f (finalize-statement! st))
                  (rd (set! reader (reader! path)))
                  (r1 (prepare-statement db returning-sql))
                  (s1 (step! r1))
                  (c (errmsg-after db (lambda () (reset! r1))))
                  (f1 (finalize-statement! r1))
                  (r2 (prepare-statement db returning-sql))
                  (s2 (step! r2))
                  (d (errmsg-after db (lambda () (finalize-statement! r2)))))
             (list a b c d)))
         (lambda () (release! reader)))))))

;; --- the close that finalizes ----------------------------------------------------------------

(test-equal "a connection tracks its live statements, oldest first: three prepared, the middle one finalized, leaves the first and the last; the close finalizes both, and every count is zero"
  (list 'oldest-first 'first-and-last 'closed '(finalized finalized finalized) '() zero-counts)
  (let* ((db (guard (e (#t #f)) (open-database ":memory:")))
         (a (guard (e (#t #f)) (prepare-statement db "select 1")))
         (b (guard (e (#t #f)) (prepare-statement db "select 2")))
         (c (guard (e (#t #f)) (prepare-statement db "select 3")))
         (three (attempt (lambda () (if (equal? (tracked-statements db) (list a b c)) 'oldest-first (tracked-statements db)))))
         (f (attempt (lambda () (finalize-statement! b))))
         (two (attempt (lambda () (if (equal? (tracked-statements db) (list a c)) 'first-and-last (tracked-statements db)))))
         (closed (attempt (lambda () (close-database! db) 'closed)))
         (states (map (lambda (st) (attempt (lambda () (statement-state st)))) (list a b c)))
         (after (attempt (lambda () (tracked-statements db)))))
    (list three two closed states after (native-counts))))

;; two-returning : String -> Any
;; Two insert ... returning statements, A then B, each stepped once under a
;; reader on PATH's database: what close-database! raised, the connection
;; after, both statements' states, the rows left, and the counts.
(define (two-returning)
  (with-file-db
   (lambda (path db)
     (let ((reader #f))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (set! reader (reader! path))
           (let* ((a (prepare-statement db "insert into t values (1) returning 'a'"))
                  (b (prepare-statement db "insert into t values (2) returning 'b'"))
                  (sa (step! a))
                  (sb (step! b))
                  (r (attempt (lambda () (close-database! db) 'closed)))
                  (handle (attempt (lambda () (with-handle db (lambda (h) 'still-open)))))
                  (states (list (statement-state a) (statement-state b)))
                  (counts (native-counts)))
             (release! reader)
             (set! reader #f)
             (list sa sb r handle states counts
                   (let ((other (open-database path)))
                     (let ((n (guard (e (#t (close-database! other) (raise e)))
                                (query-int other "select count(*) from t"))))
                       (close-database! other)
                       n)))))
         (lambda () (release! reader)))))))

;; Measured (build/m2s3/probe-close.sps), on both libraries: of two inserts
;; stepped once under a read, the one finalized second answers 5 and the
;; first 0, whichever was prepared first, and both are rolled back. So the
;; SQL of the failure the close raises names the statement it finalized
;; last: the newest, when it finalizes oldest first.
(test-equal "close-database! finalizes oldest first: of two inserts stepped once under a read, the failure raised is the newer's, busy, with its SQL, from close-database!; the connection is closed, both statements finalized, both inserts rolled back, and nothing is counted but the reader and its statement, until they are closed"
  (list #t #t
        (list 'raised (sqlite-failure 'close-database! 'busy 'busy "insert into t values (2) returning 'b'" #f 'busy))
        (list 'raised (closed 'test-statement))
        '(finalized finalized)
        (with-statements 1)
        1)
  (two-returning))

(test-equal "first-finalize-failure, on synthetic outcomes: none for none, or when every finalize succeeded; else the first failure, in order, a raise among them"
  (list #f #f '(failed 5 "first" "select 1") '(raised r) '(failed 19 "only" "x"))
  (list (first-finalize-failure '())
        (first-finalize-failure '(finalized finalized))
        (first-finalize-failure '(finalized (failed 5 "first" "select 1") (failed 6 "last" "select 2")))
        (first-finalize-failure '((raised r) (failed 5 "a" "b")))
        (first-finalize-failure '(finalized finalized (failed 19 "only" "x")))))

;; entries-row : (Listof (Pairof Symbol (-> Any))) -> Any
;; A :memory: connection tracking, besides nothing real, one entry made here
;; per (KEY . ANSWER): a finalize that records its key and the handle's kind,
;; then answers ANSWER's value. What close-database! raised, by what-raised or
;; as the very object, the order the entries were finalized in, and the
;; connection and counts after.
(define (entries-row entries planted)
  (let ((db (guard (e (#t #f)) (open-database ":memory:"))) (order '()))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (for-each (lambda (entry)
                       (track-statement! db (car entry)
                                         (lambda (handle)
                                           (set! order (cons (list (car entry) (if (and (integer? handle) (positive? handle)) 'handle handle))
                                                             order))
                                           ((cdr entry)))))
                     entries)
           (let* ((r (guard (e ((eq? e planted) (list 'raised 'the-planted-object))
                               (#t (list 'raised (what-raised e))))
                       (close-database! db)
                       'closed))
                  (handle (attempt (lambda () (with-handle db (lambda (h) 'still-open))))))
             (list r (reverse order) handle (native-counts))))))
      (lambda () (undo! '() (if db (list db) '()))))))

(define planted-object (list 'planted))

(test-equal "the close keeps the first failure: three entries tracked here, the first finalized, the second and third each reporting a failure: close-database! raises the second's, busy, with its SQL, after finalizing all three, oldest first, each given the handle; the connection is closed"
  (list (list 'raised (sqlite-failure 'close-database! 'busy 'busy "select 'b'" #f 'busy))
        '((a handle) (b handle) (c handle)) (list 'raised (closed 'test-statement)) zero-counts)
  (entries-row (list (cons 'a (lambda () 'finalized))
                     (cons 'b (lambda () '(failed 5 "second" "select 'b'")))
                     (cons 'c (lambda () '(failed 19 "third" "select 'c'"))))
               planted-object))

(test-equal "an entry whose finalize raises counts as its failure: the close raises that very object, once every entry is finalized, and the connection is closed"
  (list (list 'raised 'the-planted-object) '((a handle) (b handle)) (list 'raised (closed 'test-statement)) zero-counts)
  (entries-row (list (cons 'a (lambda () (raise planted-object)))
                     (cons 'b (lambda () '(failed 5 "second" "select 'b'"))))
               planted-object))

;; Measured (build/m2s3/probe-close.sps), on both libraries: a backup reading
;; from the connection makes sqlite3_close answer 5 with every statement
;; finalized; nothing in M2's own entry points can (SQLite's documentation
;; names unfinalized statements, unfinished backups and open BLOB handles).
(test-equal "a close that fails, after a finalize that failed: the close's own failure is raised, busy, with no SQL; the statement is finalized and counted down, the connection open and counted; once the backup is finished the connection closes, raising nothing, and the finalize's failure is lost"
  (list 'backup
        (list 'raised (sqlite-failure 'close-database! 'busy 'busy #f #f 'busy))
        'finalized '() (counts-with '((connection . 3) (statement . 1))) 'still-open 0 'closed
        zero-counts)
  (in-dir
   (lambda (dir)
     (let ((path (string-append dir "/t.db")) (db #f) (target #f) (reader #f) (backup #f))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (attempt
            (lambda ()
              (make-table! path)
              (set! db (open-database path))
              (set! target (open-database ":memory:"))
              (set! reader (reader! path))
              (let* ((st (prepare-statement db returning-sql))
                     (s (step! st)))
                (set! backup
                      (with-handle target
                        (lambda (t)
                          (with-handle db
                            (lambda (s)
                              (call-with-c-string 'test-statement "main"
                                (lambda (main) (backup-init t main s main))))))))
                (let* ((made (if (eqv? backup 0) 'no-backup 'backup))
                       (r (attempt (lambda () (close-database! db) 'closed)))
                       (state (statement-state st))
                       (tracked (tracked-statements db))
                       (counts (native-counts))
                       (handle (attempt (lambda () (with-handle db (lambda (h) 'still-open)))))
                       (finished (let ((code (backup-finish backup))) (set! backup #f) code))
                       (release (begin (release! reader) (set! reader #f)))
                       (closed (attempt (lambda () (close-database! db) 'closed)))
                       (last (begin (close-database! target) (native-counts))))
                  (list made r state tracked counts handle finished closed last))))))
         (lambda ()
           (when (and backup (not (eqv? backup 0))) (guard (e (#t #f)) (backup-finish backup)))
           (release! reader)
           (undo! '() (filter (lambda (x) x) (list db target)))))))))

(test-equal "an untracked statement, made with a raw prepare, beside a tracked one: close-database! finalizes the tracked one, then refuses, naming the count; the connection stays open; once the raw one is finalized it closes"
  (list (list 'raised (refused 'close-database! 'untracked-statements 1))
        'finalized '() one-connection 'still-open 0 'closed zero-counts)
  (let ((db #f) (raw #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let* ((st (prepare-statement db "select 1")))
             (set! raw (raw-prepare! db "select 2"))
             (let* ((r (attempt (lambda () (close-database! db) 'closed)))
                    (state (statement-state st))
                    (tracked (tracked-statements db))
                    (counts (native-counts))
                    (handle (attempt (lambda () (with-handle db (lambda (h) 'still-open)))))
                    (code (let ((c (raw-finalize raw))) (set! raw #f) c))
                    (closed (attempt (lambda () (close-database! db) 'closed))))
               (list r state tracked counts handle code closed (native-counts)))))))
      (lambda ()
        (when raw (guard (e (#t #f)) (raw-finalize raw)))
        (undo! '() (if db (list db) '()))))))

(test-equal "call-with-database's close finalizes what the procedure left: a statement stepped and left, finalized after, and every count zero"
  (list 'row 'finalized zero-counts)
  (let* ((kept #f)
         (state (attempt (lambda ()
                           (call-with-database ":memory:"
                             (lambda (db)
                               (set! kept (prepare-statement db "select 1"))
                               (step! kept)
                               (statement-state kept)))))))
    (list state (attempt (lambda () (statement-state kept))) (native-counts))))

;; --- call-with-statement --------------------------------------------------------------------

(test-equal "call-with-statement: the procedure's two values come back; inside, the statement is ready, tracked and counted; after, it is finalized and untracked, and only the connection is counted"
  (list (list 'ready 'tracked (with-statements 1) 'x 'y) 'finalized '() one-connection)
  (with-memory-db
   (lambda (db)
     (let* ((kept #f)
            (answers (call-with-values
                      (lambda ()
                        (call-with-statement db "select 1"
                          (lambda (st)
                            (set! kept st)
                            (values (list (statement-state st)
                                          (if (equal? (tracked-statements db) (list st)) 'tracked 'untracked)
                                          (native-counts))
                                    'x 'y))))
                      (lambda (inside x y) (append inside (list x y))))))
       (list answers (statement-state kept) (tracked-statements db) (native-counts))))))

(test-equal "call-with-statement: the procedure's raise reaches the caller as the same object, and the statement is finalized"
  (list 'the-same-object 'finalized one-connection)
  (with-memory-db
   (lambda (db)
     (let* ((kept #f)
            (mine (list 'mine))
            (caught (guard (e (#t (if (eq? e mine) 'the-same-object (list 'another e))))
                      (call-with-statement db "select 1"
                        (lambda (st) (set! kept st) (raise mine))))))
       (list caught (statement-state kept) (native-counts))))))

(test-equal "call-with-statement: a warning the procedure raises with raise-continuable reaches an outer handler that returns, and the procedure goes on with its value; the statement is then finalized"
  (list '(proc-saw handled) 'finalized one-connection)
  (with-memory-db
   (lambda (db)
     (let* ((kept #f)
            (r (with-exception-handler
                (lambda (c) 'handled)
                (lambda ()
                  (call-with-statement db "select 1"
                    (lambda (st)
                      (set! kept st)
                      (list 'proc-saw (raise-continuable (make-warning)))))))))
       (list r (statement-state kept) (native-counts))))))

(test-equal "call-with-statement: an escape through a continuation finalizes the statement"
  (list 'escaped 'finalized one-connection)
  (with-memory-db
   (lambda (db)
     (let* ((kept #f)
            (r (call/cc (lambda (out)
                          (call-with-statement db "select 1"
                            (lambda (st) (set! kept st) (out 'escaped)))))))
       (list r (statement-state kept) (native-counts))))))

(test-equal "call-with-statement: a continuation that re-enters the procedure finds the statement finalized, its step! raising &sqlite-closed; nothing is prepared again"
  (list 2 (list (list 1 'ready) (list 2 (list 'raised (closed 'step!)))) one-connection)
  (with-memory-db
   (lambda (db)
     (let ((k #f) (runs 0) (seen '()))
       (call-with-statement db "select 1"
         (lambda (st)
           (call/cc (lambda (c) (set! k c)))
           (set! runs (+ runs 1))
           (set! seen (cons (list runs (if (= runs 1) (statement-state st) (attempt (lambda () (step! st)))))
                            seen))))
       (when (< runs 2) (k 'again))
       (list runs (reverse seen) (native-counts))))))

(test-equal "call-with-statement: a finalize that fails after the procedure returned raises, from call-with-statement, busy, with the SQL; the statement is finalized"
  (list (list 'raised (sqlite-failure 'call-with-statement 'busy 'busy returning-sql #f 'busy))
        'finalized 1)
  (with-file-db
   (lambda (path db)
     (let ((reader #f) (kept #f))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (set! reader (reader! path))
           (let ((r (attempt (lambda ()
                               (call-with-statement db returning-sql
                                 (lambda (st) (set! kept st) (step! st) 'returned))))))
             (release! reader)
             (set! reader #f)
             (list r (statement-state kept) (query-int db "select count(*) from t"))))
         (lambda () (release! reader)))))))

(test-equal "call-with-statement: a finalize that fails after the procedure raised does not mask the procedure's condition, which reaches the caller as the same object; the statement is freed"
  (list 'the-same-object 'finalized one-connection)
  (with-file-db
   (lambda (path db)
     (let ((reader #f) (kept #f) (mine (list 'mine)))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (set! reader (reader! path))
           (let ((r (guard (e (#t (if (eq? e mine) 'the-same-object (list 'another (what-raised e)))))
                      (call-with-statement db returning-sql
                        (lambda (st) (set! kept st) (step! st) (raise mine))))))
             (release! reader)
             (set! reader #f)
             (list r (statement-state kept) (native-counts))))
         (lambda () (release! reader)))))))

(test-equal "call-with-statement: a finalize that fails after an escape raises"
  (list (list 'raised (sqlite-failure 'call-with-statement 'busy 'busy returning-sql #f 'busy)) 'finalized)
  (with-file-db
   (lambda (path db)
     (let ((reader #f) (kept #f))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (set! reader (reader! path))
           (let ((r (attempt (lambda ()
                               (call/cc (lambda (out)
                                          (call-with-statement db returning-sql
                                            (lambda (st) (set! kept st) (step! st) (out 'escaped)))))))))
             (release! reader)
             (set! reader #f)
             (list r (statement-state kept))))
         (lambda () (release! reader)))))))

(test-equal "call-with-statement checks its procedure first, before the database and the SQL; then prepare-statement's checks and refusals, each from call-with-statement; the procedure never runs, and nothing is counted"
  (list (list 'raised (refused 'call-with-statement 'not-a-procedure 'p))
        (list 'raised (refused 'call-with-statement 'not-a-database 'x))
        (list 'raised (refused 'call-with-statement 'not-a-string 42))
        (list 'raised (refused 'call-with-statement 'sql-holds-nul '(kind string)))
        (list 'raised (refused 'call-with-statement 'no-statement '(kind string)))
        (list 'raised (refused 'call-with-statement 'more-than-one-statement 10))
        (list 'raised (sqlite-failure 'call-with-statement 'error 'error "selectx 1" 0 'no-subtype))
        'not-run one-connection)
  (with-memory-db
   (lambda (db)
     (let* ((ran 'not-run)
            (proc (lambda (st) (set! ran 'ran)))
            (r (list (attempt (lambda () (call-with-statement 'x 42 'p)))
                     (attempt (lambda () (call-with-statement 'x 42 proc)))
                     (attempt (lambda () (call-with-statement db 42 proc)))
                     (attempt (lambda () (call-with-statement db "select\x0;1" proc)))
                     (attempt (lambda () (call-with-statement db " -- c" proc)))
                     (attempt (lambda () (call-with-statement db "select 1; select 2" proc)))
                     (attempt (lambda () (call-with-statement db "selectx 1" proc))))))
       (append r (list ran (native-counts)))))))

;; --- every raise after its section --------------------------------------------------------
;; A with-exception-handler handler of a raise made inside a critical section
;; runs with interrupts disabled, at depth 2; after it, at depth 1. Each row's
;; handler reads its depth, and what was raised: depth-1, and the verb's own
;; condition. The no-raise sentinel, (no-raise VALUE), is no depth.

(test-equal "prepare-statement raises after its section: a failed prepare, no statement, more than one, U+0000, a closed connection and no database each reach a handler at depth 1"
  (list (at-depth-1 (sqlite-failure 'prepare-statement 'error 'error "selectx 1" 0 'no-subtype))
        (at-depth-1 (refused 'prepare-statement 'no-statement '(kind string)))
        (at-depth-1 (refused 'prepare-statement 'more-than-one-statement 10))
        (at-depth-1 (refused 'prepare-statement 'sql-holds-nul '(kind string)))
        (at-depth-1 (closed 'prepare-statement))
        (at-depth-1 (refused 'prepare-statement 'not-a-database 'x))
        zero-counts)
  (let* ((db (guard (e (#t #f)) (open-database ":memory:")))
         (r (list (handler-depth (lambda () (prepare-statement db "selectx 1")))
                  (handler-depth (lambda () (prepare-statement db ";")))
                  (handler-depth (lambda () (prepare-statement db "select 1; select 2")))
                  (handler-depth (lambda () (prepare-statement db "select\x0;1")))))
         (c (guard (e (#t #f)) (close-database! db)))
         (s (list (handler-depth (lambda () (prepare-statement db "select 1")))
                  (handler-depth (lambda () (prepare-statement 'x "select 1"))))))
    (append r s (list (native-counts)))))

(test-equal "step! raises after its section: a failed step, a refusal in done, a finalized statement, and the wrong thread each reach a handler at depth 1"
  (list (at-depth-1 (sqlite-failure 'step! 'constraint 'constraint-unique insert-sql #f 'constraint))
        (at-depth-1 (refused 'step! 'not-allowed-in-state 'done))
        (at-depth-1 (closed 'step!))
        (at-depth-1 (list 'wrong-thread 'step! 'message 'main 'the-thread)))
  (with-file-db
   (lambda (path db)
     (let* ((failing (prepare-statement db insert-sql))
            (a (handler-depth (lambda () (step! failing))))
            (done (prepare-statement db "select 1"))
            (b (begin (step! done) (step! done) (handler-depth (lambda () (step! done)))))
            (finalized (prepare-statement db "select 1"))
            (c (begin (finalize-statement! finalized) (handler-depth (lambda () (step! finalized)))))
            (live (prepare-statement db "select 1"))
            (d (from-another-thread (lambda () (handler-depth (lambda () (step! live)))))))
       (for-each finalize-statement! (list failing done live))
       (list a b c d)))))

(test-equal "reset! and finalize-statement! raise their own failures after their sections, and reset! a finalized statement: each reaches a handler at depth 1"
  (list (at-depth-1 (sqlite-failure 'reset! 'busy 'busy returning-sql #f 'busy))
        (at-depth-1 (sqlite-failure 'finalize-statement! 'busy 'busy returning-sql #f 'busy))
        (at-depth-1 (closed 'reset!)))
  (with-file-db
   (lambda (path db)
     (let ((reader #f))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (set! reader (reader! path))
           (let* ((a (let ((st (prepare-statement db returning-sql)))
                       (step! st)
                       (let ((r (handler-depth (lambda () (reset! st)))))
                         (finalize-statement! st)
                         r)))
                  (st (prepare-statement db returning-sql))
                  (b (begin (step! st) (handler-depth (lambda () (finalize-statement! st)))))
                  (c (handler-depth (lambda () (reset! st)))))
             (list a b c)))
         (lambda () (release! reader)))))))

(test-equal "statement-sql, parameter-count and column-count raise after their sections: on a finalized statement, a not-a-statement and a closed, each at depth 1"
  (list (at-depth-1 (closed 'statement-sql)) (at-depth-1 (closed 'parameter-count))
        (at-depth-1 (closed 'column-count))
        (at-depth-1 (refused 'statement-sql 'not-a-statement 'x))
        (at-depth-1 (refused 'parameter-count 'not-a-statement 'x))
        (at-depth-1 (refused 'column-count 'not-a-statement 'x)))
  (with-memory-db
   (lambda (db)
     (let ((st (prepare-statement db "select 1")))
       (finalize-statement! st)
       (list (handler-depth (lambda () (statement-sql st)))
             (handler-depth (lambda () (parameter-count st)))
             (handler-depth (lambda () (column-count st)))
             (handler-depth (lambda () (statement-sql 'x)))
             (handler-depth (lambda () (parameter-count 'x)))
             (handler-depth (lambda () (column-count 'x))))))))

(test-equal "call-with-statement-handle raises its procedure's raise again after its section, at depth 1, the same object a guard then gets; and its refusal of a state, at depth 1"
  (list (at-depth-1 (refused 'test-proc 'planted)) 'the-same-object
        (at-depth-1 (refused 'test-statement 'not-allowed-in-state 'ready)))
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select 1"))
            (planted (condition (make-assertion-violation) (make-who-condition 'test-proc)
                                (make-message-condition "planted") (make-irritants-condition '(planted))))
            (a (handler-depth (lambda () (call-with-statement-handle 'test-statement st 'step! (lambda (c h sql) (raise planted))))))
            (b (guard (e (#t (if (eq? e planted) 'the-same-object (list 'another e))))
                 (call-with-statement-handle 'test-statement st 'step! (lambda (c h sql) (raise planted)))))
            (c (handler-depth (lambda () (call-with-statement-handle 'test-statement st 'column-value (lambda (c h sql) (values #f 'ran)))))))
       (finalize-statement! st)
       (list a b c)))))

(test-equal "call-with-statement raises its prepare's refusal, and its finalize's failure after a return, at depth 1"
  (list (at-depth-1 (refused 'call-with-statement 'no-statement '(kind string)))
        (at-depth-1 (sqlite-failure 'call-with-statement 'busy 'busy returning-sql #f 'busy)))
  (with-file-db
   (lambda (path db)
     (let ((reader #f))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (let ((a (handler-depth (lambda () (call-with-statement db ";" (lambda (st) 'ran))))))
             (set! reader (reader! path))
             (list a (handler-depth (lambda () (call-with-statement db returning-sql
                                                 (lambda (st) (step! st) 'returned)))))))
         (lambda () (release! reader)))))))

(test-equal "close-database! raises a finalize's failure after its section, at depth 1, with the connection closed"
  (list (at-depth-1 (sqlite-failure 'close-database! 'busy 'busy returning-sql #f 'busy))
        (list 'raised (closed 'test-statement)))
  (with-file-db
   (lambda (path db)
     (let ((reader #f))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (set! reader (reader! path))
           (let* ((st (prepare-statement db returning-sql))
                  (s (step! st))
                  (r (handler-depth (lambda () (close-database! db)))))
             (list r (attempt (lambda () (with-handle db (lambda (h) 'still-open)))))))
         (lambda () (release! reader)))))))

;; --- engines --------------------------------------------------------------------------------
;; An engine's expiry unwinds every dynamic-wind it is inside, and its resume
;; rewinds them. A verb's checks, its C call and its use of the handles share
;; one critical section, where an engine spends no ticks, so an expiry falls
;; only before the section or after it.

;; prepare-step-finalize-under-engine : Positive-Integer -> (U (List Any Natural) (List 'unfinished Natural))
(define (prepare-step-finalize-under-engine db fuel)
  (run-engine (lambda ()
                (guard (e (#t (list 'raised (what-raised e))))
                  (let* ((st (prepare-statement db "select 1"))
                         (a (step! st))
                         (b (step! st)))
                    (reset! st)
                    (finalize-statement! st)
                    (list a b))))
              fuel 100000))

(test-equal "prepare-statement, step!, reset! and finalize-statement! under an engine of every fuel from 1 to 60 ticks a slice: each completes, #t then #f, the engine of 1 tick expired, and nothing is left counted but the connection"
  (list (map (lambda (fuel) (list fuel '(#t #f))) (fuels 60)) 'expired one-connection)
  (with-memory-db
   (lambda (db)
     (let loop ((rest (fuels 60)) (found '()))
       (if (null? rest)
           (let ((at-one (prepare-step-finalize-under-engine db 1)))
             (list (reverse found)
                   (if (and (pair? (cdr at-one)) (integer? (cadr at-one)) (> (cadr at-one) 0))
                       'expired
                       (list 'at-fuel-1 at-one))
                   (native-counts)))
           (let ((run (prepare-step-finalize-under-engine db (car rest))))
             (loop (cdr rest)
                   (cons (if (eq? (car run) 'unfinished)
                             (list (car rest) run)
                             (list (car rest) (car run)))
                         found))))))))

;; Two engines on one thread share a statement. A runs a verb for FUEL ticks;
;; B then finalizes the statement, or closes its connection; A finishes. A's
;; checks and its use of the handle share a section where it cannot expire,
;; so B can come only before the checks, and A then raises &sqlite-closed, or
;; after the call, and A answers: never between, where A would hand C a
;; handle B freed.

;; interleaved : Positive-Integer Symbol Symbol -> Any
;; ok when A's answer is the verb's own, or &sqlite-closed from its who; else
;; what went wrong. A runs call-with-statement-handle, whose procedure tells
;; whether B had finished first (ACCESSOR), or step! itself (STEP).
(define (interleaved fuel a-kind b-kind)
  (let ((db (open-database ":memory:")))
    (dynamic-wind
      (lambda () #f)
      (lambda () (interleaved-on db fuel a-kind b-kind))
      (lambda () (undo! '() (list db))))))

(define (interleaved-on db fuel a-kind b-kind)
  (let* ((st (prepare-statement db "select 1"))
         (b-done #f)
         (a (make-engine
             (lambda ()
               (guard (c (#t (what-raised c)))
                 (if (eq? a-kind 'accessor)
                     (call-with-statement-handle 'test-statement st 'step!
                       (lambda (connection handle sql) (values #f (if b-done 'ran-after-b 'ran))))
                     (step! st))))))
         (b (make-engine (lambda ()
                           (if (eq? b-kind 'finalize) (finalize-statement! st) (close-database! db))
                           (set! b-done #t))))
         (answer 'a-not-finished))
    (let ((a2 (a fuel (lambda (left . v) (set! answer (car v)) #f) (lambda (next) next))))
      (b 1000000 (lambda (left . v) #f) (lambda (next) (set! b-done 'b-expired) #f))
      (let loop ((e a2) (n 0))
        (when (and e (< n 100000))
          (loop (e 1000000 (lambda (left . v) (set! answer (car v)) #f) (lambda (next) next))
                (+ n 1)))))
    (guard (e (#t #f)) (close-database! db))
    (cond ((and (eq? b-done #t) (memq answer '(ran #t))) 'ok)
          ((and (eq? b-done #t) (equal? answer (closed (if (eq? a-kind 'accessor) 'test-statement 'step!))))
           'ok)
          (else (list 'wrong answer b-done)))))

(test-equal "two engines on one thread, at every fuel from 1 to 60 ticks of the first slice: one runs call-with-statement-handle, or step!, while the other finalizes the statement, or closes its connection; each answer is the verb's own or &sqlite-closed, never a procedure run on a statement already finalized; every count is zero after"
  (list (map (lambda (fuel) (list fuel '(ok ok ok ok))) (fuels 60)) zero-counts)
  (list (map (lambda (fuel)
               (list fuel (map (lambda (kinds) (attempt (lambda () (interleaved fuel (car kinds) (cdr kinds)))))
                               '((accessor . finalize) (accessor . close) (step . finalize) (step . close)))))
             (fuels 60))
        (native-counts)))

;; call-with-statement-under-engine : Database Positive-Integer -> Any
;; call-with-statement in an engine of FUEL ticks a slice, its procedure
;; stepping, spinning 500 calls, long enough to expire at any fuel here, then
;; stepping again: the two steps' answers, or what each raised, and how many
;; times the engine expired.
(define (call-with-statement-under-engine db fuel)
  (run-engine (lambda ()
                (guard (e (#t (list 'raised (what-raised e))))
                  (call-with-statement db "select 1 union all select 2"
                    (lambda (st)
                      (let* ((a (attempt (lambda () (step! st))))
                             (spun (let spin ((i 0)) (if (< i 500) (spin (+ i 1)) i)))
                             (b (attempt (lambda () (step! st)))))
                        (list a b))))))
              fuel 1000000))

;; Measured here, the answer the consequences of ADR-0014 expected: an
;; expiry inside the procedure runs call-with-statement's after thunk, which
;; finalizes the statement, and the resumed procedure finds it finalized. The
;; first step may come before an expiry or after one, by the fuel.
(test-equal "call-with-statement does not survive an engine's preemption: at every fuel from 1 to 60 ticks a slice, an expiry inside the procedure finalizes the statement, and its step! after the expiry raises &sqlite-closed; nothing is left counted but the connection"
  (list (map (lambda (fuel) (list fuel 'stepped-or-closed (list 'raised (closed 'step!)))) (fuels 60))
        one-connection)
  (with-memory-db
   (lambda (db)
     (list (map (lambda (fuel)
                  (let ((run (call-with-statement-under-engine db fuel)))
                    (if (and (list? run) (= (length run) 2) (integer? (cadr run)) (> (cadr run) 0)
                             (list? (car run)) (= (length (car run)) 2))
                        (let ((a (car (car run))) (b (cadr (car run))))
                          (list fuel
                                (if (member a (list #t (list 'raised (closed 'step!)))) 'stepped-or-closed a)
                                b))
                        (list fuel 'no-expiry-or-raised run))))
                (fuels 60))
           (native-counts)))))

;; abandoned-at-first-expiry : Database Positive-Integer -> Any
;; call-with-statement in an engine of FUEL ticks, abandoned at its first
;; expiry, never resumed: whether it expired, and what DB tracks after.
(define (abandoned-at-first-expiry db fuel)
  (let* ((e (make-engine (lambda () (call-with-statement db "select 1" (lambda (st) (step! st) 'done)))))
         (r (e fuel (lambda (left . v) 'completed) (lambda (next) 'expired))))
    (list r (length (tracked-statements db)))))

(test-equal "call-with-statement abandoned at its first expiry, at every fuel from 1 to 400 ticks, leaves no statement prepared: the expiry's after thunk finalizes whatever the prepare made, since the prepare hands its statement over inside its own section"
  (list (map (lambda (fuel) (list fuel 0)) (fuels 400)) one-connection)
  (with-memory-db
   (lambda (db)
     (list (map (lambda (fuel) (list fuel (cadr (abandoned-at-first-expiry db fuel)))) (fuels 400))
           (native-counts)))))

;; --- what docs/reference.md says, each held by a row ------------------------------------

;; Measured on 3.53.1 and 3.45.1 alike (build/m2s3-verify/m3-items.sps and
;; build/m2s3-fix/probe-docs.sps): a held select * reads its column count
;; again at each call, and SQLite re-prepares it at its next step.
(test-equal "column-count changes at the statement's next step after an alter table, on its own connection or another: a held select * reads 2, 2, then #t and 3, the alter made on its own connection; 1, 1, then #t and 2 when another connection made it"
  (list (list 2 2 #t 3) (list 1 1 #t 2))
  (list
   (with-memory-db
    (lambda (db)
      (exec! db "create table t (x, y)")
      (exec! db "insert into t values (1, 2)")
      (let* ((st (prepare-statement db "select * from t"))
             (before (column-count st))
             (altered (exec! db "alter table t add column z"))
             (after-alter (column-count st))
             (stepped (step! st))
             (after-step (column-count st)))
        (finalize-statement! st)
        (list before after-alter stepped after-step))))
   (with-file-db
    (lambda (path db)
      (let ((other (open-database path)))
        (dynamic-wind
          (lambda () #f)
          (lambda ()
            (let* ((st (prepare-statement db "select * from t"))
                   (before (column-count st))
                   (altered (exec! other "alter table t add column y"))
                   (after-alter (column-count st))
                   (stepped (step! st))
                   (after-step (column-count st)))
              (finalize-statement! st)
              (list before after-alter stepped after-step)))
          (lambda () (undo! '() (list other)))))))))

;; Measured on both libraries (build/m2s3-verify/m3-items.sps): begin, an
;; insert ... returning stepped once, then commit answers busy, "cannot commit
;; transaction - SQL statements in progress": no wait fixes it, and a reset
;; of the insert lets the commit through.
(test-equal "a commit refused while the connection's own statement is mid-row raises &sqlite-busy from step!, the statement failed; after a reset! of the insert, the same commit, reset, steps to done, and the table holds the insert's two rows"
  (list #t (list 'raised (sqlite-failure 'step! 'busy 'busy "commit" #f 'busy))
        'failed #f 'done 2)
  (with-memory-db
   (lambda (db)
     (exec! db "create table t (x)")
     (exec! db "begin")
     (let* ((ins (prepare-statement db "insert into t values (1), (2) returning x"))
            (row (step! ins))
            (commit (prepare-statement db "commit"))
            (refused (attempt (lambda () (step! commit))))
            (state (statement-state commit))
            (rewound (begin (reset! ins) (finalize-statement! ins) (reset! commit)))
            (again (step! commit))
            (after (statement-state commit)))
       (finalize-statement! commit)
       (list row refused state again after (query-int db "select count(*) from t"))))))

;; reset! rewinds the statement and keeps its bindings (docs/reference.md): a
;; value bound by sqlite3_bind_int64 through the accessor, which slice 4's
;; bind! will be, reads back after a reset and a second step.
(test-equal "reset! keeps the bindings: select ?1 bound to 7 reads 7, is reset, and reads 7 again"
  '(7 7)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select ?1"))
            (bound (call-with-statement-handle 'test-statement st 'bind!
                     (lambda (c h sql) (values #f (sqlite3-bind-int64 h 1 7)))))
            (stepped (step! st))
            (first (column-int st 0))
            (rewound (reset! st))
            (stepped-again (step! st))
            (second (column-int st 0)))
       (finalize-statement! st)
       (list first second)))))

;; call-with-statement's prepare carries an offset too, a character index
;; (docs/reference.md): "select 1, nosuchcol" fails at 10.
(test-equal "call-with-statement's failed prepare carries the SQL and the offset, as prepare-statement's does: 10 for select 1, nosuchcol"
  (list (list 'raised (sqlite-failure 'call-with-statement 'error 'error "select 1, nosuchcol" 10 'no-subtype))
        (list 'raised (sqlite-failure 'prepare-statement 'error 'error "select 1, nosuchcol" 10 'no-subtype)))
  (with-memory-db
   (lambda (db)
     (list (attempt (lambda () (call-with-statement db "select 1, nosuchcol" (lambda (st) 'ran))))
           (attempt (lambda () (prepare-statement db "select 1, nosuchcol")))))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "statement")

(exit (suite-exit-status runner))
