#!r6rs
;;; The value verbs under engines (ADR-0014, decision 10; ADR-0015). Each
;;; verb's checks, its counts, its C calls and its block share one critical
;;; section, the accessor's, where an engine spends no ticks, so an expiry
;;; falls only before the section or after it. Sweeps of a first engine A
;;; that expires once, at every fuel from 1 to 60, and a second thread of
;;; control B that runs at A's first expiry, on the same thread; then A
;;; finishes:
;;;
;;;   bind against step       A binds a TEXT, B steps. B comes before A's
;;;                           section, and A is refused naming row, or after
;;;                           it, and the row reads the value: never a bind
;;;                           while a row is ready, which SQLite answers MISUSE
;;;   read against reset,     A reads a column, B resets or finalizes the
;;;   and finalize            statement: A reads the value, or is refused
;;;                           naming ready, or &sqlite-closed; never a read of a
;;;                           reset statement nor a freed one
;;;   read against a          A reads the third column, its value or its name,
;;;   dropped column          B resets, drops that column and steps: A reads
;;;                           it, or is refused by column-out-of-range, the
;;;                           count read with the read
;;;   a name changed          A binds by a name, B puts U+0000 into the
;;;                           caller's string: A binds the name it was given,
;;;                           or refuses it, never C's view of the change
;;;   bind-all! against close A binds both parameters, B closes the
;;;                           connection: A answers, or &sqlite-closed, and
;;;                           every count is zero after
;;;
;;; Each sweep's row asserts that its fuels reached B before A's section, B
;;; after it, and A finished before expiring, each at one fuel at least.
;;;
;;; And every verb under an engine of every fuel from 1 to 60 completes with
;;; its own answer: a block made outside its section, a name's C string or a
;;; TEXT's, would be freed at an expiry and its resume refused.
;;;
;;; Every computation that can raise runs under a guard with a sentinel of its
;;; own. Effects run in order, through let* and named lets (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) make-engine string-set!)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) sqlite-closed? sqlite-error? sqlite-error-code))

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

