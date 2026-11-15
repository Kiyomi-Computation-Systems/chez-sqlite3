;;; Trap repro: sqlite3_error_offset answers an earlier failed prepare's
;;; offset after a refused bind. A failed prepare of "select nosuch_col"
;;; leaves offset 7; a bind at index 0 then answers SQLITE_RANGE, and the
;;; connection's code and message are the bind's, but the offset is still 7.
;;; A clean bind clears it.
;;;
;;;   scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-slice-4/trap-stale-offset.sps'
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define libversion (foreign-procedure "sqlite3_libversion" () string))
(define sourceid (foreign-procedure "sqlite3_sourceid" () string))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare-v3 (foreign-procedure "sqlite3_prepare_v3" (uptr string int unsigned-int uptr uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define bind-int64 (foreign-procedure "sqlite3_bind_int64" (uptr int integer-64) int))
(define errcode (foreign-procedure "sqlite3_errcode" (uptr) int))
(define errmsg (foreign-procedure "sqlite3_errmsg" (uptr) string))
(define error-offset (foreign-procedure "sqlite3_error_offset" (uptr) int))

;; The SQL and messages here are ASCII, so Chez's string type reads them
;; whole; the version and source id too.
(define (open)
  (let* ([cell (foreign-alloc 8)]
         [rc (open-v2 ":memory:" cell (logior #x2 #x4 #x80 #x02000000) 0)]
         [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    db))
(define (prep db sql)
  (let* ([cell (foreign-alloc 8)]
         [zero (foreign-set! 'uptr cell 0 0)]
         [rc (prepare-v3 db sql -1 0 cell 0)]
         [st (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (list rc st)))

(printf "libversion: ~a~nsourceid: ~a~n" (libversion) (sourceid))
(let* ([db (open)]
       [good (prep db "select ?1")]
       [st (cadr good)]
       [bad (prep db "select nosuch_col")]
       [c1 (errcode db)] [m1 (errmsg db)] [o1 (error-offset db)]
       [rc (bind-int64 st 0 1)]
       [c2 (errcode db)] [m2 (errmsg db)] [o2 (error-offset db)]
       [ok (bind-int64 st 1 1)]
       [c3 (errcode db)] [m3 (errmsg db)] [o3 (error-offset db)]
       [f (finalize st)]
       [c (close db)])
  (printf "failed prepare rc ~a: errcode ~a, errmsg ~s, offset ~a~n" (car bad) c1 m1 o1)
  (printf "bind at index 0 rc ~a: errcode ~a, errmsg ~s, offset ~a~n" rc c2 m2 o2)
  (printf "bind at index 1 rc ~a: errcode ~a, errmsg ~s, offset ~a~n" ok c3 m3 o3))
