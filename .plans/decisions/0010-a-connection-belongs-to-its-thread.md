# ADR-0010: A connection belongs to the thread that opened it, and opens with SQLite's mutex

- **Status:** Accepted (the maintainer, 2026-11-14), proposed in M1 slice 0. Decisions 3 and 4
  were the maintainer's own, on 2026-11-13: brief D2, and the `THREADSAFE=0` refusal. Proposed first
  in the brief, §3c. Amended 2026-11-14: the mutex, measured
  ([amendment](#amendment-2026-11-14-the-mutex-measured-m1-slice-4)). Amended 2026-11-15, and
  accepted by the maintainer that day: the interrupt, designed (M3's plan,
  [amendment](#amendment-2026-11-15-the-interrupt-designed-m3s-plan)).
  Amended 2026-11-18 in M4's closing review, and accepted by the maintainer on 2026-11-19 ("Accept all"): the owner compared inside the section
  ([amendment](#amendment-2026-11-18-the-owner-compared-inside-the-section-m4s-closing-review)).
- **Date:** 2026-11-14
- **Scope:** chez-sqlite3 v1: every connection, and the library's load
- **Settles:** brief §3c and D2. Closes ADR-0002's open question.
- **Related:** chez-curl ADR-0012 and chez-libuv ADR-0019, whose ownership rule this follows ·
  [ADR-0002](0002-runtime-libsqlite3-discovery.md) (the load, amended) ·
  [ADR-0011](0011-collect-safe-and-no-scheme-memory.md) (blocking calls) ·
  [ADR-0013](0013-errors-are-condition-types.md) (`&sqlite-wrong-thread`) ·
  [the M1 plan](../2026-11-13-m1-plan.md), §2

## Context

- **Chez threads are operating-system threads** (ADR-0001: a threaded Chez is required).
- **SQLite's threading mode is set at compile time,** and read with `sqlite3_threadsafe()`:
  - 0 is single-thread: SQLite has no mutexes, so no two threads may use SQLite at once, even
    through separate connections;
  - 1 is serialized: each connection takes a mutex around every call;
  - 2 is multi-thread: a connection may be used by one thread at a time, and SQLite doesn't check.
- **An open flag overrides the mode per connection,** unless the build is single-thread:
  `SQLITE_OPEN_NOMUTEX` gives multi-thread, `SQLITE_OPEN_FULLMUTEX` serialized.
  `sqlite3_db_mutex` returns NULL for a connection that isn't serialized.
- **Serialized mode doesn't make a connection's state safe to share.** SQLite's documentation for
  `sqlite3_errmsg` warns that in serialized mode another thread's error can land between a failed
  call and the read of its message. A statement's step, column reads and reset are separate calls,
  so another thread can come between them.
- **Measured:**
  - Guix's 3.53.1 answers 1 ([research/guix-pin/](../research/guix-pin/)), and the CI runner's
    3.45.1 lists `THREADSAFE=1` among its compile options, read through the FFI
    ([research/ci-runner/](../research/ci-runner/));
  - on the maintainer's Mac, Homebrew's 3.54.1 answers 1 and Apple's 3.51.0 answers 2
    ([research/mac-d7/](../research/mac-d7/)).

## Decision

1. **A connection belongs to the thread that opened it.** It records that thread's
   `get-thread-id`. Every verb on it, `close-database!` among them, checks the calling thread, and
   on any other thread raises `&sqlite-wrong-thread` before anything reaches C. ADR-0012 gives the
   order of a verb's checks. The connection is left as it was. M3's `sqlite3_interrupt` is the one
   call another thread may make (brief §3c). SQLite says it is unsafe on a connection that is
   closed, or might close before it returns, so M3 designs it with `close-database!`.
2. **Statements belong to their connection's thread** (M2). The same check guards every
   statement verb.
3. **A connection opens with `SQLITE_OPEN_FULLMUTEX`,** unless `open-database` is given
   `'no-mutex`, which opens it with `SQLITE_OPEN_NOMUTEX` (brief D2, the maintainer). Decision 1
   holds either way, so the mutex is a second defence, against a gap in the thread check, at the
   cost of one uncontended lock per call.
4. **A library built single-thread is refused at load,** with the reason `not-threadsafe`: its
   `sqlite3_threadsafe()` answers 0. Such a build has no mutexes at all, so two connections on two
   threads would race inside SQLite, and decision 1 can't prevent that. The check runs after the
   floor and before any other entry point is bound (ADR-0002, amended).
5. **What the flags do is measured, not assumed.** Slice 4 reads `sqlite3_db_mutex` after each
   open: non-NULL with the default, NULL with `'no-mutex`. On the Mac it is read against Apple's
   `THREADSAFE=2` library too, where the default changes what SQLite does.

### Rejected

- **Sharing a connection between threads under serialized mode alone.** An error's message, a
  statement's step and its column reads would then be separate calls with another thread between
  them (the context).
- **`SQLITE_OPEN_NOMUTEX` by default,** the leaning brief D2 started from. The maintainer chose
  the mutex on by default, and configurable.
- **Accepting a `THREADSAFE=0` build and documenting it.** One thread per process isn't a rule a
  binding can check.

## Consequences

- **A program that uses several threads opens a connection in each.** A pool hands out
  connections per thread.
- **The counters stay process-wide,** behind their one mutex (ADR-0005).
- **A program that calls `sqlite3_config` itself,** from another library in the same process,
  can make SQLite single-thread after the load checked it. chez-sqlite3 never calls
  `sqlite3_config` (ADR-0001), and can't see another library's call.
- **A test of decision 1 forks a thread** and asserts the type that thread raised, as its answer,
  with every wait bounded (AGENTS.md).

## Amendment, 2026-11-14: the mutex, measured (M1 slice 4)

- **On Guix's 3.53.1, `THREADSAFE=1`,** `sqlite3_db_mutex` answered non-NULL with no mutex flag,
  non-NULL with `SQLITE_OPEN_FULLMUTEX`, and NULL with `SQLITE_OPEN_NOMUTEX`. So on that build no
  behaviour tells the default from no flag at all: the parser's rows hold that `FULLMUTEX` is
  passed, and `'no-mutex` alone is proven end to end. Apple's `THREADSAFE=2` library is where the
  default shows; the Mac's hand run reads it (decision 5).
- **Thread ids:** six threads forked in turn got ids 1 to 6, the main thread 0, on Chez 10.4.0.
  CSUG doesn't promise that ids are never reused. If a later Chez reused them, a new thread could
  pass a dead owner's check.
- **On the maintainer's Mac** (macOS 26.7.1, 2026-11-14), Apple's 3.51.0, `THREADSAFE=2`, passed
  `test-connection`'s mutex rows: `sqlite3_db_mutex` non-NULL with the default and NULL with
  `'no-mutex`. On that build a connection with no flag is multi-thread, so the default's
  `FULLMUTEX` is what serializes it. The plan's open question is settled.

## Amendment, 2026-11-15: the interrupt, designed (M3's plan)

Accepted by the maintainer on 2026-11-15 ("Accept all"), proposed in M3 slice 0
([the M3 plan](../2026-11-15-m3-plan.md), §4.4).

- **Decision 1's exception is `interrupt-database!`,** designed with `close-database!` by
  [ADR-0019](0019-interrupt-and-close.md). It checks only that its argument is a database. A
  mutex in the record keeps any interrupt from running once the close has begun, and on a closed
  connection it does nothing.
- **The context's "each connection takes a mutex around every call" isn't so for every call.**
  Under `FULLMUTEX`, another thread's `sqlite3_errmsg` waited 200 ms for a running step, and its
  `sqlite3_interrupt` returned before the step did (M3's research, concurrency I8). So the
  interrupt calls nothing else of the connection.

## Amendment, 2026-11-18: the owner compared inside the section (M4's closing review)

Accepted by the maintainer on 2026-11-19 ("Accept all"), proposed in M4's closing review ([its code log](../m4-closing-review-code-log.md)), from its review
of the code (Opus).

- **Chez resumes an engine's remainder on whichever thread calls it.** A remainder started on the
  owner's thread and taken between `call-with-open-handle`'s owner check and its section finished
  on another: swept at every fuel, with each remainder resumed on a new thread, the section that
  makes the C call ran on another thread in 3 of 12 trials, on threads 8, 9 and 10 (reviewer A's
  run; 3 of 13, on threads 9 to 11, in the M4 session's check; the probe is
  `research/m4-closing-review/code/probes/handle-other-thread.sps`). The check, made before the
  section, vouched for a thread the section no longer ran on. M1 made that check, and every verb
  since leans on it; M4's own calls were immune only because each wraps `call-with-open-handle` in
  a critical section of its own.
- **So `call-with-open-handle` reads the owner, the calling thread and the handle inside its
  section,** owner first, then open. A wrong thread is answered as data and raised after the
  section, `&sqlite-wrong-thread` from the procedure the caller called. The check before the
  section stays, so an argument's refusal still comes after a wrong thread's.
- **`close-database!` compares it too,** in a critical section around the interrupt latch's close,
  which finalizes, empties the cache and calls `sqlite3_close`: the first fix missed that verb,
  and the M4 session's check found a close resumed on another thread closing the connection there,
  at two fuels. Two more rows hold it.
- **Rows hold it:** seven, each sweeping every fuel and finishing each remainder on a forked
  thread, with every wait bounded: a bare call, open and closed, and `changes`,
  `in-transaction?`, `step!` and `prepare-statement`, and the refusal's handler at depth 1. On
  `main`'s code before the fix, six failed by three trials each; the seventh, the depth, was
  watched failing against a plant that raises inside the section.
