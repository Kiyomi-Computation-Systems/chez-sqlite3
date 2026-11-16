# M3 slice 2 mutation log: the bindings

Evidence that each rule the slice's suites claim to guard fails through the property it names
([M3 plan](2026-11-15-m3-plan.md), §4.7 and §5's item 2). Format of
[the M2 slice 2 log](m2-slice-2-mutation-log.md).

The slice is M3's five entry points in `(chez-sqlite3 private native)` (`sqlite3_changes64`,
`sqlite3_total_changes64`, `sqlite3_last_insert_rowid`, `sqlite3_get_autocommit`,
`sqlite3_interrupt`), all plain; `sqlite-prepare-persistent` in `(chez-sqlite3 private constants)`;
the convention table's five rows; the decoy's five (`tests/decoy-libsqlite3.c`); the C oracle's
`--counters` mode (`tests/libsqlite3-oracle.c` and `.sls`); the alternation check
(`entries-at-parity` in `tests/library-loading.sls`); and the suites `test-constants`,
`test-conventions`, `test-library-loading-decoys`, `test-library-loading-real` and `test-native`.
An agent built it test first from its brief.

Every mutation ran in its own whole copy of the tree (`build/m3s2/mut/ID/`, git-ignored; the
generator is `build/m3s2/mutate.py`), each edit refused unless its old text occurred the stated
number of times and changed something. One container call ran the five suites in each copy, six at
a time, outside the gate, on Guix's 3.53.1. The counts are read from the suites' own output
(`# of expected passes`, `# of unexpected failures`); a suite that printed no count is marked
`died`. The driver and the definitions are in `build/m3s2/`, not the repository.

## The red runs

Each row was written first and run against the code as it stood.

| Suite | Red run | Against | Green run |
|---|---|---|---|
| `test-conventions` | 35 passed, 10 failed | the new suite, the table and native without the five (`HEAD`'s `src/`, after the table was written: the 41-form, 66-argument and written-out rows, and `no-form` for the five) | 45 |
| `test-constants` | 41 passed, 2 failed | the new suite, slice 1's constants and map: the exports row (`sqlite-prepare-persistent` is no export) and the values row | 43 |
| `test-native` | 82 passed, 18 failed | the new suite against `HEAD`'s `src/` (`HEAD`'s own suite: 82 passed): every row that calls one of the five, the exports and both body rows | 100 |
| `test-library-loading-decoys` | 48 passed, 3 failed | the new suite and support, `HEAD`'s `src/`: `lacks-` rows of `changes64`, `last_insert_rowid` and `interrupt`, which loaded, since native did not bind them | 51 |
| `test-library-loading-real` | 55 passed, 2 failed | the same: `total_changes64` and `get_autocommit` | 57 |
| `test-native`, both `test-library-loading` | died | the same: the support lacked `libsqlite3-oracle-counters` and `entries-at-parity`, so the import failed | |

Every figure above is read from a red run made after the slice: slice 1's `src/` (`0505ff5`) with
the slice's tests as committed (`2e844f1`), the five suites run directly on Guix's 3.53.1. The rows
that pass against that red copy are rows it can satisfy: `test-native`'s three (the oracle's read,
its Valgrind line, and the oracle against the literal) and one alternation row per half need no
binding. The alternation check has no earlier state to fail against; A01 to A05 watch it fail.

Existing rows that had to change, by count or list only, not by what they assert: the rows that
count the table's rows, forms and arguments (36 to 41, 61 to 66), the table's expected names, the
exports row, the load-steps row and the eager-binding row of `test-native`, the names asked of the
header (123 to 124), and `every-entry` and the halves in `tests/library-loading.sls`. Two others:
`test-constants`' `map-problems` maps a `void` result through a `result-type` of its own, leaving
`chez-type`, and the map row that asserts `void` is unmapped, as it was; and the convention
suite's used-types row now leaves `void` out of the argument side, which a `void` result had
joined (`sqlite3_interrupt` is the first row to write it).

## Measured first

Through the C oracle on Guix's 3.53.1 and the floor, 3.45.1: the two agree on every counter in
both scripts. The first script's four counters after each statement are written out in
`test-native` (`counters-written`); the second's (`rowid-script`) too.

