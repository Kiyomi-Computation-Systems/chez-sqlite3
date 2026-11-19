# build-layout.py OLD-TESTS NEW-TESTS: writes the nine loading suites into
# NEW-TESTS from the three in OLD-TESTS (main's 34721b4), by moving their
# text. Every block moved is found by exact text, asserted to occur once.
import sys, os

old_dir, new_dir = sys.argv[1], sys.argv[2]
def read(name):
    return open(os.path.join(old_dir, name)).read()
REAL = read('test-library-loading-real.sps')
DEC = read('test-library-loading-decoys.sps')
MISS = read('test-library-loading-missing.sps')

def between(text, start, end, include_end=False):
    """The text from START (included) up to END (excluded, or included)."""
    assert text.count(start) == 1, ('start', start[:70], text.count(start))
    i = text.index(start)
    assert text.count(end, i) >= 1, ('end', end[:70])
    j = text.index(end, i)
    return text[i:j + (len(end) if include_end else 0)]

def once(text, old, new):
    assert text.count(old) == 1, ('once', old[:70], text.count(old))
    return text.replace(old, new)

# --- the shared parts --------------------------------------------------------------------

RUNNER = between(REAL, ';; SRFI-64 sets no exit status.', '(test-begin "library-loading-real")')
assert RUNNER == between(DEC, ';; SRFI-64 sets no exit status.', '(test-begin "library-loading-decoys")')
CHEZ_ROW = between(MISS, ';; The Makefile exports CHEZ,', ';; --- the scratch directory')
SCRATCH_DECOYS = between(MISS, ';; scratch : (U String #f)', '(define floor-values (read-floor-values))')
FLOORS = between(MISS, '(define floor-values (read-floor-values))', ';; --- the partition')
PROCESS_END = lambda name: (
    between(MISS, ';; --- this process', '(test-end "library-loading-missing")')
    + '(test-end "library-loading-%s")\n\n(exit (suite-exit-status runner))\n' % name)

def head(header, imports, name):
    return ('#!r6rs\n' + header + imports + RUNNER + '(test-begin "library-loading-%s")\n\n' % name
            + CHEZ_ROW + ';; --- the scratch directory and the floors ----------------------------------------------\n\n')

COMMON_TAIL = """;;; Each child that reaches native code prints its counts, and every row
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
"""

WHY = """;;; They were one suite until it passed 450 s under the memory gate on CI,
;;; three quarters of MEMORY_TIMEOUT, then three until -real took 264 s there,
;;; over half of it (ADR-0005, amended); now each runs at most 11 children,
;;; and (library-loading) holds what all nine use.
;;;
;;; Native loads libsqlite3 in its library body, once per process, and Chez
;;; runs that body before a program's own, so a refusal cannot be caught in
;;; this process, nor a second library tried in it. Every case therefore runs
;;; a probe in a fresh Chez, through `env`, and reads back what it printed,
;;; as data, whole: exit status, every line, and stderr.
;;;
"""

DECOY_IMPORTS = """(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
        (library-loading)
        (only (chezscheme) file-directory? foreign-entry?))

"""

# --- the four missing suites ----------------------------------------------------------------

PARTITION = between(MISS, ';; --- the partition', ';; --- decoys')
MISSING_DECOYS = between(MISS, ';; --- decoys', ';; --- this process')

PARTITION_NEW = PARTITION
PARTITION_NEW = once(PARTITION_NEW, """;; Each part makes the missing-api rows of one suite. Merged in native's
;; order, every-entry's, the parts are the required entry points exactly when
;; each is in one part, once, and each part keeps the order; the other two
;; suites hold the same row.""", """;; Each part makes the missing-api rows of one suite. Merged in native's
;; order, every-entry's, the parts are the required entry points exactly when
;; each is in one part, once, and each part keeps the order; the other three
;; missing suites hold the same row.""")
PARTITION_NEW = once(PARTITION_NEW,
    '"the three suites\' entry lists partition the required entry points',
    '"the four missing suites\' entry lists partition the required entry points')
