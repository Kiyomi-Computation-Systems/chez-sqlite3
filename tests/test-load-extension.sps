#!r6rs
;;; The suite for load-extension! (ADR-0021), in (chez-sqlite3 private
;;; extension), with the extension tests/extension.c, compiled here by
;;; (extension-build) against the lane's sqlite3ext.h.
;;;
;;;   the build        each variant of tests/extension.c compiled with $CC
;;;                    -Wall -Werror: a missing compiler or header fails
;;;                    this row, and every load row after it, never a skip
;;;   the checks       in order, each refusal from
;;;                    load-extension!: every kind of value for the
;;;                    database, the path and the entry point; U+0000 at
;;;                    every position of each string; every first character
;;;                    but / refused as not absolute, and every path that
;;;                    starts with one let through to the next check; each
;;;                    pair of refusals in order; nothing reaches C
;;;   the opt-in       a connection without it, or with (enable-load-
;;;                    extension . #f), is refused as extension-loading-not-
;;;                    enabled, its message naming the fix, chez_half absent
;;;                    after; and so beside an entry point that
;;;                    sqlite3_auto_extension runs at every open, which turns
;;;                    the C switch on, as Ubuntu's library starts it, where
;;;                    a raw sqlite3_load_extension through native then loads
;;;   the loads        the default entry point, the named one, the derived
;;;                    one, a path without its suffix; chez_half through
;;;                    query; the init counted across loads and connections,
;;;                    and the close unloading the file; each failure's code
;;;                    the call's own, error, its message the slot's as a raw
;;;                    call reads it, never the connection's earlier one
;;;   the held row     a load beside a statement at a row, whose init
;;;                    replaces the functions an earlier load registered:
;;;                    error from the call, the connection's busy left on it,
;;;                    and the condition's message ending with the
;;;                    connection's, read through native; then, nothing held,
;;;                    the replacing load takes, and the cache's statement
;;;                    still answers
;;;   a stand-in       load-extension/with, its binding a stand-in: the call
;;;                    it is given, the handle, the path's and the entry
;;;                    point's C strings, NULL for none, and an empty slot; a
;;;                    slot left empty gives sqlite3_errstr's message; a code
;;;                    that names no error is an assertion violation,
;;;                    (not-an-error CODE); a message on the success path is
;;;                    freed; a copy that raises has its raise raised, the
;;;                    message freed
;;;   the refusals     the wrong thread, &sqlite-wrong-thread before the
;;;                    argument checks and the opt-in, and with everything
;;;                    valid, nothing loaded; a closed connection, before the
;;;                    argument checks; every wait bounded. An engine's
;;;                    remainder taken at every fuel on the owner's thread
;;;                    and finished on another: every refusal there from
;;;                    load-extension!, the opt-in's read among them, and
;;;                    nothing loaded
;;;   the memory       a load, a call and the close leave sqlite3_memory_used
;;;                    as it was; each failure's message is freed, the count
;;;                    as it was before the load. Under make test-memory the
;;;                    gate's Valgrind reads the same process
;;;   depth            each raise site's with-exception-handler handler runs
;;;                    at interrupt depth 1, after every section
;;;
;;; Where the library lacks sqlite3_load_extension, as Apple's does, no
;;; connection can opt in: each load row is printed unavailable, and the
;;; open's refusal asserted in its place (ADR-0005); the checks and the
;;; opt-in's refusal run on every library, since they reach no C. The
;;; loading procedures are reached through eval, under a guard, so the suite
;;; runs against a library that lacks the verb, failing by name. Rows assert
;;; codes, never SQLite's text: a message is only ever compared with another
;;; reading of the same library (ADR-0013), and Apple's dlopen words its
;;; failures its own way.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-ref foreign-procedure foreign-callable foreign-callable-entry-point
              lock-object unlock-object fork-thread make-mutex with-mutex sleep make-time
              get-thread-id disable-interrupts enable-interrupts mkdir current-directory directory-list
              machine-type make-engine)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (extension-build)
        (only (chez-sqlite3 private constants) sqlite-dbconfig-enable-load-extension)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-error-message sqlite-error-sql
              sqlite-error-offset sqlite-closed? sqlite-wrong-thread? sqlite-wrong-thread-owner
              sqlite-wrong-thread-caller sqlite-extensions-unavailable?))

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
(define (reach-value library name)
  (guard (e (#t (list 'unreached name)))
    (eval name (environment library))))

(define (public name) (reach '(chez-sqlite3) name))

(define load-extension! (public 'load-extension!))
(define open-database (public 'open-database))
(define call-with-database (public 'call-with-database))
(define close-database! (public 'close-database!))
(define database? (public 'database?))
(define execute! (public 'execute!))
(define query (public 'query))
(define query-row (public 'query-row))
(define prepare-statement (public 'prepare-statement))
(define step! (public 'step!))
(define finalize-statement! (public 'finalize-statement!))
(define load-extension/with (reach '(chez-sqlite3 private extension) 'load-extension/with))
(define database-cache-count (reach '(chez-sqlite3 private connection) 'database-cache-count))
(define database-extension-loading?
  (reach '(chez-sqlite3 private connection) 'database-extension-loading?))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-out-pointer (reach '(chez-sqlite3 private native) 'call-with-out-pointer))
(define call-with-int-cell (reach '(chez-sqlite3 private native) 'call-with-int-cell))
(define c-string->string (reach '(chez-sqlite3 private native) 'c-string->string))
(define sqlite3-db-config (reach '(chez-sqlite3 private native) 'sqlite3-db-config))
(define sqlite3-free (reach '(chez-sqlite3 private native) 'sqlite3-free))
(define sqlite3-errstr (reach '(chez-sqlite3 private native) 'sqlite3-errstr))
(define sqlite3-errmsg (reach '(chez-sqlite3 private native) 'sqlite3-errmsg))
(define sqlite3-extended-errcode (reach '(chez-sqlite3 private native) 'sqlite3-extended-errcode))
(define sqlite3-memory-used (reach '(chez-sqlite3 private native) 'sqlite3-memory-used))

;; available : Any
;; native's record of sqlite3_load_extension: #t where the library has it,
;; #f where it lacks it, as Apple's does.
(define available (reach-value '(chez-sqlite3 private native) 'load-extension-available?))

;; raw-load-binding : Any
;; native's binding of sqlite3_load_extension, for the suite's own raw
;; calls: a procedure where the library has it.
(define raw-load-binding (reach-value '(chez-sqlite3 private native) 'sqlite3-load-extension))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
;; E as the rows compare it: an &sqlite-error by its who, codes, SQL and
;; offset; &sqlite-closed and &sqlite-wrong-thread by their who; the opt-in
;; open's refusal by its who; an assertion violation by its who and
;; irritants.
(define (what-raised e)
  (cond ((sqlite-extensions-unavailable? e)
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

;; with-db : (-> Database) (Database -> Any) -> Any
;; PROC's answer, or what it raised, given the database OPEN makes, closed
;; after, however PROC ends.
(define (with-db open proc)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda () (attempt (lambda () (set! db (open)) (proc db))))
      (lambda () (when db (close-answer db))))))

(define (plain) (open-database ":memory:"))
(define (opted) (open-database ":memory:" '((enable-load-extension . #t))))

;; loaded : String -> Any
;; What load-extension! of PATH, and of ENTRY when given, answers or raises.
(define (loaded db . args)
  (attempt (lambda () (apply load-extension! db args) 'loaded)))

;; half : Database -> Any
;; chez_half(5) through query: present, answering ((#(2.5))) whole; else
;; absent with the code of query's raise, or what else it answered.
(define (half db)
  (let ((r (guard (e ((sqlite-error? e) (list 'absent (sqlite-error-code e)))
                     (#t (list 'raised (what-raised e))))
             (query db "select chez_half(5)"))))
    (if (equal? r '(#(2.5))) 'present r)))

;; inits : Database -> Any
;; chez_inits() through query-row: the count, or what it raised.
(define (inits db)
  (let ((r (attempt (lambda () (query-row db "select chez_inits()")))))
    (if (and (vector? r) (= (vector-length r) 1)) (vector-ref r 0) r)))

(define (yes-no x) (cond ((eq? x #t) 'yes) ((eq? x #f) 'no) (else (list 'neither x))))

;; message-of : (-> Any) -> Any
;; The &message of what THUNK raised, or (no-message WHAT).
(define (message-of thunk)
  (guard (e ((message-condition? e) (condition-message e))
            (#t (list 'no-message (what-raised e))))
    (thunk)
    'no-raise))

;; contains? : String String -> Boolean
(define (contains? hay needle)
  (let ((n (string-length hay)) (m (string-length needle)))
    (let loop ((i 0))
      (and (<= (+ i m) n)
           (or (string=? (substring hay i (+ i m)) needle) (loop (+ i 1)))))))

;; ends-with? : String String -> Boolean
(define (ends-with? s suffix)
  (let ((n (string-length s)) (m (string-length suffix)))
    (and (>= n m) (string=? (substring s (- n m) n) suffix))))

;; depth-raw : (-> Any) -> (List Any Any)
;; The interrupt depth a with-exception-handler handler of THUNK's raise
;; ran at, depth-1 outside any critical section, and the object raised; or
;; (#f no-raise).
(define no-raise (list 'no-raise))
(define (depth-raw thunk)
  (let* ((at #f)
         (r (guard (e (#t e))
              (with-exception-handler
               (lambda (c)
                 (unless at
                   (set! at (let ((n (disable-interrupts)))
                              (enable-interrupts)
                              (string->symbol (string-append "depth-" (number->string n))))))
                 (raise c))
               (lambda () (thunk) no-raise)))))
    (list at r)))

;; depth-of : (-> Any) -> (List Any Any)
;; depth-raw, the raise shown as what-raised shows it.
(define (depth-of thunk)
  (let ((d (depth-raw thunk)))
    (list (car d) (if (eq? (cadr d) no-raise) 'no-raise (list 'raised (what-raised (cadr d)))))))

;; --- the library, read through native ------------------------------------------------------

;; handle-call : Database (Natural -> Any) -> Any
;; PROC's answer given DB's handle, inside call-with-open-handle, or what it
;; raised.
(define (handle-call db proc)
  (attempt (lambda () (call-with-open-handle 'test-load-extension db proc))))

;; connection-error : Database -> Any
;; DB's own extended code and sqlite3_errmsg, read through native.
(define (connection-error db)
  (handle-call db (lambda (h) (list (sqlite3-extended-errcode h) (c-string->string (sqlite3-errmsg h))))))

;; errstr : Integer -> Any
(define (errstr code)
  (guard (e (#t (list 'raised (describe e))))
    (c-string->string (sqlite3-errstr code))))

;; raw-load : Database String (U String #f) -> Any
;; sqlite3_load_extension of PATH on DB, through native's binding with no
;; check of ours, the entry point ENTRY's C string or NULL: its code and its
;; slot's message, copied, then freed with sqlite3_free; (CODE none) for an
;; empty slot.
(define (raw-load db path entry)
  (handle-call db
    (lambda (h)
      (call-with-c-string 'test-load-extension path
        (lambda (file)
          (let ((call (lambda (proc)
                        (let-values (((code message)
                                      (call-with-out-pointer 'test-load-extension
                                        (lambda (slot) (raw-load-binding h file proc slot)))))
                          (if (eqv? message 0)
                              (list code 'none)
                              (let ((text (c-string->string message)))
                                (sqlite3-free message)
                                (list code text)))))))
            (if entry
                (call-with-c-string 'test-load-extension entry call)
                (call 0))))))))

;; memory-used : -> Any
(define (memory-used) (guard (e (#t (list 'raised (describe e)))) (sqlite3-memory-used)))

;; counts-memory? : Boolean
;; Whether the library keeps a count of its memory: sqlite3_memory_used
;; higher while a connection of the suite's is open than before it, as the
;; memory check's own control asks (ADR-0005). Apple's
;; DEFAULT_MEMSTATUS=0 build keeps none.
(define counts-memory?
  (guard (e (#t #f))
    (let* ((before (sqlite3-memory-used))
           (db (open-database ":memory:"))
           (during (sqlite3-memory-used)))
      (close-database! db)
      (> during before))))

;; memory-verdict : Symbol
;; What held-then-freed must answer on this library.
(define memory-verdict (if counts-memory? 'held-then-freed 'no-count))

;; held-then-freed : Any Any Any -> Any
;; BEFORE, HELD and AFTER, sqlite3_memory_used read before a load, while
;; its message or extension was held, and after it was let go:
;; held-then-freed when the count rose while held and came back to BEFORE;
;; no-count where the library keeps none and all three read alike; else
;; the three.
(define (held-then-freed before held after)
  (cond ((and (integer? before) (integer? held) (integer? after) (> held before) (= after before))
         'held-then-freed)
        ((and (not counts-memory?) (equal? before held) (equal? held after)) 'no-count)
        (else (list 'memory before held after))))

;; memory-noted! : String -> Void
;; Where the library keeps no count, the row NAME's memory part printed
;; unavailable, never passed unseen (ADR-0005).
(define (memory-noted! name)
  (unless counts-memory?
    (display "UNAVAILABLE ")
    (display name)
    (display ", its memory part: this libsqlite3 keeps no count of its memory")
    (newline)))

;; --- the extension ---------------------------------------------------------------------------

;; dir : (U String (List 'raised String))
;; The suite's own scratch directory, removed when the process ends.
(define dir (guard (e (#t (list 'raised (describe e)))) (make-process-temp-directory)))

(define (in-dir name) (if (string? dir) (string-append dir "/" name) "/nonexistent/no-scratch"))

;; built : Any
;; built-where-loadable's answer: each variant's name and path, or the
;; failure; or (unavailable), nothing compiled, where native records no
;; sqlite3_load_extension, as on Apple's library.
(define built
  (if (string? dir)
      (guard (e (#t (list 'raised (describe e)))) (built-where-loadable available dir))
      (list 'no-scratch dir)))

(define ext (extension-path built 'default))
(define ext-named (extension-path built 'named))
(define ext-derived (extension-path built 'derived))
(define ext-failing (extension-path built 'failing))
(define ext-exec-failing (extension-path built 'exec-failing))
(define ext-leaves (extension-path built 'leaves))

;; ext-bare : String
;; The default variant's path without its suffix, which SQLite retries
;; with the suffix appended.
(define ext-bare (in-dir "ext"))

;; The failures' files: none at nosuch; an empty file; a directory; a file
;; that is no shared object.
(define missing (in-dir "nosuch.so"))
(define empty (in-dir "empty.so"))
(define a-directory (in-dir "dir.so"))
(define not-a-library (in-dir "not-a-library.so"))

(define files-made
  (guard (e (#t (list 'raised (describe e))))
    (call-with-port (open-file-output-port empty) (lambda (p) #t))
    (call-with-port (open-file-output-port not-a-library)
      (lambda (p) (put-bytevector p (string->utf8 "no ELF and no Mach-O here\n"))))
    (mkdir a-directory)
    'made))

;; load-row : String Any (-> Any) -> Void
;; The test NAME, EXPECTED against THUNK's answer, on a library that has
;; sqlite3_load_extension. On one without it, NAME is printed UNAVAILABLE,
;; and the open that opts in is asserted refused in its place.
(define (load-row name expected thunk)
  (if (eq? available #t)
      (test-equal name expected (guard (e (#t (list 'raised (what-raised e)))) (thunk)))
      (begin
        (display "UNAVAILABLE ")
        (display name)
        (display ": this libsqlite3 has no sqlite3_load_extension, so no connection can opt in, and the open's refusal is asserted in its place")
        (newline)
        (test-equal (string-append "unavailable, the opt-in's open refused in its place: " name)
          '(raised (extensions-unavailable open-database library-condition))
          (attempt-open opted)))))

(test-begin "load-extension")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(if (eq? available #f)
    (begin
      (display "UNAVAILABLE the extension's build: this libsqlite3 has no sqlite3_load_extension, so no connection can load it; the build is named unavailable and the opt-in's refusal asserted in its place")
      (newline)
      (test-equal "unavailable, the build not made and the opt-in's open refused in its place: tests/extension.c compiles"
        (list '(unavailable) '(raised (extensions-unavailable open-database library-condition)) 'made)
        (list built (attempt-open opted) files-made)))
    (test-equal "tests/extension.c compiles, each of its six variants, with $CC -Wall -Werror against this lane's sqlite3ext.h, each a file at its path, the library having sqlite3_load_extension; the failures' files are made"
      (list '(default named derived failing exec-failing leaves) '(yes yes yes yes yes yes) 'made)
      (list (if (list? built) (map (lambda (b) (if (pair? b) (car b) b)) built) built)
            (if (list? built) (map (lambda (b) (yes-no (and (pair? b) (string? (cdr b)) (file-exists? (cdr b))))) built) built)
            files-made)))

(test-equal "the build's decision: where native records no sqlite3_load_extension, built-where-loadable answers (unavailable), and compiles and writes nothing, its directory left empty; where it records one, or its record is unread, it builds, so a missing compiler or header fails there, asked only where this library has the entry point, so that the build is never required where nothing loads it"
  (list '(unavailable) '() (if (eq? available #f) 'not-asked 'builds) (if (eq? available #f) 'not-asked 'builds))
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (scratch)
       (let* ((none (built-where-loadable #f scratch))
              (left (directory-list scratch))
              (some (if (eq? available #f) 'not-asked (built-where-loadable #t scratch)))
              (unread (if (eq? available #f)
                          'not-asked
                          (built-where-loadable '(unreached load-extension-available?) scratch))))
         (list none left
               (if (and (list? some) (= (length some) 6) (for-all pair? some)) 'builds some)
               (if (and (list? unread) (= (length unread) 6) (for-all pair? unread)) 'builds unread)))))))

(test-equal "native records sqlite3_load_extension as a boolean; where it is #f, the load rows say so"
  'boolean
  (begin
    (unless (eq? available #t)
      (display "UNAVAILABLE the loads: this libsqlite3 has no sqlite3_load_extension, so no connection opts in; the checks and the opt-in's refusal still run")
      (newline))
    (if (boolean? available) 'boolean available)))

;; --- the checks: the database ------------------------------------------------------------------

;; kinds : (Listof (Pairof Any Any))
;; A value of every kind, each with its shown-value, the suite's own: a
;; refusal names a string, a list holding one, a bytevector, a vector, a
;; procedure or any other object by its kind, and an atom, or a list of
;; atoms, as itself.
(define kinds
  (list (cons 42 42) (cons 1.5 1.5) (cons #f #f) (cons #t #t) (cons #\a #\a) (cons 'sym 'sym)
        (cons '() '()) (cons '(1 2) '(1 2)) (cons '("x") '(kind list)) (cons '(1 . 2) '(kind list))
        (cons "a string" '(kind string)) (cons (u8-list->bytevector (list 47)) '(kind bytevector))
        (cons (vector 47) '(kind vector)) (cons car '(kind procedure))))

;; in-order : (Any -> Any) (Listof Any) -> (Listof Any)
;; PROC called on each of ITEMS, first to last, by a named let, never map,
;; whose order of calls is not fixed: a call of the verb is an effect.
;; Their answers, in order.
(define (in-order proc items)
  (let loop ((rest items) (found '()))
    (if (null? rest)
        (reverse found)
        (loop (cdr rest) (cons (proc (car rest)) found)))))

;; refusals-of : (Any -> Any) (Listof (Pairof Any Any)) -> (Listof Any)
;; Each value of VALUES through CALL, in order: what it answered or raised.
(define (refusals-of call values)
  (let loop ((rest values) (found '()))
    (if (null? rest)
        (reverse found)
        (loop (cdr rest) (cons (call (car (car rest))) found)))))

(define (refused irritants) (list 'raised (list 'assertion-violation 'load-extension! irritants)))

(define (each-refused rule values)
  (map (lambda (v) (refused (list rule (cdr v)))) values))

(test-equal "a database is checked first: every kind of value that is no database is refused, not-a-database, by its kind, with a valid path, a bad one, and an entry point; a statement is no database"
  (append (each-refused 'not-a-database kinds)
          (each-refused 'not-a-database kinds)
          (each-refused 'not-a-database kinds)
          (list (refused '(not-a-database (kind other)))))
  (let ((statement-refusal
         (with-db plain
           (lambda (db)
             (let ((st (prepare-statement db "select 1")))
               (let ((r (loaded st ext)))
                 (finalize-statement! st)
                 r))))))
    (append (refusals-of (lambda (v) (loaded v ext)) kinds)
            (refusals-of (lambda (v) (loaded v 42)) kinds)
            (refusals-of (lambda (v) (loaded v ext "chez_named_init")) kinds)
            (list statement-refusal))))

;; --- the checks: the path ---------------------------------------------------------------------

;; non-strings : (Listof (Pairof Any Any))
(define non-strings (filter (lambda (k) (not (string? (car k)))) kinds))

(test-equal "the path is a string: every other kind of value is refused, path-not-a-string, by its kind, on a connection that did not opt in and on one that did, with an entry point or without"
  (append (each-refused 'path-not-a-string non-strings)
          (each-refused 'path-not-a-string non-strings)
          (each-refused 'path-not-a-string non-strings))
  (append (with-db plain (lambda (db) (refusals-of (lambda (v) (loaded db v)) non-strings)))
          (if (eq? available #t)
              (with-db opted (lambda (db) (refusals-of (lambda (v) (loaded db v)) non-strings)))
              (each-refused 'path-not-a-string non-strings))
          (with-db plain (lambda (db) (refusals-of (lambda (v) (loaded db v 42)) non-strings)))))

;; with-nul-at : String Natural -> String
;; TEXT with U+0000 put before its character I, or at its end for its length.
(define (with-nul-at text i)
  (string-append (substring text 0 i) (string #\nul) (substring text i (string-length text))))

;; nul-strings : String -> (Listof String)
;; TEXT with U+0000 at every position, 0 to its length, then two together.
(define (nul-strings text)
  (let loop ((i (string-length text)) (found (list (string-append (string #\nul #\nul) text))))
    (if (< i 0) found (loop (- i 1) (cons (with-nul-at text i) found)))))

(test-equal "a path holding U+0000 at any position, first or last or between, or twice, is refused, path-holds-nul, before it is judged absolute: so a relative path with one is refused the same; on a connection that opted in and one that did not, nothing loaded"
  (list (map (lambda (s) (refused '(path-holds-nul (kind string)))) (nul-strings "/x/ext.so"))
        (map (lambda (s) (refused '(path-holds-nul (kind string)))) (nul-strings "x.so"))
        (map (lambda (s) (refused '(path-holds-nul (kind string)))) (nul-strings ext))
        (if (eq? available #t) '(absent error) 'not-asked))
  (let ((on-opted (if (eq? available #t)
                      (with-db opted
                        (lambda (db)
                          (let* ((r (in-order (lambda (s) (loaded db s)) (nul-strings ext)))
                                 (h (half db)))
                            (list r h))))
                      (list (map (lambda (s) (refused '(path-holds-nul (kind string)))) (nul-strings ext))
                            'not-asked))))
    (list (with-db plain (lambda (db) (in-order (lambda (s) (loaded db s)) (nul-strings "/x/ext.so"))))
          (with-db plain (lambda (db) (in-order (lambda (s) (loaded db s)) (nul-strings "x.so"))))
          (if (pair? on-opted) (car on-opted) on-opted)
          (if (pair? on-opted) (cadr on-opted) on-opted))))

;; firsts : (Listof Char)
;; Every character from U+0001 to U+007F but /, and a few beyond: é, λ,
;; U+FEFF, which Chez's UTF-8 decoders drop at a string's start, and
;; U+FF0F, the fullwidth solidus.
(define firsts
  (append (let loop ((c 127) (found '()))
            (cond ((= c 0) found)
                  ((= c (char->integer #\/)) (loop (- c 1) found))
                  (else (loop (- c 1) (cons (integer->char c) found)))))
          (list #\xE9 #\x3BB #\xFEFF #\xFF0F)))

(test-equal "the path is absolute, its first character /: \"\", a bare name, ./ and ../ paths, and a path starting with every other character from U+0001 to U+007F, and with é, λ, U+FEFF and U+FF0F, are refused, path-not-absolute, by its kind; each path that starts with / is let through, to the opt-in's refusal on a connection that did not opt in"
  (list (map (lambda (s) (refused '(path-not-absolute (kind string))))
             '("" "ext.so" "ext" "./ext.so" "../ext.so" "x/ext.so" "~/ext.so" " /ext.so" "\\ext.so"))
        (map (lambda (c) (refused '(path-not-absolute (kind string)))) firsts)
        (map (lambda (s) (refused '(extension-loading-not-enabled)))
             (list "/" "//" "/ext.so" "/./ext.so" "/../x" ext ext-bare missing)))
  (with-db plain
    (lambda (db)
      (list (in-order (lambda (s) (loaded db s))
                 '("" "ext.so" "ext" "./ext.so" "../ext.so" "x/ext.so" "~/ext.so" " /ext.so" "\\ext.so"))
            (in-order (lambda (c) (loaded db (string-append (string c) "/ext.so"))) firsts)
            (in-order (lambda (s) (loaded db s))
                 (list "/" "//" "/ext.so" "/./ext.so" "/../x" ext ext-bare missing))))))

;; ext-relative : String
;; The default variant's path written relative to the working directory:
;; up to / by one .. for each of its parts, then down to the file. dlopen
;; would load it.
(define ext-relative
  (let* ((cwd (current-directory))
         (ups (let loop ((i 0) (n 0))
                (cond ((= i (string-length cwd)) n)
                      ((and (char=? (string-ref cwd i) #\/)
                            (< (+ i 1) (string-length cwd))
                            (not (char=? (string-ref cwd (+ i 1)) #\/)))
                       (loop (+ i 1) (+ n 1)))
                      (else (loop (+ i 1) n))))))
    (let loop ((n ups) (prefix ""))
      (if (= n 0)
          (string-append prefix (substring ext 1 (string-length ext)))
          (loop (- n 1) (string-append prefix "../"))))))

(load-row "on a connection that opted in, a relative path, a bare name and \"\" are refused, path-not-absolute, nothing loaded, though a raw sqlite3_load_extension through native loads the default variant by the relative path on another such connection: chez_half stays absent"
  (list (map (lambda (s) (refused '(path-not-absolute (kind string)))) '(1 2 3 4 5))
        '(absent error) '(0 none))
  (lambda ()
    (let ((refusals (with-db opted
                      (lambda (db)
                        (let ((r (in-order (lambda (s) (loaded db s))
                                      (list ext-relative (string-append "./" ext-relative) "ext.so" "ext" ""))))
                          (list r (half db))))))
          (raw (with-db opted (lambda (db) (raw-load db ext-relative #f)))))
      (append refusals (list raw)))))

;; --- the checks: the entry point ------------------------------------------------------------------

(test-equal "the entry point, when given, is a string: every other kind of value is refused, entry-point-not-a-string, by its kind, #f among them, after a valid path, on a connection that did not opt in and on one that did"
  (append (each-refused 'entry-point-not-a-string non-strings)
          (each-refused 'entry-point-not-a-string non-strings))
  (append (with-db plain (lambda (db) (refusals-of (lambda (v) (loaded db ext v)) non-strings)))
          (if (eq? available #t)
              (with-db opted (lambda (db) (refusals-of (lambda (v) (loaded db ext v)) non-strings)))
              (each-refused 'entry-point-not-a-string non-strings))))

(test-equal "an entry point holding U+0000 at any position, or twice, is refused, entry-point-holds-nul; a string without one, \"\" among them, is let through, to the opt-in's refusal"
  (list (map (lambda (s) (refused '(entry-point-holds-nul (kind string)))) (nul-strings "chez_named_init"))
        (map (lambda (s) (refused '(extension-loading-not-enabled))) '("" "chez_named_init" "x")))
  (with-db plain
    (lambda (db)
      (list (in-order (lambda (s) (loaded db ext-named s)) (nul-strings "chez_named_init"))
            (in-order (lambda (s) (loaded db ext-named s)) '("" "chez_named_init" "x"))))))

;; --- the checks' order -----------------------------------------------------------------------------

(test-equal "the checks' order: the path before the entry point, U+0000 before absolute, the entry point before the opt-in, each with every later argument wrong too"
  (list (refused '(path-not-a-string 42))
        (refused '(path-holds-nul (kind string)))
        (refused '(path-not-absolute (kind string)))
        (refused '(entry-point-not-a-string 42))
        (refused '(entry-point-holds-nul (kind string)))
        (refused '(path-holds-nul (kind string))))
  (with-db plain
    (lambda (db)
      (list (loaded db 42 42)
            (loaded db (string #\x #\nul) 42)
            (loaded db "x.so" 42)
            (loaded db ext 42)
            (loaded db ext (string #\nul))
            (loaded db (string #\nul #\/) (string #\nul))))))

;; --- the opt-in ---------------------------------------------------------------------------------

(test-equal "a connection opened without the opt-in, and one opened with (enable-load-extension . #f), through each verb, is refused, extension-loading-not-enabled, for each form and each variant, and chez_half is absent after"
  (list (list (refused '(extension-loading-not-enabled)) (refused '(extension-loading-not-enabled))
              (refused '(extension-loading-not-enabled)) '(absent error))
        (list (refused '(extension-loading-not-enabled)) (refused '(extension-loading-not-enabled))
              (refused '(extension-loading-not-enabled)) '(absent error))
        (list (refused '(extension-loading-not-enabled)) '(absent error)))
  (let ((tried (lambda (db)
                 (let* ((a (loaded db ext))
                        (b (loaded db ext-named "chez_named_init"))
                        (c (loaded db ext-derived))
                        (h (half db)))
                   (list a b c h)))))
    (let* ((none (with-db plain tried))
           (false (with-db (lambda () (open-database ":memory:" '((enable-load-extension . #f)))) tried))
           (cwd (attempt (lambda ()
                           (call-with-database ":memory:" '((enable-load-extension . #f) (defensive . #t))
                             (lambda (db)
                               (let* ((r (loaded db ext))
                                      (h (half db)))
                                 (list r h))))))))
      (list none false cwd))))

(test-equal "the opt-in's refusal names the fix: its message holds (enable-load-extension . #t), written out here"
  'names-the-fix
  (with-db plain
    (lambda (db)
      (let ((m (message-of (lambda () (load-extension! db ext)))))
        (if (and (string? m) (contains? m "(enable-load-extension . #t)")) 'names-the-fix m)))))

;; --- the opt-in judged with the C switch on
;; -------------------------------------------------------- Ubuntu's library opens every connection
;; with ENABLE_LOAD_EXTENSION's C switch on, and there the verb's own check is all that stops a
;; load. Every other library this suite meets starts it at 0, where SQLite itself refuses a load,
;; "not authorized", so a verb that dropped its check would show only on the main lane. Here an
;; entry point sqlite3_auto_extension runs at every open turns the switch on, through native's
;; binding, so every lane is Ubuntu's: a raw sqlite3_load_extension through native then loads on
;; that connection, where the verb refuses. A libsqlite3 can refuse the registration, Apple's 3.51.0
;; answering 21, and then the row is printed unavailable and the refusal, 21, asserted in its place
;; (ADR-0005). It is unregistered by sqlite3_reset_auto_extension, and unlocked once.

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_auto_extension(void (*xEntryPoint)(void))
(define auto-extension
  (bound 'sqlite3_auto_extension (foreign-procedure "sqlite3_auto_extension" (uptr) int)))
;; void sqlite3_reset_auto_extension(void)
(define reset-auto-extension
  (bound 'sqlite3_reset_auto_extension (foreign-procedure "sqlite3_reset_auto_extension" () void)))

;; switch-answers : (Listof Any)
;; What each of switch-on's calls answered, newest first: (code cell), or
;; (raised TEXT).
(define switch-answers '())

;; int (*xEntryPoint)(sqlite3 *db, const char **pzErrMsg, const sqlite3_api_routines *pThunk)
;; The new connection's ENABLE_LOAD_EXTENSION set to 1, its answer and cell
;; noted; 0, always.
(define switch-on
  (foreign-callable __collect_safe
    (lambda (db message api)
      (let ((noted (guard (e (#t (list 'raised (describe e))))
                     (call-with-values
                      (lambda ()
                        (call-with-int-cell 'test-load-extension 9
                          (lambda (c) (sqlite3-db-config db sqlite-dbconfig-enable-load-extension 1 c))))
                      list))))
        (set! switch-answers (cons noted switch-answers))
        0))
    (uptr uptr uptr) int))

;; switch-read : Database -> Any
;; ENABLE_LOAD_EXTENSION's state on DB, by a -1 read through native.
(define (switch-read db)
  (handle-call db
    (lambda (h)
      (call-with-values
       (lambda ()
         (call-with-int-cell 'test-load-extension 77
           (lambda (c) (sqlite3-db-config h sqlite-dbconfig-enable-load-extension -1 c))))
       list))))

;; switched-run : -> Any
;; With switch-on registered: on a connection opened without the opt-in,
;; the switch read; the verb's three forms; chez_half; then a raw load of
;; the default variant through native, and chez_half again; and the same
;; on one opened with the opt-in's #f, the verb's first form only. Or
;; (refused CODE).
(define (switched-run)
  (lock-object switch-on)
  (let ((rc (guard (e (#t (list 'raised (describe e))))
              (auto-extension (foreign-callable-entry-point switch-on)))))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (if (not (eqv? rc 0))
            (list 'refused rc)
            (list (with-db plain
                    (lambda (db)
                      (let* ((switch (switch-read db))
                             (verb (list (loaded db ext) (loaded db ext-named "chez_named_init")
                                         (loaded db ext-derived)))
                             (before (half db))
                             (raw (raw-load db ext #f))
                             (after (half db)))
                        (list switch verb before raw after))))
                  (with-db (lambda () (open-database ":memory:" '((enable-load-extension . #f))))
                    (lambda (db)
                      (let* ((switch (switch-read db))
                             (verb (loaded db ext))
                             (before (half db)))
                        (list switch verb before)))))))
      (lambda ()
        (when (eqv? rc 0) (reset-auto-extension))
        (unlock-object switch-on)))))

(define switched
  (if (eq? available #t)
      (guard (e (#t (list 'raised (describe e)))) (switched-run))
      'not-run))

(define (switch-refused?) (and (pair? switched) (eq? (car switched) 'refused)))

(load-row "the opt-in judged with the C switch on: beside an entry point every open runs, which turns ENABLE_LOAD_EXTENSION's switch on as Ubuntu's library opens a connection, each of its calls answering 0 with the cell 1, a connection without the opt-in reads the switch 1, yet the verb refuses it, extension-loading-not-enabled, for each form, and chez_half is absent; a raw sqlite3_load_extension through native then loads there, code 0, an empty slot, and chez_half is present; with the opt-in's #f, the same refusal"
  (if (switch-refused?)
      (list (list 'refused 21) 'no-calls)
      (list (list (list (list 0 1)
                        (list (refused '(extension-loading-not-enabled))
                              (refused '(extension-loading-not-enabled))
                              (refused '(extension-loading-not-enabled)))
                        '(absent error) '(0 none) 'present)
                  (list (list 0 1) (refused '(extension-loading-not-enabled)) '(absent error)))
            'every-call-answered))
  (lambda ()
    (when (switch-refused?)
      (display "UNAVAILABLE the opt-in judged with the C switch on: this libsqlite3 refused sqlite3_auto_extension (")
      (write (cadr switched))
      (display "), so its refusal, 21, is asserted in its place")
      (newline))
    (list switched
          (cond ((null? switch-answers) 'no-calls)
                ((for-all (lambda (a) (equal? a '(0 1))) switch-answers) 'every-call-answered)
                (else (list 'answers switch-answers))))))

;; --- the loads ------------------------------------------------------------------------------------

(load-row "the default entry point: the default variant loaded with none named answers nothing, sqlite3_extension_init found by SQLite's search; chez_half(5) answers 2.5 through query, and chez_inits() 1; the load leaves every count but the connection's zero, no block and no statement of its own"
  (list '((block . 0) (connection . 1) (statement . 0)) 'loaded '((block . 0) (connection . 1) (statement . 0))
        'present 1)
  (lambda ()
    (with-db opted
      (lambda (db)
        (let* ((c0 (native-counts))
               (r (loaded db ext))
               (c1 (native-counts))
               (h (half db))
               (n (inits db)))
          (list c0 r c1 h n))))))

(load-row "a named entry point: the named variant, whose file holds no entry point SQLite's search finds, loaded with chez_named_init answers nothing and chez_half answers; loaded with none named, it fails, error, and chez_half stays absent"
  (list (list 'loaded 'present)
        (list (list 'raised (list 'sqlite-error 'load-extension! 'error 'error #f #f)) '(absent error)))
  (lambda ()
    (list (with-db opted (lambda (db) (let* ((r (loaded db ext-named "chez_named_init"))) (list r (half db)))))
          (with-db opted (lambda (db) (let* ((r (loaded db ext-named))) (list r (half db))))))))

(load-row "the derived entry point: the file libchezext loaded with none named answers nothing, sqlite3_chezext_init found by the name SQLite derives from it, and chez_half answers"
  (list 'loaded 'present)
  (lambda ()
    (with-db opted (lambda (db) (let* ((r (loaded db ext-derived))) (list r (half db)))))))

(load-row "a path without its suffix: the default variant's path with its suffix left off loads, SQLite trying the path, then the path with the suffix appended, and chez_half answers"
  (list 'loaded 'present)
  (lambda ()
    (with-db opted (lambda (db) (let* ((r (loaded db ext-bare))) (list r (half db)))))))

(load-row "the init counted across loads and connections: the default variant loaded twice into one connection counts 1 then 2, each load running the init again; a second connection has no chez_half until its own load, which counts 3; both closed, the file is unloaded, and a third connection's load counts 1 again"
  (list 1 2 '(absent error) 3 2 'closed 1)
  (lambda ()
    (let* ((a (opted))
           (b (opted))
           (one (begin (load-extension! a ext) (inits a)))
           (two (begin (load-extension! a ext) (inits a)))
           (b-before (half b))
           (three (begin (load-extension! b ext) (inits b)))
           (connections (cdr (assq 'connection (native-counts)))))
      (close-database! a)
      (close-database! b)
      (let* ((c (opted))
             (again (begin (load-extension! c ext) (inits c))))
        (close-database! c)
        (list one two b-before three connections
              (if (equal? (native-counts) zero-counts) 'closed (native-counts))
              again)))))

;; mac? : Boolean
;; Whether Chez runs on macOS, its machine type ending in osx.
(define mac?
  (let* ((name (symbol->string (machine-type))) (n (string-length name)))
    (and (>= n 3) (string=? (substring name (- n 3) n) "osx"))))

;; dlsym-stable? : Boolean
;; Whether dlsym's failure reads the same at a second load: everywhere but
;; macOS, where it names the handle dlopen gave, not the file, which a
;; second load need not share.
(define dlsym-stable? (not mac?))

;; failure-cases : (Listof (List String String (Listof String) Boolean))
;; Each failure: what it is, the path, the entry point given, if any, and
;; whether its message names only what the load was given, so that a
;; second load's reads the same: every case's, but an entry point the file
;; lacks, dlsym's failure, on macOS.
(define failure-cases
  (list (list "a path no file stands at" missing '() #t)
        (list "an empty file" empty '() #t)
        (list "a directory" a-directory '() #t)
        (list "a file that is no shared object" not-a-library '() #t)
        (list "the named variant with none named" ext-named '() dlsym-stable?)
        (list "the default variant with an entry point it lacks" ext '("chez_nothing_init") dlsym-stable?)
        (list "the default variant with the entry point \"\"" ext '("") dlsym-stable?)
        (list "the failing variant, whose init sets its message and answers SQLITE_ERROR" ext-failing '() #t)))

(load-row "each failure raises &sqlite-error from load-extension!, code error and extended code error, the call's own answer, with no SQL and no offset: a path no file stands at, an empty file, a directory, a file that is no shared object, an entry point the file lacks, the derived name absent, \"\", and an init that fails; its message is the slot's text exactly as a raw sqlite3_load_extension through native, answering 1, reads it on another connection, dlsym's failures among them, but on a Mac, where dlsym's message names a handle, a message as the raw call gives one; chez_half is absent after each"
  (map (lambda (c) (list 1 (list 'raised (list 'sqlite-error 'load-extension! 'error 'error #f #f))
                         (if (cadddr c) 'the-raw-calls-message 'a-message-as-the-raw-calls)
                         '(absent error)))
       failure-cases)
  (lambda ()
    (let loop ((rest failure-cases) (found '()))
      (if (null? rest)
          (reverse found)
          (let* ((c (car rest))
                 (path (cadr c))
                 (entry (caddr c))
                 (raw (with-db opted (lambda (db) (raw-load db path (if (null? entry) #f (car entry))))))
                 (r (with-db opted
                      (lambda (db)
                        (let* ((m (guard (e ((sqlite-error? e)
                                             (list (list 'raised (what-raised e)) (sqlite-error-message e)))
                                            (#t (list (list 'raised (what-raised e)) 'no-message)))
                                    (apply load-extension! db path entry)
                                    (list 'loaded 'no-message)))
                               (h (half db)))
                          (list (if (pair? raw) (car raw) raw)
                                (car m)
                                (cond ((not (and (pair? raw) (= (length raw) 2) (string? (cadr raw))
                                                 (string? (cadr m))))
                                       (list 'messages (cadr m) raw))
                                      ((equal? (cadr m) (cadr raw)) (if (cadddr c) 'the-raw-calls-message 'a-message-as-the-raw-calls))
                                      ((not (cadddr c)) 'a-message-as-the-raw-calls)
                                      (else (list 'messages (cadr m) raw)))
                                h))))))
            (loop (cdr rest) (cons r found)))))))

(load-row "a failure's code is the call's own, never the connection's: after a unique constraint's failure on the connection, whose own extended code reads constraint-unique, 2067, through native, a load of a path no file stands at raises error, extended code error; its message is the raw call's, which answered 1, and does not end with the connection's own, which the load leaves as it was"
  (list 'failed (list 2067 'a-message) 1
        (list 'raised (list 'sqlite-error 'load-extension! 'error 'error #f #f))
        'the-raw-calls-message 'not-the-connections 'left-as-it-was)
  (lambda ()
    (with-db opted
      (lambda (db)
        (execute! db "create table u (x unique)")
        (execute! db "insert into u values (1)")
        (let* ((failed (guard (e ((sqlite-error? e) 'failed)) (execute! db "insert into u values (1)") 'not-failed))
               (own (connection-error db))
               (raw (raw-load db missing #f))
               (m (guard (e ((sqlite-error? e) (list (list 'raised (what-raised e)) (sqlite-error-message e)))
                            (#t (list (list 'raised (what-raised e)) 'no-message)))
                    (load-extension! db missing)
                    (list 'loaded 'no-message)))
               (after (connection-error db)))
          (list failed
                (if (and (list? own) (string? (cadr own))) (list (car own) 'a-message) own)
                (if (pair? raw) (car raw) raw)
                (car m)
                (if (and (pair? raw) (equal? (cadr m) (cadr raw))) 'the-raw-calls-message (list 'messages (cadr m) raw))
                (if (and (string? (cadr m)) (list? own) (string? (cadr own)) (not (ends-with? (cadr m) (cadr own))))
                    'not-the-connections
                    (list 'message (cadr m) own))
                (if (equal? after own) 'left-as-it-was (list 'after after own))))))))

;; --- the held row --------------------------------------------------------------------------------

(load-row "a load beside a held row: with a statement of the connection at a row, the default variant's first load takes; its second, whose init replaces the functions the first registered, raises &sqlite-error error, extended code error, the call's own, while the connection's own code reads busy, 5, through native, its message read there too; the condition's message ends with the connection's message, and is longer; then, the row let go, a third load takes, replacing the functions, and the cache's statement, prepared before it, still answers, the cache holding it as before"
  (list #t 'loaded 'present
        (list 'raised (list 'sqlite-error 'load-extension! 'error 'error #f #f))
        5 'ends-with-the-connections #f 'loaded '(#(4.0)) '(#(4.0)) 2 2)
  (lambda ()
    (with-db opted
      (lambda (db)
        (let* ((st (prepare-statement db "select 1 union all select 2"))
               (at-row (step! st))
               (first (loaded db ext))
               (present (half db))
               (cached (query db "select chez_half(8)"))
               (m (guard (e ((sqlite-error? e) (list (list 'raised (what-raised e)) (sqlite-error-message e)))
                            (#t (list (list 'raised (what-raised e)) 'no-message)))
                    (load-extension! db ext)
                    (list 'loaded 'no-message)))
               (own (connection-error db))
               (count-before (database-cache-count db))
               (let-go (begin (finalize-statement! st) #f))
               (third (loaded db ext))
               (answers (query db "select chez_half(8)"))
               (count-after (database-cache-count db)))
          (list at-row first present (car m)
                (if (list? own) (car own) own)
                (if (and (string? (cadr m)) (list? own) (string? (cadr own))
                         (ends-with? (cadr m) (cadr own))
                         (> (string-length (cadr m)) (string-length (cadr own))))
                    'ends-with-the-connections
                    (list 'message (cadr m) own))
                let-go third cached answers count-before count-after))))))

;; held-raw : -> Any
;; The held row's second load made raw, through native, on a connection of
;; its own: a statement at a row, the default variant loaded twice, the
;; second's code and slot; then the connection's own extended code and
;; message.
(define (held-raw)
  (with-db opted
    (lambda (db)
      (let* ((st (prepare-statement db "select 1 union all select 2"))
             (at-row (step! st))
             (first (raw-load db ext #f))
             (second (raw-load db ext #f))
             (own (connection-error db)))
        (finalize-statement! st)
        (list at-row first second own)))))

(load-row "the held row's message, whole, from two readings of the library: the raw second load beside a held row answers 1 with the slot's \"error during initialization: \" text, which ends in a space, the connection then reading busy; the verb's message is that slot text followed at once by the connection's own message"
  (list (list #t '(0 none) 1 5) 'slot-text-then-the-connections)
  (lambda ()
    (let ((raw (held-raw))
          (verb (with-db opted
                  (lambda (db)
                    (let* ((st (prepare-statement db "select 1 union all select 2"))
                           (at-row (step! st))
                           (first (load-extension! db ext))
                           (m (guard (e ((sqlite-error? e) (sqlite-error-message e)))
                                (load-extension! db ext)
                                'no-raise))
                           (own (connection-error db)))
                      (finalize-statement! st)
                      (list m own))))))
      (if (and (list? raw) (= (length raw) 4) (list? (caddr raw)) (list? (cadddr raw))
               (list? verb) (string? (car verb)) (list? (cadr verb)))
          (let ((slot (cadr (caddr raw))))
            (list (list (car raw) (cadr raw) (car (caddr raw)) (car (cadddr raw)))
                  (if (and (string? slot) (ends-with? slot " ")
                           (equal? (car verb) (string-append slot (cadr (cadr verb)))))
                      'slot-text-then-the-connections
                      (list 'messages slot verb))))
          (list raw verb)))))

;; int sqlite3_prepare_v2(sqlite3*, const char *zSql, int nByte, sqlite3_stmt **, const char **pzTail)
(define prepare-v2
  (bound 'sqlite3_prepare_v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int)))

;; failed-prepare! : Natural -> Any
;; SQL that prepares nothing, select from, prepared raw on the connection
;; whose handle is H: its code, 1, which leaves the connection's own error
;; at it; the statement, NULL.
(define (failed-prepare! h)
  (call-with-c-string 'test-load-extension "select from"
    (lambda (sql)
      (let-values (((code statement)
                    (call-with-out-pointer 'test-load-extension
                      (lambda (slot) (prepare-v2 h sql -1 slot 0)))))
        (list code statement)))))

(load-row "a slot's text that ends in no space joins the connection's message with \": \": a stand-in that makes the real load of the failing variant, whose slot reads \"error during initialization: chez_failing refused\", then a raw prepare that fails on the connection, a fresh one whose code read 0, then answers 1, raises error, its message the raw call's slot text, \": \", and the connection's own message after, read through native"
  (list '(0 "not an error") '(1 0) 'joined-by-a-colon)
  (lambda ()
    (let ((raw (with-db opted (lambda (db) (raw-load db ext-failing #f)))))
      (with-db opted
        (lambda (db)
          (let* ((fresh (connection-error db))
                 (prepared #f)
                 (load (lambda (h f p s)
                         (raw-load-binding h f p s)
                         (set! prepared (failed-prepare! h))
                         1))
                 (m (guard (e ((sqlite-error? e) (sqlite-error-message e)))
                      (load-extension/with load c-string->string db ext-failing)
                      'no-raise))
                 (own (connection-error db)))
            (list fresh prepared
                  (if (and (list? raw) (string? (cadr raw)) (not (ends-with? (cadr raw) " "))
                           (list? own) (string? (cadr own)) (string? m)
                           (equal? m (string-append (cadr raw) ": " (cadr own))))
                      'joined-by-a-colon
                      (list 'messages m raw own)))))))))

(load-row "SQL's load_extension() stays refused on a connection that opted in: called through query with the default variant's path, it raises &sqlite-error error, and chez_half stays absent"
  (list '(raised (sqlite-error query error error "select load_extension(?)" #f)) '(absent error))
  (lambda ()
    (with-db opted
      (lambda (db)
        (let* ((r (attempt (lambda () (query db "select load_extension(?)" ext))))
               (h (half db)))
          (list r h))))))

;; after-a-failed-statement : Database -> Any
;; A failed statement on DB, select from, which fails at its prepare, so
;; DB's own extended code and message are that failure's; then DB's own,
;; read through native.
(define (after-a-failed-statement db)
  (let ((failed (guard (e ((sqlite-error? e) (sqlite-error-code e))) (execute! db "select from") 'not-failed)))
    (list failed (let ((own (connection-error db))) (if (list? own) (car own) own)))))

(load-row "an init that makes a call that succeeds, then fails: the exec-failing variant's init runs select 1 through sqlite3_exec, which leaves the connection's code at 0, then answers SQLITE_ERROR with its own message; after a failed statement on the connection, whose own code read error, 1, the verb raises error, and its message is the slot's alone, exactly as a raw sqlite3_load_extension through native, answering 1, reads it on another connection in the same state: the connection's code, changed across the call to 0, names no error, so its message is not appended; the connection's code after reads 0"
  (list '(error 1) '(error 1) 1 '(raised (sqlite-error load-extension! error error #f #f))
        'the-raw-calls-message 0)
  (lambda ()
    (let* ((raw (with-db opted
                  (lambda (db)
                    (let* ((state (after-a-failed-statement db))
                           (r (raw-load db ext-exec-failing #f)))
                      (list state r)))))
           (verb (with-db opted
                   (lambda (db)
                     (let* ((state (after-a-failed-statement db))
                            (m (guard (e ((sqlite-error? e)
                                          (list (list 'raised (what-raised e)) (sqlite-error-message e)))
                                         (#t (list (list 'raised (what-raised e)) 'no-message)))
                                 (load-extension! db ext-exec-failing)
                                 (list 'loaded 'no-message)))
                            (after (connection-error db)))
                       (list state m (if (list? after) (car after) after)))))))
      (if (and (list? raw) (= (length raw) 2) (list? (cadr raw)) (list? verb) (= (length verb) 3))
          (let ((raw-code (car (cadr raw))) (raw-text (cadr (cadr raw))) (m (cadr verb)))
            (list (car raw) (car verb) raw-code (car m)
                  (if (and (string? raw-text) (equal? (cadr m) raw-text)) 'the-raw-calls-message
                      (list 'messages (cadr m) raw-text))
                  (caddr verb)))
          (list raw verb)))))

;; int sqlite3_finalize(sqlite3_stmt*), native's, and
;; sqlite3_stmt *sqlite3_next_stmt(sqlite3*, sqlite3_stmt*)
(define sqlite3-finalize (reach '(chez-sqlite3 private native) 'sqlite3-finalize))
(define sqlite3-next-stmt (reach '(chez-sqlite3 private native) 'sqlite3-next-stmt))

(load-row "a statement an extension leaves open makes the close refuse: the leaves variant's init registers its functions, then prepares select 1 and leaves it open; the load answers and chez_half answers; close-database! raises untracked-statements 1, the connection still open and counted; the statement, found through native's sqlite3_next_stmt, finalizes with 0; then a second close closes, every count back to 0"
  (list 'loaded 'present '(raised (assertion-violation close-database! (untracked-statements 1)))
        '((block . 0) (connection . 1) (statement . 0)) '(finalized 0) 'closed zero-counts)
  (lambda ()
    (let* ((db (opted))
           (r (loaded db ext-leaves))
           (h (half db))
           (refused (attempt (lambda () (close-database! db) 'closed)))
           (counts (native-counts))
           (finished (handle-call db
                       (lambda (handle)
                         (let ((left (sqlite3-next-stmt handle 0)))
                           (if (eqv? left 0) 'none (list 'finalized (sqlite3-finalize left)))))))
           (again (attempt (lambda () (close-database! db) 'closed))))
      (list r h refused counts finished again (native-counts)))))

;; --- the close ---------------------------------------------------------------------------------

(load-row "the close unloads the extension: a connection's load counts 1; closed, a new connection has no chez_half, and its own load counts 1 again, the file loaded afresh"
  (list 1 '(absent error) 1)
  (lambda ()
    (let* ((a (opted))
           (one (begin (load-extension! a ext) (inits a))))
      (close-database! a)
      (let* ((b (opted))
             (absent (half b))
             (again (begin (load-extension! b ext) (inits b))))
        (close-database! b)
        (list one absent again)))))

;; --- a stand-in for the binding -----------------------------------------------------------------

;; c-bytes : Natural -> Any
;; The bytes at ADDRESS up to its NUL, as a string read byte by byte; null
;; for 0.
(define (c-bytes address)
  (if (eqv? address 0)
      'null
      (let loop ((i 0) (found '()))
        (let ((b (foreign-ref 'unsigned-8 address i)))
          (if (= b 0)
              (utf8->string (u8-list->bytevector (reverse found)))
              (loop (+ i 1) (cons b found)))))))

;; stand-in : (Natural Natural Natural Natural -> Any) -> (Values Procedure (-> (Listof Any)))
;; A stand-in for native's binding, and a reader of its calls, oldest
;; first: each the handle given, the path's bytes, the entry point's or
;; null, and what the slot held at the call. ANSWER, given the same four,
;; answers the code. It runs inside the section, and raises nothing.
(define (stand-in answer)
  (let ((calls '()))
    (values
     (lambda (h file proc slot)
       (set! calls (cons (list h (c-bytes file) (c-bytes proc) (foreign-ref 'uptr slot 0)) calls))
       (answer h file proc slot))
     (lambda () (reverse calls)))))

;; handle-of : Database -> Any
(define (handle-of db) (handle-call db (lambda (h) h)))

(load-row "through load-extension/with, its binding a stand-in that answers 0: each form calls it once, given the connection's handle, the path's C string, the entry point's or NULL for none, and the slot set to NULL, and answers nothing"
  (list 'loaded 'loaded 'the-handle (list (list ext 'null 0) (list ext-named "chez_named_init" 0)))
  (lambda ()
    (with-db opted
      (lambda (db)
        (let-values (((load calls) (stand-in (lambda (h f p s) 0))))
          (let* ((a (attempt (lambda () (load-extension/with load c-string->string db ext) 'loaded)))
                 (b (attempt (lambda () (load-extension/with load c-string->string db ext-named "chez_named_init") 'loaded)))
                 (h (handle-of db))
                 (noted (calls)))
            (list a b
                  (if (for-all (lambda (c) (equal? (car c) h)) noted) 'the-handle (list 'handles h noted))
                  (map cdr noted))))))))

(load-row "a slot left empty: a stand-in answering 1 and writing nothing raises &sqlite-error error, its message sqlite3_errstr's for 1, read through native; one answering 5 raises busy, its message sqlite3_errstr's for 5"
  (list (list (list 'raised (list 'sqlite-error 'load-extension! 'error 'error #f #f)) 'errstr)
        (list (list 'raised (list 'sqlite-error 'load-extension! 'busy 'busy #f #f)) 'errstr))
  (lambda ()
    (with-db opted
      (lambda (db)
        (let ((run (lambda (code)
                     (let-values (((load calls) (stand-in (lambda (h f p s) code))))
                       (guard (e ((sqlite-error? e)
                                  (list (list 'raised (what-raised e))
                                        (if (equal? (sqlite-error-message e) (errstr code)) 'errstr
                                            (list 'message (sqlite-error-message e) (errstr code)))))
                                 (#t (list (list 'raised (what-raised e)) 'no-message)))
                         (load-extension/with load c-string->string db ext)
                         (list 'loaded 'no-message))))))
          (let* ((one (run 1)) (five (run 5)))
            (list one five)))))))

(load-row "a code that names no error, which only a stand-in answers, its low byte 0, 100 or 101 but not 0, or no exact integer, is an assertion violation from load-extension!, (not-an-error CODE), never raise-sqlite-error's own refusal"
  (map (lambda (code) (refused (list 'not-an-error code))) '(100 101 256 612 1.0 none))
  (lambda ()
    (with-db opted
      (lambda (db)
        (in-order (lambda (code)
               (let-values (((load calls) (stand-in (lambda (h f p s) code))))
                 (attempt (lambda () (load-extension/with load c-string->string db ext) 'loaded))))
             '(100 101 256 612 1.0 none))))))

(load-row "a message on the success path is freed: a stand-in that makes the real load of a path no file stands at, which answers 1 and leaves a message in the slot, then answers 0; the verb answers nothing, and sqlite3_memory_used, higher while the message was held, read by the stand-in, is back to what it read before the load"
  (list 'loaded '(1 a-message) memory-verdict)
  (lambda ()
    (memory-noted! "a message on the success path is freed")
    (with-db opted
      (lambda (db)
        (let* ((real #f)
               (load (lambda (h f p s)
                       (let ((code (raw-load-binding h f p s)))
                         (set! real (list code (if (eqv? (foreign-ref 'uptr s 0) 0) 'none 'a-message)
                                          (memory-used)))
                         0)))
               (before (memory-used))
               (r (attempt (lambda () (load-extension/with load c-string->string db missing) 'loaded)))
               (after (memory-used)))
          (list r (if real (list (car real) (cadr real)) 'not-called)
                (held-then-freed before (and real (caddr real)) after)))))))

(load-row "a copy that raises: a stand-in copy raising an object of the suite's own, beside native's binding, on a path no file stands at, has that very object raised from the verb, and the message freed all the same: sqlite3_memory_used, higher while the copy held it, read by the copy, back to what it read before; chez_half absent"
  (list 'the-copys-own memory-verdict '(absent error))
  (lambda ()
    (memory-noted! "a copy that raises")
    (with-db opted
      (lambda (db)
        (let* ((marker (list 'the-copys-raise))
               (held #f)
               (copy (lambda (address) (set! held (memory-used)) (raise marker)))
               (before (memory-used))
               (r (guard (e ((eq? e marker) 'the-copys-own) (#t (list 'raised (what-raised e))))
                    (load-extension/with raw-load-binding copy db missing)
                    'no-raise))
               (after (memory-used)))
          (list r (held-then-freed before held after) (half db)))))))

;; --- the refusals: the wrong thread and a closed connection ----------------------------------------

;; in-thread : (-> Any) -> Any
;; THUNK run on a thread of its own: (answered V), or what it raised, as
;; data, (raised WHAT FIELDS ID), with a wrong thread's owner and caller and
;; the thread's own id. The wait is bounded, 3000 waits of 10 ms:
;; (timed-out) past it.
(define (in-thread thunk)
  (let ((m (make-mutex)) (answer #f) (done #f))
    (fork-thread
     (lambda ()
       (let ((r (guard (e ((sqlite-wrong-thread? e)
                           (list 'raised (what-raised e)
                                 (list (sqlite-wrong-thread-owner e) (sqlite-wrong-thread-caller e))
                                 (get-thread-id)))
                          (#t (list 'raised (what-raised e) 'no-fields (get-thread-id))))
                  (list 'answered (thunk)))))
         (with-mutex m (set! answer r) (set! done #t)))))
    (let loop ((n 0))
      (cond ((with-mutex m done) (with-mutex m answer))
            ((>= n 3000) '(timed-out))
            (else (sleep (make-time 'time-duration 10000000 0)) (loop (+ n 1)))))))

;; thread-judged : Any -> Any
;; IN-THREAD's answer, its owner and caller held to this thread's id and
;; the thread's own.
(define (thread-judged r)
  (if (and (list? r) (= (length r) 4) (list? (caddr r)))
      (list (cadr r)
            (if (equal? (caddr r) (list (get-thread-id) (cadddr r))) 'owner-and-caller (list 'ids (caddr r))))
      r))

(define wrong-thread '(wrong-thread load-extension!))

(test-equal "from another thread, on a connection that did not opt in: &sqlite-wrong-thread from load-extension!, its owner this thread and its caller that one, before the argument checks and the opt-in: a valid path, no string, a relative path, a path holding U+0000, and a bad entry point all raise it"
  (map (lambda (x) (list wrong-thread 'owner-and-caller)) '(1 2 3 4 5))
  (with-db plain
    (lambda (db)
      (in-order (lambda (args) (thread-judged (in-thread (lambda () (apply load-extension! db args)))))
           (list (list ext) (list 42) (list "ext.so") (list (string #\/ #\nul)) (list ext 42))))))

(load-row "from another thread, on a connection that opted in, with everything valid: &sqlite-wrong-thread, owner and caller as they are, though SQLite itself loads from any thread; chez_half is absent on the owner's thread after, nothing loaded"
  (list (list wrong-thread 'owner-and-caller) (list wrong-thread 'owner-and-caller) '(absent error))
  (lambda ()
    (with-db opted
      (lambda (db)
        (let* ((a (thread-judged (in-thread (lambda () (load-extension! db ext)))))
               (b (thread-judged (in-thread (lambda () (load-extension! db ext-named "chez_named_init"))))))
          (list a b (half db)))))))

(test-equal "a closed connection: &sqlite-closed from load-extension!, before the argument checks and the opt-in: a valid path, no string, a relative path, and a bad entry point, on a connection that opted in where the library allows it"
  (map (lambda (x) '(raised (closed load-extension!))) '(1 2 3 4 5))
  (let ((db (attempt (if (eq? available #t) opted plain))))
    (if (a-database? db)
        (begin
          (close-answer db)
          (list (loaded db ext) (loaded db 42) (loaded db "ext.so") (loaded db ext 42)
                (loaded db ext-named "chez_named_init")))
        (list 'not-opened db))))

;; --- a remainder finished on another thread ------------------------------------------------------
;; Chez resumes an engine's remainder on whichever thread calls it, so the call's checks can pass on
;; the owner's thread, and the call go on on another. Each check after the expiry refuses that
;; thread, and every refusal names load-extension!, the opt-in's read among them (ADR-0013). When
;; the opt-in's read named itself, 99 of 109 refusals named database-extension-loading? instead of
;; load-extension!. Each sweep runs the call at every fuel from 1 until it completes without
;; expiring, a fresh connection for every trial, and finishes each remainder on a thread of its own,
;; by in-thread, whose wait is bounded.

;; load-answer : Database String -> Any
;; load-extension! of PATH on DB, and the thread it ran on: (loaded ID), or
;; what it raised and ID, a wrong thread's with its owner and caller.
(define (load-answer db path)
  (guard (e ((sqlite-wrong-thread? e)
             (list (list 'wrong-thread (who-of e) (sqlite-wrong-thread-owner e)
                         (sqlite-wrong-thread-caller e))
                   (get-thread-id)))
            (#t (list (list 'raised (what-raised e)) (get-thread-id))))
    (load-extension! db path)
    (list 'loaded (get-thread-id))))

;; finished : Engine -> Any
;; ENGINE run to its end, in slices of 10^8 ticks, at most 100 of them.
(define (finished engine)
  (let loop ((e engine) (n 0))
    (if (>= n 100)
        '(unfinished 100)
        (e 100000000 (lambda (left . answers) (car answers)) (lambda (next) (loop next (+ n 1)))))))

;; init-runs : Database -> Any
;; How many times the extension's init has run on DB, by chez_inits(), the
;; whole call's effect: none when it never loaded, chez_inits absent.
(define (init-runs db)
  (let ((n (inits db)))
    (if (and (integer? n) (exact? n)) n 'none)))

;; load-sweep : (-> Database) String -> (Listof Any)
;; load-extension! of PATH swept: at each fuel from 1, a fresh connection
;; made by OPEN on this thread, and the call in an engine of FUEL ticks.
;; One that completes ends the sweep, (FUEL completed ANSWER RUNS). One that
;; expires is finished on a thread of its own: (FUEL resumed ANSWER RUNS),
;; ANSWER in-thread's. RUNS is init-runs, read on this thread after; the
;; connection is closed then. Past 3000 fuels, (unfinished-sweep 3000).
(define (load-sweep open path)
  (let loop ((fuel 1) (found '()))
    (if (> fuel 3000)
        (reverse (cons '(unfinished-sweep 3000) found))
        (let* ((db (open))
               (engine (make-engine (lambda () (load-answer db path))))
               (run (engine fuel (lambda (left . answers) (list 'completed (car answers)))
                            (lambda (next) (list 'expired next)))))
          (if (eq? (car run) 'completed)
              (let ((runs (init-runs db)))
                (close-answer db)
                (reverse (cons (list fuel 'completed (cadr run) runs) found)))
              (let* ((a (in-thread (lambda () (finished (cadr run)))))
                     (runs (init-runs db)))
                (close-answer db)
                (loop (+ fuel 1) (cons (list fuel 'resumed a runs) found))))))))

;; load-verdict : (Listof Any) Any Any -> (List Any Symbol Symbol (Listof Any))
;; A sweep's TRIALS, each judged by its own answer and effect: the
;; completion's answer, its thread this one, and its runs; whether some
;; resumed trial was refused there, (wrong-thread load-extension! OWNER
;; CALLER), OWNER this thread's id and CALLER the thread's own, with no run
;; of the init; whether some answered PAST, the call's end, its runs
;; PAST-RUNS: the answer the call had on this thread before the expiry;
;; and every other trial, whole: a refusal naming another procedure, or a
;; load made there.
(define (load-verdict trials past past-runs)
  (let ((main (get-thread-id)))
    (let loop ((rest trials) (refused 0) (answered 0) (others '()) (completion 'never-completed))
      (if (null? rest)
          (list completion (if (> refused 0) 'yes 'no) (if (> answered 0) 'yes 'no) (reverse others))
          (let* ((t (car rest))
                 (a (and (= (length t) 4) (eq? (cadr t) 'resumed) (caddr t)))
                 (v (and (list? a) (= (length a) 2) (eq? (car a) 'answered) (cadr a)))
                 (id (and (list? v) (= (length v) 2) (cadr v))))
            (cond ((and (= (length t) 4) (eq? (cadr t) 'completed))
                   (let ((c (caddr t)))
                     (loop (cdr rest) refused answered others
                           (list (if (and (list? c) (= (length c) 2) (eqv? (cadr c) main)) (car c) c)
                                 (cadddr t)))))
                  ((and id (not (eqv? id main))
                        (equal? (car v) (list 'wrong-thread 'load-extension! main id))
                        (eq? (cadddr t) 'none))
                   (loop (cdr rest) (+ refused 1) answered others completion))
                  ((and id (not (eqv? id main)) (equal? (car v) past) (equal? (cadddr t) past-runs))
                   (loop (cdr rest) refused (+ answered 1) others completion))
                  (else (loop (cdr rest) refused answered (cons t others) completion))))))))

(test-equal "load-extension!'s remainder, taken at every fuel on the owner's thread of a connection that did not opt in and finished on another: refused there with &sqlite-wrong-thread from load-extension!, never from another procedure, the owner this thread and the caller that one; or the opt-in's refusal, raised on this thread before the expiry; the sweep reaches both, nothing loads, and every count is zero after"
  (list (list (refused '(extension-loading-not-enabled)) 'none) 'yes 'yes '() zero-counts)
  (attempt
   (lambda ()
     (append (load-verdict (load-sweep plain ext) (refused '(extension-loading-not-enabled)) 'none)
             (list (native-counts))))))

;; The load's section is the call's last, and at this trip no tick falls
;; after it: every remainder this sweep takes is before it, so the row asks
;; for no answer past it, and allows one, judged as the plain row judges it.
(load-row "load-extension!'s remainder, taken at every fuel on the owner's thread of a connection that opted in and finished on another: refused there with &sqlite-wrong-thread from load-extension!, never from another procedure, the owner this thread and the caller that one, the init never run; the call that completes loads, its init run once; and every count is zero after"
  (list (list 'loaded 1) 'yes '() zero-counts)
  (lambda ()
    (let ((v (load-verdict (load-sweep opted ext) 'loaded 1)))
      (list (car v) (cadr v) (cadddr v) (native-counts)))))

;; The reader load-extension! calls, given its who: from another thread its
;; refusal names that who, and a who that is no symbol is refused first.
(test-equal "database-extension-loading? given a who: from another thread, &sqlite-wrong-thread from that who, the owner this thread and the caller that one; on this one, the opt-in; a who that is no symbol is an assertion violation from database-extension-loading?, not-a-who, before the database is looked at"
  (list (list '(wrong-thread some-verb) 'owner-and-caller) '(answered no) 'no
        '(raised (assertion-violation database-extension-loading? (not-a-who 42)))
        '(raised (assertion-violation database-extension-loading? (not-a-who (kind string))))
        '(raised (assertion-violation some-verb (not-a-database x))))
  (with-db plain
    (lambda (db)
      (let* ((other (thread-judged
                     (in-thread (lambda () (yes-no (database-extension-loading? 'some-verb db))))))
             (here (attempt (lambda () (list 'answered (yes-no (database-extension-loading? 'some-verb db))))))
             (one (attempt (lambda () (yes-no (database-extension-loading? db)))))
             (number (attempt (lambda () (database-extension-loading? 42 'x))))
             (text (attempt (lambda () (database-extension-loading? "some-verb" 'x))))
             (no-db (attempt (lambda () (database-extension-loading? 'some-verb 'x)))))
        (list other here one number text no-db)))))

;; --- the memory ----------------------------------------------------------------------------------

(load-row "a load, a call and the close leave sqlite3_memory_used as it read before the open, higher while the connection held the extension, and every count zero: the extension's registrations and the load's own records are freed by the close"
  (list 'loaded 'present memory-verdict zero-counts)
  (lambda ()
    (memory-noted! "a load, a call and the close")
    (let* ((before (memory-used))
           (db (opted))
           (r (loaded db ext))
           (h (half db))
           (held (memory-used)))
      (close-database! db)
      (let ((after (memory-used)))
        (list r h (held-then-freed before held after) (native-counts))))))

(load-row "each failure's message is freed: on one connection, each failed load, made by the verb's own work with native's binding and a copy that reads sqlite3_memory_used as it is given the message, then copies it, raises &sqlite-error error from load-extension!; the count was higher while the message was held, and reads after the raise what it read just before the load, for every failure, the failing init's among them"
  (map (lambda (c) (list '(raised (sqlite-error load-extension! error error #f #f)) memory-verdict))
       failure-cases)
  (lambda ()
    (memory-noted! "each failure's message is freed")
    (with-db opted
      (lambda (db)
        (let loop ((rest failure-cases) (found '()))
          (if (null? rest)
              (reverse found)
              (let* ((c (car rest))
                     (held #f)
                     (copy (lambda (address) (set! held (memory-used)) (c-string->string address)))
                     (before (memory-used))
                     (r (attempt (lambda () (apply load-extension/with raw-load-binding copy db (cadr c) (caddr c)))))
                     (after (memory-used)))
                (loop (cdr rest) (cons (list r (held-then-freed before held after)) found)))))))))

;; --- depth --------------------------------------------------------------------------------------

(test-equal "each refusal's with-exception-handler handler runs at interrupt depth 1, after every section: no database, a closed connection, each argument check, and the opt-in"
  (list (list 'depth-1 (refused '(not-a-database 42)))
        (list 'depth-1 '(raised (closed load-extension!)))
        (list 'depth-1 (refused '(path-not-a-string 42)))
        (list 'depth-1 (refused '(path-holds-nul (kind string))))
        (list 'depth-1 (refused '(path-not-absolute (kind string))))
        (list 'depth-1 (refused '(entry-point-not-a-string 42)))
        (list 'depth-1 (refused '(entry-point-holds-nul (kind string))))
        (list 'depth-1 (refused '(extension-loading-not-enabled))))
  (let ((closed (attempt plain)))
    (when (a-database? closed) (close-answer closed))
    (with-db plain
      (lambda (db)
        (list (depth-of (lambda () (load-extension! 42 ext)))
              (depth-of (lambda () (load-extension! closed ext)))
              (depth-of (lambda () (load-extension! db 42)))
              (depth-of (lambda () (load-extension! db (string #\/ #\nul))))
              (depth-of (lambda () (load-extension! db "x.so")))
              (depth-of (lambda () (load-extension! db ext 42)))
              (depth-of (lambda () (load-extension! db ext (string #\nul))))
              (depth-of (lambda () (load-extension! db ext))))))))

(test-equal "from another thread, the wrong thread's handler runs at depth 1 there"
  (list 'answered (list 'depth-1 (list 'raised wrong-thread)))
  (with-db plain
    (lambda (db)
      (in-thread (lambda () (depth-of (lambda () (load-extension! db ext))))))))

(load-row "each failure's handler runs at depth 1: SQLite's failure, a code that names no error, and a copy's raise, the copy's own object"
  (list (list 'depth-1 (list 'raised (list 'sqlite-error 'load-extension! 'error 'error #f #f)))
        (list 'depth-1 (refused '(not-an-error 100)))
        (list 'depth-1 'the-copys-own))
  (lambda ()
    (with-db opted
      (lambda (db)
        (let-values (((load calls) (stand-in (lambda (h f p s) 100))))
          (let* ((marker (list 'the-copys-raise))
                 (failed (depth-of (lambda () (load-extension! db missing))))
                 (no-error (depth-of (lambda () (load-extension/with load c-string->string db ext))))
                 (copied (depth-raw (lambda () (load-extension/with raw-load-binding
                                                                     (lambda (a) (raise marker))
                                                                     db missing)))))
            (list failed no-error
                  (list (car copied) (if (eq? (cadr copied) marker) 'the-copys-own (cadr copied))))))))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "load-extension")

(exit (suite-exit-status runner))
