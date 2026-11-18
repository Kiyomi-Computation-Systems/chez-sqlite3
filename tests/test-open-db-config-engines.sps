#!r6rs
;;; The suite for db_config's four settings at open under engines (ADR-0018,
;;; amended in M3 slice 5, in M3's closing review and for M4; ADR-0021,
;;; decision 3; the M4 plan, section 4.1, and section 5, item 3), in
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
;;;                  unanswered, and the one answered reads as asked
;;;   once a call    applied-settings/with on a connection of the suite's, the
;;;                  four and a PRAGMA, through a stand-in that counts each
;;;                  call and passes it to native's binding: interleaved as
;;;                  above, each op's set made once a call, in order, by
;;;                  whichever run reaches it first; a whole new call's only
;;;                  below a refusal its control saw before the first set
;;;   a failing set  applied-settings/with whose stand-in fails the second
;;;   twice          set, resumed to its end twice at every fuel: the first
;;;                  raises its &sqlite-error, the connection closed; the second
;;;                  is refused or raises it again past the close, and calls
;;;                  the stand-in no more
;;;
;;; Where the library lacks sqlite3_load_extension, as Apple's does, the
;;; opt-in would refuse every open, so its list leaves the opt-in out, and a
;;; line names it unavailable (ADR-0005, amended); the rest run. An engine
;;; spends no ticks inside a critical section, so the fuels measure the Scheme
;;; work between the call's sections (.plans/traps.md). Each fuel and tick
;;; begins with a collection, collect-trip-bytes raised far above what its
;;; runs allocate, so no collect request falls in them and their order holds
;;; (.plans/research/m3-slice-5/, gc-ticks.sps). Each bound on a whole new call
;;; is a refusal the sweep sees itself, never a refused call's fuel, a control
;;; on another call, or a caller's count (AGENTS.md).
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) make-engine set-timer timer-interrupt-handler collect collect-trip-bytes
              foreign-ref)
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

;; slice : Engine Positive-Integer -> (U (List 'completed Any) (List 'expired Engine))
(define (slice e fuel)
  (e fuel (lambda (left . vals) (list 'completed (car vals))) (lambda (more) (list 'expired more))))

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

