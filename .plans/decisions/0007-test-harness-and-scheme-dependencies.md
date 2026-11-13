# ADR-0007: Tests use SRFI-64 from a vendored chez-srfi pinned in Akku.lock, and the suite rules are checks

- **Status:** Accepted (the harness plan, 2026-11-13); amended 2026-11-13 with what M0 slice 2
  built ([amendment](#amendment-2026-11-13-what-m0-slice-2-built))
- **Date:** 2026-11-13
- **Scope:** chez-sqlite3's suites and Scheme dependencies
- **Related:** chez-curl ADR-0015, which this copies · [ADR-0006](0006-pinned-guix-container.md)
  (no network, no git) · [ADR-0005](0005-memory-gate.md) (the counters in `suite-exit-status`)

## Context

The family tests with SRFI-64 from a chez-srfi submodule at
`7879b527f267f067416552fb989135ad1b4ea436`, declared in `Akku.manifest` and pinned in `Akku.lock`.
chez-curl found that rules written only as prose got broken. A suite with no exit line passed while
failing, a suite that ran no tests passed, and a timeout was optional. So it made each rule a
check. AGENTS.md carries those rules here.

## Decision

1. **SRFI-64 comes from a chez-srfi submodule under `vendor/`,** at `7879b52`.
2. **Akku declares and pins it.** `Akku.manifest` names chez-srfi as the only development
   dependency, with no `depends` and no scripts. `Akku.lock` pins the same commit.
   `make check-pins` fails when the lock, the superproject's gitlink and the checkout disagree. It
   runs on the host and in CI, never in the container. `tests/test-manifest.sps` holds the
   manifest, the lock and CHANGELOG.md's latest version to each other.
3. **`make deps` never fetches.** It links the checked-out submodule into `build/scheme-libs`. An
   empty submodule fails it, pointing at `git submodule update --init` on the host.
4. **The suite rules are checks:**
   - **`make check-suites`** reads every `tests/test-*.sps` as data. Each must end with the shared
     form, `(exit (suite-exit-status runner))`, from `tests/chez-sqlite3-testing.sls`. Before that,
     a suite may exit only with `(exit 1)`. `suite-exit-status` answers 0 only when the runner saw
     a pass, no failure, no unexpected pass, and zero counts (ADR-0005). It answers 0 or 1, never a
     count.
   - **`make test`** runs `check-help`, `check-suites` and `check-floors` first. It then runs every
     suite, even after a failure, each under `timeout --foreground`. Exit 124 is reported as HUNG.
     It fails if any suite failed or hung, or if there were no suites.
   - **`make check-test-fails`** plants each of these in a copy of the tree, and `make test` must
     fail on each by name, then go on:
     - a failing suite;
     - a suite that runs no test;
     - one that hangs;
     - one without the shared form;
     - one that exits 0 early;
     - one with a nested exit;
     - an empty file;
     - one whose tests pass but which leaks a counted block;
     - a README that disagrees with the floors;
     - an empty glob.
5. **Probes and helpers sit outside the `test-*` glob.** A probe of a refusal prints
   `(reason . symbol)`, and tests assert the symbol, never error text.

### Rejected

- **Fetching inside `make deps`.** It can't work in a network-less container.
- **Leaving the rules as prose.** Each was broken somewhere in the family while it was only prose.

## Consequences

- **A fresh clone runs `git submodule update --init --recursive` on the host** before its first
  `make deps`.
- **Bumping chez-srfi takes two edits,** the submodule and `Akku.lock`, and `check-pins` holds them
  together.
- **A suite can't pass silently** by forgetting its exit line, running no tests, hanging or
  leaking.

## Amendment, 2026-11-13: what M0 slice 2 built

- **The leaks plant raises a count itself.** Decision 4's "leaks a counted block" is, for now, a
  suite that calls `count-up! 'statement` and never lowers it. It proves the path from the counts
  through `suite-exit-status` to `make test`, not that anything counts: no library makes a native
  object yet. M1, with the first constructor, replaces it with a suite that leaks through that
  constructor. Until then, "a suite can't pass silently by leaking" holds only for objects whose
  constructors count.
- **`make test` refuses a `TEST_TIMEOUT` that isn't a positive whole number,** before any suite
  runs. GNU `timeout` reads 0 as no limit, so `TEST_TIMEOUT=0` would have removed the bound
  silently. The host-side tests hold the default to a positive whole number and the refusal to
  0, a leading zero, a fraction and empty.
- **Every test helper comes with its first consumer,** and a suite uses the shared helper rather
  than a stand-in of its own. The slice's review found stand-ins writing fixed paths under
  `build/`, so two `make test` runs in one tree collided. Reproduced: three of six concurrent runs
  failed.
- **The copies `check-test-fails` and the host-side tests make leave out `.claude/`,** as
  `check-clean`'s does. It is Claude Code's local state, and can hold whole worktrees.
