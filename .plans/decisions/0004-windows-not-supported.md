# ADR-0004: Windows is not supported

- **Status:** Accepted (AGENTS.md, 2026-11-13)
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
