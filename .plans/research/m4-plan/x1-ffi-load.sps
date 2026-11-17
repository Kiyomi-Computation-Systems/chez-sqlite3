;;; x1-ffi-load.sps: sqlite3_load_extension through Chez's FFI, as v1's verb
;;; would call it (the M4 plan, sections 4.4 and 8).
;;;
;;; Usage: scheme --program x1-ffi-load.sps LIBRARY DIR MODE
;;;
;;; Standalone: it loads LIBRARY by that path with load-shared-object and
;;; binds what it needs with foreign-procedure, and loads none of
;;; chez-sqlite3's libraries. DIR holds ext.so and ext-failing.so, built by
;;; run-x1.sh against LIBRARY's header. No binding takes a Scheme object:
;;; strings go in foreign blocks, and come back as addresses (ADR-0011).
;;; Every connection is :memory:, opened as chez-sqlite3 opens one. It prints
;;; one datum per line and flushes it. Paths are printed with DIR as "DIR".
;;;
;;; MODE:
;;;   gate        under Valgrind, the gate's flags: db_config's
;;;               ENABLE_LOAD_EXTENSION set by (__varargs_after 2); ext.so
;;;               loaded with no entry point named, its chez_half called;
;;;               ext-failing.so's failed load, its message read and freed by
;;;               sqlite3_free; a missing file's, the same; then the close,
;;;               which unloads both. sqlite3_memory_used is printed before
;;;               the open and after the close.
;;;   gate-leak   the same, but the failed loads' messages never freed: the
;;;               plant the gate must see
;;;   gate-none   the same open, db_config call and close, and no load: the
;;;               control for what a load leaves still reachable, in the same
;;;               program
;;;   fifo-plain  the load bound plain, of DIR/fifo.so, a FIFO run-x1.sh
;;;               made; a second thread asks for a collection 300 ms after
;;;               the load began. run-x1.sh writes to the FIFO from outside
;;;               the process 1500 ms after it starts, which ends the load: a
;;;               thread of this process could not, since it would wait for
;;;               the collection too. Prints when the load returned, when
;;;               the collection was asked for and when it was done, and
;;;               whether it waited for the load
;;;   fifo-safe   the same, the load bound __collect_safe
;;;
;;; Every wait is bounded: the main thread waits at most 20 s for the
;;; others. The steps run in the order written: every sequence of effects is
;;; a let* or a body, never a call's arguments (AGENTS.md).
(import (chezscheme))

(define (emit . items)
  (let ((port (current-output-port)))
    (write items port)
    (newline port)
    (flush-output-port port)))

(define arguments (command-line-arguments))
(unless (= (length arguments) 3)
  (display "usage: scheme --program x1-ffi-load.sps LIBRARY DIR MODE\n" (current-error-port))
  (exit 2))
