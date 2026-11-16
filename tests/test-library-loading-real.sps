#!r6rs
;;; One of the three suites that load libsqlite3 end to end, through (chez-sqlite3
;;; private native), tests/refusal-probe.sps and tests/preflight.sps
;;; (ADR-0002, ADR-0003, ADR-0010, ADR-0013): this one holds the real
;;; libsqlite3, the refusals no decoy reaches, discovery, make build's
;;; preflight, and its part of the decoy's missing-api rows.
;;; tests/test-library-loading-decoys.sps holds the decoy's behaviours and its
;;; own part; tests/test-library-loading-missing.sps holds only missing-api
;;; rows, the largest part. They were one suite until it passed 450 s under
;;; the memory gate on CI, three quarters of MEMORY_TIMEOUT (ADR-0005,
;;; amended); (library-loading) holds what all three use.
;;;
;;; Native loads libsqlite3 in its library body, once per process, and Chez
;;; runs that body before a program's own, so a refusal cannot be caught in
;;; this process, nor a second library tried in it. Every case therefore runs
;;; tests/refusal-probe.sps in a fresh Chez, through `env`, and reads back
;;; what it printed, as data, whole: exit status, every line, and stderr.
;;;
;;;   - decoys: this suite's part of the missing-api rows, as the other suites
;;;     build them, and the control build, for preflight. The partition's
;;;     three rows are held here too, so that any one suite alone holds it;
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
        (foreign-conventions)
        (libsqlite3-oracle)
        (library-loading)
        (only (chezscheme) getenv putenv format format-condition? load-shared-object
              file-directory? foreign-entry? machine-type directory-list)
        (chez-sqlite3 private discovery))

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

(test-begin "library-loading-real")

;; The Makefile exports CHEZ, so this suite spawns the Chez that runs it.
;; Without it nothing below can run: fail, never skip.
(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (set? chez) 'set 'unset))

(unless (set? chez)
  (exit 1))

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

(define floor-values (read-floor-values))

(test-equal "packaging/floors.sexp gives the decoys their versions: the floor, and the one below it"
  'read
  (if (and (= (length floor-values) 4) (string? (car floor-values))) 'read floor-values))

(unless (string? (car floor-values))
  (exit 1))

(define floor-version (car floor-values))
(define floor-number (cadr floor-values))
(define below-version (caddr floor-values))
(define below-number (cadddr floor-values))

;; --- the partition ----------------------------------------------------------------------

;; Each part makes the missing-api rows of one suite. Merged in the table's
;; order, the parts are its names exactly when each entry is in one part,
;; once, and each part keeps the table's order; the other two suites hold the
;; same row.
(test-equal "the three suites' entry lists partition the convention table: merged in its order, they are its names, each once"
  (map row-name conventions-table)
  (merge-halves (map row-name conventions-table) (map cdr decoy-parts)))

;; The partition is dealt: native's order, by position from 0, by a pattern of
;; five that repeats (deal-pattern). The row above holds only that the parts
;; partition the table, each in its order, so two entries swapped between
;; parts, or one moved to another, passes it. Each part is exactly what the
;; pattern deals its suite, and every name the pattern holds is a part.
(test-equal "each suite's part is the entries the pattern deals it, by position in the convention table from 0, and the pattern names only parts"
  (list decoy-parts 'all)
  (list (map (lambda (part)
               (cons (car part) (entries-dealt (map row-name conventions-table) deal-pattern (car part))))
             decoy-parts)
        (if (for-all (lambda (name) (assoc name decoy-parts)) deal-pattern) 'all deal-pattern)))

;; The pattern, written out, so that it and the parts changed together, which
;; the rows above pass, still fail: three of every five entries to the missing
;; suite, which holds only missing-api rows, and one each to the decoys' and
;; the real suite, which hold about 20 children of their own (ADR-0005,
;; amended 2026-11-16).
(test-equal "the pattern deals positions 0, 2 and 4 of every five to the missing suite, 1 to the decoys' suite and 3 to the real suite"
  '("test-library-loading-missing.sps" "test-library-loading-decoys.sps"
    "test-library-loading-missing.sps" "test-library-loading-real.sps"
    "test-library-loading-missing.sps")
  deal-pattern)

;; this-part : (U (Pairof String (Listof String)) #f)
;; This suite's part, by its own file's name. The row below writes the name
;; out, so a suite copied from another, or a lookup that answers another
;; part, fails it.
(define this-part (suite-part (command-line)))

(test-equal "this suite runs its own part of the partition, found by its file's name, and each suite the partition names is a file in tests/"
  (list "test-library-loading-real.sps" (map (lambda (part) (cons (car part) 'present)) decoy-parts))
  (list (if this-part (car this-part) (list 'unlisted (command-line)))
        (map (lambda (part)
               (cons (car part) (if (file-exists? (string-append "tests/" (car part))) 'present 'absent)))
             decoy-parts)))

(define this-entries (if this-part (cdr this-part) '()))

;; --- decoys --------------------------------------------------------------------------

;; builds : (Listof (Pairof String (Listof String)))
;; The control, for preflight's rows, and a lacking build for each entry of
;; this suite's part.
(define builds
  (decoy-builds (cons "control" (map lacks-build this-entries))))

(define (so-of build) (in-scratch (string-append build ".so")))

;; compiled : (Listof (Pairof String Any))
;; Every build, compiled once, in order.
(define compiled (compile-decoys so-of floor-values builds))

(define (compiled-status build) (decoy-status compiled build))

;; decoy-env : String (U String #f) -> (Listof String)
(define (decoy-env build switch)
  (cons (override (so-of build)) (switch-args switch)))

;; decoy-row : String (U String #f) (Listof String) String (String -> Expected) -> Void
;; (library-loading)'s decoy-row-in, on this suite's builds.
(define (decoy-row build switch args description expected)
  (decoy-row-in so-of compiled-status build switch args description expected))

(define control-report (report floor-version floor-number "decoy-sourceid"))
(define (control-library so) (report-of so 'override control-report))

;; This suite's part of the entry points, each left out, one at a time
;; ((library-loading)'s missing-api-rows).
(missing-api-rows decoy-row control-library this-entries)

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

(test-end "library-loading-real")

(exit (suite-exit-status runner))
