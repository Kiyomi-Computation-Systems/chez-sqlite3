# ADR-0019: Any thread may interrupt a connection, the close excludes it first, and a busy wait ends only at its timeout

- **Status:** Accepted (the maintainer, 2026-11-15), proposed in M3 slice 0. The maintainer's own choices, the same day
  ([the M3 plan](../2026-11-15-m3-plan.md), §3): decision 1's name, "Short names" (Q1);
  decision 5's interrupt between statements, "SQLite's way, documented" (Q12); and decision 8's
  busy timeout, with no default, "None, SQLite's 0" (Q10). Revised the same day after the plan's
  adversarial review: decision 2's flag on both paths a failed close takes, decision 8's held
  read, and a test of the exclusion that doesn't need the gate. Amended 2026-11-16 in M3 slice 5,
  and accepted by the maintainer that day: decision 11's upper bound, the maintainer's "Keep,
  amend" ([amendment](#amendment-2026-11-16-a-waits-upper-bound-m3-slice-5)). Amended
  2026-11-16 in M3 slice 6, proposed: the interrupt and contention as built, and probes P4 and P5
  ([amendment](#amendment-2026-11-16-the-interrupt-and-contention-as-built-m3-slice-6)).
- **Date:** 2026-11-15
- **Scope:** chez-sqlite3 v1: `interrupt-database!`, the close's part in it, and the busy timeout
- **Settles:** ADR-0010, decision 1: "M3's `sqlite3_interrupt` … M3 designs it with
  `close-database!`"; brief §4's busy timeout and `sqlite3_interrupt`
- **Related:** [ADR-0005](0005-memory-gate.md) (the counters' mutex) ·
  [ADR-0010](0010-a-connection-belongs-to-its-thread.md) (threads) ·
  [ADR-0011](0011-collect-safe-and-no-scheme-memory.md) (bindings) ·
  [ADR-0012](0012-explicit-close-and-the-handle.md) (the close) ·
  [ADR-0013](0013-errors-are-condition-types.md) (`&sqlite-interrupt`) ·
  [ADR-0018](0018-the-settings-list.md) (the busy timeout as a setting) ·
  [research/m3-plan/concurrency/](../research/m3-plan/concurrency/README.md) ·
  [the M3 plan](../2026-11-15-m3-plan.md), §4.4 and §4.5

## Context

Measured on Guix's 3.53.1 and at the floor, 3.45.1, alike but for timings within noise (M3's
research, concurrency; "single" names its other half):

- **What an interrupt from another thread reaches:**
  - a long step answers 9 within 0.14 ms, and a long prepare within about 6 ms (I1, I7). Through
    Chez, a `__collect_safe` step inside a critical section answered 9 promptly, and the
    interrupting thread collected while it ran (C1);
  - **not a wait in the busy handler:** a `BEGIN IMMEDIATE`, an autocommit insert, a `COMMIT`, a
    fresh connection's prepare and `sqlite3_exec` each waited out a 600 ms timeout, interrupted at
    100 ms, and answered BUSY (I6, C2, S6, trap 1);
  - **a statement held at a row counts as running:** the interrupt then sticks, and every new
    prepare and step answers 9 until that statement is reset (I3, I4b, trap 2);
  - **one made while no statement runs is lost** at the next statement's start, one prepared
    before it and not yet stepped included (I2; both headers);
  - an interrupted write ends the transaction and its savepoints; an interrupted SELECT doesn't
    (I5, trap 3).
- **`sqlite3_is_interrupted` reads 1** after an interrupt that reached nothing, and after the
  step it stopped has returned, until the next statement starts (I1, I2).
- **The call:** `sqlite3_interrupt` took 0.31 to 12.22 µs, under `FULLMUTEX` and `NOMUTEX`, and
  didn't wait for the connection's mutex, where another thread's `sqlite3_errmsg` waited 200 ms for
  a running step (I1, I8).
- **SQLite calls it unsafe on a connection that is closed, or might close before it returns**
  (both headers; A4). The research's probe kept it safe only by making the owner wait for the
  interrupter before closing (A3).
- **`sqlite3_close`** wrote a checkpoint, about 5 ms for 4 MB of WAL, and never called the busy
  handler (S5).
- **Engines and timers can't bound time inside SQLite:** a timer's ticks don't elapse during a
  foreign call (C3).
- **The busy timeout:** `sqlite3_busy_timeout` and `PRAGMA busy_timeout` are one setting, and only
  the PRAGMA can be read; a new connection's is 0 (B1). A build without `nanosleep` sleeps whole
  seconds: under 1000 ms it answers BUSY at once, and 1500 waits 1000; no compile option shows it
  (B3's variant). Both measured libraries sleep in milliseconds (B3).
- **BUSY's codes:** 517, `busy-snapshot`, for a deferred transaction's upgrade after another's
  commit (B5); 6, `locked`, for the connection's own conflict, with no wait (B9). Four cases that
  need different remedies all answer 5, extended 5: deadlock avoidance at once (B2), a timeout
  waited out (B3), a `COMMIT` under another's read (B7), and a `COMMIT` under the connection's own
  unfinished write (B11).

## Decision

1. **`interrupt-database!` may be called from any thread:**

   ```scheme
   ;; interrupt-database! : Database -> Void
   ```

   It checks that its argument is a database, else an assertion violation, and makes no owner
   check: it is ADR-0010's one exception.
2. **The record gains a mutex and an `interruptible` flag.**
   - **The interrupt,** in one critical section: takes the mutex; if the flag is set, calls
     `sqlite3_interrupt` with the handle; releases the mutex.
   - **The close,** in its critical section, before it finalizes anything: takes the mutex, clears
     the flag, releases it. Then it finalizes and closes as ADR-0012 and ADR-0014 have it. **A
     close that leaves the connection open sets the flag again the same way,** on both such paths:
     a statement found untracked, refused before `sqlite3_close` runs (`connection.sls:417`), and
     `sqlite3_close` failing (`connection.sls:428`).
   - **The open** sets the flag once the record exists, in its section.

   The interrupt calls `sqlite3_interrupt` while it holds the mutex, and the close clears the
   flag while it holds the same mutex, so an interrupt in flight when the close begins finishes
   first. So no interrupt is in flight when `sqlite3_close` starts, and none starts after.
3. **The mutex is held only inside a critical section, for constant time, never across a call that
   can block,** as the counters' mutex is (ADR-0005, decision 4). A thread in a section doesn't
   stop for another's collection until it leaves: ADR-0012's closing-review amendment measured a
   collection waiting behind one. So a holder releases the mutex before it can stop, and neither
   side waits on a collection the other blocks. `sqlite3_close` runs with it released. **The mutex
   is the exclusion, never the section:** a critical section keeps out only its own thread's
   engines, timers and interrupts. M2's closing review measured another thread run 423,841,665
   loop iterations while one sat inside a section, and M2's libraries hold no mutex of their own.
   The section around the mutex only keeps the holder from being preempted while it holds it.
   **Every other section M3 adds guards state only the owner thread touches** (ADR-0010, decision
   1): the cache's table, the tracked statements, `with-transaction`'s refusal pass and flags,
   `query-fold`'s flag. There a section is enough, since the only rivals are this thread's own
   engines and interrupts. This verb is the one cross-thread call, and it touches only the flag and
   the handle, under the mutex.
4. **On a closed connection, or one closing, the interrupt does nothing** and raises nothing. A
   watchdog races its target's close by nature; a raise there would depend on timing.
5. **It calls `sqlite3_interrupt` alone,** bound plain, and reads nothing else of the connection:
   any call that takes the connection's mutex would wait for the step it means to stop. What it
   reaches is SQLite's: a running step or prepare; not a busy wait; and one that lands between
   statements is lost, so a watchdog repeats it until the work stops (Q12). `docs/reference.md`
   says each.
6. **An interrupt raises `&sqlite-interrupt`,** classed by its primary code `interrupt`
   (ADR-0013, amended), from the verb whose statement it stopped.
7. **`sqlite3_is_interrupted` is neither bound nor exported.** Its 1 doesn't mean a statement was
   stopped.
8. **The busy timeout is a setting, `busy-timeout`,** set and read back by PRAGMA (ADR-0018);
   `sqlite3_busy_timeout` isn't bound. **No connection gets one unasked:** without the setting it
   keeps SQLite's 0 (Q10). **No busy handler and no retry in Scheme** (brief §4): a busy wait ends
   at its timeout, interrupt or not. **The timeout covers no write while the connection's own
   statement holds a read:** its `BEGIN IMMEDIATE` and an autocommit INSERT answered BUSY at once
   there, where without the held read they waited out a 1500 ms timeout (M3 slice 0's research,
   P12).
9. **No new busy subtypes.** `&sqlite-busy` keeps `busy` and `locked` (ADR-0013, decision 8); the
   extended code tells `busy-snapshot` and `locked` from the rest, and nothing tells the four 5s
   apart. `docs/reference.md` gives each case's remedy.
10. **No deadline and no watchdog in v1.** A caller who wants one runs a thread that calls
    `interrupt-database!`, and repeats it until the work stops.
11. **A test times a wait with a timeout of at least 1500 ms, and asserts at least 1000 ms,** so it
    holds on either grain. No row asserts an upper bound beyond its own bounded wait for an answer.

### Rejected

- **No exclusion, leaving the race to the caller:** an interrupt landing during `sqlite3_close`,
  or after, is the case both headers call unsafe, and no caller can see the close from another
  thread.
- **Holding the mutex across `sqlite3_close`,** as M2's closing review suggests: a mutex taken
  inside the close's section around `sqlite3_close` and the clearing of the handle, which the
  interrupt takes too. It keeps an interrupt off a freed connection as decision 2 does. But
  `sqlite3_close` can write a checkpoint, about 5 ms for 4 MB of WAL and more for a larger one
  (concurrency S5), and every interrupting thread, a watchdog among them, would wait on that I/O;
  and a thread blocked on a mutex while a collection waits for it is a hazard no measurement here
  clears. Decision 2's cost: an interrupt made during the close's finalizes is dropped, where the
  suggestion would deliver it. None of the close's work is a step or a prepare, the calls an
  interrupt was measured to stop (I1, I7).
- **Raising `&sqlite-closed` from an interrupt on a closed connection:** the race is inherent.
- **An owner check on the interrupt:** another thread is its whole use.
- **Exporting `sqlite3_is_interrupted`.**
- **A busy handler, or a Scheme retry loop of short timeouts:** callbacks are out of v1, and a loop
  would make every blocking call's time the library's, not SQLite's.
- **Subtypes for `busy-snapshot` and `locked`:** the extended code is already the answer.
- **An engine or a timer as a deadline:** neither counts time spent in SQLite.
- **A flag that keeps an interrupt for the next statement,** declined in Q12: an interrupt landing
  just after a statement finished would stop the next one, which wasn't its target.

## Consequences

- **A watchdog can't stop a busy wait;** the timeout bounds it. `docs/reference.md` says to keep
  timeouts as short as the program can wait.
- **A statement held at a row keeps an interrupt in force,** failing every new statement on its
  connection until reset, `ROLLBACK` and `COMMIT` among them, so its transaction can't end (M3
  slice 0's research, P7; ADR-0017's consequences). A statement of the caller's can hold one, and
  so does `query-fold`'s own while its procedure runs (ADR-0016, decision 6). The other
  conveniences hold none once they return or raise. `with-transaction` refuses to begin beside a
  held row (ADR-0017, decision 1; the plan's Q14).
- **The close takes the mutex once more,** for constant time.
- **The exclusion has a test that doesn't need the gate.** It is a procedure of its own, which
  takes the interrupt's foreign call as an argument, as M2 slice 1's NULL-pointer readers take
  theirs. M3 slice 1 tests it with stand-ins across two threads, every wait bounded: a stand-in
  call that records when it ran, against a close's clearing of the flag. A mutant without the
  mutex, or one that clears the flag after `sqlite3_close`, lets the stand-in run once the close
  has begun, and fails the row.
- **The race is held by a row under the gate too:** interrupts from one thread against opens and
  closes on another, every wait bounded. Whether Valgrind sees the planted copy without the
  exclusion, as an invalid write, is the M3 plan's probe P5. If it can't, the stand-in row is the
  exclusion's failing test, and the gate's row says it saw nothing.

## Amendment, 2026-11-16: a wait's upper bound (M3 slice 5)

Accepted by the maintainer on 2026-11-16 ("Keep, amend"), proposed in M3 slice 5, from its
adversarial review ([ADR-0018](0018-the-settings-list.md), amended in M3 slice 5; the slice's
[mutation log](../m3-slice-5-mutation-log.md), part C).

- **Decision 11, amended: a row that times a wait asserts it under twice its timeout,** as well as
  at least 1000 ms. The review planted a retry in Scheme, each setting tried again once on busy: it
  waited 3003 ms against 1502, and every row passed, asserting only the lower bound. So "no retry
  in Scheme" (decision 7) had no row. Under 3000 ms for a 1500 ms timeout, the mutant fails.
- **Measured,** `test-open-locks`: each wait ran 1502 ms plain, and 1509 to 1526 ms under Valgrind
  at the floor, about 1.5 s under the bound. A build without `nanosleep`, sleeping whole seconds,
  waits 1000 ms for 1500 (concurrency B3's variant), under it too.
- **A wait the other connection ends mid-wait is still asserted only as before its timeout's end**
  (slice-0 P3).

## Amendment, 2026-11-16: the interrupt and contention, as built (M3 slice 6)

Proposed in M3 slice 6, from its builders' reports and the lead's checks (the slice's
[mutation log](../m3-slice-6-mutation-log.md), parts A and B;
[research/m3-slice-6/](../research/m3-slice-6/README.md)).

- **`interrupt-database!` lives in `(chez-sqlite3 private connection)`,** beside the record and
  its handle. The handle's one accessor, `call-with-open-handle`, makes the owner check this verb
  must not (ADR-0012, decision 2), so anywhere else it would need a second accessor.
  - The handle is read inside the latch's call, holding its mutex, only while the flag is set.
    The close clears the flag before it can clear the handle, so a set flag means a live handle.
  - The verb answers nothing, and checks only that its argument is a database.
- **Decision 2, as built:**
  - the record holds slice 1's latch, made not interruptible;
  - `connection-outcome`'s section sets the flag once the record exists;
  - `close-connection` runs its work through `interrupt-latch-close!`, which clears the flag
    before the first finalize;
  - the flag is set again only after the two closes that leave the connection open: a statement
    found untracked, and `sqlite3_close` refusing, busy beside an unfinished backup.
- **A close that does close leaves the flag clear,** including one that then raises a finalize's
  failure (M2's R1), and a second close. A mutant setting it again after either survived every row
  until a row of each was added: the verb then handed `#f` to `sqlite3_interrupt`, which Chez
  refuses, so it raised on a closed connection, against decision 4.
- **Probe P5:** Valgrind does report an interrupt on a freed connection. A direct probe gave
  "Invalid write of size 4 at sqlite3_interrupt", 408 bytes inside a freed block of 792 at the
  floor and of 840 on 3.53.1. But the gate's race row can't see a missing exclusion:
  - the plant, the flag's read made true, hands Chez `#f` once the close has cleared the handle,
    and Chez refuses it before C;
  - a plant that read the handle before the latch passed the race's 200 rounds with no error.

  So, as the consequences foresaw, the gate's row sees nothing. The exclusion's failing tests are
  `test-interrupt-database`'s rows inside the close, on one thread with no timing, and slice 1's
  stand-in row, the one that fails a latch without its mutex.
- **The race row runs 20 rounds.** Its plant fails at 1, but under the gate 1, 20 and 200 rounds
  each cost 10 to 11 s, so 20 buys coverage at no cost.
- **The suites' watchdog under the gate:** Valgrind runs one thread at a time, and a thread running
  C keeps it.
  - A watchdog against a prepare of 4 MB of comments stopped none of 15 prepares under Valgrind,
    in the slice's runs, sending 0 interrupts in 14 of them. Plain, it stopped 8 of 9.
  - So each round the suites' watchdog takes SQLite's memory mutex, `SQLITE_MUTEX_STATIC_MEM`,
    sleeps 1 ms holding it, calls the verb, then lets the mutex go. The owner's call blocks at
    its next allocation inside SQLite, and the interrupt lands there. Under Valgrind it stopped 3
    of 3 prepares in its first round.
  - It needs SQLite's memory statistics on, as both measured libraries keep them. Apple's 3.51.0
    keeps none, so the maintainer's Mac run reads that row.
  - Every call the owner makes while the watchdog may hold the mutex is `__collect_safe` or takes
    none of SQLite's memory. Otherwise the owner could block in a plain call while another
    thread's collection waits for it.
  - The hold isn't a critical section: there, the owner's collections waited for the section's
    end, which released the mutex, and the long prepare ran unstopped in all 4 gated runs.
- **The long prepare is 3 MB of `select 1 in (1, 1, …)`,** a million and one items, not
  comments. Each item makes an expression, and so an allocation, where comments make none. The
  long step calls `randomblob` on each row, for the same reason.
- **Measured,** alike on both libraries:
  - the busy wait the interrupt doesn't stop ran 1502 ms plain, and 1509 to 1514 ms under the
    gate;
  - the three suites, `test-interrupt-database`, `-reach` and `-close`, took 10, 15 and 10 s under
    the gate locally.
- **The contention suite,** `test-contention`: two connections to one WAL file, each on its own
  thread, under a 1500 ms busy timeout. Every wait for a thread is bounded, and whatever a thread
  raises is its answer. Measured alike on both libraries:

  | Row | What it holds | Plain | Under the gate |
  |---|---|---|---|
  | `BEGIN IMMEDIATE` under the other's write lock | waits, then `busy`, left in autocommit | 1502–1503 ms | 1512–1513 ms |
  | the other commits 500 ms in | succeeds after the commit, before the timeout's end | 529–530 ms | 532–535 ms |
  | from that commit to the return (slice-0 P3) | | 29–30 ms | 28–31 ms |
  | a deferred read, then the other's commit | the write: `busy-snapshot` at once, the transaction open | 0 ms | 1 ms |
  | a reader's snapshot while the other writes | the writer's steps, each at once | 0 ms | 0–1 ms |
  | `with-transaction`'s default, `immediate` | the second waits for the first, then both commit; under `'deferred`, `busy-snapshot` | 529–530 ms | 532–533 ms |

- **Decision 11's exception, for the grain itself:** one row, probe P4's, times a 250 ms timeout.
  It asserts only that `busy` comes within 500 ms, which holds on either grain: a millisecond
  build answers after 250 ms, and a whole-second build at once. It prints which. Every other
  timed row keeps decision 11's 1500 ms floor and both bounds.
- **Probe P4:** both measured libraries sleep in milliseconds. The grain row waited 251 ms plain
  and 252 to 253 ms under the gate. CI's `main` lane, Ubuntu's 3.45.1, prints its own grain in
  its log, and the maintainer's Mac run reads Apple's.
- **The docs give each busy case's remedy** in `sqlite-busy?`'s entry (decision 9): `busy-snapshot`,
  `locked`, and the four plain `busy`s, with which leave the transaction open.
