# M4 closing review: the sweeps' low passes and the control-run judges

Builder D's log for M4's closing review: the findings' B1, B2 and B3, and Proposal 1's items A
to G, from the closing review's findings file (the lead's, with the maintainer's decisions of
2026-11-18). An Opus agent built it in the worktree `chez-sqlite3-wt-m4cr-d`, on
`m4cr-sweeps` from `main` at `34721b4`, beside builders C (the code and docs), E1 (the CI
lane) and E2 (the loading suites), each on disjoint files. Nothing under `src/` changed.
Every figure is from the final tree on Guix's 3.53.1 unless a line names another library.

The drivers are in [research/m4-closing-review/sweeps/](research/m4-closing-review/sweeps/):
`plant.py`, reviewer B's three plants copied unchanged and builder D's; `planted.sh`, which
makes each plant's copy of `src/` under `build/plant/`; `plants.sh`, which runs every suite
of this log against every plant and against `src/`; `rounds.sh`, which runs each plant against
its own suites five times; `twenty.sh`, which runs one suite 20 times, ten at once and ten one
after another; `slipped.sh`, the trip-slip plant; and two probes, `exit-probe.sps` and
`timer-probe.sps`.

The M4 session's read-only check of the merged work found that low rows could not fail when the
low trip stopped working. The follow-up, below the first build's sections, gives every low row
checks the high pass can't meet, and a trip slipped to 256 KiB fails every one of them. Where a
first-build section says something the follow-up changed, it says so.

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
  row among them, are as they were. 8 rows, now 10; 12 after the follow-up, with the forcing
  VFS's two rows.
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
  true. 12 rows, now 16; 18 after the follow-up, which moves the `open-database` interleaved
  rows from `:memory:` to a file, so the forcing VFS sees the open.
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
  thunk's own count, gives way to the sweep's own first refusal by the claim; after the
  follow-up, in the high pass too. 20 rows, now 23, with the trace's lock row; 24 after the
  follow-up, with the claim re-entry row's low pass.

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

The first build's run; the follow-up's, five runs each, is in its own section. Each plant was made in a copy of `src/` under `build/plant/` by `planted.sh`, on the host, and
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

The first build's figures; the follow-up's forced sections are in its own section. On correct
code, Guix's 3.53.1, each low row beside its high one. "Left out" counts the whole
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

The first build's; the follow-up's are in its own section. Each changed suite under `make test-memory` on Guix's library, HEAD's version, from a copy of
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

## The follow-up: low rows that could not fail

The M4 session's read-only check of the merged work, `04fd82e`, found that low rows could not
fail when the low trip stopped working:

- ten low rows asked nothing of their reach but `collect-requests-met`. With `low-trip`
  mistyped as 262144, `test-open-db-config-engines`' low passes ran as its high ones did, and
  it passed 16 of 16.
  `P-conv-advance-after` was caught by `transaction-engine`'s pending low row in 3 runs of 9.
- the high pass meets the other rows' reach checks too: `same 21`, `again 22`, the straddles of
  1,139 and 189, and the give-back straddles of `query-failing`, the fold and the script.
- two claim-holding sweeps had no low pass: `conveniences-reentry`'s jump-back row and
  `transaction-engine`'s claim re-entry row.
- the claim rows bounded a whole new call by the count plus a window of 2. AGENTS.md says
  "nor by a caller's own count".
- two nits.

The fix, one shape in every suite, test first: every low row now asks two checks the high pass
can't meet, and the trip-slip plant fails every low row by name.

### What a low row asks now

Each low row keeps its verdicts and its `collect-requests-met`. It adds two checks, each
failing by name:

- **`every-forced-section-met-its-request`.** Something the suite owns runs inside the
  library's sections and allocates 32 KiB there in the low pass (`force!`). This check needs
  some such section, and needs each one's collect request handled before the next forced
  section or before its slice ends. At 256 bytes a request falls due in every one. At 256 KiB,
  32 KiB meets one about one time in eight. In the high pass nothing is forced. The failing
  form is `(forced-sections N unmet M)`.
