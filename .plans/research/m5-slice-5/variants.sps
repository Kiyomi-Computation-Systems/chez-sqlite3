;; variants.sps BASE: every build of a C file the suites compile, one line each, as
;; PATH NAME SWITCH..., taken from the suites' own definitions in BASE, read as data and
;; evaluated: tests/extension-build.sls's source and extension-variants, and
;; tests/library-loading.sls's decoy-source and all-builds, with the definitions they
;; reach. Exit 1, naming what is missing, when a definition can't be found or evaluated.
;; sweep-check.sh compiles each changed C file once for each of its lines.
(import (chezscheme))

;; library-body : String -> (Listof Any)
;; The forms after the export and import of the one library PATH holds.
(define (library-body path)
  (let ((form (call-with-input-file path read)))
    (if (and (pair? form) (eq? (car form) 'library) (>= (length form) 4))
        (cdddr form)
        (error 'variants "no library form" path))))

;; defined-name : Any -> (U Symbol #f)
(define (defined-name form)
  (and (pair? form) (eq? (car form) 'define) (pair? (cdr form))
       (let ((target (cadr form)))
         (cond ((symbol? target) target)
               ((and (pair? target) (symbol? (car target))) (car target))
               (else #f)))))

;; evaluated : String (Listof Symbol) Symbol ... -> (Listof Any)
;; The values of RESULTS, after the definitions of NAMES from PATH's library body, in
;; the body's order, are evaluated in (rnrs).
(define (evaluated path names . results)
  (let* ((body (library-body path))
         (defs (filter (lambda (f) (memq (defined-name f) names)) body))
         (found (map defined-name defs)))
    (for-each (lambda (n)
                (unless (memq n found) (error 'variants "no definition" path n)))
              names)
    (eval `(let () ,@defs (list ,@results)) (environment '(rnrs)))))

;; emit : String String (Listof String) -> Void
(define (emit path name switches)
  (display path)
  (display " ")
  (display name)
  (for-each (lambda (s) (display " ") (display s)) switches)
  (newline))

(let ((base (car (command-line-arguments))))
  (guard (e (#t (display "variants: ")
                (display (if (message-condition? e) (condition-message e) "raised"))
                (when (irritants-condition? e)
                  (display " ")
                  (write (condition-irritants e)))
                (newline)
                (exit 1)))
    (let ((ext (evaluated (string-append base "/tests/extension-build.sls")
                          '(source extension-variants) 'source 'extension-variants))
          (decoy (evaluated (string-append base "/tests/library-loading.sls")
                            '(decoy-source lacks lacks-build report-entries rest-entries
                              every-entry optional-entries all-builds)
                            'decoy-source 'all-builds)))
      (for-each (lambda (v) (emit (car ext) (symbol->string (car v)) (caddr v)))
                (cadr ext))
      (for-each (lambda (b) (emit (car decoy) (car b) (cdr b)))
                (cadr decoy))
      (exit 0))))
