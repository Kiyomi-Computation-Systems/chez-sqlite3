# What M3's single-connection topics rest on

Measured 2026-11-15 in the Guix container, for M3's plan: transactions and savepoints, the change
counters, the per-connection settings, and what a statement cache and a script runner rest on.
The concurrency topics (interrupt from another thread, busy timeout, WAL contention) are measured
apart, by another session. Revised the same day after an adversarial review. Measured again:
which errors end a transaction, the settings a VACUUM applies, and the cost of preparing. New:
`journal_mode` beside an open statement. Two libraries:

- **Guix's 3.53.1,** the container's own (`$GUIX_ENVIRONMENT/lib/libsqlite3.so.0`, its header in
  `$GUIX_ENVIRONMENT/include`);
- **the floor, 3.45.1** (`build/m3-floor/lib/libsqlite3.so.0`, its header in
  `build/m3-floor/include/`), CI's `floor` lane build of the pinned amalgamation,
  `$CC -shared -fPIC -O2 -DSQLITE_THREADSAFE=1 … -lpthread -lm`.

Every output file starts with `sqlite3_libversion()` and `sqlite3_sourceid()`, read at run time.
Each C probe is compiled against the library's own header and linked to that library by path,
with an rpath. It refuses to run unless the runtime version number and source id equal the
header's. The Chez probes are handed the header's two values by `run.sh`, read with `-dM -E`, and
refuse the same way. No version or option is read from the `sqlite3` command.

## Running the probes

From the worktree's root, every probe on both libraries, into a fresh directory:

```
mkdir -p build/m3rs
scripts/guix-env sh -c 'd=$(mktemp -d build/m3rs/run.XXXXXX) && \
  sh .plans/research/m3-plan/single/run.sh "$d" "$d/out"'
```

Name probes after `"$d/out"` to run only those, such as `txn cache`. To compare a run with the
files here, leaving out the timing lines:

```
scripts/guix-env sh -c 'd=…; r=.plans/research/m3-plan/single; for f in "$d"/out/*.txt; do \
  n=$(basename "$f"); grep -v "^time:" "$f" > "$d/a"; grep -v "^time:" "$r/$n" > "$d/b"; \
  cmp -s "$d/a" "$d/b" && echo "same: $n" || echo "DIFFERENT: $n"; done'
```

**Each probe was run twice from fresh scratch on both libraries,** after the review's fixes, by
the first command above with its scratch under `build/m3rs-fix/`. All 28 outputs matched byte for
byte, apart from their `time:` lines. The comparison was watched failing twice: on a Guix output
against its floor twin (`txn-special`), and on a copy with one planted line. The files here are
the second run. The first run's timings are kept as `cost-rerun-…` and `cost-chez-rerun-…`.

| Probe | Measures |
|---|---|
| [run.sh](run.sh) | builds and runs the rest, on both libraries |
| [options.c](options.c) | each library's compile options, through `sqlite3_compileoption_get` |
| [txn.c](txn.c) | B1: transaction state at each step; savepoints; the errors of transaction statements |
| [txn-errors.c](txn-errors.c) | B1: which errors end the transaction they happen in |
| [txn-special.c](txn-special.c) | B1: NOMEM by two methods, FULL, INTERRUPT, and a column read's NOMEM; the writes after an error that ended the transaction |
| [txn-open-stmts.c](txn-open-stmts.c) | B1: statements still open when a transaction ends; DDL rolled back |
| [counters.c](counters.c) | B2: `changes64`, `total_changes64`, `last_insert_rowid` |
| [pragmas.c](pragmas.c) | B3: the settings |
| [cache.c](cache.c) | B4: `PERSISTENT`, schema changes, `stmt_busy`/`stmt_readonly`, `sql`/`expanded_sql` |
| [cost.c](cost.c), [cost-chez.sps](cost-chez.sps) | B4: preparing against reuse, in C and through Chez's bare FFI |
| [script.c](script.c) | B4: a script by `sqlite3_exec`, and by a prepare loop over the tail |
| [entry-points.sps](entry-points.sps), [b5.c](b5.c) | B5: claims no research had measured |
| [traps.c](traps.c) | each trap, minimal, reproduced twice in a run |

Each probe's outputs are `PROBE-guix-3.53.1.txt` and `PROBE-floor-3.45.1.txt`. A probe's sections
are numbered, and the citations below name them: `txn-errors` E4 is section E4 of
`txn-errors-*.txt`.

## The libraries differ in these build options ([options.c](options.c))

Guix's has `ENABLE_COLUMN_METADATA`, `ENABLE_DBSTAT_VTAB`, `ENABLE_FTS3`, `ENABLE_FTS4`,
`ENABLE_FTS5`, `ENABLE_MATH_FUNCTIONS`, `ENABLE_PERCENTILE`, `ENABLE_UNLOCK_NOTIFY`,
`MAX_FUNCTION_ARG=1000` (the floor: 127) and **`SECURE_DELETE`**. The floor has none of them. Their
compilers differ: gcc 14.3.0 against 16.2.0. Every `DEFAULT_*` option is alike, so are
`TEMP_STORE=1` and `THREADSAFE=1`.

## B1. Transactions and savepoints

### State at each step ([txn.c](txn.c))

Alike on both libraries.

1. **`BEGIN` (deferred) sets autocommit to 0 and leaves `txn_state` at NONE** until the first read
   (READ) or write (WRITE). `BEGIN IMMEDIATE` and `BEGIN EXCLUSIVE` give WRITE at once, and
   `txn_state` has no state of its own for EXCLUSIVE. `COMMIT`, `END` and `ROLLBACK` give autocommit 1 and
   NONE (T1 to T4). `txn_state(NULL)` and `txn_state("main")` agreed throughout.
2. **In autocommit, a SELECT that has answered a row holds a read transaction.** Autocommit stays
   1, and `txn_state` is READ until the SELECT is reset or answers DONE (T5). Inside a transaction,
   a read leaves READ after its finalize (T6).
3. **`txn_state(NULL)` is the highest over every schema.** A temp table's write gave NULL WRITE
   with main NONE and temp WRITE (T7). An unknown schema answers −1.
4. **`SAVEPOINT` outside a transaction begins one,** deferred: autocommit 0, `txn_state` NONE until
   a read (S1). **`RELEASE` of it commits:** the second connection saw the row.
5. **`RELEASE` of an inner savepoint commits nothing** (S2). Inside `BEGIN`, `RELEASE` of the
   outermost savepoint commits nothing either (S5).
6. **`ROLLBACK TO` leaves its savepoint open, and the transaction too,** at WRITE, even when the
   savepoint began the transaction (S2, S4). A later write was rolled back to it again. Ending
   the transaction takes `RELEASE`, `COMMIT` or `ROLLBACK`. `ROLLBACK TO` an inner savepoint
   leaves it open too: its `RELEASE` succeeded (S3).
7. **`COMMIT` or `ROLLBACK` with savepoints open ends the whole stack.** A `RELEASE a` after it
   answered "no such savepoint: a" (S6). `RELEASE b` of an outer savepoint releases the ones
   inside it (S10).
8. **Names are compared case-insensitively for ASCII only** (S8). `RELEASE foo` released `Foo`,
   and `RELEASE "FOO"` released `foo`; `"Ä"` wasn't released by `"ä"` ("no such savepoint: ä"). Each of these is
   accepted as a name: `"a b"`, a string literal `'q'`, `[br]`, `` `bt` ``, the empty `""`, the
   keyword `begin` bare, and `"x""y"`, released by `'x"y'`.
9. **A name used twice: `ROLLBACK TO` and `RELEASE` reach the most recent** (S9). `ROLLBACK TO a`
   undid only the inner one's write. `RELEASE a` then released the inner one and committed nothing,
   and a second `ROLLBACK TO a` reached the outer.
10. **The errors come from the step, never the prepare,** each `rc 1`, extended 1 (S6, S7, S12,
    X1 to X3):
    - `BEGIN` inside a transaction, begun by `BEGIN` or by `SAVEPOINT`: "cannot start a
      transaction within a transaction". The transaction stays open. **A refused `BEGIN IMMEDIATE`
      or `BEGIN EXCLUSIVE` still takes its lock** (X1: NONE became WRITE; trap T1).
    - `COMMIT` or `END` with none open: "cannot commit - no transaction is active"; `ROLLBACK`:
      "cannot rollback - no transaction is active".
    - `RELEASE` or `ROLLBACK TO` of an unknown name, in a transaction or out of one: "no such
      savepoint: NAME". A transaction stays open (S12).

### Which errors end the transaction ([txn-errors.c](txn-errors.c))

