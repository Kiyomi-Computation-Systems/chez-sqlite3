#!r6rs
;;; (chez-sqlite3 private connection): a connection to a database, opened,
;;; owned and closed (ADR-0010, ADR-0012). (chez-sqlite3) exports its two
;;; public procedures, close-database! and database?, the counters and
;;; interrupt-database!; call-with-open-handle, the one way to a connection's
;;; handle, and check-database-owner are the statement tier's, with the
;;; tracking procedures below; failure-details, first-finalize-failure and
;;; interrupt-database/with are exported for the suites too.
;;;
;;; The open verbs, open-database and call-with-database, are (chez-sqlite3
;;; private open)'s: their settings run statements through (chez-sqlite3
;;; private statement), which imports this library, so this one cannot
;;; (ADR-0018). Their parts are here and exported to it:
;;; prepared-open, the checks of a filename and its options;
;;; connection-outcome, the open's one critical section; opened-database, its
;;; outcome raised; and close-connection, the close for a who.
;;;
;;; A connection is a database record, opaque and sealed, holding the
;;; sqlite3* as an integer, so Valgrind sees one never closed, and the
;;; get-thread-id of the thread that opened it. The handle field is #f once
;;; closed. No accessor of it escapes this library but call-with-open-handle,
;;; which checks first (ADR-0012).
;;;
;;; Every verb checks, in order, that its argument is a database, that it runs
;;; on the owning thread, and that the connection is open, before anything
;;; reaches C (ADR-0012). close-database! does the first two, and on a closed
;;; connection does nothing.
;;;
;;; The handle is read out of the record, used by each native call, and the
;;; record and the connection count changed, all in one critical section, and
;;; anything raised is raised after it, from the data it returns. An engine
;;; can preempt between any two calls, and two engines on one thread may share
;;; a connection: a check made outside the section, then a switch, then the
;;; other's close, would hand C a freed address. A __collect_safe call
;;; inside critical-section lets other threads collect (ADR-0011), so
;;; sqlite3_open_v2 and sqlite3_close run there too.
;;;
;;; Nothing raises inside a section, nor inside call-with-database's critical
;;; after thunk. A raise there would reach a with-exception-handler handler
;;; with interrupts still disabled, where an engine never expires and another
;;; thread's collection waits for the handler. So each answers data, and the
;;; raise follows it. A raise from a call made inside one, the open's string
;;; helpers, count-down! or call-with-open-handle's procedure, is caught there
;;; and raised again after it, the same object. The open's section holds the
;;; filename's whole C string, so no engine's expiry unwinds the string's
;;; block and finds it freed on resuming: a program under engines takes
;;; open-database (ADR-0012).
;;;
;;;   the count   up when sqlite3_open_v2 hands back a handle, failed or not;
;;;               down when sqlite3_close answers SQLITE_OK (ADR-0012)
;;;   a failure   its extended code and message read from its handle, then
;;;               the handle closed, then &sqlite-error raised; a NULL handle
;;;               takes its message from sqlite3_errstr
;;;   the close   every statement the connection tracks is finalized, oldest
;;;               first, keeping the first failure a finalize reported
;;;               (ADR-0014). Then sqlite3_close, never sqlite3_close_v2. Once
;;;               it is closed, the first finalize failure is raised. The
;;;               close vouches only for the statements it tracks, and judges
;;;               none it did not make. An answer but SQLITE_OK means
;;;               something else left work open on the connection, a
;;;               statement, a blob or a backup: a defect of chez-sqlite3's,
;;;               or foreign code's, such as a loaded extension's. The
;;;               connection stays open and counted, and only then does
;;;               sqlite3_next_stmt count what is left, as a diagnostic: one
;;;               or more, an assertion violation naming the count; none, a
;;;               backup's, sqlite3_close's own &sqlite-error. The count names
;;;               every statement left, SQLite's own among them: a virtual
;;;               table's module, FTS3's, FTS4's, FTS5's or RTREE's, keeps
;;;               statements on the connection, which sqlite3_close finalizes
;;;               as it disconnects the table, before it looks for statements,
;;;               but not for a table a statement left open still holds.
;;;               sqlite3_close has by then also rolled back each virtual
;;;               table a transaction wrote, which is the other work's affair,
;;;               not the library's
;;;
;;; A connection tracks its live statements (ADR-0012; ADR-0014).
;;; (chez-sqlite3 private statement) makes them and imports this library, so
;;; this one cannot name a statement's record: it holds, for each, an entry
;;; that statement.sls made, and track-statement!, untrack-statement! and
;;; tracked-statements are its private procedures for them.
;;;
;;; Every refusal of a caller's mistake is an assertion violation whose
;;; irritants begin with a symbol naming its rule, then the value by
;;; shown-value, never a string's text (ADR-0013).
;;;
;;; The library also holds (ADR-0016; ADR-0020; ADR-0012; ADR-0021):
;;;
;;;   the cache      the record holds its statement cache, statement-cache.sls's
;;;                  table, its capacity fixed when the record is made: the one
;;;                  connection-outcome is given, the settings' statement-cache,
;;;                  0 to 1024, 32 when they give none (ADR-0018; ADR-0020). The
;;;                  database-cache procedures read and change it inside a
;;;                  verb's critical section, for (chez-sqlite3 private
;;;                  statement)'s check-out and return; the close empties it,
;;;                  whether or not the connection closes
;;;   the counters   changes, total-changes, last-insert-rowid and
;;;                  in-transaction?, each one plain call through
;;;                  call-with-open-handle, which makes every verb's checks
;;;                  first
;;;   the interrupt  the record holds its latch, a mutex and an
;;;                  interruptible flag ((chez-sqlite3 private interrupt);
;;;                  ADR-0019). connection-outcome's section sets the flag
;;;                  once the record exists; close-connection runs its work
;;;                  through interrupt-latch-close!, which clears it before
;;;                  the first finalize and sets it again when the work left
;;;                  the connection open: sqlite3_close failing, with a
;;;                  statement found untracked or none. interrupt-database! is
;;;                  the one verb another thread may call: it checks only that
;;;                  its argument is a database, and calls sqlite3_interrupt
;;;                  through the latch, holding its mutex, while the flag is
;;;                  set; the call itself is made inside the latch, never
;;;                  after it returns. Its work is interrupt-database/with's,
;;;                  which takes the foreign call, so the suites run it on a
;;;                  stand-in. It lives here because the record and its handle
;;;                  do, and the handle's one accessor, call-with-open-handle,
;;;                  makes the owner check this verb must not (ADR-0012;
;;;                  ADR-0010). call-with-latch-shut runs with-transaction's
;;;                  exits through interrupt-latch-shut!, which clears the
;;;                  flag around them and puts it back after
;;;   the opt-in     the record holds the connection's opt-in to extension
;;;                  loading, fixed when it is made, as the cache's capacity
;;;                  is: connection-outcome is given it, from the settings'
;;;                  plan, whether its steps hold
;;;                  (enable-load-extension . #t)'s. database-extension-loading?
;;;                  reads it, for the suites and for load-extension!, which
;;;                  reads it last of its checks. A set that fails closes the
;;;                  connection, so no caller holds a record whose opt-in the
;;;                  C call lacks
(library (chez-sqlite3 private connection)
  (export close-database! database?
          prepared-open connection-outcome opened-database close-connection
          call-with-open-handle failure-details check-database-owner
          track-statement! untrack-statement! tracked-statements first-finalize-failure
          database-cache-capacity database-cache-count database-extension-loading?
          database-cache-check-out! database-cache-return!
          changes total-changes last-insert-rowid in-transaction?
          interrupt-database! interrupt-database/with call-with-latch-shut
          database-depth set-database-depth!)
  (import (chez-sqlite3 private require-threaded)
          (except (rnrs) dynamic-wind)
          (only (chezscheme) critical-section dynamic-wind get-thread-id)
          (chez-sqlite3 private native)
          (chez-sqlite3 private counters)
          (only (chez-sqlite3 private constants) sqlite-open-uri sqlite-result-codes)
          (chez-sqlite3 private conditions)
          (chez-sqlite3 private open-options)
          (chez-sqlite3 private statement-cache)
          (chez-sqlite3 private interrupt))

  (define sqlite-ok (cdr (assq 'ok sqlite-result-codes)))

  ;; database? : Any -> Boolean
  ;; Opaque, so record-rtd on a database raises, and sealed, so no type
  ;; extends it; not nongenerative, so no other definition makes its type.
  ;; LIVE is the statements it tracks, an eq-hashtable from each statement to
  ;; its entry; SERIAL the number the next one tracked takes, so the close
  ;; can finalize them oldest first. CACHE is its statement cache, of the
  ;; capacity the record is made with, which never changes (ADR-0020). DEPTH
  ;; is how many with-transaction levels are open on it, from 0 (ADR-0017).
  ;; LATCH is its interrupt latch, made not interruptible: the open sets it,
  ;; in its section (ADR-0019). OPT-IN is whether it opted in to extension
  ;; loading, #t or #f, fixed when it is made, as CACHE's capacity is
  ;; (ADR-0012).
  (define-record-type database
    (fields (mutable handle unchecked-database-handle set-database-handle!)
            (immutable owner unchecked-database-owner)
            (immutable live unchecked-database-live)
            (mutable serial unchecked-database-serial set-database-serial!)
            (immutable cache unchecked-database-cache)
            (mutable depth unchecked-database-depth set-unchecked-database-depth!)
            (immutable latch unchecked-database-latch)
            (immutable opt-in unchecked-database-opt-in))
    (protocol (lambda (new)
                (lambda (handle owner capacity opt-in)
                  (new handle owner (make-eq-hashtable) 0 (make-statement-cache capacity) 0
                       (make-interrupt-latch) (and opt-in #t)))))
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

  ;; check-database-owner : Symbol Any -> Void
  ;; check-owned, for a verb that makes its own checks of other arguments
  ;; between these two and call-with-open-handle's open check, as
  ;; prepare-statement checks its SQL. It hands over no handle, and raises
  ;; outside any section: neither a database's type nor its owner can change.
  ;; The calling thread can, when an engine's remainder is resumed on
  ;; another, so it orders the refusals and guards nothing:
  ;; call-with-open-handle checks the owner again inside its section.
  (define (check-database-owner who db)
    (check-who 'check-database-owner who)
    (check-owned who db))

  ;; call-with-open-handle : Symbol Any (Positive-Integer -> A ...) -> A ...
  ;; PROC's answers, given DB's handle, once DB is checked: a database, else
  ;; an assertion violation from WHO; on its owning thread, else
  ;; &sqlite-wrong-thread from WHO; open, else &sqlite-closed from WHO. A WHO
  ;; that is no symbol and a PROC that is no procedure are assertion
  ;; violations first.
  ;;
  ;; The first two checks come before the critical section, so a wrong
  ;; thread is refused before anything else is touched. The owner check is
  ;; made again inside the section, first, with the thread id read there:
  ;; Chez resumes an engine's remainder on whichever thread calls it, so a
  ;; call that passed the first check on the owner's thread, then expired, can
  ;; go on on another. There the section answers (wrong-thread OWNER CALLER),
  ;; touching nothing, and &sqlite-wrong-thread is raised from WHO after it,
  ;; the procedure the caller called, whatever state the connection is in, as
  ;; the first check does. The open check and PROC run in the section after
  ;; it, so the handle cannot be closed, nor the thread change, between the
  ;; checks and its use. PROC runs with interrupts disabled, so it keeps to
  ;; the C call and its reads, and answers data: what it raises is caught in
  ;; the section and raised again after it, the same object, with raise. So a
  ;; raise-continuable from PROC cannot be resumed.
  ;;
  ;; The section sits in a plain dynamic-wind, as call-with-block's extent
  ;; does: a continuation captured in PROC and re-entered once the call has
  ;; its outcome would run PROC again with a handle that may be freed, so the
  ;; before thunk refuses a re-entry, from WHO, outside any section. FINISHED
  ;; is set once the section is over and its outcome in hand, never by an
  ;; after thunk: an engine's expiry before that unwinds the wind and its
  ;; resume enters it again, and must go on.
  ;; A few instructions lie between FINISHED's set! and the wind's exit.
  ;; An expiry there would make its resume refused, re-entered: harmless,
  ;; the section's work done, and the refused run touching nothing. None was
  ;; seen there in a measurement: no engine over fuel 1 to 3000, 20 calls
  ;; each, nor a timer's handler over 2804 trials re-entering execute-script!;
  ;; the 212 to 218 refused as re-entered had taken theirs inside the wind
  ;; before the section, the re-entry this before thunk exists to refuse.
  (define (call-with-open-handle who db proc)
    (check-who 'call-with-open-handle who)
    (unless (procedure? proc)
      (assertion-violation who "not a procedure" 'not-a-procedure (shown-value proc)))
    (check-owned who db)
    (let* ((finished #f)
           (outcome
            (dynamic-wind
              (lambda ()
                (when finished
                  (assertion-violation who "re-entered after it finished" 're-entered)))
              (lambda ()
                (let ((outcome
                       (critical-section
                        (let ((owner (unchecked-database-owner db))
                              (caller (get-thread-id))
                              (handle (unchecked-database-handle db)))
                          (cond ((not (eqv? owner caller)) (list 'wrong-thread owner caller))
                                ((not handle) '(closed))
                                (else
                                 (guard (c (#t (list 'raised c)))
                                   (call-with-values (lambda () (proc handle))
                                     (lambda answers (cons 'answered answers))))))))))
                  (set! finished #t)
                  outcome))
              (lambda () #f))))
      (case (car outcome)
        ((answered) (apply values (cdr outcome)))
        ((closed) (raise-closed who))
        ((wrong-thread) (raise-wrong-thread who (cadr outcome) (caddr outcome)))
        (else (raise (cadr outcome))))))

  ;; --- the statements a connection tracks ------------------------------------------------
  ;;
  ;; An entry is a statement's record, as KEY, and FINALIZE, a procedure that
  ;; (chez-sqlite3 private statement) made for it when it was prepared:
  ;;
  ;;   FINALIZE : Positive-Integer -> Finalize-Outcome
  ;;   Finalize-Outcome = (U 'finalized
  ;;                         (List 'failed Integer String String)
  ;;                         (List 'raised Any))
  ;;
  ;; Given the connection's handle, inside the close's critical section, it
  ;; finalizes the statement, clears its handle, makes it finalized and counts
  ;; it down, whatever sqlite3_finalize answers, and answers data, raising
  ;; nothing: finalized; or (failed CODE MESSAGE SQL) for a failure of the
  ;; finalize's own, CODE its answer, MESSAGE sqlite3_errmsg read straight
  ;; after it, SQL the statement's; or (raised C) for what a call inside it
  ;; raised, count-down!'s double free. A statement already finalized answers
  ;; finalized, and reaches no C.
  ;;
  ;; Why a procedure: statement.sls imports this library, so this one cannot
  ;; import it, nor name the statement record's fields. The procedure closes
  ;; over the record and carries the statement's own finalize with it, so the
  ;; close needs no accessor of a statement, and a statement's handle has one
  ;; accessor still, in statement.sls. Why the record as KEY: untracking and
  ;; tracked-statements find it by eq?, and a record of an opaque type cannot
  ;; be forged. Each entry also takes the database's next serial number, so
  ;; the close finalizes oldest first (ADR-0014) with an O(1) add and remove.
  ;;
  ;; Each procedure here is called inside the critical section of the verb
  ;; that prepares, finalizes or closes, with the connection's handle in hand,
  ;; so it reads and changes the table with interrupts off; none raises for a
  ;; database, which is all a caller gives it.

  ;; track-statement! : Database Any (Positive-Integer -> Finalize-Outcome) -> Boolean
  ;; KEY tracked by DB, newest, with FINALIZE: #t; #f, tracking nothing, for a
  ;; DB that is no database. Raises nothing.
  (define (track-statement! db key finalize)
    (and (database? db)
         (let ((serial (unchecked-database-serial db)))
           (set-database-serial! db (+ serial 1))
           (hashtable-set! (unchecked-database-live db) key (cons serial finalize))
           #t)))

  ;; untrack-statement! : Database Any -> Boolean
  ;; KEY no longer tracked by DB: #t when it was; #f when it was not, or DB is
  ;; no database. Raises nothing.
  (define (untrack-statement! db key)
    (and (database? db)
         (let ((live (unchecked-database-live db)))
           (and (hashtable-contains? live key)
                (begin (hashtable-delete! live key) #t)))))

  ;; entries-oldest-first : Database -> (Listof (Pairof Any (Pairof Natural Procedure)))
  ;; DB's entries, each (KEY SERIAL . FINALIZE), oldest first.
  (define (entries-oldest-first db)
    (let-values (((keys entries) (hashtable-entries (unchecked-database-live db))))
      (list-sort (lambda (a b) (< (cadr a) (cadr b)))
                 (map cons (vector->list keys) (vector->list entries)))))

  ;; tracked-statements : Database -> (Listof Any)
  ;; The statements DB tracks, oldest first, read in one critical section.
  ;; DB checked by check-owned first, from tracked-statements. For the
  ;; suites, and for with-transaction.
  (define (tracked-statements db)
    (check-owned 'tracked-statements db)
    (critical-section (map car (entries-oldest-first db))))

  ;; first-finalize-failure : (Listof Finalize-Outcome) -> (U Finalize-Outcome #f)
  ;; The first of OUTCOMES that is not finalized, in their order; #f when
  ;; every one is. Pure and total.
  (define (first-finalize-failure outcomes)
    (cond ((null? outcomes) #f)
          ((eq? (car outcomes) 'finalized) (first-finalize-failure (cdr outcomes)))
          (else (car outcomes))))

  ;; finalize-tracked! : Database Positive-Integer -> (U Finalize-Outcome #f)
  ;; Every statement DB tracks finalized, oldest first, each by its entry's
  ;; FINALIZE given HANDLE, and none tracked after: the first failure any
  ;; reported, or #f. Called inside the close's critical section; it raises
  ;; nothing, a FINALIZE that raised counting as (raised C).
  (define (finalize-tracked! db handle)
    (let ((entries (entries-oldest-first db)))
      (hashtable-clear! (unchecked-database-live db))
      (let loop ((rest entries) (outcomes '()))
        (if (null? rest)
            (first-finalize-failure (reverse outcomes))
            (let ((outcome (guard (c (#t (list 'raised c)))
                             ((cddr (car rest)) handle))))
              (loop (cdr rest) (cons outcome outcomes)))))))

  ;; --- the statement cache (ADR-0020) ---------------------------------------------------
  ;;
  ;; The record's table holds statements as opaque values, keyed by the SQL's
  ;; exact text, a string its caller has checked and copied. Check-out and
  ;; return are called inside the critical section of the verb that makes
  ;; them, in call-with-open-handle's, with the connection checked open, so
  ;; they read and change the table with interrupts off; neither raises for a
  ;; database and a string key, and each answers what statement-cache.sls's
  ;; table answers. The caller finalizes what a return answers, after its
  ;; section.

  ;; database-cache-check-out! : Database String -> (U (List 'hit Any) (List 'miss))
  ;; The statement DB's cache holds under KEY, removed from it, as (hit S);
  ;; (miss) when it holds none, or DB is no database. Raises nothing.
  (define (database-cache-check-out! db key)
    (if (database? db)
        (statement-cache-check-out! (unchecked-database-cache db) key)
        '(miss)))

  ;; database-cache-return! : Database String Any -> (Listof Any)
  ;; STATEMENT filed under KEY as DB's cache's most recent: what to finalize,
  ;; by the cache's table, the evicted one, or STATEMENT itself at a capacity
  ;; of 0 or when the cache holds KEY already; (STATEMENT) when DB is no
  ;; database. Raises nothing.
  (define (database-cache-return! db key statement)
    (if (database? db)
        (statement-cache-return! (unchecked-database-cache db) key statement)
        (list statement)))

  ;; database-cache-capacity : Database -> Natural
  ;; The most statements DB's cache holds, fixed when DB was opened. DB
  ;; checked by check-owned first, from database-cache-capacity.
  (define (database-cache-capacity db)
    (check-owned 'database-cache-capacity db)
    (statement-cache-capacity (unchecked-database-cache db)))

  ;; database-extension-loading? : (case-> (Database -> Boolean) (Symbol Database -> Boolean))
  ;; Whether DB opted in to extension loading at open: its settings list
  ;; held (enable-load-extension . #t), so its plan held the opt-in's step,
  ;; and that set matched; #f for its #f, which makes no call, and for no
  ;; setting (ADR-0021). Fixed when the record was made, read whether DB is
  ;; open or closed. DB checked by check-owned first, as
  ;; database-cache-capacity is: from WHO when it is given, else from
  ;; database-extension-loading?. A WHO that is no symbol is an assertion
  ;; violation first. For the suites, and, with its WHO, for load-extension!,
  ;; which reads it last of its checks. A remainder of that call can be
  ;; resumed on another thread after its first checks, so this read's own
  ;; owner check refuses it there, and names the verb the caller called
  ;; (ADR-0013).
  (define database-extension-loading?
    (case-lambda
      ((db) (database-extension-loading? 'database-extension-loading? db))
      ((who db)
       (check-who 'database-extension-loading? who)
       (check-owned who db)
       (unchecked-database-opt-in db))))

  ;; database-cache-count : Database -> Natural
  ;; How many statements DB's cache holds now, read in one critical section;
  ;; 0 once DB is closed. DB checked by check-owned first, from
  ;; database-cache-count. For the suites.
  (define (database-cache-count db)
    (check-owned 'database-cache-count db)
    (critical-section (statement-cache-count (unchecked-database-cache db))))

  ;; --- the transaction depth (ADR-0017) ------------------------------------------------
  ;;
  ;; (chez-sqlite3 private transaction) reads and changes it inside its own
  ;; critical sections, on the owner's thread: neither procedure raises.

  ;; database-depth : Any -> Natural
  ;; How many with-transaction levels are open on DB, which names the next
  ;; savepoint; 0 when DB is no database.
  (define (database-depth db)
    (if (database? db) (unchecked-database-depth db) 0))

  ;; set-database-depth! : Any Natural -> Boolean
  ;; DB's depth made N: #t; #f, changing nothing, for a DB that is no
  ;; database.
  (define (set-database-depth! db n)
    (and (database? db)
         (begin (set-unchecked-database-depth! db n) #t)))

  ;; raise-finalize-failure : Symbol Finalize-Outcome -> Nothing
  ;; OUTCOME, a failure, raised from WHO: (failed CODE MESSAGE SQL) as an
  ;; &sqlite-error carrying SQL and no offset, (raised C) as C itself.
  (define (raise-finalize-failure who outcome)
    (if (eq? (car outcome) 'failed)
        (raise-sqlite-error who (cadr outcome) (caddr outcome) (cadddr outcome) #f)
        (raise (cadr outcome))))

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
  ;; (ADR-0011). OPTIONS are the options alone, the settings list split from
  ;; them (chez-sqlite3 private open).
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

  ;; connection-outcome : Symbol String Natural Natural Boolean (U (-> Any) #f)
  ;;                -> (U (List 'opened Database) (List 'failed Integer String)
  ;;                      (List 'raised Any) (List 'refused))
  ;; NAME, a checked copy, opened with FLAGS and owned by this thread, its
  ;; cache of CAPACITY and its opt-in OPT-IN, checked: the database; or the
  ;; failure's extended code and message, its handle closed; or what a call
  ;; raised, call-with-c-string's refusal of U+0000, from WHO before anything is
  ;; allocated, among them. One critical section holds the C string's whole
  ;; extent: the open, the read of its out-pointer, the count, the record
  ;; and its latch made interruptible (ADR-0019), or else the failure's
  ;; details and its handle's close. So no handle is ever left uncounted, and
  ;; no engine's expiry frees the string between the open's calls. It raises
  ;; nothing.
  ;;
  ;; REFUSED?, the open's claim on its call, a procedure of no arguments or
  ;; #f for none, is evaluated first in the section: when it answers true,
  ;; another run of the same call has made its open already, and the section
  ;; opens nothing and answers refused. So of the runs an engine's multi-shot
  ;; remainder makes, or a continuation a timer's handler took, one alone
  ;; opens: none opens a connection that nothing would return or close
  ;; ((chez-sqlite3 private open); ADR-0018).
  (define (connection-outcome who name flags capacity opt-in refused?)
    (critical-section
     (if (and refused? (refused?))
         '(refused)
         (guard (c (#t (list 'raised c)))
           (call-with-c-string who name
             (lambda (c-name)
               (let-values (((rc handle)
                             (call-with-out-pointer who
                               (lambda (slot) (sqlite3-open-v2 c-name slot flags 0)))))
                 (cond
                   ((eqv? handle 0) (cons 'failed (details-of rc 0)))
                   (else
                    (count-up! 'connection)
                    (if (eqv? rc sqlite-ok)
                        (let ((db (make-database handle (get-thread-id) capacity opt-in)))
                          (interrupt-latch-open! (unchecked-database-latch db))
                          (list 'opened db))
                        (let ((details (details-of rc handle)))
                          (when (eqv? (sqlite3-close handle) sqlite-ok)
                            (count-down! 'connection))
                          (cons 'failed details))))))))))))

  ;; opened-database : Symbol (U (List 'opened Database) (List 'failed Integer String)
  ;;                             (List 'raised Any) (List 'refused)) -> Database
  ;; OUTCOME's database; or its failure, &sqlite-error from WHO; or what it
  ;; caught, raised again; or, for refused, &sqlite-closed from WHO. Called
  ;; after the section that made OUTCOME.
  (define (opened-database who outcome)
    (case (car outcome)
      ((opened) (cadr outcome))
      ((failed) (raise-sqlite-error who (cadr outcome) (caddr outcome) #f #f))
      ((refused) (raise-closed who))
      (else (raise (cadr outcome)))))

  ;; --- closing -----------------------------------------------------------------------------

  ;; statements-on : Positive-Integer -> Natural
  ;; How many statements sqlite3_next_stmt finds on HANDLE.
  (define (statements-on handle)
    (let loop ((statement (sqlite3-next-stmt handle 0)) (n 0))
      (if (eqv? statement 0)
          n
          (loop (sqlite3-next-stmt handle statement) (+ n 1)))))

  ;; close-left-open? : (Pairof Symbol Any) -> Boolean
  ;; Whether a close's OUTCOME, as close-connection's work answers it, left
  ;; the connection open: sqlite3_close failing, with a statement found
  ;; untracked after it, or none (ADR-0019). Raises nothing.
  (define (close-left-open? outcome)
    (and (memq (car outcome) '(untracked failed)) #t))

  ;; close-connection : Symbol Any -> Void
  ;; DB closed, for WHO; nothing when it is closed already: close-database!'s
  ;; work, and (chez-sqlite3 private open)'s close of a connection whose
  ;; settings failed, or whose call-with-database ends. In
  ;; interrupt-latch-close!'s one critical section: DB's latch made not
  ;; interruptible, holding its mutex, before anything is finalized, so no
  ;; interrupt is in flight once the work starts and none starts after
  ;; (ADR-0019); then the work, with the mutex released: every tracked
  ;; statement finalized, oldest first, the first failure kept; the cache
  ;; emptied, its statements among those finalized, whether or not the
  ;; connection then closes, so it never holds a freed one (ADR-0020);
  ;; sqlite3_close; on SQLITE_OK, the handle cleared and the count down; on
  ;; any other answer, the connection left open and counted, and only then
  ;; sqlite3_next_stmt's count of the statements left on it, and the latch
  ;; made interruptible again. sqlite3_close comes before the count because it
  ;; disconnects every virtual table first, finalizing the statements a module
  ;; such as FTS5 keeps on the connection, which a count before it would find
  ;; as untracked. The close judges no statement it did not make: a refusal
  ;; means work something else left open, a defect of chez-sqlite3's or
  ;; foreign code's, and the count is a diagnostic of every statement left, a
  ;; module's among them while a leftover statement holds its table. After it,
  ;; by what the work answered:
  ;; with sqlite3_close failed, a statement found untracked, an assertion
  ;; violation naming the count, or with none, sqlite3_close's failure,
  ;; each raised in place of a finalize's failure, with the connection open
  ;; and counted; else, the connection closed, the first finalize failure,
  ;; then a count-down that found the count at zero, count-down!'s double
  ;; free. The work raises nothing.
  ;;
  ;; The owner is checked twice, as call-with-open-handle checks it: by
  ;; check-owned first, so the refusals keep their order, and again in a
  ;; critical section around interrupt-latch-close!'s, with the thread id
  ;; read there, before the latch is touched. Chez resumes an engine's
  ;; remainder on whichever thread calls it, so a close that passed the
  ;; first check on the owner's thread could otherwise finalize and close on
  ;; another. There the section answers (wrong-thread OWNER CALLER), touching
  ;; nothing, and &sqlite-wrong-thread is raised from WHO after it. What
  ;; interrupt-latch-close! raises after its own section, only what the work
  ;; raised, is caught in this one and raised again after it.
  (define (close-connection who db)
    (check-owned who db)
    (let ((outcome
           (critical-section
            (let ((owner (unchecked-database-owner db))
                  (caller (get-thread-id)))
              (if (not (eqv? owner caller))
                  (list 'wrong-thread owner caller)
                  (guard (c (#t (list 'raised c)))
                    (interrupt-latch-close!
                     (unchecked-database-latch db)
                     (lambda ()
                       (let ((handle (unchecked-database-handle db)))
                         (if (not handle)
                             '(already-closed)
                             (let* ((failure (finalize-tracked! db handle))
                                    (emptied (statement-cache-clear! (unchecked-database-cache db)))
                                    (rc (sqlite3-close handle)))
                               (if (eqv? rc sqlite-ok)
                                   (begin
                                     (set-database-handle! db #f)
                                     (let ((double-free (guard (c (#t c))
                                                          (count-down! 'connection)
                                                          #f)))
                                       (cond (failure (list 'finalize-failed failure))
                                             (double-free (list 'double-free double-free))
                                             (else '(closed)))))
                                   (let ((untracked (statements-on handle)))
                                     (if (> untracked 0)
                                         (list 'untracked untracked)
                                         (cons 'failed (details-of rc handle)))))))))
                     close-left-open?)))))))
      (case (car outcome)
        ((wrong-thread) (raise-wrong-thread who (cadr outcome) (caddr outcome)))
        ((raised) (raise (cadr outcome)))
        ((untracked)
         (assertion-violation who "the connection has statements chez-sqlite3 does not track"
                              'untracked-statements (cadr outcome)))
        ((failed) (raise-sqlite-error who (cadr outcome) (caddr outcome) #f #f))
        ((finalize-failed) (raise-finalize-failure who (cadr outcome)))
        ((double-free) (raise (cadr outcome)))
        (else (if #f #f)))))

  ;; close-database! : Database -> Void
  ;; DB closed, every statement it tracks finalized first, oldest first; then
  ;; the first failure a finalize reported, raised with DB closed. Nothing
  ;; when it is closed already. From another thread, &sqlite-wrong-thread,
  ;; closed or not.
  (define (close-database! db)
    (close-connection 'close-database! db))

  ;; --- the interrupt (ADR-0019) ------------------------------------------------------------

  ;; interrupt-database! : Database -> Void
  ;; Any thread's: DB's running statement, a step or a prepare, made to
  ;; answer SQLITE_INTERRUPT, and one held at a row with it, by
  ;; sqlite3_interrupt (ADR-0019). DB that is no database is an assertion
  ;; violation; there is no owner check, and no other: on a closed connection,
  ;; or one closing, it does nothing and raises nothing. The handle is read
  ;; and sqlite3_interrupt called by interrupt-latch-interrupt!, in its one
  ;; critical section, holding DB's latch's mutex, and only while the latch is
  ;; interruptible, which the close clears under the same mutex before it
  ;; finalizes anything. So the flag being set means the handle is live. It
  ;; reads nothing else of the connection, since any call that takes the
  ;; connection's own mutex waits for the step it means to stop, and answers
  ;; nothing. It is interrupt-database/with, given sqlite3_interrupt.
  (define (interrupt-database! db)
    (interrupt-database/with db sqlite3-interrupt))

  ;; interrupt-database/with : Database (Positive-Integer -> Any) -> Void
  ;; interrupt-database!'s work, with its foreign call INTERRUPT given, so a
  ;; suite runs the record's own wiring on a stand-in, as test-interrupt runs
  ;; the latch's (ADR-0019). DB that is no database is an assertion violation
  ;; from interrupt-database!. Then, inside interrupt-latch-interrupt!'s one
  ;; critical section, holding DB's latch's mutex and only while the latch is
  ;; interruptible: DB's handle read, and INTERRUPT called with it, its answer
  ;; dropped. Both stay inside: a call made after the latch returns could be
  ;; stopped between the two, by an engine's expiry or by another thread, and
  ;; made after a close had freed the connection. A raise from INTERRUPT is
  ;; raised after the section, the same object. Answers nothing. For the
  ;; suites; (chez-sqlite3) exports only interrupt-database!.
  (define (interrupt-database/with db interrupt)
    (unless (database? db)
      (assertion-violation 'interrupt-database! "not a database" 'not-a-database
                           (shown-value db)))
    (interrupt-latch-interrupt! (unchecked-database-latch db)
                                (lambda () (interrupt (unchecked-database-handle db))))
    (if #f #f))

  ;; call-with-latch-shut : Database (-> A) -> A
  ;; WORK's answer, run with DB's interrupt latch shut by
  ;; interrupt-latch-shut!: in one critical section, the flag cleared
  ;; holding the latch's mutex, WORK with the mutex released, then the flag
  ;; put back as it was found. So interrupt-database!, from any thread,
  ;; calls nothing while WORK runs, and one in flight as the shut begins
  ;; ends first. WORK is with-transaction's ROLLBACK, or ROLLBACK TO then
  ;; RELEASE, which answers data; a raise from it is raised after the
  ;; section, the same object, with the flag put back. DB is a database,
  ;; checked by with-transaction; for any other value WORK runs with nothing
  ;; shut. No other check: it is private.
  (define (call-with-latch-shut db work)
    (if (database? db)
        (interrupt-latch-shut! (unchecked-database-latch db) work)
        (work)))

  ;; --- the counters (ADR-0016) ---------------------------------------------------------------
  ;;
  ;; Each checks DB as every verb does, a database, on its owning thread, and
  ;; open, through call-with-open-handle, and makes its one plain call there:
  ;; the counters are SQLite's, read as it keeps them.

  ;; changes : Database -> Natural
  ;; The rows the last INSERT, UPDATE or DELETE on DB to finish changed,
  ;; sqlite3_changes64's answer: a trigger's own rows are not counted, and
  ;; DDL, SELECT, PRAGMA, BEGIN and COMMIT leave it as it was.
  (define (changes db)
    (call-with-open-handle 'changes db (lambda (handle) (sqlite3-changes64 handle))))

  ;; total-changes : Database -> Natural
  ;; The rows every INSERT, UPDATE and DELETE on DB has changed since it
  ;; opened, sqlite3_total_changes64's answer: triggers' and cascades' rows
  ;; among them, and rows a rollback undid.
  (define (total-changes db)
    (call-with-open-handle 'total-changes db (lambda (handle) (sqlite3-total-changes64 handle))))

  ;; last-insert-rowid : Database -> Integer
  ;; The rowid of the last row an INSERT on DB made, sqlite3_last_insert_rowid's
  ;; answer: it can name a row a failure or a rollback undid, and a WITHOUT
  ;; ROWID table's insert or an upsert's DO UPDATE leaves it as it was.
  (define (last-insert-rowid db)
    (call-with-open-handle 'last-insert-rowid db (lambda (handle) (sqlite3-last-insert-rowid handle))))

  ;; in-transaction? : Database -> Boolean
  ;; Whether DB is inside a transaction, sqlite3_get_autocommit answering 0:
  ;; #t after a deferred BEGIN that has read nothing, and #f while an
  ;; autocommit SELECT holds a read.
  (define (in-transaction? db)
    (call-with-open-handle 'in-transaction? db
      (lambda (handle) (eqv? (sqlite3-get-autocommit handle) 0)))))
