#!r6rs
;;; One of the nine suites that load libsqlite3 end to end, through
;;; (chez-sqlite3 private native), tests/refusal-probe.sps and a decoy
;;; (ADR-0002, ADR-0003, ADR-0010, ADR-0013): this one, the second of four,
;;; holds only missing-api rows, its part of the entry points.
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
;;;     once per build, each export of this suite's part left out one at a
;;;     time. Each row asserts the refusal's reason and every field (plan
;;;     section 3.4), and the decoy's call log, whole. A failed compile fails
;;;     its row, never skips it (ADR-0001). The decoy's versions are the floor
;;;     and the one below it, read from packaging/floors.sexp (ADR-0008);
;;;   - the partition: each entry point's missing-api row runs in exactly one
;;;     of the four missing suites, this one's part found by its file's name,
;;;     and four rows, here and in each other missing suite, hold the parts,
;;;     the pattern that deals them and the suites.
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

(test-begin "library-loading-missing-2")

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

;; --- the partition ----------------------------------------------------------------------

;; Each part makes the missing-api rows of one suite. Merged in native's
;; order, every-entry's, the parts are the required entry points exactly when
;; each is in one part, once, and each part keeps the order; the other three
;; missing suites hold the same row. The optional entry points, which a
;; library may lack and still load, follow every-entry in the convention
;; table, outside the partition (the M4 plan, section 4.6).
(test-equal "the four missing suites' entry lists partition the required entry points, every-entry: merged in its order, they are its names, each once"
  every-entry
  (merge-halves every-entry (map cdr decoy-parts)))

;; The partition is dealt: native's order, by position from 0, by a pattern of
;; four that repeats (deal-pattern). The row above holds only that the parts
;; partition the table, each in its order, so two entries swapped between
;; parts, or one moved to another, passes it. Each part is exactly what the
;; pattern deals its suite, and every name the pattern holds is a part.
(test-equal "each suite's part is the entries the pattern deals it, by position in every-entry from 0, and the pattern names only parts"
  (list decoy-parts 'all)
  (list (map (lambda (part)
               (cons (car part) (entries-dealt every-entry deal-pattern (car part))))
             decoy-parts)
        (if (for-all (lambda (name) (assoc name decoy-parts)) deal-pattern) 'all deal-pattern)))

;; The pattern, written out, so that it and the parts changed together, which
;; the rows above pass, still fail: one of every four entries to each missing
;; suite, which holds only missing-api rows, so that none runs more than 11
;; children (ADR-0005, amended).
(test-equal "the pattern deals positions 0, 1, 2 and 3 of every four to the missing suites 1, 2, 3 and 4"
  '("test-library-loading-missing-1.sps" "test-library-loading-missing-2.sps"
    "test-library-loading-missing-3.sps" "test-library-loading-missing-4.sps")
  deal-pattern)

;; this-part : (U (Pairof String (Listof String)) #f)
;; This suite's part, by its own file's name. The row below writes the name
;; out, so a suite copied from another, or a lookup that answers another
;; part, fails it.
(define this-part (suite-part (command-line)))

(test-equal "this suite runs its own part of the partition, found by its file's name, and each suite the partition names is a file in tests/"
  (list "test-library-loading-missing-2.sps" (map (lambda (part) (cons (car part) 'present)) decoy-parts))
  (list (if this-part (car this-part) (list 'unlisted (command-line)))
        (map (lambda (part)
               (cons (car part) (if (file-exists? (string-append "tests/" (car part))) 'present 'absent)))
             decoy-parts)))

(define this-entries (if this-part (cdr this-part) '()))

;; --- decoys --------------------------------------------------------------------------

;; builds : (Listof (Pairof String (Listof String)))
;; A lacking build for each entry of this suite's part.
(define builds
  (decoy-builds (map lacks-build this-entries)))

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
(define (control-library so) (report-of so 'override control-report))

;; This suite's part of the entry points, each left out, one at a time
;; ((library-loading)'s missing-api-rows).
(missing-api-rows decoy-row control-library this-entries)

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

(test-end "library-loading-missing-2")

(exit (suite-exit-status runner))
