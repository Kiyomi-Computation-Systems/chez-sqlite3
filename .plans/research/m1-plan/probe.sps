;;; Two facts the M1 plan states:
;;;   1. sqlite3_open_v2 creates the file at open, before any statement runs.
;;;   2. PRAGMA journal_mode=wal on a :memory: database answers "memory" and raises nothing.
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare (foreign-procedure "sqlite3_prepare_v2" (uptr string int uptr uptr) int))
(define step (foreign-procedure "sqlite3_step" (uptr) int))
(define column-text (foreign-procedure "sqlite3_column_text" (uptr int) utf-8))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define READWRITE #x2)
(define CREATE #x4)
(define (open name flags)
  (let* ([cell (foreign-alloc 8)]
         [rc (open-v2 name cell flags 0)]
         [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (cons rc db)))
(define path (string-append (car (command-line-arguments)) "/created.db"))
(printf "before open, exists: ~a~n" (file-exists? path))
(let* ([o (open path (logior READWRITE CREATE))])
  (printf "open rc ~a; after open, before any statement, exists: ~a, size ~a~n"
          (car o) (file-exists? path)
          (if (file-exists? path) (file-length (open-input-file path)) 'none))
  (printf "close rc ~a~n" (close (cdr o))))
(let* ([o (open ":memory:" (logior READWRITE CREATE))]
       [db (cdr o)]
       [cell (foreign-alloc 8)]
       [rc (prepare db "PRAGMA journal_mode=wal" -1 cell 0)]
       [stmt (foreign-ref 'uptr cell 0)])
  (foreign-free cell)
  (let* ([s (step stmt)]
         [answer (column-text stmt 0)])
    (printf "prepare rc ~a; step rc ~a (100 is ROW); journal_mode answers ~s~n" rc s answer))
  ;; let*, not two arguments to printf: Chez fixes no order for a call's
  ;; arguments, and a close before the finalize would answer SQLITE_BUSY.
  (let* ([f (finalize stmt)]
         [c (close db)])
    (printf "finalize rc ~a; close rc ~a~n" f c)))