- **`taken-at-a-forced-exit`.** Some first slice expired at a forced section's exit, or a
  timer's capture was made there. The high pass forces nothing, so it never meets this. The
  failing form is `(none-taken-at-a-forced-exit ())`.

How a suite tells where a remainder lies, measured:

- **The request costs ticks at the exit.** A request due inside a critical section is
  handled at its exit, where the handler costs the engine ticks.
  [exit-probe.sps](research/m4-closing-review/sweeps/exit-probe.sps) runs six sections that
  each allocate 32 KiB, with a marker set inside each section and overwritten just after it. At
  a trip of 256 bytes, three fuels a section expired with the section's marker, at fuels 3 to 5,
  8 to 10, and so on. At 2^27 and at 256 KiB, no fuel did.
- **The handler can see it.** At the handler's end the engine's timer, read through Chez's
  own `$tc-field`, reached through `eval`, reads `#f` at exactly those fuels, and a number at
  every other fuel ([timer-probe.sps](research/m4-closing-review/sweeps/timer-probe.sps)). So
  the suites' `counted-request` notes, after the default handler, whether a forced section's
  request spent the ticks. Each first slice numbers the forced sections it passes from 1, and
  the row prints the exits it met.
- **Two callbacks in one section count once.** One section can fire two callbacks: a close's
  finalizes, a prepare's several authorizer calls. Counted once a callback, `query`'s warm low
  sweep on correct code had 226 of 1,837 callbacks unmet. An engine spends no ticks inside a
  section, so a callback whose timer reads as the last one's is counted as the same section.
  Counted that way, 0 are unmet in every low row.

Where each suite forces, and why there:

| Suite | Forced through | Sections forced |
|---|---|---|
| `conveniences-resumed`, the pending suites, `transaction-engine` | SQLite's trace, now `SQLITE_TRACE_ROW` as well as `SQLITE_TRACE_PROFILE` | each step that answers a row, the step that finishes a statement, and `query-row`'s return |
| `conveniences-reentry` | the trace, and an authorizer, both new to the suite | those, and each prepare |
| `open-interleave` | the tell's entry point and authorizer | the open's section and each setting's prepare |
| `open-engines`, `open-db-config-engines` | a forcing VFS: SQLite's default copied, its `xAccess` and `xFullPathname` wrapped, registered as the default | the open's section, through `xFullPathname`, and each setting's that begins a read, through `xAccess`; the once-a-call stand-in, each set's section, as before |

`open-database` makes its connection inside its own call, and no code of the suite's runs
inside its sections. Apple's library refuses `sqlite3_auto_extension`, so the tell can't reach
the connection there; the VFS can. A VFS sees no `:memory:` database, so the `open-database`
interleaved rows of `test-open-db-config-engines` now open a file in the row's own directory.
None of their settings is kept in the file. Two new rows hold the VFS: one checks it is
registered as SQLite's default, the other that it is unregistered and freed at the end, with its
callbacks unlocked.

Where the tell is refused, `open-interleave` forces nothing. Its interleaved low rows are
skipped there already, and its failing low rows print their two forced checks unavailable
through `tell-kept?`, as the rows' other tell checks are.

The reach checks the high pass also meets stay in their rows as verdicts. They no longer stand
alone: `answered-again-past-its-last-section`, `called-again-past-the-settings`,
`straddled-the-last-section` and `straddled-the-give-back`.

### The trip-slip plant

[slipped.sh](research/m4-closing-review/sweeps/slipped.sh) copies each suite with `(define
low-trip 262144)` and runs it against `src/`. It gave the same result on Guix's 3.53.1 and on
the floor, 3.45.1: every one of the 29 low rows failed by name, and no other row did. Each
failure includes `(forced-sections N unmet M)` with M above 0, and 17 also include
`(none-taken-at-a-forced-exit ...)`. By suite:

