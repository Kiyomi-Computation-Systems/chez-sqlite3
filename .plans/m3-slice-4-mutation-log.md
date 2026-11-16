# M3 slice 4 mutation log

Evidence that each rule slice 4's suites claim to guard fails through the property it names
([M3 plan](2026-11-15-m3-plan.md) §5, slice 4, and §4.8's transaction plants). Format of
[the M3 slice 3 log](m3-slice-3-mutation-log.md). An Opus agent built the slice from the lead's
brief, in the slice's worktree, on `m3-slice-4-transactions` from `9deda02`. A second Opus agent
fixed what the slice's read-only review found, in the same worktree, and reran every plant
against the final suites: the counts below are that rerun's.

## What the slice adds

- **`(chez-sqlite3 private transaction)`, new:** `with-transaction`, the shell over slice 1's
  `(chez-sqlite3 private transaction-plan)`, which it calls unchanged. Each of its statements
  runs through slice 3's `checked-out`, `step!/who` and `returned`, in one critical section
  (the section's fix, last section below), the check-out's check `ended`. A failed commit's rollback runs in one
  critical section with its plan (the review's M9, below). The refusal's irritants are
  `(statement-not-finished STATE SQL)`, both read in the refusal's section (the maintainer,
  2026-11-16).
- **`(chez-sqlite3 private connection)`:** the record's `depth` field, after `cache`, from 0, and
  `database-depth` and `set-database-depth!`.
- **`(chez-sqlite3)`:** `with-transaction` and `sqlite-transaction-ended?`, in a block of their
  own.
- **The suites:** `test-transaction`, `test-transaction-nomem`, `test-transaction-engine` and
  `test-transaction-interrupt`, new; C4's fix and the peer row in `test-statement-values-nomem`;
  rows in `test-public` and `test-reference`; one name in `test-never-loads`' loader list.
- **`docs/reference.md`:** a Transactions section, its two entries and `Mode` among the types;
  the Conditions section's count, six.

`failed-commit-plan` needed no change for "Once": it never said when `ended` is set, and slice 1's
walk in `test-transaction-plan` already sets it after a failed commit's plan "whatever it
issued". `ended` is set by the shell, in the section of the rollback's last step taken.

## How the mutants ran

Every mutation ran in a copy of the worktree of its own, `build/m3s4-mut/NAME/`, made by
`tar --exclude=./build --exclude=./.git`, with `build/m3-floor` and `build/scheme-libs` linked in,
and the suites run inside the container after a `cd` into the copy, each under `timeout 280`.
A mutation is a list of edits, each checked to match its file's text exactly once before it is
written. The counts are read from the suites' own output (`# of expected passes`, `# of unexpected
failures`); none died or hung. The driver, the specs and every log are in the worktree's
git-ignored `build/`, not the repository: the builder's `build/m3s4-scratch/mutant.sh` and
`mutants/`; the review's `build/m3s4-review/specs/`; the fix's `build/m3s4-fix/plants.sh`, which
reruns every plant below through `mutant.sh`, its specs in `build/m3s4-fix/mutants/`, among them
four of the builder's adapted to the final text (`failed-commit-open` and the three `refusal-`),
and its logs in `build/m3s4-fix/plants/`. A floor run sets `CHEZ_SQLITE3_LIBRARY` and
`C_INCLUDE_PATH` to the floor's.

The green counts, on Guix's 3.53.1 and the floor's 3.45.1 alike: `test-transaction` 48,
`test-transaction-nomem` 25, `test-transaction-engine` 15, `test-transaction-interrupt` 8,
`test-statement-values-nomem` 15, `test-public` 21, `test-reference` 20, `test-never-loads` 5,
`test-docs` 91. `make test` ran 58 suites, 58 passed.

### The red runs

The four new suites ran against a stub, `with-transaction` calling its body plainly (`stub`).
The export rows ran against `HEAD`'s suites over the new code, and against the new suites with the
two exports taken out (`exports-off`). The `HEAD` rows are the builder's, not rerun: the fix
changed no export.

| Suite | Red run | Green run |
|---|---|---|
| `test-transaction`, the stub | 8 passed, 40 failed | 48 passed |
| `test-transaction-nomem`, the stub | 6 passed, 19 failed | 25 passed |
| `test-transaction-engine`, the stub | 7 passed, 8 failed | 15 passed |
| `test-transaction-interrupt`, the stub | 4 passed, 4 failed | 8 passed |
| `test-statement-values-nomem`, the hard-only lift (`c4`) | 14 passed, 1 failed, the peer row | 15 passed |
| `test-public`, `exports-off` | 17 passed, 4 failed | 21 passed |
| `test-reference`, `exports-off` | 17 passed, 3 failed | 20 passed |
| `test-docs`, `exports-off` | 86 passed, 5 failed, the four examples and the code span | 91 passed |
| `HEAD`'s `test-public` over the new code | 17 passed, 3 failed: the count, the list, connection's exports | — |
| `HEAD`'s `test-never-loads` over the new code | 4 passed, 1 failed, the loader list | 5 passed |

The rows the stub passed are rows a body run plainly satisfies: each suite's load, count,
directory and limits rows; the runs sensor's control; `[F]`'s controls, `[pH1]` and `[p2g]`,
where the body's own raise and the guard's `begin` are all there is; and the engine suite's
second-resume and no-cut-SQL rows, since a stub has no statement to touch. Each of those but the
bookkeeping is failed by a plant below: the controls by `refusal-done-too`, `[pH1]` by `pH1`,
`[p2g]` by `p2n`, the sensor by `sensor`, the second-resume row by `Da`, the no-cut-SQL row by
`names-outside`.

### The plants

Each against the four transaction suites, in the order transaction, nomem, engine, interrupt,
unless named; a suite left out passed whole. "Caught by" lists each failing row.

| Plant | The mutant | Counts (passed, failed) | Caught by |
|---|---|---|---|
| `pE4` (§4.8) | the after thunk's rollback planned at autocommit 0, unread | transaction 46, 2 | `[A]` ended; `[pE4]` (extended code 1, the cached `ROLLBACK` finalized). Floor: the same |
| `pL1` (§4.8) | the return's plan at autocommit 0, so `COMMIT` on L1's return | transaction 43, 5; nomem 20, 5; interrupt 7, 1 | `[A]` ended; `[D]` both; `[H]` the handler after the ended level; `[pE4]`; nomem S1, S3, S4, R1, R2 nested; interrupt write nested |
| `pH1` (§4.8) | the plain before thunk refuses a second entry | transaction 41, 7; engine 8, 7 | `[H]` the three exits; `[pH1]`; `[p2n]`; `[p2g]`; `[pLE]`; both sweeps; before begun; no cut SQL; once; the siblings. The second fix's the pending row fail it too |
| `p2n` (§4.8) | the after thunk acts whenever `begun` is set, its rollback's steps reading no `ended` | transaction 31, 17; engine 6, 9 | `[p2n]` and `[p2g]`, and every row whose level commits or nests: `[A]` E11 and capacity 0, `[B]`, `[C]` nested, `[E]` raise and return, `[H]`, `[pE4]`, `[pLE]`; the nested sweep, before begun, the second resume, no cut SQL, once, the siblings. The second fix's the timer re-entry row, the pending row fail it too |
| `p2g` (§4.8) | the same mutant | — | `[p2g]`: `in-transaction?` `#f` |
| `pLE` (§4.8) | the return's plan, the commit's check-out and its step read no `ended` | transaction 46, 2; engine 9, 6 | `[pLE]`; `[H]` nested; both sweeps; no cut SQL; once; the siblings |
| slice 1's (§4.8) | the commit's check-out and step read no `ended`, only the earlier autocommit read | engine 10, 5 | both sweeps, at fuels 106 to 109, `&sqlite-error` 1 in place of `&sqlite-transaction-ended`; no cut SQL, fuels 30 to 33; the siblings, fuels 105 on. Floor: the same fuels |
| `once` | a failed commit's rollback sets `ended` only when its last step succeeds | transaction 46, 2; engine 13, 2 | `[C]` O7 nested, both: `ROLLBACK TO` ran 2 times, the after thunk's second rollback; the engine's once row, by the runs it now reads (the second `ROLLBACK TO` is the cached one stepped again, which the tracked statements can't show). The second fix's the timer re-entry row fail it too |
| `Da` (adapted) | the check-out's check reads nothing, never `ended` (the use's flag is gone) | engine 9, 6 | the outer sweep, the nested sweep, the second-resume row (now by its second answers, an `&sqlite-error` among them, the `COMMIT` or `RELEASE` its snapshot could not see), no cut SQL, the siblings; and the pending row. Floor: the same |
| `begun-early` | `begun` set before the begin's issue, not in its step's section | engine 5, 10 | both sweeps; before begun; the second resume; no cut SQL; once; left behind; the siblings. The second fix's the failed-begin row, the pending row fail it too |
| `mode-first` | the mode checked before the body | transaction 47, 1 | the surface's order row |
| `default-deferred` | no mode means deferred | transaction 47, 1 | "with no mode, with-transaction begins immediate" |
| `first-value` | the commit answers the body's first value | transaction 47, 1 | "answers every value" |
| `no-rollback` | the after thunk does nothing | transaction 30, 18; nomem 18, 7; engine 13, 2; interrupt 6, 2 | `[A]` open, DDL and capacity 0; `[C]` O7 nested; `[E]` all five; `[F]` nested; `[H]`; plants; nomem S2, R3, R4, R1u; the siblings; interrupt reads. The second fix's the pending row fail it too |
| `depth-plus-one` | the savepoint named by the depth plus one | transaction 31, 17; nomem 16, 9; engine 10, 5; interrupt 6, 2 | every nested row |
| `depth-only` | outer or nested read from the depth, not autocommit | transaction 46, 2 | `[B]` the caller's `BEGIN`, and never `BEGIN` inside a transaction |
| `nested-mode` | an exclusive mode begins `BEGIN EXCLUSIVE` even inside a transaction | transaction 45, 3 | `[B]` all three |
| `failed-commit-open` | a failed commit's level ended without its rollback (adapted) | transaction 41, 7; engine 14, 1 | `[C]` all five; `[E]` returns; once |
| `release-after-failure` | a rollback goes on after a failed `ROLLBACK TO` | transaction 45, 3; engine 14, 1 | `[E]` nested, the cached `RELEASE` stepped and finalized; `[E]` both escapes, the outer `ROLLBACK`'s failure lost; once |
| `raise-over` | the rollback's failure raised over the body's condition | transaction 44, 4 | `[E]` raises, outer, nested and at capacity 0; the closed connection's row |
| `refusal-off` | no refusal (adapted) | transaction 44, 4; nomem 24, 1 | `[F]` three rows; `[C]` O7 nested while held; nomem `[F]` |
| `refusal-row-only` | `failed` not refused (adapted) | transaction 47, 1; nomem 24, 1 | `[F]` the constraint-failed case; nomem `[F]`, the read's NOMEM |
| `refusal-done-too` | `done` refused too (adapted) | transaction 47, 1; engine 13, 2 | `[F]` the controls; the siblings, B refused beside A's statement left at done. The second fix's the pending row fail it too |
| `reuse-n-off` | the depth not dropped when the rollback's last step failed | transaction 47, 1; engine 13, 2 | `[C]` O7 nested, finished: the siblings' `SAVEPOINT chez_sqlite3_2`; once |
| `no-return` | with-transaction never gives its statements back | transaction 16, 32; nomem 8, 17; engine 8, 7; interrupt 4, 4 | both capacity-0 rows, and every row that reads the statements it issued. The second fix's the pending row fail it too |
| `names-outside` | the savepoint's name built with `number->string` outside any section, for the begin and for the commit | engine 14, 1 | the no-cut-SQL row, nested. Floor: the same |
| `sensor` | the runs sensor reads `SQLITE_STMTSTATUS_VM_STEP`, 4, not `RUN`, 6 | transaction 42, 6 | the sensor's control, and every row that reads runs |
| `c4` | `test-statement-values-nomem`'s `under-limit` lifts the hard limit alone | values-nomem 14, 1 | the peer row: db2's `prepare-statement` busy. Floor: the same |
| `c4t` | `test-transaction-nomem`'s rig lifts the hard limit alone | nomem 24, 1 | its peer row: db2's `query-row` busy |
| `doc-example` | the first Transactions example states `(done ())` | docs 90, 1 | that example's run |
| `doc-line` | the reference's `with-transaction` line says `Symbol` for `Mode` | reference 18, 2 | the line against its comment; the new row |
| `transaction-exports-extra` | `(chez-sqlite3 private transaction)` exports `run-level` too | public 20, 1 | the transaction library's export row |