- **`sqlite3_interrupt`, one thread:** with a statement held at its row, the next step answers 9,
  and the finalize 9 too; a statement prepared after runs to a row and DONE. With no statement
  running (a fresh connection, or after a statement ran to DONE with no reset) it is lost: the next
  statement runs normally. **3.45.1 and 3.53.1 answer alike,** so no row asserts by version.
- **`sqlite3_total_changes64` counts a trigger's rows and `sqlite3_changes64` does not,** so a
  script with a trigger separates the two from its first change (3 and 6).
- **A ROLLBACK leaves the totals as they were:** 20 before and after, with the flag back at 1.
- **Chez's `int` range doesn't bite here:** every argument is a handle, a `uptr`, so no row feeds
  an argument past −2³¹ to 2³²−1 and none is added for it. A result of `int` reads the low 32 bits
  sign-extended instead; the three 64-bit rows catch it.

## The mutations

Baselines: `test-conventions` 45, `test-constants` 43, `test-native` 100,
`test-library-loading-decoys` 51, `test-library-loading-real` 57. Each cell is the number of rows
that failed; a suite not named passed whole. A mutation counts as caught when at least one row
failed. In `test-conventions`, a mutation of native also fails the sweeps, which hold the real
`src/`.

**62 mutations, 62 caught, none survived.** Some are caught by form alone, argued below.

### Types

| Mutation | Guards | Failed |
|---|---|---|
| T01 | `sqlite3_changes64` result `integer-64` to `int`, native alone | conventions 9 |
| T02 | `sqlite3_total_changes64` the same | conventions 9 |
| T03 | `sqlite3_last_insert_rowid` the same | conventions 9; native 5: the three 64-bit rows by a wrong value, the whole 64-bit script and its written literal |
| T04 | `sqlite3_get_autocommit` `int` to `integer-64`, native alone | conventions 9 |
| T05 | `sqlite3_interrupt` `void` to `int`, native alone | conventions 9; native 1: the result is a number, never the unspecified value |
| T06 | changes64 `int`, native and table alike | conventions 2: the five written out, the §4.8 plants; constants 1: the map |
| T07 | autocommit `integer-64`, native and table alike | conventions 2; constants 1 |
| T08 | interrupt `int`, native and table alike | conventions 2; constants 1; native 1: the unspecified value |
| T09 | changes64 `int`, native, table and its prototype alike | conventions 2; constants 1: the header declares `sqlite3_int64`, so the prototype row names it |
| T10 | interrupt `int`, native, table and prototype alike | conventions 2; constants 1: the header declares `void`; native 1 |

T01, T02 and T04 pass `test-native`: no row reads a count past 32 bits (that takes 2³² changes),
and a counter of 0 to 20, or a flag of 0 or 1, reads the same through `int` and `integer-64` on
amd64 and arm64. They are caught by form, as the brief expects. T03 is caught by behaviour: an
`int` result reads the low 32 bits sign-extended, so 2⁶³−1 reads −1, −2⁶³ reads 0 and 2³²+1 reads
1. T05 and T08 are caught by behaviour too: a `void` result answers the unspecified value, an
`int` result a number.

### Conventions

| Mutation | Guards | Failed |
|---|---|---|
| C01 | `sqlite3_changes64` `__collect_safe`, native alone | conventions 9 |
| C02 | `sqlite3_total_changes64` the same | conventions 9 |
| C03 | `sqlite3_last_insert_rowid` the same | conventions 9 |
| C04 | `sqlite3_get_autocommit` the same | conventions 9 |
| C05 | `sqlite3_interrupt` the same | conventions 9 |
| C06 | changes64 `__collect_safe`, native and table alike | conventions 3: the collect-safe names written out, the five written out, the sweep |
| C07 | interrupt `__collect_safe`, native and table alike | conventions 3 |

`test-native` passed 100 in each: the five do not block, so no row can see a collection wait on
one, and they are held by form. (ADR-0011, M3's amendment, says none waits: a row that held one by
behaviour would need a wait to hold.)

### Each bound to another of the five (a rotation)

