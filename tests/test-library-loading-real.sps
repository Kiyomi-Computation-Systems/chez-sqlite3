#!r6rs
;;; One of the nine suites that load libsqlite3 end to end, through
;;; (chez-sqlite3 private native), tests/refusal-probe.sps and tests/preflight.sps
;;; (ADR-0002, ADR-0003, ADR-0010, ADR-0013): this one holds the real
;;; libsqlite3, the refusals no decoy reaches, discovery, and make build's
;;; preflight on the real libsqlite3. tests/test-library-loading-preflight.sps
;;; holds preflight's other rows.
;;;
;;; The nine were one suite until it passed 450 s under the memory gate on
;;; CI, three quarters of MEMORY_TIMEOUT, then three until -real took 264 s
;;; there, over half of it (ADR-0005); now each runs at most 11
;;; children, and (library-loading) holds what all nine use.
;;;
;;; Native loads libsqlite3 in its library body, once per process, and Chez
;;; runs that body before a program's own, so a refusal cannot be caught in
;;; this process, nor a second library tried in it. Every case therefore runs
;;; a probe in a fresh Chez, through `env`, and reads back what it printed,
;;; as data, whole: exit status, every line, and stderr.
;;;
;;;   - the real libsqlite3: the one the probe loads in this environment,
;;;     then through the override, and preflight's report of it. What each
;;;     reports must equal what tests/libsqlite3-oracle.c reads from the same
;;;     file;
;;;   - the refusals no decoy reaches: invalid-override, load-failed, and
;;;     not-found, by world. In a Guix world, not-found is built end to end.
;;;     In an FHS world the standard directories cannot be emptied, so that
;;;     row asserts discovery's success there instead, and its name says
;;;     which world ran.
;;;
;;; Each child that reaches native code prints its counts, and every row
;;; requires them zero (ADR-0005). Each runs through
;;; gated-command, so under make test-memory the gate's own Valgrind runs it,
;;; with a log of its own that the gate reads. Every child says whether it ran
;;; under Valgrind, and a row requires yes exactly when the gate asked: the
;;; probe, and the C oracle, print a line saying so (memcheck's preload in
;;; /proc/self/maps); preflight prints none, so (library-loading)'s
;;; preflight reads the one new log in the gate's directory for it, and
;;; requires that log's Command: line to be preflight's own, whole. A child
;;; that escaped the gate fails its row (ADR-0005).
;;;
;;; This process itself never loads libsqlite3, and requires as much at its
;;; end. Each expected value is one the code under test cannot produce by
;;; failing, and none is #f: SRFI-64 makes #f of a raise in the actual
;;; expression. Anything that can raise is computed under a guard with a
;;; sentinel. Effects run in order, through let*, named lets and for-each,
;;; never map.
(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
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

;; --- the scratch directory ------------------------------------------------------------

;; scratch : (U String #f)
;; A fresh directory for the fake profile, the text file and the empty
;; HOME. This suite is flat top-level forms, so (chez-sqlite3-testing)
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

;; --- the real libsqlite3 ---------------------------------------------------------------

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

;; make build's preflight on the same file, through the override: what it
;; tells a person installing chez-sqlite3, all of it, the C oracle's report
;; (tests/test-library-loading-preflight.sps holds preflight's other rows).
(test-equal "preflight, the real libsqlite3: exit 0, with the C oracle's report, then its counts"
  (list 0 (accepted-text (or real-libsqlite3 "?") 'override (oracle-report real-oracle)) ""
        valgrind-line)
  (preflight (cons (override (or real-libsqlite3 "/the-probe-loaded-nothing")) (switch-args #f))))

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

;; --- discovery, with the override unset --------------------------------------------------
;; By platform first, then, on Linux, by world. Each child unsets the override
;; itself, and sets the Guix variables it wants.

;; platform : (U 'linux 'macos 'other)
(define platform (machine-platform))

;; world : (U 'guix 'fhs (List 'raised String))
(define world (process-world))

(test-equal "the world, guix or fhs, was determined"
  'determined
  (if (memq world '(guix fhs)) 'determined world))

(define empty-home (in-scratch "home"))
(test-equal "the empty HOME was made"
  'made
  (make-directory empty-home))

;; No profile to search: what not-found needs in a Guix world.
(define no-profiles (no-profiles-env empty-home))

(define guix-not-found-candidates (guix-candidates-in empty-home))

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

;; --- every C oracle run said whether it ran under Valgrind --------------------------
;; The C oracle's answers carry the line among other things.

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
