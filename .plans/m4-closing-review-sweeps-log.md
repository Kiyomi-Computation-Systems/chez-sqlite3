# M4 closing review: the sweeps' low passes and the control-run judges

Builder D's log for M4's closing review: the findings' B1, B2 and B3, and Proposal 1's items A
to G, from the closing review's findings file (the lead's, with the maintainer's decisions of
2026-11-18). An Opus agent built it in the worktree `chez-sqlite3-wt-m4cr-d`, on
`m4cr-sweeps` from `main` at `34721b4`, beside builders C (the code and docs), E1 (the CI
lane) and E2 (the loading suites), each on disjoint files. Nothing under `src/` changed.
Every figure is from the final tree on Guix's 3.53.1 unless a line names another library.

The drivers are in [research/m4-closing-review/sweeps/](research/m4-closing-review/sweeps/):
`plant.py`, reviewer B's three plants copied unchanged and builder D's; `planted.sh`, which
makes each plant's copy of `src/` under `build/plant/`; and `plants.sh`, which runs every suite
of this log against every plant and against `src/`.

## What changed, suite by suite

Each low pass follows slice 4's in `test-load-extension-engines.sps`: each trial collects at
2^27, then holds `collect-trip-bytes` at 256 until it ends; every resume goes through a
large-fuel finish; each trial is judged by its own effects; a whole new call is bounded by the
pass's own first refusal before the call's first section; a reach check fails by name. Every
low row also fails by name, `(no-collect-request-met 0)`, unless collect requests fell in its
trials: a `collect-request-handler` of the suite's counts each, installed by `begun!` and put
back by `ended!`. Three things the template doesn't have came out of the build, each below its
measurement: the bound reads only the trials whose first slice met no collect request; where a
low pass must reach one section's exit, a callback of the suite's allocates 32 KiB inside that
section; and the fold's whole calls are counted by the rows its procedure is given.

- **A, `test-open-engines`:** the resumed-twice and re-entered rows each have a low pass,
  their judgments the high rows', plus `answered-again-past-its-last-section` and
  `called-again-past-the-settings` by name. `sweep`, `cwd-sweep` and `untracked-sweep`, the F1
  row among them, are as they were. 8 rows, now 10.
- **B, `test-open-db-config-engines`:** both interleaved rows drop their control: a trial is
  judged by itself, two connections, or the stand-in's first set noted twice, a whole new
  call's, and the sweep requires refusals at half its fuels, and every whole new call below the
  first fuel at which a trial was refused, R before the call's first section. Low passes of the
  resumed-twice, re-entered and both interleaved rows. The once-a-call low row requires
  `straddled-the-last-set`, R before the call's last set and R1 past it, its stand-in
  allocating 32 KiB inside each set's section. B asked it of both interleaved rows; on
  `open-database`'s, where nothing of the suite's runs inside a set, the straddle came by
  chance: 150 trials on Guix's library, 3.45.1 and 3.54.1, and 4 on the no-load build, whose
  list has one set fewer, so that row does not ask it. A first build read the last set on the
  connection's handle, noted by an entry point registered through `sqlite3_auto_extension`;
  it went with the check. The header's claim that no control bounds a whole new call is now
  true. 12 rows, now 16.
- **C, `test-open-interleave`:** both interleaved rows and both failing-twice rows drop the
  control, as B's; each has a low pass, the interleaved low rows requiring
  `straddled-the-last-section`: for `open-database`, the whole plan noted and no statement
  counted; for `call-with-database`, whose connection an expiry closes, the procedure given its
  connection. The SIGINT escape row is as it was. 13 rows, now 17.
- **D, `test-conveniences-resumed`:** `bounded` and its `last-held` are gone. Each trial of
  `execute!`, `query` and `query-row` reads, at E1's expiry, where its remainder lay: held;
  past the return, the statement back in the cache, ready, its `SQLITE_STMTSTATUS_RUN` grown by
  E1's one; or before the check-out, the statement untouched; and whether the second resume
  stepped the statement, by the runs of every statement the connection tracks for the SQL,
  summed. A second resume that steps it is a whole new call, allowed only below the sweep's
  first refusal before the check-out. Low passes of the three, warm and cold, each verb's
  requiring `answered-again-past-the-return` of its warm sweep or its cold one; of the failed
  return; of the fold; and of the script. Every connection of the engine rows carries SQLite's
  profile trace, which allocates in the low pass alone (below). The second engine, E2, the
  suite's instrument, runs with the trip raised. 12 rows, now 19.
