#!r6rs
;;; The suite for with-transaction under engines (ADR-0017, decision 7, and
;;; its amendments in M3 slices 1 and 3; the M3 plan, section 4.2), in
;;; (chez-sqlite3 private transaction). An engine spends no ticks inside a
;;; critical section (.plans/traps.md), so each expiry falls between
;;; sections; each is an escape, which runs with-transaction's after thunks,
;;; and the resume runs the before thunks again.
;;;
;;;   the sweeps     an engine around with-transaction, at the outer level
;;;                  and nested, at every fuel from 1 until the call
;;;                  completes without expiring, resumed to the end after
;;;                  each expiry: it commits once, or raises
;;;                  &sqlite-transaction-ended, never anything else; its
;;;                  level begins once; it never commits what an expiry
;;;                  rolled back, and never steps a COMMIT, RELEASE or
;;;                  rollback once ENDED is set, read by each statement's
;;;                  runs, sqlite3_stmt_status's count, and the extended code.
;;;                  The fuels are printed: where each outcome begins, and
;;;                  the fuel that completes
;;;   before begun   an expiry before the BEGIN's step answers rolls nothing
;;;                  back, and the resume begins and commits
;;;   a second resume
;;;                  a remainder resumed again once its call has ended, at
;;;                  every fuel's first expiry, the second resume sliced one
;;;                  tick at a time: it checks out, steps and returns none
;;;                  of with-transaction's statements, read between every
;;;                  slice by the cache's count and the statements' states
;;;                  and runs, and at its end by the extended code. This is
;;;                  the row that settles ADR-0017's open question, in its
;;;                  slice 3 amendment: ENDED is checked-out's check
;;;   no cut SQL     every fuel's first remainder resumed to its end, then
;;;                  again: the connection tracks no SQL but the allowed, its
;;;                  savepoints named in full, and the extended code is 0. A
;;;                  remainder resumed twice from inside number->string
;;;                  answers "" on Chez 10.4.0
;;;   once           O7 nested, a failed RELEASE rolled back, under an engine
;;;                  at every fuel: the rollback is tried once, read by the
;;;                  tracked statements, the extended code and the runs
;;;   left behind    O7 nested, under an engine at every fuel, once the outer
;;;                  call has returned: none of with-transaction's statements
;;;                  is tracked failed or checked out and left, the depth is
;;;                  0, and a later with-transaction commits
;;;   the siblings   an engine taken inside an outer call and resumed inside a
;;;                  sibling level: the resume leaves the sibling, which rolls
;;;                  back and raises the ended condition
;;;
;;; Reached through eval under a guard. Every computation that can raise
;;; runs under a guard with a sentinel of its own. Effects run in order,
;;; through let* and named lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) make-engine foreign-procedure timer-interrupt-handler set-timer)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-closed? sqlite-transaction-ended?))

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

(define (reach library name)
  (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
    (eval name (environment library))))

