#!r6rs
;;; The suite for one open's runs interleaved (ADR-0018, consequences;
;;; ADR-0016), in (chez-sqlite3 private open). Chez's engine remainders are
;;; multi-shot: R, one remainder of a call, resumed until it expires again, is
;;; R1, and R can then be resumed again while R1 is pending. Each run of the
;;; call goes on from where its remainder was taken.
;;;
;;;   interleaved  open-database, then call-with-database, with two settings
;;;                on :memory:, as an engine: R taken at every fuel from 1
;;;                until the call completes without expiring; R resumed at
;;;                every later fuel until that resume completes, R1 taken
;;;                where it expires; then R resumed again to its end, then
;;;                R1. Where R's resume completes, R is resumed once more
;;;                instead. After every trial:
;;;                  - each run answers a database, or the procedure's
;;;                    answer, or &sqlite-closed, refused; or, inside the
;;;                    procedure, its own call-with-open-handle's refusal
;;;                    of a re-entry, or &sqlite-closed, the connection
;;;                    closed by the expiry;
;;;                  - a refused run opened nothing, prepared nothing and
;;;                    changed no count, so touched nothing another run
;;;                    owns;
;;;                  - every connection opened was answered, or, for
;;;                    call-with-database, is closed; once those answered
;;;                    are closed, nothing is counted;
;;;                  - each setting was applied once: every connection's
;;;                    settings statements, as an authorizer saw them
;;;                    prepared, are the plan's, in its order, none twice,
;;;                    and all of them on a connection a run answered;
;;;                  - an answered connection tracks no statement, and reads
;;;                    each setting back as asked.
;;;                Two connections, a whole new call each, come only from a
;;;                remainder taken before the call's first expression: only
;;;                below the first fuel at which a trial of the sweep was
;;;                refused, R taken before the open (below).
;;;   a failing    open-database, then call-with-database, with busy-timeout
;;;   open twice   and journal-mode wal on :memory:, which mismatches,
;;;                journal_mode reading memory, at every fuel from 1 until
;;;                the call completes without expiring: the remainder
;;;                resumed to its end raises the mismatch, the connection
;;;                closed; resumed again, it is refused with &sqlite-closed,
;;;                always when the connection was open at the expiry, or,
;;;                past the failure's close, raises the mismatch again,
;;;                either way noting nothing and changing no count; only
;;;                below the first fuel at which the sweep saw one refused, R
;;;                taken before the open, does it open a connection, a whole
;;;                new call's, which mismatches the same, alone. Every
;;;                connection's PRAGMAs are a prefix of the plan, none twice,
;;;                and nothing is counted after
;;;   an escape    call-with-database, SIGINT raised inside each of its
;;;                sections in turn, from the callbacks: Chez handles a
;;;                keyboard interrupt that came pending inside a critical
;;;                section as the section ends, before the next expression,
;;;                and the handler leaves the call: the extent closes the
;;;                connection each time, no later section runs, and nothing is
;;;                counted. An engine and a timer spend no ticks inside a
;;;                section, so only such an interrupt reaches the end of the
;;;                open's section before the connection is recorded
;;;   two passes   the interleaved and failing rows twice: with no collect
;;;                request in a trial, and under a collect trip of 256 bytes,
;;;                where a request due inside a critical section is handled at
;;;                its exit and costs the engine ticks there, so a remainder is
;;;                taken at a section's exit too, before anything after it: a
;;;                claim advanced just after its section, not inside it,
;;;                applied a setting twice there. The tell's callbacks
;;;                allocate 32 KiB inside the open's section and each
;;;                setting's prepare, so a request falls due there. The low
;;;                pass fails by name unless collect requests fell in its
;;;                trials, unless each forced section met its request before
;;;                the next, which a trip slipped to 256 KiB does not, and
;;;                unless some first slice expired at a forced section's exit,
;;;                which the high pass never does; and each interleaved low
;;;                row unless some trial had R before the call's last section
;;;                and R1 past it
;;;
;;; The tell: sqlite3_auto_extension runs an entry point of this suite at
;;; every open, which notes the open and sets an authorizer on the new
;;; connection. SQLite calls the authorizer at every prepare, and a setting
;;; takes effect at its prepare, so each PRAGMA prepared is noted, its
;;; connection, its name and its value, none for a read. Both callbacks are
;;; __collect_safe: SQLite calls them inside sqlite3_open_v2 and
;;; sqlite3_prepare_v3, which are. They answer data and raise nothing. The
;;; entry point is unregistered, and both unlocked, at the end. A libsqlite3
;;; can refuse the registration: Apple's 3.51.0 answers 21, SQLITE_MISUSE, for
;;; an entry point upstream takes. With no tell, nothing is noted, and nothing
;;; is unavailable silently (ADR-0005): a row whose every check needs the
;;; tell, or that raises SIGINT from the callbacks, goes through
;;; tell-available!, which prints UNAVAILABLE and skips it; a row with checks
;;; that read the notes goes through tell-kept?, which prints UNAVAILABLE for
;;; them, and the row runs its others. The gate is held by an independent
;;; reading: before the tell registers, an entry point that does nothing is
;;; registered straight through the FFI and the list reset, and a row requires
;;; the gate to refuse exactly when that answered 21.
;;;
;;; Which fuels lie before the call's first expression is measured, not
;;; assumed, and by the sweep itself: a remainder taken past the call's first
;;; expression and before the open, no open noted at its expiry, is refused
;;; at the open's section when another run of the call has opened, opening
;;; nothing, and the sweep must meet such a refusal, at half its fuels at
;;; least, and make every whole new call, two connections opened, below the
;;; first fuel at which it met one. A refused call's completing fuel is no
;;; bound: an open's sections spend no ticks, so the open and its settings
;;; span fewer fuels than the refusal's raise. Each trial begins with a
;;; collection, so its first slice runs as every trial's at that fuel does,
;;; unless a collect request falls in it, which the bound sets aside (below),
;;; and a remainder lies further into the call's first expressions at each
;;; fuel than at the one before. A bound from a control run on the code under
;;; test, the same call run at its fuel, would move with the low trip: each
;;; trial is judged by what it saw itself.
;;;
;;; An engine spends no ticks inside a critical section, so the fuels measure
;;; the Scheme work between the open's sections. The loading procedures are
;;; reached through eval, under a guard, as tests/test-statement.sps reaches
;;; them.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) make-engine foreign-procedure foreign-callable
              foreign-callable-entry-point lock-object unlock-object foreign-ref
              foreign-entry? keyboard-interrupt-handler collect collect-trip-bytes
              collect-request-handler scheme-environment)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-closed? sqlite-setting-mismatch?
              sqlite-setting-mismatch-setting sqlite-setting-mismatch-expected
              sqlite-setting-mismatch-actual))

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
(define database? (public 'database?))
(define query-row (public 'query-row))
(define tracked-statements (reach '(chez-sqlite3 private connection) 'tracked-statements))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define made-claim (reach '(chez-sqlite3 private open) 'made-claim))

;; --- the tell: an authorizer on every connection -------------------------------------------

;; noted : (Listof (U (List 'open Natural) (List 'pragma Natural String (U String #f))))
;; What the callbacks noted, newest first: each open, its handle; each PRAGMA
;; prepared, its connection's handle, its name and its value, #f for none.
(define noted '())

;; interrupt-at : (U Natural #f)
;; When a number, the callbacks raise SIGINT once that many events are
;; noted, inside the section whose open or prepare made the last; Chez
;; handles the keyboard interrupt as that section ends (the row below).
(define interrupt-at #f)

;; sigint : Integer
;; SIGINT, 2 on Linux and macOS.
(define sigint 2)

(define (note! event)
  (set! noted (cons event noted))
  (when (and interrupt-at c-raise (= (length noted) interrupt-at))
    (set! interrupt-at #f)
    (c-raise sigint)))

;; c-text : Natural -> (U String #f)
;; The NUL-terminated text at P, a byte a character, or #f for NULL: the
;; names SQLite hands the authorizer are ASCII. Raises nothing.
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
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; sqlite-pragma : Natural
;; SQLITE_PRAGMA, the authorizer's action code for a PRAGMA.
(define sqlite-pragma 19)

;; int (*xAuth)(void *pUserData, int action, const char *, const char *, const char *, const char *)
;; pUserData is the connection's handle, given when the authorizer is set.
(define authorizer
  (foreign-callable __collect_safe
    (lambda (data action name value schema trigger)
      (force!)
      (when (eqv? action sqlite-pragma)
        (note! (list 'pragma data (c-text name) (c-text value))))
      0)
    (uptr int uptr uptr uptr uptr) int))

;; int sqlite3_set_authorizer(sqlite3*, int (*xAuth)(...), void *pUserData)
(define set-authorizer
  (bound 'sqlite3_set_authorizer (foreign-procedure "sqlite3_set_authorizer" (uptr uptr uptr) int)))

;; int (*xEntryPoint)(sqlite3 *db, const char **pzErrMsg, const sqlite3_api_routines *pThunk)
(define entry-point
  (foreign-callable __collect_safe
    (lambda (db message api)
      (force!)
      (note! (list 'open db))
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

;; c-raise : (U (Integer -> Integer) #f)
;; C's int raise(int sig), resolved through the libc libsqlite3 loaded; #f
;; when it is missing, so the callbacks never call a procedure that raises,
;; and the escape row fails instead.
(define c-raise
  (guard (e (#t #f))
    (and (foreign-entry? "raise") (foreign-procedure "raise" (int) int))))

;; int (*xEntryPoint)(sqlite3 *db, const char **pzErrMsg, const sqlite3_api_routines *pThunk)
;; An entry point that does nothing, for direct.
(define idle-entry-point
  (foreign-callable __collect_safe
    (lambda (db message api) 0)
    (uptr uptr uptr) int))

;; direct : (U Integer (List 'raised Any))
;; What sqlite3_auto_extension answers for idle-entry-point registered
;; straight through the FFI, with nothing of the tell's between, then
;; unregistered by sqlite3_reset_auto_extension: the gate's independent
;; reading. Made before registered, since the reset unregisters every entry
;; point; the callable locked while registered and unlocked once after.
(define direct
  (guard (e (#t (list 'raised (describe e))))
    (lock-object idle-entry-point)
    (let ((rc (auto-extension (foreign-callable-entry-point idle-entry-point))))
      (reset-auto-extension)
      (unlock-object idle-entry-point)
      rc)))

;; registered : (U 'registered (List 'auto-extension-answered Integer) (List 'raised Any))
;; The entry point registered, the two callbacks locked, for every new
;; connection; or the code sqlite3_auto_extension answered instead. The
;; callbacks stay locked then, never called: Chez 10.4.0's unlock of an
;; object not locked still decrements its segment's count, which can unpin
;; another object there.
(define registered
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

;; tell-refused? : Any -> Boolean
;; Whether ANSWER, registered's, is the refusal.
(define (tell-refused? answer)
  (equal? answer (list 'auto-extension-answered sqlite-misuse)))

;; tell-answered? : Any -> Boolean
;; Whether ANSWER, registered's, is registered, or the refusal: not another
;; code, a raise, nor anything else.
(define (tell-answered? answer)
  (or (eq? answer 'registered) (tell-refused? answer)))

;; unavailable! : Any String (U String #f) -> Boolean
;; Whether ANSWER, registered's, is the refusal; then the row NAME, or its
;; CHECK, the one part that reads the tell, is printed unavailable, so it is
;; never passed unseen (ADR-0005). The one place both gates below decide.
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
;; registered's, is the refusal, the row is printed unavailable and
;; skipped, never passed. Anything else runs it.
(define (tell-available! answer name)
  (when (unavailable! answer name #f)
    (test-skip name)))

;; tell-kept? : Any String String -> Boolean
;; The gate of CHECK, the one part of the row NAME that reads the tell: #f
;; where ANSWER, registered's, is the refusal, CHECK printed unavailable,
;; the row's other checks run; else #t, every check run.
(define (tell-kept? answer name check)
  (not (unavailable! answer name check)))

;; tell-noted : Boolean Any -> Any
;; VALUE, read from the callbacks' notes, where its check is KEPT?; else
;; the symbol unavailable. A row puts it in its expected value and its
;; actual alike, so it asserts the rest of its output whole.
(define (tell-noted kept? value)
  (if kept? value 'unavailable))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
(define (what-raised e)
  (cond ((sqlite-setting-mismatch? e)
         (list 'mismatch (who-of e) (sqlite-setting-mismatch-setting e)
               (sqlite-setting-mismatch-expected e) (sqlite-setting-mismatch-actual e)))
        ((sqlite-error? e)
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

(define (a-database? x) (guard (e (#t #f)) (database? x)))

(define (close-answer r)
  (guard (e (#t #f)) (close-database! r)))

;; handle-of : Database -> (U Natural (List 'raised Any))
(define (handle-of db)
  (attempt (lambda () (call-with-open-handle 'test-open-interleave db (lambda (h) h)))))

;; pragma : Database String -> Any
(define (pragma db name)
  (let ((row (query-row db (string-append "PRAGMA " name))))
    (if (vector? row) (vector-ref row 0) (list 'no-row row))))

;; summarized : (Listof Any) -> Any
;; () for no deviation; else how many, and the first three.
(define (summarized deviations)
  (if (null? deviations)
      '()
      (list (length deviations)
            (let loop ((rest deviations) (n 0) (kept '()))
              (if (or (null? rest) (= n 3)) (reverse kept) (loop (cdr rest) (+ n 1) (cons (car rest) kept)))))))

;; --- engines ------------------------------------------------------------------------------

;; quieted! : -> Void
;; A collection now, at a trial's start, with collect-trip-bytes raised to
;; 128 MiB, far above what one trial's runs allocate, so no collect request
;; falls in a trial of the high pass: a request costs a run up to a tick,
;; and more than one can cost two.
(define (quieted!)
  (collect-trip-bytes (expt 2 27))
  (collect))

;; Pass = (U 'high 'low)
;; Each trial begins with begun!: quieted!'s collection, then PASS's trip.
;; In the high pass it stays at 2^27, so no collect request falls in a
;; trial. In the low pass it is 256 bytes, below what one call allocates,
;; until the trial ends: a request then falls due all through it, and one
;; due inside a critical section is handled at the section's exit, where it
;; costs the engine ticks, so an expiry can fall at a section's exit, before
;; anything after it. Every request the trials meet goes through
;; counted-request, which counts it, and the low rows judge where they fell
;; (where a remainder lies, below).

(define low-trip 256)

;; default-request-handler : (-> Any)
(define default-request-handler (collect-request-handler))

;; requests : Natural
;; The collect requests the trials of the pass under way met.
(define requests 0)

;; A request in a run before its expiry costs the engine ticks there, so
;; that run's remainder lies earlier in the call than its fuel says: a whole
;; new call came at the fuel at which a trial was refused, R before the open,
;; where a request fell in its first slice. So each trial notes whether a
;; request fell in its first slice, and the sweep's bound on a whole new call
;; reads only the trials where none did; a whole new call where one did is
;; counted and printed, and judged by its other evidence. The bound's refusal
;; may come from any trial: a request moves a remainder earlier, never later.

(define (counted-request)
  (set! requests (+ requests 1))
  (default-request-handler)
  (exit-noted!))

;; --- where a remainder lies: at a forced section's exit ----------------------------------------
;; The tell's callbacks run inside the library's critical sections: the entry
;; point inside sqlite3_open_v2, the open's section, and the authorizer inside
;; each setting's prepare (the tell, above). Where the tell is refused,
;; nothing is forced, and the failing low rows print their forced checks
;; unavailable through tell-kept?.
;; In the low pass force! allocates 32 KiB there, so a collect request falls
;; due inside the section and is handled at its exit, the first event check
;; once the section enables interrupts again. The handler's own work costs the
;; engine ticks. Where they run out in it, the engine's timer reads #f at its
;; end, and the engine expires as the handler returns: the remainder lies at
;; that section's exit, before anything after it. A marker set inside a
;; section and overwritten just after it reads the section's value at exactly
;; those fuels, three a section, at the low trip, and at none at the high trip
;; or at 256 KiB. So a low row fails by name unless every forced section met
;; its request before the next forced section or its slice's end, which a trip
;; slipped to 256 KiB breaks, a 32 KiB allocation then meeting one about one
;; time in eight; and unless some first slice expired at a forced section's
;; exit, which the high pass, forcing none, never does. Each first slice
;; numbers the forced sections it passes, from 1, and the row shows whose
;; exits were met. The timer is read through Chez's own $tc-field, reached
;; through eval.

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
          (set! forced-at t))))
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
;; times of 100, so it is due as the section ends.
(define (exit-noted!)
  (when forced-pending
    (set! forced-pending #f)
    (when (and numbering (not exit-k) (number? forced-at) (ticks-spent?))
      (set! exit-k forced-k))))

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

;; call-begun!, call-ended! : -> Void
;; Around a re-entry row's call, its timer firing at every tick, in place of
;; a first slice: its forced sections numbered, and once it is over, the
;; count kept for the pass and a forced section's request still due counted
;; unmet.
(define (call-begun!)
  (set! forced-k 0)
  (set! exit-k #f)
  (set! numbering #t)
  (slice-begun!))
(define (call-ended!)
  (set! numbering #f)
  (set! pass-k (max pass-k forced-k))
  (slice-ended!))

;; ticked! : -> (U Natural #f)
;; At each fire of such a timer: the forced section at whose exit its ticks
;; ran out, if they did, cleared for the next fire.
(define (ticked!)
  (let ((k exit-k))
    (set! exit-k #f)
    k))

;; captured-at! : (U Natural #f) -> Void
;; A capture made at forced section K's exit noted for the pass.
(define (captured-at! k)
  (when (and k (not (memv k pass-exits)))
    (set! pass-exits (cons k pass-exits))))

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

;; counted-pass : (-> A) -> (Values A Tally)
;; RUN's answer, a pass's sweep, and its tally, the trip and the handler
;; put back however it leaves.
(define (counted-pass run)
  (pass-reset!)
  (let ((r (dynamic-wind (lambda () #f) run ended!)))
    (values r (pass-tally))))

;; requests-judged : Pass Tally -> (Listof Any)
(define (requests-judged pass tally)
  (if (eq? pass 'low) (low-judged tally) '()))

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

;; --- the calls ----------------------------------------------------------------------------

;; settings : Settings
;; Two settings, busy-timeout listed last, so it runs first.
(define settings '((foreign-keys . #t) (busy-timeout . 1234)))

;; plan : (Listof (List String (U String #f)))
;; The PRAGMAs one open with settings prepares, in order: each setting's set,
;; then its read, busy-timeout's first.
(define plan '(("busy_timeout" "1234") ("busy_timeout" #f) ("foreign_keys" "1") ("foreign_keys" #f)))

;; as-asked : (List Any Any)
(define as-asked '(1234 1))

;; readings : Database -> Any
(define (readings db)
  (attempt (lambda () (let* ((a (pragma db "busy_timeout")) (b (pragma db "foreign_keys"))) (list a b)))))

;; proc : Database -> (List 'called Natural Natural)
;; call-with-database's procedure: its connection's handle and how many
;; statements it tracks. It notes itself given the connection inside
;; call-with-open-handle's section, where the connection is checked open, so
;; a handle a later open reused is never noted for it. It prepares nothing,
;; so the authorizer sees only the settings'.
(define (proc db)
  (let* ((h (call-with-open-handle 'test-open-interleave db
              (lambda (h) (note! (list 'proc h)) h)))
         (tracked (length (tracked-statements db))))
    (list 'called h tracked)))

;; thunk-of : Symbol -> (-> Any)
(define (thunk-of verb)
  (if (eq? verb 'open-database)
      (lambda () (attempt (lambda () (open-database ":memory:" settings))))
      (lambda () (attempt (lambda () (call-with-database ":memory:" settings proc))))))

;; --- one trial ----------------------------------------------------------------------------

;; Run = (List Any Natural Any)
;; A run's answer, how many events were noted while it ran, and the counts
;; before and after it, equal or not.

;; ran : (-> Any) -> Run
(define (ran go)
  (let* ((n0 (length noted))
         (c0 (native-counts))
         (answer (go))
         (n1 (length noted))
         (c1 (native-counts)))
    (list answer (- n1 n0) (if (equal? c0 c1) 'counts-kept (list 'counts c0 c1)))))

;; Connection = (List Natural (Listof (List String (U String #f))) Natural)
;; One open noted: its handle; the PRAGMAs noted for it, oldest first; and
;; how many times call-with-database's procedure was given it open.

;; connections-of : (Listof Any) -> (Listof Connection)
;; Each open among EVENTS, oldest first, in order, with what was noted for
;; it: a PRAGMA, or the procedure's note, belongs to the latest open of its
;; handle before it, since a closed connection's address can be reused.
(define (connections-of events)
  (let ((current (make-eqv-hashtable)) (all '()))
    (let loop ((rest events))
      (unless (null? rest)
        (let* ((e (car rest)) (h (cadr e)) (c (hashtable-ref current h #f)))
          (case (car e)
            ((open)
             (let ((fresh (vector h '() 0)))
               (hashtable-set! current h fresh)
               (set! all (cons fresh all))))
            ((pragma) (when c (vector-set! c 1 (cons (cddr e) (vector-ref c 1)))))
            ((proc) (when c (vector-set! c 2 (+ (vector-ref c 2) 1))))))
        (loop (cdr rest))))
    (let loop ((rest all) (found '()))
      (if (null? rest)
          found
          (let ((c (car rest)))
            (loop (cdr rest) (cons (list (vector-ref c 0) (reverse (vector-ref c 1)) (vector-ref c 2))
                                   found)))))))

;; latest-of : Natural (Listof Connection) -> (U Connection #f)
;; The latest open of handle H among CONNS.
(define (latest-of h conns)
  (let loop ((rest conns) (found #f))
    (cond ((null? rest) found)
          ((eqv? (car (car rest)) h) (loop (cdr rest) (car rest)))
          (else (loop (cdr rest) found)))))

;; prefix? : (Listof Any) (Listof Any) -> Boolean
(define (prefix? short long)
  (cond ((null? short) #t)
        ((null? long) #f)
        ((equal? (car short) (car long)) (prefix? (cdr short) (cdr long)))
        (else #f)))

;; refused-answer : Symbol -> Any
(define (refused-answer verb) (list 'raised (list 'closed verb)))

;; own-wind-refused : Any
;; What the procedure's own call-with-open-handle raises when an expiry
;; falls in the few instructions between its finished flag and its wind's
;; exit, and its resume enters the wind again: that call's refusal, as its
;; comment in (chez-sqlite3 private connection) says. Measured:
;; no engine reaches the window over fuel 1 to 3000 in one slice; a
;; remainder resumed at a fuel of 1 to 3 reaches it here.
(define own-wind-refused
  '(raised (assertion-violation test-open-interleave (re-entered))))

;; judged : Symbol Counts (Listof Run) Boolean Boolean -> (List Natural (Listof Any) Natural Boolean Boolean Boolean)
;; RUNS, those whose answers came back in the trial, for VERB, judged once
;; the trial's events are in, by the trial itself: how many connections the
;; runs answered, or were given to the procedure; what deviated; how many
;; connections were opened, two a whole new call each, which the sweep
;; bounds; whether a run was refused, &sqlite-closed from VERB; REFUSED-
;; BEFORE, whether R's own second run was, R taken before the open, the
;; sweep's bound; and STRADDLE, R taken before the call's last section and
;; R1 past it. R's second run alone tells: R1's run of call-with-database
;; is refused too where R1's expiry closed the connection, though R lay
;; before the call's first expression, its second run a whole new call.
;; Every database answered is
;; checked, then closed, and the counts are then START's, those when the
;; trial began: zero, unless an earlier trial left something, which the
;; sweep's end finds.
(define (judged verb start runs refused-before straddle)
  (let* ((conns (connections-of (reverse noted)))
         (answers (let loop ((rest runs) (found '()))
                    (if (null? rest) (reverse found) (loop (cdr rest) (cons (car (car rest)) found)))))
         ;; the databases open-database answered, each once
         (answered
          (let loop ((rest answers) (found '()))
            (cond ((null? rest) (reverse found))
                  ((and (a-database? (car rest)) (not (memq (car rest) found)))
                   (loop (cdr rest) (cons (car rest) found)))
                  (else (loop (cdr rest) found)))))
         ;; the connections answered: those databases, each the latest open
         ;; of its handle, still open; or those given to the procedure
         (given
          (if (eq? verb 'open-database)
              (let loop ((rest answered) (found '()))
                (if (null? rest)
                    (reverse found)
                    (loop (cdr rest) (cons (latest-of (handle-of (car rest)) conns) found))))
              (let loop ((rest conns) (found '()))
                (cond ((null? rest) (reverse found))
                      ((> (caddr (car rest)) 0) (loop (cdr rest) (cons (car rest) found)))
                      (else (loop (cdr rest) found))))))
         (deviations '()))
    (define (deviate! d) (set! deviations (cons d deviations)))
    ;; each answer is a database, the procedure's, or a refusal that
    ;; touched nothing
    (let loop ((rest runs))
      (unless (null? rest)
        (let ((a (car (car rest))))
          (cond ((a-database? a) #f)
                ((and (pair? a) (eq? (car a) 'called))
                 (unless (eqv? (caddr a) 0) (deviate! (list 'tracked-in-proc a))))
                ((or (equal? a (refused-answer verb))
                     (and (eq? verb 'call-with-database)
                          (or (equal? a (refused-answer 'test-open-interleave))
                              (equal? a own-wind-refused))))
                 (unless (and (eqv? (cadr (car rest)) 0) (eq? (caddr (car rest)) 'counts-kept))
                   (deviate! (list 'closed-run-touched a (cdr (car rest))))))
                (else (deviate! (list 'answer a)))))
        (loop (cdr rest))))
    ;; every connection opened: its PRAGMAs a prefix of the plan, none twice
    (let loop ((rest conns))
      (unless (null? rest)
        (let ((seen (cadr (car rest))))
          (unless (prefix? seen plan) (deviate! (list 'not-the-plan seen))))
        (loop (cdr rest))))
    ;; every connection answered: the whole plan, once
    (let loop ((rest given))
      (unless (null? rest)
        (let ((c (car rest)))
          (unless (and c (equal? (cadr c) plan)) (deviate! (list 'answered-not-the-plan c))))
        (loop (cdr rest))))
    ;; opens: those answered alone, for open-database; one a call, at most,
    ;; for call-with-database, a second only from a whole new call, which
    ;; the sweep bounds
    (if (eq? verb 'open-database)
        (unless (= (length conns) (length given))
          (deviate! (list 'opened (length conns) 'answered (length given))))
        (unless (<= (length conns) 2)
          (deviate! (list 'opened (length conns)))))
    ;; the procedure given each connection, open, once at most
    (let loop ((rest conns))
      (unless (null? rest)
        (when (> (caddr (car rest)) 1) (deviate! (list 'procedure-given-twice (car rest))))
        (loop (cdr rest))))
    ;; an answered database: nothing tracked, the settings as asked
    (let loop ((rest answered))
      (unless (null? rest)
        (let* ((db (car rest))
               (tracked (attempt (lambda () (length (tracked-statements db)))))
               (read (readings db)))
          (unless (eqv? tracked 0) (deviate! (list 'tracked tracked)))
          (unless (equal? read as-asked) (deviate! (list 'readings read)))
          (close-answer db))
        (loop (cdr rest))))
    (unless (equal? (native-counts) start)
      (deviate! (list 'counts start (native-counts))))
    (let ((refused (exists (lambda (run) (equal? (car run) (refused-answer verb))) runs)))
      (list (length given) (reverse deviations) (length conns) (and refused #t)
            (and refused-before #t) (and straddle #t)))))

;; Trial = (List Symbol Natural (Listof Any) Natural Boolean Boolean Boolean Boolean)
;; Its kind, completed when R's first slice completed the call, last when
;; R's resume completed within G, else interleaved; then judged's: how many
;; connections, or connections given to the procedure, were answered; what
;; deviated; how many were opened; whether a run was refused; whether R's
;; own second run was, R before the open; whether R lay before the call's
;; last section and R1 past it; and whether no collect request fell in R's
;; first slice, so the sweep's bound reads it.

;; opened? : -> Boolean
;; Whether the trial's notes hold an open.
(define (opened?) (exists (lambda (e) (eq? (car e) 'open)) noted))

;; past-last? : Symbol Counts -> Boolean
;; Whether VERB's run lies past the call's last section now, by the trial's
;; notes: for open-database, a connection with the whole plan noted and no
;; statement counted beyond START's, its last read finalized; for
;; call-with-database, whose connection an expiry closes, the procedure
;; given its connection.
(define (past-last? verb start)
  (let ((conns (connections-of (reverse noted))))
    (if (eq? verb 'open-database)
        (and (exists (lambda (c) (equal? (cadr c) plan)) conns)
             (= (cdr (assq 'statement (native-counts))) (cdr (assq 'statement start))))
        (exists (lambda (c) (> (caddr c) 0)) conns))))

;; trial : Pass Symbol Natural Natural -> Trial
;; One trial of VERB at FUEL, R resumed at G, in PASS.
(define (trial pass verb fuel g)
  (begun! pass)
  (set! noted '())
  (let* ((start (native-counts))
         (met requests)
         (r (first-slice (make-engine (thunk-of verb)) fuel))
         (clean (= requests met))
         (t (if (eq? (car r) 'completed)
                (cons 'completed (judged verb start (list (list (cadr r) 0 'counts-kept)) #f #f))
                (let* ((R (cadr r))
                       (r-open (opened?))
                       (r-last (past-last? verb start))
                       (r1 (slice R g)))
                  (if (eq? (car r1) 'completed)
                      (let ((second (ran (lambda () (finish R)))))
                        (cons 'last (judged verb start (list (list (cadr r1) 0 'counts-kept) second)
                                            (and (not r-open) (equal? (car second) (refused-answer verb)))
                                            #f)))
                      (let* ((R1 (cadr r1))
                             (r1-last (past-last? verb start))
                             (second (ran (lambda () (finish R))))
                             (third (ran (lambda () (finish R1)))))
                        (cons 'interleaved (judged verb start (list second third)
                                                   (and (not r-open) (equal? (car second) (refused-answer verb)))
                                                   (and (not r-last) r1-last)))))))))
    (ended!)
    (append t (list clean))))

;; Sweep = (List Any Natural (Listof Any) Natural (Listof Natural) (U Natural #f) Natural Natural Counts Natural)
;; The fuel at which the call completes without expiring, or
;; no-completion-by-20000; how many trials ran; each trial's deviations,
;; with its fuels; the trials in which a run answered a connection, or the
;; procedure; the fuels of the trials that opened two connections, whole
;; new calls; the first fuel at which a trial was refused, R taken before
;; the open, #f for none; how many fuels saw a refusal; the trials with R
;; before the call's last section and R1 past it; the counts once the
;; sweep is done; and the whole new calls left out of the bound, a collect
;; request in their first slice.

;; sweep : Pass Symbol -> Sweep
;; At every fuel from 1 until the call completes without expiring, trial in
;; PASS at every G from 1 until R's resume completes within it.
(define (sweep pass verb)
  (let floop ((fuel 1) (trials 0) (deviations '()) (answered 0) (news '()) (refused-at #f)
              (refused-fuels 0) (straddle 0) (moved 0))
    (let gloop ((g 1) (trials trials) (deviations deviations) (answered answered) (news news)
                (refused-at refused-at) (seen #f) (straddle straddle) (moved moved))
      (let* ((t (trial pass verb fuel g))
             (kind (car t))
             (deviations (if (null? (caddr t)) deviations
                             (cons (list verb fuel g (caddr t)) deviations)))
             (answered (if (> (cadr t) 0) (+ answered 1) answered))
             (new (> (cadddr t) 1))
             (news (if (and new (list-ref t 7)) (cons fuel news) news))
             (moved (if (and new (not (list-ref t 7))) (+ moved 1) moved))
             (seen (or seen (list-ref t 4)))
             (refused-at (or refused-at (and (list-ref t 5) fuel)))
             (straddle (if (list-ref t 6) (+ straddle 1) straddle))
             (trials (+ trials 1)))
        (cond ((eq? kind 'completed)
               (list fuel trials (reverse deviations) answered (reverse news) refused-at refused-fuels
                     straddle (native-counts) moved))
              ((>= fuel 20000)
               (list 'no-completion-by-20000 trials (reverse deviations) answered (reverse news)
                     refused-at refused-fuels straddle (native-counts) moved))
              ((eq? kind 'last)
               (floop (+ fuel 1) trials deviations answered news refused-at
                      (if seen (+ refused-fuels 1) refused-fuels) straddle moved))
              (else (gloop (+ g 1) trials deviations answered news refused-at seen straddle moved)))))))

;; past-the-bound : (Listof Natural) (U Natural #f) -> (Listof Natural)
;; The distinct fuels among NEWS at or past REFUSED-AT, every one when it
;; is #f, in order: a failing row's evidence.
(define (past-the-bound news refused-at)
  (let loop ((rest news) (found '()))
    (cond ((null? rest) (reverse found))
          ((and (or (not refused-at) (>= (car rest) refused-at)) (not (memv (car rest) found)))
           (loop (cdr rest) (cons (car rest) found)))
          (else (loop (cdr rest) found)))))

;; tallied : (Listof (List Symbol Natural Natural (Listof Any))) -> (Listof (Pairof Symbol Natural))
;; How many trials among DEVIATIONS deviated by each kind, a deviation's
;; first symbol, in the order each kind was first seen; printed for a
;; reader of a failing run.
(define (tallied deviations)
  (let loop ((rest deviations) (kinds '()))
    (if (null? rest)
        kinds
        (loop (cdr rest)
              (let each ((ds (cadddr (car rest))) (kinds kinds) (seen '()))
                (if (null? ds)
                    kinds
                    (let ((k (car (car ds))))
                      (if (memq k seen)
                          (each (cdr ds) kinds seen)
                          (each (cdr ds) (counted-up k kinds) (cons k seen))))))))))

;; counted-up : Symbol (Listof (Pairof Symbol Natural)) -> (Listof (Pairof Symbol Natural))
;; KINDS with K's count one more, a kind first seen added last.
(define (counted-up k kinds)
  (cond ((null? kinds) (list (cons k 1)))
        ((eq? (car (car kinds)) k) (cons (cons k (+ (cdr (car kinds)) 1)) (cdr kinds)))
        (else (cons (car kinds) (counted-up k (cdr kinds))))))

;; reported : Pass Symbol -> (Listof Any)
;; sweep of VERB in PASS, printed, and judged: its deviations, summarized;
;; whether its trials answered a connection, or the procedure, at least
;; three a fuel on average, over the fuels up to the one at which the call
;; completes: a sweep that reused one R across every G makes at most one a
;; fuel; refusals at half the fuels at least; every whole new call below
;; the first refusal the sweep saw itself, R taken before the open; in the
;; low pass, R before the last section and R1 past it in some trial, and
;; collect requests met in its trials; and the counts once it was done.
(define (reported pass verb)
  (let-values (((run met) (counted-pass (lambda () (sweep pass verb)))))
    (let ((fuel (car run)) (news (list-ref run 4)) (refused-at (list-ref run 5))
          (refused-fuels (list-ref run 6)) (straddle (list-ref run 7)))
      (display "  ")
      (display verb)
      (when (eq? pass 'low) (display ", low trip"))
      (display ": completed without expiring at fuel ")
      (write fuel)
      (display "; trials ")
      (write (cadr run))
      (display "; trials answering ")
      (write (cadddr run))
      (display "; fuels seeing a refusal ")
      (write refused-fuels)
      (display "; R before the last section and R1 past it in ")
      (write straddle)
      (display "; whole new calls ")
      (write (length news))
      (display ", the last at fuel ")
      (write (if (null? news) 0 (apply max news)))
      (display ", below the first refusal before the open, at fuel ")
      (write refused-at)
      (display "; whole new calls left out, a collect request in the first slice, ")
      (write (list-ref run 9))
      (tally-shown met)
      (newline)
      (unless (null? (caddr run))
        (display "    deviations by kind: ")
        (write (tallied (caddr run)))
        (newline))
      (append
       (list (if (integer? fuel) (summarized (caddr run)) (list fuel (summarized (caddr run))))
             (if (and (integer? fuel) (>= (cadddr run) (* 3 fuel)))
                 'answered-three-a-fuel
                 (list 'answered (cadddr run) 'over fuel))
             (if (and (integer? fuel) (>= (* 2 refused-fuels) fuel))
                 'refused-at-half-the-fuels
                 (list 'refused-fuels refused-fuels 'over fuel))
             (if (and refused-at (for-all (lambda (f) (< f refused-at)) news))
                 'whole-new-calls-below-a-refusal
                 (list 'whole-new-calls-not-below-a-refusal (past-the-bound news refused-at) refused-at)))
       (if (eq? pass 'low)
           (list (if (> straddle 0) 'straddled-the-last-section (list 'none-straddling-the-last-section straddle)))
           '())
       (requests-judged pass met)
       (list (list-ref run 8))))))

(test-begin "open-interleave")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "the authorizer is registered for every new connection, through sqlite3_auto_extension, or the call is refused with its code; registering raises nothing"
  'registered-or-refused
  (if (tell-answered? registered) 'registered-or-refused registered))

(test-equal "the gate refuses the tell exactly when sqlite3_auto_extension, given an entry point that does nothing straight through the FFI, answers 21, and registers it exactly when that answers 0"
  'gate-held
  (if (or (and (tell-refused? registered) (eqv? direct sqlite-misuse))
          (and (eq? registered 'registered) (eqv? direct 0)))
      'gate-held
      (list 'gate registered 'direct direct)))

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

;; --- the claim, pure ---------------------------------------------------------------------
;; The open verbs' claim, made-claim's, made by the call's first expression.
;; The sweeps below hold it through the calls; these rows hold it whole: no
;; position the call has passed is claimed again, 0 above all, the open's,
;; which any remainder taken before the open carries.

;; claimed : (Listof Natural) -> (Listof Boolean)
;; A fresh claim given each of STEPS, in order: what it answered each time.
(define (claimed steps)
  (let ((claim (made-claim)))
    (let loop ((rest steps) (found '()))
      (if (null? rest)
          (reverse found)
          (loop (cdr rest) (cons (claim (car rest)) found))))))

(test-equal "an open's claim, made-claim's, claims each position once, in order: 0, then 0 again refused, 2 refused before 1, 1, 1 again refused, 0 refused, 2 and 3; then every position it passed is refused, 0 included, one past the next too, and the next, 4, is claimed"
  '(#t #f #f #t #f #f #t #t #f #f #f #f #f #f #t #f)
  (guard (e (#t (list 'raised (what-raised e))))
    (claimed '(0 0 2 1 1 0 2 3 0 1 2 3 5 0 4 0))))

(let* ((name "the tell: an open with the two settings is noted once, then each PRAGMA it prepares, in the plan's order, busy-timeout's first, its value and none for a read")
       (noted? (tell-kept? registered name "count of the opens and the PRAGMAs the callbacks noted")))
  (test-equal name
    (list (tell-noted noted? 1) (tell-noted noted? plan) as-asked zero-counts)
    (begin
      (set! noted '())
      (let* ((db (open-database ":memory:" settings))
             (conns (connections-of (reverse noted)))
             (c (latest-of (handle-of db) conns))
             (read (readings db)))
        (close-answer db)
        (list (tell-noted noted? (length conns)) (tell-noted noted? (and c (cadr c))) read
              (native-counts))))))

(define open-name
  "open-database's remainder R, taken at every fuel from 1 until the call completes without expiring, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1: each run answers the connection or is refused with &sqlite-closed, touching nothing; every connection opened is answered; each setting is applied once, in the plan's order, on the connection answered; it tracks no statement and reads back as asked; once it is closed, nothing is counted; at least three trials a fuel on average answer a connection; refusals come at half the fuels at least; and two connections, a whole new call's, only below the first fuel at which a trial was refused, R taken before the open")

(define low-said
  "the same, its trials under a collect trip of 256 bytes, so a request falls due in every run and one due inside a section costs ticks at its exit, the tell's callbacks allocating 32 KiB inside the open's section and each setting's prepare: the same verdicts, each trial judged by itself and bounded by the sweep's own refusals; some trial has R before the call's last section and R1 past it; and collect requests met in the trials, each forced section's request met before the next, and some first slice expired at a forced section's exit. ")

(let ((name open-name))
  (tell-available! registered name)
  (test-equal name
    (list '() 'answered-three-a-fuel 'refused-at-half-the-fuels 'whole-new-calls-below-a-refusal zero-counts)
    (reported 'high 'open-database)))

(let ((name (string-append low-said open-name)))
  (tell-available! registered name)
  (test-equal name
    (append (list '() 'answered-three-a-fuel 'refused-at-half-the-fuels 'whole-new-calls-below-a-refusal
                  'straddled-the-last-section)
            low-checks (list zero-counts))
    (reported 'low 'open-database)))

(define cwd-name
  "call-with-database's remainder R, taken at every fuel from 1 until the call completes without expiring, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1: each run answers the procedure's answer or &sqlite-closed, a refused run touching nothing; at most one connection a call is opened, and none is left open; each setting is applied once, in the plan's order, and wholly on the connection the procedure was given, which tracks no statement there; nothing is counted after; at least three trials a fuel on average answer the procedure; refusals come at half the fuels at least; and two connections, a whole new call's, only below the first fuel at which a trial was refused, R taken before the open")

(let ((name cwd-name))
  (tell-available! registered name)
  (test-equal name
    (list '() 'answered-three-a-fuel 'refused-at-half-the-fuels 'whole-new-calls-below-a-refusal zero-counts)
    (reported 'high 'call-with-database)))

(let ((name (string-append low-said cwd-name)))
  (tell-available! registered name)
  (test-equal name
    (append (list '() 'answered-three-a-fuel 'refused-at-half-the-fuels 'whole-new-calls-below-a-refusal
                  'straddled-the-last-section)
            low-checks (list zero-counts))
    (reported 'low 'call-with-database)))

;; --- a failing open, resumed twice ------------------------------------------------------------

;; failing : Settings
;; busy-timeout, then journal-mode wal, which :memory: reads back memory.
(define failing '((busy-timeout . 7) (journal-mode . wal)))

;; failing-plan : (Listof (List String (U String #f)))
(define failing-plan '(("busy_timeout" "7") ("busy_timeout" #f) ("journal_mode" "wal") ("journal_mode" #f)))

(define (mismatched verb) (list 'raised (list 'mismatch verb 'journal-mode 'wal 'memory)))

(define (failing-thunk-of verb)
  (if (eq? verb 'open-database)
      (lambda () (attempt (lambda () (open-database ":memory:" failing))))
      (lambda () (attempt (lambda () (call-with-database ":memory:" failing proc))))))

;; failing-twice : Pass Symbol Natural Boolean -> (U 'completed (List Symbol (Listof Any) Boolean Boolean))
;; VERB with failing as an engine, one slice of FUEL, in PASS; expired, its
;; remainder resumed to its end, then again. Answers completed when the
;; slice completed; else the second's kind, refused, again or new, what
;; deviated, and whether the remainder lay before the open: no connection
;; counted at its expiry beyond the counts at the start, for open-database;
;; no open noted then, for call-with-database, whose connection an expiry
;; closes, #f where NOTED? is #f; and whether no collect request fell in
;; the first slice, so the sweep's bound reads it. What deviated: the first not the
;; mismatch, or, for call-with-database, not &sqlite-closed either, an
;; expiry after the open having closed the connection; the second anything
;; else, or noting what it may not; a connection's PRAGMAs no prefix of the
;; plan, or one twice; anything counted after. A new one, a whole new
;; call's, the sweep bounds. Where NOTED? is #f, the checks that read the
;; notes are dropped: that the second notes nothing, that only a whole new
;; call opens a connection, and each connection's PRAGMAs. A remainder
;; taken while open-database's connection was still open, counted at the
;; expiry beyond the counts at the start, lies before the failure's close,
;; so the second resume is refused, there or earlier, never the mismatch
;; again: that comes only from one taken past the close.
(define (failing-twice pass verb fuel noted?)
  (begun! pass)
  (set! noted '())
  (let* ((start (native-counts))
         (met requests)
         (r (first-slice (make-engine (failing-thunk-of verb)) fuel))
         (clean (= requests met))
         (t (if (eq? (car r) 'completed)
                'completed
                (let* ((open-at-expiry (> (cdr (assq 'connection (native-counts)))
                                          (cdr (assq 'connection start))))
                       (before (if (eq? verb 'open-database)
                                   (not open-at-expiry)
                                   (and noted? (not (opened?)))))
                       (first (finish (cadr r)))
                       (n (length noted))
                       (second (ran (lambda () (finish (cadr r)))))
                       (conns (connections-of (reverse noted)))
                       (since (let loop ((rest noted) (k (- (length noted) n)) (found '()))
                                (if (= k 0) found (loop (cdr rest) (- k 1) (cons (car rest) found)))))
                       (opened-since (let loop ((rest since) (k 0))
                                       (cond ((null? rest) k)
                                             ((eq? (car (car rest)) 'open) (loop (cdr rest) (+ k 1)))
                                             (else (loop (cdr rest) k)))))
                       (quiet (and (or (not noted?) (eqv? (cadr second) 0))
                                   (eq? (caddr second) 'counts-kept)))
                       (kind (cond ((and (equal? (car second) (refused-answer verb)) quiet) 'refused)
                                   ((and (equal? (car second) (mismatched verb)) quiet) 'again)
                                   ((and (equal? (car second) (mismatched verb)) (eqv? opened-since 1)
                                         (eq? (caddr second) 'counts-kept))
                                    'new)
                                   (else 'other)))
                       (deviations '()))
                  (define (deviate! d) (set! deviations (cons d deviations)))
                  (unless (or (equal? first (mismatched verb))
                              (and (eq? verb 'call-with-database) (equal? first (refused-answer verb))))
                    (deviate! (list 'first first)))
                  (when (eq? kind 'other) (deviate! (list 'second second opened-since)))
                  (when (and open-at-expiry (not (eq? kind 'refused)))
                    (deviate! (list 'open-at-the-expiry-but-not-refused kind)))
                  (let loop ((rest (if noted? conns '())))
                    (unless (null? rest)
                      (unless (prefix? (cadr (car rest)) failing-plan)
                        (deviate! (list 'not-the-plan (cadr (car rest)))))
                      (loop (cdr rest))))
                  (unless (equal? (native-counts) start) (deviate! (list 'counts start (native-counts))))
                  (list kind (reverse deviations) before clean)))))
    (ended!)
    t))

;; failing-sweep : Pass Symbol Boolean -> (List Any (Listof Any) (Listof (Pairof Symbol Natural)) (Listof Natural) (U Natural #f) Counts Natural)
;; failing-twice, NOTED? given it, at every fuel from 1 until the call
;; completes without expiring, at most 20000, in PASS: that fuel; each
;; fuel's deviations; how many fuels each kind came at; the fuels at which
;; it made a whole new call, no collect request in the first slice; the
;; first fuel at which it was refused, the remainder before the open; the
;; counts after; and the whole new calls left out of the bound, a collect
;; request in their first slice.
(define (failing-sweep pass verb noted?)
  (let loop ((fuel 1) (deviations '()) (kinds '()) (news '()) (refused-at #f) (moved 0))
    (let ((t (failing-twice pass verb fuel noted?)))
      (cond ((eq? t 'completed)
             (list fuel (reverse deviations) kinds (reverse news) refused-at (native-counts) moved))
            ((>= fuel 20000)
             (list 'no-completion-by-20000 (reverse deviations) kinds (reverse news) refused-at (native-counts)
                   moved))
            (else
             (loop (+ fuel 1)
                   (if (null? (cadr t)) deviations (cons (cons fuel (cadr t)) deviations))
                   (counted-up (car t) kinds)
                   (if (and (eq? (car t) 'new) (cadddr t)) (cons fuel news) news)
                   (or refused-at (and (eq? (car t) 'refused) (caddr t) fuel))
                   (if (and (eq? (car t) 'new) (not (cadddr t))) (+ moved 1) moved)))))))

;; failing-reported : Pass Symbol Boolean -> (Listof Any)
;; failing-sweep of VERB in PASS, printed, and judged: no deviation;
;; refusals at a third of the fuels at least; where NOTED?, every whole new
;; call below the first refusal the sweep saw itself, the remainder before
;; the open, else unavailable; in the low pass, low-judged's three, its
;; two forced checks unavailable where NOTED? is #f, the tell refused, which
;; forces nothing; and the counts.
(define (failing-reported pass verb noted?)
  (let-values (((run met) (counted-pass (lambda () (failing-sweep pass verb noted?)))))
    (let ((news (list-ref run 3)) (refused-at (list-ref run 4)))
      (display "  ")
      (display verb)
      (display ", failing, resumed twice")
      (when (eq? pass 'low) (display ", low trip"))
      (display ": completed without expiring at fuel ")
      (write (car run))
      (display "; second resumes ")
      (write (caddr run))
      (display "; whole new calls at ")
      (write news)
      (display ", below the first refusal before the open, at fuel ")
      (write refused-at)
      (display "; whole new calls left out, a collect request in the first slice, ")
      (write (list-ref run 6))
      (tally-shown met)
      (newline)
      (append
       (list (summarized (cadr run))
             (let ((p (assq 'refused (caddr run))))
               (if (and p (integer? (car run)) (>= (* 3 (cdr p)) (car run)))
                   'refused-at-a-third-of-the-fuels
                   (list 'refused (if p (cdr p) 0) 'of (car run))))
             (tell-noted noted?
                         (if (and refused-at (for-all (lambda (f) (< f refused-at)) news))
                             'whole-new-calls-below-a-refusal
                             (list 'whole-new-calls-not-below-a-refusal news refused-at))))
       (let ((j (requests-judged pass met)))
         (if (null? j) j (list (car j) (tell-noted noted? (cadr j)) (tell-noted noted? (caddr j)))))
       (list (list-ref run 5))))))

(define failing-checks
  "checks of what the callbacks noted: that the second resume notes nothing, that only a whole new call opens a connection, and each connection's PRAGMAs; and, in the low pass, where the callbacks' allocations met their requests")

(define failing-open-name
  "open-database with busy-timeout and journal-mode wal on :memory:, which mismatches, its remainder taken at every fuel from 1 until it completes without expiring and resumed to its end twice: the first raises the mismatch, the connection closed; the second is refused with &sqlite-closed, at a third of the fuels at least, or, past the failure's close, raises the mismatch again, noting nothing and changing no count; only below the first fuel at which the sweep saw one refused, the remainder before the open, does it open a connection, a whole new call's, which mismatches alone; no PRAGMA is prepared twice on a connection; nothing is counted after")

(define failing-low-said
  "the same, its trials under a collect trip of 256 bytes, the tell's callbacks allocating 32 KiB inside the open's section and each setting's prepare: the same verdicts, and collect requests met in the trials, each forced section's request met before the next, and some first slice expired at a forced section's exit. ")

(let* ((name failing-open-name)
       (noted? (tell-kept? registered name failing-checks)))
  (test-equal name
    (list '() 'refused-at-a-third-of-the-fuels (tell-noted noted? 'whole-new-calls-below-a-refusal) zero-counts)
    (failing-reported 'high 'open-database noted?)))

(let* ((name (string-append failing-low-said failing-open-name))
       (noted? (tell-kept? registered name failing-checks)))
  (test-equal name
    (list '() 'refused-at-a-third-of-the-fuels (tell-noted noted? 'whole-new-calls-below-a-refusal)
          'collect-requests-met (tell-noted noted? 'every-forced-section-met-its-request)
          (tell-noted noted? 'taken-at-a-forced-exit) zero-counts)
    (failing-reported 'low 'open-database noted?)))

(define failing-cwd-name
  "call-with-database the same: the first raises the mismatch, its procedure never called, or &sqlite-closed where the expiry closed the connection; the second is refused, at a third of the fuels at least, or raises the mismatch again, noting nothing; only below the first fuel at which the sweep saw one refused, no open noted at the expiry, does it open a connection, a whole new call's; nothing is counted after")

(let* ((name failing-cwd-name)
       (noted? (tell-kept? registered name failing-checks)))
  (test-equal name
    (list '() 'refused-at-a-third-of-the-fuels (tell-noted noted? 'whole-new-calls-below-a-refusal) zero-counts)
    (failing-reported 'high 'call-with-database noted?)))

(let* ((name (string-append failing-low-said failing-cwd-name))
       (noted? (tell-kept? registered name failing-checks)))
  (test-equal name
    (list '() 'refused-at-a-third-of-the-fuels (tell-noted noted? 'whole-new-calls-below-a-refusal)
          'collect-requests-met (tell-noted noted? 'every-forced-section-met-its-request)
          (tell-noted noted? 'taken-at-a-forced-exit) zero-counts)
    (failing-reported 'low 'call-with-database noted?)))

;; --- an interrupt that escapes, at each of call-with-database's sections --------------------

;; escaped-at : Natural -> (List Any Natural (Listof Any) Symbol Counts)
;; call-with-database with settings on :memory:, SIGINT raised inside the
;; section that notes the call's Kth event, its open, 1, or a PRAGMA's
;; prepare, 2 to 5; a keyboard-interrupt handler leaves the call through an
;; escape continuation. Answers what the call answered, escaped when the
;; handler ran; how many connections were noted; the PRAGMAs noted for
;; them; whether the procedure was called; and the counts after.
(define (escaped-at k)
  (set! noted '())
  (let* ((called 'proc-not-called)
         (old (keyboard-interrupt-handler))
         (r (call/cc
             (lambda (escape)
               (dynamic-wind
                 (lambda ()
                   (keyboard-interrupt-handler (lambda () (escape 'escaped)))
                   (set! interrupt-at k))
                 (lambda ()
                   (attempt (lambda () (call-with-database ":memory:" settings
                                         (lambda (db) (set! called 'proc-called))))))
                 (lambda ()
                   (set! interrupt-at #f)
                   (keyboard-interrupt-handler old))))))
         (conns (connections-of (reverse noted))))
    (list r (length conns)
          (if (pair? conns) (cadr (car conns)) 'no-connection)
          called (native-counts))))

;; first-of : (Listof Any) Natural -> (Listof Any)
(define (first-of items n)
  (if (or (= n 0) (null? items)) '() (cons (car items) (first-of (cdr items) (- n 1)))))

(let ((name "an interrupt that escapes from call-with-database, raised inside each of its sections in turn: its open's, then each setting's prepare: each time the keyboard interrupt is handled as that section ends, the handler leaves the call, and the call's extent closes the connection, the statement just prepared among what it finalizes; no later section runs, the procedure is never called, and nothing is counted"))
  (tell-available! registered name)
  (test-equal name
    (let loop ((k 1) (expected '()))
      (if (> k 5)
          (reverse expected)
          (loop (+ k 1) (cons (list 'escaped 1 (first-of plan (- k 1)) 'proc-not-called zero-counts)
                              expected))))
    (let loop ((k 1) (found '()))
      (if (> k 5)
          (reverse found)
          (loop (+ k 1) (cons (escaped-at k) found))))))

(let ((name "the entry point is unregistered once the sweeps are done: an open after it is not noted"))
  (tell-available! registered name)
  (test-equal name
    '(reset ())
    (guard (e (#t (list 'raised (describe e))))
      (reset-auto-extension)
      (unlock-object entry-point)
      (unlock-object authorizer)
      (set! noted '())
      (let ((db (open-database ":memory:" settings)))
        (close-answer db)
        (list 'reset noted)))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "open-interleave")

(exit (suite-exit-status runner))
