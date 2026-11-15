# ADR-0015: Values: what binds, what a column reads back, and what is refused

- **Status:** Accepted (the maintainer, 2026-11-14), proposed in M2 slice 0. The maintainer's own
  choices, the same day ([the M2 plan](../2026-11-14-m2-plan.md), §2 and §3): decision 3's
  refusal of `+nan.0` (D4); decision 4's refusal of `#t` and `#f` (D5); decision 9's named
  condition for TEXT that isn't UTF-8, with the column readable as bytes instead (D6), and its type
  and fields (Q8, in [ADR-0013](0013-errors-are-condition-types.md)'s amendment); and decision 10's
  `sql-null` as one value (Q7). The reasons given here were put to the maintainer, and accepted
  with the record. Amended 2026-11-14 in M2 slice 1, from its measurements and its review, and
  accepted by the maintainer that day ([amendment](#amendment-2026-11-14-what-m2-slice-1-measured)).
  Amended 2026-11-15 in M2's closing review, and accepted by the maintainer that day: what a big
  value costs, and the copies reworded
  ([amendment](#amendment-2026-11-15-what-m2s-closing-review-measured)). Amended 2026-11-15 in M2
  slice 4, and accepted by the maintainer that day: what it built and measured, and a NULL pointer
  told by its
  column's type ([amendment](#amendment-2026-11-15-what-m2-slice-4-built-and-measured)).
- **Date:** 2026-11-14
- **Scope:** chez-sqlite3 v1: every bound parameter and every column value
- **Settles:** brief §3f, D4, D5 and D6
- **Related:** [ADR-0011](0011-collect-safe-and-no-scheme-memory.md) (what crosses the FFI) ·
  [ADR-0013](0013-errors-are-condition-types.md) (`&sqlite-invalid-text`) ·
  [ADR-0014](0014-statements-belong-to-their-connection.md) (states and checks) ·
  [research/m2-plan/](../research/m2-plan/) and [research/m2-review/](../research/m2-review/)
  (the measurements) · [the assessment](../chez-sqlite-thunderchez-assessment.org)

## Context

- **SQLite has five storage classes,** INTEGER, REAL, TEXT, BLOB and NULL, and types values, not
  columns. A declared type is an affinity: a column declared `BOOLEAN` holds the text `'yes'` as
  TEXT (measured). SQLite has no boolean; its documentation says booleans are stored as the
  integers 0 and 1, and `TRUE` and `FALSE` are spellings of them.
- **Measured** on Guix's 3.53.1 and at the floor, 3.45.1 ([research/m2-plan/](../research/m2-plan/),
  [research/m2-review/](../research/m2-review/), and the brief's evidence):
  - `sqlite3_bind_double` with `+nan.0` stores NULL and answers `SQLITE_OK`, and every NaN is
    `eqv?` to `+nan.0`, whatever its bits;
  - Chez's `integer-64` wraps 2⁶³ to −2⁶³ and 2⁶⁴−1 to −1, both binding with `SQLITE_OK`, and
    raises its own error for 2⁶⁴ and −2⁶³−1;
  - a NULL pointer binds NULL, for text and for a blob, measured with length 0. SQLite's
    documentation for `sqlite3_bind_blob` says the length is then ignored;
  - a bind SQLite refuses, TOOBIG over a lowered length limit, leaves its parameter NULL, not the
    value bound before it;
  - `-0.0` comes back `0.0` from a REAL column, and `-0.0` through `select ?`;
  - SQLite stores bytes that aren't UTF-8 as TEXT: `cast(x'ff41' as text)` is TEXT;
  - an empty TEXT answers a non-NULL pointer through `sqlite3_column_text` and a NULL one through
    `sqlite3_column_blob`; an empty BLOB answers a NULL pointer, as SQLite's documentation for
    `sqlite3_column_blob` says. After a step answers a row, `sqlite3_errcode` is 100;
  - **in a UTF-16 database, `sqlite3_column_text` converts:** a lone surrogate comes out as
    `ED A0 80`, and `D800` then `A` as `F0 90 81 81`, valid UTF-8 for another character.
    `sqlite3_column_blob`, called first, gives the stored UTF-16 bytes;
  - Chez's `utf8->string` replaces invalid bytes with U+FFFD without raising.
- **A Chez string holds Unicode scalar values only** (R6RS), so `string->utf8` always gives valid
  UTF-8. Invalid TEXT comes only from what another program, or SQL itself, wrote.
- **SQLite's documentation for binding text says** that the result of expressions on strings with
  embedded NULs is undefined.
- **Thunderchez guessed booleans from a column's declared type and numbered parameters from 0.**
  The assessment lists both among what it does well; this project rejects both (decisions 6 and
  7).

## Decision

1. **A value is an exact integer, a flonum, a string, a bytevector or `sql-null`:**
   `Value = (U Integer Flonum String Bytevector SqlNull)`.
2. **Binding:**

   | Scheme value | Binds through | Refused |
   |---|---|---|
   | exact integer | `sqlite3_bind_int64` | outside −2⁶³ to 2⁶³−1 |
   | flonum | `sqlite3_bind_double` | `+nan.0` (decision 3) |
   | string | `sqlite3_bind_text64`, UTF-8, its byte length | — |
   | bytevector | `sqlite3_bind_blob64`, its length | — |
   | `sql-null` | `sqlite3_bind_null` | — |
   | `#t`, `#f` (decision 4), an exact non-integer, a complex, anything else | — | always |

   - A refusal is an assertion violation (ADR-0013, decision 7), its irritants led by a symbol
     naming its rule. It names the value by its kind, never its text, and the parameter by its
     index, or a name by its kind.
   - **The integer range is checked by us,** since Chez's `integer-64` wraps silently between 2⁶³
     and 2⁶⁴−1 (measured). Its boundary rows are 2⁶³−1 and −2⁶³ accepted, and 2⁶³, 2⁶⁴−1 and
     −2⁶³−1 refused, each asserting the rule's symbol: Chez's own error at 2⁶⁴ would pass a test
     that asserts only an assertion violation.
   - **A bind SQLite refuses** raises `&sqlite-error` from its own code, with `sqlite3_errmsg`
     read straight after, and the state stays `ready`. The parameter is then NULL (measured).
     The row lowers `SQLITE_LIMIT_LENGTH` and binds a value over 30 bytes: 3.53.1 clamps the limit
     to at least 30, and the floor doesn't (measured). `sqlite3_limit` isn't one of M2's entry
     points, so the suite binds it itself and reaches the handle through
     `call-with-open-handle`, as `test-connection` does for its backup.
3. **`+nan.0` is refused** (D4, the maintainer). SQLite would store NULL in its place, unasked.
   Every NaN is `eqv?` to it, so one check covers them all. `+inf.0` and `-inf.0` bind as REAL; a
   caller who means "missing" passes `sql-null`.
4. **`#t` and `#f` are refused** (D5, the maintainer). Callers pass 1 or 0. The reasons put to
   the maintainer: a read gives back 0, which is true in Scheme, and `#f` also means "not found"
   (`assq`, `member`), so accepting it would store 0 for "absent". A refusal can be loosened
   later; an acceptance can't be withdrawn.
5. **Strings and bytevectors are counted copies.** A string is encoded to UTF-8 and put in a
   counted block; a bytevector is copied into one (ADR-0011, decisions 1 and 2). (M2's closing
   review reworded this from "a string is copied": the code makes no copy of the string before
   it encodes it, which binding needs no check between.) Each is
   bound with its byte length, `SQLITE_UTF8` for text, and `SQLITE_TRANSIENT`, so SQLite makes its
   own copy, and the block is freed after the call on every path.
   - **A bound string keeps any U+0000 in it,** since its length is given. Brief §3f keeps a NUL
     when TEXT is read, and binding keeps it the same way. SQL on such a string is undefined, by
     SQLite's documentation, and `docs/reference.md` says so.
   - **An empty value still passes a non-NULL pointer:** the block holds at least one byte, since
     a NULL pointer binds NULL (measured).
6. **Parameters:**
   - **by index,** from 1 to `parameter-count`, checked before C; or **by name,** a string with its
     sigil (`":name"`), found with `sqlite3_bind_parameter_index`. The name is a C string, so one
     holding U+0000 is refused before anything is allocated (ADR-0011, amended), and a name no
     parameter has is an assertion violation.
   - **`bind!`** binds one; **`bind-all!`** binds every parameter, 1 to n, from n values. A count
     other than `parameter-count` is refused. Every value is checked before any is bound, so a
     refusal of ours binds nothing; a bind SQLite refuses midway leaves the parameters before it
     bound.
   - **`clear-bindings!`** calls `sqlite3_clear_bindings`, making every parameter NULL again.
   - Binding and clearing are allowed only in the `ready` state (ADR-0014, decision 5).

   ```scheme
   ;; bind! : Statement (U Positive-Integer String) Value -> Void
   ;; bind-all! : Statement Value ... -> Void
   ;; clear-bindings! : Statement -> Void
   ```
7. **Column values,** allowed only in the `row` state, at an index from 0 below the column count
   (ADR-0014, decision 5):

   | `sqlite3_column_type` | Read through | Gives |
   |---|---|---|
   | INTEGER | `sqlite3_column_int64` | an exact integer |
   | FLOAT | `sqlite3_column_double` | a flonum |
   | TEXT | `sqlite3_column_text`, then `sqlite3_column_bytes` | a string, decoded strictly (decision 9) |
   | BLOB | `sqlite3_column_blob`, then `sqlite3_column_bytes` | a new bytevector |
   | NULL | — | `sql-null` |

   - **The declared type is never read** (brief §3f). A column declared `BOOLEAN` reads back 1 and
     0.
   - **The type is read first, then the matching accessor.** In a UTF-8 database SQLite converts
     nothing then. TEXT and BLOB are read as a pointer, then a byte count, in the order SQLite's
     documentation gives, and copied out by our code (ADR-0011, decision 4). An embedded NUL
     survives.
   - **A NULL pointer:** `sqlite3_errcode` is read at once, before any other call. `SQLITE_NOMEM`
     raises `&sqlite-error`; any other code means an empty value, as an empty BLOB answers
     (measured). Running out of memory can't be caused on demand, so this reader is a pure
     function of what the bindings answer, tested with stand-ins, as M1's `failure-details` is.
     Both halves were corrected in slice 4: the code can be another statement's, so the column's
     type is read too, and running out of memory is caused for real by a suite (the slice 4
     amendment).
   - **A UTF-16 database:** `sqlite3_column_text` converts its text to UTF-8 (measured), so decision
     9's check holds the converted bytes. Some invalid UTF-16 converts to valid UTF-8 for another
     character, which the check can't see. `docs/reference.md` says the check guards UTF-8
     databases.

   ```scheme
   ;; column-value : Statement Natural -> Value
   ;; column-bytevector : Statement Natural -> (U Bytevector SqlNull)
   ```
8. **`column-bytevector` reads a TEXT or BLOB value's bytes, undecoded:** D6's way to read text
   that isn't UTF-8. It reads TEXT through `sqlite3_column_text`, as decision 7 does, never
   `sqlite3_column_blob`, which answers NULL for an empty TEXT and the stored UTF-16 in a UTF-16
   database (measured). So it gives the bytes a TEXT value decodes from. NULL gives `sql-null`; an
   INTEGER or FLOAT value is an assertion violation.
9. **TEXT is decoded strictly** (D6, the maintainer). A value that isn't well-formed UTF-8, by
   Unicode's table of well-formed byte sequences, raises `&sqlite-invalid-text` (ADR-0013,
   amended), with the column's index and an offset:
   - **The ill-formed forms:** a continuation byte with no lead; a lead byte followed by a byte
     that doesn't continue it, or by the end; an overlong form (`C0`, `C1`, `E0` then `80`–`9F`,
     `F0` then `80`–`8F`); a surrogate (`ED` then `A0`–`BF`); a code point above U+10FFFF (`F4`
     then `90`–`BF`, or `F5`–`FF`). U+0000 is well-formed and kept.
   - **The offset is the byte where the first maximal ill-formed subpart starts** (Unicode §3.9),
     where Python's decoder reports it too: 0 for `E0 80 80`, for `C2 41` and for a final `E1 80`.
   - **Tested exhaustively** on every 1- and 2-byte input, and at each 3- and 4-byte form's range
     edges, at every position in a longer value (AGENTS.md).
   - **`column-name` decodes its name the same way,** and raises the same condition with the
     column's index. A name has no bytes reader.
   - **`sqlite3_column_name` answering NULL** means an allocation failed, by SQLite's
     documentation, and SQLite sets no error code for it: its `columnName` clears its
     out-of-memory flag and returns NULL (the floor's source,
     [research/m2-review/](../research/m2-review/)). So `sqlite3_errcode` and `sqlite3_errmsg`
     would be stale. It raises `&sqlite-error` with the code `nomem` and the message
     `sqlite3_errstr` gives for it: SQLite did fail, out of memory, though it returned no code. The
     index is in range by then (ADR-0014, decision 5). The path is part of decision 7's pure
     reader, tested with stand-ins.
10. **`sql-null` is one value** (Q7, the maintainer): the only instance of an opaque, sealed record
    type, made once by its library, compared with `eq?` and tested with `sql-null?`.

    ```scheme
    ;; sql-null : SqlNull
    ;; sql-null? : Any -> Boolean
    ```

### Rejected

- **Storing `+nan.0` as NULL,** as SQLite does (D4).
- **Binding `#t` as 1 and `#f` as 0** (D5), and a boolean column read beside it. The read is held
  as a possible loosening for later, perhaps with M3's conveniences.
- **U+FFFD for invalid bytes** (D6): reading a value and writing it back would change it.
  **Answering a bytevector for invalid TEXT:** a column's Scheme type would then depend on its
  bytes.
- **Guessing a type from the declared type,** as Thunderchez does for booleans.
- **Binding symbols or characters as TEXT, or exact fractions as REAL:** each is a guess at what
  the caller meant.
- **Reading TEXT through `sqlite3_column_blob`:** an empty TEXT answers NULL there (measured).
- **A procedure, `(sql-null)`** (Q7).

## Consequences

- **`-0.0` comes back `0.0` from a REAL column** (measured), and `docs/reference.md` says so.
- **A bound string is copied three times by our code:** encoded into a fresh bytevector by
  `string->utf8`, copied again by `call-with-bytes`, and written into the block. SQLite then makes
  its own copy. Each byte is copied in Scheme, with this thread's interrupts off: about 2 s for
  64 MiB (M2's closing review, amended).
- **Every TEXT read is checked byte by byte.** Slice 1 measures the cost against `utf8->string`.
- **A program reading a database other programs wrote may meet `&sqlite-invalid-text`,** and
  reads the column with `column-bytevector` instead.
- **`sqlite-error-offset` counts characters and `sqlite-invalid-text-offset` counts bytes,** and
  `docs/reference.md` says which is which.
- **Three guards of our own are each watched failing against a planted copy,** though they aren't
  defects the assessment lists: integers bound or read through `int`, booleans guessed from a
  declared type, and parameters numbered from 0.

## Amendment, 2026-11-14: what M2 slice 1 measured

Accepted by the maintainer on 2026-11-14 ("Accept it"), proposed in M2 slice 1, from its build and
its Opus review. None of it changes a choice of the maintainer's; each item corrects what the record says
the code reads, or adds a measurement.

- **Chez's `utf8->string` drops one leading U+FEFF,** besides replacing invalid bytes with U+FFFD
  (measured on Chez 10.4.0, M2 slice 1's review). `EF BB BF 69 64` decodes to `"id"`, and
  `EF BB BF` alone to `""`. A U+FEFF anywhere else survives, and of two leading ones only the first
  is dropped. Decision 9's strict decoder put a value through `utf8->string` once it was checked,
  so a TEXT value or a column name starting with U+FEFF read back changed, which decision 9 exists
  to prevent. The decoder now restores it, and a round trip of every scalar value holds it.
- **Decision 7's code is read through `sqlite3_extended_errcode`,** not `sqlite3_errcode`. M1
  binds both (ADR-0002, amended). A connection opens with `SQLITE_OPEN_EXRESCODE`, so both would
  answer the extended code, but only `sqlite3_extended_errcode` answers it whatever the open's
  flags. `(nomem CODE MESSAGE)` carries it to `raise-sqlite-error`, which takes an extended code.
  As first written, this bullet said M1 doesn't bind `sqlite3_errcode`. M1 slice 2 does; the
  reason was corrected before slice 1 merged, and the decision is unchanged.
- **The reader reads the message too:** on `SQLITE_NOMEM` it calls `sqlite3_errmsg` straight after
  the code and answers `(nomem CODE MESSAGE)`, so the order decision 7 asks for lives inside the
  reader its stand-ins test, not in the slice 4 code around it.
- **The strict check's cost,** measured against `utf8->string` (median of 5 runs, in the
  container, not under Valgrind): 1.52 times for 1 MiB of ASCII, 1.76 for 1 MiB of mixed 2-, 3- and
  4-byte text, and 2.32 for 100,000 values of 16 bytes. That is about 1.5 ms per MiB, and under
  25 ns per short value, so TEXT stays checked byte by byte, as the Consequences say
  ([research/m2-slice-1/](../research/m2-slice-1/)).
- **Chez shares its empty bytevector:** `(eq? (make-bytevector 0 0) (make-bytevector 0 0))` is
  `#t` on 10.4.0. So "a fresh empty bytevector" can't be told from a shared one, and only
  non-empty plans and reads are held fresh.

## Amendment, 2026-11-15: what M2 slice 4 built and measured

Accepted by the maintainer on 2026-11-15 ("Accept it"), proposed in M2 slice 4, from its build, its
Opus review and the research the M1 session measured for it
([research/m2-slice-4/](../research/m2-slice-4/)). None of it changes a choice of the maintainer's. Measured on Guix's 3.53.1 and at the floor,
3.45.1, alike, unless a line says otherwise.

- **Decision 7's NULL pointer is told by the column's type as well as the code.**
  - **What went wrong:** the slice's review found it. An empty BLOB answers a NULL pointer and sets
    no code, so `sqlite3_extended_errcode` answers the connection's last code. After another
    statement's NOMEM on the same connection, a read or a bind, that is 7. A healthy statement's
    empty-BLOB read then raised `nomem` and moved to `failed`. Its raw read gave a NULL pointer,
    code 7, and its column still BLOB.
  - **Measured:** a real NOMEM read turns its column's type to NULL. Through `sqlite3_column_text`
    on TEXT, the code is 7, then the type 5, and reading the type changes neither the code nor the
    message. Through `sqlite3_column_blob`, a zeroblob bound with `sqlite3_bind_zeroblob64` gives
    the same 7, then 5 ([stale-code.sps](../research/m2-slice-4/stale-code.sps)).
  - **So, on a NULL pointer:** read the code. If its low byte isn't 7, the value is empty. If it
    is 7, read `sqlite3_column_type` again: only a type turned NULL is NOMEM, and then
    `sqlite3_errmsg` is read. Any other type is an empty value, and the 7 another statement's.
    Slice 1's `read-column-bytes` takes the type as a procedure, between the code and the message.
- **Running out of memory is caused for real,** where decisions 7 and 9 and the plan's §4.4 said it
  couldn't be:
  - a suite binds `sqlite3_hard_heap_limit64` itself, and sets it just above the memory used,
    around the one read. A TEXT bigger than lookaside then answers NOMEM through
    `sqlite3_column_text`;
  - after the suite's own `sqlite3_column_name16`, under the limit, `sqlite3_column_name` answers
    NULL with the code unchanged, so `column-name`'s path is held on a real library too;
  - where SQLite keeps no memory count (`SQLITE_CONFIG_MEMSTATUS` 0, as Apple's library has it),
    the limit reads back but isn't enforced. Those rows report themselves unavailable.
- **The maintainer's NOMEM choice is built** (ADR-0014's slice 3 amendment): a value read's NOMEM
  moves the statement to `failed`, raised once. Inside a transaction, the next reset rolls the
  transaction back for a statement that reads a table. `column-name`'s NOMEM leaves the state,
  since `sqlite3_column_name`'s NULL sets no code on the statement.
- **Decision 2's limit, refined:** at `SQLITE_LIMIT_LENGTH`, 3.53.1 raises any value from 0 to 30
  up to 30, and the floor raises 0 to 1 and keeps every value from 1. So "the floor doesn't" means
  it doesn't clamp to 30. The limit also holds column names at prepare: a refused-bind row
  prepares before it lowers the limit.
- **A refused bind leaves its own code and message,** `sqlite3_errstr` of its code exactly, never
  a stale one. So its `&sqlite-error` reads `sqlite3_errmsg` straight after the bind.
- **Decision 6's names are byte-exact:** a name is its bytes as the SQL writes them, sigil
  included, and case matters. `?32766` is the largest numbered parameter, which is
  `SQLITE_LIMIT_VARIABLE_NUMBER` on both libraries.
- **Built:** `(chez-sqlite3 private statement-values)`, with the six verbs. Native's three byte
  helpers, `call-with-bytes`, `foreign-bytes` and `c-string->bytevector`, are there because
  native alone touches foreign memory (ADR-0011). Slice 1's readers took copy procedures that no
  slice had been given, and the builder's brief had put native off limits; the builder stopped
  and said so.

## Amendment, 2026-11-15: what M2's closing review measured

Accepted by the maintainer on 2026-11-15 ("Accept it"), proposed in M2's closing review. It changes no
choice of the maintainer's.

- **Big values are copied byte by byte, with this thread's interrupts off.** A 64 MiB BLOB's
  `column-value` took 1932 ms, and a 64 MiB `bind!` 2000 ms, about 30 ns a byte. Under an engine
  the read ran with no expiry in 1.8 s, against 64,000 for a plain loop as long. Another thread's
  `collect-rendezvous` wasn't held: 0 to 7 ms. So a keyboard interrupt, a timer or an engine waits
  out a big copy, and `docs/reference.md` says so, where it says the blocking calls hold them. The
  probes are the review's, `big-read-section.sps` and `big-read-engine.sps`.
- **Decision 5's copies are reworded** to the ones the code makes: `string->utf8`, then
  `call-with-bytes`' copy, then the block's fill. There is no `string-copy`.
- **M3's row reading follows this:** each value in a section of its own (M3's plan, Q15), so no
  section holds a whole row's copies.
