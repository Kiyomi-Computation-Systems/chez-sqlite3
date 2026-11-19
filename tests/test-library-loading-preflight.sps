#!r6rs
;;; One of the nine suites that load libsqlite3 end to end, through
;;; (chez-sqlite3 private native), tests/refusal-probe.sps and tests/preflight.sps
;;; (ADR-0002, ADR-0003, ADR-0010, ADR-0013): this one holds make build's
;;; preflight, and a raise that is not a refusal, through the probe and
;;; through preflight. tests/test-library-loading-real.sps holds preflight on
;;; the real libsqlite3.
;;;
;;; The nine were one suite until it passed 450 s under the memory gate on
;;; CI, three quarters of MEMORY_TIMEOUT, then three until -real took 264 s
;;; there, over half of it (ADR-0005, amended); now each runs at most 11
;;; children, and (library-loading) holds what all nine use.
;;;
;;; Native loads libsqlite3 in its library body, once per process, and Chez
;;; runs that body before a program's own, so a refusal cannot be caught in
;;; this process, nor a second library tried in it. Every case therefore runs
;;; a probe in a fresh Chez, through `env`, and reads back what it printed,
;;; as data, whole: exit status, every line, and stderr.
;;;
;;;   - make build's preflight: its exit status and its output, whole, on
;;;     the control decoy, below the floor, a bare name, a raise that is not
;;;     a refusal and, in a Guix world, not-found. Its remedy line is the
;;;     refusal's own message, compared with what the probe read for the
;;;     same refusal: never written here as text (ADR-0002, ADR-0013);
;;;   - a raise that is not a refusal: a fixture native that raises a plain
;;;     error, which the probe reports as a raise.
;;;
;;; Each child that reaches native code prints its counts, and every row
;;; requires them zero (ADR-0005, decision 4). Each runs through
;;; gated-command, so under make test-memory the gate's own Valgrind runs it,
;;; with a log of its own that the gate reads. Every child says whether it ran
;;; under Valgrind, and a row requires yes exactly when the gate asked: the
;;; probe prints a line saying so (memcheck's preload in /proc/self/maps);
;;; preflight prints none, so (library-loading)'s preflight reads the one new
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
        (library-loading)
        (only (chezscheme) file-directory? foreign-entry?))

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

(test-begin "library-loading-preflight")

;; The Makefile exports CHEZ, so this suite spawns the Chez that runs it.
;; Without it nothing below can run: fail, never skip.
(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (set? chez) 'set 'unset))

(unless (set? chez)
  (exit 1))

;; --- the scratch directory and the floors ----------------------------------------------

;; scratch : (U String #f)
;; A fresh directory for the decoy and the empty HOME. This suite is flat
;; top-level forms, so (chez-sqlite3-testing) removes the directory when the
;; process ends; the last forms remove it earlier, and the tests below require
;; that.
(define scratch
  (guard (e (#t #f))
    (make-process-temp-directory)))

(test-equal "mktemp -d made a scratch directory"
  'made
  (if (and (absolute? scratch) (file-directory? scratch)) 'made 'not-made))

(unless (and (absolute? scratch) (file-directory? scratch))
  (exit 1))

(define (in-scratch name) (string-append scratch "/" name))

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

;; --- decoys --------------------------------------------------------------------------

;; builds : (Listof (Pairof String (Listof String)))
;; The control, for preflight's rows on a decoy.
(define builds (decoy-builds '("control")))

(define (so-of build) (in-scratch (string-append build ".so")))

;; compiled : (Listof (Pairof String Any))
;; Every build, compiled once, in order. Preflight's rows read the control's
;; output, so a failed compile fails them.
(define compiled (compile-decoys so-of floor-values builds))

;; decoy-env : String (U String #f) -> (Listof String)
(define (decoy-env build switch)
  (cons (override (so-of build)) (switch-args switch)))

(define control-report (report floor-version floor-number "decoy-sourceid"))

;; --- the world -------------------------------------------------------------------------
;; Preflight's not-found row needs a Guix world and no profile to search, as
;; tests/test-library-loading-real.sps's not-found row does.

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

;; --- make build's preflight ----------------------------------------------------------------
;; Its output is what make build tells a person installing chez-sqlite3, so
;; these rows assert all of it. Its remedy line is the refusal's message,
;; which no test writes as text (ADR-0002, ADR-0013): it must equal what the
;; probe read for the same refusal, in a process of its own. Preflight
;; itself, its text and its gate check are (library-loading)'s.

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

(let ((so (so-of "control")))
  (test-equal "preflight, the control decoy: exit 0, naming its path, version and source id, then its counts"
    (list 0 (accepted-text so 'override control-report) "" valgrind-line)
    (preflight (decoy-env "control" #f))))

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

;; --- every probe that read a message said whether it ran under Valgrind --------------
;; The message probes' answers carry the line among other things.

(test-equal "every probe that read a refusal's message ran under Valgrind exactly when the gate asked, and there were at least two"
  (cons #t (map (lambda (run) valgrind-line) message-runs))
  (cons (>= (length message-runs) 2) message-runs))

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

(test-end "library-loading-preflight")

(exit (suite-exit-status runner))
