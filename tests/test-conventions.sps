#!r6rs
;;; The convention suite (ADR-0011, decision 6): every foreign-procedure form
;;; under src/, read as data, held to a table with one row per binding. It
;;; never loads libsqlite3. tests/test-constants.sps holds each row's C
;;; prototype to sqlite3.h, and the map from its C types to its Chez types.
;;;
;;;   the table      written-out names and conventions, so a table loosened
;;;                  with the binding it holds still fails; each row's shape;
;;;                  every cited record exists; the allowlists, written out,
;;;                  are the types the table uses and void as a result
;;;   src/           no violation, and the 15 forms are all native's
;;;   fixtures       tests/fixtures/conventions/<case>/, each the one fault it
;;;                  names, and the whole list of violations asserted: a form
;;;                  outside native, an entry that is no string literal, type
;;;                  lists that are not literal, a plain open or close, a
;;;                  collect-safe anything else, a form with no row, a row
;;;                  with no form, a C name bound twice, a file that cannot be
;;;                  read, and words that are no form
;;;   sweeps         each row of the table, changed in each field in turn,
;;;                  held against the real src/; each row removed in turn
;;;   the allowlist  against its whole complement: every type Chez 10.4
;;;                  accepts that the table does not use, each in a fixture
;;;                  binding as an argument and as a result, and the suite
;;;                  asks Chez itself that each is accepted
;;;
;;; Every computation that can raise runs under a guard with a sentinel of
;;; its own: SRFI-64 makes #f of a raise in an actual expression, and catches
;;; none in an expected expression or a top-level definition. No expected
;;; value here is #f, and none depends on the order of a call's arguments.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) directory-list load-shared-object machine-type)
        (chez-sqlite3-testing)
        (foreign-conventions))

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

;; --- what the table must say, written out ---------------------------------------------

;; expected-names : (Listof String)
;; ADR-0002's amended order: the report's three, the threadsafe answer,
;; sqlite3_initialize, then the rest of M1's required list.
(define expected-names
  '("sqlite3_libversion_number" "sqlite3_libversion" "sqlite3_sourceid"
    "sqlite3_threadsafe" "sqlite3_initialize"
    "sqlite3_compileoption_used" "sqlite3_compileoption_get"
    "sqlite3_open_v2" "sqlite3_close" "sqlite3_errmsg" "sqlite3_errstr"
    "sqlite3_errcode" "sqlite3_extended_errcode" "sqlite3_next_stmt"
    "sqlite3_memory_used"))

;; collect-safe-names : (Listof String)
;; The calls that can block (ADR-0011, decision 5); every other is plain.
(define collect-safe-names '("sqlite3_open_v2" "sqlite3_close"))

;; accepted-types : (Listof Any)
;; Every foreign type Chez 10.4 accepts (CSUG 4.2) that the table does not
;; use. The allowlist must refuse each, as an argument and as a result.
(define accepted-types
  '(integer-8 unsigned-8 integer-16 unsigned-16 integer-24 unsigned-24
    integer-32 unsigned-32 integer-40 unsigned-40 integer-48 unsigned-48
    integer-56 unsigned-56 unsigned-64 double-float single-float short
    unsigned-short unsigned-int unsigned long unsigned-long long-long
    unsigned-long-long float double char wchar fixnum boolean iptr void*
    u8* u16* u32* utf-8 utf-16le utf-16be utf-32le utf-32be string wstring
    scheme-object ptr size_t ssize_t ptrdiff_t wchar_t
    (* int) (& int) (* unsigned-8) (* uptr) (& uptr)))

