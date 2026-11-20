#!r6rs
;;; Gap 3: a settings list that sets journal-mode, to each value the list
;;; takes, on ":memory:" (and the memory option, and a "" temporary file as
;;; a control that opens). For each, what the open raised: the mismatch's
;;; setting, expected and actual; or 'opened, with the connection closed.
;;; Each open runs under its own guard, through eval, with its own sentinel.
(import (rnrs) (rnrs eval) (chez-sqlite3-testing) (chez-sqlite3 private counters))

(define env (environment '(rnrs) '(chez-sqlite3)))

(define (reach name) (eval name env))
(define mismatch? (reach 'sqlite-setting-mismatch?))
(define mismatch-setting (reach 'sqlite-setting-mismatch-setting))
(define mismatch-expected (reach 'sqlite-setting-mismatch-expected))
(define mismatch-actual (reach 'sqlite-setting-mismatch-actual))
(define sql-error? (reach 'sqlite-error?))
(define sql-error-code (reach 'sqlite-error-code))

(define (try form)
  (guard (e ((mismatch? e) (list 'mismatch (mismatch-setting e) (mismatch-expected e) (mismatch-actual e)))
            ((sql-error? e) (list 'sqlite-error (sql-error-code e)))
            (#t (list 'other (describe e))))
    (eval form env)))

(define (case-of name extra value)
  (try `(let ((db (apply open-database ,name (append ',extra (list '((journal-mode . ,value)))))))
          (let ((mode (vector-ref (query-row db "pragma journal_mode") 0)))
            (close-database! db)
            (list 'opened mode)))))

(define library (guard (e (#t 'unloaded)) (eval '(sqlite-version) env)))
(display "library: ") (write library) (newline)

(for-each
 (lambda (target)
   (for-each
    (lambda (value)
      (let ((r (case-of (car target) (cdr target) value)))
        (display (car target)) (display " ") (write (cdr target)) (display " journal-mode ")
        (write value) (display " => ") (write r) (newline)))
    '(delete truncate persist wal)))
 '((":memory:") ("x" memory) ("")))

(display "counts at the end: ") (write (native-counts)) (newline)
