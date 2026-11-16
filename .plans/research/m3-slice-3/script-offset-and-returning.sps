;; M3 slice 3, part B's probe: a script's prepare error past its failing
;; statement's first token, a column no table has, and its offset in the
;; whole script; and query-row of a multi-row insert ... returning whose
;; second row breaks a unique constraint. Run from the repository's root:
;;   $CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-3/script-offset-and-returning.sps
(import (rnrs) (chez-sqlite3) (chez-sqlite3 private conveniences))
(define db (open-database ":memory:"))
(execute! db "create table s (x unique)")
(write (guard (e (#t (list (sqlite-error-extended-code e) (sqlite-error-offset e) (sqlite-error-message e))))
  (execute-script! db "insert into s values (2); select 1, nosuchcol")))
(newline)
(write (query db "select x from s")) (newline)
(write (guard (e (#t (list (sqlite-error-extended-code e) (sqlite-error-offset e) (sqlite-error-message e))))
  (query-row db "insert into s values (1), (2) returning x")))
(newline)
(close-database! db)
