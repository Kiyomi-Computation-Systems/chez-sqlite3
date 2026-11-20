#!r6rs
;;; The convention suite (ADR-0011): every foreign-procedure form
;;; under src/, read as data, held to a table with one row per binding. It
;;; never loads libsqlite3. tests/test-constants.sps holds each row's C
;;; prototype to sqlite3.h, and the map from its C types to its Chez types.
;;;
;;;   the table      written-out names and conventions, so a table loosened
;;;                  with the binding it holds still fails; each row's shape;
;;;                  every cited record exists; the allowlists, written out,
;;;                  are the types the table uses and void as a result; its
;;;                  names are (library-loading)'s every-entry, the required
;;;                  entry points, then its optional-entries, whole and in
;;;                  order, and the optional rows alone say so
;;;   conventions    convention-of reads exactly nothing as plain,
;;;                  __collect_safe alone as collect-safe, and the list of
;;;                  __varargs_after and 2 alone as variadic; anything else,
;;;                  a count of 3 and __collect_safe beside the count among
;;;                  it, as other, which no row holds
;;;   src/           no violation, and the 44 forms are all native's
;;;   fixtures       tests/fixtures/conventions/<case>/, each the one fault it
;;;                  names, and the whole list of violations asserted: a form
;;;                  outside native, an entry that is no string literal, type
;;;                  lists that are not literal, a plain open or close, a
;;;                  collect-safe anything else, a form with no row, a row
;;;                  with no form, a C name bound twice, a file that cannot be
;;;                  read, words that are no form, and the symbol
;;;                  foreign-procedure anywhere but a form's head, the import
;;;                  entry and one fender each of bind-required and
;;;                  bind-optional: a stray reference; sqlite3_db_config bound
;;;                  plain, with a count of 3, with __collect_safe beside its
;;;                  count either way, and the count's words written bare;
;;;                  sqlite3_load_extension bound plain through bind-optional
;;;                  and sqlite3_free bound __collect_safe
;;;   sweeps         each row of the table, changed in each field in turn,
;;;                  held against the real src/; each row removed in turn
;;;   the allowlist  against its whole complement: every type Chez 10.4
;;;                  accepts that the table does not use, each in a fixture
;;;                  binding as an argument and as a result, and each type the
;;;                  table uses as an argument alone, bound as a result; the
;;;                  suite asks Chez itself that each is accepted
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
        (foreign-conventions)
        (only (library-loading) every-entry optional-entries))

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
;; ADR-0002's order: the report's three, the threadsafe answer,
;; sqlite3_initialize, then the rest of the first required list, then the
;; statement tier's 21, then the five of the change counters, autocommit and
;; interrupt, then the two required and one optional of the settings and
;; extension calls (ADR-0002).
(define expected-names
  '("sqlite3_libversion_number" "sqlite3_libversion" "sqlite3_sourceid"
    "sqlite3_threadsafe" "sqlite3_initialize"
    "sqlite3_compileoption_used" "sqlite3_compileoption_get"
    "sqlite3_open_v2" "sqlite3_close" "sqlite3_errmsg" "sqlite3_errstr"
    "sqlite3_errcode" "sqlite3_extended_errcode" "sqlite3_next_stmt"
    "sqlite3_memory_used"
    "sqlite3_prepare_v3" "sqlite3_finalize" "sqlite3_step" "sqlite3_reset"
    "sqlite3_clear_bindings" "sqlite3_bind_parameter_count" "sqlite3_bind_parameter_index"
    "sqlite3_bind_null" "sqlite3_bind_int64" "sqlite3_bind_double" "sqlite3_bind_text64"
    "sqlite3_bind_blob64" "sqlite3_column_count" "sqlite3_column_name" "sqlite3_column_type"
    "sqlite3_column_int64" "sqlite3_column_double" "sqlite3_column_text" "sqlite3_column_blob"
    "sqlite3_column_bytes" "sqlite3_error_offset"
    "sqlite3_changes64" "sqlite3_total_changes64" "sqlite3_last_insert_rowid"
    "sqlite3_get_autocommit" "sqlite3_interrupt"
    "sqlite3_db_config" "sqlite3_free" "sqlite3_load_extension"))

