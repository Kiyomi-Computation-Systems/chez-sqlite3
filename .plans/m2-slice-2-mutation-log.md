# M2 slice 2 mutation log: the bindings

Evidence that each rule the slice's suites claim to guard fails through the property it names
([M2 plan](2026-11-14-m2-plan.md), §4.7, §4.8 and §5's slice 2). Format of
[the M2 slice 1 log](m2-slice-1-mutation-log.md).

The slice is M2's 21 entry points in `(chez-sqlite3 private native)`, with `sqlite-transient`;
the constants `sqlite-row`, `sqlite-done`, the five type codes and `sqlite-utf8` in
`(chez-sqlite3 private constants)`; the convention table's 21 rows and its allowlists
(`tests/foreign-conventions.sls`); the decoy's 21 (`tests/decoy-libsqlite3.c`); the C oracle's
`--rows` and `--transient` modes (`tests/libsqlite3-oracle.c` and `.sls`); and the suites
`test-constants`, `test-conventions`, `test-library-loading` and `test-native`. An Opus agent
built it test first from the maintainer's brief.

Every mutation ran in its own copy of `src/`, `tests/`, `packaging/` and `.plans/decisions/`,
made under the worktree's git-ignored `build/m2s2/mut/`, since the container cannot see the
session scratchpad. A driver refused any edit whose old text did not occur exactly the stated
number of times (each did), and any that changed nothing. One container call then ran the named
suites in each copy, six copies at a time, with the worktree's SRFI libraries, outside the gate.
The counts below are read from the suites' own output (`# of expected passes`,
`# of unexpected failures`), never by eye; a suite that printed no count is marked `died`. The
driver and the mutation definitions are in `build/m2s2/`, not the repository.

## The red runs

Each row was written first and run against the code as it stood, or against a planted copy, then
the code was written. The counts are the suites' own.

| Suite | Red run | Against | Green run |
|---|---|---|---|
| `test-constants` | 36 passed, 5 failed | constants without the eight, the old map, the 15-row table | 41 passed |
| `test-conventions` | 32 passed, 9 failed | the old table and allowlists | |
| `test-conventions` | 33 passed, 8 failed; the violations row names the 21 as `(no-form …)` | the 36-row table, native without the 21 | 41 passed |
| `test-library-loading` | 63 passed, 7 failed: every accepted load refused `missing-api`, `sqlite3_prepare_v3` | native with the 21, the old decoy | 70 passed, the rows unchanged |
| `test-library-loading` | 70 passed, 21 failed: exactly the 21 new `lacks-` rows | the 21 rows, against `HEAD`'s native | 91 passed |
| `test-native` | 47 passed, 19 failed | the new suite against `HEAD`'s native (`HEAD`'s own suite: 46 passed) | 66 passed |
| `test-library-loading` | 90 passed, 1 failed: the entry-list row | N10, the review's fix 1 | 92 passed |
| `test-native` | 68 passed, 1 failed: the written-out columns | N12, the review's fix 2 | 69 passed |
| `test-native` | 68 passed, 1 failed each: the TOOBIG row of the text, of the blob | T06, T07, the review's fix 3 | 69 passed |

The rows that passed against a red copy are rows it can satisfy:

