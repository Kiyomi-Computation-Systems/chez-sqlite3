#!r6rs
;;; The suite for Akku.manifest, Akku.lock and CHANGELOG.md, which no tool
;;; checks for us. It reads them as data and compares whole values:
;;;
;;;   - the package is chez-sqlite3, one akku-package form, licensed
;;;     BSD-3-Clause;
;;;   - it has no depends clause: the libraries bind libsqlite3 directly and
;;;     need no Scheme library at runtime (ADR-0001), and chez-srfi is the
;;;     suites' own, not a consumer's (ADR-0007);
;;;   - it has no scripts clause: Akku's script mechanism prompts on every
;;;     install, and nothing here builds (see Akku.manifest);
;;;   - its depends/dev is exactly chez-srfi, in the range that names the
;;;     pinned version;
;;;   - Akku.lock holds one project, chez-srfi, whose url holds that version
;;;     and which carries a sha256;
;;;   - the package's version is CHANGELOG.md's latest release, or 0.0.0
;;;     while there is none, so a release that bumps one alone fails.
;;;
;;; There is no check of git clone lines in README.org or docs/ yet: there
;;; are no install instructions. They come with the first release. Until a
;;; check exists, a tripwire fails this suite on any line of README.org, or of
;;; any file under docs/, that holds "git clone": the line would go unchecked.
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
;;;
;;; make test runs every suite from the repository root, where all three files
;;; are.
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

;; manifest-version : -> String
;; The version Akku.manifest asks chez-srfi for: the range in its depends/dev,
;; without the ^.
(define (manifest-version)
  (let ((range (cadr (cadr (car (package-clauses 'depends/dev))))))
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

;; clone-lines : String -> (Listof String)
;; The lines of README.org, and of each file under docs/, that hold "git
;; clone", in the directory ROOT: "PATH:N: LINE", with PATH from ROOT, N the
;; line's number from 1, and LINE whole. README.org must be there: it raises
;; when it cannot be read. A docs/ that is absent holds nothing. Files in order,
;; README.org first, then docs/ depth first, each directory sorted.
(define (clone-lines root)
  (apply append
         (map (lambda (rel)
                (let loop ((lines (file-lines (string-append root "/" rel))) (n 1) (found '()))
                  (cond ((null? lines) (reverse found))
                        ((contains? (car lines) "git clone")
                         (loop (cdr lines) (+ n 1)
                               (cons (string-append rel ":" (number->string n) ": " (car lines))
                                     found)))
                        (else (loop (cdr lines) (+ n 1) found)))))
              (cons "README.org" (files-under root "docs")))))

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

(test-equal "Akku.manifest's depends/dev is exactly chez-srfi, in the range that names the pinned version"
  '((depends/dev ("chez-srfi" "^0.0.0-akku.181.7879b52")))
  (answer (lambda () (package-clauses 'depends/dev))))

(test-equal "Akku.lock holds exactly one project, chez-srfi"
  '(((name "chez-srfi")))
  (answer (lambda () (map (lambda (project) (list (assq 'name project))) (lock-projects)))))

;; One url, and it holds the version. The expected value is the version the
;; pin names, so a lock and a manifest that drift together still fail.
(test-equal "Akku.lock's chez-srfi url holds the version Akku.manifest asks for, and the pinned one"
  '((#t #t))
  (answer
   (lambda ()
     (map (lambda (url)
            (list (contains? url (manifest-version)) (contains? url "akku.181.7879b52")))
          (lock-urls "chez-srfi")))))

(test-equal "Akku.lock's chez-srfi carries a sha256 of 64 hex digits"
  '(#t)
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

;; --- git clone lines: a tripwire until a check of them exists ---------------------
;; clone-lines is held on fixture trees first, so that a tripwire which never
;; fires cannot pass the real one.

(test-equal "clone-lines: a git clone line in README.org is named, with its file, number and whole text"
  '("README.org:3:   $ git clone https://example.invalid/x.git")
  (answer (lambda () (clone-lines "tests/fixtures/clone-lines/readme"))))

(test-equal "clone-lines: a git clone line in a file deep under docs/ is named the same way"
  '("docs/guide/install.md:5:     git clone https://example.invalid/x.git")
  (answer (lambda () (clone-lines "tests/fixtures/clone-lines/docs"))))

(test-equal "clone-lines: lines that mention git, a clone, or neither, are not clone lines"
  '()
  (answer (lambda () (clone-lines "tests/fixtures/clone-lines/clean"))))

(test-equal "clone-lines: with no README.org it raises, and does not pass for want of a file"
  '("failed for ~a: ~(~a~)"
    ("tests/fixtures/clone-lines/none/README.org" "No such file or directory"))
  (refusal (lambda () (clone-lines "tests/fixtures/clone-lines/none"))))

(test-equal "README.org and docs/ hold no git clone line: no clone-line check exists yet, so none may be written"
  '()
  (answer (lambda () (clone-lines "."))))

(test-end "manifest")

(exit (suite-exit-status runner))
