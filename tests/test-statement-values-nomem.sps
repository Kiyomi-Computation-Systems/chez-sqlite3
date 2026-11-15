#!r6rs
;;; Running out of memory while reading a column, for real (ADR-0015,
;;; decisions 7 and 9; ADR-0014's slice 3 amendment, the maintainer's
;;; choice). In a process of its own: the heap limit is process-wide.
;;;
;;; The suite binds sqlite3_hard_heap_limit64 itself, and sets it to
;;; sqlite3_memory_used plus 1,000 bytes around the one read, setting it back
;;; to 0 however the read ends. A 100,000-byte TEXT, bigger than SQLite's
;;; lookaside, bound with its length and read back through select ?1, makes
;;; sqlite3_column_text allocate a NUL-terminated copy, and that allocation
;;; answers NOMEM (the research's heap-limit.c, on both libraries).
;;;
;;;   the read       column-value and column-bytevector raise &sqlite-error
;;;                  nomem once, with the SQL and no offset; the statement is
;;;                  failed; reads and step! are refused until reset!, which
;;;                  raises nothing; it then steps and reads again
;;;   a transaction  a statement that reads a table rolls it back at the next
;;;                  reset or finalize; one that reads none keeps it (measured
;;;                  on both libraries, build/m2s4/probes/nomem-bound.sps)
;;;   column-name    sqlite3_column_name16, bound here, converts a name in
;;;                  place, so sqlite3_column_name must convert it back, and
;;;                  under the limit answers NULL, setting no code: column-name
;;;                  raises nomem with sqlite3_errstr's message, and the state
;;;                  stays (measured on both, build/m2s4/probes/name-nomem.sps)
;;;   after the section
;;;                  each raise at depth 1
;;;
;;; Where SQLite keeps no memory count, as on a build with
;;; SQLITE_DEFAULT_MEMSTATUS=0 like Apple's, the limit is kept but not
;;; enforced (the research), so each row here is named unavailable and
;;; skipped, as the memory check is: never a pass.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. Effects run in order, through let* and named lets (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure disable-interrupts enable-interrupts)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) sqlite-error? sqlite-error-code sqlite-error-extended-code
              sqlite-error-message sqlite-error-sql sqlite-error-offset sqlite-closed?))

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

(define (reach library name)
  (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
    (eval name (environment library))))

