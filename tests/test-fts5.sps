#!r6rs
;;; The suite for FTS5, SQLite's full-text search, through (chez-sqlite3)
;;; (the M4 plan, section 4.5 and Q2; ADR-0003, amended). A library compiles
;;; FTS5 in or doesn't, so the suite chooses its rows by what the library
;;; reports, and runs on every lane:
;;;
;;;   the check     (sqlite-compile-option? "ENABLE_FTS5") held to
;;;                 select count(*) from pragma_module_list where name =
;;;                 'fts5', either way; the check that compares them is
;;;                 held, in the same row, to an option without the module,
;;;                 the module without the option, a probe that raised, and
;;;                 a count neither 0 nor 1, each named
;;;   the rows      where both say yes (Guix's library, the current lane):
;;;                 MATCH with order by rank, bm25()'s order, never its
;;;                 exact REAL; diacritics folded by unicode61, and not with
;;;                 remove_diacritics 0; highlight() and snippet() over
;;;                 UTF-8; prefix, phrase, column and NOT filters; a MATCH
;;;                 given as a bound parameter; a query's syntax error at
;;;                 step, code error; delete and update
;;;   the refusal   where both say no (the floor lane): the suite prints
;;;                 "FTS5 unavailable", runs none of the rows, and asserts
;;;                 in their place that create virtual table ... using fts5
;;;                 prepares, then raises &sqlite-error, code error, at its
;;;                 step, never checked by its message
;;;
;;; The refusal's row holds the unavailable line (ADR-0005's amendment of
;;; M3's closing review): a library with FTS5 answers done at that create's
;;; step, where the rows' first row asserts it, so a check that takes the
;;; refusal wrongly fails by name wherever FTS5 is.
;;;
;;; FTS5 prepares statements of its own on the connection, for its shadow
;;; tables, from the create on, and finalizes them only when its table is
;;; disconnected: by a drop, or by sqlite3_close. close-database! finalizes
;;; its own statements and calls sqlite3_close before it counts any, and
;;; counts only when SQLite refuses (ADR-0012, amended), so every row here
;;; closes with its FTS5 tables in place. One row closes, outside
;;; call-with-database, a connection that made, filled and queried one.
;;;
;;; Every value a row asserts is the research's (.plans/research/m4-plan/,
;;; F1 and F2), the same on Guix's 3.53.1 and the FTS5 build of 3.54.1, and
;;; the refusal the same on 3.45.1 and the plain 3.54.1, but two, measured in
;;; the slice's review on those libraries and on 3.45.1 with FTS5
;;; (.plans/m4-slice-5-mutation-log.md): "sqlite OR rank" ranks 3 before 2,
;;; where rowid order is 2 then 3, so the rank rows can tell the orders
;;; apart; and the phrase "text full" matches nothing, where the words'
;;; AND matches 2, so the phrase row can tell a phrase from an AND. The
;;; bound MATCH's row asserts its parameter's typeof, text, so a string bound
;;; as a BLOB, which FTS5 reads as text, fails it. The agreement row holds
;;; the check against its complement: a probe that raised, and a module
;;; count neither 0 nor 1, with each answer of the option. The rows go through
;;; the conveniences and the statement verbs, so they test the values' path
;;; through the library, not SQLite: UTF-8 in SQL text and bound strings,
;;; rows read back as vectors of exact integers, flonums and strings.
;;;
;;; The library is reached through eval, under a guard, as
;;; tests/test-conveniences.sps reaches it. Every computation that can raise
;;; runs under a guard that answers what was raised; no expected value is #f.
;;; Effects run in order, through let* and named lets, never map (AGENTS.md).
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3) sqlite-error? sqlite-error-code sqlite-error-extended-code
              sqlite-error-sql sqlite-error-offset))

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

;; --- reached through eval -------------------------------------------------------------