- **E, `conveniences-pending.sls` and its suites:** the control is gone, as B's: a trial's
  evidence of two whole calls is its SQL prepared past one call's count, its rows added past
  one call's, or the fold's procedure given more than one call's three rows; the sweep requires
  refusals at half its fuels, a third for `query-failing`, and every whole new call below its
  first refusal. The low pass requires `straddled-the-give-back`, R before the give-back and R1
  past it, the give-back read as no statement out of the cache. `execute`, `query` (both
  sweeps) and `query-row` carry their low passes; the fold's is a new suite,
  `test-conveniences-pending-fold-low.sps`, and the script's four,
  `test-conveniences-pending-script-low-0.sps` to `-3.sps`, each the fuels whose remainder by 4
  is its number, every G there and G = 1 alone at the rest: the sweep's parity also takes
  `(mod M K)`. Two low halves by parity took 167 and 169 s under the gate here, half again the
  high halves' 115 and 117; on CI's spread for those, 119 to 196 s, that is about 174 to 283 s,
  past half the 450 s bound, which the findings' B4 calls a major for the loading suites.
- **F, `test-interrupt-database`:** the header says why its engine rows take no low pass: the
  gigabyte trip is for coverage, the verb holds no claim, and nothing follows the latch's one
  section but the return. No row changed.
- **G, `test-transaction-engine`:** low passes of the pending row and the claim row, each
  built for its row. In the claim's low pass the claim window, a count of fuels past the
  thunk's own count, gives way to the sweep's own first refusal by the claim. 20 rows, now 23,
  with the trace's lock row.

## What the build measured

Three of the template's assumptions failed correct code once the low passes ran on M3's calls.
Each is below with its measurement, what the suites do instead, and how to reproduce it.

- **A collect request in a first slice moves its remainder earlier than its fuel.** The
  template bounds a whole new call by the first fuel at which a trial was refused, R before the
  call's first section, and so assumes every trial at one fuel takes its first slice to the same
  point. On correct code, `test-open-interleave`'s low `open-database` row made two connections
  at fuel 8, G 87, while every other trial at fuel 8 was refused, R before the open; G 87's
  first slice alone met a collect request, and at fuel 9 G 1's alone. The request's handler
  costs the engine ticks before the call's first expression, so that remainder lies before it.
  `test-open-db-config-engines`' interleaved low rows left out 3 and 1 such trials in one run,
  4 and 1 in another, and the script's low suites up to 7. Which trial meets one moved from run to run: the same row passed in another
  run. So every bound of this log reads only the trials whose first slice, or whose run before a
  timer's capture, met no request; each prints the whole new calls it left out. The bound's
  refusal may come from any trial, since a request moves a remainder earlier, never later.
  Reproduce: in `test-open-interleave.sps`, make `news` take every trial with two opens,
  whatever `clean` says, and run the suite a few times; the low `open-database` row fails
  `(whole-new-calls-not-below-a-refusal (8) 8)` in some runs.
- **A trip of 256 bytes makes a request only when an allocation chunk runs out.** Chez checks
  `collect-trip-bytes` only when it needs a new chunk: a loop consing 100,000 pairs met 50
  requests, one per 32 KiB, and a critical section that allocated 1,000 bytes met one at its exit
  in 6 of 100 tries, 32,000 bytes in 100 of 100 ([chunk-probe.sps](research/m4-closing-review/sweeps/chunk-probe.sps)). A call that
  allocates less than a chunk meets a request only where its allocation crosses one, and once
  each trial collects first that is the same point at every fuel. So the low passes reached the
  exits that mattered only by luck: `test-open-db-config-engines`' once-trial had R before the
  last set and R1 past it in 0 of 3706 low trials, and `test-conveniences-resumed`'s low
  `query-row` and `execute!` sweeps took no remainder past the return, while reviewer B's whole
  suite under one trip, with no collect at each trial's start, saw them at fuels 78 to 82. A
  pad that varied the start's allocation by fuel found none either. So where a low pass must
  reach a section's exit, something the suite owns allocates 32 KiB inside that section: the
  once-trial's stand-in, inside each set's section, 227 trials then straddling the last set;
  and, for the conveniences and `with-transaction`, SQLite's profile trace, whose callback runs
  inside the step that finishes a statement and inside `query-row`'s return, the BEGIN's step
  among them. Each allocates only in the low pass, through `forcing`, and keeps what it made in
  `sink`, so no compiler drops it. Where a forced request lands still moves with the heap: on
  thirteen copies of `src/`, the plants', query's warm low sweep completed at fuel 88 and took
  no remainder past the return in the three whose `transaction.sls` changed, which
  `(chez-sqlite3)` loads though the suite never calls it, and at 90 or 91, 2 remainders, in the
  rest; its cold sweep took 2 or 3 in all, as did every other sweep. So each verb's low row asks
  the reach of warm and cold together: the return is one code path in both, which differ at the
  check-out alone.
