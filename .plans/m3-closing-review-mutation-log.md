# M3's closing review: the mutation log

Evidence that each fix of M3's closing review fails through the property it names. Format of [the
M3 slice 6 log](m3-slice-6-mutation-log.md). The review is the last of M3's done conditions ([the
M3 plan](2026-11-15-m3-plan.md), §6). Its probes and outputs are in
[research/m3-review/](research/m3-review/README.md).

## The review

Two Opus reviewers ran read-only on `c0a5408`, `main` after #30, in parallel on disjoint
dimensions: A took the code and its seams, and B the tests, the gate and the records. The lead
reproduced each finding below on that head before any fix was briefed.

| Finding | By | Rank | The lead's reproduction |
|---|---|---|---|
| `execute-script!` runs statements again when a timer's continuation jumps back inside its block | A | major | `script-reenter3.sps`: 629 of 2804 trials returned with a row twice, the reviewer's count exactly |
| `with-transaction` makes its flags after its plan, so a second resume commits the body again | A | major | `verbs-twice.sps`: fuels 9 to 11, 15 and 16; the marked copy places them after the call's entry |
| A watchdog that keeps interrupting stops `with-transaction`'s ROLLBACK and COMMIT | A | major | `watchdog-loss.sps`: left open at trial 84, and the later write gone after a reopen; `watchdog-rollback2.sps`: 351 of 20,000 left open |
| The BEGIN's plan and refusal are read a section before the BEGIN | A | minor | `wt-stale-plan.sps`: the refused BEGIN, and a busy second connection, at fuels 14 to 25 |
| A claim of 0 taken again after the call's end passes every suite (N1) | B | major | `twice.sps`: 2 rows at fuels 8 to 14 under N1, 1 on the tree; 13 conveniences suites pass N1 |
| A failed commit raised from inside a critical section passes every suite (B8) | B | major | `commit-depth.sps`: the handler at depth 2 under B8, 1 on the tree; the 5 transaction suites pass B8 |
| `test-transaction-interrupt` took 318 s on CI, past ADR-0005's 150 s line | B | major | GitHub's log of run 44083802043: the suite from 12:56:13.96 to 13:01:31.71 |
| The near-spellings row depends on order, and a cache keyed by a 4096-character prefix passes (N3) | B | major | `long-keys.sps`: 1 under N3, 2 on the tree; the 3 cache suites pass N3 |
| `README.org` says transactions are "not here yet" | B | major | read |
| The tell's gate, N2, the contention window, the default-valued settings, the sweeps' guards, untestable comments, a rollback after the end, the whole-second grain, the reference's text, and the records | B | minor | as the parts below say |
| Stale comments in the code, and ADR-0020's text on where the SQL is checked | A | minor | read against the code |

**Two of the reviewers' claims didn't hold:**
- A read `script-reenter4.sps`'s refusals as a timer reaching `call-with-open-handle`'s window
  after `finished` is set. Part T marked that window, saw no timer fire inside it, and traced the
  refusals to continuations taken inside the wind before its section.
- A's "ADR-0020, decision 5" is decision 7.

**The maintainer settled one:** "Shut the latch on exit" (2026-11-17), for the watchdog's finding,
over documenting the race.

