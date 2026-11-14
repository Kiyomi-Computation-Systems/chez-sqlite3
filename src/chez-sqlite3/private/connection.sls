#!r6rs
;;; (chez-sqlite3 private connection): a connection to a database, opened,
;;; owned and closed (ADR-0010, ADR-0012). (chez-sqlite3) exports its four
;;; public procedures; call-with-open-handle, the one way to a connection's
;;; handle, is M2's, and failure-details is exported for its suite.
;;;
;;; A connection is a database record, opaque and sealed, holding the
;;; sqlite3* as an integer, so Valgrind sees one never closed (the M1 plan,
;;; §3.1), and the get-thread-id of the thread that opened it. The handle
;;; field is #f once closed. No accessor of it escapes this library but
;;; call-with-open-handle, which checks first (ADR-0012, decision 2).
;;;
;;; Every verb checks, in order, that its argument is a database, that it
;;; runs on the owning thread, and that the connection is open, before
;;; anything reaches C (ADR-0012, decision 7). close-database! does the first
;;; two, and on a closed connection does nothing.
;;;
;;; The handle is read out of the record, used by each native call, and the
;;; record and the connection count changed, all in one critical section, and
;;; anything raised is raised after it, from the data it returns. An engine
;;; can preempt between any two calls, and two engines on one thread may share
;;; a connection: a check made outside the section, then a switch, then the
;;; other's close, would hand C a freed address. The native builder measured
;;; that a __collect_safe call inside critical-section lets other threads
;;; collect (ADR-0011's amendment), so sqlite3_open_v2 and sqlite3_close run
;;; there too.
;;;
;;;   the count   up when sqlite3_open_v2 hands back a handle, failed or not;
;;;               down when sqlite3_close answers SQLITE_OK (ADR-0012,
;;;               decision 6)
;;;   a failure   its extended code and message read from its handle, then
;;;               the handle closed, then &sqlite-error raised; a NULL handle
;;;               takes its message from sqlite3_errstr (decision 4)
;;;   the close   sqlite3_next_stmt must find no statement, since the
;;;               connection tracks none until M2: one found is a defect of
;;;               chez-sqlite3's, an assertion violation naming the count,
;;;               and the connection stays open. Then sqlite3_close, never
;;;               sqlite3_close_v2; an answer but SQLITE_OK is &sqlite-error,
;;;               and the connection stays open and counted (decision 5)
;;;
;;; Every refusal of a caller's mistake is an assertion violation whose
;;; irritants begin with a symbol naming its rule, then the value by
;;; shown-value, never a string's text (ADR-0013, decisions 7 and 9).
(library (chez-sqlite3 private connection)
  (export open-database close-database! call-with-database database?
          call-with-open-handle failure-details)
  (import (chez-sqlite3 private require-threaded)
          (except (rnrs) dynamic-wind)
          (only (chezscheme) critical-section dynamic-wind get-thread-id)
          (chez-sqlite3 private native)
          (chez-sqlite3 private counters)
          (only (chez-sqlite3 private constants) sqlite-open-uri sqlite-result-codes)
          (chez-sqlite3 private conditions)
          (chez-sqlite3 private open-options))

  (define sqlite-ok (cdr (assq 'ok sqlite-result-codes)))

  ;; database? : Any -> Boolean
  ;; Opaque, so record-rtd on a database raises, and sealed, so no type
  ;; extends it; not nongenerative, so no other definition makes its type.
  (define-record-type database
    (fields (mutable handle unchecked-database-handle set-database-handle!)
            (immutable owner unchecked-database-owner))
    (sealed #t)
    (opaque #t))

  ;; --- the checks ------------------------------------------------------------------

  ;; check-who : Symbol Any -> Void
  (define (check-who helper who)
    (unless (symbol? who)
      (assertion-violation helper "a who is a symbol" 'not-a-who (shown-value who))))

  ;; check-owned : Symbol Any -> Void
  ;; DB is a database, else an assertion violation from WHO; and this is its
  ;; owning thread, else &sqlite-wrong-thread from WHO.
  (define (check-owned who db)
    (unless (database? db)
      (assertion-violation who "not a database" 'not-a-database (shown-value db)))
    (let ((owner (unchecked-database-owner db))
          (caller (get-thread-id)))
      (unless (eqv? owner caller)
        (raise-wrong-thread who owner caller))))

  ;; call-with-open-handle : Symbol Any (Positive-Integer -> A) -> A
  ;; PROC's answer, given DB's handle, once DB is checked: a database, else an
  ;; assertion violation from WHO; on its owning thread, else
  ;; &sqlite-wrong-thread from WHO; open, else &sqlite-closed from WHO. The
  ;; checks and PROC run in one critical section, so the handle cannot be
  ;; closed between the check and its use. A WHO that is no symbol and a PROC
  ;; that is no procedure are assertion violations first.
  (define (call-with-open-handle who db proc)
    (check-who 'call-with-open-handle who)
    (unless (procedure? proc)
      (assertion-violation who "not a procedure" 'not-a-procedure (shown-value proc)))
    (critical-section
     (check-owned who db)
     (let ((handle (unchecked-database-handle db)))
       (unless handle (raise-closed who))
       (proc handle))))

  ;; --- a failure's details -------------------------------------------------------------

  ;; failure-details : Integer Natural (Natural -> Integer) (Natural -> (U String #f))
  ;;                   (Integer -> (U String #f)) -> (List Integer String)
  ;; The extended code and the message of a call that answered RC on HANDLE,
  ;; read through EXTENDED, ERRMSG and ERRSTR: for no handle, RC and
  ;; ERRSTR's text for it, calling neither other reader; else HANDLE's
  ;; extended code and its errmsg, or ERRSTR's text for that code when errmsg
  ;; answers NULL. A NULL from ERRSTR leaves the message empty. Pure but for
  ;; the readers: the shell passes the native bindings, a suite passes stubs.
  (define (failure-details rc handle extended errmsg errstr)
    (if (eqv? handle 0)
        (list rc (or (errstr rc) ""))
        (let* ((code (extended handle))
               (message (or (errmsg handle) (errstr code) "")))
          (list code message))))

  ;; details-of : Integer Natural -> (List Integer String)
  ;; failure-details, read from the library.
  (define (details-of rc handle)
    (failure-details rc handle sqlite3-extended-errcode
                     (lambda (h) (c-string->string (sqlite3-errmsg h)))
                     (lambda (code) (c-string->string (sqlite3-errstr code)))))

  ;; --- opening -----------------------------------------------------------------------------

  ;; prepared-open : Symbol Any (Listof Any) -> (Values String Natural)
  ;; FILENAME, copied, and its flags, once checked, for WHO: a FILENAME that
  ;; is no string, an option refused, and a copy that starts file: without
  ;; the uri option are assertion violations from WHO, before anything is
  ;; allocated. The caller's string is copied first and the copy alone is
  ;; checked and opened, so another thread cannot change it between the two
  ;; (ADR-0011, decision 2).
  (define (prepared-open who filename options)
    (unless (string? filename)
      (assertion-violation who "a filename is a string" 'not-a-string (shown-value filename)))
    (let ((parsed (parse-open-options options)))
      (case (car parsed)
        ((unknown)
         (assertion-violation who "not an option for opening a database" 'unknown-option
                              (cadr parsed)))
        ((twice)
         (assertion-violation who "an option given twice" 'option-given-twice (cadr parsed)))
        ((contradiction)
         (apply assertion-violation who "read-only contradicts read-write and create"
                'contradictory-options (cdr parsed)))
        (else
         (let ((copy (string-copy filename))
               (flags (cdr parsed)))
           (when (and (uri-filename? copy) (zero? (bitwise-and flags sqlite-open-uri)))
             (assertion-violation who
                                  "a filename that starts file: is a URI, which needs the uri option; name a file so named ./file:..."
                                  'file-uri-without-uri-option (shown-value copy)))
           (values copy flags))))))

  ;; open-connection : Symbol String Natural -> Database
  ;; A database opened on NAME, a checked copy, with FLAGS, owned by this
  ;; thread; or &sqlite-error from WHO. NAME holding U+0000 is
  ;; call-with-c-string's refusal, from WHO, before anything is allocated.
  ;; The open, the read of its out-pointer, the count and the record, or
  ;; else the failure's details and its handle's close, are one critical
  ;; section: no handle is ever left uncounted.
  (define (open-connection who name flags)
    (let ((outcome
           (call-with-c-string who name
             (lambda (c-name)
               (critical-section
                (let-values (((rc handle)
                              (call-with-out-pointer who
                                (lambda (slot) (sqlite3-open-v2 c-name slot flags 0)))))
                  (cond
                    ((eqv? handle 0) (cons 'failed (details-of rc 0)))
                    (else
                     (count-up! 'connection)
                     (if (eqv? rc sqlite-ok)
                         (list 'opened (make-database handle (get-thread-id)))
                         (let ((details (details-of rc handle)))
                           (when (eqv? (sqlite3-close handle) sqlite-ok)
                             (count-down! 'connection))
                           (cons 'failed details)))))))))))
      (if (eq? (car outcome) 'opened)
          (cadr outcome)
          (raise-sqlite-error who (cadr outcome) (caddr outcome) #f #f))))

  ;; open-database : String Symbol ... -> Database
  ;; FILENAME opened with OPTIONS, owned by the calling thread
  ;; (open-options' table; ADR-0012, decision 3).
  (define (open-database filename . options)
    (let-values (((name flags) (prepared-open 'open-database filename options)))
      (open-connection 'open-database name flags)))

  ;; --- closing -----------------------------------------------------------------------------

  ;; statements-on : Positive-Integer -> Natural
  ;; How many statements sqlite3_next_stmt finds on HANDLE.
  (define (statements-on handle)
    (let loop ((statement (sqlite3-next-stmt handle 0)) (n 0))
      (if (eqv? statement 0)
          n
          (loop (sqlite3-next-stmt handle statement) (+ n 1)))))

  ;; close-connection : Symbol Any -> Void
  ;; DB closed, for WHO; nothing when it is closed already.
  (define (close-connection who db)
    (check-owned who db)
    (let ((outcome
           (critical-section
            (let ((handle (unchecked-database-handle db)))
              (if (not handle)
                  '(already-closed)
                  (let ((untracked (statements-on handle)))
                    (if (> untracked 0)
                        (list 'untracked untracked)
                        (let ((rc (sqlite3-close handle)))
                          (if (eqv? rc sqlite-ok)
                              (begin
                                (set-database-handle! db #f)
                                (count-down! 'connection)
                                '(closed))
                              (cons 'failed (details-of rc handle)))))))))))
      (case (car outcome)
        ((untracked)
         (assertion-violation who "the connection has statements chez-sqlite3 does not track"
                              'untracked-statements (cadr outcome)))
        ((failed) (raise-sqlite-error who (cadr outcome) (caddr outcome) #f #f))
        (else (if #f #f)))))

  ;; close-database! : Database -> Void
  ;; DB closed; nothing when it is closed already. From another thread,
  ;; &sqlite-wrong-thread, closed or not.
  (define (close-database! db)
    (close-connection 'close-database! db))

  ;; --- call-with-database ------------------------------------------------------------------

  ;; split-last : (Pairof Any (Listof Any)) -> (Values (Listof Any) Any)
  (define (split-last items)
    (let loop ((rest items) (before '()))
      (if (null? (cdr rest))
          (values (reverse before) (car rest))
          (loop (cdr rest) (cons (car rest) before)))))

  ;; call-with-database : String Symbol ... (Database -> A ...) -> A ...
  ;; PROC's answers, PROC given FILENAME opened with the options before it
  ;; (ADR-0012, decision 8). Every check comes before anything opens: that
  ;; PROC, the last argument, is a procedure, then open-database's. Then:
  ;;   - PROC returns, or leaves through a continuation: the connection is
  ;;     closed, and that close's failure raises;
  ;;   - PROC raises: the connection is closed, and PROC's condition reaches
  ;;     the caller unchanged; a failure of that close is not raised over it,
  ;;     and the connection stays open and counted, for the gate to see;
  ;;   - a continuation that re-enters PROC finds the connection closed.
  ;; A raise is told from an escape by a handler around PROC that records it
  ;; and hands it on in place, with raise-continuable; PROC's return, or a
  ;; handler outside that returns, clears it. The before thunk does nothing,
  ;; and never clears it: a guard whose clauses do not match re-enters the
  ;; extent to raise again, and the close on the way out again must still be
  ;; contained. The open sits in the body with the variable the after thunk
  ;; reads, in one critical section, and the winder is Chez's critical form,
  ;; so no interrupt that escapes falls between the open and the close. An
  ;; engine's expiry is an escape: the connection does not survive one.
  ;; Everything raised names call-with-database.
  (define (call-with-database filename . rest)
    (let ((who 'call-with-database))
      (when (null? rest)
        (assertion-violation who "the procedure, the last argument, is missing" 'no-procedure))
      (let-values (((options proc) (split-last rest)))
        (unless (procedure? proc)
          (assertion-violation who "the last argument is the procedure" 'not-a-procedure
                               (shown-value proc)))
        (let-values (((name flags) (prepared-open who filename options)))
          (let ((db #f) (raising #f))
            (dynamic-wind #t
              (lambda () #f)
              (lambda ()
                (critical-section (set! db (open-connection who name flags)))
                (with-exception-handler
                 (lambda (c)
                   (set! raising (list c))
                   (call-with-values
                    (lambda () (raise-continuable c))
                    (lambda answers (set! raising #f) (apply values answers))))
                 (lambda ()
                   (call-with-values
                    (lambda () (proc db))
                    (lambda answers (set! raising #f) (apply values answers))))))
              (lambda ()
                (when db
                  (if raising
                      (guard (e (#t #f)) (close-connection who db))
                      (close-connection who db)))))))))))
