# ADR-0014: A statement belongs to its connection, is an integer in a sealed record, and keeps its state in Scheme

- **Status:** Proposed in M2 slice 0. The maintainer chose, on 2026-11-14
  ([the M2 plan](../2026-11-14-m2-plan.md), §3): decision 1's short names (Q1) and `step!`'s
  answer (Q2); decision 3's `&sqlite-closed` for a finalized statement, and a second finalize that
  does nothing (Q5); decision 4's refusal of SQL holding no statement or more than one (Q3), and
  its scan of the tail in Scheme (R2); decision 5's refusal of `step!` on a done or failed
  statement until `reset!` (Q4); and decision 8's finalize, close, then raise the first finalize
  failure, with the connection left open and counted when the close fails (R1). The rest awaits
  the maintainer's acceptance: decision 1's list of verbs, decision 8's order and which failure is
  raised when both a finalize and the close fail among it.
- **Date:** 2026-11-14
- **Scope:** chez-sqlite3 v1: every prepared statement
- **Settles:** brief §4's statements; how [ADR-0010](0010-a-connection-belongs-to-its-thread.md)'s
  decision 2 and [ADR-0012](0012-explicit-close-and-the-handle.md)'s decision 5 are built
- **Related:** [ADR-0011](0011-collect-safe-and-no-scheme-memory.md) (strings and blocking calls) ·
  [ADR-0013](0013-errors-are-condition-types.md) (what is raised) ·
  [ADR-0015](0015-values.md) (what binds and what a column reads) ·
  [research/m2-plan/](../research/m2-plan/) and [research/m2-review/](../research/m2-review/)
  (the measurements) · [the assessment](../chez-sqlite-thunderchez-assessment.org)

## Context

- **A statement's life in SQLite:** `sqlite3_prepare_v3` compiles it; binds set its parameters;
  each `sqlite3_step` answers `SQLITE_ROW`, `SQLITE_DONE` or an error; `sqlite3_reset` rewinds it,
  keeping its bindings; `sqlite3_finalize` frees it.
- **Measured** on Guix's 3.53.1 and at the floor, 3.45.1, with the same results
  ([research/m2-plan/](../research/m2-plan/), [research/m2-review/](../research/m2-review/)):
  - a step after `SQLITE_DONE`, with no reset, runs the statement again: one `insert` stepped twice
    made two rows. A build with `SQLITE_OMIT_AUTORESET` answers `SQLITE_MISUSE` instead;
  - `sqlite3_reset` and `sqlite3_finalize` answer a failed step's code again;
  - **they can also answer a failure of their own, and lose data:** an `insert … returning` stepped
    once commits at its reset or finalize. Under another connection's read, both answered BUSY,
    and the insert was rolled back. SQLite's documentation for `sqlite3_reset` warns of it;
  - **they can wait:** with `pragma busy_timeout = 1500`, that reset and that finalize each took
    1502 ms;
  - `sqlite3_finalize` frees the statement whatever it answers: none was left on the connection
    after answers of 2067 and of 5;
  - a bind while a row is ready answers `SQLITE_MISUSE`, and one out of range `SQLITE_RANGE`;
  - **`sqlite3_clear_bindings` while a row is ready answers `SQLITE_OK` and frees what the row
    still reads:** a later column read gave freed bytes, and Valgrind saw an invalid read of a
    freed 5,008-byte block;
  - `sqlite3_prepare_v3` compiles the first statement and leaves the rest unread, answering
    `SQLITE_OK`. Empty SQL, SQL that is only whitespace, comments or semicolons, gives a NULL
    statement;
  - **preparing a PRAGMA changes the connection,** unstepped: `cache_size`, `encoding` and
    `case_sensitive_like` each changed;
  - a statement's column count changes when another connection adds or drops a column, read
    after its next step;
  - with two statements stepped once under a reader, only the last finalize commits: the first
    answered 0 and the second 5;
  - SQLite's whitespace is exactly space, `\t`, `\n`, `\f` and `\r`, and `/*` as the SQL's last
    two bytes is an error, though `/*` and one more byte is an unterminated comment.

  SQLite's documentation leaves a column read undefined when no row is ready or the index is out
  of range.
