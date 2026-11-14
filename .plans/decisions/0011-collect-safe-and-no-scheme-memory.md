# ADR-0011: Calls that can block are `__collect_safe`, and nothing passed to libsqlite3 lives in Scheme memory

- **Status:** Proposed in M1 slice 0, for the maintainer's acceptance with its PR. Proposed first in
  the brief, §3d. Amended 2026-11-14: what slice 2 measured
  ([amendment](#amendment-2026-11-14-what-m1-slice-2-measured)).
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
