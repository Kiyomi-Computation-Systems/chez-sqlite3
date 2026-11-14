;;; Opens and closes SQLite databases through bare FFI, for the memory
;;; gate's first measurement (M0 slice 3). Every return code is printed and
;;; checked; the program exits 1 on any it does not expect. Given an
;;; argument, it opens one :memory: database and never closes it, keeping
;;; the handle in one of three shapes until exit:
;;;   forget  an integer, dropped
;;;   hold    an integer, held in a top-level variable
;;;   wrap    an ftype pointer, dropped
(import (chezscheme))

(load-shared-object (getenv "CHEZ_SQLITE3_LIBRARY"))

(define open-v2 (foreign-procedure "sqlite3_open_v2" (utf-8 uptr int uptr) int))
(define close-v2 (foreign-procedure "sqlite3_close_v2" (uptr) int))
(define prepare-v2 (foreign-procedure "sqlite3_prepare_v2" (uptr utf-8 int uptr uptr) int))
(define step (foreign-procedure "sqlite3_step" (uptr) int))
(define finalize (foreign-procedure "sqlite3_finalize" (uptr) int))
(define libversion (foreign-procedure "sqlite3_libversion" () string))

(define ok 0) (define row 100) (define done 101) (define cantopen 14)
(define readwrite #x2) (define create #x4)

(define failures 0)
(define (expect what want got)
  (printf "~a ~a~%" what got)
  (unless (eqv? want got)
    (printf "  expected ~a~%" want)
    (set! failures (+ failures 1))))

;; Opens path; returns the handle, or 0. The out-parameter block is freed
;; before returning, on every path.
(define (open path flags want)
  (let ((out (foreign-alloc (foreign-sizeof 'uptr))))
    (foreign-set! 'uptr out 0 0)
    (let* ((rc (open-v2 path out flags 0))
           (db (foreign-ref 'uptr out 0)))
      (foreign-free out)
      (expect (format "open ~a" path) want rc)
      db)))

(define (run db sql want)
  (let ((out (foreign-alloc (foreign-sizeof 'uptr))))
    (foreign-set! 'uptr out 0 0)
    (let* ((rc (prepare-v2 db sql -1 out 0))
           (st (foreign-ref 'uptr out 0)))
      (foreign-free out)
      (expect (format "prepare ~s" sql) ok rc)
      (let* ((s (step st))
             (f (finalize st)))
        (expect (format "step ~s" sql) want s)
        (expect (format "finalize ~s" sql) ok f)))))

(printf "libsqlite3 ~a~%" (libversion))

(define-ftype handle (struct (unused uptr)))
(define held #f)

(cond
  ((member (command-line-arguments) '(("forget") ("hold") ("wrap")))
   (let ((shape (car (command-line-arguments)))
         (db (open ":memory:" (logor readwrite create) ok)))
     (run db "create table t(x)" done)
     (cond
       ((equal? shape "hold") (set! held db))
       ((equal? shape "wrap") (make-ftype-pointer handle db)))
     (collect (collect-maximum-generation))
     (printf "~a: nothing closes the handle~%" shape)))
  (else
   (let ((file "build/memory-research/probe.db"))
     (mkdir "build/memory-research")
     (let ((db (open file (logor readwrite create) ok)))
       (run db "pragma journal_mode=wal" row)
       (run db "create table t(x)" done)
       (run db "insert into t values (1), (2), (3)" done)
       (run db "select count(*) from t" row)
       (expect "close file db" ok (close-v2 db)))
     (let ((db (open ":memory:" (logor readwrite create) ok)))
       (run db "create table t(x)" done)
       (expect "close :memory:" ok (close-v2 db)))
     ;; A failed open still returns a handle, which must be closed.
     (let ((db (open "build/memory-research/no/such/dir.db" readwrite cantopen)))
       (expect "failed open gave a handle" #t (not (eqv? db 0)))
       (expect "close failed open" ok (close-v2 db))))))

(printf "failures ~a~%" failures)
(when held (printf "held ~a~%" (not (eqv? held 0))))
(exit (if (= failures 0) 0 1))