**Left as they are, argued:**
- **The default-valued settings rows (B's B2 and B3):** equivalent on every tested build. A set
  skipped would be seen by its read-back on a build whose default differs.
- **A rollback issued after the end, unseen in two suites:** `test-transaction`'s [A] and [pE4]
  catch it.

**Found while the fixes ran:** `main`'s run 44087748537, on `e590fdc`, failed `memory-2` on
`test-interrupt-reach`'s 3 MB prepare row. Part S takes it up.

## The lead's records

- **`test-docs` bans any "yet".** Red on `README.org`'s old line: 0 passed, 1 failed,
  `(("README.org" " yet"))`. Green after the line was rewritten, with `test-check-floors`, which
  reads the same file.
- **The reference's load paragraph** was checked by `reviewers/lead/sweep.sh`: a program that names
  any of 37 of the 68 exports, with no loadable libsqlite3, dies before its first line. The other 31
  are the conditions' predicates and accessors, `sql-null` and `sql-null?`.

## The lead's checks

Each part's hand-back was checked by rerunning its suites, rerunning the reviewers' probes on the
fix, and planting the lead's own mutants, each in a copy of that part's tree.

| Part | Plant | Result |
|---|---|---|
| T | J1: `rolled-back!` outside the shut | `test-interrupt-database`: the four shut rows fail |
| T | J2: the shut puts back "interruptible", whatever it found | `test-interrupt`: three stand-in rows fail |
| T | J3: the shut never clears the flag | `test-interrupt`: four rows; `test-interrupt-database`: two |
| T | J4: B8 again | `test-transaction`'s depth row fails |
| C | K2: `claim!` lowers `claimed` when it refuses | **Survives,** equivalent: a refused run raises out of `execute-script!`, and the block's extent can't be entered again after it, so the lowered claim is never read |
| C | K5: `made-claim` claims every position | `test-conveniences-resumed`'s pure row, and `-pending-execute`'s sweep, fail |
| C | K6: the tell answers 21 though it registered | `-pending-execute`'s gate row fails |
| S | L1: `memory-kept` forced to `#f` | `test-transaction-nomem`'s control row fails |
| S | L2: N3 | the near-spellings row fails, `(hit "long")` |
| S | L3: the after thunk never rolls back | `test-transaction-interrupt`'s two read rows fail |

- **The reviewers' probes on the fixes:**
  - `script-reenter3.sps`: no trial has a row twice, against 629.
  - `watchdog-rollback2.sps`: none of 20,000 left open, against 351.
  - `watchdog-loss.sps`: never left open, and the later write survives the reopen.
  - `wt-stale-plan.sps`: no refused BEGIN.
  - `commit-depth.sps`: depth 1.
  - `verbs-twice.sps`: a second commit only at fuels 1 to 9, before the call's first expression.
    At 20 and 21, the body's own `execute!`, a whole new call, writes again, and the return raises
    the ended condition, as the reference says.
- **Each part's suites, rerun:** they pass plain on 3.53.1 and at the floor, and pass under the
  gate on 3.53.1.
- **The handshake, against the old first round:**
  - **`prepare-race.sps`,** under the gate's Valgrind options, at the floor, pinned to two cores,
    with the prepare called 200 ms late: the old round left 1 of 20 prepares unstopped, and the
    handshake none of 20.
  - **The whole reach suite,** with the same late prepare, 8 gate runs each, pinned: both
    passed 8 of 8. So the lead's runs didn't reproduce part S's 6 of 20 for the old round, on a
    quieter machine: part S's ran while two other builders loaded it. CI's failure, the probe's
    1 of 20 and part S's counts are the red runs.
- **The merged tree:** `make test` ran 73 and passed 73 on 3.53.1, and 73 of 73 at the floor.
- **CI,** run 44112097972 on `17a975c`: all six jobs passed. `test-transaction-interrupt` took
  11 s, `test-interrupt-reach` 17 s, and `test-transaction-engine` 57 s; the shards' suites took
  900 s and 986 s.

## Part T: `with-transaction` and the latch

Evidence that each rule this part's suites claim to guard fails through the property it names.
Format of [the M3 slice 6 log](m3-slice-6-mutation-log.md), part A. An Opus agent built it from
the lead's brief, in `chez-sqlite3-wt-m3cr-t`, on `m3cr-transaction` from `main`'s
`e590fdc`. Probes kept with their outputs are in
[research/m3-review/transaction/](research/m3-review/transaction/).

### What this part adds

- **`(chez-sqlite3 private transaction)`:**
  - **the call's claim,** made by `transaction`'s first expression, a variable and a procedure,
    no call, before any check. The BEGIN's section takes it first. A run that reaches that section
    once another has taken it steps nothing and raises `&sqlite-transaction-ended` (review item 1).
    The flags are made after the claim. So a run that makes flags of its own never passes the
    BEGIN, and every run past it shares the claiming run's flags.
  - **the BEGIN's plan in the BEGIN's own section.** `begun!` is one critical section: the claim,
    then, in `call-with-open-handle`'s, the refusal's pass, `held-state`, and `begin-plan` from
    autocommit, the depth and the mode, then the BEGIN or SAVEPOINT taken, stepped and given back
    (item 2). `LEVEL` is set with `BEGUN`, in the step's section. The refusal, the ended
    condition and the BEGIN's failure are raised after the section. `run-level` no longer takes a
    level and its SQL; it takes the mode and the claim.
  - **the shut:** `rolled-back!`, the one path to ROLLBACK, and to ROLLBACK TO then RELEASE, for a
    raise's exit and for a failed commit's, runs its statements inside `call-with-latch-shut`
    (item 3). COMMIT, and the RELEASE that commits a savepoint, are not shut.
- **`(chez-sqlite3 private interrupt)`:** `interrupt-latch-shut! : Interrupt-Latch (-> A) -> A`,
  exported. In one critical section it reads and clears the flag, holding the mutex; runs the
  work with the mutex released; then sets the flag back to what it read, holding the mutex. A
  raise from the work is caught, the flag put back, and raised after the section, the same object.
- **`(chez-sqlite3 private connection)`:** `call-with-latch-shut : Database (-> A) -> A`,
  exported, the shut on the record's latch. For a value that is no database it runs the work with
  nothing shut. Item 7's comment on `call-with-open-handle`'s window is corrected (below).
- **The suites:**
  - `test-transaction-engine`: five new rows, the claim, the claim's depth, the claim
    re-entered, the stale plan and the tracked refusal. Slice 4's failed-begin row now holds an
    untracked select. The five sweeps take a fresh connection each fuel, and each asserts a
    guard (item 5).
  - `test-transaction`: two depth rows (item 4).
  - `test-interrupt`: eight stand-in rows for the shut, and the export row's fifth name.
  - `test-interrupt-database`: five wiring rows for the shut.
  - `test-public`: `call-with-latch-shut` in the connection library's exports.

`transaction-plan.sls` is unchanged.

### How the mutants ran

- **The copies.** Every mutation ran in a copy of its own, `build/t/mut/NAME/`, made by
  `rsync -a --delete --exclude .git --exclude build`, after `make deps` in the copy, each suite
  under `timeout 300`, through the worktree's `scripts/guix-env`.
- **The edits.** A mutation is a list of edits, each checked to match its file's text exactly
  once before it is written.
- **The counts** are read from the suites' own output, never by eye. The driver, `mutants.py` and
  `run-mutants.sh`, is kept in [research/m3-review/transaction/scripts/](research/m3-review/transaction/scripts/);
  every log stayed in the worktree's git-ignored `build/t/`.
- **The red runs** used `build/t/red/`: a copy of `e590fdc`'s tree with the five changed suites
  put in.

### The red runs

| Suite, against `e590fdc` | Red run | Green run |
|---|---|---|
| `test-transaction-engine` | 16 passed, 4 failed: the claim (fuels 9, 10, 14, 15, both levels), the claim re-entered, the stale plan (fuels 14 to 25), the tracked refusal (12 failed begins; 600 in its first, two-dimensional build) | 20 passed |
| `test-interrupt-database` | 19 passed, 4 failed: the four shut rows (the ROLLBACK interrupted, the transaction left open, `"inner"` written; nested, the outer committed `"inner,outer"`) | 23 passed |
| `test-interrupt` | died at import: `interrupt-latch-shut!` unbound | 27 passed |
| `test-public` | 21 passed, 1 failed: the connection library's exports | 22 passed |
| `test-transaction` | 50 passed: the depth rows hold `e590fdc`'s raises, all outside a section | 50 passed |

- **Rows written after the first red run.** The claim's depth row, the claim re-entered row
  and the refusals' wrong-thread case came later.
  - The claim's depth row failed M13 and M15.
  - The claim re-entered row failed `e590fdc`, in the final red run, and M03, M03b and M04.
  - The wrong-thread case failed M18.
- **The rows without a red run** are `test-transaction`'s depth rows, which pass on
  `e590fdc`. Each failed a plant that raises its site inside a section (M10 to M17).

### The mutations

The suites: `test-transaction` (tx), `test-transaction-engine` (engine),
`test-interrupt-database` (database), `test-interrupt` (interrupt), and `test-public` (public)
where named. Baselines, green: 50, 20, 23, 27, 22.

| Mutation | Guards | Failed |
|---|---|---|
| M01 | the claim (`claim!` always true) | engine 2: the claim, the claim re-entered |
| M02 | the claim made by the first expression (made in `run-level`'s let) | engine 1: the claim |
| M03 | the claim read in the BEGIN's section (taken just before it) | engine 1: the claim re-entered |
| M03b | the same (taken in a section of its own before it) | engine 1: the claim re-entered |
| M04 | the plan in the BEGIN's section (plan and claim in a section of their own) | engine 3: the stale plan, the tracked refusal, the claim re-entered |
| M05 | the refusal's pass in the BEGIN's section (read in its own) | engine 1: the tracked refusal |
| M06 | the rollback shut (`rolled-back!` unshut) | database 4 |
| M07 | COMMIT interruptible (COMMIT shut too) | database 2: the two commit rows |
| M08 | a failed commit's rollback shut (the raise path's alone shut) | database 2: the two commit rows |
| M09 | `call-with-latch-shut` shuts (it calls the work alone) | database 4 |
| M10 | B8: a commit's failure raised outside a section | tx 1: the failures' depths |
| M11 | the BEGIN's failure, and the handle's, raised outside a section | tx 2: both depth rows (closed is that `raise` too) |
| M12 | the refusal raised outside a section | tx 1: the refusals' depths |
| M13 | the ended condition at a return raised outside a section | tx 1, engine 1: the claim's depth |
| M14 | the rollback's failure, on an escape, raised outside a section | tx 1 |
| M15 | the claim's refusal raised outside a section | engine 1: the claim's depth |
| M16 | the body's refusal raised outside a section | tx 1 |
| M17 | the mode's refusal raised outside a section | tx 1 |
| M18 | the owner checks raised outside a section (`check-database-owner` in one) | tx 1: not-a-database and wrong-thread at depth 2 |
| M19 | the body's own raise handed on outside a section (the handler's `raise-continuable` in one) | tx 2 |
| M20 | the shut puts the flag back (it leaves it clear) | interrupt 6, database 4 |
| M21 | the shut puts back what it found (it sets interruptible) | interrupt 3 |
| M22 | the shut's mutex (the read and clear without it) | interrupt 1: the race |
| M23 | the mutex held for constant time (held across the work) | interrupt 1: the race, `work-end-with-the-try-unended` |
| M24 | one section (the clear in one, the work and the put-back outside it) | interrupt 1: the engine row |
| M25 | the work's raise caught inside the section (left to raise there) | interrupt 2: the raise's depth, and its resumption |
| M26 | the flag put back after a raise (only after an answer) | interrupt 1 |
| M27 | the work called once (twice) | interrupt 3: the answer, the engine row, the race |
| M28 | the verb reaches SQLite at all (`interrupt-database/with` does nothing) | database 15, the case the shut leaves among them |
| M29 | the after thunk acts only once begun (it ignores `begun`) | engine 10; not the failed begins: `exit-plan` reads `begun` too, and `level` is unset until the BEGIN answers |
| M29c | a failed begin rolls nothing back (M29, `exit-plan` ignoring `begun`, and `level` set before the step) | engine 13, the failed begins among them |
| W1 | a commit at all (`committed!` never commits) | engine 10, then the suite hung past 300 s in the pending sweep; the outer sweep by its kinds alone, `(() (ended-after-a-later-write rolled-back) rolled-back)` |
| W2 | the guards of the second-resume sweeps (the suite's trials at `statement-cache` 0, so no BEGIN is ever seen run) | engine 3: `too-few-first-slices-began-the-level 0 of 29`, `too-few-past-the-begin 0 of 29`, and the claim re-entered, which reads the BEGIN's runs |
| W3 | the claim row's guards (the suite's trial thunk in a critical section, so no slice expires) | engine 1: `too-few-refused 0`, `too-few-past-the-begin 0` |

**34 mutations, all caught**, every count above read from a last run of all of them against the
final suites, 6.5 minutes. The W rows are suite-side plants that collapse a sweep.

- **M03 and M03b passed every row as first written.** They take the claim before the BEGIN's
  section, not inside it: just before it, or in a section of its own. Under an engine, a second
  run from between the two then reaches the BEGIN's `issued`. Its check is `ended?`, which that
  run shares with the first, and the first's end, or its expiry's rollback, has set it. So the
  run is refused there anyway.
- **The schedule that tells them apart** is a re-entry from inside the level, with no wind
  crossed: a continuation a timer's handler took before the BEGIN, called from the body's first
  entry. Its run arrives at the BEGIN while `ended` is unset. The claim re-entered row sweeps it.
  At tick 17, M03's outer call answered 42 with the depth left at 1 and the transaction open,
  and its nested call left the depth at 1.
- **On the right code,** 18 of 53 ticks re-entered, and every call answered 42 or the ended
  condition, depth 0, nothing open.

