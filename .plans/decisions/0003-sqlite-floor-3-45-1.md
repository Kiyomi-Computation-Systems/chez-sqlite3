# ADR-0003: The SQLite floor is 3.45.1

- **Status:** Accepted (the maintainer, 2026-11-13). Amended 2026-11-14, and accepted by the
  maintainer that day: decision 3 is built (M1 slice 5,
  [amendment](#amendment-2026-11-14-decision-3-is-built-m1-slice-5)).
  Amended 2026-11-17 in M4's plan, and accepted by the maintainer that day: FTS5 on the current lane
  ([amendment](#amendment-2026-11-17-fts5-on-the-current-lane-m4s-plan)).
- **Date:** 2026-11-13
- **Scope:** every SQLite chez-sqlite3 loads
- **Settles:** brief §2.2
- **Related:** [ADR-0002](0002-runtime-libsqlite3-discovery.md) (where the check runs) ·
  [ADR-0008](0008-floors-have-one-source.md) (where the floor is written)

## Context

What ships where:

| Where | SQLite | How we know |
|---|---|---|
| Ubuntu 22.04 (this host is Pop!_OS 22.04) | 3.37.2 | measured, 2026-11-13 |
| Debian 12 | 3.40.1 | not measured |
| Ubuntu 24.04, GitHub's `ubuntu-24.04` runner | 3.45.1 | measured, 2026-11-13, on CI's first run ([research/ci-runner/](../research/ci-runner/)) |
| the host's Guix home profile | 3.53.1 | measured, 2026-11-13 |
| the maintainer's Mac | 3.51.0 | the assessment |
| macOS 14 and 15 | believed 3.43.x | not measured (brief D7) |

What the versions bring that v1 uses:

| Version | Feature |
|---|---|
| 3.20.0 | `sqlite3_prepare_v3` |
| 3.37.0 | `sqlite3_changes64`, `sqlite3_total_changes64`, `SQLITE_OPEN_EXRESCODE` |
| 3.38.0 | `sqlite3_error_offset`; JSON functions built in by default |
| 3.45.0 | JSONB |

## Decision

1. **The floor is 3.45.1.** After loading, `sqlite3_libversion_number` must be at least 3045001.
   A lower version is refused as `below-floor` (ADR-0002), naming the path, the version and the
   override.
2. **v1 binds only entry points that exist at the floor.** A newer one is bound only as an
   optional entry point (ADR-0002, decision 3), whose absence is reported where it is used.
3. **CI tests the floor** in the `floor` lane, against a 3.45.1 amalgamation compiled by CI. The
   `main` job tests the runner's own build, also 3.45.1.

### Rejected

- **3.37.2,** Ubuntu 22.04's. It lacks JSONB and `sqlite3_error_offset`.
- **3.40.1,** Debian 12's. It lacks JSONB.
- **The newest release.** It would exclude Ubuntu 24.04 and CI's own runner.

## Consequences

- **Ubuntu 22.04, Debian 12, and Macs below the floor need the override,** pointing at a newer
  SQLite. That covers this host's system library.
- **JSONB is always available,** and FTS5 is wherever the build enables it (brief §2.6).
- **Raising the floor** makes the edits ADR-0008 lists.

## Amendment, 2026-11-14: decision 3 is built (M1 slice 5)

- **The `floor` lane compiles the floor itself,** from sqlite.org's autoconf tarball, which holds
  the same amalgamation as the zip, byte for byte, and needs only `tar`. Before compiling, it
  checks the archive against its pin, and `sqlite3.c` against the SHA3-256 the release's log
  publishes. Then `check-sqlite.sh` holds the build's version, source id and every compile option
  before the suites load it through the override.
- **The `current` lane does the same at 3.54.1.**
- **Before CI:** with both builds, compiled in the Guix container with the lanes' flags,
  `make test` passed 25 of 25 suites. See [the log](../m1-slice-5-mutation-log.md).

## Amendment, 2026-11-17: FTS5 on the current lane (M4's plan)

Accepted by the maintainer on 2026-11-17 ("Accept all"), proposed in M4 slice 0 ([the M4 plan](../2026-11-17-m4-plan.md), §2 and §4.5).

- **The consequence's "FTS5 is wherever the build enables it" held, and CI's compiled lanes
  enabled it nowhere:** `build-sqlite.sh` compiled SQLite's defaults, so `floor` and `current` had
  no FTS5, where Guix's, Ubuntu's (`main`), Apple's and Homebrew's have it (M4's pre-work).
- **The `current` lane compiles with `-DSQLITE_ENABLE_FTS5`** (the maintainer's Q1, "FTS5 on
  current only"). Built so, 3.54.1 lists one more option, `ENABLE_FTS5`, after
  `DIRECT_OVERFLOW_READ`, 39 for 38 (M4's research, F0). `check-sqlite.sh`'s `current` list and
  `test-ci-sqlite`'s copy move with it. Each lane's cache key moves by itself, since both hash
  `build-sqlite.sh`; the workflow doesn't change.
- **The `floor` lane keeps SQLite's defaults,** so a real library runs the suites' path for a
  library without FTS5. The FTS5 suite chooses its rows by `sqlite-compile-option?
  "ENABLE_FTS5"`, held to `pragma_module_list`, names FTS5 unavailable, never silently, and
  asserts the refusal in their place, code `error` at the `create virtual table`'s step, as the
  memory check names itself unavailable on a library that keeps no count
  ([ADR-0005](0005-memory-gate.md), amended).
- **JSON is in every library measured,** the floor's included, and alike there but for
  `json_pretty`, which arrived in 3.46.0. The JSON suite uses the floor's functions alone (F3).
