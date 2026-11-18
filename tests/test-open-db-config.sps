#!r6rs
;;; The suite for db_config's four settings at open (ADR-0021, decisions 1 to
;;; 5 and 10; ADR-0018, amended for M4; the M4 plan, sections 4.1, 4.3 and
;;; 4.7, and section 5, item 3), in (chez-sqlite3 private open):
;;; enable-load-extension, defensive, dqs-dml and dqs-ddl, each one
;;; sqlite3_db_config call in a critical section of its own, held by its own
;;; answer.
;;;
;;;   each set held     #t and #f for defensive, dqs-dml and dqs-ddl, and #t
;;;                     for enable-load-extension, read back by the suite's
;;;                     own -1 read through native on the open connection, a
;;;                     sentinel of its own each read; through both verbs, on
;;;                     :memory:, a file, read-only and no-mutex
;;;   each start        the library's start read by a -1 read on a
;;;   unasked           connection the suite opens itself through native's
;;;                     sqlite3_open_v2, outside open-database, then the same
;;;                     read on a connection open-database opened with no
;;;                     setting, (), the six PRAGMAs, the opt-in's #f, or one
;;;                     op alone, the other three compared (decision 2)
;;;   the opt-in's #f   beside an entry point sqlite3_auto_extension runs at
;;;                     every open, which starts the C switch at 1, as
;;;                     Ubuntu's library does: no call of 0 is made (Q15)
;;;   defensive         under it PRAGMA writable_schema = 1 answers done and
;;;                     reads back 0; with it off, 1 (Q6)
;;;   DQS               off, a double-quoted name that is no column fails at
;;;                     prepare, code error, never at the step; on, it is a
;;;                     string; each flag its own statements' alone
;;;   a stand-in        a set's failures and mismatches through a stand-in for
;;;                     the binding, given to applied-settings/with: an answer
;;;                     of 1 is &sqlite-error error, its message sqlite3_errstr's;
;;;                     0 with the cell left, the mismatch, actual (); 0 with
;;;                     the other value, the mismatch; 100, 101 and 256 an
;;;                     assertion violation from the who given, (not-an-error
;;;                     CODE); 21, &sqlite-error misuse. Each closes the
;;;                     connection first, every count 0 at the raise; the
;;;                     stand-in counts its calls, each given the connection's
;;;                     handle, the op, the value written and a cell holding
;;;                     the core's db-config-sentinel
;;;   the code, the     a failure's code is the call's own, on a fresh
;;;   message           connection whose own reads 0 and after a constraint's
;;;                     failure whose own reads constraint-unique; its message
;;;                     sqlite3_errstr's, never the connection's sqlite3_errmsg
;;;   once, in order    each set made once, in the list's order, a PRAGMA among
;;;                     them; a set that matched before one that fails made once
;;;   a failing close   a close that fails after a set's failure is not raised
;;;                     over it
;;;   the opt-in        the record holds it after (enable-load-extension . #t),
;;;                     read by database-extension-loading?, and not after its
;;;                     #f, no setting, (), or another op; where the library
;;;                     lacks sqlite3_load_extension, the opt-in's open is
;;;                     refused with &sqlite-extensions-unavailable instead, and
;;;                     the row says so
;;;   refusals          each of the four's values outside its domain, a name
;;;                     given twice, and the list's rules beside the opt-in,
;;;                     through both verbs, before anything is allocated; every
;;;                     other op of 3.45.1's and 3.54.1's headers, named by
;;;                     ADR-0021's rule, unknown-setting, trusted-schema aside,
;;;                     ADR-0018's PRAGMA
;;;   with the six      all four among the six PRAGMAs on a file: each PRAGMA
;;;                     and each op reads back as asked, nothing tracked
;;;   depth             each new raise site's with-exception-handler handler
;;;                     runs at interrupt depth 1, after every section
;;;
;;; The fifth check's order against the list's own rules needs a library
;;; without sqlite3_load_extension, so its rows are test-library-loading-
;;; real's, on the decoy. The loading procedures are reached through eval,
;;; under a guard, as tests/test-statement.sps reaches them, so the suite runs
;;; against a library that lacks slice 3's names, failing by name.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure foreign-ref foreign-set! directory-list
              disable-interrupts enable-interrupts foreign-callable foreign-callable-entry-point
              lock-object unlock-object)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3 private constants) sqlite-open-readwrite sqlite-open-create
              sqlite-open-fullmutex sqlite-open-exrescode sqlite-dbconfig-enable-load-extension
              sqlite-dbconfig-defensive sqlite-dbconfig-dqs-dml sqlite-dbconfig-dqs-ddl)
        (only (chez-sqlite3 private conditions) sqlite-setting-mismatch?
              sqlite-setting-mismatch-setting sqlite-setting-mismatch-expected
              sqlite-setting-mismatch-actual sqlite-extensions-unavailable?)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-error-message sqlite-error-sql
              sqlite-error-offset sqlite-closed?))

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

