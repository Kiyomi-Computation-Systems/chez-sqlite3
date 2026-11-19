#!r6rs
;;; One of the nine suites that load libsqlite3 end to end, through
;;; (chez-sqlite3 private native), tests/refusal-probe.sps and a decoy
;;; (ADR-0002, ADR-0003, ADR-0010, ADR-0013): this one holds the decoy's
;;; builds combined with its behaviours: a build without the rest, one with
;;; no sqlite3_* function, the load's order (a lacking build under a switch
;;; that an earlier step refuses), and the kept refusal with the marker.
;;; tests/test-library-loading-decoys.sps holds each switch alone.
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
;;;   - decoys: tests/decoy-libsqlite3.c, compiled here with $CC (else cc)
;;;     once per build, and run under one behaviour per row, chosen by
;;;     CHEZ_SQLITE3_DECOY. Each row asserts the refusal's reason and every
;;;     field (plan section 3.4), and the decoy's call log, whole. A lacking
;;;     build run under a behaviour that an earlier step refuses holds that
;;;     step's place: the earlier refusal must win. A failed compile fails
;;;     its row, never skips it (ADR-0001). The decoy's versions are the floor
;;;     and the one below it, read from packaging/floors.sexp (ADR-0008);
;;;   - the load runs once: the probe references loaded-libsqlite3 three
;;;     times, and the later two must answer what the first did, with no
;;;     second load in the call log and no second library in the process.
;;;
;;; Each child that reaches native code prints its counts, and every row
;;; requires them zero (ADR-0005, decision 4). Each runs through
;;; gated-command, so under make test-memory the gate's own Valgrind runs it,
;;; with a log of its own that the gate reads. Every child here is the probe,
;;; which says whether it ran under Valgrind (memcheck's preload in
;;; /proc/self/maps), and a row requires yes exactly when the gate asked. A
;;; child that escaped the gate fails its row (ADR-0005, amended).
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

(test-begin "library-loading-combined")

;; The Makefile exports CHEZ, so this suite spawns the Chez that runs it.
;; Without it nothing below can run: fail, never skip.
(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (set? chez) 'set 'unset))

(unless (set? chez)
  (exit 1))

;; --- the scratch directory and the floors ----------------------------------------------

;; scratch : (U String #f)
;; A fresh directory for the decoys. This suite is flat top-level forms, so
;; (chez-sqlite3-testing) removes the directory when the process ends; the
;; last forms remove it earlier, and the tests below require that.
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
;; The builds this suite's rows use: the control and the marked build, for
;; the kept refusal and the marker; not-sqlite and lacks-rest; and the three
;; the order rows use.
(define builds
  (decoy-builds
   (append '("control" "marked" "not-sqlite" "lacks-rest")
           (map lacks-build '("sqlite3_open_v2" "sqlite3_threadsafe" "sqlite3_initialize")))))

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
(define below-report (report below-version below-number "decoy-sourceid"))
(define (control-library so) (report-of so 'override control-report))
(define (below-library so) (report-of so 'override below-report))

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
                        (list (cons 'marker 'present)) (loaded-calls "control"))))

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

(test-end "library-loading-combined")

(exit (suite-exit-status runner))
