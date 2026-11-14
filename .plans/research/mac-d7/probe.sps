;;; Brief D7: what a Mac's SQLite is, and whether it can load extensions.
;;;
;;; Usage: scheme --program probe.sps PATH
;;;
;;; Loads the libsqlite3 at PATH by that path alone, through bare FFI, and
;;; prints one datum per line, (KEY . VALUE). Nothing here is chez-sqlite3's
;;; code, and nothing is written to disk: the one database is :memory:.
;;;
;;; It answers, for that library:
;;;   - whether load-shared-object loads it, and whether a file is there
;;;     (Apple's lives in the dyld shared cache, with no file on disk);
;;;   - its version, version number, source id and threadsafe setting;
;;;   - every compile option it reports;
;;;   - which of the entry points v1 binds are missing;
;;;   - SQLite's memory count before an open, while open, and after the close;
;;;   - whether JSON, JSONB and FTS5 work;
;;;   - extension loading through the C call v1 uses (brief §2.5):
;;;     sqlite3_db_config's ENABLE_LOAD_EXTENSION, read before and after it is
;;;     turned on, then sqlite3_load_extension on a path that doesn't exist,
;;;     whose message says whether loading was even tried; and whether SQL's
;;;     load_extension() stays refused after the C call is turned on.
;;;
;;; Each step that can raise is guarded and prints (KEY raised MESSAGE), so
;;; one failure doesn't hide the answers after it. The steps run in the order
;;; written: every effect is in a let* or a sequence (AGENTS.md).
(import (chezscheme))

;; show : Symbol Any -> Void
(define (show key value)
  (write (cons key value))
  (newline))

;; message-of : Condition -> String
(define (message-of e)
  (call-with-string-output-port (lambda (p) (display-condition e p))))

;; step : Symbol (-> Any) -> Void
;; Prints KEY with THUNK's value, or with what it raised.
(define (step key thunk)
  (let ((answer (guard (e (#t (list 'raised (message-of e)))) (list 'value (thunk)))))
    (if (eq? (car answer) 'value)
        (show key (cadr answer))
        (show key answer))))

(define path
  (let ((args (command-line-arguments)))
    (if (= (length args) 1)
        (car args)
        (begin (display "usage: probe.sps PATH\n" (current-error-port)) (exit 2)))))

(show 'path path)
(show 'chez (scheme-version))
(show 'machine-type (machine-type))
(show 'threaded (threaded?))
(show 'file-on-disk (file-exists? path))

(let ((loaded (guard (e (#t (message-of e))) (load-shared-object path) #t)))
  (show 'loaded loaded)
  (unless (eq? loaded #t) (exit 1)))

;; Every binding below follows the load, in the order written.
(define libversion (foreign-procedure "sqlite3_libversion" () utf-8))
(define libversion-number (foreign-procedure "sqlite3_libversion_number" () int))
(define sourceid (foreign-procedure "sqlite3_sourceid" () utf-8))
(define threadsafe (foreign-procedure "sqlite3_threadsafe" () int))
(define compileoption-get (foreign-procedure "sqlite3_compileoption_get" (int) utf-8))
(define memory-used (foreign-procedure "sqlite3_memory_used" () integer-64))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define errmsg (foreign-procedure "sqlite3_errmsg" (uptr) utf-8))
(define prepare-v2 (foreign-procedure "sqlite3_prepare_v2" (uptr string int uptr uptr) int))
(define sqlite-step (foreign-procedure "sqlite3_step" (uptr) int))
(define column-text (foreign-procedure "sqlite3_column_text" (uptr int) utf-8))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define sqlite-free (foreign-procedure "sqlite3_free" (uptr) void))

(define SQLITE_OK 0)
(define SQLITE_ROW 100)
(define SQLITE_OPEN_READWRITE #x2)
(define SQLITE_OPEN_CREATE #x4)
(define SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION 1005)

(show 'libversion (libversion))
(show 'libversion-number (libversion-number))
(show 'sourceid (sourceid))
(show 'threadsafe (threadsafe))

;; compile-options : -> (Listof String)
(define (compile-options)
  (let loop ((i 0) (acc '()))
    (let ((o (compileoption-get i)))
      (if o (loop (+ i 1) (cons o acc)) (reverse acc)))))
(show 'compile-options (compile-options))

;; The entry points v1 binds (brief §4), M1 to M4.
(define v1-entries
  '("sqlite3_libversion" "sqlite3_libversion_number" "sqlite3_sourceid" "sqlite3_threadsafe"
    "sqlite3_compileoption_used" "sqlite3_compileoption_get" "sqlite3_open_v2" "sqlite3_close"
    "sqlite3_errcode" "sqlite3_extended_errcode" "sqlite3_errmsg" "sqlite3_errstr"
    "sqlite3_error_offset" "sqlite3_prepare_v3" "sqlite3_step" "sqlite3_reset"
    "sqlite3_clear_bindings" "sqlite3_finalize" "sqlite3_bind_int64" "sqlite3_bind_double"
    "sqlite3_bind_text" "sqlite3_bind_blob" "sqlite3_bind_null" "sqlite3_bind_parameter_count"
    "sqlite3_bind_parameter_index" "sqlite3_bind_parameter_name" "sqlite3_column_count"
    "sqlite3_column_name" "sqlite3_column_type" "sqlite3_column_int64" "sqlite3_column_double"
    "sqlite3_column_text" "sqlite3_column_blob" "sqlite3_column_bytes" "sqlite3_next_stmt"
    "sqlite3_changes64" "sqlite3_total_changes64" "sqlite3_last_insert_rowid"
    "sqlite3_busy_timeout" "sqlite3_interrupt" "sqlite3_memory_used" "sqlite3_db_config"
    "sqlite3_load_extension" "sqlite3_enable_load_extension" "sqlite3_free"))
(show 'entries-checked (length v1-entries))
(show 'entries-missing (filter (lambda (e) (not (foreign-entry? e))) v1-entries))

;; c-string : Integer -> (U String #f)
;; The NUL-terminated UTF-8 string at ADDRESS, or #f for NULL.
(define (c-string address)
  (if (= address 0)
      #f
      (let loop ((i 0))
        (if (= (foreign-ref 'unsigned-8 address i) 0)
            (let ((bv (make-bytevector i)))
              (do ((j 0 (+ j 1))) ((= j i))
                (bytevector-u8-set! bv j (foreign-ref 'unsigned-8 address j)))
              (utf8->string bv))
            (loop (+ i 1))))))

;; with-cell : (Integer -> Any) -> Any
;; Calls PROC with a zeroed 8-byte foreign cell, freed afterwards.
(define (with-cell proc)
  (let ((cell (foreign-alloc 8)))
    (foreign-set! 'uptr cell 0 0)
    (let ((answer (proc cell)))
      (foreign-free cell)
      answer)))

;; sql : Integer String -> (List Symbol Any)
;; Prepares SQL on DB and steps it once: (row TEXT) for a row's first column,
;; (done RC) for no row, or (error RC MESSAGE).
(define (sql db text)
  (with-cell
   (lambda (cell)
     (let ((rc (prepare-v2 db text -1 cell 0)))
       (if (not (= rc SQLITE_OK))
           (list 'error rc (errmsg db))
           (let* ((stmt (foreign-ref 'uptr cell 0))
                  (s (sqlite-step stmt))
                  (answer (cond ((= s SQLITE_ROW) (list 'row (column-text stmt 0)))
                                ((= s 101) (list 'done s))
                                (else (list 'error s (errmsg db))))))
             (finalize stmt)
             answer))))))

(show 'memory-used-before-open (memory-used))

(let* ((opened (with-cell
                (lambda (cell)
                  (let ((rc (open-v2 ":memory:" cell (logior SQLITE_OPEN_READWRITE SQLITE_OPEN_CREATE) 0)))
                    (cons rc (foreign-ref 'uptr cell 0))))))
       (rc (car opened))
       (db (cdr opened)))
  (show 'open-rc rc)
  (unless (= rc SQLITE_OK) (exit 1))
  (show 'memory-used-while-open (memory-used))
  (step 'sqlite-version (lambda () (sql db "SELECT sqlite_version()")))
  (step 'json (lambda () (sql db "SELECT json('{\"a\":1}')")))
  (step 'jsonb-type (lambda () (sql db "SELECT typeof(jsonb('{}'))")))
  (step 'fts5 (lambda () (sql db "CREATE VIRTUAL TABLE probe_fts USING fts5(body)")))
  (if (foreign-entry? "sqlite3_db_config")
      (let ((db-config (foreign-procedure (__varargs_after 2) "sqlite3_db_config"
                                          (uptr int int uptr) int)))
        ;; db-config-load : Integer -> (List Integer Integer)
        ;; ONOFF 1 turns the C call on, -1 only asks; the answer is (rc setting).
        (define (db-config-load onoff)
          (with-cell
           (lambda (cell)
             (foreign-set! 'int cell 0 -7)
             (let ((rc (db-config db SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION onoff cell)))
               (list rc (foreign-ref 'int cell 0))))))
        (step 'db-config-load-extension-before (lambda () (db-config-load -1)))
        (step 'db-config-load-extension-on (lambda () (db-config-load 1)))
        (step 'db-config-load-extension-after (lambda () (db-config-load -1))))
      (show 'db-config 'missing))
  (if (foreign-entry? "sqlite3_load_extension")
      (let ((load-extension (foreign-procedure "sqlite3_load_extension"
                                               (uptr string uptr uptr) int)))
        (step 'load-extension-nonexistent
              (lambda ()
                (with-cell
                 (lambda (cell)
                   (let* ((rc (load-extension db "/nonexistent/chez-sqlite3-probe-extension" 0 cell))
                          (address (foreign-ref 'uptr cell 0))
                          (message (c-string address)))
                     (unless (= address 0) (sqlite-free address))
                     (list rc message)))))))
      (show 'load-extension 'missing))
  (step 'sql-load-extension
        (lambda () (sql db "SELECT load_extension('/nonexistent/chez-sqlite3-probe-extension')")))
  (show 'close-rc (close db)))

(show 'memory-used-after-close (memory-used))
