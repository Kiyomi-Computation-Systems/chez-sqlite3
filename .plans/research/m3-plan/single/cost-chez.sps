;;; B4: what preparing costs against reusing a prepared statement, through
;;; Chez's bare FFI, from the library CHEZ_SQLITE3_LIBRARY names.
;;;
;;;   CHEZ_SQLITE3_LIBRARY=... $CHEZ --script cost-chez.sps DIR NUMBER SOURCE-ID
;;;
;;; NUMBER and SOURCE-ID are the header's SQLITE_VERSION_NUMBER and
;;; SQLITE_SOURCE_ID (run.sh reads them); the probe refuses to run unless the
;;; library's own equal them. DIR is unused: the database is :memory:.
;;;
;;; The same four loops as cost.c, each shaped the way ADR-0011, ADR-0014 and
;;; ADR-0015 have the library call SQLite: the SQL encoded with string->utf8
;;; and copied into a foreign block, passed to sqlite3_prepare_v3 with its
;;; byte length, with the statement and the tail as foreign out-parameters,
;;; each block freed after; text bound through sqlite3_bind_text64 from a
;;; block of its own, SQLITE_TRANSIENT; a TEXT column read as
;;; sqlite3_column_type, then sqlite3_column_text and sqlite3_column_bytes,
;;; copied into a bytevector and decoded.
;;; Each loop is run four times over: with prepare, step, reset and finalize
;;; bound __collect_safe (as ADR-0011 binds them), and bound plain; each with
;;; prepare flags 0 (as ADR-0014's prepare passes them) and with
;;; SQLITE_PREPARE_PERSISTENT. The reused statements are prepared with the
;;; same flags as the loops that prepare each round. The select loop's
;;; statement is reset, outside the timing, after each run, so no read stays
;;; open into the next run's inserts. Every return code is checked.
;;;
;;; What this leaves out of the library's prepare: its critical sections, the
;;; record and state checks, the counters behind their mutex, and the tail
;;; scan and the U+0000 scan in Scheme. So the saving it measures is a lower
;;; bound.
;;;
;;; Every effect is ordered by let*, begin or a named let (AGENTS.md). Lines
;;; starting "time:" are timings, ns per round, min / median / max over the
;;; runs, on a shared machine; every other line is compared byte for byte.
(import (chezscheme))

(define rounds 2000)
(define runs 25)

(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))

