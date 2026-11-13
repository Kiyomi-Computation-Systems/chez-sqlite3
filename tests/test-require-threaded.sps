#!r6rs
;;; The suite for (chez-sqlite3 private require-threaded): chez-sqlite3 needs a
;;; threaded Chez of at least 10.4.0, and refuses any other by name (ADR-0001).
;;;
;;; Chez builds make-mutex, fork-thread and the rest of its thread system
;;; only into threaded builds, so on a --nothreads Chez a library importing
;;; them dies at import with a bare "missing import for make-mutex". The
;;; refusal raises a readable message instead, while it is being expanded.
;;; That helps only if it is expanded first: Chez processes a library's
;;; imports in order. So every library under src/ but the refusal itself
;;; imports (chez-sqlite3 private require-threaded) first among its imports.
;;; This suite reads each library's import form as data and holds that order.
;;;
;;; The scan reads .sls files only, but Chez tries every ending of
;;; (library-extensions), and loads a .ss or a .chezscheme.sls ahead of the
;;; .sls beside it. So a second rule holds every file under src/ that Chez
;;; could load, source or compiled, to be a .sls and no .chezscheme.sls, and
;;; names any other. Each ending has a row, on a tree made in a temporary
;;; directory, so that two runs of this suite at once share no path.
;;;
;;; It also holds the refusal itself, on this Chez: it expands a copy of the
;;; refusal's source in which each call (threaded?) answers #f, as a
;;; --nothreads Chez's does, and requires the refusal's whole message. It does the
;;; same with each call (scheme-version-number) answering a version and each
;;; call (scheme-version #t) answering the version's text, for a release or
;;; for a pre-release, in rows on each side of the floor, 10.4.0. A
;;; pre-release comes before the release it is numbered for, so
;;; 10.4.0-pre-release.N is below the floor and 10.5.0-pre-release.N is not.
;;;
;;; The floor is held to packaging/floors.sexp, the one file that writes it
;;; (ADR-0008). Each expected message takes the floor's text from that file,
;;; and further rows are built from it. The literal rows stay: they name
;;; 10.4.0 and its neighbours, so a floor changed in both places at once is a
;;; decision a reader of this suite sees.
;;;
;;; make test runs every suite from the repository root, where src/ is. An
;;; empty or missing src/ fails here by name, never passes for want of rows.
;;;
;;; Each expected value is a symbol the code under test cannot produce by
;;; failing. SRFI-64 turns a raise in the actual expression into #f.
(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
        (floors)
        (only (chezscheme) directory-list file-directory? file-symbolic-link? eval
              interaction-environment library-extensions))

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

(define refusal-library '(chez-sqlite3 private require-threaded))

;; The Chez floor of packaging/floors.sexp, computed under a guard: a raise at
;; top level would end the suite with no test named, and one in an expected
;; expression would escape SRFI-64. Each is a symbol when the file cannot give
;; the floor, so the rows built from it fail by name.

;; chez-floor : (U (List Natural Natural Natural) Symbol)
(define chez-floor
  (guard (e (#t 'floors-file-unreadable))
    (let ((parts (floor-numbers (read-floors) 'chez)))
      (if (= (length parts) 3) parts 'not-three-numbers))))

;; chez-floor-text : (U String Symbol)
(define chez-floor-text
  (guard (e (#t 'floors-file-unreadable))
    (floor-text (read-floors) 'chez)))

;; --- reading the tree -----------------------------------------------------------

;; sls-file? : String -> Boolean
;; A library source by its name: *.sls, with something before the suffix.
(define (sls-file? name)
  (let ((n (string-length name)))
    (and (> n 4)
         (string=? (substring name (- n 4) n) ".sls"))))

;; lock-file? : String String -> Boolean
;; Whether the entry NAME, at PATH, is an Emacs lock file: named .#..., and a
;; symbolic link to nothing, which Chez cannot load. It is the rule of
;; tests/check-seam.sps. A regular file or a directory named .#... is no lock
;; file: Chez loads a library from .#g.sls as it does from g.sls, so the scan
;; reads it. Nor is a link that resolves.
(define (lock-file? path name)
  (and (> (string-length name) 1)
       (char=? (string-ref name 0) #\.)
       (char=? (string-ref name 1) #\#)
       (file-symbolic-link? path)
       (not (file-exists? path))))

;; sls-files : String -> (Listof String)
;; Every library source under DIR, depth first, sorted; none when DIR is
;; not a directory. A lock-file? is skipped: reading one would stop the suite.
(define (sls-files dir)
  (if (file-directory? dir)
      (apply append
             (map (lambda (name)
                    (let ((path (string-append dir "/" name)))
                      (cond ((lock-file? path name) '())
                            ((file-directory? path) (sls-files path))
                            ((sls-file? name) (list path))
                            (else '()))))
                  (list-sort string<? (directory-list dir))))
      '()))

;; first-datum : String -> Any
;; The first datum in the file at PATH (Chez's reader skips #!r6rs), or
;; (unreadable TEXT).
(define (first-datum path)
  (guard (e (#t (list 'unreadable (describe e))))
    (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      read)))

;; library-form? : Any -> Boolean
;; (library NAME (export ...) (import ...) body ...).
(define (library-form? form)
  (and (list? form)
       (>= (length form) 4)
       (eq? (car form) 'library)
       (pair? (cadddr form))
       (eq? (car (cadddr form)) 'import)))

(define (form-name form)
  (and (library-form? form) (cadr form)))

(define (form-exports form)
  (and (library-form? form)
       (pair? (caddr form))
       (eq? (car (caddr form)) 'export)
       (cdr (caddr form))))

;; spec-library : Import-Spec -> Library-Reference
;; The library an import spec draws on, seen through only, except, prefix,
;; rename and for, and the (library ...) escape.
(define (spec-library spec)
  (if (and (pair? spec)
           (memq (car spec) '(only except prefix rename for library))
           (pair? (cdr spec))
           (pair? (cadr spec)))
      (spec-library (cadr spec))
      spec))

;; library-name : Library-Reference -> (Listof Symbol)
;; The reference without its optional version: (chez-sqlite3 private x (1)).
(define (library-name ref)
  (if (or (not (pair? ref)) (pair? (car ref)))
      '()
      (cons (car ref) (library-name (cdr ref)))))

;; first-order : (Listof Import-Spec) (Listof Symbol) -> (U 'first 'not-first 'absent)
;; Where the library REQUIRED stands among SPECS.
(define (first-order specs required)
  (let ((names (map (lambda (spec) (library-name (spec-library spec))) specs)))
    (cond ((null? names) 'absent)
          ((equal? (car names) required) 'first)
          ((member required (cdr names)) 'not-first)
          (else 'absent))))

;; import-order : (Listof Import-Spec) -> (U 'first 'not-first 'absent)
;; Where the refusal stands among SPECS.
(define (import-order specs)
  (first-order specs refusal-library))

;; verdict : Any -> (U 'first 'not-first 'absent 'not-a-library)
(define (verdict form)
  (if (library-form? form)
      (first-order (cdr (cadddr form)) refusal-library)
      'not-a-library))

;; written : Any -> String
(define (written x)
  (call-with-string-output-port (lambda (p) (write x p))))

(test-begin "require-threaded")

;; --- the checker, on seeded import forms -------------------------------------------
;; A checker that never reported anything would pass every row on the real
;; tree, so first it must tell each of these apart.

(test-equal "the refusal first among the imports is first"
  'first
  (import-order '((chez-sqlite3 private require-threaded) (rnrs) (only (chezscheme) make-mutex))))

(test-equal "the refusal after (rnrs) is not first"
  'not-first
  (import-order '((rnrs) (chez-sqlite3 private require-threaded))))

(test-equal "no refusal among the imports is absent"
  'absent
  (import-order '((rnrs) (chez-sqlite3 private counters))))

(test-equal "no imports at all is absent"
  'absent
  (import-order '()))

(test-equal "a wrapped or versioned refusal is the same library"
  '(first first first)
  (map (lambda (spec) (import-order (list spec '(rnrs))))
       '((only (chez-sqlite3 private require-threaded))
         (library (chez-sqlite3 private require-threaded))
         (chez-sqlite3 private require-threaded (1)))))

(test-equal "a file whose first datum is no library form is not a library"
  'not-a-library
  (verdict '(import (rnrs))))

;; --- the scan ------------------------------------------------------------------------

(test-equal "the scan reads a name ending in .sls, a dotfile included, and no other"
  '(read read skipped skipped skipped skipped)
  (map (lambda (name) (if (sls-file? name) 'read 'skipped))
       '("native.sls" "._native.sls" "native.sls~" "#native.sls#" ".sls" "native.ss")))

;; Trees the suite makes, each in a temporary directory of its own, so that
;; two runs of this suite at once share no path.

;; make-tree : String (Listof (List Symbol String ...)) -> Unit
;; Makes ENTRIES under DIR: (file PATH) an empty file, (dir PATH) a directory,
;; (link PATH TARGET) a symbolic link to TARGET, which may be dangling.
;; Parent directories are made as needed.
(define (make-tree dir entries)
  (for-each
   (lambda (entry)
     (let* ((path (string-append dir "/" (cadr entry)))
            (parent (let loop ((i (string-length path)))
                      (if (char=? (string-ref path (- i 1)) #\/) (substring path 0 (- i 1)) (loop (- i 1))))))
       (capture-command (list "mkdir" "-p" (if (eq? (car entry) 'dir) path parent)))
       (case (car entry)
         ((file) (capture-command (list "touch" path)))
         ((link) (capture-command (list "ln" "-s" (caddr entry) path)))
         ((dir) #f))))
   entries))

;; relative : String (Listof String) -> (Listof String)
;; PATHS without the leading DIR and slash.
(define (relative dir paths)
  (let ((n (+ (string-length dir) 1)))
    (map (lambda (p) (substring p n (string-length p))) paths)))

;; in-tree : (Listof Entry) (String -> Any) -> Any
;; PROC on the path of a fresh temporary directory holding ENTRIES. A raise of
;; PROC's is its answer, as (raised TEXT), so no raise escapes the row.
(define (in-tree entries proc)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir) (make-tree dir entries) (proc dir)))))

(test-equal "the scan skips a .# dangling symbolic link, reads a .# regular file, and enters a .# directory"
  '("d/.#dir/inner.sls" "d/.#regular.sls" "d/legal.sls")
  (in-tree '((file "d/legal.sls") (file "d/.#regular.sls") (file "d/.#dir/inner.sls")
             (link "d/.#lock.sls" "nowhere"))
           (lambda (dir) (relative dir (sls-files dir)))))

(test-equal "the scan reads a .# link that resolves, which is no lock file"
  '("d/.#live.sls" "d/real.sls")
  (in-tree '((file "d/real.sls") (link "d/.#live.sls" "real.sls"))
           (lambda (dir) (relative dir (sls-files dir)))))

;; --- a file Chez could load in place of a .sls --------------------------------------
;; Chez's (library-extensions) here is .chezscheme.sls .ss .sls .scm .sch, tried
;; in that order, and an object file (.so) beside a source is loaded when it is
;; newer. So a counters.ss beside counters.sls, without the refusal import, is
;; what Chez loads, and the scan of .sls files alone never sees it. Every file
;; under src/ that Chez could load must be a .sls, and not a .chezscheme.sls,
;; which Chez prefers to the .sls beside it.

;; ends-with? : String String -> Boolean
(define (ends-with? suffix s)
  (let ((n (string-length s)) (m (string-length suffix)))
    (and (>= n m) (string=? (substring s (- n m) n) suffix))))

;; loadable-endings : (Listof String)
;; Every ending of a file Chez could load as a library, source or compiled,
;; from Chez's own list: (library-extensions) pairs each source ending with its
;; compiled one.
(define loadable-endings
  (fold-left (lambda (found ext) (if (member ext found) found (append found (list ext))))
             '()
             (apply append (map (lambda (pair) (list (car pair) (cdr pair)))
                                (library-extensions)))))

;; stray-file? : String String -> Boolean
;; Whether the entry NAME, at PATH, is a file Chez could load as a library that
;; is not a plain .sls: it ends in a loadable ending, and is not a .sls other
;; than .chezscheme.sls. A lock-file? is no file Chez can load.
(define (stray-file? path name)
  (and (not (lock-file? path name))
       (not (file-directory? path))
       (exists (lambda (ending) (ends-with? ending name)) loadable-endings)
       (or (not (ends-with? ".sls" name))
           (ends-with? ".chezscheme.sls" name))))

;; stray-files : String -> (Listof String)
;; Every stray-file? under DIR, depth first, sorted; none when DIR is not a
;; directory.
(define (stray-files dir)
  (if (file-directory? dir)
      (apply append
             (map (lambda (name)
                    (let ((path (string-append dir "/" name)))
                      (cond ((lock-file? path name) '())
                            ((file-directory? path) (stray-files path))
                            ((stray-file? path name) (list path))
                            (else '()))))
                  (list-sort string<? (directory-list dir))))
      '()))

;; One row per ending: a legal .sls beside the file, so that the tree is
;; otherwise clean, and the file is the one thing named.
(for-each
 (lambda (ending)
   (test-equal (string-append "a file x" ending " under the tree is named, and the .sls beside it is not")
     (list (string-append "d/x" ending))
     (in-tree (list '(file "d/x.sls") (list 'file (string-append "d/x" ending)))
              (lambda (dir) (relative dir (stray-files dir))))))
 '(".ss" ".scm" ".sch" ".so" ".chezscheme.sls" ".chezscheme.so"))

(test-equal "a tree of .sls files, other files, a .#lock.ss dangling link and a directory named x.ss has no stray file"
  '()
  (in-tree '((file "d/x.sls") (file "d/notes.txt") (file "d/x.sls~") (file "d/.#x.sls")
             (link "d/.#y.ss" "nowhere") (dir "d/z.ss"))
           (lambda (dir) (relative dir (stray-files dir)))))

(test-equal "every stray file is named, in order"
  '("a/b.sch" "a/c.ss" "z.so")
  (in-tree '((file "a/b.sch") (file "a/c.ss") (file "a/ok.sls") (file "z.so"))
           (lambda (dir) (relative dir (stray-files dir)))))

;; --- the real tree ------------------------------------------------------------------

;; libraries : (Listof (Pairof String Any))
;; Each source under src/, with its first datum.
(define libraries
  (map (lambda (path) (cons path (first-datum path))) (sls-files "src")))

(define library-names (map (lambda (entry) (form-name (cdr entry))) libraries))

(test-equal "src/ holds no file Chez could load as a library but a .sls: no .ss, .scm, .sch, .so, .chezscheme.sls or .chezscheme.so"
  '()
  (stray-files "src"))

(test-equal "src/ defines (chez-sqlite3 private require-threaded)"
  'defined
  (if (member refusal-library library-names) 'defined 'absent))

;; The libraries named here. A scan of the wrong directory, or of an empty one,
;; finds none of them.
(test-equal "the scan read src/: counters and the refusal"
  '(read read)
  (map (lambda (name) (if (member name library-names) 'read 'missed))
       '((chez-sqlite3 private counters) (chez-sqlite3 private require-threaded))))

;; Every library but the refusal itself.
(define covered
  (filter (lambda (entry) (not (equal? (form-name (cdr entry)) refusal-library)))
          libraries))

(test-equal "the order rows are live: src/ holds a library besides the refusal"
  'live
  (if (null? covered) 'no-rows 'live))

(for-each
 (lambda (entry)
   (test-equal (string-append (car entry) " imports "
                              (written refusal-library)
                              " first")
     'first
     (verdict (cdr entry))))
 covered)

;; --- the refusal, as a --nothreads or an older Chez would expand it ------------------
;; No Chez here takes a refusing branch, so a refusal that stopped asking
;; (threaded?) or (scheme-version-number), asked it backwards, only printed,
;; or lost its message would pass every row above. These expand the refusal's
;; own source with eval: once as it is, once with each call (threaded?)
;; replaced by #f, and once for each version with each call
;; (scheme-version-number) replaced by that version's three numbers.

(define refusal-form
  (let ((entry (find (lambda (entry) (equal? (form-name (cdr entry)) refusal-library))
                     libraries)))
    (and entry (cdr entry))))

;; as-nonthreaded : Any -> Any
;; Replaces each element (threaded?) with #f. A call is always an element;
;; (only (chezscheme) threaded?) merely ends in a tail of the same shape.
(define (as-nonthreaded x)
  (if (list? x)
      (map (lambda (e) (if (equal? e '(threaded?)) #f (as-nonthreaded e))) x)
      x))

(define (threaded-calls x)
  (if (list? x)
      (fold-left + 0 (map (lambda (e)
                            (if (equal? e '(threaded?)) 1 (threaded-calls e)))
                          x))
      0))

;; as-version : Any (Listof Natural) (U Natural #f) -> Any
;; Replaces each element (scheme-version-number) with (values MAJOR MINOR
;; PATCH), what that procedure answers, and each element (scheme-version #t)
;; with the text it answers for that version: for a pre-release, PRE is its
;; number, else #f.
(define (as-version x version pre)
  (if (list? x)
      (map (lambda (e)
             (cond ((equal? e '(scheme-version-number)) (cons 'values version))
                   ((equal? e '(scheme-version #t)) (version-text version pre))
                   (else (as-version e version pre))))
           x)
      x))

;; version-text : (Listof Natural) (U Natural #f) -> String
;; What (scheme-version #t) answers.
(define (version-text version pre)
  (string-append "Chez Scheme Version "
                 (number->string (car version)) "."
                 (number->string (cadr version)) "."
                 (number->string (caddr version))
                 (if pre (string-append "-pre-release." (number->string pre)) "")))

;; calls-of : Any Any -> Natural
;; How many elements equal to CALL X holds, at any depth.
(define (calls-of call x)
  (if (list? x)
      (fold-left + 0 (map (lambda (e) (if (equal? e call) 1 (calls-of call e))) x))
      0))

;; expand-refusal : (U Any #f) (Listof Symbol) -> Any
;; Evaluates FORM, a library form, under the fresh NAME: loaded, or
;; (refused WHO MESSAGE) for a syntax violation, or else the text of what
;; was raised.
(define (expand-refusal form name)
  (if (library-form? form)
      (guard (e ((and (syntax-violation? e) (who-condition? e) (message-condition? e))
                 (list 'refused (condition-who e) (condition-message e)))
                (#t (describe e)))
        (eval (cons 'library (cons name (cddr form))) (interaction-environment))
        'loaded)
      'no-refusal-source))

(test-equal "the refusal exports nothing"
  '()
  (if (library-form? refusal-form) (form-exports refusal-form) 'no-refusal-source))

(test-equal "the refusal asks (threaded?)"
  'asks
  (if (and refusal-form (> (threaded-calls refusal-form) 0)) 'asks 'never-asks))

(test-equal "on this threaded Chez, the refusal lets its library load"
  'loaded
  (expand-refusal refusal-form '(require-threaded as-it-is)))

;; The whole text, as written by hand: a message cut anywhere, or a line lost
;; from it, fails.
(test-equal "where (threaded?) is #f, the refusal raises its whole message at expansion"
  '(refused chez-sqlite3
            "chez-sqlite3 needs a threaded Chez Scheme, and (threaded?) is #f in this one. Chez builds threaded unless configured with --nothreads")
  (expand-refusal (and refusal-form (as-nonthreaded refusal-form))
                  '(require-threaded as-nonthreaded)))

;; The floor is Chez 10.4.0, threaded (ADR-0001), written in
;; packaging/floors.sexp. Each expected message is the whole text, naming the
;; floor, as that file writes it, and the version that was refused.
;; refused-below-floor : String -> (List 'refused Symbol (U String Symbol))
;; What expand-refusal answers for a Chez whose version reads FOUND. The
;; message is a symbol when the floors file cannot give the floor: the row
;; fails by name, and nothing raises in an expected expression.
(define (refused-below-floor found)
  (list 'refused 'chez-sqlite3
        (if (and (string? chez-floor-text) (string? found))
            (string-append "chez-sqlite3 needs Chez Scheme " chez-floor-text
                           " or later, and this one is " found)
            'floors-file-unreadable)))

(test-equal "the refusal asks (scheme-version-number)"
  'asks
  (if (and refusal-form (> (calls-of '(scheme-version-number) refusal-form) 0)) 'asks 'never-asks))

(test-equal "the refusal asks (scheme-version #t), which says whether this Chez is a pre-release"
  'asks
  (if (and refusal-form (> (calls-of '(scheme-version #t) refusal-form) 0)) 'asks 'never-asks))

;; A row is the version, the pre-release number or #f, and what the message
;; says this Chez is. A pre-release is named only at the floor, where it
;; decides the matter: below it, the version refuses on its own.
(for-each
 (lambda (row)
   (let ((version (car row)) (pre (cadr row)) (said (caddr row)))
     (test-equal (string-append "where Chez is " (version-text version pre)
                                ", the refusal raises its message naming the floor")
       (refused-below-floor said)
       (expand-refusal (and refusal-form (as-version refusal-form version pre))
                       '(require-threaded below-floor)))))
 '(((10 3 0) #f "10.3.0")
   ((9 5 9) #f "9.5.9")
   ((10 3 9) #f "10.3.9")
   ((10 3 0) 2 "10.3.0")
   ;; A pre-release is before its own release, so before the floor.
   ((10 4 0) 1 "10.4.0-pre-release.1")
   ((10 4 0) 7 "10.4.0-pre-release.7")
   ((10 4 0) 12 "10.4.0-pre-release.12")))

(for-each
 (lambda (row)
   (let ((version (car row)) (pre (cadr row)))
     (test-equal (string-append "where Chez is " (version-text version pre)
                                ", the refusal lets its library load")
       'loaded
       (expand-refusal (and refusal-form (as-version refusal-form version pre))
                       '(require-threaded at-floor)))))
 '(((10 4 0) #f)
   ((10 5 1) #f)
   ((11 0 0) #f)
   ;; The numbers are compared as numbers: as text, "10.10.0" sorts before "10.4.0".
   ((10 10 0) #f)
   ;; A pre-release of a later version is after the floor.
   ((10 4 1) 1)
   ((10 5 0) 1)
   ((11 0 0) 3)))

;; --- the floor of packaging/floors.sexp -----------------------------------------------
;; These rows take the floor from the file, so they move with it, and a refusal
;; that still holds another floor fails them. The rows above name 10.4.0.

;; dotted : (Listof Natural) -> String
(define (dotted version)
  (let loop ((rest (cdr version)) (text (number->string (car version))))
    (if (null? rest)
        text
        (loop (cdr rest) (string-append text "." (number->string (car rest)))))))

;; floor-after : Natural -> (U (Listof Natural) Symbol)
;; The floor with its number at INDEX one higher and the numbers after it
;; zero: the nearest version after the floor that changes that number. A
;; symbol when the floors file is unreadable.
(define (floor-after index)
  (if (list? chez-floor)
      (let loop ((rest chez-floor) (i 0))
        (cond ((null? rest) '())
              ((< i index) (cons (car rest) (loop (cdr rest) (+ i 1))))
              ((= i index) (cons (+ (car rest) 1) (loop (cdr rest) (+ i 1))))
              (else (cons 0 (loop (cdr rest) (+ i 1))))))
      'floors-file-unreadable))

;; floor-major-below : (U (Listof Natural) Symbol)
;; The floor with its major number one lower, and the rest as it is. A symbol
;; when the floors file is unreadable, or the major number is zero.
(define floor-major-below
  (if (and (list? chez-floor) (> (car chez-floor) 0))
      (cons (- (car chez-floor) 1) (cdr chez-floor))
      'no-version-below))

;; expand-at : (U (Listof Natural) Symbol) (U Natural #f) (Listof Symbol) -> Any
;; expand-refusal for a Chez that reports VERSION, or a symbol when VERSION is
;; no version.
(define (expand-at version pre name)
  (if (and (list? version) (= (length version) 3) (for-all integer? version))
      (expand-refusal (and refusal-form (as-version refusal-form version pre)) name)
      'no-such-version))

(test-equal "where Chez is the floor of packaging/floors.sexp, the refusal lets its library load"
  'loaded
  (expand-at chez-floor #f '(require-threaded at-file-floor)))

(for-each
 (lambda (pre)
   (test-equal (string-append "where Chez is a pre-release of the floor of packaging/floors.sexp, number "
                              (number->string pre) ", the refusal raises its message naming the floor")
     (refused-below-floor
      (if (string? chez-floor-text)
          (string-append chez-floor-text "-pre-release." (number->string pre))
          'floors-file-unreadable))
     (expand-at chez-floor pre '(require-threaded pre-release-of-file-floor))))
 '(1 7 12))

(for-each
 (lambda (row)
   (test-equal (string-append "where Chez is one step after the floor of packaging/floors.sexp, in its "
                              (cadr row) " number, the refusal lets its library load")
     'loaded
     (expand-at (floor-after (car row)) #f '(require-threaded after-file-floor))))
 '((0 "major") (1 "minor") (2 "patch")))

(test-equal "where Chez's major number is one below the floor of packaging/floors.sexp, the refusal raises its message naming the floor"
  (refused-below-floor
   (if (list? floor-major-below) (dotted floor-major-below) 'no-such-version))
  (expand-at floor-major-below #f '(require-threaded below-file-floor)))

(test-end "require-threaded")

(exit (suite-exit-status runner))
