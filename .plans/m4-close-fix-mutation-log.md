# The close fix: the mutation log

Evidence that the fix to `close-database!`, and each row that holds it, fails through the property
it names. Format of [the M3 slice 6 log](m3-slice-6-mutation-log.md). An Opus agent built it from
the lead's brief, in the worktree of branch `m4-close-fix`, on `main` at `87e762c`, then answered
the fix's read-only Opus review and the maintainer's two decisions on it. Its probes and their
driver, [run-probes.sh](research/m4-close-fix/run-probes.sh), are in research/m4-close-fix/, their
output in [output.txt](research/m4-close-fix/output.txt) and
[stmt-busy.txt](research/m4-close-fix/stmt-busy.txt), and the plants' runs in
[plants.txt](research/m4-close-fix/plants.txt). The review's probes named below,
`autocommit-returning.sps`, `backup-txn.sps`, `savepoint-flush.sps`, `reuse-after-refusal.sps` and
`refusal-site.sps`, are the reviewer's, in the worktree's git-ignored `build/review-mut/probes/`, and
not in the repository unless the lead keeps them; the builder reran each there.

## The defect

A connection that has made or used an FTS5 table can't be closed: `close-database!` raises an
assertion violation, `(untracked-statements N)`, and leaves the connection open and counted.

- **The cause.** A virtual table's module prepares statements of its own on the connection, for its
  shadow tables, and finalizes them only when its table is disconnected. `sqlite3Close` disconnects
  every virtual table, and calls `sqlite3VtabRollback`, before its busy check: "the v-table
  implementation may be storing some prepared statements internally". `close-connection` counted
  `sqlite3_next_stmt`'s statements before it called `sqlite3_close`, so it found the module's.
- **Which modules,** measured by [vtab-close.sps](research/m4-close-fix/vtab-close.sps) on the old
  order, each count the close's irritant:

  | Module | Made only | Written and searched | A file's table, made and written |
  |---|---|---|---|
  | FTS5, 3.53.1 and 3.54.1 | 2 | 7 | 6 |
  | FTS5, 3.45.1 | 3 | 7 | 6 |
  | FTS4, 3.45.1 and 3.53.1 | closes | 10 | 9 |
  | FTS3, 3.45.1 and 3.53.1 | closes | 7 | 6 |
  | RTREE, 3.45.1 | 8 | 8 | 8 |

  FTS3 and FTS4 prepare theirs as they are first used, FTS5 and RTREE theirs as the table is
  connected.
- **Two libraries were built for this fix,** git-ignored, by CI's compile line with
  `-DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE` added, the
  four modules Ubuntu's 3.45.1 lists (the census): `build/m4cf-floor-vtab`, the floor's 3.45.1, and
  `build/m4cf-current-vtab`, the current 3.54.1. Each `sqlite3.c` has its role's source pin as its
  SHA3-256. RTREE is in neither Guix's library nor `build/m4-current-fts5`.

## The fix, and the boundary

The maintainer's "Close first, count on failure", 2026-11-17. `close-connection` keeps its first
steps, the tracked statements finalized and the cache emptied, then calls `sqlite3_close`:

- **`SQLITE_OK`:** the close's outcomes as before: closed, the first finalize failure (R1), or the
  double free.
- **Any other answer:** the connection left open and counted, and only then `sqlite3_next_stmt`
  counts what is left on it: one or more, the same assertion violation, `untracked-statements N`;
  none, `sqlite3_close`'s own `&sqlite-error`, as before.

After the review, the maintainer's "Vouch only for ours", 2026-11-17, set the boundary: the close
finalizes what chez-sqlite3 tracks, calls `sqlite3_close` and reports its answer, and never judges a
statement it didn't make. A refused close means something other than the library left a statement,
a blob or a backup open on the connection, a chez-sqlite3 bug or foreign code such as a loaded
extension; that work, and what SQLite's close does to it, is theirs. After a refusal the count is a
diagnostic, every statement left, a module's pinned ones among them. The library's own leaks are
caught by the counters, Valgrind and the memory gate. So there is no busy check: the code is the
fix as first built.

