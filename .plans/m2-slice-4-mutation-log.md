# M2 slice 4 mutation log: values, part A

Evidence that each rule the slice's suites claim to guard fails through the property it names
([M2 plan](2026-11-14-m2-plan.md), §4.3, §4.4, §4.8 and §5's slice 4; ADR-0015; ADR-0014's slice 3
amendment). Format of [the M2 slice 3 log](m2-slice-3-mutation-log.md).

Part A is `(chez-sqlite3 private statement-values)`, new: `bind!`, `bind-all!`,
`clear-bindings!`, `column-value`, `column-bytevector` and `column-name`, each through
`call-with-statement-handle`. And three helpers in `(chez-sqlite3 private native)`, which the
brief was amended to allow: no library but native may read or write foreign memory (check-seam's
`library-only-chez-names`), and native had no byte helper:

- `call-with-bytes`: a copy of a bytevector's bytes in a counted block of at least one byte, the
  extra byte of an empty one written 0, built on `call-with-block`;
- `foreign-bytes`: N bytes at an address, copied into a fresh bytevector;
- `c-string->bytevector`: the bytes up to a NUL, undecoded. `c-string->string` reads through it.

The suites are `tests/test-statement-values.sps`, `tests/test-statement-values-nomem.sps`
(NOMEM, in a process of its own, since the heap limit is process-wide) and
`tests/test-statement-values-sections.sps` (the two-engine sweeps), and `tests/test-native.sps`'s
new rows. An Opus agent built it test first from the maintainer's brief.

Every mutation ran in its own copy of `src/` and `tests/`, made under the worktree's git-ignored
`build/m2s4/mut/run/`, and its suites ran from inside the copy, with the worktree's SRFI
libraries, outside the gate. The driver, `build/m2s4/mut/mut.py`, refused any edit whose old text
did not occur exactly the stated number of times (each did), and any mutant that changed nothing.
The definitions are `build/m2s4/mut/defs.py`; the tables below are made from the suites' own output
(`# of expected passes`, `# of unexpected failures`) by `build/m2s4/mut/tables.py`, never by eye,
from one run against the final tree on each library. The plant P01 also ran under the gate, in
whole copies of the worktree, `build/m2s4/gate/`. None of it is in the repository.

## The red runs

| Suite | Red run | Against | Green run |
|---|---|---|---|
| `test-native` | 69 passed, 13 failed | the 12 new rows and the widened export row, over native as it stood | 82 passed |
| `test-statement-values` | 4 passed, 43 failed | a stub `statement-values.sls`: every export, none doing its work | 47 passed |
| `test-statement-values-nomem` | 3 passed, 7 failed | the same stub | 10 passed |
| `test-statement-values-sections` | 2 passed, 5 failed | the same stub, the suite's first 7 rows | 9 passed |

The rows that passed against the stub: the load, the counts once loaded, the export list (the stub
exported the same names) and the counts at the end, in each suite that has them; E01 to E03 watch
them fail, and E04 the load rows. The sections suite grew 2 rows after its red run, each watched
failing by the mutant named in its place: `column-name` against a dropped column (K03), and a name
changed by another engine while `bind!` runs (X12). Every row of the three new suites, and every
new row of `test-native`, has failed under at least one mutation or red run.

Final green runs, the baseline B00, every row passed:

| Suite | 3.53.1 | 3.45.1 |
|---|---|---|
| `test-native` | 82 passed | 82 passed |
| `test-statement-values` | 47 passed | 47 passed |
| `test-statement-values-nomem` | 10 passed | 10 passed |
| `test-statement-values-sections` | 9 passed | 9 passed |
| `test-statement` | 75 passed | 75 passed |
| `test-connection` | 63 passed | 63 passed |

`make test` ran 37 suites on each library, and passed all but part B's `test-never-loads`, whose
list of the libraries that load libsqlite3 now finds this one.

## Measured first

Through bare FFI, on Guix's 3.53.1 and the floor, 3.45.1, each run twice per library and compared
byte for byte (`build/m2s4/probes/`). The outputs differ in the version line alone.

