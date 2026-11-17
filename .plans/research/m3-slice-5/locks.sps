;;; locks: each setting, with a busy timeout of 1500 ms set first, opened
;;; beside another connection's lock, timed (M3 slice 5, part B). What the
;;; rows of tests/test-open-locks.sps assert, measured first, and the
;;; settings and locks the rows leave out.
;;;
;;; Run from the repository's root. Its databases are made in
;;; build/research-m3-slice-5-locks/, which it makes, and which it removes,
;;; with what it holds, at its end, by delete-file and delete-directory.
;;;
;;; Part 1: a fresh file in rollback-journal (delete) or WAL mode, holding t
;;; with three rows; a holder opens it and holds a lock: unused, opened and
;;; never used; idle, a read run to its end, then nothing held; read, BEGIN
;;; and a SELECT at its row; reserved, BEGIN IMMEDIATE and a write;
;;; exclusive, BEGIN EXCLUSIVE and a write. Then a fresh open with
;;; ((busy-timeout . 1500) SETTING), timed, and what it gave: opened, or
;;; what it raised.
;;;
;;; Part 2: on a WAL file, journal-mode delete, truncate and persist beside a
;;; holder that is unused, or idle after a read, a pragma or a write; and the
;;; same open once the holder has closed.
(import (rnrs)
        (only (chezscheme) real-time directory-list delete-directory mkdir file-directory?)
        (chez-sqlite3)
        (chez-sqlite3 private counters))

(define (show . xs)
  (for-each (lambda (x) (write x) (display " ")) xs)
  (newline))

;; try : (-> Any) -> Any
;; THUNK's answer, a database it answered closed, as opened; or what it
;; raised: an &sqlite-error by its who, codes and SQL.
(define (try thunk)
  (guard (e ((sqlite-error? e)
             (list 'sqlite-error (condition-who e) (sqlite-error-code e) (sqlite-error-extended-code e)
                   (sqlite-error-sql e)))
            (#t (list 'other (if (message-condition? e) (condition-message e) e))))
    (let ((r (thunk)))
      (if (database? r)
          (begin (close-database! r) 'opened)
          r))))

(define dir "build/research-m3-slice-5-locks")
(unless (file-directory? dir) (mkdir dir))

(define made 0)

;; fresh : Symbol -> String
;; A new file in journal mode MODE, holding t with three rows, closed.
(define (fresh mode)
  (set! made (+ made 1))
  (let* ((path (string-append dir "/f" (number->string made) ".db"))
         (db (open-database path (list (cons 'journal-mode mode)))))
    (execute! db "create table t (x)")
    (execute! db "insert into t values (1), (2), (3)")
    (close-database! db)
    path))

;; hold! : Database Symbol -> (U Statement #f)
(define (hold! db lock)
  (case lock
    ((unused) #f)
    ((idle) (query db "select count(*) from t") #f)
    ((idle-pragma) (query db "pragma journal_mode") #f)
    ((idle-wrote) (execute! db "insert into t values (4)") #f)
    ((read) (execute! db "begin")
            (let ((st (prepare-statement db "select x from t"))) (step! st) st))
    ((reserved) (execute! db "begin immediate") (execute! db "insert into t values (9)") #f)
    ((exclusive) (execute! db "begin exclusive") (execute! db "insert into t values (9)") #f)))

;; timed-open : String (Listof (Pairof Symbol Any)) -> (List Any Natural)
(define (timed-open path settings)
  (let* ((t0 (real-time))
         (r (try (lambda () (open-database path settings))))
         (t1 (real-time)))
    (list r (- t1 t0))))

;; one : Symbol Symbol (Pairof Symbol Any) -> Void
(define (one mode lock setting)
  (let* ((path (fresh mode))
         (holder (open-database path))
         (st (hold! holder lock))
         (r (timed-open path (list '(busy-timeout . 1500) setting))))
    (when st (finalize-statement! st))
    (when (in-transaction? holder) (execute! holder "rollback"))
    (close-database! holder)
    (show mode lock setting (car r) (cadr r) 'ms)))

(show 'version (sqlite-version))
(display "Part 1\n")
(for-each
 (lambda (lock)
   (for-each (lambda (setting) (one 'delete lock setting))
             '((journal-mode . delete) (journal-mode . truncate) (journal-mode . persist)
               (journal-mode . wal) (synchronous . off) (synchronous . extra) (foreign-keys . #t)
               (temp-store . memory) (trusted-schema . #f))))
 '(read reserved exclusive))
(for-each
 (lambda (lock)
   (for-each (lambda (setting) (one 'wal lock setting))
             '((journal-mode . delete) (journal-mode . truncate) (journal-mode . persist)
               (journal-mode . wal) (synchronous . off))))
 '(unused idle read reserved exclusive))

(display "Part 2\n")
(for-each
 (lambda (lock)
   (for-each
    (lambda (mode)
      (let* ((path (fresh 'wal))
             (holder (open-database path))
             (st (hold! holder lock))
             (r (timed-open path (list '(busy-timeout . 1500) (cons 'journal-mode mode)))))
        (close-database! holder)
        (let ((after (timed-open path (list '(busy-timeout . 1500) (cons 'journal-mode mode)))))
          (show 'wal lock mode (car r) (cadr r) 'ms 'once-it-has-closed (car after)))))
    '(delete truncate persist)))
 '(unused idle idle-pragma idle-wrote))

(show 'counts (native-counts))
(for-each (lambda (f) (delete-file (string-append dir "/" f))) (directory-list dir))
(delete-directory dir)
(show 'removed (not (file-exists? dir)))
