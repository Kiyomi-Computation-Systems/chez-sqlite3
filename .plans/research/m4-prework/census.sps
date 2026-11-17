;;; census.sps: what one libsqlite3 is built with, and what it does (M4's
;;; pre-work).
;;;
;;; Usage: scheme --program census.sps LIBRARY
;;;
;;; Standalone, as varargs.sps is: it loads LIBRARY by that path with
;;; load-shared-object, binds what it needs with foreign-procedure, and loads
;;; none of chez-sqlite3's libraries. Every database is :memory:.
;;;
;;; It prints one datum per line, flushed as it goes:
;;;   - (constant NAME VALUE) for every number from sqlite3.h it uses, before
;;;     the load, for constants.c to hold to a header;
;;;   - sqlite3_libversion, sqlite3_sourceid, sqlite3_threadsafe, and every
;;;     option sqlite3_compileoption_get gives until it answers NULL;
;;;   - whether sqlite3_load_extension, and sqlite3_enable_load_extension,
;;;     resolve, by foreign-entry? (which asks the whole process: this one
;;;     loads one SQLite);
;;;   - FTS5: an fts5 table, a row, and a MATCH query;
;;;   - JSON: json('{}'), and jsonb('{}') with its column's type and bytes;
;;;   - DQS: select "x" with nothing changed;
;;;   - each db_config op's starting value, read with -1 through
;;;     sqlite3_db_config bound with (__varargs_after 2), on a fresh
;;;     connection each.
;;; The steps run in the order written (AGENTS.md).
(import (chezscheme))

;; emit : Any ... -> Void
(define (emit . items)
  (let ((port (current-output-port)))
    (write items port)
    (newline port)
    (flush-output-port port)))

