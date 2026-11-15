# ADR-0019: Any thread may interrupt a connection, the close excludes it first, and a busy wait ends only at its timeout

- **Status:** Accepted (the maintainer, 2026-11-15), proposed in M3 slice 0. The maintainer's own choices, the same day
  ([the M3 plan](../2026-11-15-m3-plan.md), §3): decision 1's name, "Short names" (Q1);
  decision 5's interrupt between statements, "SQLite's way, documented" (Q12); and decision 8's
  busy timeout, with no default, "None, SQLite's 0" (Q10). Revised the same day after the plan's
  adversarial review: decision 2's flag on both paths a failed close takes, decision 8's held
  read, and a test of the exclusion that doesn't need the gate.
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
