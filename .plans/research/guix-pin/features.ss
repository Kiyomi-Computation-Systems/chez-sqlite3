(load-shared-object (string-append (getenv "GUIX_ENVIRONMENT") "/lib/libsqlite3.so.0"))
(define open (foreign-procedure "sqlite3_open" (string uptr) int))
(define exec (foreign-procedure "sqlite3_exec" (uptr string uptr uptr uptr) int))
(define prep (foreign-procedure "sqlite3_prepare_v2" (uptr string int uptr uptr) int))
(define step (foreign-procedure "sqlite3_step" (uptr) int))
(define text (foreign-procedure "sqlite3_column_text" (uptr int) string))
(define fin (foreign-procedure "sqlite3_finalize" (uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define pp (foreign-alloc 8))
(let* ([rc-open (open ":memory:" pp)]
       [db (foreign-ref 'uptr pp 0)]
       [rc-fts (exec db "create virtual table t using fts5(x)" 0 0 0)]
       [rc-prep (prep db "select typeof(jsonb('{}')), json_valid('{}')" -1 pp 0)]
       [st (foreign-ref 'uptr pp 0)]
       [rc-step (step st)]
       [t0 (text st 0)]
       [t1 (text st 1)]
       [rc-fin (fin st)]
       [rc-close (close db)])
  (printf "open ~a fts5-create ~a prepare ~a step ~a jsonb-type ~a json_valid ~a finalize ~a close ~a~n"
          rc-open rc-fts rc-prep rc-step t0 t1 rc-fin rc-close))
(foreign-free pp)