Each case begins `BEGIN` (or `SAVEPOINT`), then inserts 10, then runs the failing statement. Alike
on both libraries. NOMEM was caused by `sqlite3_hard_heap_limit64(sqlite3_memory_used() + 1000)`,
set just before the step and set back to 0 straight after, with `randomblob(100000)`, the way M2
slice 4's research measured. The limit stays in force across the statement's own rollback, which
changes the outcome (the next section). FULL came from `PRAGMA max_page_count = 1` (clamped to
the file's size) on a file database.

| Case | Answer | The transaction | Rows |
|---|---|---|---|
| E1 UNIQUE, one row, default conflict (ABORT) | 2067 "UNIQUE constraint failed: t.x" | open | 10 stays |
| E2 UNIQUE at the 3rd row of 4 | 2067 | open | the statement's 2 earlier rows undone; 10 stays |
| E3 NOT NULL; CHECK | 1299; 275 "CHECK constraint failed: x < 1000" | open | 10 stays |
| E4 `INSERT OR ROLLBACK` | 2067 | **ended** | 10 gone |
| E5 `INSERT OR ROLLBACK` in a `SAVEPOINT` transaction | 2067 | **ended**; then `RELEASE`, `ROLLBACK TO`: "no such savepoint"; `ROLLBACK`: "no transaction is active" | 10 gone |
| E6 `INSERT OR FAIL` at the 3rd row of 4 | 2067 | open | the 2 earlier rows stay |
| E7 `UPDATE OR ROLLBACK` | 2067 | **ended** | 10 gone |
| E8 a trigger's `RAISE(ROLLBACK, '…')` | 1811, the trigger's message | **ended** | 10 gone |
| E9 `RAISE(ABORT, '…')` at the 3rd row of 4 | 1811 | open | the statement undone |
| E10 `RAISE(FAIL, '…')` at the 3rd row of 4 | 1811 | open | the 2 earlier rows stay |
| E11 `RAISE(IGNORE)` | DONE | open | that row skipped |
| E12 an immediate foreign key | 787 "FOREIGN KEY constraint failed" | open | 10 stays |
| E13 a deferred foreign key | the INSERT passes; **`COMMIT` answers 787** | **open after the failed COMMIT** (autocommit 0, WRITE) | none committed; with the parent added, `COMMIT` passed |
| E14 integer overflow at the 3rd row of 4 | 1 "integer overflow" | open | the statement undone |
| E15 FULL, one-row `INSERT … VALUES (zeroblob(100000))`, no constraints | 13 "database or disk is full" | **ended** | 10 gone |
| E16 FULL, `INSERT … SELECT zeroblob(3000)` of 100 rows, no constraints | 13 | open | the statement undone |
| E17 FULL, the one-row INSERT of E15, a NOT NULL column | 13 | **ended** | 10 gone |
| E18 FULL, the `INSERT … SELECT zeroblob(3000)` of E16, a NOT NULL column | 13 | open | the statement undone |
| E19 FULL, `INSERT … SELECT 100 + i`, no function, into t (UNIQUE, NOT NULL, CHECK) | 13 | open | the statement undone |
| E20 NOMEM, heap limit: one-row `INSERT … VALUES (randomblob(100000))` | 7 "out of memory" | **ended** | 10 gone |
| E21, E22 NOMEM, heap limit: `INSERT … SELECT` of 3 rows calling `randomblob(100000)`, two shapes | 7 | **ended** under this method; a statement of the same kind stayed open when one allocation failed (N3 against M5, below) | 10 gone |
| E23 NOMEM, heap limit: `SELECT randomblob(100000)`, which reads no table | 7 | open | 10 stays |
| E24, E25 refused at prepare: no such table; a syntax error | prepare rc 1 | open | 10 stays |

These rows stand as measured, but their shapes hide the rule. E16, E18, E21 and E22 call a
function, E19 checks constraints, and E23 reads no table. The next section measures the rule with
pairs that differ in one of these alone, and NOMEM by a second method.

### NOMEM, FULL and INTERRUPT ([txn-special.c](txn-special.c))

Each case has a fresh file holding `t`, `b(x)`, `bn(x NOT NULL)` and `src`, 10 rows of 3,000 bytes
of TEXT, committed. Then `BEGIN`, a marker row in `t`, and the statement. **Ended** means
autocommit 1 afterwards, with the marker gone for this connection and for a second one. **Open**
means autocommit 0 and `txn_state` WRITE, with the statement undone and the marker committed by a
later `COMMIT`. Alike on both libraries.

**The rule, from the floor's source** (`sqlite3VdbeHalt`, `sqlite3.c` lines 87620 to 87664 of
the 3.45.1 amalgamation). It explains the measurements; it is not one.

- **It applies only to a statement that reads or writes a database file** (`bIsReader`: any
  statement that opens a transaction on one, and `BEGIN`, `COMMIT`, `SAVEPOINT`; lines 85214 to
  85231). A statement that reads none, such as `select randomblob(100000)` or `select ?1`, is
  never subject to it.
- **INTERRUPT** ends the transaction, unless the statement is read-only.
- **IOERR** always ends it. Not measured here.
- **NOMEM and FULL undo only the statement when it has a statement journal, and otherwise end the
  transaction.** A statement has one when it may write more than one row and may abort partway
  (`usesStmtJournal = isMultiWrite && mayAbort`, line 86980). A function call sets `mayAbort`
  (line 84787), and so does a constraint that aborts. A SELECT has none, so NOMEM in a SELECT that
  reads a table ends the transaction.
- **If the statement's own rollback fails, the transaction is rolled back too** (lines 87739 to
  87751).

**NOMEM, by two methods.** N is txn-errors' method: the hard heap limit at
`memory_used + 1000`, set after the prepare and lifted after the last step. M is an
`SQLITE_CONFIG_MALLOC` wrapper armed just before the first step, which fails the first allocation
that reaches it and disarms itself. No limit is set for M. The bytes are the failed allocation's.

| Statement | N: the heap limit kept across the step | M: exactly one allocation failing |
|---|---|---|
| `SELECT randomblob(100000) FROM src LIMIT 1` | **ended** (N1) | **ended** (M1; 100,000 bytes) |
| `SELECT randomblob(100000)`, reading no table | open (N2) | open (M2; 100,000) |
| `INSERT INTO b SELECT randomblob(100000) FROM src LIMIT 3` | **ended** (N3) | open (M3, the first allocation: 56 bytes; M5, the first of at least 100,000: 100,000) |
| `INSERT INTO b VALUES (randomblob(100000))`, one row | **ended** (N4) | **ended** (M4; 100,000) |

- **The methods disagree on the multi-row INSERT,** the one statement here with a statement
  journal. M6 failed M5's 100,000-byte allocation and every allocation after it until the step
  returned: 2 failed in all, and the transaction ended. So under a limit left in force, the
  statement's own rollback fails too, and is escalated to the transaction's (trap T12). By the
  source, that rollback allocates a bitmap of the pages it plays back (`pagerPlaybackSavepoint`,
  about line 60104).
- **A SELECT's NOMEM ended the transaction when it read a table** (N1, M1), and not when it read
  none (N2, M2).

**FULL.** `PRAGMA max_page_count` was set to `PRAGMA page_count`, read after the marker: 15 on
both libraries. Each statement answered 13, "database or disk is full".

| Case | Statement | Calls a function? Checks a constraint? | The transaction |
|---|---|---|---|
| F1 | `INSERT INTO b SELECT x FROM src` | neither | **ended** |
| F2 | `INSERT INTO b SELECT lower(x) FROM src` | `lower` | open |
| F3 | `INSERT INTO bn SELECT x FROM src` | NOT NULL | open |
| F4 | `INSERT INTO b SELECT zeroblob(3000) FROM src` | `zeroblob` | open |
| F5 | `INSERT INTO b VALUES (zeroblob(100000))` | `zeroblob`, but one row | **ended** |
| F6 | `UPDATE src SET x = x \|\| x` | neither | **ended** |
| F7 | `UPDATE src SET x = lower(x \|\| x)` | `lower` | open |
| F8 | `UPDATE src SET x = zeroblob(9000)` | `zeroblob` | open |

F1 and F2 differ by one function call, F1 and F3 by one constraint, and F6 and F7 by one function
call (trap T8). F5 calls a function too, but writes one row, so it has no statement journal. In
every case `src` read back unchanged, 10 rows of 30,000 bytes.

**INTERRUPT.** `sqlite3_interrupt` was called on the same thread, from a progress handler at its
50th call, one call per 100 opcodes. Each statement answered 9, "interrupted".

| Case | Statement | The transaction |
|---|---|---|
| I1 | `INSERT INTO b WITH RECURSIVE c(i) AS (…) SELECT i FROM c` | **ended** |
| I2 | the same through `SELECT abs(i)`, so with a statement journal | **ended** |
| I3 | `WITH RECURSIVE c(i) AS (…) SELECT count(*) FROM c, src`, reading a table | open |
| I4 | the same `FROM c` alone, reading no table | open |

**A column read's NOMEM.** The statement was stepped to a row, inside the transaction, and one
column read with the heap limit at `memory_used + 1000` around that one call only. In every case
autocommit was still 0 straight after the read.

| Case | Statement and read | The read | Then | The transaction |
|---|---|---|---|---|
| G1 | `SELECT hex(x) FROM src`, `sqlite3_column_text16`, no limit: the control | a pointer | reset 0, finalize 0 | open |
| G2 | the same, under the limit | NULL, extended 7 | **reset 7**, finalize 0 | **ended** at the reset |
| G3 | the same, under the limit | NULL, extended 7 | **finalize 7** | **ended** at the finalize |
| G4 | `SELECT ?1`, reading no table, 100,000 bytes of TEXT bound with their length, `sqlite3_column_text` | NULL, extended 7 | reset 7, finalize 0 | open |
| G5 | the same | NULL, extended 7 | finalize 7 | open |
| G6 | `SELECT ?1` as G4, read by `sqlite3_column_text16` | NULL, extended 7 | reset 7, finalize 0 | open |

