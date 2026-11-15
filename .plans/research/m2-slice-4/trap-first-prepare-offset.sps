;;; Trap repro: the offset a failed prepare reports can depend on what the
;;; connection prepared before. Each failing SQL is prepared on a fresh
;;; connection four ways: as its first statement; again, straight after
;;; that; after one successful prepare of "select 1"; and after one failed
;;; prepare of "select nosuch_col". Then sqlite3_error_offset is read.
;;;
;;;   scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-slice-4/trap-first-prepare-offset.sps'
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define libversion (foreign-procedure "sqlite3_libversion" () string))
(define sourceid (foreign-procedure "sqlite3_sourceid" () string))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare-v3 (foreign-procedure "sqlite3_prepare_v3" (uptr string int unsigned-int uptr uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define errmsg (foreign-procedure "sqlite3_errmsg" (uptr) string))
(define error-offset (foreign-procedure "sqlite3_error_offset" (uptr) int))

;; Every SQL and message here is ASCII, so Chez's string type reads it whole.
(define (open)
  (let* ([cell (foreign-alloc 8)]
         [rc (open-v2 ":memory:" cell (logior #x2 #x4 #x80 #x02000000) 0)]
         [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    db))
;; prep : Address String -> (List rc offset message), the statement finalized
(define (prep db sql)
  (let* ([cell (foreign-alloc 8)]
         [zero (foreign-set! 'uptr cell 0 0)]
         [rc (prepare-v3 db sql -1 0 cell 0)]
         [off (error-offset db)]
         [msg (errmsg db)]
         [st (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (unless (= st 0) (finalize st))
    (list rc off msg)))

(printf "libversion: ~a~nsourceid: ~a~n" (libversion) (sourceid))
(for-each
 (lambda (sql)
   (let* ([db1 (open)]
          [first (prep db1 sql)]
          [again (prep db1 sql)]
          [c1 (close db1)]
          [db2 (open)]
          [ok (prep db2 "select 1")]
          [after-ok (prep db2 sql)]
          [c2 (close db2)]
          [db3 (open)]
          [bad (prep db3 "select nosuch_col")]
          [after-bad (prep db3 sql)]
          [c3 (close db3)])
     (printf "~s: ~s~n" sql (caddr first))
     (printf "  offset as the first prepare ~a, again ~a, after a good prepare ~a, after a failed one (its offset ~a) ~a~n"
             (cadr first) (cadr again) (cadr after-ok) (cadr bad) (cadr after-bad))))
 '("select ?0" "select ?32767" "select ?1, ?0" "select nosuch_col" "select 1 from nosuch_table" "selectx 1" "select 1 +"
   "select ?0 where 1" "select 1 from nosuch_table where 1" "select nosuch_col where 1"))
