#!r6rs
;;; (conveniences-pending): what the suites for one convenience's runs
;;; interleaved share, tests/test-conveniences-pending-execute.sps, -query.sps,
;;; -query-row.sps, -fold.sps and -script.sps, one a convenience, so each
;;; stays well under the memory gate's limit (ADR-0005, amended; ADR-0016,
;;; amended in M3 slice 5's part D; the maintainer's "Guard every call",
;;; ADR-0016, amended in M3 slice 3). Chez's engine remainders are multi-shot:
;;; R, one remainder of a call, resumed until it expires again, is R1, and R
;;; can then be resumed again while R1 is pending. Each run of the call goes
;;; on from where its remainder was taken.
;;;
;;; The schedule, the lead's (build/verify-d/pending-sweep.sps), each trial
;;; on a fresh :memory: connection holding t, its rows 1, 2 and 3, made
;;; through the statement tier, so the cache starts empty and the call's SQL
;;; is a miss:
;;;   - at fuel F, a fresh engine's remainder R;
;;;   - R resumed at G until it expires again, as R1;
;;;   - R resumed again to its end, then R1 to its end;
;;;   - G from 1 until R completes within G, where R is resumed once more
;;;     instead; F from 1 until the call completes unexpired.
;;; After every trial:
;;;   - each run answers the call's answer, or &sqlite-closed from the verb;
;;;     query-fold and execute-script!, which do not survive a preemption,
;;;     may also meet a library wind's refusal of a re-entry;
;;;   - the call made its statement once: SQLite's authorizer saw its SQL
;;;     prepared once, or, for the script, each statement at most once;
;;;   - its effect came once: execute!'s row inserted once, the script's rows
;;;     a prefix of its own, none twice;
;;;   - no statement is tracked outside the cache, and none is at a row;
;;;   - the cache holds what one clean call leaves: the call's statement,
;;;     ready, for the four that use it, or, for query-fold, nothing, where
;;;     an expiry inside its wind finalized it; for the script, nothing;
;;;   - once the connection is closed, every count is what it was before.
;;; A remainder taken before the call's first expression, which makes its
;;; claim or its flag, is the caller's own: resumed again, it makes a whole
;;; new call, its statement and its effect a second time. A trial may make
;;; one only at a fuel at which the control makes one (below).
;;;
;;; The tell: sqlite3_auto_extension runs an entry point of this library at
;;; every open, which sets an authorizer on the new connection. SQLite calls
;;; the authorizer at every prepare, never at a cache's check-out, so each
;;; select and each insert prepared is noted, an insert with its table. Both
;;; callbacks are __collect_safe: SQLite calls them inside sqlite3_open_v2 and
;;; sqlite3_prepare_v3, which are. They answer data and raise nothing. A
;;; suite registers them first, through tell-registered, and unregisters
;;; them last, through tell-reset, as tests/test-open-interleave.sps does.
;;; A libsqlite3 can refuse the registration: Apple's 3.51.0 answers 21,
;;; SQLITE_MISUSE, for an entry point upstream takes. With no tell, no
;;; prepare is noted, and nothing is unavailable silently (ADR-0005,
;;; amended): a row whose every check needs the tell, or that raises
;;; SIGINT from the authorizer, goes through tell-available!, which prints
;;; UNAVAILABLE and skips it; a row with one check that reads the notes
;;; goes through tell-kept?, which prints UNAVAILABLE for that check, and
;;; the row runs its others. The gate itself is held by an independent
;;; reading: before the tell registers, tell-direct registers an entry point
;;; that does nothing, straight through the FFI, and resets the list; a row
;;; requires the gate to refuse exactly when that registration answered 21.
;;; A gate forced to refuse passed every suite, printing UNAVAILABLE, with
;;; nothing to say it was wrong (M3's closing review, reviewer B).
;;;
;;; The control: at each fuel, on a connection whose statement cache holds
;;; none, so every call prepares its statement, R is taken and resumed to its
;;; end twice, one after the other. The second makes a whole new call when
;;; the authorizer sees the call's SQL prepared again: a run of the same call
;;; is refused at its next section, or, past its last section, answers again,
;;; and prepares nothing either way. Nothing before a call's first expression
;;; reads the connection, so a remainder lies before it at the same fuels on
;;; both connections. A collect request costs a run up to a tick
;;; (.plans/research/m3-slice-5/, gc-ticks.sps), so each fuel begins with a
;;; collection, collect-trip-bytes raised far above what a fuel's runs
;;; allocate; a trial may make a whole new call where the control made one at
;;; its fuel or the one before, a tick's room besides.
;;;
;;; The control cannot tell a whole new call from the same call run again,
;;; which is what a call that lost its claim or its flag would do. So it is
;;; bounded by what it can tell: a remainder taken past the call's first
;;; expression and before its first section, nothing noted at its expiry,
;;; is refused the second time, &sqlite-closed from the verb, preparing
;;; nothing. Each fuel begins with a collection, so a remainder lies further
;;; into the call at each fuel than at the one before; the control must meet
;;; such a refusal, and every whole new call it makes must come at a fuel
;;; below the first. A claim taken again once its call had ended made the
;;; whole window new calls, and passed the bound slice 5 used, the fuel at
;;; which the call refused at its first check completes, 72 for execute!,
;;; past the whole call's 42 (M3's closing review, reviewer B's N1).
;;;
;;; Which trials count: a trial interleaves when R1 exists. It is past the
;;; first section when the call had made its first section, the check-out's
;;; prepare or the script's first, by the time R1 was taken; both past it
;;; when the call had made it by the time R was taken, so both pending runs
;;; lie inside the call past its first section. A sweep that made too few of
;;; either has reached nothing, and says so by name (the M2 session's guard,
;;; after a sweep that reused one R across every G).
;;;
;;; Three more schedules hold what a raise from the caller's handler does, a
;;; raise inside the call that no section caught: a timer's handler raising
;;; at every tick, for all five, the statement finished each time; for query
;;; and query-row, one that first takes a statement for the call's SQL, the
;;; call's own once it is given back, which the call then leaves alone; and,
;;; for query-row, a keyboard interrupt that comes pending inside the call's
;;; return, the one way to the instructions after its last section, whose
;;; handler takes the statement the return filed. execute!, query and
;;; query-row give their statement back then by a claim of whatever position
;;; is next, unless the call has ended (the conveniences' with-checked-out).
;;;
;;; An engine spends no ticks inside a critical section, so the fuels measure
;;; the Scheme work between a call's sections (.plans/traps.md). The loading
;;; procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them; the foreign bindings come after
;;; the load, in the library's body, each under a guard of its own.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of
;;; its own. Effects run in order, through let* and named lets, never map
;;; (AGENTS.md).
;;;
;;; Test-only: it lives in tests/, which make test puts on Chez's library
;;; path. Its body loads libsqlite3, through eval, when a suite first
;;; references one of its bindings, and binds sqlite3_set_authorizer,
;;; sqlite3_auto_extension, sqlite3_reset_auto_extension, sqlite3_trace_v2 and
;;; C's raise after the load, each under a guard of its own.
(library (conveniences-pending)
  (export public-load tell-direct tell-registered tell-answered? tell-gate-held tell-available!
          tell-kept? tell-noted tell-reset zero-counts clean-call sweep reported timer-sweep
          timer-reported taken-sweep keyboard-in)
  (import (rnrs)
          (rnrs eval)
          (only (srfi :64) test-skip)
          (only (chezscheme) make-engine foreign-procedure foreign-callable
                foreign-callable-entry-point lock-object unlock-object foreign-ref
                collect collect-trip-bytes set-timer timer-interrupt-handler
                keyboard-interrupt-handler foreign-entry?)
          (chez-sqlite3-testing)
          (chez-sqlite3 private counters)
          (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
                sqlite-error-extended-code sqlite-closed?))

  ;; --- reached through eval -----------------------------------------------------------

  ;; public-load : (U 'loaded (List 'raised Any))
  (define public-load
    (guard (e (#t (list 'raised (describe e))))
      (eval '(sqlite-version) (environment '(chez-sqlite3)))
      'loaded))

  ;; reach : (Listof Symbol) Symbol -> Procedure
  (define (reach library name)
    (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
      (eval name (environment library))))

  (define (public name) (reach '(chez-sqlite3) name))
  (define statement-library '(chez-sqlite3 private statement))
  (define connection-library '(chez-sqlite3 private connection))

  (define open-database (public 'open-database))
  (define close-database! (public 'close-database!))
  (define execute! (public 'execute!))
  (define query (public 'query))
  (define query-row (public 'query-row))
  (define query-fold (public 'query-fold))
  (define execute-script! (public 'execute-script!))
  (define prepare-statement (public 'prepare-statement))
  (define finalize-statement! (public 'finalize-statement!))
  (define step! (public 'step!))
  (define column-value (public 'column-value))
  (define bind-all! (public 'bind-all!))
  (define statement-sql (reach statement-library 'statement-sql))
  (define statement-state (reach statement-library 'statement-state))
  (define tracked-statements (reach connection-library 'tracked-statements))
  (define database-cache-count (reach connection-library 'database-cache-count))
  (define checked-out (reach statement-library 'checked-out))
  (define call-with-open-handle (reach connection-library 'call-with-open-handle))
  (define returned (reach statement-library 'returned))

  ;; --- the tell: an authorizer on every connection -------------------------------------

  ;; noted : (Listof (List Integer (U String #f)))
  ;; What the authorizer noted, newest first: each select's and each insert's
  ;; action code, and an insert's table, #f for a select.
  (define noted '())

  ;; note! : (List Integer (U String #f)) -> Void
  (define (note! event) (set! noted (cons event noted)))

  ;; noted-count : (U 'select 'insert) -> Natural
  ;; How many prepares of KIND the authorizer noted since the last clear: an
  ;; insert counts only into t.
  (define (noted-count kind)
    (let loop ((rest noted) (n 0))
      (if (null? rest)
          n
          (loop (cdr rest)
                (if (if (eq? kind 'select)
                        (eqv? (car (car rest)) sqlite-select)
                        (and (eqv? (car (car rest)) sqlite-insert) (equal? (cadr (car rest)) "t")))
                    (+ n 1)
                    n)))))

  (define (clear-notes!) (set! noted '()))

  ;; c-raise : (U (Integer -> Integer) #f)
  ;; C's int raise(int sig), or #f when missing, so a callback never calls a
  ;; procedure that raises, and the keyboard rows fail instead.
  (define c-raise
    (guard (e (#t #f))
      (and (foreign-entry? "raise") (foreign-procedure "raise" (int) int))))

  ;; sigint : Integer
  ;; SIGINT, 2 on Linux and macOS.
  (define sigint 2)

  ;; armed, armed-at-prepare : Boolean
  ;; Whether the profile callback, or the authorizer, raises SIGINT the next
  ;; time it fires, once (keyboard-in, below).
  (define armed #f)
  (define armed-at-prepare #f)

  ;; c-text : Natural -> (U String #f)
  ;; The NUL-terminated text at P, a byte a character, or #f for NULL: the
  ;; table names SQLite hands the authorizer here are ASCII. Raises nothing.
  (define (c-text p)
    (if (eqv? p 0)
        #f
        (let loop ((i 0) (chars '()))
          (let ((b (foreign-ref 'unsigned-8 p i)))
            (if (eqv? b 0)
                (list->string (reverse chars))
                (loop (+ i 1) (cons (integer->char b) chars)))))))

  (define-syntax bound
    (syntax-rules ()
      ((_ name form)
       (guard (e (#t (lambda args (error name "this library could not bind it" (describe e)))))
         form))))

  ;; sqlite-insert, sqlite-select : Natural
  ;; SQLITE_INSERT and SQLITE_SELECT, the authorizer's action codes.
  (define sqlite-insert 18)
  (define sqlite-select 21)

  ;; int (*xAuth)(void *pUserData, int action, const char *, const char *, const char *, const char *)
  ;; When armed-at-prepare is set, the authorizer raises SIGINT once, inside
  ;; the prepare that called it (keyboard-in, below).
  (define authorizer
    (foreign-callable __collect_safe
      (lambda (data action name value schema trigger)
        (when (or (eqv? action sqlite-select) (eqv? action sqlite-insert))
          (note! (list action (and (eqv? action sqlite-insert) (c-text name))))
          (when (and armed-at-prepare c-raise)
            (set! armed-at-prepare #f)
            (c-raise sigint)))
        0)
      (uptr int uptr uptr uptr uptr) int))

  ;; int sqlite3_set_authorizer(sqlite3*, int (*xAuth)(...), void *pUserData)
  (define set-authorizer
    (bound 'sqlite3_set_authorizer (foreign-procedure "sqlite3_set_authorizer" (uptr uptr uptr) int)))

  ;; int (*xEntryPoint)(sqlite3 *db, const char **pzErrMsg, const sqlite3_api_routines *pThunk)
  (define entry-point
    (foreign-callable __collect_safe
      (lambda (db message api)
        (set-authorizer db (foreign-callable-entry-point authorizer) db))
      (uptr uptr uptr) int))

  ;; int sqlite3_auto_extension(void (*xEntryPoint)(void))
  (define auto-extension
    (bound 'sqlite3_auto_extension (foreign-procedure "sqlite3_auto_extension" (uptr) int)))

  ;; void sqlite3_reset_auto_extension(void)
  ;; Unregisters every entry point and frees SQLite's list of them, which
  ;; sqlite3_cancel_auto_extension keeps, 8 bytes the memory check finds.
  (define reset-auto-extension
    (bound 'sqlite3_reset_auto_extension (foreign-procedure "sqlite3_reset_auto_extension" () void)))

  ;; tell-registered : -> (U 'registered (List 'auto-extension-answered Integer) (List 'raised Any))
  ;; The entry point registered, the two callbacks locked, for every new
  ;; connection; or the code sqlite3_auto_extension answered instead. The
  ;; callbacks stay locked then, never called: Chez 10.4.0's unlock of an
  ;; object not locked still decrements its segment's count, which can unpin
  ;; another object there. Raises nothing.
  (define (tell-registered)
    (guard (e (#t (list 'raised (describe e))))
      (lock-object authorizer)
      (lock-object entry-point)
      (let ((rc (auto-extension (foreign-callable-entry-point entry-point))))
        (if (eqv? rc 0) 'registered (list 'auto-extension-answered rc)))))

  ;; sqlite-misuse : Natural
  ;; SQLITE_MISUSE, 21, the one refusal: Apple's 3.51.0 answers it for an
  ;; entry point upstream takes, where upstream answers it only for NULL.
  ;; Any other code, SQLITE_NOMEM's 7 from a failed realloc or whatever
  ;; sqlite3_initialize failed with, is a failure, which nothing gates.
  (define sqlite-misuse 21)

  ;; int (*xEntryPoint)(sqlite3 *db, const char **pzErrMsg, const sqlite3_api_routines *pThunk)
  ;; An entry point that does nothing, for tell-direct.
  (define idle-entry-point
    (foreign-callable __collect_safe
      (lambda (db message api) 0)
      (uptr uptr uptr) int))

  ;; tell-direct : -> (U Integer (List 'raised Any))
  ;; What sqlite3_auto_extension answers for idle-entry-point, an entry
  ;; point that does nothing, registered straight through the FFI, with no
  ;; procedure of the tell's between, then unregistered by
  ;; sqlite3_reset_auto_extension, which frees SQLite's list: an
  ;; independent reading of whether this libsqlite3 refuses a registration.
  ;; The callable is locked while registered, and unlocked once, after the
  ;; reset. Call it before tell-registered: the reset unregisters every
  ;; entry point. Raises nothing.
  (define (tell-direct)
    (guard (e (#t (list 'raised (describe e))))
      (lock-object idle-entry-point)
      (let ((rc (auto-extension (foreign-callable-entry-point idle-entry-point))))
        (reset-auto-extension)
        (unlock-object idle-entry-point)
        rc)))

  ;; tell-refused? : Any -> Boolean
  ;; Whether ANSWER, tell-registered's, is the refusal.
  (define (tell-refused? answer)
    (equal? answer (list 'auto-extension-answered sqlite-misuse)))

  ;; tell-gate-held : Any Any -> Any
  ;; gate-held when the gate's decision on REGISTRATION, tell-registered's,
  ;; matches DIRECT, tell-direct's: refused exactly when the direct
  ;; registration answered 21, and registered exactly when it answered 0;
  ;; else both, to be read.
  (define (tell-gate-held registration direct)
    (if (or (and (tell-refused? registration) (eqv? direct sqlite-misuse))
            (and (eq? registration 'registered) (eqv? direct 0)))
        'gate-held
        (list 'gate registration 'direct direct)))

  ;; tell-answered? : Any -> Boolean
  ;; Whether ANSWER, tell-registered's, is registered, or the refusal: not
  ;; another code, a raise, nor anything else.
  (define (tell-answered? answer)
    (or (eq? answer 'registered) (tell-refused? answer)))

  ;; unavailable! : Any String (U String #f) -> Boolean
  ;; Whether ANSWER, tell-registered's, is the refusal; then the row NAME,
  ;; or its CHECK, the one part that reads the tell, is printed unavailable,
  ;; so it is never passed unseen (ADR-0005, amended). The one place both
  ;; gates below decide.
  (define (unavailable! answer name check)
    (let ((refused (tell-refused? answer)))
      (when refused
        (display "UNAVAILABLE ")
        (display name)
        (when check
          (display ", its ")
          (display check))
        (display ": this libsqlite3 refused sqlite3_auto_extension (")
        (display sqlite-misuse)
        (display "), so the tell can't note a prepare")
        (newline))
      refused))

  ;; tell-available! : Any String -> Void
  ;; The gate of a row NAME that needs the tell whole: where ANSWER,
  ;; tell-registered's, is the refusal, the row is printed unavailable and
  ;; skipped, never passed. Anything else runs it.
  (define (tell-available! answer name)
    (when (unavailable! answer name #f)
      (test-skip name)))

  ;; tell-kept? : Any String String -> Boolean
  ;; The gate of CHECK, the one part of the row NAME that reads the tell:
  ;; #f where ANSWER, tell-registered's, is the refusal, CHECK printed
  ;; unavailable, the row's other checks run; else #t, every check run.
  (define (tell-kept? answer name check)
    (not (unavailable! answer name check)))

  ;; tell-noted : Boolean Any -> Any
  ;; VALUE, read from the tell's notes, where its check is KEPT?; else the
  ;; symbol unavailable. A row puts it in its expected value and its actual
  ;; alike, so it asserts the rest of its output whole.
  (define (tell-noted kept? value)
    (if kept? value 'unavailable))

  ;; tell-reset : -> (U (List 'reset Natural) (List 'raised Any))
  ;; The entry point unregistered and the callbacks unlocked; then how many
  ;; prepares a fresh connection's select noted: 0, the tell gone. Harmless
  ;; after a refusal: no entry point of this library is registered, and the
  ;; callbacks, which tell-registered locked all the same, are unlocked
  ;; once each. Call it once: a second unlock is of objects not locked.
  (define (tell-reset)
    (guard (e (#t (list 'raised (describe e))))
      (reset-auto-extension)
      (unlock-object entry-point)
      (unlock-object authorizer)
      (clear-notes!)
      (let ((db (open-database ":memory:")))
        (tier-run db "select 1")
        (close-database! db)
        (list 'reset (length noted)))))

  ;; --- helpers ------------------------------------------------------------------------------

  ;; zero-counts : (Listof (Pairof Symbol Natural))
  (define zero-counts '((block . 0) (connection . 0) (statement . 0)))

  (define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

  ;; what-raised : Any -> Any
  (define (what-raised e)
    (cond ((sqlite-error? e)
           (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)))
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

  (define void-value (if #f #f))
  (define (no-value x) (if (eq? x void-value) 'no-value x))

  ;; tier-run : Database String -> (Listof Any)
  ;; SQL run through M2's statement tier: each row's first column, in order.
  ;; The cache is never touched.
  (define (tier-run db sql)
    (let ((st (prepare-statement db sql)))
      (dynamic-wind
        (lambda () #f)
        (lambda ()
          (let loop ((rows '()))
            (if (step! st)
                (loop (cons (column-value st 0) rows))
                (reverse rows))))
        (lambda () (finalize-statement! st)))))

  ;; fresh : (Listof (Pairof Symbol Any)) -> Database
  ;; A fresh :memory: connection opened with SETTINGS, holding t, its rows 1,
  ;; 2 and 3, made by one statement through the statement tier, which costs
  ;; a trial under the memory gate a seventh less than two; the notes cleared
  ;; after.
  (define (fresh settings)
    (let ((db (open-database ":memory:" settings)))
      (tier-run db "create table t as select 1 as x union all select 2 union all select 3")
      (clear-notes!)
      db))

  ;; states : Database -> (Listof (Pairof String Symbol))
  ;; Every statement DB tracks, its SQL and state, sorted by SQL.
  (define (states db)
    (list-sort (lambda (a b) (string<? (car a) (car b)))
               (let loop ((rest (tracked-statements db)) (found '()))
                 (if (null? rest)
                     found
                     (loop (cdr rest)
                           (cons (cons (statement-sql (car rest)) (statement-state (car rest))) found))))))

  ;; summarized : (Listof Any) -> Any
  ;; () for no deviation; else how many, and the first three.
  (define (summarized deviations)
    (if (null? deviations)
        '()
        (list (length deviations)
              (let loop ((rest deviations) (n 0) (kept '()))
                (if (or (null? rest) (= n 3)) (reverse kept) (loop (cdr rest) (+ n 1) (cons (car rest) kept)))))))

  ;; --- the calls ----------------------------------------------------------------------------

  ;; Call = (Vector Symbol (Database -> Any) String (U 'select 'insert) Natural
  ;;                (Listof Any) (Listof Any) (Listof Any) Boolean)
  ;; A convenience's call: its name; the call; its SQL; the kind of prepare
  ;; the authorizer notes for it, and how many one clean call makes; its
  ;; answers, the call's own first; t's rows after one clean call; the rows
  ;; one call adds, in order; and whether it survives a preemption.

  (define select-sql "select x from t where x > ?")
  (define insert-sql "insert into t values (?)")
  (define script-sql "insert into t values (7); insert into t values (8)")

  ;; failing-sql, least-integer : String Integer
  ;; A select whose first row is 1 and whose second step fails: abs of the
  ;; least 64-bit integer overflows. query answers the first row, then
  ;; raises the second step's failure, and gives the failed statement back,
  ;; which finalizes it (ADR-0020, decision 5).
  (define failing-sql "select abs(x) from (select 1 as x union all select ?)")
  (define least-integer (- (expt 2 63)))

  ;; failing-answer : Any
  ;; What query of failing-sql raises: SQLite's integer overflow, an error.
  (define failing-answer (list 'raised (list 'sqlite-error 'query 'error 'error)))

  ;; failing-selects : Natural
  ;; The selects the authorizer notes for one prepare of failing-sql, as the
  ;; tell's row measures them: four, on both libraries.
  (define failing-selects 4)

  (define (closed name) (list 'raised (list 'closed name)))

  ;; re-entered : Symbol -> Any
  ;; call-with-open-handle's refusal of a re-entry, from NAME.
  (define (re-entered name) (list 'raised (list 'assertion-violation name '(re-entered))))

  ;; re-entered* : Symbol -> Any
  ;; call-with-block's refusal of a re-entry, from NAME, its irritants none.
  (define (re-entered* name) (list 'raised (list 'assertion-violation name '())))

  (define (sum acc row) (+ acc (vector-ref row 0)))

  ;; call-of : Symbol -> Call
  (define (call-of verb)
    (case verb
      ((execute!)
       (vector 'execute! (lambda (db) (no-value (execute! db insert-sql 9))) insert-sql 'insert 1
               (list 'no-value (closed 'execute!)) '(1 2 3 9) '(9) #t))
      ((query)
       (vector 'query (lambda (db) (query db select-sql 0)) select-sql 'select 1
               (list '(#(1) #(2) #(3)) (closed 'query)) '(1 2 3) '() #t))
      ((query-row)
       (vector 'query-row (lambda (db) (query-row db select-sql 0)) select-sql 'select 1
               (list '#(1) (closed 'query-row)) '(1 2 3) '() #t))
      ((query-fold)
       (vector 'query-fold (lambda (db) (query-fold db select-sql sum 0 0)) select-sql 'select 1
               (list 6 (closed 'query-fold) (re-entered 'query-fold)) '(1 2 3) '() #f))
      ((query-failing)
       (vector 'query-failing (lambda (db) (query db failing-sql least-integer)) failing-sql 'select
               failing-selects (list failing-answer (closed 'query)) '(1 2 3) '() #t))
      (else
       (vector 'execute-script! (lambda (db) (no-value (execute-script! db script-sql))) #f 'insert 2
               (list 'no-value (closed 'execute-script!) (re-entered* 'execute-script!))
               '(1 2 3 7 8) '(7 8) #f))))

  (define (call-name c) (vector-ref c 0))
  (define (call-run c) (vector-ref c 1))
  (define (call-sql c) (vector-ref c 2))
  (define (call-kind c) (vector-ref c 3))
  (define (call-prepares c) (vector-ref c 4))
  (define (call-answers c) (vector-ref c 5))
  (define (call-rows c) (vector-ref c 6))
  (define (call-adds c) (vector-ref c 7))
  (define (call-survives? c) (vector-ref c 8))

  ;; thunk-of : Call Database -> (-> Any)
  (define (thunk-of c db) (lambda () (attempt (lambda () ((call-run c) db)))))

  ;; --- engines ------------------------------------------------------------------------------

  ;; quieted! : -> Void
  ;; A collection now, at a fuel's start, with collect-trip-bytes raised to
  ;; 128 MiB, far above what one fuel's runs allocate, so no collect request
  ;; falls in a control or a trial (.plans/research/m3-slice-5/, gc-ticks.sps).
  (define (quieted!)
    (collect-trip-bytes (expt 2 27))
    (collect))

  ;; slice : Engine Positive-Integer -> (U (List 'completed Any) (List 'expired Engine))
  (define (slice e fuel)
    (e fuel (lambda (left . vals) (list 'completed (car vals))) (lambda (more) (list 'expired more))))

  ;; finish : Engine -> Any
  ;; E resumed a million ticks at a time until it completes, at most 1000
  ;; slices.
  (define (finish e)
    (let loop ((e e) (n 0))
      (let ((r (slice e 1000000)))
        (cond ((eq? (car r) 'completed) (cadr r))
              ((>= n 1000) 'never-completed)
              (else (loop (cadr r) (+ n 1)))))))

  ;; --- one clean call -----------------------------------------------------------------------

  ;; clean-call : Symbol Boolean -> (List Any (U Natural 'unavailable) (Listof Any) (Listof (Pairof String Symbol)) Natural Counts)
  ;; VERB's call, once, outside any engine, on a fresh connection: its
  ;; answer, the prepares the authorizer noted, or unavailable unless
  ;; NOTED?, t's rows, what the connection tracks and caches, and the
  ;; counts once it is closed. The tell's own row.
  (define (clean-call verb noted?)
    (let* ((c (call-of verb))
           (db (fresh '()))
           (answer ((thunk-of c db)))
           (prepares (tell-noted noted? (noted-count (call-kind c))))
           (rows (tier-run db "select x from t order by x"))
           (tracked (states db))
           (cached (database-cache-count db)))
      (close-database! db)
      (list answer prepares rows tracked cached (native-counts))))

  ;; clean-tracked : Call -> (Listof (Pairof String Symbol))
  ;; What one clean call leaves tracked: its statement, ready, in the cache;
  ;; the script, and a call whose statement failed, nothing.
  (define (clean-tracked c)
    (if (and (call-sql c) (not (call-fails? c))) (list (cons (call-sql c) 'ready)) '()))

  ;; call-fails? : Call -> Boolean
  ;; Whether C's call raises, its statement failed: query-failing's.
  (define (call-fails? c) (eq? (call-name c) 'query-failing))

  ;; --- the control --------------------------------------------------------------------------

  ;; Controlled = (U 'completed (List Boolean Boolean))
  ;; control : Call Positive-Integer -> Controlled
  ;; C as an engine on a connection whose statement cache holds none, one
  ;; slice of FUEL: completed, when it completed; else whether its
  ;; remainder, resumed to its end, then to its end again, made a whole new
  ;; call the second time, the authorizer seeing the call's SQL prepared
  ;; again; and whether it was refused then, before the call's first
  ;; section: nothing noted at the expiry, and the second resume answering
  ;; &sqlite-closed from the verb, preparing nothing.
  (define (control c fuel)
    (let* ((db (fresh '((statement-cache . 0))))
           (r (slice (make-engine (thunk-of c db)) fuel))
           (made (if (eq? (car r) 'completed)
                     'completed
                     (let* ((before (= (noted-count (call-kind c)) 0))
                            (first (finish (cadr r)))
                            (n (noted-count (call-kind c)))
                            (second (finish (cadr r)))
                            (new (> (noted-count (call-kind c)) n)))
                       (list new (and before (not new) (equal? second (cadr (call-answers c)))))))))
      (guard (e (#t #f)) (close-database! db))
      made))

  ;; made-new? : Controlled -> Boolean
  (define (made-new? made) (and (pair? made) (car made)))

  ;; --- one trial ----------------------------------------------------------------------------

  ;; prefix? : (Listof Any) (Listof Any) -> Boolean
  (define (prefix? short long)
    (cond ((null? short) #t)
          ((null? long) #f)
          ((equal? (car short) (car long)) (prefix? (cdr short) (cdr long)))
          (else #f)))

  ;; made-by-one : Call -> (Listof (Listof Integer))
  ;; The rows one call of C may add to t, in order: all its own for a call
  ;; that survives a preemption; any prefix of them for one that does not.
  (define (made-by-one c)
    (let ((adds (call-adds c)))
      (if (call-survives? c)
          (list adds)
          (let loop ((n (length adds)) (found '()))
            (if (< n 0) found (loop (- n 1) (cons (prefix-of adds n) found)))))))

  (define (prefix-of items n)
    (if (or (= n 0) (null? items)) '() (cons (car items) (prefix-of (cdr items) (- n 1)))))

  ;; rows-allowed? : Call Any Boolean -> Boolean
  ;; Whether ROWS, t's after a trial, in order, are 1, 2 and 3, then what one
  ;; call of C adds; or, where NEW? allows a whole new call, what two add,
  ;; merged in order.
  (define (rows-allowed? c rows new?)
    (and (list? rows) (>= (length rows) 3) (prefix? '(1 2 3) rows)
         (let ((tail (list-tail rows 3)) (ones (made-by-one c)))
           (or (exists (lambda (one) (equal? tail one)) ones)
               (and new?
                    (exists (lambda (a)
                              (exists (lambda (b) (equal? tail (list-sort < (append a b)))) ones))
                            ones))))))

  ;; prepares-allowed? : Call Natural Boolean -> Boolean
  ;; Whether N, the authorizer's count of the trial's prepares, is one
  ;; call's: its statement once, for the four that use the cache; for the
  ;; script, each of its statements at most once, none at all where an expiry
  ;; inside its block freed the block before the first; twice that where NEW?
  ;; allows a whole new call, whose first run may find the other's statement
  ;; cached.
  (define (prepares-allowed? c n new?)
    (let ((most (call-prepares c)))
      (if (call-sql c)
          (or (= n most) (and new? (= n (* 2 most))))
          (or (<= n most) (and new? (<= n (* 2 most)))))))

  ;; Judged = (List Symbol Boolean Boolean (Listof Any))
  ;; A trial's kind, completed when R's first slice completed the call, last
  ;; when R's resume completed within G, else interleaved; whether it was
  ;; past the first section, R1 taken after the call had made it; whether
  ;; both were, R taken after it too; and what deviated.

  ;; judged : Call Boolean (Listof Any) Natural (Listof Any) Database -> (Listof Any)
  ;; RUNS' answers judged, NEW? whether the control allows a whole new call,
  ;; PREPARES the authorizer's count for the trial, DB the trial's
  ;; connection, then closed; START the counts when the trial began. What
  ;; deviated.
  (define (judged c new? runs prepares db start captures)
    (let* ((rows (attempt (lambda () (tier-run db "select x from t order by x"))))
           (tracked (attempt (lambda () (states db))))
           (cached (attempt (lambda () (database-cache-count db))))
           (cleared (attempt (lambda () (bindings-cleared? c db))))
           (closed (attempt (lambda () (close-database! db) 'closed)))
           (counts (native-counts))
           (deviations '()))
      (define (deviate! d) (set! deviations (cons d deviations)))
      ;; each run answers the call's answer, or a refusal
      (let loop ((rest runs))
        (unless (null? rest)
          (unless (member (car rest) (call-answers c)) (deviate! (list 'answer (car rest))))
          (loop (cdr rest))))
      ;; made once, and its effect once; twice where a whole new call is allowed
      (unless (prepares-allowed? c prepares new?) (deviate! (list 'prepares prepares)))
      (unless (rows-allowed? c rows new?) (deviate! (list 'rows rows)))
      ;; nothing out of the cache, nothing at a row, the cache as one clean call leaves it
      (unless (or (and (equal? tracked (clean-tracked c)) (eqv? cached (length tracked)))
                  (and (not (call-survives? c)) (equal? tracked '()) (eqv? cached 0)))
        (deviate! (list 'left tracked cached)))
      (unless (eq? cleared #t) (deviate! (list 'bindings cleared)))
      ;; a failing call: the failure raised by one run, and again by each run
      ;; taken past the call's give-back; every other run refused
      (when (and (call-fails? c) (not (and new? (= prepares (* 2 (call-prepares c))))))
        (let ((failures (length (filter (lambda (a) (equal? a (car (call-answers c)))) runs)))
              (past (length (filter (lambda (x) x) captures))))
          (unless (= failures (if (> past 0) past 1))
            (deviate! (list 'failures failures 'past-the-give-back past)))))
      (unless (eq? closed 'closed) (deviate! (list 'close closed)))
      (unless (equal? counts start) (deviate! (list 'counts start counts)))
      (reverse deviations)))

  ;; bindings-cleared? : Call Database -> (U Boolean Any)
  ;; Whether the statement DB's cache holds for C's SQL, if any, has its
  ;; bindings cleared, as a return leaves it: checked out, stepped unbound,
  ;; its parameter NULL, then given back. A select of rows above NULL
  ;; answers none; an insert of NULL leaves one NULL row more in t, read
  ;; after. #t when the cache holds none.
  (define (bindings-cleared? c db)
    (if (not (and (call-sql c) (eqv? (database-cache-count db) 1)))
        #t
        (let* ((st (checked-out 'test-conveniences-pending db (call-sql c) #f #f))
               (row? (step! st))
               (back (returned 'test-conveniences-pending st)))
          (if (eq? (call-kind c) 'select)
              (not row?)
              (equal? (tier-run db "select count(*) from t where x is null") '(1))))))

  ;; past-the-give-back? : Call Database -> Boolean
  ;; Whether a run taken now lies past C's give-back: its statement made,
  ;; the authorizer having noted its prepare, and no longer tracked. A
  ;; failed statement is finalized at its return, so for query-failing it
  ;; is the run's last section.
  (define (past-the-give-back? c db)
    (and (>= (noted-count (call-kind c)) (call-prepares c))
         (null? (tracked-statements db))))

  ;; trial : Call Positive-Integer Positive-Integer Boolean -> Judged
  ;; One trial of C at FUEL, R resumed at G, NEW? the control's answer.
  (define (trial c fuel g new?)
    (let* ((start (native-counts))
           (db (fresh '()))
           (kind (call-kind c))
           (r (slice (make-engine (thunk-of c db)) fuel)))
      (if (eq? (car r) 'completed)
          (list 'completed #f #f (judged c new? (list (cadr r)) (noted-count kind) db start '(#f)))
          (let* ((R (cadr r))
                 (r-past (> (noted-count kind) 0))
                 (r-given (past-the-give-back? c db))
                 (r1 (slice R g)))
            (if (eq? (car r1) 'completed)
                (let ((again (finish R)))
                  (list 'last #f #f
                        (judged c new? (list (cadr r1) again) (noted-count kind) db start
                                (list r-given r-given))))
                (let* ((R1 (cadr r1))
                       (r1-past (> (noted-count kind) 0))
                       (r1-given (past-the-give-back? c db))
                       (second (finish R))
                       (third (finish R1)))
                  (list 'interleaved r1-past r-past
                        (judged c new? (list second third) (noted-count kind) db start
                                (list r-given r1-given)))))))))

  ;; --- the sweep ----------------------------------------------------------------------------

  ;; Sweep = (List Any Natural Natural Natural (Listof Any) Natural Counts (U Natural #f))
  ;; The fuel at which the call completes without expiring, or
  ;; no-completion-by-20000; how many trials interleaved, R1 existing; how
  ;; many of those were past the call's first section, and how many both
  ;; past it; each trial's deviations, with its fuels; the last fuel at which
  ;; the control made a whole new call, 0 for none; the counts once the
  ;; sweep is done; and the first fuel at which the control was refused
  ;; before the call's first section, #f for none.

  ;; sweep : Symbol (U 'every 'odd 'even) -> Sweep
  ;; VERB's call swept: at every fuel from 1 until the call completes
  ;; without expiring, the control, then trial at every G from 1 until R's
  ;; resume completes within it, each fuel begun by quieted!. With PARITY
  ;; odd or even, only the fuels of that parity run every G; the others run
  ;; G = 1 alone, which tells whether the call completes there. So two suites
  ;; of the two parities sweep every trial between them (the script's, which
  ;; one suite could not hold well under the memory gate's limit).
  (define (sweep verb parity)
    (let ((c (call-of verb)))
      (define (every-g? fuel)
        (case parity ((odd) (odd? fuel)) ((even) (even? fuel)) (else #t)))
      (let floop ((fuel 1) (trials 0) (past 0) (both 0) (deviations '()) (last-new 0) (was-new #f)
                  (refused-at #f))
        (let* ((made (begin (quieted!) (control c fuel)))
               (new? (or (made-new? made) was-new))
               (last-new (if (made-new? made) fuel last-new))
               (refused-at (or refused-at (and (pair? made) (cadr made) fuel))))
          (let gloop ((g 1) (trials trials) (past past) (both both) (deviations deviations))
            (let* ((t (trial c fuel g new?))
                   (kind (car t))
                   (deviations (if (null? (cadddr t)) deviations
                                   (cons (list fuel g (cadddr t)) deviations)))
                   (interleaved (eq? kind 'interleaved))
                   (trials (if interleaved (+ trials 1) trials))
                   (past (if (and interleaved (cadr t)) (+ past 1) past))
                   (both (if (and interleaved (caddr t)) (+ both 1) both)))
              (cond ((eq? kind 'completed)
                     (list fuel trials past both (reverse deviations) last-new (native-counts)
                           refused-at))
                    ((>= fuel 20000)
                     (list 'no-completion-by-20000 trials past both (reverse deviations) last-new
                           (native-counts) refused-at))
                    ((or (eq? kind 'last) (not (every-g? fuel)))
                     (floop (+ fuel 1) trials past both deviations last-new (made-new? made) refused-at))
                    (else (gloop (+ g 1) trials past both deviations)))))))))

  ;; tallied : (Listof (List Natural Natural (Listof Any))) -> (Listof (Pairof Symbol Natural))
  ;; How many trials among DEVIATIONS deviated by each kind, a deviation's
  ;; first symbol, in the order each kind was first seen.
  (define (tallied deviations)
    (let loop ((rest deviations) (kinds '()))
      (if (null? rest)
          kinds
          (loop (cdr rest)
                (let each ((ds (caddr (car rest))) (kinds kinds) (seen '()))
                  (if (null? ds)
                      kinds
                      (let ((k (car (car ds))))
                        (if (memq k seen)
                            (each (cdr ds) kinds seen)
                            (each (cdr ds) (counted-up k kinds) (cons k seen))))))))))

  ;; counted-up : Symbol (Listof (Pairof Symbol Natural)) -> (Listof (Pairof Symbol Natural))
  (define (counted-up k kinds)
    (cond ((null? kinds) (list (cons k 1)))
          ((eq? (car (car kinds)) k) (cons (cons k (+ (cdr (car kinds)) 1)) (cdr kinds)))
          (else (cons (car kinds) (counted-up k (cdr kinds))))))

  ;; reported : Symbol Sweep Natural (U Natural 'none) -> (List Any Any Counts)
  ;; RUN's deviations, summarized; whether its interleaved trials past the
  ;; call's first section reached PAST-A-FUEL a fuel on average, and those
  ;; both past it BOTH-A-FUEL, or none at all where it is none, over the
  ;; fuels up to the one at which the call completes; and whether its
  ;; control was refused before the call's first section at some fuel, and
  ;; made every whole new call below the first: a second resume of the same
  ;; call that ran again would look like one to the control; and the counts
  ;; once it was done. Its fuels and counts printed, naming VERB. A sweep
  ;; that reused one R across every G, its every trial after G = 1 refused
  ;; at once, makes at most one trial a fuel (the lead's, slice 5's part D).
  (define (reported verb run past-a-fuel both-a-fuel)
    (let ((fuel (list-ref run 0)) (trials (list-ref run 1)) (past (list-ref run 2))
          (both (list-ref run 3)) (deviations (list-ref run 4)) (last-new (list-ref run 5))
          (refused-at (list-ref run 7)))
      (display "  ")
      (display verb)
      (display ": completed without expiring at fuel ")
      (write fuel)
      (display "; trials with R1 ")
      (write trials)
      (display "; past the first section ")
      (write past)
      (display "; both past it ")
      (write both)
      (display "; the last fuel at which the control made a whole new call ")
      (write last-new)
      (display ", below the first at which it was refused before the call's first section, ")
      (write refused-at)
      (newline)
      (unless (null? deviations)
        (display "    deviations by kind: ")
        (write (tallied deviations))
        (newline))
      (list (if (integer? fuel) (summarized deviations) (list fuel (summarized deviations)))
            (cond ((not (and (integer? fuel) (>= past (* past-a-fuel fuel))
                             (if (eq? both-a-fuel 'none) (= both 0) (>= both (* both-a-fuel fuel)))))
                   (list 'too-few-interleavings 'past past 'both both 'fuel fuel))
                  ((not (and refused-at (< last-new refused-at)))
                   (list 'whole-new-calls-not-below-a-refusal last-new refused-at))
                  (else 'interleavings-reached))
            (list-ref run 6))))

  ;; --- a timer handler's raise, at every tick -------------------------------------------
  ;;
  ;; A timer's handler is the caller's code, and runs between any two
  ;; critical sections; one that raises makes a raise inside the call that no
  ;; section caught. execute!, query and query-row give their statement back
  ;; then, the call's, by a claim of whatever position is next, unless the
  ;; call has ended, and raise it again (the conveniences' with-checked-out);
  ;; query-fold's wind and execute-script!'s each finish theirs. So a raise
  ;; always finishes the statement, from any tick. The call's statement once
  ;; given back is no longer the call's: a handler that takes it from the
  ;; cache, then raises, keeps it as it took it.

  ;; timer-trial : Call Positive-Integer Boolean -> (List Boolean (Listof Any))
  ;; C on a fresh connection, a timer of TICKS ticks set just before the
  ;; call, whose handler raises the symbol timer once, the timer cleared
  ;; after: whether the handler ran; and what deviated. The call answers its
  ;; answer, or the raise reaches the caller, the very symbol; the
  ;; statement was prepared at most once, as the authorizer noted, checked
  ;; only where PREPARES?, its effect made at most once; no
  ;; statement is tracked outside the cache, none at a row, the cache holding
  ;; the call's statement, ready, or none, the raise before its check-out;
  ;; nothing is counted once the connection is closed. The handler notes
  ;; the statements counted as it raises, the counters' own reading, which
  ;; needs no tell: for a call that survives a preemption, one counted then
  ;; is the call's, and the raise gives it back, so the cache holds it. A
  ;; give-back that finalized it instead passed every row that read only
  ;; the end, where the tell was refused (M3's closing review, reviewer B's
  ;; N2).
  (define (timer-trial c ticks prepares?)
    (let* ((start (native-counts))
           (db (fresh '()))
           (fired #f)
           (made-at-raise #f)
           (old (timer-interrupt-handler))
           (answer
            (dynamic-wind
              (lambda ()
                (timer-interrupt-handler
                 (lambda ()
                   (unless fired
                     (set! fired #t)
                     (set! made-at-raise (cdr (assq 'statement (native-counts))))
                     (raise 'timer)))))
              (lambda ()
                (guard (e ((eq? e 'timer) 'timer)
                          (#t (list 'raised (what-raised e))))
                  (set-timer ticks)
                  (let ((r ((call-run c) db)))
                    (set-timer 0)
                    r)))
              (lambda ()
                (set-timer 0)
                (timer-interrupt-handler old))))
           (prepares (noted-count (call-kind c)))
           (rows (attempt (lambda () (tier-run db "select x from t order by x"))))
           (tracked (attempt (lambda () (states db))))
           (cached (attempt (lambda () (database-cache-count db))))
           (closed (attempt (lambda () (close-database! db) 'closed)))
           (counts (native-counts))
           (deviations '()))
      (define (deviate! d) (set! deviations (cons d deviations)))
      (unless (or (equal? answer (car (call-answers c))) (eq? answer 'timer))
        (deviate! (list 'answer answer)))
      (unless (or (not prepares?) (<= prepares (call-prepares c)))
        (deviate! (list 'prepares prepares)))
      (unless (and (list? rows) (exists (lambda (one) (equal? rows (append '(1 2 3) one)))
                                        (cons '() (made-by-one c))))
        (deviate! (list 'rows rows)))
      (unless (or (and (equal? tracked (clean-tracked c)) (eqv? cached (length tracked)))
                  (and (equal? tracked '()) (eqv? cached 0)
                       (not (and (call-survives? c) (eq? answer 'timer) (eqv? made-at-raise 1)))))
        (deviate! (list 'left tracked cached 'made-at-the-raise made-at-raise)))
      (unless (eq? closed 'closed) (deviate! (list 'close closed)))
      (unless (equal? counts start) (deviate! (list 'counts start counts)))
      (list fired (reverse deviations))))

  ;; timer-sweep : Symbol Boolean -> (List Any Natural (Listof Any) Counts)
  ;; VERB's call under timer-trial at every tick from 1 until the call
  ;; completes before the handler runs, at most 20000, its prepares checked
  ;; only where PREPARES?: that tick, or no-completion-by-20000; how many
  ;; ticks the handler raised at; each tick's deviations; and the counts
  ;; after.
  (define (timer-sweep verb prepares?)
    (let ((c (call-of verb)))
      (let loop ((ticks 1) (raised 0) (deviations '()))
        (let* ((t (timer-trial c ticks prepares?))
               (deviations (if (null? (cadr t)) deviations (cons (list ticks (cadr t)) deviations))))
          (cond ((not (car t)) (list ticks raised (reverse deviations) (native-counts)))
                ((>= ticks 20000) (list 'no-completion-by-20000 raised (reverse deviations) (native-counts)))
                (else (loop (+ ticks 1) (+ raised 1) deviations)))))))

  ;; taken-trial : Call Positive-Integer -> (List Boolean (Listof Any))
  ;; As timer-trial, for a select, but the handler first takes a statement
  ;; for the call's SQL, the cache's by checked-out or a fresh one, binds 0
  ;; to its parameter and steps it once, to its first row, then raises: the call's own statement, given
  ;; back before the raise, is the one it takes. Whether the handler ran;
  ;; and what deviated: the call's answer, or the raise, as timer-trial's;
  ;; the taken statement still at its row, as the handler left it, before
  ;; the trial gives it back; then, once it is given back, the statements
  ;; tracked as one clean call leaves them, nothing at a row, and nothing
  ;; counted once the connection is closed.
  (define (taken-trial c ticks)
    (let* ((start (native-counts))
           (db (fresh '()))
           (taken #f)
           (old (timer-interrupt-handler))
           (answer
            (dynamic-wind
              (lambda ()
                (timer-interrupt-handler
                 (lambda ()
                   (unless taken
                     (set! taken (checked-out 'test-conveniences-pending db (call-sql c) #f #f))
                     (bind-all! taken 0)
                     (step! taken)
                     (raise 'timer)))))
              (lambda ()
                (guard (e ((eq? e 'timer) 'timer)
                          (#t (list 'raised (what-raised e))))
                  (set-timer ticks)
                  (let ((r ((call-run c) db)))
                    (set-timer 0)
                    r)))
              (lambda ()
                (set-timer 0)
                (timer-interrupt-handler old))))
           (kept (and taken (attempt (lambda () (statement-state taken)))))
           (given (and taken (attempt (lambda () (returned 'test-conveniences-pending taken) 'given))))
           (tracked (attempt (lambda () (states db))))
           (cached (attempt (lambda () (database-cache-count db))))
           (closed (attempt (lambda () (close-database! db) 'closed)))
           (counts (native-counts))
           (deviations '()))
      (define (deviate! d) (set! deviations (cons d deviations)))
      (unless (or (equal? answer (car (call-answers c))) (eq? answer 'timer))
        (deviate! (list 'answer answer)))
      (unless (or (not taken) (and (eq? kept 'row) (eq? given 'given)))
        (deviate! (list 'taken kept given)))
      (unless (and (equal? tracked (clean-tracked c)) (eqv? cached 1))
        (deviate! (list 'left tracked cached)))
      (unless (eq? closed 'closed) (deviate! (list 'close closed)))
      (unless (equal? counts start) (deviate! (list 'counts start counts)))
      (list (and taken #t) (reverse deviations))))

  ;; taken-sweep : Symbol -> (List Any Natural (Listof Any) Counts)
  ;; VERB's call, a select, under taken-trial at every tick from 1 until the
  ;; call completes before the handler runs, at most 20000, as timer-sweep.
  (define (taken-sweep verb)
    (let ((c (call-of verb)))
      (let loop ((ticks 1) (raised 0) (deviations '()))
        (let* ((t (taken-trial c ticks))
               (deviations (if (null? (cadr t)) deviations (cons (list ticks (cadr t)) deviations))))
          (cond ((not (car t)) (list ticks raised (reverse deviations) (native-counts)))
                ((>= ticks 20000) (list 'no-completion-by-20000 raised (reverse deviations) (native-counts)))
                (else (loop (+ ticks 1) (+ raised 1) deviations)))))))

  ;; timer-reported : Symbol (List Any Natural (Listof Any) Counts) -> (List Any Any Counts)
  ;; RUN's deviations, summarized; whether the handler raised at some tick;
  ;; and the counts after. Its tick printed, naming VERB.
  (define (timer-reported verb run)
    (display "  ")
    (display verb)
    (display ", a timer handler raising: completed before it ran at tick ")
    (write (car run))
    (display "; raised at ")
    (write (cadr run))
    (display " ticks")
    (newline)
    (list (if (integer? (car run)) (summarized (caddr run)) (list (car run) (summarized (caddr run))))
          (if (> (cadr run) 0) 'some-raised 'none-raised)
          (cadddr run)))

  ;; --- a keyboard interrupt pending inside the return ---------------------------------
  ;;
  ;; No tick falls between a call's return section and its give-back's
  ;; guard, so no timer's handler runs there; a keyboard interrupt that came
  ;; pending inside the section is handled as it ends, there
  ;; (.plans/research/m3-slice-5/, section-end.sps). SQLite's profile trace
  ;; fires as a statement finishes, which for query-row is the reset inside
  ;; its return: raising SIGINT from it puts the keyboard handler just after
  ;; the call's last section. The handler takes the statement the return has
  ;; just filed, so the call's claim must have ended with the return: a raise
  ;; there gives nothing back.


  ;; int (*xCallback)(unsigned, void *pCtx, void *P, void *X)
  (define profile
    (foreign-callable __collect_safe
      (lambda (mask ctx p x)
        (when (and armed c-raise) (set! armed #f) (c-raise sigint))
        0)
      (unsigned-32 uptr uptr uptr) int))

  ;; int sqlite3_trace_v2(sqlite3*, unsigned uMask, int(*xCallback)(...), void *pCtx)
  (define trace-v2
    (bound 'sqlite3_trace_v2 (foreign-procedure "sqlite3_trace_v2" (uptr unsigned-32 uptr uptr) int)))

  ;; sqlite-trace-profile : Natural
  ;; SQLITE_TRACE_PROFILE, the trace's mask for a statement's finish.
  (define sqlite-trace-profile 2)

  ;; keyboard-in : Symbol (U 'return 'check-out) -> (List Any Any Any (Listof (Pairof String Symbol)) Any Counts)
  ;; VERB's call of t's rows on a fresh connection, SIGINT raised once from
  ;; inside one of its sections, the keyboard handler run as that section
  ;; ends: at return, from the profile trace as the return's reset finishes
  ;; query-row's statement, the handler taking a statement for the call's
  ;; SQL by checked-out, binding 0 to it and stepping it to its row; at
  ;; check-out, from the authorizer as the miss's prepare runs, taking
  ;; nothing. Then it raises the symbol interrupt. Answers what the call
  ;; answered or raised; the taken statement's state, #f for none, once the
  ;; call has raised, and the cache's count then; and, once the row gives the
  ;; taken statement back, what the connection tracks and caches, and the
  ;; counts once it is closed.
  (define (keyboard-in verb where)
    (guard (e (#t (list 'raised (what-raised e))))
      (let* ((c (call-of verb))
             (start (native-counts))
             (db (fresh '()))
             (handle (call-with-open-handle 'test-conveniences-pending db (lambda (h) h)))
             (taken #f)
             (handled #f)
             (old (keyboard-interrupt-handler))
             (answer
              (dynamic-wind
                (lambda ()
                  (lock-object profile)
                  (trace-v2 handle sqlite-trace-profile (foreign-callable-entry-point profile) 0)
                  (keyboard-interrupt-handler
                   (lambda ()
                     (unless handled
                       (set! handled #t)
                       (when (eq? where 'return)
                         (set! taken (checked-out 'test-conveniences-pending db (call-sql c) #f #f))
                         (bind-all! taken 0)
                         (step! taken))
                       (raise 'interrupt)))))
                (lambda ()
                  (guard (e ((eq? e 'interrupt) 'interrupt)
                            (#t (list 'raised (what-raised e))))
                    (if (eq? where 'return) (set! armed #t) (set! armed-at-prepare #t))
                    ((call-run c) db)))
                (lambda ()
                  (set! armed #f)
                  (set! armed-at-prepare #f)
                  (keyboard-interrupt-handler old)
                  (trace-v2 handle 0 0 0)
                  (unlock-object profile))))
             (kept (and taken (attempt (lambda () (statement-state taken)))))
             (cached-while-taken (attempt (lambda () (database-cache-count db))))
             (given (and taken (attempt (lambda () (returned 'test-conveniences-pending taken)))))
             (tracked (attempt (lambda () (states db))))
             (cached (attempt (lambda () (database-cache-count db)))))
        (close-database! db)
        (list answer kept cached-while-taken tracked cached
              (if (equal? (native-counts) start) 'counts-kept (list 'counts start (native-counts)))))))
)
