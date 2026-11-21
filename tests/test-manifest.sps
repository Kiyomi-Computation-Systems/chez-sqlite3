#!r6rs
;;; The suite for Akku.manifest, Akku.lock, CHANGELOG.md, .gitattributes and
;;; the clone lines of README.org and docs/, which no tool checks for us. It
;;; reads them as data and compares whole values:
;;;
;;;   - the package is chez-sqlite3, one akku-package form, licensed
;;;     BSD-3-Clause;
;;;   - it has no depends clause: the libraries bind libsqlite3 directly and
;;;     need no Scheme library at runtime (ADR-0001), and chez-srfi is the
;;;     suites' own, not a consumer's (ADR-0007);
;;;   - it has no scripts clause: Akku's script mechanism prompts on every
;;;     install, and nothing here builds (see Akku.manifest);
;;;   - its depends/dev is exactly chez-srfi, in the range that names the
;;;     pinned version, and chez-cmark-gfm, which renders the docs site
;;;     alone (ADR-0007);
;;;   - Akku.lock holds two projects, chez-cmark-gfm then chez-srfi, each
;;;     url holding the version Akku.manifest asks for, and each carrying a
;;;     sha256: chez-cmark-gfm's the archive `make site-deps` fetches and
;;;     checks;
;;;   - the package's version is CHANGELOG.md's latest release, or 0.0.0
;;;     while there is none, so a release that bumps one alone fails;
;;;   - CHANGELOG.md's latest release has an entry that says something, and
;;;     the link references [Unreleased] and its own, each once and naming
;;;     its tag; while there is no release, no line is a link reference;
;;;   - .gitattributes, its comments and blank lines aside, is exactly
;;;     /.plans export-ignore and /AGENTS.md export-ignore, in that order, so
;;;     a release archive leaves out the design records and the agents'
;;;     instructions (ADR-0022). git archive reads the file of the tree it
;;;     archives, so a tag's archive follows the tag's file.
;;;
;;; The clone lines. Every line of README.org, or of any file under docs/,
;;; that holds "git clone" is, past its leading spaces, exactly
;;; git clone --branch vX.Y.Z https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git
;;; X.Y.Z being Akku.manifest's version; while that is 0.0.0, with no
;;; release, the same line without --branch vX.Y.Z, which clones the default
;;; branch the docs there describe. README.org holds one, docs/quickstart.md
;;; one, and another page any number. So a release that bumps the
;;; manifest and the changelog bumps the clone lines with them, or fails
;;; (ADR-0007, ADR-0022). Other spellings, as git  clone with two spaces, are
;;; no clone line.
;;;
;;; CHANGELOG.md is read as Keep a Changelog writes it: `# Changelog` first,
;;; then `## [Unreleased]`, then each release's `## [X.Y.Z] - YYYY-MM-DD`, the
;;; newest first,
;;; each version below the one above it and dated no later. It raises at a
;;; `## ` heading of any other form, and at any other line beginning `#`, up
;;; to three spaces in, that holds `[` before a digit: so a release written
;;; wrongly, at another level, indented, or out of order, is never skipped for
;;; an older one. Lines inside a fenced block are not headings. A yanked
;;; release's `[YANKED]` is refused too: the first release yanked amends this.
;;; The link references are Keep a Changelog's: `[Unreleased]` compares the
;;; latest release's tag with HEAD; the first release links its tag's
;;; release page, and each later one compares the tag below it with its own.
;;; A release's entry runs from its heading to the next `## ` heading, and
;;; says something when one of its lines, past its blanks, begins with no #
;;; and is no link reference.
;;;
;;; make test runs every suite from the repository root, where all these
;;; files are. The clone check takes its root and its version as arguments,
;;; and is held on fixture trees under tests/fixtures/clone-lines first.
;;;
;;; Each expected value is one the code under test cannot produce by failing.
;;; SRFI-64 turns a raise in the actual expression into #f, so no expected
;;; value here is #f.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) directory-list file-directory?)
        (chez-sqlite3-testing))

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

