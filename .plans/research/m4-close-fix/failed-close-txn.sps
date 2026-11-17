#!r6rs
;;; failed-close-txn.sps MODE: what a close that sqlite3_close refuses does
;;; to an open transaction that wrote to a plain table and to a virtual
;;; table. For each of fts5, fts4, fts3 and rtree that pragma_module_list lists,
;;; and for none (the plain table alone): a file holding t and v; BEGIN;
;;; a row into t, a row into v; a statement made with a raw
;;; sqlite3_prepare_v2, which the connection does not track; then the close,
;;; by MODE:
;;;   raw    sqlite3_close called on the handle directly, which answers BUSY
;;;          for the raw statement: SQLite's own behaviour, whatever order
;;;          close-database! keeps
;;;   verb   close-database!
;;; Then: what it answered; in-transaction?; the connection's extended code;
;;; t's rows; v's rows, read plainly and through the module's own search;
;;; then the raw statement finalized, and the transaction ended by END,
;;; commit or rollback; the module's own integrity check; and a second
;;; connection's view of the file. The connections are closed last; on code
;;; that counts before sqlite3_close, a close beside a virtual table's own
;;; statements fails, and is printed. Run from the repository's root, in
;;; the container:
;;;   $CHEZ --libdirs src:build/scheme-libs --program .plans/research/m4-close-fix/failed-close-txn.sps raw commit
;;; with MODE raw or verb and END commit or rollback.
(import (chezscheme)
        (chez-sqlite3)
        (only (chez-sqlite3 private connection) call-with-open-handle)
        (only (chez-sqlite3 private native) call-with-c-string call-with-out-pointer))

(define prepare-v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define raw-close (foreign-procedure "sqlite3_close" (uptr) int))
(define extended-errcode (foreign-procedure "sqlite3_extended_errcode" (uptr) int))

(define mode (string->symbol (cadr (command-line))))
(define end (string->symbol (caddr (command-line))))

(define (handle-of db) (call-with-open-handle 'probe db (lambda (h) h)))

(define (prepare! db sql)
  (call-with-open-handle 'probe db
    (lambda (h)
      (call-with-c-string 'probe sql
        (lambda (text)
          (let-values (((rc st) (call-with-out-pointer 'probe (lambda (slot) (prepare-v2 h text -1 slot 0)))))
            st))))))

(define (outcome thunk)
  (guard (e ((assertion-violation? e) (list 'assertion-violation (condition-who e) (condition-irritants e)))
            ((sqlite-error? e) (list 'sqlite-error (sqlite-error-code e) (sqlite-error-extended-code e)
                                     (sqlite-error-message e)))
            (#t (list 'other (if (message-condition? e) (condition-message e) e))))
    (thunk)))

(define (say . xs) (for-each (lambda (x) (write x) (display " ")) xs) (newline))

(define (one db sql) (outcome (lambda () (vector-ref (query-row db sql) 0))))

;; name create insert plain-count search integrity
(define cases
  '((none #f #f #f #f #f)
    (fts5 "create virtual table v using fts5(body)" "insert into v(body) values ('hello world')"
          "select count(*) from v" "select count(*) from v where v match 'hello'"
          "insert into v(v) values ('integrity-check')")
    (fts4 "create virtual table v using fts4(body)" "insert into v(body) values ('hello world')"
          "select count(*) from v" "select count(*) from v where v match 'hello'"
          "insert into v(v) values ('integrity-check')")
    (fts3 "create virtual table v using fts3(body)" "insert into v(body) values ('hello world')"
          "select count(*) from v" "select count(*) from v where v match 'hello'"
          "insert into v(v) values ('integrity-check')")
    (rtree "create virtual table v using rtree(id, x0, x1)" "insert into v values (1, 0.0, 1.0)"
           "select count(*) from v" "select count(*) from v where x0 >= 0.0 and x1 <= 1.0"
           "select rtreecheck('v')")))

(define (listed)
  (let ((db (open-database ":memory:")))
    (let ((names (map (lambda (r) (string->symbol (vector-ref r 0)))
                      (query db "select name from pragma_module_list"))))
      (close-database! db)
      names)))

(define (views db c)
  (let ((plain (list-ref c 3)) (search (list-ref c 4)))
    (list (list 't (one db "select count(*) from t"))
          (if plain (list 'v (one db plain)) '(v none))
          (if search (list 'v-search (one db search)) '(v-search none)))))

(say 'version (sqlite-version) 'mode mode 'end end)
(unless (file-exists? "build/failed-close-txn") (mkdir "build/failed-close-txn"))
(let ((names (listed)))
  (for-each
   (lambda (c)
     (let ((name (car c)) (create (cadr c)) (insert (caddr c)) (integrity (list-ref c 5)))
       (if (and create (not (memq name names)))
           (say name 'not-listed)
           (let ((path (format "build/failed-close-txn/~a-~a-~a.db" name mode end)))
             (when (file-exists? path) (delete-file path))
             (let ((db (open-database path)))
               (execute! db "create table t(x)")
               (when create (execute! db create))
               (execute! db "begin")
               (execute! db "insert into t values (1)")
               (when insert (execute! db insert))
               (say name 'before (in-transaction? db) (views db c))
               (let* ((h (handle-of db))
                      (raw (prepare! db "select 1"))
                      (r (case mode
                           ((raw) (raw-close h))
                           (else (outcome (lambda () (close-database! db) 'closed))))))
                 (say name 'close r 'in-transaction (outcome (lambda () (in-transaction? db)))
                      'extended-code (extended-errcode h))
                 (say name 'after-close (views db c))
                 (finalize raw)
                 (say name end (outcome (lambda () (execute! db (symbol->string end)) 'ended))
                      'in-transaction (outcome (lambda () (in-transaction? db))))
                 (say name 'after-end (views db c))
                 (when integrity
                   (say name 'integrity (outcome (lambda () (query db integrity)))))
                 (let ((other (open-database path)))
                   (say name 'other-connection (views other c)
                        (if integrity (outcome (lambda () (query other integrity))) 'no-check))
                   (say name 'other-close (outcome (lambda () (close-database! other) 'closed))))
                 (say name 'last-close (outcome (lambda () (close-database! db) 'closed)))))))))
   cases))