- **A bound TEXT's NOMEM, inside a transaction** (`nomem-bound.sps`). The research measured the
  transaction's rollback through `sqlite3_column_text16`; this slice reads `column_text`. A
  100,000-byte TEXT bound with its length and read back under `sqlite3_hard_heap_limit64` of
  `sqlite3_memory_used() + 1000`: `column_text` answered NULL, extended code 7, the type then 5 and
  the bytes 0; the reset answered 7, then 0. Inside `begin`, after an insert into `u`:
  `select ?1 from src`, which reads a table, left autocommit 1 and the marker gone after the reset;
  `select ?1`, which reads none, left autocommit 0 and the marker there.
- **`column-name`'s NULL, for real** (`name-nomem.sps`). `sqlite3_column_name16`, which the suite
  binds and chez-sqlite3 never calls, converts a name in place. Then, under the same limit,
  `sqlite3_column_name` of a 5,000-byte alias answered NULL, and the extended code stayed what it
  was, 0 after the prepare and 100 after a step. Without the limit it read the 5,000 bytes again.
  So the path ADR-0015 decision 9 and the M2 plan §4.4 call unreachable on a real library is held
  by a real row here, beside slice 1's stand-ins.
- **A UTF-16 database's accessors** (`utf16-accessors.sps`). In `UTF-16le`, TEXT `é` reads `C3 A9`
  through `column_text` and `E9 00` through `column_blob`; `aé` `61 C3 A9` and `61 00 E9 00`; the
  empty TEXT a pointer to none and NULL. A BLOB `x'4100'` reads `41` through `column_text`, which
  turns its type to TEXT, and `41 00` through `column_blob`. So a TEXT read through the wrong
  accessor, and a BLOB, are both seen in a UTF-16 database, where a UTF-8 one shows neither.
- **A count past a dropped column** (the same probe). A held `select * from d` of three columns
  answers 3, then 2 after `alter table d drop column c`, a reset and a step, and
  `sqlite3_column_type` of column 2 then answers 5, NULL: a read past a stale count is no error to
  SQLite, so only a count read with the read refuses it.
- **The parameter count across a reprepare** (`param-count-reprepare.sps`). `select ?1, :x, * from
  t` has 2 parameters and 4 columns; after an `add column` and the step that reprepares it, 2 and 5;
  after a `drop column` and a step, 2 and 4. The parameters are the SQL's.
- **`call-with-bytes` under an engine** (`bytes-engine.sps`). Its fill runs outside
  `call-with-block`'s critical thunks, so an engine's expiry there unwinds the extent and frees the
  block, and the resume is refused, "re-entered after its block was freed", as native's comment says
  of every helper. Under the tree, fuels 1 to 60 all expired before the copy; under H01, with no
  copy, one expired in the fill and was refused. So `call-with-bytes` is for a caller in a section,
  as the verbs are, and no engine row can hold its copy (H01, below).

## The mutations

**83 mutations by the driver, 78 caught, 5 survived, and E04 by hand, caught:
84 in all, 79 caught;** each survivor is argued below. Each row
names the suites that failed and how many of their rows, on Guix's 3.53.1; where the floor's count
differs, it follows in parentheses. A suite run and not named passed whole. `native` is
`test-native`, `values` `test-statement-values`, `nomem` its NOMEM suite, `sections` its sweeps,
`statement` `test-statement`.

### Native's three helpers

