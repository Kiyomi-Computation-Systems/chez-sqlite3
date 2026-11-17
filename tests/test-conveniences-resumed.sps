#!r6rs
;;; The suite for a convenience re-entered after its statement has left it
;;; (ADR-0016, decision 6; ADR-0020, decision 7; the maintainer's choice of
;;; 2026-11-16, after M3 slice 3's review), in (chez-sqlite3 private
;;; conveniences). Chez's engine remainders are multi-shot, and a timer's,
;;; keyboard's or collect request's handler can capture a continuation
;;; between any two critical sections. So each call of a convenience holds a
;;; flag, set once its statement leaves the call, given back to the cache or
;;; finalized, and every section that touches the statement reads it first:
;;; set, the section touches nothing, and the convenience raises
;;; &sqlite-closed after it.
;;;
;;;   resumed twice   for execute!, query and query-row, at every fuel from 1
;;;                   until the call completes without expiring: an engine's
;;;                   remainder, resumed to its end, then resumed again,
;;;                   warm, while another engine holds the statement at its
;;;                   row; and cold, alone. A remainder taken while the call
;;;                   held its statement raises &sqlite-closed the second time;
;;;                   any other raises it or answers again, touching nothing.
;;;                   One taken inside the library's own wind, the
;;;                   call-with-open-handle a check-out runs in, is refused by
;;;                   that wind, re-entered, before any flag is read
;;;                   The other engine answers its own rows, and the cache ends
;;;                   holding the one statement, ready
;;;   a failed return query-row's return failing, its reset of an insert ...
;;;                   returning answering busy under another's read: the
;;;                   failure has set the flag, so a remainder resumed again
;;;                   raises &sqlite-closed, never the row of the insert the
;;;                   failure rolled back
;;;   the fold        query-fold's remainder resumed twice, at every fuel: an
;;;                   expiry before the hand-over leaves the fold to complete,
;;;                   one inside its wind finalizes the statement; the second
;;;                   resume raises &sqlite-closed or answers again, touching
;;;                   nothing; no statement is left out of the cache or at a
;;;                   row
;;;   the timer       a timer handler captures a continuation at every tick of
;;;                   a fold, and the row re-enters each, with the statement
;;;                   cached, then while the suite holds it at its row: none
;;;                   that the fold had begun calls the procedure again or
;;;                   touches the statement
;;;   the script      execute-script!'s remainder resumed twice: one taken
;;;                   before the script's block refuses, &sqlite-closed, rather
;;;                   than running the script again; one inside it is refused
;;;                   by the block's own wind, re-entered
;;;
;;; A remainder taken before the call's first expression is the caller's own:
;;; resumed again, it makes a whole new call, with a flag of its own. The rows
;;; tell those apart by what they touch, and by the fuel. Each fuel begins
;;; with a collection, so a remainder lies further into the call at each
;;; fuel than at the one before, and a remainder taken past the call's first
;;; expression and before its first section is refused, &sqlite-closed: so
;;; a whole new call, which for execute!, query and query-row answers again
;;; as a remainder past the return does, touching nothing the rows read, must
;;; lie below the first such refusal. A bound from the call refused at its
;;; first check, slice 3's, was loose: its raise costs ticks of its own, and
;;; it completed at fuel 75, the script's whole new calls ending at 7 (M3's
;;; closing review, reviewer B).
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
        (only (chezscheme) make-engine set-timer timer-interrupt-handler collect collect-trip-bytes)
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
(define values-library '(chez-sqlite3 private statement-values))
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
(define checked-out (reach statement-library 'checked-out))
(define returned (reach statement-library 'returned))
(define bind-all! (reach values-library 'bind-all!))
(define column-value (reach values-library 'column-value))
(define made-claim (reach conveniences 'made-claim))

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

(define (closed name) (list 'raised (list 'closed name)))

;; re-entered : Symbol -> Any
;; What call-with-open-handle's, or call-with-block's, refusal of a re-entry
;; looks like, from NAME.
(define (re-entered name) (list 'raised (list 'assertion-violation name '(re-entered))))

(define (statement-count) (cdr (assq 'statement (native-counts))))

;; states : Database -> (Listof (Pairof String Symbol))
(define (states db)
  (list-sort (lambda (a b) (string<? (car a) (car b)))
             (let loop ((rest (tracked-statements db)) (found '()))
               (if (null? rest)
                   found
                   (loop (cdr rest)
                         (cons (cons (statement-sql (car rest)) (statement-state (car rest))) found))))))

;; tier-run : Database String -> (Listof Any)
;; SQL run through M2's statement tier: each row's first column, in order.
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

;; with-fresh : (Database -> Any) -> Any
;; PROC's answer, or what it raised, given a fresh :memory: database holding
;; table n, its rows 1, 2 and 3, and table s, empty; closed after.
(define (with-fresh proc)
  (let ((db #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (attempt (lambda ()
                   (set! db (open-database ":memory:"))
                   (tier-run db "create table n (x)")
                   (tier-run db "insert into n values (1), (2), (3)")
                   (tier-run db "create table s (x)")
                   (proc db))))
      (lambda () (when db (guard (e (#t #f)) (close-database! db)))))))

;; quieted! : -> Void
;; A collection now, at a fuel's start, with collect-trip-bytes raised to
;; 128 MiB, far above what one fuel's runs allocate, so no collect request
;; falls in a fuel's runs: one costs a run up to a tick
;; (.plans/research/m3-slice-5/, gc-ticks.sps), and the bound below reads
;; the fuels in order.
(define (quieted!)
  (collect-trip-bytes (expt 2 27))
  (collect))

;; summarized : (Listof Any) -> Any
;; () for no deviation; else how many, and the first three.
(define (summarized deviations)
  (if (null? deviations)
      '()
      (list (length deviations)
            (let loop ((rest deviations) (n 0) (kept '()))
              (if (or (null? rest) (= n 3)) (reverse kept) (loop (cdr rest) (+ n 1) (cons (car rest) kept)))))))

;; --- engines ------------------------------------------------------------------------------

;; slice : Engine Positive-Integer -> (U (List 'completed Any) (List 'expired Engine))
(define (slice e fuel)
  (e fuel (lambda (left . vals) (list 'completed (car vals))) (lambda (more) (list 'expired more))))

;; finish : Engine -> Any
;; E's answer, resumed with a large fuel until it completes, at most 1000
;; times.
(define (finish e)
  (let loop ((e e) (n 0))
    (let ((r (slice e 1000000)))
      (cond ((eq? (car r) 'completed) (cadr r))
            ((>= n 1000) 'never-completed)
            (else (loop (cadr r) (+ n 1)))))))

;; until-holding : Engine (-> Boolean) -> (U Engine #f)
;; E resumed one tick at a time until it expires with HOLDING? true: its
;; remainder; #f when it completes first, or after 100000 ticks.
(define (until-holding e holding?)
  (let loop ((e e) (n 0))
    (let ((r (slice e 1)))
      (cond ((eq? (car r) 'completed) #f)
            ((holding?) (cadr r))
            ((>= n 100000) #f)
            (else (loop (cadr r) (+ n 1)))))))

;; sweep : (Positive-Integer -> (List Boolean Boolean (Listof Any))) -> (List Any (Listof Any) Natural)
;; CHECK at each fuel from 1 until the call completes without expiring, at
;; most 5000: that fuel, or no-completion; each fuel's deviations, in order;
;; and how many fuels CHECK found the call holding its statement at the
;; expiry. CHECK answers whether the call expired, whether it held its
;; statement then, and what deviated.
(define (sweep check)
  (let loop ((fuel 1) (deviations '()) (held 0))
    (let* ((r (check fuel))
           (deviations (if (null? (caddr r)) deviations (cons (cons fuel (caddr r)) deviations)))
           (held (if (cadr r) (+ held 1) held)))
      (cond ((not (car r)) (list fuel (reverse deviations) held))
            ((>= fuel 5000) (list 'no-completion-by-5000 (reverse deviations) held))
            (else (loop (+ fuel 1) deviations held))))))

;; named : String (List Any (Listof Any) Natural) -> (List Any Any)
;; RUN's deviations, summarized, and whether it held its statement at some
;; fuel; its completing fuel printed, naming WHAT.
(define (named what run)
  (display "  ")
  (display what)
  (if (integer? (car run))
      (begin (display " completed without expiring at fuel ") (display (car run)))
      (begin (display ": ") (write (car run))))
  (newline)
  (list (if (integer? (car run)) (summarized (cadr run)) (list (car run) (summarized (cadr run))))
        (if (> (caddr run) 0) 'held-at-some-fuel 'never-held)))

;; --- the claim, pure -------------------------------------------------------------------------
;; execute!, query and query-row each hold a claim, made-claim's, made by the
;; call's first expression. The sweeps below and (conveniences-pending)'s
;; hold it through the calls; a claim taken again once its call has ended,
;; position 0 above all, which any remainder taken before the check-out
;; carries, passed them all (M3's closing review, reviewer B's N1: execute!'s
;; remainder at fuels 8 to 14, resumed twice, inserted twice). So these rows
;; hold it whole.

;; claimed : (Listof (List (U Natural #f) Boolean)) -> (Listof Boolean)
;; A fresh claim given each of STEPS, a position and LAST?, in order: what
;; it answered each time.
(define (claimed steps)
  (let ((claim (made-claim)))
    (let loop ((rest steps) (found '()))
      (if (null? rest)
          (reverse found)
          (loop (cdr rest) (cons (claim (car (car rest)) (cadr (car rest))) found))))))

;; after-the-end : (Listof (List (U Natural #f) Boolean))
;; Every kind of claim a run can make once its call has ended: position 0,
;; the check-out's; one the call made; one past it; none, #f, a raise's
;; give-back; each with LAST? and without.
(define after-the-end
  '((0 #f) (0 #t) (1 #f) (2 #f) (3 #f) (4 #f) (4 #t) (#f #f) (#f #t) (0 #f)))

(define (refusals steps) (let loop ((rest steps) (found '())) (if (null? rest) found (loop (cdr rest) (cons #f found)))))

(test-equal "a call's claim, made-claim's, claims each position once, in order, the next whatever it is when given none, and ends at its last: 0, then 0 again refused, 2 refused before 1, 1, none claiming 2, 2 refused, then 3 as the last; once ended, every position is refused, 0 and none included, by a run carrying any"
  (append '(#t #f #f #t #t #f #t) (refusals after-the-end))
  (guard (e (#t (list 'raised (what-raised e))))
    (claimed (append '((0 #f) (0 #f) (2 #f) (1 #f) (#f #f) (2 #f) (3 #t)) after-the-end))))

(test-equal "a claim ended by a raise's give-back, a claim of none as the last, and one ended at its first section: each then refuses every position, 0 included"
  (list (append '(#t #t) (refusals after-the-end))
        (append '(#t) (refusals after-the-end)))
  (guard (e (#t (list 'raised (what-raised e))))
    (let* ((given-back (claimed (append '((0 #f) (#f #t)) after-the-end)))
           (at-first (claimed (append '((0 #t)) after-the-end))))
      (list given-back at-first))))

;; --- execute!, query and query-row: a remainder resumed twice ---------------------------------

(define X "select x + ?1 from n order by x")

;; resumed-twice : Symbol (Database Integer -> Any) Any Any Boolean Positive-Integer
;;                 -> (List Boolean Boolean (Listof Any) (U 'again 'refused #f))
;; On a fresh database, RUN with 10 as an engine, E1, one slice of FUEL:
;; whether it expired; whether it then held its statement, checked out of
;; the cache; what deviated; and, for a remainder taken while the call did
;; not hold its statement, again when its second resume answered MINE,
;; refused when it raised &sqlite-closed, else #f. Expired, its remainder is resumed to its
;; end, answering FIRST, due MINE; then, when WARM, the cache warmed by RUN
;; with 0 before E1, a second engine, E2, RUN with 20, is run a tick at a
;; time until it holds the statement at its row; then E1's remainder is
;; resumed again, answering SECOND: &sqlite-closed when E1 held its
;; statement, else that or MINE again; or, taken inside the library's own
;; wind, its refusal, re-entered; then E2 is resumed to its end, due
;; THEIRS. The cache ends holding the one statement, ready, and counted.
(define (resumed-twice name run mine theirs warm fuel)
  (let ((outcome
         (with-fresh
          (lambda (db)
            (when warm (run db 0))
            (let ((r (slice (make-engine (lambda () (attempt (lambda () (no-value (run db 10)))))) fuel)))
              (if (eq? (car r) 'completed)
                  (list #f #f (if (equal? (cadr r) mine) '() (list (list 'completed (cadr r)))) #f)
                  (let* ((more (cadr r))
                         (held (and (= (database-cache-count db) 0) (= (length (tracked-statements db)) 1)))
                         (first (finish more))
                         (other (and warm
                                     (until-holding
                                      (make-engine (lambda () (attempt (lambda () (no-value (run db 20))))))
                                      (lambda () (and (= (database-cache-count db) 0)
                                                      (equal? (states db) (list (cons X 'row))))))))
                         (second (finish more))
                         (theirs-answer (cond ((not warm) 'none) (other (finish other)) (else 'never-held-at-a-row)))
                         (end (list (states db) (database-cache-count db) (statement-count))))
                    (list #t held
                          (append (if (equal? first mine) '() (list (list 'first first)))
                                  (if (or (member second (list (closed name) (re-entered name)))
                                          (and (not held) (equal? second mine)))
                                      '()
                                      (list (list 'second (if held 'held 'not-held) second)))
                                  (if (or (not warm) (equal? theirs-answer theirs)) '() (list (list 'theirs theirs-answer)))
                                  (if (equal? end (list (list (cons X 'ready)) 1 1)) '() (list (list 'end end))))
                          (cond (held #f)
                                ((equal? second mine) 'again)
                                ((equal? second (closed name)) 'refused)
                                (else #f))))))))))
    (if (and (pair? outcome) (eq? (car outcome) 'raised))
        (list #f #f (list outcome) #f)
        outcome)))

;; bounded : (Positive-Integer -> (List Boolean Boolean (Listof Any) (U 'again 'refused #f)))
;;           -> (List Any (Listof Any) Natural Any)
;; CHECK, resumed-twice's, swept as sweep sweeps it, each fuel begun by
;; quieted!, and the sweep's answers with one more: whether every second
;; resume that answered again, of a remainder taken while the call did not
;; hold its statement, lies below the first fuel whose remainder, taken
;; before the check-out, was refused, a whole new call, or past the last
;; fuel at which the call held its statement, past the return; and whether
;; that refusal came before the first fuel at which the call held its
;; statement. A claim taken again once its call had ended, by a remainder
;; between the call's first expression and its check-out, answered again
;; there, and passed every row of this suite (M3's closing review,
;; reviewer B's N1).
(define (bounded check)
  (let ((refused-at #f) (first-held #f) (last-held #f) (again '()))
    (let ((run (sweep (lambda (fuel)
                        (quieted!)
                        (let ((r (check fuel)))
                          (when (cadr r)
                            (unless first-held (set! first-held fuel))
                            (set! last-held fuel))
                          (case (cadddr r)
                            ((refused) (unless refused-at (set! refused-at fuel)))
                            ((again) (set! again (cons fuel again))))
                          (list (car r) (cadr r) (caddr r)))))))
      (display "  refused before the check-out first at fuel ")
      (write refused-at)
      (display "; the statement held at fuels ")
      (write first-held)
      (display " to ")
      (write last-held)
      (display "; answered again at fuels ")
      (write (reverse again))
      (newline)
      (append run
              (list (cond ((not (and refused-at first-held (< refused-at first-held)))
                           (list 'no-refusal-before-the-check-out refused-at first-held))
                          ((exists (lambda (f) (< refused-at f last-held)) again)
                           (list 'answered-again-inside-the-call
                                 (filter (lambda (f) (< refused-at f last-held)) (reverse again))
                                 refused-at last-held))
                          (else 'answered-again-only-before-a-refusal-or-past-the-return)))))))

;; both-ways : Symbol String (Database Integer -> Any) Any Any -> (List Any Any Any Any Any Any)
(define (both-ways name what run mine theirs)
  (let* ((warm (bounded (lambda (fuel) (resumed-twice name run mine theirs #t fuel))))
         (cold (bounded (lambda (fuel) (resumed-twice name run mine theirs #f fuel)))))
    (append (named (string-append what ", warm, another engine holding its statement at a row") warm)
            (list (cadddr warm))
            (named (string-append what ", cold, alone") cold)
            (list (cadddr cold)))))

(define resumed-expected
  (list '() 'held-at-some-fuel 'answered-again-only-before-a-refusal-or-past-the-return
        '() 'held-at-some-fuel 'answered-again-only-before-a-refusal-or-past-the-return))

(test-begin "conveniences-resumed")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-equal "query, an engine's remainder resumed twice, at every fuel from 1 until it completes without expiring, warm while another engine holds the statement at its row, and cold alone: the first resume answers its rows; the second, of a remainder taken while it held its statement, raises &sqlite-closed, or re-entered inside the library's own wind, and of any other raises one of those or answers again, only below the first fuel at which one taken before the check-out was refused, or past the return; the other engine answers its own rows; the cache ends holding the one statement, ready"
  resumed-expected
  (both-ways 'query "query" (lambda (db v) (query db X v))
             '(#(11) #(12) #(13)) '(#(21) #(22) #(23))))

(test-equal "query-row, an engine's remainder resumed twice, at every fuel until it completes without expiring, warm while another engine holds the statement at its row, and cold alone: the second resume of a remainder taken while it held its statement raises &sqlite-closed, or re-entered inside the library's own wind; one that answers again lies below the first fuel at which one taken before the check-out was refused, or past the return; the other engine answers its own first row; the cache ends holding the one statement, ready"
  resumed-expected
  (both-ways 'query-row "query-row" (lambda (db v) (query-row db X v)) '#(11) '#(21)))

(test-equal "execute!, an engine's remainder resumed twice, at every fuel until it completes without expiring, warm while another engine holds the statement at its row, and cold alone: the second resume of a remainder taken while it held its statement raises &sqlite-closed, or re-entered inside the library's own wind; one that answers again lies below the first fuel at which one taken before the check-out was refused, or past the return; the other engine runs its statement to its end; the cache ends holding the one statement, ready"
  resumed-expected
  (both-ways 'execute! "execute!" (lambda (db v) (no-value (execute! db X v))) 'no-value 'no-value))

;; --- query-row, its return failing: a remainder resumed twice ----------------------------------
;; A return that fails finalizes the statement, and has set the call's flag
;; all the same: the statement has left the call. query-row of a multi-row
;; insert ... returning, under another connection's read, answers its first
;; row, then its reset commits, answers busy, and rolls the insert back
;; (part A's busy-reset.sps).

(define returning "insert into t values (1), (2) returning x")

;; failed-return-resumed-twice : Positive-Integer -> (List Boolean Boolean (Listof Any))
;; On a fresh file holding t, x unique, its one row 0, and a second
;; connection holding a read of it, query-row of RETURNING as an engine,
;; one slice of FUEL: whether it expired; whether it then held its
;; statement; and what deviated. Its remainder resumed to its end raises
;; the reset's busy; resumed again, &sqlite-closed, or re-entered, and,
;; taken while the call did not hold its statement, the busy again, of the
;; same call's tail or of a whole new call; never the row. Nothing is left
;; tracked or cached, and t holds 0 alone.
(define (failed-return-resumed-twice fuel)
  (let ((outcome
         (guard (e (#t (list 'raised (what-raised e))))
           (call-with-temp-directory
            (lambda (dir)
              (let* ((path (string-append dir "/t.db"))
                     (db (open-database path))
                     (reader #f)
                     (held-read #f))
                (dynamic-wind
                  (lambda () #f)
                  (lambda ()
                    (tier-run db "create table t (x unique)")
                    (tier-run db "insert into t values (0)")
                    (set! reader (open-database path))
                    (set! held-read (prepare-statement reader "select x from t"))
                    (step! held-read)
                    (let* ((busy (list 'raised (list 'sqlite-error 'query-row 'busy 'busy returning #f)))
                           (r (slice (make-engine (lambda () (attempt (lambda () (query-row db returning))))) fuel)))
                      (if (eq? (car r) 'completed)
                          (list #f #f (if (equal? (cadr r) busy) '() (list (list 'completed (cadr r)))))
                          (let* ((more (cadr r))
                                 (held (and (= (database-cache-count db) 0) (= (length (tracked-statements db)) 1)))
                                 (first (finish more))
                                 (second (finish more))
                                 (end (list (states db) (database-cache-count db) (tier-run db "select x from t"))))
                            (list #t held
                                  (append (if (equal? first busy) '() (list (list 'first first)))
                                          (if (or (member second (list (closed 'query-row) (re-entered 'query-row)))
                                                  (and (not held) (equal? second busy)))
                                              '()
                                              (list (list 'second (if held 'held 'not-held) second)))
                                          (if (equal? end '(() 0 (0))) '() (list (list 'end end)))))))))
                  (lambda ()
                    (when held-read (guard (e (#t #f)) (finalize-statement! held-read)))
                    (when reader (guard (e (#t #f)) (close-database! reader)))
                    (guard (e (#t #f)) (close-database! db))))))))))
    (if (and (pair? outcome) (eq? (car outcome) 'raised))
        (list #f #f (list outcome))
        outcome)))

(test-equal "query-row, its return failing, an engine's remainder resumed twice, at every fuel from 1 until it completes without expiring: an insert ... returning under another connection's read answers its row, then its reset answers busy, the insert rolled back; the second resume of a remainder taken while it held its statement raises &sqlite-closed, or re-entered, never the row again, the failed return having set the flag; nothing is left tracked or cached"
  (list '() 'held-at-some-fuel)
  (named "query-row, its return failing, resumed twice" (sweep failed-return-resumed-twice)))

;; --- query-fold: a remainder resumed twice ----------------------------------------------------

(define (sum acc row) (+ acc (vector-ref row 0)))

;; fold-resumed-twice : Positive-Integer -> (List Boolean Boolean (Listof Any))
;; On a fresh database whose cache holds X's statement, query-fold of X with
;; 10 as an engine, one slice of FUEL: whether it expired; whether its
;; statement was then finalized, an expiry inside the fold's wind having
;; finished it, or else cached, ready, the expiry before the hand-over or
;; after the return; and what deviated. Its remainder resumed to its end
;; answers the fold, 36, when the statement was cached, and &sqlite-closed
;; when it was finalized, or 36 when the expiry fell past the loop's last
;; section, the fold done; resumed again, &sqlite-closed, or the library's
;; own wind's re-entered, or 36 again where the first resume answered it.
;; The cache ends as the first resume left it: holding the one statement,
;; ready, or none.
(define (fold-resumed-twice fuel)
  (let ((outcome
         (with-fresh
          (lambda (db)
            (query-fold db X sum 0 0)
            (let ((r (slice (make-engine (lambda () (attempt (lambda () (query-fold db X sum 0 10))))) fuel)))
              (if (eq? (car r) 'completed)
                  (list #f #f (if (equal? (cadr r) 36) '() (list (list 'completed (cadr r)))))
                  (let* ((more (cadr r))
                         (finalized (and (= (database-cache-count db) 0) (null? (states db))))
                         (cached (and (= (database-cache-count db) 1) (equal? (states db) (list (cons X 'ready)))))
                         (first (finish more))
                         (second (finish more))
                         (end (list (states db) (database-cache-count db) (statement-count))))
                    (list #t finalized
                          (append (if (or finalized cached) '() (list (list 'phase (states db))))
                                  (if (or (equal? first 36) (and finalized (equal? first (closed 'query-fold))))
                                      '()
                                      (list (list 'first (if finalized 'finalized 'cached) first)))
                                  (if (or (member second (list (closed 'query-fold) (re-entered 'query-fold)))
                                          (and (equal? first 36) (equal? second 36)))
                                      '()
                                      (list (list 'second second)))
                                  (if (equal? end (if finalized '(() 0 0) (list (list (cons X 'ready)) 1 1)))
                                      '()
                                      (list (list 'end end))))))))))))
    (if (and (pair? outcome) (eq? (car outcome) 'raised))
        (list #f #f (list outcome))
        outcome)))

(test-equal "query-fold, an engine's remainder resumed twice, at every fuel from 1 until it completes without expiring: an expiry before the hand-over leaves the fold to complete, 36, and one inside its wind finalizes the statement, so the resume raises &sqlite-closed, unless the loop had done; the second resume raises &sqlite-closed, or re-entered inside the library's own wind, or answers 36 again where the first did; the cache ends holding the one statement, ready, or none, and nothing is left out of it"
  (list '() 'held-at-some-fuel)
  (named "query-fold, resumed twice" (sweep fold-resumed-twice)))

;; --- query-fold: every continuation a timer handler captured --------------------------------
;; A timer handler is the caller's code, and runs between any two critical
;; sections: it captures a continuation at every tick of a normal fold, with
;; the phase it was taken in. Every one is re-entered after the fold has
;; returned, first while the cache holds the statement, then while the suite
;; holds it, checked out, at its first row, 101. A continuation taken before
;; the hand-over, head, raises &sqlite-closed, or re-entered inside the
;; check-out's own wind, or, taken before the call's
;; first expression, makes a whole new fold: 36, the procedure called three
;; times. One taken while the fold held its statement, held, raises
;; &sqlite-closed, or call-with-open-handle's re-entered, or, past the
;; fold's last section, answers 36 again; one after the return, tail, answers
;; 36 again. None but a whole new fold calls the procedure: a call is counted
;; by the row it is given, a fresh vector each, so a continuation taken
;; inside the procedure, re-entered, finishes that call, and calls nothing.

;; timer-reentries : Database -> (List Any Natural (Listof (List Symbol Any Natural)) (Listof ...) Any Any)
(define (timer-reentries db)
  (let ((rows (make-eq-hashtable)) (capturing #f) (saved '()) (return-to #f)
        (old (timer-interrupt-handler)))
    ;; calls : -> Natural
    ;; How many calls of the procedure the folds made: the rows it was given.
    (define (calls) (hashtable-size rows))
    (define (counted acc row) (hashtable-set! rows row #t) (sum acc row))
    (define (phase)
      (cond ((= (database-cache-count db) 0) 'held)
            ((= (calls) 0) 'head)
            (else 'tail)))
    (define (fold-once)
      (set! capturing #t)
      (set-timer 1)
      (let ((r (attempt (lambda () (query-fold db X counted 0 10)))))
        (set! capturing #f)
        (set-timer 0)
        (if return-to (return-to r) r)))
    (define (re-enter-each)
      (let loop ((rest (reverse saved)) (outcomes '()))
        (if (null? rest)
            (reverse outcomes)
            (let* ((before (calls))
                   (r (call/cc (lambda (back) (set! return-to back) ((car (car rest)) #f))))
                   (delta (- (calls) before)))
              (loop (cdr rest) (cons (list (cdr (car rest)) r delta) outcomes))))))
    (dynamic-wind
      (lambda ()
        (timer-interrupt-handler
         (lambda ()
           (when capturing
             (let ((now (phase)))
               (call/cc (lambda (k) (set! saved (cons (cons k now) saved))))
               (when capturing (set-timer 1)))))))
      (lambda ()
        (let* ((first (fold-once))
               (first-calls (calls))
               (cached-pass (re-enter-each))
               (held (checked-out 'the-suite db X #f #f))
               (bound (bind-all! held 100))
               (stepped (step! held))
               (held-pass (re-enter-each))
               (held-after (list (statement-state held) (column-value held 0)))
               (given-back (returned 'the-suite held)))
          (list first first-calls cached-pass held-pass held-after
                (list (states db) (database-cache-count db) (statement-count)))))
      (lambda ()
        (set! capturing #f)
        (set-timer 0)
        (timer-interrupt-handler old)))))

;; reentry-deviations : (Listof (List Symbol Any Natural)) -> (Listof Any)
(define (reentry-deviations outcomes)
  (filter (lambda (o)
            (let ((phase (car o)) (r (cadr o)) (delta (caddr o)))
              (not (case phase
                     ((head) (or (and (member r (list (closed 'query-fold) (re-entered 'query-fold))) (= delta 0))
                                 (and (equal? r 36) (= delta 3))))
                     ((held) (and (= delta 0)
                                  (or (equal? r (closed 'query-fold)) (equal? r (re-entered 'query-fold))
                                      (equal? r 36))))
                     (else (and (equal? r 36) (= delta 0)))))))
          outcomes))

;; refused-held : (Listof (List Symbol Any Natural)) -> Symbol
(define (refused-held outcomes)
  (if (exists (lambda (o) (and (eq? (car o) 'held) (equal? (cadr o) (closed 'query-fold)))) outcomes)
      'some-held-refused
      'no-held-refused))

(test-equal "query-fold re-entered through every continuation a timer handler captured at each tick of a normal fold, after it returned, the statement cached and then held by the suite at its row: none the fold had begun calls the procedure again or touches the statement; those it held raise &sqlite-closed or re-entered, or answer 36 again past its last section; the suite's statement stays at its first row, and the cache ends holding the one statement, ready"
  (list 36 3 '() 'some-held-refused '() 'some-held-refused '(row 101) (list (list (cons X 'ready)) 1 1))
  (let ((r (with-fresh
            (lambda (db)
              (query-fold db X sum 0 0)
              (timer-reentries db)))))
    (if (and (pair? r) (eq? (car r) 'raised))
        r
        (let ((cached-pass (caddr r)) (held-pass (cadddr r)))
          (display "  continuations captured: ")
          (display (length cached-pass))
          (newline)
          (list (car r) (cadr r)
                (summarized (reentry-deviations cached-pass)) (refused-held cached-pass)
                (summarized (reentry-deviations held-pass)) (refused-held held-pass)
                (list-ref r 4) (list-ref r 5))))))

;; --- execute-script!: a remainder resumed twice ----------------------------------------------

(define S "insert into s values (1); insert into s values (2); insert into s values (3)")

;; script-resumed-twice : Positive-Integer -> (List Boolean Boolean (Listof Any) Boolean Boolean)
;; On a fresh database, execute-script! of S as an engine, one slice of
;; FUEL: whether it expired; #f; what deviated; whether its second resume
;; made a whole new call; and whether it raised &sqlite-closed, the rows as
;; the first left them. Its remainder resumed to its end completes,
;; the rows (1 2 3), or is refused by the block's wind, re-entered, the
;; statements before the expiry standing. Resumed again, it raises
;; &sqlite-closed, or re-entered, or answers again past the block, each
;; leaving the rows as they were; or, taken before the call's first
;; expression, makes a whole new call, the script's rows twice.
(define (script-resumed-twice fuel)
  (let ((outcome
         (with-fresh
          (lambda (db)
            (let ((r (slice (make-engine (lambda () (attempt (lambda () (no-value (execute-script! db S)))))) fuel))
                  (rows (lambda () (tier-run db "select x from s order by x"))))
              (if (eq? (car r) 'completed)
                  (list #f #f (if (and (equal? (cadr r) 'no-value) (equal? (rows) '(1 2 3)))
                                  '()
                                  (list (list 'completed (cadr r) (rows))))
                        #f #f)
                  (let* ((more (cadr r))
                         (first (finish more))
                         (rows1 (rows))
                         (second (finish more))
                         (rows2 (rows))
                         (whole-new (and (equal? second 'no-value)
                                         (equal? rows2 (list-sort < (append rows1 '(1 2 3)))))))
                    (list #t #f
                          (append (if (or (and (equal? first 'no-value) (equal? rows1 '(1 2 3)))
                                          (and (equal? first (re-entered* 'execute-script!))
                                               (member rows1 '(() (1) (1 2) (1 2 3)))))
                                      '()
                                      (list (list 'first first rows1)))
                                  (if (or whole-new
                                          (and (member second (list (closed 'execute-script!)
                                                                    (re-entered* 'execute-script!)
                                                                    'no-value))
                                               (equal? rows2 rows1)))
                                      '()
                                      (list (list 'second second rows2)))
                                  (let ((counts (native-counts)))
                                    (if (equal? counts '((block . 0) (connection . 1) (statement . 0)))
                                        '()
                                        (list (list 'counts counts)))))
                          whole-new
                          (and (equal? second (closed 'execute-script!)) (equal? rows2 rows1))))))))))
    (if (and (pair? outcome) (eq? (car outcome) 'raised))
        (list #f #f (list outcome) #f #f)
        outcome)))

;; re-entered* : Symbol -> Any
;; call-with-block's refusal of a re-entry, from NAME, its irritants none.
(define (re-entered* name) (list 'raised (list 'assertion-violation name '())))

(test-equal "execute-script!, an engine's remainder resumed twice, at every fuel from 1 until it completes without expiring: the first resume completes or is refused by the block's wind; the second, of a remainder taken before the block, raises &sqlite-closed rather than running the script again, and of one inside the block is refused; a whole new call comes only from a remainder taken before the call's first expression, at a fuel below the first at which the second resume raised &sqlite-closed"
  (list '() 'whole-new-calls-only-below-a-refusal)
  (let* ((whole-new '())
         (refused-at #f)
         (run (sweep (lambda (fuel)
                       (quieted!)
                       (let ((r (script-resumed-twice fuel)))
                         (when (cadddr r) (set! whole-new (cons fuel whole-new)))
                         (when (and (car (cddddr r)) (not refused-at)) (set! refused-at fuel))
                         (list (car r) (cadr r) (caddr r)))))))
    (display "  execute-script!, resumed twice, completed without expiring at fuel ")
    (display (car run))
    (display "; whole new calls at fuels ")
    (write (reverse whole-new))
    (display "; refused with &sqlite-closed first at fuel ")
    (write refused-at)
    (newline)
    (list (if (integer? (car run)) (summarized (cadr run)) (list (car run) (summarized (cadr run))))
          (if (and refused-at (for-all (lambda (f) (< f refused-at)) whole-new))
              'whole-new-calls-only-below-a-refusal
              (list 'whole-new-calls-at (reverse whole-new) 'refused-first-at refused-at)))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "conveniences-resumed")

(exit (suite-exit-status runner))
