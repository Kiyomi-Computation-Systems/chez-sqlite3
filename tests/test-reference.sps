#!r6rs
;;; docs/reference.md holds one entry for every export of (chez-sqlite3), and
;;; nothing else, each with the signature its source comment gives.
;;;
;;; The oracle for the names: src/chez-sqlite3.sls, read as data, its export
;;; clause. The oracle for the signatures: the comment above each export in
;;; that file, ";; NAME : TYPE". This is the one place a test reads a code
;;; comment. AGENTS.md says not to, because a comment can be wrong without a
;;; test noticing. Here the comment is the contract: the plan (section 5)
;;; makes the source's signature the one the reference is held to, so the
;;; reference is wrong when it differs from it, not the other way about. The
;;; export clause itself is read as data, never from a comment.
;;;
;;; The shape the page is held to:
;;; - a ### heading is an entry: one name in code, as "### `open-database`";
;;;   it runs to the next heading of level 1, 2 or 3. A ### heading of any
;;;   other shape fails, by its line;
;;; - an entry holds exactly one text block, of one line, "NAME : TYPE", the
;;;   same NAME as its heading, and TYPE the source comment's, character for
;;;   character;
;;; - no name is the heading of two entries.
;;;
;;; The page is read as CommonMark is: its ATX headings outside fenced
;;; blocks, and each fenced block, opened by up to three spaces and three or
;;; more backticks or tildes, closed by a fence of its own character, at
;;; least as long, and nothing after. One no fence closes runs to the page's
;;; end. A block's language is its info string's first word, in any case.
;;; The reader is held to all of it on texts of the suite's own, and the
;;; source reader too, before either reads a file.
;;;
;;; Names and signatures are compared as whole sorted lists, with the
;;; missing, the extra and the differing each asserted empty on its own, so a
;;; failure shows what differs. No assertion depends on an order. Each
;;; computation that can raise runs under a guard that answers what was
;;; raised, since SRFI-64 turns a raise in the actual expression into #f; no
;;; expected value is #f. make test runs every suite from the repository
;;; root.
(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing))

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

;; --- the source: exports and signatures ---------------------------------------------