(define public-load
  (guard (e (#t (list 'raised (describe e))))
    (eval '(sqlite-version) (environment '(chez-sqlite3)))
    'loaded))

;; reach : Symbol -> Procedure
;; NAME's procedure in (chez-sqlite3); when it cannot be reached, one that
;; raises that, naming NAME, every time it is called.
(define (reach name)
  (guard (e (#t (lambda args (error name "could not be reached" (describe e)))))
    (eval name (environment '(chez-sqlite3)))))

(define call-with-database (reach 'call-with-database))
(define open-database (reach 'open-database))
(define close-database! (reach 'close-database!))
(define execute! (reach 'execute!))
(define query (reach 'query))
(define query-row (reach 'query-row))
(define call-with-statement (reach 'call-with-statement))
(define bind-all! (reach 'bind-all!))
(define step! (reach 'step!))
(define sqlite-compile-option? (reach 'sqlite-compile-option?))

;; --- helpers ------------------------------------------------------------------------------

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

(define (who-of e) (if (who-condition? e) (condition-who e) 'no-who))

;; what-raised : Any -> Any
;; A &sqlite-error as its who, code, extended code, SQL and offset, never its
;; message; anything else as its text.
(define (what-raised e)
  (if (sqlite-error? e)
      (list 'sqlite-error (who-of e) (sqlite-error-code e) (sqlite-error-extended-code e)
            (sqlite-error-sql e) (sqlite-error-offset e))
      (list 'raised (describe e))))

;; answer : (-> A) -> (U A (List 'sqlite-error ...) (List 'raised String))
(define (answer thunk)
  (guard (e (#t (what-raised e)))
    (thunk)))

;; with-db : (Database -> A) -> A
(define (with-db proc)
  (call-with-database ":memory:" proc))

;; stepped : Database String Value ... -> Any
;; SQL prepared, VALUES bound, then stepped once: (prepared row) or
;; (prepared done); (prepared step-raised RAISED) when the step raised; or
;; what the prepare raised, whose who is call-with-statement's.
(define (stepped db sql . values)
  (answer
   (lambda ()
     (call-with-statement db sql
       (lambda (st)
         (apply bind-all! st values)
         (guard (e (#t (list 'prepared 'step-raised (what-raised e))))
           (list 'prepared (if (step! st) 'row 'done))))))))

;; step-error : String -> Any
;; What stepped answers when the step of SQL raises SQLite's error, code 1.
(define (step-error sql)
  (list 'prepared 'step-raised (list 'sqlite-error 'step! 'error 'error sql #f)))

;; --- the check ---------------------------------------------------------------------------

(define module-sql "select count(*) from pragma_module_list where name = 'fts5'")

;; fts5-option : (U Boolean (List 'raised ...))
(define fts5-option
  (answer (lambda () (sqlite-compile-option? "ENABLE_FTS5"))))

;; fts5-module : (U Integer (List 'raised ...))
;; The count pragma_module_list answers for fts5: 1 where it is, 0 where not.
(define fts5-module
  (answer (lambda () (with-db (lambda (db) (vector-ref (query-row db module-sql) 0))))))

;; agreement : Any Any -> (U 'agree (List 'disagree Any Any))
;; Whether OPTION and MODULE say the same: #t and 1, or #f and 0. Anything
;; else, a probe that raised among it, is named.
(define (agreement option module)
  (if (or (and (eq? option #t) (eqv? module 1))
          (and (eq? option #f) (eqv? module 0)))
      'agree
      (list 'disagree option module)))

;; path : (U 'rows 'refusal 'neither)
(define path
  (cond ((not (eq? (agreement fts5-option fts5-module) 'agree)) 'neither)
        ((eq? fts5-option #t) 'rows)
        (else 'refusal)))

(test-begin "fts5")

(test-equal "(chez-sqlite3) loads, reached through eval"
  'loaded
  public-load)

(test-equal "every count is zero once the load has returned"
  zero-counts
  (native-counts))

(test-equal "ENABLE_FTS5 and pragma_module_list's fts5 agree on this library, either way; the check that compares them names an option without the module, a module without the option, a probe that raised, and a count neither 0 nor 1"
  '(agree (disagree #t 0) (disagree #f 1)
          (disagree #f (raised "x")) (disagree #t (raised "x"))
          (disagree (raised "x") 0) (disagree (raised "x") 1)
          (disagree #t 2) (disagree #f 2))
  (list (agreement fts5-option fts5-module) (agreement #t 0) (agreement #f 1)
        (agreement #f '(raised "x")) (agreement #t '(raised "x"))
        (agreement '(raised "x") 0) (agreement '(raised "x") 1)
        (agreement #t 2) (agreement #f 2)))

;; --- the rows, where FTS5 is ---------------------------------------------------------------

;; The research's table: three documents, the first in UTF-8 beyond ASCII.
(define docs-create "create virtual table docs using fts5(title, body)")
(define docs-insert
  (string-append
   "insert into docs(rowid, title, body) values"
   " (1, 'Élan vital', 'the café serves crème brûlée'),"
   " (2, 'Second', 'sqlite full text search with fts5'),"
   " (3, 'Third', 'search engines rank documents and sqlite ranks them too')"))

;; with-docs : (Database -> A) -> A
;; PROC's answer on a fresh :memory: database holding the table docs.
(define (with-docs proc)
  (with-db
   (lambda (db)
     (execute! db docs-create)
     (execute! db docs-insert)
     (proc db))))

;; matching : Database String -> (Listof Row)
;; The rowids that match QUERY, in rowid order.
(define (matching db query-text)
  (query db (string-append "select rowid from docs where docs match '" query-text
                           "' order by rowid")))

;; ascending-negative-reals? : (Listof Any) -> Boolean
;; Each a flonum below 0, each below the next.
(define (ascending-negative-reals? xs)
  (and (for-all flonum? xs)
       (for-all (lambda (x) (< x 0.0)) xs)
       (let loop ((xs xs))
         (or (null? xs) (null? (cdr xs))
             (and (< (car xs) (cadr xs)) (loop (cdr xs)))))))

(define syntax-errors
  '("select rowid from docs where docs match '\"unterminated'"
    "select rowid from docs where docs match 'nosuchcolumn:x'"
    "select rowid from docs where docs match 'AND'"))

(define (fts5-rows)
  (test-equal "create virtual table ... using fts5 prepares, and its step answers done"
    '(prepared done)
    (answer
     (lambda ()
       (with-db
        (lambda (db) (stepped db "create virtual table probe using fts5(body)"))))))

  (test-equal "MATCH with order by rank: sqlite OR rank matches 3 then 2, not in rowid order"
    '(#(3) #(2))
    (answer
     (lambda ()
       (with-docs
        (lambda (db) (query db "select rowid from docs where docs match 'sqlite OR rank' order by rank"))))))

  (test-equal "order by rank is bm25()'s order: sqlite OR rank matches 3 then 2, each bm25 a negative flonum below the next"
    '((3 2) #t)
    (answer
     (lambda ()
       (with-docs
        (lambda (db)
          (let ((rows (query db "select rowid, bm25(docs) from docs where docs match 'sqlite OR rank' order by rank")))
            (list (map (lambda (row) (vector-ref row 0)) rows)
                  (ascending-negative-reals? (map (lambda (row) (vector-ref row 1)) rows)))))))))

  (test-equal "unicode61 folds diacritics: cafe, café and creme each match document 1"
    '((#(1)) (#(1)) (#(1)))
    (answer
     (lambda ()
       (with-docs
        (lambda (db)
          (let* ((cafe (matching db "cafe"))
                 (cafe-accented (matching db "café"))
                 (creme (matching db "creme")))
            (list cafe cafe-accented creme)))))))

  (test-equal "with remove_diacritics 0, cafe matches no café, and café matches it"
    '(#(0) #(1))
    (answer
     (lambda ()
       (with-db
        (lambda (db)
          (execute! db "create virtual table t2 using fts5(x, tokenize = 'unicode61 remove_diacritics 0')")
          (execute! db "insert into t2 values ('café')")
          (let* ((plain (query-row db "select count(*) from t2 where t2 match 'cafe'"))
                 (accented (query-row db "select count(*) from t2 where t2 match 'café'")))
            (list plain accented)))))))

  (test-equal "highlight() and snippet() answer UTF-8 text, marked: the body's café, the title's Élan, and a snippet of three tokens"
    '(#("the [café] serves crème brûlée") #("[Élan] vital") #("search <engines> rank..."))
    (answer
     (lambda ()
       (with-docs
        (lambda (db)
          (let* ((body (query-row db "select highlight(docs, 1, '[', ']') from docs where docs match 'café'"))
                 (title (query-row db "select highlight(docs, 0, '[', ']') from docs where docs match 'elan'"))
                 (snippet (query-row db "select snippet(docs, 1, '<', '>', '...', 3) from docs where docs match 'engines'")))
            (list body title snippet)))))))

  (test-equal "a prefix query: searc* matches 2 and 3"
    '(#(2) #(3))
    (answer (lambda () (with-docs (lambda (db) (matching db "searc*"))))))

  (test-equal "a phrase query: \"full text\" matches 2, and \"text full\" nothing, though both words are in 2"
    '((#(2)) ())
    (answer
     (lambda ()
       (with-docs
        (lambda (db)
          (let* ((phrase (matching db "\"full text\""))
                 (reversed (matching db "\"text full\"")))
            (list phrase reversed)))))))

  (test-equal "a column filter: title:second matches 2, and title:sqlite nothing, though bodies hold sqlite"
    '((#(2)) ())
    (answer
     (lambda ()
       (with-docs
        (lambda (db)
          (let* ((second (matching db "title:second"))
                 (sqlite (matching db "title:sqlite")))
            (list second sqlite)))))))

  (test-equal "NOT: sqlite NOT fts5 matches 3 alone"
    '(#(3))
    (answer (lambda () (with-docs (lambda (db) (matching db "sqlite NOT fts5"))))))

  (test-equal "a MATCH given as a bound parameter, \"sqlite OR café\", matches 1, 2 and 3, bound as TEXT"
    '(#(1 "text") #(2 "text") #(3 "text"))
    (answer
     (lambda ()
       (with-docs
        (lambda (db)
          (query db "select rowid, typeof(?1) from docs where docs match ?1 order by rowid" "sqlite OR café"))))))

  (test-equal "a query's syntax error through query: a bare AND raises &sqlite-error from query, code error, with its SQL and no place"
    (list 'sqlite-error 'query 'error 'error (caddr syntax-errors) #f)
    (answer
     (lambda ()
       (with-docs
        (lambda (db) (query db (caddr syntax-errors)))))))

  (test-equal "a query's syntax error, an unterminated string, an unknown column or a bare AND, prepares, then raises &sqlite-error at its step, code error"
    (map step-error syntax-errors)
    (answer
     (lambda ()
       (with-docs
        (lambda (db)
          (let loop ((sqls syntax-errors) (found '()))
            (if (null? sqls)
                (reverse found)
                (loop (cdr sqls) (cons (stepped db (car sqls)) found)))))))))

  (test-equal "delete and update: after deleting 2 and setting 3's body to fts5 again, fts5 matches 3 alone, and optimize and integrity-check leave 2 rows"
    '((#(3)) #(2))
    (answer
     (lambda ()
       (with-docs
        (lambda (db)
          (execute! db "delete from docs where rowid = 2")
          (execute! db "update docs set body = 'fts5 again' where rowid = 3")
          (let ((found (matching db "fts5")))
            (execute! db "insert into docs(docs) values ('optimize')")
            (execute! db "insert into docs(docs) values ('integrity-check')")
            (list found (query-row db "select count(*) from docs"))))))))

  (test-equal "a connection that made and queried an FTS5 table closes, with no drop first"
    'closed
    (answer
     (lambda ()
       (let* ((db (open-database ":memory:"))
              (outcome (answer
                        (lambda ()
                          (execute! db docs-create)
                          (execute! db docs-insert)
                          (matching db "sqlite")
                          (close-database! db)
                          'closed))))
         ;; Only where the close refused, as the old close did: the drop
         ;; lets a second close finish, so the counts row judges the rows
         ;; after this one, not this one's connection.
         (unless (eq? outcome 'closed)
           (execute! db "drop table if exists docs")
           (close-database! db))
         outcome))))
  'ran)

;; --- the refusal, where FTS5 is not -----------------------------------------------------------

(define (fts5-refusal)
  (display "FTS5 unavailable: this libsqlite3 has neither ENABLE_FTS5 nor the fts5 module, so the FTS5 rows are not run; the refusal is asserted in their place")
  (newline)
  (test-equal "FTS5 unavailable: create virtual table ... using fts5 prepares, then raises &sqlite-error at its step, code error"
    (step-error "create virtual table probe using fts5(body)")
    (answer
     (lambda ()
       (with-db
        (lambda (db) (stepped db "create virtual table probe using fts5(body)"))))))
  'ran)

(case path
  ((rows) (fts5-rows))
  ((refusal) (fts5-refusal))
  (else 'neither))

(test-equal "every count is zero after the rows"
  zero-counts
  (native-counts))

(test-end "fts5")

(exit (suite-exit-status runner))
