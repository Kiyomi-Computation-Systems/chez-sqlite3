;;; B5: which entry points M3 might bind each library exports, read with
;;; foreign-entry? after loading the library CHEZ_SQLITE3_LIBRARY names.
;;;
;;;   CHEZ_SQLITE3_LIBRARY=... $CHEZ --script entry-points.sps DIR NUMBER SOURCE-ID
;;;
;;; NUMBER and SOURCE-ID are the header's; the probe refuses to run unless the
;;; library's own equal them. DIR is unused.
(import (chezscheme))

(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define libversion-number (foreign-procedure "sqlite3_libversion_number" () int))
(define libversion (foreign-procedure "sqlite3_libversion" () string))
(define sourceid (foreign-procedure "sqlite3_sourceid" () string))

(let* ([args (command-line-arguments)]
       [number (cadr args)]
       [source (caddr args)])
  (unless (and (string=? number (number->string (libversion-number)))
               (string=? source (sourceid)))
    (error 'entry-points "the library is not the header's" number source (libversion-number) (sourceid))))

(printf "libversion: ~a~n" (libversion))
(printf "sourceid: ~a~n" (sourceid))

(for-each
 (lambda (name)
   (printf "~a: ~a~n" name (if (foreign-entry? name) "present" "absent")))
 '("sqlite3_changes64" "sqlite3_total_changes64" "sqlite3_last_insert_rowid"
   "sqlite3_set_last_insert_rowid" "sqlite3_get_autocommit" "sqlite3_txn_state"
   "sqlite3_exec" "sqlite3_free" "sqlite3_prepare_v2" "sqlite3_prepare_v3"
   "sqlite3_stmt_busy" "sqlite3_stmt_readonly" "sqlite3_stmt_isexplain" "sqlite3_stmt_explain"
   "sqlite3_stmt_status" "sqlite3_sql" "sqlite3_expanded_sql" "sqlite3_normalized_sql"
   "sqlite3_db_status" "sqlite3_db_status64" "sqlite3_next_stmt" "sqlite3_db_handle"
   "sqlite3_limit" "sqlite3_db_readonly" "sqlite3_db_filename" "sqlite3_db_cacheflush"
   "sqlite3_db_release_memory" "sqlite3_hard_heap_limit64" "sqlite3_soft_heap_limit64"
   "sqlite3_busy_timeout" "sqlite3_busy_handler" "sqlite3_interrupt" "sqlite3_is_interrupted"
   "sqlite3_setlk_timeout" "sqlite3_wal_autocheckpoint" "sqlite3_wal_checkpoint_v2"
   "sqlite3_error_offset" "sqlite3_errstr" "sqlite3_extended_errcode"))