| Mutation | Guards | Failed |
|---|---|---|
| H01 | call-with-bytes writes the caller's bytevector, uncopied | **none: survived** (below) |
| H02 | call-with-bytes' block exactly n bytes, none for an empty value | native 1; values 2 |
| H03 | call-with-bytes leaves an empty value's one byte unwritten | native 1 |
| H04 | call-with-bytes writes one byte too few | native 1; values 11 (the floor 10) |
| H05 | call-with-bytes' bytevector check dropped | native 2 |
| H06 | call-with-bytes' procedure check dropped | native 2 |
| H07 | call-with-bytes' who check dropped | native 2 |
| H08 | call-with-bytes makes and frees its block without call-with-block's extent | native 9 |
| H09 | foreign-bytes reads the address even for none | native 1 |
| H10 | foreign-bytes reads one byte too few | native 12 (the floor 13); values 30 |
| H11 | foreign-bytes' address check dropped | native 1 |
| H12 | foreign-bytes' count check dropped | native 1 |
| H13 | foreign-bytes' NULL check dropped | native 1 |
| H14 | c-string->bytevector keeps the NUL | native 9; values 4; statement 1 |
| H15 | c-string->bytevector answers no bytes for NULL | native 2 |
| H16 | c-string->bytevector's address check dropped | native 1 |

H04, H10 and X02 (below) read bytes nothing wrote, or a freed block holds: H04's block keeps a
byte it never wrote, H10's bytevector a byte `make-bytevector` never filled, and X02 reads a block
freed after its bind. So their counts depend on that memory, and differ by a row between the two
libraries; H04 and X02 were each steady over three runs on one library.

H09 and H13 read address 0. Chez makes that a condition, "invalid memory reference", which the
row's guard catches, so each fails by its row and the suite goes on. H14 shows that
`c-string->string` reads through `c-string->bytevector`: the NUL kept fails `test-native`'s
C-string rows and `test-statement`'s trigger message too.

### Each refusal dropped

| Mutation | Guards | Failed |
|---|---|---|
| R01 | not-a-parameter dropped: anything else taken as an index | values 1 |
| R02 | parameter-out-of-range dropped | values 3 |
| R03 | parameter-name-holds-nul dropped | values 2; sections 1 |
| R04 | no-such-parameter dropped: index 0 bound | values 3 |
| R05 | bind!'s value refusal dropped | values 5 |
| R06 | bind-all!'s value refusals dropped | values 2 |
| R07 | value-count-mismatch dropped | values 3 |
| R08 | not-a-column-index dropped | values 2 |
| R09 | column-out-of-range dropped | values 3; sections 2 |
| R10 | not-text-or-blob dropped for an INTEGER: read as int64 | values 2 |
| R11 | not-text-or-blob dropped for a FLOAT: read as a double | values 1 |
| R12 | bind!'s state check: its verb one every live state allows | values 3; sections 1 |
| R13 | bind-all!'s state check: a verb every live state allows | values 1 |
| R14 | column-value's state check: a verb every live state allows | values 2; nomem 1; sections 1 |
| R15 | column-bytevector's state check: a verb every live state allows | values 1; nomem 1 |
| R16 | column-name allowed in row alone | values 4; nomem 2 |

### Each boundary moved by one

| Mutation | Guards | Failed |
|---|---|---|
| D01 | a parameter index from 0 | values 2 |
| D02 | a parameter index below the count | values 23; nomem 6; sections 1 |
| D03 | a parameter index to the count plus 1 | values 1 |
| D04 | a column index from 1 | values 35; nomem 7; sections 5 |
| D05 | a column index to the count | values 3; sections 2 |
| D06 | the integer range's top at 2^63 (values.sls, in the copy) | values 1 |
| D07 | the integer range's bottom above -2^63 | values 1 |
| D08 | the integer range's bottom at -2^63-1 | values 1 |
| D09 | bind-all! from parameter 0 | values 5; sections 2 |

D06 to D08 are slice 1's `bind-plan`, mutated in the copy: the rows here hold its boundaries end to
end, on a real library. Chez's `integer-64` wraps 2⁶³ to −2⁶³ (D06), and refuses −2⁶³−1 from
inside the bind's section (D08), where `call-with-open-handle` catches it.

### Each type read through the wrong accessor

| Mutation | Guards | Failed |
|---|---|---|
| A01 | TEXT read through sqlite3_column_blob | values 1; nomem 6 |
| A02 | BLOB read through sqlite3_column_text | values 2 |
| A03 | INTEGER read through sqlite3_column_double | values 19; nomem 1; sections 2 |
| A04 | FLOAT read through sqlite3_column_int64 | values 6; sections 1 |
| A05 | column-bytevector's TEXT read through sqlite3_column_blob | values 1; nomem 2 |

