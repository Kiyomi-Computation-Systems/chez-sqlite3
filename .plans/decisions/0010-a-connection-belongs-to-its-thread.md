# ADR-0010: A connection belongs to the thread that opened it, and opens with SQLite's mutex

- **Status:** Accepted (the maintainer, 2026-11-14), proposed in M1 slice 0. Decisions 3 and 4
  were the maintainer's own, on 2026-11-13: brief D2, and the `THREADSAFE=0` refusal. Proposed first
  in the brief, §3c. Amended 2026-11-14: the mutex, measured
  ([amendment](#amendment-2026-11-14-the-mutex-measured-m1-slice-4)).
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
