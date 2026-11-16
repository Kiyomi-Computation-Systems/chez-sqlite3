# M3 slice 6 mutation log

Evidence that each rule slice 6's suites claim to guard fails through the property it names
([M3 plan](2026-11-15-m3-plan.md) §5, slice 6, §4.4, §4.8 and probe P5). Format of
[the M3 slice 5 log](m3-slice-5-mutation-log.md). The slice is built in two parts, each keeping
its own part of this log: A, `interrupt-database!` and the close's exclusion; B, contention.

## Part A: `interrupt-database!` and the close's exclusion

An Opus agent built part A from the lead's brief, in the slice's worktree, on
`m3-slice-6-interrupt` from slice 5's head `635f5c5`.

### What part A adds

- **`(chez-sqlite3 private connection)`:**
  - the record's `latch` field, last, made by slice 1's `make-interrupt-latch`;
  - `connection-outcome`'s section opens the latch once the record exists;
  - `close-connection` runs its work through `interrupt-latch-close!`, which clears the flag
    before the first finalize, and `close-left-open?` names the two outcomes that leave the
    connection open, `untracked` and `failed`, after which the latch sets it again;
  - `interrupt-database! : Database -> Void`, exported: it checks only that its argument is a
    database, then calls `interrupt-latch-interrupt!` with a thunk that reads the record's handle
    and calls `sqlite3-interrupt` on it, and answers the void object.

  The verb lives here because the record and its handle do: the handle's one accessor,
  `call-with-open-handle`, makes the owner and open checks the verb must not make (ADR-0012,
  decision 2), so a verb anywhere else would need a second accessor. The handle is read inside
  the latch's thunk, under its mutex and only while the flag is set, which the close clears
  before it can null the handle: so a set flag means a live handle.
- **`(chez-sqlite3)`:** `interrupt-database!` among the connections, `sqlite-interrupt?` among
  the conditions: 68 names.
- **`docs/reference.md`:** `interrupt-database!`'s entry, after `database?`; `sqlite-interrupt?`'s,
  after `sqlite-read-only?`; the Conditions table's kinds of `sqlite-error?`, the count still
  seven; the Connections section's thread rule.
- **The suites:** `test-interrupt-database`, `test-interrupt-reach` and `test-interrupt-close`,
  new; `test-public`'s count, its list of where each name is defined, and its row of the
  connection library's exports.

`(chez-sqlite3 private interrupt)`, `open.sls`, the conveniences, the statement tier and
`transaction.sls` are unchanged.

### How the mutants ran

Every mutation ran in a copy of the worktree of its own, `build/mut/NAME/`, made by
`tar --exclude=./build --exclude=./.git`, with `build/m3-floor` copied in, through the copy's own
`scripts/guix-env`, after `make deps` in the copy, each suite under `timeout 300`. A mutation is
a list of edits, each checked to match its file's text exactly once before it is written. The
counts are read from the suites' own output (`# of unexpected failures`), never by eye; none died
or hung. The driver (`mutants.py`, `run-mutant.sh`) and every log are in the session's
scratchpad, not the repository.

### The red runs

The new suites were written first and run against `635f5c5`'s libraries, where
`interrupt-database!` does not exist: each row that calls it fails by name, reached through
`eval` as "could not be reached". The changed suites ran against a copy of `635f5c5`
(`git archive`) with the new `test-public` and `docs/reference.md` put in.

| Suite | Red run | Green run |
|---|---|---|
| `test-interrupt-database`, against `635f5c5` | 4 passed, 9 failed | 13 passed; 15 with K1's and K2's rows, each watched failing against its mutant (below) |
| `test-interrupt-reach`, against `635f5c5` | 5 passed, 8 failed | 13 passed |
| `test-interrupt-close`, against `635f5c5` | 5 passed, 3 failed | 8 passed |
| `test-public`, against `635f5c5` | 18 passed, 4 failed | 22 passed |
| `test-reference`, against `635f5c5` with the new page | 18 passed, 2 failed | 20 passed |
| `test-docs`, against `635f5c5` with the new page | 96 passed, 3 failed | 99 passed |

The rows that passed red are each new suite's load row, its counts rows, its temporary
directory, and the rows that read SQLite's memory mutex and the long prepare's length. Against
`635f5c5`, `test-docs` failed the page's two new runnable examples and its code-span rule (the
`sqlite-interrupt?` span named no export). `test-interrupt-reach`'s first red run died on its
own syntax, an unquoted `#(1)` under `#!r6rs`, and was rerun once fixed. The busy wait's row
gained its probe read, `set`, after the red run: M01 below fails it.

Green: `make test` ran 71, passed 71, against the baseline's 68 of 68, the three new suites
added; at the floor, 3.45.1, through `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH`, it ran 71 and
passed 71 too, every suite at the same count, and SQLite answered alike. Plain, each new suite
takes 2 s or less on either library; the busy wait ran 1502 ms on both. Under the memory gate,
twice on each library, the three new suites and `test-public` passed with no error and nothing
lost, none `SLOW`, by the gate's `time:` lines:

| Suite | Guix's 3.53.1 | The floor's 3.45.1 |
|---|---|---|
| `test-interrupt-database` | 10 s, 10 s; with K1's and K2's rows, 10 s, 10 s | 10 s, 10 s; with them, 10 s, 11 s |
| `test-interrupt-reach` | 15 s, 14 s; again, 15 s, 15 s | 15 s, 15 s; again, 15 s, 14 s |
| `test-interrupt-close` | 10 s, 10 s; again, 10 s, 10 s | 10 s, 9 s; again, 10 s, 10 s |
| `test-public` | 10 s | 10 s |

