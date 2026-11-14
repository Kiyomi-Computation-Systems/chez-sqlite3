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
;;; The CI rules hold every file under the workflow directory: no line may
;;; contain a floor's version text, and none may hold a backslash after a
;;; double quote. The same file tests the CI scripts that read the floors file
;;; or hold the workflows, scripts/ci/floor.sh and check-action-pins.sh, in
;;; temporary trees and directories the suite makes, each call in a directory
;;; of its own.
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
        (only (chezscheme) directory-list file-directory? getenv system
              scheme-version-number))

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

;; --- the workflows the README rows are held beside ----------------------------------

(define wd "W")
(define wp "W/ci.yml")

;; wrote : String Natural String String String -> String
;; The complaint about line N of the workflow file PATH, which contains a
;; floor's version text. WHICH is "Chez" or "SQLite", VERSION its floor,
;; FLOORS the floors file's path.
(define (wrote path n which version floors)
  (string-append path ": line " (number->string n) " contains the " which " floor " version
                 ", which no workflow line may write: the CI scripts read it from " floors))

;; literal : Natural String String -> String
;; The complaint about line N of ci.yml, held against the floors file f.sexp.
(define (literal n which version) (wrote wp n which version fp))

;; elsewhere : String Natural String String -> String
;; The same for a workflow file but ci.yml.
(define (elsewhere path n which version) (wrote path n which version fp))

;; form-wrote : String Natural String String String String -> String
;; The complaint about line N of the workflow file PATH, which contains FORM,
;; the WHAT form of the SQLite floor VERSION, FLOORS the floors file's path.
(define (form-wrote path n form what version floors)
  (string-append path ": line " (number->string n) " contains " form ", the " what
                 " form of the SQLite floor " version
                 ", which no workflow line may write: the CI scripts read it from " floors))

;; numbered, amalgam : String Natural -> String
;; The complaint about line N of the file PATH for 8001002, the version number
;; of the fixtures' floor 8.1.2, and for 8010200, its amalgamation number.
(define (numbered path n) (form-wrote path n "8001002" "version-number" "8.1.2" fp))
(define (amalgam path n) (form-wrote path n "8010200" "amalgamation" "8.1.2" fp))

;; escaped : String Natural -> String
;; The complaint about line N of the workflow file PATH, which holds a
;; backslash after a double quote.
(define (escaped path n)
  (string-append path ": line " (number->string n)
                 " holds a backslash after a double quote, which YAML may read as an escape, and check-floors does not"))

;; open-quote : String Natural -> String
;; The complaint about line N of the workflow file PATH, which holds an odd
;; number of double quotes.
(define (open-quote path n)
  (string-append path ": line " (number->string n)
                 " holds an odd number of double quotes, so a double-quoted string goes on past it, where YAML may read an escape, and check-floors reads line by line"))

;; no-files, no-ci : String
;; The complaints about a workflow directory that holds no file, and one that
;; holds files but no ci.yml.
(define no-files (string-append wd ": it holds no file, but must hold ci.yml, the workflow CI runs"))
(define no-ci (string-append wd ": it holds no ci.yml, the workflow CI runs"))

;; workflow : String ... -> String
;; The lines, each ended by a newline.
(define (workflow . lines)
  (apply string-append (map (lambda (line) (string-append line "\n")) lines)))

;; workflow-with : String ... -> String
;; A legal workflow, which states no floor, with the lines BODY after its first
;; job's steps.
(define (workflow-with . body)
  (apply workflow
         (append (list "name: CI" "" "on:" "  pull_request:" "" "jobs:" "  main:"
                       "    runs-on: ubuntu-24.04" "    steps:"
                       "      - run: scripts/ci/build-chez.sh /opt/chez"
                       "      - run: scripts/ci/floor.sh sqlite")
                 body)))

;; The first line of BODY in workflow-with is line 12.
(define body-line 12)

(define good-workflow (workflow-with))

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
    (outcome (lambda () (check-floors fp good rp text wd (list (list wp good-workflow)))))))

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

;; --- the workflow: what is legal -----------------------------------------------------

