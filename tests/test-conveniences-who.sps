#!r6rs
;;; The suite for the conveniences' raises (ADR-0013, decision 2; ADR-0016,
;;; decision 9; the M3 plan, section 5, slice 3): at every raise site of each
;;; of (chez-sqlite3 private conveniences)'s five verbs, the raise names the
;;; convenience the caller called, never one of M2's verbs or part A's
;;; internals, and reaches a with-exception-handler handler at depth 1, after
;;; every critical section, against a no-raise sentinel.
;;;
;;;   the sites     for execute!, query, query-row and query-fold: the
;;;                 check-out's refusals, no database, the wrong thread, no
;;;                 string, U+0000, and a closed connection; the prepare's
;;;                 failure, no statement and more than one; a bind's count,
;;;                 value and SQLite's toobig; a step's failure; a row read's
;;;                 invalid text, but execute!'s, which reads no row; the
;;;                 reset on return to the cache, query-row's alone, since the
;;;                 others step to done; and the finalize of the statement a
;;;                 return evicts. For query-fold too: a procedure that is no
;;;                 procedure; the finalize when the procedure escapes; and
;;;                 &sqlite-closed when the fold is re-entered after it
;;;                 returned. For execute!, query and query-row:
;;;                 &sqlite-closed when an engine's remainder, taken while
;;;                 the call held its statement, is resumed a second time,
;;;                 from a flag's section, the return's among them. For
;;;                 execute-script!: its checks, SQLite's failures at a
;;;                 prepare and at a step, each rebuilt, and &sqlite-closed
;;;                 when a remainder taken before its block is resumed a
;;;                 second time
;;;   the eviction  an evicted statement is reset, so its finalize has
;;;                 nothing to commit and cannot fail. The suite moves one
;;;                 the cache holds, an insert ... returning, to its first row
;;;                 through tracked-statements, as tests/test-connection-cache.sps
;;;                 moves one, so the eviction's finalize commits, and answers
;;;                 busy under another connection's read
;;;
;;; The loading procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them. SQLite's answers here were measured
;;; on 3.53.1 and 3.45.1 alike (.plans/research/m3-slice-3/, conveniences-answers.sps
;;; and busy-reset.sps; .plans/research/m2-slice-3/probe-block.sps) before a row
;;; asserts them.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure fork-thread make-mutex with-mutex sleep make-time
              get-thread-id disable-interrupts enable-interrupts make-engine)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3 private conditions) sqlite-invalid-text? sqlite-invalid-text-column
              sqlite-invalid-text-offset)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-error-message sqlite-error-sql sqlite-error-offset
              sqlite-wrong-thread? sqlite-wrong-thread-owner sqlite-wrong-thread-caller
              sqlite-closed?))

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
(define statement-library '(chez-sqlite3 private statement))
(define execute! (reach conveniences 'execute!))
(define query (reach conveniences 'query))
(define query-row (reach conveniences 'query-row))
(define query-fold (reach conveniences 'query-fold))
(define execute-script! (reach conveniences 'execute-script!))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define call-with-open-handle (reach connection-library 'call-with-open-handle))
(define tracked-statements (reach connection-library 'tracked-statements))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define step! (reach statement-library 'step!))
(define column-value (reach '(chez-sqlite3 private statement-values) 'column-value))
(define statement-sql (reach statement-library 'statement-sql))
(define statement-state (reach statement-library 'statement-state))
(define database-cache-count (reach connection-library 'database-cache-count))

;; --- bindings made here, after the load ------------------------------------------------

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_limit(sqlite3*, int id, int newVal): the old value.
(define limit (bound 'sqlite3_limit (foreign-procedure "sqlite3_limit" (uptr int int) int)))

;; SQLITE_LIMIT_LENGTH, sqlite3.h's limit id 0.
(define limit-length 0)

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))
(define (message-of e) (if (message-condition? e) 'message 'no-message))

;; what-raised : Any -> Any
;; As tests/test-statement-who.sps compares a raise.
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

(define (sqlite-failure who code extended sql offset)
  (list 'sqlite-error who code extended sql offset 'message-is-the-field))
(define (closed who) (list 'closed who 'message))
(define (refused who . irritants) (list 'assertion-violation who irritants))
(define (invalid who column offset) (list 'invalid-text who column offset 'message))
(define (wrong-thread who) (list 'wrong-thread who 'message 'main 'the-thread))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define void-value (if #f #f))
(define (no-value x) (if (eq? x void-value) 'no-value x))

;; interrupt-depth : -> Positive-Integer
(define (interrupt-depth)
  (let ((n (disable-interrupts)))
    (enable-interrupts)
    n))

;; handler-depth : (-> Any) -> (U (List 'raised-at-depth Symbol Any) (List 'no-raise Any))
;; The depth a with-exception-handler handler runs at for the first thing
;; THUNK raises, and what it raised; the handler escapes. (no-raise VALUE)
;; when THUNK raises nothing.
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

;; undo! : (Listof Any) (Listof Any) -> Void
(define (undo! statements databases)
  (for-each (lambda (s) (guard (e (#t #f)) (finalize-statement! s))) statements)
  (for-each (lambda (db) (guard (e (#t #f)) (close-database! db))) databases))

;; with-db : (-> Database) (Database -> Any) -> Any
(define (with-db open proc)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda () (attempt (lambda () (set! db (open)) (proc db))))
      (lambda () (when db (undo! '() (list db)))))))

;; in-dir : (String -> Any) -> Any
(define (in-dir proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory proc)))

;; with-handle : Any (Positive-Integer -> A) -> A
(define (with-handle db proc) (call-with-open-handle 'test-conveniences-who db proc))

;; tier-run : Database String -> (Listof (Vectorof Any))
(define (tier-run db sql)
  (let ((st (prepare-statement db sql)))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let loop ((rows '()))
          (if (step! st)
              (loop (cons (vector (column-value st 0)) rows))
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

;; with-file-db : Natural (String Database -> Any) -> Any
;; PROC's answer, or what it raised, given a temporary directory's database
;; file made by make-table!, and a connection to it whose cache holds
;; CAPACITY, closed after.
(define (with-file-db capacity proc)
  (in-dir (lambda (dir)
            (let ((path (string-append dir "/t.db")) (db #f))
              (dynamic-wind
                (lambda () #f)
                (lambda ()
                  (attempt (lambda ()
                             (make-table! path)
                             (set! db (open-database path (list (cons 'statement-cache capacity))))
                             (proc path db))))
                (lambda () (when db (undo! '() (list db)))))))))

;; under-reader : String (-> Any) -> Any
;; THUNK's answer while a second connection to PATH holds a read.
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

;; wait-until : (-> Any) Natural -> (U 'satisfied 'iterations-exhausted)
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

(define (text-of n) (make-string n #\a))

;; run : Symbol Any Any Any ... -> Any
;; The convenience NAME on DB and SQL with GIVEN, query-fold's procedure
;; answering its accumulator, from 0.
(define (run name db sql . given)
  (case name
    ((execute!) (apply execute! db sql given))
    ((query) (apply query db sql given))
    ((query-row) (apply query-row db sql given))
    (else (apply query-fold db sql (lambda (acc row) acc) 0 given))))

(define returning-sql "insert into t values (1), (2) returning x")
(define evicted-sql "insert into u values (1), (2) returning x")
(define overflow-sql "select abs(-9223372036854775807 - 1)")

;; common-sites : Symbol -> (Listof Any)
;; handler-depth of NAME at each raise site the four share, in order: no
;; database, the wrong thread, no string, U+0000, a failed prepare, no
;; statement, more than one, a bind's count, value and toobig, a step, and
;; a call that raises nothing; then, closed, a closed connection.
(define (common-sites name)
  (let* ((db (guard (e (#t #f)) (open-database ":memory:")))
         (a (handler-depth (lambda () (run name 'x "select 1"))))
         (b (from-another-thread (lambda () (handler-depth (lambda () (run name db "select 1"))))))
         (c (handler-depth (lambda () (run name db 42))))
         (d (handler-depth (lambda () (run name db "select\x0;1"))))
         (e (handler-depth (lambda () (run name db "select 1, nosuchcol"))))
         (f (handler-depth (lambda () (run name db ";"))))
         (g (handler-depth (lambda () (run name db "select 1; select 2"))))
         (h (handler-depth (lambda () (run name db "select ?1, ?2" 1))))
         (i (handler-depth (lambda () (run name db "select ?1, ?2" 1 #t))))
         (old (with-handle db (lambda (handle) (limit handle limit-length 30))))
         (j (handler-depth (lambda () (run name db "select ?1, ?2" 1 (text-of 31)))))
         (restored (with-handle db (lambda (handle) (limit handle limit-length old))))
         (k (handler-depth (lambda () (run name db overflow-sql))))
         (l (handler-depth (lambda () (run name db "select 1"))))
         (m (begin (guard (e (#t #f)) (close-database! db))
                   (handler-depth (lambda () (run name db "select 1"))))))
    (list a b c d e f g h i j k l m)))

;; expected-common : Symbol Any -> (Listof Any)
;; What common-sites answers for NAME, whose call that raises nothing
;; answers ANSWER.
(define (expected-common name answer)
  (list (at-depth-1 (refused name 'not-a-database 'x))
        (at-depth-1 (wrong-thread name))
        (at-depth-1 (refused name 'not-a-string 42))
        (at-depth-1 (refused name 'sql-holds-nul '(kind string)))
        (at-depth-1 (sqlite-failure name 'error 'error "select 1, nosuchcol" 10))
        (at-depth-1 (refused name 'no-statement '(kind string)))
        (at-depth-1 (refused name 'more-than-one-statement 10))
        (at-depth-1 (refused name 'value-count-mismatch 1 2))
        (at-depth-1 (refused name 'boolean 2 '(kind boolean)))
        (at-depth-1 (sqlite-failure name 'toobig 'toobig "select ?1, ?2" #f))
        (at-depth-1 (sqlite-failure name 'error 'error overflow-sql #f))
        (list 'no-raise answer)
        (at-depth-1 (closed name))))

;; read-site : Symbol -> Any
;; handler-depth of NAME reading a row whose TEXT is not well-formed.
(define (read-site name)
  (with-db (lambda () (open-database ":memory:"))
    (lambda (db) (handler-depth (lambda () (run name db "select cast(x'ff' as text)"))))))

;; evicting : Symbol -> Any
;; On a file database whose cache holds one statement: evicted-sql run once
;; by execute!, so it is cached, then stepped to its first row by the suite
;; through tracked-statements, so its finalize commits; then, under another
;; connection's read, NAME runs select 1, whose return into the full cache
;; evicts it, and the eviction's finalize answers busy. handler-depth's
;; answer, the evicted statement's state, and u's rows after, its first two
;; standing and the moved insert's rolled back.
(define (evicting name)
  (with-file-db 1
    (lambda (path db)
      (execute! db evicted-sql)
      (let* ((held (car (tracked-statements db)))
             (r (under-reader path
                  (lambda ()
                    (step! held)
                    (handler-depth (lambda () (run name db "select 1")))))))
        (list r (statement-state held) (tier-run db "select count(*) from u"))))))

(define (expected-eviction name)
  (list (at-depth-1 (sqlite-failure name 'busy 'busy evicted-sql #f)) 'finalized '(#(2))))

(test-begin "conveniences-who")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

;; --- the sites the four share --------------------------------------------------------------

(test-equal "execute! names itself at every raise site, each reaching a handler at depth 1: the check-out's refusals, the prepare's failure, no statement and more than one, a bind's count, value and toobig, a step's failure, a closed connection; a call that raises nothing answers no value"
  (expected-common 'execute! 'no-value)
  (common-sites 'execute!))

(test-equal "query names itself at every raise site, each at depth 1"
  (expected-common 'query '(#(1)))
  (common-sites 'query))

(test-equal "query-row names itself at every raise site, each at depth 1"
  (expected-common 'query-row '#(1))
  (common-sites 'query-row))

(test-equal "query-fold names itself at every raise site, each at depth 1"
  (expected-common 'query-fold 0)
  (common-sites 'query-fold))

(test-equal "a row read's invalid TEXT names query, query-row and query-fold, at depth 1, with its column and offset"
  (list (at-depth-1 (invalid 'query 0 0)) (at-depth-1 (invalid 'query-row 0 0))
        (at-depth-1 (invalid 'query-fold 0 0)))
  (list (read-site 'query) (read-site 'query-row) (read-site 'query-fold)))

;; Measured (.plans/research/m3-slice-3/busy-reset.sps;
;; .plans/research/m2-slice-3/probe-block.sps), on both libraries: the reset
;; of an insert ... returning stepped once, and its finalize, answer busy
;; under another's read.
(test-equal "query-row's reset on return names it, at depth 1: an insert ... returning under another's read answers busy at the reset that commits it"
  (at-depth-1 (sqlite-failure 'query-row 'busy 'busy returning-sql #f))
  (with-file-db 32
    (lambda (path db)
      (under-reader path (lambda () (handler-depth (lambda () (query-row db returning-sql))))))))

(test-equal "the finalize of a statement a return evicts names the convenience whose return evicted it, at depth 1, for execute!, query, query-row and query-fold, whose return is its normal exit's"
  (list (expected-eviction 'execute!) (expected-eviction 'query) (expected-eviction 'query-row)
        (expected-eviction 'query-fold))
  (let* ((a (evicting 'execute!))
         (b (evicting 'query))
         (c (evicting 'query-row))
         (d (evicting 'query-fold)))
    (list a b c d)))

;; --- query-fold's own sites ---------------------------------------------------------------

(test-equal "query-fold's own sites, each at depth 1: a procedure that is no procedure, before anything else; the finalize when the procedure escapes through a continuation, an insert ... returning at its row under another's read, answering busy, raised as the escape leaves; and &sqlite-closed when a continuation re-enters the fold after its normal return"
  (list (at-depth-1 (refused 'query-fold 'not-a-procedure 'x))
        (at-depth-1 (sqlite-failure 'query-fold 'busy 'busy returning-sql #f))
        (list (list 'no-raise 0) (at-depth-1 (closed 'query-fold))))
  (let* ((a (handler-depth (lambda () (query-fold 'not-a-database "select 1" 'x 0))))
         (b (with-file-db 32
              (lambda (path db)
                (under-reader path
                  (lambda ()
                    (handler-depth
                     (lambda ()
                       (call/cc (lambda (k) (query-fold db returning-sql (lambda (acc row) (k 'escaped)) 0))))))))))
         (c (with-db (lambda () (open-database ":memory:"))
              (lambda (db)
                (let ((k #f) (answers '()))
                  (let ((r (handler-depth
                            (lambda ()
                              (query-fold db "select 1"
                                          (lambda (acc row) (call/cc (lambda (c) (set! k c))) acc)
                                          0)))))
                    (set! answers (cons r answers))
                    (if (and k (= (length answers) 1))
                        (k #f)
                        (reverse answers))))))))
    (list a b c)))

;; --- execute-script! ---------------------------------------------------------------------------

(test-equal "execute-script! names itself at every raise site, each at depth 1: no database, the wrong thread, no string, U+0000, a closed connection, and SQLite's failures at a prepare and at a step, each rebuilt with the whole script and its offset; a script that raises nothing answers no value"
  (list (at-depth-1 (refused 'execute-script! 'not-a-database 'x))
        (at-depth-1 (wrong-thread 'execute-script!))
        (at-depth-1 (refused 'execute-script! 'not-a-string 42))
        (at-depth-1 (refused 'execute-script! 'sql-holds-nul '(kind string)))
        (at-depth-1 (sqlite-failure 'execute-script! 'error 'error "select 1; selekt 2" 10))
        (at-depth-1 (sqlite-failure 'execute-script! 'error 'error (string-append "select 1; " overflow-sql) 10))
        (list 'no-raise 'no-value)
        (at-depth-1 (closed 'execute-script!))
        zero-counts)
  (let* ((db (guard (e (#t #f)) (open-database ":memory:")))
         (a (handler-depth (lambda () (execute-script! 'x "select 1"))))
         (b (from-another-thread (lambda () (handler-depth (lambda () (execute-script! db "select 1"))))))
         (c (handler-depth (lambda () (execute-script! db 42))))
         (d (handler-depth (lambda () (execute-script! db "select 1;\x0;"))))
         (e (handler-depth (lambda () (execute-script! db "select 1; selekt 2"))))
         (f (handler-depth (lambda () (execute-script! db (string-append "select 1; " overflow-sql)))))
         (g (handler-depth (lambda () (execute-script! db "select 1; select 2"))))
         (h (begin (guard (e (#t #f)) (close-database! db))
                   (handler-depth (lambda () (execute-script! db "select 1"))))))
    (list a b c d e f g h (native-counts))))

;; --- a call resumed a second time, once its statement has left it --------------------------------
;; An engine's remainder is multi-shot. Resumed to its end, then again, the
;; call raises &sqlite-closed from the section that reads its flag next:
;; a bind's, a step's, a read's, the return's, or, for a script, its first
;; prepare's; or call-with-open-handle's or call-with-block's re-entered,
;; from its before thunk. Each after every section.

;; second-resumes : (Positive-Integer -> (Values (-> Any) (-> Boolean) (-> Any))) -> (Listof Any)
;; At each fuel from 1 until one slice completes, at most 5000, SETUP
;; answers a thunk to run, as an engine, under handler-depth; whether to
;; keep the fuel, read at the first expiry; and the fuel's undoing. Kept,
;; the remainder is resumed to its end, then again: each kept fuel's second
;; answer, each once, in the order first seen.
(define (second-resumes setup)
  (define (slice e fuel)
    (e fuel (lambda (left . vals) (list 'completed (car vals))) (lambda (more) (list 'expired more))))
  (define (finish e)
    (let loop ((e e) (n 0))
      (let ((r (slice e 1000000)))
        (cond ((eq? (car r) 'completed) (cadr r))
              ((>= n 1000) 'never-completed)
              (else (loop (cadr r) (+ n 1)))))))
  (let loop ((fuel 1) (seen '()))
    (let-values (((thunk keep? undo) (setup fuel)))
      (let* ((r (slice (make-engine (lambda () (handler-depth thunk))) fuel))
             (kept (and (eq? (car r) 'expired) (keep?)))
             (second (and kept (begin (finish (cadr r)) (finish (cadr r))))))
        (undo)
        (let ((seen (if (and kept (not (member second seen))) (append seen (list second)) seen)))
          (if (or (eq? (car r) 'completed) (>= fuel 5000))
              seen
              (loop (+ fuel 1) seen)))))))

;; resumed-closed : Symbol (Listof Any) (Listof Any) -> Any
;; closed-at-depth-1 when SEEN holds &sqlite-closed from NAME at depth 1,
;; and nothing but that and ALSO; else SEEN.
(define (resumed-closed name seen also)
  (if (and (member (at-depth-1 (closed name)) seen)
           (for-all (lambda (x) (or (equal? x (at-depth-1 (closed name))) (member x also))) seen))
      'closed-at-depth-1
      seen))

(define X "select x + ?1 from n order by x")

;; plain-resumed : Symbol (Database -> Any) -> Any
;; NAME's RUN on a fresh database holding n, its rows 1, 2 and 3, its cache
;; warm, at each fuel where the call holds its statement at the first
;; expiry, checked out of the cache.
(define (plain-resumed name run)
  (resumed-closed
   name
   (second-resumes
    (lambda (fuel)
      (let ((db (open-database ":memory:")))
        (tier-run db "create table n (x)")
        (tier-run db "insert into n values (1), (2), (3)")
        (run db)
        (values (lambda () (run db))
                (lambda () (and (= (database-cache-count db) 0) (= (length (tracked-statements db)) 1)))
                (lambda () (undo! '() (list db)))))))
   (list (at-depth-1 (refused name 're-entered)))))

(test-equal "execute!, query and query-row, an engine's remainder taken while the call held its statement and resumed a second time, at every such fuel until the call completes without expiring, raise &sqlite-closed from their own name, at depth 1, or call-with-open-handle's re-entered"
  '(closed-at-depth-1 closed-at-depth-1 closed-at-depth-1)
  (list (plain-resumed 'execute! (lambda (db) (no-value (execute! db X 10))))
        (plain-resumed 'query (lambda (db) (query db X 10)))
        (plain-resumed 'query-row (lambda (db) (query-row db X 10)))))

(test-equal "execute-script!, an engine's remainder resumed a second time, at every fuel until it completes without expiring: taken before its block, it raises &sqlite-closed from execute-script!, at depth 1; inside it, call-with-block's refusal, at depth 1; or it answers again, past the block or as a whole new call"
  'closed-at-depth-1
  (resumed-closed
   'execute-script!
   (second-resumes
    (lambda (fuel)
      (let ((db (open-database ":memory:")))
        (tier-run db "create table s (x)")
        (values (lambda () (no-value (execute-script! db "insert into s values (1); insert into s values (2)")))
                (lambda () #t)
                (lambda () (undo! '() (list db)))))))
   (list (at-depth-1 (refused 'execute-script!)) (list 'no-raise 'no-value))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "conveniences-who")

(exit (suite-exit-status runner))