The review's fix added these, each the mutant named for its row (next section):

| Plant | The mutant | Counts (passed, failed) | Caught by |
|---|---|---|---|
| `rv-escape-silent` (M1) | an escape's rollback failure never raised | transaction 46, 2; engine 14, 1 | `[E]` both escapes; once, the lost engine's raise gone |
| `rv-raising-stale` (M1) | `raising` not cleared when a handler resumes the body | transaction 47, 1 | `[E]` the escape after a resumed raise |
| `rv-begin-unraised` (M2) | the begin's failure not raised | transaction 47, 1; engine 14, 1 | "a BEGIN that fails". The second fix's the failed-begin row fail it too |
| `rv-te-unset` (M3) | the return's transaction-ended plan leaves the level unended | transaction 47, 1 | `[H]` the handler after the ended level |
| `handler-ends` (M4) | the raise's handler ends the level when autocommit reads 1 at the raise | transaction 46, 2 | `[H]` a handler before the unwind; the closed connection's row |
| `end-no-drop` (M5) | ending a level never drops the depth, "Reuse N" off | transaction 40, 8; engine 8, 7 | the siblings: `SAVEPOINT chez_sqlite3_2`, depth 3 after W; and every row that reuses a depth. The second fix's the pending row fail it too |
| `rv-nested-mode` (m4) | a refused `BEGIN EXCLUSIVE` or `IMMEDIATE` issued before a nested level's savepoint | transaction 46, 2 | `[B]` the nested mode, now with the outer's marker after the inner call; `[B]` never `BEGIN`. The siblings no longer catch it (it did at engine 10, 1) |
| `refusal-sql-off` (the maintainer's 1) | the refusal's irritants without the SQL | transaction 44, 4; nomem 24, 1; docs 90, 1 | `[F]` three rows; `[C]` O7 nested while held; nomem `[F]`; the refusal's example |
| `once-section-off` (M9) | a failed commit's rollback outside the critical section: the code before the fix | engine 13, 2 | once, by the runs: `ROLLBACK TO` ran 2 times, at fuels 217 to 219 (below); and the timer re-entry row, ticks 28 to 30. Floor: the same |
| `m9-progress` (M9) | design A, below, in place of B | engine 14, 1 | caught, no longer a survivor: the timer re-entry row, `ROLLBACK TO` ran 2 times at ticks 28 to 30 (below); the once row passes it, design A's difference there, a statement left by the lost engine, being one the one section no longer allows. Floor: the same |
| `watchdog-silent` (M6) | the watchdog never answers, its bound 2 s | interrupt 4, 4 | all four rows, `the-watchdog-did-not-end` once the owner's own 2 s had passed |

`p2n` as §4.8 words it, "the critical after thunk without its `ended` check", acts once all the
same: each rollback step reads `ended` in its own section (slice 1's amendment), so the second
exit's steps stepped nothing. The plant that acts twice also clears `ended` before the after
thunk's rollback, which is what the rows must catch.

## The review's findings, and their rows

The review's read-only Opus pass, its probes and mutants in `build/m3s4-review/`. Each new row was
watched failing against its mutant, the counts above; each code change against its rows.

| Finding | The fix | Its row |
|---|---|---|
| M1, an escape past a failed rollback | none: the code held | `[E]` the escape, and the escape after a resumed raise: `&sqlite-interrupt` from `with-transaction`, `in-transaction?` `#t` |
| M2, the begin's failure | none | "a BEGIN that fails": db2's `begin immediate`, no busy timeout; `&sqlite-busy` from `with-transaction`, the body unrun, `#f` |
| M3, `committed!`'s `end-level!` | none | `[H]` once the call has ended its level, a handler's transaction stands |
| M4, a handler before the unwind | documented | `[H]` E4 raised, the handler begins and escapes, its transaction rolled back |
| M5, an engine resumed inside a sibling | documented | the engine suite's siblings, every fuel 1 to 110, complete at 111: B's row gone, depth 0, code 0, `SAVEPOINT chez_sqlite3_1` only |
| M6, the interrupt suite's time | the watchdog bound by a wall-clock deadline, 120 s, each wake interrupting before it reads it; the owner's wait as long, from its own return | the four rows, unchanged; `watchdog-silent` |
| M7, this table | rerun | — |
| M8, the second resume | the docs | — |
| M9, "Once" under an engine | the failed commit's rollback in one section with its plan | the engine suite's once row, and the timer re-entry row |
| m1, the runs sensor | the comments; no interrupted row reads runs | — |
| m2, m3, the nomem headers | the comments | — |
| m4, `[B]`'s premise | the outer's marker after the inner call | `[B]` the nested mode, against `rv-nested-mode` |
| m5, `[F]`'s NOMEM case | — | nomem `[F]`: `(statement-not-finished failed "select ?1 from src limit 1")` |
| m6, m7 | `issued`'s comment; the docs | — |
| the maintainer's 1 | the refusal's irritants with the SQL | `[F]`, `[C]` O7 held, nomem `[F]`, the docs' example: watched failing against the code before, transaction 44, 4; nomem 24, 1; docs 90, 1 |

### M9: a failed commit's rollback, tried once

`build/m3s4-review/probes/once-engine.sps` swept O7 nested under an engine: at fuels 224 to 228,
`ROLLBACK TO chez_sqlite3_1` ran twice, the failed commit's in the wind's body and then the
critical after thunk's, after an expiry between its `ROLLBACK TO` and its `RELEASE`. The row,
`test-transaction-engine`'s once row, sweeps O7 nested at every fuel to completion and counts
through the tracked statements and the extended code, as the brief asks, not the runs: at every
fuel, one `ROLLBACK TO chez_sqlite3_1` tracked, ready; the `RELEASE`s by kind; the extended code
the last step's; depth 1 inside the outer, and the outer commits.

| Design | Run | Outcomes, by fuel | Deviations |
|---|---|---|---|
| the code before the fix | `once-section-off` | ended 1 to 185, lost 186 to 219, busy 220 to 269; completes at 270 | once row, fuels 217 to 219: lost, `ROLLBACK TO` ran 2 times; timer row, ticks 28 to 30: ran 2 times |
| A: each rollback step records in its own section what is left, and the after thunk issues only that | `m9-progress` | the same as the code before the fix | once row: none; timer row, ticks 28 to 30: `ROLLBACK TO` ran 2 times, ready |
| B: the plan and every step of the failed commit's rollback in one critical section (taken) | the worktree | ended 1 to 185, lost 186 to 198, busy 199 to 248; completes at 249 | none |

Both designs ran at the floor with the same deviations. The figures are the second fix's rerun
on the final suites; the first run's, 253 for B and 278 for the code before the fix, moved with
the rows added since. The once row fails the code before the fix and holds both designs; the
timer re-entry row (below) fails both and holds B, so A is caught. The once row can't tell an
unstepped statement from a stepped one without the runs. A scratch probe with the runs
(`build/m3s4-fix/probes/o7-sweep.sps`) reads `ROLLBACK TO` run once at every fuel under B. Under
B no expiry lands inside the rollback, so the double the tracked statements can't see, the cached
`ROLLBACK TO` stepped again (fuels 225 to 227 in the review's probe), can't happen either. The
`once` plant shows that blind spot: its second `ROLLBACK TO` is the cached one, and only `[C]`'s
O7 rows, which read runs, catch it.

The busy `RELEASE` is counted by the runs: a failed `RELEASE` left tracked read 1 (fuel 203 in the
probe). The runs miss only a step that fails at its entry, as an interrupted one does (the
review's `sensor.sps`).

### M6: the interrupt suite under the gate

`make test-memory MEMORY_SUITES="tests/test-transaction-interrupt.sps"`, each run on its own: the
final suite read 15 s, 15 s and 48 s, each a pass. Before the deadline's last change, which made
a late wake's interrupt count, it read 18 s in one run with the six other changed suites, then
99 s and 93 s on its own. The review read 12 s to 71 s. The other six changed suites, in that one
run: `test-transaction` 15 s, `-nomem` 11 s, `-engine` 14 s, `test-statement-values-nomem`
11 s, `test-docs` 31 s, `test-reference` 10 s.

## One critical section per statement (the maintainer, 2026-11-16)

The lead's probe `build/m3s4-fix/probes/o7-orphan.sps` swept O7 nested under an engine and found
`issued`, which used each of with-transaction's statements in three critical sections, leaving
one behind: at fuel 203, `RELEASE chez_sqlite3_1` failed and tracked, a later `with-transaction`
refused ("a statement of the connection is at a row or failed"); at 202, a `RELEASE` checked out
at `ready`, tracked until the connection closes. The maintainer decided `issued` takes the
statement from the cache, steps it and gives it back in one `critical-section`. The check stays
`ended?`; the use's flag, `left`, went with the sections it guarded, since no remainder can be
captured inside one. Nothing else in the shell changed.

**The row**, `test-transaction-engine`'s "left behind": O7 nested under an engine at every fuel
from 1 until the call completes unexpired, the inner body holding `insert … returning` at a row
and returning, so its `RELEASE` fails. After the outer `with-transaction` returns, at each fuel:
of with-transaction's tracked statements none is not `ready` and none is tracked twice; every
statement the connection tracks is in the cache (`tracked-statements` as long as
`database-cache-count`); the depth is 0; and a later `with-transaction` commits. "None tracked at
any state" could not be the assertion: the cache keeps its own `ready` statements tracked, at fuel
1 among them, so the row asks that none be left outside the cache.

| Run | Counts (engine) | Outcomes |
|---|---|---|
| the row against the code before the change | 11 passed, 1 failed | fuel 200: `RELEASE` checked out and never given back, tracked beyond the cache (1 outside); fuel 201: a `RELEASE` `failed` and tracked, the later `with-transaction` refused, `statement-not-finished failed "RELEASE chez_sqlite3_1"`. The probe's own fuels, 202 and 203, differ by its setup |
| after the change, Guix's 3.53.1 and the floor's 3.45.1 | 12 passed | completes at fuel 249; kinds ended 1 to 185, lost 186 to 198, busy 199 to 248 (the once row's, before: 253, 188, 203) |

The once row now reads the tracked `ROLLBACK TO`'s runs as well, one at every fuel: with every
statement atomic, the double `ROLLBACK TO` that `once-section-off` plants is the cached statement
stepped again, which the tracked statements cannot show (the M9 blind spot above). The row at 12
tests, `once-section-off` caught again, engine 11, 1 (then; now 13, 2, the final rerun).

Plants of this change, the counts above rerun against the final suites (the tables carry them):
`three-sections` (the old `issued`, the three sections and `left` restored) fails the new row
alone, engine 11, 1, on both libraries (now 12, 3 with the rows added since); `Da`, the use's flag
being gone, is adapted to the check reading nothing, engine 8, 4, both libraries (now 9, 6); `no-return` re-specified to the one section's
`returned` line; `m9-progress` (design A) survived then, engine 12, 0, both libraries, and is caught now (the second fix, below); the
siblings row against `rv-nested-mode` (the `[B]` rows in `test-transaction` still fail it). Every
other plant's counts are rerun, its engine count one higher for the new row, plus the failures
the new row and the once row's runs add: `begun-early` 4, 8; `end-no-drop` 6, 6; `no-return` 6, 6;
`reuse-n-off` 10, 2; `once` 11, 1 with transaction 46, 2.

Green: `make test` ran 58 suites, 58 passed; the four transaction suites at the floor, 48, 25, 12
and 8; under the gate, `test-transaction` 16 s, `-nomem` 11 s, `-engine` 16 s and `-interrupt`
11 s, none slow.

## `number->string` resumed twice (the lead's addition)

On Chez 10.4.0 a remainder resumed a second time from inside `number->string` answers `""` (the
lead's probe). `with-transaction`'s savepoint names come from N, through slice 1's plans, and the
shell calls each plan inside `call-with-open-handle`'s section, where no expiry lands; nothing in
the shell calls `number->string` otherwise. `test-transaction-engine`'s no-cut-SQL row resumes
every fuel's first remainder twice, at both levels, and reads the connection's tracked SQL and
its extended code, never an error. It holds in the worktree, and `names-outside`, the names
built outside the sections, fails it. The commit's half of that plant alone could not: its
check-out reads `ended` first, so the cut `RELEASE` never reached SQLite.

## The open question: `ended` as `checked-out`'s check

ADR-0017's 2026-11-16 amendment left it to this slice, with a row. The row is
`test-transaction-engine`'s second-resume row: every remainder captured once `ended` is set,
resumed a second time, one tick a slice, the cache's count read between every slice. Both designs
ran it, the builder's runs:

| Design | Run | Remainders resumed twice, each level | That touched a statement |
|---|---|---|---|
| `ended` passed as the check | the worktree, Guix and floor | 373 | 0 |
| the use's flag alone | `Da`, Guix and floor | 381 | 6 |

One design fails it and the other holds it, so the slice takes `ended` as the check, as the brief
directs. [research/m3-slice-4/](research/m3-slice-4/README.md) has both runs. The final suite
reads 303 remainders at each level over fuels 1 to 36, 10 that began the level, none touching a
statement (one earlier run on Guix gave 306 nested); the adapted `Da` has 371 and fails it by
its second answers alone: its snapshot sees no statement touched, 0, while its second answers
include `(raised (sqlite-error with-transaction error error))`, a `COMMIT` or `RELEASE` that
reached SQLite. The row now asserts that none is an `&sqlite-error`: with one section per
statement a second resume's check-out, step and return fall in one slice, which the snapshot
cannot see (the second review's M-A). Before that, the adapted `Da` passed the row.

## The second review's fixes

A read-only review of the fix found two majors and some minors; a third Opus agent fixed them. Each new or
strengthened row was watched failing against its mutant, in a copy under `build/m3s4-mut/`. The
plants' specs are in `build/m3s4-fix/mutants/` and `build/m3s4-review2/specs/`; `plants.sh` reruns
all 50 distinct plants, each against the four suites unless named, on Guix's library, and the
floor's run of eleven of them reads the same counts.

| Plant | The mutant | Counts (passed, failed) | Caught by |
|---|---|---|---|
| `Da` (adapted), M-A | the check-out's check reads nothing | engine 9, 6 | the second-resume row, now by its second answers (it passed before: `(raised (sqlite-error with-transaction error error))` among them); the sweeps, no cut SQL, the pending row, the siblings |
| `m9-progress`, M-B | design A, in place of B | engine 14, 1 | the timer re-entry row: `ROLLBACK TO chez_sqlite3_1` ran 2 times at ticks 28 to 30 of 80 fired in 84. Caught, no longer a survivor |
| `once-section-off`, M-B | the rollback outside the critical section | engine 13, 2 | the once row, fuels 217 to 219; the timer re-entry row, ticks 28 to 30 |
| `return-outside` | `returned` outside the section, after it | engine 13, 2 | the once row, fuels 199 on: the lost engine's `RELEASE` left tracked, `failed`, where the row now expects none, and the orphan row |
| `begun-on-failure` | `begun` set and the depth added to on a failed begin | engine 14, 1 | the failed-begin row, below |
| `watchdog-raises-once` | the watchdog raises once at its start | interrupt 4, 4 | all four rows, by name: `(the-watchdog-raised ((other "Exception in vector-ref ...")) the-watchdog-ended)`; it kept interrupting after the raise |
| `watchdog-raises-after-first` | the watchdog raises after its first interrupt | interrupt 4, 4 | the same |
| `pending-depth-on-ended` | the depth added to when the begin finds its level ended, no `BEGIN` stepped | engine 13, 2 | the pending row, `(depth 1)` at every (F, G) from fuel 16; and no cut SQL |
| `watchdog-silent` | re-specified to the retrying watchdog | interrupt 4, 4 | all four rows |

Not planted, argued: `pending-begun-on-ended`, `begun` set again on a run that stepped no `BEGIN`,
passes every row (engine 15, 0): that run's `ended` is set, so the after thunk's `begun`-and-not-`ended`
test, and every step it could make, read `ended` first. It is equivalent.

1. **The second-resume row** asserts its second answers: each is 42, the `re-entered` refusal or
   `&sqlite-transaction-ended`. A second resume now takes, steps and returns a statement within one
   slice, so the cache snapshot cannot see a `COMMIT` that reached SQLite.
2. **The timer re-entry row** (O7 nested; a timer interrupt set as the inner body returns, whose
   handler calls a continuation captured at the body's start, swept over the ticks): `ROLLBACK TO
   chez_sqlite3_1` runs at most once at every tick, and the handler fires at 20 or more ticks. On
   the final code the handler fires at 59 of 63 ticks, on both libraries.
3. **The once row's allowance** for a lost engine, "at most the commit's `RELEASE`, left checked
   out", is gone: a lost engine leaves no `RELEASE`. `return-outside` fails it.
4. **The watchdog** answers what it raises, and keeps interrupting, 5 ms after each raise, until
   the step is done or its deadline passes; the row's answer names the raise. The review's own
   spec, a raise before the deadline is read, is no longer a spec of this text: the deadline is read
   by the owner before the thread forks. Against a watchdog that raises every time before it can
   interrupt (`watchdog-raises-always`, in `build/m3s4-fix/mutants/`) the owner's `execute!` is never
   interrupted and the suite hangs: no interrupt, no row. That is the limit of the answer, and it
   hangs by a timeout, where a raise that clears now ends by itself.
5. **`begun-on-failure`**, the failed begin at a nested level. A SAVEPOINT fails when SQLite's
   interrupt flag is set and a statement of the caller's is held at a row: the flag stays while a
   statement is active, which `with-transaction`'s refusal forbids at the begin but not between its
   check and its step. The row sets a timer whose handler steps the caller's select to a row and calls
   `sqlite3_interrupt`, between the refusal's check and the SAVEPOINT's step; a second timer then
   finalizes the select, so the interrupt's flag is gone for the exit. With `begun` set by the
   failed begin, the after thunk issued `ROLLBACK TO chez_sqlite3_1`, answered 1, no such
   savepoint: the extended code 1 where the final code leaves 0, in 204 of the 600 cases. The final code leaves 0 or 9 and tracks only `BEGIN DEFERRED`, in all 600.
   The row fails against the mutant, engine 14, 1. At the outer level the mutant is equivalent: the
   after thunk reads autocommit 1 and issues nothing.
6. **The pending row** (a remainder resumed while an earlier resume of it is pending; the lead's
   schedule, from the M3 session's slice 5): each (F, G) on a fresh in-memory connection, engine and
   R. At the outer level and nested: the depth restored, `in-transaction?` `#f` after the outer
   level, a later `with-transaction` committing, and none of with-transaction's own statements
   tracked other than ready, twice, or outside the cache. G steps by 4: the full sweep made 8,210
   trials at each level and the engine suite 100 s under the gate, the stride 2,091 or 2,092 and 46 s.
   The row also fails by name when fewer than 1,000 trials had an R1. Observed, asserted neither way:
   in some trials the body's `insert into t values (1)`, slice 3's convenience, is left tracked
   outside the cache, at ready or done, when R1's `execute!` raises `&sqlite-closed`, its call's
   flag (the lead's: outer F=29 G=46 and G=66). The row reads with-transaction's own SQL only.
7. **The docs and the comment** corrected, the Conditions table's sixth row added.

Figures corrected in this log from runs of the final suites: slice 1's plant (sweeps 106 to 109, no
cut SQL fuels 30 to 33, siblings from 105, both libraries); the M5 siblings (1 to 110, complete at
111); the M9 table (the code before the fix: ended 1 to 185, lost 186 to 219, busy 220 to 269,
complete at 270; B: 1 to 185, 186 to 198, 199 to 248, complete at 249); the second-resume row (303
remainders at each level, fuels 1 to 36); the stub and green counts (engine 15); and the counts of
every plant that the new rows moved, in the tables above.

Green: `make test` 58 suites, 58 passed; the four transaction suites at the floor 48, 25, 15 and 8;
under the gate, `test-transaction` 15 s, `-nomem` 11 s, `-engine` 46 s and `-interrupt` 109 s, none
slow. The interrupt suite's time is the scheduler's (the M6 section): 96 s and 109 s in two gate runs
of this fix.

## Reproducing

From the worktree's root, on the host. The green runs:

```
$ scripts/guix-env sh -c 'make deps && make test'
$ scripts/guix-env sh -c 'make test-memory MEMORY_SUITES="tests/test-transaction.sps tests/test-transaction-nomem.sps tests/test-transaction-engine.sps tests/test-transaction-interrupt.sps tests/test-statement-values-nomem.sps tests/test-docs.sps tests/test-reference.sps"'
$ scripts/guix-env sh -c 'CHEZ_SQLITE3_LIBRARY=$PWD/build/m3-floor/lib/libsqlite3.so.0 C_INCLUDE_PATH=$PWD/build/m3-floor/include $CHEZ --libdirs src:tests:build/scheme-libs --program tests/test-transaction.sps'
```

A red run, the plant `NAME` in its own copy (the driver and specs in the worktree's git-ignored
`build/`):

```
$ build/m3s4-scratch/mutant.sh NAME build/m3s4-scratch/mutants/NAME.py tests/test-transaction.sps tests/test-transaction-engine.sps
$ FLOOR=1 build/m3s4-scratch/mutant.sh NAME build/m3s4-scratch/mutants/NAME.py tests/test-transaction-engine.sps
$ build/m3s4-fix/plants.sh            # every plant above, logs in build/m3s4-fix/plants/
$ FLOOR=1 build/m3s4-fix/plants.sh pE4 slice1 Da names-outside c4 once-section-off m9-progress
```
