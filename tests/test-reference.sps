#!r6rs
;;; docs/reference.md holds one entry for every export of (chez-sqlite3), and
;;; nothing else, each with a NAME : TYPE line whose type fits what the name
;;; is.
;;;
;;; The oracles: the names (chez-sqlite3) exports, as Chez's library-exports
;;; lists them, never as the library's text writes them; and what each name
;;; is, as Chez evaluates it in the library's environment: a procedure, or
;;; another value (syntax, too, which this library exports none of, would
;;; fail the suite). No code comment is read. And the page, read as
;;; CommonMark is: its ATX headings outside fenced blocks, and the lines of
;;; each fenced block whose info string's first word is text, in any case.
;;;
;;; The shape the page is held to:
;;; - a ### heading is an entry: one name in code, as "### `open-database`";
;;;   it runs to the next heading of level 1, 2 or 3. A ### heading of any
;;;   other shape fails, by its line;
;;; - an entry holds exactly one text block, of one line, "NAME : TYPE", the
;;;   same NAME as its heading; a procedure's TYPE holds ->, and a value's
;;;   does not;
;;; - every export has exactly one entry, and every entry is an export.
;;;
;;; Out of its reach, with no oracle but a reader's reading of the code: a
;;; type that is wrong, so long as a procedure's holds -> and a value's does
;;; not.
;;;
;;; The page is read as CommonMark is: its ATX headings outside fenced
;;; blocks, and each fenced block, opened by up to three spaces and three or
;;; more backticks or tildes, closed by a fence of its own character, at
;;; least as long, and nothing after. One no fence closes runs to the page's
;;; end. A block's language is its info string's first word, in any case.
;;; The reader is held to all of it on texts of the suite's own before it
;;; reads a file.
;;;
;;; Names are compared as whole sorted lists, with the missing, the extra
;;; and the differing each asserted empty on its own, so a failure shows what
;;; differs. No assertion depends on an order. Each computation that can
;;; raise runs under a guard that answers what was raised, since SRFI-64
;;; turns a raise in the actual expression into #f; no expected value is #f.
;;; make test runs every suite from the repository root.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (chez-sqlite3-testing)
        (only (chezscheme) library-exports copy-environment interaction-environment)
        (prefix (only (chezscheme) eval) chez:))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "reference")

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

;; --- reading text ----------------------------------------------------------------

;; slurp : String -> String
;; The file's text, read as UTF-8.
(define (slurp path)
  (call-with-port
   (open-file-input-port path (file-options) (buffer-mode block)
                         (make-transcoder (utf-8-codec)))
   (lambda (port)
     (let ((text (get-string-all port)))
       (if (eof-object? text) "" text)))))

