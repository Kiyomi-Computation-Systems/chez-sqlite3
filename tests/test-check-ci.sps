#!r6rs
;;; The suite for tests/check-ci.sh, the check behind `make check-ci`: it holds
;;; .github/workflows/ci.yml to the one shape it reads, and fails closed on any
;;; spelling that a text reader cannot see. Without this suite, loosening a rule
;;; would leave `make test` green: nothing else plants a fault in the workflow.
;;;
;;; Every row copies the real workflow into a directory of its own, under one
;;; temporary directory of this process (never at a fixed path, so two runs at
;;; once share no file), applies one edit, and runs the script on it. An edit is
;;; old text and new text, and the old text must occur exactly once in the real
;;; file, or the row fails and says which. A row asserts the exit status, the
;;; whole of stdout and the whole of stderr. Each expected problem is written by
;;; hand here: the line it names is the one holding an anchor text in the edited
;;; file, never a number read back from the script.
;;;
;;; make test runs every suite from the repository root. Without CHEZ nothing
;;; below runs: that fails here, by name, and never skips.
(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
        (only (chezscheme) mkdir current-directory))

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

(define script "tests/check-ci.sh")
(define real-path ".github/workflows/ci.yml")

;; --- files and text ---------------------------------------------------------------

;; read-text : String -> String
(define (read-text path)
  (call-with-port
   (open-file-input-port path (file-options) (buffer-mode block)
                         (make-transcoder (utf-8-codec)))
   get-string-all))

;; write-text : String String -> Void
(define (write-text path text)
  (call-with-port
   (open-file-output-port path (file-options) (buffer-mode block)
                          (make-transcoder (utf-8-codec)))
   (lambda (p) (put-string p text))))

