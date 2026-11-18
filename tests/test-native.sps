#!r6rs
;;; The suite for (chez-sqlite3 private native), the load of libsqlite3 and
;;; its bindings (ADR-0002, ADR-0010, ADR-0011), in a process of its own. It
;;; is the first suite to load libsqlite3, and make test-memory runs it under
;;; Valgrind.
;;;
;;; Native's body is the load, and a guard in a program cannot catch a raise
;;; from an imported library's body (AGENTS.md). So this suite reaches native
;;; through eval, under a guard: a refused library names the row "native
;;; loads", and every row that needs native fails by name, where an import
;;; would kill the suite, unnamed, before its first line. Refusals themselves
;;; are M1 slice 3's, each in a process of its own.
;;;
;;;   the report     the path and source equal what this suite chose itself:
;;;                  CHEZ_SQLITE3_LIBRARY when it is set, else discovery on
;;;                  this suite's own inputs. The version, its number, the
;;;                  source id, the threadsafe answer, every compile option
;;;                  and sqlite3_errstr of a list of codes equal what
;;;                  tests/libsqlite3-oracle.c reads in C from that same file
;;;   the bindings   each one answers: an open and close of :memory:, and an
;;;                  open that fails and is closed, every return code
;;;                  asserted, the counts back at zero
;;;   M2's bindings  each of the 21 answers, on :memory:: a prepare and its
;;;                  tail, prepares that fail and their offsets (measured on
;;;                  3.53.1 and the floor, 3.45.1, alike), step, reset and
;;;                  finalize, the parameters; each bind held by SQLite, read
;;;                  back through select ?1, typeof(?1), at the values where a
;;;                  narrower type differs; SQLite's copy of a value bound with
;;;                  sqlite-transient; and every column read, held whole to
;;;                  what the C oracle reads of the same SQL. sqlite-transient
;;;                  is the header's SQLITE_TRANSIENT, through the oracle
;;;   M3's five      sqlite3_changes64, sqlite3_total_changes64,
;;;                  sqlite3_last_insert_rowid, sqlite3_get_autocommit and
;;;                  sqlite3_interrupt (M3 slice 2). The counters: a fixed
;;;                  script on :memory:, the four read after each statement,
;;;                  held whole to what the C oracle reads of the same script
;;;                  and to a written-out literal, and to the 64-bit rowids at
;;;                  2^63-1, -2^63 and past 2^32. The autocommit flag: each
;;;                  state its own row. The interrupt, on one thread: a held
;;;                  row's next step answers SQLITE_INTERRUPT, and with no
;;;                  statement running it is a no-op. Every argument is a
;;;                  handle, a uptr, so Chez's int range never bites here
;;;   M4's three     sqlite3_db_config, variadic: each of the four ops
;;;                  round-trips through the binding on a :memory: connection
;;;                  of its own, read, set to the other value, read, set back
;;;                  and read, a fresh sentinel in its cell before each call;
;;;                  an op the library does not know answers SQLITE_ERROR and
;;;                  leaves the cell. sqlite3_free of NULL. Native's record,
;;;                  load-extension-available?, is this process's own
;;;                  foreign-entry?. sqlite3_load_extension of a file that is
;;;                  no shared object answers SQLITE_ERROR and a message,
;;;                  freed by sqlite3_free. On a library without
;;;                  sqlite3_load_extension, ENABLE_LOAD_EXTENSION's round
;;;                  trip and the load's rows print UNAVAILABLE, and the
;;;                  record and the binding, both #f, are asserted in their
;;;                  place. On x86-64 a binding of sqlite3_db_config without
;;;                  its variadic convention round-trips too: only
;;;                  test-conventions holds that, and make check-variadic
;;;                  watches it fail
;;;   C strings      call-with-c-string: UTF-8 on bytes where encodings
;;;                  differ, the NUL written, U+0000 refused at every position
;;;                  before anything is allocated, by kind, from the WHO it is
;;;                  given; the block freed on return, raise and escape, and
;;;                  re-entry refused. c-string->string reads them back
;;;   out-pointers   call-with-out-pointer: a zeroed, counted slot, read after
;;;                  PROC and freed on every path
;;;   int cells      call-with-int-cell (M4): a counted int block written with
;;;                  the caller's fill, read after PROC, the fill read back when
;;;                  PROC writes nothing, freed on every path, a fill no C int
;;;                  holds refused before anything is allocated
;;;   bytes          call-with-bytes: a bytevector's bytes, U+0000 and bytes
;;;                  past ASCII kept, in a counted block of at least one byte,
;;;                  never NULL for none, freed on return, raise and escape,
;;;                  re-entry refused; foreign-bytes and c-string->bytevector
;;;                  read bytes back undecoded into fresh bytevectors, and
;;;                  c-string->string reads through the second (M2 slice 4)
;;;   after the section
;;;                  each helper's refusals are raised outside the critical
;;;                  dynamic-wind thunks that make and free its block: a
;;;                  with-exception-handler handler of one runs at depth 1,
;;;                  with interrupts enabled (disable-interrupts answers 1
;;;                  outside any section). A row each for re-entry, and for
;;;                  the free of a block PROC freed itself
;;;   the body       native.sls read as data: its load steps in order, and
;;;                  every foreign-procedure form bound eagerly, as the value
;;;                  of a top-level load-step definition; and sqlite-transient
;;;                  computed from the pointer's size, never a literal. With one good library
;;;                  in one process neither can be seen by behaviour: the load
;;;                  runs once, and every check passes. M1 slice 3's decoy sees
;;;                  them
;;;   collect-safe   sqlite3_open_v2 blocked on a FIFO while another thread
;;;                  collects: the collection finishes only if the call is
;;;                  __collect_safe; and sqlite3_load_extension, the same
;;;                  way, on a connection with the C call on (M4). The types
;;;                  and conventions of every binding are the convention
;;;                  suite's
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own: SRFI-64 makes #f of a raise in an actual expression, and catches
;;; none in an expected expression or a top-level definition. No expected
;;; value here is #f. Effects run in order, through let* and named lets,
;;; never map (AGENTS.md).
;;;
;;; The oracle is a child process: C reading SQLite, not chez-sqlite3's native
;;; layer, and it keeps no counts. Under make test-memory it runs under the
;;; gate's own Valgrind (tests/libsqlite3-oracle.sls). The shells the FIFO row
;;; starts run outside it.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-ref foreign-set! foreign-sizeof getenv machine-type void
              library-exports fork-thread make-mutex with-mutex collect-rendezvous
              sleep make-time disable-interrupts enable-interrupts foreign-entry?)
        (chez-sqlite3-testing)
        (libsqlite3-oracle)
        (chez-sqlite3 private counters)
        (chez-sqlite3 private memory)
        (chez-sqlite3 private libsqlite3-info)
        (chez-sqlite3 private discovery)
        (chez-sqlite3 private constants)
        (only (chez-sqlite3 private conditions) chez-sqlite3-error?))

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

;; --- native, reached through eval -----------------------------------------------------------

