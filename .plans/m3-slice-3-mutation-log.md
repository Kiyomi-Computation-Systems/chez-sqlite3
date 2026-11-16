# M3 slice 3 mutation log

Evidence that each rule slice 3's suites claim to guard fails through the property it names
([M3 plan](2026-11-15-m3-plan.md) §5, slice 3). Format of
[the M3 slice 1 log](m3-slice-1-mutation-log.md). The slice is built in four parts, A to D, each
keeping its own part of this log.

## Part A: the internals the conveniences stand on

Part A changes three of M2's libraries and adds no library:

- **`(chez-sqlite3 private statement)`:** `prepared` and `finalized` exported as they stood, the
  who-taking `step!/who`, `reset!/who` and `column-count/who`, with M2's verbs as thin wrappers;
  `checked-sql` exported; `prepared-at`, the prepare with flags and its tail (finding F1); and
  the cache's `checked-out` and `returned` (ADR-0020).
- **`(chez-sqlite3 private statement-values)`:** `bind!/who`, `bind-all!/who`,
  `clear-bindings!/who`, `column-value/who`, `column-bytevector/who` and `column-name/who`, M2's six
  verbs as thin wrappers; and `bind-each!/who`, bind-all!'s rule one value a section (Q15).
- **`(chez-sqlite3 private connection)`:** the record's statement cache, slice 1's table, 32 by
  default; `open-database-with-cache-capacity`, the suites' opener of a given capacity; the close
  emptying the cache on every path; and the counters `changes`, `total-changes`,
  `last-insert-rowid` and `in-transaction?`.

Its suites: `test-statement-who`, `test-connection-cache` and `test-change-counters`, new; a NOMEM
row in `test-statement-values-nomem`; and the export rows of `test-statement`,
`test-statement-values` and `test-public`, each list grown by the new names. An Opus agent built
it from the lead's brief, in the slice's worktree.

Every mutation ran in one of six copies of the worktree, made under its git-ignored `build/mut/`
without `.git` or `build/`, through that copy's own `scripts/guix-env`, after `make deps` in the
copy. A mutation changes one place in one library under `src/`; the driver checks that the old
text occurs once in the worktree's file (each did), writes the mutant into the copy, runs the ten
suites below, each under `timeout 300`, and puts the file back. The counts are read from the
suites' own output (`# of unexpected failures`), never by eye; a suite that died with no count is
marked `died`, and one that timed out `hung` (none did). Every suite a mutation left passing ran
at its green count, and every failing run counted all its rows. The driver and the mutation
definitions are in the session scratchpad, not the repository.

### The red runs

The suites were written against the brief, with the libraries, and run first against a copy whose
three libraries were `HEAD`'s, `0913468`, with the new exports added as stubs: each who-taking
internal called M2's verb, naming that verb; `prepared-at` answered `stub`; `checked-out` was
`prepare-statement` and `returned` `finalize-statement!`; the opener ignored its capacity, the
cache's procedures kept nothing, and the counters answered `stub`. The export rows ran against
`HEAD`'s libraries unchanged.

| Suite | Red run | Green run |
|---|---|---|
| `test-statement-who` | 5 passed, 20 failed | 25 passed |
| `test-connection-cache` | 2 passed, 20 failed | 22 passed |
| `test-change-counters` | 3 passed, 20 failed | 23 passed |
| `test-statement-values-nomem` | 13 passed, 1 failed, the new row | 14 passed |
| `test-statement`, against `HEAD` | 75 passed, 1 failed, the export row | 76 passed |
| `test-statement-values`, against `HEAD` | 46 passed, 1 failed, the export row | 47 passed |
| `test-public`, against `HEAD` | 18 passed, 1 failed, the export row | 19 passed |

The rows that passed red are rows a stub can satisfy:

- **each suite's load row and its counts rows,** at the start and, where the stubs leaked nothing,
  at the end;
- **`prepared`'s and `finalized`'s who rows:** M2's two already took a WHO (finding F11), and
  were only exported. S06 to S12 below watch both rows fail.

`bind-each!/who`'s row "binds nothing when its count or a value is refused" failed red by its who
alone, the stub being `bind-all!`; V11 watches it fail by what is bound.

Green: `make test` ran 47, passed 47, against the baseline's 44 of 44, the three new suites added.
At the floor, 3.45.1, through `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH`, the three new suites,
the NOMEM suite, `test-statement`, `test-statement-values` and `test-connection` passed at the
same counts. Under the memory gate, `make test-memory` on the eight changed or new suites passed
with no error and nothing lost, and again on the four new or grown ones once their last rows were
in, the three new suites taking 10 to 12 s each.

### The mutations

The ten suites: `test-statement-who` (who), `test-connection-cache` (cache),
`test-change-counters` (counters), `test-statement-values-nomem` (nomem), `test-statement`,
`test-statement-values`, `test-connection`, `test-statement-sections`,
`test-statement-values-sections` and `test-public`. Baselines, from the green runs: 25, 22, 23,
14, 76, 47, 63, 4, 9 and 19. Each row names the suites that failed and how many rows failed in
each. A mutation counts as caught when at least one row failed.

**87 mutations, 87 caught, none survived.** The whole set ran once, on the final libraries, which
no edit changed after it. Fourteen were rerun alone to read which row failed, and each was the row
written for it: S31 and S46 the two-engine race, V09 the one-value-a-section sweep, V11 the
binds-nothing row, S25 the tracking row, S21 and S28 the hand-over rows, S13 the lookaside row,
C07 the two failed closes, C04 the opener's order, S27 the two miss rows, S33 the failed step,
S35 the cleared binding, C22 call-with-database's capacity.

#### statement.sls: the who of M2's internals

| Mutation | Guards | Failed |
|---|---|---|
| S01 | step!/who's failed step names the who | who 1 |
| S02 | step!/who's accessor refusals name the who | who 1 |
| S03 | reset!/who's own failure names the who | who 1 |
| S04 | reset!/who's accessor refusals name the who | who 1 |
| S05 | column-count/who's refusals name the who | who 1 |
| S06 | finalized's own failure names the who | who 1, statement 3 |
| S07 | finalized's accessor refusals name the who | who 1 |
| S08 | prepared's database checks name the who | who 1, statement 1 |
| S09 | prepared's SQL checks name the who | who 1, statement 1 |
| S10 | a failed prepare names the who | who 2, statement 2 |
| S11 | no statement names the who | who 2, statement 2 |
| S12 | more than one statement names the who | who 2, statement 1 |

#### statement.sls: the flags

