#!r6rs
;;; rebuild.sps: what each full-text module's own 'rebuild' command does to an
;;; index a refused close left inconsistent. For each of fts5, fts4 and fts3 that
;;; pragma_module_list lists: a file holding v; BEGIN; a row into v; a raw
;;; statement, so close-database! is refused after sqlite3_close; the raw
;;; statement finalized; COMMIT; then v's rows read plainly and searched, and
;;; the module's integrity check; then INSERT INTO v(v) VALUES ('rebuild');
;;; then the same reads; then a second connection's. Run from the
;;; repository's root, in the container:
;;;   $CHEZ --libdirs src:build/scheme-libs --program .plans/research/m4-close-fix/rebuild.sps
(import (chezscheme)
        (chez-sqlite3)
        (only (chez-sqlite3 private connection) call-with-open-handle)
        (only (chez-sqlite3 private native) call-with-c-string call-with-out-pointer))
(define prepare-v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
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
            (#t (list 'other e)))
    (thunk)))
(define (say . xs) (for-each (lambda (x) (write x) (display " ")) xs) (newline))
(define (one db sql) (outcome (lambda () (vector-ref (query-row db sql) 0))))
(define (reads db)
  (list 'plain (one db "select count(*) from v") 'search (one db "select count(*) from v where v match 'hello'")
        'integrity (outcome (lambda () (execute! db "insert into v(v) values ('integrity-check')") 'intact))))
(define names
  (let ((db (open-database ":memory:")))
    (let ((n (map (lambda (r) (string->symbol (vector-ref r 0))) (query db "select name from pragma_module_list"))))
      (close-database! db) n)))
(say 'version (sqlite-version))
(unless (file-exists? "build/rebuild") (mkdir "build/rebuild"))
(for-each
 (lambda (m)
   (if (not (memq m names))
       (say m 'not-listed)
       (let ((path (format "build/rebuild/~a.db" m)))
         (when (file-exists? path) (delete-file path))
         (let ((db (open-database path)))
           (execute! db (format "create virtual table v using ~a(body)" m))
           (execute! db "insert into v(body) values ('hello one')")
           (execute! db "begin")
           (execute! db "insert into v(body) values ('hello two')")
           (let ((raw (prepare! db "select 1")))
             (say m 'close (outcome (lambda () (close-database! db) 'closed)))
             (finalize raw))
           (say m 'commit (outcome (lambda () (execute! db "commit") 'done)) (reads db))
           (say m 'rebuild (outcome (lambda () (execute! db "insert into v(v) values ('rebuild')") 'done)) (reads db))
           (say m 'close (outcome (lambda () (close-database! db) 'closed))))
         (let ((other (open-database path)))
           (say m 'reopened (reads other))
           (say m 'close (outcome (lambda () (close-database! other) 'closed))))
         (delete-file path))))
 '(fts5 fts4 fts3))