- **A counter of a procedure's calls counts one call twice.** The fold's whole calls first
  counted its procedure's calls; on correct code the high fold row then read two calls at fuels
  145 and 146, both runs refused: a remainder taken inside the procedure, resumed twice, runs its
  tail twice. Counting the rows it is given, a fresh vector each, as `test-conveniences-resumed`'s
  timer row counts its calls, reads one.

Two more, about the suites' own instruments:

- **An engine stepped one tick at a time under the low trip never reached its row.** In
  `test-conveniences-resumed`'s warm low sweep, E2, run a tick at a time until it holds the
  statement at its row, answered `never-held-at-a-row` at fuel 9 in one run of three. E2 now runs
  with the trip raised and the trace's allocation off, PASS's put back after.
- **A query that fails sees refusals at fewer than half its fuels.** `query-failing`'s runs past
  its give-back raise the failure again rather than be refused: 41 fuels of 84 saw a refusal in
  its high sweep, so its row asks a third, as `test-open-interleave`'s failing rows do.

## The plants

Each plant was made in a copy of `src/` under `build/plant/` by `planted.sh`, on the host, and
every suite of this log run against it by `plants.sh`. B's three are its `plant.py`'s, copied
unchanged; D's two are Proposal 1 D's names; the six controls watch each changed high row fail.

