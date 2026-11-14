#!r6rs
;;; make check-floors: reads the floors file, the README, every file under the
;;; workflow directory and every file under the CI scripts directory named on
;;; the command line (make passes packaging/floors.sexp, README.org,
;;; .github/workflows and scripts/ci) and fails, naming each problem, unless README.org's Requirements section states the floors in
;;; packaging/floors.sexp (the lines (floors)'s requirement-lines writes from
;;; the file, whole, as one list), and no line of any file in the workflow
;;; directory contains either floor's version text, contains the SQLite
;;; floor's version number or amalgamation number as a whole run of digits
;;; (3045001, 3450100 for 3.45.1), holds a backslash after a double quote, or
;;; holds an odd number of double quotes, a double-quoted string left open at
;;; the line's end: CI states no floor, and scripts/ci/floor.sh reads them from
;;; the file. And no line of any file in the scripts directory contains either
;;; floor's version text or the SQLite floor's numeric forms as whole runs of
;;; digits; the two rules about double quotes are YAML's, and a script is shell,
;;; so they do not apply there. The rules are in (floors); this program reads
;;; the files, prints, and exits. tests/test-check-floors.sps holds each rule on texts and runs
;;; this program on fixture directories.
;;;
;;; The workflow directory and the scripts directory are each read whole: every
;;; file in it and in its subdirectories, whatever its name, in the order of
;;; their paths. The directory must be a directory, not a symbolic link to one;
;;; a symbolic link to a directory inside it is not followed: it is read as a
;;; file, which fails.
;;;
;;; It fails closed, because a check that passes on nothing is vacuous. It
;;; names, and exits 1 on, a file or directory it cannot read, a floors file
;;; with a problem, a README with no "** Requirements" section or the wrong list
;;; in it, a workflow directory that holds no file or no ci.yml, a scripts
;;; directory that holds no file or no floor.sh, and a floor, a numeric form of
;;; the SQLite floor, or, in a workflow only, a backslash after a double quote
;;; or an odd number of double quotes, written anywhere in them. A file it
;;; cannot read does not stop it comparing the others.
;;;
;;; It prints one line on a pass, to stdout, naming the files it read under the
;;; workflow directory, then those under the scripts directory, and the floors
;;; it found, or each problem and then a
;;; count of them on a failure, to stderr. It exits 0 or 1, never a count.
(import (rnrs)
        (floors)
        (only (chezscheme) directory-list display-condition file-directory?
                file-symbolic-link?))

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

(define (text-or-false read)
  (and (eq? (car read) 'text) (cadr read)))

;; walk : String -> (Listof String)
;; Every file under DIR, as a path, in subdirectories too, in no set order.
;; A subdirectory is entered only when it is a directory itself, not a
;; symbolic link to one, which is a file here. It raises when a directory
;; cannot be listed.
(define (walk dir)
  (apply append
         (map (lambda (name)
                (let ((path (string-append dir "/" name)))
                  (if (file-directory? path #f) (walk path) (list path))))
              (directory-list dir))))

;; read-directory : String
;;   -> (U (List 'files (Listof (List String (U (List 'text String) (List 'unreadable String)))))
;;         (List 'unreadable String))
;; Every file under the directory DIR, the workflows or the scripts, in the
;; order of its path, with its text or the problem with reading it, or the
;; problem with listing the directory. DIR itself must not be a symbolic link.
(define (read-directory wdir)
  (guard (e (#t (list 'unreadable (string-append wdir ": it cannot be read: " (describe e)))))
    (when (file-symbolic-link? wdir)
      (error #f "it is a symbolic link, not a directory"))
    (list 'files
          (map (lambda (path) (list path (read-text path)))
               (list-sort string<? (walk wdir))))))

;; texts : (U (Listof (List String (U (List 'text String) (List 'unreadable String)))) #f)
;;   -> (U (Listof (List String (U String #f))) #f)
;; The files of a directory read as the pure checks take them: each path and
;; its text, or #f for a file that could not be read; #f for a directory that
;; could not be listed.
(define (texts files)
  (and files
       (map (lambda (file) (list (car file) (text-or-false (cadr file)))) files)))

;; unreadable : Directory -> (Listof String)
;; The problems of reading a directory W (what read-directory answers): the
;; directory's own when it could not be listed, else each file's that could not
;; be read, in path order.
(define (unreadable w)
  (if (eq? (car w) 'files)
      (apply append
             (map (lambda (file)
                    (if (eq? (car (cadr file)) 'text) '() (list (cadr (cadr file)))))
                  (cadr w)))
      (list (cadr w))))

;; problems : String String String String Read Read Directory Directory -> (Listof String)
;; What is wrong with the floors file at FPATH, the README at RPATH, the files
;; under the workflow directory WDIR and those under the scripts directory
;; SDIR, given F, R, W and S, what reading them found: a Read is what
;; read-text answers, and a Directory what read-directory answers. A file or
;; directory that cannot be read is a problem of its own, named after the
;; others', the floors file's first, then the README's, then the workflow
;; directory's or its files', in path order, then the scripts'. The README,
;; the workflows and the scripts are each held to the floors file whenever it
;; and they can be read.
(define (problems fpath rpath wdir sdir f r w s)
  (let ((files (and (eq? (car w) 'files) (cadr w)))
        (scripts (and (eq? (car s) 'files) (cadr s))))
    (append (if (eq? (car f) 'text)
                (append
                 (check-floors fpath (cadr f) rpath (text-or-false r) wdir (texts files))
                 (if (and scripts (null? (floors-problems fpath (cadr f))))
                     (scripts-problems fpath sdir (texts scripts) (parse-floors (cadr f)))
                     '()))
                (list (cadr f)))
            (if (eq? (car r) 'text) '() (list (cadr r)))
            (unreadable w)
            (unreadable s))))

;; read-names : String Directory -> (Listof String)
;; The paths of the files W found under WDIR, relative to it, in order.
(define (read-names wdir w)
  (let ((skip (+ (string-length wdir) 1)))
    (map (lambda (file) (substring (car file) skip (string-length (car file))))
         (cadr w))))

;; joined : (Listof String) -> String
;; NAMES with ", " between them.
(define (joined names)
  (fold-left (lambda (text name) (if (string=? text "") name (string-append text ", " name)))
             ""
             names))

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
  (if (not (= (length args) 4))
      (begin
        (say (current-error-port)
             "usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README WORKFLOWS SCRIPTS")
        (exit 1))
      (let* ((fpath (car args))
             (rpath (cadr args))
             (wdir (caddr args))
             (sdir (cadddr args))
             (f (read-text fpath))
             (r (read-text rpath))
             (w (read-directory wdir))
             (s (read-directory sdir))
             (found (problems fpath rpath wdir sdir f r w s)))
        (cond
          ((null? found)
           (say (current-output-port)
                (string-append rpath ", " wdir " (" (joined (read-names wdir w)) ")"
                               " and " sdir " (" (joined (read-names sdir s)) ")"
                               " hold the floors in " fpath " (" (summary (cadr f)) ")"))
           (exit 0))
          (else
           (for-each (lambda (p) (say (current-error-port) p)) found)
           (say (current-error-port)
                (string-append "FAILED (problems: " (number->string (length found)) ")"))
           (exit 1))))))

(main (cdr (command-line)))
