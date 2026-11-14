# Global constraints

The hard rules from the decision records. Every task brief is bound by them. Each rule cites the
record it comes from, and where a rule and its record disagree, the record wins. A rule from a
Proposed record is marked *(provisional)* until that record is accepted.

## Platforms and versions

- **Linux and macOS, on amd64 and arm64. Never Windows.** No Windows code paths, no Windows CI,
  and no abstraction kept only so Windows could come later (ADR-0004).
- **CI is Linux only.** macOS is checked by hand on the maintainer's Mac, and any variadic binding
  is run there whenever it changes (ADR-0004, ADR-0001).
- **SQLite and a threaded Chez, each at its floor in `packaging/floors.sexp`.**
  `(chez-sqlite3 private require-threaded)` refuses any other Chez by name at import, and every
  library under `src/` imports it first (ADR-0003, ADR-0001 amended).
- **The floors are written once, in `packaging/floors.sexp`.** README.org's Requirements is held
  to it by `make check-floors`, which also refuses any workflow line that writes a floor: its
  dotted text, and SQLite's version number and amalgamation number as whole runs of digits. Other
  spellings pass, and `check-floors` reads only `.github/workflows` (ADR-0008, amended). CI reads floors through
  `scripts/ci/floor.sh` and writes none. The code is held to the file by behaviour: the floor
  itself is accepted and the version below it refused (ADR-0008, amended). No other house
  document restates a floor.

## Native code

- **No C shim; nothing is compiled at install.** Every binding is a `foreign-procedure` in a
  `(chez-sqlite3 private …)` library (ADR-0001).
- **Constants and signatures are checked against `sqlite3.h`** by a C program compiled at test
  time. A missing header or compiler fails the suite, never skips it. The compiler is a test
  oracle, never an install dependency (ADR-0001).
- **`sqlite3_db_config` is bound with `(__varargs_after 2)`; `sqlite3_config` is never bound**
  (ADR-0001, brief §2.8).
- **`SQLITE_TRANSIENT` and `SQLITE_STATIC` are pointer-width integers,** −1 and 0 (ADR-0001).
- **v1 binds only entry points that exist at the floor.** A newer one is optional: checked with
  `foreign-entry?`, its absence reported where it is used (ADR-0003, ADR-0002).
- **No binding takes a Scheme object:** never Chez's `string`, `utf-8`, `u8*` or `scheme-object`
  types, nor a bytevector. Every string passed to libsqlite3 is copied, UTF-8 and NUL-terminated,
  into a counted foreign block freed on every path, and one holding U+0000 is refused before
  anything is allocated. Out-parameters are counted blocks too. A returned string is read by our
  code from a `uptr` (ADR-0011).
- **The calls that can block are `__collect_safe`:** `sqlite3_open_v2` and `sqlite3_close` from
  M1, `sqlite3_prepare_v3` and `sqlite3_step` from M2. Every binding has a row in the convention
  table, which the convention suite holds every `foreign-procedure` form to (ADR-0011).

## Loading libsqlite3

- **`CHEZ_SQLITE3_LIBRARY`, if set, is an absolute path, loaded as given,** with no search and no
  fallback. Anything else is `invalid-override` (ADR-0002).
- **Otherwise one candidate list, chosen by world.** A Guix world never yields a standard
  directory, and an FHS world never yields a Guix profile. macOS has one candidate,
  `/usr/lib/libsqlite3.dylib`. Discovery is a pure function of its inputs (ADR-0002).
- **One load, then verify, never fall through.** The floor is checked first, then
  `sqlite3_threadsafe`: a single-thread build is refused. Every other required entry point is then
  bound eagerly in the same library body. The first failure is kept for the life of the process
  (ADR-0002, amended; ADR-0010).
- **Refusals carry a reason symbol:** `invalid-override`, `not-found`, `load-failed`,
  `below-floor`, `not-threadsafe` or `missing-api`. Tests assert the symbol, never the text
  (ADR-0002, amended).
- **Nothing reads `LD_LIBRARY_PATH` or `DYLD_*` on the library's behalf** (ADR-0002).

## Connections, threads and conditions

- **A connection belongs to the thread that opened it.** Every verb checks, in order, that its
  argument is a database, that it runs on the owning thread, and that the connection is open,
  before anything reaches C. The wrong thread raises `&sqlite-wrong-thread`, and a closed
  connection `&sqlite-closed`. M3's `sqlite3_interrupt` is the one exception (ADR-0010,
  ADR-0012).