A01 and A05 also fail the NOMEM rows: `sqlite3_column_blob` on a bound TEXT allocates nothing,
since it needs no NUL, so the read under the limit succeeds.

### The order of the reads

| Mutation | Guards | Failed |
|---|---|---|
| O01 | the bytes counted before the pointer | **none: survived** (below) |
| O02 | the type read after the value: column_text first | values 8; nomem 6 |

### The decoder made lenient

| Mutation | Guards | Failed |
|---|---|---|
| L01 | TEXT and names decoded by utf8->string | values 6 |
| L02 | names alone decoded by utf8->string | values 3 |
| L03 | TEXT values alone decoded by utf8->string | values 4 |

### NOMEM

| Mutation | Guards | Failed |
|---|---|---|
| N01 | the NOMEM read's move to failed dropped | nomem 6 |
| N02 | column-name's NOMEM moves the state to failed | nomem 1 |
| N03 | column-name's NOMEM message sqlite3_errmsg's, not sqlite3_errstr's | nomem 1 |

### A block or a C string made outside the section

| Mutation | Guards | Failed |
|---|---|---|
| C01 | a name's C string made outside the section | sections 2 |
| C02 | a TEXT's block made outside the section | sections 2 |

### Each count read outside its section

| Mutation | Guards | Failed |
|---|---|---|
| K01 | bind!'s parameter count read in a section of its own, before the bind's | **none: survived** (below) |
| K02 | column-value's column count read in a section of its own | sections 1 |
| K03 | column-name's column count read in a section of its own | values 1; sections 1 |
| K04 | bind-all!'s parameter count read in a section of its own | **none: survived** (below) |

### Each raise moved inside a section

| Mutation | Guards | Failed |
|---|---|---|
| I01 | the refusals raised inside a critical section | values 3 |
| I02 | a value's refusal raised inside a critical section | values 2 |
| I03 | SQLite's failures raised inside a critical section | values 2; nomem 1 |
| I04 | &sqlite-invalid-text raised inside a critical section | values 1 |
| I05 | bind!'s parameter refusal raised inside the accessor's procedure | **none: survived** (below) |

### The plants (the M2 plan, §4.8)

| Mutation | Guards | Failed |
|---|---|---|
| P01 | clear-bindings! let through while a row is ready | values 3 |
| P02 | a boolean guessed from a declared type | values 1 |
| P03 | parameters numbered from 0 | values 23; nomem 6; sections 1 |

**P01 under the gate.** In a whole copy of the worktree, `make test-memory
MEMORY_SUITES=tests/test-statement-values.sps` failed the suite, "exit 9, Valgrind's: an error or
a definite leak", on both libraries; the suite's own rows were 44 passed, 3 failed. The row's
5,000-byte BLOB, read after the `clear-bindings!` the plant lets through, is read byte by byte by
`foreign-bytes`, and each byte is an invalid read. Valgrind's report at the floor, which has symbols, scrubbed of the
checkout's path and the store's hashes:

