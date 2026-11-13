#!r6rs
;;; make check-floors: reads the floors file and the README (make passes
;;; packaging/floors.sexp and README.org) and fails, naming each problem,
;;; unless README.org's Requirements section states the floors in
;;; packaging/floors.sexp (the lines (floors)'s requirement-lines writes from
;;; the file, whole, as one list). The rules are in (floors); this program
;;; reads the files, prints, and exits. tests/test-check-floors.sps holds each
;;; rule on texts and runs this program on fixture directories.
;;;
;;; It fails closed, because a check that passes on nothing is vacuous. It
;;; names, and exits 1 on, a file it cannot read, a floors file with a
;;; problem, and a README with no "** Requirements" section or the wrong list
;;; in it. A file it cannot read does not stop it comparing the other.
;;;
;;; It prints one line on a pass, to stdout, naming the files it read and the
;;; floors it found, or each problem and then a count of them on a failure, to
;;; stderr. It exits 0 or 1, never a count.
(import (rnrs)
        (floors)
        (only (chezscheme) display-condition))

;; describe : Any -> String
(define (describe obj)
  (call-with-string-output-port
    (lambda (p) (if (condition? obj) (display-condition obj p) (write obj p)))))

;; say : Port String -> Unit
(define (say port text)
  (put-string port (string-append "check-floors: " text "\n")))

;; read-text : String -> (U (List 'text String) (List 'unreadable String))
;; The text of the file at PATH, or the problem with reading it.
(define (read-text path)
  (guard (e (#t (list 'unreadable
                      (string-append path ": it cannot be read: " (describe e)))))
    (list 'text (file-text path))))

;; problems : String String Read Read -> (Listof String)
;; What is wrong with the floors file at FPATH and the README at RPATH, given
;; F and R, what reading them found: a Read is what read-text answers. A file
;; that cannot be read is a problem of its own, named after the others', the
;; floors file's first. The README is held to the floors file whenever both
;; can be read.
(define (problems fpath rpath f r)
  (append (if (eq? (car f) 'text)
              (check-floors fpath (cadr f) rpath (and (eq? (car r) 'text) (cadr r)))
              (list (cadr f)))
          (if (eq? (car r) 'text) '() (list (cadr r)))))

;; summary : String -> String
;; The floors in the file text FTEXT, which floors-problems accepts: "chez
;; 10.4.0, sqlite 3.45.1".
(define (summary ftext)
  (let loop ((rest (parse-floors ftext)) (text ""))
    (if (null? rest)
        text
        (loop (cdr rest)
              (string-append text (if (string=? text "") "" ", ")
                             (symbol->string (caar rest)) " "
                             (cadar rest))))))

;; main : (Listof String) -> Unit
(define (main args)
  (if (not (= (length args) 2))
      (begin
        (say (current-error-port)
             "usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README")
        (exit 1))
      (let* ((fpath (car args))
             (rpath (cadr args))
             (f (read-text fpath))
             (r (read-text rpath))
             (found (problems fpath rpath f r)))
        (cond
          ((null? found)
           (say (current-output-port)
                (string-append rpath " holds the floors in " fpath " (" (summary (cadr f)) ")"))
           (exit 0))
          (else
           (for-each (lambda (p) (say (current-error-port) p)) found)
           (say (current-error-port)
                (string-append "FAILED (problems: " (number->string (length found)) ")"))
           (exit 1))))))

(main (cdr (command-line)))
