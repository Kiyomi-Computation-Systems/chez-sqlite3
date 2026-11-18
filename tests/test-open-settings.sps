#!r6rs
;;; The suite for the settings list at open (ADR-0018; the M3 plan, section
;;; 4.3, and section 5, item 5), in (chez-sqlite3 private open):
;;; open-database's and call-with-database's settings, checked before
;;; anything is allocated, then applied on the open connection.
;;;
;;;   refusals     every rule of ADR-0018's decision 2, through both verbs,
;;;                each before anything is allocated: the counts at the raise
;;;                and after are zero, and no file is made. '() is accepted,
;;;                and a list of options, '(read-only), refused as
;;;                not-an-association-list
;;;   db_config    each of the four db_config settings, #t and #f, accepted
;;;                and opened, on :memory: and on a file: M4 slice 3 joined
;;;                them to the live list and replaced slice 1's two rows that
;;;                held them out; their sets are test-open-db-config's
;;;   the order    the split first, a second list; then M2's checks, the
;;;                filename, the options, file: without uri; then the list's
;;;   together     options and a list, the list at each position among two
;;;                options, through both verbs: each option and each setting
;;;                takes effect
;;;   set, read    each of the six at every value of its domain, read back
;;;                by PRAGMA on the same connection; journal-mode through a
;;;                second connection's view, which the file keeps; foreign-keys
;;;                by what it refuses; all six at once
;;;   mismatches   journal-mode on :memory: at each of its values reads
;;;                memory, and wal on a temporary database delete (Q9; single
;;;                P11; concurrency S4), through both verbs; each of the six
;;;                read back as other than asked, through applied-settings!
;;;                with steps no list makes; the three fields whole
;;;   a failure    closes: a mismatch, a set that fails, a read that fails,
;;;   closes       each leaves no connection counted and no file descriptor
;;;                open; call-with-database's procedure is never called; a
;;;                close that then fails is not raised over the setting's
;;;                condition, the connection left open and counted
;;;   the cache    statement-cache through the public surface: after 33
;;;                distinct statements through query, the statement count is
;;;                32 at the default, 1 at 1, 33 at 1024, and 0 at 0 after
;;;                every convenience; at 2, A, B, A, C leave A and C
;;;   busy first   under another's exclusive lock, a list with busy-timeout
;;;                last waits at synchronous's prepare for the timeout, once,
;;;                under twice it, which
;;;                only busy-timeout's running first explains; without
;;;                busy-timeout it answers busy at once
;;;   unasked      a connection opened without busy-timeout keeps SQLite's 0,
;;;                and a list's other settings are a plain open's (decision 8)
;;;   depth        a with-exception-handler handler of each raise site runs at
;;;                interrupt depth 1, its who the verb called
;;;
;;; The loading procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them. SQLite's answers here were measured
;;; on 3.53.1 and 3.45.1 alike before a row asserts them.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure directory-list real-time disable-interrupts
              enable-interrupts)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3 private conditions) sqlite-setting-mismatch?
              sqlite-setting-mismatch-setting sqlite-setting-mismatch-expected
              sqlite-setting-mismatch-actual sqlite-extensions-unavailable?)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-error-sql sqlite-busy? sqlite-closed?))

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

