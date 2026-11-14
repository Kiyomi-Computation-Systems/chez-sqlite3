#!r6rs
;;; The suite for (chez-sqlite3 private constants): every value held to
;;; SQLite's own sqlite3.h by a C program compiled here, at test time
;;; (ADR-0001). It never loads libsqlite3.
;;;
;;;   rows         src/chez-sqlite3/private/constants.sls, read as data for
;;;                its export list. Every export has a row in constant-rows,
;;;                and every row is an export. A row names the C expression
;;;                its value must equal, or (each PREFIX) for a list of
;;;                (NAME . VALUE) entries, each checked against PREFIX and
;;;                NAME upcased, - as _; or procedure, for an export checked
;;;                by what it answers.
;;;   values       the C program prints each row's C value, and the suite
;;;                asserts the list of mismatches is empty, each one naming
;;;                its row. A name the header lacks is a mismatch too: the
;;;                program asks under #ifdef, so one bad row does not stop
;;;                the compile.
;;;   names        a code's name has no _, no capital and no empty word:
;;;                ioerr_short_read upcases to the same C name as
;;;                ioerr-short-read, so the derivation cannot see it.
;;;   completeness the result-code macros of $CC -dM -E must be exactly the
;;;                table's names when the header is the floor's, and the
;;;                table's names must be a subset of them when it is newer
;;;                (ADR-0013, decision 4). A newer header may name more codes
;;;                than the floor's; the suite says so, by line, when it
;;;                could check only a subset. A header older than the floor
;;;                fails. What counts as a result code macro (result-code-
;;;                macros), the choice of plan, and the problems each plan
;;;                finds are tested on synthetic text.
;;;   procedures   sqlite-result-code-name and sqlite-primary-code-name, by
;;;                their answers on every row and on codes outside the table.
;;;   prototypes   each row of the convention table (tests/foreign-conventions.sls)
;;;                holds its C prototype to sqlite3.h: the C program asks
;;;                _Generic whether the function's type is exactly the row's.
;;;                A map written here, int to int, sqlite3_int64 to
;;;                integer-64 and any pointer to uptr, holds the row's Chez
;;;                types to its C types. A wrong row fails by name, and each
;;;                kind of wrong row is planted in the suite.
;;;
;;; The C program is compiled with $CC and no -I flag: the compiler's own
;;; search path must find sqlite3.h. A missing compiler or header fails a
;;; named row; this suite never skips (ADR-0001). A compile is judged by its
;;; exit status alone.
;;;
;;; Every computation that can raise runs under a guard, before the tests,
;;; with a sentinel of its own: SRFI-64 does not catch a raise in an expected
;;; expression, nor in a suite's top-level definitions, and makes #f of one
;;; in an actual expression. No expected value here is #f.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) getenv)
        (chez-sqlite3-testing)
        (only (foreign-conventions) conventions-table row-name row-prototype row-arguments
              row-result)
        (only (floors) read-floors floor-numbers))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (write (test-result-ref r 'expected-value))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r 'actual-value))
        (newline)))))

;; --- the tables ---------------------------------------------------------------

(define constants-source "src/chez-sqlite3/private/constants.sls")

;; constant-rows : (Listof (Pairof Symbol (U String (List 'each String) 'procedure)))
;; Each export of (chez-sqlite3 private constants), with the C expression its
;; value must equal, (each PREFIX), or procedure.
(define constant-rows
  '((sqlite-open-readonly . "SQLITE_OPEN_READONLY")
    (sqlite-open-readwrite . "SQLITE_OPEN_READWRITE")
    (sqlite-open-create . "SQLITE_OPEN_CREATE")
    (sqlite-open-uri . "SQLITE_OPEN_URI")
    (sqlite-open-memory . "SQLITE_OPEN_MEMORY")
    (sqlite-open-nomutex . "SQLITE_OPEN_NOMUTEX")
    (sqlite-open-fullmutex . "SQLITE_OPEN_FULLMUTEX")
    (sqlite-open-nofollow . "SQLITE_OPEN_NOFOLLOW")
    (sqlite-open-exrescode . "SQLITE_OPEN_EXRESCODE")
    (sqlite-result-codes . (each "SQLITE_"))
    (sqlite-result-code-name . procedure)
    (sqlite-primary-code-name . procedure)))

;; primary-c-names : (Listof String)
;; The primary result codes of SQLite's documentation, by C name: the low
;; byte every extended code carries. Written here, not read from the table.
(define primary-c-names
  '("SQLITE_OK" "SQLITE_ERROR" "SQLITE_INTERNAL" "SQLITE_PERM" "SQLITE_ABORT"
    "SQLITE_BUSY" "SQLITE_LOCKED" "SQLITE_NOMEM" "SQLITE_READONLY"
    "SQLITE_INTERRUPT" "SQLITE_IOERR" "SQLITE_CORRUPT" "SQLITE_NOTFOUND"
    "SQLITE_FULL" "SQLITE_CANTOPEN" "SQLITE_PROTOCOL" "SQLITE_EMPTY"
    "SQLITE_SCHEMA" "SQLITE_TOOBIG" "SQLITE_CONSTRAINT" "SQLITE_MISMATCH"
    "SQLITE_MISUSE" "SQLITE_NOLFS" "SQLITE_AUTH" "SQLITE_FORMAT" "SQLITE_RANGE"
    "SQLITE_NOTADB" "SQLITE_NOTICE" "SQLITE_WARNING" "SQLITE_ROW" "SQLITE_DONE"))

