#!r6rs
;;; (chez-sqlite3 private native): loads libsqlite3, once, and binds it
;;; (ADR-0001, ADR-0002, ADR-0010, ADR-0011). The only library that calls
;;; into libsqlite3.
;;;
;;; Its body is the load, written as definitions in the order they must run.
;;; A library body evaluates its definitions in order, so the order below is
;;; the order at run time. Nothing binds lazily:
;;;
;;;   0. once        a failure recorded by an earlier run of this body is
;;;                  raised again, before anything else runs
;;;   1. choose      (chez-sqlite3 private discovery) picks the path and its
;;;                  source, from getenv, the machine type, /proc/self/maps'
;;;                  text and file-exists?
;;;   2. load        load-shared-object, once. A raise is load-failed, and no
;;;                  other candidate is ever tried: a library once loaded
;;;                  cannot be unloaded, and Chez binds each name to the most
;;;                  recently loaded object (ADR-0002)
;;;   3. the report  sqlite3_libversion_number, sqlite3_libversion and
;;;                  sqlite3_sourceid, bound and called; the report built from
;;;                  their answers, the path and the source. Every refusal
;;;                  from here on carries it
;;;   4. the floor   check-version
;;;   5. threadsafe  sqlite3_threadsafe, bound and called once, then
;;;                  check-threadsafe (ADR-0010, decision 4)
;;;   6. initialize  sqlite3_initialize, bound and called once: SQLite
;;;                  initialises itself at its first open unless it was built
;;;                  with SQLITE_OMIT_AUTOINIT, where the application must. An
;;;                  answer but SQLITE_OK is load-failed
;;;   7. the rest    every other entry point M1 requires, then M2's 21, in
;;;                  ADR-0002's amended order, eagerly: sqlite3_prepare_v3,
;;;                  sqlite3_finalize, sqlite3_step, sqlite3_reset,
;;;                  sqlite3_clear_bindings, sqlite3_bind_parameter_count,
;;;                  sqlite3_bind_parameter_index, sqlite3_bind_null,
;;;                  sqlite3_bind_int64, sqlite3_bind_double,
;;;                  sqlite3_bind_text64, sqlite3_bind_blob64,
;;;                  sqlite3_column_count, sqlite3_column_name,
;;;                  sqlite3_column_type, sqlite3_column_int64,
;;;                  sqlite3_column_double, sqlite3_column_text,
;;;                  sqlite3_column_blob, sqlite3_column_bytes and
;;;                  sqlite3_error_offset (ADR-0002, M2's amendment)
;;;   8. the check   sqlite3_memory_used read once, the baseline, and the
;;;                  check against it registered with the counters, for
;;;                  suite-exit-status (chez-sqlite3 private memory-check)
;;;
;;; The load runs once per process, whatever it decides. Chez runs a library
;;; body that raised again at every later reference, so each step from 1 on
;;; runs inside load-step, from (chez-sqlite3 private load-state), which
;;; records the first failure and raises it, made serious. Step 0 raises that
;;; recorded failure at every later reference: nothing is loaded twice, and a
;;; CHEZ_SQLITE3_LIBRARY changed in between is never read (ADR-0002).
;;;
;;; foreign-procedure resolves its entry point when it is evaluated, so a
;;; binding must follow the load, and an entry point the library lacks fails
;;; with Chez's bare "no entry for". So every entry point is asked of
;;; foreign-entry? first, and an absent one is missing-api, naming it:
;;; carrying no report for the report's own three, which come before it, and
;;; the report for every other.
;;;
;;; Every binding is a literal foreign-procedure form, the whole second
;;; argument of bind-required, the whole argument of load-step, the whole value
;;; of a top-level definition:
;;;
;;;   (define NAME
;;;     (load-step
;;;      (bind-required LIBRARY
;;;        (foreign-procedure [__collect_safe] "C_NAME" (ARG-TYPE ...) RESULT-TYPE))))
;;;
;;; so the convention suite reads each binding at its use, as data, and the
;;; entry point bind-required checks is the one the form binds: the binder
;;; takes the name from the form. No binding takes a Scheme object: every
;;; argument is an integer, a flonum, or the address of a counted block, and
;;; every pointer is a uptr, never Chez's string, utf-8, u8* or scheme-object
;;; types, nor a bytevector (ADR-0011, decision 1). The calls that can block are
;;; __collect_safe, so another thread's collection need not wait for them
;;; (ADR-0011, decision 5, amended): sqlite3_open_v2, which creates the file,
;;; and sqlite3_close, which can write; sqlite3_prepare_v3, which reads the
;;; schema and waits in the busy handler under another connection's lock;
;;; sqlite3_step, which does the statement's I/O and waits there too; and
;;; sqlite3_reset and sqlite3_finalize, measured waiting 1502 ms in the busy
;;; handler under another connection's read. Every other binding is plain.
;;; sqlite-transient is SQLITE_TRANSIENT, the destructor that makes SQLite
;;; copy a bound value: a pointer whose bits are all ones, computed from the
;;; pointer's size (ADR-0001).
;;;
;;; Strings cross in counted blocks (ADR-0011, decisions 2 to 4).
;;; call-with-c-string hands C a UTF-8, NUL-terminated copy, written with
;;; foreign-set!; c-string->string reads one back with foreign-ref, up to its
;;; NUL, and decodes it; call-with-out-pointer hands C a zeroed slot of a
;;; pointer's size and reads it after. Each block is freed when PROC returns,
;;; raises or escapes, and a PROC re-entered after that raises. Each takes the
;;; WHO of the public procedure it serves, so its refusals name that one
;;; (ADR-0013, decision 2), and names a refused value by shown-value, never a
;;; string's text (ADR-0013, decision 7). None raises inside the critical
;;; thunks that make and free its block: a raise there would reach a
;;; with-exception-handler handler with interrupts still disabled (M1's
;;; closing review). An engine's expiry unwinds the extent and frees the
;;; block, and its resume is a re-entry, so a caller under engines holds the
;;; whole extent in one critical section, and raises what it caught there
;;; after it: (chez-sqlite3 private connection)'s open, and report's
;;; sqlite-compile-option?.
;;;
;;; Every refusal is a &sqlite-library-unavailable, raised through
;;; raise-library-unavailable, carrying the path and its source. The reasons
;;; raised here, beside those of discovery and verify:
;;;
;;;   load-failed  the loader refused the path (detail: its message);
;;;                sqlite3_libversion or sqlite3_sourceid answered NULL
;;;                (detail: that entry point's C name); sqlite3_initialize
;;;                answered other than SQLITE_OK (detail: its code)
;;;   missing-api  a required entry point is absent (detail: its C name)
;;;
;;; The handle, its thread and its count are (chez-sqlite3)'s, from M1 slice 4:
;;; the raw bindings here take any integer, and are private (ADR-0009).
(library (chez-sqlite3 private native)
  (export loaded-libsqlite3 loaded-threadsafe
          sqlite3-open-v2 sqlite3-close sqlite3-errmsg sqlite3-errstr sqlite3-errcode
          sqlite3-extended-errcode sqlite3-next-stmt sqlite3-memory-used
          sqlite3-compileoption-used sqlite3-compileoption-get
          sqlite3-prepare-v3 sqlite3-finalize sqlite3-step sqlite3-reset
          sqlite3-clear-bindings sqlite3-bind-parameter-count sqlite3-bind-parameter-index
          sqlite3-bind-null sqlite3-bind-int64 sqlite3-bind-double sqlite3-bind-text64
          sqlite3-bind-blob64 sqlite3-column-count sqlite3-column-name sqlite3-column-type
          sqlite3-column-int64 sqlite3-column-double sqlite3-column-text sqlite3-column-blob
          sqlite3-column-bytes sqlite3-error-offset sqlite-transient
          call-with-c-string c-string->string call-with-out-pointer)
  (import (chez-sqlite3 private require-threaded)
          (except (rnrs) dynamic-wind)
          (only (chezscheme) display-condition dynamic-wind foreign-entry? foreign-procedure
                foreign-ref foreign-set! foreign-sizeof format format-condition? getenv
                load-shared-object machine-type)
          (chez-sqlite3 private load-state)
          (chez-sqlite3 private libsqlite3-info)
          (chez-sqlite3 private conditions)
          (chez-sqlite3 private memory)
          (chez-sqlite3 private discovery)
          (chez-sqlite3 private verify)
          (only (chez-sqlite3 private counters) register-exit-check!)
          (chez-sqlite3 private memory-check))

  ;; --- 0. once -------------------------------------------------------------------

  ;; The first definition: an earlier run of this body failed, and that
  ;; failure is raised again. The steps below never run twice.
  (define earlier-failure
    (let ((failure (load-failure)))
      (when failure (raise failure))
      #f))

  ;; --- helpers -------------------------------------------------------------------

  ;; linux-machine? : Symbol -> Boolean
  ;; Chez's Linux machine types end in le: ta6le, tarm64le.
  (define (linux-machine? type)
    (let* ((name (symbol->string type)) (n (string-length name)))
      (and (>= n 2) (string=? (substring name (- n 2) n) "le"))))

  ;; maps-text : -> (U String #f)
  ;; /proc/self/maps, read whole, on Linux; #f on any failure, and on any
  ;; other platform. Discovery reads the world from it.
  (define (maps-text)
    (and (linux-machine? (machine-type))
         (guard (e (#t #f))
           (let ((text (call-with-port
                        (open-file-input-port "/proc/self/maps" (file-options)
                                              (buffer-mode block)
                                              (make-transcoder (utf-8-codec)))
                        get-string-all)))
             (and (string? text) text)))))

  ;; loader-message : Condition -> String
  ;; What the loader said, as Chez would print it after "Exception: ".
  (define (loader-message e)
    (if (and (format-condition? e) (message-condition? e) (irritants-condition? e))
        (apply format (condition-message e) (condition-irritants e))
        (call-with-string-output-port (lambda (p) (display-condition e p)))))

  ;; required-entry : String String Symbol (U Libsqlite3-Info #f) -> Void
  ;; Raises missing-api, naming NAME and carrying PATH, SOURCE and LIBRARY,
  ;; unless the loaded library has NAME.
  (define (required-entry name path source library)
    (unless (foreign-entry? name)
      (raise-library-unavailable
       'missing-api path source name '() library
       (string-append "the library has no " name
                      ", so it is not a libsqlite3 chez-sqlite3 can use; name another with CHEZ_SQLITE3_LIBRARY")
       (list path))))

  ;; (bind-required LIBRARY (foreign-procedure CONVENTION ... ENTRY (ARG-TYPE ...) RESULT-TYPE))
  ;; The foreign-procedure form's value, once required-entry has found ENTRY
  ;; in the loaded library, carrying LIBRARY, the report or #f, if not. The
  ;; form is the binding, literal at its use, and the name checked is the one
  ;; it binds. Anything else in its place is a syntax violation. Internal:
  ;; check-seam rule (k) lets native export no macro.
  (define-syntax bind-required
    (lambda (x)
      (syntax-case x ()
        ((_ library (fp convention ... entry (arg ...) result))
         (and (identifier? #'fp)
              (free-identifier=? #'fp #'foreign-procedure)
              (string? (syntax->datum #'entry)))
         #'(begin
             (required-entry entry libsqlite3-path libsqlite3-source library)
             (fp convention ... entry (arg ...) result))))))

  ;; sqlite-transient : Natural
  ;; SQLITE_TRANSIENT, ((sqlite3_destructor_type)-1): a pointer whose bits are
  ;; all ones, as a uptr reads it. Given as the destructor of a bound TEXT or
  ;; BLOB, it makes SQLite copy the value before the bind returns, so the
  ;; block can be freed after (ADR-0001, ADR-0015 decision 5). Computed from
  ;; the pointer's size, never written for one width.
  (define sqlite-transient
    (- (bitwise-arithmetic-shift-left 1 (* 8 (foreign-sizeof 'uptr))) 1))

  ;; exact-natural? : Any -> Boolean
  (define (exact-natural? x)
    (and (integer? x) (exact? x) (>= x 0)))

  ;; check-who : Symbol Any -> Void
  ;; HELPER's refusal of a WHO that is no symbol.
  (define (check-who helper who)
    (unless (symbol? who)
      (assertion-violation helper "a who is a symbol" (shown-value who))))

  ;; holds-nul? : String -> Boolean
  (define (holds-nul? s)
    (let loop ((i 0))
      (and (< i (string-length s))
           (or (char=? (string-ref s i) #\nul) (loop (+ i 1))))))

  ;; call-with-block : Symbol Positive-Integer (Positive-Integer -> Any)
  ;;                   (Positive-Integer -> A) -> A
  ;; PROC's answer, PROC given the address of a counted block of SIZE bytes
  ;; that FILL! has written. The block is freed once PROC returns, raises or
  ;; escapes, and re-entering PROC through a continuation after that raises an
  ;; assertion violation from WHO, so the address is never used after. The
  ;; block's extent is a critical dynamic-wind: its before thunk, with the
  ;; block's making, and its after thunk, with the block's freeing, each run in
  ;; one critical section with the record that the extent was entered or left,
  ;; so no escaping interrupt leaves a block made and unrecorded.
  ;;
  ;; Neither critical thunk raises. Each records what it caught, and the
  ;; raise follows, from a plain thunk of a dynamic-wind around the block's:
  ;;   - a re-entry: from its before thunk, before the block's extent is
  ;;     entered again, so no second block is made. A resume between the free
  ;;     and the end of the outer extent would be refused too, though PROC
  ;;     had returned; with a PROC that did nothing, an engine of 1 to 300
  ;;     ticks a slice was never refused once PROC had returned (measured,
  ;;     Chez 10.4.0);
  ;;   - a block that could not be made: from the body, before FILL!;
  ;;   - a free that failed, as when PROC freed the block itself: from its
  ;;     after thunk, once the block's extent is left.
  (define (call-with-block who size fill! proc)
    (let ((block #f)
          (freed #f)
          (make-failure #f)
          (free-failure #f))
      (dynamic-wind
        (lambda ()
          (when freed
            (assertion-violation who "re-entered after its block was freed")))
        (lambda ()
          (dynamic-wind #t
            (lambda ()
              (set! make-failure
                    (guard (c (#t (list c)))
                      (set! block (foreign-block size))
                      #f)))
            (lambda ()
              (when make-failure (raise (car make-failure)))
              (fill! block)
              (proc block))
            (lambda ()
              (set! freed #t)
              (when block
                (let ((made block))
                  (set! block #f)
                  (set! free-failure
                        (guard (c (#t (list c)))
                          (free-foreign-block! made)
                          #f)))))))
        (lambda ()
          (when free-failure
            (let ((failure (car free-failure)))
              (set! free-failure #f)
              (raise failure)))))))

  ;; call-with-c-string : Symbol String (Positive-Integer -> A) -> A
  ;; PROC's answer, PROC given the address of STRING as C reads it: its UTF-8
  ;; bytes and a NUL, in a counted block freed once PROC returns, raises or
  ;; escapes. STRING is the caller's, and mutable, so it is copied first, and
  ;; the copy alone is checked and encoded: a check of STRING, then an encoding
  ;; of it, would let another thread change it between the two. A STRING that
  ;; holds U+0000, which C would read as its end, is an assertion violation
  ;; from WHO before anything is allocated, as is a STRING that is no string,
  ;; or a PROC that is no procedure, each named by shown-value. Re-entering
  ;; PROC after the free raises from WHO.
  (define (call-with-c-string who string proc)
    (check-who 'call-with-c-string who)
    (unless (string? string)
      (assertion-violation who "not a string" (shown-value string)))
    (unless (procedure? proc)
      (assertion-violation who "not a procedure" (shown-value proc)))
    (let ((copy (string-copy string)))
      (when (holds-nul? copy)
        (assertion-violation who "a string C reads ends at its first NUL, and this one holds U+0000"
                             (shown-value copy)))
      (let* ((utf8 (string->utf8 copy))
             (n (bytevector-length utf8)))
        (call-with-block who (+ n 1)
          (lambda (block)
            (let loop ((i 0))
              (when (< i n)
                (foreign-set! 'unsigned-8 block i (bytevector-u8-ref utf8 i))
                (loop (+ i 1))))
            (foreign-set! 'unsigned-8 block n 0))
          proc))))

  ;; c-string->string : Natural -> (U String #f)
  ;; The NUL-terminated string at ADDRESS, read byte by byte up to its NUL,
  ;; into a bytevector of exactly that length, and decoded as UTF-8; #f for
  ;; NULL. An ADDRESS that is no exact natural is an assertion violation.
  (define (c-string->string address)
    (unless (exact-natural? address)
      (assertion-violation 'c-string->string "an address is an exact non-negative integer"
                           (shown-value address)))
    (and (not (eqv? address 0))
         (let* ((n (let scan ((i 0))
                     (if (eqv? (foreign-ref 'unsigned-8 address i) 0) i (scan (+ i 1)))))
                (bytes (make-bytevector n)))
           (let fill ((i 0))
             (when (< i n)
               (bytevector-u8-set! bytes i (foreign-ref 'unsigned-8 address i))
               (fill (+ i 1))))
           (utf8->string bytes))))

  ;; call-with-out-pointer : Symbol (Positive-Integer -> A) -> (Values A Natural)
  ;; PROC's answer, and the pointer its slot holds once PROC has returned:
  ;; PROC given the address of a counted block of a pointer's size, set to 0
  ;; first, so a call that writes nothing reads NULL. The slot is freed once
  ;; PROC returns, raises or escapes, and re-entering PROC after the free
  ;; raises from WHO. A PROC that is no procedure is an assertion violation
  ;; from WHO.
  (define (call-with-out-pointer who proc)
    (check-who 'call-with-out-pointer who)
    (unless (procedure? proc)
      (assertion-violation who "not a procedure" (shown-value proc)))
    (call-with-block who (foreign-sizeof 'uptr)
      (lambda (slot) (foreign-set! 'uptr slot 0 0))
      (lambda (slot)
        (let ((answer (proc slot)))
          (values answer (foreign-ref 'uptr slot 0))))))

  ;; --- 1. choose -----------------------------------------------------------------

  (define chosen
    (load-step
     (call-with-values
      (lambda () (choose-libsqlite3 getenv (machine-type) (maps-text) file-exists?))
      cons)))

  (define libsqlite3-path (car chosen))
  (define libsqlite3-source (cdr chosen))

  ;; --- 2. load, once ---------------------------------------------------------------

  (define libsqlite3-loaded
    (load-step
     (guard (e (#t (raise-library-unavailable
                    'load-failed libsqlite3-path libsqlite3-source (loader-message e) '() #f
                    "the loader refused this libsqlite3; name one this Chez can load with CHEZ_SQLITE3_LIBRARY, an absolute path"
                    (list libsqlite3-path))))
       (load-shared-object libsqlite3-path)
       #t)))

  ;; --- 3. the report ----------------------------------------------------------------

  ;; int sqlite3_libversion_number(void)
  (define raw-libversion-number
    (load-step
     (bind-required #f
       (foreign-procedure "sqlite3_libversion_number" () int))))

  ;; const char *sqlite3_libversion(void)
  (define raw-libversion
    (load-step
     (bind-required #f
       (foreign-procedure "sqlite3_libversion" () uptr))))

  ;; const char *sqlite3_sourceid(void)
  (define raw-sourceid
    (load-step
     (bind-required #f
       (foreign-procedure "sqlite3_sourceid" () uptr))))

  ;; answered-null : String -> Nothing
  ;; The refusal of a library whose ENTRY answered NULL where SQLite answers a
  ;; string, before the report exists.
  (define (answered-null entry)
    (raise-library-unavailable
     'load-failed libsqlite3-path libsqlite3-source entry '() #f
     (string-append entry " answered NULL, so this libsqlite3 cannot say what it is; name another with CHEZ_SQLITE3_LIBRARY")
     (list libsqlite3-path)))

  ;; The report: the five fields, and no others (ADR-0002, amended).
  (define report
    (load-step
     (let* ((number (raw-libversion-number))
            (version (or (c-string->string (raw-libversion))
                         (answered-null "sqlite3_libversion")))
            (source-id (or (c-string->string (raw-sourceid))
                           (answered-null "sqlite3_sourceid"))))
       (make-libsqlite3-info libsqlite3-path libsqlite3-source version number source-id))))

  ;; --- 4. the floor ------------------------------------------------------------------

  (define version-checked
    (load-step
     (check-version (libsqlite3-info-version report) (libsqlite3-info-version-number report)
                    libsqlite3-path libsqlite3-source report)))

  ;; --- 5. threadsafe ------------------------------------------------------------------

  ;; int sqlite3_threadsafe(void)
  (define raw-threadsafe
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_threadsafe" () int))))

  ;; The answer, read once: the one checked is the one loaded-threadsafe gives.
  (define threadsafe
    (load-step (raw-threadsafe)))

  (define threadsafe-checked
    (load-step
     (check-threadsafe threadsafe libsqlite3-path libsqlite3-source report)))

  ;; --- 6. sqlite3_initialize -----------------------------------------------------------

  ;; int sqlite3_initialize(void)
  ;; Thread-safe, and a no-op once SQLite is initialised (sqlite3.h).
  (define raw-initialize
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_initialize" () int))))

  (define initialized
    (load-step
     (let ((code (raw-initialize)))
       (unless (eqv? code 0)
         (raise-library-unavailable
          'load-failed libsqlite3-path libsqlite3-source code '() report
          "sqlite3_initialize did not answer SQLITE_OK, so this libsqlite3 cannot be used; name another with CHEZ_SQLITE3_LIBRARY"
          (list libsqlite3-path)))
       #t)))

  ;; --- 7. the rest, eagerly --------------------------------------------------------------

  ;; sqlite3-compileoption-used : Positive-Integer -> Integer
  ;; int sqlite3_compileoption_used(const char *zOptName): the address of a C
  ;; string, as call-with-c-string hands it; 1 when the option was used, else 0.
  (define sqlite3-compileoption-used
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_compileoption_used" (uptr) int))))

  ;; sqlite3-compileoption-get : Integer -> Natural
  ;; const char *sqlite3_compileoption_get(int N): the address of the Nth
  ;; option, for c-string->string; 0 past the last.
  (define sqlite3-compileoption-get
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_compileoption_get" (int) uptr))))

  ;; sqlite3-open-v2 : Positive-Integer Positive-Integer Integer Natural -> Integer
  ;; int sqlite3_open_v2(const char *filename, sqlite3 **ppDb, int flags,
  ;;                     const char *zVfs): a C string's address, an
  ;; out-pointer's slot, the flags and 0 for the default VFS; the result code.
  ;; It can block, creating the file (ADR-0011).
  (define sqlite3-open-v2
    (load-step
     (bind-required report
       (foreign-procedure __collect_safe "sqlite3_open_v2" (uptr uptr int uptr) int))))

  ;; sqlite3-close : Positive-Integer -> Integer
  ;; int sqlite3_close(sqlite3*): the result code. It can block, writing
  ;; (ADR-0011).
  (define sqlite3-close
    (load-step
     (bind-required report
       (foreign-procedure __collect_safe "sqlite3_close" (uptr) int))))

  ;; sqlite3-errmsg : Positive-Integer -> Natural
  ;; const char *sqlite3_errmsg(sqlite3*): an address, for c-string->string.
  (define sqlite3-errmsg
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_errmsg" (uptr) uptr))))

  ;; sqlite3-errstr : Integer -> Natural
  ;; const char *sqlite3_errstr(int): an address, for c-string->string.
  (define sqlite3-errstr
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_errstr" (int) uptr))))

  ;; sqlite3-errcode : Positive-Integer -> Integer
  ;; int sqlite3_errcode(sqlite3 *db)
  (define sqlite3-errcode
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_errcode" (uptr) int))))

  ;; sqlite3-extended-errcode : Positive-Integer -> Integer
  ;; int sqlite3_extended_errcode(sqlite3 *db)
  (define sqlite3-extended-errcode
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_extended_errcode" (uptr) int))))

  ;; sqlite3-next-stmt : Positive-Integer Natural -> Natural
  ;; sqlite3_stmt *sqlite3_next_stmt(sqlite3 *pDb, sqlite3_stmt *pStmt): the
  ;; statement after PSTMT, or the first for 0; 0 when there is none.
  (define sqlite3-next-stmt
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_next_stmt" (uptr uptr) uptr))))

  ;; sqlite3-memory-used : -> Integer
  ;; sqlite3_int64 sqlite3_memory_used(void), 64 bits: never an int, the
  ;; assessment's error.
  (define sqlite3-memory-used
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_memory_used" () integer-64))))

  ;; M2's 21 (ADR-0002, M2's amendment). A statement is a Positive-Integer
  ;; here, the address SQLite handed back, as a connection is; a column's
  ;; index counts from 0, a parameter's from 1.

  ;; sqlite3-prepare-v3 : Positive-Integer Positive-Integer Integer Natural
  ;;                      Positive-Integer Positive-Integer -> Integer
  ;; int sqlite3_prepare_v3(sqlite3 *db, const char *zSql, int nByte,
  ;;                        unsigned int prepFlags, sqlite3_stmt **ppStmt,
  ;;                        const char **pzTail): the handle, a C string's
  ;; address, its byte length, the flags (0 in v1), and two out-pointers'
  ;; slots, the statement's and the tail's; the result code. It can block,
  ;; reading the schema, and wait in the busy handler (ADR-0011, amended).
  (define sqlite3-prepare-v3
    (load-step
     (bind-required report
       (foreign-procedure __collect_safe "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))))

  ;; sqlite3-finalize : Natural -> Integer
  ;; int sqlite3_finalize(sqlite3_stmt *pStmt): the result code. It can wait
  ;; in the busy handler (ADR-0011, amended).
  (define sqlite3-finalize
    (load-step
     (bind-required report
       (foreign-procedure __collect_safe "sqlite3_finalize" (uptr) int))))

  ;; sqlite3-step : Positive-Integer -> Integer
  ;; int sqlite3_step(sqlite3_stmt*): SQLITE_ROW, SQLITE_DONE or a failure's
  ;; code. It does the statement's I/O, and can wait in the busy handler
  ;; (ADR-0011, amended).
  (define sqlite3-step
    (load-step
     (bind-required report
       (foreign-procedure __collect_safe "sqlite3_step" (uptr) int))))

  ;; sqlite3-reset : Positive-Integer -> Integer
  ;; int sqlite3_reset(sqlite3_stmt *pStmt): the result code. It can wait in
  ;; the busy handler (ADR-0011, amended).
  (define sqlite3-reset
    (load-step
     (bind-required report
       (foreign-procedure __collect_safe "sqlite3_reset" (uptr) int))))

  ;; sqlite3-clear-bindings : Positive-Integer -> Integer
  ;; int sqlite3_clear_bindings(sqlite3_stmt*): every parameter NULL again;
  ;; the result code.
  (define sqlite3-clear-bindings
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_clear_bindings" (uptr) int))))

  ;; sqlite3-bind-parameter-count : Positive-Integer -> Natural
  ;; int sqlite3_bind_parameter_count(sqlite3_stmt*): the largest parameter
  ;; index.
  (define sqlite3-bind-parameter-count
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_bind_parameter_count" (uptr) int))))

  ;; sqlite3-bind-parameter-index : Positive-Integer Positive-Integer -> Natural
  ;; int sqlite3_bind_parameter_index(sqlite3_stmt*, const char *zName): a C
  ;; string's address, the name with its sigil; its index, 0 when no
  ;; parameter has it.
  (define sqlite3-bind-parameter-index
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_bind_parameter_index" (uptr uptr) int))))

  ;; sqlite3-bind-null : Positive-Integer Integer -> Integer
  ;; int sqlite3_bind_null(sqlite3_stmt*, int): the result code.
  (define sqlite3-bind-null
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_bind_null" (uptr int) int))))

  ;; sqlite3-bind-int64 : Positive-Integer Integer Integer -> Integer
  ;; int sqlite3_bind_int64(sqlite3_stmt*, int, sqlite3_int64): a value from
  ;; -2^63 to 2^63-1, 64 bits, never an int (the M2 plan, section 4.8). Chez
  ;; wraps one above it silently, so the range is the caller's to check
  ;; (ADR-0015, decision 2). The result code.
  (define sqlite3-bind-int64
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_bind_int64" (uptr int integer-64) int))))

  ;; sqlite3-bind-double : Positive-Integer Integer Flonum -> Integer
  ;; int sqlite3_bind_double(sqlite3_stmt*, int, double): the result code.
  (define sqlite3-bind-double
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_bind_double" (uptr int double) int))))

  ;; sqlite3-bind-text64 : Positive-Integer Integer Positive-Integer Natural
  ;;                       Natural Natural -> Integer
  ;; int sqlite3_bind_text64(sqlite3_stmt*, int, const char*, sqlite3_uint64,
  ;;                         void(*)(void*), unsigned char encoding): the
  ;; address of a counted block holding the UTF-8 bytes, never NULL, even for
  ;; none; their byte length; sqlite-transient, so SQLite copies them; and
  ;; sqlite-utf8. The result code (ADR-0015, decision 5).
  (define sqlite3-bind-text64
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_bind_text64" (uptr int uptr unsigned-64 uptr unsigned-8) int))))

  ;; sqlite3-bind-blob64 : Positive-Integer Integer Positive-Integer Natural
  ;;                       Natural -> Integer
  ;; int sqlite3_bind_blob64(sqlite3_stmt*, int, const void*, sqlite3_uint64,
  ;;                         void(*)(void*)): the address of a counted block
  ;; holding the bytes, never NULL, even for none; their length; and
  ;; sqlite-transient. The result code (ADR-0015, decision 5).
  (define sqlite3-bind-blob64
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_bind_blob64" (uptr int uptr unsigned-64 uptr) int))))

  ;; sqlite3-column-count : Positive-Integer -> Natural
  ;; int sqlite3_column_count(sqlite3_stmt *pStmt)
  (define sqlite3-column-count
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_column_count" (uptr) int))))

  ;; sqlite3-column-name : Positive-Integer Integer -> Natural
  ;; const char *sqlite3_column_name(sqlite3_stmt*, int N): an address, for
  ;; c-string->string; 0 when SQLite has none to give.
  (define sqlite3-column-name
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_column_name" (uptr int) uptr))))

  ;; sqlite3-column-type : Positive-Integer Integer -> Integer
  ;; int sqlite3_column_type(sqlite3_stmt*, int iCol): a type code,
  ;; sqlite-integer to sqlite-null.
  (define sqlite3-column-type
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_column_type" (uptr int) int))))

  ;; sqlite3-column-int64 : Positive-Integer Integer -> Integer
  ;; sqlite3_int64 sqlite3_column_int64(sqlite3_stmt*, int iCol), 64 bits:
  ;; never an int (the M2 plan, section 4.8).
  (define sqlite3-column-int64
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_column_int64" (uptr int) integer-64))))

  ;; sqlite3-column-double : Positive-Integer Integer -> Flonum
  ;; double sqlite3_column_double(sqlite3_stmt*, int iCol)
  (define sqlite3-column-double
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_column_double" (uptr int) double))))

  ;; sqlite3-column-text : Positive-Integer Integer -> Natural
  ;; const unsigned char *sqlite3_column_text(sqlite3_stmt*, int iCol): an
  ;; address, read by our own code for sqlite3_column_bytes' count, read
  ;; after it; 0 for NULL.
  (define sqlite3-column-text
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_column_text" (uptr int) uptr))))

  ;; sqlite3-column-blob : Positive-Integer Integer -> Natural
  ;; const void *sqlite3_column_blob(sqlite3_stmt*, int iCol): an address,
  ;; read as sqlite3-column-text's is; 0 for NULL and for an empty BLOB.
  (define sqlite3-column-blob
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_column_blob" (uptr int) uptr))))

  ;; sqlite3-column-bytes : Positive-Integer Integer -> Natural
  ;; int sqlite3_column_bytes(sqlite3_stmt*, int iCol): the byte count of the
  ;; text or blob last read from the column.
  (define sqlite3-column-bytes
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_column_bytes" (uptr int) int))))

  ;; sqlite3-error-offset : Positive-Integer -> Integer
  ;; int sqlite3_error_offset(sqlite3 *db): the byte offset into the SQL of
  ;; the error the last call reported, or -1 when it has none, as for an
  ;; error at the end of the SQL.
  (define sqlite3-error-offset
    (load-step
     (bind-required report
       (foreign-procedure "sqlite3_error_offset" (uptr) int))))

  ;; --- 8. the exit check ---------------------------------------------------------------
  ;; The count SQLite holds once initialised and bound, before anything is
  ;; opened, is the baseline. The sqlite3_memory_used check against it is
  ;; registered with the counters, which suite-exit-status reads, so only a
  ;; process whose load got this far has it to run (ADR-0005, amended; the M1
  ;; plan, §3.7). Neither definition can raise, so neither is a load-step.
  (define memory-baseline (sqlite3-memory-used))

  (define memory-check-registered
    (register-exit-check! 'sqlite3_memory_used
                          (make-memory-check memory-baseline sqlite3-memory-used
                                             call-with-c-string call-with-out-pointer
                                             sqlite3-open-v2 sqlite3-close)))

  ;; --- the report's readers ----------------------------------------------------------

  ;; loaded-libsqlite3 : -> Libsqlite3-Info
  ;; The libsqlite3 this process loaded and accepted. Reaching this binding
  ;; runs the load above, once; a refusal raises from there instead, at this
  ;; reference and every later one.
  (define (loaded-libsqlite3) report)

  ;; loaded-threadsafe : -> Integer
  ;; What sqlite3_threadsafe answered at the load, the answer check-threadsafe
  ;; accepted: 1 serialized, 2 multi-thread.
  (define (loaded-threadsafe) threadsafe))