### The claim's window

The suite cannot see the claim. Its engine thunk counts its own entries, then calls
`with-transaction`. Between the count and the claim lie two procedure entries, `with-transaction`'s
and `transaction`'s, and an engine can stop at each.

- **What the claim row allows.** A second level is allowed where R re-ran the count, or at the two
  fuels after the first fuel whose first slice made it (`claim-window`, 2). It is allowed only
  where the first slice began nothing.
- **The fixed code.** The count was first made at fuel 7, and whole new calls came at fuels 1 to 8,
  both levels. The claim refused R2 at fuels 9 to 18, and 45 fuels lay past the BEGIN.
- **`e590fdc`.** Whole new calls came at 1 to 10, 14 and 15. 9, 10, 14 and 15 lay outside the
  window, so the row failed.
- **The brief's rule alone** would fail the fixed code at fuels 7 and 8. Its rule: a second commit
  only where the second resume re-ran the thunk's entry.
- **A probe in a library of its own** found the same one-fuel gap per procedure entry
  (`research/m3-review/transaction/scripts/probe-window.sps`).

### Item 2: the refusal and slice 4's failed-begin row

Slice 4's row "a nested begin that fails leaves nothing to roll back" found 0 failed begins once
the refusal's pass joined the BEGIN's section: `too-few-failed-begins 0`.

- **Why it had found them.** A timer stepped the caller's tracked select to its row between the
  refusal's section and the BEGIN's. That window is item 2's defect, now closed.
- **Its select is now made outside the library,** by raw `sqlite3_prepare_v2`, so the refusal
  cannot see it. It then finds 849 failed begins and still holds that none rolls anything back.
- **The tracked version is a row of its own,** the tracked refusal: 0 failed begins and 1428
  refusals on the fixed code; 600 failed begins on `e590fdc`.

### Item 5: the guards and the fresh connections

- **The five sweeps** each take a fresh connection, and a fresh engine, at every fuel:
  - the outer and nested sweeps and the before-begun sweep on a fresh file and two connections;
  - the two second-resume sweeps on a fresh `:memory:` one, its cache primed for `twice`.
- **The outer and nested sweeps** now assert their kinds: all three seen, and the completing
  fuel's a commit.
- **`twice`** fails by name when fewer than one fuel in five begins its level in its first slice,
  or fewer than two remainders a fuel are resumed. It saw 10 of 29, and 303 remainders.
- **`resumed-twice`** fails by name when fewer than one fuel in five lay past the BEGIN. It saw
  10 of 28.
- **A trial that raises** ends its sweep there, as a deviation, so a broken call costs one trial
  and not one a fuel to the cap.

### Item 6: D4c

ADR-0017 accepts it, in its slice 3 amendment:

- "A second way a failed commit's rollback fails" names this case: RELEASE busy beside the
  connection's own held `insert … returning`, ROLLBACK TO done, the rollback's own RELEASE busy
  again, "so the savepoint stayed open, rolled back to its start";
- "Once": "At a nested level the level's writes are undone once its ROLLBACK TO has succeeded";
- "Reuse N": "The one left open ends with its transaction."

`probe2.sps`'s D4c lines show just that: the inner raised busy, the write undone, the outer committed
`(#(0))`, and a later `release chez_sqlite3_1` released the open savepoint. `test-transaction`'s
[C] O7 rows hold it. No fix is proposed.

### Item 7: `call-with-open-handle`'s window

The brief: a timer's handler reaches the window between `finished`'s set and the wind's exit, in
212 of 2804 trials of `script-reenter4.sps`.

- **The probe, rerun** (`.plans/research/m3-review/transaction/window-probe.sps`), against a copy
  that marks the window (`window-probe.patch`):
  - 216 to 218 of 2804 trials raised `re-entered after it finished`, `call-with-open-handle`'s
    refusal;
  - no timer fired inside the window in any trial;
  - every trial that was refused had taken its continuation with the window unmarked.
- **So the refusals are the before thunk's own:** a continuation taken inside the wind before the
  section, re-entered after it finished.
- **The comment now says so.** No tick was seen in the window, by engine or timer, and an expiry
  there would be harmless.

### Times

Plain, one run each, `research/m3-review/transaction/scripts/time-suites.sh` in the container, while two other builders ran
beside it. Under the gate, `make test-memory MEMORY_SUITES=…`, the gate's `time:` lines.

| Suite | Plain, 3.53.1 | Plain, floor | Gate, 3.53.1 | Gate, floor |
|---|---|---|---|---|
| `test-transaction-engine`, before | 1.4 s | 1.3 s | 51 s | 49 s |
| `test-transaction-engine`, first build | | | 62 s | 57 s |
| `test-transaction-engine`, after | 1.4 s | 1.3 s | 47 s | 44 s |
| `test-transaction`, before | 0.5 s | 0.5 s | 15 s | 17 s |
| `test-transaction`, after | 0.5 s | 0.5 s | 16 s | 17 s |
| `test-interrupt`, before | 0.4 s | 0.4 s | 8 s | 7 s |
| `test-interrupt`, after | 0.6 s | 0.6 s | 8 s | 8 s |
| `test-interrupt-database`, before | 0.5 s | 0.5 s | 12 s | 11 s |
| `test-interrupt-database`, after | 0.5 s | 0.5 s | 12 s | 12 s |
| `test-public`, after | 0.3 s | 0.3 s | 11 s | 10 s |

The engine suite's first build cost 11 s more under the gate. A copy that printed each row's
time under the gate put 10.4 s of it on the tracked refusal's two-dimensional timer sweep,
1428 trials on files. That row needs one dimension: a select the refusal sees is refused, or comes
after the BEGIN, whenever it is finalized. So the select is now held to the end, and T1 alone
swept, 17 refusals. The fresh connections cost little: the outer sweep 0.9 s under the gate, the
nested 0.5 s, the second-resume sweeps 0.7 s and 0.2 s. The engine suite is in shard 2, 64 to
66 s on CI before.

## Part C: the conveniences and the open

Evidence that each rule the fixes claim to guard fails through the property it names. Format of
[the M3 slice 6 log](m3-slice-6-mutation-log.md). The findings are M3's closing review's: reviewer
A's `execute-script!` re-entry, and reviewer B's six on the claims, the tell's gate, the sweeps'
guards and the comments. The lead reproduced each major before the brief.

### The fixes

An Opus agent built them from the lead's brief, in `chez-sqlite3-wt-m3cr-c`, on
`m3cr-conveniences` from `main`'s `e590fdc`, test first, uncommitted.

#### What the fixes change

- **`(chez-sqlite3 private conveniences)`:**
  - `execute-script!` holds a claim on its statements' byte offsets, `claimed`, -1 at first,
    made by the call's first expression, in place of slice 3's `begun`. Each prepare's check,
    `claim!`, is evaluated inside the prepare's section, through `prepared-at`'s `left?`: it
    refuses unless the statement's offset, `start`, lies past `claimed`, then sets `claimed`
    to `start`. A refusal prepares nothing and raises `&sqlite-closed`. The loop carries
    `start` as an argument, never assigned.
  - `made-claim` exported for the suites.
