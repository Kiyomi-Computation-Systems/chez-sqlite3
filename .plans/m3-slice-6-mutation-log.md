# M3 slice 6 mutation log

Evidence that each rule slice 6's suites claim to guard fails through the property it names
([M3 plan](2026-11-15-m3-plan.md) §5, slice 6, §4.4, §4.8 and probe P5). Format of
[the M3 slice 5 log](m3-slice-5-mutation-log.md). The slice is built in three parts, each keeping
its own part of this log: A, `interrupt-database!` and the close's exclusion; B, contention; C,
the memory job in two shards.

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

## Part C: the memory job in two shards

An Opus agent built part C from the lead's brief, in the slice's worktree, on
`m3-slice-6-interrupt` over parts A's and B's records, `edecfff`. ADR-0005's consequence, and its
M3 amendment's rule: past 45 minutes the `memory` job is sharded. Slice 5's ran 40m31s on a fast
runner (run 43957085196), and slice 6 adds four suites. The maintainer chose "Shard in slice 6".
The precedent is chez-curl ADR-0014's amendment "the memory job is split in two". Its design is
followed, and its job names, so the two repositories' required checks read alike. None of its
code is copied: the refusals, their messages, case n and the check are written here.

### What part C adds

- **The Makefile:**
  - `MEMORY_SHARD`, empty by default, and the two shards written out, `MEMORY_SUITES_1` (35 suites)
    and `MEMORY_SUITES_2` (38);
  - `make test-memory MEMORY_SHARD=1` or `=2` runs that list; with no `MEMORY_SHARD`, every
    suite, as before. It refuses, by name and before any suite runs:
    - a `MEMORY_SHARD` but 1 or 2;
    - one from the environment, as it refuses `MEMORY_SUITES` there;
    - one beside a `MEMORY_SUITES` on its command line;
    - a shard's list set on its command line, or under `make -e` in the environment, with a shard or
      without;
    - a shard whose list is empty, and one holding two suites of one name;
  - `make check-memory-shards`, a prerequisite of `make test` after `check-ci`, runs
    `tests/check-memory-shards.sh` on the two lists and, after the lead's fix below, the tree's
    suites, every `tests/test-*.sps` (as built, `SUITES`);
  - the `help` lines of `test-memory` and `check-memory-shards`, and the comments of `test`,
    `check-ci`, `test-memory` and `check-memory-gate`.
- **`tests/check-memory-shards.sh`, new:** fails `make test` on a suite in neither list, one in
  both, one written twice in a list, and a path in a list that is no suite, each by name; and on an
  awk that fails, prints nothing, or prints no verdict.
- **`tests/test-check-memory-shards.sps`, new:** 28 rows, each the script's exit status, whole
  stdout and whole stderr, written by hand.
- **`.github/workflows/ci.yml`:** jobs `memory-1` and `memory-2` in place of `memory`. Each is the
  old job's setup, then `make check-memory-gate`, then `make test-memory MEMORY_SHARD=1` or
  `=2`, the number the run line's argument. No `if:`, `continue-on-error:`, `needs:` or
  `strategy:`, and no `env:` names a shard or a list.
- **`tests/check-ci.sh`:** six jobs. In `memory-1` and `memory-2`, check-chez, then
  `make check-memory-gate`, then the job's own shard, each a step's whole run line, with no `if:`.
  `test-memory` may stand only on a memory job's own shard's line, and `check-memory-gate` only as
  the run line of a memory job's step. Every word `MEMORY_*` is refused, as `VALGRIND_*` is, but
  `MEMORY_SHARD` on that one line.
- **`tests/test-check-ci.sps`:** 397 rows to 439. Each memory job's rows come from one procedure,
  `memory-rows`, and the old `memory` rows are aimed at `memory-1`.
- **`tests/check-memory-gate.sh`:** case n, eight verdicts (59 cases to 67), and `suite_argv`, case
  e's per-suite command, which n holds each shard's runs to.
- **`tests/check-test-fails.sh`:** the copy's Makefile names the copy's own suites in its two
  shards. Cases `shards-neither` and `shards-both` are new (13 to 15; the lead's
  `shards-narrowed` makes 16), and case `ci` plants its key in `memory-1`.

### The split

The split starts from the M2 session's
([research/m3-slice-6/memory-shard-input.md](research/m3-slice-6/memory-shard-input.md)). It
balances six CI runs' times, each suite's normalised to the fast class, with the threaded suites
dealt first. Taken whole, it partitioned the 72 suites at `edecfff`, parts A's and B's among them.
Part C's new suite went to shard 1, the lighter. Then one suite moved, after the local runs:

- **`test-open-interleave`, 40 s, from shard 1 to shard 2.** Shard 1 holds
  `test-transaction-interrupt`, whose time is the widest of any suite's. On CI, four runs of
  today's code took 20 s to 149 s, normalised median 82 s, and slice 5's run 138 s. Here it took
  225 s beside shard 2's run, then 434 s alone, 16 s short of `SLOW`, and 429 s in the final
  split's run. Its shard is left 68 s lighter at the median, so it stays the lighter at slice 5's
  138 s and at the 149 s seen. Without it, the final split's runs here took 854 s and 908 s.
- **Local times are no guide to CI's balance.** Against the input's times, shard 2's suites ran at
  0.84 here, but shard 1's, `test-transaction-interrupt` left out, at 0.93. The suites that start
  many children run slower here than on CI: `test-ci-sqlite` at 1.23, `test-check-ci` at 1.06,
  `test-check-floors` at 1.04, `test-library-loading-real` at 1.01. So the split follows CI's
  numbers.

The predictions use the input's normalised times. Two suites changed and are estimated:
`test-check-ci` at 106 s, its 96 s scaled from 397 rows to 439, and `test-check-memory-shards` at
8 s, 7 s here. Each job adds setup, 30 to 80 s, and `check-memory-gate`, about 305 s on the fast
class: run 43957085196's 293 s, and case n's 13 s or so. On the slow class, the slowest runner seen
(factor 1.27), the gate takes about 385 s. These are estimates: slice 5's suites rest on one CI run
each, and slice 6's on local runs.

| | Shard 1, `memory-1` | Shard 2, `memory-2` |
|---|---|---|
| suites | 35 | 38 |
| the suites, fast class | 1018 s; 1085 s with `test-transaction-interrupt` at 149 s | 1086 s |
| the job, fast class | 22.6 to 23.4 min; to 24.5 min at 149 s | 23.7 to 24.5 min |
| the job, slow class | 28.5 to 29.3 min; to 30.7 min at 149 s | 29.9 to 30.7 min |
| every suite at its worst seen | 29.0 to 29.9 min | 29.4 to 30.2 min |
| here, beside each other, first split | 18m43s, its suites 1120 s | 14m48s, 883 s |
| here, beside each other, final split | 21m27s, 1283 s, `test-transaction-interrupt` 429 s of it | 15m13s, 908 s |

One job would take about 41 minutes on the fast class and 52 on the slow, the input's projection.

### The gate in both jobs

Both jobs run `make check-memory-gate` before their shard, as chez-curl's two do.

- **The proof is per runner.** The gate proves nothing unless it can fail where the suites run.
  Each job is a runner of its own, with its own Valgrind from apt and its own Chez, restored from
  the cache or built there. A shard whose job skipped the gate would trust a proof made on another
  machine.
- **`check-ci` keeps one rule a job:** the job that runs `test-memory` runs `check-memory-gate`
  first, as it held of `memory`. With the gate in one job only, the other's shape would be a second
  rule, and deleting the gate's job would leave the other shard unproven.
- **What it costs:** one gate a job, about 290 s on the fast class and 370 s on the slow, and case
  n's 10 s more, locally. The jobs run side by side, so the run's wall time grows by one gate, not
  two. With the gate in one job only, moving suites to balance would save about half a gate,
  2.5 minutes, from the longer job.
- **Case b's unreproduced flake** now runs twice a run. A flake fails red; it never hides a
  defect. It stays out of scope, as the brief says.

### The red runs

| Check | Red run | Green run |
|---|---|---|
| `test-check-memory-shards`, before the script existed | 0 of 28 passed: `sh` found no `tests/check-memory-shards.sh`, exit 127 | 28 of 28 |
| `check-test-fails`, with the Makefile's lists but no `check-memory-shards` | `shards-neither` and `shards-both` failed, "make test exited 0"; the 11 old cases passed (`ci` waited on the workflow) | 15 of 15 |
| `check-memory-gate`'s n, against the Makefile with its lists, whose `test-memory` ignored `MEMORY_SHARD` | 7 of 7 verdicts failed: each shard, each refused value and each empty shard ran every suite | 7 of 7; `n names`, added after, fails only G14 (below) |
| `test-check-ci`, the new workflow and rows against the old `check-ci.sh` | 6 of 439 passed: the unedited file failed, `job "memory-1" is not one of main, memory, nothreads, floor, current` | 439 of 439 |

The check itself had a red run of its own before any plant: the input's split, taken whole,
partitioned the 72 suites at `edecfff`, parts A's and B's among them, and `check-memory-shards`
named the one suite it lacked, the new `test-check-memory-shards`, in neither list. It went to
shard 1, the lighter.