| Plant | What it plants | Fails |
|---|---|---|
| `P-open-advance-after` | the open verbs' claim compared inside each setting's section and advanced just after it, inline (B's) | low rows only: `test-open-engines` 2 of 10, its two low rows; `test-open-db-config-engines` 4 of 16, its four; `test-open-interleave` 2 of 17, `open-database`'s interleaved and failing low rows. Every high row passes |
| `P-conv-advance-after` | the conveniences' claim compared inside each section and advanced just after it (B's) | low rows: `test-conveniences-resumed` 3, the three verbs' low rows; `pending-execute` 1, `pending-query` 2, `pending-query-row` 1, their low rows; `test-transaction-engine` 1, the pending low row, its body's `execute!`. And `pending-query-row`'s keyboard row, which HEAD's suite fails too: it is no sweep, and B's "passes every sweep" holds |
| `P-tx-take-after` | `with-transaction`'s claim read inside the BEGIN's section and taken just after it (B's) | **none**; argued equivalent below |
| `P-fold-left-after` | `query-fold`'s flag set just after the give-back's section: on a normal return the critical after thunk gives the statement back and the wind's body sets LEFT once that wind returns, inline; any other exit sets it inside, as the code does | `pending-fold-low` 1, and `pending-fold`'s high interleaved row, which HEAD's suite fails too, 8 trials preparing twice: the `dynamic-wind #t` after thunk's exit spends a tick at the high trip |
| `P-script-claim-after` | `execute-script!`'s claim compared inside the prepare's section, and set by its `on-made`, the section's last work, once interrupts are enabled and disabled again there | low rows only: two or three of `pending-script-low-0` to `-3`, which ones moving from run to run, `-1`, `-2` and `-3` in one, `-2` and `-3` in the next; never `-0` in the runs made. Every high row passes |
| `C-open-settings-unclaimed` | the open verbs' setting sections never refuse | every changed open row, high and low: `open-engines` 4, `open-db-config-engines` 8, `open-interleave` 4 |
| `C-open-open-unclaimed` | the open's own section never refuses | `open-engines` 7, `open-db-config-engines` 11, `open-interleave` 10, the bounds among them, `(refused ... before-the-open-first-at #f)` |
| `C-conv-unclaimed` | the conveniences' claim never refuses | `resumed` 8, its six resumed and failed-return rows; `pending-execute` 2, `-query` 4, `-query-row` 3; `transaction-engine` 2, both pending rows |
| `C-fold-unflagged` | `query-fold`'s flag never read | `pending-fold` 1, `pending-fold-low` 1, `resumed` 3, the fold's two rows and the timer row |
| `C-script-unclaimed` | `execute-script!`'s claim never refuses | `pending-script-even`, `-odd` and `-low-0` to `-3`, 1 each; `resumed` 2, the script's two rows |
| `C-tx-unclaimed` | `with-transaction`'s claim never refuses | `transaction-engine` 2: the high claim row, by the claim window, and the claim's re-entry row. Its low claim row passes: the plant moves its own first refusal, to fuel 10, below which its fuel-9 second level falls |
| `C-tx-unclaimed-unended` | that, and the BEGIN's step no longer reads ENDED | `transaction-engine` 5: both pending rows, both claim rows, the re-entry row |

`src/` itself passes every suite, the same run.

- **`P-tx-take-after` is equivalent.** Its window, between the BEGIN's section and the take,
  matters only when another run of the same call reaches the BEGIN while one is held there.
  An engine's expiry that holds R1 there escapes the wind, and its critical after thunk finds
  BEGUN set, in the BEGIN's own step section, so it rolls the level back and ends it, ENDED set
  unconditionally; R's second run then reaches the BEGIN's step, which reads ENDED in its own
  section, and is refused there, `&sqlite-transaction-ended`, whatever the claim says. A timer's
  continuation taken in the window holds no run: the call goes on, takes the claim, and runs
  its body. Both low passes, the pending row's and the claim's, carry the profile trace, so a
  request falls due inside the BEGIN's step and is handled at the section's exit; the plant
  passed both, and every other row. Reviewer B's run of it at a whole-suite low trip listed
  no effect of its own: its failures there were correct code's.
- **`P-fold-left-after`'s first two forms were wrong.** Wrapping the critical after thunk's
  finish in a `critical-section` inside a plain wind let a timer's raise skip the after thunk;
  `enable-interrupts` then `disable-interrupts` inside the critical after thunk, an engine
  expiring between them under the low trip, left every later engine and timer of the process
  dead, so later high rows failed. Neither is kept. The third, above, changes the normal path
  alone.
- **`P-script-claim-after` sets the claim inside the prepare's section,** in `on-made`, with an
  interrupt window before it: a set after `prepared-at` returns is a procedure call, which spends
  a tick at the high trip, and that form failed the high script rows, `(prepares 3)`.

## The rows' figures

On correct code, Guix's 3.53.1, each low row beside its high one. "Left out" counts the whole
new calls the bound set aside, a collect request in their first slice; "met" the collect
requests the pass's trials met. The figures read alike on 3.45.1, 3.54.1 and the no-load
3.54.1, the forced reaches exactly so; the no-load build's `open-database` list has one set
fewer, and its interleaved low row straddled the last set in 4 trials, where Guix's did in 150:
which is why that row no longer asks it.

| Suite, row | High | Low |
|---|---|---|
| `open-engines`, resumed twice | completes 257; refused 226, same 21, new 9; first refusal before the open at 10 | completes 293; refused 262, same 21, new 9; first at 10; left out 0; met 9,320 |
| `open-engines`, re-entered | starts at tick 269; refused 238, again 22, new 8; first at 9 | 304; refused 276, again 19, new 8; first at 9; met 6,104 |
| `open-db-config-engines`, resumed twice | 289; refused 258, same 21, new 9; first at 10 | 327; refused 296; first at 10; met 12,641 |
| `open-db-config-engines`, re-entered | 301; refused 270, again 22, new 8; first at 9 | 340; refused 310; met 8,214 |
| `open-db-config-engines`, `open-database` interleaved | 119; 7,022 trials; refusals at 109 fuels; 1,026 whole new calls, the last at 9, the first refusal at 10 | 134; 9,003 trials; 124 fuels; 1,162 new, the last at 9, first at 10; left out 4; met 122,021 |
| `open-db-config-engines`, once a call | 76; 2,851 trials; 66 fuels; 639 new, last 9, first 10; the last set straddled in 0 | 92; 4,394 trials; 81 fuels; 793 new; left out 1; the last set straddled in 248; met 64,011 |
| `open-interleave`, `open-database` | 85; 3,571 trials; 60 fuels; 567 new, last 7, first 8; the last section straddled in 1,139 | 97; 4,868; 78 fuels; 666 new; 1,339; met 43,934 |
| `open-interleave`, `call-with-database` | 109; 6,644 trials, 1,114 answering; 79 fuels; 735 new, last 7, first 8; 189 | 127; 8,180, 1,341 answering; 101 fuels; 861 new; 217; met 63,592 |
| `open-interleave`, failing, `open-database` | 145; new 7, refused 95, again 42; new at 1 to 7, first refusal at 8 | 160; new 7, refused 110, again 42; met 868 |
| `open-interleave`, failing, `call-with-database` | 167; new 7, refused 107, again 52 | 185; new 7, refused 125, again 52; met 1,077 |
| `conveniences-resumed`, query warm, cold | 72, 72; refused 63, new 8; held at 56 fuels; first refusal at 9; again 0 | 90, 81; again 2, 3; met 3,072, 1,328 |
| `conveniences-resumed`, query-row warm, cold | 46, 46; held 30; again 0 | 49, 52; again 3, 2 |
| `conveniences-resumed`, execute! warm, cold | 51, 51; held 35; again 0 | 57, 60; again 3, 3 |
| `conveniences-resumed`, failed return, fold, script | 78; 150; 638, new at 1 to 7, first refusal at 8 | 84; 162; 647, new at 1 to 7, first at 8; met 10,934 |
| `pending-execute` | 42; 820 trials with R1; refusals at 33 fuels; 300 new, last 8, first 9; give-back straddled in 0 | 51; 1,199; 39 fuels; 369 new; straddled in 128; left out 3; met 19,278 |
| `pending-query`, query | 72; 2,485; 63 fuels; 448 new; 0 | 81; 3,337; 69 fuels; 520 new; 184; left out 2; met 53,323 |
| `pending-query`, query-failing | 84; 3,403; 41 fuels; 636 new; 1,666 | 93; 4,195; 49 fuels; 705 new; 2,016; met 47,339 |
| `pending-query-row` | 46; 990; 37 fuels; 240 new; 0 | 52; 1,242; 40 fuels; 265 new; 137; met 16,213 |
| `pending-fold`, `-fold-low` | 160; 12,479; 155 fuels; 1,244 new; 6,110 | 169; 13,363; 163 fuels; 1,310 new; 6,693; left out 8; met 125,961 |
| `pending-script-even`, `-odd` | 431; 25,460 and 25,817; 426 fuels each; 1,036 and 1,040 new, the first refusal at 10 and 9; 3,905 and 3,960 | |
| `pending-script-low-0` to `-3` | | 437; 13,092, 13,468, 13,446 and 13,517; 430 fuels each; straddled in 1,987, 2,050, 2,066 and 2,054; left out 0, 4, 2 and 3 |
| `transaction-engine`, pending, outer and nested | 2,133 and 2,133 trials, completing at 51 | 2,755 and 2,699, completing at 60 |
| `transaction-engine`, the claim, outer and nested | 64; new at 1 to 8, refused at 9 to 18, past the BEGIN at 45 fuels | 74; the same new and refused fuels, past the BEGIN at 55 |

## The times

Each changed suite under `make test-memory` on Guix's library, HEAD's version, from a copy of
`main`'s tree under `build/`, then the final one, back to back, so each pair met the same load:
the host ran the other builders too, at a load of 12 to 14 on 18 threads (traps.md: "A suite's
time under the gate can be the host's, not the code's"). Each time is the gate's `time:` line.
CI's are `main`'s latest three runs, 44432932562, 44423636001 and 44418373153, from
`gh run view RUN --log --job JOB` on the host.

| Suite | CI at HEAD | HEAD here | Final here | Ratio |
|---|---|---|---|---|
| `test-open-engines` | 32, 27, 31 s | 24 s | 32 s | 1.33 |
| `test-open-db-config-engines` | 73, 66, 71 | 57 | 138 | 2.42 |
| `test-open-interleave` | 45, 32, 60 | 37 | 93 | 2.51 |
| `test-conveniences-resumed` | 22, 19, 30 | 21 | 35 | 1.67 |
| `test-conveniences-pending-execute` | 21, 18, 21 | 16 | 25 | 1.56 |
| `test-conveniences-pending-query` | 46, 38, 61 | 37 | 87 | 2.35 |
| `test-conveniences-pending-query-row` | 22, 18, 22 | 15 | 23 | 1.53 |
| `test-conveniences-pending-fold` | 80, 73, 76 | 56 | 60 | 1.07 |
| `test-conveniences-pending-script-even` | 145, 119, 194 | 110 | 115 | 1.05 |
| `test-conveniences-pending-script-odd` | 149, 121, 196 | 114 | 117 | 1.03 |
| `test-transaction-engine` | 60, 54, 83 | 47 | 92 | 1.96 |
| `test-interrupt-database` | 17, 14, 17 | 12 | 12 | 1.00 |
| `test-conveniences-pending-fold-low`, new | | | 84 | |
| `test-conveniences-pending-script-low-0` to `-3`, new | | | 92, 92, 93, 91 | |

Every suite passed the gate. CI's runs took 1.30 times this host's HEAD times, on average over
the twelve, so the largest, `test-open-db-config-engines`, comes to about 170 s on CI, and each
new suite to about 110 to 120 s; CI's slowest runners take about twice the fastest. Reviewer B
estimated 1.3 to 1.7 times a suite's high time; the open verbs' and `query`'s interleaved low
passes cost more, 2.4 to 2.5 times, their trials meeting 44,000 to 122,000 collect requests a
pass.

**The shards.** The memory jobs of `main`'s latest three runs summed 4,050 s for shard 1 and
3,607 s for shard 2. Each changed suite's CI time scaled by its ratio above gives 4,462 s and
4,279 s. Each new suite then went, largest first, into the lighter: `script-low-2` into 2,
`-low-0` into 1, `-low-1` into 2, `-low-3` into 1, `fold-low` into 2, ending at 5,176 s and
5,330 s, each new suite's CI time estimated as 1.30 times its time here. The Makefile's lines
for them are the five this log adds; builder E2 changes the loading suites' lines in its own
worktree, and the lead merges the two.

## What the records need

Builder D edits none of these; the lead does.

- **`global-constraints.md`, Conveniences' last rule:** "A sweep of a call that holds a claim
  also runs a pass with collect requests falling ... M4 slice 4's sweeps do; whether M3's and
  slice 3's need it is for M4's closing review." They need it, and now do: the open verbs'
  (`test-open-engines`, `test-open-db-config-engines`, `test-open-interleave`), the
  conveniences' (`test-conveniences-resumed`, the pending suites and their `-low` suites) and
  `with-transaction`'s pending and claim rows. `interrupt-database!` holds no claim and takes
  none. Add that a low pass whose call allocates less than a chunk makes a request fall inside
  the section it must reach, by allocating 32 KiB there, and that its bound reads only the
  trials whose first slice met no collect request.
- **`AGENTS.md`, Testing:** the bullet "A sweep bounds a whole new call by a refusal it sees
  itself" needs: under a low trip, a collect request in a first slice costs the engine ticks
  before the call's first expression, so that trial's remainder lies earlier than its fuel; the
  bound reads only the trials whose first slice met none. And `collect-trip-bytes` is read only
  when an allocation chunk, 32 KiB here, runs out.
- **`traps.md`:** the three measurements above, and two from the plants above: a
  `dynamic-wind #t` after thunk's exit spends a tick even with no collect request, so a flag set
  just after it is split from it at the high trip; and `enable-interrupts` then
  `disable-interrupts` inside such a thunk, an engine expiring between them, left every later
  engine and timer of the process dead.
- **ADR-0016, ADR-0017 and ADR-0018:** an amendment each, that their sweeps run the low pass,
  and the conveniences' and the open verbs' bound reads the sweep's own refusals, not a control.
- **The findings, for the lead's close-out:** reviewer B's reach "answered again past the
  return" held only with the profile trace's allocation, and for query only over its warm and
  cold sweeps together; B's "R before the last set and R1 past it" holds on the once-a-call row
  alone; `P-tx-take-after` is argued equivalent above; `P-conv-advance-after` fails HEAD's
  `test-conveniences-pending-query-row` already, at its keyboard row, which is no sweep; my
  `P-fold-left-after` fails HEAD's `test-conveniences-pending-fold` already.
- **The Makefile:** the five new suites' shard lines, above, for the lead to merge with E2's.