```
==847== Invalid read of size 1
==847==    at 0x7158B8A: ???
==847==    by 0x4C5AA8F: ???
==847==    by 0x416B51: S_call_help (in /gnu/store/…-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme)
==847==  Address 0x9a1bdf8 is 8 bytes inside a block of size 5,008 free'd
==847==    at 0x48489EB: free (in /gnu/store/…-valgrind-3.27.0/libexec/valgrind/vgpreload_memcheck-amd64-linux.so)
==847==    by 0x510B6C5: sqlite3MemFree (in <checkout>/build/m2s1-floor/libsqlite3-floor.so)
==847==    by 0x510DDCF: sqlite3_free (in <checkout>/build/m2s1-floor/libsqlite3-floor.so)
==847==    by 0x510DE27: sqlite3DbFreeNN (in <checkout>/build/m2s1-floor/libsqlite3-floor.so)
==847==    by 0x510ECF6: vdbeMemClear (in <checkout>/build/m2s1-floor/libsqlite3-floor.so)
==847==    by 0x510ED16: sqlite3VdbeMemRelease (in <checkout>/build/m2s1-floor/libsqlite3-floor.so)
==847==    by 0x510ED66: sqlite3_clear_bindings (in <checkout>/build/m2s1-floor/libsqlite3-floor.so)
==847==  Block was alloc'd at
==847==    at 0x4845772: malloc (in /gnu/store/…-valgrind-3.27.0/libexec/valgrind/vgpreload_memcheck-amd64-linux.so)
==847==    by 0x512CEB6: sqlite3MemMalloc (in <checkout>/build/m2s1-floor/libsqlite3-floor.so)
==847==    by 0x5110795: sqlite3Malloc (in <checkout>/build/m2s1-floor/libsqlite3-floor.so)
==847==    by 0x5118D01: dbMallocRawFinish (in <checkout>/build/m2s1-floor/libsqlite3-floor.so)
==847==    by 0x5118D47: sqlite3DbMallocRawNN (in <checkout>/build/m2s1-floor/libsqlite3-floor.so)
==847==    by 0x51148B1: sqlite3DbMallocRaw (in <checkout>/build/m2s1-floor/libsqlite3-floor.so)
==847==    by 0x511C653: sqlite3VdbeMemGrow (in <checkout>/build/m2s1-floor/libsqlite3-floor.so)
==847==    by 0x511C766: sqlite3VdbeMemClearAndResize (in <checkout>/build/m2s1-floor/libsqlite3-floor.so)
==847==    by 0x511D574: sqlite3VdbeMemSetStr (in <checkout>/build/m2s1-floor/libsqlite3-floor.so)
==847==    definitely lost: 0 bytes in 0 blocks
==847== ERROR SUMMARY: 5000 errors from 1 contexts (suppressed: 0 from 0)
```