;; byte-text : Byte -> String
;; Printable ASCII but % as itself, any other byte as %HH.
(define (byte-text b)
  (if (and (>= b #x20) (<= b #x7e) (not (= b #x25)))
      (string (integer->char b))
      (let ((hex (string-upcase (number->string b 16))))
        (string-append "%" (if (< b 16) "0" "") hex))))

;; bytes-text : Integer Integer -> String
(define (bytes-text address n)
  (let loop ((i 0) (parts '()))
    (if (= i n)
        (apply string-append (reverse parts))
        (loop (+ i 1) (cons (byte-text (foreign-ref 'unsigned-8 address i)) parts)))))

;; bytes-hex : Integer Integer -> String
;; The N bytes at ADDRESS as hex, two digits each.
(define (bytes-hex address n)
  (let loop ((i 0) (parts '()))
    (if (= i n)
        (apply string-append (reverse parts))
        (let* ((b (foreign-ref 'unsigned-8 address i))
               (hex (string-upcase (number->string b 16))))
          (loop (+ i 1) (cons (string-append (if (< b 16) "0" "") hex) parts))))))

;; c-text : Integer -> (U String 'null)
(define (c-text address)
  (if (= address 0)
      'null
      (let count ((n 0))
        (if (= (foreign-ref 'unsigned-8 address n) 0)
            (bytes-text address n)
            (count (+ n 1))))))

(define library-path
  (let ((args (command-line-arguments)))
    (if (= (length args) 1)
        (car args)
        (begin
          (display "usage: scheme --program census.sps LIBRARY\n" (current-error-port))
          (exit 2)))))

;; The numbers from sqlite3.h, written once.
(define constants
  '((SQLITE_OK . 0)
    (SQLITE_ROW . 100)
    (SQLITE_DONE . 101)
    (SQLITE_INTEGER . 1)
    (SQLITE_FLOAT . 2)
    (SQLITE_TEXT . 3)
    (SQLITE_BLOB . 4)
    (SQLITE_NULL . 5)
    (SQLITE_OPEN_READWRITE . 2)
    (SQLITE_OPEN_CREATE . 4)
    (SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION . 1005)
    (SQLITE_DBCONFIG_DEFENSIVE . 1010)
    (SQLITE_DBCONFIG_DQS_DML . 1013)
    (SQLITE_DBCONFIG_DQS_DDL . 1014)
    (SQLITE_DBCONFIG_TRUSTED_SCHEMA . 1017)))

;; k : Symbol -> Integer
(define (k name)
  (let ((entry (assq name constants)))
    (if entry
        (cdr entry)
        (begin (emit 'internal-error 'no-constant name) (exit 1)))))

(define ops
  '((ENABLE_LOAD_EXTENSION . SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION)
    (DEFENSIVE . SQLITE_DBCONFIG_DEFENSIVE)
    (DQS_DML . SQLITE_DBCONFIG_DQS_DML)
    (DQS_DDL . SQLITE_DBCONFIG_DQS_DDL)
    (TRUSTED_SCHEMA . SQLITE_DBCONFIG_TRUSTED_SCHEMA)))

(for-each (lambda (entry) (emit 'constant (car entry) (cdr entry))) constants)
(emit 'path library-path)
(emit 'chez (scheme-version))
(emit 'machine-type (machine-type))

(let ((loaded (guard (e (#t (call-with-string-output-port
                             (lambda (p) (display-condition e p)))))
                (load-shared-object library-path)
                #t)))
  (emit 'loaded loaded)
  (unless (eq? loaded #t) (exit 1)))

;; Every binding follows the load, and takes no Scheme object (ADR-0011).
(define libversion (foreign-procedure "sqlite3_libversion" () uptr))
(define libversion-number (foreign-procedure "sqlite3_libversion_number" () int))
(define sourceid (foreign-procedure "sqlite3_sourceid" () uptr))
(define threadsafe (foreign-procedure "sqlite3_threadsafe" () int))
(define compileoption-get (foreign-procedure "sqlite3_compileoption_get" (int) uptr))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (uptr uptr int uptr) int))
(define close-db (foreign-procedure "sqlite3_close" (uptr) int))
(define errmsg (foreign-procedure "sqlite3_errmsg" (uptr) uptr))
(define prepare-v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int))
(define step (foreign-procedure "sqlite3_step" (uptr) int))
(define column-type (foreign-procedure "sqlite3_column_type" (uptr int) int))
(define column-text (foreign-procedure "sqlite3_column_text" (uptr int) uptr))
(define column-blob (foreign-procedure "sqlite3_column_blob" (uptr int) uptr))
(define column-bytes (foreign-procedure "sqlite3_column_bytes" (uptr int) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define db-config
  (foreign-procedure (__varargs_after 2) "sqlite3_db_config" (uptr int int uptr) int))

(emit 'libversion (c-text (libversion)))
(emit 'libversion-number (libversion-number))
(emit 'sourceid (c-text (sourceid)))
(emit 'threadsafe (threadsafe))

(let loop ((i 0))
  (let ((address (compileoption-get i)))
    (if (= address 0)
        (emit 'compile-options-count i)
        (begin
          (emit 'option (c-text address))
          (loop (+ i 1))))))

(emit 'entry "sqlite3_load_extension" (foreign-entry? "sqlite3_load_extension"))
(emit 'entry "sqlite3_enable_load_extension" (foreign-entry? "sqlite3_enable_load_extension"))

;; with-block : Integer (Integer -> Any) -> Any
(define (with-block n proc)
  (let ((block (foreign-alloc n)))
    (dynamic-wind
      (lambda () #f)
      (lambda () (proc block))
      (lambda () (foreign-free block)))))

;; with-cell : Integer (Integer -> Any) -> Any
(define (with-cell sentinel proc)
  (with-block 8
    (lambda (cell)
      (foreign-set! 'uptr cell 0 0)
      (foreign-set! 'int cell 0 sentinel)
      (proc cell))))

;; with-c-string : String (Integer -> Any) -> Any
(define (with-c-string s proc)
  (let* ((bytes (string->utf8 s))
         (n (bytevector-length bytes)))
    (with-block (+ n 1)
      (lambda (block)
        (do ((i 0 (+ i 1))) ((= i n))
          (foreign-set! 'unsigned-8 block i (bytevector-u8-ref bytes i)))
        (foreign-set! 'unsigned-8 block n 0)
        (proc block)))))

;; call-with-memory-db : (Integer -> Any) -> Any
(define (call-with-memory-db proc)
  (let* ((opened (with-c-string ":memory:"
                   (lambda (name)
                     (with-cell 0
                       (lambda (cell)
                         (let* ((rc (open-v2 name cell
                                             (logior (k 'SQLITE_OPEN_READWRITE)
                                                     (k 'SQLITE_OPEN_CREATE))
                                             0))
                                (db (foreign-ref 'uptr cell 0)))
                           (cons rc db)))))))
         (rc (car opened))
         (db (cdr opened)))
    (unless (= rc (k 'SQLITE_OK))
      (emit 'open-failed rc)
      (unless (= db 0) (close-db db))
      (exit 1))
    (let* ((answer (proc db))
           (closed (close-db db)))
      (unless (= closed (k 'SQLITE_OK))
        (emit 'close-failed closed)
        (exit 1))
      answer)))

;; type-name : Integer -> Symbol
(define (type-name t)
  (cond ((= t (k 'SQLITE_INTEGER)) 'integer)
        ((= t (k 'SQLITE_FLOAT)) 'float)
        ((= t (k 'SQLITE_TEXT)) 'text)
        ((= t (k 'SQLITE_BLOB)) 'blob)
        ((= t (k 'SQLITE_NULL)) 'null)
        (else t)))

;; run-sql : Integer String -> List
;; Prepares SQL, steps it once: (row TYPE VALUE) with a BLOB's bytes as hex
;; and anything else as text; (done); (prepare-error RC MESSAGE) or
;; (step-error RC MESSAGE). The statement is finalized either way.
(define (run-sql db sql)
  (with-c-string sql
    (lambda (text)
      (with-cell 0
        (lambda (cell)
          (let ((rc (prepare-v2 db text -1 cell 0)))
            (if (not (= rc (k 'SQLITE_OK)))
                (list 'prepare-error rc (c-text (errmsg db)))
                (let* ((stmt (foreign-ref 'uptr cell 0))
                       (s (step stmt))
                       (answer
                        (cond ((= s (k 'SQLITE_ROW))
                               (let ((t (column-type stmt 0)))
                                 (if (= t (k 'SQLITE_BLOB))
                                     (let* ((address (column-blob stmt 0))
                                            (n (column-bytes stmt 0)))
                                       (list 'row 'blob (if (= address 0) "" (bytes-hex address n))))
                                     (let* ((address (column-text stmt 0))
                                            (n (column-bytes stmt 0)))
                                       (list 'row (type-name t)
                                             (if (= address 0) 'null (bytes-text address n)))))))
                              ((= s (k 'SQLITE_DONE)) (list 'done))
                              (else (list 'step-error s (c-text (errmsg db))))))
                       (finalized (finalize stmt)))
                  answer))))))))

;; probe-sql : Symbol (Listof String) -> Void
;; Runs each of SQLS in turn on one fresh connection, printing each answer
;; under KEY.
(define (probe-sql key sqls)
  (call-with-memory-db
   (lambda (db)
     (for-each (lambda (sql)
                 (let ((answer (run-sql db sql)))
                   (emit key sql answer)))
               sqls))))

(probe-sql 'fts5 '("create virtual table f using fts5(body)"
                   "insert into f(body) values ('hello world')"
                   "select count(*) from f where f match 'hello'"))
(probe-sql 'json '("select json('{}')"))
(probe-sql 'jsonb '("select jsonb('{}')"))
(probe-sql 'dqs '("select \"x\""))

(for-each
 (lambda (op)
   (call-with-memory-db
    (lambda (db)
      (with-cell -100
        (lambda (cell)
          (let* ((rc (db-config db (k (cdr op)) -1 cell))
                 (out (foreign-ref 'int cell 0)))
            (emit 'db-config-start (car op) 'rc rc 'out (if (= out -100) 'untouched out))))))))
 ops)

(emit 'finished)
