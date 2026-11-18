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
;;;                     setting, (), the six PRAGMAs, the opt-in's #f, or any
;;;                     list of one op, the other three compared (decision 2)
;;;   the opt-in's #f   beside an entry point sqlite3_auto_extension runs at
;;;                     every open, which starts the C switch at 1, as
;;;                     Ubuntu's library does: no call of 0 is made (Q15)
;;;   moved starts      beside an entry point that moves every op off this
;;;                     library's start at every open: no setting, (), and
;;;                     call-with-database keep every moved value; each list
;;;                     of one op reads its own op as asked and leaves the
;;;                     other three moved; so a set that writes a start's
;;;                     value unasked, or a set skipped where the value asked
;;;                     is the start, shows on every library
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
;;;                     them; a set that matched before one that fails made once;
;;;                     the order across PRAGMAs and sets, by a stand-in that
;;;                     reads foreign_keys and trusted_schema at each set
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
              lock-object unlock-object fork-thread make-mutex with-mutex sleep make-time
              get-thread-id)
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
              sqlite-error-offset sqlite-closed? sqlite-wrong-thread?))

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
        ((sqlite-wrong-thread? e) (list 'wrong-thread (who-of e)))
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

;; single-lists : (Listof (Pairof Symbol Boolean))
;; Every list of one op: each of the four at #t and at #f, the opt-in's #t
;; only where the library has sqlite3_load_extension, since it is refused
;; before anything opens where it lacks it.
(define single-lists
  (append (if (eq? available #t) '((enable-load-extension . #t)) '())
          '((enable-load-extension . #f) (defensive . #t) (defensive . #f) (dqs-dml . #t)
            (dqs-dml . #f) (dqs-ddl . #t) (dqs-ddl . #f))))

;; The review's R3 set defensive to 1 beside the opt-in, unasked, and passed
;; when the opt-in's list stood outside this row; so every list of one op is
;; here, each judged by the other three against the library's start.
(test-equal "a list naming one op leaves the other three at the library's start: each of the four at #t and at #f, the opt-in's #t where the library has sqlite3_load_extension, each list's other three compared with the suite's own connection's"
  (let ((s (raw-starts ":memory:")))
    (let loop ((rest single-lists) (expected '()))
      (if (null? rest)
          (reverse expected)
          (loop (cdr rest) (cons (list (car rest) (others-than (car (car rest)) s)) expected)))))
  (let loop ((rest single-lists) (found '()))
    (if (null? rest)
        (reverse found)
        (let ((r (starts-on (lambda () (open-database ":memory:" (list (car rest)))))))
          (loop (cdr rest) (cons (list (car rest) (others-than (car (car rest)) r)) found))))))

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

;; switch-answers : (Listof Any)
;; What each of switch-on's calls answered, newest first: (code cell), or
;; (raised TEXT) where the call raised.
(define switch-answers '())

;; int (*xEntryPoint)(sqlite3 *db, const char **pzErrMsg, const sqlite3_api_routines *pThunk)
;; The new connection's op set to 1, the call's answer and cell noted in
;; switch-answers, a raise noted as (raised TEXT); 0, always.
(define switch-on
  (foreign-callable __collect_safe
    (lambda (db message api)
      (let ((noted (guard (e (#t (list 'raised (describe e))))
                     (call-with-values
                      (lambda ()
                        (call-with-int-cell 'test-open-db-config 9
                          (lambda (c) (sqlite3-db-config db sqlite-dbconfig-enable-load-extension 1 c))))
                      list))))
        (set! switch-answers (cons noted switch-answers))
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

;; all-answered : (Listof Any) Any -> Any
;; every-call-answered when ANSWERS holds one or more and each is EXPECTED;
;; else how many there were and those that are not.
(define (all-answered answers expected)
  (let ((others (filter (lambda (a) (not (equal? a expected))) answers)))
    (if (and (pair? answers) (null? others))
        'every-call-answered
        (list 'answers (length answers) 'unlike others))))

(test-equal "where an entry point every open runs starts enable-load-extension's C switch at 1, as Ubuntu's library does: each of its calls answered 0 with the cell 1; the suite's own connection reads 1, and so do open-database's with no setting and with (enable-load-extension . #f), and call-with-database's with its #f, no call of 0 made; the opt-in's #t reads 1 too; unregistered, an open reads the library's own start again"
  (if (and (pair? switched) (pair? (car switched)) (eq? (car (car switched)) 'refused))
      (list (list 'refused 21) 'not-registered 'no-calls)
      (list (list '(0 1) '(0 1) '(0 1) '(0 1) (if (eq? available #t) '(0 1) 'not-asked))
            'after-as-before 'every-call-answered))
  (begin
    (when (and (pair? switched) (pair? (car switched)) (eq? (car (car switched)) 'refused))
      (display "UNAVAILABLE the opt-in's #f beside a C switch that starts on: this libsqlite3 refused sqlite3_auto_extension (")
      (write (cadr (car switched)))
      (display "), so its refusal, 21, is asserted in its place")
      (newline))
    (append (if (list? switched) switched (list switched))
            (list (if (null? switch-answers) 'no-calls (all-answered switch-answers '(0 1)))))))

;; --- each set and each start, over moved starts --------------------------------------------
;; The start rows above hold each start where nothing moves it, so they
;; cannot see a set that writes the library's own start value: in slice 3's
;; review, defensive set to 0 at every open (R1) and dqs-dml set to 1 (R2)
;; passed every row on Guix's library, and so did defensive's #f skipped and
;; answered as a match (R6), since c-held's #f reads 0 either way. Here an
;; entry point sqlite3_auto_extension runs at every open moves each of the
;; four ops off this library's start, read by raw-starts first, through
;; native's binding, so a value written unasked, or a set not made, shows on
;; any library, whatever its starts: the moved value is 1 less the start's
;; cell. open-database's sets run after the entry point, inside its open. The
;; entry point is __collect_safe, as sqlite3_open_v2, which calls it, is, and
;; raises nothing. Where the library refuses the registration, Apple's 21,
;; each row is printed unavailable, and 21 is asserted in its place, as
;; c-switch-on does. It is unregistered by sqlite3_reset_auto_extension, and
;; unlocked once.

;; start-cells : Any
;; The library's starts, as raw-starts reads them, before any entry point.
(define start-cells (raw-starts ":memory:"))

;; move-to : (U (Listof (Pairof Natural (U 0 1))) #f)
;; Each op and the value the entry point writes it, 1 less its start's
;; cell; #f where a start was not read as code 0 and a cell of 0 or 1.
(define move-to
  (and (list? start-cells) (= (length start-cells) 4)
       (for-all (lambda (r) (and (list? r) (eqv? (car r) 0) (memv (cadr r) '(0 1)))) start-cells)
       (let loop ((rest ops) (cells start-cells) (found '()))
         (if (null? rest)
             (reverse found)
             (loop (cdr rest) (cdr cells) (cons (cons (cdr (car rest)) (- 1 (cadr (car cells)))) found))))))

;; moved-reads : (Listof (List 0 (U 0 1)))
;; What a -1 read of each op answers once the entry point moved it.
(define moved-reads
  (if move-to
      (let loop ((rest move-to) (found '()))
        (if (null? rest) (reverse found) (loop (cdr rest) (cons (list 0 (cdr (car rest))) found))))
      (list 'no-moves start-cells)))

;; move-answers : (Listof Any)
;; What each of move-starts' calls answered, newest first: the four sets'
;; (code cell), in the table's order, or (raised TEXT) where one raised.
(define move-answers '())

;; int (*xEntryPoint)(sqlite3 *db, const char **pzErrMsg, const sqlite3_api_routines *pThunk)
;; Each op of the new connection set to move-to's value, in the table's
;; order, the four answers and cells noted in move-answers, a raise noted
;; as (raised TEXT); 0, always.
(define move-starts
  (foreign-callable __collect_safe
    (lambda (db message api)
      (let ((noted (guard (e (#t (list 'raised (describe e))))
                     (let loop ((rest (or move-to '())) (found '()))
                       (if (null? rest)
                           (reverse found)
                           (loop (cdr rest)
                                 (cons (call-with-values
                                        (lambda ()
                                          (call-with-int-cell 'test-open-db-config 9
                                            (lambda (c) (sqlite3-db-config db (car (car rest))
                                                                           (cdr (car rest)) c))))
                                        list)
                                       found)))))))
        (set! move-answers (cons noted move-answers))
        0))
    (uptr uptr uptr) int))

;; six-pragmas : Settings
;; The six PRAGMAs, each at a value of its domain, and statement-cache.
(define six-pragmas
  '((busy-timeout . 5) (foreign-keys . #t) (journal-mode . truncate) (synchronous . off)
    (temp-store . file) (trusted-schema . #f) (statement-cache . 4)))

;; beside-lists : (Listof (Listof (Pairof Symbol Any)))
;; Each PRAGMA beside each list of one op, the PRAGMA first, then the op:
;; the opt-in's #t and #f beside each PRAGMA among them.
(define beside-lists
  (let loop ((pragmas (filter (lambda (s) (not (eq? (car s) 'statement-cache))) six-pragmas))
             (found '()))
    (if (null? pragmas)
        (reverse found)
        (loop (cdr pragmas)
              (let each ((rest single-lists) (found found))
                (if (null? rest)
                    found
                    (each (cdr rest) (cons (list (car pragmas) (car rest)) found))))))))

;; full-list : Settings
;; The six PRAGMAs, statement-cache and the four, the opt-in only where the
;; library has sqlite3_load_extension, the ops among the PRAGMAs.
(define full-list
  (append '((foreign-keys . #t) (defensive . #f) (journal-mode . truncate) (dqs-dml . #t)
            (busy-timeout . 5) (synchronous . off))
          (if (eq? available #t) '((enable-load-extension . #t)) '())
          '((dqs-ddl . #f) (temp-store . file) (trusted-schema . #f) (statement-cache . 4))))

;; own-read : Symbol Any -> Any
;; NAME's read among READS, the four's in the table's order.
(define (own-read name reads)
  (if (list? reads)
      (let find ((rest-ops ops) (reads reads))
        (cond ((or (null? rest-ops) (not (pair? reads))) 'no-read)
              ((eq? (car (car rest-ops)) name) (car reads))
              (else (find (cdr rest-ops) (cdr reads)))))
      reads))

;; moved-run : -> Any
;; With move-starts registered, read in order: the four on the suite's own
;; connection; on open-database's with no setting and with (), and
;; call-with-database's with none; then, for each list of single-lists,
;; its own op, and the other three; then, each on a file of its own, the
;; four on a connection opened with the six PRAGMAs and statement-cache;
;; for each list of beside-lists, its op's own read and the other three;
;; and the four under full-list. Or (refused CODE).
(define (moved-run)
  (lock-object move-starts)
  (let ((rc (guard (e (#t (list 'raised (describe e))))
              (auto-extension (foreign-callable-entry-point move-starts)))))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (if (not (eqv? rc 0))
            (list 'refused rc)
            (let* ((raw (raw-starts ":memory:"))
                   (none (starts-on (lambda () (open-database ":memory:"))))
                   (empty (starts-on (lambda () (open-database ":memory:" '()))))
                   (cwd (attempt (lambda () (call-with-database ":memory:" op-reads))))
                   (singles
                    (let loop ((rest single-lists) (found '()))
                      (if (null? rest)
                          (reverse found)
                          (let* ((name (car (car rest)))
                                 (r (starts-on (lambda () (open-database ":memory:" (list (car rest))))))
                                 (own (own-read name r)))
                            (loop (cdr rest) (cons (list (car rest) own (others-than name r)) found))))))
                   (files
                    (in-dir
                     (lambda (dir)
                       (let* ((path (lambda (i) (string-append dir "/m" (number->string i) ".db")))
                              (pragmas (starts-on (lambda () (open-database (path 0) six-pragmas))))
                              (beside
                               (let loop ((rest beside-lists) (i 1) (found '()))
                                 (if (null? rest)
                                     (reverse found)
                                     (let* ((name (car (cadr (car rest))))
                                            (r (starts-on (lambda () (open-database (path i) (car rest))))))
                                       (loop (cdr rest) (+ i 1)
                                             (cons (list (car rest) (own-read name r) (others-than name r))
                                                   found))))))
                              (full (starts-on (lambda () (open-database (path 999) full-list)))))
                         (list pragmas beside full))))))
              (list 'moved raw none empty cwd singles files))))
      (lambda ()
        (when (eqv? rc 0) (reset-auto-extension))
        (unlock-object move-starts)))))

(define moved (guard (e (#t (list 'raised (describe e)))) (moved-run)))

;; moves-expected : Any
;; What each op reads once moved, computed apart from move-to, the entry
;; point's own values, from a fresh read of the library's starts: 1 for a
;; start of 0, 0 for a start of 1, in the table's order; (unread STARTS)
;; where a start is no code 0 with a cell of 0 or 1.
(define moves-expected
  (let ((starts (raw-starts ":memory:")))
    (if (and (list? starts) (= (length starts) 4)
             (for-all (lambda (r) (and (list? r) (eqv? (car r) 0) (memv (cadr r) '(0 1)))) starts))
        (let loop ((rest starts) (found '()))
          (if (null? rest)
              (reverse found)
              (loop (cdr rest) (cons (list 0 (if (eqv? (cadr (car rest)) 0) 1 0)) found))))
        (list 'unread starts))))

;; moved-refused? : -> Boolean
(define (moved-refused?)
  (and (pair? moved) (eq? (car moved) 'refused)))

;; moved-part : Natural -> Any
;; The Kth part of moved's reads, or (refused CODE).
(define (moved-part k)
  (if (and (pair? moved) (eq? (car moved) 'moved)) (list-ref moved k) moved))

;; moved-unavailable! : String -> Void
(define (moved-unavailable! name)
  (when (moved-refused?)
    (display "UNAVAILABLE ")
    (display name)
    (display ": this libsqlite3 refused sqlite3_auto_extension (")
    (write (cadr moved))
    (display "), so its refusal, 21, is asserted in its place")
    (newline)))

;; or-refused : Any -> Any
;; EXPECTED, or the refusal 21 where the registration was refused.
(define (or-refused expected)
  (if (moved-refused?) '(refused 21) expected))

;; every-moved : Any Any -> Any
;; every-op-moved when each of MOVED's four cells differs from its STARTS'
;; cell; else the two.
(define (every-moved moved starts)
  (if (and (list? moved) (list? starts) (= (length moved) 4) (= (length starts) 4)
           (for-all (lambda (m s) (and (list? m) (list? s) (= (length m) 2) (= (length s) 2)
                                       (not (equal? (cadr m) (cadr s)))))
                    moved starts))
      'every-op-moved
      (list 'not-moved moved starts)))

(let ((name "an entry point every open runs moves each of the four ops off this library's start: every one of its calls answered 0 with the cell the value written; the suite's own connection, opened outside open-database, reads each op at 1 less its start's cell, computed apart from the entry point's values, and each differs from the start read before it was registered"))
  (moved-unavailable! name)
  (test-equal name
    (or-refused (list moves-expected 'every-op-moved 'every-call-answered))
    (begin
      (display "    moved to, enable-load-extension, defensive, dqs-dml, dqs-ddl: ")
      (write moves-expected)
      (newline)
      (if (moved-refused?)
          moved
          (list (moved-part 1) (every-moved (moved-part 1) (raw-starts ":memory:"))
                (all-answered move-answers moves-expected))))))

(let ((name "over the moved starts, a connection open-database opens with no setting and with (), and one call-with-database opens with none, keep every moved value: no op is set unasked, whatever value it would write"))
  (moved-unavailable! name)
  (test-equal name
    (or-refused (list moves-expected moves-expected moves-expected))
    (if (moved-refused?) moved (list (moved-part 2) (moved-part 3) (moved-part 4)))))

;; asked-read : (Pairof Symbol Boolean) -> Any
;; What a list's own op reads back: the value asked, 1 or 0; for the
;; opt-in's #f, which makes no call, the moved value.
(define (asked-read entry)
  (if (equal? entry '(enable-load-extension . #f))
      (if (and (pair? moves-expected) (pair? (car moves-expected))) (car moves-expected) moves-expected)
      (list 0 (if (cdr entry) 1 0))))

(let ((name "over the moved starts, each list of one op reads its own op back as asked, #t as 1 and #f as 0, so each value is set off its start on one side or the other of these rows and c-held's; the opt-in's #f, which makes no call, keeps the moved value"))
  (moved-unavailable! name)
  (test-equal name
    (or-refused (let loop ((rest single-lists) (expected '()))
                  (if (null? rest)
                      (reverse expected)
                      (loop (cdr rest) (cons (list (car rest) (asked-read (car rest))) expected)))))
    (if (moved-refused?)
        moved
        (let loop ((rest (moved-part 5)) (found '()))
          (if (not (pair? rest))
              (reverse found)
              (loop (cdr rest) (cons (list (car (car rest)) (cadr (car rest))) found)))))))

(let ((name "over the moved starts, each list of one op leaves the other three at their moved values"))
  (moved-unavailable! name)
  (test-equal name
    (or-refused (let loop ((rest single-lists) (expected '()))
                  (if (null? rest)
                      (reverse expected)
                      (loop (cdr rest)
                            (cons (list (car rest) (others-than (car (car rest)) moves-expected)) expected)))))
    (if (moved-refused?)
        moved
        (let loop ((rest (moved-part 5)) (found '()))
          (if (not (pair? rest))
              (reverse found)
              (loop (cdr rest) (cons (list (car (car rest)) (caddr (car rest))) found)))))))

;; full-expected : Any
;; What full-list's connection reads: each op as asked.
(define full-expected
  (append (if (eq? available #t) '((0 1)) '()) '((0 0) (0 1) (0 0))))

;; full-reads : Any -> Any
;; READS without the opt-in's where the library lacks the entry point, so
;; the four's reads line up with full-expected.
(define (full-reads reads)
  (if (and (list? reads) (= (length reads) 4) (not (eq? available #t))) (cdr reads) reads))

(let ((name "over the moved starts, settings beside PRAGMAs, each on a file of its own: the six PRAGMAs and statement-cache leave every op at its moved value; each PRAGMA beside each list of one op, the opt-in's #t and #f among them, reads that op as asked, the opt-in's #f keeping the moved value, and leaves the other three at their moved values; the six, statement-cache and the four together read each op as asked"))
  (moved-unavailable! name)
  (test-equal name
    (or-refused
     (list moves-expected
           (let loop ((rest beside-lists) (expected '()))
             (if (null? rest)
                 (reverse expected)
                 (let ((entry (cadr (car rest))))
                   (loop (cdr rest)
                         (cons (list (car rest) (asked-read entry) (others-than (car entry) moves-expected))
                               expected)))))
           full-expected))
    (if (moved-refused?)
        moved
        (let ((files (moved-part 6)))
          (if (and (list? files) (= (length files) 3))
              (list (car files) (cadr files) (full-reads (caddr files)))
              files)))))

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
   (list 'inexact-one 'open-database (list (step-of 'defensive #t)) (lambda (op v) (list 1.0 #f))
         '(assertion-violation open-database (not-an-error 1.0)))
   (list 'not-a-number 'call-with-database (list (step-of 'dqs-dml #f)) (lambda (op v) (list 'oops #f))
         '(assertion-violation call-with-database (not-an-error oops)))
   (list 'misuse 'the-suite (list (step-of 'enable-load-extension #t)) (lambda (op v) (list 21 #f))
         (list (list 'sqlite-error 'the-suite 'misuse 'misuse #f #f) (errstr 21)))))

(test-equal "a set's failures and mismatches through a stand-in, each closing the connection first, every count 0 at the raise and after, no descriptor left open: an answer of 1 is &sqlite-error error, its message sqlite3_errstr's, no SQL and no offset; 0 with the cell left, the mismatch, actual (); 0 with the other value, the mismatch, #f or #t; 0 with 7, 7; 100, 101 and 256 an assertion violation from the who given, (not-an-error CODE), and so are an inexact 1.0 and a code that is no number; Apple's 21, &sqlite-error misuse; the stand-in called once each"
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

;; --- the order across PRAGMAs and sets (ADR-0018, decision 5) -------------------------------
;; busy-timeout first, then the rest in the list's order, PRAGMAs and the
;; four alike (the M4 plan, section 4.1). Two PRAGMAs set flags that
;; sqlite3_db_config reads too: foreign_keys SQLITE_DBCONFIG_ENABLE_FKEY's,
;; 1002, and trusted_schema SQLITE_DBCONFIG_TRUSTED_SCHEMA's, 1017, as the
;; ops of 3.45.1's and 3.54.1's headers are listed in tests/test-settings.sps.
;; So a stand-in for the binding, at each set, reads both by a -1 read
;; through native's binding on the handle it is given, notes them, and
;; passes the call on: each note shows which of the two PRAGMAs had applied
;; when that set was made. The list's steps are settings-plan's, so the
;; plan's order and the shell's are held together; each PRAGMA is asked off
;; the connection's own start, read first.

(define settings-plan (reach '(chez-sqlite3 private settings) 'settings-plan))

;; fkey-op, trusted-op : Natural
(define fkey-op 1002)
(define trusted-op 1017)

;; cell-of : Natural Natural -> Any
;; OP's cell on the connection whose handle is H, by a -1 read, or the read
;; whole where its code is not 0.
(define (cell-of h op)
  (let ((r (raw-read h op)))
    (if (eqv? (car r) 0) (cadr r) r)))

;; ordered-run : (Integer Integer -> Settings) -> Any
;; On a fresh :memory: connection, the two flags' starts read, then the list
;; LIST-OF gives for the values off them applied by applied-settings/with,
;; its steps settings-plan's, through a stand-in that notes, at each set,
;; its op, the value written and the two flags' cells, then calls native's
;; binding. Answers the starts, what the apply did, and the notes, in order.
(define (ordered-run list-of)
  (with-db (lambda () (open-database ":memory:"))
    (lambda (db)
      (let* ((starts (call-with-open-handle 'test-open-db-config db
                       (lambda (h) (list (cell-of h fkey-op) (cell-of h trusted-op)))))
             (fk (if (eqv? (car starts) 0) #t #f))
             (ts (if (eqv? (cadr starts) 0) #t #f))
             (plan (settings-plan (list-of fk ts)))
             (notes '())
             (through (lambda (h op v cell)
                        (set! notes (cons (list op v (cell-of h fkey-op) (cell-of h trusted-op)) notes))
                        (sqlite3-db-config h op v cell)))
             (r (attempt (lambda () (applied-settings/with 'the-suite db (caddr plan) through) 'applied))))
        (list starts r (reverse notes))))))

;; flag-starts : Any
;; The two flags' starts on a fresh connection, read apart from any run.
(define flag-starts
  (with-db (lambda () (open-database ":memory:"))
    (lambda (db)
      (call-with-open-handle 'test-open-db-config db
        (lambda (h) (list (cell-of h fkey-op) (cell-of h trusted-op)))))))

;; ordered-expected : (Listof (List Natural (U 0 1) Boolean Boolean)) -> Any
;; What ordered-run answers, given each set's op, value written, and whether
;; foreign_keys and trusted_schema had applied by then: an applied flag
;; reads the value asked, 1 less its start; an unapplied one its start.
(define (ordered-expected sets)
  (if (not (and (list? flag-starts) (= (length flag-starts) 2)
                (memv (car flag-starts) '(0 1)) (memv (cadr flag-starts) '(0 1))))
      (list 'unread-starts flag-starts)
      (list flag-starts 'applied
            (let loop ((rest sets) (found '()))
              (if (null? rest)
                  (reverse found)
                  (let ((s (car rest)))
                    (loop (cdr rest)
                          (cons (list (car s) (cadr s)
                                      (if (caddr s) (- 1 (car flag-starts)) (car flag-starts))
                                      (if (cadddr s) (- 1 (cadr flag-starts)) (cadr flag-starts)))
                                found))))))))

(define ordered-a
  (lambda (fk ts)
    (list (cons 'foreign-keys fk) (cons 'defensive #t) (cons 'trusted-schema ts) (cons 'dqs-dml #f)
          (cons 'busy-timeout 7) (cons 'dqs-ddl #f))))

(define ordered-b
  (lambda (fk ts)
    (list (cons 'defensive #t) (cons 'foreign-keys fk) (cons 'dqs-dml #f) (cons 'trusted-schema ts)
          (cons 'dqs-ddl #t))))

(test-equal "the order across PRAGMAs and sets is the list's, busy-timeout first: through a stand-in that notes, at each set, whether foreign_keys and trusted_schema had applied, read by their own ops through native, foreign-keys, defensive, trusted-schema, dqs-dml, busy-timeout and dqs-ddl make defensive's set after foreign-keys and before trusted-schema, the DQS sets after both; and defensive, foreign-keys, dqs-dml, trusted-schema, dqs-ddl make defensive's before both, dqs-dml's between, dqs-ddl's after"
  (list (ordered-expected (list (list sqlite-dbconfig-defensive 1 #t #f)
                                (list sqlite-dbconfig-dqs-dml 0 #t #t)
                                (list sqlite-dbconfig-dqs-ddl 0 #t #t)))
        (ordered-expected (list (list sqlite-dbconfig-defensive 1 #f #f)
                                (list sqlite-dbconfig-dqs-dml 0 #t #f)
                                (list sqlite-dbconfig-dqs-ddl 1 #t #t))))
  (let* ((a (ordered-run ordered-a))
         (b (ordered-run ordered-b)))
    (list a b)))

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

;; wait-until : (-> Any) Natural -> (U 'satisfied 'iterations-exhausted)
;; DONE? asked every 10 ms, at most STEPS times.
(define (wait-until done? steps)
  (run-until (lambda () (sleep (make-time 'time-duration 10000000 0))) done? steps))

;; in-thread : (-> Any) -> Any
;; THUNK's answer on a forked thread, (answer VALUE), whatever it raised
;; being its answer; the-thread-hung when it gives none within 120 s.
(define (in-thread thunk)
  (let ((m (make-mutex)) (answer #f))
    (fork-thread
     (lambda ()
       (let ((a (guard (e (#t (list 'answer (list 'raised (what-raised e)))))
                  (list 'answer (thunk)))))
         (with-mutex m (set! answer a)))))
    (if (eq? (wait-until (lambda () (with-mutex m answer)) 12000) 'satisfied)
        (with-mutex m answer)
        'the-thread-hung)))

(let ((name "database-extension-loading? makes the owner check too: called from another thread, on a connection that opted in and on one that did not, it raises &sqlite-wrong-thread, naming itself; on the owner's thread it answers"))
  (unavailable-noted! name)
  (test-equal name
    (list (opt-in-or-refusal 'open-database
                             '((answer (raised (wrong-thread database-extension-loading?))) yes))
          '((answer (raised (wrong-thread database-extension-loading?))) no))
    (list (with-db (lambda () (open-database ":memory:" '((enable-load-extension . #t))))
                   (lambda (db)
                     (let* ((other (in-thread (lambda () (yes-no (database-extension-loading? db)))))
                            (own (yes-no (database-extension-loading? db))))
                       (list other own))))
          (with-db (lambda () (open-database ":memory:"))
                   (lambda (db)
                     (let* ((other (in-thread (lambda () (yes-no (database-extension-loading? db)))))
                            (own (yes-no (database-extension-loading? db))))
                       (list other own)))))))

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