On 3.53.1 the same: an invalid read of size 1, 8 bytes inside a freed block of 5,008 bytes, freed
under `sqlite3_clear_bindings`, its inner frames unnamed (`???`, Guix's library is stripped), and
"ERROR SUMMARY: 5000 errors from 1 contexts". ADR-0005's amendment measured the same block size.
The gate needs no new plant program: P01 is a planted copy of the library, and the plant programs
`check-memory-gate` holds stay as they were.

### The rest

| Mutation | Guards | Failed |
|---|---|---|
| X01 | TEXT bound with SQLITE_STATIC, not SQLITE_TRANSIENT | values 7; nomem 1; sections 2 |
| X02 | BLOB bound with SQLITE_STATIC | values 5 (the floor 6); sections 1 |
| X03 | TEXT bound one byte long | values 7; nomem 1; sections 2 |
| X04 | TEXT bound as UTF-16LE | values 9; nomem 6; sections 2 |
| X05 | a failure's SQL dropped | values 4 |
| X06 | a refused bind leaves the statement failed | values 2 |
| X07 | bind-all! binds from the last parameter to the first | values 1 |
| X08 | clear-bindings! calls nothing | values 1 |
| X09 | NULL read as the empty list, not sql-null | values 6; sections 2 |
| X10 | a bind failure's message read before the bind | values 1 |
| X11 | a TEXT column decoded as bytes: column-value answers its bytevector | values 24; nomem 1; sections 4 |
| X12 | a parameter's name checked and used uncopied | sections 1 |

X02's count depends on freed memory, as H04's and H10's do (above).

### The load

| Mutation | Guards | Failed |
|---|---|---|
| E01 | an export more: finish | values 1 |
| E02 | the library body allocates a counted block it never frees | values 21; nomem 4; sections 3 |
| E03 | the library body raises at its first reference | values 43; nomem 7; sections 8 |

E04, run by hand on 3.53.1, is `CHEZ_SQLITE3_LIBRARY` naming no file: `test-statement-values` 3
passed, 44 failed, its load row among them; the NOMEM suite 1 passed, 2 failed, and its 7 NOMEM
rows named unavailable and skipped, never passed; the sections suite 1 passed, 8 failed. The load
rows reach `(chez-sqlite3)`, which imports this library only once part B exports its names, so no
mutation of the library fails them.

## The survivors

| Mutation | Why it is equivalent |
|---|---|
| H01 | `call-with-bytes` writes the caller's bytevector into the block, uncopied. The copy guards against another thread changing the bytevector while the block is written, which no row can stage: an engine on the same thread can't run inside the verbs' sections, and under an engine outside one the fill's expiry frees the block, and its resume is refused (`bytes-engine.sps`). Another thread can tear `bytevector-copy` as well as the fill, so the copy narrows the window and closes none. Every caller in `src/` hands it a bytevector `bind-plan` has just made, which no other code holds. The coordinator's settled design asked for the copy, as `call-with-c-string` copies its string, and it stays. |
| O01 | The bytes counted before the pointer. SQLite's documentation orders `column_text` then `column_bytes` because a later conversion can invalidate a pointer; `column_bytes` counts in UTF-8, the encoding `column_text` asks for, so read first it converts a UTF-16 TEXT to UTF-8 in place and counts that, and the pointer read after is the same text's. For a BLOB neither converts. So on every read the verbs make, the count is the same either way: the UTF-16 row, which converts, the bound TEXT that `column_text` must copy to end with a NUL, and the NOMEM rows all pass under O01, on both libraries. The order lives in slice 1's `read-column-bytes`, held by its stand-ins. |
| K01 | `bind!`'s parameter count read in a section of its own, before the bind's. The count is the SQL's: it stayed 2 across a reprepare that added a column and one that dropped one, on both libraries (`param-count-reprepare.sps`), so a count read earlier is the count now. The bind's own section makes decision 3's checks and the state's again, so another engine's finalize or step between the two is refused there: the bind-against-step sweep passes under K01. |
| K04 | The same for `bind-all!`. |
| I05 | `bind!`'s parameter refusal raised inside the accessor's procedure, not answered as data. `call-with-open-handle` catches what its procedure raises inside its section and raises it again after, the same object (ADR-0012, amended), so a handler still runs at depth 1. Slice 3's I07 is the same. Only a raise in a section of the library's own reaches a handler with interrupts disabled, and I01 to I04 make one: each is caught. |

## Findings

- **No library but native could copy a value's bytes, and the brief forbade a change to native.**
  Binding TEXT and BLOB, reading them, and decoding a column's name strictly each need
  `foreign-ref` or `foreign-set!`, which check-seam lets only native import. A probe of check-seam
  on a library that imports them failed, naming rule (f). The coordinator amended the brief to add
  the three helpers, keeping ADR-0011's design and every seam list as they were.
- **`column_name`'s NULL is reachable for real,** through a suite's own `sqlite3_column_name16` and
  a heap limit, and sets no code, on both libraries. ADR-0015 decision 9 and the M2 plan §4.4 say
  neither out-of-memory path can be caused on a real library; the research found the value path,
  and this slice the name's.
- **A read past a stale column count answers NULL, not an error.** So a count read in a section of
  its own (K02, K03) gives `sql-null` or `nomem` at the fuels where another engine dropped the
  column between: only the count read with the read refuses it.
- **`call-with-bytes`, like every native helper, is for a caller inside a section.** An engine's
  expiry during its fill frees the block. The verbs hold it inside the accessor's section; a caller
  under engines outside one would see its resume refused.
- **A sweep that passes when A always finishes first holds nothing.** Each sweep row asserts the
  three kinds of interleaving its fuels reached, B before A's section, B after it, and A finished
  first, beside every fuel's verdict.

## Part B: the public names and their docs

Part B makes the value verbs public, documents them, and updates the suites that hold the public
surface: `src/chez-sqlite3.sls` (eleven exports), `docs/reference.md` (a "Values" section, three
entries in "Conditions", the types block, the Conditions table), `tests/test-public.sps` and
`tests/test-never-loads.sps`. Built test first by a Sonnet agent. `test-reference` and `test-docs`
needed no row of their own: they read the page and the source, so each new entry and example is a
row already. `test-native`'s export row already holds the three byte helpers (part A), and
`test-public` has no row for native.

The eleven exports: `bind!`, `bind-all!`, `clear-bindings!`, `column-value`, `column-bytevector`
and `column-name` from `(chez-sqlite3 private statement-values)`; `sql-null` and `sql-null?` from
`(chez-sqlite3 private values)`; `sqlite-invalid-text?`, `sqlite-invalid-text-column` and
`sqlite-invalid-text-offset` from `(chez-sqlite3 private conditions)`. None of the three was public
before. `(chez-sqlite3 private connection)`'s private list did not change.

Mutations ran in whole copies of the worktree (less `build/` and `.git/`, with `build/scheme-libs`
linked) under the git-ignored `build/m2s4b/mut/run/`, each suite run from inside its copy. The
driver is `build/m2s4b/mut/mut.py`, its definitions `defs.py`; it refused an edit whose old text did
not occur exactly once, and one that changed nothing. Not in the repository. Counts are read from
the suites' own `# of expected passes` and `# of unexpected failures` lines.

### The red runs

| Suite | Red run | Against | Green run |
|---|---|---|---|
| `test-public` | 17 passed, 2 failed: the export list, and the eq? row | the new rows (11 more names, the private library of each) over the old `src/chez-sqlite3.sls` | 19 passed |
| `test-never-loads` | 4 passed, 1 failed: the loaders row, `(chez-sqlite3 private statement-values)` found and not expected | the old list, over the tree as part A left it | 5 passed |
| `test-reference` | 17 passed, 2 failed: every export has an entry (11 without one), the entries are the exports | the new exports over the old page | 19 passed |

`test-public`'s row "(chez-sqlite3) names 40 exports", now 51, counts the suite's own list and so
passed before the source changed: the two rows above are what held the names. `test-docs` has no red
run of its own: its rows are the page's blocks, and the six new runnable examples add 12 rows (57
to 69, the old page run under the new suite). A wrong stated result fails it (D01 to D06).