`close-left-open?` is unchanged: both outcomes still come from the work as `untracked` and
`failed`, so the latch is set again after either. `connection.sls`'s header and `close-connection`'s
and `close-left-open?`'s comments say the order and the boundary. `docs/reference.md`'s
`close-database!` entry gains two paragraphs, below. No other caller changed: `close-database!`,
`open.sls`'s close after a failed setting, and `call-with-database`'s close all reach
`close-connection`.

## No busy rule

The review's major: an untracked `insert … returning` into an FTS5 table, stepped once in
autocommit, has its index's pending terms dropped by `sqlite3_close`'s rollback, and its finalize
then commits the row without them. The first proposal refused a close while any statement left was
`sqlite3_stmt_busy`. [stmt-busy.sps](research/m4-close-fix/stmt-busy.sps), whose probe is a tracked
entry of its own that the close finalizes last, read every statement left at the point the close
calls `sqlite3_close`, on all five FTS or RTREE libraries
([stmt-busy.txt](research/m4-close-fix/stmt-busy.txt)). Nothing chez-sqlite3 made was busy. But
RTREE, on 3.45.1 and 3.54.1, keeps a busy statement of its own, with no SQL, whenever its table has
been written in a transaction still open, and FTS5 does the same at 3.45.1; FTS3, FTS4, and FTS5 at
3.53.1 and 3.54.1 don't. [blob-busy.sps](research/m4-close-fix/blob-busy.sps) shows that shape is a
`sqlite3_blob`'s: SQL NULL, busy. A busy rule would have refused those closes, the defect this fix
removes. They are why no busy rule was taken, and why the maintainer chose the boundary over another
heuristic.

## What the fix adds

- **`src/chez-sqlite3/private/connection.sls`:** the order, and its comments.
- **`docs/reference.md`:** under `close-database!`, what a refused close means, and what SQLite has
  then done: full-text tables' unsaved changes thrown away, plain and RTREE tables' kept; roll
  back, never commit; and the full-text table's own rebuild command, measured below.
