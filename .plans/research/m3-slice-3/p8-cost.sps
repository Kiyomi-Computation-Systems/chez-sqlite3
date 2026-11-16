#!r6rs
;;; P8 (the M3 plan, section 8): what the conveniences cost through the
;;; library, and what a critical section a value costs against one a row.
;;;
;;; Part 1. Each convenience, and M2's statement tier by hand, runs one
;;; SELECT of one row by its key, "select v + J from t where k = ?1", on a
;;; :memory: table of 100 rows, in three regimes:
;;;   cached    capacity 32, the one SQL every call: every call a hit
;;;   uncached  capacity 32, 64 SQL texts in turn: every call a miss, prepared
;;;             SQLITE_PREPARE_PERSISTENT, and every return evicts the least
;;;             recently used statement, finalized
;;;   off       capacity 0, the one SQL every call: prepared with no flags,
;;;             and finalized at the return
;;; and the statement tier by hand: a fresh statement each call (prepare,
;;; bind-all!, step!, column-value, finalize), and one held statement
;;; (reset!, bind-all!, step!, column-value).
;;;
;;; Part 2. A statement held at its row of N small columns, N 1, 10 and 100,
;;; all integers or all one-character TEXT, read whole again and again:
;;;   a section a value  as the conveniences read a row: column-count/who,
;;;                      then column-value/who for each column, each in a
;;;                      critical section of its own (the plan's Q15)
;;;   a section a row    one call-with-statement-handle, the count read once
;;;                      and every column's type and value inside it, TEXT
;;;                      decoded after it: the row reader Q15 declined
;;; and query-row of the same SELECT, cached, for the whole convenience.
;;;
;;; Each figure is the median of 7 samples, each a loop of many calls, with a
;;; collection before each sample; the range is the samples' least and most.
;;; No set of foreign_keys or trusted_schema runs here (ADR-0020, decision 8).
;;; A research probe, never a suite row: it runs outside the memory gate.
(import (rnrs)
        (rnrs eval)
        (only (chezscheme) printf collect current-time time-difference time-second
              time-nanosecond critical-section scheme-version)
        (only (chez-sqlite3 private native) sqlite3-column-count sqlite3-column-type
              sqlite3-column-int64 sqlite3-column-double sqlite3-column-text
              sqlite3-column-blob sqlite3-column-bytes foreign-bytes)
        (only (chez-sqlite3 private connection) open-database-with-cache-capacity close-database!
              database-cache-count)
        (only (chez-sqlite3 private statement) prepare-statement finalize-statement! step!
              reset! call-with-statement-handle column-count/who)
        (only (chez-sqlite3 private statement-values) bind-all! column-value column-value/who)
        (only (chez-sqlite3 private values) sql-null)
        (only (chez-sqlite3 private utf8) strict-utf8->string)
        (chez-sqlite3 private conveniences)
        (only (chez-sqlite3 private counters) native-counts))

(define samples 7)

;; seconds-of : (-> Any) -> Real
;; THUNK's wall time, in seconds, by the monotonic clock, after a collection.
(define (seconds-of thunk)
  (collect)
  (let ((t0 (current-time 'time-monotonic)))
    (thunk)
    (let ((d (time-difference (current-time 'time-monotonic) t0)))
      (+ (time-second d) (/ (time-nanosecond d) 1e9)))))

;; median-of : (Listof Real) -> Real
(define (median-of xs)
  (let ((sorted (list-sort < xs)))
    (list-ref sorted (div (length sorted) 2))))

;; per-call : Natural (Natural -> Any) Real -> (List Real Real Real)
;; CALL run on 0 to N-1, SAMPLES times: the median, least and most of its
;; time a call, in units of SCALE seconds.
(define (per-call n call scale)
  (let loop ((k 0) (found '()))
    (if (= k samples)
        (list (median-of found) (apply min found) (apply max found))
        (let ((s (seconds-of (lambda ()
                               (let run ((i 0))
                                 (when (< i n) (call i) (run (+ i 1))))))))
          (loop (+ k 1) (cons (/ (/ s n) scale) found))))))

(define (show x) (/ (round (* x 100)) 100.0))

;; report : String Natural (Natural -> Any) -> (List Real Real Real)
(define (report label n call)
  (let ((r (per-call n call 1e-6)))
    (printf "  ~a~a ~8,2f us  [~,2f to ~,2f]\n" label
            (make-string (max 0 (- 34 (string-length label))) #\space)
            (show (car r)) (show (cadr r)) (show (caddr r)))
    r))

;; run! : Database String -> Void
;; SQL run through the statement tier, stepped to its end, finalized.
(define (run! db sql)
  (let ((st (prepare-statement db sql)))
    (let loop () (when (step! st) (loop)))
    (finalize-statement! st)))

;; table-db : Natural -> Database
;; A :memory: database of cache CAPACITY holding t, k from 1 to 100, v = k.
(define (table-db capacity)
  (let ((db (open-database-with-cache-capacity capacity ":memory:")))
    (run! db "create table t (k integer primary key, v)")
    (run! db "with recursive n(i) as (select 1 union all select i + 1 from n where i < 100) insert into t select i, i from n")
    db))

(define (sql-of j) (string-append "select v + " (number->string j) " from t where k = ?1"))
(define the-sql (sql-of 0))
(define miss-sqls (let loop ((j 63) (found '())) (if (< j 0) (list->vector found) (loop (- j 1) (cons (sql-of j) found)))))
(define (key-of i) (+ 1 (mod i 100)))
(define (sum acc row) (+ acc (vector-ref row 0)))

(printf "P8: the conveniences' cost through the library\n")
(printf "SQLite ~a; ~a\n" (eval '(sqlite-version) (environment '(chez-sqlite3))) (scheme-version))

;; --- part 1 -----------------------------------------------------------------------------

(define n1 5000)

(let* ((cached (table-db 32))
       (missing (table-db 32))
       (off (table-db 0))
       (held (prepare-statement cached the-sql)))
  (printf "\nPart 1. One SELECT of one row by its key, ~a calls a sample, us a call\n" n1)
  (printf "the statement tier by hand:\n")
  (report "a fresh statement each call" n1
          (lambda (i)
            (let ((st (prepare-statement off the-sql)))
              (bind-all! st (key-of i))
              (step! st)
              (column-value st 0)
              (finalize-statement! st))))
  (report "one held statement" n1
          (lambda (i)
            (reset! held)
            (bind-all! held (key-of i))
            (step! held)
            (column-value held 0)))
  (for-each
   (lambda (entry)
     (let ((name (car entry)) (call (cdr entry)))
       (printf "~a:\n" name)
       (report "cached, capacity 32" n1 (lambda (i) (call cached the-sql (key-of i))))
       (report "uncached, capacity 32, 64 SQL" n1
               (lambda (i) (call missing (vector-ref miss-sqls (mod i 64)) (key-of i))))
       (report "off, capacity 0" n1 (lambda (i) (call off the-sql (key-of i))))))
   (list (cons "execute!" (lambda (db sql k) (execute! db sql k)))
         (cons "query-row" (lambda (db sql k) (query-row db sql k)))
         (cons "query" (lambda (db sql k) (query db sql k)))
         (cons "query-fold" (lambda (db sql k) (query-fold db sql sum 0 k)))))
  (printf "check: each answers v + 0 for k = 7: ~s ~s ~s ~s\n"
          (query-row cached the-sql 7) (query off the-sql 7) (query-fold missing (sql-of 0) sum 0 7)
          (begin (reset! held) (bind-all! held 7) (step! held) (column-value held 0)))
  (printf "check: the caches hold ~a, ~a and ~a statements, cached, uncached and off\n"
          (database-cache-count cached) (database-cache-count missing) (database-cache-count off))
  (finalize-statement! held)
  (close-database! cached)
  (close-database! missing)
  (close-database! off))

;; --- part 2 -----------------------------------------------------------------------------

;; row-per-value : Statement -> (Vectorof Value)
;; ST's row as the conveniences read it: the count, then each column, each in
;; a critical section of its own.
(define (row-per-value st)
  (let* ((n (column-count/who 'p8 st))
         (row (make-vector n)))
    (let loop ((i 0))
      (when (< i n)
        (vector-set! row i (column-value/who 'p8 st i))
        (loop (+ i 1))))
    row))

;; row-per-section : Statement -> (Vectorof Value)
;; ST's row in one critical section: the count read once, then each column's
;; type and value, by sqlite3_column_type as column-value reads it; TEXT's
;; bytes copied there, and decoded strictly after the section.
(define (row-per-section st)
  (let ((row (call-with-statement-handle 'p8 st 'column-value
               (lambda (connection handle sql)
                 (let* ((n (sqlite3-column-count handle))
                        (row (make-vector n)))
                   (let loop ((i 0))
                     (when (< i n)
                       (vector-set! row i
                         (let ((type (sqlite3-column-type handle i)))
                           (cond ((eqv? type 1) (sqlite3-column-int64 handle i))
                                 ((eqv? type 2) (sqlite3-column-double handle i))
                                 ((eqv? type 5) sql-null)
                                 ((eqv? type 3)
                                  (let ((p (sqlite3-column-text handle i)))
                                    (cons 'text (foreign-bytes p (sqlite3-column-bytes handle i)))))
                                 (else
                                  (let ((p (sqlite3-column-blob handle i)))
                                    (foreign-bytes p (sqlite3-column-bytes handle i)))))))
                       (loop (+ i 1))))
                   (values #f row))))))
    (let loop ((i 0))
      (when (< i (vector-length row))
        (let ((v (vector-ref row i)))
          (when (and (pair? v) (eq? (car v) 'text))
            (vector-set! row i (strict-utf8->string (cdr v)))))
        (loop (+ i 1))))
    row))

;; select-of : Natural String -> String
;; select of N columns, each the literal VALUE.
(define (select-of n value)
  (let loop ((i 1) (text (string-append "select " value)))
    (if (= i n) text (loop (+ i 1) (string-append text ", " value)))))

(define n2-values 100000)

(printf "\nPart 2. A row of N small columns, read whole again and again, ns a value\n")
(let ((db (open-database-with-cache-capacity 32 ":memory:")))
  (for-each
   (lambda (shape)
     (let* ((n (car shape))
            (value (cdr shape))
            (sql (select-of n value))
            (st (prepare-statement db sql))
            (rows (div n2-values n))
            (row (begin (step! st) #t))
            (same (equal? (row-per-value st) (row-per-section st))))
       (printf "~a columns of ~a (~a rows a sample), the readers agree: ~a\n" n value rows same)
       (let* ((a (per-call rows (lambda (i) (row-per-value st)) 1e-9))
              (b (per-call rows (lambda (i) (row-per-section st)) 1e-9))
              (c (per-call rows (lambda (i) (query-row db sql)) 1e-9)))
         (for-each
          (lambda (label r)
            (printf "  ~a~a ~9,1f ns a value  [~,1f to ~,1f]\n" label
                    (make-string (max 0 (- 34 (string-length label))) #\space)
                    (/ (car r) n) (/ (cadr r) n) (/ (caddr r) n)))
          (list "a section a value" "a section a row" "query-row, cached, whole")
          (list a b c))
         (printf "  a section a value costs ~,1f ns a value more\n" (/ (- (car a) (car b)) n)))
       (finalize-statement! st)))
   (list (cons 1 "1") (cons 10 "1") (cons 100 "1")
         (cons 1 "'a'") (cons 10 "'a'") (cons 100 "'a'")))
  (close-database! db))

;; --- a section alone ------------------------------------------------------------------

(printf "\nA critical section alone, ns a section:\n")
(let* ((n 1000000)
       (empty (per-call n (lambda (i) i) 1e-9))
       (section (per-call n (lambda (i) (critical-section i)) 1e-9)))
  (printf "  the loop alone ~,1f ns; with an empty critical-section ~,1f ns\n"
          (car empty) (car section)))

(printf "\ncounts at the end: ~s\n" (native-counts))