(define library-path (car arguments))
(define dir (cadr arguments))
(define mode (string->symbol (caddr arguments)))
(unless (memq mode '(gate gate-leak gate-none fifo-plain fifo-safe))
  (display "x1-ffi-load.sps: MODE is gate, gate-leak, gate-none, fifo-plain or fifo-safe\n"
           (current-error-port))
  (exit 2))

(define constants
  '((SQLITE_OK . 0) (SQLITE_ROW . 100) (SQLITE_OPEN_READWRITE . 2) (SQLITE_OPEN_CREATE . 4)
    (SQLITE_OPEN_FULLMUTEX . #x10000) (SQLITE_OPEN_EXRESCODE . #x2000000)
    (SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION . 1005)))
(define (k name) (cdr (assq name constants)))
(for-each (lambda (entry) (emit 'constant (car entry) (cdr entry))) constants)
(emit 'mode mode)

(load-shared-object library-path)

(define open-v2 (foreign-procedure __collect_safe "sqlite3_open_v2" (uptr uptr int uptr) int))
(define close-db (foreign-procedure __collect_safe "sqlite3_close" (uptr) int))
(define prepare-v2 (foreign-procedure "sqlite3_prepare_v2" (uptr uptr int uptr uptr) int))
(define step (foreign-procedure "sqlite3_step" (uptr) int))
(define column-double (foreign-procedure "sqlite3_column_double" (uptr int) double))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define memory-used (foreign-procedure "sqlite3_memory_used" () integer-64))
(define sqlite3-free (foreign-procedure "sqlite3_free" (uptr) void))
(define db-config
  (foreign-procedure (__varargs_after 2) "sqlite3_db_config" (uptr int int uptr) int))
(define load-safe
  (foreign-procedure __collect_safe "sqlite3_load_extension" (uptr uptr uptr uptr) int))
(define load-plain
  (foreign-procedure "sqlite3_load_extension" (uptr uptr uptr uptr) int))
(define libversion (foreign-procedure "sqlite3_libversion" () uptr))

;; --- foreign memory ------------------------------------------------------------

(define (with-block n proc)
  (let ((block (foreign-alloc n)))
    (dynamic-wind
      (lambda () #f)
      (lambda () (proc block))
      (lambda () (foreign-free block)))))

(define (with-c-string s proc)
  (let* ((bytes (string->utf8 s))
         (n (bytevector-length bytes)))
    (with-block (+ n 1)
      (lambda (block)
        (do ((i 0 (+ i 1))) ((= i n))
          (foreign-set! 'unsigned-8 block i (bytevector-u8-ref bytes i)))
        (foreign-set! 'unsigned-8 block n 0)
        (proc block)))))

;; c-text : Integer -> (U String 'null)
(define (c-text address)
  (if (= address 0)
      'null
      (let count ((n 0))
        (if (= (foreign-ref 'unsigned-8 address n) 0)
            (let ((bv (make-bytevector n)))
              (do ((i 0 (+ i 1))) ((= i n))
                (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 address i)))
              (utf8->string bv))
            (count (+ n 1))))))

;; shown : String -> String
;; TEXT with DIR written "DIR".
(define (shown text)
  (let ((d (string-length dir)))
    (let loop ((i 0) (parts '()))
      (cond ((> (+ i d) (string-length text))
             (apply string-append (reverse (cons (substring text i (string-length text)) parts))))
            ((string=? (substring text i (+ i d)) dir)
             (loop (+ i d) (cons "DIR" parts)))
            (else (loop (+ i 1) (cons (string (string-ref text i)) parts)))))))

(emit 'libversion (c-text (libversion)))

;; --- connections ---------------------------------------------------------------

(define (open-memory)
  (with-c-string ":memory:"
    (lambda (name)
      (with-block 8
        (lambda (cell)
          (foreign-set! 'uptr cell 0 0)
          (let* ((rc (open-v2 name cell (logior (k 'SQLITE_OPEN_READWRITE) (k 'SQLITE_OPEN_CREATE)
                                               (k 'SQLITE_OPEN_FULLMUTEX)
                                               (k 'SQLITE_OPEN_EXRESCODE))
                              0))
                 (db (foreign-ref 'uptr cell 0)))
            (unless (= rc 0) (emit 'open-failed rc) (exit 1))
            db))))))

(define (c-call-on db)
  (with-block 8
    (lambda (cell)
      (foreign-set! 'int cell 0 -77)
      (let* ((rc (db-config db (k 'SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION) 1 cell))
             (out (foreign-ref 'int cell 0)))
        (emit 'enable-load-extension 'rc rc 'cell out)))))

;; load-ext : Procedure Integer String (U String #f) Boolean -> Integer
;; BINDING's call of PATH and ENTRY on DB, as v1's verb would make it: the
;; path and entry point as C strings, the message slot a block set to 0.
;; Prints the code and the message, which FREE? frees with sqlite3_free.
(define (load-ext binding db path entry free?)
  (with-c-string path
    (lambda (p)
      (let ((go (lambda (e)
                  (with-block 8
                    (lambda (slot)
                      (foreign-set! 'uptr slot 0 0)
                      (let* ((rc (binding db p e slot))
                             (msg (foreign-ref 'uptr slot 0))
                             (text (c-text msg)))
                        (when (and free? (not (= msg 0))) (sqlite3-free msg))
                        (emit 'load (shown path) (or entry 'null) 'rc rc
                              'message (if (string? text) (shown text) text)
                              'freed (and free? (not (= msg 0))))
                        rc))))))
        (if entry (with-c-string entry go) (go 0))))))

(define (half db)
  (with-c-string "select chez_half(5)"
    (lambda (sql)
      (with-block 8
        (lambda (cell)
          (foreign-set! 'uptr cell 0 0)
          (let ((rc (prepare-v2 db sql -1 cell 0)))
            (if (not (= rc 0))
                (emit 'half 'prepare rc)
                (let* ((st (foreign-ref 'uptr cell 0))
                       (s (step st))
                       (v (if (= s (k 'SQLITE_ROW)) (column-double st 0) 'no-row))
                       (f (finalize st)))
                  (emit 'half 'step s 'value v 'finalize f)))))))))

;; --- the gate ------------------------------------------------------------------

(define (gate free? load?)
  (emit 'memory-used-before (memory-used))
  (let ((db (open-memory)))
    (c-call-on db)
    (when load?
      (load-ext load-safe db (string-append dir "/ext.so") #f free?)
      (half db)
      (load-ext load-safe db (string-append dir "/ext-failing.so") #f free?)
      (load-ext load-safe db (string-append dir "/nosuch.so") #f free?))
    (let ((closed (close-db db)))
      (emit 'close closed)))
  (emit 'memory-used-after (memory-used)))

;; --- the FIFO ------------------------------------------------------------------

(define (fifo binding label)
  (let* ((path (string-append dir "/fifo.so"))
         (db (open-memory))
         (m (make-mutex))
         (c (make-condition))
         (load-ms #f)
         (collect-from #f)
         (collect-to #f)
         (t0 (current-time 'time-monotonic))
         (ms (lambda ()
               (let ((d (time-difference (current-time 'time-monotonic) t0)))
                 (+ (* 1000.0 (time-second d)) (/ (time-nanosecond d) 1e6))))))
    (c-call-on db)
    (fork-thread
     (lambda ()
       (sleep (make-time 'time-duration 300000000 0))
       (let ((start (ms)))
         (collect-rendezvous)
         (let ((end (ms)))
           (with-mutex m
             (set! collect-from start)
             (set! collect-to end)
             (condition-broadcast c))))))
    (load-ext binding db path #f #t)
    (let ((end (ms)))
      (with-mutex m
        (set! load-ms end)
        (condition-broadcast c)))
    (let ((deadline (add-duration (current-time 'time-utc) (make-time 'time-duration 0 20))))
      (with-mutex m
        (let wait ()
          (unless (and load-ms collect-to)
            (when (condition-wait c m deadline)
              (wait))))))
    ;; Times in ms from the load's start. The collection waited for the load
    ;; when it took most of the time from its request to the load's return,
    ;; which the FIFO's writer sets at about 1500 ms.
    (emit label 'load-returned-at (and load-ms (exact (round load-ms)))
          'collection-asked-at (and collect-from (exact (round collect-from)))
          'collection-done-at (and collect-to (exact (round collect-to)))
          'collection-waited-for-the-load
          (and load-ms collect-from collect-to
               (> (- collect-to collect-from) (* 0.8 (- load-ms collect-from)))))
    (close-db db)))

(case mode
  ((gate) (gate #t #t))
  ((gate-leak) (gate #f #t))
  ((gate-none) (gate #t #f))
  ((fifo-plain) (fifo load-plain 'plain))
  ((fifo-safe) (fifo load-safe 'collect-safe)))