;; refused-by-chez-types : (Listof Any)
;; Types Chez itself refuses, and an ftype's bare name: the allowlist refuses
;; them too.
(define refused-by-chez-types
  '(time_t bool sqlite3 (* void) (* sqlite3) (& sqlite3)))

;; --- small helpers ---------------------------------------------------------------------

;; written : Any -> String
(define (written x)
  (guard (e (#t "<unprintable>"))
    (call-with-string-output-port (lambda (p) (write x p)))))

;; starts-with? : String String -> Boolean
(define (starts-with? text prefix)
  (and (>= (string-length text) (string-length prefix))
       (string=? (substring text 0 (string-length prefix)) prefix)))

;; index-of : String String -> (U Natural #f)
;; Where PART first occurs in TEXT.
(define (index-of text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (cond ((> (+ i k) n) #f)
            ((string=? (substring text i (+ i k)) part) i)
            (else (loop (+ i 1)))))))

;; sorted-strings : (Listof String) -> (Listof String)
(define (sorted-strings strings) (list-sort string<? strings))

;; unique : (Listof Any) -> (Listof Any)
;; LST without a later repeat, in order of first appearance.
(define (unique lst)
  (let loop ((rest lst) (seen '()))
    (cond ((null? rest) (reverse seen))
          ((member (car rest) seen) (loop (cdr rest) seen))
          (else (loop (cdr rest) (cons (car rest) seen))))))

;; sorted-symbols : (Listof Symbol) -> (Listof Symbol)
(define (sorted-symbols symbols)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) symbols))

;; checked : (-> Any) -> Any
;; The thunk's answer, or (raised TEXT): a raise is an answer a row can name.
(define (checked thunk)
  (guard (e (#t (list 'raised (describe e))))
    (thunk)))

;; the real table, and the root the fixtures sit under
(define table conventions-table)
(define fixtures "tests/fixtures/conventions")

;; found-in : String Table -> (Listof Violation)
;; The violations of the fixture case CASE against TABLE.
(define (found-in case-name rows)
  (checked (lambda () (violations (string-append fixtures "/" case-name) rows))))

;; rows-named : (Listof String) -> Table
;; The real table's rows of these names, in the table's order.
(define (rows-named names)
  (filter (lambda (row) (member (row-name row) names)) table))

;; synthetic : String (Listof Any) Any -> Row
;; A row that says exactly what a fixture binding says, so that nothing but
;; the allowlist can refuse it.
(define (synthetic name arguments result)
  (list name (list "int" '()) arguments result 'plain '()))

;; with-field : Row Symbol Any -> Row
;; ROW with its convention, arguments or result replaced.
(define (with-field row field value)
  (let ((name (row-name row)) (proto (row-prototype row)) (records (row-records row)))
    (case field
      ((convention) (list name proto (row-arguments row) (row-result row) value records))
      ((arguments) (list name proto value (row-result row) (row-convention row) records))
      (else (list name proto (row-arguments row) value (row-convention row) records)))))

;; replace-row : Table String Row -> Table
(define (replace-row rows name new)
  (map (lambda (row) (if (string=? (row-name row) name) new row)) rows))

;; other-type : Symbol -> Symbol
;; An allowed type that is not T.
(define (other-type t) (if (eq? t 'int) 'uptr 'int))

(define native-file "chez-sqlite3/private/native.sls")

(test-begin "conventions")

;; --- the table ---------------------------------------------------------------------------

(test-equal "table: it has a row for each of M1's 15 entry points, in ADR-0002's order, and no other"
  expected-names
  (map row-name table))

(test-equal "table: every row is (NAME (RESULT (PARAMETER ...)) (ARGUMENT ...) RESULT CONVENTION (RECORD ...)), and its prototype and its argument types have as many parameters"
  '()
  (filter (lambda (row)
            (not (and (list? row) (= (length row) 6)
                      (string? (row-name row))
                      (let ((p (row-prototype row)))
                        (and (list? p) (= (length p) 2) (string? (car p))
                             (list? (cadr p)) (for-all string? (cadr p))
                             (= (length (cadr p)) (length (row-arguments row)))))
                      (list? (row-arguments row)) (for-all symbol? (row-arguments row))
                      (symbol? (row-result row))
                      (memq (row-convention row) '(plain collect-safe))
                      (pair? (row-records row)) (for-all string? (row-records row)))))
          table))

(test-equal "table: sqlite3_open_v2 and sqlite3_close are collect-safe, and every other row is plain (ADR-0011, decision 5)"
  (map (lambda (name) (if (member name collect-safe-names) 'collect-safe 'plain)) expected-names)
  (map row-convention table))

(test-equal "table: the allowlists are int, uptr and integer-64, and void as a result only"
  '((int uptr integer-64) (int uptr integer-64 void))
  (list allowed-argument-types allowed-result-types))

(test-equal "table: the types its rows use are exactly the allowlist's, void aside: no type is allowed that no row uses"
  (sorted-symbols allowed-argument-types)
  (sorted-symbols (unique (append (apply append (map row-arguments table))
                                  (map row-result table)))))

(test-equal "table: no row writes a type its allowlist refuses"
  '()
  (filter (lambda (row)
            (not (and (for-all (lambda (t) (memq t allowed-argument-types)) (row-arguments row))
                      (memq (row-result row) allowed-result-types))))
          table))

;; The records a row cites exist: ADR-NNNN is a file under .plans/decisions.
(define record-files
  (checked (lambda () (directory-list ".plans/decisions"))))

(define (cited-number record)
  (and (starts-with? record "ADR-") (>= (string-length record) 8)
       (substring record 4 8)))

(test-equal "table: every row cites ADR-0011 and ADR-0002, and every record cited is a decision record that exists"
  '()
  (filter
   (lambda (row)
     (let ((numbers (map cited-number (row-records row))))
       (not (and (member "0011" numbers) (member "0002" numbers)
                 (list? record-files)
                 (for-all (lambda (n)
                            (and n (exists (lambda (f) (starts-with? f (string-append n "-")))
                                           record-files)))
                          numbers)))))
   table))

;; --- src/ ----------------------------------------------------------------------------------

(define src-items (checked (lambda () (scan-tree "src"))))

;; form-entry : Pair -> Any
;; The third from the end of (foreign-procedure CONVENTION ... ENTRY (ARGUMENT ...) RESULT).
(define (form-entry form)
  (let ((r (reverse (cdr form))))
    (if (>= (length r) 3) (caddr r) 'no-entry)))

(test-equal "src: every foreign-procedure form under src/ is one of the 15 bindings of (chez-sqlite3 private native), in its one file and its one library, once each"
  (list (list native-file) '((chez-sqlite3 private native)) (sorted-strings expected-names))
  (if (and (list? src-items) (for-all (lambda (i) (eq? (car i) 'binding)) src-items))
      (list (unique (map cadr src-items))
            (unique (map caddr src-items))
            (sorted-strings (map (lambda (i) (let ((e (form-entry (cadddr i)))) (if (string? e) e "?")))
                                 src-items)))
      src-items))

(test-equal "src: no violation: each form is a literal binding held to its row, and each row has its form"
  '()
  (checked (lambda () (violations "src" table))))

;; --- fixtures -------------------------------------------------------------------------------

(test-equal "fixture decoys: the word foreign-procedure in a comment, a string, a quoted symbol, #'foreign-procedure, an import, and the tail of a list is no form; three real forms are, one nested in a let and a lambda, one in a vector"
  '(3 ())
  (let ((items (checked (lambda () (scan-tree (string-append fixtures "/decoys"))))))
    (list (if (list? items) (length items) items)
          (found-in "decoys"
                    (rows-named '("sqlite3_open_v2" "sqlite3_errstr" "sqlite3_memory_used"))))))

(test-equal "fixture plain-open: sqlite3_open_v2 bound plain fails, by name"
  '((mismatch "sqlite3_open_v2" convention collect-safe plain))
  (found-in "plain-open" (rows-named '("sqlite3_open_v2"))))

(test-equal "fixture plain-close: sqlite3_close bound plain fails, by name"
  '((mismatch "sqlite3_close" convention collect-safe plain))
  (found-in "plain-close" (rows-named '("sqlite3_close"))))

(test-equal "fixture safe-other: sqlite3_errmsg bound __collect_safe fails, by name"
  '((mismatch "sqlite3_errmsg" convention plain collect-safe))
  (found-in "safe-other" (rows-named '("sqlite3_errmsg"))))

(test-equal "fixture outside: a form in another library fails, naming the file, the library and the entry"
  '((outside-native "chez-sqlite3/private/other.sls" (chez-sqlite3 private other) "sqlite3_errcode"))
  (found-in "outside" (rows-named '("sqlite3_errcode"))))

(test-equal "fixture outside-no-library: a form in a file that holds no library fails too"
  '((outside-native "chez-sqlite3/stray.sls" #f "sqlite3_errcode"))
  (found-in "outside-no-library" (rows-named '("sqlite3_errcode"))))

(test-equal "fixture entry-not-literal: an entry that is a name, a call, a quoted symbol, a convention, or missing fails, naming each form"
  `((entry-not-literal ,native-file (foreign-procedure entry-name (uptr) int))
    (entry-not-literal ,native-file
                       (foreign-procedure (string-append "sqlite3_" "close") (uptr) int))
    (entry-not-literal ,native-file (foreign-procedure (quote sqlite3_close) (uptr) int))
    (entry-not-literal ,native-file (foreign-procedure __collect_safe (uptr) int))
    (entry-not-literal ,native-file (foreign-procedure)))
  (found-in "entry-not-literal" '()))

(test-equal "fixture types-not-literal: an argument list that is a name, is improper, holds a number or is a vector, and a result that is a string, fail, naming each entry"
  '((types-not-literal "sqlite3_close" argument-types int)
    (types-not-literal "sqlite3_errcode" (uptr . uptr) int)
    (types-not-literal "sqlite3_errmsg" (uptr) "uptr")
    (types-not-literal "sqlite3_errstr" (7) uptr)
    (types-not-literal "sqlite3_next_stmt" #(uptr uptr) uptr))
  (found-in "types-not-literal" '()))

(test-equal "fixture no-row: a binding the table has no row for fails, by name"
  '((no-row "sqlite3_free"))
  (found-in "no-row" '()))

(test-equal "fixture bound-twice: a C name bound twice in one file fails, once, by name"
  '((bound-twice "sqlite3_errcode"))
  (found-in "bound-twice" (rows-named '("sqlite3_errcode"))))

(test-equal "fixture bound-twice-two-files: and bound once in each of two files fails the same"
  '((bound-twice "sqlite3_errcode"))
  (found-in "bound-twice-two-files" (rows-named '("sqlite3_errcode"))))

(test-equal "fixture unreadable: a file the reader cannot read fails, naming the file"
  `((unreadable ,native-file))
  (found-in "unreadable" '()))

(test-equal "fixture positions: a refused type fails at each position: first, middle and last argument, the result, void as an argument; void as a result and integer-64 in every position are allowed"
  '((type-refused "p_first" argument 0 string)
    (type-refused "p_middle" argument 1 string)
    (type-refused "p_last" argument 2 string)
    (type-refused "p_result" result string)
    (type-refused "p_void_argument" argument 0 void))
  (found-in "positions"
            (list (synthetic "p_first" '(string int int) 'int)
                  (synthetic "p_middle" '(int string int) 'int)
                  (synthetic "p_last" '(int int string) 'int)
                  (synthetic "p_result" '(int int int) 'string)
                  (synthetic "p_void_argument" '(void) 'int)
                  (synthetic "p_void_result" '(int) 'void)
                  (synthetic "p_allowed" '(integer-64 int uptr) 'integer-64))))

;; --- rows against the real src/, changed in turn ---------------------------------------------

(test-equal "sweep: a row removed fails, by name, for each of the 15 rows"
  (map (lambda (name) (list (list 'no-row name))) expected-names)
  (map (lambda (name)
         (checked (lambda ()
                    (violations "src" (filter (lambda (row) (not (string=? (row-name row) name)))
                                              table)))))
       expected-names))

(test-equal "sweep: a row with no form fails, by name"
  '((no-form "sqlite3_extra"))
  (checked (lambda ()
             (violations "src" (append table (list (synthetic "sqlite3_extra" '() 'int)))))))

(test-equal "sweep: a row's convention flipped fails, by name, for each of the 15 rows"
  (map (lambda (row)
         (let ((flipped (if (eq? (row-convention row) 'plain) 'collect-safe 'plain)))
           (list (list 'mismatch (row-name row) 'convention flipped (row-convention row)))))
       table)
  (map (lambda (row)
         (let ((flipped (if (eq? (row-convention row) 'plain) 'collect-safe 'plain)))
           (checked (lambda ()
                      (violations "src" (replace-row table (row-name row)
                                                     (with-field row 'convention flipped)))))))
       table))

(test-equal "sweep: a row's result type changed fails, by name, for each of the 15 rows"
  (map (lambda (row)
         (list (list 'mismatch (row-name row) 'result (other-type (row-result row)) (row-result row))))
       (filter (lambda (row) (memq (row-result row) '(int uptr))) table))
  (map (lambda (row)
         (checked (lambda ()
                    (violations "src" (replace-row table (row-name row)
                                                   (with-field row 'result (other-type (row-result row))))))))
       (filter (lambda (row) (memq (row-result row) '(int uptr))) table)))

(test-equal "sweep: sqlite3_memory_used's result, integer-64, changed to int fails, by name"
  '((mismatch "sqlite3_memory_used" result int integer-64))
  (checked (lambda ()
             (violations "src" (replace-row table "sqlite3_memory_used"
                                            (with-field (car (rows-named '("sqlite3_memory_used")))
                                                        'result 'int))))))

;; every argument of every row, changed at its own position
(define argument-cases
  (apply append
         (map (lambda (row)
                (let loop ((i 0) (found '()))
                  (if (= i (length (row-arguments row)))
                      (reverse found)
                      (loop (+ i 1)
                            (cons (list row i
                                        (let swap ((rest (row-arguments row)) (j 0))
                                          (cond ((null? rest) '())
                                                ((= j i) (cons (other-type (car rest)) (cdr rest)))
                                                (else (cons (car rest) (swap (cdr rest) (+ j 1)))))))
                                  found)))))
              table)))

(test-equal "sweep: a row's argument type changed at each position fails, by name, for each of the 13 arguments"
  (list 13
        (map (lambda (c)
               (list (list 'mismatch (row-name (car c)) 'arguments (caddr c) (row-arguments (car c)))))
             argument-cases))
  (list (length argument-cases)
        (map (lambda (c)
               (checked (lambda ()
                          (violations "src" (replace-row table (row-name (car c))
                                                         (with-field (car c) 'arguments (caddr c)))))))
             argument-cases)))

;; --- the allowlist, against its whole complement --------------------------------------------

;; Chez itself is asked: each type of the complement must be one it accepts,
;; as an argument and as a result, so the list is the foreign types Chez 10.4
;; takes and not a guess. A control, a type Chez refuses, is refused.
(define libc-loaded
  (checked (lambda ()
             (load-shared-object (if (memq (machine-type) '(ta6le tarm64le))
                                     "libc.so.6"
                                     "libSystem.B.dylib"))
             'loaded)))

(define (chez-takes? type position)
  (guard (e (#t 'refused))
    (eval (if (eq? position 'argument)
              `(foreign-procedure "getpid" (,type) int)
              `(foreign-procedure "getpid" () ,type))
          (environment '(chezscheme)))
    'accepted))

(test-equal "complement: libc loaded, for Chez to resolve an entry point to ask about"
  'loaded libc-loaded)

(test-equal "complement: Chez accepts each type as an argument, and refuses the control"
  '(() refused)
  (list (filter (lambda (t) (not (eq? (chez-takes? t 'argument) 'accepted))) accepted-types)
        (chez-takes? 'not-a-type 'argument)))

(test-equal "complement: Chez accepts each type as a result, and refuses the control"
  '(() refused)
  (list (filter (lambda (t) (not (eq? (chez-takes? t 'result) 'accepted))) accepted-types)
        (chez-takes? 'not-a-type 'result)))

(test-equal "complement: Chez refuses the types the list adds, so the two lists are apart"
  '()
  (filter (lambda (t) (eq? (chez-takes? t 'argument) 'accepted)) '(time_t bool (* void))))

(test-equal "complement: none of the types is one the allowlist allows"
  '()
  (filter (lambda (t) (or (memq t allowed-argument-types) (memq t allowed-result-types)))
          (append accepted-types refused-by-chez-types)))

;; The fixture binds each type, as the one argument of fx_argument_N and as
;; the result of fx_result_N, and void as an argument of fx_void_argument.
(define complement (append accepted-types refused-by-chez-types))

(define complement-rows
  (let loop ((rest complement) (i 0) (rows '()))
    (if (null? rest)
        (reverse (cons (synthetic "fx_void_argument" '(void) 'int) rows))
        (loop (cdr rest) (+ i 1)
              (cons (synthetic (string-append "fx_result_" (number->string i)) '() (car rest))
                    (cons (synthetic (string-append "fx_argument_" (number->string i))
                                     (list (car rest)) 'int)
                          rows))))))

(define complement-refusals
  (let loop ((rest complement) (i 0) (found '()))
    (if (null? rest)
        (reverse (cons '(type-refused "fx_void_argument" argument 0 void) found))
        (loop (cdr rest) (+ i 1)
              (cons (list 'type-refused (string-append "fx_result_" (number->string i)) 'result (car rest))
                    (cons (list 'type-refused (string-append "fx_argument_" (number->string i))
                                'argument 0 (car rest))
                          found))))))

(test-equal "complement: the fixture binds every type, each row says exactly what its binding says, and the allowlist refuses every one, as an argument and as a result, and void as an argument"
  complement-refusals
  (found-in "types" complement-rows))

(test-end "conventions")

(exit (suite-exit-status runner))
