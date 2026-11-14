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
;;;                  THREADSAFE=2 library (ADR-0010, decision 5);
;;;                  tests/test-open-options.sps holds the bit itself
;;;   refusals       before anything opens or is allocated: an option, a
;;;                  filename that is no string, a file: name without 'uri,
;;;                  U+0000, each asserted by who and irritants, never by
;;;                  message (ADR-0013, decision 9), with the counts at the
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
;;;                  thread that opened, not the main one
;;;   call-with-database
;;;                  return, raise, escape and re-entry, and each with a close
;;;                  that fails, the procedure checked before anything opens
;;;
;;; &sqlite-closed has no public verb in M1 but close-database!, which does
;;; nothing on a closed connection (ADR-0012, decision 7). So it is reached
;;; here through the private call-with-open-handle, M2's helper.
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
              get-thread-id current-directory)
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

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "connection")

(exit (suite-exit-status runner))