The busy wait ran 1509 to 1514 ms under the gate; the race made 60 to 270 interrupts there, 50
to 190 of them on a closed connection, and 60 to 140 plain, 25 to 99 on a closed one.

### The watchdog under the gate

Valgrind runs one thread at a time, and a thread running C keeps the lock: slice 4's watchdog,
meant to interrupt every 5 ms, sent its first interrupt 16.5 s into a step ([traps.md](traps.md)).
A long step ends anyway, once the watchdog gets in. A prepare doesn't wait for it. Measured in the
container, with a watchdog interrupting `prepare-statement` of `SELECT 1` and 4 MB of empty
comments (`build/m3s6-probe/prepare-gate.sps`, git-ignored, kept for the records):

| Run | The watchdog | Each of three prepares |
|---|---|---|
| plain | no sleep | five of six interrupted, 166 to 173 ms, 87,507 to 122,761 interrupts sent; one prepared, 177 ms, after 115,334 |
| plain | 1 ms sleep | prepared, 176 to 184 ms, 17 to 23 sent |
| Valgrind | no sleep | prepared, 3751 to 4033 ms, **0 sent**, nine of nine |
| Valgrind | 1 ms sleep | prepared, 3843 to 4055 ms, **0 sent** |

**Corrected after the lead's rerun:** "0 sent" is not the whole of it. The lead's rerun of the
no-sleep case sent 0, 125 and 0 interrupts, and the prepare finished every time, even after 125.
What holds on every run is that the watchdog stopped none of the twelve prepares under Valgrind;
how many interrupts it sent, all landing before the prepare's C part or none, is the scheduler's.
And plain, a watchdog that spins stopped five of six, not every one.

So the plan's long prepare (§4.7) could not pass under the gate with any watchdog that waits its
turn. The suites' watchdog makes the owner give way instead: each round it takes SQLite's own
memory mutex, `SQLITE_MUTEX_STATIC_MEM`, which `sqlite3_malloc` and `sqlite3_free` take while
memory statistics are on, sleeps 1 ms holding it, calls the verb, lets go, and sleeps 1 ms. A
call that allocates as it runs blocks inside SQLite at its next allocation, and the watchdog,
the one thread then runnable, sends its interrupt there. Comments allocate nothing, so the
prepare's SQL is `select 1 in (1, 1, …, 1)`, a million and one items, 3,000,015 characters: an
expression for each item, and a space after each comma for the tokenizer's check. The long step
calls `randomblob` on each row. Measured with `build/m3s6-probe/prepare-mem.sps`: under
Valgrind, three of three prepares of 300,001 items stopped, 786 to 839 ms, each in the
watchdog's first round; plain, a million items stopped in 123 to 124 ms, in 7 or 8 rounds.

Each call the owner makes while the watchdog may hold the mutex allocates nothing of SQLite's,
as a bind of an integer over a NULL, or is `__collect_safe`, as the step, the prepare and the
finalize: an owner blocked on the mutex in a call that holds off collections, while the
watchdog holding it starts one, would deadlock. Reasoned from Chez's collection rendezvous, not
reproduced. The busy wait's watchdog takes no mutex: the owner sleeps in the busy handler,
which lets it run. Memory statistics are on in Guix's 3.53.1 and the floor's 3.45.1, where the
memory check's control rises; Apple's 3.51.0 keeps none, so there the watchdog's rounds race
the owner as threads do outside Valgrind.

**The hold is no critical section; measured after the lead's proposal.** The lead proposed
wrapping each round's hold, from `mutex-enter` to `mutex-leave`, in `critical-section`, so that
the watchdog never handles a collect request, and never starts a collection, while it holds the
mutex, whatever the owner calls. The reasoning about sections holds (`build/m3s6-probe/section.sps`,
twice):

- a collect request made inside a section waits for its end: 105,600,000 bytes allocated inside
  one, against a `collect-trip-bytes` of 8,388,608, and `(collections)` read 1 at the section's
  end and 2 just after it;
- `sleep` of 200 ms inside a section slept 200 ms, and `with-mutex` inside one waited 300 ms for
  another thread's hold;
- another thread's `(collect-rendezvous)` waited for the section to end, 500 and 501 ms, whether
  the thread inside it slept or spun. A `sleep` outside a section lets another's collection
  proceed; inside one it doesn't.

That last fact defeats the device. The owner allocates heavily as it copies its 3 MB of SQL
before the prepare, and starts collections there; each now waits for the watchdog's section to
end, and the section's end lets the mutex go. Between rounds the watchdog sleeps without it, and
Valgrind's one thread at a time then keeps it out while the owner reaches its C call. With the
section, the long prepare ran unstopped, `#<statement>` prepared and counted, in all four gated
runs of `test-interrupt-reach` (two on Guix's 3.53.1, alone; one on each library beside another
run); plain, every row passed. The long steps still stopped: a step runs until a later round's
hold catches it at a `randomblob`. So the suites keep the hold outside any section, as built, and
the header's rule about the owner's calls is the one line of defence.

