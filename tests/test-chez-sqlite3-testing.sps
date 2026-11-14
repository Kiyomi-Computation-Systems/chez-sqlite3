#!r6rs
;;; The suite for (chez-sqlite3-testing): suite-exit-form, suite-exit-status
;;; with the exit checks it runs, capture-command, the temporary directories
;;; (call-with-temp-directory, make-process-temp-directory,
;;; remove-temp-directory), run-until, gated-command and describe.
;;;
;;; Each expected value is one the code under test cannot produce by failing.
;;; SRFI-64 turns a raise in the actual expression into #f, so no expected
;;; value here is #f, and a refusal is compared, who and irritants, against a
;;; no-raise sentinel.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) parameterize record-writer getenv putenv directory-list
              file-directory? make-time sleep fork-thread make-mutex with-mutex
              real-time iota get-process-id mkdir)
        ;; Chez's own current-error-port is a parameter; (rnrs)'s takes no
        ;; argument, and reads the same port.
        (prefix (only (chezscheme) current-error-port) chez:)
        (chez-sqlite3 private counters)
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

;; raised : (-> Any) -> Any
;; What THUNK raised: (assertion-violation WHO IRRITANTS) for an assertion
;; violation, (other-raise MESSAGE) for any other condition with a message,
;; (other-raise OBJECT) for anything else, and the symbol no-raise if THUNK
;; returned.
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e)
                  (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            ((message-condition? e) (list 'other-raise (condition-message e)))
            (#t (list 'other-raise e)))
    (thunk)
    'no-raise))

(test-begin "chez-sqlite3-testing")

;; --- suite-exit-form ------------------------------------------------------

(test-equal "suite-exit-form is exactly the datum (exit (suite-exit-status runner))"
  ;; Built, not quoted: make check-suites refuses a quoted exit form.
  (list (string->symbol "exit") (list 'suite-exit-status 'runner))
  suite-exit-form)

;; --- suite-exit-status: the verdict behind the shared exit form -----------
;; Each runner below is a fresh null runner, which prints nothing and which
;; this suite's own runner never sees. Each base holds the outcomes the rule
;; under test must ignore, so that only that rule can produce the expected
;; verdict.

;; runner-after : (-> Any) -> Test-Runner
(define (runner-after thunk)
  (let ((r (test-runner-null)))
    (test-with-runner r
      (test-begin "inner")
      (thunk)
      (test-end "inner"))
    r))

;; verdict : Test-Runner -> (List Integer String)
;; suite-exit-status's answer, then everything it wrote to the error port.
(define (verdict r)
  (let-values (((port contents) (open-string-output-port)))
    (let ((status (parameterize ((chez:current-error-port port))
                    (suite-exit-status r))))
      (list status (contents)))))

(define runner-tail "): a suite needs a pass, and no fail or xpass\n")

(test-equal "a pass beside an expected failure and a skip: exit 0, and nothing said"
  '(0 "")
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-expect-fail 1)
                           (test-assert "fails, as expected" #f)
                           (test-skip 1)
                           (test-assert "skipped" #t)))))

(test-equal "two failures beside a pass: exit 1, not a count, since exit statuses wrap at 256"
  (list 1 (string-append "suite-exit-status: exit 1 (pass 1, fail 2, xpass 0" runner-tail))
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-assert "fails" #f)
                           (test-assert "fails too" #f)))))

(test-equal "256 failures beside a pass: exit 1, since a count of 256 would wrap to 0"
  (list 1 (string-append "suite-exit-status: exit 1 (pass 1, fail 256, xpass 0" runner-tail))
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (do ((i 0 (+ i 1))) ((= i 256))
                             (test-assert "fails" #f))))))

(test-equal "an unexpected pass beside a pass: exit 1"
  (list 1 (string-append "suite-exit-status: exit 1 (pass 1, fail 0, xpass 1" runner-tail))
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-expect-fail 1)
                           (test-assert "passes unexpectedly" #t)))))

(test-equal "an expected failure and a skip, but no pass: exit 1"
  (list 1 (string-append "suite-exit-status: exit 1 (pass 0, fail 0, xpass 0" runner-tail))
  (verdict (runner-after (lambda ()
                           (test-expect-fail 1)
                           (test-assert "fails, as expected" #f)
                           (test-skip 1)
                           (test-assert "skipped" #t)))))

(test-equal "no test at all: exit 1"
  (list 1 (string-append "suite-exit-status: exit 1 (pass 0, fail 0, xpass 0" runner-tail))
  (verdict (runner-after (lambda () 'no-tests))))

(test-equal "suite-exit-status refuses what is not a runner"
  '(assertion-violation suite-exit-status ("not a runner"))
  (raised (lambda () (suite-exit-status "not a runner"))))

;; --- the counters' rule (ADR-0005) ----------------------------------------
;; Each raises counts on purpose, and lowers them again under dynamic-wind,
;; so this suite's own exit, which reads the same counts, sees zero.

;; with-counts : (Listof Symbol) (-> Any) -> Any
;; THUNK's answer, with one more of each kind in KINDS counted while it runs.
(define (with-counts kinds thunk)
  (dynamic-wind
    (lambda () (for-each count-up! kinds))
    thunk
    (lambda () (for-each count-down! kinds))))

(define counts-tail "): every native object a suite makes must be freed by its end\n")

(define (passing-verdict)
  (verdict (runner-after (lambda () (test-assert "passes" #t)))))

(test-equal "a pass, and native objects left: exit 1, one line naming each count not zero, in the counters' order"
  (list 1 (string-append "suite-exit-status: exit 1 (native objects left: block 1, statement 2"
                         counts-tail))
  (with-counts '(statement block statement) passing-verdict))

;; Each kind alone fails a suite that passed: a gate that read some kinds
;; only passes a test of two. Written out here, not read from native-kinds.
(for-each
 (lambda (kind)
   (test-equal (string-append "a pass, and one " (symbol->string kind)
                              " left alone: exit 1, the line naming it")
     (list 1 (string-append "suite-exit-status: exit 1 (native objects left: "
                            (symbol->string kind) " 1" counts-tail))
     (with-counts (list kind) passing-verdict)))
 '(block connection statement))

(test-equal "every kind left is named, each with its count"
  (list 1 (string-append "suite-exit-status: exit 1 (native objects left: block 1, connection 3, statement 1"
                         counts-tail))
  (with-counts '(connection statement block connection connection) passing-verdict))

(test-equal "a failure, and a native object left: both lines, the runner's first"
  (list 1 (string-append
           "suite-exit-status: exit 1 (pass 1, fail 1, xpass 0" runner-tail
           "suite-exit-status: exit 1 (native objects left: connection 1" counts-tail))
  (with-counts '(connection)
    (lambda () (verdict (runner-after (lambda ()
                                        (test-assert "passes" #t)
                                        (test-assert "fails" #f)))))))

(test-equal "the counts are back at zero once with-counts returns: a pass exits 0, and nothing is said"
  (list '((block . 0) (connection . 0) (statement . 0))
        '(0 ""))
  (list (native-counts) (passing-verdict)))

;; --- capture-command ------------------------------------------------------

(test-equal "capture-command: the exit status, stdout and stderr, kept apart"
  '(3 "out\n" "err\n")
  (capture-command '("sh" "-c" "echo out; echo err >&2; exit 3")))

(test-equal "capture-command: each argument arrives as one word, unchanged"
  '(0 "a b|$HOME|it's|\"q\"|back\\slash||*|;|two\nlines|" "")
  (capture-command
   (list "printf" "%s|"
         "a b" "$HOME" "it's" "\"q\"" "back\\slash" "" "*" ";" "two\nlines")))

(test-equal "capture-command: a NUL would cut the command short, so it is refused"
  (list 'assertion-violation 'capture-command (list (string #\a #\nul #\b)))
  (raised (lambda () (capture-command (list "printf" (string #\a #\nul #\b))))))

(test-equal "capture-command: every argument is a string"
  '(assertion-violation capture-command (5))
  (raised (lambda () (capture-command '("echo" 5)))))

(test-equal "capture-command: a command has at least its name"
  '(assertion-violation capture-command (()))
  (raised (lambda () (capture-command '()))))

;; --- temporary directories ------------------------------------------------
;; call-with-temp-directory, make-process-temp-directory and
;; remove-temp-directory. The dangerous mistake is a path cut at whitespace,
;; so that a removal destroys a neighbour: those rows keep a canary directory
;; beside the one that is made, and require it to survive.

(define chez (getenv "CHEZ"))

(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (and chez (not (string=? chez ""))) 'set 'unset))

;; absolute? : String -> Boolean
(define (absolute? s)
  (and (> (string-length s) 0) (char=? (string-ref s 0) #\/)))

;; prefix? : String String -> Boolean
(define (prefix? prefix s)
  (and (<= (string-length prefix) (string-length s))
       (string=? prefix (substring s 0 (string-length prefix)))))

;; call-with-env : String String (-> Any) -> Any
;; THUNK with the environment variable NAME set to VALUE. Afterwards NAME is
;; put back to its old value, or to /tmp when it was unset: putenv cannot
;; unset, and /tmp is where mktemp and capture-command go for an unset TMPDIR.
;; Only PATH and TMPDIR are set here.
(define (call-with-env name value thunk)
  (let ((old (getenv name)))
    (dynamic-wind
      (lambda () (putenv name value))
      thunk
      (lambda () (putenv name (or old "/tmp"))))))

;; write-file : String String -> Unit
(define (write-file path text)
  (call-with-port (open-file-output-port path (file-options no-fail) (buffer-mode block)
                                         (make-transcoder (utf-8-codec)))
    (lambda (p) (put-string p text))))

;; sorted-names : String -> (Listof String)
(define (sorted-names dir) (list-sort string<? (directory-list dir)))

;; --- capture-command from many threads ------------------------------------
;; Each capture writes its two files into a directory of its own, which
;; Chez's mkdir makes with mode 700 and refuses to make over a name that is
;; taken. These rows hold that, and what the directory costs: none left
;; behind, however the call ends, and a raise before the command runs when
;; none can be made.

;; captures-in-threads : Natural Natural
;;                       -> (List (Listof (List Natural (Listof Answer))) Natural)
;; THREADS threads, each running PER-THREAD captures at once with the
;; others, of a command that prints its token on stdout, sleeps 10 ms, and
;; prints it again on stderr. An Answer is (TOKEN RESULT), RESULT what
;; capture-command answered, or what it raised. The answers come by thread,
;; in order, and then how many pairs of captures from different threads ran
;; at the same time, by the clock: without some, nothing here ran at once.
;; Whatever a thread raises outside a capture is its answers, as
;; (raised-on-thread TEXT), and the wait for the threads is bounded, at
;; 120 s: a thread that died, or hangs, fails the check that called this,
;; by name, as (unanswered-within-120-s ANSWERS).
(define (captures-in-threads threads per-thread)
  (let ((mx (make-mutex)) (by-thread '()) (spans '()))
    (do ((t 0 (+ t 1))) ((= t threads))
      (let ((t t))
        (fork-thread
         (lambda ()
           (let ((r (guard (e (#t (list (list 'raised-on-thread (describe e)) '())))
                      (let loop ((i 0) (answers '()) (mine '()))
                        (if (= i per-thread)
                            (list (reverse answers) mine)
                            (let* ((token (string-append "t" (number->string t) "-" (number->string i)))
                                   (start (real-time))
                                   (result (guard (e (#t (list 'raised (describe e))))
                                             (capture-command
                                              (list "sh" "-c"
                                                    "printf %s \"$1\"; sleep 0.01; printf %s \"$1\" >&2"
                                                    "sh" token))))
                                   (end (real-time)))
                              (loop (+ i 1) (cons (list token result) answers)
                                    (cons (cons start end) mine))))))))
             (with-mutex mx
               (set! by-thread (cons (list t (car r)) by-thread))
               (set! spans (cons (cons t (cadr r)) spans))))))))
    (let* ((all (let ((deadline (+ (real-time) 120000)))
                  (let wait ()
                    (cond ((with-mutex mx (= (length by-thread) threads)) #t)
                          ((> (real-time) deadline) #f)
                          (else (sleep (make-time 'time-duration 1000000 0)) (wait))))))
           (answers (with-mutex mx (list-sort (lambda (a b) (< (car a) (car b))) by-thread))))
      (list (if all answers (list 'unanswered-within-120-s answers))
            (with-mutex mx (overlapping-pairs spans))))))

;; overlapping-pairs : (Listof (Pairof Natural (Listof (Pairof Ms Ms)))) -> Natural
;; How many pairs of spans, from different threads, overlap in time.
(define (overlapping-pairs spans)
  (define (overlap? a b) (and (< (car a) (cdr b)) (< (car b) (cdr a))))
  (define (across mine theirs)
    (fold-left (lambda (n a) (+ n (length (filter (lambda (b) (overlap? a b)) theirs))))
               0 mine))
  (let loop ((rest spans) (n 0))
    (if (null? rest)
        n
        (loop (cdr rest)
              (fold-left (lambda (n other) (+ n (across (cdr (car rest)) (cdr other))))
                         n (cdr rest))))))

(test-equal "capture-command: two threads capturing at once, 50 times each, each capture answers its own command's output, the calls overlapped in time, and nothing is left behind"
  (list (map (lambda (t)
               (list t (map (lambda (i)
                              (let ((token (string-append "t" (number->string t) "-" (number->string i))))
                                (list token (list 0 token token))))
                            (iota 50))))
             '(0 1))
        'overlapped
        '())
  (call-with-temp-directory
   (lambda (dir)
     (let ((ran (call-with-env "TMPDIR" dir (lambda () (captures-in-threads 2 50)))))
       (list (car ran)
             (if (> (cadr ran) 0) 'overlapped (list 'never-overlapped (cadr ran)))
             (directory-list dir))))))

;; capture-name : Natural -> String
;; The name of capture N's directory, below the scratch directory.
(define (capture-name n)
  (string-append "chez-sqlite3-testing-" (number->string (get-process-id)) "-" (number->string n)))

;; current-capture : String -> Natural
;; The N of the capture that lists DIR, with TMPDIR at DIR: the one capture
;; directory its command sees there is its own.
(define (current-capture dir)
  (let* ((answer (call-with-env "TMPDIR" dir (lambda () (capture-command (list "ls" dir)))))
         (line (cadr answer))
         (prefix (capture-name 0)))
    (string->number (substring line (- (string-length prefix) 1) (- (string-length line) 1)))))

(test-equal "capture-command: names taken by a directory and by a symbolic link to one are skipped, and nothing is written into either"
  '((0 "hi\n" "") () () same-names)
  (call-with-temp-directory
   (lambda (dir)
     (let* ((n (current-capture dir))
            (victim (string-append dir "/victim"))
            (planted (string-append dir "/" (capture-name (+ n 2))))
            (link (string-append dir "/" (capture-name (+ n 3)))))
       (mkdir victim)
       ;; This capture is n + 1, so the next tries n + 2, then n + 3.
       (call-with-env "TMPDIR" dir (lambda () (capture-command (list "ln" "-s" victim link))))
       (mkdir planted)
       (let ((answer (call-with-env "TMPDIR" dir (lambda () (capture-command '("echo" "hi"))))))
         (list answer (directory-list planted) (directory-list victim)
               (if (equal? (sorted-names dir)
                           (list-sort string<? (list "victim" (capture-name (+ n 2))
                                                     (capture-name (+ n 3)))))
                   'same-names
                   (sorted-names dir))))))))

(test-equal "capture-command: when the next 100 names are taken, it raises before the command runs"
  '((other-raise "could not make a directory for the command's output") absent)
  (call-with-temp-directory
   (lambda (dir)
     (let ((n (current-capture dir))
           (marker (string-append dir "/ran")))
       (for-each (lambda (i) (mkdir (string-append dir "/" (capture-name (+ n 1 i))))) (iota 100))
       (let ((answer (call-with-env "TMPDIR" dir
                                    (lambda () (raised (lambda () (capture-command (list "touch" marker))))))))
         (list answer (if (file-exists? marker) 'ran 'absent)))))))

(test-equal "capture-command: its directory is the only one in the scratch directory, with mode 700"
  (list 0 'only-one-dir-mode-700 "")
  (call-with-temp-directory
   (lambda (dir)
     (let* ((n (current-capture dir))
            (answer (call-with-env
                     "TMPDIR" dir
                     (lambda ()
                       (capture-command
                        (list "sh" "-c"
                              "for d in \"$1\"/*; do printf '%s %s\\n' \"$(ls -ld \"$d\" | cut -c1-10)\" \"${d##*/}\"; done"
                              "sh" dir))))))
       (list (car answer)
             (if (equal? (cadr answer)
                         (string-append "drwx------ " (capture-name (+ n 1)) "\n"))
                 'only-one-dir-mode-700
                 (cadr answer))
             (caddr answer))))))

(test-equal "capture-command: a raise after its directory is made still removes it"
  '((other-raise "the shell did not create a capture file") ())
  (call-with-temp-directory
   (lambda (dir)
     (let ((answer (call-with-env "TMPDIR" dir
                                  (lambda ()
                                    (raised (lambda ()
                                              (capture-command
                                               (list "sh" "-c" "rm \"$1\"/chez-sqlite3-testing-*/out" "sh" dir))))))))
       (list answer (directory-list dir))))))

(test-equal "capture-command: it leaves nothing behind in the scratch directory"
  '((0 "x\n" "") ())
  (call-with-temp-directory
   (lambda (dir)
     (let ((answer (call-with-env "TMPDIR" dir (lambda () (capture-command '("sh" "-c" "echo x"))))))
       (list answer (directory-list dir))))))

(test-equal "capture-command: with no scratch directory to write in, it raises before the command runs"
  '((other-raise "could not make a directory for the command's output") absent)
  (call-with-temp-directory
   (lambda (dir)
     (let* ((marker (string-append dir "/ran"))
            (answer (call-with-env "TMPDIR" (string-append dir "/missing")
                                   (lambda () (raised (lambda () (capture-command (list "touch" marker))))))))
       (list answer (if (file-exists? marker) 'ran 'absent))))))

(test-equal "call-with-temp-directory: PROC gets the path of an empty directory, and the directory is gone after"
  '((#t #t ()) removed)
  (let* ((made #f)
         (inside (call-with-temp-directory
                  (lambda (dir)
                    (set! made dir)
                    (list (absolute? dir) (file-directory? dir) (directory-list dir))))))
    (list inside (if (file-exists? made) 'left 'removed))))

(test-equal "call-with-temp-directory: its answer is PROC's, and what the directory held is removed too"
  '(answer ("g" "sub") removed)
  (let* ((made #f)
         (listing #f)
         (value (call-with-temp-directory
                 (lambda (dir)
                   (set! made dir)
                   (capture-command
                    (list "sh" "-c" "mkdir \"$1/sub\" && echo x > \"$1/sub/f\" && echo y > \"$1/g\""
                          "sh" dir))
                   (set! listing (sorted-names dir))
                   'answer))))
    (list value listing (if (file-exists? made) 'left 'removed))))

(test-equal "call-with-temp-directory: the directory is removed when PROC raises, and the raise goes on"
  '(boom removed)
  (let ((made #f))
    (guard (e (#t (list e (if (file-exists? made) 'left 'removed))))
      (call-with-temp-directory
       (lambda (dir) (set! made dir) (raise 'boom)))
      'no-raise)))

(test-equal "call-with-temp-directory: the directory is removed when PROC escapes"
  '(escaped removed)
  (let* ((made #f)
         (value (call/cc
                 (lambda (k)
                   (call-with-temp-directory
                    (lambda (dir) (set! made dir) (k 'escaped)))))))
    (list value (if (file-exists? made) 'left 'removed))))

(test-equal "call-with-temp-directory: TMPDIR holding a space is one path; the directory beside it survives"
  '(inside kept removed)
  (call-with-temp-directory
   (lambda (base)
     (let ((canary (string-append base "/can"))
           (spaced (string-append base "/can ary")))
       (capture-command (list "mkdir" canary spaced))
       (write-file (string-append canary "/keep") "keep\n")
       (let ((inside (call-with-env "TMPDIR" spaced
                       (lambda ()
                         (call-with-temp-directory
                          (lambda (dir)
                            (if (prefix? (string-append spaced "/") dir) 'inside 'elsewhere)))))))
         (list inside
               (if (file-exists? (string-append canary "/keep")) 'kept 'destroyed)
               (if (null? (directory-list spaced)) 'removed 'left)))))))

;; refusal : (-> Any) -> Any
;; THUNK's raise, or the symbol no-raise.
(define (refusal thunk) (raised thunk))

(define mktemp-refusal
  '(other-raise "mktemp -d did not answer one absolute path to a directory"))

(test-equal "call-with-temp-directory: a newline in TMPDIR makes two lines, which it refuses; the directory named by the first survives"
  (list mktemp-refusal 'kept 'never-called)
  (call-with-temp-directory
   (lambda (base)
     (let ((canary (string-append base "/can"))
           (newlined (string-append base "/can\nary"))
           (called 'never-called))
       (capture-command (list "mkdir" canary newlined))
       (write-file (string-append canary "/keep") "keep\n")
       (let ((answer (call-with-env "TMPDIR" newlined
                       (lambda ()
                         (refusal (lambda ()
                                    (call-with-temp-directory
                                     (lambda (dir) (set! called 'called)))))))))
         (list answer
               (if (file-exists? (string-append canary "/keep")) 'kept 'destroyed)
               called))))))

;; A mktemp on PATH ahead of the real one, answering what BODY (shell
;; commands) makes it. CANARY is a directory that exists, which BODY may name.
(define (with-fake-mktemp base body thunk)
  (let ((bin (string-append base "/bin")))
    (capture-command (list "mkdir" bin))
    (write-file (string-append bin "/mktemp") (string-append "#!/bin/sh\n" body "\n"))
    (capture-command (list "chmod" "+x" (string-append bin "/mktemp")))
    (call-with-env "PATH" (string-append bin ":" (getenv "PATH")) thunk)))

(for-each
 (lambda (row)
   (let ((name (car row)) (body (cadr row)))
     (test-equal (string-append "call-with-temp-directory refuses a mktemp that answers " name
                                ", and calls nothing, and removes nothing")
       (list mktemp-refusal 'kept 'never-called)
       (call-with-temp-directory
        (lambda (base)
          (let ((canary (string-append base "/can"))
                (called 'never-called))
            (capture-command (list "mkdir" canary))
            (write-file (string-append canary "/keep") "keep\n")
            (let ((answer (with-fake-mktemp base (string-append "CANARY='" canary "'\n" body)
                            (lambda ()
                              (refusal (lambda ()
                                         (call-with-temp-directory
                                          (lambda (dir) (set! called 'called)))))))))
              (list answer
                    (if (file-exists? (string-append canary "/keep")) 'kept 'destroyed)
                    called))))))))
 '(("a relative path to a directory that exists" "printf 'tests\\n'")
   ("a path that is not there" "printf '/no/such/directory/anywhere\\n'")
   ("an empty line"        "printf '\\n'")
   ("no newline"           "printf '%s' \"$CANARY\"")
   ("two lines, the first a directory" "printf '%s\\n%s\\n' \"$CANARY\" \"$CANARY/second\"")
   ("a directory and exit 1" "printf '%s\\n' \"$CANARY\"; exit 1")))

(test-equal "remove-temp-directory: it removes a directory and what is in it, and a path that is gone is no error"
  '(no-raise removed no-raise)
  (call-with-temp-directory
   (lambda (base)
     (let ((victim (string-append base "/victim")))
       (capture-command (list "mkdir" "-p" (string-append victim "/sub")))
       (let* ((first (refusal (lambda () (remove-temp-directory victim))))
              (gone (if (file-exists? victim) 'left 'removed))
              (second (refusal (lambda () (remove-temp-directory victim)))))
         (list first gone second))))))

;; with-fake-rm : String (-> Any) -> Any
;; THUNK with an rm ahead of the real one on PATH that removes nothing and
;; logs its arguments to BASE/rm-log. A refusal is shown to run no rm, and a
;; removal that should have been refused cannot reach a real directory.
(define (with-fake-rm base thunk)
  (let ((bin (string-append base "/bin")))
    (capture-command (list "mkdir" bin))
    (write-file (string-append bin "/rm")
                (string-append "#!/bin/sh\necho \"$@\" >> '" base "/rm-log'\nexit 0\n"))
    (capture-command (list "chmod" "+x" (string-append bin "/rm")))
    (call-with-env "PATH" (string-append bin ":" (getenv "PATH")) thunk)))

(test-equal "remove-temp-directory: only an absolute path other than /, and it runs no rm for any other"
  '((assertion-violation remove-temp-directory ("relative/dir"))
    (assertion-violation remove-temp-directory ("/"))
    (assertion-violation remove-temp-directory (""))
    never-run)
  (call-with-temp-directory
   (lambda (base)
     (with-fake-rm base
       (lambda ()
         (let* ((relative (refusal (lambda () (remove-temp-directory "relative/dir"))))
                (root (refusal (lambda () (remove-temp-directory "/"))))
                (empty (refusal (lambda () (remove-temp-directory ""))))
                (ran (if (file-exists? (string-append base "/rm-log")) 'run 'never-run)))
           (list relative root empty ran)))))))

(test-equal "remove-temp-directory: a directory still there after rm is a raise"
  (list (list 'other-raise "could not remove the directory") 'still-there)
  (call-with-temp-directory
   (lambda (base)
     (let ((bin (string-append base "/bin"))
           (victim (string-append base "/victim")))
       (capture-command (list "mkdir" bin victim))
       (write-file (string-append bin "/rm") "#!/bin/sh\nexit 0\n")
       (capture-command (list "chmod" "+x" (string-append bin "/rm")))
       (let ((answer (call-with-env "PATH" (string-append bin ":" (getenv "PATH"))
                       (lambda () (refusal (lambda () (remove-temp-directory victim)))))))
         (list answer (if (file-exists? victim) 'still-there 'removed)))))))

;; process-outcome : String [Symbol] -> (List Integer Symbol (Listof String) Symbol)
;; Runs a program that makes a process temp directory, prints its path, then
;; runs the forms in AFTER, in a fresh Chez whose TMPDIR is a directory of
;; this suite's making. The answer: its exit status; whether the path it
;; printed is under that TMPDIR; whatever else it printed, as lines; and
;; whether the directory is gone. With the symbol fake-rm after AFTER, the
;; program's PATH has an rm that removes nothing, so a removal fails.
(define (process-outcome after . options)
  (call-with-temp-directory
   (lambda (base)
     (let ((program (string-append base "/probe.sps"))
           (bin (string-append base "/bin")))
       (when (memq 'fake-rm options)
         (capture-command (list "mkdir" bin))
         (write-file (string-append bin "/rm") "#!/bin/sh\nexit 0\n")
         (capture-command (list "chmod" "+x" (string-append bin "/rm"))))
       (write-file program
                   (string-append
                    "#!r6rs\n"
                    "(import (rnrs) (only (chezscheme) warning file-directory?) (chez-sqlite3-testing))\n"
                    "(define dir (make-process-temp-directory))\n"
                    "(put-string (current-output-port) dir)\n"
                    "(put-string (current-output-port) \"\\n\")\n"
                    after "\n"))
       (let* ((answer (capture-command
                       (append (list "env" (string-append "TMPDIR=" base))
                               (if (memq 'fake-rm options)
                                   (list (string-append "PATH=" bin ":" (getenv "PATH")))
                                   '())
                               (list chez "--libdirs" "src:tests:build/scheme-libs"
                                     "--program" program))))
              (lines (let loop ((chars (string->list (cadr answer))) (line '()) (found '()))
                       (cond ((null? chars) (reverse found))
                             ((char=? (car chars) #\newline)
                              (loop (cdr chars) '() (cons (list->string (reverse line)) found)))
                             (else (loop (cdr chars) (cons (car chars) line) found)))))
              (dir (and (pair? lines) (car lines))))
         (list (car answer)
               (if (and dir (prefix? (string-append base "/") dir)) 'under-tmpdir 'elsewhere)
               (if (pair? lines) (cdr lines) lines)
               (if (and dir (file-exists? dir)) 'left 'removed)))))))

(define kept-line
  (string-append "(put-string (current-output-port) (if (file-directory? dir) \"kept\\n\" \"gone\\n\"))\n"
                 "(exit 0)"))

(test-equal "make-process-temp-directory: removed by exit, which keeps its status"
  '(3 under-tmpdir () removed)
  (process-outcome "(exit 3)"))

(test-equal "make-process-temp-directory: removed by a raise nothing guards, status 255"
  '(255 under-tmpdir () removed)
  (process-outcome "(car '())"))

(test-equal "make-process-temp-directory: removed by a raise of a non-condition too"
  '(255 under-tmpdir () removed)
  (process-outcome "(raise 'boom)"))

(test-equal "make-process-temp-directory: a removal that fails in the exit hook neither raises nor changes the status"
  '(3 under-tmpdir () left)
  (process-outcome "(exit 3)" 'fake-rm))

(test-equal "make-process-temp-directory: a removal that fails in the exception hook neither loops nor changes the status"
  '(255 under-tmpdir () left)
  (process-outcome "(car '())" 'fake-rm))

(test-equal "make-process-temp-directory: a raise a guard catches does not remove it"
  '(0 under-tmpdir ("kept") removed)
  (process-outcome
   (string-append "(guard (e (#t 'caught)) (car '()))\n"
                  "(guard (e (#t 'caught)) (raise 'boom))\n"
                  kept-line)))

(test-equal "make-process-temp-directory: a warning, which goes on, does not remove it"
  '(0 under-tmpdir ("kept") removed)
  (process-outcome
   (string-append "(warning 'probe \"just a warning\")\n" kept-line)))

;; --- the exit checks (ADR-0005, amended; the M1 plan, §3.7) ----------------
;; suite-exit-status runs every check registered with the counters, in the
;; order registered, and names each outcome on the error port: a pass, a
;; failure, which exits 1, or unavailable. A check is registered for good, so
;; each row runs in a child: a fresh Chez running a suite of one passing test
;; under a null runner, which prints nothing, then the forms given, then the
;; shared exit form. This suite's own process registers nothing: its verdict
;; rows above see no check.
;;
;; The first rows register checks of their own, and load no libsqlite3. The
;; rest load it, through (chez-sqlite3 private native), whose load registers
;; the sqlite3_memory_used check; each such child reads the count itself, and
;; prints what it read, so the row knows the numbers the verdict must name.
;; Those children reach native code, so each runs through gated-command: under
;; make test-memory the gate's own Valgrind runs it, with a log of its own, and
;; it prints (valgrind . yes|no) after its counts, read from /proc/self/maps.
;; Its row asserts the line: (valgrind . yes) there, (valgrind . no) in a plain
;; make test.

;; child-suite : String String -> (List Integer String String)
;; The exit status, stdout and stderr of a child suite whose imports end with
;; IMPORTS and whose forms after its one test are BODY.
(define (child-suite imports body)
  (run-child-suite capture-command imports body))

;; gated-child-suite : String String -> (List Integer String String)
;; child-suite for a child that reaches native code: run through
;; gated-command, and its stdout ends with its (valgrind . yes|no) line.
(define (gated-child-suite imports body)
  (run-child-suite (lambda (argv) (capture-command (gated-command getenv argv)))
                   imports
                   (string-append body "\n" valgrind-printer)))

;; Prints whether this process runs under memcheck: its preload is in /proc/self/maps.
(define valgrind-printer
  (string-append
   "(write (cons 'valgrind\n"
   "            (guard (e (#t 'no-maps))\n"
   "              (let ((maps (call-with-port\n"
   "                           (open-file-input-port \"/proc/self/maps\" (file-options) (buffer-mode block)\n"
   "                                                 (make-transcoder (utf-8-codec)))\n"
   "                           get-string-all))\n"
   "                    (needle \"vgpreload_memcheck\"))\n"
   "                (let loop ((i 0))\n"
   "                  (cond ((> (+ i (string-length needle)) (string-length maps)) 'no)\n"
   "                        ((string=? (substring maps i (+ i (string-length needle))) needle) 'yes)\n"
   "                        (else (loop (+ i 1)))))))))\n"
   "(newline)"))

;; Under make test-memory the gated child says (valgrind . yes); anywhere else, no.
(define valgrind-line
  (string-append "(valgrind . " (if (getenv "CHEZ_SQLITE3_GATE_CHILD") "yes" "no") ")\n"))

(define (run-child-suite run imports body)
  (call-with-temp-directory
   (lambda (base)
     (let ((program (string-append base "/child.sps")))
       (write-file program
                   (string-append
                    "#!r6rs\n"
                    "(import (rnrs) (srfi :64) (chez-sqlite3 private counters) (chez-sqlite3-testing)\n"
                    "        " imports ")\n"
                    "(define runner (test-runner-null))\n"
                    "(test-runner-current runner)\n"
                    "(test-begin \"child\")\n"
                    "(test-assert \"passes\" #t)\n"
                    body "\n"
                    "(test-end \"child\")\n"
                    "(exit (suite-exit-status runner))\n"))
       (run (list chez "--libdirs" "src:tests:build/scheme-libs" "--program" program))))))

(test-equal "two checks that pass and are unavailable: exit 0, each named on its own line, in the order registered"
  (list 0 ""
        (string-append
         "suite-exit-status: the zeta check passed: all is well\n"
         "suite-exit-status: the alpha check is unavailable: nothing to count here\n"))
  (child-suite ""
               (string-append "(register-exit-check! 'zeta (lambda () '(pass \"all is well\")))\n"
                              "(register-exit-check! 'alpha (lambda () '(unavailable \"nothing to count here\")))")))

(test-equal "a check that fails: exit 1, its line naming it"
  (list 1 "" "suite-exit-status: exit 1 (the fake check failed): it did not hold\n")
  (child-suite "" "(register-exit-check! 'fake (lambda () '(fail \"it did not hold\")))"))

(test-equal "a check that raises: exit 1, its line naming what it raised"
  (list 1 "" "suite-exit-status: exit 1 (the fake check failed): it raised: Exception in fake-check: it broke with irritant 42\n")
  (child-suite "" "(register-exit-check! 'fake (lambda () (error 'fake-check \"it broke\" 42)))"))

;; The answers a check may give are (pass TEXT), (fail TEXT) and
;; (unavailable TEXT); these are their neighbours. None may pass.
(test-equal "a check that answers anything but (pass TEXT), (fail TEXT) or (unavailable TEXT): exit 1, each named with what it answered"
  (list 1 ""
        (apply string-append
               (map (lambda (shown)
                      (string-append "suite-exit-status: exit 1 (the odd check failed): it answered "
                                     shown ", not (pass TEXT), (fail TEXT) or (unavailable TEXT)\n"))
                    '("fine" "(pass)" "(pass 5)" "(passed \"x\")" "(pass \"x\" \"y\")"
                      "(unavailable . \"x\")" "#f"))))
  (child-suite ""
               (apply string-append
                      (map (lambda (answer) (string-append "(register-exit-check! 'odd (lambda () '" answer "))\n"))
                           '("fine" "(pass)" "(pass 5)" "(passed \"x\")" "(pass \"x\" \"y\")"
                             "(unavailable . \"x\")" "#f")))))

;; The checks run before the counts are read, so a check that makes a native
;; object is seen. The child lowers the count again once the verdict is
;; printed, and exits 0 itself, so the shared exit form never runs the check
;; a second time.
(test-equal "a check that counts a block up and answers pass: the exit checks run before the counts are read, so the counts' line names block 1 and then the check's line; once the child lowers the count, it exits clean"
  (list 0 "(1 ((block . 0) (connection . 0) (statement . 0)))\n"
        (string-append "suite-exit-status: exit 1 (native objects left: block 1" counts-tail
                       "suite-exit-status: the bump check passed: counted\n"))
  (child-suite ""
               (string-append "(register-exit-check! 'bump (lambda () (count-up! 'block) '(pass \"counted\")))\n"
                              "(let ((status (suite-exit-status runner)))\n"
                              "  (count-down! 'block)\n"
                              "  (write (list status (native-counts)))\n"
                              "  (newline)\n"
                              "  (exit 0))")))

(test-equal "a failure, a native object left and two checks: every line, the runner's first, then the counts', then the checks' in the order registered"
  (list 1 ""
        (string-append
         "suite-exit-status: exit 1 (pass 1, fail 1, xpass 0" runner-tail
         "suite-exit-status: exit 1 (native objects left: statement 1" counts-tail
         "suite-exit-status: the zeta check passed: all is well\n"
         "suite-exit-status: exit 1 (the alpha check failed): it did not hold\n"))
  (child-suite ""
               (string-append "(test-assert \"fails\" #f)\n"
                              "(count-up! 'statement)\n"
                              "(register-exit-check! 'zeta (lambda () '(pass \"all is well\")))\n"
                              "(register-exit-check! 'alpha (lambda () '(fail \"it did not hold\")))")))

;; --- the sqlite3_memory_used check, on the library --------------------------

;; The verdict lines for the counts a child read: written out here, and not
;; read from the library.
(define (memory-pass-line baseline)
  (string-append "suite-exit-status: the sqlite3_memory_used check passed: the count is back at its baseline, "
                 (number->string baseline)
                 " bytes, after the control's :memory: open and close\n"))
(define (memory-fail-line after baseline)
  (string-append "suite-exit-status: exit 1 (the sqlite3_memory_used check failed): the count is "
                 (number->string after)
                 " bytes after the control's :memory: open and close, not its baseline, "
                 (number->string baseline)
                 " bytes: SQLite still holds memory that a suite's end must have freed\n"))
(define (memory-unavailable-line count)
  (string-append "suite-exit-status: the sqlite3_memory_used check is unavailable: the count was "
                 (number->string count) " bytes before the control's :memory: open and "
                 (number->string count)
                 " while it was open, so this libsqlite3 keeps no memory count\n"))

;; datum-of : String -> Any
;; The first datum of TEXT, or (unreadable TEXT).
(define (datum-of text)
  (guard (e (#t (list 'unreadable text)))
    (read (open-string-input-port text))))

(define native-import "(chez-sqlite3 private native)")

;; The children below leave SQLite memory held on purpose, for the exit check
;; to name. Under the gate's Valgrind a leak the child still holds at its end
;; would fail the gate, rightly, so each frees it in an exit handler: the
;; handler runs after suite-exit-status has run every check, which is the
;; moment the row is about, and keeps the exit status it was given.
(define exit-handler-import "(only (chezscheme) exit-handler)")

;; freed-after-the-exit-checks : String -> String
;; A form that runs FREE-FORM, when the child exits, after the checks.
(define (freed-after-the-exit-checks free-form)
  (string-append
   "(exit-handler (let ((previous (exit-handler)))\n"
   "  (lambda args " free-form " (apply previous args))))\n"))

;; The plant: SQLite memory held past a suite's end, through a raw open that
;; nothing counts and nothing closes. The child prints the count once loaded,
;; the count holding the open, and the open's code.
(define raw-plant
  (guard (e (#t (list 'raised (describe e))))
    (gated-child-suite (string-append native-import " " exit-handler-import)
                 (string-append
                  "(define baseline (sqlite3-memory-used))\n"
                  "(define plant-handle #f)\n"
                  "(define rc\n"
                  "  (call-with-c-string 'plant \":memory:\"\n"
                  "    (lambda (name)\n"
                  "      (let-values (((rc handle) (call-with-out-pointer 'plant (lambda (slot) (sqlite3-open-v2 name slot 6 0)))))\n"
                  "        (set! plant-handle handle)\n"
                  "        rc))))\n"
                  (freed-after-the-exit-checks "(sqlite3-close plant-handle)")
                  "(define holding (sqlite3-memory-used))\n"
                  "(write (list baseline holding rc))\n"
                  "(newline)"))))

;; plant-read : (U (List Integer Integer Integer) Any)
;; What the plant printed, its three counts, when it ran.
(define plant-read
  (if (and (list? raw-plant) (= (length raw-plant) 3) (string? (cadr raw-plant)))
      (datum-of (cadr raw-plant))
      raw-plant))

(define plant-read? (and (list? plant-read) (= (length plant-read) 3) (for-all integer? plant-read)))

;; counting? : Boolean
;; Whether this libsqlite3 keeps a memory count: the plant's open raised it.
;; Apple's does not (ADR-0005, amended), and there every check below is
;; unavailable.
(define counting? (and plant-read? (> (cadr plant-read) (car plant-read))))

(test-equal "SQLite memory held past the end through a raw open, never closed: exit 1, the check's line naming the count and the baseline, and no count of ours, which never saw the open; or, where the library keeps no count, unavailable and exit 0"
  (if plant-read?
      (let ((baseline (car plant-read)) (holding (cadr plant-read)))
        (list (if counting? 1 0)
              (string-append (call-with-string-output-port (lambda (p) (write plant-read p))) "\n"
                             valgrind-line)
              (if counting?
                  (memory-fail-line holding baseline)
                  (memory-unavailable-line baseline))))
      (list 'the-plant-printed-no-counts plant-read))
  raw-plant)

(test-equal "the plant's open succeeded, so its count is the open's"
  0
  (if plant-read? (caddr plant-read) plant-read))

;; native-child : String String -> (List Integer String String)
;; A child that loads native, reads the count, runs BODY, then prints the count
;; it read after the load and the one at the end of BODY.
(define (native-child imports body)
  (gated-child-suite (string-append native-import " " imports)
               (string-append "(define baseline (sqlite3-memory-used))\n"
                              body "\n"
                              "(write (list baseline (sqlite3-memory-used)))\n"
                              "(newline)")))

;; expected-for : Any ((List Integer Integer) -> Any) -> Any
;; EXPECTED given the two counts the child of OUTCOME printed, or why it
;; printed none. It raises nothing: an expected expression's raise would end
;; this suite, naming no test.
(define (expected-for outcome expected)
  (let ((read (and (list? outcome) (= (length outcome) 3) (string? (cadr outcome))
                   (datum-of (cadr outcome)))))
    (if (and (list? read) (= (length read) 2) (for-all integer? read))
        (expected read)
        (list 'the-child-printed-no-counts outcome))))

(define (printed counts)
  (string-append (call-with-string-output-port (lambda (p) (write counts p))) "\n" valgrind-line))

;; checked-line : Integer -> String
;; The check's line for a suite that freed all it held: a pass naming the
;; BASELINE, or unavailable where the library keeps no count.
(define (checked-line baseline)
  (if counting? (memory-pass-line baseline) (memory-unavailable-line baseline)))

(define opened-nothing
  (guard (e (#t (list 'raised (describe e)))) (native-child "" "")))

(test-equal "a suite that loaded libsqlite3 and opened nothing still runs the check, through its control: exit 0, the line naming the baseline"
  (expected-for opened-nothing
                (lambda (counts) (list 0 (printed counts) (checked-line (car counts)))))
  opened-nothing)

(define opened-and-closed
  (guard (e (#t (list 'raised (describe e))))
    (native-child "(chez-sqlite3)" "(close-database! (open-database \":memory:\"))")))

(test-equal "a suite that opened and closed a connection through open-database: exit 0, the line naming the baseline"
  (expected-for opened-and-closed
                (lambda (counts) (list 0 (printed counts) (checked-line (car counts)))))
  opened-and-closed)

(define left-open
  (guard (e (#t (list 'raised (describe e))))
    (native-child (string-append "(chez-sqlite3) " exit-handler-import)
                  (string-append "(define db (open-database \":memory:\"))\n"
                                 (freed-after-the-exit-checks "(close-database! db)")))))

(test-equal "a suite that left a connection from open-database open: exit 1, the connection counted, then the check's line naming the count it holds"
  (expected-for left-open
                (lambda (counts)
                  (list 1 (printed counts)
                        (string-append
                         "suite-exit-status: exit 1 (native objects left: connection 1" counts-tail
                         (if counting?
                             (memory-fail-line (cadr counts) (car counts))
                             (memory-unavailable-line (car counts)))))))
  left-open)


;; --- run-until ------------------------------------------------------------

;; steps-until : Natural Natural -> (List Symbol Natural)
;; run-until's answer for a predicate that holds once N steps are taken,
;; under a cap of CAP, then the number of steps it took.
(define (steps-until n cap)
  (let* ((steps 0)
         (answer (run-until (lambda () (set! steps (+ steps 1)))
                            (lambda () (>= steps n))
                            cap)))
    (list answer steps)))

(test-equal "run-until: a predicate that already holds costs no step"
  '(satisfied 0)
  (steps-until 0 5))

(test-equal "run-until: it steps until the predicate holds, and no further"
  '(satisfied 3)
  (steps-until 3 5))

(test-equal "run-until: a predicate that first holds after the last step allowed is satisfied"
  '(satisfied 4)
  (steps-until 4 4))

(test-equal "run-until: one step short, it answers iterations-exhausted, with no step past the cap"
  '(iterations-exhausted 4)
  (steps-until 5 4))

(test-equal "run-until: the cap is a positive exact integer"
  '(assertion-violation run-until (0))
  (raised (lambda () (run-until (lambda () 'step) (lambda () #f) 0))))

(test-equal "run-until: the predicate is a procedure"
  '(assertion-violation run-until (#t))
  (raised (lambda () (run-until (lambda () 'step) #t 3))))

(test-equal "run-until: the step is a procedure"
  '(assertion-violation run-until (step))
  (raised (lambda () (run-until 'step (lambda () #f) 3))))


;; --- gated-command ----------------------------------------------------------

;; env-of : (Listof (Pairof String String)) -> (String -> (U String #f))
;; A getenv that reads ALIST and nothing else.
(define (env-of alist)
  (lambda (name) (cond ((assoc name alist) => cdr) (else #f))))

(define child-argv '("/opt/chez/bin/scheme" "--libdirs" "src" "--program" "tests/p.sps" "a b"))

(test-equal "gated-command: with CHEZ_SQLITE3_GATE_CHILD unset, the command comes back unchanged"
  child-argv
  (gated-command (env-of '(("OTHER" . "valgrind"))) child-argv))

(test-equal "gated-command: with it set, its words come first, cut at runs of spaces, tabs and newlines, and each argument of the command stays one word"
  (append '("valgrind" "-v" "--log-file=build/memory/x.children/%p.valgrind" "--error-exitcode=9")
          child-argv)
  (gated-command (env-of '(("CHEZ_SQLITE3_GATE_CHILD"
                            . "  valgrind\t-v --log-file=build/memory/x.children/%p.valgrind\n --error-exitcode=9 ")))
                 child-argv))

(test-equal "gated-command: a value that holds no word is refused, since no Valgrind would run the child"
  '((assertion-violation gated-command ("")) (assertion-violation gated-command (" \t ")))
  (let* ((empty (raised (lambda () (gated-command (env-of '(("CHEZ_SQLITE3_GATE_CHILD" . ""))) child-argv))))
         (blank (raised (lambda () (gated-command (env-of '(("CHEZ_SQLITE3_GATE_CHILD" . " \t "))) child-argv)))))
    (list empty blank)))

(test-equal "gated-command: a command is a non-empty list of strings"
  '((assertion-violation gated-command (())) (assertion-violation gated-command (("scheme" 5))))
  (let* ((none (raised (lambda () (gated-command (env-of '()) '()))))
         (odd (raised (lambda () (gated-command (env-of '()) '("scheme" 5))))))
    (list none odd)))

;; --- describe -------------------------------------------------------------

(define-record-type unprintable (fields x))
(record-writer (record-type-descriptor unprintable)
  (lambda (r port wr) (error 'unprintable "this record cannot be printed")))

(test-equal "describe: a condition, as display-condition shows it"
  "Exception in f: bad thing with irritants (1 \"two\")"
  (describe (condition (make-error)
                       (make-who-condition 'f)
                       (make-message-condition "bad thing")
                       (make-irritants-condition '(1 "two")))))

(test-equal "describe: anything else is written, so a string keeps its quotes"
  "(1 \"two\" three)"
  (describe '(1 "two" three)))

(test-equal "describe: an object whose printing raises gets a fixed text, not a raise"
  "<the raised object could not be printed>"
  (describe (make-unprintable 1)))

(test-end "chez-sqlite3-testing")

;; This suite tests suite-exit-status, so its exit cannot rest on it alone:
;; a suite-exit-status that ignored failures would pass this suite, and
;; make test with it. Any failure here exits 1 first.
(when (or (positive? (test-runner-fail-count runner))
          (positive? (test-runner-xpass-count runner)))
  (exit 1))

(exit (suite-exit-status runner))