- `open-engines` 2
- `open-db-config-engines` 4
- `open-interleave` 4
- `conveniences-resumed` 6
- `pending-execute` 1, `pending-query` 2, `pending-query-row` 1
- `pending-fold-low` 1, `pending-script-low-0` to `-3` 1 each
- `transaction-engine` 3
- `conveniences-reentry` 1

`pending-fold`, `-script-even` and `-odd` have no low row, and passed.

### The plants, five runs each

[rounds.sh](research/m4-closing-review/sweeps/rounds.sh) ran each plant against the suites its
low rows are for, five times, on Guix's library. The figure is how many of the 5 runs failed
the row.

| Plant | Rows failed in 5 of 5 runs | Rows that pass it |
|---|---|---|
| `P-open-advance-after` | `open-engines`: both low rows. `open-db-config-engines`: all four low rows. `open-interleave`: the `open-database` interleaved low row | `open-interleave`'s `call-with-database` interleaved row and both failing rows (below) |
| `P-conv-advance-after` | `resumed`: the low rows of `query`, `query-row` and `execute!`, and the failed return's in these 5, but in 0 of 20 in the second follow-up's runs. `pending-execute`, `-query` (both), `-query-row`: their low rows. `transaction-engine`'s pending low row in these 5, but the M4 session's recheck caught it in 11 of 21 (the second follow-up). `pending-query-row`'s keyboard row too, which HEAD fails | none |
| `P-fold-left-after` | `pending-fold-low` | `resumed`'s fold low row (below) |
| `P-script-claim-after` | `pending-script-low-0`, `-1`, `-2` and `-3` in these 5, where the first build caught two or three; the recheck caught `-3` in 11 of 15 (the second follow-up) | `resumed`'s script low row, and `conveniences-reentry`'s new jump-back low row (below) |
| `P-tx-take-after` | none; equivalent, as argued above | every row, the new claim re-entry low row among them |

Beyond the two high rows the first build named, no plant failed a high row. Those two are
`P-conv-advance-after`'s keyboard row in `pending-query-row` and `P-fold-left-after`'s
`pending-fold` interleaved row, both of which HEAD fails too. The rows that pass a plant can't
see it, for one of two reasons:

- **Their second run finds the connection closed.** `call-with-database`'s connection is
  closed by any expiry, and a failing open closes its own. Every section of a later run then
  answers `&sqlite-closed` from the handle check, the refusal's own answer, whatever the claim
  says. `open-engines`' resumed-twice low row, whose connection stays open, catches the same
  plant 5 of 5.
- **Their runs come one after the other.** `P-fold-left-after` and `P-script-claim-after`
  split a section's own work from its flag or claim. That matters only when another run reaches
  the same check while one run is held in the split. A remainder resumed twice in sequence, or a
  jump back through a timer's continuation, never has a second run pending: the first run sets
  the flag or claim, and the second meets it, as it would in correct code. The interleaved
  suites, `pending-fold-low` and `pending-script-low-0` to `-3`, hold R1 pending while R runs,
  and catch each plant 5 of 5.

`plants.sh` then ran every plant against every suite once, the follow-up's tree, `src/`
passing every suite. The controls fail as the first build's table says, with two changes:

- **`C-conv-unclaimed` fails `resumed` 7, where it failed 8.** The failed return's low row
  passes it. Its high row fails at one fuel, 29, a second resume answering the row again. The
  low pass's forced requests move that one-tick point into a handler's ticks.
- **The claim rows bound by refusals.** `C-tx-unclaimed` fails `transaction-engine` 2, now
  the claim re-entry rows, high and low (the claim window, below).

`C-script-unclaimed` fails `conveniences-reentry` 2, the jump-back rows, high and low.

### The two new low passes

- **`conveniences-reentry`, the jump-back row.** It now has a low pass, under the trip, the
  trace and an authorizer. Its 4 forced sections are each statement's prepare and step, and its
  captures were made at the exits of sections 2, 3 and 4: none at 1, since a capture waits for
  the first row. `P-script-claim-after` passes it for the second reason above. The low pass
  still covers the shape at the low trip: a capture at a prepare's exit, the claim set inside
  the section, is refused at the next prepare. 12 rows, now 14, with the callbacks' lock row.
