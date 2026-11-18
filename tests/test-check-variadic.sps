#!r6rs
;;; The suite for tests/check-variadic.sh, the check behind `make
;;; check-variadic`, which CI's main job runs as a step and make test does
;;; not (ADR-0001, amended 2026-11-17; the M4 plan, section 4.2). The real
;;; script's real run is make check-variadic's own: this suite holds each of
;;; its branches, every failure among them, so that a check loosened to pass
;;; leaves this suite red.
;;;
;;; Every row runs the real script, copied into a tree of the row's own,
;;; since the script works on the tree it sits in: a native.sls written here,
;;; an empty .plans/decisions and build/scheme-libs/srfi, and stand-ins, in
;;; the row's bin/, for the programs the script is handed:
;;;
;;;   CHEZ      answers --script, the script's question for (machine-type),
;;;             with the row's machine type; and --libdirs D --program
;;;             SUITE with what the row says that suite prints and exits on
;;;             the unchanged copy, where native.sls holds the convention,
;;;             or on the mutant, where it does not, so the decision by
;;;             machine type is held by a Linux host answering Apple's types,
;;;             which no reading of uname could give
;;;   TIMEOUT   logs its first two arguments and runs the rest
;;;   sed       in one row, on PATH, the real sed with one more line changed
;;;
;;; Two rows hold the script to the tree make test runs on: its list of
;;; the ten tests the mutant must fail is exactly the names of
;;; test-conventions' tests that hold the table to src/, read from that
;;; suite as data; and native.sls holds the convention's text on one line,
;;; its comments counted, which the script's mutation step requires.
;;;
;;; Both stand-ins log each call, and a row asserts the log whole: the
;;; question first, then each suite in the copy, never in the tree itself,
;;; with the tree's own build/scheme-libs, under TEST_TIMEOUT. Every row
;;; asserts the exit status, the whole stdout and the whole stderr, each
;;; line written here by hand, never read back from the script. No child
;;; reaches native code: the stand-ins run no Chez, so none runs under the
;;; gate (ADR-0005, amended, M1 slice 5).
(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
        (only (chezscheme) getenv))

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

(define script "tests/check-variadic.sh")
(define form "(__varargs_after 2)")

;; --- text ------------------------------------------------------------------------

;; lines : String ... -> String
;; Each string, a newline after each.
(define (lines . items)
  (apply string-append (map (lambda (item) (string-append item "\n")) items)))

