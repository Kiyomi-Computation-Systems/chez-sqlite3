#!r6rs
;;; The suite for loading libsqlite3 end to end: (chez-sqlite3 private
;;; native), tests/refusal-probe.sps and tests/preflight.sps (ADR-0002,
;;; ADR-0003, ADR-0010, ADR-0013).
;;;
;;; Native loads libsqlite3 in its library body, once per process, and Chez
;;; runs that body before a program's own, so a refusal cannot be caught in
;;; this process, nor a second library tried in it. Every case therefore runs
;;; tests/refusal-probe.sps in a fresh Chez, through `env`, and reads back
;;; what it printed, as data, whole: exit status, every line, and stderr.
;;;
;;;   - decoys: tests/decoy-libsqlite3.c, compiled here with $CC (else cc)
;;;     once per build, each export left out one at a time, and run under
;;;     one behaviour per row, chosen by CHEZ_SQLITE3_DECOY. Each row asserts
;;;     the refusal's reason and every field (plan section 3.4), and the
;;;     decoy's call log, whole. The log holds the load's order by
;;;     behaviour: the report's three, the floor, threadsafe, initialize,
;;;     then the rest, each refused before the next runs. A lacking build
;;;     run under a behaviour that an earlier step refuses holds that step's
;;;     place: the earlier refusal must win. A failed compile fails its row,
;;;     never skips it (ADR-0001). The decoy's versions are the floor and the
;;;     one below it, read from packaging/floors.sexp (ADR-0008);
;;;   - the load runs once: the probe references loaded-libsqlite3 three
;;;     times, and the later two must answer what the first did, with no
;;;     second load in the call log and no second library in the process;
;;;   - the real libsqlite3: the one the probe loads in this environment,
;;;     then through the override. What it reports must equal what
;;;     tests/libsqlite3-oracle.c reads from the same file;
;;;   - the refusals no decoy reaches: invalid-override, load-failed, and
;;;     not-found, by world. In a Guix world, not-found is built end to end.
;;;     In an FHS world the standard directories cannot be emptied, so that
;;;     row asserts discovery's success there instead, and its name says
;;;     which world ran;
;;;   - make build's preflight: its exit status and its output, whole. Its
;;;     remedy line is the refusal's own message, compared with what the
;;;     probe read for the same refusal: never written here as text
;;;     (ADR-0002, ADR-0013).
;;;
;;; Each child that reaches native code prints its counts, and every row
;;; requires them zero (ADR-0005, decision 4). Each runs through
;;; gated-command, so under make test-memory the gate's own Valgrind runs it,
;;; with a log of its own that the gate reads. Every child says whether it ran
;;; under Valgrind, and a row requires yes exactly when the gate asked: the
;;; probe, and the C oracle, print a line saying so (memcheck's preload in
;;; /proc/self/maps); preflight prints none, so this suite reads the one new
;;; log in the gate's directory for it, and requires that log's Command: line
;;; to be preflight's own, whole. A child that escaped the gate fails its row
;;; (ADR-0005, amended).
;;;
;;; This process itself never loads libsqlite3, and requires as much at its
;;; end. Each expected value is one the code under test cannot produce by
;;; failing, and none is #f: SRFI-64 makes #f of a raise in the actual
;;; expression. Anything that can raise is computed under a guard with a
;;; sentinel. Effects run in order, through let*, named lets and for-each,
;;; never map (AGENTS.md).
(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
        (libsqlite3-oracle)
        (floors)
        (only (chezscheme) getenv putenv format format-condition? load-shared-object
              file-directory? foreign-entry? machine-type directory-list)
        (chez-sqlite3 private discovery)
        (chez-sqlite3 private verify)
        (chez-sqlite3 private constants))

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

;; --- strings -------------------------------------------------------------------------

(define (string-prefix? prefix s)
  (let ((n (string-length s)) (m (string-length prefix)))
    (and (>= n m) (string=? (substring s 0 m) prefix))))

(define (string-suffix? suffix s)
  (let ((n (string-length s)) (m (string-length suffix)))
    (and (>= n m) (string=? (substring s (- n m) n) suffix))))

(define (absolute? s)
  (and (string? s) (string-prefix? "/" s)))

;; join : (Listof String) -> String
;; ENTRIES with one space between: a decoy's call log.
(define (join entries)
  (if (null? entries)
      ""
      (fold-left (lambda (all entry) (string-append all " " entry))
                 (car entries) (cdr entries))))

(define (set? value) (and (string? value) (not (string=? value ""))))

;; --- the processes it spawns -----------------------------------------------------------

(define chez (getenv "CHEZ"))

(test-begin "library-loading")

;; The Makefile exports CHEZ, so this suite spawns the Chez that runs it.
;; Without it nothing below can run: fail, never skip.
(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (set? chez) 'set 'unset))

(unless (set? chez)
  (exit 1))