- **`transaction-engine`, the claim re-entry row.** It now has a low pass. Its timer, set for
  each case's ticks, ran out at the exits of forced sections 1, 2 and 3. `C-tx-unclaimed`
  fails both the high and the low re-entry row.

### The claim window

`claim-window` is gone. Both claim rows, high and low, now allow a second level only where R
re-ran the thunk's count, or below the first fuel at which the sweep saw R refused by the claim,
or, in the low pass, where a collect request fell in the first slice. With that bound,
`C-tx-unclaimed` passes both claim rows: its first refusal moves to fuel 10, above its extra
levels at fuels 1 to 9, which correct code makes at 1 to 8. A bound read from the sweep's own
refusals can't see a plant that moves those refusals, and the window that did see it was a
caller's count. The claim re-entry rows, high and low, catch it. `C-tx-unclaimed-unended`
fails six rows, the changed high claim row among them, watched.

### The nits

- `pending-script-even.sps` and `-odd.sps` now name the four low suites.
- `transaction-engine`'s pending, claim and claim re-entry rows run their two sweeps under
  `let*`, high and low.

### New rows, watched failing

Each mutation below was made in a scratch copy of the suite:

- **The VFS registered as the default.** With `makeDflt` 0 it failed,
  `(forcing-vfs (registered ...))`, and both of `open-engines`' low rows failed with it,
  `(forced-sections 0 unmet 0)`.
- **The VFS unregistered at the end.** With no unregister it failed, `(0 not-sqlite-default)`.
- **`conveniences-reentry`'s lock row.** With its answer misspelled it failed.
- **`taken-at-a-forced-exit`.** With the exit never noted, both of `open-engines`' low rows
  failed, `(none-taken-at-a-forced-exit ())`, while `every-forced-section-met-its-request`
  held.
- **The rest.** Every changed low row failed under the trip-slip plant above.

### The forced reaches, by row

These are the second follow-up's figures. Its exit detection no longer credits an expiry's
unwinding, and the pending suites' prepares are forced too. On correct code, Guix's 3.53.1.
Each line gives the forced sections the pass counted; the most one first slice passed, or, for
a re-entry row, one call and its re-entry; and the exits a remainder or a capture was taken at.
Every row had 0 unmet.

- **`open-engines`.** Resumed twice: 610; 2; exits 1 and 2. Re-entered: 945; 5; exits 1 and 2.
- **`open-db-config-engines`.** Resumed twice: 668; 2; exits 1 and 2. Re-entered: 1,041; 5;
  exits 1 and 2. `open-database` interleaved: 10,137; 1; exit 1. Once a call: 20,656; 4; exits
  1 to 4.
- **`open-interleave`.** `open-database`, `call-with-database`, and the two failing rows:
  28,325, 32,797, 835 and 809; 5 each; exits 1 to 5 each.
- **`conveniences-resumed`.**
  - `query`, warm and cold: 806 and 440; 4; exits 1 to 4.
  - `query-row`, warm and cold: 189 and 132; 2; exits 1 and 2.
  - `execute!`, warm and cold: 491 and 308; 4; exits 2 and 3, and 1 to 4.
  - The failed return: 182; 2; exits 1 and 2.
  - The fold: 506; 4; exits 1 to 4.
  - The script: 953; 3; exits 1 to 3.
- **The pending suites, their prepares forced as well.**
  - `execute!`: 3,211; 2; exits 1 and 2.
  - `query`: 29,531; 5; exits 1 to 5.
  - `query-failing`: 16,827; 3; exits 1 to 3.
  - `query-row`: 6,536; 3; exits 1 to 3.
  - The fold: 50,802; 5; exits 1 to 5.
  - The script's four suites: about 49,700 each; 4; exits 1 to 4.
