#!r6rs
;;; The suite for open-database with settings under an engine (ADR-0018,
;;; consequences), in (chez-sqlite3 private open). open-database holds no
;;; dynamic-wind around its settings, so an engine's expiry between two of
;;; their critical sections suspends the open, and the resume goes on.
;;;
;;;   every fuel     the six settings and statement-cache on a file, at every
;;;                  fuel from 1 until the open completes without expiring,
;;;                  that fuel named: each fuel's open, resumed at its fuel
;;;                  until it completes, answers a connection whose every
;;;                  setting reads back as asked, its cache of the list's
;;;                  capacity; some expiries fall while a setting's statement
;;;                  is held
;;;   resumed twice  the same open's remainder resumed to its end, then, once
;;;                  the suite has set each of the six otherwise on the
;;;                  connection it answered, resumed again: it raises
;;;                  &sqlite-closed, refused at the open's section or a
;;;                  setting's, or, past its last section, answers that
;;;                  connection again, touching nothing either way. A remainder
;;;                  taken before the call's first expression would make a
;;;                  whole new call, a connection of its own as asked; none
;;;                  applies a setting to the first connection again, closes
;;;                  it, opens a connection, or reaches SQLite with SQL the
;;;                  checks computed again: Chez's number->string, resumed a
;;;                  second time from inside, answered "" or the digits
;;;                  twice, and the checks run in one critical section, where no
;;;                  remainder is taken
;;;
;;;   re-entered     call-with-database, whose connection does not survive an
;;;                  engine, at each tick from 1 until its procedure starts: a
;;;                  timer's handler takes a continuation at that tick, and the
;;;                  procedure, once the suite has set each of the six
;;;                  otherwise, re-enters it. Taken before the settings were
;;;                  done, it raises &sqlite-closed, refused at the open's
;;;                  section or a setting's, and the procedure is not called
;;;                  again; taken past their last section, it calls the
;;;                  procedure again, which finds the six as the suite set
;;;                  them. Only one taken before the call's first expression
;;;                  makes a whole new call. None applies a setting again to
;;;                  the first connection, or leaves a connection open
;;;   under an       call-with-database with the same settings, at every fuel
;;;   engine         from 1 until it completes without expiring: a remainder
;;;                  dropped leaves nothing counted, since the expiry closed
;;;                  the connection; one resumed to its end answers the
;;;                  procedure's readings as asked, or &sqlite-closed, from the
;;;                  call or from the procedure's own reads; the procedure is
;;;                  called once a call at most
;;;   two passes     the resumed-twice and re-entered rows twice: with no
;;;                  collect request in a trial, and under a collect trip of
;;;                  256 bytes, where a request due inside a critical section
;;;                  is handled at its exit and costs the engine ticks there, so
;;;                  a remainder or a continuation is taken at a section's exit
;;;                  too, before anything after it: a claim advanced just
;;;                  after its section, not inside it, applies a setting twice
;;;                  there. The low pass fails by name unless collect requests
;;;                  fell in its trials, and unless a run past the call's last
;;;                  section answered again
;;;   a failing      the procedure leaves a statement its
;;;   close          connection does not track, so the close fails, then
;;;                  re-enters a continuation a timer's handler took at each
;;;                  tick until it starts. Inside the call's extent, refused at
;;;                  the open's section or a setting's, the call raises
;;;                  &sqlite-closed, the close's refusal not raised over it,
;;;                  at some tick before the open and some after; a
;;;                  continuation outside the extent, or one that calls the
;;;                  procedure again, is left by the procedure, so the close's
;;;                  refusal is raised, as for any procedure that leaves. Each
;;;                  tick is judged by its own capture, the connections counted
;;;                  then, never by another run's: a collect request costs a
;;;                  run up to a tick, so two runs' ticks can differ
;;;
;;; An engine spends no ticks inside a critical section, so the fuels measure
;;; the Scheme work between the open's sections. Each trial of the two passes
;;; begins with a collection, so its first slice runs as every trial's at that
;;; fuel does, unless a collect request falls in it (below); each is judged by
;;; what it saw itself, and each bound on a whole new call is a refusal the
;;; sweep saw itself, never a refused call's fuel, a control run on the code
;;; under test, or a caller's count. The low pass leaves sweep, cwd-sweep and
;;; untracked-sweep alone: each judges a fuel by itself. The loading
;;; procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) make-engine set-timer timer-interrupt-handler foreign-procedure collect
              collect-trip-bytes collect-request-handler foreign-callable foreign-callable-entry-point
              lock-object unlock-object define-ftype ftype-ref ftype-set! make-ftype-pointer ftype-sizeof
              foreign-alloc foreign-free foreign-set! scheme-environment)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-closed?))

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
(define execute! (public 'execute!))
(define query-row (public 'query-row))
(define tracked-statements (reach '(chez-sqlite3 private connection) 'tracked-statements))
(define database-cache-capacity (reach '(chez-sqlite3 private connection) 'database-cache-capacity))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define call-with-c-string (reach '(chez-sqlite3 private native) 'call-with-c-string))
(define call-with-out-pointer (reach '(chez-sqlite3 private native) 'call-with-out-pointer))

;; --- bindings made here, after the load ------------------------------------------------

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_prepare_v2(sqlite3*, const char *zSql, int nByte, sqlite3_stmt **, const char **pzTail)
(define prepare-v2 (bound 'sqlite3_prepare_v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int)))
;; int sqlite3_finalize(sqlite3_stmt*)
(define raw-finalize (bound 'sqlite3_finalize (foreign-procedure "sqlite3_finalize" (uptr) int)))

;; --- the forcing VFS ---------------------------------------------------------------------------
;; open-database admits no code of the suite's inside its sections, and its
;; connection does not exist before its open, so no trace or authorizer can
;; be given it: the low passes force through SQLite's VFS. The suite
;; registers, as SQLite's default, a copy of SQLite's own default VFS, its
;; every method SQLite's own but xAccess and xFullPathname, which call
;; force! and then SQLite's own, with SQLite's own VFS. SQLite calls
;; xFullPathname inside sqlite3_open_v2, the open's section, and xAccess as
;; a read transaction begins, inside the settings' prepares and steps. Both
;; callbacks are __collect_safe, as the library's calls into SQLite are;
;; they raise nothing, and they are locked until the suite's end, where the
;; VFS is unregistered and its memory freed. Apple's library takes a VFS,
;; though it refuses sqlite3_auto_extension.

;; sqlite3_vfs, as sqlite3.h has it, to iVersion 3.
(define-ftype sqlite3-vfs
  (struct (iVersion int) (szOsFile int) (mxPathname int) (pNext uptr) (zName uptr) (pAppData uptr)
          (xOpen uptr) (xDelete uptr) (xAccess uptr) (xFullPathname uptr)
          (xDlOpen uptr) (xDlError uptr) (xDlSym uptr) (xDlClose uptr)
          (xRandomness uptr) (xSleep uptr) (xCurrentTime uptr) (xGetLastError uptr)
          (xCurrentTimeInt64 uptr)
          (xSetSystemCall uptr) (xGetSystemCall uptr) (xNextSystemCall uptr)))

;; sqlite3_vfs *sqlite3_vfs_find(const char *zVfsName)
(define vfs-find (bound 'sqlite3_vfs_find (foreign-procedure "sqlite3_vfs_find" (uptr) uptr)))

;; int sqlite3_vfs_register(sqlite3_vfs*, int makeDflt)
(define vfs-register (bound 'sqlite3_vfs_register (foreign-procedure "sqlite3_vfs_register" (uptr int) int)))

;; int sqlite3_vfs_unregister(sqlite3_vfs*)
(define vfs-unregister (bound 'sqlite3_vfs_unregister (foreign-procedure "sqlite3_vfs_unregister" (uptr) int)))

;; sqlite-vfs : Natural
;; SQLite's default VFS, before the suite's: 0 where none was found.
(define sqlite-vfs (guard (e (#t 0)) (vfs-find 0)))

;; sqlite-method : Natural -> (U Natural #f)
;; Of SQLite's default VFS, the entry of xAccess (0) or xFullPathname (1).
(define (sqlite-method which)
  (and (not (eqv? sqlite-vfs 0))
       (let ((src (make-ftype-pointer sqlite3-vfs sqlite-vfs)))
         (if (eqv? which 0)
             (ftype-ref sqlite3-vfs (xAccess) src)
             (ftype-ref sqlite3-vfs (xFullPathname) src)))))

;; int (*xAccess)(sqlite3_vfs*, const char *zName, int flags, int *pResOut)
;; int (*xFullPathname)(sqlite3_vfs*, const char *zName, int nOut, char *zOut)
;; SQLite's own, bound by their entries; 1, SQLITE_ERROR, where none was found.
(define sqlite-access
  (let ((entry (sqlite-method 0)))
    (if entry (foreign-procedure entry (uptr uptr int uptr) int) (lambda args 1))))
(define sqlite-full-pathname
  (let ((entry (sqlite-method 1)))
    (if entry (foreign-procedure entry (uptr uptr int uptr) int) (lambda args 1))))

(define forcing-access
  (foreign-callable __collect_safe
    (lambda (vfs name flags out)
      (force!)
      (sqlite-access sqlite-vfs name flags out))
    (uptr uptr int uptr) int))

(define forcing-full-pathname
  (foreign-callable __collect_safe
    (lambda (vfs name n out)
      (force!)
      (sqlite-full-pathname sqlite-vfs name n out))
    (uptr uptr int uptr) int))

;; copied-fields : the named fields of sqlite3-vfs copied from SRC to DST.
(define-syntax copied-fields
  (syntax-rules ()
    ((_ src dst field ...)
     (begin (ftype-set! sqlite3-vfs (field) dst (ftype-ref sqlite3-vfs (field) src)) ...))))

;; c-text-copy : String -> Natural
;; S, ASCII, as a NUL-terminated C string, foreign-allocated.
(define (c-text-copy s)
  (let* ((n (string-length s))
         (p (foreign-alloc (+ n 1))))
    (let loop ((i 0))
      (when (< i n)
        (foreign-set! 'unsigned-8 p i (char->integer (string-ref s i)))
        (loop (+ i 1))))
    (foreign-set! 'unsigned-8 p n 0)
    p))

;; forcing-vfs : (U (List 'registered Natural Natural) (List Symbol Any))
;; The copy registered as the default, its address and its name's; or what
;; stopped it. The copy keeps the version of SQLite's, and the fields that
;; version has.
(define forcing-vfs
  (guard (e (#t (list 'raised (describe e))))
    (if (eqv? sqlite-vfs 0)
        (list 'no-default-vfs 0)
        (let* ((src (make-ftype-pointer sqlite3-vfs sqlite-vfs))
               (version (ftype-ref sqlite3-vfs (iVersion) src))
               (p (foreign-alloc (ftype-sizeof sqlite3-vfs)))
               (dst (make-ftype-pointer sqlite3-vfs p))
               (name (c-text-copy "chez-sqlite3-forcing")))
          (let loop ((i 0))
            (when (< i (ftype-sizeof sqlite3-vfs))
              (foreign-set! 'unsigned-8 p i 0)
              (loop (+ i 1))))
          (copied-fields src dst iVersion szOsFile mxPathname pAppData xOpen xDelete
                         xDlOpen xDlError xDlSym xDlClose xRandomness xSleep xCurrentTime xGetLastError)
          (when (>= version 2) (copied-fields src dst xCurrentTimeInt64))
          (when (>= version 3) (copied-fields src dst xSetSystemCall xGetSystemCall xNextSystemCall))
          (ftype-set! sqlite3-vfs (zName) dst name)
          (lock-object forcing-access)
          (lock-object forcing-full-pathname)
          (ftype-set! sqlite3-vfs (xAccess) dst (foreign-callable-entry-point forcing-access))
          (ftype-set! sqlite3-vfs (xFullPathname) dst (foreign-callable-entry-point forcing-full-pathname))
          (let ((rc (vfs-register p 1)))
            (if (eqv? rc 0)
                (list 'registered p name)
                (begin (foreign-free name) (foreign-free p) (list 'register-answered rc))))))))

;; forcing-vfs-default : -> Any
;; registered when SQLite's default VFS is now the suite's copy.
(define (forcing-vfs-default)
  (if (and (eq? (car forcing-vfs) 'registered) (eqv? (vfs-find 0) (cadr forcing-vfs)))
      'registered
      (list 'forcing-vfs forcing-vfs)))

;; forcing-vfs-removed : -> Any
;; The copy unregistered, SQLite's own the default again, the copy's memory
;; freed and its callbacks unlocked, once; or what went wrong.
(define (forcing-vfs-removed)
  (guard (e (#t (list 'raised (describe e))))
    (if (not (eq? (car forcing-vfs) 'registered))
        (list 'forcing-vfs forcing-vfs)
        (let ((rc (vfs-unregister (cadr forcing-vfs))))
          (foreign-free (cadr forcing-vfs))
          (foreign-free (caddr forcing-vfs))
          (unlock-object forcing-full-pathname)
          (unlock-object forcing-access)
          (list rc (if (eqv? (vfs-find 0) sqlite-vfs) 'sqlite-default 'not-sqlite-default))))))


;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (connection-count) (cdr (assq 'connection (native-counts))))
(define (statement-count) (cdr (assq 'statement (native-counts))))

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

(define (a-database? x) (guard (e (#t #f)) (database? x)))

(define (close-answer r)
  (guard (e (#t #f)) (close-database! r)))

(define (in-dir proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory proc)))

;; pragma : Database String -> Any
(define (pragma db name)
  (let ((row (query-row db (string-append "PRAGMA " name))))
    (if (vector? row) (vector-ref row 0) (list 'no-row row))))

(define pragma-names '("busy_timeout" "foreign_keys" "journal_mode" "synchronous" "temp_store" "trusted_schema"))

;; readings : Database -> (Listof Any)
;; The six settings on DB, in ADR-0018's table order, and its cache's
;; capacity, each read in order; or what a read raised.
(define (readings db)
  (attempt
   (lambda ()
     (let loop ((rest pragma-names) (found '()))
       (if (null? rest)
           (reverse (cons (database-cache-capacity db) found))
           (loop (cdr rest) (cons (pragma db (car rest)) found)))))))

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
;; A collection now, at a fuel's or a tick's start, with collect-trip-bytes
;; raised to 128 MiB, far above what one fuel's runs allocate, so no collect
;; request falls in them: one costs a run up to a tick, and the rows that
;; bound a whole new call read the fuels, or the ticks, in order.
(define (quieted!)
  (collect-trip-bytes (expt 2 27))
  (collect))

;; --- the two passes ---------------------------------------------------------------------
;; Pass = (U 'high 'low)
;; Each trial of the resumed-twice and re-entered rows begins with begun!:
;; quieted!'s collection, then PASS's trip. In the high pass it stays at
;; 2^27, so no collect request falls in a trial. In the low pass it is 256
;; bytes, below what one call allocates, until the trial ends: a request then
;; falls due all through it, and one due inside a critical section is
;; handled at the section's exit, where it costs the engine ticks. So an
;; expiry, or a timer's tick, can fall at a section's exit, before anything
;; after it. Every request the trials meet goes through counted-request, which
;; counts it, and the low rows judge where they fell (where a remainder lies,
;; below).

(define low-trip 256)

;; default-request-handler : (-> Any)
;; The collect-request handler the suite started with, which collects.
(define default-request-handler (collect-request-handler))

;; requests : Natural
;; The collect requests the trials of the pass under way met.
(define requests 0)

;; A request in a run before its expiry, or before a timer's capture, costs
;; the engine ticks there, so that run's remainder lies earlier in the call
;; than its fuel or tick says: a whole new call can come at a fuel at or past
;; one a trial was refused at, R before the call's first section, where a
;; request falls. So each trial notes whether a request fell before its
;; remainder was taken, and the sweep's bound on a whole new call reads only
;; the trials where none did; a whole new call where one did is counted and
;; printed, and judged by its other evidence. The bound's refusal may come
;; from any trial: a request moves a remainder earlier, never later.

;; counted-request : -> Any
(define (counted-request)
  (set! requests (+ requests 1))
  (default-request-handler)
  (exit-noted!))

;; --- where a remainder lies: at a forced section's exit ----------------------------------------
;; The forcing VFS calls back inside the library's critical sections: the
;; open's, through xFullPathname, and each setting's that begins a read
;; transaction, through xAccess (the forcing VFS, above). The re-entered row's
;; timer fires at every tick, so its ticks run out in every forced request's
;; handler, and it fires at that section's exit.
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

;; slice : Engine Positive-Integer -> (U (List 'completed Any) (List 'expired Engine))
;; Each slice's forced sections are judged met or unmet.
(define (slice e fuel)
  (slice-begun!)
  (let ((r (e fuel (lambda (left . vals) (list 'completed (car vals))) (lambda (more) (list 'expired more)))))
    (slice-ended!)
    r))

;; resumed-at : Engine Positive-Integer -> Any
;; E's answer, resumed one slice of FUEL at a time until it completes, at
;; most 100000 slices.
(define (resumed-at e fuel)
  (let loop ((e e) (n 0))
    (let ((r (slice e fuel)))
      (cond ((eq? (car r) 'completed) (cadr r))
            ((>= n 100000) 'never-completed)
            (else (loop (cadr r) (+ n 1)))))))

;; finish : Engine -> Any
(define (finish e) (resumed-at e 1000000))

;; sweep : (Positive-Integer -> (List Boolean Boolean (Listof Any))) -> (List Any (Listof Any) Natural)
;; CHECK at each fuel from 1 until the call completes without expiring, at
;; most 20000: that fuel, or no-completion; each fuel's deviations, in order;
;; and at how many fuels CHECK found a statement of the open's held at the
;; expiry. CHECK answers whether the call expired, whether one was held
;; then, and what deviated.
(define (sweep check)
  (let loop ((fuel 1) (deviations '()) (held 0))
    (let* ((r (check fuel))
           (deviations (if (null? (caddr r)) deviations (cons (cons fuel (caddr r)) deviations)))
           (held (if (cadr r) (+ held 1) held)))
      (cond ((not (car r)) (list fuel (reverse deviations) held))
            ((>= fuel 20000) (list 'no-completion-by-20000 (reverse deviations) held))
            (else (loop (+ fuel 1) deviations held))))))

;; named : String (List Any (Listof Any) Natural) -> (List Any Any)
;; RUN's deviations, summarized, and whether a statement was held at the
;; expiry of at least as many fuels as the settings prepare statements, two
;; a setting: so the sweep reached into the settings' statements, not one
;; fuel by chance. Its completing fuel and those fuels printed, naming WHAT.
(define (named what run)
  (display "  ")
  (display what)
  (if (integer? (car run))
      (begin (display " completed without expiring at fuel ") (display (car run)))
      (begin (display ": ") (write (car run))))
  (display "; a statement held at the expiry at ")
  (write (caddr run))
  (display " fuels")
  (newline)
  (list (if (integer? (car run)) (summarized (cadr run)) (list (car run) (summarized (cadr run))))
        (if (and (integer? (car run)) (>= (caddr run) (* 2 (length pragma-names))))
            'held-at-a-fuel-a-statement
            (list 'held-at (caddr run) 'of (car run)))))

(define (kind-count kinds k) (let ((p (assq k kinds))) (if p (cdr p) 0)))

;; --- the settings ---------------------------------------------------------------------------

;; settings : Settings
;; The six, busy-timeout among the rest, and statement-cache.
(define settings
  '((foreign-keys . #t) (journal-mode . truncate) (busy-timeout . 1234) (synchronous . extra)
    (temp-store . memory) (trusted-schema . #f) (statement-cache . 3)))

;; as-asked : (Listof Any)
;; What readings answers for a connection opened with settings.
(define as-asked '(1234 1 "truncate" 3 2 0 3))

;; otherwise : (Listof String)
;; Each of the six set to another value than settings asks, by the suite.
(define otherwise
  '("PRAGMA busy_timeout = 7" "PRAGMA foreign_keys = 0" "PRAGMA journal_mode = delete"
    "PRAGMA synchronous = 0" "PRAGMA temp_store = 0" "PRAGMA trusted_schema = 1"))

;; as-set-otherwise : (Listof Any)
(define as-set-otherwise '(7 0 "delete" 0 0 1 3))

(define (open-thunk path) (lambda () (attempt (lambda () (open-database path settings)))))

(test-begin "open-engines")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-equal "the forcing VFS, a copy of SQLite's default whose xAccess and xFullPathname call force! first, is registered as SQLite's default"
  'registered
  (forcing-vfs-default))

;; --- every fuel ---------------------------------------------------------------------------------

;; at-fuel : String Positive-Integer -> (List Boolean Boolean (Listof Any))
;; open-database on PATH with settings, as an engine, one slice of FUEL:
;; whether it expired; whether a statement was held then; and what deviated.
;; Expired, it is resumed at FUEL until it completes. Either way it answers a
;; database whose readings are as-asked, closed after, leaving nothing
;; counted.
(define (at-fuel path fuel)
  (let* ((r (slice (make-engine (open-thunk path)) fuel))
         (expired (eq? (car r) 'expired))
         (held (and expired (> (statement-count) 0)))
         (answer (if expired (resumed-at (cadr r) fuel) (cadr r)))
         (read (if (a-database? answer) (readings answer) (list 'not-a-database answer))))
    (when (a-database? answer) (close-answer answer))
    (list expired held
          (append (if (equal? read as-asked) '() (list (list 'readings read)))
                  (if (equal? (native-counts) zero-counts) '() (list (list 'counts (native-counts))))))))

(test-equal "open-database with the six settings and statement-cache on a file, as an engine, at every fuel from 1 until it completes without expiring: each fuel's open, resumed at its fuel until it completes, answers a connection whose every setting reads back as asked, its cache's capacity the list's; a setting's statement is held at as many expiries as the settings prepare statements, at least; nothing is left counted"
  (list '() 'held-at-a-fuel-a-statement zero-counts)
  (let ((r (in-dir (lambda (dir)
                     (let ((path (string-append dir "/e.db")))
                       (named "open-database with settings, resumed at its fuel"
                              (sweep (lambda (fuel) (at-fuel path fuel)))))))))
    (if (and (pair? r) (eq? (car r) 'raised))
        r
        (append r (list (native-counts))))))

;; --- resumed twice ------------------------------------------------------------------------------

;; set-otherwise! : Database -> Void
(define (set-otherwise! db)
  (let loop ((rest otherwise))
    (unless (null? rest)
      (execute! db (car rest))
      (loop (cdr rest)))))

;; twice : Pass String Positive-Integer -> (List Boolean Symbol (Listof Any) Boolean Boolean)
;; open-database on PATH with settings, as an engine, one slice of FUEL, in
;; PASS.
;; Completed, it is closed: (#f none () #f CLEAN). Expired, its remainder is resumed
;; to its end, FIRST, a database whose readings are as-asked; the suite sets
;; each of the six otherwise on it; and the same remainder is resumed again,
;; SECOND. Answers #t, what SECOND was, and what deviated:
;;   refused  &sqlite-closed from open-database, nothing touched;
;;   same     FIRST again, nothing touched, the remainder past the call's
;;            last section;
;;   new      another database, a whole new call: its readings as-asked;
;; and in each case FIRST still open, its readings as the suite set them,
;; and the statement count and FIRST's tracked statements as they were.
;; Once both are closed, nothing is counted. Then whether a connection was
;; counted at the expiry: the remainder lay past the open's section; and
;; whether no collect request fell in the first slice.
(define (twice pass path fuel)
  (begun! pass)
  (let* ((met requests)
         (r (first-slice (make-engine (open-thunk path)) fuel))
         (clean (= requests met)))
    (if (eq? (car r) 'completed)
        (begin (close-answer (cadr r)) (ended!) (list #f 'none '() #f clean))
        (let* ((more (cadr r))
               (open-at-expiry (> (connection-count) 0))
               (first (finish more))
               (first-read (if (a-database? first) (readings first) (list 'not-a-database first))))
          (if (not (a-database? first))
              (begin (ended!) (list #t 'none (list (list 'first first-read)) open-at-expiry clean))
              (let* ((set (attempt (lambda () (set-otherwise! first) 'set)))
                     (statements (statement-count))
                     (tracked (length (tracked-statements first)))
                     (second (finish more))
                     (kind (cond ((equal? second '(raised (closed open-database))) 'refused)
                                 ((and (a-database? second) (eq? second first)) 'same)
                                 ((a-database? second) 'new)
                                 (else 'other)))
                     (second-read (if (eq? kind 'new) (readings second) 'not-new))
                     (statements-after (statement-count))
                     (tracked-after (attempt (lambda () (length (tracked-statements first)))))
                     (first-after (readings first)))
                (when (eq? kind 'new) (close-answer second))
                (close-answer first)
                (ended!)
                (list #t kind
                      (append (if (equal? first-read as-asked) '() (list (list 'first first-read)))
                              (if (eq? set 'set) '() (list (list 'set set)))
                              (if (eq? kind 'other) (list (list 'second second)) '())
                              (if (or (not (eq? kind 'new)) (equal? second-read as-asked))
                                  '()
                                  (list (list 'second-read second-read)))
                              (if (equal? first-after as-set-otherwise) '()
                                  (list (list 'first-after first-after)))
                              (if (or (eq? kind 'new) (= statements-after statements)) '()
                                  (list (list 'statements statements statements-after)))
                              (if (equal? tracked-after tracked) '()
                                  (list (list 'tracked tracked tracked-after)))
                              (if (equal? (native-counts) zero-counts) '()
                                  (list (list 'counts (native-counts)))))
                      open-at-expiry clean)))))))

;; twice-sweep : Pass String -> (List Any (Listof Any) (Listof (Pairof Symbol Natural)) (U Natural #f) Natural)
;; twice at every fuel from 1 until the open completes without expiring, at
;; most 20000, in PASS, each fuel begun by begun!'s collection, so a
;; remainder lies further into the call's first expressions at each fuel
;; than at the one before: that fuel; each fuel's
;; deviations; how many fuels each kind of second resume came at; and the
;; first fuel at which a remainder taken before the open's section, no
;; connection counted at its expiry, was refused, #f for none. A whole new
;; call comes only from a remainder taken before the call's first
;; expression, and one taken past it and before the open is refused: so a
;; new one at a fuel past that refusal is a deviation, unless a collect
;; request fell in its first slice: those are counted, last. A bound from the
;; call refused at its first check, a filename that is no string, was
;; loose: it completed at fuel 68, the whole new calls ending at 9.
(define (twice-sweep pass path)
  (let loop ((fuel 1) (deviations '()) (refused 0) (same 0) (new 0) (refused-at #f) (moved 0))
    (let* ((r (twice pass path fuel))
           (kind (cadr r))
           (late (and (eq? kind 'new) refused-at))
           (late-new (and late (list-ref r 4)))
           (moved (if (and late (not (list-ref r 4))) (+ moved 1) moved))
           (found (if late-new (cons (list 'new-past-a-refusal refused-at) (caddr r)) (caddr r)))
           (deviations (if (null? found) deviations (cons (cons fuel found) deviations)))
           (refused-at (or refused-at (and (eq? kind 'refused) (not (cadddr r)) fuel)))
           (refused (if (eq? kind 'refused) (+ refused 1) refused))
           (same (if (eq? kind 'same) (+ same 1) same))
           (new (if (eq? kind 'new) (+ new 1) new)))
      (cond ((not (car r))
             (list fuel (reverse deviations) (list (cons 'refused refused) (cons 'same same) (cons 'new new))
                   refused-at moved))
            ((>= fuel 20000) (list 'no-completion-by-20000 (reverse deviations) '() refused-at moved))
            (else (loop (+ fuel 1) deviations refused same new refused-at moved))))))

(define twice-name
  "open-database's remainder resumed twice, at every fuel from 1 until it completes without expiring: resumed to its end it answers a connection as asked; the suite sets each of the six otherwise there; resumed again, it raises &sqlite-closed, refused at the open's section or a setting's, at half the fuels at least and at some before the open, or, past its last section, answers that connection again; only a remainder taken before the call's first expression makes a whole new call, its own connection as asked, below every refusal before the open; none applies a setting to the first connection again, closes it, or touches its statements, and nothing is left counted")

;; twice-reported : String Pass -> Any
;; twice-sweep in PASS, printed, naming WHAT, and judged: no deviation; a
;; refusal before the open seen, and refusals at half the fuels at least;
;; and, in the low pass, a remainder past the call's last section answering
;; the same connection at some fuel, and low-judged's three, each failing
;; by name.
(define (twice-reported what pass)
  (let-values (((r tally) (counted-pass (lambda () (in-dir (lambda (dir) (twice-sweep pass (string-append dir "/t.db"))))))))
    (if (and (pair? r) (eq? (car r) 'raised))
        r
        (let ((kinds (caddr r)) (refused-at (cadddr r)))
          (display "  ")
          (display what)
          (display ": completed without expiring at fuel ")
          (write (car r))
          (display "; second resumes ")
          (write kinds)
          (display "; refused before the open first at fuel ")
          (write refused-at)
          (display "; whole new calls past it, a collect request in the first slice, ")
          (write (list-ref r 4))
          (tally-shown tally)
          (newline)
          (append
           (list (summarized (cadr r))
                 (let ((refused (let ((p (assq 'refused kinds))) (if p (cdr p) 0))))
                   (if (and refused-at (integer? (car r)) (>= (* 2 refused) (car r)))
                       'refused-before-the-open-and-at-half-the-fuels
                       (list 'refused refused 'of (car r) 'before-the-open-first-at refused-at))))
           (if (eq? pass 'low)
               (cons (if (> (kind-count kinds 'same) 0)
                         'answered-again-past-its-last-section
                         (list 'none-past-its-last-section kinds))
                     (low-judged tally))
               '())
           (list (native-counts)))))))

(test-equal twice-name
  (list '() 'refused-before-the-open-and-at-half-the-fuels zero-counts)
  (twice-reported "open-database resumed twice" 'high))

(test-equal (string-append "the same, its trials under a collect trip of 256 bytes, so a request falls due in every run and one due inside a section costs ticks at its exit, the forcing VFS allocating 32 KiB inside the open's section and each setting's that begins a read: the same verdicts; at some fuel a remainder past the call's last section answers its connection again; and collect requests met in the trials, each forced section's request met before the next, and some first slice expired at a forced section's exit. " twice-name)
  (append (list '() 'refused-before-the-open-and-at-half-the-fuels 'answered-again-past-its-last-section)
          low-checks (list zero-counts))
  (twice-reported "open-database resumed twice, low trip" 'low))

;; --- call-with-database, re-entered through a timer's continuation ------------------------------

;; reentered-at : Pass String Positive-Integer -> (U 'no-capture (List Natural Any Natural))
;; In PASS, call-with-database on PATH with settings, a timer's handler taking a
;; continuation at the call's tick I, the timer stopped there or at the
;; procedure's start. The procedure, called first, sets each of the six
;; otherwise and re-enters that continuation, once; called again, it reads
;; the six and answers (nested-call READINGS). Answers no-capture when tick I
;; fell after the procedure started; else the connections counted at the
;; capture, what the re-entry answered when it came back, and how many more
;; calls of the procedure it made. The re-entry's raise reaches the guard
;; around the call, whose continuation hands it back to the procedure.
(define (reentered-at pass path i)
  (begun! pass)
  (let* ((met requests)
         (r (reentry-run path i))
         (clean (= requests-at-capture met)))
    (ended!)
    (cons clean r)))

;; requests-at-capture : Natural
;; The collect requests counted when the timer's handler took its
;; continuation, or when the run began, where it took none.
(define requests-at-capture 0)

;; reentry-run : String Positive-Integer -> (U 'no-capture (List Natural Any Natural))
;; reentered-at's run, inside its pass's trip.
(define (reentry-run path i)
  (set! requests-at-capture requests)
  (let ((ticks 0) (saved #f) (phase #f) (return-to #f) (calls 0) (old (timer-interrupt-handler)))
    (define (proc db)
      (set-timer 0)
      (set! calls (+ calls 1))
      (cond ((> calls 1) (list 'nested-call (readings db)))
            ((not saved) 'no-capture)
            (else
             (set-otherwise! db)
             (let* ((before calls)
                    (r (call/cc (lambda (back) (set! return-to back) (saved #f)))))
               (list phase r (- calls before))))))
    (dynamic-wind
      (lambda ()
        (timer-interrupt-handler
         (lambda ()
           (set! ticks (+ ticks 1))
           (let ((at-exit (ticked!)))
             (if (= ticks i)
                 (begin (set! phase (connection-count))
                        (set! requests-at-capture requests)
                        (captured-at! at-exit)
                        (call/cc (lambda (k) (set! saved k))))
                 (set-timer 1))))))
      (lambda ()
        (call-begun!)
        (set-timer 1)
        (let ((r (attempt (lambda () (call-with-database path settings proc)))))
          (set-timer 0)
          (call-ended!)
          (if return-to
              (let ((back return-to)) (set! return-to #f) (back r))
              r)))
      (lambda ()
        (set-timer 0)
        (call-ended!)
        (timer-interrupt-handler old)))))

;; reentry-sweep : Pass String -> (List Natural (Listof Any) (Listof (Pairof Symbol Natural)) (U Natural #f) Natural)
;; reentered-at at each tick from 1 until one falls after the procedure
;; starts, at most 20000, in PASS, each tick begun by begun!'s collection,
;; so a continuation lies further into the call's first expressions at each
;; tick than at the one before: that
;; tick; each tick's deviations, with the counts after its call; how many
;; re-entries were refused, how many called the procedure again past the
;; settings, and how many made a whole new call; and the first tick at
;; which one taken before the open, no connection counted at the capture,
;; was refused, #f for none. A whole new call, its own connection as asked,
;; comes only from a continuation taken before the call's first expression,
;; and one taken past it and before the open is refused: so a new one at a
;; tick past that refusal is a deviation, unless a collect request fell in
;; the call before the capture: those are counted, last. A bound from the call refused at
;; its first check was loose: it took 71 ticks, the whole new calls ending
;; at 8.
(define (reentry-sweep pass path)
  (let loop ((i 1) (deviations '()) (refused 0) (again 0) (new 0) (refused-at #f) (moved 0))
    (let* ((p (reentered-at pass path i))
           (clean (car p))
           (r (cdr p))
           (counts (native-counts))
           (kind (reentry-kind r))
           (late (and (eq? kind 'new) refused-at))
           (moved (if (and late (not clean)) (+ moved 1) moved))
           (found (append (if (eq? kind 'deviation) (list r) '())
                          (if (and late clean) (list (list 'new-past-a-refusal refused-at)) '())
                          (if (equal? counts zero-counts) '() (list (list 'counts counts)))))
           (deviations (if (null? found) deviations (cons (cons i found) deviations)))
           (refused-at (or refused-at (and (eq? kind 'refused) (eqv? (car r) 0) i))))
      (cond ((or (eq? kind 'done) (>= i 20000))
             (list i (reverse deviations)
                   (list (cons 'refused refused) (cons 'again again) (cons 'new new))
                   refused-at moved))
            (else (loop (+ i 1) deviations
                        (if (eq? kind 'refused) (+ refused 1) refused)
                        (if (eq? kind 'again) (+ again 1) again)
                        (if (eq? kind 'new) (+ new 1) new)
                        refused-at moved))))))

;; reentry-kind : (U 'no-capture (List Natural Any Natural)) -> (U 'done 'refused 'again 'new 'deviation)
;; R, what reentered-at answered, as a kind: done, no capture; refused,
;; &sqlite-closed and the procedure not called again; again, the procedure
;; called again, finding the six as the suite set them; new, the procedure
;; called again on a whole new call's connection, as asked; else a
;; deviation.
(define (reentry-kind r)
  (cond ((eq? r 'no-capture) 'done)
        ((and (list? r) (= (length r) 3)
              (equal? (cadr r) '(raised (closed call-with-database)))
              (eqv? (caddr r) 0))
         'refused)
        ((and (list? r) (= (length r) 3)
              (equal? (cadr r) (list 'nested-call as-set-otherwise))
              (eqv? (caddr r) 1))
         'again)
        ((and (list? r) (= (length r) 3)
              (equal? (cadr r) (list 'nested-call as-asked))
              (eqv? (caddr r) 1))
         'new)
        (else 'deviation)))

(define reentry-name
  "call-with-database re-entered through a continuation a timer's handler took at each tick from 1 until its procedure starts, the procedure re-entering it once the suite has set each of the six otherwise: taken before the settings were done, it raises &sqlite-closed, refused at the open's section or a setting's, and the procedure is not called again; taken past their last section, it calls the procedure again, which finds the six as the suite set them; refused at half the ticks at least and at some before the open; only one taken before the call's first expression makes a whole new call, below every refusal before the open; none applies a setting again to the first connection or leaves a connection open, and nothing is left counted")

;; reentry-reported : String Pass -> Any
;; reentry-sweep in PASS, printed, naming WHAT, and judged: no deviation;
;; refusals at half the ticks at least, one before the open; and, in the
;; low pass, a continuation past the settings' last section calling the
;; procedure again at some tick, and low-judged's three, each failing by
;; name.
(define (reentry-reported what pass)
  (let-values (((r tally) (counted-pass (lambda () (in-dir (lambda (dir) (reentry-sweep pass (string-append dir "/c.db"))))))))
    (if (and (pair? r) (eq? (car r) 'raised))
        r
        (let ((kinds (caddr r)) (refused-at (cadddr r)))
          (display "  ")
          (display what)
          (display ": its procedure started at tick ")
          (write (car r))
          (display "; re-entries ")
          (write kinds)
          (display "; refused before the open first at tick ")
          (write refused-at)
          (display "; whole new calls past it, a collect request before the capture, ")
          (write (list-ref r 4))
          (tally-shown tally)
          (newline)
          (append
           (list (summarized (cadr r))
                 (let ((refused (cdr (assq 'refused kinds))))
                   (if (and refused-at (>= (* 2 refused) (car r)))
                       'refused-before-the-open-and-at-half-the-ticks
                       (list 'refused refused 'of (car r) 'before-the-open-first-at refused-at))))
           (if (eq? pass 'low)
               (cons (if (> (kind-count kinds 'again) 0)
                         'called-again-past-the-settings
                         (list 'none-past-the-settings kinds))
                     (low-judged tally))
               '())
           (list (native-counts)))))))

(test-equal reentry-name
  (list '() 'refused-before-the-open-and-at-half-the-ticks zero-counts)
  (reentry-reported "call-with-database re-entered" 'high))

(test-equal (string-append "the same, its trials under a collect trip of 256 bytes, the forcing VFS allocating 32 KiB inside the open's section and each setting's that begins a read: the same verdicts; at some tick a continuation past the settings' last section calls the procedure again; and collect requests met in the trials, each forced section's request met before the next, and some capture made at a forced section's exit. " reentry-name)
  (append (list '() 'refused-before-the-open-and-at-half-the-ticks 'called-again-past-the-settings)
          low-checks (list zero-counts))
  (reentry-reported "call-with-database re-entered, low trip" 'low))

;; --- call-with-database under an engine ---------------------------------------------------------

;; cwd-at-fuel : String Positive-Integer -> (List Boolean Symbol (Listof Any))
;; call-with-database on PATH with settings, its procedure answering how
;; many statements its connection tracks and its readings, as an engine,
;; one slice of FUEL, twice: the first remainder dropped, the second resumed
;; to its end. Answers whether it expired; what the resumed one answered,
;; as a kind: as-asked, nothing tracked and every reading as asked; closed,
;; &sqlite-closed from call-with-database, the expiry before the procedure;
;; closed-in-proc, the procedure's readings refused, the expiry inside it,
;; since an expiry closes the connection; and what deviated: any other
;; answer, a procedure called more than once a call, or anything counted
;; after the dropped remainder or after the resumed one.
(define (cwd-at-fuel path fuel)
  (let* ((calls 0)
         (proc (lambda (db)
                 (set! calls (+ calls 1))
                 (let* ((tracked (length (tracked-statements db)))
                        (read (readings db)))
                   (list tracked read))))
         (thunk (lambda () (attempt (lambda () (call-with-database path settings proc)))))
         (dropped (slice (make-engine thunk) fuel))
         (after-drop (native-counts))
         (dropped-calls calls)
         (r (begin (set! calls 0) (slice (make-engine thunk) fuel)))
         (expired (eq? (car r) 'expired))
         (answer (if expired (finish (cadr r)) (cadr r)))
         (kind (cond ((equal? answer (list 0 as-asked)) 'as-asked)
                     ((equal? answer '(raised (closed call-with-database))) 'closed)
                     ((equal? answer '(0 (raised (closed query-row)))) 'closed-in-proc)
                     (else 'other))))
    (list expired kind
          (append (if (eq? kind 'other) (list (list 'answer answer)) '())
                  (if (<= dropped-calls 1) '() (list (list 'dropped-calls dropped-calls)))
                  (if (<= calls 1) '() (list (list 'calls calls)))
                  (if (equal? after-drop zero-counts) '() (list (list 'after-drop after-drop)))
                  (if (equal? (native-counts) zero-counts) '() (list (list 'counts (native-counts))))))))

;; cwd-sweep : String -> (List Any (Listof Any) (Listof (Pairof Symbol Natural)))
;; cwd-at-fuel at every fuel from 1 until the call completes without
;; expiring, at most 20000: that fuel; each fuel's deviations; and how many
;; fuels gave each kind.
(define (cwd-sweep path)
  (let loop ((fuel 1) (deviations '()) (kinds '()))
    (let* ((r (cwd-at-fuel path fuel))
           (deviations (if (null? (caddr r)) deviations (cons (cons fuel (caddr r)) deviations)))
           (kinds (let ((k (assq (cadr r) kinds)))
                    (if k
                        (cons (cons (car k) (+ (cdr k) 1)) (remq k kinds))
                        (cons (cons (cadr r) 1) kinds)))))
      (cond ((not (car r)) (list fuel (reverse deviations) kinds))
            ((>= fuel 20000) (list 'no-completion-by-20000 (reverse deviations) kinds))
            (else (loop (+ fuel 1) deviations kinds))))))

(test-equal "call-with-database with the six settings and statement-cache on a file, as an engine, at every fuel from 1 until it completes without expiring: a remainder dropped leaves nothing counted, since the expiry closed the connection; a remainder resumed to its end answers the procedure's readings, as asked with nothing tracked, or &sqlite-closed, from call-with-database or from the procedure's own reads, never another answer; the procedure is called once a call at most; some fuels give each kind, and nothing is left counted"
  (list '() 'some-as-asked 'some-closed zero-counts)
  (let ((r (in-dir (lambda (dir) (cwd-sweep (string-append dir "/w.db"))))))
    (if (and (pair? r) (eq? (car r) 'raised))
        r
        (let ((kinds (caddr r)))
          (display "  call-with-database with settings, resumed: completed without expiring at fuel ")
          (write (car r))
          (display "; kinds ")
          (write kinds)
          (newline)
          (list (summarized (cadr r))
                (if (> (kind-count kinds 'as-asked) 0) 'some-as-asked 'none-as-asked)
                (if (> (+ (kind-count kinds 'closed) (kind-count kinds 'closed-in-proc)) 0)
                    'some-closed 'none-closed)
                (native-counts))))))

;; --- a failing close beside a refused re-entry ------------------------------------------------

;; raw-prepare! : Database String -> Positive-Integer
;; A statement of SQL on DB, made with the raw sqlite3_prepare_v2, so the
;; connection does not track it, and its close is refused.
(define (raw-prepare! db sql)
  (call-with-open-handle 'test-open-engines db
    (lambda (h)
      (call-with-c-string 'test-open-engines sql
        (lambda (text)
          (let-values (((rc statement)
                        (call-with-out-pointer 'test-open-engines
                          (lambda (slot) (prepare-v2 h text -1 slot 0)))))
            (if (and (eqv? rc 0) (not (eqv? statement 0)))
                statement
                (error 'raw-prepare! "sqlite3_prepare_v2 did not answer a statement" rc))))))))

;; untracked-reentry-at : String Positive-Integer -> (U 'no-capture (List Natural Any Natural Natural))
;; call-with-database on PATH with settings, a timer's handler taking a
;; continuation at the call's tick I, as reentered-at's does. The
;; procedure, called first, makes a statement its connection does not track,
;; so the call's close fails, and re-enters that continuation, once; called
;; again, it answers called-again. Answers no-capture when tick I fell after
;; the procedure started; else the connections counted at the capture, 0
;; before the open and 1 after it; what the call answered, by attempt; the
;; connections counted then; and how many more calls of the procedure the
;; re-entry made. The statement is then finalized and the connection
;; closed. The re-entry's raise reaches the guard around the call.
(define (untracked-reentry-at path i)
  (let ((ticks 0) (saved #f) (phase #f) (the-db #f) (raw #f) (calls 0) (old (timer-interrupt-handler)))
    (define (proc db)
      (set-timer 0)
      (set! calls (+ calls 1))
      (cond ((> calls 1) 'called-again)
            ((not saved) 'no-capture)
            (else
             (set! the-db db)
             (set! raw (raw-prepare! db "select 1"))
             (saved #f))))
    (let ((r (dynamic-wind
               (lambda ()
                 (timer-interrupt-handler
                  (lambda ()
                    (set! ticks (+ ticks 1))
                    (if (= ticks i)
                        (begin (set! phase (connection-count))
                               (call/cc (lambda (k) (set! saved k))))
                        (set-timer 1)))))
               (lambda ()
                 (set-timer 1)
                 (let ((r (attempt (lambda () (call-with-database path settings proc)))))
                   (set-timer 0)
                   r))
               (lambda ()
                 (set-timer 0)
                 (timer-interrupt-handler old)))))
      (let ((counted (connection-count)))
        (when raw (raw-finalize raw))
        (when the-db (close-answer the-db))
        (if (eq? r 'no-capture) 'no-capture (list phase r counted (- calls 1)))))))

;; untracked-sweep : String -> (List Natural (Listof Any) (List Symbol Symbol))
;; untracked-reentry-at at each tick from 1 until the procedure starts, at
;; most 20000, each judged by its own capture, never by another run's: a
;; collect request costs a run up to a tick, so two runs' ticks can differ.
;; With the connection open at the capture, the continuation lies inside the
;; call's extent: refused at a setting's section, the call raises
;; &sqlite-closed, the close's refusal not raised over it; or, past the
;; settings, the procedure is called again and returns, so the close's refusal
;; is raised. Before the open, a continuation inside the extent is refused at
;; the open's section, the same &sqlite-closed; one before the extent, or
;; before the call's first expression, is left by the procedure's jump, so the
;; close's refusal is raised, the procedure not called again. The connection
;; stays open and counted each time. Answers that tick; each tick's
;; deviations, with the counts after it; and whether some tick before the
;; open, and some after it, answered &sqlite-closed: the open's refusal and
;; the settings' are each marked, so the close's refusal is never raised over
;; them.
(define (untracked-sweep path)
  (let ((closed '((raised (closed call-with-database)) 1 0))
        (left '(raised (assertion-violation call-with-database (untracked-statements 1)))))
    (let loop ((i 1) (deviations '()) (before 'none-closed-before-the-open)
               (after 'none-closed-after-the-open))
      (let ((r (untracked-reentry-at path i)))
        (if (or (eq? r 'no-capture) (>= i 20000))
            (list i (reverse deviations) (list before after))
            (let* ((phase (car r))
                   (answer (cdr r))
                   (fine (if (eqv? phase 1)
                             (or (equal? answer closed) (equal? answer (list left 1 1)))
                             (or (equal? answer closed) (equal? answer (list left 1 0)))))
                   (found (append (if fine '() (list (list 'phase phase answer)))
                                  (if (equal? (native-counts) zero-counts) '()
                                      (list (list 'counts (native-counts)))))))
              (loop (+ i 1)
                    (if (null? found) deviations (cons (cons i found) deviations))
                    (if (and (eqv? phase 0) (equal? answer closed)) 'some-closed-before-the-open before)
                    (if (and (eqv? phase 1) (equal? answer closed)) 'some-closed-after-the-open after))))))))

(test-equal "call-with-database's procedure leaves a statement its connection does not track, so the close fails, then re-enters a continuation a timer's handler took at each tick from 1 until the procedure starts: inside the call's extent, refused at the open's section or a setting's, the call raises &sqlite-closed, the close's refusal not raised over it, at some tick before the open and some after; once the connection was open, only that, or the procedure called again past the settings and the close's refusal raised; before the open, a continuation outside the extent is left by the procedure, so the close's refusal is raised; the connection stays open and counted, and nothing is left counted once the statement is gone"
  (list '() '(some-closed-before-the-open some-closed-after-the-open) zero-counts)
  (let ((r (in-dir (lambda (dir) (untracked-sweep (string-append dir "/u.db"))))))
    (if (and (pair? r) (eq? (car r) 'raised))
        r
        (begin
          (display "  call-with-database re-entered with its close refused: its procedure started at tick ")
          (write (car r))
          (newline)
          (list (summarized (cadr r)) (caddr r) (native-counts))))))

(test-equal "the forcing VFS is unregistered once every connection is closed, SQLite's own the default again, its memory freed and its callbacks unlocked"
  '(0 sqlite-default)
  (forcing-vfs-removed))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "open-engines")

(exit (suite-exit-status runner))
