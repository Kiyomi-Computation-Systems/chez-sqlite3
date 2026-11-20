#!r6rs
;;; (chez-sqlite3 private extension): load-extension!, the verb that loads
;;; a SQLite extension into a connection that opted in at open (ADR-0021).
;;; (chez-sqlite3) exports the verb; load-extension/with, its form that
;;; takes the load's binding and the message's copy, is exported for the
;;; suites alone, as interrupt-database/with takes its foreign call.
;;;
;;; Its checks, in order, before anything reaches C, each refusal naming
;;; load-extension!:
;;;
;;;   1. a database        else an assertion violation, not-a-database
;;;   2. its owning thread else &sqlite-wrong-thread (ADR-0010)
;;;   3. open              else &sqlite-closed
;;;   4. the path          a string, else path-not-a-string; holding no
;;;                        U+0000, else path-holds-nul; absolute, its first
;;;                        character /, else path-not-absolute: no relative
;;;                        path, bare name or "", whose file the working
;;;                        directory or the loader's own search would
;;;                        choose. On Linux the loader takes an absolute
;;;                        path as it is; on macOS, DYLD_LIBRARY_PATH still
;;;                        sends dyld to a file of the same leaf name in its
;;;                        folders first
;;;   5. the entry point   when given, a string, else
;;;                        entry-point-not-a-string; holding no U+0000, else
;;;                        entry-point-holds-nul
;;;   6. the opt-in        the record's, read by database-extension-loading?,
;;;                        else an assertion violation,
;;;                        extension-loading-not-enabled, whose message
;;;                        names the fix, (enable-load-extension . #t)
;;;                        (ADR-0021)
;;;
;;; The first three are one call-with-open-handle, its procedure answering
;;; nothing, in a critical section of its own: its database and owner
;;; checks, then its open check inside its section. So the thread's refusal
;;; and the closed one come before the argument checks, and SQLite, which
;;; loads from any thread, is never reached from another. The load's own
;;; section goes through call-with-open-handle again, which checks the owner
;;; and the open state there too. Each string is copied
;;; first and the copy alone checked and handed to C, so another thread
;;; cannot change it between the two (ADR-0011). Every refusal of a caller's
;;; mistake is an assertion violation whose irritants are a symbol naming its
;;; rule, then the value by shown-value, never a string's text (ADR-0013). On
;;; Ubuntu's library, whose every connection opens with the C switch on, the
;;; sixth check is all that stops a load.
;;;
;;; One call, one load. Chez's engine remainders are multi-shot, and a
;;; timer's handler can capture a continuation between any two critical
;;; sections, so one call can have several runs pending at once. Every load
;;; runs the extension's init again, so two runs that both loaded would run
;;; it twice. The call holds a claim, made by its first expression,
;;; (chez-sqlite3 private conveniences)' made-claim: the load's one section
;;; claims position 0, the call's last, inside the section, before anything
;;; else there. A run the call has passed is refused: it touches nothing, and
;;; raises &sqlite-closed after it (ADR-0016). A remainder taken before the
;;; call's first expression is the caller's own: resumed, it makes a whole
;;; new call, with a claim of its own.
;;;
;;; The one section, a critical section around call-with-open-handle, so no
;;; engine's expiry and no timer's handler falls inside either, holds:
;;;
;;;   - the claim, compared first;
;;;   - the path's C string, the entry point's or NULL, and the message's
;;;     slot, a pointer-sized counted block set to NULL, by native's
;;;     call-with-c-string and call-with-out-pointer;
;;;   - the connection's extended code, read just before the call, and
;;;     again just after it;
;;;   - the call, __collect_safe (ADR-0011): a dlopen can wait,
;;;     on a FIFO, and another thread's collection need not wait with it;
;;;   - when the slot holds a message, its copy under a guard, then its
;;;     sqlite3_free whatever the copy did, so no message is left unfreed
;;;     on any path; what the copy raised is raised after the section;
;;;   - for a failure, when the extended code changed across the call to
;;;     one that names an error, the connection's sqlite3_errmsg, copied;
;;;     and sqlite3_errstr's text for the code when the slot held none.
;;;
;;; Every block lives whole in the section (ADR-0011). It answers data, and
;;; the raise comes after it (ADR-0012):
;;;
;;;   success   the call answered 0: nothing. The extension stays loaded
;;;             until the connection closes, and what it registers is the
;;;             connection's
;;;   failure   &sqlite-error from raise-sqlite-error, its code and extended
;;;             code the call's own answer, never the connection's, which an
;;;             init's failing call leaves at its own code, 5 where the call
;;;             answered 1; no SQL and no offset. Its message: the slot's
;;;             text, as SQLite wrote it, naming the path it tried last; or
;;;             sqlite3_errstr's when the slot held none;
;;;             followed, when the connection's extended code changed
;;;             across the call to one that names an error, by the
;;;             connection's message, which holds an init's reason where the
;;;             slot says only "error during initialization: ". An init
;;;             whose last call succeeded leaves the code at 0, which names
;;;             no error, and its "not an error" is no reason: then the
;;;             slot's text stands alone. The two join as they stand where the
;;;             first ends in a space, as SQLite's "...: " does, and with
;;;             ": " between them otherwise
;;;   no error  a code that names no error, its low byte 0, 100 or 101 but
;;;             not 0 itself, or no exact integer, which only a stand-in for
;;;             the binding answers: an assertion violation from the verb,
;;;             (not-an-error CODE), tested here before raise-sqlite-error,
;;;             whose own refusal would name it, as the open's db_config
;;;             sets are (ADR-0021)
;;;
;;; A failed load leaves the connection as it was: SQLite's own failures set
;;; no error on it.
(library (chez-sqlite3 private extension)
  (export load-extension! load-extension/with)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (only (chezscheme) critical-section)
          (only (chez-sqlite3 private native) sqlite3-load-extension sqlite3-free sqlite3-errstr
                sqlite3-errmsg sqlite3-extended-errcode call-with-c-string call-with-out-pointer
                c-string->string)
          (only (chez-sqlite3 private constants) sqlite-result-codes)
          (only (chez-sqlite3 private conditions) raise-sqlite-error raise-closed shown-value)
          (only (chez-sqlite3 private connection) call-with-open-handle database-extension-loading?)
          (only (chez-sqlite3 private conveniences) made-claim))

  (define who 'load-extension!)

  (define sqlite-ok (cdr (assq 'ok sqlite-result-codes)))

  ;; --- the checks ----------------------------------------------------------------------

  ;; holds-nul? : String -> Boolean
  (define (holds-nul? s)
    (let loop ((i 0))
      (and (< i (string-length s))
           (or (char=? (string-ref s i) #\nul) (loop (+ i 1))))))

  ;; checked-open : Any -> Void
  ;; The first three checks: DB a database, on its owning thread, and open,
  ;; by call-with-open-handle, whose procedure answers nothing, in a
  ;; critical section of its own, so no expiry falls inside its wind. What
  ;; it raised is caught there and raised after it, the same object.
  (define (checked-open db)
    (let ((outcome (critical-section
                    (guard (c (#t (list 'raised c)))
                      (call-with-open-handle who db (lambda (handle) '(open)))))))
      (unless (eq? (car outcome) 'open)
        (raise (cadr outcome)))))

  ;; checked-path : Any -> String
  ;; PATH, copied, once checked: a string, holding no U+0000, and absolute;
  ;; each refusal an assertion violation from load-extension!, before
  ;; anything is allocated.
  (define (checked-path path)
    (unless (string? path)
      (assertion-violation who "the extension's path is a string" 'path-not-a-string
                           (shown-value path)))
    (let ((copy (string-copy path)))
      (when (holds-nul? copy)
        (assertion-violation who "the extension's path holds U+0000, where C would read its end"
                             'path-holds-nul (shown-value copy)))
      (unless (and (> (string-length copy) 0) (char=? (string-ref copy 0) #\/))
        (assertion-violation who
                             "the extension's path is absolute, as /opt/app/lib/ext.so is: a relative path or a bare name leaves the choice of file to the working directory or the loader's own search"
                             'path-not-absolute (shown-value copy)))
      copy))

  ;; checked-entry : Any -> String
  ;; ENTRY, the entry point's C name, copied, once checked: a string holding
  ;; no U+0000; each refusal an assertion violation from load-extension!.
  (define (checked-entry entry)
    (unless (string? entry)
      (assertion-violation who "the entry point is a string, its C name" 'entry-point-not-a-string
                           (shown-value entry)))
    (let ((copy (string-copy entry)))
      (when (holds-nul? copy)
        (assertion-violation who "the entry point holds U+0000, where C would read its end"
                             'entry-point-holds-nul (shown-value copy)))
      copy))

  ;; checked-opt-in : Database -> Void
  ;; The last check: DB opted in at open, by the record's opt-in, which
  ;; database-extension-loading? reads after check-owned's two checks, from
  ;; load-extension!. The first three made them already, but a remainder
  ;; taken after them can be resumed on another thread, and the refusal
  ;; there names this verb too (ADR-0013).
  (define (checked-opt-in db)
    (unless (database-extension-loading? who db)
      (assertion-violation who
                           "this connection did not opt in to extension loading: open it with (enable-load-extension . #t) in its settings list"
                           'extension-loading-not-enabled)))

  ;; --- the load ---------------------------------------------------------------------------

  ;; LoadBinding = (Positive-Integer Positive-Integer Natural Positive-Integer -> Any)
  ;; native's sqlite3-load-extension, or a stand-in a suite gives
  ;; load-extension/with: the handle, the path's C string, the entry
  ;; point's or 0, the message's slot; the code.
  ;; Copy = (Natural -> Any)
  ;; native's c-string->string, or a stand-in: the slot's message, read.

  ;; names-error? : Any -> Boolean
  ;; Whether CODE, the load's answer, names an error: an exact integer whose
  ;; low byte is none of 0, 100 and 101, which raise-sqlite-error refuses as
  ;; no error. Raises nothing.
  (define (names-error? code)
    (and (integer? code) (exact? code)
         (not (memv (bitwise-and code 255) '(0 100 101)))))

  ;; joined : String (U String #f) -> String
  ;; A failure's message, BASE followed by the connection's message MORE,
  ;; when there is one: as they stand when BASE is empty or ends in a
  ;; space, else with ": " between them.
  (define (joined base more)
    (cond ((not more) base)
          ((or (= (string-length base) 0)
               (char=? (string-ref base (- (string-length base) 1)) #\space))
           (string-append base more))
          (else (string-append base ": " more))))

  ;; called : LoadBinding Copy Positive-Integer Positive-Integer Natural
  ;;          -> (U (List 'loaded) (List 'failed Integer String) (List 'not-an-error Any)
  ;;                (List 'raised Any))
  ;; The load on HANDLE of the C strings at FILE and PROC, 0 for none, by
  ;; LOAD, inside its caller's section: the slot made, the connection's
  ;; extended code read before the call and after it, the call; then the
  ;; slot's message, when there is one, copied by COPY under a guard and
  ;; freed with sqlite3_free whatever the copy did; then, for a failure,
  ;; sqlite3_errstr's text when the slot held none, and the connection's
  ;; sqlite3_errmsg when its extended code changed to one that names an
  ;; error, by names-error?: an init's failing call left it, where a call
  ;; that succeeded leaves 0 and "not an error". Answers loaded; failed,
  ;; the code and the message; not-an-error, the code; or what the copy
  ;; raised.
  (define (called load copy handle file proc)
    (let-values (((codes message)
                  (call-with-out-pointer who
                    (lambda (slot)
                      (let* ((before (sqlite3-extended-errcode handle))
                             (code (load handle file proc slot))
                             (after (sqlite3-extended-errcode handle)))
                        (list code before after))))))
      (let* ((code (car codes))
             (text (if (eqv? message 0)
                       '(none)
                       (let ((read (guard (c (#t (list 'raised c)))
                                     (list 'copied (copy message)))))
                         (sqlite3-free message)
                         read))))
        (cond ((eq? (car text) 'raised) text)
              ((eqv? code sqlite-ok) '(loaded))
              ((not (names-error? code)) (list 'not-an-error code))
              (else
               (let ((base (if (eq? (car text) 'copied)
                               (cadr text)
                               (or (c-string->string (sqlite3-errstr code)) "")))
                     (more (and (names-error? (caddr codes))
                                (not (eqv? (cadr codes) (caddr codes)))
                                (c-string->string (sqlite3-errmsg handle)))))
                 (list 'failed code (joined base more))))))))

  ;; load-section : Claim Database String (U String #f) LoadBinding Copy
  ;;                -> (U (List 'refused) (List 'raised Any) (List 'loaded)
  ;;                      (List 'failed Integer String) (List 'not-an-error Any))
  ;; The call's one section: in a critical section, CLAIM given position 0,
  ;; the call's last, first; refused, nothing touched. Claimed, through
  ;; call-with-open-handle, the path FILE's C string and the entry point
  ;; PROC's, or 0 when it is #f, then called. What any of it raised is
  ;; caught there, the same object. Raises nothing.
  (define (load-section claim db file proc load copy)
    (critical-section
     (if (not (claim 0 #t))
         '(refused)
         (guard (c (#t (list 'raised c)))
           (call-with-open-handle who db
             (lambda (handle)
               (call-with-c-string who file
                 (lambda (c-file)
                   (if proc
                       (call-with-c-string who proc
                         (lambda (c-proc) (called load copy handle c-file c-proc)))
                       (called load copy handle c-file 0))))))))))

  ;; loaded : LoadBinding Copy Any Any (Listof Any) -> Void
  ;; The verb's work, for load-extension/with: the claim, made by the first
  ;; expression; the six checks, in order; the one section; then its
  ;; outcome raised, after it. ENTRIES is () when no entry point was given,
  ;; else the one given.
  (define (loaded load copy db path entries)
    (let ((claim (made-claim)))
      (checked-open db)
      (let* ((file (checked-path path))
             (proc (and (pair? entries) (checked-entry (car entries)))))
        (checked-opt-in db)
        (let ((outcome (load-section claim db file proc load copy)))
          (case (car outcome)
            ((loaded) (if #f #f))
            ((refused) (raise-closed who))
            ((failed) (raise-sqlite-error who (cadr outcome) (caddr outcome) #f #f))
            ((not-an-error)
             (assertion-violation who "the load answered a code that names no error"
                                  'not-an-error (cadr outcome)))
            (else (raise (cadr outcome))))))))

  ;; load-extension! : (case-> (Database String -> Void) (Database String String -> Void))
  ;; The extension at PATH, an absolute path, loaded into DB, which opted in
  ;; with (enable-load-extension . #t), by sqlite3_load_extension: its entry
  ;; point ENTRY, the init's C name, when given; else NULL, and SQLite's own
  ;; search, sqlite3_extension_init, then sqlite3_ followed by the letters
  ;; of the file's base name, after a leading lib and before the first dot,
  ;; lower-cased, then _init. SQLite tries PATH, then PATH with .so
  ;; appended, .dylib on a Mac, and a failure's message names the one it
  ;; tried last. Every load runs the init again; the extension stays loaded
  ;; until DB closes. Called on DB's own thread. Answers nothing.
  (define load-extension!
    (case-lambda
      ((db path) (loaded sqlite3-load-extension c-string->string db path '()))
      ((db path entry) (loaded sqlite3-load-extension c-string->string db path (list entry)))))

  ;; load-extension/with : (case-> (LoadBinding Copy Database String -> Void)
  ;;                               (LoadBinding Copy Database String String -> Void))
  ;; load-extension!'s work, with the load's binding LOAD and the message's
  ;; copy COPY given, so a suite reaches a failure the library never gives,
  ;; a slot left empty or a copy that raises, through a stand-in: LOAD is
  ;; called inside the section, with the handle, the two C strings' addresses
  ;; and the slot's, and answers the code; COPY is given the slot's message,
  ;; when there is one. For the suites; (chez-sqlite3) exports only
  ;; load-extension!.
  (define load-extension/with
    (case-lambda
      ((load copy db path) (loaded load copy db path '()))
      ((load copy db path entry) (loaded load copy db path (list entry))))))
