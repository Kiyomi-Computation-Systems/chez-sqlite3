# AGENTS.md

## Project guidelines

### Architecture & portability

* Use the functional core / imperative shell pattern
* Follow the 12 Factor Apps philosophy
* Project is built for Chez Scheme
* A Chez Scheme library binding the SQLite C library (`libsqlite3`) through
  the FFI; handle C *safely*.
* Project should be portable across macos (darwin) and linux, on amd64 and
  arm64; windows is not supported
  (`.plans/decisions/0004-windows-not-supported.md`)
* **DO NOT** setup macos CI runners: linux only!
* `make check-ci`, which `make test` runs, holds `.github/workflows/ci.yml` to
  one shape. A change to the workflow changes `tests/check-ci.sh` and its
  suite with it (ADR-0005, amended).
* Exported functions should have a comment with a Typed Racket style type signature
* The public library is `(chez-sqlite3)`. Internals live under
  `(chez-sqlite3 private …)` and never escape it (ADR-0009).
* The code is written fresh. Thunderchez's `sqlite3.sls` is a reference for
  API ideas only: copy none of its code (it is Apache-2.0; this project is
  BSD-3). `.plans/chez-sqlite-thunderchez-assessment.org` lists its defects
  (ADR-0009).

### Dependencies

* SQLite (`libsqlite3`), found and loaded at runtime (ADR-0002), and Chez
  Scheme, threaded (ADR-0001), each at or above its floor in
  `packaging/floors.sexp`, the one place the floors are written (ADR-0008)
* chez-srfi, vendored as a git submodule, for SRFI-64 in the tests only

### Guix development container

* **On a Guix host, run every build and test through `scripts/guix-env`**,
  e.g. `scripts/guix-env make test`. Batch commands with
  `scripts/guix-env sh -c 'make a && make b'`: each call takes a second or
  more to start.
* Edit, commit and push on the host. The container has no git identity,
  agents or tokens, and no network but loopback (ADR-0006).
* Verify it with `make check-guix`, run on the host.
* The container exports `CHEZ` (the real `scheme` binary), `CC` (gcc; the
  toolchain has no `cc`) and `CHEZ_SQLITE3_LIBRARY` (the profile's
  `libsqlite3.so.0`, ADR-0002). It sets no `LD_LIBRARY_PATH`.
* A floor run sets `C_INCLUDE_PATH` to the floor's headers as well as
  `CHEZ_SQLITE3_LIBRARY` to its library, as CI's `floor` lane does: the
  suites' C compiles against whichever `sqlite3.h` comes first, and no check
  compares it with the library loaded (`.plans/traps.md`).
* Anything that needs the network or git runs on the host: fetches, pushes,
  downloads, `make check-pins`, and `git submodule update --init --recursive`,
  which a fresh clone needs once before `make deps`. The container has no git.

### Layout, process & libraries

* Plans live in `/.plans`, decision records in `/.plans/decisions`
* The ledger is `/.plans/progress.md`: where the project stands, the next
  slice, and a close-out for each merged slice. `/.plans/global-constraints.md`
  holds the decision records' hard rules and binds every task brief. Read both
  before starting slice work. `/.superpowers/` is git-ignored plugin scratch,
  not the ledger.
* Add entries to `CHANGELOG.md` for each release
* `/docs` is for user facing documentation only.
* Documentation should be very concise, focused, to the point, ELI5 style.
* `Makefile` should have a `help` command which lists all of its commands
* Libraries are R6RS `.sls`; libraries and programs contain their own code —
  no shared include bodies. R6RS forbids assigning an exported variable —
  reach mutable state through procedures.
* Cite a sibling's record with its repository's name (`chez-curl ADR-0014`),
  never by its number alone.
* Before a global replace, predict how many matches it should hit, and check
  the count afterwards: the sentence that defines a marker contains the
  marker (`.plans/traps.md`).

### Testing & mutation discipline

* Use TDD / test-driven development
* A test that passes whether the code is right or wrong is worse than no test.
* A test is not finished when it passes. It is finished when you have watched
  it fail.
* Prefer a check to a comment.
* **Do not** write tests that rely on reading code comments. The one exception:
  `test-reference` holds `docs/reference.md`'s signatures to the Typed Racket
  signature comments of `(chez-sqlite3)`'s exports, which are the contract
  (the maintainer, 2026-11-14)

**Tests**

* `guard` returns the body's value when nothing raises, and `0` is truthy.
  Assert *what was raised* against an expected value, with a distinct sentinel
  for the no-raise case.
* SRFI-64 turns an exception in the *actual* expression into `#f`. Never
  expect `#f` from something that can raise.
* SRFI-64 does not catch an exception in the *expected* expression, nor in a
  suite's top-level definitions: the suite dies and no test is named. Compute
  anything that can raise under a `guard`.
* Every `tests/test-*.sps` must end with `(exit (suite-exit-status runner))`:
  SRFI-64 sets no exit status. Anything after that line never runs, and
  `make check-suites` checks it is there.
* An exit status is taken modulo 256, so `(exit 256)` exits 0. Exit with 0 or
  1, never a count.
