#!r6rs
;;; vtab-close.sps: which virtual table modules leave statements of their own
;;; on a connection, and whether close-database! then closes it. For each of
;;; fts5, fts4, fts3 and rtree that pragma_module_list lists: a :memory:
;;; connection makes a table of it, and the statements sqlite3_next_stmt
;;; finds are counted and their SQL printed; then the same after an insert
;;; and a query; then close-database!'s outcome. A file's table is then made,
;;; closed, reopened and queried, and closed again. A close that fails is
;;; undone by dropping the table, then closing. Run from the repository's
;;; root, in the container:
;;;   $CHEZ --libdirs src:build/scheme-libs --program .plans/research/m4-close-fix/vtab-close.sps
;;; with CHEZ_SQLITE3_LIBRARY and C_INCLUDE_PATH set for another library.
(import (chezscheme)
        (chez-sqlite3)
        (only (chez-sqlite3 private connection) call-with-open-handle))

(define next-stmt (foreign-procedure "sqlite3_next_stmt" (uptr uptr) uptr))
(define stmt-sql (foreign-procedure "sqlite3_sql" (uptr) uptr))

(define (c-text p)
  (if (eqv? p 0)
      "NULL"
      (let loop ((i 0) (bytes '()))
        (let ((b (foreign-ref 'unsigned-8 p i)))
          (if (zero? b)
              (utf8->string (u8-list->bytevector (reverse bytes)))
              (loop (+ i 1) (cons b bytes)))))))

;; statements : Database -> (Listof String)
(define (statements db)
  (call-with-open-handle 'probe db
    (lambda (h)
      (let loop ((s (next-stmt h 0)) (acc '()))
        (if (eqv? s 0)
            (reverse acc)
            (loop (next-stmt h s) (cons (c-text (stmt-sql s)) acc)))))))

(define (outcome thunk)
  (guard (e ((assertion-violation? e) (list 'assertion-violation (condition-who e) (condition-irritants e)))
            ((sqlite-error? e) (list 'sqlite-error (sqlite-error-code e) (sqlite-error-message e)))
            (#t (list 'other (if (message-condition? e) (condition-message e) e))))
    (thunk)))

(define (say . xs) (for-each (lambda (x) (write x) (display " ")) xs) (newline))

(define modules
  '((fts5 "create virtual table v using fts5(body)" "insert into v(body) values ('hello world')"
          "select count(*) from v where v match 'hello'")
    (fts4 "create virtual table v using fts4(body)" "insert into v(body) values ('hello world')"
          "select count(*) from v where v match 'hello'")
    (fts3 "create virtual table v using fts3(body)" "insert into v(body) values ('hello world')"
          "select count(*) from v where v match 'hello'")
    (rtree "create virtual table v using rtree(id, x0, x1)" "insert into v values (1, 0.0, 1.0)"
           "select count(*) from v where x0 >= 0.0")))

(define (listed)
  (let ((db (open-database ":memory:")))
    (let ((names (map (lambda (r) (string->symbol (vector-ref r 0)))
                      (query db "select name from pragma_module_list order by name"))))
      (close-database! db)
      names)))

(define (close-or-undo db)
  (let ((r (outcome (lambda () (close-database! db) 'closed))))
    (unless (eq? r 'closed)
      (outcome (lambda () (execute! db "drop table v") (close-database! db) 'undone)))
    r))

(say 'version (sqlite-version))
(say 'options (filter (lambda (o) (or (and (>= (string-length o) 10) (string=? (substring o 0 10) "ENABLE_FTS"))
                                       (string=? o "ENABLE_RTREE")))
                      (sqlite-compile-options)))
(let ((names (listed)))
  (say 'modules-listed (filter (lambda (n) (memq n '(fts3 fts4 fts5 rtree))) names))
  (for-each
   (lambda (m)
     (let ((name (car m)) (create (cadr m)) (insert (caddr m)) (select (cadddr m)))
       (if (not (memq name names))
           (say name 'not-listed (outcome (lambda () (let ((db (open-database ":memory:")))
                                                         (let ((r (outcome (lambda () (execute! db create) 'made))))
                                                           (close-database! db) r)))))
           (begin
             ;; created only
             (let ((db (open-database ":memory:")))
               (execute! db create)
               (let ((s (statements db)))
                 (say name 'created (length s) s))
               (say name 'created-close (close-or-undo db)))
             ;; created, written and queried
             (let ((db (open-database ":memory:")))
               (execute! db create)
               (execute! db insert)
               (let ((n (query-row db select)))
                 (let ((s (statements db)))
                   (say name 'queried n (length s) s)))
               (say name 'queried-close (close-or-undo db)))
             ;; a file: made, closed, reopened, queried, closed
             (let* ((dir (format "build/vtab-close-~a" name))
                    (path (string-append dir "/v.db")))
               (unless (file-exists? dir) (mkdir dir))
               (when (file-exists? path) (delete-file path))
               (let ((db (open-database path)))
                 (execute! db create)
                 (execute! db insert)
                 (say name 'file-first-close (close-or-undo db)))
               (let ((db (open-database path)))
                 (let ((n (outcome (lambda () (query-row db select)))))
                   (let ((s (statements db)))
                     (say name 'file-reopened n (length s) s)))
                 (say name 'file-reopened-close (close-or-undo db)))
               (when (file-exists? path) (delete-file path)))))))
   modules))
