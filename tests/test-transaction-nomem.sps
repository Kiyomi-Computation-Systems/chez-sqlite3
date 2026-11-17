#!r6rs
;;; with-transaction beside a real NOMEM (ADR-0017; the M3 plan, section 5
;;; item 4), in a process of its own: the heap limit is process-wide.
;;;
;;; The suite binds sqlite3_hard_heap_limit64 and sqlite3_soft_heap_limit64
;;; itself, after the load, and sets the hard limit to sqlite3_memory_used
;;; plus 1,000 bytes around exactly one call, a step! or a column-value of the
;;; statement tier, inside with-transaction's body. It reads the limit
;;; straight after the call, which must be the one set, a check that fails
;;; only if the call itself lifted the limit; each row asserts what this
;;; method measured. Then it lifts both limits, the hard then the soft,
;;; however the call ends: the hard limit's lift alone leaves SQLite's memory
;;; pressure on for the process, and a second connection's read beside a
;;; later write transaction answered BUSY (M3 slice 4's groundwork). Both
;;; limits read 0 after every row, and at the end, but that check can't tell
;;; the hard lift alone: sqlite3_hard_heap_limit64(0) zeroes the soft limit
;;; too. Only the peer row holds the soft lift.
;;;
;;;   S1 to S4   a step!: a SELECT reading a table, one reading none, a
;;;              multi-row INSERT ... SELECT, a one-row INSERT. S3's case is
;;;              the build's: its NOMEM ended the transaction at the floor,
;;;              with Guix's 3.53.1 and CI's 3.54.1, and left it open in a
;;;              build with -DSQLITE_ENABLE_MEMORY_MANAGEMENT, Homebrew's among
;;;              them (.plans/research/m3-mac/). So S3 takes the case its
;;;              body's autocommit shows, and holds with-transaction's exit to
;;;              that case, whole
;;;   R1 to R4   a column-value of 100,000 bound bytes, by a SELECT reading a
;;;              table or none, then reset! or finalize-statement!
;;;   R1u        R1's statement left failed through with-transaction's exit
;;;   [F]        with-transaction refused beside a statement a column read's
;;;              NOMEM failed: its irritants, the state and the SQL
;;;   the peer   after them, a second connection reads beside a write
;;;              transaction that has read a table, and gets its row
;;;
;;; Each at the outer level and nested. The body records what the call
;;; raised, autocommit straight after, the finish and autocommit after it,
;;; and raises the call's condition past with-transaction. Then
;;; with-transaction's exit: what it raised, in-transaction?, the markers as
;;; this connection and a second one see them, and the statements it issued.
;;;
;;; Where SQLite keeps no memory count, as on a build with
;;; SQLITE_DEFAULT_MEMSTATUS=0 like Apple's, the limit is kept but not
;;; enforced, so each row prints UNAVAILABLE and is skipped, never passed.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. Effects run in order, through let* and named lets (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) foreign-procedure)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) sqlite-error? sqlite-error-code sqlite-error-extended-code
              sqlite-closed? sqlite-transaction-ended?))

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
(define native-library '(chez-sqlite3 private native))
(define with-transaction (reach public 'with-transaction))
(define open-database (reach public 'open-database))
(define close-database! (reach public 'close-database!))
(define execute! (reach public 'execute!))
(define query-row (reach public 'query-row))
(define in-transaction? (reach public 'in-transaction?))
(define prepare-statement (reach public 'prepare-statement))
(define finalize-statement! (reach public 'finalize-statement!))
(define step! (reach public 'step!))
(define reset! (reach public 'reset!))
(define bind! (reach public 'bind!))
(define column-value (reach public 'column-value))
(define statement-sql (reach public 'statement-sql))
(define statement-state (reach '(chez-sqlite3 private statement) 'statement-state))
(define tracked-statements (reach '(chez-sqlite3 private connection) 'tracked-statements))
(define call-with-open-handle (reach '(chez-sqlite3 private connection) 'call-with-open-handle))
(define sqlite3-memory-used (reach native-library 'sqlite3-memory-used))
(define sqlite3-get-autocommit (reach native-library 'sqlite3-get-autocommit))
(define sqlite3-extended-errcode (reach native-library 'sqlite3-extended-errcode))

;; --- bound here, after the load --------------------------------------------------------

(define-syntax bound
  (syntax-rules ()
    ((_ name form)
     (guard (e (#t (lambda args (error name "this suite could not bind it" (describe e)))))
       form))))

;; sqlite3_int64 sqlite3_hard_heap_limit64(sqlite3_int64 N): the limit
;; before; a negative N reads it, and 0 means no limit.
(define hard-limit (bound 'sqlite3_hard_heap_limit64
                          (foreign-procedure "sqlite3_hard_heap_limit64" (integer-64) integer-64)))
;; sqlite3_int64 sqlite3_soft_heap_limit64(sqlite3_int64 N): the same, soft.
(define soft-limit (bound 'sqlite3_soft_heap_limit64
                          (foreign-procedure "sqlite3_soft_heap_limit64" (integer-64) integer-64)))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

(define (what-raised e)
  (cond ((sqlite-transaction-ended? e) (list 'transaction-ended (who-of e)))
        ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)))
        ((sqlite-closed? e) (list 'closed (who-of e)))
        ((assertion-violation? e)
         (list 'assertion-violation (who-of e)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        ((condition? e) (list 'other (describe e)))
        (else (list 'value e))))

(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define void-value (if #f #f))
(define (no-value x) (if (eq? x void-value) 'no-value x))

(define (with-handle db proc) (call-with-open-handle 'test-transaction-nomem db proc))
(define (autocommit db) (with-handle db sqlite3-get-autocommit))
(define (extended db) (with-handle db sqlite3-extended-errcode))

(define (limits) (list 'hard (hard-limit -1) 'soft (soft-limit -1)))

(define (prefix? p s) (and (<= (string-length p) (string-length s))
                           (string=? p (substring s 0 (string-length p)))))
(define (own-sql? s)
  (or (member s '("BEGIN DEFERRED" "BEGIN IMMEDIATE" "BEGIN EXCLUSIVE" "COMMIT" "ROLLBACK"))
      (prefix? "SAVEPOINT chez_sqlite3_" s) (prefix? "RELEASE chez_sqlite3_" s)
      (prefix? "ROLLBACK TO chez_sqlite3_" s)))
(define (issued db)
  (let loop ((rest (tracked-statements db)) (found '()))
    (if (null? rest)
        (reverse found)
        (let ((sql (statement-sql (car rest))))
          (loop (cdr rest)
                (if (own-sql? sql) (cons (cons sql (statement-state (car rest))) found) found))))))

(define (markers db)
  (attempt (lambda ()
             (vector-ref (query-row db "select coalesce(group_concat(x, ','), '(none)') from (select x from t order by x)")
                         0))))

(define big-text (make-string 100000 #\a))

;; around-one-call : (-> Any) -> (List Any Symbol)
;; THUNK's answer, or what it raised, run with the hard heap limit at the
;; memory SQLite uses now plus 1,000; and whether the limit read straight
;; after THUNK is the one set. Both limits lifted after, hard then soft,
;; however THUNK ends.
(define (around-one-call thunk)
  (let ((target #f) (kept #f))
    (let ((r (dynamic-wind
               (lambda () (set! target (+ (sqlite3-memory-used) 1000)) (hard-limit target))
               (lambda ()
                 (let ((v (guard (e (#t (list 'raised-object e))) (no-value (thunk)))))
                   (set! kept (hard-limit -1))
                   v))
               (lambda () (hard-limit 0) (soft-limit 0)))))
      (list r (if (eqv? kept target) 'the-limit-in-force-when-the-call-returned 'the-limit-changed)))))

(define temp-dir (guard (e (#t #f)) (make-process-temp-directory)))
(define case-number 0)
(define (fresh-path)
  (set! case-number (+ case-number 1))
  (string-append (or temp-dir "/nonexistent") "/case-" (number->string case-number) ".db"))

;; with-case : (Database Database -> Any) -> Any
;; Two connections to a fresh file holding t, b, and src, ten rows of 3,000
;; bytes; both closed after.
(define (with-case proc)
  (let ((db #f) (db2 #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt (lambda ()
                   (let ((path (fresh-path)))
                     (set! db (open-database path))
                     (execute! db "create table t (x)")
                     (execute! db "create table b (x)")
                     (execute! db "create table src (x)")
                     (execute! db "insert into src select replace(hex(zeroblob(1500)), '0', 'a') from (with recursive n(i) as (select 1 union all select i + 1 from n where i < 10) select i from n)")
                     (set! db2 (open-database path))
                     (proc db db2)))))
      (lambda ()
        (when db2 (guard (e (#t #f)) (close-database! db2)))
        (when db (guard (e (#t #f)) (close-database! db)))))))

;; the-call : Database Symbol String Symbol -> (List Any ...)
;; The body's work: SQL prepared; for a read, KIND read, the 100,000 bytes
;; bound and the statement stepped to its row; then the one call under the
;; limit, step! or column-value; then the statement finished by FINISH,
;; reset!, finalize-statement!, or none, left failed. What the call raised,
;; whether the limit stayed in force, the limits after, the state,
;; autocommit straight after, the finish's answer and autocommit after it,
;; and the call's condition, to raise, and the statement when left.
(define (the-call db kind sql finish)
  (let* ((st (prepare-statement db sql))
         (prepared (when (eq? kind 'read)
                     (bind! st 1 big-text)
                     (step! st)))
         (call (around-one-call (lambda () (if (eq? kind 'read) (column-value st 0) (step! st)))))
         (raised (and (pair? (car call)) (eq? (car (car call)) 'raised-object) (cadr (car call))))
         (lifted (limits))
         (state (statement-state st))
         (a1 (autocommit db))
         (f (case finish
              ((reset!) (no-value (attempt (lambda () (reset! st)))))
              ((finalize-statement!) (no-value (attempt (lambda () (finalize-statement! st)))))
              (else 'left)))
         (a2 (autocommit db)))
    (when (eq? finish 'reset!) (finalize-statement! st))
    (list (list (if raised (what-raised raised) (car call)) (cadr call) lifted state a1 f a2)
          raised
          (and (eq? finish 'left) st))))

;; nomem-row : Symbol String Symbol Boolean -> Any
;; The call inside with-transaction, deferred, after a marker; NESTED,
;; inside an inner with-transaction after a second marker, whose raise the
;; outer body catches before it returns. The body raises the call's
;; condition. What the body recorded; what with-transaction raised, the
;; inner's and the outer's when nested; in-transaction?; the markers on DB
;; and DB2; the statements with-transaction issued; and, for a statement
;; left failed, the extended code after its later finalize.
(define (nomem-row kind sql finish nested)
  (with-case
   (lambda (db db2)
     (let* ((recorded #f) (left #f) (inner 'not-nested)
            (body (lambda ()
                    (let ((c (the-call db kind sql finish)))
                      (set! recorded (car c))
                      (set! left (caddr c))
                      (raise (or (cadr c) 'the-call-raised-nothing)))))
            (r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda ()
                              (execute! db "insert into t values ('outer')")
                              (if nested
                                  (begin
                                    (set! inner (attempt (lambda ()
                                                           (with-transaction db
                                                             (lambda ()
                                                               (execute! db "insert into t values ('inner')")
                                                               (body))))))
                                    'outer-returned)
                                  (body)))))))
            (in (if (in-transaction? db) 'yes 'no))
            (mine (markers db))
            (theirs (markers db2))
            (own (issued db))
            (later (if left
                       (let ((f (no-value (attempt (lambda () (finalize-statement! left))))))
                         (list f (extended db)))
                       'finished-in-the-body)))
       (list recorded inner r in mine theirs own later (limits))))))

;; --- whether the limit is enforced here -------------------------------------------------------

(define memory-kept
  (guard (e (#t (list 'raised (describe e))))
    (let* ((db (open-database ":memory:"))
           (used (sqlite3-memory-used)))
      (close-database! db)
      (> used 0))))

;; control-kept : Any
;; What the memory check's own control says of this library: the check
;; native registered with the counters at the load, run here, whose
;; :memory: open and close is its positive control (ADR-0005, amended).
;; kept when the count rose while that connection was open, its verdict
;; pass or fail; not-kept when it did not, unavailable; else what it
;; answered, or raised. memory-kept decides which rows run, so it answers
;; to this, which the memory gate's own rows hold.
(define control-kept
  (guard (e (#t (list 'raised (describe e))))
    (let ((check (assq 'sqlite3_memory_used (exit-checks))))
      (if (not check)
          'no-memory-check-registered
          (let ((verdict ((cdr check))))
            (case (car verdict)
              ((unavailable) 'not-kept)
              ((pass fail) 'kept)
              (else (list 'no-verdict verdict))))))))

(define (available! name)
  (when (eq? memory-kept #f)
    (display "UNAVAILABLE ")
    (display name)
    (display ": this libsqlite3 keeps no memory count, so a hard heap limit is not enforced")
    (newline)
    (test-skip name)))

(define nomem-step '(sqlite-error step! nomem nomem))
(define nomem-read '(sqlite-error column-value nomem nomem))
(define kept 'the-limit-in-force-when-the-call-returned)
(define lifted '(hard 0 soft 0))

;; expected : ... -> Any
;; A row's whole outcome. ENDED: autocommit 1 at the exit, nothing issued
;; and the markers gone; else rolled back, ROLLBACK or ROLLBACK TO and
;; RELEASE kept, and nested, the outer committed by its own return.
(define (expected recorded ended nested later)
  (let ((nomem (list 'raised (car recorded))))
    (cond ((and ended (not nested))
           (list recorded 'not-nested nomem 'no "(none)" "(none)" '(("BEGIN DEFERRED" . ready)) later lifted))
          ((not nested)
           (list recorded 'not-nested nomem 'no "(none)" "(none)" '(("BEGIN DEFERRED" . ready) ("ROLLBACK" . ready))
                 later lifted))
          (ended
           (list recorded nomem '(raised (transaction-ended with-transaction)) 'no "(none)" "(none)"
                 '(("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready)) later lifted))
          (else
           (list recorded nomem 'outer-returned 'no "outer" "outer"
                 '(("BEGIN DEFERRED" . ready) ("SAVEPOINT chez_sqlite3_1" . ready)
                   ("ROLLBACK TO chez_sqlite3_1" . ready) ("RELEASE chez_sqlite3_1" . ready)
                   ("COMMIT" . ready))
                 later lifted)))))

;; rows : (Listof (List String Symbol String Symbol (List Any ...) (U Boolean 'either)))
;; NAME, KIND, SQL, FINISH, what the body records, and whether the
;; transaction has ended by the exit; or, for S3, either, and the two
;; records, the ended case's then the open case's.
(define rows
  (list (list "S1" 'step "select randomblob(100000) from src limit 1" 'finalize-statement!
              (list nomem-step kept lifted 'failed 1 'no-value 1) #t)
        (list "S2" 'step "select randomblob(100000)" 'finalize-statement!
              (list nomem-step kept lifted 'failed 0 'no-value 0) #f)
        (list "S3" 'step "insert into b select randomblob(100000) from src limit 3" 'finalize-statement!
              (list (list nomem-step kept lifted 'failed 1 'no-value 1)
                    (list nomem-step kept lifted 'failed 0 'no-value 0))
              'either)
        (list "S4" 'step "insert into b values (randomblob(100000))" 'finalize-statement!
              (list nomem-step kept lifted 'failed 1 'no-value 1) #t)
        (list "R1" 'read "select ?1 from src limit 1" 'reset!
              (list nomem-read kept lifted 'failed 0 'no-value 1) #t)
        (list "R2" 'read "select ?1 from src limit 1" 'finalize-statement!
              (list nomem-read kept lifted 'failed 0 'no-value 1) #t)
        (list "R3" 'read "select ?1" 'reset!
              (list nomem-read kept lifted 'failed 0 'no-value 0) #f)
        (list "R4" 'read "select ?1" 'finalize-statement!
              (list nomem-read kept lifted 'failed 0 'no-value 0) #f)))

;; either-case : Any (List Any ...) (List Any ...) Boolean String -> Any
;; For a row whose case is the build's: its outcome A, compared whole with
;; each case's. ENDED-RECORD is the body's record when the NOMEM ended the
;; transaction, autocommit 1 straight after the call and after the finish;
;; OPEN-RECORD when it left it open, 0 and 0. Prints which case LABEL met,
;; and answers as-its-record-shows; else A, with both cases' outcomes.
(define (either-case a ended-record open-record nested label)
  (let ((as-ended (expected ended-record #t nested 'finished-in-the-body))
        (as-open (expected open-record #f nested 'finished-in-the-body)))
    (cond ((equal? a as-ended)
           (display "    ")
           (display label)
           (display ": the NOMEM ended the transaction")
           (newline)
           'as-its-record-shows)
          ((equal? a as-open)
           (display "    ")
           (display label)
           (display ": the NOMEM left the transaction open")
           (newline)
           'as-its-record-shows)
          (else (list a 'neither 'ended as-ended 'open as-open)))))

(test-begin "transaction-nomem")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-assert "the memory probe answers #t or #f, and does not raise"
  (boolean? memory-kept))

(test-equal "the memory probe agrees with the memory check's own control: the rows run, the heap limit taken as kept, exactly where the control's :memory: open raised SQLite's count, and are skipped as UNAVAILABLE exactly where it did not"
  control-kept
  (cond ((eq? memory-kept #t) 'kept) ((eq? memory-kept #f) 'not-kept) (else (list 'neither memory-kept))))

(test-assert "a temporary directory for the suite's databases"
  (string? temp-dir))

(test-equal "both limits read 0 before any row"
  lifted
  (guard (e (#t (list 'raised (describe e)))) (limits)))

;; one row per case and level, each named
(for-each
 (lambda (row)
   (for-each
    (lambda (nested)
      (let* ((label (string-append (car row) (if nested ", nested" ", outer")))
             (name (string-append label
                                  ": " (symbol->string (cadr row)) " of " (caddr row)
                                  " under the heap limit, then " (symbol->string (cadddr row))
                                  (case (list-ref row 5)
                                    ((either)
                                     ": the transaction has ended, so with-transaction issues nothing, or is open, so with-transaction rolls the level back, as the body's autocommit shows")
                                    ((#t)
                                     ": the transaction has ended, so with-transaction issues nothing")
                                    (else
                                     ": the transaction is open, so with-transaction rolls the level back"))
                                  "; the body's NOMEM reaches the caller; both limits read 0 after")))
        (available! name)
        (if (eq? (list-ref row 5) 'either)
            (test-equal name
              'as-its-record-shows
              (either-case (nomem-row (cadr row) (caddr row) (cadddr row) nested)
                           (car (list-ref row 4)) (cadr (list-ref row 4)) nested label))
            (test-equal name
              (expected (list-ref row 4) (list-ref row 5) nested 'finished-in-the-body)
              (nomem-row (cadr row) (caddr row) (cadddr row) nested)))))
    '(#f #t)))
 rows)

(define r1u-name "R1u: R1's statement left failed through with-transaction's exit: the read's NOMEM left autocommit 0, so with-transaction rolls back beside it, ROLLBACK, or ROLLBACK TO and RELEASE, each kept; the statement's later finalize raises nothing, and leaves the extended code nomem")
(available! r1u-name)
(test-equal r1u-name
  (list (expected (list nomem-read kept lifted 'failed 0 'left 0) #f #f '(no-value 7))
        (expected (list nomem-read kept lifted 'failed 0 'left 0) #f #t '(no-value 7)))
  (let* ((outer (nomem-row 'read "select ?1 from src limit 1" 'left #f))
         (nested (nomem-row 'read "select ?1 from src limit 1" 'left #t)))
    (list outer nested)))

(define refusal-name "[F] beside a statement a column read's NOMEM failed, with-transaction refuses to begin: an assertion violation from with-transaction, statement-not-finished, failed and the statement's own SQL, raised before anything reaches C; the body never runs, and the extended code and in-transaction? stay as the read left them")
(available! refusal-name)
(test-equal refusal-name
  (list (list nomem-read kept 'failed)
        '(raised (assertion-violation with-transaction (statement-not-finished failed "select ?1 from src limit 1")))
        'not-run 'extended-code-unchanged 'in-transaction-unchanged "(none)" 'no-value lifted)
  (with-case
   (lambda (db db2)
     (let* ((st (prepare-statement db "select ?1 from src limit 1"))
            (bound (bind! st 1 big-text))
            (stepped (step! st))
            (call (around-one-call (lambda () (column-value st 0))))
            (read (list (if (and (pair? (car call)) (eq? (car (car call)) 'raised-object))
                            (what-raised (cadr (car call)))
                            (car call))
                        (cadr call)
                        (statement-state st)))
            (code-before (extended db))
            (in-before (in-transaction? db))
            (ran 'not-run)
            (r (attempt (lambda ()
                          (with-transaction db 'deferred
                            (lambda () (set! ran 'ran) (execute! db "insert into t values ('outer')") 'committed)))))
            (code-after (extended db))
            (in-after (in-transaction? db))
            (theirs (markers db2))
            (finished (no-value (attempt (lambda () (finalize-statement! st))))))
       (list read r ran
             (if (eqv? code-before code-after) 'extended-code-unchanged (list code-before code-after))
             (if (eq? in-before in-after) 'in-transaction-unchanged (list in-before in-after))
             theirs finished (limits))))))

(define peer-name "after the NOMEM rows, inside with-transaction, immediate, a write and a read of src, a second connection's read beside it answers its row, not busy: the rig's lift, the hard then the soft, left no memory pressure behind")
(available! peer-name)
(test-equal peer-name
  '((10 0) no)
  (with-case
   (lambda (db db2)
     (let* ((r (attempt (lambda ()
                          (with-transaction db 'immediate
                            (lambda ()
                              (execute! db "insert into t values ('written')")
                              (let* ((n (vector-ref (query-row db "select count(*) from src") 0))
                                     (peer (attempt (lambda () (vector-ref (query-row db2 "select count(*) from t") 0)))))
                                (list n peer)))))))
            (in (if (in-transaction? db) 'yes 'no)))
       (list r in)))))

(test-equal "both limits read 0, and every count is zero, at the end"
  (list lifted zero-counts)
  (list (guard (e (#t (list 'raised (describe e)))) (limits)) (native-counts)))

(test-end "transaction-nomem")

(exit (suite-exit-status runner))
