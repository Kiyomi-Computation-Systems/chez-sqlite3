;;; dyld.sps: whether the environment can redirect an absolute path, for
;;; M4's Mac run after slice 5 (research/m4-mac/slices-3-5.md). run-dyld.sh
;;; runs it, each case in a Chez of its own, since dyld reads
;;; DYLD_LIBRARY_PATH and DYLD_FALLBACK_LIBRARY_PATH only at launch.
;;;
;;;   dyld.sps library        the libsqlite3 chez-sqlite3 loaded, as SQLite
;;;                           reports itself: (library VERSION PATH), PATH
;;;                           the one chez-sqlite3 was given
;;;   dyld.sps load PATH      PATH loaded through load-extension! into a
;;;                           :memory: connection that opted in:
;;;                           (loaded HALF), HALF chez_half(3) as it answers
;;;
;;; Each answer follows the three variables as this Chez saw them, (seen
;;; DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH LD_LIBRARY_PATH), each #f
;;; when unset: macOS strips DYLD_* from a protected binary's environment,
;;; /usr/bin/env and /bin/sh among them, so a case whose variable never
;;; reached Chez says so.
;;;
;;; Anything raised is (raised KINDS MESSAGE): KINDS the condition's simple
;;; types by name, MESSAGE sqlite-error-message's for an &sqlite-error, or
;;; the &message's. chez-sqlite3 is reached only through eval inside the
;;; guard, so a library that fails to load is an answer too.
;;;
;;; The default variant of tests/extension.c registers chez_half; the
;;; failing variant's init refuses with "chez_failing refused". So a load
;;; tells which of two files of the same leaf name dyld opened.
(import (rnrs) (rnrs eval) (only (chezscheme) getenv))

(define env (environment '(rnrs) '(chez-sqlite3)))

;; kinds : Any -> (Listof Symbol)
;; The simple conditions' type names, or (not-a-condition).
(define (kinds e)
  (if (condition? e)
      (let loop ((rest (simple-conditions e)) (found '()))
        (if (null? rest)
            (reverse found)
            (loop (cdr rest) (cons (record-type-name (record-rtd (car rest))) found))))
      '(not-a-condition)))

;; message : Any -> Any
(define (message e)
  (cond ((memq '&sqlite-error (kinds e))
         (guard (x (#t 'unread)) ((eval 'sqlite-error-message env) e)))
        ((message-condition? e) (condition-message e))
        (else 'no-message)))

;; outcome : Any -> Any
;; FORM evaluated in ENV, or what it raised.
(define (outcome form)
  (guard (e (#t (list 'raised (kinds e) (message e))))
    (eval form env)))

(let ((args (cdr (command-line))))
  (write (list 'seen (getenv "DYLD_LIBRARY_PATH") (getenv "DYLD_FALLBACK_LIBRARY_PATH")
               (getenv "LD_LIBRARY_PATH")))
  (display " ")
  (write
   (cond ((equal? args '("library"))
          (outcome '(list 'library (sqlite-version) (sqlite-library-path))))
         ((and (= (length args) 2) (equal? (car args) "load"))
          (outcome
           `(call-with-database ":memory:" '((enable-load-extension . #t))
              (lambda (db)
                (load-extension! db ,(cadr args))
                (let ((row (query-row db "select chez_half(3)")))
                  (list 'loaded (and row (vector-ref row 0))))))))
         (else (list 'usage args))))
  (newline))
