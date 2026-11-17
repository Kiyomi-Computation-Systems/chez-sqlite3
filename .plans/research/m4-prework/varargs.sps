;;; varargs.sps: sqlite3_db_config, bound with (__varargs_after 2) and plain,
;;; on one libsqlite3 (M4's pre-work).
;;;
;;; Usage: scheme --program varargs.sps LIBRARY [all | varargs | plain]
;;;
;;; Standalone: it loads LIBRARY by that path with load-shared-object and
;;; binds what it needs with foreign-procedure. It loads none of
;;; chez-sqlite3's libraries, so it runs from this one file, on a Mac too.
;;; Every database is :memory:, and nothing is written to disk.
;;;
;;; It prints one datum per line, flushed as it goes, so a crash keeps every
;;; line before it. The lines that start with a binding's label, varargs or
;;; plain, are the ones varargs.c prints under the label c, in the same
;;; order, and run.sh compares them.
;;;
;;;   - (constant NAME VALUE) for every number from sqlite3.h the probe
;;;     uses, and (unknown-op N): constants.c holds them to each header.
;;;     They are written once, below, and every use reads them from there.
;;;   - varargs: sqlite3_db_config bound with (__varargs_after 2), in the
;;;     shape (db op int int*), for ENABLE_LOAD_EXTENSION, DEFENSIVE,
;;;     DQS_DML, DQS_DDL and TRUSTED_SCHEMA. Each is read with -1, set to 0,
;;;     read, set to 1, read, set back to its starting value and read, on a
;;;     connection of its own. Each call's int cell starts at a sentinel of
;;;     its own, printed as `untouched` when the call left it. Then an
;;;     unknown op; then each op's behaviour with the setting 0 and 1, on a
;;;     fresh connection each; then the shape LOOKASIDE takes,
;;;     (db op void* int int), with lookaside's counters read after a small
;;;     workload.
;;;   - plain: the same (db op int int*) shape bound with no convention, and
;;;     the same read-backs and unknown op under its own label. On Apple
;;;     arm64 a variadic argument goes on the stack, so this binding hands C
;;;     whatever is there: it may print garbage, or crash. So it runs last,
;;;     and `plain` alone runs it in a process of its own.
;;;
;;; MODE all, the default, runs varargs then plain. The steps run in the
;;; order written: every sequence of effects is a let* or a body, never a
;;; call's arguments, and no map runs an effect (AGENTS.md).
(import (chezscheme))

;; --- output -------------------------------------------------------------------

;; emit : Any ... -> Void
;; Writes ITEMS as one list on one line, and flushes it.
(define (emit . items)
  (let ((port (current-output-port)))
    (write items port)
    (newline port)
    (flush-output-port port)))

;; byte-text : Byte -> String
;; One byte as varargs.c prints it: printable ASCII but % as itself, any
;; other byte as %HH. So the text decodes nothing, and the two agree.
(define (byte-text b)
  (if (and (>= b #x20) (<= b #x7e) (not (= b #x25)))
      (string (integer->char b))
      (let ((hex (string-upcase (number->string b 16))))
        (string-append "%" (if (< b 16) "0" "") hex))))

;; bytes-text : Integer Integer -> String
;; The N bytes at ADDRESS, each by byte-text.
(define (bytes-text address n)
  (let loop ((i 0) (parts '()))
    (if (= i n)
        (apply string-append (reverse parts))
        (loop (+ i 1) (cons (byte-text (foreign-ref 'unsigned-8 address i)) parts)))))

;; c-text : Integer -> (U String 'null)
;; The NUL-terminated bytes at ADDRESS, by byte-text, or null for NULL.
(define (c-text address)
  (if (= address 0)
      'null
      (let count ((n 0))
        (if (= (foreign-ref 'unsigned-8 address n) 0)
            (bytes-text address n)
            (count (+ n 1))))))

;; --- arguments ----------------------------------------------------------------

(define arguments (command-line-arguments))

(define (usage)
  (display "usage: scheme --program varargs.sps LIBRARY [all | varargs | plain]\n"
           (current-error-port))
  (exit 2))

(define library-path
  (if (and (>= (length arguments) 1) (<= (length arguments) 2))
      (car arguments)
      (usage)))

(define mode
  (cond ((= (length arguments) 1) 'all)
        ((member (cadr arguments) '("all" "varargs" "plain")) (string->symbol (cadr arguments)))
        (else (usage))))

;; --- the numbers from sqlite3.h, written once ------------------------------------

(define constants
  '((SQLITE_OK . 0)
    (SQLITE_ERROR . 1)
    (SQLITE_BUSY . 5)
    (SQLITE_MISUSE . 21)
    (SQLITE_ROW . 100)
    (SQLITE_DONE . 101)
    (SQLITE_OPEN_READWRITE . 2)
    (SQLITE_OPEN_CREATE . 4)
    (SQLITE_DBCONFIG_LOOKASIDE . 1001)
    (SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION . 1005)
    (SQLITE_DBCONFIG_DEFENSIVE . 1010)
    (SQLITE_DBCONFIG_DQS_DML . 1013)
    (SQLITE_DBCONFIG_DQS_DDL . 1014)
    (SQLITE_DBCONFIG_TRUSTED_SCHEMA . 1017)
    (SQLITE_DBSTATUS_LOOKASIDE_USED . 0)
    (SQLITE_DBSTATUS_LOOKASIDE_HIT . 4)
    (SQLITE_DBSTATUS_LOOKASIDE_MISS_SIZE . 5)
    (SQLITE_DBSTATUS_LOOKASIDE_MISS_FULL . 6)))

;; An op no header defines: constants.c checks it is above SQLITE_DBCONFIG_MAX.
(define unknown-op 1999)

;; k : Symbol -> Integer
(define (k name)
  (let ((entry (assq name constants)))
    (if entry
        (cdr entry)
        (begin (emit 'internal-error 'no-constant name) (exit 1)))))

;; The ops, by the label each line gives, in the order they run.
(define ops
  '((ENABLE_LOAD_EXTENSION . SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION)
    (DEFENSIVE . SQLITE_DBCONFIG_DEFENSIVE)
    (DQS_DML . SQLITE_DBCONFIG_DQS_DML)
    (DQS_DDL . SQLITE_DBCONFIG_DQS_DDL)
    (TRUSTED_SCHEMA . SQLITE_DBCONFIG_TRUSTED_SCHEMA)))

;; --- the header lines, then the load -------------------------------------------

(for-each (lambda (entry) (emit 'constant (car entry) (cdr entry))) constants)
(emit 'unknown-op unknown-op)
(emit 'path library-path)
(emit 'chez (scheme-version))
(emit 'machine-type (machine-type))
(emit 'mode mode)

(let ((loaded (guard (e (#t (call-with-string-output-port
                             (lambda (p) (display-condition e p)))))
                (load-shared-object library-path)
                #t)))
  (emit 'loaded loaded)
  (unless (eq? loaded #t) (exit 1)))

(unless (foreign-entry? "sqlite3_db_config")
  (emit 'missing-entry "sqlite3_db_config")
  (exit 1))

;; Every binding follows the load. No binding takes a Scheme object: strings
;; go in foreign blocks, and come back as addresses (ADR-0011).
(define libversion (foreign-procedure "sqlite3_libversion" () uptr))
(define sourceid (foreign-procedure "sqlite3_sourceid" () uptr))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (uptr uptr int uptr) int))
(define close-db (foreign-procedure "sqlite3_close" (uptr) int))
(define errmsg (foreign-procedure "sqlite3_errmsg" (uptr) uptr))
(define prepare-v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int))
(define step (foreign-procedure "sqlite3_step" (uptr) int))
(define column-text (foreign-procedure "sqlite3_column_text" (uptr int) uptr))
(define column-bytes (foreign-procedure "sqlite3_column_bytes" (uptr int) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define db-status (foreign-procedure "sqlite3_db_status" (uptr int uptr uptr int) int))

;; The bindings under test. Each shape is one binding (ADR-0001, decision 2).
(define db-config-varargs
  (foreign-procedure (__varargs_after 2) "sqlite3_db_config" (uptr int int uptr) int))
(define db-config-lookaside
  (foreign-procedure (__varargs_after 2) "sqlite3_db_config" (uptr int uptr int int) int))
(define db-config-plain
  (foreign-procedure "sqlite3_db_config" (uptr int int uptr) int))

(emit 'libversion (c-text (libversion)))
(emit 'sourceid (c-text (sourceid)))

;; --- foreign memory ------------------------------------------------------------

;; with-block : Integer (Integer -> Any) -> Any
;; Calls PROC with N bytes of foreign memory, freed however PROC leaves.
(define (with-block n proc)
  (let ((block (foreign-alloc n)))
    (dynamic-wind
      (lambda () #f)
      (lambda () (proc block))
      (lambda () (foreign-free block)))))

;; with-cell : Integer (Integer -> Any) -> Any
;; Calls PROC with an 8-byte cell whose int holds SENTINEL.
(define (with-cell sentinel proc)
  (with-block 8
    (lambda (cell)
      (foreign-set! 'uptr cell 0 0)
      (foreign-set! 'int cell 0 sentinel)
      (proc cell))))

;; with-c-string : String (Integer -> Any) -> Any
;; Calls PROC with S as NUL-terminated UTF-8 in a foreign block.
(define (with-c-string s proc)
  (let* ((bytes (string->utf8 s))
         (n (bytevector-length bytes)))
    (with-block (+ n 1)
      (lambda (block)
        (do ((i 0 (+ i 1))) ((= i n))
          (foreign-set! 'unsigned-8 block i (bytevector-u8-ref bytes i)))
        (foreign-set! 'unsigned-8 block n 0)
        (proc block)))))

;; --- connections and SQL -------------------------------------------------------

;; call-with-memory-db : (Integer -> Any) -> Any
;; Opens :memory:, calls PROC with the handle, and closes it. A failed open or
;; close prints a line and exits 1.
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

;; run-sql : Integer String -> List
;; Prepares SQL on DB and steps it once: (row TEXT) for the first column of a
;; row, null for a NULL; (done) for no row; (prepare-error RC MESSAGE) or
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
                               (let* ((address (column-text stmt 0))
                                      (n (column-bytes stmt 0)))
                                 (list 'row (if (= address 0) 'null (bytes-text address n)))))
                              ((= s (k 'SQLITE_DONE)) (list 'done))
                              (else (list 'step-error s (c-text (errmsg db))))))
                       (finalized (finalize stmt)))
                  answer))))))))

;; --- the round trips -----------------------------------------------------------

;; config-call : Procedure Integer Integer Integer Integer -> (Pair Integer Any)
;; BINDING's answer to (DB OP ONOFF cell), with the cell at SENTINEL first:
;; (rc . value), the value `untouched` when the call left the sentinel.
(define (config-call binding db op onoff sentinel)
  (with-cell sentinel
    (lambda (cell)
      (let* ((rc (binding db op onoff cell))
             (out (foreign-ref 'int cell 0)))
        (cons rc (if (= out sentinel) 'untouched out))))))

;; The seven calls of a round trip: the step's name and its onoff, where
;; `start` stands for the value the first read answered. Call I's sentinel
;; is -(100 + I).
(define round-trip-steps
  '((start . -1) (set-0 . 0) (read-0 . -1) (set-1 . 1) (read-1 . -1)
    (restore . start) (read-restored . -1)))

;; round-trip : Symbol Procedure Symbol Integer -> Void
;; Runs and prints the round trip of OP, named NAME, through BINDING, on a
;; connection of its own, then its verdict: ok when every call answered
;; SQLITE_OK and every value is the one it should be.
(define (round-trip label binding name op)
  (call-with-memory-db
   (lambda (db)
     (let loop ((steps round-trip-steps) (i 0) (start #f) (ok #t))
       (if (null? steps)
           (emit label 'verdict name (if ok 'ok 'fails))
           (let* ((step-name (caar steps))
                  (onoff (let ((o (cdar steps)))
                           (cond ((not (eq? o 'start)) o)
                                 ((memv start '(0 1)) start)
                                 (else -1))))
                  (answer (config-call binding db op onoff (- (+ 100 i))))
                  (rc (car answer))
                  (out (cdr answer))
                  (start* (if (= i 0) out start))
                  (expected (case step-name
                              ((start) (if (memv out '(0 1)) out 'any-bit))
                              ((set-0 read-0) 0)
                              ((set-1 read-1) 1)
                              (else start*)))
                  (good (and (= rc (k 'SQLITE_OK)) (eqv? out expected))))
             (emit label 'round-trip name step-name 'onoff onoff 'rc rc 'out out)
             (loop (cdr steps) (+ i 1) start* (and ok good))))))))

;; unknown : Symbol Procedure -> Void
(define (unknown label binding)
  (call-with-memory-db
   (lambda (db)
     (let ((answer (config-call binding db unknown-op -1 -150)))
       (emit label 'unknown-op unknown-op 'rc (car answer) 'out (cdr answer))))))

;; --- behaviour, through the varargs binding -----------------------------------

;; The SQL each op's behaviour runs, after the op is set.
(define behaviour-sql
  '((ENABLE_LOAD_EXTENSION "select load_extension('x')")
    (DEFENSIVE "create table t(a)"
               "PRAGMA writable_schema = 1"
               "PRAGMA writable_schema"
               "update sqlite_schema set sql = sql where name = 't'"
               "PRAGMA writable_schema = 0")
    (DQS_DML "select \"no_such_column\"")
    (DQS_DDL "create table t(a)"
             "create index i on t(\"no_such_column\")")))

;; behaviour : Symbol Symbol Integer Integer -> Void
;; On a fresh connection, sets OP, named NAME, to VALUE and runs NAME's SQL,
;; printing the set and each statement's answer.
(define (behaviour label name op value)
  (call-with-memory-db
   (lambda (db)
     (let ((answer (config-call db-config-varargs db op value -200)))
       (emit label 'behaviour name value 'config 'rc (car answer) 'out (cdr answer))
       (for-each (lambda (sql)
                   (let ((answer (run-sql db sql)))
                     (emit label 'behaviour name value sql answer)))
                 (cdr (assq name behaviour-sql)))))))

;; --- the LOOKASIDE shape --------------------------------------------------------

(define lookaside-workload
  '("create table t(a, b)"
    "insert into t values (1, 'one'), (2, 'two'), (3, 'three')"
    "select count(*) from t"))

(define lookaside-stats
  '((used . SQLITE_DBSTATUS_LOOKASIDE_USED)
    (hit . SQLITE_DBSTATUS_LOOKASIDE_HIT)
    (miss-size . SQLITE_DBSTATUS_LOOKASIDE_MISS_SIZE)
    (miss-full . SQLITE_DBSTATUS_LOOKASIDE_MISS_FULL)))

;; lookaside : Symbol Integer Integer -> Void
;; On a fresh connection: LOOKASIDE with a NULL buffer, SZ and CNT; the
;; workload; each counter's current and highwater. With SZ under 256 SQLite
;; makes CNT slots of SZ bytes, so a saturated highwater shows CNT arrived,
;; and the misses for size move with SZ. Then LOOKASIDE again, (NULL, 120,
;; 3), while a statement is held at a row, and once more after its
;; finalize: SQLite refuses with SQLITE_BUSY while a slot is in use.
(define (lookaside label sz cnt)
  (call-with-memory-db
   (lambda (db)
     (let ((rc (db-config-lookaside db (k 'SQLITE_DBCONFIG_LOOKASIDE) 0 sz cnt)))
       (emit label 'lookaside sz cnt 'config 'rc rc))
     (for-each (lambda (sql)
                 (let ((answer (run-sql db sql)))
                   (emit label 'lookaside sz cnt sql answer)))
               lookaside-workload)
     (for-each
      (lambda (stat)
        (with-cell -300
          (lambda (current)
            (with-cell -301
              (lambda (highwater)
                (let* ((rc (db-status db (k (cdr stat)) current highwater 0))
                       (c (foreign-ref 'int current 0))
                       (h (foreign-ref 'int highwater 0)))
                  (emit label 'lookaside sz cnt 'status (car stat) 'rc rc 'cur c 'hi h)))))))
      lookaside-stats)
     (with-c-string "select a from t"
       (lambda (text)
         (with-cell 0
           (lambda (cell)
             (let* ((prepared (prepare-v2 db text -1 cell 0))
                    (stmt (foreign-ref 'uptr cell 0))
                    (stepped (if (= prepared (k 'SQLITE_OK)) (step stmt) 'not-prepared))
                    (held (db-config-lookaside db (k 'SQLITE_DBCONFIG_LOOKASIDE) 0 120 3))
                    (finalized (if (= stmt 0) 'no-statement (finalize stmt)))
                    (after (db-config-lookaside db (k 'SQLITE_DBCONFIG_LOOKASIDE) 0 120 3)))
               (emit label 'lookaside sz cnt 'reconfigure 'prepare prepared 'step stepped
                     'held-rc held 'finalize finalized 'after-rc after)))))))))

;; --- the run --------------------------------------------------------------------

(when (memq mode '(all varargs))
  (for-each (lambda (op) (round-trip 'varargs db-config-varargs (car op) (k (cdr op)))) ops)
  (unknown 'varargs db-config-varargs)
  (for-each
   (lambda (op)
     (when (assq (car op) behaviour-sql)
       (behaviour 'varargs (car op) (k (cdr op)) 0)
       (behaviour 'varargs (car op) (k (cdr op)) 1)))
   ops)
  (lookaside 'varargs 120 7)
  (lookaside 'varargs 120 5)
  (lookaside 'varargs 200 7)
  (lookaside 'varargs 0 0))

(when (memq mode '(all plain))
  (for-each (lambda (op) (round-trip 'plain db-config-plain (car op) (k (cdr op)))) ops)
  (unknown 'plain db-config-plain))

(emit 'finished mode)
