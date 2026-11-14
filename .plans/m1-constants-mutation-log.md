# M1 constants mutation log

Evidence that `tests/test-constants.sps` fails through the property each row guards
([M1 plan](2026-11-13-m1-plan.md) §4, "The header check"; ADR-0001, ADR-0013 decision 4).

Every mutation ran in its own copy of the worktree under the session scratchpad, without `.git` or
`build/`, through that copy's own `scripts/guix-env`, and the counts are read from the outputs. Each
ran twice: against the container's header (SQLite 3.53.1, so completeness is a subset check), and
against the floor's own header, 3.45.1's `sqlite3.h` from sqlite.org's amalgamation 3450100, put first
on `C_INCLUDE_PATH` (so completeness is the exact check, as on CI's `main` job).

Baseline: 30 passed, on both headers. The 3.53.1 run prints one line, `completeness checked against a
subset only`; the floor-header run prints none.

Red run, before the real table: a stub with `sqlite-open-create` as 8 and the `ok-symlink` row
missing: 28 passed, 2 failed (the values row, naming `sqlite-open-create is SQLITE_OPEN_CREATE`, 8
against 4; and the count row, 107 against 108).

| Mutation | Guards | 3.53.1 header | Floor header |
|---|---|---|---|
| C1: `ioerr-short-read` is 523, not 522 | a value is the header's | 26 passed, 4 failed: values (naming the row), the unique-values row, the extended-code row, and the name-of-code row | the same 4 |
| C2: the `ok-symlink` row dropped | no code is missing | 29 passed, 1 failed: **the count row alone**; the subset check cannot see a dropped row | 28 passed, 2 failed: the count row and the exact completeness row |
| C3: an export with no row (`sqlite-open-extra`) | every export has a row | 29 passed, 1 failed: the exports row | the same |
| C4: `ioerr_short_read` for `ioerr-short-read` | a name is its C name, hyphenated | 28 passed, 2 failed: the name-shape row and the extended-code row. **The values row passes**: `ioerr_short_read` upcases to the same C name | the same 2 |
| C5: the recogniser ignores the shifted form | the macros the header defines include the extended codes | 27 passed, 3 failed: both recogniser rows with the shifted form, and the completeness row | 27 passed, 3 failed: the same recogniser rows, and the exact completeness row |
| C6: completeness skipped on a floor header (`completeness-plan` answers `subset` for equal numbers), and `ok-symlink` dropped | the floor's header is held to the exact set | 28 passed, 2 failed: the count row and the plan row | the same 2. **The completeness row passes**, as does everything but the count and the plan row: the plan row is what holds the exact check on |

Notes:

- C2 on 3.53.1 shows what a subset check cannot do. A dropped row is caught there by the count (108
  codes, 117 names) alone. A table that drops one row and adds another would pass on a newer header,
  and fail on CI's floor header.
- C4 shows why the name-shape row exists: the value check derives the C name from the Scheme name, and
  `_` and `-` derive the same name.
- C6 shows the plan row guards the floor-header path. With the check turned to `subset`, the real
  3.45.1 header passes completeness although a code is missing from the table.

Not mutated, only run once by hand: a missing compiler (`CC=/nonexistent/cc`) and a header the
compiler cannot find (`CC="gcc -nostdinc"`) each fail 5 rows by name (the oracle rows, the values rows
and the completeness row) and exit 1. Neither skips.