| Mutation | Guards | Failed |
|---|---|---|
| B01 | `sqlite3-changes64` calls `sqlite3_total_changes64` | conventions 10 (`no-form`, bound twice); native 5: the script's two rows (the oracle's and the literal's by the first), the eagerness row; ll-decoys 1: the `lacks-sqlite3_changes64` row |
| B02 | total_changes64 calls `sqlite3_last_insert_rowid` | conventions 10; native 5; ll-real 1 |
| B03 | last_insert_rowid calls `sqlite3_get_autocommit` | conventions 10; native 8; ll-decoys 1 |
| B04 | get_autocommit calls `sqlite3_interrupt` | conventions 10; native 8; ll-real 1 |
| B05 | interrupt calls `sqlite3_changes64` | conventions 10; native 2: the held-row row and the eagerness row; ll-decoys 1 |

### `foreign-entry?` dropped

| Mutation | Guards | Failed |
|---|---|---|
| F01 | `sqlite3_changes64` bound without `bind-required` | native 2: the load-steps row and the eagerness row; ll-decoys 1: `lacks-sqlite3_changes64` is Chez's bare "no entry for", not `missing-api` |
| F02 | total_changes64 the same | native 2; ll-real 1 |
| F03 | last_insert_rowid the same | native 2; ll-decoys 1 |
| F04 | get_autocommit the same | native 2; ll-real 1 |
| F05 | interrupt the same | native 2; ll-decoys 1 |
| F06 | `required-entry` never refuses, for every binding | ll-decoys 23, ll-real 20: every `lacks-` row |

The convention suite passes F01 to F05: its reader accepts a literal form. The order and the eager
binding are `test-native`'s, and the refusal's naming the decoy's.

### Order

| Mutation | Guards | Failed |
|---|---|---|
| S01 | native: changes64 and total_changes64 bound in the other order | native 2: the load-steps row and the eagerness row |
| S02 | native: last_insert_rowid and interrupt swapped, not adjacent | native 2 |
| S03 | table: the rows of changes64 and total_changes64 swapped | conventions 2: the written-out order and the last-five row; ll-decoys 2 and ll-real 1: the entry list held to the table, and the alternation (it fails in both suites) |
| S04 | both swapped | conventions 2; native 2; ll 3 |

As M2's E02 and E03, S01 and S02 pass the convention suite and `test-library-loading`: a decoy
lacking one entry point names it whatever the order. Only `test-native`'s body rows hold the order.

### The lists and the decoy

| Mutation | Guards | Failed |
|---|---|---|
| L01 | `sqlite3_interrupt` left out of `rest-entries` | ll-decoys 2: the entry list against the table, and `lacks-sqlite3_interrupt` |
| L02 | `sqlite3_total_changes64` left out of the real half | ll-decoys 2 and ll-real 2: the partition row and its `lacks-` row |
| L03 | the decoy defines no `sqlite3_interrupt` | ll-decoys 6: the control and its behaviours, the marked build; ll-real 1: preflight's control |
| L04 | `sqlite3_changes64` left out of the decoys half | ll-decoys 2, ll-real 2: the partition (a `lacks-` row went with it) |
| L05 | the decoy's switch misnamed, `DECOY_LACKS_sqlite3_interupt` | ll-decoys 1: `lacks-sqlite3_interrupt` loaded |
| L06 | the decoy's `sqlite3_get_autocommit` takes an `int` | ll-decoys 39, ll-real 21: every build fails to compile (`-Werror`, conflicting types) |
| L07 | the decoy's `sqlite3_changes64` answers `int` | ll-decoys 38, ll-real 22: the same |
| L08 | `rest-entries` has `sqlite3_interrupt` before `sqlite3_get_autocommit` | ll-decoys 1: the entry list against the table |

### The constant

| Mutation | Guards | Failed |
|---|---|---|
| K01 | `sqlite-prepare-persistent` 2 (`SQLITE_PREPARE_NORMALIZE`) | constants 1: the values row |
| K02 | 0 | constants 1 |
| K03 | 16 | constants 1 |
| K04 | dropped from the export list | constants 2: every row is an export, the values row |

### The alternation check (item 6)

