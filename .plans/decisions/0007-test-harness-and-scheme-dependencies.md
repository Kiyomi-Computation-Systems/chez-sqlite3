# ADR-0007: Tests use SRFI-64 from a vendored chez-srfi pinned in Akku.lock, and the suite rules are checks

- **Status:** Accepted (the harness plan, 2026-11-13); amended 2026-11-13 with what M0 slice 2
  built ([amendment](#amendment-2026-11-13-what-m0-slice-2-built)), and after M0's closing review
  ([amendment](#amendment-2026-11-13-check-ci-is-a-prerequisite-and-is-held-as-one-m0s-closing-review))
  ; amended 2026-11-20 in M5's plan, accepted: the site's dependency, the clone lines and the
  archive
  ([amendment](#amendment-2026-11-20-the-sites-dependency-the-clone-lines-and-the-archive-m5s-plan))
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

## Amendment, 2026-11-13: `check-ci` is a prerequisite, and is held as one (M0's closing review)

- **`make test` runs `check-help`, `check-suites`, `check-floors` and `check-ci` first.** Decision
  4 lists three; M0 slice 4 added `check-ci` (ADR-0005, amended).
- **`make check-test-fails` holds that place,** with an eleventh plant beside decision 4's ten:
  - a workflow whose `memory` job carries a job-level `continue-on-error`, which `make test` must
    fail on `check-ci`'s lines, whole, running no suite.

  The closing review removed `check-ci` from the prerequisites, and every check still passed.
  `check-help` has no plant: CI's `main` job runs it by name, and `check-ci` holds that line
  whole.
- **Temporary files go in a directory of the process's own, under `$TMPDIR`,** not at fixed
  paths under `build/` (this record's slice 2 amendment). The brief's §7 said `build/`; it now
  follows this record.

## Amendment, 2026-11-20: the site's dependency, the clone lines and the archive (M5's plan)

Proposed in M5 slice 0 ([the M5 plan](../2026-11-20-m5-plan.md), §4.2, §4.3, §4.5 and §4.6;
[ADR-0022](0022-the-first-release.md), decisions 3, 4 and 6), by the maintainer's answers to M5's
pre-work, Q1, "Site from v0.1.0", and Q3, "Exclude .plans/ and AGENTS.md" (2026-11-20).
Accepted by the maintainer on 2026-11-20 ("Accept all").

- **Decision 2's "chez-srfi as the only development dependency" gains a second:**
  chez-cmark-gfm, at `^2.0.0`, for the docs site alone, as chez-curl ADR-0042's decision 2 has
  it. Its `Akku.lock` entry is chez-curl's, byte for byte, which `akku lock` wrote for a sibling;
  `akku` isn't installed here. Nothing under `src/`, nor any `tests/test-*.sps`, imports it, so
  `make test` needs none of it.
- **`make site-deps` gets it as the lock pins it,** through `scripts/fetch-akku-lock`, which
  downloads the locked archive, checks its sha256 and unpacks it under `build/`. Like the
  submodule's checkout, it runs on the host or in CI, never in the container, and decision 3's
  `make deps` still never fetches. `make check-site-deps` holds the script to an offline test of
  its own.
- **`check-pins` still reads chez-srfi's line alone:** its `sed` read `7879b52` from chez-curl's
  lock of two projects (the M5 plan, P2).
- **`tests/test-manifest.sps` holds the new shape:** `depends/dev` exactly chez-srfi and
  chez-cmark-gfm, each in its pinned range; `Akku.lock` exactly those two projects, each url
  naming its version and each carrying a sha256. Watched failing on the old manifest and lock.
- **The site's suites, `tests/site-*.sps`, exit through `(site-testing)`'s `site-exit-form`,**
  and `make check-suites` holds each to it, as it holds each `tests/test-*.sps` to the shared
  form. They run on Ubuntu's Chez, below the floor, so they import nothing under `src/`:
  `(chez-sqlite3-testing)` reads the counters, which import
  `(chez-sqlite3 private require-threaded)`. `make check-site` runs them; `make test` doesn't.
- **The tripwire becomes the check the harness plan owed** (its §6, slice 2): every line of
  README.org, or of any file under `docs/`, that holds `git clone` is, after its leading spaces,
  exactly
  `git clone --branch vX.Y.Z https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git`,
  X.Y.Z the manifest's version; while the manifest says 0.0.0, with no release, the same line
  without `--branch vX.Y.Z`. README.org and the quick start hold one each. So a release bumps
  the manifest, the changelog and the clone lines together, or fails.
- **`tests/test-manifest.sps` holds `.gitattributes`:** its lines, comments and blank lines
  aside, are `/.plans export-ignore` and `/AGENTS.md export-ignore`, each as its two words, in
  that order. `git archive` reads the archived tree's file, so the tag's archive follows the
  tag's (the M5 plan, P1).
- **A release archive is no test tree:** its `vendor/chez-srfi` is empty, which decision 3's
  `make deps` refuses, and it holds no `.plans/`, which `test-conventions` reads. The suites run
  from a clone, after the consequences' `git submodule update`.