;; find-sub : String String Natural -> (U Natural #f)
(define (find-sub s sub start)
  (let ((n (string-length s)) (m (string-length sub)))
    (let loop ((i start))
      (cond ((> (+ i m) n) #f)
            ((string=? (substring s i (+ i m)) sub) i)
            (else (loop (+ i 1)))))))

;; count-sub : String String -> Natural
(define (count-sub s sub)
  (let loop ((i 0) (n 0))
    (let ((at (find-sub s sub i)))
      (if at (loop (+ at (string-length sub)) (+ n 1)) n))))

;; replace-first : String String String -> String
(define (replace-first s old new)
  (let ((at (find-sub s old 0)))
    (string-append (substring s 0 at) new (substring s (+ at (string-length old)) (string-length s)))))

;; split-lines : String -> (Listof String)
;; The lines of TEXT, a final newline ending the last line, not starting another.
(define (split-lines text)
  (let loop ((chars (string->list text)) (cur '()) (acc '()))
    (cond ((null? chars) (reverse (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
          ((char=? (car chars) #\newline)
           (loop (cdr chars) '() (cons (list->string (reverse cur)) acc)))
          (else (loop (cdr chars) (cons (car chars) cur) acc)))))

(define real (guard (e (#t "")) (read-text real-path)))

;; lines : String ... -> String
;; Each argument as a line, newline-ended.
(define (lines . ls)
  (apply string-append (map (lambda (l) (string-append l "\n")) ls)))

;; span : String String -> String
;; The real file from the first START to the end of the first END after it.
;; START must occur once.
(define (span start end)
  (let* ((s (find-sub real start 0))
         (e (and s (find-sub real end s))))
    (unless e (error 'span "markers not found" start end))
    (substring real s (+ e (string-length end)))))

;; span-after : String String String -> String
;; As span, with START searched for after the first ANCHOR.
(define (span-after anchor start end)
  (unless (= (count-sub real anchor) 1)
    (error 'span-after "anchor must occur once" anchor))
  (let* ((a (find-sub real anchor 0))
         (s (find-sub real start a))
         (e (and s (find-sub real end s))))
    (unless e (error 'span-after "markers not found" start end))
    (substring real s (+ e (string-length end)))))

;; e : String String -> (Pair String String)
(define (e old new) (cons old new))

;; The jobs, in the file's order. A job's text runs from its header line to the
;; next job's, so a lane's text can be told from the other lanes' copies of it.
(define job-order '("main" "memory" "nothreads" "floor" "current"))

;; job-bounds : String String -> (Pair Natural Natural)
(define (job-bounds text job)
  (let ((start (find-sub text (string-append "\n  " job ":\n") 0)))
    (unless start (error 'job-bounds "no such job" job))
    (let loop ((later (cdr (member job job-order))))
      (cond ((null? later) (cons start (string-length text)))
            ((find-sub text (string-append "\n  " (car later) ":\n") start)
             => (lambda (at) (cons start at)))
            (else (loop (cdr later)))))))

;; job-text : String String -> String
(define (job-text text job)
  (let ((b (job-bounds text job))) (substring text (car b) (cdr b))))

;; le : String String String -> Edit
;; An edit that must find OLD once in one job's text, not once in the file: the
;; lanes hold copies of each other's steps.
(define (le job old new) (list 'lane job old new))

;; apply-edit : String Edit -> String
;; The old text must occur once in the real file, and once in the text so far;
;; for a lane edit, once in that job's text of each.
(define (apply-edit text edit)
  (if (eq? (car edit) 'lane)
      (let* ((job (cadr edit)) (old (caddr edit)) (new (cadddr edit))
             (tb (job-bounds text job))
             (tt (substring text (car tb) (cdr tb))))
        (unless (and (= (count-sub (job-text real job) old) 1) (= (count-sub tt old) 1))
          (error 'apply-edit "the old text does not occur exactly once in the job" job old))
        (string-append (substring text 0 (car tb))
                       (replace-first tt old new)
                       (substring text (cdr tb) (string-length text))))
      (let ((old (car edit)))
        (unless (and (= (count-sub real old) 1) (= (count-sub text old) 1))
          (error 'apply-edit "the old text does not occur exactly once" old))
        (replace-first text old (cdr edit)))))

(define (apply-edits edits)
  (fold-left apply-edit real edits))

;; --- the words the problems are made of, written by hand --------------------------

(define tab-msg "holds a tab, which YAML may read as white space beside a key")
(define odd-msg "holds a character beyond ASCII, which GitHub may fold into a key's letters")
(define explicit-msg "writes an explicit key, with ?, whose colon may be on another line")
(define alias-msg "puts an alias or an anchor where a key goes")
(define quoted-msg "writes a quoted key")
(define space-msg "has white space between a key and its colon")
(define flow-msg "holds a flow mapping, with {, outside a quoted scalar and a ${{ }} expression")
(define openq-msg "holds a quoted scalar that runs past the line's end")
(define bsq-msg "holds a backslash after a double quote, which YAML may read as an escape")
(define place-msg "is not a line check-ci reads at this place")
(define hasval-msg "this key must hold a block, not a value")

(define (names-msg w) (string-append "names " w ", which could steer a check or a later step"))
(define (gate-msg w)
  (string-append "names " w " other than as the whole run line of the one step that runs it"))

(define tops "name, on, permissions, concurrency, jobs")
(define (top-unknown k) (string-append "top-level key \"" k "\" is not one of " tops))
(define (top-twice k) (string-append "top-level key \"" k "\" is written twice"))
(define (top-order k)
  (string-append "top-level key \"" k "\" comes out of order: the order is " tops))
(define (top-missing k) (string-append "top-level key \"" k "\" is missing"))
(define (block-differs k want got)
  (string-append "the \"" k "\" block differs from the one check-ci holds: expected \""
                 want "\", found \"" got "\""))
(define (block-extra k got)
  (string-append "the \"" k "\" block has a line it must not: \"" got "\""))

(define jobs "main, memory, nothreads, floor, current")
(define (job-unknown j) (string-append "job \"" j "\" is not one of " jobs))
(define (job-missing j) (string-append "job \"" j "\" is missing"))
(define (job-key j k)
  (string-append "job " j " has the key \"" k "\", which is not one of name, runs-on, timeout-minutes, steps"))
(define (job-key-twice j k) (string-append "job " j " has the key \"" k "\" twice"))
(define (job-no-key j k) (string-append "job " j " has no key \"" k "\""))
(define (job-runs-on j) (string-append "job " j " has runs-on other than ubuntu-24.04"))
(define (job-timeout j)
  (string-append "job " j " has a timeout-minutes that is not a whole number"))

(define (step-key k)
  (string-append "step key \"" k "\" is not one of name, id, uses, with, run, env, if"))
(define (with-key k)
  (string-append "with key \"" k "\" is not one of submodules, path, key"))
(define (env-key k) (string-append "env key \"" k "\" is not CHEZ"))
(define chez-t "${{ runner.temp }}/chez-threads/bin/scheme")
(define chez-n "${{ runner.temp }}/chez-nothreads/bin/scheme")
(define (env-chez j v) (string-append "env CHEZ in job " j " is not " v))
(define hash-list
  "'packaging/floors.sexp', 'scripts/ci/floor.sh', 'scripts/ci/build-chez.sh', 'scripts/ci/check-chez.sh'")
(define (cache-key j prefix)
  (string-append "the cache key in job " j " does not begin with " prefix
                 "${{ hashFiles(" hash-list ") }}"))
(define if-line "if: steps.chez.outputs.cache-hit != 'true'")
(define if-bad (string-append "if is not exactly \"" if-line "\""))
(define if-wrong
  "if is on a step that neither runs scripts/ci/build-chez.sh nor uses actions/cache/save")

(define (n-steps j run n)
  (string-append "job " j " has " (number->string n) " steps that run \"" run "\", not one"))
(define (out-of-order j run before)
  (string-append "job " j " runs \"" run "\" before \"" before "\", and must run it after"))
(define (step-has-if j run) (string-append "job " j "'s step that runs \"" run "\" has an if"))
(define (step-no-if j run) (string-append "job " j "'s step that runs \"" run "\" has no if"))
(define first-step-msg
  "job main's first step is not uses: actions/checkout@ with submodules: recursive")
(define second-step-msg
  "job main's second step is not run: scripts/ci/check-action-pins.sh .github/workflows")

;; finding 7: the two report steps of main
(define vers-name "Report the versions this run uses")
(define sql-name "Report the runner's SQLite")
(define sql-run "scripts/ci/report-sqlite.sh")
(define (named-n name n)
  (string-append "job main has " (number->string n) " steps named \"" name "\", not one"))
(define (runs-before name before)
  (string-append "job main runs step \"" name "\" before \"" before "\", and must run it after"))
(define (runs-after name after)
  (string-append "job main runs step \"" name "\" after \"" after "\", and must run it before"))
(define swapped-msg
  (string-append "job main's step \"" sql-name "\" comes before step \"" vers-name "\", and must come after"))
(define not-block-msg
  (string-append "job main's step \"" vers-name "\" does not run a block: it must be run: |"))
(define (vers-differs want got)
  (string-append "job main's step \"" vers-name "\" has a run line that differs from the one check-ci holds: expected \""
                 want "\", found \"" got "\""))
(define (vers-extra got)
  (string-append "job main's step \"" vers-name "\" has a run line it must not: \"" got "\""))
(define (vers-early want)
  (string-append "job main's step \"" vers-name "\" has a run block that ends early: expected \"" want "\""))
(define sql-run-msg (string-append "job main's step \"" sql-name "\" is not run: " sql-run))
(define sql-env-msg (string-append "job main's step \"" sql-name "\" has no env CHEZ"))
(define vers-l1 "          \"$RUNNER_TEMP/chez-threads/bin/scheme\" --version")
(define vers-l2 "          cc --version | head -n 1")
(define vers-l3 "          valgrind --version")
(define vers-l4 "          echo \"image: ${ImageOS:-unknown} ${ImageVersion:-unknown}\"")
(define vers-l5 "          echo \"kernel: $(uname -r)\"")
(define vers-hdr "      - name: Report the versions this run uses")
(define sql-hdr "      - name: Report the runner's SQLite")
(define (vers-step) (span (string-append vers-hdr "\n") (string-append vers-l5 "\n")))
(define (sql-step) (span "      # The runner's own SQLite" (string-append "run: " sql-run "\n")))
(define (make-run) (string-append "        run: " make-line "\n"))
(define install-hdr "      - name: The install check, by discovery")
(define (install-step)
  (span "      # ADR-0002's install check." "        run: make build\n"))
(define chk-step-text
  (lambda ()
    (span-after "  main:\n" "      - name: Check the Chez this job runs\n"
                (string-append "run: " chk-t "\n"))))

(define pin-run "scripts/ci/check-action-pins.sh .github/workflows")
(define chk-t "scripts/ci/check-chez.sh \"$RUNNER_TEMP/chez-threads\"")
(define chk-n "scripts/ci/check-chez.sh \"$RUNNER_TEMP/chez-nothreads\" --nothreads")
(define bld-n "scripts/ci/build-chez.sh \"$RUNNER_TEMP/chez-nothreads\" --nothreads")
(define make-line
  "make check-help check-suites check-pins check-floors check-ci test check-test-fails check-dev check-clean")
(define build-run "make build")
(define launcher "sh tests/guix-env-launcher.sh")

;; --- rows ---------------------------------------------------------------------------

;; A row is (name edits-thunk problems-thunk setup-thunk): the edits to the real
;; file, the problems expected, in order, each (anchor message), and what to do
;; to the directory before the run (or #f). The thunks keep a fault in a row's
;; own construction from killing the suite: it fails that row, by name.
(define-syntax row
  (syntax-rules ()
    ((_ name edits problems) (list name (lambda () edits) (lambda () problems) #f))))

(define-syntax row/setup
  (syntax-rules ()
    ((_ name setup edits problems)
     (list name (lambda () edits) (lambda () problems) setup))))

;; An anchor: a string, the one line of the edited file that is exactly it; a
;; list (string n), the nth such line; (after HEADER string), the first line
;; that is exactly string below the one line that is exactly HEADER, so that a
;; line repeated across steps is named by its step; 'eof, the file's last
;; line; 'dir, no line, the directory; 'file, no line, the file.

;; (in JOB HEADER string), the same inside one job: the first line that is
;; exactly HEADER below the job's own header line "  JOB:" (or the job's header
;; itself, with #f), then the first line that is exactly string below that. A
;; step's lines are named by the step, never by their number among the lanes'.

;; line-number : (Listof String) Anchor -> Natural
(define (line-number ls anchor)
  (cond ((and (pair? anchor) (eq? (car anchor) 'after))
         (line-number-after ls (cadr anchor) (caddr anchor)))
        ((and (pair? anchor) (eq? (car anchor) 'in))
         (line-number-in ls (cadr anchor) (caddr anchor) (cadddr anchor)))
        (else (line-number-plain ls anchor))))

;; line-number-in : (Listof String) String (U String #f) String -> Natural
(define (line-number-in ls job header text)
  (let* ((j (line-number-plain ls (string-append "  " job ":")))
         (h (if header (line-number-below ls j header) j)))
    (line-number-below ls h text)))

;; line-number-below : (Listof String) Natural String -> Natural
;; The first line after line START (1-based) that is exactly TEXT.
(define (line-number-below ls start text)
  (let loop ((rest (list-tail ls start)) (i (+ start 1)))
    (cond ((null? rest) (error 'anchor "no such line below its header" text))
          ((string=? (car rest) text) i)
          (else (loop (cdr rest) (+ i 1))))))

;; line-number-after : (Listof String) String String -> Natural
(define (line-number-after ls header text)
  (let ((start (line-number-plain ls header)))
    (let loop ((rest (list-tail ls start)) (i (+ start 1)))
      (cond ((null? rest) (error 'anchor "no such line below its header" header text))
            ((string=? (car rest) text) i)
            (else (loop (cdr rest) (+ i 1)))))))

(define (line-number-plain ls anchor)
  (let* ((text (if (pair? anchor) (car anchor) anchor))
         (nth (if (pair? anchor) (cadr anchor) #f))
         (hits (let loop ((ls ls) (i 1) (acc '()))
                 (cond ((null? ls) (reverse acc))
                       ((string=? (car ls) text) (loop (cdr ls) (+ i 1) (cons i acc)))
                       (else (loop (cdr ls) (+ i 1) acc))))))
    (cond (nth (if (<= nth (length hits))
                   (list-ref hits (- nth 1))
                   (error 'anchor "no such line" anchor)))
          ((= (length hits) 1) (car hits))
          (else (error 'anchor "the line is not there exactly once" anchor)))))

;; problem-line : String String (Listof String) (List Anchor String) -> String
(define (problem-line dir file ls problem)
  (let ((anchor (car problem)) (msg (cadr problem)))
    (string-append
     "check-ci: "
     (cond ((eq? anchor 'dir) (string-append dir ": "))
           ((eq? anchor 'file) (string-append file ": "))
           ((eq? anchor 'eof) (string-append file ":" (number->string (length ls)) ": "))
           (else (string-append file ":" (number->string (line-number ls anchor)) ": ")))
     msg "\n")))

(define pass-line (lambda (dir) (string-append "check-ci: " dir "/ci.yml has the one shape check-ci reads\n")))

;; expected : String String (Listof (List Anchor String)) -> (List Integer String String)
(define (expected dir text problems)
  (let ((file (string-append dir "/ci.yml")) (ls (split-lines text)))
    (if (null? problems)
        (list 0 (pass-line dir) "")
        (list 1 ""
              (string-append
               (apply string-append (map (lambda (p) (problem-line dir file ls p)) problems))
               "check-ci: FAILED (problems: " (number->string (length problems)) ")\n")))))

;; Without a temporary directory no row can run, so the suite says why and exits
;; 1 here, before any row: a raise at the top level names no test.
(define base
  (guard (e (#t (display "test-check-ci: no temporary directory for the rows' copies: ")
                (display (describe e))
                (newline)
                (exit 1)))
    (make-process-temp-directory)))

(define counter 0)

;; run-row : (List String Thunk Thunk (U Procedure #f))
;;         -> (List (List Integer String String) (List Integer String String))
;; The expected answer, then the script's.
(define (run-row r)
  (set! counter (+ counter 1))
  (let ((dir (string-append base "/r" (number->string counter))))
    (guard (c (#t (list (list 'raised (string-append (car r) ": " (describe c))) '(not run))))
      (mkdir dir)
      (let* ((text (apply-edits ((cadr r))))
             (want (expected dir text ((caddr r)))))
        (write-text (string-append dir "/ci.yml") text)
        (when (cadddr r) ((cadddr r) dir))
        (list want (capture-command (list "sh" script dir)))))))

;; The rows.

;; setup procedures
(define (add-file name)
  (lambda (dir) (write-text (string-append dir "/" name) "on: push\n")))

(define (insert-after old new-lines) (e old (string-append old new-lines)))

;; The block scalar the rows plant their lines in: main's "Identify the runner
;; image" run block, which check-ci holds to no line. (The versions step's own
;; block is held line for line, so a planted line there is a problem of its own.)
(define id-line "          echo \"id=${ID}-${VERSION_ID}-${RUNNER_ARCH}\" >> \"$GITHUB_OUTPUT\"\n")
;; The text from main's first comment to the end of that block: it holds the
;; real file's one such text, which the other two jobs' copies of the block do not.
(define (id-span)
  (span "      # Every line with a uses key in this directory" id-line))
(define (in-id-block f)
  (let ((old (id-span))) (e old (f old))))
(define (after-id . ls)
  (in-id-block (lambda (old)
                 (string-append old (apply lines (map (lambda (l) (string-append "          " l)) ls))))))

(define job-keys
  '("if" "needs" "continue-on-error" "strategy" "container" "services" "defaults"
    "env" "permissions" "outputs" "environment"))

(define step-keys-refused '("shell" "working-directory" "continue-on-error" "timeout-minutes"))

(define banned-words
  '("MAKEFLAGS" "MFLAGS" "GNUMAKEFLAGS" "VALGRIND" "VALGRIND_OPTS" "VALGRIND_LIB"
    "MEMORY_SUITES" "MEMORY_TIMEOUT" "TEST_TIMEOUT" "LIBDIRS" "TIMEOUT" "SUITES"
    "CHEZ_SQLITE3_LIBRARY" "CHEZ_SQLITE3_DECOY" "CHEZ_SQLITE3_GATE_CHILD"
    "CC" "C_INCLUDE_PATH" "CPATH" "LD_LIBRARY_PATH" "LD_PRELOAD"))

(define make-words
  '("check-help" "check-suites" "check-pins" "check-floors" "check-ci" "test"
    "check-test-fails" "check-dev" "check-clean"))

(define (without-word line word)
  (let* ((at (find-sub line (string-append " " word) 0)))
    (string-append (substring line 0 at)
                   (substring line (+ at 1 (string-length word)) (string-length line)))))

(define nt-restore-key
  "          key: chez-nothreads-${{ hashFiles('packaging/floors.sexp', 'scripts/ci/floor.sh', 'scripts/ci/build-chez.sh', 'scripts/ci/check-chez.sh') }}-${{ steps.image.outputs.id }}")

(define hash-parts
  '("'packaging/floors.sexp', " ", 'scripts/ci/floor.sh'" ", 'scripts/ci/build-chez.sh'"
    ", 'scripts/ci/check-chez.sh'"))

(define gate-step
  (lambda ()
    (span "      - name: The gate must fail on planted defects" "run: make check-memory-gate\n")))
(define valgrind-step
  (lambda ()
    (span "      - name: Every suite under Valgrind" "run: make test-memory\n")))

;; --- the lanes: floor and current ----------------------------------------------------

(define checkout-line
  "      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1")

(define (lane-floor? j) (string=? j "floor"))
(define (lane-where j) (if (lane-floor? j) "at its floor" "at the current release"))
(define (lane-flag j) (if (lane-floor? j) "" " --current"))
(define (sql-sq j) (string-append "${{ runner.temp }}/sqlite-" j))
(define (sql-lib j) (string-append (sql-sq j) "/lib/libsqlite3.so.0"))
(define (sql-inc j) (string-append (sql-sq j) "/include"))
(define (other-lane j) (if (lane-floor? j) "current" "floor"))
(define (bld* j flag)
  (string-append "scripts/ci/build-sqlite.sh \"$RUNNER_TEMP/sqlite-" j "\"" flag))
(define (chk* j flag)
  (string-append "scripts/ci/check-sqlite.sh \"$RUNNER_TEMP/sqlite-" j "\"" flag))
(define (lane-bld j) (bld* j (lane-flag j)))
(define (lane-chk j) (chk* j (lane-flag j)))
(define cc-line
  "echo \"id=$(cc --version | head -n 1 | tr -c '[:alnum:].' '-')\" >> \"$GITHUB_OUTPUT\"")
(define (lane-hash j)
  (if (lane-floor? j)
      "'packaging/floors.sexp', 'scripts/ci/floor.sh', 'scripts/ci/build-sqlite.sh', 'scripts/ci/check-sqlite.sh'"
      "'scripts/ci/build-sqlite.sh', 'scripts/ci/check-sqlite.sh'"))
(define (lane-key j)
  (string-append "sqlite-" j "-${{ hashFiles(" (lane-hash j) ") }}-${{ steps.image.outputs.id }}-${{ steps.cc.outputs.id }}"))
(define (key-line k) (string-append "          key: " k))
(define (path-line p) (string-append "          path: " p))

(define h-install "Install the packages in packaging/debian-prereqs.txt")
(define h-image "Identify the runner image")
(define h-restore-chez "Restore Chez")
(define h-build-chez "Build Chez")
(define h-save-chez "Save Chez")
(define h-chk-chez "Check the Chez this job runs")
(define h-cc "Name the C compiler for the cache key")
(define (h-restore j) (string-append "Restore SQLite " (lane-where j)))
(define (h-build j) (string-append "Build SQLite " (lane-where j)))
(define (h-save j) (string-append "Save SQLite " (lane-where j)))
(define h-chk "Check the SQLite this job runs")
(define (h-load j) (string-append "Load SQLite " (lane-where j)))
(define (h-suites j) (string-append "The suites against SQLite " (lane-where j)))
(define (hdr-line h) (string-append "      - name: " h))

;; lane-step : String String -> String
;; The text of one step of a job, its header line to its last line.
(define (lane-step j h)
  (let* ((rt (job-text real j))
         (hl (string-append (hdr-line h) "\n"))
         (s (find-sub rt hl 0)))
    (unless (and s (= (count-sub rt hl) 1)) (error 'lane-step "no such step, or twice" j h))
    (let ((end (find-sub rt "\n\n" s)))
      (substring rt s (if end (+ end 1) (string-length rt))))))

;; se : String String String String -> Edit
;; In one step of one job, OLD becomes NEW.
(define (se j h old new)
  (let ((st (lane-step j h)))
    (unless (= (count-sub st old) 1) (error 'se "the old text is not once in the step" j h old))
    (le j st (replace-first st old new))))

;; del-step : String String -> Edit
(define (del-step j h)
  (let ((st (lane-step j h)))
    (if (and (string=? j "current") (string=? h (h-suites j)))
        (le j (string-append "\n" st) "")
        (le j (string-append st "\n") ""))))

;; A : String (U String #f) String -> Anchor
(define (A j h text) (list 'in j h text))

(define if-chez if-line)
(define if-sql "if: steps.sqlite.outputs.cache-hit != 'true'")
(define if-bad2 (string-append "if is not one of \"" if-chez "\" or \"" if-sql "\""))
(define chez-if-wrong
  "the Chez cache's if is on a step that is neither the Chez build nor the Chez cache's save")
(define sql-if-wrong
  "the SQLite cache's if is on a step that is neither the SQLite build nor the SQLite cache's save")
(define (path-msg j)
  (string-append "the cache path in job " j " is not one of ${{ runner.temp }}/chez-threads or " (sql-sq j)))
(define (sql-key-msg j) (string-append "the cache key in job " j " is not exactly " (lane-key j)))
(define (save-key-msg j id)
  (string-append "the cache key of the save in job " j " is not exactly ${{ steps." id ".outputs.cache-primary-key }}"))
(define (lane-env-key k)
  (string-append "env key \"" k "\" is not one of CHEZ, CHEZ_SQLITE3_LIBRARY, C_INCLUDE_PATH"))
(define (env-value j k v) (string-append "env " k " in job " j " is not " v))
(define (env-wrong-step k)
  (string-append "env key \"" k "\" is only for the steps that run the SQLite check, make build and make test"))
(define (env-missing j run k)
  (string-append "job " j "'s step that runs \"" run "\" has no env " k))
(define (cc-id-msg j) (string-append "job " j "'s step that runs \"" cc-line "\" has no id: cc"))
(define lane-env-names '("CHEZ_SQLITE3_LIBRARY" "C_INCLUDE_PATH"))

;; The problems of a lane's three env blocks, when the lane is not a job check-ci
;; knows: every line that names one of the two names is refused.
(define (lane-name-problems j)
  (apply append
         (map (lambda (h)
                (list (list (A j (hdr-line h) (string-append "          CHEZ_SQLITE3_LIBRARY: " (sql-lib j)))
                            (names-msg "CHEZ_SQLITE3_LIBRARY"))
                      (list (A j (hdr-line h) (string-append "          C_INCLUDE_PATH: " (sql-inc j)))
                            (names-msg "C_INCLUDE_PATH"))))
              (list h-chk (h-load j) (h-suites j)))))

;; The problems of a step whose run line is none of the three, but whose env
;; names the two keys.
(define (wrong-step-pair j h)
  (list (list (A j (hdr-line h) (string-append "          CHEZ_SQLITE3_LIBRARY: " (sql-lib j)))
              (env-wrong-step "CHEZ_SQLITE3_LIBRARY"))
        (list (A j (hdr-line h) (string-append "          C_INCLUDE_PATH: " (sql-inc j)))
              (env-wrong-step "C_INCLUDE_PATH"))))

(define chez-key-line
  "          key: chez-threads-${{ hashFiles('packaging/floors.sexp', 'scripts/ci/floor.sh', 'scripts/ci/build-chez.sh', 'scripts/ci/check-chez.sh') }}-${{ steps.image.outputs.id }}")

(define (lane-rows j)
  (define (HA h) (A j #f (hdr-line h)))
  (define (here) (string-append "  " j ":"))
  (define (step h) (lane-step j h))
  (define chk-t-line chk-t)
  ;; each required line: the step's name, its run line
  (define req
    (list (list h-chk-chez chk-t)
          (list h-cc cc-line)
          (list (h-build j) (lane-bld j))
          (list h-chk (lane-chk j))
          (list (h-load j) build-run)
          (list (h-suites j) "make test")))
  (define (insert-line h line)
    (le j (string-append (hdr-line h) "\n") (string-append (hdr-line h) "\n" line "\n")))
  (define (env-line k v) (string-append "          " k ": " v))
  (define (drop-part part) (replace-first (lane-key j) part ""))
  (define key-parts
    (if (lane-floor? j)
        (list "'packaging/floors.sexp', " ", 'scripts/ci/floor.sh'" ", 'scripts/ci/build-sqlite.sh'"
              ", 'scripts/ci/check-sqlite.sh'")
        (list "'scripts/ci/build-sqlite.sh', " ", 'scripts/ci/check-sqlite.sh'")))
  (define (pfx s) (string-append j ": " s))
  (define (restore-key-row name new-key msg-anchor-key)
    (row (pfx name)
         (list (se j (h-restore j) (key-line (lane-key j)) (key-line new-key)))
         (list (list (A j (hdr-line (h-restore j)) (key-line new-key)) (sql-key-msg j)))))
  (append
   ;; rule 3: the first step
   (list
    (row (pfx "the checkout without submodules")
         (list (le j "        with:\n          submodules: recursive\n" ""))
         (list (list (A j #f checkout-line)
                     (string-append "job " j "'s first step is not uses: actions/checkout@ with submodules: recursive"))))
    (row (pfx "the checkout with submodules: false")
         (list (le j "          submodules: recursive\n" "          submodules: false\n"))
         (list (list (A j #f checkout-line)
                     (string-append "job " j "'s first step is not uses: actions/checkout@ with submodules: recursive")))))

   ;; rule 4: each required run line deleted, and written twice
   (apply append
          (map (lambda (r)
                 (let ((h (car r)) (run (cadr r)))
                   (list
                    (row (pfx (string-append "the step that runs " run " deleted"))
                         (list (del-step j h))
                         (list (list (here) (n-steps j run 0))))
                    (row (pfx (string-append "the step that runs " run " written twice"))
                         (list (le j (step h) (string-append (step h) "\n" (step h))))
                         (list (list (here) (n-steps j run 2)))))))
               req))

   (list
    (row (pfx "the check after make build")
         (list (le j (string-append (step h-chk) "\n" (step (h-load j)))
                   (string-append (step (h-load j)) "\n" (step h-chk))))
         (list (list (A j (hdr-line (h-load j)) "        run: make build")
                     (out-of-order j build-run (lane-chk j)))))
    (row (pfx "make test before make build")
         (list (le j (string-append (step (h-load j)) "\n" (step (h-suites j)))
                   (string-append (step (h-suites j)) "\n" (step (h-load j)))))
         (list (list (A j (hdr-line (h-suites j)) "        run: make test")
                     (out-of-order j "make test" build-run))))
    (row (pfx "the SQLite build before check-chez")
         (list (del-step j (h-build j))
               (le j (step h-chk-chez) (string-append (step (h-build j)) "\n" (step h-chk-chez))))
         (list (list (A j (hdr-line (h-build j)) (string-append "        run: " (lane-bld j)))
                     (out-of-order j (lane-bld j) cc-line))))
    (row (pfx "the SQLite build without its if")
         (list (se j (h-build j) (string-append "        " if-sql "\n") ""))
         (list (list (HA (h-build j)) (step-no-if j (lane-bld j)))))
    (row (pfx "an if with another value on the SQLite build")
         (list (se j (h-build j) if-sql "if: false"))
         (list (list (A j (hdr-line (h-build j)) "        if: false") if-bad2)))
    (row (pfx "an if: always() on the SQLite check")
         (list (insert-line h-chk "        if: always()"))
         (list (list (A j (hdr-line h-chk) "        if: always()") if-bad2)
               (list (A j (hdr-line h-chk) "        if: always()") (step-has-if j (lane-chk j)))))
    (row (pfx "an if: always() on make build")
         (list (insert-line (h-load j) "        if: always()"))
         (list (list (A j (hdr-line (h-load j)) "        if: always()") if-bad2)
               (list (A j (hdr-line (h-load j)) "        if: always()") (step-has-if j build-run))))
    (row (pfx "an if: always() on make test")
         (list (insert-line (h-suites j) "        if: always()"))
         (list (list (A j (hdr-line (h-suites j)) "        if: always()") if-bad2)
               (list (A j (hdr-line (h-suites j)) "        if: always()") (step-has-if j "make test"))))
    (row (pfx "continue-on-error on make test")
         (list (insert-line (h-suites j) "        continue-on-error: true"))
         (list (list (A j (hdr-line (h-suites j)) "        continue-on-error: true")
                     (step-key "continue-on-error"))))
    (row (pfx "make test X")
         (list (se j (h-suites j) "        run: make test\n" "        run: make test X\n"))
         (cons (list (here) (n-steps j "make test" 0)) (wrong-step-pair j (h-suites j))))
    (row (pfx "make test as a block scalar")
         (list (se j (h-suites j) "        run: make test\n" "        run: |\n          make test\n"))
         (cons (list (here) (n-steps j "make test" 0)) (wrong-step-pair j (h-suites j))))
    (row (pfx "make build with an argument")
         (list (se j (h-load j) "        run: make build\n" "        run: make build X\n"))
         (cons (list (here) (n-steps j build-run 0)) (wrong-step-pair j (h-load j))))
    (row (pfx (if (lane-floor? j) "the check with --current" "the check without --current"))
         (list (se j h-chk (lane-chk j) (chk* j (if (lane-floor? j) " --current" ""))))
         (cons (list (here) (n-steps j (lane-chk j) 0)) (wrong-step-pair j h-chk)))
    (row (pfx "the build with the other lane's flag")
         (list (se j (h-build j) (lane-bld j) (bld* j (if (lane-floor? j) " --current" ""))))
         (list (list (here) (n-steps j (lane-bld j) 0))))
    (row (pfx "the build into another directory")
         (list (se j (h-build j) (lane-bld j) (string-append "scripts/ci/build-sqlite.sh \"$RUNNER_TEMP/sqlite-x\"" (lane-flag j))))
         (list (list (here) (n-steps j (lane-bld j) 0))))
    (row (pfx "the compiler step's line changed")
         (list (se j h-cc "head -n 1" "head -n 2"))
         (list (list (here) (n-steps j cc-line 0))))
    (row (pfx "the compiler step without its id")
         (list (se j h-cc "        id: cc\n" ""))
         (list (list (HA h-cc) (cc-id-msg j))))
    (row (pfx "check-chez with --nothreads")
         (list (se j h-chk-chez chk-t (string-append chk-t " --nothreads")))
         (list (list (here) (n-steps j chk-t 0)))))

   ;; rule 5: the ifs
   (list
    (row (pfx "the SQLite if on the Chez build")
         (list (se j h-build-chez "steps.chez." "steps.sqlite."))
         (list (list (A j (hdr-line h-build-chez) (string-append "        " if-sql)) sql-if-wrong)))
    (row (pfx "the Chez if on the SQLite build")
         (list (se j (h-build j) "steps.sqlite." "steps.chez."))
         (list (list (A j (hdr-line (h-build j)) (string-append "        " if-chez)) chez-if-wrong)))
    (row (pfx "the SQLite if on the Chez save")
         (list (se j h-save-chez "steps.chez.outputs.cache-hit" "steps.sqlite.outputs.cache-hit"))
         (list (list (A j (hdr-line h-save-chez) (string-append "        " if-sql)) sql-if-wrong)))
    (row (pfx "the Chez if on the SQLite save")
         (list (se j (h-save j) "steps.sqlite.outputs.cache-hit" "steps.chez.outputs.cache-hit"))
         (list (list (A j (hdr-line (h-save j)) (string-append "        " if-chez)) chez-if-wrong)))
    (row (pfx "the SQLite if on make test")
         (list (insert-line (h-suites j) (string-append "        " if-sql)))
         (list (list (A j (hdr-line (h-suites j)) (string-append "        " if-sql)) sql-if-wrong)
               (list (A j (hdr-line (h-suites j)) (string-append "        " if-sql)) (step-has-if j "make test"))))
    (row (pfx "the Chez if on make test")
         (list (insert-line (h-suites j) (string-append "        " if-chez)))
         (list (list (A j (hdr-line (h-suites j)) (string-append "        " if-chez)) chez-if-wrong)
               (list (A j (hdr-line (h-suites j)) (string-append "        " if-chez)) (step-has-if j "make test")))))

   ;; rule 6: the cache keys
   (map (lambda (part)
          (restore-key-row (string-append "the SQLite key drops " part) (drop-part part) #f))
        key-parts)
   (list
    (restore-key-row "the SQLite key hashes one file more"
                     (replace-first (lane-key j) "check-sqlite.sh')" "check-sqlite.sh', 'README.org')") #f)
    (restore-key-row "the SQLite key drops the compiler"
                     (replace-first (lane-key j) "-${{ steps.cc.outputs.id }}" "") #f)
    (restore-key-row "the SQLite key drops the image"
                     (replace-first (lane-key j) "-${{ steps.image.outputs.id }}" "") #f)
    (restore-key-row "the SQLite key takes the other lane's prefix"
                     (replace-first (lane-key j) (string-append "sqlite-" j "-") (string-append "sqlite-" (other-lane j) "-")) #f)
    (restore-key-row "the SQLite key takes the other lane's whole key"
                     (lane-key (other-lane j)) #f)
    (restore-key-row "the SQLite key has a tail"
                     (string-append (lane-key j) "-x") #f)
    (row (pfx "the SQLite restore's path is the other lane's")
         (list (se j (h-restore j) (path-line (sql-sq j)) (path-line (sql-sq (other-lane j)))))
         (list (list (A j (hdr-line (h-restore j)) (path-line (sql-sq (other-lane j)))) (path-msg j))))
    (row (pfx "the SQLite save's path is the other lane's")
         (list (se j (h-save j) (path-line (sql-sq j)) (path-line (sql-sq (other-lane j)))))
         ;; a save at the other lane's path is no save of this lane's cache, so
         ;; its if is held as well
         (list (list (A j (hdr-line (h-save j)) (string-append "        " if-sql)) sql-if-wrong)
               (list (A j (hdr-line (h-save j)) (path-line (sql-sq (other-lane j)))) (path-msg j))))
    (row (pfx "the SQLite save is keyed by the Chez cache")
         (list (se j (h-save j) "steps.sqlite.outputs.cache-primary-key" "steps.chez.outputs.cache-primary-key"))
         (list (list (A j (hdr-line (h-save j)) (key-line "${{ steps.chez.outputs.cache-primary-key }}"))
                     (save-key-msg j "sqlite"))))
    (row (pfx "the Chez save is keyed by the SQLite cache")
         (list (se j h-save-chez "steps.chez.outputs.cache-primary-key" "steps.sqlite.outputs.cache-primary-key"))
         (list (list (A j (hdr-line h-save-chez) (key-line "${{ steps.sqlite.outputs.cache-primary-key }}"))
                     (save-key-msg j "chez"))))
    (row (pfx "the SQLite save is keyed as a restore is")
         (list (se j (h-save j) "${{ steps.sqlite.outputs.cache-primary-key }}" (lane-key j)))
         (list (list (A j (hdr-line (h-save j)) (key-line (lane-key j))) (save-key-msg j "sqlite"))))
    (row (pfx "the Chez key drops a file")
         (list (se j h-restore-chez ", 'scripts/ci/check-chez.sh'" ""))
         (list (list (A j (hdr-line h-restore-chez)
                        "          key: chez-threads-${{ hashFiles('packaging/floors.sexp', 'scripts/ci/floor.sh', 'scripts/ci/build-chez.sh') }}-${{ steps.image.outputs.id }}")
                     (cache-key j "chez-threads-"))))
    (row (pfx "the Chez cache's path is the SQLite cache's")
         (list (se j h-restore-chez "/chez-threads\n" (string-append "/sqlite-" j "\n")))
         (list (list (A j (hdr-line h-restore-chez) chez-key-line)
                     (sql-key-msg j)))))

   ;; rule 7: the env keys
   (let ((chk-env (lambda (k v) (env-line k v))))
     (list
      (row (pfx "the check's library is the other lane's")
           (list (se j h-chk (chk-env "CHEZ_SQLITE3_LIBRARY" (sql-lib j)) (chk-env "CHEZ_SQLITE3_LIBRARY" (sql-lib (other-lane j)))))
           (list (list (A j (hdr-line h-chk) (chk-env "CHEZ_SQLITE3_LIBRARY" (sql-lib (other-lane j))))
                       (env-value j "CHEZ_SQLITE3_LIBRARY" (sql-lib j)))))
      (row (pfx "the suites' header directory has a second directory")
           (list (se j (h-suites j) (chk-env "C_INCLUDE_PATH" (sql-inc j)) (chk-env "C_INCLUDE_PATH" (string-append (sql-inc j) ":/usr/include"))))
           (list (list (A j (hdr-line (h-suites j)) (chk-env "C_INCLUDE_PATH" (string-append (sql-inc j) ":/usr/include")))
                       (env-value j "C_INCLUDE_PATH" (sql-inc j)))))
      (row (pfx "the library's value is relative")
           (list (se j (h-load j) (chk-env "CHEZ_SQLITE3_LIBRARY" (sql-lib j)) (chk-env "CHEZ_SQLITE3_LIBRARY" "lib/libsqlite3.so.0")))
           (list (list (A j (hdr-line (h-load j)) (chk-env "CHEZ_SQLITE3_LIBRARY" "lib/libsqlite3.so.0"))
                       (env-value j "CHEZ_SQLITE3_LIBRARY" (sql-lib j)))))
      (row (pfx "the check's CHEZ is the nothreads Chez")
           (list (se j h-chk (chk-env "CHEZ" chez-t) (chk-env "CHEZ" chez-n)))
           (list (list (A j (hdr-line h-chk) (chk-env "CHEZ" chez-n)) (env-chez j chez-t))))
      (row (pfx "make test without C_INCLUDE_PATH")
           (list (se j (h-suites j) (string-append (chk-env "C_INCLUDE_PATH" (sql-inc j)) "\n") ""))
           (list (list (HA (h-suites j)) (env-missing j "make test" "C_INCLUDE_PATH"))))
      (row (pfx "make build without CHEZ_SQLITE3_LIBRARY")
           (list (se j (h-load j) (string-append (chk-env "CHEZ_SQLITE3_LIBRARY" (sql-lib j)) "\n") ""))
           (list (list (HA (h-load j)) (env-missing j build-run "CHEZ_SQLITE3_LIBRARY"))))
      (row (pfx "the check without CHEZ")
           (list (se j h-chk (string-append (chk-env "CHEZ" chez-t) "\n") ""))
           (list (list (HA h-chk) (env-missing j (lane-chk j) "CHEZ"))))
      (row (pfx "the check without any env")
           (list (se j h-chk (string-append "        env:\n" (chk-env "CHEZ" chez-t) "\n" (chk-env "CHEZ_SQLITE3_LIBRARY" (sql-lib j)) "\n" (chk-env "C_INCLUDE_PATH" (sql-inc j)) "\n") ""))
           (list (list (HA h-chk) (env-missing j (lane-chk j) "CHEZ"))
                 (list (HA h-chk) (env-missing j (lane-chk j) "CHEZ_SQLITE3_LIBRARY"))
                 (list (HA h-chk) (env-missing j (lane-chk j) "C_INCLUDE_PATH"))))
      (row (pfx "the SQLite build without CHEZ")
           (list (se j (h-build j) (string-append "        env:\n" (chk-env "CHEZ" chez-t) "\n") ""))
           (list (list (HA (h-build j)) (env-missing j (lane-bld j) "CHEZ"))))
      (row (pfx "the SQLite build with the override")
           (list (se j (h-build j) (string-append (chk-env "CHEZ" chez-t) "\n")
                     (string-append (chk-env "CHEZ" chez-t) "\n" (chk-env "CHEZ_SQLITE3_LIBRARY" (sql-lib j)) "\n")))
           (list (list (A j (hdr-line (h-build j)) (chk-env "CHEZ_SQLITE3_LIBRARY" (sql-lib j)))
                       (env-wrong-step "CHEZ_SQLITE3_LIBRARY"))))
      (row (pfx "the SQLite restore with the header directory")
           (list (se j (h-restore j) "        with:\n"
                     (string-append "        env:\n" (chk-env "C_INCLUDE_PATH" (sql-inc j)) "\n        with:\n")))
           (list (list (A j (hdr-line (h-restore j)) (chk-env "C_INCLUDE_PATH" (sql-inc j)))
                       (env-wrong-step "C_INCLUDE_PATH"))))
      (row (pfx "the Chez build with the override")
           (list (se j h-build-chez "        run:" (string-append "        env:\n" (chk-env "CHEZ_SQLITE3_LIBRARY" (sql-lib j)) "\n        run:")))
           (list (list (A j (hdr-line h-build-chez) (chk-env "CHEZ_SQLITE3_LIBRARY" (sql-lib j)))
                       (env-wrong-step "CHEZ_SQLITE3_LIBRARY"))))))
   ;; rule 7, the names that stay refused
   (map (lambda (k)
          (row (pfx (string-append "the suites' env gains " k))
               (list (se j (h-suites j) (string-append "          CHEZ: " chez-t "\n")
                         (string-append "          CHEZ: " chez-t "\n          " k ": x\n")))
               (list (list (A j (hdr-line (h-suites j)) (string-append "          " k ": x")) (names-msg k))
                     (list (A j (hdr-line (h-suites j)) (string-append "          " k ": x")) (lane-env-key k)))))
        '("CPATH" "LD_LIBRARY_PATH" "CC" "MAKEFLAGS" "CHEZ_SQLITE3_DECOY"))

   ;; rule 8: the names on every other line
   (list
    (row (pfx "a run block exports CHEZ_SQLITE3_LIBRARY")
         (list (se j h-image id-line (string-append id-line "          export CHEZ_SQLITE3_LIBRARY=x\n")))
         (list (list (A j (hdr-line h-image) "          export CHEZ_SQLITE3_LIBRARY=x") (names-msg "CHEZ_SQLITE3_LIBRARY"))))
    (row (pfx "C_INCLUDE_PATH is written to GITHUB_ENV")
         (list (se j h-image id-line (string-append id-line "          echo C_INCLUDE_PATH=/x >> \"$GITHUB_ENV\"\n")))
         (list (list (A j (hdr-line h-image) "          echo C_INCLUDE_PATH=/x >> \"$GITHUB_ENV\"") (names-msg "GITHUB_ENV"))
               (list (A j (hdr-line h-image) "          echo C_INCLUDE_PATH=/x >> \"$GITHUB_ENV\"") (names-msg "C_INCLUDE_PATH"))))
    (row (pfx "a step's name names C_INCLUDE_PATH")
         (list (le j (hdr-line (h-load j)) "      - name: Load C_INCLUDE_PATH"))
         (list (list (A j #f "      - name: Load C_INCLUDE_PATH") (names-msg "C_INCLUDE_PATH"))))
    (row (pfx "a with value names CHEZ_SQLITE3_LIBRARY")
         (list (se j (h-restore j) (path-line (sql-sq j)) (path-line "CHEZ_SQLITE3_LIBRARY")))
         (list (list (A j (hdr-line (h-restore j)) (path-line "CHEZ_SQLITE3_LIBRARY")) (names-msg "CHEZ_SQLITE3_LIBRARY"))
               (list (A j (hdr-line (h-restore j)) (path-line "CHEZ_SQLITE3_LIBRARY")) (path-msg j))))
    (row (pfx "a run line names C_INCLUDE_PATH")
         (list (se j (h-load j) "        run: make build\n" "        run: make build C_INCLUDE_PATH=x\n"))
         (list (list (A j (hdr-line (h-load j)) "        run: make build C_INCLUDE_PATH=x") (names-msg "C_INCLUDE_PATH"))
               (list (here) (n-steps j build-run 0))
               (car (wrong-step-pair j (h-load j)))
               (cadr (wrong-step-pair j (h-load j))))))

   ;; rule 9: the spellings, over the lane
   (list
    (row (pfx "a quoted key, \"if\": false")
         (list (insert-line (h-load j) "        \"if\": false"))
         (list (list (A j (hdr-line (h-load j)) "        \"if\": false") quoted-msg)))
    (row (pfx "an explicit key, ? if")
         (list (insert-line (h-load j) "        ? if\n        : false"))
         (list (list (A j (hdr-line (h-load j)) "        ? if") explicit-msg)
               (list (A j (hdr-line (h-load j)) "        : false") (step-key "")))))

   ;; rule 2: the job's keys
   (map (lambda (k)
          (row (pfx (string-append "a job key " k))
               (list (le j "    runs-on: ubuntu-24.04\n" (string-append "    runs-on: ubuntu-24.04\n    " k ": x\n")))
               (list (list (A j #f (string-append "    " k ": x")) (job-key j k)))))
        job-keys)
   (list
    (row (pfx "runs-on is not ubuntu-24.04")
         (list (le j "    runs-on: ubuntu-24.04\n" (string-append "    runs-on: " (if (lane-floor? j) "macos-15" "ubuntu-latest") "\n")))
         (list (list (A j #f (string-append "    runs-on: " (if (lane-floor? j) "macos-15" "ubuntu-latest"))) (job-runs-on j))))
    (row (pfx "the job has no timeout-minutes")
         (list (le j "    timeout-minutes: 60\n" ""))
         (list (list (here) (job-no-key j "timeout-minutes")))))))


(define (env-ln k v) (string-append "          " k ": " v))

;; The rows that are not a lane's: the job list, and the two names in the jobs
;; that must stay refused them.
(define lane-global-rows
  (list
   (row "the floor job deleted"
        (list (e (string-append (span "  # SQLite at its floor" "run: make test\n") "\n") ""))
        (list (list "jobs:" (job-missing "floor"))))
   (row "the current job deleted"
        (list (e (string-append "\n" (span "  # SQLite at the current release" "run: make test\n")) ""))
        (list (list "jobs:" (job-missing "current"))))
   (row "a sixth job"
        (list (le "current" "        run: make test\n"
                  (string-append "        run: make test\n\n"
                                 (lines "  extra:" "    name: x" "    runs-on: ubuntu-24.04"
                                        "    timeout-minutes: 5" "    steps:" "      - run: echo hi"))))
        (list (list "  extra:" (job-unknown "extra"))))

   (row "main's install check gains CHEZ_SQLITE3_LIBRARY, with floor's exact value"
        (list (insert-after (string-append install-hdr "\n        env:\n          CHEZ: " chez-t "\n")
                            (string-append (env-ln "CHEZ_SQLITE3_LIBRARY" (sql-lib "floor")) "\n")))
        (list (list (A "main" install-hdr (env-ln "CHEZ_SQLITE3_LIBRARY" (sql-lib "floor"))) (names-msg "CHEZ_SQLITE3_LIBRARY"))
              (list (A "main" install-hdr (env-ln "CHEZ_SQLITE3_LIBRARY" (sql-lib "floor"))) (env-key "CHEZ_SQLITE3_LIBRARY"))))
   (row "main's install check gains C_INCLUDE_PATH, with floor's exact value"
        (list (insert-after (string-append install-hdr "\n        env:\n          CHEZ: " chez-t "\n")
                            (string-append (env-ln "C_INCLUDE_PATH" (sql-inc "floor")) "\n")))
        (list (list (A "main" install-hdr (env-ln "C_INCLUDE_PATH" (sql-inc "floor"))) (names-msg "C_INCLUDE_PATH"))
              (list (A "main" install-hdr (env-ln "C_INCLUDE_PATH" (sql-inc "floor"))) (env-key "C_INCLUDE_PATH"))))
   (row "memory's gate step gains C_INCLUDE_PATH, with floor's exact value"
        (list (insert-after (string-append "      - name: The gate must fail on planted defects\n        env:\n          CHEZ: " chez-t "\n")
                            (string-append (env-ln "C_INCLUDE_PATH" (sql-inc "floor")) "\n")))
        (list (list (A "memory" "      - name: The gate must fail on planted defects" (env-ln "C_INCLUDE_PATH" (sql-inc "floor")))
                    (names-msg "C_INCLUDE_PATH"))
              (list (A "memory" "      - name: The gate must fail on planted defects" (env-ln "C_INCLUDE_PATH" (sql-inc "floor")))
                    (env-key "C_INCLUDE_PATH"))))
   (row "memory's gate step gains CHEZ_SQLITE3_LIBRARY, with floor's exact value"
        (list (insert-after (string-append "      - name: The gate must fail on planted defects\n        env:\n          CHEZ: " chez-t "\n")
                            (string-append (env-ln "CHEZ_SQLITE3_LIBRARY" (sql-lib "floor")) "\n")))
        (list (list (A "memory" "      - name: The gate must fail on planted defects" (env-ln "CHEZ_SQLITE3_LIBRARY" (sql-lib "floor")))
                    (names-msg "CHEZ_SQLITE3_LIBRARY"))
              (list (A "memory" "      - name: The gate must fail on planted defects" (env-ln "CHEZ_SQLITE3_LIBRARY" (sql-lib "floor")))
                    (env-key "CHEZ_SQLITE3_LIBRARY"))))
   (row "nothreads's step gains CHEZ_SQLITE3_LIBRARY, with floor's exact value"
        (list (insert-after (string-append "      - name: Every library must be refused, by name\n        env:\n          CHEZ: " chez-n "\n")
                            (string-append (env-ln "CHEZ_SQLITE3_LIBRARY" (sql-lib "floor")) "\n")))
        (list (list (A "nothreads" "      - name: Every library must be refused, by name" (env-ln "CHEZ_SQLITE3_LIBRARY" (sql-lib "floor")))
                    (names-msg "CHEZ_SQLITE3_LIBRARY"))
              (list (A "nothreads" "      - name: Every library must be refused, by name" (env-ln "CHEZ_SQLITE3_LIBRARY" (sql-lib "floor")))
                    (env-key "CHEZ_SQLITE3_LIBRARY"))))
   (row "nothreads's step gains C_INCLUDE_PATH, with floor's exact value"
        (list (insert-after (string-append "      - name: Every library must be refused, by name\n        env:\n          CHEZ: " chez-n "\n")
                            (string-append (env-ln "C_INCLUDE_PATH" (sql-inc "floor")) "\n")))
        (list (list (A "nothreads" "      - name: Every library must be refused, by name" (env-ln "C_INCLUDE_PATH" (sql-inc "floor")))
                    (names-msg "C_INCLUDE_PATH"))
              (list (A "nothreads" "      - name: Every library must be refused, by name" (env-ln "C_INCLUDE_PATH" (sql-inc "floor")))
                    (env-key "C_INCLUDE_PATH"))))))

(define rows
  (append
   (list
    (row "the unedited file passes" '() '())

    ;; --- the spellings a text reader cannot see ---
    (row "a quoted key, \"if\": false"
         (list (e "        run: make test-memory\n"
                  "        \"if\": false\n        run: make test-memory\n"))
         (list (list "        \"if\": false" quoted-msg)))
    (row "a single-quoted key, 'if': false"
         (list (e "        run: make test-memory\n"
                  "        'if': false\n        run: make test-memory\n"))
         (list (list "        'if': false" quoted-msg)))
    (row "white space between a key and its colon, if : false"
         (list (e "        run: make test-memory\n"
                  "        if : false\n        run: make test-memory\n"))
         (list (list "        if : false" space-msg)))
    (row "an explicit key, ? if"
         (list (e "        run: make test-memory\n"
                  "        ? if\n        : false\n        run: make test-memory\n"))
         (list (list "        ? if" explicit-msg)
               (list "        : false" (step-key ""))))
    (row "an anchor where a key goes"
         (list (e "        run: make test-memory\n"
                  "        &a if: false\n        run: make test-memory\n"))
         (list (list "        &a if: false" alias-msg)))
    (row "an alias where a key goes"
         (list (e "        run: make test-memory\n"
                  "        *a if: false\n        run: make test-memory\n"))
         (list (list "        *a if: false" alias-msg)))
    (row "an anchor on a step's key, - &a uses: x"
         (list (insert-after "        run: scripts/ci/check-action-pins.sh .github/workflows\n"
                             "\n      - &a uses: owner/action@main\n"))
         (list (list "      - &a uses: owner/action@main" alias-msg)))
    (row "an unpinned action hidden by - ? uses / : owner/action@main"
         (list (insert-after "        run: scripts/ci/check-action-pins.sh .github/workflows\n"
                             "\n      - ? uses\n        : owner/action@main\n"))
         (list (list "      - ? uses" explicit-msg)
               (list "        : owner/action@main" (step-key ""))))
    (row "a flow mapping in a name"
         (list (e "    name: memory (the Valgrind gate)\n"
                  "    name: memory {the Valgrind gate}\n"))
         (list (list "    name: memory {the Valgrind gate}" flow-msg)))
    (row "a { inside a quoted scalar passes"
         (list (e "    name: memory (the Valgrind gate)\n"
                  "    name: \"memory {the Valgrind gate}\"\n"))
         '())
    (row "a backslash after a double quote"
         (list (e "    name: memory (the Valgrind gate)\n"
                  "    name: \"memory\\x2D\"\n"))
         (list (list "    name: \"memory\\x2D\"" bsq-msg)))
    (row "a quoted scalar left open"
         (list (e "    name: memory (the Valgrind gate)\n"
                  "    name: \"memory\n"))
         (list (list "    name: \"memory" openq-msg)))
    (row "a tab in a structural line"
         (list (e "main (checks and suites" "main\t(checks and suites"))
         (list (list "    name: main\t(checks and suites, Chez built from source)" tab-msg)))
    (row "a tab in a block scalar's content"
         (list (in-id-block (lambda (old) (replace-first old "id=$" "id=\t$"))))
         (list (list "          echo \"id=\t${ID}-${VERSION_ID}-${RUNNER_ARCH}\" >> \"$GITHUB_OUTPUT\"" tab-msg)))
    (row "a character beyond ASCII in a structural line"
         (list (e "main (checks and suites" "ma\x131;n (checks and suites"))
         (list (list "    name: ma\x131;n (checks and suites, Chez built from source)" odd-msg)))
    (row "a key spelled with a dotless i"
         (list (e "        run: make test-memory\n"
                  "        \x131;f: false\n        run: make test-memory\n"))
         (list (list "        \x131;f: false" odd-msg)))
    (row "a character beyond ASCII in a block scalar's content"
         (list (in-id-block (lambda (old) (replace-first old "id=$" "id=\xe9;$"))))
         (list (list "          echo \"id=\xe9;${ID}-${VERSION_ID}-${RUNNER_ARCH}\" >> \"$GITHUB_OUTPUT\"" odd-msg)))
    (row "key-looking lines inside a block scalar are content, and pass"
         (list (after-id "if: false" "? x" "\"q\": 1" "*a" "foo: {x}" "&b c: d" ))
         '())
    (row "a line dedented out of a block scalar is read again"
         (list (in-id-block (lambda (old) (string-append old "        shell: bash\n"))))
         (list (list "        shell: bash" (step-key "shell")))))

   ;; --- the names no line may hold ---
   (list
    (row "GITHUB_ENV written as MAKE\"\"FLAGS"
         (list (after-id "echo \"MAKE\"\"FLAGS=-i\" >> \"$GITHUB_ENV\""))
         (list (list "          echo \"MAKE\"\"FLAGS=-i\" >> \"$GITHUB_ENV\"" (names-msg "GITHUB_ENV"))))
    (row "GITHUB_PATH in a block scalar"
         (list (after-id "echo /x >> \"$GITHUB_PATH\""))
         (list (list "          echo /x >> \"$GITHUB_PATH\"" (names-msg "GITHUB_PATH"))))
    (row "a word of the allowed set, SUITES_X, is no name held"
         (list (after-id "echo SUITES_X MAKEFLAGSX timeout"))
         '())
    (row "CHEZ_SQLITE3_LIBRARY at the workflow's top level"
         (list (e "permissions:\n  contents: read\n"
                  "env:\n  CHEZ_SQLITE3_LIBRARY: /x\npermissions:\n  contents: read\n"))
         (list (list "env:" (top-unknown "env"))
               (list "  CHEZ_SQLITE3_LIBRARY: /x" (names-msg "CHEZ_SQLITE3_LIBRARY"))))
    (row "CHEZ_SQLITE3_LIBRARY in a step's env"
         (list (insert-after (string-append "      - name: Every suite under Valgrind\n        env:\n          CHEZ: " chez-t "\n")
                             "          CHEZ_SQLITE3_LIBRARY: /x\n"))
         (list (list "          CHEZ_SQLITE3_LIBRARY: /x" (names-msg "CHEZ_SQLITE3_LIBRARY"))
               (list "          CHEZ_SQLITE3_LIBRARY: /x" (env-key "CHEZ_SQLITE3_LIBRARY")))))

   (map (lambda (w)
          (row (string-append "a block scalar names " w)
               (list (after-id (string-append "echo " w)))
               (list (list (string-append "          echo " w) (names-msg w)))))
        banned-words)

   (map (lambda (w)
          (row (string-append "a block scalar names " w ", a gate")
               (list (after-id (string-append "echo " w)))
               (list (list (string-append "          echo " w) (gate-msg w)))))
        '("check-memory-gate" "test-memory" "check-nothreads"))

   ;; --- the top of the file ---
   (list
    (row "the on block gets a path filter"
         (list (e "  pull_request:\n" "  pull_request:\n    paths: [src/**]\n"))
         (list (list "    paths: [src/**]"
                     (block-differs "on" "  workflow_dispatch:" "    paths: [src/**]"))))
    (row "the on block gets another trigger"
         (list (insert-after "  workflow_dispatch:\n" "  workflow_run:\n"))
         (list (list "  workflow_run:" (block-extra "on" "  workflow_run:"))))
    (row "the on block loses a trigger"
         (list (e "  workflow_dispatch:\n" ""))
         (list (list "  pull_request:" (string-append "the \"on\" block ends early: expected \"  workflow_dispatch:\""))))
    (row "the permissions widen"
         (list (e "  contents: read\n" "  contents: write\n"))
         (list (list "  contents: write" (block-differs "permissions" "  contents: read" "  contents: write"))))
    (row "the concurrency group changes"
         (list (e "  cancel-in-progress: ${{ github.event_name == 'pull_request' }}\n"
                  "  cancel-in-progress: false\n"))
         (list (list "  cancel-in-progress: false"
                     (block-differs "concurrency"
                                    "  cancel-in-progress: ${{ github.event_name == 'pull_request' }}"
                                    "  cancel-in-progress: false"))))
    (row "a top-level defaults"
         (list (e "permissions:\n" "defaults:\n  run:\n    shell: bash\npermissions:\n"))
         (list (list "defaults:" (top-unknown "defaults"))))
    (row "a top-level key twice"
         (list (e "name: CI\n" "name: CI\nname: CI\n"))
         (list (list '("name: CI" 2) (top-twice "name"))))
    (row "permissions after concurrency"
         (list (e "permissions:\n  contents: read\n" "")
               (insert-after "  cancel-in-progress: ${{ github.event_name == 'pull_request' }}\n"
                             "permissions:\n  contents: read\n"))
         (list (list "permissions:" (top-order "permissions"))))
    (row "no jobs key"
         (list (e "jobs:\n" "jobz:\n"))
         ;; With no jobs key no job is known, so no lane's env may name the two
         ;; names: each of the six lines is refused.
         (append (list (list "jobz:" (top-unknown "jobz"))
                       (list "        run: make check-memory-gate" (gate-msg "check-memory-gate"))
                       (list "        run: make test-memory" (gate-msg "test-memory"))
                       (list "        run: make check-nothreads" (gate-msg "check-nothreads")))
                 (lane-name-problems "floor")
                 (lane-name-problems "current")
                 (list (list 'eof (top-missing "jobs"))))))

   ;; --- jobs ---
   (list
    (row "the nothreads job deleted"
         (list (e (span "  nothreads:\n    name:" "run: make check-nothreads\n") ""))
         (list (list "jobs:" (job-missing "nothreads"))))
    (row "a job added"
         (list (insert-after "        run: make check-nothreads\n"
                             (string-append "\n" (lines "  extra:" "    name: x" "    runs-on: ubuntu-24.04"
                                                        "    timeout-minutes: 5" "    steps:" "      - run: echo hi"))))
         (list (list "  extra:" (job-unknown "extra"))))
    (row "a job's runs-on changes"
         (list (e "    name: main (checks and suites, Chez built from source)\n    runs-on: ubuntu-24.04\n"
                  "    name: main (checks and suites, Chez built from source)\n    runs-on: ubuntu-latest\n"))
         (list (list "    runs-on: ubuntu-latest" (job-runs-on "main"))))
    (row "a job's timeout-minutes is no number"
         (list (e "    timeout-minutes: 60\n    steps:\n      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1\n        with:\n          submodules: recursive\n\n      # Every"
                  "    timeout-minutes: sixty\n    steps:\n      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1\n        with:\n          submodules: recursive\n\n      # Every"))
         (list (list "    timeout-minutes: sixty" (job-timeout "main"))))
    (row "a job without timeout-minutes"
         (list (e "    name: main (checks and suites, Chez built from source)\n    runs-on: ubuntu-24.04\n    timeout-minutes: 60\n"
                  "    name: main (checks and suites, Chez built from source)\n    runs-on: ubuntu-24.04\n"))
         (list (list "  main:" (job-no-key "main" "timeout-minutes"))))
    (row "a job key twice"
         (list (e "    name: memory (the Valgrind gate)\n"
                  "    name: memory (the Valgrind gate)\n    runs-on: ubuntu-24.04\n"))
         (list (list '("    runs-on: ubuntu-24.04" 3) (job-key-twice "memory" "runs-on"))))
    (row "a job key with a value where a block goes, steps: x"
         (list (e "    steps:\n      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1\n\n      - name: Install the packages in packaging/debian-prereqs.txt\n"
                  "    steps: x\n      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1\n\n      - name: Install the packages in packaging/debian-prereqs.txt\n"))
         (list (list "    steps: x" hasval-msg))))

   (map (lambda (k)
          (row (string-append "a job key " k)
               (list (e "    name: memory (the Valgrind gate)\n"
                        (string-append "    name: memory (the Valgrind gate)\n    " k ": x\n")))
               (list (list (string-append "    " k ": x") (job-key "memory" k)))))
        job-keys)

   (list
    (row "O1: continue-on-error on job memory"
         (list (e "    name: memory (the Valgrind gate)\n"
                  "    name: memory (the Valgrind gate)\n    continue-on-error: true\n"))
         (list (list "    continue-on-error: true" (job-key "memory" "continue-on-error"))))
    (row "O2: an if on the test-memory step"
         (list (e "      - name: Every suite under Valgrind\n        env:\n"
                  "      - name: Every suite under Valgrind\n        if: always()\n        env:\n"))
         (list (list "        if: always()" if-bad)
               (list "        if: always()" if-wrong)
               (list "        if: always()" (step-has-if "memory" "make test-memory"))))
    (row "O3: continue-on-error on the check-memory-gate step"
         (list (e "      - name: The gate must fail on planted defects\n        env:\n"
                  "      - name: The gate must fail on planted defects\n        continue-on-error: true\n        env:\n"))
         (list (list "        continue-on-error: true" (step-key "continue-on-error"))))
    (row "O4: test-memory with an argument"
         (list (e "        run: make test-memory\n"
                  "        run: make test-memory MEMORY_SUITES=tests/test-counters.sps\n"))
         (list (list "        run: make test-memory MEMORY_SUITES=tests/test-counters.sps"
                     (names-msg "MEMORY_SUITES"))
               (list "        run: make test-memory MEMORY_SUITES=tests/test-counters.sps"
                     (gate-msg "test-memory"))
               (list "  memory:" (n-steps "memory" "make test-memory" 0))))
    (row "O5: check-memory-gate never runs"
         (list (e (span "      # The gate proves nothing unless it can fail"
                        "run: make check-memory-gate\n\n")
                  ""))
         (list (list "  memory:" (n-steps "memory" "make check-memory-gate" 0))))
    (row "O6: test-memory runs before check-memory-gate"
         (list (e (string-append (gate-step) "\n" (valgrind-step))
                  (string-append (valgrind-step) "\n" (gate-step))))
         (list (list "        run: make test-memory"
                     (out-of-order "memory" "make test-memory" "make check-memory-gate"))))
    (row "O7: MAKEFLAGS in the gate step's env"
         (list (insert-after (string-append "      - name: The gate must fail on planted defects\n        env:\n          CHEZ: " chez-t "\n")
                             "          MAKEFLAGS: -i\n"))
         (list (list "          MAKEFLAGS: -i" (names-msg "MAKEFLAGS"))
               (list "          MAKEFLAGS: -i" (env-key "MAKEFLAGS"))))
    (row "O8: a run block that names the gate"
         (list (e "      # The gate proves nothing unless it can fail"
                  "      - name: sneak\n        run: |\n          make check-memory-gate\n\n      # The gate proves nothing unless it can fail"))
         (list (list "          make check-memory-gate" (gate-msg "check-memory-gate"))))
    (row "O9: VALGRIND_OPTS written through GITHUB_ENV"
         (list (after-id "echo VALGRIND_OPTS=--x >> \"$GITHUB_ENV\""))
         (list (list "          echo VALGRIND_OPTS=--x >> \"$GITHUB_ENV\"" (names-msg "GITHUB_ENV"))
               (list "          echo VALGRIND_OPTS=--x >> \"$GITHUB_ENV\"" (names-msg "VALGRIND_OPTS"))))
    (row "a trailing comment on a gate's run line"
         (list (e "        run: make test-memory\n" "        run: make test-memory # x\n"))
         (list (list "        run: make test-memory # x" (gate-msg "test-memory"))
               (list "  memory:" (n-steps "memory" "make test-memory" 0))))
    (row "a gate's run line as a block scalar"
         (list (e "        run: make test-memory\n" "        run: |\n          make test-memory\n"))
         (list (list "          make test-memory" (gate-msg "test-memory"))
               (list "  memory:" (n-steps "memory" "make test-memory" 0))))
    (row "a gate's run line in the wrong job"
         (list (e "        run: make check-nothreads\n" "        run: make test-memory\n"))
         (list (list '("        run: make test-memory" 2) (gate-msg "test-memory"))
               (list "  nothreads:" (n-steps "nothreads" "make check-nothreads" 0)))))

   ;; --- steps ---
   (map (lambda (k)
          (row (string-append "a step key " k)
               (list (e "        run: make check-nothreads\n"
                        (string-append "        " k ": x\n        run: make check-nothreads\n")))
               (list (list (string-append "        " k ": x") (step-key k)))))
        step-keys-refused)

   (list
    (row "a with key outside the three"
         (list (e "      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1\n\n      - name: Install the packages in packaging/debian-prereqs.txt\n"
                  "      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1\n        with:\n          ref: x\n\n      - name: Install the packages in packaging/debian-prereqs.txt\n"))
         (list (list "          ref: x" (with-key "ref"))))
    (row "a flow mapping under with"
         (list (e "      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1\n\n      - name: Install the packages in packaging/debian-prereqs.txt\n"
                  "      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1\n        with: {ref: x}\n\n      - name: Install the packages in packaging/debian-prereqs.txt\n"))
         (list (list "        with: {ref: x}" flow-msg)))
    (row "an env key besides CHEZ"
         (list (insert-after (string-append "      - name: Every library must be refused, by name\n        env:\n          CHEZ: " chez-n "\n")
                             "          FOO: x\n"))
         (list (list "          FOO: x" (env-key "FOO"))))
    (row "the CHEZ path of main swapped to nothreads's"
         (list (e (string-append "      - name: Checks and suites\n        env:\n          CHEZ: " chez-t "\n")
                  (string-append "      - name: Checks and suites\n        env:\n          CHEZ: " chez-n "\n")))
         (list (list (list 'in "main" "      - name: Checks and suites" (string-append "          CHEZ: " chez-n))
                     (env-chez "main" chez-t))))
    (row "the CHEZ path of nothreads swapped to main's"
         (list (e (string-append "      - name: Every library must be refused, by name\n        env:\n          CHEZ: " chez-n "\n")
                  (string-append "      - name: Every library must be refused, by name\n        env:\n          CHEZ: " chez-t "\n")))
;; The swapped line is named by its step's header, not by its place among
;; the file's CHEZ lines.
         (list (list (list 'after "      - name: Every library must be refused, by name"
                           (string-append "          CHEZ: " chez-t))
                     (env-chez "nothreads" chez-n))))
    (row "an if with another value"
         (list (e (string-append "        if: steps.chez.outputs.cache-hit != 'true'\n        run: " bld-n "\n")
                  (string-append "        if: false\n        run: " bld-n "\n")))
         (list (list "        if: false" if-bad)))
    (row "the nothreads build without its if"
         (list (e (string-append "        if: steps.chez.outputs.cache-hit != 'true'\n        run: " bld-n "\n")
                  (string-append "        run: " bld-n "\n")))
         (list (list "      - name: Build Chez without threads" (step-no-if "nothreads" bld-n))))
    (row "the cache's if on the wrong step"
         (list (e "      - name: Checks and suites\n        env:\n"
                  "      - name: Checks and suites\n        if: steps.chez.outputs.cache-hit != 'true'\n        env:\n"))
         (list (list (list 'in "main" "      - name: Checks and suites" (string-append "        " if-line)) if-wrong)
               (list (list 'in "main" "      - name: Checks and suites" (string-append "        " if-line))
                     (step-has-if "main" make-line))))
    (row "an if on a required check"
         (list (e "      - name: Check the Chez this job runs\n        run: scripts/ci/check-chez.sh \"$RUNNER_TEMP/chez-nothreads\" --nothreads\n"
                  "      - name: Check the Chez this job runs\n        if: always()\n        run: scripts/ci/check-chez.sh \"$RUNNER_TEMP/chez-nothreads\" --nothreads\n"))
         (list (list "        if: always()" if-bad)
               (list "        if: always()" if-wrong)
               (list "        if: always()" (step-has-if "nothreads" chk-n)))))

   ;; --- the checks each job must run ---
   (map (lambda (w)
          (row (string-append "main's make line without " w)
               (list (e (string-append "        run: " make-line "\n")
                        (string-append "        run: " (without-word make-line w) "\n")))
               (list (list "  main:" (n-steps "main" make-line 0)))))
        make-words)

   (list
    (row "main's pin step deleted"
         (list (e (span "      # Every line with a uses key in this directory"
                        "run: scripts/ci/check-action-pins.sh .github/workflows\n\n")
                  ""))
         (list (list (list 'after "  main:" "      - name: Install the packages in packaging/debian-prereqs.txt")
                     second-step-msg)))
    (row "main's checkout without submodules"
         (list (e "        with:\n          submodules: recursive\n\n      # Every line"
                  "\n      # Every line"))
         (list (list (list 'in "main" #f checkout-line)
                     first-step-msg)))
    (row "main's checkout with submodules: false"
         (list (e "          submodules: recursive\n\n      # Every line"
                  "          submodules: false\n\n      # Every line"))
         (list (list (list 'in "main" #f checkout-line)
                     first-step-msg)))
    (row "main's launcher step deleted"
         (list (e (span "      # The launcher's own tests run no Guix" "run: sh tests/guix-env-launcher.sh\n") ""))
         (list (list "  main:" (n-steps "main" launcher 0))))
    (row "main's check-chez step deleted"
         (list (let ((hdr "      - name: Report the versions this run uses\n"))
                 (e (span-after "  main:\n" "      - name: Check the Chez this job runs\n" hdr) hdr)))
         (list (list "  main:" (n-steps "main" chk-t 0))))
    ;; ADR-0002's install check: make build, a step of its own, after
    ;; check-chez and before the make line.
    (row "main's install check deleted"
         (list (e (string-append (install-step) "\n") ""))
         (list (list "  main:" (n-steps "main" build-run 0))))
    (row "main's install check written twice"
         (list (e (string-append (install-step) "\n")
                  (string-append (install-step) "\n" (install-step) "\n")))
         (list (list "  main:" (n-steps "main" build-run 2))))
    (row "main's install check moved after Checks and suites"
         (list (e (string-append (install-step) "\n") "")
               (e (make-run) (string-append (make-run) "\n" (install-step))))
         (list (list (string-append "        run: " make-line) (out-of-order "main" make-line build-run))))
    (row "main's install check moved before Check the Chez"
         (list (e (string-append (install-step) "\n") "")
               (e (string-append (chk-step-text) "\n" (vers-step))
                  (string-append (install-step) "\n" (chk-step-text) "\n" (vers-step))))
         (list (list (list 'in "main" #f "        run: make build") (out-of-order "main" build-run chk-t))))
    (row "an if on main's install check"
         (list (e (string-append install-hdr "\n") (string-append install-hdr "\n        if: always()\n")))
         (list (list "        if: always()" if-bad)
               (list "        if: always()" if-wrong)
               (list "        if: always()" (step-has-if "main" build-run))))
    (row "main's install check with an argument, make build X"
         (list (le "main" "        run: make build\n" "        run: make build X\n"))
         (list (list "  main:" (n-steps "main" build-run 0))))
    (row "main's install check as a block scalar"
         (list (le "main" "        run: make build\n" "        run: |\n          make build\n"))
         (list (list "  main:" (n-steps "main" build-run 0))))
    (row "an env key CC on main's install check"
         (list (insert-after (string-append install-hdr "\n        env:\n          CHEZ: " chez-t "\n")
                             "          CC: gcc\n"))
         (list (list "          CC: gcc" (names-msg "CC"))
               (list "          CC: gcc" (env-key "CC"))))
    (row "memory's check-chez step deleted"
         (list (let ((hdr "      # The gate proves nothing unless it can fail, so the planted defects run\n"))
                 (e (span-after "  memory:\n" "      - name: Check the Chez this job runs\n" hdr) hdr)))
         (list (list "  memory:" (n-steps "memory" chk-t 0))))
    (row "nothreads's check-chez without --nothreads"
         (list (e (string-append "run: " chk-n "\n")
                  (string-append "run: " "scripts/ci/check-chez.sh \"$RUNNER_TEMP/chez-nothreads\"" "\n")))
         (list (list "  nothreads:" (n-steps "nothreads" chk-n 0))))
    (row "nothreads's check-nothreads step deleted"
         (list (e (span "      # No submodules, no deps" "run: make check-nothreads\n") ""))
         (list (list "  nothreads:" (n-steps "nothreads" "make check-nothreads" 0)))))

   ;; --- main's report steps (finding 7) ---
   (list
    (row "the versions step deleted"
         (list (e (string-append (vers-step) "\n") ""))
         (list (list "  main:" (named-n vers-name 0))))
    (row "the SQLite step deleted"
         (list (e (string-append (sql-step) "\n") ""))
         (list (list "  main:" (named-n sql-name 0))))
    (row "both report steps deleted"
         (list (e (string-append (vers-step) "\n") "")
               (e (string-append (sql-step) "\n") ""))
         (list (list "  main:" (named-n vers-name 0))
               (list "  main:" (named-n sql-name 0))))
    (row "the versions step renamed"
         (list (e vers-hdr "      - name: Report the version this run uses"))
         (list (list "  main:" (named-n vers-name 0))))
    (row "the SQLite step renamed"
         (list (e sql-hdr "      - name: Report the SQLite"))
         (list (list "  main:" (named-n sql-name 0))))
    (row "the versions step written twice"
         (list (e (string-append (vers-step) "\n") (string-append (vers-step) "\n" (vers-step) "\n")))
         (list (list "  main:" (named-n vers-name 2))))
    (row "the two report steps swapped"
         (list (e (string-append (vers-step) "\n" (sql-step))
                  (string-append (sql-step) "\n" (vers-step))))
         (list (list sql-hdr swapped-msg)))
    (row "the versions step moved after Checks and suites"
         (list (e (string-append (vers-step) "\n") "")
               (e (make-run) (string-append (make-run) "\n" (vers-step))))
         (list (list vers-hdr (runs-after vers-name make-line))
               (list sql-hdr swapped-msg)))
    (row "the SQLite step moved after Checks and suites"
         (list (e (string-append (sql-step) "\n") "")
               (e (make-run) (string-append (make-run) "\n" (sql-step))))
         (list (list sql-hdr (runs-after sql-name make-line))))
    (row "the versions step moved before Check the Chez"
         (list (e (string-append (chk-step-text) "\n" (vers-step))
                  (string-append (vers-step) "\n" (chk-step-text))))
         (list (list vers-hdr (runs-before vers-name chk-t))))
    (row "the SQLite step moved before Check the Chez"
         (list (e (string-append (sql-step) "\n") "")
               (e (string-append (chk-step-text) "\n" (vers-step))
                  (string-append (sql-step) "\n" (chk-step-text) "\n" (vers-step))))
         (list (list sql-hdr (runs-before sql-name chk-t))
               (list sql-hdr swapped-msg)))
    (row "a line at the start of the versions block"
         (list (e (string-append vers-l1 "\n") (string-append "          echo x\n" vers-l1 "\n")))
         (list (list "          echo x" (vers-differs vers-l1 "          echo x"))))
    (row "a line in the middle of the versions block"
         (list (e (string-append vers-l2 "\n") (string-append vers-l2 "\n          echo x\n")))
         (list (list "          echo x" (vers-differs vers-l3 "          echo x"))))
    (row "a line at the end of the versions block"
         (list (e (string-append vers-l5 "\n") (string-append vers-l5 "\n          echo x\n")))
         (list (list "          echo x" (vers-extra "          echo x"))))
    (row "a comment at the end of the versions block"
         (list (e (string-append vers-l5 "\n") (string-append vers-l5 "\n          # x\n")))
         (list (list "          # x" (vers-extra "          # x"))))
    (row "a line removed from the middle of the versions block"
         (list (e (string-append vers-l3 "\n") ""))
         (list (list vers-l4 (vers-differs vers-l3 vers-l4))))
    (row "the last line removed from the versions block"
         (list (e (string-append vers-l5 "\n") ""))
         (list (list vers-l4 (vers-early vers-l5))))
    (row "a line of the versions block changed"
         (list (e vers-l2 "          cc --version | head -n 2"))
         (list (list "          cc --version | head -n 2"
                     (vers-differs vers-l2 "          cc --version | head -n 2"))))
    (row "a line of the versions block re-indented"
         (list (e vers-l3 "            valgrind --version"))
         (list (list "            valgrind --version" (vers-differs vers-l3 "            valgrind --version"))))
    (row "the versions block clipped, run: |-"
         (list (e (span (string-append vers-hdr "\n") "run: |\n")
                  (string-append vers-hdr "\n        run: |-\n")))
         (list (list "        run: |-" not-block-msg)))
    (row "the SQLite step's run line changed"
         (list (e (string-append "run: " sql-run "\n") (string-append "run: " sql-run " --x\n")))
         (list (list (string-append "        run: " sql-run " --x") sql-run-msg)))
    (row "the SQLite step's env dropped"
         (list (e (string-append sql-hdr "\n        env:\n          CHEZ: " chez-t "\n")
                  (string-append sql-hdr "\n")))
         (list (list sql-hdr sql-env-msg))))

   ;; --- cache keys ---
   (map (lambda (part)
          (row (string-append "nothreads's cache key drops " part)
               (list (e nt-restore-key
                        (replace-first nt-restore-key part "")))
               (list (list (replace-first nt-restore-key part "")
                           (cache-key "nothreads" "chez-nothreads-")))))
        hash-parts)

   (list
    (row "nothreads's cache key takes threads's prefix"
         (list (e "key: chez-nothreads-${{" "key: chez-threads-${{"))
         (list (list (list 'in "nothreads" "      - name: Restore Chez without threads"
                           (replace-first nt-restore-key "chez-nothreads-" "chez-threads-"))
                     (cache-key "nothreads" "chez-nothreads-"))))
    (row "nothreads's cache key has a tail that is no suffix"
         (list (e nt-restore-key (replace-first nt-restore-key "}}-${{" "}}x${{")))
         (list (list (replace-first nt-restore-key "}}-${{" "}}x${{")
                     (cache-key "nothreads" "chez-nothreads-"))))
    (row "a cache key that is no expression at all"
         (list (e nt-restore-key "          key: static"))
         (list (list "          key: static" (cache-key "nothreads" "chez-nothreads-"))))
    (row "nothreads's cache key hashes one file more"
         (list (e nt-restore-key
                  (replace-first nt-restore-key "check-chez.sh')" "check-chez.sh', 'README.org')")))
         (list (list (replace-first nt-restore-key "check-chez.sh')" "check-chez.sh', 'README.org')")
                     (cache-key "nothreads" "chez-nothreads-"))))
    (row "main's cache key drops a file"
         (list (let ((old (span-after "  main:\n" "          key: chez-threads-${{"
                                      "      - name: Report the versions this run uses\n")))
                 (e old (replace-first old ", 'scripts/ci/check-chez.sh'" ""))))
         (list (list (string-append "          key: chez-threads-${{ hashFiles('packaging/floors.sexp', 'scripts/ci/floor.sh', 'scripts/ci/build-chez.sh') }}-${{ steps.image.outputs.id }}")
                     (cache-key "main" "chez-threads-"))))
    (row "memory's cache key takes nothreads's prefix"
         (list (let ((old (span-after "  memory:\n" "          key: chez-threads-${{"
                                      "      # The gate proves nothing unless it can fail")))
                 (e old (replace-first old "chez-threads-" "chez-nothreads-"))))
         (list (list (list 'in "memory" "      - name: Restore Chez" nt-restore-key)
                     (cache-key "memory" "chez-threads-")))))

   ;; --- the lanes: floor and current ---
   lane-global-rows
   (lane-rows "floor")
   (lane-rows "current")

   ;; --- the directory and the arguments ---
   (list
    (row/setup "a second workflow in the directory" (add-file "other.yml") '()
               (list (list 'dir "other.yml is not ci.yml: the directory must hold ci.yml alone")))
    (row/setup "a hidden file in the directory" (add-file ".hidden") '()
               (list (list 'dir ".hidden is not ci.yml: the directory must hold ci.yml alone")))
    (row/setup "a subdirectory in the directory"
               (lambda (dir) (mkdir (string-append dir "/sub"))) '()
               (list (list 'dir "sub is not ci.yml: the directory must hold ci.yml alone")))
    (row/setup "ci.yml is a link"
               (lambda (dir)
                 (let ((r (capture-command
                           (list "sh" "-c"
                                 (string-append "cd \"$1\" && mv ci.yml real.yml.tmp && ln -s real.yml.tmp ci.yml")
                                 "sh" dir))))
                   (unless (= (car r) 0) (error 'setup "the link was not made" r))))
               '()
               (list (list 'file "is not a regular file: a link, a directory or nothing there")
                     (list 'dir "real.yml.tmp is not ci.yml: the directory must hold ci.yml alone"))))))

;; --- the run ------------------------------------------------------------------------

(test-begin "check-ci")

(test-assert "the real workflow is there to be copied" (> (string-length real) 1000))

(let loop ((rs rows))
  (unless (null? rs)
    (let ((result (run-row (car rs))))
      (test-equal (caar rs) (car result) (cadr result)))
    (loop (cdr rs))))

;; Rows that need no copy of the workflow.

;; run-bare : (Listof String) -> (U (List Integer String String) (List 'raised String))
(define (run-bare args)
  (guard (c (#t (list 'raised (describe c))))
    (capture-command (append (list "sh" script) args))))

(define usage-line "check-ci: usage: sh tests/check-ci.sh DIR\n")

(test-equal "no argument is a usage error" (list 2 "" usage-line) (run-bare '()))
(test-equal "two arguments are a usage error" (list 2 "" usage-line) (run-bare '("a" "b")))

(let ((missing (string-append base "/nowhere")))
  (test-equal "a directory that is not there"
              (list 1 "" (string-append "check-ci: " missing ": is not a directory\n"
                                        "check-ci: FAILED (problems: 1)\n"))
              (run-bare (list missing))))

(let ((empty (string-append base "/empty")))
  (guard (c (#t #f)) (mkdir empty))
  (test-equal "a directory with no ci.yml"
              (list 1 ""
                    (string-append "check-ci: " empty "/ci.yml: is not a regular file: a link, a directory or nothing there\n"
                                   "check-ci: FAILED (problems: 1)\n"))
              (run-bare (list empty))))

(test-end "check-ci")

(exit (suite-exit-status runner))
