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
  to it by `make check-floors`, which also refuses any line, in a workflow or in a file under
  `scripts/ci/`, that writes a floor: its dotted text, and SQLite's version number and
  amalgamation number as whole runs of digits. Other spellings pass, and `check-floors` reads only
  `.github/workflows` and `scripts/ci` (ADR-0008, amended). CI reads floors through
  `scripts/ci/floor.sh` and writes none: its pins are keyed by role, never by version. The code is held to the file by behaviour: the floor
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
- **`SQLITE_TRANSIENT` and `SQLITE_STATIC` are pointer-width integers,** −1 and 0 as C writes
  them. As a `uptr`, −1 is all ones, and native computes it from the pointer's size (ADR-0001).
- **Every value a verb passes to C is checked to fit its C type before the critical section that
  makes the call,** by a pure check. Chez's `int` takes −2³¹ to 2³²−1, hands 2³¹ and above to C as
  negative numbers, and raises beyond, from inside the section. So prepare refuses SQL longer than
  2³¹−1 bytes, and indexes are checked against their counts (ADR-0011, amended).
- **v1 binds only entry points that exist at the floor.** A newer one is optional: checked with
  `foreign-entry?`, its absence reported where it is used (ADR-0003, ADR-0002).
  `sqlite3_load_extension` is optional too, since a build can omit it, as Apple's does, and
  `sqlite3_enable_load_extension` is never bound (ADR-0002, amended).
- **No binding takes a Scheme object:** never Chez's `string`, `utf-8`, `u8*` or `scheme-object`
  types, nor a bytevector. Every string passed to libsqlite3 is copied, UTF-8 and NUL-terminated,
  into a counted foreign block freed on every path, and one holding U+0000 is refused before
  anything is allocated. Out-parameters are counted blocks too. A returned string is read by our
  code from a `uptr` (ADR-0011).
  - **M2 narrows the U+0000 refusal to the strings SQLite reads to a NUL:** a filename, SQL text, a
    parameter name. Bound text is counted, and keeps its U+0000 (ADR-0011 amended).
- **The calls that can block are `__collect_safe`:** `sqlite3_open_v2` and `sqlite3_close` from
  M1, `sqlite3_prepare_v3` and `sqlite3_step` from M2. Every binding has a row in the convention
  table, and from M1 slice 2 the convention suite holds every `foreign-procedure` form to it
  (ADR-0011).
  - **`sqlite3_reset` and `sqlite3_finalize` join them in M2,** measured waiting in the busy
    handler, and M2's four are held by behaviour too (ADR-0011 amended).