| Mutation | Guards | Failed |
|---|---|---|
| S13 | the string prepare passes its flags to SQLite (the cache's miss) | cache 1 |
| S14 | prepare-call passes the flags to sqlite3_prepare_v3 | who 1, cache 1 |
| S15 | prepared-at passes its flags to SQLite | who 1 |
| S16 | prepared-at refuses flags other than 0 and PERSISTENT | who 1 |

#### statement.sls: prepared-at

| Mutation | Guards | Failed |
|---|---|---|
| S17 | prepared-at accepts a start at the SQL's end | who 2 |
| S18 | prepared-at refuses a start past the SQL's end | who 1 |
| S19 | prepared-at prepares from the statement's start | who 3 |
| S20 | prepared-at's tail is a byte offset from the SQL's start | who 2 |
| S21 | prepared-at hands its statement to on-made | who 1 |
| S22 | prepared-at's statement holds its own text | who 3 |
| S23 | own-text keeps a leading U+FEFF (the strict decoder) | who 1 |
| S24 | prepared-at answers SQLite's raw offset, -1 kept | who 1 |
| S25 | prepared-at's statement is tracked | who 2 |
| S26 | prepared-at's statement is counted | who 9 |
| S45 | prepared-at's start refusal names the who | who 1 |

#### statement.sls: checked-out

| Mutation | Guards | Failed |
|---|---|---|
| S27 | checked-out hands out a hit only when it is ready | cache 2 |
| S28 | checked-out hands a hit to on-made | who 1 |
| S29 | checked-out prepares with no flags at capacity 0 | cache 1 |
| S30 | checked-out prepares PERSISTENT above capacity 0 | cache 1 |
| S31 | checked-out reads and changes the table inside the section | cache 1 |
| S32 | checked-out checks out the cache's statement | cache 3 |
| S43 | checked-out names the who for its on-made check | who 1 |
| S44 | checked-out's SQL checks name the who | who 1 |

#### statement.sls: returned

| Mutation | Guards | Failed |
|---|---|---|
| S33 | returned finalizes a failed statement, never filing it | cache 1 |
| S34 | returned does not file a statement whose reset failed | who 1, cache 1 |
| S35 | returned clears the bindings | cache 1 |
| S36 | returned finalizes what the table answers | who 1, cache 6 |
| S37 | returned's reset failure names the who | who 1, cache 1 |
| S38 | returned's accessor refusals name the who | who 1 |
| S39 | returned does nothing on a finalized statement | who 1 |
| S40 | returned finalizes a statement whose reset failed | who 1, cache 1 |
| S41 | returned raises a reset's failure | who 1, cache 1 |
| S42 | returned files under the statement's own SQL | cache 3 |
| S46 | returned changes the table inside the section | cache 1 |

#### statement-values.sls

| Mutation | Guards | Failed |
|---|---|---|
| V01 | bind!/who's raises name the who | who 1, nomem 1 |
| V02 | bind!'s accessor refusals name the who | who 2 |
| V03 | bind-all!/who's raises name the who | who 1 |
| V04 | bind-all!/who's accessor refusals name the who | who 1 |
| V05 | bind-each!/who's count section names the who | who 2 |
| V06 | bind-each!/who's count refusal names the who | who 2 |
| V07 | bind-each!/who's value refusal names the who | who 2 |
| V08 | bind-each!/who's binds name the who | who 1 |
| V09 | bind-each!/who binds each value in a section of its own | who 1 |
| V10 | bind-each!/who checks the count first | who 2 |
| V11 | bind-each!/who checks every value before any is bound | who 1 |
| V12 | clear-bindings!/who's raises name the who | who 1 |
| V13 | column-value/who's raises name the who | who 1, nomem 1 |
| V14 | column-value/who's accessor refusals name the who | who 1 |
| V15 | column-bytevector/who's raises name the who | who 1, nomem 1 |
| V16 | column-bytevector/who's accessor refusals name the who | who 1 |
| V17 | column-name/who's raises name the who | who 1, nomem 1 |
| V18 | column-name/who's accessor refusals name the who | who 1 |

#### connection.sls: the cache in the record

| Mutation | Guards | Failed |
|---|---|---|
| C01 | the record's cache has the capacity it is made with | cache 6 |
| C02 | the default capacity is 32 | cache 2 |
| C03 | the opener refuses a capacity outside 0 to 1024 | cache 9 |
| C04 | the opener checks its capacity before the filename | cache 1 |
| C05 | the opener gives the record its capacity | cache 6 |
| C06 | the close empties the cache | cache 4 |
| C07 | the close empties the cache when it fails too | cache 2 |
| C08 | a check-out reads the record's table | cache 3 |
| C09 | a return files in the record's table | cache 9 |
| C10 | database-cache-count checks its database | cache 1 |
| C11 | database-cache-capacity checks its database | cache 1 |
| C21 | open-database's cache has the default capacity | cache 8 |
| C22 | call-with-database's cache has the default capacity | cache 1 |
| C23 | open-outcome makes the record with its capacity | cache 6 |

#### connection.sls: the counters

| Mutation | Guards | Failed |
|---|---|---|
| C12 | changes reads sqlite3_changes64 | counters 15 |
| C13 | total-changes reads sqlite3_total_changes64 | counters 12 |
| C14 | last-insert-rowid reads sqlite3_last_insert_rowid | counters 16 |
| C15 | in-transaction? is autocommit answering 0 | counters 2 |
| C16 | changes names itself | counters 1 |
| C17 | total-changes names itself | counters 1 |
| C18 | last-insert-rowid names itself | counters 1 |
| C19 | in-transaction? names itself | counters 1 |
| C20 | a counter checks that its connection is open | counters 1 |

### What the section mutants did

- **S31, `checked-out`'s table read outside the section,** failed the race from fuel 1: both
  engines were handed the one cached statement, each then found it `done` at its column read, and
  the table's count read −1.
- **S46, `returned`'s filing outside the section,** failed it at 23 fuels from 1 to 126: each
  engine answered 7, but two statements were left tracked and counted, one of them in no cache.
- **V09, `bind-each!/who` as one section,** failed the sweep: the second engine never stepped the
  statement between two binds.

In the code as built both sweeps completed without expiring at fuel 102 and 103, on 3.53.1 and
3.45.1 alike, and each row prints its fuel. An engine spends no ticks inside a critical section
(`.plans/traps.md`), so the sections, which hold most of the work, are free.

### The survivors

None.

### Rules the mutants do not cover

- **The refusals' messages** are not asserted, by ADR-0013 decision 9. None was run.
- **A failure of an evicted statement's finalize, raised after the return.** An evicted or refused
  statement is reset before it is filed, so its finalize has nothing to commit and answers 0; no
  suite can make it fail without a plant. `finalize-each` raises the first failure once all are
  finalized, and the table answers at most one statement a return.
- **`sqlite3_clear_bindings` failing.** By SQLite's source it answers `SQLITE_OK` for every live
  statement, so `returned`'s and `clear-bindings!/who`'s failure branch is unreachable; in
  `returned` the reset's failure takes the same path, and S34, S40 and S41 hold it.
- **`own-text`'s fallback to the whole SQL,** for bytes that are not well-formed: SQLite starts and
  ends a statement on a character's boundary, so no input reaches it.
- **`prepared-at`'s contract that BYTES and BLOCK are SQL's,** as `checked-sql` and
  `call-with-c-string` made them. It checks their types and the length, not their agreement, which
  would read the script once a statement.
- **A statement given to `returned` that `checked-out` did not answer.** It would be filed though
  not prepared `PERSISTENT`. The record keeps no flags; part B's conveniences return only what
  they checked out.

### Findings

- **What `sqlite3_finalize` answers after a reset's own BUSY.** An `insert … returning` stepped
  once under another connection's read: `sqlite3_reset` answered 5, `sqlite3_clear_bindings` 0,
  `sqlite3_finalize` 0, and the insert was rolled back, on 3.53.1 and 3.45.1 alike. So `returned`
  finalizes such a statement and raises the reset's failure, which is the only one
  (`build/m3s3-probes/probe2.sps` then, now `.plans/research/m3-slice-3/busy-reset.sps`).
- **Lookaside, by flags.** Ten held statements of `select 1, 2 where ?1` took 70 lookaside slots
  prepared with no flags, and none prepared `SQLITE_PREPARE_PERSISTENT`, on both libraries, as M3's
  research found for 50 (single K1). Two rows read it through the suites' own `sqlite3_db_status`
  (`build/m3s3-probes/probe1.sps` then, now `.plans/research/m3-slice-3/lookaside-tails.sps`).
- **The tails `prepared-at` answers** match the research's (slice-0 P11): `select 1; select 2` at
  9, `;; select 2` one statement at 11, ` -- c` no statement at 5, and empty SQL at 0. A syntax
  error answers its offset from the statement's start, and a missing table −1.

## Part B: the conveniences

Part B adds one library and changes none of part A's:

- **`(chez-sqlite3 private conveniences)`:** `execute!`, `query`, `query-row`, `query-fold` and
  `execute-script!`, each through part A's who-taking internals. A library of its own, since the
  conveniences need both `statement.sls` (step, check-out, return, the script's prepare) and
  `statement-values.sls` (bind, read), and `statement-values.sls` imports `statement.sls`. It
  loads libsqlite3, so `test-never-loads`' list of loaders grows by it.

Its suites, all new: `test-conveniences` (conv), `test-execute-script` (script),
`test-conveniences-who` (who), `test-conveniences-reentry` (reentry),
`test-conveniences-engines` (engines) and `test-conveniences-counters` (counters); and
`test-never-loads`' loader row, its list grown by one. An Opus agent built it from the lead's
brief, in the slice's worktree, on part A's uncommitted libraries.

Every mutation ran in one copy of the worktree, `build/mut/b0`, made without `.git` or `build/`,
through that copy's own `scripts/guix-env`, after `make deps` in the copy. Before each run the
driver copies the worktree's `src/` and `tests/` into the copy. A mutation is one change to one
library, made by one or more replacements, each of whose old text the driver checks occurs once
in the worktree's file (each did). One container run applies each mutant in turn, runs the six
suites, each under `timeout 300`, and puts the file back. The counts are read from the suites'
own output (`# of unexpected failures`), never by eye; a suite that died with no count would be
marked `died`, and one that timed out `hung` (none did). The driver and the mutation definitions
are in the session scratchpad, not the repository.

### The red runs

The suites were written against the brief before the library, and run first against a stub at
the library's path: the five verbs on M2's public statement tier, each naming M2's verbs, with no
cache, `bind-all!` for the parameters, the statement finalized on the normal path only, and
`execute-script!` refusing. So a row that passed red is one a convenience built on M2's own verbs
satisfies. `test-never-loads`' row was run first with its list grown and no library under `src/`.

| Suite | Red run | Green run |
|---|---|---|
| `test-conveniences` | 7 passed, 13 failed | 21 passed |
| `test-execute-script` | 3 passed, 13 failed | 17 passed |
| `test-conveniences-who` | 3 passed, 9 failed | 12 passed |
| `test-conveniences-reentry` | 3 passed, 7 failed | 11 passed |
| `test-conveniences-engines` | 3 passed, 6 failed | 12 passed |
| `test-conveniences-counters` | 21 passed, 0 failed | 21 passed |
| `test-never-loads`, no library | 4 passed, 1 failed, the loader row | 5 passed |

The rows that passed red, and the mutants that watch each fail:

- **each suite's load row and its counts rows;**
- **`test-conveniences`' four shape rows,** which M2's verbs answer alike: execute!'s positional
  binds (B19), query's rows in order (B12), query-fold's `(proc acc row)` (F17), and execute!
  stepping to done (B07, through the row's later case, a select whose second row's step fails);
- **every row of `test-conveniences-counters`:** the counters are SQLite's, read alike after any
  statement tier. Part A's counter mutants fail them through execute!: A02 14 rows, A03 12, A04
  16, A05 the two `in-transaction?` rows; and C12b's row fails when a convenience never gives its
  statement back (B06).

Six rows were added after the red run, once the first mutation pass found what no row held;
each was then watched failing by the mutant named: the return's failure dropped beside a
convenience's own condition (B02); the script's prepare flags, read through lookaside (X09); an
outer handler's return clearing the fold's raise record (F16); and, in the engine suite, Q15's
one value a section (B08 to B10, B13), the fold's hand-over under an abandoned engine (F02), and
query's documented leak under an abandoned engine (B22). Four rows were widened the same way: a
prepare's error mid-statement (X02), statements with nothing between them (X16), a closed
connection's refusal from inside the script's block (X13), and the fold row's cache count (F14).

Green: `make test` ran 53, passed 53, against part A's 47 of 47, the six new suites added. At the
floor, 3.45.1, through `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH`, the six suites,
`test-never-loads` and part A's three passed at the same counts. Under the memory gate, `make
test-memory` on the six new suites passed with no error and nothing lost, each taking 10 to 12 s.

### The mutations

Baselines, from the green runs: conv 21, script 17, who 12, reentry 11, engines 12, counters 21.
Each row names the suites that failed and how many rows failed in each. A mutation counts as
caught when at least one row failed. Each narrow kill was read: it failed the row written for it.

**63 mutations, 59 caught, 4 survived.** The whole set ran on the final suites and library, which
no edit changed after it; B22, X04 (rewritten, below), X17 and X18 ran after it, on the same
files.

#### execute!, query and query-row

| Mutation | Guards | Failed |
|---|---|---|
| B01 | on a raise, the statement is given back | conv 3, reentry 1 |
| B02 | on a raise, the return's failure is dropped | conv 1 |
| B03 | on a raise, the statement is given back, not finalized | conv 2 |
| B04 | on the normal path, the return's failure raises | conv 1, who 2 |
| B05 | on the normal path, the statement is given back, not finalized | conv 7, script 1, who 1, engines 4 |
| B06 | on the normal path, the statement is given back | conv 9, script 1, who 2, engines 4, counters 1 |
| B07 | execute! steps to done | conv 1 |
| B08 | execute! binds one value a section | engines 1 |
| B09 | query binds one value a section | engines 1 |
| B10 | query-row binds one value a section | engines 1 |
| B11 | execute!'s step names execute! | conv 2, who 1, reentry 1 |
| B12 | query answers its rows in order | conv 1, reentry 1, engines 1 |
| B13 | a row is read one value a section | who 1, engines 1 |
| B14 | a row's columns are read from 0 | conv 7, who 3, reentry 3, engines 5, counters 1 |
| B15 | query-row never steps to a second row | conv 1 |
| B16 | query's step names query | conv 2, who 1, reentry 1 |
| B17 | query-row's bind names query-row | who 1 |
| B18 | execute!'s check-out and return name execute! | who 2 |
| B19 | execute! binds its values in order | conv 2, who 1 |
| B20 | a row's read names its convenience | conv 3, who 1, reentry 1 |
| B21 | query-row's reset on return names query-row | conv 1, who 3 |
| B22 | they hold no dynamic-wind (the alternative ADR-0016 rejects) | conv 1, who 2, engines 6 |

#### query-fold

| Mutation | Guards | Failed |
|---|---|---|
| F01 | the procedure is checked first | who 1 |
| F02 | the hand-over sits inside the check-out's section | engines 1 |
| F03 | the raise record covers the wind's whole body, not the procedure alone | reentry 1 |
| F04 | the finish acts once, behind its flag | reentry 1 |
| F05 | the loop reads the flag after each call of the procedure | survived |
| F06 | the loop reads the flag in each step's and read's section | survived |
| F07 | the loop reads the flag at all (F05 and F06 together) | who 1, reentry 2 |
| F08 | a normal return gives the statement back to the cache | conv 3, who 1, reentry 2 |
| F09 | any other exit finalizes the statement, never keeps it | conv 1, reentry 1 |
| F10 | the finish's failure is not raised over a raise under way | reentry 2 |
| F11 | the finish's failure is raised when nothing else is | who 2, reentry 1 |
| F12 | the plain before thunk lets a re-entry through | who 1, reentry 4, engines 1 |
| F13 | the critical before thunk lets a re-entry through | who 1, reentry 4, engines 1 |
| F14 | the flag is set only by an exit that holds the statement | engines 1 |
| F15 | query-fold binds one value a section | who 1 |
| F16 | an outer handler's return clears the raise record | reentry 1 |
| F17 | query-fold calls (proc acc row) | conv 2, who 2, reentry 4, engines 1, counters 1 |
| F18 | the fold's step names query-fold | conv 1, who 1, reentry 2 |

#### execute-script!

| Mutation | Guards | Failed |
|---|---|---|
| X01 | every raise in the loop is caught inside the block's extent | reentry 1 |
| X02 | a prepare's error points at SQLite's token | script 1 |
| X03 | a step's error points at its statement's first token | script 6, who 1, reentry 1 |
| X04 | a step's error carries the whole script | script 5, who 1, reentry 1 |
| X05 | the loop stops at a step's failure | script 6, who 1, reentry 1 |
| X06 | the first prepare always runs, so a closed connection is refused | script 1 |
| X07 | each statement is finalized by its wind on every way out | engines 1 |
| X08 | the loop finalizes each statement it ran | survived |
| X09 | the script prepares with no flags | script 1 |
| X10 | a step's failure is rebuilt | script 6, who 1, reentry 1 |
| X11 | a rebuilt error keeps the extended code | script 4, reentry 1 |
| X12 | the database is checked before the SQL | script 1 |
| X13 | a raise that is no SQLite failure is caught inside the block too | reentry 1 |
| X14 | a NULL statement ends the loop | survived |
| X15 | a prepare's failure carries the whole script | script 2, who 1 |
| X16 | the loop prepares from each statement's tail | script 1 |
| X17 | the loop runs every statement, to the script's end | conv 1, script 8, who 1, reentry 1, engines 1 |
| X18 | SQL holding no statement is no error | script 2 |

#### Part A's internals, through part B's rows

| Mutation | Guards | Failed |
|---|---|---|
| A01 | checked-out reads and changes the table inside the section (part A's S31) | engines 1 |
| A02 | changes reads sqlite3_changes64 (part A's C12) | counters 14 |
| A03 | total-changes reads sqlite3_total_changes64 (part A's C13) | counters 12 |
| A04 | last-insert-rowid reads sqlite3_last_insert_rowid (part A's C14) | counters 16 |
| A05 | in-transaction? is autocommit answering 0 (part A's C15) | script 3, counters 2 |

### What the section and engine mutants did

- **B08 to B10, binds in one section,** and **B13, a row read in one,** failed the Q15 row: at fuel
  1, 50 values cost 27 expiries more than 1 under B08, and none more under B13, against 1303 for
  the binds and 1128 for the reads in the code as built, over 20 a value.
- **F02, the hand-over outside the section,** left the fold's statement checked out, ready and in
  no cache, under an engine abandoned at its first expiry.
- **F14, the flag set by an exit with no statement,** let an expiry inside `checked-out` set it, so
  the resumed fold raised `&sqlite-closed` and left the statement it was then handed out of the
  cache, unfinalized.
- **X07, the script with no wind of its own,** left a statement tracked after an expiry's resume
  was refused.
- **A01, part A's S31,** failed the two-engine sweep through the conveniences.
- **B22, a dynamic-wind giving the statement back,** failed the six engine rows that run execute!,
  query or query-row: an expiry gave the statement back, reset and cleared, under the resumed call,
  so execute! inserted no row of its value and query's resumed read was refused in `ready`; and an
  abandoned query left none at its row.

### The survivors

- **F05 and F06, each of the fold's two flag reads alone.** Each is redundant with the other on
  every path a test can make. A re-entry resumes only inside the procedure, the fold's one call of
  the caller's code, so the first read it meets is the one after the procedure, and without it the
  next step's in-section read raises the same `&sqlite-closed`. An engine's expiry between a read
  and its step finalizes the statement, since an expiry is never a normal return, so the step's
  own accessor refuses it with `&sqlite-closed` from `query-fold`, the same condition. The section
  read is kept as the records ask (ADR-0017, amended in M3 slice 1); F07, both dropped, is caught.
- **X08, the loop's own finalize dropped.** The statement's critical wind finalizes it on every
  exit, the normal one too. The two differ only in a finalize's own failure, raised by the loop and
  dropped by the after thunk; after done, and after a failed step, SQLite's finalize answers
  nothing of its own, so no input reaches the difference.
- **X14, a NULL statement continuing the loop.** Its tail was the input's end in every case
  measured (slice 0's P11), so the loop's next test, the tail at the script's end, ends it the same.

### Rules the mutants do not cover

- **The refusals' messages** are not asserted, by ADR-0013 decision 9.
- **The same object raised again** by execute!, query and query-row: the conditions come from the
  internals, so no row holds one to compare by `eq?`; the fold's procedure's own condition is held
  so, under the nested guards.
- **query-fold's bind, one value a section:** the fold does not survive an engine, so no engine row
  can count its sections. F15 is caught only by the depth of its raise.
- **The reset on return to the cache for execute! and query:** each steps to done, and a reset
  after done answers nothing of its own. query-row's is held.

### Mutants that proved nothing at first

- **X04, first written,** named `sqlite-error-sql`, which the library does not import: the library
  failed to load, and every row of every suite failed. Rewritten with the import, it fails the rows
  it guards. A mutant that fails everything is read before it is counted.
- **X14, first written,** took `(caddr made)` of the two-element `(empty TAIL)`, and raised. Its
  fair form, `(cadr made)`, survives, above.
- **The Q15 row, first written,** compared 50 values with 1 in SQL of different lengths, and B08 to
  B10 and B13 survived it: `checked-sql` reads each character outside any section, and the longer
  SQL cost more ticks than the binds and reads saved. The one-value SQL is now padded with spaces to
  its twin's length.

### Findings

- **The engine rows' fuels,** each the first at which the call completed without expiring, alike on
  3.53.1 and 3.45.1: execute! 153, query 438, query-row 210, query-fold 103 (resumed, and
  abandoned), execute-script! 640, and the two engines 556. Below each, execute!, query and query-row
  completed at every fuel; query-fold answered its fold or `&sqlite-closed`, the latter at fuel 1;
  execute-script! completed or was refused by `call-with-block` from execute-script!, at fuel 1
  refused.
- **The eviction's finalize can fail through the conveniences** when the cache holds a statement a
  suite moved to its row, as part A's moved-statement row moves one. An insert ... returning so
  moved, evicted under another's read, answers busy, raised from the convenience whose return
  evicted it. Part A's "Rules the mutants do not cover" said no suite reaches it without a plant.
- **Lookaside, by the script's flags,** measured on both libraries (`build/b/probes/p5.sps`, kept
  since part D as [lookaside-by-flags.sps](research/m3-slice-3/lookaside-by-flags.sps)): a select of 200 columns, run by execute-script! or by query at a capacity of 0, fills
  the connection's 123 lookaside slots at its high-water mark; through query's
  `SQLITE_PREPARE_PERSISTENT` miss, stepped and read, it takes none.
- **A prepare's error mid-statement in a script:** `insert into s values (2); select 1, nosuchcol`
  answers offset 36, at the column, on both libraries.

## Part C: the plants, the probes and the public names

Part C changes no library's behaviour:

- **`(chez-sqlite3)`:** exports `execute!`, `execute-script!`, `query`, `query-row`,
  `query-fold`, `changes`, `total-changes`, `last-insert-rowid` and `in-transaction?`, each with
  the M3 plan's §4.9 signature comment, one line, `;; NAME : TYPE`, and `;;   Row = (Vectorof
  Value)` after the conveniences.
- **`docs/reference.md`:** a section, "Conveniences and counters", after Connections: an entry for
  each of the nine, `Integer` and `Row` among the page's type names.
- **`tests/test-public.sps`:** its list of public names grown by the nine, and its count from 51
  to 60.
- **`tests/test-conveniences.sps`:** one row, §4.8's own for a statement left at a row, read by
  SQLite's account: after each convenience returns or raises, `sqlite3_interrupt` on the
  connection, through native's `sqlite3-interrupt` and `call-with-open-handle` as the suites
  reach them, then `select 7` through the statement tier. While no statement of the connection
  holds a row the interrupt is lost and `select 7` answers; while one does, its prepare answers 9
  (M3's research, concurrency I3). Its control, a statement the row holds at its row, shows the
  interrupt sticking. Eleven cases: the control; `query-row`, `query`, `execute!`, `query-fold`
  and `execute-script!` returning; `query-row`, `query` and `query-fold` raising
  `&sqlite-invalid-text` at a row; and `query-fold`'s procedure raising and escaping.
- **The research:** P8 and part A's two probes, in
  [research/m3-slice-3/](research/m3-slice-3/README.md). The suites' comments that cited part A's
  probes under `build/m3s3-probes/` now cite them there, in `test-statement-who`,
  `test-connection-cache` and `test-conveniences`; and the conveniences library's header says
  `(chez-sqlite3)` exports its verbs.

Every plant ran in one copy of the worktree, `build/mut/c0`, made without `.git` or `build/`,
through that copy's own `scripts/guix-env`, after `make deps` in the copy. Before each run the
driver copies the worktree's `src/`, `tests/` and `docs/` into the copy. A plant is one change to
one file, made by one or more replacements, each of whose old text the driver checks occurs once
in the worktree's file (each did). One container run applies each plant in turn, runs its suites,
each under `timeout 300`, and puts the file back. The counts are read from the suites' own output
(`# of unexpected failures`), never by eye; a suite that died with no count would be marked
`died`, and one that timed out `hung` (none did). The driver and the plant definitions are in the
session scratchpad, not the repository.

### The red runs

| Suite | Red run | Green run |
|---|---|---|
| `test-public`, its list grown, nothing exported | 16 passed, 3 failed: the count, the list, and the `eq?` row | 19 passed |
| `test-reference`, the page's entries written, nothing exported | 17 passed, 2 failed: the entries that are no export, and the whole lists | 19 passed |
| `test-docs`, the same | 76 passed, 7 failed: each new `scheme run` example, an unbound name | 83 passed |
| `test-conveniences`, the interrupt row | passed at once, on parts A's and B's code; watched failing against L1 to L4 | 22 passed, from 21 |

The interrupt row was written against code already built, so it had no red run of its own
against the code: its red runs are the four plants below. Each failed only its own cases: the
control and the others answered as on the green run.

Green: `make test` ran 53, passed 53, as before part C, which adds no suite. At the floor, 3.45.1,
through `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH`, `test-conveniences`, `test-public`,
`test-reference`, `test-docs`, `test-statement-who`, `test-connection-cache` and
`test-never-loads` passed at the same counts. Under the memory gate, `make test-memory` on
`test-conveniences`, `test-public`, `test-reference` and `test-docs` passed, with no error and
nothing lost, in 11, 9, 10 and 30 s.

### The plants

The suites, for L to P: parts A's and B's sixteen, and slice 1's `test-statement-cache`
(table). The short names are part A's and part B's, with stmt-who for `test-statement-who`. For
D: `test-public`, `test-reference` and `test-docs` (reference, docs). Green counts, from the
plant run's own green run, G0: conv 22, script 17, who 12, reentry 11, engines 12, counters 21,
stmt-who 25, cache 22, change-counters 23, nomem 14, statement 76, values 47, connection 63,
sections 4, values-sections 9, public 19, table 32.

**21 plants, 21 caught, none survived,** on Guix's 3.53.1. Each ran three times, with the same
counts every time: L to P first, with part C's interrupt row and nothing else of part C's; D1 to
D4 once the exports and the page were in; and then the whole set together, twice, the second time
on the final files, which no edit changed after it, once a sentence of the page's had changed.

#### §4.8: a convenience that leaves its statement at a row

| Plant | Guards | Failed | §4.8's row |
|---|---|---|---|
| L1 | `query-row` gives its statement back on its normal path | conv 7, who 2, engines 2, counters 1 | conv's interrupt row |
| L2 | a statement given back is reset before it is filed | conv 6, who 1, engines 5, counters 1, stmt-who 1, cache 5 | conv's interrupt row |
| L3 | on a raise, `execute!`, `query` and `query-row` give the statement back | conv 4, reentry 1 | conv's interrupt row |
| L4 | `query-fold`'s statement is finished on an exit that is no normal return | conv 2, who 1, reentry 5, engines 2 | conv's interrupt row |

Each L plant fails rows of part A's or part B's too, which read the library's own states and
counts. The interrupt row is §4.8's, and reads SQLite's own account, which L2's statement, filed
`ready` at SQLite's row, shows the two can differ on.

#### §4.8: a before thunk that refuses a re-entry, in `query-fold` (H1)

Each plant refuses any second entry, by a flag its before thunk sets on the first.

| Plant | Guards | Failed | §4.8's row |
|---|---|---|---|
| H1 | the fold's plain before thunk lets a re-entry through | who 1, reentry 4, engines 1 | reentry's "query-fold under a guard whose clauses do not match …" |
| H2 | the fold's critical before thunk lets a re-entry through | who 1, reentry 4, engines 1 | the same |

#### §4.8: a raise let out of `execute-script!`'s block

| Plant | Guards | Failed | §4.8's row |
|---|---|---|---|
| X1 | every raise in the script's loop is caught inside the block's extent (part B's X01) | reentry 1 | reentry's "execute!, query, query-row and execute-script!, each under a guard …" |
| X2 | a raise that is no SQLite failure is caught inside the block too (part B's X13) | reentry 1 | the same |

#### §4.8: `query-fold`'s loop without its read of the flag, or a finish that acts twice

| Plant | Guards | Failed | §4.8's row |
|---|---|---|---|
| F1 | the fold's loop reads its flag, after the procedure and in each section (part B's F07) | who 1, reentry 2 | reentry's "a fold re-entered through a continuation after its normal return …" |
| F2 | the fold's finish acts once (part B's F04) | reentry 1 | reentry's "query-fold's statement is finished once …" |

#### §4.8: the cache ignoring its capacity, or evicting one too early or too late

K1, K3, K4 and K5 are planted in slice 1's table, `statement-cache.sls`, in the copy; K2 in the
record.

| Plant | Guards | Failed | §4.8's row |
|---|---|---|---|
| K1 | the table evicts once full, never growing past its capacity | conv 2, who 1, cache 3, table 12 | cache's "33 distinct statements …" |
| K2 | the record's cache has the capacity the open is given | conv 3, script 1, who 1, cache 6 | the same, and cache's "the cache's capacity is 32 …" |
| K3 | the table evicts no earlier than when full | conv 1, cache 2, table 12 | cache's "33 distinct statements …", and conv's and cache's A, B, A, C at 2 |
| K4 | the table evicts no later than when full | conv 2, who 1, cache 3, table 12 | cache's "33 distinct statements …" |
| K5 | at capacity 0 the table keeps nothing | conv 1, cache 2, table 6 | the same |

#### §4.8: the cache keeping a failed statement (single T6), and preparing without `PERSISTENT` (single K1)

| Plant | Guards | Failed | §4.8's row |
|---|---|---|---|
| T1 | a statement whose step or read failed is finalized on its return, never kept | conv 2, reentry 1, cache 1 | conv's and cache's "a statement whose step failed is finalized on its return, never kept …" |
| P1 | a miss prepares `SQLITE_PREPARE_PERSISTENT` while the capacity is above 0 | script 1, cache 1 | cache's "a miss prepares SQLITE_PREPARE_PERSISTENT …", and script's "execute-script! prepares with no flags …" |

#### The public names and their docs

| Plant | Guards | Failed |
|---|---|---|
| D1 | the reference's signature line is the export's comment, character for character (`query-fold`'s `(Row A -> A)`) | reference 1 |
| D2 | each export's signature comment is the reference's line (`query-row`'s comment `(U Row False)`) | reference 1 |
| D3 | `(chez-sqlite3)` exports `in-transaction?` | public 3, reference 2, docs 1 |
| D4 | the reference holds an entry for `changes` | reference 2 |

### What the plants did

- **L1 to L4, through the interrupt row.** Each case answers `(#(7))` on the green run, and the
  control `(raised (sqlite-error prepare-statement interrupt interrupt "select 7" #f))`. L1 made
  `query-row`'s case answer that; L2 `query-row`'s and the two raising reads', so a statement
  filed `ready` that SQLite held at its row; L3 the two raising reads'; L4 the fold's raise, its
  escape and its failed read.
- **H1 and H2** made all four cases of the reentry row answer
  `(outer (assertion-violation query-fold (re-entered)))`, the refusal in place of the caller's
  condition, the procedure's own object, a symbol, and the fold's failed step.
- **X1 and X2** made one case fail, the closed connection's: the outer guard caught
  `(assertion-violation execute-script! ())`, `call-with-block`'s refusal, for
  `(closed execute-script!)`. The script's constraint failure still reached the outer guard as
  itself under both: `script-statement` answers SQLite's failures as data before they reach the
  block's guard, so only a raise that is no SQLite failure shows the plant.
- **F1** made the fold re-entered after its normal return answer 7 after 6, its procedure called
  6 times, and leave the cached statement at `done`: the shape the plan's second review measured.
  **F2** left the fold's statement, which the suite had checked out and held at its row, reset
  and filed again: `ready`, the cache holding 1, where `row` and 0 were due.
- **K1 to K5, through the 33-statement row,** due `((32 32) (1 1) (0 0))`, the count and the
  cache's at the default, 1 and 0: K1 `((33 33) (33 33) (0 0))`; K2 `((32 32) (32 32) (32 32))`;
  K3 `((31 31) (1 1) (0 0))`; K4 `((33 33) (2 2) (0 0))`; K5 `((32 32) (1 1) (1 1))`. K3 is not
  seen at 1, where a table one too eager still keeps one; at 2 the A, B, A, C rows saw it keep C
  alone.
- **T1** left `execute!`'s failed insert filed `ready`, where none of its SQL was due, and part A's
  failed statement `ready`, cached and counted, where `finalized`, an empty cache and no statement
  counted were due.
- **P1** made ten held statements take 70 lookaside slots at capacity 32 and at 1, where 0 was due,
  and `query`'s miss of 200 columns fill the 123 slots, where 0 was due.
- **D1 to D4** failed `test-reference`'s rows by name, each as `(name comment line)`, or as the
  exports and entries that differ; D3 failed `test-public`'s count, 59, and `test-docs`' run
  of the page's `in-transaction?` example, its name unbound.

### The survivors

None.

### Rules the plants do not cover

- **The stale schema of single T6 itself.** T1 is caught by the cache's state after a failed
  step, a constraint failure's: no row rebuilds a table under a held INSERT and reads the stale
  "has 3 columns" a kept statement repeats.
- **The 50 held statements of single K1, and `LOOKASIDE_USED` full.** Part A's row holds ten and
  asserts 0 against "some", and part B's script row reads the high-water mark of one 200-column
  select; each caught P1, so no 50-statement row was written.
- **Capacity 2 in the 33-statement row.** Part A's row reads the default, 1 and 0; 2 is read by
  the A, B, A, C rows of part A's and part B's suites.
- **F05 and F06, each of the fold's two flag reads alone,** part B's survivors, by its argument.
- **The docs' prose,** which no oracle reads but a reader (`test-docs`' own account); its
  examples are run, and its signatures held to the comments.

### Findings

- **P8** ([research/m3-slice-3/](research/m3-slice-3/README.md)), alike on both libraries: a hit
  saves 4.5 to 5.0 µs a call against capacity 0, 63 to 71% of the call; a miss at 32 costs 1.3 to
  1.7 µs more than capacity 0; a convenience costs 0.7 to 1.9 µs over the statement tier by hand.
  A section a value costs 150 to 200 ns a value more than a section a row, about three quarters
  of `query-row` on a row of 100 small integers; an empty critical section is about 8 ns of it,
  and the rest each value's checks through `call-with-statement-handle`.
- **Part A's probes,** kept beside P8: ten held statements took 70 lookaside slots with no flags
  and none `PERSISTENT`; `prepare_v3`'s tails as part A's findings give them; and after a reset's
  own BUSY, `sqlite3_clear_bindings` answered 0, the finalize nothing, and the insert was rolled
  back. Part A's findings above call both "not kept"; they are now.
- **The interrupt row needed no change to pass at the floor:** the control's prepare answered 9,
  with no offset, on 3.53.1 and 3.45.1 alike.

## Part D: the fixes of the slice's review

The slice's adversarial review, read-only on Opus, found that a convenience's call could be
resumed, or re-entered, after its statement had left it, and the lead reproduced each finding.
Chez's engine remainders are multi-shot: one remainder can be resumed twice
(`build/review/probes/engine-twice.sps`). And a timer's, keyboard's or collect request's handler
is the caller's code, which runs between any two critical sections and can capture a
continuation there. So:

- **`execute!`, `query` and `query-row` kept no flag.** A remainder resumed a second time stepped
  and refiled a statement the first resume had given back, after another engine had checked it
  out: the review's `engine-resumed-twice.sps` answered `(#(1) #(2) #(3))` from the other engine's
  statement, whose own resume was then refused in `ready`.
- **`query-fold`'s flag guarded neither its check-out nor its binds.** A re-entry before the loop
  checked the cached statement out again, or prepared one, and left it tracked, ready and in no
  cache: 93 re-entries by a timer handler left 31 statements so, the cache holding 0
  (`timer-reentry.sps`).
- **Part B's survivor F06 was not redundant.** A timer handler can re-enter between the read after
  the procedure and the next step's section; with F06 planted, the timer probe called the
  procedure 66 times against 18, and left 30 statements at a row. Part B's argument, that a
  re-entry resumes only inside the procedure, was wrong.
- **The docs promised a closed condition** where a fold's finish that fails during an engine's
  expiry raises from the plain after thunk, inside the engine, and the engine is lost: Chez's
  "no engine active" (`fold-engine-finish-fails.sps`).

**The maintainer's choice, 2026-11-16, "Guard every call":** each call of the five holds a flag,
set once its statement leaves the call, given back to the cache or finalized; and every critical
section that touches the call's statement reads it first. With it set, the section touches
nothing, and the convenience raises `&sqlite-closed` after the section.

Part D changes part A's two statement libraries and part B's library. The signatures it changes:

```scheme
;; checked-out : Symbol Any Any (U (Statement -> Any) #f) (U (-> Any) #f) -> Statement
;; prepared-at : Symbol Any String Bytevector Positive-Integer Natural Natural
;;               (U (Statement -> Any) #f) (U (-> Any) #f)
;;   -> (U (List 'prepared Statement Natural) (List 'empty Natural)
;;         (List 'failed Integer String Integer))
;; bind-each!/who : Symbol Statement (Listof Value) (U (-> Any) #f) -> Void
;; while-held : Symbol (U (-> Any) #f) (-> A ...) -> A ...        (new, exported)
;; code-number : Any -> (U Integer #f)                             (now exported)
```

The new last argument of each is LEFT?, the call's check: a procedure of no arguments that
answers whether the call's statement has left it, or `#f` for none, as slice 4's
`with-transaction` will pass for its own statements. Each refuses one that is neither, an
assertion violation from its who, `not-a-procedure`. Inside the statement library,
`prepare-outcome` and `prepared-checked` take it too.

**The flag's shape.** For `execute!`, `query` and `query-row`, `with-checked-out` makes it, unset,
before the check-out: a variable, its check `(lambda () left)` and its setter. For `query-fold`,
the fold's own `left`, made before its winds. For `execute-script!`, `begun`, made before its
checks. The sections that read it:

| Section | Where | Read by |
|---|---|---|
| the check-out's, before the table is read | `checked-out`, inside `call-with-open-handle`'s procedure | LEFT? |
| a miss's prepare, before it allocates or prepares | `prepare-outcome`, inside `call-with-open-handle`'s procedure | LEFT? |
| each bind: the count's, and each value's | `bind-each!/who` | `while-held` |
| each step | the conveniences' `stepped` | `while-held` |
| each column read: the count's, and each value's | the conveniences' `row-of` | `while-held` |
| the return | `execute!`, `query` and `query-row`'s `given-back`, which sets the flag in the same section, before `returned` runs | its own section |
| the return or the finalize | `query-fold`'s critical after thunk, which sets it | the thunk, a section |
| the first prepare | `execute-script!`'s, through `prepared-at`'s LEFT?, which marks the run begun | LEFT? |

`while-held` is a critical section around one of the accessor's sections, so the flag is read
before the accessor's checks of the statement's state: a bind on a statement another caller
holds at its row is refused as closed, never as `not-allowed-in-state`. What the accessor raises
after its own section is caught in `while-held`'s and raised after it, the same object.
`query-fold` also reads its flag after each call of the procedure, as before. Inside
`execute-script!`'s block, `call-with-block` refuses a re-entry itself; the begun flag refuses a
call re-entered before its block, so the script never runs again. A re-entry inside the
library's own winds, `call-with-open-handle`'s around a check-out or a prepare and
`call-with-block`'s, is refused by those winds, an assertion violation, `re-entered`, before any
flag is read. A remainder taken before a call's first expression is the caller's own: resumed,
it makes a whole new call, with a flag of its own.

Its suites: `test-conveniences-resumed`, new, ten rows; four rows in `test-statement-who`, for the
check at each internal; two in `test-conveniences-who`, a second resume's raise at depth 1; a
`trusted_schema` row in `test-conveniences`; a `code-number` row in `test-execute-script`; the
conveniences' export row in `test-public`; `test-statement`'s export row grown by `while-held`;
and `test-conveniences-engines`' abandoned `query` row printing its fuel. The calls of the three
changed signatures in `test-connection-cache`, `test-statement-who`, `test-conveniences-reentry`
and the new suite were given `#f`: 37 calls of `checked-out`, 15 of `prepared-at` and 10 of
`bind-each!/who`, each count predicted before the replace and read after it.

### The red runs

The new suite's rows were written against the code as it stood, and run first in the worktree
before its libraries changed. The later red runs used a copy of those libraries, taken from the
review's copy of the worktree, `build/review/tree/src/`, which differed from the worktree's in
part D's three files alone. The internals' rows were written after the fix, and watched failing
by the mutations below.

| Suite | Red run | Green run |
|---|---|---|
| `test-conveniences-resumed`, before the fix | 3 passed, 7 failed: every row but the load and the counts; the timer row by its strays in the first run, before `checked-out` took its fifth argument | 10 passed |
| `test-conveniences-who`, before the fix | 12 passed, 2 failed, the two new rows | 14 passed |
| `test-public`, before the fix | 19 passed, 1 failed, the new row: no `code-number` | 20 passed |
| `test-execute-script`, before the fix | 17 passed, 1 failed, the new row, `code-number` unbound; R3 fails it by its branch | 18 passed |
| `test-statement`, on the fixed code before its row grew | 75 passed, 1 failed, the export row | 76 passed |
| `test-statement-who`'s four rows | written after the code; watched failing by D01 to D04, D10, D15, D19 to D22 and D24 | 29 passed |
| `test-conveniences`' `trusted_schema` row | passed at once, as the `foreign_keys` row it follows; watched failing by P1, a return that keeps nothing | 23 passed |

On the code before the fix, the new suite failed as the review found:

- **`execute!`, `query` and `query-row`, warm:** a remainder taken while the call held its
  statement, resumed again while another engine held it at a row, was refused binding that
  engine's statement, `not-allowed-in-state row`, and the other engine's own resume was then
  refused in `ready`. **Cold:** the second resume re-ran the call from its first row, `(#(11) #(12)
  #(13))` again from a remainder that had held the statement.
- **`query-fold`:** at 51 fuels, a remainder taken before the check-out, resumed again, left the
  cached statement tracked, ready and in no cache.
- **The timer row:** every re-entry raised or answered as it should, but the cache was left
  holding many statements, each ready: the check-out's missing read.
- **`execute-script!`:** a whole new call, the script run twice, at every fuel up to the block,
  far past the refused call's fuel.
- **`query-row`, its return failing:** at 25 fuels, the second resume answered `#(1)`, the row of
  an insert the first resume's failure had rolled back.

Two rows' expectations were corrected as they first ran: a second resume can be refused by
`call-with-open-handle`'s own wind, `re-entered`, even where the call did not yet hold its
statement (fuels 55 to 57, on the code before the fix); and an expiry past the fold's last step,
before its normal return, finalizes the statement, yet the resume answers the fold (fuels 133 and
134, on the fixed code). The timer row first counted the procedure's calls by a counter at its
entry, and read six re-entries as calls: a continuation taken inside the procedure, re-entered,
finishes that call. It now counts a call by the row it is given, a fresh vector each.

Green: `make test` ran 54, passed 54, against the slice's 53 of 53, the new suite added. At the
floor, 3.45.1, through `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH`, the slice's seventeen suites
passed at the same counts. Under the memory gate, `make test-memory` on the thirteen changed or
new suites passed with no error and nothing lost: `test-conveniences-resumed` in 24 s,
`test-docs` 29, `test-statement` 19, and the others 9 to 12; `test-conveniences-who`, run again
under the gate and at the floor once its two rows were in, 13 s.

**The engine rows' fuels,** each the first at which the call completed without expiring, on
3.53.1 (3.45.1 within two): in the engines suite, `execute!` 84, `query` 156, `query-row` 104,
`query-fold` 113, an abandoned `query-fold` 113, an abandoned `query` 119, `execute-script!` 640,
the two engines 259. In the new suite: `query` 150 cold, 143 warm; `query-row` 108 and 101;
`execute!` 114 and 107; `query-row`, its return failing, 156; `query-fold` 137;
`execute-script!` 640, its whole new calls at fuels 1 to 9, below the refused call's 76. Every
bind, step and read now runs its accessor's checks inside `while-held`'s section, where an engine
spends no ticks, so the conveniences' fuels fell by about half: `query` from 438, the two engines
from 556. The one-value-a-section row still holds by wide margins, 979 expiries against 362 for
the binds and 499 against 253 for the reads.

### The mutations

Every mutation ran in one copy of the worktree, `build/mut/d0`, made without `.git` or `build/`,
through that copy's own `scripts/guix-env`, after `make deps` in the copy. Before each mutant the
driver copies the worktree's `src/`, `tests/` and `docs/` into the copy, checks that each old text
occurs once in the worktree's file, writes the mutant, runs the twelve suites below, each under
`timeout 300`, and puts the files back. The counts are read from the suites' own output, never by
eye. The driver and the definitions are in the worktree's git-ignored `build/fix/mut/`.

The suites, with their green counts: resumed (`test-conveniences-resumed`) 10, conv 23, who
(`test-conveniences-who`) 14, reentry 11, engines 12, script 18, counters 21, stmt-who 29, cache
22, statement 76, values 47, public 20.

**36 mutations, 31 caught, 5 survived.** The whole set ran once, on the final libraries and suites,
which no edit changed after it; an earlier pass of 34, on the suites before the failed-return row
and the who suite's two rows, found D17 surviving, and those rows were written for it and for
D23. Each narrow kill was read: it failed the row written for it.

#### Each flag read dropped alone

| Mutation | Guards | Failed |
|---|---|---|
| D01 | the check-out's section reads the call's check before the table | resumed 5, stmt-who 1 |
| D02 | a miss's prepare reads it before it prepares | resumed 4, stmt-who 1 |
| D03 | bind-each!/who's count's section reads it | resumed 4, stmt-who 1 |
| D04 | each value's bind reads it | resumed 4, stmt-who 1 |
| D05 | each step reads it | resumed 4 |
| D06 | a row's column count's read reads it | survived |
| D07 | each column's read reads it | resumed 3, who 1 |
| D08 | the return's section reads it | resumed 4, who 1 |
| D09 | the fold's finish reads it, and acts once (part B's F04) | resumed 1, reentry 1 |
| D10 | the script's first prepare reads it, through prepared-at | resumed 1, who 1, stmt-who 1 |
| F05 | the fold reads it after each call of the procedure | survived |
| F06 | the fold's steps and reads read it, the other conveniences' kept | resumed 1, the timer row |
| F07 | F05 and F06 together | resumed 1, who 1, reentry 2 |
| D11 | the fold's check-out and binds read it | resumed 2 |

#### The flag never set, set late, or read apart from what it guards

| Mutation | Guards | Failed |
|---|---|---|
| D12 | execute!, query and query-row set their flag | resumed 4, who 1 |
| D13 | the fold sets its flag | resumed 1, who 1, reentry 2 |
| D14 | the script marks its run begun | resumed 1, who 1 |
| D15 | while-held reads the check in the section it guards, not one before it | resumed 4, who 1, stmt-who 1 |
| D16 | the return runs in the section that reads and sets the flag | resumed 4, who 1 |
| D17 | the flag is set before the return, so a return that fails sets it too | resumed 1, the failed-return row |
| D18 | the flag is made before the check-out, so the check-out reads it | resumed 3, who 1 |
| D23 | the return's section raises nothing, &sqlite-closed after it | who 1 |
| D24 | while-held's section raises nothing, &sqlite-closed after it | stmt-who 2 |

#### The checks

| Mutation | Guards | Failed |
|---|---|---|
| D19 | checked-out refuses a check that is no procedure | stmt-who 1 |
| D20 | prepared-at refuses one | stmt-who 1 |
| D21 | while-held refuses one | stmt-who 2 |
| D22 | while-held with a check reads it in a section; with #f, plainly | resumed 4, who 1, stmt-who 2 |

#### The review's mutations, rerun on the fixed code

R6 of the review, the column count read outside the flag, is D06 here: the count is read through
while-held now.

| Mutation | Guards | Failed |
|---|---|---|
| R1 | a failed statement's return untracks it | conv 2, reentry 1 |
| R2 | a statement not kept, its reset or clear failing, is untracked | resumed 1, conv 2, stmt-who 1 |
| R3 | code-number answers an integer itself | script 1, the code-number row |
| R4 | the script's loop ends at the script's end, `>=` | survived |
| R5 | the fold's normal return clears its raise record | survived |
| R7 | a failed statement's finalize failure is raised on its return | survived |
| R8 | an evicted statement's finalize failure is raised | who 1 |
| F14 | the fold's flag is set only by an exit that holds the statement | resumed 1 |
| P1 | a return keeps its statement: the trusted_schema row's plant | resumed 3, conv 10, who 1, engines 4, script 1 |

### What the mutants did

Each read from the new suite's failing rows, planted alone.

- **D01,** the check-out unguarded: a cold call's second resume, or a fold's, checked the cached
  statement out again, and left it tracked, `ready`, in no cache; the timer row left three tracked,
  as the review found.
- **D02,** a miss's prepare unguarded: a cold call's second resume prepared a second statement,
  left tracked beside the cached one.
- **D03 and D04,** the binds unguarded: a second resume bound the statement another engine held at
  its row, refused `not-allowed-in-state row`, where `&sqlite-closed` was due; so did a timer
  re-entry, on the statement the suite held.
- **D05,** the steps unguarded: a second resume stepped another engine's statement on, so that
  engine answered `(#(22) #(23))`, its first row lost, or, for `execute!`, was refused in `done`;
  cold, it left the cached statement at a row.
- **F06,** the fold's steps and reads unguarded: a timer re-entry stepped the cached statement, its
  bindings cleared, and called the procedure with a row of NULL, which `+` refused; with the suite
  holding it, stepped the suite's statement to its end.
- **D07,** the column reads unguarded: cold, a second resume read the cached statement, refused
  `not-allowed-in-state ready`. Warm, it read the other engine's row and wrote it into the row
  vector the first resume had already answered: `(#(21) #(12) #(13))`. A remainder taken after
  `make-vector` and before a column's `vector-set!` shares that vector with every resume.
- **D08, D12, D16 and D18,** the return unguarded, the flag never set, set outside the return's
  section, or made after the check-out: a second resume answered again, or bound the other
  engine's statement at its row, and that engine's own resume was refused in `ready`, its
  statement reset under it.
- **D10 and D14:** the script ran twice, a whole new call at every fuel up to its block, past the
  refused call's 76.
- **D15,** while-held's read in a section of its own before the one it guards: a remainder taken
  between them bound the other engine's statement, refused in `row`, or left the cached statement
  at a row.
- **D17:** a remainder resumed after its return failed answered `#(1)`, the row of an insert the
  failure had rolled back.
- **D23 and D24** raised `&sqlite-closed` inside their sections, where a handler ran at depth 2.
  D24 is seen only by `while-held`'s own row: `execute!`, `query` and `query-row` catch every raise
  of their work in their guard and raise it again after, so the caller's handler sees depth 1.
- **F14:** an expiry before the hand-over set the fold's flag, so the resumed fold, due to complete,
  raised `&sqlite-closed` from its check-out, at 51 fuels.
- **R2** now fails the new suite too: a statement not kept, its reset failing, stays tracked.

### The survivors

- **D06, the column count's read unguarded.** The count is read by `sqlite3_column_count` alone,
  which changes nothing, and the accessor allows it in every live state; the first column's read
  follows at once, in a section that reads the flag first, and a statement at a row has at least
  one column. So a call whose statement has left it raises the same `&sqlite-closed`, from the same
  who, one section later, having changed nothing; a finalized statement is refused as closed by
  the accessor itself. The read is kept, as the maintainer's rule has every section that touches
  the statement read the flag.
- **F05, the fold's read after each call of the procedure.** After the procedure returns, the
  loop's next act is the next step, in a section that reads the flag first, and nothing between
  them touches the statement or can unset the flag. So a fold re-entered or resumed in its
  procedure raises the same `&sqlite-closed` from `query-fold` one section later, the procedure
  not called again. Part B's argument for F06 was wrong and this one is not: F06's reads are what
  stop a re-entry between the procedure's return and the step, as the timer row shows. F05's read
  is kept, as ADR-0016's decision 6 has it.
- **R4, the script's loop ending at `>` for `>=`.** At the script's end it prepares once more, from
  the end, with no check: SQLite finds no statement, and `(empty TAIL)` ends the loop as `(done)`.
  An extra section and an extra prepare of nothing, on a connection nothing can close mid-script.
- **R5, the fold's normal return keeping its raise record.** The record decides only whether the
  plain after thunk raises a finish's failure, and only the first exit records one. A normal
  return with the record still set needs a raise whose handler neither returned, which clears it,
  nor left the fold, which would be the first exit and set the flag, so that the normal return
  finishes nothing: an outer handler that jumps to a continuation inside the fold's own extent.
  Then that return's finish must fail, and at `done` the reset has nothing to commit, so only a
  statement the return evicts, moved to a row by a suite, could fail it. No row builds that; it
  survives, as the review found.
- **R7, a failed statement's finalize failure dropped on its return.** `finish-failure` never counts
  a failed statement's finalize as a failure of its own, since the finalize repeats the step's
  code (ADR-0014, decision 7), so `returned`'s `discarded` outcome is always `finalized`, or the
  counters' double free, which no path makes.

### Rules the mutants do not cover

- **P8's figures** (the research's README) were measured before the fix. Each bind, step and read
  now runs inside `while-held`'s section, around the accessor's, so a convenience's cost per value
  has moved; P8 was not run again.
- **A keyboard's or a collect request's handler** re-entering a call: the timer's stands for them,
  as each runs between any two sections.
- **The docs' prose:** "Each call runs once", the fold's lost engine and the script's re-entry are
  read by `test-docs` as text only; the rows above hold each.

### Findings

- **A second resume on the code before the fix answered rows of NULL:** it stepped a statement
  whose bindings the first resume's return had cleared, `(#(11) #(null) #(null) #(null))` and the
  like (the who suite's red run).
- **A remainder resumed twice shares every object made before the expiry:** under D07 the second
  resume wrote another engine's value into the row vector the first had answered. On the fixed
  code the second resume's next section refuses before any column is read, so it can write a
  vector only with the value its first slice read already.
- **A whole new call is the caller's:** a remainder taken before a call's first expression makes
  one when resumed, with a flag of its own, so a row that re-enters a call tells those apart by
  what they touch, or, for the script, whose whole new call touches only rows of its own, by the
  fuel: below the fuel at which the same call shape, refused at its first check, completes, 76
  against whole new calls at 1 to 9.
- **An expiry past the fold's last step, before its normal return,** finalizes the statement, and
  the resume answers the fold all the same: fuels 133 and 134 of the new suite's fold row, and the
  review's probe at fuel 101, `(6 (() 0) 6 (() 0))`.
- **A continuation a timer handler takes inside the caller's procedure,** re-entered, finishes that
  call: a counter bumped at the procedure's entry counts it again.
- **The conveniences' engine fuels fell by about half,** since the accessor's checks now run inside
  `while-held`'s section, where an engine spends no ticks.
- **Part B's probes are kept** in [research/m3-slice-3/](research/m3-slice-3/README.md), named for
  what each measures, run again on both libraries after the fix; `p6.sps` is not, its finding held
  by the engines suite's one-value-a-section row. The suites' citations of `build/b/probes/` now
  name the probe that measured each claim: one of these, part A's `busy-reset.sps`, M2's
  `probe-block.sps` for a returning insert's finalize under a read, or M3's research, single K2.2,
  for a held `select *`.
