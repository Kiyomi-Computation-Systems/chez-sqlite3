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
;;; - no page says ADR- or TODO, "not yet", "unreleased", "slice", a path in
;;;   .plans, or a date written YYYY-MM-DD, in any case;
;;; - every code span of a page's prose that is one name beginning sqlite- or
;;;   chez-sqlite3- is an export of (chez-sqlite3).
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
                    '("adr-" "todo" "not yet" "unreleased" "slice" ".plans"))
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

(test-equal "forbidden: each banned phrase, in any case across a line's end, and a date"
  '(("adr-" "todo" "not yet" "slice" ".plans" "a date") ())
  (list (forbidden "see ADR-0001, TODO: Not\nyet, a Slice of .plans/x on 2026-11-14")
        (forbidden "Nothing to see: 2026-1-14 or 20261114.")))

(test-equal "unknown-names: only the name-like spans that are no export, sorted, each once"
  '("chez-sqlite3-nope" "sqlite-nope")
  (unknown-names '("sqlite-nope" "sqlite-ok" "chez-sqlite3-nope" "sqlite-nope" "sqlite-x y" "Sqlite-Q"
                   "(sqlite-nope)" "open-database")
                 '("sqlite-ok" "open-database")))

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
  (string-append "(valgrind . " (if (getenv "CHEZ_SQLITE3_GATE_CHILD") "yes" "no") ")\n"))

;; write-text : String String -> Void
(define (write-text path text)
  (call-with-port
   (open-file-output-port path (file-options no-fail) (buffer-mode block)
                          (make-transcoder (utf-8-codec)))
   (lambda (p) (put-string p text))))

;; child : (U String #f) String -> (U (List Integer String String) (List 'raised String))
;; A program of BODY, after its imports, run in a fresh Chez, with
;; CHEZ_SQLITE3_LIBRARY set to OVERRIDE, or as the environment has it for #f,
;; and the status, stdout and stderr it gave.
(define (child override body)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (base)
       (let ((program (string-append base "/child.sps")))
         (write-text program
                     (string-append "#!r6rs\n(import (rnrs) (rnrs eval) (chez-sqlite3))\n"
                                    body "\n" valgrind-printer))
         (capture-command
          (append (if override
                      (list "env" (string-append "CHEZ_SQLITE3_LIBRARY=" override))
                      '())
                  (gated-command getenv
                                 (list chez "--libdirs" "src:tests:build/scheme-libs"
                                       "--program" program)))))))))

;; shown : Datum -> String
(define (shown d)
  (call-with-string-output-port (lambda (p) (write d p))))

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

(test-end "docs")

;; SRFI-64 sets no exit status; this is the shared form.
(exit (suite-exit-status runner))
