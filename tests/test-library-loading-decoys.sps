#!r6rs
;;; One of the three suites that load libsqlite3 end to end, through (chez-sqlite3
;;; private native), tests/refusal-probe.sps and a decoy (ADR-0002, ADR-0003,
;;; ADR-0010, ADR-0013): this one holds the decoy's behaviours and its part of
;;; the missing-api rows. tests/test-library-loading-real.sps holds the real
;;; libsqlite3, the refusals no decoy reaches, discovery, make build's
;;; preflight, and its own part; tests/test-library-loading-missing.sps holds
;;; only missing-api rows, the largest part. They were one suite until it
;;; passed 450 s under the memory gate on CI, three quarters of
;;; MEMORY_TIMEOUT (ADR-0005, amended); (library-loading) holds what all
;;; three use.
;;;
;;; Native loads libsqlite3 in its library body, once per process, and Chez
;;; runs that body before a program's own, so a refusal cannot be caught in
;;; this process, nor a second library tried in it. Every case therefore runs
;;; tests/refusal-probe.sps in a fresh Chez, through `env`, and reads back
;;; what it printed, as data, whole: exit status, every line, and stderr.
;;;
;;;   - decoys: tests/decoy-libsqlite3.c, compiled here with $CC (else cc)
;;;     once per build, each export of this suite's part left out one at a
;;;     time, and run under one behaviour per row, chosen by
;;;     CHEZ_SQLITE3_DECOY. Each row asserts the refusal's reason and every
;;;     field (plan section 3.4), and the decoy's call log, whole. The log
;;;     holds the load's order by behaviour: the report's three, the floor,
;;;     threadsafe, initialize, then the rest, each refused before the next
;;;     runs. A lacking build run under a behaviour that an earlier step
;;;     refuses holds that step's place: the earlier refusal must win. A
;;;     failed compile fails its row, never skips it (ADR-0001). The decoy's
;;;     versions are the floor and the one below it, read from
;;;     packaging/floors.sexp (ADR-0008);
;;;   - the load runs once: the probe references loaded-libsqlite3 three
;;;     times, and the later two must answer what the first did, with no
;;;     second load in the call log and no second library in the process;
;;;   - the partition: each entry point's missing-api row runs in exactly one
;;;     of the three suites, this one's part found by its file's name, and
;;;     three rows, here and in each other suite, hold the parts, the pattern
;;;     that deals them and the suites.
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

;; --- the entries, and the partition ----------------------------------------------------

;; The lists are written out, and an entry dropped from them takes its
;; build and its missing-api row with it. The convention table holds the
;; bindings to native, in ADR-0002's order (test-conventions), so the list
;; is held to the table's names, whole and in order.
(test-equal "the decoy's entry list is the convention table's names, whole and in order"
  (map row-name conventions-table)
  every-entry)

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
  (list "test-library-loading-decoys.sps" (map (lambda (part) (cons (car part) 'present)) decoy-parts))
  (list (if this-part (car this-part) (list 'unlisted (command-line)))
        (map (lambda (part)
               (cons (car part) (if (file-exists? (string-append "tests/" (car part))) 'present 'absent)))
             decoy-parts)))

(define this-entries (if this-part (cdr this-part) '()))

;; --- decoys --------------------------------------------------------------------------

;; builds : (Listof (Pairof String (Listof String)))
;; The builds this suite's rows use: the behaviours' four, a lacking build for
;; each entry of its part, and the three the order rows use, whatever part
;; they are in.
(define builds
  (decoy-builds
   (append '("control" "marked" "not-sqlite" "lacks-rest")
           (map lacks-build
                (append this-entries '("sqlite3_open_v2" "sqlite3_threadsafe" "sqlite3_initialize"))))))

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

;; This suite's part of the entry points, each left out, one at a time
;; ((library-loading)'s missing-api-rows).
(missing-api-rows decoy-row control-library this-entries)

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

(test-end "library-loading-decoys")

(exit (suite-exit-status runner))