;; --- small helpers ------------------------------------------------------------

;; written : Any -> String
(define (written x)
  (guard (e (#t "<unprintable>"))
    (call-with-string-output-port (lambda (p) (write x p)))))

;; underscored : String -> String
;; S with each - as _.
(define (underscored s)
  (list->string (map (lambda (c) (if (char=? c #\-) #\_ c)) (string->list s))))

;; code-c-name : Symbol -> String
;; The C name a table name stands for: sqlite-ok-symlink is SQLITE_OK_SYMLINK.
(define (code-c-name name)
  (string-append "SQLITE_" (underscored (string-upcase (symbol->string name)))))

;; symbol-before? : Symbol Symbol -> Boolean
(define (symbol-before? a b)
  (string<? (symbol->string a) (symbol->string b)))

;; sort-symbols : (Listof Symbol) -> (Listof Symbol)
(define (sort-symbols symbols) (list-sort symbol-before? symbols))

;; sorted-strings : (Listof String) -> (Listof String)
(define (sorted-strings strings) (list-sort string<? strings))

;; starts-with? : String String -> Boolean
(define (starts-with? text prefix)
  (and (>= (string-length text) (string-length prefix))
       (string=? (substring text 0 (string-length prefix)) prefix)))

;; split-lines : String -> (Listof String)
;; TEXT cut at each newline.
(define (split-lines text)
  (let loop ((i 0) (start 0) (found '()))
    (cond ((= i (string-length text))
           (reverse (if (> i start) (cons (substring text start i) found) found)))
          ((char=? (string-ref text i) #\newline)
           (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
          (else (loop (+ i 1) start found)))))

;; split-words : String -> (Listof String)
;; TEXT cut at each run of spaces, tabs and newlines, empty pieces dropped.
(define (split-words text)
  (let loop ((i 0) (start 0) (found '()))
    (define (piece) (if (> i start) (cons (substring text start i) found) found))
    (cond ((= i (string-length text)) (reverse (piece)))
          ((memv (string-ref text i) '(#\space #\tab #\newline))
           (loop (+ i 1) (+ i 1) (piece)))
          (else (loop (+ i 1) start found)))))

;; strip-spaces : String -> String
;; S without any space or tab.
(define (strip-spaces s)
  (list->string (filter (lambda (c) (not (memv c '(#\space #\tab)))) (string->list s))))

;; digits? : String -> Boolean
;; Whether S is one or more decimal digits and nothing else.
(define (digits? s)
  (and (> (string-length s) 0)
       (for-all char-numeric? (string->list s))
       (for-all (lambda (c) (char<=? #\0 c #\9)) (string->list s))))

;; c-compiler : -> (Listof String)
;; $CC as a command's words; ("cc") when CC is unset or blank.
(define (c-compiler)
  (let ((words (split-words (or (getenv "CC") ""))))
    (if (null? words) '("cc") words)))

;; --- what counts as a result code macro -----------------------------------------

;; parse-define : String -> (U (Pairof String String) #f)
;; "#define NAME BODY" as (NAME . BODY), BODY without spaces or tabs. #f for any
;; other line, and for a function-like macro, whose name carries a (.
(define (parse-define line)
  (and (starts-with? line "#define ")
       (let ((words (split-words (substring line 8 (string-length line)))))
         (and (pair? words)
              (cons (car words)
                    (strip-spaces
                     (let ((rest (substring line 8 (string-length line))))
                       ;; the body is what follows the name
                       (let loop ((i 0))
                         (cond ((= i (string-length rest)) "")
                               ((memv (string-ref rest i) '(#\space #\tab))
                                (substring rest i (string-length rest)))
                               (else (loop (+ i 1))))))))))))

;; c-identifier? : String -> Boolean
;; SQLITE_ and then capitals, digits and _ only.
(define (sqlite-identifier? s)
  (and (starts-with? s "SQLITE_")
       (> (string-length s) 7)
       (for-all (lambda (c) (or (char<=? #\A c #\Z) (char<=? #\0 c #\9) (char=? c #\_)))
                (string->list s))))

;; index-of : String String -> (U Natural #f)
;; Where PART first occurs in TEXT.
(define (index-of text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (cond ((> (+ i k) n) #f)
            ((string=? (substring text i (+ i k)) part) i)
            (else (loop (+ i 1)))))))

;; extended-primary : String String -> (U String #f)
;; The primary code's C name when NAME and BODY (BODY without spaces) are an
;; extended code: BODY is (SQLITE_PRIMARY|(N<<8)), PRIMARY one of the
;; primaries, N decimal, and NAME is SQLITE_PRIMARY_ and something more.
(define (extended-primary name body)
  (and (starts-with? body "(")
       (let ((bar (index-of body "|(")))
         (and bar
              (let ((primary (substring body 1 bar))
                    (tail (substring body (+ bar 2) (string-length body))))
                (and (member primary primary-c-names)
                     (starts-with? name (string-append primary "_"))
                     (> (string-length name) (+ 1 (string-length primary)))
                     (let ((shift (index-of tail "<<8))")))
                       (and shift
                            (digits? (substring tail 0 shift))
                            (= (string-length tail) (+ shift 5))))
                     primary))))))

;; result-code-macros : String -> (Listof String)
;; The C names of the result codes that TEXT, the output of $CC -dM -E,
;; defines, in the text's order. A macro is a result code when its name is
;; SQLITE_ and capitals, digits and _, and either
;;   - its name is one of primary-c-names and its body a decimal integer: the
;;     primary codes; or
;;   - its body is (SQLITE_PRIMARY | (N<<8)), PRIMARY one of them, N decimal,
;;     and its name begins SQLITE_PRIMARY_: the extended codes, in any spacing.
;; Anything else is not: SQLITE_OPEN_* (hex flags), SQLITE_VERSION (a string),
;; SQLITE_TRANSIENT (a cast), a primary's name with a body that is no plain
;; integer, and an OR with a primary that is not shifted by 8.
(define (result-code-macros text)
  (let loop ((lines (split-lines text)) (found '()))
    (if (null? lines)
        (reverse found)
        (let* ((d (parse-define (car lines)))
               (name (and d (car d)))
               (body (and d (cdr d)))
               (code? (and d (sqlite-identifier? name)
                           (or (and (member name primary-c-names) (digits? body) #t)
                               (and (extended-primary name body) #t)))))
          (loop (cdr lines) (if code? (cons name found) found))))))

;; header-define : String String -> (U String #f)
;; The body of NAME's #define in TEXT, spaces dropped.
(define (header-define text name)
  (let loop ((lines (split-lines text)))
    (cond ((null? lines) #f)
          ((let ((d (parse-define (car lines)))) (and d (string=? (car d) name) d))
           => cdr)
          (else (loop (cdr lines))))))

;; --- the completeness plan --------------------------------------------------------

;; completeness-plan : Natural Natural -> (U 'exact 'subset 'below-floor)
;; HEADER-NUMBER is the header's SQLITE_VERSION_NUMBER, FLOOR-NUMBER the
;; floor's. Only the floor's own header can be held to the table's exact set.
(define (completeness-plan header-number floor-number)
  (cond ((= header-number floor-number) 'exact)
        ((> header-number floor-number) 'subset)
        (else 'below-floor)))

;; completeness-problems : Symbol (Listof String) (Listof String)
;;                         -> (Listof (Pairof Symbol (Listof String)))
;; What PLAN finds wrong between the table's C names and the header's. exact:
;; every name in one and not the other; subset: only a table name the header
;; lacks; below-floor: always a problem. Names are sorted.
(define (completeness-problems plan table-names header-names)
  (define (without a b) (sorted-strings (filter (lambda (n) (not (member n b))) a)))
  (let ((missing-from-table (without header-names table-names))
        (missing-from-header (without table-names header-names)))
    (define (keep kind names) (if (null? names) '() (list (cons kind names))))
    (case plan
      ((exact) (append (keep 'header-has-more missing-from-table)
                       (keep 'table-has-more missing-from-header)))
      ((subset) (keep 'table-has-more missing-from-header))
      (else (list (list 'header-below-floor))))))

;; --- the C program ------------------------------------------------------------------

;; c-program : (Listof String) (Listof (List String String)) -> String
;; Prints (header-version N), then for each name (constant "NAME" VALUE) or,
;; when the header defines no macro of that name, (undefined "NAME"); then for
;; each prototype (NAME FUNCTION-TYPE), (prototype "NAME" 1) when the header
;; declares NAME as a function of exactly FUNCTION-TYPE, and 0 when it
;; declares it otherwise. _Generic does not evaluate its operand, so nothing is
;; called or linked. The name is in parentheses, so a function-like macro of
;; its name would not be expanded.
(define (c-program names prototypes)
  (string-append
   "#include <sqlite3.h>\n"
   "#include <stdio.h>\n"
   "\n"
   "#define CONSTANT(e) printf(\"(constant \\\"%s\\\" %lld)\\n\", #e, (long long)(e))\n"
   "#define UNDEFINED(e) printf(\"(undefined \\\"%s\\\")\\n\", #e)\n"
   "#define PROTOTYPE(f, t) printf(\"(prototype \\\"%s\\\" %d)\\n\", #f, _Generic((f), t: 1, default: 0))\n"
   "\n"
   "int main(void)\n"
   "{\n"
   "  printf(\"(header-version %lld)\\n\", (long long)SQLITE_VERSION_NUMBER);\n"
   (apply string-append
          (map (lambda (n)
                 (string-append "#ifdef " n "\n  CONSTANT(" n ");\n#else\n  UNDEFINED(" n
                                ");\n#endif\n"))
               names))
   (apply string-append
          (map (lambda (p) (string-append "  PROTOTYPE(" (car p) ", " (cadr p) ");\n"))
               prototypes))
   "  return 0;\n"
   "}\n"))

;; answer? : Any -> Boolean
(define (answer? d)
  (and (list? d)
       (or (and (= (length d) 2) (eq? (car d) 'header-version)
                (integer? (cadr d)) (exact? (cadr d)))
           (and (= (length d) 2) (eq? (car d) 'undefined) (string? (cadr d)))
           (and (= (length d) 3) (eq? (car d) 'constant) (string? (cadr d))
                (integer? (caddr d)) (exact? (caddr d)))
           (and (= (length d) 3) (eq? (car d) 'prototype) (string? (cadr d))
                (memv (caddr d) '(0 1)) #t))))

;; read-all : String -> (U (Listof Any) #f)
(define (read-all text)
  (guard (e (#t #f))
    (let ((port (open-string-input-port text)))
      (let loop ((data '()))
        (let ((datum (read port)))
          (if (eof-object? datum) (reverse data) (loop (cons datum data))))))))

(define (write-text path text)
  (call-with-port (open-file-output-port path (file-options) (buffer-mode block)
                                         (make-transcoder (utf-8-codec)))
    (lambda (port) (put-string port text))))

;; header-facts : (Listof String) (Listof (List String String))
;;                -> (U (List 'facts (Listof Answer) String)
;;                      (Pairof Symbol Any))
;; In a directory of its own: compiles and runs the program for NAMES, and
;; runs $CC -dM -E on a file that includes sqlite3.h. The facts are what the
;; program printed, read as data, and the macro text. Anything else names the
;; step that went wrong: macros or compile or run (with the command's status,
;; stdout and stderr), output (what the program printed, which is not
;; answers), or raised.
(define (header-facts names prototypes)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((source (string-append dir "/headers.c"))
             (probe (string-append dir "/probe.c"))
             (program (string-append dir "/headers")))
         (write-text source (c-program names prototypes))
         (write-text probe "#include <sqlite3.h>\n")
         (let ((macros (capture-command (append (c-compiler) (list "-dM" "-E" probe)))))
           (if (not (= (car macros) 0))
               (cons 'macros macros)
               (let ((compiled (capture-command
                                (append (c-compiler) (list "-o" program source)))))
                 (if (not (= (car compiled) 0))
                     (cons 'compile compiled)
                     (let ((ran (capture-command (list program))))
                       (if (not (= (car ran) 0))
                           (cons 'run ran)
                           (let ((data (read-all (cadr ran))))
                             (if (and data (for-all answer? data))
                                 (list 'facts data (cadr macros))
                                 (list 'output (cadr ran)))))))))))))))

;; --- constants.sls, read as data ----------------------------------------------------

;; read-data : String -> (U (List 'data (Listof Any)) (List 'unreadable String String))
(define (read-data path)
  (guard (e (#t (list 'unreadable path (describe e))))
    (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      (lambda (port)
        (let loop ((found '()))
          (let ((datum (read port)))
            (if (eof-object? datum)
                (list 'data (reverse found))
                (loop (cons datum found)))))))))

;; library-form? : Any -> Boolean
;; (library NAME (export ...) (import ...) BODY ...)
(define (library-form? d)
  (and (list? d) (>= (length d) 4) (eq? (car d) 'library)
       (list? (caddr d)) (pair? (caddr d)) (eq? (car (caddr d)) 'export)
       (list? (cadddr d)) (pair? (cadddr d)) (eq? (car (cadddr d)) 'import)))

;; constants-read : (U (List 'read (Listof Symbol)) (Pairof Symbol Any))
;; The export list, when every export is an identifier. A (rename ...) spec
;; is not read, and fails here rather than going unchecked.
(define constants-read
  (guard (e (#t (list 'raised (describe e))))
    (let ((found (read-data constants-source)))
      (if (eq? (car found) 'data)
          (let ((form (find library-form? (cadr found))))
            (if form
                (let* ((specs (cdr (caddr form)))
                       (odd (filter (lambda (spec) (not (symbol? spec))) specs)))
                  (if (null? odd) (list 'read specs) (list 'exports-not-identifiers odd)))
                (list 'no-library-form constants-source)))
          found))))

;; exports : (Listof Symbol)
(define exports
  (if (eq? (car constants-read) 'read) (cadr constants-read) '()))

;; constant-value : Symbol -> Any
;; NAME's value in (chez-sqlite3 private constants), or (no-value TEXT).
(define (constant-value name)
  (guard (e (#t (list 'no-value (describe e))))
    (eval name (environment '(chez-sqlite3 private constants)))))

;; entries? : Any -> Boolean
;; A non-empty list of (NAME . NATURAL), each NAME a symbol.
(define (entries? x)
  (and (list? x) (pair? x)
       (for-all (lambda (entry)
                  (and (pair? entry) (symbol? (car entry))
                       (integer? (cdr entry)) (exact? (cdr entry)) (>= (cdr entry) 0)))
                x)))

;; --- the checks ---------------------------------------------------------------------

;; A check is (LABEL C-NAME SCHEME-VALUE): LABEL names the row for a reader.

;; row-checks : Row -> (Listof Check)
(define (row-checks row)
  (let ((name (car row)) (c (cdr row)))
    (cond
      ((string? c)
       (list (list (string-append (symbol->string name) " is " c) c (constant-value name))))
      ((and (list? c) (= (length c) 2) (eq? (car c) 'each) (string? (cadr c)))
       (let ((entries (constant-value name)))
         (if (entries? entries)
             (map (lambda (entry)
                    (let ((c-name (code-c-name (car entry))))
                      (list (string-append (symbol->string name) ": "
                                           (symbol->string (car entry)) " is " c-name)
                            c-name
                            (cdr entry))))
                  entries)
             (list (list (string-append (symbol->string name) " is a list of entries")
                         "" entries)))))
      (else '()))))

(define checks
  (guard (e (#t (list 'raised (describe e))))
    (apply append (map row-checks constant-rows))))

(define check-list (if (and (pair? checks) (eq? (car checks) 'raised)) '() checks))

;; The C names asked, once each, in the order of the checks.
(define asked-names
  (let loop ((cs check-list) (seen '()))
    (cond ((null? cs) (reverse seen))
          ((member (cadr (car cs)) seen) (loop (cdr cs) seen))
          (else (loop (cdr cs) (cons (cadr (car cs)) seen))))))

;; --- the prototypes ---------------------------------------------------------------------

;; The convention table (tests/foreign-conventions.sls) has a row per binding:
;; its C name, its prototype in sqlite3.h's own spelling and the Chez types it
;; binds with. The C program holds each prototype to the header, through
;; _Generic on the function itself, and the map below holds each row's Chez
;; types to its C types.

;; function-type : Row -> String
;; The row's prototype as a C pointer-to-function type: RESULT (*)(PARAMETERS),
;; (void) for none.
(define (function-type row)
  (let ((proto (row-prototype row)))
    (string-append (car proto) " (*)("
                   (if (null? (cadr proto))
                       "void"
                       (fold-left (lambda (acc p) (string-append acc ", " p))
                                  (car (cadr proto)) (cdr (cadr proto))))
                   ")")))

;; prototype-ask : Row -> (List String String)
(define (prototype-ask row) (list (row-name row) (function-type row)))

(define prototype-asks (map prototype-ask conventions-table))

;; ends-with? : String String -> Boolean
(define (ends-with? text suffix)
  (and (>= (string-length text) (string-length suffix))
       (string=? (substring text (- (string-length text) (string-length suffix))
                            (string-length text))
                 suffix)))

;; chez-type : String -> (U Symbol #f)
;; The Chez type a C type is bound as: int is int, sqlite3_int64 is integer-64,
;; and any pointer, const char * and sqlite3 ** among them, is the address
;; itself, uptr (ADR-0011, decisions 1 and 4). Any other C type has no
;; mapping, and a row that writes one fails until a record decides it.
(define (chez-type c-type)
  (cond ((string=? c-type "int") 'int)
        ((string=? c-type "sqlite3_int64") 'integer-64)
        ((ends-with? c-type "*") 'uptr)
        (else #f)))

;; map-problems : Table -> (Listof (List String Any Any Any Any))
;; Each row whose Chez types are not the map of its C types:
;; (NAME MAPPED-ARGUMENTS MAPPED-RESULT ARGUMENTS RESULT).
(define (map-problems rows)
  (filter (lambda (m) m)
          (map (lambda (row)
                 (let ((arguments (map chez-type (cadr (row-prototype row))))
                       (result (chez-type (car (row-prototype row)))))
                   (if (and (equal? arguments (row-arguments row)) (eq? result (row-result row)))
                       #f
                       (list (row-name row) arguments result (row-arguments row) (row-result row)))))
               rows)))

(define facts (header-facts asked-names prototype-asks))

(define answers (if (eq? (car facts) 'facts) (cadr facts) '()))
(define macro-text (if (eq? (car facts) 'facts) (caddr facts) ""))

;; header-number : (U Natural #f)
;; SQLITE_VERSION_NUMBER, as the program printed it.
(define header-number
  (let ((entry (find (lambda (a) (eq? (car a) 'header-version)) answers)))
    (and entry (cadr entry))))

;; answer-for : String -> (U Integer 'undefined 'no-answer)
(define (answer-for c-name)
  (let ((entry (find (lambda (a) (and (memq (car a) '(constant undefined))
                                      (string=? (cadr a) c-name)))
                     answers)))
    (cond ((not entry) 'no-answer)
          ((eq? (car entry) 'undefined) 'undefined)
          (else (caddr entry)))))

;; mismatches : (Listof (List String Any Any))
;; Each check whose Scheme value is not the C value: (LABEL SCHEME C).
(define mismatches
  (filter (lambda (m) m)
          (map (lambda (c)
                 (let ((seen (answer-for (cadr c))))
                   (if (and (integer? (caddr c)) (eqv? (caddr c) seen))
                       #f
                       (list (car c) (caddr c) seen))))
               check-list)))

;; The table, read for the checks that follow.
(define table
  (let ((v (constant-value 'sqlite-result-codes)))
    (if (entries? v) v '())))

(define table-names (map car table))
(define table-c-names (map code-c-name table-names))

;; shape-problems : (Listof Symbol)
;; The names that are not lower-case words, joined by single hyphens.
(define (name-shaped? name)
  (let* ((s (symbol->string name))
         (cs (string->list s)))
    (and (> (string-length s) 0)
         (for-all (lambda (c) (or (char<=? #\a c #\z) (char<=? #\0 c #\9) (char=? c #\-))) cs)
         (not (char=? (car cs) #\-))
         (not (char=? (car (reverse cs)) #\-))
         (not (index-of s "--")))))

;; The floor's SQLITE_VERSION_NUMBER: 3.45.1 is 3045001.
(define floor-number
  (guard (e (#t 'raised))
    (let ((n (floor-numbers (read-floors) 'sqlite)))
      (+ (* (car n) 1000000) (* (cadr n) 1000) (caddr n)))))

(define plan
  (if (and (integer? header-number) (integer? floor-number))
      (completeness-plan header-number floor-number)
      'unknown))

(define header-names (result-code-macros macro-text))

;; --- the suite -------------------------------------------------------------------

(test-begin "constants")

;; --- the oracle -----------------------------------------------------------------

(test-equal "oracle: constants.sls is read as a library with identifier exports"
  'read (car constants-read))

(test-equal "oracle: the C program compiled and ran against sqlite3.h"
  'facts (car facts))

(test-equal "oracle: the program printed its header version"
  'integer (if (integer? header-number) 'integer 'none))

(test-equal "oracle: every row's check could be made"
  'checks (if (and (pair? checks) (eq? (car checks) 'raised)) 'raised 'checks))

;; --- every export has a row, and every row is an export ----------------------------

(test-equal "rows: every export has a row"
  '() (sort-symbols (filter (lambda (e) (not (assq e constant-rows))) exports)))

(test-equal "rows: every row is an export"
  '() (sort-symbols (filter (lambda (r) (not (memq r exports))) (map car constant-rows))))

(test-equal "rows: no export is listed twice"
  '() (filter (lambda (e) (> (length (filter (lambda (x) (eq? x e)) exports)) 1)) exports))

;; --- values, against the header -----------------------------------------------------

(test-equal "values: every checked value equals the header's, naming each bad row"
  '() mismatches)

(test-equal "values: every question got an answer"
  '() (filter (lambda (c) (eq? (answer-for c) 'no-answer)) asked-names))

(test-equal "values: the table asks 108 codes, and the checks ask 117 names"
  '(108 117) (list (length table) (length asked-names)))

;; --- the table's own shape ------------------------------------------------------------

(test-equal "table: every name is lower-case words joined by hyphens"
  '() (filter (lambda (n) (not (name-shaped? n))) table-names))

(test-equal "table: no name and no value twice"
  '(() ())
  (list (filter (lambda (n) (> (length (filter (lambda (x) (eq? x n)) table-names)) 1))
                table-names)
        (filter (lambda (v) (> (length (filter (lambda (x) (eqv? x v)) (map cdr table))) 1))
                (map cdr table))))

(test-equal "table: the primary codes, below 256, are exactly the documented ones"
  (sorted-strings primary-c-names)
  (sorted-strings (map code-c-name (map car (filter (lambda (e) (< (cdr e) 256)) table)))))

(test-equal "table: an extended code's low byte is a primary code, and its name begins with its name"
  '()
  (filter (lambda (e)
            (let* ((primary (find (lambda (p) (and (< (cdr p) 256)
                                                   (= (cdr p) (bitwise-and (cdr e) 255))))
                                  table))
                   (prefix (and primary (string-append (symbol->string (car primary)) "-"))))
              (not (and primary (starts-with? (symbol->string (car e)) prefix)))))
          (filter (lambda (e) (>= (cdr e) 256)) table)))

;; --- completeness -----------------------------------------------------------------

;; Against the floor's own header the sets must be equal; against a newer one
;; the suite can only say the table's names are in it, and says so.
(let ((problems (completeness-problems plan table-c-names header-names)))
  (test-equal (case plan
                ((exact) "completeness: the header's result codes are exactly the table's")
                ((subset) "completeness: the table's names are a subset of the header's")
                (else "completeness: the header is at the floor or newer, and its version was read"))
    '() (if (eq? plan 'unknown) (list (list 'no-plan header-number floor-number)) problems))
  (when (eq? plan 'subset)
    (display "test-constants: completeness checked against a subset only: header ")
    (display header-number)
    (display " is newer than the floor ")
    (display floor-number)
    (newline)))

;; --- the recogniser, on synthetic -dM text ------------------------------------------

(define synthetic-text
  (string-append
   ;; primaries, as the header defines them
   "#define SQLITE_OK 0\n"
   "#define SQLITE_BUSY 5\n"
   "#define SQLITE_ROW 100\n"
   "#define SQLITE_DONE 101\n"
   ;; extended codes, in each spacing
   "#define SQLITE_IOERR_SHORT_READ (SQLITE_IOERR | (2<<8))\n"
   "#define SQLITE_IOERR (10)\n"
   "#define SQLITE_BUSY_TIMEOUT (SQLITE_BUSY|(3<<8))\n"
   "#define SQLITE_OK_SYMLINK   (  SQLITE_OK  |  ( 2<<8 )  )\n"
   "#define SQLITE_ABORT_ROLLBACK (SQLITE_ABORT | (2<<8))\n"
   ;; decoys
   "#define SQLITE_OPEN_READONLY 0x00000001\n"
   "#define SQLITE_OPEN_CREATE 4\n"
   "#define SQLITE_VERSION \"3.45.1\"\n"
   "#define SQLITE_VERSION_NUMBER 3045001\n"
   "#define SQLITE_TRANSIENT ((sqlite3_destructor_type)-1)\n"
   "#define SQLITE_STATIC ((sqlite3_destructor_type)0)\n"
   "#define SQLITE_CONSTRAINT_X (SQLITE_CONSTRAINT | 0x10)\n"
   "#define SQLITE_BUSY_X (SQLITE_BUSY | (3<<4))\n"
   "#define SQLITE_BUSY_Y (SQLITE_LOCKED | (3<<8))\n"
   "#define SQLITE_ERROR_Z (SQLITE_NOPE | (1<<8))\n"
   "#define SQLITE_ERROR_Q (SQLITE_ERROR | (x<<8))\n"
   "#define SQLITE_ERROR_R (SQLITE_ERROR | (1<<8)) + 1\n"
   "#define SQLITE_FULL(x) 13\n"
   "#define SQLITE_MISUSE 0x15\n"
   "#define OTHER_OK 0\n"
   "#define sqlite_ok 0\n"
   "#define SQLITE_CANTOPEN_ (SQLITE_CANTOPEN | (1<<8))\n"
   "#undef SQLITE_NOTADB\n"
   "typedef int SQLITE_ABORT_TYPE;\n"))

(test-equal "recogniser: a primary, an extended code in each spacing, and no decoy"
  '("SQLITE_OK" "SQLITE_BUSY" "SQLITE_ROW" "SQLITE_DONE"
    "SQLITE_IOERR_SHORT_READ" "SQLITE_BUSY_TIMEOUT" "SQLITE_OK_SYMLINK"
    "SQLITE_ABORT_ROLLBACK")
  (result-code-macros synthetic-text))

(test-equal "recogniser: the shifted form alone"
  '("SQLITE_IOERR_READ")
  (result-code-macros "#define SQLITE_IOERR_READ (SQLITE_IOERR | (1<<8))\n"))

(test-equal "recogniser: a primary alone"
  '("SQLITE_NOTICE")
  (result-code-macros "#define SQLITE_NOTICE 27\n"))

(test-equal "recogniser: the decoys alone name nothing"
  '()
  (result-code-macros
   (string-append "#define SQLITE_OPEN_READONLY 0x00000001\n"
                  "#define SQLITE_VERSION \"3.45.1\"\n"
                  "#define SQLITE_TRANSIENT ((sqlite3_destructor_type)-1)\n")))

(test-equal "recogniser: a header's version number is read from the text"
  '("3045001" #f)
  (list (header-define synthetic-text "SQLITE_VERSION_NUMBER")
        (header-define synthetic-text "SQLITE_NOSUCH")))

;; --- the plan, on fixtures --------------------------------------------------------

(test-equal "plan: the floor's own header is held to exactly the table's names"
  '(exact subset subset below-floor below-floor)
  (list (completeness-plan 3045001 3045001) (completeness-plan 3053001 3045001)
        (completeness-plan 3045002 3045001) (completeness-plan 3044999 3045001)
        (completeness-plan 2999999 3045001)))

(define fixture-table '("SQLITE_OK" "SQLITE_ERROR" "SQLITE_ERROR_X"))

(test-equal "problems: exact, the same sets, finds nothing"
  '() (completeness-problems 'exact fixture-table '("SQLITE_ERROR_X" "SQLITE_OK" "SQLITE_ERROR")))

(test-equal "problems: exact finds a header code the table lacks, and a table name the header lacks"
  '((header-has-more "SQLITE_A" "SQLITE_B") (table-has-more "SQLITE_ERROR_X"))
  (completeness-problems 'exact fixture-table '("SQLITE_B" "SQLITE_OK" "SQLITE_ERROR" "SQLITE_A")))

(test-equal "problems: subset lets the header have more"
  '() (completeness-problems 'subset fixture-table
                             '("SQLITE_NEW" "SQLITE_OK" "SQLITE_ERROR" "SQLITE_ERROR_X")))

(test-equal "problems: subset finds a table name the header lacks"
  '((table-has-more "SQLITE_ERROR" "SQLITE_ERROR_X"))
  (completeness-problems 'subset fixture-table '("SQLITE_NEW" "SQLITE_OK")))

(test-equal "problems: a header below the floor is a problem, however alike"
  '((header-below-floor))
  (completeness-problems 'below-floor fixture-table fixture-table))

;; --- the procedures -----------------------------------------------------------------

;; Each answer is computed under a guard, with a sentinel of its own.
(define (answers-of proc codes)
  (guard (e (#t (list 'raised (describe e))))
    (map proc codes)))

(define result-code-name
  (guard (e (#t #f)) (constant-value 'sqlite-result-code-name)))
(define primary-code-name
  (guard (e (#t #f)) (constant-value 'sqlite-primary-code-name)))

(test-equal "sqlite-result-code-name: every row's value answers its name"
  table-names
  (answers-of result-code-name (map cdr table)))

(test-equal "sqlite-result-code-name: a code the table has no row for is itself"
  '(29 99 102 9999 4096 -1 65535)
  (answers-of result-code-name '(29 99 102 9999 4096 -1 65535)))

(test-equal "sqlite-primary-code-name: examples, an extended code, a primary, and codes outside"
  '(ioerr locked ok done row ioerr protocol 29 busy)
  (answers-of primary-code-name '(522 262 256 101 100 3082 9999 285 773)))

(test-equal "sqlite-primary-code-name: every row's value answers the name of its low byte"
  (map (lambda (e)
         (let ((low (find (lambda (p) (= (cdr p) (bitwise-and (cdr e) 255))) table)))
           (if low (car low) 'no-primary)))
       table)
  (answers-of primary-code-name (map cdr table)))

;; --- the prototypes, against the header --------------------------------------------------

;; prototype-answer : String -> (U 0 1 'no-answer)
(define (prototype-answer name)
  (let ((entry (find (lambda (a) (and (eq? (car a) 'prototype) (string=? (cadr a) name))) answers)))
    (if entry (caddr entry) 'no-answer)))

;; verdicts-of : (Listof Row) -> (U (Listof (Pair String Any)) (Pair Symbol Any))
;; A fresh compile and run of the C program, asking only ROWS' prototypes:
;; each row's name and the program's answer, or the step that failed.
(define (verdicts-of rows)
  (guard (e (#t (list 'raised (describe e))))
    (let ((f (header-facts '() (map prototype-ask rows))))
      (if (eq? (car f) 'facts)
          (map (lambda (row)
                 (let ((entry (find (lambda (a) (and (eq? (car a) 'prototype)
                                                     (string=? (cadr a) (row-name row))))
                                    (cadr f))))
                   (cons (row-name row) (if entry (caddr entry) 'no-answer))))
               rows)
          f))))

(test-equal "prototypes: the table has a row for each of M1's 15 entry points"
  15 (length conventions-table))

(test-equal "prototypes: the header declares each row's prototype exactly: the rows it does not, each by name"
  '()
  (map car (filter (lambda (row) (not (eqv? (prototype-answer (row-name row)) 1)))
                   conventions-table)))

(test-equal "prototypes: every question got an answer, 1 or 0"
  '()
  (map car (filter (lambda (row) (eq? (prototype-answer (row-name row)) 'no-answer))
                   conventions-table)))

(test-equal "prototypes: each row's Chez types are the map of its C types, the rows that are not each by name"
  '()
  (map-problems conventions-table))

;; The map, written out: int, sqlite3_int64 and every pointer; nothing else.
(test-equal "map: int is int, sqlite3_int64 is integer-64, any pointer is uptr, and nothing else is mapped"
  '(int integer-64 uptr uptr uptr uptr #f #f #f #f #f #f #f #f)
  (map chez-type '("int" "sqlite3_int64" "const char *" "sqlite3 **" "sqlite3 *" "sqlite3_stmt *"
                   "unsigned int" "long" "long long" "sqlite3_uint64" "double" "size_t"
                   "void" "const char")))

;; The C side's control: a row written as the header does not declare it must
;; be answered 0, by name, and written right 1. Each pair differs in the one
;; thing named.
(test-equal "the prototype check refuses a wrong parameter type: sqlite3_open_v2 with its sqlite3 ** written sqlite3 *, and answers 1 when it is written right"
  '((("sqlite3_open_v2" . 1)) (("sqlite3_open_v2" . 0)))
  (list (verdicts-of (list (list "sqlite3_open_v2"
                                 '("int" ("const char *" "sqlite3 **" "int" "const char *"))
                                 '(uptr uptr int uptr) 'int 'collect-safe '())))
        (verdicts-of (list (list "sqlite3_open_v2"
                                 '("int" ("const char *" "sqlite3 *" "int" "const char *"))
                                 '(uptr uptr int uptr) 'int 'collect-safe '())))))

(test-equal "the prototype check refuses a result written int where the header has sqlite3_int64, and a dropped const, each by name"
  '(("sqlite3_memory_used" . 0) ("sqlite3_errmsg" . 0) ("sqlite3_errstr" . 1))
  (verdicts-of (list (list "sqlite3_memory_used" '("int" ()) '() 'int 'plain '())
                     (list "sqlite3_errmsg" '("char *" ("sqlite3 *")) '(uptr) 'uptr 'plain '())
                     (list "sqlite3_errstr" '("const char *" ("int")) '(int) 'uptr 'plain '()))))

(test-equal "the prototype check refuses a parameter count: sqlite3_close with an extra int, and sqlite3_threadsafe given a parameter"
  '(("sqlite3_close" . 0) ("sqlite3_threadsafe" . 0))
  (verdicts-of (list (list "sqlite3_close" '("int" ("sqlite3 *" "int")) '(uptr int) 'int 'collect-safe '())
                     (list "sqlite3_threadsafe" '("int" ("int")) '(int) 'int 'plain '()))))

(test-equal "the map check names a row whose Chez types differ from its C types: sqlite3_close taking int, sqlite3_errstr returning int, sqlite3_memory_used returning int, and a C type the map lacks"
  '(("sqlite3_close" (uptr) int (int) int)
    ("sqlite3_errstr" (int) uptr (int) int)
    ("sqlite3_memory_used" () integer-64 () int)
    ("sqlite3_sourceid" () #f () uptr))
  (map-problems
   (list (list "sqlite3_close" '("int" ("sqlite3 *")) '(int) 'int 'collect-safe '())
         (list "sqlite3_errstr" '("const char *" ("int")) '(int) 'int 'plain '())
         (list "sqlite3_memory_used" '("sqlite3_int64" ()) '() 'int 'plain '())
         (list "sqlite3_sourceid" '("double" ()) '() 'uptr 'plain '()))))

(test-end "constants")

(exit (suite-exit-status runner))