- **SQLite links every statement from its connection.** `sqlite3_close` answers `SQLITE_BUSY`
  while one is unfinalized (ADR-0012). So a statement leaked on an open connection stays reachable
  through it, and Valgrind sees it only when the connection is lost too.
- **A `with-exception-handler` handler of a raise inside `critical-section` runs with interrupts
  disabled;** a `guard` clause, which runs after unwinding, doesn't (measured). M1's
  `call-with-open-handle` raises its refusals inside its section, and `call-with-database`'s failed
  open raises inside one, so their callers' handlers do (measured). M1's closing review fixes both
  (ADR-0012, amended).
- **Thunderchez leaked prepare's out-parameter, and its close stopped after finalizing the first
  statement,** joining return codes with `or`, where 0 is true (the assessment).

## Decision

1. **The surface,** in the maintainer's short names (Q1), with `step!`'s answer (Q2):

   ```scheme
   ;; prepare-statement : Database String -> Statement
   ;; finalize-statement! : Statement -> Void
   ;; call-with-statement : Database String (Statement -> A ...) -> A ...
   ;; statement? : Any -> Boolean
   ;; statement-sql : Statement -> String
   ;; parameter-count : Statement -> Natural
   ;; step! : Statement -> Boolean          ; #t when a row is ready, #f when done
   ;; reset! : Statement -> Void
   ;; column-count : Statement -> Natural
   ;; column-name : Statement Natural -> String
   ```

   ADR-0015 gives the binding and column-value verbs. Parameters are numbered from 1 and columns
   from 0, as SQLite numbers them.
2. **The handle is an integer in an opaque, sealed `statement` record,** as a connection's is
   (ADR-0012, decision 2). The record holds the `sqlite3_stmt*` as a `uptr` integer, `#f` once
   finalized; its database; a copy of the SQL it was given; and its state (decision 5). No
   accessor of the handle escapes its library, and one private procedure checks and hands it
   over. **A verb reaches its connection's handle,** for `sqlite3_prepare_v3` or
   `sqlite3_errmsg`, **only through `call-with-open-handle`,** which stays the one accessor of a
   connection's handle (ADR-0012, amended).
3. **Every statement verb checks three things, in order, before anything reaches C:** that its
   argument is a statement, else an assertion violation; that it runs on the thread that owns the
   statement's connection, else `&sqlite-wrong-thread` (ADR-0010, decision 2); and that the
   statement isn't finalized, else `&sqlite-closed`, its `&who` naming the verb (Q5). Then the
   state, by decision 5's table. **`finalize-statement!` makes the first two checks only,** as
   `close-database!` does (ADR-0012, decision 7): on a finalized statement it does nothing (Q5).
4. **Preparing:**
   - The SQL is copied, then checked: a copy holding U+0000 is refused before anything is
     allocated (ADR-0011, amended). The copy is encoded into a counted block and passed with its
     byte length and no prepare flags.
   - The statement and the tail are out-parameters, each a counted block freed on every path
     (ADR-0011, decision 3).
   - A failure raises `&sqlite-error` with the SQL and its offset (ADR-0013, amended).
   - **A NULL statement is refused** (Q3): SQL holding no statement is an assertion violation.
     There is nothing to hand back.
   - **The tail is scanned in Scheme, never prepared** (Q3; the maintainer chose the scan, R2): a
     pure function over the SQL's bytes from the tail's offset. It accepts only:
     - SQLite's whitespace, exactly space, `\t`, `\n`, `\f` and `\r` (measured: `\v`, U+0085
       and U+00A0 are errors);
     - `--`, running to the end of the line or of the SQL;
     - `/*` with at least one byte after it, running to `*/` or to the end (measured: `/*` as the
       last two bytes is an error);
     - semicolons.

     Anything else is an assertion violation, once the statement is finalized: a statement holds
     one statement. Preparing the tail would run a PRAGMA's side effects (measured). SQLite's own
     prepare is the scanner's test oracle, over every byte, and over those edges.
   - The new statement joins its connection's live statements and the `statement` counter goes
     up, in the critical section of decision 10.
