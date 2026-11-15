# M2 slice 3 mutation log: statements

Evidence that each rule the slice's suites claim to guard fails through the property it names
([M2 plan](2026-11-14-m2-plan.md), §4.1, §4.2, §4.8 and §5's slice 3; ADR-0014). Format of
[the M2 slice 2 log](m2-slice-2-mutation-log.md).

The slice, part A, is `(chez-sqlite3 private statement)`, new: the statement record, the accessor
`call-with-statement-handle`, prepare, step, reset, finalize, `call-with-statement`,
`statement-sql`, `parameter-count` and `column-count`. And `(chez-sqlite3 private connection)`'s
tracking: the live statements, `track-statement!`, `untrack-statement!`, `tracked-statements`,
`first-finalize-failure`, `check-database-owner`, and the close that finalizes. The suites are
`tests/test-statement.sps`, `tests/test-statement-block.sps` (the four `__collect_safe` calls by
behaviour), `tests/test-statement-tail.sps` (the tail scan against SQLite's prepare) and, from the
review, `tests/test-statement-sections.sps` (decision 10's "change together" under two engines), with the
leaks plant `tests/memory-plant-statement.sps`, held by `check-memory-gate`'s cases `a` and
`b statement`. An Opus agent built it test first from the maintainer's brief.

Every mutation ran in its own copy of `src/` and `tests/`, made under the worktree's git-ignored
`build/m2s3/mut/`, and its suites ran from inside the copy, with the worktree's SRFI libraries,
outside the gate. A driver refused any edit whose old text did not occur exactly the stated number
of times (each did), and any that changed nothing. The plant's two mutations ran
`make check-memory-gate` in whole copies of the worktree, `build/m2s3/gate/`. The counts below
are read from the suites' own output (`# of expected passes`, `# of unexpected failures`), never
by eye, and come from one run against the final tree. The driver and the definitions are in
`build/m2s3/`, not the repository. The review's fixes (below) ran from `build/m2s3-fix/`, with the
same driver pointed at `build/m2s3-fix/mut/`, and the first 80 again from `build/m2s3-fix/oldmut/`.

## The red runs

| Suite | Red run | Against | Green run |
|---|---|---|---|
| `test-statement` | 4 passed, 56 failed | a stub `statement.sls`: every export, none doing its work | 60 passed |
| `test-statement` | 30 passed, 30 failed | the real `statement.sls` over M1's `connection.sls`, its new exports stubbed: no tracking, no finalizing close | 60 passed |
| `test-statement-block` | 5 passed, 1 failed, in each of four copies | each call bound plain, C01 to C04 | 6 passed |
| `test-statement-tail` | 4 passed, 5 failed; 3 and 6; 3 and 6 | the scan skipped, from 0, from past the tail: TS1 to TS3 | 9 passed |
| `test-statement-sections` | 3 passed, 1 failed, in each of three copies | the tracking, the state's change and the untracking each made after their section, R01, R03 and R06 | 4 passed |
| `test-native` | 69 passed, 1 failed | `c-string->string` without the U+FEFF restored, F4 | 70 passed |

The 4 rows that passed against the stub: the load, the counts once loaded, the export list (the
stub exported the same names), and `first-finalize-failure`, which is `connection.sls`'s. E01, E02,
E03 and T06 watch them fail. The suite grew to 68 rows after the red runs, and to 75 with the review's fixes; each row added was
watched failing by the mutations named in its place below. Every row of the three suites has
failed under at least one mutation or red run.

Final green runs, on Guix's 3.53.1 and on the floor, 3.45.1, alike: `test-statement` 75 passed,
`test-statement-block` 6, `test-statement-tail` 9, `test-statement-sections` 4, `test-native` 70;
`make test` 34 of 34 on both, `check-memory-gate` in all 58 cases.

## Measured first

Through bare FFI, on Guix's 3.53.1 and the floor, 3.45.1 (`build/m2s3/probe-*.sps`); the outputs
differ in the version line and by a millisecond.

- **The step's block** (`probe-block.sps`): a plain insert stepped under another connection's
  read, with `busy_timeout = 1500`, waited 1502 ms and answered 5, "database is locked"; its
  finalize answered 5 again, and the table kept its row. ADR-0011's amendment expected it.
- **All four, plain and `__collect_safe`** (`probe-block.sps`): a prepare on a fresh connection
  under `begin exclusive`, that step, and a reset and a finalize of an `insert … returning`
  stepped once under a read, each waited 1502 ms and answered 5. Bound plain, another thread's
  `collect-rendezvous` took 1402 or 1403 ms and ended after the call; bound `__collect_safe`, 0 or
  1 ms, while the call was still blocked.
- **The close's failure** (`probe-close.sps`): with every statement finalized, a backup reading
  from the connection makes `sqlite3_close` answer 5. M2's own entry points can't: SQLite's
  documentation names unfinalized statements, unfinished backups and open BLOB handles, and M2
  binds neither of the last two, so the row binds `sqlite3_backup_init` itself, as
  `test-connection` does. With both, a finalize that answers 5 and then a close that answers 5:
  once the backup is finished the close answers 0.
- **Two inserts stepped once under a read:** whichever is finalized second answers 5, prepared
  first or not; both are rolled back. So the failure's SQL names the statement finalized last.
- **The codes** (`probe-codes.sps`): a unique violation's step 2067, then reset 2067, reset 0,
  finalize 0; a read-only connection's insert prepares, steps 8 and finalizes 8; under a read
  with no timeout, an insert's step answers 5 at once, and an `insert … returning`'s reset 5,
  then reset 0 and finalize 0; prepare's code is extended (257 for a missing collation).
  `sqlite3_error_offset` is 10 for `select 1, nosuchcol`, 13 bytes after `é`, 0 for
  `selectx 1`, and −1 at the end of the SQL, for a missing table, for a missing collation, and
  (the block suite) for a busy prepare. The suite reads each on a connection's first prepare and
  on a used one, alike.
- **The tail oracle's cost** (`probe-cost.sps`): 2,000 pairs of prepares took 3 ms plainly and
  323 ms under Valgrind. The suite's 20,602 inputs, three prepares each, take 0.4 s plainly and
  21.1 s under the gate, make's own time included, so it covers every two characters over 130.

## The mutations

**92 mutations, 88 caught, 4 survived;** each survivor is argued below. The first 80 were rerun
against the tree as the review's fixes leave it, with the same driver, and the new 12 are in
"The review's fixes" below. Each row names the suites that failed and how many of their rows; a
suite run and not named passed whole. Baselines: `test-statement` 75, `test-statement-tail` 9,
`test-statement-block` 6, `test-statement-sections` 4, `test-native` 70, `test-connection` 63.
`test-connection` ran beside every mutation of `connection.sls`, and failed only under D02.

### Decision 3's checks, removed or reordered

| Mutation | Guards | Failed |
|---|---|---|
| D01 | the accessor's statement check dropped | statement 3: every verb's not-a-statement row, the accessor's own checks, the depth rows' not-a-statement |
| D02 | `check-owned`'s owner comparison dropped | statement 5: the wrong-thread rows; connection 6 |
| D03 | a finalized statement let through to its procedure | statement 13 |
| D04 | the finalized check before the thread's | statement 2: wrong-thread on a finalized statement, and in every state |
| D05 | the state check before the thread's | statement 1: wrong-thread in every state (added for it) |
| D06 | `finalize-statement!` makes the third check | statement 11 |
| D07 | `finalize-statement!` skips the thread check on a finalized statement | statement 2: the same two wrong-thread rows |

### The state rules loosened

| Mutation | Guards | Failed |
|---|---|---|
| S01 | `step!` allowed in `done` (`statement-state.sls`) | statement 4 |
| S02 | `step!` allowed in `failed` | statement 4 |
| S03 | the binds allowed in `row` | statement 1: the accessor's 12-by-5 table |
| S04 | the column reads allowed in `ready` | statement 2: that table, and a depth row's refusal |
| S05 | a refused verb's procedure run | statement 7 |
| S06 | a refusal moves the state to `ready` | statement 4 |
| S07 | the procedure's new state ignored | statement 23 |
| S08 | `finalized` taken as a new state | statement 1: the not-a-live-state row (added for it) |
| S09 | any symbol taken as a new state | statement 1: the same |

### Each raise moved inside a section

| Mutation | Guards | Failed |
|---|---|---|
| I01 | the accessor's refusals raised inside `critical-section` | statement 5: its depth rows |
| I02 | `step!`'s failure | statement 1: its depth row |
| I03 | `reset!`'s own failure | statement 1 |
| I04 | `finalize-statement!`'s own failure | statement 1 |
| I05 | prepare's `&sqlite-error` | statement 1 |
| I06 | prepare's no-statement refusal | statement 2: prepare's and `call-with-statement`'s depth rows |
| I07 | `&sqlite-closed` raised inside the accessor's procedure | **none: survived** (below) |
| I08 | `call-with-statement`'s finalize failure raised in its critical after thunk | statement 2: its depth row, and the raise that must not be masked |
| I09 | the close's finalize failure raised inside its section | statement 1: its depth row |

### The four `__collect_safe` calls made plain

| Mutation | Guards | Failed |
|---|---|---|
| C01 | `sqlite3_prepare_v3` | statement-block 1: prepare's row, the collection 2,995 ms |
| C02 | `sqlite3_step` | statement-block 1: step's row, 2,994 ms |
| C03 | `sqlite3_reset` | statement-block 1: reset's row, 2,995 ms |
| C04 | `sqlite3_finalize` | statement-block 1: finalize's row, 2,994 ms |

Each failed by its bound, 1,500 ms, against a block of 4,000. The flag the blocked thread sets as
its call answers read unset after every one of the four collections: bound plain, the thread joins
the collection before it can set the flag, so only the time tells (a trap, below).

### The tracking and the close

| Mutation | Guards | Failed |
|---|---|---|
| T01 | prepare's `track-statement!` dropped | statement 32 |
| T02 | finalize's `untrack-statement!` dropped | statement 4: the tracked lists, `call-with-statement`'s, the abandoned engine's |
| T03 | `track-statement!`'s body dropped | statement 32 |
| T04 | `untrack-statement!`'s body dropped | statement 4 |
| T05 | the close's order reversed, newest first | statement 4: the tracked order, the two inserts (the older's SQL raised), the synthetic entries |
| T06 | `first-finalize-failure` answers the last | statement 3: its pure row and the two synthetic-entry rows |
| T07 | the close's outcomes not put back in order | statement 2: the two synthetic-entry rows (added for it) |
| T08 | the close's table not cleared | statement 3 |
| T09 | a finalizer's raise let out of the close's section | statement 1: the raising entry |

### Offsets, checks and nByte

| Mutation | Guards | Failed |
|---|---|---|
| O01 | prepare's offset left in bytes | statement 1: the failed prepares, −1 refused by `make-sqlite-error` |
| O02 | −1 kept as −1 | statement 1: the same |
| O03 | the tail's index left in bytes | statement 1: 13 for `select 'é'; x`, not 12 |
| N01 | the U+0000 check dropped | statement 4: native's refusal came instead, irritants `((kind string))` |
| N02 | the length check's call dropped | **none: survived** (below) |
| N03 | the limit 2³¹−1 bytes | statement 1: the numbers row |
| N04 | an inexact length accepted | statement 1: the numbers row |
| B01 | nByte without the NUL | **none: survived** (below) |

### The tail scan

| Mutation | Guards | Failed |
|---|---|---|
| TS1 | the scan skipped | statement 4; statement-tail 5 |
| TS2 | the scan from 0 | statement 64; statement-tail 6 |
| TS3 | the scan from one past the tail | statement 1; statement-tail 6 |

### The plants (the M2 plan, §4.8)

| Mutation | Guards | Failed |
|---|---|---|
| P01 | the assessment's: prepare's out-parameter block, counted, never freed | statement 34; statement-tail 1 |
| P02 | the assessment's: a close that stops after the first statement, an `or` over codes | statement 20 |
| P03 | `reset!` drops its own failure | statement 3 |
| P04 | `finalize-statement!` drops its own failure | statement 6 |
| P05 | the close drops the first finalize failure | statement 4 |
| P06 | the leaks plant finalizes its statement and closes its connection | `check-memory-gate`: `a plain` (its counts line) and `b memory-plant-statement` (`make test-memory exited 0`) |
| P06b | the leaks plant finalizes its statement, its connection still dropped | `check-memory-gate`: `a plain` alone, the line's counts `(statement . 0)`. Valgrind still saw the connection, as it must |

### The rest

| Mutation | Guards | Failed |
|---|---|---|
| X01 | `statement-sql` hands out the record's string | statement 1 |
| X02 | prepare keeps the caller's string, uncopied | statement 3 |
| X03 | finalize leaves the freed handle in the record | statement 31 on the first runs. On the review's rerun it hung on a freed statement again, and the 120 s timeout killed it with 8 rows named failed: caught, but its count is not reproducible, since the freed handle is read |
| X04 | finalize not counted down | statement 38 |
| X05 | prepare not counted | statement 57 |
| X06 | the refused statement, more than one, never finalized | statement 32 |
| X07 | the NULL statement checked before the failure | statement 5 |
| X08 | `reset!` leaves the state | statement 7 |
| X09 | `step!` leaves the state | statement 22 |
| X10 | `reset!` raises a failed step's repeat | statement 3 |
| X11 | `finalize-statement!` raises the repeat | statement 10 |
| X12 | the finalize failure raised over the close's own | statement 1: the backup row |
| X13 | untracked statements counted before the tracked are finalized | statement 27 |
| X14 | the no-op of a finalize on a closed connection dropped | statement 1 |
| X15 | that no-op given to every verb | statement 2 |
| X16 | `column-count` reads the parameter count | statement 4 |
| X17 | `parameter-count` reads the column count | statement 3 |
| X18 | `call-with-statement`'s procedure not checked first | statement 1 |
| X19 | its finalize failure raised over the procedure's | statement 1 |
| X20 | its finalize failure never raised | statement 3 |
| X21 | its statement learnt after the prepare's section, not in it | statement 1: an engine abandoned at its first expiry left a statement at fuels 23, 25 and 26 (added for it) |
| X22 | the SQL checked before the database | statement 2 |
| X23 | step's message read before the step | statement 2: the message against `sqlite3_errmsg` read straight after (added for it): "not an error" where SQLite said "UNIQUE constraint failed: t.x". It compares two readings, never a message's words |
| E01 | an export more | statement 1: the export list |
| E02 | `CHEZ_SQLITE3_LIBRARY` naming no file | statement 65: the load row, and every row after it |
| E03 | the library body counts a statement | statement 39; statement-tail 2; statement-block 6, every row now that each asserts the counts |
| E04 | slice 1's 3-byte literal renamed | statement-tail 2: the literals' count and their oracle row |

## The survivors

| Mutation | Why it is equivalent |
|---|---|
| B01 | nByte without the NUL. SQLite reads to nByte or the first NUL, whichever comes first, and `call-with-c-string` writes the NUL after the bytes, so both prepare the same bytes and leave the same tail. Slice 2's B02 is the same equivalence from the other side; slice 2's review measured that without the NUL SQLite copies the SQL at every prepare, a cost no row sees. |
| N02 | **Not equivalent: unexercised for its cost under the gate.** The call to the length check dropped from `checked-sql`. Only SQL longer than 2³¹−2 bytes of UTF-8 reaches it, and a Chez string of 4-byte characters holds 2³¹−1 bytes of UTF-8 in 2 GiB (the review's correction: this log said 8 GiB or more). On 536,870,914 characters, run plainly, the tree refuses it with `(sql-too-long 2147483647)` in 8.5 s, and N02 hands it to SQLite, which answers `toobig`, in 74.8 s (rerun for this log, `build/m2s3-review/probe-long-sql.sps`; the review measured 8.1 s and 73.9 s). The row exists, and the mutant fails it, but a row of 2 GiB, 75 s plainly and several times that under Valgrind, doesn't fit the gate's budget. `sql-length-fits?`, the check itself, is held on numbers at the boundary (N03, N04). The call is one `unless` form, held by that probe, run by hand. |
| R10 | `(sealed #t)` dropped from the statement record, `(opaque #t)` kept. A sealed type can't be extended, so sealing only matters to code that can name the type to make a child of it. The record is opaque, so `record-rtd` raises on a statement (R09 and its row hold that), and nothing outside the library can reach the type; inside, nothing extends it. While the record is opaque, sealing it changes nothing a caller or a row can see. Held by R09's row: should opacity go, R10's fault is reachable and sealing has no row of its own. `test-libsqlite3-info` argues the same for its record. |
| I07 | `&sqlite-closed` raised inside the accessor's procedure rather than answered as data. `call-with-open-handle` catches whatever its procedure raises inside the section and raises it again after, the same object (ADR-0012, amended; `test-connection`'s depth rows hold it), so a caller's handler still runs at depth 1. Only a raise outside that procedure, in a section of the statement library's own, can reach a handler with interrupts disabled: I01 to I06, I08 and I09. |

## Findings

- **A flag the blocked thread sets can't show that a plain call returned before a collection.**
  Bound plain, the blocked thread returns from C and joins the pending collection before it runs
  the `set!` after the call: the flag read unset after all four plain collections (C01 to C04).
  The bound on the collection's time is what tells. Reproduced by C01 to C04, each with the
  block suite's own flag.
- **The floor's statement plant reads exactly as its connection plant does.** On 3.45.1 the
  loss record is 57,432 bytes, 792 direct and 56,640 indirect in 24 blocks, the M1 connection
  plant's numbers; on 3.53.1 the statement adds 5,152 bytes in 19 blocks, 67,280 against
  62,128. So Valgrind can't tell a leaked statement from its connection at the floor, and the
  plant's own line, the counters', is what holds that the statement was counted (P06b).
- **R6RS string escapes take their semicolon.** `"select 1;\xFEFF;"` is `select 1;` and U+FEFF,
  with no second semicolon, and `"\xFEFF "` is a reader error. The tail suite spells its edges
  with names, `{bom}`, `{vt}`, `{nel}`, `{nbsp}` and `{e}`.
- **A prepare-statement takes a string,** so the brief's every 1-byte and 2-byte tail over a
  14-byte alphabet can't all be SQL: bytes 80 to FF alone, and `EF BB` without `BF`, aren't
  characters. The oracle takes characters: every one of a byte, every two and three over a
  14-character alphabet (the ten ASCII bytes the rules name, `A`, U+FEFF, U+0085 and U+00A0),
  every two over 130, and the 590 inputs of slice 1's literals that are strings. Slice 1's
  byte-level oracle holds the scan on every byte.

## The review's fixes

An adversarial review of the slice (PR #18, at `1eff5be`) found nine things. Each was fixed test
first: the row written, watched failing against a mutant that restores the fault, in a whole copy
of the tree, run from inside the copy, then made to pass. The mutants are in `build/m2s3-fix/mut/`
(`build/m2s3-fix/defs.py`, `mut.py`), the probes in `build/m2s3-review/` and `build/m2s3-verify/`.
Every mutant below ran on Guix's 3.53.1 and on the floor, 3.45.1, with the same counts.

| Mutation | What | Failed |
|---|---|---|
| R01 | the prepare's tracking made after its section | `test-statement-sections` 1 (prepare against close, fuels 27 to 30: the close refuses with `untracked-statements`, the connection stays open); `test-statement` 75 passed |
| R03 | the accessor's state change made after its section | `test-statement-sections` 1 (step against step, fuels 25 and 26: the done insert runs again, 2 rows); `test-statement` 75 passed |
| R06 | the finalize's untracking made after its section | `test-statement-sections` 1 (finalize against `tracked-statements`, fuels 34 to 39: a finalized statement is listed); `test-statement` 75 passed |
| R09 | `(opaque #t)` dropped from the statement record | statement 1: the opacity row, `record-rtd` answers instead of raising |
| R10 | `(sealed #t)` dropped | **none: survived** (above) |
| F3 | the accessor hands its procedure `""` as the SQL | statement 9: the new row, and every row whose failure carries its SQL, since step and reset now read it from the argument |
| F4 | `c-string->string` drops a leading U+FEFF again | `test-native` 1 (the block `EF BB BF 61`); statement 1 (the trigger's message) |
| F8 | a finalize that leaves its statement counted | `test-statement-block` 5 of 6: the four blocking rows and the last. Against the suite as it stood, 1 of 6: only the last, "every count is zero at the end" |
| D1 | `column-count` answers its first reading for ever | statement 1 (the `alter table` row) |
| D2 | `step!` answers done whatever SQLite said | statement 26; the new row for the refused commit among them |
| D3 | `reset!` clears the bindings | statement 1 (the bindings row) |
| D4 | `call-with-statement`'s failed prepare drops the offset | statement 2: the new row, and the existing row of `call-with-statement`'s checks, which already held it |

**12 mutations, 11 caught, 1 survived.**

1. **Decision 10's "change together" was held by no row.** R01, R03 and R06 each passed
   `test-statement` whole. `tests/test-statement-sections.sps` has three sweeps, each an engine A
   that expires once and a second thread of control B that runs at A's first expiry, on the same
   thread, at every fuel from 1 to 60: prepare against close (the close answers, the connection is
   closed, A's statement is finalized by it or A's prepare raised `&sqlite-closed`, every count is
   zero); step against step on one insert (one row, the statement done, the other step refused
   naming done); finalize against `tracked-statements` (a statement is listed exactly when it is
   not finalized; afterwards neither listed nor live). **The fuel range:** the windows fall at 25
   to 39 on both libraries (R01 27 to 30, R03 25 and 26, R06 34 to 39), found by sweeping the
   mutants; 60 clears the last with 21 to spare and is the range the other engine sweeps use. The
   suite runs in 0.2 s plainly and 9.3 s under the gate, make's own time included, so it needs no
   split.
2. **Nothing held the statement record's opacity.** R09 passed every suite, and through
   `(chez-sqlite3)` alone a probe read the raw pointer. The row asserts that `record-rtd` of a
   genuine statement raises from `record-rtd`, and `record?` says no, as `test-libsqlite3-info`'s
   row does for its record. R10 is argued above.
3. **The accessor gave its procedure no way to the SQL.** Read after the section, `statement-sql`
   refuses a statement another engine finalized in between: at fuels 26 to 51 a would-be
   `&sqlite-error` became `&sqlite-closed` (`probe-accessor-sql.sps`). The accessor now gives its
   procedure the SQL as a third argument, after the two handles: the copy made at prepare, which
   never changes. Its signature comment, its contract and every caller (step, reset, finalize,
   the counts, the suites) follow. The row shows the procedure receives the SQL: equal to the SQL
   prepared, not the caller's string, ready and in a row alike. F3 fails it.
4. **An error message dropped a leading U+FEFF.** `c-string->string` decoded with `utf8->string`,
   which drops one; a trigger's `RAISE(ABORT, '\xFEFF;boom')` reached the `&sqlite-error` as
   `boom`, on both libraries (`feff-errmsg.sps`). When the bytes read begin `EF BB BF`, the string
   now begins U+FEFF, as `strict-utf8->string` restores it; invalid bytes are still replaced, never
   refused. Rows: `test-native` reads `EF BB BF 61` as U+FEFF and `a`, a second U+FEFF kept, one
   kept before an invalid byte (replaced), a BOM-less block and `EF BB` alone as before;
   `test-statement` keeps the trigger's text, with one that has no U+FEFF as the control. Both
   watched failing against the code as it stood (F4).
5. **The tail oracle re-decoded SQLite's tail.** `sqlite-verdict` decoded the tail's bytes with
   `utf8->string`, which drops a leading U+FEFF, so for `select 1;` then U+FEFF and `x` it asked
   SQLite about `x`. It now prepares the tail in place, at the SQL's address plus k, with nByte
   less k. **No mutant or row can tell the two apart:** U+FEFF is a token of its own to SQLite, an
   error alone or before any statement, so both ask a question whose answer is refused. The suite
   passes 9 of 9 before and after, with the same counts of accepted, refused and failed.
6. **The docs.** Each fact has a row now. `docs/reference.md` says a failed prepare has an
   offset, `prepare-statement`'s or `call-with-statement`'s (D4; the existing row of
   `call-with-statement`'s checks held it already, the new row names it); `column-count` is read
   afresh and moves at the next step after an `alter table`, its own connection's or another's
   (measured 2, 2, then 3 on both libraries; 1, 1, then 2 for another's; D1); `sqlite-busy?`
   covers a `commit` refused while the connection's own statement is mid-row, which a reset of that
   statement lets through (D2); `reset!` keeps its bindings, a value bound through the accessor
   with `sqlite3_bind_int64` reading back after the reset and a second step (D3).
7. **The accessor's comment** said the no-op "answers no value"; it answers one unspecified value.
   Comment only.
8. **`test-statement-block`'s comments claimed checks its rows didn't make.** Each blocking row now
   asserts the counts, once everything is closed (F8): 5 of 6 fail against a leak, where one did.
9. **This log:** the mutants above, N02 relabelled (its table row and its survivor entry), and
   the first 80 rerun against the tree as it stands. Their failed counts moved up where the new
   rows also catch them (S07 23, TS2 64, X02 3, X05 57, X07 5, X08 7, X09 22, X10 3, X16 4, X23 2;
   E03 now fails all 6 rows of the block suite); the rest are unchanged; the same three survived,
   B01, I07 and N02. D03 and S05 were adapted to pass the SQL as a third argument. X03 hung again
   and the timeout killed it (above). The red run of M1's `connection.sls` under the real
   `statement.sls` (R00) is now 42 passed, 33 failed of 75. N02's numbers, rerun here: 536,870,914
   characters, 2³¹−1 bytes, the tree answers `(sql-too-long 2147483647)` in 8.5 s, N02 answers
   `toobig` from SQLite in 74.8 s.

## Part B: the public names and their docs

Part B makes the statement verbs public, documents them, and updates the suites that hold the
public surface: `src/chez-sqlite3.sls`, `docs/reference.md`, `tests/test-public.sps`,
`tests/test-never-loads.sps`, and `&sqlite-closed`'s message in `conditions.sls`
("the connection or statement is closed"; no row asserts it, and none was added). Built test first by a
Sonnet agent. `test-reference` and `test-docs` needed no row of their own: they
read the page and the source, so the new entries and examples are rows already.

Mutations ran in copies of `src/`, `tests/` and `docs/` under the git-ignored `build/m2s3b/mut/`,
with `README.org` and the SRFI libraries linked in. A baseline copy ran green first. The driver is
`build/m2s3b/mut.py`, not the repository. Counts are read from the suites' own `# of expected
passes` and `# of unexpected failures` lines.

### The red runs

| Suite | Red run | Against | Green run |
|---|---|---|---|
| `test-public` | 18 passed, 1 failed: the connection library's export list | M1's suite over the tree as it stands (the library already exports `check-database-owner`, `first-finalize-failure`, `track-statement!`, `tracked-statements` and `untrack-statement!`) | 19 passed |
| `test-never-loads` | 4 passed, 1 failed: the loaders row, `(chez-sqlite3 private statement)` found and not expected | the old list | 5 passed |
| `test-public` | 17 passed, 2 failed: the export list, and the eq? row | the new rows over the old `src/chez-sqlite3.sls` | 19 passed |
| `test-reference` | 17 passed, 2 failed: every export has an entry (12 without one), the entries are the exports | the new exports over the old page | 19 passed |

`test-docs` has no red run of its own: its rows are the page's blocks, each a row, and the four
new runnable examples add 8 rows (49 to 57). A wrong stated result fails it (D01).

Final green runs, on Guix's 3.53.1: `make test` 33 of 33. On the floor, 3.45.1
(`CHEZ_SQLITE3_LIBRARY=$PWD/build/m2s1-floor/libsqlite3-floor.so`, read back as 3.45.1): 33 of 33.
`test-public` 19, `test-reference` 19, `test-docs` 57, `test-never-loads` 5.

### The mutations

**37 mutations, 37 caught.** Each row names the suites' failures, as passed and failed.
Baseline: `test-public` 19, `test-reference` 19, `test-docs` 57, `test-never-loads` 5, all passed.

| Mutation | What | Failed |
|---|---|---|
| A01 to A12 | the name dropped from `(chez-sqlite3)`'s export clause, one per new export | `test-public` 2 and `test-reference` 3 each (the exports, the eq? row; no entry for an export, the entries as sorted lists, a signature comment for a name not exported); `test-docs` 1 to 2 for the nine whose page examples or prose name them (A01 2, A02 1, A03 2, A06 1, A07 2, A08 1, A09 1, A10 1, A11 1, A12 1; A04 and A05 0) |
| B01 to B12 | the export's signature comment changed (` X` appended) | `test-reference` 1 each: the entry's line differs from its comment |
| C01 to C12 | the page's entry dropped | `test-reference` 2 each: the export has no entry, the entries are not the exports; `test-docs` 4, 2 and 2 fewer rows for C01, C03 and C07, whose runnable examples went with them (not failures) |
| D01 | a runnable example's stated result changed (`;; => 2` to `3`) | `test-docs` 1 |

A12's first run dropped the export clause's closing parenthesis with the name and broke the
library, an artefact of the driver; it was redone with the parenthesis kept, and its row is the
one above. The full lines are in `build/m2s3b/mut-results.txt`.

The `test-never-loads` list is held by its red run alone: no mutation of `src/` makes
`(chez-sqlite3 private statement)` load or not load libsqlite3 without breaking the library.
