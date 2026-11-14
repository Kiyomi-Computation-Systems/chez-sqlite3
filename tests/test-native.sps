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
;;;   C strings      call-with-c-string: UTF-8 on bytes where encodings
;;;                  differ, the NUL written, U+0000 refused at every position
;;;                  before anything is allocated, by kind, from the WHO it is
;;;                  given; the block freed on return, raise and escape, and
;;;                  re-entry refused. c-string->string reads them back
;;;   out-pointers   call-with-out-pointer: a zeroed, counted slot, read after
;;;                  PROC and freed on every path
;;;   the body       native.sls read as data: its load steps in order, and
;;;                  every foreign-procedure form bound eagerly, as the value
;;;                  of a top-level load-step definition. With one good library
;;;                  in one process neither can be seen by behaviour: the load
;;;                  runs once, and every check passes. M1 slice 3's decoy sees
;;;                  them
;;;   collect-safe   sqlite3_open_v2 blocked on a FIFO while another thread
;;;                  collects: the collection finishes only if the call is
;;;                  __collect_safe. The types and conventions of every binding
;;;                  are the convention suite's
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own: SRFI-64 makes #f of a raise in an actual expression, and catches
;;; none in an expected expression or a top-level definition. No expected
;;; value here is #f. Effects run in order, through let* and named lets,
;;; never map (AGENTS.md).
;;;
;;; The oracle is a child process, and runs outside Valgrind. It is C reading
;;; SQLite, not chez-sqlite3's native layer, and keeps no counts. So are the
;;; shells the FIFO row starts.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-ref foreign-set! foreign-sizeof getenv machine-type
              library-exports fork-thread make-mutex with-mutex collect-rendezvous
              sleep make-time)
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
(test-equal "(chez-sqlite3 private native) exports exactly the report, the threadsafe answer, the ten raw bindings, and the C-string and out-pointer helpers"
  (sorted-names '(loaded-libsqlite3 loaded-threadsafe
                  sqlite3-open-v2 sqlite3-close sqlite3-errmsg sqlite3-errstr sqlite3-errcode
                  sqlite3-extended-errcode sqlite3-next-stmt sqlite3-memory-used
                  sqlite3-compileoption-used sqlite3-compileoption-get
                  call-with-c-string c-string->string call-with-out-pointer))
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
;; (define NAME (load-step (bind-required LIBRARY (foreign-procedure ...)))).
(define (placed-binding form)
  (let ((step (load-step-of form)))
    (and step
         (let ((expr (cadr step)))
           (and (list? expr) (= (length expr) 3) (eq? (car expr) 'bind-required)
                (let ((fp (caddr expr)))
                  (and (pair? fp) (eq? (car fp) 'foreign-procedure)
                       (list (car step) (cadr expr) (c-name fp)))))))))

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
(test-equal "native's load steps, in order: choose, load, the report's three bindings and the report, the floor, threadsafe's binding, answer and check, sqlite3_initialize's binding and call, then the rest of M1's required list, in ADR-0002's order; each with the head of what it runs and the load's names it uses"
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
    (sqlite3-memory-used bind-required report))
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

(test-equal "every foreign-procedure form in native.sls binds eagerly: each is a top-level (define NAME (load-step (bind-required LIBRARY (foreign-procedure ...)))), with no report for the report's own three and the report for the rest, and there are no others"
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
          (sqlite3-memory-used report "sqlite3_memory_used"))
        15)
  (if body-read?
      (list (let loop ((forms native-body) (found '()))
              (if (null? forms)
                  (reverse found)
                  (let ((placed (placed-binding (car forms))))
                    (loop (cdr forms) (if placed (cons placed found) found)))))
            (length (foreign-forms native-body)))
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

(test-equal "sqlite3_open_v2 is __collect_safe: blocked on a FIFO, it lets another thread's collection finish, and that thread releases it; it answers SQLITE_IOERR and the handle closes with SQLITE_OK; every count is zero after"
  (list (list (list ioerr ok) 'collected) 'released-by-the-collector zero-counts)
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
               (list answers released-by (native-counts)))))))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "native")

(exit (suite-exit-status runner))