;; collect-safe-names : (Listof String)
;; The calls that can block (ADR-0011): open and close, prepare, step, reset
;; and finalize, and the extension load. The one variadic binding is
;; sqlite3_db_config's. Every other is plain.
(define collect-safe-names
  '("sqlite3_open_v2" "sqlite3_close"
    "sqlite3_prepare_v3" "sqlite3_finalize" "sqlite3_step" "sqlite3_reset"
    "sqlite3_load_extension"))

(define variadic-names '("sqlite3_db_config"))

;; optional-names : (Listof String)
;; The entry points a library may lack, and native binds by bind-optional
;; (ADR-0002).
(define optional-names '("sqlite3_load_extension"))

;; accepted-types : (Listof Any)
;; Every foreign type Chez 10.4 accepts (CSUG 4.2) that the table does not
;; use. The allowlist must refuse each, as an argument and as a result.
(define accepted-types
  '(integer-8 integer-16 unsigned-16 integer-24 unsigned-24
    integer-32 unsigned-32 integer-40 unsigned-40 integer-48 unsigned-48
    integer-56 unsigned-56 double-float single-float short
    unsigned-short unsigned long unsigned-long long-long
    unsigned-long-long float char wchar fixnum boolean iptr void*
    u8* u16* u32* utf-8 utf-16le utf-16be utf-32le utf-32be string wstring
    scheme-object ptr size_t ssize_t ptrdiff_t wchar_t
    (* int) (& int) (* unsigned-8) (* uptr) (& uptr)))

;; argument-only-types : (Listof Symbol)
;; The types the table writes as an argument and never as a result: the
;; result allowlist must refuse each.
(define argument-only-types '(unsigned-int unsigned-64 unsigned-8))

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

;; list-head-of : (Listof Any) Natural -> (Listof Any)
;; The first N elements of LST.
(define (list-head-of lst n)
  (if (or (= n 0) (null? lst)) '() (cons (car lst) (list-head-of (cdr lst) (- n 1)))))

;; flipped : Symbol -> Symbol
;; Another convention than C: plain's is collect-safe, and every other's,
;; collect-safe's and variadic's, plain.
(define (flipped c) (if (eq? c 'plain) 'collect-safe 'plain))

;; named-parameters : (Listof String) -> (Listof String)
;; A prototype's parameters before a closing "...": all of them for a
;; function that is not variadic.
(define (named-parameters parameters)
  (if (and (pair? parameters) (equal? (list-ref parameters (- (length parameters) 1)) "..."))
      (reverse (cdr (reverse parameters)))
      parameters))

;; variadic-prototype? : (Listof String) -> Boolean
(define (variadic-prototype? parameters)
  (not (= (length (named-parameters parameters)) (length parameters))))

(define native-file "chez-sqlite3/private/native.sls")

(test-begin "conventions")

;; --- the table ---------------------------------------------------------------------------

(test-equal "table: it has a row for each of M1's 15 entry points, M2's 21, M3's five and M4's three, in ADR-0002's order, and no other"
  expected-names
  (map row-name table))

;; (library-loading)'s every-entry is what the pattern of four deals and
;; missing-api-rows makes a row for, the required entry points alone, and
;; optional-entries follows it. Held whole and in order, as merge-halves'
;; row holds the parts: an optional entry point joined to every-entry would
;; be dealt a missing-api row for a library that must load.
(test-equal "table: its names are (library-loading)'s every-entry, the 43 required entry points, then its optional-entries, sqlite3_load_extension, whole and in order"
  (list (map row-name table) 43 '("sqlite3_load_extension"))
  (list (append every-entry optional-entries) (length every-entry) optional-entries))

(test-equal "table: every row is (NAME (RESULT (PARAMETER ...)) (ARGUMENT ...) RESULT CONVENTION (RECORD ...)); its argument types are as many as its prototype's parameters, or, for a prototype that ends \"...\", more than the parameters before it"
  '()
  (filter (lambda (row)
            (not (and (list? row) (= (length row) 6)
                      (string? (row-name row))
                      (let ((p (row-prototype row)))
                        (and (list? p) (= (length p) 2) (string? (car p))
                             (list? (cadr p)) (for-all string? (cadr p))
                             (if (variadic-prototype? (cadr p))
                                 (< (length (named-parameters (cadr p))) (length (row-arguments row)))
                                 (= (length (cadr p)) (length (row-arguments row))))))
                      (list? (row-arguments row)) (for-all symbol? (row-arguments row))
                      (symbol? (row-result row))
                      (memq (row-convention row) '(plain collect-safe variadic))
                      (pair? (row-records row)) (for-all string? (row-records row)))))
          table))

(test-equal "table: sqlite3_open_v2, sqlite3_close, sqlite3_prepare_v3, sqlite3_finalize, sqlite3_step, sqlite3_reset and sqlite3_load_extension are collect-safe, sqlite3_db_config alone is variadic, and every other row is plain (ADR-0011, decision 5, amended; ADR-0021, decision 4)"
  (map (lambda (name)
         (cond ((member name collect-safe-names) 'collect-safe)
               ((member name variadic-names) 'variadic)
               (else 'plain)))
       expected-names)
  (map row-convention table))

;; ADR-0002: the optional entry point's row says it is optional, and no
;; required one's does. The words, not "optional" alone, which
;; "bind-optional" holds too.
(test-equal "table: the rows whose records say \"an optional entry point\" are exactly the optional entry points', sqlite3_load_extension's"
  optional-names
  (map row-name
       (filter (lambda (row)
                 (exists (lambda (record) (index-of record "an optional entry point"))
                         (row-records row)))
               table)))

(test-equal "table: the allowlists are int, uptr, integer-64, unsigned-int, double, unsigned-64 and unsigned-8 as arguments, and int, uptr, integer-64, double and void as results"
  '((int uptr integer-64 unsigned-int double unsigned-64 unsigned-8)
    (int uptr integer-64 double void))
  (list allowed-argument-types allowed-result-types))

(test-equal "table: the types its rows use are exactly the allowlists': every type an argument or a result, but void, is the argument allowlist, and every result, and void, the result allowlist; no type is allowed that no row uses"
  (list (sorted-symbols allowed-argument-types) (sorted-symbols allowed-result-types))
  ;; void is a result only, so it joins the argument side never
  ;; (sqlite3_interrupt is the first row to write it).
  (list (sorted-symbols (unique (append (apply append (map row-arguments table))
                                        (filter (lambda (t) (not (eq? t 'void)))
                                                (map row-result table)))))
        (sorted-symbols (unique (cons 'void (map row-result table))))))

(test-equal "table: the types only an argument uses are unsigned-int, unsigned-64 and unsigned-8, which the result allowlist refuses"
  (list (sorted-symbols argument-only-types) '())
  (list (sorted-symbols (filter (lambda (t) (not (memq t (map row-result table))))
                                (unique (apply append (map row-arguments table)))))
        (filter (lambda (t) (memq t allowed-result-types)) argument-only-types)))

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

;; --- conventions --------------------------------------------------------------------------

;; Written out, so a reader loosened with its table still fails.
(test-equal "conventions: plain is nothing before the entry, collect-safe is __collect_safe alone, and variadic is the list of __varargs_after and 2 alone"
  '((plain) (collect-safe __collect_safe) (variadic (__varargs_after 2)))
  convention-forms)

(test-equal "conventions: convention-of reads nothing as plain, __collect_safe alone as collect-safe, and the list of __varargs_after and 2 alone as variadic"
  '(plain collect-safe variadic)
  (map convention-of '(() (__collect_safe) ((__varargs_after 2)))))

(test-equal "conventions: convention-of reads anything else as other, whole: a count of 3, of 1 or of 0, __collect_safe on either side of the count of 2, the count's two words bare, the count twice, the count written \"2\", a convention unknown, and __collect_safe twice"
  '((other (__varargs_after 3)) (other (__varargs_after 1)) (other (__varargs_after 0))
    (other __collect_safe (__varargs_after 2)) (other (__varargs_after 2) __collect_safe)
    (other __varargs_after 2) (other (__varargs_after 2) (__varargs_after 2))
    (other (__varargs_after "2")) (other __collect_unsafe) (other __collect_safe __collect_safe))
  (map convention-of '(((__varargs_after 3)) ((__varargs_after 1)) ((__varargs_after 0))
                       (__collect_safe (__varargs_after 2)) ((__varargs_after 2) __collect_safe)
                       (__varargs_after 2) ((__varargs_after 2) (__varargs_after 2))
                       ((__varargs_after "2")) (__collect_unsafe) (__collect_safe __collect_safe))))

;; --- src/ ----------------------------------------------------------------------------------

(define src-items (checked (lambda () (scan-tree "src"))))

;; form-entry : Pair -> Any
;; The third from the end of (foreign-procedure CONVENTION ... ENTRY (ARGUMENT ...) RESULT).
(define (form-entry form)
  (let ((r (reverse (cdr form))))
    (if (>= (length r) 3) (caddr r) 'no-entry)))

(test-equal "src: every foreign-procedure form under src/ is one of the 44 bindings of (chez-sqlite3 private native), in its one file and its one library, once each"
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

(test-equal "fixture decoys: the word foreign-procedure in a comment, a string, #'foreign-procedure outside bind-required, a quoted symbol, the tail of a list and an import is no form; three real forms are, one nested in a let and a lambda, one in a vector; and the three uses that are no form, the syntax mention, the quoted symbol and the list's last element, are stray references, the import's entry not"
  `(3 ((stray-reference ,native-file) (stray-reference ,native-file) (stray-reference ,native-file)))
  (let ((items (checked (lambda () (scan-tree (string-append fixtures "/decoys"))))))
    (list (if (list? items) (length items) items)
          (found-in "decoys"
                    (rows-named '("sqlite3_open_v2" "sqlite3_errstr" "sqlite3_memory_used"))))))

;; A stray reference: the symbol where no form is headed by it, so that the
;; bindings it could make are unseen. Each fixture is the one fault it names,
;; with no row to answer for a binding.
(test-equal "fixture stray-alias: a keyword alias, (define-syntax fp (identifier-syntax foreign-procedure)), and a binding through it, fail, by file"
  `((stray-reference ,native-file))
  (found-in "stray-alias" '()))

(test-equal "fixture stray-define: (define fp foreign-procedure) fails, by file"
  `((stray-reference ,native-file))
  (found-in "stray-define" '()))

(test-equal "fixture stray-quoted: the symbol in a quoted list fails, by file"
  `((stray-reference ,native-file))
  (found-in "stray-quoted" '()))

(test-equal "fixture stray-syntax: a second (syntax foreign-procedure), in bind-required's fender, fails; the first, the import entry and the form's head do not"
  `((stray-reference ,native-file))
  (found-in "stray-syntax" (rows-named '("sqlite3_errcode"))))

(test-equal "fixture stray-other-macro: a (syntax foreign-procedure) in the fender of a macro that is not bind-required fails"
  `((stray-reference ,native-file))
  (found-in "stray-other-macro" (rows-named '("sqlite3_errcode"))))

(test-equal "fixture permitted: the import entry, bind-required's one fender mention and a form's head are all there is, and nothing fails"
  '()
  (found-in "permitted" (rows-named '("sqlite3_errcode"))))

(test-equal "fixture permitted-optional: bind-required's and bind-optional's one fender mention each, the import entry and two forms' heads, and nothing fails"
  '()
  (found-in "permitted-optional" (rows-named '("sqlite3_errcode" "sqlite3_load_extension"))))

(test-equal "fixture stray-optional-syntax: a second (syntax foreign-procedure) in bind-optional's fender fails, though no bind-required is there to have used its allowance"
  `((stray-reference ,native-file))
  (found-in "stray-optional-syntax" (rows-named '("sqlite3_load_extension"))))

(test-equal "fixture plain-open: sqlite3_open_v2 bound plain fails, by name"
  '((mismatch "sqlite3_open_v2" convention collect-safe plain))
  (found-in "plain-open" (rows-named '("sqlite3_open_v2"))))

(test-equal "fixture plain-close: sqlite3_close bound plain fails, by name"
  '((mismatch "sqlite3_close" convention collect-safe plain))
  (found-in "plain-close" (rows-named '("sqlite3_close"))))

(test-equal "fixture safe-other: sqlite3_errmsg bound __collect_safe fails, by name"
  '((mismatch "sqlite3_errmsg" convention plain collect-safe))
  (found-in "safe-other" (rows-named '("sqlite3_errmsg"))))

(test-equal "fixture variadic: sqlite3_db_config bound as the M4 plan's section 4.2 writes it, the count of 2 before its entry, holds to its row"
  '()
  (found-in "variadic" (rows-named '("sqlite3_db_config"))))

(test-equal "fixture variadic-plain: sqlite3_db_config bound plain fails, by name: what check-variadic's mutant must show"
  '((mismatch "sqlite3_db_config" convention variadic plain))
  (found-in "variadic-plain" (rows-named '("sqlite3_db_config"))))

(test-equal "fixture variadic-3: sqlite3_db_config bound with a count of 3 fails, by name, the count read whole"
  '((mismatch "sqlite3_db_config" convention variadic (other (__varargs_after 3))))
  (found-in "variadic-3" (rows-named '("sqlite3_db_config"))))

(test-equal "fixture variadic-safe: sqlite3_db_config bound __collect_safe beside its count fails, by name"
  '((mismatch "sqlite3_db_config" convention variadic (other __collect_safe (__varargs_after 2))))
  (found-in "variadic-safe" (rows-named '("sqlite3_db_config"))))

(test-equal "fixture variadic-safe-after: and with __collect_safe after the count, the same"
  '((mismatch "sqlite3_db_config" convention variadic (other (__varargs_after 2) __collect_safe)))
  (found-in "variadic-safe-after" (rows-named '("sqlite3_db_config"))))

(test-equal "fixture variadic-bare: the count's words written bare fail, and the count twice, on another binding, fails against its plain row"
  '((mismatch "sqlite3_db_config" convention variadic (other __varargs_after 2))
    (mismatch "sqlite3_errcode" convention plain (other (__varargs_after 2) (__varargs_after 2))))
  (found-in "variadic-bare" (rows-named '("sqlite3_db_config" "sqlite3_errcode"))))

(test-equal "fixture load-plain: sqlite3_load_extension bound plain through bind-optional is read as bind-required's forms are, and fails, by name"
  '((mismatch "sqlite3_load_extension" convention collect-safe plain))
  (found-in "load-plain" (rows-named '("sqlite3_load_extension"))))

(test-equal "fixture free-safe: sqlite3_free bound __collect_safe fails, by name"
  '((mismatch "sqlite3_free" convention plain collect-safe))
  (found-in "free-safe" (rows-named '("sqlite3_free"))))

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

(test-equal "sweep: a row removed fails, by name, for each of the 44 rows"
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

(test-equal "sweep: a row's convention flipped fails, by name, for each of the 44 rows: plain to collect-safe, and collect-safe and variadic to plain"
  (map (lambda (row)
         (list (list 'mismatch (row-name row) 'convention (flipped (row-convention row))
                     (row-convention row))))
       table)
  (map (lambda (row)
         (checked (lambda ()
                    (violations "src" (replace-row table (row-name row)
                                                   (with-field row 'convention
                                                               (flipped (row-convention row))))))))
       table))

(test-equal "sweep: sqlite3_db_config's row made plain, and made collect-safe, each fails, by name, against the real src/"
  '(((mismatch "sqlite3_db_config" convention plain variadic))
    ((mismatch "sqlite3_db_config" convention collect-safe variadic)))
  (map (lambda (c)
         (checked (lambda ()
                    (violations "src" (replace-row table "sqlite3_db_config"
                                                   (with-field (car (rows-named '("sqlite3_db_config")))
                                                               'convention c))))))
       '(plain collect-safe)))

(test-equal "sweep: a row's result type changed fails, by name, for each of the 44 rows: int to uptr, and uptr, integer-64, double and void to int"
  (list 44
        (map (lambda (row)
               (list (list 'mismatch (row-name row) 'result (other-type (row-result row)) (row-result row))))
             table))
  (list (length table)
        (map (lambda (row)
               (checked (lambda ()
                          (violations "src" (replace-row table (row-name row)
                                                         (with-field row 'result (other-type (row-result row))))))))
             table)))

(test-equal "sweep: sqlite3_memory_used's and sqlite3_column_int64's results, integer-64, and sqlite3_bind_int64's third argument, changed to int, each fail, by name (the M2 plan, section 4.8)"
  '(((mismatch "sqlite3_memory_used" result int integer-64))
    ((mismatch "sqlite3_column_int64" result int integer-64))
    ((mismatch "sqlite3_bind_int64" arguments (uptr int int) (uptr int integer-64))))
  (list (checked (lambda ()
                   (violations "src" (replace-row table "sqlite3_memory_used"
                                                  (with-field (car (rows-named '("sqlite3_memory_used")))
                                                              'result 'int)))))
        (checked (lambda ()
                   (violations "src" (replace-row table "sqlite3_column_int64"
                                                  (with-field (car (rows-named '("sqlite3_column_int64")))
                                                              'result 'int)))))
        (checked (lambda ()
                   (violations "src" (replace-row table "sqlite3_bind_int64"
                                                  (with-field (car (rows-named '("sqlite3_bind_int64")))
                                                              'arguments '(uptr int int))))))))

;; The change counters, autocommit and interrupt calls, written out, so that a table
;; loosened with the bindings it holds still fails. Each takes a handle, a uptr. The three
;; counters answer sqlite3_int64, get_autocommit an int and the interrupt void, and none
;; can block, so each is plain (ADR-0011).
(define m3-five
  '(("sqlite3_changes64" (uptr) integer-64 plain)
    ("sqlite3_total_changes64" (uptr) integer-64 plain)
    ("sqlite3_last_insert_rowid" (uptr) integer-64 plain)
    ("sqlite3_get_autocommit" (uptr) int plain)
    ("sqlite3_interrupt" (uptr) void plain)))

(test-equal "table: M3's five are written out: a handle each; sqlite3_int64 for the three counters, int for sqlite3_get_autocommit and void for sqlite3_interrupt; all five plain, never __collect_safe (ADR-0011, decision 5, M3 amendment)"
  m3-five
  (map (lambda (name)
         (let ((row (car (rows-named (list name)))))
           (list name (row-arguments row) (row-result row) (row-convention row))))
       (map car m3-five)))

(test-equal "table: M3's five follow M2's sqlite3_error_offset, in ADR-0002's M3 order, at 36 to 40"
  (list "sqlite3_error_offset" (map car m3-five))
  (let ((names (map row-name table)))
    (list (list-ref names 35)
          (map (lambda (i) (list-ref names i)) '(36 37 38 39 40)))))

(test-equal "sweep: M3's five made __collect_safe each fail, by name: a binding that held the lock-free counters or the interrupt through a collection would let another thread's collection wait on them"
  (map (lambda (entry) (list (list 'mismatch (car entry) 'convention 'collect-safe 'plain)))
       m3-five)
  (map (lambda (entry)
         (checked (lambda ()
                    (violations "src" (replace-row table (car entry)
                                                   (with-field (car (rows-named (list (car entry))))
                                                               'convention 'collect-safe))))))
       m3-five))

(test-equal "sweep: sqlite3_changes64's, sqlite3_total_changes64's and sqlite3_last_insert_rowid's results, integer-64, changed to int, sqlite3_get_autocommit's, int, changed to integer-64, and sqlite3_interrupt's, void, changed to int, each fail, by name"
  '(((mismatch "sqlite3_changes64" result int integer-64))
    ((mismatch "sqlite3_total_changes64" result int integer-64))
    ((mismatch "sqlite3_last_insert_rowid" result int integer-64))
    ((mismatch "sqlite3_get_autocommit" result integer-64 int))
    ((mismatch "sqlite3_interrupt" result int void)))
  (map (lambda (plant)
         (checked (lambda ()
                    (violations "src" (replace-row table (car plant)
                                                   (with-field (car (rows-named (list (car plant))))
                                                               'result (cdr plant)))))))
       '(("sqlite3_changes64" . int) ("sqlite3_total_changes64" . int)
         ("sqlite3_last_insert_rowid" . int) ("sqlite3_get_autocommit" . integer-64)
         ("sqlite3_interrupt" . int))))

;; The last three, written out (ADR-0021): sqlite3_db_config in the shape (db
;; op int int*), variadic and plain; sqlite3_free of a pointer, plain;
;; sqlite3_load_extension of a handle, a path, an entry point and a message's
;; slot, __collect_safe.
(define m4-three
  '(("sqlite3_db_config" (uptr int int uptr) int variadic)
    ("sqlite3_free" (uptr) void plain)
    ("sqlite3_load_extension" (uptr uptr uptr uptr) int collect-safe)))

(test-equal "table: M4's three are written out: sqlite3_db_config in the shape (db op int int*), answering int, variadic; sqlite3_free of a pointer, answering void, plain; sqlite3_load_extension of four pointers, answering int, collect-safe"
  m4-three
  (map (lambda (name)
         (let ((row (car (rows-named (list name)))))
           (list name (row-arguments row) (row-result row) (row-convention row))))
       (map car m4-three)))

(test-equal "table: M4's three are the last three rows, after M3's sqlite3_interrupt, the two required before the optional one"
  (list "sqlite3_interrupt" (map car m4-three))
  (let ((names (map row-name table)))
    (list (list-ref names 40) (list-tail names 41))))

(test-equal "table: sqlite3_db_config's prototype is int (sqlite3*, int, ...), as sqlite3.h writes it, its two named parameters the leading two of its four argument types"
  '(("int" ("sqlite3*" "int" "...")) (uptr int))
  (let ((row (car (rows-named '("sqlite3_db_config")))))
    (list (row-prototype row) (list-head-of (row-arguments row) 2))))

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

(test-equal "sweep: a row's argument type changed at each position fails, by name, for each of the 75 arguments"
  (list 75
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

(test-equal "complement: Chez accepts each type as a result, and each type the table uses as an argument alone, and refuses the control"
  '(() refused)
  (list (filter (lambda (t) (not (eq? (chez-takes? t 'result) 'accepted)))
                (append accepted-types argument-only-types))
        (chez-takes? 'not-a-type 'result)))

(test-equal "complement: Chez refuses the types the list adds, so the two lists are apart"
  '()
  (filter (lambda (t) (eq? (chez-takes? t 'argument) 'accepted)) '(time_t bool (* void))))

(test-equal "complement: none of the types is one the allowlist allows"
  '()
  (filter (lambda (t) (or (memq t allowed-argument-types) (memq t allowed-result-types)))
          (append accepted-types refused-by-chez-types)))

;; The fixture binds each type, as the one argument of fx_argument_N and as
;; the result of fx_result_N; then each type of argument-only-types as the
;; result of fx_result_only_K; and void as an argument of fx_void_argument.
(define complement (append accepted-types refused-by-chez-types))

;; result-only : (Listof (Pairof String Symbol))
;; fx_result_only_K and its type, for each of argument-only-types.
(define result-only
  (let loop ((rest argument-only-types) (k 0) (found '()))
    (if (null? rest)
        (reverse found)
        (loop (cdr rest) (+ k 1)
              (cons (cons (string-append "fx_result_only_" (number->string k)) (car rest)) found)))))

(define complement-rows
  (let loop ((rest complement) (i 0) (rows '()))
    (if (null? rest)
        (append (reverse rows)
                (map (lambda (entry) (synthetic (car entry) '() (cdr entry))) result-only)
                (list (synthetic "fx_void_argument" '(void) 'int)))
        (loop (cdr rest) (+ i 1)
              (cons (synthetic (string-append "fx_result_" (number->string i)) '() (car rest))
                    (cons (synthetic (string-append "fx_argument_" (number->string i))
                                     (list (car rest)) 'int)
                          rows))))))

(define complement-refusals
  (let loop ((rest complement) (i 0) (found '()))
    (if (null? rest)
        (append (reverse found)
                (map (lambda (entry) (list 'type-refused (car entry) 'result (cdr entry))) result-only)
                (list '(type-refused "fx_void_argument" argument 0 void)))
        (loop (cdr rest) (+ i 1)
              (cons (list 'type-refused (string-append "fx_result_" (number->string i)) 'result (car rest))
                    (cons (list 'type-refused (string-append "fx_argument_" (number->string i))
                                'argument 0 (car rest))
                          found))))))

(test-equal "complement: the fixture binds every type, each row says exactly what its binding says, and the allowlist refuses every one, as an argument and as a result, each type the table uses as an argument alone as a result, and void as an argument"
  (list 116 complement-refusals)
  (list (length complement-refusals) (found-in "types" complement-rows)))

(test-end "conventions")

(exit (suite-exit-status runner))
