# M3 slice 5 mutation log

Evidence that each rule slice 5's suites claim to guard fails through the property it names
([M3 plan](2026-11-15-m3-plan.md) §5, slice 5). Format of
[the M3 slice 3 log](m3-slice-3-mutation-log.md). The slice is built in two parts, A and B, each
keeping its own part of this log; part C holds the fixes of the slice's review, and part D the
conveniences' claim, the fix of a defect in slice 3 that the M2 session found.

## Part A: the settings list at open

Part A adds one library and changes two:

- **`(chez-sqlite3 private open)`, new:** `open-database` and `call-with-database`, moved from
  the connection's library, now taking the settings list (ADR-0018), and `applied-settings!`, for
  the suites. They had to move: the settings run statements through M2's statement tier, whose
  libraries import the connection's, so the connection's library cannot import them.
- **`(chez-sqlite3 private connection)`:** the open verbs and `open-database-with-cache-capacity`
  gone; `prepared-open`, `connection-outcome` (M2's `open-outcome`, renamed, since
  `(chez-sqlite3 private statement)` imports the library whole and defines an `open-outcome` of
  its own), `opened-database` and `close-connection` exported; the open's section reads the call's
  flag first, and answers `left` when it is set.
- **`(chez-sqlite3)`:** imports the two verbs from the new library. Its exports are unchanged.

Its suites: `test-open-settings` and `test-open-engines`, new. Changed with the move:
`test-public`'s export rows and its list of where each public name is defined, and
`test-never-loads`' list of the libraries that load libsqlite3. Changed with the private opener's
removal, each moved to the public `statement-cache` setting: `test-connection-cache`, whose
refusal rows now name `open-database` and whose row for the opener's own order is gone (the new
suite holds the order), `test-conveniences`, `test-conveniences-who` and `test-execute-script`.
An Opus agent built it from the lead's brief, in the slice's worktree.

Every mutation ran in one of three copies of the worktree, made under its git-ignored `build/mut/`
without `.git` or `build/`, through that copy's own `scripts/guix-env`, after `make deps` in the
copy, and with the worktree's `src/` and `tests/` synced into it before the run. A mutation
changes one library under `src/`, one place or, where an import must follow, two; the driver checks
that each old text occurs once in the worktree's file (each did), writes the mutant into the copy,
runs the five suites below, each under `timeout 300`, and puts the file back. The counts are read
from the suites' own output (`# of unexpected failures`), never by eye; a suite that died with no
count would be marked `died`, and one that timed out `hung` (none did). The driver and the
mutation definitions are in the session scratchpad, not the repository.

### The red runs

The new suites were written against the brief, and run first against a copy whose
`(chez-sqlite3 private open)` was a stub: it split the list from the options and ignored it,
checking nothing, applying nothing, the cache 32; `applied-settings!` did nothing. The changed
suites ran against `9deda02`'s libraries, the slice's base, unchanged.

| Suite | Red run | Green run |
|---|---|---|
| `test-open-settings`, against the stub | 3 passed, 18 failed | 21 passed |
| `test-open-engines`, against the stub | 2 passed, 4 failed | 6 passed |
| `test-public`, against `9deda02` | 18 passed, 3 failed | 21 passed |
| `test-never-loads`, against `9deda02` | 4 passed, 1 failed | 5 passed |
| `test-connection-cache`, against `9deda02` | 14 passed, 7 failed | 21 passed |
| `test-conveniences`, against `9deda02` | 20 passed, 3 failed | 23 passed |
| `test-conveniences-who`, against `9deda02` | 11 passed, 3 failed | 14 passed |
| `test-execute-script`, against `9deda02` | 17 passed, 1 failed | 18 passed |

The rows that passed red are each suite's load row and its counts rows; against the stub, the
engine suite's last counts row failed too, the stub's re-entered calls leaving connections open.
Against the stub, the row "no setting is applied unasked" failed by its one setting not applied;
its `busy_timeout` of 0, which the stub cannot fail, is watched failing by B07 below.

Green: `make test` ran 56, passed 56, against the baseline's 54 of 54, the two new suites added.
At the floor, 3.45.1, through `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH` (`$CC -dM -E` read
`SQLITE_VERSION "3.45.1"`, and the suites loaded 3.45.1), the two new suites, the six they
changed, and `test-connection`, `test-statement` and `test-settings` passed at the same
counts, and SQLite answered alike: every value read back, each
mismatch's actual, the busy waits, the fuels. Under the memory gate, `make test-memory` on the
nine passed with no error and nothing lost, none `SLOW`: `test-open-settings` 13 s,
`test-open-engines` 23 s, `test-connection` 13 s, `test-connection-cache` 11 s,
`test-conveniences` 10 s, `test-conveniences-who` 13 s, `test-execute-script` 11 s,
`test-public` 9 s, `test-never-loads` 7 s; at the floor the two new suites took 13 s and 23 s.

The engine rows' fuels, alike on both libraries: the open with the six settings and
`statement-cache` on a file completes without expiring at fuel 553; the same call refused at its
first check, a filename that is no string, completes at 79. Resumed twice, of the 552 fuels that
expired, 525 second resumes were refused, `&sqlite-closed`, 18 answered the same connection
again, past the call's last section, and 9, all below fuel 79, made a whole new call.
`call-with-database`'s procedure starts at its 548th tick, the refused call takes 83, and of the
547 continuations re-entered, 521 were refused, 18 called the procedure again past the settings,
and 8, all below 83, made a whole new call. **Corrected in part C:** re-measured three times on
these libraries with the final suite, the split is 520, 19 and 8, as the slice's review read it;
the fixed libraries' fuels are part C's.

### The mutations

The five suites: `test-open-settings` (settings), `test-open-engines` (engines),
`test-connection` (connection), `test-connection-cache` (cache) and `test-public` (public).
Baselines, from the green runs: 21, 6, 63, 21 and 21. Each row names the suites that failed and how
many rows failed in each. A mutation counts as caught when at least one row failed.

#### open.sls: the checks and their order

| Mutation | Guards | Failed |
|---|---|---|
| A01 | the list is checked after M2's checks, not before (the order) | settings 1 |
| A02 | a second list is refused (the split's refusal raised) | settings 2 |
| A03 | the list's refusals are raised | settings 3, cache 8 |
| A04 | the split happens before M2's checks (a second list refused before a bad filename) | settings 1 |

#### open.sls: the capacity, the steps and their order

| Mutation | Guards | Failed |
|---|---|---|
| B01 | open-database passes the list's capacity to the record | settings 4, engines 2, cache 6 |
| B02 | call-with-database passes the list's capacity to the record | settings 2, engines 1, cache 1 |
| B03 | open-database applies the steps | settings 9, engines 2 |
| B04 | call-with-database applies the steps | settings 4, engines 1 |
| B05 | busy-timeout runs first: the steps in settings-plan's order, not reversed (the list's, for a list with busy-timeout last) | settings 1 |
| B06 | call-with-database applies its settings before calling its procedure | settings 3, engines 2, connection 1 |
| B07 | open-database applies no setting unasked: no default busy timeout (decision 8) | settings 2 |
| B08 | call-with-database applies no setting unasked: no default busy timeout (decision 8) | settings 2 |

#### open.sls: a setting set and read back

| Mutation | Guards | Failed |
|---|---|---|
| C01 | the set statement is stepped | settings 7, engines 3 |
| C02 | the read statement's row is read | settings 12, engines 3 |
| C03 | each statement is finalized after its use | settings 1 |
| C04 | a setting's prepare is M2's, inside the section that reads the flag; the cache's check-out instead, outside it | engines 2 |
| C05 | the read-back is a second statement, not the set's own row | settings 8, engines 3 |
| C06 | the read follows the set (set, then read) | settings 11, engines 3 |
| C07 | the read-back is compared (a setting applied without its read-back) | settings 5 |
| C08 | the settings' statements never use the cache: each is finalized, never filed in it | settings 1 |

#### open.sls: a failure closes, then raises