Green, at the end: `make test` ran 73, passed 73; `make check-test-fails` held in all 15 cases;
`make check-memory-gate` failed, as it must, in all 67 cases; and each shard passed under the gate
(above), each `ran 35, passed 35` and `ran 38, passed 38`, with no `SLOW`.

### How the mutants ran

Every mutant ran in a copy of the worktree of its own, `mut-NAME/` under the session's scratchpad,
made without `.git` and `build/`, through the copy's own `scripts/guix-env`, after `make deps`
there. A mutant is a list of edits, each checked to match its file's text exactly once before it is
written. Each kind runs one check: C, the script, `test-check-memory-shards`; W, the Makefile's
wiring, `make check-test-fails`; G, `test-memory`'s shards, `make check-memory-gate` cut to its
cases e, g and n, which hold every rule of the shards; K, `check-ci.sh`, `test-check-ci`. Rows are
read from the suites' `FAIL` lines and counts, and cases from the checks' `FAILED` lines, never by
eye. The driver (`mutants.py`, `trim-gate.py`, `mktree.sh`) and every log are in the session's
scratchpad, not the repository. Eight ran at once; none died or hung. The G mutants ran twice,
before and after the refusals were reworded in part C's own words, and the same cases failed.

### The mutations

Baselines: `test-check-memory-shards` 28 rows, `test-check-ci` 439, `check-test-fails` 15 cases,
and check-memory-gate's cases e, g and n, 16 verdicts. Each row names what failed.

