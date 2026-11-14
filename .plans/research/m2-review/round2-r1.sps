;;; Reviewer's probe (round 2). Effects ordered by let*; no map.
(import (chezscheme))
(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))
(define open-v2 (foreign-procedure "sqlite3_open_v2" (string uptr int uptr) int))
(define close (foreign-procedure "sqlite3_close" (uptr) int))
(define prepare-v3 (foreign-procedure __collect_safe "sqlite3_prepare_v3" (uptr uptr int unsigned-int uptr uptr) int))
(define step (foreign-procedure __collect_safe "sqlite3_step" (uptr) int))
(define reset (foreign-procedure "sqlite3_reset" (uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define column-text-ptr (foreign-procedure "sqlite3_column_text" (uptr int) uptr))
(define column-bytes (foreign-procedure "sqlite3_column_bytes" (uptr int) int))
(define errcode (foreign-procedure "sqlite3_errcode" (uptr) int))
(define libversion (foreign-procedure "sqlite3_libversion" () string))
(define EXRESCODE #x02000000)
(define (open name)
  (let* ([cell (foreign-alloc 8)]
         [rc (open-v2 name cell (logior #x2 #x4 EXRESCODE) 0)]
         [db (foreign-ref 'uptr cell 0)])
    (foreign-free cell)
    (unless (= rc 0) (error 'probe "open failed" rc))
    db))
(define (prep db text)
  (let* ([bv (string->utf8 text)]
         [n (bytevector-length bv)]
         [sql (foreign-alloc (+ n 1))]
         [fill (let loop ([i 0]) (when (< i n) (foreign-set! 'unsigned-8 sql i (bytevector-u8-ref bv i)) (loop (+ i 1))))]
         [nul (foreign-set! 'unsigned-8 sql n 0)]
         [cell (foreign-alloc 8)]
         [tail (foreign-alloc 8)]
         [z (foreign-set! 'uptr cell 0 0)]
         [rc (prepare-v3 db sql n 0 cell tail)]
         [stmt (foreign-ref 'uptr cell 0)]
         [rest (- (foreign-ref 'uptr tail 0) sql)])
    (foreign-free cell) (foreign-free tail) (foreign-free sql)
    (list rc stmt rest)))
(define (exec db text)
  (let* ([p (prep db text)]
         [s (if (= (cadr p) 0) 'none (step (cadr p)))]
         [f (if (= (cadr p) 0) 'none (finalize (cadr p)))])
    (list (car p) s f)))
(define (one db sql)
  (let* ([p (prep db sql)] [st (cadr p)] [s (step st)]
         [ptr (column-text-ptr st 0)] [n (column-bytes st 0)]
         [bv (make-bytevector n)]
         [fill (let loop ([k 0]) (when (< k n) (bytevector-u8-set! bv k (foreign-ref 'unsigned-8 ptr k)) (loop (+ k 1))))]
         [f (finalize st)])
    (utf8->string bv)))
(define (show label value) (printf "~a: ~s~n" label value))
(define (ms) (let ([t (current-time 'time-monotonic)]) (+ (* 1000 (time-second t)) (quotient (time-nanosecond t) 1000000))))
(show "libversion" (libversion))

;; R1. A fresh connection's prepare under another's BEGIN EXCLUSIVE, busy_timeout set by pragma first.
(let* ([path "build/rev2/tmp-excl.db"]
       [rm (when (file-exists? path) (delete-file path))]
       [a (open path)]
       [e1 (exec a "create table t (x)")]
       [e2 (exec a "insert into t values (1)")]
       [b (open path)]
       [bt (exec b "pragma busy_timeout = 1500")]
       [ex (exec a "begin exclusive")]
       [t0 (ms)]
       [p (prep b "select x from t")]
       [t1 (ms)]
       [pf (if (= (cadr p) 0) 'none (finalize (cadr p)))]
       [cm (exec a "commit")]
       [c1 (close a)]
       [c2 (close b)])
  (show "R1. b's busy_timeout pragma, a's begin exclusive, b's prepare rc and ms" (list bt ex (car p) (- t1 t0))))

;; R1b. The same, but b read the schema before a's lock (not fresh).
(let* ([path "build/rev2/tmp-excl2.db"]
       [rm (when (file-exists? path) (delete-file path))]
       [a (open path)]
       [e1 (exec a "create table t (x)")]
       [b (open path)]
       [bt (exec b "pragma busy_timeout = 1500")]
       [warm (exec b "select count(*) from t")]
       [ex (exec a "begin exclusive")]
       [t0 (ms)]
       [p (prep b "select x from t")]
       [t1 (ms)]
       [pf (if (= (cadr p) 0) 'none (finalize (cadr p)))]
       [cm (exec a "commit")]
       [c1 (close a)]
       [c2 (close b)])
  (show "R1b. b warmed, then a's begin exclusive, b's prepare rc and ms" (list (car p) (- t1 t0))))

;; R2. After a reset that answered a failure of its own (RETURNING under a reader), what finalize answers.
(let* ([path "build/rev2/tmp-busy.db"]
       [rm (when (file-exists? path) (delete-file path))]
       [db1 (open path)]
       [db2 (open path)]
       [e1 (exec db1 "create table t (x)")]
       [e2 (exec db1 "insert into t values (0)")]
       [r (prep db2 "select x from t")]
       [rs (cadr r)]
       [r-step (step rs)]
       [p (prep db1 "insert into t values (1) returning x")]
       [st (cadr p)]
       [s (step st)]
       [rr (reset st)]
       [ec (errcode db1)]
       [rr2 (reset st)]
       [ff (finalize st)]
       [rf (finalize rs)]
       [c1 (close db1)]
       [c2 (close db2)])
  (show "R2. step, reset, errcode, second reset, finalize after it" (list s rr ec rr2 ff)))

;; R3. Tails SQLite's tokenizer reads near the scanner's edges.
(let* ([db (open ":memory:")]
       [cases (list "/*" "/* " "/*x" "select 1;/*" "--" "-" (string #\vtab) (string #\page) (string #\x85) (string #\xA0) "select 1;\x0b;")]
       [results (let loop ([cs cases] [acc '()])
                  (if (null? cs) (reverse acc)
                      (let* ([p (prep db (car cs))]
                             [f (if (= (cadr p) 0) 'none (finalize (cadr p)))])
                        (loop (cdr cs) (cons (list (car cs) 'rc (car p) 'null? (= (cadr p) 0) 'tail (caddr p)) acc)))))]
       [c (close db)])
  (for-each (lambda (r) (show "R3. prepare" r)) results))

;; R4. The first statement's prepare side effect when a second statement follows.
(let* ([db (open ":memory:")]
       [before (one db "pragma cache_size")]
       [p (prep db "pragma cache_size = 7; select 1")]
       [f (if (= (cadr p) 0) 'none (finalize (cadr p)))]
       [after (one db "pragma cache_size")]
       [c (close db)])
  (show "R4. cache_size before, prepare rc and tail of 'pragma cache_size = 7; select 1', cache_size after" (list before (car p) (caddr p) after)))
