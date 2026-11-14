#!r6rs
;;; The suite that holds (chez-sqlite3-testing) and the counters it imports
;;; to loading no libsqlite3 (the M1 plan, §3.7). make check-suites, the
;;; copy check-test-fails makes, which holds only require-threaded and the
;;; counters in all but its leaks case, the launcher's env -i runs of make
;;; test, and the seven children test-chez-sqlite3-testing starts to test the
;;; temporary directories all import the testing library, and each would
;;; break, or become a child that reaches native code, if it loaded
;;; libsqlite3. Since M1 slice 4, native's load registers the
;;; sqlite3_memory_used check with the counters, so the testing library runs
;;; it without importing native.
;;;
;;; Each library is read as data, with Chez's reader, and nothing in it is
;;; evaluated:
;;;
;;;   the allowlists  tests/chez-sqlite3-testing.sls' and counters.sls'
;;;                   import specs, each exactly its allowlist below, the
;;;                   (only (chezscheme) ...) name lists included: a planted
;;;                   import, or a name such as load-shared-object, is extra
;;;   the loaders     the libraries under src/ that load libsqlite3:
;;;                   (chez-sqlite3 private native), the only one that calls
;;;                   load-shared-object (check-seam's rule (f)), and every
;;;                   library that imports a loader, found from src/'s
;;;                   imports, and asserted whole
;;;   the reach       the (chez-sqlite3 ...) libraries the testing library
;;;                   imports, and every one they import, through src/: none
;;;                   is a loader, nor any library an allowlist names
;;;
;;; An allowlist that gained a loader, with an import to match, passes the
;;; first row and fails the last two. A loader that the data cannot see, a
;;; helper library under tests/ that imports (chez-sqlite3), say, is seen by
;;; the last row, which runs a child:
;;;
;;;   the child       a fresh Chez imports (chez-sqlite3-testing) and
;;;                   references every export of it, so its body runs, then
;;;                   prints how many it referenced, (exit-checks) and
;;;                   whether /proc/self/maps names a libsqlite3: no check
;;;                   registered, and no library mapped
(import (rnrs)
        (srfi :64)
        (only (chezscheme) directory-list file-directory? file-symbolic-link? getenv library-exports)
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
      (when (memq (test-result-kind r) (quote (fail xpass)))
        (display "  expected: ")
        (write (test-result-ref r (quote expected-value)))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r (quote actual-value)))
        (newline)))))

;; --- the allowlists ---------------------------------------------------------
;; Each is a library's import specs, whole, as the file writes them. A change
;; to a library's imports changes its list here, in review.

(define testing-source "tests/chez-sqlite3-testing.sls")
(define counters-source "src/chez-sqlite3/private/counters.sls")

;; testing-allowlist : (Listof Any)
(define testing-allowlist
  '((rnrs)
    (srfi :64)
    (chez-sqlite3 private counters)
    (only (chezscheme) base-exception-handler critical-section
          delete-directory display-condition exit-handler file-directory?
          get-process-id getenv make-mutex mkdir system with-mutex)
    (prefix (only (chezscheme) file-exists?) chez:)))

;; counters-allowlist : (Listof Any)
(define counters-allowlist
  '((chez-sqlite3 private require-threaded)
    (rnrs)
    (only (chezscheme) critical-section make-mutex with-mutex)))

;; --- reading libraries as data ----------------------------------------------

