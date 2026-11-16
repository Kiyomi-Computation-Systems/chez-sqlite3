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