- **`transaction-engine`.** Pending: 19,975; 3; exits 1 to 3, the BEGIN's, the insert's and the
  COMMIT's. The claim: 496; 3; exits 1 to 3. The claim re-entered: 380; 3; exits 1 to 3.
- **`conveniences-reentry`, jumped back.** 456; 4; exits 2 to 4.

### The times, and `make test`

`make test` passed 86 of 86 suites on each of the four: Guix's 3.53.1, `m3-floor` 3.45.1,
`m4-current` and `m4-noload`, the last two with `C_INCLUDE_PATH` set to their headers.

Each touched suite ran under `make test-memory` on Guix's library, two versions back to back so
that each pair met the same load: `04fd82e`'s, from a copy of its tree under `build/`, then the
follow-up's. Each figure is the gate's `time:` line, and every run passed the gate. The
follow-up adds no suite. The shard is the worktree Makefile's, which the lead rebalances.

| Suite | Shard | `04fd82e` | Follow-up | Ratio |
|---|---|---|---|---|
| `open-engines` | 1 | 32 s | 33 s | 1.03 |
| `open-db-config-engines` | 1 | 138 s | 143 s | 1.04 |
| `open-interleave` | 2 | 93 s | 93 s | 1.00 |
| `conveniences-resumed` | 2 | 34 s | 37 s | 1.09 |
| `conveniences-reentry` | 1 | 11 s | 15 s | 1.36 |
| `pending-execute` | 1 | 24 s | 26 s | 1.08 |
| `pending-query` | 2 | 85 s | 114 s | 1.34 |
| `pending-query-row` | 1 | 23 s | 28 s | 1.22 |
| `pending-fold` | 1 | 61 s | 60 s | 0.98 |
| `pending-fold-low` | 2 | 85 s | 108 s | 1.27 |
| `pending-script-even` | 2 | 117 s | 116 s | 0.99 |
| `pending-script-odd` | 2 | 120 s | 121 s | 1.01 |
| `pending-script-low-0` | 1 | 90 s | 109 s | 1.21 |
| `pending-script-low-1` | 2 | 93 s | 113 s | 1.22 |
| `pending-script-low-2` | 2 | 93 s | 113 s | 1.22 |
| `pending-script-low-3` | 1 | 93 s | 110 s | 1.18 |
| `transaction-engine` | 2 | 92 s | 91 s | 0.99 |

The follow-up adds 52 s to shard 1 and 94 s to shard 2 here. Most of it comes from
the row trace's extra forced sections: `pending-query` 1.34 times, `fold-low` 1.27, and the
script's four low suites 1.18 to 1.22. The largest suite is still `open-db-config-engines`, at
143 s. Taking the first build's ratio of 1.30 from this host to CI, that comes to about 186 s
on CI. The script's low suites, at 109 to 113 s, come to about 145 s, under three quarters of
`MEMORY_TIMEOUT` on CI's slower runners, at about twice the fastest's times.

## The second follow-up: catches the heap decided

The M4 session's recheck of `6fe29c8` found two catches that depended on luck.

- **`P-conv-advance-after` against `transaction-engine`'s pending low row** was caught in 11
  runs of 21: 3 of 5 by `rounds.sh`, 5 of 10 in parallel, and 3 of 6 one after another. Every
  run, caught or not, printed the same tally, so the reach checks said nothing about the catch.
- **`P-script-claim-after` against `pending-script-low-3`** was caught in 11 runs of 15.
  `-low-0` to `-2` caught it in 5 of 5.

Both are fixed below, test first. The plant is now caught in 20 of 20 runs, ten in parallel
and ten one after another, and correct code passes 20 of 20.

### What the tallies hid

