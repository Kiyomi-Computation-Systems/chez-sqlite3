#!r6rs
;;; The suite for one open's runs interleaved (ADR-0018, consequences; the
;;; maintainer's "Guard every call", ADR-0016, amended in M3 slice 3), in
;;; (chez-sqlite3 private open). Chez's engine remainders are multi-shot: R,
;;; one remainder of a call, resumed until it expires again, is R1, and R
;;; can then be resumed again while R1 is pending. Each run of the call goes
;;; on from where its remainder was taken.
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
;;;                at a fuel at which the control makes one (below).
;;;   a failing    open-database, then call-with-database, with busy-timeout
;;;   open twice   and journal-mode wal on :memory:, which mismatches,
;;;                journal_mode reading memory, at every fuel from 1 until
;;;                the call completes without expiring: the remainder
;;;                resumed to its end raises the mismatch, the connection
;;;                closed; resumed again, it is refused with &sqlite-closed,
;;;                always when the connection was open at the expiry, or,
;;;                past the failure's close, raises the mismatch again,
;;;                either way noting nothing and changing no count; only
;;;                where the control makes a whole new call does it open a
;;;                connection, which mismatches the same, alone. Every
;;;                connection's PRAGMAs are a prefix of the plan, none twice,
;;;                and nothing is counted after
;;;   an escape    call-with-database, SIGINT raised inside each of its
;;;                sections in turn, from the callbacks: Chez handles a
;;;                keyboard interrupt that came pending inside a critical
;;;                section as the section ends, before the next expression
;;;                (.plans/research/m3-slice-5/, section-end.sps), and the
;;;                handler leaves the call: the extent closes the connection
;;;                each time, no later section runs, and nothing is counted. An engine and a
;;;                timer spend no ticks inside a section, so only such an
;;;                interrupt reaches the end of the open's section before the
;;;                connection is recorded
;;;
;;; The tell: sqlite3_auto_extension runs an entry point of this suite at
;;; every open, which notes the open and sets an authorizer on the new
;;; connection. SQLite calls the authorizer at every prepare, and a setting
;;; takes effect at its prepare (M3's research, single P3), so each PRAGMA
;;; prepared is noted, its connection, its name and its value, none for a
;;; read. Both callbacks are __collect_safe: SQLite calls them inside
;;; sqlite3_open_v2 and sqlite3_prepare_v3, which are. They answer data and
;;; raise nothing. The entry point is unregistered, and both unlocked, at
;;; the end. A libsqlite3 can refuse the registration: Apple's 3.51.0
;;; answers 21, SQLITE_MISUSE, for an entry point upstream takes. With no
;;; tell, nothing is noted, so each row that reads the notes, or raises
;;; SIGINT from the callbacks, goes through tell-available!, which prints
;;; UNAVAILABLE and skips it: never passed (ADR-0005, amended).
;;;
;;; Which fuels lie before the call's first expression is measured, not
;;; assumed: at each fuel, a control takes R and resumes it to its end
;;; twice, one after the other, and the second makes a whole new call when
;;; it opens a connection of its own. A refused call's completing fuel is no
;;; bound: an open's sections spend no ticks, so the open and its settings
;;; span fewer fuels than the refusal's raise. A collect request costs a run
;;; up to a tick, and two can cost two, so a trial's R could lie before the
;;; control's at the same fuel: each fuel begins with a collection, and
;;; collect-trip-bytes is raised far above what a fuel's runs allocate, so
;;; no request falls in them; a trial may make a whole new call where the
;;; control made one at its fuel or the one before, a tick's room besides.
;;;
;;; An engine spends no ticks inside a critical section, so the fuels measure
;;; the Scheme work between the open's sections (.plans/traps.md). The
;;; loading procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) make-engine foreign-procedure foreign-callable
              foreign-callable-entry-point lock-object unlock-object foreign-ref
              foreign-entry? keyboard-interrupt-handler collect collect-trip-bytes)
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