(define (workflow-row name text problems)
  (test-equal (string-append "workflow: " name)
    (list 'returned problems)
    (outcome (lambda ()
               (check-floors fp good rp (apply under-section good-lines) wd (list (list wp text)))))))

(workflow-row "a workflow that states no floor: nothing to report" good-workflow '())

(workflow-row "a version that is no floor of the file may be written anywhere, the real floors among them"
  (workflow-with "      - run: echo 10.4.0 3.45.1, the real floors, here other versions"
                 "      - run: echo 10.9 8.1 10.9.0 8.1.3")
  '())

;; check-floors reads text, not YAML. A matrix value of another version is no
;; floor's text, so it is not seen here: the scripts read the floors from the
;; file and take no version, so the value reaches nothing.
(workflow-row "a matrix value of another version is no floor's text: check-floors cannot see it"
  (workflow "jobs:" "  floor:" "    strategy:" "      matrix:" "        sqlite: [\"8.1.3\", \"8.1.1\"]")
  '())

(workflow-row "a backslash before the first double quote, and none after it: nothing to report"
  (workflow-with "      - run: printf '%s\\n' \"x\"" "      - run: echo \\\"a\"")
  '())

(workflow-row "a backslash in single quotes, with no double quote before it: nothing to report"
  (workflow-with "          pkgs=$(tr '\\n' ' ')")
  '())

;; --- the workflow: a floor written anywhere ------------------------------------------

(workflow-row "the Chez floor in a run step"
  (workflow-with "      - run: scripts/ci/build-chez.sh 10.9.1 /opt/chez")
  (list (literal body-line "Chez" "10.9.1")))

(workflow-row "the SQLite floor in a run step"
  (workflow-with "      - run: scripts/ci/floor.sh 8.1.2")
  (list (literal body-line "SQLite" "8.1.2")))

(workflow-row "the Chez floor in a comment"
  (workflow-with "      # Chez 10.9.1 is built from its tarball")
  (list (literal body-line "Chez" "10.9.1")))

(workflow-row "the SQLite floor in a cache key"
  (workflow-with "          key: sqlite-8.1.2-linux")
  (list (literal body-line "SQLite" "8.1.2")))

(workflow-row "the floor inside a longer number is still the floor's text, before it and after it"
  (workflow-with "      - run: echo 110.9.1" "      - run: echo 8.1.23")
  (list (literal body-line "Chez" "10.9.1")
        (literal (+ body-line 1) "SQLite" "8.1.2")))

(workflow-row "both floors on one line: both are named, the Chez floor first"
  (workflow-with "      - run: echo 8.1.2 10.9.1")
  (list (literal body-line "Chez" "10.9.1")
        (literal body-line "SQLite" "8.1.2")))

(workflow-row "a floor on several lines: each line is named, in line order"
  (workflow-with "      - run: echo 8.1.2" "      - run: echo fine" "      - run: echo 10.9.1")
  (list (literal body-line "SQLite" "8.1.2")
        (literal (+ body-line 2) "Chez" "10.9.1")))

(workflow-row "a floor on the first line, and on the last, which has no newline after it"
  (string-append "# 10.9.1\n" "name: CI\n" "# 8.1.2")
  (list (literal 1 "Chez" "10.9.1") (literal 3 "SQLite" "8.1.2")))

;; --- the workflow: the SQLite floor's numeric forms ----------------------------------
;; The floor 8.1.2 is 8001002 as SQLITE_VERSION_NUMBER and 8010200 as the
;; amalgamation's file name, written here by hand. A form is found as a whole
;; run of digits only: no ASCII letter or digit on either side.

(define (num-row name line problems)
  (workflow-row name (workflow-with line) problems))

(num-row "the version number at the start of a line"
  "8001002 is the number" (list (numbered wp body-line)))
(num-row "the version number in the middle of a line"
  "      - run: echo want 8001002 here" (list (numbered wp body-line)))
(num-row "the version number at the end of a line"
  "      - run: echo want 8001002" (list (numbered wp body-line)))
(num-row "the amalgamation number at the start of a line"
  "8010200 is the number" (list (amalgam wp body-line)))
(num-row "the amalgamation number in the middle of a line"
  "      - run: curl -O https://x.invalid/sqlite-amalgamation-8010200.zip" (list (amalgam wp body-line)))
(num-row "the amalgamation number at the end of a line"
  "      - run: echo want 8010200" (list (amalgam wp body-line)))

(num-row "a form beside a dot, a dash, an underscore or a space is found"
  "      - run: echo .8001002. -8010200_"
  (list (numbered wp body-line) (amalgam wp body-line)))
(num-row "a form beside a non-ASCII letter is found: only ASCII letters and digits bound a run"
  "      - run: echo \xe9;8001002\xe9; \x3b1;8010200"
  (list (numbered wp body-line) (amalgam wp body-line)))

(num-row "the version number beside a digit on its left, a digit on its right, a letter on each side: not found"
  "      - run: echo 18001002 80010021 a8001002 8001002f"
  '())
(num-row "the amalgamation number beside a digit on its left, a digit on its right, a letter on each side: not found"
  "      - run: echo 18010200 80102001 a8010200 8010200f"
  '())
(num-row "an upper-case letter beside a form is a letter too: not found"
  "      - run: echo A8001002 8010200Z"
  '())
(num-row "a hex digest holding a form between letters and digits: not found"
  "      - run: echo deadbeef8001002cafe 9f8010200a1"
  '())
(num-row "a form past an unfound one on the same line is still found: the scan tries every position"
  "      - run: echo 18001002 x8001002 8001002"
  (list (numbered wp body-line)))
(num-row "a run that holds the version number twice is no form, and a form beside it is found"
  "      - run: echo 80010028001002 8010200"
  (list (amalgam wp body-line)))
(num-row "a form twice on a line is named once"
  "      - run: echo 8001002 8001002"
  (list (numbered wp body-line)))
(num-row "both forms and the dotted floor on one line: the dotted floor, the version number, the amalgamation number"
  "      - run: echo 8010200 8001002 8.1.2"
  (list (literal body-line "SQLite" "8.1.2") (numbered wp body-line) (amalgam wp body-line)))
(num-row "the forms of the real floors, 3.45.1, are no form of the fixtures' floor"
  "      - run: echo 3045001 3450100"
  '())
(num-row "the Chez floor 10.9.1 has no numeric form: its digits run together, in each layout, are not found"
  "      - run: echo 10009001 10090100 100901 1009001 10901 1091"
  '())

(workflow-row "a form on the first line of a file, and another on the last, which has no newline after it"
  (string-append "8001002\n" "name: CI\n" "# 8010200")
  (list (numbered wp 1) (amalgam wp 3)))

;; --- the workflow: a backslash after a double quote ----------------------------------
;; YAML reads escapes inside double quotes, so "8\x2e1\x2e2" is the SQLite
;; floor with no floor text in it. check-floors does not resolve them: it
;; fails the line closed.

(workflow-row "a backslash after a double quote spells a floor with none of its text"
  (workflow-with "      - run: echo \"8\\x2e1\\x2e2\"")
  (list (escaped wp body-line)))

(workflow-row "a backslash after a double quote that is never closed: named twice, as an escape and as a string left open"
  (workflow-with "      - run: echo \"a\\")
  (list (escaped wp body-line) (open-quote wp body-line)))

(workflow-row "a backslash in a double-quoted key"
  (workflow-with "          \"sq\\x6cite\": x")
  (list (escaped wp body-line)))

(workflow-row "a backslash right after the opening quote, of a string left open"
  (workflow-with "      - run: echo \"\\")
  (list (escaped wp body-line) (open-quote wp body-line)))

(workflow-row "a double-quoted string left open goes on over the next line, where an escape spells a floor: both lines named"
  (workflow-with "    env:" "      CHEZ_FLOOR: \"" "        \\x31\\x30.9.1\"")
  (list (open-quote wp (+ body-line 1)) (open-quote wp (+ body-line 2))))

(workflow-row "a double-quoted string closed on its own line: nothing to report"
  (workflow-with "    env:" "      NOTE: \"one \" and \"two\"")
  '())

(workflow-row "a backslash after the second double quote still counts"
  (workflow-with "      - run: echo \"a\" \"b\" \\")
  (list (escaped wp body-line)))

(workflow-row "a floor and a backslash after a quote on one line: the floor first"
  (workflow-with "      - run: echo 10.9.1 \"\\n\"")
  (list (literal body-line "Chez" "10.9.1") (escaped wp body-line)))

(workflow-row "each rule on its own line: line order"
  (workflow-with "      - run: echo \"\\n\"" "      - run: echo 8.1.2")
  (list (escaped wp body-line) (literal (+ body-line 1) "SQLite" "8.1.2")))

;; --- the workflows: every file under the directory -----------------------------------

(define (workflows-row name workflows problems)
  (test-equal (string-append "workflows: " name)
    (list 'returned problems)
    (outcome (lambda ()
               (check-floors fp good rp (apply under-section good-lines) wd workflows)))))

(define release "W/release.yml")

;; release-with : String ... -> String
;; A second workflow, with the lines BODY after its steps. The first line of
;; BODY is line 7.
(define (release-with . body)
  (apply workflow
         (append (list "name: Release" "on:" "  push:" "jobs:" "  release:" "    steps:")
                 body)))

(define release-line 7)

(define clean-release (release-with "      - run: make build"))

(workflows-row "a second workflow that writes no floor: nothing to report"
  (list (list wp good-workflow) (list release clean-release))
  '())

(workflows-row "a second workflow that writes the Chez floor in a step: named, by its own path and line"
  (list (list wp good-workflow)
        (list release (release-with "      - run: scripts/ci/build-chez.sh 10.9.1 /opt/chez")))
  (list (elsewhere release release-line "Chez" "10.9.1")))

(workflows-row "a second workflow that writes the SQLite floor in a comment"
  (list (list wp good-workflow)
        (list release (release-with "      - run: make build" "# sqlite 8.1.2 is the floor")))
  (list (elsewhere release (+ release-line 1) "SQLite" "8.1.2")))

(workflows-row "a second workflow with a backslash after a double quote"
  (list (list wp good-workflow)
        (list release (release-with "      - run: echo \"\\x38\"")))
  (list (escaped release release-line)))

(workflows-row "every file is held, in path order, whatever order they come in; a line names its floors in order"
  (list (list "W/z.yml" (workflow "# 10.9.1"))
        (list wp (workflow-with "      - run: echo 8.1.2"))
        (list "W/a.yml" (workflow "" "# 8.1.2 and 10.9.1")))
  (list (elsewhere "W/a.yml" 2 "Chez" "10.9.1")
        (elsewhere "W/a.yml" 2 "SQLite" "8.1.2")
        (literal body-line "SQLite" "8.1.2")
        (elsewhere "W/z.yml" 1 "Chez" "10.9.1")))

(workflows-row "a second workflow with a numeric form: named, by its own path and line"
  (list (list wp good-workflow)
        (list release (release-with "      - run: echo 8001002")))
  (list (numbered release release-line)))

(workflows-row "a file in a subdirectory is held like any other"
  (list (list wp good-workflow) (list "W/sub/notes.yml" (workflow "# 10.9.1")))
  (list (elsewhere "W/sub/notes.yml" 1 "Chez" "10.9.1")))

(workflows-row "a ci.yml in a subdirectory is not the workflow: there is no ci.yml, and its lines are held"
  (list (list "W/sub/ci.yml" (workflow-with "      - run: echo 10.9.1")))
  (list no-ci
        (elsewhere "W/sub/ci.yml" body-line "Chez" "10.9.1")))

(workflows-row "a file that is not a workflow by its name is held too"
  (list (list wp good-workflow) (list "W/notes.txt" (workflow "8.1.2")))
  (list (elsewhere "W/notes.txt" 1 "SQLite" "8.1.2")))

(workflows-row "no file at all: the directory is named, once"
  '()
  (list no-files))

(workflows-row "no ci.yml, and a second workflow that writes no floor"
  (list (list release clean-release))
  (list no-ci))

(workflows-row "an unreadable ci.yml, #f, is not compared, and is no missing ci.yml; the others still are"
  (list (list wp #f)
        (list release (release-with "      - run: echo 10.9.1")))
  (list (elsewhere release release-line "Chez" "10.9.1")))

(workflows-row "an unreadable second workflow, #f, is not compared"
  (list (list wp good-workflow) (list release #f))
  '())

(workflows-row "a workflow directory that could not be read, #f, is not compared"
  #f
  '())

(test-equal "a bad floors file is reported alone: the workflows are not read against it"
  (list 'returned (list (missing-key "sqlite")))
  (outcome (lambda ()
             (check-floors fp "((chez \"10.9.1\"))" rp (apply under-section good-lines)
                           wd (list (list wp (workflow "# 10.9.1")))))))

(test-equal "a README problem and a workflow problem: both named, the README first"
  (list 'returned
        (list (lacks-line line-sqlite) (literal 1 "Chez" "10.9.1")))
  (outcome (lambda ()
             (check-floors fp good rp (under-section line-chez)
                           wd (list (list wp (workflow "# 10.9.1")))))))

;; --- the README is held to the file, and the file comes first ------------------------

(test-equal "the lines come from the floors file: other floors, other lines"
  (list 'returned
        (list (altered-line "1" line-chez "- Chez Scheme 10.0.0 or later, built with threads")
              (altered-line "2" line-sqlite "- SQLite 3.45.1 or later")))
  (outcome (lambda ()
             (check-floors fp (floors-of "\"10.0.0\"" "\"3.45.1\"")
                           rp (apply under-section good-lines)
                           wd (list (list wp good-workflow))))))

(test-equal "a bad floors file is reported alone: the README is not read against it"
  (list 'returned (list (missing-key "sqlite")))
  (outcome (lambda ()
             (check-floors fp "((chez \"10.9.1\"))" rp (readme "* Title")
                           wd (list (list wp good-workflow))))))

(test-equal "an unreadable README, #f, is not compared"
  '(returned ())
  (outcome (lambda () (check-floors fp good rp #f wd (list (list wp good-workflow))))))

(test-equal "a bad floors file is reported even when the README is unreadable"
  (list 'returned (list (missing-key "sqlite")))
  (outcome (lambda ()
             (check-floors fp "((chez \"10.9.1\"))" rp #f wd (list (list wp good-workflow))))))

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
;; The three arguments the program takes for the fixture directory CASE: the
;; floors file, the README and the workflow directory.
(define (both case)
  (list (at case "floors.sexp") (at case "README.org") (at case "workflows")))

;; holds : String String String String String -> (List 0 String "")
;; What a pass prints: the README and the workflow directory that hold the
;; floors in the floors file, the files read there, and the floors.
(define (holds readme-path workflows-path names floors-path summary)
  (list 0
        (string-append "check-floors: " readme-path " and " workflows-path " (" names ")"
                       " hold the floors in " floors-path " (" summary ")\n")
        ""))

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

(define (cannot-read path)
  (string-append path ": it cannot be read: Exception in open-file-input-port: failed for "
                 path ": no such file or directory"))

;; cannot-list : String String -> String
;; The complaint about a workflow directory at PATH that cannot be listed, for
;; WHY: "no such file or directory", or "not a directory".
(define (cannot-list path why)
  (string-append path ": it cannot be read: Exception in directory-list: failed for "
                 path ": " why))

(define usage
  (list 1
        ""
        "check-floors: usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README WORKFLOWS\n"))

(define floors-summary "chez 10.9.1, sqlite 8.1.2")

;; of-number, of-amalgam : String Natural -> String
;; The complaint about line N of the fixture CASE's ci.yml for 8001002, or
;; 8010200, the forms of its floor 8.1.2.
(define (of-number case n)
  (form-wrote (at case "workflows/ci.yml") n "8001002" "version-number" "8.1.2" (at case "floors.sexp")))
(define (of-amalgam case n)
  (form-wrote (at case "workflows/ci.yml") n "8010200" "amalgamation" "8.1.2" (at case "floors.sexp")))

;; cases : (Listof (List String String (Listof String) Expected))
;; The fixture directory, what it holds, the arguments, and the program's
;; whole answer. Every fixture directory is one case, and each has its
;; workflows in a directory of its own.
(define cases
  (list
   (list "legal"
         "floors no real floor equals, a README with their lines among other lists and sections, a ci.yml that states no floor"
         (both "legal")
         (holds (at "legal" "README.org") (at "legal" "workflows") "ci.yml" (at "legal" "floors.sexp")
                floors-summary))
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
         "a floors file with a bad version and an extra key: both named, and the README and workflows not read against it"
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
   (list "workflow-chez-literal"
         "ci.yml passes the Chez floor to a build script"
         (both "workflow-chez-literal")
         (refused 1 (wrote (at "workflow-chez-literal" "workflows/ci.yml") 11 "Chez" "10.9.1"
                           (at "workflow-chez-literal" "floors.sexp"))))
   (list "workflow-sqlite-literal"
         "ci.yml has the SQLite floor in a cache key"
         (both "workflow-sqlite-literal")
         (refused 1 (wrote (at "workflow-sqlite-literal" "workflows/ci.yml") 11 "SQLite" "8.1.2"
                           (at "workflow-sqlite-literal" "floors.sexp"))))
   (list "workflow-sqlite-number"
         "ci.yml writes the SQLite floor's version number, 8001002, at the start of a line, in the middle and at the end"
         (both "workflow-sqlite-number")
         (refused 3 (of-number "workflow-sqlite-number" 11)
                  (of-number "workflow-sqlite-number" 12)
                  (of-number "workflow-sqlite-number" 13)))
   (list "workflow-sqlite-amalgamation"
         "ci.yml writes the SQLite floor's amalgamation number, 8010200, at the start of a line, in a file name and at the end"
         (both "workflow-sqlite-amalgamation")
         (refused 3 (of-amalgam "workflow-sqlite-amalgamation" 11)
                  (of-amalgam "workflow-sqlite-amalgamation" 12)
                  (of-amalgam "workflow-sqlite-amalgamation" 13)))
   (list "workflow-sqlite-digits"
         "ci.yml writes both numeric forms beside letters and digits, and the Chez floor's digits run together: nothing to report"
         (both "workflow-sqlite-digits")
         (holds (at "workflow-sqlite-digits" "README.org") (at "workflow-sqlite-digits" "workflows")
                "ci.yml" (at "workflow-sqlite-digits" "floors.sexp") floors-summary))
   (list "workflow-other-floor"
         "its floors file names SQLite 3.46.0: its forms are found, and 3.45.1's forms, on the same lines, are not"
         (both "workflow-other-floor")
         (refused 3
                  (form-wrote (at "workflow-other-floor" "workflows/ci.yml") 11 "3046000" "version-number" "3.46.0"
                              (at "workflow-other-floor" "floors.sexp"))
                  (form-wrote (at "workflow-other-floor" "workflows/ci.yml") 12 "3460000" "amalgamation" "3.46.0"
                              (at "workflow-other-floor" "floors.sexp"))
                  (form-wrote (at "workflow-other-floor" "workflows/ci.yml") 13 "3460000" "amalgamation" "3.46.0"
                              (at "workflow-other-floor" "floors.sexp"))))
   (list "workflow-both"
         "a comment in ci.yml names both floors: each named, the Chez floor first"
         (both "workflow-both")
         (refused 2
                  (wrote (at "workflow-both" "workflows/ci.yml") 11 "Chez" "10.9.1"
                         (at "workflow-both" "floors.sexp"))
                  (wrote (at "workflow-both" "workflows/ci.yml") 11 "SQLite" "8.1.2"
                         (at "workflow-both" "floors.sexp"))))
   (list "workflow-escaped"
         "ci.yml spells the SQLite floor with escapes, \"8\\x2e1\\x2e2\", which holds no floor text"
         (both "workflow-escaped")
         (refused 1 (escaped (at "workflow-escaped" "workflows/ci.yml") 11)))
   (list "workflow-other-version"
         "ci.yml writes versions that are no floor of the fixture, the real floors among them: nothing to report"
         (both "workflow-other-version")
         (holds (at "workflow-other-version" "README.org") (at "workflow-other-version" "workflows")
                "ci.yml" (at "workflow-other-version" "floors.sexp") floors-summary))
   (list "no-workflow"
         "a floors file and a README, and no workflow directory beside them"
         (both "no-workflow")
         (refused 1 (cannot-list (at "no-workflow" "workflows") "no such file or directory")))
   (list "workflows-no-ci"
         "a workflow directory that holds release.yml and no ci.yml"
         (both "workflows-no-ci")
         (refused 1 (string-append (at "workflows-no-ci" "workflows") ": it holds no ci.yml, the workflow CI runs")))
   (list "workflows-second-literal"
         "a second workflow beside ci.yml writes the Chez floor in a step"
         (both "workflows-second-literal")
         (refused 1 (wrote (at "workflows-second-literal" "workflows/release.yml") 7 "Chez" "10.9.1"
                           (at "workflows-second-literal" "floors.sexp"))))
   (list "workflows-second-clean"
         "a second workflow beside ci.yml that writes no floor: both read, and both named"
         (both "workflows-second-clean")
         (holds (at "workflows-second-clean" "README.org") (at "workflows-second-clean" "workflows")
                "ci.yml, release.yml" (at "workflows-second-clean" "floors.sexp") floors-summary))
   (list "workflows-nested"
         "a file in a subdirectory of the workflows names the SQLite floor in a comment"
         (both "workflows-nested")
         (refused 1 (wrote (at "workflows-nested" "workflows/sub/notes.yml") 2 "SQLite" "8.1.2"
                           (at "workflows-nested" "floors.sexp"))))
   (list "workflows-dir-link"
         "a symbolic link to a directory among the workflows is not followed: it is a file that cannot be read"
         (both "workflows-dir-link")
         (refused 1 (string-append
                     (at "workflows-dir-link" "workflows/linked")
                     ": it cannot be read: Exception in get-string-all: failed on #<binary input port "
                     (at "workflows-dir-link" "workflows/linked") ">: is a directory")))
   (list "workflows-self-link"
         "the workflow directory is itself a symbolic link to a directory with a legal ci.yml: refused, not followed"
         (both "workflows-self-link")
         (refused 1 (string-append (at "workflows-self-link" "workflows")
                                   ": it cannot be read: Exception: it is a symbolic link, not a directory")))))

;; ad hoc : (List String (Listof String) Expected)
;; Runs that need no directory of their own: no file exists, a bad floors file
;; with no README, a workflows argument that is a file, and the wrong number of
;; arguments.
(define ad-hoc
  (list
   (list "no file exists: all three named, the floors first, then the README, then the workflow directory"
         (list (at "legal" "none.sexp") (at "legal" "none.org") (at "legal" "none"))
         (refused 3 (cannot-read (at "legal" "none.sexp"))
                  (cannot-read (at "legal" "none.org"))
                  (cannot-list (at "legal" "none") "no such file or directory")))
   (list "a bad floors file, no README and no workflow directory: the floors problems, then the README, then the directory"
         (list (at "floors-invalid" "floors.sexp") (at "floors-invalid" "none.org")
               (at "floors-invalid" "none"))
         (refused 4
                  (string-append (at "floors-invalid" "floors.sexp") ": the key python is extra: the keys are chez, sqlite")
                  (string-append (at "floors-invalid" "floors.sexp")
                                 ": chez: the version \"10.9\" is not three dot-separated naturals, major.minor.patch")
                  (cannot-read (at "floors-invalid" "none.org"))
                  (cannot-list (at "floors-invalid" "none") "no such file or directory")))
   (list "a README with a problem and no workflow directory: both named, the README first"
         (list (at "legal" "floors.sexp") (at "no-section" "README.org") (at "legal" "none"))
         (refused 2
                  (string-append (at "no-section" "README.org") ": it has no \"** Requirements\" section")
                  (cannot-list (at "legal" "none") "no such file or directory")))
   (list "the workflows argument names ci.yml itself, a file: it cannot be read as a directory"
         (list (at "legal" "floors.sexp") (at "legal" "README.org") (at "legal" "workflows/ci.yml"))
         (refused 1 (cannot-list (at "legal" "workflows/ci.yml") "not a directory")))
   (list "no arguments: the usage line, exit 1" '() usage)
   (list "one argument: the usage line, exit 1" (list (at "legal" "floors.sexp")) usage)
   (list "two arguments: the usage line, exit 1"
         (list (at "legal" "floors.sexp") (at "legal" "README.org"))
         usage)
   (list "four arguments: the usage line, exit 1"
         (list (at "legal" "floors.sexp") (at "legal" "README.org") (at "legal" "workflows") "extra")
         usage)))

(for-each
 (lambda (row)
   (test-equal (string-append "program: " (car row) ": " (cadr row))
     (list 'returned (cadddr row))
     (outcome (lambda () (run (caddr row))))))
 cases)

(for-each
 (lambda (row)
   (test-equal (string-append "program: " (car row))
     (list 'returned (caddr row))
     (outcome (lambda () (run (cadr row))))))
 ad-hoc)

;; git keeps no empty directory, so the empty workflow directory is made here,
;; beside a floors file and a README that pass. Its path is the run's input,
;; so the expected answer is built from it; the answer itself is the program's.
(test-equal "program: an empty workflow directory: named, once, and nothing else"
  '(returned same)
  (outcome
   (lambda ()
     (call-with-temp-directory
      (lambda (dir)
        (let ((got (run (list (at "no-workflow" "floors.sexp") (at "no-workflow" "README.org") dir)))
              (want (refused 1 (string-append dir ": it holds no file, but must hold ci.yml,"
                                              " the workflow CI runs"))))
          (if (equal? got want) 'same (list 'got got 'want want))))))))

;; The program and the pure procedure agree on the fixtures: each answer above
;; comes from check-floors on the files' texts. A fixture the pure procedure
;; passes, but the program refuses, would be the program's own rule.
(test-equal "the legal fixture's files pass the pure procedure"
  '(returned ())
  (outcome (lambda ()
             (check-floors "f" (file-text (at "legal" "floors.sexp"))
                           "r" (file-text (at "legal" "README.org"))
                           "w" (list (list "w/ci.yml" (file-text (at "legal" "workflows/ci.yml"))))))))

;; A fixture nothing runs guards nothing, and a case with no fixture runs on a
;; missing directory.
(test-equal "every fixture directory is a case above, and every case has its directory"
  (list 'returned (list-sort string<? (map car cases)))
  (outcome (lambda ()
             (list-sort string<?
                        (filter (lambda (name) (file-directory? (string-append fixtures "/" name)))
                                (directory-list fixtures))))))

(test-equal "program: a floors file and a README both missing are both named, the floors file first"
  (list 'returned
        (refused 3 (cannot-read (at "nothing" "floors.sexp")) (cannot-read (at "nothing" "README.org"))
                 (cannot-list (at "nothing" "workflows") "no such file or directory")))
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

(test-equal "the checked-in README and ci.yml hold the checked-in floors"
  '(returned ())
  (outcome (lambda ()
             (check-floors floors-path (file-text floors-path)
                           "README.org" (file-text "README.org")
                           ".github/workflows"
                           (list (list ".github/workflows/ci.yml"
                                       (file-text ".github/workflows/ci.yml")))))))

;; --- the CI scripts ------------------------------------------------------------------
;;
;; scripts/ci/floor.sh finds packaging/floors.sexp from its own place, two
;; directories up. So each floor.sh row runs a copy of the real script in a
;; fresh tree whose packaging/floors.sexp is the row's own, made in a
;; directory of the call's own: two runs of this suite at once share no file.
;; The rows run the script with sh, not by its own name, so a lost execute bit
;; is not what they find.

;; write-file : String String -> Unit
;; TEXT as the whole of the file at PATH, as UTF-8. The directory is there.
(define (write-file path text)
  (call-with-port (open-file-output-port path (file-options no-fail) (buffer-mode block)
                                         (make-transcoder (utf-8-codec)))
    (lambda (port) (put-string port text))))

;; checked : String (Listof String) -> Unit
;; Runs ARGV, which sets a row up and must exit 0 and print nothing.
(define (checked what argv)
  (let ((answer (capture-command argv)))
    (unless (equal? answer (list 0 "" ""))
      (error 'checked what answer))))

;; write-file-in : String String String -> Unit
;; TEXT as the file at DIR/NAME, with the directories above it made.
(define (write-file-in dir name text)
  (let* ((path (string-append dir "/" name))
         (slash (let loop ((i (- (string-length path) 1)))
                  (if (char=? (string-ref path i) #\/) i (loop (- i 1))))))
    (checked "mkdir" (list "mkdir" "-p" (substring path 0 slash)))
    (write-file path text)))

;; with-tree : (U String Symbol #f) ((String) -> Any) -> Any
;; PROC on ROOT, a fresh directory holding a copy of the real
;; scripts/ci/floor.sh and a packaging/floors.sexp with FLOORS-TEXT: none when
;; it is #f, and a directory of that name when it is the symbol directory.
(define (with-tree floors-text proc)
  (call-with-temp-directory
   (lambda (root)
     (checked "mkdir" (list "mkdir" "-p" (string-append root "/scripts/ci")
                            (string-append root "/packaging")))
     (checked "cp" (list "cp" "scripts/ci/floor.sh" (string-append root "/scripts/ci/floor.sh")))
     (cond ((string? floors-text)
            (write-file (string-append root "/packaging/floors.sexp") floors-text))
           ((eq? floors-text 'directory)
            (checked "mkdir" (list "mkdir" (string-append root "/packaging/floors.sexp")))))
     (proc root))))

;; --- floor.sh ------------------------------------------------------------------------

;; floor-sh-row : String (U String Symbol #f) (Listof String) Expected -> Unit
;; sh scripts/ci/floor.sh ARGS, in a tree whose floors file is FLOORS-TEXT,
;; must answer EXPECTED: its exit status, whole stdout and whole stderr.
(define (floor-sh-row name floors-text args expected)
  (test-equal (string-append "floor.sh: " name)
    (list 'returned expected)
    (outcome (lambda ()
               (with-tree floors-text
                 (lambda (root)
                   (capture-command (append (list "sh" (string-append root "/scripts/ci/floor.sh"))
                                            args))))))))

;; refused-floor : String ... -> (List 1 "" String)
(define (refused-floor . words)
  (list 1 "" (string-append "floor.sh: packaging/floors.sexp: " (apply string-append words) "\n")))

(define floor-usage (list 2 "" "usage: floor.sh chez|sqlite\n"))

(define not-one-list "it is not one list of (key \"version\") entries")

(floor-sh-row "the Chez floor" good '("chez") (list 0 "10.9.1\n" ""))
(floor-sh-row "the SQLite floor" good '("sqlite") (list 0 "8.1.2\n" ""))

(floor-sh-row "zero is a natural, and so is a number of several digits"
  (floors-of "\"0.0.0\"" "\"10.0.10\"") '("sqlite") (list 0 "10.0.10\n" ""))

(floor-sh-row "a comment above, an entry's own line and after the datum holds an entry of the same name: it is no entry"
  (string-append ";; the old (sqlite \"7.0.0\")\n"
                 "((chez \"10.9.1\") ; and (sqlite \"7.1.0\")\n"
                 " (sqlite \"8.1.2\"))\n"
                 ";; (sqlite \"7.2.0\")\n")
  '("sqlite") (list 0 "8.1.2\n" ""))

(floor-sh-row "a # inside a comment is no # outside one"
  (string-append ";; #; and #| are only words here\n" good)
  '("chez") (list 0 "10.9.1\n" ""))

(floor-sh-row "the datum spread over lines, with spaces inside it"
  "(\n  ( chez   \"10.9.1\" )\n\n(sqlite \"8.1.2\"))"
  '("sqlite") (list 0 "8.1.2\n" ""))

(floor-sh-row "no floors file" #f '("chez") (refused-floor "it cannot be read"))
(floor-sh-row "a floors file that is a directory" 'directory '("chez") (refused-floor "it cannot be read"))
(floor-sh-row "an empty file" "" '("chez") (refused-floor not-one-list))
(floor-sh-row "a file of comments only" ";; nothing here\n" '("chez") (refused-floor not-one-list))

(floor-sh-row "the key is missing"
  "((chez \"10.9.1\"))" '("sqlite")
  (refused-floor "it holds no sqlite entry"))

(floor-sh-row "the other key is missing"
  "((sqlite \"8.1.2\"))" '("chez")
  (refused-floor "it holds no chez entry"))

(floor-sh-row "the key twice"
  "((chez \"10.9.1\") (chez \"10.9.2\") (sqlite \"8.1.2\"))" '("chez")
  (refused-floor "it holds more than one chez entry"))

(floor-sh-row "the key twice, the other floor once"
  "((chez \"10.9.1\") (sqlite \"8.1.2\") (sqlite \"8.1.3\"))" '("sqlite")
  (refused-floor "it holds more than one sqlite entry"))

(floor-sh-row "the other floor is well-formed, and the one asked for is not"
  (floors-of good-chez "\"8.1\"") '("sqlite")
  (refused-floor "the sqlite version \"8.1\" is not three dot-separated naturals, major.minor.patch"))

(floor-sh-row "another floor's malformed version is not this floor's problem: check-floors names it"
  (floors-of good-chez "\"8.1\"") '("chez")
  (list 0 "10.9.1\n" ""))

(floor-sh-row "a version of two parts"
  (floors-of "\"10.9\"" good-sqlite) '("chez")
  (refused-floor "the chez version \"10.9\" is not three dot-separated naturals, major.minor.patch"))

(floor-sh-row "a version with a leading zero"
  (floors-of good-chez "\"08.1.2\"") '("sqlite")
  (refused-floor "the sqlite version \"08.1.2\" is not three dot-separated naturals, major.minor.patch"))

(floor-sh-row "a version with a leading zero in its last part"
  (floors-of "\"10.9.01\"" good-sqlite) '("chez")
  (refused-floor "the chez version \"10.9.01\" is not three dot-separated naturals, major.minor.patch"))

(floor-sh-row "a version with a plus sign"
  (floors-of "\"+10.9.1\"" good-sqlite) '("chez")
  (refused-floor "the chez version \"+10.9.1\" is not three dot-separated naturals, major.minor.patch"))

(floor-sh-row "a version with a minus sign"
  (floors-of good-chez "\"8.-1.2\"") '("sqlite")
  (refused-floor "the sqlite version \"8.-1.2\" is not three dot-separated naturals, major.minor.patch"))

(floor-sh-row "a version with four numbers"
  (floors-of "\"10.9.1.1\"" good-sqlite) '("chez")
  (refused-floor "the chez version \"10.9.1.1\" is not three dot-separated naturals, major.minor.patch"))

(floor-sh-row "a version with a letter"
  (floors-of good-chez "\"8.1.x\"") '("sqlite")
  (refused-floor "the sqlite version \"8.1.x\" is not three dot-separated naturals, major.minor.patch"))

(floor-sh-row "an empty version"
  (floors-of good-chez "\"\"") '("sqlite")
  (refused-floor "the sqlite version \"\" is not three dot-separated naturals, major.minor.patch"))

(floor-sh-row "a version that is a symbol, not a string"
  "((chez 10.9.1) (sqlite \"8.1.2\"))" '("sqlite")
  (refused-floor not-one-list))

(floor-sh-row "a key in capitals"
  "((Chez \"10.9.1\") (sqlite \"8.1.2\"))" '("sqlite")
  (refused-floor not-one-list))

(floor-sh-row "an entry of three elements"
  "((chez \"10.9.1\" \"x\") (sqlite \"8.1.2\"))" '("sqlite")
  (refused-floor not-one-list))

(floor-sh-row "a second datum"
  (string-append good good) '("chez")
  (refused-floor not-one-list))

(floor-sh-row "text after the datum"
  (string-append good "(more)\n") '("chez")
  (refused-floor not-one-list))

(floor-sh-row "a datum comment, which the Scheme reader skips and this script does not read"
  (string-append "#;(chez \"9.5.8\")\n" good) '("chez")
  (refused-floor "it holds a # outside a ; comment, which this script does not read"))

(floor-sh-row "a block comment"
  (string-append "#| (chez \"9.5.8\") |#\n" good) '("chez")
  (refused-floor "it holds a # outside a ; comment, which this script does not read"))

(floor-sh-row "a # after the datum, on the line of an entry"
  "((chez \"10.9.1\") #;(sqlite \"1.0.0\") (sqlite \"8.1.2\"))" '("sqlite")
  (refused-floor "it holds a # outside a ; comment, which this script does not read"))

(floor-sh-row "no name: the usage" good '() floor-usage)
(floor-sh-row "a name that is no floor: the usage" good '("python") floor-usage)
(floor-sh-row "a name that is no floor, with no floors file: the usage, not the file's problem"
  #f '("python") floor-usage)
(floor-sh-row "two names: the usage" good '("chez" "sqlite") floor-usage)

;; --- check-chez.sh ---------------------------------------------------------------------
;;
;; scripts/ci/check-chez.sh PREFIX asks PREFIX/bin/scheme for its version and
;; (threaded?), against the Chez floor floor.sh reads two directories above
;; it. The rows run copies of both scripts in a fresh tree whose floors file
;; names the Chez this suite runs on, or one patch above it, so they hold on
;; any threaded Chez, the floor or above. The Chez is the one CHEZ names,
;; found through the shell as make test runs it: its directory's parent is
;; the prefix, and its name must be scheme, as check-chez.sh asks.

;; this-chez : (List Natural Natural Natural)
(define this-chez
  (call-with-values scheme-version-number list))

;; dotted : (Listof Natural) -> String
(define (dotted ns)
  (let loop ((rest (cdr ns)) (text (number->string (car ns))))
    (if (null? rest) text (loop (cdr rest) (string-append text "." (number->string (car rest)))))))

;; answer : (Listof Natural) String -> String
(define (answer ns threads)
  (string-append "(" (number->string (car ns)) " " (number->string (cadr ns)) " "
                 (number->string (caddr ns)) " " threads ")"))

;; chez-prefix : (U String #f)
;; The prefix of the Chez CHEZ names, or #f when that is not .../bin/scheme.
(define chez-prefix
  (guard (e (#t #f))
    (let* ((found (capture-command (list "sh" "-c" "command -v \"$CHEZ\"")))
           (path (cadr found))
           (path (if (and (> (string-length path) 0)
                          (char=? (string-ref path (- (string-length path) 1)) #\newline))
                     (substring path 0 (- (string-length path) 1))
                     path))
           (tail "/bin/scheme")
           (n (string-length path)) (m (string-length tail)))
      (and (eqv? (car found) 0)
           (> n m)
           (string=? (substring path (- n m) n) tail)
           (substring path 0 (- n m))))))

(test-assert "check-chez.sh: CHEZ names a Chez at PREFIX/bin/scheme, which the rows below run"
  (string? chez-prefix))

;; check-chez-row : String (Listof Natural) (String -> (Listof String)) (String -> Expected) -> Unit
;; In a tree whose Chez floor is FLOOR, sh scripts/ci/check-chez.sh with the
;; arguments ARGS-OF gives, from the tree's root, must answer what EXPECTED-OF
;; gives: its exit status, whole stdout and whole stderr.
(define (check-chez-row name floor args-of expected-of)
  (test-equal (string-append "check-chez.sh: " name)
    '(returned same)
    (outcome
     (lambda ()
       (with-tree (floors-of (string-append "\"" (dotted floor) "\"") good-sqlite)
         (lambda (root)
           (checked "cp" (list "cp" "scripts/ci/check-chez.sh"
                               (string-append root "/scripts/ci/check-chez.sh")))
           (let ((got (capture-command (append (list "sh" (string-append root "/scripts/ci/check-chez.sh"))
                                               (args-of root))))
                 (want (expected-of root)))
             (if (equal? got want) 'same (list 'got got 'want want)))))))))

(define (scheme-at prefix) (string-append prefix "/bin/scheme"))

(define next-patch (list (car this-chez) (cadr this-chez) (+ 1 (caddr this-chez))))

(define chez-usage (lambda (root) (list 2 "" "usage: check-chez.sh PREFIX [--nothreads]\n")))

(check-chez-row "the Chez at the floor, threaded, passes, with its one line" this-chez
  (lambda (root) (list chez-prefix))
  (lambda (root)
    (list 0 (string-append "check-chez.sh: " (scheme-at chez-prefix) " is Chez " (dotted this-chez)
                           ", threaded: " (answer this-chez "yes") "\n")
          "")))

(check-chez-row "a threaded Chez asked for --nothreads fails, naming both answers" this-chez
  (lambda (root) (list chez-prefix "--nothreads"))
  (lambda (root)
    (list 1 "" (string-append "check-chez.sh: " (scheme-at chez-prefix) " answers " (answer this-chez "yes")
                              ", but (scheme-version-number) and (threaded?) should answer "
                              (answer this-chez "no") "\n"))))

(check-chez-row "a Chez one patch below the floor fails, naming both answers" next-patch
  (lambda (root) (list chez-prefix))
  (lambda (root)
    (list 1 "" (string-append "check-chez.sh: " (scheme-at chez-prefix) " answers " (answer this-chez "yes")
                              ", but (scheme-version-number) and (threaded?) should answer "
                              (answer next-patch "yes") "\n"))))

(check-chez-row "a prefix with no bin/scheme fails, naming the path" this-chez
  (lambda (root) (list (string-append root "/nowhere")))
  (lambda (root)
    (list 1 "" (string-append "check-chez.sh: " root "/nowhere/bin/scheme is not an executable file\n"))))

(check-chez-row "no prefix is a usage error" this-chez (lambda (root) '()) chez-usage)
(check-chez-row "a second argument but --nothreads is a usage error" this-chez
  (lambda (root) (list chez-prefix "--threads")) chez-usage)
(check-chez-row "three arguments are a usage error" this-chez
  (lambda (root) (list chez-prefix "--nothreads" "x")) chez-usage)

;; --- check-action-pins.sh ------------------------------------------------------------

(define pin-sha "3d3c42e5aac5ba805825da76410c181273ba90b1")

;; pinned : String String -> String
;; A canonical step line for ACTION, at TAG.
(define (pinned action tag) (string-append "      - uses: " action "@" pin-sha " # " tag))

;; steps : String ... -> String
;; A workflow whose first job's steps are LINES. Its first is line 4.
(define (steps . lines) (apply workflow "jobs:" "  main:" "    steps:" lines))

(define the-pinned (pinned "actions/checkout" "v7.0.1"))

;; pin-row : String (Listof (Pair String String)) (String -> (List Integer String String)) -> Unit
;; check-action-pins.sh on a fresh directory holding FILES, a name and its
;; text, answers what EXPECTED-OF gives for the directory's path.
(define (pin-row name files expected-of)
  (test-equal (string-append "pins: " name)
    '(returned same)
    (outcome
     (lambda ()
       (call-with-temp-directory
        (lambda (dir)
          (for-each (lambda (file) (write-file-in dir (car file) (cdr file))) files)
          (let ((got (capture-command (list "sh" "scripts/ci/check-action-pins.sh" dir)))
                (want (expected-of dir)))
            (if (equal? got want) 'same (list 'got got 'want want)))))))))

(define (pins-pass n)
  (lambda (dir)
    (list 0
          (string-append "check-action-pins: all " (number->string n) " lines with a uses key under "
                         dir " name a full commit SHA, with its tag in a comment\n")
          "")))

;; pins-fail : Natural Natural (Pair String (Pair Natural String)) ... -> (String -> Answer)
;; BAD is each line at fault, as its file, number and text; BAD-COUNT and
;; TOTAL are given, not counted.
(define (pins-fail bad-count total . bad)
  (lambda (dir)
    (list 1 ""
          (string-append
           (apply string-append
                  (map (lambda (b)
                         (string-append "check-action-pins: " dir "/" (car b) ":"
                                        (number->string (cadr b)) ":" (cddr b) "\n"))
                       bad))
           "check-action-pins: " (number->string bad-count) " of " (number->string total)
           " lines with a uses key are not \"uses: OWNER/REPO@<40 hex digits> # vTAG\", after an optional \"- \"\n"))))

(define (pins-error text)
  (lambda (dir) (list 1 "" (string-append "check-action-pins: " (text dir) "\n"))))

(pin-row "canonical lines: a step's first key, a later key, a path action and a reusable workflow"
         (list (cons "ci.yml"
                     (steps the-pinned
                            (string-append "        uses: actions/cache/restore@" pin-sha " # v6.1.0")
                            (string-append "    uses: owner/repo/.github/workflows/x.yml@" pin-sha " # v1"))))
         (pins-pass 3))

(pin-row "a comment, a value and a word that only end in uses are no uses key"
         (list (cons "ci.yml"
                     (steps the-pinned
                            "      # uses: actions/checkout@v4"
                            "      - name: Report the versions this run uses"
                            "      - run: echo reuses: x")))
         (pins-pass 1))

;; bad-line : String String -> Unit
;; A workflow with the canonical line and then LINE, which is line 5.
(define (bad-line name line)
  (pin-row name
           (list (cons "ci.yml" (steps the-pinned line)))
           (pins-fail 1 2 (cons "ci.yml" (cons 5 line)))))

(bad-line "a tag" "      - uses: actions/checkout@v4")
(bad-line "a branch" "      - uses: actions/checkout@main")
(bad-line "a short commit" "      - uses: actions/checkout@3d3c42e # v7.0.1")
(bad-line "a commit with no tag comment" (string-append "      - uses: actions/checkout@" pin-sha))
(bad-line "a comment that is no tag" (string-append "      - uses: actions/checkout@" pin-sha " # latest"))
(bad-line "more after the tag" (string-append "      - uses: actions/checkout@" pin-sha " # v7.0.1 and more"))
(bad-line "a uses key after other text on the line, in a trailing comment: it fails closed"
          (string-append "      - name: checkout # uses: actions/checkout@" pin-sha " # v7.0.1"))
(bad-line "a local action" "      - uses: ./.github/actions/setup")
(bad-line "a docker image" "      - uses: docker://alpine:3.20")
(bad-line "a quoted value" (string-append "      - uses: \"actions/checkout@" pin-sha "\" # v7.0.1"))
(bad-line "a flow mapping, though its commit is pinned"
          (string-append "      - {uses: actions/checkout@" pin-sha ", with: {submodules: true}} # v7.0.1"))
(bad-line "a flow mapping on a tag" "      - {uses: actions/checkout@v4, with: {submodules: true}}")
(bad-line "a flow sequence of mappings" "    steps: [{uses: actions/checkout@v4}]")
(bad-line "a later key of a flow mapping, after a comma" "      - {name: x,uses: actions/checkout@v4}")
(bad-line "a double-quoted key" "      - \"uses\": actions/checkout@v4")
(bad-line "a double-quoted key, though its commit is pinned"
          (string-append "      - \"uses\": actions/checkout@" pin-sha " # v7.0.1"))
(bad-line "a single-quoted key" "      - 'uses': actions/checkout@v4")
(bad-line "a space before the colon" "      - uses : actions/checkout@v4")
(bad-line "a space before the colon, though its commit is pinned"
          (string-append "      - uses : actions/checkout@" pin-sha " # v7.0.1"))
(bad-line "a key in a nested sequence" (string-append "      - - uses: actions/checkout@" pin-sha " # v7.0.1"))
(bad-line "a key with its value on the next line" "      - uses:")

(pin-row "every file is read, subdirectories too, and each line at fault is named by its own file, in path order"
         (list (cons "ci.yml" (steps the-pinned "      - uses: actions/checkout@v4"))
               (cons "sub/b.yml" (steps "      - uses: actions/cache@abc # v6" the-pinned)))
         (pins-fail 2 4
                    (cons "ci.yml" (cons 5 "      - uses: actions/checkout@v4"))
                    (cons "sub/b.yml" (cons 4 "      - uses: actions/cache@abc # v6"))))

(pin-row "a directory with no file: nothing was checked"
         '() (pins-error (lambda (dir) (string-append dir " holds no file"))))

;; A file grep cannot read, here a link to nothing, fails the check, naming
;; it, after a file it could read: a file it cannot read is never skipped.
;; grep's own line comes first, as GNU grep writes it, on the container and
;; on CI's runner.
(test-equal "pins: a file that cannot be read, a link to nothing after a pinned ci.yml, is named"
  '(returned same)
  (outcome
   (lambda ()
     (call-with-temp-directory
      (lambda (dir)
        (write-file-in dir "ci.yml" (steps the-pinned))
        (let* ((linked (capture-command (list "ln" "-s" "nothing-here" (string-append dir "/x.yml"))))
               (got (capture-command (list "sh" "scripts/ci/check-action-pins.sh" dir)))
               (want (list 1 "" (string-append "grep: " dir "/x.yml: No such file or directory\n"
                                               "check-action-pins: " dir "/x.yml cannot be read\n"))))
          (cond ((not (equal? linked '(0 "" ""))) (list 'ln linked))
                ((equal? got want) 'same)
                (else (list 'got got 'want want)))))))))

(pin-row "no file has a uses key: nothing was checked"
         (list (cons "ci.yml" (workflow "name: CI" "on: push")))
         (pins-error (lambda (dir)
                       (string-append "no file under " dir " has a line with a uses key, so nothing was checked"))))

(pin-row "a uses key only in a comment: nothing was checked"
         (list (cons "ci.yml" (workflow "# uses: actions/checkout@v4")))
         (pins-error (lambda (dir)
                       (string-append "no file under " dir " has a line with a uses key, so nothing was checked"))))

(test-equal "pins: a path that is no directory"
  '(returned same)
  (outcome
   (lambda ()
     (call-with-temp-directory
      (lambda (dir)
        (let ((got (capture-command (list "sh" "scripts/ci/check-action-pins.sh" (string-append dir "/none"))))
              (want (list 1 "" (string-append "check-action-pins: " dir "/none is not a directory\n"))))
          (if (equal? got want) 'same (list 'got got 'want want))))))))

(test-equal "pins: a file named as the directory is no directory"
  '(returned same)
  (outcome
   (lambda ()
     (call-with-temp-directory
      (lambda (dir)
        (write-file-in dir "ci.yml" (steps the-pinned))
        (let ((got (capture-command (list "sh" "scripts/ci/check-action-pins.sh" (string-append dir "/ci.yml"))))
              (want (list 1 "" (string-append "check-action-pins: " dir "/ci.yml is not a directory\n"))))
          (if (equal? got want) 'same (list 'got got 'want want))))))))

(test-equal "pins: no directory named: the usage"
  '(returned (2 "" "usage: check-action-pins.sh DIR\n"))
  (outcome (lambda () (capture-command (list "sh" "scripts/ci/check-action-pins.sh")))))

(test-equal "pins: two directories named: the usage"
  '(returned (2 "" "usage: check-action-pins.sh DIR\n"))
  (outcome (lambda () (capture-command (list "sh" "scripts/ci/check-action-pins.sh" "a" "b")))))

(test-end "check-floors")

(exit (suite-exit-status runner))