| Mutation | Guards | Failed |
|---|---|---|
| D01 | a mismatch closes the connection before it raises | settings 8 |
| D02 | a close that fails then is not raised over the setting's condition | settings 1 |
| D03 | a failure with the flag set closes nothing (the first resume's connection) | engines 1 |
| D04 | the flag is set once the settings are done | engines 3 |
| D05 | a mismatch is raised as &sqlite-setting-mismatch, its three fields | settings 5 |
| D06 | a mismatch names the verb (who) | settings 5 |
| D07 | a mismatch stops the settings and is raised, never dropped | settings 5 |
| D08 | every raise of a setting's statement is caught, then raised after the close, the same object | settings 4 |

#### open.sls and connection.sls: the call's flag

| Mutation | Guards | Failed |
|---|---|---|
| E01 | every section of the settings reads the flag (prepare) | engines 2 |
| E02 | every section of the settings reads the flag (all, a fresh never-set check) | engines 2 |
| E03 | the open's section reads the flag | engines 3 |
| E04 | the flag is the call's first expression, before the checks | engines 1 |
| E05 | the flag read before the open answers left (connection.sls) | engines 3 |
| E06 | a left outcome raises &sqlite-closed from the who (connection.sls) | engines 2 |
| E07 | the read's section reads the flag | engines 2 |
| E08 | the finalize's section reads the flag | engines 2 |
| E09 | the set's steps read the flag | engines 2 |
| E10 | the read's step reads the flag | engines 2 |

#### open.sls: call-with-database's handler and flag

| Mutation | Guards | Failed |
|---|---|---|
| F01 | call-with-database's settings run inside the handler that marks a raise, so a close's failure is not raised over a setting's | **survived** |
| F02 | call-with-database's open reads the flag | engines 2 |
| F03 | call-with-database's settings read the call's own flag, set once they are done | engines 2 |

**41 mutations, 40 caught, one survived.** The whole set ran once, on the final libraries and
suites, which no edit changed after it; 38 of them had run once before, on the same libraries with
the engine suite lacking its `call-with-database` row, when F01 to F03 survived. Each mutation's
failing rows were read from its own output: A01 and A04 the order row; B05 the busy-first row;
B07 and B08 the unasked row and the busy-first row's wait with no `busy-timeout`; C03 and C08 the
row that an open with settings leaves no statement tracked; D02 the failed-close row; the D and E
flag mutants the two re-entry rows of `test-open-engines`.

**C04** was caught by its shape, not by the cache. At open the cache is empty, and the mutant
finalized what it checked out, so only the prepare's flag told it from M2's prepare: a cached
statement's check-out runs outside `while-held`, and a second resume landed in
`call-with-open-handle`'s own wind, refused `re-entered`, where the library raises
`&sqlite-closed`. C08, which files the settings' statements in the cache, is the mutant of the
rule itself, and the no-statement-left row fails it.

**The survivor, F01,** moves `call-with-database`'s settings out of the handler that marks a
raise. That handler matters to a setting's failure only when the close the settings make then
fails too: the after thunk's second close would then fail again, and, with no raise marked, be
raised over the setting's condition. No row can reach it. A close fails only with a statement the
connection does not track, or a backup reading from it (ADR-0012, amended), and nothing of the
caller's reaches `call-with-database`'s connection before its procedure, which a failed setting
never calls. The shared failure path, `settled`'s, is held by the failed-close row through
`applied-settings!`, which D02 fails.

**Corrected in part C: that argument is false.** The procedure can make the close fail itself,
with a statement its connection does not track, and then re-enter a continuation a timer's
handler took inside the settings: the re-entry is refused there, a raise of the settings', while
the close fails. As built, the call raises `&sqlite-closed`; with F01 planted, every such tick
raises the close's refusal instead (the review's `f01.sps`). Part C's F01 row in
`test-open-engines` holds it, and C12, F01 on part C's libraries, fails that row.

### A trap the slice found

**An engine's remainder resumed twice re-runs Chez's own procedures from inside, and they keep
state the continuation does not.** On Chez 10.4.0, `(string-append "PRAGMA busy_timeout = "
(number->string 1234))` as an engine, expired at fuel 22, 23, 31 or 32 and its remainder resumed
twice, answered the whole string the first time and `"PRAGMA busy_timeout = "` the second:
`number->string` writes through a string port whose buffer the first resume had drained.
`string-append` alone, at every fuel, answered alike both times
([research/m3-slice-5/](research/m3-slice-5/README.md), `number-twice.sps`, moved there in part
B from the worktree's git-ignored `build/probe/`). The engine row found it: with the call's flag made
after the checks, a second resume of a remainder taken inside slice 1's `settings-plan` sent that
text to SQLite, which answered "incomplete input", at fuels 130, 131, 139 and 140. With the flag
the call's first expression, the open's section refuses such a resume before anything it computed
again reaches SQLite; E04 is that mutant.

## Part B: the lock rows, §4.8's settings plants, and the public names

Part B changes no library's behaviour:

- **`tests/test-open-locks.sps`, new:** the settings under another connection's lock (§4.3;
  slice-0 P2, P3 and P14), five rows, two connections on a file in each, the open a fresh
  connection holding no read of its own. Each timed open's busy timeout is 1500 ms, a wait at
  least 1000 ms, and each case prints its milliseconds. It does not repeat `test-open-settings`'
  busy-first row, which already holds `synchronous` waiting under an exclusive lock and
  `journal-mode wal` refused under a reserved lock with no busy timeout.
- **`(chez-sqlite3)`:** `open-database` and `call-with-database` take §4.9's signatures,
  `String (U Symbol Settings) ...`, with `;;   Settings = (Listof (Pairof Symbol Any))` after
  them; it exports `sqlite-setting-mismatch?` and its three accessors, each with its signature.
- **`tests/test-public.sps`:** its list grown by the four, its count from 60 to 64.
- **`docs/reference.md`:** the two entries' signatures; a "Settings" part of `open-database`'s
  entry, a `####` heading, since `test-reference` takes every `###` heading for an entry: the
  list, a table of each setting's values, the checks SQLite would not make, `busy-timeout` first,
  the read-back and its mismatch, `(journal-mode . wal)` on `":memory:"` as a run example, a
  failure closing the connection, no busy timeout unasked, and a table of what waits under each
  lock and what is refused at once; `call-with-database`'s settings and a run example; the
  cache's size by `statement-cache`; the four entries in Conditions, its table and count; and
  `Settings` and `SqliteSettingMismatch` among the page's type names.
- **The research:** part A's two probes, `number-twice.sps` and `busy-probe.sps`, moved from the
  worktree's git-ignored `build/probe/` into
  [research/m3-slice-5/](research/m3-slice-5/README.md), with part B's `locks.sps`; each SQLite
  probe makes its database under `build/` and removes it itself. `busy-probe.sps` was changed in
  the move: its first draft left the database in `build/probe/d/` and the connection of its
  `foreign-keys` case open, and read its descriptors from after the holder had locked. The engine
  suite's comment that cited `number->string` now cites the research, as part A's paragraph above
  does.

Every mutation and plant ran in one copy of the worktree, `build/mut/b1`, made without `.git` or
`build/`, through that copy's own `scripts/guix-env`, after `make deps` in the copy. Before each
run the driver copies the worktree's `src/`, `tests/` and `docs/` into the copy. A mutation
changes one library, one place, or two where an import must follow; the driver checks that each
old text occurs once in the worktree's file (each did), writes the mutant into the copy, runs the
suites, each under `timeout 300`, and puts the file back. The counts are read from the suites' own
output (`# of unexpected failures`), never by eye; a suite that died with no count would be marked
`died`, and one that timed out `hung` (none did). The driver and the definitions are in the
session scratchpad, not the repository.

### The red runs

| Suite | Red run | Green run |
|---|---|---|
| `test-open-locks`, against a copy whose `settled` applies no setting | 3 passed, 5 failed: every row but the load and the two counts | 8 passed |
| `test-public`, its list grown, against part A's `(chez-sqlite3)` | 18 passed, 3 failed: the count, the list, the `eq?` row | 21 passed |
| `test-reference`, the page written, against part A's `(chez-sqlite3)` | 16 passed, 3 failed: the entries that are no export, the whole lists, the two open verbs' lines against their comments | 19 passed |
| `test-reference`, the comments changed, against `9deda02`'s page | 16 passed, 3 failed: the exports with no entry, the whole lists, the two open verbs' lines | 19 passed |
| `test-docs`, the page written, against part A's `(chez-sqlite3)` | 85 passed, 2 failed: the mismatch's run example, and the code spans that name no export | 87 passed |

Green: `make test` ran 57, passed 57, against part A's 56, `test-open-locks` added. At the floor,
3.45.1, through `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH` (`$CC -dM -E` read
`SQLITE_VERSION "3.45.1"`, and the library loaded 3.45.1), `test-open-locks`, `test-public`,
`test-reference`, `test-docs`, `test-open-settings` and `test-open-engines` passed at the same
counts.
Under the memory gate, `make test-memory` passed each with no error and nothing lost, none `SLOW`:
on 3.53.1, `test-open-locks` 15 s, `test-public` 10 s, `test-reference` 9 s, `test-docs` 31 s and
`test-open-engines` 23 s; at the floor, `test-open-locks` 16 s, `test-public` 9 s,
`test-reference` 10 s and `test-docs` 30 s.

The lock rows' times, in ms, as `test-open-locks` printed them:

| Case | 3.53.1 | 3.45.1 | 3.53.1, gate | 3.45.1, gate |
|---|---|---|---|---|
| exclusive, `journal-mode wal`, waits | 1502 | 1502 | 1525 | 1525 |
| exclusive, `journal-mode delete`, waits | 1502 | 1502 | 1511 | 1510 |
| read, `journal-mode wal`, waits | 1503 | 1503 | 1511 | 1511 |
| exclusive: `foreign-keys`, `temp-store`, `trusted-schema`, `busy-timeout` alone | 0 to 1 | 0 to 1 | 2 to 5 | 1 to 4 |
| read, and reserved: all but `journal-mode wal` | 0 to 1 | 0 | 6 | 5 |
| reserved, `journal-mode wal`, refused | 0 | 0 | 4 | 4 |
| WAL, idle: `delete`, `truncate`, refused; unused: `delete`, opened | 0 to 4 | 0 to 2 | 3 to 4 | 2 to 4 |
| exclusive, let go at 500 ms | 529 | 530 | 534 | 538 |
| read, let go at 500 ms | 530 | 529 | 535 | 536 |
| WAL on WAL, beside each of the four | 0 to 1 | 0 to 1 | 2 | 2 to 4 |

So every wait ended within 25 ms of its 1500, and every open at once took under 7 ms. An open let
go mid-wait returned 529 to 538 ms after it began, 500 of them the holder's sleep: about P3's 28.7
ms after the release, the busy handler's next retry.

### The mutations of the lock rows

The suites: `test-open-locks` (locks) and `test-open-settings` (settings), baselines 8 and 21.
The rows of locks: waits, at once, refused at once, mid-wait, WAL on WAL, and the last counts row.

