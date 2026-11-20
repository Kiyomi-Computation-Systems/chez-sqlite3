#!r6rs
;;; One of the nine suites that load libsqlite3 end to end, through
;;; (chez-sqlite3 private native), tests/refusal-probe.sps and a decoy
;;; (ADR-0002, ADR-0003, ADR-0010, ADR-0013): this one holds the decoy's
;;; behaviours, one switch a row, on the control build.
;;; tests/test-library-loading-combined.sps holds a lacking build under a
;;; switch, and the kept refusal.
;;;
;;; Under the memory gate each child runs under a Valgrind of its own, so
;;; the rows are split among nine suites, each running at most 11 children,
;;; to keep each well under MEMORY_TIMEOUT (ADR-0005); (library-loading)
;;; holds what all nine use.
;;;
;;; Native loads libsqlite3 in its library body, once per process, and Chez
;;; runs that body before a program's own, so a refusal cannot be caught in
;;; this process, nor a second library tried in it. Every case therefore runs
;;; a probe in a fresh Chez, through `env`, and reads back what it printed,
;;; as data, whole: exit status, every line, and stderr.
;;;
;;;   - decoys: tests/decoy-libsqlite3.c, compiled here with $CC (else cc),
;;;     the control alone, and run under one behaviour per row, chosen by
;;;     CHEZ_SQLITE3_DECOY. Each row asserts the refusal's reason and every
;;;     field, and the decoy's call log, whole. The log holds the load's order
;;;     by behaviour: the report's three, the floor, threadsafe, initialize,
;;;     then the rest, each refused before the next runs. A failed compile
;;;     fails its row, never skips it (ADR-0001). The decoy's versions are the
;;;     floor and the one below it, read from packaging/floors.sexp
;;;     (ADR-0008);
;;;   - the entry lists: the required, then the optional, are the convention
;;;     table's names; the missing suites deal the required ones.
;;;
;;; Each child that reaches native code prints its counts, and every row
;;; requires them zero (ADR-0005). Each runs through gated-command, so under
;;; make test-memory the gate's own Valgrind runs it, with a log of its own
;;; that the gate reads. Every child here is the probe, which says whether it
;;; ran under Valgrind (memcheck's preload in /proc/self/maps), and a row
;;; requires yes exactly when the gate asked. A child that escaped the gate
;;; fails its row (ADR-0005).
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
        (foreign-conventions)
        (libsqlite3-oracle)
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

(test-begin "library-loading-decoys")

;; The Makefile exports CHEZ, so this suite spawns the Chez that runs it.
;; Without it nothing below can run: fail, never skip.
(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (set? chez) 'set 'unset))

(unless (set? chez)
  (exit 1))

;; Every compile here, the decoys', runs $CC's words.
(test-equal "CC is cut at whitespace, so CC='ccache gcc' runs ccache, with gcc as its argument"
  '(("ccache" "gcc") ("gcc" "-m64") ("cc") ("cc"))
  (let* ((a (c-compiler (lambda (name) (and (string=? name "CC") " ccache\tgcc "))))
         (b (c-compiler (lambda (name) (and (string=? name "CC") "gcc -m64"))))
         (c (c-compiler (lambda (name) (and (string=? name "CC") "  "))))
         (d (c-compiler (lambda (name) #f))))
    (list a b c d)))

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

;; --- the entries ----------------------------------------------------------------------

;; The lists are written out, and an entry dropped from them takes its
;; build and its missing-api row with it. The convention table holds the
;; bindings to native, in ADR-0002's order (test-conventions), so the
;; required list, then the optional one, is held to the table's names, whole
;; and in order, as test-conventions holds it too.
(test-equal "the decoy's entry lists, every-entry then optional-entries, are the convention table's names, whole and in order"
  (map row-name conventions-table)
  (append every-entry optional-entries))

;; --- decoys --------------------------------------------------------------------------

;; builds : (Listof (Pairof String (Listof String)))
;; The builds this suite's rows use: the control, under each switch.
(define builds (decoy-builds '("control")))

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
(define below-report (report below-version below-number "decoy-sourceid"))
(define (control-library so) (report-of so 'override control-report))
(define (below-library so) (report-of so 'override below-report))

(decoy-row "control" #f '()
  "the floor itself is accepted: the report's five fields, threadsafe 2, and the load's six calls in order"
  (lambda (so) (loaded so 'override control-report 2 (loaded-calls "control"))))

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
                       (loaded-calls "sourceid-utf8"))))

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
                               (list threadsafe-call initialize-call memory-used-call)))))

(decoy-row "control" "below-floorX" '()
  "a value that only begins with a switch, below-floorX, is no switch: the control, and the log names it"
  (lambda (so) (loaded so 'override control-report 2
                       (append (list "decoy(?below-floorX)") the-report-three
                               (list threadsafe-call initialize-call memory-used-call)))))

(decoy-row "control" "" '()
  "an empty value is no switch either"
  (lambda (so) (loaded so 'override control-report 2
                       (append (list "decoy(?)") the-report-three
                               (list threadsafe-call initialize-call memory-used-call)))))

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

(test-end "library-loading-decoys")

(exit (suite-exit-status runner))