| Mutation | Guards | Failed |
|---|---|---|
| A01 | `sqlite3_changes64` and `sqlite3_total_changes64` swapped between the halves | the alternation row, in each of ll-decoys and ll-real: 1 each; **the partition row passes** |
| A02 | `sqlite3_get_autocommit` moved from the real half to the decoys' | the alternation row, 1 each; the partition row passes |
| A03 | `entries-at-parity` ignores its parity | the alternation row, 1 each |
| A04 | `sqlite3_libversion_number` and `sqlite3_libversion` swapped between the halves, M1's | the alternation row, 1 each; the partition row passes |
| A05 | `sqlite3_changes64` moved from the decoys half to the real half | the alternation row, 1 each; the partition row passes |

A01, A02, A04 and A05 pass every other row of both suites, `merge-halves`' partition row among
them: it holds the halves partition the table in its order, which a swap or a move keeps. This is
the hole the row closes.

### The oracle's `--counters` mode

| Mutation | Guards | Failed |
|---|---|---|
| O01 | `total_changes64` printed as `changes64` | native 3: the script against the oracle, the 64-bit script, the oracle against the literal |
| O02 | `last_insert_rowid` read through an `int` | native 1: the 64-bit script against the oracle |
| O03 | `get_autocommit` printed as 1 | native 2: the script, the oracle against the literal |
| O04 | nByte one short | native 5: no oracle, the Valgrind line, both scripts, the literal |
| O05 | `changes64` printed as `total_changes64` | native 3 |
| O06 | the counters read before the statement runs | native 3 |

### The suite's own rows, planted

| Mutation | Guards | Failed |
|---|---|---|
| R01 | the update changes one row fewer (`id < 1002`) | native 2: the written literal and the oracle's against it; **the script against the oracle passes**, both read one library: the literal earns its place |
| R02 | the rowid script at tame values | native 1: the written 64-bit counters; the oracle row passes |
| R03 | the held-row row without its interrupt | native 1: the step answers a row |
| R04 | the interrupt moved after the finalize | native 1: the interrupt then reaches no running statement |
| I01 | `sqlite3-interrupt` a no-op | conventions 10, native 3: the held-row row, the load steps and the eagerness; ll-decoys 1 |
| I02 | `sqlite3-get-autocommit` always 1 | conventions 10, native 7: the script, the three transaction rows, the load rows; ll-real 1 |
| I03 | `sqlite3-last-insert-rowid` the low 32 bits | native 7: the three 64-bit rows, the 64-bit script twice, the load rows |

## The gate, measured locally