(define (reach library name)
  (guard (e (#t (lambda args (error name "could not be reached" library (describe e)))))
    (eval name (environment library))))

(define values-library '(chez-sqlite3 private statement-values))
(define statement-library '(chez-sqlite3 private statement))
(define open-database (reach '(chez-sqlite3) 'open-database))
(define close-database! (reach '(chez-sqlite3) 'close-database!))
(define prepare-statement (reach statement-library 'prepare-statement))
(define finalize-statement! (reach statement-library 'finalize-statement!))
(define step! (reach statement-library 'step!))
(define reset! (reach statement-library 'reset!))
(define statement-state (reach statement-library 'statement-state))
(define bind! (reach values-library 'bind!))
(define bind-all! (reach values-library 'bind-all!))
(define clear-bindings! (reach values-library 'clear-bindings!))
(define column-value (reach values-library 'column-value))
(define column-bytevector (reach values-library 'column-bytevector))
(define column-name (reach values-library 'column-name))
(define sql-null (guard (e (#t (list 'unreachable 'sql-null)))
                   (eval 'sql-null (environment '(chez-sqlite3 private values)))))

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))
(define one-connection '((block . 0) (connection . 1) (statement . 0)))

;; what-raised : Any -> Any
(define (what-raised e)
  (cond ((sqlite-closed? e) (list 'closed (if (who-condition? e) (condition-who e) 'no-who)))
        ((sqlite-error? e) (list 'sqlite-error (sqlite-error-code e)))
        ((assertion-violation? e)
         (list 'assertion-violation (if (who-condition? e) (condition-who e) 'no-who)
               (if (irritants-condition? e) (condition-irritants e) 'no-irritants)))
        (else (list 'other (describe e)))))

;; attempt : (-> Any) -> Any
(define (attempt thunk)
  (guard (e (#t (list 'raised (what-raised e))))
    (thunk)))

(define void-value (if #f #f))
(define (no-value x) (if (eq? x void-value) 'no-value x))
(define (shown x) (if (and (not (pair? sql-null)) (eq? x sql-null)) 'sql-null x))

;; fuels : Positive-Integer -> (Listof Positive-Integer)
(define (fuels n)
  (let loop ((i n) (found '()))
    (if (= i 0) found (loop (- i 1) (cons i found)))))

;; finish! : (U Engine #f) -> Void
(define (finish! e)
  (let loop ((e e) (n 0))
    (when (and e (< n 100000))
      (loop (e 1000000 (lambda (left . v) #f) (lambda (next) next)) (+ n 1)))))

;; interleave : (-> Any) (-> Any) Positive-Integer -> (List Any Any)
;; A's thunk run in an engine of FUEL ticks; at its first expiry B's thunk
;; runs, on this thread, once; then A finishes. A's answer, or
;; 'a-not-finished, and B's, or 'a-finished-first when A completed before
;; it expired.
(define (interleave a-thunk b-thunk fuel)
  (let* ((a-answer 'a-not-finished)
         (a (make-engine (lambda () (set! a-answer (no-value (attempt a-thunk))) 'a)))
         (a2 (a fuel (lambda (left . v) #f) (lambda (next) next)))
         (b (if a2 (no-value (attempt b-thunk)) 'a-finished-first)))
    (finish! a2)
    (list a-answer b)))

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

(define (exec! db sql)
  (let ((st (prepare-statement db sql)))
    (step! st)
    (finalize-statement! st)))

;; sweep : (Positive-Integer -> Any) -> (Listof (List Positive-Integer Any))
;; PROC at each fuel from 1 to 60, under a guard, first to last.
(define (sweep proc)
  (let loop ((rest (fuels 60)) (found '()))
    (if (null? rest)
        (reverse found)
        (let ((r (list (car rest) (attempt (lambda () (proc (car rest)))))))
          (loop (cdr rest) (cons r found))))))

;; the kinds of interleaving a sweep's fuels must reach, each at one fuel
;; at least: B before A's section, B after it, and A finished before its
;; first expiry. A sweep whose A always finished first would hold nothing.
(define kinds '(a-first b-after b-before))

;; summary : (Listof (List Positive-Integer Any)) -> (List Any (Listof Symbol))
;; every-fuel-ok, or the fuels whose outcome was no kind; and the kinds the
;; fuels reached, in kinds' order.
(define (summary results)
  (let ((wrong (filter (lambda (r) (not (memq (cadr r) kinds))) results)))
    (list (if (null? wrong) 'every-fuel-ok wrong)
          (filter (lambda (k) (exists (lambda (r) (eq? (cadr r) k)) results)) kinds))))

(define all-ok (list 'every-fuel-ok kinds))

(define (not-allowed who state) (list 'raised (list 'assertion-violation who (list 'not-allowed-in-state state))))

(test-begin "statement-values-sections")

;; --- bind against step -------------------------------------------------------------------

;; bind-vs-step : Positive-Integer -> Any
;; ok when A's bind came wholly before B's step, and the row reads x; or
;; after it, refused naming row, and the row reads NULL; or A finished first.
(define (bind-vs-step fuel)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select ?1"))
            (r (interleave (lambda () (bind! st 1 "x")) (lambda () (step! st)) fuel))
            (a (car r))
            (b (cadr r))
            (state (statement-state st))
            (v (if (eq? state 'row) (shown (attempt (lambda () (column-value st 0)))) 'no-row))
            (counts (native-counts)))
       (finalize-statement! st)
       (cond ((and (eq? b 'a-finished-first) (eq? a 'no-value) (eq? state 'ready)) 'a-first)
             ((and (eq? b #t) (eq? a 'no-value) (equal? v "x")) 'b-after)
             ((and (eq? b #t) (equal? a (not-allowed 'bind! 'row)) (eq? v 'sql-null)) 'b-before)
             (else (list 'wrong a b state v counts)))))))

(test-equal "bind against step, at every fuel from 1 to 60: the bind is wholly before the step, and the row reads its value, or after it, refused naming row, the row reading NULL; never a bind while a row is ready"
  all-ok
  (summary (sweep bind-vs-step)))

;; --- read against reset and finalize ---------------------------------------------------------

;; read-vs : Symbol Positive-Integer -> Any
;; ok when A read abc, or was refused naming ready after B's reset, or
;; raised &sqlite-closed after B's finalize.
(define (read-vs b-kind fuel)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select 'abc'"))
            (s (step! st))
            (r (interleave (lambda () (column-value st 0))
                           (lambda () (if (eq? b-kind 'reset) (reset! st) (finalize-statement! st)))
                           fuel))
            (a (car r))
            (b (cadr r))
            (state (statement-state st)))
       (finalize-statement! st)
       (cond ((and (eq? b 'a-finished-first) (equal? a "abc")) 'a-first)
             ((and (eq? b 'no-value) (equal? a "abc")) 'b-after)
             ((and (eq? b-kind 'reset) (eq? b 'no-value) (equal? a (not-allowed 'column-value 'ready)))
              'b-before)
             ((and (eq? b-kind 'finalize) (eq? b 'no-value)
                   (equal? a '(raised (closed column-value))))
              'b-before)
             (else (list 'wrong a b state)))))))

(test-equal "a read against a reset, at every fuel from 1 to 60: it reads abc, or is refused naming ready; never a read of a reset statement"
  all-ok
  (summary (sweep (lambda (fuel) (read-vs 'reset fuel)))))

(test-equal "a read against a finalize, at every fuel from 1 to 60: it reads abc, or raises &sqlite-closed; never a read of a freed statement"
  all-ok
  (summary (sweep (lambda (fuel) (read-vs 'finalize fuel)))))

;; read-vs-drop : Symbol Positive-Integer -> Any
;; READ, column-value or column-name, of the third column: ok when A read
;; it, 3 or its name c, before B's reset, drop and step, or was refused
;; after them by column-out-of-range, 2 of 2: the count read in the read's
;; own section.
(define (read-vs-drop read fuel)
  (with-memory-db
   (lambda (db)
     (exec! db "create table d (a, b, c)")
     (exec! db "insert into d values (1, 2, 3)")
     (let* ((st (prepare-statement db "select * from d"))
            (s (step! st))
            (r (interleave (lambda () (if (eq? read 'column-name) (column-name st 2) (column-value st 2)))
                           (lambda ()
                             (reset! st)
                             (exec! db "alter table d drop column c")
                             (step! st))
                           fuel))
            (a (car r))
            (b (cadr r)))
       (finalize-statement! st)
       (cond ((and (eq? b 'a-finished-first) (equal? a (if (eq? read 'column-name) "c" 3))) 'a-first)
             ((and (eq? b #t) (equal? a (if (eq? read 'column-name) "c" 3))) 'b-after)
             ((and (eq? b #t)
                   (equal? a (list 'raised (list 'assertion-violation read '(column-out-of-range 2 2)))))
              'b-before)
             (else (list 'wrong (shown a) b)))))))

(test-equal "a read of the third column against a reset, a drop column and a step, at every fuel from 1 to 60: it reads 3, or is refused 2 of 2; never a read past the count"
  all-ok
  (summary (sweep (lambda (fuel) (read-vs-drop 'column-value fuel)))))

(test-equal "column-name of the third column against a reset, a drop column and a step, at every fuel from 1 to 60: it reads c, or is refused 2 of 2; never a name past the count"
  all-ok
  (summary (sweep (lambda (fuel) (read-vs-drop 'column-name fuel)))))

;; --- a name changed while bind! runs --------------------------------------------------------------

;; name-vs-change : Positive-Integer -> Any
;; A binds :ab by a string of the caller's, B puts U+0000 into that string.
;; bind! copies a name before it checks it, and checks and uses only the
;; copy, so ok when A bound :ab, read back as 1, or was refused by
;; parameter-name-holds-nul when B came before the copy; never a refusal of
;; C's, made of a string changed after it was checked.
(define (name-vs-change fuel)
  (with-memory-db
   (lambda (db)
     (let* ((st (prepare-statement db "select :ab"))
            (name (string-copy ":ab"))
            (r (interleave (lambda () (bind! st name 1)) (lambda () (string-set! name 1 #\nul)) fuel))
            (a (car r))
            (b (cadr r))
            (s (step! st))
            (v (shown (column-value st 0))))
       (finalize-statement! st)
       (cond ((and (eq? b 'a-finished-first) (eq? a 'no-value) (eqv? v 1)) 'a-first)
             ((and (eq? a 'no-value) (eqv? v 1)) 'b-after)
             ((and (equal? a '(raised (assertion-violation bind! (parameter-name-holds-nul (kind string)))))
                   (eq? v 'sql-null))
              'b-before)
             (else (list 'wrong a b v)))))))

(test-equal "a name another engine changes while bind! runs, at every fuel from 1 to 60: bind! binds the name it was given, or refuses it by parameter-name-holds-nul; never C's view of a changed string"
  all-ok
  (summary (sweep name-vs-change)))

;; --- bind-all! against close ------------------------------------------------------------------

;; bind-all-vs-close : Positive-Integer -> Any
;; ok when the close answered and A answered, or raised &sqlite-closed; the
;; connection then closed, a second close doing nothing, and every count zero.
(define (bind-all-vs-close fuel)
  (let* ((db (open-database ":memory:"))
         (st (prepare-statement db "select ?1, ?2")))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let* ((r (interleave (lambda () (bind-all! st 1 "two")) (lambda () (close-database! db)) fuel))
               (a (car r))
               (b (cadr r))
               (closing (attempt (lambda () (close-database! db) 'closed)))
               (state (statement-state st))
               (counts (native-counts)))
          (cond ((not (and (memq b '(no-value a-finished-first)) (eq? closing 'closed)
                           (eq? state 'finalized) (equal? counts zero-counts)))
                 (list 'wrong 'close a b closing state counts))
                ((and (eq? b 'a-finished-first) (eq? a 'no-value)) 'a-first)
                ((eq? a 'no-value) 'b-after)
                ((equal? a '(raised (closed bind-all!))) 'b-before)
                (else (list 'wrong 'a a b)))))
      (lambda () (undo! (list st) (list db))))))

(test-equal "bind-all! against a close, at every fuel from 1 to 60: it answers or raises &sqlite-closed, never binding a freed statement; the connection is closed and every count zero"
  all-ok
  (summary (sweep bind-all-vs-close)))

;; --- every verb under an engine -----------------------------------------------------------------

;; under-engine : Database Positive-Integer -> Any
;; Every verb run in an engine of FUEL ticks a slice, resumed each time it
;; expires until it completes: their answers, and whether it expired.
(define (under-engine db fuel)
  (let loop ((engine (make-engine
                      (lambda ()
                        (attempt
                         (lambda ()
                           (let* ((st (prepare-statement db "select :name, ?2, ?3"))
                                  (a (no-value (bind! st ":name" "\xE9;t\xE9;")))
                                  (b (no-value (clear-bindings! st)))
                                  (c (no-value (bind-all! st "x" #vu8(1 2) 2.5)))
                                  (s (step! st))
                                  (d (column-value st 0))
                                  (e (column-bytevector st 1))
                                  (f (column-value st 2))
                                  (g (column-name st 0))
                                  (h (begin (reset! st) (no-value (bind! st ":name" "\xE9;t\xE9;"))))
                                  (s2 (step! st))
                                  (i (column-value st 0)))
                             (finalize-statement! st)
                             (list a b c d e f g h i)))))))
             (expired 0))
    (if (>= expired 100000)
        (list 'unfinished expired)
        (engine fuel
                (lambda (left . answers) (list (car answers) (if (> expired 0) 'expired 'never-expired)))
                (lambda (next) (loop next (+ expired 1)))))))

(test-equal "every verb under an engine of every fuel from 1 to 60 ticks a slice completes with its own answer, a name and a TEXT bound and read back; the engine of 1 tick expired; only the connection is counted after"
  (list (map (lambda (fuel) (list fuel '(no-value no-value no-value "x" #vu8(1 2) 2.5 ":name" no-value "\xE9;t\xE9;")))
             (fuels 60))
        'expired one-connection)
  (with-memory-db
   (lambda (db)
     (let loop ((rest (fuels 60)) (found '()))
       (if (null? rest)
           (let ((at-one (under-engine db 1)))
             (list (reverse found)
                   (if (and (pair? at-one) (pair? (cdr at-one))) (cadr at-one) at-one)
                   (native-counts)))
           (let ((run (under-engine db (car rest))))
             (loop (cdr rest) (cons (list (car rest) (car run)) found))))))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "statement-values-sections")

(exit (suite-exit-status runner))
