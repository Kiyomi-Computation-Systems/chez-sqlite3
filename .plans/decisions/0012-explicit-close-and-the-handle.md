# ADR-0012: Closing is explicit, with no guardians, and a connection's handle is an integer in a sealed record

- **Status:** Accepted. The maintainer approved the handle and the open surface on 2026-11-13, and
  the closed type and `call-with-database`'s shape on 2026-11-14. Proposed in the brief, §3e.
- **Date:** 2026-11-14
- **Scope:** chez-sqlite3 v1: opening and closing a connection
- **Settles:** brief §3e, and the open surface of brief §4
- **Related:** chez-libuv ADR-0007, which this follows ·
  [ADR-0005](0005-memory-gate.md) (the gate) ·
  [ADR-0010](0010-a-connection-belongs-to-its-thread.md) (threads) ·
  [ADR-0011](0011-collect-safe-and-no-scheme-memory.md) (strings and out-parameters) ·
  [ADR-0013](0013-errors-are-condition-types.md) (what is raised) ·
  [the M1 plan](../2026-11-13-m1-plan.md), §3.1

## Context

- **A guardian closes a connection when the collector notices it.** That may be never, or long
  after the file should have been released. And a leak it hides is invisible to the gate.
- **`sqlite3_open_v2` returns a handle even when the open fails,** unless SQLite can't allocate
  one. That handle must still be passed to `sqlite3_close`. Thunderchez left it open (the
  assessment).
- **`sqlite3_close` refuses with `SQLITE_BUSY`** while statements are unfinalized, and leaves the
  connection open. `sqlite3_close_v2` instead marks the connection a "zombie", to be freed when
  its last statement is.
- **Valgrind sees a connection left open only if its handle is held as an integer** (ADR-0005,
  amended at M0 slice 3). A fixnum holds the address shifted, so Valgrind finds no pointer to it,
  and the never-closed connection is definitely lost at exit. In an ftype pointer, the same
  connection is still reachable and the gate passes.
- **`sqlite3_open_v2`'s flags must include exactly one of** `READONLY`, `READWRITE`, or
  `READWRITE|CREATE`. SQLite's documentation calls any other combination undefined behaviour.

## Decision

1. **Closing is explicit.** `open-database`, `close-database!` and `call-with-database` are public,
   and there are no guardians and no finalizers. A connection never closed is a leak, and the gate
   sees it: through the `connection` counter, and through Valgrind at exit.
2. **The handle is an integer in an opaque, sealed record.** The `sqlite3*` address, bound as
   `uptr`, sits in a field of a `database` record whose type is opaque and sealed. The field's
   accessor stays private, so no caller can forge, copy or reuse a handle. A procedure that takes
   a database checks the record type first, which takes over the check an ftype pointer typed
   `(* sqlite3)` would have given at the boundary: `uptr` takes any integer.
3. **The open surface** (approved 2026-11-13):

   ```scheme
   ;; open-database : String Symbol ... -> Database
   (open-database "app.db")                        ; read-write, creating the file
   (open-database "app.db" 'read-only)
   (open-database "app.db" 'read-write)            ; read-write, without creating
   (open-database "file:app.db?mode=ro" 'uri 'read-only)
   (open-database "app.db" 'no-mutex)
   ```

   - With no mode, a connection opens read-write and creates the file. `'read-write` alone
     doesn't create it, `'create` adds creation, and `'read-only` opens read-only.
   - `'uri`, `'memory` and `'no-follow` add `SQLITE_OPEN_URI`, `SQLITE_OPEN_MEMORY` and
     `SQLITE_OPEN_NOFOLLOW`. `'no-mutex` swaps `FULLMUTEX` for `NOMUTEX` (ADR-0010).
     `SQLITE_OPEN_EXRESCODE` is always on. v1 never passes a shared-cache flag or a VFS name.
   - **Refused** with an assertion violation from `open-database`, before anything is allocated:
     `'read-only` with `'read-write` or `'create`, an option given twice, and an unknown option,
     each named. So the flags SQLite gets are always one of its three legal combinations.
4. **A failed open closes its handle before it raises.** SQLite's message is read first, from the
   failing handle, then the handle is passed to `sqlite3_close`, and then `&sqlite-error` is
   raised (ADR-0013). A NULL handle, when SQLite couldn't allocate one, takes its message from
   `sqlite3_errstr`.
5. **Closing finalizes the connection's tracked statements** (M2). Then `sqlite3_next_stmt` must
   find none (ADR-0005, decision 5), and then `sqlite3_close` runs, never `sqlite3_close_v2`.
   - **A statement the connection doesn't track** is a defect in chez-sqlite3, so
     `close-database!` raises an assertion violation naming the count, and leaves the connection
     open. The counters and Valgrind then see it too.
   - **`sqlite3_close` answering anything but `SQLITE_OK`** raises `&sqlite-error`, and the
     connection stays open, still counted.
6. **The `connection` counter** goes up when `sqlite3_open_v2` hands back a handle, failed or not,
   and down when `sqlite3_close` answers `SQLITE_OK` (ADR-0005).
7. **A closed connection refuses every verb** with `&sqlite-closed` (ADR-0013). Each verb checks
   three things, in order, before it reaches C: that its argument is a database, that it runs on
   the owning thread (ADR-0010), and that the connection is open. A second `close-database!` on
   the owning thread does nothing and returns. The record keeps no address once closed.
8. **`call-with-database` takes the procedure last** (the maintainer, 2026-11-14):

   ```scheme
   ;; call-with-database : String Symbol ... (Database -> Any) -> Any
   (call-with-database "app.db" 'read-only
     (lambda (db) …))
   ```

   It opens with the options given, calls the procedure, and closes the connection when the
   procedure returns or raises, through `dynamic-wind`. Its answer is the procedure's. The
   procedure is checked before anything is opened. A continuation that re-enters the procedure
   finds the connection closed.

### Rejected

- **Guardians, as a fallback behind explicit close.** They hide the leak the gate exists to find,
  and close on the collector's schedule.
- **`sqlite3_close_v2`.** A connection with a leaked statement would become a zombie that
  outlives its owner, unseen.
- **An ftype pointer `(* sqlite3)`.** Valgrind would then be blind to a connection left open
  (the context).
- **A public handle accessor,** even read-only. A copied address outlives its record's close.

## Consequences

- **Every suite closes what it opens,** or its counts fail it (ADR-0005).
- **Slice 4's leaks plant opens through `open-database` and drops the record.** It must fail
  through the counters and under Valgrind. If Valgrind can't see it, because a raw copy of the
  address survives somewhere in SQLite's calls, that is recorded, and the counters still hold
  (the M1 plan, §3.1).
- **M3's settings list arrives as an argument that isn't a symbol,** so the options stay
  symbols.