(define (public name) (reach '(chez-sqlite3) name))

(define open-database (public 'open-database))
(define call-with-database (public 'call-with-database))
(define close-database! (public 'close-database!))
(define execute! (public 'execute!))
(define query (public 'query))
(define query-row (public 'query-row))
(define query-fold (public 'query-fold))
(define statement-sql (public 'statement-sql))
(define applied-settings! (reach '(chez-sqlite3 private open) 'applied-settings!))
(define tracked-statements (reach '(chez-sqlite3 private connection) 'tracked-statements))
(define database-cache-capacity (reach '(chez-sqlite3 private connection) 'database-cache-capacity))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-out-pointer (reach '(chez-sqlite3 private native) 'call-with-out-pointer))

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
;; whether it is a library condition and not an &sqlite-error; an
;; &sqlite-error by its who, codes and SQL; &sqlite-closed by its who; an
;; assertion violation by its who and irritants.
(define (what-raised e)
  (cond ((sqlite-setting-mismatch? e)
         (list 'mismatch (who-of e) (sqlite-setting-mismatch-setting e)
               (sqlite-setting-mismatch-expected e) (sqlite-setting-mismatch-actual e)
               (if (and (chez-sqlite3-error? e) (not (sqlite-error? e))) 'library-condition 'other-kind)))
        ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (sqlite-error-sql e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

;; attempt-open : (-> Any) -> Any
;; attempt, but a database THUNK answers is closed, and answered as opened,
;; so a row that expects a refusal leaves nothing open when it gets none.
(define database? (public 'database?))
(define (attempt-open thunk)
  (let ((r (attempt thunk)))
    (if (guard (e (#t #f)) (database? r))
        (begin (close-answer r) 'opened)
        r)))

;; first-n : (Listof Any) Natural -> (Listof Any)
(define (first-n items n)
  (if (or (= n 0) (null? items)) '() (cons (car items) (first-n (cdr items) (- n 1)))))

(define (mismatch who setting expected actual)
  (list 'raised (list 'mismatch who setting expected actual 'library-condition)))

(define (refused who . irritants) (list 'raised (list 'assertion-violation who irritants)))

;; at-raise : (-> Any) -> (List Any Any)
;; What THUNK raised, and the counts when it raised them, read by a handler
;; before anything unwinds; (no-raise ...) when it raised nothing, any
;; database it answered closed.
(define raised-tag (list 'raised-tag))
(define (at-raise thunk)
  (let* ((seen 'no-raise)
         (r (guard (e (#t (cons raised-tag e)))
              (with-exception-handler
               (lambda (c) (when (eq? seen 'no-raise) (set! seen (native-counts))) (raise c))
               thunk))))
    (if (and (pair? r) (eq? (car r) raised-tag))
        (list (what-raised (cdr r)) seen)
        (begin (close-answer r) (list 'no-raise 'no-counts)))))

;; close-answer : Any -> Void
(define (close-answer r)
  (guard (e (#t #f)) (close-database! r)))

(define (in-dir proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory proc)))

(define (made path) (if (file-exists? path) 'made 'not-made))

;; descriptors : -> Natural
;; How many file descriptors this process has open, read from /dev/fd,
;; which Linux and macOS both have.
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
;; The first column of PRAGMA NAME's row on DB, by query-row.
(define (pragma db name)
  (let ((row (query-row db (string-append "PRAGMA " name))))
    (if (vector? row) (vector-ref row 0) (list 'no-row row))))

(define pragma-names '("busy_timeout" "foreign_keys" "journal_mode" "synchronous" "temp_store" "trusted_schema"))

;; readings : Database -> (Listof Any)
;; The six settings on DB, in ADR-0018's table order, each by pragma, in order.
(define (readings db)
  (let loop ((rest pragma-names) (found '()))
    (if (null? rest)
        (reverse found)
        (loop (cdr rest) (cons (pragma db (car rest)) found)))))

;; raw-prepare! : Database String -> Positive-Integer
;; A statement of SQL on DB, made with the raw sqlite3_prepare_v2, so the
;; connection does not track it, and its close is refused.
(define (raw-prepare! db sql)
  (call-with-open-handle 'test-open-settings db
    (lambda (h)
      (call-with-c-string 'test-open-settings sql
        (lambda (text)
          (let-values (((rc statement)
                        (call-with-out-pointer 'test-open-settings
                          (lambda (slot) (prepare-v2 h text -1 slot 0)))))
            (if (and (eqv? rc 0) (not (eqv? statement 0)))
                statement
                (error 'raw-prepare! "sqlite3_prepare_v2 did not answer a statement" rc))))))))

;; interrupt-depth : -> Positive-Integer
(define (interrupt-depth)
  (let ((n (disable-interrupts)))
    (enable-interrupts)
    n))

;; handler-depth : (-> Any) -> (U (List 'raised-at-depth Symbol Any) (List 'no-raise Any))
;; The depth a with-exception-handler handler runs at for the first thing
;; THUNK raises, and what it raised; the handler escapes. (no-raise) when
;; THUNK raises nothing, any database it answered closed.
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
          (close-answer r)
          (list 'no-raise)))))))

(define (at-depth-1 what) (list 'raised-at-depth 'depth-1 what))

;; distinct-sql : Natural -> String
(define (distinct-sql i) (string-append "select " (number->string i)))

;; query-distinct! : Database Natural -> Void
;; N distinct statements, select 0 to select N-1, each run once by query, in
;; order.
(define (query-distinct! db n)
  (let loop ((i 0))
    (when (< i n)
      (query db (distinct-sql i))
      (loop (+ i 1)))))

;; tracked-sql : Database -> (Listof String)
;; The SQL of every statement DB tracks, sorted.
(define (tracked-sql db)
  (list-sort string<?
             (let loop ((rest (tracked-statements db)) (found '()))
               (if (null? rest)
                   found
                   (loop (cdr rest) (cons (statement-sql (car rest)) found))))))

(test-begin "open-settings")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

;; --- refusals, before anything opens ---------------------------------------------------------

;; refusal-cases : (Listof (Pairof (Listof Any) (Listof Any)))
;; Each case's arguments after the filename, and the irritants its refusal
;; names: every rule of ADR-0018's decision 2, each setting's domain.
(define refusal-cases
  (list
   (cons '(() ()) '(second-settings-list))
   (cons '(((foreign-keys . #t)) read-only ((busy-timeout . 5))) '(second-settings-list))
   (cons '((read-only)) '(not-an-association-list read-only))
   (cons '(((foreign-keys . #t) . 5)) '(not-an-association-list (kind list)))
   (cons '(((foreign-keys . #t) 7)) '(not-an-association-list 7))
   (cons '((("foreign-keys" . #t))) '(not-an-association-list (kind list)))
   (cons '(((nosuch . 1))) '(unknown-setting nosuch))
   (cons '(((foreign_keys . #t))) '(unknown-setting foreign_keys))
   (cons '(((page-size . 4096))) '(unknown-setting page-size))
   (cons '(((foreign-keys . #t) (foreign-keys . #t))) '(setting-given-twice foreign-keys))
   (cons '(((busy-timeout . -1))) '(setting-out-of-domain busy-timeout -1))
   (cons '(((busy-timeout . 2147483648))) '(setting-out-of-domain busy-timeout 2147483648))
   (cons '(((busy-timeout . 1.5))) '(setting-out-of-domain busy-timeout 1.5))
   (cons '(((busy-timeout . "5000"))) '(setting-out-of-domain busy-timeout (kind string)))
   (cons '(((foreign-keys . 1))) '(setting-out-of-domain foreign-keys 1))
   (cons '(((journal-mode . memory))) '(setting-out-of-domain journal-mode memory))
   (cons '(((journal-mode . WAL))) '(setting-out-of-domain journal-mode WAL))
   (cons '(((journal-mode . "wal"))) '(setting-out-of-domain journal-mode (kind string)))
   (cons '(((synchronous . 4))) '(setting-out-of-domain synchronous 4))
   (cons '(((temp-store . 2))) '(setting-out-of-domain temp-store 2))
   (cons '(((trusted-schema . on))) '(setting-out-of-domain trusted-schema on))
   (cons '(((statement-cache . 1025))) '(setting-out-of-domain statement-cache 1025))))

;; refusal-run : Symbol String (Listof Any) -> (List Any Any Any Any)
;; The case's ARGUMENTS through VERB on PATH: what it raised and the counts
;; at the raise, the counts after, and whether PATH was made. call-with-
;; database's procedure, when it runs, answers proc-ran.
(define (refusal-run verb path arguments)
  (let* ((r (at-raise (lambda ()
                        (if (eq? verb 'open-database)
                            (apply open-database path arguments)
                            (apply call-with-database path
                                   (append arguments (list (lambda (db) 'proc-ran))))))))
         (after (native-counts)))
    (list r after (made path))))

;; refusal-expected : Symbol (Listof Any) -> (List Any Any Any)
(define (refusal-expected verb irritants)
  (list (list (list 'assertion-violation verb irritants) zero-counts) zero-counts 'not-made))

(test-equal "every refusal of the settings list, by its rule and the value as shown-value shows it, through open-database and call-with-database: a second list; no association list of symbols; an unknown setting; one given twice; a value outside its domain, for each setting; each before anything is allocated, the counts zero at the raise and after, and no file made"
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

(test-equal "an empty settings list is accepted by both verbs, the cache 32 as with none; a list of options, '(read-only), is refused as not-an-association-list, before anything opens"
  (list 32 32 (refused 'open-database 'not-an-association-list 'read-only)
        (refused 'call-with-database 'not-an-association-list 'read-only) zero-counts)
  (let* ((a (with-db (lambda () (open-database ":memory:" '())) database-cache-capacity))
         (b (attempt (lambda () (call-with-database ":memory:" '() database-cache-capacity))))
         (c (attempt-open (lambda () (open-database ":memory:" '(read-only)))))
         (d (attempt (lambda () (call-with-database ":memory:" '(read-only) database-cache-capacity)))))
    (list a b c d (native-counts))))

;; The four db_config settings (ADR-0021, decision 1) joined the live list in
;; M4 slice 3, which replaced slice 1's two rows here that held them out,
;; refused as unknown-setting: each is accepted now, and opens. Their sets,
;; each read back, are tests/test-open-db-config.sps's.
(define db-config-cases
  '((enable-load-extension . #t) (enable-load-extension . #f) (defensive . #t) (defensive . #f)
    (dqs-dml . #t) (dqs-dml . #f) (dqs-ddl . #t) (dqs-ddl . #f)))

;; extension-loading : Any
;; native's record of sqlite3_load_extension: where it is not #t, the
;; opt-in's #t is refused before anything opens (ADR-0021, decision 5).
(define extension-loading
  (guard (e (#t (list 'unreached (describe e))))
    (eval 'load-extension-available? (environment '(chez-sqlite3 private native)))))

;; accepted-expected : (Pairof Symbol Boolean) -> Symbol
(define (accepted-expected s)
  (if (and (equal? s '(enable-load-extension . #t)) (not (eq? extension-loading #t)))
      'extensions-unavailable
      'opened))

;; accepted-run : (-> Any) -> Any
;; opened, the database THUNK answered closed; extensions-unavailable; or
;; what else THUNK raised.
(define (accepted-run thunk)
  (let ((r (guard (e ((sqlite-extensions-unavailable? e) 'extensions-unavailable)
                     (#t (list 'raised (what-raised e))))
             (thunk))))
    (if (guard (e (#t #f)) (database? r))
        (begin (close-answer r) 'opened)
        r)))

(test-equal "each of db_config's four, #t and #f, is accepted by open-database on :memory: and opens, nothing left counted once it is closed; where the library lacks sqlite3_load_extension, the opt-in's #t is refused instead, before anything opens"
  (map (lambda (s) (list (accepted-expected s) zero-counts)) db-config-cases)
  (begin
    (unless (eq? extension-loading #t)
      (display "UNAVAILABLE the opt-in's open: this libsqlite3 has no sqlite3_load_extension, so its refusal is asserted in its place")
      (newline))
    (let loop ((rest db-config-cases) (found '()))
      (if (null? rest)
          (reverse found)
          (let* ((r (accepted-run (lambda () (open-database ":memory:" (list (car rest))))))
                 (after (native-counts)))
            (loop (cdr rest) (cons (list r after) found)))))))

(test-equal "each of db_config's four, #t and #f, is accepted the same on a file of its own, which the open makes; a refused opt-in makes none"
  (map (lambda (s)
         (let ((e (accepted-expected s)))
           (list e zero-counts (if (eq? e 'opened) 'made 'not-made))))
       db-config-cases)
  (in-dir (lambda (dir)
            (let loop ((rest db-config-cases) (i 0) (found '()))
              (if (null? rest)
                  (reverse found)
                  (let* ((path (string-append dir "/d" (number->string i) ".db"))
                         (r (accepted-run (lambda () (open-database path (list (car rest))))))
                         (after (native-counts))
                         (file (made path)))
                    (loop (cdr rest) (+ i 1) (cons (list r after file) found))))))))

;; --- the order of the refusals ---------------------------------------------------------------

(test-equal "a bad option and a bad setting together: M2's checks come first, wherever the option stands among the arguments, and so do the filename's and file:'s; a second list, the split's, comes before every other; call-with-database checks its procedure before all"
  (list (refused 'open-database 'unknown-option 'bogus)
        (refused 'open-database 'unknown-option 'bogus)
        (refused 'open-database 'option-given-twice 'uri)
        (refused 'open-database 'contradictory-options 'read-only 'create)
        (refused 'open-database 'not-a-string 42)
        (refused 'open-database 'file-uri-without-uri-option '(kind string))
        (refused 'open-database 'second-settings-list)
        (refused 'open-database 'second-settings-list)
        (refused 'call-with-database 'unknown-option 'bogus)
        (refused 'call-with-database 'not-a-procedure 'bogus)
        zero-counts)
  (in-dir (lambda (dir)
            (let* ((path (string-append dir "/o.db"))
                   (bad '((nosuch . 1)))
                   (a (attempt-open (lambda () (open-database path 'bogus bad))))
                   (b (attempt-open (lambda () (open-database path bad 'bogus))))
                   (c (attempt-open (lambda () (open-database path 'uri bad 'uri))))
                   (d (attempt-open (lambda () (open-database path 'read-only '((busy-timeout . -1)) 'create))))
                   (e (attempt-open (lambda () (open-database 42 bad))))
                   (f (attempt-open (lambda () (open-database (string-append "file:" path) bad))))
                   (g (attempt-open (lambda () (open-database 42 '() '()))))
                   (h (attempt-open (lambda () (open-database path 'bogus bad '()))))
                   (i (attempt (lambda () (call-with-database path bad 'bogus (lambda (db) 'proc-ran)))))
                   (j (attempt (lambda () (call-with-database path 'bogus bad 'bogus)))))
              (list a b c d e f g h i j (native-counts))))))

;; --- options and a list together ---------------------------------------------------------------

;; mixed-list : Settings
(define mixed-list '((busy-timeout . 77) (foreign-keys . #t)))

;; mixed-arguments : (Listof (Listof Any))
;; The list at each position among two options, read-only and uri.
(define mixed-arguments
  (list (list mixed-list 'read-only 'uri)
        (list 'read-only mixed-list 'uri)
        (list 'read-only 'uri mixed-list)))

;; both-took : Database -> (List Any Any Any)
;; What a write on DB raised, and its busy_timeout and foreign_keys, each in
;; order.
(define (both-took db)
  (let* ((w (attempt (lambda () (execute! db "insert into t values (1)") 'written)))
         (b (pragma db "busy_timeout"))
         (f (pragma db "foreign_keys")))
    (list w b f)))

(define both-expected
  (list (list 'raised (list 'sqlite-error 'execute! 'readonly 'readonly "insert into t values (1)"))
        77 1))

(test-equal "options and a list together, the list at each position among read-only and uri, through both verbs: each opens the file: name, which uri allows; refuses a write, read-only; and reads back busy-timeout 77 and foreign-keys on, the list's; nothing is left counted"
  (list (list both-expected both-expected both-expected)
        (list both-expected both-expected both-expected)
        zero-counts)
  (in-dir (lambda (dir)
            (let* ((path (string-append dir "/mixed.db"))
                   (name (string-append "file:" path))
                   (made (with-db (lambda () (open-database path))
                                  (lambda (db) (execute! db "create table t (x)") 'made))))
              (if (not (eq? made 'made))
                  (list 'not-made made)
                  (let loop ((rest mixed-arguments) (opened '()) (called '()))
                    (if (null? rest)
                        (list (reverse opened) (reverse called) (native-counts))
                        (let* ((args (car rest))
                               (a (with-db (lambda () (apply open-database name args)) both-took))
                               (b (attempt (lambda ()
                                             (apply call-with-database name
                                                    (append args (list both-took)))))))
                          (loop (cdr rest) (cons a opened) (cons b called))))))))))

;; --- each of the six, set and read back ---------------------------------------------------------

;; value-cases : (Listof (List Symbol Any String Any))
;; Each setting at every value of its domain, busy-timeout at its edges and
;; one between: the setting, the value, its PRAGMA, and what that PRAGMA
;; reads back, as column-value reads it.
(define value-cases
  '((busy-timeout 0 "busy_timeout" 0)
    (busy-timeout 1234 "busy_timeout" 1234)
    (busy-timeout 2147483647 "busy_timeout" 2147483647)
    (foreign-keys #t "foreign_keys" 1)
    (foreign-keys #f "foreign_keys" 0)
    (journal-mode delete "journal_mode" "delete")
    (journal-mode truncate "journal_mode" "truncate")
    (journal-mode persist "journal_mode" "persist")
    (journal-mode wal "journal_mode" "wal")
    (synchronous off "synchronous" 0)
    (synchronous normal "synchronous" 1)
    (synchronous full "synchronous" 2)
    (synchronous extra "synchronous" 3)
    (temp-store default "temp_store" 0)
    (temp-store file "temp_store" 1)
    (temp-store memory "temp_store" 2)
    (trusted-schema #t "trusted_schema" 1)
    (trusted-schema #f "trusted_schema" 0)))

(test-equal "each of the six at every value of its domain, set at open, reads back as asked by PRAGMA on the same connection, each on a fresh file of its own, so every value but one of each is no default"
  (map cadddr value-cases)
  (in-dir (lambda (dir)
            (let loop ((rest value-cases) (i 0) (found '()))
              (if (null? rest)
                  (reverse found)
                  (let* ((case (car rest))
                         (path (string-append dir "/v" (number->string i) ".db"))
                         (r (with-db (lambda () (open-database path (list (cons (car case) (cadr case)))))
                                     (lambda (db) (pragma db (caddr case))))))
                    (loop (cdr rest) (+ i 1) (cons r found))))))))

(test-equal "journal-mode wal is kept in the file: a second connection, opened while the first is open, reads wal; delete, set once both have closed, is what a connection opened after it reads"
  (list (list "wal" "wal") "delete" "delete" zero-counts)
  (in-dir (lambda (dir)
            (let* ((path (string-append dir "/j.db"))
                   (a (with-db (lambda () (open-database path '((journal-mode . wal))))
                               (lambda (db)
                                 (let* ((own (pragma db "journal_mode"))
                                        (other (with-db (lambda () (open-database path))
                                                        (lambda (o) (pragma o "journal_mode")))))
                                   (list own other)))))
                   (b (with-db (lambda () (open-database path '((journal-mode . delete))))
                               (lambda (db) (pragma db "journal_mode"))))
                   (c (with-db (lambda () (open-database path)) (lambda (db) (pragma db "journal_mode")))))
              (list a b c (native-counts))))))

;; orphan-insert : Any -> Any
;; On a :memory: connection opened with SETTINGS, a child row whose parent is
;; missing inserted: inserted, or what the insert raised.
(define (orphan-insert settings)
  (with-db (lambda () (open-database ":memory:" settings))
    (lambda (db)
      (execute! db "create table p (id integer primary key)")
      (execute! db "create table c (p integer references p (id))")
      (execute! db "insert into c values (1)")
      'inserted)))

(test-equal "foreign-keys by what it refuses: at #t a child row with no parent is a constraint, extended foreignkey; at #f it goes in"
  (list (list 'raised (list 'sqlite-error 'execute! 'constraint 'constraint-foreignkey
                            "insert into c values (1)"))
        'inserted)
  (list (orphan-insert '((foreign-keys . #t)))
        (orphan-insert '((foreign-keys . #f)))))

(test-equal "all six at once, busy-timeout among the rest, and statement-cache: the open leaves no statement tracked, none in its cache, since each setting's two are finalized and never cached; then each reads back as asked on the one connection, its cache's capacity 5; call-with-database applies its list before it calls its procedure"
  (list (list 0 0 '(1234 1 "truncate" 3 2 0) 5) '(0 77 1 9))
  (in-dir (lambda (dir)
            (let* ((path (string-append dir "/all.db"))
                   (a (with-db (lambda ()
                                 (open-database path '((trusted-schema . #f) (journal-mode . truncate)
                                                       (busy-timeout . 1234) (statement-cache . 5)
                                                       (foreign-keys . #t) (synchronous . extra)
                                                       (temp-store . memory))))
                               (lambda (db)
                                 (let* ((tracked (length (tracked-statements db)))
                                        (counted (statement-count))
                                        (read (readings db)))
                                   (list tracked counted read (database-cache-capacity db))))))
                   (b (attempt (lambda ()
                                 (call-with-database path '((busy-timeout . 77) (foreign-keys . #t)
                                                            (statement-cache . 9))
                                   (lambda (db)
                                     (let* ((tracked (length (tracked-statements db)))
                                            (timeout (pragma db "busy_timeout"))
                                            (keys (pragma db "foreign_keys")))
                                       (list tracked timeout keys (database-cache-capacity db)))))))))
              (list a b)))))

;; --- mismatches -----------------------------------------------------------------------------

(test-equal "journal-mode on :memory: mismatches at each of its values, the read-back memory (Q9; single P11): open-database raises &sqlite-setting-mismatch, a library condition and no &sqlite-error, its setting, the value asked for and memory; call-with-database the same, its procedure never called; nothing is left counted"
  (list (mismatch 'open-database 'journal-mode 'delete 'memory)
        (mismatch 'open-database 'journal-mode 'truncate 'memory)
        (mismatch 'open-database 'journal-mode 'persist 'memory)
        (mismatch 'open-database 'journal-mode 'wal 'memory)
        (mismatch 'call-with-database 'journal-mode 'wal 'memory)
        'proc-not-called zero-counts)
  (let* ((called 'proc-not-called)
         (a (attempt-open (lambda () (open-database ":memory:" '((journal-mode . delete))))))
         (b (attempt-open (lambda () (open-database ":memory:" '((journal-mode . truncate))))))
         (c (attempt-open (lambda () (open-database ":memory:" '((journal-mode . persist))))))
         (d (attempt-open (lambda () (open-database ":memory:" '((journal-mode . wal))))))
         (e (attempt (lambda () (call-with-database ":memory:" '((journal-mode . wal))
                                  (lambda (db) (set! called 'proc-called)))))))
    (list a b c d e called (native-counts))))

(test-equal "journal-mode wal on a temporary database, filename \"\", mismatches, the read-back delete (concurrency S4); delete, truncate and persist read back as asked there"
  (list (mismatch 'open-database 'journal-mode 'wal 'delete) "delete" "truncate" "persist" zero-counts)
  (let* ((a (attempt-open (lambda () (open-database "" '((journal-mode . wal))))))
         (b (with-db (lambda () (open-database "" '((journal-mode . delete))))
                     (lambda (db) (pragma db "journal_mode"))))
         (c (with-db (lambda () (open-database "" '((journal-mode . truncate))))
                     (lambda (db) (pragma db "journal_mode"))))
         (d (with-db (lambda () (open-database "" '((journal-mode . persist))))
                     (lambda (db) (pragma db "journal_mode")))))
    (list a b c d (native-counts))))

;; crafted-mismatches : (Listof (Pairof Setting-Step (List Symbol Any Any)))
;; A step no list makes, whose set writes other than the value it expects,
;; for each of the six; and the mismatch's setting, expected and actual. Each
;; actual is what SQLite reads back: synchronous = 4 is stored as 4, no
;; level of SQLite's (single P4).
(define crafted-mismatches
  '(((busy-timeout "PRAGMA busy_timeout = 5" "PRAGMA busy_timeout" 6) busy-timeout 6 5)
    ((foreign-keys "PRAGMA foreign_keys = 1" "PRAGMA foreign_keys" #f) foreign-keys #f #t)
    ((journal-mode "PRAGMA journal_mode = truncate" "PRAGMA journal_mode" wal) journal-mode wal truncate)
    ((synchronous "PRAGMA synchronous = 4" "PRAGMA synchronous" extra) synchronous extra 4)
    ((temp-store "PRAGMA temp_store = 2" "PRAGMA temp_store" file) temp-store file memory)
    ((trusted-schema "PRAGMA trusted_schema = 0" "PRAGMA trusted_schema" #t) trusted-schema #t #f)))

;; crafted-run : String (Listof Setting-Step) -> (List Any Natural Natural Any Any)
;; A connection opened on PATH, then STEPS applied by applied-settings!, as
;; the-suite: what that raised; then the connections and statements counted;
;; whether the descriptors are those before the open; and what a query on
;; the connection raises.
(define (crafted-run path steps)
  (let* ((before (descriptors))
         (db (open-database path))
         (r (attempt (lambda () (applied-settings! 'the-suite db steps) 'applied)))
         (counts (list (connection-count) (statement-count)))
         (back (if (equal? (descriptors) before) 'descriptors-back (list 'descriptors before (descriptors))))
         (after (attempt (lambda () (query-row db "select 1")))))
    (close-answer db)
    (list r (car counts) (cadr counts) back after)))

(test-equal "each of the six read back as other than asked mismatches, through applied-settings! with a step no list makes: the mismatch names the setting, the value asked for and the value read, each as a Scheme value, 4 for synchronous as read; the connection is closed first, nothing counted, no descriptor left open"
  (map (lambda (c) (list (mismatch 'the-suite (cadr c) (caddr c) (cadddr c)) 0 0 'descriptors-back
                         (list 'raised (list 'closed 'query-row))))
       crafted-mismatches)
  (in-dir (lambda (dir)
            (let loop ((rest crafted-mismatches) (i 0) (found '()))
              (if (null? rest)
                  (reverse found)
                  (let ((r (crafted-run (string-append dir "/m" (number->string i) ".db")
                                        (list (car (car rest))))))
                    (loop (cdr rest) (+ i 1) (cons r found))))))))

;; --- a failure closes --------------------------------------------------------------------------

(define failing-set '(foreign-keys "PRAGMA nosuch.foreign_keys = 1" "PRAGMA foreign_keys" #t))
(define failing-read '(foreign-keys "PRAGMA foreign_keys = 1" "PRAGMA nosuch.foreign_keys" #t))
(define matching '(busy-timeout "PRAGMA busy_timeout = 25" "PRAGMA busy_timeout" 25))

(define (unknown-database sql) (list 'raised (list 'sqlite-error 'the-suite 'error 'error sql)))

(test-equal "a setting's statement that fails closes the connection, then raises its own condition, from the who: a set, an unknown schema at its prepare; a read the same, after a setting that matched; no connection counted, no statement, no descriptor left open"
  (list (list (unknown-database "PRAGMA nosuch.foreign_keys = 1") 0 0 'descriptors-back
              (list 'raised (list 'closed 'query-row)))
        (list (unknown-database "PRAGMA nosuch.foreign_keys") 0 0 'descriptors-back
              (list 'raised (list 'closed 'query-row))))
  (in-dir (lambda (dir)
            (let* ((a (crafted-run (string-append dir "/f1.db") (list failing-set)))
                   (b (crafted-run (string-append dir "/f2.db") (list matching failing-read))))
              (list a b)))))

;; close-fails : Setting-Step -> (List Any Natural Any Any)
;; On a :memory: connection holding a statement it does not track, so its
;; close is refused, STEP applied by applied-settings!: what that raised;
;; the connections counted; a query's answer on the connection, still open;
;; and its close once the statement is gone.
(define (close-fails step)
  (let ((db #f) (raw #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt
         (lambda ()
           (set! db (open-database ":memory:"))
           (set! raw (raw-prepare! db "select 1"))
           (let* ((r (attempt (lambda () (applied-settings! 'the-suite db (list step)) 'applied)))
                  (n (connection-count))
                  (alive (attempt (lambda () (query-row db "select 7"))))
                  (freed (begin (raw-finalize raw) (set! raw #f)))
                  (closed (attempt (lambda () (close-database! db) 'closed))))
             (list r n alive closed)))))
      (lambda ()
        (when raw (raw-finalize raw))
        (when db (close-answer db))))))

(test-equal "a close that fails after a setting's failure is not raised over it: with an untracked statement on the connection, a mismatch raises the mismatch, and a failing set its own condition, never the close's refusal; the connection stays open and counted, and closes once the statement is gone"
  (list (list (mismatch 'the-suite 'foreign-keys #f #t) 1 '#(7) 'closed)
        (list (unknown-database "PRAGMA nosuch.foreign_keys = 1") 1 '#(7) 'closed)
        zero-counts)
  (let* ((a (close-fails (car (cadr crafted-mismatches))))
         (b (close-fails failing-set)))
    (list a b (native-counts))))

;; --- statement-cache through the public surface ---------------------------------------------

;; after-33 : (-> Database) -> Any
;; The statement count after 33 distinct statements through query, on the
;; connection OPEN makes.
(define (after-33 open)
  (with-db open (lambda (db) (query-distinct! db 33) (statement-count))))

(test-equal "statement-cache through the public surface: after 33 distinct statements through query, the statement count is 32 at the default, with no list, with () and with 32; 1 at 1; 33 at 1024; and 1 at 1 through call-with-database"
  '(32 32 32 1 33 1)
  (list (after-33 (lambda () (open-database ":memory:")))
        (after-33 (lambda () (open-database ":memory:" '())))
        (after-33 (lambda () (open-database ":memory:" '((statement-cache . 32)))))
        (after-33 (lambda () (open-database ":memory:" '((statement-cache . 1)))))
        (after-33 (lambda () (open-database ":memory:" '((statement-cache . 1024)))))
        (attempt (lambda () (call-with-database ":memory:" '((statement-cache . 1))
                              (lambda (db) (query-distinct! db 33) (statement-count)))))))

;; each-convenience : (-> Database) -> Any
;; The statement count after each of execute!, query, query-row and
;; query-fold, each on its own SQL, then after 33 distinct statements through
;; query, on the connection OPEN makes.
(define (each-convenience open)
  (with-db open
    (lambda (db)
      (let* ((a (begin (execute! db "create table t (x)") (statement-count)))
             (b (begin (query db "select 1") (statement-count)))
             (c (begin (query-row db "select 2") (statement-count)))
             (d (begin (query-fold db "select 3" (lambda (acc row) acc) 0) (statement-count)))
             (e (begin (query-distinct! db 33) (statement-count))))
        (list a b c d e)))))

(test-equal "at a statement-cache of 0 no statement is left after any convenience, execute!, query, query-row and query-fold, nor after 33 distinct statements; at the default each leaves one more, up to 32"
  (list '(0 0 0 0 0) '(1 2 3 4 32))
  (list (each-convenience (lambda () (open-database ":memory:" '((statement-cache . 0)))))
        (each-convenience (lambda () (open-database ":memory:")))))

(test-equal "at a statement-cache of 2, the statements A, B, A, C through query leave A and C, read through tracked-statements: A's reuse made B the least recently used, and C evicted it"
  '("select 'a'" "select 'c'")
  (with-db (lambda () (open-database ":memory:" '((statement-cache . 2))))
    (lambda (db)
      (query db "select 'a'")
      (query db "select 'b'")
      (query db "select 'a'")
      (query db "select 'c'")
      (tracked-sql db))))

;; --- busy-timeout first, under another's lock ---------------------------------------------------

;; under-lock : String Symbol (-> Any) -> (List Any Natural Natural Natural)
;; What THUNK answered, by attempt-open, the milliseconds it took, and the
;; connections and statements counted after it, while a second connection to
;; PATH holds LOCK: exclusive, BEGIN EXCLUSIVE and a write; reserved, BEGIN
;; IMMEDIATE and a write. That connection's three statements stay in its
;; cache; the one THUNK opens is fresh, and holds no read of its own
;; (AGENTS.md).
(define (under-lock path lock thunk)
  (let ((holder (open-database path)))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (execute! holder "create table if not exists t (x)")
        (execute! holder (if (eq? lock 'exclusive) "begin exclusive" "begin immediate"))
        (execute! holder "insert into t values (1)")
        (let* ((t0 (real-time))
               (r (attempt-open thunk))
               (t1 (real-time)))
          (list r (- t1 t0) (connection-count) (statement-count))))
      (lambda ()
        (guard (e (#t #f)) (execute! holder "rollback"))
        (close-answer holder)))))

(define (busy who sql) (list 'raised (list 'sqlite-error who 'busy 'busy sql)))

;; grain-ms : -> Any
;; The milliseconds a BEGIN IMMEDIATE with a 250 ms busy timeout takes to
;; answer busy, under another connection's reserved lock on a fresh file,
;; both on this thread: about 250 where the build sleeps in milliseconds, 0
;; where it sleeps whole seconds, whose first sleep would pass the timeout
;; (concurrency B3; test-contention's P4 row). Else what it answered, or
;; raised.
(define (grain-ms)
  (in-dir
   (lambda (dir)
     (let* ((path (string-append dir "/grain.db"))
            (holder (open-database path)))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (execute! holder "create table t (x)")
           (execute! holder "begin immediate")
           (execute! holder "insert into t values (1)")
           (let ((waiter (open-database path '((busy-timeout . 250)))))
             (dynamic-wind
               (lambda () #f)
               (lambda ()
                 (let* ((t0 (real-time))
                        (r (attempt (lambda () (execute! waiter "begin immediate"))))
                        (t1 (real-time)))
                   (if (equal? r (busy 'execute! "begin immediate")) (- t1 t0) (list 'not-busy r))))
               (lambda () (close-answer waiter)))))
         (lambda ()
           (guard (e (#t #f)) (execute! holder "rollback"))
           (close-answer holder)))))))

;; grain : (U 'milliseconds 'whole-seconds (List 'unread Any))
;; The build's busy-wait grain, read once, before the timed row:
;; milliseconds from 125 ms, half the timeout, as test-contention's P4 row
;; tells them apart.
(define grain
  (let ((ms (guard (e (#t (list 'raised (describe e)))) (grain-ms))))
    (cond ((not (integer? ms)) (list 'unread ms))
          ((>= ms 125) 'milliseconds)
          (else 'whole-seconds))))

;; retry-ms : Natural
;; Where the timed open's wait is too long: a retry of its 1500 ms busy
;; timeout waits at least 2000 ms on a whole-second build, and 3000 on any
;; other; an unread grain takes the looser bound, and its row fails.
(define retry-ms (if (eq? grain 'whole-seconds) 2000 3000))

;; timed : (List Any Natural Natural Natural) -> (List Any Symbol Natural Natural)
;; R with its milliseconds read as waited, at least 1000 and under retry-ms;
;; too-long, from retry-ms; or at-once. The timed open's busy timeout is
;; 1500 ms: one wait takes 1500 ms of it on a build that sleeps in
;; milliseconds, and 1000 on one without nanosleep, which sleeps whole
;; seconds; one retry in Scheme waits it out twice, at least 3000 on the
;; first and 2000 on the second (ADR-0019, no retry in Scheme).
(define (timed r)
  (if (and (list? r) (= (length r) 4))
      (list (car r)
            (cond ((>= (cadr r) retry-ms) 'too-long) ((>= (cadr r) 1000) 'waited) (else 'at-once))
            (caddr r) (cadddr r))
      r))

(test-equal "the busy wait's grain is read before the timed row, as test-contention's P4 row reads it: a 250 ms busy timeout under another's reserved lock answers busy after 125 ms or more, milliseconds, or before, whole seconds; the timed open's wait is too long from 3000 ms on the first, and from 2000 on the second"
  'read
  (begin
    (display "    the grain: ")
    (write grain)
    (display ", a wait too long from ")
    (display retry-ms)
    (display " ms")
    (newline)
    (cond ((and (eq? grain 'milliseconds) (= retry-ms 3000)) 'read)
          ((and (eq? grain 'whole-seconds) (= retry-ms 2000)) 'read)
          (else (list grain retry-ms)))))

(test-equal "busy-timeout runs first, whatever the list's order: under another's exclusive lock, with busy-timeout last at 1500 ms, synchronous's prepare waits once, at least 1000 ms and under 3000, or 2000 on a whole-second build, then open-database raises &sqlite-busy, naming synchronous's SQL; with no busy-timeout it answers busy at once, as call-with-database does, its procedure never called; under a reserved lock journal-mode wal's step answers busy at once; each leaves the holder alone counted, with its three statements, and once it has closed, nothing counted and no descriptor open"
  (list (list (busy 'open-database "PRAGMA synchronous = 2") 'waited 1 3)
        (list (busy 'open-database "PRAGMA synchronous = 2") 'at-once 1 3)
        (list (busy 'call-with-database "PRAGMA synchronous = 2") 'at-once 1 3)
        'proc-not-called
        (list (busy 'open-database "PRAGMA journal_mode = wal") 'at-once 1 3)
        zero-counts 'descriptors-back)
  (in-dir (lambda (dir)
            (let* ((path (string-append dir "/lock.db"))
                   (called 'proc-not-called)
                   (before (descriptors))
                   (a (under-lock path 'exclusive
                                  (lambda () (open-database path '((synchronous . full) (busy-timeout . 1500))))))
                   (b (under-lock path 'exclusive (lambda () (open-database path '((synchronous . full))))))
                   (c (under-lock path 'exclusive
                                  (lambda () (call-with-database path '((synchronous . full))
                                               (lambda (db) (set! called 'proc-called))))))
                   (d (under-lock path 'reserved (lambda () (open-database path '((journal-mode . wal))))))
                   (after (descriptors)))
              (list (timed a) (timed b) (timed c) called (timed d) (native-counts)
                    (if (equal? after before) 'descriptors-back (list 'descriptors before after)))))))

;; --- no setting applied unasked ----------------------------------------------------------------

(test-equal "no setting is applied unasked (decision 8): a connection opened without busy-timeout keeps SQLite's 0, with no list, with (), with a list of the other five and statement-cache, and through call-with-database; a list naming one setting leaves the other five as a plain open has them"
  (list 0 0 0 0 'as-a-plain-open)
  (in-dir (lambda (dir)
            (let* ((plain (with-db (lambda () (open-database ":memory:")) readings))
                   (a (if (pair? plain) (car plain) plain))
                   (b (with-db (lambda () (open-database ":memory:" '()))
                               (lambda (db) (pragma db "busy_timeout"))))
                   (c (with-db (lambda ()
                                 (open-database (string-append dir "/u.db")
                                                '((foreign-keys . #t) (journal-mode . truncate)
                                                  (synchronous . off) (temp-store . file)
                                                  (trusted-schema . #f) (statement-cache . 4))))
                               (lambda (db) (pragma db "busy_timeout"))))
                   (d (attempt (lambda () (call-with-database ":memory:" '((foreign-keys . #t))
                                            (lambda (db) (pragma db "busy_timeout"))))))
                   (one (with-db (lambda () (open-database ":memory:" '((trusted-schema . #f)))) readings))
                   (e (if (and (list? plain) (list? one) (= (length plain) 6) (= (length one) 6)
                               (equal? (first-n plain 5) (first-n one 5))
                               (equal? (list-ref one 5) 0))
                          'as-a-plain-open
                          (list plain one))))
              (list a b c d e)))))

;; --- depth ------------------------------------------------------------------------------------

(test-equal "each raise site's with-exception-handler handler runs at interrupt depth 1, its who the verb called: a refusal through each verb; a mismatch through each verb; a set that fails, and a mismatch, through applied-settings!"
  (list (at-depth-1 (list 'assertion-violation 'open-database '(unknown-setting nosuch)))
        (at-depth-1 (list 'assertion-violation 'call-with-database '(unknown-setting nosuch)))
        (at-depth-1 (list 'mismatch 'open-database 'journal-mode 'wal 'memory 'library-condition))
        (at-depth-1 (list 'mismatch 'call-with-database 'journal-mode 'wal 'memory 'library-condition))
        (at-depth-1 (list 'sqlite-error 'the-suite 'error 'error "PRAGMA nosuch.foreign_keys = 1"))
        (at-depth-1 (list 'mismatch 'the-suite 'foreign-keys #f #t 'library-condition))
        zero-counts)
  (let* ((on-fresh (lambda (step)
                     (let ((db (open-database ":memory:")))
                       (let ((r (handler-depth (lambda () (applied-settings! 'the-suite db (list step)) db))))
                         (close-answer db)
                         r))))
         (a (handler-depth (lambda () (open-database ":memory:" '((nosuch . 1))))))
         (b (handler-depth (lambda () (call-with-database ":memory:" '((nosuch . 1)) (lambda (db) #f)))))
         (c (handler-depth (lambda () (open-database ":memory:" '((journal-mode . wal))))))
         (d (handler-depth (lambda () (call-with-database ":memory:" '((journal-mode . wal)) (lambda (db) #f)))))
         (e (on-fresh failing-set))
         (f (on-fresh (car (cadr crafted-mismatches)))))
    (list a b c d e f (native-counts))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "open-settings")

(exit (suite-exit-status runner))