(define public '(chez-sqlite3))
(define connection-library '(chez-sqlite3 private connection))
(define statement-library '(chez-sqlite3 private statement))
(define with-transaction (reach public 'with-transaction))
(define open-database (reach public 'open-database))
(define close-database! (reach public 'close-database!))
(define execute! (reach public 'execute!))
(define query-row (reach public 'query-row))
(define in-transaction? (reach public 'in-transaction?))
(define statement-sql (reach public 'statement-sql))
(define statement-state (reach statement-library 'statement-state))
(define call-with-statement-handle (reach statement-library 'call-with-statement-handle))
(define tracked-statements (reach connection-library 'tracked-statements))
(define call-with-open-handle (reach connection-library 'call-with-open-handle))
(define database-cache-count (reach connection-library 'database-cache-count))
(define database-depth (reach connection-library 'database-depth))
(define prepare-statement (reach public 'prepare-statement))
(define finalize-statement! (reach public 'finalize-statement!))
(define step! (reach public 'step!))
(define query (reach public 'query))
(define sqlite3-extended-errcode (reach '(chez-sqlite3 private native) 'sqlite3-extended-errcode))
(define database-cache-check-out! (reach connection-library 'database-cache-check-out!))
(define database-cache-return! (reach connection-library 'database-cache-return!))
(define sqlite3-interrupt (reach '(chez-sqlite3 private native) 'sqlite3-interrupt))

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; int sqlite3_stmt_status(sqlite3_stmt*, int op, int reset), never bound by
;; chez-sqlite3; SQLITE_STMTSTATUS_RUN is 6, at the floor and since. It
;; counts a run when a step starts the statement's program, the first step
;; after a prepare or a reset. A step that fails at its entry, as an
;; interrupted one does beside a held row, starts none and counts none (M3
;; slice 4's review), so no row reads runs where an interrupt may land, and
;; none here is interrupted.
(define stmt-status (bound 'sqlite3_stmt_status (foreign-procedure "sqlite3_stmt_status" (uptr int int) int)))
(define stmtstatus-run 6)

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

(define (what-raised e)
  (cond ((sqlite-transaction-ended? e) (list 'transaction-ended (who-of e)))
        ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((chez-sqlite3-error? e) (list 'chez-sqlite3-error (describe e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        ((condition? e) (list 'other (describe e)))
        (else (list 'value e))))

(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define (extended db) (call-with-open-handle 'test-transaction-engine db sqlite3-extended-errcode))

(define (runs st)
  (call-with-statement-handle 'test-transaction-engine st 'statement-sql
    (lambda (connection handle sql) (values #f (stmt-status handle stmtstatus-run 0)))))

(define (prefix? p s) (and (<= (string-length p) (string-length s))
                           (string=? p (substring s 0 (string-length p)))))

(define (own-sql? s)
  (or (member s '("BEGIN DEFERRED" "BEGIN IMMEDIATE" "BEGIN EXCLUSIVE" "COMMIT" "ROLLBACK"))
      (prefix? "SAVEPOINT chez_sqlite3_" s) (prefix? "RELEASE chez_sqlite3_" s)
      (prefix? "ROLLBACK TO chez_sqlite3_" s)))

;; own-statements : Database -> (Listof (List String Symbol Integer))
;; with-transaction's statements DB tracks, oldest first, with their states
;; and runs.
(define (own-statements db)
  (let loop ((rest (tracked-statements db)) (found '()))
    (if (null? rest)
        (reverse found)
        (let ((sql (statement-sql (car rest))))
          (loop (cdr rest)
                (if (own-sql? sql)
                    (cons (list sql (statement-state (car rest)) (runs (car rest))) found)
                    found))))))

;; runs-of : (Listof (List String Symbol Integer)) String -> Integer
;; The runs of SQL's tracked statement, 0 when none is tracked.
(define (runs-of statements sql)
  (let ((found (filter (lambda (s) (string=? (car s) sql)) statements)))
    (if (null? found) 0 (caddr (car found)))))

;; own-runs : Database -> (Listof (List String Integer Statement))
;; with-transaction's statements DB tracks, with their runs and themselves.
(define (own-runs db)
  (let loop ((rest (tracked-statements db)) (found '()))
    (if (null? rest)
        (reverse found)
        (let ((sql (statement-sql (car rest))))
          (loop (cdr rest)
                (if (own-sql? sql) (cons (list sql (runs (car rest)) (car rest)) found) found))))))

;; not-ready : (Listof (List String Symbol Integer)) -> (Listof Any)
(define (not-ready statements)
  (filter (lambda (s) (not (eq? (cadr s) 'ready))) statements))

(define temp-dir (guard (e (#t #f)) (make-process-temp-directory)))
(define case-number 0)
(define (fresh-path)
  (set! case-number (+ case-number 1))
  (string-append (or temp-dir "/nonexistent") "/case-" (number->string case-number) ".db"))

;; with-files : (Database Database -> Any) -> Any
;; PROC's answer, or what it raised, given two connections to a fresh file
;; holding t; both closed after.
(define (with-files proc)
  (let ((db #f) (db2 #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt (lambda ()
                   (let ((path (fresh-path)))
                     (set! db (open-database path))
                     (execute! db "create table t (x)")
                     (set! db2 (open-database path))
                     (proc db db2)))))
      (lambda ()
        (when db2 (guard (e (#t #f)) (close-database! db2)))
        (when db (guard (e (#t #f)) (close-database! db)))))))

;; complete, expire : the engine's procedures: a completion's answer, and
;; the remainder.
(define (complete left . vals) (list 'completed (car vals)))
(define (expire more) more)

;; finish : Engine Positive-Integer -> Any
;; The answer of E, an engine's remainder, resumed with FUEL a slice until
;; it completes, at most 100000 times.
(define (finish e fuel)
  (let loop ((e e) (n 0))
    (let ((next (e fuel (lambda (left . vals) (list 'completed (car vals))) (lambda (more) more))))
      (cond ((pair? next) (cadr next))
            ((>= n 100000) 'never-completed)
            (else (loop next (+ n 1)))))))

;; engine-run : (-> Any) Positive-Integer -> (List Any Boolean)
;; THUNK's answer, run in an engine of FUEL ticks a slice and resumed with
;; FUEL again after each expiry, at most 100000 times; and whether it
;; expired at all.
(define (engine-run thunk fuel)
  (let loop ((e (make-engine thunk)) (expired #f) (n 0))
    (let ((next (e fuel (lambda (left . vals) (list 'completed (car vals))) (lambda (more) more))))
      (cond ((pair? next) (list (cadr next) expired))
            ((>= n 100000) (list 'never-completed #t))
            (else (loop next #t (+ n 1)))))))

;; sweep : (Positive-Integer -> (List Boolean Any Any)) Positive-Integer
;;         -> (List Any (Listof Any) (Listof (List Positive-Integer Any)))
;; CHECK at each fuel from 1, until a fuel at which the call completed
;; without expiring, at most CAP: that fuel, each fuel's deviation, in
;; order, and the fuels at which the outcome's kind changed, with the kind.
;; CHECK answers whether the call expired, #f or what deviated, and the
;; outcome's kind.
(define (sweep check cap)
  (let loop ((fuel 1) (found '()) (kinds '()) (last #f))
    (let* ((r (check fuel))
           (more (if (cadr r) (cons (list fuel (cadr r)) found) found))
           (kinds* (if (equal? (caddr r) last) kinds (cons (list fuel (caddr r)) kinds))))
      (cond ((not (car r)) (list fuel (reverse more) (reverse kinds*)))
            ((>= fuel cap) (list (list 'no-completion-by cap) (reverse more) (reverse kinds*)))
            (else (loop (+ fuel 1) more kinds* (caddr r)))))))

;; named : String (List Any (Listof Any) (Listof Any)) -> (Listof Any)
;; RUN's deviations, its completing fuel and its outcomes' first fuels
;; printed, naming WHAT.
(define (named what run)
  (display "  ")
  (display what)
  (display ": completed without expiring at fuel ")
  (write (car run))
  (display "; each outcome from the fuel ")
  (write (caddr run))
  (newline)
  (if (integer? (car run)) (cadr run) (cons (car run) (cadr run))))

;; --- the sweeps -------------------------------------------------------------------------------

;; outcome-kind : Any Integer -> Symbol
;; What a fuel's call did: committed, answering 42 with its row seen once;
;; rolled-back, &sqlite-transaction-ended with the row absent; or
;; ended-after-a-later-write, &sqlite-transaction-ended with the row present,
;; the expiry's rollback having fallen before the body's insert, which then
;; autocommitted (single L1's shape; ADR-0017's consequences). Anything else
;; is no kind.
(define (outcome-kind answer seen)
  (cond ((and (eqv? answer 42) (eqv? seen 1)) 'committed)
        ((and (equal? answer '(raised (transaction-ended with-transaction))) (eqv? seen 0)) 'rolled-back)
        ((and (equal? answer '(raised (transaction-ended with-transaction))) (eqv? seen 1))
         'ended-after-a-later-write)
        (else 'no-kind)))

;; delta : (Listof Any) (Listof Any) (Listof String) -> (Listof Integer)
;; How many times each of SQLS ran between BEFORE and AFTER, two own-runs
;; readings: over every statement of that SQL tracked after, its runs, less
;; its runs before when it was tracked then. A statement the cache gave up for
;; another of the same SQL, as when the after thunk prepared its own while
;; the commit held the cached one, counts the new one's runs; the one given
;; up is finalized, unread, and a step of it that failed shows in the
;; extended code.
(define (delta before after sqls)
  (let loop ((rest sqls) (out '()))
    (if (null? rest)
        (reverse out)
        (let* ((sql (car rest))
               (n (fold-left
                   (lambda (sum a)
                     (if (string=? (car a) sql)
                         (let ((b (filter (lambda (b) (eq? (caddr b) (caddr a))) before)))
                           (+ sum (if (null? b) (cadr a) (- (cadr a) (cadr (car b))))))
                         sum))
                   0 after)))
          (loop (cdr rest) (cons n out))))))

(test-begin "transaction-engine")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-assert "a temporary directory for the suite's databases"
  (string? temp-dir))

(test-equal "the outer sweep: an engine around with-transaction, deferred, whose body inserts the fuel and answers 42, at every fuel from 1 until it completes without expiring, resumed after each expiry: it commits once, its row seen once by db2, BEGIN, then COMMIT, run once each; or raises &sqlite-transaction-ended, BEGIN and ROLLBACK run once each and COMMIT never, the row absent, or present when the rollback fell before the insert, which autocommitted; never another outcome; with-transaction's statements all ready, in-transaction? #f and the extended code 0 after every fuel"
  '()
  (with-files
   (lambda (db db2)
     (named "the outer sweep"
            (sweep (lambda (fuel)
                     (let* ((before (own-runs db))
                            (r (engine-run (lambda ()
                                             (attempt (lambda ()
                                                        (with-transaction db 'deferred
                                                          (lambda () (execute! db "insert into t values (?)" fuel) 42)))))
                                           fuel))
                            (code (extended db))
                            (in (in-transaction? db))
                            (after (own-runs db))
                            (states (own-statements db))
                            (seen (attempt (lambda () (vector-ref (query-row db2 "select count(*) from t where x = ?" fuel) 0))))
                            (kind (outcome-kind (car r) seen))
                            (runs (delta before after '("BEGIN DEFERRED" "COMMIT" "ROLLBACK")))
                            (expected-runs (if (eq? kind 'committed) '(1 1 0) '(1 0 1)))
                            (whole (list kind runs (not-ready states) in code)))
                       (list (cadr r)
                             (and (or (eq? kind 'no-kind)
                                      (not (equal? whole (list kind expected-runs '() #f 0))))
                                  (list (car r) seen whole))
                             kind)))
                   5000)))))

(test-equal "the nested sweep: inside an outer with-transaction, an engine around a nested one whose body inserts the fuel and answers 42: at every fuel it commits once, SAVEPOINT and RELEASE run once each and ROLLBACK TO never; or raises &sqlite-transaction-ended, SAVEPOINT, ROLLBACK TO and RELEASE run once each; never another outcome; the outer level stays open throughout and commits, so db2 then sees the row once, or not, by the same rule"
  '()
  (with-files
   (lambda (db db2)
     (named "the nested sweep"
            (sweep (lambda (fuel)
                     (let* ((inside #f)
                            (before (own-runs db))
                            (r (with-transaction db 'deferred
                                 (lambda ()
                                   (let ((r (engine-run (lambda ()
                                                          (attempt (lambda ()
                                                                     (with-transaction db
                                                                       (lambda () (execute! db "insert into t values (?)" fuel) 42)))))
                                                        fuel)))
                                     (set! inside (in-transaction? db))
                                     r))))
                            (code (extended db))
                            (in (in-transaction? db))
                            (after (own-runs db))
                            (states (own-statements db))
                            (seen (attempt (lambda () (vector-ref (query-row db2 "select count(*) from t where x = ?" fuel) 0))))
                            (kind (outcome-kind (car r) seen))
                            (runs (delta before after '("SAVEPOINT chez_sqlite3_1" "RELEASE chez_sqlite3_1"
                                                        "ROLLBACK TO chez_sqlite3_1")))
                            (expected-runs (if (eq? kind 'committed) '(1 1 0) '(1 1 1)))
                            (whole (list kind runs (not-ready states) inside in code)))
                       (list (cadr r)
                             (and (or (eq? kind 'no-kind)
                                      (not (equal? whole (list kind expected-runs '() #t #f 0))))
                                  (list (car r) seen whole))
                             kind)))
                   5000)))))

;; --- an expiry before begun ----------------------------------------------------------------

;; before-begun : Database Database Positive-Integer String String String -> (U #f Any)
;; The call, inserting a row of its own, given a first slice of FUEL ticks;
;; #f when that slice began the level, BEGIN-SQL having run, or completed
;; the call. Else, resumed with fuel to spare: its answer, the row's count
;; as DB2 sees it, and the runs of BEGIN-SQL, COMMIT-SQL and ROLLBACK-SQL
;; since before the call.
(define (before-begun db db2 fuel nested begin-sql commit-sql rollback-sql)
  (let* ((row (string-append (if nested "nested-before-" "outer-before-") (number->string fuel)))
         (call (lambda ()
                 (attempt (lambda ()
                            (with-transaction db 'deferred
                              (lambda () (execute! db "insert into t values (?)" row) 42))))))
         (run (lambda ()
                (let* ((before (own-runs db))
                       (first ((make-engine call) fuel complete expire)))
                  (cond ((not (procedure? first)) #f)
                        ((> (car (delta before (own-runs db) (list begin-sql))) 0)
                         (finish first 1000000)
                         #f)
                        (else
                         (let* ((answer (first 1000000 (lambda (left . vals) (car vals)) (lambda (more) 'expired-again)))
                                (after (own-runs db)))
                           (list answer (delta before after (list begin-sql commit-sql rollback-sql)))))))))
         (r (if nested (with-transaction db 'deferred run) (run))))
    (and r (list (car r)
                 (attempt (lambda () (vector-ref (query-row db2 "select count(*) from t where x = ?" row) 0)))
                 (cadr r)))))

;; before-sweep : Database Database Boolean String String String -> (List Natural (Listof Any))
;; before-begun at every fuel from 1 until a first slice begins the level:
;; how many fuels expired before it, and those whose outcome differs from
;; 42, the row seen once, and the runs (1 1 0).
(define (before-sweep db db2 nested begin-sql commit-sql rollback-sql)
  (let loop ((fuel 1) (found '()))
    (let ((r (before-begun db db2 fuel nested begin-sql commit-sql rollback-sql)))
      (cond ((not r) (list (- fuel 1) (reverse found)))
            ((>= fuel 5000) (list 'no-begin-by-5000 (reverse found)))
            ((equal? r '(42 1 (1 1 0))) (loop (+ fuel 1) found))
            (else (loop (+ fuel 1) (cons (list fuel r) found)))))))

(test-equal "an expiry before the BEGIN's step answers rolls nothing back: at every fuel from 1 until a first slice begins the level, that slice expiring before begun is set and the call then resumed with fuel to spare, it begins once and commits: 42, the row seen once, BEGIN and COMMIT run once each, ROLLBACK never; nested, SAVEPOINT and RELEASE once, ROLLBACK TO never"
  '((many ()) (many ()))
  (with-files
   (lambda (db db2)
     (let* ((outer (before-sweep db db2 #f "BEGIN DEFERRED" "COMMIT" "ROLLBACK"))
            (nested (before-sweep db db2 #t "SAVEPOINT chez_sqlite3_1" "RELEASE chez_sqlite3_1"
                                  "ROLLBACK TO chez_sqlite3_1"))
            (shown (lambda (what r)
                     (display "  ")
                     (display what)
                     (display ": first slices that expired before begun: ")
                     (write (car r))
                     (newline)
                     (list (if (and (integer? (car r)) (> (car r) 1)) 'many (car r)) (cadr r)))))
       (list (shown "the outer level" outer) (shown "nested" nested))))))

;; --- a remainder resumed a second time ------------------------------------------------------

;; snapshot : Database -> (List Natural (Listof Any))
;; The cache's count, and with-transaction's statements with their states
;; and runs.
(define (snapshot db) (list (database-cache-count db) (own-statements db)))


;; after-ended : Database (-> Any) Positive-Integer String -> (U 'completed (Listof Engine))
;; THUNK, a with-transaction on DB, given a first slice of FUEL ticks. When
;; that slice expired after BEGIN-SQL ran, its level begun, every expiry
;; from there falls with ENDED set: that one's after thunk rolled the level
;; back, or the commit had set it. Then the call is resumed one tick a slice
;; to its end, and every remainder it made is answered, the first slice's
;; first. completed when the first slice completed the call. Otherwise
;; none, the call finished with fuel to spare: a remainder taken before the call bound its flags
;; makes a whole new call when resumed (.plans/traps.md).
(define (after-ended db thunk fuel begin-sql)
  (let* ((before (own-runs db))
         (first ((make-engine thunk) fuel complete expire))
         (begun (and (procedure? first)
                     (> (car (delta before (own-runs db) (list begin-sql))) 0))))
    (cond ((not (procedure? first)) 'completed)
          ((not begun) (finish first 1000000) '())
          (else
           (let loop ((e first) (rs (list first)) (n 0))
             (let ((next (e 1 complete expire)))
               (cond ((pair? next) (reverse rs))
                     ((>= n 100000) (reverse rs))
                     (else (loop next (cons next rs) (+ n 1))))))))))

;; resumed-again : Database Engine -> (Listof Any)
;; R, a remainder whose call has ended, resumed a second time, one tick a
;; slice: (answered A), A R's answer, when the cache's count read between
;; every slice, and DB's snapshot and extended code read at its end, are
;; those before it; else what differed, and R's answer.
(define (resumed-again db r)
  (let* ((base (snapshot db))
         (code (extended db)))
    (let loop ((e r) (n 0) (dips '()))
      (let* ((next (e 1 complete expire))
             (count (database-cache-count db))
             (dips* (if (eqv? count (car base)) dips (cons (list n count) dips))))
        (cond ((pair? next)
               (let ((now (snapshot db)) (code* (extended db)))
                 (if (or (pair? dips*) (not (equal? now base)) (not (eqv? code code*)))
                     (list 'cache-count-between-slices (reverse dips*) 'before base 'after now
                           'extended code code* 'answer (cadr next))
                     (list 'answered (cadr next)))))
              ((>= n 100000) (list 'never-completed))
              (else (loop next (+ n 1) dips*)))))))

;; allowed-second-answers : (Listof Any)
;; What a remainder resumed a second time may answer: the body's value, the
;; refusal of a re-entry, or the ended level's condition. Never an
;; &sqlite-error: that is a COMMIT or RELEASE that reached SQLite with the
;; level over. The cache's snapshot cannot see it, for a second resume takes,
;; steps and returns a statement within one slice.
(define allowed-second-answers
  '(42
    (raised (assertion-violation with-transaction (re-entered)))
    (raised (transaction-ended with-transaction))))

;; twice : String Database (-> (-> Any)) String -> (Listof Any)
;; At every fuel from 1 until the call completes without expiring, each
;; remainder after-ended answers, resumed again: the fuels and remainders
;; that touched a statement of with-transaction's. Prints how many fuels
;; began their level in the first slice, how many remainders were resumed
;; twice, and the answers they gave.
(define (twice what db thunk-of begin-sql)
  (let loop ((fuel 1) (found '()) (checked 0) (remainders 0) (answers '()))
    (let* ((rs (after-ended db (thunk-of) fuel begin-sql))
           (completes (eq? rs 'completed)))
      (if (or completes (>= fuel 5000))
          (begin
            (display "  ")
            (display what)
            (display ": fuels 1 to ")
            (write fuel)
            (display "; first slices that began the level: ")
            (write checked)
            (display "; remainders resumed twice: ")
            (write remainders)
            (display "; their second answers: ")
            (write answers)
            (display "; that touched a statement: ")
            (write (length found))
            (newline)
            (let ((bad (filter (lambda (a) (not (member a allowed-second-answers))) answers))
                  (found* (reverse found)))
              (append (if completes found* (cons 'no-completion-by-5000 found*))
                      (if (null? bad) '() (list (list 'second-answers-outside-the-allowed bad))))))
          (let inner ((rest rs) (k 0) (found found) (answers answers))
            (if (null? rest)
                (loop (+ fuel 1) found (if (null? rs) checked (+ checked 1)) (+ remainders (length rs))
                      answers)
                (let ((d (resumed-again db (car rest))))
                  (inner (cdr rest) (+ k 1)
                         (if (and (pair? d) (eq? (car d) 'answered)) found (cons (list fuel k d) found))
                         (if (and (pair? d) (eq? (car d) 'answered))
                             (if (member (cadr d) answers) answers (cons (cadr d) answers))
                             answers)))))))))

(test-equal "a remainder captured once ENDED is set, resumed a second time once its call has ended, checks out, steps and returns none of with-transaction's statements: at every fuel until the call completes unexpired whose first slice began the level, each remainder from that expiry on, resumed again one tick a slice, leaves the cache's count unchanged between every slice, and each statement's state and runs, and the extended code, at its end, and answers 42, the re-entry's refusal or &sqlite-transaction-ended, never an &sqlite-error; at the outer level and nested"
  '(() ())
  (with-files
   (lambda (db db2)
     (let* ((prime (with-transaction db 'deferred (lambda () (with-transaction db (lambda () 'primed)))))
            (outer (twice "the outer level" db
                          (lambda () (lambda () (attempt (lambda () (with-transaction db 'deferred (lambda () 42))))))
                          "BEGIN DEFERRED"))
            (nested (with-transaction db 'deferred
                      (lambda ()
                        (twice "nested" db
                               (lambda () (lambda () (attempt (lambda () (with-transaction db (lambda () 42))))))
                               "SAVEPOINT chez_sqlite3_1")))))
       (list outer nested)))))

;; --- no cut or wrong SQL reaches SQLite -----------------------------------------------------
;;
;; On Chez 10.4.0 an engine's remainder resumed a second time from inside
;; number->string answers "" (the lead's probe, M3 slice 4). with-transaction
;; builds its savepoints' names from N, so its plans, which build them, are
;; made inside call-with-open-handle's sections, where no expiry lands. This
;; row holds that: no statement but the allowed ones is ever tracked, and the
;; extended code stays 0, after either resume.

;; sql-texts : Database -> (Listof String)
;; The SQL of every statement DB tracks, the cache's among them, each once,
;; sorted.
(define (sql-texts db)
  (let loop ((rest (tracked-statements db)) (found '()))
    (if (null? rest)
        (list-sort string<? found)
        (let ((sql (statement-sql (car rest))))
          (loop (cdr rest) (if (member sql found) found (cons sql found)))))))

;; resumed-twice : String Database (-> (-> Any)) (Listof String) -> (Listof Any)
;; At every fuel from 1 until the first slice completes the call: the first
;; slice's remainder resumed to its end, then resumed again to its end. After
;; each, every SQL DB tracks is one of ALLOWED and the extended code is 0:
;; the fuels and resumes where either is not, with what was found. Prints how
;; many remainders were resumed twice.
(define (resumed-twice what db thunk-of allowed)
  (let loop ((fuel 1) (found '()))
    (let ((first ((make-engine (thunk-of)) fuel complete expire)))
      (if (or (not (procedure? first)) (>= fuel 5000))
          (begin
            (display "  ")
            (display what)
            (display ": every first remainder, fuels 1 to ")
            (write (- fuel 1))
            (display ", resumed twice; resumes that tracked other SQL or left a code: ")
            (write (length found))
            (newline)
            (reverse found))
          (let* ((check (lambda (which)
                          (let* ((texts (sql-texts db))
                                 (other (filter (lambda (t) (not (member t allowed))) texts))
                                 (code (extended db)))
                            (and (or (pair? other) (not (eqv? code 0)))
                                 (list fuel which other code)))))
                 (a1 (finish first 1000000))
                 (c1 (check 'first))
                 (a2 (finish first 1000000))
                 (c2 (check 'second))
                 (found* (cond ((and c1 c2) (cons c2 (cons c1 found)))
                               (c1 (cons c1 found))
                               (c2 (cons c2 found))
                               (else found))))
            (loop (+ fuel 1) found*))))))

(define allowed-outer '("BEGIN DEFERRED" "COMMIT" "ROLLBACK" "create table t (x)"))
(define allowed-nested
  (append allowed-outer '("SAVEPOINT chez_sqlite3_1" "RELEASE chez_sqlite3_1" "ROLLBACK TO chez_sqlite3_1")))

(test-equal "no cut or wrong SQL reaches SQLite: at every fuel until the call completes unexpired, its first remainder resumed to its end and then a second time, at the outer level and nested, a whole new call among them where the remainder was taken before the call began, the connection tracks no SQL but with-transaction's own, its savepoints named in full, and the extended code is 0 after each"
  '(() ())
  (with-files
   (lambda (db db2)
     (let* ((outer (resumed-twice "the outer level" db
                                  (lambda () (lambda () (attempt (lambda () (with-transaction db 'deferred (lambda () 42))))))
                                  allowed-outer))
            (nested (with-transaction db 'deferred
                      (lambda ()
                        (resumed-twice "nested" db
                                       (lambda () (lambda () (attempt (lambda () (with-transaction db (lambda () 42))))))
                                       allowed-nested)))))
       (list outer nested)))))

;; --- a failed commit's rollback, tried once under any expiry ----------------------------------
;;
;; O7 nested: the inner level's RELEASE answers busy beside the body's own
;; insert ... returning held at its row, so the failed commit is rolled back,
;; ROLLBACK TO answering done, then RELEASE busy again (slice 3's "Once"). An
;; engine whose ticks run out inside that rollback escapes, and its exit
;; must not issue again what the rollback already issued. Counted through the
;; statements the connection tracks and the extended code, and the runs of the
;; tracked ROLLBACK TO, the one thing they cannot show: a
;; ROLLBACK TO the rollback took and the exit's own are two tracked
;; statements, the first left at done, or left ready when its step never
;; came; one cached and stepped again is one, which only the runs would show.

(define release-1 "RELEASE chez_sqlite3_1")
(define rollback-to-1 "ROLLBACK TO chez_sqlite3_1")

;; states-of : (Listof (List String Symbol Integer)) String -> (Listof Symbol)
;; The states of the tracked statements of SQL, oldest first.
(define (states-of statements sql)
  (let loop ((rest statements) (out '()))
    (cond ((null? rest) (reverse out))
          ((string=? (car (car rest)) sql) (loop (cdr rest) (cons (cadr (car rest)) out)))
          (else (loop (cdr rest) out)))))

;; engine-lost? : Any -> Boolean
;; Whether E is what an engine's run raises when an exit's failure is raised
;; as the engine runs out: Chez's own error, "no engine active".
(define (engine-lost? e)
  (and (condition? e) (message-condition? e) (equal? (condition-message e) "no engine active")))

;; o7-engine : Positive-Integer -> (List Boolean Any Symbol)
;; At FUEL: inside an outer with-transaction, deferred, on a fresh file, an
;; engine of FUEL ticks a slice around the inner with-transaction, whose body
;; writes inner, holds insert ... returning at its row, and returns; resumed
;; to its end after each expiry. Whether the first slice expired; #f, or
;; what deviated; and the run's kind, ended, busy or lost, read from its
;; answer. A run's whole outcome: its kind; the extended code straight
;; after it; the states of the tracked ROLLBACK TO and RELEASE; the depth
;; inside the outer; then the outer's answer, in-transaction? and the depth
;; after it. Expected, by kind: ended, the exit's rollback ran before the
;; held step, which then answered its row, 100, one ROLLBACK TO and one
;; RELEASE, ready; busy, the commit's failure raised once its rollback ran,
;; the RELEASE's busy, 5, one ROLLBACK TO, ready, and no RELEASE, its failed
;; ones finalized; lost, the exit's own RELEASE failed as the engine ran
;; out, 5, one ROLLBACK TO, ready, and no RELEASE, the lost engine leaving
;; none checked out. Always depth 1 inside, and the outer
;; commits. The tracked ROLLBACK TO has run once, at every kind.
(define (o7-engine fuel)
  (let ((r (with-files
            (lambda (db db2)
              (execute! db "create table r (x)")
              (let* ((held #f) (inside #f)
                     (w (with-transaction db 'deferred
                          (lambda ()
                            (execute! db "insert into t values ('outer')")
                            (let* ((run (guard (e ((engine-lost? e) 'the-engine-was-lost)
                                                  (#t (list 'raised (what-raised e))))
                                           (engine-run
                                            (lambda ()
                                              (attempt
                                               (lambda ()
                                                 (with-transaction db
                                                   (lambda ()
                                                     (execute! db "insert into t values ('inner')")
                                                     (set! held (prepare-statement db "insert into r values (6), (7) returning x"))
                                                     (step! held)
                                                     'inner-returned)))))
                                            fuel)))
                                   (code (extended db))
                                   (own (own-statements db))
                                   (depth (database-depth db)))
                              (when held (finalize-statement! held))
                              (set! inside (list run code own depth))
                              'outer-returned))))
                     (in (in-transaction? db))
                     (depth (database-depth db)))
                (list inside w in depth))))))
    (if (not (and (list? r) (= (length r) 4) (list? (car r))))
        (list #t (list fuel 'the-case-raised r) 'no-kind)
        (let* ((inside (car r))
               (run (car inside))
               (lost (eq? run 'the-engine-was-lost))
               (expired (or lost (and (list? run) (= (length run) 2) (cadr run))))
               (answer (and (not lost) (list? run) (car run)))
               (kind (cond (lost 'lost)
                           ((equal? answer '(raised (transaction-ended with-transaction))) 'ended)
                           ((equal? answer '(raised (sqlite-error with-transaction busy busy))) 'busy)
                           (else 'no-kind)))
               (rollbacks (states-of (caddr inside) rollback-to-1))
               (releases (states-of (caddr inside) release-1))
               (whole (list kind (cadr inside) rollbacks
                            releases
                            (cadddr inside) (cadr r) (caddr r) (cadddr r)
                            (runs-of (caddr inside) rollback-to-1)))
               (expected (case kind
                           ((ended) (list 'ended 100 '(ready) '(ready) 1 'outer-returned #f 0 1))
                           ((busy) (list 'busy 5 '(ready) '() 1 'outer-returned #f 0 1))
                           ((lost) (list 'lost 5 '(ready) '() 1 'outer-returned #f 0 1))
                           (else 'no-kind))))
          (list expired (and (not (equal? whole expected)) (list fuel run whole)) kind)))))

(test-equal "a failed commit's rollback is tried once under any expiry: O7 nested, its RELEASE busy beside the body's held insert ... returning, under an engine at every fuel from 1 until it completes without expiring, resumed after each expiry: at every fuel the connection tracks one ROLLBACK TO chez_sqlite3_1, ready, never a second beside one at done or one left unstepped, and the extended code is the last step's; the call raises &sqlite-transaction-ended when the expiry's rollback came before the held step, its RELEASE kept; the commit's busy once the rollback ran; or loses the engine, Chez's no engine active, when the expiry's own RELEASE failed; the outer level stays open, depth 1, and commits"
  '()
  (named "O7 nested under an engine" (sweep o7-engine 5000)))

;; --- a statement of with-transaction's own, never left behind by an expiry --------------------
;;
;; The same O7 nested, the inner RELEASE failing beside a held insert ...
;; returning. Each of with-transaction's statements is taken from the cache,
;; stepped and given back in one critical section, so no expiry lands between
;; the three: none can be left checked out, or failed and tracked, for a later
;; with-transaction to be refused by. Read once the outer call has returned.

;; distinct-sql : (Listof (List String Symbol Integer)) -> (Listof (List String Symbol Integer))
;; STATEMENTS without a second of the same SQL.
(define (distinct-sql statements)
  (let loop ((rest statements) (seen '()))
    (cond ((null? rest) (reverse seen))
          ((member (car (car rest)) (map car seen)) (loop (cdr rest) seen))
          (else (loop (cdr rest) (cons (car rest) seen))))))

;; o7-orphan : Positive-Integer -> (List Boolean Any Symbol)
;; At FUEL: O7 nested under an engine as o7-engine runs it. Whether the first
;; slice expired; #f, or what deviated; and the kind of the engine's run,
;; lost or not. Once the outer with-transaction has returned, expected: of
;; with-transaction's own statements the connection tracks none that is not
;; ready, none twice, and every statement it tracks is in the cache, so none is
;; checked out or failed and left; depth 0; and a later with-transaction on the
;; connection commits, answering later.
(define (o7-orphan fuel)
  (let ((r (with-files
            (lambda (db db2)
              (execute! db "create table r (x)")
              (let* ((held #f)
                     (run #f)
                     (w (attempt
                         (lambda ()
                           (with-transaction db 'deferred
                             (lambda ()
                               (execute! db "insert into t values ('outer')")
                               (set! run (guard (e ((engine-lost? e) 'the-engine-was-lost)
                                                   (#t (list 'raised (what-raised e))))
                                           (engine-run
                                            (lambda ()
                                              (attempt
                                               (lambda ()
                                                 (with-transaction db
                                                   (lambda ()
                                                     (execute! db "insert into t values ('inner')")
                                                     (set! held (prepare-statement db "insert into r values (6), (7) returning x"))
                                                     (step! held)
                                                     'inner-returned)))))
                                            fuel)))
                               (when held (finalize-statement! held))
                               'outer-returned)))))
                     (own (own-statements db))
                     (left-out (list (length (not-ready own))
                                     (- (length own) (length (distinct-sql own)))
                                     (- (length (tracked-statements db)) (database-cache-count db))))
                     (depth (database-depth db))
                     (later (attempt (lambda () (with-transaction db (lambda () 'later))))))
                (list run w left-out depth later))))))
    (if (not (and (list? r) (= (length r) 5)))
        (list #t (list fuel 'the-case-raised r) 'no-kind)
        (let* ((run (car r))
               (lost (eq? run 'the-engine-was-lost))
               (expired (or lost (and (list? run) (= (length run) 2) (cadr run))))
               (whole (list (cadr r) (caddr r) (cadddr r) (car (cddddr r))))
               (expected (list 'outer-returned '(0 0 0) 0 'later)))
          (list expired (and (not (equal? whole expected)) (list fuel whole)) (if lost 'lost 'not-lost))))))

(test-equal "a statement of with-transaction's own is never left behind by an expiry: O7 nested under an engine at every fuel from 1 until it completes without expiring, resumed after each expiry: once the outer with-transaction has returned, none of with-transaction's own statements the connection tracks is not ready or tracked twice, every statement it tracks is in the cache, the depth is 0, and a later with-transaction on the connection commits"
  '()
  (named "O7 nested, nothing left behind" (sweep o7-orphan 5000)))

;; --- a body re-entered by a timer interrupt, the rollback tried once ---------------------------
;;
;; O7 nested again, with no engine: as the inner body returns, a timer
;; interrupt is set whose handler calls a continuation captured at the inner
;; body's start. That re-enters the body from inside the call's extent, no
;; wind crossed, at whichever point of the commit the tick lands. Swept over
;; the ticks. ROLLBACK TO chez_sqlite3_1, the failed commit's rollback, must
;; run at most once whatever the tick: the sections that take, step and
;; return it are what keep a re-entered body from stepping a second one
;; (the M3 slice 4 review's probe, reenter.sps).

;; rollback-runs : (Listof (List String Symbol Integer)) -> Integer
;; The runs of every tracked ROLLBACK TO chez_sqlite3_1, summed.
(define (rollback-runs statements)
  (let loop ((rest statements) (n 0))
    (cond ((null? rest) n)
          ((string=? (car (car rest)) rollback-to-1) (loop (cdr rest) (+ n (caddr (car rest)))))
          (else (loop (cdr rest) n)))))

;; reenter-case : Positive-Integer -> (List Boolean Any)
;; At TICKS: whether the handler fired, and #f or what deviated: the case's
;; raise, or the runs of ROLLBACK TO chez_sqlite3_1, when over one, with the
;; own statements.
(define (reenter-case ticks)
  (let* ((fired (vector #f))
         (old (timer-interrupt-handler))
         (r (with-files
             (lambda (db db2)
               (execute! db "create table r (x)")
               (let* ((again #f) (entries 0) (held '())
                      (w (with-transaction db 'deferred
                           (lambda ()
                             (execute! db "insert into t values ('outer')")
                             (let* ((inner (attempt
                                            (lambda ()
                                              (with-transaction db
                                                (lambda ()
                                                  (call/cc (lambda (k) (set! again k)))
                                                  (set! entries (+ entries 1))
                                                  (execute! db "insert into t values ('inner')")
                                                  (let ((h (prepare-statement db "insert into r values (6), (7) returning x")))
                                                    (set! held (cons h held))
                                                    (step! h))
                                                  (when (= entries 1)
                                                    (timer-interrupt-handler
                                                     (lambda ()
                                                       (timer-interrupt-handler old)
                                                       (vector-set! fired 0 #t)
                                                       (again #f)))
                                                    (set-timer ticks))
                                                  'inner-returned)))))
                                    (off (set-timer 0))
                                    (restored (timer-interrupt-handler old))
                                    (own (own-statements db)))
                               (for-each finalize-statement! held)
                               (list inner entries own))))))
                 w)))))
    (set-timer 0)
    (timer-interrupt-handler old)
    (list (vector-ref fired 0)
          (cond ((not (and (list? r) (= (length r) 3))) (list ticks 'the-case-raised r))
                ((> (rollback-runs (caddr r)) 1) (list ticks (rollback-runs (caddr r)) (caddr r)))
                (else #f)))))

;; reenters : -> (Listof Any)
;; Every tick count from 1 until four in a row do not fire the handler: the
;; ticks' deviations. Prints how many ticks fired it; fewer than 20 is itself
;; a deviation, the sweep having reached nothing.
(define (reenters)
  (let loop ((ticks 1) (unfired 0) (fired 0) (found '()))
    (if (or (> unfired 3) (>= ticks 2000))
        (begin
          (display "  the re-entries: the handler fired at ")
          (write fired)
          (display " of ")
          (write (- ticks 1))
          (display " ticks")
          (newline)
          (append (reverse found) (if (< fired 20) (list (list 'too-few-ticks-fired fired)) '())))
        (let ((r (reenter-case ticks)))
          (loop (+ ticks 1) (if (car r) 0 (+ unfired 1)) (if (car r) (+ fired 1) fired)
                (if (cadr r) (cons (cadr r) found) found))))))

(test-equal "a body re-entered by a timer interrupt as it returns steps ROLLBACK TO chez_sqlite3_1 at most once: O7 nested, its RELEASE busy beside the body's held insert ... returning, a timer interrupt set as the inner body returns whose handler calls a continuation captured at the body's start, at every tick count from 1 until four in a row do not fire it, and at least 20 do: the tracked ROLLBACK TO chez_sqlite3_1 statements' runs sum to at most one"
  '()
  (reenters))

;; --- a nested begin that fails ------------------------------------------------------------------

;; failed-begin-case : Positive-Integer Positive-Integer -> (List Boolean Boolean Any)
(define (failed-begin-case t1 t2)
  (let* ((fired (vector #f #f))
         (old (timer-interrupt-handler))
         (r (with-files
             (lambda (db db2)
               (let* ((held (prepare-statement db "select 1 union all select 2"))
                      (w (with-transaction db 'deferred
                           (lambda ()
                             (execute! db "insert into t values ('outer')")
                             (timer-interrupt-handler
                              (lambda ()
                                (vector-set! fired 0 #t)
                                (step! held)
                                (call-with-open-handle 'test-transaction-engine db sqlite3-interrupt)
                                (timer-interrupt-handler
                                 (lambda ()
                                   (timer-interrupt-handler old)
                                   (vector-set! fired 1 #t)
                                   (finalize-statement! held)))
                                (set-timer t2)))
                             (set-timer t1)
                             (let* ((inner (attempt (lambda () (with-transaction db (lambda () 'inner-returned)))))
                                    (off (set-timer 0))
                                    (restored (timer-interrupt-handler old))
                                    (own (own-statements db))
                                    (depth (database-depth db))
                                    (code (extended db)))
                               (guard (e (#t #f)) (finalize-statement! held))
                               (list inner own depth code))))))
                 w)))))
    (set-timer 0)
    (timer-interrupt-handler old)
    (list (vector-ref fired 0) (vector-ref fired 1) r)))

;; begin-failed? : Any -> Boolean
;; Whether R, a failed-begin-case's outcome, is a nested begin that failed
;; interrupted: the inner call raised &sqlite-error interrupt and no
;; SAVEPOINT of with-transaction's is tracked.
(define (begin-failed? r)
  (and (list? r) (= (length r) 4)
       (equal? (car r) '(raised (sqlite-error with-transaction interrupt interrupt)))
       (null? (filter (lambda (t) (prefix? "SAVEPOINT" (car t))) (cadr r)))))

;; failed-begins : -> (Listof Any)
;; failed-begin-case at every T1 from 1 until four in a row fire no
;; interrupt, and every T2 from 1 until four in a row fire no finalize,
;; both fired: the cases that deviated, a begin that failed after which
;; with-transaction tracked a ROLLBACK TO or RELEASE, or the extended code is
;; neither 0 nor 9, interrupt: a ROLLBACK TO behind no SAVEPOINT answers 1.
;; Prints how many cases failed their begin; fewer than 100 is itself a
;; deviation.
(define (failed-begins)
  (let loop ((t1 1) (u1 0) (found '()) (failed 0))
    (if (or (> u1 3) (>= t1 300))
        (begin
          (display "  the failed begins: cases that failed the nested begin: ")
          (write failed)
          (newline)
          (append (reverse found) (if (< failed 100) (list (list 'too-few-failed-begins failed)) '())))
        (let inner ((t2 1) (u2 0) (any #f) (found found) (failed failed))
          (if (or (> u2 3) (>= t2 300))
              (loop (+ t1 1) (if any 0 (+ u1 1)) found failed)
              (let* ((r (failed-begin-case t1 t2))
                     (both (and (car r) (cadr r)))
                     (o (caddr r))
                     (fb (and both (begin-failed? o)))
                     (bad (and fb
                               (or (pair? (filter (lambda (t) (not (own-sql-is-begin? (car t)))) (cadr o)))
                                   (not (member (cadddr o) '(0 9)))))))
                (inner (+ t2 1) (if (cadr r) 0 (+ u2 1)) (or any (car r))
                       (if bad (cons (list t1 t2 o) found) found)
                       (if fb (+ failed 1) failed))))))))

;; own-sql-is-begin? : String -> Boolean
(define (own-sql-is-begin? sql) (string=? sql "BEGIN DEFERRED"))

(test-equal "a nested begin that fails leaves nothing to roll back: inside an outer with-transaction, deferred, a timer interrupt at T1 ticks steps the caller's select to a row and calls sqlite3_interrupt, which stays while the select is held, and a second at T2 ticks later finalizes it, at every T1 and T2 until four in a row do not fire: in the at least 100 cases where the inner with-transaction raises &sqlite-error interrupt with no SAVEPOINT tracked, only BEGIN DEFERRED is tracked of with-transaction's statements and the extended code is 0 or 9, never the 1 of a ROLLBACK TO behind no SAVEPOINT"
  '()
  (failed-begins))

;; --- a remainder resumed while an earlier resume of it is pending ---------------------------
;;
;; At fuel F the call's first remainder R. R is resumed with fuel G until it
;; expires, as R1. Then R is resumed to its end, then R1 to its end: the
;; second resume of R's call begins while R1, its earlier one, is still
;; pending. Swept over F from 1 until the call completes unexpired, and over
;; G from 1 until R completes within G, at the outer level and nested, inside
;; an outer with-transaction whose body runs the engines (M3 slice 5's
;; schedule, the lead's probe). A flag set only when a call ends is what that
;; schedule broke. After both runs: the depth is restored, in-transaction? is
;; #f once the outer level is over, a later with-transaction commits, and
;; none of with-transaction's own statements is tracked other than ready, or
;; outside the cache. Only with-transaction's own SQL is read: the body's
;; execute! is slice 3's convenience, and in some trials R1's
;; execute! raises &sqlite-closed (its call's flag), leaving its statement
;; tracked outside the cache at ready or done (outer F=29 G=46 and G=66);
;; that is observed, and asserted neither way.

;; cached? : Database String -> Boolean
;; Whether DB's cache holds a statement under SQL, read by taking it out and
;; putting it back, inside the connection's section.
(define (cached? db sql)
  (call-with-open-handle 'test-transaction-engine db
    (lambda (handle)
      (let ((r (database-cache-check-out! db sql)))
        (when (eq? (car r) 'hit) (database-cache-return! db sql (cadr r)))
        (eq? (car r) 'hit)))))

;; own-left : Database -> (Listof Any)
;; Of with-transaction's own statements DB tracks: those not ready, those
;; tracked twice, and those whose SQL the cache does not hold.
(define (own-left db)
  (let ((own (own-statements db)))
    (append (map (lambda (s) (list 'not-ready (car s) (cadr s))) (not-ready own))
            (map (lambda (s) (list 'tracked-twice (car s)))
                 (filter (lambda (s) (> (length (filter (lambda (o) (string=? (car o) (car s))) own)) 1))
                         (distinct-sql own)))
            (map (lambda (s) (list 'outside-the-cache (car s)))
                 (filter (lambda (s) (not (cached? db (car s)))) (distinct-sql own))))))

;; pending-trial : Boolean Positive-Integer Positive-Integer
;;                 -> (U 'completed-at-f 'r-completed-at-g (Listof Any))
;; One (F, G) on a fresh in-memory database: 'completed-at-f when the call
;; completed within F, 'r-completed-at-g when R completed within G, else the
;; deviations, '() for none.
(define (pending-trial nested? f g)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let ((r (attempt
                  (lambda ()
                    (set! db (open-database ":memory:"))
                    (execute! db "create table t (x)")
                    (let* ((inside #f)
                           (run (lambda ()
                                  (let ((first ((make-engine
                                                 (lambda ()
                                                   (attempt (lambda ()
                                                              (with-transaction db
                                                                (lambda ()
                                                                  (execute! db "insert into t values (1)")
                                                                  42))))))
                                                f complete expire)))
                                    (if (pair? first)
                                        'completed-at-f
                                        (let ((second (first g complete expire)))
                                          (if (pair? second)
                                              'r-completed-at-g
                                              (let* ((a (finish first 1000000))
                                                     (b (finish second 1000000)))
                                                'ran)))))))
                           (outcome
                            (if nested?
                                (let ((w (with-transaction db 'deferred
                                           (lambda ()
                                             (let ((x (run)))
                                               (set! inside (list (database-depth db) (own-left db)))
                                               x)))))
                                  w)
                                (run))))
                      (if (memq outcome '(completed-at-f r-completed-at-g))
                          outcome
                          (let* ((depth (database-depth db))
                                 (in (in-transaction? db))
                                 (left (own-left db))
                                 (later (attempt (lambda () (with-transaction db (lambda () 'later-committed))))))
                            (append
                             (if (and nested? (not (equal? inside '(1 ())))) (list (list 'inside inside)) '())
                             (if (eqv? depth 0) '() (list (list 'depth depth)))
                             (if in (list 'in-transaction-after) '())
                             (if (eq? later 'later-committed) '() (list (list 'later later)))
                             (if (null? left) '() (list (list 'left left)))))))))))
          (cond ((symbol? r) r)
                ((and (pair? r) (eq? (car r) 'raised)) (list (list 'the-trial-raised r)))
                (else r))))
      (lambda ()
        (when db (guard (e (#t #f)) (close-database! db)))))))

;; pending-stride : Positive-Integer
;; G steps by this, from 1: under the memory gate the full sweep cost the
;; suite 100 s, for 16,420 trials, and a stride of 4 keeps every F and about
;; every fourth G, with R1 existing at each.
(define pending-stride 4)

;; pending : Boolean -> (Listof Any)
;; pending-trial at every F from 1 until the call completes unexpired, and G
;; from 1 by pending-stride until R completes within G: the (F G deviation ...) of the trials
;; that deviated. Prints the trials made, each with R1 existing; fewer than
;; 1000, or any other collapse of the sweep, is itself a
;; deviation, the sweep having reached nothing.
(define (pending nested?)
  (let floop ((f 1) (found '()) (trials 0))
    (let gloop ((g 1) (found found) (trials trials))
      (let ((r (pending-trial nested? f g)))
        (cond ((eq? r 'completed-at-f)
               (display (if nested? "  pending, nested: " "  pending, the outer level: "))
               (write trials)
               (display " trials, the call completed unexpired at fuel ")
               (write f)
               (newline)
               (append (reverse found) (if (< trials 1000) (list (list 'too-few-trials-with-r1 trials)) '())))
              ((eq? r 'r-completed-at-g)
               (if (>= f 5000) (reverse (cons 'no-completion found)) (floop (+ f 1) found trials)))
              ((>= g 1000) (floop (+ f 1) (cons (list f g 'r-never-completed) found) trials))
              (else (gloop (+ g pending-stride) (if (null? r) found (cons (cons f (cons g r)) found)) (+ trials 1))))))))

(test-equal "a remainder resumed while an earlier resume of it is pending leaves the level and its statements whole: at fuel F the call's first remainder R, resumed with fuel G until it expires as R1, then R to its end, then R1 to its end, at every F until the call completes unexpired and every G until R completes within G, at the outer level and nested in an outer with-transaction: the depth is restored, in-transaction? is #f after the outer level, a later with-transaction commits, and none of with-transaction's own statements is tracked other than ready, tracked twice, or outside the cache"
  '(() ())
  (list (pending #f) (pending #t)))

;; --- an engine taken outside the call, resumed inside a sibling -------------------------------
;;
;; Inside an outer W, an engine runs a nested level A for one slice; then
;; W's body runs a sibling B, and inside B's body resumes A to its end.
;; Chez runs B's after thunk, then its before thunk, on the resume, as for
;; any continuation taken outside B (the M3 slice 4 review's probe): B's
;; level is rolled back as the resume leaves it, and B's return raises the
;; ended condition.

;; siblings : Database Positive-Integer -> (List Any ...)
;; At FUEL: whether A's first slice expired, or its answer; A's answer once
;; resumed inside B; B's; W's; the extended code, the depth after W, the
;; markers, and the SAVEPOINTs the connection tracks.
(define (siblings db fuel)
  (let* ((a-first #f) (a-answer 'a-not-resumed) (b-answer #f)
         (w (attempt
             (lambda ()
               (with-transaction db 'deferred
                 (lambda ()
                   (execute! db "insert into t values ('w')")
                   (let ((rem ((make-engine
                                (lambda ()
                                  (attempt (lambda ()
                                             (with-transaction db
                                               (lambda () (execute! db "insert into t values ('a')") 42))))))
                               fuel complete expire)))
                     (set! a-first (if (procedure? rem) 'expired (cadr rem)))
                     (set! b-answer
                           (attempt (lambda ()
                                      (with-transaction db
                                        (lambda ()
                                          (execute! db "insert into t values ('b')")
                                          (when (procedure? rem) (set! a-answer (finish rem 1000000)))
                                          'b-returned)))))
                     'w-returned))))))
         (code (extended db))
         (depth (database-depth db))
         (rows (attempt (lambda ()
                          (let loop ((rest (query db "select x from t order by x")) (out '()))
                            (if (null? rest) (reverse out) (loop (cdr rest) (cons (vector-ref (car rest) 0) out)))))))
         (savepoints (filter (lambda (s) (prefix? "SAVEPOINT" s)) (sql-texts db))))
    (list a-first a-answer b-answer w code depth rows savepoints)))

(test-equal "an engine taken outside a call and resumed inside a sibling leaves the sibling: inside W, nested A runs one slice in an engine, then sibling B resumes A inside its body. At every fuel from 1 until A's first slice completes, B's level is rolled back as the resume leaves it, so B's return raises &sqlite-transaction-ended and B's row is gone, while A answers 42 or the ended condition; W commits; the depth is 0 after W, the extended code 0, and the only savepoint ever tracked is SAVEPOINT chez_sqlite3_1. At the completing fuel, B commits its row"
  '()
  (let loop ((fuel 1) (found '()))
    (let* ((r (with-files (lambda (db db2) (siblings db fuel))))
           (ok (and (list? r) (= (length r) 8)))
           (expired (and ok (eq? (car r) 'expired)))
           (deviation
            (cond ((not ok) (list fuel 'the-case-raised r))
                  (expired
                   (and (not (and (member (cadr r) '(42 (raised (transaction-ended with-transaction))))
                                  (member (list-ref r 6) '(("a" "w") ("w")))
                                  (equal? (cddr r) (list '(raised (transaction-ended with-transaction)) 'w-returned 0 0
                                                         (list-ref r 6) '("SAVEPOINT chez_sqlite3_1")))))
                        (list fuel r)))
                  (else
                   (and (not (equal? r '(42 a-not-resumed b-returned w-returned 0 0 ("a" "b" "w")
                                         ("SAVEPOINT chez_sqlite3_1"))))
                        (list fuel r)))))
           (found* (if deviation (cons deviation found) found)))
      (cond ((and ok (not expired))
             (display "  the siblings: A's first slice expired at fuels 1 to ")
             (write (- fuel 1))
             (display ", and completed at fuel ")
             (write fuel)
             (newline)
             (if (> fuel 2) (reverse found*) (cons 'too-few-expiring-fuels (reverse found*))))
            ((or (not ok) (>= fuel 5000)) (cons 'no-completion (reverse found*)))
            (else (loop (+ fuel 1) found*))))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "transaction-engine")

(exit (suite-exit-status runner))
