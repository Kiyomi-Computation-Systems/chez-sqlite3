#!r6rs
;;; The suite for db_config's four settings at open under engines (ADR-0018,
;;; ADR-0021), in
;;; (chez-sqlite3 private open). Each set is one more critical section of the
;;; call, at the next position of its claim, claimed inside it: a run the call
;;; has passed is refused there, touching nothing.
;;;
;;;   clean          the open with the three ops and the opt-in among the six
;;;                  PRAGMAs and statement-cache, through both verbs, with no
;;;                  engine: every setting reads back as asked
;;;   every fuel     open-database with that list on a file, at every fuel
;;;                  from 1 until it completes without expiring, each fuel's
;;;                  open resumed at its fuel until it completes: every
;;;                  setting reads back as asked, each op by the suite's own -1
;;;                  read through native, the record holding the opt-in
;;;   resumed twice  the remainder resumed to its end, the suite then setting
;;;                  every PRAGMA and every op otherwise, through native for
;;;                  the ops, then resumed again: refused with &sqlite-closed,
;;;                  or the same connection past the call's last section, or a
;;;                  whole new call only below a refusal the sweep saw before
;;;                  the open; the first connection keeps what the suite set,
;;;                  so no set ran again on it
;;;   re-entered     call-with-database, a timer's continuation taken at each
;;;                  tick until its procedure starts, re-entered by the
;;;                  procedure once it has set everything otherwise: refused
;;;                  before the procedure, or the procedure called again past
;;;                  the sets, finding what it set
;;;   under an       call-with-database at every fuel: a dropped remainder
;;;   engine         leaves nothing counted; a resumed one answers as asked or
;;;                  &sqlite-closed
;;;   interleaved    open-database's remainder R at every fuel, R1 taken from
;;;                  R's resume at every later fuel, R resumed again to its
;;;                  end, then R1: each run answers the connection or is
;;;                  refused touching nothing, no connection is left open
;;;                  unanswered, and the one answered reads as asked; two
;;;                  connections, a whole new call's, only below the first
;;;                  fuel at which a trial of the sweep was refused, R taken
;;;                  before the open
;;;   once a call    applied-settings/with on a connection of the suite's, the
;;;                  four and a PRAGMA, through a stand-in that counts each
;;;                  call and passes it to native's binding: interleaved as
;;;                  above, each op's set made once a call, in order, by
;;;                  whichever run reaches it first; a whole new call's only
;;;                  below the first fuel at which a trial of the sweep was
;;;                  refused, R taken before the first set
;;;   two passes     resumed twice, re-entered and both interleaved rows twice:
;;;                  with no collect request in a trial, and under a collect
;;;                  trip of 256 bytes, where a request due inside a critical
;;;                  section is handled at its exit and costs the engine ticks
;;;                  there, so a remainder or a continuation is taken at a
;;;                  set's exit too, before anything after it: a claim
;;;                  advanced just after its section, not inside it, set an op
;;;                  twice there. A
;;;                  forcing VFS, SQLite's default with xAccess and
;;;                  xFullPathname wrapped, allocates 32 KiB inside the open's
;;;                  section and each setting's that begins a read, so a
;;;                  request falls due there. The low pass fails by name unless
;;;                  collect requests fell in its trials, unless each forced
;;;                  section met its request before the next, which a trip
;;;                  slipped to 256 KiB does not, and unless some first slice,
;;;                  or capture, ran out at a forced section's exit, which the
;;;                  high pass never does; and the once-a-call low row unless some trial had
;;;                  R before the call's last set and R1 past it, which no
;;;                  trial of the high pass has: no tick falls after the last
;;;                  set's section before the call returns. Its stand-in
;;;                  allocates inside each set's section, so a request falls
;;;                  due there; the forcing VFS forces none of open-database's
;;;                  sets, where the straddle came by chance, 150 trials on
;;;                  Guix's library and 4 on the no-load build, so its row
;;;                  does not ask it
;;;   a failing set  applied-settings/with whose stand-in fails the second
;;;   twice          set, resumed to its end twice at every fuel: the first
;;;                  raises its &sqlite-error, the connection closed; the second
;;;                  is refused or raises it again past the close, and calls
;;;                  the stand-in no more
;;;
;;; Where the library lacks sqlite3_load_extension, as Apple's does, the
;;; opt-in would refuse every open, so its list leaves the opt-in out, and a
;;; line names it unavailable (ADR-0005); the rest run. An engine
;;; spends no ticks inside a critical section, so the fuels measure the Scheme
;;; work between the call's sections. Each trial begins with
;;; a collection, so its first slice runs as every trial's at that fuel
;;; does, unless a collect request falls in it (below), whichever pass; in
;;; the high pass collect-trip-bytes is then raised
;;; far above what its runs allocate, so no collect request falls in them.
;;; Each trial is judged by what
;;; it saw itself, and each bound on a whole new call is a refusal the sweep
;;; saw itself, R taken before the call's first section: never a refused
;;; call's fuel, a control run on the code under test, or a caller's count.
;;; The interleaved rows judge a trial by what it saw itself: a control run
;;; at its fuel would be moved from the trial by a low trip.

;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) make-engine set-timer timer-interrupt-handler collect collect-trip-bytes
              collect-request-handler foreign-ref foreign-procedure foreign-callable
              foreign-callable-entry-point lock-object unlock-object define-ftype ftype-ref ftype-set!
              make-ftype-pointer ftype-sizeof foreign-alloc foreign-free foreign-set! scheme-environment)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3 private constants) sqlite-dbconfig-enable-load-extension
              sqlite-dbconfig-defensive sqlite-dbconfig-dqs-dml sqlite-dbconfig-dqs-ddl)
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
(define applied-settings/with (reach '(chez-sqlite3 private open) 'applied-settings/with))
(define database-extension-loading?
  (reach '(chez-sqlite3 private connection) 'database-extension-loading?))
(define tracked-statements (reach '(chez-sqlite3 private connection) 'tracked-statements))
(define database-cache-capacity (reach '(chez-sqlite3 private connection) 'database-cache-capacity))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define call-with-int-cell (reach '(chez-sqlite3 private native) 'call-with-int-cell))
(define sqlite3-db-config (reach '(chez-sqlite3 private native) 'sqlite3-db-config))

