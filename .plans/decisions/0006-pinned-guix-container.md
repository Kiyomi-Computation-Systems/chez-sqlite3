# ADR-0006: Builds and tests run in a pinned, toolchain-only Guix container with no network

- **Status:** Accepted (AGENTS.md and the harness plan, 2026-11-13); amended 2026-11-13 with what
  M0 slice 1 measured at the pin ([amendment](#amendment-2026-11-13-what-m0-slice-1-measured)),
  with the self-test after the slice's review
  ([amendment](#amendment-2026-11-13-the-self-test-after-the-slices-review)), and with the
  version reports held by `check-ci` after M0's closing review
  ([amendment](#amendment-2026-11-13-the-version-reports-are-held-m0s-closing-review))
- **Date:** 2026-11-13
- **Scope:** development tooling; no library change
- **Related:** chez-curl ADR-0006, which this copies · [ADR-0002](0002-runtime-libsqlite3-discovery.md)
  (the override) · [ADR-0005](0005-memory-gate.md) (Valgrind) ·
  [ADR-0007](0007-test-harness-and-scheme-dependencies.md) (submodules)

## Context

- **The maintainer develops on Guix.** Builds and tests need Chez ≥ 10.4.0, SQLite ≥ 3.45.1 with
  its header, a C compiler for the constants check (ADR-0001), Valgrind (ADR-0005), `make` and the
  usual shell tools.
- **Outside Guix, this host's SQLite is 3.37.2,** below the floor, and Guix's Chez can't load it by
  soname (ADR-0002). The host's Guix home has SQLite 3.53.1, but that is the host's Guix, not a
  pin.
- **chez-curl's container already does this job,** and so does its pin, `b532aa7d…`. What SQLite
  that pin gives isn't measured yet.

## Decision

**Copy chez-curl's container, with these changes for SQLite.**

1. **The launcher, unchanged.** `scripts/guix-env` runs
   `guix time-machine -C channels.scm -- shell -m manifest.scm --container -- sh scripts/guix-env-enter CMD…`
   without `--network`. It refuses to run inside a Guix environment. It preserves only `TERM`,
   `COLORTERM` and `LANG`. `GUIX_ENV_DRY_RUN=1` prints the command instead of running it.
2. **The pin.** `channels.scm` pins chez-curl's `b532aa7d0bb345aafabf6b63cbfbda45abbec091`, if M0
   slice 1 measures its SQLite at 3.45.1 or above. Otherwise slice 1 moves to a newer pin.
   Either way, the measurement is recorded here as an amendment.
3. **The manifest** holds `chez-scheme`, `sqlite` (library and header) and `gcc-toolchain`
   (ADR-0001), `valgrind` (ADR-0005), and the shell tools the Makefile and scripts call. It holds
   no git, Node or openssl. Each entry has a comment naming the decision that needs it.
4. **`scripts/guix-env-enter`** refuses to start without `bin/scheme`, `bin/gcc` and
   `lib/libsqlite3.so.0` in the profile. It exports:
   - `CHEZ`, the profile's real `scheme` binary;
   - `CC`, the profile's `gcc` (the toolchain has no `cc`);
   - `CHEZ_SQLITE3_LIBRARY`, which is `$GUIX_ENVIRONMENT/lib/libsqlite3.so.0`, so no suite
     depends on discovery.

   It sets no `LD_LIBRARY_PATH` and uses no `--emulate-fhs`, so no bare-name load can work by
   accident.
5. **`scripts/require-tools GOAL TOOL…`** fails a target before it runs when a tool is missing. On
   a Guix host, its hint is `scripts/guix-env`.
6. **`make check-guix`** runs the host-side launcher tests, then a self-test in the container. The
   self-test asserts these things:
   - `HOME` is isolated.
   - `scheme`, `gcc`, `valgrind` and `make` resolve to the profile's own binaries.
   - `CHEZ` is an ELF binary under the profile.
   - `CC` compiles a program against `<sqlite3.h>`.
   - `CHEZ_SQLITE3_LIBRARY` is exactly the profile's library, and it exists.
   - A bare-name load of `libsqlite3.so.0` is refused.
   - The network is loopback only.
   - Valgrind instruments `$CHEZ`.
   - There is no git.
   - The Makefile's own checks pass.

   Each assertion is watched failing under a targeted change before it counts.
7. **People and agents edit, commit and push on the host.** Builds and tests go through
   `scripts/guix-env`.

### Rejected

- **`--network`.** Nothing fetches at build or test time, so "no test touches the network" is a
  property of the environment.
- **`--emulate-fhs`, or `LD_LIBRARY_PATH`.** ADR-0002 never searches standard directories in a Guix
  world, and either would let a bare-name load succeed by accident.
- **git in the container.** In a git worktree, the container's git finds no repository, because
  `.git` names a directory outside the share (chez-curl ADR-0006's amendment).

## Consequences

- **Anything that needs the network or git runs on the host:** submodules, `make check-pins`, and
  fetching an amalgamation.
- **The container is for x86_64 Linux hosts like this one.** The Mac doesn't use it.
- **No CI job runs the container.** CI builds Chez from the release tarball and uses the runner's
  SQLite, or one it compiles. Each run records the versions it used, because the pinned container
  and the runner can drift apart.
- **The container isolates the toolchain; it is not a sandbox.** The repository is shared
  read-write.
- **Bumping the pin** means changing `channels.scm` and running `make check-guix`.

## Amendment, 2026-11-13: what M0 slice 1 measured

At `b532aa7d…`, a container with `chez-scheme`, `sqlite`, `gcc-toolchain` and `valgrind` gives:

- Chez 10.4.0 (`ta6le`, threaded);
- SQLite 3.53.1 (`sqlite3_libversion_number` 3053001, `THREADSAFE=1`, `ENABLE_FTS5`,
  `sqlite3_load_extension` present), with `sqlite3.h` in the profile;
- gcc 16.2.0;
- Valgrind 3.27.0.

Through the library, an FTS5 table can be created and `jsonb('{}')` is a blob. Every need in the
Context is met, so **the pin is kept** (decision 2). The commands and their output are in
[research/guix-pin/](../research/guix-pin/).

- **The profile's library is the host's Guix home's library:** the same store item,
  `/gnu/store/vi2anm0…-sqlite-3.53.1`.
- **The `sqlite3` command is not the library.** The command in that store item links no
  `libsqlite3`. It carries its own copy of SQLite, compiled with options the library lacks:
  `DQS=0`, `ENABLE_RTREE` and `ENABLE_STMTVTAB` among them. The brief's first version recorded the
  command's options as the library's. Options are read from the library, through the FFI.

## Amendment, 2026-11-13: the self-test after the slice's review

The slice's review found checks that read a symptom instead of the property (`.plans/traps.md`).
Each was reproduced, then fixed and watched failing ([the mutation
log](../guix-env-mutation-log.md)). Decisions 1 and 6 gain:

- **Only `GUIX_ENV_DRY_RUN=1` is a dry run.** Any other value runs guix, so
  `GUIX_ENV_DRY_RUN=0 make check-guix` can't pass without entering a container.
- **`CHEZ` is the profile's `scheme` itself:** under the profile, and resolving to its `scheme`.
  `petite`, which is under the profile too, has no compiler.
- **The header is the library's.** `sqlite3.h`'s `SQLITE_VERSION_NUMBER` must equal
  `sqlite3_libversion_number` from `CHEZ_SQLITE3_LIBRARY`. Otherwise the constants check could be
  held to another SQLite's numbers (ADR-0001).
- **The container's only interface is `lo`,** read from `/proc/net/dev`. The connection probe
  stays as a cross-check, run under `LC_ALL=C` because it matches error text. An outside address
  that is unreachable shows only that there is no route there. A container with a network gives
  that too when the host has no default route.

chez-curl's scripts share each of these gaps; this repository's copies now differ from them.

## Amendment, 2026-11-13: the version reports are held (M0's closing review)

- **The steps that record the versions are now held.** The review deleted both of the `main`
  job's report steps, and every check passed. `make check-ci` now requires them, once each and in
  order, between the check-chez step and the make step: "Report the versions this run uses", with
  its run block line for line, then "Report the runner's SQLite", with its `env: CHEZ` and its
  run line (ADR-0005's amendments).
- **What `scripts/ci/report-sqlite.sh` prints is not held.** Replaced by `exit 0`, it passed
  `check-ci`, and nothing under `tests/` runs it. It reports and checks nothing, and was left out
  of slice 4's mutations for that reason; its output is read by eye on each run.