;; reach-value : (Listof Symbol) Symbol -> Any
;; NAME's value in LIBRARY, or (unreached NAME).
(define (reach-value library name)
  (guard (e (#t (list 'unreached name)))
    (eval name (environment library))))

(define (public name) (reach '(chez-sqlite3) name))

(define open-database (public 'open-database))
(define call-with-database (public 'call-with-database))
(define close-database! (public 'close-database!))
(define database? (public 'database?))
(define execute! (public 'execute!))
(define query (public 'query))
(define query-row (public 'query-row))
(define prepare-statement (public 'prepare-statement))
(define step! (public 'step!))
(define column-value (public 'column-value))
(define finalize-statement! (public 'finalize-statement!))
(define applied-settings/with (reach '(chez-sqlite3 private open) 'applied-settings/with))
(define database-extension-loading?
  (reach '(chez-sqlite3 private connection) 'database-extension-loading?))
(define tracked-statements (reach '(chez-sqlite3 private connection) 'tracked-statements))
(define database-cache-capacity (reach '(chez-sqlite3 private connection) 'database-cache-capacity))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-out-pointer (reach '(chez-sqlite3 private native) 'call-with-out-pointer))
(define call-with-int-cell (reach '(chez-sqlite3 private native) 'call-with-int-cell))
(define c-string->string (reach '(chez-sqlite3 private native) 'c-string->string))
(define sqlite3-db-config (reach '(chez-sqlite3 private native) 'sqlite3-db-config))
(define sqlite3-open-v2 (reach '(chez-sqlite3 private native) 'sqlite3-open-v2))
(define sqlite3-close (reach '(chez-sqlite3 private native) 'sqlite3-close))
(define sqlite3-errstr (reach '(chez-sqlite3 private native) 'sqlite3-errstr))
(define sqlite3-errmsg (reach '(chez-sqlite3 private native) 'sqlite3-errmsg))
(define sqlite3-extended-errcode (reach '(chez-sqlite3 private native) 'sqlite3-extended-errcode))

;; available : Any
;; native's record of sqlite3_load_extension, which an open that opts in
;; reads: #t where the library has it, #f where it lacks it, as Apple's does.
(define available (reach-value '(chez-sqlite3 private native) 'load-extension-available?))

;; sentinel : Any
;; The core's db-config-sentinel, which the shell fills the cell with.
(define sentinel (reach-value '(chez-sqlite3 private settings) 'db-config-sentinel))

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

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (connection-count) (cdr (assq 'connection (native-counts))))
(define (statement-count) (cdr (assq 'statement (native-counts))))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
;; E as the rows compare it: a mismatch by its who and its three fields, and
;; whether it is a library condition and not an &sqlite-error; the opt-in's
;; refusal by its who, the same; an &sqlite-error by its who, codes, SQL and
;; offset; &sqlite-closed by its who; an assertion violation by its who and
;; irritants.
(define (what-raised e)
  (cond ((sqlite-setting-mismatch? e)
         (list 'mismatch (who-of e) (sqlite-setting-mismatch-setting e)
               (sqlite-setting-mismatch-expected e) (sqlite-setting-mismatch-actual e)
               (if (and (chez-sqlite3-error? e) (not (sqlite-error? e))) 'library-condition 'other-kind)))
        ((sqlite-extensions-unavailable? e)
         (list 'extensions-unavailable (who-of e)
               (if (and (chez-sqlite3-error? e) (not (sqlite-error? e))) 'library-condition 'other-kind)))
        ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (sqlite-error-sql e) (sqlite-error-offset e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

;; with-message : Any -> Any
;; what-raised, and for an &sqlite-error its message too.
(define (with-message e)
  (if (sqlite-error? e)
      (list (what-raised e) (sqlite-error-message e))
      (what-raised e)))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define (close-answer r)
  (guard (e (#t #f)) (close-database! r)))

(define (a-database? x) (guard (e (#t #f)) (database? x)))

;; attempt-open : (-> Any) -> Any
;; attempt, but a database THUNK answers is closed, and answered as opened.
(define (attempt-open thunk)
  (let ((r (attempt thunk)))
    (if (a-database? r)
        (begin (close-answer r) 'opened)
        r)))

;; at-raise : (-> Any) (Any -> Any) -> (List Any Any)
;; What THUNK raised, as SHOW shows it, and the counts when it raised it,
;; read by a handler before anything unwinds; (no-raise V) when it raised
;; nothing, any database it answered closed.
(define raised-tag (list 'raised-tag))
(define (at-raise thunk show)
  (let* ((seen 'no-raise)
         (r (guard (e (#t (cons raised-tag e)))
              (with-exception-handler
               (lambda (c) (when (eq? seen 'no-raise) (set! seen (native-counts))) (raise c))
               thunk))))
    (if (and (pair? r) (eq? (car r) raised-tag))
        (list (show (cdr r)) seen)
        (begin (close-answer r) (list 'no-raise (if (a-database? r) 'a-database r))))))

(define (in-dir proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory proc)))

(define (made path) (if (file-exists? path) 'made 'not-made))

;; descriptors : -> Natural
(define (descriptors)
  (guard (e (#t (list 'unreadable (describe e))))
    (length (directory-list "/dev/fd"))))

;; with-db : (-> Database) (Database -> Any) -> Any
;; PROC's answer, or what it raised, given the database OPEN makes, closed
;; after, however PROC ends.
(define (with-db open proc)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda () (attempt (lambda () (set! db (open)) (proc db))))
      (lambda () (when db (close-answer db))))))

;; pragma : Database String -> Any
(define (pragma db name)
  (let ((row (query-row db (string-append "PRAGMA " name))))
    (if (vector? row) (vector-ref row 0) (list 'no-row row))))

(define (yes-no x) (cond ((eq? x #t) 'yes) ((eq? x #f) 'no) (else (list 'neither x))))

;; handle-of : Database -> Any
(define (handle-of db)
  (attempt (lambda () (call-with-open-handle 'test-open-db-config db (lambda (h) h)))))

;; --- db_config's reads, through native ----------------------------------------------------

;; ops : (Listof (Pairof Symbol Natural))
;; The four, by name and op, in the M4 plan's table order, the ops
;; constants.sls's, which test-constants holds to sqlite3.h.
(define ops
  (list (cons 'enable-load-extension sqlite-dbconfig-enable-load-extension)
        (cons 'defensive sqlite-dbconfig-defensive)
        (cons 'dqs-dml sqlite-dbconfig-dqs-dml)
        (cons 'dqs-ddl sqlite-dbconfig-dqs-ddl)))

(define (op-of name) (cdr (assq name ops)))

;; next-fill : Natural
;; The sentinel the next read fills its cell with: each read its own, never
;; 0 or 1, so a read that leaves its cell is seen as left, never as a value
;; another read wrote (AGENTS.md: each round trip its own sentinel).
(define next-fill 700)
(define (fresh-fill!) (set! next-fill (+ next-fill 1)) next-fill)

;; raw-read : Natural Natural -> (List Integer (U Integer 'left))
;; OP's state on the connection whose handle is H, by a -1 read through
;; native's binding: the code, and the cell, left when it still holds the
;; read's own fill.
(define (raw-read h op)
  (let ((fill (fresh-fill!)))
    (let-values (((code cell)
                  (call-with-int-cell 'test-open-db-config fill
                    (lambda (c) (sqlite3-db-config h op -1 c)))))
      (list code (if (eqv? cell fill) 'left cell)))))

;; op-read : Database Symbol -> Any
;; NAME's op read on DB, by raw-read inside call-with-open-handle, or what
;; that raised.
(define (op-read db name)
  (attempt (lambda ()
             (call-with-open-handle 'test-open-db-config db
               (lambda (h) (raw-read h (op-of name)))))))

;; op-reads : Database -> (Listof Any)
;; The four's states on DB, in the table's order, each read in order.
(define (op-reads db)
  (let loop ((rest ops) (found '()))
    (if (null? rest)
        (reverse found)
        (loop (cdr rest) (cons (op-read db (car (car rest))) found)))))

;; raw-flags : Natural
;; open-database's flags with no option: read-write, create, the full mutex
;; and extended codes (ADR-0012, decision 3).
(define raw-flags
  (bitwise-ior sqlite-open-readwrite sqlite-open-create sqlite-open-fullmutex sqlite-open-exrescode))

;; raw-starts : String -> Any
;; The four's states on a connection to NAME the suite opens itself, through
;; native's sqlite3_open_v2, outside open-database, read in order, then
;; closed through native's sqlite3_close; or what failed.
(define (raw-starts name)
  (guard (e (#t (list 'raised (describe e))))
    (let-values (((rc h)
                  (call-with-c-string 'test-open-db-config name
                    (lambda (c)
                      (call-with-out-pointer 'test-open-db-config
                        (lambda (slot) (sqlite3-open-v2 c slot raw-flags 0)))))))
      (if (not (and (eqv? rc 0) (not (eqv? h 0))))
          (begin (unless (eqv? h 0) (sqlite3-close h)) (list 'raw-open-failed rc))
          (let* ((found (let loop ((rest ops) (found '()))
                          (if (null? rest)
                              (reverse found)
                              (loop (cdr rest) (cons (raw-read h (cdr (car rest))) found)))))
                 (closed (sqlite3-close h)))
            (if (eqv? closed 0) found (list 'raw-close-failed closed found)))))))

;; errstr : Integer -> Any
;; sqlite3_errstr's text for CODE, read through native: what a set's failure
;; carries as its message (ADR-0021, decision 3).
(define (errstr code)
  (guard (e (#t (list 'raised (describe e))))
    (c-string->string (sqlite3-errstr code))))

;; connection-error : Database -> Any
;; DB's own extended code and sqlite3_errmsg, read through native.
(define (connection-error db)
  (attempt (lambda ()
             (call-with-open-handle 'test-open-db-config db
               (lambda (h) (list (sqlite3-extended-errcode h) (c-string->string (sqlite3-errmsg h))))))))

;; --- the opt-in, chosen by what the library reports ---------------------------------------

;; opt-in-or-refusal : Symbol Any -> Any
;; EXPECTED where the library has sqlite3_load_extension; where it lacks it,
;; the opt-in's refusal from WHO, raised before anything opens.
(define (opt-in-or-refusal who expected)
  (if (eq? available #t)
      expected
      (list 'raised (list 'extensions-unavailable who 'library-condition))))

;; unavailable-noted! : String -> Void
;; Where the library lacks sqlite3_load_extension, the row NAME's opt-in
;; part printed unavailable, its refusal asserted in its place, never
;; passed unseen (ADR-0005, amended).
(define (unavailable-noted! name)
  (unless (eq? available #t)
    (display "UNAVAILABLE ")
    (display name)
    (display ", its opt-in: this libsqlite3 has no sqlite3_load_extension, so the open's refusal is asserted in its place")
    (newline)))

;; --- a stand-in for the binding -----------------------------------------------------------

;; Call = (List Any Integer Integer Any)
;; A stand-in's call: the handle, the op, the value written, and what the
;; cell held when the call began.

;; stand-in : (Integer Integer -> (List Any (U Integer #f))) -> (Values Procedure (-> (Listof Call)))
;; A stand-in for native's sqlite3-db-config, and a reader of its calls,
;; oldest first. ANSWER, given the op and the value, answers the code to
;; give and what to write to the cell, #f for nothing. It runs inside the
;; set's critical section: it notes, reads and writes the cell, and raises
;; nothing.
(define (stand-in answer)
  (let ((calls '()))
    (values
     (lambda (h op value cell)
       (set! calls (cons (list h op value (foreign-ref 'int cell 0)) calls))
       (let ((a (answer op value)))
         (when (cadr a) (foreign-set! 'int cell 0 (cadr a)))
         (car a)))
     (lambda () (reverse calls)))))

;; passing : Integer Integer -> (List Integer (U Integer #f))
;; The answer of a set that took: 0, the value written to the cell.
(define (passing op value) (list 0 value))

;; stood : String Symbol (Listof Any) (Integer Integer -> (List Any (U Integer #f)))
;;         -> (List Any Any Any Any (Listof Call) Any)
;; A connection opened on PATH, then STEPS applied by applied-settings/with
;; for WHO with a stand-in answering by ANSWER: what that raised, as
;; with-message shows it, and the counts at the raise; the counts after;
;; whether the descriptors are those before the open; what a query on the
;; connection then answers; the stand-in's calls, the handle each was given
;; read as the connection's or another; and the connection's handle.
(define (stood path who steps answer)
  (let-values (((db-config calls) (stand-in answer)))
    (let* ((before (descriptors))
           (db (open-database path))
           (h (handle-of db))
           (r (at-raise (lambda () (applied-settings/with who db steps db-config) 'applied)
                        with-message))
           (counts (native-counts))
           (back (if (equal? (descriptors) before) 'descriptors-back (list 'descriptors before (descriptors))))
           (after (attempt (lambda () (query-row db "select 1")))))
      (close-answer db)
      (list r counts back after
            (let loop ((rest (calls)) (found '()))
              (if (null? rest)
                  (reverse found)
                  (loop (cdr rest)
                        (cons (cons (if (eqv? (car (car rest)) h) 'the-handle (list 'another (car (car rest))))
                                    (cdr (car rest)))
                              found))))
            (native-counts)))))

;; failed-closed : Any -> (List Any Any Any Any)
;; What stood answers for a set whose failure RAISED closed the connection
;; first: the raise with every count zero at it, zero after, the
;; descriptors back, a query refused as closed.
(define (failed-closed raised)
  (list (list raised zero-counts) zero-counts 'descriptors-back '(raised (closed query-row))))

;; first-four : (Listof Any) -> (Listof Any)
(define (first-four r) (list (car r) (cadr r) (caddr r) (cadddr r)))

(define (step-of name value) (list name (op-of name) (if value 1 0) value))

(test-begin "open-db-config")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-equal "native records sqlite3_load_extension as a boolean, the opt-in's check, and the core's sentinel is -1, neither 0 nor 1"
  '(boolean -1)
  (begin
    (display "    extension loading: ")
    (write available)
    (newline)
    (list (if (boolean? available) 'boolean available) sentinel)))

;; --- each set held -----------------------------------------------------------------------

;; held-cases : (Listof (Pairof Symbol Boolean))
(define held-cases
  '((defensive . #t) (defensive . #f) (dqs-dml . #t) (dqs-dml . #f) (dqs-ddl . #t) (dqs-ddl . #f)
    (enable-load-extension . #t)))

;; held-expected : Symbol (Pairof Symbol Boolean) -> Any
;; The case's own op read back as asked, code 0 and the cell 1 or 0; the
;; opt-in's refusal where the library lacks the entry point.
(define (held-expected who case)
  (let ((read (list 0 (if (cdr case) 1 0))))
    (if (eq? (car case) 'enable-load-extension)
        (opt-in-or-refusal who read)
        read)))

;; held-run : (-> Database) Symbol -> Any
(define (held-run open name)
  (with-db open (lambda (db) (op-read db name))))

(let ((name "each set held: #t and #f for defensive, dqs-dml and dqs-ddl, and #t for enable-load-extension, through open-database on :memory:, each read back by the suite's own -1 read through native on the open connection, a sentinel of its own each read: code 0 and the cell the value written"))
  (unavailable-noted! name)
  (test-equal name
    (let loop ((rest held-cases) (expected '()))
      (if (null? rest)
          (reverse expected)
          (loop (cdr rest) (cons (held-expected 'open-database (car rest)) expected))))
    (let loop ((rest held-cases) (found '()))
      (if (null? rest)
          (reverse found)
          (let ((case (car rest)))
            (loop (cdr rest)
                  (cons (held-run (lambda () (open-database ":memory:" (list case))) (car case))
                        found)))))))

(let ((name "each set held the same through call-with-database, read inside its procedure"))
  (unavailable-noted! name)
  (test-equal name
    (let loop ((rest held-cases) (expected '()))
      (if (null? rest)
          (reverse expected)
          (loop (cdr rest) (cons (held-expected 'call-with-database (car rest)) expected))))
    (let loop ((rest held-cases) (found '()))
      (if (null? rest)
          (reverse found)
          (let ((case (car rest)))
            (loop (cdr rest)
                  (cons (attempt (lambda () (call-with-database ":memory:" (list case)
                                              (lambda (db) (op-read db (car case))))))
                        found)))))))

(let ((name "each set held on every connection an open makes: a file, then the file read-only, then no-mutex, each with all three ops off their start and the opt-in, every op read back as asked"))
  (unavailable-noted! name)
  (test-equal name
    (let ((asked (list (opt-in-or-refusal 'open-database '((0 1) (0 1) (0 0) (0 0))))))
      (list asked asked asked zero-counts))
    (in-dir (lambda (dir)
              (let* ((path (string-append dir "/h.db"))
                     (list-of '((enable-load-extension . #t) (defensive . #t) (dqs-dml . #f)
                                (dqs-ddl . #f)))
                     (a (with-db (lambda () (open-database path list-of)) op-reads))
                     (b (with-db (lambda () (open-database path 'read-only list-of)) op-reads))
                     (c (with-db (lambda () (open-database path 'no-mutex list-of)) op-reads)))
                (list (list a) (list b) (list c) (native-counts)))))))

;; --- each start unasked (decision 2; the M4 plan, section 4.7) -----------------------------

;; starts-on : (-> Database) -> Any
(define (starts-on open) (with-db open op-reads))

(test-equal "the library's start is read on a connection the suite opens itself, through native's sqlite3_open_v2, outside open-database: four reads, each answered"
  'read
  (let ((starts (raw-starts ":memory:")))
    (display "    the library's starts, enable-load-extension, defensive, dqs-dml, dqs-ddl: ")
    (write starts)
    (newline)
    (if (and (list? starts) (= (length starts) 4)
             (for-all (lambda (r) (and (list? r) (= (length r) 2) (integer? (car r)))) starts))
        'read
        starts)))

(test-equal "each start unasked: a connection open-database opens with no setting, with (), with the six PRAGMAs and statement-cache, and with (enable-load-extension . #f), and one call-with-database opens with none, reads all four ops as the suite's own connection does, opened outside open-database; on a file too"
  (let ((s (raw-starts ":memory:")))
    (list s s s s s s))
  (in-dir (lambda (dir)
            (let* ((a (starts-on (lambda () (open-database ":memory:"))))
                   (b (starts-on (lambda () (open-database ":memory:" '()))))
                   (c (starts-on (lambda ()
                                   (open-database (string-append dir "/p.db")
                                                  '((busy-timeout . 5) (foreign-keys . #t)
                                                    (journal-mode . truncate) (synchronous . off)
                                                    (temp-store . file) (trusted-schema . #f)
                                                    (statement-cache . 4))))))
                   (d (starts-on (lambda () (open-database ":memory:" '((enable-load-extension . #f))))))
                   (e (attempt (lambda () (call-with-database ":memory:" op-reads))))
                   (f (starts-on (lambda () (open-database (string-append dir "/s.db"))))))
              (list a b c d e f)))))

;; others-than : Symbol (Listof Any) -> (Listof Any)
;; READS, the four's in the table's order, without NAME's.
(define (others-than name reads)
  (let loop ((rest ops) (reads reads) (kept '()))
    (cond ((or (null? rest) (not (pair? reads))) (reverse kept))
          ((eq? (car (car rest)) name) (loop (cdr rest) (cdr reads) kept))
          (else (loop (cdr rest) (cdr reads) (cons (car reads) kept))))))

(test-equal "a list naming one op leaves the other three at the library's start: each of defensive, dqs-dml and dqs-ddl, at the value other than its start"
  (let ((s (raw-starts ":memory:")))
    (list (others-than 'defensive s) (others-than 'dqs-dml s) (others-than 'dqs-ddl s)))
  (let* ((s (raw-starts ":memory:"))
         (other (lambda (name)
                  (let ((r (and (list? s) (list-ref s (if (eq? name 'defensive) 1 (if (eq? name 'dqs-dml) 2 3))))))
                    (not (and (list? r) (eqv? (cadr r) 1))))))
         (a (starts-on (lambda () (open-database ":memory:" (list (cons 'defensive (other 'defensive)))))))
         (b (starts-on (lambda () (open-database ":memory:" (list (cons 'dqs-dml (other 'dqs-dml)))))))
         (c (starts-on (lambda () (open-database ":memory:" (list (cons 'dqs-ddl (other 'dqs-ddl))))))))
    (list (others-than 'defensive a) (others-than 'dqs-dml b) (others-than 'dqs-ddl c))))

;; --- the opt-in's #f beside a C switch that starts on (Q15) ---------------------------------
;; Ubuntu's library starts ENABLE_LOAD_EXTENSION at 1, every other this suite
;; meets at 0 (the M4 pre-work's census), so the start rows see a call of 0
;; for the opt-in's #f, which must never be made (ADR-0021, decision 5), on
;; Ubuntu's alone. Here an entry point that sqlite3_auto_extension runs at
;; every open sets the op to 1 on each new connection, through native's
;; binding: a start of 1 on every lane, read first on the suite's own
;; connection. The entry point is __collect_safe, as sqlite3_open_v2, which
;; calls it, is, and raises nothing. A libsqlite3 can refuse the
;; registration: Apple's 3.51.0 answers 21, SQLITE_MISUSE, as
;; test-open-interleave records; then the row is printed unavailable, and the
;; refusal, 21 and no other code, is asserted in its place (ADR-0005,
;; amended). It is unregistered by sqlite3_reset_auto_extension, which frees
;; SQLite's list, and unlocked once.

;; int sqlite3_auto_extension(void (*xEntryPoint)(void))
(define auto-extension
  (bound 'sqlite3_auto_extension (foreign-procedure "sqlite3_auto_extension" (uptr) int)))
;; void sqlite3_reset_auto_extension(void)
(define reset-auto-extension
  (bound 'sqlite3_reset_auto_extension (foreign-procedure "sqlite3_reset_auto_extension" () void)))

;; int (*xEntryPoint)(sqlite3 *db, const char **pzErrMsg, const sqlite3_api_routines *pThunk)
;; The new connection's op set to 1, its answer dropped; 0, always.
(define switch-on
  (foreign-callable __collect_safe
    (lambda (db message api)
      (guard (e (#t 0))
        (call-with-int-cell 'test-open-db-config 9
          (lambda (c) (sqlite3-db-config db sqlite-dbconfig-enable-load-extension 1 c)))
        0))
    (uptr uptr uptr) int))

;; switched-reads : -> Any
;; With switch-on registered: the op read on the suite's own connection,
;; then on connections open-database opens with no setting and with the
;; opt-in's #f, one call-with-database opens with its #f, and, where the
;; library has sqlite3_load_extension, one open-database opens with its #t;
;; then, unregistered, the op on open-database's connection with no setting,
;; read as the library's start, before. Or (refused CODE).
(define (switched-reads)
  (let ((before (let ((s (raw-starts ":memory:"))) (if (pair? s) (car s) s))))
    (lock-object switch-on)
    (let ((rc (guard (e (#t (list 'raised (describe e))))
                (auto-extension (foreign-callable-entry-point switch-on)))))
      (let ((reads
             (dynamic-wind
        (lambda () #f)
        (lambda ()
          (if (not (eqv? rc 0))
              (list 'refused rc)
              (let* ((raw (let ((s (raw-starts ":memory:"))) (if (pair? s) (car s) s)))
                     (none (with-db (lambda () (open-database ":memory:"))
                                    (lambda (db) (op-read db 'enable-load-extension))))
                     (off (with-db (lambda () (open-database ":memory:" '((enable-load-extension . #f))))
                                   (lambda (db) (op-read db 'enable-load-extension))))
                     (cwd (attempt (lambda ()
                                     (call-with-database ":memory:" '((enable-load-extension . #f))
                                       (lambda (db) (op-read db 'enable-load-extension))))))
                     (on (if (eq? available #t)
                             (with-db (lambda () (open-database ":memory:" '((enable-load-extension . #t))))
                                      (lambda (db) (op-read db 'enable-load-extension)))
                             'not-asked)))
                (list raw none off cwd on))))
        (lambda ()
          (when (eqv? rc 0) (reset-auto-extension))
          (unlock-object switch-on)))))
        (list reads
              (if (eqv? rc 0)
                  (let ((after (with-db (lambda () (open-database ":memory:"))
                                        (lambda (db) (op-read db 'enable-load-extension)))))
                    (if (equal? after before) 'after-as-before (list 'after after 'before before)))
                  'not-registered))))))

(define switched (guard (e (#t (list 'raised (describe e)))) (switched-reads)))

(test-equal "where an entry point every open runs starts enable-load-extension's C switch at 1, as Ubuntu's library does: the suite's own connection reads 1, and so do open-database's with no setting and with (enable-load-extension . #f), and call-with-database's with its #f, no call of 0 made; the opt-in's #t reads 1 too; unregistered, an open reads the library's own start again"
  (if (and (pair? switched) (pair? (car switched)) (eq? (car (car switched)) 'refused))
      (list (list 'refused 21) 'not-registered)
      (list (list '(0 1) '(0 1) '(0 1) '(0 1) (if (eq? available #t) '(0 1) 'not-asked))
            'after-as-before))
  (begin
    (when (and (pair? switched) (pair? (car switched)) (eq? (car (car switched)) 'refused))
      (display "UNAVAILABLE the opt-in's #f beside a C switch that starts on: this libsqlite3 refused sqlite3_auto_extension (")
      (write (cadr (car switched)))
      (display "), so its refusal, 21, is asserted in its place")
      (newline))
    switched))

;; --- defensive's writable_schema (Q6) ------------------------------------------------------

;; writable : Database -> Any
;; PRAGMA writable_schema = 1 prepared and stepped on DB: what the step
;; answered, done or a row, then what PRAGMA writable_schema reads back.
(define (writable db)
  (let* ((st (prepare-statement db "PRAGMA writable_schema = 1"))
         (stepped (step! st))
         (gone (finalize-statement! st))
         (read (pragma db "writable_schema")))
    (list (if stepped 'a-row 'done) read)))

(test-equal "under defensive, PRAGMA writable_schema = 1 answers done and does nothing: it reads back 0; with defensive off it reads back 1, so the 0 is defensive's (Q6)"
  '((done 0) (done 1) (done 0) zero-counts)
  (let* ((a (with-db (lambda () (open-database ":memory:" '((defensive . #t)))) writable))
         (b (with-db (lambda () (open-database ":memory:" '((defensive . #f)))) writable))
         (c (attempt (lambda () (call-with-database ":memory:" '((defensive . #t)) writable))))
         (counts (native-counts)))
    (list a b c (if (equal? counts zero-counts) 'zero-counts counts))))

;; --- DQS at prepare --------------------------------------------------------------------------

;; prepared-as : Database String -> Any
;; SQL prepared on DB, then stepped once: (row V), V its first column,
;; done, or what the prepare or the step raised, by its who and code alone,
;; never its message, which differs by version (the M4 plan, section 4.1).
(define (prepared-as db sql)
  (guard (e ((sqlite-error? e) (list 'refused (who-of e) (sqlite-error-code e)))
            (#t (list 'raised (what-raised e))))
    (let* ((st (prepare-statement db sql))
           (stepped (guard (e ((sqlite-error? e) (list 'step-refused (sqlite-error-code e))))
                      (step! st)))
           (answer (cond ((eq? stepped #t) (list 'row (column-value st 0)))
                         ((eq? stepped #f) 'done)
                         (else stepped))))
      (finalize-statement! st)
      answer)))

;; dqs-run : Any -> Any
;; On :memory: opened with SETTINGS: a double-quoted name that is no column
;; in DML, then in DDL, each prepared as prepared-as runs it.
(define (dqs-run settings)
  (with-db (lambda () (open-database ":memory:" settings))
    (lambda (db)
      (execute! db "create table t (x)")
      (let* ((dml (prepared-as db "select \"nosuch\""))
             (ddl (prepared-as db "create index i on t (\"nosuch\")")))
        (list dml ddl)))))

(test-equal "with dqs-dml off, a double-quoted name that is no column fails in DML at prepare, prepare-statement's error, never at its step; on, it is the string; dqs-ddl off fails DDL's the same at prepare and leaves DML's a string; each flag its own statements' alone; both on, both run"
  '(((refused prepare-statement error) done)
    ((row "nosuch") (refused prepare-statement error))
    ((row "nosuch") done)
    ((refused prepare-statement error) (refused prepare-statement error)))
  (list (dqs-run '((dqs-dml . #f)))
        (dqs-run '((dqs-ddl . #f)))
        (dqs-run '((dqs-dml . #t) (dqs-ddl . #t)))
        (dqs-run '((dqs-ddl . #f) (dqs-dml . #f)))))

;; --- a set's failures and mismatches, through a stand-in ------------------------------------

(test-equal "a stand-in that answers 0 and writes the value: the set matches, the connection stays open; the stand-in is called once, with the connection's handle, the op, the value written and a cell holding the core's db-config-sentinel"
  (list (list (list 'no-raise 'applied) (list '(connection . 1)) 'descriptors-back '#(1))
        (list (list 'the-handle sqlite-dbconfig-defensive 1 sentinel)))
  (let ((r (stood ":memory:" 'the-suite (list (step-of 'defensive #t)) passing)))
    (list (list (car r) (filter (lambda (p) (eq? (car p) 'connection)) (cadr r)) (caddr r)
                (cadddr r))
          (list-ref r 4))))

;; failure-cases : (Listof (List Any Symbol (Listof Any) (Integer Integer -> (List Any (U Integer #f))) Any))
;; Each case: its label, the who given, its steps, the stand-in's answer,
;; and what the set must raise, closing the connection first.
(define failure-cases
  (list
   (list 'one 'the-suite (list (step-of 'defensive #t)) (lambda (op v) (list 1 #f))
         (list (list 'sqlite-error 'the-suite 'error 'error #f #f) (errstr 1)))
   (list 'left 'the-suite (list (step-of 'defensive #t)) (lambda (op v) (list 0 #f))
         '(mismatch the-suite defensive #t () library-condition))
   (list 'other-false 'the-suite (list (step-of 'defensive #t)) (lambda (op v) (list 0 0))
         '(mismatch the-suite defensive #t #f library-condition))
   (list 'other-true 'the-suite (list (step-of 'dqs-dml #f)) (lambda (op v) (list 0 1))
         '(mismatch the-suite dqs-dml #f #t library-condition))
   (list 'other-integer 'the-suite (list (step-of 'dqs-ddl #t)) (lambda (op v) (list 0 7))
         '(mismatch the-suite dqs-ddl #t 7 library-condition))
   (list 'opt-in-left 'the-suite (list (step-of 'enable-load-extension #t)) (lambda (op v) (list 0 #f))
         '(mismatch the-suite enable-load-extension #t () library-condition))
   (list 'hundred 'open-database (list (step-of 'defensive #t)) (lambda (op v) (list 100 1))
         '(assertion-violation open-database (not-an-error 100)))
   (list 'hundred-one 'call-with-database (list (step-of 'dqs-dml #t)) (lambda (op v) (list 101 1))
         '(assertion-violation call-with-database (not-an-error 101)))
   (list 'two-five-six 'open-database (list (step-of 'dqs-ddl #f)) (lambda (op v) (list 256 0))
         '(assertion-violation open-database (not-an-error 256)))
   (list 'misuse 'the-suite (list (step-of 'enable-load-extension #t)) (lambda (op v) (list 21 #f))
         (list (list 'sqlite-error 'the-suite 'misuse 'misuse #f #f) (errstr 21)))))

(test-equal "a set's failures and mismatches through a stand-in, each closing the connection first, every count 0 at the raise and after, no descriptor left open: an answer of 1 is &sqlite-error error, its message sqlite3_errstr's, no SQL and no offset; 0 with the cell left, the mismatch, actual (); 0 with the other value, the mismatch, #f or #t; 0 with 7, 7; 100, 101 and 256 an assertion violation from the who given, (not-an-error CODE); Apple's 21, &sqlite-error misuse; the stand-in called once each"
  (let loop ((rest failure-cases) (expected '()))
    (if (null? rest)
        (reverse expected)
        (let ((c (car rest)))
          (loop (cdr rest)
                (cons (list (car c) (failed-closed (list-ref c 4)) 1 zero-counts) expected)))))
  (in-dir (lambda (dir)
            (let loop ((rest failure-cases) (i 0) (found '()))
              (if (null? rest)
                  (reverse found)
                  (let* ((c (car rest))
                         (r (stood (string-append dir "/f" (number->string i) ".db") (cadr c) (caddr c)
                                   (cadddr c))))
                    (loop (cdr rest) (+ i 1)
                          (cons (list (car c) (first-four r) (length (list-ref r 4)) (list-ref r 5))
                                found))))))))

;; --- the code and the message: the call's, never the connection's --------------------------

(test-equal "a failure's code is the call's own, never the connection's: on a fresh connection, whose own extended code reads 0 through native, a stand-in answering 1 raises &sqlite-error error, not an assertion violation (not-an-error 0)"
  (list '(0 ok) (list (list 'sqlite-error 'the-suite 'error 'error #f #f) (errstr 1)))
  (with-db (lambda () (open-database ":memory:"))
    (lambda (db)
      (let-values (((db-config calls) (stand-in (lambda (op v) (list 1 #f)))))
        (let* ((own (connection-error db))
               (own-code (if (and (list? own) (integer? (car own)))
                             (list (car own) (if (eqv? (car own) 0) 'ok 'not-ok))
                             own))
               (r (guard (e (#t (with-message e)))
                    (applied-settings/with 'the-suite db (list (step-of 'defensive #t)) db-config)
                    'no-raise)))
          (list own-code r))))))

;; after-constraint : Database -> Any
;; A unique constraint's failure on DB, so its own extended code and message
;; are that failure's.
(define (after-constraint! db)
  (execute! db "create table u (x unique)")
  (execute! db "insert into u values (1)")
  (guard (e ((sqlite-error? e) 'failed))
    (execute! db "insert into u values (1)")
    'not-failed))

(test-equal "after a constraint's failure on the connection, its own code constraint-unique and its message the constraint's, read through native, a stand-in answering 1 raises &sqlite-error error, never constraint, its message sqlite3_errstr's for 1, which the connection's differs from"
  (list 'failed 2067 'messages-differ (list (list 'sqlite-error 'the-suite 'error 'error #f #f) (errstr 1)))
  (with-db (lambda () (open-database ":memory:"))
    (lambda (db)
      (let-values (((db-config calls) (stand-in (lambda (op v) (list 1 #f)))))
        (let* ((failed (after-constraint! db))
               (own (connection-error db))
               (r (guard (e (#t (with-message e)))
                    (applied-settings/with 'the-suite db (list (step-of 'dqs-dml #f)) db-config)
                    'no-raise)))
          (list failed
                (if (list? own) (car own) own)
                (if (and (list? own) (string? (cadr own)) (not (equal? (cadr own) (errstr 1))))
                    'messages-differ
                    (list 'messages own (errstr 1)))
                r))))))

;; --- once, in order ---------------------------------------------------------------------------

;; once-steps : (Listof Any)
;; The four, the opt-in only where the library has sqlite3_load_extension,
;; whose op Apple's library answers 21 to, and a PRAGMA among them.
(define once-steps
  (append (if (eq? available #t) (list (step-of 'enable-load-extension #t)) '())
          (list (step-of 'defensive #t)
                '(foreign-keys "PRAGMA foreign_keys = 1" "PRAGMA foreign_keys" #t)
                (step-of 'dqs-dml #f)
                (step-of 'dqs-ddl #f))))

(let ((name "each set is made once, in the list's order, a PRAGMA among them, by a stand-in that notes each call, then passes it to native's binding: its calls are the ops and the values written, in order, each once, each given the connection's handle and a cell holding the sentinel; each op then reads back as asked, and the PRAGMA too"))
  (unavailable-noted! name)
  (test-equal name
    (list (list 'no-raise 'applied)
          (append (if (eq? available #t)
                      (list (list 'the-handle sqlite-dbconfig-enable-load-extension 1 sentinel))
                      '())
                  (list (list 'the-handle sqlite-dbconfig-defensive 1 sentinel)
                        (list 'the-handle sqlite-dbconfig-dqs-dml 0 sentinel)
                        (list 'the-handle sqlite-dbconfig-dqs-ddl 0 sentinel)))
          (append (if (eq? available #t) '((0 1)) '()) '((0 1) (0 0) (0 0) 1)))
    (let-values (((note calls) (stand-in (lambda (op v) (list 'noted #f)))))
      (let* ((through (lambda (h op v cell)
                        (note h op v cell)
                        (sqlite3-db-config h op v cell)))
             (db (open-database ":memory:"))
             (h (handle-of db))
             (r (at-raise (lambda () (applied-settings/with 'the-suite db once-steps through) 'applied)
                          what-raised))
             (reads (append (if (eq? available #t) (list (op-read db 'enable-load-extension)) '())
                            (list (op-read db 'defensive) (op-read db 'dqs-dml) (op-read db 'dqs-ddl)
                                  (pragma db "foreign_keys")))))
        (close-answer db)
        (list r
              (let loop ((rest (calls)) (found '()))
                (if (null? rest)
                    (reverse found)
                    (loop (cdr rest) (cons (cons (if (eqv? (car (car rest)) h) 'the-handle 'another)
                                                 (cdr (car rest)))
                                           found))))
              reads)))))

(test-equal "a set that matched before one that fails is made once, and the failing one once, then the connection is closed: two calls, every count 0 at the raise"
  (list (failed-closed '(mismatch the-suite dqs-dml #f () library-condition)) 2
        (list sqlite-dbconfig-defensive sqlite-dbconfig-dqs-dml))
  (in-dir (lambda (dir)
            (let ((r (stood (string-append dir "/o.db") 'the-suite
                            (list (step-of 'defensive #t) (step-of 'dqs-dml #f))
                            (lambda (op v) (if (eqv? op sqlite-dbconfig-defensive) (list 0 v) (list 0 #f))))))
              (list (first-four r) (length (list-ref r 4))
                    (let loop ((rest (list-ref r 4)) (found '()))
                      (if (null? rest) (reverse found) (loop (cdr rest) (cons (cadr (car rest)) found)))))))))

;; --- a close that fails after a set's failure ----------------------------------------------

;; raw-prepare! : Database String -> Positive-Integer
;; A statement of SQL on DB, made with the raw sqlite3_prepare_v2, so the
;; connection does not track it, and its close is refused.
(define (raw-prepare! db sql)
  (call-with-open-handle 'test-open-db-config db
    (lambda (h)
      (call-with-c-string 'test-open-db-config sql
        (lambda (text)
          (let-values (((rc statement)
                        (call-with-out-pointer 'test-open-db-config
                          (lambda (slot) (prepare-v2 h text -1 slot 0)))))
            (if (and (eqv? rc 0) (not (eqv? statement 0)))
                statement
                (error 'raw-prepare! "sqlite3_prepare_v2 did not answer a statement" rc))))))))

;; close-fails : (Integer Integer -> (List Any (U Integer #f))) -> (List Any Natural Any Any)
;; On a :memory: connection holding a statement it does not track, so its
;; close is refused, defensive's set applied by applied-settings/with with a
;; stand-in answering by ANSWER: what that raised; the connections counted;
;; a query's answer on the connection, still open; and its close once the
;; statement is gone.
(define (close-fails answer)
  (let ((db #f) (raw #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (let-values (((db-config calls) (stand-in answer)))
             (set! db (open-database ":memory:"))
             (set! raw (raw-prepare! db "select 1"))
             (let* ((r (guard (e (#t (with-message e)))
                         (applied-settings/with 'the-suite db (list (step-of 'defensive #t)) db-config)
                         'applied))
                    (n (connection-count))
                    (alive (attempt (lambda () (query-row db "select 7"))))
                    (freed (begin (raw-finalize raw) (set! raw #f)))
                    (closed (attempt (lambda () (close-database! db) 'closed))))
               (list r n alive closed))))))
      (lambda ()
        (when raw (raw-finalize raw))
        (when db (close-answer db))))))

(test-equal "a close that fails after a set's failure is not raised over it: with an untracked statement on the connection, a stand-in answering 1 raises the set's &sqlite-error, and one leaving the cell the mismatch, never the close's refusal; the connection stays open and counted, and closes once the statement is gone"
  (list (list (list (list 'sqlite-error 'the-suite 'error 'error #f #f) (errstr 1)) 1 '#(7) 'closed)
        (list '(mismatch the-suite defensive #t () library-condition) 1 '#(7) 'closed)
        zero-counts)
  (let* ((a (close-fails (lambda (op v) (list 1 #f))))
         (b (close-fails (lambda (op v) (list 0 #f)))))
    (list a b (native-counts))))

;; --- the record's opt-in ------------------------------------------------------------------

;; opt-in-of : (-> Database) -> Any
;; database-extension-loading? on the connection OPEN makes, as yes or no.
(define (opt-in-of open)
  (with-db open (lambda (db) (yes-no (database-extension-loading? db)))))

(let ((name "the record holds the opt-in, fixed when it is made, read by database-extension-loading?: after (enable-load-extension . #t), through both verbs, and beside the other three; not after its #f, which makes no call, nor with no setting, (), the other three at #t, or the six PRAGMAs"))
  (unavailable-noted! name)
  (test-equal name
    (list (opt-in-or-refusal 'open-database 'yes)
          (opt-in-or-refusal 'call-with-database 'yes)
          (opt-in-or-refusal 'open-database 'yes)
          'no 'no 'no 'no 'no 'no)
    (list (opt-in-of (lambda () (open-database ":memory:" '((enable-load-extension . #t)))))
          (attempt (lambda () (call-with-database ":memory:" '((enable-load-extension . #t))
                                (lambda (db) (yes-no (database-extension-loading? db))))))
          (opt-in-of (lambda () (open-database ":memory:" '((defensive . #t) (enable-load-extension . #t)
                                                            (dqs-dml . #f)))))
          (opt-in-of (lambda () (open-database ":memory:" '((enable-load-extension . #f)))))
          (opt-in-of (lambda () (open-database ":memory:")))
          (opt-in-of (lambda () (open-database ":memory:" '())))
          (opt-in-of (lambda () (open-database ":memory:" '((defensive . #t) (dqs-dml . #t) (dqs-ddl . #t)))))
          (opt-in-of (lambda () (open-database ":memory:" '((busy-timeout . 1) (foreign-keys . #t)
                                                            (trusted-schema . #t) (statement-cache . 2)))))
          (attempt (lambda () (call-with-database ":memory:" '((enable-load-extension . #f))
                                (lambda (db) (yes-no (database-extension-loading? db)))))))))

(test-equal "database-extension-loading? checks its argument first, as every reader of the record does: a value that is no database is an assertion violation, naming its kind"
  '((raised (assertion-violation database-extension-loading? (not-a-database 5)))
    (raised (assertion-violation database-extension-loading? (not-a-database (kind string)))))
  (list (attempt (lambda () (database-extension-loading? 5)))
        (attempt (lambda () (database-extension-loading? "db")))))

;; --- refusals, before anything opens -----------------------------------------------------------

;; refusal-cases : (Listof (Pairof (Listof Any) (Listof Any)))
;; Each case's arguments after the filename, and the irritants its refusal
;; names: each of the four's values outside its domain, a name given twice,
;; the opt-in's #f among them, and the list's rules beside the opt-in, which
;; come first wherever it stands.
(define refusal-cases
  (list
   (cons '(((enable-load-extension . 1))) '(setting-out-of-domain enable-load-extension 1))
   (cons '(((defensive . 0))) '(setting-out-of-domain defensive 0))
   (cons '(((dqs-dml . on))) '(setting-out-of-domain dqs-dml on))
   (cons '(((dqs-ddl . "off"))) '(setting-out-of-domain dqs-ddl (kind string)))
   (cons '(((defensive . ()))) '(setting-out-of-domain defensive ()))
   (cons '(((enable-load-extension . #f) (enable-load-extension . #t)))
         '(setting-given-twice enable-load-extension))
   (cons '(((dqs-ddl . #t) (dqs-ddl . #t))) '(setting-given-twice dqs-ddl))
   (cons '(((enable-load-extension . #t) (nosuch . 1))) '(unknown-setting nosuch))
   (cons '(((nosuch . 1) (enable-load-extension . #t))) '(unknown-setting nosuch))
   (cons '(((enable-load-extension . #t) (busy-timeout . -1))) '(setting-out-of-domain busy-timeout -1))
   (cons '(((enable-load-extension . #t)) bogus) '(unknown-option bogus))
   (cons '(((enable-load-extension . #t)) ((defensive . #t))) '(second-settings-list))
   (cons '(((enable-load-extension . #t) 5)) '(not-an-association-list 5))))

;; refusal-run : Symbol String (Listof Any) -> (List Any Any Any)
(define (refusal-run verb path arguments)
  (let* ((r (at-raise (lambda ()
                        (if (eq? verb 'open-database)
                            (apply open-database path arguments)
                            (apply call-with-database path
                                   (append arguments (list (lambda (db) 'proc-ran))))))
                      what-raised))
         (after (native-counts)))
    (list r after (made path))))

(define (refusal-expected verb irritants)
  (list (list (list 'assertion-violation verb irritants) zero-counts) zero-counts 'not-made))

(test-equal "each of the four's values outside its domain, a name given twice, the opt-in's #f among them, and the list's own rules and M2's beside the opt-in, through both verbs, each an assertion violation before anything is allocated: the counts zero at the raise and after, no file made"
  (let loop ((rest refusal-cases) (expected '()))
    (if (null? rest)
        (reverse expected)
        (loop (cdr rest)
              (cons (list (refusal-expected 'open-database (cdr (car rest)))
                          (refusal-expected 'call-with-database (cdr (car rest))))
                    expected))))
  (in-dir (lambda (dir)
            (let ((path (string-append dir "/r.db")))
              (let loop ((rest refusal-cases) (found '()))
                (if (null? rest)
                    (reverse found)
                    (let* ((a (refusal-run 'open-database path (car (car rest))))
                           (b (refusal-run 'call-with-database path (car (car rest)))))
                      (loop (cdr rest) (cons (list a b) found)))))))))

;; other-ops : (Listof Symbol)
;; Every SQLITE_DBCONFIG_ op of the floor's sqlite3.h, 3.45.1's, and of the
;; current lane's, 3.54.1's, but the four, each named by ADR-0021's rule,
;; SQLITE_DBCONFIG_ dropped, lower-cased, _ turned to -: as tests/test-
;; settings.sps lists them, with the headers' sha256s. trusted-schema is
;; ADR-0018's PRAGMA, the one way in to that flag (Q7).
(define other-ops
  '(maindbname lookaside enable-fkey enable-trigger enable-fts3-tokenizer no-ckpt-on-close
    enable-qpsg trigger-eqp reset-database writable-schema legacy-alter-table enable-view
    legacy-file-format trusted-schema stmt-scanstatus reverse-scanorder enable-attach-create
    enable-attach-write enable-comments fp-digits))

(test-equal "every other op of 3.45.1's and 3.54.1's headers, named by ADR-0021's rule, is refused by open-database on :memory: as an unknown setting, before anything is allocated; trusted-schema opens, ADR-0018's PRAGMA: #f, off its start, reads back 0"
  (let loop ((rest other-ops) (expected '()))
    (if (null? rest)
        (reverse expected)
        (loop (cdr rest)
              (cons (if (eq? (car rest) 'trusted-schema)
                        0
                        (list (list (list 'assertion-violation 'open-database
                                          (list 'unknown-setting (car rest)))
                                    zero-counts)
                              zero-counts))
                    expected))))
  (let loop ((rest other-ops) (found '()))
    (if (null? rest)
        (reverse found)
        (loop (cdr rest)
              (cons (if (eq? (car rest) 'trusted-schema)
                        (with-db (lambda () (open-database ":memory:" (list (cons (car rest) #f))))
                                 (lambda (db) (pragma db "trusted_schema")))
                        (let* ((r (at-raise (lambda () (open-database ":memory:" (list (cons (car rest) #t))))
                                            what-raised))
                               (after (native-counts)))
                          (list r after)))
                    found)))))

;; --- the four among the six ---------------------------------------------------------------------

(let ((name "all four among the six PRAGMAs and statement-cache on a file: the open leaves no statement tracked or counted; each PRAGMA reads back as asked, each op too, the cache's capacity the list's, and the record holds the opt-in (rv1, part C)"))
  (unavailable-noted! name)
  (test-equal name
    (opt-in-or-refusal 'open-database
                       (list 0 0 '(1234 1 "truncate" 3 2 0) '((0 1) (0 1) (0 0) (0 0)) 5 'yes))
    (in-dir (lambda (dir)
              (let* ((path (string-append dir "/all.db"))
                     (r (with-db (lambda ()
                                   (open-database path '((trusted-schema . #f) (defensive . #t)
                                                         (journal-mode . truncate) (dqs-dml . #f)
                                                         (busy-timeout . 1234) (statement-cache . 5)
                                                         (enable-load-extension . #t)
                                                         (foreign-keys . #t) (dqs-ddl . #f)
                                                         (synchronous . extra) (temp-store . memory))))
                                 (lambda (db)
                                   (let* ((tracked (length (tracked-statements db)))
                                          (counted (statement-count))
                                          (read (let loop ((rest '("busy_timeout" "foreign_keys" "journal_mode"
                                                                   "synchronous" "temp_store" "trusted_schema"))
                                                           (found '()))
                                                  (if (null? rest)
                                                      (reverse found)
                                                      (loop (cdr rest) (cons (pragma db (car rest)) found)))))
                                          (op-read (op-reads db))
                                          (capacity (database-cache-capacity db))
                                          (opt-in (yes-no (database-extension-loading? db))))
                                     (list tracked counted read op-read capacity opt-in))))))
                r)))))

;; --- depth --------------------------------------------------------------------------------------

;; interrupt-depth : -> Positive-Integer
(define (interrupt-depth)
  (let ((n (disable-interrupts)))
    (enable-interrupts)
    n))

;; handler-depth : (-> Any) -> Any
;; The depth a with-exception-handler handler runs at for the first thing
;; THUNK raises, and what it raised; the handler escapes.
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
        (thunk)
        (list 'no-raise))))))

(define (at-depth-1 what) (list 'raised-at-depth 'depth-1 what))

;; on-fresh : (Integer Integer -> (List Any (U Integer #f))) Symbol -> Any
(define (on-fresh answer who)
  (let-values (((db-config calls) (stand-in answer)))
    (let ((db (open-database ":memory:")))
      (let ((r (handler-depth (lambda () (applied-settings/with who db (list (step-of 'defensive #t))
                                                                db-config)))))
        (close-answer db)
        r))))

(test-equal "each new raise site's with-exception-handler handler runs at interrupt depth 1, after every section, its who the one given: a set's failure, its mismatch, and a code that names no error"
  (list (at-depth-1 '(sqlite-error the-suite error error #f #f))
        (at-depth-1 '(mismatch the-suite defensive #t () library-condition))
        (at-depth-1 '(assertion-violation open-database (not-an-error 100)))
        zero-counts)
  (let* ((a (on-fresh (lambda (op v) (list 1 #f)) 'the-suite))
         (b (on-fresh (lambda (op v) (list 0 #f)) 'the-suite))
         (c (on-fresh (lambda (op v) (list 100 1)) 'open-database)))
    (list a b c (native-counts))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "open-db-config")

(exit (suite-exit-status runner))