PARTITION_NEW = once(PARTITION_NEW, """;; five that repeats (deal-pattern).""", """;; four that repeats (deal-pattern).""")
PARTITION_NEW = once(PARTITION_NEW, """;; The pattern, written out, so that it and the parts changed together, which
;; the rows above pass, still fail: three of every five entries to the missing
;; suite, which holds only missing-api rows, and one each to the decoys' and
;; the real suite, which hold about 20 children of their own (ADR-0005,
;; amended 2026-11-16).
(test-equal "the pattern deals positions 0, 2 and 4 of every five to the missing suite, 1 to the decoys' suite and 3 to the real suite"
  '("test-library-loading-missing.sps" "test-library-loading-decoys.sps"
    "test-library-loading-missing.sps" "test-library-loading-real.sps"
    "test-library-loading-missing.sps")
  deal-pattern)""", """;; The pattern, written out, so that it and the parts changed together, which
;; the rows above pass, still fail: one of every four entries to each missing
;; suite, which holds only missing-api rows, so that none runs more than 11
;; children (ADR-0005, amended in M4's closing review).
(test-equal "the pattern deals positions 0, 1, 2 and 3 of every four to the missing suites 1, 2, 3 and 4"
  '("test-library-loading-missing-1.sps" "test-library-loading-missing-2.sps"
    "test-library-loading-missing-3.sps" "test-library-loading-missing-4.sps")
  deal-pattern)""")

def missing_suite(k):
    name = 'missing-%d' % k
    header = """;;; One of the nine suites that load libsqlite3 end to end, through
;;; (chez-sqlite3 private native), tests/refusal-probe.sps and a decoy
;;; (ADR-0002, ADR-0003, ADR-0010, ADR-0013): this one, the %s of four,
;;; holds only missing-api rows, its part of the entry points.
""" % ['first', 'second', 'third', 'fourth'][k - 1] + WHY + """;;;   - decoys: tests/decoy-libsqlite3.c, compiled here with $CC (else cc)
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
""" + COMMON_TAIL
    p = PARTITION_NEW.replace('(list "test-library-loading-missing.sps" (map',
                              '(list "test-library-loading-%s.sps" (map' % name)
    assert p != PARTITION_NEW
    return (head(header, DECOY_IMPORTS, name) + SCRATCH_DECOYS + FLOORS + p + MISSING_DECOYS
            + PROCESS_END(name))

# --- -decoys: the switches --------------------------------------------------------------------

DEC_CC = between(DEC, ';; Every compile here, the decoys\', runs $CC\'s words.', ';; --- the scratch directory')
DEC_SCRATCH = between(DEC, ';; scratch : (U String #f)', ';; --- the entries, and the partition')
DEC_CONVENTIONS = between(DEC, ';; The lists are written out, and an entry dropped', ';; Each part makes the missing-api rows')
DEC_ENV = between(DEC, '(define (so-of build) (in-scratch (string-append build ".so")))', '(decoy-row "control" #f \'()\n  "the floor itself is accepted')
DEC_SWITCHES = between(DEC, '(decoy-row "control" #f \'()\n  "the floor itself is accepted', ';; This suite\'s part of the entry points, each left out')
DEC_COMBOS = between(DEC, '(decoy-row "lacks-rest" #f \'()', ';; --- this process')

def decoys_suite():
    name = 'decoys'
    header = """;;; One of the nine suites that load libsqlite3 end to end, through
;;; (chez-sqlite3 private native), tests/refusal-probe.sps and a decoy
;;; (ADR-0002, ADR-0003, ADR-0010, ADR-0013): this one holds the decoy's
;;; behaviours, one switch a row, on the control build.
;;; tests/test-library-loading-combined.sps holds a lacking build under a
;;; switch, and the kept refusal.
""" + WHY + """;;;   - decoys: tests/decoy-libsqlite3.c, compiled here with $CC (else cc),
;;;     the control alone, and run under one behaviour per row, chosen by
;;;     CHEZ_SQLITE3_DECOY. Each row asserts the refusal's reason and every
;;;     field (plan section 3.4), and the decoy's call log, whole. The log
;;;     holds the load's order by behaviour: the report's three, the floor,
;;;     threadsafe, initialize, then the rest, each refused before the next
;;;     runs. A failed compile fails its row, never skips it (ADR-0001). The
;;;     decoy's versions are the floor and the one below it, read from
;;;     packaging/floors.sexp (ADR-0008);
;;;   - the entry lists: the required, then the optional, are the convention
;;;     table's names; the missing suites deal the required ones.
;;;
""" + COMMON_TAIL
    imports = """(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
        (foreign-conventions)
        (libsqlite3-oracle)
        (library-loading)
        (only (chezscheme) file-directory? foreign-entry?))

"""
    builds = """;; --- decoys --------------------------------------------------------------------------

;; builds : (Listof (Pairof String (Listof String)))
;; The builds this suite's rows use: the control, under each switch.
(define builds (decoy-builds '("control")))

"""
    conventions = ';; --- the entries ----------------------------------------------------------------------\n\n' + DEC_CONVENTIONS
    env = DEC_ENV
    return (head(header, imports, name).replace(CHEZ_ROW, CHEZ_ROW + DEC_CC)
            + DEC_SCRATCH + conventions + builds + env + DEC_SWITCHES + PROCESS_END(name))