;; native-load : (U 'loaded (List 'raised String))
;; Whether (chez-sqlite3 private native) loaded: its body runs at this first
;; reference, under a guard.
(define native-load
  (guard (e (#t (list 'raised (describe e))))
    (eval '(loaded-libsqlite3) (environment '(chez-sqlite3 private native)))
    'loaded))

;; The counts once the load has returned.
(define counts-after-load (native-counts))

;; native-procedure : Symbol -> Procedure
;; NAME's procedure in (chez-sqlite3 private native); when the load failed, or
;; NAME is not exported, a procedure that raises that, with NAME, every time
;; it is called, so each test that calls it fails by name.
(define (native-procedure name)
  (guard (e (#t (lambda args
                  (error name "(chez-sqlite3 private native) could not be reached" (describe e)))))
    (eval name (environment '(chez-sqlite3 private native)))))

(define loaded-libsqlite3 (native-procedure 'loaded-libsqlite3))
(define loaded-threadsafe (native-procedure 'loaded-threadsafe))
(define sqlite3-open-v2 (native-procedure 'sqlite3-open-v2))
(define sqlite3-close (native-procedure 'sqlite3-close))
(define sqlite3-errmsg (native-procedure 'sqlite3-errmsg))
(define sqlite3-errstr (native-procedure 'sqlite3-errstr))
(define sqlite3-errcode (native-procedure 'sqlite3-errcode))
(define sqlite3-extended-errcode (native-procedure 'sqlite3-extended-errcode))
(define sqlite3-next-stmt (native-procedure 'sqlite3-next-stmt))
(define sqlite3-memory-used (native-procedure 'sqlite3-memory-used))
(define sqlite3-compileoption-used (native-procedure 'sqlite3-compileoption-used))
(define sqlite3-compileoption-get (native-procedure 'sqlite3-compileoption-get))
(define call-with-c-string (native-procedure 'call-with-c-string))
(define c-string->string (native-procedure 'c-string->string))
(define call-with-out-pointer (native-procedure 'call-with-out-pointer))
(define call-with-int-cell (native-procedure 'call-with-int-cell))
(define call-with-bytes (native-procedure 'call-with-bytes))
(define foreign-bytes (native-procedure 'foreign-bytes))
(define c-string->bytevector (native-procedure 'c-string->bytevector))
(define sqlite3-prepare-v3 (native-procedure 'sqlite3-prepare-v3))
(define sqlite3-finalize (native-procedure 'sqlite3-finalize))
(define sqlite3-step (native-procedure 'sqlite3-step))
(define sqlite3-reset (native-procedure 'sqlite3-reset))
(define sqlite3-clear-bindings (native-procedure 'sqlite3-clear-bindings))
(define sqlite3-bind-parameter-count (native-procedure 'sqlite3-bind-parameter-count))
(define sqlite3-bind-parameter-index (native-procedure 'sqlite3-bind-parameter-index))
(define sqlite3-bind-null (native-procedure 'sqlite3-bind-null))
(define sqlite3-bind-int64 (native-procedure 'sqlite3-bind-int64))
(define sqlite3-bind-double (native-procedure 'sqlite3-bind-double))
(define sqlite3-bind-text64 (native-procedure 'sqlite3-bind-text64))
(define sqlite3-bind-blob64 (native-procedure 'sqlite3-bind-blob64))
(define sqlite3-column-count (native-procedure 'sqlite3-column-count))
(define sqlite3-column-name (native-procedure 'sqlite3-column-name))
(define sqlite3-column-type (native-procedure 'sqlite3-column-type))
(define sqlite3-column-int64 (native-procedure 'sqlite3-column-int64))
(define sqlite3-column-double (native-procedure 'sqlite3-column-double))
(define sqlite3-column-text (native-procedure 'sqlite3-column-text))
(define sqlite3-column-blob (native-procedure 'sqlite3-column-blob))
(define sqlite3-column-bytes (native-procedure 'sqlite3-column-bytes))
(define sqlite3-error-offset (native-procedure 'sqlite3-error-offset))
(define sqlite3-changes64 (native-procedure 'sqlite3-changes64))
(define sqlite3-total-changes64 (native-procedure 'sqlite3-total-changes64))
(define sqlite3-last-insert-rowid (native-procedure 'sqlite3-last-insert-rowid))
(define sqlite3-get-autocommit (native-procedure 'sqlite3-get-autocommit))
(define sqlite3-interrupt (native-procedure 'sqlite3-interrupt))
(define sqlite3-db-config (native-procedure 'sqlite3-db-config))
(define sqlite3-free (native-procedure 'sqlite3-free))
;; sqlite3-load-extension and load-extension-available? are values: the
;; binding or #f, and a boolean. When native cannot be reached each is the
;; raising procedure, which no row's expected value is.
(define sqlite3-load-extension (native-procedure 'sqlite3-load-extension))
(define load-extension-available? (native-procedure 'load-extension-available?))
;; sqlite-transient is a value, not a procedure: when native cannot be
;; reached it is the raising procedure, which no row's expected value is,
;; and which no binding takes as a uptr.
(define transient (native-procedure 'sqlite-transient))

;; info : Any
;; The report, or (raised TEXT).
(define info
  (guard (e (#t (list 'raised (describe e))))
    (loaded-libsqlite3)))

;; --- helpers ---------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

;; counts-with : (Listof (Pairof Symbol Integer)) -> (Listof (Pairof Symbol Integer))
;; zero-counts, with each kind in CHANGES at its count.
(define (counts-with changes)
  (map (lambda (entry) (cond ((assq (car entry) changes) => (lambda (c) c)) (else entry)))
       zero-counts))

;; in-order : (A -> B) (Listof A) -> (Listof B)
;; PROC of each of ITEMS, called first to last, one at a time: map calls its
;; procedure in no fixed order, and these calls allocate.
(define (in-order proc items)
  (let loop ((items items) (found '()))
    (if (null? items)
        (reverse found)
        (let ((answer (proc (car items))))
          (loop (cdr items) (cons answer found))))))

;; raised : (-> Any) -> Any
;; What THUNK raised: (assertion-violation WHO IRRITANTS), (other TEXT)
;; for any other raise, or (no-raise VALUE).
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e)
                  (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other (describe e))))
    (list 'no-raise (thunk))))

;; poke! : Natural (Listof Natural) -> Void
(define (poke! address bytes)
  (let loop ((i 0) (bytes bytes))
    (unless (null? bytes)
      (foreign-set! 'unsigned-8 address i (car bytes))
      (loop (+ i 1) (cdr bytes)))))

;; peek : Natural Natural -> (Listof Natural)
(define (peek address n)
  (let loop ((i (- n 1)) (found '()))
    (if (< i 0) found (loop (- i 1) (cons (foreign-ref 'unsigned-8 address i) found)))))

;; make-list-of : Natural Any -> (Listof Any)
(define (make-list-of n x) (if (= n 0) '() (cons x (make-list-of (- n 1) x))))

;; with-block : Natural (Natural -> Any) -> Any
;; PROC's answer, given a counted block of SIZE bytes, freed after.
(define (with-block size proc)
  (let ((block (foreign-block size)))
    (dynamic-wind
      (lambda () #f)
      (lambda () (proc block))
      (lambda () (free-foreign-block! block)))))

;; code-of : Symbol -> (U Integer (List 'no-code Symbol))
;; A result code's value, from (chez-sqlite3 private constants), which
;; tests/test-constants.sps holds to sqlite3.h. A name the table lacks is a
;; sentinel no row's expected value matches, so the rows that use it fail by
;; name where a raise in a top-level definition would end the suite unnamed.
(define (code-of name)
  (guard (e (#t (list 'no-code name)))
    (cdr (assq name sqlite-result-codes))))

(define ok (code-of 'ok))
(define cantopen (code-of 'cantopen))
(define ioerr (code-of 'ioerr))
(define error-code (code-of 'error))
(define range (code-of 'range))
(define toobig (code-of 'toobig))
(define readwrite-create (bitwise-ior sqlite-open-readwrite sqlite-open-create))

(define (sorted-names names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

;; A refusal is compared by its kind, who and irritants, never its message
;; text (ADR-0013, decision 9).

;; --- what this suite chose, and what the oracle read there -------------------------------------

;; maps-text : -> (U String #f)
;; /proc/self/maps, read whole; #f when it cannot be read, as off Linux.
(define (maps-text)
  (guard (e (#t #f))
    (let ((text (call-with-port
                 (open-file-input-port "/proc/self/maps" (file-options) (buffer-mode block)
                                       (make-transcoder (utf-8-codec)))
                 get-string-all)))
      (and (string? text) text))))

;; expected-choice : (U (Pairof String Symbol) (List 'raised String))
;; The path and source, chosen here without native: CHEZ_SQLITE3_LIBRARY as
;; given when it is set, as the container sets it; otherwise discovery's
;; answer on this suite's own inputs, as on CI's main job.
(define expected-choice
  (guard (e (#t (list 'raised (describe e))))
    (let ((override (getenv "CHEZ_SQLITE3_LIBRARY")))
      (if override
          (cons override 'override)
          (call-with-values
           (lambda () (choose-libsqlite3 getenv (machine-type) (maps-text) file-exists?))
           cons)))))

(define expected-path
  (and (pair? expected-choice) (string? (car expected-choice)) (car expected-choice)))

;; The codes sqlite3_errstr is read for: primary and extended, a row and a
;; done, and two no build names.
(define errstr-codes '(0 1 5 14 21 26 100 101 266 1555 -1 9999))

;; oracle : (U (Listof (Pairof Symbol Any)) (List 'no-oracle Symbol Any))
(define oracle
  (if expected-path
      (libsqlite3-oracle getenv expected-path errstr-codes)
      (list 'no-oracle 'no-path expected-choice)))

;; read-by-oracle : Symbol -> Pair
;; The oracle's (FIELD . VALUE), or (FIELD no-oracle) when it failed.
(define (read-by-oracle field)
  (or (and (list? oracle) (for-all pair? oracle) (assq field oracle))
      (list field 'no-oracle)))

;; read-compile-options : -> (U (Listof String) (List 'too-many ...))
;; sqlite3_compileoption_get from 0 up to its first NULL, each read by
;; c-string->string, in order; capped, so a binding that never answers NULL
;; ends.
(define (read-compile-options)
  (let loop ((i 0) (found '()))
    (if (= i 1000)
        (cons 'too-many (reverse found))
        (let ((address (sqlite3-compileoption-get i)))
          (if (eqv? address 0)
              (reverse found)
              (loop (+ i 1) (cons (c-string->string address) found)))))))

;; reported : Symbol -> Pair
;; What native reports for FIELD, as (FIELD . VALUE), or (FIELD raised TEXT).
(define (reported field)
  (cons field
        (guard (e (#t (list 'raised (describe e))))
          (case field
            ((version) (libsqlite3-info-version info))
            ((version-number) (libsqlite3-info-version-number info))
            ((source-id) (libsqlite3-info-source-id info))
            ((threadsafe) (loaded-threadsafe))
            ((compile-options) (read-compile-options))
            ((errstr) (in-order (lambda (code) (cons code (c-string->string (sqlite3-errstr code))))
                                errstr-codes))
            (else 'no-accessor)))))

;; oracle-options : (U (Listof String) (List 'no-options Any))
(define oracle-options
  (let ((entry (read-by-oracle 'compile-options)))
    (if (and (list? entry) (pair? (cdr entry)) (for-all string? (cdr entry)))
        (cdr entry)
        (list 'no-options entry))))

;; option-name : String -> String
;; An option as sqlite3_compileoption_get gives it, up to its first =.
(define (option-name option)
  (let loop ((i 0))
    (cond ((= i (string-length option)) option)
          ((char=? (string-ref option i) #\=) (substring option 0 i))
          (else (loop (+ i 1))))))

(test-begin "native")

;; --- the load and the report -----------------------------------------------------------------

(test-equal "(chez-sqlite3 private native) loads, reached through eval"
  'loaded
  native-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  counts-after-load)

;; No back door: the exports, written out whole.
(test-equal "(chez-sqlite3 private native) exports exactly the report, the threadsafe answer, M1's ten raw bindings, M2's 21, M3's five and M4's three, the record of the optional one, sqlite-transient, and the C-string, out-pointer and byte helpers"
  (sorted-names '(loaded-libsqlite3 loaded-threadsafe
                  sqlite3-open-v2 sqlite3-close sqlite3-errmsg sqlite3-errstr sqlite3-errcode
                  sqlite3-extended-errcode sqlite3-next-stmt sqlite3-memory-used
                  sqlite3-compileoption-used sqlite3-compileoption-get
                  sqlite3-prepare-v3 sqlite3-finalize sqlite3-step sqlite3-reset
                  sqlite3-clear-bindings sqlite3-bind-parameter-count sqlite3-bind-parameter-index
                  sqlite3-bind-null sqlite3-bind-int64 sqlite3-bind-double sqlite3-bind-text64
                  sqlite3-bind-blob64 sqlite3-column-count sqlite3-column-name sqlite3-column-type
                  sqlite3-column-int64 sqlite3-column-double sqlite3-column-text sqlite3-column-blob
                  sqlite3-column-bytes sqlite3-error-offset
                  sqlite3-changes64 sqlite3-total-changes64 sqlite3-last-insert-rowid
                  sqlite3-get-autocommit sqlite3-interrupt
                  sqlite3-db-config sqlite3-free sqlite3-load-extension load-extension-available?
                  sqlite-transient
                  call-with-c-string c-string->string call-with-out-pointer call-with-int-cell
                  call-with-bytes foreign-bytes c-string->bytevector))
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3 private native)))))

(test-equal "loaded-libsqlite3 answers a libsqlite3-info, the same one at every call"
  '(libsqlite3-info same)
  (list (if (libsqlite3-info? info) 'libsqlite3-info info)
        (guard (e (#t (list 'raised (describe e))))
          (if (eq? (loaded-libsqlite3) info) 'same 'different))))

;; A record that record-rtd opens can be rebuilt from its type: one holding
;; any path and version, and answering libsqlite3-info? true. Opaque, it
;; raises instead.
(test-equal "the report is opaque: record-rtd on a genuine one raises an assertion violation"
  '(assertion-violation record-rtd)
  (guard (e ((and (assertion-violation? e) (who-condition? e))
             (list 'assertion-violation (condition-who e)))
            (#t (list 'other-raise (describe e))))
    (list 'no-raise (record-type-name (record-rtd info)))))

(test-equal "this suite chose a path itself: CHEZ_SQLITE3_LIBRARY when set, else discovery's"
  'chosen
  (if expected-path 'chosen expected-choice))

(test-equal "the report's path and source are the ones this suite chose"
  (guard (e (#t (list 'unchosen (describe e))))
    (list (car expected-choice) (cdr expected-choice)))
  (guard (e (#t (list 'raised (describe e))))
    (list (libsqlite3-info-path info) (libsqlite3-info-source info))))

(test-equal "the C oracle read the library at that path"
  'read
  (if (eq? (car oracle) 'no-oracle) oracle 'read))

(for-each
 (lambda (field)
   (test-equal (string-append "native's " (symbol->string field) " is the C oracle's, whole")
     (read-by-oracle field)
     (reported field)))
 oracle-fields)

(test-equal "sqlite3-compileoption-used answers 1 for the name of every option the library lists, and 0 for a name no build has"
  (guard (e (#t (list 'no-expectation (describe e))))
    (append (map (lambda (option) (cons (option-name option) 1)) oracle-options)
            (list (cons "CHEZ_SQLITE3_NO_SUCH_OPTION" 0))))
  (guard (e (#t (list 'raised (describe e))))
    (in-order (lambda (name)
                (cons name (call-with-c-string 'test-native name sqlite3-compileoption-used)))
              (append (map option-name oracle-options)
                      (list "CHEZ_SQLITE3_NO_SUCH_OPTION")))))

;; --- the raw bindings answer -------------------------------------------------------------------

;; open-with : String Integer -> (Values Integer Natural)
;; sqlite3_open_v2 of FILENAME with FLAGS and no VFS: its code and the handle.
(define (open-with filename flags)
  (call-with-c-string 'test-native filename
    (lambda (name)
      (call-with-out-pointer 'test-native
        (lambda (slot) (sqlite3-open-v2 name slot flags 0))))))

(test-equal "sqlite3_open_v2 of :memory: answers SQLITE_OK and a handle; on it errcode and extended_errcode answer SQLITE_OK, errmsg reads as errstr of SQLITE_OK, next_stmt finds none, memory_used is an exact natural; sqlite3_close answers SQLITE_OK; every count is zero after"
  (list ok 'handle ok ok 'errstr-of-ok 0 'natural ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (let-values (((rc db) (open-with ":memory:" readwrite-create)))
      (if (eqv? db 0)
          (list rc 'no-handle)
          (let* ((errcode (sqlite3-errcode db))
                 (extended (sqlite3-extended-errcode db))
                 (message (c-string->string (sqlite3-errmsg db)))
                 (errstr-ok (c-string->string (sqlite3-errstr ok)))
                 (next (sqlite3-next-stmt db 0))
                 (used (sqlite3-memory-used))
                 (closed (sqlite3-close db)))
            (list rc 'handle errcode extended
                  (if (and (string? message) (equal? message errstr-ok)) 'errstr-of-ok
                      (list message errstr-ok))
                  next
                  (if (and (integer? used) (exact? used) (>= used 0)) 'natural used)
                  closed (native-counts)))))))

;; The assessment's defect: an open that fails still hands back a handle,
;; which must be closed.
(test-equal "sqlite3_open_v2 of a file in a missing directory answers SQLITE_CANTOPEN and still a handle; on it errcode and extended_errcode answer SQLITE_CANTOPEN, errmsg reads as errstr of SQLITE_CANTOPEN; sqlite3_close answers SQLITE_OK; every count is zero after"
  (list cantopen 'handle cantopen cantopen 'errstr-of-cantopen ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let-values (((rc db) (open-with (string-append dir "/no-such-directory/x.db")
                                        readwrite-create)))
         (if (eqv? db 0)
             (list rc 'no-handle)
             (let* ((errcode (sqlite3-errcode db))
                    (extended (sqlite3-extended-errcode db))
                    (message (c-string->string (sqlite3-errmsg db)))
                    (errstr-cantopen (c-string->string (sqlite3-errstr cantopen)))
                    (closed (sqlite3-close db)))
               (list rc 'handle errcode extended
                     (if (and (string? message) (equal? message errstr-cantopen))
                         'errstr-of-cantopen
                         (list message errstr-cantopen))
                     closed (native-counts)))))))))

;; --- M2's bindings answer ----------------------------------------------------------------------
;; Each row opens :memory: through the raw open, runs its calls in order
;; through let*, asserts every code, closes, and requires every count zero
;; after. The expected values were measured first, on Guix's 3.53.1 and on
;; the floor, 3.45.1, which answered the same (build/m2s2's probe).

;; with-memory : (Natural -> Any) -> (List Any Integer (Listof Pair))
;; PROC's answer, given the handle of a fresh :memory: database; then
;; sqlite3_close's code; then the counts after. A failed open is the answer
;; (open-failed CODE), with the handle closed.
(define (with-memory proc)
  (let-values (((rc db) (open-with ":memory:" readwrite-create)))
    (if (or (not (eqv? rc ok)) (eqv? db 0))
        (let ((closed (if (eqv? db 0) 'no-handle (sqlite3-close db))))
          (list (list 'open-failed rc) closed (native-counts)))
        (let* ((answer (guard (e (#t (list 'raised (describe e)))) (proc db)))
               (closed (sqlite3-close db)))
          (list answer closed (native-counts))))))

;; sql-length : String -> Natural
;; SQL's byte length in UTF-8: prepare's nByte.
(define (sql-length sql) (bytevector-length (string->utf8 sql)))

;; prepare : Natural String -> (List Integer Natural (U Natural 'null))
;; sqlite3_prepare_v3 of SQL on DB, nByte its byte length, prepFlags 0: the
;; code, the statement (0 for none) and where the tail points, as a byte
;; offset from the SQL's start, or null.
(define (prepare db sql)
  (call-with-c-string 'test-native sql
    (lambda (address)
      (let-values (((inner tail)
                    (call-with-out-pointer 'test-native
                      (lambda (tail-slot)
                        (call-with-values
                         (lambda ()
                           (call-with-out-pointer 'test-native
                             (lambda (statement-slot)
                               (sqlite3-prepare-v3 db address (sql-length sql) 0
                                                   statement-slot tail-slot))))
                         list)))))
        (list (car inner) (cadr inner) (if (eqv? tail 0) 'null (- tail address)))))))

;; with-statement : Natural String (Natural -> Any) -> (List Integer Any Integer)
;; SQL prepared on DB, PROC given the statement, then sqlite3_finalize: the
;; prepare's code, PROC's answer and the finalize's code. A prepare that
;; makes no statement answers (no-statement CODE).
(define (with-statement db sql proc)
  (let* ((prepared (prepare db sql))
         (statement (cadr prepared)))
    (if (eqv? statement 0)
        (list 'no-statement (car prepared))
        (let* ((answer (guard (e (#t (list 'raised (describe e)))) (proc statement)))
               (finalized (sqlite3-finalize statement)))
          (list (car prepared) answer finalized)))))

;; read-bytes : Natural Natural -> (U Bytevector #f)
;; The N bytes at ADDRESS, read by our own code; #f for NULL.
(define (read-bytes address n)
  (and (not (eqv? address 0))
       (let ((bytes (make-bytevector n)))
         (let loop ((i 0))
           (when (< i n)
             (bytevector-u8-set! bytes i (foreign-ref 'unsigned-8 address i))
             (loop (+ i 1))))
         bytes)))

;; column-text-bytes : Natural Natural -> (U Bytevector #f)
;; Column I's text, read through sqlite3_column_text, then
;; sqlite3_column_bytes, in the order SQLite's documentation gives.
(define (column-text-bytes statement i)
  (let* ((address (sqlite3-column-text statement i))
         (n (sqlite3-column-bytes statement i)))
    (read-bytes address n)))

;; column-blob-bytes : Natural Natural -> (U Bytevector #f)
(define (column-blob-bytes statement i)
  (let* ((address (sqlite3-column-blob statement i))
         (n (sqlite3-column-bytes statement i)))
    (read-bytes address n)))

;; flonum-bits : Flonum -> Natural
;; X's 64 bits, as an unsigned integer.
(define (flonum-bits x)
  (let ((bytes (make-bytevector 8)))
    (bytevector-ieee-double-native-set! bytes 0 x)
    (bytevector-u64-native-ref bytes 0)))

;; with-bytes : Bytevector (Natural Natural -> Any) -> Any
;; PROC's answer, given a counted block holding BYTES and their count. The
;; block holds at least one byte, so an empty value's address is never NULL
;; (ADR-0011, amended); it is freed after.
(define (with-bytes bytes proc)
  (let ((n (bytevector-length bytes)))
    (with-block (max n 1)
      (lambda (block)
        (poke! block (bytevector->u8-list bytes))
        (proc block n)))))

;; text-of : Natural Natural -> (U String Bytevector #f)
;; Column I's text, decoded when it is ASCII: typeof's answer.
(define (text-of statement i)
  (let ((bytes (column-text-bytes statement i)))
    (if (and bytes (for-all (lambda (b) (< 0 b 128)) (bytevector->u8-list bytes)))
        (utf8->string bytes)
        bytes)))

(test-equal "sqlite3_prepare_v3 of \"select 1; select 2\", nByte its byte length and prepFlags 0, answers SQLITE_OK, a statement and the tail 9 bytes on; sqlite3_error_offset is then -1; sqlite3_finalize and sqlite3_close answer SQLITE_OK; every count is zero after"
  (list (list ok 'statement 9 -1 ok) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (let* ((prepared (prepare db "select 1; select 2"))
              (offset (sqlite3-error-offset db))
              (finalized (sqlite3-finalize (cadr prepared))))
         (list (car prepared) (if (eqv? (cadr prepared) 0) 'no-statement 'statement)
               (caddr prepared) offset finalized))))))

;; Measured on 3.53.1 and 3.45.1 alike: the offset counts bytes, and is -1
;; for an error at the end of the SQL (the M2 plan, section 4.6), 0 for one
;; at its first byte.
(test-equal "a prepare that fails answers SQLITE_ERROR and no statement, and sqlite3_error_offset the error's byte: 10 for nosuchcol after \"select 1, \", 13 after \"select '\xE9;', \", whose \xE9; is two bytes, 0 for selectx, and -1 for an error at the end of the SQL, \"select 1 +\"; every count is zero after"
  (list (list (list error-code 'no-statement 10)
              (list error-code 'no-statement 13)
              (list error-code 'no-statement 0)
              (list error-code 'no-statement -1))
        ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (in-order (lambda (sql)
                   (let* ((prepared (prepare db sql))
                          (offset (sqlite3-error-offset db)))
                     (unless (eqv? (cadr prepared) 0) (sqlite3-finalize (cadr prepared)))
                     (list (car prepared) (if (eqv? (cadr prepared) 0) 'no-statement 'statement)
                           offset)))
                 '("select 1, nosuchcol" "select '\xE9;', nosuchcol" "selectx 1" "select 1 +"))))))

(test-equal "sqlite3_step of \"select 12\" answers SQLITE_ROW, with one column whose int64 is 12, then SQLITE_DONE; sqlite3_reset answers SQLITE_OK, and a step after it SQLITE_ROW again; sqlite3_finalize answers SQLITE_OK; every count is zero after"
  (list (list ok (list sqlite-row 1 12 sqlite-done ok sqlite-row 12) ok) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (with-statement db "select 12"
         (lambda (statement)
           (let* ((first (sqlite3-step statement))
                  (columns (sqlite3-column-count statement))
                  (value (sqlite3-column-int64 statement 0))
                  (second (sqlite3-step statement))
                  (reset (sqlite3-reset statement))
                  (again (sqlite3-step statement))
                  (value-again (sqlite3-column-int64 statement 0)))
             (list first columns value second reset again value-again))))))))

;; :alpha is 1, ?7 is 7, and $beta the next after the largest, 8.
(test-equal "sqlite3_bind_parameter_count of \"select :alpha, ?7, $beta\" is 8; sqlite3_bind_parameter_index finds :alpha at 1, ?7 at 7 and $beta at 8, and answers 0 for :nosuch, a name no parameter has, and for alpha without its sigil; every count is zero after"
  (list (list ok (list 8 1 7 8 0 0) ok) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (with-statement db "select :alpha, ?7, $beta"
         (lambda (statement)
           (let* ((count (sqlite3-bind-parameter-count statement))
                  (indexes (in-order (lambda (name)
                                       (call-with-c-string 'test-native name
                                         (lambda (address)
                                           (sqlite3-bind-parameter-index statement address))))
                                     '(":alpha" "?7" "$beta" ":nosuch" "alpha"))))
             (cons count indexes))))))))

;; bind-each : Natural Natural -> (Listof Integer)
;; Each of the five binds at INDEX, one after another: null, int64 5,
;; double 2.5, text "t" and blob 01.
(define (bind-each statement index)
  (let* ((null (sqlite3-bind-null statement index))
         (int64 (sqlite3-bind-int64 statement index 5))
         (double (sqlite3-bind-double statement index 2.5))
         (text (with-bytes (string->utf8 "t")
                 (lambda (address n)
                   (sqlite3-bind-text64 statement index address n transient sqlite-utf8))))
         (blob (with-bytes (u8-list->bytevector '(1))
                 (lambda (address n)
                   (sqlite3-bind-blob64 statement index address n transient)))))
    (list null int64 double text blob)))

(test-equal "each bind at index 0, and at one past the count, answers SQLITE_RANGE, and at the count SQLITE_OK: null, int64, double, text64 and blob64; every count is zero after"
  (list (list ok
              (list (list range range range range range)
                    (list range range range range range)
                    (list ok ok ok ok ok))
              ok)
        ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (with-statement db "select ?1, ?2"
         (lambda (statement)
           (let* ((zero (bind-each statement 0))
                  (past (bind-each statement 3))
                  (at (bind-each statement 2)))
             (list zero past at))))))))

;; --- the binds, held by SQLite: select ?1, typeof(?1) ---------------------------------------------

;; round-trip : (Natural -> Integer) (Natural -> Any) -> Any
;; A fresh "select ?1, typeof(?1)": BIND! given the statement, then a step,
;; then column 0's type, READ of the statement and column 1's text, then a
;; step to the end. Each round trip has its own statement, so a bind that
;; did nothing reads NULL, never an earlier value.
(define (round-trip bind! read)
  (with-memory
   (lambda (db)
     (with-statement db "select ?1, typeof(?1)"
       (lambda (statement)
         (let* ((bound (bind! statement))
                (row (sqlite3-step statement))
                (type (sqlite3-column-type statement 0))
                (value (read statement))
                (typeof (text-of statement 1))
                (done (sqlite3-step statement)))
           (list bound row type value typeof done)))))))

;; trip : Integer Integer Any String -> Expected
;; What round-trip answers when the bind answers SQLITE_OK and SQLite reads
;; back VALUE of TYPE, which typeof names TYPEOF.
(define (trip type value typeof)
  (list (list ok (list ok sqlite-row type value typeof sqlite-done) ok) ok zero-counts))

;; An int binding wraps or refuses each of these: -2^63 and 2^63-1 need 64
;; bits, and -2^31-1 and 2^31 are each one past an int's range.
(test-equal "sqlite3_bind_int64 binds -2^63, -2^31-1, 2^31 and 2^63-1 as INTEGER, read back the same by sqlite3_column_int64; every count is zero after each"
  (map (lambda (v) (trip sqlite-integer v "integer"))
       '(-9223372036854775808 -2147483649 2147483648 9223372036854775807))
  (in-order (lambda (v)
              (guard (e (#t (list 'raised (describe e))))
                (round-trip (lambda (statement) (sqlite3-bind-int64 statement 1 v))
                            (lambda (statement) (sqlite3-column-int64 statement 0)))))
            '(-9223372036854775808 -2147483649 2147483648 9223372036854775807)))

;; Compared by their 64 bits, written out: -0.0 is its sign bit alone, which
;; = cannot tell from 0.0; +inf.0 the exponent's; the smallest subnormal, 1;
;; 1.5, 3FF8 and zeros. A float binding loses the subnormal, and reads
;; another double's bits.
(test-equal "sqlite3_bind_double binds -0.0, +inf.0, the smallest subnormal and 1.5 as REAL, read back by sqlite3_column_double with the same 64 bits; every count is zero after each"
  (map (lambda (bits) (trip sqlite-float bits "real"))
       '(#x8000000000000000 #x7FF0000000000000 1 #x3FF8000000000000))
  (in-order (lambda (x)
              (guard (e (#t (list 'raised (describe e))))
                (round-trip (lambda (statement) (sqlite3-bind-double statement 1 x))
                            (lambda (statement) (flonum-bits (sqlite3-column-double statement 0))))))
            (list -0.0 +inf.0 4.9406564584124654e-324 1.5)))

;; The text's bytes, written out: a, é (two bytes), U+0000, € (three) and
;; U+1D11E (four), 11 bytes in 5 characters. A length counted in characters
;; would stop at €'s first byte.
(define text-bytes '(97 195 169 0 226 130 172 240 157 132 158))

(test-equal "sqlite3_bind_text64 binds a\xE9;, U+0000, \x20AC; and U+1D11E as TEXT, its 11 bytes counted, with sqlite-utf8 and sqlite-transient, read back the same by sqlite3_column_text and sqlite3_column_bytes; every count is zero after"
  (trip sqlite-text (u8-list->bytevector text-bytes) "text")
  (guard (e (#t (list 'raised (describe e))))
    (round-trip (lambda (statement)
                  (with-bytes (string->utf8 "a\xE9;\x0;\x20AC;\x1D11E;")
                    (lambda (address n)
                      (sqlite3-bind-text64 statement 1 address n transient sqlite-utf8))))
                (lambda (statement) (column-text-bytes statement 0)))))

;; An empty BLOB reads back as a NULL pointer with 0 bytes (measured, the M2
;; plan, section 4.4), read here as #f; bound from a NULL pointer it would
;; be NULL, which typeof names null.
(test-equal "sqlite3_bind_blob64 binds 00 FF 7F 80 00 as a BLOB, read back the same by sqlite3_column_blob and sqlite3_column_bytes; and an empty value, from a block of one byte, never NULL, as an empty BLOB, which reads back as no pointer and 0 bytes; every count is zero after each"
  (list (trip sqlite-blob (u8-list->bytevector '(0 255 127 128 0)) "blob")
        (trip sqlite-blob '(#f 0) "blob"))
  (in-order (lambda (bytes)
              (guard (e (#t (list 'raised (describe e))))
                (round-trip (lambda (statement)
                              (with-bytes bytes
                                (lambda (address n)
                                  (sqlite3-bind-blob64 statement 1 address n transient))))
                            (lambda (statement)
                              (if (= (bytevector-length bytes) 0)
                                  (let* ((address (sqlite3-column-blob statement 0))
                                         (n (sqlite3-column-bytes statement 0)))
                                    (list (if (eqv? address 0) #f address) n))
                                  (column-blob-bytes statement 0))))))
            (list (u8-list->bytevector '(0 255 127 128 0)) (u8-list->bytevector '()))))

(test-equal "sqlite3_bind_null makes a parameter bound to 5 NULL, which typeof names null; both binds answer SQLITE_OK; every count is zero after"
  (list (list ok (list (list ok ok) sqlite-row sqlite-null 0 "null" sqlite-done) ok) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (round-trip (lambda (statement)
                  (let* ((five (sqlite3-bind-int64 statement 1 5))
                         (null (sqlite3-bind-null statement 1)))
                    (list five null)))
                (lambda (statement) (sqlite3-column-int64 statement 0)))))

(test-equal "sqlite3_clear_bindings, after a reset, turns a parameter bound to 7 back to NULL: 7 and integer, then 0 and null; every code is asserted; every count is zero after"
  (list (list ok
              (list ok sqlite-row 7 "integer" sqlite-done ok ok sqlite-row sqlite-null "null" sqlite-done)
              ok)
        ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (with-statement db "select ?1, typeof(?1)"
         (lambda (statement)
           (let* ((bound (sqlite3-bind-int64 statement 1 7))
                  (row (sqlite3-step statement))
                  (value (sqlite3-column-int64 statement 0))
                  (typeof (text-of statement 1))
                  (done (sqlite3-step statement))
                  (reset (sqlite3-reset statement))
                  (cleared (sqlite3-clear-bindings statement))
                  (row-again (sqlite3-step statement))
                  (type-again (sqlite3-column-type statement 0))
                  (typeof-again (text-of statement 1))
                  (done-again (sqlite3-step statement)))
             (list bound row value typeof done reset cleared row-again type-again typeof-again
                   done-again))))))))

;; --- a length past 32 bits ------------------------------------------------------------------------
;; sqlite3_bind_text64 and sqlite3_bind_blob64 take a 64-bit length. A 1-byte
;; block with a length of 2^32+1 is refused by SQLite before it reads or
;; copies a byte (the length is checked against its limit first), so no
;; 4 GiB block is needed: SQLITE_TOOBIG, and the parameter stays NULL. Bound
;; as an unsigned-32 length, Chez refuses the argument and raises instead.
(define past-32-bits (+ (expt 2 32) 1))

(for-each
 (lambda (kind bind!)
   (test-equal (string-append "sqlite3_bind_" kind "64 of a 1-byte block with the length 2^32+1 answers SQLITE_TOOBIG, and the parameter stays NULL, which typeof names null; every count is zero after")
     (list (list ok (list toobig sqlite-row sqlite-null 0 "null" sqlite-done) ok) ok zero-counts)
     (guard (e (#t (list 'raised (describe e))))
       (round-trip (lambda (statement)
                     (with-bytes (u8-list->bytevector '(65))
                       (lambda (address n) (bind! statement address past-32-bits))))
                   (lambda (statement) (sqlite3-column-int64 statement 0))))))
 '("text" "blob")
 (list (lambda (statement address n)
         (sqlite3-bind-text64 statement 1 address n transient sqlite-utf8))
       (lambda (statement address n)
         (sqlite3-bind-blob64 statement 1 address n transient))))

;; --- the copy: SQLite copies a value bound with sqlite-transient -------------------------------
;; The bytes go into a counted block and are bound from it; then the block is
;; overwritten with other bytes, and freed, before the step reads the value.
;; Bound with 0, SQLITE_STATIC, SQLite would keep the address and read the
;; block's new bytes, or what the allocator left there, outside Valgrind too.

;; copied : (Natural Natural Natural -> Integer) (Natural -> Any) -> Any
(define (copied bind! read)
  (let ((first (bytevector->u8-list (string->utf8 "first-\xE9;-bytes")))
        (other (bytevector->u8-list (string->utf8 "OTHER-\x20AC;BYTE"))))
    (with-memory
     (lambda (db)
       (with-statement db "select ?1"
         (lambda (statement)
           (let* ((block (foreign-block (length first)))
                  (written (poke! block first))
                  (bound (bind! statement block (length first)))
                  (overwritten (poke! block other))
                  (freed (free-foreign-block! block))
                  (row (sqlite3-step statement))
                  (value (read statement))
                  (done (sqlite3-step statement)))
             (list bound row value done))))))))

(test-equal "SQLite copies TEXT bound with sqlite-transient: the block overwritten and freed before the step, the value reads back as first written; every count is zero after"
  (list (list ok (list ok sqlite-row (string->utf8 "first-\xE9;-bytes") sqlite-done) ok) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (copied (lambda (statement block n)
              (sqlite3-bind-text64 statement 1 block n transient sqlite-utf8))
            (lambda (statement) (column-text-bytes statement 0)))))

(test-equal "SQLite copies a BLOB bound with sqlite-transient: the block overwritten and freed before the step, the value reads back as first written; every count is zero after"
  (list (list ok (list ok sqlite-row (string->utf8 "first-\xE9;-bytes") sqlite-done) ok) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (copied (lambda (statement block n)
              (sqlite3-bind-blob64 statement 1 block n transient))
            (lambda (statement) (column-blob-bytes statement 0)))))

;; --- sqlite-transient, against the header ------------------------------------------------------

(define transient-oracle (libsqlite3-oracle-transient getenv))

(test-equal "sqlite-transient is the header's (uintptr_t)SQLITE_TRANSIENT, as the C oracle compiled here prints it"
  (if (and (list? transient-oracle) (pair? transient-oracle) (pair? (car transient-oracle))
           (eq? (caar transient-oracle) 'transient))
      (cdar transient-oracle)
      transient-oracle)
  transient)

(test-equal "the transient oracle ran under Valgrind exactly when the gate asked"
  (cons 'valgrind (if (getenv "CHEZ_SQLITE3_GATE_CHILD") 'yes 'no))
  (or (and (list? transient-oracle) (for-all pair? transient-oracle) (assq 'valgrind transient-oracle))
      (list 'valgrind 'no-oracle transient-oracle)))

;; --- every column read, against the oracle ---------------------------------------------------
;; The SQL: integers at the binds' boundaries; -0.0, 1e308, the smallest
;; subnormal and 1.5; text with two-, three- and four-byte sequences and
;; char(0) inside; x'00ff', x'' and zeroblob(0); NULL; and column names with
;; multibyte sequences. Its second row puts other types in the same columns.
;; Each column is read in the oracle's order: name, type, int64, double, text
;; then bytes, blob then bytes. No value is written out: the text of a REAL
;; differs between versions (the smallest subnormal is 23 bytes on 3.53.1, 21
;; on 3.45.1, measured), so both sides read the one library.
(define columns-sql
  (string-append
   "select -9223372036854775808 as \"int\xE9;\", -2147483649 as \"\x20AC;\", "
   "2147483648 as \"\x1D11E;\", 9223372036854775807 as \"a\x20AC;\x1D11E;\xE9;z\", "
   "-0.0, 1e308, 4.9406564584124654e-324, 1.5, "
   "'a' || char(0) || '\xE9;\x20AC;\x1D11E;', x'00ff', x'', zeroblob(0), null "
   "union all select 1, 2, 3, 4, 5.0, '', x'ff00', 'x', 10, 11.5, null, x'01', char(0)"))

(define columns-oracle
  (if expected-path
      (libsqlite3-oracle-rows getenv expected-path columns-sql)
      (list 'no-oracle 'no-path expected-choice)))

;; read-column : Natural Natural -> Column
;; Column I of the row STATEMENT holds, in the oracle's order and shape.
(define (read-column statement i)
  (let* ((name (let ((address (sqlite3-column-name statement i)))
                 (and (not (eqv? address 0))
                      (let scan ((n 0))
                        (if (eqv? (foreign-ref 'unsigned-8 address n) 0)
                            (read-bytes address n)
                            (scan (+ n 1)))))))
         (type (sqlite3-column-type statement i))
         (int64 (sqlite3-column-int64 statement i))
         (bits (flonum-bits (sqlite3-column-double statement i)))
         (text-address (sqlite3-column-text statement i))
         (text-n (sqlite3-column-bytes statement i))
         (text (read-bytes text-address text-n))
         (blob-address (sqlite3-column-blob statement i))
         (blob-n (sqlite3-column-bytes statement i))
         (blob (read-bytes blob-address blob-n)))
    (list name type text-n int64 bits text blob)))

;; read-rows : Natural -> (Listof Row)
;; Every row, stepped to SQLITE_DONE, each column read by read-column; a step
;; that answers anything else ends the list with (step CODE).
(define (read-rows statement)
  (let ((columns (sqlite3-column-count statement)))
    (let loop ((found '()))
      (let ((code (sqlite3-step statement)))
        (cond ((eqv? code sqlite-row)
               (loop (cons (let row ((i 0) (cells '()))
                             (if (= i columns)
                                 (reverse cells)
                                 (row (+ i 1) (cons (read-column statement i) cells))))
                           found)))
              ((eqv? code sqlite-done) (reverse found))
              (else (reverse (cons (list 'step code) found))))))))

(test-equal "the C oracle read every row and column of the SQL"
  'read
  (if (and (list? columns-oracle) (pair? columns-oracle) (pair? (car columns-oracle))
           (eq? (caar columns-oracle) 'rows))
      'read
      columns-oracle))

(test-equal "the oracle's columns ran under Valgrind exactly when the gate asked"
  (cons 'valgrind (if (getenv "CHEZ_SQLITE3_GATE_CHILD") 'yes 'no))
  (or (and (list? columns-oracle) (for-all pair? columns-oracle) (assq 'valgrind columns-oracle))
      (list 'valgrind 'no-oracle)))

(test-equal "every row and column, read through native's bindings, is the C oracle's, whole: each name's bytes, its type, its bytes, its int64, its double's 64 bits, its text and its blob, two rows of 13; the prepare, the finalize and the close answer SQLITE_OK, and every count is zero after"
  (list (list ok
              (if (and (list? columns-oracle) (pair? columns-oracle) (pair? (car columns-oracle))
                       (eq? (caar columns-oracle) 'rows))
                  (cdar columns-oracle)
                  'no-oracle)
              ok)
        ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (with-statement db columns-sql read-rows)))))

;; What the SQL reads, written out, so that replacing its boundary values with
;; tame ones fails whatever the oracle reads. Each column: its name's bytes,
;; type, int64, double bits, and, but for a REAL, its text's bytes and its
;; blob's. A REAL's text differs between SQLite versions (above), so a REAL
;; column's text, its byte count and its blob are left out; they are held to
;; the oracle's by the row above. Read from the oracle on 3.53.1 and 3.45.1,
;; which agree on all of it.
(define columns-written
  '(((#vu8(105 110 116 195 169) 1 -9223372036854775808 14114281232179134464
      #vu8(45 57 50 50 51 51 55 50 48 51 54 56 53 52 55 55 53 56
           48 56)
      #vu8(45 57 50 50 51 51 55 50 48 51 54 56 53 52 55 55 53 56
           48 56))
     (#vu8(226 130 172) 1 -2147483649 13970166044105375744
       #vu8(45 50 49 52 55 52 56 51 54 52 57)
       #vu8(45 50 49 52 55 52 56 51 54 52 57))
     (#vu8(240 157 132 158) 1 2147483648 4746794007248502784
       #vu8(50 49 52 55 52 56 51 54 52 56)
       #vu8(50 49 52 55 52 56 51 54 52 56))
     (#vu8(97 226 130 172 240 157 132 158 195 169 122) 1 9223372036854775807 4890909195324358656
       #vu8(57 50 50 51 51 55 50 48 51 54 56 53 52 55 55 53 56 48
            55)
       #vu8(57 50 50 51 51 55 50 48 51 54 56 53 52 55 55 53 56 48
            55))
     (#vu8(45 48 46 48) 2 0 9223372036854775808)
     (#vu8(49 101 51 48 56)
       2
       9223372036854775807
       9214871658872686752)
     (#vu8(52 46 57 52 48 54 53 54 52 53 56 52 49 50 52 54 53 52
           101 45 51 50 52)
       2
       0
       1)
     (#vu8(49 46 53) 2 1 4609434218613702656)
     (#vu8(39 97 39 32 124 124 32 99 104 97 114 40 48 41 32 124
           124 32 39 195 169 226 130 172 240 157 132 158 39) 3 0 0 #vu8(97 0 195 169 226 130 172 240 157 132 158)
       #vu8(97 0 195 169 226 130 172 240 157 132 158))
     (#vu8(120 39 48 48 102 102 39) 4 0 0 #vu8(0 255)
       #vu8(0 255))
     (#vu8(120 39 39) 4 0 0 #vu8() #f)
     (#vu8(122 101 114 111 98 108 111 98 40 48 41) 4 0 0 #vu8() #f)
     (#vu8(110 117 108 108) 5 0 0 #f #f))
    ((#vu8(105 110 116 195 169) 1 1 4607182418800017408 #vu8(49)
       #vu8(49))
      (#vu8(226 130 172) 1 2 4611686018427387904 #vu8(50)
        #vu8(50))
      (#vu8(240 157 132 158) 1 3 4613937818241073152 #vu8(51)
        #vu8(51))
      (#vu8(97 226 130 172 240 157 132 158 195 169 122) 1 4 4616189618054758400 #vu8(52) #vu8(52))
      (#vu8(45 48 46 48) 2 5 4617315517961601024)
      (#vu8(49 101 51 48 56) 3 0 0 #vu8() #f)
      (#vu8(52 46 57 52 48 54 53 54 52 53 56 52 49 50 52 54 53 52
            101 45 51 50 52) 4 0 0 #vu8(255 0) #vu8(255 0))
      (#vu8(49 46 53) 3 0 0 #vu8(120) #vu8(120))
      (#vu8(39 97 39 32 124 124 32 99 104 97 114 40 48 41 32 124
            124 32 39 195 169 226 130 172 240 157 132 158 39) 1 10 4621819117588971520 #vu8(49 48) #vu8(49 48))
      (#vu8(120 39 48 48 102 102 39) 2 11 4622663542519103488)
      (#vu8(120 39 39) 5 0 0 #f #f)
      (#vu8(122 101 114 111 98 108 111 98 40 48 41) 4 0 0 #vu8(1)
        #vu8(1))
      (#vu8(110 117 108 108) 3 0 0 #vu8(0) #vu8(0)))))

;; written-fields : Column -> List
;; A column as columns-written has it: the version-dependent fields of a REAL
;; (type 2) dropped.
(define (written-fields column)
  (let ((name (car column)) (type (cadr column)) (int64 (cadddr column))
        (bits (car (cddddr column))) (text (cadr (cddddr column)))
        (blob (caddr (cddddr column))))
    (if (eqv? type sqlite-float)
        (list name type int64 bits)
        (list name type int64 bits text blob))))

(test-equal "every row and column, read through native's bindings, has the written-out names, types, int64s and double bits, and the written-out text and blob bytes of each column that is no REAL; two rows of 13"
  (list (list ok columns-written ok) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (let ((answer (with-memory
                   (lambda (db)
                     (with-statement db columns-sql read-rows)))))
      (list (list (car (car answer))
                  (let ((rows (cadr (car answer))))
                    (if (and (list? rows) (for-all list? rows))
                        (map (lambda (row) (map written-fields row)) rows)
                        rows))
                  (caddr (car answer)))
            (cadr answer) (caddr answer)))))

(test-equal "the oracle's datum is two rows of 13 columns, so the comparison above reads something"
  '(2 13 13)
  (if (and (list? columns-oracle) (pair? columns-oracle) (pair? (car columns-oracle))
           (eq? (caar columns-oracle) 'rows) (list? (cdar columns-oracle)))
      (cons (length (cdar columns-oracle)) (map length (cdar columns-oracle)))
      columns-oracle))

;; --- M3's five: the counters, the autocommit flag and the interrupt -------------------------------
;; Every argument is a handle, a uptr, so Chez's int range (-2^31 to 2^32-1)
;; never bites here: no row feeds one a value past it. A result is another
;; matter, and the rows below read sqlite3_int64s past 32 bits.

;; run-statement : Natural String -> (List Integer (U Integer Symbol) (U Integer 'null))
;; SQL prepared on DB, stepped to the first answer but SQLITE_ROW (a cap of
;; 1000 rows, past which it is too-many-rows) and finalized: the prepare's
;; code, the step's, the finalize's. A prepare that makes no statement
;; answers (CODE no-statement 0). A prepare whose tail is not the end of the
;; SQL, a byte length in, would leave SQL that never runs: the statement is
;; finalized, unrun, and the answer is (CODE tail OFFSET), which no row
;; expects.
(define (run-statement db sql)
  (let* ((prepared (prepare db sql))
         (statement (cadr prepared)))
    (cond
     ((eqv? statement 0)
      (list (car prepared) 'no-statement 0))
     ((not (equal? (caddr prepared) (sql-length sql)))
      (sqlite3-finalize statement)
      (list (car prepared) 'tail (caddr prepared)))
     (else
      (let* ((stepped (let loop ((rows 0))
                        (let ((code (sqlite3-step statement)))
                          (cond ((not (eqv? code sqlite-row)) code)
                                ((= rows 1000) 'too-many-rows)
                                (else (loop (+ rows 1)))))))
             (finalized (sqlite3-finalize statement)))
        (list (car prepared) stepped finalized))))))

;; read-counters : Natural -> (List Integer Integer Integer Integer)
;; (CHANGES TOTAL ROWID AUTOCOMMIT): the four of M3's five that read, called in
;; this order, each once.
(define (read-counters db)
  (let* ((changes (sqlite3-changes64 db))
         (total (sqlite3-total-changes64 db))
         (rowid (sqlite3-last-insert-rowid db))
         (autocommit (sqlite3-get-autocommit db)))
    (list changes total rowid autocommit)))

;; run-script : Natural (Listof String) -> (Listof (List (List Integer Any Integer) (List Integer ...)))
;; Each of SQLS run by run-statement, in order, and the four read after it.
(define (run-script db sqls)
  (in-order (lambda (sql)
              (let* ((codes (run-statement db sql))
                     (counters (read-counters db)))
                (list codes counters)))
            sqls))

;; counters-script : (Listof String)
;; Three inserts at once, then one, an update, a select, a delete of every
;; row, and a BEGIN and COMMIT, then a BEGIN and ROLLBACK. A trigger inserts
;; into another table for each row of t, which sqlite3_total_changes64 counts
;; and sqlite3_changes64 does not, so the two differ from the first change on;
;; the rowids are ones no counter reaches (1003, 7777, -5, 43); and the counts
;; of the changing statements, 3, 1, 2, 4, 1 and 2, differ from the totals,
;; 6, 8, 10, 14, 16 and 20.
(define counters-script
  '("create table t(id integer primary key, v)"
    "create table log(n)"
    "create trigger tr after insert on t begin insert into log values (new.id); end"
    "insert into t values (1001, 'a'), (1002, 'b'), (1003, 'c')"
    "insert into t values (7777, 'd')"
    "update t set v = 'z' where id < 1003"
    "select id, v from t"
    "delete from t where id > 1000"
    "begin"
    "insert into t values (-5, 'e')"
    "commit"
    "begin"
    "insert into t values (42, 'f'), (43, 'g')"
    "rollback"))

;; The 64-bit rowids: past 32 bits, at the signed 64-bit extremes, and a
;; value whose low 32 bits are 1.
(define rowid-script
  '("create table r(id integer primary key)"
    "insert into r values (9223372036854775807)"
    "insert into r values (-9223372036854775808)"
    "insert into r values (4294967297)"))

;; oracle-counters : (Listof String) -> (U (Listof (List Integer Integer Integer Integer)) Any)
;; What the C oracle reads of SQLS; its datum when it failed.
(define (oracle-counters sqls)
  (let ((answer (if expected-path
                    (libsqlite3-oracle-counters getenv expected-path sqls)
                    (list 'no-oracle 'no-path expected-choice))))
    (if (and (list? answer) (pair? answer) (pair? (car answer)) (eq? (caar answer) 'counters))
        (cdar answer)
        answer)))

(define counters-oracle (oracle-counters counters-script))
(define rowids-oracle (oracle-counters rowid-script))

(test-equal "the C oracle read the four counters after each statement of both scripts: 14 and 4"
  '(14 4)
  (list (if (list? counters-oracle) (length counters-oracle) counters-oracle)
        (if (list? rowids-oracle) (length rowids-oracle) rowids-oracle)))

(test-equal "the C oracle's counters ran under Valgrind exactly when the gate asked"
  (cons 'valgrind (if (getenv "CHEZ_SQLITE3_GATE_CHILD") 'yes 'no))
  (let ((answer (if expected-path
                    (libsqlite3-oracle-counters getenv expected-path rowid-script)
                    (list 'no-oracle 'no-path))))
    (or (and (list? answer) (for-all pair? answer) (assq 'valgrind answer))
        (list 'valgrind 'no-oracle answer))))

;; every statement's own codes: SQLITE_OK to prepare, SQLITE_DONE to step, SQLITE_OK to finalize
(define (all-done n) (make-list-of n (list ok sqlite-done ok)))

(test-equal "after each statement of the script, sqlite3_changes64, sqlite3_total_changes64, sqlite3_last_insert_rowid and sqlite3_get_autocommit read, whole, what the C oracle reads: 14 rows of four; every prepare and finalize answers SQLITE_OK and every step SQLITE_DONE; the close answers SQLITE_OK and every count is zero after"
  (list (list (all-done 14) counters-oracle) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (let ((script (run-script db counters-script)))
         (list (map car script) (map cadr script)))))))

;; Written out, so that a script whose every statement changed nothing, or
;; whose counters all read the same, fails whatever the oracle reads. Read
;; from the oracle on 3.53.1 and on 3.45.1, which agree on all of it. The
;; trigger's rows are in the totals only: 3 inserts and 3 into log make 6.
;; A SELECT, a BEGIN and a COMMIT change none of the four but the flag; a
;; ROLLBACK undoes rows and leaves the totals as they were.
(define counters-written
  '((0 0 0 1)       ; create table t
    (0 0 0 1)       ; create table log
    (0 0 0 1)       ; create trigger
    (3 6 1003 1)    ; insert three rows, three more by the trigger
    (1 8 7777 1)    ; insert one
    (2 10 7777 1)   ; update two: the rowid is the last insert's
    (2 10 7777 1)   ; select: nothing changes
    (4 14 7777 1)   ; delete four, which no trigger sees
    (4 14 7777 0)   ; begin: autocommit off
    (1 16 -5 0)     ; insert one inside it
    (1 16 -5 1)     ; commit: autocommit on
    (1 16 -5 0)     ; begin
    (2 20 43 0)     ; insert two inside it
    (2 20 43 1)))   ; rollback: autocommit on, nothing undone in the counts

(test-equal "the same sequence has the written-out counters: 3 changes and 6 in all after the first insert, rowid 7777 after the update, the select and the delete, -5 inside the first transaction, 43 in the second and its rollback, and the flag 0 exactly inside BEGIN"
  (list (list (all-done 14) counters-written) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (let ((script (run-script db counters-script)))
         (list (map car script) (map cadr script)))))))

;; The oracle is held to the literal by a second route too: they must agree.
(test-equal "the oracle's counters are the written-out ones: the comparison above is of the library with the library, and this holds the oracle to the literal"
  counters-written
  counters-oracle)

;; The rows of the 64-bit range: an int binding of sqlite3_last_insert_rowid
;; reads the low 32 bits, sign-extended: 2^63-1 as -1, -2^63 as 0 and
;; 2^32+1 as 1.
(test-equal "sqlite3_last_insert_rowid after an insert at rowid 2^63-1 is 9223372036854775807, whole; every count is zero after"
  (list 9223372036854775807 ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (let* ((created (run-statement db "create table r(id integer primary key)"))
              (inserted (run-statement db "insert into r values (9223372036854775807)")))
         (sqlite3-last-insert-rowid db))))))

(test-equal "sqlite3_last_insert_rowid after an insert at rowid -2^63 is -9223372036854775808, whole; every count is zero after"
  (list -9223372036854775808 ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (let* ((created (run-statement db "create table r(id integer primary key)"))
              (inserted (run-statement db "insert into r values (-9223372036854775808)")))
         (sqlite3-last-insert-rowid db))))))

(test-equal "sqlite3_last_insert_rowid after an insert at rowid 2^32+1 is 4294967297, whole; every count is zero after"
  (list 4294967297 ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (let* ((created (run-statement db "create table r(id integer primary key)"))
              (inserted (run-statement db "insert into r values (4294967297)")))
         (sqlite3-last-insert-rowid db))))))

(define (rowid-script-answer)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (let ((script (run-script db rowid-script)))
         (list (map car script) (map cadr script)))))))

(test-equal "the 64-bit script, a create and three inserts at 2^63-1, -2^63 and 2^32+1, reads the oracle's four counters after each, whole; every statement answers OK, DONE, OK, and every count is zero after"
  (list (list (all-done 4) rowids-oracle) ok zero-counts)
  (rowid-script-answer))

(test-equal "the 64-bit script has the written-out counters: rowids whole, changes 1 and totals 1 to 3 for each insert"
  (list (list (all-done 4)
              '((0 0 0 1) (1 1 9223372036854775807 1) (1 2 -9223372036854775808 1)
                (1 3 4294967297 1)))
        ok zero-counts)
  (rowid-script-answer))

;; get_autocommit, each state its own row: a fresh connection is in
;; autocommit mode; BEGIN leaves it; COMMIT and ROLLBACK return to it.
(test-equal "sqlite3_get_autocommit is 1 on a fresh :memory: connection, outside any transaction; every count is zero after"
  (list 1 ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory (lambda (db) (sqlite3-get-autocommit db)))))

(test-equal "sqlite3_get_autocommit is 0 inside BEGIN; every code is OK, DONE, OK and every count is zero after"
  (list (list (list ok sqlite-done ok) 0) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (let* ((began (run-statement db "begin"))
              (flag (sqlite3-get-autocommit db)))
         (list began flag))))))

(test-equal "sqlite3_get_autocommit is 1 after BEGIN and COMMIT, the flag 0 between them; every count is zero after"
  (list (list (list ok sqlite-done ok) 0 (list ok sqlite-done ok) 1) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (let* ((began (run-statement db "begin"))
              (inside (sqlite3-get-autocommit db))
              (committed (run-statement db "commit"))
              (outside (sqlite3-get-autocommit db)))
         (list began inside committed outside))))))

(test-equal "sqlite3_get_autocommit is 1 after BEGIN and ROLLBACK, the flag 0 between them; every count is zero after"
  (list (list (list ok sqlite-done ok) 0 (list ok sqlite-done ok) 1) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (let* ((began (run-statement db "begin"))
              (inside (sqlite3-get-autocommit db))
              (rolled (run-statement db "rollback"))
              (outside (sqlite3-get-autocommit db)))
         (list began inside rolled outside))))))

;; sqlite3_interrupt, on one thread: deterministic. A statement held at a
;; row is running, so the interrupt reaches it; with none running it is lost
;; (the M3 plan, section 4.4; research: concurrency I2, I3).
(define interrupted (code-of 'interrupt))

(test-equal "sqlite3_interrupt answers the unspecified value, as a void result does, never a number"
  (list 'void ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory (lambda (db) (if (eq? (sqlite3-interrupt db) (void)) 'void 'not-void)))))

(test-equal "a statement held at its row, then sqlite3_interrupt: its next step answers SQLITE_INTERRUPT, 9, and its finalize that code too; a statement after it runs to a row, 7, and DONE; every count is zero after"
  (list (list sqlite-row interrupted interrupted (list ok sqlite-row 7 sqlite-done ok))
        ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (let* ((prepared (prepare db "select 1 union all select 2"))
              (statement (cadr prepared))
              (held (sqlite3-step statement))
              (void-result (sqlite3-interrupt db))
              (stopped (sqlite3-step statement))
              (finalized (sqlite3-finalize statement))
              (next (prepare db "select 7"))
              (next-statement (cadr next))
              (row (sqlite3-step next-statement))
              (value (sqlite3-column-int64 next-statement 0))
              (done (sqlite3-step next-statement))
              (next-finalized (sqlite3-finalize next-statement)))
         (list held stopped finalized
               (list (car next) row value done next-finalized)))))))

(test-equal "sqlite3_interrupt with no statement running is a no-op: on a fresh connection, the next statement, select 7, steps to a row, 7, and DONE, and finalizes SQLITE_OK; every count is zero after"
  (list (list ok sqlite-row 7 sqlite-done ok) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (let* ((void-result (sqlite3-interrupt db))
              (next (prepare db "select 7"))
              (statement (cadr next))
              (row (sqlite3-step statement))
              (value (sqlite3-column-int64 statement 0))
              (done (sqlite3-step statement))
              (finalized (sqlite3-finalize statement)))
         (list (car next) row value done finalized))))))

(test-equal "sqlite3_interrupt after a statement ran to DONE, not reset, is lost too: another statement, select 9, then steps to a row, 9, and DONE; every code is OK or DONE or ROW as written, and every count is zero after"
  (list (list ok sqlite-row sqlite-done ok sqlite-row 9 sqlite-done ok ok) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (let* ((first (prepare db "select 1"))
              (first-statement (cadr first))
              (first-row (sqlite3-step first-statement))
              (first-done (sqlite3-step first-statement))
              (void-result (sqlite3-interrupt db))
              (second (prepare db "select 9"))
              (second-statement (cadr second))
              (second-row (sqlite3-step second-statement))
              (value (sqlite3-column-int64 second-statement 0))
              (second-done (sqlite3-step second-statement))
              (first-finalized (sqlite3-finalize first-statement))
              (second-finalized (sqlite3-finalize second-statement)))
         (list (car first) first-row first-done (car second) second-row value second-done
               first-finalized second-finalized))))))

;; --- M4's three: sqlite3_db_config, sqlite3_free and sqlite3_load_extension -------------------------
;; sqlite3_db_config is variadic, int sqlite3_db_config(sqlite3*, int op, ...),
;; bound once in the shape (db op int int*) with (__varargs_after 2): the op's
;; value, then a counted int block, its cell, which gets the op's state after
;; every call, a set's as a read's (ADR-0021, decision 4; research D6). A
;; value of -1 reads and changes nothing. On x86-64 a binding without the
;; convention answers alike, so these rows hold the binding's behaviour, and
;; test-conventions, with make check-variadic, its convention.

;; op-of : Symbol -> (U Natural (List 'no-op Symbol))
;; A db_config op's value, from (chez-sqlite3 private constants), which
;; tests/test-constants.sps holds to sqlite3.h; reached through eval, so a
;; name the library lacks is a sentinel that the binding refuses, and the
;; rows that use it fail by name, where an import would end the suite
;; unnamed.
(define (op-of name)
  (guard (e (#t (list 'no-op name)))
    (eval name (environment '(chez-sqlite3 private constants)))))

(define enable-load-extension-op (op-of 'sqlite-dbconfig-enable-load-extension))
(define defensive-op (op-of 'sqlite-dbconfig-defensive))
(define dqs-dml-op (op-of 'sqlite-dbconfig-dqs-dml))
(define dqs-ddl-op (op-of 'sqlite-dbconfig-dqs-ddl))

;; config-call : Natural Integer Integer Integer -> (List Integer Integer)
;; sqlite3_db_config of OP with VALUE on DB, its cell native's counted int
;; block, call-with-int-cell's, that holds SENTINEL before the call: the
;; code, and the cell after it.
(define (config-call db op value sentinel)
  (let-values (((code after)
                (call-with-int-cell 'test-native sentinel
                  (lambda (cell) (sqlite3-db-config db op value cell)))))
    (list code after)))

;; config-round-trip : Natural Integer -> Any
;; On a :memory: connection of its own: OP read with -1, set to the other of
;; 0 and 1, read, set back to the start, read; each cell's sentinel BASE plus
;; the call's place, 1 to 5, so no call can pass on another's. Each call is
;; its code and its cell, the cell named start or other once the start, the
;; first call's, is known, and kept as a number when it is neither.
(define (config-round-trip op base)
  (with-memory
   (lambda (db)
     (let* ((read-start (config-call db op -1 (+ base 1)))
            (start (cadr read-start))
            (other (if (eqv? start 0) 1 0))
            (set-other (config-call db op other (+ base 2)))
            (read-other (config-call db op -1 (+ base 3)))
            (set-start (config-call db op start (+ base 4)))
            (read-back (config-call db op -1 (+ base 5)))
            (named (lambda (call)
                     (list (car call)
                           (cond ((eqv? (cadr call) start) 'start)
                                 ((eqv? (cadr call) other) 'other)
                                 (else (cadr call)))))))
       (list (if (memv start '(0 1)) 'start-is-0-or-1 (list 'start start))
             (in-order named (list read-start set-other read-other set-start read-back)))))))

(define round-tripped
  (list (list 'start-is-0-or-1 (list (list ok 'start) (list ok 'other) (list ok 'other)
                                     (list ok 'start) (list ok 'start)))
        ok zero-counts))

(for-each
 (lambda (op-case)
   (test-equal (string-append "sqlite3_db_config round-trips " (car op-case)
                              " through the binding: read with -1, set to the other value, read, set back and read, every call SQLITE_OK and its cell the state after it, a fresh sentinel before each; the close answers SQLITE_OK and every count is zero after")
     round-tripped
     (guard (e (#t (list 'raised (describe e))))
       (config-round-trip (cadr op-case) (caddr op-case)))))
 (list (list "DEFENSIVE" defensive-op 7100)
       (list "DQS_DML" dqs-dml-op 7200)
       (list "DQS_DDL" dqs-ddl-op 7300)))

;; extension-loading? : Boolean
;; Whether native's load found sqlite3_load_extension: its own record, which
;; the suites choose their load rows by (ADR-0005, amended 2026-11-17).
(define extension-loading? (eq? load-extension-available? #t))

;; load-row : String Any (-> Any) -> Void
;; The test NAME, EXPECTED against THUNK's answer, on a library that has
;; sqlite3_load_extension. On one without it, as Apple's, NAME is printed
;; UNAVAILABLE, never skipped silently, and in its place native's record
;; and its binding, #f both, are asserted.
(define (load-row name expected thunk)
  (if extension-loading?
      (test-equal name expected (guard (e (#t (list 'raised (describe e)))) (thunk)))
      (begin
        (display "UNAVAILABLE ")
        (display name)
        (display ": this libsqlite3 has no sqlite3_load_extension")
        (newline)
        (test-equal (string-append "unavailable, the library has no sqlite3_load_extension, in place of: " name)
          '(#f #f)
          (list load-extension-available? sqlite3-load-extension)))))

;; Apple's library answers 21 to every call of ENABLE_LOAD_EXTENSION and
;; leaves the cell, and lacks sqlite3_load_extension (the M4 pre-work's Mac
;; step), so its round trip is chosen by native's record.
(load-row "sqlite3_db_config round-trips ENABLE_LOAD_EXTENSION through the binding: read with -1, set to the other value, read, set back and read, every call SQLITE_OK and its cell the state after it, a fresh sentinel before each; the close answers SQLITE_OK and every count is zero after"
  round-tripped
  (lambda () (config-round-trip enable-load-extension-op 7400)))

;; 1999 is above SQLITE_DBCONFIG_MAX in every header measured, 1019 at the
;; floor and 1023 in 3.53.1's and 3.54.1's (the M4 pre-work).
(test-equal "sqlite3_db_config of an op the library does not know, 1999, answers SQLITE_ERROR and leaves the cell at its sentinel, to set and to read; the close answers SQLITE_OK and every count is zero after"
  (list (list (list error-code 7501) (list error-code 7502)) ok zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (with-memory
     (lambda (db)
       (let* ((set (config-call db 1999 1 7501))
              (read (config-call db 1999 -1 7502)))
         (list set read))))))

(test-equal "sqlite3_free of NULL does nothing, and answers the unspecified value, as a void result does, never a number; every count is zero after"
  (list 'void zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (list (if (eq? (sqlite3-free 0) (void)) 'void 'not-void) (native-counts))))

;; Native's record of the optional entry point is this process's own answer:
;; foreign-entry? asks the whole process, which holds the one libsqlite3
;; native loaded (ADR-0002, amended), and the binding is a procedure exactly
;; when the record says it is there.
(test-equal "load-extension-available?, native's record, is a boolean, this process's own foreign-entry? of sqlite3_load_extension, and sqlite3-load-extension is a procedure exactly when it is #t"
  (let ((there (foreign-entry? "sqlite3_load_extension")))
    (list there there))
  (list load-extension-available?
        (and (boolean? load-extension-available?) (procedure? sqlite3-load-extension))))

;; load-call : Natural String -> (List Integer (U String (List 'no-message Any)))
;; sqlite3_load_extension of PATH on DB with no entry point, its message's
;; slot a counted out-pointer: its code, and the slot's message, copied,
;; then freed with sqlite3_free whatever the copy did.
(define (load-call db path)
  (call-with-c-string 'test-native path
    (lambda (file)
      (let-values (((code message)
                    (call-with-out-pointer 'test-native
                      (lambda (slot) (sqlite3-load-extension db file 0 slot)))))
        (let ((text (guard (e (#t (list 'raised (describe e))))
                      (and (not (eqv? message 0)) (c-string->string message)))))
          (unless (eqv? message 0) (sqlite3-free message))
          (list code (if (string? text) text (list 'no-message text))))))))

;; message-of : (List Integer Any) -> (List Integer Symbol)
;; A load's code, and message for a string, as a row names it: it never
;; asserts SQLite's text (ADR-0013, decision 9).
(define (message-of answer)
  (list (car answer) (if (string? (cadr answer)) 'message (cadr answer))))

;; A file that is no shared object: dlopen refuses it, and so does the path
;; with .so appended, which isn't there (research L2). SQLite's message is
;; its own allocation, and an unfreed one shows in the memory check and
;; under the gate's Valgrind (X1). With the C call off the load answers "not
;; authorized" without opening anything, so the row loads twice, with the
;; call set off, then on, through the binding: each a failure with a
;; message, and the two messages differ, two readings of one library, no
;; text written here. A set that did not take, which leaves the call as the
;; library starts it, gives two alike.
(load-row "sqlite3_load_extension of a file that is no shared object answers SQLITE_ERROR and a message, which sqlite3_free frees, with ENABLE_LOAD_EXTENSION set to 0 through the binding and then to 1, and the two messages differ; the close answers SQLITE_OK and every count is zero after"
  (list (list (list ok 0) (list error-code 'message) (list ok 1) (list error-code 'message) 'messages-differ)
        ok zero-counts)
  (lambda ()
    (call-with-temp-directory
     (lambda (dir)
       (let* ((path (string-append dir "/not-a-library.so"))
              (written (capture-command
                        (list "sh" "-c" "printf 'no ELF here\\n' >\"$1\"" "sh" path))))
         (if (not (equal? written '(0 "" "")))
             (list 'not-written written)
             (with-memory
              (lambda (db)
                (let* ((off (config-call db enable-load-extension-op 0 7601))
                       (refused (load-call db path))
                       (on (config-call db enable-load-extension-op 1 7602))
                       (failed (load-call db path)))
                  (list off (message-of refused) on (message-of failed)
                        (if (equal? (cadr refused) (cadr failed)) 'messages-alike 'messages-differ)))))))))))

;; --- call-with-c-string and c-string->string ----------------------------------------------------

;; c-bytes : String -> Any
;; What call-with-c-string hands C for STRING, read with foreign-ref up to
;; and with its NUL; c-string->string's answer for the same address; and the
;; counts while PROC runs. Or what was raised.
(define (c-bytes string)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e)
                  (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other (describe e))))
    (call-with-c-string 'open-database string
      (lambda (address)
        (let loop ((i 0) (found '()))
          (let ((b (foreign-ref 'unsigned-8 address i)))
            (if (= b 0)
                (list (reverse (cons 0 found)) (c-string->string address) (native-counts))
                (loop (+ i 1) (cons b found)))))))))

(test-equal "call-with-c-string hands C UTF-8 and a NUL: é is 195 169, λ is 206 187, € is 226 130 172, U+1F600 is 240 159 152 128, \"\" is the NUL alone; c-string->string reads each back; one block is counted while PROC runs"
  (list (list '(195 169 0) "\xE9;" (counts-with '((block . 1))))
        (list '(206 187 0) "\x3BB;" (counts-with '((block . 1))))
        (list '(226 130 172 0) "\x20AC;" (counts-with '((block . 1))))
        (list '(240 159 152 128 0) "\x1F600;" (counts-with '((block . 1))))
        (list '(0) "" (counts-with '((block . 1))))
        zero-counts)
  (let* ((a (c-bytes "\xE9;"))
         (b (c-bytes "\x3BB;"))
         (c (c-bytes "\x20AC;"))
         (d (c-bytes "\x1F600;"))
         (e (c-bytes "")))
    (list a b c d e (native-counts))))

;; at-raise : (-> Any) (Condition -> Any) -> (List Any Any)
;; What THUNK raised, through HANDLE, and the native counts at the moment of
;; the raise: read by a handler that runs before any dynamic-wind's after
;; thunk, then raises on. The counts after are a separate reading.
(define (at-raise thunk handle)
  (let ((seen 'no-raise))
    (let ((r (guard (e (#t (handle e)))
               (with-exception-handler
                 (lambda (c) (set! seen (native-counts)) (raise c))
                 thunk))))
      (list r seen))))

;; U+0000 at every place a scan can miss: first, in the middle, last, the
;; whole string, and beside characters past ASCII on both sides. "Before
;; anything is allocated" is read at the raise: a refusal made once the
;; block existed shows it there, though the block is freed by the time the
;; raise is caught.
(for-each
 (lambda (string)
   (test-equal (string-append "call-with-c-string refuses "
                              (call-with-string-output-port (lambda (p) (write string p)))
                              " as an assertion violation from its WHO, naming it by its kind, with nothing allocated at the raise, and PROC not run")
     (list (list (list 'assertion-violation 'open-database '((kind string)))
                 zero-counts)
           'proc-not-run zero-counts)
     (let* ((ran #f)
            (r (at-raise (lambda ()
                           (call-with-c-string 'open-database string
                             (lambda (address) (set! ran #t) 'ran)))
                         (lambda (e)
                           (if (and (assertion-violation? e) (who-condition? e)
                                    (message-condition? e) (irritants-condition? e))
                               (list 'assertion-violation (condition-who e) (condition-irritants e))
                               (list 'other (describe e)))))))
       (list r (if ran 'proc-ran 'proc-not-run) (native-counts)))))
 '("\x0;abc" "a\x0;b" "abc\x0;" "\x0;" "\xE9;\x0;\x3BB;" "\x1F600;\x0;" "\x20AC;\x0;"))

(test-equal "the U+0000 refusal is an assertion violation, and no &chez-sqlite3-error: a caller's mistake (ADR-0013, decision 1)"
  '(assertion-violation not-a-library-condition)
  (guard (e (#t (list (if (assertion-violation? e) 'assertion-violation 'other)
                      (if (chez-sqlite3-error? e) 'a-library-condition 'not-a-library-condition))))
    (call-with-c-string 'open-database "a\x0;b" (lambda (address) 'ran))
    '(no-raise)))

(test-equal "the round trip: a string through call-with-c-string and c-string->string comes back the same"
  "file:app.db?vfs=\x3BB;&\xE9;=\x1F600;"
  (guard (e (#t (list 'raised (describe e))))
    (call-with-c-string 'open-database "file:app.db?vfs=\x3BB;&\xE9;=\x1F600;" c-string->string)))

;; The NUL is written, not found: the block call-with-c-string makes for a
;; 39-byte string is 40 bytes, and malloc's last one freed, of that size,
;; was filled with #xFF first, so a copy that left the NUL out leaves #xFF
;; where it belongs. The row needs that very block back, and glibc hands it
;; back; so the row asserts the address, and where the block is a different
;; one (Valgrind never reuses a block at once, and calls a NUL left unwritten
;; an uninitialised read itself) it is skipped, named, with a line saying why.
(define nul-row-name "call-with-c-string writes the NUL itself: a fresh block that held #xFF reads the string's bytes, then 0")

(define nul-row-run
  (guard (e (#t (list 'raised (describe e))))
    (let ((freed (with-block 40 (lambda (block) (poke! block (make-list-of 40 #xFF)) block))))
      (call-with-c-string 'open-database "abcdefghijklmnopqrstuvwxyz0123456789ABC"
        (lambda (address) (list 'ran (eqv? address freed) (peek address 40)))))))

;; reuse-unavailable? : Any -> Boolean
;; Whether a run completed on a block that is not the one just freed.
(define (reuse-unavailable? run)
  (and (pair? run) (eq? (car run) 'ran) (pair? (cdr run)) (not (cadr run))))

;; skip-unavailable! : String Any -> Void
;; When RUN is reuse-unavailable?, say so by NAME and skip the test of that
;; name that follows: a skip is its own result, never a pass.
(define (skip-unavailable! name run)
  (when (reuse-unavailable? run)
    (display "UNAVAILABLE ")
    (display name)
    (display ": malloc did not hand back the block just freed")
    (newline)
    (test-skip name)))

(skip-unavailable! nul-row-name nul-row-run)
(test-equal nul-row-name
  (list 'ran #t
        (append (bytevector->u8-list (string->utf8 "abcdefghijklmnopqrstuvwxyz0123456789ABC")) '(0)))
  nul-row-run)

(test-equal "c-string->string answers #f for NULL, compared as the symbol null, and refuses what is no address"
  (list 'null
        (list 'assertion-violation 'c-string->string '(x))
        (list 'assertion-violation 'c-string->string '(-1))
        (list 'assertion-violation 'c-string->string '(1.5)))
  (let* ((null (guard (e (#t (list 'raised (describe e))))
                 (let ((r (c-string->string 0))) (if (eq? r #f) 'null r))))
         (a (raised (lambda () (c-string->string 'x))))
         (b (raised (lambda () (c-string->string -1))))
         (c (raised (lambda () (c-string->string 1.5)))))
    (list null a b c)))

;; Chez's utf8->string drops one leading U+FEFF; an error message is data a
;; user controls (a trigger's RAISE), so c-string->string keeps it. Each block
;; is read as bytes the row writes itself, so no encoder is under test.
;; Invalid bytes are replaced, never refused: the second block's FF is U+FFFD.
(test-equal "c-string->string reads EF BB BF 61 as U+FEFF then a, keeps a second U+FEFF, keeps one before an invalid byte (replaced, not refused), and reads a BOM-less block and a 2-byte EF BB as before"
  (list "\xFEFF;a" "\xFEFF;\xFEFF;a" "\xFEFF;\xFFFD;" "a\xFEFF;" "\xFFFD;")
  (guard (e (#t (list 'raised (describe e))))
    (let ((read (lambda (bytes)
                  (with-block 8
                    (lambda (block)
                      (poke! block (append bytes '(0)))
                      (c-string->string block))))))
      (let* ((a (read '(#xEF #xBB #xBF #x61)))
             (b (read '(#xEF #xBB #xBF #xEF #xBB #xBF #x61)))
             (c (read '(#xEF #xBB #xBF #xFF)))
             (d (read '(#x61 #xEF #xBB #xBF)))
             (e2 (read '(#xEF #xBB))))
        (list a b c d e2)))))

(test-equal "call-with-c-string: a raise from PROC frees the block, and reaches the caller"
  (list 'proc-raised zero-counts)
  (let ((r (guard (e ((eq? e 'from-proc) 'proc-raised)
                     (#t (list 'other (describe e))))
             (call-with-c-string 'open-database "abc" (lambda (address) (raise 'from-proc))))))
    (list r (native-counts))))

(test-equal "call-with-c-string: an escape from PROC through a continuation frees the block"
  (list 'escaped zero-counts)
  (let ((r (guard (e (#t (list 'other (describe e))))
             (call/cc
              (lambda (k)
                (call-with-c-string 'open-database "abc" (lambda (address) (k 'escaped))))))))
    (list r (native-counts))))

(test-equal "call-with-c-string: re-entering PROC through a continuation, once the block is freed, raises from its WHO, and PROC runs once"
  (list (list 'assertion-violation 'open-database '()) 1 zero-counts)
  (let ((k #f) (runs 0))
    (let ((r (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e)
                             (irritants-condition? e))
                        (list 'assertion-violation (condition-who e) (condition-irritants e)))
                       (#t (list 'other (describe e))))
               (call-with-c-string 'open-database "abc"
                 (lambda (address)
                   (call/cc (lambda (c) (set! k c)))
                   (set! runs (+ runs 1))))
               (if (= runs 1) (k #f) (list 'reentered runs)))))
      (list r runs (native-counts)))))

(test-equal "call-with-c-string refuses what is no string and a PROC that is no procedure, from its WHO, and a WHO that is no symbol, from itself, each by shown-value"
  (list (list 'assertion-violation 'open-database '(abc))
        (list 'assertion-violation 'open-database '(not-a-procedure))
        (list 'assertion-violation 'open-database '((kind list)))
        (list 'assertion-violation 'call-with-c-string '((kind string)))
        zero-counts)
  (let* ((a (raised (lambda () (call-with-c-string 'open-database 'abc (lambda (address) address)))))
         (b (raised (lambda () (call-with-c-string 'open-database "abc" 'not-a-procedure))))
         (c (raised (lambda () (call-with-c-string 'open-database '("abc") (lambda (address) address)))))
         (d (raised (lambda () (call-with-c-string "open-database" "abc" (lambda (address) address))))))
    (list a b c d (native-counts))))

;; --- call-with-out-pointer ---------------------------------------------------------------------

(test-equal "call-with-out-pointer answers PROC's answer and the pointer PROC wrote to the slot; one block is counted while PROC runs, and none after"
  (list (list 'proc-answer (counts-with '((block . 1)))) #x12345678 zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (let-values (((answer pointer)
                  (call-with-out-pointer 'open-database
                    (lambda (slot)
                      (foreign-set! 'uptr slot 0 #x12345678)
                      (list 'proc-answer (native-counts))))))
      (list answer pointer (native-counts)))))

;; The slot is zeroed, not found zero: malloc's last block freed of a
;; pointer's size held #xFF, so a slot left unwritten reads all ones. As for
;; the NUL, the row needs that block back, asserts it, and is skipped, named,
;; where it is another.
(define zero-row-name "call-with-out-pointer zeroes the slot first: a PROC that writes nothing reads 0, on a fresh block that held #xFF")

(define zero-row-run
  (guard (e (#t (list 'raised (describe e))))
    (let ((freed (with-block (foreign-sizeof 'uptr)
                             (lambda (block)
                               (poke! block (make-list-of (foreign-sizeof 'uptr) #xFF))
                               block)))
          (reused 'unset))
      (call-with-values
       (lambda ()
         (call-with-out-pointer 'open-database
           (lambda (slot) (set! reused (eqv? slot freed)) 'wrote-nothing)))
       (lambda (answer pointer) (list 'ran reused answer pointer))))))

(skip-unavailable! zero-row-name zero-row-run)
(test-equal zero-row-name
  (list 'ran #t 'wrote-nothing 0)
  zero-row-run)

(test-equal "call-with-out-pointer: a raise from PROC frees the slot, and reaches the caller; so does an escape"
  (list 'proc-raised 'escaped zero-counts)
  (let* ((a (guard (e ((eq? e 'from-proc) 'proc-raised)
                      (#t (list 'other (describe e))))
              (call-with-out-pointer 'open-database (lambda (slot) (raise 'from-proc)))))
         (b (guard (e (#t (list 'other (describe e))))
              (call/cc
               (lambda (k)
                 (call-with-out-pointer 'open-database (lambda (slot) (k 'escaped))))))))
    (list a b (native-counts))))

(test-equal "call-with-out-pointer: re-entering PROC through a continuation, once the slot is freed, raises from its WHO, and PROC runs once"
  (list (list 'assertion-violation 'open-database '()) 1 zero-counts)
  (let ((k #f) (runs 0))
    (let ((r (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e)
                             (irritants-condition? e))
                        (list 'assertion-violation (condition-who e) (condition-irritants e)))
                       (#t (list 'other (describe e))))
               (call-with-out-pointer 'open-database
                 (lambda (slot)
                   (call/cc (lambda (c) (set! k c)))
                   (set! runs (+ runs 1))))
               (if (= runs 1) (k #f) (list 'reentered runs)))))
      (list r runs (native-counts)))))

(test-equal "call-with-out-pointer refuses a PROC that is no procedure, from its WHO, and a WHO that is no symbol, from itself"
  (list (list 'assertion-violation 'open-database '(not-a-procedure))
        (list 'assertion-violation 'call-with-out-pointer '(42))
        zero-counts)
  (let* ((a (raised (lambda () (call-with-out-pointer 'open-database 'not-a-procedure))))
         (b (raised (lambda () (call-with-out-pointer 42 (lambda (slot) slot))))))
    (list a b (native-counts))))

;; --- call-with-int-cell (M4 slice 2) -------------------------------------------------------------
;; sqlite3_db_config's cell: a counted int block, its fill a sentinel of the
;; caller's, read after PROC (ADR-0021, decision 3). A fill of 0, which a set
;; writes, would make a call that left the cell read as one that wrote 0.

;; int-bound : Integer -> Integer
;; 2^(B-1) for a C int of B bits: the first value above an int's range.
(define int-bound (expt 2 (- (* 8 (foreign-sizeof 'int)) 1)))

(test-equal "call-with-int-cell writes its fill first: a PROC that writes nothing reads back each fill, -1, 7, 255, and an int's two bounds, -2^31 and 2^31-1, never 0; one block is counted while PROC runs, and none after"
  (list (map (lambda (fill) (list (list 'wrote-nothing (counts-with '((block . 1)))) fill))
             (list -1 7 255 (- int-bound) (- int-bound 1)))
        zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (let ((answers (in-order (lambda (fill)
                               (let-values (((answer value)
                                             (call-with-int-cell 'open-database fill
                                               (lambda (cell) (list 'wrote-nothing (native-counts))))))
                                 (list answer value)))
                             (list -1 7 255 (- int-bound) (- int-bound 1)))))
      (list answers (native-counts)))))

(test-equal "call-with-int-cell reads the cell once PROC has returned: over a fill of -1, a PROC that writes 42, then -5, reads -5, and its answer is PROC's"
  (list (list 'wrote -1) -5 zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (let-values (((answer value)
                  (call-with-int-cell 'open-database -1
                    (lambda (cell)
                      (let ((before (foreign-ref 'int cell 0)))
                        (foreign-set! 'int cell 0 42)
                        (foreign-set! 'int cell 0 -5)
                        (list 'wrote before))))))
      (list answer value (native-counts)))))

(test-equal "call-with-int-cell: a raise from PROC frees the cell, and reaches the caller; so does an escape; the count is back at 0 after each"
  (list 'proc-raised zero-counts 'escaped zero-counts)
  (let* ((a (guard (e ((eq? e 'from-proc) 'proc-raised)
                      (#t (list 'other (describe e))))
              (call-with-int-cell 'open-database -1 (lambda (cell) (raise 'from-proc)))))
         (after-a (native-counts))
         (b (guard (e (#t (list 'other (describe e))))
              (call/cc
               (lambda (k)
                 (call-with-int-cell 'open-database -1 (lambda (cell) (k 'escaped)))))))
         (after-b (native-counts)))
    (list a after-a b after-b)))

(test-equal "call-with-int-cell: re-entering PROC through a continuation, once the cell is freed, raises from its WHO, and PROC runs once"
  (list (list 'assertion-violation 'open-database '()) 1 zero-counts)
  (let ((k #f) (runs 0))
    (let ((r (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e)
                             (irritants-condition? e))
                        (list 'assertion-violation (condition-who e) (condition-irritants e)))
                       (#t (list 'other (describe e))))
               (call-with-int-cell 'open-database -1
                 (lambda (cell)
                   (call/cc (lambda (c) (set! k c)))
                   (set! runs (+ runs 1))))
               (if (= runs 1) (k #f) (list 'reentered runs)))))
      (list r runs (native-counts)))))

;; The range is a C int's, not Chez's foreign int's, which also takes 2^31
;; to 2^32-1 and hands them to C as negatives (AGENTS.md).
(test-equal "call-with-int-cell refuses a fill no C int holds, from its WHO, by shown-value, with nothing allocated at the raise and without running PROC: 2^31, -2^31-1, 2^32-1, the top of what Chez's foreign int takes, 2^32 and 2^63 beyond it, 1.5, 1.0, a symbol and a string"
  (list (map (lambda (irritant)
               (list (list 'assertion-violation 'open-database (list irritant)) zero-counts))
             (list int-bound (- (- int-bound) 1) (- (* 2 int-bound) 1) (* 2 int-bound) (expt 2 63)
                   1.5 1.0 'one '(kind string)))
        0 zero-counts)
  (let* ((runs 0)
         (refusals
          (in-order (lambda (fill)
                      (at-raise (lambda ()
                                  (call-with-int-cell 'open-database fill
                                    (lambda (cell) (set! runs (+ runs 1)) 'ran)))
                                (lambda (e)
                                  (if (and (assertion-violation? e) (who-condition? e)
                                           (irritants-condition? e))
                                      (list 'assertion-violation (condition-who e) (condition-irritants e))
                                      (list 'other (describe e))))))
                    (list int-bound (- (- int-bound) 1) (- (* 2 int-bound) 1) (* 2 int-bound)
                          (expt 2 63) 1.5 1.0 'one "1"))))
    (list refusals runs (native-counts))))

(test-equal "call-with-int-cell refuses a PROC that is no procedure, from its WHO, and a WHO that is no symbol, from itself"
  (list (list 'assertion-violation 'open-database '(not-a-procedure))
        (list 'assertion-violation 'call-with-int-cell '(42))
        zero-counts)
  (let* ((a (raised (lambda () (call-with-int-cell 'open-database -1 'not-a-procedure))))
         (b (raised (lambda () (call-with-int-cell 42 -1 (lambda (cell) cell))))))
    (list a b (native-counts))))

;; --- call-with-bytes, foreign-bytes and c-string->bytevector (M2 slice 4) -------------------------
;; A bound TEXT or BLOB, and a column's bytes and name read back, cross in
;; counted blocks and are copied by native's own code (ADR-0011, decisions 2
;; and 4; ADR-0015, decisions 5, 7 and 9). No other library may read or write
;; foreign memory (check-seam).

;; long-bytes : Bytevector
;; 5,000 bytes, each its index modulo 256, so a copy that drops, repeats or
;; shifts a byte is told apart.
(define long-bytes
  (let ((b (make-bytevector 5000 0)))
    (let loop ((i 0))
      (when (< i 5000)
        (bytevector-u8-set! b i (mod i 256))
        (loop (+ i 1))))
    b))

;; in-block : Bytevector -> Any
;; What call-with-bytes hands PROC for BYTES: whether the address is a
;; pointer, never NULL; the block's first (max 1 n) bytes, read with
;; foreign-ref, as a bytevector, or same when they equal BYTES whole; and the
;; counts while PROC runs. Or what was raised.
(define (in-block bytes)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other (describe e))))
    (call-with-bytes 'bind! bytes
      (lambda (address)
        (let ((read (u8-list->bytevector (peek address (max 1 (bytevector-length bytes))))))
          (list (if (and (integer? address) (exact? address) (positive? address)) 'pointer address)
                (if (and (> (bytevector-length bytes) 0) (equal? read bytes)) 'same read)
                (native-counts)))))))

(test-equal "call-with-bytes hands C a bytevector's bytes in a counted block, never NULL: none is one byte, 0; 00, 61 00 62, 00 00 00 and C3 A9 FF FE 80 as given, U+0000 kept; 5,000 bytes whole; one block counted while PROC runs, and none after"
  (list (list 'pointer #vu8(0) (counts-with '((block . 1))))
        (list 'pointer 'same (counts-with '((block . 1))))
        (list 'pointer 'same (counts-with '((block . 1))))
        (list 'pointer 'same (counts-with '((block . 1))))
        (list 'pointer 'same (counts-with '((block . 1))))
        (list 'pointer 'same (counts-with '((block . 1))))
        zero-counts)
  (let* ((a (in-block #vu8()))
         (b (in-block #vu8(0)))
         (c (in-block #vu8(#x61 0 #x62)))
         (d (in-block #vu8(0 0 0)))
         (e (in-block #vu8(#xC3 #xA9 #xFF #xFE #x80)))
         (f (in-block long-bytes)))
    (list a b c d e f (native-counts))))

(test-equal "call-with-bytes: a raise from PROC frees the block, and reaches the caller; so does an escape"
  (list 'proc-raised 'escaped zero-counts)
  (let* ((a (guard (e ((eq? e 'from-proc) 'proc-raised)
                      (#t (list 'other (describe e))))
              (call-with-bytes 'bind! #vu8(1 2 3) (lambda (address) (raise 'from-proc)))))
         (b (guard (e (#t (list 'other (describe e))))
              (call/cc
               (lambda (k)
                 (call-with-bytes 'bind! #vu8(1 2 3) (lambda (address) (k 'escaped))))))))
    (list a b (native-counts))))

(test-equal "call-with-bytes: re-entering PROC through a continuation, once the block is freed, raises from its WHO, and PROC runs once"
  (list (list 'assertion-violation 'bind! '()) 1 zero-counts)
  (let ((k #f) (runs 0))
    (let ((r (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e)
                             (irritants-condition? e))
                        (list 'assertion-violation (condition-who e) (condition-irritants e)))
                       (#t (list 'other (describe e))))
               (call-with-bytes 'bind! #vu8(1 2 3)
                 (lambda (address)
                   (call/cc (lambda (c) (set! k c)))
                   (set! runs (+ runs 1))))
               (if (= runs 1) (k #f) (list 'reentered runs)))))
      (list r runs (native-counts)))))

;; refused-at-raise : (-> Any) -> (List Any Any Symbol)
;; What THUNK, a call-with-bytes whose PROC records that it ran, raised; the
;; counts at the raise; and whether PROC ran.
(define (refused-at-raise make-thunk)
  (let* ((ran #f)
         (r (at-raise (make-thunk (lambda (address) (set! ran #t) 'ran))
                      (lambda (e)
                        (if (and (assertion-violation? e) (who-condition? e)
                                 (message-condition? e) (irritants-condition? e))
                            (list 'assertion-violation (condition-who e) (condition-irritants e))
                            (list 'other (describe e)))))))
    (append r (list (if ran 'proc-ran 'proc-not-run)))))

(test-equal "call-with-bytes refuses what is no bytevector and a PROC that is no procedure, from its WHO, and a WHO that is no symbol, from itself, each by shown-value, with nothing allocated at the raise and PROC not run"
  (list (list (list 'assertion-violation 'bind! '((kind string))) zero-counts 'proc-not-run)
        (list (list 'assertion-violation 'bind! '(abc)) zero-counts 'proc-not-run)
        (list (list 'assertion-violation 'bind! '((kind vector))) zero-counts 'proc-not-run)
        (list (list 'assertion-violation 'bind! '(not-a-procedure)) zero-counts 'proc-not-run)
        (list (list 'assertion-violation 'call-with-bytes '((kind string))) zero-counts 'proc-not-run)
        zero-counts)
  (let* ((a (refused-at-raise (lambda (proc) (lambda () (call-with-bytes 'bind! "abc" proc)))))
         (b (refused-at-raise (lambda (proc) (lambda () (call-with-bytes 'bind! 'abc proc)))))
         (c (refused-at-raise (lambda (proc) (lambda () (call-with-bytes 'bind! (vector 1 2) proc)))))
         (d (refused-at-raise (lambda (proc) (lambda () (call-with-bytes 'bind! #vu8(1) 'not-a-procedure)))))
         (e (refused-at-raise (lambda (proc) (lambda () (call-with-bytes "bind!" #vu8(1) proc))))))
    (list a b c d e (native-counts))))

;; in-written-block : (Listof Natural) (Natural -> Any) -> Any
;; PROC's answer, given a counted block of at least BYTES' length holding
;; BYTES, freed after; or what was raised.
(define (in-written-block bytes proc)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other (describe e))))
    (with-block (max 1 (length bytes))
      (lambda (block) (poke! block bytes) (proc block)))))

(test-equal "foreign-bytes reads N bytes at an address, undecoded, into a bytevector: 00 61 00 FF 80 C3 whole, its first 2, none at the block, and none at NULL, which it never reads"
  (list #vu8(0 #x61 0 #xFF #x80 #xC3) #vu8(0 #x61) #vu8() #vu8())
  (let* ((a (in-written-block '(0 #x61 0 #xFF #x80 #xC3) (lambda (b) (foreign-bytes b 6))))
         (b (in-written-block '(0 #x61 0 #xFF #x80 #xC3) (lambda (b) (foreign-bytes b 2))))
         (c (in-written-block '(#x61) (lambda (b) (foreign-bytes b 0))))
         (d (guard (e (#t (list 'raised (describe e)))) (foreign-bytes 0 0))))
    (list a b c d)))

(test-equal "foreign-bytes answers a fresh bytevector: the block written after the read leaves it, and two reads are two bytevectors"
  (list #vu8(1 2 3) 'two)
  (in-written-block '(1 2 3)
    (lambda (block)
      (let* ((first (foreign-bytes block 3))
             (second (foreign-bytes block 3)))
        (poke! block '(9 9 9))
        (list first (if (eq? first second) 'one 'two))))))

(test-equal "foreign-bytes refuses an address and a count that are no exact naturals, each named by its field and shown-value, and NULL with bytes to read, from itself"
  (list (list 'assertion-violation 'foreign-bytes '(address x))
        (list 'assertion-violation 'foreign-bytes '(address -1))
        (list 'assertion-violation 'foreign-bytes '(address 1.5))
        (list 'assertion-violation 'foreign-bytes '(count x))
        (list 'assertion-violation 'foreign-bytes '(count -1))
        (list 'assertion-violation 'foreign-bytes '(count 1.5))
        (list 'assertion-violation 'foreign-bytes '(null-address 1)))
  (let* ((a (raised (lambda () (foreign-bytes 'x 1))))
         (b (raised (lambda () (foreign-bytes -1 1))))
         (c (raised (lambda () (foreign-bytes 1.5 1))))
         (d (in-written-block '(1) (lambda (block) (raised (lambda () (foreign-bytes block 'x))))))
         (e (in-written-block '(1) (lambda (block) (raised (lambda () (foreign-bytes block -1))))))
         (f (in-written-block '(1) (lambda (block) (raised (lambda () (foreign-bytes block 1.5))))))
         (g (raised (lambda () (foreign-bytes 0 1)))))
    (list a b c d e f g)))

(test-equal "c-string->bytevector reads the bytes up to the NUL, undecoded: 61 62, none, FF, EF BB BF kept, C3 A9 before a NUL and 78; #f for NULL, compared as the symbol null"
  (list #vu8(#x61 #x62) #vu8() #vu8(#xFF) #vu8(#xEF #xBB #xBF) #vu8(#xC3 #xA9) 'null)
  (let* ((a (in-written-block '(#x61 #x62 0) c-string->bytevector))
         (b (in-written-block '(0) c-string->bytevector))
         (c (in-written-block '(#xFF 0) c-string->bytevector))
         (d (in-written-block '(#xEF #xBB #xBF 0) c-string->bytevector))
         (e (in-written-block '(#xC3 #xA9 0 #x78 0) c-string->bytevector))
         (f (guard (e (#t (list 'raised (describe e))))
              (let ((r (c-string->bytevector 0))) (if (eq? r #f) 'null r)))))
    (list a b c d e f)))

(test-equal "c-string->bytevector answers a fresh bytevector: the block written after the read leaves it, and two reads are two bytevectors"
  (list #vu8(1 2 3) 'two)
  (in-written-block '(1 2 3 0)
    (lambda (block)
      (let* ((first (c-string->bytevector block))
             (second (c-string->bytevector block)))
        (poke! block '(9 9 9 0))
        (list first (if (eq? first second) 'one 'two))))))

(test-equal "c-string->bytevector refuses what is no address, from itself, by shown-value"
  (list (list 'assertion-violation 'c-string->bytevector '(x))
        (list 'assertion-violation 'c-string->bytevector '(-1))
        (list 'assertion-violation 'c-string->bytevector '(1.5)))
  (let* ((a (raised (lambda () (c-string->bytevector 'x))))
         (b (raised (lambda () (c-string->bytevector -1))))
         (c (raised (lambda () (c-string->bytevector 1.5)))))
    (list a b c)))

;; --- raised after the section ---------------------------------------------------------------------
;; A raise made inside a critical section, or a critical dynamic-wind thunk,
;; reaches a with-exception-handler handler with interrupts still disabled:
;; there an engine never expires, and another thread's collection waits for
;; the handler (measured by M1's closing review). Each row's handler reads
;; its depth, as depth-N, and what was raised.

;; interrupt-depth : -> Positive-Integer
;; How many critical sections this thread is inside, plus one: what
;; disable-interrupts answers, put back at once. 1 outside any section.
(define (interrupt-depth)
  (let ((n (disable-interrupts)))
    (enable-interrupts)
    n))

;; handler-depth : (-> Any) -> (U (List 'raised-at-depth Symbol Any) (List 'no-raise Any))
;; The depth a with-exception-handler handler runs at for the first thing
;; THUNK raises, read before anything else, and what it raised: an assertion
;; violation by its who and irritants, else (other TEXT). The handler
;; escapes, so nothing returns into the raise.
(define (handler-depth thunk)
  (call/cc
   (lambda (k)
     (with-exception-handler
      (lambda (c)
        (let* ((depth (interrupt-depth))
               (what (if (and (assertion-violation? c) (who-condition? c) (irritants-condition? c))
                         (list 'assertion-violation (condition-who c) (condition-irritants c))
                         (list 'other (describe c)))))
          (k (list 'raised-at-depth
                   (string->symbol (string-append "depth-" (number->string depth)))
                   what))))
      (lambda () (list 'no-raise (thunk)))))))

;; reentered : ((Positive-Integer -> Any) -> Any) -> Any
;; What a handler of a re-entry into WITH's PROC sees: PROC keeps its
;; continuation, returns, and is entered again once its block is freed.
(define (reentered with)
  (let ((k #f) (runs 0))
    (let ((r (handler-depth
              (lambda ()
                (with (lambda (address)
                        (call/cc (lambda (c) (set! k c)))
                        (set! runs (+ runs 1))))
                (if (= runs 1) (k #f) (list 'reentered runs))))))
      (list r runs (native-counts)))))

(test-equal "call-with-c-string and call-with-out-pointer refuse a re-entry outside their critical thunks: a handler of it runs at depth 1, and PROC runs once"
  (list (list (list 'raised-at-depth 'depth-1 (list 'assertion-violation 'open-database '())) 1 zero-counts)
        (list (list 'raised-at-depth 'depth-1 (list 'assertion-violation 'open-database '())) 1 zero-counts))
  (let* ((a (reentered (lambda (proc) (call-with-c-string 'open-database "abc" proc))))
         (b (reentered (lambda (proc) (call-with-out-pointer 'open-database proc)))))
    (list a b)))

(test-equal "call-with-int-cell refuses a re-entry outside its critical thunks, and a fill no C int holds before any: a handler of each runs at depth 1, and PROC runs once"
  (list (list (list 'raised-at-depth 'depth-1 (list 'assertion-violation 'open-database '())) 1 zero-counts)
        (list 'raised-at-depth 'depth-1 (list 'assertion-violation 'open-database (list int-bound))))
  (let* ((a (reentered (lambda (proc) (call-with-int-cell 'open-database -1 proc))))
         (b (handler-depth (lambda () (call-with-int-cell 'open-database int-bound (lambda (cell) cell))))))
    (list a b)))

;; PROC frees the block it was handed, so the free on the way out finds no
;; live block there: free-foreign-block!'s refusal, raised outside the
;; critical after thunk that tried the free. Nothing is freed twice. Both
;; helpers share that thunk, call-with-block's, and only call-with-c-string
;; is asked: call-with-out-pointer reads its slot once PROC returns, and a
;; slot PROC freed is a read after free, which the gate's Valgrind reports
;; (measured).
(test-equal "call-with-bytes refuses a re-entry outside its critical thunks, and its argument refusals come before any: a handler of each runs at depth 1, and PROC runs once"
  (list (list (list 'raised-at-depth 'depth-1 (list 'assertion-violation 'bind! '())) 1 zero-counts)
        (list 'raised-at-depth 'depth-1 (list 'assertion-violation 'bind! '((kind string))))
        (list 'raised-at-depth 'depth-1 (list 'assertion-violation 'bind! '(x)))
        (list 'raised-at-depth 'depth-1 (list 'assertion-violation 'call-with-bytes '(42))))
  (let* ((a (reentered (lambda (proc) (call-with-bytes 'bind! #vu8(1 2 3) proc))))
         (b (handler-depth (lambda () (call-with-bytes 'bind! "abc" (lambda (address) address)))))
         (c (handler-depth (lambda () (call-with-bytes 'bind! #vu8(1) 'x))))
         (d (handler-depth (lambda () (call-with-bytes 42 #vu8(1) (lambda (address) address))))))
    (list a b c d)))

(test-equal "call-with-bytes raises a failed free outside its critical after thunk: a PROC that freed its block itself makes free-foreign-block! refuse it, and a handler of that runs at depth 1; every count is zero after"
  (list (list 'raised-at-depth 'depth-1 '(assertion-violation free-foreign-block! (that-block))) zero-counts)
  (let* ((given #f)
         (r (handler-depth
             (lambda ()
               (call-with-bytes 'bind! #vu8(1 2 3)
                 (lambda (address) (set! given address) (free-foreign-block! address) 'freed-by-proc))))))
    (list (if (and (eq? (car r) 'raised-at-depth)
                   (equal? (caddr r) (list 'assertion-violation 'free-foreign-block! (list given))))
              (list (car r) (cadr r) '(assertion-violation free-foreign-block! (that-block)))
              r)
          (native-counts))))

(test-equal "call-with-c-string raises a failed free outside its critical after thunk: a PROC that freed its block itself makes free-foreign-block! refuse it, and a handler of that runs at depth 1; every count is zero after"
  (list (list 'raised-at-depth 'depth-1 '(assertion-violation free-foreign-block! (that-block))) zero-counts)
  (let* ((given #f)
         (r (handler-depth
             (lambda ()
               (call-with-c-string 'open-database "abc"
                 (lambda (address) (set! given address) (free-foreign-block! address) 'freed-by-proc))))))
    (list (if (and (eq? (car r) 'raised-at-depth)
                   (equal? (caddr r) (list 'assertion-violation 'free-foreign-block! (list given))))
              (list (car r) (cadr r) '(assertion-violation free-foreign-block! (that-block)))
              r)
          (native-counts))))

;; --- the body, read as data ----------------------------------------------------------------------
;; Neither the order of the load's steps nor whether a binding is eager can be
;; seen with one good library in one process: every check passes, and the load
;; runs once. So native.sls is read as data, forms and never comments, as
;; M1 slice 3's decoy will hold the same by behaviour.

(define native-source "src/chez-sqlite3/private/native.sls")

;; native-body : (U (Listof Any) (List 'unreadable Any))
;; The forms of native's library body, after its name, export and import.
(define native-body
  (guard (e (#t (list 'unreadable (describe e))))
    (let ((form (call-with-port
                 (open-file-input-port native-source (file-options) (buffer-mode block)
                                       (make-transcoder (utf-8-codec)))
                 read)))
      (if (and (list? form) (> (length form) 4) (eq? (car form) 'library))
          (cddddr form)
          (list 'unreadable 'not-a-library-form)))))

(define body-read? (not (and (pair? native-body) (eq? (car native-body) 'unreadable))))

;; load-step-of : Any -> (U (List Symbol Any) #f)
;; (NAME EXPR) for a top-level (define NAME (load-step EXPR)); #f for any
;; other form.
(define (load-step-of form)
  (and (list? form) (= (length form) 3) (eq? (car form) 'define) (symbol? (cadr form))
       (let ((value (caddr form)))
         (and (list? value) (= (length value) 2) (eq? (car value) 'load-step)
              (list (cadr form) (cadr value))))))

;; occurs? : Symbol Any -> Boolean
(define (occurs? name x)
  (cond ((eq? x name) #t)
        ((pair? x) (or (occurs? name (car x)) (occurs? name (cdr x))))
        (else #f)))

;; has-subform? : Any Any -> Boolean
;; Whether FORM is X, or an element of X, or of an element of it: never a
;; tail.
(define (has-subform? form x)
  (or (equal? x form)
      (and (pair? x)
           (let loop ((rest x))
             (and (pair? rest)
                  (or (has-subform? form (car rest)) (loop (cdr rest))))))))

;; foreign-forms : Any -> (Listof Any)
;; Every list headed by foreign-procedure anywhere in X, in reading order. It
;; looks at the elements of each list, never at a tail: the tail of
;; (syntax foreign-procedure), the binder's #'foreign-procedure, is
;; (foreign-procedure), and is no form.
(define (foreign-forms x)
  (cond ((and (pair? x) (eq? (car x) 'foreign-procedure)) (list x))
        ((pair? x)
         (let loop ((rest x) (found '()))
           (if (pair? rest)
               (loop (cdr rest) (append found (foreign-forms (car rest))))
               found)))
        (else '())))

;; c-name : (Listof Any) -> Any
;; The first string in a foreign-procedure form: its entry point.
(define (c-name form)
  (let ((s (find string? (cdr form)))) (or s (list 'no-name form))))

;; placed-binding : Any -> (U (List Symbol Any String) #f)
;; (NAME LIBRARY ENTRY) for a top-level
;; (define NAME (load-step (bind-required LIBRARY (foreign-procedure ...)))),
;; and (NAME optional ENTRY) for a top-level
;; (define NAME (load-step (bind-optional (foreign-procedure ...)))).
(define (placed-binding form)
  (let ((step (load-step-of form)))
    (and step
         (let ((expr (cadr step)))
           (cond ((and (list? expr) (= (length expr) 3) (eq? (car expr) 'bind-required))
                  (let ((fp (caddr expr)))
                    (and (pair? fp) (eq? (car fp) 'foreign-procedure)
                         (list (car step) (cadr expr) (c-name fp)))))
                 ((and (list? expr) (= (length expr) 2) (eq? (car expr) 'bind-optional))
                  (let ((fp (cadr expr)))
                    (and (pair? fp) (eq? (car fp) 'foreign-procedure)
                         (list (car step) 'optional (c-name fp)))))
                 (else #f))))))

;; step-names : (Listof Symbol)
;; The load's own names a step's expression may use: its bindings of the
;; report's three, of threadsafe and of initialize, the threadsafe answer, the
;; report, and the report's version and number accessors.
(define step-names
  '(raw-libversion-number raw-libversion raw-sourceid raw-threadsafe raw-initialize threadsafe report
    libsqlite3-info-version libsqlite3-info-version-number))

;; The load's steps, in order: each top-level load-step definition's name, the
;; head of what it runs, and which of step-names that uses, so a step whose
;; body was swapped for another's, or that stopped calling its binding or
;; checking its answer, changes the list too.
(test-equal "native's load steps, in order: choose, load, the report's three bindings and the report, the floor, threadsafe's binding, answer and check, sqlite3_initialize's binding and call, then the rest of M1's required list, M2's 21, M3's five and M4's two, in ADR-0002's order, then the optional sqlite3_load_extension; each with the head of what it runs and the load's names it uses"
  '((chosen call-with-values)
    (libsqlite3-loaded guard)
    (raw-libversion-number bind-required)
    (raw-libversion bind-required)
    (raw-sourceid bind-required)
    (report let* raw-libversion-number raw-libversion raw-sourceid)
    (version-checked check-version report libsqlite3-info-version libsqlite3-info-version-number)
    (raw-threadsafe bind-required report)
    (threadsafe raw-threadsafe raw-threadsafe)
    (threadsafe-checked check-threadsafe threadsafe report)
    (raw-initialize bind-required report)
    (initialized let raw-initialize report)
    (sqlite3-compileoption-used bind-required report)
    (sqlite3-compileoption-get bind-required report)
    (sqlite3-open-v2 bind-required report)
    (sqlite3-close bind-required report)
    (sqlite3-errmsg bind-required report)
    (sqlite3-errstr bind-required report)
    (sqlite3-errcode bind-required report)
    (sqlite3-extended-errcode bind-required report)
    (sqlite3-next-stmt bind-required report)
    (sqlite3-memory-used bind-required report)
    (sqlite3-prepare-v3 bind-required report)
    (sqlite3-finalize bind-required report)
    (sqlite3-step bind-required report)
    (sqlite3-reset bind-required report)
    (sqlite3-clear-bindings bind-required report)
    (sqlite3-bind-parameter-count bind-required report)
    (sqlite3-bind-parameter-index bind-required report)
    (sqlite3-bind-null bind-required report)
    (sqlite3-bind-int64 bind-required report)
    (sqlite3-bind-double bind-required report)
    (sqlite3-bind-text64 bind-required report)
    (sqlite3-bind-blob64 bind-required report)
    (sqlite3-column-count bind-required report)
    (sqlite3-column-name bind-required report)
    (sqlite3-column-type bind-required report)
    (sqlite3-column-int64 bind-required report)
    (sqlite3-column-double bind-required report)
    (sqlite3-column-text bind-required report)
    (sqlite3-column-blob bind-required report)
    (sqlite3-column-bytes bind-required report)
    (sqlite3-error-offset bind-required report)
    (sqlite3-changes64 bind-required report)
    (sqlite3-total-changes64 bind-required report)
    (sqlite3-last-insert-rowid bind-required report)
    (sqlite3-get-autocommit bind-required report)
    (sqlite3-interrupt bind-required report)
    (sqlite3-db-config bind-required report)
    (sqlite3-free bind-required report)
    (sqlite3-load-extension bind-optional))
  (if body-read?
      (let loop ((forms native-body) (found '()))
        (if (null? forms)
            (reverse found)
            (let ((step (load-step-of (car forms))))
              (loop (cdr forms)
                    (if step
                        (let ((expr (cadr step)))
                          (cons (cons* (car step)
                                       (if (pair? expr) (car expr) expr)
                                       (filter (lambda (name) (occurs? name expr)) step-names))
                                found))
                        found)))))
      native-body))

;; step-named : Any -> Any
;; The name of the load step whose expression is EXPR, or no-step.
(define (step-named expr)
  (let loop ((forms native-body))
    (cond ((null? forms) 'no-step)
          ((let ((step (load-step-of (car forms)))) (and step (equal? (cadr step) expr)))
           (cadr (car forms)))
          (else (loop (cdr forms))))))

;; reader-body : Symbol -> Any
;; The body of native's (define (NAME) BODY), or no-reader.
(define (reader-body name)
  (let loop ((forms native-body))
    (cond ((null? forms) 'no-reader)
          ((let ((form (car forms)))
             (and (list? form) (= (length form) 3) (eq? (car form) 'define)
                  (pair? (cadr form)) (null? (cdr (cadr form))) (eq? (car (cadr form)) name)))
           (caddr (car forms)))
          (else (loop (cdr forms))))))

;; Native's record of the optional entry point is read from bind-optional's
;; answer alone, so the record and the binding cannot disagree: a second
;; foreign-entry? could, in a process that loaded another library since.
(test-equal "load-extension-available? is defined right after sqlite3-load-extension's step, as whether that step's answer, the binding or #f, is a procedure, and from nothing else"
  '((sqlite3-load-extension load-extension-available?)
    (if (procedure? sqlite3-load-extension) #t #f))
  (if body-read?
      (let loop ((forms native-body))
        (cond ((or (null? forms) (null? (cdr forms))) (list 'no-such-definitions))
              ((and (load-step-of (car forms)) (eq? (car (load-step-of (car forms))) 'sqlite3-load-extension))
               (let ((next (cadr forms)))
                 (list (list 'sqlite3-load-extension
                             (and (list? next) (= (length next) 3) (eq? (car next) 'define) (cadr next)))
                       (and (list? next) (= (length next) 3) (caddr next)))))
              (else (loop (cdr forms)))))
      native-body))

(test-equal "loaded-threadsafe answers the variable of the threadsafe step, the one check-threadsafe was given, and no constant"
  '(threadsafe threadsafe)
  (if body-read?
      (list (step-named '(raw-threadsafe)) (reader-body 'loaded-threadsafe))
      native-body))

(test-equal "native's first definition is step 0, earlier-failure, which raises a recorded load-failure again"
  '(earlier-failure calls-load-failure)
  (if body-read?
      (let ((first (find (lambda (form) (and (pair? form) (eq? (car form) 'define))) native-body)))
        (list (and first (cadr first))
              (if (and first (occurs? 'load-failure first) (occurs? 'raise first))
                  'calls-load-failure
                  first)))
      native-body))

(test-equal "every foreign-procedure form in native.sls binds eagerly: each is a top-level (define NAME (load-step (bind-required LIBRARY (foreign-procedure ...)))), with no report for the report's own three and the report for the rest, or, for the optional sqlite3_load_extension, (define NAME (load-step (bind-optional (foreign-procedure ...)))), and there are no others"
  (list '((raw-libversion-number #f "sqlite3_libversion_number")
          (raw-libversion #f "sqlite3_libversion")
          (raw-sourceid #f "sqlite3_sourceid")
          (raw-threadsafe report "sqlite3_threadsafe")
          (raw-initialize report "sqlite3_initialize")
          (sqlite3-compileoption-used report "sqlite3_compileoption_used")
          (sqlite3-compileoption-get report "sqlite3_compileoption_get")
          (sqlite3-open-v2 report "sqlite3_open_v2")
          (sqlite3-close report "sqlite3_close")
          (sqlite3-errmsg report "sqlite3_errmsg")
          (sqlite3-errstr report "sqlite3_errstr")
          (sqlite3-errcode report "sqlite3_errcode")
          (sqlite3-extended-errcode report "sqlite3_extended_errcode")
          (sqlite3-next-stmt report "sqlite3_next_stmt")
          (sqlite3-memory-used report "sqlite3_memory_used")
          (sqlite3-prepare-v3 report "sqlite3_prepare_v3")
          (sqlite3-finalize report "sqlite3_finalize")
          (sqlite3-step report "sqlite3_step")
          (sqlite3-reset report "sqlite3_reset")
          (sqlite3-clear-bindings report "sqlite3_clear_bindings")
          (sqlite3-bind-parameter-count report "sqlite3_bind_parameter_count")
          (sqlite3-bind-parameter-index report "sqlite3_bind_parameter_index")
          (sqlite3-bind-null report "sqlite3_bind_null")
          (sqlite3-bind-int64 report "sqlite3_bind_int64")
          (sqlite3-bind-double report "sqlite3_bind_double")
          (sqlite3-bind-text64 report "sqlite3_bind_text64")
          (sqlite3-bind-blob64 report "sqlite3_bind_blob64")
          (sqlite3-column-count report "sqlite3_column_count")
          (sqlite3-column-name report "sqlite3_column_name")
          (sqlite3-column-type report "sqlite3_column_type")
          (sqlite3-column-int64 report "sqlite3_column_int64")
          (sqlite3-column-double report "sqlite3_column_double")
          (sqlite3-column-text report "sqlite3_column_text")
          (sqlite3-column-blob report "sqlite3_column_blob")
          (sqlite3-column-bytes report "sqlite3_column_bytes")
          (sqlite3-error-offset report "sqlite3_error_offset")
          (sqlite3-changes64 report "sqlite3_changes64")
          (sqlite3-total-changes64 report "sqlite3_total_changes64")
          (sqlite3-last-insert-rowid report "sqlite3_last_insert_rowid")
          (sqlite3-get-autocommit report "sqlite3_get_autocommit")
          (sqlite3-interrupt report "sqlite3_interrupt")
          (sqlite3-db-config report "sqlite3_db_config")
          (sqlite3-free report "sqlite3_free")
          (sqlite3-load-extension optional "sqlite3_load_extension"))
        44)
  (if body-read?
      (list (let loop ((forms native-body) (found '()))
              (if (null? forms)
                  (reverse found)
                  (let ((placed (placed-binding (car forms))))
                    (loop (cdr forms) (if placed (cons placed found) found)))))
            (length (foreign-forms native-body)))
      native-body))

;; definition-of : Symbol -> Any
;; The expression of native's top-level (define NAME EXPR), or no-definition.
(define (definition-of name)
  (let loop ((forms native-body))
    (cond ((null? forms) 'no-definition)
          ((let ((form (car forms)))
             (and (list? form) (= (length form) 3) (eq? (car form) 'define) (eq? (cadr form) name)))
           (caddr (car forms)))
          (else (loop (cdr forms))))))

;; numbers-in : Any -> (Listof Number)
(define (numbers-in x)
  (cond ((number? x) (list x))
        ((pair? x) (append (numbers-in (car x)) (numbers-in (cdr x))))
        (else '())))

;; On a 64-bit machine the header's value is 2^64-1, so a literal of it
;; passes the oracle row there and fails on any other width: only the form
;; can show it. sqlite-transient's expression must ask for the pointer's
;; size, and write no number as big as a byte's values.
(test-equal "sqlite-transient is computed from (foreign-sizeof 'uptr), and writes no number above 255: never a literal for one pointer width"
  '(asks-the-size ())
  (if body-read?
      (let ((expr (definition-of 'sqlite-transient)))
        (list (if (has-subform? '(foreign-sizeof 'uptr) expr) 'asks-the-size (list 'no-size expr))
              (filter (lambda (n) (not (and (integer? n) (exact? n) (<= 0 n 255)))) (numbers-in expr))))
      native-body))

;; --- __collect_safe, by behaviour: sqlite3_open_v2 blocked on a FIFO (ADR-0011) ----------------
;; A FIFO opened read-only blocks its opener until a writer opens it, and
;; SQLite opens the database file in sqlite3_open_v2. One thread opens it, and
;; another, once the opener has called, waits a second and asks for a
;; collection (collect-rendezvous), which waits for every active thread. A
;; thread in a plain foreign call stays active, so the collection, and every
;; thread with it, waits until the call returns; a __collect_safe call
;; deactivates its thread, and the collection finishes while it blocks. Once
;; it has, the collector opens the FIFO for writing, which releases the
;; opener. A watchdog shell does the same after 30 s, leaving a marker first:
;; with a plain binding no thread of this process can run until the call
;; returns, so only a process outside it can end the wait. The verdict is who
;; released the opener. SQLite then reads the file's header, which a FIFO
;; cannot give (pread answers ESPIPE): SQLITE_IOERR, and the handle is closed.
;; Measured in M1 slice 2's copy table (P3): plain, the process deadlocked.

;; wait-until : (-> Any) Natural -> (U 'satisfied 'iterations-exhausted)
;; DONE? asked every 10 ms, at most STEPS times.
(define (wait-until done? steps)
  (run-until (lambda () (sleep (make-time 'time-duration 10000000 0))) done? steps))

;; blocking-open : String -> (List Any Any)
;; What the opener and the collector each answered, or that it hung.
(define (blocking-open fifo)
  (let ((m (make-mutex))
        (opener-calling #f)
        (opener-answer #f)
        (collector-answer #f))
    (fork-thread
     (lambda ()
       (let ((a (guard (e (#t (list 'raised (describe e))))
                  (let-values (((rc db)
                                (call-with-c-string 'test-native fifo
                                  (lambda (name)
                                    (call-with-out-pointer 'test-native
                                      (lambda (slot)
                                        (with-mutex m (set! opener-calling #t))
                                        (sqlite3-open-v2 name slot sqlite-open-readonly 0)))))))
                    (list rc (if (eqv? db 0) 'no-handle (sqlite3-close db)))))))
         (with-mutex m (set! opener-answer (list 'answer a))))))
    (fork-thread
     (lambda ()
       (let ((a (guard (e (#t (list 'raised (describe e))))
                  (if (eq? (wait-until (lambda () (with-mutex m opener-calling)) 3000) 'satisfied)
                      (begin
                        (sleep (make-time 'time-duration 0 1))
                        (collect-rendezvous)
                        (let ((released (capture-command
                                         (list "sh" "-c" "exec 3<>\"$1\"" "sh" fifo))))
                          (if (equal? released '(0 "" "")) 'collected (list 'release released))))
                      'the-opener-never-called))))
         (with-mutex m (set! collector-answer (list 'answer a))))))
    (let* ((opener (wait-until (lambda () (with-mutex m opener-answer)) 12000))
           (collector (wait-until (lambda () (with-mutex m collector-answer)) 12000)))
      (list (if (eq? opener 'satisfied) (cadr (with-mutex m opener-answer)) 'the-opener-hung)
            (if (eq? collector 'satisfied) (cadr (with-mutex m collector-answer)) 'the-collector-hung)))))

;; fifo-refused : Any -> Any
;; RESULT with its open's answer written refused-open when it is SQLITE_IOERR
;; or SQLITE_CANTOPEN, and left as it is otherwise. The open's answer is not
;; what the row is about: Guix's 3.53.1 and Homebrew's 3.54.1 answer IOERR,
;; reading the header from a FIFO, and Apple's 3.51.0 answers CANTOPEN
;; (measured on the maintainer's Mac). Any other answer fails the row.
(define (fifo-refused result)
  (if (and (pair? result) (pair? (car result)) (pair? (caar result))
           (memv (car (caar result)) (list ioerr cantopen)))
      (cons (cons (cons 'refused-open (cdr (caar result))) (cdar result)) (cdr result))
      result))

(test-equal "sqlite3_open_v2 is __collect_safe: blocked on a FIFO, it lets another thread's collection finish, and that thread releases it; it answers SQLITE_IOERR, or SQLITE_CANTOPEN on Apple's 3.51.0, and the handle closes with SQLITE_OK; every count is zero after"
  (list (list (list 'refused-open ok) 'collected) 'released-by-the-collector zero-counts)
  (fifo-refused
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let* ((fifo (string-append dir "/blocking.fifo"))
              (marker (string-append dir "/watchdog-fired"))
              (made (capture-command (list "mkfifo" fifo))))
         (if (not (equal? made '(0 "" "")))
             (list 'mkfifo made)
             (let* ((watchdog (capture-command
                               (list "sh" "-c"
                                     "(sleep 30; : >\"$2\"; exec 3<>\"$1\") </dev/null >/dev/null 2>&1 & echo $!"
                                     "sh" fifo marker)))
                    (pid (let ((out (cadr watchdog)))
                           (and (= (car watchdog) 0) (> (string-length out) 1)
                                (substring out 0 (- (string-length out) 1)))))
                    (answers (if pid (blocking-open fifo) (list 'no-watchdog watchdog)))
                    (released-by (if (file-exists? marker)
                                     'released-by-the-watchdog
                                     'released-by-the-collector)))
               (when pid (capture-command (list "kill" pid)))
               (list answers released-by (native-counts))))))))))

;; --- __collect_safe, by behaviour: sqlite3_load_extension blocked on a FIFO (ADR-0011, amended) -----
;; The open's method above, for M4's load (research L6 and X1). The
;; connection has the C call on: ENABLE_LOAD_EXTENSION set to 1 through
;; native's sqlite3_db_config, or the load would answer "not authorized"
;; without opening anything. dlopen opens the FIFO read-only and waits for a
;; writer. The collector, once the loader has called, waits a second, asks
;; for a collection, notes that it finished, then releases the loader
;; through release-until: the FIFO opened for writing, and again each second
;; until the loader answers. Linux's dlopen opens the FIFO once; macOS's
;; dyld opens it twice, each open waiting for a writer (the M4 session's Mac
;; run 2, PR #38), so a single release left the Mac's load to the watchdog.
;; .plans/research/m4-slice-2/fifo-double-open.sps shows a single release
;; leaving an opener that opens twice waiting, on Linux too, and
;; release-until freeing it. A plain binding holds the collection, and the
;; collector with it, until the load returns, so only the watchdog shell can
;; release it: after 30 s, its marker left first, it opens the FIFO for
;; writing ten times, a second apart. The verdict is who released the
;; loader. The loader notes, as its call returns, whether the collection had
;; finished: a load that never waited, as one that did not open the FIFO
;; would, returns before it, and fails the row too.
;;
;; While dlopen waits, glibc's dynamic loader holds its lock, and a thread
;; made then waits for it: pthread_create, which fork-thread calls, returned
;; only when a blocked load did, 3.5 s after it was called (measured in M4
;; slice 2, glibc 2.41). So the collector is forked first, and the loader,
;; the last thread the row makes, after it. capture-command's shell, started
;; by the collector, does not wait for the lock. Released, dlopen reads no
;; header from the FIFO, and SQLite tries the path with .so appended, which
;; isn't there: the load answers SQLITE_ERROR and a message, freed with
;; sqlite3_free.

;; release-rounds : Natural
;; How many releases release-until makes at most, a second apart.
(define release-rounds 10)

;; release-until : String (-> Any) -> (U (List 'released Natural) (List 'unanswered Natural) (List 'release Any))
;; FIFO opened for writing by a shell, then up to a second's wait for
;; ANSWERED?, and again until it answers, release-rounds times at most: the
;; releases it took, or that it never answered, or a release's own failure.
(define (release-until fifo answered?)
  (let loop ((n 1))
    (let ((released (capture-command (list "sh" "-c" "exec 3<>\"$1\"" "sh" fifo))))
      (cond ((not (equal? released '(0 "" ""))) (list 'release released))
            ((eq? (wait-until answered? 100) 'satisfied) (list 'released n))
            ((< n release-rounds) (loop (+ n 1)))
            (else (list 'unanswered n))))))

;; blocking-load : Natural String -> (List Any Any)
;; What the loader and the collector each answered, or that it hung.
(define (blocking-load db fifo)
  (let ((m (make-mutex))
        (loader-calling #f)
        (collected #f)
        (loader-answer #f)
        (collector-answer #f))
    (fork-thread
     (lambda ()
       (let ((a (guard (e (#t (list 'raised (describe e))))
                  (if (eq? (wait-until (lambda () (with-mutex m loader-calling)) 3000) 'satisfied)
                      (begin
                        (sleep (make-time 'time-duration 0 1))
                        (collect-rendezvous)
                        (with-mutex m (set! collected #t))
                        (let ((released (release-until fifo (lambda () (with-mutex m loader-answer)))))
                          (if (eq? (car released) 'released) 'collected released)))
                      'the-loader-never-called))))
         (with-mutex m (set! collector-answer (list 'answer a))))))
    (fork-thread
     (lambda ()
       (let ((a (guard (e (#t (list 'raised (describe e))))
                  (call-with-c-string 'test-native fifo
                    (lambda (file)
                      (let-values (((code message)
                                    (call-with-out-pointer 'test-native
                                      (lambda (slot)
                                        (with-mutex m (set! loader-calling #t))
                                        (sqlite3-load-extension db file 0 slot)))))
                        (let* ((order (if (with-mutex m collected)
                                          'returned-after-the-collection
                                          'returned-before-the-collection))
                               (text (guard (e (#t (list 'raised (describe e))))
                                       (and (not (eqv? message 0)) (c-string->string message)))))
                          (unless (eqv? message 0) (sqlite3-free message))
                          (list code (if (string? text) 'message (list 'no-message text)) order))))))))
         (with-mutex m (set! loader-answer (list 'answer a))))))
    ;; A loader still waiting once the bound has passed is released here,
    ;; through release-until, and waited for again, bounded: the
    ;; connection's close, which follows, would wait for the load, which
    ;; holds the connection's mutex, to TEST_TIMEOUT. So the row fails by
    ;; name, the-loader-hung, and the suite goes on.
    (let* ((loader (wait-until (lambda () (with-mutex m loader-answer)) loader-steps))
           (released (if (eq? loader 'satisfied)
                         'not-needed
                         (release-until fifo (lambda () (with-mutex m loader-answer)))))
           (returned (if (eq? loader 'satisfied)
                         'satisfied
                         (wait-until (lambda () (with-mutex m loader-answer)) 3000)))
           (collector (wait-until (lambda () (with-mutex m collector-answer)) 12000)))
      (list (if (eq? loader 'satisfied)
                (cadr (with-mutex m loader-answer))
                (list 'the-loader-hung 'released released 'then returned))
            (if (eq? collector 'satisfied) (cadr (with-mutex m collector-answer)) 'the-collector-hung)))))

;; loader-steps : Natural
;; How many 10 ms waits the FIFO row gives the loader: 120 s, past the
;; watchdog's 30 s.
(define loader-steps 12000)

(load-row "sqlite3_load_extension is __collect_safe: on a connection whose ENABLE_LOAD_EXTENSION the binding set to 1, blocked on a FIFO, it lets another thread's collection finish, returning after it, and that thread releases it; it answers SQLITE_ERROR and a message, freed by sqlite3_free; the handle closes with SQLITE_OK; every count is zero after"
  (list (list (list (list ok 1) (list (list error-code 'message 'returned-after-the-collection) 'collected))
              ok zero-counts)
        'released-by-the-collector)
  (lambda ()
    (call-with-temp-directory
     (lambda (dir)
       (let* ((fifo (string-append dir "/blocking.fifo"))
              (marker (string-append dir "/watchdog-fired"))
              (made (capture-command (list "mkfifo" fifo))))
         (if (not (equal? made '(0 "" "")))
             (list 'mkfifo made)
             (let* ((watchdog (capture-command
                               (list "sh" "-c"
                                     "(sleep 30; : >\"$2\"; i=0; while [ $i -lt 10 ]; do exec 3<>\"$1\"; exec 3<&-; sleep 1; i=$((i+1)); done) </dev/null >/dev/null 2>&1 & echo $!"
                                     "sh" fifo marker)))
                    (pid (let ((out (cadr watchdog)))
                           (and (= (car watchdog) 0) (> (string-length out) 1)
                                (substring out 0 (- (string-length out) 1)))))
                    (answers (if pid
                                 (with-memory
                                  (lambda (db)
                                    (let* ((on (config-call db enable-load-extension-op 1 7701))
                                           (blocked (blocking-load db fifo)))
                                      (list on blocked))))
                                 (list 'no-watchdog watchdog)))
                    (released-by (if (file-exists? marker)
                                     'released-by-the-watchdog
                                     'released-by-the-collector)))
               (when pid (capture-command (list "kill" pid)))
               (list answers released-by))))))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "native")

(exit (suite-exit-status runner))