- **Connections open with `SQLITE_OPEN_FULLMUTEX`,** or `NOMUTEX` when given `'no-mutex`, and
  always with `SQLITE_OPEN_EXRESCODE` (ADR-0010, ADR-0012).
- **Closing is explicit: no guardians, no finalizers.** Closing finalizes tracked statements,
  checks `sqlite3_next_stmt`, then calls `sqlite3_close`, never `sqlite3_close_v2`. A failed open
  closes its handle before it raises. A second close does nothing (ADR-0012).
- **A handle is an integer in an opaque, sealed `database` record,** with a private accessor. No
  ftype pointer holds one (ADR-0012).
- **`open-database`'s options are symbols, and the flags SQLite gets are always legal.** A
  contradiction, an option given twice, or an unknown option is an assertion violation before
  anything is allocated (ADR-0012).
- **Every condition is a `&chez-sqlite3-error`,** a fieldless root under `&error`. SQLite's codes
  are symbols on `&sqlite-error`. A caller's mistake is an assertion violation that names a string
  by its kind, never its text. Tests assert the type, the reason or code and the fields, never a
  message (ADR-0013).

## Layout and names

- **The public library is `(chez-sqlite3)`.** Internals live under `(chez-sqlite3 private …)`, and
  nothing public imports them except `(chez-sqlite3)` itself. The test helpers are
  `(chez-sqlite3-testing)` (ADR-0009). `check-seam` reads `src/` alone: tests and the test
  helpers may import private libraries (ADR-0009, amended).
- **No Thunderchez code.** Its API ideas may be taken, never its text. It is not vendored, fetched
  or imported (ADR-0009).
- **Each defect the assessment lists becomes a test,** watched failing against a planted copy of
  that defect (ADR-0009).

## Environment and tests

- **Builds and tests run through `scripts/guix-env` on a Guix host.** The container has no network
  but loopback, and no git. It exports `CHEZ`, `CC` and `CHEZ_SQLITE3_LIBRARY`, and sets no
  `LD_LIBRARY_PATH` (ADR-0006).
- **Network and git work runs on the host:** submodules, `make check-pins`, downloads (ADR-0006,
  ADR-0007).
- **SRFI-64 comes from `vendor/chez-srfi` at `7879b52`,** pinned in `Akku.lock`. `make deps`
  never fetches (ADR-0007).
- **Every suite ends with `(exit (suite-exit-status runner))`,** and exits early only with
  `(exit 1)`. `make check-suites` checks it (ADR-0007).
- **`make test` runs every suite under `timeout`, even after a failure,** and fails on any failure,
  hang, or empty glob. `make check-test-fails` proves each of those (ADR-0007).
- **Probes print `(reason . symbol)`, and tests assert the symbol** (ADR-0007).

## Memory and the test harness

- **The gate has four parts:** Valgrind, our counters, `sqlite3_next_stmt` and
  `sqlite3_memory_used`. The last two join in M1: `sqlite3_next_stmt` in `close-database!`, and
  `sqlite3_memory_used` only in a process that loaded libsqlite3 (ADR-0005, amended).
- **The memory check has a positive control.** It must see the count rise while a connection is
  open. Where it never rises, as on Apple's `DEFAULT_MEMSTATUS=0` build, the suite names the
  check as unavailable and passes on its other checks, never silently (ADR-0005, amended).
- **Valgrind's evidence comes from its log alone.** `timeout` wraps Valgrind and never sits between
  it and Chez, and `CHEZ` is the real binary. There are no suppressions without a recorded run
  that needs one (ADR-0005).
- **`make check-memory-gate` must see the gate fail** on a planted leak and a planted overrun, and
  runs before `make test-memory` in CI (ADR-0005).
- **Counts of blocks, connections and statements must be zero when a suite exits.** There is no
  reset, and a count below zero raises (ADR-0005).
- **CI's workflow has one shape, which `make check-ci` holds and `make test` runs:** its triggers,
  three jobs and their keys; each check as a step's whole run line; no `if:` but the cache's own;
  no line naming a variable that steers a check; no key spelled so a text check would miss it. It
  holds against a mistaken edit, not a deliberate one: a step can compute any name. A change to
  the workflow changes `tests/check-ci.sh` with it (ADR-0005, amended).
- **`make check-nothreads` refuses every library under `src/` by name** on CI's `--nothreads`
  Chez (ADR-0001, amended).
- **Valgrind follows no child process.** A suite's child that reaches native code runs under the
  gate itself, with its own log, or the gate follows children and reads every process's log
  (ADR-0005, amended).
- **`make test-memory` takes `MEMORY_SUITES` from make's command line only,** and refuses one
  from the environment (ADR-0005, amended).