- **Nothing raises inside `critical-section`, or inside a critical `dynamic-wind` thunk,** in
  `src/` or in the testing library. Code there answers data; a raise from a call made there is
  caught in the section and raised again after it, as the same object.
  - A `with-exception-handler` handler of a raise inside a section runs with interrupts disabled.
    There an engine never expires, and another thread's collection waits.
  - `call-with-open-handle`'s procedure answers data, and what it raises can't be resumed.
  - A C string that a caller under engines uses lives, whole, in one section: the open,
    `sqlite-compile-option?`, and M2's prepare.
  - A row per site holds the rule (ADR-0012 and ADR-0011, amended by M1's closing review).

## Loading libsqlite3

- **`CHEZ_SQLITE3_LIBRARY`, if set, is an absolute path, loaded as given,** with no search and no
  fallback. Anything else is `invalid-override` (ADR-0002).
- **Otherwise one candidate list, chosen by world.** A Guix world never yields a standard
  directory, and an FHS world never yields a Guix profile. macOS has one candidate,
  `/usr/lib/libsqlite3.dylib`. Discovery is a pure function of its inputs (ADR-0002).
- **One load, then verify, never fall through.** The report's three entry points are bound first
  (`sqlite3_libversion_number`, `sqlite3_libversion`, `sqlite3_sourceid`). Then the
  floor is checked, then `sqlite3_threadsafe`: a single-thread build is refused. Then
  `sqlite3_initialize` is called once. Every other required entry point is then bound eagerly in
  the same library body. The first failure is kept
  for the life of the process (ADR-0002, amended; ADR-0010).
- **Refusals carry a reason symbol:** `invalid-override`, `not-found`, `load-failed`,
  `below-floor`, `not-threadsafe` or `missing-api`. Tests assert the symbol, never the text
  (ADR-0002, amended).
- **Nothing reads `LD_LIBRARY_PATH` or `DYLD_*` on the library's behalf** (ADR-0002).

## Connections, threads and conditions

- **A connection belongs to the thread that opened it.** Every verb checks, in order, that its
  argument is a database, that it runs on the owning thread, and that the connection is open,
  before anything reaches C. The wrong thread raises `&sqlite-wrong-thread`, and a closed
  connection `&sqlite-closed`. `interrupt-database!` is the one exception, and checks only that its
  argument is a database (ADR-0010 and ADR-0012, amended; ADR-0019).
- **Connections open with `SQLITE_OPEN_FULLMUTEX`,** or `NOMUTEX` when given `'no-mutex`, and
  always with `SQLITE_OPEN_EXRESCODE` (ADR-0010, ADR-0012).
- **Closing is explicit: no guardians, no finalizers.** Closing finalizes tracked statements,
  checks `sqlite3_next_stmt`, then calls `sqlite3_close`, never `sqlite3_close_v2`. A failed open
  closes its handle before it raises. A second close does nothing (ADR-0012).
- **A handle is an integer in an opaque, sealed `database` record,** with a private accessor. No
  ftype pointer holds one (ADR-0012).
- **A `file:` name without `'uri` is refused,** case-sensitively, as SQLite tests it (ADR-0012,
  amended; the maintainer's).
- **`(chez-sqlite3)` exports the maintainer's names and the conditions' predicates and accessors,
  and `test-public` holds the list whole** (ADR-0012, ADR-0013, amended).
- **`open-database`'s options are symbols, and the flags SQLite gets are always legal.** A
  contradiction, an option given twice, or an unknown option is an assertion violation before
  anything is allocated (ADR-0012).
- **Every library condition is a `&chez-sqlite3-error`,** a fieldless root under `&error` (the
  maintainer's). SQLite's codes are symbols on `&sqlite-error`. A caller's mistake is an assertion
  violation, not a library condition, and names a string by its kind, never its text. Tests assert
  the type, the reason or code and the fields, never a message (ADR-0013).

## Statements and values

- **A statement is an integer in an opaque, sealed record, and its connection holds it,
  strongly.** No guardians, no weak tracking (ADR-0014, ADR-0012 amended).
- **`close-database!` finalizes every statement it holds, checks `sqlite3_next_stmt`, calls
  `sqlite3_close`, and then raises the first failure a finalize reported;** a failed close keeps the
  connection open and counted (the maintainer's, R1). The statements are finalized oldest first,
  and a failed close raises its own failure (ADR-0014).
- **Every statement verb checks, in order, before anything reaches C:** a statement; on its
  connection's owning thread, else `&sqlite-wrong-thread`; not finalized, else `&sqlite-closed`;
  then its state. `finalize-statement!` makes the first two alone, and does nothing on a finalized
  statement (ADR-0014).
- **A statement's state lives in Scheme:** `ready`, `row`, `done`, `failed`, or finalized. Binding
  and `clear-bindings!` are allowed only in `ready`, column values only in `row`; `step!` on a done
  or failed statement is refused until `reset!`; every index is checked before C against a count
  read in the same critical section (ADR-0014).
- **SQL holding no statement, or more than one, is refused,** the tail checked by a scan in Scheme,
  never prepared, against SQLite's own tokenizer: whitespace runs (one of space, `\t`, `\n`, `\f`,
  `\r`, then any of those or `\v`), U+FEFF, comments and semicolons, agreeing with SQLite's
  prepare on every input; so is SQL holding U+0000 (ADR-0014 amended, ADR-0011 amended).
- **Reset and finalize raise a failure of their own,** and never repeat a failed step's. A finalize
  clears, untracks and counts the statement down whatever SQLite answers, then raises (ADR-0014).
- **A statement verb raises after its critical section, never inside it,** and reaches a
  connection's handle only through `call-with-open-handle`, its one accessor (ADR-0014, ADR-0012
  amended).
- **What binds:** an exact integer within 64 bits, checked by us, a flonum but `+nan.0`, a string,
  a bytevector, `sql-null`. Anything else, `#t` and `#f` among them, is an assertion violation
  naming the value by its kind; a bind SQLite refuses raises `&sqlite-error` (ADR-0015).
- **A pointer passed for a value is never NULL,** even for an empty one (ADR-0011 amended,
  ADR-0015).
- **A column's Scheme type comes from `sqlite3_column_type`, never the declared type.** TEXT is
  read through `sqlite3_column_text` and decoded strictly, and bytes that aren't well-formed UTF-8
  raise `&sqlite-invalid-text`; `column-bytevector` reads them undecoded (ADR-0015).
- **A `&sqlite-error`'s subtype comes from its primary code, in the one procedure that makes
  one,** and its `offset` counts characters of its `sql` (ADR-0013 amended).
- **No suite passes three quarters of `MEMORY_TIMEOUT` under the gate,** 450 s of 600. `make
  test-memory` prints each suite's time, and fails one past it as `SLOW`, so a suite is split
  before CI's slower runners reach the timeout. `test-library-loading` was split in two in M2, at
  562 s on a slow runner (ADR-0005, amended).

## Conveniences, transactions, settings and interrupt

- **A convenience runs one statement and finishes it on every path** before it returns or raises:
  back in the cache, reset with its bindings cleared, or finalized. None is left at a row once it
  has returned or raised; `query-fold` holds one only while its procedure runs (ADR-0016,
  ADR-0020).
- **A `dynamic-wind` around a caller's procedure lets a re-entry through,** as M2's do: a guard
  whose clauses don't match re-enters the raise's extent to raise again, and a refusing before
  thunk would replace the caller's condition. **Where an after thunk's work isn't idempotent, a
  flag of M3's own makes it act once,** and a later exit, or a re-entered body or loop, is
  decided by the flag: `query-fold`'s loop raises `&sqlite-closed`, and `with-transaction`'s
  later return raises `&sqlite-transaction-ended`, never a second commit (ADR-0016,
  ADR-0017). A raise inside `call-with-c-string`'s procedure is caught inside it and
  raised after it, since `call-with-block` refuses a re-entry (ADR-0016).
- **Every raise names the procedure the caller called:** M3's conveniences reach M2's statement
  verbs through internals that take a who (ADR-0013, decision 2; ADR-0014, amended).
- **The statement cache holds only reset statements, prepared `SQLITE_PREPARE_PERSISTENT`,** at
  most its connection's `statement-cache` setting, 32 when absent, 0 to 1024, fixed at open; the
  least recently used out first. At 0 it holds none, and the conveniences prepare with no flags. A
  statement whose step or read failed is finalized, never kept. `prepare-statement`,
  `execute-script!` and the settings never use it, and the close finalizes its statements as
  tracked ones (ADR-0020).
- **`with-transaction` reads `sqlite3_get_autocommit`** to choose `BEGIN` or a savepoint, and again
  after its body, before any commit or rollback: whether a failure ended a transaction can't be
  told from its code. It refuses to begin while its connection holds a row (ADR-0017; the M3
  plan's Q14).
- **The settings are an allowlist, each value checked in Scheme before anything opens:** six of
  SQLite's, each set, then read back by a second statement and compared, `busy-timeout` first; and
  the library's own `statement-cache`, which SQLite never sees and nothing reads back. They run at
  open only, and a failure closes the connection, then raises (ADR-0018).
- **`interrupt-database!` calls `sqlite3_interrupt` alone, bound plain, holding the record's
  mutex, and only while the connection is interruptible.** The close clears that under the same
  mutex before it finalizes anything. The mutex is held only inside a critical section, never
  across a call that can block (ADR-0019).
- **A critical section is no lock between threads:** it keeps out only its own thread's engines,
  timers and interrupts. M3's sections guard only what the owner thread touches (ADR-0010,
  decision 1); the one state another thread reaches, the interrupt's flag and handle, is under the
  record's mutex (ADR-0019).
- **No busy handler and no retry in Scheme;** a busy wait ends at its timeout, interrupt or not.
  A row times a wait with a timeout of at least 1500 ms and asserts at least 1000 ms (ADR-0019).
- **M3's five bindings are plain,** and `sqlite3_busy_timeout`, `sqlite3_is_interrupted` and
  `sqlite3_exec` are never bound (ADR-0011, amended; ADR-0019).

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
  check as unavailable and passes on its other checks, never silently (ADR-0005, amended; the
  maintainer's). The control is the check's own `:memory:` open and close, so a suite that opens
  nothing still runs it. Native registers the check with the counters after
  `sqlite3_initialize`; a process that never loaded libsqlite3 has none (ADR-0005, amended).
- **The testing library and the counters never load libsqlite3,** and `test-never-loads` holds
  their imports to exact allowlists (ADR-0005, amended).
- **Valgrind's evidence comes from its log alone.** `timeout` wraps Valgrind and never sits between
  it and Chez, and `CHEZ` is the real binary. There are no suppressions without a recorded run
  that needs one (ADR-0005).
- **`make check-memory-gate` must see the gate fail** on a planted leak and a planted overrun, and
  runs before `make test-memory` in CI (ADR-0005).
- **Counts of blocks, connections and statements must be zero when a suite exits.** There is no
  reset, and a count below zero raises (ADR-0005).
- **CI's workflow has one shape, which `make check-ci` holds and `make test` runs:** its triggers,
  five jobs and their keys; each check as a step's whole run line; only the checkout and cache
  actions, each cache restored before its build and saved before its check; every script a step
  runs by its path there and executable, and no other line naming `scripts/`, a comment or a
  cache key's `hashFiles(` list apart, so no spelling runs a script the rule hasn't read
  (`make check-ci` clears `CHECK_CI_ROOT`); no `if:` but the
  cache's own;
  no line naming a variable that steers a check; no key spelled so a text check would miss it. It
  holds against a mistaken edit, not a deliberate one: a step can compute any name. A change to
  the workflow changes `tests/check-ci.sh` with it (ADR-0005, amended). The banned names include
  `CC`, `C_INCLUDE_PATH`, `CPATH`, `LD_LIBRARY_PATH`, `LD_PRELOAD`, `CHEZ_SQLITE3_DECOY` and
  `CHEZ_SQLITE3_GATE_CHILD`. `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH` stand only in `floor` and
  `current`, as exact env keys of the three steps that name the lane's build; `main`, the job that
  tests discovery, refuses both (M1 slices 3 and 5).
- **`make check-nothreads` refuses every library under `src/` by name** on CI's `--nothreads`
  Chez (ADR-0001, amended).
- **Every child that reaches native code runs through `gated-command`,** under the gate's own
  Valgrind with its own log, which `make test-memory` holds to the parent's evidence rules. The
  gate never uses `--trace-children`. A child started otherwise runs outside Valgrind (ADR-0005,
  amended). The rule covers a child that runs chez-sqlite3's code. A row that runs a CI script,
  whose Chez reads a library through a probe of its own and runs none of chez-sqlite3's code,
  runs it outside the gate (ADR-0005, amended, M1 slice 5).
- **`make test-memory` takes `MEMORY_SUITES` from make's command line only,** and refuses one
  from the environment (ADR-0005, amended).
