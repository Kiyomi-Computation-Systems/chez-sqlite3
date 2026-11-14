# ADR-0012: Closing is explicit, with no guardians, and a connection's handle is an integer in a sealed record

- **Status:** Accepted (the maintainer, 2026-11-14), proposed in M1 slice 0. The maintainer
  approved decision 2 (the handle) and decision 3's surface on 2026-11-13, and decision 7's type
  and decision 8's shape on 2026-11-14. Proposed first in the brief, §3e. Amended 2026-11-14:
  what slice 4 built ([amendment](#amendment-2026-11-14-what-m1-slice-4-built)).
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
   and there are no guardians and no finalizers. A connection never closed is a leak, and the
   `connection` counter sees it. On Linux, Valgrind should see it at exit too, if slice 4's leaks
   plant confirms what M0 measured with bare FFI (the consequences).
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

   - **The mode options, and the flags each gives:**

     | Options | Flags |
     |---|---|
     | none | `READWRITE` \| `CREATE` |
     | `'create` | `READWRITE` \| `CREATE` |
     | `'read-write` | `READWRITE` |
     | `'read-write 'create` | `READWRITE` \| `CREATE` |
     | `'read-only` | `READONLY` |

     So `'create` implies read-write, and `'read-write` alone doesn't create the file.
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
7. **A closed connection refuses every verb but `close-database!`** with `&sqlite-closed`
   (ADR-0013). Each verb checks
   three things, in order, before it reaches C: that its argument is a database, that it runs on
   the owning thread (ADR-0010), and that the connection is open. A second `close-database!` on
   the owning thread does nothing and returns. The record keeps no address once closed.
8. **`call-with-database` takes the procedure last** (the maintainer, 2026-11-14):

   ```scheme
   ;; call-with-database : String Symbol ... (Database -> Any) -> Any
   (call-with-database "app.db" 'read-only
     (lambda (db) …))
   ```

   It checks the procedure before anything is opened, opens with the options given, and calls the
   procedure. Its answer is the procedure's.
   - **When the procedure returns,** or leaves through a continuation, the connection is closed,
     through `dynamic-wind`. A failure of that close raises.
   - **When the procedure raises,** the connection is closed, and the procedure's condition
     reaches the caller, unchanged. If that close fails too, its failure is not raised over the
     procedure's: the connection stays open and counted, so the gate sees it.
   - **A continuation that re-enters the procedure** finds the connection closed.
   - **A raise no handler catches** ends a program through Chez's exit, which runs no after thunk.
     The process is ending, and SQLite's files are left as a crash would leave them.

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
- **A filename starting `file:` is a URI on most builds, with or without `'uri`.** Ubuntu's,
  Apple's and Homebrew's are compiled with `USE_URI`, and no open flag turns that off. So a
  filename can bring in `vfs=` or `cache=shared`. Whether `open-database` refuses a `file:` name
  given without `'uri` is decided in slice 4, with a test per build (the M1 plan, §7).

## Amendment, 2026-11-14: what M1 slice 4 built

- **A `file:` name without `'uri` is refused** (the maintainer, 2026-11-14): an assertion violation
  from the procedure the caller called, before anything is allocated, its irritants
  `(file-uri-without-uri-option (kind string))`. The test is SQLite's own: the five bytes `file:`
  at position 0, case-sensitive. With `SQLITE_OPEN_URI`, `"FILE:up.db"` opened a file of that
  literal name (3.53.1). This settles the consequence's open question. Guix's 3.53.1 isn't built
  with `USE_URI` (`sqlite3_compileoption_used("USE_URI")` answered 0, and `"file:nu.db?mode=rwc"`
  without the flag made a file of that name), so there such a name would have been a plain file;
  the refusal makes every build alike.
- **The public names** (the maintainer, 2026-11-14): `sqlite-version`, `sqlite-version-number`,
  `sqlite-source-id`, `sqlite-library-path`, `sqlite-library-source`, `sqlite-compile-option?`,
  `sqlite-compile-options`, `open-database`, `close-database!`, `call-with-database`,
  `database?`, and the conditions' predicates and accessors (ADR-0013, amended). `test-public`
  asserts the list whole, so no private binding can leak through `(chez-sqlite3)`.
- **The libraries:** `(chez-sqlite3 private open-options)`, the pure parser of decision 3's table;
  `(chez-sqlite3 private connection)`; and `(chez-sqlite3 private report)`. `(chez-sqlite3)`
  re-exports, with an empty body, and referencing a condition predicate through it runs no
  library that loads libsqlite3.
- **`call-with-open-handle` is the only accessor of the handle,** even privately. It runs its three
  checks (decision 7) and the procedure in one critical section, so no engine or interrupt can
  close the handle between a check and its use. The open, the read of the out-parameter and
  `count-up!` share one critical section; so do the close, clearing the handle and `count-down!`.
- **`call-with-database` doesn't survive an engine's preemption.** An expiry runs `dynamic-wind`'s
  after thunk: a 2,000-expiry engine logged 4,002 before and after entries. So the connection
  closes at the first expiry, and a resumed procedure finds it closed. A program under engines
  takes `open-database`.
- **SQLite refuses a close when a backup reads from the connection,** with `SQLITE_BUSY` and no
  statement open. `test-connection` uses that to test decision 5's failed close.
- **The consequence on Valgrind holds.** A connection from `open-database` whose record is dropped
  unclosed is definitely lost at exit: 840 bytes direct and 61,288 indirect on 3.53.1, 792 and
  56,640 on 3.45.1, the same with the record held by a top-level variable and after
  `(collect 4)`. `check-memory-gate` plants it, beside the counters' case in `check-test-fails`.
- **Three of the assessment's defects are planted and caught:** a failed open's handle never
  closed, an out-parameter never freed, and a close that leaves the address in the record.