;; Every compile here, the decoys' and the oracle's, runs $CC's words.
(test-equal "CC is cut at whitespace, so CC='ccache gcc' runs ccache, with gcc as its argument"
  '(("ccache" "gcc") ("gcc" "-m64") ("cc") ("cc"))
  (let* ((a (c-compiler (lambda (name) (and (string=? name "CC") " ccache\tgcc "))))
         (b (c-compiler (lambda (name) (and (string=? name "CC") "gcc -m64"))))
         (c (c-compiler (lambda (name) (and (string=? name "CC") "  "))))
         (d (c-compiler (lambda (name) #f))))
    (list a b c d)))

;; read-data : String -> (U (Listof Any) (List 'unreadable String))
;; TEXT read as a sequence of data.
(define (read-data text)
  (guard (e (#t (list 'unreadable text)))
    (let ((port (open-string-input-port text)))
      (let loop ((data '()))
        (let ((datum (read port)))
          (if (eof-object? datum)
              (reverse data)
              (loop (cons datum data))))))))

;; env-order : (Listof String) -> (Listof String)
;; ENV-ARGS with every -u NAME pair first, then each NAME=VALUE, each group in
;; its own order: env reads -u only before the first assignment.
(define (env-order env-args)
  (let loop ((rest env-args) (unsets '()) (sets '()))
    (cond ((null? rest) (append (reverse unsets) (reverse sets)))
          ((and (string=? (car rest) "-u") (pair? (cdr rest)))
           (loop (cddr rest) (cons* (cadr rest) "-u" unsets) sets))
          (else (loop (cdr rest) unsets (cons (car rest) sets))))))

;; spawn-in : String (Listof String) String (Listof String)
;;            -> (U (List Integer String String) (List 'raised String))
;; Runs PROGRAM with ARGS in a fresh Chez with LIBDIRS as its library path,
;; under the memory gate's Valgrind when the gate asks (gated-command),
;; through env with ENV-ARGS (NAME=VALUE to set, -u NAME to unset): its exit
;; status, stdout and stderr. Never env -i: CHEZ and PATH survive
;; (.plans/traps.md).
(define (spawn-in libdirs env-args program args)
  (guard (e (#t (list 'raised (describe e))))
    (capture-command
     (append '("env") (env-order env-args)
             (gated-command getenv (append (list chez "--libdirs" libdirs "--program" program)
                                           args))))))

(define (spawn env-args program args) (spawn-in "src" env-args program args))

;; as-data : (U (List Integer String String) (List 'raised String))
;;           -> (U (List Integer (Listof Any) String) (List 'raised String))
;; A probe's answer, with what it printed read as data.
(define (as-data answer)
  (if (eq? (car answer) 'raised)
      answer
      (list (car answer) (read-data (cadr answer)) (caddr answer))))

;; probe-with : (Listof String) (Listof String)
;;              -> (U (List Integer (Listof Any) String) (List 'raised String))
;; tests/refusal-probe.sps under ENV-ARGS, with ARGS.
(define (probe-with env-args args)
  (as-data (spawn env-args "tests/refusal-probe.sps" args)))

(define (probe env-args) (probe-with env-args '()))

(define (override path) (string-append "CHEZ_SQLITE3_LIBRARY=" path))

;; switch-args : (U String #f) -> (Listof String)
;; CHEZ_SQLITE3_DECOY set to SWITCH, or unset for #f: every child gets one or
;; the other, so a value left in this process's environment never reaches a
;; row.
(define (switch-args switch)
  (if switch
      (list (string-append "CHEZ_SQLITE3_DECOY=" switch))
      '("-u" "CHEZ_SQLITE3_DECOY")))

;; The probe references loaded-libsqlite3 three times. A load runs once per
;; process, whatever it decided, so the two later references answer the very
;; object the first did: the report, or the refusal raised again.
(define once '(again . (same same)))

;; Every count zero, whatever the load decided (ADR-0005, decision 4).
(define no-native-objects '(counts . ((block . 0) (connection . 0) (statement . 0))))

;; Under make test-memory, every child runs under the gate's own Valgrind,
;; and says so; anywhere else, none does.
(define gated? (and (getenv "CHEZ_SQLITE3_GATE_CHILD") #t))
(define valgrind-line (cons 'valgrind (if gated? 'yes 'no)))

;; outcome : Integer (Listof Pair) (Listof Pair) (Listof Pair) (U (Listof String) #f)
;;           -> Expected
;; The probe's whole answer: STATUS; the lines of its first reference, HEAD;
;; BEFORE (then-override) and the references' again; the counts; AFTER
;; (marker); whether it ran under Valgrind; and the decoy's call log, CALLS,
;; as entries, or no calls line for a library without one. Its stderr is
;; empty.
(define (outcome status head before after calls)
  (list status
        (append head before (list once no-native-objects) after (list valgrind-line)
                (if calls (list (cons 'calls (join calls))) '()))
        ""))

;; A report is what a loaded library says about itself, as the probe prints
;; it after the path and source: (version . V) (version-number . N)
;; (source-id . ID).
(define (report version number source-id)
  (list (cons 'version version) (cons 'version-number number) (cons 'source-id source-id)))

;; loaded-lines : String Symbol Report Any -> (Listof Pair)
(define (loaded-lines path source report threadsafe)
  (append (list (cons 'loaded path) (cons 'source source)) report
          (list (cons 'threadsafe threadsafe))))

;; refused-lines : Symbol (U String #f) (U Symbol #f) Any (Listof String) Any
;;                  (Listof Any) -> (Listof Pair)
;; LIBRARY is report-of's list for a refusal made after the version was
;; read, else #f. IRRITANTS are the condition's: the path, as the one
;; irritant, for each refusal that has a path.
(define (refused-lines reason path source detail candidates library irritants)
  (list (cons 'reason reason) (cons 'who 'chez-sqlite3) (cons 'path path)
        (cons 'source source) (cons 'detail detail) (cons 'candidates candidates)
        (cons 'library library) (cons 'irritants irritants)))

;; report-of : String Symbol Report -> (Listof Any)
;; A refusal's library as the probe prints it: path, source, then the
;; report's values.
(define (report-of path source report)
  (cons* path source (map cdr report)))

(define (loaded path source report threadsafe calls)
  (outcome 0 (loaded-lines path source report threadsafe) '() '() calls))

(define refused
  (case-lambda
    ((reason path source detail candidates library calls)
     (refused reason path source detail candidates library calls (list path)))
    ((reason path source detail candidates library calls irritants)
     (outcome 1 (refused-lines reason path source detail candidates library irritants)
              '() '() calls))))

;; --- the scratch directory and the floors ----------------------------------------------

;; scratch : (U String #f)
;; A fresh directory for the decoys, the fake profile, the text file and the
;; empty HOME. This suite is flat top-level forms, so (chez-sqlite3-testing)
;; removes the directory when the process ends; the last forms remove it
;; earlier, and the tests below require that.
(define scratch
  (guard (e (#t #f))
    (make-process-temp-directory)))

(test-equal "mktemp -d made a scratch directory"
  'made
  (if (and (absolute? scratch) (file-directory? scratch)) 'made 'not-made))

(unless (and (absolute? scratch) (file-directory? scratch))
  (exit 1))

(define (in-scratch name) (string-append scratch "/" name))

;; write-text-file : String String -> (U 'written (List 'not-written String))
;; TEXT in the file at PATH, or what went wrong; never a raise.
(define (write-text-file path text)
  (guard (e (#t (list 'not-written (describe e))))
    (call-with-port (open-file-output-port path (file-options no-fail)
                                           (buffer-mode block)
                                           (make-transcoder (utf-8-codec)))
      (lambda (p) (put-string p text)))
    'written))

;; make-directory : String -> (U 'made (List 'not-made Any))
;; mkdir -p PATH, or what went wrong; never a raise.
(define (make-directory path)
  (guard (e (#t (list 'not-made (describe e))))
    (let ((answer (capture-command (list "mkdir" "-p" path))))
      (if (and (eqv? (car answer) 0) (file-directory? path)) 'made (list 'not-made answer)))))

;; floor-values : (U (List String Natural String Natural) (List 'no-floors Any))
;; SQLite's floor from packaging/floors.sexp, its number as
;; sqlite3_libversion_number encodes it, and the version one below it, as
;; text and number: the decoy's versions (ADR-0008).
(define floor-values
  (guard (e (#t (list 'no-floors (describe e))))
    (let* ((floors (read-floors))
           (parts (floor-numbers floors 'sqlite))
           (number (+ (* (car parts) 1000000) (* (cadr parts) 1000) (caddr parts)))
           (below (- number 1)))
      (list (floor-text floors 'sqlite) number (version-number->string below) below))))

(test-equal "packaging/floors.sexp gives the decoys their versions: the floor, and the one below it"
  'read
  (if (and (= (length floor-values) 4) (string? (car floor-values))) 'read floor-values))

(unless (string? (car floor-values))
  (exit 1))

(define floor-version (car floor-values))
(define floor-number (cadr floor-values))
(define below-version (caddr floor-values))
(define below-number (cadddr floor-values))

;; --- decoys --------------------------------------------------------------------------

(define decoy-source "tests/decoy-libsqlite3.c")

;; The entry points (chez-sqlite3 private native) binds, in its order
;; (ADR-0002, amended): the report's three, threadsafe, initialize, and the
;; rest. A sixteenth that native binds and the decoy lacks refuses the
;; control, and the control's row fails.
(define report-entries '("sqlite3_libversion_number" "sqlite3_libversion" "sqlite3_sourceid"))
(define rest-entries
  '("sqlite3_compileoption_used" "sqlite3_compileoption_get" "sqlite3_open_v2" "sqlite3_close"
    "sqlite3_errmsg" "sqlite3_errstr" "sqlite3_errcode" "sqlite3_extended_errcode"
    "sqlite3_next_stmt" "sqlite3_memory_used"))
(define every-entry (append report-entries '("sqlite3_threadsafe" "sqlite3_initialize") rest-entries))

(define (lacks entry) (string-append "-DDECOY_LACKS_" entry))

;; builds : (Listof (Pairof String (Listof String)))
;; Each build's name and its switches.
(define builds
  (append (list (list "control")
                (list "marked" "-DDECOY_MARKER")
                (list "not-sqlite" "-DDECOY_NOT_SQLITE")
                (cons "lacks-rest" (map lacks rest-entries)))
          (map (lambda (entry) (list (string-append "lacks-" entry) (lacks entry))) every-entry)))

(define (so-of build) (in-scratch (string-append build ".so")))

;; compile-decoy : String (Listof String) -> (U 0 (List Integer String String) (List 'raised String))
;; Compiles the decoy as BUILD.so in the scratch directory under SWITCHES, with
;; the floor's versions: 0, or the compiler's whole answer when it failed.
(define (compile-decoy build switches)
  (guard (e (#t (list 'raised (describe e))))
    (let ((answer (capture-command
                   (append (c-compiler getenv)
                           (list "-Wall" "-Werror" "-shared" "-fPIC" "-o" (so-of build) decoy-source
                                 (string-append "-DDECOY_VERSION_NUMBER=" (number->string floor-number))
                                 (string-append "-DDECOY_VERSION=\"" floor-version "\"")
                                 (string-append "-DDECOY_BELOW_NUMBER=" (number->string below-number))
                                 (string-append "-DDECOY_BELOW=\"" below-version "\""))
                           switches))))
      (if (eqv? (car answer) 0) 0 answer))))

;; compiled : (Listof (Pairof String Any))
;; Every build, compiled once, in order.
(define compiled
  (let loop ((rest builds) (done '()))
    (if (null? rest)
        (reverse done)
        (let ((status (compile-decoy (caar rest) (cdar rest))))
          (loop (cdr rest) (cons (cons (caar rest) status) done))))))

(define (compiled-status build)
  (cond ((assoc build compiled) => cdr) (else (list 'no-such-build build))))

;; decoy-env : String (U String #f) -> (Listof String)
(define (decoy-env build switch)
  (cons (override (so-of build)) (switch-args switch)))

;; decoy-row : String (U String #f) (Listof String) String (String -> Expected) -> Void
;; The test DESCRIPTION: the probe, with ARGS, on BUILD under SWITCH; the
;; build's compile must have answered 0, then EXPECTED of its path. Every
;; row references loaded-libsqlite3 three times, so each log asserted whole
;; also shows that the load ran once.
(define (decoy-row build switch args description expected)
  (test-equal (string-append "decoy " build
                             (if switch (string-append " under \"" switch "\"") "")
                             ": " description)
    (cons 0 (expected (so-of build)))
    (cons (compiled-status build) (probe-with (decoy-env build switch) args))))

;; The call log's entries, as tests/decoy-libsqlite3.c writes them: first the
;; switch it read, then each call.
(define (read-switch switch) (string-append "decoy(" switch ")"))
(define the-report-three '("sqlite3_libversion_number()" "sqlite3_libversion()" "sqlite3_sourceid()"))
(define threadsafe-call "sqlite3_threadsafe()")
(define initialize-call "sqlite3_initialize()")
(define (log-of switch . calls) (cons (read-switch switch) calls))
(define (every-call switch)
  (append (list (read-switch switch)) the-report-three (list threadsafe-call initialize-call)))

(define control-report (report floor-version floor-number "decoy-sourceid"))
(define below-report (report below-version below-number "decoy-sourceid"))
(define (control-library so) (report-of so 'override control-report))
(define (below-library so) (report-of so 'override below-report))

;; code-of : Symbol -> (U Integer (List 'no-code Symbol))
;; A result code's value, from (chez-sqlite3 private constants), which
;; tests/test-constants.sps holds to sqlite3.h. A name it lacks answers
;; (no-code NAME), which no probe prints, so that row fails by name.
(define (code-of name)
  (guard (e (#t (list 'no-code name)))
    (cdr (assq name sqlite-result-codes))))

(decoy-row "control" #f '()
  "the floor itself is accepted: the report's five fields, threadsafe 2, and the load's five calls in order"
  (lambda (so) (loaded so 'override control-report 2 (every-call "control"))))

(decoy-row "control" "below-floor" '()
  "one below the floor is below-floor, detail its version, carrying its report, and nothing runs after the report's three"
  (lambda (so) (refused 'below-floor so 'override below-version '() (below-library so)
                        (apply log-of "below-floor" the-report-three))))

(decoy-row "control" "not-threadsafe" '()
  "sqlite3_threadsafe answering 0 is not-threadsafe, detail 0, and sqlite3_initialize never runs"
  (lambda (so) (refused 'not-threadsafe so 'override 0 '() (control-library so)
                        (append (apply log-of "not-threadsafe" the-report-three)
                                (list threadsafe-call)))))

(decoy-row "control" "libversion-null" '()
  "sqlite3_libversion answering NULL is load-failed, naming it, with no report, and sqlite3_sourceid never runs"
  (lambda (so) (refused 'load-failed so 'override "sqlite3_libversion" '() #f
                        (log-of "libversion-null" "sqlite3_libversion_number()" "sqlite3_libversion()"))))

(decoy-row "control" "sourceid-null" '()
  "sqlite3_sourceid answering NULL is load-failed, naming it, with no report"
  (lambda (so) (refused 'load-failed so 'override "sqlite3_sourceid" '() #f
                        (apply log-of "sourceid-null" the-report-three))))

;; sqlite3_sourceid's bytes are UTF-8: é is two bytes, λ two and € three, and
;; a reading as Latin-1 would report seven characters for them.
(decoy-row "control" "sourceid-utf8" '()
  "a source id past ASCII is read as UTF-8: d\xE9;coy-\x3BB;\x20AC;"
  (lambda (so) (loaded so 'override (report floor-version floor-number "d\xE9;coy-\x3BB;\x20AC;") 2
                       (every-call "sourceid-utf8"))))

(decoy-row "control" "initialize-fails" '()
  "sqlite3_initialize answering SQLITE_NOMEM is load-failed, detail that code, carrying the report, after threadsafe"
  (lambda (so) (refused 'load-failed so 'override (code-of 'nomem) '() (control-library so)
                        (every-call "initialize-fails"))))

;; A second code, so that no one value passes for "not SQLITE_OK".
(decoy-row "control" "initialize-misuse" '()
  "sqlite3_initialize answering SQLITE_MISUSE is load-failed too, detail that code, not NOMEM's"
  (lambda (so) (refused 'load-failed so 'override (code-of 'misuse) '() (control-library so)
                        (every-call "initialize-misuse"))))

;; Only an exact value is a switch: a near miss, and an empty value, behave as
;; the control, and the log shows what the decoy read.
(decoy-row "control" "Below-floor" '()
  "a value that is no switch behaves as the control, and the log names it"
  (lambda (so) (loaded so 'override control-report 2
                       (append (list "decoy(?Below-floor)") the-report-three
                               (list threadsafe-call initialize-call)))))

(decoy-row "control" "below-floorX" '()
  "a value that only begins with a switch, below-floorX, is no switch: the control, and the log names it"
  (lambda (so) (loaded so 'override control-report 2
                       (append (list "decoy(?below-floorX)") the-report-three
                               (list threadsafe-call initialize-call)))))

(decoy-row "control" "" '()
  "an empty value is no switch either"
  (lambda (so) (loaded so 'override control-report 2
                       (append (list "decoy(?)") the-report-three
                               (list threadsafe-call initialize-call)))))

;; Each entry point left out, one at a time: refused by name before anything
;; calls it, never Chez's "no entry for". The report's three are each bound
;; before any is called, so a library lacking one has had no call, and no
;; report. Every later refusal carries the report.
(for-each
 (lambda (entry)
   (decoy-row (string-append "lacks-" entry) #f '()
     (string-append "a library without " entry " is missing-api, naming it")
     (lambda (so)
       (cond ((member entry report-entries)
              (refused 'missing-api so 'override entry '() #f (log-of "control")))
             ((string=? entry "sqlite3_threadsafe")
              (refused 'missing-api so 'override entry '() (control-library so)
                       (apply log-of "control" the-report-three)))
             ((string=? entry "sqlite3_initialize")
              (refused 'missing-api so 'override entry '() (control-library so)
                       (append (apply log-of "control" the-report-three) (list threadsafe-call))))
             (else
              (refused 'missing-api so 'override entry '() (control-library so)
                       (every-call "control")))))))
 every-entry)

(decoy-row "lacks-rest" #f '()
  "a library without any of the rest is refused naming the first in ADR-0002's order, sqlite3_compileoption_used"
  (lambda (so) (refused 'missing-api so 'override "sqlite3_compileoption_used" '() (control-library so)
                        (every-call "control"))))

(decoy-row "not-sqlite" #f '()
  "a library with no sqlite3_* function is missing-api, naming sqlite3_libversion_number, the first asked"
  (lambda (so) (refused 'missing-api so 'override "sqlite3_libversion_number" '() #f (log-of "control"))))

;; The load's order, by behaviour. Each row's library lacks an entry point that
;; a later step binds, and answers wrongly at an earlier step: the earlier
;; step's refusal must win, and the log must stop where it does.
(decoy-row "lacks-sqlite3_open_v2" "below-floor" '()
  "the floor comes before the rest: below-floor, not missing-api"
  (lambda (so) (refused 'below-floor so 'override below-version '() (below-library so)
                        (apply log-of "below-floor" the-report-three))))

(decoy-row "lacks-sqlite3_open_v2" "not-threadsafe" '()
  "threadsafe comes before the rest: not-threadsafe, not missing-api"
  (lambda (so) (refused 'not-threadsafe so 'override 0 '() (control-library so)
                        (append (apply log-of "not-threadsafe" the-report-three)
                                (list threadsafe-call)))))

(decoy-row "lacks-sqlite3_open_v2" "initialize-fails" '()
  "sqlite3_initialize comes before the rest: load-failed with its code, not missing-api"
  (lambda (so) (refused 'load-failed so 'override (code-of 'nomem) '() (control-library so)
                        (every-call "initialize-fails"))))

(decoy-row "lacks-sqlite3_threadsafe" "below-floor" '()
  "the floor comes before threadsafe's binding: below-floor, not missing-api"
  (lambda (so) (refused 'below-floor so 'override below-version '() (below-library so)
                        (apply log-of "below-floor" the-report-three))))

(decoy-row "lacks-sqlite3_initialize" "not-threadsafe" '()
  "threadsafe's check comes before sqlite3_initialize's binding: not-threadsafe, not missing-api"
  (lambda (so) (refused 'not-threadsafe so 'override 0 '() (control-library so)
                        (append (apply log-of "not-threadsafe" the-report-three)
                                (list threadsafe-call)))))

;; A refusal is kept. Below the floor, then CHEZ_SQLITE3_LIBRARY names the
;; marked build, and the probe references loaded-libsqlite3 twice more. Both
;; raise the first refusal again: nothing is loaded or called a second time,
;; and the second library never enters the process (ADR-0002).
(let ((first (so-of "control")) (second (so-of "marked")))
  (test-equal "a refusal is kept: CHEZ_SQLITE3_LIBRARY changed between references loads nothing new"
    (list 0 0 1
          (append (refused-lines 'below-floor first 'override below-version '() (below-library first)
                                 (list first))
                  (list (cons 'then-override second) once no-native-objects (cons 'marker 'absent)
                        valgrind-line
                        (cons 'calls (join (apply log-of "below-floor" the-report-three)))))
          "")
    (cons* (compiled-status "control") (compiled-status "marked")
           (probe-with (decoy-env "control" "below-floor")
                       (list "--then-override" second "--marker" "decoy_marker")))))

;; The marker's control: loaded, the marked build's marker is seen.
(decoy-row "marked" #f '("--marker" "decoy_marker")
  "a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?"
  (lambda (so) (outcome 0 (loaded-lines so 'override control-report 2) '()
                        (list (cons 'marker 'present)) (every-call "control"))))

;; --- the real libsqlite3 ---------------------------------------------------------------

;; field : Any Symbol -> Pair
;; The (KEY . VALUE) the probe printed for KEY, or (KEY . absent).
(define (field answer key)
  (or (and (pair? answer) (pair? (cdr answer)) (list? (cadr answer))
           (for-all pair? (cadr answer))
           (assq key (cadr answer)))
      (cons key 'absent)))

;; The probe, in this process's own environment: the libsqlite3 a program here
;; would load, through the override when it is set, by discovery when not.
(define ambient (probe (switch-args #f)))

(define real-libsqlite3
  (let ((path (cdr (field ambient 'loaded))))
    (and (absolute? path) path)))

(test-equal "the real libsqlite3: the probe, in this environment, loads one by absolute path"
  'loaded
  (if (and (pair? ambient) (eqv? (car ambient) 0) real-libsqlite3) 'loaded ambient))

(test-equal "the real libsqlite3: that probe ran under Valgrind exactly when the gate asked"
  valgrind-line
  (field ambient 'valgrind))

;; oracle-runs : (Listof Pair)
;; The (valgrind . yes) or (valgrind . no) line of every oracle run so far, or
;; (valgrind no-oracle) of one that failed: the last rows require each.
(define oracle-runs '())

;; oracle-of : (U String #f) -> (U (Listof (Pairof Symbol Any)) (List 'no-oracle Symbol Any))
;; What tests/libsqlite3-oracle.c reads from the library at PATH.
(define (oracle-of path)
  (let ((oracle (if (string? path)
                    (libsqlite3-oracle getenv path '())
                    (list 'no-oracle 'no-path path))))
    (set! oracle-runs
          (cons (or (and (list? oracle) (for-all pair? oracle) (assq 'valgrind oracle))
                    (list 'valgrind 'no-oracle))
                oracle-runs))
    oracle))

(define real-oracle (oracle-of real-libsqlite3))

;; oracle-field : Any Symbol -> Pair
;; The oracle's (KEY . VALUE), or (KEY no-oracle) when it failed.
(define (oracle-field oracle key)
  (or (and (list? oracle) (for-all pair? oracle) (assq key oracle))
      (list key 'no-oracle)))

;; oracle-report : Any -> Report
(define (oracle-report oracle)
  (list (oracle-field oracle 'version) (oracle-field oracle 'version-number)
        (oracle-field oracle 'source-id)))

(define (oracle-threadsafe oracle) (cdr (oracle-field oracle 'threadsafe)))

(test-equal "the C oracle read the real libsqlite3"
  'read
  (if (and (pair? real-oracle) (eq? (car real-oracle) 'no-oracle)) real-oracle 'read))

;; Field by field, so a failure names the field.
(for-each
 (lambda (key)
   (test-equal (string-append "the real libsqlite3: the probe's " (symbol->string key)
                              " is the C oracle's")
     (oracle-field real-oracle key)
     (field ambient key)))
 '(version version-number source-id threadsafe))

(test-equal "the real libsqlite3 through the override: loaded, with the C oracle's report and threadsafe answer, whole"
  (loaded (or real-libsqlite3 "?") 'override (oracle-report real-oracle)
          (oracle-threadsafe real-oracle) #f)
  (probe (cons (override (or real-libsqlite3 "/the-probe-loaded-nothing")) (switch-args #f))))

;; call-with-tmpdir : String (-> Any) -> Any
;; THUNK with TMPDIR set to DIR. Afterwards TMPDIR is put back to its old
;; value, or to /tmp when it was unset: putenv cannot unset, and /tmp is
;; where mktemp and capture-command go for an unset TMPDIR.
(define (call-with-tmpdir dir thunk)
  (let ((old (getenv "TMPDIR")))
    (dynamic-wind
      (lambda () (putenv "TMPDIR" dir))
      thunk
      (lambda () (putenv "TMPDIR" (or old "/tmp"))))))

;; The oracle never raises, and removes its directory when something inside it
;; raises. Here the getenv it is handed does, once the directory exists.
(test-equal "the oracle, when a raise comes inside its directory: it answers no-oracle, and has removed the directory"
  '(no-oracle raised 1 ())
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (base)
       (let* ((seen '())
              (answer (call-with-tmpdir base
                        (lambda ()
                          (libsqlite3-oracle (lambda (name)
                                               (set! seen (directory-list base))
                                               (raise 'getenv-raised))
                                             "/unused" '())))))
         (list (car answer) (cadr answer) (length seen) (directory-list base)))))))

;; --- refusals no decoy reaches ----------------------------------------------------------

(test-equal "a bare name in the override is invalid-override, carrying it"
  (refused 'invalid-override #f 'override "libsqlite3.so.0" '() #f #f (list "libsqlite3.so.0"))
  (probe (cons (override "libsqlite3.so.0") (switch-args #f))))

;; loader-text : String -> (U String (List Symbol Any))
;; What Chez's loader says when it refuses PATH, formatted as native formats
;; it: the oracle for load-failed's detail. Nothing loads.
(define (loader-text path)
  (guard (e ((and (format-condition? e) (message-condition? e) (irritants-condition? e))
             (apply format (condition-message e) (condition-irritants e)))
            (#t (list 'unexpected-raise (describe e))))
    (load-shared-object path)
    (list 'loaded path)))

(define text-file (in-scratch "not-a-library.so"))
(test-equal "the text file was written"
  'written
  (write-text-file text-file "not a shared object\n"))
(define text-file-refusal (loader-text text-file))

(test-equal "a text file is load-failed, with the loader's message"
  (refused 'load-failed text-file 'override text-file-refusal '() #f #f)
  (probe (cons (override text-file) (switch-args #f))))

(define no-such-file (in-scratch "no-such-dir/libsqlite3.so.0"))
(define no-such-file-refusal (loader-text no-such-file))

(test-equal "a path that does not exist is load-failed, with the loader's message"
  (refused 'load-failed no-such-file 'override no-such-file-refusal '() #f #f)
  (probe (cons (override no-such-file) (switch-args #f))))

;; --- a raise that is not a refusal --------------------------------------------------------
;; tests/fixtures/raising/chez-sqlite3/private/native.sls shadows src/'s
;; native: its loaded-libsqlite3 raises a plain error. That is a bug, not a
;; refusal, and the probe must report it as a raise.

(define raising-libdirs "tests/fixtures/raising:src")

;; What the fixture raises, as the probe prints it: its &who, and the condition
;; types it is, by name (rnrs's error: serious, error, who, message and
;; irritants); never its text (ADR-0013, decision 9).
(define fixture-raised '(loaded-libsqlite3 (serious error who message irritants)))

(test-equal "a raise that is not a refusal: the probe prints its who and its types, each reference again, and exits 2"
  (list 2 (list (cons 'raised fixture-raised)
                (cons 'again (list (cons 'raised fixture-raised) (cons 'raised fixture-raised)))
                no-native-objects valgrind-line)
        "")
  (as-data (spawn-in raising-libdirs (switch-args #f) "tests/refusal-probe.sps" '())))

;; --- discovery, with the override unset --------------------------------------------------
;; By platform first, then, on Linux, by world. Each child unsets the override
;; itself, and sets the Guix variables it wants.

;; platform : (U 'linux 'macos 'other)
(define platform
  (let ((name (symbol->string (machine-type))))
    (cond ((string-suffix? "le" name) 'linux)
          ((string-suffix? "osx" name) 'macos)
          (else 'other))))

;; real-maps : (U String #f)
;; This process's /proc/self/maps, as native reads it. A probe runs the same
;; Chez, so it lives in the same world.
(define real-maps
  (guard (e (#t #f))
    (call-with-port (open-file-input-port "/proc/self/maps" (file-options)
                                          (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      get-string-all)))

(define world
  (guard (e (#t (list 'raised (describe e))))
    (libsqlite3-world (if (string? real-maps) real-maps #f))))

(test-equal "the world, guix or fhs, was determined"
  'determined
  (if (memq world '(guix fhs)) 'determined world))

(define empty-home (in-scratch "home"))
(test-equal "the empty HOME was made"
  'made
  (make-directory empty-home))

(define unset-override (cons* "-u" "CHEZ_SQLITE3_LIBRARY" (switch-args #f)))

;; No profile to search: what not-found needs in a Guix world.
(define no-profiles
  (append unset-override
          (list "-u" "GUIX_ENVIRONMENT" "-u" "GUIX_PROFILE" (string-append "HOME=" empty-home))))

(define guix-not-found-candidates
  (list (string-append empty-home "/.guix-home/profile/lib/libsqlite3.so.0")
        (string-append empty-home "/.guix-profile/lib/libsqlite3.so.0")
        "/run/current-system/profile/lib/libsqlite3.so.0"))

;; first-standard : (U String (List 'no-fhs-candidate-exists) (List 'raised String))
;; The first FHS candidate that exists here, as discovery would choose it.
(define first-standard
  (guard (e (#t (list 'raised (describe e))))
    (or (find file-exists? (map car (libsqlite3-candidates 'fhs (machine-type) getenv)))
        (list 'no-fhs-candidate-exists))))

;; loaded-fhs : -> Expected
;; The probe's whole answer when discovery chooses the first FHS candidate.
(define (loaded-fhs)
  (let ((oracle (oracle-of (and (string? first-standard) first-standard))))
    (loaded first-standard 'system (oracle-report oracle) (oracle-threadsafe oracle) #f)))

(case platform
  ((macos)
   ;; Apple's, the one candidate, lives in the dyld shared cache.
   (let ((oracle (oracle-of "/usr/lib/libsqlite3.dylib")))
     (test-equal "discovery (macos): with the override unset, Apple's /usr/lib/libsqlite3.dylib loads"
       (loaded "/usr/lib/libsqlite3.dylib" 'macos-system (oracle-report oracle)
               (oracle-threadsafe oracle) #f)
       (probe unset-override))))
  ((linux)
   (case world
     ((guix)
      (let* ((environment-libsqlite3
              (string-append (or (getenv "GUIX_ENVIRONMENT") "<GUIX_ENVIRONMENT unset>")
                             "/lib/libsqlite3.so.0"))
             (oracle (oracle-of environment-libsqlite3)))
        (test-equal "discovery (guix world): with the override unset, $GUIX_ENVIRONMENT/lib/libsqlite3.so.0 loads"
          (loaded environment-libsqlite3 'guix-environment (oracle-report oracle)
                  (oracle-threadsafe oracle) #f)
          (probe unset-override))

        ;; Only the three candidates no variable names are left, and none of
        ;; them exists here: the container has no /run/current-system.
        (test-equal "not-found (guix world): with no profile to search, not-found lists every candidate checked"
          (refused 'not-found #f #f #f guix-not-found-candidates #f #f (list guix-not-found-candidates))
          (probe no-profiles))

        ;; GUIX_ENVIRONMENT's candidate exists, so it is chosen, but it is a
        ;; text file. GUIX_PROFILE's, next in line, is a real libsqlite3, and
        ;; must never be tried (ADR-0002).
        (let* ((broken-profile (in-scratch "broken-profile"))
               (broken (string-append broken-profile "/lib/libsqlite3.so.0")))
          (test-equal "the broken profile's lib directory was made"
            'made
            (make-directory (string-append broken-profile "/lib")))
          (test-equal "the broken profile's text file was written"
            'written
            (write-text-file broken "not a shared object\n"))
          (let ((refusal (loader-text broken)))
            (test-equal "discovery (guix world): a candidate that fails to load is load-failed, and the next is never tried"
              (refused 'load-failed broken 'guix-environment refusal '() #f #f)
              (probe (append unset-override
                             (list (string-append "GUIX_ENVIRONMENT=" broken-profile)
                                   (string-append "GUIX_PROFILE="
                                                  (or (getenv "GUIX_ENVIRONMENT") "/nonexistent"))
                                   (string-append "HOME=" empty-home)))))))))
     (else
      (test-equal "discovery (fhs world): with the override unset, the first standard candidate that exists loads, source system"
        (loaded-fhs)
        (probe unset-override))

      ;; No Guix profile is a candidate here, and the standard directories
      ;; cannot be emptied, so not-found cannot be built: with no profile to
      ;; search, discovery must still load the first standard candidate.
      (test-equal "not-found (fhs world): not buildable, so with no profile to search, discovery's success instead: the first standard candidate, source system"
        (loaded-fhs)
        (probe no-profiles)))))
  (else
   (test-equal "not-found (no list on this platform): with the override unset, not-found, having no candidate"
     (refused 'not-found #f #f #f '() #f #f (list '()))
     (probe unset-override))))

;; --- make build's preflight ----------------------------------------------------------------
;; Its output is what make build tells a person installing chez-sqlite3, so
;; these rows assert all of it. Its remedy line is the refusal's message,
;; which no test writes as text (ADR-0002, ADR-0013): it must equal what the
;; probe read for the same refusal, in a process of its own.

;; The gate's directory of child logs, from the prefix make test-memory
;; exports: the directory of its --log-file=DIR/%p.valgrind word; #f outside
;; the gate.
(define gate-log-dir
  (let ((prefix (getenv "CHEZ_SQLITE3_GATE_CHILD")))
    (and prefix
         (let loop ((words (split-words prefix)))
           (cond ((null? words) #f)
                 ((and (string-prefix? "--log-file=" (car words))
                       (string-suffix? "/%p.valgrind" (car words)))
                  (let ((word (car words)))
                    (substring word (string-length "--log-file=")
                               (- (string-length word) (string-length "/%p.valgrind")))))
                 (else (loop (cdr words))))))))

;; gate-logs : -> (Listof String)
;; The names in the gate's directory of child logs, sorted; none outside the
;; gate.
(define (gate-logs)
  (if gate-log-dir
      (guard (e (#t (list 'unreadable)))
        (list-sort string<? (directory-list gate-log-dir)))
      '()))

;; command-of-log : String -> (U String (List 'no-command String))
;; The program and arguments of the Command: line of the Valgrind log NAME in
;; the gate's directory.
(define (command-of-log name)
  (guard (e (#t (list 'no-command (describe e))))
    (let ((text (call-with-port
                 (open-file-input-port (string-append gate-log-dir "/" name) (file-options)
                                       (buffer-mode block) (make-transcoder (utf-8-codec)))
                 get-string-all)))
      (let loop ((lines (lines-of text)))
        (cond ((null? lines) (list 'no-command name))
              ((command-line-of (car lines)) => (lambda (command) command))
              (else (loop (cdr lines))))))))

;; lines-of : String -> (Listof String)
(define (lines-of text)
  (let loop ((i 0) (start 0) (found '()))
    (cond ((= i (string-length text))
           (reverse (if (> i start) (cons (substring text start i) found) found)))
          ((char=? (string-ref text i) #\newline)
           (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
          (else (loop (+ i 1) start found)))))

;; command-line-of : String -> (U String #f)
;; What follows "==PID== Command: " on LINE, else #f.
(define (command-line-of line)
  (let ((marker "== Command: "))
    (and (string-prefix? "==" line)
         (let loop ((i 2))
           (cond ((>= (+ i (string-length marker)) (string-length line)) #f)
                 ((string=? (substring line i (+ i (string-length marker))) marker)
                  (substring line (+ i (string-length marker)) (string-length line)))
                 ((char-numeric? (string-ref line i)) (loop (+ i 1)))
                 (else #f))))))

;; preflight-in : String (Listof String) -> (List Integer String String Pair)
;; tests/preflight.sps with LIBDIRS under ENV-ARGS: its exit status, stdout
;; and stderr, then (valgrind . yes) when exactly one log is new in the gate's
;; directory and its Command: line is the child's own, whole; (valgrind . no)
;; when none is, as outside the gate; else what the new logs were. Preflight
;; prints no such line itself: it is what make build runs.
(define (preflight-in libdirs env-args)
  (let* ((before (gate-logs))
         (answer (spawn-in libdirs env-args "tests/preflight.sps" '()))
         (after (gate-logs))
         (new (filter (lambda (name) (not (member name before))) after))
         (command (join (list chez "--libdirs" libdirs "--program" "tests/preflight.sps"))))
    (append answer
            (list (cons 'valgrind
                        (cond ((null? new) 'no)
                              ((and (null? (cdr new)) (equal? (command-of-log (car new)) command))
                               'yes)
                              (else (list 'logs new (map command-of-log new)))))))))

;; preflight : (Listof String) -> (List Integer String String Pair)
(define (preflight env-args) (preflight-in "src" env-args))

;; message-runs : (Listof Pair)
;; The valgrind line of every probe message-of ran: the last rows require each.
(define message-runs '())

;; message-of : (Listof String) -> (U String (List 'no-message Any))
;; The message of the refusal the probe meets under ENV-ARGS.
(define (message-of env-args)
  (let* ((answer (probe-with env-args '("--message" "yes")))
         (entry (field answer 'message)))
    (set! message-runs (cons (field answer 'valgrind) message-runs))
    (if (string? (cdr entry)) (cdr entry) (list 'no-message answer))))

(define counts-line "  counts:     ((block . 0) (connection . 0) (statement . 0))\n")

;; text : Any ... -> (U String (List 'unbuildable Any))
;; PARTS displayed one after another, or a sentinel no output equals when a
;; part is no string or number.
(define (text . parts)
  (if (for-all (lambda (p) (or (string? p) (number? p) (symbol? p))) parts)
      (call-with-string-output-port
       (lambda (port) (for-each (lambda (p) (display p port)) parts)))
      (list 'unbuildable parts)))

;; accepted-text : Any Symbol Report -> (U String (List 'unbuildable Any))
(define (accepted-text path source report)
  (text "chez-sqlite3: libsqlite3 loaded and accepted\n"
        "  path:       " path " (" source ")\n"
        "  version:    " (cdr (list-ref report 0)) " (" (cdr (list-ref report 1)) ")\n"
        "  source id:  " (cdr (list-ref report 2)) "\n"
        counts-line))

(let ((so (so-of "control")))
  (test-equal "preflight, the control decoy: exit 0, naming its path, version and source id, then its counts"
    (list 0 (accepted-text so 'override control-report) "" valgrind-line)
    (preflight (decoy-env "control" #f))))

(test-equal "preflight, the real libsqlite3: exit 0, with the C oracle's report, then its counts"
  (list 0 (accepted-text (or real-libsqlite3 "?") 'override (oracle-report real-oracle)) ""
        valgrind-line)
  (preflight (cons (override (or real-libsqlite3 "/the-probe-loaded-nothing")) (switch-args #f))))

(let* ((so (so-of "control"))
       (env-args (decoy-env "control" "below-floor")))
  (test-equal "preflight, the control decoy below the floor: exit 1, the reason, the fields and the report it read, the refusal's own message as the remedy, then its counts"
    (list 1 ""
          (text "chez-sqlite3: libsqlite3 refused\n"
                "(reason . below-floor)\n"
                "  path:       " so "\n"
                "  source:     override\n"
                "  detail:     " below-version "\n"
                "  version:    " below-version " (" below-number ")\n"
                "  source id:  decoy-sourceid\n"
                "  candidates: none\n"
                "  remedy:     " (message-of env-args) "\n"
                counts-line)
          valgrind-line)
    (preflight env-args)))

(let ((env-args (cons (override "libsqlite3.so.0") (switch-args #f))))
  (test-equal "preflight, a bare name: exit 1, invalid-override, the refusal's own message as the remedy, then its counts"
    (list 1 ""
          (text "chez-sqlite3: libsqlite3 refused\n"
                "(reason . invalid-override)\n"
                "  path:       none\n"
                "  source:     override\n"
                "  detail:     libsqlite3.so.0\n"
                "  candidates: none\n"
                "  remedy:     " (message-of env-args) "\n"
                counts-line)
          valgrind-line)
    (preflight env-args)))

;; reason-line? : String -> Boolean
;; Whether some line of TEXT begins "(reason ", as a refusal's first datum does.
(define (reason-line? text)
  (exists (lambda (line) (string-prefix? "(reason " line)) (lines-of text)))

;; A raise that is no refusal is Chez's default handler's to print, and what
;; it prints is its own text, never asserted here (ADR-0013, decision 9): the
;; row asserts the exit status, that nothing reached stdout, and that no
;; refusal's reason line appeared.
(test-equal "preflight, a raise that is not a refusal: Chez's default handler, exit 255, nothing on stdout, and no reason line"
  (list 255 "" 'no-reason-line valgrind-line)
  (let ((answer (preflight-in raising-libdirs (switch-args #f))))
    (if (eq? (car answer) 'raised)
        answer
        (list (car answer) (cadr answer)
              (if (reason-line? (caddr answer)) 'reason-line 'no-reason-line)
              (cadddr answer)))))

(when (and (eq? platform 'linux) (eq? world 'guix))
  (test-equal "preflight, not-found (guix world), no profile to search: exit 1, every candidate on its own line, then its counts"
    (list 1 ""
          (text "chez-sqlite3: libsqlite3 refused\n"
                "(reason . not-found)\n"
                "  path:       none\n"
                "  source:     none\n"
                "  detail:     none\n"
                "  candidates:\n"
                "    " (car guix-not-found-candidates) "\n"
                "    " (cadr guix-not-found-candidates) "\n"
                "    " (caddr guix-not-found-candidates) "\n"
                "  remedy:     " (message-of no-profiles) "\n"
                counts-line)
          valgrind-line)
    (preflight no-profiles)))

;; --- every child said whether it ran under Valgrind -----------------------------------------
;; The probe's own rows assert the line in their whole answers, and preflight's
;; rows theirs. These are the children whose answers carry it among other
;; things: the message probes, and the C oracle's runs.

(test-equal "every probe that read a refusal's message ran under Valgrind exactly when the gate asked, and there were at least two"
  (cons #t (map (lambda (run) valgrind-line) message-runs))
  (cons (>= (length message-runs) 2) message-runs))

(test-equal "every C oracle run ran under Valgrind exactly when the gate asked, and there were at least two"
  (cons #t (map (lambda (run) valgrind-line) oracle-runs))
  (cons (>= (length oracle-runs) 2) oracle-runs))

;; --- this process ----------------------------------------------------------------------------

(test-equal "this suite's own process never loaded a libsqlite3, nor a decoy"
  '(not-loaded not-loaded)
  (list (if (foreign-entry? "sqlite3_libversion_number") 'loaded 'not-loaded)
        (if (foreign-entry? "decoy_calls") 'loaded 'not-loaded)))

(test-equal "the scratch directory is removed"
  '(done removed)
  (list (guard (e (#t (list 'raised (describe e))))
          (remove-temp-directory scratch)
          'done)
        (if (file-directory? scratch) 'left 'removed)))

(test-end "library-loading")

(exit (suite-exit-status runner))
