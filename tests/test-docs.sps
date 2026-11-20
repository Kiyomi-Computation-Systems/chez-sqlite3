#!r6rs
;;; The docs' rules, held for README.org and every docs/*.md page:
;;;
;;; - every block names its language: scheme, sh or text (an Org block a src
;;;   block of one of them, or a quote block), and a fence or #+end_ closes
;;;   it;
;;; - every Scheme block is a fragment, each datum of which Chez's read
;;;   reads, or a runnable example (below). A Scheme block that says
;;;   anything else fails, by its page and line;
;;; - every relative link names a file or directory of the checkout, and its
;;;   #anchor, when it has one, names a heading of that Markdown page by
;;;   GitHub's rule. A link with an anchor into a page that is not Markdown,
;;;   and an Org link to a place on its own page, fail: nothing here could
;;;   check them. No link points into .plans/, and no page says so;
;;; - README.org links every page of docs/, so none is orphaned;
;;; - README.org holds a Scheme block, and each of its Scheme blocks is the
;;;   twin of a runnable example (below) of a page of docs/: its lines are,
;;;   line for line, all of that block's lines, its ";; =>" line included. So
;;;   the README's example runs, through its twin. A block with no twin
;;;   fails, by its #+begin_src line; so does a README with no Scheme block,
;;;   and one with a block inside another, which the Org reader would not see;
;;; - no page says ADR- or TODO, "not yet" or any other "yet", "unreleased",
;;;   "slice", a path in .plans, or a date written YYYY-MM-DD, in any case;
;;; - every code span of a page's prose that is one name beginning sqlite- or
;;;   chez-sqlite3- is an export of (chez-sqlite3);
;;; - every Markdown Scheme fragment whose first datum, as Chez's read reads
;;;   the block's text, is a list headed import is a whole program: read
;;;   skips a #!r6rs and comments before it. It runs as written, a program of
;;;   its own in a fresh Chez with a reader's library path, src alone,
;;;   through gated-command: it exits 0 with nothing on stderr; when a text
;;;   block follows it on its page before the next Scheme block, whatever
;;;   lies between, it prints the first such block's lines, line for line;
;;;   and when it holds a guard with a clause (sqlite-library-unavailable?
;;;   V), V the guard's variable, it prints the list of sqlite-version,
;;;   sqlite-library-path and sqlite-library-source the suite reads itself,
;;;   as write writes it, and a newline, and runs again with
;;;   CHEZ_SQLITE3_LIBRARY naming a file that is not there, exits 0 with
;;;   nothing on stderr, and prints one datum, as write writes it, and a
;;;   newline: a list whose first element is refused. Some whole program
;;;   has a text block that holds what it prints;
;;; - docs/finding-sqlite.md's tables are the code's. The reasons table's
;;;   first column, each cell one code span, is the library's list of
;;;   refusal reasons, in its order. The discovery table's rows are
;;;   discovery's worlds, in order, Guix, other Linux, macOS and any other
;;;   system: each row's first cell names its world, the first holding Guix,
;;;   the second beginning Other Linux, the third holding Mac and the fourth
;;;   beginning Any other; and each row names the candidates discovery's own
;;;   procedure gives for its world on x86_64 and on arm64, by their paths as
;;;   it writes them, and their sources, each once, in order. The code span
;;;   before " for `CHEZ_SQLITE3_LIBRARY`" in the prose is the source an
;;;   override gets; with the table's, they are discovery's sources, each
;;;   once;
;;; - every word of a page, a run of letters, digits and _, in a block or
;;;   not, that holds CHEZ_ is CHEZ_SQLITE3_LIBRARY; and every
;;;   CHEZ_SQLITE3_LIBRARY= of a line that sets it, one at the line's start
;;;   or after a blank, as export X=, env X= and X=... before a command do,
;;;   gives it a value, up to a blank, that begins with /. One after any
;;;   other char, as Org's verbatim =CHEZ_SQLITE3_LIBRARY= is, sets nothing;
;;; - every page of docs/ has one level-1 heading, and it is the page's
;;;   first line.
;;;
;;; THE RUNNABLE CONVENTION. A Markdown Scheme block whose info string is
;;; exactly the one word run, written ```scheme run, is run: the tests
;;; evaluate it, and a reader sees the mark on the fence's own line, where no
;;; other kind of block has it. Its last non-blank line is a comment that
;;; states its result, ";; => DATUM", and no other line of the block starts
;;; that way. Everything above that line is the body, one or more data
;;; evaluated as the body of (let () ...) in an environment of (rnrs) and
;;; (chez-sqlite3); its last value, as Chez's read reads DATUM, must be
;;; equal? to the stated one. A body that raises fails, with what it raised.
;;; The runs leave every native count at zero, so a block that opens a
;;; database closes it. A block that has no ";; =>" line, or has two, or
;;; whose line is not last, or whose DATUM is not one datum, fails; so does
;;; an info string of any other words after scheme, and an Org Scheme block
;;; with any: the convention is Markdown's.
;;;
;;; The pages are read as CommonMark is: a fenced block opens on a line of up
;;; to three spaces, then three or more backticks or tildes and an info
;;; string, and closes only on a fence of its own character, at least as
;;; long, and nothing after; one no fence closes runs to the page's end. Its
;;; links are each inline link, [text](target), of its prose, outside code;
;;; its headings, its ATX headings outside blocks. A reference-style link is
;;; out of reach: write inline ones. An Org page's blocks run from
;;; #+begin_NAME to #+end_NAME; its links are [[target]] and [[target][text]]
;;; outside blocks. A heading's anchor, by GitHub's rule: its text, a link
;;; read as its text, inline code's marks and * dropped, in lower case, every
;;; char but a letter, a digit, _, a space or a - dropped, each space made a
;;; -; a second heading of one anchor takes -1, a third -2.
;;;
;;; A pipe table is a run of prose lines that begin, past up to three
;;; spaces, with |, its second line a delimiter row; a cell is the text
;;; between two |s, trimmed, a \| kept as |. A table whose lines do not
;;; begin with | is out of reach. A discovery row's second cell is read by
;;; its code spans: none names no path, one names that path, and more are
;;; written `FILE` in `DIR`, `DIR`, ..., each path DIR/FILE. A span written
;;; right after another as (`ALT` on M) takes that one's place on the
;;; machine M, arm64 or x86_64, and names nothing on any other. Its third
;;; cell's code spans are its sources. Discovery is asked in an environment
;;; where GUIX_ENVIRONMENT, GUIX_PROFILE and HOME each name a stand-in
;;; directory and nothing else is set, so a path under one reads as the page
;;; writes it: $GUIX_ENVIRONMENT, $GUIX_PROFILE, and ~ for HOME.
;;;
;;; Out of its reach, with no oracle but a reader's reading: prose that says
;;; something wrong, and a stated result that is wrong in a way equal? cannot
;;; see. (The signatures are tests/test-reference.sps's.) Every reader and
;;; rule is held on texts of the suite's own before it reads a page. Each
;;; computation that can raise runs under a guard that answers what was
;;; raised, since SRFI-64 turns a raise in the actual expression into #f; no
;;; expected value is #f. make test runs every suite from the repository root.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (chez-sqlite3-testing)
        (chez-sqlite3 private counters)
        (only (chez-sqlite3 private conditions) sqlite-library-unavailable-reasons)
        (only (chez-sqlite3 private discovery)
              choose-libsqlite3 libsqlite3-candidates libsqlite3-sources)
        (only (chezscheme) directory-list file-directory? getenv))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "docs")

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

;; joined : (Listof String) -> String
;; The lines, each ended by a newline.
(define (joined lines)
  (apply string-append (map (lambda (l) (string-append l "\n")) lines)))

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

;; ends? : String String -> Boolean
(define (ends? s suffix)
  (let ((n (string-length s)) (k (string-length suffix)))
    (and (>= n k) (string=? (substring s (- n k) n) suffix))))

;; search : String String Natural -> (U Natural #f)
;; Where PAT next begins in S, from I.
(define (search s pat i)
  (let ((n (string-length s)) (k (string-length pat)))
    (let loop ((i i))
      (cond ((> (+ i k) n) #f)
            ((string=? (substring s i (+ i k)) pat) i)
            (else (loop (+ i 1)))))))

;; run : String Natural Char -> Natural
;; How many of C begin at I.
(define (run s i c)
  (let loop ((j i))
    (if (and (< j (string-length s)) (char=? (string-ref s j) c)) (loop (+ j 1)) (- j i))))

;; split : String Char -> (Listof String)
(define (split s c)
  (let loop ((cs (string->list s)) (piece '()) (out '()))
    (cond ((null? cs) (reverse (cons (list->string (reverse piece)) out)))
          ((char=? (car cs) c) (loop (cdr cs) '() (cons (list->string (reverse piece)) out)))
          (else (loop (cdr cs) (cons (car cs) piece) out)))))

;; words : String -> (Listof String)
(define (words s)
  (filter (lambda (w) (not (string=? w "")))
          (split (list->string (map (lambda (c) (if (blank? c) #\space c)) (string->list s)))
                 #\space)))

;; ascii-downcase : String -> String
(define (ascii-downcase s)
  (list->string (map (lambda (c) (if (and (char<=? #\A c) (char<=? c #\Z))
                                     (integer->char (+ (char->integer c) 32))
                                     c))
                     (string->list s))))

;; datums : String -> (U (Listof Any) (List 'unreadable))
;; Every datum Chez's read reads from the text.
(define (datums text)
  (guard (e (#t (list 'unreadable)))
    (let ((p (open-string-input-port text)))
      (let loop ((out '()))
        (let ((d (read p)))
          (if (eof-object? d) (reverse out) (loop (cons d out))))))))

;; shown : Datum -> String
(define (shown d)
  (call-with-string-output-port (lambda (p) (write d p))))

;; numbered : (Listof String) -> (Listof (Pair Natural String))
;; Each line with its number, from 1.
(define (numbered lines)
  (let loop ((ls lines) (n 1) (out '()))
    (if (null? ls) (reverse out) (loop (cdr ls) (+ n 1) (cons (cons n (car ls)) out)))))

;; --- Markdown: blocks, prose, headings and links -------------------------------------

;; A block of a page: its line, its language, the words of its info string
;; after the language, its lines, and whether a fence closes it.
(define-record-type block (fields line language info lines closed?))

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

;; unindent : String Natural -> String
(define (unindent line n)
  (let ((k (min n (run line 0 #\space)))) (substring line k (string-length line))))

;; heading-of : String -> (U (Pair Natural String) #f)
(define (heading-of line)
  (let* ((indent (run line 0 #\space)) (n (string-length line)))
    (and (<= indent 3)
         (let ((k (run line indent #\#)))
           (and (<= 1 k 6)
                (or (= (+ indent k) n) (blank? (string-ref line (+ indent k))))
                (cons k (trim (substring line (+ indent k) n))))))))

;; make-block-of : (List Char Natural Natural String) Natural (Listof String) Boolean -> Block
(define (make-block-of open line lines closed?)
  (let ((ws (words (cadddr open))))
    (make-block line (if (null? ws) "" (ascii-downcase (car ws))) (if (null? ws) '() (cdr ws))
                lines closed?)))

;; markdown : String -> (List (Listof Block) (Listof String) (Listof (Pair Natural String)))
;; The page's fenced blocks, in order; its prose, every other line, a blank
;; line for each of a block's, so the prose keeps the page's line numbers;
;; and its headings, each with its text, outside blocks.
(define (markdown text)
  (let loop ((ls (text-lines text)) (n 1) (open #f) (start 0) (body '())
             (blocks '()) (prose '()) (heads '()))
    (cond ((null? ls)
           (list (reverse (if open (cons (make-block-of open start (reverse body) #f) blocks) blocks))
                 (reverse prose) (reverse heads)))
          (open
           (if (closes? (car ls) open)
               (loop (cdr ls) (+ n 1) #f 0 '()
                     (cons (make-block-of open start (reverse body) #t) blocks) (cons "" prose) heads)
               (loop (cdr ls) (+ n 1) open start (cons (unindent (car ls) (caddr open)) body)
                     blocks (cons "" prose) heads)))
          ((fence (car ls))
           => (lambda (f) (loop (cdr ls) (+ n 1) f n '() blocks (cons "" prose) heads)))
          (else
           (loop (cdr ls) (+ n 1) #f 0 '() blocks (cons (car ls) prose)
                 (let ((h (heading-of (car ls)))) (if h (cons h heads) heads)))))))

;; h1-lines : (Listof String) -> (Listof Natural)
;; The line of each level-1 heading of a Markdown page's prose, as markdown
;; reads its headings, in order.
(define (h1-lines prose)
  (map car (filter (lambda (l) (let ((h (heading-of (cdr l)))) (and h (= (car h) 1))))
                   (numbered prose))))

;; code-ranges : String -> (Listof (Pair Natural Natural))
;; Where each `code` span of the text begins and ends: a run of backticks
;; opens one, and the next run of exactly as many closes it; a run that none
;; closes is text, and so is a backtick after a backslash.
(define (code-ranges text)
  (let ((n (string-length text)))
    (define (closer i k)
      (cond ((>= i n) #f)
            ((char=? (string-ref text i) #\`)
             (let ((m (run text i #\`))) (if (= m k) i (closer (+ i m) k))))
            (else (closer (+ i 1) k))))
    (let loop ((i 0) (out '()))
      (cond ((>= i n) (reverse out))
            ((and (char=? (string-ref text i) #\\) (< (+ i 1) n)) (loop (+ i 2) out))
            ((char=? (string-ref text i) #\`)
             (let* ((k (run text i #\`)) (j (closer (+ i k) k)))
               (if j (loop (+ j k) (cons (cons i (+ j k)) out)) (loop (+ i k) out))))
            (else (loop (+ i 1) out))))))

;; code-spans : String -> (Listof String)
;; The text of each code span, its backticks off and its blanks trimmed.
(define (code-spans text)
  (map (lambda (r)
         (let* ((s (substring text (car r) (cdr r)))
                (k (run s 0 #\`)))
           (trim (substring s k (- (string-length s) k)))))
       (code-ranges text)))

;; without-code : String -> String
;; The text with each code span made spaces, its line ends kept.
(define (without-code text)
  (let ((ranges (code-ranges text)))
    (let loop ((cs (string->list text)) (i 0) (out '()))
      (if (null? cs)
          (list->string (reverse out))
          (loop (cdr cs) (+ i 1)
                (cons (if (and (not (char=? (car cs) #\newline))
                               (exists (lambda (r) (and (<= (car r) i) (< i (cdr r)))) ranges))
                          #\space
                          (car cs))
                      out))))))

;; markdown-links : (Listof String) -> (Listof String)
;; The target of each inline link and image of the prose, [text](target),
;; outside code: what follows "](" up to a blank, a line's end or the ")"
;; that ends it, without angle brackets around it.
(define (markdown-links prose)
  (let ((s (without-code (joined prose))))
    (let loop ((i 0) (out '()))
      (let ((j (search s "](" i)))
        (if (not j)
            (reverse out)
            (let end ((k (+ j 2)))
              (if (or (>= k (string-length s)) (memv (string-ref s k) '(#\) #\space #\tab #\newline)))
                  (let ((t (substring s (+ j 2) k)))
                    (loop k (cons (if (and (starts? t "<") (ends? t ">"))
                                      (substring t 1 (- (string-length t) 1))
                                      t)
                                  out)))
                  (end (+ k 1)))))))))

;; --- Org: blocks and links ------------------------------------------------------------

;; org-keyword : String String -> (U String #f)
;; The rest of the line after KEYWORD, when the line, past its blanks,
;; begins with it in any case.
(define (org-keyword line keyword)
  (let ((s (trim line)))
    (and (starts? (ascii-downcase s) keyword) (substring s (string-length keyword) (string-length s)))))

;; org : String -> (List (Listof Block) (Listof String))
;; The page's blocks, and its prose, every line outside a block, a blank
;; line for a block's, with its #+begin_ and #+end_ lines. A src block's
;; language is the first word after #+begin_src, "" for none; any other
;; block's is # and its NAME.
(define (org text)
  (let loop ((ls (text-lines text)) (n 1) (open #f) (start 0) (body '()) (blocks '()) (prose '()))
    (define (finish closed?)
      (let ((ws (cadr open)))
        (cons (if (string=? (car open) "src")
                  (make-block start (if (null? ws) "" (ascii-downcase (car ws)))
                              (if (null? ws) '() (cdr ws)) (reverse body) closed?)
                  (make-block start (string-append "#" (car open)) ws (reverse body) closed?))
              blocks)))
    (cond ((null? ls) (list (reverse (if open (finish #f) blocks)) (reverse prose)))
          (open
           (let ((end (org-keyword (car ls) "#+end_")))
             (if (and end (string=? (ascii-downcase (trim end)) (car open)))
                 (loop (cdr ls) (+ n 1) #f 0 '() (finish #t) (cons "" prose))
                 (loop (cdr ls) (+ n 1) open start (cons (car ls) body) blocks (cons "" prose)))))
          ((org-keyword (car ls) "#+begin_")
           => (lambda (rest)
                (let ((ws (words rest)))
                  (if (null? ws)
                      (loop (cdr ls) (+ n 1) #f 0 '() blocks (cons (car ls) prose))
                      (loop (cdr ls) (+ n 1) (list (ascii-downcase (car ws)) (cdr ws)) n '() blocks
                            (cons "" prose))))))
          (else (loop (cdr ls) (+ n 1) #f 0 '() blocks (cons (car ls) prose))))))

;; org-links : (Listof String) -> (Listof String)
;; The target of each [[target]] and [[target][text]] link of the prose.
(define (org-links prose)
  (let ((s (joined prose)))
    (let loop ((i 0) (out '()))
      (let ((j (search s "[[" i)))
        (if (not j)
            (reverse out)
            (let end ((k (+ j 2)))
              (cond ((>= k (string-length s)) (reverse out))
                    ((char=? (string-ref s k) #\]) (loop k (cons (substring s (+ j 2) k) out)))
                    (else (end (+ k 1))))))))))

;; --- anchors ---------------------------------------------------------------------------

;; heading-text : String -> String
;; A heading's text as it reads: each link [t](u) as t, code's marks and *
;; dropped.
(define (heading-text s)
  (let loop ((cs (string->list s)) (out '()))
    (cond ((null? cs) (list->string (reverse out)))
          ((and (char=? (car cs) #\]) (pair? (cdr cs)) (char=? (cadr cs) #\())
           (let skip ((rest (cddr cs)))
             (cond ((null? rest) (loop rest out))
                   ((char=? (car rest) #\)) (loop (cdr rest) out))
                   (else (skip (cdr rest))))))
          ((memv (car cs) '(#\[ #\` #\*)) (loop (cdr cs) out))
          (else (loop (cdr cs) (cons (car cs) out))))))

;; slug : String -> String
;; GitHub's rule for one heading's text, before duplicates.
(define (slug text)
  (list->string
   (map (lambda (c) (if (char=? c #\space) #\- c))
        (filter (lambda (c) (or (char-alphabetic? c) (char-numeric? c) (memv c '(#\_ #\- #\space))))
                (string->list (ascii-downcase (heading-text text)))))))

;; anchors : (Listof String) -> (Listof String)
;; The anchor of each heading text, in order: a second of one slug takes -1,
;; a third -2.
(define (anchors texts)
  (let loop ((rest texts) (seen '()) (out '()))
    (if (null? rest)
        (reverse out)
        (let* ((s (slug (car rest)))
               (n (length (filter (lambda (x) (string=? x s)) seen))))
          (loop (cdr rest) (cons s seen)
                (cons (if (= n 0) s (string-append s "-" (number->string n))) out))))))

;; --- links, resolved -------------------------------------------------------------------

;; scheme-like? : String -> Boolean
;; The target begins with a URI scheme and a colon, as https: or mailto: does.
(define (scheme-like? target)
  (let ((colon (search target ":" 0)))
    (and colon (> colon 0)
         (char-alphabetic? (string-ref target 0))
         (for-all (lambda (c) (or (char-alphabetic? c) (char-numeric? c) (memv c '(#\+ #\- #\.))))
                  (string->list (substring target 0 colon))))))

;; cut : String Char -> (Pair String (U String #f))
;; The text before the first C, and what follows it, or #f.
(define (cut s c)
  (let ((k (search s (string c) 0)))
    (if k (cons (substring s 0 k) (substring s (+ k 1) (string-length s))) (cons s #f))))

;; link-parts : String Boolean -> (U (List String (U String #f)) (List 'own-page) #f)
;; A link's file and its anchor, when it names one of the checkout: its
;; ?query dropped, and for an Org link a file: before it and a ::search
;; after it. #f for a link with a scheme; (own-page) for a place on its own
;; page, # or, for Org, * ; a link of no file at all is that too.
(define (link-parts target org?)
  (let* ((t (if (and org? (starts? target "file:")) (substring target 5 (string-length target)) target))
         (t (if org? (car (let ((k (search t "::" 0))) (cons (if k (substring t 0 k) t) #f))) t))
         (parts (cut t #\#))
         (file (car (cut (car parts) #\?))))
    (cond ((and (not org?) (scheme-like? file)) #f)
          ((and org? (scheme-like? file)) #f)
          ((or (string=? file "") (and org? (starts? target "*"))) (list 'own-page))
          (else (list file (cdr parts))))))

;; resolve : String String -> (U String #f)
;; PATH, relative to the directory DIR of the checkout ("" for its root), as
;; a path from the root, its . and empty segments dropped, each .. taking
;; off the segment before; #f when it climbs out of the root, or is
;; absolute. The root itself is "".
(define (resolve dir path)
  (and (not (starts? path "/"))
       (let loop ((segments (append (if (string=? dir "") '() (split dir #\/)) (split path #\/)))
                  (out '()))
         (cond ((null? segments)
                (if (null? out)
                    ""
                    (fold-left (lambda (acc s) (if (string=? acc "") s (string-append acc "/" s)))
                               "" (reverse out))))
               ((member (car segments) '("" ".")) (loop (cdr segments) out))
               ((string=? (car segments) "..") (and (pair? out) (loop (cdr segments) (cdr out))))
               (else (loop (cdr segments) (cons (car segments) out)))))))

;; dir-of : String -> String
(define (dir-of path)
  (let ((parts (split path #\/)))
    (if (null? (cdr parts))
        ""
        (fold-left (lambda (acc s) (if (string=? acc "") s (string-append acc "/" s)))
                   "" (reverse (cdr (reverse parts)))))))

;; into-plans? : String -> Boolean
(define (into-plans? path) (or (string=? path ".plans") (starts? path ".plans/")))

;; link-problem : String String Boolean (String -> Boolean) (String -> (U (Listof String) #f))
;;                -> (U Symbol #f)
;; Why TARGET, a link of the page PAGE, is no good, or #f. EXISTS? says a
;; path of the checkout is there; ANCHORS-OF answers a Markdown page's
;; anchors, #f when it cannot be read.
(define (link-problem page target org? exists? anchors-of)
  (let ((parts (link-parts target org?)))
    (cond ((not parts) #f)
          ((eq? (car parts) 'own-page)
           (if (and (not org?) (starts? target "#"))
               (let ((frag (substring target 1 (string-length target))))
                 (if (or (string=? frag "") (member frag (or (anchors-of page) '()))) #f 'no-such-anchor))
               'own-page-link-unchecked))
          (else
           (let ((path (resolve (dir-of page) (car parts))))
             (cond ((not path) 'outside-the-checkout)
                   ((into-plans? path) 'into-plans)
                   ((not (exists? (if (string=? path "") "." path))) 'no-such-file)
                   ((not (cadr parts)) #f)
                   ((not (ends? path ".md")) 'anchor-into-a-page-that-is-not-markdown)
                   ((string=? (cadr parts) "") #f)
                   ((member (cadr parts) (or (anchors-of path) '())) #f)
                   (else 'no-such-anchor)))))))

;; --- what a Scheme block says -----------------------------------------------------------

;; scheme-mark : Block Boolean -> (U 'fragment 'run 'unknown)
;; What the info of a Scheme block says it is: nothing, a fragment; the one
;; word run in Markdown, a runnable example; else unknown.
(define (scheme-mark b org?)
  (let ((info (block-info b)))
    (cond ((null? info) 'fragment)
          ((and (not org?) (equal? info '("run"))) 'run)
          (else 'unknown))))

;; parse-run : (Listof String) -> (U (List 'ok (Listof Any) Any) (List 'bad Symbol))
;; The body's data and the stated result's datum of a runnable block, or why
;; the block is no runnable example.
(define (parse-run lines)
  (let* ((marks (filter (lambda (l) (starts? (trim l) ";; =>")) lines))
         (nonblank (filter (lambda (l) (not (string=? (trim l) ""))) lines)))
    (cond ((null? marks) '(bad no-result-line))
          ((> (length marks) 1) '(bad two-result-lines))
          ((not (equal? (car (reverse nonblank)) (car marks))) '(bad result-line-not-last))
          (else
           (let* ((mark (trim (car marks)))
                  (stated (datums (substring mark 5 (string-length mark))))
                  (body (datums (joined (filter (lambda (l) (not (string=? l (car marks)))) lines)))))
             (cond ((or (equal? stated '(unreadable)) (not (= (length stated) 1))) '(bad result-is-not-one-datum))
                   ((or (equal? body '(unreadable)) (null? body)) '(bad body-is-not-data))
                   (else (list 'ok body (car stated)))))))))

;; check-run : (Listof String) Environment -> (U 'ok (List 'bad Symbol) (List 'wrong-result Any Any))
;; A runnable block's lines run in ENV: ok when its value is equal? to the
;; stated one; else why not, with what was stated and what happened.
(define (check-run lines env)
  (let ((parsed (parse-run lines)))
    (if (eq? (car parsed) 'bad)
        parsed
        (let ((outcome (guard (e (#t (list 'raised (describe e))))
                         (list 'value (eval (cons 'let (cons '() (cadr parsed))) env)))))
          (if (equal? outcome (list 'value (caddr parsed)))
              'ok
              (list 'wrong-result (caddr parsed) outcome))))))

;; --- the README's twin ----------------------------------------------------------------------

;; twin-problems : String String (Listof String) -> (Listof (Listof Any))
;; What keeps the README NAME, of Org text ORG-TEXT, from its twins in the
;; Markdown pages of texts MD-TEXTS: (NAME no-scheme-block) when it holds no
;; Scheme block; else (NAME LINE no-twin) for each Scheme block, by the line
;; of its #+begin_src, whose lines are not, line for line, all the lines of
;; one runnable block of a page.
(define (twin-problems name org-text md-texts)
  (let ((blocks (filter (lambda (b) (string=? (block-language b) "scheme")) (car (org org-text))))
        (runnable (apply append
                         (map (lambda (t)
                                (filter (lambda (b) (and (string=? (block-language b) "scheme")
                                                         (eq? (scheme-mark b #f) 'run)))
                                        (car (markdown t))))
                              md-texts))))
    (if (null? blocks)
        (list (list name 'no-scheme-block))
        (apply append
               (map (lambda (b)
                      (if (exists (lambda (r) (equal? (block-lines b) (block-lines r))) runnable)
                          '()
                          (list (list name (block-line b) 'no-twin))))
                    blocks)))))

;; --- prose rules ----------------------------------------------------------------------------

;; digit? : Char -> Boolean
(define (digit? c) (and (char<=? #\0 c) (char<=? c #\9)))

;; dated? : String -> Boolean
;; Whether the text holds four digits, -, two digits, -, two digits.
(define (dated? s)
  (let ((n (string-length s)))
    (let loop ((i 0))
      (and (<= (+ i 10) n)
           (or (let ((w (substring s i (+ i 10))))
                 (and (for-all digit? (string->list (substring w 0 4)))
                      (char=? (string-ref w 4) #\-)
                      (for-all digit? (string->list (substring w 5 7)))
                      (char=? (string-ref w 7) #\-)
                      (for-all digit? (string->list (substring w 8 10)))))
               (loop (+ i 1)))))))

;; forbidden : String -> (Listof String)
;; Which of the banned phrases the text says, in any case, a line's end
;; between two words read as a space.
(define (forbidden text)
  (let ((flat (ascii-downcase (list->string (map (lambda (c) (if (char=? c #\newline) #\space c))
                                                 (string->list text))))))
    (append (filter (lambda (p) (search flat p 0))
                    '("adr-" "todo" "not yet" " yet" "unreleased" "slice" ".plans"))
            (if (dated? flat) '("a date") '()))))

;; name-like? : String -> Boolean
;; A code span that is one name of this library's kind.
(define (name-like? s)
  (and (or (starts? s "sqlite-") (starts? s "chez-sqlite3-"))
       (for-all (lambda (c) (or (and (char<=? #\a c) (char<=? c #\z)) (digit? c) (memv c '(#\- #\! #\?))))
                (string->list s))))

;; unknown-names : (Listof String) (Listof String) -> (Listof String)
;; The name-like code spans that are no export, sorted, each once.
(define (unknown-names spans exports)
  (let loop ((rest spans) (out '()))
    (cond ((null? rest) (list-sort string<? out))
          ((and (name-like? (car rest)) (not (member (car rest) exports)) (not (member (car rest) out)))
           (loop (cdr rest) (cons (car rest) out)))
          (else (loop (cdr rest) out)))))

;; --- the readers, on texts of the suite's own --------------------------------------------------

(define sample-md
  (string-append
   "# Top `x`\n"
   "See [a](a.md#top-x) and `[no](code.md)`, ![i](<b.png>).\n"
   "```scheme run\n[no](block.md)\n# not a heading\n```\n"
   "## Top x\n"
   "[two](u#top-x-1) [mail](mailto:a@b)\n"
   "~~~sh\nls\n"))