5. **A statement's state lives in its record,** and every verb is checked against it before C:

   | State | Reached by | Allowed |
   |---|---|---|
   | `ready` | prepare, `reset!` | binding and `clear-bindings!` (ADR-0015), `step!`, `reset!` |
   | `row` | `step!` answering `#t` | column values (ADR-0015), `step!`, `reset!` |
   | `done` | `step!` answering `#f` | `reset!` |
   | `failed` | a step answering an error code | `reset!` |
   | finalized | `finalize-statement!`, or its connection's close | nothing; `finalize-statement!` does nothing |

   - `finalize-statement!` is allowed in every state (decision 3). `statement-sql`,
     `parameter-count`, `column-count` and `column-name` work in every state but finalized.
   - A refusal before C leaves the state as it was: only SQLite's answer moves it.
   - A verb its state doesn't allow is an assertion violation naming the state. **So `step!` on a
     done or failed statement is refused until `reset!`** (Q4): no build reruns a statement
     unasked, and every build behaves alike.
   - **`clear-bindings!` is `ready`-only** because SQLite doesn't refuse it while a row is ready,
     and then frees what the row still reads (measured).
   - **A column index is checked against `sqlite3_column_count`,** read in the same critical
     section as the read it guards, never cached: the count changes when another connection
     changes the table (measured).
6. **Stepping:** `sqlite3_step`, `__collect_safe` (ADR-0011, decision 5). `SQLITE_ROW` gives the
   state `row` and the answer `#t`; `SQLITE_DONE` gives `done` and `#f` (Q2). Any other code gives
   `failed` and raises `&sqlite-error` from the step's own code, which is extended (measured), with
   `sqlite3_errmsg` read on the owning thread straight after, the statement's SQL, and no offset
   (ADR-0013, amended).
7. **Resetting and finalizing** call `sqlite3_reset` and `sqlite3_finalize`, both
   `__collect_safe`: they can wait in the busy handler (measured; ADR-0011, amended).
   - **In the `failed` state, their answer repeats the failed step's code** (measured), which that
     step has raised already, so it is not raised again.
   - **In any other state, an answer other than `SQLITE_OK` is a failure of its own,** such as the
     commit of an `insert … returning` stepped once (measured). It raises `&sqlite-error`, after the
     critical section, with `sqlite3_errmsg` read straight after and the statement's SQL.
   - `reset!` gives the state `ready`, whatever SQLite answered, and the bindings stay, as SQLite
     keeps them.
   - `finalize-statement!` clears the handle, removes the statement from its connection's live
     statements and counts it down on every answer, since SQLite has freed it, and only then
     raises.
   - **`call-with-statement`** mirrors `call-with-database` (ADR-0012, decision 8): the procedure
     is checked first, then the statement is prepared and passed to it, and finalized when it
     returns, escapes or raises, through `dynamic-wind`. A finalize that fails after the procedure
     returned raises. One that fails after the procedure raised doesn't raise over the procedure's
     condition, which reaches the caller unchanged; the statement is freed either way. A
     continuation that re-enters finds the statement finalized.
