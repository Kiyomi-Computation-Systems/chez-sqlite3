#!r6rs
;;; The suite for (floors) and tests/check-floors.sps, the program behind
;;; `make check-floors`. packaging/floors.sexp is the one file that writes the
;;; Chez and SQLite floors (ADR-0008), and check-floors holds README.org to it.
;;; Without this suite, deleting a rule would leave `make test` green: the real
;;; README and floors file break none of them.
;;;
;;; Three layers, each asserting whole values written by hand here, never read
;;; back from the code under test: a substring would pass whenever another
;;; rule produced the same words.
;;;
;;;   - the pure procedures, on texts held in this suite: every rule of the
;;;     floors file and every rule of the README comparison, one fault in an
;;;     otherwise legal text;
;;;   - the program, on the fixture directories under tests/fixtures/floors/,
;;;     and on paths that do not exist: its exit status, whole stdout and
;;;     whole stderr;
;;;   - the answers (floors) gives a suite: a floor by name, as text and as
;;;     numbers, and the checked-in file.
;;;
;;; The CI rules (the workflows) arrive with CI, in slice 4. Until then a
;;; .github/workflows beside the README is a failure, a tripwire with a pure
;;; row (workflows-problems) and a fixture row.
;;;
;;; The program runs under the CHEZ the container exports: without it nothing
;;; below can run, which fails here, by name, and never skips. Each computation
;;; that can raise runs under a guard that names what was raised, since SRFI-64
;;; turns a raise in the actual expression into #f and does not catch one in
;;; the expected expression. No expected value is #f.
(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
        (floors)
        (only (chezscheme) getenv system))

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

(define chez (getenv "CHEZ"))

(define program "tests/check-floors.sps")

(define fixtures "tests/fixtures/floors")

