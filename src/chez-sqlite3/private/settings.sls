#!r6rs
;;; (chez-sqlite3 private settings): the pure core of the settings list that
;;; open-database and call-with-database take (ADR-0018). Data in, data out:
;;; no foreign code, and nothing here loads libsqlite3.
;;;
;;;   split-open-arguments  open's arguments after the filename: the options,
;;;                         for parse-open-options, and at most one settings
;;;                         list
;;;   settings-plan         a settings list checked by ADR-0018's rules: the
;;;                         statement cache's capacity, and each of SQLite's
;;;                         settings as the SQL that sets it, the SQL that
;;;                         reads it back and the value expected back; or
;;;                         the rule that refuses it
;;;   raise-setting-refusal a refusal as an assertion violation, its
;;;                         irritants led by the rule's symbol
;;;   read-back-value       a read-back's value as the Scheme value compared
;;;   read-back-comparison  a match, or the mismatch's setting, expected and
;;;                         actual, for slice 5 to raise
;;;
;;; The table (ADR-0018, decision 3), each value written as canonical SQL from
;;; the words below and decimal integers alone, so no text of the caller's
;;; reaches SQL:
;;;
;;;   setting          Scheme value                 written   read back
;;;   busy-timeout     exact integer, 0 to 2^31-1   decimal   INTEGER
;;;   foreign-keys     #t or #f                     1 or 0    INTEGER
;;;   journal-mode     delete truncate persist wal  the word  lower-case TEXT
;;;   synchronous      off normal full extra        0 to 3    INTEGER
;;;   temp-store       default file memory          0 to 2    INTEGER
;;;   trusted-schema   #t or #f                     1 or 0    INTEGER
;;;   statement-cache  exact integer, 0 to 1024;    never: the library's own,
;;;                    32 when absent               the cache's capacity
;;;
;;; Each procedure but raise-setting-refusal answers data for any argument and
;;; raises nothing, so slice 5 may call any of them inside a critical section;
;;; raise-setting-refusal is called after it.
(library (chez-sqlite3 private settings)
  (export setting-names setting-refusal-rules split-open-arguments settings-plan
          raise-setting-refusal read-back-value read-back-comparison)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (only (chez-sqlite3 private conditions) shown-value))

  ;; setting-names : (Listof Symbol)
  ;; Every setting the list takes, in ADR-0018's table order.
  (define setting-names
    '(busy-timeout foreign-keys journal-mode synchronous temp-store trusted-schema statement-cache))

  ;; setting-refusal-rules : (Listof Symbol)
  ;; The rules a settings list is refused by (ADR-0018, decision 2):
  ;;
  ;;   second-settings-list     open's arguments hold a second list
  ;;   not-an-association-list  the list is no list of pairs whose cars are
  ;;                            symbols: an improper or cyclic list, an
  ;;                            entry that is no pair, a name that is no symbol
  ;;   unknown-setting          a name setting-names does not hold
  ;;   setting-given-twice      a name given before in the same list
  ;;   setting-out-of-domain    a value outside its setting's domain
  (define setting-refusal-rules
    '(second-settings-list not-an-association-list unknown-setting setting-given-twice
      setting-out-of-domain))

  ;; largest-busy-timeout : Natural
  (define largest-busy-timeout (- (expt 2 31) 1))

  ;; largest-statement-cache, default-statement-cache : Natural
  (define largest-statement-cache 1024)
  (define default-statement-cache 32)

  ;; enumerated-settings : (Listof (List Symbol String (Listof (List Any String Any))))
  ;; Each of SQLite's settings with a fixed set of values: its name, its
  ;; PRAGMA, and each value as (scheme-value sql-text read-back), the
  ;; read-back as M2's column-value answers it, an exact integer or a string.
  (define enumerated-settings
    '((foreign-keys "foreign_keys" ((#t "1" 1) (#f "0" 0)))
      (journal-mode "journal_mode" ((delete "delete" "delete") (truncate "truncate" "truncate")
                                    (persist "persist" "persist") (wal "wal" "wal")))
      (synchronous "synchronous" ((off "0" 0) (normal "1" 1) (full "2" 2) (extra "3" 3)))
      (temp-store "temp_store" ((default "0" 0) (file "1" 1) (memory "2" 2)))
      (trusted-schema "trusted_schema" ((#t "1" 1) (#f "0" 0)))))

  ;; exact-integer-within? : Any Natural -> Boolean
  ;; Whether V is an exact integer from 0 to LARGEST.
  (define (exact-integer-within? v largest)
    (and (integer? v) (exact? v) (>= v 0) (<= v largest)))

  ;; --- the split ---------------------------------------------------------------------------

  ;; split-open-arguments : (Listof Any) -> (U (List 'split (Listof Any) Any) Setting-Refusal)
  ;; ARGS, open's arguments after the filename, split in one pass: every
  ;; argument that is a pair or () is a settings list, and every other goes to
  ;; the options, in its order, for parse-open-options to read as it did
  ;; before M3. So a string, a number or a boolean is still an unknown option,
  ;; and an improper pair is a settings list for settings-plan to refuse. The
  ;; settings list is the caller's own, not a copy; with none, (). A second
  ;; list is refused. ARGS is never changed.
  (define (split-open-arguments args)
    (let loop ((rest args) (options '()) (settings #f))
      (cond ((not (pair? rest)) (list 'split (reverse options) (if settings (car settings) '())))
            ((or (pair? (car rest)) (null? (car rest)))
             (if settings
                 (list 'refused 'second-settings-list)
                 (loop (cdr rest) options (list (car rest)))))
            (else (loop (cdr rest) (cons (car rest) options) settings)))))

  ;; --- the plan ----------------------------------------------------------------------------

  ;; shape-refusal : Any -> (U #f (List Any))
  ;; #f when SETTINGS is a proper list of pairs whose cars are symbols; else
  ;; a list of what refuses it: the first entry that is no such pair, or
  ;; SETTINGS itself when it is no proper list, an improper or a cyclic one.
  (define (shape-refusal settings)
    (if (not (list? settings))
        (list settings)
        (let loop ((rest settings))
          (cond ((null? rest) #f)
                ((and (pair? (car rest)) (symbol? (caar rest))) (loop (cdr rest)))
                (else (list (car rest)))))))

  ;; step-for : Symbol Any -> (U (List Symbol String String Any) #f)
  ;; The step that sets NAME, one of SQLite's six, to VALUE: (name set-sql
  ;; read-sql expected), or #f when VALUE is outside its domain. The SQL is
  ;; written from the table's words and a decimal integer alone.
  (define (step-for name value)
    (define (step pragma text)
      (list name (string-append "PRAGMA " pragma " = " text) (string-append "PRAGMA " pragma) value))
    (if (eq? name 'busy-timeout)
        (and (exact-integer-within? value largest-busy-timeout)
             (step "busy_timeout" (number->string value)))
        (let* ((setting (assq name enumerated-settings))
               (row (and setting (find (lambda (r) (eq? (car r) value)) (caddr setting)))))
          (and row (step (cadr setting) (cadr row))))))

  ;; settings-plan : Any -> (U (List 'settings Natural (Listof Setting-Step)) Setting-Refusal)
  ;; Setting-Step = (List Symbol String String Any)
  ;; Setting-Refusal = (U (List 'refused 'second-settings-list)
  ;;                      (List 'refused 'not-an-association-list Any)
  ;;                      (List 'refused 'unknown-setting Symbol)
  ;;                      (List 'refused 'setting-given-twice Symbol)
  ;;                      (List 'refused 'setting-out-of-domain Symbol Any))
  ;; SETTINGS checked by ADR-0018's rules, then planned. Its shape is checked
  ;; whole first: anything but a proper list of pairs whose cars are symbols
  ;; is refused, naming the first entry that is no such pair, or the list
  ;; itself when it is improper or cyclic. Then one pass, left to right: the
  ;; first entry whose name is unknown, or given before, or whose value is
  ;; outside its domain, in that order, is refused. A value is named by
  ;; shown-value, a string by its kind. Else the plan: the statement cache's
  ;; capacity, statement-cache's value or 32; and a step for each of SQLite's
  ;; settings given, busy-timeout's first, then the rest in the list's order.
  ;; A step is the setting's name, the SQL that sets it, the SQL that reads it
  ;; back, PRAGMA and its name, and the Scheme value expected back, the value
  ;; given. SETTINGS is never changed.
  (define (settings-plan settings)
    (let ((bad-shape (shape-refusal settings)))
      (if bad-shape
          (list 'refused 'not-an-association-list (shown-value (car bad-shape)))
          (let loop ((rest settings) (seen '()) (capacity default-statement-cache)
                     (first '()) (steps '()))
            (if (null? rest)
                (list 'settings capacity (append first (reverse steps)))
                (let ((name (caar rest)) (value (cdar rest)))
                  (cond ((not (memq name setting-names)) (list 'refused 'unknown-setting name))
                        ((memq name seen) (list 'refused 'setting-given-twice name))
                        ((eq? name 'statement-cache)
                         (if (exact-integer-within? value largest-statement-cache)
                             (loop (cdr rest) (cons name seen) value first steps)
                             (list 'refused 'setting-out-of-domain name (shown-value value))))
                        (else
                         (let ((step (step-for name value)))
                           (cond ((not step)
                                  (list 'refused 'setting-out-of-domain name (shown-value value)))
                                 ((eq? name 'busy-timeout)
                                  (loop (cdr rest) (cons name seen) capacity (list step) steps))
                                 (else
                                  (loop (cdr rest) (cons name seen) capacity first
                                        (cons step steps)))))))))))))

  ;; --- the refusal ----------------------------------------------------------------------------

  ;; refusal? : Any -> Boolean
  ;; Whether X is a refusal split-open-arguments or settings-plan answers:
  ;; (refused RULE DETAIL ...), with as many details as RULE's refusal has.
  (define (refusal? x)
    (and (list? x) (pair? x) (eq? (car x) 'refused) (pair? (cdr x))
         (case (cadr x)
           ((second-settings-list) (= (length x) 2))
           ((not-an-association-list unknown-setting setting-given-twice) (= (length x) 3))
           ((setting-out-of-domain) (= (length x) 4))
           (else #f))))

  ;; refusal-message : Symbol -> String
  (define (refusal-message rule)
    (case rule
      ((second-settings-list) "at most one argument is a settings list")
      ((not-an-association-list)
       "the settings are an association list from a setting's name, a symbol, to its value")
      ((unknown-setting)
       "not a setting: busy-timeout, foreign-keys, journal-mode, synchronous, temp-store, trusted-schema or statement-cache")
      ((setting-given-twice) "a setting given twice")
      (else
       "a value outside its setting's domain: busy-timeout an exact integer from 0 to 2147483647 ms; foreign-keys and trusted-schema #t or #f; journal-mode delete, truncate, persist or wal; synchronous off, normal, full or extra; temp-store default, file or memory; statement-cache an exact integer from 0 to 1024")))

  ;; raise-setting-refusal : Symbol Setting-Refusal -> Nothing
  ;; An assertion violation from WHO for REFUSAL, as split-open-arguments or
  ;; settings-plan answered it: its irritants are the rule's symbol, then what
  ;; the refusal names. A WHO that is no symbol, checked first, is an
  ;; assertion violation from raise-setting-refusal, (who V); a REFUSAL that
  ;; is none, (not-a-refusal V); each V by shown-value.
  (define (raise-setting-refusal who refusal)
    (unless (symbol? who)
      (assertion-violation 'raise-setting-refusal "not a symbol" 'who (shown-value who)))
    (unless (refusal? refusal)
      (assertion-violation 'raise-setting-refusal "not a refusal of a settings list"
                           'not-a-refusal (shown-value refusal)))
    (apply assertion-violation who (refusal-message (cadr refusal)) (cdr refusal)))

  ;; --- the read-back --------------------------------------------------------------------------

  ;; read-back-value : Any Any -> Any
  ;; RAW, a setting's value as its read-back statement answered it, as the
  ;; Scheme value compared with the one asked for. For an enumerated setting
  ;; a read-back its table holds reads as the table's Scheme value, 1 as #t,
  ;; "wal" as wal, 2 as full, matched by equal?, so whole and by case. Any
  ;; other RAW reads as itself, unchanged: an integer outside the table, a
  ;; REAL, TEXT of another spelling, such as "memory" from an in-memory
  ;; database (Q9), a BLOB or sql-null. It is the mismatch's actual, and
  ;; equals no table's value, for SQLite answers no symbol or boolean.
  ;; busy-timeout's every value reads as itself, as do statement-cache's and
  ;; a NAME no setting has. Total.
  (define (read-back-value name raw)
    (let* ((setting (assq name enumerated-settings))
           (row (and setting (find (lambda (r) (equal? (caddr r) raw)) (caddr setting)))))
      (if row (car row) raw)))

  ;; read-back-comparison : Any Any Any -> (U 'match (List 'mismatch Any Any Any))
  ;; Whether RAW, NAME's read-back, reads as EXPECTED, the step's expected
  ;; value: match when read-back-value's answer is eqv? to it, else
  ;; (mismatch NAME EXPECTED ACTUAL), ACTUAL that answer, the fields of
  ;; &sqlite-setting-mismatch for slice 5 to raise. Total.
  (define (read-back-comparison name expected raw)
    (let ((actual (read-back-value name raw)))
      (if (eqv? actual expected)
          'match
          (list 'mismatch name expected actual)))))