- **`tests/test-connection-close.sps`, new,** in `MEMORY_SUITES_1`, between `test-ci-sqlite` and
  `test-constants`: 22 rows on Guix's library.
  - **the modules:** a row holds each module's compile option to `pragma_module_list`: fts5 by
    `ENABLE_FTS5`, fts4 by `ENABLE_FTS3`, rtree by `ENABLE_RTREE`. A module's rows run where both say
    yes; where both say no, the suite prints the module unavailable and asserts the refusal in each
    row's place: the create prepares, so its SQL is well formed, its step raises `&sqlite-error`,
    code `error`, and no table `v` is in the schema. fts4 is chosen by `ENABLE_FTS3`, not
    `ENABLE_FTS4`: the amalgamation defines `SQLITE_ENABLE_FTS3` from `SQLITE_ENABLE_FTS4` before
    its option list, and the FTS3 code registers both `fts3` and `fts4`. Homebrew's 3.54.1 lists
    `ENABLE_FTS3` and no `ENABLE_FTS4` (the census), so a row chosen by `ENABLE_FTS4` would call its
    library's options and modules disagreeing. That library's module list was read from the source,
    not run;
  - **closing:** for each module, a `:memory:` connection that made a table, and one that also
    wrote and searched it, close, every count back to 0; a file's table made, written and closed,
    reopened, searched and read, closes again, its rows kept. And `call-with-database` whose
    procedure makes, writes and searches an fts5 table gives its answer and closes;
  - **left open:** an untracked statement, with no module, raises `untracked-statements 1` after
    `sqlite3_close` answered busy: the connection's extended code, `error` from a failed prepare
    made first, reads `busy` after the refusal. The connection stays open and counted, the latch's
    probe reads `(clear void set)`, and once the statement is finalized a second close closes.
    Beside an fts5 table, the count is the raw statement's alone, 1. A backup, alone and beside an
    fts5 table: `&sqlite-error` busy and busy, its message the connection's own, `sqlite3_errmsg`
    read after the refusal, the extended code busy, the latch set again;
  - **a transaction:** the measured effect of a refused close on an open transaction, below, with
    fts5 and with a plain table alone; and, after a refusal a backup made, the fts5 table takes an
    insert and a `with-transaction` insert, each found by its search, the integrity check intact,
    and the file reopened finds all three rows, intact (the review's `reuse-after-refusal.sps`);
  - **the boundary:** rows that hold what SQLite does to work the close doesn't judge, as measured,
    so a change in SQLite shows. They document it, and don't endorse it. The review's untracked
    `insert … returning` into fts5, stepped once in autocommit: the close is refused after
    `sqlite3_close`, naming every statement left, as the suite counts them after it, fts5's among
    them; once finalized, the row commits without its index terms: read 1, searched 0, the
    integrity check `corrupt-vtab`. An untracked `select` held at its row, with no module (1 left)
    and over fts5 (fts5's among those left): refused the same way, and a second close closes once
    it is finalized.

## A refused close and an open transaction

[failed-close-txn.sps](research/m4-close-fix/failed-close-txn.sps): a file holding a plain table
`t` and a virtual table `v`; `BEGIN`; a row into each; a raw statement, so the close is refused;
then the close, by `sqlite3_close` called directly (`raw`, SQLite's behaviour whatever the
library's order) or by `close-database!` (`verb`); then the transaction ended. Measured in both
modes, the fix's `verb` the same as `raw`: FTS5 and the plain table alike on 3.53.1, 3.54.1 and
3.45.1; FTS3 and FTS4 on 3.53.1, 3.54.1 and 3.45.1; RTREE on the two built libraries:

| | `t` | `v`, read plainly | `v`, searched | Transaction | After `COMMIT`: integrity, both connections | After `ROLLBACK` |
|---|---|---|---|---|---|---|
| before the close | 1 | 1 | 1 | open | | |
| FTS5, after the refused close | 1 | 1 | **0** | open | `corrupt`, `corrupt-vtab`; `t` 1, `v` 1, searched 0 | all 0, intact |
| FTS4 and FTS3 | 1 | 1 | **0** | open | `corrupt`, `corrupt-vtab` | all 0, intact |
| RTREE | 1 | 1 | 1 | open | `rtreecheck` ok | all 0, ok |
| a plain table alone | 1 | | | open | `t` 1 | `t` 0 |

So `sqlite3_close`'s refusal leaves the pager's transaction open, and every plain write in it, but
`sqlite3VtabRollback` has called each written virtual table's `xRollback`. FTS3, FTS4 and FTS5 hold
a transaction's new terms in memory until they flush them, and their rollback discards what they
hadn't flushed: the content row stays, the index loses it, and a `COMMIT` then writes an index the
module's own integrity check calls corrupt, `SQLITE_CORRUPT_VTAB`, on this connection and on
another. What was flushed stays: the review's `savepoint-flush.sps`, a row, a `SAVEPOINT` and its
`RELEASE`, then a second row, read `plain 2 alpha 1 beta 0` after the refusal, and corrupt after the
commit. RTREE writes its shadow tables as it goes and loses nothing. A `ROLLBACK` after the refusal
leaves everything as it was before the transaction.

**The module's own rebuild mends it.** [rebuild.sps](research/m4-close-fix/rebuild.sps): an
ordinary FTS3, FTS4 or FTS5 table so committed reads 2 rows, finds 1, and is corrupt;
`insert into v(v) values ('rebuild')` then makes it find 2, intact, and a reopened connection the
same, on all four FTS libraries. Contentless and external-content tables were not tried.

**It is new with the fix.** The old order called `sqlite3_close` only when nothing was left to
count, and a transaction that has written an FTS table has left the module's statements, so the
old order refused that close before `sqlite3_close` ran, whatever else held the connection: the
review's `backup-txn.sps` on the old order read `search 1`, and intact after the commit. Now both
refusals, a backup's and an untracked statement's, roll the module back first. That is the boundary:
the work left open is the other party's, and the docs tell the caller to roll back.

## What the count counts

[untracked-vtab.sps](research/m4-close-fix/untracked-vtab.sps), on 3.53.1, 3.54.1 and 3.45.1: an
untracked statement of `select 1` beside an fts5 table is counted alone, 1. One that reads the fts5
table holds it connected, since a prepared statement keeps a lock on the virtual tables it uses,
so `sqlite3_close` can't disconnect it, and the module's statements are counted with it: 8 for
`select count(*) from v where v match 'hello'` prepared only, 9 for `select body from v` stepped
to its row. Each closed once the raw statement was finalized. So `untracked-statements N` counts
every statement `sqlite3_next_stmt` finds after the refused close, SQLite's own among them while
an untracked statement holds their table. The boundary rows assert N whole, as the count the suite
reads itself after the refusal, and that it exceeds the one raw statement beside fts5.

## `sqlite3_close` failing with nothing untracked

Reachable, but not through the public surface alone. `sqlite3Close` refuses a close only when
`connectionIsBusy`: a statement on the connection, or a backup reading from one of its databases,
whose source's count `sqlite3_backup_init` raises. A `sqlite3_blob` is a statement, so it is
counted. Once `sqlite3_close` has disconnected the virtual tables, a refusal with nothing to count
is a backup's. `SQLITE_MISUSE` needs a handle that isn't open, which the record never holds. The
library binds no backup or blob API, so a caller reaches it only through a backup bound in the same
process, as five suites do with their own `sqlite3_backup_init`, or C code given the connection (an
extension, through M4's `load-extension!`, was not tried). `test-connection`,
`test-connection-cache`, `test-interrupt-close`, `test-interrupt-database` and `test-statement`
hold it as before; the new suite holds it alone and beside an fts5 table.

## How the mutants ran

Every plant ran in a copy of the worktree of its own, `build/mut/NAME/`, made by
[plants.py](research/m4-close-fix/plants.py) with `tar --exclude=./build --exclude=./.git`, the
five libraries under `build/` copied in. A plant is a list of edits, each checked to match its
file's text exactly once before it is written. [run-plants.sh](research/m4-close-fix/run-plants.sh)
ran `make deps` in each copy, then each suite under `timeout 300`, through the worktree's
`scripts/guix-env`, from inside the copy: `guix-env` changes to its own root, so a command meant
for a copy must change into it inside the container. The counts are read from each suite's own
output, never by eye; none died or hung, the longest p04's `test-interrupt-close`, 108 s, whose
long step ran to its end with the latch shut.

Eleven suites: the new one, and every suite that reaches the untracked or failed path, the latch
after them, or the close's engines: `test-connection`, `test-connection-cache`,
`test-interrupt-close`, `test-interrupt-database`, `test-interrupt`, `test-open-settings`,
`test-open-engines`, `test-transaction-engine`, `test-statement` and `test-statement-who`.

**Which version ran.** The first round ran all eleven suites in every copy, with the new suite's
first version. The other ten suites haven't changed since, nor has `connection.sls`'s code, so
their counts below are that round's. The new suite changed three times after it: its backup rows,
the review's rows and the boundary, and comments. Before the last round, `plants.py --refresh` wrote
the worktree over every copy again and applied each copy's edits again, so all 21 copies ran the
final suite, whose md5 the lead can compare with the tree's; the `close` counts below are that
round's. An earlier round had run 14 copies on a version two edits older; it is superseded.

## The red runs

The suite was written first, and run against the code as it stood, `87e762c`'s
`connection.sls`, before the fix, and again in plant p01's copy, the old order, with the final
suite:

| Library | Red, the first 17 rows | Red, the final 22 | Green |
|---|---|---|---|
| Guix's 3.53.1 | 6 passed, 11 failed | 6 passed, 16 failed | 22 passed |
| `build/m4-current-fts5`, 3.54.1 | | 8 passed, 14 failed | 22 passed |
| `build/m4cf-floor-vtab`, 3.45.1 | | 4 passed, 18 failed | 22 passed |
| `build/m4cf-current-vtab`, 3.54.1 | | 4 passed, 18 failed | 22 passed |
| `build/m3-floor`, 3.45.1 | | 20 passed, 2 failed | 22 passed |
| `build/m4-current`, 3.54.1 | | 20 passed, 2 failed | 22 passed |

Each module's rows fail by the count the old order names, the untracked rows by their extended
code, `error` or the step's, where the fix reads `busy`, and the transaction and boundary rows by the
search, 1 where the fix reads 0. On a library without a module, its rows are its refusal rows, which
pass on either order, and the two untracked rows with no module tell the orders apart there. The
rows that pass red, and each one's plant:

- the load, the counts at the load, the temporary directory and the counts at the end: every
  suite's;
- the module agreement row: T1;
- each refusal row, on a library without the module: T2, which runs the refusal rows where the
  library has the module, so its create answers done; and T3, run on `build/m3-floor`, whose broken
  create fails at its prepare, where each refusal row asserts it prepares;
- the plain table's transaction row, on a library without FTS5: p02, p05, p06, p10 and p15 fail
  it by its own values;
- the backup row without a module: p04, p05, p06, p08, p09, p15 and p17 fail it by its own
  values, p17 by its message alone.

  On the FTS lanes p01 fails these two as well, by a connection an earlier row left open.

## The mutations

The new suite is `close` below; the other ten are named by their own words. Each row names the
suites that failed on Guix's 3.53.1, and how many rows of each; a plant counts as caught when one
row failed.

| Plant | What it plants | Failed |
|---|---|---|
| p01 | the old order, counting before `sqlite3_close` | close 16; no other suite |
| p02 | close first, never counting: every refusal `&sqlite-error` | close 7, connection 5, connection-cache 1, interrupt-close 1, interrupt-database 2, open-engines 1, statement 1 |
| p03 | counting on success too: `sqlite3_next_stmt` on the handle `sqlite3_close` freed, a count above 0 taken as untracked | **none plain**; under the gate, `close` fails: 238 errors from 7 contexts with the final suite (196 with the first), "Invalid read of size 8 at `sqlite3_next_stmt`", 32 bytes inside a freed block of 840, and reads in `pthread_mutex_lock` |
| p04 | the latch left shut on the busy path: neither refusal sets the flag again | close 4, interrupt-close 2, interrupt-database 4 |
| p05 | the handle cleared on a failed close | close 11, connection 37, connection-cache 3, interrupt-close 4, interrupt-database 10, open-engines 2, open-settings 4, statement 16 |
| p06 | the connection counted down on a failed close | close 10, connection 8, connection-cache 2, interrupt-close 2, interrupt-database 4, open-engines 1, open-settings 1, statement 2 |
| p07 | the latch shut after an untracked refusal only | close 2, interrupt-close 1, interrupt-database 3 |
| p08 | the latch shut after `sqlite3_close`'s own failure only | close 2, interrupt-close 1, interrupt-database 1 |
| p09 | every refusal named untracked, a count of 0 among them | close 3, connection 1, connection-cache 1, interrupt-close 1, interrupt-database 1, statement 1 |
| p10 | one statement left taken for none | close 5, connection 4, connection-cache 1, interrupt-close 1, interrupt-database 2, open-engines 1, statement 1 |
| p11 | counted before `sqlite3_close`, that count named after it fails | close 4; **survives on a library without FTS5** |
| p12 | the tracked statements finalized after `sqlite3_close` | close 19, connection-cache 8, interrupt-database 15, open-engines 6, open-settings 13, statement 27, statement-who 8, transaction-engine 1 |
| p13 | the cache left full | connection-cache 4 |
| p14 | `sqlite3_close` tried again on a refusal, before the count | **survived** |
| p15 | busy taken for success | close 10, connection 8, connection-cache 2, interrupt-close 2, interrupt-database 4, open-engines 1, open-settings 1, statement 2 |
| p16 | the failure's details read before the count | **survived** |
| p17 | the failure's details read with no handle, `sqlite3_errstr` of the answer | close 2, the two backup rows; no other suite |
| p18 | the count down dropped from a close that closed | close 19, connection 55, connection-cache 8, interrupt-close 4, interrupt-database 15, open-engines 6, open-settings 12, statement 35, statement-who 6, transaction-engine 1 |
| T1 | the suite: rtree's option read as `ENABLE_FTS5` | close 1, the agreement row |
| T2 | the suite: every module taken for unavailable | close 11, every refusal row of fts5 and fts4 |
| T3 | the suite: fts5's create a syntax error | close 9 on every library: on `build/m3-floor` and `build/m4-current`, every fts5 refusal row, by its prepare; where fts5 is, every fts5 row |

p01 to p06 are the brief's; p07 to p18 and T1 to T3 the builder's. `test-interrupt` failed no
plant: it holds the latch on stand-ins, not the record's close. The rows the review added fail
these plants: the reuse row p01, p05, p06, p09, p11, p12, p15, p18 and T3; the boundary's
`insert … returning` p01, p02, p05, p06, p12, p15, p18 and T3; its `select` with no module p01,
p02, p05, p06, p10, p12, p15 and p18, and over fts5 the same but p10, and T3.

**21 plants: 18 caught plain, p03 caught under the gate, two survived, both equivalent.**

- **p01 fails the new suite alone.** The ten older suites pass the old order: none makes a virtual
  table, and none read whether `sqlite3_close` ran before a refusal for an untracked statement.
- **p03 is a use after free that reads 0.** Plain, `sqlite3_next_stmt` on the freed connection
  never read above 0 in any close of the eleven suites, so none was refused, and nothing failed.
  Under `make test-memory MEMORY_SUITES=tests/test-connection-close.sps`, Valgrind reports its
  reads and the gate fails the suite, 12 s. CI's `memory-1` runs the suite.
- **p11 survives where no module keeps statements.** On `build/m3-floor` and `build/m4-current`,
  22 of 22 passed: with no virtual table, the count before `sqlite3_close` and the count after its
  refusal are the same statements. Where FTS5 is, four rows fail it on Guix's library, among them
  the untracked statement beside a written and searched fts5 table, `untracked-statements 8` where
  the fix names 1, and the backup beside one, `untracked-statements 7` where the fix raises busy;
  five on `build/m4cf-floor-vtab`, where the boundary's `insert … returning` adds one, fts5's blob
  counted before `sqlite3_close` closes it. CI's `main`, `memory-1` and `current` lanes have FTS5.

### The survivors, argued

- **p14, `sqlite3_close` tried again on a refusal, is equivalent.** The second call meets what the
  first left: the virtual tables already disconnected and rolled back, and the same statement or
  backup, so it answers busy again and does nothing more. Nothing runs between the two calls, in one
  critical section on the owner's thread. Concrete input: the backup row; both calls answer 5, and
  the condition is the second's, the same code, extended code and message.
- **p16, the failure's details read before the count, is equivalent.** `sqlite3_next_stmt` takes
  the connection's mutex and walks its list, and sets no error, so the extended code and message read
  after it are the ones read before. Concrete input: the backup row; both orders give busy, busy,
  and `sqlite3_errmsg`'s message.

## The engines and the claims

The close's work runs inside `interrupt-latch-close!`'s one critical section, where no engine
expires and no timer's handler runs, so no engine row can see the order of its steps; it sees only
the outcome. The rows that close under engines or through a claim, each passing on all five
libraries with the fix, `make test` 74 of 74 on each before the review's rows, and on Guix's after:

- `test-open-engines`: "call-with-database's procedure leaves a statement its connection does not
  track, so the close fails, then re-enters a continuation a timer's handler took at each tick";
  its sweeps of the open verbs, whose failed settings close. p02, p05, p06, p10, p12, p15 and p18
  fail the first;
- `test-interrupt-database`: the latch's engine sweeps, which close at the first expiry, and the
  rows of the close's three callers;
- `test-connection`: `open-database` and `close-database!` under an engine of every fuel from 1 to
  60, and the close in another engine beside `call-with-open-handle`;
- `test-statement`: the finalize and the close in another engine beside a statement verb;
- `test-connection-cache`: two engines on one thread sharing the cache;
- `test-transaction-engine`: the failed begins beside a tracked and an untracked select.

## Times

`tests/test-connection-close.sps`, the one suite the fix touches, in its final 22 rows: three runs
plain and two under the gate on each library, by `date` around the run and by the gate's `time:`
lines, after the review's rows. Before them, at 18 rows, it ran 298 to 320 ms plain and 10 to 11 s
under the gate.

| Library | Rows unavailable | Plain | `make test-memory MEMORY_SUITES=tests/test-connection-close.sps` |
|---|---|---|---|
| Guix's 3.53.1 | rtree's 2 | 313, 315, 317 ms | 11 s, 12 s |
| `build/m4-current-fts5`, 3.54.1 | fts4's and rtree's, 4 | 317, 318, 320 ms | 12 s, 12 s |
| `build/m4cf-floor-vtab`, 3.45.1 | none | 320, 324, 345 ms | 11 s, 11 s |
| `build/m4cf-current-vtab`, 3.54.1 | none | 329, 342, 345 ms | 12 s, 11 s |
| `build/m3-floor`, 3.45.1 | 13 | 308, 311, 323 ms | not run |
| `build/m4-current`, 3.54.1 | 13 | 314, 331, 337 ms | not run |

Under the gate, each run: 0 errors, nothing definitely lost, 22 passed. `make test` ran 74 suites
and passed 74 on five libraries with the 18-row suite, against the baseline's 73 of 73 on Guix's,
and 74 of 74 on Guix's with the final one, the new suite's 22 rows passing.

## For the records

The builder edited none; the lead's.

- **ADR-0012, decision 5,** amended:
  - **the order:** the tracked statements finalized and the cache emptied, then `sqlite3_close`; on
    `SQLITE_OK` the outcomes as before; on any other answer the connection open and counted, and
    only then `sqlite3_next_stmt`: one or more, the assertion violation naming the count; none,
    `sqlite3_close`'s `&sqlite-error`. Why: the modules' table above, and `sqlite3Close`'s
    disconnect before its busy check;
  - **the boundary,** the maintainer's "Vouch only for ours": the close vouches only for the
    statements chez-sqlite3 tracks, and judges none it didn't make. A refusal means something
    other than the library left a statement, a blob or a backup open, a chez-sqlite3 bug or foreign
    code such as an extension loaded by `load-extension!`; that work, and what SQLite's close does
    to it, is theirs. The library's own leaks are the counters', Valgrind's and the gate's to
    catch. After a refusal the count is a diagnostic: every statement left, a module's pinned ones
    among them while a leftover statement holds their table;
  - **what SQLite's refusal does,** measured, and held by the boundary rows: every virtual table a
    transaction wrote is rolled back first. FTS3, FTS4 and FTS5 lose what they hadn't flushed, so
    a commit after it, or an untracked write's own finalize in autocommit, writes an index the
    module calls corrupt; plain tables and RTREE lose nothing. The old order never reached this:
    it refused every such close before `sqlite3_close`. The docs tell the caller to roll back, and
    that the table's own `'rebuild'` mended the index in the measured cases;
  - **rejected, with the measurement:** a refusal of busy statements before `sqlite3_close`. RTREE
    keeps a busy blob of its own in an open write transaction, on 3.45.1 and 3.54.1, and FTS5 at
    3.45.1 (`stmt-busy.txt`), so the rule would have refused the closes this fix exists for;
  - `sqlite3_close` failing with nothing to count is a backup's refusal alone, and the library
    binds no backup; `sqlite3_close_v2` stays rejected.

  The M2-plan amendment's "finalizes each, counting each down, before `sqlite3_next_stmt` and
  `sqlite3_close`" and "A close that then fails leaves its statements finalized" read in the old
  order; the second still holds.
- **ADR-0014, decision 8:** "then `sqlite3_next_stmt` must find none, and `sqlite3_close` runs",
  and "an untracked statement is refused as in M1", in the new order, and "a defect of
  chez-sqlite3's" widened to foreign code's.
- **ADR-0019, decision 2,** and its slice 6 amendment: the two paths that leave the connection
  open are now both `sqlite3_close` refusing, with statements left to count or none. The
  citations `connection.sls:417` and `:428` are stale, as are ADR-0020 decision 9's.
- **ADR-0020, decision 9:** "on a statement found untracked (`connection.sls:417`) or
  `sqlite3_close` failing (`connection.sls:428`)" becomes `sqlite3_close` failing, with or without
  a statement left.
- **ADR-0005, decision 5,** and its M2 amendment "`sqlite3_next_stmt` now has something to
  miss": the statements check runs after a refused close, not before each close. The gate keeps
  its property: SQLite refuses a close while any statement is left, so no close succeeds beside
  one, and a refusal names the count.
- **ADR-0021:** an extension's own statements, blobs or backups left open on a connection make its
  close refuse, and are the extension's, by the boundary.
- **`global-constraints.md`:** "Closing finalizes tracked statements, checks `sqlite3_next_stmt`,
  then calls `sqlite3_close`" (Connections), and "`close-database!` finalizes every statement it
  holds, checks `sqlite3_next_stmt`, calls `sqlite3_close`, and then raises" (Statements), in the
  new order, and the boundary in a line. The M4 rule on rows for what a library may lack names
  FTS5 only; this suite applies it to fts4, by `ENABLE_FTS3`, and rtree too.
- **`progress.md`:** the fix's close-out; the suite count, 74; `test-connection-close` in
  `MEMORY_SUITES_1`.
- **`traps.md`:** the traps below.
- **`CHANGELOG.md`,** at the next release: `close-database!` closes a connection that used an FTS3,
  FTS4, FTS5 or RTREE table; a refused close's advice in the reference.
- **The M4 slices:** an FTS5 suite whose connections close needs this fix, and no `drop table`
  before its close. Slice 2's `sqlite3_stmt_busy`, if it lands for its own use, has none here.

## The traps

- **A virtual table's module keeps prepared statements of its own on the connection,** until the
  table is disconnected, which only `sqlite3_close` or a `drop table` does for a table in the
  schema. Count a connection's statements after `sqlite3_close` refuses, never before. Reproduce
  with `src/chez-sqlite3/private/connection.sls` as it was at `87e762c`, from the root:
  `scripts/guix-env sh -c 'make deps >/dev/null; $CHEZ --libdirs src:build/scheme-libs --program .plans/research/m4-close-fix/vtab-close.sps'`
  prints `fts5 created-close (assertion-violation close-database! (untracked-statements 2))`.
- **A module's own statement can be busy: RTREE's node blob in an open write transaction,** on
  3.45.1 and 3.54.1, and FTS5's at 3.45.1. "Busy" doesn't mean "someone else's". Reproduce:
  `scripts/guix-env sh -c 'CHEZ_SQLITE3_LIBRARY=$PWD/build/m4cf-current-vtab/lib/libsqlite3.so.0 $CHEZ --libdirs src:build/scheme-libs --program .plans/research/m4-close-fix/stmt-busy.sps'`
  prints `rtree open-write ((9 ((#f read-only))) closed)`.
- **A refused `sqlite3_close` rolls back the virtual tables of an open transaction, and nothing
  else.** FTS3, FTS4 and FTS5 lose the terms they hadn't flushed; the content stays, so a commit
  writes a corrupt index. Reproduce:
  `scripts/guix-env sh -c '$CHEZ --libdirs src:build/scheme-libs --program .plans/research/m4-close-fix/failed-close-txn.sps raw commit'`:
  `fts5 integrity (sqlite-error corrupt corrupt-vtab ...)`.
- **`scripts/guix-env` changes to its own root.** Run from a copy under `build/`, it runs the
  worktree's code, not the copy's: `cd build/mut/p01-count-first && ../../../scripts/guix-env sh -c pwd`
  prints the worktree's root. A command for a copy changes into it inside the container, as
  `run-plants.sh` does. The builder's first probe of p03, and of the old order's modules, ran the
  fixed code so, and were run again.
- **`sqlite3_next_stmt` on a freed connection read 0, plain, in every close of eleven suites.**
  Only the gate sees a count made after a successful close: p03.
- **A module's option is not always its name's.** fts4's rows are chosen by `ENABLE_FTS3`, which
  every build with FTS4 lists, and which registers both modules.
- **A missing module is refused at the create's step, not its prepare,** with the code a syntax
  error's prepare gives, `error`. A refusal row prepares first and asserts it, so a broken create
  fails it (T3).