;; available : Any
;; native's record of sqlite3_load_extension, which an open that opts in reads.
(define available
  (guard (e (#t (list 'unreached (describe e))))
    (eval 'load-extension-available? (environment '(chez-sqlite3 private native)))))

;; --- bindings made here, after the load ------------------------------------------------

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

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

(define (yes-no x) (cond ((eq? x #t) 'yes) ((eq? x #f) 'no) (else (list 'neither x))))

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

(define (kind-count kinds k) (let ((p (assq k kinds))) (if p (cdr p) 0)))

;; counted-up : Symbol (Listof (Pairof Symbol Natural)) -> (Listof (Pairof Symbol Natural))
(define (counted-up k kinds)
  (cond ((null? kinds) (list (cons k 1)))
        ((eq? (car (car kinds)) k) (cons (cons k (+ (cdr (car kinds)) 1)) (cdr kinds)))
        (else (cons (car kinds) (counted-up k (cdr kinds))))))

;; --- the ops, through native ----------------------------------------------------------------

;; read-ops : (Listof (Pairof Symbol Natural))
;; The ops the readings read, by name and op, constants.sls's, which
;; test-constants holds to sqlite3.h: the opt-in's where the library has
;; sqlite3_load_extension, then defensive, dqs-dml and dqs-ddl.
(define read-ops
  (append (if (eq? available #t)
              (list (cons 'enable-load-extension sqlite-dbconfig-enable-load-extension))
              '())
          (list (cons 'defensive sqlite-dbconfig-defensive)
                (cons 'dqs-dml sqlite-dbconfig-dqs-dml)
                (cons 'dqs-ddl sqlite-dbconfig-dqs-ddl))))

;; next-fill : Natural
;; The sentinel the next read fills its cell with, each read its own.
(define next-fill 700)
(define (fresh-fill!) (set! next-fill (+ next-fill 1)) next-fill)

;; op-call : Database Natural Integer -> (List Integer (U Integer 'left))
;; One sqlite3_db_config call on DB through native, OP given VALUE, -1 to
;; read: its code, and its cell, left when it still holds the call's fill.
(define (op-call db op value)
  (call-with-open-handle 'test-open-db-config-engines db
    (lambda (h)
      (let ((fill (fresh-fill!)))
        (let-values (((code cell)
                      (call-with-int-cell 'test-open-db-config-engines fill
                        (lambda (c) (sqlite3-db-config h op value c)))))
          (list code (if (eqv? cell fill) 'left cell)))))))

;; op-reads : Database -> (Listof (List Integer (U Integer 'left)))
(define (op-reads db)
  (let loop ((rest read-ops) (found '()))
    (if (null? rest)
        (reverse found)
        (loop (cdr rest) (cons (op-call db (cdr (car rest)) -1) found)))))

;; --- the settings ---------------------------------------------------------------------------

;; settings : Settings
;; The six PRAGMAs, busy-timeout among the rest, statement-cache, and the
;; three ops off their start, with the opt-in among them where the library
;; has sqlite3_load_extension.
(define settings
  (append '((foreign-keys . #t) (defensive . #t) (journal-mode . truncate) (dqs-dml . #f)
            (busy-timeout . 1234) (synchronous . extra))
          (if (eq? available #t) '((enable-load-extension . #t)) '())
          '((dqs-ddl . #f) (temp-store . memory) (trusted-schema . #f) (statement-cache . 3))))

(define pragma-names '("busy_timeout" "foreign_keys" "journal_mode" "synchronous" "temp_store" "trusted_schema"))

;; readings : Database -> Any
;; The six PRAGMAs on DB, in ADR-0018's table order, its cache's capacity,
;; the ops read-ops names, and the record's opt-in, each read in order; or
;; what a read raised.
(define (readings db)
  (attempt
   (lambda ()
     (let* ((pragmas (let loop ((rest pragma-names) (found '()))
                       (if (null? rest)
                           (reverse found)
                           (loop (cdr rest) (cons (pragma db (car rest)) found)))))
            (capacity (database-cache-capacity db))
            (ops (op-reads db))
            (opt-in (yes-no (database-extension-loading? db))))
       (append pragmas (list capacity ops opt-in))))))

;; as-asked : (Listof Any)
(define as-asked
  (list 1234 1 "truncate" 3 2 0 3
        (append (if (eq? available #t) '((0 1)) '()) '((0 1) (0 0) (0 0)))
        (if (eq? available #t) 'yes 'no)))

;; otherwise : (Listof String)
(define otherwise
  '("PRAGMA busy_timeout = 7" "PRAGMA foreign_keys = 0" "PRAGMA journal_mode = delete"
    "PRAGMA synchronous = 0" "PRAGMA temp_store = 0" "PRAGMA trusted_schema = 1"))

;; ops-otherwise : (Listof (Pairof Natural Integer))
;; Each op read-ops names set to the value other than settings asks.
(define ops-otherwise
  (append (if (eq? available #t) (list (cons sqlite-dbconfig-enable-load-extension 0)) '())
          (list (cons sqlite-dbconfig-defensive 0) (cons sqlite-dbconfig-dqs-dml 1)
                (cons sqlite-dbconfig-dqs-ddl 1))))

;; as-set-otherwise : (Listof Any)
;; What readings answers once set-otherwise! has run: the record's opt-in,
;; fixed when it was made, unchanged.
(define as-set-otherwise
  (list 7 0 "delete" 0 0 1 3
        (append (if (eq? available #t) '((0 0)) '()) '((0 0) (0 1) (0 1)))
        (if (eq? available #t) 'yes 'no)))

;; set-otherwise! : Database -> Void
;; Each PRAGMA set otherwise by execute!, then each op by native's binding,
;; each set's answer required 0 with its value in the cell.
(define (set-otherwise! db)
  (let loop ((rest otherwise))
    (unless (null? rest)
      (execute! db (car rest))
      (loop (cdr rest))))
  (let loop ((rest ops-otherwise))
    (unless (null? rest)
      (let ((r (op-call db (car (car rest)) (cdr (car rest)))))
        (unless (equal? r (list 0 (cdr (car rest))))
          (error 'set-otherwise! "a set the suite made did not take" (car rest) r)))
      (loop (cdr rest)))))

(define (open-thunk path) (lambda () (attempt (lambda () (open-database path settings)))))

;; --- engines ------------------------------------------------------------------------------

;; quieted! : -> Void
(define (quieted!)
  (collect-trip-bytes (expt 2 27))
  (collect))

;; Pass = (U 'high 'low)
;; Each trial of the two passes begins with begun!: quieted!'s collection,
;; then PASS's trip. In the high pass it stays at 2^27, so no collect
;; request falls in a trial. In the low pass it is 256 bytes, below what one
;; call allocates, until the trial ends: a request then falls due all
;; through it, and one due inside a critical section is handled at the
;; section's exit, where it costs the engine ticks, so an expiry or a timer's
;; tick can fall at a set's exit, before anything after it.
;; Every request the trials meet goes through counted-request, which counts
;; it, and the low rows judge where they fell (where a remainder lies,
;; below).

(define low-trip 256)

;; default-request-handler : (-> Any)
(define default-request-handler (collect-request-handler))

;; requests : Natural
;; The collect requests the trials of the pass under way met.
(define requests 0)

;; A request in a run before its expiry, or before a timer's capture, costs
;; the engine ticks there, so that run's remainder lies earlier in the call
;; than its fuel or tick says: a whole new call came at a fuel at or past
;; one a trial was refused at, R before the call's first section, where a
;; request fell. So each trial notes
;; whether a request fell before its remainder was taken, and the sweep's
;; bound on a whole new call reads only the trials where none did; a whole
;; new call where one did is counted and printed, and judged by its other
;; evidence. The bound's refusal may come from any trial: a request moves a
;; remainder earlier, never later.

(define (counted-request)
  (set! requests (+ requests 1))
  (default-request-handler)
  (exit-noted!))

;; --- where a remainder lies: at a forced section's exit ----------------------------------------
;; The forcing VFS calls back inside the library's critical sections: the
;; open's, through xFullPathname, and each setting's that begins a read
;; transaction, through xAccess (the forcing VFS, above); once-trial's
;; stand-in, inside each set's section. The re-entered row's timer fires at
;; every tick, so its ticks run out in every forced request's handler, and
;; it fires at that section's exit.
;; In the low pass force! allocates 32 KiB there, so a collect request falls
;; due inside the section and is handled at its exit, the first event check
;; once the section enables interrupts again. The handler's own work costs
;; the engine ticks. Where they run out in it, the engine's timer reads #f
;; at its end, and the engine expires as the handler returns: the remainder
;; lies at that section's exit, before anything after it. A probe's marker,
;; set inside a section and overwritten just after it, read the section's
;; at exactly those fuels, three a section, at the low trip, and at none at
;; the high trip or at 256 KiB. So a low row fails by name unless every forced section met
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
;; In the low pass, low-judged's three; in the high, nothing.
(define (requests-judged pass tally)
  (if (eq? pass 'low) (low-judged tally) '()))

;; slice : Engine Positive-Integer -> (U (List 'completed Any) (List 'expired Engine))
;; Each slice's forced sections are judged met or unmet.
(define (slice e fuel)
  (slice-begun!)
  (let ((r (e fuel (lambda (left . vals) (list 'completed (car vals))) (lambda (more) (list 'expired more)))))
    (slice-ended!)
    r))

;; resumed-at : Engine Positive-Integer -> Any
(define (resumed-at e fuel)
  (let loop ((e e) (n 0))
    (let ((r (slice e fuel)))
      (cond ((eq? (car r) 'completed) (cadr r))
            ((>= n 100000) 'never-completed)
            (else (loop (cadr r) (+ n 1)))))))

;; finish : Engine -> Any
(define (finish e) (resumed-at e 1000000))

(test-begin "open-db-config-engines")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-equal "native records sqlite3_load_extension as a boolean; where it is #f the lists leave the opt-in out, and this says so"
  'boolean
  (begin
    (unless (eq? available #t)
      (display "UNAVAILABLE the opt-in in this suite's lists: this libsqlite3 has no sqlite3_load_extension, so an open that opts in is refused, test-open-db-config's rows assert it, and these lists leave it out")
      (newline))
    (if (boolean? available) 'boolean available)))

(test-equal "the forcing VFS, a copy of SQLite's default whose xAccess and xFullPathname call force! first, is registered as SQLite's default"
  'registered
  (forcing-vfs-default))

;; --- the clean answer ---------------------------------------------------------------------

(test-equal "the clean answer, with no engine: open-database with the three ops and the opt-in among the six PRAGMAs and statement-cache, on a file, answers a connection whose every setting reads back as asked, nothing tracked; call-with-database the same, inside its procedure; nothing left counted"
  (list (list 0 as-asked) (list 0 as-asked) zero-counts)
  (in-dir (lambda (dir)
            (let* ((path (string-append dir "/c.db"))
                   (db (attempt (lambda () (open-database path settings))))
                   (a (if (a-database? db)
                          (let* ((tracked (length (tracked-statements db)))
                                 (read (readings db)))
                            (close-answer db)
                            (list tracked read))
                          db))
                   (b (attempt (lambda ()
                                 (call-with-database path settings
                                   (lambda (db)
                                     (let* ((tracked (length (tracked-statements db)))
                                            (read (readings db)))
                                       (list tracked read))))))))
              (list a b (native-counts))))))

;; --- every fuel ---------------------------------------------------------------------------------

;; sweep : (Positive-Integer -> (List Boolean Boolean (Listof Any))) -> (List Any (Listof Any) Natural)
(define (sweep check)
  (let loop ((fuel 1) (deviations '()) (held 0))
    (let* ((r (check fuel))
           (deviations (if (null? (caddr r)) deviations (cons (cons fuel (caddr r)) deviations)))
           (held (if (cadr r) (+ held 1) held)))
      (cond ((not (car r)) (list fuel (reverse deviations) held))
            ((>= fuel 20000) (list 'no-completion-by-20000 (reverse deviations) held))
            (else (loop (+ fuel 1) deviations held))))))

;; at-fuel : String Positive-Integer -> (List Boolean Boolean (Listof Any))
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

(test-equal "open-database with the three ops and the opt-in among the six PRAGMAs and statement-cache on a file, as an engine, at every fuel from 1 until it completes without expiring: each fuel's open, resumed at its fuel until it completes, answers a connection whose every setting reads back as asked, each op by the suite's own -1 read, the record holding the opt-in; a PRAGMA's statement is held at as many expiries as the PRAGMAs prepare statements, at least; nothing is left counted"
  (list '() 'held-at-a-fuel-a-statement zero-counts)
  (let ((r (in-dir (lambda (dir)
                     (let ((path (string-append dir "/e.db")))
                       (sweep (lambda (fuel) (at-fuel path fuel))))))))
    (if (and (pair? r) (eq? (car r) 'raised))
        r
        (begin
          (display "  open-database with the ops, resumed at its fuel: completed without expiring at fuel ")
          (write (car r))
          (display "; a statement held at the expiry at ")
          (write (caddr r))
          (display " fuels")
          (newline)
          (list (if (integer? (car r)) (summarized (cadr r)) (list (car r) (summarized (cadr r))))
                (if (and (integer? (car r)) (>= (caddr r) (* 2 (length pragma-names))))
                    'held-at-a-fuel-a-statement
                    (list 'held-at (caddr r) 'of (car r)))
                (native-counts))))))

;; --- resumed twice ------------------------------------------------------------------------------

;; twice : Pass String Positive-Integer -> (List Boolean Symbol (Listof Any) Boolean Boolean)
;; open-database on PATH with settings, as an engine, one slice of FUEL, in
;; PASS.
;; Completed, it is closed: (#f none () #f CLEAN). Expired, its remainder is resumed
;; to its end, FIRST, as asked; the suite sets every PRAGMA and op otherwise
;; on it; and the same remainder is resumed again, SECOND: refused,
;; &sqlite-closed, nothing touched; same, FIRST again, past the call's last
;; section; new, a whole new call's connection, as asked. FIRST must still
;; read as the suite set it: no set ran again on it. Then whether a
;; connection was counted at the expiry, and whether no collect request fell
;; in the first slice.
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
;; twice at every fuel from 1 until the open completes without expiring, in
;; PASS, each trial begun by begun!: that fuel; each fuel's deviations; how many
;; fuels each kind of second resume came at; the first fuel at which a
;; remainder taken before the open's section, no connection counted at its
;; expiry, was refused, the sweep's own bound: a new one past it deviates,
;; unless a collect request fell in its first slice; and how many of those.
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
  "open-database's remainder resumed twice, at every fuel from 1 until it completes without expiring: resumed to its end it answers a connection as asked; the suite sets every PRAGMA and op otherwise there; resumed again, it raises &sqlite-closed, refused at a section, at half the fuels at least and at some before the open, or, past its last section, answers that connection again; a whole new call, its own connection as asked, only below every refusal before the open; the first connection keeps what the suite set, so no PRAGMA and no op is set on it again, and nothing is left counted")

;; twice-reported : String Pass -> Any
;; twice-sweep in PASS, printed, naming WHAT, and judged: no deviation;
;; refusals at half the fuels, one before the open; in the low pass,
;; low-judged's three; and the counts.
(define (twice-reported what pass)
  (let-values (((r met) (counted-pass (lambda () (in-dir (lambda (dir) (twice-sweep pass (string-append dir "/t.db"))))))))
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
          (tally-shown met)
          (newline)
          (append
           (list (summarized (cadr r))
                 (let ((refused (kind-count kinds 'refused)))
                   (if (and refused-at (integer? (car r)) (>= (* 2 refused) (car r)))
                       'refused-before-the-open-and-at-half-the-fuels
                       (list 'refused refused 'of (car r) 'before-the-open-first-at refused-at))))
           (requests-judged pass met)
           (list (native-counts)))))))

(test-equal twice-name
  (list '() 'refused-before-the-open-and-at-half-the-fuels zero-counts)
  (twice-reported "open-database with the ops resumed twice" 'high))

(test-equal (string-append "the same, its trials under a collect trip of 256 bytes, so a request falls due in every run and one due inside a section costs ticks at its exit, the forcing VFS allocating 32 KiB inside the open's section and each setting's that begins a read: the same verdicts, and collect requests met in the trials, each forced section's request met before the next, and some first slice expired at a forced section's exit. " twice-name)
  (append (list '() 'refused-before-the-open-and-at-half-the-fuels) low-checks (list zero-counts))
  (twice-reported "open-database with the ops resumed twice, low trip" 'low))

;; --- call-with-database, re-entered through a timer's continuation ------------------------------

;; reentered-at : Pass String Positive-Integer -> (U 'no-capture (List Natural Any Natural))
;; In PASS, call-with-database on PATH with settings, a timer's handler taking a
;; continuation at the call's tick I. The procedure, called first, sets
;; everything otherwise and re-enters it, once; called again, it answers
;; (nested-call READINGS). no-capture when tick I fell after the procedure
;; started; else the connections counted at the capture, what the re-entry
;; answered, and how many more calls of the procedure it made.
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

;; reentry-kind : (U 'no-capture (List Natural Any Natural)) -> Symbol
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

;; reentry-sweep : Pass String -> (List Natural (Listof Any) (Listof (Pairof Symbol Natural)) (U Natural #f) Natural)
;; reentered-at at each tick from 1 until one falls after the procedure
;; starts, in PASS, each trial begun by begun!; a whole new call past the
;; first refusal before the open deviates, unless a collect request fell in
;; the call before the capture: how many of those, last.
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

(define reentry-name
  "call-with-database with the ops re-entered through a continuation a timer's handler took at each tick from 1 until its procedure starts, the procedure re-entering it once it has set every PRAGMA and op otherwise: taken before the sets were done, it raises &sqlite-closed, refused at a section, the procedure not called again; taken past their last section, it calls the procedure again, which finds what it set; refused at half the ticks at least and at some before the open; a whole new call only below every refusal before the open; none sets anything again on the first connection, and nothing is left counted")

;; reentry-reported : String Pass -> Any
;; reentry-sweep in PASS, printed, naming WHAT, and judged: no deviation;
;; refusals at half the ticks, one before the open; in the low pass,
;; low-judged's three; and the counts.
(define (reentry-reported what pass)
  (let-values (((r met) (counted-pass (lambda () (in-dir (lambda (dir) (reentry-sweep pass (string-append dir "/r.db"))))))))
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
          (tally-shown met)
          (newline)
          (append
           (list (summarized (cadr r))
                 (let ((refused (kind-count kinds 'refused)))
                   (if (and refused-at (>= (* 2 refused) (car r)))
                       'refused-before-the-open-and-at-half-the-ticks
                       (list 'refused refused 'of (car r) 'before-the-open-first-at refused-at))))
           (requests-judged pass met)
           (list (native-counts)))))))

(test-equal reentry-name
  (list '() 'refused-before-the-open-and-at-half-the-ticks zero-counts)
  (reentry-reported "call-with-database with the ops re-entered" 'high))

(test-equal (string-append "the same, its trials under a collect trip of 256 bytes, the forcing VFS allocating 32 KiB inside the open's section and each setting's that begins a read: the same verdicts, and collect requests met in the trials, each forced section's request met before the next, and some capture made at a forced section's exit. " reentry-name)
  (append (list '() 'refused-before-the-open-and-at-half-the-ticks) low-checks (list zero-counts))
  (reentry-reported "call-with-database with the ops re-entered, low trip" 'low))

;; --- call-with-database under an engine ---------------------------------------------------------

;; cwd-at-fuel : String Positive-Integer -> (List Boolean Symbol (Listof Any))
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
                     ((and (list? answer) (= (length answer) 2) (eqv? (car answer) 0)
                           (pair? (cadr answer)) (eq? (car (cadr answer)) 'raised))
                      'closed-in-proc)
                     (else 'other))))
    (list expired kind
          (append (if (eq? kind 'other) (list (list 'answer answer)) '())
                  (if (eq? kind 'closed-in-proc)
                      (if (member (cadr answer) '((raised (closed query-row))
                                                  (raised (closed database-cache-capacity))
                                                  (raised (closed test-open-db-config-engines))))
                          '()
                          (list (list 'closed-in-proc answer)))
                      '())
                  (if (<= dropped-calls 1) '() (list (list 'dropped-calls dropped-calls)))
                  (if (<= calls 1) '() (list (list 'calls calls)))
                  (if (equal? after-drop zero-counts) '() (list (list 'after-drop after-drop)))
                  (if (equal? (native-counts) zero-counts) '() (list (list 'counts (native-counts))))))))

;; cwd-sweep : String -> (List Any (Listof Any) (Listof (Pairof Symbol Natural)))
(define (cwd-sweep path)
  (let loop ((fuel 1) (deviations '()) (kinds '()))
    (let* ((r (cwd-at-fuel path fuel))
           (deviations (if (null? (caddr r)) deviations (cons (cons fuel (caddr r)) deviations)))
           (kinds (counted-up (cadr r) kinds)))
      (cond ((not (car r)) (list fuel (reverse deviations) kinds))
            ((>= fuel 20000) (list 'no-completion-by-20000 (reverse deviations) kinds))
            (else (loop (+ fuel 1) deviations kinds))))))

(test-equal "call-with-database with the ops on a file, as an engine, at every fuel from 1 until it completes without expiring: a remainder dropped leaves nothing counted, since the expiry closed the connection; a remainder resumed to its end answers the procedure's readings, as asked with nothing tracked, or &sqlite-closed, from call-with-database or from the procedure's own reads; the procedure is called once a call at most; some fuels give each kind, and nothing is left counted"
  (list '() 'some-as-asked 'some-closed zero-counts)
  (let ((r (in-dir (lambda (dir) (cwd-sweep (string-append dir "/w.db"))))))
    (if (and (pair? r) (eq? (car r) 'raised))
        r
        (let ((kinds (caddr r)))
          (display "  call-with-database with the ops, resumed: completed without expiring at fuel ")
          (write (car r))
          (display "; kinds ")
          (write kinds)
          (newline)
          (list (summarized (cadr r))
                (if (> (kind-count kinds 'as-asked) 0) 'some-as-asked 'none-as-asked)
                (if (> (+ (kind-count kinds 'closed) (kind-count kinds 'closed-in-proc)) 0)
                    'some-closed 'none-closed)
                (native-counts))))))

;; --- one remainder's runs interleaved ---------------------------------------------------------

;; Trial = (List Symbol Natural (Listof Any) (U 'both 'straddle #f) Boolean Boolean (U 'last #f) Boolean)
;; Its kind, completed when R's first slice completed the call, last when
;; R's resume completed within G, else interleaved; how many whole calls its
;; runs made, told by their effects, distinct databases or the stand-in's
;; first set; what deviated; for an interleaved trial, where its remainders
;; lay against the call's first section, each read at its own expiry: both
;; past it; straddle, R before it and R1, taken later on R's own resume,
;; past it; or #f, both before; whether a run was refused; whether one was,
;; R taken before the call's first section, the sweep's own bound; and, for
;; an interleaved trial, last when R was taken before the call's last set
;; and R1 past it, read at each one's expiry, else #f; and whether no
;; collect request fell in R's first slice, so the sweep's bound reads it.

;; Sweep = (List Any Natural (Listof Any) Natural (Listof Natural) (U Natural #f) Natural Natural Natural Natural Natural)
;; The fuel at which the call completes without expiring, or
;; no-completion-by-20000; how many trials ran; each trial's deviations,
;; with its fuels; the trials whose runs answered the call; the fuels of the
;; trials in which two runs made whole calls; the first fuel at which a
;; trial was refused, R taken before the call's first section, #f for none;
;; how many fuels saw a refusal; the trials with both remainders past the
;; first section; those with R before it and R1 past it, which race R's
;; second run against R1 at that section itself; those with R before the
;; last set and R1 past it; and the whole new calls left out of the bound,
;; a collect request in their first slice.

;; interleave-sweep : Pass (Pass Natural Natural -> Trial) -> Sweep
;; At every fuel from 1 until the call completes without expiring, TRIAL in
;; PASS at every G from 1 until R's resume completes within it.
(define (interleave-sweep pass trial)
  (let floop ((fuel 1) (trials 0) (deviations '()) (answered 0) (news '()) (refused-at #f)
              (refused-fuels 0) (past 0) (straddle 0) (last 0) (moved 0))
    (let gloop ((g 1) (trials trials) (deviations deviations) (answered answered) (news news)
                (refused-at refused-at) (seen #f) (past past) (straddle straddle) (last last)
                (moved moved))
      (let* ((t (trial pass fuel g))
             (kind (car t))
             (deviations (if (null? (caddr t)) deviations (cons (list fuel g (caddr t)) deviations)))
             (answered (if (> (cadr t) 0) (+ answered 1) answered))
             (new (> (cadr t) 1))
             (news (if (and new (list-ref t 7)) (cons fuel news) news))
             (moved (if (and new (not (list-ref t 7))) (+ moved 1) moved))
             (past (if (eq? (cadddr t) 'both) (+ past 1) past))
             (straddle (if (eq? (cadddr t) 'straddle) (+ straddle 1) straddle))
             (seen (or seen (list-ref t 4)))
             (refused-at (or refused-at (and (list-ref t 5) fuel)))
             (last (if (eq? (list-ref t 6) 'last) (+ last 1) last))
             (trials (+ trials 1)))
        (cond ((eq? kind 'completed)
               (list fuel trials (reverse deviations) answered (reverse news) refused-at refused-fuels
                     past straddle last moved))
              ((>= fuel 20000)
               (list 'no-completion-by-20000 trials (reverse deviations) answered (reverse news)
                     refused-at refused-fuels past straddle last moved))
              ((eq? kind 'last)
               (floop (+ fuel 1) trials deviations answered news refused-at
                      (if seen (+ refused-fuels 1) refused-fuels) past straddle last moved))
              (else (gloop (+ g 1) trials deviations answered news refused-at seen past straddle
                           last moved)))))))

;; interleave-reported : String Pass Boolean (Pass Natural Natural -> Trial) -> (Listof Any)
;; interleave-sweep of TRIAL in PASS, printed, naming WHAT, and judged: its
;; deviations, summarized; its trials answering the call three a fuel on
;; average, both remainders past the call's first section in one a fuel,
;; and R before it with R1 past it in some: a sweep that reused one R
;; across every G answers at most one a fuel; refusals at half the fuels at
;; least; every whole new call below the first refusal the sweep saw
;; itself, R taken before the first section; in the low pass, where LAST?,
;; R before the last set and R1 past it in some trial, and low-judged's
;; three; and the counts.
(define (interleave-reported what pass last? trial)
  (let-values (((run met) (counted-pass (lambda () (interleave-sweep pass trial)))))
    (let ((fuel (car run)) (news (list-ref run 4)) (refused-at (list-ref run 5))
          (refused-fuels (list-ref run 6)))
      (display "  ")
      (display what)
      (display ": completed without expiring at fuel ")
      (write fuel)
      (display "; trials ")
      (write (cadr run))
      (display "; trials answering ")
      (write (list-ref run 3))
      (display "; fuels seeing a refusal ")
      (write refused-fuels)
      (display "; both remainders past the first section in ")
      (write (list-ref run 7))
      (display "; R before it and R1 past it in ")
      (write (list-ref run 8))
      (display "; R before the last set and R1 past it in ")
      (write (list-ref run 9))
      (display "; whole new calls ")
      (write (length news))
      (display ", the last at fuel ")
      (write (if (null? news) 0 (apply max news)))
      (display ", below the first refusal before the first section, at fuel ")
      (write refused-at)
      (display "; whole new calls left out, a collect request in the first slice, ")
      (write (list-ref run 10))
      (tally-shown met)
      (newline)
      (append
       (list (if (integer? fuel) (summarized (caddr run)) (list fuel (summarized (caddr run))))
             (if (and (integer? fuel) (>= (list-ref run 3) (* 3 fuel))
                      (>= (list-ref run 7) fuel) (> (list-ref run 8) 0))
                 'answered-three-a-fuel-and-past-the-first-section-one-a-fuel
                 (list 'answered (list-ref run 3) 'past (list-ref run 7) 'straddling (list-ref run 8)
                       'over fuel))
             (if (and (integer? fuel) (>= (* 2 refused-fuels) fuel))
                 'refused-at-half-the-fuels
                 (list 'refused-fuels refused-fuels 'over fuel))
             (if (and refused-at (for-all (lambda (f) (< f refused-at)) news))
                 'whole-new-calls-below-a-refusal
                 (list 'whole-new-calls-not-below-a-refusal (past-the-bound news refused-at) refused-at)))
       (if (and (eq? pass 'low) last?)
           (list (if (> (list-ref run 9) 0)
                     'straddled-the-last-set
                     (list 'none-straddling-the-last-set (list-ref run 9))))
           '())
       (requests-judged pass met)
       (list (native-counts))))))

;; past-the-bound : (Listof Natural) (U Natural #f) -> (Listof Natural)
;; The distinct fuels among NEWS at or past REFUSED-AT, every one when it
;; is #f, in order: a failing row's evidence.
(define (past-the-bound news refused-at)
  (let loop ((rest news) (found '()))
    (cond ((null? rest) (reverse found))
          ((and (or (not refused-at) (>= (car rest) refused-at)) (not (memv (car rest) found)))
           (loop (cdr rest) (cons (car rest) found)))
          (else (loop (cdr rest) found)))))

;; --- interleaved: open-database -----------------------------------------------------------

;; mem-settings : Settings
;; A PRAGMA, busy-timeout listed last so it runs first, and the three ops,
;; with the opt-in where the library has it. They are opened on a file, not on :memory:, which
;; no VFS method sees: on a file, the open's section calls xFullPathname, so
;; the forcing VFS forces it.
(define mem-settings
  (append '((defensive . #t) (foreign-keys . #t))
          (if (eq? available #t) '((enable-load-extension . #t)) '())
          '((dqs-dml . #f) (dqs-ddl . #f) (busy-timeout . 1234))))

;; mem-readings : Database -> Any
(define (mem-readings db)
  (attempt (lambda ()
             (let* ((b (pragma db "busy_timeout"))
                    (f (pragma db "foreign_keys"))
                    (ops (op-reads db))
                    (opt-in (yes-no (database-extension-loading? db))))
               (list b f ops opt-in)))))

(define mem-as-asked
  (list 1234 1 (append (if (eq? available #t) '((0 1)) '()) '((0 1) (0 0) (0 0)))
        (if (eq? available #t) 'yes 'no)))

;; open-path : (U String #f)
;; The file open-trial opens, in the row's own directory: no setting of
;; mem-settings is kept in the file, so every trial opens it as the first.
(define open-path #f)

(define (mem-thunk) (attempt (lambda () (open-database open-path mem-settings))))

;; ran-counts : (-> Any) -> (List Any Symbol)
;; GO's answer, and whether the counts were the same before and after it.
(define (ran-counts go)
  (let* ((c0 (native-counts))
         (answer (go))
         (c1 (native-counts)))
    (list answer (if (equal? c0 c1) 'counts-kept (list 'counts c0 c1)))))

;; open-judged : Counts (Listof (List Any Symbol)) Any Boolean Any -> Trial-Tail
;; RUNS' answers judged, each by itself: each a database, or &sqlite-closed
;; refused with the counts kept; each database answered checked, nothing
;; tracked, read as asked, then closed; then the counts START's, so no run
;; left a connection open that it did not answer. Two distinct databases
;; are two whole calls, which the sweep bounds. Answers the trial's tail:
;; how many distinct databases, the deviations, PAST, whether a run was
;; refused, whether one was with R before the open, R-OPEN #f, and LAST.
(define (open-judged start runs past r-open last)
  (let* ((deviations '())
         (answered (let loop ((rest runs) (found '()))
                     (cond ((null? rest) (reverse found))
                           ((and (a-database? (car (car rest))) (not (memq (car (car rest)) found)))
                            (loop (cdr rest) (cons (car (car rest)) found)))
                           (else (loop (cdr rest) found)))))
         (refused (exists (lambda (run) (equal? (car run) '(raised (closed open-database)))) runs)))
    (define (deviate! d) (set! deviations (cons d deviations)))
    (let loop ((rest runs))
      (unless (null? rest)
        (let ((a (car (car rest))))
          (cond ((a-database? a) #f)
                ((equal? a '(raised (closed open-database)))
                 (unless (eq? (cadr (car rest)) 'counts-kept)
                   (deviate! (list 'refused-run-touched (cadr (car rest))))))
                (else (deviate! (list 'answer a)))))
        (loop (cdr rest))))
    (when (> (length answered) 2) (deviate! (list 'calls (length answered))))
    (let loop ((rest answered))
      (unless (null? rest)
        (let* ((db (car rest))
               (tracked (attempt (lambda () (length (tracked-statements db)))))
               (read (mem-readings db)))
          (unless (eqv? tracked 0) (deviate! (list 'tracked tracked)))
          (unless (equal? read mem-as-asked) (deviate! (list 'readings read)))
          (close-answer db))
        (loop (cdr rest))))
    (unless (equal? (native-counts) start)
      (deviate! (list 'left-open start (native-counts))))
    (list (length answered) (reverse deviations) past (and refused #t) (and refused (not r-open) #t)
          last)))

;; open-trial : Pass Natural Natural -> Trial
;; One trial of open-database with mem-settings at FUEL, R resumed at G, in
;; PASS. Each remainder's place is read at its own expiry: past the open,
;; the trial's connection counted. Its last-set place is #f: nothing outside
;; the call reads it.
(define (open-trial pass fuel g)
  (begun! pass)
  (let* ((start (native-counts))
         (open? (lambda () (> (connection-count) (cdr (assq 'connection start)))))
         (met requests)
         (r (first-slice (make-engine mem-thunk) fuel))
         (clean (= requests met))
         (t (if (eq? (car r) 'completed)
                (cons 'completed (open-judged start (list (list (cadr r) 'counts-kept)) #f #f #f))
                (let* ((R (cadr r))
                       (r-open (open?))
                       (r1 (slice R g)))
                  (if (eq? (car r1) 'completed)
                      (let ((second (ran-counts (lambda () (finish R)))))
                        (cons 'last (open-judged start (list (list (cadr r1) 'counts-kept) second) #f
                                                 r-open #f)))
                      (let* ((R1 (cadr r1))
                             (r1-open (open?))
                             (second (ran-counts (lambda () (finish R))))
                             (third (ran-counts (lambda () (finish R1)))))
                        (cons 'interleaved (open-judged start (list second third)
                                                        (cond ((and r-open r1-open) 'both)
                                                              (r1-open 'straddle)
                                                              (else #f))
                                                        r-open
                                                        #f))))))))
    (ended!)
    (append t (list clean))))

;; open-reported : String Pass -> (Listof Any)
;; interleave-reported of open-trial in PASS, on a file of its own
;; directory.
(define (open-reported what pass)
  (in-dir (lambda (dir)
            (set! open-path (string-append dir "/i.db"))
            (interleave-reported what pass #f open-trial))))

(define open-name
  "open-database's remainder R with the ops among two PRAGMAs on a file, taken at every fuel from 1 until the call completes without expiring, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1: each run answers the connection or is refused with &sqlite-closed, the counts kept; no connection is left open that a run did not answer; the one answered tracks nothing and reads every setting as asked; trials answer three a fuel on average, have both remainders past the open in one a fuel, and R before it with R1 past it in some; refusals come at half the fuels at least; and two connections, a whole new call's, only below the first fuel at which a trial was refused, R taken before the open")

(test-equal open-name
  (list '() 'answered-three-a-fuel-and-past-the-first-section-one-a-fuel 'refused-at-half-the-fuels
        'whole-new-calls-below-a-refusal zero-counts)
  (open-reported "open-database with the ops, interleaved" 'high))

(test-equal (string-append "the same, its trials under a collect trip of 256 bytes, so a request falls due in every run and one due inside a section costs ticks at its exit, the forcing VFS allocating 32 KiB inside the open's section: the same verdicts, each trial judged by itself and bounded by the sweep's own refusals, and collect requests met in the trials, each forced section's request met before the next, and some first slice expired at a forced section's exit. " open-name)
  (append (list '() 'answered-three-a-fuel-and-past-the-first-section-one-a-fuel 'refused-at-half-the-fuels
                'whole-new-calls-below-a-refusal)
          low-checks (list zero-counts))
  (open-reported "open-database with the ops, interleaved, low trip" 'low))

;; --- once a call: applied-settings/with, through a counting stand-in ----------------------------

;; once-steps : (Listof Any)
;; The four's steps, the opt-in's where the library has sqlite3_load_extension,
;; and a PRAGMA among them, written out, the ops constants.sls's.
(define once-steps
  (append (if (eq? available #t) (list (list 'enable-load-extension sqlite-dbconfig-enable-load-extension 1 #t)) '())
          (list (list 'defensive sqlite-dbconfig-defensive 1 #t)
                '(foreign-keys "PRAGMA foreign_keys = 1" "PRAGMA foreign_keys" #t)
                (list 'dqs-dml sqlite-dbconfig-dqs-dml 0 #f)
                (list 'dqs-ddl sqlite-dbconfig-dqs-ddl 0 #f))))

;; once-calls : (Listof (List Natural Integer))
;; The calls one whole call makes, each op and the value written, in order.
(define once-calls
  (let loop ((rest once-steps) (found '()))
    (cond ((null? rest) (reverse found))
          ((integer? (cadr (car rest))) (loop (cdr rest) (cons (list (cadr (car rest)) (caddr (car rest))) found)))
          (else (loop (cdr rest) found)))))

(define once-as-asked
  (list (append (if (eq? available #t) '((0 1)) '()) '((0 1) (0 0) (0 0))) 1))

;; counting : Pass -> (Values Procedure (-> (Listof (List Natural Integer))))
;; A stand-in for native's binding that notes each call's op and value,
;; then passes it to native's binding; and a reader of its notes, oldest
;; first. It runs inside the set's critical section, where no tick is spent,
;; so no fuel splits its note from its call. In the low pass it allocates
;; 32 KiB there too, past which a collect request always fell inside a
;; section under the low trip: so one falls due inside every set's section,
;; and is handled at its exit, where it costs the engine ticks. Without it,
;; no trial of 3706 had R before the last set and R1 past it. Its
;; allocation is force!'s, counted with the forcing VFS's.

(define (counting pass)
  (let ((calls '()))
    (values
     (lambda (h op value cell)
       (force!)
       (set! calls (cons (list op value) calls))
       (sqlite3-db-config h op value cell))
     (lambda () (reverse calls)))))

;; once-thunk : Database Procedure -> (-> Any)
(define (once-thunk db db-config)
  (lambda () (attempt (lambda () (applied-settings/with 'the-suite db once-steps db-config) 'applied))))

;; noted-run : (-> Any) (-> (Listof Any)) -> (List Any Natural Symbol)
;; GO's answer, how many calls the stand-in noted while it ran, and whether
;; the counts were the same before and after.
(define (noted-run go calls)
  (let* ((n0 (length (calls)))
         (c0 (native-counts))
         (answer (go))
         (n1 (length (calls)))
         (c1 (native-counts)))
    (list answer (- n1 n0) (if (equal? c0 c1) 'counts-kept (list 'counts c0 c1)))))

;; two-whole? : (Listof (List Natural Integer)) -> Boolean
;; Whether NOTED is two whole calls' calls, each once-calls in order, their
;; runs interleaved: once-calls' ops are distinct, so it is exactly when
;; each call is noted twice, the first of each pair in once-calls' order,
;; and the second too.
(define (two-whole? noted)
  (let loop ((rest noted) (firsts '()) (seconds '()))
    (if (null? rest)
        (and (equal? (reverse firsts) once-calls) (equal? (reverse seconds) once-calls))
        (let ((c (car rest)))
          (cond ((not (member c firsts)) (loop (cdr rest) (cons c firsts) seconds))
                ((not (member c seconds)) (loop (cdr rest) firsts (cons c seconds)))
                (else #f))))))

;; once-judged : Database (-> (Listof Any)) (Listof (List Any Natural Symbol)) Any Boolean Any -> Trial-Tail
;; RUNS, judged once the trial is done, by the trial itself: each answered
;; applied, or &sqlite-closed refused, noting no call and keeping the
;; counts; the stand-in's calls, the whole call's exactly, once each and in
;; order, or twice over, whole each time, two whole calls, which the sweep
;; bounds; and DB, still open, reads every op and the PRAGMA as asked. Then
;; DB is closed, and nothing is counted. The whole calls are counted from
;; the stand-in's notes, each the first set's call: a whole call makes every
;; set once, and so its first, a refused run makes none, and a run past the
;; last set answers applied again making none, as open-database's past its
;; last section answers the same connection. Counting the runs that answer
;; applied counted such a run as a second call. Answers the trial's tail:
;; the whole calls, the deviations, PAST, whether a run was refused, whether
;; one was with R before the first set, R-PAST #f, and LAST.
(define (once-judged db calls runs past r-past last)
  (let* ((deviations '())
         (noted (calls))
         (whole (let loop ((rest noted) (n 0))
                  (cond ((null? rest) n)
                        ((equal? (car rest) (car once-calls)) (loop (cdr rest) (+ n 1)))
                        (else (loop (cdr rest) n)))))
         (refused (exists (lambda (run) (equal? (car run) '(raised (closed the-suite)))) runs)))
    (define (deviate! d) (set! deviations (cons d deviations)))
    (let loop ((rest runs))
      (unless (null? rest)
        (let ((a (car (car rest))))
          (cond ((equal? a 'applied) #f)
                ((equal? a '(raised (closed the-suite)))
                 (unless (and (eqv? (cadr (car rest)) 0) (eq? (caddr (car rest)) 'counts-kept))
                   (deviate! (list 'refused-run-touched (cdr (car rest))))))
                (else (deviate! (list 'answer a)))))
        (loop (cdr rest))))
    (unless (or (equal? noted once-calls) (two-whole? noted))
      (deviate! (list 'calls noted)))
    (let ((read (attempt (lambda () (list (op-reads db) (pragma db "foreign_keys"))))))
      (unless (equal? read once-as-asked) (deviate! (list 'readings read))))
    (unless (eqv? (connection-count) 1) (deviate! (list 'connections (connection-count))))
    (close-answer db)
    (unless (equal? (native-counts) zero-counts) (deviate! (list 'counts (native-counts))))
    (list whole (reverse deviations) past (and refused #t) (and refused (not r-past) #t) last)))

;; once-trial : Pass Natural Natural -> Trial
;; One trial at FUEL, R resumed at G, in PASS: a fresh connection, opened
;; with no engine, and a fresh stand-in and engine. Each remainder's place
;; is read at its own expiry from the stand-in's notes: past the first set,
;; a call noted; past the last, every one.
(define (once-trial pass fuel g)
  (begun! pass)
  (let ((db (open-database ":memory:")))
    (let-values (((db-config calls) (counting pass)))
      (let* ((met requests)
             (r (first-slice (make-engine (once-thunk db db-config)) fuel))
             (clean (= requests met))
             (t (if (eq? (car r) 'completed)
                    (cons 'completed (once-judged db calls (list (list (cadr r) 0 'counts-kept)) #f #f #f))
                    (let* ((R (cadr r))
                           (r-past (> (length (calls)) 0))
                           (r-last (= (length (calls)) (length once-calls)))
                           (r1 (slice R g)))
                      (if (eq? (car r1) 'completed)
                          (let ((second (noted-run (lambda () (finish R)) calls)))
                            (cons 'last (once-judged db calls (list (list (cadr r1) 0 'counts-kept) second)
                                                     #f r-past #f)))
                          (let* ((R1 (cadr r1))
                                 (r1-past (> (length (calls)) 0))
                                 (r1-last (= (length (calls)) (length once-calls)))
                                 (second (noted-run (lambda () (finish R)) calls))
                                 (third (noted-run (lambda () (finish R1)) calls)))
                            (cons 'interleaved (once-judged db calls (list second third)
                                                            (cond ((and r-past r1-past) 'both)
                                                                  (r1-past 'straddle)
                                                                  (else #f))
                                                            r-past
                                                            (and (not r-last) r1-last 'last)))))))))
        (ended!)
        (append t (list clean))))))

(define once-name
  "applied-settings/with on a connection of the suite's, the four and a PRAGMA, through a stand-in that notes each call and passes it to native's binding, its remainder R taken at every fuel from 1 until the call completes without expiring, R1 from R's resume at every later fuel, then R resumed again to its end, then R1, each trial on a fresh connection, stand-in and engine: each op's set is made once a call, in the list's order, by whichever run reaches it; a refused run notes no call and keeps the counts; the connection stays open and reads every op and the PRAGMA as asked; trials answer three a fuel on average, have both remainders past the first set in one a fuel, and R before it with R1 past it in some; refusals come at half the fuels at least; and a whole new call's sets only below the first fuel at which a trial was refused, R taken before the first set")

(test-equal once-name
  (list '() 'answered-three-a-fuel-and-past-the-first-section-one-a-fuel 'refused-at-half-the-fuels
        'whole-new-calls-below-a-refusal zero-counts)
  (interleave-reported "applied-settings/with, counted, interleaved" 'high #t once-trial))

(test-equal (string-append "the same, its trials under a collect trip of 256 bytes, the stand-in allocating 32 KiB inside each set's section, so a request falls due there and is handled at the set's exit: the same verdicts, each trial judged by itself and bounded by the sweep's own refusals; some trial has R before the last set and R1 past it; and collect requests met in the trials, each forced section's request met before the next, and some first slice expired at a forced section's exit. " once-name)
  (append (list '() 'answered-three-a-fuel-and-past-the-first-section-one-a-fuel 'refused-at-half-the-fuels
                'whole-new-calls-below-a-refusal 'straddled-the-last-set)
          low-checks (list zero-counts))
  (interleave-reported "applied-settings/with, counted, interleaved, low trip" 'low #t once-trial))

;; --- a failing set, resumed twice ---------------------------------------------------------------

;; failing-steps : (Listof Any)
;; Two ops, the second failed by the stand-in.
(define failing-steps
  (list (list 'defensive sqlite-dbconfig-defensive 1 #t)
        (list 'dqs-dml sqlite-dbconfig-dqs-dml 0 #f)))

;; failing-stand-in : -> (Values Procedure (-> Natural))
;; A stand-in that answers 0 with the value for defensive's set, 1 with the
;; cell left for any other, and counts its calls.
(define (failing-stand-in)
  (let ((n 0))
    (values
     (lambda (h op value cell)
       (set! n (+ n 1))
       (if (eqv? op sqlite-dbconfig-defensive)
           (begin (sqlite3-db-config h op value cell) 0)
           1))
     (lambda () n))))

(define failed-answer '(raised (sqlite-error the-suite error error)))

;; failing-twice : Natural -> (U 'completed (List Symbol (Listof Any) Boolean))
;; applied-settings/with with failing-steps at FUEL on a fresh connection;
;; expired, its remainder resumed to its end twice. The first raises the
;; set's error, the connection closed; the second is refused, &sqlite-closed,
;; or raises the error again, past the close; neither calls the stand-in
;; past its two calls, nor changes a count after the first. Answers the
;; second's kind, again or refused, what deviated, and whether the stand-in
;; had been called at the expiry.
(define (failing-twice fuel)
  (let ((db (open-database ":memory:")))
    (let-values (((db-config calls) (failing-stand-in)))
      (let ((r (slice (make-engine (lambda () (attempt (lambda () (applied-settings/with 'the-suite db failing-steps db-config) 'applied))))
                      fuel)))
        (if (eq? (car r) 'completed)
            (begin (close-answer db) 'completed)
            (let* ((at-expiry (calls))
                   (first (finish (cadr r)))
                   (c-first (native-counts))
                   (n-first (calls))
                   (second (finish (cadr r)))
                   (kind (cond ((equal? second '(raised (closed the-suite))) 'refused)
                               ((equal? second failed-answer) 'again)
                               (else 'other)))
                   (deviations (append (if (equal? first failed-answer) '() (list (list 'first first)))
                                       (if (eqv? n-first 2) '() (list (list 'calls-first n-first)))
                                       (if (eq? kind 'other) (list (list 'second second)) '())
                                       (if (eqv? (calls) 2) '() (list (list 'calls-second (calls))))
                                       (if (equal? c-first zero-counts) '() (list (list 'counts-first c-first)))
                                       (if (equal? (native-counts) zero-counts) '()
                                           (list (list 'counts (native-counts)))))))
              (close-answer db)
              (list kind deviations (> at-expiry 0))))))))

;; failing-sweep : -> (List Any (Listof Any) (Listof (Pairof Symbol Natural)))
(define (failing-sweep)
  (let loop ((fuel 1) (deviations '()) (kinds '()))
    (quieted!)
    (let ((t (failing-twice fuel)))
      (cond ((eq? t 'completed) (list fuel (reverse deviations) kinds))
            ((>= fuel 20000) (list 'no-completion-by-20000 (reverse deviations) kinds))
            (else
             (loop (+ fuel 1)
                   (if (null? (cadr t)) deviations (cons (cons fuel (cadr t)) deviations))
                   (counted-up (if (and (eq? (car t) 'refused) (caddr t)) 'refused-past-a-set (car t))
                               kinds)))))))

(test-equal "applied-settings/with whose stand-in fails the second set, its remainder resumed to its end twice at every fuel from 1 until it completes without expiring: the first raises the set's &sqlite-error, the connection closed, the stand-in called twice; the second is refused with &sqlite-closed, at a third of the fuels at least and at some after a set was made, or raises the error again, past the close; neither calls the stand-in again, nor changes a count"
  (list '() 'refused-at-a-third-of-the-fuels-and-past-a-set zero-counts)
  (let ((r (failing-sweep)))
    (display "  applied-settings/with, failing, resumed twice: completed without expiring at fuel ")
    (write (car r))
    (display "; second resumes ")
    (write (caddr r))
    (newline)
    (list (summarized (cadr r))
          (let ((refused (+ (kind-count (caddr r) 'refused) (kind-count (caddr r) 'refused-past-a-set))))
            (if (and (integer? (car r)) (>= (* 3 refused) (car r))
                     (> (kind-count (caddr r) 'refused-past-a-set) 0))
                'refused-at-a-third-of-the-fuels-and-past-a-set
                (list 'refused refused 'past-a-set (kind-count (caddr r) 'refused-past-a-set)
                      'of (car r))))
          (native-counts))))

(test-equal "the forcing VFS is unregistered once every connection is closed, SQLite's own the default again, its memory freed and its callbacks unlocked"
  '(0 sqlite-default)
  (forcing-vfs-removed))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "open-db-config-engines")

(exit (suite-exit-status runner))
