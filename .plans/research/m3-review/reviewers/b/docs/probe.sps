#!r6rs
;; M3 closing review, docs probe. Read-only against the library; files only
;; under build/m3cr-b/docs/.
(import (rnrs)
        (chez-sqlite3)
        (only (chezscheme) fork-thread make-mutex with-mutex make-condition condition-wait
              condition-signal make-time sleep current-time time-difference time-second
              time-nanosecond)
        (only (chez-sqlite3 private connection) database-cache-count database-cache-capacity))

(define (describe c)
  (cond ((sqlite-setting-mismatch? c)
         (list 'mismatch (sqlite-setting-mismatch-setting c) (sqlite-setting-mismatch-expected c)
               (sqlite-setting-mismatch-actual c)))
        ((sqlite-transaction-ended? c) 'ended)
        ((sqlite-closed? c) 'closed)
        ((sqlite-wrong-thread? c) 'wrong-thread)
        ((sqlite-error? c)
         (list 'sqlite (sqlite-error-code c) (sqlite-error-extended-code c) (sqlite-error-offset c)
               (sqlite-error-message c)))
        ((assertion-violation? c) (cons 'assert (if (irritants-condition? c) (condition-irritants c) '())))
        ((symbol? c) c)
        ((condition? c) (list 'condition (if (message-condition? c) (condition-message c) "")))
        (else (list 'other c))))

(define-syntax try
  (syntax-rules ()
    ((_ body ...) (guard (c (#t (list 'raised (describe c)))) (list 'ok (begin body ...))))))

(define (show label v) (write label) (display " => ") (write v) (newline))

(define (ms-since t0)
  (let ((d (time-difference (current-time) t0)))
    (+ (* 1000 (time-second d)) (div (time-nanosecond d) 1000000))))

(define (fresh path) (when (file-exists? path) (delete-file path)) path)

;; run-on-thread : (-> A) -> (U (List 'ok A) (List 'raised Any) 'timeout)
(define (run-on-thread thunk)
  (let ((m (make-mutex)) (cv (make-condition)) (result #f) (done #f))
    (fork-thread
     (lambda ()
       (let ((r (guard (c (#t (list 'raised (describe c)))) (list 'ok (thunk)))))
         (with-mutex m (set! result r) (set! done #t) (condition-signal cv)))))
    (with-mutex m
      (let loop ((k 0))
        (cond (done result)
              ((> k 100) 'timeout)
              (else (condition-wait cv m (make-time 'time-duration 100000000 0)) (loop (+ k 1))))))))

;; with-watchdog : Database (-> A) -> (List Outcome Natural Boolean)
;; THUNK run on this thread while another runs the doc's watchdog loop.
(define (with-watchdog db thunk)
  (let* ((m (make-mutex)) (cv (make-condition)) (finished #f) (exited #f)
         (done? (lambda () (with-mutex m finished))))
    (fork-thread
     (lambda ()
       (let loop ()
         (unless (done?)
           (interrupt-database! db)
           (sleep (make-time 'time-duration 1000000 0))
           (loop)))
       (with-mutex m (set! exited #t) (condition-signal cv))))
    (let* ((t0 (current-time))
           (r (try (thunk)))
           (ms (ms-since t0)))
      (with-mutex m (set! finished #t))
      (with-mutex m
        (let loop ((k 0))
          (unless (or exited (> k 50))
            (condition-wait cv m (make-time 'time-duration 100000000 0))
            (loop (+ k 1)))))
      (list r ms (with-mutex m exited)))))

(define long-count
  "with recursive c(x) as (select 1 union all select x + 1 from c where x < 300000000) select count(*) from c")

;; ===== A. settings refusals; nothing opened =====
(define nothing-path "build/m3cr-b/docs/p-nothing.db")
(define (opened-with . args)
  (fresh nothing-path)
  (let* ((r (try (let ((db (apply open-database nothing-path args))) (close-database! db) 'opened)))
         (made (file-exists? nothing-path)))
    (list r 'file-made made)))

(show 'A1-unknown (opened-with '((bogus . 1))))
(show 'A2-twice (opened-with '((busy-timeout . 1) (busy-timeout . 2))))
(show 'A3-fk-1 (opened-with '((foreign-keys . 1))))
(show 'A4-bt-neg (opened-with '((busy-timeout . -1))))
(show 'A5-bt-2^31 (opened-with '((busy-timeout . 2147483648))))
(show 'A6-bt-max (opened-with '((busy-timeout . 2147483647))))
(show 'A7-sc-1025 (opened-with '((statement-cache . 1025))))
(show 'A8-sc-1024 (opened-with '((statement-cache . 1024))))
(show 'A9-sc-2.0 (opened-with '((statement-cache . 2.0))))
(show 'A10-not-pairs (opened-with '(1 2)))
(show 'A11-name-not-symbol (opened-with '((1 . 2))))
(show 'A12-improper (opened-with '((busy-timeout . 1) . x)))
(show 'A13-second-list (opened-with '() '()))
(show 'A14-empty-list (opened-with '()))
(show 'A15-WAL-upper (opened-with '((journal-mode . WAL))))
(show 'A16-cwd-proc-never-called
      (let ((called #f))
        (let ((r (try (call-with-database ":memory:" '((journal-mode . wal))
                        (lambda (db) (set! called #t) 'ran)))))
          (list r 'called called))))

;; ===== B. the statement cache =====
(define (cache-after settings n)
  (let ((db (apply open-database ":memory:" settings)))
    (let loop ((i 0))
      (when (< i n)
        (query-row db (string-append "select " (number->string i)))
        (loop (+ i 1))))
    (let* ((cap (database-cache-capacity db)) (count (database-cache-count db)))
      (close-database! db)
      (list 'capacity cap 'held count))))
(show 'B1-default-40 (cache-after '() 40))
(show 'B2-zero-40 (cache-after '(((statement-cache . 0))) 40))
(show 'B3-five-40 (cache-after '(((statement-cache . 5))) 40))
(show 'B4-script-not-kept
      (call-with-database ":memory:"
        (lambda (db)
          (execute-script! db "create table t (x); insert into t values (1); select x from t")
          (database-cache-count db))))
(show 'B5-with-transaction-own-statements-kept
      (call-with-database ":memory:"
        (lambda (db)
          (with-transaction db (lambda () 'x))
          (database-cache-count db))))
(show 'B6-kept-statement-does-not-lock-drop
      (call-with-database ":memory:"
        (lambda (db)
          (execute! db "create table t (x)")
          (query db "select x from t")
          (try (execute! db "drop table t")))))

;; ===== C. the interrupt =====
(show 'C1-lost-when-idle
      (call-with-database ":memory:"
        (lambda (db) (interrupt-database! db) (try (query-row db "select 2")))))
(show 'C2-other-thread-idle
      (call-with-database ":memory:"
        (lambda (db)
          (let* ((t (run-on-thread (lambda () (interrupt-database! db) 'called)))
                 (q (try (query-row db "select 2"))))
            (list t q)))))
(show 'C2b-other-thread-execute-is-wrong-thread
      (call-with-database ":memory:"
        (lambda (db) (run-on-thread (lambda () (execute! db "select 1"))))))
(show 'C2c-other-thread-with-transaction
      (call-with-database ":memory:"
        (lambda (db) (run-on-thread (lambda () (with-transaction db (lambda () 1)))))))
(show 'C2d-not-a-database (try (interrupt-database! 'x)))
(show 'C2e-closed-other-thread
      (let ((db (open-database ":memory:")))
        (close-database! db)
        (run-on-thread (lambda () (interrupt-database! db) 'nothing))))
(show 'C3-commit-rollback-under-held-row
      (call-with-database ":memory:"
        (lambda (db)
          (execute! db "create table t (x)")
          (execute! db "insert into t values (1), (2)")
          (execute! db "begin")
          (let* ((st (prepare-statement db "select x from t"))
                 (row (step! st)))
            (interrupt-database! db)
            (let* ((c (try (execute! db "commit")))
                   (r (try (execute! db "rollback")))
                   (in1 (in-transaction? db))
                   (reset (try (reset! st)))
                   (r2 (try (execute! db "rollback")))
                   (in2 (in-transaction? db)))
              (finalize-statement! st)
              (list 'commit c 'rollback r 'in in1 'reset reset 'rollback2 r2 'in in2))))))
(show 'C4-with-transaction-rollback-interrupted
      (call-with-database ":memory:"
        (lambda (db)
          (execute! db "create table t (x)")
          (execute! db "insert into t values (1), (2)")
          (let* ((st #f)
                 (out (try (with-transaction db
                             (lambda ()
                               (execute! db "insert into t values (3)")
                               (set! st (prepare-statement db "select x from t"))
                               (step! st)
                               (interrupt-database! db)
                               (raise 'boom)))))
                 (in1 (in-transaction? db))
                 (reset (try (reset! st)))
                 (r (try (execute! db "rollback")))
                 (in2 (in-transaction? db))
                 (n (query-row db "select count(*) from t")))
            (finalize-statement! st)
            (list out 'in in1 'reset reset 'rollback r 'in in2 'count n)))))
(show 'C5-watchdog-stops-long-query
      (call-with-database ":memory:"
        (lambda (db) (with-watchdog db (lambda () (query-row db long-count))))))
(show 'C5b-after-watchdog-next-runs
      (call-with-database ":memory:"
        (lambda (db)
          (let* ((w (with-watchdog db (lambda () (query-row db long-count))))
                 (q (try (query-row db "select 2"))))
            (list (car w) q)))))
(show 'C6-interrupted-write-ends-transaction
      (call-with-database ":memory:"
        (lambda (db)
          (execute! db "create table big (x)")
          (execute! db "begin")
          (execute! db "insert into big values (0)")
          (let* ((w (with-watchdog db
                      (lambda ()
                        (execute! db "insert into big with recursive c(x) as (select 1 union all select x + 1 from c where x < 300000000) select x from c"))))
                 (in (in-transaction? db))
                 (n (query-row db "select count(*) from big")))
            (when (in-transaction? db) (execute! db "rollback"))
            (list (car w) (cadr w) 'in in 'count n)))))
(show 'C7-interrupted-select-keeps-transaction
      (call-with-database ":memory:"
        (lambda (db)
          (execute! db "begin")
          (let* ((w (with-watchdog db (lambda () (query-row db long-count))))
                 (in (in-transaction? db)))
            (when (in-transaction? db) (execute! db "rollback"))
            (list (car w) 'in in)))))
(show 'C8-interrupted-execute-script
      (call-with-database ":memory:"
        (lambda (db)
          (with-watchdog db (lambda () (execute-script! db (string-append "select 1; " long-count)))))))

;; ===== D. with-transaction =====
(show 'D1-deferred-fk-commit-fails
      (call-with-database ":memory:" '((foreign-keys . #t))
        (lambda (db)
          (execute! db "create table p (id integer primary key)")
          (execute! db "create table c (pid references p (id) deferrable initially deferred)")
          (let* ((r (try (with-transaction db (lambda () (execute! db "insert into c values (9)") 'returned))))
                 (in (in-transaction? db))
                 (n (query-row db "select count(*) from c")))
            (list r 'in in 'count n)))))
(show 'D2-ended-later-write-stays
      (call-with-database ":memory:"
        (lambda (db)
          (execute! db "create table t (x unique)")
          (execute! db "insert into t values (1)")
          (let* ((r (try (with-transaction db
                           (lambda ()
                             (guard (e ((sqlite-error? e) 'caught))
                               (execute! db "insert or rollback into t values (1)"))
                             (execute! db "insert into t values (2)")
                             'returned))))
                 (rows (query db "select x from t order by x")))
            (list r rows)))))
(show 'D3-outer-rollback-beside-held-write
      (call-with-database ":memory:"
        (lambda (db)
          (execute! db "create table w (x)")
          (let* ((st #f)
                 (r (try (with-transaction db
                           (lambda ()
                             (set! st (prepare-statement db "insert into w values (1), (2), (3) returning x"))
                             (step! st)
                             (raise 'boom)))))
                 (in (in-transaction? db))
                 (next (try (and (step! st) (column-value st 0))))
                 (fin (try (finalize-statement! st)))
                 (n (query-row db "select count(*) from w")))
            (list r 'in in 'next-step next 'finalize fin 'count n)))))
(show 'D4-nested-rollback-beside-held-write
      (call-with-database ":memory:"
        (lambda (db)
          (execute! db "create table w (x)")
          (let* ((st #f) (inner #f) (inner-next #f) (inner-fin #f) (release #f)
                 (outer (try (with-transaction db
                               (lambda ()
                                 (execute! db "insert into w values (0)")
                                 (set! inner (try (with-transaction db
                                                    (lambda ()
                                                      (set! st (prepare-statement db "insert into w values (1), (2), (3) returning x"))
                                                      (step! st)
                                                      (raise 'boom)))))
                                 (set! inner-next (try (and (step! st) (column-value st 0))))
                                 (set! inner-fin (try (finalize-statement! st)))
                                 (set! release (try (execute! db "release chez_sqlite3_0")))
                                 (query db "select x from w order by x")))))
                 (in (in-transaction? db))
                 (n (query db "select x from w order by x")))
            (list 'inner inner 'inner-next-step inner-next 'inner-finalize inner-fin
                  'savepoint-still-open release 'outer outer 'in in 'rows n)))))
(show 'D5-rollback-beside-held-select-after-create
      (call-with-database ":memory:"
        (lambda (db)
          (execute! db "create table w (x)")
          (execute! db "insert into w values (1), (2)")
          (let* ((st #f)
                 (r (try (with-transaction db
                           (lambda ()
                             (set! st (prepare-statement db "select x from w"))
                             (step! st)
                             (execute! db "create table z (y)")
                             (raise 'boom)))))
                 (in (in-transaction? db))
                 (next (try (and (step! st) (column-value st 0))))
                 (fin (try (finalize-statement! st))))
            (list r 'in in 'next-step next 'finalize fin)))))
(show 'D5b-rollback-beside-held-select-no-schema-change
      (call-with-database ":memory:"
        (lambda (db)
          (execute! db "create table w (x)")
          (execute! db "insert into w values (1), (2)")
          (let* ((st #f)
                 (r (try (with-transaction db
                           (lambda ()
                             (set! st (prepare-statement db "select x from w"))
                             (step! st)
                             (execute! db "insert into w values (3)")
                             (raise 'boom)))))
                 (in (in-transaction? db))
                 (next (try (and (step! st) (column-value st 0))))
                 (fin (try (finalize-statement! st))))
            (list r 'in in 'next-step next 'finalize fin)))))
(define tx-path (fresh "build/m3cr-b/docs/p-tx.db"))
(show 'D6-default-immediate-vs-deferred
      (let* ((a (open-database tx-path)) (b (open-database tx-path)))
        (execute! a "create table t (x)")
        (let* ((imm (with-transaction a
                      (lambda ()
                        (query-row a "select count(*) from t")
                        (let ((r (try (execute! b "begin immediate"))))
                          (when (in-transaction? b) (execute! b "rollback"))
                          r))))
               (def (with-transaction a 'deferred
                      (lambda ()
                        (query-row a "select count(*) from t")
                        (let ((r (try (execute! b "begin immediate"))))
                          (when (in-transaction? b) (execute! b "rollback"))
                          r)))))
          (close-database! a)
          (close-database! b)
          (list 'default imm 'deferred def))))
(show 'D7-unknown-mode
      (call-with-database ":memory:" (lambda (db) (try (with-transaction db 'bogus (lambda () 1))))))
(show 'D8-unknown-mode-nested
      (call-with-database ":memory:"
        (lambda (db) (with-transaction db (lambda () (try (with-transaction db 'bogus (lambda () 1))))))))
(show 'D9-body-checked-first (try (with-transaction 'not-db 'bogus 5)))
(show 'D10-closed (let ((db (open-database ":memory:"))) (close-database! db) (try (with-transaction db (lambda () 1)))))
(show 'D11-raise-unchanged
      (call-with-database ":memory:"
        (lambda (db)
          (let ((obj (list 'mine)))
            (guard (e (#t (eq? e obj))) (with-transaction db (lambda () (raise obj))))))))
(show 'D12-user-begin-then-with-transaction-is-savepoint
      (call-with-database ":memory:"
        (lambda (db)
          (execute! db "create table t (x)")
          (execute! db "begin")
          (execute! db "insert into t values ('outer')")
          (let* ((r (try (with-transaction db 'exclusive
                           (lambda () (execute! db "insert into t values ('inner')") (raise 'x)))))
                 (in (in-transaction? db)))
            (execute! db "commit")
            (list r 'in in (query db "select x from t"))))))

;; ===== E. execute-script! =====
(show 'E1-empty (call-with-database ":memory:" (lambda (db) (list (try (execute-script! db "")) (try (execute-script! db "-- only a comment"))))))
(show 'E2-own-begin-left-open
      (call-with-database ":memory:"
        (lambda (db)
          (let* ((r (try (execute-script! db "begin; create table s (x unique); insert into s values (1); insert into s values (1)")))
                 (in (in-transaction? db)))
            (when in (execute! db "rollback"))
            (list r 'in in)))))
(show 'E3-prepare-error-offset
      (call-with-database ":memory:" (lambda (db) (try (execute-script! db "select 1; selec 2")))))
(show 'E4-missing-table-offset
      (call-with-database ":memory:" (lambda (db) (try (execute-script! db "select 1; /* c */ insert into nope values (1)")))))
(show 'E5-nul (call-with-database ":memory:" (lambda (db) (try (execute-script! db (string-append "select 1;" (string #\nul) "select 2"))))))
(show 'E6-closed-empty (let ((db (open-database ":memory:"))) (close-database! db) (try (execute-script! db ""))))
(show 'E7-sql-is-whole-script
      (call-with-database ":memory:"
        (lambda (db)
          (guard (e ((sqlite-error? e) (sqlite-error-sql e)))
            (execute-script! db "select 1; selec 2")))))

;; ===== F. a mismatch's actual =====
(show 'F1-temp-db-wal (try (close-database! (open-database "" '((journal-mode . wal))))))
(show 'F2-memory-persist (try (close-database! (open-database ":memory:" '((journal-mode . persist))))))
(define ro-path (fresh "build/m3cr-b/docs/p-ro.db"))
(let ((db (open-database ro-path))) (execute! db "create table t (x)") (close-database! db))
(show 'F3-read-only-wal (try (close-database! (open-database ro-path 'read-only '((journal-mode . wal))))))
(show 'F4-memory-sync-off (try (close-database! (open-database ":memory:" '((synchronous . off)))) 'opened))

;; ===== O. conveniences =====
(define overflow-on-2 "select case when x = 2 then abs(-9223372036854775807 - 1) else x end from (select 1 as x union all select 2)")
(show 'O1-query-row-never-reads-second (call-with-database ":memory:" (lambda (db) (try (query-row db overflow-on-2)))))
(show 'O1b-query-reads-second (call-with-database ":memory:" (lambda (db) (try (query db overflow-on-2)))))
(show 'O2-execute-pragma
      (call-with-database ":memory:"
        (lambda (db) (list (try (execute! db "select 1")) (begin (execute! db "pragma user_version = 3") (query-row db "pragma user_version"))))))
(show 'O3-params
      (call-with-database ":memory:"
        (lambda (db)
          (let* ((a (try (query-row db "select :a, :b" 1 2)))
                 (b (try (query-row db "select :a, :a" 7)))
                 (c (try (query-row db "select ?3" 1 2 3)))
                 (d (try (query-row db "select ?3" 1)))
                 (e (try (query-row db "select ?" 'sym))))
            (list a b c d e)))))
(show 'O4-none-or-two
      (call-with-database ":memory:"
        (lambda (db)
          (let* ((a (try (execute! db "")))
                 (b (try (execute! db "pragma cache_size = 7; select 1")))
                 (c (query-row db "pragma cache_size"))
                 (d (try (query-row db "select 1;  -- trailing"))))
            (list a b c d)))))
(show 'O5-raise-finishes
      (call-with-database ":memory:"
        (lambda (db)
          (let* ((a (try (query-fold db "select 1 union all select 2" (lambda (acc row) (raise 'x)) 0)))
                 (b (try (query db "select ?")))
                 (c (try (with-transaction db (lambda () 'ok)))))
            (list a b c)))))
(show 'O6-fold-reads-outside-transaction
      (call-with-database ":memory:"
        (lambda (db) (query-fold db "select 1" (lambda (acc row) (in-transaction? db)) 'seed))))
(show 'O7-counters-closed
      (let ((db (open-database ":memory:")))
        (close-database! db)
        (list (try (changes db)) (try (total-changes db)) (try (last-insert-rowid db)) (try (in-transaction? db)))))
(show 'O8-fold-seed-no-rows
      (call-with-database ":memory:" (lambda (db) (query-fold db "select 1 where 0" (lambda (a r) 'called) 'seed))))
(show 'O9-fold-not-a-procedure
      (call-with-database ":memory:" (lambda (db) (try (query-fold db "select 1" 5 0)))))