(define values-library '(chez-sqlite3 private statement-values))
(define statement-library '(chez-sqlite3 private statement))
(define native-library '(chez-sqlite3 private native))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define step! (reach statement-library 'step!))
(define reset! (reach statement-library 'reset!))
(define statement-state (reach statement-library 'statement-state))
(define call-with-statement-handle (reach statement-library 'call-with-statement-handle))
(define bind! (reach values-library 'bind!))
(define column-value (reach values-library 'column-value))
(define column-bytevector (reach values-library 'column-bytevector))
(define column-name (reach values-library 'column-name))
(define sqlite3-memory-used (reach native-library 'sqlite3-memory-used))
(define sqlite3-errmsg (reach native-library 'sqlite3-errmsg))
(define sqlite3-errstr (reach native-library 'sqlite3-errstr))
(define c-string->string (reach native-library 'c-string->string))

;; --- bindings made here, after the load ------------------------------------------------

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; sqlite3_int64 sqlite3_hard_heap_limit64(sqlite3_int64 N): the limit
;; before; a negative N reads it, and 0 means no limit.
(define heap-limit (bound 'sqlite3_hard_heap_limit64
                          (foreign-procedure "sqlite3_hard_heap_limit64" (integer-64) integer-64)))
;; int sqlite3_get_autocommit(sqlite3*): 0 inside a transaction.
(define get-autocommit (bound 'sqlite3_get_autocommit (foreign-procedure "sqlite3_get_autocommit" (uptr) int)))
;; const void *sqlite3_column_name16(sqlite3_stmt*, int N): converts the
;; name in place; never called by chez-sqlite3.
(define column-name16 (bound 'sqlite3_column_name16 (foreign-procedure "sqlite3_column_name16" (uptr int) uptr)))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))
(define (with-statements n) (list '(block . 0) '(connection . 1) (cons 'statement n)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (sqlite-error-sql e) (sqlite-error-offset e)
               (if (and (message-condition? e) (string? (sqlite-error-message e))
                        (equal? (condition-message e) (sqlite-error-message e)))
                   'message-is-the-field
                   'message-differs)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

(define (sqlite-failure who code extended sql)
  (list 'sqlite-error who code extended sql #f 'message-is-the-field))
(define (not-allowed who state) (list 'assertion-violation who (list 'not-allowed-in-state state)))

(define raised-tag (list 'raised))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define void-value (if #f #f))
(define (no-value x) (if (eq? x void-value) 'no-value x))

(define (interrupt-depth)
  (let ((n (disable-interrupts)))
    (enable-interrupts)
    n))

;; handler-depth : (-> Any) -> Any
;; The depth a with-exception-handler handler runs at for THUNK's raise, and
;; what it raised; the handler escapes. (no-raise VALUE) when nothing raises.
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
      (lambda () (list 'no-raise (no-value (thunk))))))))

(define (at-depth-1 what) (list 'raised-at-depth 'depth-1 what))

(define (undo! statements databases)
  (for-each (lambda (s) (guard (e (#t #f)) (finalize-statement! s))) statements)
  (for-each (lambda (db) (guard (e (#t #f)) (close-database! db))) databases))

;; with-db : String (Database -> Any) -> Any
;; PROC's answer, or what it raised, given a connection to PATH, closed after.
(define (with-db path proc)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda () (attempt (lambda () (set! db (open-database path)) (proc db))))
      (lambda () (when db (undo! '() (list db)))))))

(define (with-memory-db proc) (with-db ":memory:" proc))

(define (with-handle db proc) (call-with-open-handle 'test-statement-values-nomem db proc))

;; exec! : Database String -> Any
(define (exec! db sql)
  (let* ((st (prepare-statement db sql))
         (answer (guard (e (#t (finalize-statement! st) (raise e))) (step! st))))
    (finalize-statement! st)
    answer))

;; under-limit : (-> Any) -> Any
;; THUNK's answer, run with the hard heap limit at the memory SQLite uses
;; now plus 1,000 bytes, and set back to 0 however THUNK ends.
(define (under-limit thunk)
  (dynamic-wind
    (lambda () (heap-limit (+ (sqlite3-memory-used) 1000)))
    thunk
    (lambda () (heap-limit 0))))

;; read-under-limit : Database (-> Any) -> (List Any Symbol)
;; What THUNK, a read, raised under the limit, and whether an &sqlite-error's
;; message is sqlite3_errmsg's, read straight after with nothing between.
(define (read-under-limit db thunk)
  (let* ((r (guard (e (#t (cons raised-tag e))) (under-limit thunk) 'no-raise))
         (now (with-handle db (lambda (h) (c-string->string (sqlite3-errmsg h))))))
    (if (and (pair? r) (eq? (car r) raised-tag))
        (list (what-raised (cdr r))
              (if (and (sqlite-error? (cdr r)) (equal? (sqlite-error-message (cdr r)) now))
                  'the-message-after-the-read
                  'another-message))
        (list 'no-raise r))))

(define big-text (make-string 100000 #\a))

;; --- whether the limit is enforced here -------------------------------------------------------

;; memory-kept : Any
;; #t when SQLite's memory count rises while a connection is open, as the
;; memory check's control asks; else the limit is not enforced here.
(define memory-kept
  (with-memory-db (lambda (db) (> (sqlite3-memory-used) 0))))

;; available! : String -> Void
;; Where the count is not kept, says so by NAME and skips the test of that
;; name that follows: a skip is its own result, never a pass.
(define (available! name)
  (unless (eq? memory-kept #t)
    (display "UNAVAILABLE ")
    (display name)
    (display ": this libsqlite3 keeps no memory count, so a hard heap limit is not enforced")
    (newline)
    (test-skip name)))

(test-begin "statement-values-nomem")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(define read-name "a 100,000-byte TEXT read back through select ?1 under a heap limit of the memory used plus 1,000: column-value raises &sqlite-error nomem, nomem, with the SQL, no offset, and sqlite3_errmsg's message straight after; the statement is failed; the limit reads 0 after")
(available! read-name)
(test-equal read-name
  (list (list (sqlite-failure 'column-value 'nomem 'nomem "select ?1") 'the-message-after-the-read)
        'failed 0 (with-statements 1))
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select ?1"))
            (b (bind! st 1 big-text))
            (s (step! st))
            (r (read-under-limit db (lambda () (column-value st 0))))
            (state (statement-state st))
            (now (heap-limit -1))
            (counts (native-counts)))
       (finalize-statement! st)
       (list r state now counts)))))

(define after-name "after the NOMEM read, column-value, column-bytevector and step! are refused, naming failed; reset! raises nothing and leaves it ready; it steps and reads its 100,000 bytes again, its binding kept")
(available! after-name)
(test-equal after-name
  (list (list 'raised (not-allowed 'column-value 'failed))
        (list 'raised (not-allowed 'column-bytevector 'failed))
        (list 'raised (not-allowed 'step! 'failed))
        'no-value 'ready #t 'the-same-text 'row)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select ?1"))
            (b (bind! st 1 big-text))
            (s (step! st))
            (r (read-under-limit db (lambda () (column-value st 0))))
            (a (attempt (lambda () (column-value st 0))))
            (c (attempt (lambda () (column-bytevector st 0))))
            (d (attempt (lambda () (step! st))))
            (reset (no-value (attempt (lambda () (reset! st)))))
            (ready (statement-state st))
            (again (attempt (lambda () (step! st))))
            (v (attempt (lambda () (column-value st 0))))
            (row (statement-state st)))
       (finalize-statement! st)
       (list a c d reset ready again (if (equal? v big-text) 'the-same-text v) row)))))

(define finalize-name "after the NOMEM read, finalize-statement! raises nothing, and the statement is finalized and counted down")
(available! finalize-name)
(test-equal finalize-name
  (list (list (sqlite-failure 'column-value 'nomem 'nomem "select ?1") 'the-message-after-the-read)
        'no-value 'finalized (list '(block . 0) '(connection . 1) '(statement . 0)))
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select ?1"))
            (b (bind! st 1 big-text))
            (s (step! st))
            (r (read-under-limit db (lambda () (column-value st 0))))
            (f (no-value (attempt (lambda () (finalize-statement! st)))))
            (state (statement-state st))
            (counts (native-counts)))
       (list r f state counts)))))

(define bytevector-name "column-bytevector reads TEXT through sqlite3_column_text, so the same read under the limit raises &sqlite-error nomem from column-bytevector, and the statement is failed")
(available! bytevector-name)
(test-equal bytevector-name
  (list (list (sqlite-failure 'column-bytevector 'nomem 'nomem "select ?1") 'the-message-after-the-read)
        'failed)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select ?1"))
            (b (bind! st 1 big-text))
            (s (step! st))
            (r (read-under-limit db (lambda () (column-bytevector st 0))))
            (state (statement-state st)))
       (finalize-statement! st)
       (list r state)))))

;; in-transaction : String (Database Statement -> Any) -> Any
;; In a fresh database file: src holding a row, u, a transaction begun with
;; a marker inserted into u; SQL prepared, bound to the 100,000 bytes,
;; stepped, read under the limit; then FINISH given the database and the
;; statement. What the read raised, FINISH's answer, autocommit, and the
;; marker rows.
(define (in-transaction sql finish)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (with-db (string-append dir "/t.db")
         (lambda (db)
           (let* ((a (exec! db "create table src (x)"))
                  (b (exec! db "create table u (x)"))
                  (c (exec! db "insert into src values (1)"))
                  (d (exec! db "begin"))
                  (e (exec! db "insert into u values ('marker')"))
                  (st (prepare-statement db sql))
                  (bd (bind! st 1 big-text))
                  (s (step! st))
                  (r (car (read-under-limit db (lambda () (column-value st 0)))))
                  (f (no-value (attempt (lambda () (finish st)))))
                  (autocommit (with-handle db get-autocommit))
                  (marker (let* ((q (prepare-statement db "select count(*) from u"))
                                 (qs (step! q))
                                 (n (column-value q 0)))
                            (finalize-statement! q)
                            n)))
             (finalize-statement! st)
             (when (eqv? autocommit 0) (exec! db "rollback"))
             (list r f autocommit marker))))))))

(define transaction-name "inside a transaction, after the NOMEM read of a statement that reads a table, reset! and finalize-statement! raise nothing, and the transaction has been rolled back: autocommit 1, the marker row gone; a statement that reads no table keeps it: autocommit 0, the marker there")
(available! transaction-name)
(test-equal transaction-name
  (list (list (sqlite-failure 'column-value 'nomem 'nomem "select ?1 from src") 'no-value 1 0)
        (list (sqlite-failure 'column-value 'nomem 'nomem "select ?1 from src") 'no-value 1 0)
        (list (sqlite-failure 'column-value 'nomem 'nomem "select ?1") 'no-value 0 1))
  (let* ((a (in-transaction "select ?1 from src" (lambda (st) (reset! st))))
         (b (in-transaction "select ?1 from src" (lambda (st) (finalize-statement! st))))
         (c (in-transaction "select ?1" (lambda (st) (reset! st)))))
    (list a b c)))

;; long-name : String
;; A 5,000-character alias, so no lookaside slot serves its conversion.
(define long-name (make-string 5000 #\n))

;; name-under-limit : Boolean -> Any
;; select 1 AS long-name, stepped when STEPPED; its name converted in place
;; by sqlite3_column_name16, through the accessor, then column-name read
;; under the limit: what it raised, and whether its message is
;; sqlite3_errstr's for NOMEM; the state; the name read again without the
;; limit, by its length; and step!'s answer.
(define (name-under-limit stepped)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db (string-append "select 1 as " long-name)))
            (s (if stepped (step! st) 'unstepped))
            (n16 (call-with-statement-handle 'test-statement-values-nomem st 'column-name
                   (lambda (connection handle sql)
                     (values #f (if (eqv? (column-name16 handle 0) 0) 'null 'converted)))))
            (r (guard (e (#t (cons raised-tag e)))
                 (under-limit (lambda () (column-name st 0)))
                 'no-raise))
            (errstr (c-string->string (sqlite3-errstr 7)))
            (what (if (and (pair? r) (eq? (car r) raised-tag))
                      (list (what-raised (cdr r))
                            (if (and (sqlite-error? (cdr r)) (equal? (sqlite-error-message (cdr r)) errstr))
                                'errstr-of-nomem
                                'another-message))
                      (list 'no-raise r)))
            (state (statement-state st))
            (again (attempt (lambda () (string-length (column-name st 0)))))
            (step (attempt (lambda () (step! st)))))
       (finalize-statement! st)
       (list n16 what state again step)))))

(define name-name "column-name, its name converted in place by sqlite3_column_name16, under the limit: sqlite3_column_name answers NULL and sets no code, so column-name raises &sqlite-error nomem, nomem, with sqlite3_errstr's message, the SQL and no offset; the state stays ready, or row, and the name then reads whole")
(available! name-name)
(test-equal name-name
  (let ((sql (string-append "select 1 as " long-name)))
    (list (list 'converted (list (sqlite-failure 'column-name 'nomem 'nomem sql) 'errstr-of-nomem)
                'ready 5000 #t)
          (list 'converted (list (sqlite-failure 'column-name 'nomem 'nomem sql) 'errstr-of-nomem)
                'row 5000 #f)))
  (let* ((a (name-under-limit #f))
         (b (name-under-limit #t)))
    (list a b)))

(define depth-name "each NOMEM is raised after its section: column-value's, column-bytevector's and column-name's reach a handler at depth 1")
(available! depth-name)
(test-equal depth-name
  (list (at-depth-1 (sqlite-failure 'column-value 'nomem 'nomem "select ?1"))
        (at-depth-1 (sqlite-failure 'column-bytevector 'nomem 'nomem "select ?1"))
        (at-depth-1 (sqlite-failure 'column-name 'nomem 'nomem (string-append "select 1 as " long-name))))
  (with-memory-db
   (lambda (db)
     (let* ((one (lambda (read)
                   (let* ((st (prepare-statement db "select ?1"))
                          (b (bind! st 1 big-text))
                          (s (step! st))
                          (r (under-limit (lambda () (handler-depth (lambda () (read st 0)))))))
                     (finalize-statement! st)
                     r)))
            (a (one column-value))
            (b (one column-bytevector))
            (named (prepare-statement db (string-append "select 1 as " long-name)))
            (n16 (call-with-statement-handle 'test-statement-values-nomem named 'column-name
                   (lambda (connection handle sql) (values #f (column-name16 handle 0)))))
            (c (under-limit (lambda () (handler-depth (lambda () (column-name named 0)))))))
       (finalize-statement! named)
       (list a b c)))))

(test-equal "the heap limit is back at 0, and every count is zero at the end"
  (list 0 zero-counts)
  (list (guard (e (#t (list 'raised (describe e)))) (heap-limit -1)) (native-counts)))

(test-end "statement-values-nomem")

(exit (suite-exit-status runner))
