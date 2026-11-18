#!r6rs
;;; stmt-busy.sps: at the point the close calls sqlite3_close, after it has
;;; finalized every statement the connection tracks, which statements does
;;; sqlite3_next_stmt find, and which does sqlite3_stmt_busy report busy?
;;; The probe is an entry of its own tracked by the connection, made just
;;; before close-database!, so it is the newest, and the close finalizes it
;;; last of the tracked statements, inside the close's section, with the
;;; handle: it walks sqlite3_next_stmt there, reading each statement's SQL
;;; and sqlite3_stmt_busy, both bound here after the load, and answers
;;; finalized. The close's cache is emptied after the tracked statements, and
;;; holds only statements the connection tracks, all finalized by then.
;;;
;;; For each of fts5, fts4, fts3 and rtree that pragma_module_list lists:
;;;   created      a :memory: table made
;;;   searched     made, written and searched
;;;   reopened     a file's table made, written and closed, then reopened and
;;;                searched
;;;   open-write   made, then BEGIN and a write, left open
;;;   open-search  made, then BEGIN, a write and a search, left open
;;;   held-tracked made and written, then a search held at its row by a
;;;                statement of prepare-statement's, which the close finalizes
;;;   untracked-returning  made, then INSERT ... RETURNING prepared raw and
;;;                stepped once, in autocommit (the review's case)
;;;   untracked-held       made and written, then a raw SELECT of it stepped
;;;                to its row
;;;   untracked-idle       made and written, then a raw SELECT prepared only
;;; and, with no module, a raw SELECT 1 stepped to its row, and prepared
;;; only. Each prints: (statements found, each busy one's SQL and
;;; sqlite3_stmt_readonly), the close's outcome, and for a raw statement its
;;; finalize and the close after it. A busy statement with no SQL is a
;;; sqlite3_blob's (blob-busy.sps). Run from the repository's root, in the container:
;;;   $CHEZ --libdirs src:build/scheme-libs --program .plans/research/m4-close-fix/stmt-busy.sps
(import (chezscheme)
        (chez-sqlite3)
        (only (chez-sqlite3 private connection) call-with-open-handle track-statement!)
        (only (chez-sqlite3 private native) call-with-c-string call-with-out-pointer c-string->string))

(define prepare-v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int))
(define raw-step (foreign-procedure "sqlite3_step" (uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define next-stmt (foreign-procedure "sqlite3_next_stmt" (uptr uptr) uptr))
(define stmt-sql (foreign-procedure "sqlite3_sql" (uptr) uptr))
(define stmt-busy (foreign-procedure "sqlite3_stmt_busy" (uptr) int))
(define stmt-readonly (foreign-procedure "sqlite3_stmt_readonly" (uptr) int))

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

;; walk : Positive-Integer -> (List Natural (Listof (List (U String #f) Symbol)))
;; How many statements sqlite3_next_stmt finds on HANDLE, and, for each
;; sqlite3_stmt_busy reports busy, its SQL, #f for none, and whether
;; sqlite3_stmt_readonly calls it read-only or a writer.
(define (walk handle)
  (let loop ((s (next-stmt handle 0)) (n 0) (busy '()))
    (if (eqv? s 0)
        (list n (reverse busy))
        (loop (next-stmt handle s) (+ n 1)
              (if (eqv? (stmt-busy s) 0)
                  busy
                  (cons (list (c-string->string (stmt-sql s))
                              (if (eqv? (stmt-readonly s) 0) 'writer 'read-only))
                        busy))))))

;; probed-close : Database -> (List Any Any)
;; What the probe saw inside the close, and the close's outcome.
(define (probed-close db)
  (let ((seen 'probe-not-reached))
    (track-statement! db (list 'probe)
                      (lambda (handle)
                        (set! seen (guard (e (#t (list 'probe-raised (condition-message e))))
                                     (walk handle)))
                        'finalized))
    (let ((r (outcome (lambda () (close-database! db) 'closed))))
      (list seen r))))

(define modules
  '((fts5 "create virtual table v using fts5(body)" "insert into v(body) values ('hello world')"
          "select count(*) from v where v match 'hello'" "select body from v where v match 'hello'"
          "insert into v(body) values ('hello again') returning rowid")
    (fts4 "create virtual table v using fts4(body)" "insert into v(body) values ('hello world')"
          "select count(*) from v where v match 'hello'" "select body from v where v match 'hello'"
          "insert into v(body) values ('hello again') returning rowid")
    (fts3 "create virtual table v using fts3(body)" "insert into v(body) values ('hello world')"
          "select count(*) from v where v match 'hello'" "select body from v where v match 'hello'"
          "insert into v(body) values ('hello again') returning rowid")
    (rtree "create virtual table v using rtree(id, x0, x1)" "insert into v values (1, 0.0, 1.0)"
           "select count(*) from v where x0 >= 0.0" "select id from v where x0 >= 0.0"
           "insert into v values (2, 0.0, 2.0) returning id")))

(define (listed)
  (let ((db (open-database ":memory:")))
    (let ((names (map (lambda (r) (string->symbol (vector-ref r 0)))
                      (query db "select name from pragma_module_list"))))
      (close-database! db)
      names)))

(define (after-raw db raw)
  ;; the raw statement finalized, and the close again, once refused
  (list 'raw-finalized (finalize raw) 'then (outcome (lambda () (close-database! db) 'closed))))

(say 'version (sqlite-version))
(unless (file-exists? "build/stmt-busy") (mkdir "build/stmt-busy"))
(let ((names (listed)))
  (for-each
   (lambda (m)
     (let ((name (car m)) (create (list-ref m 1)) (insert (list-ref m 2)) (count (list-ref m 3))
           (rows (list-ref m 4)) (returning (list-ref m 5)))
       (if (not (memq name names))
           (say name 'not-listed)
           (begin
             (let ((db (open-database ":memory:")))
               (execute! db create)
               (say name 'created (probed-close db)))
             (let ((db (open-database ":memory:")))
               (execute! db create) (execute! db insert) (query-row db count)
               (say name 'searched (probed-close db)))
             (let ((path (format "build/stmt-busy/~a.db" name)))
               (when (file-exists? path) (delete-file path))
               (let ((db (open-database path)))
                 (execute! db create) (execute! db insert)
                 (close-database! db))
               (let ((db (open-database path)))
                 (query-row db count)
                 (say name 'reopened (probed-close db)))
               (delete-file path))
             (let ((db (open-database ":memory:")))
               (execute! db create) (execute! db "begin") (execute! db insert)
               (say name 'open-write (probed-close db)))
             (let ((db (open-database ":memory:")))
               (execute! db create) (execute! db "begin") (execute! db insert) (query-row db count)
               (say name 'open-search (probed-close db)))
             (let ((db (open-database ":memory:")))
               (execute! db create) (execute! db insert)
               (let ((st (prepare-statement db rows)))
                 (step! st)
                 (say name 'held-tracked (probed-close db))))
             (let ((db (open-database ":memory:")))
               (execute! db create)
               (let* ((raw (prepare! db returning)) (rc (raw-step raw)))
                 (say name 'untracked-returning 'step rc (probed-close db) (after-raw db raw))))
             (let ((db (open-database ":memory:")))
               (execute! db create) (execute! db insert)
               (let* ((raw (prepare! db rows)) (rc (raw-step raw)))
                 (say name 'untracked-held 'step rc (probed-close db) (after-raw db raw))))
             (let ((db (open-database ":memory:")))
               (execute! db create) (execute! db insert)
               (let ((raw (prepare! db rows)))
                 (say name 'untracked-idle (probed-close db) (after-raw db raw))))))))
   modules))
(let ((db (open-database ":memory:")))
  (let* ((raw (prepare! db "select 1")) (rc (raw-step raw)))
    (say 'none 'untracked-held 'step rc (probed-close db) (after-raw db raw))))
(let ((db (open-database ":memory:")))
  (let ((raw (prepare! db "select 1")))
    (say 'none 'untracked-idle (probed-close db) (after-raw db raw))))
