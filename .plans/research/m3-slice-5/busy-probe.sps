;;; busy-probe: the settings list under another connection's exclusive lock,
;;; and the file descriptors a failed open leaves (M3 slice 5, part A).
;;;
;;; Run from the repository's root. Its database is made in
;;; build/research-m3-slice-5-busy/, which it makes, and which it removes,
;;; with what it holds, at its end, by delete-file and delete-directory.
;;;
;;; A holder opens the file, makes t, and takes BEGIN EXCLUSIVE with a write.
;;; Then each open below, by open-database or call-with-database, is timed,
;;; and printed with what it raised, the counts after it, and how many more
;;; file descriptors the process has open than before the holder opened.
;;; Last, the descriptors once the holder has rolled back, and once it has
;;; closed.
(import (rnrs)
        (only (chezscheme) real-time directory-list delete-directory mkdir file-directory?)
        (chez-sqlite3)
        (chez-sqlite3 private counters))

(define (show . xs)
  (for-each (lambda (x) (write x) (display " ")) xs)
  (newline))

;; try : (-> Any) -> Any
;; THUNK's answer, a database it answered closed, as opened; or what it
;; raised: an &sqlite-error by its who, codes, SQL, offset and whether
;; sqlite-busy? holds it.
(define (try thunk)
  (guard (e ((sqlite-error? e)
             (list 'sqlite-error (condition-who e) (sqlite-error-code e) (sqlite-error-extended-code e)
                   (sqlite-error-sql e) (sqlite-error-offset e) (sqlite-busy? e)))
            (#t (list 'other (if (message-condition? e) (condition-message e) e))))
    (let ((r (thunk)))
      (if (database? r)
          (begin (close-database! r) 'opened)
          r))))

(define (descriptors) (length (directory-list "/dev/fd")))

(define dir "build/research-m3-slice-5-busy")
(define path (string-append dir "/busy.db"))

(unless (file-directory? dir) (mkdir dir))
(show 'version (sqlite-version))

(define before (descriptors))
(define holder (open-database path))
(execute! holder "create table if not exists t (x)")
(execute! holder "begin exclusive")
(execute! holder "insert into t values (1)")
(show 'the-holder-holds (native-counts) 'descriptors+ (- (descriptors) before))

(for-each
 (lambda (settings)
   (let* ((t0 (real-time))
          (r (try (lambda () (open-database path settings))))
          (t1 (real-time)))
     (show 'open-database settings r (- t1 t0) 'ms (native-counts) 'descriptors+ (- (descriptors) before))))
 '(((synchronous . full) (busy-timeout . 1500))
   ((synchronous . full))
   ((busy-timeout . 200) (journal-mode . wal))
   ((foreign-keys . #t) (busy-timeout . 1500))))

(let* ((called 'proc-not-called)
       (t0 (real-time))
       (r (try (lambda () (call-with-database path '((synchronous . full))
                            (lambda (db) (set! called 'proc-called))))))
       (t1 (real-time)))
  (show 'call-with-database '((synchronous . full)) r called (- t1 t0) 'ms (native-counts)
        'descriptors+ (- (descriptors) before)))

(execute! holder "rollback")
(show 'after-the-holder-rolls-back 'descriptors+ (- (descriptors) before))
(close-database! holder)
(show 'after-the-holder-closes (native-counts) 'descriptors+ (- (descriptors) before))

(for-each (lambda (f) (delete-file (string-append dir "/" f))) (directory-list dir))
(delete-directory dir)
(show 'removed (not (file-exists? dir)))
