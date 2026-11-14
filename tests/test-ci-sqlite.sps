#!r6rs
;;; The suite for scripts/ci/check-sqlite.sh and scripts/ci/build-sqlite.sh,
;;; the two scripts behind CI's floor and current lanes: they build SQLite
;;; from sqlite.org's source, and check what was built before any suite runs
;;; on it (ADR-0003, decision 3; ADR-0005; ADR-0008).
;;;
;;; Both scripts find packaging/floors.sexp from their own place, through
;;; scripts/ci/floor.sh, so every row runs a copy of scripts/ci in a fresh
;;; tree whose floors file is the row's own, as test-check-floors' floor.sh
;;; and check-chez.sh rows do. The rows run the scripts with sh, not by their
;;; own names, so a lost execute bit is not what they find. Each row asserts
;;; the script's exit status, its whole stdout and its whole stderr, written
;;; here by hand, never read back from the scripts.
;;;
;;;   - check-sqlite.sh: each row compiles, with $CC, a stub
;;;     PREFIX/lib/libsqlite3.so.0 that answers the row's version, number,
;;;     source id, threadsafe and compile options, and writes a
;;;     PREFIX/include/sqlite3.h that defines the row's three macros. The
;;;     base row's floor is 8.1.2, a version no SQLite has, so a version
;;;     written in the script fails it. Its options are the floor's 37 lines
;;;     and the current release's 38, written here as a reviewed copy of
;;;     what SQLite, built with build-sqlite.sh's flags, lists (the slice's
;;;     log), with the COMPILER= entry this suite computes from $CC's own
;;;     macros, by another route than the script's. Every other row is one
;;;     edit of a passing row, and names what it breaks;
;;;   - build-sqlite.sh: each row puts a shim/ directory first on PATH,
;;;     whose curl, openssl and tar are POSIX sh scripts that log each call,
;;;     and a CC that logs its own and builds nothing. PATH holds nothing
;;;     else but links to the tools the scripts need, so a row can leave one
;;;     out. Each row asserts the calls, whole and in order, besides the
;;;     output: a download, a digest, an unpack and a compile, each in its
;;;     place or never. The pins are literals here, a reviewed copy of the
;;;     script's.
;;;
;;; The children are sh, the C compiler, the shims and, through
;;; check-sqlite.sh, a Chez that runs the script's own probe on a stub. None
;;; reaches chez-sqlite3's code, which is what the memory gate holds, and a
;;; shell cannot run under it: the gate requires a child's Command: to be
;;; Chez or the oracle. So they run outside it, through capture-command, as
;;; test-check-floors' check-chez.sh rows do (ADR-0005, amended).
;;;
;;; Each computation that can raise runs under a guard that names what was
;;; raised, since SRFI-64 turns a raise in the actual expression into #f and
;;; does not catch one in the expected expression. No expected value is #f.
;;; Effects run in order, through let*, named lets and for-each, never map.
(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
        (only (floors) read-floors floor-numbers)
        (only (libsqlite3-oracle) c-compiler)
        (only (chezscheme) directory-list getenv))

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

