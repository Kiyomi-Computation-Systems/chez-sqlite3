#!r6rs
;;; (foreign-conventions): the calling conventions and types chez-sqlite3's
;;; foreign procedures must carry, and a reader that finds the ones they do
;;; (ADR-0011, decision 6). Test-only: it lives in tests/, and
;;; tests/test-conventions.sps is its suite. tests/test-constants.sps holds
;;; each row's C prototype to sqlite3.h.
;;;
;;;   conventions-table    one row per binding: its C name, its C prototype
;;;                        in sqlite3.h's own spelling, its Chez argument
;;;                        types and result type, its convention, and the
;;;                        records that decide it
;;;   allowed-argument-types, allowed-result-types
;;;                        the only types a binding may write: exactly the
;;;                        types the table uses, and void as a result
;;;   scan-tree            every foreign-procedure form under a directory,
;;;                        read as data, each with the library it sits in
;;;   violations           the scan held against a table: what a suite
;;;                        asserts is empty
;;;
;;; The reader evaluates nothing and fails closed. It reads every .sls under
;;; the directory as data, so a comment or a string holding the words is no
;;; form. It looks at the elements of each list, never at a tail: the tail of
;;; (syntax foreign-procedure) and the tail of an import clause that lists
;;; foreign-procedure among its names both begin with the symbol, and neither
;;; is a form. A form is read from its end: the result type, the argument
;;; types, the entry name, and whatever precedes the entry is its convention.
(library (foreign-conventions)
  (export conventions-table
          row-name row-prototype row-arguments row-result row-convention row-records
          allowed-argument-types allowed-result-types
          scan-tree violations)
  (import (rnrs)
          (only (chezscheme) directory-list file-directory?))

  ;; --- the table ---------------------------------------------------------------

  ;; conventions-table : (Listof Row)
  ;; Row = (NAME PROTOTYPE ARGUMENTS RESULT CONVENTION RECORDS)
  ;;   NAME        String: the C name
  ;;   PROTOTYPE   (RESULT (PARAMETER ...)), each a String in sqlite3.h's own
  ;;               spelling; (RESULT ()) for (void)
  ;;   ARGUMENTS   (Listof Symbol): the Chez argument types
  ;;   RESULT      Symbol: the Chez result type
  ;;   CONVENTION  collect-safe or plain
  ;;   RECORDS     (Listof String): each begins with the record it cites
  ;; In ADR-0002's amended order. Every call that can block is collect-safe:
  ;; sqlite3_open_v2 and sqlite3_close in M1. Every other binding is plain
  ;; (ADR-0011, decision 5). No binding takes a Scheme object: every
  ;; argument is an integer or the address of a block we allocated, and a
  ;; string SQLite returns is an address we read ourselves (decisions 1 and 4).
  (define conventions-table
    '(("sqlite3_libversion_number" ("int" ()) () int plain
       ("ADR-0011 decision 5: it cannot block, so it is plain"
        "ADR-0002 amendment: the report's first binding"))
      ("sqlite3_libversion" ("const char *" ()) () uptr plain
       ("ADR-0011 decision 4: a returned string is an address, read by our own code"
        "ADR-0011 decision 5: plain"
        "ADR-0002 amendment: the report's second binding"))
      ("sqlite3_sourceid" ("const char *" ()) () uptr plain
       ("ADR-0011 decision 4: a returned string is an address, read by our own code"
        "ADR-0011 decision 5: plain"
        "ADR-0002 amendment: the report's third binding"))
      ("sqlite3_threadsafe" ("int" ()) () int plain
       ("ADR-0011 decision 5: plain"
        "ADR-0002 amendment: bound after the floor, for not-threadsafe"))
      ("sqlite3_initialize" ("int" ()) () int plain
       ("ADR-0011 decision 5: plain"
        "ADR-0002 amendment: called once, for a build with SQLITE_OMIT_AUTOINIT"))
      ("sqlite3_compileoption_used" ("int" ("const char *")) (uptr) int plain
       ("ADR-0011 decision 1: the name is the address of a block we allocated"
        "ADR-0011 decision 5: plain"
        "ADR-0002 amendment: a required entry point"))
      ("sqlite3_compileoption_get" ("const char *" ("int")) (int) uptr plain
       ("ADR-0011 decision 4: a returned string is an address, read by our own code"
        "ADR-0011 decision 5: plain"
        "ADR-0002 amendment: a required entry point"))
      ("sqlite3_open_v2" ("int" ("const char *" "sqlite3 **" "int" "const char *"))
       (uptr uptr int uptr) int collect-safe
       ("ADR-0011 decision 5: it can block, creating the file at the open, so it is __collect_safe"
        "ADR-0011 decisions 1 to 3: the filename and the out-pointer are blocks we allocated, zVfs is NULL"
        "ADR-0002 amendment: a required entry point"))
      ("sqlite3_close" ("int" ("sqlite3 *")) (uptr) int collect-safe
       ("ADR-0011 decision 5: it can block, writing, so it is __collect_safe"
        "ADR-0002 amendment: a required entry point"))
      ("sqlite3_errmsg" ("const char *" ("sqlite3 *")) (uptr) uptr plain
       ("ADR-0011 decision 4: a returned string is an address, read by our own code"
        "ADR-0011 decision 5: plain"
        "ADR-0002 amendment: a required entry point"))
      ("sqlite3_errstr" ("const char *" ("int")) (int) uptr plain
       ("ADR-0011 decision 4: a returned string is an address, read by our own code"
        "ADR-0011 decision 5: plain"
        "ADR-0002 amendment: a required entry point"))
      ("sqlite3_errcode" ("int" ("sqlite3 *")) (uptr) int plain
       ("ADR-0011 decision 5: plain"
        "ADR-0002 amendment: a required entry point"))
      ("sqlite3_extended_errcode" ("int" ("sqlite3 *")) (uptr) int plain
       ("ADR-0011 decision 5: plain"
        "ADR-0002 amendment: a required entry point"))
      ("sqlite3_next_stmt" ("sqlite3_stmt *" ("sqlite3 *" "sqlite3_stmt *")) (uptr uptr) uptr plain
       ("ADR-0011 decision 5: plain"
        "ADR-0002 amendment: a required entry point"))
      ("sqlite3_memory_used" ("sqlite3_int64" ()) () integer-64 plain
       ("ADR-0011 decision 5: plain"
        "ADR-0002 amendment: a required entry point"))))

  (define (row-name row) (car row))
  (define (row-prototype row) (cadr row))
  (define (row-arguments row) (caddr row))
  (define (row-result row) (cadddr row))
  (define (row-convention row) (car (cddddr row)))
  (define (row-records row) (cadr (cddddr row)))

  ;; allowed-argument-types, allowed-result-types : (Listof Symbol)
  ;; Written here, not read from the table: a table loosened together with the
  ;; binding it holds would otherwise pass. void is a result only.
  (define allowed-argument-types '(int uptr integer-64))
  (define allowed-result-types '(int uptr integer-64 void))

  ;; --- the reader ----------------------------------------------------------------

  ;; read-data : String -> (U (Listof Any) #f)
  ;; Every datum of the file at PATH, or #f when it cannot be read.
  (define (read-data path)
    (guard (e (#t #f))
      (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                            (make-transcoder (utf-8-codec)))
        (lambda (port)
          (let loop ((found '()))
            (let ((datum (read port)))
              (if (eof-object? datum)
                  (reverse found)
                  (loop (cons datum found)))))))))

  ;; foreign-forms : Any -> (Listof Pair)
  ;; Every list headed by foreign-procedure anywhere in X, in reading order,
  ;; vectors included. It looks at the elements of each list, never at a
  ;; tail: (syntax foreign-procedure) ends in the tail (foreign-procedure),
  ;; and so does an import clause naming foreign-procedure.
  (define (foreign-forms x)
    (cond ((and (pair? x) (eq? (car x) 'foreign-procedure)) (list x))
          ((pair? x)
           (let loop ((rest x) (found '()))
             (if (pair? rest)
                 (loop (cdr rest) (append found (foreign-forms (car rest))))
                 found)))
          ((vector? x) (foreign-forms (vector->list x)))
          (else '())))

  ;; source-files : String String -> (Listof String)
  ;; The paths, relative to ROOT and sorted, of every .sls under ROOT/DIR.
  (define (source-files root dir)
    (let ((here (if (string=? dir "") root (string-append root "/" dir))))
      (apply append
             (map (lambda (name)
                    (let ((relative (if (string=? dir "") name (string-append dir "/" name)))
                          (full (string-append here "/" name)))
                      (cond ((file-directory? full) (source-files root relative))
                            ((ends-with? name ".sls") (list relative))
                            (else '()))))
                  (list-sort string<? (directory-list here))))))

  (define (ends-with? s suffix)
    (let ((n (string-length s)) (k (string-length suffix)))
      (and (>= n k) (string=? (substring s (- n k) n) suffix))))

  ;; library-name : Any -> (U (Listof Any) #f)
  ;; NAME of a top-level (library NAME ...) datum.
  (define (library-name datum)
    (and (pair? datum) (eq? (car datum) 'library)
         (pair? (cdr datum)) (list? (cadr datum))
         (cadr datum)))

  ;; scan-tree : String -> (Listof (U (List 'binding String Any Pair) (List 'unreadable String)))
  ;; Every foreign-procedure form in every .sls under ROOT, in file order and
  ;; reading order: (binding FILE LIBRARY FORM), LIBRARY the name of the
  ;; library it sits in or #f outside one; and (unreadable FILE) for a file
  ;; that cannot be read.
  (define (scan-tree root)
    (apply append
           (map (lambda (file)
                  (let ((data (read-data (string-append root "/" file))))
                    (if data
                        (apply append
                               (map (lambda (datum)
                                      (map (lambda (form) (list 'binding file (library-name datum) form))
                                           (foreign-forms datum)))
                                    data))
                        (list (list 'unreadable file)))))
                (source-files root ""))))

  ;; --- the checks ---------------------------------------------------------------------

  (define native-library '(chez-sqlite3 private native))

  ;; form-parts : Pair -> (U (List Conventions Any Any Any) #f)
  ;; (foreign-procedure CONVENTION ... ENTRY (ARGUMENT ...) RESULT) as
  ;; (CONVENTIONS ENTRY ARGUMENTS RESULT), read from its end; #f for a form
  ;; too short to hold the three.
  (define (form-parts form)
    (let ((rest (cdr form)))
      (and (list? rest) (>= (length rest) 3)
           (let ((r (reverse rest)))
             (list (reverse (cdddr r)) (caddr r) (cadr r) (car r))))))

  ;; literal-type? : Any -> Boolean
  ;; A type written out: a symbol, or a proper list such as (* int).
  (define (literal-type? x) (or (symbol? x) (list? x)))

  ;; convention-of : (Listof Any) -> Any
  (define (convention-of conventions)
    (cond ((null? conventions) 'plain)
          ((equal? conventions '(__collect_safe)) 'collect-safe)
          (else (cons 'other conventions))))

  ;; refused-types : Any (Listof Symbol) (Listof Any) Any -> (Listof Violation)
  (define (refused-types entry allowed-arguments arguments result allowed-results)
    (append
     (let loop ((rest arguments) (i 0) (found '()))
       (cond ((null? rest) (reverse found))
             ((member (car rest) allowed-arguments) (loop (cdr rest) (+ i 1) found))
             (else (loop (cdr rest) (+ i 1)
                         (cons (list 'type-refused entry 'argument i (car rest)) found)))))
     (if (member result allowed-results)
         '()
         (list (list 'type-refused entry 'result result)))))

  ;; form-violations : String Any Pair Table -> (Listof Violation)
  (define (form-violations file library form table)
    (let ((parts (form-parts form)))
      (cond
        ((not (and parts (string? (cadr parts))))
         (append (if (equal? library native-library) '() (list (list 'outside-native file library #f)))
                 (list (list 'entry-not-literal file form))))
        (else
         (let* ((conventions (car parts)) (entry (cadr parts))
                (arguments (caddr parts)) (result (cadddr parts))
                (row (assoc entry table)))
           (append
            (if (equal? library native-library)
                '()
                (list (list 'outside-native file library entry)))
            (if (and (list? arguments) (for-all literal-type? arguments) (literal-type? result))
                (append
                 (refused-types entry allowed-argument-types arguments result allowed-result-types)
                 (if row
                     (append
                      (if (equal? (convention-of conventions) (row-convention row))
                          '()
                          (list (list 'mismatch entry 'convention
                                      (row-convention row) (convention-of conventions))))
                      (if (equal? arguments (row-arguments row))
                          '()
                          (list (list 'mismatch entry 'arguments (row-arguments row) arguments)))
                      (if (equal? result (row-result row))
                          '()
                          (list (list 'mismatch entry 'result (row-result row) result))))
                     (list (list 'no-row entry))))
                (list (list 'types-not-literal entry arguments result)))))))))

  ;; bound-entries : (Listof Item) -> (Listof String)
  ;; Each literal entry the scan found, once per form, in scan order.
  (define (bound-entries items)
    (apply append
           (map (lambda (item)
                  (if (eq? (car item) 'binding)
                      (let ((parts (form-parts (cadddr item))))
                        (if (and parts (string? (cadr parts))) (list (cadr parts)) '()))
                      '()))
                items)))

  ;; violations : String Table -> (Listof Violation)
  ;; What is wrong between the forms under ROOT and TABLE, each one named, in
  ;; this order: per file and form, a form outside native, an entry or type
  ;; lists that are not literal, a type outside the allowlists, a form with no
  ;; row, and a mismatch of convention, arguments or result; then each C name
  ;; bound twice; then each row with no form; and (unreadable FILE) where a
  ;; file could not be read. Empty when all is as the table says.
  (define (violations root table)
    (let* ((items (scan-tree root))
           (entries (bound-entries items)))
      (append
       (apply append
              (map (lambda (item)
                     (if (eq? (car item) 'binding)
                         (form-violations (cadr item) (caddr item) (cadddr item) table)
                         (list item)))
                   items))
       (let loop ((rest entries) (seen '()) (found '()))
         (cond ((null? rest) (reverse found))
               ((member (car rest) seen)
                (loop (cdr rest) seen
                      (if (member (list 'bound-twice (car rest)) found)
                          found
                          (cons (list 'bound-twice (car rest)) found))))
               (else (loop (cdr rest) (cons (car rest) seen) found))))
       (apply append
              (map (lambda (row)
                     (if (member (row-name row) entries) '() (list (list 'no-form (row-name row)))))
                   table))))))