- `test-constants`: 35 of its 39 older rows, which hold M1's values and the table's shape, the
  count of names asked among them (now 123: it counts the suite's own questions); and one new
  row, which compiles prototypes of its own, M2's C types and their near misses, so needs no
  table row. R05 watches it fail.
- `test-native`: the four new rows that hold the C oracle alone: it read the SQL, its two valgrind
  lines, and its datum's shape (two rows of 13). Mutations B04 and O03 watch them fail.

## Measured first

Through bare FFI (`build/m2s2/probe-measure.sps`), on Guix's 3.53.1 and the floor, 3.45.1: the two
outputs differ in their first line alone, the version.

| SQL, on `:memory:` | Code | Statement | `sqlite3_error_offset` |
|---|---|---|---|
| `select 1, nosuchcol` | 1 (`SQLITE_ERROR`) | NULL | 10 |
| `select 'é', nosuchcol` | 1 | NULL | 13, in bytes: `é` is two |
| `selectx 1` | 1 | NULL | 0 |
| `select 1 +` | 1 | NULL | −1, the end of the SQL |
| `select (` and `select 1 from` | 1 | NULL | −1 |
| `select 1; select 2` | 0 | a statement, the tail at 9 | −1 after a success |

- **Parameters:** `select :alpha, ?7, $beta` counts 8; `:alpha` is 1, `?7` 7, `$beta` 8, and
  `:nosuch` and `alpha` without its sigil 0. A bind at 0, or at the count plus 1, answers 25
  (`SQLITE_RANGE`).
- **`select ?1` keeps what is bound:** −2⁶³, −2³¹−1, 2³¹ and 2⁶³−1 as INTEGER; −0.0 with its sign
  bit, +inf.0, the smallest subnormal (bits 1) and 1.5 as REAL, bit for bit.

## The mutations

Baselines, from the green runs, after the review's fixes: `test-constants` 41, `test-conventions` 41,
`test-native` 69, `test-library-loading` 92. Every mutation of the first 58 was rerun against the fixed
tree, and its counts below are the rerun's. Each row names the suites that failed and how many rows failed in
each; a suite run and not named passed whole. A mutation counts as caught when at least one row
failed. In `test-conventions`, a mutation of native also fails the six sweeps, which hold the real
`src/`: "7" is the violations row and those six.

**62 mutations, 60 caught, 2 survived;** each survivor is argued below. The review added N10 to N13.

### Types: the M2 plan's section 4.8 plant, and the narrower types

| Mutation | Guards | Failed |
|---|---|---|
| T01 | `sqlite3_bind_int64` bound with `int` (§4.8) | conventions 7; native 1: the int64 round trip, **by a raise**. Chez's `int` refused −2⁶³, −2³¹−1 and 2⁶³−1 ("invalid foreign-procedure argument"); 2³¹ came through as itself, since the callee reads a 64-bit register whose upper half was zero (below) |
| T02 | `sqlite3_column_int64` bound with `int` (§4.8) | conventions 7; native 3, **by a wrong value**: the int64 round trip read 0, 2³¹−1, −2³¹ and −1 (the low 32 bits, sign-extended); the oracle's columns and the written-out columns |
| T03 | both bound with `int`, and the table's two rows loosened with them | conventions 1 (the §4.8 sweep); constants 1 (the map names both rows); native 3 |
| T04 | `sqlite3_bind_double`: `double` to `float` | conventions 7; native 1: the REAL round trip |
| T05 | `sqlite3_column_double`: `double` to `float` | conventions 7; native 3: the REAL round trip, the oracle's columns, the written-out columns |
| T06 | `sqlite3_bind_text64`: `unsigned-64` to `unsigned-32` | conventions 7; native 1: the TOOBIG row of the text, **by a raise**: "invalid foreign-procedure argument 4294967297", where SQLite answers 18 (the review's fix 3) |
| T07 | `sqlite3_bind_blob64`: `unsigned-64` to `unsigned-32` | conventions 7; native 1: the TOOBIG row of the blob, by the same raise |
| T08 | `sqlite3_bind_text64`: `unsigned-8` to `unsigned-32` | conventions 7; native none |
| T09 | `sqlite3_prepare_v3`: `unsigned-int` to `int` | conventions 7; native none |
| T10 | `sqlite3_bind_double` loosened to `float` in native and the table alike | conventions 10 (`float` refused, the allowlists' rows); constants 1 (the map); native 1 |
| T11 | the encoding as `unsigned int`, in native, the table and its prototype alike | conventions 2 (the allowlists' rows: `unsigned-8` now unused); constants 1 (the header declares `unsigned char`); native none |

T08, T09 and T11 are caught by form alone, as the brief expects of the convention suite. By
behaviour each is equivalent here: on amd64 and arm64 an argument narrower than a register is
passed in one, and the callee reads its low bits, so an encoding of 1 and flags of 0 arrive the
same.

T06 and T07 were first caught by form alone, on the reasoning that only a 4 GiB block could tell
`unsigned-32` from `unsigned-64`. That was wrong: a length is not a block. SQLite checks the length
against its limit before it reads or copies a byte, so a 1-byte block with the length 2³²+1 is
refused with `SQLITE_TOOBIG` (18) and the parameter stays NULL. The two TOOBIG rows bind that, and
an `unsigned-32` length makes Chez refuse the argument, so each mutant fails its row by a raise.

**Chez's `int`, measured.** An `int` argument takes −2³¹ to 2³²−1 and raises "invalid
foreign-procedure argument" beyond that range. Within it, 2³¹ to 2³²−1 reach the callee as the
negative numbers of the same 32 bits when the callee reads an `int`, and as themselves when it
reads a 64-bit register, whose upper half Chez leaves zero. So an `int` mutant is caught
**by a raise** in the int64 round trip when it binds a value past that range (T01: −2⁶³, −2³¹−1,
2⁶³−1), and **by a wrong value** when it reads one (T02: a result of `int` is the low 32 bits
sign-extended, so −2⁶³ reads 0). The earlier claim that `int` "passed 2³¹ unchanged" holds only
for a 64-bit callee, as `sqlite3_bind_int64` is.

### Conventions

| Mutation | Guards | Failed |
|---|---|---|
| C01 | `sqlite3_prepare_v3`'s `__collect_safe` dropped | conventions 7 |
| C02 | `sqlite3_finalize`'s dropped | conventions 7 |
| C03 | `sqlite3_step`'s dropped | conventions 7 |
| C04 | `sqlite3_reset`'s dropped | conventions 7 |
| C05 | `__collect_safe` added to `sqlite3_column_text` | conventions 7 |
| C06 | `__collect_safe` added to `sqlite3_bind_text64` | conventions 7 |
| C07 | `sqlite3_step` plain in native and the table alike | conventions 1: the table row that writes the six collect-safe names out |

`test-native` passed 66 in each: in this slice the four are held by form. Slice 3 holds them by
behaviour, each under a busy timeout and a second connection's lock (the brief, ADR-0011 amended).

### The allowlists

| Mutation | Guards | Failed |
|---|---|---|
| A01 | `unsigned-8` allowed as a result | conventions 4: the written-out allowlists, the used-types row, the argument-only row, the complement fixture |
| A02 | `float` allowed as an argument | conventions 4: the written-out allowlists, the used-types row, the complement's two rows |
| A03 | `unsigned-8` dropped from the argument allowlist | conventions 10: the allowlists' rows, `src/`'s violation, the sweeps |

### Names, order and eagerness

| Mutation | Guards | Failed |
|---|---|---|
| E01 | an entry point misspelt, `sqlite3_prepare_v4` | conventions 8 (`no-row` and `no-form`); native 55 (the load refused `missing-api`); library-loading 38 |
| E02 | two bindings swapped: `sqlite3_finalize` and `sqlite3_step` | native 2: the load-steps row and the eagerness row |
| E03 | `sqlite3_error_offset` moved before `sqlite3_prepare_v3` | native 2: the same |
| E04 | `missing-api` carries the report: `sqlite3_step` bound with `#f` | native 2: the same; library-loading 1: `lacks-sqlite3_step`, `(library . #f)` |
| E05 | eager binding: `sqlite3_error_offset` bound at each call | native 2: the same; library-loading 1: `lacks-sqlite3_error_offset` loaded |
| E06 | the table's rows for `sqlite3_finalize` and `sqlite3_step` swapped | conventions 1: the written-out order row |

E02 and E03 pass the convention suite and `test-library-loading`: the convention suite reads the
forms as a set, and a decoy lacking one entry point names it whatever the order. Only
`test-native`'s body rows hold the order; a decoy build lacking each adjacent pair would hold it by
behaviour, at a gated child each.

### The decoy

| Mutation | Guards | Failed |
|---|---|---|
| D01 | `sqlite3_step` dropped from the control build | library-loading 25: the seven accepted loads, and the 18 `lacks-` rows of the entry points after it, refused for `sqlite3_step` instead |
| D02 | `sqlite3_error_offset`, the last, dropped | library-loading 7: the accepted loads |
| D03 | a decoy definition with a prototype the header does not give: `bind_int64` taking `int` | library-loading 55: every build fails to compile (`-Werror`, conflicting types) |
| D04 | a switch misnamed: `DECOY_LACKS_sqlite3_rest` | library-loading 1: `lacks-sqlite3_reset`, loaded |

### The constants, each off by one

| Mutation | Guards | Failed |
|---|---|---|
| K01 | `sqlite-row` 101 | constants 1 (the values row, by name); native 13 |
| K02 | `sqlite-done` 102 | constants 1; native 13 |
| K03 | `sqlite-integer` 2 | constants 1; native 1: the int64 round trip |
| K04 | `sqlite-float` 3 | constants 1; native 2: the REAL round trip, the written-out columns |
| K05 | `sqlite-text` 4 | constants 1; native 1: the TEXT round trip |
| K06 | `sqlite-blob` 5 | constants 1; native 1: the BLOB row, both its round trips |
| K07 | `sqlite-null` 6 | constants 1; native 4: the null and clear-bindings rows, the two TOOBIG rows |
| K08 | `sqlite-utf8` 2, `SQLITE_UTF16LE` | constants 1; native 2: the TEXT round trip and the TEXT copy, whose bytes SQLite read as UTF-16 |

### `sqlite-transient`

| Mutation | Guards | Failed |
|---|---|---|
| S01 | 0, `SQLITE_STATIC` | native 6: the TEXT and BLOB round trips and copies, the header row, the form row |
| S02 | `#xFFFFFFFF`, a 32-bit all-ones value | native 9: SQLite called it as a destructor, and Chez raised "invalid memory reference", caught by each row's guard, the two TOOBIG rows among them; the header row, the form row |
| S03 | `#xFFFFFFFFFFFFFFFF`, the 64-bit literal | native 1: the form row alone. On a 64-bit machine the value is right |
| S04 | `(- (expt 2 64) 1)`, computed for one width | native 1: the form row (no `foreign-sizeof`) |
| S05 | all ones but the last bit | native 8: as S02, the binds' rows and the two TOOBIG rows raised "invalid memory reference", and the header row; the form row passed, the size still asked |
| S06 | −1, which a `uptr` takes as all ones (measured) | native 2: the header row (the oracle prints it unsigned) and the form row |

### Prepare's nByte

The slice binds prepare and calls it from the suite's own helper and from the oracle; slice 3's
verb computes nByte for callers.

| Mutation | Guards | Failed |
|---|---|---|
| B01 | the suite's nByte one short | native 13: every row whose SQL's last byte matters |
| B02 | the suite's nByte one long, the NUL counted | **none: survived** (below) |
| B03 | the suite's nByte the SQL's length in characters | native 2: the columns and the written-out columns, whose SQL is 18 bytes longer than its characters. The failed prepares passed: `select 'é', nosuchcol` cut one byte short still fails at byte 13 |
| B04 | the oracle's nByte one short | native 4: the oracle's read, its valgrind line, the columns, the shape |

### The oracle's `--rows` and `--transient` modes

| Mutation | Guards | Failed |
|---|---|---|
| O01 | `sqlite3_column_int64` read as an `int` | native 1: the columns, whole |
| O02 | the text's count read before `sqlite3_column_text` | **none: survived** (below) |
| O03 | the text printed one byte short | native 1: the columns, whole |
| O04 | `SQLITE_STATIC` printed for `SQLITE_TRANSIENT` | native 1: the header row |

O03 as first written put `column_blob`'s bytes in the text's place; it left `text` set but unused,
so `-Werror` refused the oracle's compile and 14 rows failed for that reason, not the one named.
It was rewritten to compile, and the count above is the rewritten one's.

### The suites' own rows, planted

| Mutation | Guards | Failed |
|---|---|---|
| R01 | the TEXT copy bound with 0, `SQLITE_STATIC`, outside Valgrind | native 1: the TEXT copy, which read the overwritten block |
| R02 | the BLOB copy bound with 0 | native 1: the BLOB copy |
| R03 | an empty value passed as a NULL pointer | native 1: the BLOB row, whose empty value read back NULL |
| R04 | the map: `double` mapped to `float` | constants 3: the written-out map, every `double` row by name, the plants' map row |
| R05 | the prototype check loosened: `_Generic` answers 1 for any type | constants 4: every planted prototype row |

### The review's mutations

| Mutation | Guards | Failed |
|---|---|---|
| N10 | `"sqlite3_column_blob"` deleted from the decoy's entry list | library-loading 1: the entry-list row (90 passed, before the row 90 of 90: its build and its `missing-api` row went with it) |
| N11 | four entries of the list reordered: `sqlite3_prepare_v3`, `_finalize`, `_step`, `_reset` | library-loading 1: the same row (91 passed; before it 91 of 91) |
| N12 | the columns SQL's boundary values replaced with 1 to 4, 0.0, 1.0, 0.0 | native 1: the written-out columns (68 passed; before the row 66 of 66) |
| N13 | one boundary integer changed by one: 2³¹ to 2³¹+1 | native 1: the same row (68 passed) |

## The review's fixes

An adversarial review of the slice found five things. Each fix was written first and watched fail
against a mutant in a whole copy of the tree (`build/m2s2-fix/`).

1. **The decoy's entry list was held to nothing.** An entry dropped from `every-entry` took its
   build and its `missing-api` row with it, and a reordering moved the rows. Now
   `test-library-loading` asserts the list equals `(map row-name conventions-table)`, whole and in
   order; `test-conventions` holds that table to native, in ADR-0002's order. N10 and N11 fail it.
2. **The columns row's coverage rested on SQL nothing asserted.** The row held native's reading to
   the oracle's, so tame values in the SQL still passed (N12, 66 of 66). Now a second row writes
   out, from the oracle's reading on both libraries, each column's name bytes, type, int64 and
   double bits, and the text and blob bytes of every column that is no REAL. A REAL's text, its
   byte count and its blob differ between 3.45.1 and 3.53.1 and stay with the oracle. N12 and N13
   fail it, and T02, T05 and K04 now fail it too.
3. **A length past 32 bits was held by form only.** One row each for `sqlite3_bind_text64` and
   `sqlite3_bind_blob64` binds a 1-byte block with the length 2³²+1 and asserts `SQLITE_TOOBIG`
   and a parameter that `typeof` still names null. T06 and T07 now fail them, by a raise. The
   log's reason, that no row can bind 4 GiB, was wrong.
4. **The oracle's comment** said each column's calls run "in this order, each once";
   `sqlite3_column_bytes` runs twice, after `_text` and after `_blob`. The comment says so.
5. **This log:** N10 to N13, T06 and T07 by behaviour, the `int` claim corrected (under T06 to T09
   above), and the totals and the red runs rerun.

## The survivors

| Mutation | Why it is equivalent |
|---|---|
| B02 | nByte one long counts the NUL `call-with-c-string` writes after the SQL. SQLite reads up to nByte or the first NUL, whichever comes first, and its documentation recommends counting the terminator when the string has one. So the same bytes are prepared, and the tail is the same. |
| O02 | In a UTF-8 database, `sqlite3_column_bytes` converts a numeric value to UTF-8 text exactly as `sqlite3_column_text` does, and leaves TEXT and BLOB alone, so either order gives the same pointer and count. The documented order matters when the `16` forms are mixed in; the oracle opens `:memory:` in UTF-8 and calls neither. |

By behaviour alone T08, T09 and T11 (argued above), C01 to C06 (slice 3's), E02 and E03 (order,
held by the body rows) and S03 (a literal right on this width) would survive; each is caught by
form.

## Findings

- **A REAL's text differs between SQLite versions** (`build/m2s2/probe-traps.sps`):
  `cast(4.9406564584124654e-324 as text)` is `4.9406564584124654e-324` on 3.53.1 and
  `4.94065645841247e-324` on 3.45.1; `2.2250738585072014e-308` is `2.2250738585072e-308` there.
  `0.1`, `1.0e+308` and `0.0` agree. So the columns row writes no expected value: native and the
  oracle read the one library.
- **Chez's `uptr` takes −1 as all ones,** and 2⁶⁴−1 the same; it refuses 2⁶⁴ (the same probe,
  through `labs`). So `SQLITE_TRANSIENT` written −1 behaves as `sqlite-transient` does, and only
  the header row and the form row tell them apart (S06).
- **A call through a bad function pointer raised in Chez** (S02): SQLite called `0xFFFFFFFF` as a
  destructor, and the suite got a catchable "invalid memory reference" where a crash was expected.
  The rows failed by name, but the TEXT row's finalize raised it, so the statement stayed open and
  the close answered `SQLITE_BUSY`.
- **`test-library-loading` spawns its children with `--libdirs src`,** so a native planted on a
  prefix of the parent's library path never reaches them. Its red run, and every mutation here,
  ran in a copy of the tree.
- **The convention suite's complement held the four types this slice allows** (`unsigned-8`,
  `unsigned-64`, `unsigned-int`, `double`), and the `types` fixture numbers its bindings by
  position in that list: allowing a type renumbers every later binding. The fixture was
  regenerated from the suite's lists, and the result-only types got bindings of their own.