(define sample-parsed (markdown sample-md))

(test-equal "markdown: each block with its line, language, info, lines and whether a fence closes it"
  '((3 "scheme" ("run") ("[no](block.md)" "# not a heading") #t)
    (9 "sh" () ("ls") #f))
  (map (lambda (b) (list (block-line b) (block-language b) (block-info b) (block-lines b) (block-closed? b)))
       (car sample-parsed)))

(test-equal "markdown: a block's lines are blank prose, so the prose keeps its line numbers"
  '("# Top `x`" "See [a](a.md#top-x) and `[no](code.md)`, ![i](<b.png>)." "" "" "" ""
    "## Top x" "[two](u#top-x-1) [mail](mailto:a@b)" "" "")
  (cadr sample-parsed))

(test-equal "markdown: the headings outside blocks, with level and text"
  '((1 . "Top `x`") (2 . "Top x"))
  (caddr sample-parsed))

(test-equal "h1-lines: each level-1 heading's line, a bare # and one indented three spaces among them; not one in a block, a level-2, a #word, one indented four, or seven #s"
  '((1) (2 8 10))
  (list (h1-lines (cadr sample-parsed))
        (h1-lines (cadr (markdown (string-append
                                   "Intro\n# Two\n```\n# in a block\n```\n#NoSpace\n    # four spaces\n"
                                   "   # three spaces\n## level two\n#\n####### seven\n"))))))

