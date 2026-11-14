# chez-sqlite3 harness plan: what M0 copies from chez-curl

Date: 2026-11-13
Status: approved 2026-11-13. Amended in M0 slice 2: each test helper comes with its first
consumer, a threaded Chez is required (brief D1), and the floors' CI rules wait for CI.
Amended in M0 slice 3: the gate needs no suppression, so sabotage group c has nothing to hold,
and group o comes with CI in slice 4; the review added g all, g environment and o's tripwire,
and M1 owns the children Valgrind doesn't follow. Amended in M0 slice 4: `check-nothreads` checks
every library under `src/`, since M0 has no public one; `report-sqlite.sh` reports the runner's
SQLite and checks nothing, M1's lanes holding it to its floor and header; and, from the slice's
review, `make check-ci`, which `make test` runs, holds the workflow's shape. Amended at M0's
closing review: `check-ci` holds the version reports too, and `check-test-fails` holds its place
in `make test`; SQLite's two checks follow ADR-0005, decision 5 (§3).
Source: chez-curl at `79c6ced` (`main`), surveyed read-only. Every path below is chez-curl's
unless it says otherwise.
Brief: [the project brief](2026-11-13-chez-sqlite3-project-brief.md). The maintainer settled
these on 2026-11-13: the harness is a trimmed copy of chez-curl's, and the memory gate has four
parts, SQLite's counters, our counters, and Valgrind.

chez-curl's harness is the newest in the family, and it binds a C library with no shim, as we
will. We copy what works and change only what SQLite needs. M0 builds the parts that need no
library code; the rest arrives with the code it checks (§4).

## 1. What M0 copies