By the source, a column read's failed allocation stores NOMEM as the statement's code
(`columnMallocFailure`, about line 91164). A reset or finalize of a statement still running halts
it (`sqlite3VdbeReset`, about line 87874), and the halt applies the rule above to that NOMEM
(trap T13).

**The writes after an error that ended the transaction** (L1). `BEGIN`, the marker, then
`INSERT OR ROLLBACK` failing with 2067 ended the transaction. Two more INSERTs each answered DONE
with autocommit 1, and the second connection saw each at once. The closing `COMMIT` answered 1,
"cannot commit - no transaction is active". The marker was gone, and both later rows stood.

**So whether a failure ended the transaction can't be told from its code, or from the statement's
text.** The same code, 7 or 13, ended it or didn't, turning on four things:

- a function call or a constraint (F1 against F2 and F3);
- how many rows the statement may write (F5);
- whether it reads a table (N1 against N2);
- whether memory is still short while the statement rolls back (N3 against M5).

A column read's NOMEM is reported by the read, and ends the transaction at the reset or finalize
that follows (G2, G3). **The one test is `sqlite3_get_autocommit`, read after the failure.**

### Statements open across a transaction's end ([txn-open-stmts.c](txn-open-stmts.c))

Alike on both libraries.

1. **`COMMIT` succeeds with a SELECT on the same connection still mid-row** (O1). The SELECT went on
   answering rows, autocommit 1 with `txn_state` READ, until DONE gave NONE. The other connection
   saw the commit at once.
2. **After `ROLLBACK`, an open SELECT goes on answering rows, with no error** (O2, O3, O4):
   - with `ORDER BY` and no index, its sorter answered the rows the rollback removed (O2: 4 and 5);
   - as a rowid scan, it answered the rolled-back state (O2b: 2, 3, DONE);
   - **only when the rolled-back transaction had changed the schema, and the SELECT read a table**,
     did its next step answer **516 `SQLITE_ABORT_ROLLBACK`, "abort due to ROLLBACK"** (O4b, O4c).
     Its reset answered 516 again, and its finalize 0. With a sorter, even a schema change didn't
     stop it (O4).

   After the `ROLLBACK`, autocommit was 1 and `txn_state` READ until the SELECT finished (trap T2).
3. **In autocommit, a write commits while a SELECT on the same connection is mid-row** (O5). The
   other connection saw it at once.
4. **A write stepped to DONE and not reset doesn't hold up `COMMIT`** (O6).
5. **`COMMIT` answers `SQLITE_BUSY` (5, extended 5) while a write statement on the same connection
   is unfinished:** "cannot commit transaction - SQL statements in progress" (O7, O7c). The
   statement was an `INSERT … RETURNING` or `UPDATE … RETURNING` that had answered one row. The
   transaction stays open at WRITE. Once the statement was stepped to DONE or reset, `COMMIT`
   passed. No other connection was involved (trap T3).
6. **Inside `BEGIN`, a reset of a once-stepped `INSERT … RETURNING` commits nothing** (O7d). The
   reset answered 0, the transaction stayed open, the other connection saw neither row, and
   `ROLLBACK` removed both. Its rows were all inserted by the first step: the connection saw 6 and
   7. After `ROLLBACK`, the statement still answered its remaining row (O7b).
7. **A SELECT reset after a `ROLLBACK` answers 0 and restarts cleanly** (O8).
8. **DDL rolls back.** A rolled-back `CREATE TABLE`, `INSERT` into it, `ADD COLUMN`,
   `CREATE INDEX`, `DROP TABLE` and `CREATE VIEW` were all undone (D1). So was an `ADD COLUMN`
   rolled back to a savepoint, while the earlier `CREATE TABLE` stood (D2).

## B2. The change counters ([counters.c](counters.c))

Before each statement, the probe sets `changes64` to 2 and `last_insert_rowid` to 7777. Alike on
both libraries. "Unchanged" means 2 and 7777 kept.

| Statement | `changes64` | `total_changes64` moves | `last_insert_rowid` |
|---|---|---|---|
| INSERT of 3 rows; INSERT … SELECT of 5 | 3; 5 | +3; +5 | the last row's |
| UPDATE of 3; of 0 | 3; 0 | +3; 0 | unchanged |
| DELETE of 2 with WHERE; `DELETE FROM t` of 6; of an empty table | 2; 6; 0 | +2; +6; 0 | unchanged |
| DDL: CREATE TABLE, CREATE INDEX, ADD COLUMN, CREATE VIEW, DROP TABLE of 4 rows, DROP INDEX | unchanged | 0 | unchanged |
| SELECT; `PRAGMA user_version = 5`; BEGIN; COMMIT | unchanged | 0 | unchanged |
| INSERT failing (ABORT) at its 3rd row of 4 | 0 | 0 | **302, a row rolled back** |
| `INSERT OR FAIL` failing at its 3rd row of 4 | 2 | +2 | 402, which stands |
| a one-row INSERT failing; an UPDATE failing | 0 | 0 | unchanged |
| `INSERT OR IGNORE` that ignores; that ignores 1 of 2 | 0; 1 | 0; +1 | unchanged; the inserted row's |
| `INSERT OR REPLACE` replacing 1 row, by its key or by a UNIQUE; replacing 2 at once | 1; 1 | +1; +1 | the new row's |
| upsert `DO UPDATE`; `DO NOTHING` | 1; 0 | +1; 0 | **unchanged** |
| upsert of 2: an update and an insert; two updates | 2; 2 | +2; +2 | the inserted row's; unchanged |
| INSERT of 2 rows firing triggers that write 6 | 2 | **+8** | the outer statement's last row, 501 |
| UPDATE of 2 rows firing triggers that write 2 | 2 | +4 | unchanged |
| FK cascade: DELETE of 1 parent, 3 children; UPDATE of 1 parent, 1 child | 1; 1 | **+4; +2** | unchanged |
| WITHOUT ROWID: INSERT of 2, UPDATE of 2, REPLACE | 2, 2, 1 | +2, +2, +1 | **unchanged** |
| a statement prepared and finalized, never stepped | unchanged | 0 | unchanged |
| BEGIN; INSERT 2 rows; ROLLBACK | 2 | **+2, kept after ROLLBACK** | **7002, rolled back** |

- **Inside a trigger** (C9): `last_insert_rowid()` was the outer row's in an AFTER trigger. After
  the trigger's own INSERT, it was that INSERT's row. In a BEFORE trigger, it was the value before
  the outer row: 7777 for the first row, and 500 for the second, so the inner rows didn't leak out.
  `changes()` there was 2, the last outer statement's, and 1 after the trigger's own INSERT.
- **`INSERT … RETURNING` of 3 rows** (C12): `last_insert_rowid` moved at the first step, to the
  last row's 903. **`changes64` and `total_changes64` moved only at the step that answered DONE.**
  A reset after one step moved them too, and all 3 rows were in the table (C12b). So did a
  `DELETE … RETURNING`'s finalize (C12c).
- **Another connection's writes move none of this connection's counters** (C13).
- **A fresh connection:** 0, 0, 0 (C0).

## B3. The settings, through PRAGMAs ([pragmas.c](pragmas.c))

Alike on both libraries but in one place: **`secure_delete`'s default is 1 on Guix's, built with
`SECURE_DELETE`, and 0 at the floor** (P1.10, P3, P9).

1. **Kept in the file across a close and reopen:** `journal_mode=WAL`, `user_version` and
   `application_id` (P1). **Deferred to a VACUUM once the file holds a table:** `auto_vacuum` and
   `page_size`. Each read back its old value, and no error was raised (P1.30, P1.31). After a
   `VACUUM` on the same connection they read 1 and 8192, the rows intact, and they kept those
   after a reopen (P12.1, P12.2). **No effect on a file holding a table:** `encoding`, which read
   `UTF-8` after the set, after a `VACUUM` and after a reopen (P1.32, P12.3). **Reset by
   every new connection:** everything else measured, `foreign_keys`, `busy_timeout`, `synchronous`,
   `cache_size`, `temp_store`, `recursive_triggers`, `defer_foreign_keys`, `query_only`,
   `trusted_schema`, `secure_delete`, `automatic_index`, `journal_mode=TRUNCATE`, `locking_mode`
   and 12 more, 25 in all.
2. **What a set answers** (P1):
   - **a row of the new value:** `busy_timeout`, its column named **`timeout`**; `journal_mode`;
     `locking_mode`; `secure_delete`; `max_page_count`; `wal_autocheckpoint`;
     `journal_size_limit`; `mmap_size`; `threads`; `analysis_limit`; the heap limits;
   - **no row:** every other setting measured. `case_sensitive_like` has no read form, and
     answers no row to a read.
   - **Reads answer TEXT** for `journal_mode` (`'wal'`) and `locking_mode` (`'exclusive'`), in
     lower case, and for `encoding` (`'UTF-8'`). Every other setting answers INTEGER,
     `synchronous`, `temp_store` and `secure_delete` among them.
