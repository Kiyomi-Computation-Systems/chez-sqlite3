# Contributing to chez-sqlite3

Thanks for helping. A **small fix**, such as a typo, a doc fix, or a bug with
a test that shows it, needs only the checks below. **Bigger work**, such as a
new export, a change to what a call returns or raises, or a new platform,
starts as an issue, so the design is agreed before the code is written. The
library hands C pointers to SQLite and keeps them safe for you; a change to
how it does that is a design decision, not a fix.

## Setup

The tests need more than the library does: [README.org's
Requirements](README.org) list them. Ubuntu 24.04's `chezscheme` is too old:
build Chez from source, as `scripts/ci/build-chez.sh PREFIX` does for CI, or
use Guix's or Homebrew's. `packaging/debian-prereqs.txt` lists the packages
CI's test jobs install. Then:

```sh
git clone https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git
cd chez-sqlite3
git submodule update --init --recursive
make test
```

The submodule is chez-srfi, for the tests' SRFI-64 alone. `make help` lists
every target, and `make test SUITES=tests/test-NAME.sps` runs one suite.
`make build` names the SQLite library the tests will load; the quick start's
[Running the tests](docs/quickstart.md#running-the-tests) says how to test
another.

**On Guix,** `scripts/guix-env` runs a pinned container with every tool:
`scripts/guix-env make test`. It has no git, and no network but loopback, so
fetch, commit and push on the host. `make check-guix`, on the host, tests it.

## The checks

CI runs seven jobs on every pull request, on Linux x86_64. Keep them green:

- `main`, in order: every action pinned to a commit; `make build`, which
  must accept the runner's SQLite, found by discovery; `make test`; the
  checks it leaves out, `make check-pins`, `make check-test-fails`,
  `make check-variadic`, `make check-dev` and `make check-clean`; and the
  Guix launcher's own tests.
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

**macOS isn't in CI,** and no macOS job will be added. The suites run on a
Mac, with Apple's SQLite and Homebrew's, before each release. If you touch
how the library is found (`src/chez-sqlite3/private/discovery.sls`) or how a
C function is bound, run `make test` on a Mac too, or say in the pull
request that you couldn't.

## When you change…

- **An export:** give it a comment with its type, Typed Racket style, and an
  entry in `docs/reference.md`. `test-reference` fails until the two
  signatures agree.
- **A suite:** a `tests/test-*.sps` ends with
  `(exit (suite-exit-status runner))`, or `make check-suites` fails. Add it
  to `MEMORY_SUITES_1` or `MEMORY_SUITES_2` in the Makefile, whichever took
  less time on CI (each memory job prints a `time:` line per suite).
  `make test` fails, naming it, until it is in one.
- **`docs/`:** it is for people using the library. Keep it short and plain.
  - A new page goes in README.org's Documentation list and in
    `site/pages.sls`, the site's nav, in the same order and under the same
    label, which is also the page's `# ` title.
  - `make test` fails until README.org links the page, and `make check-site`
    until the nav matches. `make check-site` isn't part of `make test`: it
    needs the cmark-gfm library, and `make site-deps`, run once on the host,
    which fetches chez-cmark-gfm.
  - `make test` runs a page's whole programs and its `scheme run` blocks.
    Each must exit 0 with nothing on stderr, and print the text block that
    follows it, if one does.
- **The floors:** the oldest Chez and SQLite supported are written once, in
  `packaging/floors.sexp`. `make check-floors` fails if README.org's
  Requirements disagree, or if any other line of README.org, a page, a
  workflow or a CI script names one.
- **A workflow:** `.github/workflows` holds `ci.yml` and `pages.yml` alone.
  `make check-ci` holds `ci.yml` to one shape and `pages.yml` to its copy;
  change `tests/check-ci.sh` and its suite with them. Each `uses:` names a
  full commit SHA, its tag in a comment.
- **The Makefile:** give each new target a `## ` description and a place in
  `.PHONY`: `make check-help` fails when it has one without the other. It
  also reads the code spans of this file, SECURITY.md, and the pull request
  and bug report templates: it fails when a span's `make` command starts
  with a target the Makefile lacks.
- **The chez-srfi pin:** `make check-pins` fails unless `Akku.lock`, the
  gitlink and the checkout name one commit.
- **What ships:** a release archive is `git archive` of the tag, which leaves
  out `.plans/` and `AGENTS.md`. `test-manifest` holds `.gitattributes` to
  exactly those two rules, so leaving out another path is a design change:
  raise it in an issue first.

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
  locked. AGENTS.md has the full list, and the trap behind each.
- The code is written fresh. Thunderchez's `sqlite3.sls` is Apache-2.0, and
  this project is BSD-3: read it for ideas if you like, but copy none of it.
- Linux and macOS, on x86_64 and arm64, are supported, but only Linux on
  x86_64 and macOS 26 on arm64 have run the suites (README.org's Status).
  Windows isn't supported.
- A comment in `src/`, `tests/`, the Makefile, `scripts/` or `packaging/` is
  for a developer reading the code: no plans, dates or issue numbers. A bare
  `ADR-NNNN` may point to why.

## Tests

- Write the test first, and watch it fail before you make it pass. A test
  that passes whether the code is right or wrong is worse than none.
- A change in behaviour comes with a test that fails without it.
- Assert whole values, not substrings, and what was raised, not only that
  something was.
- SRFI-64 turns a raise in a test's actual expression into `#f`: never
  expect `#f` from code that can raise. `guard` answers the body's value
  when nothing raises, so give that case a sentinel of its own.
- Read a library's version and options through the FFI, never from the
  `sqlite3` command, which can carry its own SQLite.
- Chez fixes no order for a call's arguments, nor `map` for its calls:
  depend on neither.
- Test what the code does, never what a comment says.

## Pull requests

- Commit messages and pull request titles follow
  [Conventional Commits](https://www.conventionalcommits.org): `feat:`,
  `fix:`, `docs:`, `test:`, `ci:`. Pull requests are squash-merged, and
  either can become the squash commit's title.
- Say where you ran `make test`, and on which SQLite: CI runs Linux x86_64
  alone.
- A change users can see gets an entry under `## [Unreleased]` in
  [CHANGELOG.md](CHANGELOG.md).
- Releases are the maintainer's. A release moves `Akku.manifest`,
  CHANGELOG.md, and the clone lines in README.org and `docs/` together, and
  `test-manifest` fails one that moves them apart.

## How the project is developed

Each lasting decision has a numbered record in `.plans/decisions/`, and
`.plans/progress.md` says where the project stands. [AGENTS.md](AGENTS.md)
holds the rules in full, and the lessons behind them. Following them is
encouraged for features, not demanded of small fixes, but a rule a check
enforces binds every change. Neither ships in a release archive; read them
in the repository.

## Security

Don't open a public issue for a suspected vulnerability.
[SECURITY.md](SECURITY.md) says how to report it privately.
