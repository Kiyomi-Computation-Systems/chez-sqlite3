# ADR-0008: The floors have one source, `packaging/floors.sexp`

- **Status:** Accepted (the harness plan, 2026-11-13)
- **Date:** 2026-11-13
- **Scope:** every statement of the Chez and SQLite floors
- **Related:** chez-curl ADR-0016, which this copies · [ADR-0001](0001-bind-libsqlite3-directly.md)
  (the Chez floor) · [ADR-0003](0003-sqlite-floor-3-45-1.md) (the SQLite floor)

## Context

A floor gets written in several places: the code that enforces it, the README that promises it,
and CI, which builds at it. When those places drift apart, the README promises a version the code
refuses, or CI tests a version nobody supports. chez-curl also found that a job-level `env:` could
redefine a floor that CI wrote as a variable, and a text check couldn't see it.

## Decision

1. **`packaging/floors.sexp` holds the floors** as one datum: `((chez "10.4.0") (sqlite "3.45.1"))`.
   The keys are exactly `chez` and `sqlite`, in that order. Each version is three numbers of ASCII
   digits, with no leading zero.
2. **`make check-floors` holds the prose to the file,** and `make test` runs it. README.org's
   `** Requirements` section must hold the list lines the file calls for.
3. **CI states no floor.** `scripts/ci/floor.sh NAME` prints one floor from the file, failing
   closed unless the file has exactly one well-formed entry for NAME. Build scripts read their
   floor through it. `check-floors` fails if any workflow line holds a floor's version text.
4. **The code is held to the file by behaviour, not text.** The SQLite check must accept 3.45.1
   (3045001) and refuse 3.45.0 (3045000), with both rows built from the file. The Chez floor's
   check is designed with brief D1.
5. **`check-test-fails` plants a README that disagrees with the file,** and `make test` must fail
   on it, naming the line.

### Rejected

- **Generating the code's floors from the file.** A library contains its own code (AGENTS.md).
  Checking behaviour gets the same guarantee.
- **Floors as CI variables.** A job can redefine one, and no text check sees it.

## Consequences

- **Changing a floor edits** the file, the README's lines, the code's constant, and the literal
  test rows that name the old floor. Each place left behind fails by name.
- **CI's cache keys hash the file** with each build script, so changing a floor rebuilds.