;; registered : (U 'registered (List 'auto-extension-answered Integer) (List 'raised Any))
;; The entry point registered, the two callbacks locked, for every new
;; connection; or the code sqlite3_auto_extension refused it with, the
;; callbacks unlocked again, since nothing will call them.
(define registered
  (guard (e (#t (list 'raised (describe e))))
    (lock-object authorizer)
    (lock-object entry-point)
    (let ((rc (auto-extension (foreign-callable-entry-point entry-point))))
      (if (eqv? rc 0)
          'registered
          (begin
            (unlock-object entry-point)
            (unlock-object authorizer)
            (list 'auto-extension-answered rc))))))

;; tell-refused : Any -> (U Integer #f)
;; The code of ANSWER, registered's, when it is a refusal, a nonzero
;; integer; else #f.
(define (tell-refused answer)
  (and (pair? answer) (eq? (car answer) 'auto-extension-answered)
       (pair? (cdr answer)) (null? (cddr answer))
       (let ((rc (cadr answer)))
         (and (integer? rc) (exact? rc) (not (eqv? rc 0)) rc))))

;; tell-answered? : Any -> Boolean
;; Whether ANSWER, registered's, is registered, or a refusal with its code:
;; not a raise, nor anything else.
(define (tell-answered? answer)
  (or (eq? answer 'registered) (and (tell-refused answer) #t)))

;; tell-available! : Any String -> Void
;; The gate of a row that depends on the tell, NAME: where ANSWER,
;; registered's, is a refusal, prints that the row is unavailable, and
;; skips it, so it is never passed (ADR-0005, amended). Anything else runs
;; the row: registered, or a raise, which the registration row fails.
(define (tell-available! answer name)
  (let ((rc (tell-refused answer)))
    (when rc
      (display "UNAVAILABLE ")
      (display name)
      (display ": this libsqlite3 refused sqlite3_auto_extension (")
      (display rc)
      (display "), so the tell can't note a prepare")
      (newline)
      (test-skip name))))

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
;; A collection now, at a fuel's start, with collect-trip-bytes raised to
;; 128 MiB, far above what one fuel's runs allocate, so no collect request
;; falls in a control or a trial: a request costs a run up to a tick, and
;; more than one can cost two (.plans/research/m3-slice-5/, gc-ticks.sps),
;; and a trial is judged by the control at its fuel.
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
;; comment in (chez-sqlite3 private connection) says. M1's closing review
;; found no engine reaching the window over fuel 1 to 3000 in one slice; a
;; remainder resumed at a fuel of 1 to 3 reaches it here.
(define own-wind-refused
  '(raised (assertion-violation test-open-interleave (re-entered))))

;; judged : Symbol Boolean Counts (Listof Run) -> (List Natural (Listof Any))
;; RUNS, those whose answers came back in the trial, for VERB, NEW? whether
;; the control made a whole new call at the trial's fuel, judged once the
;; trial's events are in: how many connections the runs answered, or were
;; given to the procedure; and what deviated. Every database answered is
;; checked, then closed, and the counts are then START's, those when the
;; trial began: zero, unless an earlier trial left something, which the
;; sweep's end finds.
(define (judged verb new? start runs)
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
    ;; for call-with-database, and a second only from a whole new call
    (if (eq? verb 'open-database)
        (unless (= (length conns) (length given))
          (deviate! (list 'opened (length conns) 'answered (length given))))
        (unless (<= (length conns) (if new? 2 1))
          (deviate! (list 'opened (length conns)))))
    (when (and (> (length given) 1) (not new?))
      (deviate! (list 'new-where-the-control-made-none (length given))))
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
    (list (length given) (reverse deviations))))

;; Trial = (List Symbol Natural (Listof Any))
;; Its kind, completed when R's first slice completed the call, last when
;; R's resume completed within G, else interleaved; how many connections, or
;; connections given to the procedure, were answered; and what deviated.

;; trial : Symbol Natural Natural Boolean -> Trial
;; One trial of VERB at FUEL, R resumed at G, NEW? the control's answer.
(define (trial verb fuel g new?)
  (set! noted '())
  (let* ((start (native-counts))
         (r (slice (make-engine (thunk-of verb)) fuel)))
    (if (eq? (car r) 'completed)
        (cons 'completed (judged verb new? start (list (list (cadr r) 0 'counts-kept))))
        (let* ((R (cadr r))
               (r1 (slice R g)))
          (if (eq? (car r1) 'completed)
              (let ((second (ran (lambda () (finish R)))))
                (cons 'last (judged verb new? start (list (list (cadr r1) 0 'counts-kept) second))))
              (let* ((R1 (cadr r1))
                     (second (ran (lambda () (finish R))))
                     (third (ran (lambda () (finish R1)))))
                (cons 'interleaved (judged verb new? start (list second third)))))))))

;; control : Symbol Natural -> (U Boolean 'completed)
;; VERB as an engine, one slice of FUEL: completed, when it completed; else
;; whether its remainder, resumed to its end, then resumed to its end again,
;; made a whole new call the second time: opened a connection of its own.
;; Every database either answered is closed.
(define (control verb fuel)
  (set! noted '())
  (let ((r (slice (make-engine (thunk-of verb)) fuel)))
    (if (eq? (car r) 'completed)
        (begin (when (a-database? (cadr r)) (close-answer (cadr r))) 'completed)
        (let* ((first (finish (cadr r)))
               (n (length noted))
               (second (finish (cadr r)))
               (new (let loop ((rest noted) (k (- (length noted) n)))
                      (cond ((= k 0) #f)
                            ((eq? (car (car rest)) 'open) #t)
                            (else (loop (cdr rest) (- k 1)))))))
          (when (a-database? first) (close-answer first))
          (when (and (a-database? second) (not (eq? second first))) (close-answer second))
          new))))

;; Sweep = (List Any Natural (Listof Any) Natural Natural Natural Counts)
;; The fuel at which the call completes without expiring, or
;; no-completion-by-20000; how many trials ran; each trial's deviations,
;; with its fuels; the trials in which a run answered a connection, or the
;; procedure; those in which a remainder made a whole new call; the last
;; fuel at which the control made one, 0 for none; and the counts once the
;; sweep is done.

;; sweep : Symbol -> Sweep
;; At every fuel from 1 until the call completes without expiring, the
;; control, then trial at every G from 1 until R's resume completes within
;; it, each fuel begun by quieted!, so no collect request falls in its
;; runs. A trial may make a whole new call where the control made one at
;; its fuel or the fuel before, a tick's room should a request fall all the
;; same: one costs a run up to a tick (.plans/research/m3-slice-5/,
;; gc-ticks.sps), so a trial's R would lie a tick before the control's.
(define (sweep verb)
  (let floop ((fuel 1) (trials 0) (deviations '()) (answered 0) (new 0) (last-new 0) (was-new #f))
    (let* ((made (begin (quieted!) (control verb fuel)))
           (new? (or (eq? made #t) was-new)))
      (if (eq? made 'completed)
          (list fuel trials (reverse deviations) answered new last-new (native-counts))
          (let ((last-new (if (eq? made #t) fuel last-new)))
            (let gloop ((g 1) (trials trials) (deviations deviations) (answered answered) (new new))
              (let* ((t (trial verb fuel g new?))
                     (kind (car t))
                     (deviations (if (null? (caddr t)) deviations
                                     (cons (list verb fuel g (caddr t)) deviations)))
                     (answered (if (> (cadr t) 0) (+ answered 1) answered))
                     (new (if (> (cadr t) 1) (+ new 1) new))
                     (trials (+ trials 1)))
                (cond ((eq? kind 'completed)
                       (list fuel trials (reverse deviations) answered new last-new (native-counts)))
                      ((>= fuel 20000)
                       (list 'no-completion-by-20000 trials (reverse deviations) answered new last-new
                             (native-counts)))
                      ((eq? kind 'last)
                       (floop (+ fuel 1) trials deviations answered new last-new (eq? made #t)))
                      (else (gloop (+ g 1) trials deviations answered new))))))))))

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

;; reported : Symbol Sweep -> (List Any Symbol Counts)
;; RUN's deviations, summarized; whether some trial answered a connection;
;; and the counts once it was done; its fuels printed, naming VERB.
(define (reported verb run)
  (display "  ")
  (display verb)
  (display ": completed without expiring at fuel ")
  (write (car run))
  (display "; trials ")
  (write (cadr run))
  (display "; trials answering ")
  (write (cadddr run))
  (display "; whole new calls ")
  (write (list-ref run 4))
  (display "; the last fuel at which the control made a whole new call ")
  (write (list-ref run 5))
  (newline)
  (unless (null? (caddr run))
    (display "    deviations by kind: ")
    (write (tallied (caddr run)))
    (newline))
  (list (if (integer? (car run)) (summarized (caddr run)) (list (car run) (summarized (caddr run))))
        (if (> (cadddr run) 0) 'some-answered 'none-answered)
        (list-ref run 6)))

(test-begin "open-interleave")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "the authorizer is registered for every new connection, through sqlite3_auto_extension, or the call is refused with its code; registering raises nothing"
  'registered-or-refused
  (if (tell-answered? registered) 'registered-or-refused registered))

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(let ((name "the tell: an open with the two settings is noted once, then each PRAGMA it prepares, in the plan's order, busy-timeout's first, its value and none for a read"))
  (tell-available! registered name)
  (test-equal name
    (list 1 plan as-asked zero-counts)
    (begin
      (set! noted '())
      (let* ((db (open-database ":memory:" settings))
             (conns (connections-of (reverse noted)))
             (c (latest-of (handle-of db) conns))
             (read (readings db)))
        (close-answer db)
        (list (length conns) (and c (cadr c)) read (native-counts))))))

(let ((name "open-database's remainder R, taken at every fuel from 1 until the call completes without expiring, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1: each run answers the connection or is refused with &sqlite-closed, touching nothing; every connection opened is answered; each setting is applied once, in the plan's order, on the connection answered; it tracks no statement and reads back as asked; once it is closed, nothing is counted"))
  (tell-available! registered name)
  (test-equal name
    (list '() 'some-answered zero-counts)
    (reported 'open-database (sweep 'open-database))))

(let ((name "call-with-database's remainder R, taken at every fuel from 1 until the call completes without expiring, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1: each run answers the procedure's answer or &sqlite-closed, a refused run touching nothing; at most one connection a call is opened, and none is left open; each setting is applied once, in the plan's order, and wholly on the connection the procedure was given, which tracks no statement there; nothing is counted after"))
  (tell-available! registered name)
  (test-equal name
    (list '() 'some-answered zero-counts)
    (reported 'call-with-database (sweep 'call-with-database))))

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

;; failing-twice : Symbol Natural Boolean -> (U 'completed (List Symbol (Listof Any)))
;; VERB with failing as an engine, one slice of FUEL, NEW? whether a whole
;; new call may come at it, by the control; expired, its remainder
;; resumed to its end, then again. Answers completed when the slice
;; completed; else the second's kind, refused, again or new, and what
;; deviated: the first not the mismatch, or, for call-with-database, not
;; &sqlite-closed either, an expiry after the open having closed the
;; connection; the second anything else, or
;; noting what it may not; a new one where the control made none; a
;; connection's PRAGMAs no prefix of the plan, or one twice; anything
;; counted after. A remainder taken while open-database's connection was
;; still open, counted at the expiry beyond the counts at the start, lies
;; before the failure's close, so
;; the second resume is refused, there or earlier, never the mismatch
;; again: that comes only from one taken past the close. An expiry closes
;; call-with-database's connection, so none is counted at its expiries.
(define (failing-twice verb fuel new?)
  (begin
    (set! noted '())
    (let* ((start (native-counts))
           (r (slice (make-engine (failing-thunk-of verb)) fuel)))
      (if (eq? (car r) 'completed)
          'completed
          (let* ((open-at-expiry (> (cdr (assq 'connection (native-counts)))
                                    (cdr (assq 'connection start))))
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
                 (quiet (and (eqv? (cadr second) 0) (eq? (caddr second) 'counts-kept)))
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
            (when (and (eq? kind 'new) (not new?)) (deviate! (list 'new-where-the-control-made-none)))
            (when (and open-at-expiry (not (eq? kind 'refused)))
              (deviate! (list 'open-at-the-expiry-but-not-refused kind)))
            (let loop ((rest conns))
              (unless (null? rest)
                (unless (prefix? (cadr (car rest)) failing-plan)
                  (deviate! (list 'not-the-plan (cadr (car rest)))))
                (loop (cdr rest))))
            (unless (equal? (native-counts) start) (deviate! (list 'counts start (native-counts))))
            (list kind (reverse deviations)))))))

;; failing-sweep : Symbol -> (List Any (Listof Any) (Listof (Pairof Symbol Natural)) Counts)
;; failing-twice at every fuel from 1 until the call completes without
;; expiring, at most 20000, a whole new call allowed where the succeeding
;; call's control made one, at the fuel or the one before, as sweep allows
;; it: the checks run in one section, which spends no ticks, so the two
;; calls' ticks before their claims are alike. That fuel; each fuel's
;; deviations; how many fuels each kind came at; and the counts after.
(define (failing-sweep verb)
  (let loop ((fuel 1) (deviations '()) (kinds '()) (was-new #f))
    (let* ((made (begin (quieted!) (control verb fuel)))
           (t (failing-twice verb fuel (or (eq? made #t) was-new))))
      (cond ((eq? t 'completed) (list fuel (reverse deviations) kinds (native-counts)))
            ((>= fuel 20000) (list 'no-completion-by-20000 (reverse deviations) kinds (native-counts)))
            (else
             (loop (+ fuel 1)
                   (if (null? (cadr t)) deviations (cons (cons fuel (cadr t)) deviations))
                   (counted-up (car t) kinds)
                   (eq? made #t)))))))

;; failing-reported : Symbol (List Any (Listof Any) (Listof (Pairof Symbol Natural)) Counts)
;;                    -> (List Any Symbol Counts)
(define (failing-reported verb run)
  (display "  ")
  (display verb)
  (display ", failing, resumed twice: completed without expiring at fuel ")
  (write (car run))
  (display "; second resumes ")
  (write (caddr run))
  (newline)
  (list (summarized (cadr run))
        (let ((p (assq 'refused (caddr run)))) (if (and p (> (cdr p) 0)) 'some-refused 'none-refused))
        (cadddr run)))

(let ((name "open-database with busy-timeout and journal-mode wal on :memory:, which mismatches, its remainder taken at every fuel from 1 until it completes without expiring and resumed to its end twice: the first raises the mismatch, the connection closed; the second is refused with &sqlite-closed, or, past the failure's close, raises the mismatch again, noting nothing and changing no count; only where the control makes a whole new call does it open a connection, which mismatches alone; no PRAGMA is prepared twice on a connection; nothing is counted after"))
  (tell-available! registered name)
  (test-equal name
    (list '() 'some-refused zero-counts)
    (failing-reported 'open-database (failing-sweep 'open-database))))

(let ((name "call-with-database the same: the first raises the mismatch, its procedure never called, or &sqlite-closed where the expiry closed the connection; the second is refused, or raises the mismatch again, noting nothing; only where the control makes a whole new call does it open a connection; nothing is counted after"))
  (tell-available! registered name)
  (test-equal name
    (list '() 'some-refused zero-counts)
    (failing-reported 'call-with-database (failing-sweep 'call-with-database))))

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
