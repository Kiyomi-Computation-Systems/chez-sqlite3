#!r6rs
;;; The suite for tests/check-nothreads.sps, the program behind `make
;;; check-nothreads` (ADR-0001). On a --nothreads Chez every library under src/
;;; must be refused at import, by name: every library there imports
;;; (chez-sqlite3 private require-threaded) first, and the program imports each
;;; and requires its refusal. CI runs it on a Chez built with --nothreads, the
;;; one place the refusal meets a real non-threaded Chez. Everything else is
;;; held here, on the Chez that runs the suites, which is threaded, so the real
;;; src/ must FAIL the program, naming each library it could import. That
;;; failure is the program's red run. Without this suite, deleting a rule would
;;; leave `make test` green: nothing else runs the program.
;;;
;;; Every rule has a fixture tree, written into one temporary directory of this
;;; process (never at a fixed path, so two runs at once share no file), whose
;;; require-threaded behaves as the case says whatever Chez runs it. This suite
;;; runs the program on each in a fresh Chez, through capture-command. A case
;;; asserts the exit status, the whole of stdout and the whole of stderr, as
;;; text written by hand here, never read back from the program: a substring
;;; would pass whenever another rule produced the same words.
;;;
;;; Each tree is the one fault it names, in an otherwise legal setting, so that
;;; only that rule can make it fail. `refusing` is the legal tree: the refusal,
;;; a public library, a library under it and a client of it, each importing the
;;; refusal first. Private libraries are checked as the others are: `private-loads`
;;; holds one that would load.
;;;
;;; make test runs every suite from the repository root, where tests/ and src/
;;; are, with CHEZ exported. Without CHEZ nothing below can run: that fails
;;; here, by name, and never skips.
(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
        (only (chezscheme) getenv directory-list file-directory? mkdir))

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

(define program "tests/check-nothreads.sps")

;; written : Any -> String
(define (written datum)
  (call-with-string-output-port (lambda (p) (write datum p))))

