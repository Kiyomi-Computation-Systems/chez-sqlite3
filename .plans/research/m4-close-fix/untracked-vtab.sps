#!r6rs
;;; untracked-vtab.sps: what close-database! counts when an untracked
;;; statement stands beside an FTS5 table. A statement made with a raw
;;; sqlite3_prepare_v2, so the connection does not track it, of SQL that
;;; reads no virtual table, or that reads the FTS5 table, prepared only or
;;; stepped to its row; then close-database!'s outcome, the statements
;;; sqlite3_next_stmt still finds, by their SQL, and the close once the raw
;;; statement is finalized. Run from the repository's root, in the
;;; container:
;;;   $CHEZ --libdirs src:build/scheme-libs --program .plans/research/m4-close-fix/untracked-vtab.sps
(import (chezscheme)
        (chez-sqlite3)
        (only (chez-sqlite3 private connection) call-with-open-handle)
        (only (chez-sqlite3 private native) call-with-c-string call-with-out-pointer))

(define prepare-v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int))
(define raw-step (foreign-procedure "sqlite3_step" (uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define next-stmt (foreign-procedure "sqlite3_next_stmt" (uptr uptr) uptr))
(define stmt-sql (foreign-procedure "sqlite3_sql" (uptr) uptr))

(define (c-text p)
  (let loop ((i 0) (bytes '()))
    (let ((b (foreign-ref 'unsigned-8 p i)))
      (if (zero? b)
          (utf8->string (u8-list->bytevector (reverse bytes)))
          (loop (+ i 1) (cons b bytes))))))

(define (statements db)
  (call-with-open-handle 'probe db
    (lambda (h)
      (let loop ((s (next-stmt h 0)) (acc '()))
        (if (eqv? s 0) (reverse acc) (loop (next-stmt h s) (cons (c-text (stmt-sql s)) acc)))))))

(define (prepare! db sql)
  (call-with-open-handle 'probe db
    (lambda (h)
      (call-with-c-string 'probe sql
        (lambda (text)
          (let-values (((rc st) (call-with-out-pointer 'probe (lambda (slot) (prepare-v2 h text -1 slot 0)))))
            st))))))

(define (outcome thunk)
  (guard (e ((assertion-violation? e) (list 'assertion-violation (condition-who e) (condition-irritants e)))
            ((sqlite-error? e) (list 'sqlite-error (sqlite-error-code e) (sqlite-error-extended-code e)))
            (#t (list 'other (if (message-condition? e) (condition-message e) e))))
    (thunk)))

(define (say . xs) (for-each (lambda (x) (write x) (display " ")) xs) (newline))

(say 'version (sqlite-version))
(for-each
 (lambda (c)
   (let ((sql (car c)) (stepped (cadr c)))
     (let ((db (open-database ":memory:")))
       (execute! db "create virtual table v using fts5(body)")
       (execute! db "insert into v(body) values ('hello world')")
       (query-row db "select count(*) from v where v match 'hello'")
       (let* ((raw (prepare! db sql))
              (step (if stepped (raw-step raw) 'not-stepped))
              (r (outcome (lambda () (close-database! db) 'closed))))
         (say sql step 'close r)
         (say '  'left (statements db))
         (finalize raw)
         (say '  'then (outcome (lambda () (close-database! db) 'closed)))))))
 '(("select 1" #f)
   ("select count(*) from v where v match 'hello'" #f)
   ("select body from v" #t)))
