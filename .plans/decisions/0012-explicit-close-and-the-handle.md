# ADR-0012: Closing is explicit, with no guardians, and a connection's handle is an integer in a sealed record

- **Status:** Accepted (the maintainer, 2026-11-14), proposed in M1 slice 0. The maintainer
  approved decision 2 (the handle) and decision 3's surface on 2026-11-13, and decision 7's type
  and decision 8's shape on 2026-11-14. Proposed first in the brief, §3e. Amended 2026-11-14:
  what slice 4 built ([amendment](#amendment-2026-11-14-what-m1-slice-4-built)). Amended 2026-11-14: the statements a connection
  holds (M2's plan, [amendment](#amendment-2026-11-14-the-statements-a-connection-holds-m2s-plan)).
  Amended 2026-11-14, and accepted by the maintainer that day: raised after the section (M1's
  closing review,
  [amendment](#amendment-2026-11-14-raised-after-the-section-m1s-closing-review)). Amended
  2026-11-15, and accepted by the maintainer that day: the settings, and the close's exclusion of
  interrupts (M3's plan,
  [amendment](#amendment-2026-11-15-the-settings-and-the-closes-exclusion-of-interrupts-m3s-plan)).
  Amended 2026-11-16 in M3 slice 5, and accepted by the maintainer that day: the open verbs'
  library, the open's claim, and decision 8's handler around the open
  ([amendment](#amendment-2026-11-16-the-open-verbs-library-m3-slice-5)).
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

## Amendment, 2026-11-14: the statements a connection holds (M2's plan)

Accepted by the maintainer on 2026-11-14, proposed in M2 slice 0. Closing, then raising a
finalize's failure, is the maintainer's own choice (R1, 2026-11-14,
[the M2 plan](../2026-11-14-m2-plan.md), §3).

- **Decision 5 is built in M2,** by [ADR-0014](0014-statements-belong-to-their-connection.md):
  the `database` record holds its live statements, strongly. `close-database!` finalizes each,
  counting each down, before `sqlite3_next_stmt` and `sqlite3_close`.
- **A finalize can report a failure of its own,** such as the commit of an `insert … returning`
  stepped once, answered BUSY and rolled back (measured,
  [research/m2-review/](../research/m2-review/)). The statement is freed all the same.
  `close-database!` keeps the first such failure, closes, and then raises it, with the connection
  closed (R1).
- **A close that then fails leaves its statements finalized.** `sqlite3_close` answering
  `SQLITE_BUSY`, as it does while a backup reads from the connection, keeps the connection open
  and counted, as decision 5 says, and its failure is the one raised.
- **M2's statement verbs reach a connection's handle only through `call-with-open-handle`,** which
  stays its one accessor: `prepare-statement`, and every verb that needs `sqlite3_errmsg`
  ([ADR-0014](0014-statements-belong-to-their-connection.md), decisions 2 and 10).
- **M1's closing review fixes two raises inside critical sections, not M2.** `call-with-open-handle`
  raises `&sqlite-wrong-thread`, `&sqlite-closed` and its refusal of a non-database inside its
  section, and `call-with-database`'s failed open raises inside the section that holds its open,
  so a `with-exception-handler` handler of the raise runs with interrupts disabled; a `guard`
  clause, which runs after unwinding, doesn't (measured, [research/m2-review/](../research/m2-review/),
  and reproduced by the M1 session on `main` at `2579a0d`). The M1 session took the fix on
  2026-11-14, in the shape slice 0's review proposed: the record and owner checks before the
  section, the open check inside it returning its refusal as data, the procedure returning data
  and raising nothing, every refusal raised after, and `call-with-open-handle` still the one
  accessor. It landed as PR #15, `1b2f688`, with its own amendment to this record, below, which
  the maintainer accepted on 2026-11-14; M2 slice 3 builds on the contract it settles.
- **A failed close raises `&sqlite-busy` there,** a `&sqlite-error`: ADR-0013's subtypes, amended
  the same day, class every raise.

## Amendment, 2026-11-14: raised after the section (M1's closing review)

Accepted by the maintainer on 2026-11-14, proposed in M1's closing review. The maintainer had
approved its scope and the procedure's contract that day.

- **The rule.** Nothing raises inside `critical-section`, or inside a critical `dynamic-wind`
  thunk, in any library under `src/` or in `(chez-sqlite3-testing)`. Code there answers data, and
  the raise follows the section. A raise from a call made there is caught inside the section and
  raised again after it, as the same object.
- **Why.** A `with-exception-handler` handler runs in the raise's dynamic extent, before anything
  unwinds. For a raise inside a section, it runs at interrupt depth 2, and depth 3 where two
  sections nest. There, the closing review measured on `497d45b`:
  - an engine never expired: one run inside such a handler was killed after 10 s;
  - another thread's `collect-rendezvous` waited more than 11 s behind such a handler, against
    1 ms behind a handler for a raise outside a section.

  A `guard` clause unwinds first, and runs at depth 1. The M2 session found the first two sites,
  and the M1 session reproduced them on `2579a0d`.
- **The sites, nine:**
  1. `call-with-open-handle`'s refusals and its procedure's raise;
  2. `call-with-database`'s open, and its U+0000 refusal;
  3. `call-with-database`'s close, from its critical after thunk;
  4. `close-connection`'s double free;
  5. `free-foreign-block!`'s refusal of a block that isn't live, and its double free;
  6. `foreign-block`'s allocation failure;
  7. `call-with-block`'s refusal of a re-entry;
  8. the testing library's `make-capture-directory`;
  9. `call-with-block`'s failed free, when its procedure had freed the block, which was found
     while fixing the eight.
- **`call-with-open-handle`:**
  - **It checks the database and its owner before the section.** Neither can change: the record's
    type, its immutable owner field, and the caller's own thread id.
  - **In the section are the open check and the procedure.** The procedure answers data. What it
    raises is caught, and raised again after the section with `raise`, so a `raise-continuable`
    from it can't be resumed (the maintainer, 2026-11-14). It runs with interrupts off, so it
    keeps to the C call and its reads.
  - **This replaces slice 4's** "its three checks … and the procedure in one critical section".
    It is still the handle's only accessor, and it is the contract M2's statement verbs build on.
- **The open holds the filename's C string, the open, the out-parameter's read and `count-up!` in
  one critical section.**
  - **Before,** an engine's expiry could land between the string's block and the open. It freed
    the block, and the resume refused the open: at fuel 20, 50 opens of 50, and over fuel 20 to
    400, at 54 of 381 sizes.
  - **Now** `open-database` completes at every fuel from 1 to 60, and `sqlite-compile-option?` at
    every fuel from 1 to 40. So slice 4's "a program under engines takes `open-database`" holds,
    as `docs/reference.md` says.
  - **A U+0000 in the filename is refused as before,** by `call-with-c-string`: caught in the
    section and raised after it, with the same who and irritants.
- **`call-with-database`: decision 8 is unchanged.**
  - Its open answers data in its section, and raises after it.
  - Its critical after thunk closes and records any failure, raising nothing.
  - A plain `dynamic-wind` around it raises that failure, unless the procedure is raising.
  - The procedure runs outside any section, so its warnings stay resumable.
- **The double frees and memory's refusals are raised after their sections:**
  - `close-connection`'s `count-down!`;
  - `free-foreign-block!`'s refusal and its `count-down!`;
  - `foreign-block`'s allocation failure. `foreign-alloc` raises it, and never answers 0, so the
    branch for 0 is gone.

  Each keeps its who and irritants.
- **Held by:**
  - a row per site, whose handler reads the depth and expects 1, with a no-raise sentinel distinct
    from it;
  - engine rows over fuel 1 to 60 for the open, and 1 to 40 for `sqlite-compile-option?`;
  - rows for the procedure's raise: the same object, a warning not resumed, several values
    answered.

  The rows failed on the code before. Each of 18 mutations moved one raise back inside its section,
  or one string's extent out of it, and each was caught
  ([the log](../m1-closing-review-mutation-log.md)).
- **The review of these fixes** (Opus, read-only) found one major finding and six minor ones, all
  reproduced:
  - **No row held the section's purpose,** that no close falls between the open check and the
    procedure's use of the handle. Replacing the section with `begin`, or reading the handle
    before it, passed every suite, and handed the procedure a closed connection's freed handle at
    fuel 8 to 12.
    - A row now sweeps two engines that share a connection, over fuel 1 to 60. One runs
      `call-with-open-handle`, the other closes the connection.
    - Both mutants fail the row.
  - **A continuation captured in the procedure, re-entered after the call ended,** ran the
    procedure again with the freed handle. This was older than these fixes.
    - `call-with-open-handle` now sits in a plain `dynamic-wind`, as `call-with-block` does. Its
      before thunk refuses a re-entry from WHO, with irritants `(re-entered)`, outside any section.
    - Its flag is set once the section's outcome is in hand, never by an after thunk, so an
      engine's expiry before then still resumes.
    - A few instructions lie between the flag's set and the wind's exit, where an expiry's resume
      would be refused. No engine reached them: over fuel 1 to 3000, 60,000 calls all ran.
  - **A raise of a non-condition from the procedure** comes back as the same object, at depth 1.
- **Under an engine, `call-with-database`'s close at an expiry may fail.** It did so with an
  untracked statement left open. Its failure is then raised during the expiry's unwind. The
  engine is lost, its caller sees "no engine active", and the connection stays open. This was
  older than these fixes, and M2's close, which raises a finalize's failure, makes it reachable
  without a defect. A program under engines takes `open-database`, and `docs/reference.md` says so.
- **The M2-plan amendment's last bullets are met here.** M2 slice 3 builds on this contract.

## Amendment, 2026-11-15: the settings, and the close's exclusion of interrupts (M3's plan)

Accepted by the maintainer on 2026-11-15 ("Accept all"), proposed in M3 slice 0
([the M3 plan](../2026-11-15-m3-plan.md), §4.3 and §4.4).

- **The consequence's settings list is built** ([ADR-0018](0018-the-settings-list.md)): at most one
  argument among `open-database`'s and `call-with-database`'s options may be a list, the
  settings. The signatures become:

  ```scheme
  ;; open-database : String (U Symbol Settings) ... -> Database
  ;; call-with-database : String (U Symbol Settings) ... (Database -> A ...) -> A ...
  ```

  The list is checked with the options, before anything is allocated.
- **The record gains the statement cache's capacity,** from the list's `statement-cache`, 32 when
  it gives none, fixed when the record is made ([ADR-0020](0020-the-statement-cache.md)). A size
  can't be an option, which stays a symbol (decision 3).
- **A setting that fails or mismatches closes the connection, then raises,** as decision 4's
  failed open does. `call-with-database` then never calls its procedure.
- **Decision 5's close first excludes interrupts** ([ADR-0019](0019-interrupt-and-close.md)): in
  its critical section, before finalizing anything, it clears the record's `interruptible` flag
  under the record's mutex. A close that leaves the connection open sets it again, on both paths:
  a statement found untracked, and `sqlite3_close` failing.
- **The close's section empties the record's statement cache, whether or not the connection
  closes** ([ADR-0020](0020-the-statement-cache.md)): it has finalized every tracked statement,
  the cache's among them, on either path.
- **Decision 7's "every verb" has one exception, `interrupt-database!`,** which any thread may
  call, and which does nothing on a closed connection (ADR-0010, amended).

## Amendment, 2026-11-16: the open verbs' library (M3 slice 5)

Accepted by the maintainer on 2026-11-16 ("Accept all"), proposed in M3 slice 5, from its
builders' reports and its adversarial review ([ADR-0018](0018-the-settings-list.md), amended in
M3 slice 5).

- **`open-database` and `call-with-database` moved to `(chez-sqlite3 private open)`,** a fourth
  library beside M1 slice 4's three. Their settings run statements through
  `(chez-sqlite3 private statement)`, which imports `(chez-sqlite3 private connection)`. That
  library keeps the open's parts, and exports them to the new one:
  - `prepared-open`, the filename's and the options' checks;
  - `connection-outcome`, the open's one critical section. It is M1's `open-outcome` renamed:
    exported under its old name, it clashed with a definition of
    `(chez-sqlite3 private statement)`'s own, which imports the library whole
    ([traps.md](../traps.md));
  - `opened-database`, its outcome raised;
  - `close-connection`, the close for a who.
- **`connection-outcome` takes the call's claim,** `refused?`, read first inside the open's
  section. When another run of the same call has opened, the section opens nothing and answers
  `(refused)`, which `opened-database` raises as `&sqlite-closed`. So of one call's runs, one
  alone opens.
- **Decision 8's handler that marks a raise wraps the open and the settings too,** not the
  procedure alone. So the close's failure isn't raised over a setting's failure, nor over a
  refused run's `&sqlite-closed`.
- **`open-database-with-cache-capacity` is gone.** The suites give `'((statement-cache . N))`
  ([ADR-0020](0020-the-statement-cache.md), amended in M3 slice 5).