8. **A connection holds its live statements, strongly. `close-database!` finalizes each, closes,
   then raises.** The maintainer chose (R1):
   - it finalizes every statement it holds, by decision 7, keeping the first failure any finalize
     reported;
   - then `sqlite3_next_stmt` must find none, and `sqlite3_close` runs (ADR-0012, decision 5);
   - **if the close succeeds, the first finalize failure is raised,** with the connection closed:
     the caller learns that, for example, a commit was lost;
   - if `sqlite3_close` fails, the connection stays open and counted.

   Proposed with it:
   - **the statements are finalized oldest first,** in the order they were prepared;
   - when `sqlite3_close` fails, its failure is the one raised, as in M1; an untracked statement
     is refused as in M1; each takes the place of a finalize failure;
   - **one failure is all the measured case reaches:** of two statements stepped once under a
     reader, only the last finalize commits, and only it answered BUSY (measured). So no row can
     tell "the first" from "the last", and the row asserts that the one failure is raised and the
     connection closed.

   A statement kept past its connection's close is finalized, and its verbs raise
   `&sqlite-closed`.
9. **The `statement` counter** goes up for every statement `sqlite3_prepare_v3` hands back, and
   down at its finalize (ADR-0005).
10. **One critical section per verb.** The checks, the handle's use, the state's change, the live
    statements and the count change together. **Anything raised is raised after the section,**
    from the data it returns, as `open-connection` and `close-connection` do in M1, so a caller's
    `with-exception-handler` handler never runs with interrupts disabled. `prepare-statement` and
    `call-with-statement`'s prepare are verbs too, and `call-with-statement`'s own handler around
    its procedure, as `call-with-database`'s, must not run inside a section. They reach the
    connection's handle through `call-with-open-handle`, as M1's closing review leaves it
    (ADR-0012, amended).
    `sqlite3_prepare_v3`, `sqlite3_step`, `sqlite3_reset` and `sqlite3_finalize` run inside their
    sections; they are `__collect_safe`, so other threads collect meanwhile (ADR-0011's
    amendment).

### Rejected

- **Guardians, to finalize a dropped statement,** for ADR-0012's reasons: they hide the leak the
  gate exists to find.
- **Tracking statements weakly.** A dropped statement would leave the table without being
  finalized, and the next close would find it through `sqlite3_next_stmt` and refuse.
- **Raising none of reset's and finalize's answers,** the first draft's rule. A lost commit would
  pass in silence (the review's measurement).
- **Preparing the tail to check it:** a refused `select 1; pragma …` would still have changed the
  connection (R2).
- **Raising a finalize failure before `sqlite3_close`,** leaving the connection open for a retry
  (R1).
- **Following SQLite after `done`** (Q4), **preparing the first statement and ignoring or
  returning the rest** (Q3), **a new `&sqlite-finalized`** (Q5), the symbols `row` and `done`
  (Q2), and prefixed names such as `statement-step!` (Q1): the maintainer chose otherwise.

## Consequences

- **A statement never finalized lives until its connection closes,** since the connection holds
  it. The `statement` count shows it at any moment: a long-lived connection that prepares in a
  loop without finalizing grows, and its count with it.
- **A blocking call holds its own thread's interrupts:** while a step, prepare, reset or finalize
  waits, a keyboard interrupt, a timer or an engine's expiry waits too. Other threads run and
  collect. M3's interrupt is how another thread stops a long one.
- **`call-with-statement` is expected not to survive an engine's preemption,** as ADR-0012's
  amendment measured for `call-with-database`. M2 slice 3 measures it.
- **A refused SQL's first statement has been prepared,** so its prepare-time effects stand:
  `pragma cache_size = 7; select 1` is refused, and `cache_size` is 7 afterwards (measured).
  Finding the first statement's end without preparing it would mean tokenizing SQL in Scheme.
  M2 slice 3 holds it by a row, and `docs/reference.md` says so.
- **When a close fails twice over,** a finalize and then `sqlite3_close`, the close's failure is
  the one raised, and the finalize's is lost.
- **Valgrind sees a leaked statement only through its connection.** The counters see it alone.
- **M3's conveniences are built on these verbs,** and its statement cache (brief D3) holds
  statements its connection still tracks.
