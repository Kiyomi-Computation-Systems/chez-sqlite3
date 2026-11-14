#!r6rs
;;; The suite for tests/check-seam.sps, the program behind `make check-seam`
;;; (ADR-0009, amended). Every rule it holds has a fixture tree under
;;; tests/fixtures/seam/<case>/, or a tree this suite writes into a temporary
;;; directory, and this suite runs the program on each, in a fresh Chez,
;;; through capture-command. A case asserts the exit status, the whole of
;;; stdout and the whole of stderr, as text written by hand here, never read
;;; back from the program: a substring would pass whenever another rule
;;; produced the same words. Without this suite, deleting a rule would leave
;;; `make test` green: the real tree under src/ breaks none of them.
;;;
;;; Each case's tree is the one fault it names, in an otherwise legal setting,
;;; so that only that rule can make it fail. `legal` and the lock-file cases
;;; that must pass say so with the program's own pass line, counts included.
;;; The fixture trees are never suites: make test runs tests/test-*.sps only,
;;; which check-suites reads.
;;;
;;; Two programs run. The real one holds the real tables, in which only the
;;; names src/ imports today are allowed. The variant is the real program with
;;; allowed-chez-names widened by every name in library-only-chez-names, the
;;; state the tables reach when (chez-sqlite3 private memory) and (chez-sqlite3
;;; private native) land and import them: the rules about those names, (f) and
;;; (k) among them, cannot be reached through the real table until then. The
;;; variant is the program's own text, read as data, with that one definition
;;; replaced.
;;;
;;; The two allowlists are held against their whole complements: every name
;;; (chezscheme) exports that is not allowed, and every library this Chez has
;;; that is not allowed, are each refused in one run, whole output.
;;;
;;; make test runs every suite from the repository root, where tests/ and src/
;;; are, with CHEZ exported. Without CHEZ nothing below can run: that fails
;;; here, by name, and never skips.
(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
        (only (chezscheme) getenv directory-list file-directory? library-list
              environment environment-symbols mkdir list-head))

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

(define program "tests/check-seam.sps")

(define fixtures "tests/fixtures/seam")

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; joined : String (Listof String) -> String
(define (joined separator strings)
  (if (null? strings)
      ""
      (fold-left (lambda (text s) (string-append text separator s)) (car strings) (cdr strings))))

;; --- the tables, written out whole ---------------------------------------------------------
;; Held against the program's own below, and the source of every expectation that
;; depends on them: never read back from the program.

;; table-allowed : (Listof Symbol)
;; The names src/ imports from (chezscheme) today: counters', and require-threaded's.
(define table-allowed
  '(critical-section make-mutex scheme-version scheme-version-number threaded? with-mutex))

;; table-only : (Listof (Pair Symbol (Listof (Listof Symbol))))
;; The library-only entries. Neither library exists yet; the entries record the layout.
(define table-only
  '((foreign-alloc (chez-sqlite3 private memory))
    (foreign-free (chez-sqlite3 private memory))
    (load-shared-object (chez-sqlite3 private native))
    (foreign-procedure (chez-sqlite3 private native))
    (foreign-entry (chez-sqlite3 private native))
    (foreign-entry? (chez-sqlite3 private native))
    (foreign-ref (chez-sqlite3 private native))
    (foreign-set! (chez-sqlite3 private native))
    (getenv (chez-sqlite3 private native))
    (machine-type (chez-sqlite3 private native))))

;; --- running a program --------------------------------------------------------------