;; outcome : (-> Any) -> (U (List 'returned Any) (List 'raised String))
;; What THUNK did: returned a value, or raised, and what.
(define (outcome thunk)
  (guard (e (#t (list 'raised (describe e))))
    (list 'returned (thunk))))

;; --- words the messages are made of, written by hand --------------------------------

(define fp "f.sexp")
(define rp "R.org")

;; q : String -> String
;; S in double quotes, as write shows a string with no quote, backslash or
;; control character in it.
(define (q s) (string-append "\"" s "\""))

(define three "three dot-separated naturals, major.minor.patch")

(define (f: . words) (apply string-append fp ": " words))

(define (missing-key key) (f: "the key " key " is missing"))

(define (extra-key key)
  (f: "the key " key " is extra: the keys are chez, sqlite"))

(define (repeated-key key times)
  (f: "the key " key " appears " times " times"))

(define (misordered found)
  (f: "the keys are in the order " found ", but must be chez, sqlite"))

;; bad-version : String String -> String
;; SHOWN is the version as written, quotes included when it is a string.
(define (bad-version key shown)
  (f: key ": the version " shown " is not " three))

(define (not-an-entry shown) (f: shown " is not an entry (key \"version\")"))

(define (r: . words) (apply string-append rp ": " words))

(define section "** Requirements")

(define no-section (r: "it has no " (q section) " section"))

(define (many-sections n)
  (r: "it has " n " " (q section) " sections, but must have one"))

(define (altered-line i found wanted)
  (r: "list line " i " under " (q section) " is " (q found) ", but " fp " gives " (q wanted)))

(define (extra-line line)
  (r: (q section) " has an extra list line, " (q line) ", which " fp " does not give"))

(define (lacks-line line)
  (r: (q section) " lacks the list line " (q line) ", which " fp " gives"))

;; --- the floors file: texts ----------------------------------------------------------

;; floors-of : String String -> String
;; A floors file holding the two datum texts as the versions.
(define (floors-of chez sqlite)
  (string-append "((chez " chez ")\n (sqlite " sqlite "))\n"))

(define good-chez "\"10.9.1\"")
(define good-sqlite "\"8.1.2\"")

(define good (floors-of good-chez good-sqlite))

(define (floors-row name text problems)
  (test-equal (string-append "floors file: " name)
    (list 'returned problems)
    (outcome (lambda () (floors-problems fp text)))))

(test-begin "check-floors")

(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (and chez (not (string=? chez ""))) 'set 'unset))

(unless (and chez (not (string=? chez "")))
  (exit 1))

;; --- the floors file: what is legal --------------------------------------------------

(floors-row "the base text is legal" good '())

(floors-row "a comment above, between, after and inside the datum is no datum"
  (string-append ";; the floors\n"
                 "((chez \"10.9.1\") ; the Chez floor\n"
                 " #;(python \"3\") #| block |# (sqlite \"8.1.2\"))\n"
                 ";; end\n")
  '())

(floors-row "zero is a natural, and so is a number of several digits"
  (floors-of "\"0.0.0\"" "\"10.0.10\"")
  '())

;; --- the floors file: what is one datum ----------------------------------------------

(floors-row "an empty file holds no datum" ""
  (list (f: "it holds no datum, but must hold exactly one")))

(floors-row "a file of comments holds no datum" "; nothing here\n#| nor here |#\n"
  (list (f: "it holds no datum, but must hold exactly one")))

(floors-row "a second datum"
  (string-append good "(more)\n")
  (list (f: "it holds 2 data, but must hold exactly one")))

(floors-row "three data"
  (string-append good good good)
  (list (f: "it holds 3 data, but must hold exactly one")))

(floors-row "a datum cut short cannot be read"
  "((chez \"10.9.1\")"
  (list (f: "it cannot be read as data: Exception in read: unexpected end-of-file reading list at char 0 of #<input port string>")))

(floors-row "an #!eof literal would end the reading early"
  (string-append "#!eof " good)
  (list (f: "it cannot be read as data: Exception in read: an #!eof literal ends the reading before the end of the file")))

;; --- the floors file: what is an entry -----------------------------------------------

(floors-row "the datum is a number" "42"
  (list (f: "the datum is 42, not a list of (key \"version\") entries")))

(floors-row "the datum is a string" "\"10.9.1\""
  (list (f: "the datum is \"10.9.1\", not a list of (key \"version\") entries")))

(floors-row "the datum is a dotted pair" "(chez . \"10.9.1\")"
  (list (f: "the datum is (chez . \"10.9.1\"), not a list of (key \"version\") entries")))

(floors-row "the datum is a cyclic list, which is named and never walked" "#0=(a . #0#)"
  (list (f: "the datum is #0=(a . #0#), not a list of (key \"version\") entries")))

(floors-row "an empty list names both keys missing" "()"
  (list (missing-key "chez") (missing-key "sqlite")))

(floors-row "an entry with a key and no version"
  "((chez \"10.9.1\") (sqlite))"
  (list (not-an-entry "(sqlite)") (missing-key "sqlite")))

(floors-row "an entry with a key and two versions"
  "((chez \"10.9.1\" \"10.9.2\") (sqlite \"8.1.2\"))"
  (list (not-an-entry "(chez \"10.9.1\" \"10.9.2\")") (missing-key "chez")))

(floors-row "an entry whose key is a string"
  "((\"chez\" \"10.9.1\") (sqlite \"8.1.2\"))"
  (list (not-an-entry "(\"chez\" \"10.9.1\")") (missing-key "chez")))

(floors-row "an entry that is no list"
  "(chez (sqlite \"8.1.2\"))"
  (list (not-an-entry "chez") (missing-key "chez")))

(floors-row "the keys and versions in one flat list"
  "(chez \"10.9.1\")"
  (list (not-an-entry "chez") (not-an-entry "\"10.9.1\"")
        (missing-key "chez") (missing-key "sqlite")))

;; --- the floors file: the keys -------------------------------------------------------

(floors-row "no chez key"
  "((sqlite \"8.1.2\"))"
  (list (missing-key "chez")))

(floors-row "no sqlite key"
  "((chez \"10.9.1\"))"
  (list (missing-key "sqlite")))

(floors-row "an extra key"
  "((chez \"10.9.1\") (sqlite \"8.1.2\") (python \"3.12.0\"))"
  (list (extra-key "python")))

(floors-row "an extra key first"
  "((python \"3.12.0\") (chez \"10.9.1\") (sqlite \"8.1.2\"))"
  (list (extra-key "python")))

(floors-row "an extra key twice is named once"
  "((chez \"10.9.1\") (sqlite \"8.1.2\") (python \"3.12.0\") (python \"3.13.0\"))"
  (list (extra-key "python")))

(floors-row "libcurl, the key chez-curl holds, is extra here"
  "((chez \"10.9.1\") (libcurl \"7.85.0\") (sqlite \"8.1.2\"))"
  (list (extra-key "libcurl")))

(floors-row "a key in capitals is another key"
  "((Chez \"10.9.1\") (sqlite \"8.1.2\"))"
  (list (missing-key "chez") (extra-key "Chez")))

(floors-row "a key twice"
  "((chez \"10.9.1\") (chez \"10.9.1\") (sqlite \"8.1.2\"))"
  (list (repeated-key "chez" "2")))

(floors-row "a key three times, and another twice"
  "((sqlite \"8.1.2\") (sqlite \"8.1.2\") (sqlite \"8.1.2\") (chez \"10.9.1\") (chez \"10.9.1\"))"
  (list (repeated-key "sqlite" "3") (repeated-key "chez" "2")))

(floors-row "sqlite before chez"
  "((sqlite \"8.1.2\") (chez \"10.9.1\"))"
  (list (misordered "sqlite, chez")))

(floors-row "an extra key and a missing one, and no word about the order"
  "((sqlite \"8.1.2\") (python \"3.12.0\"))"
  (list (missing-key "chez") (extra-key "python")))

;; --- the floors file: the versions ---------------------------------------------------

;; Each floor is three numbers, because that is how the code compares them.
(for-each
 (lambda (text)
   (floors-row (string-append "chez " (q text) " is not three dot-separated naturals")
     (floors-of (q text) good-sqlite)
     (list (bad-version "chez" (q text))))
   (floors-row (string-append "sqlite " (q text) " is not three dot-separated naturals")
     (floors-of good-chez (q text))
     (list (bad-version "sqlite" (q text)))))
 '("10.9" "10" "10.9.1.2" "" "v10.9.1" "10.9.x" "10..1" "10.9." ".9.1" "." " 10.9.1" "10.9.1 "
   "10.09.1" "00.9.1" "010.9.1" "-10.9.1" "+10.9.1" "1e1.9.1" "10.9.1-pre" "10,9,1" "0x10.9.1"
   "\x661;0.9.1"))

(for-each
 (lambda (row)
   (floors-row (string-append "chez " (car row) " is no string")
     (floors-of (car row) good-sqlite)
     (list (bad-version "chez" (car row))))
   (floors-row (string-append "sqlite " (car row) " is no string")
     (floors-of good-chez (car row))
     (list (bad-version "sqlite" (car row)))))
 '(("10") ("10.9") ("ten") ("#f") ("()") ("(\"10.9.1\")")))

(floors-row "a version longer than the message shows is cut"
  (floors-of (q (make-string 70 #\1)) good-sqlite)
  (list (bad-version "chez" (string-append "\"" (make-string 56 #\1) "..."))))

(floors-row "several faults at once come in a fixed order: the entries, the keys, the versions"
  "((chez \"10.9\") (sqlite) (python \"3\"))"
  (list (not-an-entry "(sqlite)")
        (missing-key "sqlite")
        (extra-key "python")
        (bad-version "chez" (q "10.9"))))

;; --- the README ----------------------------------------------------------------------

(define line-chez "- Chez Scheme 10.9.1 or later, built with threads")
(define line-sqlite "- SQLite 8.1.2 or later")
(define good-lines (list line-chez line-sqlite))

;; readme : String ... -> String
;; The lines, each ended by a newline.
(define (readme . lines)
  (apply string-append (map (lambda (line) (string-append line "\n")) lines)))

;; under-section : String ... -> String
;; A README whose Requirements section holds BODY.
(define (under-section . body)
  (apply readme (append (list "* Title" "" "An opening paragraph." "" section "") body)))

(define (readme-row name text problems)
  (test-equal (string-append "README: " name)
    (list 'returned problems)
    (outcome (lambda () (check-floors fp good rp text)))))

(readme-row "the two lines the floors give, in order" (apply under-section good-lines) '())

(readme-row "the section last in the file, with no newline after its last line"
  (string-append (readme "* Title" section line-chez) line-sqlite)
  '())

(readme-row "prose, blank lines and lines that are no bullets between the items"
  (under-section line-chez "Some prose." "" "-not a bullet"
                 "text - with a dash" "-- two dashes" "*bold*" line-sqlite "Closing prose.")
  '())

(readme-row "lists under other headings are not compared"
  (readme "* Title" "** Status" "- Chez Scheme 9.9.9 or later, built with threads"
          section line-chez line-sqlite
          "** License" "- SQLite 1.0.0 or later")
  '())

(readme-row "a deeper heading ends the section"
  (under-section line-chez line-sqlite "*** Details" "- an extra item")
  '())

(readme-row "a heading of one star ends the section"
  (under-section line-chez line-sqlite "* Next" "- an extra item")
  '())

;; the section

(readme-row "an empty README" "" (list no-section))

(readme-row "the right lines and no heading"
  (apply readme (cons "* Title" good-lines))
  (list no-section))

(readme-row "the right lines under another heading"
  (apply readme (append (list "* Title" "** Status") good-lines))
  (list no-section))

(readme-row "a heading of one star"
  (apply readme (append (list "* Title" "* Requirements") good-lines))
  (list no-section))

(readme-row "a heading of three stars"
  (apply readme (append (list "* Title" "*** Requirements") good-lines))
  (list no-section))

(readme-row "a heading with a tag"
  (apply readme (append (list "* Title" "** Requirements :build:") good-lines))
  (list no-section))

(readme-row "a heading in lower case"
  (apply readme (append (list "* Title" "** requirements") good-lines))
  (list no-section))

(readme-row "a plain line that says Requirements"
  (apply readme (append (list "* Title" "Requirements") good-lines))
  (list no-section))

(readme-row "two sections"
  (string-append (apply under-section good-lines) (apply under-section good-lines))
  (list (many-sections "2")))

(readme-row "three sections"
  (string-append (apply under-section good-lines) (apply under-section good-lines)
                 (apply under-section good-lines))
  (list (many-sections "3")))

;; a line altered

(readme-row "the Chez line says an older Chez"
  (under-section "- Chez Scheme 10.8.0 or later, built with threads" line-sqlite)
  (list (altered-line "1" "- Chez Scheme 10.8.0 or later, built with threads" line-chez)))

(readme-row "the Chez line does not say threads"
  (under-section "- Chez Scheme 10.9.1 or later" line-sqlite)
  (list (altered-line "1" "- Chez Scheme 10.9.1 or later" line-chez)))

(readme-row "the SQLite line says another SQLite"
  (under-section line-chez "- SQLite 8.1.3 or later")
  (list (altered-line "2" "- SQLite 8.1.3 or later" line-sqlite)))

(readme-row "a line with a space at its end"
  (under-section line-chez (string-append line-sqlite " "))
  (list (altered-line "2" (string-append line-sqlite " ") line-sqlite)))

(readme-row "a line with two spaces inside it"
  (under-section line-chez "- SQLite 8.1.2  or later")
  (list (altered-line "2" "- SQLite 8.1.2  or later" line-sqlite)))

(readme-row "a line indented"
  (under-section line-chez (string-append "  " line-sqlite))
  (list (altered-line "2" (string-append "  " line-sqlite) line-sqlite)))

(readme-row "a line with a plus for its bullet"
  (under-section "+ Chez Scheme 10.9.1 or later, built with threads" line-sqlite)
  (list (altered-line "1" "+ Chez Scheme 10.9.1 or later, built with threads" line-chez)))

(readme-row "both lines altered"
  (under-section "- Chez Scheme 1.0.0 or later, built with threads"
                 "- SQLite 2.0.0 or later")
  (list (altered-line "1" "- Chez Scheme 1.0.0 or later, built with threads" line-chez)
        (altered-line "2" "- SQLite 2.0.0 or later" line-sqlite)))

;; a line added or lost

(readme-row "an extra line at the end"
  (under-section line-chez line-sqlite "- Python 3 or later")
  (list (extra-line "- Python 3 or later")))

(readme-row "an extra line at the start"
  (under-section "- Python 3 or later" line-chez line-sqlite)
  (list (extra-line "- Python 3 or later")))

(readme-row "an extra line in the middle"
  (under-section line-chez "- Python 3 or later" line-sqlite)
  (list (extra-line "- Python 3 or later")))

(readme-row "an extra line with a plus bullet"
  (under-section line-chez line-sqlite "+ Python 3 or later")
  (list (extra-line "+ Python 3 or later")))

(readme-row "an extra line nested under an item"
  (under-section line-chez line-sqlite "  - nested")
  (list (extra-line "  - nested")))

(readme-row "an extra numbered line"
  (under-section line-chez line-sqlite "1. numbered")
  (list (extra-line "1. numbered")))

(readme-row "an extra numbered line with a parenthesis"
  (under-section line-chez line-sqlite "12) numbered")
  (list (extra-line "12) numbered")))

(readme-row "an extra line with an indented star"
  (under-section line-chez line-sqlite "  * starred")
  (list (extra-line "  * starred")))

(readme-row "an extra line indented with a tab"
  (under-section line-chez line-sqlite "\t- tabbed")
  (list (r: (q section) " has an extra list line, \"\\t- tabbed\", which " fp " does not give")))

(readme-row "a line twice"
  (under-section line-chez line-sqlite line-sqlite)
  (list (extra-line line-sqlite)))

(readme-row "the Chez line missing"
  (under-section line-sqlite)
  (list (lacks-line line-chez)))

(readme-row "the SQLite line missing"
  (under-section line-chez)
  (list (lacks-line line-sqlite)))

(readme-row "the heading and nothing under it"
  (readme "* Title" section)
  (list (lacks-line line-chez) (lacks-line line-sqlite)))

(readme-row "the heading and prose under it"
  (under-section "Prose, and no list.")
  (list (lacks-line line-chez) (lacks-line line-sqlite)))

(readme-row "one line altered and one added"
  (under-section "- Chez Scheme 10.8.0 or later, built with threads" line-sqlite
                 "- Python 3 or later")
  (list (extra-line "- Chez Scheme 10.8.0 or later, built with threads")
        (extra-line "- Python 3 or later")
        (lacks-line line-chez)))

;; lines in another order

(readme-row "the two lines swapped"
  (under-section line-sqlite line-chez)
  (list (altered-line "1" line-sqlite line-chez)
        (altered-line "2" line-chez line-sqlite)))

;; --- the README is held to the file, and the file comes first ------------------------

(test-equal "the lines come from the floors file: other floors, other lines"
  (list 'returned
        (list (altered-line "1" line-chez "- Chez Scheme 10.0.0 or later, built with threads")
              (altered-line "2" line-sqlite "- SQLite 3.45.1 or later")))
  (outcome (lambda ()
             (check-floors fp (floors-of "\"10.0.0\"" "\"3.45.1\"")
                           rp (apply under-section good-lines)))))

(test-equal "a bad floors file is reported alone: the README is not read against it"
  (list 'returned (list (missing-key "sqlite")))
  (outcome (lambda ()
             (check-floors fp "((chez \"10.9.1\"))" rp (readme "* Title")))))

(test-equal "an unreadable README, #f, is not compared"
  '(returned ())
  (outcome (lambda () (check-floors fp good rp #f))))

(test-equal "a bad floors file is reported even when the README is unreadable"
  (list 'returned (list (missing-key "sqlite")))
  (outcome (lambda () (check-floors fp "((chez \"10.9.1\"))" rp #f))))

;; --- the program -----------------------------------------------------------------------

;; run : (Listof String) -> (U (List Integer String String) (List 'raised String))
;; tests/check-floors.sps in a fresh Chez with ARGS: its exit status, stdout
;; and stderr. capture-command makes a directory of its own for each call, and
;; quotes each argument, so two runs of this suite at once share no file.
(define (run args)
  (guard (e (#t (list 'raised (describe e))))
    (capture-command (append (list chez "--libdirs" "tests" "--program" program) args))))

;; at : String String -> String
;; The path the program names for FILE in the fixture directory CASE.
(define (at case file) (string-append fixtures "/" case "/" file))

;; both : String -> (Listof String)
;; The two arguments the program takes for the fixture directory CASE.
(define (both case)
  (list (at case "floors.sexp") (at case "README.org")))

;; refused : Natural String ... -> (List 1 "" String)
;; What a failure prints: PROBLEMS, one line each, then the count. COUNT is
;; given, not counted, so a miscount in the program is not copied here.
(define (refused count . problems)
  (list 1
        ""
        (string-append
         (apply string-append
                (map (lambda (p) (string-append "check-floors: " p "\n")) problems))
         "check-floors: FAILED (problems: " (number->string count) ")\n")))

;; workflows-refusal : String -> String
;; The problem for a workflow directory at PATH, as the program prints it.
(define (workflows-refusal path)
  (string-append path ": it exists, but the workflow rules are not written yet (M0 slice 4)"))

(define (cannot-read path)
  (string-append path ": it cannot be read: Exception in open-file-input-port: failed for "
                 path ": no such file or directory"))

(define usage
  (list 1
        ""
        "check-floors: usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README\n"))

;; cases : (Listof (List String String (Listof String) Expected))
;; The fixture directory, what it holds, the arguments, and the program's
;; whole answer.
(define cases
  (list
   (list "legal"
         "floors no real floor equals, a README with their lines among other lists and sections"
         (both "legal")
         (list 0
               (string-append "check-floors: " (at "legal" "README.org") " holds the floors in "
                              (at "legal" "floors.sexp") " (chez 10.9.1, sqlite 8.1.2)\n")
               ""))
   (list "readme-altered"
         "one README line altered"
         (both "readme-altered")
         (refused 1 (string-append
                     (at "readme-altered" "README.org")
                     ": list line 1 under \"** Requirements\" is \"- Chez Scheme 10.8.0 or later, built with threads\", but "
                     (at "readme-altered" "floors.sexp")
                     " gives \"- Chez Scheme 10.9.1 or later, built with threads\"")))
   (list "no-section"
         "the right lines under another heading"
         (both "no-section")
         (refused 1 (string-append (at "no-section" "README.org")
                                   ": it has no \"** Requirements\" section")))
   (list "floors-invalid"
         "a floors file with a bad version and an extra key: both named, and the README not read against it"
         (both "floors-invalid")
         (refused 2
                  (string-append (at "floors-invalid" "floors.sexp") ": the key python is extra: the keys are chez, sqlite")
                  (string-append (at "floors-invalid" "floors.sexp")
                                 ": chez: the version \"10.9\" is not three dot-separated naturals, major.minor.patch")))
   (list "empty-readme"
         "an empty README, which reads as no text, not as an end of file"
         (both "empty-readme")
         (refused 1 (string-append (at "empty-readme" "README.org")
                                   ": it has no \"** Requirements\" section")))
   (list "no-readme"
         "a floors file and no README beside it"
         (both "no-readme")
         (refused 1 (cannot-read (at "no-readme" "README.org"))))
   (list "no-floors"
         "a README and no floors file beside it"
         (both "no-floors")
         (refused 1 (cannot-read (at "no-floors" "floors.sexp"))))
   ;; The workflow directory is looked for beside the README, as .github/workflows.
   (list "workflows"
         "a legal floors file and README, and a .github/workflows beside the README: a tripwire until slice 4 writes the workflow rules"
         (both "workflows")
         (refused 1 (workflows-refusal (at "workflows" ".github/workflows"))))
   (list "no-arguments" "no arguments at all" '() usage)
   (list "one-argument" "one argument" (list (at "legal" "floors.sexp")) usage)
   (list "three-arguments" "three arguments"
         (list (at "legal" "floors.sexp") (at "legal" "README.org") (at "legal" "README.org"))
         usage)))

(for-each
 (lambda (row)
   (test-equal (string-append "program: " (car row) ": " (cadr row))
     (list 'returned (cadddr row))
     (outcome (lambda () (run (caddr row))))))
 cases)

(test-equal "workflows-problems: a directory that exists is a problem, naming it; one that does not is none"
  (list 'returned
        (list (workflows-refusal "d/.github/workflows") '()))
  (outcome (lambda ()
             (list (car (workflows-problems "d/.github/workflows" #t))
                   (workflows-problems "d/.github/workflows" #f)))))

(test-equal "workflows-problems: exactly one problem when the directory exists"
  '(returned 1)
  (outcome (lambda () (length (workflows-problems "x" #t)))))

(test-equal "program: a floors file and a README both missing are both named, the floors file first"
  (list 'returned
        (refused 2 (cannot-read (at "nothing" "floors.sexp")) (cannot-read (at "nothing" "README.org"))))
  (outcome (lambda () (run (both "nothing")))))

;; --- the answers (floors) gives a suite ------------------------------------------------

(define (floor-row name proc key expected)
  (test-equal name
    (list 'returned expected)
    (outcome (lambda () (proc (parse-floors good) key)))))

(test-equal "parse-floors answers the floors file's datum"
  `(returned ((chez "10.9.1") (sqlite "8.1.2")))
  (outcome (lambda () (parse-floors good))))

(floor-row "floor-text: chez" floor-text 'chez "10.9.1")
(floor-row "floor-text: sqlite" floor-text 'sqlite "8.1.2")
(floor-row "floor-numbers: chez" floor-numbers 'chez '(10 9 1))
(floor-row "floor-numbers: sqlite" floor-numbers 'sqlite '(8 1 2))

(test-equal "floor-numbers: zeros and several digits stay as they are"
  '(returned ((0 0 0) (10 0 10)))
  (outcome (lambda ()
             (let ((floors (parse-floors (floors-of "\"0.0.0\"" "\"10.0.10\""))))
               (map (lambda (key) (floor-numbers floors key)) '(chez sqlite))))))

(test-equal "floor-text: a name that is no floor is refused, by name"
  '(raised "Exception in floor-text: no such floor with irritant python")
  (outcome (lambda () (floor-text (parse-floors good) 'python))))

(test-equal "floor-numbers: a name that is no floor is refused, by name"
  '(raised "Exception in floor-numbers: no such floor with irritant python")
  (outcome (lambda () (floor-numbers (parse-floors good) 'python))))

(test-equal "parse-floors refuses a file with a problem, naming it"
  '(raised "Exception in parse-floors: packaging/floors.sexp: the key sqlite is missing")
  (outcome (lambda () (parse-floors "((chez \"10.9.1\"))"))))

(test-equal "parse-floors refuses a file with two problems, naming both"
  '(raised "Exception in parse-floors: packaging/floors.sexp: the key sqlite is missing; packaging/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, major.minor.patch")
  (outcome (lambda () (parse-floors "((chez \"10.9\"))"))))

(test-equal "requirement-lines: the two lines the README states, from the file"
  (list 'returned good-lines)
  (outcome (lambda () (requirement-lines (parse-floors good)))))

(test-equal "requirement-lines: other floors, other lines"
  '(returned ("- Chez Scheme 11.0.0 or later, built with threads"
              "- SQLite 9.9.9 or later"))
  (outcome (lambda ()
             (requirement-lines (parse-floors (floors-of "\"11.0.0\"" "\"9.9.9\""))))))

(test-equal "floors-path names the checked-in file"
  "packaging/floors.sexp"
  floors-path)

(test-equal "the checked-in floors file is legal"
  '(returned ())
  (outcome (lambda () (floors-problems floors-path (file-text floors-path)))))

(test-equal "read-floors answers the checked-in file's two floors, in order"
  '(returned (chez sqlite))
  (outcome (lambda () (map car (read-floors)))))

(test-equal "the checked-in floors are Chez 10.4.0 and SQLite 3.45.1"
  '(returned (((10 4 0) (3 45 1)) "10.4.0" "3.45.1"))
  (outcome (lambda ()
             (let ((floors (read-floors)))
               (list (list (floor-numbers floors 'chez) (floor-numbers floors 'sqlite))
                     (floor-text floors 'chez)
                     (floor-text floors 'sqlite))))))

(test-equal "the checked-in README holds the checked-in floors"
  '(returned ())
  (outcome (lambda ()
             (check-floors floors-path (file-text floors-path)
                           "README.org" (file-text "README.org")))))

(test-end "check-floors")

(exit (suite-exit-status runner))