* A suite cannot vouch for the verdict it exits through. A suite that tests
  `suite-exit-status` must also exit 1 on its own failures, before the
  shared form.
* Chez fixes no order for a call's arguments. On 10.4.0, compiled code ran
  them left to right and `interpret` right to left, and the interpreter path
  that `--script` and `load` take for simple top-level forms mixed them
  (`cab`, `bca`) (`.plans/research/evaluation-order/`). `map` calls its
  procedure in no fixed order, and a `let`'s inits are arguments too. No
  assertion may depend on any order; use `for-each` for effects, and `let*`
  when one init must follow another. A probe is code under these rules too.
* The `sqlite3` command can carry its own copy of SQLite, with other
  compile options; Guix's does. Read a library's version and options through
  the FFI, never from the command (`.plans/traps.md`).
* A setter that refuses a value keeps the one it had. Give each round trip
  its own sentinel, and assert every return code.
* An assertion passes whenever *another* rule can produce its expected value.
  Assert whole outputs, not substrings, and build a test's base from
  non-default values. Test a scan at every position, an encoding on bytes
  where encodings differ, and an allowlist against its whole complement.
* SRFI-64 keeps one result per runner. Never run a test inside another test's
  actual expression: the outer verdict is reported under the inner test's name.
* `make test-memory` fails a suite past three quarters of `MEMORY_TIMEOUT`
  as `SLOW`. CI's runners differ about two to one, so split a suite long
  before it nears the limit, and read a cost from more than one CI run
  (ADR-0005, amended).
* CI's memory gate runs in two shards, the Makefile's `MEMORY_SUITES_1`
  and `MEMORY_SUITES_2`. A new suite goes in the one whose suites take
  less time on CI, and `make test` fails, naming it, until it is in one
  (ADR-0005, amended).
* A thread a suite forks dies on a raise it does not catch, and a waiter with
  no bound then hangs the suite, naming no test. Make whatever a thread raises
  its answer, and bound every wait for one.
* Under Valgrind a thread running C keeps the CPU, so a watchdog may never
  run during the call it means to interrupt. Have it take SQLite's memory
  mutex each round, so the owner blocks inside SQLite. Every call the owner
  makes while the mutex may be held is `__collect_safe` or takes none of
  SQLite's memory, or another thread's collection waits on it. SQLite
  clears the interrupt as a statement or a parse starts, and a prepare
  reads it only while it tokenizes, so the first round is a handshake:
  holding the mutex, interrupt, wait until the flag reads clear, then
  interrupt again, inside the call. A watched call doesn't prepare unless
  the prepare is the point, and a round's raise lets the mutex go
  (`.plans/traps.md`).
* Whether a failure ended a transaction can't be told from its code, its
  SQL or its version: the same NOMEM or FULL undid one statement or the
  whole transaction, by one function call, and one compile option,
  `ENABLE_MEMORY_MANAGEMENT`, moves a statement's NOMEM from one to the
  other. Read `sqlite3_get_autocommit` after it
  (`.plans/research/m3-plan/single/`, `.plans/research/m3-mac/`).
* A busy wait's length is the build's: one without `nanosleep` sleeps whole
  seconds, so a timeout under 1000 ms answers BUSY at once. A row that times
  a wait uses a timeout of at least 1500 ms and asserts at least 1000 ms,
  and under twice the timeout. On whole seconds the wait is 1000 ms and a
  retry 2000 ms, so the row reads the grain first and asserts under 2000 ms
  there: then a retry in Scheme fails it on either grain
  (`.plans/research/m3-plan/concurrency/`; ADR-0019, amended). A row that
  reads the grain itself may time a shorter one, asserting only a bound
  that holds on either grain.
* A connection's own statement held at a row stops its writes from waiting:
  under another's write lock they answered BUSY at once, where without the
  held read they waited out a 1500 ms timeout. A row that waits on a lock
  holds no read of its own (`.plans/research/m3-plan/slice-0/`, P12).
* SQLite's unix VFS keeps a closed connection's file descriptor while
  another connection in the process holds a POSIX lock on the file. Read
  a file's descriptors only once every connection holding a lock on it
  has let go (`.plans/traps.md`).
* A collect request costs an engine's run ticks. A row that judges one
  run by another at the same fuel collects first, with
  `collect-trip-bytes` raised above what the runs allocate, or judges
  each run by what it saw itself (`.plans/traps.md`). A raised trip
  hides a remainder just past a call's last section, since a request due
  inside a section costs its ticks at the exit: a sweep of a call that
  holds a claim also runs a pass with the trip below what one call
  allocates, judges each trial by its own effects, and fails by name
  unless that pass reached past the section (ADR-0016, amended in M4
  slice 4).

**Chez and the FFI**

* `foreign-procedure` resolves its entry point when evaluated, so every
  binding must follow the library's load. Mistakes fail at *import*.
* A library body runs only when one of its bindings is *referenced*. A test of
  load-time behaviour must call into the library. A top-level program runs every
  body it references before its first line, so no thread of a program makes a
  first reference: only `eval` reaches a race on one.
