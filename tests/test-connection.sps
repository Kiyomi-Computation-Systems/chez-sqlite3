#!r6rs
;;; The suite for connections through (chez-sqlite3): open-database,
;;; close-database!, call-with-database and database? (ADR-0010, ADR-0012,
;;; ADR-0013), and (chez-sqlite3 private connection)'s call-with-open-handle,
;;; the one way to a connection's handle.
;;;
;;;   the flags      each option row against what SQLite got, read back by
;;;                  behaviour through bindings made here, never in src/:
;;;                  sqlite3_db_readonly, sqlite3_db_mutex NULL or not, a file
;;;                  that is or is not created, a symlink refused, and
;;;                  EXRESCODE through sqlite3_exec of a comparison under a
;;;                  missing collation: 257 with it, 1 without, on any
;;;                  connection, a read-only one too (measured on 3.53.1).
;;;                  On a THREADSAFE=1 library, as Guix's and Ubuntu's are,
;;;                  sqlite3_db_mutex is non-NULL with FULLMUTEX and with no
;;;                  mutex flag at all, so the default row tells FULLMUTEX
;;;                  from NOMUTEX here, and from no flag only on Apple's
;;;                  THREADSAFE=2 library (ADR-0010);
;;;                  tests/test-open-options.sps holds the bit itself
;;;   refusals       before anything opens or is allocated: an option, a
;;;                  filename that is no string, a file: name without 'uri,
;;;                  U+0000, each asserted by who and irritants, never by
;;;                  message (ADR-0013), with the counts at the
;;;                  raise and no file made. FILE: and ./file: are plain names
;;;   failed opens   CANTOPEN, its handle closed before the raise: the counts
;;;                  at the raise are zero; NOFOLLOW's cantopen-symlink, whose
;;;                  extended code differs from its primary; failure-details
;;;                  with stub readers, for the NULL handle no real open gives
;;;   closing        a second close does nothing; an untracked statement, made
;;;                  here with a raw sqlite3_prepare_v2, is an assertion
;;;                  violation naming the count, and the connection stays open;
;;;                  a backup makes SQLite refuse the close, an &sqlite-error,
;;;                  and the connection stays open
;;;   threads        the wrong thread on close-database! and on
;;;                  call-with-open-handle, from a forked thread, whatever it
;;;                  raises its answer, every wait bounded; the owner is the
;;;                  thread that opened, not the main one. An engine's
;;;                  remainder of call-with-open-handle, and of changes,
;;;                  in-transaction?, step! and prepare-statement, taken at
;;;                  every fuel on the owner's thread and finished on
;;;                  another, open or closed: refused there, from the
;;;                  caller's who, never run there, nor refused as closed;
;;;                  and of close-database!, a statement held: refused
;;;                  there, the connection left open for the owner
;;;   call-with-database
;;;                  return, raise, escape and re-entry, and each with a close
;;;                  that fails, the procedure checked before anything opens
;;;   after the section
;;;                  every raise is made after the critical section that
;;;                  decided it, never inside one: a with-exception-handler
;;;                  handler of it runs with interrupts enabled, at depth 1
;;;                  (disable-interrupts answers 1 outside any section, 2 in
;;;                  one). A guard clause runs after unwinding, so only a
;;;                  handler sees it. A row per site: call-with-open-handle's
;;;                  three refusals and its procedure's raise, which reaches
;;;                  the caller as the same object, raised again;
;;;                  call-with-database's open and its close; open-database's
;;;                  own; and close-database!'s count-down, made a double free
;;;                  by a count-down! this suite makes first
;;;   engines        open-database under an engine, at every fuel from 1 to 60
;;;                  ticks a slice, past the 44 where an expiry once unwound
;;;                  the open's string block and found it freed on resuming
;;;
;;; &sqlite-closed has no public verb but close-database!, which does
;;; nothing on a closed connection (ADR-0012). So it is reached
;;; here through the private call-with-open-handle.
;;;
;;; The loading procedures are reached through eval, under a guard, as
;;; tests/test-native.sps reaches native: a refused library fails the rows by
;;; name. The condition predicates and accessors are imported from
;;; (chez-sqlite3) itself: each is a re-export of (chez-sqlite3 private
;;; conditions), and referencing one loads nothing.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f. Effects run in order, through let* and named
;;; lets; every row that leaves a connection, a statement or a backup open on
;;; purpose undoes it under dynamic-wind (ADR-0005). The shells ln starts reach
;;; no native code.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure fork-thread make-mutex with-mutex sleep make-time
              get-thread-id current-directory disable-interrupts enable-interrupts make-engine)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
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

(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define call-with-database (reach '(chez-sqlite3) 'call-with-database))
(define database? (reach '(chez-sqlite3) 'database?))
(define changes (reach '(chez-sqlite3) 'changes))
(define in-transaction? (reach '(chez-sqlite3) 'in-transaction?))
(define prepare-statement (reach '(chez-sqlite3) 'prepare-statement))
(define step! (reach '(chez-sqlite3) 'step!))
(define query (reach '(chez-sqlite3) 'query))
(define execute-script! (reach '(chez-sqlite3) 'execute-script!))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define failure-details (reach '(chez-sqlite3 private connection) 'failure-details))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-out-pointer (reach '(chez-sqlite3 private native) 'call-with-out-pointer))