(define libversion-number (foreign-procedure "sqlite3_libversion_number" () int))
(define libversion (foreign-procedure "sqlite3_libversion" () string))
(define sourceid (foreign-procedure "sqlite3_sourceid" () string))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define exec (foreign-procedure "sqlite3_exec" (uptr string uptr uptr uptr) int))
(define prepare-safe (foreign-procedure __collect_safe "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define step-safe (foreign-procedure __collect_safe "sqlite3_step" (uptr) int))
(define reset-safe (foreign-procedure __collect_safe "sqlite3_reset" (uptr) int))
(define finalize-safe (foreign-procedure __collect_safe "sqlite3_finalize" (uptr) int))
(define prepare-plain (foreign-procedure "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define step-plain (foreign-procedure "sqlite3_step" (uptr) int))
(define reset-plain (foreign-procedure "sqlite3_reset" (uptr) int))
(define finalize-plain (foreign-procedure "sqlite3_finalize" (uptr) int))
(define bind-text64 (foreign-procedure "sqlite3_bind_text64" (uptr int uptr unsigned-64 iptr unsigned-8) int))
(define bind-int64 (foreign-procedure "sqlite3_bind_int64" (uptr int integer-64) int))
(define column-type (foreign-procedure "sqlite3_column_type" (uptr int) int))
(define column-int64 (foreign-procedure "sqlite3_column_int64" (uptr int) integer-64))
(define column-text (foreign-procedure "sqlite3_column_text" (uptr int) uptr))
(define column-bytes (foreign-procedure "sqlite3_column_bytes" (uptr int) int))

(define READWRITE #x2)
(define CREATE #x4)
(define FULLMUTEX #x10000)
(define EXRESCODE #x02000000)
(define PERSISTENT #x01)
(define TRANSIENT -1)
(define UTF8 1)
(define ROW 100)
(define DONE 101)

(define (check what rc want)
  (unless (= rc want) (error 'cost-chez "unexpected answer" what rc want)))

(let* ([args (command-line-arguments)]
       [number (cadr args)]
       [source (caddr args)])
  (unless (and (string=? number (number->string (libversion-number)))
               (string=? source (sourceid)))
    (error 'cost-chez "the library is not the header's" number source (libversion-number) (sourceid))))

(printf "libversion: ~a~n" (libversion))
(printf "sourceid: ~a~n" (sourceid))
(printf "rounds per loop ~a, runs ~a~n" rounds runs)

;; bytes->block : Bytevector -> Address, a copy with a NUL after it
(define (bytes->block bv)
  (let* ([n (bytevector-length bv)]
         [p (foreign-alloc (+ n 1))])
    (let loop ([i 0])
      (when (< i n)
        (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bv i))
        (loop (+ i 1))))
    (foreign-set! 'unsigned-8 p n 0)
    p))

;; prepare : Procedure Address String Natural -> Address
(define (prepare prep db sql flags)
  (let* ([bv (string->utf8 (string-copy sql))]
         [block (bytes->block bv)]
         [cell (foreign-alloc 8)]
         [tail (foreign-alloc 8)]
         [rc (prep db block (bytevector-length bv) flags cell tail)]
         [st (foreign-ref 'uptr cell 0)])
    (foreign-free tail)
    (foreign-free cell)
    (foreign-free block)
    (check 'prepare rc 0)
    st))

;; bind-string! : Address Natural String -> Void
(define (bind-string! st i s)
  (let* ([bv (string->utf8 (string-copy s))]
         [block (bytes->block bv)]
         [rc (bind-text64 st i block (bytevector-length bv) TRANSIENT UTF8)])
    (foreign-free block)
    (check 'bind rc 0)))

;; column-string : Address Natural -> String
(define (column-string st i)
  (let* ([type (column-type st i)]
         [p (column-text st i)]
         [n (column-bytes st i)]
         [bv (make-bytevector n)])
    (check 'type type 3)
    (let loop ([k 0])
      (when (< k n)
        (bytevector-u8-set! bv k (foreign-ref 'unsigned-8 p k))
        (loop (+ k 1))))
    (utf8->string bv)))

(define insert-sql "INSERT INTO t(name, n) VALUES (?1, ?2)")
(define select-sql "SELECT name, n FROM t WHERE id = ?1")
(define checksum 0)

(define (insert-prepare db prep step finalize base flags)
  (let loop ([i 0])
    (when (< i rounds)
      (let* ([st (prepare prep db insert-sql flags)])
        (bind-string! st 1 "a typical name")
        (check 'bind (bind-int64 st 2 (+ base i)) 0)
        (check 'step (step st) DONE)
        (check 'finalize (finalize st) 0))
      (loop (+ i 1)))))

(define (insert-reuse st step reset base)
  (let loop ([i 0])
    (when (< i rounds)
      (check 'reset (reset st) 0)
      (bind-string! st 1 "a typical name")
      (check 'bind (bind-int64 st 2 (+ base i)) 0)
      (check 'step (step st) DONE)
      (loop (+ i 1)))))

(define (read-row! st)
  (let* ([name (column-string st 0)]
         [n (column-int64 st 1)])
    (set! checksum (+ checksum (string-length name) n))))

(define (select-prepare db prep step finalize flags)
  (let loop ([i 0])
    (when (< i rounds)
      (let* ([st (prepare prep db select-sql flags)])
        (check 'bind (bind-int64 st 1 (+ 1 (mod i 1000))) 0)
        (check 'step (step st) ROW)
        (read-row! st)
        (check 'finalize (finalize st) 0))
      (loop (+ i 1)))))

(define (select-reuse st step reset)
  (let loop ([i 0])
    (when (< i rounds)
      (check 'reset (reset st) 0)
      (check 'bind (bind-int64 st 1 (+ 1 (mod i 1000))) 0)
      (check 'step (step st) ROW)
      (read-row! st)
      (loop (+ i 1)))))

(define (ns-since t0)
  (let* ([t1 (current-time 'time-monotonic)]
         [d (time-difference t1 t0)])
    (+ (* (time-second d) 1000000000) (time-nanosecond d))))

(define (report label times)
  (let* ([sorted (list-sort < times)]
         [k (length sorted)])
    (printf "time: ~56a min ~7d  median ~7d  max ~7d  ns/round~n" label
            (round (/ (car sorted) rounds))
            (round (/ (list-ref sorted (quotient k 2)) rounds))
            (round (/ (list-ref sorted (- k 1)) rounds)))))

(define (open-memory)
  (let* ([cell (foreign-alloc 8)]
         [rc (open-v2 ":memory:" cell (logior READWRITE CREATE FULLMUTEX EXRESCODE) 0)]
         [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (check 'open rc 0)
    db))

(define db (open-memory))
(check 'setup
       (exec db (string-append
                 "CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT, n INTEGER);"
                 "INSERT INTO t(name, n) SELECT 'a typical name', value FROM "
                 "(WITH RECURSIVE c(value) AS (SELECT 1 UNION ALL SELECT value + 1 FROM c WHERE value < 1000) "
                 "SELECT value FROM c);")
             0 0 0)
       0)

;; measure : String Procedure Procedure Procedure Procedure Natural -> Void
(define (measure label prep step reset finalize flags)
  (let* ([ins (prepare prep db insert-sql flags)]
         [sel (prepare prep db select-sql flags)])
    ;; one warm-up run, untimed
    (insert-prepare db prep step finalize 0 flags)
    (insert-reuse ins step reset 0)
    (select-prepare db prep step finalize flags)
    (select-reuse sel step reset)
    (check 'reset (reset sel) 0)
    (let loop ([r 0] [ip '()] [ir '()] [sp '()] [sr '()])
      (if (< r runs)
          (let* ([t0 (current-time 'time-monotonic)]
                 [_ (insert-prepare db prep step finalize r flags)]
                 [a (ns-since t0)]
                 [t1 (current-time 'time-monotonic)]
                 [_ (insert-reuse ins step reset r)]
                 [b (ns-since t1)]
                 [t2 (current-time 'time-monotonic)]
                 [_ (select-prepare db prep step finalize flags)]
                 [c (ns-since t2)]
                 [t3 (current-time 'time-monotonic)]
                 [_ (select-reuse sel step reset)]
                 [d (ns-since t3)]
                 ;; untimed: no read stays open into the next run's inserts
                 [_ (check 'reset (reset sel) 0)])
            (loop (+ r 1) (cons a ip) (cons b ir) (cons c sp) (cons d sr)))
          (begin
            (check 'finalize (finalize ins) 0)
            (check 'finalize (finalize sel) 0)
            (report (string-append "insert, prepare each round" label) ip)
            (report (string-append "insert, reuse one statement" label) ir)
            (report (string-append "select, prepare each round" label) sp)
            (report (string-append "select, reuse one statement" label) sr))))))

(measure ", __collect_safe, flags 0" prepare-safe step-safe reset-safe finalize-safe 0)
(measure ", __collect_safe, PERSISTENT" prepare-safe step-safe reset-safe finalize-safe PERSISTENT)
(measure ", plain, flags 0" prepare-plain step-plain reset-plain finalize-plain 0)
(measure ", plain, PERSISTENT" prepare-plain step-plain reset-plain finalize-plain PERSISTENT)

(let* ([st (prepare prepare-plain db "SELECT count(*) FROM t" 0)]
       [rc (step-plain st)]
       [n (column-int64 st 0)])
  (check 'step rc ROW)
  (check 'finalize (finalize-plain st) 0)
  (printf "rows in t afterwards: ~a~n" n))
(printf "select checksum: ~a~n" checksum)
(check 'close (close db) 0)
