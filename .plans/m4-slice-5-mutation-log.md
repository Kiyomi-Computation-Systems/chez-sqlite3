# M4 slice 5 mutation log

Evidence that each rule slice 5's suites and scripts claim to guard fails through the property it
names ([the M4 plan](2026-11-17-m4-plan.md) §5, slice 5, §4.5, and §4.7's FTS5 plants). Format of
[the M3 slice 6 log](m3-slice-6-mutation-log.md).

An Opus agent built the slice from the lead's brief, in its worktree, on `m4-slice-5-fts5-json`
from slice 0's head `fd4831c`, beside slices 1 and 2 in worktrees of their own. Every run was in
the Guix container: Chez 10.4.0 (`ta6le`, threaded), gcc 16.2.0, Valgrind 3.27.0, x86_64. The lead
then rebased it onto `3488963`, the close fix, and took its workaround out
([after the close fix](#after-the-close-fix-the-lead)).

## What the slice adds

- **The `current` lane compiles FTS5 in** (ADR-0003, amended; the maintainer's Q1):
  - `scripts/ci/build-sqlite.sh`: the compile line by role, `-DSQLITE_ENABLE_FTS5` on the
    `current` role's alone; its header lists the flag, and no longer says both builds are SQLite's
    defaults;
  - `scripts/ci/check-sqlite.sh`: `current_options` gains `ENABLE_FTS5` after
    `DIRECT_OVERFLOW_READ`, 39 lines; its comments say the current lane is SQLite's defaults and
    FTS5 besides;
  - `.github/workflows/ci.yml`: the `current` job's comment, "compiled here as the floor's is but
    with FTS5". No other line. `tests/check-ci.sh` and `test-check-ci` are unchanged: `check-ci`
    reads the `hashFiles(` lists, which are as they were, and skips comments (its header, lines
    16 to 17 and 55 to 56). `test-check-ci` passed 439 of 439 on the changed workflow. Both lanes'
    SQLite cache keys hash `build-sqlite.sh`, so both caches are rebuilt once on CI.
- **`tests/test-ci-sqlite.sps`:** its copy of the current list, 39 with `ENABLE_FTS5`; the count
  row, 37 and 39; the current pass row's name; the floor-against-current row's hunk, now three
  changes in one; a new row, the current release built without FTS5 refused by its one line; and
  the compile line by role, `floor-flags` and `current-flags`, through `cc-call` and
  `success-row`. 80 rows to 81.
- **`tests/test-fts5.sps`, new,** 19 rows on a library with FTS5, 5 on one without (below).
- **`tests/test-json.sps`, new,** 16 rows on every library.
- **The Makefile:** both suites in `MEMORY_SUITES_1`, the shard whose suites took less time on CI,
  900 s against 986 s on run 44112097972 (the lead's figures). Shard 1 held 37 suites, shard 2 38;
  on `3488963`, with the close fix's `test-connection-close`, each holds 38.
- **`docs/reference.md`:** under `sqlite-compile-option?`, FTS5 is an option SQLite's own build
  leaves out, so check `(sqlite-compile-option? "ENABLE_FTS5")` before using it; a plain `scheme`
  block, since its output depends on the library.

## The trap the slice found: FTS5's own statements and the close (fixed by PR #36)

**`close-database!` can't close a connection that has used an FTS5 table.** FTS5 prepares
statements of its own on the connection for its shadow tables, from the `create virtual table` on,
and finalizes them only when the table is disconnected. `sqlite3_close` disconnects every virtual
table before it looks for statements (`sqlite3.c`'s `sqlite3Close`: "the v-table implementation
may be storing some prepared statements internally"). The library looks first: after finalizing
its own, it counts what `sqlite3_next_stmt` finds, sees FTS5's, and raises an assertion
violation, "the connection has statements chez-sqlite3 does not track", `(untracked-statements
N)`, the connection left open and counted (ADR-0012, decision 5, which calls such a statement "a
defect in chez-sqlite3").

- **Measured,** on Guix's 3.53.1 and on the FTS5 build of 3.54.1, through the library:
  - after `create virtual table docs using fts5(body)` alone, the close raised
    `(untracked-statements 2)`; `sqlite3_sql` of the two read `REPLACE INTO 'main'.'docs_config'
    VALUES(?,?)` and `REPLACE INTO 'main'.'docs_data'(id, block) VALUES(?,?)`;
  - after an insert and a `MATCH`, 7 statements;
  - a file holding an FTS5 table, reopened and closed untouched, closed; reopened and queried, its
    close raised `(untracked-statements 2)`. So a program that queries a persistent FTS5 table can
    never close its connection;
  - FTS3 and FTS4 do the same on Guix's library: 8 and 11 statements after a create, an insert and
    a `MATCH`. R*Tree isn't in Guix's library, so it wasn't tried;
  - `drop table` of the virtual table before the close lets it close, every count back to 0;
  - `sqlite3_close` itself, called through the FFI on a connection holding FTS5's statements,
    answered 0.
- **Reproduce,** from the worktree's root, with a file the container can see:

  ```
  cat > build/fts5-close.sps <<'EOF'
  (import (chezscheme) (chez-sqlite3))
  (define db (open-database ":memory:"))
  (execute! db "create virtual table docs using fts5(body)")
  (write (guard (e ((assertion-violation? e) (list (condition-who e) (condition-irritants e))))
           (close-database! db)
           'closed))
  (newline)
  (execute! db "drop table docs")
  (close-database! db)
  (write 'closed-after-the-drop)
  (newline)
  EOF
  scripts/guix-env sh -c '$CHEZ --libdirs src:build/scheme-libs --program build/fts5-close.sps'
  ```

  It prints `(close-database! (untracked-statements 2))`, then `closed-after-the-drop`; the same
  with `CHEZ_SQLITE3_LIBRARY` naming `build/m4-current-fts5`'s library.
- **What the suite did about it, until the close fix.** The slice touches no file under `src/`, so
  `test-fts5` worked around it and pinned it:
  - every FTS5 row runs through `with-fts5`, which drops the row's FTS5 tables before the close;
  - one row, "a connection that made and queried an FTS5 table closes, with no drop first", asserts
    the close the library should make, and is marked `(test-expect-fail 1)`. SRFI-64 counts it as
    an expected failure while the close refuses, and `suite-exit-status` counts that neither way.
    Once the close succeeds it is an unexpected pass, which fails the suite: then the mark and the
    drops go. X01 below watched that flip.
- **A candidate fix, tried in a copy only (X01, X02):** `close-connection` calls `sqlite3_close`
  first, and counts `sqlite3_next_stmt`'s statements only when it fails, raising the same
  assertion violation when it finds any, else the close's own failure. A statement the library
  doesn't track still makes `sqlite3_close` answer `SQLITE_BUSY` and leave the connection open, so
  the old refusal stands for it. In the copy, `test-connection` (63), `test-connection-cache` (21),
  `test-open-settings` (23), `test-interrupt-close` (8), `test-statement` (76) and
  `test-interrupt-database` (23) passed at their baselines; with the mark and the drops removed,
  `test-fts5` passed 19 of 19 on both FTS5 libraries, and `make test` ran 75 and passed 75 on
  Guix's library. It was not run at the floor, under the gate, or through the engine sweeps'
  reasoning about the close's section, and ADR-0012's decision 5 would need amending first: it is
  the maintainer's to decide. The maintainer chose that order, "Close first, count on failure",
  built in a PR of its own: PR #36, merged as `3488963`, which also finalizes the tracked statements
  and empties the cache before `sqlite3_close`, and amends ADR-0012 ("close first, and vouch only
  for ours").

## After the close fix (the lead)

The lead committed the builder's tree, rebased it onto `3488963`, PR #36's merge, with no
conflict, and took the workaround out in a commit of its own:
- `with-fts5` is gone: each row runs on `with-db`, `call-with-database` on `:memory:`, and closes
  with its FTS5 tables in place; `with-docs` makes `docs` there;
- the close's row, "a connection that made and queried an FTS5 table closes, with no drop first",
  is an ordinary row, its `(test-expect-fail 1)` and comment gone;
- the header says what the close does now, and why the rows can leave their tables.

**Watched failing,** in a copy, `build/lead-mut/X-old-close/`, with `connection.sls` as it was at
`d1792e4`, before the close fix: `test-fts5` failed 15 and passed 4 on Guix's library, on
`build/m4-current-fts5` and on `build/m4cf-floor-vtab` (3.45.1 with FTS3, FTS4, FTS5 and RTREE).
The 15 are every FTS5 row whose answer passes through a close, the close's row among them, and the
counts row after. The one FTS5 row that passed is the syntax error through `query`: its answer is
the query's raise: `call-with-database` raises a close's failure only when nothing else is being
raised.

**Green on the rebased tree:**

| Library | `test-fts5` | `test-json` | `make test` |
|---|---|---|---|
| Guix's 3.53.1 | 19 of 19, the rows | 16 | 76 of 76 |
| `build/m3-floor`, 3.45.1 | 5 of 5, the refusal | 16 | 76 of 76 |
| `build/m4-current`, 3.54.1, no FTS5 | 5 of 5, the refusal | 16 | |
| `build/m4-current-fts5`, 3.54.1 with FTS5 | 19 of 19 | 16 | 76 of 76 |
| `build/m4cf-floor-vtab`, 3.45.1 with every module | 19 of 19 | 16 | 76 of 76 |
| `build/m4cf-current-vtab`, 3.54.1 with every module | 19 of 19 | 16 | |

Under the gate, by its `time:` lines: `test-fts5` 11 s, 10 s and 10 s on Guix's, the floor and
the FTS5 build; `test-json` 9 s, 10 s and 10 s. None `SLOW`, each passing.

**The plants, rerun on the rebased tree before the review's fixes,** with the drivers in
[research/m4-slice-5/scripts/](research/m4-slice-5/scripts/), unchanged then: all but F10, F11,
X01 and X02, which planted the workaround and the candidate fix. 50 mutants, 48 caught, F07 and
V02 surviving as before, with the same arguments (below). The head's rerun, 49 caught, is
[on the head](#on-the-head-the-lead-after-the-m4-sessions-check). The counts move with the close's row, now
an ordinary row: F01 and F02 fail 15 rows on the floor and the plain 3.54.1, the 15 FTS5 rows,
the close's row among them, while the counts row passes; and each FV plant fails its row alone,
18 passing, on Guix's library and the FTS5 build. Every other count is as the tables below give
it. The builder's tables are of the tree before the rebase.

## The red runs

| Check | Red run | Green run |
|---|---|---|
| `make test SUITES="tests/test-fts5.sps tests/test-json.sps"`, the suites written, no shard line | `check-memory-shards` named both, in neither list, `FAILED (problems: 2)` | both in `MEMORY_SUITES_1`: "each of the 75 suites once" |
| `test-ci-sqlite`, its new rows against `fd4831c`'s scripts | 75 passed, 6 failed: the current pass row and its floors-file twin, the floor-against-current hunk, the new without-FTS5 row, and the two current build rows' compile line | 81 of 81 |
| `test-fts5`, first run, on Guix's library | 4 passed, 14 failed: every row's close raised `(untracked-statements N)`, 14 connections left open, and the memory check failed with them. The first row read `#f`: its close raised outside the row's guard | 18 passed and 1 expected failure, the close's row, once each row drops its tables and the row's guard covers the close |
| `test-json`, first run | 16 of 16 passed: the library as it stands answers JSON as F3 measured. Its rows were watched failing against the plants below, every one | 16 of 16 |
| `test-docs` with the note | no red: a fragment adds no row. D01 and D02 below watched it fail | 101 of 101, as before |

The FTS5 rows can't fail on `fd4831c`'s library either: they test values the library already
carries. Each was watched failing against a plant of its own: F01 at the floor, its value's FV
plant on both FTS5 libraries, and the library plants V01 and V04 for the rows they reach.

## Green

**`make test`: 75 of 75 on each of the three, against the baseline's 73 of 73 on Guix's library,**
twice, the second on the final tree.
Guix's 3.53.1 (the container's default); the floor, `build/m3-floor` (3.45.1); and the FTS5 build,
`build/m4-current-fts5` (3.54.1), each through `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH`.
`check-ci`, `check-floors` and `check-memory-shards` passed in each.

**The two suites on all four libraries,** plain:

| Library | `test-fts5`'s path | `test-fts5` | `test-json` |
|---|---|---|---|
| Guix's 3.53.1 | the rows | 18 passed, 1 expected failure | 16 |
| `build/m3-floor`, 3.45.1 | the refusal, "FTS5 unavailable" printed | 5 | 16 |
| `build/m4-current`, 3.54.1, no FTS5 | the refusal, printed | 5 | 16 |
| `build/m4-current-fts5`, 3.54.1 with FTS5 | the rows | 18 passed, 1 expected failure | 16 |

**Under the gate,** `make test-memory MEMORY_SUITES="tests/test-fts5.sps tests/test-json.sps"`,
by the gate's `time:` lines, twice on each library, the second on the final tree:

| Library | `test-fts5` | `test-json` |
|---|---|---|
| Guix's 3.53.1 | 11 s, 11 s | 9 s, 10 s |
| the floor, 3.45.1 | 10 s, 11 s | 10 s, 10 s |
| the FTS5 build of 3.54.1 | 10 s, 11 s | 10 s, 10 s |

Each passed with no Valgrind error and nothing lost, the memory check passing; none `SLOW`. On
the floor the suite's log, `build/memory/test-fts5.log`, holds the `FTS5 unavailable` line, and its
refusal row passed; on the other two, the rows and the expected failure.

## F0: the lane's check on both 3.54.1 builds

`check-sqlite.sh --current`, with the lane's env for the call, `ROOT` the worktree:

```
### check-sqlite.sh --current on build/m4-current
check-sqlite.sh: ROOT/build/m4-current/lib/libsqlite3.so.0's compile options are not the 39 of the pinned current SQLite, line for line:
--- expected
+++ library
@@ -14,7 +14,6 @@
 DEFAULT_WAL_SYNCHRONOUS=2
 DEFAULT_WORKER_THREADS=0
 DIRECT_OVERFLOW_READ
-ENABLE_FTS5
 MALLOC_SOFT_LIMIT=1024
 MAX_ATTACHED=10
 MAX_COLUMN=2000
(exit 1)
### check-sqlite.sh --current on build/m4-current-fts5
check-sqlite.sh: ROOT/build/m4-current-fts5/lib/libsqlite3.so.0 is SQLite 3.54.1 (3054001), source id 2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76: the pinned current SQLite
check-sqlite.sh: it is threadsafe (1), and its 39 compile options are the pinned current SQLite's, line for line:
  ATOMIC_INTRINSICS=1
  COMPILER=gcc-16.2.0
  …the 37 lines between, ENABLE_FTS5 after DIRECT_OVERFLOW_READ…
  THREADSAFE=1
check-sqlite.sh: /gnu/store/5v2iykmw4z9r6wvq5kqbh2yx1zz1ncan-profile/bin/gcc finds <sqlite3.h> at ROOT/build/m4-current-fts5/include/sqlite3.h, which declares the same release, and CHEZ_SQLITE3_LIBRARY names the library
(exit 0)
```

**`build-sqlite.sh --current` itself, end to end.** The container has no network, `tar` or
`openssl`, so the run put three shims first on `PATH`: a `curl` that copies
`build/m4-dl/sqlite-autoconf-3540100.tar.gz`; an `openssl` that answers, only for a file byte for
byte the one it names, the digest the host's real `openssl` computed of it, which matched
`current_archive` and `current_source`; and a `tar` that copies the three members the host's real
`tar` extracted. The compile and the check were the real ones, with the container's gcc. It built,
passed its own `check-sqlite.sh --current` with 39 options, and printed its last line, exit 0, in
25 s. The library was byte for byte `build/m4-current-fts5`'s. L01 ran the same with the flag
dropped. The three shims and the digests are kept in
[research/m4-slice-5/replay/](research/m4-slice-5/replay/). The archive and its extraction were
not kept: they are SQLite's pinned release, which `build-sqlite.sh` fetches by its URL and checks
by its digests.

## How the mutants ran

Every mutant ran in a copy of the worktree of its own, `build/mut/NAME/`, made by `tar` without
`./build` and `./.git`. A mutant is a list of edits, each checked to match its file's text exactly
once before it is written, and a list of runs. The runs went through the worktree's
`scripts/guix-env`, from `build/mut/NAME`, so the libraries under the worktree's `build/` were in
reach; each suite under `timeout 300`, six mutants at once; none hung. Rows are read from the
suites' `FAIL` and `XPASS` lines and counts, never by eye. The driver (`mutants.py`,
`run-mutants.sh`, `summarize.py`) was in the session's scratchpad; the lead copied it, unchanged,
into [research/m4-slice-5/scripts/](research/m4-slice-5/scripts/). Its per-mutant logs in
`build/mut/` were not kept; `summarize.py`'s reading of them is, for the rerun on the head
([research/m4-slice-5/plants-rerun.txt](research/m4-slice-5/plants-rerun.txt)).

As first run, F02's refusal row on an FTS5 library failed on its close, which raised FTS5's
untracked statements, not on the create's `done`. The row then dropped its probe table as the
others did, until the rebase, and every mutant that touches `test-fts5` or the library was made again from the final tree and
rerun: F02's row then failed on `(prepared done)`, and the counts row after it passed.

Baselines, before the rebase: `test-fts5` 18 and 1 expected failure on Guix's and the FTS5 build
(19 after it), 5 on the floor and the plain 3.54.1; `test-json` 16 everywhere; `test-ci-sqlite` 81; `test-docs` 101. A mutation is
caught when a row fails, or an expected failure passes, on at least one library.

### The brief's FTS5 plants, and the check's

| Mutation | Guards | Failed |
|---|---|---|
| F01 | the FTS5 rows run only where the check says yes (run whatever it says) | floor 14, plain 3.54.1 14: every FTS5 row; Guix's and the FTS5 build pass, as they must |
| F02 | the check's choice (inverted) | Guix's 1 and the FTS5 build 1: the refusal row, actual `(prepared done)`; floor 14 and plain 3.54.1 14, the rows |
| F03 | the refusal's code (expected `misuse`) | floor 1, plain 3.54.1 1: the refusal row |
| F04 | the refusal comes at step (expected at prepare, from `call-with-statement`) | floor 1, plain 3.54.1 1: the refusal row |
| F05 | the option and module check reads both (the option alone) | 1 on each of the four: the agreement row |
| F06 | the same (the module alone) | 1 on each of the four: the agreement row |
| F07 | the path is chosen only where they agree (by the option alone) | **survived**, equivalent (below) |
| F08 | the module probe names `fts5` (`fts4`) | the FTS5 build 1, the agreement row; Guix's, the floor and plain 3.54.1 pass |
| F09 | the option probe names `ENABLE_FTS5` (`ENABLE_FTS4`) | the FTS5 build 1, the agreement row; the other three pass |
| F10 | each row drops its FTS5 tables (none dropped) | Guix's 15 and the FTS5 build 15: every FTS5 row and the counts row |
| F11 | the close's row is marked an expected failure (the mark dropped) | Guix's 1 and the FTS5 build 1: that row |
| X01 | the mark flips once the close closes (the candidate fix, above) | Guix's and the FTS5 build: the close's row an unexpected pass, the suite exit 1 |
| X02 | control: X01's fix with the mark and the drops gone | none, as it must: 19 of 19 on both |

### The lane's plants

| Mutation | Guards | Failed |
|---|---|---|
| L01 | the current lane compiles FTS5 in (the flag dropped from its line) | `test-ci-sqlite` 2: the current build rows' compile line; and the copy's `build-sqlite.sh --current`, run end to end, failed its own check on the missing `ENABLE_FTS5`, exit 1 |
| L02 | the floor's line keeps SQLite's defaults (the flag given it too) | `test-ci-sqlite` 5: every floor build row |
| L03 | `current_options` holds `ENABLE_FTS5` (the line dropped) | `test-ci-sqlite` 5; and `check-sqlite.sh --current` failed the FTS5 build on `+ENABLE_FTS5`, while it passed the plain one |
| L04 | `ENABLE_FTS5` in SQLite's order (before `DIRECT_OVERFLOW_READ`) | `test-ci-sqlite` 5; and `check-sqlite.sh --current` failed the FTS5 build, the line out of place |
| L05 | the floor's list keeps SQLite's defaults (`ENABLE_FTS5` added to it) | `test-ci-sqlite` 12; and `check-sqlite.sh` failed the floor's real library on `-ENABLE_FTS5` |
| L06 | the flag goes with the current role (given when the role is the floor) | `test-ci-sqlite` 7: every build row that compiles |

### The JSON rows' values, planted one at a time

Each ran on Guix's library and the floor, and failed its own row alone on both, 15 of 16 passing.

| Mutation | Row | The planted value |
|---|---|---|
| J01 | `OMIT_JSON` is absent, `THREADSAFE` present | `(#f #f)`, a predicate answering `#f` to everything |
| J02 | `json()` minifies a literal | the literal as written |
| J03 | `json()` minifies a bound string | the string unchanged |
| J04 | malformed JSON at step | at prepare, from `call-with-statement` |
| J05 | malformed JSON through `query-row` | the who `step!`, an internal's |
| J06 | a bound BLOB that is no JSONB, at step | read, a row |
| J07 | `->` answers JSON text | `"é"`, the SQL value `->>` answers |
| J08 | `->>`'s REAL a flonum | the exact `5/2` |
| J09 | `json_each`'s rows | x's `1` as the flonum `1.0` |
| J10 | `jsonb()`'s BLOB | its last byte one more |
| J11 | a bound bytevector binds as a BLOB | `typeof` `text` |
| J12 | `+inf.0` and `-inf.0` | swapped |
| J13 | `9223372036854775808` a flonum | the exact integer |

### The FTS5 rows' values, planted one at a time

Each ran on Guix's library and the FTS5 build, and failed its own row alone on both, 17 passing.
The planted values are the builder's, of the rows before the review, so FV01's and FV02's "3
then 2" is now the rows' expected value. On the head, FV01 and FV02 plant rowid order, 2 then 3;
FV07 the AND's answer, the reversed phrase matching 2; FV10 café lost, each row's typeof kept;
and J03 the string unchanged, its typeof kept (the driver's header).

| Mutation | Row | The planted value |
|---|---|---|
| FV01 | `MATCH` with `order by rank` | 3 then 2 |
| FV02 | rank is `bm25()`'s order | 3 then 2 |
| FV03 | `unicode61` folds diacritics | `creme` matching nothing |
| FV04 | `remove_diacritics 0` | `cafe` matching |
| FV05 | `highlight()` over UTF-8 | the folded `cafe` |
| FV06 | prefix | `searc*` as a whole term, nothing |
| FV07 | phrase | nothing |
| FV08 | column filter | `title:sqlite` matching the bodies' 2 and 3 |
| FV09 | `NOT` | ignored, 2 and 3 |
| FV10 | a bound `MATCH` | `café` lost, 2 and 3 |
| FV11 | a syntax error through `query` | the who `step!` |
| FV12 | syntax errors at step | code `misuse` |
| FV13 | delete and update | neither applied |
| FV14 | the create's step | a row |

### Both suites' load and counts rows, the docs, and the values' path in the library

| Mutation | Guards | Failed |
|---|---|---|
| P01 | the load row reads the load (`CHEZ_SQLITE3_LIBRARY` naming no file) | `test-fts5` 2: the load row, and the agreement row, so no path ran; `test-json` 14: the load row and every value row |
| P02 | the counts row at the load (a connection opened before it) | `test-fts5` 2 and `test-json` 2: the counts rows at the load and after |
| D01 | the note's block is one Chez reads (a parenthesis dropped) | `test-docs` 1: "every fragment's text is data Chez reads" |
| D02 | the note's block is plain `scheme` (marked `scheme run`) | `test-docs` 1: the runnable example at `docs/reference.md:1152`, `:1165` after the rebase |
| V01 | `column-value` reads a REAL as its flonum (rounded) | `test-fts5` 1, the `bm25()` row; `test-json` 1, the `->>` row |
| V02 | a string binds as TEXT (as a BLOB) | **survived both suites on Guix's library**; `test-statement-values` failed 7 and `test-conveniences` 2 (below) |
| V03 | a bytevector binds as a BLOB (as TEXT) | `test-json` 1, the bound `#vu8(12)` row; `test-fts5` binds none |
| V04 | TEXT decodes as UTF-8 (each byte a character) | `test-fts5` 1, the `highlight()` row; `test-json` 1, the `->` row |

**53 mutants and X02's control: 51 caught by the new suites, `test-ci-sqlite` and `test-docs`, F08
and F09 among them on the FTS5 build alone; V02 caught by the older suites; F07 survived,
equivalent.**

## The survivors, argued

- **F07, the path chosen by the option alone, ignoring the agreement,** is equivalent in every
  verdict. Where the option and the module agree, as on all four libraries, it takes the same path.
  Where they disagree, the agreement row fails by name, as before, and only which further rows run
  changes: the suite fails either way. Take a library whose option says yes and whose module says
  no: the agreement row names `(disagree #t 0)`, and F07 then runs the FTS5 rows, which fail too.
- **F08 and F09 are caught on one library of four,** the FTS5 build, which has FTS5 and neither
  FTS3 nor FTS4. Guix's has all three, the floor and the plain 3.54.1 none, so a probe of the wrong
  module or option agrees with its partner there. CI's `current` lane is that build, so CI catches
  both.
- **V02, a string bound as a BLOB, survived both suites on Guix's library,** where it was run.
  3.53.1's and 3.54.1's JSON functions read a BLOB that holds text JSON, so `json(?1)` of
  `"[1, 2]"` as a BLOB answered `[1,2]` and `json_valid` 1, as for TEXT; FTS5 reads a BLOB `MATCH`
  as its text, so `"sqlite OR café"` matched 1, 2 and 3. The review found the argument false at the
  floor: 3.45.1 raises "malformed JSON" for that BLOB, so `test-json` caught V02 there. Since the
  review, the bound row asserts `typeof(?1)` too, and catches V02 on every library (below).
  `test-statement-values` (7 rows) and `test-conveniences` (2) hold it besides.

## The review's fixes

An Opus reviewer read the slice after the rebase, read-only, with mutants of its own in copies:
no blocker, one major, nine minors, each shown by a mutant or a run. Its mutants R01 to R05 each
survived the suites as they stood.

| Finding | Mutant that survived | Fix | The fixed row passes on |
|---|---|---|---|
| **Major:** the rank rows' `sqlite` and `search` rank 2 then 3, which is rowid order too | R01, `order by rank` as `order by rowid`: 19 of 19 on the four FTS5 libraries | both rows query `sqlite OR rank`, which ranks 3 (bm25 -0.463…) before 2 (-1.05e-6), measured by the reviewer | Guix's, 3.54.1 with FTS5, and 3.45.1 and 3.54.1 with every module |
| the phrase row can't tell a phrase from an AND | R02, the quotes dropped | also `"text full"`, which matches nothing, where `text full` matches 2 | the same four |
| the agreement row holds two points of its complement | R03, a module count neither 0 nor 1 taken as no; on 3.54.1 built with `OMIT_INTROSPECTION_PRAGMAS` it printed "neither" with the module never read | five more points: each side a probe that raised, and a count of 2 | all six |
| `json_each`'s key order is the document's | R04, `order by key` dropped | the object written z, x, y, the expected value unchanged | all six |
| V02's argument was false at the floor (above) | V02 on 3.53.1 and 3.54.1 | the bound row asserts `typeof(?1)`, `text` | all six |

The minors besides: F01's and F02's count (above); the log's stale prose about the drivers, the
probe table's drop, the baselines and D02's line, each fixed in place; the rerun's summary kept
in the repository; a comment on the close row's cleanup, which runs only where the close refuses;
and the ledger's items: the merge order with PR #37, the shard choice read on a second run, the
CI run and the Mac run owed.

**The lead's plants of the fixed tree,** each in `build/lead-mut/`, before the rebase onto
`1735a66` (the head's run is below):

| Mutation | Guards | Failed |
|---|---|---|
| LR01 | the rank rows' `order by rank` (`order by rowid`, in both) | `test-fts5` 2, both rank rows, on Guix's and the FTS5 build |
| LR02 | the reversed phrase is a phrase (its quotes dropped, an AND) | `test-fts5` 1, the phrase row, on both |
| LR03 | the agreement's no needs a count of 0 (any count but 1) | `test-fts5` 1, the agreement row, on Guix's |
| LR04 | `json_each`'s `order by key` (dropped) | `test-json` 1, the key-order row, on Guix's and the floor |
| LR05 | V02, a string bound as a BLOB | `test-json` 1, the bound row, on Guix's and the floor; `test-fts5` none, as before |

On the fixed tree, `make test` ran 76 and passed 76 on Guix's, the floor, 3.54.1 with FTS5 and
3.45.1 with every module; `test-fts5` passed 19 on the four FTS5 libraries and 5 on the floor
and the plain 3.54.1, `test-json` 16 on all six. Under the gate on Guix's library, `test-fts5`
11 s and `test-json` 10 s.

## On the head (the lead, after the M4 session's check)

The M4 session checked PR #40 against the plan and the records, read-only: no blocker, no
major, three minors in the evidence and records, and five nits. The lead then:
- **Rows:** the agreement row holds `(#f 2)` beside `(#t 2)`, so a no that takes any count but 1
  fails on both sides; the bound `MATCH` asserts `typeof(?1)`, `text`, so a string bound as a
  BLOB, which FTS5 reads as text, fails `test-fts5` too.
- **The driver:** FV01, FV02, FV07, FV08, FV10 and J03 moved to the head's rows, FV08's anchor
  lengthened since its old text now matched the phrase row too, and the four workaround plants
  retired from the default run.
- **The lead's plants,** kept as scripts in [research/m4-slice-5/lead/](research/m4-slice-5/lead/):
  `plants.json` for `plant.py`, `old-close.sh` for the copy with `d1792e4`'s close, and `run.sh`,
  which runs each on the libraries it touches.
- **Rebased** onto `1735a66`, slice 2's merge, the ledger's Now line and close-outs resolved by
  hand.

**The rerun on the head,** every run from the scripts:

| Run | Result |
|---|---|
| the driver, 50 mutants ([plants-rerun.txt](research/m4-slice-5/plants-rerun.txt)) | 49 caught; F07 survives, equivalent; V02 caught by `test-fts5`'s bound `MATCH` and `test-json`'s bound string |
| the lead's LR01 to LR05 ([lead/results.txt](research/m4-slice-5/lead/results.txt)) | each caught: LR01 2 rows, LR02, LR03 and LR04 1 each, on both of their libraries; LR05 `test-json`'s bound row on Guix's and the floor, and `test-fts5`'s bound `MATCH` on Guix's and the FTS5 build |
| the old close, `X-old-close` | `test-fts5` 15 failed and 4 passed on Guix's, the FTS5 build and 3.45.1 with every module |
| `make test` | 77 of 77 on Guix's, the floor, 3.54.1 with FTS5 and 3.45.1 with every module |
| the two suites on the other two | `test-fts5` 5 on the plain 3.54.1 and 19 on 3.54.1 with every module; `test-json` 16 on both |
| under the gate, Guix's library | `test-fts5` 10 s, `test-json` 10 s |

**On CI,** run 44211896445 at `1b2d6a0`, the lanes' lines as "For the records" gives them, and
`memory-1` timed `test-fts5` at 11 s and `test-json` at 10 s. The shards' sums on three runs, shard
1 against shard 2: 900 and 986 s (44112097972), 1186 and 1268 s (44204326637), and 936 and 874 s
on this one, 915 s without the two new suites. Shard 1 is the lesser on two of three, so the
choice stands, by a narrow margin; slice 3's new suites go in shard 2.

**Two nits, answered rather than changed:**
- The plan's Q2 and §4.5 put the agreement row, and `test-json`'s `OMIT_JSON` row, first; each is
  third, after the load and counts rows, so a library that doesn't load is named before the
  agreement is read. Nothing fails from the order.
- `test-json`'s bound BLOB that is no JSONB, `x'0102'`, passes V03, a bytevector bound as TEXT,
  since both are malformed JSON at step. V03 is caught by the row that binds `#vu8(12)`, JSONB's
  empty object, which `json()` reads as `{}` only from a BLOB.

## For the records

- **ADR-0012, decision 5, and the trap above: done** by PR #36, its amendment, its traps and the
  global constraints' close rules. `test-fts5`'s mark and drops are gone, and its close row is an
  ordinary row (below).
- **ADR-0003's amendment** is built: the lane, the lists and the rows, and F0's two outcomes on the
  two 3.54.1 builds. CI's first run on this branch, 44211896445 at `1b2d6a0`, read them, both
  SQLite caches missing and rebuilt: `current`'s `check-sqlite.sh` passed its build's 39 compile
  options, `ENABLE_FTS5` after `DIRECT_OVERFLOW_READ`, and `test-fts5` ran its 19 rows; `floor`'s
  passed 37, and `test-fts5` printed "FTS5 unavailable" and ran 5; `main`, on Ubuntu's 3.45.1,
  ran the 19, the first run of the rows on that library. `test-json` passed 16 on each. The
  amendment says the workflow doesn't change, and no job or step did; the `current` job's comment
  did, as the plan's §4.5 asks, and `check-ci` skips comments.
- **ADR-0005's shard amendment** lists `MEMORY_SUITES_1` at 35 suites, as it was then; it is 38 on
  `3488963` with these two, at about 10 s each under the gate here. Their CI times are for the
  first runs of `memory-1` to read.
- **The brief's §2.6,** amended with M4's plan, says the FTS5 suite runs on every lane, which
  holds; with the close fix, nothing about FTS5 needs adding there.
- **The ledger:** slice 5's close-out, and the merge order with slice 2, which edits the same shard
  lines and `ci.yml`.