;; read-library : String -> (U (List Name (Listof Spec)) (List 'unreadable String))
;; The library form at PATH, its first datum: its name and its import specs.
(define (read-library path)
  (guard (e (#t (list 'unreadable (string-append path ": " (describe e)))))
    (let ((form (call-with-port
                 (open-file-input-port path (file-options) (buffer-mode block)
                                       (make-transcoder (utf-8-codec)))
                 read)))
      (if (and (list? form) (>= (length form) 4) (eq? (car form) 'library)
               (pair? (cadddr form)) (eq? (car (cadddr form)) 'import))
          (list (cadr form) (cdr (cadddr form)))
          (list 'unreadable (string-append path ": not a (library NAME (export ...) (import ...) ...) form"))))))

;; spec-library : Spec -> Name
;; The library an import spec names, through the wrappers R6RS and Chez
;; give: only, except, prefix, rename, for, library. A version reference
;; after a name, a list, is dropped.
(define (spec-library spec)
  (cond ((and (pair? spec) (memq (car spec) '(only except prefix rename for)) (pair? (cdr spec)))
         (spec-library (cadr spec)))
        ((and (pair? spec) (eq? (car spec) 'library) (pair? (cdr spec)))
         (spec-library (cadr spec)))
        ((pair? spec)
         (let ((parts (reverse spec)))
           (if (pair? (car parts)) (reverse (cdr parts)) spec)))
        (else spec)))

;; sls-files : String -> (Listof String)
;; Every .sls file under DIR, in sorted order, through no symbolic link.
(define (sls-files dir)
  (let loop ((names (list-sort string<? (directory-list dir))) (found '()))
    (if (null? names)
        (reverse found)
        (let ((path (string-append dir "/" (car names))))
          (loop (cdr names)
                (cond ((file-symbolic-link? path) found)
                      ((file-directory? path) (append (reverse (sls-files path)) found))
                      ((let ((n (string-length path)))
                         (and (> n 4) (string=? (substring path (- n 4) n) ".sls")))
                       (cons path found))
                      (else found)))))))

;; src-imports : (U (Listof (Pairof Name (Listof Name))) (List 'unreadable String))
;; Each library under src/ with the libraries it imports.
(define src-imports
  (guard (e (#t (list 'unreadable (describe e))))
    (let loop ((paths (sls-files "src")) (found '()))
      (if (null? paths)
          (reverse found)
          (let ((lib (read-library (car paths))))
            (if (eq? (car lib) 'unreadable)
                lib
                (loop (cdr paths)
                      (cons (cons (car lib) (map spec-library (cadr lib))) found))))))))

(define src-read? (not (and (pair? src-imports) (eq? (car src-imports) 'unreadable))))

;; imports-of : Name -> (Listof Name)
;; What the library NAME under src/ imports; none for a library outside it.
(define (imports-of name)
  (cond ((and src-read? (assoc name src-imports)) => cdr)
        (else '())))

;; name<? : Name Name -> Boolean
;; Library names ordered by how they are written, so a set of them is a list.
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))
(define (name<? a b) (string<? (written a) (written b)))
(define (sorted names) (list-sort name<? names))

;; adjoin : (Listof Any) (Listof Any) -> (Listof Any)
(define (adjoin items set)
  (fold-left (lambda (set x) (if (member x set) set (cons x set))) set items))

;; native : Name
(define native '(chez-sqlite3 private native))

;; loaders : (Listof Name)
;; native, and every library under src/ that imports a loader, found by
;; adding importers until none is left to add.
(define loaders
  (let grow ((found (list native)))
    (let ((more (filter (lambda (entry)
                          (and (not (member (car entry) found))
                               (exists (lambda (name) (member name found)) (cdr entry))))
                        (if src-read? src-imports '()))))
      (if (null? more)
          (sorted found)
          (grow (adjoin (map car more) found))))))

;; reach : (Listof Name) -> (Listof Name)
;; The (chez-sqlite3 ...) libraries among NAMES, and every one they import,
;; and so on, through src/.
(define (reach names)
  (let walk ((todo names) (seen '()))
    (cond ((null? todo) (sorted seen))
          ((or (member (car todo) seen)
               (not (and (pair? (car todo)) (eq? (caar todo) 'chez-sqlite3))))
           (walk (cdr todo) seen))
          (else (walk (append (cdr todo) (imports-of (car todo))) (cons (car todo) seen))))))

;; differences : (Listof Any) (Listof Any) -> (List (Listof Any) (Listof Any))
;; (EXTRA MISSING): the specs in FOUND that ALLOWED lacks, and those it has
;; that FOUND lacks, each in the order written.
(define (differences found allowed)
  (list (filter (lambda (s) (not (member s allowed))) found)
        (filter (lambda (s) (not (member s found))) allowed)))

;; import-differences : String (Listof Any) -> Any
;; differences for the library at PATH against ALLOWED, or why it was not read.
(define (import-differences path allowed)
  (let ((lib (read-library path)))
    (if (eq? (car lib) 'unreadable)
        lib
        (cons (car lib) (differences (cadr lib) allowed)))))

(test-begin "never-loads")

(test-equal "(chez-sqlite3-testing) imports exactly its allowlist, no more and no less"
  '((chez-sqlite3-testing) () ())
  (import-differences testing-source testing-allowlist))

(test-equal "(chez-sqlite3 private counters) imports exactly its allowlist, no more and no less"
  '((chez-sqlite3 private counters) () ())
  (import-differences counters-source counters-allowlist))

(test-equal "the libraries under src/ that load libsqlite3, found from their imports: native, and each that imports a loader"
  (sorted '((chez-sqlite3)
            (chez-sqlite3 private connection)
            (chez-sqlite3 private native)
            (chez-sqlite3 private report)))
  (if src-read? loaders src-imports))

;; What the testing library imports, read from its file, not its allowlist.
(define testing-read (read-library testing-source))

(test-equal "what the testing library reaches through src/ is the counters and require-threaded, and no library an allowlist names, nor one it reaches, loads libsqlite3"
  (list (sorted '((chez-sqlite3 private counters) (chez-sqlite3 private require-threaded)))
        '()
        '())
  (cond ((not src-read?) src-imports)
        ((eq? (car testing-read) 'unreadable) testing-read)
        (else
         (let* ((named (map spec-library (append testing-allowlist counters-allowlist)))
                (reached (reach (map spec-library (cadr testing-read)))))
           (list reached
                 (filter (lambda (name) (member name loaders)) (sorted (adjoin named '())))
                 (filter (lambda (name) (member name loaders)) reached))))))

;; --- the behaviour: a child that uses every export ----------------------------

(define chez (getenv "CHEZ"))

;; The names (chez-sqlite3-testing) exports, as Chez lists them, sorted.
(define testing-exports
  (guard (e (#t (list (string->symbol (describe e)))))
    (sorted (library-exports '(chez-sqlite3-testing)))))

;; write-text : String String -> Void
(define (write-text path text)
  (call-with-port
   (open-file-output-port path (file-options no-fail) (buffer-mode block)
                          (make-transcoder (utf-8-codec)))
   (lambda (p) (put-string p text))))

;; child-program : (Listof Symbol) -> String
;; A program that imports the testing library, and the counters for
;; exit-checks, makes a list of every name in NAMES, and prints (COUNT CHECKS
;; MAPPED): how many it referenced, what exit-checks answers, and yes or no
;; for a libsqlite3 in /proc/self/maps.
(define (child-program names)
  (string-append
   "#!r6rs\n"
   "(import (rnrs) (chez-sqlite3-testing) (chez-sqlite3 private counters))\n"
   "(define referenced (list " (apply string-append (map (lambda (n) (string-append (symbol->string n) " ")) names)) "))\n"
   "(define (mapped?)\n"
   "  (if (not (file-exists? \"/proc/self/maps\"))\n"
   "      'no-maps\n"
   "      (let ((maps (call-with-port\n"
   "                   (open-file-input-port \"/proc/self/maps\" (file-options) (buffer-mode block)\n"
   "                                         (make-transcoder (utf-8-codec)))\n"
   "                   get-string-all))\n"
   "            (needle \"libsqlite3\"))\n"
   "        (let loop ((i 0))\n"
   "          (cond ((> (+ i (string-length needle)) (string-length maps)) 'no)\n"
   "                ((string=? (substring maps i (+ i (string-length needle))) needle) 'yes)\n"
   "                (else (loop (+ i 1))))))))\n"
   "(write (list (length referenced) (exit-checks) (mapped?)))\n"
   "(newline)\n"
   "(exit 0)\n"))

;; run-child : (Listof Symbol) -> (U (List Integer String String) (List 'raised String))
(define (run-child names)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (base)
       (let ((program (string-append base "/child.sps")))
         (write-text program (child-program names))
         (capture-command
          (list chez "--libdirs" "src:tests:build/scheme-libs" "--program" program)))))))

;; A system with no /proc, macOS, can't say what is mapped: there the child
;; prints no-maps, and the row holds the count and the checks alone.
(test-equal "a child that references every export of (chez-sqlite3-testing) runs its body, and registers no exit check and maps no libsqlite3: it prints the count of names, (), and no, or no-maps where there is no /proc"
  (list 0 (string-append "(" (number->string (length testing-exports)) " () "
                         (if (file-exists? "/proc/self/maps") "no" "no-maps") ")\n") "")
  (run-child testing-exports))

(test-end "never-loads")

(exit (suite-exit-status runner))