- **The exits `transaction-engine` printed were an unwinding's.** An engine's expiry inside
  `with-transaction` runs its after thunk, whose ROLLBACK steps inside a section the trace
  forces. Its request was handled with the timer already off, so `exit-noted!` read the ticks
  spent and credited that section. The tally's "exits 2 and 3" were the ROLLBACK's, at fuels 20
  to 57 of the low sweep, whatever the first slice had done. To reproduce: in a copy of the
  suite, have the trace's callback note `sqlite3_sql` of its statement and `timer-ticks`, and
  `counted-request` the timer before and after the default handler, inside first slices. Fuel
  31 printed `(cb BEGIN IMMEDIATE 13) (req 10 13 ...) (cb ROLLBACK #f) (req #f #f ...)`: the
  BEGIN's callback found 13 ticks left, its request left 10, and the ROLLBACK's callback found
  the timer off.
- **The two catches came from luck.** In `transaction-engine` each caught run had 1 or 2
  trials with `(stray 1)`, where a natural request had fallen at a section's exit. The pending
  trial never read its two runs' answers. In the script's suites the plant's window, inside the
  prepare's section, met a request only where a natural one fell there: nothing forced the
  prepares.

### What changed

- **`exit-noted!`, in every suite.** It credits a section only when the section's callback found
  the engine's timer running, and keeps the first credit of a slice. With it, `transaction-engine`'s
  pending exits are 1 to 3: the BEGIN's, the insert's and the COMMIT's. The fold's first exit,
  which the unwinding of its wind had overwritten, now shows in `resumed`. Every row still
  passes on correct code, and fails under the trip-slip plant.
- **`transaction-engine`'s pending row reads each run's answer.** In both passes, each answer
  must be one of `pending-answers`: 42, the ended condition, `&sqlite-closed` from the body's
  `execute!`, or the re-entry's refusal. Under the plant, R's second run answers the statement
  tier's refusal, `(not-allowed-in-state done)`.
- **`transaction-engine`'s pending low row asks the interleaving the plant needs.** It fails by
  name, `(refused-at-the-step-r1-made OUTER NESTED)`, unless some trial at each level has all
  three of:
  - R holding the body's statement ready, checked out but not yet stepped;
  - R1 taken at the step's forced exit, the statement done, credited as above;
  - R's second run refused by the body's claim, `&sqlite-closed` from `execute!`.

  Correct code meets it in 32 to 36 trials at each level, in every run measured.
- **The pending suites force each prepare.** The tell's authorizer allocates 32 KiB in the low
  pass, as the trace does.
- **The script's low rows ask the interleaving the plant needs.** They fail by name,
  `(refused-at-a-prepare-r1-made 0)`, unless some trial has all three of:
  - R before the call's first section;
  - R1 taken at the exit of the first section R's resume forced, a prepare;
  - R's second run refused by the claim.

  Correct code meets it in 96 to 100 trials a suite.

Each changed row was watched failing. In a scratch copy with 42 left out of
`pending-answers`, both pending rows, high and low, failed. The plants failed the two new
checks' rows, and the trip-slip plant failed every low row.

### Why each catch is now certain

- **`transaction-engine`.**
  - The plant shows where R lies between `execute!`'s parameter-count section and its step,
    and R1 at the step's exit, before the split advance. R's second run then reaches the step's
    section with the claim still at it, and steps a done statement again. The statement tier
    refuses that, whatever the heap does.
  - The trace forces the step's section. So for each such R, the G sweep takes R1 at that exit
    at three Gs, from the forced request alone, not from a natural one. The F sweep takes R at
    every tick between the two sections.
  - Under the plant that is 27 to 32 trials a run, at fuels 44 to 48. In the 20 runs, 27 to 32
    answer `(not-allowed-in-state done)`, and 1 or 2 more show `(stray 1)`.
  - The row's check counts more than that sub-shape. Correct code meets it at fuels 31 to 42,
    and R may lie before the parameter-count section, whose refusal answers the same. But the
    step's forced window exists for every R before the step. So any trial the check counts
    means some later R, between the two sections, makes one too, and that one is the plant's
    catch. Under the plant, 25 to 28 trials a level still meet the check: those whose R lies
    before the parameter count.