;; string-index-of : String String -> (U Natural #f)
;; Where PART first occurs in TEXT.
(define (string-index-of text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (cond ((> (+ i k) n) #f)
            ((string=? (substring text i (+ i k)) part) i)
            (else (loop (+ i 1)))))))

;; split-lines : String -> (Listof String)
;; TEXT cut at each newline, the last piece kept when no newline ends it.
(define (split-lines text)
  (let loop ((i 0) (start 0) (found '()))
    (cond ((= i (string-length text))
           (reverse (if (> i start) (cons (substring text start i) found) found)))
          ((char=? (string-ref text i) #\newline)
           (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
          (else (loop (+ i 1) start found)))))

;; shown : String -> String
;; TEXT as the script's show prints a run's output: each line after "  | ".
(define (shown text)
  (apply lines (map (lambda (l) (string-append "  | " l)) (split-lines text))))

(define (write-file path text)
  (call-with-port (open-file-output-port path (file-options no-fail) (buffer-mode block)
                                         (make-transcoder (utf-8-codec)))
    (lambda (port) (put-string port text))))

;; sh : String String ... -> (List Integer String String)
;; The shell's answer to SCRIPT, run with ARGS as $1 ....
(define (sh text . args)
  (capture-command (append (list "sh" "-c" text "sh") args)))

;; --- the suites' outputs, as the stand-in prints them --------------------------------

;; runner-out : String Natural (Listof (List String String String)) -> String
;; What the simple runner prints: its start, each failing test, its name,
;; expected and actual value, and its counts.
(define (runner-out name passed failures)
  (string-append
   (lines (string-append "%%%% Starting test " name))
   (apply string-append
          (map (lambda (f)
                 (lines (string-append "FAIL " (car f))
                        (string-append "  expected: " (cadr f))
                        (string-append "  actual:   " (caddr f))))
               failures))
   (lines (string-append "# of expected passes      " (number->string passed)))
   (if (null? failures)
       ""
       (lines (string-append "# of unexpected failures  " (number->string (length failures)))))))

(define src-row "src: no violation: each form is a literal binding held to its row, and each row has its form")
(define the-mismatch "((mismatch \"sqlite3_db_config\" convention variadic plain))")

;; ten-names : (Listof String)
;; The ten tests of test-conventions that hold the whole table to src/,
;; written out here as the script writes them.
(define ten-names
  (list src-row
        "sweep: a row removed fails, by name, for each of the 44 rows"
        "sweep: a row with no form fails, by name"
        "sweep: a row's convention flipped fails, by name, for each of the 44 rows: plain to collect-safe, and collect-safe and variadic to plain"
        "sweep: sqlite3_db_config's row made plain, and made collect-safe, each fails, by name, against the real src/"
        "sweep: a row's result type changed fails, by name, for each of the 44 rows: int to uptr, and uptr, integer-64, double and void to int"
        "sweep: sqlite3_memory_used's and sqlite3_column_int64's results, integer-64, and sqlite3_bind_int64's third argument, changed to int, each fail, by name (the M2 plan, section 4.8)"
        "sweep: M3's five made __collect_safe each fail, by name: a binding that held the lock-free counters or the interrupt through a collection would let another thread's collection wait on them"
        "sweep: sqlite3_changes64's, sqlite3_total_changes64's and sqlite3_last_insert_rowid's results, integer-64, changed to int, sqlite3_get_autocommit's, int, changed to integer-64, and sqlite3_interrupt's, void, changed to int, each fail, by name"
        "sweep: a row's argument type changed at each position fails, by name, for each of the 75 arguments"))

;; failing : (Listof String) String -> (Listof (List String String String))
;; NAMES as failing tests, the src row's actual value VIOLATIONS, the
;; others' a stand-in's.
(define (failing names violations)
  (map (lambda (name)
         (if (string=? name src-row)
             (list name "()" violations)
             (list name "(expected)" "(actual)")))
       names))

(define conventions-passes (runner-out "conventions" 77 '()))
(define native-passes (runner-out "native" 120 '()))
(define conventions-mutant (runner-out "conventions" 67 (failing ten-names the-mismatch)))
(define native-two-fail
  (runner-out "native" 118 (list (list "sqlite3_db_config round-trips DEFENSIVE" "(a)" "(b)")
                                 (list "sqlite3_db_config round-trips DQS_DML" "(a)" "(c)"))))

;; A behaviour is (OUT . STATUS): what a suite prints, and its exit status.
(define (behaves out status) (cons out status))

;; The four runs a passing check makes, each passing but the mutant's
;; test-conventions.
(define standard
  (list (cons "test-conventions-control" (behaves conventions-passes 0))
        (cons "test-native-control" (behaves native-passes 0))
        (cons "test-conventions-mutant" (behaves conventions-mutant 1))
        (cons "test-native-mutant" (behaves native-passes 0))))

;; with : Alist String Behaviour -> Alist
;; BEHAVIOURS with KEY's replaced.
(define (with behaviours key behaviour)
  (map (lambda (entry) (if (string=? (car entry) key) (cons key behaviour) entry)) behaviours))

;; --- native.sls as each row writes it ------------------------------------------------

(define (native-text . middle)
  (apply lines
         (append (list "#!r6rs" "(library (chez-sqlite3 private native)"
                       "  (export sqlite3-db-config)"
                       "  (import (rnrs) (only (chezscheme) foreign-procedure))"
                       "  (define sqlite3-db-config"
                       "    (load-step"
                       "     (bind-required report")
                       middle)))

(define native-once
  (native-text "       (foreign-procedure (__varargs_after 2) \"sqlite3_db_config\" (uptr int int uptr) int)))))"))
(define native-none
  (native-text "       (foreign-procedure \"sqlite3_db_config\" (uptr int int uptr) int)))))"))
(define native-two-lines
  (native-text "       (foreign-procedure (__varargs_after 2)"
               "         \"sqlite3_db_config\" (__varargs_after 2) (uptr int int uptr) int)))))"))
(define native-twice-on-a-line
  (native-text "       (foreign-procedure (__varargs_after 2) (__varargs_after 2) \"sqlite3_db_config\" (uptr int int uptr) int)))))"))

;; --- a row's tree ---------------------------------------------------------------------

(define base
  (guard (x (#t (display "test-check-variadic: no temporary directory: ")
                (display (describe x))
                (newline)
                (exit 1)))
    (make-process-temp-directory)))

;; real-sed : (U String #f)
;; The sed on PATH, which a row's stand-in runs.
(define real-sed
  (let ((found (sh "command -v sed")))
    (and (= (car found) 0) (> (string-length (cadr found)) 1)
         (substring (cadr found) 0 (- (string-length (cadr found)) 1)))))

;; chez-stand-in : String String String String -> String
;; The stand-in CHEZ's text: it logs to LOG each call, and answers --script
;; by MACHINE-ANSWER, a shell command; a suite by the files under
;; BEHAVIOURS, SUITE-STATE.out and SUITE-STATE.status, STATE control when the
;; copy's native.sls holds the convention and mutant when not. It logs
;; where it ran: the row's TREE, a copy under the row's ROW/tmp, or
;; elsewhere.
(define (chez-stand-in log machine-answer behaviours row tree)
  (lines "#!/bin/sh"
         (string-append "log='" log "'")
         "if [ \"$1\" = --script ]; then"
         "  printf 'chez --script\\n' >>\"$log\""
         (string-append "  " machine-answer)
         "fi"
         "if [ $# -ne 4 ] || [ \"$1\" != --libdirs ] || [ \"$3\" != --program ]; then"
         "  printf 'chez with other arguments: %s\\n' \"$*\" >>\"$log\"; exit 98"
         "fi"
         (string-append "if grep -q -F '" form "' src/chez-sqlite3/private/native.sls; then state=control; else state=mutant; fi")
         (string-append "case $(pwd) in '" tree "') where=the-tree ;; '" row "'/tmp/check-variadic.*/tree) where=a-copy ;; *) where=elsewhere ;; esac")
         "printf 'chez %s %s in %s, libdirs %s\\n' \"$4\" \"$state\" \"$where\" \"$2\" >>\"$log\""
         "name=$(basename \"$4\" .sps)-$state"
         (string-append "b='" behaviours "'")
         "[ -f \"$b/$name.out\" ] || { printf 'no behaviour for %s\\n' \"$name\"; exit 97; }"
         "cat \"$b/$name.out\""
         "exit \"$(cat \"$b/$name.status\")\""))

(define (timeout-stand-in log)
  (lines "#!/bin/sh"
         (string-append "printf 'timeout %s %s\\n' \"$1\" \"$2\" >>'" log "'")
         "[ \"$1\" = --foreground ] || exit 96"
         "shift 2"
         "exec \"$@\""))

;; sed-stand-in : String -> String
;; A sed that runs the real one, then changes the first line too.
(define (sed-stand-in real)
  (lines "#!/bin/sh"
         (string-append "'" real "' \"$@\" | awk 'NR == 1 { $0 = $0 \" ;\" } { print }'")))

(define counter 0)

;; run-check : Row -> (U (List Integer String String String) (List 'raised String))
;; The script, copied into a fresh tree, run there with the row's stand-ins:
;; its exit status, stdout and stderr, and the stand-ins' log.
;;   NATIVE      the text of the tree's native.sls
;;   MACHINE     the stand-in CHEZ's answer to --script, a shell command
;;   BEHAVIOURS  an alist of each suite's run, (SUITE-STATE . (OUT . STATUS))
;;   OPTIONS     symbols: no-srfi leaves build/scheme-libs/srfi out;
;;               other-sed puts sed-stand-in first on PATH; an-argument
;;               hands the script one
(define (run-check native machine behaviours options)
  (guard (x (#t (list 'raised (describe x))))
    (set! counter (+ counter 1))
    (let* ((row (string-append base "/row" (number->string counter)))
           (tree (string-append row "/tree"))
           (bin (string-append row "/bin"))
           (seds (string-append row "/sed"))
           (b (string-append row "/behaviours"))
           (tmp (string-append row "/tmp"))
           (log (string-append row "/log"))
           (made (sh (string-append
                      "mkdir -p \"$1/tests\" \"$1/src/chez-sqlite3/private\" \"$1/.plans/decisions\" "
                      "\"$2\" \"$3\" \"$4\" \"$5\" && : >\"$6\" && cp \"$7\" \"$1/tests/\" && "
                      ": >\"$1/.plans/decisions/0001-a.md\"")
                     tree bin seds b tmp log script)))
      (unless (equal? made '(0 "" "")) (error 'run-check "the tree was not made" made))
      (unless (memq 'no-srfi options)
        (let ((srfi (sh "mkdir -p \"$1/build/scheme-libs/srfi\"" tree)))
          (unless (equal? srfi '(0 "" "")) (error 'run-check "no srfi directory" srfi))))
      (write-file (string-append tree "/src/chez-sqlite3/private/native.sls") native)
      (write-file (string-append bin "/chez") (chez-stand-in log machine b row tree))
      (write-file (string-append bin "/timeout") (timeout-stand-in log))
      (write-file (string-append seds "/sed") (sed-stand-in real-sed))
      (for-each (lambda (entry)
                  (write-file (string-append b "/" (car entry) ".out") (cadr entry))
                  (write-file (string-append b "/" (car entry) ".status")
                              (number->string (cddr entry))))
                behaviours)
      (let ((modes (sh "chmod +x \"$1/chez\" \"$1/timeout\" \"$2/sed\"" bin seds)))
        (unless (equal? modes '(0 "" "")) (error 'run-check "no execute bits" modes)))
      (let* ((path (if (memq 'other-sed options)
                       (string-append seds ":" (getenv "PATH"))
                       (getenv "PATH")))
             (answer (capture-command
                      (append (list "env" (string-append "PATH=" path)
                                    (string-append "CHEZ=" bin "/chez")
                                    (string-append "TIMEOUT=" bin "/timeout")
                                    "TEST_TIMEOUT=7" (string-append "TMPDIR=" tmp)
                                    "sh" (string-append tree "/tests/check-variadic.sh"))
                              (if (memq 'an-argument options) '("now") '()))))
             (logged (sh "cat \"$1\"" log)))
        (append answer (list (cadr logged)))))))

;; --- the answers, written by hand ------------------------------------------------------

(define (ok text) (string-append "check-variadic: ok " text))
(define (failed text) (string-append "check-variadic: FAILED " text))
(define (stopped n m)
  (string-append "check-variadic: stopped after " (number->string n) " ok, "
                 (number->string m) " FAILED"))
(define (tally n m)
  (string-append "check-variadic: " (number->string n) " ok, " (number->string m) " FAILED"))

(define copy-ok (ok "copy: src/, tests/ and .plans/decisions/ copied to a scratch tree"))
(define (machine-ok type) (ok (string-append "machine: Chez's machine type is " type)))
(define conventions-control-ok
  (ok "control: tests/test-conventions.sps passes on the unchanged copy (exit 0)"))
(define native-control-ok
  (ok "control: tests/test-native.sps passes on the unchanged copy (exit 0)"))
(define mutant-ok
  (ok "mutant: (__varargs_after 2) stood on one line of src/chez-sqlite3/private/native.sls; removed, it stands on none, and no other line changed"))
(define static-text
  "tests/test-conventions.sps fails on the mutant (exit 1), naming exactly the ten tests that hold the table to src/, its violations exactly ((mismatch \"sqlite3_db_config\" convention variadic plain))")
(define static-ok (ok (string-append "static: " static-text)))
(define static-failed
  (failed "static: tests/test-conventions.sps must fail on the mutant, exit 1, naming exactly the ten tests that hold the table to src/, its violations exactly ((mismatch \"sqlite3_db_config\" convention variadic plain))"))
(define (other-passes type)
  (ok (string-append "other: on " type ", tests/test-native.sps passes on the mutant (exit 0), as expected: this ABI passes variadic arguments as it passes named ones, so only Apple arm64 (arm64osx, tarm64osx) can show the mutation by behaviour")))
(define (all-ok n type)
  (string-append "check-variadic: all " (number->string n) " steps ok, on " type))
(define (control-failed suite status how)
  (failed (string-append "control: " suite " must pass on the unchanged copy, by exit 0, no FAIL line and the runner's count of passes; it exited "
                         (number->string status) ", " how ", so nothing below would say anything about the mutation")))

;; The steps every run makes before the mutant's.
(define (head type)
  (list copy-ok (machine-ok type) conventions-control-ok native-control-ok mutant-ok))

;; log-of : String -> String
;; The stand-ins' log of a run that reaches every suite, in a tree whose
;; build/scheme-libs is under ROW-TREE.
(define (calls-for tree . runs)
  (apply lines
         (append (list "timeout --foreground 7" "chez --script")
                 (apply append
                        (map (lambda (run)
                               (list "timeout --foreground 7"
                                     (string-append "chez tests/" (car run) ".sps " (cadr run)
                                                    " in a-copy, libdirs src:tests:" tree
                                                    "/build/scheme-libs")))
                             runs)))))

(define (tree-of n) (string-append base "/row" (number->string n) "/tree"))
(define (chez-of n) (string-append base "/row" (number->string n) "/bin/chez"))

(define every-run
  '(("test-conventions" "control") ("test-native" "control")
    ("test-conventions" "mutant") ("test-native" "mutant")))

;; The answer of a row, its log dropped: rows that assert the log say so.
(define (without-log answer)
  (if (and (list? answer) (= (length answer) 4)) (list-head-of answer 3) answer))

(define (list-head-of lst n)
  (if (or (= n 0) (null? lst)) '() (cons (car lst) (list-head-of (cdr lst) (- n 1)))))

(define (machine type) (string-append "printf '%s\\n' '" type "'; exit 0"))

;; --- the rows -------------------------------------------------------------------------

(test-begin "check-variadic")

;; --- the script, held to the tree -----------------------------------------------------

;; read-all-data : String -> (U (Listof Any) (List 'unreadable Any))
(define (read-all-data path)
  (guard (x (#t (list 'unreadable (describe x))))
    (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      (lambda (port)
        (let loop ((found '()))
          (let ((datum (read port)))
            (if (eof-object? datum) (reverse found) (loop (cons datum found)))))))))

;; read-lines : String -> (U (Listof String) (List 'unreadable Any))
(define (read-lines path)
  (guard (x (#t (list 'unreadable (describe x))))
    (split-lines (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                                       (make-transcoder (utf-8-codec)))
                   get-string-all))))

;; calls-src? : Any -> Boolean
;; Whether X holds, at any depth, a call (violations "src" ...): a test that
;; holds the convention table to the real src/.
(define (calls-src? x)
  (and (pair? x)
       (or (and (eq? (car x) 'violations) (pair? (cdr x)) (equal? (cadr x) "src"))
           (let loop ((rest x))
             (and (pair? rest) (or (calls-src? (car rest)) (loop (cdr rest))))))))

;; src-tests : Any -> (Listof String)
;; The names of the (test-equal NAME ...) forms in X, at any depth and in
;; reading order, whose NAME is a string and which call violations on "src".
(define (src-tests x)
  (cond ((and (pair? x) (eq? (car x) 'test-equal) (pair? (cdr x)) (string? (cadr x)))
         (if (calls-src? (cddr x)) (list (cadr x)) '()))
        ((pair? x)
         (let loop ((rest x) (found '()))
           (if (pair? rest) (loop (cdr rest) (append found (src-tests (car rest)))) found)))
        (else '())))

;; the-ten : (U (Listof String) (List 'no-list Any))
;; The script's own list: the lines between its "cat <<'TEN'" and "TEN".
(define the-ten
  (let ((ls (read-lines script)))
    (if (and (pair? ls) (string? (car ls)))
        (let skip ((rest ls))
          (cond ((null? rest) (list 'no-list 'no-start))
                ((string=? (car rest) "  cat <<'TEN'")
                 (let take ((rest (cdr rest)) (found '()))
                   (cond ((null? rest) (list 'no-list 'no-end))
                         ((string=? (car rest) "TEN") (reverse found))
                         (else (take (cdr rest) (cons (car rest) found))))))
                (else (skip (cdr rest)))))
        (list 'no-list ls))))

(test-equal "the script's ten are exactly test-conventions' tests that call violations on \"src\", read from that suite as data, in its order"
  (let ((data (read-all-data "tests/test-conventions.sps")))
    (if (eq? (car data) 'unreadable) data (src-tests data)))
  the-ten)

(test-equal "the script's ten are ten, and the src row, whose violations the script reads, is the first"
  (list 10 "src: no violation: each form is a literal binding held to its row, and each row has its form")
  (if (and (list? the-ten) (pair? the-ten) (string? (car the-ten)))
      (list (length the-ten) (car the-ten))
      the-ten))

(test-equal "src/chez-sqlite3/private/native.sls holds the convention's text, (__varargs_after 2), on exactly one line, its comments counted, as the script's mutation step requires"
  1
  (let ((ls (read-lines "src/chez-sqlite3/private/native.sls")))
    (if (and (pair? ls) (string? (car ls)))
        (length (filter (lambda (l) (string-index-of l form)) ls))
        ls)))

(test-equal "the real sed was found on PATH, for the stand-in that wraps it"
  'found
  (if (string? real-sed) 'found real-sed))

;; passing, on machines that are not Apple arm64
(let* ((answer (run-check native-once (machine "ta6le") standard '()))
       (n counter))
  (test-equal "on ta6le, the unchanged copy passes, the mutant fails test-conventions by the ten tests and the one violation, and test-native's pass on it is reported: every step ok, exit 0"
    (list 0 (apply lines (append (head "ta6le") (list static-ok (other-passes "ta6le") (all-ok 7 "ta6le")))) "")
    (without-log answer))
  (test-equal "on ta6le, the stand-ins' log: Chez asked its machine type, then test-conventions and test-native in a copy of the tree, never the tree itself, unchanged then mutated, each with the tree's own build/scheme-libs, each under TIMEOUT --foreground TEST_TIMEOUT"
    (apply calls-for (tree-of n) every-run)
    (if (and (list? answer) (= (length answer) 4)) (cadddr answer) answer)))

(test-equal "on tarm64le, Linux arm64, test-native's pass on the mutant is reported, never failed"
  (list 0 (apply lines (append (head "tarm64le") (list static-ok (other-passes "tarm64le") (all-ok 7 "tarm64le")))) "")
  (without-log (run-check native-once (machine "tarm64le") standard '())))

(test-equal "on ta6osx, a Chez under Rosetta on an arm64 Mac, x86-64's ABI: reported, never failed"
  (list 0 (apply lines (append (head "ta6osx") (list static-ok (other-passes "ta6osx") (all-ok 7 "ta6osx")))) "")
  (without-log (run-check native-once (machine "ta6osx") standard '())))

(test-equal "on ta6le, test-native failing on the mutant is reported, with its failing tests, never failed"
  (list 0
        (apply lines (append (head "ta6le")
                             (list static-ok
                                   (ok "other: on ta6le, tests/test-native.sps fails on the mutant (exit 1), naming 2 failing tests; reported, never failed: only Apple arm64 is required to show the mutation by behaviour")
                                   "  FAIL sqlite3_db_config round-trips DEFENSIVE"
                                   "  FAIL sqlite3_db_config round-trips DQS_DML"
                                   (all-ok 7 "ta6le"))))
        "")
  (without-log (run-check native-once (machine "ta6le")
                          (with standard "test-native-mutant" (behaves native-two-fail 1)) '())))

;; Apple arm64, by Chez's machine type alone
(test-equal "on arm64osx, test-native failing on the mutant by name passes the step, listing its failing tests"
  (list 0
        (apply lines (append (head "arm64osx")
                             (list static-ok
                                   (ok "arm64: on arm64osx, tests/test-native.sps fails on the mutant (exit 1), naming 2 failing tests")
                                   "  FAIL sqlite3_db_config round-trips DEFENSIVE"
                                   "  FAIL sqlite3_db_config round-trips DQS_DML"
                                   (all-ok 7 "arm64osx"))))
        "")
  (without-log (run-check native-once (machine "arm64osx")
                          (with standard "test-native-mutant" (behaves native-two-fail 1)) '())))

(test-equal "on tarm64osx, test-native dying on the mutant by an uncaught raise, exit 255, naming no test, passes the step"
  (list 0
        (apply lines (append (head "tarm64osx")
                             (list static-ok
                                   (ok "arm64: on tarm64osx, tests/test-native.sps fails on the mutant (exit 255), dying by an uncaught raise (exit 255), naming no test")
                                   (all-ok 7 "tarm64osx"))))
        "")
  (without-log (run-check native-once (machine "tarm64osx")
                          (with standard "test-native-mutant"
                                (behaves "Exception: invalid memory reference\n" 255))
                          '())))

(test-equal "on tarm64osx, test-native killed by a signal on the mutant, exit 139, naming no test, passes the step"
  (list 0
        (apply lines (append (head "tarm64osx")
                             (list static-ok
                                   (ok "arm64: on tarm64osx, tests/test-native.sps fails on the mutant (exit 139), dying by signal 11, naming no test")
                                   (all-ok 7 "tarm64osx"))))
        "")
  (without-log (run-check native-once (machine "tarm64osx")
                          (with standard "test-native-mutant" (behaves "" 139)) '())))

(test-equal "on arm64osx, test-native passing on the mutant fails the step, showing its output: exit 1"
  (list 1
        (apply lines (append (head "arm64osx") (list static-ok)))
        (string-append
         (lines (failed "arm64: on arm64osx, tests/test-native.sps must fail on the mutant, by a failing test that names sqlite3_db_config or by dying; it exited 0, naming no test"))
         (shown native-passes)
         (lines (tally 6 1))))
  (without-log (run-check native-once (machine "arm64osx") standard '())))

(test-equal "on tarm64osx, test-native hanging on the mutant, TIMEOUT's 124, fails the step"
  (list 1
        (apply lines (append (head "tarm64osx") (list static-ok)))
        (string-append
         (lines (failed "arm64: on tarm64osx, tests/test-native.sps must fail on the mutant, by a failing test that names sqlite3_db_config or by dying; it exited 124, hanging: no exit within 7s"))
         (lines (tally 6 1))))
  (without-log (run-check native-once (machine "tarm64osx")
                          (with standard "test-native-mutant" (behaves "" 124)) '())))

;; Each failing test these two name holds sqlite3_db_config, so only the exit
;; status, 0 or the hang's 124, can fail the step.
(let ((zero-with-fail (runner-out "native" 119 (list (list "sqlite3_db_config round-trips DEFENSIVE" "1" "2")))))
  (test-equal "on arm64osx, test-native exiting 0 on the mutant, though it names a failing test through sqlite3_db_config, fails the step: exit 0 is a pass"
    (list 1
          (apply lines (append (head "arm64osx") (list static-ok)))
          (string-append
           (lines (failed "arm64: on arm64osx, tests/test-native.sps must fail on the mutant, by a failing test that names sqlite3_db_config or by dying; it exited 0, naming 1 failing tests"))
           (shown zero-with-fail)
           (lines (tally 6 1))))
    (without-log (run-check native-once (machine "arm64osx")
                            (with standard "test-native-mutant" (behaves zero-with-fail 0)) '())))
  (test-equal "on arm64osx, test-native naming a failing test through sqlite3_db_config and then hanging on the mutant, TIMEOUT's 124, fails the step: a hang is no verdict"
    (list 1
          (apply lines (append (head "arm64osx") (list static-ok)))
          (string-append
           (lines (failed "arm64: on arm64osx, tests/test-native.sps must fail on the mutant, by a failing test that names sqlite3_db_config or by dying; it exited 124, naming 1 failing tests"))
           (shown zero-with-fail)
           (lines (tally 6 1))))
    (without-log (run-check native-once (machine "arm64osx")
                            (with standard "test-native-mutant" (behaves zero-with-fail 124)) '()))))

(let ((elsewhere (runner-out "native" 118 (list (list "call-with-c-string refuses U+0000" "(a)" "(b)")
                                                (list "every count is zero at the end" "(a)" "(c)")))))
  (test-equal "on arm64osx, test-native failing on the mutant by name, but naming no test that holds sqlite3_db_config, the binding the mutant broke, fails the step"
    (list 1
          (apply lines (append (head "arm64osx") (list static-ok)))
          (string-append
           (lines (failed "arm64: on arm64osx, tests/test-native.sps must fail on the mutant, by a failing test that names sqlite3_db_config or by dying; it exited 1, naming 2 failing tests"))
           (shown elsewhere)
           (lines (tally 6 1))))
    (without-log (run-check native-once (machine "arm64osx")
                            (with standard "test-native-mutant" (behaves elsewhere 1)) '()))))

(test-equal "on arm64osx, test-native exiting 1 on the mutant with no failing test named fails the step: no evidence of the mutation"
  (list 1
        (apply lines (append (head "arm64osx") (list static-ok)))
        (string-append
         (lines (failed "arm64: on arm64osx, tests/test-native.sps must fail on the mutant, by a failing test that names sqlite3_db_config or by dying; it exited 1, naming no test"))
         (shown "no runner here\n")
         (lines (tally 6 1))))
  (without-log (run-check native-once (machine "arm64osx")
                          (with standard "test-native-mutant" (behaves "no runner here\n" 1)) '())))

;; the mutant. A native.sls without the convention reads as a mutant to the
;; stand-in, so that row's unchanged copy runs the mutant's behaviours, each
;; set to pass.
(test-equal "native.sls without the convention: the mutant step stops the check, naming 0 lines"
  (list 1
        (lines copy-ok (machine-ok "ta6le") conventions-control-ok native-control-ok)
        (lines (failed "mutant: (__varargs_after 2) stands on 0 lines of src/chez-sqlite3/private/native.sls, not one")
               (stopped 4 1)))
  (without-log (run-check native-none (machine "ta6le")
                          (with standard "test-conventions-mutant" (behaves conventions-passes 0))
                          '())))

(test-equal "native.sls with the convention on two lines: the mutant step stops the check, naming 2"
  (list 1
        (lines copy-ok (machine-ok "ta6le") conventions-control-ok native-control-ok)
        (lines (failed "mutant: (__varargs_after 2) stands on 2 lines of src/chez-sqlite3/private/native.sls, not one")
               (stopped 4 1)))
  (without-log (run-check native-two-lines (machine "ta6le") standard '())))

(test-equal "native.sls with the convention twice on one line: removed once, it still stands there, and the check stops"
  (list 1
        (lines copy-ok (machine-ok "ta6le") conventions-control-ok native-control-ok)
        (lines (failed "mutant: removing (__varargs_after 2) changed 1 lines of src/chez-sqlite3/private/native.sls and left it on 1; it must change one line and leave it on none")
               (stopped 4 1)))
  (without-log (run-check native-twice-on-a-line (machine "ta6le") standard '())))

(test-equal "a mutation that changed another line too, by a sed that does: the check stops, naming 2 lines changed"
  (list 1
        (lines copy-ok (machine-ok "ta6le") conventions-control-ok native-control-ok)
        (lines (failed "mutant: removing (__varargs_after 2) changed 2 lines of src/chez-sqlite3/private/native.sls and left it on 0; it must change one line and leave it on none")
               (stopped 4 1)))
  (without-log (run-check native-once (machine "ta6le") standard '(other-sed))))

;; the control
(let ((one-fail (runner-out "conventions" 76 (list (list "table: something" "1" "2")))))
  (test-equal "test-conventions failing on the unchanged copy stops the check before any mutation, showing its output"
    (list 1
          (lines copy-ok (machine-ok "ta6le"))
          (string-append (shown one-fail)
                         (lines (control-failed "tests/test-conventions.sps" 1 "naming 1 failing tests")
                                (stopped 2 1))))
    (without-log (run-check native-once (machine "ta6le")
                            (with standard "test-conventions-control" (behaves one-fail 1)) '()))))

(test-equal "test-native failing on the unchanged copy stops the check too"
  (list 1
        (lines copy-ok (machine-ok "ta6le") conventions-control-ok)
        (string-append (shown native-two-fail)
                       (lines (control-failed "tests/test-native.sps" 1 "naming 2 failing tests")
                              (stopped 3 1))))
  (without-log (run-check native-once (machine "ta6le")
                          (with standard "test-native-control" (behaves native-two-fail 1)) '())))

(test-equal "test-native exiting 1 on the unchanged copy with no FAIL line, though the runner counted its passes, as a suite does whose memory check fails at its exit, stops the check"
  (list 1
        (lines copy-ok (machine-ok "ta6le") conventions-control-ok)
        (string-append (shown native-passes)
                       (lines (control-failed "tests/test-native.sps" 1 "naming no test")
                              (stopped 3 1))))
  (without-log (run-check native-once (machine "ta6le")
                          (with standard "test-native-control" (behaves native-passes 1)) '())))

(test-equal "test-conventions exiting 0 on the unchanged copy without the runner's count of passes stops the check: an exit status alone is no evidence"
  (list 1
        (lines copy-ok (machine-ok "ta6le"))
        (string-append (shown "nothing ran\n")
                       (lines (control-failed "tests/test-conventions.sps" 0 "naming no test")
                              (stopped 2 1))))
  (without-log (run-check native-once (machine "ta6le")
                          (with standard "test-conventions-control" (behaves "nothing ran\n" 0)) '())))

(let ((zero-with-fail (runner-out "native" 119 (list (list "a row" "1" "2")))))
  (test-equal "test-native exiting 0 on the unchanged copy with a FAIL line stops the check"
    (list 1
          (lines copy-ok (machine-ok "ta6le") conventions-control-ok)
          (string-append (shown zero-with-fail)
                         (lines (control-failed "tests/test-native.sps" 0 "naming 1 failing tests")
                                (stopped 3 1))))
    (without-log (run-check native-once (machine "ta6le")
                            (with standard "test-native-control" (behaves zero-with-fail 0)) '()))))

;; the static step: the mutant's test-conventions
(define (static-row name behaviour problems)
  (test-equal name
    (list 1
          (apply lines (append (head "ta6le") (list (other-passes "ta6le"))))
          (string-append (lines static-failed) problems (shown (car behaviour)) (lines (tally 6 1))))
    (without-log (run-check native-once (machine "ta6le")
                            (with standard "test-conventions-mutant" behaviour) '()))))

(define (named-differ wanted got)
  (string-append "  the tests it named differ:\n"
                 (apply string-append (map (lambda (n) (lines (string-append "    wanted: FAIL " n))) wanted))
                 (apply string-append (map (lambda (n) (lines (string-append "    got:    FAIL " n))) got))))

(define (violations-differ got)
  (lines "  its violations differ:"
         (string-append "    wanted:   actual:   " the-mismatch)
         (string-append "    got:    " got)))

(static-row "test-conventions passing on the mutant fails the static step, which says why, and the check goes on to test-native"
  (behaves conventions-passes 0)
  (string-append (lines "  it exited 0, not 1, naming no test")
                 "  the tests it named differ:\n"
                 (apply string-append (map (lambda (n) (lines (string-append "    wanted: FAIL " n))) ten-names))
                 (lines "    got:    ")
                 (violations-differ "")))

(let ((eleven (append ten-names (list "table: another test"))))
  (static-row "test-conventions failing on the mutant on one test more than the ten fails the static step"
    (behaves (runner-out "conventions" 66 (failing eleven the-mismatch)) 1)
    (named-differ ten-names eleven)))

(let ((nine (cdr (reverse ten-names))))
  (static-row "test-conventions failing on the mutant on one test fewer than the ten fails the static step"
    (behaves (runner-out "conventions" 68 (failing (reverse nine) the-mismatch)) 1)
    (named-differ ten-names (reverse nine))))

(let ((swapped (cons (cadr ten-names) (cons (car ten-names) (cddr ten-names)))))
  (static-row "test-conventions naming the ten in another order fails the static step"
    (behaves (runner-out "conventions" 67 (failing swapped the-mismatch)) 1)
    (named-differ ten-names swapped)))

(let ((more "((mismatch \"sqlite3_db_config\" convention variadic plain) (no-form \"sqlite3_free\"))"))
  (static-row "test-conventions on the mutant with another violation beside the variadic one fails the static step"
    (behaves (runner-out "conventions" 67 (failing ten-names more)) 1)
    (violations-differ (string-append "  actual:   " more))))

(let ((other "((mismatch \"sqlite3_db_config\" convention variadic collect-safe))"))
  (static-row "test-conventions on the mutant with another violation in its place fails the static step"
    (behaves (runner-out "conventions" 67 (failing ten-names other)) 1)
    (violations-differ (string-append "  actual:   " other))))

(static-row "test-conventions dying on the mutant, exit 255, though it names the ten, fails the static step"
  (behaves (runner-out "conventions" 67 (failing ten-names the-mismatch)) 255)
  (lines "  it exited 255, not 1, naming 10 failing tests, then dying by an uncaught raise (exit 255)"))

;; the machine type, and what the check needs before it starts. Each answer
;; is taken before its expected value is built, which names the row's own
;; CHEZ: a call's arguments run in no fixed order (AGENTS.md).
(let* ((answer (run-check native-once "printf 'Exception: no\\n'; exit 1" standard '()))
       (n counter))
  (test-equal "Chez failing its machine-type question stops the check, showing what it printed"
    (list 1 (lines copy-ok)
          (string-append (shown "Exception: no\n")
                         (lines (failed (string-append "machine: " (chez-of n)
                                                       " --script printing (machine-type) must exit 0, printing one machine type alone on one line; it exited 1"))
                                (stopped 1 1))))
    (without-log answer)))

(let* ((answer (run-check native-once "printf 'ta6le\\nmore\\n'; exit 0" standard '()))
       (n counter))
  (test-equal "Chez answering more than a machine type stops the check"
    (list 1 (lines copy-ok)
          (string-append (shown "ta6le\nmore\n")
                         (lines (failed (string-append "machine: " (chez-of n)
                                                       " --script printing (machine-type) must exit 0, printing one machine type alone on one line; it exited 0"))
                                (stopped 1 1))))
    (without-log answer)))

(let* ((answer (run-check native-once "printf 'ta6le\\n'; exit 3" standard '()))
       (n counter))
  (test-equal "Chez printing a machine type but exiting 3 stops the check: the type alone is no answer"
    (list 1 (lines copy-ok)
          (string-append (shown "ta6le\n")
                         (lines (failed (string-append "machine: " (chez-of n)
                                                       " --script printing (machine-type) must exit 0, printing one machine type alone on one line; it exited 3"))
                                (stopped 1 1))))
    (without-log answer)))

(test-equal "build/scheme-libs/srfi missing stops the check at the copy, naming make deps, before Chez is asked anything"
  (list 1 ""
        (lines (failed "copy: build/scheme-libs/srfi is missing; run make deps") (stopped 0 1))
        "")
  (run-check native-once (machine "ta6le") standard '(no-srfi)))

(test-equal "an argument is a usage error, exit 2, before anything runs"
  (list 2 "" (lines "check-variadic: usage: sh tests/check-variadic.sh") "")
  (run-check native-once (machine "ta6le") standard '(an-argument)))

(test-end "check-variadic")

(exit (suite-exit-status runner))