- **`(chez-sqlite3 private open)`:** `made-claim` exported for the suites.
- **`settings.sls`, `script.sls`:** comments only (item 7).
- **The suites:** `test-conveniences-reentry` (the jumped-back row), `test-conveniences-resumed`
  (the claim's pure rows; the resumed rows' and the script row's bounds),
  `test-conveniences-engines` (fresh connections; the bind and read rows; the comment),
  `test-execute-script` (the block count at every tick), `test-open-engines` (four guards and
  two bounds), `test-open-interleave` (the open claim's pure row; the gate's reading; the
  control's bound; two guards), `(conveniences-pending)` and its six suites (the control's
  bound; the gate's reading; the timer row's give-back; the script's none both past), and
  `test-public`'s two private-exports rows.

#### How the mutants ran

Every plant ran in a copy of the worktree of its own, `build/c/NAME/`, made by
`rsync -a --exclude .git --exclude build`, with `build/m3-floor` copied in, after `make deps` in
the copy, through the worktree's `scripts/guix-env` (`plant.sh` and `runc.sh`, kept in
[research/m3-review/conveniences/scripts/](research/m3-review/conveniences/scripts/)). Each
plant is a list of edits, each checked to match its file's text exactly once before it is
written. The counts are read from the suites' own output, never by eye. The plants and their
logs stayed in `build/c/`, git-ignored.

#### The red runs

Each new row, and each changed guard, was run against the code or the sweep it holds before
the fix, or against a plant of the defect it names where the code had none:

| Row | Suite | Red run | Green run |
|---|---|---|---|
| jumped back, item 1 | `test-conveniences-reentry` | against `e590fdc`'s `execute-script!`: 35 of 96 captures returned with j's rows `(1 2 2)`, the second statement run twice | 96 captures: 32 answered, 35 refused at a prepare, 20 by the statement's state, 9 by `call-with-open-handle`'s wind; no deviation |
| the claim, pure, two rows, item 2 | `test-conveniences-resumed` | N1: both fail, `(0 #f)` claimed after the end | pass |
| the open claim, pure, item 2 | `test-open-interleave` | N1o | pass |
| the control's bound, item 2 | the six pending suites | N1: `execute!`, `query`, `query-failing` and `query-row` each `(whole-new-calls-not-below-a-refusal 15 #f)`; the fold, untouched by N1, passes | every control: last whole new call at fuel 8, first refusal before the first section at 9 |
| the gate's reading, item 3 | the six pending suites and `test-open-interleave` | P3, `(let ((rc 21))` in both registrations: all seven fail, `(gate (auto-extension-answered 21) direct 0)` | `gate-held` |
| the timer row's give-back, item 4 | `-pending-execute`, `-query`, `-query-row` | N2, and N2 with P3, the tell refused as on Apple's library: each fails, 24 ticks of `execute!` leaving nothing cached where a statement was counted at the raise | pass |
| the resumed rows' bound, item 5 | `test-conveniences-resumed` | N1: all three, `(no-refusal-before-the-check-out #f 16)` | refused before the check-out first at fuel 9; held 16 to 45, 50 and 71; answered again at 1 to 8 only |
| the script's resumed bound, item 5 | `test-conveniences-resumed` | S0 and S2 (below) | whole new calls at 1 to 7, refused first at 8 |
| twice's and the re-entry's bound, item 5 | `test-open-engines` | N1o; G3, G4 | refused before the open first at fuel 10 and tick 9; new at 1 to 9 and 1 to 8 |
| the open control's bound, item 5 | `test-open-interleave` | N1o | last new 7, refused first at 8, for both verbs |
| none both past, item 5 | the two script suites | G5, `both` counted as `past`: `too-few-interleavings` | `both` 0 |
| answered three a fuel, item 5 | `test-open-interleave` | G1, one trial a fuel: 72 over 73, 33 over 97 | 2628 over 73, 1029 over 97 |
| held a fuel a statement, item 5 | `test-open-engines` | G2: held at 0 of 221 | 40 of 221, against 12 |
| refused at half, item 5 | `test-open-engines`, two rows | G3, G4: refused 0 of 51 | 190 of 221; 202 of 233 |
| refused at a third, item 5 | `test-open-interleave`, two rows | G7: refused 0 of 51 | 83 of 133; 95 of 155 |
| a quarter refused at a prepare, item 1 | `test-conveniences-reentry` | G6, the jump never made: refused 0 of 96 | 35 of 96 |
| fresh connections, item 5 | `test-conveniences-engines` | P-hit: the abandoned fold's row, warm; `e590fdc`'s suite passes P-hit | pass |
| one value a section, binds, item 6 | `test-conveniences-engines` | B1: counts seen `(0 50)` for all four; `e590fdc`'s count row passes B1 | each count from 0 to 50, cold and warm |
| one value a section, reads, item 6 | `test-conveniences-engines` | R1: `query` and `query-row` see levels `(0 10 20)`; the count row fails R1 too, 38 against 37 | ten consecutive levels or more, for all three |
| no block before the checks, item 6 | `test-execute-script` | N6: the handler counts a block; `e590fdc`'s row passes N6 | none, at more than 20 ticks |

Green: `make test` ran 73, passed 73. Plain, on Guix's 3.53.1 and at the floor, 3.45.1, through
`CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH`, every changed suite passed, and every count each
prints matched between the two libraries. Under the memory gate, the 13 changed suites passed
13 of 13 on each library, none `SLOW`; `e590fdc`'s, in a copy, on the same machine the same
afternoon, for the cost. Plain times are one run each; the gate's by its `time:` lines. Other
builders shared the machine, so a gap of 10% is noise: the script suites ran 107 to 125 s across
the three runs, faster with the fix at the floor than without it on 3.53.1.

| Suite | Plain, `e590fdc` | Plain, 3.53.1 | Plain, 3.45.1 | Gate, `e590fdc` | Gate, 3.53.1 | Gate, 3.45.1 |
|---|---|---|---|---|---|---|
| `test-conveniences-reentry` | 306 ms | 342 ms | 342 ms | 11 s | 12 s | 12 s |
| `test-conveniences-resumed` | 651 ms | 700 ms | 708 ms | 20 s | 21 s | 23 s |
| `test-conveniences-engines` | 321 ms | 499 ms | 512 ms | 12 s | 18 s | 20 s |
| `test-execute-script` | 324 ms | 355 ms | 402 ms | 12 s | 13 s | 13 s |
| `test-open-engines` | 549 ms | 616 ms | 600 ms | 22 s | 25 s | 23 s |
| `test-open-interleave` | 758 ms | 733 ms | 750 ms | 33 s | 38 s | 31 s |
| `test-public` | 295 ms | 293 ms | 308 ms | 10 s | 12 s | 10 s |
| `-pending-execute` | 401 ms | 410 ms | 407 ms | 15 s | 16 s | 14 s |
| `-pending-query` | 943 ms | 906 ms | 868 ms | 37 s | 38 s | 34 s |
| `-pending-query-row` | 433 ms | 418 ms | 427 ms | 15 s | 15 s | 15 s |
| `-pending-fold` | 1401 ms | 1348 ms | 1293 ms | 57 s | 61 s | 53 s |
| `-pending-script-odd` | 2703 ms | 2751 ms | 2434 ms | 114 s | 125 s | 108 s |
| `-pending-script-even` | 2598 ms | 2709 ms | 2360 ms | 114 s | 124 s | 107 s |

The jumped-back row went into `test-conveniences-reentry`, shard 1's, 12 to 15 s on CI, rather
than either script suite, shard 2's costliest at 122 to 149 s: about 1 s under the gate. The
pending sweeps lost slice 5's refused-call sweep, which no longer bounds anything; the fresh
connections and the two new rows cost `test-conveniences-engines` 6 to 8 s, its only real rise.



#### The mutations

Each row names the suites that failed and how many rows failed in each. The pending suites are
`-execute`, `-query`, `-query-row`, `-fold` and `-script-odd`, `-even`. A mutation counts as caught
when at least one row failed. The plants in `statement.sls` and the suites are in their copies
only.

| Mutation | Guards | Failed |
|---|---|---|
| S0 | the script's first prepare claims offset 0 (`claim!` true at 0 always) | resumed 1, script-odd 1, script-even 1 |
| S1 | a prepare claims only an offset past the claim (`>=` for `>`) | reentry 1, script-odd 1, script-even 1 |
| S2 | the claim advances (`set! claimed` dropped) | reentry 1, resumed 1, script-odd 1, script-even 1, who 1 |
| S3 | the claim is read inside the prepare's section (read before `prepared-at`, a constant passed in) | reentry 1 |
| S4 | every prepare claims, not the first alone (`claim!` true past 0: slice 3's `begun`) | reentry 1 |
| S5 | the claim starts at -1 (at 0) | reentry 1, resumed 1, `test-execute-script` 13, engines 1, script-odd 4, script-even 2, who 2, `test-conveniences` 4 |
| N1 | reviewer B's: a claim taken again at 0 once its call has ended (`conveniences.sls`) | resumed 5, execute 1, query 2, query-row 1; fold 0 |
| N1o | the open's analogue: a claim of 0 taken again at any time (`open.sls`) | `test-open-interleave` 7, `test-open-engines` 5 |
| P3 | reviewer B's: the tell's registration forced to 21, in both registrations | the six pending suites 1 each, `test-open-interleave` 1 |
| N2 | reviewer B's: the escape path finalizes, never gives back | execute 1, query 1, query-row 2 |
| N2 + P3 | the same, the tell refused | execute 2, query 2, query-row 2: each timer row, and the gate's |
| B1 | one value a bind section: every value bound by `bind-all!/who`, its plans outside its one section, for the four | engines 1 |
| R1 | one value a read section: a row read in one section, for `query` and `query-row` | engines 2 |
| N6 | reviewer B's: `execute-script!` holds a counted block over its checks, freed as the refusal leaves | `test-execute-script` 1 |
| P-hit | a hit hands its statement over after the check-out's section (`statement.sls`) | engines 1, resumed 1 |
| G1 | the open sweeps make one trial a fuel (`test-open-interleave`'s copy) | `test-open-interleave` 2 |
| G2 | the every-fuel sweep never reads a statement held (`test-open-engines`' copy) | `test-open-engines` 1 |
| G3 | twice's remainder taken at fuel 1 at every fuel to 50 | `test-open-engines` 1 |
| G4 | the re-entry's continuation taken at tick 1 at every tick to 50 | `test-open-engines` 1 |
| G5 | `both` counted as `past` (`(conveniences-pending)`'s copy) | script-odd 1; execute 0, its both past by design |
| G6 | the jumped-back row's jump never made | reentry 1 |
| G7 | the failing sweeps' remainder taken at fuel 1 at every fuel to 50 | `test-open-interleave` 2 |

Reviewer A's `script-reenter3.sps` and `-reenter4.sps`, run on the fix: no trial returns with a
row twice, where 629 of 2804 did; 1613 raise `&sqlite-closed`, 885 return with the script's eight
rows, 218 meet `call-with-open-handle`'s refusal and 88 the statement tier's `not-allowed-in-state
done`.

#### The survivors, argued

None of the plants survived. What the rows don't hold, by design:

- **The jumped-back row captures only once the script's first row stands.** A jump back to
  before the first prepare is the engine rows' (`test-conveniences-resumed`'s script row and the
  two script suites), which S0 fails; the timer row starts later so that no capture lies before
  the call's first expression, where a whole new call is the caller's.
- **A jump inside one statement's own extent is refused by the statement's state, or by a
  section's wind, never by the claim.** The row accepts both by their exact outcomes,
  `not-allowed-in-state done` and `re-entered`, as `docs/reference.md` allows "inside the
  script, an assertion violation". No row asks for `&sqlite-closed` there: a claim on every
  section of the script, as the three verbs hold, would give it, and is the records' call.
- **The read row needs the connection's lookaside.** A libsqlite3 whose step of ten TEXT
  constants takes no lookaside slot prints UNAVAILABLE and skips it; the count row still holds
  a whole row read in one section, as R1 shows.
- **The count row can't see binds or reads made in one section with their checks or finishes
  outside** (B1); the bind and read rows hold those.

Single-trial guards outside the review's list, left as they were: `test-conveniences-resumed`'s
`held-at-some-fuel` (five rows), `test-open-engines`' `some-as-asked` and `some-closed`, and the
timer rows' `some-raised`. Each row now has a bound or a count of its own beside it, but these
still pass on one fuel or tick.

#### For the records

- **ADR-0016:** an amendment. `execute-script!` holds a claim on its statements' byte offsets,
  in place of slice 3's flag, each prepare's section claiming its own: decision 7's "the one
  re-entry left is an engine's resume after an expiry has freed the block" was false, since a
  timer's or keyboard's handler can jump back inside the block's extent, crossing no winder.
  Slice 3's amendment ("`execute-script!`'s first prepare marks its own") and part D's
  ("`query-fold` and `execute-script!` keep slice 3's flag") read so too. `made-claim` is
  exported, held whole. Part D's sweeps bound a whole new call by a refusal the control sees
  before the call's first section, not by the refused call's fuel.
- **ADR-0018:** its `made-claim` exported and held whole; `test-open-engines`' two bounds and
  `test-open-interleave`'s control by a refusal before the open, the refused call's fuel, 68 and
  71 ticks, against a boundary at 9, no bound.
- **`global-constraints.md`:** the conveniences' rule, "every call of `query-fold` and
  `execute-script!` holds a flag … read first in every critical section that touches the
  statement", for the script: a claim on each statement's byte offset, made by the call's first
  expression, claimed inside each prepare's section. The sweep rule's bound: below the first
  refusal of a remainder taken before the call's first section, the fuels in order.
- **`traps.md` and `AGENTS.md`:** below.
- **`docs/reference.md`'s `execute-script!`:** its last paragraph was false before the fix and
  is true after it. Tighter: "Going back into a script, through a continuation or an engine
  resumed a second time, never runs any of its statements again, whether from before the first
  or from between two of them: it raises a condition that `sqlite-closed?` holds, or, inside the
  script, an assertion violation."
- **`statement.sls`'s `prepared-at` comment** still says "execute-script! passes its first
  prepare a check that marks the call's run begun"; it passes every prepare its claim now.
  `statement.sls` is outside this brief.

#### The traps the fixes found

- **A continuation a timer's handler captured inside a wind's extent, called from inside the same
  extent, crosses no winder.** So a before thunk that refuses a re-entry, as `call-with-block`'s
  does, never runs, and slice 3's `begun`, read by the first prepare alone, let `execute-script!`
  run its later statements again. Reviewer A's `script-reenter3.sps` found it, 629 of 2804
  trials; the jumped-back row against `e590fdc`'s conveniences reproduces it, 35 of 96 captures
  returning with `(1 2 2)`. A claim each section compares refuses it; a wind can't.
- **A whole new call bounded by the fuel at which the refused call completes is no bound.** The
  refusal's raise costs ticks: 72 for `execute!`, whose whole call completes at 42, and 68 and
  71 ticks for the open verbs, against boundaries at 8 and 9. N1 passed every suite so. A
  remainder taken past the first expression and before the first section is refused; the first
  such refusal, the fuels in order, bounds every whole new call, and its absence fails the row.
- **One connection across an engine row's fuels sweeps whatever path the last fuel left.**
  `test-conveniences-engines`' fold rows swept only the cold path: every expiry inside the wind
  finalized the statement, so the cache was empty at every fuel, and P-hit, a hand-over on a
  hit made after its section, passed `e590fdc`'s suite.
- **A count of expiries can't tell one section a value from one for all, when each value's
  checks run outside the section.** `bind-all!`, one section, expired 249 times more for 50
  values than for 1 (reviewer B's `q15-binds.sps`), and B1 passed `e590fdc`'s count row. What
  each section did is readable from outside: `sqlite3_expanded_sql` shows each parameter bound or
  NULL, and in a UTF-16 database each TEXT column read takes a lookaside slot
  ([research/m3-review/conveniences/read-lookaside.sps](research/m3-review/conveniences/read-lookaside.sps),
  alike on both libraries).
- **A suite's own text moves its fuels.** Adding the bind and read rows to
  `test-conveniences-engines`, the library unchanged, moved P6's completing fuels from 43, 82
  and 47 to 41, 80 and 45. The rows name the fuel they read and write none down, as
  `traps.md`'s "an engine's fuel names no fixed point" has it; a bound that compares fuels across
  suites, as all five verbs' boundaries being equal, would rest on it.

## Part S: the suites

Evidence that each suite fix of reviewer B's six findings fails through the property it names.
Format of [the M3 slice 6 log](m3-slice-6-mutation-log.md). An Opus agent fixed them from the
lead's brief, in the worktree `chez-sqlite3-wt-m3cr-s`, on `m3cr-suites` from `e590fdc`. No file
under `src/` changed; every plant below sat in a copy.

### What it changes

- **`test-transaction-interrupt`, item 1:** slice 4's plain watchdog, waking every 5 ms, is
  replaced by `test-interrupt-reach`'s device, copied and adapted: each round takes SQLite's
  memory mutex, sleeps 1 ms holding it, calls native's `sqlite3_interrupt` on the handle read
  once, lets the mutex go, sleeps 1 ms; the statement starts only once the first round holds the
  mutex.
  - The long statements take their bound as `?1`, `long-rows` 20,000,000, and call
    `randomblob(16)` for each row: `long-write` inserts into `b`, `long-read` counts beside
    `src`.
  - Each row runs its statement once with a bound of 1 before `with-transaction` begins, so the
    watched `execute!` finds it in the cache and prepares nothing (the trap, below).
  - A row of its own, "SQLite's memory mutex is had": 9 rows, was 8.
  - The four rows' expected values are unchanged.
- **`test-statement-cache`, item 2:** the near-spellings row checks out each near spelling
  first, by `let*`, while the table holds all four keys, then the exact keys, and reads the
  count after each half. The sweep found one more row of the shape: capacity 1024's two
  check-outs were the arguments of one `list`; now `let*`. The non-string-key row keeps its
  `list` (survivors, below).
- **`test-contention`, item 3:** in `contended`, the second says `second-runs` once told the
  first read, then runs; the first's body hears `second-runs` before its `window-ms` wait for
  the second's read starts. So the window holds no wake-up of the second's.
- **The grain, item 4, in `test-open-locks`, `test-open-settings`, `test-contention` and
  `test-interrupt-reach`:** each reads the build's busy-wait grain once, before the rows that
  need it, on one thread: a `BEGIN IMMEDIATE` with a 250 ms busy timeout under another
  connection's write lock, `milliseconds` from 125 ms, else `whole-seconds`.
  - Each timed 1500 ms wait is too long from `retry-ms`: 2000 ms on a whole-second build, 3000
    on any other, an unread grain taking 3000.
  - A row of its own in each prints the grain and fails when it is unread.
  - `test-open-locks`' and `test-open-settings`' comments said a whole-second build waits
    "2000 ms of it": it waits 1000, and a retry 2000. `test-open-locks`' header also had a retry
    take "at least another 1500"; both corrected. Each timed row's name now says "or 2000 on a
    whole-second build".
  - `test-contention` and `test-interrupt-reach` are past the brief's two suites: their W, T and
    busy rows had the same 3000 ms bound, and the same blind spot (the red runs).
- **`test-transaction-nomem`, item 5:** `control-kept`, the verdict of the memory check native
  registered at the load, run here: `kept` for `pass` or `fail`, `not-kept` for `unavailable`.
  A new row holds `memory-kept` to it: 26 rows, was 25.
- **The watchdogs, item 6, in `test-interrupt-reach`, `test-interrupt-close` and the new
  `test-transaction-interrupt`:**
  - each round is a procedure whose raise goes to one handler: it lets SQLite's mutex go if the
    round holds it, notes the raise among the first three as `(a-round-raised WHAT)`, counts
    the watchdog started, sleeps 1 ms, and the next round follows;
  - `holding` is cleared only after `mutex-leave` returns, and a round takes the mutex only when
    it doesn't hold it, so a `mutex-leave` that raised once is tried again;
  - `test-interrupt-close`'s race interrupter answers a raise in a turn as `(a-turn-raised
    WHAT)` among its other answers, and goes on.

- **The handshake, after `main`'s CI failed the long prepare:** the device's first round, in
  `test-interrupt-reach`, `test-interrupt-close` and `test-transaction-interrupt` (its section,
  below). Each binds `sqlite3_is_interrupted` and reads the handle before the fork.

The Makefile's shard lists are unchanged: no suite was split.

### How the plants ran

Each plant ran in a copy of the worktree, `build/s/NAME/`, made by `rsync -a --exclude .git
--exclude build`, with `build/m3-floor` copied in, through the copy's own `scripts/guix-env`,
after `make deps` there. A plant is a list of edits, each checked to match its file exactly once
(`plant.py`, with every plant's spec, kept in
[research/m3-review/suites/scripts/](research/m3-review/suites/scripts/)). The old suites ran as `tests/old-*.sps`, copied
from `e590fdc`, beside the new. Counts come from the suites' own `# of` lines. A floor run sets
`CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH` to the floor's.

**The whole-second build.** No library here sleeps in whole seconds, so the floor's 3.45.1
source, `build/m3-floor-dl/` in the main checkout, was compiled with CI's line and
`-DHAVE_NANOSLEEP=0`:

```
$CC -shared -fPIC -O2 -DSQLITE_THREADSAFE=1 -DHAVE_NANOSLEEP=0 -Wl,-z,defs \
  -o build/s/ws/lib/libsqlite3.so.0 build/s/ws-src/sqlite3.c -lpthread -lm
```

On it a 250 ms timeout answered busy after 0 ms, a 1500 ms one waited 1000 to 1001 ms, and the
suites printed `the grain: whole-seconds`.

### The red runs

| Row | Red run | Green |
|---|---|---|
| cache: near spellings | N3, keys compared by their first 4096 characters: old suite 32 passed; new 31 passed, 1 failed: `(hit "long")` for the near spelling, then `(miss)` for the key, count 3 | 32 passed |
| cache: capacity 1024 | `nmiss`, a missing check-out evicts the oldest: 26 and 25 passed, 6 and 7 failed, this row among them, `(miss)` for `select 1` | 32 passed |
| contention: the default | B03, the default `deferred`, with the second woken 700 ms late (`late-old`, `late-new`, in the suite): old row's default half passed as immediate's, `(#(3) no-second-read) #(4) … #(5)`; new row's failed, `saw-the-second-read`, `busy-snapshot` | 11 passed, late or not |
| the four grain rows | `grain-unread`, each read with no lock held: each suite 1 failed, `((unread (not-busy #<void>)) 3000)` or `(unread (raised …))` | each passes, `milliseconds` on both libraries, `whole-seconds` on the whole-second build |
| locks: waits; settings: busy first; contention: W and T; reach: the busy wait | `retry`, a step or prepare that answers 5 tried once more, on the whole-second build: the old suites passed, each wait 2000 to 2001 ms; the new failed each row, `too-long` | each 1000 to 1001 ms there, `waited` |
| nomem: agrees with the control | T16, `memory-kept` forced to `#f`: old 6 passed, 19 skipped, exit 0; new 6 passed, 1 failed, `not-kept` for `kept`, 19 skipped. Floor: the same | 26 passed |
| transaction-interrupt's four rows | below | 9 passed |
| the watchdogs, reach's three held rows, close's two, transaction-interrupt's four | below | |
| close: the race | below | |

#### Item 1: `test-transaction-interrupt`'s rows

Each plant on the final suite, on Guix's 3.53.1 and the floor's 3.45.1, the same counts on each;
the last three on Guix's alone (`enter-odd` also at the floor, before the leave's retry: the same).

| Plant | The mutant | Counts | Rows failed |
|---|---|---|---|
| `stub` | `with-transaction` calls its body plainly | 5, 4 | all four: nothing issued, the markers kept |
| `no-return` | `issued` never gives its statements back | 5, 4 | all four: every statement `done` |
| `no-rollback` | the after thunk does nothing | 7, 2 | the read, outer (`in-transaction?` yes) and nested (`COMMIT` of the inner's marker) |
| `depth-plus-one` | `begin-plan` given the depth plus one | 7, 2 | both nested: `SAVEPOINT chez_sqlite3_2` |
| `pL1` | the return's plan read at autocommit 0 | 8, 1 | the write, nested: `(sqlite-error with-transaction error error)` for `transaction-ended` |
| `watchdog-silent` | the watchdog never says it ended; `bound-ms` 2 s | 5, 4 | all four: `the-watchdog-did-not-end` |
| `no-interrupt` | the round calls no `sqlite3_interrupt` | 5, 4 | all four: `no-raise`; 47 s plain, 41 s at the floor |
| `cold` | no run before `with-transaction`: the watched call prepares | 7, 2 | both writes: autocommit 0 and `ROLLBACK` issued, the prepare interrupted (the trap) |
| `enter-odd` | `mutex-enter` raises on every odd call | 5, 4 | all four: `(the-watchdog-raised ((a-round-raised …)) the-watchdog-ended)`, each still interrupted |
| `sleep-odd` | the hold's `sleep` raises on every odd call | 5, 4 | the same |
| `leave-once` | `mutex-leave` raises on its first call | 8, 1 | the write, outer; the handler's second leave lets the mutex go, and the rest pass |

So each row fails at least three plants by its content, and the four watchdog plants by its
watchdog's answer: write outer `stub`, `no-return`, `cold`,
`leave-once`; write nested `stub`, `no-return`, `depth-plus-one`, `pL1`, `cold`; read outer
`stub`, `no-return`, `no-rollback`; read nested `stub`, `no-return`, `no-rollback`,
`depth-plus-one`; the watchdog plants `watchdog-silent`, `no-interrupt`, `enter-odd` and
`sleep-odd`, each all four.

#### Item 6: a raise in a round

| Plant | New suites | Old suites, `e590fdc` |
|---|---|---|
| `enter-odd` | reach 11, 3; close 6, 2; each in 1 to 2 s, `(a-round-raised (other "Exception in mutex-enter: …"))`, interrupted, `the-watchdog-ended` | reach 321 s, 10, 3: `(the-watchdog-never-started #t) no-interrupt-sent the-watchdog-did-not-end`, the step run to its row, and the busy row `cantopen`, the thread's death having removed the directory; close 201 s, 6, 2, its race `cantopen` too |
| `sleep-odd`, the hold's sleep | reach 11, 3; close 6, 2; in 0 to 3 s, named the same | reach and close each **hung**, `timeout` at 400 s, exit 124: the thread died holding SQLite's mutex |
| `race-odd`, the race's sleep | close 7, 1: `((a-turn-raised …) …)` among the answers, `the-interrupter-ended` | close 150 s, 7, 1: `none-on-a-closed-connection () the-interrupter-did-not-end`, the raise in no answer |
| `leave-once` | reach 13, 1; close 7, 1; the first watched row, in 0 to 2 s | not run: the old rounds never retry the leave |

Before the retry of a failed leave, `leave-once` hung the new reach suite too, `timeout` at 60 s.

### The plants that survive, argued

- **`no-randomblob`, the SQL without `randomblob`, passes plain and under the gate,** 10 and 11 s.
  The first round holds the mutex as the step starts, and the step allocates without
  `randomblob` too, its recursive CTE's queue among the rest; where each interrupt landed was not
  measured. `randomblob` is the second line, an allocation on every row for a round that misses,
  as in `test-interrupt-reach`.
- **`no-hold`, the rounds without the mutex, passes plain and under the gate,** 24 and 16 s on
  Guix's library. The device is about time, which no row asserts: `make test-memory`'s `SLOW`
  line, and CI's time, hold it. The old suite took 11 to 77 s here; the device 11 to 15 s.
- **The cache's non-string-key row keeps its `list` of six calls.** Its verdict can't turn on
  their order: it passes only when every call raises, and a call that raises changes no table,
  so any call that doesn't raise fails it in any order.
- **A grain forced to `milliseconds` on a whole-second build** is the code before the change,
  which the `retry` row of the red runs shows passing; not planted again. **One forced to
  `whole-seconds` on a millisecond build** passes: 1502 ms is under 2000 too, and no row tells
  the grain but its own read.
- **`memory-kept` forced to `#t`** passes here, where the control says `kept`; only a library
  that keeps no count, as Apple's, would tell it.
- **A `mutex-leave` that raises every time** leaves SQLite's mutex held, and the owner blocks at
  its next allocation for good: the device's one limit, written in each suite's header.

### Times

#### `test-transaction-interrupt`

Under the gate, by `make test-memory MEMORY_SUITES='tests/test-transaction-interrupt.sps'`'s
`time:` lines, each run alone in its copy unless said. The other two builders' suites ran
beside them throughout, load average 1.3 to 4.3 on 18 cores.

| | Guix's 3.53.1 | The floor's 3.45.1 |
|---|---|---|
| plain, before | 328, 336 ms | 326, 324 ms |
| plain, after | 304 ms; final, 333 and 542 ms | 308 ms; final, 339 and 387 ms |
| gate, before, side by side with the other library | 77, 29 s | 77, 31 s |
| gate, before, interleaved with after, beside `make test` | 22, 18, 36 s | 23, 18, 35 s |
| gate, before, pinned to two cores (`taskset -c`) | 14, 11 s | 14, 15 s |
| gate, after, side by side | 11, 11 s | 11, 11 s |
| gate, after, interleaved | 11, 11, 12 s | 12, 12, 13 s |
| gate, after, two cores | 11, 11 s | 14, 15 s |
| gate, after, with the seven other suites | 12 s | 11 s |
| gate, final (the leave's retry), with reach and close | 12, 13 s | 13, 12 s |
| gate, `no-hold` | 24, 16 s | |
| gate, `no-randomblob` | 10, 11 s | |

Slice 6 read 429 to 434 s here, and CI 31 to 318 s. None of today's before runs came near that:
the old suite's time is the scheduler's, and here ran 11 to 77 s. The device ran 11 to 15 s in
every run, so no split; the next CI run reads its time in shard 1 against ADR-0005's 150 s.

#### The other changed suites

| Suite | Plain before, Guix / floor | Plain after, Guix / floor | Gate before, Guix | Gate after, Guix / floor |
|---|---|---|---|---|
| `test-statement-cache` | 233 / 223 ms | 236 / 241 ms | 10 s | 12 / 11 s |
| `test-contention` | 4694 / 4687 ms | 4943 / 4974 ms | 18 s | 18 / 19 s |
| `test-open-locks` | 5892 / 5948 ms | 6156 / 6350 ms | 19 s | 19 / 21 s |
| `test-open-settings` | 1875 / 1878 ms | 2132 / 2140 ms | 16 s | 16 / 19 s |
| `test-transaction-nomem` | 352 / 368 ms | 346, 342 / 361, 346 ms | 13 s | 14 / 13 s |
| `test-interrupt-close` | 304 / 303 ms | final, 381, 310 / 297, 303 ms | 12 s | 12 / 12 s; final, 12, 13 / 15, 12 s |
| `test-interrupt-reach` | 2024 / 1976 ms | final, 2552, 2559 / 2349, 2327 ms | 17 s | 18 / 17 s; final, 17, 18 / 23 (failed, below), 18 s |

Each grain read adds about 250 ms plain. The whole-second build ran `test-open-locks` and
`test-contention` with each 1500 ms wait at 1000 ms.

### The traps the fixes found

- **The device interrupts a prepare too.** Its first round holds SQLite's mutex as the watched
  call starts; a call that prepares then blocks in the prepare's allocation, and the tokenizer
  sees the interrupt at its next space. `cold`, the suite with no run before `with-transaction`,
  failed both write rows plain, on both libraries: autocommit 0 and a `ROLLBACK` issued, for the
  write never began. A watched call finds its statement in the cache, or is the prepare the row
  is about, as `test-interrupt-reach`'s is.
- **A watchdog that dies holding SQLite's mutex hangs the owner for good.** The old reach and
  close suites under `sleep-odd` hung until `timeout`, exit 124, naming no row. A watchdog's
  handler lets the mutex go, and tries a failed `mutex-leave` again.
- **On a whole-second build a retry waits 2000 ms, under the 3000 ms bound.** Reproduced on the
  floor's source with `-DHAVE_NANOSLEEP=0`: `retry` waited 2000 to 2001 ms in five rows of four
  suites, and the old suites passed it. AGENTS.md's "so a retry in Scheme fails it" held only on
  a millisecond grain.
- **Slice 1's late-thread trap, again:** with the second thread 700 ms late, the old default row
  passed B03 by its default half, and failed on the real library by its deferred half,
  `(#(3) no-second-read)` where `saw-the-second-read` was due.
- **The order of a call's arguments decided two rows' verdicts.**
  [research/m3-review/suites/cache-order.sps](research/m3-review/suites/cache-order.sps) runs
  each old row's expression compiled and through `interpret`: under N3 the near-spellings row
  passes compiled and fails interpreted; under `nmiss` the capacity-1024 row fails compiled and
  passes interpreted; on the real table both pass both ways (`cache-order.txt`).
- `make-process-temp-directory`'s hook removing the directory when a thread dies, slice 6's
  trap, came again under the old suites and `enter-odd`: `cantopen` in the next row.

### The long prepare, unstopped: the handshake

`test-interrupt-reach`'s long-prepare row failed on `main`'s CI (run 44087748537, `memory-2`,
Ubuntu's 3.45.1, 24 s), and in 1 of my 27 gate runs at the floor:
`(#<statement> interrupts-sent the-watchdog-ended … (statement . 1) #(1))`. Slice 6's version and
mine failed alike.

#### The mechanism

Read in 3.45.1's source and in 3.54.1's, the nearest newer source here; 3.53.1's was not on hand.
Both agree:

- **Where the flag is cleared.** `sqlite3RunParser` clears the connection's interrupt at its
  start when no statement is active. `sqlite3Step` clears it as a statement starts with none
  active. `sqlite3OomClear` and `sqlite3_wal_checkpoint_v2` clear it too.
- **Nothing allocates before the parser's clear.** Our prepare passes the SQL with its NUL counted,
  so `sqlite3Prepare` copies nothing, and the parser's engine is on the stack
  (`sqlite3Parser_ENGINEALWAYSONSTACK`).
- **A prepare reads the flag only while its tokenizer runs:** at each space token, and once at
  the end of input. The code it then generates reads it only through `sqlite3ProgressCheck`, in
  label growth, column naming and the planner. So the window ends at the last token, well before
  the call returns: the probe's sends during code generation stopped nothing (below).
- **Slice 6's first round** slept 1 ms holding SQLite's mutex, then interrupted. The owner spends
  most of a trial in Scheme first, copying 3 MB of SQL inside `prepare-statement`; the round's
  interrupt then came before the parse's clear and was lost. After that, a later round had to win
  the CPU from Valgrind inside the tokenizer's window.

The probe ([research/m3-review/suites/prepare-race.sps](research/m3-review/suites/prepare-race.sps))
runs the row alone, N trials a process, under the gate's Valgrind options, at the floor, pinned to
two cores. A delay before the prepare, inside the watched thunk, raises the rate; a shorter IN
list did not.

| Device | Delay, items | Unstopped |
|---|---|---|
| slice 6's | 0, 1,000,000 | 0 of 32 |
| slice 6's | 50, 1,000,000 | 1 of 10 |
| slice 6's | 50, 300,000 | 1 of 20 |
| slice 6's | 200, 1,000,000 | 13 of 70 |
| handshake | 0, 1,000,000 | 0 of 35 |
| handshake | 50, 300,000 | 0 of 20 |
| handshake | 200, 1,000,000 | 0 of 40 |

**What the probe confirms.** It counts the sends that found the flag clear, so came after a clear.
- In the 4 unstopped trials of the last 30, each first such send came 5084 to 6356 ms into a call
  of 6913 to 7004 ms. Stopped calls took 2.8 to 3 s, so these sends came after the tokenizer had
  finished, in the code generation.
- In the 7 unstopped trials of the 30 before, 3 had no send after any clear, and 4 had one.
- Not shown directly: the instant of the parser's clear, which no API reads.

#### The fix: the handshake, the device's first round

Holding SQLite's memory mutex, the watchdog:
1. interrupts before the call starts, and notes it by name if the flag doesn't then read set;
2. lets the owner start;
3. reads `sqlite3_is_interrupted` each 1 ms until it reads clear, which only the call's own start
   or parse does;
4. interrupts again;
5. lets the mutex go.

Between steps 3 and 4 the owner is held at its next allocation from SQLite's heap: the
connection's lookaside slots run out within the first few hundred of a million expressions, and a
step allocates on every row. So
the second interrupt lands inside the window, on any scheduler.

- **When it is tried:** once. A raise in it falls back to the ordinary rounds: a second try could
  wait, holding the mutex, for a clear that came already.
- **The ordinary rounds** follow as before.
- **It needs** `sqlite3_is_interrupted`, from 3.41.0, so present at the floor; the handle is read
  on the owner's thread before the fork.
- **The hold now lasts the owner's whole way into its call.** The rule on the owner's calls
  already covered that span: they are Scheme, Chez's own `malloc`, a bind of an integer over a
  NULL, and the `__collect_safe` prepare or step.

**Same flaw in `test-transaction-interrupt` and `test-interrupt-close`, so both are fixed the same
way.** Their steps clear the flag as they start. A step reads it at every jump until it returns,
so a lost first round costs time, not the row. With the call made 200 ms late
(`late-step`), four runs each, alternating, pinned:

| | Slice 6's round | The handshake |
|---|---|---|
| `test-transaction-interrupt` | 22, 11, 13, 12 s | 11, 11, 11, 11 s |
| `test-interrupt-close` | 11, 45, 10, 10 s | 11, 11, 11, 11 s |

#### Proof: the suite, before and after

`test-interrupt-reach`, whole, under `make test-memory` at the floor, N = 20 each. `late-prepare`
is the plant that delays the long prepare 200 ms inside its thunk.

| | Pinned to two cores | Unpinned |
|---|---|---|
| slice 6's, as it is | 0 of 20 failed | 0 of 20 |
| the handshake, as it is | 0 of 20 | 0 of 20 |
| slice 6's, `late-prepare` | **6 of 20**, the long-prepare row each time, CI's actual | **9 of 20** |
| the handshake, `late-prepare` | **0 of 20** | **0 of 20** |

As written, slice 6's version failed 1 of 27 runs here and once on CI, which N = 20 can't show.

**Gate times with the handshake, s:**

| Suite | Guix's library | The floor |
|---|---|---|
| `test-interrupt-reach` | 16, 16 | 15 to 16 (4 runs) |
| `test-interrupt-close` | 10, 10 | 10 to 11 |
| `test-transaction-interrupt` | 11, 11 | 10 |

Plain, each about as before: reach 2.2 s, close 0.3 s, transaction 0.3 s, on both libraries.

#### The rows, watched failing on the handshake version

| Plant | reach | close | transaction-interrupt |
|---|---|---|---|
| `enter-odd` | 11, 3 | 6, 2 | 5, 4 |
| `sleep2-odd`, an ordinary round's hold sleep | 12, 2 | 7, 1 | 7, 2 |
| `hs-sleep-odd`, the handshake's sleep | 12, 2 | 7, 1 | 7, 2 |
| `hs-flag`, the first interrupt skipped | 11, 3 | 6, 2 | 5, 4 |
| `leave-once` | 13, 1 | 7, 1 | 8, 1 |
| `noint`, the device sends nothing | 10, 4 | 6, 2 | 5, 4 |
| `race-odd` | — | 7, 1 | — |

`transaction-interrupt`'s seven content plants read as before on both libraries: `stub` 5, 4;
`no-rollback` 7, 2; `depth-plus-one` 7, 2; `no-return` 5, 4; `pL1` 8, 1; `watchdog-silent` 5, 4;
`cold` 7, 2.

**Notes on the plants:**
- Every watchdog plant fails each row it reaches by name, `the-watchdog-raised` or the flag's
  note, with no hang.
- `noint` took 123, 118 and 52 s plain: the steps ran uninterrupted, and the prepare row read
  `#<statement>`.
- `cold` still fails both writes: the handshake meets the parse's clear and stops the prepare.
  That is the trap below, unchanged.

Not planted as a row plant: the handshake's second interrupt sent without waiting for the clear.
That is slice 6's round, whose rate the tables above give.

`make test`: ran 73, passed 73.

### For the records

- **ADR-0019's slice 6 amendment and the global constraints' interrupt rule:** the rows' device
  is now the handshake, in three suites.
- **ADR-0005, slice 6's open risk:** the device is in the suite, and no split was needed.
  Today's times are above; the 150 s finding is read on the next CI run.
- **AGENTS.md and the global constraints, the busy wait:** "under twice the timeout, so a retry
  in Scheme fails it" holds on a millisecond grain. A row that times a 1500 ms wait reads the
  grain first and bounds it at 2000 ms on a whole-second build, as four suites now do
  (ADR-0019's decision 11, amended).
- **AGENTS.md, the Valgrind watchdog rule:** add the handshake. An interrupt stops a call only
  inside it: SQLite clears it as a statement starts and as a parse starts, and a prepare reads it
  only while its tokenizer runs. So the watchdog's first round, holding the mutex, interrupts
  before the call starts, waits for the flag to read clear, then interrupts again. Also: a
  watched call must not prepare unless the prepare is the subject; and the handler of a raise
  lets SQLite's mutex go.
- **traps.md:**
  - the first two traps above;
  - the whole-second retry, beside "A busy wait's grain is the build's";
  - `test-contention`'s default row in slice 1's late-thread account;
  - and, under the Valgrind watchdog trap, the lost first round: an interrupt sent before the
    call's own clear is lost; a prepare reads the flag only while it tokenizes, not in its code
    generation. With slice 6's round the long prepare ran unstopped once on CI, in 1 of 27 runs
    here, and, delayed 200 ms, in 15 of 40 suite runs and 13 of 70 probe trials; with the
    handshake, 0 of 40 and 0 of 95.
  - The account of "An interrupt sent as a statement starts stops it before its busy wait" gains
    its pair: SQLite clears the flag as the parse starts too.
- **ADR-0005's amendment and traps.md's "One CI run is one sample":** the old suite's gate time
  ran 11 to 15 s pinned to two cores and 18 to 77 s on all 18, today; it is the scheduler's.
- **The probes:** `.plans/research/m3-review/suites/cache-order.sps` and
  `prepare-race.sps`, each with its output.

### Reproducing

From the worktree's root, on the host:

```
scripts/guix-env sh -c 'make test'
scripts/guix-env sh -c "make test-memory MEMORY_SUITES='tests/test-transaction-interrupt.sps'"
scripts/guix-env sh -c 'CHEZ_SQLITE3_LIBRARY=$PWD/build/m3-floor/lib/libsqlite3.so.0 C_INCLUDE_PATH=$PWD/build/m3-floor/include make test-memory MEMORY_SUITES=tests/test-transaction-interrupt.sps'
scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-review/suites/cache-order.sps'
taskset -c 2,3 scripts/guix-env sh -c '.plans/research/m3-review/suites/scripts/race.sh floor old 1000000 200 30 LABEL'
taskset -c 2,3 scripts/guix-env sh -c '.plans/research/m3-review/suites/scripts/race.sh floor handshake 1000000 200 30 LABEL'
```

`race.sh` runs `prepare-race.sps` under the gate's Valgrind options, writing into `build/s/race/`; its arguments are the
library, the device, the IN list's items, the delay in ms, the trials and a label.

A plant, with the kept scripts in `.plans/research/m3-review/suites/scripts/` as `S`:
`$S/mkcopy.sh NAME && python3 $S/plant.py build/s/NAME $S/specs/SPEC.py`,
then `make deps` and the suite in the copy.