3. **Most settings take effect at prepare, never stepped** (P3). 30 settings were each set on a
   file of their own holding a table, `journal_mode` twice, to WAL and to TRUNCATE. Each was read
   while its set statement was held unstepped, and again after its finalize. 23 had changed:
   `foreign_keys`, `busy_timeout`, `synchronous`, `cache_size`, `temp_store`,
   `recursive_triggers`, `defer_foreign_keys`, `query_only`, `trusted_schema`, `secure_delete`,
   `automatic_index`, `locking_mode` and 11 more. Unchanged: `journal_mode`, `user_version`,
   `application_id`, `max_page_count`; `auto_vacuum` and `page_size`, which wait for a VACUUM; and
   `encoding`. `case_sensitive_like` wasn't measured: it has no read form.
4. **Process-wide, not per connection:** `soft_heap_limit` and `hard_heap_limit`, set on one
   connection, were read on another and on one opened later (P2). **`PRAGMA hard_heap_limit` only
   lowers:** `= 70000000` and `= 0` each left 60000000. `sqlite3_hard_heap_limit64(0)` cleared it,
   and the soft limit with it. With a hard limit set, `PRAGMA soft_heap_limit = 0` answered the hard
   limit (trap T9).
5. **Invalid values are never an error; SQLite coerces them silently** (P4, each from a
   non-default base):
   - **booleans**, measured on `foreign_keys`: a word it doesn't know, such as `bogus` or
     `enable`, an empty `''`, `DEFAULT`, `-1` and `0.5` each turn it **off**. `2`, `1.5`, `0x1`,
     `yes`, `true` and `'on'` turn it on, and `256` turns it off (trap T4). `recursive_triggers`,
     `query_only`, `trusted_schema`, `automatic_index`, `defer_foreign_keys` and
     `cell_size_check` each went off for `bogus` and on for `2`;
   - **`synchronous`** (from EXTRA, 3): `bogus`, `''`, `-1`, `DEFAULT`, `ON` and `yes` give NORMAL,
     1. `4` is stored and read back as 4, which is no level of SQLite's. `99` keeps 3;
   - **integers**: `cache_size = 'abc'`, `''`, `DEFAULT`, 99999999999 and ±2⁶³ give 0. `'12abc'`
     gives 12, `1.9` and `1e3` give 1, `0x10` gives 16. `busy_timeout = -5`, `'abc'`, `''` and
     2147483648 give 0, and `1.5` gives 1. `user_version = 2147483648` and `4294967296`, and
     `application_id = 4294967297`, give 0. `-1` is kept as −1, and `'42'`, `+42` and `0x2A` give
     42. `temp_store = 7`, `3`, `-1` and `'bogus'` give 0, the default;
   - **names**: `journal_mode = bogus`, `'WAL '` and `1` keep the mode, but `''` gives
     `delete`. `locking_mode = bogus` keeps it. `secure_delete = bogus` gives 0, and `5` gives 1.
6. **An unknown name is no error, in either form** (P5). `PRAGMA nosuch`, `PRAGMA nosuch = 1`,
   `PRAGMA nosuch(1)`, `PRAGMA main.nosuch` and the misspelt `PRAGMA foreign_key = ON` each
   prepared and stepped, with no columns and no rows. The setting stayed as it was (trap T4).
   **An unknown schema is an error at prepare,** "unknown database nosuchschema", even for a
   connection-wide setting. `temp.foreign_keys = ON` set the connection's `foreign_keys`.
7. **Inside a transaction** (P6, trap T5):
   - `foreign_keys = ON` answers nothing, raises nothing, and **does nothing**: it read 0, a
     violating INSERT passed, and it was still 0 after `COMMIT`. Turning it off inside a savepoint
     did nothing either;
   - `synchronous = OFF` is refused **at prepare**: "Safety level may not be changed inside a
     transaction";
   - `journal_mode = WAL` **fails at its step** before the transaction has written: "cannot change
     into wal mode from within a transaction". **Once it has written, the step answers `delete`,
     the old mode, and raises nothing.** `journal_mode = TRUNCATE` succeeded before a write;
   - `busy_timeout` set inside a transaction survives its `ROLLBACK`, and `user_version` doesn't.
8. **`defer_foreign_keys` switches itself off** at the end of the next write statement in
   autocommit, and at `COMMIT` and `ROLLBACK`, but not after a SELECT (P6b).
9. **A bound parameter is a syntax error at prepare** (P7): `PRAGMA busy_timeout = ?`, `= ?1`,
   `= :t`, `(?)`, and `PRAGMA user_version = ?` and `main.user_version = ?`, each "near "?":
   syntax error", rc 1. **A schema name works:** `PRAGMA main.user_version = 5`,
   `PRAGMA "main".user_version`. `temp.user_version` reads temp's own 0.
   - **The value's grammar** (P7): accepted are an integer, signed with `-` or `+`, a float, a
     bare word, a `'string'`, a `"quoted name"`, `ON`, `DELETE` and `DEFAULT`, after `=` or in
     parentheses. These are syntax errors: `1 + 1`, `(5)` after `=`, `NULL`, `x'37'`, and `()`.
     `PRAGMA busy_timeout =` with nothing after it is "incomplete input". A trailing `;` or
     comment is fine.
10. **Names and values are compared case-insensitively** (P8): `FOREIGN_KEYS = on`, `Wal`,
    `'DELETE'`, `"Truncate"`, `Exclusive`, `Normal`, `Memory`, `FAST`. **A column is named in lower
    case, whatever case was typed:** `"foreign_keys"`, `"journal_mode"`, `"user_version"`, and
    busy_timeout's `"timeout"`.
11. **Every setting in the list reads through a table-valued function,** `SELECT * FROM
    pragma_foreign_keys` and the other 14, with the same column names (P9). An argument is refused:
    `pragma_user_version('main')`, `(5)` and `(?)`, and `pragma_busy_timeout(5)`, each "too many
    arguments on pragma_user_version() - max 0". `pragma_cache_size(?)`, left unbound, was
    accepted and answered −2000. `main.pragma_user_version` works. So a setting can be read by a
    SELECT, but not written by one.