An alternative that keeps the device, measured but not applied (`build/m3s6-probe/sleep-alloc.sps`
and the copy `build/mut/hold-alt/`): take the mutex, set the flag and sleep outside any section,
which allocate nothing (0 bytes over 200 and 1000 calls each, where a `cons` made 16 a call and
`critical-section` itself 48 at its entry), so no collect request can arise while the mutex is
held there; then `disable-interrupts`, call the verb, clear the flag, let the mutex go, and
`enable-interrupts`, so the verb's allocation can't start a collection until the mutex is gone (0
bytes over 200 calls for the window but the verb). The sleep stays outside, so the owner's
collections go on past it. In the copy, `test-interrupt-reach` and `test-interrupt-close`
passed plain, and under the gate twice on each library: 14 to 15 s and 9 to 10 s.

### The mutations

The five suites: `test-interrupt-database` (database), `test-interrupt-reach` (reach),
`test-interrupt-close` (close), slice 1's `test-interrupt` (interrupt) and `test-connection`
(connection). Baselines, from the green runs: 13, 13, 8, 19 and 63; 15 for the database suite
once K1's and K2's rows joined it. Each row names the suites
that failed and how many rows failed in each; `test-connection` failed none. A mutation counts as
caught when at least one row failed. Three of them change slice 1's `interrupt.sls`, in the copy
only, since the record's clear and flag live there.

