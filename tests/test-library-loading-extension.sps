#!r6rs
;;; One of the nine suites that load libsqlite3 end to end, through
;;; (chez-sqlite3 private native), tests/refusal-probe.sps and a decoy
;;; (ADR-0002, ADR-0003, ADR-0010, ADR-0013): this one holds the rows on
;;; the decoy, where it has sqlite3_load_extension and where it lacks it.
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
;;;   - the optional entry point, outside the pattern: a build without
;;;     sqlite3_load_extension loads, with no missing-api, and native records
;;;     it absent; the control records it there;
;;;   - the opt-in's check: on the build without it, an open that opts in is
;;;     refused by the named condition, after the list's own rules, the open
;;;     never tried; on the control it is tried, and so is
;;;     (enable-load-extension . #f) on the lacking build;
;;;   - load-extension! on the decoy: reached on the build
;;;     without sqlite3_load_extension and on the control, it refuses what is
;;;     no database at depth 1, and the log shows nothing of SQLite's called.
;;;
;;; Each build of tests/decoy-libsqlite3.c is compiled here with $CC (else
;;; cc), once, and a failed compile fails its rows, never skips them
;;; (ADR-0001). The decoy's versions are the floor and the one below it, read
;;; from packaging/floors.sexp (ADR-0008).
;;;
;;; Each child that reaches native code prints its counts, and every row
;;; requires them zero (ADR-0005). Each runs through
;;; gated-command, so under make test-memory the gate's own Valgrind runs it,
;;; with a log of its own that the gate reads. Every child here is the probe,
;;; which says whether it ran under Valgrind (memcheck's preload in
;;; /proc/self/maps), and a row requires yes exactly when the gate asked. A
;;; child that escaped the gate fails its row (ADR-0005).
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

(test-begin "library-loading-extension")

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
;; The control and a lacking build for each optional entry point.
(define builds
  (decoy-builds (cons "control" (map lacks-build optional-entries))))

(define (so-of build) (in-scratch (string-append build ".so")))

;; compiled : (Listof (Pairof String Any))
;; Every build, compiled once, in order.
(define compiled (compile-decoys so-of floor-values builds))

(define (compiled-status build) (decoy-status compiled build))

;; decoy-row : String (U String #f) (Listof String) String (String -> Expected) -> Void
;; (library-loading)'s decoy-row-in, on this suite's builds.
(define (decoy-row build switch args description expected)
  (decoy-row-in so-of compiled-status build switch args description expected))

(define control-report (report floor-version floor-number "decoy-sourceid"))

;; The optional entry point, outside the pattern (ADR-0002): a library without
;; sqlite3_load_extension, as Apple's is, loads, never missing-api, and native
;; records it absent, which an open that opts in reads. The control has it, and
;; its record says so: the row above is the entry point's doing, not the
;; probe's. Neither load calls it, so each log is a successful load's six calls.
(decoy-row "lacks-sqlite3_load_extension" #f '("--extension-loading" "yes")
  "a library without the optional sqlite3_load_extension loads, with no missing-api, and native records it absent, load-extension-available? #f"
  (lambda (so) (outcome 0 (append (loaded-lines so 'override control-report 2)
                                  (list (cons 'load-extension-available? #f)))
                        '() '() (loaded-calls "control"))))

(decoy-row "control" #f '("--extension-loading" "yes")
  "the control, which has sqlite3_load_extension, loads, and native records it there, load-extension-available? #t"
  (lambda (so) (outcome 0 (append (loaded-lines so 'override control-report 2)
                                  (list (cons 'load-extension-available? #t)))
                        '() '() (loaded-calls "control"))))

;; --- the opt-in's check ----------------------------------------------------------------
;; An open whose settings opt in, (enable-load-extension . #t), on a library
;; without sqlite3_load_extension raises &sqlite-extensions-unavailable from
;; the verb, the fifth of the refusals, after the list's own rules: in the
;; checks' critical section, caught there and raised after it, so a handler
;; of it runs at depth 1, every count zero there. The decoy's open always
;; fails, SQLITE_CANTOPEN, so its log can never show a db_config call: what a
;; row sees is whether the open was tried, sqlite3_open_v2 in the log, and
;; each row asserts the log whole. Each case runs through open-database,
;; then call-with-database, whose procedure is never called.

(define no-counts '((block . 0) (connection . 0) (statement . 0)))
(define (opt-in-refused who) (list 'extensions-unavailable who 'library-condition 'depth-1 no-counts))
(define (refused-as who irritants) (list 'assertion who irritants 'depth-1 no-counts))
(define (cantopen-from who) (list 'sqlite-error who 'cantopen 'depth-1 no-counts))

;; both : (Symbol -> Any) -> (List Any Any Symbol)
;; A case's result as the probe prints it, the same refusal from each verb,
;; the procedure never called.
(define (both refusal) (list (refusal 'open-database) (refusal 'call-with-database) 'not-called))

;; lacking-cases : (Listof (Pairof (Listof Any) (Symbol -> Any)))
;; Each case's arguments, the filename first, and its refusal from a verb:
;; the opt-in alone and among the other three, the fifth step; then the
;; list's own rules, the split's and the open's, each with the opt-in in the list,
;; which raise their own refusal first, wherever the opt-in stands.
(define lacking-cases
  (list
   (cons '(":memory:" ((enable-load-extension . #t))) opt-in-refused)
   (cons '(":memory:" ((defensive . #t) (enable-load-extension . #t) (dqs-dml . #f))) opt-in-refused)
   (cons '(":memory:" ((enable-load-extension . #t) (nosuch . 1)))
         (lambda (who) (refused-as who '(unknown-setting nosuch))))
   (cons '(":memory:" ((nosuch . 1) (enable-load-extension . #t)))
         (lambda (who) (refused-as who '(unknown-setting nosuch))))
   (cons '(":memory:" ((enable-load-extension . #t) (defensive . 1)))
         (lambda (who) (refused-as who '(setting-out-of-domain defensive 1))))
   (cons '(":memory:" ((enable-load-extension . #t) (enable-load-extension . #t)))
         (lambda (who) (refused-as who '(setting-given-twice enable-load-extension))))
   (cons '(":memory:" ((enable-load-extension . #t) 5))
         (lambda (who) (refused-as who '(not-an-association-list 5))))
   (cons '(":memory:" ((enable-load-extension . #t)) ((dqs-ddl . #t)))
         (lambda (who) (refused-as who '(second-settings-list))))
   (cons '(":memory:" bogus ((enable-load-extension . #t)))
         (lambda (who) (refused-as who '(unknown-option bogus))))
   (cons '(42 ((enable-load-extension . #t))) (lambda (who) (refused-as who '(not-a-string 42))))
   (cons '("file:x.db" ((enable-load-extension . #t)))
         (lambda (who) (refused-as who '(file-uri-without-uri-option (kind string)))))))

(decoy-row "lacks-sqlite3_load_extension" #f
  (list "--extension-loading" "yes" "--opens" (opens-arg (map car lacking-cases)))
  "an open that opts in, (enable-load-extension . #t), alone or among the other three, raises &sqlite-extensions-unavailable from open-database and from call-with-database, whose procedure is never called, a library condition, its handler at depth 1 and every count zero; each of the list's own rules, the split's and M2's, with the opt-in beside it, raises its own refusal first; and the log holds the load's entries alone, no sqlite3_open_v2"
  (lambda (so) (outcome 0 (append (loaded-lines so 'override control-report 2)
                                  (list (cons 'load-extension-available? #f)
                                        (cons 'opens (map (lambda (c) (both (cdr c))) lacking-cases))))
                        '() '() (loaded-calls "control"))))

;; The control, which has sqlite3_load_extension: the same opt-in is tried,
;; so the refusal above is the entry point's doing. And (enable-load-
;; extension . #f) on the lacking build is the same as leaving it out:
;; the open is tried. Each case opens twice, once by each verb, so the log
;; holds the open's two entries twice.
(decoy-row "control" #f
  (list "--extension-loading" "yes" "--opens" (opens-arg '((":memory:" ((enable-load-extension . #t))))))
  "the control, with the entry point: the same open that opts in is tried by each verb, sqlite3_open_v2 in the log, and answers &sqlite-error cantopen, the decoy's, its handler at depth 1, every count zero, the procedure never called"
  (lambda (so) (outcome 0 (append (loaded-lines so 'override control-report 2)
                                  (list (cons 'load-extension-available? #t)
                                        (cons 'opens (list (both cantopen-from)))))
                        '() '() (append (loaded-calls "control") (open-calls) (open-calls)))))

(decoy-row "lacks-sqlite3_load_extension" #f
  (list "--extension-loading" "yes" "--opens" (opens-arg '((":memory:" ((enable-load-extension . #f))))))
  "(enable-load-extension . #f) on the lacking build is the same as leaving it out (Q15): the open is tried by each verb, sqlite3_open_v2 in the log, and answers &sqlite-error cantopen, the procedure never called"
  (lambda (so) (outcome 0 (append (loaded-lines so 'override control-report 2)
                                  (list (cons 'load-extension-available? #f)
                                        (cons 'opens (list (both cantopen-from)))))
                        '() '() (append (loaded-calls "control") (open-calls) (open-calls)))))

;; --- load-extension! on the decoy -------------------------------------------------------
;; The decoy's open always fails, so no connection of it reaches a load:
;; what a row sees is the verb itself, where the library lacks
;; sqlite3_load_extension and where it has it. On both, load-extension! is
;; reached, its library loading where native binds no load, and its first
;; check refuses what is no database, whatever the arguments after it, an
;; assertion violation from the verb, raised after its section, its handler
;; at depth 1, every count zero; and the log holds the load's entries
;; alone, so nothing of SQLite's is called, sqlite3_load_extension least of
;; all where the build has it.

(define load-cases
  '((nope "/x/ext.so")
    (nope "/x/ext.so" "chez_named_init")
    (42 "ext.so")
    (#f 42 42)))

(define (load-refused db) (list 'assertion 'load-extension! (list 'not-a-database db) 'depth-1 no-counts))

(decoy-row "lacks-sqlite3_load_extension" #f
  (list "--extension-loading" "yes" "--loads" (loads-arg load-cases))
  "load-extension! on a library without sqlite3_load_extension: reached, its library loading though native binds no load, it refuses what is no database, for each form, from load-extension!, its handler at depth 1 and every count zero; the log holds the load's entries alone"
  (lambda (so) (outcome 0 (append (loaded-lines so 'override control-report 2)
                                  (list (cons 'load-extension-available? #f)
                                        (cons 'loads (map (lambda (c) (load-refused (car c))) load-cases))))
                        '() '() (loaded-calls "control"))))

(decoy-row "control" #f
  (list "--extension-loading" "yes" "--loads" (loads-arg load-cases))
  "load-extension! on the control, which has sqlite3_load_extension: the same refusals, and the log holds the load's entries alone, no sqlite3_load_extension"
  (lambda (so) (outcome 0 (append (loaded-lines so 'override control-report 2)
                                  (list (cons 'load-extension-available? #t)
                                        (cons 'loads (map (lambda (c) (load-refused (car c))) load-cases))))
                        '() '() (loaded-calls "control"))))

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

(test-end "library-loading-extension")

(exit (suite-exit-status runner))
