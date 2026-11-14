# ADR-0013: Errors are condition types under one fieldless root, and SQLite's codes are symbols

- **Status:** Accepted (the maintainer, 2026-11-14), proposed in M1 slice 0. The maintainer
  chose decision 1's root and decision 6's closed type on 2026-11-14. Proposed first in the brief,
  §3g. Amended 2026-11-14: what slice 4 built
  ([amendment](#amendment-2026-11-14-what-m1-slice-4-built)). Amended 2026-11-14: M2's conditions (M2's plan,
  [amendment](#amendment-2026-11-14-m2s-conditions-m2s-plan)).
- **Date:** 2026-11-14
- **Scope:** chez-sqlite3 v1: every condition the library raises
- **Settles:** brief §3g
- **Related:** chez-curl ADR-0022 and chez-libuv ADR-0006, which this follows ·
  [ADR-0002](0002-runtime-libsqlite3-discovery.md) (the load's reasons) ·
  [ADR-0010](0010-a-connection-belongs-to-its-thread.md) (the wrong thread) ·
  [ADR-0012](0012-explicit-close-and-the-handle.md) (a closed connection) ·
  [the M1 plan](../2026-11-13-m1-plan.md)

## Context

- **SQLite answers with integer codes.** A primary code is the low byte of an extended one.
  Connections open with `SQLITE_OPEN_EXRESCODE` (brief §3g), so calls return extended codes.
- **Some failures have no SQLite code:** a library refused at load (ADR-0002), a verb on the wrong
  thread (ADR-0010), a closed connection (ADR-0012).
- **Brief §3g gives the base `&sqlite-error`** the primary code, the extended code, the message,
  the SQL and the error offset.
- **chez-curl's checked accessors.** Chez's own check named the value it refused, so a refusal
  could print a caller's secret (chez-curl ADR-0036). chez-curl's `checked-accessor` names a
  value by its kind instead.

## Decision

1. **The hierarchy** (the maintainer chose the fieldless root, 2026-11-14):

   ```
   &error
    └ &chez-sqlite3-error             no fields; every library condition is one
       ├ &sqlite-error                code, extended-code, message, sql, offset
       │   └ (M2) &sqlite-busy, &sqlite-constraint, &sqlite-read-only
       ├ &sqlite-library-unavailable  reason, path, source, detail, candidates, library
       ├ &sqlite-wrong-thread         owner, caller
       └ &sqlite-closed               no fields
   ```

   `sqlite-error?` means SQLite returned a code. `chez-sqlite3-error?` catches every library
   condition. A caller's mistake is an assertion violation (decision 7), which it doesn't catch.
2. **Every raise compounds a `&who`** naming the public procedure, so `condition-who` says which
   call failed. A refusal at load, which no one procedure raises, names `chez-sqlite3`. `&sqlite-error` also carries a `&message` with SQLite's text, so Chez's printer
   shows it, beside the field that is the contract.
3. **`&sqlite-error`'s fields:**
   - **`code`**: the primary code as a symbol. A code's name is its C name with `SQLITE_`
     dropped, lower-cased, and `_` turned to `-`: `busy`, `cantopen`, `constraint`.
   - **`extended-code`**: the extended code as a symbol, by the same rule: `cantopen-isdir`,
     `constraint-unique`. A primary code with no extension is its own extended code: `busy`. A
     code no table row names, newer than the floor's header, is the integer itself.
   - **`message`**: `sqlite3_errmsg` for the connection, read on the owning thread right after
     the failing call, or `sqlite3_errstr` of the code when there is no connection.
   - **`sql`** and **`offset`**: the statement's text and `sqlite3_error_offset`, from M2's
     prepare. Otherwise `#f`.
4. **One table names every code in the floor's header,** 3.45.1's, primary and extended.
   `test-constants` checks every row against the `sqlite3.h` each lane compiles with (ADR-0001). A
   newer header may name more codes, and the table leaves those as integers. Every code's primary
   code is its low byte, and every primary code is named, so a code the table doesn't name still
   has a named `code`, and decision 8's class.
5. **`&sqlite-library-unavailable`'s fields are chez-curl's six:** reason, path, source,
   detail, candidates and the report, `#f` when the refusal came before the version was read.
   The reasons are `invalid-override`, `not-found`, `load-failed`, `below-floor`,
   `not-threadsafe` and `missing-api` (ADR-0002, amended). A reason outside that list is an
   assertion violation from the constructor, so a misspelt reason can't reach a caller.
6. **`&sqlite-wrong-thread`** carries the owner's and the caller's thread ids.
   **`&sqlite-closed`** carries nothing beyond its `&who`.
7. **A caller's mistake is an assertion violation,** never a library condition: an argument of
   the wrong type, an unknown or contradictory open option, a string holding U+0000. It names the
   argument by its kind when it is a string, never the string, since a filename or a URI can hold
   a key (chez-curl ADR-0036). Every accessor of the library's types is checked this way.
8. **M1 builds the root, `&sqlite-error`, `&sqlite-library-unavailable`, `&sqlite-wrong-thread`
   and `&sqlite-closed`.** M2 builds the subtypes, each classed by its primary code, never by
   the scenario (chez-curl ADR-0022): busy and locked, constraint, and read-only.
9. **Tests assert the type, the reason or code, and the fields,** never the message text.

### Rejected

- **`&sqlite-error` as the root,** with a new type carrying the codes. `sqlite-error?` would then
  stop meaning "SQLite said no", and the brief's name would move.
- **One coded base for everything.** Every field would be optional, and a load refusal would
  carry a code SQLite never returned.
- **Codes as integers only,** as SQLite gives them. Every caller would compare against magic
  numbers (chez-libuv ADR-0006).
- **An assertion violation for a closed connection.** A long-lived program that closes on one
  path and calls on another should be able to catch it by type.

## Consequences

- **`(chez-sqlite3)` exports one type, predicate and accessor set per condition.**
- **A subtype is only as stable as SQLite's codes.** They have been stable since extended codes
  arrived, and the table's suite records any that move.

## Amendment, 2026-11-14: what M1 slice 4 built

- **`(chez-sqlite3)` exports each condition's predicate and accessors,** not its `&…` type name and
  not its constructor, as the maintainer's list of public names has it. The consequence's "one
  type, predicate and accessor set per condition" is read so.
- **`sqlite-library-unavailable-library` is not exported in M1.** It would hand back a report no
  public accessor can read, and `below-floor`'s detail already carries the version. The
  maintainer approved leaving it unexported, 2026-11-14.
- **`code`'s type is `(U Symbol Integer)`.** Decision 4's "every primary code is named" holds for
  today's primaries; a future low byte the table doesn't name answers the integer.
- **Slice 4's refusals lead their irritants with a symbol naming the rule:** `not-a-string`,
  `unknown-option`, `option-given-twice`, `contradictory-options`,
  `file-uri-without-uri-option`, `not-a-database`, `untracked-statements`, `not-a-procedure` and
  the rest, and `register-exit-check!`'s after slice 4's review. Native's earlier refusals don't:
  `call-with-c-string`'s U+0000 refusal names the string by its kind alone, `((kind string))`.
  Each still differs from every other by its who or irritants, so decision 9 holds without
  reading a message.
- **`&sqlite-wrong-thread` and `&sqlite-closed` carry a fixed `&message`,** whose presence the rows
  assert, never its text.
- **`&sqlite-closed` can't be reached through the public surface in M1:** its one verb,
  `close-database!`, is a no-op on a closed connection. `test-connection` reaches it through the
  private `call-with-open-handle`, which M2's verbs use.

## Amendment, 2026-11-14: M2's conditions (M2's plan)

Accepted by the maintainer on 2026-11-14, proposed in M2 slice 0. The maintainer's own choices,
the same day ([the M2 plan](../2026-11-14-m2-plan.md), §3): `offset` in characters (Q6);
`&sqlite-invalid-text`, under the root, with the column's index and a byte offset (Q8); and
`&sqlite-closed` for a finalized statement (Q5).

- **The hierarchy, with M2's types:**

  ```
  &error
   └ &chez-sqlite3-error             no fields; every library condition is one
      ├ &sqlite-error                code, extended-code, message, sql, offset
      │   ├ &sqlite-busy             primary code busy or locked
      │   ├ &sqlite-constraint       primary code constraint
      │   └ &sqlite-read-only        primary code readonly
      ├ &sqlite-invalid-text         column, offset
      ├ &sqlite-library-unavailable  reason, path, source, detail, candidates, library
      ├ &sqlite-wrong-thread         owner, caller
      └ &sqlite-closed               no fields
  ```

- **The subtypes add no field.** The one procedure that makes a `&sqlite-error` classes it by its
  primary code (decision 8), so every raise gets its subtype, M1's open and close among them. The
  classing is a pure function, tested over every primary code, those that give no subtype too.
  `(chez-sqlite3)` exports `sqlite-busy?`, `sqlite-constraint?` and `sqlite-read-only?`.
- **`offset` counts characters** (Q6): an index into the `sql` field's string, converted from
  SQLite's byte offset, which measured 13 for a token at character 12, after an `é`
  ([research/m2-plan/](../research/m2-plan/)). SQLite's −1, which it answers for an error at the
  end of the SQL, gives `#f` ([research/m2-review/](../research/m2-review/)).
- **`sql` and `offset`, by where the failure came from**
  ([ADR-0014](0014-statements-belong-to-their-connection.md), [ADR-0015](0015-values.md)). This
  amends decision 3, whose `sql` came from prepare alone:
  - a failed prepare carries the SQL it was given and its offset;
  - **every other `&sqlite-error` a statement raises carries its statement's SQL and no offset:**
    a failed step; a reset or finalize that fails on its own; a bind SQLite refuses; a column read
    out of memory; `sqlite3_column_name` answering NULL; and the finalize failure
    `close-database!` raises, which carries the SQL of the statement whose finalize failed;
  - a connection's own failures, an open or a close, carry neither, as in M1.
- **`&sqlite-invalid-text`** (Q8) is raised for a TEXT value, or a column name, that isn't
  well-formed UTF-8 ([ADR-0015](0015-values.md), decision 9). Its fields are the column's index
  and the byte offset where the first ill-formed part starts, both naturals. It carries no bytes.
  It isn't a `&sqlite-error`: SQLite answered `SQLITE_OK`, and the subtype would carry a code it
  never returned. `(chez-sqlite3)` exports `sqlite-invalid-text?`, `sqlite-invalid-text-column`
  and `sqlite-invalid-text-offset`.
- **A finalized statement raises `&sqlite-closed`** (Q5), its `&who` naming the verb. So
  `&sqlite-closed` becomes reachable through the public surface, which M1's amendment found it
  wasn't. Its fixed `&message`, "the connection is closed" in M1, is reworded to cover a statement
  too; no row asserts its text (decision 9).
- **Decision 7's U+0000 rule is narrowed** to the strings SQLite reads to a NUL: a filename, SQL
  text, a parameter name. A bound string keeps its U+0000 (ADR-0011, amended).
- **M2's refusals of a caller's mistake are assertion violations** (decision 7): a value that can't
  bind, a parameter or column out of range, a verb its statement's state doesn't allow, SQL
  holding no statement or more than one.