- **The script.**
  - The plant sets the claim after an interrupt window inside the prepare's section. The
    authorizer's request, due inside the prepare, is handled at the first point interrupts are
    enabled after it. Under the plant that is the window, so R1 lies there. In correct code it
    is the section's exit, the claim set.
  - Every trial the check counts in correct code is one where the plant lets R's second run
    prepare the statement again. Under the plant the check counts 0. The trial then reads two
    calls at nearly every fuel of its suite from the first refusal on: 33 fuels each in `-0`
    and `-3`.

### The runs

`twenty.sh`, in the research drivers, runs a suite 20 times against `src/` or a plant's copy:
ten at once, then ten one after another. All on Guix's library:

- **`P-conv-advance-after` against `transaction-engine`:** caught 20 of 20, always and only by
  the pending low row, with 27 to 32 answer deviations a run.
- **`src/` against `transaction-engine`:** passed 20 of 20, its check met in 32 to 36 trials a level each run.
- **`P-script-claim-after` against `pending-script-low-3`:** caught 20 of 20 by its low row, two calls read at 33 fuels each run, and its check counting 0.
- **`src/` against `pending-script-low-3`:** passed 20 of 20, its check met in 98 trials each run.
- **`P-script-claim-after` against `pending-script-low-0` to `-2`, five runs each in parallel:**
  caught 15 of 15, each run at 33 fuels, and the check counting 0.

- **`P-conv-advance-after` against `conveniences-resumed`:** caught 20 of 20, each run by the
  low rows of `query`, `query-row` and `execute!`. The failed return's low row caught it in 0
  of 20, where round 2's five runs had it in 5. After its failed return the statement is
  finalized, so every later section of a second resume answers `&sqlite-closed`, the claim's
  own refusal, and that row can see the split only by a natural request's luck. No row relies
  on it: the three verbs' rows see the split without a failure, every run.
- **One round of `rounds.sh` on the final tree:** every plant's rows as in the table above, but
  the failed return's row, as just said.

The trip-slip plant, rerun on the final tree, fails all 29 low rows by name, all of them
`(forced-sections N unmet M)` with M above 0, 14 also `(none-taken-at-a-forced-exit ())`, and no
other row. `transaction-engine`'s pending low row fails `(refused-at-the-step-r1-made 0 0)` too,
and each script low suite `(refused-at-a-prepare-r1-made 0)`.

### The credit's soundness

`exit-noted!` credits the next request handled while a forced section's request is pending.
It can't tell, by itself, a section's exit from a later event check, or from a timer's
handler, where `timer-ticks` also reads `#f`.

It is sound because a 32 KiB allocation always trips the request inside its own section at a
trip of 256 bytes: 100 of 100 in `chunk-probe.sps`. So the request is due as the section ends,
and is handled at the first event check after it. A timer's handler has no such request pending
unless a forced section just ended. The second follow-up adds only the check that the section's
callback found the timer running, which keeps an unwinding's sections out.

### The times, and `make test`, after the second follow-up

`make test` passed 86 of 86 suites on Guix's 3.53.1 and on `m3-floor`, 3.45.1. The touched
suites ran under `make test-memory` on Guix's library, in pairs as before: round 2's tree,
`56d1102`, from a copy under `build/`, then the second follow-up's. Every run passed the gate.

| Suite | Shard | Round 2, `56d1102` | Second follow-up | Ratio |
|---|---|---|---|---|
| `open-engines` | 1 | 33 s | 32 s | 0.97 |
| `open-db-config-engines` | 1 | 141 s | 137 s | 0.97 |
| `open-interleave` | 2 | 93 s | 93 s | 1.00 |
| `conveniences-resumed` | 2 | 37 s | 36 s | 0.97 |
| `conveniences-reentry` | 1 | 15 s | 16 s | 1.07 |
| `pending-execute` | 1 | 25 s | 26 s | 1.04 |
| `pending-query` | 2 | 115 s | 118 s | 1.03 |
| `pending-query-row` | 1 | 29 s | 29 s | 1.00 |
| `pending-fold` | 1 | 60 s | 61 s | 1.02 |
| `pending-fold-low` | 2 | 106 s | 111 s | 1.05 |
| `pending-script-even` | 2 | 115 s | 116 s | 1.01 |
| `pending-script-odd` | 2 | 117 s | 120 s | 1.03 |
| `pending-script-low-0` | 1 | 108 s | 116 s | 1.07 |
| `pending-script-low-1` | 2 | 112 s | 121 s | 1.08 |
| `pending-script-low-2` | 2 | 112 s | 122 s | 1.09 |
| `pending-script-low-3` | 1 | 111 s | 118 s | 1.06 |
| `transaction-engine` | 2 | 92 s | 94 s | 1.02 |