def combined_suite():
    name = 'combined'
    header = """;;; One of the nine suites that load libsqlite3 end to end, through
;;; (chez-sqlite3 private native), tests/refusal-probe.sps and a decoy
;;; (ADR-0002, ADR-0003, ADR-0010, ADR-0013): this one holds the decoy's
;;; builds combined with its behaviours: a build without the rest, one with
;;; no sqlite3_* function, the load's order, a lacking build under a switch
;;; that an earlier step refuses, and the kept refusal with the marker.
;;; tests/test-library-loading-decoys.sps holds each switch alone.
""" + WHY + """;;;   - decoys: tests/decoy-libsqlite3.c, compiled here with $CC (else cc)
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
""" + COMMON_TAIL
    builds = """;; --- decoys --------------------------------------------------------------------------

;; builds : (Listof (Pairof String (Listof String)))
;; The builds this suite's rows use: the control and the marked build, for
;; the kept refusal and the marker; not-sqlite and lacks-rest; and the three
;; the order rows use.
(define builds
  (decoy-builds
   (append '("control" "marked" "not-sqlite" "lacks-rest")
           (map lacks-build '("sqlite3_open_v2" "sqlite3_threadsafe" "sqlite3_initialize")))))

"""
    return (head(header, DECOY_IMPORTS, name) + SCRATCH_DECOYS + FLOORS + builds + DEC_ENV
            + DEC_COMBOS + PROCESS_END(name))

# --- -extension: M4's rows ---------------------------------------------------------------

REAL_OPTIONAL = between(REAL, ';; The optional entry point, outside the pattern (ADR-0002, amended', ';; --- the real libsqlite3')
REAL_ENV = between(REAL, '(define (so-of build) (in-scratch (string-append build ".so")))', ';; This suite\'s part of the entry points, each left out')

def extension_suite():
    name = 'extension'
    header = """;;; One of the nine suites that load libsqlite3 end to end, through
;;; (chez-sqlite3 private native), tests/refusal-probe.sps and a decoy
;;; (ADR-0002, ADR-0003, ADR-0010, ADR-0013): this one holds M4's rows on
;;; the decoy, where it has sqlite3_load_extension and where it lacks it.
""" + WHY + """;;;   - the optional entry point, outside the pattern (the M4 plan, section
;;;     4.6): a build without sqlite3_load_extension loads, with no
;;;     missing-api, and native records it absent; the control records it
;;;     there;
;;;   - the opt-in's check (M4 slice 3; the M4 plan, section 4.3): on the build
;;;     without it, an open that opts in is refused by the named condition,
;;;     after the list's own rules, the open never tried; on the control it is
;;;     tried, and so is (enable-load-extension . #f) on the lacking build;
;;;   - load-extension! on the decoy (M4 slice 4): reached on the build
;;;     without sqlite3_load_extension and on the control, it refuses what is
;;;     no database at depth 1, and the log shows nothing of SQLite's called.
;;;
;;; Each build of tests/decoy-libsqlite3.c is compiled here with $CC (else
;;; cc), once, and a failed compile fails its rows, never skips them
;;; (ADR-0001). The decoy's versions are the floor and the one below it, read
;;; from packaging/floors.sexp (ADR-0008).
;;;
""" + COMMON_TAIL
    builds = """;; --- decoys --------------------------------------------------------------------------

;; builds : (Listof (Pairof String (Listof String)))
;; The control and a lacking build for each optional entry point.
(define builds
  (decoy-builds (cons "control" (map lacks-build optional-entries))))

"""
    return (head(header, DECOY_IMPORTS, name) + SCRATCH_DECOYS + FLOORS + builds + REAL_ENV
            + REAL_OPTIONAL + PROCESS_END(name))

# --- -real and -preflight ---------------------------------------------------------------------

