# ADR-0003: The SQLite floor is 3.45.1

- **Status:** Accepted (the maintainer, 2026-11-13)
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