The second follow-up adds 13 s to shard 1 and 32 s to shard 2 here. Most of it is the
script's four low suites, 1.06 to 1.09 times, from the forced prepares. The largest suite is still
`open-db-config-engines`, at 137 s.

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
- **The follow-up, for `AGENTS.md`'s low-pass bullet.** The bullet says a low pass "fails by
  name unless that pass reached past the section". It could say how: something the suite owns
  allocates 32 KiB inside the sections the pass must reach. The pass then fails by name unless
  every such section met its collect request before the next, and unless some remainder was
  taken at such a section's exit, as the engine's timer reads at the request handler's end. The
  test of a low pass is that a trip slipped to 256 KiB fails every low row by name.
- **The follow-up, for `traps.md`:**
  - A collect request due inside a critical section is handled at the section's exit. Where
    its handler spends the engine's last ticks, the timer, `$tc-field`'s `timer-ticks`, reads
    `#f` as the handler ends, and the remainder lies at that exit (`exit-probe.sps`,
    `timer-probe.sps`).
  - One section can fire a callback more than once: a close's finalizes, a prepare's
    authorizer calls. Count sections by the timer's reading, which no tick changes inside a
    section.
  - A VFS sees no `:memory:` database. `open-database` admits no code of a suite's inside its
    sections but through a VFS, or through `sqlite3_auto_extension`, which Apple's library
    refuses.
  - A low pass can hide a one-tick point that follows a forced section.
    `C-conv-unclaimed`'s fuel 29 in the failed return's row is one; the high pass keeps those
    points.
  - A bound read from the sweep's own refusals can't see a plant that moves the sweep's first
    refusal: `C-tx-unclaimed`.
- **The follow-up, for `global-constraints.md`'s Conveniences rule:** the two checks above,
  for every claim-holding sweep's low pass.
- **The follow-up, for ADR-0017:** the claim rows bound a whole new call by the sweep's own
  first refusal, high and low, and the claim window is gone. `C-tx-unclaimed` is caught by
  the claim re-entry rows alone.
- **The follow-up, for the Mac run.** Nothing here tested the forcing VFS on Apple's or
  Homebrew's library, or `$tc-field` on the Mac's Chez. The VFS's registration row and every
  low row of `test-open-engines` and `test-open-db-config-engines` read the VFS. Where
  `$tc-field` can't be reached, every low row fails `taken-at-a-forced-exit` by name, never
  silently.
- **The follow-up, for the Makefile:** it adds no suite. The times above are for the lead's
  rebalance.
- **The second follow-up, for `traps.md`:**
  - An engine's expiry inside a wind runs the after thunk with the timer off. A check that reads
    `timer-ticks` as `#f` at a request handler's end sees that thunk's sections as exits, unless
    it requires the section's own callback to have found the timer running.
  - A trial that reads only state after its runs can miss a run that answered wrongly. The
    plant's split claim showed in R's second run's answer, `(not-allowed-in-state done)`, in 30
    trials a run. The after-state saw it in 1 or 2, by a natural request's luck.
- **The second follow-up, for `AGENTS.md`'s low-pass bullet:** a low row's reach check
  should be the interleaving its plant needs, met by correct code in every run: a remainder at
  a forced exit while the other is pending, and the run that follows refused where the claim
  must refuse it. Then the plant's catch is the check's complement, not luck. The proof is 20
  runs, ten in parallel and ten one after another.