* A `guard` in a program cannot catch a raise from an imported library's body.
  A probe must `eval` its call inside the guard.
* Nothing raises inside `critical-section` or a critical `dynamic-wind` thunk:
  a `with-exception-handler` handler of the raise runs with interrupts
  disabled, where an engine never expires and another thread's collection
  waits. Answer data there, and raise after the section (ADR-0012, amended).
* A `guard` whose clauses don't match re-enters the raise's extent to raise
  again, so a `dynamic-wind` before thunk that refuses a re-entry replaces
  the caller's condition with its own. Let a re-entry through, as
  `call-with-database`'s before thunks do. An after thunk whose work isn't
  idempotent acts once, behind a flag, and whatever runs after a re-entry
  reads that flag before it touches anything the first exit finished.
* An engine's expiry runs `dynamic-wind`'s after thunks, `with-mutex`'s
  release among them, and the resume runs the before thunks again. So a
  check in one section and the act it guards in a later one can be split
  by an expiry: read a flag inside the section of the step it guards, and
  sweep an engine row's fuel until the call completes without expiring,
  not to a fixed bound (`.plans/traps.md`).
* An engine's remainder can be resumed twice, and runs twice from the same
  point; a timer's, a keyboard's or a collect request's handler is the
  caller's code, run between any two critical sections, and can capture a
  continuation there. So a flag that guards a call is read in every
  section that touches the call's resource, not only around the caller's
  procedure, and a row tells a whole new call, from a continuation taken
  before the call began, from a re-entry (`.plans/traps.md`).
* One remainder can also be resumed again while an earlier resume of it
  is still pending, so a flag set only once a call ends lets both runs
  act. Give the call a claim that each section compares, inside the
  section, with a position the run carries, and advances (ADR-0016,
  ADR-0018, amended). Build text with Chez's own procedures inside a
  critical section: `number->string`, resumed from inside, answered `""`
  or the digits twice (`.plans/traps.md`).
* A sweep of an engine's remainders takes a fresh engine and connection
  for every trial, checks the call's clean answer first, and fails by
  name when too few trials have both runs past the call's first section:
  one remainder reused across trials sweeps nothing past the first. An
  engine's fuel names no fixed point in the code, so sweep every pair of
  fuels (`.plans/traps.md`). A stand-in a sweep reads spins before the
  effect it notes: one that only notes may cost no tick, and then no fuel
  splits it from the code before it (`.plans/traps.md`).
* Unlock exactly what was locked, once: Chez 10.4.0's `unlock-object` of an
  object that isn't locked still decrements its segment's count, and can
  unpin another locked object there (`.plans/traps.md`).
* Chez's foreign `int` takes −2³¹ to 2³²−1, hands 2³¹ and above to C as
  negatives, and raises beyond, inside the section that makes the call.
  Check that each value fits its C type before the section (ADR-0011,
  amended).
* A variadic C function is bound with `(__varargs_after N)`, N its named
  parameters. Without it, `sqlite3_db_config` worked on x86_64 and crashed
  on Apple arm64 (`.plans/research/m4-prework/`), so no Linux behaviour row
  can see the convention lost.
* `sqlite3_db_config` sets no error on its connection, and
  `sqlite3_load_extension` none of its own: after either fails, the
  connection's code and `sqlite3_errmsg` are another call's, unless an
  extension's init failed a call that set them. Take a failure's code from
  the call's own answer, a set's message from `sqlite3_errstr`, and a
  load's from its own message slot (`.plans/research/m4-plan/`).
* Chez's `utf8->string`, and a UTF-8 transcoder, drop one leading U+FEFF.
  Decode a column's value or name with `strict-utf8->string`, which keeps
  it. `c-string->string` keeps it too but replaces invalid bytes, so it
  reads SQLite's own text and messages, never a value or a name. Never
  `utf8->string` outside `utf8` and `native`: `check-seam` refuses it
  (`.plans/traps.md`).
* A handler's jump back within a wind's extent crosses no winder, so a
  `dynamic-wind` before thunk refuses only a jump in from outside. A call
  that must run each step once claims each step's position inside that
  step's section. Hold such a claim with a timer's continuation called from
  inside the call too: engine sweeps passed a check made outside its
  section, since every run they reached met a flag the first run had set
  (ADR-0016, ADR-0017, amended in M3's closing review; `.plans/traps.md`).
* A sweep bounds a whole new call by a refusal it sees itself: a remainder
  taken before the call's first section has its second resume refused, and
  every whole new call comes below the first such fuel. Never bound it by a
  refused call's fuel, which can pass the whole call's; nor by a control run
  on the code under test, which moves with a mutant; nor by a caller's own
  count, since each procedure entry before the call's first expression costs
  a tick. Count a guard against the fuels swept, never one trial
  (`.plans/traps.md`).

## Closing ritual

We run this when we're done and ready to merge the PR.

**Important**: ALWAYS ask before running this.

1. Squash merge the PR.
2. Catch up local `main`.
3. Clean up branches. Delete the merged branch locally and on the remote.
4. Reflect.
