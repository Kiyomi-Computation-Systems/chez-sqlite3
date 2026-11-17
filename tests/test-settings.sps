#!r6rs
;;; The suite for (chez-sqlite3 private settings): the pure core of the
;;; settings list open-database and call-with-database take (ADR-0018). It
;;; loads no libsqlite3: the library holds no foreign code, and the shell that
;;; runs the plan's SQL at open and raises its mismatch is M3 slice 5's.
;;;
;;;   the split        open's arguments after the filename: the options, in
;;;                    order, for parse-open-options, and at most one
;;;                    settings list, a pair or (), at any position
;;;   the plan         each setting's SQL and read-back expected, written out
;;;                    here as SQL text, never read from the library;
;;;                    busy-timeout first, then the list's order, over every
;;;                    ordering of every set of settings; statement-cache's
;;;                    capacity, 32 when absent
;;;   the domains      each at its edges, and against one universe of values
;;;                    of every kind, the other settings' values among them:
;;;                    an allowlist against its whole complement
;;;   the names        against every PRAGMA SQLite has, in both spellings,
;;;                    every name (chezscheme) exports, and near names
;;;   the refusals     each rule's leading symbol, the value by shown-value,
;;;                    and which rule comes first
;;;   the read-back    each setting's reader over its table and outside it,
;;;                    and the comparison over every expected value against
;;;                    every read-back
;;;   db_config        M4 slice 1: the four sqlite3_db_config settings, held
;;;                    out of setting-names until slice 3 joins them
;;;                    (ADR-0021; ADR-0018, amended for M4): the table, its
;;;                    names against every other op's and the list's, each
;;;                    domain against the universe, each step written out,
;;;                    the sentinel, and the set's verdict over codes, cells
;;;                    and values
;;;
;;; Every procedure but raise-setting-refusal answers data and raises
;;; nothing, so every call is made under a guard with a sentinel of its own,
;;; (raised TEXT). No expected value is #f: a boolean answer is read as the
;;; symbol yes or no, and a match as the symbol match.
(import (rnrs)
        (rnrs mutable-pairs)
        (srfi :64)
        (only (chezscheme) environment environment-symbols library-exports)
        (chez-sqlite3-testing)
        (only (chez-sqlite3 private conditions) shown-value)
        (chez-sqlite3 private settings))

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

;; --- helpers -----------------------------------------------------------------------------