;; exports-of : (Listof Any) -> (Listof Symbol)
;; The names of the export clause of the one library form read from the source.
(define (exports-of data)
  (let* ((form (car data))
         (clause (find (lambda (c) (and (pair? c) (eq? (car c) 'export))) (cddr form))))
    (cdr clause)))

;; signature-lines : String (Listof Symbol) -> (Listof (Pair Symbol (Listof String)))
;; For each NAME, every line of the source's text, up to its import clause,
;; that is a comment ";; NAME : TYPE" (any indent), as "NAME : TYPE".
(define (signature-lines text names)
  (let* ((lines (let take ((ls (text-lines text)) (out '()))
                  (if (or (null? ls) (starts? (trim (car ls)) "(import"))
                      (reverse out)
                      (take (cdr ls) (cons (trim (car ls)) out)))))
         (comments (filter (lambda (l) (starts? l ";; ")) lines)))
    (map (lambda (name)
           (let ((lead (string-append ";; " (symbol->string name) " : ")))
             (cons name
                   (map (lambda (l) (substring l 3 (string-length l)))
                        (filter (lambda (l) (starts? l lead)) comments)))))
         names)))

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

(test-equal "signature-lines: a comment of any indent, the name and the space-colon-space after it whole, nothing past the import clause"
  '((f "f : A -> B") (g) (f? "f? : Any -> Boolean"))
  (signature-lines
              (string-append "(library (x)\n  (export\n   ;; f : A -> B\n   f\n"
                             "   ;; fx : C -> D\n   ;;  f : not\n   ;; f? : Any -> Boolean\n   f?)\n"
                             "  (import\n   ;; g : late\n")
                             '(f g f?)))

(test-equal "exports-of: the export clause of the library form, whatever follows it"
  '(a b!)
  (exports-of '((library (x) (export a b!) (import (rnrs)) (define c 1)))))

;; --- the page and the source ---------------------------------------------------------

(define reference-path "docs/reference.md")
(define source-path "src/chez-sqlite3.sls")

;; page-text, source-text : (U String (List 'unreadable String))
(define (read-or-describe path)
  (guard (e (#t (list 'unreadable (describe e)))) (slurp path)))
(define page-text (read-or-describe reference-path))
(define source-text (read-or-describe source-path))

(define source-data
  (guard (e (#t (list 'unreadable (describe e))))
    (call-with-port
     (open-file-input-port source-path (file-options) (buffer-mode block)
                           (make-transcoder (utf-8-codec)))
     (lambda (port)
       (let loop ((found '()))
         (let ((datum (read port)))
           (if (eof-object? datum) (reverse found) (loop (cons datum found)))))))))

(define export-names
  (guard (e (#t (list (string->symbol (string-append "unreadable: " (describe e))))))
    (exports-of source-data)))

(define entries
  (if (string? page-text) (page-entries (page-items page-text)) '()))

(define (symbols->strings l) (map symbol->string l))

;; the entry names the page has, those it has twice, and the headings that are no entry
(define entry-names (map symbol->string (filter symbol? (map caddr entries))))
(define bad-headings (map (lambda (e) (list (car e) (cadr e))) (filter (lambda (e) (not (caddr e))) entries)))
(define exported (symbols->strings export-names))

;; duplicates : (Listof String) -> (Listof String)
;; The members that occur more than once, sorted, each once.
(define (duplicates l)
  (sort-strings
   (filter (lambda (x) (> (length (filter (lambda (y) (string=? x y)) l)) 1))
           (let loop ((rest l) (seen '()))
             (cond ((null? rest) (reverse seen))
                   ((member (car rest) seen) (loop (cdr rest) seen))
                   (else (loop (cdr rest) (cons (car rest) seen))))))))

;; difference : (Listof String) (Listof String) -> (Listof String)
;; The members of A that B lacks, sorted.
(define (difference a b)
  (sort-strings (filter (lambda (x) (not (member x b))) a)))

(test-equal "docs/reference.md and src/chez-sqlite3.sls are read"
  '(read read)
  (list (if (string? page-text) 'read page-text) (if (string? source-text) 'read source-text)))

(test-equal "the source's export clause names no name twice"
  '()
  (duplicates exported))

(test-equal "every ### heading is one name in code (by its line and text)"
  '()
  bad-headings)

(test-equal "no name is the heading of two entries"
  '()
  (duplicates entry-names))

(test-equal "every export has an entry: the exports with none"
  '()
  (difference exported entry-names))

(test-equal "every entry is an export: the entries that are none"
  '()
  (difference entry-names exported))

(test-equal "the entries are the exports, as whole sorted lists"
  (sort-strings exported)
  (sort-strings entry-names))

;; --- the signatures ----------------------------------------------------------------------

(define source-signatures (signature-lines (if (string? source-text) source-text "") export-names))

(test-equal "every export has exactly one signature comment in the source (the exports with none, or more)"
  '()
  (map car (filter (lambda (p) (not (= (length (cdr p)) 1))) source-signatures)))

;; the pairs (NAME . SIGNATURE) of the source and of the page, whole
(define expected-pairs
  (map (lambda (p) (cons (symbol->string (car p)) (if (null? (cdr p)) "" (cadr p))))
       source-signatures))
(define actual-pairs
  (map (lambda (e)
         (cons (if (caddr e) (symbol->string (caddr e)) (cadr e)) (entry-signature e)))
       entries))

(define (pair<? a b) (string<? (car a) (car b)))

(test-equal "an entry's signature is its source comment's, character for character: the entries that differ, each with both"
  '()
  (map (lambda (p)
         (list (car p) 'source (cdr (assoc (car p) expected-pairs)) 'page (cdr p)))
       (filter (lambda (p)
                 (let ((want (assoc (car p) expected-pairs)))
                   (and want (not (equal? (cdr want) (cdr p))))))
               actual-pairs)))

(test-equal "the signatures, whole: every export with the source's, as the page has it"
  (list-sort pair<? expected-pairs)
  (list-sort pair<? (filter (lambda (p) (assoc (car p) expected-pairs)) actual-pairs)))

(test-end "reference")

;; SRFI-64 sets no exit status; this is the shared form.
(exit (suite-exit-status runner))
