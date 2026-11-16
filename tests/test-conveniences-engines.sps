#!r6rs
;;; The suite for the conveniences under engines (ADR-0016, decision 6, and
;;; its amendment in M3 slice 1; ADR-0020, decision 7, amended; the M3 plan,
;;; section 4.1 and its probe P6), in (chez-sqlite3 private conveniences).
;;; Each row sweeps fuel from 1 until the call completes without expiring,
;;; never to a fixed bound, and prints that fuel. An engine spends no ticks
;;; inside a critical section (.plans/traps.md), so each expiry falls between
;;; sections.
;;;
;;;   P6            execute!, query and query-row, at every fuel, complete
;;;                 with their answer, resumed after each expiry, and leave
;;;                 their statement cached, ready, none at a row: they hold no
;;;                 dynamic-wind, and nothing but the convenience reaches its
;;;                 checked-out statement
;;;   query-fold    does not survive a preemption: an expiry inside its wind
;;;                 finalizes its statement, and the resumed loop raises
;;;                 &sqlite-closed. At every fuel it answers its fold or that,
;;;                 at fuel 1 that, and leaves no statement at a row
;;;   execute-script!
;;;                 does not survive one either: an expiry inside its block's
;;;                 extent frees the block, and call-with-block refuses the
;;;                 resume, from execute-script!. At every fuel it completes
;;;                 or is refused so, at fuel 1 refused, the statements before
;;;                 the expiry standing, and leaves no statement and no block
;;;   two engines   on one thread, sharing a connection, each running
;;;                 execute!, query and query-row on the same SQL, the cache
;;;                 warm: at every fuel each answers rightly, and the cache and
;;;                 the statement count end where they began, so no statement
;;;                 was handed out twice, finalized twice or lost (ADR-0020,
;;;                 decision 7)
;;;
;;; The loading procedures are reached through eval, under a guard, as
;;; tests/test-statement.sps reaches them.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. No expected value is #f where the actual could raise. Effects run in
;;; order, through let* and named lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) make-engine)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) chez-sqlite3-error? sqlite-error? sqlite-error-code
              sqlite-error-extended-code sqlite-error-sql sqlite-error-offset sqlite-closed?))

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

