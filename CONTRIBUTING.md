# Contributing to chez-sqlite3

Thanks for helping. A **small fix**, such as a typo, a doc fix, or a bug with
a test that shows it, needs only the checks below. **Bigger work**, such as a
new export, a change to what a call returns or raises, or a new platform,
starts as an issue, so the design is agreed before the code is written. The
library hands C pointers to SQLite and keeps them safe for you; a change to
how it does that is a design decision, not a fix.

## Setup

The tests need more than the library does: [README.org's
Requirements](README.org) list them. Then, from a clone:

```sh
git clone https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git
cd chez-sqlite3
git submodule update --init --recursive
make test
```

The submodule is chez-srfi, for the tests' SRFI-64 alone. `make help` lists
every target. `make build` names the SQLite library the tests will load, and
`CHEZ_SQLITE3_LIBRARY` names another, by its absolute path.

**On Guix,** `scripts/guix-env` runs a pinned container with every tool:
`scripts/guix-env make test`. It has no git, and no network but loopback, so
fetch, commit and push on the host. `make check-guix`, on the host, tests it.

## The checks

CI runs seven jobs on every pull request, on Linux x86_64. Keep them green:

- `main`: `make test`, which runs every suite, with `check-pins`,
  `check-floors`, `check-test-fails`, `check-variadic`, `check-dev` and
  `check-clean`.
- `memory-1` and `memory-2`: every suite under Valgrind, in two shards,
  after `make check-memory-gate` shows the gate fails on a planted overrun
  and leak.
- `nothreads`: `make check-nothreads`, on a Chez built without threads,
  which every library must refuse.
- `floor` and `current`: `make test` on SQLite built from source, at the
  oldest version supported and at the current release; `current` runs it
  once more on a build without extension loading.
- `site`: `make check-site` and `make site`, on Ubuntu's Chez: the docs site
  renders, and its links and anchors resolve.

**macOS isn't in CI.** The suites run on a Mac, with Apple's SQLite and
Homebrew's, before each release. If you touch how the library is found
(`src/chez-sqlite3/private/discovery.sls`) or how a C function is bound, run
`make test` on a Mac too, or say in the pull request that you couldn't.

## When you change…

- **An export:** give it a comment with its type, Typed Racket style, and an
  entry in `docs/reference.md`. `test-reference` fails until the two
  signatures agree.
- **A suite:** a `tests/test-*.sps` ends with
  `(exit (suite-exit-status runner))`, or `make check-suites` fails. Add it
  to `MEMORY_SUITES_1` or `MEMORY_SUITES_2` in the Makefile, whichever takes
  less time on CI: `make test` fails, naming it, until it is in one.
- **`docs/`:** it is for people using the library. Keep it short and plain.
  A new page goes in README.org's Documentation list and in `site/pages.sls`,
  the site's nav, in the same order: `make check-site` fails until both name
  it. `make test` runs every whole program on a page, and each must print
  what its text block shows.
- **The floors:** the oldest Chez and SQLite supported are written once, in
  `packaging/floors.sexp`. `make check-floors` fails if README.org's
  Requirements disagree, or if a page, a workflow or a CI script names one.
- **A workflow:** `make check-ci` holds `ci.yml` to one shape and `pages.yml`
  to its copy. Change `tests/check-ci.sh` and its suite with them.
- **The Makefile:** give each new target a `## ` description and a place in
  `.PHONY`, or `make check-help` fails.
- **The chez-srfi pin:** `make check-pins` fails unless `Akku.lock`, the
  gitlink and the checkout name one commit.
- **What ships:** a release archive is `git archive` of the tag, which leaves
  out `.plans/` and `AGENTS.md`. A new top-level path that is only for
  development needs an `export-ignore` rule in `.gitattributes` too.

## Code

- Libraries are R6RS `.sls` files under `src/`, and each holds its own code:
  no shared include files. R6RS forbids assigning an exported variable, so
  reach mutable state through procedures.
- The public library is `(chez-sqlite3)`. Internals live under
  `(chez-sqlite3 private …)` and never escape it; `make check-seam` holds
  each library's imports.
- **Functional core, imperative shell:** pure code decides what to do, and a
  thin shell makes the C calls.
- **Handle C safely:** check that a value fits its C type before the call,
  raise nothing inside a critical section, and unlock exactly what was
  locked. [AGENTS.md](AGENTS.md) has the full list, and the trap behind each.
- The code is written fresh. Thunderchez's `sqlite3.sls` is Apache-2.0, and
  this project is BSD-3: read it for ideas if you like, but copy none of it.
- The library runs on Linux and macOS, on x86_64 and arm64. Windows isn't
  supported.
- A comment in `src/`, `tests/`, the Makefile, `scripts/` or `packaging/` is
  for a developer reading the code: no plans, dates or issue numbers. A bare
  `ADR-NNNN` may point to why.

## Tests

- Write the test first, and watch it fail before you make it pass. A test
  that passes whether the code is right or wrong is worse than none.
- A change in behaviour comes with a test that fails without it.
- Assert whole values, not substrings, and what was raised, not only that
  something was.
- Chez fixes no order for a call's arguments, nor `map` for its calls:
  depend on neither.
- Test what the code does, never what a comment says.

## Pull requests

- Titles follow [Conventional Commits](https://www.conventionalcommits.org):
  `feat:`, `fix:`, `docs:`, `test:`, `ci:`. Pull requests are
  squash-merged, so the title becomes the commit's.
- Say where you ran `make test`, and on which SQLite: CI runs Linux x86_64
  alone.
- A change users can see gets an entry under `## [Unreleased]` in
  [CHANGELOG.md](CHANGELOG.md).
- Releases are the maintainer's. A release moves `Akku.manifest`,
  CHANGELOG.md and the clone lines together, and `test-manifest` fails one
  that moves them apart.

## How the project is developed

Each lasting decision has a numbered record in `.plans/decisions/`, and
`.plans/progress.md` says where the project stands. [AGENTS.md](AGENTS.md)
holds the rules in full, and the lessons behind them. Following them is
encouraged for features, not demanded of small fixes. Neither ships in a
release archive; read them in the repository.

## Security

Don't open a public issue for a suspected vulnerability.
[SECURITY.md](SECURITY.md) says how to report it privately.