`make test-memory` in the container, run once each way, this tree (after the review's fixes)
against `0505ff5`, slice 1's head, in a copy of its own. Seconds, as the gate prints them. Other runs
may have shared the machine, and a lone run is not a reading of the cost; CI's figures are the
maintainer's. The floor runs set the floor's library and header.

| Suite | Guix 3.53.1 before | after | floor 3.45.1 before | after |
|---|---|---|---|---|
| conventions | | 25 | | 25 |
| constants | | 9 | | 9 |
| native | | 17 | | 16 |
| library-loading-decoys | 201 | 219 | 200 | 219 |
| library-loading-real | 189 | 202 | 188 | 202 |

Only the two halves were measured before. Every suite passed, none slow.

Each half grew by its entries, each child under a Valgrind of its own:

| Half | children before | after | time added, Guix | time added, floor |
|---|---|---|---|---|
| decoys | 38 | 41 | +18 | +19 |
| real | 38 | 40 | +13 | +14 |

**The cost is 6 to 7 s per child** (decoys 6.0 and 6.3 for three, real 6.5 and 7 for two). A half
is near 220 s of the 450 s limit.

## The review's fixes

The fixes of the slice's adversarial review. Suites now: `test-constants` 44 (one row added),
`test-conventions` 45, `test-native` 100 (the same rows), the halves 51 and 57. Each mutant ran in a
whole copy of the fixed tree, on Guix's 3.53.1, test first.

| Fix | Row or check | Watched fail on | Counts |
|---|---|---|---|
| 2 | `test-constants`: `result-type` gives `void` for `"void"` alone and `chez-type`'s answer for every other C type of the map row's list | **RT2**: any C result spelled from `void` maps to `void` (it survived before) | constants 43 passed, 1 failed |
| 2 | the same row, against RT1 (an unmapped result maps to `void`) | RT1 | constants 42 passed, 2 failed: the new row and the map check |
| 3 | `run-statement` answers `(CODE tail OFFSET)` when prepare's tail is not the SQL's byte length | a copy whose `counters-script` has `"create table log(n); select 1"`, the oracle left as it was | native 97 passed, 3 failed: the oracle's read, the script against the oracle, the oracle against the literal |
| 3 | the oracle's `--counters` refuses a tail | the same script, `run-statement` left as it was | native 98 passed, 2 failed: the script against the oracle, the written-out counters |
| 3 | both | the same script, both new | native 96 passed, 4 failed; and with the tail in `rowid-script` instead, 93 passed, 7 failed |
| 3 | both | the same two copies against the old code | native 100 passed, 0 failed: the insert never ran and both sides agreed |
| 3 | `--rows` refuses a tail | `--rows LIB <select 1; select 2>` by hand: before, exit 0; after, exit 1 | no suite row reaches it |

Fix 3's check also refuses `select 1; ` with a space after the semicolon: SQLite's tail points at
the space. No row's SQL ends so.

**Fix 4, the oracle's leak on bad hex.** `counters()` decoded each statement after the open. It now
decodes every statement before the open and frees each after it runs. No row reaches the path, since
`utf8-hex` always gives even hex, so it is shown here: under Valgrind with the gate's flags
(`--errors-for-leak-kinds=definite --error-exitcode=9`), on `--counters LIB 73656c6563742031 abc`,
the old oracle exited 9 with 840 bytes in 1 block definitely lost; the new one exits 1 with none. A
good run (two statements) and a run with a tail are both clean: 0 bytes definitely lost.

**Fixes with no row to watch:** the five record strings and the `sqlite3-changes64` comment
(fix 1: strings the sweeps read as data, not what any row asserts); the decoy's five, a comment that
says they exist for dlsym and that no row reads what they answer (fix 5); and the sweep's name,
which now lists `void` (fix 6).

## The review's own mutants

Rerun in whole copies of the fixed tree, all five suites each (Guix's 3.53.1). The counts are the
suites' failed rows.

| Mutant | What it changes | Result |
|---|---|---|
| O1 | the oracle reads the counters before the finalize | survives: sqlite3 answers the same before and after a finalize (argued equivalent) |
| O2 | the oracle reads changes and total through the 32-bit `sqlite3_changes` and `sqlite3_total_changes` | survives: no counter reaches 32 bits, so the two agree (argued equivalent) |
| D1 | the decoy's five answer otherwise, and the interrupt aborts | survives by the decoy's design: the load binds them and calls none (fix 5) |
| D2 | M2's `sqlite3_column_int64` in the decoy answers 99 | survives for the same reason |
| RT1 | `result-type` maps an unmapped result to `void` | caught: constants 2 |
| RT2 | `result-type` maps any result spelled from `void` to `void` | caught by the fix-2 row: constants 1 (survived before) |
| RT3 | `chez-type` maps `void` too | caught: constants 2 (the map row, the void row) |
| RT4 | `map-problems` maps arguments through `result-type` | caught: constants 1 (the void row) |
| UT1 | the table writes `sqlite3_interrupt`'s argument as `void` | caught: conventions 12, constants 1 |
| AL1 | the halves as a partition in order, 21 and 20 | caught: the alternation row, 1 in each half |
| AL2 | the halves swapped wholesale | caught: the alternation row, 1 in each half |
| NL1 | `sqlite3-changes64` bound without `load-step` | caught: native 2 (load steps, eagerness); decoys 1 |
| NC1 | `sqlite3_interrupt` bound to `sqlite3_close` | caught: native 4, conventions 10, decoys 1 |
| PG1 | `_Generic`'s default in the prototype check made 1 | caught: constants 5 of the prototype rows (39 passed, 5 failed); the review ran 38 and 5 before the fix-2 row |

## Findings

- **The alternation is held now:** before this slice nothing held that each half is the entries at
  its parity; the partition row keeps a swap.
- **`test-native` reads `(void)` for a `void` result:** the only way to see a `void` binding made
  `int` by behaviour.
- **A first run of the floor's gate cost 266 s and 241 s,** 50 s above its rerun and above the
  guix runs; a lone gate run is not a reading of the cost.