;; outcome : (-> Any) -> (U (List 'returned Any) (List 'raised String))
;; What THUNK did: returned a value, or raised, and what.
(define (outcome thunk)
  (guard (e (#t (list 'raised (describe e))))
    (list 'returned (thunk))))

(test-begin "ci-sqlite")

;; --- what the rows run -----------------------------------------------------------------

(define (set? value) (and (string? value) (not (string=? value ""))))

;; The Makefile exports CHEZ, and check-sqlite.sh reads the library through
;; it. Without it nothing below can run: fail, never skip.
(define chez (getenv "CHEZ"))

(test-equal "CHEZ names the Chez that check-sqlite.sh runs its probe with"
  'set
  (if (set? chez) 'set 'unset))

(unless (set? chez)
  (exit 1))

;; The scripts read CC as one word, ${CC:-cc}, as report-sqlite.sh does.
(define cc-words (c-compiler getenv))

(test-equal "CC is one word, as the scripts read it"
  1
  (length cc-words))

(unless (= (length cc-words) 1)
  (exit 1))

(define cc (car cc-words))

;; --- strings -------------------------------------------------------------------------

(define (string-prefix? prefix s)
  (let ((n (string-length s)) (m (string-length prefix)))
    (and (>= n m) (string=? (substring s 0 m) prefix))))

;; q : String -> String
;; S in double quotes.
(define (q s) (string-append "\"" s "\""))

;; text-of : (Listof String) -> String
;; LINES, each ended by a newline.
(define (text-of lines)
  (apply string-append (map (lambda (line) (string-append line "\n")) lines)))

;; indented : (Listof String) -> String
(define (indented lines)
  (apply string-append (map (lambda (line) (string-append "  " line "\n")) lines)))

;; text-lines : String -> (Listof String)
;; TEXT cut at each newline; a last line without one is kept.
(define (text-lines text)
  (let loop ((chars (string->list text)) (line '()) (found '()))
    (cond ((null? chars)
           (reverse (if (null? line) found (cons (list->string (reverse line)) found))))
          ((char=? (car chars) #\newline)
           (loop (cdr chars) '() (cons (list->string (reverse line)) found)))
          (else (loop (cdr chars) (cons (car chars) line) found)))))

;; --- the compiler's own COMPILER= entry ---------------------------------------------------
;;
;; SQLite lists the compiler that built it among its compile options: clang's
;; major, minor and patch level when __clang__ and __clang_major__ are
;; defined, else MSVC's _MSC_VER, else gcc's __VERSION__ (sqlite3.c's ctime.c,
;; at both versions the lanes build). The scripts compute it by stringifying
;; those macros through $CC -E, as SQLite does. This suite reads them another
;; way, from the definitions $CC -dM -E lists, so a row's expected entry is
;; not the script's own answer.

;; defines : String -> (Listof (Pairof String String))
;; Each "#define NAME VALUE" line of TEXT as (NAME . VALUE), VALUE "" when
;; there is none.
(define (defines text)
  (let loop ((lines (text-lines text)) (found '()))
    (if (null? lines)
        (reverse found)
        (let ((line (car lines)) (head "#define "))
          (if (string-prefix? head line)
              (let* ((rest (substring line (string-length head) (string-length line)))
                     (space (let scan ((i 0))
                              (cond ((= i (string-length rest)) #f)
                                    ((char=? (string-ref rest i) #\space) i)
                                    (else (scan (+ i 1)))))))
                (loop (cdr lines)
                      (cons (if space
                                (cons (substring rest 0 space)
                                      (substring rest (+ space 1) (string-length rest)))
                                (cons rest ""))
                            found)))
              (loop (cdr lines) found))))))

;; unquoted : String -> String
;; A C string literal's text, when S is one with no quote or backslash inside;
;; otherwise a raise.
(define (unquoted s)
  (let ((n (string-length s)))
    (if (and (>= n 2)
             (char=? (string-ref s 0) #\")
             (char=? (string-ref s (- n 1)) #\")
             (not (memv #\" (string->list (substring s 1 (- n 1)))))
             (not (memv #\\ (string->list s))))
        (substring s 1 (- n 1))
        (error 'unquoted "not a plain C string literal" s))))

;; compiler-option : (U String 'none (List Symbol Any))
;; The COMPILER= entry SQLite built with $CC lists, 'none when it lists none,
;; or what went wrong.
(define compiler-option
  (guard (e (#t (list 'raised (describe e))))
    (let ((answer (capture-command (append cc-words '("-dM" "-E" "-x" "c" "/dev/null")))))
      (if (not (eqv? (car answer) 0))
          (list 'cc answer)
          (let* ((macros (defines (cadr answer)))
                 (value (lambda (name) (cond ((assoc name macros) => cdr) (else #f)))))
            (cond ((and (value "__clang__") (value "__clang_major__"))
                   (string-append "COMPILER=clang-" (value "__clang_major__") "."
                                  (value "__clang_minor__") "." (value "__clang_patchlevel__")))
                  ((value "_MSC_VER") (string-append "COMPILER=msvc-" (value "_MSC_VER")))
                  ((and (value "__GNUC__") (value "__VERSION__"))
                   (string-append "COMPILER=gcc-" (unquoted (value "__VERSION__"))))
                  (else 'none)))))))

(test-equal "CC's predefined macros give the COMPILER= entry SQLite would list, or none"
  'computed
  (if (or (string? compiler-option) (eq? compiler-option 'none)) 'computed compiler-option))

;; with-compiler : (Listof (U String 'compiler)) -> (Listof String)
;; OPTIONS with the symbol compiler replaced by compiler-option, or dropped
;; when SQLite would list none.
(define (with-compiler options)
  (fold-right (lambda (option rest)
                (cond ((not (eq? option 'compiler)) (cons option rest))
                      ((string? compiler-option) (cons compiler-option rest))
                      (else rest)))
              '()
              options))

;; --- the pins, a reviewed copy -----------------------------------------------------------
;;
;; What SQLite's release logs publish for the two builds the lanes make
;; (https://sqlite.org/releaselog/X_Y_Z.html), and the compile options each
;; lists when built with build-sqlite.sh's flags, in SQLite's order, as the
;; slice's log measured them through the FFI.

(define floor-source-id
  "2024-01-30 16:01:20 e876e51a0ed5c5b3126f52e532044363a014bc594cfefa87ffb5b82257cc467a")

(define current-version "3.54.1")
(define current-number 3054001)
(define current-source-id
  "2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76")

(define floor-options
  (with-compiler
   '("ATOMIC_INTRINSICS=1"
     compiler
     "DEFAULT_AUTOVACUUM"
     "DEFAULT_CACHE_SIZE=-2000"
     "DEFAULT_FILE_FORMAT=4"
     "DEFAULT_JOURNAL_SIZE_LIMIT=-1"
     "DEFAULT_MMAP_SIZE=0"
     "DEFAULT_PAGE_SIZE=4096"
     "DEFAULT_PCACHE_INITSZ=20"
     "DEFAULT_RECURSIVE_TRIGGERS"
     "DEFAULT_SECTOR_SIZE=4096"
     "DEFAULT_SYNCHRONOUS=2"
     "DEFAULT_WAL_AUTOCHECKPOINT=1000"
     "DEFAULT_WAL_SYNCHRONOUS=2"
     "DEFAULT_WORKER_THREADS=0"
     "DIRECT_OVERFLOW_READ"
     "MALLOC_SOFT_LIMIT=1024"
     "MAX_ATTACHED=10"
     "MAX_COLUMN=2000"
     "MAX_COMPOUND_SELECT=500"
     "MAX_DEFAULT_PAGE_SIZE=8192"
     "MAX_EXPR_DEPTH=1000"
     "MAX_FUNCTION_ARG=127"
     "MAX_LENGTH=1000000000"
     "MAX_LIKE_PATTERN_LENGTH=50000"
     "MAX_MMAP_SIZE=0x7fff0000"
     "MAX_PAGE_COUNT=0xfffffffe"
     "MAX_PAGE_SIZE=65536"
     "MAX_SQL_LENGTH=1000000000"
     "MAX_TRIGGER_DEPTH=1000"
     "MAX_VARIABLE_NUMBER=32766"
     "MAX_VDBE_OP=250000000"
     "MAX_WORKER_THREADS=8"
     "MUTEX_PTHREADS"
     "SYSTEM_MALLOC"
     "TEMP_STORE=1"
     "THREADSAFE=1")))

(define current-options
  (with-compiler
   '("ATOMIC_INTRINSICS=1"
     compiler
     "DEFAULT_AUTOVACUUM"
     "DEFAULT_CACHE_SIZE=-2000"
     "DEFAULT_FILE_FORMAT=4"
     "DEFAULT_JOURNAL_SIZE_LIMIT=-1"
     "DEFAULT_MMAP_SIZE=0"
     "DEFAULT_PAGE_SIZE=4096"
     "DEFAULT_PCACHE_INITSZ=20"
     "DEFAULT_RECURSIVE_TRIGGERS"
     "DEFAULT_SECTOR_SIZE=4096"
     "DEFAULT_SYNCHRONOUS=2"
     "DEFAULT_WAL_AUTOCHECKPOINT=1000"
     "DEFAULT_WAL_SYNCHRONOUS=2"
     "DEFAULT_WORKER_THREADS=0"
     "DIRECT_OVERFLOW_READ"
     "MALLOC_SOFT_LIMIT=1024"
     "MAX_ATTACHED=10"
     "MAX_COLUMN=2000"
     "MAX_COMPOUND_SELECT=500"
     "MAX_DEFAULT_PAGE_SIZE=8192"
     "MAX_EXPR_DEPTH=1000"
     "MAX_FUNCTION_ARG=1000"
     "MAX_LENGTH=1000000000"
     "MAX_LIKE_PATTERN_LENGTH=50000"
     "MAX_MMAP_SIZE=0x7fff0000"
     "MAX_PAGE_COUNT=0xfffffffe"
     "MAX_PAGE_SIZE=65536"
     "MAX_SCHEMA=10000000"
     "MAX_SQL_LENGTH=1000000000"
     "MAX_TRIGGER_DEPTH=1000"
     "MAX_VARIABLE_NUMBER=32766"
     "MAX_VDBE_OP=250000000"
     "MAX_WORKER_THREADS=8"
     "MUTEX_PTHREADS"
     "SYSTEM_MALLOC"
     "TEMP_STORE=1"
     "THREADSAFE=1")))

(test-equal "the copies hold 37 and 38 lines, the COMPILER= entry among them when SQLite lists one"
  (if (string? compiler-option) '(37 38) '(36 37))
  (list (length floor-options) (length current-options)))

;; --- trees ---------------------------------------------------------------------------

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

;; floors-text : String -> String
;; A floors file whose SQLite floor is SQLITE. Its Chez floor is no real one:
;; neither script reads it.
(define (floors-text sqlite)
  (string-append "((chez \"9.8.7\")\n (sqlite \"" sqlite "\"))\n"))

;; with-tree : (U String #f) (String -> Any) -> Any
;; PROC on ROOT, a fresh directory holding a copy of the real scripts/ci
;; and a packaging/floors.sexp with FLOORS-TEXT, or none for #f.
(define (with-tree floors-text proc)
  (call-with-temp-directory
   (lambda (root)
     (checked "mkdir" (list "mkdir" "-p" (string-append root "/scripts")
                            (string-append root "/packaging")))
     (checked "cp" (list "cp" "-R" "scripts/ci" (string-append root "/scripts/ci")))
     (when floors-text
       (write-file (string-append root "/packaging/floors.sexp") floors-text))
     (proc root))))

;; env-order : (Listof String) -> (Listof String)
;; ENV-ARGS with every -u NAME pair first, then each NAME=VALUE, each group in
;; its own order: env reads -u only before the first assignment (traps.md).
(define (env-order env-args)
  (let loop ((rest env-args) (unsets '()) (sets '()))
    (cond ((null? rest) (append (reverse unsets) (reverse sets)))
          ((and (string=? (car rest) "-u") (pair? (cdr rest)))
           (loop (cddr rest) (cons* (cadr rest) "-u" unsets) sets))
          (else (loop (cdr rest) unsets (cons (car rest) sets))))))

;; --- check-sqlite.sh: the stub and its header ------------------------------------------------
;;
;; A Lib is (list VERSION NUMBER SOURCE-ID THREADSAFE OPTIONS): what the stub
;; answers to sqlite3_libversion, sqlite3_libversion_number, sqlite3_sourceid,
;; sqlite3_threadsafe and sqlite3_compileoption_get, which answers NULL after
;; the last option. A Header is (list VERSION NUMBER SOURCE-ID), the C text of
;; each of its three #defines.

(define floor-lib (list "8.1.2" 8001002 floor-source-id 1 floor-options))
(define floor-header (list (q "8.1.2") "8001002" (q floor-source-id)))
(define current-lib (list current-version current-number current-source-id 1 current-options))
(define current-header (list (q current-version) (number->string current-number) (q current-source-id)))

;; c-string : String -> String
;; S as a C string literal.
(define (c-string s)
  (call-with-string-output-port
   (lambda (p)
     (put-char p #\")
     (string-for-each (lambda (c)
                        (when (memv c '(#\" #\\)) (put-char p #\\))
                        (put-char p c))
                      s)
     (put-char p #\"))))

;; stub-source : Lib -> String
(define (stub-source lib)
  (let ((options (list-ref lib 4)))
    (string-append
     "static const char *const options[] = {\n"
     (apply string-append (map (lambda (option) (string-append "  " (c-string option) ",\n")) options))
     "  0\n};\n"
     "const char *sqlite3_libversion(void) { return " (c-string (list-ref lib 0)) "; }\n"
     "int sqlite3_libversion_number(void) { return " (number->string (list-ref lib 1)) "; }\n"
     "const char *sqlite3_sourceid(void) { return " (c-string (list-ref lib 2)) "; }\n"
     "int sqlite3_threadsafe(void) { return " (number->string (list-ref lib 3)) "; }\n"
     "const char *sqlite3_compileoption_get(int n) {\n"
     "  return n >= 0 && n < " (number->string (length options)) " ? options[n] : 0;\n"
     "}\n")))

;; make-library! : String String Lib -> (U 0 (List 'compile Any))
;; The stub LIB, compiled with $CC as DIR/libsqlite3.so.0, from ROOT/stub.c:
;; 0, or the compiler's whole answer.
(define (make-library! root dir lib)
  (let ((source (string-append root "/stub.c")))
    (checked "mkdir" (list "mkdir" "-p" dir))
    (write-file source (stub-source lib))
    (let ((answer (capture-command
                   (append cc-words (list "-Wall" "-Werror" "-shared" "-fPIC"
                                          "-o" (string-append dir "/libsqlite3.so.0") source)))))
      (if (eqv? (car answer) 0) 0 (list 'compile answer)))))

;; header-text : Header -> String
(define (header-text header)
  (string-append "#define SQLITE_VERSION        " (list-ref header 0) "\n"
                 "#define SQLITE_VERSION_NUMBER " (list-ref header 1) "\n"
                 "#define SQLITE_SOURCE_ID      " (list-ref header 2) "\n"))

;; --- check-sqlite.sh: the rows ---------------------------------------------------------
;;
;; A Spec is an association list: floors (the tree's floors text, or #f), lib
;; (a Lib, or none for no library file), header (a Header, or none), args and
;; env (each a procedure of the tree's root and PREFIX, giving the script's
;; arguments and env's NAME=VALUE and -u NAME words), and setup (a procedure
;; of the same two, run after the stub is made: 0, or what went wrong).

(define (lib-path prefix) (string-append prefix "/lib/libsqlite3.so.0"))
(define (header-path prefix) (string-append prefix "/include/sqlite3.h"))

;; lane-env : String String -> (Listof String)
;; The environment a lane's check step gives: the override and the header's
;; directory naming PREFIX's, as CI's env does, and this suite's CC and CHEZ.
;; CPATH, which the compiler searches before C_INCLUDE_PATH, is unset.
(define (lane-env root prefix)
  (list (string-append "CHEZ_SQLITE3_LIBRARY=" (lib-path prefix))
        (string-append "C_INCLUDE_PATH=" prefix "/include")
        (string-append "CC=" cc)
        (string-append "CHEZ=" chez)
        "-u" "CPATH"))

;; env-with : String (U (String String -> String) #f) -> (String String -> (Listof String))
;; lane-env with NAME set to what VALUE gives, or unset for #f.
(define (env-with name value)
  (lambda (root prefix)
    (let ((others (filter (lambda (word) (not (string-prefix? (string-append name "=") word)))
                          (lane-env root prefix))))
      (if value
          (cons (string-append name "=" (value root prefix)) others)
          (cons* "-u" name others)))))

;; env-plus : String ... -> (String String -> (Listof String))
;; lane-env with the NAME=VALUE words ASSIGNMENTS too.
(define (env-plus . assignments)
  (lambda (root prefix) (append (lane-env root prefix) assignments)))

(define floor-spec
  (list (cons 'floors (floors-text "8.1.2"))
        (cons 'lib floor-lib)
        (cons 'header floor-header)
        (cons 'args (lambda (root prefix) (list prefix)))
        (cons 'env lane-env)
        (cons 'setup (lambda (root prefix) 0))))

(define current-spec
  (append (list (cons 'floors #f)
                (cons 'lib current-lib)
                (cons 'header current-header)
                (cons 'args (lambda (root prefix) (list prefix "--current"))))
          floor-spec))

;; spec-with : Spec Symbol Any ... -> Spec
;; SPEC with each KEY given its VALUE.
(define (spec-with spec . changes)
  (let loop ((rest changes) (spec spec))
    (if (null? rest)
        spec
        (loop (cddr rest) (cons (cons (car rest) (cadr rest)) spec)))))

(define (spec-ref spec key) (cdr (assq key spec)))

;; make-prefix! : String String Spec -> (U 0 Any)
;; PREFIX as SPEC has it: the stub, the header, then SPEC's setup.
(define (make-prefix! root prefix spec)
  (let* ((lib (spec-ref spec 'lib))
         (built (if (eq? lib 'none) 0 (make-library! root (string-append prefix "/lib") lib))))
    (cond ((not (eqv? built 0)) built)
          (else
           (let ((header (spec-ref spec 'header)))
             (unless (eq? header 'none)
               (write-file-in prefix "include/sqlite3.h" (header-text header))))
           ((spec-ref spec 'setup) root prefix)))))

;; matches? : Answer (U Answer (Pairof 'either (Listof Answer))) -> Boolean
(define (matches? got want)
  (if (and (pair? want) (eq? (car want) 'either))
      (and (member got (cdr want)) #t)
      (equal? got want)))

;; check-row : String Spec (String String -> Expected) -> Unit
;; In a tree and a PREFIX made as SPEC says, sh scripts/ci/check-sqlite.sh
;; with SPEC's arguments, under env with SPEC's words, must answer what
;; EXPECTED-OF gives for the tree's root and PREFIX: its exit status, whole
;; stdout and whole stderr.
(define (check-row name spec expected-of)
  (test-equal (string-append "check-sqlite.sh: " name)
    '(returned same)
    (outcome (lambda () (check-run spec expected-of)))))

;; check-run : Spec (String String -> Expected) -> (U 'same (List ...))
;; What check-row asserts, unguarded: its caller guards it, so that a raise in
;; building SPEC, which a caller may leave to this call, fails the row.
(define (check-run spec expected-of)
  (with-tree (spec-ref spec 'floors)
    (lambda (root)
      (let* ((prefix (string-append root "/prefix"))
             (made (make-prefix! root prefix spec)))
        (if (not (eqv? made 0))
            (list 'setup made)
            (let* ((got (capture-command
                         (append (list "env")
                                 (env-order ((spec-ref spec 'env) root prefix))
                                 (list "sh" (string-append root "/scripts/ci/check-sqlite.sh"))
                                 ((spec-ref spec 'args) root prefix))))
                   (want (expected-of root prefix)))
              (if (matches? got want) 'same (list 'got got 'want want))))))))

;; --- check-sqlite.sh: what it answers, written by hand ---------------------------------------

(define floor-role "the SQLite floor")
(define current-role "the pinned current SQLite")

;; passes : String String Natural String String (Listof String) -> Expected
(define (passes prefix version number source-id role options)
  (passes-by cc prefix version number source-id role options))

;; passes-by : String String String Natural String String (Listof String) -> Expected
;; The same, for a check run with the compiler CC-NAME.
(define (passes-by cc-name prefix version number source-id role options)
  (list 0
        (string-append
         "check-sqlite.sh: " (lib-path prefix) " is SQLite " version " (" (number->string number)
         "), source id " source-id ": " role "\n"
         "check-sqlite.sh: it is threadsafe (1), and its " (number->string (length options))
         " compile options are " role "'s, line for line:\n"
         (indented options)
         "check-sqlite.sh: " cc-name " finds <sqlite3.h> at " (header-path prefix)
         ", which declares the same release, and CHEZ_SQLITE3_LIBRARY names the library\n")
        ""))

(define (floor-passes prefix)
  (passes prefix "8.1.2" 8001002 floor-source-id floor-role floor-options))

(define (current-passes prefix)
  (passes prefix current-version current-number current-source-id current-role current-options))

;; refused : String ... -> Expected
(define (refused . words)
  (list 1 "" (string-append "check-sqlite.sh: " (apply string-append words) "\n")))

;; identity : String Natural String -> String
(define (identity version number source-id)
  (string-append (q version) ", " (number->string number) " and " (q source-id)))

(define floor-identity (identity "8.1.2" 8001002 floor-source-id))
(define current-identity (identity current-version current-number current-source-id))

(define (library-refused prefix answered role wanted)
  (refused (lib-path prefix) " answers " answered
           " to sqlite3_libversion(), sqlite3_libversion_number() and sqlite3_sourceid(), but "
           role " is " wanted))

(define (header-refused prefix header role wanted)
  (refused (header-path prefix) " defines SQLITE_VERSION " (list-ref header 0)
           ", SQLITE_VERSION_NUMBER " (list-ref header 1)
           " and SQLITE_SOURCE_ID " (list-ref header 2) ", but " role " is " wanted))

(define (threadsafe-refused prefix answer)
  (refused (lib-path prefix) " answers " (number->string answer)
           " to sqlite3_threadsafe(), but a lane's SQLite must answer 1: serialized, SQLite's default"))

(define (library-env-refused prefix how)
  (refused "CHEZ_SQLITE3_LIBRARY is " how ", but must be " (lib-path prefix)
           ", the library this checks, so that make build and make test load it"))

(define (header-elsewhere prefix found)
  (refused cc " finds <sqlite3.h> at " found ", not " (header-path prefix)
           ": C_INCLUDE_PATH must name " prefix "/include first, so that the suites compile against the library's own header"))

;; options-refused : String Natural String String -> Expected
;; The refusal of a library whose options differ, DIFF being diff -u's
;; hunks, with its two file lines.
(define (options-refused prefix count role diff)
  (list 1 ""
        (string-append "check-sqlite.sh: " (lib-path prefix) "'s compile options are not the "
                       (number->string count) " of " role ", line for line:\n"
                       diff)))

;; --- check-sqlite.sh: one edit of a list, and its diff -----------------------------------------
;;
;; Each edit below changes one place of a list of options. hunk writes the
;; diff -u of the list against the edited one, as GNU and BSD diff write a
;; single change, three lines of context on each side, with the script's two
;; file lines: what the script prints, written here from the edit, not by
;; running diff.

(define (sublist items from to)
  (let loop ((i 0) (rest items) (found '()))
    (cond ((or (null? rest) (>= i to)) (reverse found))
          ((>= i from) (loop (+ i 1) (cdr rest) (cons (car rest) found)))
          (else (loop (+ i 1) (cdr rest) found)))))

;; position : String (Listof String) -> Natural
;; Where ITEM is in ITEMS; a raise when it is not there.
(define (position item items)
  (let loop ((i 0) (rest items))
    (cond ((null? rest) (error 'position "not in the list" item))
          ((string=? (car rest) item) i)
          (else (loop (+ i 1) (cdr rest))))))

;; hunk : (Listof String) Natural Natural (Listof (Pairof Char String)) -> String
;; The diff -u of OLD against a list that differs from it only where OLD's
;; K lines from index I are, which BODY shows: #\- a line of OLD's dropped,
;; #\+ a line added, #\space a line both keep.
(define (hunk old i k body)
  (let* ((n (length old))
         (from (max 0 (- i 3)))
         (before (sublist old from i))
         (after (sublist old (+ i k) (min n (+ i k 3))))
         (marked (lambda (marks)
                   (length (filter (lambda (entry) (memv (car entry) marks)) body))))
         (old-count (+ (length before) (marked '(#\- #\space)) (length after)))
         (new-count (+ (length before) (marked '(#\+ #\space)) (length after))))
    (string-append
     "--- expected\n+++ library\n"
     "@@ -" (number->string (+ from 1)) "," (number->string old-count)
     " +" (number->string (+ from 1)) "," (number->string new-count) " @@\n"
     (apply string-append (map (lambda (line) (string-append " " line "\n")) before))
     (apply string-append (map (lambda (entry) (string-append (string (car entry)) (cdr entry) "\n"))
                               body))
     (apply string-append (map (lambda (line) (string-append " " line "\n")) after)))))

;; An Edit is (list OPTIONS DIFF): the edited list, and its diff from the
;; original, or (list OPTIONS (either DIFF DIFF)) when two diffs are minimal.

(define (inserted items at new)
  (let ((i (if (eq? at 'end) (length items) (position at items))))
    (list (append (sublist items 0 i) (list new) (sublist items i (length items)))
          (hunk items i 0 (list (cons #\+ new))))))

(define (dropped items old)
  (let ((i (position old items)))
    (list (append (sublist items 0 i) (sublist items (+ i 1) (length items)))
          (hunk items i 1 (list (cons #\- old))))))

(define (replaced items old new)
  (let ((i (position old items)))
    (list (append (sublist items 0 i) (list new) (sublist items (+ i 1) (length items)))
          (hunk items i 1 (list (cons #\- old) (cons #\+ new))))))

;; swapped : (Listof String) String -> Edit
;; OLD and the line after it swapped. A diff keeps one of the two: GNU's
;; drops the first and adds it after the second; another may add the second
;; before the first and drop it after.
(define (swapped items old)
  (let* ((i (position old items))
         (next (list-ref items (+ i 1))))
    (list (append (sublist items 0 i) (list next old) (sublist items (+ i 2) (length items)))
          (list 'either
                (hunk items i 2 (list (cons #\- old) (cons #\space next) (cons #\+ old)))
                (hunk items i 2 (list (cons #\+ next) (cons #\space old) (cons #\- next)))))))

;; options-row : String Spec (-> Edit) String -> Unit
;; check-row on SPEC with its library's options replaced by EDIT-OF's, refused
;; with its diff, against the count of SPEC's own options under ROLE. EDIT-OF is
;; a thunk, run inside the row's guard: an edit that names an option not in the
;; list raises there, and fails the row by name.
(define (options-row name spec edit-of role)
  (test-equal (string-append "check-sqlite.sh: " name)
    '(returned same)
    (outcome
     (lambda ()
       (let* ((edit (edit-of))
              (lib (spec-ref spec 'lib))
              (count (length (list-ref lib 4)))
              (edited (list (list-ref lib 0) (list-ref lib 1) (list-ref lib 2) (list-ref lib 3) (car edit))))
         (check-run (spec-with spec 'lib edited)
                    (lambda (root prefix)
                      (let ((diff (cadr edit)))
                        (if (and (pair? diff) (eq? (car diff) 'either))
                            (cons 'either (map (lambda (d) (options-refused prefix count role d)) (cdr diff)))
                            (options-refused prefix count role diff))))))))))

;; with-lib : Lib Integer Any -> Lib
;; LIB with its I-th field VALUE.
(define (with-lib lib i value)
  (let loop ((j 0) (rest lib) (found '()))
    (if (null? rest)
        (reverse found)
        (loop (+ j 1) (cdr rest) (cons (if (= j i) value (car rest)) found)))))

(define (with-header header i value) (with-lib header i value))

;; last-changed : String -> String
;; S with its last character changed: a source id one character off.
(define (last-changed s)
  (let* ((n (string-length s)) (c (string-ref s (- n 1))))
    (string-append (substring s 0 (- n 1)) (if (char=? c #\0) "1" "0"))))

;; --- check-sqlite.sh: passes -------------------------------------------------------------

(check-row "the floor's library, its header and the lane's env pass, with the identity, every option and the header named"
  floor-spec
  (lambda (root prefix) (floor-passes prefix)))

(check-row "--current: the pinned release's library passes, with its 38 lines, in a tree with no floors file"
  current-spec
  (lambda (root prefix) (current-passes prefix)))

(check-row "--current: it passes whatever floor the tree has: the floors file is not read"
  (spec-with current-spec 'floors (floors-text "8.1.2"))
  (lambda (root prefix) (current-passes prefix)))

(check-row "the env names no version: version, number, source_id, floor_source_id and floor_options set to the next release's change nothing"
  (spec-with floor-spec 'env
             (env-plus "version=8.1.3" "number=8001003" "source_id=x" "floor_source_id=x"
                       "floor_options=x" "role=current"))
  (lambda (root prefix) (floor-passes prefix)))

;; --- check-sqlite.sh: the library's identity ------------------------------------------------

(check-row "a library answering 8.1.23, the floor's version with a digit after it, is refused"
  (spec-with floor-spec 'lib (with-lib floor-lib 0 "8.1.23"))
  (lambda (root prefix)
    (library-refused prefix (identity "8.1.23" 8001002 floor-source-id) floor-role floor-identity)))

(check-row "a library answering 8.1.3 is refused"
  (spec-with floor-spec 'lib (with-lib floor-lib 0 "8.1.3"))
  (lambda (root prefix)
    (library-refused prefix (identity "8.1.3" 8001002 floor-source-id) floor-role floor-identity)))

(check-row "a library whose number is one more than the floor's is refused"
  (spec-with floor-spec 'lib (with-lib floor-lib 1 8001003))
  (lambda (root prefix)
    (library-refused prefix (identity "8.1.2" 8001003 floor-source-id) floor-role floor-identity)))

(check-row "a library whose source id is one character off the pinned one is refused"
  (spec-with floor-spec 'lib (with-lib floor-lib 2 (last-changed floor-source-id)))
  (lambda (root prefix)
    (library-refused prefix (identity "8.1.2" 8001002 (last-changed floor-source-id))
                     floor-role floor-identity)))

(check-row "a library that answers 0 to sqlite3_threadsafe, single-thread, is refused, though its options list THREADSAFE=1"
  (spec-with floor-spec 'lib (with-lib floor-lib 3 0))
  (lambda (root prefix) (threadsafe-refused prefix 0)))

(check-row "a library that answers 2 to sqlite3_threadsafe, multi-thread, is refused"
  (spec-with floor-spec 'lib (with-lib floor-lib 3 2))
  (lambda (root prefix) (threadsafe-refused prefix 2)))

;; --- check-sqlite.sh: the options, whole -------------------------------------------------------

(options-row "DEFAULT_MEMSTATUS=0, at its place in SQLite's order, is refused: ADR-0005's lane keeps SQLite's memory count"
  floor-spec (lambda () (inserted floor-options "DEFAULT_MMAP_SIZE=0" "DEFAULT_MEMSTATUS=0")) floor-role)

(options-row "an option added before the first is refused"
  floor-spec (lambda () (inserted floor-options "ATOMIC_INTRINSICS=1" "ALLOW_URI_AUTHORITY")) floor-role)

(options-row "an option added after the last is refused"
  floor-spec (lambda () (inserted floor-options 'end "USE_URI")) floor-role)

(options-row "the first option dropped is refused"
  floor-spec (lambda () (dropped floor-options "ATOMIC_INTRINSICS=1")) floor-role)

(options-row "an option in the middle dropped is refused"
  floor-spec (lambda () (dropped floor-options "MAX_EXPR_DEPTH=1000")) floor-role)

(options-row "the last option dropped is refused"
  floor-spec (lambda () (dropped floor-options "THREADSAFE=1")) floor-role)

(options-row "MAX_VARIABLE_NUMBER=250000, Ubuntu's, in place of SQLite's default is refused"
  floor-spec (lambda () (replaced floor-options "MAX_VARIABLE_NUMBER=32766" "MAX_VARIABLE_NUMBER=250000")) floor-role)

(options-row "two options swapped are refused: the list is compared in order, not as a set"
  floor-spec (lambda () (swapped floor-options "MAX_PAGE_COUNT=0xfffffffe")) floor-role)

(test-equal "the COMPILER= row below changes an entry SQLite lists"
  'listed
  (if (string? compiler-option) 'listed compiler-option))

(when (string? compiler-option)
  (options-row "COMPILER=gcc-0.0.0, another compiler than CC, is refused: the entry is held whole"
    floor-spec (lambda () (replaced floor-options compiler-option "COMPILER=gcc-0.0.0")) floor-role))

;; --- check-sqlite.sh: the files and the env --------------------------------------------------

(check-row "no library file is refused, naming its path"
  (spec-with floor-spec 'lib 'none)
  (lambda (root prefix)
    (refused "no library at " (lib-path prefix) ": it is not a regular file")))

(check-row "no header file is refused, naming its path"
  (spec-with floor-spec 'header 'none)
  (lambda (root prefix)
    (refused "no header at " (header-path prefix) ": it is not a regular file")))

(check-row "CHEZ_SQLITE3_LIBRARY unset is refused"
  (spec-with floor-spec 'env (env-with "CHEZ_SQLITE3_LIBRARY" #f))
  (lambda (root prefix) (library-env-refused prefix "unset")))

(check-row "CHEZ_SQLITE3_LIBRARY relative, lib/libsqlite3.so.0, is refused"
  (spec-with floor-spec 'env (env-with "CHEZ_SQLITE3_LIBRARY" (lambda (root prefix) "lib/libsqlite3.so.0")))
  (lambda (root prefix) (library-env-refused prefix "'lib/libsqlite3.so.0'")))

(check-row "CHEZ_SQLITE3_LIBRARY naming a copy of the same library elsewhere is refused"
  (spec-with floor-spec
             'setup (lambda (root prefix)
                      (checked "mkdir" (list "mkdir" (string-append root "/other")))
                      (checked "cp" (list "cp" (lib-path prefix) (string-append root "/other/libsqlite3.so.0")))
                      0)
             'env (env-with "CHEZ_SQLITE3_LIBRARY"
                            (lambda (root prefix) (string-append root "/other/libsqlite3.so.0"))))
  (lambda (root prefix)
    (library-env-refused prefix (string-append "'" root "/other/libsqlite3.so.0'"))))

;; The decoy header declares the floor's own identity, so only the check of
;; where the compiler finds <sqlite3.h> can refuse it.
(define (with-decoy-header root prefix)
  (write-file-in root "decoy/include/sqlite3.h" (header-text floor-header))
  0)

(check-row "C_INCLUDE_PATH without PREFIX/include, so the compiler finds another sqlite3.h, is refused, naming the one found"
  (spec-with floor-spec
             'setup with-decoy-header
             'env (env-with "C_INCLUDE_PATH" (lambda (root prefix) (string-append root "/decoy/include"))))
  (lambda (root prefix)
    (header-elsewhere prefix (string-append root "/decoy/include/sqlite3.h"))))

(check-row "C_INCLUDE_PATH with PREFIX/include second, after another sqlite3.h, is refused, naming the one found"
  (spec-with floor-spec
             'setup with-decoy-header
             'env (env-with "C_INCLUDE_PATH"
                            (lambda (root prefix)
                              (string-append root "/decoy/include:" prefix "/include"))))
  (lambda (root prefix)
    (header-elsewhere prefix (string-append root "/decoy/include/sqlite3.h"))))

;; --- check-sqlite.sh: the header's identity ---------------------------------------------------

(check-row "a header whose SQLITE_VERSION is 8.1.3 is refused"
  (spec-with floor-spec 'header (with-header floor-header 0 (q "8.1.3")))
  (lambda (root prefix)
    (header-refused prefix (with-header floor-header 0 (q "8.1.3")) floor-role floor-identity)))

(check-row "a header whose SQLITE_VERSION_NUMBER is one more is refused"
  (spec-with floor-spec 'header (with-header floor-header 1 "8001003"))
  (lambda (root prefix)
    (header-refused prefix (with-header floor-header 1 "8001003") floor-role floor-identity)))

(check-row "a header whose SQLITE_SOURCE_ID is one character off is refused"
  (spec-with floor-spec 'header (with-header floor-header 2 (q (last-changed floor-source-id))))
  (lambda (root prefix)
    (header-refused prefix (with-header floor-header 2 (q (last-changed floor-source-id)))
                    floor-role floor-identity)))

;; --- check-sqlite.sh: the floor and --current ---------------------------------------------------

(check-row "a malformed floor is refused, with floor.sh's line and then the script's"
  (spec-with floor-spec 'floors "((chez \"9.8.7\") (sqlite \"8.1\"))\n")
  (lambda (root prefix)
    (list 1 ""
          (string-append
           "floor.sh: packaging/floors.sexp: the sqlite version \"8.1\" is not three dot-separated naturals, major.minor.patch\n"
           "check-sqlite.sh: no SQLite floor to check against\n"))))

(check-row "no floors file, without --current, is refused"
  (spec-with floor-spec 'floors #f)
  (lambda (root prefix)
    (list 1 ""
          (string-append
           "floor.sh: packaging/floors.sexp: it cannot be read\n"
           "check-sqlite.sh: no SQLite floor to check against\n"))))

(check-row "--current: the floor's library and header are refused, at the header, which is checked first"
  (spec-with current-spec 'lib floor-lib 'header floor-header)
  (lambda (root prefix)
    (header-refused prefix floor-header current-role current-identity)))

(check-row "--current: the pinned release's header with the floor's library is refused, at the library"
  (spec-with current-spec 'lib floor-lib)
  (lambda (root prefix)
    (library-refused prefix floor-identity current-role current-identity)))

;; The floor's list differs from the current one in two places five lines
;; apart, so diff -u shows both in one hunk.
(options-row "--current: the pinned release's identity with the floor's 37 options is refused"
  current-spec
  (lambda ()
    (list floor-options
          (hunk current-options (position "MAX_FUNCTION_ARG=1000" current-options) 7
                '((#\- . "MAX_FUNCTION_ARG=1000")
                  (#\+ . "MAX_FUNCTION_ARG=127")
                  (#\space . "MAX_LENGTH=1000000000")
                  (#\space . "MAX_LIKE_PATTERN_LENGTH=50000")
                  (#\space . "MAX_MMAP_SIZE=0x7fff0000")
                  (#\space . "MAX_PAGE_COUNT=0xfffffffe")
                  (#\space . "MAX_PAGE_SIZE=65536")
                  (#\- . "MAX_SCHEMA=10000000")))))
  current-role)

(check-row "--current: current_version and version set to the floor's in the env, with the floor's library, are still refused"
  (spec-with current-spec
             'lib floor-lib 'header floor-header
             'floors (floors-text "8.1.2")
             'env (env-plus "current_version=8.1.2" "version=8.1.2"
                            (string-append "current_source_id=" floor-source-id)))
  (lambda (root prefix)
    (header-refused prefix floor-header current-role current-identity)))

;; --- check-sqlite.sh: usage --------------------------------------------------------------

(define check-usage (list 2 "" "usage: check-sqlite.sh PREFIX [--current]\n"))

(check-row "no prefix is a usage error"
  (spec-with floor-spec 'args (lambda (root prefix) '()))
  (lambda (root prefix) check-usage))

(check-row "two prefixes are a usage error"
  (spec-with floor-spec 'args (lambda (root prefix) (list prefix prefix)))
  (lambda (root prefix) check-usage))

(check-row "--nothreads, check-chez.sh's flag, is a usage error"
  (spec-with floor-spec 'args (lambda (root prefix) (list prefix "--nothreads")))
  (lambda (root prefix) check-usage))

(check-row "three arguments are a usage error"
  (spec-with floor-spec 'args (lambda (root prefix) (list prefix "--current" "x")))
  (lambda (root prefix) check-usage))

(check-row "a relative prefix is refused, naming it"
  (spec-with floor-spec 'args (lambda (root prefix) (list "prefix")))
  (lambda (root prefix)
    (list 2 "" "check-sqlite.sh: PREFIX must be an absolute path, not 'prefix'\n")))

;; --- build-sqlite.sh: the tree -------------------------------------------------------------
;;
;; Besides scripts/ci and the floors file, each row's tree holds:
;;   shim/    curl, openssl, tar and cc, POSIX sh scripts. Each appends its
;;            name and arguments to ROOT/calls, one line a call. curl names
;;            its URL on stderr, then writes ROOT/served to its -o file, or
;;            exits 7 when there is none, as for a host it cannot reach.
;;            openssl answers dgst -sha3-256 -r FILE from ROOT/digests, by
;;            FILE's name. tar makes each member it is asked for, under -C.
;;            cc builds nothing: it writes "the shim's library" to its -o
;;            file only when ROOT/cc-writes exists, and logs the two names a
;;            check reads from its environment, when they are set;
;;   tools/   a link to each other tool the scripts and the shims run, and
;;            nothing else: PATH is shim/ and tools/;
;;   tmp/     TMPDIR, where each script makes its work directory, so a row
;;            sees it removed.
;; The calls name the work directories, made by mktemp: the suite writes
;; build-sqlite.sh's as WORK and check-sqlite.sh's as CWORK, and counts how
;; many of each were named.

;; The pins, a reviewed copy of the script's: the SHA3-256 of each role's
;; sqlite-autoconf tarball, as fetched from sqlite.org and read by two
;; implementations, and of its sqlite3.c, as the release log publishes it.
(define floor-archive "a54395aa2cf76b5b973fa420715b6108afedc4d8c0209c763fd2c1b517f8ad9f")
(define floor-source "0474604df9e1b69a5544295dd046aad954749279780d557da80f44b958100295")
(define current-archive "b6ced585c750916b1052667239a12c25a7ff34e7f06e1e6e01ecb0427657d9c4")
(define current-source "e2b869d3003b33c942b7dd7063604fbc53553e1b66609570df39b9b7b558ee81")

;; A digest no pin has.
(define other-digest (make-string 64 #\5))

;; shell-word : String -> String
;; S as one POSIX shell word.
(define (shell-word s)
  (call-with-string-output-port
   (lambda (p)
     (put-char p #\')
     (string-for-each (lambda (c) (if (char=? c #\') (put-string p "'\\''") (put-char p c))) s)
     (put-char p #\'))))

;; first-line : String -> (U String #f)
(define (first-line text)
  (let ((lines (text-lines text)))
    (and (= (length lines) 1) (car lines))))

;; sh-path : (U String #f)
;; The sh on this PATH, which the rows run the script with, by its path:
;; their PATH holds only shim/ and tools/.
(define sh-path
  (guard (e (#t #f))
    (let ((found (capture-command (list "sh" "-c" "command -v sh"))))
      (and (eqv? (car found) 0) (first-line (cadr found))))))

(test-equal "sh is a file on this PATH, which the build rows run and link"
  'found
  (if (and (string? sh-path) (string-prefix? "/" sh-path)) 'found sh-path))

;; real-cc : (U String #f)
;; The path of the C compiler $CC names, which a row's cc shim runs for the
;; calls check-sqlite.sh makes.
(define real-cc
  (guard (e (#t #f))
    (let ((found (capture-command (list "sh" "-c" "command -v \"$0\"" cc))))
      (and (eqv? (car found) 0) (first-line (cadr found))))))

(test-equal "CC is a file on this PATH, which the build row that passes runs as its compiler"
  'found
  (if (and (string? real-cc) (string-prefix? "/" real-cc)) 'found real-cc))

(define row-tools
  '("sh" "dirname" "sed" "tr" "grep" "awk" "mktemp" "rm" "mkdir" "cp" "cat" "cmp" "diff"))

;; The line each shim's call log begins with: its own name and arguments.
(define log-call
  "{ printf '%s' \"${0##*/}\"; for a in \"$@\"; do printf ' %s' \"$a\"; done; printf '\\n'; } >>\"$root/calls\"\n")

(define (shim-text root name)
  (string-append
   "#!/bin/sh\n"
   "root=" (shell-word root) "\n"
   (cond
     ((string=? name "curl")
      (string-append
       log-call
       "out=\n"
       "url=\n"
       "while [ \"$#\" -gt 0 ]; do\n"
       "  case $1 in\n"
       "    -o) out=$2; shift 2 ;;\n"
       "    -*) shift ;;\n"
       "    *) url=$1; shift ;;\n"
       "  esac\n"
       "done\n"
       "echo \"curl: $url\" >&2\n"
       "[ -f \"$root/served\" ] || exit 7\n"
       "cp \"$root/served\" \"$out\"\n"))
     ((string=? name "openssl")
      (string-append
       log-call
       "if [ \"$#\" -ne 4 ] || [ \"$1\" != dgst ] || [ \"$2\" != -sha3-256 ] || [ \"$3\" != -r ]; then\n"
       "  echo \"openssl shim: not dgst -sha3-256 -r FILE: $*\" >&2\n"
       "  exit 64\n"
       "fi\n"
       "[ -f \"$4\" ] || { echo \"openssl shim: no file $4\" >&2; exit 1; }\n"
       "digest=$(awk -v name=\"${4##*/}\" '$1 == name { print $2 }' \"$root/digests\")\n"
       "[ -n \"$digest\" ] || { echo \"openssl shim: no digest for ${4##*/}\" >&2; exit 1; }\n"
       "printf '%s *%s\\n' \"$digest\" \"$4\"\n"))
     ((string=? name "tar")
      (string-append
       log-call
       "if [ \"$#\" -lt 4 ] || [ \"$1\" != xzf ] || [ \"$3\" != -C ]; then\n"
       "  echo \"tar shim: not xzf ARCHIVE -C DIR MEMBER...: $*\" >&2\n"
       "  exit 64\n"
       "fi\n"
       "[ -f \"$2\" ] || { echo \"tar shim: no archive $2\" >&2; exit 2; }\n"
       "dir=$4\n"
       "shift 4\n"
       "for member in \"$@\"; do\n"
       "  mkdir -p \"$dir/$(dirname \"$member\")\"\n"
       "  if [ \"${member##*/}\" = sqlite3.h ] && [ -f \"$root/header\" ]; then\n"
       "    cp \"$root/header\" \"$dir/$member\"\n"
       "  else\n"
       "    printf \"the shim's %s\\n\" \"$member\" >\"$dir/$member\"\n"
       "  fi\n"
       "done\n"))
     (else
      (string-append
       "{ printf '%s' \"${0##*/}\"\n"
       "  [ -z \"${C_INCLUDE_PATH+set}\" ] || printf ' [C_INCLUDE_PATH=%s]' \"$C_INCLUDE_PATH\"\n"
       "  [ -z \"${CHEZ_SQLITE3_LIBRARY+set}\" ] || printf ' [CHEZ_SQLITE3_LIBRARY=%s]' \"$CHEZ_SQLITE3_LIBRARY\"\n"
       "  for a in \"$@\"; do printf ' %s' \"$a\"; done; printf '\\n'; } >>\"$root/calls\"\n"
       "if [ -f \"$root/realcc\" ]; then\n"
       "  case \" $* \" in *\" -shared \"*) ;; *) exec \"$(cat \"$root/realcc\")\" \"$@\" ;; esac\n"
       "fi\n"
       "out=\n"
       "while [ \"$#\" -gt 0 ]; do\n"
       "  case $1 in\n"
       "    -o) out=$2; shift 2 ;;\n"
       "    *) shift ;;\n"
       "  esac\n"
       "done\n"
       "if [ -n \"$out\" ] && [ -f \"$root/stub-lib\" ]; then\n"
       "  cp \"$root/stub-lib\" \"$out\"\n"
       "elif [ -n \"$out\" ] && [ -f \"$root/cc-writes\" ]; then\n"
       "  printf \"the shim's library\\n\" >\"$out\"\n"
       "fi\n")))))

;; A Build-Spec is an association list: floors, args and env as a Spec's
;; (env giving the words added to build-env's), shims (the names shim/
;; holds, each a shim above, cc's text under any name), digests (an
;; association list of a file's name and the digest openssl answers),
;; served (whether curl serves an archive), cc-writes (whether cc
;; writes its -o file), and stub and header (#f, or a Lib and a Header: the
;; row's compiler then writes that Lib, built before the row by the suite's own
;; stub builder, as its -shared output, tar's sqlite3.h is that Header, and
;; cc runs the real compiler for every call that is not the -shared one, as
;; check-sqlite.sh's calls need).

(define build-floor-spec
  (list (cons 'floors (floors-text "8.1.2"))
        (cons 'args (lambda (root prefix) (list prefix)))
        (cons 'env (lambda (root prefix) '()))
        (cons 'shims '("curl" "openssl" "tar" "cc"))
        (cons 'digests (list (cons "sqlite-autoconf-8010200.tar.gz" floor-archive)
                             (cons "sqlite3.c" floor-source)))
        (cons 'served #t)
        (cons 'cc-writes #f)
        (cons 'stub #f)
        (cons 'header #f)))

(define build-current-spec
  (append (list (cons 'floors #f)
                (cons 'args (lambda (root prefix) (list prefix "--current")))
                (cons 'digests (list (cons "sqlite-autoconf-3540100.tar.gz" current-archive)
                                     (cons "sqlite3.c" current-source))))
          build-floor-spec))

;; build-env : String String (Listof String) -> (Listof String)
;; The row's environment: PATH and TMPDIR in the tree, CHEZ this suite's,
;; CC unset so cc is found on PATH, and nothing that names a library or a
;; header; then EXTRA.
(define (build-env root prefix extra)
  (append (list "-u" "CHEZ_SQLITE3_LIBRARY" "-u" "C_INCLUDE_PATH" "-u" "CPATH" "-u" "CC"
                (string-append "PATH=" root "/shim:" root "/tools")
                (string-append "TMPDIR=" root "/tmp")
                (string-append "CHEZ=" chez))
          extra))

;; make-build-tree! : String Build-Spec -> Unit
(define (make-build-tree! root spec)
  (let ((shims (spec-ref spec 'shims)))
    (checked "mkdir" (list "mkdir" (string-append root "/shim") (string-append root "/tools")
                           (string-append root "/tmp")))
    (for-each (lambda (name)
                (let ((path (string-append root "/shim/" name)))
                  (write-file path (shim-text root name))
                  (checked "chmod" (list "chmod" "755" path))))
              shims)
    (checked "link the tools"
             (append (list "sh" "-c"
                           "cd \"$0\" && for t in \"$@\"; do p=$(command -v \"$t\") || exit 1; ln -s \"$p\" \"$t\" || exit 1; done"
                           (string-append root "/tools"))
                     row-tools))
    (write-file (string-append root "/digests")
                (apply string-append
                       (map (lambda (entry) (string-append (car entry) " " (cdr entry) "\n"))
                            (spec-ref spec 'digests))))
    (when (spec-ref spec 'served)
      (write-file (string-append root "/served") "the archive curl's shim serves\n"))
    (when (spec-ref spec 'cc-writes)
      (write-file (string-append root "/cc-writes") ""))
    (when (spec-ref spec 'stub)
      (let ((made (make-library! root (string-append root "/stubdir") (spec-ref spec 'stub))))
        (unless (eqv? made 0) (error 'make-build-tree! "the stub did not compile" made))
        (checked "cp" (list "cp" (string-append root "/stubdir/libsqlite3.so.0")
                            (string-append root "/stub-lib")))
        (write-file (string-append root "/header") (header-text (spec-ref spec 'header)))
        (write-file (string-append root "/realcc") (or real-cc (error 'make-build-tree! "no real cc")))))))

;; file-or-none : String -> (U String 'none)
(define (file-or-none path)
  (if (file-exists? path)
      (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                            (make-transcoder (utf-8-codec)))
        get-string-all)
      'none))

(define (text-or-empty path)
  (let ((text (file-or-none path)))
    (cond ((eq? text 'none) "") ((eof-object? text) "") (else text))))

;; find-from : String String Natural -> (U Natural #f)
(define (find-from text part start)
  (let ((n (string-length text)) (m (string-length part)))
    (let loop ((i start))
      (cond ((> (+ i m) n) #f)
            ((string=? (substring text i (+ i m)) part) i)
            (else (loop (+ i 1)))))))

;; work-written : String String String -> (Pairof String Natural)
;; TEXT with each BASE followed by mktemp's six characters written NAME,
;; and how many different ones it named.
(define (work-written text base name)
  (let loop ((i 0) (pieces '()) (seen '()))
    (let ((at (find-from text base i)))
      (if (or (not at) (> (+ at (string-length base) 6) (string-length text)))
          (cons (apply string-append (reverse (cons (substring text i (string-length text)) pieces)))
                (length seen))
          (let* ((end (+ at (string-length base) 6))
                 (suffix (substring text (+ at (string-length base)) end)))
            (loop end (cons* name (substring text i at) pieces)
                  (if (member suffix seen) seen (cons suffix seen))))))))

;; normalized : String String -> (List String Natural Natural)
;; TEXT with ROOT/tmp/build-sqlite.XXXXXX written WORK and
;; ROOT/tmp/check-sqlite.XXXXXX written CWORK, and how many of each it named.
(define (normalized root text)
  (let* ((build (work-written text (string-append root "/tmp/build-sqlite.") "WORK"))
         (check (work-written (car build) (string-append root "/tmp/check-sqlite.") "CWORK")))
    (list (car check) (cdr build) (cdr check))))

;; prefix-state : String -> (U 'no-prefix (List (U String 'none) ...))
;; Whether PREFIX was made, and then what its library and two headers hold.
(define (prefix-state prefix)
  (if (file-exists? prefix)
      (list (file-or-none (lib-path prefix))
            (file-or-none (header-path prefix))
            (file-or-none (string-append prefix "/include/sqlite3ext.h")))
      'no-prefix))

;; A Build-Answer is (list STATUS STDOUT STDERR CALLS WORKS CHECK-WORKS
;; TMP-LEFT PREFIX-STATE): the script's exit status and output, the calls the
;; shims logged, how many work directories of each script they named, what
;; tmp/ still holds, and what PREFIX holds, the work directories written
;; WORK and CWORK throughout.

;; build-row : String Build-Spec (String String -> Build-Answer) -> Unit
(define (build-row name spec expected-of)
  (test-equal (string-append "build-sqlite.sh: " name)
    '(returned same)
    (outcome
     (lambda ()
       (with-tree (spec-ref spec 'floors)
         (lambda (root)
           (let ((prefix (string-append root "/prefix")))
             (make-build-tree! root spec)
             (let* ((ran (capture-command
                          (append (list "env")
                                  (env-order (build-env root prefix ((spec-ref spec 'env) root prefix)))
                                  (list sh-path (string-append root "/scripts/ci/build-sqlite.sh"))
                                  ((spec-ref spec 'args) root prefix))))
                    (calls (normalized root (text-or-empty (string-append root "/calls"))))
                    (stderr (normalized root (caddr ran)))
                    (left (directory-list (string-append root "/tmp")))
                    (state (prefix-state prefix))
                    (got (list (car ran) (cadr ran) (car stderr) (car calls) (cadr calls) (caddr calls)
                               left state))
                    (want (expected-of root prefix)))
               (if (equal? got want) 'same (list 'got got 'want want))))))))))

;; --- build-sqlite.sh: what it answers and calls, written by hand ---------------------------------

(define (archive-name number) (string-append "sqlite-autoconf-" number))

(define (url-of year number)
  (string-append "https://sqlite.org/" year "/" (archive-name number) ".tar.gz"))

(define (curl-call year number)
  (string-append "curl -fsSL --retry 3 -o WORK/" (archive-name number) ".tar.gz " (url-of year number)))

(define (archive-digest-call number)
  (string-append "openssl dgst -sha3-256 -r WORK/" (archive-name number) ".tar.gz"))

(define (tar-call number)
  (let ((d (archive-name number)))
    (string-append "tar xzf WORK/" d ".tar.gz -C WORK " d "/sqlite3.c " d "/sqlite3.h " d "/sqlite3ext.h")))

(define (source-digest-call number)
  (string-append "openssl dgst -sha3-256 -r WORK/" (archive-name number) "/sqlite3.c"))

;; §2c of the slice's plan: one compile, SQLite's defaults with THREADSAFE
;; written, an unresolved symbol an error.
(define (cc-call cc-name prefix number)
  (string-append cc-name " -shared -fPIC -O2 -DSQLITE_THREADSAFE=1 -Wl,-z,defs -o " (lib-path prefix)
                 " WORK/" (archive-name number) "/sqlite3.c -lpthread -lm"))

(define (shim-file number name) (string-append "the shim's " (archive-name number) "/" name "\n"))

;; build-answer : Integer String String (Listof String) Natural Natural Any -> Build-Answer
;; With tmp/ left empty: each work directory removed.
(define (build-answer status stdout stderr calls works check-works state)
  (list status stdout stderr (text-of calls) works check-works '() state))

;; build-refused : String ... -> String
(define (build-refused . words)
  (string-append "build-sqlite.sh: " (apply string-append words) "\n"))

(define (curl-says year number) (string-append "curl: " (url-of year number) "\n"))

(define (floor-unreached year number)
  (build-refused "could not download " (url-of year number)
                 ": if the SQLite floor in packaging/floors.sexp was raised, floor_year, floor_archive and floor_source in this script may still be the old floor's"))

(define (current-unreached year number)
  (build-refused "could not download " (url-of year number)
                 ": if current_version was changed, current_year, current_archive and current_source in this script may still be the old release's"))

;; padded-number : (Listof Natural) -> String
;; The archive's number for a version: X, then Y and Z in two digits each,
;; then 00.
(define (padded-number parts)
  (let ((two (lambda (n) (let ((s (number->string n))) (if (< n 10) (string-append "0" s) s)))))
    (string-append (number->string (car parts)) (two (cadr parts)) (two (caddr parts)) "00")))

;; unreached : (String String -> String) String String -> Build-Answer
;; curl was asked for the archive and could not get it: nothing else ran.
(define (unreached message year number)
  (build-answer 1 "" (string-append (curl-says year number) (message year number))
                (list (curl-call year number)) 1 0 'no-prefix))

(define (without-served spec) (spec-with spec 'served #f))

;; --- build-sqlite.sh: what it downloads -----------------------------------------------------

(build-row "the real floors file: the floor's archive, its number computed, from the floor's year"
  (spec-with (without-served build-floor-spec) 'floors (text-or-empty "packaging/floors.sexp"))
  (lambda (root prefix)
    (unreached floor-unreached "2024" (padded-number (floor-numbers (read-floors) 'sqlite)))))

(build-row "a floor of 8.1.2 reaches sqlite-autoconf-8010200.tar.gz, from the floor's year: the pins go with the role"
  (without-served build-floor-spec)
  (lambda (root prefix) (unreached floor-unreached "2024" "8010200")))

(build-row "a floor of 8.12.3 reaches sqlite-autoconf-8120300.tar.gz: minor and patch two digits each"
  (spec-with (without-served build-floor-spec) 'floors (floors-text "8.12.3"))
  (lambda (root prefix) (unreached floor-unreached "2024" "8120300")))

(build-row "--current reaches the pinned release, 3540100 from 2026, with the real floors file"
  (spec-with (without-served build-current-spec) 'floors (text-or-empty "packaging/floors.sexp"))
  (lambda (root prefix) (unreached current-unreached "2026" "3540100")))

(build-row "--current reaches the pinned release with no floors file"
  (spec-with (without-served build-current-spec) 'floors #f)
  (lambda (root prefix) (unreached current-unreached "2026" "3540100")))

(build-row "--current reaches the pinned release with a floor of 8.1.2"
  (spec-with (without-served build-current-spec) 'floors (floors-text "8.1.2"))
  (lambda (root prefix) (unreached current-unreached "2026" "3540100")))

(build-row "the env moves nothing: version, current_version, floor_year, year, number and url set, the floor's archive is still reached"
  (spec-with (without-served build-floor-spec)
             'env (lambda (root prefix)
                    (list "version=9.9.9" "current_version=9.9.9" "floor_year=1999" "year=1999"
                          "number=9090900" "url=https://example.invalid/x.tar.gz" "role=current")))
  (lambda (root prefix) (unreached floor-unreached "2024" "8010200")))

(build-row "--current: the env moves nothing: current_version and current_year set, the pinned release is still reached"
  (spec-with (without-served build-current-spec)
             'env (lambda (root prefix)
                    (list "current_version=9.9.9" "version=9.9.9" "current_year=1999" "year=1999")))
  (lambda (root prefix) (unreached current-unreached "2026" "3540100")))

;; --- build-sqlite.sh: before any download ---------------------------------------------------

(build-row "a malformed floor fails before any download, with floor.sh's line, then the script's"
  (spec-with build-floor-spec 'floors "((chez \"9.8.7\") (sqlite \"8.1\"))\n")
  (lambda (root prefix)
    (build-answer 1 ""
                  (string-append
                   "floor.sh: packaging/floors.sexp: the sqlite version \"8.1\" is not three dot-separated naturals, major.minor.patch\n"
                   (build-refused "no SQLite floor to build"))
                  '() 0 0 'no-prefix)))

(define (cannot-find tool why) (build-refused "cannot find " tool ", which " why))
(define no-curl (cannot-find "curl" "downloads the archive"))
(define no-openssl (cannot-find "openssl" "checks the SHA3-256 of the archive and of its sqlite3.c"))
(define no-tar (cannot-find "tar" "unpacks the archive"))
(define (no-cc name) (cannot-find name "is the C compiler CC names, cc by default, and compiles sqlite3.c"))

(build-row "no openssl is named before any download"
  (spec-with build-floor-spec 'shims '("curl" "tar" "cc"))
  (lambda (root prefix) (build-answer 1 "" no-openssl '() 0 0 'no-prefix)))

(build-row "no tar is named before any download"
  (spec-with build-floor-spec 'shims '("curl" "openssl" "cc"))
  (lambda (root prefix) (build-answer 1 "" no-tar '() 0 0 'no-prefix)))

(build-row "no curl is named"
  (spec-with build-floor-spec 'shims '("openssl" "tar" "cc"))
  (lambda (root prefix) (build-answer 1 "" no-curl '() 0 0 'no-prefix)))

(build-row "no compiler where CC points is named before any download"
  (spec-with build-floor-spec
             'env (lambda (root prefix) (list (string-append "CC=" root "/nowhere/cc"))))
  (lambda (root prefix) (build-answer 1 "" (no-cc (string-append root "/nowhere/cc")) '() 0 0 'no-prefix)))

(build-row "none of the four: each is named, in order, before any download"
  (spec-with build-floor-spec 'shims '())
  (lambda (root prefix)
    (build-answer 1 "" (string-append no-curl no-openssl no-tar (no-cc "cc")) '() 0 0 'no-prefix)))

;; --- build-sqlite.sh: the digests -----------------------------------------------------------

(define (archive-refused number got role pin)
  (build-refused (archive-name number) ".tar.gz has SHA3-256 " got ", but " role "_archive in this script pins " pin))

(define (source-refused number got role pin)
  (build-refused (archive-name number) "/sqlite3.c has SHA3-256 " got ", but " role
                 "_source in this script pins " pin ", the digest sqlite.org's release log publishes"))

(build-row "an archive whose SHA3-256 is not the pin is refused, naming both, and nothing is unpacked"
  (spec-with build-floor-spec 'digests (list (cons "sqlite-autoconf-8010200.tar.gz" other-digest)
                                             (cons "sqlite3.c" floor-source)))
  (lambda (root prefix)
    (build-answer 1 "" (string-append (curl-says "2024" "8010200")
                                      (archive-refused "8010200" other-digest "floor" floor-archive))
                  (list (curl-call "2024" "8010200") (archive-digest-call "8010200"))
                  1 0 'no-prefix)))

(build-row "floor_archive set in the env to the archive's digest moves nothing: still refused"
  (spec-with build-floor-spec
             'digests (list (cons "sqlite-autoconf-8010200.tar.gz" other-digest)
                            (cons "sqlite3.c" floor-source))
             'env (lambda (root prefix) (list (string-append "floor_archive=" other-digest)
                                              (string-append "archive_sha3=" other-digest))))
  (lambda (root prefix)
    (build-answer 1 "" (string-append (curl-says "2024" "8010200")
                                      (archive-refused "8010200" other-digest "floor" floor-archive))
                  (list (curl-call "2024" "8010200") (archive-digest-call "8010200"))
                  1 0 'no-prefix)))

(build-row "--current: the floor's archive pin is not the current one's: the current archive with the floor's digest is refused"
  (spec-with build-current-spec 'digests (list (cons "sqlite-autoconf-3540100.tar.gz" floor-archive)
                                               (cons "sqlite3.c" floor-source)))
  (lambda (root prefix)
    (build-answer 1 "" (string-append (curl-says "2026" "3540100")
                                      (archive-refused "3540100" floor-archive "current" current-archive))
                  (list (curl-call "2026" "3540100") (archive-digest-call "3540100"))
                  1 0 'no-prefix)))

(build-row "an archive that matches its pin, with a sqlite3.c that does not, is refused before the compiler runs"
  (spec-with build-floor-spec 'digests (list (cons "sqlite-autoconf-8010200.tar.gz" floor-archive)
                                             (cons "sqlite3.c" other-digest)))
  (lambda (root prefix)
    (build-answer 1 "" (string-append (curl-says "2024" "8010200")
                                      (source-refused "8010200" other-digest "floor" floor-source))
                  (list (curl-call "2024" "8010200") (archive-digest-call "8010200")
                        (tar-call "8010200") (source-digest-call "8010200"))
                  1 0 'no-prefix)))

(build-row "--current: the current archive's pin with the floor's sqlite3.c digest is refused before the compiler runs"
  (spec-with build-current-spec 'digests (list (cons "sqlite-autoconf-3540100.tar.gz" current-archive)
                                               (cons "sqlite3.c" floor-source)))
  (lambda (root prefix)
    (build-answer 1 "" (string-append (curl-says "2026" "3540100")
                                      (source-refused "3540100" floor-source "current" current-source))
                  (list (curl-call "2026" "3540100") (archive-digest-call "3540100")
                        (tar-call "3540100") (source-digest-call "3540100"))
                  1 0 'no-prefix)))

;; --- build-sqlite.sh: the build, and the check at its end -------------------------------------

(define (no-library prefix)
  (string-append "check-sqlite.sh: no library at " (lib-path prefix) ": it is not a regular file\n"))

(define (built-calls year number cc-line)
  (list (curl-call year number) (archive-digest-call number) (tar-call number)
        (source-digest-call number) cc-line))

(build-row "both digests right: three members unpacked, one compile with the plan's flags, the headers copied, then check-sqlite.sh's refusal of the library cc never wrote, last"
  build-floor-spec
  (lambda (root prefix)
    (build-answer 1 "" (string-append (curl-says "2024" "8010200") (no-library prefix))
                  (built-calls "2024" "8010200" (cc-call "cc" prefix "8010200"))
                  1 0
                  (list 'none (shim-file "8010200" "sqlite3.h") (shim-file "8010200" "sqlite3ext.h")))))

(build-row "--current, both digests right, in a tree with no floors file: the pinned release built the same way, then checked with --current"
  build-current-spec
  (lambda (root prefix)
    (build-answer 1 "" (string-append (curl-says "2026" "3540100") (no-library prefix))
                  (built-calls "2026" "3540100" (cc-call "cc" prefix "3540100"))
                  1 0
                  (list 'none (shim-file "3540100" "sqlite3.h") (shim-file "3540100" "sqlite3ext.h")))))

(define (no-header-found)
  "check-sqlite.sh: cc lists no sqlite3.h among the files #include <sqlite3.h> reads\n")

(define (find-call prefix include-path)
  (string-append "cc [C_INCLUDE_PATH=" include-path "] [CHEZ_SQLITE3_LIBRARY=" (lib-path prefix)
                 "] -E -M CWORK/find.c"))

(build-row "a compile that writes the library: check-sqlite.sh gets the override and the header's directory, and its first compiler call is its own"
  (spec-with build-floor-spec 'cc-writes #t)
  (lambda (root prefix)
    (build-answer 1 "" (string-append (curl-says "2024" "8010200") (no-header-found))
                  (append (built-calls "2024" "8010200" (cc-call "cc" prefix "8010200"))
                          (list (find-call prefix (string-append prefix "/include"))))
                  1 1
                  (list "the shim's library\n" (shim-file "8010200" "sqlite3.h")
                        (shim-file "8010200" "sqlite3ext.h")))))

(build-row "C_INCLUDE_PATH in the env: the compile gets it as it is, and the check gets PREFIX/include before it"
  (spec-with build-floor-spec
             'cc-writes #t
             'env (lambda (root prefix) (list (string-append "C_INCLUDE_PATH=" root "/elsewhere"))))
  (lambda (root prefix)
    (build-answer 1 "" (string-append (curl-says "2024" "8010200") (no-header-found))
                  (append (built-calls "2024" "8010200"
                                       (string-append "cc [C_INCLUDE_PATH=" root "/elsewhere]"
                                                      (substring (cc-call "cc" prefix "8010200") 2
                                                                 (string-length (cc-call "cc" prefix "8010200")))))
                          (list (find-call prefix (string-append prefix "/include:" root "/elsewhere"))))
                  1 1
                  (list "the shim's library\n" (shim-file "8010200" "sqlite3.h")
                        (shim-file "8010200" "sqlite3ext.h")))))

(build-row "CC naming another compiler: that one compiles"
  (spec-with build-floor-spec
             'shims '("curl" "openssl" "tar" "cc-other")
             'env (lambda (root prefix) (list (string-append "CC=" root "/shim/cc-other"))))
  (lambda (root prefix)
    (build-answer 1 "" (string-append (curl-says "2024" "8010200") (no-library prefix))
                  (built-calls "2024" "8010200" (cc-call "cc-other" prefix "8010200"))
                  1 0
                  (list 'none (shim-file "8010200" "sqlite3.h") (shim-file "8010200" "sqlite3ext.h")))))

;; --- build-sqlite.sh: the success path ---------------------------------------------------------
;;
;; The one row that runs the script to its last line: cc writes a stub library
;; the suite's own stub builder made, answering the role's version, source id,
;; threadsafe and options, tar's sqlite3.h declares the same release, and the
;; check runs the real compiler and Chez on them.

;; check-cc-call : String String String -> String
;; The call of the compiler that check-sqlite.sh makes, with ARGS.
(define (check-cc-call prefix include-path args)
  (string-append "cc [C_INCLUDE_PATH=" include-path "] [CHEZ_SQLITE3_LIBRARY=" (lib-path prefix)
                 "] " args))

;; success-row : String Build-Spec String String String Natural String String Lib Header (Listof String) -> Unit
(define (success-row name spec year number version lib-number source-id role lib header options)
  (build-row name
    (spec-with spec 'stub lib 'header header)
    (lambda (root prefix)
      (build-answer
       0
       (string-append
        (cadr (passes-by "cc" prefix version lib-number source-id role options))
        "build-sqlite.sh: SQLite " version " built into " prefix "\n")
       (curl-says year number)
       (append (built-calls year number (cc-call "cc" prefix number))
               (list (check-cc-call prefix (string-append prefix "/include") "-E -M CWORK/find.c")
                     (check-cc-call prefix (string-append prefix "/include") "-dM -E CWORK/find.c")
                     (check-cc-call prefix (string-append prefix "/include") "-E -P CWORK/compiler.c")))
       1 1
       (list (file-or-none (string-append root "/stub-lib"))
             (header-text header)
             (shim-file number "sqlite3ext.h"))))))

(success-row "both digests right and a library that is the floor's: built, checked, and the last line printed, exit 0"
  build-floor-spec "2024" "8010200" "8.1.2" 8001002 floor-source-id floor-role
  floor-lib floor-header floor-options)

(success-row "--current, both digests right and a library that is the pinned release's: built, checked with --current, and the last line printed, exit 0"
  build-current-spec "2026" "3540100" current-version current-number current-source-id current-role
  current-lib current-header current-options)

;; --- both scripts: the execute bit ------------------------------------------------------------
;;
;; CI runs both scripts by their names, and every row here runs them with sh,
;; so no row above would see a lost execute bit.

(test-equal "both scripts are executable, as CI runs them by their names"
  '(returned (("scripts/ci/build-sqlite.sh" . 0) ("scripts/ci/check-sqlite.sh" . 0)))
  (outcome
   (lambda ()
     (let* ((build (car (capture-command (list "test" "-x" "scripts/ci/build-sqlite.sh"))))
            (check (car (capture-command (list "test" "-x" "scripts/ci/check-sqlite.sh")))))
       (list (cons "scripts/ci/build-sqlite.sh" build) (cons "scripts/ci/check-sqlite.sh" check))))))

;; --- build-sqlite.sh: usage --------------------------------------------------------------

(define build-usage
  (lambda (root prefix) (build-answer 2 "" "usage: build-sqlite.sh PREFIX [--current]\n" '() 0 0 'no-prefix)))

(build-row "no prefix is a usage error" (spec-with build-floor-spec 'args (lambda (root prefix) '())) build-usage)

(build-row "two prefixes are a usage error"
  (spec-with build-floor-spec 'args (lambda (root prefix) (list prefix prefix))) build-usage)

(build-row "--nothreads, build-chez.sh's flag, is a usage error"
  (spec-with build-floor-spec 'args (lambda (root prefix) (list prefix "--nothreads"))) build-usage)

(build-row "three arguments are a usage error"
  (spec-with build-floor-spec 'args (lambda (root prefix) (list prefix "--current" "x"))) build-usage)

(build-row "a relative prefix is refused, naming it, before any download"
  (spec-with build-floor-spec 'args (lambda (root prefix) (list "prefix")))
  (lambda (root prefix)
    (build-answer 2 "" "build-sqlite.sh: PREFIX must be an absolute path, not 'prefix'\n" '() 0 0 'no-prefix)))

(test-end "ci-sqlite")

(exit (suite-exit-status runner))