REAL_SCRATCH = between(REAL, ';; scratch : (U String #f)', '(define (make-directory path)')
REAL_REAL = between(REAL, ';; The probe, in this process\'s own environment:', ';; call-with-tmpdir : String')
REAL_TMPDIR = between(REAL, ';; call-with-tmpdir : String', ';; --- refusals no decoy reaches')
REAL_REFUSALS = between(REAL, ';; --- refusals no decoy reaches', ';; --- a raise that is not a refusal')
REAL_RAISING = between(REAL, ';; --- a raise that is not a refusal', ';; --- discovery, with the override unset')
REAL_DISCOVERY = between(REAL, ';; --- discovery, with the override unset', ';; --- make build\'s preflight')
REAL_PREFLIGHT_REAL = between(REAL, '(test-equal "preflight, the real libsqlite3: exit 0, with the C oracle\'s report, then its counts"', '(let* ((so (so-of "control"))')
REAL_ORACLE_RUNS = between(REAL, '(test-equal "every C oracle run ran under Valgrind exactly when the gate asked, and there were at least two"', ';; --- this process')
REAL_MESSAGE_RUNS = between(REAL, '(test-equal "every probe that read a refusal\'s message ran under Valgrind exactly when the gate asked, and there were at least two"', '(test-equal "every C oracle run')

WORLD_OLD = between(REAL_DISCOVERY, ';; platform : (U \'linux \'macos \'other)', ';; first-standard :')
WORLD_NEW = """;; platform : (U 'linux 'macos 'other)
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

"""

def real_suite():
    name = 'real'
    header = """;;; One of the nine suites that load libsqlite3 end to end, through
;;; (chez-sqlite3 private native), tests/refusal-probe.sps and tests/preflight.sps
;;; (ADR-0002, ADR-0003, ADR-0010, ADR-0013): this one holds the real
;;; libsqlite3, the refusals no decoy reaches, discovery, and make build's
;;; preflight on the real libsqlite3. tests/test-library-loading-preflight.sps
;;; holds preflight's other rows.
""" + WHY + """;;;   - the real libsqlite3: the one the probe loads in this environment,
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
;;; requires them zero (ADR-0005, decision 4). Each runs through
;;; gated-command, so under make test-memory the gate's own Valgrind runs it,
;;; with a log of its own that the gate reads. Every child says whether it ran
;;; under Valgrind, and a row requires yes exactly when the gate asked: the
;;; probe, and the C oracle, print a line saying so (memcheck's preload in
;;; /proc/self/maps); preflight prints none, so (library-loading)'s
;;; preflight reads the one new log in the gate's directory for it, and
;;; requires that log's Command: line to be preflight's own, whole. A child
;;; that escaped the gate fails its row (ADR-0005, amended).
;;;
;;; This process itself never loads libsqlite3, and requires as much at its
;;; end. Each expected value is one the code under test cannot produce by
;;; failing, and none is #f: SRFI-64 makes #f of a raise in the actual
;;; expression. Anything that can raise is computed under a guard with a
;;; sentinel. Effects run in order, through let*, named lets and for-each,
;;; never map (AGENTS.md).
"""
    imports = """(import (rnrs)
        (srfi :64)
        (chez-sqlite3-testing)
        (libsqlite3-oracle)
        (library-loading)
        (only (chezscheme) getenv putenv format format-condition? load-shared-object
              file-directory? foreign-entry? machine-type directory-list)
        (chez-sqlite3 private discovery))

"""
    scratch = once(REAL_SCRATCH, """;; A fresh directory for the decoys, the fake profile, the text file and the
;; empty HOME.""", """;; A fresh directory for the fake profile, the text file and the empty HOME.""")
    real = once(REAL_REAL, """(test-equal "the real libsqlite3 through the override: loaded, with the C oracle's report and threadsafe answer, whole"
  (loaded (or real-libsqlite3 "?") 'override (oracle-report real-oracle)
          (oracle-threadsafe real-oracle) #f)
  (probe (cons (override (or real-libsqlite3 "/the-probe-loaded-nothing")) (switch-args #f))))
""", """(test-equal "the real libsqlite3 through the override: loaded, with the C oracle's report and threadsafe answer, whole"
  (loaded (or real-libsqlite3 "?") 'override (oracle-report real-oracle)
          (oracle-threadsafe real-oracle) #f)
  (probe (cons (override (or real-libsqlite3 "/the-probe-loaded-nothing")) (switch-args #f))))

;; make build's preflight on the same file, through the override: what it
;; tells a person installing chez-sqlite3, all of it, the C oracle's report
;; (tests/test-library-loading-preflight.sps holds preflight's other rows).
""" + REAL_PREFLIGHT_REAL)
    discovery = once(REAL_DISCOVERY, WORLD_OLD, WORLD_NEW)
    tail = (';; --- every C oracle run said whether it ran under Valgrind --------------------------\n'
            ';; The C oracle\'s answers carry the line among other things.\n\n' + REAL_ORACLE_RUNS)
    return ('#!r6rs\n' + header + imports + RUNNER + '(test-begin "library-loading-real")\n\n' + CHEZ_ROW
            + ';; --- the scratch directory ------------------------------------------------------------\n\n'
            + scratch + ';; --- the real libsqlite3 ---------------------------------------------------------------\n\n'
            + real + REAL_TMPDIR + REAL_REFUSALS + discovery + tail + PROCESS_END(name))