;; read-forms : String -> (Listof Any)
(define (read-forms path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                        (make-transcoder (utf-8-codec)))
    (lambda (port)
      (let loop ((found '()))
        (let ((datum (read port)))
          (if (eof-object? datum) (reverse found) (loop (cons datum found))))))))

;; declared : Symbol -> Any
;; What the program's (define NAME '(...)) lists.
(define (declared name)
  (guard (e (#t (list 'unreadable (describe e))))
    (let ((form (find (lambda (form)
                        (and (pair? form) (eq? (car form) 'define)
                             (pair? (cdr form)) (eq? (cadr form) name)))
                      (read-forms program))))
      (if form (cadr (caddr form)) '(not-defined)))))

(define declared-names (declared 'allowed-chez-names))

(define declared-library-only (declared 'library-only-chez-names))

;; variant-text : -> String
;; The program, with allowed-chez-names holding also every name in library-only-chez-names.
(define (variant-text)
  (let ((widened (append declared-names (map car declared-library-only))))
    (string-append
     "#!r6rs\n"
     (apply string-append
            (map (lambda (form)
                   (string-append
                    (written (if (and (pair? form) (eq? (car form) 'define)
                                      (pair? (cdr form)) (eq? (cadr form) 'allowed-chez-names))
                                 (list 'define 'allowed-chez-names (list 'quote widened))
                                 form))
                    "\n"))
                 (read-forms program))))))

(define variant-directory (make-process-temp-directory))

(define variant-program (string-append variant-directory "/check-seam-variant.sps"))

;; ensure-directory! : String -> Unit
;; PATH and each directory above it that is missing, below the first that exists.
(define (ensure-directory! path)
  (unless (file-directory? path)
    (let loop ((i (- (string-length path) 1)))
      (cond ((<= i 0) #f)
            ((char=? (string-ref path i) #\/)
             (ensure-directory! (substring path 0 i)))
            (else (loop (- i 1)))))
    (mkdir path #o700)))

;; dir-of : String -> String
(define (dir-of path)
  (let loop ((i (- (string-length path) 1)))
    (if (char=? (string-ref path i) #\/) (substring path 0 i) (loop (- i 1)))))

;; put-file! : String String -> Unit
(define (put-file! path text)
  (ensure-directory! (dir-of path))
  (call-with-output-file path (lambda (port) (put-string port text))))

(guard (e (#t #f))
  (put-file! variant-program (variant-text)))

;; run-program : String (Listof String) -> (U (List Integer String String) (List 'raised String))
;; PROGRAM-PATH in a fresh Chez with ARGS: its exit status, stdout and stderr.
(define (run-program program-path args)
  (guard (e (#t (list 'raised (describe e))))
    (capture-command (append (list chez "--program" program-path) args))))

;; run : (Listof String) -> (List Integer String String)
(define (run args) (run-program program args))

;; --- the words the lines are made of, written by hand ----------------------------------------

;; at : String String -> String
;; The path check-seam names for FILE in the fixture tree CASE.
(define (at case file) (string-append fixtures "/" case "/" file))

;; holds : Natural Natural -> (List 0 String "")
;; What a pass prints: the libraries read, in how many files.
(define (holds libraries files)
  (list 0
        (string-append "check-seam: the seam holds (" (number->string libraries)
                       " libraries in " (number->string files) " files checked)\n")
        ""))

;; refused : Natural String ... -> (List 1 "" String)
;; What a failure prints: PROBLEMS, one line each, then the count. COUNT is
;; given, not counted, so a miscount in the program is not copied here.
(define (refused count . problems)
  (refused-list count problems))

(define (refused-list count problems)
  (list 1
        ""
        (string-append
         (apply string-append
                (map (lambda (p) (string-append "check-seam: " p "\n")) problems))
         "check-seam: FAILED (problems: " (number->string count) ")\n")))

(define chez-only
  "but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)")

(define (not-listed name)
  (string-append "imports " name " from (chezscheme), but allowed-chez-names in"
                 " tests/check-seam.sps does not list it"))

;; library-only : String String -> String
(define (library-only name where)
  (string-append "imports " name " from (chezscheme), but library-only-chez-names in"
                 " tests/check-seam.sps allows it only in " where))

;; re-exports : String String -> String
(define (re-exports what name)
  (string-append "exports " what ", but it imports " name " from (chezscheme), and no"
                 " library under src/ may export a name it imports from (chezscheme)"))

;; macro-export : String (Listof String) -> String
;; Rule (k): WHAT is the name, or the internal name and " as " the external one.
(define (macro-export what imports)
  (string-append "exports " what ", a macro it binds with define-syntax, but it imports "
                 (joined ", " imports)
                 " from (chezscheme), which only some libraries may import: the macro could"
                 " hand them on to a library that may not"))

(define unlisted-tail
  (string-append "but a library under src/ may import only the (rnrs ...) libraries"
                 " except (rnrs eval), (only (chezscheme) name ...), and (chez-sqlite3 ...)"
                 " libraries"))

(define undefined-tail
  (string-append ", but no library under src/ defines it, so Chez would load it from"
                 " elsewhere on its library path, which this check does not read"))

(define not-read-tail
  ", and this check does not read one; rename it or keep it out of src/")

(define (unread ending)
  (string-append "Chez could load a library from a file ending in " ending not-read-tail))

;; outside : String String -> String
;; Rule (d), the boundary: the library NAME, written, is outside the family.
(define (outside name)
  (string-append (string-append name " is outside the family: a library under src/ must be")
                 " (chez-sqlite3) or (chez-sqlite3 private name ...)"))

;; holds-several : String String Natural -> String
;; Rule (i): the file FILE in the tree CASE holds COUNT libraries.
(define (holds-several case file count)
  (string-append (at case file) ": it holds " (number->string count)
                 " libraries, but Chez loads one library from a file, so each file under"
                 " src/ holds exactly one"))

;; off-path : String String String String -> String
(define (off-path case file name path)
  (string-append (at case file) ": " name " is defined here, but Chez loads it from "
                 (at case path) ", its name's path"))

;; no-such-file : String String -> String
(define (no-such-file case file)
  (string-append (at case file)
                 ": it cannot be read as data: Exception in open-file-input-port: failed for "
                 (at case file) ": no such file or directory"))

;; --- the fixture cases ---------------------------------------------------------------

;; P : String -> String
;; The path of FILE under chez-sqlite3/private/, in a fixture tree.
(define (p file) (string-append "chez-sqlite3/private/" file))

;; cases : (Listof (List String String Symbol Expected))
;; The case's name, its fixture directory, the program that runs it (real or
;; variant), and the program's whole answer.
(define cases
  (list
   (list "legal: the public library and private ones, wrappers over (rnrs ...) and (only (chezscheme) ...), a version reference, a nested library, notes.txt passed by"
         "legal" 'real (holds 4 4))

   (list "second-library: every library form in a file is checked, the second included; rule (i) names the file, and the second library, off its name's path"
         "second-library" 'real
         (refused 3
                  (string-append (at "second-library" (p "two-a.sls"))
                                 ": (chez-sqlite3 private two-b) imports (chezscheme), " chez-only)
                  (holds-several "second-library" (p "two-a.sls") 2)
                  (off-path "second-library" (p "two-a.sls") "(chez-sqlite3 private two-b)" (p "two-b.sls"))))
   (list "off-path: rule (i), a second library in a file, which an import elsewhere finds defined, and a library alone in a file named for another"
         "off-path" 'real
         (refused 3
                  (holds-several "off-path" (p "a.sls") 2)
                  (off-path "off-path" (p "a.sls") "(chez-sqlite3 private extra)" (p "extra.sls"))
                  (off-path "off-path" (p "b.sls") "(chez-sqlite3 private c)" (p "c.sls"))))
   (list "import-undefined: a family import, through prefix, and one in the public library, that no library in the tree defines; ones it defines pass"
         "import-undefined" 'real
         (refused 2
                  (string-append (at "import-undefined" "chez-sqlite3.sls")
                                 ": (chez-sqlite3) imports (chez-sqlite3 private w)" undefined-tail)
                  (string-append (at "import-undefined" (p "x.sls"))
                                 ": (chez-sqlite3 private x) imports (chez-sqlite3 private extra)" undefined-tail)))

   ;; --- rule (d): the boundary ---
   (list "outside-family: rule (d), eight libraries that are not (chez-sqlite3) nor (chez-sqlite3 private name ...): a plain name, a near name, a sibling's, the old family's, a second-level name, a near private, the bare private, private not second; the public and a private library pass"
         "outside-family" 'real
         (refused 8
                  (string-append (at "outside-family" "chez-sqlite3-testing.sls") ": " (outside "(chez-sqlite3-testing)"))
                  (string-append (at "outside-family" "chez-sqlite3/foo/private/x.sls") ": " (outside "(chez-sqlite3 foo private x)"))
                  (string-append (at "outside-family" "chez-sqlite3/private.sls") ": " (outside "(chez-sqlite3 private)"))
                  (string-append (at "outside-family" "chez-sqlite3/privateer/x.sls") ": " (outside "(chez-sqlite3 privateer x)"))
                  (string-append (at "outside-family" "chez-sqlite3/util.sls") ": " (outside "(chez-sqlite3 util)"))
                  (string-append (at "outside-family" "curl.sls") ": " (outside "(curl)"))
                  (string-append (at "outside-family" "sqlite3.sls") ": " (outside "(sqlite3)"))
                  (string-append (at "outside-family" "util.sls") ": " (outside "(util)"))))
   (list "outside-imports: a library outside the family that imports a private one is refused once, for being outside; a family library importing an undefined outside one (rule (h)), a defined outside one (passes (h); its definition is refused), and the test helpers (rule (e))"
         "outside-imports" 'real
         (refused 4
                  (string-append (at "outside-imports" (p "y1.sls"))
                                 ": (chez-sqlite3 private y1) imports (chez-sqlite3 util)" undefined-tail)
                  (string-append (at "outside-imports" (p "y3.sls"))
                                 ": (chez-sqlite3 private y3) imports (chez-sqlite3-testing), " unlisted-tail)
                  (string-append (at "outside-imports" "chez-sqlite3/util2.sls") ": " (outside "(chez-sqlite3 util2)"))
                  (string-append (at "outside-imports" "util.sls") ": " (outside "(util)"))))

   ;; --- rule (c): (chezscheme), (scheme) and (rnrs eval) ---
   (list "chez-whole: (chezscheme) imported whole"
         "chez-whole" 'real
         (refused 1 (string-append (at "chez-whole" (p "w.sls")) ": (chez-sqlite3 private w) imports (chezscheme), " chez-only)))
   (list "scheme-alias: (scheme), the alias, imported whole"
         "scheme-alias" 'real
         (refused 1 (string-append (at "scheme-alias" (p "s.sls")) ": (chez-sqlite3 private s) imports (scheme), " chez-only)))
   (list "chez-wrapped: (chezscheme) under except, prefix, rename, for, library, a nested only and (scheme)"
         "chez-wrapped" 'real
         (refused-list
          10
          (map (lambda (entry)
                 (string-append (at "chez-wrapped" (p (string-append "w" (car entry) ".sls")))
                                ": (chez-sqlite3 private w" (car entry) ") imports " (cdr entry) ", " chez-only))
               (list-sort (lambda (a b) (string<? (string-append "w" (car a) ".sls") (string-append "w" (car b) ".sls")))
                          '(("1" . "(except (chezscheme) car)")
                            ("2" . "(prefix (chezscheme) c:)")
                            ("3" . "(rename (chezscheme) (car kar))")
                            ("4" . "(for (chezscheme) expand)")
                            ("5" . "(library (chezscheme))")
                            ("6" . "(for (only (chezscheme) threaded?) expand)")
                            ("7" . "(only (prefix (chezscheme) c:) c:threaded?)")
                            ("8" . "(only (library (chezscheme)) threaded?)")
                            ("9" . "(only (scheme) threaded?)")
                            ("10" . "(only (only (chezscheme) threaded? car) threaded?)"))))))
   (list "name-import-only: a name outside allowed-chez-names: import-only, which opens an import in a body"
         "name-import-only" 'real
         (refused 1 (string-append (at "name-import-only" (p "a.sls")) ": (chez-sqlite3 private a) " (not-listed "import-only"))))
   (list "name-top-level-value: a name outside allowed-chez-names: top-level-value, which reaches eval"
         "name-top-level-value" 'real
         (refused 1 (string-append (at "name-top-level-value" (p "b.sls")) ": (chez-sqlite3 private b) " (not-listed "top-level-value"))))
   (list "name-primitive: a name outside allowed-chez-names: $primitive, which reaches eval"
         "name-primitive" 'real
         (refused 1 (string-append (at "name-primitive" (p "d.sls")) ": (chez-sqlite3 private d) " (not-listed "$primitive"))))
   (list "names-several: allowed and refused names mixed, including format, which chez-curl's list had: each name outside is named, in order"
         "names-several" 'real
         (refused 3
                  (string-append (at "names-several" (p "n.sls")) ": (chez-sqlite3 private n) " (not-listed "format"))
                  (string-append (at "names-several" (p "n.sls")) ": (chez-sqlite3 private n) " (not-listed "eval"))
                  (string-append (at "names-several" (p "n.sls")) ": (chez-sqlite3 private n) " (not-listed "$primitive"))))
   (list "names-denylisted: the names the old denylist held are outside the allowlist too"
         "names-denylisted" 'real
         (apply refused 12
                (map (lambda (name)
                       (string-append (at "names-denylisted" (p "n.sls")) ": (chez-sqlite3 private n) " (not-listed name)))
                     '("import" "include" "include-library-declarations" "eval" "environment"
                       "interaction-environment" "load" "load-library" "library-directories"
                       "interpret" "compile" "load-program"))))
   (list "names-not-symbols: an only over (chezscheme) with a name that is no identifier"
         "names-not-symbols" 'real
         (refused 1 (string-append (at "names-not-symbols" (p "n.sls"))
                                   ": (chez-sqlite3 private n) has an import it cannot read: (only (chezscheme) 42)")))
   (list "names-refused, real table: define-ftype, lock-object, foreign-callable, foreign-callable-entry-point and fork-thread, which no library may import, and condition-wait and mutex-acquire, in three libraries, memory and native among them"
         "names-refused" 'real
         (refused-list
          21
          (apply append
                 (map (lambda (lib)
                        (map (lambda (name)
                               (string-append (at "names-refused" (p (string-append lib ".sls")))
                                              ": (chez-sqlite3 private " lib ") " (not-listed name)))
                             '("define-ftype" "lock-object" "foreign-callable" "foreign-callable-entry-point"
                               "fork-thread" "condition-wait" "mutex-acquire")))
                      '("memory" "native" "other")))))
   (list "names-refused, variant table: the same names stay refused when every library-only name is allowed: no library, memory and native included, may import them"
         "names-refused" 'variant
         (refused-list
          21
          (apply append
                 (map (lambda (lib)
                        (map (lambda (name)
                               (string-append (at "names-refused" (p (string-append lib ".sls")))
                                              ": (chez-sqlite3 private " lib ") " (not-listed name)))
                             '("define-ftype" "lock-object" "foreign-callable" "foreign-callable-entry-point"
                               "fork-thread" "condition-wait" "mutex-acquire")))
                      '("memory" "native" "other")))))
   (list "rnrs-eval: (rnrs eval), plain and wrapped"
         "rnrs-eval" 'real
         (refused 2
                  (string-append (at "rnrs-eval" (p "e1.sls"))
                                 ": (chez-sqlite3 private e1) imports (rnrs eval), but no library under src/ may import (rnrs eval)")
                  (string-append (at "rnrs-eval" (p "e2.sls"))
                                 ": (chez-sqlite3 private e2) imports (rnrs eval), but no library under src/ may import (rnrs eval)")))

   ;; --- rule (f): names only some libraries may import ---
   (list "ftype-with-unlisted: rule (f) and rule (c) in one import set, each name outside its list named, in the order the import set holds them (variant)"
         "ftype-with-unlisted" 'variant
         (refused 3
                  (string-append (at "ftype-with-unlisted" (p "m.sls")) ": (chez-sqlite3 private m) "
                                 (library-only "foreign-alloc" "(chez-sqlite3 private memory)"))
                  (string-append (at "ftype-with-unlisted" (p "m.sls")) ": (chez-sqlite3 private m) " (not-listed "eval"))
                  (string-append (at "ftype-with-unlisted" (p "m.sls")) ": (chez-sqlite3 private m) " (not-listed "$primitive"))))
   (list "memory-native-listed: rule (f) passing: memory imports foreign-alloc and foreign-free, native its eight names, with make-mutex and with-mutex beside them (variant)"
         "memory-native-listed" 'variant (holds 3 3))

   ;; --- rule (g): no library exports a name it imports from (chezscheme) ---
   (list "export-chez: rule (g): a name imported from (chezscheme) exported, plain or as a rename spec's internal name, in the listed libraries too, each in export order; a name from (rnrs), a rename of a library's own definition to a (chezscheme) name, and a definition named like a (chezscheme) binding are not named (variant)"
         "export-chez" 'variant
         (refused 6
                  (string-append (at "export-chez" (p "h.sls")) ": (chez-sqlite3 private h) "
                                 (re-exports "critical-section" "critical-section"))
                  (string-append (at "export-chez" (p "memory.sls")) ": (chez-sqlite3 private memory) "
                                 (re-exports "foreign-alloc" "foreign-alloc"))
                  (string-append (at "export-chez" (p "native.sls")) ": (chez-sqlite3 private native) "
                                 (re-exports "foreign-procedure" "foreign-procedure"))
                  (string-append (at "export-chez" (p "native.sls")) ": (chez-sqlite3 private native) "
                                 (re-exports "foreign-ref as raw-ref" "foreign-ref"))
                  (string-append (at "export-chez" (p "r.sls")) ": (chez-sqlite3 private r) "
                                 (re-exports "with-mutex" "with-mutex"))
                  (string-append (at "export-chez" (p "r.sls")) ": (chez-sqlite3 private r) "
                                 (re-exports "make-mutex as mk" "make-mutex"))))
   (list "export-unreadable: rule (g) fails closed: each export spec that is neither an identifier nor (rename (internal external) ...) is named, in order, a cyclic one included"
         "export-unreadable" 'real
         (refused-list
          9
          (append
           (map (lambda (spec)
                  (string-append (at "export-unreadable" (p "x.sls")) ": (chez-sqlite3 private x) has an export it cannot read: " spec))
                '("42" "\"s\"" "(car)" "(foo car)" "(rename car kar)" "(rename (car))"
                  "(rename (car kar kaar))" "(rename (car 1))"))
           (list (string-append (at "export-unreadable" (p "y.sls"))
                                ": (chez-sqlite3 private y) has an export it cannot read: (rename #0=(a #0#))")))))
   (list "export-wrapped-chez: rule (g) and a wrapper over (only (chezscheme) ...): except, for, prefix and rename are each refused by rule (c), so none can rename a name imported from (chezscheme) unseen"
         "export-wrapped-chez" 'real
         (refused 4
                  (string-append (at "export-wrapped-chez" (p "e.sls"))
                                 ": (chez-sqlite3 private e) imports (except (only (chezscheme) threaded? with-mutex) with-mutex), " chez-only)
                  (string-append (at "export-wrapped-chez" (p "f.sls"))
                                 ": (chez-sqlite3 private f) imports (for (only (chezscheme) threaded?) run), " chez-only)
                  (string-append (at "export-wrapped-chez" (p "p.sls"))
                                 ": (chez-sqlite3 private p) imports (prefix (only (chezscheme) threaded?) c:), " chez-only)
                  (string-append (at "export-wrapped-chez" (p "r.sls"))
                                 ": (chez-sqlite3 private r) imports (rename (only (chezscheme) threaded?) (threaded? tt)), " chez-only)))

   ;; --- rule (k): macros ---
   (list "macro-export: rule (k): a library that imports library-only names exports macros it binds with define-syntax, plain, renamed, and inside begin, each in export order; its plain definition is not named (variant)"
         "macro-export" 'variant
         (refused 3
                  (string-append (at "macro-export" (p "native.sls")) ": (chez-sqlite3 private native) "
                                 (macro-export "call" '("foreign-procedure" "foreign-ref")))
                  (string-append (at "macro-export" (p "native.sls")) ": (chez-sqlite3 private native) "
                                 (macro-export "call2 as call-two" '("foreign-procedure" "foreign-ref")))
                  (string-append (at "macro-export" (p "native.sls")) ": (chez-sqlite3 private native) "
                                 (macro-export "call3" '("foreign-procedure" "foreign-ref")))))
   (list "macro-internal: rule (k) passing: an internal macro, a let-syntax, never exported, and a macro exported by a library that imports no library-only name (variant)"
         "macro-internal" 'variant (holds 3 3))

   ;; --- the import allowlist ---
   (list "unlisted-libraries: a library not on the import allowlist: a third-party one, (chezscheme csv7), ($system), (scheme csv7), the test helpers, a near-family name, an (rnrs ...) name R6RS lacks, the library's own name without its family"
         "unlisted-libraries" 'real
         (refused-list
          9
          (map (lambda (entry)
                 (string-append (at "unlisted-libraries" (p (string-append "u" (car entry) ".sls")))
                                ": (chez-sqlite3 private u" (car entry) ") imports " (cdr entry) ", " unlisted-tail))
               '(("1" . "(srfi :1)") ("2" . "(chezscheme csv7)") ("3" . "($system)") ("4" . "(scheme csv7)")
                 ("5" . "(chez-sqlite3-testing)") ("6" . "(chez-sqlite3-extras)") ("7" . "(rnrs foo)")
                 ("8" . "(sqlite3)") ("9" . "(srfi :64)")))))

   ;; --- files Chez could load that the program does not read ---
   (list "unread-ss: a .ss file, which Chez loads as a library and the program does not read"
         "unread-ss" 'real
         (refused 1 (string-append (at "unread-ss" (p "hidden.ss")) ": " (unread ".ss"))))
   (list "unread-so: a lone .so, with no source beside it, whatever it holds"
         "unread-so" 'real
         (refused 1 (string-append (at "unread-so" (p "lone.so")) ": " (unread ".so"))))
   (list "unread-extensions: every unread ending, each named for its longest: .ss .scm .sch .chezscheme.sls .so .chezscheme.so"
         "unread-extensions" 'real
         (refused 6
                  (string-append (at "unread-extensions" (p "a.ss")) ": " (unread ".ss"))
                  (string-append (at "unread-extensions" (p "b.scm")) ": " (unread ".scm"))
                  (string-append (at "unread-extensions" (p "c.sch")) ": " (unread ".sch"))
                  (string-append (at "unread-extensions" (p "d.chezscheme.sls")) ": " (unread ".chezscheme.sls"))
                  (string-append (at "unread-extensions" (p "e.so")) ": " (unread ".so"))
                  (string-append (at "unread-extensions" (p "f.chezscheme.so")) ": " (unread ".chezscheme.so"))))
   (list "dir-symlink: a symbolic link to a directory, which the program does not follow"
         "dir-symlink" 'real
         (refused 1 (string-append (at "dir-symlink" "linked")
                                   ": it is a symbolic link to a directory, which this check does not follow")))

   ;; --- Emacs lock files: .#name, a dangling symbolic link ---
   (list "lock-symlink: a .# dangling symbolic link, which is Emacs's lock file, is skipped"
         "lock-symlink" 'real (holds 1 1))
   (list "lock-regular: a .# regular file is no lock file: it is read and checked"
         "lock-regular" 'real
         (refused 1 (string-append (at "lock-regular" (p ".#g.sls"))
                                   ": (chez-sqlite3 private \\x2E;\\x23;g) imports (chezscheme), " chez-only)))
   (list "lock-directory: a .# directory is no lock file: it is walked"
         "lock-directory" 'real
         (refused 1 (string-append (at "lock-directory" (p ".#dir/bad.sls"))
                                   ": (chez-sqlite3 private \\x2E;\\x23;dir bad) imports (chezscheme), " chez-only)))
   (list "lock-symlink-live: a .# symbolic link that resolves to a library is no lock file: it is read, and named by rule (i), since the library it holds is not at its own name's path"
         "lock-symlink-live" 'real
         (refused 1 (off-path "lock-symlink-live" (p ".#real.sls") "(chez-sqlite3 private real)" (p "real.sls"))))
   (list "dangling-link: a dangling symbolic link not named .# is no lock file: it is named, for it cannot be read"
         "dangling-link" 'real
         (refused 1 (no-such-file "dangling-link" (p "dangling.sls"))))
   (list "dangling-dot-link: a dangling symbolic link named with a dot but not .# is no lock file"
         "dangling-dot-link" 'real
         (refused 1 (no-such-file "dangling-dot-link" (p ".dangling.sls"))))
   (list "dangling-hash-link: a dangling symbolic link with .# inside its name, not at its start, is no lock file"
         "dangling-hash-link" 'real
         (refused 1 (no-such-file "dangling-hash-link" (p "a.#b.sls"))))

   ;; --- fails closed ---
   (list "no-datum: a file that holds no datum"
         "no-datum" 'real
         (refused 1 (string-append (at "no-datum" "chez-sqlite3.sls") ": it holds no datum, so it holds no library form")))
   (list "not-a-library: a datum that is no library form, the first or a later one"
         "not-a-library" 'real
         (refused 2
                  (string-append (at "not-a-library" (p "d1.sls")) ": datum 1 is (define x 1), not a library form")
                  (string-append (at "not-a-library" (p "d2.sls")) ": datum 2 is (define y 2), not a library form")))
   (list "unreadable: a file that cannot be read as data"
         "unreadable" 'real
         (refused 1 (string-append (at "unreadable" (p "broken.sls"))
                                   ": it cannot be read as data: Exception in read: unexpected end-of-file reading list before file-position 64 of #<input port "
                                   (at "unreadable" (p "broken.sls"))
                                   ">; the character position might differ")))
   (list "eof-literal: a file with an #!eof literal, which would end the reading early"
         "eof-literal" 'real
         (refused 1 (string-append (at "eof-literal" (p "eof.sls"))
                                   ": it cannot be read as data: Exception in read: an #!eof literal ends the reading before the end of the file")))
   (list "cannot-read-import: an import it cannot read: a number, an empty list, a bare only, and a cyclic datum"
         "cannot-read-import" 'real
         (refused 4
                  (string-append (at "cannot-read-import" (p "m1.sls")) ": (chez-sqlite3 private m1) has an import it cannot read: 42")
                  (string-append (at "cannot-read-import" (p "m2.sls")) ": (chez-sqlite3 private m2) has an import it cannot read: ()")
                  (string-append (at "cannot-read-import" (p "m3.sls")) ": (chez-sqlite3 private m3) has an import it cannot read: (only)")
                  (string-append (at "cannot-read-import" (p "m4.sls")) ": (chez-sqlite3 private m4) has an import it cannot read: #0=(only #0# x)")))))

(test-begin "check-seam")

(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (and chez (not (string=? chez ""))) 'set 'unset))

(unless (and chez (not (string=? chez "")))
  (exit 1))

(test-equal "the variant program was written: it is the program, with allowed-chez-names widened"
  'written
  (if (file-exists? variant-program) 'written 'missing))

(for-each
 (lambda (case)
   (test-equal (car case)
     (cadddr case)
     (run-program (if (eq? (caddr case) 'variant) variant-program program)
                  (list (string-append fixtures "/" (cadr case))))))
 cases)

;; A fixture nothing runs guards nothing, and a case with no fixture runs on a
;; missing directory.
(test-equal "every fixture directory is a case above, and every case has its directory"
  (list-sort string<? (let loop ((names (map cadr cases)) (found '()))
                        (cond ((null? names) found)
                              ((member (car names) found) (loop (cdr names) found))
                              (else (loop (cdr names) (cons (car names) found))))))
  (list-sort string<?
             (filter (lambda (name) (file-directory? (string-append fixtures "/" name)))
                     (directory-list fixtures))))

;; --- the lists the program holds are exact ------------------------------------------------
;; allowed-chez-names is exactly the names src/ imports from (chezscheme): a name in it
;; that no library uses is a permission nobody exercises, and a name a library uses that
;; is not in it fails check-seam. A library-only name enters allowed-chez-names when its
;; library lands and imports it, and not before: until then its entry names a library
;; that does not exist, which is legal. So each entry's name is either allowed or imported
;; by no library under src/, and no library under src/ imports it that the entry does not
;; list. Each list is read from the program as data, never from its output.

;; sls-files : String -> (Listof String)
(define (sls-files dir)
  (apply append
         (map (lambda (name)
                (let ((path (string-append dir "/" name)))
                  (cond ((file-directory? path) (sls-files path))
                        ((and (> (string-length name) 4)
                              (string=? (substring name (- (string-length name) 4)
                                                   (string-length name))
                                        ".sls"))
                         (list path))
                        (else '()))))
              (directory-list dir))))

;; chez-imports : -> (Listof (Pair (Listof Symbol) (Listof Symbol)))
;; Each library form under src/ as its name and the names it imports from
;; (chezscheme), through (only (chezscheme) name ...) in its import clause.
;; Raises when src/ cannot be read.
(define (chez-imports)
  (apply append
         (map (lambda (path)
                (map (lambda (form)
                       (cons (cadr form)
                             (fold-left
                              (lambda (found spec)
                                (if (and (pair? spec) (eq? (car spec) 'only)
                                         (pair? (cdr spec)) (equal? (cadr spec) '(chezscheme)))
                                    (fold-left (lambda (found id) (if (memq id found) found (cons id found)))
                                               found (cddr spec))
                                    found))
                              '() (cdr (cadddr form)))))
                     (filter (lambda (form)
                               (and (pair? form) (eq? (car form) 'library) (list? form) (> (length form) 3)))
                             (read-forms path))))
              (sls-files "src"))))

;; imported-names : (Listof Symbol)
;; The names the libraries under src/ import from (chezscheme). No duplicate.
(define imported-names
  (guard (e (#t (list 'unreadable (describe e))))
    (fold-left (lambda (found id) (if (memq id found) found (cons id found)))
               '() (apply append (map cdr (chez-imports))))))

(define (symbols<? a b) (string<? (symbol->string a) (symbol->string b)))

;; sorted : (Listof Any) -> (Listof Any)
;; NAMES sorted by name; (unsortable NAMES) when they are not all symbols, as
;; the (unreadable TEXT) a failed read leaves is not. SRFI-64 does not catch a
;; raise in an expected expression, so neither side may raise.
(define (sorted names)
  (guard (e (#t (list 'unsortable names)))
    (list-sort symbols<? names)))

(test-equal "the scan of src/ found names imported from (chezscheme)"
  'found
  (if (and (pair? imported-names) (not (eq? (car imported-names) 'unreadable))) 'found imported-names))

(test-equal "allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)"
  (sorted imported-names)
  (sorted declared-names))

(test-equal "allowed-chez-names, written out whole"
  (sorted table-allowed)
  (sorted declared-names))

;; sorted-libraries : Any -> Any
(define (sorted-libraries names)
  (guard (e (#t (list 'unsortable names)))
    (list-sort (lambda (a b) (string<? (written a) (written b))) names)))

;; library-name? : Any -> Boolean
(define (library-name? x) (and (pair? x) (list? x) (for-all symbol? x)))

;; entry? : Any -> Boolean
;; Whether X is (name library-name ...), with at least one library.
(define (entry? x)
  (and (pair? x) (list? x) (symbol? (car x)) (pair? (cdr x)) (for-all library-name? (cdr x))))

(test-equal "library-only-chez-names is a list of (name library ...) entries"
  'entries
  (if (and (list? declared-library-only) (for-all entry? declared-library-only))
      'entries
      declared-library-only))

;; SRFI-64 does not catch a raise in the expected expression: each side below is
;; built under a guard of its own, with a sentinel of its own.
(test-equal "every library-only name is allowed, or imported by no library under src/"
  '()
  (guard (e (#t (list 'unreadable (describe e))))
    (remp (lambda (id) (or (memq id declared-names) (not (memq id imported-names))))
          (map car declared-library-only))))

(test-equal "no library under src/ imports a library-only name that its entry does not list"
  (guard (e (#t (list 'malformed (describe e))))
    (map (lambda (entry) (cons (car entry) '())) declared-library-only))
  (guard (e (#t (list 'unreadable (describe e))))
    (let ((scan (chez-imports)))
      (map (lambda (entry)
             (cons (car entry)
                   (remp (lambda (name) (member name (cdr entry)))
                         (map car (filter (lambda (library) (memq (car entry) (cdr library))) scan)))))
           declared-library-only))))

;; The entries above are held to src/'s imports, so an entry dropped with nothing else
;; changed passes there: the name then becomes one every library may import. So the
;; table is written out here whole, each name with its libraries.
(test-equal "library-only-chez-names, written out whole: foreign-alloc and foreign-free for memory; load-shared-object, foreign-procedure, foreign-entry, foreign-entry?, foreign-ref, foreign-set!, getenv and machine-type for native"
  table-only
  declared-library-only)

(test-equal "rnrs-libraries is the (rnrs ...) libraries this Chez has, but (rnrs eval)"
  (sorted-libraries
   (filter (lambda (name)
             (and (pair? name) (eq? (car name) 'rnrs) (not (equal? name '(rnrs eval)))))
           (library-list)))
  (sorted-libraries (declared 'rnrs-libraries)))

;; --- trees this suite writes ---------------------------------------------------------------

;; library-text : (Listof Symbol) (Listof Any) (Listof Any) (Listof Any) -> String
;; A library form, written, in a file that starts #!r6rs.
(define (library-text name exports imports body)
  (string-append "#!r6rs\n"
                 (written `(library ,name (export ,@exports) (import ,@imports) ,@body))
                 "\n"))

;; library-file : (Listof Symbol) -> String
;; Where Chez looks for the library NAME, below a tree's root.
(define (library-file name)
  (string-append (joined "/" (map symbol->string name)) ".sls"))

;; call-with-tree : (Listof (Pair (Listof Symbol) String)) (String -> Any) -> Any
;; Writes each (name . text) as the file for its library name in a fresh
;; directory, and answers (PROC DIR).
(define (call-with-tree files proc)
  (call-with-temp-directory
   (lambda (dir)
     (for-each (lambda (entry) (put-file! (string-append dir "/" (library-file (car entry))) (cdr entry)))
               files)
     (proc dir))))

;; refused-at : String (Listof (Pair (Listof Symbol) (Listof String))) -> (List 1 "" String)
;; The refusal for a tree at DIR whose libraries (name . complaint-tails), taken
;; in the order of their files' paths, each complaint being "PATH: NAME TAIL".
(define (refusals-at dir entries)
  (let* ((with-path (map (lambda (entry) (cons (string-append dir "/" (library-file (car entry))) entry)) entries))
         (ordered (list-sort (lambda (a b) (string<? (car a) (car b))) with-path))
         (problems (apply append
                          (map (lambda (item)
                                 (map (lambda (tail)
                                        (string-append (car item) ": " (written (cadr item)) " " tail))
                                      (cddr item)))
                               ordered))))
    (refused-list (length problems) problems)))

;; tree-verdict : String (Listof (Pair (Listof Symbol) String)) (String -> Expected) -> Any
;; Writes FILES in a fresh directory, runs the program PROGRAM-PATH there, and
;; answers 'as-expected when its whole answer equals (EXPECTED-OF dir), else the
;; two. The directory is in every complaint, so both sides are built with it. A
;; raise is answered, so no test's expected expression raises.
(define (tree-verdict program-path files expected-of)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-tree
     files
     (lambda (dir)
       (let* ((expected (expected-of dir))
              (actual (run-program program-path (list dir))))
         (if (equal? expected actual) 'as-expected (list 'differs expected actual)))))))

;; library-in : (Listof Symbol) (Listof Any) (Listof Any) (Listof Any) -> (Pair (Listof Symbol) String)
(define (library-in name exports imports body)
  (cons name (library-text name exports imports body)))

;; --- the allowlist of names, against its whole complement ---------------------------------

;; every-chez-name : (Listof Symbol)
;; Every name this Chez's (chezscheme) exports, sorted by name.
(define every-chez-name
  (list-sort symbols<? (environment-symbols (environment '(chezscheme)))))

(define complement-names
  (remp (lambda (id) (memq id table-allowed)) every-chez-name))

(test-equal "(chezscheme) exports names to refuse, in the hundreds"
  'many
  (if (> (length complement-names) 500) 'many (length complement-names)))

(test-equal "every name (chezscheme) exports that allowed-chez-names does not list is refused, in one library, in order, whole output"
  'as-expected
  (tree-verdict program
                (list (library-in '(chez-sqlite3 private x) '(x)
                                  (list '(rnrs) `(only (chezscheme) ,@complement-names))
                                  '((define x 1))))
                (lambda (dir)
                  (refusals-at dir
                               (list (cons '(chez-sqlite3 private x)
                                           (map (lambda (id) (not-listed (symbol->string id)))
                                                complement-names)))))))

(test-equal "every name allowed-chez-names lists passes, in one library"
  'as-expected
  (tree-verdict program
                (list (library-in '(chez-sqlite3 private x) '(x)
                                  (list '(rnrs) `(only (chezscheme) ,@table-allowed))
                                  '((define x 1))))
                (lambda (dir) (holds 1 1))))

;; The names, as p0 to p6, c0 to c2 and e0 to e4: a refused name at every position of an
;; only list, of the import clauses and of the export clause, one library each.
(define (numbered prefix i) (list 'chez-sqlite3 'private (string->symbol (string-append prefix (number->string i)))))

(test-equal "a name outside the list is refused at every position of an only list"
  'as-expected
  (tree-verdict program
                (map (lambda (i)
                       (library-in (numbered "p" i) '()
                                   (list '(rnrs) `(only (chezscheme) ,@(list-head table-allowed i) eval ,@(list-tail table-allowed i)))
                                   '()))
                     '(0 1 2 3 4 5 6))
                (lambda (dir)
                  (refusals-at dir (map (lambda (i) (cons (numbered "p" i) (list (not-listed "eval"))))
                                        '(0 1 2 3 4 5 6))))))

(test-equal "(chezscheme) imported whole is refused in the first, the middle and the last import clause"
  'as-expected
  (tree-verdict program
                (map (lambda (i)
                       (let ((specs '(((rnrs)) ((rnrs lists)) ((rnrs io ports)))))
                         (library-in (numbered "c" i) '()
                                     (append (apply append (list-head specs i)) '((chezscheme))
                                             (apply append (list-tail specs i)))
                                     '())))
                     '(0 1 2))
                (lambda (dir)
                  (refusals-at dir (map (lambda (i) (cons (numbered "c" i)
                                                          (list (string-append "imports (chezscheme), " chez-only))))
                                        '(0 1 2))))))

(test-equal "a name imported from (chezscheme) is refused at every position of the export clause"
  'as-expected
  (tree-verdict program
                (map (lambda (i)
                       (let ((others '(a b c d)))
                         (library-in (numbered "e" i)
                                     (append (list-head others i) '(threaded?) (list-tail others i))
                                     '((rnrs) (only (chezscheme) threaded?))
                                     '((define a 1) (define b 1) (define c 1) (define d 1)))))
                     '(0 1 2 3 4))
                (lambda (dir)
                  (refusals-at dir (map (lambda (i) (cons (numbered "e" i) (list (re-exports "threaded?" "threaded?"))))
                                        '(0 1 2 3 4))))))

;; --- the allowlist of libraries, against its whole complement ----------------------------------

;; extra-libraries : (Listof (Listof Symbol))
;; Libraries to refuse that this Chez may not have loaded.
(define extra-libraries
  '((srfi :1) (srfi :64) ($system) (rnrs foo) (sqlite3) (curl) (chez-sqlite3-testing) (rnrs eval)))

;; rnrs-allowed? : (Listof Symbol) -> Boolean
(define (rnrs-allowed? name)
  (and (pair? name) (eq? (car name) 'rnrs) (not (equal? name '(rnrs eval)))))

;; foreign-libraries : (Listof (Listof Symbol))
;; Every library this Chez has, and the extras, that is not an (rnrs ...) library allowed and not
;; in the family, sorted as written, once each.
(define foreign-libraries
  (let ((all (fold-left (lambda (found name) (if (member name found) found (cons name found)))
                        '() (append (library-list) extra-libraries))))
    (list-sort (lambda (a b) (string<? (written a) (written b)))
               (remp (lambda (name) (or (rnrs-allowed? name) (and (pair? name) (eq? (car name) 'chez-sqlite3))))
                     all))))

;; library-complaint : (Listof Symbol) -> String
(define (library-complaint name)
  (cond ((member name '((chezscheme) (scheme)))
         (string-append "imports " (written name) ", " chez-only))
        ((equal? name '(rnrs eval))
         "imports (rnrs eval), but no library under src/ may import (rnrs eval)")
        (else (string-append "imports " (written name) ", " unlisted-tail))))

(test-equal "every library this Chez has that the import allowlist does not allow is refused, in one library, in order, whole output"
  'as-expected
  (tree-verdict program
                (list (library-in '(chez-sqlite3 private x) '(x)
                                  (cons '(rnrs) foreign-libraries)
                                  '((define x 1))))
                (lambda (dir)
                  (refusals-at dir (list (cons '(chez-sqlite3 private x)
                                               (map library-complaint foreign-libraries)))))))

(test-equal "the (rnrs ...) libraries the allowlist allows are all accepted, in one library"
  'as-expected
  (tree-verdict program
                (list (library-in '(chez-sqlite3 private x) '(x)
                                  (filter rnrs-allowed? (library-list))
                                  '((define x 1))))
                (lambda (dir) (holds 1 1))))

;; --- rule (f), every name against every library, on the variant ----------------------------------

;; only-libraries : (Listof (Listof Symbol))
;; The libraries each library-only name is imported by, one library holding every name: the listed
;; ones, the public library, a private one, and near names of the listed ones.
(define only-libraries
  '((chez-sqlite3 private memory) (chez-sqlite3 private native) (chez-sqlite3)
    (chez-sqlite3 private counters) (chez-sqlite3 private other)
    (chez-sqlite3 private memory extra) (chez-sqlite3 private native extra)))

(test-equal "each library-only name is refused in every library but the one listed for it, whole output (variant)"
  'as-expected
  (tree-verdict variant-program
                (map (lambda (lib) (library-in lib '() (list '(rnrs) `(only (chezscheme) ,@(map car table-only))) '()))
                     only-libraries)
                (lambda (dir)
                  (refusals-at
                   dir
                   (map (lambda (lib)
                          (cons lib
                                (apply append
                                       (map (lambda (entry)
                                              (if (member lib (cdr entry))
                                                  '()
                                                  (list (library-only (symbol->string (car entry))
                                                                      (joined ", " (map written (cdr entry)))))))
                                            table-only))))
                        only-libraries)))))

;; --- rule (g), every allowed name re-exported, on the variant -----------------------------------

;; reexporters : (Listof (Pair (Listof Symbol) (Listof Symbol)))
;; Each library with the names it may import, all of them (variant).
(define reexporters
  (list (cons '(chez-sqlite3 private counters) table-allowed)
        (cons '(chez-sqlite3 private memory) '(foreign-alloc foreign-free))
        (cons '(chez-sqlite3 private native)
              '(load-shared-object foreign-procedure foreign-entry foreign-entry?
                foreign-ref foreign-set! getenv machine-type))))

(test-equal "each name allowed, in the library that may import it, refuses a re-export, plain and renamed, whole output (variant)"
  'as-expected
  (tree-verdict variant-program
                (map (lambda (entry)
                       (library-in (car entry)
                                   (apply append
                                          (map (lambda (id)
                                                 (list id (list 'rename (list id (string->symbol (string-append (symbol->string id) "-x"))))))
                                               (cdr entry)))
                                   (list '(rnrs) `(only (chezscheme) ,@(cdr entry)))
                                   '()))
                     reexporters)
                (lambda (dir)
                  (refusals-at dir
                               (map (lambda (entry)
                                      (cons (car entry)
                                            (apply append
                                                   (map (lambda (id)
                                                          (let ((s (symbol->string id)))
                                                            (list (re-exports s s)
                                                                  (re-exports (string-append s " as " s "-x") s))))
                                                        (cdr entry)))))
                                    reexporters)))))

;; --- the cases no fixture tree can hold ----------------------------------------------

;; Git keeps no empty directory, and the program is told a path that need not exist.
(test-equal "an empty directory holds no library"
  'refused
  (call-with-temp-directory
   (lambda (dir)
     (if (equal? (run (list dir))
                 (refused 1 (string-append "no libraries: " dir
                                           " holds no .sls file, so there is no seam to check")))
         'refused
         (run (list dir))))))

(test-equal "a directory that does not exist holds no library"
  'refused
  (call-with-temp-directory
   (lambda (dir)
     (let ((missing (string-append dir "/no-such-directory")))
       (if (equal? (run (list missing))
                   (refused 1 (string-append "no libraries: " missing
                                             " holds no .sls file, so there is no seam to check")))
           'refused
           (run (list missing)))))))

(define usage
  (list 1 "" "check-seam: usage: scheme --program tests/check-seam.sps DIR\n"))

(test-equal "no directory named: the usage line, exit 1" usage (run '()))

(test-equal "two directories named: the usage line, exit 1" usage (run '("a" "b")))

(test-end "check-seam")

(exit (suite-exit-status runner))