| Mutation | Guards | locks: the rows that failed | settings |
|---|---|---|---|
| L01 | `busy-timeout` is applied: its step dropped from the plan | waits, at once (`busy-timeout` alone read back 0), mid-wait (busy at once) | 3 |
| L02 | `busy-timeout` runs first: in the list's order instead | waits (`delete` with `busy-timeout` last answered at once), mid-wait | 1 |
| L03 | a setting's raise closes the connection; a mismatch still does | waits, refused at once, each `(counts …)` where `nothing-left` was due; then at once, mid-wait, WAL on WAL and the counts row, by the connections left | 4 |
| L04 | no retry in Scheme: each setting retried on busy, every 100 ms, 15 times | refused at once: each `waited` | 1 |
| L05 | the wait is the timeout asked for: `busy-timeout` written and expected as a tenth | waits: each `at-once`; at once: 150 read back; mid-wait: busy before the release | 3 |
| L06 | a setting's own condition is raised: a mismatch raised instead | waits, refused at once | 4 |
| L07 | no transaction around the settings: `BEGIN IMMEDIATE` before them, `COMMIT` after | waits, at once, refused at once, mid-wait, WAL on WAL: `BEGIN IMMEDIATE` busy, or `journal_mode = wal` failing inside it | 10 |
| L08 | a read-back reads no schema: each read through its table-valued pragma, a SELECT | waits: busy at the read-back of `busy-timeout`; at once: each of the four under the exclusive lock `waited`, then busy | 1 |

**8 mutations, 8 caught, none survived,** on the final suites and libraries. L01 to L07 ran twice,
the second time on the final files; L08 once, on them.

- **L08 is the one whose only failure in locks is a time:** under the exclusive lock its four
  opens waited out the timeout, so the at once row's `at-once` holds what P2 measured, that
  `foreign-keys`, `temp-store`, `trusted-schema` and `busy-timeout` read no schema.
- **WAL on WAL fails directly only to L07 and the red stub;** L03 fails it by the connections
  earlier rows left. It holds SQLite's answer, P14, more than a rule of the library's: a library
  that took a lock of its own around the settings would fail it.

### The plants

The suites: `test-open-settings` (settings), `test-open-engines` (engines), `test-settings`
(plan), `test-connection-cache` (cache) and `test-statement-cache` (table), baselines 21, 6, 59,
21 and 32. **6 plants, 6 caught, none survived,** each run twice, the second time on the final
files. Each of §4.8's settings plants is caught by a row of part A's, which part B names here and
adds none for.

| Plant | §4.8's plant | Failed | The row of part A's |
|---|---|---|---|
| P1 | a setting applied without its read-back: the set runs, no read statement, a match answered | settings 6 | "journal-mode on :memory: mismatches at each of its values …" |
| P2 | a value passed to SQL unchecked: a number outside an enumerated setting's table written as its digits, expected back as given | settings 1, plan 3 | "every refusal of the settings list …", at `(synchronous . 4)` |
| P3 | the cache ignoring its setting: every record's capacity 32, in `connection-outcome` | settings 4, engines 3, cache 6 | "statement-cache through the public surface …", "at a statement-cache of 0 …", "at a statement-cache of 2 …" |
| P4 | evicting one too early: `(>= (+ size 1) capacity)` in slice 1's table | settings 3, cache 2, table 12 | the same three |
| P5 | evicting one too late: `(> size capacity)` | settings 3, cache 3, table 12 | the same three |
| P6 | capacity 0 keeping a statement: its own case dropped | settings 1, cache 2, table 6 | "at a statement-cache of 0 …" |

The named rows' failing output:

- **P1:** expected each `(raised (mismatch open-database journal-mode V memory library-condition))`
  for `delete`, `truncate`, `persist` and `wal`, and `call-with-database`'s, then
  `proc-not-called`; actual `(opened opened opened opened #<void> proc-called …)`. Part A's C07,
  which still runs the read and drops its comparison, failed 5 of settings; P1, which runs no read,
  fails the same and the depth row.
- **P2:** at `(synchronous . 4)`, expected `(assertion-violation open-database
  (setting-out-of-domain synchronous 4))`, nothing made; actual `(no-raise no-counts)`, the file
  made, through both verbs: the open succeeded, `synchronous` 4 stored and read back as asked.
  `(foreign-keys . 1)` and `(temp-store . 2)` mismatched instead, and the later cases found the
  file made.
- **P3:** after 33 distinct statements, expected `(32 32 32 1 33 1)`, actual
  `(32 32 32 32 32 32)`; at 0, expected `((0 0 0 0 0) (1 2 3 4 32))`, actual
  `((1 2 3 4 32) (1 2 3 4 32))`; at 2, expected `("select 'a'" "select 'c'")`, actual
  `("select 'a'" "select 'b'" "select 'c'")`.
- **P4:** after 33, actual `(31 31 31 1 33 1)`: one fewer at the default, and at 1 the same, since
  a table of one evicts nothing before its first; at the default after each convenience,
  `(1 2 3 4 31)`; at 2, `("select 'c'")`.
- **P5:** after 33, actual `(33 33 33 2 33 2)`; at the default, `(1 2 3 4 33)`; at 2,
  `("select 'a'" "select 'b'" "select 'c'")`.
- **P6:** at 0, actual `((1 1 1 1 1) (1 2 3 4 32))`.

### Rules the mutants do not cover

- **The mid-wait row's `after-the-release`** says the open was still waiting when the holder let
  go. The holder sleeps 500 ms after this thread says the open begins; if this thread then took
  longer than that to reach SQLite's busy handler, the open would find no lock, and return after
  the release without having waited, passing. No mutant shows it: one that never waits, L01, fails
  the waits row anyway. Under the gate the opens that run at once took under 7 ms, so the window
  is that 500 ms against a few.
- **The descriptors** each row reads once its holders have closed: no mutant leaks a descriptor
  without leaking its connection, which the counts see first.

### Findings

- **Leaving WAL is refused beside a connection that has read the file, not beside any open one.**
  Slice 0's P2 measured a holder that had made the file and written it, and the plan, ADR-0018 and
  `traps.md` say "even an idle one". Beside a holder opened and never used, `journal-mode`
  `delete`, `truncate` and `persist` opened, alike on both libraries; after a `select`, a
  `pragma journal_mode` or a write, then idle, each was refused at once
  ([research/m3-slice-5/](research/m3-slice-5/README.md), `locks.sps`). The row holds both.
- **Under an exclusive lock, every `journal-mode` waits,** `delete`, `truncate` and `persist` as
  well as P2's `wal`, and every `synchronous` (`locks.sps`); under a read only `wal` waits.
- **Part A's `busy-probe.sps` leaked a connection,** its `foreign-keys` case's, which it never
  closed; the copy kept here closes it.

## Part C: the review's fixes

The slice's adversarial review found two holes in the open verbs and six gaps in the suites. Its
probes and mutants are in the worktree's git-ignored `build/review/`. The lead reproduced the
first hole. Part C closes both holes, adds a row for each gap, and reruns the review's probes and
mutants. An Opus agent built it from the lead's brief, in the slice's worktree.

- **The first hole:** one remainder, R, resumed again while an earlier resume of it was still
  pending opened a second connection, and left the first open, counted and unreachable. The
  schedule: R taken before the open at fuel 199; resumed at fuel 38 until it expired after the
  open, as R1; R resumed again to its end, opening and returning another connection; then R1,
  refused.
- **The second:** the same schedule past the open applied the settings twice. The connection it
  returned kept a settings statement tracked, at a row.
- **Why:** the call's flag was set only once the connection left the call, so two pending runs
  of one call could each pass the same section.

### The shape: one claim a call, one-shot sections

The review offered two shapes:

- **A.** The open's section claims the call, so a later run's open is refused, and the settings'
  sections refuse only once the connection has left.
- **B.** Each section is one-shot: a counter in the call, which each section compares with the
  position the run's continuation carries, then advances.

**B, because A leaves two pending runs inside the settings.** Both are past the open, and the
connection has not left, so A refuses neither: each applies the settings, and the refused one's
statement stays tracked. Only a position each run carries in its own continuation tells two
pending runs apart.

As built, in `(chez-sqlite3 private open)`:

- **The claim:** `made-claim`, the call's first expression, holds the position of the next
  section any run of the call may make, 0 at first.
- **Each run's position** is an argument, never assigned, so a continuation holds it as it was.
- **Every section** of the call claims its position in `in-section`, inside the section: claimed
  when the call's position is the run's, advancing it; refused otherwise, touching nothing. The
  sections, in order:
  - the open's, at 0, in `connection-outcome`;
  - then, for each setting, its set and then its read: a statement's prepare, each step, the
    read's column, the finalize;
  - and, on a failure, the close, claimed by the run whose section failed, at the position after
    the failure.
