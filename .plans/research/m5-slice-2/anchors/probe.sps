#!r6rs
;;; For each docs/*.md page, prints the heading anchors two of chez-sqlite3's
;;; rules give, one line per page per rule:
;;;
;;;   site PAGE ANCHOR ...      (site render)'s registry: make-slugger over
;;;                             chez-cmark-gfm's headings
;;;   test-docs PAGE ANCHOR ... tests/test-docs.sps's anchors over its own
;;;                             markdown reading, its definitions read from
;;;                             the file and evaluated, not a copy
;;;
;;; compare.py reads these beside GitHub's rendering. From the repository
;;; root, in the container, after make check-site:
;;;   $CHEZ --libdirs .:build/akku/chez-cmark-gfm/src \
;;;     --program .plans/research/m5-slice-2/anchors/probe.sps
(import (chezscheme) (site io) (site render))

(define (read-datums path)
  (call-with-input-file path
    (lambda (p)
      (let loop ((acc '()))
        (let ((d (read p)))
          (if (eof-object? d) (reverse acc) (loop (cons d acc))))))))

(define (define-name form)
  (and (pair? form) (eq? (car form) 'define) (pair? (cdr form))
       (if (pair? (cadr form)) (caadr form) (cadr form))))

(define (symbols-in x)
  (cond ((symbol? x) (list x))
        ((pair? x) (append (symbols-in (car x)) (symbols-in (cdr x))))
        ((vector? x) (symbols-in (vector->list x)))
        (else '())))

(define (remove-duplicates xs)
  (let loop ((xs xs) (acc '()))
    (cond ((null? xs) (reverse acc))
          ((memq (car xs) acc) (loop (cdr xs) acc))
          (else (loop (cdr xs) (cons (car xs) acc))))))

(define roots '(slurp markdown anchors))

;; The defines the roots need, closed over the file's own defines, in file
;; order.
(define test-docs-forms
  (let* ((forms (filter define-name (read-datums "tests/test-docs.sps")))
         (names (map define-name forms)))
    (let close ((want roots))
      (let ((more (filter (lambda (n) (and (memq n names) (not (memq n want))))
                          (apply append
                                 (map (lambda (n)
                                        (symbols-in (cdr (assq n (map cons names forms)))))
                                      want)))))
        (if (null? more)
            (filter (lambda (f) (memq (define-name f) want)) forms)
            (close (append want (remove-duplicates more))))))))

;; Its record types, every one: a define closes over the names they make.
(define test-docs-records
  (filter (lambda (f) (and (pair? f) (eq? (car f) 'define-record-type)))
          (read-datums "tests/test-docs.sps")))

(define env (copy-environment (environment '(chezscheme))))
(for-each (lambda (f) (eval f env)) test-docs-records)
(for-each (lambda (f) (eval f env)) test-docs-forms)
(define slurp (eval 'slurp env))
(define markdown (eval 'markdown env))
(define anchors (eval 'anchors env))
(define (page-anchors path) (anchors (map cdr (caddr (markdown (slurp path))))))

(define (show rule page anchors)
  (display rule) (display " ") (display page)
  (for-each (lambda (a) (display " ") (display a)) anchors)
  (newline))

(let ((result (render-site (read-site-inputs) "main")))
  (for-each (lambda (entry) (show "site" (car entry) (cdr entry)))
            (site-result-registry result)))

(define (md? f)
  (let ((n (string-length f)))
    (and (> n 3) (string=? (substring f (- n 3) n) ".md"))))

(for-each (lambda (page) (show "test-docs" page (page-anchors (string-append "docs/" page))))
          (list-sort string<? (filter md? (directory-list "docs"))))

(display "probe: defines evaluated from tests/test-docs.sps: ")
(display (map define-name test-docs-forms))
(newline)