;; outcome : (-> Any) -> (U (List 'returned Any) (List 'raised String))
(define (outcome thunk)
  (guard (e (#t (list 'raised (describe e))))
    (list 'returned (thunk))))

;; run : (Listof String) -> (U (List Integer String String) (List 'raised String))
;; tests/check-nothreads.sps in a fresh Chez with ARGS: its exit status, stdout
;; and stderr. No --libdirs: the program finds the libraries it scans itself.
(define (run args)
  (guard (e (#t (list 'raised (describe e))))
    (capture-command (append (list chez "--program" program) args))))

;; --- the words the lines are made of, written by hand ------------------------------

;; line : String -> String
(define (line text) (string-append "check-nothreads: " text "\n"))

;; refused-line : String -> String
;; What a library that is refused by name gets, on stdout.
(define (refused-line name)
  (line (string-append name " is refused by name")))

;; loaded-line : String -> String
(define (loaded-line name)
  (line (string-append name " loaded, but a non-threaded Chez must refuse it")))

;; other-line : String String -> String
(define (other-line name what)
  (line (string-append name " raised something other than the refusal: " what)))

;; failed : Natural -> String
;; The last line of a failure. COUNT is given, not counted, so a miscount in the
;; program is not copied here.
(define (failed count)
  (line (string-append "FAILED (problems: " (number->string count) ")")))

;; passes : String ... -> (List 0 String "")
;; What a pass prints: one line for each library, in order.
(define (passes . names)
  (list 0 (apply string-append (map refused-line names)) ""))

;; fails : String Natural String ... -> (List 1 String String)
;; What a failure prints: STDOUT as given, then on stderr each problem line as
;; given, and the count.
(define (fails stdout count . problem-lines)
  (list 1 stdout (string-append (apply string-append problem-lines) (failed count))))

;; none : String -> String
;; The line for a tree with no library to import.
(define (none dir)
  (line (string-append "no library under " dir ", so there is nothing to refuse")))

(define usage
  (list 1 "" (line "usage: scheme --program tests/check-nothreads.sps DIR")))

(define threads-message
  "chez-sqlite3 needs a threaded Chez Scheme, and (threaded?) is #f in this one")

;; --- writing the fixture trees -----------------------------------------------------

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

;; put-link! : String String -> Unit
;; A symbolic link at PATH to TARGET, which need not exist.
(define (put-link! path target)
  (ensure-directory! (dir-of path))
  (let ((answer (capture-command (list "ln" "-s" target path))))
    (unless (eqv? (car answer) 0)
      (error 'put-link! "ln -s failed" answer))))

;; library-text : (Listof Symbol) (Listof (Listof Symbol)) -> String
(define (library-text name imports)
  (string-append "#!r6rs\n(library " (written name) " (export) (import "
                 (apply string-append
                        (map (lambda (i) (string-append (written i) " ")) imports))
                 "))\n"))

(define refusal '(chez-sqlite3 private require-threaded))

;; refusing-text, loading-text : (Listof Symbol) -> String
;; A library that imports the refusal first, and one that does not.
(define (refusing-text name) (library-text name (list refusal '(rnrs))))
(define (loading-text name) (library-text name '((rnrs))))

;; refusal-text : String String String String -> String
;; The source of the refusal, raising at expansion with RAISER (a procedure
;; name), WHO and MESSAGE, and TAIL closing the call: "x" hands it the form.
;; The (refuse) that raises is on line 13, at char 3.
(define (refusal-text raiser who message tail)
  (string-append
   "#!r6rs\n"
   ";;; Fixture: the refusal, raising at expansion as its case says.\n"
   ";;; Which case it is, is in the row that runs it.\n"
   "(library (chez-sqlite3 private require-threaded)\n"
   "  (export)\n"
   "  (import (rnrs))\n"
   "  (define-syntax refuse\n"
   "    (lambda (x)\n"
   "      (" raiser "\n"
   "       '" who "\n"
   "       \"" message "\"\n"
   "       " tail ")))\n"
   "  (refuse))\n"))

(define good-refusal (refusal-text "syntax-violation" "chez-sqlite3" threads-message "x"))

;; The cases. Each is the tree it writes: (path . text) files below its root,
;; and (path . target) links.

;; tree : (Listof (Pair String String)) -> (List files links)
(define (tree . files) (list files '()))
(define (with-links t . links) (list (car t) links))

;; The refusal and one public library: the smallest tree that passes.
(define (base refusal-source)
  (list (cons "chez-sqlite3/private/require-threaded.sls" refusal-source)
        (cons "chez-sqlite3.sls" (refusing-text '(chez-sqlite3)))))

(define lib-main "(chez-sqlite3)")
(define lib-refusal "(chez-sqlite3 private require-threaded)")

(define (raised-at case-root what where)
  (string-append what " (refuse) at " where " of "
                 case-root "/chez-sqlite3/private/require-threaded.sls"))

;; cases : (Listof (List String String (List files links) (String -> Expected)))
;; The case's name, what it holds, its tree, and from its root the program's
;; whole answer.
(define cases
  (list
   (list "refusing"
         "every library imports the refusal, which refuses: the refusal itself, a public library, one under it, a client of it"
         (tree (cons "chez-sqlite3/private/require-threaded.sls" good-refusal)
               (cons "chez-sqlite3.sls" (refusing-text '(chez-sqlite3)))
               (cons "chez-sqlite3/extra.sls" (refusing-text '(chez-sqlite3 extra)))
               (cons "chez-sqlite3/private/helper.sls" (refusing-text '(chez-sqlite3 private helper)))
               (cons "other-client.sls" (library-text '(other-client) '((chez-sqlite3) (rnrs)))))
         (lambda (root)
           (passes lib-main "(chez-sqlite3 extra)" "(chez-sqlite3 private helper)"
                   lib-refusal "(other-client)")))
   (list "mixed"
         "one public library does not import the refusal: it loads, and is named, and the others are still refused"
         (apply tree
                (cons "chez-sqlite3/unsupported.sls" (loading-text '(chez-sqlite3 unsupported)))
                (base good-refusal))
         (lambda (root)
           (fails (string-append (refused-line lib-main) (refused-line lib-refusal))
                  1
                  (loaded-line "(chez-sqlite3 unsupported)"))))
   (list "private-loads"
         "one private library does not import the refusal: it loads, and is named, so private libraries are imported"
         (apply tree
                (cons "chez-sqlite3/private/helper.sls" (loading-text '(chez-sqlite3 private helper)))
                (base good-refusal))
         (lambda (root)
           (fails (string-append (refused-line lib-main) (refused-line lib-refusal))
                  1
                  (loaded-line "(chez-sqlite3 private helper)"))))
   (list "raises-other"
         "the refusal raises, but a plain error, not the refusal"
         (apply tree (base (refusal-text "error" "fixture" "boom" "")))
         (lambda (root)
           (fails "" 2
                  (other-line lib-main "Exception in fixture: boom")
                  (other-line lib-refusal "Exception in fixture: boom"))))
   (list "wrong-message"
         "a syntax violation from chez-sqlite3 whose message is not the threads refusal's"
         (apply tree
                (base (refusal-text "syntax-violation" "chez-sqlite3"
                                    "chez-sqlite3 needs Chez Scheme 10.4.0 or later, and this one is 10.3.0"
                                    "x")))
         (lambda (root)
           (let ((what (raised-at root
                                  "Exception in chez-sqlite3: chez-sqlite3 needs Chez Scheme 10.4.0 or later, and this one is 10.3.0"
                                  "line 13, char 3")))
             (fails "" 2 (other-line lib-main what) (other-line lib-refusal what)))))
   (list "wrong-who"
         "the threads refusal's message in a syntax violation from someone else"
         (apply tree (base (refusal-text "syntax-violation" "someone-else" threads-message "x")))
         (lambda (root)
           (let ((what (raised-at root
                                  (string-append "Exception in someone-else: " threads-message)
                                  "line 13, char 3")))
             (fails "" 2 (other-line lib-main what) (other-line lib-refusal what)))))
   (list "not-syntax"
         "the threads refusal's who and message in an assertion violation, not a syntax violation"
         (apply tree (base (refusal-text "assertion-violation" "chez-sqlite3" threads-message "")))
         (lambda (root)
           (let ((what (string-append "Exception in chez-sqlite3: " threads-message)))
             (fails "" 2 (other-line lib-main what) (other-line lib-refusal what)))))
   (list "empty"
         "a tree with no library source in it"
         (tree (cons "notes.txt" "Fixture: a tree with no library source in it.\n"))
         (lambda (root) (fails "" 1 (none root))))
   (list "unreadable"
         "a source that cannot be read as data is named, and the libraries beside it are still checked"
         (apply tree
                (cons "chez-sqlite3/broken.sls" "(library (chez-sqlite3 broken) (export) (import (rnrs))\n")
                (base good-refusal))
         (lambda (root)
           (fails (string-append (refused-line lib-main) (refused-line lib-refusal)) 1
                  (line (string-append
                         root "/chez-sqlite3/broken.sls"
                         ": it cannot be read as data: Exception in read: unexpected end-of-file reading list before file-position 56 of #<input port "
                         root "/chez-sqlite3/broken.sls"
                         ">; the character position might differ")))))
   (list "dangling-link"
         "a .sls that is a symbolic link to nothing is named, and the libraries beside it are still checked"
         (with-links (apply tree (base good-refusal))
                     (cons "chez-sqlite3/dangling.sls" "nowhere.sls"))
         (lambda (root)
           (fails (string-append (refused-line lib-main) (refused-line lib-refusal)) 1
                  (line (string-append
                         root "/chez-sqlite3/dangling.sls"
                         ": it cannot be read as data: Exception in open-file-input-port: failed for "
                         root "/chez-sqlite3/dangling.sls: no such file or directory")))))
   (list "dir-symlink"
         "a symbolic link to a directory is named, not followed"
         (with-links (apply tree (base good-refusal))
                     (cons "linked" "chez-sqlite3"))
         (lambda (root)
           (fails (string-append (refused-line lib-main) (refused-line lib-refusal)) 1
                  (line (string-append root "/linked"
                                       ": it is a symbolic link to a directory, which this check does not follow")))))))

;; Where the trees go: one directory of this process, removed when it ends.
(define fixtures
  (guard (e (#t #f)) (make-process-temp-directory)))

;; at : String -> String
(define (at case) (string-append fixtures "/" case))

;; build! : -> Unit
(define (build!)
  (for-each
   (lambda (case)
     (let ((root (at (car case))))
       (ensure-directory! root)
       (for-each (lambda (f) (put-file! (string-append root "/" (car f)) (cdr f)))
                 (car (caddr case)))
       (for-each (lambda (l) (put-link! (string-append root "/" (car l)) (cdr l)))
                 (cadr (caddr case)))))
   cases))

(test-begin "check-nothreads")

(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (and chez (not (string=? chez ""))) 'set 'unset))

(unless (and chez (not (string=? chez "")))
  (exit 1))

(test-equal "the fixture trees are written"
  '(returned ok)
  (outcome (lambda () (build!) 'ok)))

(for-each
 (lambda (case)
   (test-equal (string-append (car case) ": " (cadr case))
     ((cadddr case) (at (car case)))
     (run (list (at (car case))))))
 cases)

;; --- arguments ---------------------------------------------------------------------------

(test-equal "a directory that does not exist holds no library"
  (fails "" 1 (none (at "no-such-tree")))
  (run (list (at "no-such-tree"))))

(test-equal "no arguments: the usage line, exit 1"
  usage
  (run '()))

(test-equal "two arguments: the usage line, exit 1"
  usage
  (run (list (at "refusing") (at "mixed"))))

;; --- the real tree --------------------------------------------------------------------------
;; This Chez is threaded, so nothing is refused here: the program must fail on
;; src/, naming every library it finds. The expected names come from a scan
;; written out in this suite, so that a library added later is named without
;; editing the row.

;; sls-files : String -> (Listof String)
;; Every .sls under DIR, sorted by its whole path, as the program sorts them:
;; so src/chez-sqlite3.sls comes before src/chez-sqlite3/x.sls, . before /,
;; though a walk directory by directory would reach chez-sqlite3/ first.
(define (sls-files dir)
  (define (walk dir)
    (apply append
           (map (lambda (name)
                  (let ((path (string-append dir "/" name)))
                    (cond ((file-directory? path) (walk path))
                          ((and (> (string-length name) 4)
                                (string=? (substring name (- (string-length name) 4)
                                                     (string-length name))
                                          ".sls"))
                           (list path))
                          (else '()))))
                (directory-list dir))))
  (list-sort string<? (walk dir)))

;; library-name : String -> (U (Listof Symbol) Symbol)
;; The name of the library form that opens the file at PATH, or a symbol when
;; it holds none.
(define (library-name path)
  (guard (e (#t 'unreadable))
    (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      (lambda (port)
        (let ((form (read port)))
          (if (and (pair? form) (eq? (car form) 'library) (pair? (cdr form)))
              (cadr form)
              'no-library))))))

;; real-names : (Listof String)
;; The libraries under src/, as the program writes them, in path order. None
;; when src/ cannot be listed: a raise at top level would end the suite with no
;; test named, and the rows below then fail by name.
(define real-names
  (guard (e (#t '()))
    (let loop ((names (map library-name (sls-files "src"))) (found '()))
      (cond ((null? names) (reverse found))
            ((pair? (car names)) (loop (cdr names) (cons (written (car names)) found)))
            (else (loop (cdr names) found))))))

(test-equal "src/ holds the refusal and the counters"
  '(found found)
  (list (if (member lib-refusal real-names) 'found 'not-found)
        (if (member "(chez-sqlite3 private counters)" real-names) 'found 'not-found)))

(test-equal "src/: on a threaded Chez nothing is refused, so the program names every library it could import"
  (apply fails "" (length real-names) (map loaded-line real-names))
  (run (list "src")))

(test-end "check-nothreads")

(exit (suite-exit-status runner))
