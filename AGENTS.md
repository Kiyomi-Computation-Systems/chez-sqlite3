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
* A thread a suite forks dies on a raise it does not catch, and a waiter with
  no bound then hangs the suite, naming no test. Make whatever a thread raises
  its answer, and bound every wait for one.

**Chez and the FFI**

* `foreign-procedure` resolves its entry point when evaluated, so every
  binding must follow the library's load. Mistakes fail at *import*.
* A library body runs only when one of its bindings is *referenced*. A test of
  load-time behaviour must call into the library. A top-level program runs every
  body it references before its first line, so no thread of a program makes a
  first reference: only `eval` reaches a race on one.
* A `guard` in a program cannot catch a raise from an imported library's body.
  A probe must `eval` its call inside the guard.

## Closing ritual

We run this when we're done and ready to merge the PR.

**Important**: ALWAYS ask before running this.

1. Squash merge the PR.
2. Catch up local `main`.
3. Clean up branches. Delete the merged branch locally and on the remote.
4. Reflect.