| Mutation | Guards | Failed |
|---|---|---|
| M01 | the open sets the flag (`interrupt-latch-open!` dropped from `connection-outcome`) | database 3, reach 8 |
| M02 | the close runs its work through the latch (the work in a plain critical section) | database 6, close 1 |
| M03 | the close clears the flag (the latch's clear dropped) | database 6, close 1, interrupt 9 |
| M04 | the close clears it before the work (cleared after) | database 5, interrupt 3 |
| M05 | a statement found untracked sets the flag again (`untracked` out of `close-left-open?`) | database 3, close 1 |
| M06 | `sqlite3_close` failing sets the flag again (`failed` out of it) | database 1, close 1 |
| M07 | a close that closed doesn't set it again (`close-left-open?` always true) | database 1, close 1 |
| M08 | the interrupt reads the flag: P5's plant, `sqlite3_interrupt` whatever it says | database 6, close 1, interrupt 11 |
| M09 | the verb goes through the latch: the handle read, then `sqlite3-interrupt` when it is not `#f` | database 5 |
| M10 | the verb checks its argument is a database | database 1 |
| M11 | the verb makes no owner check (`check-owned` added) | database 2, reach 8, close 3 |
| M12 | the latch's mutex, in the real record (`with-mutex` dropped from the flag's set and the interrupt) | interrupt 1; **survived the new suites** |
| M13 | the verb answers void (the latch's boolean answered) | database 8, reach 8, close 3 |
| M14 | the handle read inside the latch's thunk (read before the latch instead) | **survived** |
| K1 | a close that closed and raised a finalize's failure, M2's R1, doesn't set the flag again (`finalize-failed` in `close-left-open?`) | database 1, of 15 |
| K2 | a second close doesn't set it again (`already-closed` in `close-left-open?`) | database 1, of 15 |

**16 mutations: 14 caught by the new suites, 15 by the five, one survived, equivalent.** K1 and K2
are the lead's. Both survived every suite as first built, `test-interrupt-*`, `test-interrupt`,
`test-connection` and the `test-open-*` suites: no row interrupted after a close that closed but
raised, nor after a second close. Each sets the flag on a closed connection, whose handle is
`#f`, so a later `interrupt-database!` raises Chez's refusal of `(sqlite3-interrupt #f)`, against
ADR-0019's decision 4. Two rows of `test-interrupt-database` now hold them, each watched failing:

- **a close that closes and then raises a finalize's failure:** a file holding `t`, another
  connection's `select` held at its row, and the connection's own `insert … returning` stepped
  once, which can't commit, so its finalize answers busy (M2's R1; `test-statement`'s rows). The
  close raises `&sqlite-error` busy and busy, the connection closed; the verb from inside the
  close reads clear; then the verb from the owner and from another thread answers void. Against
  K1 both answered `(answered (raised (assertion-violation "sqlite3_interrupt" (#f))))`; the row
  alone failed, 14 of 15 passing;
- **a second close:** closed, closed again, then the verb from the owner and from another thread
  answers void. Against K2 both answered the same refusal; the row alone failed, 14 of 15.

Which rows: M01 fails every row that reads the flag set, but no row of a close left open, since
the close's set again makes such a connection interruptible whatever the open did. M02, M03, M08
and M09 fail the five rows that call the verb from inside a close, where the probe reads `set`;
M02, M03, M07 and M08 fail the closed-connection row and the race, whose interrupt of a closed
connection raises on its `#f` handle. M04 fails the rows inside the close alone. M05 and M06 fail
the rows of their own path, and `test-interrupt-close`'s row after that path, whose step then
runs its 100,000,000 rows to its answer, 43 s. M10 fails the refusals' row: the record's own
accessor refused each value, as `unchecked-database-latch`, the string by its text, `"app.db"`,
where the verb names it `(kind string)`. M11 fails every row whose interrupt comes from another
thread, and the long steps run to their answers. M13 fails every row that reads the verb's answer.

**M12, the mutex dropped,** survives the new suites, and slice 1's race row fails it, as its I01
did. The schedule it opens: the interrupter, inside its section, reads the flag set; the owner,
inside the close's section, which keeps out only its own thread, clears the flag without waiting
and runs the work; the interrupter then calls `sqlite3_interrupt` on a connection the close is
freeing. In the real record nothing holds the interrupter between its read and its call: the call
is `sqlite3_interrupt` itself, microseconds, with no hook. Tried against the race: at 200 rounds,
three plain runs (490 to 510 interrupts, 355 to 382 on a closed connection) and one under the
gate (1320, 1240; no Valgrind error) all passed. Slice 1's row holds the interrupter in flight
with a stand-in and starts the close's work in that window, which is the schedule; with M12 its
notes came out `(interrupt-start work-start interrupt-end work-end)`, the work started while the
interrupt was in flight. So the exclusion's mutex is
held by slice 1's stand-in row, as ADR-0019's consequences planned.

**M14, the handle read before the latch,** is equivalent. Every schedule tried: on one thread, an
interrupt from inside the close reads the live handle and the flag clear, and calls nothing (the
five rows inside the close pass); on a closed connection the handle reads `#f` and the flag clear;
after a close left open, the handle is live and the flag set. Across threads, a handle read just
before the close is used only if the interrupter then holds the mutex with the flag still set, and
then the close's clear waits for it, so the handle is live when it is used. The 200-round race
passed three times plain (510 to 800 interrupts, 426 to 638 on a closed connection) and once
under the gate (1070, 990; no error). The library reads the handle inside, where the flag's
meaning covers it.

### P5: the plant under the gate

P5's plant is M08: `interrupt-latch-interrupt!`'s flag test made `#t`, in `build/mut/a/`, run
under `make test-memory` through the copy's own `scripts/guix-env`.

- **Valgrind reported no invalid access** against it: "ERROR SUMMARY: 0 errors from 0 contexts",
  over 1, 20 and 200 rounds of the race (20, 40 and 1560 interrupts, 10, 20 and 1550 of them on a
  closed connection), and in `test-interrupt-database`.
- **The race row failed by name** all the same, at every round count, from 1: the close clears
  the record's handle, so the plant's call on a closed connection reached `sqlite3-interrupt`
  with `#f`, and Chez refused it before C, `(assertion-violation "sqlite3_interrupt" (#f))`. The
  row's last call is made certain to land on a closed connection: the owner stops the
  interrupter only once one has. So the fewest rounds at which the plant fails is 1. The row keeps
  20, the lead's call: under the gate 1, 20 and 200 rounds cost the same 10 to 11 s, so 20 buys a
  race of real interleavings at no cost.
- **A second plant, P5b,** reads the handle before the latch and calls only when it is not
  `#f`, the flag still ignored: no exclusion at all, and no raise. Under the gate, 200 rounds, the
  race passed with no Valgrind error (890 interrupts, 870 on a closed connection): Valgrind's one
  thread at a time never ran the interrupter between its read and its call while the owner freed
  the connection. `test-interrupt-database`'s five rows inside the close failed it.
- **Valgrind does see the access itself,** measured directly in the copy
  (`build/mut/a/build/p5/direct.sps`: open, read the handle, close, `sqlite3-interrupt` on it),
  on both libraries. At the floor:

  ```text
  Invalid write of size 4
     at 0x50D14A0: sqlite3_interrupt (in …/build/m3-floor/lib/libsqlite3.so.0)
   Address 0x4c61f58 is 408 bytes inside a block of size 792 free'd
     at 0x48489EB: free (in …/vgpreload_memcheck-amd64-linux.so)
     by 0x50D360A: sqlite3_free (in …/build/m3-floor/lib/libsqlite3.so.0)
     by 0x5143AD9: sqlite3Close.part.0 (in …/build/m3-floor/lib/libsqlite3.so.0)
   Block was alloc'd at
     at 0x4845772: malloc (in …/vgpreload_memcheck-amd64-linux.so)
     by 0x519DEAA: openDatabase (in …/build/m3-floor/lib/libsqlite3.so.0)
  ```

  On Guix's 3.53.1 the same write lands 408 bytes inside a block of 840.

So the gate's race row sees nothing of a missing exclusion: no schedule the gate ran put a stale
handle into C. What holds the exclusion is `test-interrupt-database`'s rows inside the close,
one thread, no timing, which fail M02, M03, M04, M08, M09 and P5b; and slice 1's stand-in row,
which fails M12 (ADR-0019's consequences).

### The lead's checks

Run by the lead on part A's hand-back, in the worktree and in a copy under its git-ignored
`build/lead-mut/A`.

- **`make test`:** ran 71, passed 71. After the follow-up, the three new suites passed again.
- **P5's direct probe** reproduced on 3.53.1: "Invalid write of size 4 at sqlite3_interrupt",
  408 bytes inside a freed block of 840.
- **The device** reproduced under Valgrind: `prepare-mem.sps 300000 hold 3` stopped 3 of 3
  prepares in the watchdog's first round. The plain watchdog, `prepare-gate.sps 4 0 3`, sent 0,
  125 and 0 interrupts, and stopped none.
- **The lead's mutants** (`build/lead-mut/drive-a.py`), against the three new suites,
  `test-interrupt`, `test-connection` and the four `test-open-*` suites:

  | Mutation | What it plants | Failed |
  |---|---|---|
  | K1 | `close-left-open?` true for `finalize-failed` too: a closed connection made interruptible | **survived**, then the R1 row added in the follow-up |
  | K2 | `close-left-open?` true for `already-closed` too | **survived**, then the second-close row added in the follow-up |
  | K4 | the verb answers the latch's answer, not nothing | 19 rows of the three new suites |
  | K5 | the open sets the flag in `opened-database`, after its section, not inside it | survived, equivalent |

  - **K1 and K2** set the flag on a connection whose handle is gone. The interrupt then hands `#f`
    to `sqlite3_interrupt`, which Chez refuses, so the verb raises on a closed connection, against
    ADR-0019's decision 4. No row closed a connection that way before interrupting it.
  - **K5 is equivalent.** Every connection an open verb returns passes `opened-database` first, so
    each is interruptible before its caller has it. A run that expires between the section and
    `opened-database`, and is never resumed, returns no connection to anyone, and only the record's
    own engines and interrupts could reach that window.
- **The hold window is not a critical section.** At the lead's request the builder wrapped each
  round's hold, from `mutex-enter` to `mutex-leave`, in one. Its probe confirmed the reasoning:
  a collect request made inside a section waits for its end, and another thread's collection
  waits too. But that is what broke the device. The owner's collections, made while it copies its
  SQL, waited for the section's end, which released the mutex, and under Valgrind the watchdog
  then could not get back in. The long prepare ran unstopped in all 4 gated runs, so the code
  stays as built.
- **The builder's alternative is not applied.** It sleeps holding the mutex with interrupts on,
  and disables them only around the verb and `mutex-leave`. It allocates nothing in the window,
  but a collect request the owner raised can still be handled by the watchdog, mid-sleep with the
  mutex held, since the thread that handles a request is whichever checks for events first. So it
  narrows the hazard without closing it. The guarantee in either shape is the header's rule: every
  call the owner makes while the watchdog may hold the mutex is `__collect_safe` or takes none of
  SQLite's memory.

## Part B: contention

An Opus agent built part B from the lead's brief, in the slice's worktree, on
`m3-slice-6-interrupt` over part A's `00dbb28`.

### What part B adds

Part B changes no library's code.

- **`tests/test-contention.sps`, new:** two connections to one WAL file, each opened, used and
  closed on a thread of its own, each with `((journal-mode . wal) (busy-timeout . 1500))`, or 250
  for the grain, and each answering its two settings as read back first, its premise. Seven
  rows, with the load row and the two counts rows, 10 in all:
  - **W, waits out:** `BEGIN IMMEDIATE`, under the other's `BEGIN IMMEDIATE` and write, waits at
    least 1000 ms and under 3000, then raises `&sqlite-busy`, `busy` and `busy`, from `execute!`;
    the waiter is left in autocommit (concurrency B3, B6);
  - **T, the default waits out,** added after the lead's J3: the same, through `with-transaction`
    with no mode, so its own `BEGIN IMMEDIATE`. It waits at least 1000 ms and under 3000, then
    raises `&sqlite-busy`, `busy` and `busy`, from `with-transaction`, naming `"BEGIN
    IMMEDIATE"`; nothing is begun, `in-transaction?` false and the depth 0, read by the
    connection's private `database-depth` as `test-transaction-engine` reads it; and the body,
    which would say so on the board, never runs (ADR-0019, decisions 8 and 11);
  - **M, mid-wait:** the other commits 500 ms into the wait; `BEGIN IMMEDIATE` succeeds after the
    commit and before its timeout's end, and sees the other's row; it prints how long after the
    commit it returned (slice-0 P3);
  - **U, the upgrade:** a deferred transaction reads; the other commits a write in autocommit; the
    reader's write raises `busy` and `busy-snapshot` at once, under 1000 ms, and again when tried
    again; it is still in a transaction, still reads 3 rows; rolled back, a new transaction's
    write commits, and it reads 5 (B5);
  - **S, the snapshot:** a reader in a transaction reads 3 rows while the other commits a write in
    autocommit, holds one open in `BEGIN IMMEDIATE`, and commits it, each at once; once it
    commits, it reads 5 (B4);
  - **D, the default:** two threads each run `with-transaction`, no mode, on a body that reads,
    then writes. The first's body waits up to 500 ms for the second's read, which never comes:
    the second's `BEGIN IMMEDIATE` is waiting for the first's commit. The second then reads 4,
    and both commit. The same bodies under `'deferred` both read 3, the first commits, and the
    second's write raises `busy-snapshot`, its level rolled back, 4 rows in all;
  - **G, the grain:** probe P4. `BEGIN IMMEDIATE` with a 250 ms timeout raises `busy` and `busy`
    under 500 ms, which holds on either grain, and the row prints `P4: SQLite V sleeps in
    milliseconds` (or `whole seconds`), from 125 ms.

  Every wait for another thread is bounded: a thread waits up to 10 s for the other's word and
  raises, naming it, when it never comes; the main thread waits up to 30 s for each answer, and
  one not given is `unfinished`. Whatever a thread raises is its answer, the busy conditions W,
  T, G and D's deferred run expect among them.
- **`docs/reference.md`:** `sqlite-busy?`'s entry gives each case and its remedy (ADR-0019,
  decision 9): a table of the extended codes, `busy-snapshot`, `locked` and `busy`; the four
  plain `busy` cases, B2, B3, B7 and B11; which leave the transaction open; keep `busy-timeout`
  short, since an interrupt doesn't stop a busy wait; and a run example, a `drop table` beside
  the connection's own `select` on a row, `(locked #(2))`. `with-transaction`'s sentence on
  `'deferred` now says the write can't wait only once the transaction has read, as B2 and
  trap 4 measured, names `busy-snapshot`'s case, and links the entry.

### How the mutants ran

Every plant ran in a copy of the worktree of its own, `build/mut/b/NAME/`, made by
`tar --exclude=./build --exclude=./.git`, with `build/m3-floor` copied in for the floor's runs,
through the copy's own `scripts/guix-env`, after `make deps` in the copy, each suite under
`timeout 300`. A plant is a list of edits, each checked to match its file's text exactly once
before it is written. The counts are read from the suites' own output (`# of unexpected
failures`), the rows from its `FAIL` lines, never by eye; none died or hung. The driver
(`mutants.py`, `rows.py`) and every log are in the session's scratchpad, not the repository.

### The red runs

Part B adds no library code, so no row has a red run against a missing feature: each was watched
failing against the plants below. The suite's first run failed D alone, on its own expected
value: `3` where `query-row` answers `#(3)`. T, added after the lead's J3, was watched failing
against J3, 9 passed and 1 failed, T alone, its wait 3004 ms, `too-long`; then it passed on the
real code, 1502 ms. The page's new run example and link were watched failing against D1 and D2.

| Suite | Red | Green |
|---|---|---|
| `test-contention` | B01 to B12 and J3 each failed it, 1 to 7 of its 7 rows (below) | 10 passed; 9 before T |
| `test-docs`, the new page | D1 and D2: 100 passed, 1 failed each | 101 passed, part A's 99 and the new example's two rows |
| `test-reference`, the new page | | 20 passed |

The thread plant first failed every row, the three whose threads raise and the three whose don't
alike. A thread that dies on a raise runs the base exception handler, where
`make-process-temp-directory`'s hook removed the suite's one directory, so every later row's
open answered `cantopen`. The suite now gives each row its own directory, by
`call-with-temp-directory`, and the plant fails W, D and G alone, each `unfinished` (the trap,
below).

Green: `make test` ran 72, passed 72, part A's 71 and `test-contention`, before T and again with
it; at the floor, 3.45.1, through `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH`, it ran 72 and
passed 72 too. Under the gate,
`test-docs` took 33 s on 3.53.1 and 32 s at the floor, and `test-reference` 10 s on each, both
passing with no error.

### The waits, timed

Every wait each row printed, in ms, on the final suite, T among its rows: plain, and under the
gate, two runs each on each library, first run first.

| Row | The wait | 3.53.1 | 3.45.1 | 3.53.1, gate | 3.45.1, gate |
|---|---|---|---|---|---|
| W | `BEGIN IMMEDIATE`, waited out | 1503, 1502 | 1502, 1502 | 1514, 1512 | 1512, 1512 |
| T | `with-transaction`, waited out | 1502, 1502 | 1502, 1502 | 1512, 1512 | 1512, 1512 |
| M | `BEGIN IMMEDIATE`, ended mid-wait | 529, 529 | 529, 529 | 532, 532 | 532, 535 |
| M | from the other's commit to its return | 29, 29 | 29, 29 | 28, 28 | 28, 30 |
| U | the upgrade's write, `busy-snapshot` | 0, 0 | 0, 0 | 1, 1 | 1, 1 |
| S | the writer's autocommit insert | 0, 0 | 0, 0 | 1, 0 | 1, 1 |
| S | its `BEGIN IMMEDIATE` and insert | 0, 0 | 0, 0 | 1, 1 | 1, 1 |
| S | its `COMMIT` | 0, 0 | 0, 0 | 1, 0 | 0, 0 |
| D | immediate: the second's call to its first read | 529, 529 | 529, 530 | 532, 533 | 532, 532 |
| D | deferred: the same | 0, 0 | 0, 0 | 1, 1 | 1, 2 |
| G | `BEGIN IMMEDIATE`, a 250 ms timeout | 250, 251 | 251, 251 | 253, 252 | 253, 254 |

- **W's and T's waits ran 1502 to 1514 ms,** about 1.5 s under their bound of 3000 on either
  library, as slice 5's did. The waits M's commit and D's ended ran 529 to 535 ms, 500 of them
  the other's hold. The suite before T, on the same machine, gave the same figures to within
  2 ms.
- **M returned 28 to 30 ms after the other's commit,** P3's 28.7 to 29.1 ms medians: the busy
  handler's next retry.
- **D's deferred second read at once, 0 to 2 ms after its call, under the gate too,** so the
  first's 500 ms window for that read was never near its end. Its immediate second waited
  the window out.
- **The waits total about 4.3 s of the suite's wall time,** W's and T's 1.5 s each, the two
  500 ms holds, and G's 250 ms: the plan's budget was near 20 s (§4.7).
- **The suite took 4.7 s plain on each library,** 4683 and 4680 ms on 3.53.1, 4676 and 4675 at
  the floor, a program's whole run inside the container (3.2 s before T); **under the gate, 15 s
  in each of the four runs** (13 to 14 s before T), by the gate's `time:` lines, each with "ERROR
  SUMMARY: 0 errors" and nothing lost, none `SLOW`, far under a quarter of the 450 s limit, so it
  is not split.

### P4: the busy wait's grain

**Both libraries here sleep in milliseconds,** read through the library on 3.53.1 and the
floor's 3.45.1 alike: G's 250 ms timeout answered busy after 250 to 251 ms plain and 252 to 254
under the gate, where a whole-second build answers at once, and W's and T's 1500 ms waited 1502
to 1514, where a whole-second build waits 1000 (concurrency B3, its `HAVE_NANOSLEEP=0` variant).
The row's print on each:

```text
P4: SQLite 3.53.1 sleeps in milliseconds: a 250 ms busy timeout answered busy after 251 ms
P4: SQLite 3.45.1 sleeps in milliseconds: a 250 ms busy timeout answered busy after 251 ms
```

B01's copy shows the other print: with no timeout set, `P4: SQLite 3.53.1 sleeps in whole
seconds: a 250 ms busy timeout answered busy after 0 ms`, and G failed on its premise,
`("wal" 0)`. CI's `main` lane, Ubuntu 24.04's 3.45.1, prints its own line in the log of the
slice's first run; Apple's waits for the Mac's hand run (the M3 plan, §8).

### The mutations

The suite: `test-contention`, baseline 10; its rows W, T, M, U, S, D and G above. Each plant ran
on Guix's 3.53.1 and at the floor, 3.45.1, against the final suite, T among its rows, and failed
the same rows on both.

| Plant | What it plants | Failed |
|---|---|---|
| B01 | no busy timeout: `busy-timeout`'s step dropped from the settings' plan | W and T (`at-once`), M (busy at once), D (the second's `BEGIN IMMEDIATE` busy at once); U, S and G by the premise alone, `("wal" 0)` |
| B02 | a retry in Scheme: a step that answers 5 is reset and stepped once more | W and T (3004 ms, `too-long`), G (502 ms) |
| B03 | `with-transaction`'s default made `deferred` | D: the default run met `busy-snapshot`, as the deferred one does; T: `BEGIN DEFERRED` took no lock, so the body ran and committed, at once |
| B04 | a thread's raise not made its answer: `start-thread`'s guard dropped, in the suite | W, T, D and G, each `unfinished`, and no hang |
| B05 | a retry loop in Scheme: a step that answers 5 is stepped again until 1500 ms have passed | U (`busy-snapshot` after 1500 ms, `waited`), G (1506 ms) |
| B06 | the extended code lost: the condition's extended code is the primary's | U, D (`busy` for `busy-snapshot`) |
| B07 | `execute!` rolls the transaction back when its statement answers busy | U: the plant's rollback ended the transaction, so U's own `rollback` raised `error`, `error` |
| B08 | every connection opened with `SQLITE_OPEN_SHAREDCACHE` | all seven: `locked`, `locked-sharedcache`, at once |
| B09 | `journal-mode` checked but never set | all seven by the premise, `"delete"`; U, S and D by behaviour too: the other's insert beside the reader's open transaction answered busy, and so did the deferred first's `COMMIT` |
| B10 | a busy handler in Scheme: no SQLite timeout, and a step that answers 5 sleeps 1500 ms and is stepped again once | all seven by the premise, `("wal" 0)`; M by its bound too, `not-before-the-timeout`, 1500 ms, 1000 after the commit; U `waited`; G about 1500 ms |
| B11 | B04 and B01 together | all seven: M, a thread that raises only when the library is wrong, `unfinished` too |
| B12 | `with-transaction`'s default made `exclusive` | T alone, by the SQL its condition names, `"BEGIN EXCLUSIVE"`; it waited 1502 ms as `immediate` does. Before T, **survived**; `test-transaction` fails it |
| J3 | the lead's: `with-transaction`'s own `BEGIN`, when it answers busy, issued again once | T alone: 3004 and 3005 ms, `too-long`. Before T it survived every suite |
| D1 | the busy entry's example states `(busy #(2))` | `test-docs`: the example's result row |
| D2 | `with-transaction`'s link names `#sqlite-busy-cases` | `test-docs`: the links row |

**15 plants, every one caught.** Each row failed at least two plants by its behaviour, not its
premise alone: W B01, B02, B04, B08 and B11; T B01 to B04, B08, B11, B12 and J3; M B01, B08, B10
and B11; U B05 to B10; S B08 and B09; D B01, B03, B04, B06, B08, B09 and B11; G B02, B04, B05,
B08, B10 and B11.

### The survivors, argued

- **J3, the lead's plant, survived every suite before T:** `test-contention` as first built, and
  `test-transaction`, `-engine`, `-interrupt` and `-nomem`, by the lead's run in
  `build/lead-mut/B`. No row had `with-transaction` wait out a timeout: W times `execute!`'s
  `BEGIN IMMEDIATE`, and D's waits end mid-wait, where the retry never runs. So `with-transaction`'s
  own `BEGIN` could retry in Scheme, against ADR-0019's decisions 8 and 11. T, added for it, has
  `with-transaction` wait the timeout out under the other's write lock, and fails J3 alone, 3004
  and 3005 ms; the copy's `transaction.sls` is the lead's byte for byte.
- **B12, `exclusive` for `immediate`, passes D by behaviour,** and T but for its SQL. In WAL,
  `BEGIN EXCLUSIVE` and `BEGIN IMMEDIATE` take the same write lock, and readers go on under
  either: D's default run under B12 answered as under `immediate`, and T waited 1502 ms, on both
  libraries. Only a rollback-journal file tells them apart, where an exclusive lock stops readers.
  T fails it by the `sqlite-error-sql` of its condition, `"BEGIN EXCLUSIVE"`; and
  `test-transaction`'s row "with no mode, with-transaction begins immediate" reads the SQL issued,
  and failed B12: `("BEGIN EXCLUSIVE" . ready)` where `("BEGIN IMMEDIATE" . ready)` was due, 47
  of 48 passing.
- **B04 survives M, U and S,** whose threads raise nothing when the library is right: U catches
  its `busy-snapshot` itself, since it reads on after it. The guard is the bound's partner only
  where something else is wrong. Tried against that schedule, B11: M's waiter, its `BEGIN
  IMMEDIATE` busy at once, died, and M failed by name, `unfinished`, the suite ending.
- **B05 survives W, T, M, S and D:** a loop whose deadline is the timeout stops after SQLite's
  own first wait has run it out, so W and T waited about 1502 ms, as without it; M's and D's
  immediate waits end in success, which the loop never retries; S's writes never answer busy;
  and D asserts no time for its deferred second's `busy-snapshot`, which came 1500 ms late. Its
  extra waits show where SQLite's don't: U's `busy-snapshot`, which SQLite answers at once, and
  G's 250 ms timeout, each then waited about 1500 ms.
- **B02 survives M, U, S and D:** a retry changes only a step that ends busy. M's wait and D's
  immediate one end in success, S's writes never answer busy, and `busy-snapshot`, in U and in D's
  deferred run, answers again at once when stepped again, as U asserts of its own retry.
- **B10 passes W and T by behaviour,** failing them by the premise alone: SQLite answers at once,
  the Scheme sleep waits 1500 ms, and one more step answers at once, so each wait is 1500 ms, as
  SQLite's own. M tells them apart: the other's commit at 500 ms ends SQLite's wait at its next
  retry, 29 ms later, and the sleep's 1000 ms later.
- **B01 fails U, S and G by the premise alone.** `busy-snapshot` and S's writes never wait, so the
  timeout changes nothing there: U's claim is that the timeout doesn't cover the upgrade, which the
  premise holds is there. G's 0 ms is what a whole-second build answers to a 250 ms timeout, so
  only the premise tells no timeout from that grain.
- **B09 fails W, T, M and G by the premise alone:** in rollback-journal mode, `BEGIN IMMEDIATE`
  under another's reserved lock waits the same.

### The trap the part found

- **A thread that dies on a raise runs the base exception handler, and
  `make-process-temp-directory`'s hook removes its directory then.** Reproduced with
  `build/m3s6b-probe/thread-removes-dir.sps`, git-ignored: a program makes the directory, forks a
  thread that raises `'boom` unguarded, waits for the thread's `dynamic-wind` after thunk, and
  reads `(file-directory? dir)`: `#t` before, `#f` after, the main thread going on and exiting 0.
  So one thread's death removed every later row's file, and each open answered `cantopen`. A
  suite whose threads may raise unguarded gives each row its own directory, as this one does, or
  guards every thread.

### For the records

- **G times a 250 ms wait,** where ADR-0019's decision 11 and the global constraints have "a row
  times a wait with a timeout of at least 1500 ms". It asserts no lower bound, only under twice its
  timeout, which holds on either grain, as the brief asked. Decision 11 wants a line for such a
  row: a probe's shorter timeout, asserting only under twice it.
- **P4 is read here on both libraries, milliseconds;** CI's `main` lane and Apple's remain (the
  M3 plan, §7 and §8).
- **The trap above** is `traps.md`'s, and perhaps an AGENTS.md line beside "A thread a suite forks
  dies on a raise": a dying thread also runs `make-process-temp-directory`'s hook. The hook could
  remove the directory only for a raise on the thread that made it; the testing library is
  outside part B's brief, so it is unchanged.
- **ADR-0017's consequence, a deferred write under contention fails at once,** holds once the
  transaction has read. Measured here, on both libraries, beside another's `BEGIN IMMEDIATE` and
  write, with a 1500 ms timeout: a deferred transaction's first statement, an insert, waited
  1502 ms and answered busy; after a `select`, the same insert answered busy in 0 ms; each left
  the transaction open (`build/m3s6b-probe/deferred-first-write.sps`, git-ignored). It fits B2's
  reading of the source, the handler called only from no transaction. The page now says "once it
  has read".

### The lead's checks of part B

Run by the lead on part B's hand-back, in the worktree and in a copy under its git-ignored
`build/lead-mut/B`.

- **`make test`:** ran 72, passed 72. After the follow-up, `test-contention` passed again, 10 of
  10.
- **Reproduced,** on both libraries where they load SQLite:
  - `deferred-first-write.sps`: the write with nothing read waited 1501 to 1502 ms, and after a
    read answered in 0 ms;
  - `thread-removes-dir.sps`: `(before #t)`, then `(after #f)`, exit 0.
- **The lead's plant, J3:** `with-transaction`'s own `BEGIN` retried once in Scheme on busy, in
  `begun!`.
  - **It survived:** `test-contention`, `test-transaction`, `-engine`, `-interrupt` and `-nomem`
    all passed under it. W times `execute!`'s `BEGIN IMMEDIATE`, and D's waits end mid-wait, so
    no row had `with-transaction` wait out a full timeout.
  - **Row T,** added in the follow-up, does: it failed alone under J3, waiting 3004 ms, and
    passes on the real code at 1502 ms.