;; read-data : String -> (Listof Any)
;; Every datum in the file at PATH, but its (import ...) forms. Chez's reader
;; skips the #!r6rs line itself.
(define (read-data path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                        (make-transcoder (utf-8-codec)))
    (lambda (port)
      (let loop ((found '()))
        (let ((datum (read port)))
          (cond ((eof-object? datum) (reverse found))
                ((and (pair? datum) (eq? (car datum) 'import)) (loop found))
                (else (loop (cons datum found)))))))))

;; the-form : Symbol String -> Any
;; The one form in the file at PATH whose first element is HEAD. It raises
;; unless there is exactly one, so a file without the form fails a test and
;; never passes one by having nothing in it.
(define (the-form head path)
  (let ((forms (filter (lambda (datum) (and (pair? datum) (eq? (car datum) head)))
                       (read-data path))))
    (if (= (length forms) 1)
        (car forms)
        (assertion-violation 'the-form "expected exactly one form" head path
                             (length forms)))))

;; package-clauses : Symbol -> (Listof Any)
;; Every clause named NAME in Akku.manifest's akku-package form, whole:
;; (NAME . body).
(define (package-clauses name)
  (filter (lambda (clause) (and (pair? clause) (eq? (car clause) name)))
          (cddr (the-form 'akku-package "Akku.manifest"))))

;; dev-version : String -> String
;; The version Akku.manifest asks the project NAME for: the range of its
;; entry in depends/dev, without the ^.
(define (dev-version name)
  (let ((range (cadr (assoc name (cdr (car (package-clauses 'depends/dev)))))))
    (substring range 1 (string-length range))))

;; package-version : -> String
;; The version Akku.manifest gives the package itself.
(define (package-version)
  (cadr (cadr (the-form 'akku-package "Akku.manifest"))))

;; lock-projects : -> (Listof Any)
;; Every project form of Akku.lock, whole.
(define (lock-projects)
  (cdr (the-form 'projects "Akku.lock")))

;; hex-sha256? : Any -> Boolean
;; Whether X is a string of 64 lowercase hex digits.
(define (hex-sha256? x)
  (and (string? x)
       (= (string-length x) 64)
       (for-all (lambda (c) (or (char<=? #\0 c #\9) (char<=? #\a c #\f))) (string->list x))))

;; lock-urls : String -> (Listof String)
;; The url of every project named NAME in Akku.lock.
(define (lock-urls name)
  (map (lambda (project) (cadr (assq 'url (cdr (assq 'location project)))))
       (filter (lambda (project) (equal? (assq 'name project) (list 'name name)))
               (lock-projects))))

;; contains? : String String -> Boolean
;; Whether PART occurs in WHOLE.
(define (contains? whole part)
  (let ((n (string-length whole)) (m (string-length part)))
    (let loop ((i 0))
      (cond ((> (+ i m) n) #f)
            ((string=? (substring whole i (+ i m)) part) #t)
            (else (loop (+ i 1)))))))

;; starts-with? : String String -> Boolean
;; Whether TEXT begins with PREFIX.
(define (starts-with? text prefix)
  (and (>= (string-length text) (string-length prefix))
       (string=? (substring text 0 (string-length prefix)) prefix)))

;; ascii-digit? : Char -> Boolean
;; Whether C is 0 to 9. char-numeric? takes other digits too.
(define (ascii-digit? c)
  (char<=? #\0 c #\9))

;; cut-at : String Char -> (Listof String)
;; TEXT cut at every SEPARATOR, empty fields kept.
(define (cut-at text separator)
  (let loop ((i (- (string-length text) 1)) (end (string-length text)) (found '()))
    (cond ((< i 0) (cons (substring text 0 end) found))
          ((char=? (string-ref text i) separator)
           (loop (- i 1) i (cons (substring text (+ i 1) end) found)))
          (else (loop (- i 1) end found)))))

;; version-number? : String -> Boolean
;; Whether TEXT is one of a semantic version's numbers: ASCII digits, with no
;; leading zero but a lone 0.
(define (version-number? text)
  (and (> (string-length text) 0)
       (for-all ascii-digit? (string->list text))
       (or (= (string-length text) 1)
           (not (char=? (string-ref text 0) #\0)))))

;; date? : String -> Boolean
;; Whether TEXT is YYYY-MM-DD: ten characters, ASCII digits but the two
;; hyphens, the month 01 to 12 and the day 01 to 31.
(define (date? text)
  (and (= (string-length text) 10)
       (let loop ((i 0))
         (or (= i 10)
             (and (if (memv i '(4 7))
                      (char=? (string-ref text i) #\-)
                      (ascii-digit? (string-ref text i)))
                  (loop (+ i 1)))))
       (let ((month (string->number (substring text 5 7)))
             (day (string->number (substring text 8 10))))
         (and (<= 1 month 12) (<= 1 day 31)))))

;; release-version : String -> (U String #f)
;; X.Y.Z when LINE is exactly `## [X.Y.Z] - YYYY-MM-DD`; #f for any other
;; line.
(define (release-version line)
  (and (starts-with? line "## [")
       (let ((rest (substring line 4 (string-length line))))
         (let ((parts (cut-at rest #\])))
           (and (= (length parts) 2)
                (let ((version (car parts)) (tail (cadr parts)))
                  (and (let ((numbers (cut-at version #\.)))
                         (and (= (length numbers) 3)
                              (for-all version-number? numbers)))
                       (starts-with? tail " - ")
                       (date? (substring tail 3 (string-length tail)))
                       version)))))))

;; release-date : String -> String
;; The date of a LINE release-version takes.
(define (release-date line)
  (substring line (- (string-length line) 10) (string-length line)))

;; version-numbers : String -> (Listof Integer)
;; X.Y.Z's three numbers, of a version release-version gave.
(define (version-numbers version)
  (map string->number (cut-at version #\.)))

;; version<? : (Listof Integer) (Listof Integer) -> Boolean
;; Whether version A comes before B, number by number.
(define (version<? a b)
  (cond ((null? a) #f)
        ((< (car a) (car b)) #t)
        ((> (car a) (car b)) #f)
        (else (version<? (cdr a) (cdr b)))))

;; indent : String -> Integer
;; How many spaces LINE begins with.
(define (indent line)
  (let loop ((i 0))
    (if (and (< i (string-length line)) (char=? (string-ref line i) #\space))
        (loop (+ i 1))
        i)))

;; fence-char : String -> (U Char #f)
;; The fence a LINE opens or closes, #\` or #\~, three of it up to three
;; spaces in; #f for any other line.
(define (fence-char line)
  (let ((i (indent line)))
    (and (<= i 3)
         (>= (string-length line) (+ i 3))
         (let ((c (string-ref line i)))
           (and (memv c '(#\` #\~))
                (char=? (string-ref line (+ i 1)) c)
                (char=? (string-ref line (+ i 2)) c)
                c)))))

;; release-like? : String -> Boolean
;; Whether LINE holds `[` before an ASCII digit.
(define (release-like? line)
  (let loop ((i 0))
    (and (< (+ i 1) (string-length line))
         (or (and (char=? (string-ref line i) #\[)
                  (ascii-digit? (string-ref line (+ i 1))))
             (loop (+ i 1))))))

;; section-headings : (Listof String) -> (Listof String)
;; Every `## ` heading of a changelog's LINES outside a fenced block, in
;; order. It raises at any other line outside one that begins `#`, up to
;; three spaces in, and holds `[` before a digit.
(define (section-headings lines)
  (let loop ((lines lines) (fence #f) (found '()))
    (cond ((null? lines) (reverse found))
          (fence
           (loop (cdr lines) (if (eqv? (fence-char (car lines)) fence) #f fence) found))
          ((fence-char (car lines))
           => (lambda (c) (loop (cdr lines) c found)))
          ((starts-with? (car lines) "## ")
           (loop (cdr lines) #f (cons (car lines) found)))
          ((let ((i (indent (car lines))))
             (and (<= i 3)
                  (< i (string-length (car lines)))
                  (char=? (string-ref (car lines) i) #\#)
                  (release-like? (car lines))))
           (assertion-violation 'latest-release "not a release heading" (car lines)))
          (else (loop (cdr lines) #f found)))))

;; latest-release : (Listof String) -> (U String 'none)
;; The version of the first release heading in a changelog's LINES, or 'none
;; when none follows `## [Unreleased]`. It raises when the first `## ` heading
;; is not `## [Unreleased]`, at any later one that is not a release's, and at
;; a release whose version is not below, or whose date is after, the one
;; above it.
(define (latest-release lines)
  (let ((headings (section-headings lines)))
    (unless (and (pair? headings) (string=? (car headings) "## [Unreleased]"))
      (assertion-violation 'latest-release "the first heading is not ## [Unreleased]"
                           (if (pair? headings) (car headings) 'no-heading)))
    (for-each (lambda (heading)
                (unless (release-version heading)
                  (assertion-violation 'latest-release "not a release heading" heading)))
              (cdr headings))
    (let check ((releases (cdr headings)))
      (when (and (pair? releases) (pair? (cdr releases)))
        (let ((above (car releases)) (below (cadr releases)))
          (unless (version<? (version-numbers (release-version below))
                             (version-numbers (release-version above)))
            (assertion-violation 'latest-release
                                 "a release's version is not below the one above it"
                                 above below))
          (when (string<? (release-date above) (release-date below))
            (assertion-violation 'latest-release
                                 "a release is dated before the one below it"
                                 above below))
          (check (cdr releases)))))
    (if (null? (cdr headings))
        'none
        (release-version (cadr headings)))))

;; repository : String
;; The repository's address, which a changelog's link references name.
(define repository "https://github.com/Kiyomi-Computation-Systems/chez-sqlite3")

;; link-label : String -> (U String #f)
;; LABEL when LINE begins `[LABEL]: `, LABEL holding no `]`: a link
;; reference; #f for any other line.
(define (link-label line)
  (and (starts-with? line "[")
       (let ((parts (cut-at (substring line 1 (string-length line)) #\])))
         (and (pair? (cdr parts))
              (starts-with? (cadr parts) ": ")
              (car parts)))))

;; body-line? : String -> Boolean
;; Whether LINE says something in an entry: past its spaces and tabs it is
;; not empty, and begins with no #, and it is no link reference.
(define (body-line? line)
  (let loop ((i 0))
    (cond ((= i (string-length line)) #f)
          ((memv (string-ref line i) '(#\space #\tab)) (loop (+ i 1)))
          (else (and (not (char=? (string-ref line i) #\#))
                     (not (link-label line)))))))

;; latest-entry : (Listof String) -> (Listof String)
;; The lines of a changelog's LINES below its first release heading outside
;; a fenced block, up to the next `## ` heading outside one, or the end: the
;; latest release's entry. None when it has no release.
(define (latest-entry lines)
  (let skip ((lines lines) (fence #f))
    (cond ((null? lines) '())
          (fence (skip (cdr lines) (if (eqv? (fence-char (car lines)) fence) #f fence)))
          ((fence-char (car lines)) => (lambda (c) (skip (cdr lines) c)))
          ((release-version (car lines))
           (let take ((lines (cdr lines)) (fence #f) (found '()))
             (cond ((null? lines) (reverse found))
                   (fence (take (cdr lines) (if (eqv? (fence-char (car lines)) fence) #f fence)
                                (cons (car lines) found)))
                   ((fence-char (car lines))
                    => (lambda (c) (take (cdr lines) c (cons (car lines) found))))
                   ((starts-with? (car lines) "## ") (reverse found))
                   (else (take (cdr lines) #f (cons (car lines) found))))))
          (else (skip (cdr lines) #f)))))

;; link-problems : (Listof String) String String -> (Listof String)
;; What is wrong with the link reference LABEL among a changelog's link
;; references REFS, where WANT is the one line it must be: none, more than
;; one, or one that is not WANT.
(define (link-problems refs label want)
  (let ((given (filter (lambda (line) (equal? (link-label line) label)) refs)))
    (cond ((null? given)
           (list (string-append "there is no link reference [" label "], but it must be "
                                (shown want))))
          ((pair? (cdr given))
           (list (string-append "the link reference [" label "] is given "
                                (number->string (length given)) " times, but once it must be "
                                (shown want))))
          ((string=? (car given) want) '())
          (else
           (list (string-append "the link reference [" label "] is " (shown (car given))
                                ", but it must be " (shown want)))))))

;; changelog-problems : (Listof String) -> (Listof String)
;; What is wrong with the latest release of a changelog's LINES, as Keep a
;; Changelog writes it. With no release, each link reference is wrong, as
;; there is nothing to link. With one, X.Y.Z: an entry holding no body-line?;
;; and the link references [Unreleased] and [X.Y.Z], unless each is given
;; once, as `[Unreleased]: REPOSITORY/compare/vX.Y.Z...HEAD` and, for the
;; first release, `[X.Y.Z]: REPOSITORY/releases/tag/vX.Y.Z`, or, for a later
;; one, `[X.Y.Z]: REPOSITORY/compare/vW...vX.Y.Z`, W the release below. A
;; link reference is any line link-label takes, a fenced block's too. It
;; raises where latest-release raises.
(define (changelog-problems lines)
  (let ((latest (latest-release lines))
        (refs (filter link-label lines)))
    (if (eq? latest 'none)
        (map (lambda (line)
               (string-append "there is no release, so no link reference, but this is one: "
                              (shown line)))
             refs)
        (let ((below (map release-version (cddr (section-headings lines)))))
          (append
           (if (exists body-line? (latest-entry lines))
               '()
               (list (string-append "the entry of [" latest "] says nothing: it holds no line"
                                    " but blanks, headings and link references")))
           (link-problems refs "Unreleased"
                          (string-append "[Unreleased]: " repository "/compare/v" latest "...HEAD"))
           (link-problems refs latest
                          (string-append "[" latest "]: " repository
                                         (if (null? below)
                                             (string-append "/releases/tag/v" latest)
                                             (string-append "/compare/v" (car below) "...v"
                                                            latest)))))))))

;; file-lines : String -> (Listof String)
;; Every line of the file at PATH, read as UTF-8, without its line feed.
(define (file-lines path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                        (make-transcoder (utf-8-codec)))
    (lambda (port)
      (let loop ((found '()))
        (let ((line (get-line port)))
          (if (eof-object? line)
              (reverse found)
              (loop (cons line found))))))))

;; refusal : (-> Any) -> Any
;; What THUNK raised: its message and irritants, or 'no-message for a raise
;; that has none; or (no-raise VALUE) when it returned. A refusal row expects
;; the first, so a THUNK that returns fails it, whatever it returned.
(define (refusal thunk)
  (guard (e (#t (if (message-condition? e)
                    (list (condition-message e)
                          (if (irritants-condition? e) (condition-irritants e) '()))
                    'no-message)))
    (list 'no-raise (thunk))))

;; answer : (-> Any) -> Any
;; THUNK's value, or (raised MESSAGE IRRITANTS) or (raised no-message) when it
;; raised, so that no row expecting a value can be met by a raise.
(define (answer thunk)
  (guard (e (#t (if (message-condition? e)
                    (list 'raised (condition-message e)
                          (if (irritants-condition? e) (condition-irritants e) '()))
                    '(raised no-message))))
    (thunk)))

;; clone-url : String
;; The repository a clone line clones.
(define clone-url "https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git")

;; clone-line : String -> String
;; The one clone line VERSION calls for: the tag vVERSION's; at 0.0.0, no
;; release, the default branch's.
(define (clone-line version)
  (if (string=? version "0.0.0")
      (string-append "git clone " clone-url)
      (string-append "git clone --branch v" version " " clone-url)))

;; clone-homes : (Listof String)
;; The files that hold one clone line each, from the root. No other file
;; under docs/ holds any.
(define clone-homes '("README.org" "docs/quickstart.md"))

;; shown : String -> String
;; TEXT as write writes it, in double quotes.
(define (shown text)
  (call-with-string-output-port (lambda (port) (write text port))))

;; numbered-clone-lines : String -> (Listof (Pair Integer String))
;; Each line of the file at PATH that holds "git clone", with its number from
;; 1. It raises when the file cannot be read.
(define (numbered-clone-lines path)
  (let loop ((lines (file-lines path)) (n 1) (found '()))
    (cond ((null? lines) (reverse found))
          ((contains? (car lines) "git clone") (loop (cdr lines) (+ n 1) (cons (cons n (car lines)) found)))
          (else (loop (cdr lines) (+ n 1) found)))))

;; line-numbers : (Listof (Pair Integer String)) -> String
;; The numbers of numbered LINES, ", " between them.
(define (line-numbers lines)
  (fold-left (lambda (text line)
               (string-append text (if (string=? text "") "" ", ") (number->string (car line))))
             "" lines))

;; home-problems : String (Listof (Pair Integer String)) String String -> (Listof String)
;; line-problems : String (Listof (Pair Integer String)) String String -> (Listof String)
;; Each of the clone lines LINES of the file REL that is not WANT, the line
;; VERSION calls for, past its leading spaces.
(define (line-problems rel lines version want)
  (apply append
         (map (lambda (line)
                (let ((text (substring (cdr line) (indent (cdr line)) (string-length (cdr line)))))
                  (if (string=? text want)
                      '()
                      (list (string-append rel ":" (number->string (car line))
                                           ": past its leading spaces it is " (shown text)
                                           ", but version " version " calls for " (shown want))))))
              lines)))

;; home-problems : String (Listof (Pair Integer String)) String String -> (Listof String)
;; What is wrong with the clone lines LINES of the file REL, one of
;; clone-homes, where VERSION calls for the line WANT: how many there are,
;; unless one, then each line that is not WANT past its leading spaces.
(define (home-problems rel lines version want)
  (append
   (cond ((null? lines)
          (list (string-append rel ": it holds no git clone line, but must hold one")))
         ((pair? (cdr lines))
          (list (string-append rel ": it holds " (number->string (length lines))
                               " git clone lines, at lines " (line-numbers lines)
                               ", but must hold one")))
         (else '()))
   (line-problems rel lines version want)))

;; clone-problems : String String -> (Listof String)
;; What is wrong with the clone lines of the tree at ROOT, VERSION being
;; Akku.manifest's: each problem names its file, from ROOT, and its line. A
;; clone line is any line of README.org, or of a file under docs/, that holds
;; "git clone", and past its leading spaces each is (clone-line VERSION).
;; README.org and docs/quickstart.md hold one each; another page may hold
;; any number. Files in order, README.org first, then docs/ depth first, each
;; directory sorted, and then a quick start that is missing. It raises when
;; README.org, or a file under docs/, cannot be read.
(define (clone-problems root version)
  (let* ((want (clone-line version))
         (rels (cons "README.org" (files-under root "docs"))))
    (append
     (apply append
            (map (lambda (rel)
                   (let ((lines (numbered-clone-lines (string-append root "/" rel))))
                     (if (member rel clone-homes)
                         (home-problems rel lines version want)
                         (line-problems rel lines version want))))
                 rels))
     (if (member "docs/quickstart.md" rels)
         '()
         (list "docs/quickstart.md: there is no such file, but it must hold one git clone line")))))

;; attribute-lines : (Listof String) -> (Listof (Listof String))
;; The words of each line of a .gitattributes, its blanks and tabs the
;; separators: a pattern and its attributes. A line blank but for spaces and
;; tabs, and one whose first character past them is #, is no line, as git
;; reads them.
(define (attribute-lines lines)
  (let loop ((lines lines) (found '()))
    (if (null? lines)
        (reverse found)
        (let ((words (filter (lambda (w) (not (string=? w "")))
                             (apply append
                                    (map (lambda (piece) (cut-at piece #\tab))
                                         (cut-at (car lines) #\space))))))
          (if (or (null? words) (char=? (string-ref (car words) 0) #\#))
              (loop (cdr lines) found)
              (loop (cdr lines) (cons words found)))))))

;; files-under : String String -> (Listof String)
;; Every file under ROOT/REL, as a path from ROOT, depth first, each directory
;; sorted; none when it is not a directory.
(define (files-under root rel)
  (if (file-directory? (string-append root "/" rel))
      (apply append
             (map (lambda (name)
                    (let ((sub (string-append rel "/" name)))
                      (if (file-directory? (string-append root "/" sub))
                          (files-under root sub)
                          (list sub))))
                  (list-sort string<? (directory-list (string-append root "/" rel)))))
      '()))

(test-begin "manifest")

;; The actual expressions below run under a guard: SRFI-64 turns a raise into
;; #f, which would hide why a file failed.
(test-equal "Akku.manifest holds exactly one akku-package form"
  1
  (answer (lambda ()
             (length (filter (lambda (datum) (and (pair? datum) (eq? (car datum) 'akku-package)))
                             (read-data "Akku.manifest"))))))

(test-equal "Akku.manifest's package is chez-sqlite3"
  "chez-sqlite3"
  (answer (lambda () (car (cadr (the-form 'akku-package "Akku.manifest"))))))

(test-equal "Akku.manifest's license is BSD-3-Clause, and given once"
  '((license "BSD-3-Clause"))
  (answer (lambda () (package-clauses 'license))))

(test-equal "Akku.manifest has no depends clause"
  '()
  (answer (lambda () (package-clauses 'depends))))

(test-equal "Akku.manifest has no scripts clause"
  '()
  (answer (lambda () (package-clauses 'scripts))))

(test-equal "Akku.manifest's depends/dev is exactly chez-srfi, in the range that names the pinned version, and chez-cmark-gfm at ^2.0.0"
  '((depends/dev ("chez-srfi" "^0.0.0-akku.181.7879b52") ("chez-cmark-gfm" "^2.0.0")))
  (answer (lambda () (package-clauses 'depends/dev))))

;; Whole projects, in the order akku lock writes them, by name.
(test-equal "Akku.lock holds exactly two projects, chez-cmark-gfm then chez-srfi"
  '(((name "chez-cmark-gfm")) ((name "chez-srfi")))
  (answer (lambda () (map (lambda (project) (list (assq 'name project))) (lock-projects)))))

;; One url each, and it holds the version. The expected value is the version
;; the pin names, so a lock and a manifest that drift together still fail.
(test-equal "Akku.lock's chez-srfi url holds the version Akku.manifest asks for, and the pinned one"
  '((#t #t))
  (answer
   (lambda ()
     (map (lambda (url)
            (list (contains? url (dev-version "chez-srfi")) (contains? url "akku.181.7879b52")))
          (lock-urls "chez-srfi")))))

(test-equal "Akku.lock's chez-cmark-gfm url holds the version Akku.manifest asks for, and the pinned one"
  '((#t #t))
  (answer
   (lambda ()
     (map (lambda (url)
            (list (contains? url (string-append "_" (dev-version "chez-cmark-gfm") "_"))
                  (contains? url "chez-cmark-gfm_2.0.0_repack")))
          (lock-urls "chez-cmark-gfm")))))

;; The project whole: the archive make site-deps downloads, and the sha256 it
;; checks that archive against.
(test-equal "Akku.lock's chez-cmark-gfm project is the archive make site-deps fetches, and its sha256"
  '(((name "chez-cmark-gfm")
     (location
      (url "https://archive.akkuscm.org/archive/pkg/c/chez-cmark-gfm_2.0.0_repack.tar.xz"))
     (content
      (sha256 "bb647e07c03f103600ceb29d5545787bf0ba54563b1bbd98f3be7ac778305159"))))
  (answer
   (lambda ()
     (filter (lambda (project) (equal? (assq 'name project) '(name "chez-cmark-gfm")))
             (lock-projects)))))

(test-equal "Akku.lock's every project carries a sha256 of 64 hex digits"
  '(#t #t)
  (answer
   (lambda ()
     (map (lambda (project)
            (let ((sha (assq 'sha256 (cdr (assq 'content project)))))
              (and sha (= (length sha) 2) (hex-sha256? (cadr sha)))))
          (lock-projects)))))

(test-equal "a changelog's latest release is its first release heading"
  "0.2.0"
  (latest-release '("# Changelog" "" "## [Unreleased]" "" "### Added" ""
                    "## [0.2.0] - 2026-12-01" "### Added" "## [0.1.0] - 2026-11-10")))

(test-equal "a changelog whose only section is [Unreleased] names no release"
  'none
  (latest-release '("# Changelog" "## [Unreleased]" "### Added" "- a line")))

(test-equal "a changelog whose first section is a release, not [Unreleased], is refused"
  '("the first heading is not ## [Unreleased]" ("## [0.1.0] - 2026-11-10"))
  (refusal (lambda () (latest-release '("# Changelog" "## [0.1.0] - 2026-11-10")))))

(test-equal "a changelog with no section is refused"
  '("the first heading is not ## [Unreleased]" (no-heading))
  (refusal (lambda () (latest-release '("# Changelog" "")))))

;; Each line differs from a release heading in one place: the opening, each
;; number, a leading zero, a digit that is not ASCII in each number, the
;; separators, the end, the level and the indent. Before an older release,
;; none may be skipped for it.
(for-each
  (lambda (heading)
    (test-equal (string-append "a changelog refuses the heading " heading)
      (list "not a release heading" (list heading))
      (refusal (lambda ()
                 (latest-release (list "## [Unreleased]" heading "## [0.1.0] - 2026-11-10"))))))
  '("## 0.2.0 - 2026-12-01" "## [v0.2.0] - 2026-12-01" "## [0.2.0]"
    "## [0.2] - 2026-12-01" "## [0.2.0.1] - 2026-12-01" "## [.2.0] - 2026-12-01"
    "## [0.2.] - 2026-12-01" "## [0.2.x] - 2026-12-01" "## [00.2.0] - 2026-12-01"
    "## [0.02.0] - 2026-12-01" "## [0.2.00] - 2026-12-01" "## [0.2.0]- 2026-12-01"
    "## [0.2.0] -2026-12-01" "## [0.2.0] \x2013; 2026-12-01" "## [0.2.0] - 2026-12-1"
    "## [0.2.0] - 2026/12/01" "## [0.2.0] - 2026-12-01 " "## [0.2.0] - 2026-12-01x"
    "## [0.2.0] - \x0663;026-12-01" "## [0.2.0]] - 2026-12-01" "## [Unreleased]"
    "## [\x0663;.2.0] - 2026-12-01" "## [0.\x0663;.0] - 2026-12-01" "## [0.2.\x0663;] - 2026-12-01"
    "## [0.2.0] - 2026-12-01 [YANKED]" "### [0.2.0] - 2026-12-01" "# [0.2.0] - 2026-12-01"
    "##[0.2.0] - 2026-12-01" " ## [0.2.0] - 2026-12-01" "   ## [0.2.0] - 2026-12-01"))

;; A date with a wrong character at each of its ten places, a digit where
;; each hyphen goes, and a month or day out of range.
(for-each
  (lambda (date)
    (let ((heading (string-append "## [0.2.0] - " date)))
      (test-equal (string-append "a changelog refuses the date " date)
        (list "not a release heading" (list heading))
        (refusal (lambda ()
                   (latest-release (list "## [Unreleased]" heading "## [0.1.0] - 2026-11-10")))))))
  (append (map (lambda (i)
                 (string-append (substring "2026-12-01" 0 i) "x"
                                (substring "2026-12-01" (+ i 1) 10)))
               '(0 1 2 3 4 5 6 7 8 9))
          '("2026012-01" "2026-12001" "2026-00-01" "2026-13-01" "2026-12-00" "2026-12-32")))

(test-equal "a changelog takes a release dated at the ends of the month and day ranges"
  '("0.2.0" "0.2.0")
  (map (lambda (heading) (latest-release (list "## [Unreleased]" heading "## [0.1.0] - 2026-01-01")))
       '("## [0.2.0] - 2026-01-31" "## [0.2.0] - 2026-12-01")))

(test-equal "a line four spaces in is code, not a heading"
  "0.1.0"
  (latest-release '("## [Unreleased]" "    ## [0.2.0] - 2026-12-01" "## [0.1.0] - 2026-11-10")))

(test-equal "a fenced block's lines are not headings, and a fence closes with its own character"
  '("0.1.0" "0.1.0" "0.1.0" "0.1.0")
  (map latest-release
       '(("## [Unreleased]" "```" "## [9.9.9] - 2026-12-01" "```" "## [0.1.0] - 2026-11-10")
         ("## [Unreleased]" "~~~" "## [9.9.9] - 2026-12-01" "~~~" "## [0.1.0] - 2026-11-10")
         ("## [Unreleased]" "```" "~~~" "## [9.9.9] - 2026-12-01" "```" "## [0.1.0] - 2026-11-10")
         ("## [Unreleased]" "```text" "### [9.9.9] - x" "```" "## [0.1.0] - 2026-11-10"))))

(test-equal "a heading after a fenced block closes counts again"
  "0.2.0"
  (latest-release '("## [Unreleased]" "```" "x" "```" "## [0.2.0] - 2026-12-01"
                    "## [0.1.0] - 2026-11-10")))

(test-equal "a changelog refuses a release appended below an older one"
  '("a release's version is not below the one above it"
    ("## [0.1.0] - 2026-11-10" "## [0.2.0] - 2026-12-01"))
  (refusal (lambda ()
             (latest-release '("## [Unreleased]" "## [0.1.0] - 2026-11-10"
                               "## [0.2.0] - 2026-12-01")))))

(test-equal "a changelog refuses a version given twice"
  '("a release's version is not below the one above it"
    ("## [0.1.0] - 2026-11-10" "## [0.1.0] - 2026-11-10"))
  (refusal (lambda ()
             (latest-release '("## [Unreleased]" "## [0.1.0] - 2026-11-10"
                               "## [0.1.0] - 2026-11-10")))))

(test-equal "a changelog holds the order past its first two releases"
  '("a release's version is not below the one above it"
    ("## [0.1.0] - 2026-12-01" "## [0.2.0] - 2026-12-02"))
  (refusal (lambda ()
             (latest-release '("## [Unreleased]" "## [0.3.0] - 2026-12-03"
                               "## [0.1.0] - 2026-12-01" "## [0.2.0] - 2026-12-02")))))

(test-equal "a changelog orders versions by number, not by text"
  '("0.10.0" "1.0.0" "0.1.10")
  (map latest-release
       '(("## [Unreleased]" "## [0.10.0] - 2026-12-02" "## [0.9.0] - 2026-12-01")
         ("## [Unreleased]" "## [1.0.0] - 2026-12-02" "## [0.99.99] - 2026-12-01")
         ("## [Unreleased]" "## [0.1.10] - 2026-12-02" "## [0.1.9] - 2026-12-01"))))

(test-equal "a changelog refuses a release dated before the one below it"
  '("a release is dated before the one below it"
    ("## [0.2.0] - 2026-11-01" "## [0.1.0] - 2026-11-10"))
  (refusal (lambda ()
             (latest-release '("## [Unreleased]" "## [0.2.0] - 2026-11-01"
                               "## [0.1.0] - 2026-11-10")))))

(test-equal "a changelog takes two releases of one day"
  "0.2.0"
  (latest-release '("## [Unreleased]" "## [0.2.0] - 2026-11-10" "## [0.1.0] - 2026-11-10")))

(test-equal "a changelog refuses a malformed heading as its oldest release, and as its only one"
  '(("not a release heading" ("## [0.1.0]")) ("not a release heading" ("## [0.1.0]")))
  (map (lambda (lines) (refusal (lambda () (latest-release lines))))
       '(("## [Unreleased]" "## [0.2.0] - 2026-12-01" "## [0.1.0]")
         ("## [Unreleased]" "## [0.1.0]"))))

(test-equal "a changelog takes a release heading's every number, a lone 0 among them"
  '("10.20.30" "0.0.0" "1.0.9")
  (map (lambda (heading) (latest-release (list "## [Unreleased]" heading)))
       '("## [10.20.30] - 2026-12-01" "## [0.0.0] - 2026-12-01" "## [1.0.9] - 1999-01-31")))

(test-equal "CHANGELOG.md starts with its title"
  "# Changelog"
  (answer (lambda () (car (file-lines "CHANGELOG.md")))))

(test-equal "CHANGELOG.md has [Unreleased] first, and its releases well formed, newest first"
  'well-formed
  (answer (lambda () (latest-release (file-lines "CHANGELOG.md")) 'well-formed)))

;; The expected value is computed under a guard: SRFI-64 does not catch a
;; raise there. With no release yet, the version is 0.0.0.
(test-equal "Akku.manifest's version is CHANGELOG.md's latest release, or 0.0.0 with none"
  (answer (lambda ()
             (let ((latest (latest-release (file-lines "CHANGELOG.md"))))
               (if (eq? latest 'none) "0.0.0" latest))))
  (answer package-version))

;; --- the latest release's entry and link references -----------------------------
;; changelog-problems and its parts are held on the suite's own changelogs
;; first, so that a check which never fires cannot pass CHANGELOG.md. The
;; expected link references are written out here, as a reader follows them,
;; not built from repository.

(define unreleased-0.1.0
  "[Unreleased]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/compare/v0.1.0...HEAD")
(define unreleased-0.2.0
  "[Unreleased]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/compare/v0.2.0...HEAD")
(define tag-0.1.0
  "[0.1.0]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/releases/tag/v0.1.0")
(define compare-0.2.0
  "[0.2.0]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/compare/v0.1.0...v0.2.0")

;; must-be : String String -> String
;; The complaint that the link reference LABEL is the line GIVEN, not WANT.
(define (must-be label given want)
  (string-append "the link reference [" label "] is \"" given "\", but it must be \"" want "\""))

;; missing : String String -> String
;; The complaint that there is no link reference LABEL, which must be WANT.
(define (missing label want)
  (string-append "there is no link reference [" label "], but it must be \"" want "\""))

(test-equal "link-label: [LABEL]: at a line's start is a link reference; indented, inside a bullet, without its colon or the space after it, or with a ] in its label, it is none"
  '("Unreleased" "0.1.0" #f #f #f #f #f)
  (map link-label '("[Unreleased]: https://x" "[0.1.0]: https://y" " [0.1.0]: https://y"
                    "- [0.1.0]: https://y" "[0.1.0] https://y" "[0.1.0]:https://y"
                    "[0.1]0]: https://y")))

(test-equal "body-line?: an empty line, one of spaces and tabs, a heading, an indented heading and a link reference say nothing; text, a bullet and a fence do"
  '(#f #f #f #f #f #t #t #t)
  (map body-line? '("" " \t " "### Added" "  ## x" "[0.1.0]: https://x" "Some text."
                    "- a bullet" "```")))

(test-equal "latest-entry: the lines below the first release heading, up to the next ## heading, [Unreleased]'s left out; none with no release"
  '(("" "The second release." "" "### Added" "- a line" "") ())
  (list (latest-entry '("# Changelog" "## [Unreleased]" "- unreleased" "## [0.2.0] - 2026-12-01" ""
                        "The second release." "" "### Added" "- a line" "" "## [0.1.0] - 2026-11-10"
                        "- older"))
        (latest-entry '("# Changelog" "## [Unreleased]" "- unreleased"))))

(test-equal "latest-entry: a release heading in a fenced block is no release, a ## line in one ends no entry, and an entry with nothing below it runs to the end"
  '("```" "## [0.0.1] - 2026-01-01" "```" "- a line")
  (latest-entry '("## [Unreleased]" "~~~" "## [9.9.9] - 2026-12-01" "~~~" "## [0.1.0] - 2026-11-10"
                  "```" "## [0.0.1] - 2026-01-01" "```" "- a line")))

(test-equal "changelog-problems: no release and no link reference, the shape before the first release: nothing"
  '()
  (answer (lambda () (changelog-problems '("# Changelog" "" "Some text." "" "## [Unreleased]")))))

(test-equal "changelog-problems: with no release, each link reference is named, one in a fenced block too"
  (list (string-append "there is no release, so no link reference, but this is one: \"" unreleased-0.1.0
                       "\"")
        (string-append "there is no release, so no link reference, but this is one: \"" tag-0.1.0 "\""))
  (answer (lambda () (changelog-problems (list "## [Unreleased]" "- a line" "" unreleased-0.1.0 "```"
                                               tag-0.1.0 "```")))))

(test-equal "changelog-problems: a first release with a body, then both link references closing the file: nothing"
  '()
  (answer (lambda () (changelog-problems (list "# Changelog" "" "## [Unreleased]" ""
                                               "## [0.1.0] - 2026-11-20" "" "The first release." ""
                                               unreleased-0.1.0 tag-0.1.0)))))

(test-equal "changelog-problems: a release heading alone, with no body and no link reference: all three named"
  (list "the entry of [0.1.0] says nothing: it holds no line but blanks, headings and link references"
        (missing "Unreleased" unreleased-0.1.0)
        (missing "0.1.0" tag-0.1.0))
  (answer (lambda () (changelog-problems '("# Changelog" "" "## [Unreleased]" ""
                                           "## [0.1.0] - 2099-12-31")))))

(test-equal "changelog-problems: an entry of blanks, a heading and a link reference says nothing, and the body of the release below is not its own"
  (list "the entry of [0.2.0] says nothing: it holds no line but blanks, headings and link references")
  (answer (lambda () (changelog-problems (list "## [Unreleased]" "## [0.2.0] - 2026-12-01" "" "### Added"
                                               " \t" "[x]: https://example.org" "## [0.1.0] - 2026-11-10"
                                               "- older" "" unreleased-0.2.0 compare-0.2.0 tag-0.1.0)))))

(test-equal "changelog-problems: [Unreleased] compared from an older tag, and the first release linked as a compare: both named"
  (list (must-be "Unreleased"
                 "[Unreleased]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/compare/v0.0.9...HEAD"
                 unreleased-0.1.0)
        (must-be "0.1.0"
                 "[0.1.0]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/compare/v0.0.0...v0.1.0"
                 tag-0.1.0))
  (answer (lambda ()
            (changelog-problems
             '("## [Unreleased]" "## [0.1.0] - 2026-11-20" "- a line"
               "[Unreleased]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/compare/v0.0.9...HEAD"
               "[0.1.0]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/compare/v0.0.0...v0.1.0")))))

(test-equal "changelog-problems: another repository's [Unreleased], and a release linked to main: both named"
  (list (must-be "Unreleased"
                 "[Unreleased]: https://github.com/Kiyomi-Computation-Systems/chez-curl/compare/v0.1.0...HEAD"
                 unreleased-0.1.0)
        (must-be "0.1.0" "[0.1.0]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/tree/main"
                 tag-0.1.0))
  (answer (lambda ()
            (changelog-problems
             '("## [Unreleased]" "## [0.1.0] - 2026-11-20" "- a line"
               "[Unreleased]: https://github.com/Kiyomi-Computation-Systems/chez-curl/compare/v0.1.0...HEAD"
               "[0.1.0]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/tree/main")))))

(test-equal "changelog-problems: a second release, its link a compare from the release below and [Unreleased] from it: nothing; its link the first release's form, and [Unreleased] left at the older tag: both named"
  (list '()
        (list (must-be "Unreleased" unreleased-0.1.0 unreleased-0.2.0)
              (must-be "0.2.0"
                       "[0.2.0]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/releases/tag/v0.2.0"
                       compare-0.2.0)))
  (list (answer (lambda () (changelog-problems (list "## [Unreleased]" "## [0.2.0] - 2026-12-01" "- new"
                                                     "## [0.1.0] - 2026-11-20" "- old" ""
                                                     unreleased-0.2.0 compare-0.2.0 tag-0.1.0))))
        (answer (lambda ()
                  (changelog-problems
                   (list "## [Unreleased]" "## [0.2.0] - 2026-12-01" "- new" "## [0.1.0] - 2026-11-20"
                         "- old" "" unreleased-0.1.0
                         "[0.2.0]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/releases/tag/v0.2.0"
                         tag-0.1.0))))))

(test-equal "changelog-problems: a link reference given twice is named, the same line twice too"
  (list (string-append "the link reference [Unreleased] is given 2 times, but once it must be \""
                       unreleased-0.1.0 "\"")
        (string-append "the link reference [0.1.0] is given 2 times, but once it must be \"" tag-0.1.0
                       "\""))
  (answer (lambda ()
            (changelog-problems
             (list "## [Unreleased]" "## [0.1.0] - 2026-11-20" "- a line" unreleased-0.1.0
                   "[Unreleased]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/compare/v0.1.0...main"
                   tag-0.1.0 tag-0.1.0)))))

(test-equal "CHANGELOG.md's latest release has a body and both link references, [Unreleased] and its own; or, with no release, no link reference"
  '()
  (answer (lambda () (changelog-problems (file-lines "CHANGELOG.md")))))

;; --- git clone lines ---------------------------------------------------------------
;; clone-problems is held on the fixture trees under tests/fixtures/clone-lines
;; first, at each version a row names, so that a check which never fires
;; cannot pass the real tree. The expected messages are written here, from
;; the URL the fixtures write, not from clone-url.

(define clone-fixtures "tests/fixtures/clone-lines")

;; fixture-clone : String -> String
;; A clone line of the fixtures: of the tag TAG, or with no --branch for "".
(define (fixture-clone tag)
  (string-append "git clone " (if (string=? tag "") "" (string-append "--branch " tag " "))
                 "https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git"))

;; not-the-line : String Integer String String String -> String
;; The complaint about line N of PATH, which is TEXT past its leading spaces,
;; where VERSION calls for the clone line of TAG.
(define (not-the-line path n text version tag)
  (string-append path ":" (number->string n) ": past its leading spaces it is \"" text
                 "\", but version " version " calls for \"" (fixture-clone tag) "\""))

;; clones-at : String String -> Any
;; clone-problems on the fixture tree TREE at VERSION, or what it raised.
(define (clones-at tree version)
  (answer (lambda () (clone-problems (string-append clone-fixtures "/" tree) version))))

(test-equal "clone-problems: a tree with no release, its README's line in a block, the quick start's at the line's start, a page that mentions git and a clone: nothing at 0.0.0"
  '()
  (clones-at "unreleased" "0.0.0"))

(test-equal "clone-problems: the same tree at 0.1.0, where each line must name the tag: both lines named"
  (list (not-the-line "README.org" 6 (fixture-clone "") "0.1.0" "v0.1.0")
        (not-the-line "docs/quickstart.md" 4 (fixture-clone "") "0.1.0" "v0.1.0"))
  (clones-at "unreleased" "0.1.0"))

(test-equal "clone-problems: a tree whose lines name v0.1.0, the quick start's in an indented block: nothing at 0.1.0"
  '()
  (clones-at "released" "0.1.0"))

(test-equal "clone-problems: the same tree at 0.0.0, where no line may name a branch: both lines named"
  (list (not-the-line "README.org" 6 (fixture-clone "v0.1.0") "0.0.0" "")
        (not-the-line "docs/quickstart.md" 5 (fixture-clone "v0.1.0") "0.0.0" ""))
  (clones-at "released" "0.0.0"))

(test-equal "clone-problems: the same tree at 0.2.0, whose tag the lines do not name: both lines named"
  (list (not-the-line "README.org" 6 (fixture-clone "v0.1.0") "0.2.0" "v0.2.0")
        (not-the-line "docs/quickstart.md" 5 (fixture-clone "v0.1.0") "0.2.0" "v0.2.0"))
  (clones-at "released" "0.2.0"))

(test-equal "clone-problems: a quick start whose line names another version than the README's: it alone is named"
  (list (not-the-line "docs/quickstart.md" 4 (fixture-clone "v0.2.0") "0.1.0" "v0.1.0"))
  (clones-at "other-version" "0.1.0"))

(test-equal "clone-problems: a line cloning the repository without .git, and one cloning another host's: both named"
  (list (not-the-line "README.org" 6
                      "git clone --branch v0.1.0 https://github.com/Kiyomi-Computation-Systems/chez-sqlite3"
                      "0.1.0" "v0.1.0")
        (not-the-line "docs/quickstart.md" 4
                      "git clone --branch v0.1.0 https://gitlab.com/Kiyomi-Computation-Systems/chez-sqlite3.git"
                      "0.1.0" "v0.1.0"))
  (clones-at "other-url" "0.1.0"))

(test-equal "clone-problems: a second line in README.org and in the quick start, each named; in another page, the right line passes, and a wrong one, git clone at a line's start, middle and end, is named"
  (list "README.org: it holds 2 git clone lines, at lines 3, 5, but must hold one"
        (not-the-line "docs/a/b.md" 2
                      "git clone --branch v0.1.0 https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git"
                      "0.0.0" "")
        (not-the-line "docs/finding.md" 1 "git clone first, at the start of a line" "0.0.0" "")
        (not-the-line "docs/finding.md" 2 "in the middle, git clone, of a line" "0.0.0" "")
        (not-the-line "docs/finding.md" 3 "at the end of a line, git clone" "0.0.0" "")
        "docs/quickstart.md: it holds 2 git clone lines, at lines 3, 4, but must hold one")
  (clones-at "extra-lines" "0.0.0"))

(test-equal "clone-problems: a README.org and a quick start with no clone line: both named"
  (list "README.org: it holds no git clone line, but must hold one"
        "docs/quickstart.md: it holds no git clone line, but must hold one")
  (clones-at "missing-lines" "0.0.0"))

(test-equal "clone-problems: a docs/ with no quick start, and a tree with no docs/: the quick start named, missing"
  '(("docs/quickstart.md: there is no such file, but it must hold one git clone line")
    ("docs/quickstart.md: there is no such file, but it must hold one git clone line"))
  (list (clones-at "no-quickstart" "0.0.0") (clones-at "no-docs" "0.0.0")))

(test-equal "clone-problems: a line with a space at its end, and one indented with a tab, which is no leading space: both named"
  (list (not-the-line "README.org" 3 (string-append (fixture-clone "") " ") "0.0.0" "")
        (string-append "docs/quickstart.md:3: past its leading spaces it is \"\\t" (fixture-clone "")
                       "\", but version 0.0.0 calls for \"" (fixture-clone "") "\""))
  (clones-at "spacing" "0.0.0"))

(test-equal "clone-problems: with no README.org it raises, and does not pass for want of a file"
  (list "failed for ~a: ~(~a~)"
        (list (string-append clone-fixtures "/no-readme/README.org") "No such file or directory"))
  (refusal (lambda () (clone-problems (string-append clone-fixtures "/no-readme") "0.0.0"))))

;; A fixture tree no row reads guards nothing.
(test-equal "every fixture tree under tests/fixtures/clone-lines is one the rows above read"
  '("extra-lines" "missing-lines" "no-docs" "no-quickstart" "no-readme" "other-url" "other-version"
    "released" "spacing" "unreleased")
  (answer (lambda () (list-sort string<? (directory-list clone-fixtures)))))

(test-equal "README.org and docs/ hold the clone lines Akku.manifest's version calls for, one in README.org, one in the quick start"
  '()
  (answer (lambda () (clone-problems "." (package-version)))))

;; --- .gitattributes ----------------------------------------------------------
;; attribute-lines is held on the suite's own text first, so that a reader
;; which drops every line cannot pass the real file by finding nothing.

(test-equal "attribute-lines: a comment, a blank line and an indented comment are no line; blanks and tabs split words"
  '(("/.plans" "export-ignore") ("/AGENTS.md" "export-ignore" "-diff"))
  (attribute-lines '("# a comment" "" "   " "  # an indented comment" "/.plans     export-ignore"
                     "\t/AGENTS.md\texport-ignore  -diff ")))

(test-equal "attribute-lines: a pattern alone is a line, and so is a # past a pattern"
  '(("/x") ("/y" "#z"))
  (attribute-lines '("/x" "/y #z")))

(test-equal ".gitattributes marks /.plans and /AGENTS.md export-ignore, in that order, and nothing else"
  '(("/.plans" "export-ignore") ("/AGENTS.md" "export-ignore"))
  (answer (lambda () (attribute-lines (file-lines ".gitattributes")))))

(test-end "manifest")

(exit (suite-exit-status runner))
