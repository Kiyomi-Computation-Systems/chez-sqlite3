# ADR-0011: Calls that can block are `__collect_safe`, and nothing passed to libsqlite3 lives in Scheme memory

- **Status:** Accepted (the maintainer, 2026-11-14), proposed in M1 slice 0. Proposed first in
  the brief, §3d. Amended 2026-11-14: what slice 2 measured
  ([amendment](#amendment-2026-11-14-what-m1-slice-2-measured)). Amended
  2026-11-14: strings SQLite reads to a NUL, and counted values (M2's plan,
  [amendment](#amendment-2026-11-14-strings-sqlite-reads-to-a-nul-and-counted-values-m2s-plan)).
- **Date:** 2026-11-14
- **Scope:** chez-sqlite3 v1: every foreign procedure
- **Settles:** brief §3d
- **Related:** chez-curl ADR-0013 and chez-libuv ADR-0009, which this follows ·
  [ADR-0001](0001-bind-libsqlite3-directly.md) (no C shim) ·
  [ADR-0005](0005-memory-gate.md) (the `block` counter) ·
  [ADR-0010](0010-a-connection-belongs-to-its-thread.md) (threads) ·
  [the M1 plan](../2026-11-13-m1-plan.md), §3.2

## Context

- **Chez's collector stops every thread.** A thread blocked in a plain foreign call stays
  active, so every other thread's collection waits for it. `__collect_safe` deactivates the
  calling thread for the call (CSUG 10.4.1, §4.2, "Calling out of Scheme"). chez-curl ADR-0013
  records the cost of not doing so, measured through chez-libuv: 10,272 ms against a 28 ms
  baseline.
- **A collection can move a string or a bytevector** while a `__collect_safe` call runs. CSUG
  §4.2 disallows the `string` and `utf-8` types as arguments to one, and says to refrain from
  passing collectable memory.
- **C reads a string up to its first NUL.** A Scheme string can hold U+0000, and would then name
  a shorter file than the one the caller gave.
- **SQLite can block:**
  - `sqlite3_open_v2` creates the file at the open, before any statement runs
    ([research/m1-plan/](../research/m1-plan/));
  - `sqlite3_close` can write, a WAL checkpoint among other things;
  - `sqlite3_prepare_v3` can read the schema from disk, and `sqlite3_step` can do I/O and sleep in
    the busy timeout (M2, M3).
- **Thunderchez leaked an out-parameter block on every open and every prepare** (the assessment).

## Decision

1. **No binding takes a Scheme object.** Every argument is an integer, a flonum, or the address
   of a block we allocated: never Chez's `string`, `utf-8`, `u8*` or `scheme-object` types, nor a
   bytevector. That holds for plain calls as well as `__collect_safe` ones, so one rule covers
   both.
2. **Every string passed to libsqlite3 is copied into a counted foreign block,** UTF-8 and
   NUL-terminated, and the block is freed when the call returns, raises or escapes. The caller's
   string is copied first, and only the copy is checked and encoded, so another thread can't change
   it in between. A string holding U+0000 is refused before anything is allocated. In M1, that is the
   filename. v1 passes no VFS name: `sqlite3_open_v2`'s `zVfs` is NULL.
3. **An out-parameter is a counted block too,** read after the call and freed with it, on every
   path. `sqlite3_open_v2`'s `sqlite3**` is the first. The assessment's leak becomes a test,
   watched failing against a planted copy (ADR-0009).
4. **A string libsqlite3 returns is read by our own code,** from an address bound as `uptr`:
   bytes up to the NUL, or a counted run of them where SQLite gives the count (M2's column
   text). Then it is decoded as UTF-8. M1 reads `sqlite3_libversion`, `sqlite3_sourceid`,
   `sqlite3_errmsg`, `sqlite3_errstr` and `sqlite3_compileoption_get` this way.
5. **The calls that can block are `__collect_safe`:** `sqlite3_open_v2` and `sqlite3_close` in M1,
   `sqlite3_prepare_v3` and `sqlite3_step` in M2. Every other binding is plain. A call joins the
   list when a measurement or SQLite's documentation shows it can wait.
6. **The convention table holds both rules.** It has one row per binding: its C name, its argument
   and result types, and whether it is `__collect_safe`, citing this record. The convention suite
   (slice 2) reads every `foreign-procedure` form under `src/` as data. It fails on a binding
   with no row, on a row with no binding, on a forbidden type and on a mismatch. A binding it
   can't read fails it too.

### Rejected

- **Chez's `string` type for plain calls.** It is fine where the collector can't run, but then two
  rules would govern strings, chosen per call. A call later made `__collect_safe` would carry a
  Scheme string with it unseen.
- **Locking objects instead of copying** (`lock-object`). Every path that raises would then need an
  unlock, and a forgotten one stays invisible to every part of the gate.

## Consequences

- **Every string an M1 call takes costs one allocation and one copy.** That is small beside an
  open.
- **The `block` counter sees every copy and every out-parameter,** so a path that forgets to free
  one fails its suite (ADR-0005).
- **v1 has no callbacks** (brief §4), so CSUG's rule that a callable invoked from a
  `__collect_safe` call must be `__collect_safe` too has nothing to apply to yet.

## Amendment, 2026-11-14: what M1 slice 2 measured

- **A plain blocking call stops every thread.** `sqlite3_open_v2` on a FIFO opened read-only
  blocks until a writer opens it. Bound plain, a collection requested by another thread waited for
  it, and the whole process hung. Bound `__collect_safe`, the collection ran while the open was
  blocked. That holds even when the call sits inside `critical-section`, so slice 4 can count a
  connection in the same critical section as its open.
- **`test-native` holds it by behaviour.** A FIFO row forks a thread that opens a FIFO and collects
  from another, every wait bounded. The FIFO is released by opening it read-write, which POSIX
  leaves undefined. Linux allows it, and the Mac's hand run is the first measurement there. A plain
  `sqlite3_open_v2` fails the row, after its bound. A plain `sqlite3_close` can't be made to block
  on demand, so the convention suite holds it.
- **The bindings are literal forms,** each wrapped by a binder that checks `foreign-entry?` first:
  `(bind-required LIBRARY (foreign-procedure [__collect_safe] "C_NAME" (ARG ...) RESULT))`. The
  convention suite reads them as data (decision 6).
- **The convention table, as built** (`tests/foreign-conventions.sls`): one row per binding, with
  its C prototype in `sqlite3.h`'s spelling beside decision 6's fields, citing ADR-0002's amendment
  where the row is a required entry point. `test-conventions` holds every form under `src/` to it,
  with the type allowlist tested against the 54 type forms Chez 10.4 accepts, and `test-constants`
  checks each row's prototype against the header through `_Generic`.

## Amendment, 2026-11-14: strings SQLite reads to a NUL, and counted values (M2's plan)

Accepted by the maintainer on 2026-11-14, proposed in M2 slice 0
([the M2 plan](../2026-11-14-m2-plan.md), §4.3 to §4.5). Measured on Guix's 3.53.1 and at the
floor, 3.45.1, with the same results ([research/m2-plan/](../research/m2-plan/),
[research/m2-review/](../research/m2-review/)).

- **Decision 2's refusal of U+0000 covers the strings SQLite reads to a NUL:** a filename (M1),
  SQL text and a parameter name (M2). For SQL, it is measured: a NUL ends SQLite's parse even
  with the byte length given, so `select 1`, a NUL and ` garbage` compiled `select 1` and left its
  tail at the NUL. ADR-0013's decision 7, which calls a string holding U+0000 a caller's mistake,
  is narrowed to these strings the same day.
- **A bound TEXT value is counted, and keeps its U+0000:** it goes with its byte length, so SQLite
  reads past a NUL ([ADR-0015](0015-values.md), decision 5). A bound BLOB is a bytevector copied
  into a counted block, since decision 1 passes no bytevector.
- **A pointer passed for a value is never NULL.** SQLite binds NULL for a NULL pointer (measured
  with length 0; its documentation says the length is then ignored), so an empty string or
  bytevector still gets a block of at least one byte.
- **Decision 3's out-parameters in M2:** `sqlite3_prepare_v3`'s statement and tail, each a counted
  block freed on every path. The assessment's leak of prepare's out-parameter becomes a test,
  watched failing against a planted copy (ADR-0009).
- **Decision 4 for columns:** a TEXT value is read through `sqlite3_column_text` and a BLOB through
  `sqlite3_column_blob`, each followed by `sqlite3_column_bytes`, and copied out by our code. An
  empty BLOB answers a NULL pointer, read as no bytes; any NULL pointer is told from running out
  of memory by `sqlite3_errcode`, read at once (ADR-0015, decision 7).
- **Decision 5 in M2: `sqlite3_prepare_v3`, `sqlite3_step`, `sqlite3_reset` and `sqlite3_finalize`
  are `__collect_safe`.** Reset and finalize join because they were measured waiting: with
  `pragma busy_timeout = 1500` and another connection's read, the reset and the finalize of an
  `insert … returning` stepped once each took 1502 ms. Every other M2 binding is plain.
- **The four are held by behaviour, not only by the convention suite,** and a row must catch the
  collection while the call is still blocked. A busy-timeout block ends by itself, where a FIFO's
  doesn't: bound plain, a reset under a reader with `busy_timeout = 1500` held another thread's
  `collect-rendezvous` for 1402 ms, and the collection finished after the reset had returned;
  bound `__collect_safe`, it took 0 ms, while the reset was still blocked
  ([research/m2-review/](../research/m2-review/)). A row copied from `test-native`'s FIFO row,
  which waits up to 12 s for the collection, would pass either way. So each row asserts that the
  collection finished before the blocked call returned, with the busy timeout well above the
  bound the row gives the collection.
- **What blocks each call on demand,** a second connection holding a lock and a busy timeout set
  by pragma:
  - a reset or finalize, under the other's read, of an `insert … returning` stepped once
    (measured);
  - a step, under the other's read, of a plain `insert`, which commits inside its step: expected
    to block the same way, not yet measured; M2 slice 3 measures it;
  - a prepare, under the other's `begin exclusive`, **on a fresh connection only:** one that had
    read the schema first answered 0 at once, and a fresh one waited 1502 ms and answered 5
    (measured).