- **A refused run** raises `&sqlite-closed` from the verb, and makes no later section ("Guard
  every call").
- **A section's outcome is data.** A raise inside one is caught there, with the run's next
  position, so the failure's close knows where it stands.

Two more changes came with it, each from a row that failed:

- **The checks run in one critical section,** `checked`, what they raise caught there and raised
  again after it. A run that overtakes the first reaches the open first, so no claim can refuse
  what it computed. `test-open-interleave` found `call-with-database` sending
  `PRAGMA busy_timeout = 12341234` to SQLite, read back as a mismatch: Chez's `number->string`,
  resumed again from inside while an earlier resume was pending, answered the digits twice
  (research, `number-interleaved.sps`). The claim stays the call's first expression, before any
  SQL text is built.
- **`call-with-database`'s open sits inside the handler that marks a raise.** A continuation
  taken inside the extent before the open, re-entered once the procedure had made the close fail,
  is refused at the open's section. Outside the handler that refusal was not marked, so the
  close's failure was raised over it. The review's `f01.sps` counted those ticks among its 1 to
  177. Inside the handler, the call raises `&sqlite-closed`.

`connection-outcome`'s fifth argument is now `refused?`, and its outcome `(refused)`, which
`opened-database` raises as `&sqlite-closed`.

What it costs: an engine spends no ticks inside a section, so the fuels fell.

| Call, on 3.53.1 and 3.45.1 alike | Reviewed | Fixed |
|---|---|---|
| `open-database`, the six settings and `statement-cache` on a file, completes unexpired at fuel | 553 | 221 |
| the same, its procedure reached, `call-with-database`, starts at tick | 548 | 233 |

The re-entry split the review read as 520, 19 and 8 was re-measured on the reviewed libraries
with part C's suite, three runs each. It is 520 refused, 19 called again and 8 new, every time;
part A's 521 and 18 are corrected above. On the fixed libraries it is 202, 22 and 8.
`open-database` resumed twice gives 525, 18 and 9 reviewed, as part A has it, and 190, 21 and 9
fixed.

### The files and signatures

- **`src/chez-sqlite3/private/open.sls`:**
  - new, internal:
    - `checked : Symbol Any (Listof Any) -> (Values String Natural Natural (Listof Setting-Step))`;
    - `made-claim : -> Claim`, where `Claim = Natural -> Boolean`;
    - `in-section : Claim Natural (-> A ...) -> Section`;
    - `stepped`, `read-once : Symbol Statement Claim Natural -> Run`;
  - changed:
    - `ran : Symbol Database String Claim Natural Boolean -> Run`;
    - `step-applied : Symbol Database Setting-Step Claim Natural -> Run`;
    - `settled : Symbol Database (Listof Setting-Step) Claim Natural -> Void`;
  - the three exports' signatures are as they were.
- **`src/chez-sqlite3/private/connection.sls`:**
  `connection-outcome : Symbol String Natural Natural (U (-> Any) #f) -> (U ... (List 'refused))`,
  its last argument now `refused?`; `opened-database` raises `refused` as `&sqlite-closed`.
- **`tests/test-open-interleave.sps`, new:** the interleaving, swept through both verbs; a failing
  open resumed twice; an interrupt that escapes, at each of `call-with-database`'s sections.
- **`tests/test-open-engines.sps`:** `call-with-database` under an engine; the F01 row.
  `reentry-kind` is factored out of the re-entry row, which is otherwise unchanged.
- **`tests/test-open-settings.sps`:** options and a list together; the busy-first row's upper
  bound.
- **`tests/test-open-locks.sps`:** the list's order; the waits row's upper bound.
- **`docs/reference.md`:** a paragraph for each open verb: each call opens once and sets each
  setting once.
- **The research:** part C's three probes ([research/m3-slice-5/](research/m3-slice-5/README.md)).

### The tell, and the controls

**Whether a setting was applied once is read from SQLite.** `test-open-interleave` registers an
entry point through `sqlite3_auto_extension`, which notes each open and sets an authorizer on the
new connection. SQLite calls the authorizer at every prepare, and a setting takes effect at its
prepare (M3's research, single P3), so each PRAGMA prepared is noted with its connection, its
name and its value.

- **Both callbacks are `__collect_safe`,** since SQLite calls them inside calls that are.
- **`sqlite3_reset_auto_extension`** unregisters the entry point at the end:
  `sqlite3_cancel_auto_extension` keeps SQLite's list, 8 bytes the memory check found.
- **Events are grouped by open, not by handle,** since a closed connection's address is reused.
- **The procedure notes itself inside `call-with-open-handle`'s section,** where the connection
  is checked open, so a reused handle is never misattributed.

**Which fuels lie before a call's first expression is measured.** At each fuel a control resumes
R to its end twice, one after the other: the second makes a whole new call when it opens a
connection of its own. A refused call's completing fuel was no bound: its raise costs more ticks
than the checks, the open and the settings together, so it fell past the open.

**A collect request costs a run ticks** (research, `gc-ticks.sps`), and a trial at fuel 17 once
lay two ticks before its control. So each fuel of a sweep begins with a collection, with
`collect-trip-bytes` raised to 128 MiB, far above what a fuel's runs allocate. Once so, every
run's trials came out alike, the same count each run. A trial may still make a new call where
the control made one at its fuel or the one before, a tick's room. The F01 row instead judges
each tick by its own capture, the connections counted then.

### The red runs

Each new row was run first against the libraries as the review found them, in a copy under
`build/mut/` without `.git` or `build/` (`red5`). Where the reviewed libraries pass a row, its red
run is against its mutant.

| Suite | Red run | Green run |
|---|---|---|
| `test-open-interleave`, new, against the reviewed libraries | 5 passed, 6 failed: both sweeps and the failing open through `open-database` by their own property, the rest by the connections those leaks left counted | 11 passed |
| `test-open-engines`, its two new rows, against the reviewed libraries | 7 passed, 1 failed: the F01 row | 8 passed |
| `test-open-settings`, the together row, against N50 and against N51 | 21 passed, 1 failed, each | 22 passed |
| `test-open-settings`, the busy-first row's upper bound, against N2p | 21 passed, 1 failed | 22 passed |
| `test-open-locks`, the order row, against N41 | 8 passed, 1 failed | 9 passed |
| `test-open-locks`, the waits row's upper bound, against N2p | 8 passed, 1 failed | 9 passed |

What the reviewed libraries failed in `test-open-interleave`, by kind:

- **open-database's sweep:**
  - 11539 trials opened a connection no run answered;
  - 10126 left counts behind them;
  - 2921 applied a setting twice on the connection answered;
  - 1271 left a statement tracked;
  - 1463 had a refused run that touched something.
- **call-with-database's sweep:**
  - 13029 trials opened two connections in one call;
  - 96 sent other SQL than the plan's;
  - 620 raised a mismatch.
- **The failing open, through open-database:** at 37 fuels, a remainder taken with the
  connection still open, its second resume raised the mismatch again where `&sqlite-closed` was
  due. A twin past the read's finalize but short of the failure's flag was not refused. That is
  a defect of the reviewed libraries the review did not list.
- **The other rows** failed by the connections those leaks left counted.

The review's own N1 and F01, planted in the reviewed libraries:

- **Under N1,** the failing-open rows failed by their own property: 160 and 127 fuels made a
  whole new call where the control made none.
- **Under F01,** the F01 row failed at 292 ticks after the open, the close's refusal raised over
  the settings'.

Green:

- **`make test`:** ran 58, passed 58, against the baseline's 57 of 57, `test-open-interleave` added.
- **At the floor, 3.45.1,** through `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH`:
  - `$CC -dM -E` read `SQLITE_VERSION "3.45.1"`, and the library loaded 3.45.1;
  - `test-open-interleave` 11, `test-open-engines` 8, `test-open-settings` 22,
    `test-open-locks` 9, `test-connection` 63, `test-public` 21, `test-reference` 19,
    `test-docs` 87, `test-conveniences` 23 and `test-connection-cache` 21 passed;
  - every fuel matched the current library's, but for the failing open through
    `open-database`, which completed at 135 where 3.53.1 completed at 134.
- **Under the memory gate,** `make test-memory` passed the four with no error and nothing lost,
  none `SLOW`: on 3.53.1, `test-open-interleave` 33 s, `test-open-engines` 25 s, `test-open-settings` 13 s and `test-open-locks` 16 s; at the floor, 31 s, 23 s, 13 s and 16 s.

### The sweeps

| Row | Completes unexpired at fuel | Trials |
|---|---|---|
| interleaved, `open-database`, two settings on `:memory:` | 75 | 2775: R at each of 74 fuels, R1 at every later one |
| interleaved, `call-with-database`, the same | 99 | 5732, alike each run once the collections were quieted; 5,300 to 5,700 before |
| a failing open twice, `open-database` | 134 (135 at the floor) | 133 |
| a failing open twice, `call-with-database` | 156 | 155 |
| `call-with-database` under an engine, six settings and `statement-cache` on a file | 739 | 738 fuels, each twice: dropped, then resumed |
| F01, a timer's ticks | the procedure starts at tick 233 | 232 ticks |
| an escape | 5 sections | 5 |

The control made its last whole new call at fuel 9 through both verbs. Of the interleaved trials:

- **open-database:** every trial answered a connection; 630 made two whole new calls.
- **call-with-database:** 1224 answered the procedure's, and 288 made new calls. An expiry after
  the open closes its connection, so most resumes raise `&sqlite-closed`.

### The mutations

Every mutation ran in one of three copies under `build/mut/`, `c1` to `c3`, made without `.git` or
`build/`, after `make deps` in each, through each copy's own `scripts/guix-env`. The driver
(`build/mut/c/drive.py`, its definitions `define.py`) works one mutant at a time:

1. it syncs the worktree's `src/` and `tests/` into the copy;
2. it checks that each old text occurs once in the worktree's file (each did);
3. it writes the mutant into the copy;
4. it runs the five suites, each under `timeout 300`;
5. it reads the counts from the suites' own output, and puts the file back.

A suite that died or hung would be marked so; none did.

The suites, and their baselines from the green runs:

- `test-open-settings` (settings), 22;
- `test-open-engines` (engines), 8;
- `test-open-interleave` (interleave), 11;
- `test-open-locks` (locks), 9;
- `test-connection` (connection), 63.

The whole set ran once on the final libraries and suites. Earlier runs on earlier drafts of the
suites shaped two rows:

- **C10 and C20** survived until the failing-open row required a refusal wherever the
  connection was still open at the expiry.
- **C08** was caught in two runs of three, by a trial two ticks before its control: the collect
  requests' shift, not the mutant. Once the sweeps were quieted it survived every run.

Five mutants are each the claim made at a section but never refusing:

- **C01 and C02** at the open;
- **C03** at every settings section;
- **C10** at the failure's close;
- **C15 to C18** at one kind of section each.

They keep the call's position advancing, so only a second run tells them. A claim that never
advances fails every row, which tests nothing particular.

| Mutation | What it plants | Failed |
|---|---|---|
| C01 | open-database: the open always opens, its claim made but never refusing | engines 5: 5 rows; interleave 6: 6 rows |
| C02 | call-with-database: the open always opens, its claim made but never refusing | engines 4: re-entered, under an engine, F01, end counts; interleave 2: interleaved (call-with-database), failing twice (call-with-database) |
| C03 | every section of the settings runs, its claim made but never refusing | engines 2: resumed twice, re-entered; interleave 2: interleaved (open-database), failing twice (open-database) |
| C04 | the claim advances to the run's next position whether or not it matched | interleave 6: 6 rows |
| C05 | the claim compares with <=: a run at or past the call's position claims | **survived** |
| C06 | open-database: the checks outside a critical section | interleave 1: interleaved (open-database) |
| C07 | call-with-database: the checks outside a critical section | interleave 1: interleaved (call-with-database) |
| C08 | open-database: the claim made after the checks, not first | **survived** |
| C09 | a refused section's run goes on to the next setting | engines 1: F01; interleave 2: failing twice (open-database), failing twice (call-with-database) |
| C10 | the failure's close: its claim made but never refusing, so it runs whoever reaches it (the review's N1, ported) | interleave 1: failing twice (open-database) |
| C11 | a section that raised gives the run its own position, not the next | settings 5: 5 rows; locks 7: 7 rows |
| C12 | call-with-database's settings outside the handler that marks a raise (the review's F01, ported) | engines 1: F01 |
| C13 | call-with-database's open outside the handler that marks a raise, as the slice first built it | engines 1: F01 |
| C14 | a section's claim in a critical section of its own, its work in another | engines 1: resumed twice; interleave 2: interleaved (open-database), failing twice (open-database) |
| C15 | the read's column read: its claim made but never refusing | **survived** |
| C16 | the finalize: its claim made but never refusing | **survived** |
| C17 | the prepare: its claim made but never refusing | engines 1: resumed twice; interleave 1: interleaved (open-database) |
| C18 | the set's steps: their claims made but never refusing | interleave 1: interleaved (open-database) |
| C19 | open-database: the open's claim read before its section, not in it | engines 5: 5 rows; interleave 6: 6 rows |
| C20 | a refused failure's close raises the setting's failure, not &sqlite-closed | interleave 1: failing twice (open-database) |
| C21 | open-database: the settings start at the open's position, 0 | settings 14: 14 rows; engines 6: 6 rows; interleave 8: 8 rows; locks 7: 7 rows |
| C22 | connection.sls: the open's section ignores its refusal | engines 5: 5 rows; interleave 6: 6 rows |
| C23 | call-with-database applies no setting | settings 5: 5 rows; engines 3: re-entered, under an engine, F01; interleave 3: interleaved (call-with-database), failing twice (call-with-database), escape; locks 4: waits, order, 2 more |
| N2p | each setting retried once on busy (the review's N2, ported) | settings 1: busy first; locks 1: waits |
| N3p | a set statement stepped once, not to done (the review's N3, ported) | **survived** |
| N16p | call-with-database records its connection outside the open's section (the review's N16, ported) | interleave 2: escape, end counts |
| N41 | the settings after busy-timeout run in reverse of the list (the review's) | locks 1: order |
| N50 | an option's flags dropped when a settings list is given (the review's) | settings 1: together |
| N51 | the settings list ignored when an option is given (the review's) | settings 1: together |

**29 mutations, 24 caught, 5 survived,** on the final libraries and suites. Where a mutant fails
many rows, most fail by the connections an earlier row leaked. The rows each fails by its own
property:

| Mutants | Row |
|---|---|
| C01, C04, C06, C14, C17, C18, C19, C22 | the interleaved sweep, through `open-database` |
| C02, C04, C07, C23 | the interleaved sweep, through `call-with-database` |
| C03, C09, C10, C14, C20 | the failing-open rows |
| N16p | the escape row |
| C12, C13 | the F01 row |
| C23 | `call-with-database` under an engine, the answers not as asked |
| N2p | the two upper bounds |
| N41 | the order row |
| N50, N51 | the together row |

### The survivors

- **C05, `<=` for `eqv?` in the claim, is equivalent.** A run's position never passes the
  call's. Positions advance only by a claim, which sets the call's to the claiming run's next;
  every other run's is the call's or behind it. So `<=` and `eqv?` agree on every reachable state.
- **C08, the claim made after the checks, changes nothing a row can see, or should.**
  - The checks run in one critical section, so no remainder is taken inside them.
  - One taken after them, before the claim, resumes into two whole calls, each with its own claim,
    open and settings, each answered.
  - Nothing between the checks and the claim is shared but the checks' values, which nothing
    changes. The whole-new-call window widens from fuel 9 to 15, and the control follows it.
  - The claim stays the call's first expression, as the brief asks. The number->string trap it
    once guarded is now the checks' section's to guard, which C06 and C07 hold.
- **C15, the column read claimed but never refusing, is equivalent.** A twin that reads again
  either reads a value from a statement at a row, which changes nothing, or is refused by the
  statement's own check, the other twin having finalized it. Either way its next section, the
  finalize, refuses it, or it is the live run.
- **C16, the finalize claimed but never refusing, is equivalent.** A finalize of a finalized
  statement does nothing, and the twin's next section refuses it. C10, the failure's close, is
  the call's last section, with no later section to refuse the twin. So the twin raised the
  failure where `&sqlite-closed` is due, and the failing-open row catches it.
- **N3p, a set stepped once, not to done, is equivalent on SQLite as measured.**
  - Of the six sets, `busy_timeout` and `journal_mode` answer one row, the others none (M3's
    research, single P1).
  - Each does its work at its prepare or its first step (single P3; slice 0's P2).
  - The second step only answers done, and the finalize then ends a statement at a row as it
    would at done.
  - Part A's C01, the set never stepped, is caught.

### The review's mutants

`build/review/mutants.json` defines eight of the review's mutants: N1, N2, N3, N16, N41, N50,
N51 and F01. Its numbering runs to 51, but the rest are not in the file. Three apply to part C's
libraries as written: N41, N50 and N51. Five cut code part C changed, and are ported:

| The review's | Here | Verdict |
|---|---|---|
| N1, the failure path reads the flag but does not set it | C10 | caught, the failing-open row |
| N2, each setting retried once on busy | N2p | caught, the two upper bounds |
| N3, a set stepped once | N3p | survived, argued above |
| N16, the connection recorded outside the open's section | N16p | caught, the escape row |
| F01, the settings outside the marking handler | C12 | caught, the F01 row |

N16's window is out of an engine's and a timer's reach, which is why the review's `n1-n16.sps`
found no leak. An engine spends no ticks inside a section, and none of the instructions between
the section's end and the `set!` is a procedure call. A keyboard interrupt that comes pending
inside the section is handled as the section ends, before the next expression (research,
`section-end.sps`). The escape row raises SIGINT from the suite's own callbacks, inside each
section in turn, and its handler leaves the call. Under N16p, the escape at the open leaves the
connection counted.

### The review's probes, rerun on the fixed libraries

- **`interleave.sps`, as written:** its fuel ranges are the reviewed libraries'. Case 1 starts at
  fuel 80 in steps of 7; cases 2 and 3 run 300 to 560; case 4 runs 125 to 145. All lie past
  where the fixed open completes, 221. So case 1 completed before finding, case 2 found none,
  case 3 none, case 4 nothing, the counts zero after each.
- **`interleave-fixed.sps`, a copy from fuel 1 in steps of 1, to 230 and to 30:**
  - case 1, R before the open and R1 after it: its first find is fuel 1, before the call's first
    expression: two whole calls, both connections returned and closed;
  - case 2, R1 holding a statement: at fuel 16, G 3, the second was refused with
    `&sqlite-closed`, and R1 answered the connection, nothing tracked;
  - case 3, a statement left at a row: 1448 trials, none;
  - case 4, R in the checks: fuels 1 to 7 made whole new calls; at fuels 8 to 15, finding 1's
    schedule, the second was refused, R1 answered, and nothing was left.
  The counts were zero after each case.
- **`n1-n16.sps`:**
  - N1 completes at fuel 116. Fuels 1 to 7 raise the mismatch twice, whole new calls; 8 to 90
    are refused; 91 to 115 raise the mismatch again, past the failure's close.
  - N16 completes at 87, no dropped remainder leaving a connection counted.
- **`f01.sps`:** the procedure starts at tick 155.

  | Ticks | Fixed | Reviewed |
  |---|---|---|
  | the close's refusal, before the extent, the procedure's jump leaving it | 1 to 18 | 1 to 177 |
  | `&sqlite-closed`, inside the extent | 19 to 130 | 178 to 360 |
  | the close's refusal, the procedure called again and returning | 131 to 154 | 361 to 381 |

  The reviewed libraries' first range held the refusals at the open's section, which now raise
  `&sqlite-closed`.
- **`mixed.sps`:** as before: a write refused read-only beside a list, and busy-timeout 77 read
  back beside `read-write`.

### Findings

- **`number->string`, resumed while an earlier resume is pending, answers the digits twice.**
  Part A's trap, resumed in sequence, answered `""`; interleaved, the second run answered
  `"12341234"` (`number-interleaved.sps`). A run that overtakes the first reaches the open first,
  so the open's claim cannot refuse what it computed. Code that builds SQL from Chez's own
  procedures runs in a critical section.
- **A collect request costs a run ticks,** up to two in a trial here (`gc-ticks.sps`). A row
  that judges one run by another at the same fuel collects first, with `collect-trip-bytes`
  raised above what the runs allocate, or judges each run by its own observation. Part A's 521
  and 18 against the review's 520 and 19 may be this.
- **A keyboard interrupt that comes pending inside a critical section is handled as the section
  ends,** before the next expression; a timer and an engine spend no ticks there
  (`section-end.sps`). The instructions just after a section are reachable by a signal's
  interrupt alone.
- **`call-with-open-handle`'s window between its `finished` flag and its wind's exit is
  reachable.** Its comment says M1's closing review found no engine reaching it over fuel 1 to
  3000. A remainder resumed at a fuel of 1 to 3 reached it: `test-open-interleave`'s procedure
  calls it, and at fuel 89, G 1 to 3, the resume answered `re-entered`. The comment, in M1's
  part of `(chez-sqlite3 private connection)`, is left for the lead.
- **`sqlite3_cancel_auto_extension` keeps SQLite's list of entry points,** 8 bytes the memory
  check finds; `sqlite3_reset_auto_extension` frees it.

## Part D: the conveniences' claim

The M2 session, sweeping slice 4, found slice 5's open-verb hole in slice 3's conveniences, and the
lead reproduced it (`build/verify-d/pending-sweep.sps`). The schedule: at fuel F a fresh engine's
remainder R; R resumed at G until it expires again, as R1; R resumed again to its end, then R1.
`execute!`, `query` and `query-row` left a statement tracked outside the cache in 1,361, 3,655 and
1,849 trials, 1,935 and 602 of them at a row. **The maintainer's decision, 2026-11-16:** fix it in
slice 5's PR, as part D, applying slice 5's claim to the conveniences. An Opus agent built it from
the lead's brief, in the slice's worktree. Its probes are in the worktree's git-ignored
`build/d-probe/`, its mutants and driver in `build/mut/d/`.

- **The mechanism, confirmed** (`mechanism.sps`). At fuel 10, R lay before the check-out. R
  resumed at G 46 to 51 prepared S1 and expired holding it, as R1. R's run found S1 out of the
  cache, prepared S2, gave it back and set the flag. R1 was refused at its next section, still
  holding S1.
- **Wrong answers too, which the lead's probe did not read** (`answers.sps`). Two runs both past
  the check-out share the statement, and the flag passes both until it is given back. So R stepped
  past rows R1 had read: `query` answered `(#(2) #(3))` in 901 trials, `query-row` `#(2)` in 55.
  And where both runs prepared, `execute!` inserted its row twice: 156 trials of the new suite.

### The shape: a claim on every section

**Every section claims its position, not only the check-out's and a miss's prepare's.** With slice
3's flag kept for the sections the runs share, two runs both past the check-out would each pass
every step and read, as the wrong answers above did. Only a position each run carries tells them
apart.

As built, in `(chez-sqlite3 private conveniences)`, for `execute!`, `query` and `query-row`:

- **The claim** is the call's first expression, `(let ((claim (made-claim))) ...)`: the position
  of the next section any run of the call may make, 0 at first, `#f` once the call has ended.
- **Each run's position** is an argument, never assigned, so a continuation holds it as it was.
- **Each section** claims its position in `in-section`, inside one critical section, and answers
  data: the work's answers, or its raise, with the run's next position. In order:
  - 0: the check-out and a miss's prepare, in one section, `checked-out` taking no check of its
    own; the statement noted there by its on-made;
  - each bind, the count's and each value's, by `bind-each!/at` through the claim's sectioner,
    one value a section as before (Q15);
  - each step; at a row, the column count's read and each column's;
  - the return, by `returned`, which ends the claim.
- **A run the call has passed is refused** at its next section: the section touches nothing, and
  the run raises `&sqlite-closed` from the verb, making no section after ("Guard every call").
- **A raise in a section** gives the statement back at the run's next position, its failure
  dropped, and is raised again. A give-back that is refused raises `&sqlite-closed`.
- **A raise no section caught,** a timer's or a keyboard handler's between two sections, gives the
  statement back by a claim of whatever position is next, unless the call has ended, then is
  raised again. Whichever run held the statement is refused at its next section.

**`query-fold` and `execute-script!` keep slice 3's flag,** and their code is unchanged. An
expiry inside the fold's wind finishes its statement and sets its flag, and one inside the
script's block frees the block, so neither survives a preemption, and no second run reaches a
statement another holds. Their sweeps hold. `bind-each!/who`, the fold's, is now
`bind-each!/at`'s work with `while-held` sections, its behaviour as it was.

**What it costs:** the check-out's checks now run inside its claimed section, and every section
spends no ticks, so the three's fuels fell by about half. The fold's rose a little, its binds
now going through `bind-each!/at`.

| Row, on 3.53.1 and 3.45.1 alike | Before | After |
|---|---|---|
| engines: `execute!`, `query`, `query-row` complete unexpired at fuel | 84, 156, 104 | 43, 82, 47 |
| engines: `query-fold`, and abandoned | 113, 113 | 117, 117 |
| engines: an abandoned `query` completes in one slice at fuel | 119 | 60 |
| engines: `execute-script!`; the two engines | 640; 259 | 640; 126 |
| resumed: `query`, `query-row`, `execute!`, cold and warm | 148/141, 106/99, 112/105 | 72/72, 46/46, 51/51 |
| resumed: a failed return; `query-fold`; the script | 156; 135; 638 | 78; 150; 638 |
| statement-who: `bind-each!/who` completes unexpired at fuel | 111 | 151 |

ADR-0016's P6 table cites the engines' fuels from before.

### The files and signatures

- **`src/chez-sqlite3/private/conveniences.sls`:**
  - new, internal:
    - `made-claim : -> Claim`, where `Claim = (U Natural #f) Boolean -> Boolean`;
    - `in-section : Claim (U Natural #f) Boolean (-> A ...) -> Section`;
    - `sectioner : Claim -> Sectioner`;
    - `and-then : Run (Natural Any -> Run) -> Run`;
    - `step-at : Symbol Statement Claim Natural -> Section`;
    - `row-at : Symbol Statement Claim Natural -> Run`;
  - changed: `with-checked-out : Symbol Claim Any Any (Statement Natural -> Run) -> A`;
  - gone: `given-back`;
  - unchanged: the six exports' signatures, `query-fold`, `execute-script!`, and the fold's
    `row-of` and `stepped`.
- **`src/chez-sqlite3/private/statement-values.sls`:**
  - new, exported: `bind-each!/at : Symbol Statement (Listof Value) Sectioner Natural -> Run`;
  - new, internal: `held-sectioner : Symbol (U (-> Any) #f) -> Sectioner`, and
    `finished-at : Symbol Natural Outcome -> Run`;
  - the types: `Section = (U (List 'answered Natural A ...) (List 'raised Natural Any)
    (List 'refused))`, `Sectioner = Natural (-> A ...) -> Section`, `Run = (U (List 'done Natural
    Any) (List 'raised Natural Any) (List 'refused))`;
  - `bind-each!/who`'s signature is as it was.
- **`src/chez-sqlite3/private/statement.sls`:** unchanged. `checked-out`'s check stays for the
  fold and for slice 4's `with-transaction`, which passes one.
- **The suites:** `tests/conveniences-pending.sls`, a new test library, and six suites,
  `test-conveniences-pending-execute`, `-query`, `-query-row`, `-fold`, `-script-odd` and
  `-script-even`; `test-statement-values`' export row grows by `bind-each!/at`.
- **`docs/reference.md`:** the conveniences' re-entry paragraph says what the claim holds, and the
  raise paragraph names a handler's raise.

### The suites

**The schedule** is the lead's, each trial on a fresh `:memory:` connection holding t's three
rows, made by one statement through the statement tier, so the cache starts empty. F runs from 1
until the call completes unexpired; G from 1 until R completes within G, where R is resumed once
more instead. After every trial:

- each run answers the call's answer, or `&sqlite-closed` from the verb; the fold and the script
  also a library wind's refusal of a re-entry;
- the call made its statement once, by the authorizer's count; the script each statement at most
  once;
- its effect came once: `execute!`'s row, the script's rows a prefix of its own;
- no statement is tracked outside the cache, none at a row, and the cache holds what one clean
  call leaves, its bindings cleared;
- once the connection is closed, every count is what it was.

**The tell:** `sqlite3_auto_extension` sets an authorizer on every connection, which notes each
select and insert prepared. SQLite never calls it at a cache's check-out.

**The control,** at each fuel: R taken on a connection whose cache holds none, resumed to its end
twice. The second makes a whole new call when the authorizer sees the SQL prepared again. A trial
may make one where the control did, at its fuel or the one before. Each fuel begins with a
collection, as slice 5's sweeps do.

**The control's bound:** it cannot tell a whole new call from the same call run again, which a
call that lost its claim or its flag does. So every whole new call must come below the fuel at
which the same call, refused at its first check, completes: that check follows the claim or the
flag (slice 3's script row).

**The guard against a trivial sweep:**
- a trial is past the first section when the call had made its first section by R1's capture;
- both past it when it had by R's capture;
- each sweep makes at least three of each a fuel on average, over the fuels up to the one at
  which it completes. The lead's first sweep, which reused one R across every G, made at most one
  a fuel. An average, as the M2 session noted: a collapse over a stretch of fuels can pass it.
- The script makes none both past it: every section of the script lies inside its block, and an
  expiry there frees the block.

**More schedules,** for what a raise from the caller's handler does:
- **a timer handler that raises,** at every tick, for all five: the statement finished each time;
- **one that first takes a statement for the call's SQL** and steps it, for `query` and
  `query-row`: the call's give-back leaves it alone;
- **a keyboard interrupt pending inside a section,** for `query-row`. SIGINT is raised from the
  authorizer, inside the check-out's prepare, and from SQLite's profile trace, inside the return's
  reset. No tick falls between a section's end and the code just after it, so only such an
  interrupt reaches there;
- **a `query` whose second step fails,** swept: the failure is raised by one run, and again by each
  run taken past the call's give-back; every other run is refused.

**The script's sweep is split by the parity of R's fuel.** It makes about 52,000 trials, 225 s
under the gate in one suite. Each half runs every G at its own fuels, and G = 1 alone at the
other's, which tells where the call completes. Bounding it by gaps between sections was tried and
dropped (Findings): slices don't compose.

### The red runs

Each new row ran first against the libraries before part D, in a copy, `build/mut/d/red`, holding
`3ae146d`'s `src/` and the new suites.

| Suite | Red | Green |
|---|---|---|
| `test-conveniences-pending-execute` | 6 passed, 2 failed: the sweep, the timer | 8 passed |
| `test-conveniences-pending-query` | 7 passed, 4 failed: both sweeps, the timer, the taken | 11 passed |
| `test-conveniences-pending-query-row` | 7 passed, 4 failed: the sweep, the timer, the taken, the check-out's keyboard | 11 passed |
| `test-conveniences-pending-fold` | 8 passed | 8 passed |
| `test-conveniences-pending-script-odd` | 8 passed | 8 passed |
| `test-conveniences-pending-script-even` | 7 passed | 7 passed |
| `test-statement-values`, its export row | 46 passed, 1 failed | 47 passed |

What the libraries before part D failed:

| Sweep | Fuel | Trials | Deviating | By kind |
|---|---|---|---|---|
| `execute!` | 90 | 3,910 | 1,717 | left 1,360; prepares 1,326; answer 357; rows 156 |
| `query` | 144 | 10,147 | 6,973 | left 3,655; prepares 3,570; answer 3,318 |
| `query`, failing | 188 | 17,361 | 7,192 | left 5,087; prepares 4,650; failures 2,381; answer 1,749; bindings 375 |
| `query-row` | 102 | 5,044 | 2,546 | left 1,849; prepares 1,806; answer 697 |

- **The timer rows failed at 7 ticks each** of the three: a raise just past the check-out's
  section left the statement out of the cache. Slice 3's `with-checked-out` bound the statement
  outside its guard, so nothing gave it back: a second hole the brief did not name.
- **The fold's and the script's rows pass there,** as the lead found, and are watched failing by
  their mutants (below). The keyboard row at the return passes there too: slice 3's give-back
  raised outside its guard. M02 and M12 fail it.

Green:
- **`make test`:** ran 64, passed 64, against the baseline's 58 of 58, the six suites added.
- **At the floor, 3.45.1,** through `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH`: the library
  loaded 3.45.1, and the six suites and slice 3's six convenience suites, `test-statement-values`
  and `test-statement-who` passed at the same counts. Every fuel printed matched 3.53.1's.

### The sweeps

| Sweep, on 3.53.1 and 3.45.1 alike | Completes unexpired at fuel | Trials with R1 | Past the first section | Both past it | Last whole new call, refused call |
|---|---|---|---|---|---|
| `execute!` | 42 | 820 | 715 | 325 | 8, 72 |
| `query` | 72 | 2,485 | 2,380 | 1,540 | 8, 72 |
| `query`, its second step failing | 84 | 3,403 | 3,298 | 2,278 | 8, 72 |
| `query-row` | 46 | 990 | 885 | 435 | 8, 72 |
| `query-fold` | 154 | 11,834 | 9,760 | 4,040 | 8, 94 |
| `execute-script!`, odd fuels | 431 | 25,817 | 8,568 | 0 | 8, 75 |
| `execute-script!`, even fuels | 431 | 25,460 | 8,449 | 0 | 8, 75 |

The timer rows complete before the handler runs at tick 36, 66, 40, 148 and 425, the handler
raising at every tick before. The taken rows are `query`'s and `query-row`'s, at the same ticks.

### Time

Each suite plainly and under `make test-memory`, on both libraries, in the container. Each
passed under the gate with no error and nothing lost, none `SLOW`.

| Suite | Plain, 3.53.1 | Plain, 3.45.1 | Gate, 3.53.1 | Gate, 3.45.1 |
|---|---|---|---|---|
| `test-conveniences-pending-execute` | 0.4 s | 0.4 s | 14 s | 14 s |
| `test-conveniences-pending-query` | 0.8 s | 0.8 s | 36 s | 33 s |
| `test-conveniences-pending-query-row` | 0.4 s | 0.4 s | 14 s | 14 s |
| `test-conveniences-pending-fold` | 1.3 s | 1.2 s | 54 s | 52 s |
| `test-conveniences-pending-script-odd` | 2.7 s | 2.4 s | 112 s | 105 s |
| `test-conveniences-pending-script-even` | 2.5 s | 2.3 s | 110 s | 102 s |
| `test-conveniences` | 0.3 s | 0.3 s | 10 s | 11 s |
| `test-conveniences-who` | 0.4 s | 0.4 s | 13 s | 12 s |
| `test-conveniences-reentry` | 0.3 s | 0.3 s | 10 s | 10 s |
| `test-conveniences-engines` | 0.3 s | 0.3 s | 11 s | 12 s |
| `test-conveniences-resumed` | 0.6 s | 0.6 s | 18 s | 18 s |
| `test-conveniences-counters` | 0.3 s | 0.3 s | 11 s | 11 s |
| `test-statement-values` | 0.5 s | 0.4 s | 12 s | 13 s |
| `test-statement-who` | 0.5 s | 0.5 s | 12 s | 12 s |

The script's halves, the largest, take a quarter of the 450 s threshold here.
`test-library-loading` took 230 s here and 308 s on CI (ADR-0005, amended), so on a slow runner
each half may take about 220 s.

### The mutations

Every mutation ran in one of three copies under `build/mut/d/`, `m1` to `m3`, made without `.git` or
`build/`, after `make deps` in each, through each copy's own `scripts/guix-env`. The driver,
`build/mut/d/drive.py`, its definitions `define.py`, works as slice 5's part C's does: it syncs
the worktree's `src/`, `tests/` and `docs/` into the copy, checks that each old text occurs once,
writes the mutant, runs fifteen suites each under `timeout 300`, reads their counts from their own
output, and puts the file back. The suites: the six new ones (P-), slice 3's six convenience
suites (C-), `test-statement-who`, `test-statement-values` and `test-connection-cache`.

**33 mutations, 29 caught, 4 survived,** on the final libraries and suites, run once.
`coverage.py` reads every new row against the red runs, the mutants and the plants: each failed
under at least one.

#### The claim and its sites (`conveniences.sls`)

| Mutation | What it plants | Failed |
|---|---|---|
| M01 | the claim never refuses a stale position | P-execute, P-query 2, P-query-row |
| M02 | the claim never ends: a claim of whatever is next still claims after the return | P-query-row: the return's keyboard row |
| M03 | the claim compares with `<=` | **survived** |
| M04 | the claim made in a section of its own, the work outside it | P 9 rows, C-who, C-resumed 4 |
| M05 | the check-out's section claimed, never refusing | P 4 rows, C-resumed 4 |
| M06 | each bind's section claimed, never refusing | P-execute, P-query, P-query-row: the bindings |
| M07 | each step's section claimed, never refusing | P 4 rows, C-resumed 3 |
| M08 | the column count's section claimed, never refusing | **survived** |
| M09 | each column's section claimed, never refusing | P-query, C-resumed 2 |
| M10 | the return's section claimed, never refusing | P-query, C-who, C-resumed 4 |
| M11 | a raise no section caught gives nothing back | P 6 rows: the timer, taken and check-out keyboard rows |
| M12 | that give-back made by no claim, even once the call has ended | P-query-row: the return's keyboard row |
| M13 | the statement noted after the check-out's section, not inside it | P-query-row: the check-out's keyboard row |
| M14 | a section's raise gives the run its own position, not the next | P-query 2, C 6, C-who 4, C-reentry, C-counters |
| M15 | a refused give-back after a raise raises the work's condition | P-query: the failing sweep |
| M16 | the claim made after the SQL's checks, not first | **survived** |
| M17 | the check-out claimed in an empty section, `checked-out` run after it | P 4 rows, C-resumed 4 |

#### `bind-each!/at` (`statement-values.sls`)

| Mutation | What it plants | Failed |
|---|---|---|
| M20 | the count read outside its claimed section, an empty section claimed in its place | P 4 rows, C-resumed |
| M21 | each value bound outside its claimed section, the same | P 4 rows, C-resumed |
| M22 | a refusal of the count or a value gives the count's own position | C 2, C-who 3 |
| M23 | each value claims the count's next position | P 17 rows, C 9, C-who 5, C-engines 5, C-resumed 3, C-reentry |
| M24 | `held-sectioner` ignores the fold's flag | C-resumed, statement-who |

#### The flag's sites kept (`query-fold`'s, `execute-script!`'s)

| Mutation | What it plants | Failed |
|---|---|---|
| F01 | the fold's check-out reads no flag | P-fold, C-resumed 2 |
| F02 | the fold's binds read no flag | C-resumed |
| F03 | the fold's steps read no flag | C-resumed |
| F04 | the fold's column count and reads read no flag | C-resumed |
| F05 | the fold reads no flag after its procedure | **survived** |
| F06 | the fold's finish acts on every exit, its flag not read | C-reentry, C-resumed |
| F07 | the fold's finish never sets its flag | P-fold, C-who, C-reentry 2, C-resumed |
| F08 | the script's first prepare never marks the run begun | P-script-odd, P-script-even, C-who, C-resumed |
| F09 | the script's first prepare takes no check | P-script-odd, P-script-even, C-who, C-resumed |
| F10 | the fold's finish gives back on a normal exit, nothing on another | P-fold 2, C 2, C-who, C-reentry 5, C-engines 2, C-resumed |
| F11 | a script statement's wind finalizes nothing | P-script-odd 2, P-script-even, C-engines, C-resumed |

F11 was first written with a parenthesis too many, and every suite died at the read; it was
fixed and run again.

#### The plants of the shared rows (`build/mut/d/plants.py`)

Each written into a copy's `tests/conveniences-pending.sls`, or its environment; the six suites
run.

| Plant | What it plants | Failed |
|---|---|---|
| Q1 | `CHEZ_SQLITE3_LIBRARY` names no file | every row but the load's counts, in each suite |
| Q2 | the library leaks a connection when it loads | both counts rows, and every row judging counts |
| Q3 | the authorizer's action codes wrong: nothing noted | the tells, and every sweep |
| Q4 | `tell-reset` resets nothing | the unregistering row, in each suite |
| Q5 | the entry point never registered | the tells, and every sweep |

### The mutants that proved the suites short

The first pass, on the suites before their last rows, left M02, M06, M12, M13 and M15 surviving,
and F08 and F09 caught only by slice 3's suites. Each was argued, the argument tried against a
schedule, and the schedule kept as a row where it killed:

- **M02 and M12, the claim's end.** No tick falls between the return's section and the guard's
  exit, so no timer handler gets there. A keyboard interrupt that comes pending inside the return
  does (`keyboard.sps`): under both, the statement the handler took back from the cache was reset
  and filed while it held it. Kept: the return's keyboard row.
- **M13, the statement noted after the check-out's section.** The same window, after the
  check-out: SIGINT raised from the authorizer inside the miss's prepare. Kept: the check-out's
  keyboard row.
- **M06, a stale bind never refused.** A run before the binds, resumed once its twin had ended the
  call, bound the statement the cache then held: the judge never read the cached statement's
  bindings. Kept: the judge steps it unbound.
- **M15, a refused give-back's raise.** No sweep had a failing call. Kept: the failing `query`.
- **F08 and F09, the script run twice.** The control took a second resume of the same call,
  running the script again, for a whole new call. Kept: the refused call's bound.
- **F10 and F11** were added: no mutant reached the fold's or the script's timer row.

### The survivors

- **M03, `<=` for `eqv?` in the claim, is equivalent,** as slice 5's C05. A run's position never
  passes the call's: positions advance only by a claim, which sets the call's to the claiming
  run's next. Tried against every sweep: no deviation.
- **M08, the column count's read never refused, is equivalent,** as slice 3's D06. The count is
  read by `sqlite3_column_count` alone, which changes nothing, and the accessor allows it in every
  live state. A stale run's read is followed by its first column's section, which refuses it; and
  where the stale run and its twin stand at the same count, whichever claims the next section goes
  on from the same state. Tried against every sweep: no deviation.
- **M16, the claim made after the SQL's checks,** changes nothing a row can see, as slice 5's C08.
  A remainder taken in the checks makes a whole new call, which the control measures and the trial
  allows. Under it, `query`'s last whole new call moved from fuel 8 to 43, and the failing
  `query`'s to 76, below the refused call's bound. A reference call of the same shape, its first
  expression marking it, was tried as a tighter bound, and failed the fixed libraries by two ticks
  (`boundary.sps`, Findings). The docs' "a continuation taken before the call began makes a new
  call" would take in one taken inside the checks; no row holds the claim's place.
- **F05, the fold's read after its procedure,** is slice 3's survivor, argued there: the next
  step's section reads the flag first. Tried against the fold's sweep: no deviation.

### The lead's probe, rerun on the fixed libraries

| Call | Trials | Flagged before | Flagged after |
|---|---|---|---|
| `execute!` | 820 | 1,361 of 3,911 | 0 |
| `query` | 2,487 | 3,655 of 10,147 | 0 |
| `query-row` | 991 | 1,849 of 5,044 | 0 |
| `query-fold` | 703 | 0 | 0 |
| `execute-script!` | 52,432 | 0 | 0 |

The counts were zero after. `answers.sps`, its copy that reads each run's answer, found no
wrong answer. The fold's row sweeps nothing: the lead's probe passed the fold its seed for its
procedure, so every trial raised at the procedure's check (the lead's checks, below).

### Findings

- **Slices don't compose** (`ticks.sps`). Stepped one tick a slice, the script completed in 123
  slices; in one slice it takes 433. An engine's fuel counts ticks within a slice only, so trial
  (F, G) is not (F − 1, G + 1), and no map of positions by tick can bound a sweep.
- **Where a remainder lies depends on the code after its point** (`boundary.sps`). One first
  expression, followed by different code, put the whole-new-call boundary at fuel 6 or 7;
  `execute!`'s is at 8. No reference call places a first expression to the tick.
- **No tick falls between a section's end and the code just after it,** confirming slice 5's
  `section-end.sps`. A timer handler never reaches the give-back's or the check-out's last
  instructions; only a keyboard interrupt that came pending inside the section does.
- **A control that reads effects cannot tell a whole new call from the same call run again.**
  Bound it by a fuel past the first expression, the refused call's.
- **Slice 3's `with-checked-out` lost its statement after a raise just past the check-out,** at 7
  ticks of each of the three, its statement bound outside its guard.
- **`query-fold`'s flag is made after its procedure's check,** not by its first expression. No
  row tells: its last whole new call is at fuel 8, as the others'.
- **The six suites add about 340 s, under six minutes, to the memory job** here, most of it
  the script's halves.

### The lead's checks

Run by the lead on part D's hand-back, in the worktree and in copies under its git-ignored
`build/lead-mut/`.

- **`make test`:** ran 64, passed 64.
- **The gate and the floor:** the six suites passed under `make test-memory` on both libraries,
  none slow, and the fourteen, with slice 3's convenience suites, `test-statement-values` and
  `test-statement-who`, passed plain at the floor.
- **The lead's probe, corrected,** now [research/m3-slice-5/](research/m3-slice-5/README.md)'s
  `pending-sweep.sps`: the fold given its procedure, and each fuel begun with a collection, so its
  counts are the same from run to run and on both libraries. Before part D, `execute!` 1,360 of
  3,910, `query` 3,655 of 10,147, `query-row` 1,849 of 5,044, `query-fold` 0 of 6,331 and
  `execute-script!` 0 of 52,430. After, none of 820, 2,485, 990, 6,874 and 52,430.
- **A warm cache,** which no suite sweeps, since the authorizer sees no check-out
  (`pending-sweep-warm.sps`): each connection runs the call once first, so R's check-out is a
  hit. `execute!`, `query` and `query-row` hold in all 820, 2,485 and 990 trials. The fold's
  7,340 flags are its finish on an expiry inside its wind, which costs the cache its statement;
  none leaves one outside the cache or at a row.
- **`answers.sps` on the libraries before part D:** `query` answered `(#(2) #(3))` and
  `query-row` `#(2)`, 900 and 55 trials.
- **Traps reproduced:** `ticks.sps` and `boundary.sps`, as reported; and slice 3's second hole,
  the execute suite's timer row on the libraries before part D, its insert left tracked and
  ready, out of an empty cache, at ticks 50 to 52.
- **Slice 4's pending row, after the rebase onto slice 4's `5c295c1`:**
  - **Its guard failed:** it wanted at least 1,000 trials. Part D made the call cheaper, so it
    completes at fuel 58, and every fourth G made 647 trials a level.
  - **The row now sweeps every G:** 2,504 trials a level, 49 s under the gate, against slice 4's
    46 s at every fourth.
  - **It fails by name below ten trials a fuel on average.**
  - **It asserts what slice 4 could only observe:** no statement, the body's included, is tracked
    outside the cache. On slice 4's libraries it fails at F 29 from G 46, in 960 of 8,210 trials
    at the outer level and 959 nested. The lead's probe of the same schedule
    (`build/lead-probe/tx-pending.sps`) agrees: 960 trials with a stray before part D, none after.
- **The lead's mutants,** each run against the fifteen suites (`build/lead-mut/drive-d.py`):

  | Mutation | What it plants | Failed |
  |---|---|---|
  | L5 | a refused run, holding no statement, raises `&sqlite-closed` over its own raise | C-who 3 |
  | L10 | a bind failing after its section answers the section, not its raise | P timer rows 4, P taken 2, C-who 4, statement-who |
  | L16 | `execute!`'s refused run answers as the call does, raising nothing | C-who, C-resumed |
  | L20 | a raise no section caught replaced by `&sqlite-closed` | P timer rows 3, P taken 2, P-query-row's keyboard rows 2 |
  | L21 | the return's own failure, after the work, dropped | C, C-who 2, C-resumed |

  All five caught. L10 failed more than predicted: a timer's raise during a bind's finish, outside
  any section, reaches `finished-at`'s guard. L16 passes the new suites, whose judge takes the
  call's answer or `&sqlite-closed` from any run; slice 3's resumed rows hold it.