PRE_BODY = between(REAL, ';; --- make build\'s preflight', ';; --- every child said whether it ran under Valgrind')

def preflight_suite():
    name = 'preflight'
    header = """;;; One of the nine suites that load libsqlite3 end to end, through
;;; (chez-sqlite3 private native), tests/refusal-probe.sps and tests/preflight.sps
;;; (ADR-0002, ADR-0003, ADR-0010, ADR-0013): this one holds make build's
;;; preflight, and a raise that is not a refusal, through the probe and
;;; through preflight. tests/test-library-loading-real.sps holds preflight on
;;; the real libsqlite3.
""" + WHY + """;;;   - make build's preflight: its exit status and its output, whole, on
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
"""
    imports = DECOY_IMPORTS
    scratch = once(SCRATCH_DECOYS, ';; A fresh directory for the decoys.', ';; A fresh directory for the decoy and the empty HOME.')
    builds = """;; --- decoys --------------------------------------------------------------------------

;; builds : (Listof (Pairof String (Listof String)))
;; The control, for preflight's rows on a decoy.
(define builds (decoy-builds '("control")))

(define (so-of build) (in-scratch (string-append build ".so")))

;; compiled : (Listof (Pairof String Any))
;; Every build, compiled once, in order.
(define compiled (compile-decoys so-of floor-values builds))

(define (compiled-status build) (decoy-status compiled build))

;; decoy-env : String (U String #f) -> (Listof String)
(define (decoy-env build switch)
  (cons (override (so-of build)) (switch-args switch)))

(define control-report (report floor-version floor-number "decoy-sourceid"))

"""
    world = """;; --- the world -------------------------------------------------------------------------
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

"""
    body = PRE_BODY
    helpers = between(body, ';; The gate\'s directory of child logs,', ';; message-runs : (Listof Pair)')
    body = once(body, helpers, '')
    body = once(body, between(body, '(define counts-line', '(let ((so (so-of "control")))'), '')
    body = once(body, REAL_PREFLIGHT_REAL, '')
    body = once(body, """;; --- make build's preflight ----------------------------------------------------------------
;; Its output is what make build tells a person installing chez-sqlite3, so
;; these rows assert all of it. Its remedy line is the refusal's message,
;; which no test writes as text (ADR-0002, ADR-0013): it must equal what the
;; probe read for the same refusal, in a process of its own.
""", """;; --- make build's preflight ----------------------------------------------------------------
;; Its output is what make build tells a person installing chez-sqlite3, so
;; these rows assert all of it. Its remedy line is the refusal's message,
;; which no test writes as text (ADR-0002, ADR-0013): it must equal what the
;; probe read for the same refusal, in a process of its own. Preflight
;; itself, its text and its gate check are (library-loading)'s.
""")
    # field is (library-loading)'s now
    tail = (';; --- every probe that read a message said whether it ran under Valgrind --------------\n'
            ';; The message probes\' answers carry the line among other things.\n\n' + REAL_MESSAGE_RUNS)
    return (head(header, imports, name) + scratch + FLOORS + builds + world + REAL_RAISING + body
            + tail + PROCESS_END(name))

out = {
    'test-library-loading-missing-1.sps': missing_suite(1),
    'test-library-loading-missing-2.sps': missing_suite(2),
    'test-library-loading-missing-3.sps': missing_suite(3),
    'test-library-loading-missing-4.sps': missing_suite(4),
    'test-library-loading-decoys.sps': decoys_suite(),
    'test-library-loading-combined.sps': combined_suite(),
    'test-library-loading-extension.sps': extension_suite(),
    'test-library-loading-real.sps': real_suite(),
    'test-library-loading-preflight.sps': preflight_suite(),
}
for name, text in out.items():
    open(os.path.join(new_dir, name), 'w').write(text)
    print(name, text.count('\n'))
