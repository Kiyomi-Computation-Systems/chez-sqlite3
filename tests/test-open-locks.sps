#!r6rs
;;; The suite for the settings list under another connection's lock (ADR-0018
;;; and its consequences), through open-database and call-with-database. Each
;;; row has two connections on a file: the holder, which takes a lock, and the
;;; open, a fresh connection that holds no read of its own. busy-timeout runs
;;; first wherever the list puts it.
;;;
;;;   waits        rollback journal, under another's exclusive lock:
;;;                journal-mode, wal or delete, waits out a busy timeout of
;;;                1500 ms, at least 1000 and under 3000, or 2000 on a
;;;                whole-second build, once, then raises
;;;                &sqlite-busy naming its SQL; under a read, journal-mode
;;;                wal does. Each leaves
;;;                nothing counted: the connection is closed
;;;   the order    under the exclusive lock, with no busy timeout,
;;;                journal-mode and synchronous each answer busy at once, so
;;;                the first of them in the list names the failure, through
;;;                both verbs, in the list's order and its reverse
;;;   at once      under the exclusive lock, foreign-keys, temp-store,
;;;                trusted-schema and busy-timeout alone open at once and
;;;                read back; under a read, and under a reserved lock, every
;;;                setting but journal-mode wal
;;;   refused at   with the 1500 ms timeout set: journal-mode wal under
;;;   once         another's reserved lock; leaving WAL, delete or truncate,
;;;                while another connection that has read the file is open,
;;;                idle. One opened and never used does not count, and once
;;;                the other has closed, the same open succeeds
;;;   mid-wait     the holder, on a thread of its own, lets go 500 ms after
;;;                the open begins: the open succeeds after the release and
;;;                before its timeout's end, under an exclusive lock and under
;;;                a read
;;;   WAL on WAL   on a file already in WAL, journal-mode wal opens at once
;;;                and reads back wal, beside another that is idle, reading,
;;;                or in BEGIN IMMEDIATE or BEGIN EXCLUSIVE with a write
;;;
;;; test-open-settings holds the cases it already had, which this suite does
;;; not repeat: under an exclusive lock, synchronous with busy-timeout listed
;;; last waits, and with none answers busy at once; journal-mode wal under a
;;; reserved lock, with no busy timeout, answers busy at once.
;;;
;;; A wait is told from none by 1000 ms, and from a retry by twice what one
;;; wait takes. Each timed open's busy timeout is 1500 ms. A build that
;;; sleeps in milliseconds waits 1500 of it, and a retry in Scheme 3000; one
;;; without nanosleep sleeps whole seconds, so waits 1000 of it, and a retry
;;; 2000 (ADR-0019, no retry in Scheme). So the suite reads the build's grain
;;; first, as test-contention's probe P4 row does: a 250 ms busy timeout
;;; answers busy after about 250 ms on the first, and at once on the second. A
;;; wait is too long from 3000 ms on the first, and from 2000 on the second.
;;; Each timed case prints its milliseconds, for a reader of the run. File
;;; descriptors are read only once the holder has closed: SQLite's unix VFS
;;; keeps a closed connection's descriptor while another connection of the
;;; process holds a POSIX lock on the file.
;;;
;;; A holder on a thread of its own answers whatever it raises, and every wait
;;; for it is bounded. The loading procedures are reached through eval, under
;;; a guard, as tests/test-open-settings.sps reaches them. SQLite's answers
;;; here were measured on 3.53.1 and 3.45.1 alike before a row asserts them.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) directory-list real-time fork-thread thread-join make-mutex
              with-mutex make-condition condition-wait condition-broadcast make-time
              current-time time-difference add-duration time>=? sleep)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-error-sql sqlite-busy? sqlite-closed?))

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
(define prepare-statement (public 'prepare-statement))
(define step! (public 'step!))
(define finalize-statement! (public 'finalize-statement!))
(define in-transaction? (public 'in-transaction?))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
;; E as the rows compare it: an &sqlite-error by its who, codes and SQL, and
;; whether &sqlite-busy holds; &sqlite-closed by its who; an assertion
;; violation by its who and irritants.
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (sqlite-error-sql e) (if (sqlite-busy? e) 'sqlite-busy 'not-sqlite-busy)))
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

(define (busy who sql) (list 'raised (list 'sqlite-error who 'busy 'busy sql 'sqlite-busy)))

(define (in-dir proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory proc)))

;; descriptors : -> (U Natural (List 'unreadable String))
;; How many file descriptors this process has open, read from /dev/fd,
;; which Linux and macOS both have.
(define (descriptors)
  (guard (e (#t (list 'unreadable (describe e))))
    (length (directory-list "/dev/fd"))))

;; pragma : Database String -> Any
;; The first column of PRAGMA NAME's row on DB, by query-row.
(define (pragma db name)
  (let ((row (query-row db (string-append "PRAGMA " name))))
    (if (vector? row) (vector-ref row 0) (list 'no-row row))))

;; file-in : String String Symbol -> String
;; DIR/NAME, made fresh in journal mode MODE, delete or wal, holding t with
;; three rows, its connection closed. WAL stays in the file.
(define (file-in dir name mode)
  (let* ((path (string-append dir "/" name))
         (db (open-database path (list (cons 'journal-mode mode)))))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (execute! db "create table t (x)")
        (execute! db "insert into t values (1), (2), (3)"))
      (lambda () (close-answer db)))
    path))

;; hold! : Database Symbol -> (U Statement #f)
;; LOCK taken on DB, a connection to a file holding t: unused, nothing, DB
;; never having touched the file; idle, a read run to its end, so DB has read
;; the file and holds nothing; read, BEGIN and a SELECT stepped to its row,
;; the statement answered; reserved, BEGIN IMMEDIATE and an INSERT;
;; exclusive, BEGIN EXCLUSIVE and an INSERT.
(define (hold! db lock)
  (case lock
    ((unused) #f)
    ((idle) (query-row db "select count(*) from t") #f)
    ((read)
     (execute! db "begin")
     (let ((st (prepare-statement db "select x from t")))
       (step! st)
       st))
    ((reserved) (execute! db "begin immediate") (execute! db "insert into t values (9)") #f)
    ((exclusive) (execute! db "begin exclusive") (execute! db "insert into t values (9)") #f)
    (else (error 'hold! "no such lock" lock))))

;; let-go! : Database (U Statement #f) -> Void
;; What hold! took on DB let go: its statement finalized, its transaction
;; rolled back.
(define (let-go! db st)
  (when st (finalize-statement! st))
  (when (in-transaction? db) (execute! db "rollback")))

;; grain-ms : -> Any
;; The milliseconds a BEGIN IMMEDIATE with a 250 ms busy timeout takes to
;; answer busy, under another connection's reserved lock on a fresh file,
;; both on this thread: about 250 where the build sleeps in milliseconds, 0
;; where it sleeps whole seconds, whose first sleep would pass the timeout.
;; Else what it answered, or raised.
(define (grain-ms)
  (in-dir
   (lambda (dir)
     (let* ((path (file-in dir "grain.db" 'delete))
            (holder (open-database path)))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (hold! holder 'reserved)
           (let ((waiter (open-database path '((busy-timeout . 250)))))
             (dynamic-wind
               (lambda () #f)
               (lambda ()
                 (let* ((t0 (real-time))
                        (r (attempt (lambda () (execute! waiter "begin immediate"))))
                        (t1 (real-time)))
                   (if (equal? r (busy 'execute! "begin immediate")) (- t1 t0) (list 'not-busy r))))
               (lambda () (close-answer waiter)))))
         (lambda ()
           (guard (e (#t #f)) (let-go! holder #f))
           (close-answer holder)))))))

;; grain : (U 'milliseconds 'whole-seconds (List 'unread Any))
;; The build's busy-wait grain, read once, before any row: milliseconds from
;; 125 ms, half the timeout, as test-contention's probe P4 row tells them
;; apart.
(define grain
  (let ((ms (guard (e (#t (list 'raised (describe e)))) (grain-ms))))
    (cond ((not (integer? ms)) (list 'unread ms))
          ((>= ms 125) 'milliseconds)
          (else 'whole-seconds))))

;; retry-ms : Natural
;; Where a timed open's wait is too long: a retry of its 1500 ms busy
;; timeout waits at least 2000 ms on a whole-second build, and 3000 on any
;; other; an unread grain takes the looser bound, and its row fails.
(define retry-ms (if (eq? grain 'whole-seconds) 2000 3000))

;; how-long : Natural -> Symbol
;; MS as waited, at least 1000 and under retry-ms; too-long, from retry-ms;
;; or at-once. Every timed open's busy timeout is 1500 ms: one wait takes
;; 1500 ms of it on a build that sleeps in milliseconds and 1000 on one
;; that sleeps whole seconds, and a retry in Scheme waits it out twice.
(define (how-long ms) (cond ((>= ms retry-ms) 'too-long) ((>= ms 1000) 'waited) (else 'at-once)))

;; note-time! : String Natural -> Void
;; A timed case's milliseconds, printed for a reader of the run.
(define (note-time! label ms)
  (display "    timed: ")
  (display label)
  (display ": ")
  (display ms)
  (display " ms")
  (newline))

;; opened : (-> Any) (Database -> Any) -> (List Any Natural Natural)
;; What OPEN answered, and the real time, in milliseconds, when it began and
;; when it returned: a database it answered given to READ after that, then
;; closed, as (opened V), V what READ answered or raised; else what OPEN
;; answered, or what it raised, by attempt.
(define (opened open read)
  (let* ((t0 (real-time))
         (r (attempt open))
         (t1 (real-time)))
    (if (a-database? r)
        (let ((v (attempt (lambda () (read r)))))
          (close-answer r)
          (list (list 'opened v) t0 t1))
        (list r t0 t1))))

;; took : (List Any Natural Natural) -> Natural
;; The milliseconds an open opened timed took.
(define (took r) (- (caddr r) (cadr r)))

;; under : String String Symbol (-> Any) (Database -> Any) -> (List Any Symbol Any)
;; OPEN run, by opened, while a holder, a connection to PATH, holds LOCK:
;; what it answered, its time as how-long says it, and nothing-left when the
;; counts after it are those before it, the holder's alone. The holder is
;; let go and closed after, however OPEN ends. LABEL names the time printed.
(define (under label path lock open read)
  (let ((holder (open-database path)) (st #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (set! st (hold! holder lock))
        (let* ((before (native-counts))
               (r (opened open read))
               (after (native-counts)))
          (note-time! label (took r))
          (list (car r) (how-long (took r))
                (if (equal? before after) 'nothing-left (list 'counts before after)))))
      (lambda ()
        (guard (e (#t #f)) (let-go! holder st))
        (close-answer holder)))))

;; settled : (List Any ...) Any -> (List Any ... Any Symbol)
;; RESULTS with the counts, and whether the descriptors are BEFORE's, read
;; once every holder has closed.
(define (settled results before)
  (let* ((counts (native-counts))
         (after (descriptors)))
    (append results
            (list counts (if (equal? after before) 'descriptors-back (list 'descriptors before after))))))

(define (no-read db) 'not-read)

;; --- a holder on a thread of its own --------------------------------------------------------

;; duration : Natural -> Time
;; MS milliseconds as a time-duration, its nanoseconds below 10^9.
(define (duration ms)
  (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000)))

;; await : Mutex Condition (-> Boolean) Natural -> Boolean
;; With MUTEX held: wait on CONDITION until READY? holds, #t, or MS
;; milliseconds have passed, #f. Every wait is bounded by the deadline.
(define (await mutex condition ready? ms)
  (let ((deadline (add-duration (current-time 'time-monotonic) (duration ms))))
    (let loop ()
      (let ((now (current-time 'time-monotonic)))
        (cond ((ready?) #t)
              ((time>=? now deadline) #f)
              (else (condition-wait condition mutex (time-difference deadline now))
                    (loop)))))))

;; start-thread : (-> Any) -> (Natural -> Any)
;; THUNK run on a thread of its own. Its answer, or (raised TEXT) for what it
;; raised, is the thread's answer. Answers a procedure that waits up to MS
;; milliseconds for that answer, joins the thread once it has answered and
;; answers it, or answers unfinished, joining nothing.
(define (start-thread thunk)
  (let* ((m (make-mutex))
         (c (make-condition))
         (done #f)
         (answer 'unfinished)
         (thread (fork-thread
                  (lambda ()
                    (let ((a (guard (e (#t (list 'raised (describe e)))) (thunk))))
                      (with-mutex m
                        (set! answer a)
                        (set! done #t)
                        (condition-broadcast c)))))))
    (lambda (ms)
      (if (with-mutex m (await m c (lambda () done) ms))
          (begin (thread-join thread) (with-mutex m answer))
          'unfinished))))

;; The holder lets go this long after it is told the open has begun; the
;; other waits elapse only when something is wrong.
(define release-ms 500)
(define long-ms 5000)
(define answer-ms 15000)

;; released-mid-wait : String String Symbol (-> Any) (Database -> Any)
;;                     -> (List Any Symbol Symbol Any)
;; A holder on a thread of its own opens PATH, takes LOCK, and says so. This
;; thread then tells it the open begins, and runs OPEN, by opened. The
;; holder, told, sleeps release-ms, notes the time, then lets go and closes.
;; What OPEN answered; whether it returned after the time the holder noted;
;; whether it returned within 1500 ms of its start, before its timeout's
;; end; and the holder's answer, let-go. Every wait is bounded. LABEL names
;; the time printed.
(define (released-mid-wait label path lock open read)
  (let* ((m (make-mutex))
         (c (make-condition))
         (held #f)
         (begun #f)
         (released-at #f)
         (holder
          (start-thread
           (lambda ()
             (let ((db (open-database path)) (st #f))
               (dynamic-wind
                 (lambda () #f)
                 (lambda ()
                   (set! st (hold! db lock))
                   (with-mutex m (set! held #t) (condition-broadcast c))
                   (if (with-mutex m (await m c (lambda () begun) long-ms))
                       (begin
                         (sleep (duration release-ms))
                         (with-mutex m (set! released-at (real-time)))
                         (let-go! db st)
                         (set! st #f)
                         'let-go)
                       'never-told))
                 (lambda ()
                   (guard (e (#t #f)) (when st (let-go! db st)))
                   (close-answer db))))))))
    (if (not (with-mutex m (await m c (lambda () held) long-ms)))
        (list 'the-holder-never-held (holder answer-ms))
        (let* ((told (with-mutex m (set! begun #t) (condition-broadcast c)))
               (r (opened open read))
               (holder-answer (holder answer-ms))
               (release (with-mutex m released-at)))
          (note-time! label (took r))
          (list (car r)
                (cond ((not release) 'no-release-noted)
                      ((>= (caddr r) release) 'after-the-release)
                      (else 'before-the-release))
                (if (< (took r) 1500) 'before-the-timeout 'not-before-the-timeout)
                holder-answer)))))

(test-begin "open-locks")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

;; --- the grain -----------------------------------------------------------------------------

(test-equal "the busy wait's grain is read before any row, as test-contention's P4 row reads it: a 250 ms busy timeout under another's reserved lock answers busy after 125 ms or more, milliseconds, or before, whole seconds; a timed wait is too long from 3000 ms on the first, and from 2000 on the second"
  'read
  (begin
    (display "    the grain: ")
    (write grain)
    (display ", a wait too long from ")
    (display retry-ms)
    (display " ms")
    (newline)
    (cond ((and (eq? grain 'milliseconds) (= retry-ms 3000)) 'read)
          ((and (eq? grain 'whole-seconds) (= retry-ms 2000)) 'read)
          (else (list grain retry-ms)))))

;; --- waits ---------------------------------------------------------------------------------

(test-equal "rollback journal: under another's exclusive lock, journal-mode waits out the 1500 ms busy timeout once, at least 1000 ms and under 3000, or 2000 on a whole-second build, at wal through open-database and at delete through call-with-database, busy-timeout listed last; under a read, journal-mode wal waits the same; each then raises &sqlite-busy naming the setting's SQL, leaves nothing counted, the connection closed, and call-with-database's procedure is never called; once the holders have closed, nothing is counted and no descriptor is open"
  (list (list (busy 'open-database "PRAGMA journal_mode = wal") 'waited 'nothing-left)
        (list (busy 'call-with-database "PRAGMA journal_mode = delete") 'waited 'nothing-left)
        'proc-not-called
        (list (busy 'open-database "PRAGMA journal_mode = wal") 'waited 'nothing-left)
        zero-counts 'descriptors-back)
  (in-dir (lambda (dir)
            (let* ((before (descriptors))
                   (path (file-in dir "waits.db" 'delete))
                   (called 'proc-not-called)
                   (a (under "exclusive, journal-mode wal" path 'exclusive
                             (lambda () (open-database path '((busy-timeout . 1500) (journal-mode . wal))))
                             no-read))
                   (b (under "exclusive, journal-mode delete" path 'exclusive
                             (lambda () (call-with-database path '((journal-mode . delete) (busy-timeout . 1500))
                                          (lambda (db) (set! called 'proc-called))))
                             no-read))
                   (c (under "read, journal-mode wal" path 'read
                             (lambda () (open-database path '((busy-timeout . 1500) (journal-mode . wal))))
                             no-read)))
              (settled (list a b called c) before)))))

;; --- the list's order ------------------------------------------------------------------------

(test-equal "after busy-timeout, the rest run in the list's order, through both verbs: under another's exclusive lock on a rollback journal, with no busy timeout, journal-mode and synchronous each answer busy at once, so the first in the list names the failure: ((journal-mode . wal) (synchronous . full)) raises &sqlite-busy naming journal_mode's SQL, and its reverse synchronous's; each leaves nothing counted, call-with-database's procedure never called; once the holders have closed, nothing is counted and no descriptor is open"
  (list (list (busy 'open-database "PRAGMA journal_mode = wal") 'at-once 'nothing-left)
        (list (busy 'open-database "PRAGMA synchronous = 2") 'at-once 'nothing-left)
        (list (busy 'call-with-database "PRAGMA journal_mode = wal") 'at-once 'nothing-left)
        (list (busy 'call-with-database "PRAGMA synchronous = 2") 'at-once 'nothing-left)
        'proc-not-called
        zero-counts 'descriptors-back)
  (in-dir (lambda (dir)
            (let* ((before (descriptors))
                   (path (file-in dir "order.db" 'delete))
                   (called 'proc-not-called)
                   (in-order '((journal-mode . wal) (synchronous . full)))
                   (reversed '((synchronous . full) (journal-mode . wal)))
                   (a (under "exclusive, journal-mode then synchronous" path 'exclusive
                             (lambda () (open-database path in-order)) no-read))
                   (b (under "exclusive, synchronous then journal-mode" path 'exclusive
                             (lambda () (open-database path reversed)) no-read))
                   (c (under "exclusive, journal-mode then synchronous, call-with-database" path 'exclusive
                             (lambda () (call-with-database path in-order
                                          (lambda (db) (set! called 'proc-called))))
                             no-read))
                   (d (under "exclusive, synchronous then journal-mode, call-with-database" path 'exclusive
                             (lambda () (call-with-database path reversed
                                          (lambda (db) (set! called 'proc-called))))
                             no-read)))
              (settled (list a b c d called) before)))))

;; --- at once -------------------------------------------------------------------------------

(test-equal "rollback journal: under another's exclusive lock, foreign-keys, temp-store and trusted-schema, each with a busy timeout of 1500 ms, and busy-timeout alone, open at once and read back as asked; under a read, and under a reserved lock, a list of every setting but journal-mode wal opens at once, synchronous read back as asked; none leaves anything counted"
  (list (list '(opened 1) 'at-once 'nothing-left)
        (list '(opened 2) 'at-once 'nothing-left)
        (list '(opened 0) 'at-once 'nothing-left)
        (list '(opened 1500) 'at-once 'nothing-left)
        (list '(opened 3) 'at-once 'nothing-left)
        (list '(opened 3) 'at-once 'nothing-left)
        zero-counts 'descriptors-back)
  (in-dir (lambda (dir)
            (let* ((before (descriptors))
                   (path (file-in dir "at-once.db" 'delete))
                   (all-but-wal '((foreign-keys . #t) (journal-mode . delete) (synchronous . extra)
                                  (temp-store . memory) (trusted-schema . #f) (busy-timeout . 1500)))
                   (a (under "exclusive, foreign-keys" path 'exclusive
                             (lambda () (open-database path '((foreign-keys . #t) (busy-timeout . 1500))))
                             (lambda (db) (pragma db "foreign_keys"))))
                   (b (under "exclusive, temp-store" path 'exclusive
                             (lambda () (open-database path '((busy-timeout . 1500) (temp-store . memory))))
                             (lambda (db) (pragma db "temp_store"))))
                   (c (under "exclusive, trusted-schema" path 'exclusive
                             (lambda () (open-database path '((trusted-schema . #f) (busy-timeout . 1500))))
                             (lambda (db) (pragma db "trusted_schema"))))
                   (d (under "exclusive, busy-timeout alone" path 'exclusive
                             (lambda () (open-database path '((busy-timeout . 1500))))
                             (lambda (db) (pragma db "busy_timeout"))))
                   (e (under "read, all but journal-mode wal" path 'read
                             (lambda () (open-database path all-but-wal))
                             (lambda (db) (pragma db "synchronous"))))
                   (f (under "reserved, all but journal-mode wal" path 'reserved
                             (lambda () (open-database path all-but-wal))
                             (lambda (db) (pragma db "synchronous")))))
              (settled (list a b c d e f) before)))))

;; --- refused at once --------------------------------------------------------------------------

(test-equal "refused at once, with a busy timeout of 1500 ms: journal-mode wal under another's reserved lock; on a WAL file, journal-mode delete through open-database, and truncate through call-with-database, its procedure never called, while another connection that has read the file is open, idle; each raises &sqlite-busy naming the setting's SQL and leaves nothing counted. Beside a connection opened and never used, delete opens at once; and once the idle one has closed, it opens, reading back delete"
  (list (list (busy 'open-database "PRAGMA journal_mode = wal") 'at-once 'nothing-left)
        (list (busy 'open-database "PRAGMA journal_mode = delete") 'at-once 'nothing-left)
        (list (busy 'call-with-database "PRAGMA journal_mode = truncate") 'at-once 'nothing-left)
        'proc-not-called
        (list '(opened "delete") 'at-once 'nothing-left)
        '(opened "delete")
        zero-counts 'descriptors-back)
  (in-dir (lambda (dir)
            (let* ((before (descriptors))
                   (rollback (file-in dir "reserved.db" 'delete))
                   (wal (file-in dir "wal.db" 'wal))
                   (unused (file-in dir "unused.db" 'wal))
                   (called 'proc-not-called)
                   (a (under "reserved, journal-mode wal" rollback 'reserved
                             (lambda () (open-database rollback '((busy-timeout . 1500) (journal-mode . wal))))
                             no-read))
                   (b (under "WAL, idle, journal-mode delete" wal 'idle
                             (lambda () (open-database wal '((busy-timeout . 1500) (journal-mode . delete))))
                             no-read))
                   (c (under "WAL, idle, journal-mode truncate" wal 'idle
                             (lambda () (call-with-database wal '((journal-mode . truncate) (busy-timeout . 1500))
                                          (lambda (db) (set! called 'proc-called))))
                             no-read))
                   (d (under "WAL, unused, journal-mode delete" unused 'unused
                             (lambda () (open-database unused '((busy-timeout . 1500) (journal-mode . delete))))
                             (lambda (db) (pragma db "journal_mode"))))
                   (e (car (opened (lambda () (open-database wal '((busy-timeout . 1500) (journal-mode . delete))))
                                   (lambda (db) (pragma db "journal_mode"))))))
              (settled (list a b c called d e) before)))))

;; --- let go mid-wait ------------------------------------------------------------------------------

(test-equal "the holder, on a thread of its own, lets go 500 ms after the open begins: under its exclusive lock, open-database with journal-mode wal, busy-timeout listed last at 1500 ms, succeeds after the release and before its timeout's end, reading back wal; under its read, call-with-database the same, its procedure reading wal; nothing is left counted and no descriptor open"
  (list (list '(opened "wal") 'after-the-release 'before-the-timeout 'let-go)
        (list "wal" 'after-the-release 'before-the-timeout 'let-go)
        zero-counts 'descriptors-back)
  (in-dir (lambda (dir)
            (let* ((before (descriptors))
                   (exclusive (file-in dir "mid-exclusive.db" 'delete))
                   (reading (file-in dir "mid-read.db" 'delete))
                   (a (released-mid-wait "exclusive, let go mid-wait" exclusive 'exclusive
                                         (lambda () (open-database exclusive '((journal-mode . wal) (busy-timeout . 1500))))
                                         (lambda (db) (pragma db "journal_mode"))))
                   (b (released-mid-wait "read, let go mid-wait" reading 'read
                                         (lambda () (call-with-database reading '((busy-timeout . 1500) (journal-mode . wal))
                                                      (lambda (db) (pragma db "journal_mode"))))
                                         no-read)))
              (settled (list a b) before)))))

;; --- WAL on WAL -----------------------------------------------------------------------------------

(test-equal "on a file already in WAL, journal-mode wal with a busy timeout of 1500 ms opens at once and reads back wal, beside another connection idle, reading, in BEGIN IMMEDIATE with a write, and in BEGIN EXCLUSIVE with a write (P14); none leaves anything counted"
  (list (list '(opened "wal") 'at-once 'nothing-left)
        (list '(opened "wal") 'at-once 'nothing-left)
        (list '(opened "wal") 'at-once 'nothing-left)
        (list '(opened "wal") 'at-once 'nothing-left)
        zero-counts 'descriptors-back)
  (in-dir (lambda (dir)
            (let* ((before (descriptors))
                   (path (file-in dir "wal-on-wal.db" 'wal))
                   (open (lambda () (open-database path '((busy-timeout . 1500) (journal-mode . wal)))))
                   (mode (lambda (db) (pragma db "journal_mode")))
                   (a (under "WAL on WAL, idle" path 'idle open mode))
                   (b (under "WAL on WAL, read" path 'read open mode))
                   (c (under "WAL on WAL, reserved" path 'reserved open mode))
                   (d (under "WAL on WAL, exclusive" path 'exclusive open mode)))
              (settled (list a b c d) before)))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "open-locks")

(exit (suite-exit-status runner))
