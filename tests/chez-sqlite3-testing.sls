#!r6rs
;;; (chez-sqlite3-testing): what every suite shares (ADR-0007).
;;;
;;;   suite-exit-form    the last datum of every tests/test-*.sps
;;;   suite-exit-status  the verdict that form exits with: the runner's
;;;                      counts, and (chez-sqlite3 private counters)' native
;;;                      counts
;;;   capture-command    run a command; its exit status, stdout and stderr
;;;   call-with-temp-directory
;;;                      a fresh mktemp -d directory, removed after a call
;;;   make-process-temp-directory
;;;                      one removed when the process ends
;;;   remove-temp-directory
;;;                      a directory and all it holds, removed
;;;   run-until          step until a predicate holds, capped by steps
;;;   describe           a raised object as text, for evidence
;;;
;;; Each helper comes with its first consumer. chez-curl's (curl-testing) has
;;; more (a Node origin, a wire probe, TLS material and seeded bytes); each
;;; joins this library with the suite that first needs it.
;;;
;;; Test-only: it lives in tests/, which make test puts on Chez's library
;;; path, not in src/. Its own suite is tests/test-chez-sqlite3-testing.sps.
(library (chez-sqlite3-testing)
  (export suite-exit-form suite-exit-status
          capture-command call-with-temp-directory make-process-temp-directory
          remove-temp-directory run-until describe)
  (import (rnrs)
          (srfi :64)
          (chez-sqlite3 private counters)
          (only (chezscheme) base-exception-handler critical-section
                delete-directory display-condition exit-handler file-directory?
                get-process-id getenv make-mutex mkdir system with-mutex)
          ;; Chez's file-exists? takes a second argument, #f not to follow a
          ;; symbolic link; (rnrs)'s takes one.
          (prefix (only (chezscheme) file-exists?) chez:))

  ;; --- the shared exit form ------------------------------------------------

  ;; suite-exit-form : Sexp
  ;; The last datum of every tests/test-*.sps, exactly: make check-suites
  ;; reads each suite as data and compares its last datum with this one.
  ;; `runner` is the suite's own binding for the runner it makes current. A
  ;; suite that never makes it current leaves it with no test, and fails.
  (define suite-exit-form '(exit (suite-exit-status runner)))

  ;; suite-exit-status : Test-Runner -> (U 0 1)
  ;; 0 when RUNNER saw a pass, and no failure and no unexpected pass, and every
  ;; count of (chez-sqlite3 private counters) is zero. Otherwise 1, after a
  ;; line on the error port for each rule broken: the runner's counts, then
  ;; each native count that is not zero, in native-kinds order (ADR-0005: a
  ;; native object a suite made and never freed is a leak, which Valgrind sees
  ;; as still reachable when a Chez object held its address). Expected failures
  ;; and skips count neither way. SRFI-64 sets no exit status of its own. The
  ;; answer is 0 or 1, never a count: exit statuses wrap at 256, so 256
  ;; failures would exit 0.
  (define (suite-exit-status runner)
    (unless (test-runner? runner)
      (assertion-violation 'suite-exit-status "not a SRFI-64 test runner" runner))
    (let* ((pass (test-runner-pass-count runner))
           (fail (test-runner-fail-count runner))
           (xpass (test-runner-xpass-count runner))
           (runner-ok? (and (> pass 0) (= fail 0) (= xpass 0)))
           (left (filter (lambda (entry) (not (eqv? (cdr entry) 0))) (native-counts))))
      (if (and runner-ok? (null? left))
          0
          (let ((err (current-error-port)))
            ;; The runner's own summary, on stdout, comes first.
            (flush-output-port (current-output-port))
            (unless runner-ok?
              (put-string err
                (string-append "suite-exit-status: exit 1 (pass " (number->string pass)
                               ", fail " (number->string fail)
                               ", xpass " (number->string xpass)
                               "): a suite needs a pass, and no fail or xpass\n")))
            (unless (null? left)
              (put-string err
                (string-append "suite-exit-status: exit 1 (native objects left: "
                               (join-words*
                                (map (lambda (entry)
                                       (string-append (symbol->string (car entry)) " "
                                                      (number->string (cdr entry))))
                                     left))
                               "): every native object a suite makes must be freed by its end\n")))
            (flush-output-port err)
            1))))

  ;; join-words* : (Listof String) -> String
  ;; WORDS joined with ", ", or "none" for no words.
  (define (join-words* words)
    (if (null? words)
        "none"
        (fold-left (lambda (line word) (string-append line ", " word)) (car words) (cdr words))))

  ;; --- capture-command -----------------------------------------------------

  ;; capture-command : (Listof String) -> (List Integer String String)
  ;; Runs ARGV, a command's name and then its arguments, through /bin/sh.
  ;; Each one is quoted, so it arrives as one word, unchanged. stdin is
  ;; /dev/null. The answer is the exit status as Chez's `system` reports it
  ;; (minus the signal number, when a signal killed the command), then all
  ;; the command wrote to stdout and to stderr, as UTF-8. A non-zero exit is
  ;; an answer, not a raise, so a test compares the whole list with what it
  ;; expects.
  ;;
  ;; A NUL is refused: `system` takes a C string, which would end there and run
  ;; whatever came before it. The two streams go through two files in a
  ;; directory of the call's own (make-capture-directory), removed after,
  ;; however the call ends. Any thread may call it, and calls on several at once
  ;; share no file; but on macOS they run one after the other, since its
  ;; system(3) waits for any other thread's (measured): a check that needs two
  ;; commands at once starts the long one through open-process-ports. `system`
  ;; lets other threads collect while the command runs, except inside a critical
  ;; section, where it holds them all until the command ends (Chez 10.4.0's
  ;; c/prim5.c; measured).
  (define (capture-command argv)
    (check-command argv)
    (let ((dir #f))
      (dynamic-wind
        (lambda () #f)
        (lambda ()
          ;; Made and recorded in one critical section, so that no escape
          ;; leaves a directory the after thunk cannot see.
          (critical-section (set! dir (make-capture-directory)))
          (let* ((out (string-append dir "/out"))
                 (err (string-append dir "/err"))
                 (status (system (string-append (join-words (map shell-quote argv))
                                                " </dev/null >" (shell-quote out)
                                                " 2>" (shell-quote err)))))
            (let* ((stdout (file->string out))
                   (stderr (file->string err)))
              (list status stdout stderr))))
        (lambda ()
          (when dir
            (for-each (lambda (name)
                        (guard (e (#t #f)) (remove-files (string-append dir "/" name))))
                      '("out" "err"))
            (delete-directory dir))))))

  ;; make-capture-directory : -> String
  ;; A fresh directory for one capture's files: the scratch directory, then
  ;; chez-sqlite3-testing-PID-N, N counted for this process under a mutex. Chez's
  ;; mkdir makes it with mode 700, and refuses a name that anything already
  ;; holds, a dangling symbolic link included (measured at 10.4.0). So no
  ;; two captures share a file, in this process or any other, and none
  ;; writes through a name someone else planted. A name that is taken costs
  ;; the next N, up to 100 tries; any other failure raises, before the
  ;; command runs. The mutex keeps this process's numbers distinct, so a
  ;; name is taken only by another process or what one left behind.
  (define (make-capture-directory)
    (let ((base (string-append (scratch-root) "/chez-sqlite3-testing-"
                               (number->string (get-process-id)) "-")))
      (let try ((tries 1))
        (let ((dir (string-append base (number->string (next-capture)))))
          (cond
            ((guard (e (#t #f)) (mkdir dir #o700) #t) dir)
            ((and (< tries 100) (chez:file-exists? dir #f)) (try (+ tries 1)))
            (else (error 'capture-command "could not make a directory for the command's output"
                         dir)))))))

  ;; next-capture : -> Positive-Integer
  ;; How many captures this process has begun, this one included. The
  ;; mutex is held through critical-section around with-mutex, which takes
  ;; its mutex before its own dynamic-wind, so no escape can leave it held.
  (define (next-capture)
    (critical-section
     (with-mutex capture-mutex
       (set! captures (+ captures 1))
       captures)))

  (define capture-mutex (make-mutex))
  (define captures 0)

  (define (check-command argv)
    (unless (and (pair? argv) (list? argv))
      (assertion-violation 'capture-command "a command is a non-empty list of strings" argv))
    (for-each
     (lambda (arg)
       (unless (string? arg)
         (assertion-violation 'capture-command "an argument is not a string" arg))
       (when (memv #\nul (string->list arg))
         (assertion-violation 'capture-command
                              "an argument holds a NUL, which would end the command there"
                              arg)))
     argv))

  (define (scratch-directory)
    (let ((dir (getenv "TMPDIR")))
      (if (and dir (not (string=? dir ""))) dir "/tmp")))

  ;; shell-quote : String -> String
  ;; S as one POSIX shell word: in single quotes, each ' written as '\''.
  (define (shell-quote s)
    (call-with-string-output-port
     (lambda (p)
       (put-char p #\')
       (string-for-each (lambda (c)
                          (if (char=? c #\')
                              (put-string p "'\\''")
                              (put-char p c)))
                        s)
       (put-char p #\'))))

  (define (join-words words)
    (fold-left (lambda (line word) (string-append line " " word))
               (car words) (cdr words)))

  ;; A capture file the shell did not create is a raise, never an empty
  ;; answer, since it means the command did not run as asked.
  (define (file->string path)
    (unless (file-exists? path)
      (error 'capture-command "the shell did not create a capture file" path))
    (let* ((port (open-file-input-port path))
           (bytes (get-bytevector-all port)))
      (close-port port)
      (if (eof-object? bytes) "" (utf8->string bytes))))

  (define (remove-files . paths)
    (for-each (lambda (path) (when (file-exists? path) (delete-file path))) paths))

  ;; --- temporary directories -----------------------------------------------

  ;; call-with-temp-directory : (String -> Any) -> Any
  ;; Makes a fresh directory with `mktemp -d`, under $TMPDIR or /tmp, and
  ;; answers (PROC DIR), DIR being its absolute path. Afterwards the directory
  ;; and all it holds are removed, whether PROC returns, raises or escapes.
  ;; It raises before PROC runs when mktemp's answer is refused, below.
  (define (call-with-temp-directory proc)
    (let ((dir (make-temp-directory)))
      (dynamic-wind
        (lambda () #f)
        (lambda () (proc dir))
        (lambda () (remove-temp-directory dir)))))

  ;; make-process-temp-directory : -> String
  ;; A fresh directory, as call-with-temp-directory makes, for a suite whose
  ;; body is flat top-level forms and cannot be wrapped. It is removed when
  ;; the process ends: through `exit`, or through a raise that nothing
  ;; guards, which ends a program with status 255 without calling the exit
  ;; handler. A program that falls off its last form calls neither (measured
  ;; at 10.4.0), so a suite ends with (exit ...), as check-suites requires.
  ;; A warning, which Chez raises to the same handler and goes on from, does
  ;; not remove it. remove-temp-directory removes it earlier, and the hooks
  ;; then find nothing to do. A removal that fails in a hook is ignored
  ;; there: it must not stop an exit, nor raise from the handler it runs in.
  (define (make-process-temp-directory)
    (let ((dir (make-temp-directory)))
      (exit-handler
       (let ((previous (exit-handler)))
         (lambda args
           (remove-quietly dir)
           (apply previous args))))
      (base-exception-handler
       (let ((previous (base-exception-handler)))
         (lambda (condition)
           (unless (warning? condition)
             (remove-quietly dir))
           (previous condition))))
      dir))

  (define (remove-quietly dir)
    (guard (e (#t #f)) (remove-temp-directory dir)))

  ;; remove-temp-directory : String -> Unit
  ;; Removes the directory DIR and all it holds; DIR may be gone already.
  ;; Only an absolute path other than / is removed. It raises when the
  ;; directory is still there afterwards.
  (define (remove-temp-directory dir)
    (unless (absolute-path? dir)
      (assertion-violation 'remove-temp-directory "not an absolute path" dir))
    (when (string=? dir "/")
      (assertion-violation 'remove-temp-directory "not the root directory" dir))
    (when (file-exists? dir)
      (capture-command (list "rm" "-rf" dir))
      (when (file-exists? dir)
        (error 'remove-temp-directory "could not remove the directory" dir))))

  ;; make-temp-directory : -> String
  ;; A fresh directory from `mktemp -d`, given a template under $TMPDIR, or
  ;; /tmp: a bare `mktemp -d` honours TMPDIR on Linux and ignores it on
  ;; macOS, while both read a template alike. mktemp prints the path and a
  ;; newline. The path is that line, whole: $TMPDIR may hold a space, and a
  ;; path cut at whitespace names another directory, which a removal would
  ;; then destroy. So the answer must be exactly one line, an absolute path
  ;; to a directory that exists. Any other answer (a relative path, a second
  ;; line, a missing directory, a failure) is refused with a raise, and
  ;; nothing is removed.
  (define (make-temp-directory)
    (let* ((made (capture-command (list "mktemp" "-d" (temp-template))))
           (dir (single-line (cadr made))))
      (if (and (= (car made) 0) dir (absolute-path? dir) (file-directory? dir))
          dir
          (error 'make-temp-directory
                 "mktemp -d did not answer one absolute path to a directory" made))))

  ;; temp-template : -> String
  ;; mktemp's template: the scratch directory, without the slash macOS's
  ;; TMPDIR ends with, then chez-sqlite3-testing.XXXXXX.
  (define (temp-template)
    (string-append (scratch-root) "/chez-sqlite3-testing.XXXXXX"))

  ;; scratch-root : -> String
  ;; The scratch directory without the slashes it may end with, as macOS's
  ;; TMPDIR does: a name is appended to it after one slash.
  (define (scratch-root)
    (let loop ((dir (scratch-directory)))
      (let ((n (string-length dir)))
        (if (and (> n 0) (char=? (string-ref dir (- n 1)) #\/))
            (loop (substring dir 0 (- n 1)))
            dir))))

  ;; single-line : String -> (U String #f)
  ;; TEXT without its one final newline, when that leaves a line: not empty,
  ;; and with no newline in it.
  (define (single-line text)
    (let ((n (string-length text)))
      (and (> n 1)
           (char=? (string-ref text (- n 1)) #\newline)
           (let ((line (substring text 0 (- n 1))))
             (and (not (memv #\newline (string->list line))) line)))))

  (define (absolute-path? s)
    (and (> (string-length s) 0) (char=? (string-ref s 0) #\/)))

  ;; --- run-until -----------------------------------------------------------

  ;; run-until : (-> Any) (-> Any) Positive-Integer
  ;;             -> (U 'satisfied 'iterations-exhausted)
  ;; Calls STEP until DONE? answers true, or until STEP has run MAX-STEPS
  ;; times. DONE? is asked first, so a condition that already holds costs no
  ;; step, and again after every step, the last included. The answer is a
  ;; symbol, never a boolean, so it cannot be taken for the #f that SRFI-64
  ;; makes of a raise. The cap counts steps, not time, so a slow machine
  ;; does not make a suite flaky.
  (define (run-until step done? max-steps)
    (unless (procedure? step)
      (assertion-violation 'run-until "the step is not a procedure" step))
    (unless (procedure? done?)
      (assertion-violation 'run-until "the predicate is not a procedure" done?))
    (unless (and (integer? max-steps) (exact? max-steps) (positive? max-steps))
      (assertion-violation 'run-until "the cap is not a positive exact integer" max-steps))
    (let loop ((taken 0))
      (cond ((done?) 'satisfied)
            ((>= taken max-steps) 'iterations-exhausted)
            (else (step) (loop (+ taken 1))))))


  ;; --- describe ------------------------------------------------------------

  ;; describe : Any -> String
  ;; OBJ as text: a condition as Chez displays it, anything else as written.
  ;; A raise while printing gives a fixed string instead, so evidence never
  ;; raises.
  (define (describe obj)
    (guard (e (#t "<the raised object could not be printed>"))
      (call-with-string-output-port
       (lambda (p)
         (if (condition? obj) (display-condition obj p) (write obj p)))))))
