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
;;; one only below the first fuel at which the sweep saw a trial refused, R
;;; taken before the call's first section (below).
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
;;; The bound: a trial's evidence tells two whole calls, its call's SQL
;;; prepared twice, its rows added twice, or query-fold's procedure called
;;; past one call's three rows, but not a whole new call from the same call
;;; run again, which is what a call that lost its claim or its flag would
;;; do. So the sweep bounds them by what it can tell itself: a remainder
;;; taken past the call's first expression and before its first section,
;;; nothing noted at its expiry, has its own second run refused,
;;; &sqlite-closed from the verb, once R1's has passed it. Each trial begins
;;; with a collection, so its first slice runs as every trial's at that
;;; fuel does, unless a collect request falls in it, and a remainder lies
;;; further into the call's first
;;; expressions at each fuel than at the one before; the sweep must meet
;;; such a refusal, refusals at half its fuels, and every whole new call
;;; must come at a fuel below the first. A collect request in a first slice
;;; costs the engine ticks there, so that remainder lies earlier than its
;;; fuel says: the bound reads only the trials whose first slice met none.
;;; A claim taken again once its call had ended made the whole window new
;;; calls, and passed the bound slice 5 used, the fuel at which the call
;;; refused at its first check completes, 72 for execute!, past the whole
;;; call's 42 (M3's closing review, reviewer B's N1). Until M4's closing
;;; review a control bounded a trial, the same call run at its fuel on a
;;; connection with no cache, which a low trip moved from the trial:
;;; AGENTS.md forbids a bound from a control run on the code under test
;;; (reviewer B's B2).
;;;
;;; Two passes: every sweep runs with no collect request in a trial, and
;;; under a collect trip of 256 bytes, where a request due inside a critical
;;; section is handled at its exit and costs the engine ticks there, so R1
;;; is taken at a section's exit too: a claim advanced just after its
;;; section, not inside it, inserted execute!'s row twice there (M4's
;;; closing review, reviewer B's B1). The low pass fails by name unless
;;; collect requests fell in its trials, unless some trial had R before the
;;; give-back and R1 past it, unless each section that SQLite's trace forces
;;; met its request before the next, which a trip slipped to 256 KiB does
;;; not, and unless some first slice expired at such a section's exit, which
;;; the high pass never does. The tell's authorizer forces each prepare's
;;; section too, and the script's low rows fail by name unless some trial
;;; had R before the call's first section, R1 at the first prepare's exit
;;; and R's second run refused there by the claim, which a claim set split
;;; from its compare would let prepare the statement again. The fold's low pass is a suite of its own,
;;; tests/test-conveniences-pending-fold-low.sps, and the script's four,
;;; tests/test-conveniences-pending-script-low-0.sps to -3.sps, each a
;;; quarter of its fuels: two halves took 167 and 169 s under the gate, past
;;; half its limit on CI's slower runners.
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
                collect collect-trip-bytes collect-request-handler set-timer timer-interrupt-handler
                keyboard-interrupt-handler foreign-entry? scheme-environment)
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
  ;; the prepare that called it (keyboard-in, below). In the low pass's
  ;; trials it forces the prepare's section, named prepare, as the trace
  ;; forces a step's (where a remainder lies, below).
  (define authorizer
    (foreign-callable __collect_safe
      (lambda (data action name value schema trigger)
        (set! force-source 'prepare)
        (force!)
        (set! force-source #f)
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
  ;; a trial under the memory gate a seventh less than two; the notes and the
  ;; fold's count cleared after.
  (define (fresh settings)
    (let ((db (open-database ":memory:" settings)))
      (tier-run db "create table t as select 1 as x union all select 2 union all select 3")
      (clear-notes!)
      (set! fold-rows (make-eq-hashtable))
      db))

  ;; fold-rows : (Hashtable Row #t)
  ;; The rows query-fold's procedure, counted-sum, was given since the last
  ;; fresh connection, each call's a fresh vector: so a call is counted by
  ;; its row, and a remainder taken inside the procedure, resumed again,
  ;; finishes that call and counts nothing, where a count of calls counted
  ;; it twice. One call's fold over t's three rows gives it three at most,
  ;; so more is two whole calls': a second fold run by one call, which
  ;; neither its prepares nor t's rows show (M4's closing review, builder
  ;; D's P-fold-left-after).
  (define fold-rows (make-eq-hashtable))

  ;; fold-calls : -> Natural
  (define (fold-calls) (hashtable-size fold-rows))

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

  ;; counted-sum : Integer Row -> Integer
  ;; sum, its row kept in fold-rows.
  (define (counted-sum acc row)
    (hashtable-set! fold-rows row #t)
    (sum acc row))

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
       (vector 'query-fold (lambda (db) (query-fold db select-sql counted-sum 0 0)) select-sql 'select 1
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
  ;; A collection now, at a trial's start, with collect-trip-bytes raised to
  ;; 128 MiB, far above what one trial's runs allocate, so no collect request
  ;; falls in a trial of the high pass (.plans/research/m3-slice-5/,
  ;; gc-ticks.sps).
  (define (quieted!)
    (collect-trip-bytes (expt 2 27))
    (collect))

  ;; slice : Engine Positive-Integer -> (U (List 'completed Any) (List 'expired Engine))
  ;; Each slice's forced sections are judged met or unmet.
  (define (slice e fuel)
    (slice-begun!)
    (let ((r (e fuel (lambda (left . vals) (list 'completed (car vals))) (lambda (more) (list 'expired more)))))
      (slice-ended!)
      r))

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

  ;; --- the two passes ------------------------------------------------------------------------
  ;; Pass = (U 'high 'low)
  ;; Each trial begins with begun!: quieted!'s collection, then PASS's trip.
  ;; In the high pass it stays at 2^27, so no collect request falls in a
  ;; trial. In the low pass it is 256 bytes, below what one call allocates,
  ;; until the trial ends: a request then falls due all through it, and one
  ;; due inside a critical section is handled at the section's exit, where it
  ;; costs the engine ticks, so an expiry can fall at a section's exit, past
  ;; the call's give-back among them (.plans/traps.md). A request fell only
  ;; where the call's allocation crossed a chunk, the same point at every fuel
  ;; once each trial collects first, so in the low pass each trial's
  ;; connection also carries SQLite's trace, whose callback allocates 32 KiB
  ;; as a step answers a row and as a statement finishes: inside the step,
  ;; and inside query-row's return. The tell's authorizer allocates 32 KiB
  ;; too, inside each prepare. Past 32 KiB a collect request always fell
  ;; inside a critical section under the low trip. Every request the trials
  ;; meet goes through counted-request, which counts it, and the low rows
  ;; judge where they fell (where a remainder lies, below).

  (define low-trip 256)

  ;; default-request-handler : (-> Any)
  (define default-request-handler (collect-request-handler))

  ;; requests : Natural
  ;; The collect requests the trials of the pass under way met.
  (define requests 0)

  (define (counted-request)
    (set! requests (+ requests 1))
    (default-request-handler)
    (exit-noted!))

  ;; --- where a remainder lies: at a forced section's exit ----------------------------------------
  ;; SQLite's trace calls back inside one of the library's critical sections,
  ;; once a section: each step that answers a row, the step that finishes a
  ;; statement, and query-row's return (the two passes, above).
  ;; In the low pass force! allocates 32 KiB there, so a collect request falls
  ;; due inside the section and is handled at its exit, the first event check
  ;; once the section enables interrupts again. The handler's own work costs
  ;; the engine ticks. Where they run out in it, the engine's timer reads #f
  ;; at its end, and the engine expires as the handler returns: the remainder
  ;; lies at that section's exit, before anything after it. A probe's marker,
  ;; set inside a section and overwritten just after it, read the section's
  ;; at exactly those fuels, three a section, at the low trip, and at none at
  ;; the high trip or at 256 KiB (M4's closing review, builder D's
  ;; exit-probe.sps). So a low row fails by name unless every forced section met
  ;; its request before the next forced section or its slice's end, which a
  ;; trip slipped to 256 KiB breaks, a 32 KiB allocation then meeting one
  ;; about one time in eight; and unless some first slice expired at a forced
  ;; section's exit, which the high pass, forcing none, never does. Each first
  ;; slice numbers the forced sections it passes, from 1, and the row shows
  ;; whose exits were met. The timer is read through Chez's own $tc-field,
  ;; reached through eval.

  ;; tc-field, tc : (U Procedure #f)
  (define tc-field
    (guard (e (#t #f))
      (eval (list (string->symbol "$primitive") (string->symbol "$tc-field")) (scheme-environment))))
  (define tc
    (guard (e (#t #f))
      (eval (list (string->symbol "$primitive") (string->symbol "$tc")) (scheme-environment))))

  ;; ticks-now : -> (U Natural #f)
  ;; The running engine's timer: its ticks left, #f once they are spent.
  (define (ticks-now) (and tc-field tc (tc-field 'timer-ticks (tc))))

  ;; ticks-spent? : -> Boolean
  (define (ticks-spent?) (and tc-field tc (not (ticks-now)) #t))

  ;; forcing : Boolean
  ;; Whether force! allocates: in the low pass's trials alone.
  (define forcing #f)

  ;; sink : Any
  ;; Where force!'s allocation is kept, so no compiler drops it.
  (define sink #f)

  ;; forced-pending : Boolean
  ;; A forced section's allocation made inside a slice, its request not yet
  ;; handled.
  (define forced-pending #f)

  ;; forced, unmet : Natural
  ;; The pass's forced sections inside an engine's slice, and those whose
  ;; request was not handled before the next forced section or the slice's
  ;; end. A forced callback whose timer reads as the last one's is in the same
  ;; section: an engine spends no ticks inside one, and one section can fire
  ;; two, as a close's finalizes do.
  (define forced 0)
  (define unmet 0)

  ;; slicing, numbering : Boolean
  ;; Whether an engine's slice runs now; whether a first slice does, numbering
  ;; the forced sections it passes.
  (define slicing #f)
  (define numbering #f)

  ;; forced-at : Any
  ;; The timer as the last forced section read it.
  (define forced-at 'none)

  ;; forced-k : Natural
  ;; The forced sections the first slice under way has passed.
  (define forced-k 0)

  ;; exit-k : (U Natural #f)
  ;; The forced section at whose exit the first slice's ticks ran out.
  (define exit-k #f)

  ;; force-source, forced-source, exit-source : (U Symbol #f)
  ;; What a suite's callback names the section it forces, set around its
  ;; force!; the last forced section's; and the one exit-k numbers.
  (define force-source #f)
  (define forced-source #f)
  (define exit-source #f)

  ;; pass-k, pass-exits : Natural (Listof Natural)
  ;; The most forced sections a first slice of the pass passed, and the
  ;; forced sections a first slice of it expired at the exit of.
  (define pass-k 0)
  (define pass-exits '())

  ;; force! : -> Void
  ;; In the low pass, 32 KiB allocated; inside a slice, a new section counted,
  ;; and numbered inside a first slice, the last one counted unmet if its
  ;; request is still due.
  (define (force!)
    (when forcing
      (when slicing
        (let ((t (ticks-now)))
          (unless (and forced-pending (eqv? t forced-at))
            (when forced-pending (set! unmet (+ unmet 1)))
            (set! forced (+ forced 1))
            (when numbering (set! forced-k (+ forced-k 1)))
            (set! forced-pending #t)
            (set! forced-at t)
            (set! forced-source force-source))))
      (set! sink (make-bytevector 32768))))

  ;; exit-noted! : -> Void
  ;; In the request handler, once a request is handled: the forced section's
  ;; request met; and, inside a first slice whose ticks it spent, where the
  ;; section's callback found the engine's timer running, the section's
  ;; number noted, the first so noted. An expiry's unwinding runs after
  ;; thunks, a ROLLBACK's step among them, with the timer already off: a
  ;; section forced there is no exit a remainder was taken at. The request
  ;; handled is the forced section's own, at its exit: a 32 KiB allocation
  ;; always met a request inside its section at a trip of 256 bytes, 100
  ;; times of 100 (chunk-probe.sps), so it is due as the section ends.
  (define (exit-noted!)
    (when forced-pending
      (set! forced-pending #f)
      (when (and numbering (not exit-k) (number? forced-at) (ticks-spent?))
        (set! exit-k forced-k)
        (set! exit-source forced-source))))

  ;; slice-begun!, slice-ended! : -> Void
  ;; Around each slice: at its end, a forced section's request still due
  ;; counted unmet.
  (define (slice-begun!)
    (set! forced-pending #f)
    (set! forced-at 'none)
    (set! slicing #t))
  (define (slice-ended!)
    (set! slicing #f)
    (when forced-pending
      (set! unmet (+ unmet 1))
      (set! forced-pending #f)))

  ;; expired-slice? : Any -> Boolean
  ;; Whether R, a slice's answer, is an expiry's: (expired E), or E itself.
  (define (expired-slice? r) (or (procedure? r) (and (pair? r) (eq? (car r) 'expired))))

  ;; first-slice : Engine Positive-Integer -> (U (List 'completed Any) (List 'expired Engine))
  ;; slice, its forced sections numbered and its exit noted for the pass.
  (define (first-slice e fuel)
    (set! forced-k 0)
    (set! exit-k #f)
    (set! exit-source #f)
    (set! numbering #t)
    (let ((r (slice e fuel)))
      (set! numbering #f)
      (set! pass-k (max pass-k forced-k))
      (when (and exit-k (expired-slice? r) (not (memv exit-k pass-exits)))
        (set! pass-exits (cons exit-k pass-exits)))
      r))

  ;; Tally = (List Natural Natural Natural Natural (Listof Natural))
  ;; A pass's collect requests, its forced sections, those unmet, the most a
  ;; first slice passed, and those a first slice expired at the exit of.

  ;; pass-reset! : -> Void
  (define (pass-reset!)
    (set! requests 0)
    (set! forced 0)
    (set! unmet 0)
    (set! pass-k 0)
    (set! pass-exits '())
    (set! forced-pending #f))

  ;; pass-tally : -> Tally
  (define (pass-tally) (list requests forced unmet pass-k (list-sort < pass-exits)))

  ;; low-judged : Tally -> (Listof Any)
  ;; low-checks' three, each failing by name.
  (define (low-judged tally)
    (let ((met (car tally)) (forced (cadr tally)) (unmet (caddr tally)) (exits (list-ref tally 4)))
      (list (if (> met 0) 'collect-requests-met (list 'no-collect-request-met met))
            (if (and (> forced 0) (= unmet 0))
                'every-forced-section-met-its-request
                (list 'forced-sections forced 'unmet unmet))
            (if (pair? exits) 'taken-at-a-forced-exit (list 'none-taken-at-a-forced-exit exits)))))

  ;; low-checks : (Listof Symbol)
  (define low-checks '(collect-requests-met every-forced-section-met-its-request taken-at-a-forced-exit))

  ;; tally-shown : Tally -> Void
  (define (tally-shown tally)
    (display "; collect requests met ")
    (write (car tally))
    (display "; forced sections ")
    (write (cadr tally))
    (display ", unmet ")
    (write (caddr tally))
    (display "; a first slice's forced sections ")
    (write (cadddr tally))
    (display ", remainders at the exit of ")
    (write (list-ref tally 4)))


  ;; begun! : Pass -> Void
  (define (begun! pass)
    (quieted!)
    (collect-request-handler counted-request)
    (set! forcing (eq? pass 'low))
    (when (eq? pass 'low) (collect-trip-bytes low-trip)))

  ;; ended! : -> Void
  (define (ended!)
    (set! forcing #f)
    (collect-trip-bytes (expt 2 27))
    (collect-request-handler default-request-handler))

  ;; traced! : Database -> Void
  ;; DB given the trace, a row's and a finish's, its answer required 0.
  (define (traced! db)
    (let ((rc (call-with-open-handle 'test-conveniences-pending db
                (lambda (h) (trace-v2 h (+ sqlite-trace-profile sqlite-trace-row)
                                      (foreign-callable-entry-point profile) 0)))))
      (unless (eqv? rc 0) (error 'traced! "sqlite3_trace_v2 did not answer 0" rc))))

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

  ;; rows-allowed? : Call Any -> Boolean
  ;; Whether ROWS, t's after a trial, in order, are 1, 2 and 3, then what one
  ;; call of C adds, or what two add, merged in order: two a whole new call's,
  ;; which the sweep bounds.
  (define (rows-allowed? c rows)
    (and (list? rows) (>= (length rows) 3) (prefix? '(1 2 3) rows)
         (let ((tail (list-tail rows 3)) (ones (made-by-one c)))
           (or (exists (lambda (one) (equal? tail one)) ones)
               (exists (lambda (a)
                         (exists (lambda (b) (equal? tail (list-sort < (append a b)))) ones))
                       ones)))))

  ;; prepares-allowed? : Call Natural -> Boolean
  ;; Whether N, the authorizer's count of the trial's prepares, is one call's:
  ;; its statement once, for the four that use the cache; for the script,
  ;; each of its statements at most once, none at all where an expiry inside
  ;; its block freed the block before the first; or twice that, a whole new
  ;; call's, whose first run may find the other's statement cached.
  (define (prepares-allowed? c n)
    (let ((most (call-prepares c)))
      (if (call-sql c)
          (or (= n most) (= n (* 2 most)))
          (<= n (* 2 most)))))

  ;; two-calls? : Call Natural Any -> Boolean
  ;; Whether the trial's evidence shows two whole calls: more prepares than
  ;; one call makes, more rows than one adds, or, for query-fold, its
  ;; procedure called past one call's three rows.
  (define (two-calls? c prepares rows)
    (or (> prepares (call-prepares c))
        (and (list? rows) (>= (length rows) 3) (> (length (list-tail rows 3)) (length (call-adds c))))
        (and (eq? (call-name c) 'query-fold) (> (fold-calls) 3))))

  ;; judged : Call (Listof Any) Natural Database Counts (Listof Boolean) -> (List (Listof Any) Boolean)
  ;; RUNS' answers judged by the trial itself, PREPARES the authorizer's count
  ;; for it, DB its connection, then closed; START the counts when it began;
  ;; CAPTURES whether each run lay past the give-back. What deviated, and
  ;; whether its evidence shows two whole calls, which the sweep bounds.
  (define (judged c runs prepares db start captures)
    (let* ((rows (attempt (lambda () (tier-run db "select x from t order by x"))))
           (tracked (attempt (lambda () (states db))))
           (cached (attempt (lambda () (database-cache-count db))))
           (cleared (attempt (lambda () (bindings-cleared? c db))))
           (closed (attempt (lambda () (close-database! db) 'closed)))
           (counts (native-counts))
           (two (two-calls? c prepares rows))
           (deviations '()))
      (define (deviate! d) (set! deviations (cons d deviations)))
      ;; each run answers the call's answer, or a refusal
      (let loop ((rest runs))
        (unless (null? rest)
          (unless (member (car rest) (call-answers c)) (deviate! (list 'answer (car rest))))
          (loop (cdr rest))))
      ;; made once, and its effect once; twice for a whole new call
      (unless (prepares-allowed? c prepares) (deviate! (list 'prepares prepares)))
      (unless (rows-allowed? c rows) (deviate! (list 'rows rows)))
      (when (and (eq? (call-name c) 'query-fold) (> (fold-calls) 6)) (deviate! (list 'fold-calls (fold-calls))))
      ;; nothing out of the cache, nothing at a row, the cache as one clean call leaves it
      (unless (or (and (equal? tracked (clean-tracked c)) (eqv? cached (length tracked)))
                  (and (not (call-survives? c)) (equal? tracked '()) (eqv? cached 0)))
        (deviate! (list 'left tracked cached)))
      (unless (eq? cleared #t) (deviate! (list 'bindings cleared)))
      ;; a failing call: the failure raised by one run, and again by each run
      ;; taken past the call's give-back; every other run refused
      (when (and (call-fails? c) (not (= prepares (* 2 (call-prepares c)))))
        (let ((failures (length (filter (lambda (a) (equal? a (car (call-answers c)))) runs)))
              (past (length (filter (lambda (x) x) captures))))
          (unless (= failures (if (> past 0) past 1))
            (deviate! (list 'failures failures 'past-the-give-back past)))))
      (unless (eq? closed 'closed) (deviate! (list 'close closed)))
      (unless (equal? counts start) (deviate! (list 'counts start counts)))
      (list (reverse deviations) two)))

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
  ;; the authorizer having noted its prepare, and none out of the cache:
  ;; given back to it, or finalized. A failed statement is finalized at its
  ;; return, so for query-failing it is the run's last section.
  (define (past-the-give-back? c db)
    (and (>= (noted-count (call-kind c)) (call-prepares c))
         (= (database-cache-count db) (length (tracked-statements db)))))

  ;; refusal? : Call Any -> Boolean
  ;; Whether ANSWER is one of C's refusals: &sqlite-closed from the verb, or
  ;; a library wind's refusal of a re-entry.
  (define (refusal? c answer)
    (and (member answer (cdr (call-answers c))) #t))

  ;; Judged = (List Symbol Boolean Boolean (Listof Any) Boolean Boolean Boolean Boolean Boolean)
  ;; A trial's kind, completed when R's first slice completed the call, last
  ;; when R's resume completed within G, else interleaved; whether it was
  ;; past the first section, R1 taken after the call had made it; whether
  ;; both were, R taken after it too; what deviated; whether its evidence
  ;; shows two whole calls; whether a run was refused; whether R's own
  ;; second run was refused, &sqlite-closed from the verb, R taken before the
  ;; first section, nothing noted at its expiry, the sweep's bound; whether R
  ;; lay before the give-back and R1 past it; and whether no collect request
  ;; fell in R's first slice, so the sweep's bound reads it.

  ;; prepare-straddles : Natural
  ;; The interleaved trials of the sweep under way whose R lay before the
  ;; call's first section, whose R1 was taken at the exit of the first
  ;; section R's resume forced, a prepare, and whose R's second run was
  ;; refused, &sqlite-closed from the verb: so that run reached the first
  ;; prepare once R1's had made it, and its claim refused it. A claim whose
  ;; set is split from its compare, even inside the section, lets that run
  ;; prepare the statement again, which the trial reads as two calls: the
  ;; authorizer's request is handled where interrupts are first enabled
  ;; after it, there or at the section's exit (M4's closing review, the M4
  ;; session's recheck).
  (define prepare-straddles 0)

  ;; trial : Pass Call Positive-Integer Positive-Integer -> Judged
  ;; One trial of C at FUEL, R resumed at G, in PASS.
  (define (trial pass c fuel g)
    (begun! pass)
    (let* ((start (native-counts))
           (db (fresh '()))
           (kind (call-kind c))
           (traced (when (eq? pass 'low) (traced! db)))
           (met requests)
           (r (first-slice (make-engine (thunk-of c db)) fuel))
           (clean (= requests met))
           (j (if (eq? (car r) 'completed)
                  (let ((v (judged c (list (cadr r)) (noted-count kind) db start '(#f))))
                    (list 'completed #f #f (car v) (cadr v) #f #f #f))
                  (let* ((R (cadr r))
                         (r-past (> (noted-count kind) 0))
                         (r-given (past-the-give-back? c db))
                         (r1 (first-slice R g))
                         (r1-at-prepare (and (eqv? exit-k 1) (eq? exit-source 'prepare))))
                    (if (eq? (car r1) 'completed)
                        (let* ((again (finish R))
                               (v (judged c (list (cadr r1) again) (noted-count kind) db start
                                          (list r-given r-given))))
                          (list 'last #f #f (car v) (cadr v)
                                (or (refusal? c (cadr r1)) (refusal? c again))
                                (and (not r-past) (equal? again (cadr (call-answers c))))
                                #f))
                        (let* ((R1 (cadr r1))
                               (r1-past (> (noted-count kind) 0))
                               (r1-given (past-the-give-back? c db))
                               (second (finish R))
                               (third (finish R1))
                               (v (judged c (list second third) (noted-count kind) db start
                                          (list r-given r1-given))))
                          (when (and r1-at-prepare (not r-past) (equal? second (cadr (call-answers c))))
                            (set! prepare-straddles (+ prepare-straddles 1)))
                          (list 'interleaved r1-past r-past (car v) (cadr v)
                                (or (refusal? c second) (refusal? c third))
                                (and (not r-past) (equal? second (cadr (call-answers c))))
                                (and (not r-given) r1-given))))))))
      (ended!)
      (append j (list clean))))

  ;; --- the sweep ----------------------------------------------------------------------------

  ;; Sweep = (List Any Natural Natural Natural (Listof Any) (Listof Natural) Counts (U Natural #f) Natural Natural Natural)
  ;; The fuel at which the call completes without expiring, or
  ;; no-completion-by-20000; how many trials interleaved, R1 existing; how
  ;; many of those were past the call's first section, and how many both
  ;; past it; each trial's deviations, with its fuels; the fuels of the
  ;; trials whose evidence showed two whole calls, no collect request in
  ;; their first slice; the counts once the sweep is done; the first fuel at
  ;; which a trial was refused, R taken before the call's first section, #f
  ;; for none; how many fuels saw a refusal; the trials with R before the
  ;; give-back and R1 past it; and those with two whole calls left out of
  ;; the bound, a collect request in their first slice.

  ;; Parity = (U 'every 'odd 'even (List 'mod Positive-Integer Natural))
  ;; sweep : Symbol Parity Pass -> Sweep
  ;; VERB's call swept in PASS: at every fuel from 1 until the call completes
  ;; without expiring, trial at every G from 1 until R's resume completes
  ;; within it. With PARITY odd or even, only the fuels of that parity run
  ;; every G; the others run G = 1 alone, which tells whether the call
  ;; completes there. So two suites of the two parities sweep every trial
  ;; between them (the script's, which one suite could not hold well under
  ;; the memory gate's limit). With PARITY (mod M K), only the fuels whose
  ;; remainder by M is K run every G: the script's low pass, half again as
  ;; costly as its high one, runs in four suites, K from 0 to 3. Each trial is judged by what it saw itself,
  ;; and a whole new call is bounded by the sweep's own refusals: until M4's
  ;; closing review a trial was judged by a control, the same call run at its
  ;; fuel on a connection with no cache, which AGENTS.md forbids and which a
  ;; low trip moved from the trial (reviewer B's B2).
  (define (sweep verb parity pass)
    (let ((c (call-of verb)))
      (define (every-g? fuel)
        (cond ((pair? parity) (= (mod fuel (cadr parity)) (caddr parity)))
              ((eq? parity 'odd) (odd? fuel))
              ((eq? parity 'even) (even? fuel))
              (else #t)))
      (let floop ((fuel 1) (trials 0) (past 0) (both 0) (deviations '()) (news '()) (refused-at #f)
                  (refused-fuels 0) (straddle 0) (moved 0))
        (let gloop ((g 1) (trials trials) (past past) (both both) (deviations deviations) (news news)
                    (refused-at refused-at) (seen #f) (straddle straddle) (moved moved))
          (let* ((t (trial pass c fuel g))
                 (kind (car t))
                 (deviations (if (null? (cadddr t)) deviations
                                 (cons (list fuel g (cadddr t)) deviations)))
                 (two (list-ref t 4))
                 (clean (list-ref t 8))
                 (news (if (and two clean) (cons fuel news) news))
                 (moved (if (and two (not clean)) (+ moved 1) moved))
                 (seen (or seen (list-ref t 5)))
                 (refused-at (or refused-at (and (list-ref t 6) fuel)))
                 (straddle (if (list-ref t 7) (+ straddle 1) straddle))
                 (interleaved (eq? kind 'interleaved))
                 (trials (if interleaved (+ trials 1) trials))
                 (past (if (and interleaved (cadr t)) (+ past 1) past))
                 (both (if (and interleaved (caddr t)) (+ both 1) both)))
            (cond ((eq? kind 'completed)
                   (list fuel trials past both (reverse deviations) (reverse news) (native-counts)
                         refused-at refused-fuels straddle moved))
                  ((>= fuel 20000)
                   (list 'no-completion-by-20000 trials past both (reverse deviations) (reverse news)
                         (native-counts) refused-at refused-fuels straddle moved))
                  ((or (eq? kind 'last) (not (every-g? fuel)))
                   (floop (+ fuel 1) trials past both deviations news refused-at
                          (if seen (+ refused-fuels 1) refused-fuels) straddle moved))
                  (else (gloop (+ g 1) trials past both deviations news refused-at seen straddle
                               moved))))))))

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

  ;; past-the-bound : (Listof Natural) (U Natural #f) -> (Listof Natural)
  ;; The distinct fuels among NEWS at or past REFUSED-AT, every one when it
  ;; is #f, in order: a failing row's evidence.
  (define (past-the-bound news refused-at)
    (let loop ((rest news) (found '()))
      (cond ((null? rest) (reverse found))
            ((and (or (not refused-at) (>= (car rest) refused-at)) (not (memv (car rest) found)))
             (loop (cdr rest) (cons (car rest) found)))
            (else (loop (cdr rest) found)))))

  ;; reported : Symbol Parity Pass Natural (U Natural 'none) -> (Listof Any)
  ;; VERB's sweep of PARITY in PASS, printed, and judged: its deviations,
  ;; summarized; whether its interleaved trials past the call's first
  ;; section reached PAST-A-FUEL a fuel on average, and those both past it
  ;; BOTH-A-FUEL, or none at all where it is none, over the fuels up to the
  ;; one at which the call completes: a sweep that reused one R across every
  ;; G, its every trial after G = 1 refused at once, makes at most one trial
  ;; a fuel (the lead's, slice 5's part D); refusals at half the fuels at
  ;; least, a third for query-failing, whose runs past the give-back raise
  ;; its failure again rather than be refused; every whole new call, of a
  ;; trial whose first slice met no collect
  ;; request, below the first fuel at which a trial was refused, R taken
  ;; before the call's first section; in the low pass, R before the
  ;; give-back and R1 past it in some trial, and low-judged's three; and the
  ;; counts once it was done.
  (define (reported verb parity pass past-a-fuel both-a-fuel)
    (pass-reset!)
    (set! prepare-straddles 0)
    (let* ((run (dynamic-wind (lambda () (lock-object profile)) (lambda () (sweep verb parity pass))
                              (lambda () (ended!) (unlock-object profile))))
           (tally (pass-tally)))
      (let ((fuel (list-ref run 0)) (trials (list-ref run 1)) (past (list-ref run 2))
            (both (list-ref run 3)) (deviations (list-ref run 4)) (news (list-ref run 5))
            (refused-at (list-ref run 7)) (refused-fuels (list-ref run 8)) (straddle (list-ref run 9))
            (moved (list-ref run 10)))
        (display "  ")
        (display verb)
        (when (eq? pass 'low) (display ", low trip"))
        (display ": completed without expiring at fuel ")
        (write fuel)
        (display "; trials with R1 ")
        (write trials)
        (display "; past the first section ")
        (write past)
        (display "; both past it ")
        (write both)
        (display "; fuels seeing a refusal ")
        (write refused-fuels)
        (display "; R before the give-back and R1 past it in ")
        (write straddle)
        (display "; whole new calls ")
        (write (length news))
        (display ", the last at fuel ")
        (write (if (null? news) 0 (apply max news)))
        (display ", below the first refusal before the call's first section, at fuel ")
        (write refused-at)
        (display "; left out, a collect request in the first slice, ")
        (write moved)
        (when (eq? verb 'execute-script!)
          (display "; R before the first section, R1 at the first prepare's exit and R's second run refused in ")
          (write prepare-straddles))
        (tally-shown tally)
        (newline)
        (unless (null? deviations)
          (display "    deviations by kind: ")
          (write (tallied deviations))
          (newline))
        (append
         (list (if (integer? fuel) (summarized deviations) (list fuel (summarized deviations)))
               (if (and (integer? fuel) (>= past (* past-a-fuel fuel))
                        (if (eq? both-a-fuel 'none) (= both 0) (>= both (* both-a-fuel fuel))))
                   'interleavings-reached
                   (list 'too-few-interleavings 'past past 'both both 'fuel fuel))
               (cond ((not (integer? fuel)) (list 'refused-fuels refused-fuels 'over fuel))
                     ((call-fails? (call-of verb))
                      (if (>= (* 3 refused-fuels) fuel)
                          'refused-at-a-third-of-the-fuels
                          (list 'refused-fuels refused-fuels 'over fuel)))
                     ((>= (* 2 refused-fuels) fuel) 'refused-at-half-the-fuels)
                     (else (list 'refused-fuels refused-fuels 'over fuel)))
               (if (and refused-at (for-all (lambda (f) (< f refused-at)) news))
                   'whole-new-calls-below-a-refusal
                   (list 'whole-new-calls-not-below-a-refusal (past-the-bound news refused-at) refused-at)))
         (if (eq? pass 'low)
             (cons (if (> straddle 0) 'straddled-the-give-back (list 'none-straddling-the-give-back straddle))
                   (append (if (eq? verb 'execute-script!)
                               (list (if (> prepare-straddles 0)
                                         'refused-at-a-prepare-r1-made
                                         (list 'refused-at-a-prepare-r1-made prepare-straddles)))
                               '())
                           (low-judged tally)))
             '())
         (list (list-ref run 6))))))

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
  ;; In the low pass's sweeps force! also allocates 32 KiB, so a collect
  ;; request falls due inside the section that steps the statement (the two
  ;; passes, above).
  (define profile
    (foreign-callable __collect_safe
      (lambda (mask ctx p x)
        (force!)
        (when (and armed c-raise) (set! armed #f) (c-raise sigint))
        0)
      (unsigned-32 uptr uptr uptr) int))

  ;; int sqlite3_trace_v2(sqlite3*, unsigned uMask, int(*xCallback)(...), void *pCtx)
  (define trace-v2
    (bound 'sqlite3_trace_v2 (foreign-procedure "sqlite3_trace_v2" (uptr unsigned-32 uptr uptr) int)))

  ;; sqlite-trace-profile, sqlite-trace-row : Natural
  ;; SQLITE_TRACE_PROFILE and SQLITE_TRACE_ROW, the trace's masks for a
  ;; statement's finish and a step's row.
  (define sqlite-trace-profile 2)
  (define sqlite-trace-row 4)

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