| Mutation | Guards | Failed |
|---|---|---|
| C01 | a suite in neither list is told (the rule dropped) | 8 rows |
| C02 | a suite in both is told | 4 rows |
| C03 | a suite twice in `MEMORY_SUITES_1` is told | 3 rows |
| C04 | a suite twice in `MEMORY_SUITES_2` is told | 2 rows |
| C05 | a path that is no suite is told (no stray told) | 8 rows |
| C06 | a stray is told once (told at each place) | 1 row, "one named twice is told once" |
| C07 | `MEMORY_SUITES_2`'s strays are told (list 1's only) | 4 rows |
| C08 | the lists reach awk as they are (through `awk -v`, which reads `\b` as an escape) | 1 row, the backslash's |
| C09 | awk's exit status is read | 1 row, the failing awk's |
| C10 | an awk that prints nothing fails | 1 row, the silent awk's |
| C11 | a verdict must hold a count | 1 row, the garbled awk's |
| C12 | paths are compared whole (by their file names instead) | 18 rows |
| C13 | the second list is the third argument (the second's) | 19 rows |
| C14 | exactly three arguments (three or more) | 1 row, four arguments |
| C15 | neither means in no list (`a == 0 \|\| b == 0`) | 18 rows |
| C16 | the pass line counts the suites (the lists' entries) | **survived**, equivalent |
| C17 | the suites' problems before the strays (strays first) | 3 rows |
| C18 | any white space splits a list (single spaces only) | 1 row, the white space's |
| C19 | the FAILED line counts the problems (always 1) | 6 rows |
| W01 | `make test` runs `check-memory-shards` (the prerequisite dropped) | `shards-neither`, `shards-both` |
| W02 | the recipe hands both lists (list 1 twice) | `fails`, `no-tests`, `hangs`, `leaks`, `shards-neither` |
| W03 | the recipe hands `SUITES` (`MEMORY_SUITES` instead) | **survived**, equivalent in `make test` |
| W04 | the recipe hands `SUITES` (the lists' union instead) | `shards-neither`, `shards-both` |
| W05 | the check's status fails `make test` (`@-sh`) | `shards-neither`, `shards-both` |
| G01 | shard 1 runs `MEMORY_SUITES_1` (list 2 instead) | n split, n empty (1) |
| G02 | each shard runs its own list (the two swapped) | n split, n empty (1 and 2), n names |
| G03 | shard 2 runs `MEMORY_SUITES_2` (every suite instead) | n split, n empty (2), n names |
| G04 | a `MEMORY_SHARD` but 1 or 2 is refused (the refusal dropped) | n refused |
| G05 | only 1 and 2 (any value starting with a digit) | n refused |
| G06 | a quote in `MEMORY_SHARD` reaches the refusal (not escaped) | n refused |
| G07 | a `MEMORY_SHARD` from the environment is refused | n environment |
| G08 | a shard beside a `MEMORY_SUITES` is refused | n beside |
| G09 | a shard's list from outside is refused (every origin let through) | n lists |
| G10 | from the environment too (only the command line's refused) | n lists |
| G11 | without a shard too (only with one) | n lists |
| G12 | an empty list is refused | g none, n empty (1 and 2) |
| G13 | the refusal names the empty list (always `MEMORY_SUITES`) | n empty (1 and 2) |
| G14 | two suites of one name are refused in the list that runs (`MEMORY_SUITES` read instead) | n names |
| G15 | the run reads the shard's list (`MEMORY_SUITES` instead) | n split |
| G16 | `MEMORY_SHARD ?=`, so the environment's reaches the refusal (`:=`) | n environment |
| G17 | `MEMORY_SUITES_2 :=` (`?=`) | n empty (2), n names: by structure, argued below |
| K01 | job `memory-2` is a job check-ci knows | 432 rows, the unedited file's among them |
| K02 | every job missing is told (the loop stops at five) | 1 row, "the current job deleted" |
| K03 | a memory job runs `make check-memory-gate` | 6 rows: each job's gate deleted, its order, its `if` |
| K04 | a memory job runs its shard | 16 rows |
| K05 | memory-2 runs shard 2 (shard 1's line) | 431 rows |
| K06 | `MEMORY_SHARD` only on a shard's own line (on any line) | 14 rows |
| K07 | every `MEMORY_*` word is refused (the pattern dropped) | 19 rows, `MEMORY_LOGS`'s among them |
| K08 | the shard line's job is held (any memory job, either number) | 4 rows: each job running the other's shard, the wrong job, no jobs key |
| K09 | `check-memory-gate` only in a memory job (in any job) | 2 rows: memory-3, no jobs key |
| K10 | a memory job's step carries no `if:` | 4 rows, each step's `if: always()` |
| K11 | memory-2's Chez cache key is held (its prefix unset) | 431 rows |
| K12 | `test-memory` stands only with its shard (plain `make test-memory`) | 432 rows |

### The survivors, argued

**51 of 53 mutants were caught; two survived, both equivalent.**

- **C16, the pass line counting the lists' entries instead of the suites,** is equivalent. The line
  prints only when there is no problem. Then every suite stands once in one list, and no other path
  stands in either, so the lists' entries number exactly the suites.
- **W03, the recipe handing `MEMORY_SUITES` as the suites,** argued here as built, no longer
  applies: the lead's fix below hands the tree's suites, neither `SUITES` nor `MEMORY_SUITES`. As
  built, it was equivalent in every `make test`
  that names no `MEMORY_SUITES`. `MEMORY_SUITES ?= $(SUITES)` gives the two the same value, and no
  run of `check-test-fails` names one. CI names none: `check-ci` refuses the word in the workflow. A
  `make test MEMORY_SUITES=…` run locally would check the shards against that list instead. That
  run is the caller's own choice, and `test-memory` never sees it.
- **G17, `MEMORY_SUITES_2 ?=`, was caught by structure, not by behaviour.** Case n's `set_list`
  found no `MEMORY_SUITES_2 :=` definition in the copy's Makefile to rewrite, so `n empty` and
  `n names` failed. Its behaviour is refused anyway: with `?=`, a list exported without `make -e`
  would stand with origin `environment`, and the refusal lets only the origin `file` through, so it
  refuses that list, as "set in the environment".

**What no check here holds:**

- **An empty shard** fails CI's job, not `make test`. `test-memory` refuses it by name, `n empty`,
  but `check-memory-shards` holds only the partition: a check that each list holds a suite could
  never pass with one suite, or with `check-test-fails`' copies, which hold one or two.
- **The balance.** Nothing fails when one shard grows far past the other. The `SLOW` check holds
  each suite, and the job's own 60 minutes hold each shard.
- **Branch protection.** A change that deletes both memory jobs fails `make test`, through
  `check-ci`, but only a required check stops a merge whose workflow skips `main`. That lever is
  the maintainer's.

### The trap the part found

- **A comma inside a make function's arguments splits them, and the recipe's shell then fails.**
  As first written, the refusal of a shard's list from outside read "to run other suites, give
  MEMORY_SUITES and no MEMORY_SHARD" inside `$(foreach … $(if …,echo "…",))`. Make read the comma
  as the end of `$(if)`'s then-part, so the recipe's shell got an `echo` with its quote left open.
  `test-memory` then failed for every run, a shard or none, with `syntax error near unexpected
  token '('`: cases e, g none, g all and n failed with it, before any suite ran.
- **Reproduced** with GNU Make 4.3 on the host: a makefile of `X := 1` and a recipe
  `$(if $(X),echo "one, two" >&2; exit 1;) echo after` fails with `/bin/sh: 1: Syntax error:
  Unterminated quoted string`; with "one and two" the recipe prints it and fails on its own
  `exit 1`.
- **The refusal now reads the two lists' origins in the shell,** `for v in 'MEMORY_SUITES_1
  $(origin MEMORY_SUITES_1)' …`, where a comma is text. A message written inside a make function's
  arguments holds no comma, or takes one through a variable, `$(comma)`.

### For the records

- **`test-transaction-interrupt` nears `SLOW` under the gate here:** 434 s alone and 429 s in its
  shard, of the 450 s threshold, and 225 s once. On CI it has taken 20 s to 149 s. Its watchdog is
  slice 4's, a plain thread every 5 ms, whose latency under Valgrind is the scheduler's (its
  header: one call 57 s). Part A's watchdog, which takes SQLite's memory mutex each round, bounds
  that. Part C only places suites, so the suite is unchanged. Reproduce with
  `scripts/guix-env make test-memory MEMORY_SUITES=tests/test-transaction-interrupt.sps`.
- **ADR-0005** needs its amendment: the memory job split in two, its shape in `check-ci`, the
  refusals, `check-memory-shards` in `make test`, the gate in both jobs and why, and the split's
  predicted and measured times. Its decision 6 and its scope name "CI's memory job" and should name
  the two jobs.
- **Branch protection:** the required check `memory (the Valgrind gate)` gives way to
  `memory-1 (the Valgrind gate, shard 1 of 2)` and `memory-2 (the Valgrind gate, shard 2 of 2)`.
  The ledger's line naming the five required jobs needs the same change.
- **The trap above** is `traps.md`'s, and perhaps an AGENTS.md line beside the Makefile's `help`
  rule.
- **AGENTS.md's line on `SLOW`** could add: a new suite goes in one of the Makefile's two shards,
  the lighter by its CI time, and `make test` fails until it is in one.
- **The shards' times** are estimates until slice 6's own CI run, and slice 5's suites rest on one
  CI run each. Read every suite's `time:` line in both jobs' logs then, and rebalance if one job
  runs more than a few minutes past the other.

### The lead's checks of part C

Run by the lead on part C's hand-back, in the worktree and in fresh copies of it under the
session's scratch directory, one plant a copy.

- **Rerun:** `make test` ran 73, passed 73; `make check-memory-gate` passed all 67 cases; and
  `make check-test-fails` passed all 15, then all 16 with the case below.
- **The lead's plants,** each caught:

  | Plant | What it changes | Caught by |
  |---|---|---|
  | P1 | `memory-2`'s shard step given `continue-on-error: true` | `check-ci`, the step key |
  | P2 | `memory-2` deleted, and `memory-1` running plain `make test-memory` | `check-ci`: `memory-2` missing, `memory-1` running no shard 1, and `test-memory` off its line |
  | P4 | a job-level `env:` in `memory-2`, `MEMORY_SHARD: '1'` | `check-ci`: the job key, the word, the line |
  | P5 | `memory-2`'s shard run under the nothreads Chez | `check-ci`, its `CHEZ` |
  | P6 | `test-utf8` dropped from shard 2 | `check-memory-shards`: in neither |
  | P7 | `test-utf8` written in shard 1 as well | `check-memory-shards`: in both |
  | P8 | `test-utf8` misspelt `test-utf-8` in shard 2 | `check-memory-shards`: in neither, and the stray |
  | P9 | with no `MEMORY_SHARD`, `test-memory` running shard 1's list | `check-memory-gate`, from case b on: every case that names its suites ran shard 1's instead, and failed. Stopped there |
  | P15 | a new suite, in no shard | `check-memory-shards`: in neither, by name |

- **A regression, found and fixed.** As built, the recipe handed `check-memory-shards` the run's
  `SUITES`. So `make test SUITES=<suite>`, the narrowed run the M1 closing review's log made,
  failed with 72 problems, every other suite in the lists read as a stray. And a narrowed run
  passed with a suite in neither shard, since the check saw only the one suite. The recipe now
  hands the tree's suites, `$(sort $(wildcard tests/test-*.sps))`.
  - **Case `shards-narrowed`,** new in `check-test-fails`, runs `make test SUITES=` the
    after-suite with a suite left out of both shards, and requires the check to name it.
  - **It failed before the fix:** `make test` exited 0, having run the after-suite alone. It
    passes after.
  - After the fix, `make test SUITES=tests/test-utf8.sps` runs that suite alone and passes.
- **The comma trap reproduced** on the host's GNU Make 4.3, as the part reports.