;; sorted-names : (Listof Symbol) -> (Listof Symbol)
(define (sorted-names names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

;; split : Any -> Any
;; split-open-arguments' answer, or (raised TEXT).
(define (split args)
  (guard (e (#t (list 'raised (describe e)))) (split-open-arguments args)))

;; plan : Any -> Any
;; settings-plan's answer, or (raised TEXT).
(define (plan settings)
  (guard (e (#t (list 'raised (describe e)))) (settings-plan settings)))

;; read-back : Any Any -> Any
;; The reader's answer for a read-back that answered a row, VALUE its first column.
(define (read-back name value)
  (guard (e (#t (list 'raised (describe e)))) (read-back-value name (list 'row value))))

;; read-back-raw : Any Any -> Any
;; The reader's answer for ANSWER as given: (row V), none or anything else.
(define (read-back-raw name answer)
  (guard (e (#t (list 'raised (describe e)))) (read-back-value name answer)))

;; compared : Any Any Any -> Any
;; The comparison for a read-back that answered a row, VALUE its first column.
(define (compared name expected value)
  (guard (e (#t (list 'raised (describe e)))) (read-back-comparison name expected (list 'row value))))

;; compared-raw : Any Any Any -> Any
;; The comparison for ANSWER as given: (row V), none or anything else.
(define (compared-raw name expected answer)
  (guard (e (#t (list 'raised (describe e)))) (read-back-comparison name expected answer)))

;; raised : (-> Any) -> Any
;; What THUNK raised: (assertion-violation WHO IRRITANTS) for an assertion
;; violation with a who, a message and irritants, (other TEXT) for any other
;; raise, or (no-raise VALUE).
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e)
                  (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other (describe e))))
    (list 'no-raise (thunk))))

;; contains? : String String -> Boolean
(define (contains? text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i k) n) (or (string=? (substring text i (+ i k)) part) (loop (+ i 1)))))))

;; subsets : (Listof A) -> (Listof (Listof A))
(define (subsets items)
  (if (null? items)
      '(())
      (let ((rest (subsets (cdr items))))
        (append rest (map (lambda (s) (cons (car items) s)) rest)))))

;; permutations : (Listof A) -> (Listof (Listof A))
(define (permutations items)
  (if (null? items)
      '(())
      (apply append
             (map (lambda (x)
                    (map (lambda (p) (cons x p)) (permutations (remq x items))))
                  items))))

;; insert-at : A Natural (Listof A) -> (Listof A)
(define (insert-at x i items)
  (if (= i 0) (cons x items) (cons (car items) (insert-at x (- i 1) (cdr items)))))

;; iota : Natural -> (Listof Natural)
(define (iota n)
  (let loop ((i (- n 1)) (acc '()))
    (if (< i 0) acc (loop (- i 1) (cons i acc)))))

;; differences : (Listof A) (A -> B) (A -> B) -> (Listof (List A B B))
;; Each item whose WANT and GOT differ, with both.
(define (differences items want got)
  (filter (lambda (row) row)
          (map (lambda (x)
                 (let ((w (want x)) (g (got x)))
                   (and (not (equal? w g)) (list x w g))))
               items)))

;; underscores->hyphens : Symbol -> Symbol
(define (underscores->hyphens s)
  (string->symbol
   (list->string (map (lambda (c) (if (char=? c #\_) #\- c)) (string->list (symbol->string s))))))

(define-record-type a-thing (fields x))

;; bytevector : Byte ... -> Bytevector
(define (bytevector . bytes) (u8-list->bytevector bytes))

(define two31 (expt 2 31))

;; --- the table, written out ------------------------------------------------------------

;; The seven names, in ADR-0018's table order.
(define names '(busy-timeout foreign-keys journal-mode synchronous temp-store trusted-schema
                statement-cache))

;; step-of : Symbol Any -> (List Symbol String String Any)
;; ADR-0018's table for one value in its setting's domain: its name, the SQL
;; that sets it, the SQL that reads it back, and the value expected back.
;; Written out from the record, never computed by the library's rule.
(define (step-of name value)
  (define (row pragma text) (list name (string-append "PRAGMA " pragma " = " text)
                                  (string-append "PRAGMA " pragma) value))
  (case name
    ((busy-timeout) (row "busy_timeout" (number->string value)))
    ((foreign-keys) (row "foreign_keys" (if value "1" "0")))
    ((trusted-schema) (row "trusted_schema" (if value "1" "0")))
    ((journal-mode) (row "journal_mode" (cdr (assq value '((delete . "delete") (truncate . "truncate")
                                                            (persist . "persist") (wal . "wal"))))))
    ((synchronous) (row "synchronous" (cdr (assq value '((off . "0") (normal . "1") (full . "2")
                                                          (extra . "3"))))))
    ((temp-store) (row "temp_store" (cdr (assq value '((default . "0") (file . "1") (memory . "2"))))))
    (else (list 'no-step name))))

;; One value in each setting's domain, not its first, for the order rows.
(define sample-values
  '((busy-timeout . 250) (foreign-keys . #t) (journal-mode . wal) (synchronous . normal)
    (temp-store . memory) (trusted-schema . #f) (statement-cache . 7)))

;; expected-plan : (Listof (Pairof Symbol Any)) -> Any
;; The plan of a list of distinct settings, each in its domain: busy-timeout's
;; step first, then the rest in the list's order, statement-cache no step,
;; and the capacity its value, or 32.
(define (expected-plan settings)
  (let ((bt (assq 'busy-timeout settings))
        (sc (assq 'statement-cache settings)))
    (list 'settings
          (if sc (cdr sc) 32)
          (append (if bt (list (step-of 'busy-timeout (cdr bt))) '())
                  (map (lambda (s) (step-of (car s) (cdr s)))
                       (filter (lambda (s) (not (memq (car s) '(busy-timeout statement-cache))))
                               settings))))))

(define (out-of-domain name value) (list 'refused 'setting-out-of-domain name (shown-value value)))

(test-begin "settings")

(test-equal "(chez-sqlite3 private settings) exports exactly the names, the rules, the split, the plan, the refusal's raise, the reader and the comparison; and db_config's table, names, sentinel, step and verdict"
  (sorted-names '(setting-names setting-refusal-rules split-open-arguments settings-plan
                  raise-setting-refusal read-back-value read-back-comparison
                  db-config-settings db-config-setting-names db-config-sentinel db-config-step
                  db-config-verdict))
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3 private settings)))))

(test-equal "setting-names, written out, in ADR-0018's table order"
  '(busy-timeout foreign-keys journal-mode synchronous temp-store trusted-schema statement-cache)
  setting-names)

(test-equal "setting-refusal-rules, written out: ADR-0018's five rules"
  '(second-settings-list not-an-association-list unknown-setting setting-given-twice
    setting-out-of-domain)
  setting-refusal-rules)

;; --- the split -------------------------------------------------------------------------

(test-equal "no argument: no option and the empty settings list"
  '(split () ())
  (split '()))

(test-equal "symbols alone are the options, in their order, and no list is the empty settings list"
  '((split (read-only) ()) (split (no-mutex read-only uri) ()) (split (uri uri) ())
    (split (foo read-write) ()))
  (list (split '(read-only)) (split '(no-mutex read-only uri)) (split '(uri uri))
        (split '(foo read-write))))

(define a-list (list (cons 'busy-timeout 250) (cons 'foreign-keys #t)))

(test-equal "a settings list at every position among three options is split out, the options kept in order"
  (map (lambda (i) (list 'split '(no-mutex uri read-only) a-list)) '(0 1 2 3))
  (map (lambda (i) (split (insert-at a-list i '(no-mutex uri read-only)))) '(0 1 2 3)))

(test-equal "the settings list split out is the caller's own list, eq?, at every position"
  '(same same same same)
  (map (lambda (i)
         (let ((s (split (insert-at a-list i '(no-mutex uri read-only)))))
           (if (and (pair? s) (= (length s) 3) (eq? (caddr s) a-list)) 'same (list 'differs s))))
       '(0 1 2 3)))

(test-equal "() is a settings list, the empty one, at every position"
  (map (lambda (i) '(split (memory uri) ())) '(0 1 2))
  (map (lambda (i) (split (insert-at '() i '(memory uri)))) '(0 1 2)))

(test-equal "a pair that is no list is a settings list, for the plan to refuse"
  '((split () (busy-timeout . 5)) (split (uri) ((busy-timeout . 5) . 6)) (split () (5 . 6)))
  (list (split (list (cons 'busy-timeout 5)))
        (split (list 'uri (cons (cons 'busy-timeout 5) 6)))
        (split (list (cons 5 6)))))

;; Anything else that is neither a symbol nor a list goes to the options, so
;; parse-open-options refuses it as unknown, as before M3.
(define atoms (list "read-only" 1 2.5 #t #f #\r (vector 'read-only) (bytevector 1) car
                    (make-a-thing 1)))

(test-equal "an argument that is neither a symbol nor a pair nor () goes to the options, in order: a string, numbers, booleans, a char, a vector, a bytevector, a procedure, a record"
  (list 'split (append '(uri) atoms '(memory)) a-list)
  (split (append '(uri) atoms (list a-list 'memory))))

(define (two-lists-at i j n)
  ;; N options with a list inserted before position I and another before J.
  (let loop ((k 0) (acc '()))
    (if (= k (+ n 2))
        (reverse acc)
        (loop (+ k 1)
              (cons (cond ((= k i) a-list) ((= k j) (list (cons 'temp-store 'file))) (else 'uri))
                    acc)))))

(test-equal "a second list, at every pair of positions among options, is refused, whatever the lists hold"
  (map (lambda (p) '(refused second-settings-list))
       '((0 1) (0 2) (0 3) (1 2) (1 3) (2 3)))
  (map (lambda (p) (split (two-lists-at (car p) (cadr p) 2)))
       '((0 1) (0 2) (0 3) (1 2) (1 3) (2 3))))

(test-equal "a second list is refused when either is (), when they are equal, and when there are three"
  '((refused second-settings-list) (refused second-settings-list) (refused second-settings-list)
    (refused second-settings-list) (refused second-settings-list))
  (list (split (list '() a-list)) (split (list a-list '())) (split (list '() '()))
        (split (list a-list 'uri a-list)) (split (list a-list '() (list (cons 1 2))))))

(test-equal "the split leaves its arguments as they were"
  (list 'uri a-list 'memory)
  (let ((args (list 'uri a-list 'memory)))
    (split args)
    args))

;; --- the plan: each setting alone ------------------------------------------------------

(test-equal "the empty list plans nothing, and a capacity of 32"
  '(settings 32 ())
  (plan '()))

(test-equal "each of SQLite's six alone, at every value of its domain: its SQL and its read-back, written out"
  '((settings 32 ((busy-timeout "PRAGMA busy_timeout = 0" "PRAGMA busy_timeout" 0)))
    (settings 32 ((busy-timeout "PRAGMA busy_timeout = 5000" "PRAGMA busy_timeout" 5000)))
    (settings 32 ((busy-timeout "PRAGMA busy_timeout = 2147483647" "PRAGMA busy_timeout" 2147483647)))
    (settings 32 ((foreign-keys "PRAGMA foreign_keys = 1" "PRAGMA foreign_keys" #t)))
    (settings 32 ((foreign-keys "PRAGMA foreign_keys = 0" "PRAGMA foreign_keys" #f)))
    (settings 32 ((journal-mode "PRAGMA journal_mode = delete" "PRAGMA journal_mode" delete)))
    (settings 32 ((journal-mode "PRAGMA journal_mode = truncate" "PRAGMA journal_mode" truncate)))
    (settings 32 ((journal-mode "PRAGMA journal_mode = persist" "PRAGMA journal_mode" persist)))
    (settings 32 ((journal-mode "PRAGMA journal_mode = wal" "PRAGMA journal_mode" wal)))
    (settings 32 ((synchronous "PRAGMA synchronous = 0" "PRAGMA synchronous" off)))
    (settings 32 ((synchronous "PRAGMA synchronous = 1" "PRAGMA synchronous" normal)))
    (settings 32 ((synchronous "PRAGMA synchronous = 2" "PRAGMA synchronous" full)))
    (settings 32 ((synchronous "PRAGMA synchronous = 3" "PRAGMA synchronous" extra)))
    (settings 32 ((temp-store "PRAGMA temp_store = 0" "PRAGMA temp_store" default)))
    (settings 32 ((temp-store "PRAGMA temp_store = 1" "PRAGMA temp_store" file)))
    (settings 32 ((temp-store "PRAGMA temp_store = 2" "PRAGMA temp_store" memory)))
    (settings 32 ((trusted-schema "PRAGMA trusted_schema = 1" "PRAGMA trusted_schema" #t)))
    (settings 32 ((trusted-schema "PRAGMA trusted_schema = 0" "PRAGMA trusted_schema" #f))))
  (map (lambda (s) (plan (list s)))
       '((busy-timeout . 0) (busy-timeout . 5000) (busy-timeout . 2147483647)
         (foreign-keys . #t) (foreign-keys . #f)
         (journal-mode . delete) (journal-mode . truncate) (journal-mode . persist)
         (journal-mode . wal)
         (synchronous . off) (synchronous . normal) (synchronous . full) (synchronous . extra)
         (temp-store . default) (temp-store . file) (temp-store . memory)
         (trusted-schema . #t) (trusted-schema . #f))))

(test-equal "statement-cache: 0, 1, 32 and 1024 accepted as the capacity, and no step"
  '((settings 0 ()) (settings 1 ()) (settings 32 ()) (settings 1024 ()))
  (map (lambda (n) (plan (list (cons 'statement-cache n)))) '(0 1 32 1024)))

(test-equal "statement-cache: -1, 1025, 32.0, 32.5, #t, \"32\" and a symbol are each refused as outside its domain, the string by its kind"
  '((refused setting-out-of-domain statement-cache -1)
    (refused setting-out-of-domain statement-cache 1025)
    (refused setting-out-of-domain statement-cache 32.0)
    (refused setting-out-of-domain statement-cache 32.5)
    (refused setting-out-of-domain statement-cache #t)
    (refused setting-out-of-domain statement-cache (kind string))
    (refused setting-out-of-domain statement-cache thirty-two))
  (map (lambda (v) (plan (list (cons 'statement-cache v))))
       (list -1 1025 32.0 32.5 #t "32" 'thirty-two)))

(test-equal "statement-cache absent gives 32, beside every other setting"
  (map (lambda (s) 32) (remq 'statement-cache names))
  (map (lambda (n) (let ((p (plan (list (assq n sample-values)))))
                     (if (and (pair? p) (eq? (car p) 'settings)) (cadr p) p)))
       (remq 'statement-cache names)))

(test-equal "busy-timeout: 0 and 2^31-1 accepted; 2^31 and -1 refused, as are 2^31+1, 2^32, -2^31 and 2^64"
  (list (list 'settings 32 (list (step-of 'busy-timeout 0)))
        (list 'settings 32 (list (step-of 'busy-timeout (- two31 1))))
        (list 'refused 'setting-out-of-domain 'busy-timeout two31)
        '(refused setting-out-of-domain busy-timeout -1)
        (list 'refused 'setting-out-of-domain 'busy-timeout (+ two31 1))
        (list 'refused 'setting-out-of-domain 'busy-timeout (expt 2 32))
        (list 'refused 'setting-out-of-domain 'busy-timeout (- two31))
        (list 'refused 'setting-out-of-domain 'busy-timeout (expt 2 64)))
  (map (lambda (v) (plan (list (cons 'busy-timeout v))))
       (list 0 (- two31 1) two31 -1 (+ two31 1) (expt 2 32) (- two31) (expt 2 64))))

(test-equal "busy-timeout and statement-cache, one inside each edge: 1 and 2^31-2, 1 and 1023"
  (list (list 'settings 32 (list (step-of 'busy-timeout 1)))
        (list 'settings 32 (list (step-of 'busy-timeout (- two31 2))))
        '(settings 1 ()) '(settings 1023 ()))
  (list (plan (list (cons 'busy-timeout 1))) (plan (list (cons 'busy-timeout (- two31 2))))
        (plan (list (cons 'statement-cache 1))) (plan (list (cons 'statement-cache 1023)))))

;; --- the domains, against one universe -----------------------------------------------

;; A value of every kind, and every setting's own values, so each domain is
;; tried against the others'.
(define universe
  (list #t #f 0 1 2 3 4 -1 7 32 250 1023 1024 1025 5000 (- two31 1) two31 (- two31) (expt 2 64)
        5000.0 1.0 0.0 -0.0 0.5 32.5 +inf.0 -inf.0 +nan.0 1/2 10001/2 1+2i
        'delete 'truncate 'persist 'wal 'memory 'off 'normal 'full 'extra 'default 'file
        'on 'yes 'true 'false 'WAL 'Delete 'OFF 'NORMAL 'DEFAULT 'wal2 'immediate
        "wal" "1" "0" "" "5000" #\1 #\w '() '(1) '(wal) '(#t) (cons 1 2) (vector 1) (vector)
        (bytevector 1) car (make-a-thing 1) (make-eq-hashtable)))

;; Each setting's domain within the universe, written out from ADR-0018.
(define domains
  (list (list 'busy-timeout 0 1 2 3 4 7 32 250 1023 1024 1025 5000 (- two31 1))
        (list 'foreign-keys #t #f)
        (list 'journal-mode 'delete 'truncate 'persist 'wal)
        (list 'synchronous 'off 'normal 'full 'extra)
        (list 'temp-store 'default 'file 'memory)
        (list 'trusted-schema #t #f)
        (list 'statement-cache 0 1 2 3 4 7 32 250 1023 1024)))

(define (in-domain? name v)
  (let ((d (cdr (assq name domains))))
    (exists (lambda (x) (eqv? x v)) d)))

(test-equal "the universe holds 71 values"
  71
  (length universe))

(test-equal "every setting against every value of the universe: its domain accepted, with its step or capacity, and every other value refused by shown-value"
  '()
  (apply append
         (map (lambda (name)
                (differences universe
                             (lambda (v)
                               (cond ((not (in-domain? name v)) (out-of-domain name v))
                                     ((eq? name 'statement-cache) (list 'settings v '()))
                                     (else (list 'settings 32 (list (step-of name v))))))
                             (lambda (v) (plan (list (cons name v))))))
              names)))

(test-equal "a refused value is shown as shown-value shows it: a string, a list holding one, a vector, a procedure and a record by their kinds; numbers, booleans, symbols, chars and lists of them as themselves"
  '((refused setting-out-of-domain foreign-keys (kind string))
    (refused setting-out-of-domain foreign-keys (kind list))
    (refused setting-out-of-domain foreign-keys (kind vector))
    (refused setting-out-of-domain foreign-keys (kind procedure))
    (refused setting-out-of-domain foreign-keys (kind other))
    (refused setting-out-of-domain foreign-keys (kind bytevector))
    (refused setting-out-of-domain foreign-keys 1)
    (refused setting-out-of-domain foreign-keys on)
    (refused setting-out-of-domain foreign-keys #\1)
    (refused setting-out-of-domain foreign-keys (on 1))
    (refused setting-out-of-domain foreign-keys ()))
  (map (lambda (v) (plan (list (cons 'foreign-keys v))))
       (list "on" (list "on") (vector 1) car (make-a-thing 1) (bytevector 1) 1 'on #\1 '(on 1) '())))

(test-equal "a secret given as a value never reaches the refusal: no string is in it"
  '(refused setting-out-of-domain journal-mode (kind string))
  (plan (list (cons 'journal-mode "Pr0xyS3cr3t"))))

;; --- the names --------------------------------------------------------------------------

;; Every PRAGMA SQLite has: the union of the floor's own table, aPragmaName in
;; sqlite3.c of sqlite-amalgamation-3450100.zip (sqlite3.c's sha256
;; 1a206854aa9fe0ccc1b609f5cfce67eb52ac0a8f5aa2f5e853f7c3ed84c710ab), 78
;; names, every one compiled in or guarded by an #if; and the "List Of
;; PRAGMAs" of https://sqlite.org/pragma.html, read on 2026-11-15, 74 names.
;; The table adds activate_extensions, lock_proxy_file, lock_status,
;; sql_trace and vdbe_eqp; the page adds legacy_file_format. pragma_pragma_list
;; lists only those compiled in, so it is a subset.
(define sqlite-pragmas
  '(activate_extensions analysis_limit application_id auto_vacuum automatic_index busy_timeout
    cache_size cache_spill case_sensitive_like cell_size_check checkpoint_fullfsync
    collation_list compile_options count_changes data_store_directory data_version
    database_list default_cache_size defer_foreign_keys empty_result_callbacks encoding
    foreign_key_check foreign_key_list foreign_keys freelist_count full_column_names fullfsync
    function_list hard_heap_limit ignore_check_constraints incremental_vacuum index_info
    index_list index_xinfo integrity_check journal_mode journal_size_limit legacy_alter_table
    legacy_file_format lock_proxy_file lock_status locking_mode max_page_count mmap_size
    module_list optimize page_count page_size parser_trace pragma_list query_only quick_check
    read_uncommitted recursive_triggers reverse_unordered_selects schema_version secure_delete
    short_column_names shrink_memory soft_heap_limit sql_trace stats synchronous table_info
    table_list table_xinfo temp_store temp_store_directory threads trusted_schema user_version
    vdbe_addoptrace vdbe_debug vdbe_eqp vdbe_listing vdbe_trace wal_autocheckpoint
    wal_checkpoint writable_schema))

(test-equal "SQLite's PRAGMAs: 79 distinct names, our six among them in SQLite's spelling"
  '(79 79 (busy_timeout foreign_keys journal_mode synchronous temp_store trusted_schema))
  (list (length sqlite-pragmas)
        (length (fold-left (lambda (acc s) (if (memq s acc) acc (cons s acc))) '() sqlite-pragmas))
        (filter (lambda (s) (memq (underscores->hyphens s) names)) sqlite-pragmas)))

;; The names the list leaves out: SQLite's 79 in its spelling and in ours,
;; 152 distinct, for six have no underscore and are spelt alike, less our six
;; in our spelling, synchronous among them in both: 146.
(define left-out
  (let loop ((rest (append sqlite-pragmas (map underscores->hyphens sqlite-pragmas))) (acc '()))
    (cond ((null? rest) (reverse acc))
          ((or (memq (car rest) acc) (memq (car rest) names)) (loop (cdr rest) acc))
          (else (loop (cdr rest) (cons (car rest) acc))))))

(test-equal "146 names left out: SQLite's in its spelling and ours, but our own six, and six spelt alike either way: encoding, fullfsync, optimize, stats, synchronous and threads"
  '(146 (encoding fullfsync optimize stats synchronous threads))
  (list (length left-out)
        (filter (lambda (s) (eq? s (underscores->hyphens s))) sqlite-pragmas)))

(define (unknown-row name) (list 'refused 'unknown-setting name))

(test-equal "every PRAGMA SQLite has, in SQLite's spelling and ours, but our own six, is refused as an unknown setting, naming it"
  '()
  (differences left-out unknown-row (lambda (s) (plan (list (cons s 1))))))

(define chez-names
  (guard (e (#t (list 'raised (describe e))))
    (remp (lambda (s) (memq s names)) (environment-symbols (environment '(chezscheme))))))

(test-equal "(chezscheme) gives names to refuse, in the hundreds"
  'many
  (if (and (list? chez-names) (> (length chez-names) 500)) 'many chez-names))

(test-equal "every name (chezscheme) exports is refused as an unknown setting, naming it"
  '()
  (if (list? chez-names)
      (differences chez-names unknown-row (lambda (s) (plan (list (cons s #t)))))
      chez-names))

(define near-names
  (append
   '(BUSY-TIMEOUT Busy-Timeout busytimeout busy-timeout-ms busy-timeouts busy-time timeout
     foreign-key foreignkeys FOREIGN-KEYS foreign-keys? journal journalmode journal-modes wal
     synchronous? sync temp_store_directory tempstore temp-stores trusted-schemas trusted
     statement_cache statementcache statement-cache-size cache cache-size STATEMENT-CACHE
     statement-caches open-options read-only uri memory no-mutex)
   (map string->symbol '("busy-timeout " " busy-timeout" "foreign keys" "statement-cache\x0;"))))

(test-equal "every near name is refused as an unknown setting, naming it: case, spelling, plural and separator variants, the open options, and a name with a space or a U+0000"
  '()
  (differences near-names unknown-row (lambda (s) (plan (list (cons s 1))))))

;; --- a name given twice ----------------------------------------------------------------

(test-equal "each setting given twice, alone, is refused as given twice, naming it, whatever its two values"
  (map (lambda (n) (list 'refused 'setting-given-twice n)) names)
  (map (lambda (n) (plan (list (assq n sample-values) (assq n sample-values)))) names))

(define (others-than n) (filter (lambda (s) (not (eq? (car s) n))) sample-values))

(test-equal "each setting given twice, at every pair of positions beside two others, is refused as given twice, naming it"
  (apply append (map (lambda (n) (map (lambda (p) (list 'refused 'setting-given-twice n))
                                      '((0 1) (0 2) (0 3) (1 2) (1 3) (2 3))))
                     names))
  (apply append
         (map (lambda (n)
                (let ((two (list (car (others-than n)) (cadr (others-than n))))
                      (s (assq n sample-values)))
                  (map (lambda (p) (plan (insert-at s (cadr p) (insert-at s (car p) two))))
                       '((0 1) (0 2) (0 3) (1 2) (1 3) (2 3)))))
              names)))

(test-equal "the first name repeated is the one named, a third time changing nothing"
  '((refused setting-given-twice foreign-keys) (refused setting-given-twice busy-timeout)
    (refused setting-given-twice temp-store))
  (list (plan '((foreign-keys . #t) (busy-timeout . 1) (foreign-keys . #f) (busy-timeout . 2)))
        (plan '((busy-timeout . 1) (busy-timeout . 2) (busy-timeout . 3)))
        (plan '((temp-store . file) (synchronous . off) (temp-store . file)))))

;; --- a list that is no association list of symbols -------------------------------------

(define cyclic
  (guard (e (#t (list 'raised (describe e))))
    (let ((l (list (cons 'busy-timeout 1) (cons 'foreign-keys #t))))
      (set-cdr! (cdr l) l)
      l)))

(test-equal "a settings argument that is no list at all: an improper list, a cyclic one, and atoms, each shown by shown-value"
  '((refused not-an-association-list (kind list))
    (refused not-an-association-list (kind list))
    (refused not-an-association-list (kind list))
    (refused not-an-association-list 5)
    (refused not-an-association-list (kind string))
    (refused not-an-association-list busy-timeout)
    (refused not-an-association-list #t)
    (refused not-an-association-list (kind vector)))
  (list (plan (cons (cons 'busy-timeout 1) 5))
        (plan (cons 'busy-timeout 5))
        (plan cyclic)
        (plan 5) (plan "busy-timeout") (plan 'busy-timeout) (plan #t) (plan (vector))))

(define bad-entries
  (list 5 'busy-timeout "busy-timeout" '() #t (vector 'busy-timeout 1)
        (cons "busy-timeout" 1) (cons 5 1) (cons '() 1) (cons '(busy-timeout) 1) (list 5 1)
        (cons #t 1) (cons #\b 1)))

(test-equal "an entry that is no pair, or a pair whose name is no symbol, is refused at every position among three good entries, shown by shown-value"
  (apply append
         (map (lambda (b) (map (lambda (i) (list 'refused 'not-an-association-list (shown-value b)))
                               '(0 1 2 3)))
              bad-entries))
  (apply append
         (map (lambda (b) (map (lambda (i) (plan (insert-at b i '((busy-timeout . 1) (journal-mode . wal)
                                                                   (temp-store . file)))))
                               '(0 1 2 3)))
              bad-entries)))

(test-equal "the bad entries as shown, written out"
  '(5 busy-timeout (kind string) () #t (kind vector) (kind list) (kind list) (kind list)
    (kind list) (5 1) (kind list) (kind list))
  (map shown-value bad-entries))

;; --- which refusal comes first ---------------------------------------------------------

(test-equal "the list's shape is checked whole first; then one pass, left to right, each entry's name known, then not given before, then its value in its domain"
  '((refused not-an-association-list 5)
    (refused not-an-association-list 5)
    (refused unknown-setting nosuch)
    (refused setting-out-of-domain busy-timeout -1)
    (refused setting-given-twice busy-timeout)
    (refused setting-out-of-domain busy-timeout -1)
    (refused unknown-setting nosuch)
    (refused setting-given-twice journal-mode)
    (refused setting-out-of-domain temp-store 3))
  (list (plan '((nosuch . 1) 5))
        (plan '((busy-timeout . -1) (busy-timeout . 1) 5))
        (plan '((nosuch . -1) (busy-timeout . -1)))
        (plan '((busy-timeout . -1) (nosuch . 1)))
        (plan '((busy-timeout . 1) (busy-timeout . -1)))
        (plan '((busy-timeout . -1) (busy-timeout . 1)))
        (plan '((journal-mode . wal) (nosuch . 1) (journal-mode . wal)))
        (plan '((journal-mode . wal) (journal-mode . nosuch) (temp-store . 3)))
        (plan '((journal-mode . wal) (temp-store . 3) (journal-mode . wal)))))

;; --- the order of the steps ------------------------------------------------------------

;; every-ordering : (Listof (Listof (Pairof Symbol Any)))
;; Every ordering of every set of distinct settings: 13,700 lists.
(define every-ordering (apply append (map permutations (subsets sample-values))))

(test-equal "there are 13,700 orderings of the sets of distinct settings"
  13700
  (length every-ordering))

(test-equal "every ordering of every set of distinct settings plans busy-timeout first, then the rest in the list's order, statement-cache as the capacity alone, 32 when absent: no list differs"
  '()
  (differences every-ordering expected-plan plan))

(test-equal "the whole list, in an order that puts busy-timeout last and statement-cache first, written out"
  '(settings 7 ((busy-timeout "PRAGMA busy_timeout = 250" "PRAGMA busy_timeout" 250)
                (trusted-schema "PRAGMA trusted_schema = 0" "PRAGMA trusted_schema" #f)
                (temp-store "PRAGMA temp_store = 2" "PRAGMA temp_store" memory)
                (synchronous "PRAGMA synchronous = 1" "PRAGMA synchronous" normal)
                (journal-mode "PRAGMA journal_mode = wal" "PRAGMA journal_mode" wal)
                (foreign-keys "PRAGMA foreign_keys = 1" "PRAGMA foreign_keys" #t)))
  (plan (reverse sample-values)))

(test-equal "the plan leaves its list as it was"
  (list (cons 'temp-store 'file) (cons 'busy-timeout 9))
  (let ((given (list (cons 'temp-store 'file) (cons 'busy-timeout 9))))
    (plan given)
    given))

;; --- raise-setting-refusal ---------------------------------------------------------------

;; One refusal of each rule, as the split and the plan answer them.
(define refusals
  (list (split (list '() '()))
        (plan '(5))
        (plan '((nosuch . 1)))
        (plan '((uri . 1)))
        (plan '((temp-store . file) (temp-store . file)))
        (plan '((busy-timeout . -1)))
        (plan '((journal-mode . "wal")))))

(test-equal "raise-setting-refusal raises each rule's refusal as an assertion violation from WHO, its irritants the rule and what the refusal names"
  '((assertion-violation open-database (second-settings-list))
    (assertion-violation open-database (not-an-association-list 5))
    (assertion-violation open-database (unknown-setting nosuch))
    (assertion-violation call-with-database (unknown-setting uri))
    (assertion-violation open-database (setting-given-twice temp-store))
    (assertion-violation call-with-database (setting-out-of-domain busy-timeout -1))
    (assertion-violation open-database (setting-out-of-domain journal-mode (kind string))))
  (map (lambda (r who) (raised (lambda () (raise-setting-refusal who r))))
       refusals
       '(open-database open-database open-database call-with-database open-database
         call-with-database open-database)))

(test-equal "raise-setting-refusal's raise is no continuable one: a handler that returns gets a non-continuable violation, not its return"
  'non-continuable
  (guard (e ((non-continuable-violation? e) 'non-continuable)
            (#t (list 'other (describe e))))
    (with-exception-handler
     (lambda (c) 'handler-returned)
     (lambda () (raise-setting-refusal 'open-database (plan '((nosuch . 1)))) 'returned))))

(test-equal "the secret refused never reaches the condition's text"
  'absent
  (let ((text (guard (e (#t (describe e)))
                (raise-setting-refusal 'open-database
                                       (plan (list (cons 'journal-mode "Pr0xyS3cr3t"))))
                "no raise")))
    (if (contains? text "Pr0xyS3cr3t") (list 'present text)
        (if (string=? text "no raise") 'no-raise 'absent))))

(test-equal "raise-setting-refusal refuses a WHO that is no symbol, checked first, naming it by shown-value"
  '((assertion-violation raise-setting-refusal (who (kind string)))
    (assertion-violation raise-setting-refusal (who 5))
    (assertion-violation raise-setting-refusal (who #f)))
  (list (raised (lambda () (raise-setting-refusal "open-database" (plan '((nosuch . 1))))))
        (raised (lambda () (raise-setting-refusal 5 'stub)))
        (raised (lambda () (raise-setting-refusal #f (plan '((nosuch . 1))))))))

(test-equal "raise-setting-refusal refuses what is no refusal: a plan, a symbol, a list with no rule or another rule, an improper list, a string; naming it by shown-value"
  '((assertion-violation raise-setting-refusal (not-a-refusal (settings 32 ())))
    (assertion-violation raise-setting-refusal (not-a-refusal stub))
    (assertion-violation raise-setting-refusal (not-a-refusal (refused)))
    (assertion-violation raise-setting-refusal (not-a-refusal (refused unknown-option foo)))
    (assertion-violation raise-setting-refusal (not-a-refusal (unknown-setting nosuch)))
    (assertion-violation raise-setting-refusal (not-a-refusal (kind list)))
    (assertion-violation raise-setting-refusal (not-a-refusal (kind string))))
  (list (raised (lambda () (raise-setting-refusal 'open-database (plan '()))))
        (raised (lambda () (raise-setting-refusal 'open-database 'stub)))
        (raised (lambda () (raise-setting-refusal 'open-database '(refused))))
        (raised (lambda () (raise-setting-refusal 'open-database '(refused unknown-option foo))))
        (raised (lambda () (raise-setting-refusal 'open-database '(unknown-setting nosuch))))
        (raised (lambda () (raise-setting-refusal 'open-database '(refused . unknown-setting))))
        (raised (lambda () (raise-setting-refusal 'open-database "refused")))))

(test-equal "raise-setting-refusal refuses a refusal with a detail too many or too few, for each rule"
  '((assertion-violation raise-setting-refusal (not-a-refusal (refused second-settings-list x)))
    (assertion-violation raise-setting-refusal (not-a-refusal (refused not-an-association-list)))
    (assertion-violation raise-setting-refusal (not-a-refusal (refused not-an-association-list 5 6)))
    (assertion-violation raise-setting-refusal (not-a-refusal (refused unknown-setting)))
    (assertion-violation raise-setting-refusal (not-a-refusal (refused unknown-setting nosuch extra)))
    (assertion-violation raise-setting-refusal (not-a-refusal (refused setting-given-twice)))
    (assertion-violation raise-setting-refusal (not-a-refusal (refused setting-given-twice uri uri)))
    (assertion-violation raise-setting-refusal (not-a-refusal (refused setting-out-of-domain busy-timeout)))
    (assertion-violation raise-setting-refusal (not-a-refusal (refused setting-out-of-domain busy-timeout -1 0))))
  (map (lambda (r) (raised (lambda () (raise-setting-refusal 'open-database r))))
       '((refused second-settings-list x) (refused not-an-association-list)
         (refused not-an-association-list 5 6) (refused unknown-setting)
         (refused unknown-setting nosuch extra) (refused setting-given-twice)
         (refused setting-given-twice uri uri) (refused setting-out-of-domain busy-timeout)
         (refused setting-out-of-domain busy-timeout -1 0))))

;; --- the read-back ---------------------------------------------------------------------

;; Each setting's table, read back as SQLite answers it: INTEGER as an exact
;; integer, journal_mode as lower-case TEXT, here as its row's first column.
(define read-back-table
  '((busy-timeout (0 . 0) (5000 . 5000) (2147483647 . 2147483647))
    (foreign-keys (1 . #t) (0 . #f))
    (journal-mode ("delete" . delete) ("truncate" . truncate) ("persist" . persist) ("wal" . wal))
    (synchronous (0 . off) (1 . normal) (2 . full) (3 . extra))
    (temp-store (0 . default) (1 . file) (2 . memory))
    (trusted-schema (1 . #t) (0 . #f))))

(test-equal "each setting reads its table's read-back as its Scheme value"
  (map (lambda (row) (map cdr (cdr row))) read-back-table)
  (map (lambda (row) (map (lambda (pair) (read-back (car row) (car pair))) (cdr row)))
       read-back-table))

(define a-blob (bytevector 1))
(define a-record (make-a-thing 'null))

;; What SQLite could answer outside each table: other integers, REALs, TEXT of
;; other spellings, a BLOB, and a record standing for sql-null.
(define outsiders
  (list -1 2 3 4 7 -2147483648 2147483648 1.0 0.0 2.0 "1" "0" "" "memory" "off" "WAL" "Wal"
        "wal " "delete\x0;" "normal" a-blob a-record))

;; expected-actual : Symbol Any -> Any
;; What a read-back outside its table reads as, written out: journal-mode's TEXT as a
;; symbol, all else as itself.
(define (expected-actual name raw)
  (if (and (eq? name 'journal-mode) (string? raw)) (string->symbol raw) raw))

(test-equal "a read-back outside its setting's table reads as itself, eq?, as SQLite answered it, journal-mode's TEXT as a symbol: other integers, REALs, other TEXT, a BLOB and a NULL's stand-in"
  '()
  (apply append
         (map (lambda (row)
                (let ((name (car row)))
                  (filter (lambda (x) x)
                          (map (lambda (raw)
                                 (and (not (assoc raw (cdr row)))
                                      (let ((got (read-back name raw)))
                                        (and (not (eq? got (expected-actual name raw))) (list name raw got)))))
                               outsiders))))
              read-back-table)))

(test-equal "busy-timeout reads every integer as itself: -1, 2^31 and 2^64 too"
  (list -1 two31 (expt 2 64) 1.5)
  (map (lambda (v) (read-back 'busy-timeout v)) (list -1 two31 (expt 2 64) 1.5)))

(test-equal "journal-mode's TEXT is matched whole and by case, and any other TEXT reads as a symbol of the text as read: memory, off, WAL, and wal with a space, wa and wall"
  (list 'memory 'off 'WAL (string->symbol "wal ") 'wa 'wall)
  (map (lambda (v) (read-back 'journal-mode v)) '("memory" "off" "WAL" "wal " "wa" "wall")))

(test-equal "statement-cache and a name no setting has read every value as itself"
  (list 1 "wal" a-blob 1 "1")
  (list (read-back 'statement-cache 1) (read-back 'statement-cache "wal")
        (read-back 'nosuch a-blob) (read-back "foreign-keys" 1) (read-back 5 "1")))

;; An integer outside journal-mode's table, and any other setting's TEXT, stay as read.
(test-equal "journal-mode's integers, REALs and BLOBs stay as read, and another setting's TEXT stays a string"
  (list 1 2.0 a-blob "memory" "wal")
  (list (read-back 'journal-mode 1) (read-back 'journal-mode 2.0) (read-back 'journal-mode a-blob)
        (read-back 'temp-store "memory") (read-back 'statement-cache "wal")))

(test-equal "a read-back that answered no row, none, reads as () for every setting, and anything else that is no (row V) too"
  '(() () () () () () () () () ())
  (append (map (lambda (n) (read-back-raw n 'none)) setting-names)
          (list (read-back-raw 'foreign-keys '(row)) (read-back-raw 'foreign-keys '(row 1 2))
                (read-back-raw 'foreign-keys 1))))

(test-equal "a read-back that answered no row is always a mismatch whose actual is (), whatever was expected, () and #f among them"
  (list '(mismatch foreign-keys #f ()) '(mismatch foreign-keys #t ()) '(mismatch foreign-keys () ())
        '(mismatch journal-mode wal ()) '(mismatch busy-timeout 0 ()) '(mismatch statement-cache () ())
        '(mismatch nosuch #f ()))
  (list (compared-raw 'foreign-keys #f 'none) (compared-raw 'foreign-keys #t 'none)
        (compared-raw 'foreign-keys '() 'none) (compared-raw 'journal-mode 'wal 'none)
        (compared-raw 'busy-timeout 0 'none) (compared-raw 'statement-cache '() 'none)
        (compared-raw 'nosuch #f 'none)))

;; Every expected value of each domain, against every read-back of its table
;; and every outsider: match only against its own row.
(test-equal "the comparison: every expected value of every domain against every read-back of its table and outside it matches its own row alone, and is otherwise the mismatch whole: setting, expected, actual as read"
  '()
  (apply append
         (map (lambda (row)
                (let ((name (car row)))
                  (apply append
                         (map (lambda (expected)
                                (differences (append (map car (cdr row)) outsiders)
                                             (lambda (raw)
                                               (let ((hit (assoc raw (cdr row))))
                                                 (if (and hit (eqv? (cdr hit) expected))
                                                     'match
                                                     (list 'mismatch name expected
                                                           (if hit (cdr hit) (expected-actual name raw))))))
                                             (lambda (raw) (compared name expected raw))))
                              (map cdr (cdr row))))))
              read-back-table)))

(test-equal "the mismatches Q9 and SQLite's coercions give, written out"
  '((mismatch journal-mode wal memory) (mismatch foreign-keys #t #f)
    (mismatch busy-timeout 5000 0) (mismatch synchronous extra 4) (mismatch temp-store file default)
    (mismatch trusted-schema #f #t) match)
  (list (compared 'journal-mode 'wal "memory") (compared 'foreign-keys #t 0)
        (compared 'busy-timeout 5000 0) (compared 'synchronous 'extra 4)
        (compared 'temp-store 'file 0) (compared 'trusted-schema #f 1)
        (compared 'busy-timeout 2147483647 2147483647)))

(test-equal "each step's own expected value matches its read-back, over every value of each of the six domains"
  '()
  (apply append
         (map (lambda (row)
                (differences (cdr row)
                             (lambda (pair) 'match)
                             (lambda (pair)
                               (let ((p (plan (list (cons (car row) (cdr pair))))))
                                 (if (and (pair? p) (eq? (car p) 'settings) (= (length (caddr p)) 1))
                                     (let ((step (car (caddr p))))
                                       (compared (car step) (cadddr step) (car pair)))
                                     p)))))
              read-back-table)))

;; --- db_config's four (M4 slice 1; ADR-0021, decisions 1 to 3 and 5) --------------------
;; Slice 1 builds them beside setting-names, not in it: open.sls runs every
;; step settings-plan answers as SQL, so slice 3 joins them, with the open's
;; calls (the M4 plan, section 5, item 1).

;; dc-step : Any Any -> Any
;; db-config-step's answer, or (raised TEXT).
(define (dc-step name value)
  (guard (e (#t (list 'raised (describe e)))) (db-config-step name value)))

;; dc-verdict : Any Any Any Any -> Any
;; db-config-verdict's answer, or (raised TEXT).
(define (dc-verdict name value code cell)
  (guard (e (#t (list 'raised (describe e)))) (db-config-verdict name value code cell)))

;; The four, written out from ADR-0021's decision 1 and the M4 plan's section
;; 4.1: each setting's name, its op's value in C, and its domain.
(define db-config-written
  '((enable-load-extension 1005 (#t #f)) (defensive 1010 (#t #f)) (dqs-dml 1013 (#t #f))
    (dqs-ddl 1014 (#t #f))))

(define db-config-names-written '(enable-load-extension defensive dqs-dml dqs-ddl))

;; Every SQLITE_DBCONFIG_ op of the floor's sqlite3.h, 3.45.1's (sha256
;; 41e066ccd4f89e938f136ceb48c996c54dc381b59fe566dea48864c3750b779e), and of
;; the current lane's, 3.54.1's (sha256
;; d6c84557261893439b341d2e6c35187ae3ea24fbfd843ad94616f72d89242b8c), each
;; by its name under ADR-0021's rule, SQLITE_DBCONFIG_ dropped, lower-cased,
;; _ turned to -, and its value. SQLITE_DBCONFIG_MAX, which bounds the ops,
;; is none. 3.45.1 has 1000 to 1019; 3.54.1 adds 1020 to 1023.
(define dbconfig-ops
  '((maindbname . 1000) (lookaside . 1001) (enable-fkey . 1002) (enable-trigger . 1003)
    (enable-fts3-tokenizer . 1004) (enable-load-extension . 1005) (no-ckpt-on-close . 1006)
    (enable-qpsg . 1007) (trigger-eqp . 1008) (reset-database . 1009) (defensive . 1010)
    (writable-schema . 1011) (legacy-alter-table . 1012) (dqs-dml . 1013) (dqs-ddl . 1014)
    (enable-view . 1015) (legacy-file-format . 1016) (trusted-schema . 1017)
    (stmt-scanstatus . 1018) (reverse-scanorder . 1019) (enable-attach-create . 1020)
    (enable-attach-write . 1021) (enable-comments . 1022) (fp-digits . 1023)))

(define other-ops
  (filter (lambda (p) (not (memq (car p) db-config-names-written))) dbconfig-ops))

;; step-expected : Symbol Any -> Any
;; The step for one of the four and VALUE, written out from ADR-0021's
;; decisions 3 and 5: #t is (name op 1 #t); #f is (name op 0 #f), but
;; enable-load-extension's #f makes no call, no-call (Q15); any other value
;; is outside the domain.
(define (step-expected name value)
  (let ((op (cdr (assq name dbconfig-ops))))
    (cond ((eq? value #t) (list name op 1 #t))
          ((and (eq? value #f) (eq? name 'enable-load-extension)) 'no-call)
          ((eq? value #f) (list name op 0 #f))
          (else 'out-of-domain))))

(test-equal "db-config-settings, written out: the four, each its name, its op and its domain, #t or #f, in the plan's table order"
  db-config-written
  db-config-settings)

(test-equal "db-config-setting-names, written out: the four, in the table's order"
  '(enable-load-extension defensive dqs-dml dqs-ddl)
  db-config-setting-names)

(test-equal "the ops of 3.45.1's and 3.54.1's headers: 24 names, each distinct, each value distinct, the four among them at the table's ops"
  '(24 24 24 ((enable-load-extension . 1005) (defensive . 1010) (dqs-dml . 1013) (dqs-ddl . 1014)))
  (list (length dbconfig-ops)
        (length (fold-left (lambda (acc p) (if (memq (car p) acc) acc (cons (car p) acc))) '()
                           dbconfig-ops))
        (length (fold-left (lambda (acc p) (if (memv (cdr p) acc) acc (cons (cdr p) acc))) '()
                           dbconfig-ops))
        (filter (lambda (p) (memq (car p) db-config-names-written)) dbconfig-ops)))

(test-equal "the four stay out of the live list until slice 3: setting-names holds none of them, nor they one of its, and settings-plan refuses each, #t and #f, as an unknown setting, naming it"
  (list '() '()
        (map (lambda (s) (list 'refused 'unknown-setting (car s)))
             '((enable-load-extension . #t) (enable-load-extension . #f) (defensive . #t)
               (defensive . #f) (dqs-dml . #t) (dqs-dml . #f) (dqs-ddl . #t) (dqs-ddl . #f))))
  (list (filter (lambda (n) (memq n setting-names)) db-config-setting-names)
        (filter (lambda (n) (memq n db-config-setting-names)) setting-names)
        (map (lambda (s) (plan (list s)))
             '((enable-load-extension . #t) (enable-load-extension . #f) (defensive . #t)
               (defensive . #f) (dqs-dml . #t) (dqs-dml . #f) (dqs-ddl . #t) (dqs-ddl . #f)))))

(test-equal "each step, written out: #t sets 1 and #f 0, each to its op, the value asked expected; enable-load-extension's #f makes no call (Q15)"
  '((enable-load-extension 1005 1 #t) no-call
    (defensive 1010 1 #t) (defensive 1010 0 #f)
    (dqs-dml 1013 1 #t) (dqs-dml 1013 0 #f)
    (dqs-ddl 1014 1 #t) (dqs-ddl 1014 0 #f))
  (list (dc-step 'enable-load-extension #t) (dc-step 'enable-load-extension #f)
        (dc-step 'defensive #t) (dc-step 'defensive #f)
        (dc-step 'dqs-dml #t) (dc-step 'dqs-dml #f)
        (dc-step 'dqs-ddl #t) (dc-step 'dqs-ddl #f)))

(test-equal "each of the four against every value of the universe: #t and #f alone accepted, each with its step, or no call; every other value, 0 and 1, the other settings' words, strings, (), pairs, chars and flonums among them, outside the domain"
  '()
  (apply append
         (map (lambda (name)
                (differences universe
                             (lambda (v) (step-expected name v))
                             (lambda (v) (dc-step name v))))
              db-config-names-written)))

;; Names near the four's: case, separators, plurals, C's spelling and the
;; prefix, the verb's name, and a space or a U+0000.
(define db-config-near-names
  (append
   '(ENABLE-LOAD-EXTENSION Enable-Load-Extension enable_load_extension enable-load-extensions
     enable-load-extension? load-extension load-extension! enable-extensions extensions extension
     enable-extension-loading SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION ENABLE_LOAD_EXTENSION
     DEFENSIVE Defensive defensive? defense defensive-mode SQLITE_DBCONFIG_DEFENSIVE
     DQS-DML dqs_dml dqs-dmls dqs dqs-dml-ddl dqs-ddl-dml dqs-DML DQS-DDL dqs_ddl dqs-ddls
     SQLITE_DBCONFIG_DQS_DML SQLITE_DBCONFIG_DQS_DDL db-config dbconfig db-config-settings)
   (map string->symbol '("defensive " " defensive" "dqs dml" "dqs-ddl\x0;"
                         "enable-load-extension\x0;"))))

;; Every other name: the list's own seven, every other op's by the rule,
;; trusted-schema among them, the near names, every PRAGMA in both
;; spellings, every name (chezscheme) exports; and names that are no
;; symbol, the four's own as strings among them. The seven are the suite's
;; own, names, written out, never the library's setting-names: read here, at
;; top level, a setting-names that is no list would raise and end the suite
;; with no row named, and slice 3's join puts the four in it.
(define not-db-config-names
  (append names (map car other-ops) db-config-near-names left-out
          (if (list? chez-names) chez-names '())
          (list "defensive" "dqs-dml" "enable-load-extension" 1005 1010 #t #f '() '(defensive)
                (cons 'defensive #t) #\d (vector 'defensive))))

(test-equal "the names, against the whole complement: no name but the four is a db_config setting, at #t or at #f: the list's seven, every other op of the headers by the rule, the near names, every PRAGMA, every name (chezscheme) exports, and the four's names as strings"
  '()
  (differences not-db-config-names
               (lambda (n) '(not-db-config not-db-config))
               (lambda (n) (list (dc-step n #t) (dc-step n #f)))))

(test-equal "a name that is none of the four is no db_config setting at every value of the universe, the name told before the value: the list's seven, every other op of the headers, a near name, the four's names as strings, a number and ()"
  '()
  (apply append
         (map (lambda (n)
                (differences universe (lambda (v) 'not-db-config) (lambda (v) (dc-step n v))))
              (append names (map car other-ops)
                      (list 'DEFENSIVE 'enable_load_extension "defensive" "dqs-dml" 1010 '())))))

(test-equal "every other op of the headers, named by the rule, is refused by settings-plan as an unknown setting, but trusted-schema, which stays ADR-0018's PRAGMA (Q7)"
  '()
  (differences (map car other-ops)
               (lambda (n)
                 (if (eq? n 'trusted-schema)
                     (list 'settings 32 (list (step-of 'trusted-schema #t)))
                     (list 'refused 'unknown-setting n)))
               (lambda (n) (plan (list (cons n #t))))))

;; sentinel-shape : Any -> Any
;; Whether S can be the cell's sentinel: an exact integer a C int holds,
;; -2^31 to 2^31-1, so the cell holds it as written, and neither 0 nor 1,
;; which a set writes; else why not.
(define (sentinel-shape s)
  (cond ((not (and (integer? s) (exact? s))) (list 'no-exact-integer s))
        ((memv s '(0 1)) (list 'a-value-a-set-writes s))
        ((or (< s (- two31)) (> s (- two31 1))) (list 'outside-a-c-int s))
        (else 'a-sentinel)))

(test-equal "db-config-sentinel, what the cell holds before the call: an exact integer within a C int, so the cell holds it as written, and neither 0 nor 1, which a set writes (ADR-0021, decision 3)"
  'a-sentinel
  (sentinel-shape db-config-sentinel))

(test-equal "the verdict, written out: code 0 and the value written match; code 0 and another cell mismatch, the value read #t for 1, #f for 0, any other integer as itself; any other code is an error with that code, whatever the cell: 1, an op the library lacks; Apple's 21; -1"
  '(match match match match
    (mismatch defensive #t #f) (mismatch defensive #f #t)
    (mismatch dqs-dml #t 2) (mismatch dqs-ddl #f -2) (mismatch enable-load-extension #t 1005)
    (error 1) (error 1) (error 21) (error 21) (error -1))
  (list (dc-verdict 'defensive #t 0 1) (dc-verdict 'defensive #f 0 0)
        (dc-verdict 'enable-load-extension #t 0 1) (dc-verdict 'dqs-ddl #f 0 0)
        (dc-verdict 'defensive #t 0 0) (dc-verdict 'defensive #f 0 1)
        (dc-verdict 'dqs-dml #t 0 2) (dc-verdict 'dqs-ddl #f 0 -2)
        (dc-verdict 'enable-load-extension #t 0 1005)
        (dc-verdict 'dqs-dml #t 1 1) (dc-verdict 'defensive #f 1 0)
        (dc-verdict 'enable-load-extension #t 21 db-config-sentinel)
        (dc-verdict 'enable-load-extension #t 21 1)
        (dc-verdict 'dqs-ddl #f -1 0)))

(test-equal "a cell the call left at its sentinel, with code 0, is a mismatch whose value read is (), nothing read, for each of the four and each value"
  '((mismatch enable-load-extension #t ()) (mismatch enable-load-extension #f ())
    (mismatch defensive #t ()) (mismatch defensive #f ())
    (mismatch dqs-dml #t ()) (mismatch dqs-dml #f ())
    (mismatch dqs-ddl #t ()) (mismatch dqs-ddl #f ()))
  (list (dc-verdict 'enable-load-extension #t 0 db-config-sentinel)
        (dc-verdict 'enable-load-extension #f 0 db-config-sentinel)
        (dc-verdict 'defensive #t 0 db-config-sentinel) (dc-verdict 'defensive #f 0 db-config-sentinel)
        (dc-verdict 'dqs-dml #t 0 db-config-sentinel) (dc-verdict 'dqs-dml #f 0 db-config-sentinel)
        (dc-verdict 'dqs-ddl #t 0 db-config-sentinel) (dc-verdict 'dqs-ddl #f 0 db-config-sentinel)))

(test-equal "a value asked outside the domain matches no cell: code 0 with 1, 0, #f, the sentinel or the value itself is a mismatch, the value asked as given; another code is still an error"
  '((mismatch defensive 1 #t) (mismatch defensive 0 #f) (mismatch defensive on #t)
    (mismatch defensive () ()) (mismatch defensive x x) (mismatch defensive #f #f) (error 1))
  (list (dc-verdict 'defensive 1 0 1) (dc-verdict 'defensive 0 0 0) (dc-verdict 'defensive 'on 0 1)
        (dc-verdict 'defensive '() 0 db-config-sentinel) (dc-verdict 'defensive 'x 0 'x)
        (dc-verdict 'defensive #f 0 #f) (dc-verdict 'defensive 1 1 1)))

;; The codes and cells the verdict is held over: 0 and SQLite's codes, ok,
;; error, busy, cantopen, row, done and an extended ok among them; the
;; edges of a C int and past them; inexact zeros and a fraction; and values
;; no int is. Each cell beside 0, 1 and the sentinel.
(define verdict-codes
  (list 0 1 21 5 14 100 101 256 -1 (- two31) (- two31 1) two31 (expt 2 64)
        0.0 -0.0 1.5 'ok 'error "0" #f #t '() '(0)))

(define verdict-cells
  (list 0 1 db-config-sentinel 2 -2 5 100 1005 (- two31 1) (- two31) (expt 2 32)
        0.0 1.0 #t #f '() 'x "1"))

;; verdict-expected : Symbol Boolean Any Any -> Any
;; ADR-0021's decision 3, written out: any code but 0 is an error with that
;; code, whatever the cell; code 0 and the cell the value written, 1 for #t,
;; 0 for #f, match; code 0 and any other cell mismatch, the value read ()
;; for the sentinel, #t for 1, #f for 0, and anything else as itself.
(define (verdict-expected name value code cell)
  (cond ((not (eqv? code 0)) (list 'error code))
        ((eqv? cell (if value 1 0)) 'match)
        (else (list 'mismatch name value
                    (cond ((eqv? cell db-config-sentinel) '())
                          ((eqv? cell 1) #t)
                          ((eqv? cell 0) #f)
                          (else cell))))))

(test-equal "the verdict, for each of the four and each value asked, over every code against every cell: the whole answer"
  '()
  (apply append
         (map (lambda (name)
                (apply append
                       (map (lambda (value)
                              (apply append
                                     (map (lambda (code)
                                            (differences verdict-cells
                                                         (lambda (cell)
                                                           (verdict-expected name value code cell))
                                                         (lambda (cell)
                                                           (dc-verdict name value code cell))))
                                          verdict-codes)))
                            '(#t #f))))
              db-config-names-written)))

(test-equal "the step and the verdict raise nothing for any value, as any name, value, code or cell"
  '()
  (filter (lambda (r) (and (pair? r) (eq? (car r) 'raised)))
          (apply append
                 (map (lambda (v)
                        (list (dc-step v v) (dc-step 'defensive v) (dc-step 'enable-load-extension v)
                              (dc-step v #t) (dc-verdict v v v v) (dc-verdict 'defensive #t v v)
                              (dc-verdict 'defensive v 0 v) (dc-verdict 'dqs-dml #f 0 v)
                              (dc-verdict 'dqs-ddl #t v 1) (dc-verdict v #f 0 0)))
                      (append universe (list cyclic))))))

;; --- total ----------------------------------------------------------------------------

(test-equal "the split, the plan, the reader and the comparison raise nothing for any value"
  '()
  (filter (lambda (r) (and (pair? r) (eq? (car r) 'raised)))
          (apply append
                 (map (lambda (v)
                        (list (split (list v)) (plan v) (plan (list v)) (plan (list (cons v v)))
                              (read-back v v) (compared v v v) (read-back-raw v v) (compared-raw v v v)
                              (compared 'foreign-keys v v) (compared 'journal-mode v v)))
                      (append universe (list cyclic))))))

(test-end "settings")

(exit (suite-exit-status runner))