;; text-lines : String -> (Listof String)
;; The text split at each newline, a newline that ends it ending its last.
(define (text-lines s)
  (let loop ((cs (string->list s)) (line '()) (out '()))
    (cond ((null? cs)
           (reverse (if (null? line) out (cons (list->string (reverse line)) out))))
          ((char=? (car cs) #\newline)
           (loop (cdr cs) '() (cons (list->string (reverse line)) out)))
          (else (loop (cdr cs) (cons (car cs) line) out)))))

;; blank? : Char -> Boolean
(define (blank? c) (or (char=? c #\space) (char=? c #\tab)))

;; trim : String -> String
(define (trim s)
  (let* ((n (string-length s))
         (i (let loop ((i 0)) (if (and (< i n) (blank? (string-ref s i))) (loop (+ i 1)) i)))
         (j (let loop ((j n)) (if (and (> j i) (blank? (string-ref s (- j 1)))) (loop (- j 1)) j))))
    (substring s i j)))

;; starts? : String String -> Boolean
(define (starts? s prefix)
  (and (>= (string-length s) (string-length prefix))
       (string=? (substring s 0 (string-length prefix)) prefix)))

;; run : String Natural Char -> Natural
;; How many of C begin at I.
(define (run s i c)
  (let loop ((j i))
    (if (and (< j (string-length s)) (char=? (string-ref s j) c)) (loop (+ j 1)) (- j i))))

;; words : String -> (Listof String)
(define (words s)
  (let loop ((cs (string->list s)) (w '()) (out '()))
    (define (flush) (if (null? w) out (cons (list->string (reverse w)) out)))
    (cond ((null? cs) (reverse (flush)))
          ((blank? (car cs)) (loop (cdr cs) '() (flush)))
          (else (loop (cdr cs) (cons (car cs) w) out)))))

;; ascii-downcase : String -> String
(define (ascii-downcase s)
  (list->string (map (lambda (c) (if (and (char<=? #\A c) (char<=? c #\Z))
                                     (integer->char (+ (char->integer c) 32))
                                     c))
                     (string->list s))))

;; sort-strings : (Listof String) -> (Listof String)
(define (sort-strings l) (list-sort string<? l))

;; --- the page: headings and fenced blocks -----------------------------------------

;; An item of a page, in order: (heading LINE LEVEL TEXT) or
;; (block LINE LANGUAGE LINES CLOSED?).

;; fence : String -> (U (List Char Natural Natural String) #f)
;; The line as a fence that opens a block: its character, how many, its
;; indent, and its info string, trimmed. A backtick fence's info holds no
;; backtick.
(define (fence line)
  (let ((indent (run line 0 #\space)) (n (string-length line)))
    (and (<= indent 3) (< indent n)
         (let ((c (string-ref line indent)))
           (and (memv c '(#\` #\~))
                (let* ((k (run line indent c))
                       (info (trim (substring line (+ indent k) n))))
                  (and (>= k 3)
                       (not (and (char=? c #\`) (memv #\` (string->list info))))
                       (list c k indent info))))))))

;; closes? : String (List Char Natural Natural String) -> Boolean
(define (closes? line open)
  (let ((indent (run line 0 #\space)))
    (and (<= indent 3)
         (let ((k (run line indent (car open))))
           (and (>= k (cadr open))
                (string=? (trim (substring line (+ indent k) (string-length line))) ""))))))

;; heading-of : String -> (U (Pair Natural String) #f)
;; The line as an ATX heading: up to three spaces, one to six #, a blank or
;; the line's end, then the text, trimmed.
(define (heading-of line)
  (let* ((indent (run line 0 #\space)) (n (string-length line)))
    (and (<= indent 3)
         (let ((k (run line indent #\#)))
           (and (<= 1 k 6)
                (or (= (+ indent k) n) (blank? (string-ref line (+ indent k))))
                (cons k (trim (substring line (+ indent k) n))))))))

;; page-items : String -> (Listof Item)
(define (page-items text)
  (define (block-item open line body closed?)
    (let ((ws (words (cadddr open))))
      (list 'block line (if (null? ws) "" (ascii-downcase (car ws))) (reverse body) closed?)))
  (let loop ((ls (text-lines text)) (n 1) (open #f) (start 0) (body '()) (out '()))
    (cond ((null? ls)
           (reverse (if open (cons (block-item open start body #f) out) out)))
          (open
           (if (closes? (car ls) open)
               (loop (cdr ls) (+ n 1) #f 0 '() (cons (block-item open start body #t) out))
               (loop (cdr ls) (+ n 1) open start (cons (car ls) body) out)))
          ((fence (car ls))
           => (lambda (f) (loop (cdr ls) (+ n 1) f n '() out)))
          ((heading-of (car ls))
           => (lambda (h) (loop (cdr ls) (+ n 1) #f 0 '() (cons (list 'heading n (car h) (cdr h)) out))))
          (else (loop (cdr ls) (+ n 1) #f 0 '() out)))))

;; entry-name : String -> (U Symbol #f)
;; The one name a ### heading's text holds, in code, as `open-database`.
(define (entry-name text)
  (let ((n (string-length text)))
    (and (>= n 3)
         (char=? (string-ref text 0) #\`)
         (char=? (string-ref text (- n 1)) #\`)
         (for-all (lambda (c) (not (or (char=? c #\`) (blank? c))))
                  (string->list (substring text 1 (- n 1))))
         (string->symbol (substring text 1 (- n 1))))))

;; page-entries : (Listof Item) -> (Listof (List Natural String (U Symbol #f) (Listof Item)))
;; Each ### heading, in order, as its line, its text, its name, and the
;; items up to the next heading of level 1, 2 or 3.
(define (page-entries items)
  (let loop ((rest items) (out '()))
    (cond ((null? rest) (reverse out))
          ((and (eq? (car (car rest)) 'heading) (= (caddr (car rest)) 3))
           (let take ((more (cdr rest)) (held '()))
             (if (or (null? more)
                     (and (eq? (car (car more)) 'heading) (<= (caddr (car more)) 3)))
                 (loop more (cons (list (cadr (car rest)) (cadddr (car rest))
                                        (entry-name (cadddr (car rest))) (reverse held))
                                  out))
                 (take (cdr more) (cons (car more) held)))))
          (else (loop (cdr rest) out)))))

;; entry-signature : Entry -> (U String (List 'text-blocks Natural) (List 'lines Natural))
;; The one line of the entry's one text block; else how many of each it has.
(define (entry-signature entry)
  (let ((texts (filter (lambda (i) (and (eq? (car i) 'block) (string=? (caddr i) "text")))
                       (cadddr entry))))
    (cond ((not (= (length texts) 1)) (list 'text-blocks (length texts)))
          ((not (= (length (cadddr (car texts))) 1))
           (list 'lines (length (cadddr (car texts)))))
          (else (car (cadddr (car texts)))))))

;; --- the oracle: exports and what each is ----------------------------------------

;; The library, as Chez names it.
(define library '(chez-sqlite3))

;; exports-of : (Listof Symbol) -> (U (Listof String) (List 'raised String))
;; The names the library exports, as Chez's library-exports lists them,
;; sorted; the library is first imported into an environment, so Chez has
;; it. Or (raised WHAT) for a raise.
(define (exports-of library)
  (guard (e (#t (list 'raised (describe e))))
    (environment library)
    (list-sort string<? (map symbol->string (library-exports library)))))

;; kind-in : Environment String -> (U 'syntax 'procedure 'value (List 'raised String))
;; What NAME is, as Chez evaluates it in ENV: syntax, when evaluating it is
;; a syntax violation; a procedure; a value; or (raised WHAT) for any other
;; raise.
(define (kind-in env name)
  (guard (e ((syntax-violation? e) 'syntax)
            (#t (list 'raised (describe e))))
    (let ((v (eval (string->symbol name) env)))
      (if (procedure? v) 'procedure 'value))))

;; has-arrow? : String -> Boolean
;; Whether the type holds ->.
(define (has-arrow? type)
  (let loop ((i 0))
    (cond ((> (+ i 2) (string-length type)) #f)
          ((string=? (substring type i (+ i 2)) "->") #t)
          (else (loop (+ i 1))))))

;; line-type : String String -> (U String #f)
;; The TYPE of a line "NAME : TYPE" for this NAME, else #f.
(define (line-type name line)
  (let ((lead (string-append name " : ")))
    (and (starts? line lead)
         (substring line (string-length lead) (string-length line)))))

;; --- the readers, on texts of the suite's own ------------------------------------------

(define sample-page
  (string-append
   "# Title\n"
   "### `inside`\n"
   "```text\n### `fenced` not a heading\n```\n"
   "### `a` and `b`\n"
   "~~~~ TEXT x\none : A -> B\n~~~\n```\n~~~~\n"
   "## Next\n"
   "### `last`\n"
   "```scheme\n(open\n"))

(define sample-items (page-items sample-page))
(define sample-entries (page-entries sample-items))

(test-equal "the page reader: its headings and blocks, a fenced line being no heading, a shorter fence or another character no close, a block no fence closes running to the end"
  '((heading 1 1 "Title")
    (heading 2 3 "`inside`")
    (block 3 "text" ("### `fenced` not a heading") #t)
    (heading 6 3 "`a` and `b`")
    (block 7 "text" ("one : A -> B" "~~~" "```") #t)
    (heading 12 2 "Next")
    (heading 13 3 "`last`")
    (block 14 "scheme" ("(open") #f))
  sample-items)

(test-equal "entries: each ### heading with its line, text, name or #f, and the items to the next heading of level 3 or less"
  '((2 "`inside`" inside 1) (6 "`a` and `b`" #f 1) (13 "`last`" last 1))
  (map (lambda (e) (list (car e) (cadr e) (caddr e) (length (cadddr e)))) sample-entries))

(test-equal "an entry's signature: its one text block's one line, else how many blocks, or lines, it has"
  '((text-blocks 2) "x" (text-blocks 0))
  (let ((e (lambda (items) (entry-signature (list 1 "t" 'n items)))))
    (list (e (list '(block 1 "text" ("a" "b") #t) '(block 2 "text" ("c") #t)))
          (e (list '(block 1 "scheme" ("y") #t) '(block 2 "text" ("x") #t)))
          (e (list '(block 1 "scheme" ("y") #t))))))

(test-equal "a text block of two lines is named by its lines"
  '(lines 2)
  (entry-signature (list 1 "t" 'n (list '(block 1 "text" ("a" "b") #t)))))

(test-equal "kind-in: a procedure, a value, syntax, and a name that is none, as Chez evaluates each"
  '(procedure value syntax raised)
  (let ((env (guard (e (#t #f))
               (let ((env (copy-environment (interaction-environment) #t)))
                 (chez:eval '(define seven 7) env)
                 env))))
    (list (kind-in env "car")
          (kind-in env "seven")
          (kind-in env "else")
          (let ((k (kind-in env "no-such-name-here"))) (if (pair? k) (car k) k)))))

(test-equal "has-arrow?, line-type: an arrow anywhere in a type; a line's type only after its own NAME and the space-colon-space"
  '(#t #f #t #f "X -> Y" #f #f)
  (list (has-arrow? "A -> B") (has-arrow? "A - > B") (has-arrow? "->") (has-arrow? "-")
        (line-type "f" "f : X -> Y") (line-type "f" "fx : X -> Y") (line-type "f" "f: X -> Y")))

;; --- the page and the library ---------------------------------------------------------

;; page-text : (U String (List 'unreadable String))
(define page-text
  (guard (e (#t (list 'unreadable (describe e)))) (slurp "docs/reference.md")))

(define export-names (exports-of library))

;; Each export, with what Chez evaluates it to, in the library's environment.
(define library-env (guard (e (#t #f)) (environment library)))
(define every-export
  (if (and library-env (list? export-names) (for-all string? export-names))
      (map (lambda (n) (cons n (kind-in library-env n))) export-names)
      '()))

(define entries
  (if (string? page-text) (page-entries (page-items page-text)) '()))

;; the entry names the page has, and the headings that are no entry
(define entry-names (map symbol->string (filter symbol? (map caddr entries))))
(define bad-headings (map (lambda (e) (list (car e) (cadr e))) (filter (lambda (e) (not (caddr e))) entries)))

;; duplicates : (Listof String) -> (Listof String)
;; The members that occur more than once, sorted, each once.
(define (duplicates l)
  (sort-strings
   (filter (lambda (x) (> (length (filter (lambda (y) (string=? x y)) l)) 1))
           (let loop ((rest l) (seen '()))
             (cond ((null? rest) (reverse seen))
                   ((member (car rest) seen) (loop (cdr rest) seen))
                   (else (loop (cdr rest) (cons (car rest) seen))))))))

;; difference : (Listof String) -> (Listof String) -> (Listof String)
;; The members of A that B lacks, sorted.
(define (difference a b)
  (sort-strings (filter (lambda (x) (not (member x b))) a)))

(test-equal "the exports are read, Chez evaluates each to a procedure or a value, and docs/reference.md reads and holds entries"
  'read
  (cond ((not (and (list? export-names) (for-all string? export-names))) (list 'exports export-names))
        ((null? export-names) 'no-exports)
        ((not library-env) 'no-environment)
        ((exists (lambda (x) (not (memq (cdr x) '(procedure value)))) every-export)
         (list 'kinds (filter (lambda (x) (not (memq (cdr x) '(procedure value)))) every-export)))
        ((not (string? page-text)) page-text)
        ((null? entries) 'the-page-holds-no-entry)
        (else 'read)))

(test-equal "the library exports no name twice"
  '()
  (duplicates export-names))

(test-equal "every ### heading is one name in code (by its line and text)"
  '()
  bad-headings)

(test-equal "no name is the heading of two entries"
  '()
  (duplicates entry-names))

(test-equal "every export has an entry: the exports with none"
  '()
  (difference export-names entry-names))

(test-equal "every entry is an export: the entries that are none"
  '()
  (difference entry-names export-names))

(test-equal "the entries are the exports, as whole sorted lists"
  (sort-strings export-names)
  (sort-strings entry-names))

;; --- the signatures ----------------------------------------------------------------------

;; wrong-lines : (Listof (List String Symbol Any))
;; Each export whose entry's one text line is not "NAME : TYPE" with its own
;; NAME, or whose TYPE disagrees with what the export is: a procedure's holds
;; ->, and a value's does not. As (name kind what the entry holds).
(define (wrong-lines)
  (apply append
         (map (lambda (x)
                (let ((entry (find (lambda (e) (equal? (caddr e) (string->symbol (car x)))) entries)))
                  (if (not entry)
                      '()
                      (let* ((line (entry-signature entry))
                             (type (and (string? line) (line-type (car x) line))))
                        (cond ((not type) (list (list (car x) (cdr x) line)))
                              ((eq? (has-arrow? type) (eq? (cdr x) 'procedure)) '())
                              (else (list (list (car x) (cdr x) line))))))))
              every-export)))

(test-equal "each entry holds one line NAME : TYPE of its own name, whose TYPE holds -> for a procedure and not for a value, as Chez evaluates each: the entries that do not, as (name kind line)"
  '()
  (wrong-lines))

(test-end "reference")

;; SRFI-64 sets no exit status; this is the shared form.
(exit (suite-exit-status runner))