(define conveniences '(chez-sqlite3 private conveniences))
(define connection-library '(chez-sqlite3 private connection))
(define statement-library '(chez-sqlite3 private statement))
(define execute! (reach conveniences 'execute!))
(define query (reach conveniences 'query))
(define query-row (reach conveniences 'query-row))
(define query-fold (reach conveniences 'query-fold))
(define execute-script! (reach conveniences 'execute-script!))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define database-cache-count (reach connection-library 'database-cache-count))
(define tracked-statements (reach connection-library 'tracked-statements))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define step! (reach statement-library 'step!))
(define statement-sql (reach statement-library 'statement-sql))
(define statement-state (reach statement-library 'statement-state))
(define column-value (reach '(chez-sqlite3 private statement-values) 'column-value))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
(define (what-raised e)
  (cond ((sqlite-error? e)
         (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
               (sqlite-error-sql e) (sqlite-error-offset e)))
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

;; states : Database -> (Listof (Pairof String Symbol))
(define (states db)
  (list-sort (lambda (a b) (string<? (car a) (car b)))
             (let loop ((rest (tracked-statements db)) (found '()))
               (if (null? rest)
                   found
                   (loop (cdr rest)
                         (cons (cons (statement-sql (car rest)) (statement-state (car rest))) found))))))

(define (statement-count) (cdr (assq 'statement (native-counts))))

;; undo! : (Listof Any) (Listof Any) -> Void
(define (undo! statements databases)
  (for-each (lambda (s) (guard (e (#t #f)) (finalize-statement! s))) statements)
  (for-each (lambda (db) (guard (e (#t #f)) (close-database! db))) databases))

;; with-memory-db : (Database -> Any) -> Any
(define (with-memory-db proc)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda () (attempt (lambda () (set! db (open-database ":memory:")) (proc db))))
      (lambda () (when db (undo! '() (list db)))))))

;; tier-run : Database String -> (Listof (Vectorof Any))
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

;; sweep : (Positive-Integer -> (List Boolean Any)) Positive-Integer -> (List Any (Listof Any))
;; CHECK at each fuel from 1, until a fuel at which the call completed
;; without expiring, at most CAP: that fuel, and each fuel's deviation, in
;; order. CHECK answers whether the call expired, and #f, or what deviated.
(define (sweep check cap)
  (let loop ((fuel 1) (found '()))
    (let* ((r (check fuel))
           (more (if (cadr r) (cons (list fuel (cadr r)) found) found)))
      (cond ((not (car r)) (list fuel (reverse more)))
            ((>= fuel cap) (list 'no-completion-by cap (reverse more)))
            (else (loop (+ fuel 1) more))))))

;; named : String (List Any (Listof Any)) -> (Listof Any)
;; RUN's deviations, its completing fuel printed, naming WHAT.
(define (named what run)
  (when (integer? (car run))
    (display "  ")
    (display what)
    (display " completed without expiring at fuel ")
    (display (car run))
    (newline))
  (if (integer? (car run)) (cadr run) run))

(test-begin "conveniences-engines")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

;; --- P6: execute!, query and query-row complete at every fuel ---------------------------------

(test-equal "execute! under an engine, at every fuel from 1 until it completes without expiring, completes, inserting its row once, and leaves its statement cached and ready, none at a row"
  '()
  (with-memory-db
   (lambda (db)
     (tier-run db "create table t (x)")
     (named "execute!"
            (sweep (lambda (fuel)
                     (let* ((r (engine-run (lambda () (attempt (lambda () (no-value (execute! db "insert into t values (?)" fuel)))))
                                           fuel))
                            (after (list (car r) (states db) (statement-count)
                                         (tier-run db (string-append "select count(*) from t where x = " (number->string fuel))))))
                       (list (cadr r)
                             (and (not (equal? after (list 'no-value '(("insert into t values (?)" . ready)) 1 '(1))))
                                  after))))
                   5000)))))

(test-equal "query under an engine, at every fuel until it completes without expiring, answers every row, and leaves its statement cached and ready"
  '()
  (with-memory-db
   (lambda (db)
     (tier-run db "create table t (x)")
     (tier-run db "insert into t values (1), (2), (3)")
     (named "query"
            (sweep (lambda (fuel)
                     (let* ((r (engine-run (lambda () (attempt (lambda () (query db "select x, ?1 from t order by x" fuel))))
                                           fuel))
                            (after (list (car r) (states db) (statement-count))))
                       (list (cadr r)
                             (and (not (equal? after (list (list (vector 1 fuel) (vector 2 fuel) (vector 3 fuel))
                                                           '(("select x, ?1 from t order by x" . ready)) 1)))
                                  after))))
                   5000)))))

(test-equal "query-row under an engine, at every fuel until it completes without expiring, answers its first row, and leaves its statement cached and ready"
  '()
  (with-memory-db
   (lambda (db)
     (named "query-row"
            (sweep (lambda (fuel)
                     (let* ((r (engine-run (lambda () (attempt (lambda () (query-row db "select ?1 + 1 union all select 0" fuel))))
                                           fuel))
                            (after (list (car r) (states db) (statement-count))))
                       (list (cadr r)
                             (and (not (equal? after (list (vector (+ fuel 1)) '(("select ?1 + 1 union all select 0" . ready)) 1)))
                                  after))))
                   5000)))))

;; --- one value a section (the M3 plan's Q15) -----------------------------------------------
;; An engine spends no ticks inside a critical section, so at fuel 1 every
;; tick outside one expires. Each value bound by bind-each!/who and each
;; column read by column-value/who is its own section, with checks and a
;; finish outside it: so each adds at least one expiry. Were a row read, or a
;; statement's parameters bound, in one section, the extra values would add
;; none.

;; expiries : (-> Any) -> (List Any Natural)
;; THUNK's answer at fuel 1, resumed after each expiry, and how many there
;; were, at most 1000000.
(define (expiries thunk)
  (let loop ((e (make-engine thunk)) (n 0))
    (let ((next (e 1 (lambda (left . vals) (list 'completed (car vals))) (lambda (more) more))))
      (cond ((pair? next) (list (cadr next) n))
            ((>= n 1000000) (list 'never-completed n))
            (else (loop next (+ n 1)))))))

;; fifty : (Vectorof Natural)
;; 1 to 50.
(define fifty
  (let loop ((i 50) (acc '())) (if (= i 0) (list->vector acc) (loop (- i 1) (cons i acc)))))

;; numbered : (String -> String) Natural String -> String
;; 1 to N, each made by MAKE from its number, joined by SEPARATOR.
(define (numbered make n separator)
  (let loop ((i n) (parts '()))
    (if (= i 0)
        (fold-left (lambda (acc part) (if (string=? acc "") part (string-append acc separator part))) "" parts)
        (loop (- i 1) (cons (make (number->string i)) parts)))))

(test-equal "execute!, query and query-row bind one value a section, and query and query-row read one a section: at fuel 1, 50 parameters expire at least 49 times more than 1, and 50 columns at least 49 times more than 1, in SQL of the same length, each answering rightly"
  (list (list 'no-value 'no-value 'at-least-49-more)
        (list (list (vector 1275)) (list (vector 1)) 'at-least-49-more)
        (list (vector 1275) (vector 1) 'at-least-49-more)
        (list (list fifty) (list (vector 1)) 'at-least-49-more)
        (list fifty (vector 1) 'at-least-49-more))
  (with-memory-db
   (lambda (db)
     (tier-run db "create table t (x)")
     (let* ((given (vector->list fifty))
            (sum-50 (string-append "select " (numbered (lambda (i) (string-append "?" i)) 50 " + ")))
            (insert-50 (string-append "insert into t select " (numbered (lambda (i) (string-append "?" i)) 50 " + ")))
            (cols-50 (string-append "select " (numbered (lambda (i) i) 50 ", ")))
            (compared (lambda (more fewer)
                        (list (car more) (car fewer)
                              (if (>= (- (cadr more) (cadr fewer)) 49)
                                  'at-least-49-more
                                  (list 'only (cadr more) (cadr fewer))))))
            ;; The one-value SQL padded with spaces to its fifty-value
            ;; twin's length: checked-sql reads each character outside any
            ;; section, so a longer SQL costs ticks of its own.
            (padded (lambda (short long)
                      (string-append short (make-string (- (string-length long) (string-length short)) #\space))))
            (insert-1 (padded "insert into t select ?1" insert-50))
            (sum-1 (padded "select ?1" sum-50))
            (cols-1 (padded "select 1" cols-50))
            (e50 (expiries (lambda () (attempt (lambda () (no-value (apply execute! db insert-50 given)))))))
            (e1 (expiries (lambda () (attempt (lambda () (no-value (execute! db insert-1 1)))))))
            (q50 (expiries (lambda () (attempt (lambda () (apply query db sum-50 given))))))
            (q1 (expiries (lambda () (attempt (lambda () (query db sum-1 1))))))
            (r50 (expiries (lambda () (attempt (lambda () (apply query-row db sum-50 given))))))
            (r1 (expiries (lambda () (attempt (lambda () (query-row db sum-1 1))))))
            (c50 (expiries (lambda () (attempt (lambda () (query db cols-50))))))
            (c1 (expiries (lambda () (attempt (lambda () (query db cols-1))))))
            (d50 (expiries (lambda () (attempt (lambda () (query-row db cols-50))))))
            (d1 (expiries (lambda () (attempt (lambda () (query-row db cols-1)))))))
       (list (compared e50 e1) (compared q50 q1) (compared r50 r1) (compared c50 c1) (compared d50 d1))))))

;; --- an engine never resumed -------------------------------------------------------------------
;; An engine's expiry unwinds the winds it is inside at once, whether or not
;; the engine is ever resumed. Run one slice of FUEL ticks and abandoned:
;; query-fold, whose statement reaches its variable inside the section that
;; checks it out, has either not checked it out or finished it, never left it
;; out of the cache unfinalized; query, which holds no dynamic-wind, leaves
;; its statement out of the cache, tracked, at some fuel at its row, until
;; the close finalizes it (ADR-0016, decision 6).

;; one-slice : (-> Any) Positive-Integer -> Boolean
;; Whether THUNK, given one slice of FUEL ticks, completed; the engine is
;; abandoned if it expired.
(define (one-slice thunk fuel)
  ((make-engine thunk) fuel (lambda (left . vals) #t) (lambda (more) #f)))

(test-equal "query-fold in an engine abandoned at its first expiry, at every fuel from 1 until one slice completes it, leaves its statement finalized or cached, never checked out and left: the hand-over sits inside the check-out's section"
  '()
  (with-memory-db
   (lambda (db)
     (tier-run db "create table n (x)")
     (tier-run db "insert into n values (1), (2), (3)")
     (named "an abandoned query-fold"
            (sweep (lambda (fuel)
                     (let* ((completed (one-slice (lambda () (attempt (lambda () (query-fold db "select x from n" (lambda (acc row) acc) 0))))
                                                  fuel))
                            (left (states db))
                            (cached (database-cache-count db)))
                       (list (not completed)
                             (and (not (or (and (equal? left '()) (= cached 0))
                                           (and (equal? left '(("select x from n" . ready))) (= cached 1))))
                                  (list left cached)))))
                   5000)))))

(test-equal "query in an engine abandoned at its first expiry leaves its statement out of the cache, tracked, and at some fuel at its row, as documented; the close finalizes it, and every count is back"
  (list 'seen-at-a-row zero-counts)
  (let* ((seen-row #f)
         (n (let loop ((fuel 1))
              (let ((db (open-database ":memory:")))
                (tier-run db "create table n (x)")
                (tier-run db "insert into n values (1), (2), (3)")
                (let* ((completed (one-slice (lambda () (attempt (lambda () (query db "select x from n")))) fuel))
                       (left (states db))
                       (cached (database-cache-count db)))
                  (when (and (equal? left '(("select x from n" . row))) (= cached 0))
                    (set! seen-row #t))
                  (close-database! db)
                  (if (or completed (>= fuel 5000)) fuel (loop (+ fuel 1))))))))
    (display "  an abandoned query completed in one slice at fuel ")
    (display n)
    (newline)
    (list (if seen-row 'seen-at-a-row (list 'never-seen-at-a-row-by n)) (native-counts))))

;; --- query-fold and execute-script! do not survive a preemption ---------------------------------

;; outcome-sweep : (Positive-Integer -> (List Boolean Any (Listof Any))) Positive-Integer
;;   -> (List Any (Listof Any) (Listof Any) Any)
;; CHECK at each fuel from 1 until the call completes without expiring, CHECK
;; answering whether it expired, its outcome, and what else deviated: the
;; completing fuel; each fuel's deviation; the outcomes seen, each once, in
;; the order first seen; and fuel 1's outcome.
(define (outcome-sweep check cap)
  (let loop ((fuel 1) (deviations '()) (seen '()) (first #f))
    (let* ((r (check fuel))
           (outcome (cadr r))
           (deviations (if (null? (caddr r)) deviations (cons (list fuel (caddr r)) deviations)))
           (seen (if (member outcome seen) seen (cons outcome seen)))
           (first (if (= fuel 1) outcome first)))
      (cond ((not (car r)) (list fuel (reverse deviations) (reverse seen) first))
            ((>= fuel cap) (list 'no-completion-by cap (reverse deviations) (reverse seen) first))
            (else (loop (+ fuel 1) deviations seen first))))))

;; named-outcomes : String (List Any (Listof Any) (Listof Any) Any) -> Any
(define (named-outcomes what run)
  (when (integer? (car run))
    (display "  ")
    (display what)
    (display " completed without expiring at fuel ")
    (display (car run))
    (newline))
  (if (integer? (car run)) (cdr run) run))

(test-equal "query-fold under an engine does not survive a preemption: at every fuel until it completes without expiring, it answers its fold, or, its statement finalized by an expiry, &sqlite-closed from the resumed loop; at fuel 1 the latter; never a statement at a row, nor one left out of the cache unfinalized"
  (list '() (list 6 (list 'raised '(closed query-fold))) (list 'raised '(closed query-fold)))
  (with-memory-db
   (lambda (db)
     (tier-run db "create table n (x)")
     (tier-run db "insert into n values (1), (2), (3)")
     (let ((run (outcome-sweep
                 (lambda (fuel)
                   (let* ((r (engine-run (lambda ()
                                           (attempt (lambda ()
                                                      (query-fold db "select x from n"
                                                                  (lambda (acc row) (+ acc (vector-ref row 0)))
                                                                  0))))
                                         fuel))
                          (left (states db))
                          (counted (statement-count))
                          (cached (database-cache-count db))
                          (deviation (append (if (member (car r) (list 6 (list 'raised '(closed query-fold))))
                                                 '()
                                                 (list (list 'outcome (car r))))
                                             (if (or (and (equal? left '()) (= cached 0))
                                                     (and (equal? left '(("select x from n" . ready))) (= cached 1)))
                                                 '()
                                                 (list (list 'left left cached)))
                                             (if (= counted (length left)) '() (list (list 'counted counted))))))
                     (list (cadr r)
                           (if (equal? (car r) 6) 6 (car r))
                           deviation)))
                 5000)))
       (let ((shown (named-outcomes "query-fold" run)))
         (if (integer? (car run))
             (list (car shown)
                   (list-sort (lambda (a b) (and (integer? a) (not (integer? b)))) (cadr shown))
                   (caddr shown))
             shown))))))

(define script "insert into s values (1); insert into s values (2); insert into s values (3)")

(test-equal "execute-script! under an engine does not survive a preemption: at every fuel until it completes without expiring, it completes, or an expiry inside its block's extent frees the block and call-with-block refuses the resume, from execute-script!; at fuel 1 the latter; the statements before the expiry stand, and no statement or block is left"
  (list '() (list 'no-value (list 'raised '(assertion-violation execute-script! ())))
        (list 'raised '(assertion-violation execute-script! ())))
  (with-memory-db
   (lambda (db)
     (tier-run db "create table s (x unique)")
     (let ((run (outcome-sweep
                 (lambda (fuel)
                   (tier-run db "delete from s")
                   (let* ((r (engine-run (lambda () (attempt (lambda () (no-value (execute-script! db script))))) fuel))
                          (rows (tier-run db "select x from s order by x"))
                          (left (states db))
                          (counts (native-counts))
                          (deviation (append (if (member (car r) (list 'no-value (list 'raised '(assertion-violation execute-script! ()))))
                                                 '()
                                                 (list (list 'outcome (car r))))
                                             (if (member rows '(() (1) (1 2) (1 2 3))) '() (list (list 'rows rows)))
                                             (if (and (eq? (car r) 'no-value) (not (equal? rows '(1 2 3))))
                                                 (list (list 'completed-with rows))
                                                 '())
                                             (if (null? left) '() (list (list 'left left)))
                                             (if (equal? counts '((block . 0) (connection . 1) (statement . 0)))
                                                 '()
                                                 (list (list 'counts counts))))))
                     (list (cadr r) (car r) deviation)))
                 5000)))
       (let ((shown (named-outcomes "execute-script!" run)))
         (if (integer? (car run))
             (list (car shown)
                   (list-sort (lambda (a b) (eq? a 'no-value)) (cadr shown))
                   (caddr shown))
             shown))))))

;; --- two engines on one connection -------------------------------------------------------------
;; A and B each run execute!, query and query-row on the same three SQL, as
;; engines of FUEL ticks a slice, taking turns until both are done, on a
;; connection whose cache already holds the three. A check-out and a return
;; change the table inside call-with-open-handle's section, where no engine
;; expires, so neither engine sees the other's change half made: each is
;; handed a statement no one else holds, a cached one or a fresh one, and
;; a second return of the same SQL finds it held, and finalizes its own.

;; two-engines : Database Positive-Integer -> (List Boolean Any)
(define (two-engines db fuel)
  (tier-run db "delete from t")
  (let* ((answers (vector 'unfinished 'unfinished))
         (expired #f)
         (run (lambda (me)
                (lambda ()
                  (attempt
                   (lambda ()
                     (execute! db "insert into t values (?)" me)
                     (let* ((q (query db "select count(*) from t where x = ?" me))
                            (r (query-row db "select ?1 + 1" me)))
                       (list q r))))))))
    (let loop ((engines (list (cons 0 (make-engine (run 1))) (cons 1 (make-engine (run 2)))))
               (turns 0))
      (when (and (pair? engines) (< turns 100000))
        (let* ((me (car (car engines)))
               (next ((cdr (car engines)) fuel
                      (lambda (left . v) (vector-set! answers me (car v)) #f)
                      (lambda (more) (set! expired #t) more))))
          (loop (if next (append (cdr engines) (list (cons me next))) (cdr engines))
                (+ turns 1)))))
    (let ((outcome (list (vector-ref answers 0) (vector-ref answers 1) (states db) (statement-count)
                         (database-cache-count db))))
      (list expired
            (and (not (equal? outcome (list (list '(#(1)) '#(2)) (list '(#(1)) '#(3))
                                            '(("insert into t values (?)" . ready)
                                              ("select ?1 + 1" . ready)
                                              ("select count(*) from t where x = ?" . ready))
                                            3 3)))
                 outcome)))))

(test-equal "two engines on one thread, sharing a connection whose cache is warm, each running execute!, query and query-row on the same SQL, at every fuel from 1 until both complete without expiring: each answers rightly, and the cache and the statement count end where they began, three and three"
  '()
  (with-memory-db
   (lambda (db)
     (tier-run db "create table t (x)")
     (execute! db "insert into t values (?)" 0)
     (query db "select count(*) from t where x = ?" 0)
     (query-row db "select ?1 + 1" 0)
     (named "the two engines" (sweep (lambda (fuel) (two-engines db fuel)) 5000)))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "conveniences-engines")

(exit (suite-exit-status runner))
