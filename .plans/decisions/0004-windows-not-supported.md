# ADR-0004: Windows is not supported

- **Status:** Accepted (AGENTS.md, 2026-11-13). Amended 2026-11-20 in M5's plan, proposed: what a
  release claims ([amendment](#amendment-2026-11-20-what-a-release-claims-m5s-plan)).
- **Date:** 2026-11-13
- **Scope:** chez-sqlite3, until a later decision record reverses this one
- **Related:** chez-curl ADR-0004, which this copies ·
  [ADR-0002](0002-runtime-libsqlite3-discovery.md)

## Context

AGENTS.md names macOS and Linux, on amd64 and arm64, and says Windows is not supported. The
family's earlier projects deferred Windows but kept their designs open to it. chez-curl
deferred it outright.

## Decision

**chez-sqlite3 neither supports nor tests Windows,** and it spends no design effort keeping
Windows possible. There are no Windows code paths, no Windows CI, and no abstraction that exists
only so Windows could be added later.

## Consequences

- **The supported platforms are Linux and macOS, on amd64 and arm64.** CI is Linux only
  (AGENTS.md). macOS is checked by hand, on the maintainer's Mac.
- **Windows falls under ADR-0002's "any other platform".** Only the override works there, and
  nothing promises or tests that it does.
- **Assumptions that hold only off Windows need no flag:** POSIX paths and `/proc/self/maps`
  (ADR-0002), for example.
- **Reversing this takes its own decision record, and real work.**

## Amendment, 2026-11-20: what a release claims (M5's plan)

Proposed in M5 slice 0 ([the M5 plan](../2026-11-20-m5-plan.md), §2;
[ADR-0022](0022-the-first-release.md), decision 8), by the maintainer's answer to M5's pre-work,
Q6, "What ran" (2026-11-20).

- **The consequences' "supported platforms" are the aim; a release claims what ran.** 0.1.0
  claims Linux on x86_64, in CI and in the Guix container, and macOS on arm64, by the
  maintainer's hand runs, each with the SQLites the suites ran against there.
- **Linux on arm64, macOS on amd64, and macOS 14 and 15 haven't run the suites,** and README.org
  and the changelog's Known limitations say so. The SQLite of macOS 14 and 15 is believed older
  than the floor, so discovery would refuse it as `below-floor`, the override its remedy
  ([ADR-0002](0002-runtime-libsqlite3-discovery.md)'s consequences;
  [ADR-0003](0003-sqlite-floor-3-45-1.md)).
- **No job is added for them.** A Linux arm64 runner is still Linux, so this record doesn't bar
  one; it would be a job of its own, changing `check-ci`'s shape and the required checks
  ([ADR-0005](0005-memory-gate.md)). A later release claims a platform once the suites have run
  there.