| Piece | From | What changes |
|---|---|---|
| The pinned container: `channels.scm`, `manifest.scm`, `scripts/guix-env`, `guix-env-enter`, `guix-env-selftest`, `scripts/require-tools`, `tests/guix-env-launcher.sh` | the same paths | The manifest swaps `curl` for `sqlite` and drops `node` and `openssl`. `guix-env-enter` requires `lib/libsqlite3.so.0` and exports `CHEZ_SQLITE3_LIBRARY`, an absolute path, beside `CHEZ` and `CC`. The self-test's tool list and override assertion follow. Still no `LD_LIBRARY_PATH`. |
| The Makefile skeleton: `help`, `check-help`, `.DEFAULT_GOAL := help`, `.PHONY` on one line, `require-tools` at the head of each recipe that runs Chez, `timeout` or Valgrind (`check-guix-inside` excepted: its self-test is the toolchain's check), `CHEZ`, `GOAL`, `LIBDIRS`, sorted `SUITES` | `Makefile` | Our targets only (§4). |
| `make test`: every suite runs after a failure, each under `timeout --foreground`, exit 124 reported as HUNG, a summary line, no suites is an error | `Makefile` (`test`) | The prerequisites shrink to `deps check-help check-suites check-floors`, and slice 4 adds `check-ci`. |
| SRFI-64: `vendor/chez-srfi` at `7879b52`, `Akku.manifest` (`depends/dev` only, no scripts), `Akku.lock`, `make deps` (never fetches), `make check-pins` | the same paths | chez-srfi only, with no jsonparse or byte-machine. |
| `check-suites`, `check-test-fails`, `clean`, `check-clean` | `tests/check-suites.sps`, `tests/check-test-fails.sh`, `tests/check-clean.sh` | The plants we keep: `fails`, `no-tests`, `hangs`, `exit-line`, `early-exit`, `nested-exit`, `empty`, `leaks`, `floors`, `no-suites`, and `ci`, added at M0's closing review. `seam` arrives with `check-seam` (§4). |
| The test helper library, as `tests/chez-sqlite3-testing.sls` | `tests/curl-testing.sls`: `suite-exit-form`, `suite-exit-status`, `describe` | Each other helper (`capture-command`, temporary directories, `run-until`) joins with the suite that first needs it, as chez-curl held its origin helpers back until the origin existed. A helper with no consumer can't be seen to fail. The Node origin, wire probe and TLS helpers stay behind. Its suite comes with it. |
| The counters, as `(chez-sqlite3 private counters)` | `src/curl/private/counters.sls` | Three kinds: `block` (our `foreign-alloc`), `connection`, `statement`. Same mutex inside `critical-section`, no reset, and a raise on a count below zero. `suite-exit-status` fails a suite with any nonzero count. |
| Floors in one file: `packaging/floors.sexp`, `scripts/ci/floor.sh`, `make check-floors`, `tests/floors.sls` | the same paths | `((chez "10.4.0") (sqlite "3.45.1"))`. README.org's `** Requirements` is held to it from slice 2. The workflow rules and `floor.sh` come with CI, in slice 4. |
| `test-manifest` | `tests/test-manifest.sps` | Our package, chez-srfi as the only dev dependency, the version against CHANGELOG.md. |
| The memory gate: `test-memory`, `check-memory-gate`, `memory-plant-leak.sps`, `memory-plant-overrun.sps` | `Makefile`, `tests/check-memory-gate.sh` | §3. |
| CI: Chez built from the pinned release tarball and cached with separate restore and save steps; one fail-closed package list; versions reported; actions pinned to commit SHAs | `.github/workflows/ci.yml`, `scripts/ci/build-chez.sh`, `scripts/ci/check-action-pins.sh`, `packaging/debian-prereqs.txt` | Three jobs in M0, `main`, `memory` and `nothreads` (ADR-0001's amendment). The package list is `build-essential`, `ca-certificates`, `curl` (to fetch the Chez tarball), `libsqlite3-dev` (for `sqlite3.h`) and `valgrind`. |
| `.gitignore`, the CHANGELOG format (Keep a Changelog 1.1.0, semver), mutation logs in the newer format, decision records in the house form | the same | none |

## 2. What we leave behind

- **The Node origin and TLS:** `origin.mjs`, `wire-probe.mjs`, `make-test-pki.sh`, `NODE`,
  `OPENSSL`, and the origin and TLS helpers in `curl-testing.sls`.
- **What only libcurl needed:** the drift guard (`test-drift`, `known-*.sexp`),
  `check-variadic`, the GnuTLS lane, `CURL_SSL_BACKEND`, `stall-getaddrinfo.c`, the engine
  suites, and the two-family half of `check-seam`.
- **Memory shards** (`MEMORY_SHARD`, `MEMORY_SUITES_1`/`_2`, sabotage group n). We add them when
  the gate gets slow, as chez-curl did in M8.
- **The Guix suppression** (`tests/guix-glibc-locpath.supp`, sabotage group d). Its leak came
  from p11-kit in libcurl's TLS stack, and libsqlite3 doesn't load p11-kit. M0 slice 3 measures;
  a suppression comes back only if a recorded run needs one.
- **`traps.md`'s 1,621 lines.** AGENTS.md already carries the family's one-line rules. Our
  `.plans/traps.md` starts empty, links to chez-curl's for the incidents behind the inherited
  rules, and records only incidents that happen here.

## 3. The memory gate

The four parts each see something the others miss:

| Part | Sees | Blind to |
|---|---|---|
| Valgrind (`--leak-check=full`, definite losses, `--error-exitcode=9`) | overruns and lost blocks inside C, SQLite's included, since every build we test uses the system malloc | memory Chez's heap still points at: a forgotten handle is "reachable", not lost (chez-curl ADR-0014's 2026-10-16 amendment) |
| our counters | a connection, statement or block that Scheme forgot to release | anything inside C |
| `sqlite3_next_stmt(db, NULL)` | a statement left open on a connection | statements that were never ours |
| `sqlite3_memory_used` | SQLite memory still held after every connection closes | our own allocations |

- **M0 builds the Valgrind half and the counters.** Valgrind runs each suite as chez-curl's
  does: `timeout` wraps Valgrind and never sits between it and Chez, `CHEZ` is the real binary,
  and evidence comes from Valgrind's log alone. Its evidence rules, its refusals of `VALGRIND_*`
  and rc files, and sabotage groups a, b and e–m come with it. Group c held chez-curl's
  suppression file to its one entry; slice 3 measured that we need none, so it has nothing to
  hold ([research/memory-gate/](research/memory-gate/)). Group o reads the CI workflow, so it
  comes with CI in slice 4.
- **M1 adds SQLite's two checks,** once there is a loaded library to ask: `sqlite3_next_stmt` at
  each close (ADR-0005, decision 5), and `sqlite3_memory_used` in a process that loaded the
  library. Not in `suite-exit-status` itself, whose library never loads libsqlite3, so that
  `check-suites`, `check-test-fails` and the launcher's tests can import it (M0's closing review).
  M1 measures first whether `sqlite3_memory_used` returns to its pre-open value after a full
  open and close; if SQLite keeps something global, the baseline is taken after the first
  cycle.
- **`--undef-value-errors=no` stays off.** chez-curl needed none. It comes back only with a
  recorded run that needs it, which is most likely once callbacks exist, and none do in v1.

## 4. What arrives later, with the code it checks

| Piece | Milestone | Why it waits |
|---|---|---|
| `make build` (preflight), `make dev`, `check-dev`, the refusal probe | M1 | They print what loaded. |
| `(chez-sqlite3 private load-state)` and its suite, copied whole | M1 | It is library code. The inventory calls it generic. |
| A leaks plant that leaks through the first real constructor, replacing slice 2's raised count | M1 | No library makes a native object before then (ADR-0007's amendment). |
| Every child process that reaches native code runs under the gate's Valgrind, with its own log, or the gate follows children (`--trace-children=yes`, a log per process) and reads every log | M1 | Valgrind follows no child, and the refusal probes, children that load libsqlite3, are M1's (ADR-0005, amended). |
| `check-seam`: only the FFI library may import `foreign-procedure`, `load-shared-object` or `foreign-alloc`, and nothing public imports a private library except `(chez-sqlite3)` | M1 | Its rules are about the FFI and the public library, which arrive there. Its rule against library files that aren't `.sls` came early, in slice 2's review, as a row of `test-require-threaded`. |
| A convention suite: each foreign procedure's attributes (`__collect_safe`, `__varargs_after`) and argument types against a table (brief §3d) | M1 | chez-curl's `foreign-conventions.sls` is 1,859 lines built around its engine. We write a small one. |
| `test-constants`: a C program compiled against `sqlite3.h` checks every constant (brief §3a) | M1 | The constants come with loading. |
| A decoy libsqlite3 compiled per case, for discovery's end-to-end refusals | M1 | Discovery is M1. |
| `scripts/ci/build-sqlite.sh`, and the `floor` and `current` lanes | M1 | §5. |
| `test-docs`, `test-reference` | M1 | `docs/reference.md` holds one entry per export from the first export on. |
| A lane with extension loading compiled out (`SQLITE_OMIT_LOAD_EXTENSION`) | M4 | chez-curl's `floor-disabled-api` pattern, for brief §2.5's condition. |

## 5. CI lanes

All Linux, `ubuntu-24.04`, every job on every event, none with `if:` or `continue-on-error:`.

- **`main`** (M0): the checks and the suites, against the runner's own SQLite found by
  discovery once discovery exists. Ubuntu 24.04's is 3.45.1; slice 4 verifies this on the runner.
- **`memory`** (M0): `check-memory-gate`, then `test-memory`.
- **`floor`** (M1): `build-sqlite.sh` compiles the 3.45.1 amalgamation with `gcc -shared -fPIC`
  and fixed `-DSQLITE_*` flags, from a download checked against a pinned SHA3-256 (sqlite.org
  publishes these). It is cached like Chez. It then asserts `sqlite3_libversion()` and the
  compile options. Suites load it through `CHEZ_SQLITE3_LIBRARY`, and `C_INCLUDE_PATH` names its
  header.
- **`current`** (M1): the same at a pinned current release.

`main` and `floor` both test 3.45.1. That is on purpose: one is a distribution's build, with its
own options; the other is ours, with known flags.

## 6. Order of work: M0's slices

Each slice is one PR. A check is not finished until we have watched it fail; each slice keeps a
mutation log in the newer format (Guards, Mutation, Result, Clean rerun).

0. **The records.** Decision records for what M0 rests on: no C shim and the Chez floor,
   runtime discovery, the SQLite floor, Windows, the memory gate, the Guix container, the test
   harness, floors in one file, and written fresh under `(chez-sqlite3)`. Plus `progress.md`,
   `global-constraints.md` built from them, and AGENTS.md's links put back. The records for the
   library's own design (brief §3c–g, §2.5, §2.7, §2.8) come with the M1 and M2 plans.
1. **The container.** Measure first, on the host: what the pinned Guix gives for Chez,
   SQLite (it must be ≥ 3.45.1), gcc and Valgrind. Reuse chez-curl's pin if it passes, else move
   to a newer pin. Then the launcher, `enter`, the self-test, `require-tools`, `help`,
   `check-help`, `check-guix`, and `.gitignore`.
2. **The test harness.** chez-srfi, Akku, `deps`, `check-pins`, the testing library and its
   suite, the counters, `require-threaded` and its suite (brief D1, settled), `test`,
   `check-suites`, `check-test-fails`, `clean`, `check-clean`, floors and `check-floors`,
   `test-manifest`, CHANGELOG.md, README.org's Requirements. The host-side tests that need
   `make test` (chez-curl's M2 and its `TIMEOUT` fallback) join `tests/guix-env-launcher.sh`, and
   the self-test runs `make test`. `test-manifest`'s checks of install instructions wait for
   the first release, which writes them.
3. **The memory gate.** Measure first: Valgrind on Chez in the container, loading
   libsqlite3 and opening and closing a database through bare FFI, with no suppression. Then
   `test-memory`, the plants and `check-memory-gate`.
4. **CI.** `build-chez.sh` (with `--nothreads`), `check-action-pins.sh`, `floor.sh`, the package
   list, and the `main`, `memory` and `nothreads` jobs, the last running `check-nothreads`
   (ADR-0001's amendment). `check-floors` gains the workflow rules, and `check-memory-gate`
   gains group o: the `memory` job runs `check-memory-gate` before `test-memory`, and neither
   carries `if:` or `continue-on-error:` (ADR-0005). The first run records the runner's SQLite
   version and compile options.

M0 ends with a read-only adversarial review, on Opus, of the slices and of this plan.