12. **`query_only` refuses with `SQLITE_READONLY`** (8, extended 8, "attempt to write a readonly
    database") at the step of an INSERT, a CREATE TABLE, `PRAGMA user_version = 4`,
    `BEGIN IMMEDIATE`, and a CREATE TEMP TABLE (P10).
13. **`journal_mode=wal` on `:memory:` answers `memory`, at the floor too**, as M1 measured on
    3.53.1 alone. So does `= delete`; `= off` answers `off` (P11).
14. **`journal_mode = wal` fails beside the connection's own open statement, in autocommit**
    (P13). A SELECT on the same connection held a row: autocommit 1, `txn_state` READ. The step
    answered 1, "cannot change into wal mode from within a transaction", and the mode stayed
    `delete`. Once the SELECT was finalized, `= wal` answered `wal`. Beside the same kind of
    reader, `= truncate` succeeded: it answered `truncate`, and read back `truncate`.

## B4. What a statement cache and a script runner rest on

### `SQLITE_PREPARE_PERSISTENT` ([cache.c](cache.c), K1)

Each run held 50 statements of `SELECT x, y FROM t WHERE x = ?1` on a fresh `:memory:`
connection. Both libraries have the same pattern; their sizes differ:

| | flags 0: 3.53.1 | flags 0: 3.45.1 | `PERSISTENT`: 3.53.1 | `PERSISTENT`: 3.45.1 |
|---|---|---|---|---|
| `LOOKASIDE_USED`, holding 50 | 123, full | 123, full | **0** | **0** |
| `LOOKASIDE_MISS_FULL` (high), holding 50 | 1130 | 756 | **0** | **0** |
| `STMT_USED`, holding 50 | 143,544 | 116,808 | 114,000 | 87,600 |
| `memory_used` over its start, holding 50 | +95,640 | +68,904 | +114,000 | +87,600 |
| `LOOKASIDE_USED`, the 50 stepped once | 123 | 123 | 80 | 80 |

- **Without `PERSISTENT`, held statements fill the connection's lookaside:** 10 had taken 116
  slots (3.53.1) and 90 (3.45.1), and 50 took 123 on both, where it stopped while
  `LOOKASIDE_MISS_FULL` grew.
- **With it, a held statement takes no lookaside** and costs heap instead: 2,280 bytes each on
  3.53.1 and 1,752 on 3.45.1. A running statement still takes lookaside: 80 slots for 50 stepped.
- **No other difference was seen.** `prepare_v2` and `prepare_v3` with `PERSISTENT` re-prepared
  alike (K2.12). A third run with flags 0 repeated the first exactly.

### A statement held across a schema change ([cache.c](cache.c), K2)

Alike on both libraries. `reprepares` is `sqlite3_stmt_status(SQLITE_STMTSTATUS_REPREPARE)`.

1. **The column count changes at the step that re-prepares, never before.** After `ADD COLUMN`,
   made by the same connection (K2.2) or by another (K2.7), a held `SELECT *` read 2 columns.
   Its step answered a row of 3, and after it the count was 3 and `reprepares` 1.
2. **A statement mid-row isn't re-prepared.** Its own connection's `ADD COLUMN` succeeded while it
   had a row ready, and it went on with 2 columns to DONE. Only after a reset did it give 3 (K2.3).
   **Its own connection's `DROP TABLE` of that table was refused:** 6, "database table is locked"
   (K2.5).
3. **`CREATE INDEX` re-prepares and keeps the bindings** (K2.1, K2.6): a statement bound to 2
   answered row 2. Its `expanded_sql` read `… WHERE a = 2`.
4. **`DROP TABLE` gives the step rc 1, "no such table: t4"; never `SQLITE_SCHEMA`** (K2.4, K2.8).
   Column count and `reprepares` stayed as before. Its reset answered 1 again. **When the table was
   made again, with other columns, the same statement ran again in the new shape** (3 columns, then
   1). `DROP COLUMN` of a column it named gave "no such column: b" (K2.9).
5. **A held INSERT whose table gained a column fails at its step:** "table t10 has 3 columns but 2
   values were supplied" (K2.10). Then the table was rebuilt with 4 columns, and the statement still
   said "3 columns". It said "4" only after another statement on its connection had read the table
   (trap T6).
6. **`SQLITE_SCHEMA` reached the caller only through the legacy `sqlite3_prepare`** (K2.11). Its
   step answered 1, "SQL logic error". Its reset answered 17, "database schema has changed", and
   every later step failed with extended 17. No `prepare_v2` or `prepare_v3` statement answered 17
   in any case here.

### `stmt_readonly`, `stmt_isexplain` and `stmt_busy` ([cache.c](cache.c), K3)

Alike on both libraries.

- **`stmt_busy` is 1 only while a statement has a row ready.** It is 0 once prepared, after DONE,
  after a failed step (2067), after reset, and for a statement whose first step answers DONE.
  **One exception: `EXPLAIN` and `EXPLAIN QUERY PLAN` stay busy, 1, after answering DONE** until
  reset (trap T11).
- **`stmt_readonly` is 1 for `BEGIN`, `COMMIT`, `ROLLBACK`, `SAVEPOINT`, `RELEASE`, `ROLLBACK TO`,
  `ATTACH` and `DETACH`.** It is also 1 for `PRAGMA foreign_keys = ON`, `busy_timeout = 10` and
  `cache_size = 100`, and for the other read PRAGMAs measured (`user_version`, `foreign_keys`,
  `table_info`). **`PRAGMA journal_mode`, even as a read, is 0,** as is
  `PRAGMA user_version = 3`. Every write is 0, `CREATE TEMP TABLE`, `INSERT` into a
  temp table, `ANALYZE`, `VACUUM`, `REINDEX` and `EXPLAIN INSERT` among them.
- **`stmt_isexplain`:** 1 for `EXPLAIN`, 2 for `EXPLAIN QUERY PLAN`, otherwise 0.

### `sqlite3_sql` against `sqlite3_expanded_sql` ([cache.c](cache.c), K4)

Alike on both libraries.

- **`sqlite3_sql` gives the text exactly as prepared, from the first byte to the tail.** That
  includes leading whitespace, comments and the semicolon (`[  SELECT 1 /* c */ ;]`), and a
  trailing `--` comment with its newline when no semicolon ends the statement. It never changes
  with bindings.
- **`sqlite3_expanded_sql` is not SQL that reads back the same values.** It writes an unbound
  parameter as `NULL`, as it does after `clear_bindings`. It quotes text (`'it''s'`) and writes a
  blob as `x'00ff'`. A real has 15 significant digits (`1.23456789012346e+19`,
  `0.333333333333333`). It writes `-0.0` as `0.0`, `+inf` as `Inf` and `-inf` as `-Inf`, which
  aren't SQL literals. It cuts text at an embedded NUL (`'a'` for 3 bytes) and passes bytes that
  aren't UTF-8 through raw. **Over `SQLITE_LIMIT_LENGTH` it answers NULL:** 104 bytes over a limit
  of 100.

### Preparing against reuse ([cost.c](cost.c), [cost-chez.sps](cost-chez.sps))

Timings, so **not byte-compared**. The machine is shared: an Intel Core Ultra 5 125H, 18 logical
CPUs. Each figure is ns per round: min, median and max over 25 runs of 2,000 rounds, after one
untimed run, on a `:memory:` database of 1,000 rows or more. The insert runs in autocommit.

- **Both sides of each comparison take the same prepare flags.** Each loop was measured with
  flags 0, as ADR-0014's prepare passes them, and again with `SQLITE_PREPARE_PERSISTENT`. The
  reused statement is prepared once, untimed, with the same flags as the rounds that prepare.
- **No read stays open into the inserts.** The select's reused statement is reset, untimed, after
  each run.
- **The Chez loops do with SQLite what ADR-0011, ADR-0014 and ADR-0015 have the library do:** the
  SQL encoded and copied into a foreign block, the out-parameters in blocks, text bound from a
  block, and a TEXT column copied out and decoded.

Flags 0:

| Loop | C, 3.53.1 | C, 3.45.1 | Chez `__collect_safe`, 3.53.1 | Chez `__collect_safe`, 3.45.1 | Chez plain, 3.53.1 | Chez plain, 3.45.1 |
|---|---|---|---|---|---|---|
| insert, prepare each round | 1222 / **1232** / 1327 | 1095 / **1106** / 1464 | 3252 / **3306** / 3391 | 3063 / **3208** / 3879 | 3108 / **3141** / 3292 | 2837 / **2917** / 3228 |
| insert, reuse one statement | 578 / **586** / 640 | 535 / **541** / 583 | 1204 / **1223** / 1277 | 1114 / **1175** / 1238 | 1105 / **1111** / 1158 | 1006 / **1027** / 1179 |
| select, prepare each round | 1250 / **1280** / 1320 | 1124 / **1152** / 1233 | 3176 / **3213** / 3396 | 2992 / **3214** / 3346 | 2994 / **3011** / 3092 | 2767 / **2887** / 3272 |
| select, reuse one statement | 261 / **271** / 287 | 253 / **262** / 290 | 859 / **869** / 942 | 830 / **872** / 1073 | 769 / **776** / 842 | 726 / **736** / 851 |

`SQLITE_PREPARE_PERSISTENT`:

| Loop | C, 3.53.1 | C, 3.45.1 | Chez `__collect_safe`, 3.53.1 | Chez `__collect_safe`, 3.45.1 | Chez plain, 3.53.1 | Chez plain, 3.45.1 |
|---|---|---|---|---|---|---|
| insert, prepare each round | 1675 / **1688** / 1892 | 1599 / **1605** / 1663 | 3812 / **3839** / 3983 | 3514 / **3570** / 3904 | 3667 / **3693** / 3880 | 3341 / **3384** / 3692 |
| insert, reuse one statement | 567 / **577** / 616 | 545 / **551** / 558 | 1218 / **1227** / 1284 | 1104 / **1126** / 1215 | 1106 / **1112** / 1184 | 1007 / **1014** / 1185 |
| select, prepare each round | 1957 / **1999** / 2219 | 1743 / **1762** / 1785 | 3973 / **4011** / 4314 | 3567 / **3661** / 4034 | 3787 / **3817** / 4015 | 3441 / **3490** / 6333 |
| select, reuse one statement | 270 / **276** / 361 | 275 / **278** / 319 | 877 / **884** / 938 | 828 / **848** / 986 | 771 / **775** / 789 | 723 / **733** / 793 |

The first run's medians, in the `-rerun-` files, are within 2% of these for 30 of the 48 figures,
and within 5% for 40. The largest gap is 10%: the Chez plain insert reuse on 3.45.1, with
`PERSISTENT`, at 1118 against 1014. Every sentence below holds for both runs.

- **With flags 0, reuse saves 1.9 to 2.1 µs an insert and 2.2 to 2.3 µs a select through the
  probe's FFI path,** on both libraries and both bindings. In C it saves 0.6 µs an insert and 0.9
  to 1.0 µs a select.
- **That saving is a lower bound.** The probe's prepare path leaves out what the library's prepare
  adds: the critical sections, the record and state checks, the counters behind their mutex, and
  the tail scan and the U+0000 scan in Scheme. A round that prepares also finalizes, and the
  library's finalize has its section and counters too.
- **`PERSISTENT` makes preparing dearer, and reuse no cheaper.** With it on both sides, each round
  that prepared took 0.36 to 0.81 µs longer than with flags 0, and each reuse round was within
  50 ns of its flags-0 figure. Each `PERSISTENT` measure ran after its flags-0 twin, on a table at
  least 104,000 rows larger, but the reuse loops in the same runs didn't slow, so the order isn't
  the cause. K1's measurement fits: a `PERSISTENT` statement takes heap, not lookaside.
- **`__collect_safe` adds 0.04 to 0.15 µs to each reuse round, two calls, and 0.07 to 0.33 µs to
  each prepare round, three calls.** That is 20 to 110 ns a call; the runs differed that much.
- **3.53.1's medians were −1% to 14% above the floor's in C, and −0.3% to 10% through Chez,** in
  the second run, and 4% to 18% and −2% to 5% in the first. The two libraries came from different
  compilers and options, so this compares builds, not versions.

### A script that fails midway ([script.c](script.c))

Alike on both libraries. Each script ran by `sqlite3_exec`, and by a loop of `prepare_v2` over the
tail, each on a fresh file.

1. **Both stop at the first error, and the statements before it stand** (X1: 1 and 2 kept, 3
   never inserted). Nothing is undone that the error itself didn't undo.
2. **Inside an explicit transaction, the transaction is left open** (X2 `BEGIN`, X3 `SAVEPOINT`,
   X16 a failed `COMMIT` on a deferred foreign key). **Or it is already ended,** when the error ended
   it (X4 `INSERT OR ROLLBACK`). Neither runner rolls anything back.
3. **`sqlite3_exec`'s message equals `sqlite3_errmsg`**, and `extended_errcode` is the failure's
   extended code (2067, 787). A `NULL` out-parameter is allowed (X19).
4. **`sqlite3_exec` runs statements that answer rows, and throws the rows away** with no callback
   (X7). With a callback, each row is passed as text (X17). **A callback that answers nonzero stops
   it with 4 (ABORT), "query aborted"**, and the statements after it don't run (X18).
5. **A prepare error midway** (a syntax error, X5; no such table, X6; incomplete input, X8) stops
   both runners after the statements before it. **`sqlite3_error_offset` after `sqlite3_exec`
   counts from the failing statement with its leading whitespace skipped:** 0 for `SELEKT` at byte
   27 of the script (trap T10). The loop's prepare gives 1 from where it started, byte 26, so it
   can find byte 27. "no such table" and "incomplete input" have no offset, −1.
6. **Empty SQL, only semicolons, only a comment, and a trailing comment** are no error for either
   runner (X9 to X12). A last statement with no semicolon runs (X13). PRAGMAs in a script run in
   order (X14).

## B5. Claims in the records about M3's topics

| Claim | Where | Status |
|---|---|---|
| "PRAGMAs are SQL. They run through the ordinary statement path." | brief, line 86 | A design choice, not measurable. |
| "`foreign_keys` and `busy_timeout` reset with each connection" | brief, lines 87–88 | **Measured now:** P1.1, P1.2. |
| "A PRAGMA's value can't be a bound parameter" | brief, lines 88–89 | **Measured now:** P7, a syntax error at prepare. |
| "a setting is checked by reading its row back" | brief, lines 90–91 | **Measured now:** P1, the read forms; P4, coercions a read-back sees, and `synchronous = 4`, which it can't tell from a real level. |
| "`journal_mode=wal` on a `:memory:` database answers `memory` while every call succeeds" | brief, lines 91–92 | Measured before on 3.53.1 ([research/m1-plan/](../../m1-plan/)); **at the floor now**, P11. |
| "`sqlite3_changes64`, `sqlite3_last_insert_rowid`, `sqlite3_total_changes64`, the busy timeout, `sqlite3_interrupt`" in v1 | brief, lines 121–122 | **Measured now:** all present at the floor ([entry-points.sps](entry-points.sps)), with `sqlite3_txn_state`, `sqlite3_get_autocommit`, `sqlite3_exec`, `sqlite3_stmt_busy`, `sqlite3_stmt_readonly`, `sqlite3_stmt_isexplain`, `sqlite3_expanded_sql`, `sqlite3_db_status`, `sqlite3_is_interrupted` and the heap limits. Absent at the floor: `sqlite3_db_status64`, `sqlite3_setlk_timeout`. Absent from both: `sqlite3_normalized_sql`. |
| D3: "as Python's `sqlite3` keeps" | brief, line 140 | Not a claim about SQLite. |
| D3: "bounded and cleared by close" | brief, line 140 | A leaning. What it rests on is measured now: a held statement makes `sqlite3_close` answer BUSY (b5 V2), and held statements fill lookaside (K1). |
| "Two connections in WAL mode contending under a busy timeout" | brief, lines 160–161 | The concurrency session's. |
| "`sqlite3_close` refuses with `SQLITE_BUSY` while statements are unfinalized, and leaves the connection open" | ADR-0012, lines 28–29 | **Measured now** (b5 V2): 5, "unable to close due to unfinalized statements or unfinished backups", for a statement unstepped and for one mid-row. The connection still worked, and it closed once the statement was finalized. |
| "M3's settings list arrives as an argument that isn't a symbol" | ADR-0012, line 131 | A design choice. |
| "A finalize can report a failure of its own, such as the commit of an `insert … returning` stepped once" | ADR-0012, lines 183–185 | Measured before ([research/m2-review/](../../m2-review/), 1), in autocommit. |
| "a step after `SQLITE_DONE`, with no reset, runs the statement again" | ADR-0014, line 29 | Measured before ([research/m2-plan/](../../m2-plan/), 1). |
| "A build with `SQLITE_OMIT_AUTORESET` answers `SQLITE_MISUSE` instead" | ADR-0014, line 30; the M2 plan's Q4, lines 69–70 | **From the floor's source, not measured:** no such build is here. On such a build, `sqlite3_step` on a halted statement (`sqlite3.c` lines 90643 to 90651) answers `SQLITE_MISUSE` after DONE or after an error other than BUSY and LOCKED. After BUSY or LOCKED it resets the statement itself and runs it again. So the record holds after DONE, its context, and not after every failed step. |
| "`sqlite3_reset` and `sqlite3_finalize` answer a failed step's code again" | ADR-0014, line 31 | Measured before ([research/m2-plan/](../../m2-plan/), 2); seen again now after a failed re-prepare (K2.4, K2.8: reset 1). |
| "an `insert … returning` stepped once commits at its reset or finalize" | ADR-0014, lines 32–33 | Measured before, in autocommit, the bullet's context (m2-review, 1). **Inside a transaction a reset commits nothing** (O7d): see "Wording the records could sharpen". |
| "they can wait: with `pragma busy_timeout = 1500` …" | ADR-0014, line 35 | Measured before (m2-review, 2); the busy timeout is the concurrency session's. |
| "`sqlite3_finalize` frees the statement whatever it answers" | ADR-0014, lines 37–38 | Measured before ([m2-review/probe6.sps](../../m2-review/probe6.sps), O): after finalize answered 2067, and after it answered 5, no statement was left on the connection and `sqlite3_close` answered 0. |
| "`sqlite3_prepare_v3` compiles the first statement and leaves the rest … Empty SQL, SQL that is only whitespace, comments or semicolons, gives a NULL statement" | ADR-0014, lines 43–45 | Measured before: [m2-plan/probe.sps](../../m2-plan/probe.sps), 5 (`select 1; select 2` leaves its tail at byte 9; empty SQL and a lone comment give NULL); [m2-review/probe2.sps](../../m2-review/probe2.sps), A (`;` and `;;` give NULL); [m2-review/round2-r1.sps](../../m2-review/round2-r1.sps), R3 (`\f`, `--` and an unterminated `/* ` give NULL). |
| "preparing a PRAGMA changes the connection, unstepped: `cache_size`, `encoding` and `case_sensitive_like`" | ADR-0014, lines 46–47 | Measured before (m2-review, 5, on an empty `:memory:` database). **P3 agrees for `cache_size`, and finds 22 more that change at prepare. It found `encoding` unchanged** at prepare on a file holding a table, as at a step and a VACUUM (P1.32, P12.3). It didn't measure `case_sensitive_like`, which has no read form. |
| "a statement's column count changes when another connection adds or drops a column, read after its next step" | ADR-0014, lines 48–49 | Measured before (m2-review, 13); **now also for the same connection's DDL, and not before that step** (K2.2, K2.7). |
| "only the last finalize commits" | ADR-0014, line 50 | Measured before (m2-review, 19). |
| "SQLite's whitespace is exactly space, `\t`, `\n`, `\f` and `\r`, and `/*` as the SQL's last two bytes is an error" | ADR-0014, lines 52–53 | Measured before ([m2-review/round2-r1.sps](../../m2-review/round2-r1.sps), R3: `\v`, U+0085 and U+00A0 each answered 1, and so did a final `/*`). The record's own amendment, from [m2-slice-1/tail.sps](../../m2-slice-1/tail.sps), adds `\v` inside a run and U+FEFF anywhere. |
| "Preparing the tail would run a PRAGMA's side effects (measured)" | ADR-0014, line 119 | Measured before (m2-review, 5, 18); P3 adds which settings. |
| "never cached: the count changes when another connection changes the table" | ADR-0014, lines 142–143 | Measured before; the same connection changes it too (K2.2). |
| "M3's interrupt is how another thread stops a long one" | ADR-0014, line 224 | The concurrency session's. |
| "`pragma cache_size = 7; select 1` is refused, and `cache_size` is 7 afterwards" | ADR-0014, line 228 | Measured before (m2-review, 18). |
| "its statement cache (brief D3) holds statements its connection still tracks" | ADR-0014, line 234 | A design choice; b5 V2 is why close must finalize them first. |
| "a column declared `BOOLEAN` holds the text `'yes'` as TEXT" | ADR-0015, lines 23–24 | Measured before ([research/m2-plan/](../../m2-plan/), 10). |
| "booleans are stored as the integers 0 and 1, and TRUE and FALSE are spellings of them" | ADR-0015, lines 24–25 | **Measured now** (b5 V1): `TRUE` and `FALSE` are INTEGER 1 and 0. A BOOLEAN column keeps `'true'` as TEXT. `2 IS TRUE` is 1, but `2 = TRUE` is 0. |
| "perhaps with M3's conveniences" | ADR-0015, line 182 | A design choice. |
| "M3's `execute!` may take a script; a statement never does" | M2 plan, line 65 | A design choice; script.c measures what a script runner rests on. |
| "an `insert … returning` stepped once commits at its finalize" | M2 plan, lines 85–86 | As ADR-0014, lines 32–33: measured in autocommit, and inside a transaction a reset commits nothing (O7d). |
| "this thread's interrupts wait for it, and M3's interrupt …" | M2 plan, line 155 | The concurrency session's. |
| "A refused SQL's first statement has still been prepared" | M2 plan, line 173 | Measured before (m2-review, 18). |

## Traps ([traps.c](traps.c))

Each is a minimal probe, reproduced twice in each run, each time on a fresh file. Both runs on
both libraries gave the same output.

- **T1. A refused `BEGIN IMMEDIATE` or `BEGIN EXCLUSIVE` still takes its lock.** Inside a deferred
  transaction that had read nothing, it failed with "cannot start a transaction within a
  transaction". Even so, `txn_state` went from NONE to WRITE. After the refused `BEGIN IMMEDIATE`,
  another connection's `BEGIN IMMEDIATE` answered 5, "database is locked". After `BEGIN EXCLUSIVE`,
  its SELECT did, at prepare. Both were released by `ROLLBACK`.
- **T2. After `ROLLBACK`, an open SELECT goes on answering rows, with no error.** `ORDER BY` answered
  the rolled-back rows 4 and 5. A rowid scan answered 2, 3, DONE.
- **T3. `COMMIT` answers `SQLITE_BUSY` with no other connection.** That happens while an
  `INSERT … RETURNING` on the same connection has answered one row. The code is 5, extended 5, the
  code contention gives, though no retry can succeed until the statement is finished or reset.
- **T4. `PRAGMA foreign_keys = enable`, and `= DEFAULT`, turn foreign keys off, and
  `PRAGMA foreign_key = ON` does nothing.** None of the three is an error.
- **T5. Inside a transaction, `PRAGMA foreign_keys = ON` does nothing, and says nothing.**
  `journal_mode = WAL` fails before the transaction has written, and answers `delete`, with no
  error, after it has. `synchronous = OFF` is refused at prepare in both cases.
- **T6. A statement whose re-prepare failed reports a stale schema.** A held INSERT answered "table
  t has 3 columns" after another connection had rebuilt the table with 4. It said 4 only after a
  SELECT on its own connection had read the table.
- **T7. `last_insert_rowid` names a row that doesn't exist.** After an INSERT that failed at its
  second row, it was 50, the first row's, which was rolled back. After `BEGIN`, an INSERT and
  `ROLLBACK`, it was 60.
- **T8. Whether `SQLITE_FULL` ends the transaction turns on one function call.** With
  `max_page_count` at the page count, `INSERT INTO b SELECT x FROM src` ended the transaction, and
  its earlier row was gone. `INSERT INTO b SELECT lower(x) FROM src`, the same rows, undid only
  itself, and the row stood. The call gives the statement a statement journal (txn-special F1,
  F2).
- **T9. `PRAGMA soft_heap_limit` and `hard_heap_limit` are process-wide.** A value set through one
  connection was read through another. `PRAGMA hard_heap_limit = 0` and `= 90000000` each left
  60000000. With the hard limit set, `PRAGMA soft_heap_limit = 0` answered 60000000.
- **T10. `sqlite3_error_offset` after `sqlite3_exec` counts from the failing statement,** 0, not
  from the script, where the token is at byte 27.
- **T11. `sqlite3_stmt_busy` is 1 after an `EXPLAIN` or `EXPLAIN QUERY PLAN` answers DONE.** It is
  0 after `SELECT 1` does, and 0 after a reset.
- **T12. A NOMEM caused by a heap limit left in force can turn a statement rollback into a
  transaction rollback.** Inside `BEGIN`, after one row,
  `INSERT INTO b SELECT randomblob(100000) FROM src LIMIT 3` answered 7 by both methods. With
  `sqlite3_hard_heap_limit64(sqlite3_memory_used() + 1000)` in force across the step, the
  transaction ended and the row was gone. With only the statement's first allocation of at least
  100,000 bytes failing, through an `SQLITE_CONFIG_MALLOC` wrapper, the transaction stayed open
  and the row stood (txn-special N3, M5, M6).
- **T13. A column read's NOMEM ends the transaction at the statement's reset.** Inside `BEGIN`,
  after one row, `SELECT hex(x) FROM src` was stepped to a row. `sqlite3_column_text16`, under the
  heap limit around that one call, answered NULL with extended 7, and autocommit stayed 0. The
  `sqlite3_reset` after it answered 7, autocommit went to 1, and the row was gone (txn-special
  G2, G3).

## Every difference between the two libraries

1. **Build options** (options.c): Guix's has `SECURE_DELETE`, the eight `ENABLE_*` options listed
   above, and `MAX_FUNCTION_ARG=1000` against 127. Their compilers differ.
2. **`secure_delete`'s default:** 1 on 3.53.1, 0 at the floor (pragmas P1.10, P3, P9). Everything
   else pragmas.c read was alike, P12 and P13 among it.
3. **Statement memory** (cache K1): sizes, lookaside slots, hits and misses differ, and the
   pattern doesn't. A `PERSISTENT` statement of the probe's shape took 2,280 bytes on 3.53.1 and
   1,752 on 3.45.1.
4. **Entry points** (entry-points.sps): `sqlite3_db_status64` and `sqlite3_setlk_timeout` are in
   3.53.1, not the floor. `sqlite3_normalized_sql` is in neither.
5. **Timings:** 3.53.1's medians were −1% to 18% above the floor's in C, and −2% to 10% through
   Chez, over both runs.

Nothing else differed: `txn`, `txn-errors`, `txn-special`, `txn-open-stmts`, `counters`, `script`,
`b5` and `traps` are identical after their version lines, and `cache` past K1. So are the cost
probes' non-timing lines. In `txn-special` that includes the page count of 15 and the sizes of the
failed allocations, 56 and 100,000 bytes.

## Not measured

- **`SQLITE_OMIT_AUTORESET`** (ADR-0014, line 30): no such build here. What one does is read from
  the floor's source instead (B5).
- **`SQLITE_IOERR` ending a transaction:** it needs a fault-injecting VFS, which no probe here
  builds. By the floor's source, IOERR always ends the transaction (`sqlite3VdbeHalt`).
- **`sqlite3_interrupt` from another thread:** the concurrency session's. Here it was called from
  a progress handler on the connection's own thread (txn-special I1 to I4).
- **`COMMIT` answering BUSY under another connection's read, and the busy timeout around
  `BEGIN IMMEDIATE`:** contention, the concurrency session's.
- **Whether a re-prepared PRAGMA statement applies its setting again:** no case here re-prepared a
  PRAGMA.

## Where this contradicts the records

Nowhere. Each record's claim holds under the conditions it was measured in. The next section
lists the ones whose wording drops those conditions.

## Wording the records could sharpen

1. **ADR-0014, lines 32–33:** "an `insert … returning` stepped once commits at its reset or
   finalize." The claim sits in a context bullet whose measurement was the autocommit case
   ([research/m2-review/](../../m2-review/), 1: "An autocommit `insert … returning`"), and in that
   context it holds. Line 50 already says that only the last of two finalizes commits. **Inside a
   transaction, the reset committed nothing** (txn-open-stmts O7d). It answered 0, the
   transaction stayed open at WRITE, the other connection saw neither row, and `ROLLBACK` removed
   both. "In autocommit" would carry the condition into the sentence. The M2 plan, lines 85–86,
   words it the same way. R1's reason for raising a finalize's failure holds in autocommit.
2. **ADR-0014, lines 46–47:** "preparing a PRAGMA changes the connection, unstepped: `cache_size`,
   `encoding` and `case_sensitive_like`." m2-review, 5, measured that on an empty `:memory:`
   database. **On a file holding a table, `encoding` didn't change at prepare** (P3), nor at a
   step (P1.32), nor at a VACUUM (P12.3). P3 confirms `cache_size` and finds 22 more settings that
   change at prepare. It didn't measure `case_sensitive_like`, which has no read form.
3. **ADR-0014, lines 48–49 and 142–143:** "when another connection adds or drops a column." The
   same connection's DDL changes the count too (K2.2).
4. **ADR-0014, line 30, and the M2 plan's Q4, lines 69–70:** `SQLITE_OMIT_AUTORESET`'s MISUSE.
   By the floor's source, such a build answers MISUSE after DONE, the record's context, but resets
   and reruns after BUSY or LOCKED (B5).

## Questions for M3's plan

Questions, not decisions. Each names the measurement that raises it.

**`with-transaction`**

1. **What should it do when the error has already ended the transaction?** These leave autocommit
   at 1:
   - `OR ROLLBACK` and `RAISE(ROLLBACK)` (txn-errors E4, E7, E8);
   - INTERRUPT in any write (txn-special I1, I2);
   - NOMEM or FULL in a statement with no statement journal: a SELECT that reads a table, a
     one-row INSERT, or an `INSERT … SELECT` or UPDATE that calls no function and checks no
     constraint (N1, M1, M4, F1, F5, F6);
   - a column read's NOMEM, at the reset or finalize after it (G2, G3).

   Then `ROLLBACK` fails, "no transaction is active", and `RELEASE` or `ROLLBACK TO` fails, "no
   such savepoint" (E5). Should it read `sqlite3_get_autocommit` before its rollback? Which
   failure reaches the caller: the body's, the rollback's, or both?
2. **What should it do when the error left the transaction open?** These undo only their
   statement:
   - constraints and runtime errors (E1 to E3, E9, E12, E14), and a refused prepare (E24, E25);
   - NOMEM and FULL in a statement with a statement journal (F2 to F4, F7, F8, M3, M5);
   - any error in a statement that reads no database (N2, M2, G4 to G6, I4);
   - INTERRUPT in a SELECT (I3).

   Does "rollback on a raise" (brief, line 120) apply when the body catches the error itself and
   returns normally?
3. **What if the body catches an error that already ended the transaction, and carries on?** Its
   later writes autocommit one by one. Another connection saw each at once, and the final `COMMIT`
   failed with "cannot commit - no transaction is active". The rows before the error were gone,
   and the rows after it stood (txn-special L1). What should `with-transaction` do: check
   autocommit before its `COMMIT` and raise, or more? Nothing it does at the end can take back the
   writes that autocommitted.
4. **Must every failure path read `sqlite3_get_autocommit`?** Whether a failure ended the
   transaction can't be told from its code or the statement's text: F1 against F2, N1 against
   N2, G2 against G4. Should every raise inside `with-transaction`, and its own `ROLLBACK`, go
   through that read?
5. **Can M3's tests cause NOMEM by the process-wide heap limit at all?** The method changes the
   outcome: under a limit left in force across the step, the multi-row INSERT ended the
   transaction, and with one failing allocation it didn't (N3 against M3 and M5; M6; trap T12).
   The limit is process-wide (P2, T9). The other method needs `sqlite3_config` before SQLite
   initialises, which brief §2.8 keeps out of the library. Which failures can a suite cause
   faithfully, and how?
6. **What should it do when its `COMMIT` fails and leaves the transaction open?** A deferred
   foreign key fails at `COMMIT` with 787 (E13). An unfinished write statement makes `COMMIT`
   answer 5 (O7, T3). Roll back, or leave it for the caller? And should that 5 be `&sqlite-busy`,
   which ADR-0013 gives every primary BUSY, when no wait can make it succeed?
7. **What should it do with its connection's statements still mid-row at its end?** A RETURNING
   statement blocks `COMMIT` (O7). A SELECT survives `ROLLBACK` and answers removed rows (O2, T2),
   or answers 516 after a schema change (O4b). Should `query` and the fold always finish or reset
   their statements before returning? Should `with-transaction` reset its connection's busy
   statements, or refuse to end while any is busy?
8. **What should the outer level issue, and with which mode?** `BEGIN` takes a mode, and
   `SAVEPOINT` outside a transaction begins a deferred one with none (S1). Should it read
   `sqlite3_get_autocommit` to decide? A refused `BEGIN IMMEDIATE` still takes the write lock
   (X1, T1), so relying on the error leaves a lock behind.
9. **Should it name its own savepoints?** Names fold ASCII case only, accept string literals and
   keywords, and a reused name reaches the most recent (S8, S9). If callers name them, how is a
   name quoted and checked?
10. **Rolling back a nested level takes `ROLLBACK TO` then `RELEASE`,** since `ROLLBACK TO` leaves
    the savepoint open (S2, S3, S4). Is that the sequence it should use?

**The counters**

11. **When should `execute!` read the counters, and what should it answer?** For RETURNING,
    `changes64` moves only at DONE or reset (C12). After a failure, `last_insert_rowid` can name a
    rolled-back row (C5, C15, T7). It doesn't move for WITHOUT ROWID or upsert `DO UPDATE`, so a
    stale value can't be told from a new one (C8, C11). Should `execute!` answer
    `last_insert_rowid` at all, or only `changes64`? `total_changes64` counts trigger, cascade and
    rolled-back rows (C9, C10, C15); should it be offered?

**The settings list**

12. **Which settings may the list hold?** Some persist in the file: `journal_mode=wal`,
    `user_version`, `application_id`. Some are process-wide: the heap limits (P2, T9). Some wait
    for a VACUUM once the file holds a table: `page_size` and `auto_vacuum` (P12.1, P12.2). One does
    nothing there even then: `encoding` (P12.3). Some fail, or do nothing, inside a transaction
    (P6). Is the list an allowlist of per-connection settings, with the rest refused?
13. **Should the list refuse settings deferred to a VACUUM?** On a file holding a table, a
    read-back straight after the set sees the old value, so a checked `page_size` or `auto_vacuum`
    would fail its check. Yet the next VACUUM applies it, and it stays (P1.30, P1.31, P12). Refuse
    them, check them another way, or run the VACUUM?
14. **What happens when the list runs while the connection has an active statement?** In
    autocommit, beside a SELECT of the same connection holding a row, `journal_mode = wal` failed at
    its step, "cannot change into wal mode from within a transaction". It succeeded once the
    SELECT was finalized, and `truncate` succeeded beside it (P13). At open no statement exists.
    May the list run at any other time, and if so, must it refuse while a statement is busy?
15. **Does the list take SQL text, or Scheme values that it writes as canonical SQL?** SQLite
    coerces bad values silently (P4). A bad word turns a boolean off, `synchronous = 4` reads back
    4, and `busy_timeout = 2147483648` gives 0. A read-back catches some of these and not others.
16. **How is each read-back compared?** Answers come back as lower-case TEXT for `journal_mode`
    and `locking_mode`, and as INTEGER for `synchronous`, `temp_store` and `secure_delete` (P1,
    P8). Some set forms answer a row and some don't, and `busy_timeout`'s column is `timeout`.
    Each setting seems to need its own reader, and `pragma_NAME` tables can serve as one (P9).
17. **What should `journal_mode=wal` on `:memory:` do?** It answers `memory` (P11): raise, or
    accept?
18. **Is a setting the list doesn't know refused before SQL?** SQLite ignores unknown and
    misspelt names (P5, T4).

**The statement cache**

19. **What should the cache do with a statement whose column count changed?** It changes only at
    the step that re-prepares, and `STMTSTATUS_REPREPARE` counts it (K2.2, K2.7). Should
    `query` read the column names after the first step, never at prepare, and is the counter
    worth checking?
20. **Should the cache evict a statement whose step failed?** After `DROP TABLE` it fails with 1,
    and runs again in a new shape if the table comes back (K2.4, K2.8).
21. **What should the cache do with a statement whose re-prepare failed?** It stays stale
    through repeated steps until another statement reads the schema. After another connection
    rebuilt the table with 4 columns, a held INSERT answered "table t has 3 columns" at two steps
    running, and "4 columns" only after a SELECT on its own connection had read the table (T6,
    K2.10). Does the cache evict it, or force a schema read?
22. **Should cached statements be prepared `PERSISTENT`, and how many should it hold?** Without
    the flag, 10 held statements took 90 to 116 of the 123 lookaside slots, and 50 filled them.
    With it, each costs 1.8 to 2.3 KB of heap (K1), and each prepare took 0.36 to 0.81 µs longer,
    while a reuse round was within 50 ns either way (cost). With flags 0, reuse saves 1.9 to
    2.3 µs a statement through the probe's FFI path, a lower bound for the library's (cost).
23. **How does the cache know a statement is in use, by a fold not yet finished?** `stmt_busy` says
    1 for EXPLAIN after DONE (T11). Should the cache trust ADR-0014's states instead?
24. **Close must finalize the cache's statements before `sqlite3_close`,** which answers 5
    otherwise (b5 V2). ADR-0014's close already finalizes what it tracks; does the cache need
    anything more?

**The script runner**

25. **Should a script run through `sqlite3_exec`, or a prepare loop through `prepare-statement`?**
    The loop goes through ADR-0014's checked prepare, and knows each statement's text and place in
    the script. `sqlite3_exec`'s offset counts from the failing statement (X5, T10).
26. **What should a script do with statements that answer rows: drop the rows, as `sqlite3_exec`
    does (X7), or refuse the statement?**
27. **What should a failing script do with a transaction it opened, and one it didn't?** Both
    runners leave it open, or already ended (X2, X3, X4, X16).
28. **Should the raised condition carry the failing statement's index or byte offset in the
    script?**
29. **A runner must prepare each statement only after the one before it has run,** since a
    PRAGMA's prepare already applies it (P3). Both measured runners do. Is that the rule?

**Elsewhere**

30. **Should M3 bind only what the floor has?** `sqlite3_db_status64` and `sqlite3_setlk_timeout`
    are 3.53.1's alone (entry-points).
31. **If M3 shows `sqlite3_expanded_sql`, in an error or a log, does it say what that text isn't?**
    It loses digits, writes `Inf`, cuts at NUL, and is NULL over the length limit (K4).
32. **Is `stmt_readonly` used to route anything?** It is 1 for `BEGIN`, `COMMIT`, `ATTACH` and
    `PRAGMA foreign_keys = ON`, and 0 for `PRAGMA journal_mode` read alone (K3).