;; --- bindings made here, after the load ------------------------------------------------
;; foreign-procedure resolves its entry when it is evaluated, so each is made
;; once the load above has run; one that cannot be made raises when called.

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_db_readonly(sqlite3*, const char *zDbName)
(define db-readonly (bound 'sqlite3_db_readonly (foreign-procedure "sqlite3_db_readonly" (uptr uptr) int)))
;; sqlite3_mutex *sqlite3_db_mutex(sqlite3*)
(define db-mutex (bound 'sqlite3_db_mutex (foreign-procedure "sqlite3_db_mutex" (uptr) uptr)))
;; int sqlite3_exec(sqlite3*, const char *sql, callback, void *, char **errmsg)
(define exec (bound 'sqlite3_exec (foreign-procedure "sqlite3_exec" (uptr uptr uptr uptr uptr) int)))
;; int sqlite3_prepare_v2(sqlite3*, const char *zSql, int nByte, sqlite3_stmt **, const char **pzTail)
(define prepare-v2 (bound 'sqlite3_prepare_v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int)))
;; int sqlite3_finalize(sqlite3_stmt*)
(define finalize (bound 'sqlite3_finalize (foreign-procedure "sqlite3_finalize" (uptr) int)))
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

(define (connections) (cdr (assq 'connection (native-counts))))

;; who-of : Condition -> Any
(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; message-of : Condition -> Symbol
;; Whether E has a message, never its text.
(define (message-of e) (if (message-condition? e) 'message 'no-message))

;; what-raised : Any -> Any
;; A raised object as this suite compares it: a library condition by its type,
;; its who, whether it has a message and its fields; an assertion violation by
;; its who and irritants; anything else as text.
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (if (string? (sqlite-error-message e)) 'string 'not-a-string)
               (if (eq? (sqlite-error-sql e) #f) 'none 'some)
               (if (eq? (sqlite-error-offset e) #f) 'none 'some)
               (if (and (message-condition? e)
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

;; attempt : (-> Any) -> Any
;; THUNK's answer, or (raised WHAT) for what it raised.
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

;; at-raise : (-> Any) -> (List Any Any)
;; What THUNK raised, and the counts at the moment of the raise, read by a
;; handler that runs before any dynamic-wind's after thunk, then raises on.
;; When THUNK raises nothing: (no-raise VALUE), and a database it answered is
;; closed, so a refusal that failed to refuse leaves no connection open for
;; the rows after it to count.
(define raised-tag (list 'raised))

(define (at-raise thunk)
  (let* ((seen 'no-raise)
         (r (guard (e (#t (cons raised-tag e)))
              (with-exception-handler
               (lambda (c) (when (eq? seen 'no-raise) (set! seen (native-counts))) (raise c))
               thunk))))
    (if (and (pair? r) (eq? (car r) raised-tag))
        (list (what-raised (cdr r)) seen)
        (let ((a-database (guard (e (#t #f)) (database? r))))
          (when a-database (guard (e (#t #f)) (close-database! r)))
          (list (list 'no-raise (if a-database 'a-database r)) seen)))))

;; interrupt-depth : -> Positive-Integer
;; How many critical sections this thread is inside, plus one: what
;; disable-interrupts answers, put back at once. 1 outside any section.
(define (interrupt-depth)
  (let ((n (disable-interrupts)))
    (enable-interrupts)
    n))

;; handler-depth : (-> Any) -> (U (List 'raised-at-depth Symbol Any) (List 'no-raise Any))
;; The depth a with-exception-handler handler runs at for the first thing
;; THUNK raises, read before anything else, as depth-N, and what it raised;
;; the handler escapes, so nothing returns into the raise. A symbol, so ids
;; never takes a depth for a thread id. (no-raise VALUE) when THUNK raises
;; nothing, a database it answered closed first.
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
        (let ((r (thunk)))
          (when (guard (e (#t #f)) (database? r)) (guard (e (#t #f)) (close-database! r)))
          (list 'no-raise (if (guard (e (#t #f)) (database? r)) 'a-database r))))))))

;; run-engine : (-> Any) Positive-Integer Positive-Integer -> (U (List Any Natural) (List 'unfinished Natural))
;; THUNK run in an engine of FUEL ticks a slice, resumed each time it expires
;; until it completes: its answer and how many times it expired; or
;; (unfinished CAP) once it has expired CAP times, so a run that never ends
;; fails its row by name.
(define (run-engine thunk fuel cap)
  (let loop ((engine (make-engine thunk)) (expired 0))
    (if (>= expired cap)
        (list 'unfinished cap)
        (engine fuel
                (lambda (left . answers) (list (car answers) expired))
                (lambda (next) (loop next (+ expired 1)))))))

;; in-dir : (String -> Any) -> Any
(define (in-dir proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory proc)))

(define (made path) (if (file-exists? path) 'made 'not-made))

;; with-handle : Any (Positive-Integer -> A) -> A
(define (with-handle db proc) (call-with-open-handle 'test-connection db proc))

;; facts : Database -> (List Symbol Symbol Symbol)
;; What SQLite says of DB: read-only or read-write (sqlite3_db_readonly of
;; main), mutex or no-mutex (sqlite3_db_mutex), and extended or primary (the
;; code sqlite3_exec answers for a comparison under a missing collation).
(define (facts db)
  (with-handle db
    (lambda (h)
      (let* ((ro (call-with-c-string 'test-connection "main" (lambda (m) (db-readonly h m))))
             (mutex (db-mutex h))
             (code (call-with-c-string 'test-connection "SELECT 'a' < 'b' COLLATE no_such_collation"
                     (lambda (sql) (exec h sql 0 0 0)))))
        (list (case ro ((1) 'read-only) ((0) 'read-write) (else (list 'readonly-answered ro)))
              (if (eqv? mutex 0) 'no-mutex 'mutex)
              (case code ((257) 'extended) ((1) 'primary) (else (list 'exec-answered code))))))))

;; opened : String (Listof Any) -> Any
;; FILENAME opened with OPTIONS: (opened DATABASE? FACTS COUNTS-WHILE-OPEN
;; CLOSED COUNTS-AFTER), or (refused WHAT COUNTS-AFTER).
(define (opened filename options)
  (let ((db (guard (e (#t (list 'raised e))) (apply open-database filename options))))
    (if (and (pair? db) (eq? (car db) 'raised))
        (list 'refused (what-raised (cadr db)) (native-counts))
        (let* ((is-database (if (database? db) 'database 'not-a-database))
               (what (attempt (lambda () (facts db))))
               (while (native-counts))
               (closed (attempt (lambda () (close-database! db) 'closed))))
          (list 'opened is-database what while closed (native-counts))))))

;; make-db! : String -> Any
;; Creates the database file at PATH through open-database, empty.
(define (make-db! path)
  (attempt (lambda () (close-database! (open-database path)) 'made)))

(define while-open (counts-with '((connection . 1))))

;; prepare! : Database String -> Positive-Integer
;; A statement of SQL on DB, made here with the raw sqlite3_prepare_v2, so the
;; connection does not track it.
(define (prepare! db sql)
  (with-handle db
    (lambda (h)
      (call-with-c-string 'test-connection sql
        (lambda (text)
          (let-values (((rc statement)
                        (call-with-out-pointer 'test-connection
                          (lambda (slot) (prepare-v2 h text -1 slot 0)))))
            (if (and (eqv? rc 0) (not (eqv? statement 0)))
                statement
                (error 'prepare! "sqlite3_prepare_v2 did not answer a statement" rc))))))))

;; finalize-all! : (Listof Positive-Integer) -> (Listof Integer)
;; sqlite3_finalize of each, in order: their codes.
(define (finalize-all! statements)
  (let loop ((rest statements) (codes '()))
    (if (null? rest)
        (reverse codes)
        (let ((code (finalize (car rest))))
          (loop (cdr rest) (cons code codes))))))

;; undo! : (Listof Positive-Integer) (Listof Any) -> Void
;; What a row left open on purpose, undone however it ends: STATEMENTS
;; finalized, then each of DATABASES closed. Nothing here raises.
(define (undo! statements databases)
  (for-each (lambda (s) (guard (e (#t #f)) (finalize s))) statements)
  (for-each (lambda (db) (guard (e (#t #f)) (close-database! db))) databases))

;; nul-name : String Natural -> String
;; NAME with U+0000 put at index I.
(define (nul-name name i)
  (string-append (substring name 0 i) "\x0;" (substring name i (string-length name))))

(test-begin "connection")

;; --- the load ------------------------------------------------------------------------------------

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-equal "database? holds for an open and a closed database, and for nothing else: a symbol, a string, a number, a hashtable, a list holding one"
  '(database database not not not not not)
  (attempt
   (lambda ()
     (let* ((db (open-database ":memory:"))
            (open (if (database? db) 'database 'not))
            (closed (begin (close-database! db) (if (database? db) 'database 'not))))
       (append (list open closed)
               (map (lambda (x) (if (database? x) 'database 'not))
                    (list 'x "db" 42 (make-eq-hashtable) (list db))))))))

;; --- what SQLite got, option by option ---------------------------------------------------------

(test-equal "no option: the file is created, read-write, with a mutex and extended codes; one connection and no block while open, none after"
  (list (list 'opened 'database '(read-write mutex extended) while-open 'closed zero-counts) 'made)
  (in-dir (lambda (dir)
            (let* ((path (string-append dir "/a.db"))
                   (r (opened path '())))
              (list r (made path))))))

(test-equal "'create: as no option"
  (list (list 'opened 'database '(read-write mutex extended) while-open 'closed zero-counts) 'made)
  (in-dir (lambda (dir)
            (let* ((path (string-append dir "/a.db"))
                   (r (opened path '(create))))
              (list r (made path))))))

(test-equal "'read-write on a missing file: CANTOPEN, and no file is made; on an existing one: read-write"
  (list (list 'refused (list 'sqlite-error 'open-database 'cantopen 'cantopen 'string 'none 'none
                             'message-is-the-field)
              zero-counts)
        'not-made
        'made
        (list 'opened 'database '(read-write mutex extended) while-open 'closed zero-counts))
  (in-dir (lambda (dir)
            (let* ((missing (string-append dir "/missing.db"))
                   (r (opened missing '(read-write)))
                   (after (made missing))
                   (existing (string-append dir "/e.db"))
                   (setup (make-db! existing))
                   (s (opened existing '(read-write))))
              (list r after setup s)))))

(test-equal "'read-write 'create, in either order: the file is created, read-write"
  (list (list 'opened 'database '(read-write mutex extended) while-open 'closed zero-counts) 'made
        (list 'opened 'database '(read-write mutex extended) while-open 'closed zero-counts) 'made)
  (in-dir (lambda (dir)
            (let* ((a (string-append dir "/a.db"))
                   (ra (opened a '(read-write create)))
                   (ma (made a))
                   (b (string-append dir "/b.db"))
                   (rb (opened b '(create read-write)))
                   (mb (made b)))
              (list ra ma rb mb)))))

(test-equal "'read-only on a missing file: CANTOPEN, and no file is made; on an existing one: read-only, with a mutex and extended codes"
  (list (list 'refused (list 'sqlite-error 'open-database 'cantopen 'cantopen 'string 'none 'none
                             'message-is-the-field)
              zero-counts)
        'not-made
        'made
        (list 'opened 'database '(read-only mutex extended) while-open 'closed zero-counts))
  (in-dir (lambda (dir)
            (let* ((missing (string-append dir "/missing.db"))
                   (r (opened missing '(read-only)))
                   (after (made missing))
                   (existing (string-append dir "/e.db"))
                   (setup (make-db! existing))
                   (s (opened existing '(read-only))))
              (list r after setup s)))))

(test-equal "'uri: file:DIR/u.db makes DIR/u.db, and file:DIR/e.db?mode=ro opens it read-only"
  (list (list 'opened 'database '(read-write mutex extended) while-open 'closed zero-counts) 'made
        'made
        (list 'opened 'database '(read-only mutex extended) while-open 'closed zero-counts))
  (in-dir (lambda (dir)
            (let* ((u (string-append dir "/u.db"))
                   (r (opened (string-append "file:" u) '(uri)))
                   (mu (made u))
                   (e (string-append dir "/e.db"))
                   (setup (make-db! e))
                   (s (opened (string-append "file:" e "?mode=ro") '(uri))))
              (list r mu setup s)))))

(test-equal "'memory: a database in memory, and no file is made at the name given"
  (list (list 'opened 'database '(read-write mutex extended) while-open 'closed zero-counts) 'not-made)
  (in-dir (lambda (dir)
            (let* ((path (string-append dir "/m.db"))
                   (r (opened path '(memory))))
              (list r (made path))))))

(test-equal "'no-follow on a symbolic link: CANTOPEN, extended cantopen-symlink; the same link without it opens"
  (list 'made '(0 "" "")
        (list 'refused (list 'sqlite-error 'open-database 'cantopen 'cantopen-symlink 'string 'none
                             'none 'message-is-the-field)
              zero-counts)
        (list 'opened 'database '(read-write mutex extended) while-open 'closed zero-counts))
  (in-dir (lambda (dir)
            (let* ((real (string-append dir "/real.db"))
                   (link (string-append dir "/link.db"))
                   (setup (make-db! real))
                   (linked (capture-command (list "ln" "-s" real link)))
                   (r (opened link '(no-follow)))
                   (s (opened link '())))
              (list setup linked r s)))))

(test-equal "'no-mutex: no mutex; 'read-only 'no-mutex: read-only with no mutex"
  (list (list 'opened 'database '(read-write no-mutex extended) while-open 'closed zero-counts)
        'made
        (list 'opened 'database '(read-only no-mutex extended) while-open 'closed zero-counts))
  (in-dir (lambda (dir)
            (let* ((r (opened ":memory:" '(no-mutex)))
                   (e (string-append dir "/e.db"))
                   (setup (make-db! e))
                   (s (opened e '(no-mutex read-only))))
              (list r setup s)))))

(test-equal ":memory:, with every option that applies to it: read-write, extended, and each mutex"
  (list (list 'opened 'database '(read-write mutex extended) while-open 'closed zero-counts)
        (list 'opened 'database '(read-write no-mutex extended) while-open 'closed zero-counts))
  (list (opened ":memory:" '(memory create no-follow))
        (opened ":memory:" '(no-mutex memory read-write create))))

;; --- refused before anything opens -------------------------------------------------------------

;; refused : (-> Any) String -> Any
;; What THUNK raised and the counts at the raise, the counts after, and
;; whether PATH was made.
(define (refused thunk path)
  (let* ((r (at-raise thunk))
         (after (native-counts)))
    (list r after (made path))))

(define (refusal who irritants)
  (list (list (list 'assertion-violation who irritants) zero-counts) zero-counts 'not-made))

(test-equal "an option refused, each by its rule and the option: unknown, a string option by its kind, twice, and a contradiction; before anything is allocated, and no file made"
  (list (refusal 'open-database '(unknown-option foo))
        (refusal 'open-database '(unknown-option (kind string)))
        (refusal 'open-database '(option-given-twice uri))
        (refusal 'open-database '(contradictory-options read-only create))
        (refusal 'open-database '(contradictory-options read-only read-write create)))
  (in-dir (lambda (dir)
            (let* ((path (string-append dir "/a.db"))
                   (a (refused (lambda () (open-database path 'foo)) path))
                   (b (refused (lambda () (open-database path "read-only")) path))
                   (c (refused (lambda () (open-database path 'uri 'no-mutex 'uri)) path))
                   (d (refused (lambda () (open-database path 'create 'read-only)) path))
                   (e (refused (lambda () (open-database path 'read-write 'create 'read-only)) path)))
              (list a b c d e)))))

(test-equal "a filename that is no string is refused by its rule and shown-value: a symbol, a number, a list holding a string by its kind"
  (list (list (list 'assertion-violation 'open-database '(not-a-string x)) zero-counts)
        (list (list 'assertion-violation 'open-database '(not-a-string 42)) zero-counts)
        (list (list 'assertion-violation 'open-database '(not-a-string (kind list))) zero-counts)
        zero-counts)
  (let* ((a (at-raise (lambda () (open-database 'x))))
         (b (at-raise (lambda () (open-database 42))))
         (c (at-raise (lambda () (open-database (list "a.db"))))))
    (list a b c (native-counts))))

;; Guix's 3.53.1 is not built with USE_URI, so there a file: name given
;; without SQLITE_OPEN_URI is a relative path, and the open below would answer
;; CANTOPEN: no directory file: is in the working directory. A USE_URI build
;; would open DIR/x.db. Each differs from the refusal.
(test-equal "a filename that starts file:, given without 'uri, is refused by its rule, naming the name by its kind, with any other option; nothing is made"
  (list (refusal 'open-database '(file-uri-without-uri-option (kind string)))
        (refusal 'open-database '(file-uri-without-uri-option (kind string)))
        (refusal 'open-database '(file-uri-without-uri-option (kind string))))
  (in-dir (lambda (dir)
            (let* ((path (string-append dir "/x.db"))
                   (uri (string-append "file:" path))
                   (a (refused (lambda () (open-database uri)) path))
                   (b (refused (lambda () (open-database (string-append uri "?mode=rwc") 'create 'no-mutex)) path))
                   (c (refused (lambda () (open-database uri 'memory 'read-only)) path)))
              (list a b c)))))

;; A name holding U+0000 is call-with-c-string's refusal, (chez-sqlite3
;; private native)'s, from open-database: its irritants are the name's kind
;; alone, which tells it from the file: refusal's.
(test-equal "a filename holding U+0000, first, in the middle and last, is refused naming its kind, from open-database, before anything is allocated; nothing is made"
  (list (refusal 'open-database '((kind string)))
        (refusal 'open-database '((kind string)))
        (refusal 'open-database '((kind string))))
  (in-dir (lambda (dir)
            (let* ((path (string-append dir "/x.db"))
                   (n (string-length path))
                   (a (refused (lambda () (open-database (nul-name path 0))) path))
                   (b (refused (lambda () (open-database (nul-name path (- n 4)))) path))
                   (c (refused (lambda () (open-database (string-append path "\x0;"))) path)))
              (list a b c)))))

;; SQLite reads a name as a URI only when it starts with the five bytes
;; file:, case-sensitively (measured on 3.53.1). Each name here is a plain
;; file, made where it says.
(test-equal "the complement: FILE:x.db, File:x.db and ./file:y.db, relative, and DIR/file:z.db, absolute, are plain names, each opened and its file made"
  (list (list 'opened 'database '(read-write mutex extended) while-open 'closed zero-counts) 'made
        (list 'opened 'database '(read-write mutex extended) while-open 'closed zero-counts) 'made
        (list 'opened 'database '(read-write mutex extended) while-open 'closed zero-counts) 'made
        (list 'opened 'database '(read-write mutex extended) while-open 'closed zero-counts) 'made)
  (in-dir (lambda (dir)
            (let ((home (current-directory)))
              (dynamic-wind
                (lambda () (current-directory dir))
                (lambda ()
                  (let* ((a (opened "FILE:x.db" '()))
                         (ma (made (string-append dir "/FILE:x.db")))
                         (b (opened "File:x.db" '()))
                         (mb (made (string-append dir "/File:x.db")))
                         (c (opened "./file:y.db" '()))
                         (mc (made (string-append dir "/file:y.db")))
                         (d (opened (string-append dir "/file:z.db") '()))
                         (md (made (string-append dir "/file:z.db"))))
                    (list a ma b mb c mc d md)))
                (lambda () (current-directory home)))))))

;; --- failed opens -----------------------------------------------------------------------------

(test-equal "a file in a missing directory: an &sqlite-error from open-database, cantopen and cantopen as symbols, a message that is the &message, no sql or offset, a chez-sqlite3-error and no assertion violation; its handle closed before the raise, so every count is zero at the raise and after"
  (list (list (list 'sqlite-error 'open-database 'cantopen 'cantopen 'string 'none 'none
                    'message-is-the-field)
              zero-counts)
        '(library-condition not-an-assertion)
        zero-counts)
  (in-dir (lambda (dir)
            (let* ((path (string-append dir "/no-such-directory/x.db"))
                   (r (at-raise (lambda () (open-database path))))
                   (kinds (guard (e (#t (list (if (chez-sqlite3-error? e) 'library-condition 'other)
                                              (if (assertion-violation? e) 'an-assertion 'not-an-assertion))))
                            (close-database! (open-database path))
                            'no-raise)))
              (list r kinds (native-counts))))))

(test-equal "a symbolic link with 'no-follow: cantopen, extended cantopen-symlink, the handle closed before the raise"
  (list 'made '(0 "" "")
        (list (list 'sqlite-error 'open-database 'cantopen 'cantopen-symlink 'string 'none 'none
                    'message-is-the-field)
              zero-counts)
        zero-counts)
  (in-dir (lambda (dir)
            (let* ((real (string-append dir "/real.db"))
                   (link (string-append dir "/link.db"))
                   (setup (make-db! real))
                   (linked (capture-command (list "ln" "-s" real link)))
                   (r (at-raise (lambda () (open-database link 'no-follow)))))
              (list setup linked r (native-counts))))))

(define (stub-raises name) (lambda (x) (error name "a stub this row must not call" x)))

(test-equal "failure-details, with stub readers: no handle takes errstr of the code and calls neither other reader; a handle takes its extended code and its errmsg; an errmsg of NULL takes errstr of the extended code; an errstr of NULL leaves an empty message"
  '((7 "errstr of 7")
    (1550 "errmsg of the handle")
    (1550 "errstr of 1550")
    (7 ""))
  (list (attempt (lambda ()
                   (failure-details 7 0 (stub-raises 'extended) (stub-raises 'errmsg)
                                    (lambda (code) (if (eqv? code 7) "errstr of 7" "wrong code")))))
        (attempt (lambda ()
                   (failure-details 14 4096
                                    (lambda (h) (if (eqv? h 4096) 1550 0))
                                    (lambda (h) (if (eqv? h 4096) "errmsg of the handle" "wrong handle"))
                                    (stub-raises 'errstr))))
        (attempt (lambda ()
                   (failure-details 14 4096
                                    (lambda (h) 1550)
                                    (lambda (h) #f)
                                    (lambda (code) (if (eqv? code 1550) "errstr of 1550" "wrong code")))))
        (attempt (lambda ()
                   (failure-details 7 0 (stub-raises 'extended) (stub-raises 'errmsg)
                                    (lambda (code) #f))))))

;; --- closing ------------------------------------------------------------------------------------

(test-equal "a second close-database! does nothing: no raise, the counts stay zero; call-with-open-handle then raises &sqlite-closed from its who, with a message, and its procedure never runs"
  (list 'closed zero-counts 'closed-again zero-counts
        (list 'raised (list 'closed 'test-connection 'message)) 'proc-not-run)
  (let* ((db (attempt (lambda () (open-database ":memory:"))))
         (a (attempt (lambda () (close-database! db) 'closed)))
         (ca (native-counts))
         (b (attempt (lambda () (close-database! db) 'closed-again)))
         (cb (native-counts))
         (ran 'proc-not-run)
         (c (attempt (lambda () (with-handle db (lambda (h) (set! ran 'proc-ran) h))))))
    (list a ca b cb c ran)))

(test-equal "close-database! refuses what is no database, by its rule and shown-value: a symbol, a number, a string by its kind, a hashtable by its kind"
  '((raised (assertion-violation close-database! (not-a-database x)))
    (raised (assertion-violation close-database! (not-a-database 42)))
    (raised (assertion-violation close-database! (not-a-database (kind string))))
    (raised (assertion-violation close-database! (not-a-database (kind other)))))
  (let* ((a (attempt (lambda () (close-database! 'x))))
         (b (attempt (lambda () (close-database! 42))))
         (c (attempt (lambda () (close-database! "app.db"))))
         (d (attempt (lambda () (close-database! (make-eq-hashtable))))))
    (list a b c d)))

(test-equal "call-with-open-handle refuses what is no database from its who, and never runs its procedure"
  '((raised (assertion-violation test-connection (not-a-database x))) proc-not-run)
  (let* ((ran 'proc-not-run)
         (r (attempt (lambda () (with-handle 'x (lambda (h) (set! ran 'proc-ran) h))))))
    (list r ran)))

(test-equal "call-with-open-handle refuses a procedure that is no procedure, from its who, and a who that is no symbol, from itself, before it looks at the database"
  '((raised (assertion-violation test-connection (not-a-procedure x)))
    (raised (assertion-violation call-with-open-handle (not-a-who (kind string)))))
  (let* ((a (attempt (lambda () (call-with-open-handle 'test-connection 'not-a-database 'x))))
         (b (attempt (lambda () (call-with-open-handle "test-connection" 'not-a-database (lambda (h) h))))))
    (list a b)))

;; untracked : Natural -> Any
;; A connection with N statements made here, untracked: what close-database!
;; raised, the counts and the handle after, the statements' finalize codes,
;; and the close after them.
(define (untracked n)
  (let ((db #f) (statements '()))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let loop ((i 0))
             (when (< i n)
               (set! statements (cons (prepare! db "SELECT 1") statements))
               (loop (+ i 1))))
           (let* ((r (attempt (lambda () (close-database! db) 'closed)))
                  (counts (native-counts))
                  (handle (attempt (lambda () (with-handle db (lambda (h) 'still-open)))))
                  (codes (finalize-all! (reverse statements)))
                  (finalized (begin (set! statements '()) codes))
                  (closed (attempt (lambda () (close-database! db) 'closed))))
             (list r counts handle finalized closed (native-counts))))))
      (lambda () (undo! statements (if db (list db) '()))))))

(test-equal "an untracked statement: close-database! raises an assertion violation naming the count, the connection stays open and counted, and once the statement is finalized it closes"
  (list (list 'raised (list 'assertion-violation 'close-database! '(untracked-statements 1)))
        while-open 'still-open '(0) 'closed zero-counts)
  (untracked 1))

(test-equal "two untracked statements: the count named is 2"
  (list (list 'raised (list 'assertion-violation 'close-database! '(untracked-statements 2)))
        while-open 'still-open '(0 0) 'closed zero-counts)
  (untracked 2))

;; A backup from a connection makes sqlite3_close answer SQLITE_BUSY, with no
;; statement open (measured on 3.53.1): SQLite itself refuses the close.
(test-equal "a connection a backup reads from: sqlite3_close refuses, and close-database! raises an &sqlite-error, busy and busy, the connection staying open and counted; once the backup is finished it closes"
  (list 'backup (list 'raised (list 'sqlite-error 'close-database! 'busy 'busy 'string 'none 'none
                                    'message-is-the-field))
        (counts-with '((connection . 2))) 'still-open 0 'closed 'closed zero-counts)
  (let ((source #f) (target #f) (backup #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! source (open-database ":memory:"))
           (set! target (open-database ":memory:"))
           (set! backup
                 (with-handle target
                   (lambda (t)
                     (with-handle source
                       (lambda (s)
                         (call-with-c-string 'test-connection "main"
                           (lambda (main) (backup-init t main s main))))))))
           (let* ((made-it (if (eqv? backup 0) 'no-backup 'backup))
                  (r (attempt (lambda () (close-database! source) 'closed)))
                  (counts (native-counts))
                  (handle (attempt (lambda () (with-handle source (lambda (h) 'still-open)))))
                  (finished (let ((code (backup-finish backup))) (set! backup #f) code))
                  (a (attempt (lambda () (close-database! source) 'closed)))
                  (b (attempt (lambda () (close-database! target) 'closed))))
             (list made-it r counts handle finished a b (native-counts))))))
      (lambda ()
        (when (and backup (not (eqv? backup 0))) (guard (e (#t #f)) (backup-finish backup)))
        (undo! '() (filter (lambda (x) x) (list source target)))))))

;; --- threads ---------------------------------------------------------------------------------------

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

;; from-another-thread : Database (Database -> Any) -> Any
;; What PROC answered or raised on a forked thread, with the ids named, and
;; whether that thread is another one.
(define (from-another-thread db proc)
  (let* ((main (get-thread-id))
         (a (in-thread (lambda () (attempt (lambda () (proc db)))))))
    (if (and (list? a) (= (length a) 3))
        (list (ids (cadr a) main (caddr a)) (if (eqv? (caddr a) main) 'same-thread 'another-thread))
        a)))

(test-equal "close-database! from another thread raises &sqlite-wrong-thread from close-database!, with a message, the owner the main thread and the caller the other; the connection stays open, and the main thread closes it"
  (list (list (list 'raised (list 'wrong-thread 'close-database! 'message 'main 'the-thread))
              'another-thread)
        while-open 'still-open 'closed zero-counts)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let* ((r (from-another-thread db (lambda (db) (close-database! db) 'closed)))
                  (counts (native-counts))
                  (handle (attempt (lambda () (with-handle db (lambda (h) 'still-open)))))
                  (closed (attempt (lambda () (close-database! db) 'closed))))
             (list r counts handle closed (native-counts))))))
      (lambda () (undo! '() (if db (list db) '()))))))

(test-equal "close-database! from another thread on a closed connection still raises &sqlite-wrong-thread: the thread is checked before the connection is"
  (list (list (list 'raised (list 'wrong-thread 'close-database! 'message 'main 'the-thread))
              'another-thread)
        zero-counts)
  (attempt
   (lambda ()
     (let ((db (open-database ":memory:")))
       (close-database! db)
       (let ((r (from-another-thread db (lambda (db) (close-database! db) 'closed))))
         (list r (native-counts)))))))

(test-equal "call-with-open-handle from another thread raises &sqlite-wrong-thread from its who, and its procedure never runs"
  (list (list (list 'raised (list 'wrong-thread 'test-connection 'message 'main 'the-thread))
              'another-thread)
        'proc-not-run 'closed zero-counts)
  (let ((db #f) (ran 'proc-not-run))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let* ((r (from-another-thread db (lambda (db) (with-handle db (lambda (h) (set! ran 'proc-ran) h)))))
                  (closed (attempt (lambda () (close-database! db) 'closed))))
             (list r ran closed (native-counts))))))
      (lambda () (undo! '() (if db (list db) '()))))))

(test-equal "call-with-open-handle from another thread on a closed connection still raises &sqlite-wrong-thread from its who, not &sqlite-closed: the thread is checked before the connection is, and its procedure never runs"
  (list (list (list 'raised (list 'wrong-thread 'test-connection 'message 'main 'the-thread))
              'another-thread)
        'proc-not-run zero-counts)
  (let ((ran 'proc-not-run))
    (attempt
     (lambda ()
       (let ((db (open-database ":memory:")))
         (close-database! db)
         (let ((r (from-another-thread db (lambda (db) (with-handle db (lambda (h) (set! ran 'proc-ran) h))))))
           (list r ran (native-counts))))))))

;; The owner is the thread that opened, not the main one: a forked thread
;; opens, hands the database over, and closes it once the main thread has
;; tried. Each wait is bounded, and the thread closes its connection however
;; the main one fares.
(test-equal "a connection opened on another thread belongs to it: the main thread's close raises &sqlite-wrong-thread, the owner that thread and the caller the main one; that thread then closes it"
  (list (list 'raised (list 'wrong-thread 'close-database! 'message 'the-thread 'main))
        while-open
        (list 'satisfied 'closed)
        zero-counts)
  (let ((m (make-mutex)) (db #f) (thread-id #f) (go #f) (thread-answer #f) (main (get-thread-id)))
    (fork-thread
     (lambda ()
       (let ((a (guard (e (#t (list 'raised (what-raised e))))
                  (let ((d (open-database ":memory:")))
                    (with-mutex m (set! thread-id (get-thread-id)) (set! db d))
                    (let ((waited (wait-until (lambda () (with-mutex m go)) 12000)))
                      (close-database! d)
                      (list waited 'closed))))))
         (with-mutex m (set! thread-answer (list a))))))
    (let* ((have (wait-until (lambda () (with-mutex m db)) 12000))
           (r (if (eq? have 'satisfied)
                  (attempt (lambda () (close-database! (with-mutex m db)) 'closed))
                  'the-thread-opened-nothing))
           (counts (native-counts))
           (signalled (with-mutex m (set! go #t)))
           (done (wait-until (lambda () (with-mutex m thread-answer)) 12000))
           (answer (if (eq? done 'satisfied) (car (with-mutex m thread-answer)) 'the-thread-hung)))
      (list (ids r main (with-mutex m thread-id)) counts answer (native-counts)))))

;; --- a remainder resumed on another thread --------------------------------------------------------
;; Chez resumes an engine's remainder on whichever thread calls it. So a call
;; can pass its owner check on the owner's thread, expire, and go on on
;; another: a check made before the critical section vouches for nothing
;; there. call-with-open-handle makes it again inside its section, where no
;; expiry falls, and raises &sqlite-wrong-thread after it, from the
;; procedure the caller called. Each sweep runs a
;; call at every fuel from 1 until it completes without expiring, with a
;; fresh connection for every trial, opened on this thread. A remainder is
;; finished on a forked thread, with fuel enough to end, whatever it raises
;; its answer, the wait bounded by in-thread's.

;; finished-elsewhere : Engine -> Any
;; ENGINE run to its end on a forked thread, in slices of 10^8 ticks, at
;; most 100 of them: in-thread's (answer VALUE THREAD-ID), VALUE the
;; engine's answer or (unfinished 100); the-thread-hung past in-thread's
;; bound.
(define (finished-elsewhere engine)
  (in-thread
   (lambda ()
     (let loop ((e engine) (n 0))
       (if (>= n 100)
           '(unfinished 100)
           (e 100000000 (lambda (left . answers) (car answers)) (lambda (next) (loop next (+ n 1)))))))))

;; elsewhere-sweep : (Database -> A) (A -> Any) (Database -> Any) -> (Listof Any)
;; CALL swept. At each fuel from 1: a fresh :memory: connection opened on
;; this thread, SETUP given it there, and CALL given SETUP's answer in an
;; engine of FUEL ticks, what it raises its answer as what-raised shows it.
;; An engine that completes ends the sweep: (FUEL completed ANSWER CLOSE).
;; One that expires has BEFORE given the connection on this thread, then
;; its remainder finished on a forked thread: (FUEL resumed ANSWER ID
;; BEFORE CLOSE), ID that thread's, BEFORE what BEFORE answered or raised,
;; or (FUEL resumed WHAT) when in-thread gave no answer. Each trial's
;; connection is closed on this thread after
;; it, CLOSE what that answered or raised. Past 3000 fuels,
;; (unfinished-sweep 3000) ends it.
(define (elsewhere-sweep setup call before)
  (let loop ((fuel 1) (found '()))
    (if (> fuel 3000)
        (reverse (cons '(unfinished-sweep 3000) found))
        (let* ((db (open-database ":memory:"))
               (given (setup db))
               (engine (make-engine (lambda () (attempt (lambda () (call given))))))
               (run (engine fuel (lambda (left . answers) (list 'completed (car answers)))
                            (lambda (next) (list 'expired next)))))
          (if (eq? (car run) 'completed)
              (let ((closed (attempt (lambda () (close-database! db) 'closed))))
                (reverse (cons (list fuel 'completed (cadr run) closed) found)))
              (let* ((done (attempt (lambda () (before db))))
                     (a (finished-elsewhere (cadr run)))
                     (closed (attempt (lambda () (close-database! db) 'closed))))
                (loop (+ fuel 1)
                      (cons (if (and (list? a) (= (length a) 3))
                                (list fuel 'resumed (cadr a) (caddr a) done closed)
                                (list fuel 'resumed a))
                            found))))))))

;; elsewhere-verdict : (Listof Any) (Integer Integer -> Any) (Listof Any)
;;                     -> (List Any Symbol Symbol (Listof Any))
;; A sweep's TRIALS judged, each by its own answer: the completion's answer
;; and close; whether some resumed trial, its thread another one, was
;; refused as (REFUSAL OWNER CALLER) gives it, OWNER this thread's id and
;; CALLER that thread's, and whether some answered one of ANSWERS, each
;; with its BEFORE done and its close made, so the sweep reached both sides
;; of the call's sections; and every other trial, whole, with the ids
;; written main and the-thread: a refusal of another kind, or a section run
;; on the other thread.
(define (elsewhere-verdict trials refusal answers)
  (let ((main (get-thread-id)))
    (let loop ((rest trials) (refused 0) (answered 0) (others '()) (completion 'never-completed))
      (if (null? rest)
          (list completion (yes-no (> refused 0)) (yes-no (> answered 0)) (reverse others))
          (let* ((t (car rest))
                 (resumed (and (= (length t) 6) (eq? (cadr t) 'resumed)
                               (not (eqv? (cadddr t) main))
                               (equal? (cddddr t) '(done closed)))))
            (cond ((and (= (length t) 4) (eq? (cadr t) 'completed))
                   (loop (cdr rest) refused answered others (cddr t)))
                  ((and resumed (equal? (caddr t) (refusal main (cadddr t))))
                   (loop (cdr rest) (+ refused 1) answered others completion))
                  ((and resumed (member (caddr t) answers))
                   (loop (cdr rest) refused (+ answered 1) others completion))
                  (else
                   (loop (cdr rest) refused answered
                         (cons (if (= (length t) 6) (ids t main (cadddr t)) t) others)
                         completion))))))))

(define (yes-no x) (if x 'yes 'no))

;; refused-from : Symbol -> (Integer Integer -> Any)
;; The wrong thread's refusal from WHO, OWNER and CALLER its fields, as
;; attempt shows it.
(define (refused-from who)
  (lambda (owner caller) (list 'raised (list 'wrong-thread who 'message owner caller))))

;; leave-open, close-first : Database -> Symbol
;; What a sweep does on this thread before the resume, answering done:
;; nothing, or the connection closed.
(define (leave-open db) 'done)
(define (close-first db) (close-database! db) 'done)

;; In 3 of 12 trials of a bare call-with-open-handle, when the owner check
;; came before the section alone, the procedure ran on the other thread.
(test-equal "call-with-open-handle's remainder, taken at every fuel on the owner's thread and finished on another, never runs its procedure there: each is refused with &sqlite-wrong-thread from its who, the owner this thread and the caller that one, or answers what its procedure gave on this thread before the expiry; the sweep reaches both, and every count is zero after"
  (list (list 'ran-on-the-owner 'closed) 'yes 'yes '() zero-counts)
  (attempt
   (lambda ()
     (let* ((main (get-thread-id))
            (trials (elsewhere-sweep (lambda (db) db)
                                     (lambda (db)
                                       (with-handle db
                                         (lambda (h)
                                           (if (eqv? (get-thread-id) main)
                                               'ran-on-the-owner
                                               (list 'ran-on (get-thread-id))))))
                                     leave-open)))
       (append (elsewhere-verdict trials (refused-from 'test-connection) '(ran-on-the-owner))
               (list (native-counts)))))))

(test-equal "call-with-open-handle's remainder finished on another thread once this one has closed the connection: refused with &sqlite-wrong-thread from its who, never &sqlite-closed, since the thread is checked before the connection is, inside the section too; or the answer its procedure gave before the expiry"
  (list (list 'ran-before-the-close 'closed) 'yes 'yes '() zero-counts)
  (attempt
   (lambda ()
     (let ((trials (elsewhere-sweep (lambda (db) db)
                                    (lambda (db) (with-handle db (lambda (h) 'ran-before-the-close)))
                                    close-first)))
       (append (elsewhere-verdict trials (refused-from 'test-connection) '(ran-before-the-close))
               (list (native-counts)))))))

;; The section's refusal is raised after the section, as the first check's
;; is: a with-exception-handler handler of either runs at depth 1 on the
;; other thread.
(test-equal "call-with-open-handle's refusal of a remainder finished on another thread, the connection closed first, is raised after every section: its with-exception-handler handler runs at depth 1 there, at every fuel"
  (list (list '(no-raise ran-before-the-close) 'closed) 'yes 'yes '() zero-counts)
  (attempt
   (lambda ()
     (let ((trials (elsewhere-sweep (lambda (db) db)
                                    (lambda (db)
                                      (handler-depth
                                       (lambda () (with-handle db (lambda (h) 'ran-before-the-close)))))
                                    close-first)))
       (append (elsewhere-verdict trials
                                  (lambda (owner caller)
                                    (list 'raised-at-depth 'depth-1
                                          (list 'wrong-thread 'test-connection 'message owner caller)))
                                  '((no-raise ran-before-the-close)))
               (list (native-counts)))))))

;; Each verb reaches the handle through call-with-open-handle, outside any
;; section of its own, and each refusal names the verb: a counter, a
;; statement verb, and the prepare. The connection is closed on this thread
;; before the remainder goes on, so a section that ran on the other thread
;; would have found it closed, and said so.
(for-each
 (lambda (verb)
   (let ((who (car verb)) (setup (cadr verb)) (call (caddr verb)) (answer (cadddr verb)))
     (test-equal (string-append (symbol->string who) "'s remainder, taken at every fuel on the owner's thread and finished on another once this one has closed the connection: refused with &sqlite-wrong-thread from " (symbol->string who) ", the owner this thread and the caller that one, never &sqlite-closed; or its answer, when its section ran before the expiry; the sweep reaches both, and every count is zero after")
       (list (list answer 'closed) 'yes 'yes '() zero-counts)
       (attempt
        (lambda ()
          (let ((trials (elsewhere-sweep setup call close-first)))
            (append (elsewhere-verdict trials (refused-from who) (list answer))
                    (list (native-counts)))))))))
 (list (list 'changes (lambda (db) db) (lambda (db) (list 'changed (changes db))) '(changed 0))
       (list 'in-transaction? (lambda (db) db) (lambda (db) (if (in-transaction? db) 'in 'out)) 'out)
       (list 'step! (lambda (db) (prepare-statement db "select 1")) step! #t)
       (list 'prepare-statement (lambda (db) db)
             (lambda (db) (and (prepare-statement db "select 1") 'prepared)) 'prepared)))

;; close-database! reaches the handle through its own section, the latch's,
;; where it finalizes and closes. A remainder of it finished on another
;; thread is refused there, the connection left open for this thread to
;; close. So the sweep's BEFORE reads, on this thread, whether the
;; connection is still open: a close made on the other thread shows as a
;; connection open before the resume and an answer after it. A statement
;; held at a row gives the close a finalize to make. When the owner check
;; came before the section alone, fuels 9 and 10 closed the connection on
;; the other thread.

;; open-or-closed : Database -> Any
;; Whether DB is open, read on this thread: open, closed, or what else the
;; read raised.
(define (open-or-closed db)
  (let ((r (attempt (lambda () (with-handle db (lambda (h) 'open))))))
    (if (equal? r '(raised (closed test-connection message))) 'closed r)))

;; close-verdict : (Listof Any) (Integer Integer -> Any) Any
;;                 -> (List Any Symbol Symbol (Listof Any))
;; elsewhere-verdict's judgment of close-database!'s sweep: refused as
;; (REFUSAL OWNER CALLER) gives it, the connection open before the resume;
;; or ANSWER, the close's, the connection closed before the resume, on
;; this thread; each closed by this thread's close after; and every other
;; trial, whole.
(define (close-verdict trials refusal answer)
  (let ((main (get-thread-id)))
    (let loop ((rest trials) (refused 0) (answered 0) (others '()) (completion 'never-completed))
      (if (null? rest)
          (list completion (yes-no (> refused 0)) (yes-no (> answered 0)) (reverse others))
          (let* ((t (car rest))
                 (resumed (and (= (length t) 6) (eq? (cadr t) 'resumed)
                               (not (eqv? (cadddr t) main))
                               (equal? (list-ref t 5) 'closed))))
            (cond ((and (= (length t) 4) (eq? (cadr t) 'completed))
                   (loop (cdr rest) refused answered others (cddr t)))
                  ((and resumed (eq? (list-ref t 4) 'open)
                        (equal? (caddr t) (refusal main (cadddr t))))
                   (loop (cdr rest) (+ refused 1) answered others completion))
                  ((and resumed (eq? (list-ref t 4) 'closed) (equal? (caddr t) answer))
                   (loop (cdr rest) refused (+ answered 1) others completion))
                  (else
                   (loop (cdr rest) refused answered
                         (cons (if (= (length t) 6) (ids t main (cadddr t)) t) others)
                         completion))))))))

;; The latch's section is the close's last, and at this trip no tick falls
;; after it, so the row asks for no trial past it, and allows one.
(test-equal "close-database!'s remainder, a statement of the connection held at a row, taken at every fuel on the owner's thread and finished on another: refused there with &sqlite-wrong-thread from close-database!, the owner this thread and the caller that one, the connection open before the resume and closed by this thread after, never a close made there; the call that completes closes; and every count is zero after"
  (list (list 'closed-it 'closed) 'yes '() zero-counts)
  (attempt
   (lambda ()
     (let* ((trials (elsewhere-sweep (lambda (db) (let ((st (prepare-statement db "select 1"))) (step! st) db))
                                     (lambda (db) (close-database! db) 'closed-it)
                                     open-or-closed))
            (v (close-verdict trials (refused-from 'close-database!) 'closed-it)))
       (list (car v) (cadr v) (cadddr v) (native-counts))))))

(test-equal "close-database!'s refusal of a remainder finished on another thread, a statement held at a row, is raised after every section: its with-exception-handler handler runs at depth 1 there, at every fuel"
  (list (list '(no-raise closed-it) 'closed) 'yes '() zero-counts)
  (attempt
   (lambda ()
     (let* ((trials (elsewhere-sweep (lambda (db) (let ((st (prepare-statement db "select 1"))) (step! st) db))
                                     (lambda (db) (handler-depth (lambda () (close-database! db) 'closed-it)))
                                     open-or-closed))
            (v (close-verdict trials
                              (lambda (owner caller)
                                (list 'raised-at-depth 'depth-1
                                      (list 'wrong-thread 'close-database! 'message owner caller)))
                              '(no-raise closed-it))))
       (list (car v) (cadr v) (cadddr v) (native-counts))))))

;; --- call-with-database -------------------------------------------------------------------------

;; A raised object no other row raises.
(define boom (list 'boom))

(test-equal "call-with-database: the procedure's two values come back; inside, the connection is open and counted; after, it is closed, and every count is zero"
  (list '(first second) (list 'database 'still-open while-open)
        (list 'raised (list 'closed 'test-connection 'message)) zero-counts)
  (let* ((kept #f) (inside #f)
         (r (attempt (lambda ()
                       (call-with-values
                        (lambda ()
                          (call-with-database ":memory:"
                            (lambda (db)
                              (set! kept db)
                              (set! inside (list (if (database? db) 'database 'not)
                                                 (attempt (lambda () (with-handle db (lambda (h) 'still-open))))
                                                 (native-counts)))
                              (values 'first 'second))))
                        list))))
         (after (attempt (lambda () (with-handle kept (lambda (h) 'still-open))))))
    (list r inside after (native-counts))))

(test-equal "call-with-database: the procedure's raise reaches the caller unchanged, and the connection is closed"
  (list 'caught-the-procedures-raise (list 'raised (list 'closed 'test-connection 'message)) zero-counts)
  (let* ((kept #f)
         (r (guard (e ((eq? e boom) 'caught-the-procedures-raise)
                      (#t (list 'other (what-raised e))))
              (call-with-database ":memory:" (lambda (db) (set! kept db) (raise boom)))
              'no-raise))
         (after (attempt (lambda () (with-handle kept (lambda (h) 'still-open))))))
    (list r after (native-counts))))

(test-equal "call-with-database: a warning the procedure raises with raise-continuable reaches an outer handler that returns, and the procedure goes on with the value it returned; the connection is then closed, and every count is zero"
  (list '(proc-saw handled) 'handler-ran-on-a-warning (list 'raised (list 'closed 'test-connection 'message))
        zero-counts)
  (let* ((kept #f) (ran 'handler-not-run)
         (r (attempt
             (lambda ()
               (with-exception-handler
                (lambda (c)
                  (set! ran (if (warning? c) 'handler-ran-on-a-warning 'handler-ran-on-another))
                  'handled)
                (lambda ()
                  (call-with-database ":memory:"
                    (lambda (db)
                      (set! kept db)
                      (list 'proc-saw (raise-continuable (make-warning))))))))))
         (after (attempt (lambda () (with-handle kept (lambda (h) 'still-open))))))
    (list r ran after (native-counts))))

;; with-failing-close : ((Database -> Any) -> Any) -> Any
;; RUN given a procedure that makes an untracked statement on its database,
;; so its close fails: what RUN answered, the counts and the handle after,
;; then the statement finalized and the connection closed, however RUN ends.
(define (with-failing-close run)
  (let ((kept #f) (statement #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let* ((r (run (lambda (db)
                         (set! kept db)
                         (set! statement (prepare! db "SELECT 1")))))
               (counts (native-counts))
               (handle (if kept
                           (attempt (lambda () (with-handle kept (lambda (h) 'still-open))))
                           'no-database))
               (finalized (if statement (let ((code (finalize statement))) (set! statement #f) code) 'none))
               (closed (if kept (attempt (lambda () (close-database! kept) 'closed)) 'no-database)))
          (list r counts handle finalized closed (native-counts))))
      (lambda () (undo! (if statement (list statement) '()) (if kept (list kept) '()))))))

(test-equal "call-with-database: a raise, then a close that fails: the caller gets the procedure's raise, not the close's; the connection stays open and counted"
  (list 'caught-the-procedures-raise while-open 'still-open 0 'closed zero-counts)
  (with-failing-close
   (lambda (spoil!)
     (guard (e ((eq? e boom) 'caught-the-procedures-raise)
               (#t (list 'other (what-raised e))))
       (call-with-database ":memory:" (lambda (db) (spoil! db) (raise boom)))
       'no-raise))))

;; A guard that matches no clause re-enters the extent to raise again, and the
;; after thunk runs twice: both closes fail, and both are contained.
(test-equal "call-with-database: the same under an inner guard that does not match: the outer guard gets the procedure's raise"
  (list 'outer-caught-the-procedures-raise while-open 'still-open 0 'closed zero-counts)
  (with-failing-close
   (lambda (spoil!)
     (guard (e ((eq? e boom) 'outer-caught-the-procedures-raise)
               (#t (list 'other (what-raised e))))
       (guard (e ((string? e) 'inner-matched))
         (call-with-database ":memory:" (lambda (db) (spoil! db) (raise boom))))
       'no-raise))))

(test-equal "call-with-database: a return, then a close that fails: the close's assertion violation reaches the caller, from call-with-database; the connection stays open"
  (list (list 'raised (list 'assertion-violation 'call-with-database '(untracked-statements 1)))
        while-open 'still-open 0 'closed zero-counts)
  (with-failing-close
   (lambda (spoil!)
     (attempt (lambda ()
                (call-with-database ":memory:" (lambda (db) (spoil! db) 'returned)))))))

(test-equal "call-with-database: an escape through a continuation closes the connection"
  (list 'escaped (list 'raised (list 'closed 'test-connection 'message)) zero-counts)
  (let* ((kept #f)
         (r (attempt (lambda ()
                       (call/cc
                        (lambda (k)
                          (call-with-database ":memory:" (lambda (db) (set! kept db) (k 'escaped))))))))
         (after (attempt (lambda () (with-handle kept (lambda (h) 'still-open))))))
    (list r after (native-counts))))

(test-equal "call-with-database: an escape, then a close that fails: the close's assertion violation is raised"
  (list (list 'raised (list 'assertion-violation 'call-with-database '(untracked-statements 1)))
        while-open 'still-open 0 'closed zero-counts)
  (with-failing-close
   (lambda (spoil!)
     (attempt (lambda ()
                (call/cc
                 (lambda (k)
                   (call-with-database ":memory:" (lambda (db) (spoil! db) (k 'escaped))))))))))

(test-equal "call-with-database: a continuation that re-enters the procedure finds the connection closed, and no connection is opened again"
  (list 2 (list (list 1 'still-open 1) (list 2 (list 'raised (list 'closed 'test-connection 'message)) 0))
        zero-counts)
  (let ((k #f) (runs 0) (seen '()))
    (let ((r (attempt
              (lambda ()
                (call-with-database ":memory:"
                  (lambda (db)
                    (call/cc (lambda (c) (set! k c)))
                    (set! runs (+ runs 1))
                    (set! seen (cons (list runs
                                           (attempt (lambda () (with-handle db (lambda (h) 'still-open))))
                                           (connections))
                                     seen))
                    runs))))))
      (if (= runs 1)
          (k #f)
          (list r (reverse seen) (native-counts))))))

(test-equal "call-with-database checks its procedure first, then all open-database checks, before anything opens: no procedure, a last argument that is no procedure, before a filename that is no string, an option, file:, U+0000; the procedure never runs, nothing is made"
  (list (refusal 'call-with-database '(no-procedure))
        (refusal 'call-with-database '(not-a-procedure read-only))
        (refusal 'call-with-database '(not-a-procedure (kind string)))
        (refusal 'call-with-database '(not-a-string x))
        (refusal 'call-with-database '(unknown-option foo))
        (refusal 'call-with-database '(file-uri-without-uri-option (kind string)))
        (refusal 'call-with-database '((kind string)))
        'proc-not-run)
  (in-dir (lambda (dir)
            (let* ((ran 'proc-not-run)
                   (proc (lambda (db) (set! ran 'proc-ran) 'ran))
                   (path (string-append dir "/a.db"))
                   (a (refused (lambda () (call-with-database path)) path))
                   (b (refused (lambda () (call-with-database path 'read-only)) path))
                   (c (refused (lambda () (call-with-database 'x "not-a-procedure")) path))
                   (d (refused (lambda () (call-with-database 'x proc)) path))
                   (e (refused (lambda () (call-with-database path 'foo proc)) path))
                   (f (refused (lambda () (call-with-database (string-append "file:" path) proc)) path))
                   (g (refused (lambda () (call-with-database (nul-name path 1) proc)) path)))
              (list a b c d e f g ran)))))

(test-equal "call-with-database passes its options to the open: 'read-only on an existing file is read-only inside, and 'no-mutex has no mutex"
  (list 'made '(read-only mutex extended) '(read-write no-mutex extended) zero-counts)
  (in-dir (lambda (dir)
            (let* ((path (string-append dir "/e.db"))
                   (setup (make-db! path))
                   (a (attempt (lambda () (call-with-database path 'read-only facts))))
                   (b (attempt (lambda () (call-with-database ":memory:" 'no-mutex facts)))))
              (list setup a b (native-counts))))))

(test-equal "call-with-database: a failed open raises its &sqlite-error from call-with-database, and the procedure never runs"
  (list (list (list 'sqlite-error 'call-with-database 'cantopen 'cantopen 'string 'none 'none
                    'message-is-the-field)
              zero-counts)
        'proc-not-run zero-counts)
  (in-dir (lambda (dir)
            (let* ((ran 'proc-not-run)
                   (r (at-raise (lambda ()
                                  (call-with-database (string-append dir "/no-such-directory/x.db")
                                    (lambda (db) (set! ran 'proc-ran)))))))
              (list r ran (native-counts))))))

(test-equal "call-with-database: a procedure that closes its connection itself returns, and nothing is left"
  (list 'closed-inside zero-counts)
  (let ((r (attempt (lambda ()
                      (call-with-database ":memory:" (lambda (db) (close-database! db) 'closed-inside))))))
    (list r (native-counts))))

;; --- raised after the section -------------------------------------------------------------------
;; A raise made inside a critical section reaches a with-exception-handler
;; handler with interrupts still disabled: there an engine never expires,
;; and another thread's collection waits for the handler to end (measured).
;; So every raise follows the section that decided it.
;; Each row's handler reads its depth, written depth-N so no thread id is
;; taken for it, and what was raised: depth-1, and the site's own refusal.

(test-equal "call-with-open-handle refuses what is no database, and a closed connection, after its critical section: a handler of either runs at depth 1, and the procedure never runs"
  (list (list 'raised-at-depth 'depth-1 (list 'assertion-violation 'test-connection '(not-a-database x)))
        (list 'raised-at-depth 'depth-1 (list 'closed 'test-connection 'message))
        'proc-not-run zero-counts)
  (let* ((ran 'proc-not-run)
         (a (handler-depth (lambda () (with-handle 'x (lambda (h) (set! ran 'proc-ran) h)))))
         (closed (attempt (lambda () (let ((db (open-database ":memory:"))) (close-database! db) db))))
         (b (handler-depth (lambda () (with-handle closed (lambda (h) (set! ran 'proc-ran) h))))))
    (list a b ran (native-counts))))

(test-equal "call-with-open-handle refuses another thread after its critical section: that thread's handler runs at depth 1, and the procedure never runs"
  (list (list (list 'raised-at-depth 'depth-1
                    (list 'wrong-thread 'test-connection 'message 'main 'the-thread))
              'another-thread)
        'proc-not-run 'closed zero-counts)
  (let ((db #f) (ran 'proc-not-run))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let* ((r (from-another-thread
                      db (lambda (db)
                           (handler-depth (lambda () (with-handle db (lambda (h) (set! ran 'proc-ran) h)))))))
                  (closed (attempt (lambda () (close-database! db) 'closed))))
             (list r ran closed (native-counts))))))
      (lambda () (undo! '() (if db (list db) '()))))))

;; A condition no other row raises, with a who and irritants of its own.
(define from-proc
  (condition (make-assertion-violation) (make-who-condition 'test-proc)
             (make-message-condition "a raise this suite plants in a procedure")
             (make-irritants-condition '(planted))))

(test-equal "call-with-open-handle raises its procedure's raise again after its critical section: a handler of it runs at depth 1, and a guard gets that very object"
  (list (list 'raised-at-depth 'depth-1 (list 'assertion-violation 'test-proc '(planted)))
        'the-same-object 'closed zero-counts)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let* ((a (handler-depth (lambda () (with-handle db (lambda (h) (raise from-proc))))))
                  (b (guard (e ((eq? e from-proc) 'the-same-object)
                               (#t (list 'another (what-raised e))))
                       (with-handle db (lambda (h) (raise from-proc)))
                       'no-raise))
                  (closed (attempt (lambda () (close-database! db) 'closed))))
             (list a b closed (native-counts))))))
      (lambda () (undo! '() (if db (list db) '()))))))

;; A raise that is no condition (the guard in call-with-open-handle takes
;; every object): a fresh symbol and a fresh pair, each a depth-1 handler's
;; object and a guard's very object, never wrapped, and never a condition.
(define (non-condition-raised-again make-object)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let* ((object (make-object))
                  (seen 'handler-not-run)
                  (depth 'handler-not-run)
                  (a (call/cc
                      (lambda (k)
                        (with-exception-handler
                         (lambda (c)
                           (set! depth (string->symbol (string-append "depth-" (number->string (interrupt-depth)))))
                           (set! seen (if (eq? c object) 'the-same-object (list 'another (what-raised c))))
                           (k 'escaped))
                         (lambda () (with-handle db (lambda (h) (raise object))))))))
                  (b (guard (e ((eq? e object) 'the-same-object)
                               (#t (list 'another (what-raised e))))
                       (with-handle db (lambda (h) (raise object)))
                       'no-raise))
                  (closed (attempt (lambda () (close-database! db) 'closed))))
             (list a depth seen b closed (native-counts))))))
      (lambda () (undo! '() (if db (list db) '()))))))

(test-equal "call-with-open-handle raises its procedure's raise of a fresh symbol again after its critical section: a handler runs at depth 1, and gets, and a guard gets, that very object"
  (list 'escaped 'depth-1 'the-same-object 'the-same-object 'closed zero-counts)
  (non-condition-raised-again (lambda () (string->symbol (string-append "planted-" "symbol")))))

(test-equal "call-with-open-handle raises its procedure's raise of a fresh pair again after its critical section: a handler runs at depth 1, and gets, and a guard gets, that very object"
  (list 'escaped 'depth-1 'the-same-object 'the-same-object 'closed zero-counts)
  (non-condition-raised-again (lambda () (list 'planted 'pair))))

;; The procedure answers data (ADR-0012): what it raises is raised
;; again with raise, so a raise-continuable from it cannot be resumed. A handler that
;; returns from that raise gets the &non-continuable R6RS raises in its place.
(test-equal "call-with-open-handle: a warning its procedure raises with raise-continuable is raised again with raise, after the section; the handler runs once, its return is a &non-continuable, and the procedure does not go on"
  (list 'non-continuable 'handler-ran-on-a-warning 'proc-did-not-go-on 'closed zero-counts)
  (let ((db #f) (ran 'handler-not-run) (went-on 'proc-did-not-go-on))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let* ((r (guard (e ((non-continuable-violation? e) 'non-continuable)
                               (#t (list 'other (what-raised e))))
                       (with-exception-handler
                        (lambda (c)
                          (set! ran (if (eq? ran 'handler-not-run)
                                        (if (warning? c) 'handler-ran-on-a-warning 'handler-ran-on-another)
                                        'handler-ran-twice))
                          'handled)
                        (lambda ()
                          (with-handle db
                            (lambda (h)
                              (let ((answer (raise-continuable (make-warning))))
                                (set! went-on (list 'proc-went-on answer))
                                answer)))))))
                  (closed (attempt (lambda () (close-database! db) 'closed))))
             (list r ran went-on closed (native-counts))))))
      (lambda () (undo! '() (if db (list db) '()))))))

(test-equal "call-with-open-handle answers every value its procedure answers, and gives it the handle, an exact positive integer"
  (list '(first second) 'exact-positive-integer 'closed zero-counts)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let* ((answers (call-with-values (lambda () (with-handle db (lambda (h) (values 'first 'second))))
                             list))
                  (handle (with-handle db (lambda (h)
                                            (if (and (integer? h) (exact? h) (> h 0)) 'exact-positive-integer h))))
                  (closed (attempt (lambda () (close-database! db) 'closed))))
             (list answers handle closed (native-counts))))))
      (lambda () (undo! '() (if db (list db) '()))))))

(test-equal "open-database raises after its critical section: a handler of a failed open, and of U+0000, runs at depth 1"
  (list (list 'raised-at-depth 'depth-1
              (list 'sqlite-error 'open-database 'cantopen 'cantopen 'string 'none 'none
                    'message-is-the-field))
        (list 'raised-at-depth 'depth-1 (list 'assertion-violation 'open-database '((kind string))))
        zero-counts)
  (in-dir (lambda (dir)
            (let* ((a (handler-depth (lambda () (open-database (string-append dir "/no-such-directory/x.db")))))
                   (b (handler-depth (lambda () (open-database (nul-name (string-append dir "/x.db") 1))))))
              (list a b (native-counts))))))

(test-equal "call-with-database's open raises after its critical section: a handler of a failed open, and of U+0000, runs at depth 1, and the procedure never runs"
  (list (list 'raised-at-depth 'depth-1
              (list 'sqlite-error 'call-with-database 'cantopen 'cantopen 'string 'none 'none
                    'message-is-the-field))
        (list 'raised-at-depth 'depth-1 (list 'assertion-violation 'call-with-database '((kind string))))
        'proc-not-run zero-counts)
  (in-dir (lambda (dir)
            (let* ((ran 'proc-not-run)
                   (proc (lambda (db) (set! ran 'proc-ran) 'ran))
                   (a (handler-depth
                       (lambda () (call-with-database (string-append dir "/no-such-directory/x.db") proc))))
                   (b (handler-depth
                       (lambda () (call-with-database (nul-name (string-append dir "/x.db") 1) proc)))))
              (list a b ran (native-counts))))))

(test-equal "call-with-database raises its close's failure after the critical after thunk, on a return and on an escape: a handler of it runs at depth 1; the connection stays open"
  (list (list (list 'raised-at-depth 'depth-1
                    (list 'assertion-violation 'call-with-database '(untracked-statements 1)))
              while-open 'still-open 0 'closed zero-counts)
        (list (list 'raised-at-depth 'depth-1
                    (list 'assertion-violation 'call-with-database '(untracked-statements 1)))
              while-open 'still-open 0 'closed zero-counts))
  (let* ((returned
          (with-failing-close
           (lambda (spoil!)
             (handler-depth
              (lambda () (call-with-database ":memory:" (lambda (db) (spoil! db) 'returned)))))))
         (escaped
          (with-failing-close
           (lambda (spoil!)
             (handler-depth
              (lambda ()
                (call/cc
                 (lambda (k)
                   (call-with-database ":memory:" (lambda (db) (spoil! db) (k 'escaped)))))))))))
    (list returned escaped)))

;; The close's count-down finds the count at zero when this suite has taken
;; the connection's count away first: count-down! refuses that as a double
;; free, inside close-database!'s section, once the handle is closed and
;; cleared (a plant made from a suite).
(test-equal "close-database! raises its count-down's double free after its critical section: a handler of it runs at depth 1; the connection is closed, and the count stays at zero"
  (list (list 'raised-at-depth 'depth-1 (list 'assertion-violation 'count-down! '(double-free connection)))
        (list 'raised (list 'closed 'test-connection 'message))
        zero-counts)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (count-down! 'connection)
           (let* ((r (handler-depth (lambda () (close-database! db) 'closed)))
                  (after (attempt (lambda () (with-handle db (lambda (h) 'still-open))))))
             (list r after (native-counts))))))
      (lambda () (undo! '() (if db (list db) '()))))))

;; --- engines --------------------------------------------------------------------------------------
;; An engine's expiry unwinds every dynamic-wind it is inside, and its resume
;; rewinds them: an expiry inside the open's C string would free its block,
;; and the resume would find it freed. Before the open held its string in a
;; critical section, an engine of 1 to 44 ticks a slice expired inside it at
;; every fuel, and the open was refused (measured on Chez 10.4.0, where the
;; open and close of :memory: took some 90 ticks). An engine spends no ticks
;; inside a critical section (measured: a loop of 1,000 there, at 10 ticks a
;; slice, never expired), so the open now expires only outside its section:
;; at 1 tick a slice it still expires.

;; fuels : Positive-Integer -> (Listof Positive-Integer)
;; 1 to N.
(define (fuels n)
  (let loop ((i n) (found '()))
    (if (= i 0) found (loop (- i 1) (cons i found)))))

;; open-close-under-engine : Positive-Integer -> (U (List Any Natural) (List 'unfinished Natural))
;; An open of :memory: and its close, in an engine of FUEL ticks a slice.
(define (open-close-under-engine fuel)
  (run-engine (lambda ()
                (guard (e (#t (list 'raised (what-raised e))))
                  (let ((db (open-database ":memory:")))
                    (close-database! db)
                    'opened-and-closed)))
              fuel 100000))

(test-equal "open-database and close-database! under an engine of every fuel from 1 to 60 ticks a slice: each opens and closes, the engine of 1 tick expired, and every count is zero after"
  (list (map (lambda (fuel) (list fuel 'opened-and-closed)) (fuels 60)) 'expired zero-counts)
  (let loop ((rest (fuels 60)) (found '()))
    (if (null? rest)
        (let ((at-one (open-close-under-engine 1)))
          (list (reverse found)
                (if (and (pair? (cdr at-one)) (integer? (cadr at-one)) (> (cadr at-one) 0))
                    'expired
                    (list 'at-fuel-1 at-one))
                (native-counts)))
        (let ((run (open-close-under-engine (car rest))))
          (loop (cdr rest)
                (cons (if (eq? (car run) 'unfinished)
                          (list (car rest) run)
                          (list (car rest) (car run)))
                      found))))))

;; --- a close between the open check and the procedure's use ---------------------------------------
;; Two engines on one thread share a connection. A runs call-with-open-handle
;; for FUEL ticks; B then closes the connection; A finishes. Inside the
;; section A cannot expire, so B's close can only come before the check
;; (&sqlite-closed) or after the procedure (the answer): never between.

;; interleaved-close : Positive-Integer -> Symbol
;; ok when A's answer is the procedure's, run with the connection open, or
;; &sqlite-closed from its who; else what went wrong.
(define (interleaved-close fuel)
  (let* ((db (open-database ":memory:"))
         (closed #f)
         (a (make-engine
             (lambda ()
               (guard (c (#t (what-raised c)))
                 (with-handle db (lambda (h) (if closed 'ran-on-a-closed-connection 'ran-open)))))))
         (b (make-engine (lambda () (close-database! db) (set! closed #t))))
         (answer 'a-not-finished))
    (let ((a2 (a fuel (lambda (left . v) (set! answer (car v)) #f) (lambda (next) next))))
      (b 1000000 (lambda (left . v) #f) (lambda (next) (set! closed 'b-expired) #f))
      (let loop ((e a2) (n 0))
        (when (and e (< n 100000))
          (loop (e 1000000 (lambda (left . v) (set! answer (car v)) #f) (lambda (next) next))
                (+ n 1)))))
    (unless (eq? closed #t) (guard (e (#t #f)) (close-database! db)))
    (cond ((eq? answer 'ran-open) 'ok)
          ((equal? answer '(closed test-connection message)) 'ok)
          (else (list 'wrong answer)))))

(test-equal "call-with-open-handle: a close in another engine, at every fuel from 1 to 60 ticks of the first slice, never lets the procedure run on a closed connection: each answer is the procedure's or &sqlite-closed, and every count is zero after"
  (list (map (lambda (fuel) (list fuel 'ok)) (fuels 60)) zero-counts)
  (list (map (lambda (fuel) (list fuel (attempt (lambda () (interleaved-close fuel))))) (fuels 60))
        (native-counts)))

;; --- re-entering the procedure after the call finished ------------------------------------------
;; A continuation captured inside PROC, re-entered once the call has
;; answered and the connection is closed, would run PROC again with a freed
;; handle. It is refused from the call's who, before PROC, as call-with-block
;; refuses the same (a plain dynamic-wind's before thunk, outside any section).

;; reenter-after-close : -> (List Any Natural Any Any)
;; The refusal of the re-entry, how many times PROC ran, the close, the counts.
(define (reenter-after-close)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (let ((k #f) (runs 0) (phase 'first) (refusal 'not-reentered))
             ;; The handler stands around the first call, and the continuation
             ;; k is captured under it: a raise at the re-entry reaches it.
             (call/cc
              (lambda (out)
                (with-exception-handler
                 (lambda (c)
                   (set! refusal
                         (list 'raised-at-depth
                               (string->symbol (string-append "depth-" (number->string (interrupt-depth))))
                               (what-raised c)))
                   (out 'escaped))
                 (lambda ()
                   (with-handle db
                     (lambda (h)
                       (call/cc (lambda (c) (set! k c)))
                       (set! runs (+ runs 1))
                       'answered))
                   (when (eq? phase 'first)
                     (set! phase 'reentering)
                     (close-database! db)
                     (k 'again))))))
             (list refusal runs (attempt (lambda () (close-database! db) 'closed-again))
                   (native-counts))))))
      (lambda () (undo! '() (if db (list db) '()))))))

(test-equal "call-with-open-handle refuses a continuation of its procedure re-entered after the call finished: from its who, with the rule re-entered, and its handler runs at depth 1"
  (list (list 'raised-at-depth 'depth-1 (list 'assertion-violation 'test-connection '(re-entered)))
        'closed-again zero-counts)
  (let ((r (reenter-after-close)))
    (list (car r) (caddr r) (cadddr r))))

(test-equal "call-with-open-handle runs its procedure once when its continuation is re-entered after the call finished and the connection is closed"
  1
  (cadr (reenter-after-close)))

;; run-with-handle-under-engine : Positive-Integer -> (U (List Any Natural) (List 'unfinished Natural))
;; A call-with-open-handle of an open database, in an engine of FUEL ticks a slice.
(define (with-handle-under-engine fuel)
  (let ((db (open-database ":memory:")))
    (let ((run (run-engine (lambda ()
                             (guard (e (#t (list 'raised (what-raised e))))
                               (with-handle db (lambda (h) 'answered))))
                           fuel 100000)))
      (close-database! db)
      run)))

(test-equal "call-with-open-handle under an engine of every fuel from 1 to 60 ticks a slice: each call completes with its answer, the engine of 1 tick expired, and every count is zero after"
  (list (map (lambda (fuel) (list fuel 'answered)) (fuels 60)) 'expired zero-counts)
  (let loop ((rest (fuels 60)) (found '()))
    (if (null? rest)
        (let ((at-one (with-handle-under-engine 1)))
          (list (reverse found)
                (if (and (pair? (cdr at-one)) (integer? (cadr at-one)) (> (cadr at-one) 0))
                    'expired
                    (list 'at-fuel-1 at-one))
                (native-counts)))
        (let ((run (with-handle-under-engine (car rest))))
          (loop (cdr rest)
                (cons (if (eq? (car run) 'unfinished)
                          (list (car rest) run)
                          (list (car rest) (car run)))
                      found))))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "connection")

(exit (suite-exit-status runner))