(test-equal "markdown-links: inline links and images outside code, an angle-bracketed target as written within them"
  '("a.md#top-x" "b.png" "u#top-x-1" "mailto:a@b")
  (markdown-links (cadr sample-parsed)))

(test-equal "code-spans: the text of each, a double-backtick span holding a backtick whole"
  '("a" "b ` c")
  (code-spans "x `a` y ``b ` c`` z `open"))

(test-equal "anchors: a heading's slug, its code and * and link marks dropped, a repeat taking -1 and -2"
  '("top-x" "top-x-1" "top-x-2" "ab_c" "see-here")
  (anchors '("Top `x`" "Top x" "Top *x*" "A.b_c!" "See [here](x.md)")))

(test-equal "link-parts: a scheme is no file; a fragment-only link is its own page; a ?query is dropped; Org's file: and ::search too"
  (list #f '(own-page) '("a.md" "top") '("b/c.md" #f) '("d.org" #f) '(own-page) #f)
  (list (link-parts "https://x.y/z" #f) (link-parts "#top" #f) (link-parts "a.md?q=1#top" #f)
        (link-parts "b/c.md" #f) (link-parts "file:d.org::*Head" #t) (link-parts "*Head" #t)
        (link-parts "mailto:a@b" #f)))

(test-equal "resolve: against the page's directory, . and .. applied, a climb out of the root and an absolute path refused"
  '("docs/b.md" "a.md" "" #f #f)
  (list (resolve "docs" "./b.md") (resolve "docs" "../a.md") (resolve "docs" "..")
        (resolve "docs" "../../a") (resolve "docs" "/etc")))

(test-equal "dir-of: a page's directory, \"\" for the root"
  '("docs" "" "a/b")
  (list (dir-of "docs/r.md") (dir-of "README.org") (dir-of "a/b/c.md")))

;; link-problem on a stand-in checkout: docs/r.md with anchors (top), a.md
(define stand-in-files '("." "docs" "docs/r.md" "a.md" "x.txt" ".plans/x.md"))
(define (stand-in-exists? p) (and (member p stand-in-files) #t))
(define (stand-in-anchors p) (if (string=? p "docs/r.md") '("top") #f))

(test-equal "link-problem: each way a link fails, and each that does not"
  '(#f #f #f #f #f no-such-file no-such-anchor no-such-anchor into-plans outside-the-checkout
    no-such-anchor anchor-into-a-page-that-is-not-markdown #f)
  (map (lambda (t) (link-problem "docs/r.md" t #f stand-in-exists? stand-in-anchors))
       '("../a.md" "r.md#top" "#top" "https://x" ".." "nope.md" "r.md#nope" "#nope"
         "../.plans/x.md" "../../x" "../a.md#top" "../x.txt#top" "r.md#")))

(test-equal "link-problem: Org's own-page links cannot be checked, and a missing file is named"
  '(own-page-link-unchecked own-page-link-unchecked no-such-file #f)
  (list (link-problem "README.org" "*Head" #t stand-in-exists? stand-in-anchors)
        (link-problem "README.org" "#id" #t stand-in-exists? stand-in-anchors)
        (link-problem "README.org" "docs/none.md" #t stand-in-exists? stand-in-anchors)
        (link-problem "README.org" "file:docs/r.md::x" #t stand-in-exists? stand-in-anchors)))

(test-equal "link-problem: an own-page # link of a page whose anchors are unknown fails, and a lone # is fine"
  '(no-such-anchor #f)
  (list (link-problem "docs/zz.md" "#top" #f stand-in-exists? stand-in-anchors)
        (link-problem "docs/r.md" "#" #f stand-in-exists? stand-in-anchors)))

(define sample-org
  (string-append
   "* Head\n"
   "A [[docs/r.md][ref]] and [[file:x.org::*H]] and [[https://z]].\n"
   "#+begin_src scheme :run\n[[not-a-link]]\n#+end_src\n"
   "#+BEGIN_QUOTE\nq\n#+END_QUOTE\n"
   "#+begin_src sh\nls\n"))

(define sample-org-parsed (org sample-org))

(test-equal "org: each block with its line, language, info, lines and whether #+end_ closes it"
  '((3 "scheme" (":run") ("[[not-a-link]]") #t)
    (6 "#quote" () ("q") #t)
    (9 "sh" () ("ls") #f))
  (map (lambda (b) (list (block-line b) (block-language b) (block-info b) (block-lines b) (block-closed? b)))
       (car sample-org-parsed)))

(test-equal "org-links: [[target]] and [[target][text]] outside blocks"
  '("docs/r.md" "file:x.org::*H" "https://z")
  (org-links (cadr sample-org-parsed)))

(test-equal "scheme-mark: nothing is a fragment; run alone is runnable in Markdown, never in Org; anything else unknown"
  '(fragment run unknown unknown unknown)
  (let ((b (lambda (info) (make-block 1 "scheme" info '() #t))))
    (list (scheme-mark (b '()) #f) (scheme-mark (b '("run")) #f) (scheme-mark (b '("run")) #t)
          (scheme-mark (b '("run" "x")) #f) (scheme-mark (b '("example=a.sps")) #f))))

(define rnrs-env (environment '(rnrs)))

(test-equal "check-run: a result that is the stated one passes; a different one, a raise, and each shape that is no example fail, named"
  '(ok
    (wrong-result 4 (value 3))
    (wrong-result 1 (raised "r"))
    (bad no-result-line)
    (bad two-result-lines)
    (bad result-line-not-last)
    (bad result-is-not-one-datum)
    (bad result-is-not-one-datum)
    (bad body-is-not-data)
    ok)
  (let ((go (lambda (lines)
              (let ((r (check-run lines rnrs-env)))
                (if (and (pair? r) (eq? (car r) 'wrong-result) (pair? (caddr r)) (eq? (car (caddr r)) 'raised))
                    (list 'wrong-result (cadr r) (list 'raised "r"))
                    r)))))
    (list (go '("(+ 1 2)" ";; => 3"))
          (go '("(+ 1 2)" ";; => 4"))
          (go '("(raise 'x)" ";; => 1"))
          (go '("(+ 1 2)"))
          (go '(";; => 1" ";; => 1"))
          (go '(";; => 3" "(+ 1 2)"))
          (go '("(+ 1 2)" ";; => 3 4"))
          (go '("(+ 1 2)" ";; =>"))
          (go '(";; => 3"))
          (go '("(define x 1)" "(list x x)" "" ";; => (1 1)" "")))))

(test-equal "forbidden: each banned phrase, in any case across a line's end, and a date; a yet without its not"
  '(("adr-" "todo" "not yet" " yet" "slice" ".plans" "a date") () (" yet"))
  (list (forbidden "see ADR-0001, TODO: Not\nyet, a Slice of .plans/x on 2026-11-14")
        (forbidden "Nothing to see: 2026-1-14 or 20261114.")
        (forbidden "The rest is not here\nYet.")))

(test-equal "unknown-names: only the name-like spans that are no export, sorted, each once"
  '("chez-sqlite3-nope" "sqlite-nope")
  (unknown-names '("sqlite-nope" "sqlite-ok" "chez-sqlite3-nope" "sqlite-nope" "sqlite-x y" "Sqlite-Q"
                   "(sqlite-nope)" "open-database")
                 '("sqlite-ok" "open-database")))

;; twin-problems on texts of the suite's own: a page whose runnable block is
;; TWIN, beside a fragment of other lines, and READMEs whose Scheme blocks
;; differ from it in one way each. A README's first block opens on line 5.

(define twin '("(define x 2)" "(* x 21)" ";; => 42"))

;; fenced : String (Listof String) -> String
;; A Markdown block of LINES whose fence's info string is INFO.
(define (fenced info lines) (string-append "```" info "\n" (joined lines) "```\n"))

;; org-src : String (Listof String) -> String
;; An Org block of LINES opened by #+begin_src LANGUAGE.
(define (org-src language lines)
  (string-append "#+begin_src " language "\n" (joined lines) "#+end_src\n"))

;; readme-of : String ... -> String
;; A README of a heading and a paragraph, then PARTS.
(define (readme-of . parts) (apply string-append "* Title\n\nProse.\n\n" parts))

(define twin-page
  (string-append "# Page\n\nProse.\n\n" (fenced "scheme run" twin) "\n" (fenced "scheme" '("(display 1)"))))

;; changed-at : String Natural -> String
;; S with its char at I made another.
(define (changed-at s i)
  (string-append (substring s 0 i)
                 (if (char=? (string-ref s i) #\x) "y" "x")
                 (substring s (+ i 1) (string-length s))))

;; one-char-off : (Listof (Listof String))
;; TWIN with one char changed, at the start and at the end of each line in
;; turn, the ;; => line's among them.
(define one-char-off
  (apply append
         (map (lambda (k)
                (let ((line (list-ref twin k)))
                  (map (lambda (i)
                         (let loop ((j 0) (ls twin) (out '()))
                           (if (null? ls)
                               (reverse out)
                               (loop (+ j 1) (cdr ls) (cons (if (= j k) (changed-at line i) (car ls)) out)))))
                       (list 0 (- (string-length line) 1)))))
              '(0 1 2))))

(test-equal "twin-problems: a README whose one Scheme block is a page's runnable block, line for line, has its twin"
  '()
  (twin-problems "R" (readme-of (org-src "scheme" twin)) (list twin-page)))

(test-equal "twin-problems: one char off, at the start or the end of any of its lines, the ;; => line's too, and the block has no twin, named by its line"
  (map (lambda (x) '(("R" 5 no-twin))) one-char-off)
  (map (lambda (lines) (twin-problems "R" (readme-of (org-src "scheme" lines)) (list twin-page)))
       one-char-off))

(test-equal "twin-problems: a twin is all of a runnable block's lines, as written: its body alone, a line added before or after, two lines swapped, each line indented, have none"
  '((("R" 5 no-twin)) (("R" 5 no-twin)) (("R" 5 no-twin)) (("R" 5 no-twin)) (("R" 5 no-twin)))
  (map (lambda (lines) (twin-problems "R" (readme-of (org-src "scheme" lines)) (list twin-page)))
       (list '("(define x 2)" "(* x 21)")
             (cons "" twin)
             (append twin '(""))
             '("(* x 21)" "(define x 2)" ";; => 42")
             (map (lambda (l) (string-append "  " l)) twin))))

(test-equal "twin-problems: a README with no Scheme block is named: prose that says scheme, an sh block, a quote, an example, and an empty README"
  '((("R" no-scheme-block)) (("R" no-scheme-block)))
  (list (twin-problems "R"
                       (readme-of "Some scheme here.\n\n" (org-src "sh" '("ls"))
                                  "#+begin_quote\n(* 2 21)\n#+end_quote\n"
                                  "#+begin_example\n(* 2 21)\n#+end_example\n")
                       (list twin-page))
        (twin-problems "R" "" (list twin-page))))

(test-equal "twin-problems: two Scheme blocks, each held: the second without a twin, the first, and both, each named by its line, in order"
  '((("R" 10 no-twin)) (("R" 5 no-twin)) (("R" 5 no-twin) ("R" 10 no-twin)))
  (list (twin-problems "R" (readme-of (org-src "scheme" twin) (org-src "scheme" '("(* 2 21)")))
                       (list twin-page))
        (twin-problems "R" (readme-of (org-src "scheme" '("(* 2 21)")) "\n\n" (org-src "scheme" twin))
                       (list twin-page))
        (twin-problems "R" (readme-of (org-src "scheme" '("(* 2 21)")) "\n\n" (org-src "scheme" '("1")))
                       (list twin-page))))

(test-equal "twin-problems: the same lines in a block not marked run are no twin: plain scheme, scheme run with another word, scheme example, sh, text, and no language"
  (map (lambda (info) '(("R" 5 no-twin))) '("scheme" "scheme run x" "scheme example" "sh" "text" ""))
  (map (lambda (info)
         (twin-problems "R" (readme-of (org-src "scheme" twin))
                        (list (string-append "# Page\n\n" (fenced info twin)))))
       '("scheme" "scheme run x" "scheme example" "sh" "text" "")))

(test-equal "twin-problems: the twin may be in any page, among other runnable blocks; with no page there is none"
  '(() () (("R" 5 no-twin)))
  (list (twin-problems "R" (readme-of (org-src "scheme" twin))
                       (list "# Other\n" twin-page))
        (twin-problems "R" (readme-of (org-src "scheme" twin))
                       (list (string-append (fenced "scheme run" '("1" ";; => 1")) twin-page)))
        (twin-problems "R" (readme-of (org-src "scheme" twin)) '())))

(test-equal "twin-problems: the twin is found at each place, first, between and last among a page's runnable blocks, and in the first, middle and last of three pages"
  '(() () () () () ())
  (let ((readme (readme-of (org-src "scheme" twin)))
        (mine (string-append (fenced "scheme run" twin) "\n"))
        (other (lambda (k)
                 (string-append (fenced "scheme run" (list (number->string k)
                                                          (string-append ";; => " (number->string k))))
                                "\n")))
        (page (lambda parts (apply string-append "# Page\n\n" parts))))
    (list (twin-problems "R" readme (list (page mine (other 1) (other 2))))
          (twin-problems "R" readme (list (page (other 1) mine (other 2))))
          (twin-problems "R" readme (list (page (other 1) (other 2) mine)))
          (twin-problems "R" readme (list (page mine) (page (other 1)) (page (other 2))))
          (twin-problems "R" readme (list (page (other 1)) (page mine) (page (other 2))))
          (twin-problems "R" readme (list (page (other 1)) (page (other 2)) (page mine))))))

;; nested-blocks : String -> (Listof Natural)
;; The line of each block of the Org text ORG-TEXT that holds a #+begin_
;; line, in any case. org reads no block inside another, so a Scheme block
;; inside a quote would escape every block rule, the twin's among them.
(define (nested-blocks org-text)
  (map block-line
       (filter (lambda (b) (exists (lambda (l) (org-keyword l "#+begin_")) (block-lines b)))
               (car (org org-text)))))

(test-equal "nested-blocks: a quote holding a Scheme block, and an example holding one in capitals, are named by their lines; a quote of prose, and a src block beside a quote, are not"
  '((5) (5) () ())
  (list (nested-blocks (readme-of "#+begin_quote\n" (org-src "scheme" twin) "#+end_quote\n"))
        (nested-blocks (readme-of "#+begin_example\n#+BEGIN_SRC scheme\n(* 2 21)\n#+END_SRC\n#+end_example\n"))
        (nested-blocks (readme-of "#+begin_quote\nA quote of prose.\n#+end_quote\n"))
        (nested-blocks (readme-of (org-src "scheme" twin) "\n#+begin_quote\nProse.\n#+end_quote\n"))))

;; --- whole programs -------------------------------------------------------------------------------

;; first-datum : String -> (U (List Any) 'none 'unreadable)
;; The first datum Chez's read reads from the text, in a list; none when it
;; holds none, unreadable when read raises.
(define (first-datum text)
  (guard (e (#t 'unreadable))
    (let ((d (read (open-string-input-port text))))
      (if (eof-object? d) 'none (list d)))))

;; whole-program? : Block Boolean -> Boolean
;; A Markdown Scheme fragment whose first datum, as Chez's read reads the
;; block's text, is a list headed import: a program a reader saves and runs
;; whole. read skips a #!r6rs and comments before it.
(define (whole-program? b org?)
  (and (not org?)
       (string=? (block-language b) "scheme")
       (eq? (scheme-mark b org?) 'fragment)
       (let ((d (first-datum (joined (block-lines b)))))
         (and (pair? d) (pair? (car d)) (eq? (caar d) 'import)))))

;; text-after : Block (Listof Block) -> (U (Listof String) #f)
;; The lines of the first text block after B among its page's BLOCKS,
;; whatever lies between, when it comes before the next Scheme block; #f
;; when a Scheme block, or the page's end, comes first.
(define (text-after b blocks)
  (let ((rest (memq b blocks)))
    (and rest
         (let loop ((rest (cdr rest)))
           (cond ((null? rest) #f)
                 ((string=? (block-language (car rest)) "text") (block-lines (car rest)))
                 ((string=? (block-language (car rest)) "scheme") #f)
                 (else (loop (cdr rest))))))))

;; guards-unavailable? : Any -> Boolean
;; Whether X holds, at any depth, a guard with a clause whose test is
;; (sqlite-library-unavailable? V), V the guard's own variable.
(define (guards-unavailable? x)
  (cond ((pair? x)
         (or (and (eq? (car x) 'guard)
                  (pair? (cdr x)) (list? (cadr x)) (pair? (cadr x)) (symbol? (car (cadr x)))
                  (exists (lambda (clause)
                            (and (pair? clause)
                                 (equal? (car clause)
                                         (list 'sqlite-library-unavailable? (car (cadr x))))))
                          (cdr (cadr x))))
             (guards-unavailable? (car x))
             (guards-unavailable? (cdr x))))
        ((vector? x) (guards-unavailable? (vector->list x)))
        (else #f)))

;; refusal-shape : String -> (U 'one-refusal String)
;; one-refusal when TEXT is one datum, as write writes it, and a newline,
;; that datum a list whose first element is refused; else TEXT itself.
(define (refusal-shape text)
  (let ((d (datums text)))
    (if (and (= (length d) 1) (list? (car d)) (pair? (car d)) (eq? (caar d) 'refused)
             (string=? text (string-append (shown (car d)) "\n")))
        'one-refusal
        text)))

(test-equal "whole-program?: a Markdown fragment whose first datum, as read reads it, is a list headed import: past blanks, a #!r6rs, a line comment, a block comment and a datum comment, in brackets, with a datum after; not one whose import comes later, a quoted import, an imports, unreadable text, a runnable block, an Org block, another language, or an empty block"
  '(#t #t #t #t #t #t #t #t no no no no no no no no no)
  (let ((b (lambda (lang info lines) (make-block 1 lang info lines #t)))
        (yes-or-no (lambda (x) (if x #t 'no))))
    (list (yes-or-no (whole-program? (b "scheme" '() '("(import (rnrs))" "(display 1)")) #f))
          (yes-or-no (whole-program? (b "scheme" '() '("" "  (import (rnrs))")) #f))
          (yes-or-no (whole-program? (b "scheme" '() '("#!r6rs" "(import (rnrs))")) #f))
          (yes-or-no (whole-program? (b "scheme" '() '(";; app.sps" "(import (rnrs))")) #f))
          (yes-or-no (whole-program? (b "scheme" '() '("#| app.sps" "|# (import (rnrs))")) #f))
          (yes-or-no (whole-program? (b "scheme" '() '("#;(display 1)" "(import (rnrs))")) #f))
          (yes-or-no (whole-program? (b "scheme" '() '("[import (rnrs)]")) #f))
          (yes-or-no (whole-program? (b "scheme" '() '("#!r6rs ;; x" "" "(import (rnrs)) (display 1)")) #f))
          (yes-or-no (whole-program? (b "scheme" '() '("(display 1)" "(import (rnrs))")) #f))
          (yes-or-no (whole-program? (b "scheme" '() '("'(import (rnrs))")) #f))
          (yes-or-no (whole-program? (b "scheme" '() '("(imports (rnrs))")) #f))
          (yes-or-no (whole-program? (b "scheme" '() '("(import (rnrs)")) #f))
          (yes-or-no (whole-program? (b "scheme" '("run") '("(import (rnrs))" ";; => 1")) #f))
          (yes-or-no (whole-program? (b "scheme" '() '("(import (rnrs))")) #t))
          (yes-or-no (whole-program? (b "text" '() '("(import (rnrs))")) #f))
          (yes-or-no (whole-program? (b "sh" '() '("(import (rnrs))")) #f))
          (yes-or-no (whole-program? (b "scheme" '() '("" "")) #f)))))

(test-equal "text-after: the first text block's lines after it, right after, with prose between, past an sh block or two, the first of two; none when a Scheme block comes first, a runnable one or a fragment, or none follows"
  '(("out 1") ("out 2") ("late") ("two sh") none none ("after fragment") none)
  (let* ((page (markdown (string-append
                          (fenced "scheme" '("(import (rnrs))")) (fenced "text" '("out 1"))
                          (fenced "scheme" '("(import (rnrs))")) "\nIt prints:\n\n" (fenced "text" '("out 2"))
                          (fenced "scheme" '("(import (rnrs))")) (fenced "sh" '("ls")) "\nThen:\n\n"
                          (fenced "text" '("late"))
                          (fenced "scheme" '("(import (rnrs))")) (fenced "sh" '("ls")) (fenced "sh" '("pwd"))
                          (fenced "text" '("two sh")) (fenced "text" '("second"))
                          (fenced "scheme" '("(import (rnrs))")) (fenced "scheme run" '("1" ";; => 1"))
                          (fenced "text" '("after run"))
                          (fenced "scheme" '("(import (rnrs))"))
                          (fenced "scheme" '("(display 1)")) (fenced "text" '("after fragment"))
                          (fenced "scheme" '("(import (rnrs))")) (fenced "sh" '("ls")))))
         (bs (car page)))
    (map (lambda (b) (or (text-after b bs) 'none))
         (filter (lambda (b) (eq? (scheme-mark b #f) 'fragment))
                 (filter (lambda (b) (string=? (block-language b) "scheme")) bs)))))

(test-equal "guards-unavailable?: a guard clause (sqlite-library-unavailable? V) on its own variable, at any depth, among other clauses; not one on another variable, another predicate, or the name outside a guard"
  '(yes yes no no no)
  (map (lambda (text) (if (guards-unavailable? (datums text)) 'yes 'no))
       '("(import (rnrs)) (write (guard (e ((sqlite-library-unavailable? e) 'no)) 1))"
         "(define (f) (let () (vector (guard (c ((string? c) 1) ((sqlite-library-unavailable? c) 2)) 3))))"
         "(guard (e ((sqlite-library-unavailable? x) 'no)) 1)"
         "(guard (e ((sqlite-error? e) 'no)) 1)"
         "(list sqlite-library-unavailable? (sqlite-library-unavailable? e))")))

(test-equal "refusal-shape: one written datum and a newline, a list whose first element is refused; no newline, a line before, two data, another first element, a bare symbol, another spacing, or unreadable text is its own text"
  '(one-refusal one-refusal "(refused x)" "start\n(refused x)\n" "(refused x)\n(refused y)\n"
    "(denied x)\n" "refused\n" "(refused \"a\"  b)\n" "(refused x\n")
  (map refusal-shape
       '("(refused x)\n" "(refused load-failed \"/a b\")\n" "(refused x)" "start\n(refused x)\n"
         "(refused x)\n(refused y)\n" "(denied x)\n" "refused\n" "(refused \"a\"  b)\n" "(refused x\n")))

;; --- pipe tables and their cells ------------------------------------------------------------------

;; pipe-cells : String -> (Listof String)
;; The cells of a table line: the text between its |s, each trimmed, a |
;; after a backslash kept as |, the empty text before a leading | and after
;; a trailing one dropped.
(define (pipe-cells line)
  (let* ((s (trim line))
         (pieces (let loop ((cs (string->list s)) (piece '()) (out '()))
                   (cond ((null? cs) (reverse (cons (list->string (reverse piece)) out)))
                         ((and (char=? (car cs) #\\) (pair? (cdr cs)) (char=? (cadr cs) #\|))
                          (loop (cddr cs) (cons #\| piece) out))
                         ((char=? (car cs) #\|)
                          (loop (cdr cs) '() (cons (list->string (reverse piece)) out)))
                         (else (loop (cdr cs) (cons (car cs) piece) out)))))
         (pieces (if (starts? s "|") (cdr pieces) pieces))
         (pieces (if (and (pair? pieces) (ends? s "|") (not (ends? s "\\|")))
                     (reverse (cdr (reverse pieces)))
                     pieces)))
    (map trim pieces)))

;; delimiter-row? : (Listof String) -> Boolean
;; Cells each of one or more -, with a : at either end or both.
(define (delimiter-row? cells)
  (and (pair? cells)
       (for-all (lambda (c)
                  (let* ((c (if (starts? c ":") (substring c 1 (string-length c)) c))
                         (c (if (ends? c ":") (substring c 0 (- (string-length c) 1)) c)))
                    (and (> (string-length c) 0)
                         (for-all (lambda (ch) (char=? ch #\-)) (string->list c)))))
                cells)))

;; table-line? : String -> Boolean
(define (table-line? line)
  (let ((indent (run line 0 #\space)))
    (and (<= indent 3) (< indent (string-length line)) (char=? (string-ref line indent) #\|))))

;; tables : (Listof String) -> (Listof (List Natural (Listof String) (Listof (Listof String))))
;; Each pipe table of the prose: the number of its first line, its header's
;; cells, and each later row's cells, in order. A run of table lines whose
;; second is no delimiter row is no table.
(define (tables prose)
  (let loop ((ls prose) (n 1) (out '()))
    (cond ((null? ls) (reverse out))
          ((table-line? (car ls))
           (let collect ((rest ls) (k n) (taken '()))
             (if (and (pair? rest) (table-line? (car rest)))
                 (collect (cdr rest) (+ k 1) (cons (car rest) taken))
                 (let ((lines (reverse taken)))
                   (loop rest k
                         (if (and (pair? (cdr lines)) (delimiter-row? (pipe-cells (cadr lines))))
                             (cons (list n (pipe-cells (car lines)) (map pipe-cells (cddr lines))) out)
                             out))))))
          (else (loop (cdr ls) (+ n 1) out)))))

;; cell-span : String -> (U String (List 'not-one-code-span String))
;; The text of a cell that is one code span, whole; else why not, with it.
(define (cell-span cell)
  (let ((ranges (code-ranges cell)))
    (if (and (= (length ranges) 1) (= (caar ranges) 0) (= (cdar ranges) (string-length cell)))
        (car (code-spans cell))
        (list 'not-one-code-span cell))))

;; spans-at : String -> (Listof (List Natural Natural String))
;; Each code span of the text: where it begins, where it ends, its text.
(define (spans-at text)
  (map (lambda (r s) (list (car r) (cdr r) s)) (code-ranges text) (code-spans text)))

;; alternative-word : String (List Natural Natural String) -> (U String #f)
;; M, when the span of TEXT is written (`ALT` on M), M a word; else #f.
(define (alternative-word text span)
  (let ((s (car span)) (e (cadr span)) (n (string-length text)))
    (and (> s 0) (char=? (string-ref text (- s 1)) #\()
         (starts? (substring text e n) " on ")
         (let ((close (search text ")" (+ e 4))))
           (and close
                (let ((w (substring text (+ e 4) close)))
                  (and (> (string-length w) 0) (not (exists blank? (string->list w))) w)))))))

;; spans-on : String String -> (Listof String)
;; The code spans of CELL on the machine MACHINE: each that is no
;; alternative, in order, in its place an alternative for MACHINE written
;; right after it, when there is one.
(define (spans-on cell machine)
  (let loop ((rest (spans-at cell)) (out '()))
    (cond ((null? rest) (reverse out))
          ((alternative-word cell (car rest)) (loop (cdr rest) out))
          (else
           (let* ((alternatives (let take ((r (cdr rest)) (acc '()))
                                  (if (and (pair? r) (alternative-word cell (car r)))
                                      (take (cdr r) (cons (car r) acc))
                                      (reverse acc))))
                  (mine (find (lambda (a) (string=? (alternative-word cell a) machine)) alternatives)))
             (loop (cdr rest) (cons (caddr (or mine (car rest))) out)))))))

;; looks-in : String String -> (U (Listof String) (List 'unreadable String))
;; The paths a where-it-looks cell names on MACHINE, in order: none for no
;; code span, the one for one, and for more, `FILE` in `DIR`, ..., each
;; DIR/FILE. A cell of more whose first span " in " does not follow is
;; unreadable.
(define (looks-in cell machine)
  (let ((spans (spans-on cell machine)) (at (spans-at cell)))
    (cond ((null? spans) '())
          ((null? (cdr spans)) spans)
          ((starts? (substring cell (cadr (car at)) (string-length cell)) " in ")
           (map (lambda (dir) (string-append dir "/" (car spans))) (cdr spans)))
          (else (list 'unreadable cell)))))

;; spans-before : String String -> (Listof String)
;; The text of each code span of TEXT that AFTER follows, a line's end in
;; TEXT read as a space.
(define (spans-before text after)
  (let ((flat (list->string (map (lambda (c) (if (char=? c #\newline) #\space c)) (string->list text)))))
    (map caddr (filter (lambda (s) (starts? (substring flat (cadr s) (string-length flat)) after))
                       (spans-at flat)))))

;; distinct : (Listof String) -> (Listof String)
;; Each string once, at its first place.
(define (distinct xs)
  (let loop ((rest xs) (out '()))
    (cond ((null? rest) (reverse out))
          ((member (car rest) out) (loop (cdr rest) out))
          (else (loop (cdr rest) (cons (car rest) out))))))

;; stand-in-getenv : String -> (U String #f)
;; An environment in which GUIX_ENVIRONMENT, GUIX_PROFILE and HOME each name
;; a directory of its own, /@NAME, and nothing else is set.
(define (stand-in-getenv name)
  (and (member name '("GUIX_ENVIRONMENT" "GUIX_PROFILE" "HOME")) (string-append "/@" name)))

;; as-written : String -> String
;; A path under a stand-in's directory as the page writes it: /@HOME as ~,
;; any other /@NAME as $NAME; any other path as it is.
(define (as-written path)
  (let* ((slash (and (starts? path "/@") (or (search path "/" 2) (string-length path))))
         (name (and slash (substring path 2 slash))))
    (if (and name (not (string=? name "")))
        (string-append (if (string=? name "HOME") "~" (string-append "$" name))
                       (substring path slash (string-length path)))
        path)))

;; label-names? : String (List (U 'holds 'begins) String) -> Boolean
;; Whether a row's first cell names its world by RULE: (holds S), S
;; anywhere in it; (begins S), S at its start.
(define (label-names? cell rule)
  (if (eq? (car rule) 'begins)
      (starts? cell (cadr rule))
      (and (search cell (cadr rule) 0) #t)))

(define sample-tables
  '("Prose."
    "| A | B |"
    "|---|:-:|"
    "| `x` | y \\| z |"
    "|  | last |"
    ""
    "| not | a table |"
    "| no | delimiter |"
    ""
    "   | C |"
    "   |---|"
    "    | four spaces, no table line |"))

(test-equal "tables: each run of | lines whose second is a delimiter row, by its first line, its header and its rows; a run with no delimiter row is none, and four spaces end one"
  '((2 ("A" "B") (("`x`" "y | z") ("" "last")))
    (10 ("C") ()))
  (tables sample-tables))

(test-equal "pipe-cells: no outer |s, outer |s, a lone |, an escaped | at the end, and an empty cell"
  '(("a" "b") ("a") () ("a |") ("a" "" "b"))
  (map pipe-cells '("a | b" "| a |" "|" "| a \\|" "| a || b |")))

(test-equal "delimiter-row?: -, :-, -:, :-: cells; not an empty cell, a :, text, or no cell"
  '(yes no no no no)
  (map (lambda (cells) (if (delimiter-row? cells) 'yes 'no))
       '(("---" ":--" "--:" ":-:") ("---" "") (":") ("-a-") ())))

(test-equal "cell-span: a cell that is one code span, whole, single or double backticks; text beside it, two spans, none, and an empty cell are not"
  '("below-floor" "a ` b" (not-one-code-span "`a` b") (not-one-code-span "`a` `b`")
    (not-one-code-span "a") (not-one-code-span ""))
  (map cell-span '("`below-floor`" "``a ` b``" "`a` b" "`a` `b`" "a" "")))

(test-equal "looks-in: a file in each directory, in order; an alternative (`ALT` on M) in its span's place on M, first, between or last, and nothing elsewhere; one for another machine ignored; one path alone; none; and more spans not written FILE in DIR"
  '(("/a/f" "/b/f" "/c/f")
    ("/a/f" "/b/f" "/c/f")
    ("/x/f" "/b/f" "/c/f")
    ("/a/f" "/b/f")
    ("/a/f" "/y/f" "/c/f")
    ("/a/f" "/b/f" "/z/f")
    ("/a/f" "/b/f" "/c/f")
    ("/p/lib.dylib")
    ()
    (unreadable "`f` or `/a`"))
  (list (looks-in "`f` in `/a`, `/b`, then `/c`" "x86_64")
        (looks-in "`f` in `/a`, `/b`, then `/c`" "arm64")
        (looks-in "`f` in `/a` (`/x` on arm64), `/b`, then `/c`" "arm64")
        (looks-in "`f` in `/a` (`/x` on arm64), then `/b`" "x86_64")
        (looks-in "`f` in `/a`, `/b` (`/y` on arm64), then `/c`" "arm64")
        (looks-in "`f` in `/a`, `/b`, then `/c` (`/z` on arm64)" "arm64")
        (looks-in "`f` in `/a`, `/b` (`/y` on riscv64), then `/c`" "arm64")
        (looks-in "Apple's `/p/lib.dylib`" "arm64")
        (looks-in "nothing" "x86_64")
        (looks-in "`f` or `/a`" "x86_64")))

(test-equal "spans-before: each code span that the text follows, across a line's end; not one another text follows"
  '("override" "z")
  (spans-before "and `override` for\n`CHEZ_SQLITE3_LIBRARY`, `x` for `Y`, `z` for `CHEZ_SQLITE3_LIBRARY`"
                " for `CHEZ_SQLITE3_LIBRARY`"))

(test-equal "distinct: each once, at its first place"
  '("a" "b" "c")
  (distinct '("a" "b" "a" "c" "b")))

(test-equal "label-names?: holds finds its word at the cell's start, middle and end, and the whole cell; begins only at the start; neither in another case, nor in an empty cell"
  '(yes yes yes yes yes no no no no)
  (map (lambda (c) (if (label-names? (car c) (cadr c)) 'yes 'no))
       '(("Guix's C library" (holds "Guix")) ("Linux, on Guix's C" (holds "Guix")) ("Linux on Guix" (holds "Guix"))
         ("Mac" (holds "Mac")) ("Other Linux systems" (begins "Other Linux"))
         ("Linux, other" (begins "Other Linux")) ("Not any other" (begins "Any other"))
         ("macOS" (holds "Mac")) ("" (holds "Mac")))))

(test-equal "as-written: a stand-in's directory as $NAME, HOME's as ~, alone or before more; any other path unchanged"
  '("$GUIX_PROFILE/lib/x" "~/.guix-home/profile/lib/x" "~" "/usr/lib/x" "/@")
  (map as-written '("/@GUIX_PROFILE/lib/x" "/@HOME/.guix-home/profile/lib/x" "/@HOME" "/usr/lib/x" "/@")))

;; --- the variable's name, and its value ------------------------------------------------------------

;; word-char? : Char -> Boolean
(define (word-char? c)
  (or (and (char<=? #\a c) (char<=? c #\z)) (and (char<=? #\A c) (char<=? c #\Z)) (digit? c) (char=? c #\_)))

;; chez-words : String -> (Listof String)
;; Each word of the text, a run of letters, digits and _, that holds CHEZ_,
;; in order.
(define (chez-words s)
  (let ((n (string-length s)))
    (let loop ((i 0) (out '()))
      (cond ((>= i n) (reverse out))
            ((word-char? (string-ref s i))
             (let* ((j (let end ((j i)) (if (and (< j n) (word-char? (string-ref s j))) (end (+ j 1)) j)))
                    (w (substring s i j)))
               (loop j (if (search w "CHEZ_" 0) (cons w out) out))))
            (else (loop (+ i 1) out))))))

;; assignment-values : String -> (Listof String)
;; What follows each CHEZ_SQLITE3_LIBRARY= of the line that sets the
;; variable, up to a blank or the line's end: one at the line's start or
;; after a blank, as export X=, env X= and X=... before a command are. One
;; after any other char, as Org's verbatim =CHEZ_SQLITE3_LIBRARY= is, sets
;; nothing.
(define (assignment-values line)
  (let ((pat "CHEZ_SQLITE3_LIBRARY="))
    (let loop ((i 0) (out '()))
      (let ((j (search line pat i)))
        (if (not j)
            (reverse out)
            (let* ((start (+ j (string-length pat)))
                   (end (let e ((k start))
                          (if (and (< k (string-length line)) (not (blank? (string-ref line k)))) (e (+ k 1)) k))))
              (loop end (if (or (= j 0) (blank? (string-ref line (- j 1))))
                            (cons (substring line start end) out)
                            out))))))))

(test-equal "chez-words: each word that holds CHEZ_, at the text's start and end, after $, = or a backtick, before =, ' or a backtick, a letter before it or after; not CHEZ alone, CHEZSCHEME, or chez_"
  '("CHEZ_A" "CHEZ_SQLITE3_LIBRARY" "CHEZ_B_2" "CHEZ_C" "XCHEZ_D" "CHEZ_Ee" "CHEZ_F")
  (chez-words "CHEZ_A, $CHEZ_SQLITE3_LIBRARY=/x =CHEZ_B_2= `CHEZ_C`'s XCHEZ_D CHEZ_Ee CHEZ CHEZSCHEME chez_x CHEZ_F"))

(test-equal "chez-words: a word that holds CHEZ_, set at each place in a text, is found there alone"
  (let loop ((i 0) (out '())) (if (> i 6) out (loop (+ i 1) (cons '("CHEZ_Q") out))))
  (let ((s "a-b, c"))
    (let loop ((i 0) (out '()))
      (if (> i (string-length s))
          out
          (loop (+ i 1)
                (cons (chez-words (string-append (substring s 0 i) " CHEZ_Q " (substring s i (string-length s))))
                      out))))))

(test-equal "assignment-values: each value up to a blank, after export, indented, an empty one, two on a line, at the line's start before a command, past blanks or a tab, after env; none after =, as Org's verbatim is, a backtick, a $, a letter or a quote, nor without its ="
  '(("/a/b") ("rel") ("") ("/a;" "b") ("/x") ("lib.so") ("t") ("/e") () () () () () ())
  (map assignment-values
       '("export CHEZ_SQLITE3_LIBRARY=/a/b" "  export CHEZ_SQLITE3_LIBRARY=rel x" "export CHEZ_SQLITE3_LIBRARY="
         "export CHEZ_SQLITE3_LIBRARY=/a; export CHEZ_SQLITE3_LIBRARY=b"
         "CHEZ_SQLITE3_LIBRARY=/x scheme --program app.sps" "  CHEZ_SQLITE3_LIBRARY=lib.so scheme"
         "\tCHEZ_SQLITE3_LIBRARY=t" "env CHEZ_SQLITE3_LIBRARY=/e scheme"
         "=CHEZ_SQLITE3_LIBRARY= names it" "`CHEZ_SQLITE3_LIBRARY=x`" "$CHEZ_SQLITE3_LIBRARY=x"
         "XCHEZ_SQLITE3_LIBRARY=x" "'CHEZ_SQLITE3_LIBRARY=x'" "set CHEZ_SQLITE3_LIBRARY x")))

(test-equal "assignment-values: one after a blank, set at each place in a text, is found there alone; one after =, at each place, is not"
  (let loop ((i 0) (out '())) (if (> i 5) out (loop (+ i 1) (cons '(("v") ()) out))))
  (let ((s "a=b c"))
    (let loop ((i 0) (out '()))
      (if (> i (string-length s))
          out
          (loop (+ i 1)
                (cons (list (assignment-values (string-append (substring s 0 i) " CHEZ_SQLITE3_LIBRARY=v "
                                                              (substring s i (string-length s))))
                            (assignment-values (string-append (substring s 0 i) "=CHEZ_SQLITE3_LIBRARY=v "
                                                              (substring s i (string-length s)))))
                      out))))))

;; --- the pages ----------------------------------------------------------------------------------

;; read-page : String -> (U String (List 'unreadable String))
(define (read-page path) (guard (e (#t (list 'unreadable (describe e)))) (slurp path)))

;; docs-pages : (Listof String)
;; docs/*.md, sorted.
(define docs-pages
  (guard (e (#t (list "docs/unreadable")))
    (map (lambda (f) (string-append "docs/" f))
         (list-sort string<? (filter (lambda (f) (ends? f ".md")) (directory-list "docs"))))))

(define pages (cons "README.org" docs-pages))

(define (org-page? p) (ends? p ".org"))

;; page-texts : (Listof (Pair String (U String (List 'unreadable String))))
(define page-texts (map (lambda (p) (cons p (read-page p))) pages))

(define (text-of p) (cdr (assoc p page-texts)))

;; parsed : String -> (U (List Blocks Prose Headings) #f)
;; A page's reading: Markdown's three lists; Org's two, and no headings.
(define (parsed p)
  (let ((t (text-of p)))
    (and (string? t)
         (if (org-page? p)
             (let ((r (org t))) (list (car r) (cadr r) '()))
             (markdown t)))))

(define (blocks-of p) (let ((r (parsed p))) (if r (car r) '())))
(define (prose-of p) (let ((r (parsed p))) (if r (cadr r) '())))

;; anchors-of : String -> (U (Listof String) #f)
(define (anchors-of p)
  (let ((r (and (assoc p page-texts) (parsed p))))
    (and r (not (org-page? p)) (anchors (map cdr (caddr r))))))

;; checkout-exists? : String -> Boolean
(define (checkout-exists? p) (file-exists? p))

(test-equal "every page is read: README.org and the pages of docs/, and docs/ has the reference"
  '(() #t)
  (list (map car (filter (lambda (p) (not (string? (cdr p)))) page-texts))
        (and (member "docs/reference.md" pages) #t)))

;; --- the blocks -----------------------------------------------------------------------------------

(define allowed-languages '("scheme" "sh" "text"))
(define (allowed-language? b org?)
  (or (member (block-language b) allowed-languages)
      (and org? (string=? (block-language b) "#quote"))))

(test-equal "every block names its language, scheme, sh or text (Org: or a quote), and is closed, by page and line"
  '()
  (apply append
         (map (lambda (p)
                (apply append
                       (map (lambda (b)
                              (append (if (allowed-language? b (org-page? p)) '()
                                          (list (list p (block-line b) 'language (block-language b))))
                                      (if (block-closed? b) '() (list (list p (block-line b) 'unclosed)))))
                            (blocks-of p))))
              pages)))

(define (scheme-blocks p)
  (filter (lambda (b) (string=? (block-language b) "scheme")) (blocks-of p)))

(test-equal "every Scheme block is a fragment or runnable, by page and line"
  '()
  (apply append
         (map (lambda (p)
                (map (lambda (b) (list p (block-line b) 'unknown-mark (block-info b)))
                     (filter (lambda (b) (eq? (scheme-mark b (org-page? p)) 'unknown))
                             (scheme-blocks p))))
              pages)))

(test-equal "every fragment's text is data Chez reads, and holds a datum, by page and line"
  '()
  (apply append
         (map (lambda (p)
                (map (lambda (b) (list p (block-line b) 'fragment-unreadable))
                     (filter (lambda (b)
                               (and (eq? (scheme-mark b (org-page? p)) 'fragment)
                                    (let ((d (datums (joined (block-lines b)))))
                                      (or (equal? d '(unreadable)) (null? d)))))
                             (scheme-blocks p))))
              pages)))

;; --- the runnable examples ------------------------------------------------------------------------

(define run-env (guard (e (#t #f)) (environment '(rnrs) '(chez-sqlite3))))

(define zero-counts '((block . 0) (connection . 0) (statement . 0)))

;; each-in-order : (A -> B) (Listof A) -> (Listof B)
;; F applied to each item, first to last, and the answers in that order. An
;; example's run has effects, so it never goes through map, which calls its
;; procedure in no fixed order.
(define (each-in-order f items)
  (let loop ((rest items) (out '()))
    (if (null? rest)
        (reverse out)
        (let ((answer (f (car rest))))
          (loop (cdr rest) (cons answer out))))))

;; runs : (Listof (List String Natural Any Any))
;; Each runnable block of every Markdown page: its page, its line, what
;; check-run said, and the native counts when it was done.
(define runs
  (apply append
         (each-in-order
          (lambda (p)
            (each-in-order
             (lambda (b)
               (let* ((result (if run-env
                                  (check-run (block-lines b) run-env)
                                  '(bad no-environment)))
                      (counts (native-counts)))
                 (list p (block-line b) result counts)))
             (filter (lambda (b) (eq? (scheme-mark b (org-page? p)) 'run))
                     (scheme-blocks p))))
          pages)))

(test-equal "the docs have runnable examples at all"
  'some
  (if (null? runs) 'none 'some))

(for-each
 (lambda (r)
   (test-equal (string-append (car r) ":" (number->string (cadr r))
                              ": the runnable example gives the result it states")
     'ok
     (caddr r))
   (test-equal (string-append (car r) ":" (number->string (cadr r))
                              ": it leaves no native object open")
     zero-counts
     (cadddr r)))
 runs)

;; --- the README's example, through its twin ---------------------------------------------------------

;; text-or-empty : String -> String
(define (text-or-empty p) (let ((t (text-of p))) (if (string? t) t "")))

(test-equal "README.org holds a Scheme block, and each is, line for line, all of a runnable block of a page of docs/: the blocks that are not, by line"
  '()
  (twin-problems "README.org" (text-or-empty "README.org") (map text-or-empty docs-pages)))

(test-equal "README.org holds no block inside another, where a Scheme block would escape the block rules: the outer blocks' lines"
  '()
  (nested-blocks (text-or-empty "README.org")))

;; --- the links --------------------------------------------------------------------------------------

;; links-of : String -> (Listof String)
(define (links-of p)
  (if (org-page? p) (org-links (prose-of p)) (markdown-links (prose-of p))))

(test-equal "every relative link resolves to a file or directory of the checkout, its anchor to a heading, none into .plans/, by page and target"
  '()
  (apply append
         (map (lambda (p)
                (apply append
                       (map (lambda (t)
                              (let ((why (link-problem p t (org-page? p) checkout-exists? anchors-of)))
                                (if why (list (list p t why)) '())))
                            (links-of p))))
              pages)))

;; every file a page links, resolved from the root
(define (linked-files p)
  (apply append
         (map (lambda (t)
                (let ((parts (link-parts t (org-page? p))))
                  (if (and parts (not (eq? (car parts) 'own-page)))
                      (let ((path (resolve (dir-of p) (car parts)))) (if path (list path) '()))
                      '())))
              (links-of p))))

(test-equal "README.org links every page of docs/: the pages it leaves out"
  '()
  (filter (lambda (d) (not (member d (linked-files "README.org")))) docs-pages))

;; --- the headings -------------------------------------------------------------------------------------

(test-equal "every page of docs/ has one level-1 heading, and it is the page's first line: the others, by page and the lines of their level-1 headings"
  '()
  (apply append
         (map (lambda (p)
                (let ((lines (h1-lines (prose-of p))))
                  (if (equal? lines '(1)) '() (list (list p lines)))))
              docs-pages)))

;; --- the prose ----------------------------------------------------------------------------------------

(test-equal "no page says a banned phrase, by page"
  '()
  (apply append
         (map (lambda (p)
                (let ((found (forbidden (let ((t (text-of p))) (if (string? t) t "")))))
                  (if (null? found) '() (list (cons p found)))))
              pages)))

(define export-strings
  (guard (e (#t '("unreadable")))
    (let ((data (call-with-port
                 (open-file-input-port "src/chez-sqlite3.sls" (file-options) (buffer-mode block)
                                       (make-transcoder (utf-8-codec)))
                 read)))
      (map symbol->string (cdr (find (lambda (c) (and (pair? c) (eq? (car c) 'export))) (cddr data)))))))

(test-equal "every code span of the prose that is one sqlite- or chez-sqlite3- name is an export, by page"
  '()
  (apply append
         (map (lambda (p)
                (let ((bad (unknown-names (code-spans (joined (prose-of p)))
                                          export-strings)))
                  (map (lambda (n) (list p n)) bad)))
              pages)))

;; --- the variable's name, and its value, on the pages ----------------------------------------------

;; page-lines : String -> (Listof (Pair Natural String))
;; Every line of the page, in a block or not, with its number.
(define (page-lines p) (numbered (text-lines (text-or-empty p))))

(test-equal "the pages name CHEZ_SQLITE3_LIBRARY, and set it: the rules below hold words that are there"
  '(some some)
  (let ((all (apply append (map page-lines pages))))
    (list (if (exists (lambda (l) (pair? (chez-words (cdr l)))) all) 'some 'none)
          (if (exists (lambda (l) (pair? (assignment-values (cdr l)))) all) 'some 'none))))

(test-equal "every word of a page that holds CHEZ_, in a block or not, is CHEZ_SQLITE3_LIBRARY: the others, by page and line"
  '()
  (apply append
         (map (lambda (p)
                (apply append
                       (map (lambda (l)
                              (map (lambda (w) (list p (car l) w))
                                   (filter (lambda (w) (not (string=? w "CHEZ_SQLITE3_LIBRARY")))
                                           (chez-words (cdr l)))))
                            (page-lines p))))
              pages)))

(test-equal "every CHEZ_SQLITE3_LIBRARY= of a page that sets it, at a line's start or after a blank, in a block or not, gives it a value that begins with /: the others, by page and line"
  '()
  (apply append
         (map (lambda (p)
                (apply append
                       (map (lambda (l)
                              (map (lambda (v) (list p (car l) v))
                                   (filter (lambda (v) (not (starts? v "/"))) (assignment-values (cdr l)))))
                            (page-lines p))))
              pages)))

;; --- finding-sqlite.md's tables, held to the code --------------------------------------------------

(define finding-page "docs/finding-sqlite.md")

;; The page's prose, none when the page is not among the pages read, so
;; each row below fails by its name.
(define finding-prose (guard (e (#t '())) (prose-of finding-page)))

(define finding-tables (tables finding-prose))

;; table-headed : String -> (U (List Natural (Listof String) (Listof (Listof String))) (List 'tables Natural))
;; The one table of the page whose header's first cell is HEAD; else how
;; many there are.
(define (table-headed head)
  (let ((found (filter (lambda (t) (and (pair? (cadr t)) (string=? (car (cadr t)) head))) finding-tables)))
    (if (= (length found) 1) (car found) (list 'tables (length found)))))

;; rows-of : (U Table (List 'tables Natural)) -> (U (Listof (Listof String)) (List 'tables Natural))
(define (rows-of t) (if (symbol? (car t)) t (caddr t)))

;; no-table? : Any -> Boolean
;; Whether ROWS is table-headed's answer that no one table has its header.
(define (no-table? rows) (and (pair? rows) (eq? (car rows) 'tables)))

(define library-reasons
  (guard (e (#t (list 'raised (describe e))))
    (map symbol->string sqlite-library-unavailable-reasons)))

(test-equal "finding-sqlite.md: the reasons table's first column is the library's refusal reasons, in its order, each cell one code span"
  library-reasons
  (let ((rows (rows-of (table-headed "Reason"))))
    (if (no-table? rows)
        rows
        (map (lambda (row) (if (pair? row) (cell-span (car row)) (list 'no-cell row))) rows))))

;; discovery-worlds : (Listof (List String (U 'guix 'fhs #f) (Listof (Pair Symbol String))
;;                                   (List (U 'holds 'begins) String)))
;; Discovery's worlds, in the table's order: each one's name, the world
;; libsqlite3-candidates takes, the machine types it is read on, each with
;; the word a row's (`ALT` on WORD) names it by, and how its row's first
;; cell names it, as label-names? reads a rule.
(define discovery-worlds
  '(("Guix" guix ((ta6le . "x86_64") (tarm64le . "arm64")) (holds "Guix"))
    ("other Linux" fhs ((ta6le . "x86_64") (tarm64le . "arm64")) (begins "Other Linux"))
    ("macOS" #f ((ta6osx . "x86_64") (tarm64osx . "arm64")) (holds "Mac"))
    ("any other system" #f ((ta6fb . "x86_64") (tarm64nt . "arm64")) (begins "Any other"))))

;; world-indices : (Listof Natural)
;; Each world's place in the table, from 0.
(define world-indices
  (let loop ((k (- (length discovery-worlds) 1)) (out '())) (if (< k 0) out (loop (- k 1) (cons k out)))))

;; discovery-says : (U 'guix 'fhs #f) Symbol -> (U (List (Listof String) (Listof String)) (List 'raised String))
;; Discovery's candidates for WORLD on MACHINE-TYPE, with the stand-in
;; environment: their paths as the page writes them, and their sources,
;; each once, in order.
(define (discovery-says world machine-type)
  (guard (e (#t (list 'raised (describe e))))
    (let ((cs (libsqlite3-candidates world machine-type stand-in-getenv)))
      (list (map (lambda (c) (as-written (car c))) cs)
            (distinct (map (lambda (c) (symbol->string (cdr c))) cs))))))

;; row-says : (Listof String) String -> (U (List (Listof String) (Listof String)) (List 'cells (Listof String)))
;; A discovery row read on MACHINE: the paths its second cell names, and its
;; third cell's code spans.
(define (row-says cells machine)
  (if (= (length cells) 3)
      (list (looks-in (cadr cells) machine) (code-spans (caddr cells)))
      (list 'cells cells)))

(define discovery-rows (rows-of (table-headed "System")))

(test-equal "finding-sqlite.md: the discovery table has a row for each of discovery's worlds, and no other"
  (length discovery-worlds)
  (if (no-table? discovery-rows) discovery-rows (length discovery-rows)))

(for-each
 (lambda (w k)
   (test-equal (string-append "finding-sqlite.md: the discovery table's row " (number->string (+ k 1))
                              ", for " (car w) ", names discovery's candidates, by the paths it writes, and their sources, in order, on x86_64 and on arm64")
     (map (lambda (m) (discovery-says (cadr w) (car m))) (caddr w))
     (if (and (not (no-table? discovery-rows)) (> (length discovery-rows) k))
         (map (lambda (m) (row-says (list-ref discovery-rows k) (cdr m))) (caddr w))
         'no-row)))
 discovery-worlds
 world-indices)

(for-each
 (lambda (w k)
   (let ((rule (cadddr w)))
     (test-equal (string-append "finding-sqlite.md: the discovery table's row " (number->string (+ k 1))
                                ", for " (car w) ", names its world in its first cell, which "
                                (if (eq? (car rule) 'begins) "begins " "holds ") (cadr rule))
       'names-its-world
       (if (and (not (no-table? discovery-rows)) (> (length discovery-rows) k)
                (pair? (list-ref discovery-rows k)))
           (let ((cell (car (list-ref discovery-rows k))))
             (if (label-names? cell rule) 'names-its-world (list 'first-cell cell)))
           'no-row))))
 discovery-worlds
 world-indices)

;; override-source : (U String (List 'raised String))
;; The source discovery gives a path CHEZ_SQLITE3_LIBRARY names.
(define override-source
  (guard (e (#t (list 'raised (describe e))))
    (call-with-values
     (lambda () (choose-libsqlite3 (lambda (name) (and (string=? name "CHEZ_SQLITE3_LIBRARY") "/@override/lib.so"))
                                   'ta6le #f (lambda (path) #f)))
     (lambda (path source) (symbol->string source)))))

(define prose-override-sources
  (spans-before (joined finding-prose) " for `CHEZ_SQLITE3_LIBRARY`"))

(test-equal "finding-sqlite.md: its prose names the source an override gets, in the one code span before \" for `CHEZ_SQLITE3_LIBRARY`\""
  (list override-source)
  prose-override-sources)

(test-equal "finding-sqlite.md: the discovery table's sources and the prose's override source are discovery's sources, each once"
  (guard (e (#t (list 'raised (describe e))))
    (list-sort string<? (map symbol->string libsqlite3-sources)))
  (list-sort string<?
             (append (if (no-table? discovery-rows)
                         (list (shown discovery-rows))
                         (apply append (map (lambda (row) (if (= (length row) 3) (code-spans (caddr row)) '()))
                                            discovery-rows)))
                     prose-override-sources)))

;; --- the load a guard cannot catch ------------------------------------------------------------------
;; docs/reference.md says a library that fails to load is caught by an eval
;; inside the guard, and not by a guard around a direct call, since the load
;; runs at the program's start or before the form's guard is in place. A
;; child of each kind, with CHEZ_SQLITE3_LIBRARY naming a file that is not
;; there, shows both. Each runs through gated-command, so under make
;; test-memory the gate's own Valgrind runs it, and says so on its last line.

(define chez (getenv "CHEZ"))

;; The file the override names, which is not there.
(define missing-library "/no/such/directory/libsqlite3.so")

;; The block of docs/reference.md that shows the guard around an eval: the
;; one Scheme block of the page that holds an (environment '(chez-sqlite3)).
(define docs-guard-blocks
  (filter (lambda (b)
            (search (joined (block-lines b)) "(environment '(chez-sqlite3))" 0))
          (scheme-blocks "docs/reference.md")))

;; docs-guard : (U Datum (List 'blocks Natural))
;; The datum of that block, as the docs show it.
(define docs-guard
  (if (= (length docs-guard-blocks) 1)
      (let ((d (datums (joined (block-lines (car docs-guard-blocks))))))
        (if (= (length d) 1) (car d) (list 'blocks (length d))))
      (list 'blocks (length docs-guard-blocks))))

;; Prints whether this process runs under memcheck: its preload is in /proc/self/maps.
(define valgrind-printer
  (string-append
   "(write (cons 'valgrind\n"
   "            (guard (e (#t 'no-maps))\n"
   "              (let ((maps (call-with-port\n"
   "                           (open-file-input-port \"/proc/self/maps\" (file-options) (buffer-mode block)\n"
   "                                                 (make-transcoder (utf-8-codec)))\n"
   "                           get-string-all))\n"
   "                    (needle \"vgpreload_memcheck\"))\n"
   "                (let loop ((i 0))\n"
   "                  (cond ((> (+ i (string-length needle)) (string-length maps)) 'no)\n"
   "                        ((string=? (substring maps i (+ i (string-length needle))) needle) 'yes)\n"
   "                        (else (loop (+ i 1)))))))))\n"
   "(newline)\n"))

;; The last line a child prints: yes exactly when the gate asked.
(define valgrind-line
  (string-append "(valgrind . "
                 (cond ((getenv "CHEZ_SQLITE3_GATE_CHILD") "yes")
                       ((file-exists? "/proc/self/maps") "no")
                       (else "no-maps"))
                 ")\n"))

;; write-text : String String -> Void
(define (write-text path text)
  (call-with-port
   (open-file-output-port path (file-options no-fail) (buffer-mode block)
                          (make-transcoder (utf-8-codec)))
   (lambda (p) (put-string p text))))

;; The library path a reader gives: the quick start's --libdirs names the
;; clone's src and nothing else, so a program that imports anything more
;; fails for the reader, and must fail here.
(define reader-libdirs "src")

;; program-run : (U String #f) String -> (U (List Integer String String) (List 'raised String))
;; TEXT, as written, run as a program in a fresh Chez with a reader's
;; library path, through gated-command, with CHEZ_SQLITE3_LIBRARY set to
;; OVERRIDE, or as the environment has it for #f; and the status, stdout and
;; stderr it gave.
(define (program-run override text)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (base)
       (let ((program (string-append base "/child.sps")))
         (write-text program text)
         (capture-command
          (append (if override
                      (list "env" (string-append "CHEZ_SQLITE3_LIBRARY=" override))
                      '())
                  (gated-command getenv
                                 (list chez "--libdirs" reader-libdirs
                                       "--program" program)))))))))

;; child : (U String #f) String -> (U (List Integer String String) (List 'raised String))
;; A program of BODY, after its imports, and then the valgrind printer, run
;; as program-run runs one.
(define (child override body)
  (program-run override
               (string-append "#!r6rs\n(import (rnrs) (rnrs eval) (chez-sqlite3))\n"
                              body "\n" valgrind-printer)))

(test-equal "a program that evals a loading call inside the guard the docs show, with the library missing, catches the refusal: it ran to its end, and printed what the guard answered"
  (list 0 (string-append "start\nno-sqlite\n" valgrind-line) "")
  (child missing-library
         (string-append "(display \"start\\n\")\n(write " (shown docs-guard) ")\n(newline)")))

(test-equal "the docs show one guard around an eval, and it answers no-sqlite when the library is missing"
  '(guard (e ((sqlite-library-unavailable? e) 'no-sqlite))
     (eval '(sqlite-version) (environment '(chez-sqlite3))))
  docs-guard)

(test-equal "a program that calls a loading procedure directly inside a guard, with the library missing, dies before its first line, and the guard catches nothing: its stdout is empty"
  '(died "")
  (let ((answer (child missing-library
                       (string-append
                        "(display \"start\\n\")\n"
                        "(write (guard (e ((sqlite-library-unavailable? e) 'caught)) (sqlite-version)))\n"
                        "(newline)"))))
    (if (and (pair? answer) (integer? (car answer)))
        (list (if (zero? (car answer)) 'ran 'died) (cadr answer))
        answer)))

(test-equal "the same program with the library there, a control, runs to its end: the version it prints is a string, and its first line prints too"
  (list 0 (string-append "start\n#t\n" valgrind-line) "")
  (child #f
         (string-append "(display \"start\\n\")\n"
                        "(write (guard (e ((sqlite-library-unavailable? e) 'caught)) (string? (sqlite-version))))\n"
                        "(newline)")))

;; --- the whole programs, run as written ----------------------------------------------------------
;; Each runs through program-run, so under make test-memory the gate's own
;; Valgrind runs it, and reads its log; Valgrind writes to that log, not to
;; the program's stdout or stderr. A whole program prints no valgrind line
;; of its own: the rows above, whose children run through the same
;; program-run, print one, and fail when the gate asked and it says no.

;; whole-programs : (Listof (List String Block (U (Listof String) #f) Boolean))
;; Each whole program of every Markdown page: its page, its block, the
;; lines of the text block after it or #f, and whether it holds a guard on
;; sqlite-library-unavailable?.
(define whole-programs
  (apply append
         (map (lambda (p)
                (let ((bs (blocks-of p)))
                  (map (lambda (b)
                         (list p b (text-after b bs) (guards-unavailable? (datums (joined (block-lines b))))))
                       (filter (lambda (b) (whole-program? b (org-page? p))) bs))))
              pages)))

;; program-runs : (Listof (List String Natural (U (Listof String) #f) Run (U Run #f)))
;; Each whole program's page, line and text block's lines, what it gave run
;; as the environment has the library, and, for one that guards
;; sqlite-library-unavailable?, what it gave with the library missing.
(define program-runs
  (each-in-order
   (lambda (w)
     (let* ((text (joined (block-lines (cadr w))))
            (present (program-run #f text))
            (missing (and (cadddr w) (program-run missing-library text))))
       (list (car w) (block-line (cadr w)) (caddr w) present missing)))
   whole-programs))

;; status-and-stderr, stdout-of, refusal-of : Run -> ...
;; What a row asserts of a run's answer, or the answer when the run raised.
(define (ran? r) (integer? (car r)))
(define (status-and-stderr r) (if (ran? r) (list (car r) (caddr r)) r))
(define (stdout-of r) (if (ran? r) (cadr r) r))
(define (refusal-of r) (if (ran? r) (list (car r) (refusal-shape (cadr r)) (caddr r)) r))

;; loaded-line : (U String (List 'raised String))
;; What the suite reads itself of the library it loaded, as a program that
;; guards sqlite-library-unavailable? prints it with the library there: the
;; list of its version, path and source, written, and a newline.
(define loaded-line
  (guard (e (#t (list 'raised (describe e))))
    (string-append (shown (eval '(list (sqlite-version) (sqlite-library-path) (sqlite-library-source)) run-env))
                   "\n")))

(test-equal "the docs hold whole programs, and one of them guards sqlite-library-unavailable?"
  '(some some)
  (list (if (null? whole-programs) 'none 'some)
        (if (exists cadddr whole-programs) 'some 'none)))

(test-equal "a whole program of the docs has a text block after it that holds what it prints"
  'some
  (if (exists caddr whole-programs) 'some 'none))

(for-each
 (lambda (r)
   (let ((name (string-append (car r) ":" (number->string (cadr r)) ": the whole program, run as written, ")))
     (test-equal (string-append name "exits 0 with nothing on stderr")
       '(0 "")
       (status-and-stderr (list-ref r 3)))
     (when (caddr r)
       (test-equal (string-append name "prints the text block after it, line for line")
         (joined (caddr r))
         (stdout-of (list-ref r 3))))
     (when (list-ref r 4)
       (test-equal (string-append name "with the library there, prints the version, path and source the suite reads itself, the list written, and a newline")
         loaded-line
         (stdout-of (list-ref r 3)))
       (test-equal (string-append name "with CHEZ_SQLITE3_LIBRARY naming a missing file, exits 0 with nothing on stderr and prints one datum, a list whose first element is refused")
         '(0 one-refusal "")
         (refusal-of (list-ref r 4))))))
 program-runs)

(test-end "docs")

;; SRFI-64 sets no exit status; this is the shared form.
(exit (suite-exit-status runner))