;; twice : String Positive-Integer -> (List Boolean Symbol (Listof Any) Boolean)
;; open-database on PATH with settings, as an engine, one slice of FUEL.
;; Completed, it is closed: (#f none () #f). Expired, its remainder is resumed
;; to its end, FIRST, as asked; the suite sets every PRAGMA and op otherwise
;; on it; and the same remainder is resumed again, SECOND: refused,
;; &sqlite-closed, nothing touched; same, FIRST again, past the call's last
;; section; new, a whole new call's connection, as asked. FIRST must still
;; read as the suite set it: no set ran again on it. Last, whether a
;; connection was counted at the expiry.
(define (twice path fuel)
  (let ((r (slice (make-engine (open-thunk path)) fuel)))
    (if (eq? (car r) 'completed)
        (begin (close-answer (cadr r)) (list #f 'none '() #f))
        (let* ((more (cadr r))
               (open-at-expiry (> (connection-count) 0))
               (first (finish more))
               (first-read (if (a-database? first) (readings first) (list 'not-a-database first))))
          (if (not (a-database? first))
              (list #t 'none (list (list 'first first-read)) open-at-expiry)
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
                      open-at-expiry)))))))

;; twice-sweep : String -> (List Any (Listof Any) (Listof (Pairof Symbol Natural)) (U Natural #f))
;; twice at every fuel from 1 until the open completes without expiring,
;; each fuel begun by quieted!: that fuel; each fuel's deviations; how many
;; fuels each kind of second resume came at; and the first fuel at which a
;; remainder taken before the open's section, no connection counted at its
;; expiry, was refused, the sweep's own bound: a new one past it deviates.
(define (twice-sweep path)
  (let loop ((fuel 1) (deviations '()) (refused 0) (same 0) (new 0) (refused-at #f))
    (quieted!)
    (let* ((r (twice path fuel))
           (kind (cadr r))
           (late-new (and (eq? kind 'new) refused-at))
           (found (if late-new (cons (list 'new-past-a-refusal refused-at) (caddr r)) (caddr r)))
           (deviations (if (null? found) deviations (cons (cons fuel found) deviations)))
           (refused-at (or refused-at (and (eq? kind 'refused) (not (cadddr r)) fuel)))
           (refused (if (eq? kind 'refused) (+ refused 1) refused))
           (same (if (eq? kind 'same) (+ same 1) same))
           (new (if (eq? kind 'new) (+ new 1) new)))
      (cond ((not (car r))
             (list fuel (reverse deviations) (list (cons 'refused refused) (cons 'same same) (cons 'new new))
                   refused-at))
            ((>= fuel 20000) (list 'no-completion-by-20000 (reverse deviations) '() refused-at))
            (else (loop (+ fuel 1) deviations refused same new refused-at))))))

(test-equal "open-database's remainder resumed twice, at every fuel from 1 until it completes without expiring: resumed to its end it answers a connection as asked; the suite sets every PRAGMA and op otherwise there; resumed again, it raises &sqlite-closed, refused at a section, at half the fuels at least and at some before the open, or, past its last section, answers that connection again; a whole new call, its own connection as asked, only below every refusal before the open; the first connection keeps what the suite set, so no PRAGMA and no op is set on it again, and nothing is left counted"
  (list '() 'refused-before-the-open-and-at-half-the-fuels zero-counts)
  (let ((r (in-dir (lambda (dir) (twice-sweep (string-append dir "/t.db"))))))
    (if (and (pair? r) (eq? (car r) 'raised))
        r
        (let ((kinds (caddr r)) (refused-at (cadddr r)))
          (display "  open-database with the ops resumed twice: completed without expiring at fuel ")
          (write (car r))
          (display "; second resumes ")
          (write kinds)
          (display "; refused before the open first at fuel ")
          (write refused-at)
          (newline)
          (list (summarized (cadr r))
                (let ((refused (kind-count kinds 'refused)))
                  (if (and refused-at (integer? (car r)) (>= (* 2 refused) (car r)))
                      'refused-before-the-open-and-at-half-the-fuels
                      (list 'refused refused 'of (car r) 'before-the-open-first-at refused-at)))
                (native-counts))))))

;; --- call-with-database, re-entered through a timer's continuation ------------------------------

;; reentered-at : String Positive-Integer -> (U 'no-capture (List Natural Any Natural))
;; call-with-database on PATH with settings, a timer's handler taking a
;; continuation at the call's tick I. The procedure, called first, sets
;; everything otherwise and re-enters it, once; called again, it answers
;; (nested-call READINGS). no-capture when tick I fell after the procedure
;; started; else the connections counted at the capture, what the re-entry
;; answered, and how many more calls of the procedure it made.
(define (reentered-at path i)
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
           (if (= ticks i)
               (begin (set! phase (connection-count))
                      (call/cc (lambda (k) (set! saved k))))
               (set-timer 1)))))
      (lambda ()
        (set-timer 1)
        (let ((r (attempt (lambda () (call-with-database path settings proc)))))
          (set-timer 0)
          (if return-to
              (let ((back return-to)) (set! return-to #f) (back r))
              r)))
      (lambda ()
        (set-timer 0)
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

;; reentry-sweep : String -> (List Natural (Listof Any) (Listof (Pairof Symbol Natural)) (U Natural #f))
(define (reentry-sweep path)
  (let loop ((i 1) (deviations '()) (refused 0) (again 0) (new 0) (refused-at #f))
    (quieted!)
    (let* ((r (reentered-at path i))
           (counts (native-counts))
           (kind (reentry-kind r))
           (found (append (if (eq? kind 'deviation) (list r) '())
                          (if (and (eq? kind 'new) refused-at) (list (list 'new-past-a-refusal refused-at)) '())
                          (if (equal? counts zero-counts) '() (list (list 'counts counts)))))
           (deviations (if (null? found) deviations (cons (cons i found) deviations)))
           (refused-at (or refused-at (and (eq? kind 'refused) (eqv? (car r) 0) i))))
      (cond ((or (eq? kind 'done) (>= i 20000))
             (list i (reverse deviations)
                   (list (cons 'refused refused) (cons 'again again) (cons 'new new))
                   refused-at))
            (else (loop (+ i 1) deviations
                        (if (eq? kind 'refused) (+ refused 1) refused)
                        (if (eq? kind 'again) (+ again 1) again)
                        (if (eq? kind 'new) (+ new 1) new)
                        refused-at))))))

(test-equal "call-with-database with the ops re-entered through a continuation a timer's handler took at each tick from 1 until its procedure starts, the procedure re-entering it once it has set every PRAGMA and op otherwise: taken before the sets were done, it raises &sqlite-closed, refused at a section, the procedure not called again; taken past their last section, it calls the procedure again, which finds what it set; refused at half the ticks at least and at some before the open; a whole new call only below every refusal before the open; none sets anything again on the first connection, and nothing is left counted"
  (list '() 'refused-before-the-open-and-at-half-the-ticks zero-counts)
  (let ((r (in-dir (lambda (dir) (reentry-sweep (string-append dir "/r.db"))))))
    (if (and (pair? r) (eq? (car r) 'raised))
        r
        (let ((kinds (caddr r)) (refused-at (cadddr r)))
          (display "  call-with-database with the ops re-entered: its procedure started at tick ")
          (write (car r))
          (display "; re-entries ")
          (write kinds)
          (display "; refused before the open first at tick ")
          (write refused-at)
          (newline)
          (list (summarized (cadr r))
                (let ((refused (kind-count kinds 'refused)))
                  (if (and refused-at (>= (* 2 refused) (car r)))
                      'refused-before-the-open-and-at-half-the-ticks
                      (list 'refused refused 'of (car r) 'before-the-open-first-at refused-at)))
                (native-counts))))))

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

;; Trial = (List Symbol Natural (Listof Any) (U 'both 'straddle #f))
;; Its kind, completed when R's first slice completed the call, last when
;; R's resume completed within G, else interleaved; how many answers were
;; whole calls' own, databases or applied; what deviated; and, for an
;; interleaved trial, where its remainders lay against the call's first
;; section, each read at its own expiry: both past it; straddle, R before
;; it and R1, taken later on R's own resume, past it; or #f, both before.

;; Sweep = (List Any Natural (Listof Any) Natural Natural Natural (U Natural #f) Natural Natural)
;; The fuel at which the call completes without expiring, or
;; no-completion-by-20000; how many trials ran; each trial's deviations,
;; with its fuels; the trials whose runs answered the call; those in which
;; two runs made whole calls; the last fuel at which the control made a
;; whole new call, 0 for none; the first fuel at which the control was
;; refused before the call's first section, #f for none; the trials whose R
;; and R1 were both taken past the call's first section, each read at its
;; own expiry; and those whose R was taken before it and R1 past it, which
;; race R's second run against R1 at that section itself.

;; interleave-sweep : (Natural -> Any) (Natural Natural Boolean -> Trial) -> Sweep
;; At every fuel from 1 until the call completes without expiring, CONTROL,
;; then TRIAL at every G from 1 until R's resume completes within it, each
;; fuel begun by quieted!. CONTROL answers completed, or (NEW REFUSED-
;; BEFORE): whether its remainder, resumed to its end twice, made a whole
;; new call the second time, and whether it was refused then, taken before
;; the call's first section. A trial may make a whole new call where the
;; control made one at its fuel or the one before, a tick's room should a
;; collect request fall all the same.
(define (interleave-sweep control trial)
  (let floop ((fuel 1) (trials 0) (deviations '()) (answered 0) (new 0) (last-new 0) (was-new #f)
              (refused-at #f) (past 0) (straddle 0))
    (let* ((made (begin (quieted!) (control fuel)))
           (made-new (and (pair? made) (car made)))
           (new? (or made-new was-new))
           (refused-at (or refused-at (and (pair? made) (cadr made) fuel))))
      (if (eq? made 'completed)
          (list fuel trials (reverse deviations) answered new last-new refused-at past straddle)
          (let ((last-new (if made-new fuel last-new)))
            (let gloop ((g 1) (trials trials) (deviations deviations) (answered answered) (new new)
                        (past past) (straddle straddle))
              (let* ((t (trial fuel g new?))
                     (kind (car t))
                     (deviations (if (null? (caddr t)) deviations
                                     (cons (list fuel g (caddr t)) deviations)))
                     (answered (if (> (cadr t) 0) (+ answered 1) answered))
                     (new (if (> (cadr t) 1) (+ new 1) new))
                     (past (if (eq? (cadddr t) 'both) (+ past 1) past))
                     (straddle (if (eq? (cadddr t) 'straddle) (+ straddle 1) straddle))
                     (trials (+ trials 1)))
                (cond ((eq? kind 'completed)
                       (list fuel trials (reverse deviations) answered new last-new refused-at past
                             straddle))
                      ((>= fuel 20000)
                       (list 'no-completion-by-20000 trials (reverse deviations) answered new last-new
                             refused-at past straddle))
                      ((eq? kind 'last)
                       (floop (+ fuel 1) trials deviations answered new last-new made-new refused-at past
                              straddle))
                      (else (gloop (+ g 1) trials deviations answered new past straddle))))))))))

;; interleave-reported : String Sweep -> (List Any Any Any)
;; RUN's deviations, summarized; whether its trials answered the call at
;; least three a fuel on average, had both remainders past the call's first
;; section in a trial a fuel at least, and R before it with R1 past it in
;; some: a sweep that reused one R across every G answers at most one a
;; fuel; and whether its control was
;; refused before the call's first section at some fuel, and made every
;; whole new call below the first such fuel. Its fuels printed, naming WHAT.
(define (interleave-reported what run)
  (display "  ")
  (display what)
  (display ": completed without expiring at fuel ")
  (write (car run))
  (display "; trials ")
  (write (cadr run))
  (display "; trials answering ")
  (write (list-ref run 3))
  (display "; both remainders past the first section in ")
  (write (list-ref run 7))
  (display "; R before it and R1 past it in ")
  (write (list-ref run 8))
  (display "; whole new calls ")
  (write (list-ref run 4))
  (display "; the last fuel at which the control made one ")
  (write (list-ref run 5))
  (display ", below the first at which it was refused before the first section, ")
  (write (list-ref run 6))
  (newline)
  (list (if (integer? (car run)) (summarized (caddr run)) (list (car run) (summarized (caddr run))))
        (if (and (integer? (car run)) (>= (list-ref run 3) (* 3 (car run)))
                 (>= (list-ref run 7) (car run)) (> (list-ref run 8) 0))
            'answered-three-a-fuel-and-past-the-first-section-one-a-fuel
            (list 'answered (list-ref run 3) 'past (list-ref run 7) 'straddling (list-ref run 8)
                  'over (car run)))
        (let ((last-new (list-ref run 5)) (refused-at (list-ref run 6)))
          (if (and refused-at (< last-new refused-at))
              'whole-new-calls-below-a-refusal
              (list 'whole-new-calls-not-below-a-refusal last-new refused-at)))))

;; --- interleaved: open-database -----------------------------------------------------------

;; mem-settings : Settings
;; A PRAGMA, busy-timeout listed last so it runs first, and the three ops,
;; with the opt-in where the library has it, on :memory:.
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

(define (mem-thunk) (attempt (lambda () (open-database ":memory:" mem-settings))))

;; ran-counts : (-> Any) -> (List Any Symbol)
;; GO's answer, and whether the counts were the same before and after it.
(define (ran-counts go)
  (let* ((c0 (native-counts))
         (answer (go))
         (c1 (native-counts)))
    (list answer (if (equal? c0 c1) 'counts-kept (list 'counts c0 c1)))))

;; open-judged : Boolean Counts (Listof (List Any Symbol)) Boolean -> Trial-Tail
;; RUNS' answers, NEW? whether a whole new call may come at the fuel,
;; judged: each a database, or &sqlite-closed refused with the counts kept;
;; each database answered checked, nothing tracked, read as asked, then
;; closed; then the counts START's, so no run left a connection open that
;; it did not answer. Answers (kind-tail): how many distinct databases, the
;; deviations, and PAST.
(define (open-judged new? start runs past)
  (let* ((deviations '())
         (answered (let loop ((rest runs) (found '()))
                     (cond ((null? rest) (reverse found))
                           ((and (a-database? (car (car rest))) (not (memq (car (car rest)) found)))
                            (loop (cdr rest) (cons (car (car rest)) found)))
                           (else (loop (cdr rest) found))))))
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
    (when (and (> (length answered) 1) (not new?))
      (deviate! (list 'new-where-the-control-made-none (length answered))))
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
    (list (length answered) (reverse deviations) past)))

;; open-trial : Natural Natural Boolean -> Trial
;; One trial of open-database with mem-settings at FUEL, R resumed at G.
(define (open-trial fuel g new?)
  (let* ((start (native-counts))
         (r (slice (make-engine mem-thunk) fuel)))
    (if (eq? (car r) 'completed)
        (cons 'completed (open-judged new? start (list (list (cadr r) 'counts-kept)) #f))
        (let* ((R (cadr r))
               (r-open (> (connection-count) (cdr (assq 'connection start))))
               (r1 (slice R g)))
          (if (eq? (car r1) 'completed)
              (let ((second (ran-counts (lambda () (finish R)))))
                (cons 'last (open-judged new? start (list (list (cadr r1) 'counts-kept) second) #f)))
              (let* ((R1 (cadr r1))
                     (r1-open (> (connection-count) (cdr (assq 'connection start))))
                     (second (ran-counts (lambda () (finish R))))
                     (third (ran-counts (lambda () (finish R1)))))
                (cons 'interleaved (open-judged new? start (list second third)
                                                (cond ((and r-open r1-open) 'both)
                                                      (r1-open 'straddle)
                                                      (else #f))))))))))

;; open-control : Natural -> (U 'completed (List Boolean Boolean))
(define (open-control fuel)
  (let ((r (slice (make-engine mem-thunk) fuel)))
    (if (eq? (car r) 'completed)
        (begin (close-answer (cadr r)) 'completed)
        (let* ((before (eqv? (connection-count) 0))
               (first (finish (cadr r)))
               (second (finish (cadr r)))
               (new (and (a-database? second) (a-database? first) (not (eq? second first)))))
          (when (a-database? first) (close-answer first))
          (when (and (a-database? second) (not (eq? second first))) (close-answer second))
          (list new (and before (not new) (equal? second '(raised (closed open-database)))))))))

(test-equal "open-database's remainder R with the ops among two PRAGMAs on :memory:, taken at every fuel from 1 until the call completes without expiring, resumed at every later fuel until it expires again as R1, then R resumed again to its end, then R1: each run answers the connection or is refused with &sqlite-closed, the counts kept; no connection is left open that a run did not answer; the one answered tracks nothing and reads every setting as asked; trials answer three a fuel on average, have both remainders past the open in one a fuel, and R before it with R1 past it in some; and the control is refused before the open at some fuel, every whole new call below the first"
  (list '() 'answered-three-a-fuel-and-past-the-first-section-one-a-fuel
        'whole-new-calls-below-a-refusal zero-counts)
  (let ((run (interleave-sweep open-control open-trial)))
    (append (interleave-reported "open-database with the ops, interleaved" run)
            (list (native-counts)))))

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

;; counting : -> (Values Procedure (-> (Listof (List Natural Integer))))
;; A stand-in for native's binding that notes each call's op and value,
;; then passes it to native's binding; and a reader of its notes, oldest
;; first. It runs inside the set's critical section, where no tick is spent,
;; so no fuel splits its note from its call.
(define (counting)
  (let ((calls '()))
    (values
     (lambda (h op value cell)
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

;; once-judged : Boolean Database (-> (Listof Any)) (Listof (List Any Natural Symbol)) Boolean -> Trial-Tail
;; RUNS, judged once the trial is done: each answered applied, or
;; &sqlite-closed refused, noting no call and keeping the counts; the
;; stand-in's calls, the whole call's exactly, once each and in order, or,
;; where NEW? lets a whole new call come, twice over, whole each time; and
;; DB, still open, reads every op and the PRAGMA as asked. Then DB is
;; closed, and nothing is counted. The whole calls are counted from the
;; stand-in's notes, each the first set's call: a whole call makes every
;; set once, and so its first, a refused run makes none, and a run past
;; the last set answers applied again making none, as open-database's
;; past its last section answers the same connection. Counting the runs
;; that answer applied counted such a run as a second call.
(define (once-judged new? db calls runs past)
  (let* ((deviations '())
         (noted (calls))
         (whole (let loop ((rest noted) (n 0))
                  (cond ((null? rest) n)
                        ((equal? (car rest) (car once-calls)) (loop (cdr rest) (+ n 1)))
                        (else (loop (cdr rest) n))))))
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
    (unless (or (equal? noted once-calls)
                (and new? (two-whole? noted)))
      (deviate! (list 'calls noted)))
    (when (and (> whole 1) (not new?))
      (deviate! (list 'new-where-the-control-made-none whole)))
    (let ((read (attempt (lambda () (list (op-reads db) (pragma db "foreign_keys"))))))
      (unless (equal? read once-as-asked) (deviate! (list 'readings read))))
    (unless (eqv? (connection-count) 1) (deviate! (list 'connections (connection-count))))
    (close-answer db)
    (unless (equal? (native-counts) zero-counts) (deviate! (list 'counts (native-counts))))
    (list whole (reverse deviations) past)))

;; once-trial : Natural Natural Boolean -> Trial
;; One trial at FUEL, R resumed at G: a fresh connection, opened with no
;; engine, and a fresh stand-in and engine.
(define (once-trial fuel g new?)
  (let ((db (open-database ":memory:")))
    (let-values (((db-config calls) (counting)))
      (let ((r (slice (make-engine (once-thunk db db-config)) fuel)))
        (if (eq? (car r) 'completed)
            (cons 'completed (once-judged new? db calls (list (list (cadr r) 0 'counts-kept)) #f))
            (let* ((R (cadr r))
                   (r-past (> (length (calls)) 0))
                   (r1 (slice R g)))
              (if (eq? (car r1) 'completed)
                  (let ((second (noted-run (lambda () (finish R)) calls)))
                    (cons 'last (once-judged new? db calls (list (list (cadr r1) 0 'counts-kept) second) #f)))
                  (let* ((R1 (cadr r1))
                         (r1-past (> (length (calls)) 0))
                         (second (noted-run (lambda () (finish R)) calls))
                         (third (noted-run (lambda () (finish R1)) calls)))
                    (cons 'interleaved (once-judged new? db calls (list second third)
                                                    (cond ((and r-past r1-past) 'both)
                                                          (r1-past 'straddle)
                                                          (else #f))))))))))))

;; once-control : Natural -> (U 'completed (List Boolean Boolean))
;; applied-settings/with at FUEL on a fresh connection: completed; or
;; whether its remainder, resumed to its end twice, made a whole new call
;; the second time, the stand-in noting the calls again; and whether it was
;; refused then, noting no call, taken before the first set, no call noted
;; at its expiry.
(define (once-control fuel)
  (let ((db (open-database ":memory:")))
    (let-values (((db-config calls) (counting)))
      (let ((r (slice (make-engine (once-thunk db db-config)) fuel)))
        (if (eq? (car r) 'completed)
            (begin (close-answer db) 'completed)
            (let* ((before (= (length (calls)) 0))
                   (first (finish (cadr r)))
                   (n (length (calls)))
                   (second (finish (cadr r)))
                   (new (> (length (calls)) n)))
              (close-answer db)
              (list new (and before (not new) (equal? second '(raised (closed the-suite)))))))))))

(test-equal "applied-settings/with on a connection of the suite's, the four and a PRAGMA, through a stand-in that notes each call and passes it to native's binding, its remainder R taken at every fuel from 1 until the call completes without expiring, R1 from R's resume at every later fuel, then R resumed again to its end, then R1, each trial on a fresh connection, stand-in and engine: each op's set is made once a call, in the list's order, by whichever run reaches it; a refused run notes no call and keeps the counts; the connection stays open and reads every op and the PRAGMA as asked; trials answer three a fuel on average, have both remainders past the first set in one a fuel, and R before it with R1 past it in some; and the control is refused before the first set at some fuel, every whole new call below the first"
  (list '() 'answered-three-a-fuel-and-past-the-first-section-one-a-fuel
        'whole-new-calls-below-a-refusal zero-counts)
  (let ((run (interleave-sweep once-control once-trial)))
    (append (interleave-reported "applied-settings/with, counted, interleaved" run)
            (list (native-counts)))))

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

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "open-db-config-engines")

(exit (suite-exit-status runner))