Final green runs, on Guix's 3.53.1: `make test` 37 of 37. On the floor, 3.45.1
(`CHEZ_SQLITE3_LIBRARY=$PWD/build/m2s1-floor/libsqlite3-floor.so`): 37 of 37. `test-public` 19,
`test-reference` 19, `test-docs` 69, `test-never-loads` 5. `make check-seam` (21 libraries) and
`make check-suites` (37 suites) pass. `make test-memory` on the four suites: all pass, 52 s in all.

### The mutations

**39 mutations, 39 caught.** Each is `passed/failed` of the suite named. Baseline B00: `test-public`
19/0, `test-reference` 19/0, `test-docs` 69/0, `test-never-loads` 5/0.

| Mutation | What | Failed |
|---|---|---|
| A01 to A11 | the name dropped from `(chez-sqlite3)`'s export clause, one per new export | `test-public` 2 and `test-reference` 3 each (the exports, the eq? row; no entry for an export, the entries as sorted lists, a signature comment for a name not exported); `test-docs` by the examples and prose that name it: A01 2, A02 1, A03 1, A04 5, A05 1, A06 1, A07 1, A08 3, A09 2, A10 2, A11 2 |
| B01 to B11 | the export's signature comment changed (` X` appended) | `test-reference` 1 each: the entry's line differs from its comment |
| C01 to C11 | the page's entry dropped | `test-reference` 2 each: the export has no entry, the entries are not the exports; `test-docs` 2 fewer rows for each of C01 to C06, whose runnable example went with it (not failures) |
| D01 to D06 | a runnable example's stated result changed, one per example | `test-docs` 1 each |

A09 to A11 fail `test-docs` by the `column-bytevector` example, whose `guard` names the predicate
and both accessors, and by the rule that every `sqlite-` code span of the prose is an export. The full lines are in
`build/m2s4b/mut/report-guix.txt`.

The `test-never-loads` list is held by its red run alone: no mutation of `src/` makes
`(chez-sqlite3 private statement-values)` load or not load libsqlite3 without breaking the library.
