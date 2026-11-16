# ADR-0018: The settings list is an allowlist of Scheme values, set at every open and read back

- **Status:** Accepted (the maintainer, 2026-11-15), proposed in M3 slice 0. The maintainer's own choices, the same day
  ([the M3 plan](../2026-11-15-m3-plan.md), §3): decision 3's six settings, "Six" (Q8), and its
  seventh, `statement-cache`, "32, configurable" (Q11); decision 7's in-memory journal mode,
  "Mismatch, raise" (Q9); decision 8's busy timeout, "None, SQLite's 0" (Q10).
  `statement-cache`'s largest value, 1024, is the maintainer's too, "Cap at 1024" (Q13).
  Decision 5's waits are measured by slice 0's research (P2, P3, P14). Amended 2026-11-15 in M3
  slice 1, and accepted by the maintainer that day: what the settings argument is, the rules' names
  and order, a read-back with no row, and the readers' values
  ([amendment](#amendment-2026-11-15-what-m3-slice-1-settled)).
- **Date:** 2026-11-15
- **Scope:** chez-sqlite3 v1: `open-database`'s and `call-with-database`'s settings
- **Settles:** brief §2.7, moved to M3 (the maintainer, 2026-11-13); ADR-0012's consequence "M3's
  settings list arrives as an argument that isn't a symbol"
- **Related:** [ADR-0012](0012-explicit-close-and-the-handle.md) (the open) ·
  [ADR-0013](0013-errors-are-condition-types.md) (`&sqlite-setting-mismatch`) ·
  [ADR-0019](0019-interrupt-and-close.md) (the busy timeout) ·
  [ADR-0020](0020-the-statement-cache.md) (`statement-cache`) ·
  [research/m3-plan/](../research/m3-plan/README.md) · [the M3 plan](../2026-11-15-m3-plan.md), §4.3

## Context

- **Brief §2.7, settled by the maintainer:** PRAGMAs are SQL; opening takes a checked list of
  per-connection settings, run on every open, because `foreign_keys` and `busy_timeout` reset with
  each connection; a PRAGMA's value can't be a bound parameter, so each name and value is
  validated before it reaches SQL text; a setting is checked by reading its row back.
- **Measured** on Guix's 3.53.1 and at the floor, 3.45.1, alike but for `secure_delete`'s default
  (M3's research, "single" and "concurrency" its halves):
  - **reset by every new connection:** 25 settings, `foreign_keys`, `busy_timeout`, `synchronous`,
    `temp_store` and `trusted_schema` among them (single P1; concurrency S1, B1). **Kept in the
    file:** `journal_mode = wal`, `user_version`, `application_id` (single P1; concurrency B8).
    **Deferred to a VACUUM** once the file holds a table: `page_size`, `auto_vacuum`; **no effect
    there at all:** `encoding` (single P1, P12). **Process-wide:** the heap limits (single P2, T9);
  - **a bound parameter is a syntax error at prepare** (single P7; concurrency S2);
  - **SQLite never refuses a value or a name.** A word it doesn't know turns a boolean off;
    `synchronous = 4` is stored and read back as 4, no level of SQLite's; `temp_store = 7` gives
    0; `busy_timeout = 2147483648` and `-5` give 0, and `1e3` gives 1 (single P4; concurrency B1).
    `PRAGMA nosuch = 1` and the misspelt `PRAGMA foreign_key = ON` prepare and step, and do
    nothing (single P5, T4);
  - **a set can answer no row:** `foreign_keys = 1` answers none, so its row can't be read back
    from the set (concurrency S3; single P1). `busy_timeout`'s row is named `timeout`;
    `journal_mode` reads back lower-case TEXT, the others INTEGER (single P1, P8);
  - **most settings take effect at prepare,** never stepped (single P3);
  - **inside a transaction,** `foreign_keys = ON` does nothing and says nothing, `synchronous` is
    refused at prepare, and `journal_mode = wal` fails, or answers the old mode with no error once
    the transaction has written (single P6, T5; concurrency B8). **Beside the connection's own
    open SELECT,** `journal_mode = wal` fails (single P13);
  - **`journal_mode = wal` on `:memory:` answers `memory`,** every call succeeding; a temporary
    database, filename `""`, answers `delete` (single P11; concurrency S4);
  - **under another connection's `BEGIN EXCLUSIVE`,** a fresh connection's `busy_timeout` and
    `foreign_keys` run, while `PRAGMA journal_mode` and `PRAGMA synchronous` answer BUSY at
    prepare, with no busy timeout (concurrency B10);
  - **another connection's `journal_mode` can be stale** until its next read (concurrency B8,
    trap 5);
  - **with a 200 ms busy timeout set first on a fresh connection** (M3 slice 0's research, P2):
    under another's exclusive lock in rollback-journal mode, `PRAGMA journal_mode`,
    `journal_mode = wal`, both forms of `synchronous` and a SELECT waited it out at prepare, then
    answered BUSY, and `foreign_keys`, `temp_store`, `trusted_schema` and `busy_timeout` ran at
    once, both forms; under a read, `journal_mode = wal` waited it out at its step;
    `journal_mode = wal` under a reserved lock, and `journal_mode = delete` on a WAL file beside
    any other open connection, answered BUSY at once; in WAL mode nothing else waited. **When the
    other let go mid-wait, the waiting call succeeded,** 28.7 to 34.7 ms after the release,
    medians, which fits the busy handler's retry schedule read from the floor's source
    (concurrency B3), an inference (P3). **On a file already in WAL, `journal_mode = wal` ran at
    once and read back `wal`,** beside another's read, `BEGIN IMMEDIATE` or `BEGIN EXCLUSIVE`
    (P14).

## Decision

1. **The list is one argument among the options:** an association list from a setting's name, a
   symbol, to its value. At most one argument is a list; the options stay symbols (ADR-0012,
   decision 3):

   ```scheme
   ;; open-database : String (U Symbol Settings) ... -> Database
   ;; call-with-database : String (U Symbol Settings) ... (Database -> A ...) -> A ...
   ;; Settings = (Listof (Pairof Symbol Any))
   (open-database "app.db" '((journal-mode . wal) (foreign-keys . #t) (busy-timeout . 5000)))
   ```

2. **Checked with the options, before anything is allocated.** Each of these is an assertion
   violation from the procedure called, its irritants led by a symbol naming its rule (ADR-0013,
   decision 7, amended): a second list; a list that isn't an association list of symbols; a name
   the allowlist doesn't have; a name given twice; a value outside its setting's domain. A value is
   named by its kind if it is a string, as ADR-0013 has every refusal name one.
3. **The allowlist, and each value's domain:** six of SQLite's (Q8), and one of the library's
   own (Q11):

   | Setting | Scheme value | Written as | Read back as |
   |---|---|---|---|
   | `busy-timeout` | exact integer, 0 to 2³¹−1 ms | the integer | INTEGER, column `timeout` |
   | `foreign-keys` | `#t` or `#f` | `1` or `0` | INTEGER |
   | `journal-mode` | `delete`, `truncate`, `persist` or `wal` | the word | lower-case TEXT |
   | `synchronous` | `off`, `normal`, `full` or `extra` | `0` to `3` | INTEGER |
   | `temp-store` | `default`, `file` or `memory` | `0` to `2` | INTEGER |
   | `trusted-schema` | `#t` or `#f` | `1` or `0` | INTEGER |
   | `statement-cache` | exact integer, 0 to 1024; 32 when absent | not SQL | not read back |

   Each value is written as canonical SQL by the library, from these words and decimal integers
   alone, so no text of the caller's reaches SQL. `#t` and `#f` stand for on and off: a setting is
   no stored value, so ADR-0015's reasons for refusing them in a bind don't arise.
4. **Each of SQLite's six is set, then read back by a second statement, `PRAGMA name`, and
   compared** with the value written, by its setting's reader. A mismatch raises
   `&sqlite-setting-mismatch`, with the setting's name and the value asked for and the value read,
   as Scheme values (ADR-0013, amended).
   **`statement-cache` is the library's own:** the statement cache's capacity
   ([ADR-0020](0020-the-statement-cache.md)), 0 turning it off. SQLite never sees it, so it can't
   be coerced, and it isn't read back; it is checked in Scheme with the rest, and becomes the
   record's capacity when the record is made, before any PRAGMA runs. It sits in the list, not
   among the options, because a size is a number and the options stay symbols (decision 1).
5. **`busy-timeout` runs first,** then the rest in the list's order, each set and read back before
   the next is prepared, since a PRAGMA's prepare applies it. So a setting that a short lock holds
   up waits for it and succeeds when it is let go (P3); `docs/reference.md` names the two that
   failed at once with the 200 ms timeout measured (P2).
6. **The list runs at every open, and only there.** At open the connection has no statement and no
   transaction of its own, so neither can make a setting fail or do nothing. After open, a PRAGMA
   is SQL, run through `execute!`. The settings' statements never use the statement cache
   ([ADR-0020](0020-the-statement-cache.md)), so each is prepared once, and applied once.
7. **A setting that fails, or mismatches, closes the connection, then raises,** as a failed open
   closes its handle before it raises (ADR-0012, decision 4). A close that fails then is raised in
   its place, the connection left open and counted, as ADR-0012 has a failed close.
   `call-with-database` never calls its procedure. **`journal-mode` on an in-memory database is
   such a mismatch** (Q9).
8. **No setting is applied unasked:** a connection opened without `busy-timeout` keeps SQLite's 0
   (Q10).
9. **The read-back runs on the connection that set the value,** never another, whose
   `journal_mode` can be stale.

### Rejected

- **SQL text, checked by a parser of ours.** SQLite accepts any value and any name, so the
  library would check text it then hands on, tokenizing SQL in Scheme, which ADR-0014 avoids.
- **Trusting the set's own row.** `foreign_keys`' set has none.
- **The settings that aren't per connection,** each for its measured reason: `page_size` and
  `auto_vacuum` wait for a VACUUM, and a read-back straight after the set sees the old value;
  `encoding` does nothing on a file holding a table; `user_version` and `application_id` are the
  file's data; the heap limits are process-wide; `defer_foreign_keys` switches itself off after the
  next write; `case_sensitive_like` has no read form, so can't be checked.
- **`journal-mode`'s `memory` and `off` in v1:** no research measured them on a file, and a value
  accepted can't be withdrawn, where one refused can be loosened later.
- **Applying the list again after open,** a verb of its own. Beside the connection's own reader or
  inside its transaction, settings fail or do nothing; at open neither exists.
- **Setting the busy timeout through `sqlite3_busy_timeout`.** It and the PRAGMA are one setting,
  and only the PRAGMA can be read back (concurrency B1; ADR-0019).
- **Settings declined by the maintainer:** eleven or three of SQLite's (Q8); accepting `memory`,
  or refusing `journal-mode` before an in-memory open (Q9); a default busy timeout (Q10).
- **The cache's size as an open option, or a verb after open.** An option stays a symbol, and the
  list runs only at open, so the size is fixed with the record.

## Consequences

- **An open with settings costs two statements a setting,** each prepared, stepped and finalized:
  small beside the open.
- **Under another connection's lock, a setting can fail with `&sqlite-busy`,** closing the
  connection: after the busy timeout, or at once, with the 200 ms timeout measured, for
  `journal_mode = wal` beside another's reserved lock and for leaving WAL beside any other open
  connection (P2). Connections of a file already in WAL can each carry `(journal-mode . wal)`
  and open while the others hold locks (P14).
- **An open with settings runs statements in sections of their own,** so an engine can preempt
  between them. `open-database` holds no `dynamic-wind` around them, so an expiry suspends the open
  and its resume goes on; M3 slice 5 measures it at every fuel from 1 to 60, as ADR-0012's
  amendment measured the open alone. `call-with-database` doesn't survive an engine's preemption,
  as before.
- **A list that sets `journal-mode` can't open `:memory:`** (decision 7), and `docs/reference.md`
  says so.
- **`docs/reference.md` lists each setting,** its values, and that SQLite would have coerced or
  ignored what the list refuses.

## Amendment, 2026-11-15: what M3 slice 1 settled

Accepted by the maintainer on 2026-11-15 ("Accept all"), proposed in M3 slice 1, from its builders'
reports and its adversarial review (`(chez-sqlite3 private settings)`).

- **The settings list is any pair or `()` among open's arguments.** `()` is an empty list, so
  `(open-database f '())`, which M2 refused as `unknown-option ()`, is accepted once slice 5 wires
  the list, and `docs/reference.md` says so. A list of options, `'(read-only)`, is refused as
  `not-an-association-list`. Strings, numbers and booleans stay options, and stay `unknown-option`.
- **Decision 2's rules are named** `second-settings-list`, `not-an-association-list`,
  `unknown-setting`, `setting-given-twice` and `setting-out-of-domain`, each the irritants' first
  symbol. One domain rule covers every setting, its irritants the name and the value as
  `shown-value` shows it. The list's shape is checked whole first, then each entry left to right:
  its name, then a repeat, then its domain. A bad option against a bad setting is M3 slice 5's to
  order, and to test.
- **Decision 4's read-back is a row's value or no row.** No row is a mismatch, its actual `'()`,
  nothing read: builds that leave out the flag or pager PRAGMAs (`SQLITE_OMIT_FLAG_PRAGMAS`,
  `SQLITE_OMIT_FOREIGN_KEY`, `SQLITE_OMIT_PAGER_PRAGMAS`) answer none, by SQLite's pragma table,
  not measured. Without the rule a no-row read of `foreign-keys` set to `#f` matched (the slice's
  review).
- **The readers' values:** `journal-mode` reads its TEXT as a symbol, so on `:memory:` the actual
  is `memory`; an INTEGER outside a setting's table is the actual as read, as `synchronous`'s 4
  would be; `#t` and `#f` read from 1 and 0.
- **The allowlist's complement:** the floor's pragma table (`aPragmaName` in 3.45.1's amalgamation,
  78 names) and sqlite.org/pragma.html (74, read 2026-11-15) differ by six names. Slice 1's suite
  refuses their union.
- **Every engine row of M3 sweeps fuel from 1 until a fuel at which the call completes without
  expiring,** not to a fixed 60, and names that fuel. Slice 1's review modelled `with-transaction`
  and found its one window at fuels 138 to 174, past 60, and an open with settings can lie past 60
  too ([ADR-0017](0017-with-transaction-and-savepoints.md), amended).
