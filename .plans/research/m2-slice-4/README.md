# What M2 slice 4's research measured

Measured 2026-11-15 in the Guix container (Chez 10.4.0, gcc 16.2.0), through bare FFI and, for
running out of memory, C, on two libraries:

- **Guix's 3.53.1,** the container's own `CHEZ_SQLITE3_LIBRARY`, source id
  `2026-05-05 10:34:17 c88b2201…7127e9` (`…-guix-3.53.1.txt`);
- **the floor, 3.45.1,** `build/m2s4-floor/libsqlite3-floor.so`, compiled with
  `$CC -shared -fPIC -O1 -DSQLITE_THREADSAFE=1` from the 3.45.1 amalgamation beside it, source id
  `2024-01-30 16:01:20 e876e51a…c467a` (`…-floor-3.45.1.txt`).

Every output prints `sqlite3_libversion()` and `sqlite3_sourceid()` as read at run time. The C
probes are compiled against the matching `sqlite3.h`, linked to that `.so`, refuse to run unless
the library's version number and source id are the header's, and name the file that answered
(`dladdr` of the source id's text). Every probe ran at least three times on each library. The last
two runs were compared byte for byte (`build/m2s4/rerun.sh`, scratch), and matched. No probe calls
into documented undefined behaviour:
- a value's length never exceeds its buffer. The 2³¹- and 2³²+1-byte values are an anonymous
  `MAP_NORESERVE` mapping of that size;
- a pointer is read only before any call that can invalidate it. A column's pointer is read, then
  `sqlite3_column_bytes`, then the bytes, in the order SQLite documents.

## Rerunning

From the worktree's root. Each Scheme probe, on each library:

```
$ scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-slice-4/PROBE.sps'
$ scripts/guix-env sh -c 'CHEZ_SQLITE3_LIBRARY=$PWD/build/m2s4-floor/libsqlite3-floor.so \
    $CHEZ --script .plans/research/m2-slice-4/PROBE.sps'
```

where PROBE is `bind-errors`, `limit-length`, `parameters`, `column-names`, `embedded-nul`,
`sweep`, `trap-stale-offset`, `trap-first-prepare-offset` or `trap-limit-names`. `bind-errors`
maps memory with Linux's flags. The C probes (`trap-oom-reread.c` the same way, without `-ldl`
and the argument):

```
$ scripts/guix-env sh -c '$CC -O1 -Wall -Werror -I$GUIX_ENVIRONMENT/include \
    -o build/m2s4/oom-guix .plans/research/m2-slice-4/oom.c \
    $GUIX_ENVIRONMENT/lib/libsqlite3.so.0 -Wl,-rpath,$GUIX_ENVIRONMENT/lib -ldl \
    && build/m2s4/oom-guix && build/m2s4/oom-guix lookaside-default'
$ scripts/guix-env sh -c '$CC -O1 -Wall -Werror -Ibuild/m2s4-floor/sqlite-amalgamation-3450100 \
    -o build/m2s4/oom-floor .plans/research/m2-slice-4/oom.c \
    $PWD/build/m2s4-floor/libsqlite3-floor.so -ldl \
    && build/m2s4/oom-floor && build/m2s4/oom-floor lookaside-default'
```

`heap-limit.c` was added in review, by the session that briefed these probes. Its compile lines
are in its header comment; run each binary with no argument and with `memstatus-off`. It ran
twice per library and mode, and the runs matched byte for byte.

## Every difference between the two libraries

Apart from the lines that name the library (the version and source id, and in the C probes the
header's and the library file's), the outputs differ in these places alone. `diff` of every other
pair shows only those lines.

1. **The smallest `SQLITE_LIMIT_LENGTH` kept:** 30 on 3.53.1, which keeps 30 for every n from 0
   to 30. The floor keeps 1, raising 0 to 1 (`limit-length`). So at the floor, a limit of 1
   refuses to prepare `select ?1`, whose column name is 2 bytes, and 3.53.1 prepares it
   (`limit-length`, `trap-limit-names`).
2. **A `?NNN` out of range at the very end of the SQL, as a connection's first prepare:** 3.53.1
   answers `sqlite3_error_offset` −1, and 7 for the same SQL prepared again. The floor answers 7
   both times (`parameters`, `trap-first-prepare-offset`).
3. **The builds:** 46 compile options against 37. Only 3.53.1's lists `ENABLE_COLUMN_METADATA`,
   `ENABLE_DBSTAT_VTAB`, `ENABLE_FTS3`/`4`/`5`, `ENABLE_MATH_FUNCTIONS`, `ENABLE_PERCENTILE`,
   `ENABLE_UNLOCK_NOTIFY` and `SECURE_DELETE`. `COMPILER` is `gcc-14.3.0` against `gcc-16.2.0`.
   `MAX_FUNCTION_ARG` is 1000 against 127, so limit
   id 6 reads 1000 against 127. Limit id 12 (3.53.1's new `SQLITE_LIMIT_PARSER_DEPTH`) reads 2500
   there, and −1 (no such limit) at the floor. `MAX_LENGTH` and `MAX_SQL_LENGTH` (1,000,000,000)
   and `MAX_VARIABLE_NUMBER` (32766) are the same (`limit-length`).

## 1. A refused bind's error state ([bind-errors.sps](bind-errors.sps))

Each of 81 rows opens a connection with `SQLITE_OPEN_EXRESCODE` and prepares
`select ?1, typeof(?1), ?2, typeof(?2)`. It binds `?1` to `'old'` and `?2` to 42, then puts a
control on the connection: none, a failed prepare (`select nosuch_col`: code 1, its own message,
offset 7), or a successful prepare (`select 1`: code 0, "not an error"). Then the refused bind,
then a read of the state, then a step (after a reset, where a row was ready) and a read of both
parameters. **Both libraries answered the same in every row:**

| Refusal | Answer | After it: errcode, extended, errmsg | `?1` | `?2` |
|---|---|---|---|---|
| `text64` and `blob64`: 101 bytes over a limit of 100; 2³¹ and 2³²+1 mapped bytes at a limit of 100 and at the default (10⁹) | 18 | 18, 18, "string or blob too big" | NULL | 42 |
| index 0 and index 3 (of 2), by each of `text64`, `blob64`, `int64`, `double` and `null` | 25 | 25, 25, "column index out of range" | `'old'` | 42 |
| `?1` while a row is ready, by each of the five; and after done, before a reset, by `text64` and `int64` | 21 | 21, 21, "bad parameter or other API misuse" | `'old'` (reset 0) | 42 |

- **The connection holds the bind's own failure, never a stale one.** Before the bind it held
  1/"no such column: nosuch_col", 0/"not an error", or what the last call left: 0 after a bind,
  100 after a row, 101 after done. After the bind, every row held the bind's code and message.
- **The message is exactly `sqlite3_errstr` of the code,** with no detail. The extended code is the
  primary code for all three.
- **`sqlite3_error_offset` is stale** (a trap, below). After the failed-prepare control, all 27
  rows still answered 7 after the refused bind; every other row answered −1.
- **A refusal touches no other parameter.** In every row `?2` kept 42. TOOBIG leaves the refused
  parameter NULL; RANGE and MISUSE leave it as it was. In `bind-all!`'s order, `?1` bound
  `"first"` and then `?2` refused: `?1` kept `"first"` and `?2` was NULL.
- **On one connection, RANGE, then TOOBIG, then a clean bind,** each call left its own state, and
  the clean bind left 0, "not an error", −1.

So a refused bind's `&sqlite-error` can take its code from the bind's answer and its message from
`sqlite3_errmsg` read straight after. It must not take `sqlite3_error_offset`.

## 2. `sqlite3_limit(db, SQLITE_LIMIT_LENGTH, n)` ([limit-length.sps](limit-length.sps))

| n set on a fresh connection | answered (the old value) | then reads, 3.53.1 | then reads, the floor |
|---|---|---|---|
| −2³¹, −2, −1 | 10⁹ | 10⁹ (unchanged) | 10⁹ (unchanged) |
| 0 | 10⁹ | 30 | 1 |
| 1, 2, 10, 29 | 10⁹ | 30 | n |
| 30, 31, 32, 100, 1000, 999,999,999, 10⁹ | 10⁹ | n | n |
| 10⁹+1, 2³¹−1 | 10⁹ | 10⁹ (the hard maximum) | 10⁹ |

- **The smallest value kept as itself,** scanning n from 0 to 64: **30 on 3.53.1, 1 at the
  floor.** On one connection, setting 500, then 50, then 5 answered 10⁹, 500, 50, then read 30 on
  3.53.1 and 5 at the floor. A call always answers the value before it. `SQL_LENGTH` stayed 10⁹
  whatever `LENGTH` was set to.
- **Binds at the smallest kept limit** (statement `select ?`, its column named `?`, 1 byte):
  - on 3.53.1 at 30, TEXT and BLOB of 29 and 30 bytes bound (0) and read back with that many
    bytes. At 31 bytes
    the bind answered 18 and the value read NULL;
  - at the floor at 1, 0 and 1 bytes bound, and 2 bytes answered 18.
  - At 30 and at 100, both libraries agree: L−1 and L bind, and L+1 answers 18.
- **The limit holds a statement's column names at prepare,** on both, at 30 (a trap, below):
  - an alias of 30 bytes prepares, and one of 31 answers 18 at prepare;
  - `select '<28 a's>'`, whose name is its 30-byte text, prepares, and `select '<29 a's>'`
    answers 18;
  - a 31-byte literal under the alias `x` prepares, and its step answers 18;
  - a 117-byte SQL with a long comment prepares and steps. `select ?1` prepares and steps.

## 3. Parameters ([parameters.sps](parameters.sps))

Identical on both, apart from difference 2 above. A name is the bytes as written, sigil included.
An anonymous `?` has no name (NULL), nor has index 0 or count+1. A lookup answers 0 unless the name
is exactly a parameter's, byte for byte.

| SQL | count | names, by index | lookups |
|---|---|---|---|
| `select ?, ?5, :name, @name, $name` | 8 | 1–4 NULL, 5 `?5`, 6 `:name`, 7 `@name`, 8 `$name` | `?5` 5, `:name` 6, `@name` 7, `$name` 8; `?`, `?1`, `?6`, `name`, `:NAME`, `""`, `:` 0 |
| `select :a, @a, $a` | 3 | `:a`, `@a`, `$a` | 1, 2, 3; `a` 0 |
| `select :a, :a, @a, :a` | 2 | `:a`, `@a` | `:a` 1, `@a` 2 |
| `select ?1, ?1, ?2` | 2 | `?1`, `?2` | 1, 2 |
| `select :a, ?1` | 1 | `:a` | `:a` 1, **`?1` 0** |
| `select ?1, :a` | 2 | `?1`, `:a` | `?1` 1, `:a` 2, `?2` 0 |
| `select ?2, :a` | 3 | NULL, `?2`, `:a` | `?2` 2, `:a` 3, `?1` 0, `?3` 0 |
| `select ?0005, ?5` | 5 | 1–4 NULL, 5 `?0005` | `?0005` 5, **`?5` 0**, `?05` 0 |
| `select :1, ?1` | 1 | `:1` | `:1` 1, `?1` 0 |
| `select :a, :A` | 2 | `:a`, `:A` | 1, 2: case counts |
| `select :é, @名前, $π` | 3 | `3A C3 A9`, `40 E5 90 8D E5 89 8D`, `24 CF 80` | each by its bytes; `:É` (`3A C3 89`) 0, `:e` + U+0301 (`3A 65 CC 81`) 0 |
| `select :a<FEFF>b, :<FEFF>a` | 2 | `3A 61 EF BB BF 62`, `3A EF BB BF 61` | each by its bytes; `:ab` 0, `:a` 0 |
| `select <FEFF>:a` | 1 | `:a` (the U+FEFF before the sigil is whitespace) | `:a` 1, `EF BB BF 3A 61` 0 |
| `select $a::b, $c(xy)` | 2 | `$a::b`, `$c(xy)` | 1, 2; `$a` 0, `$c` 0 |
| `select $c(x y)` | — | prepare 1, `unrecognized token: "$c(x"` | — |
| `select ?` | 1 | NULL | `?`, `""`, `?1` 0 |
| `select 1` | 0 | — | `:a`, `""` 0 |

- **The largest `?NNN`:** `SQLITE_LIMIT_VARIABLE_NUMBER` reads 32766 on both.
  - `select ?32766` prepares, with count 32766. A bind at 32766 answers 0, and at 32767 it answers
    25.
  - `select ?32767` is the first refused: code 1, "variable number must be between ?1 and ?32766".
    `?0`, `?00`, `?2147483648` and `?99999999999999999999` answer the same.
- **Setting the limit higher keeps 32766. Lowering it moves the boundary:**
  - at 10, `?10` prepares, and `?11` answers "variable number must be between ?1 and ?10". Ten
    anonymous or named parameters prepare, and eleven answer "too many SQL variables";
  - at 1, the same at 1 and 2;
  - 0 is kept, with no minimum: then even `?1` is refused ("…between ?1 and ?0"), and one `?`
    answers "too many SQL variables".
- Slice 2's `select :alpha, ?7, $beta`, 8 parameters at 1, 7 and 8 ([progress.md](../../progress.md),
  line 75), agrees.

## 4. Column names ([column-names.sps](column-names.sps))

Identical on both. Every name is read as raw bytes.

| SQL | count | names |
|---|---|---|
| `select 1+1, 1 + 1, (1+1)` | 3 | `1+1`, `1 + 1`, `(1+1)`: the expression's text as written |
| `select x'00', 'a' \|\| 'b', -  1` | 3 | `x'00'`, `'a' \|\| 'b'`, `-  1` |
| `select a from t` | 1 | `a` |
| `select * from t` (columns `a`, `"b c"`, `"é"`, `"<FEFF>x"`) | 4 | `61`, `62 20 63`, `C3 A9`, `EF BB BF 78` |
| `select 1 as "é名"`, and bare `é名` | 1 | `C3 A9 E5 90 8D` both |
| `select 1 as "<FEFF>id"` | 1 | `EF BB BF 69 64` |
| `select 1 as <FEFF>id`, bare | 1 | **`69 64`**: a bare U+FEFF is whitespace (slice 1) |
| `select 1 as "a<FEFF>b"`, and bare `a<FEFF>b` | 1 | `61 EF BB BF 62` both |
| `select 1 as a, 2 as a`; `select a, a from t` | 2 | `a`, `a` |
| `select * from t, t as x` | 8 | t's four names, twice |
| `select 1 as "a""b"`; `select 1 as 'lit'` | 1 | `a"b`; `lit` |
| `select 1 as "<FF>"`, raw SQL bytes | 1 | `FF` |
| `select * from u`, u's column created from raw bytes as `"<FF>"` | 1 | `FF` |

- **The pointer and the bytes stay the same** after prepare, a step, a reset and a second step, in
  all 18 cases, a step that answered done among them. After a reprepare they don't: with another
  statement adding a column between prepare and step, the count went from 1 to 2, and column 0's
  pointer changed. (The old pointer was compared as an integer and never read.)
- **A name that isn't UTF-8 is reachable through valid SQL:** `select * from u`, all ASCII, names
  `FF` once u was made from raw bytes. So slice 4 can reach `column-name`'s `&sqlite-invalid-text`
  through the public prepare, after making the table with a raw FFI connection.

## 5. TEXT holding U+0000 ([embedded-nul.sps](embedded-nul.sps))

Bound with `sqlite3_bind_text64` or `sqlite3_bind_blob64` and its length. Each way was read on its
own step, from a table's row and straight through `select ?1`, with the same answers. Identical on
both libraries:

| Value | `column_type` | `column_text`, then `column_bytes` | `strlen` | `column_blob`, then `column_bytes` | `length()` | `octet_length()` | `typeof()` |
|---|---|---|---|---|---|---|---|
| TEXT `61 00 62` | 3 | 3: `61 00 62` | 1 | 3: `61 00 62` | 1 | 3 | text |
| TEXT `00` | 3 | 1: `00` | 0 | 1 | 0 | 1 | text |
| TEXT `61 62 00` | 3 | 3 | 2 | 3 | 2 | 3 | text |
| TEXT `00 61 62` | 3 | 3 | 0 | 3 | 0 | 3 | text |
| TEXT `C3 A9 00 E2 82 AC` | 3 | 6 | 2 | 6 | 1 | 6 | text |
| BLOB `61 00 62` | 4 | 3 | 1 | 3 | 3 | 3 | blob |
| BLOB `00` | 4 | 1 | 0 | 1 | 1 | 1 | blob |

- `column_bytes` counts every byte. `strlen` stops at the first NUL, and so does `length()`, in
  characters. The byte at `[column_bytes]` of `column_text`'s pointer is 0 in every row. `hex()`
  gives every byte.
- **After `column_text` on a BLOB, `column_type` answers 3, TEXT.** The headers say the type is
  undefined after a conversion (3.53.1's `sqlite3.h` lines 5425–5427, the floor's 5100–5102), so
  ADR-0015's "the type first" is what keeps the reads right.

## 6. The sweep ([sweep.sps](sweep.sps), [oom.c](oom.c))

Every statement of SQLite behaviour in the M2 plan's §4.3 and §4.4 and in ADR-0015, with where it
stands. "Plan" is `.plans/2026-11-14-m2-plan.md`; "ADR" is `.plans/decisions/0015-values.md`.

| Claim | Where | Status |
|---|---|---|
| Chez's `integer-64` wraps 2⁶³ and 2⁶⁴−1; raises at 2⁶⁴ and −2⁶³−1, an assertion violation | plan 211–212; ADR 30–31, 71–74 | measured before: m2-review probes 2 C, 3 K |
| a bind SQLite refuses leaves its parameter NULL | plan 214–215; ADR 34–35, 75–76 | measured before (m2-review probe 3 J) and here, item 1 |
| a refusal midway leaves the parameters before it bound | plan 215–216; ADR 102–105 | measured here, item 1 |
| a refused bind's message is `sqlite3_errmsg` read straight after | ADR 75–76 | measured here, item 1: fresh, equal to `errstr` |
| `SQLITE_TRANSIENT` makes SQLite copy a bound value | plan 217–218; ADR 88–91 | measured before: `tests/test-native.sps` 826, 833 |
| a counted string keeps a U+0000; "an embedded NUL survives" | plan 218–219, 233–234; ADR 92–93, 128–130 | measured before (`test-native.sps` 717) and here, item 5 |
| SQL on a string holding a NUL is undefined, by SQLite's documentation | ADR 47–48, 93–94 | documentation, in both headers (3.53.1 lines 4935, 6522; floor 4617, 6134). Undefined isn't measurable; item 5 records what four functions answer on these builds |
| a NULL pointer binds NULL (length 0); the documentation says the length is then ignored | plan 221–222; ADR 32–33, 95–96 | measured before at length 0 (m2-plan 3); measured here at 5 and at 101 over a limit of 100 (S6): NULL, `SQLITE_OK` |
| `-0.0` comes back `0.0` from a REAL column | plan 223–224; ADR 36, 194 | measured before: m2-plan 4 |
| NaN binds NULL with `SQLITE_OK`; every NaN is `eqv?` to `+nan.0` | ADR 28–29, 81 | measured before: m2-review probes 2 D, 3 I |
| the type comes from `column_type`; a column declared BOOLEAN reads back 1 and 0 | plan 228–230; ADR 125–126 | measured here (S1): TRUE, FALSE, 1, 0, '1', '0', 1.0 and 0.0 read back INTEGER 1 or 0; 'true' and 'yes' read back TEXT, and 2 reads back 2 |
| SQLite has no boolean; TRUE and FALSE are 1 and 0 | ADR 23–25 | measured here (S1): INTEGER 1 and 0, `typeof(TRUE)` integer, `TRUE = 1` |
| a declared type is an affinity: BOOLEAN holds `'yes'` as TEXT | ADR 22–23 | measured before (m2-plan 10) and here (S1) |
| bytes that aren't UTF-8 are stored as TEXT | ADR 37 | measured before: m2-plan 10 |
| empty TEXT: a pointer through `column_text`, NULL through `column_blob`; empty BLOB NULL | plan 233; ADR 38–40, 144–147, 189 | measured before: m2-plan 11, m2-review probe 2 B |
| after a step answers a row, `sqlite3_errcode` is 100 | ADR 40 | measured before (m2-review probe 2 B) and here (item 1, S3) |
| the type first, then the matching accessor: SQLite converts nothing | ADR 127–128 | measured here (S4): type and pointer unchanged by a matching read, for all four types. The other way round, a BLOB read by `column_text` turns TEXT (item 5, S4). A matching `column_text` can still allocate (`oom.c` 1), but that isn't a conversion |
| a NULL pointer is told from running out of memory by the extended code, read at once; only NOMEM raises | plan 235–237; ADR 131–133, 218–226 | measured here: a NULL read sets no code. The code read after it is the last call's: 100, or 1 after another statement's failed prepare, or 0 after a good one (S3). A NOMEM read answers extended 7 and "out of memory" (`oom.c`) |
| only `sqlite3_extended_errcode` answers the extended code whatever the open's flags | ADR 218–221 | measured here (S2): with EXRESCODE, errcode and extended are 2067; without it, errcode is 19 and extended 2067, and the step answers 19 |
| `column_name` answering NULL sets no code (the floor's source) | plan 237–238; ADR 162–169 | measured here, both libraries (`oom.c` 5): NULL, and the code stayed 1, from an earlier failed prepare. `errstr(7)` is "out of memory" |
| neither out-of-memory path can be caused on a real library; running out of memory can't be caused on demand | plan 238–239; ADR 133–134 | **contradicted** (`oom.c`, `heap-limit.c`), see below |
| a UTF-16 database converts to UTF-8; some invalid UTF-16 converts to valid UTF-8 | plan 243–245; ADR 41–43, 135–137 | measured before: m2-review probes 2 G, 3 H |
| `clear_bindings` makes every parameter NULL | ADR 106 | measured before, for one INTEGER (`test-native.sps` 755); here, for INTEGER, REAL, TEXT, BLOB and an unbound one (S5) |
| a bind while a row is ready answers MISUSE | ADR 107 | measured before (m2-plan 8) and here, item 1 |
| a name with its sigil, found by `sqlite3_bind_parameter_index`; an absent name | ADR 98–101 | measured here, item 3 |
| 3.53.1 clamps the length limit to at least 30, and the floor doesn't | ADR 77–78; plan 335–336 | measured here, item 2: **the floor clamps 0 to 1**, see below |
| `utf8->string` replaces bad bytes, drops one leading U+FEFF; a Chez string is scalar values; Chez shares its empty bytevector | ADR 44, 45–46, 212–217, 232–234 | Chez, not SQLite: the brief's evidence, M2 slice 1 (traps.md), R6RS. Not re-measured |
| the strict decoder's offsets, and its cost | plan 241–242; ADR 149–159, 227–231 | Scheme, not SQLite: measured before, [m2-slice-1/](../m2-slice-1/) |

**What `oom.c` measured,** with SQLite's default allocator wrapped by one that refuses every
`xMalloc` and `xRealloc` while a flag is set, installed with `sqlite3_config(SQLITE_CONFIG_MALLOC)`
before `sqlite3_initialize`, lookaside off. Identical on both libraries:

- **A TEXT bound with its length, as ADR-0015 binds one, read straight back through `select ?1`:**
  `column_text` asked for one allocation, a NUL-terminated copy. Refused, it answered NULL, with
  errcode and extended 7 and errmsg "out of memory". With lookaside on, a 5,000-byte value failed
  the same way, and a 5-byte one didn't: lookaside served it
  ([oom-lookaside-default-guix-3.53.1.txt](oom-lookaside-default-guix-3.53.1.txt)).
- **Read from a table's row, TEXT and BLOB, and `zeroblob(5000)` through `column_blob`, asked for
  nothing:** 0 refused, and a pointer came back.
- **After the NOMEM, the column is NULL:**
  - type 5, `column_bytes` 0, and a second `column_text` answered NULL with the code still 7;
  - the next step answered 7, and a reset or finalize straight after answered 7;
  - after the reset, the statement ran again (100, `"abcde"`).
- **`column_name` asked for nothing** after prepare or after a step, with every allocation
  refused. Only after `sqlite3_column_name16`, which chez-sqlite3 never calls, converted the name
  in place, did `column_name` allocate, and then answer NULL with the code unchanged.

**What `heap-limit.c` measured,** with no allocator of its own, after `sqlite3_initialize`, as a
suite could through the FFI. Between a step and a column read it set `sqlite3_hard_heap_limit64`
to `sqlite3_memory_used() + 1000`, then set it back to 0. Identical on both libraries
([heap-limit-guix-3.53.1.txt](heap-limit-guix-3.53.1.txt),
[heap-limit-floor-3.45.1.txt](heap-limit-floor-3.45.1.txt)):

- **With the memory count on, each library's default:** a 100,000-byte TEXT bound with its length,
  read through `select ?1`, made `column_text` answer NULL, with errcode and extended 7 and
  errmsg "out of memory". Its type was then 5. The first reset answered 7, a second 0, and the
  statement then stepped and read again. A 5-byte TEXT read the same way came back: lookaside
  served it.
- **With the memory count off** (`sqlite3_config(SQLITE_CONFIG_MEMSTATUS, 0)` before initialize,
  as a build with `SQLITE_DEFAULT_MEMSTATUS=0` has it): the limit was kept and read back, but not
  enforced. The 100,000-byte read came back, and `sqlite3_memory_used` read 0
  ([heap-limit-memstatus-off-guix-3.53.1.txt](heap-limit-memstatus-off-guix-3.53.1.txt),
  [heap-limit-memstatus-off-floor-3.45.1.txt](heap-limit-memstatus-off-floor-3.45.1.txt)).
  Apple's library keeps no memory count (M1's Mac runs: "this libsqlite3 keeps no memory count"),
  so a row built this way is unavailable there, as `suite-exit-status`'s memory check is.
- `sqlite3_hard_heap_limit64` isn't one of M2's entry points; a suite would bind it itself, as it
  binds `sqlite3_limit`. The limit is process-wide, so a row that sets it must set it back.

## Traps found

Each was reproduced twice on each library, by the minimal probe named, with the same output.

1. **`sqlite3_error_offset` answers an earlier failed prepare's offset after a refused bind**
   ([trap-stale-offset.sps](trap-stale-offset.sps)). A failed `select nosuch_col` leaves 7. A
   bind at index 0 then answers 25, and the code and message become the bind's, but the offset
   still reads 7. A clean bind clears it. Any code that reads the offset after a non-prepare
   failure carries a wrong one.
2. **On 3.53.1, a prepare's offset depends on whether it is the connection's first**
   ([trap-first-prepare-offset.sps](trap-first-prepare-offset.sps)):
   - `select ?0`, `select ?32767` and `select ?1, ?0` answer −1 as a fresh connection's first
     prepare. Prepared again, or after any earlier prepare, good or failed, they answer 7, 7 and
     11. The floor answers 7, 7 and 11 every time;
   - with SQL after the token (`select ?0 where 1`), both answer 7 every time;
   - `select 1 from nosuch_table where 1` answers −1 on both, every time, though its error isn't
     at the end of the SQL.
3. **`SQLITE_LIMIT_LENGTH` holds column names at prepare**
   ([trap-limit-names.sps](trap-limit-names.sps)). At 30, an alias of 31 bytes, or a literal
   whose own text is 31 bytes, answers 18 at prepare, on both. Set to 1, the floor refuses even
   `select ?1`. A row that lowers the limit to test a refused bind must keep every column name
   within it, or the prepare fails first.
4. **After a column read runs out of memory, the column reads NULL, and reset and finalize answer
   NOMEM** ([trap-oom-reread.c](trap-oom-reread.c)). A second read of the column answers NULL with
   the code still 7, and its type is now 5, so a reader that reads the type first gives `sql-null`
   on a retry. `sqlite3_reset` answered 7, though the step had answered a row.

## Where this contradicts the records

1. **ADR-0015, decision 2, lines 77–78:** "3.53.1 clamps the limit to at least 30, and the floor
   doesn't (measured)." The floor clamps too, to at least 1: set to 0, it reads 1
   ([limit-length-floor-3.45.1.txt](limit-length-floor-3.45.1.txt): "set LENGTH 0: answered
   1000000000, then reads 1"). [m2-review](../m2-review/README.md), lines 40–41, says the floor
   "keeps 10", which holds. The plan's lines 335–336 hold.
2. **The M2 plan, §4.4, lines 238–239:** "Neither path can be caused on a real library". And
   **ADR-0015, decision 7, lines 133–134:** "Running out of memory can't be caused on demand".
   Both were caused on both libraries, through `sqlite3_config(SQLITE_CONFIG_MALLOC)` before
   `sqlite3_initialize` ([oom-guix-3.53.1.txt](oom-guix-3.53.1.txt),
   [oom-floor-3.45.1.txt](oom-floor-3.45.1.txt)):
   - `column_text` answered NULL with NOMEM for a TEXT bound with its length, the binding's own
     way, read through `select ?1`;
   - `column_name` answered NULL with no code, though only after `column_name16`.

   That way needs a C allocator installed before the library initializes, and chez-sqlite3's
   native calls `sqlite3_initialize` at load. But `column_text`'s path needs no allocator:
   `sqlite3_hard_heap_limit64`, set at run time after initialize, caused it on both libraries
   ([heap-limit-guix-3.53.1.txt](heap-limit-guix-3.53.1.txt),
   [heap-limit-floor-3.45.1.txt](heap-limit-floor-3.45.1.txt)). It needs the memory count on, so
   not on Apple's library, and a value larger than lookaside serves. `column_name`'s path still
   needs `column_name16` first, which chez-sqlite3 never calls. Whether a suite reaches the
   `column_text` path for real is slice 4's choice. The claim, as a fact about SQLite, doesn't
   hold.
3. **ADR-0014, decision 7, lines 153–155:** "In any other state, an answer other than `SQLITE_OK`
   is a failure of its own". The M2 plan, §4.1, lines 148–151, says the same ("in any other state
   an answer other than `SQLITE_OK` is a new failure"), and so do the global constraints, line
   131 ("Reset and finalize raise a failure of their own, and never repeat a failed step's").
   - In the `row` state, after `column_text` answered NULL with NOMEM, `sqlite3_reset` answered 7
     and `sqlite3_finalize` answered 7. That is the column read's code, not a new failure
     ([oom-guix-3.53.1.txt](oom-guix-3.53.1.txt) rows 1b and 1c, and
     [trap-oom-reread-guix-3.53.1.txt](trap-oom-reread-guix-3.53.1.txt); the same at the floor).
   - So, as written, a `column-value` that raises `nomem` is followed by a `reset!` or
     `finalize-statement!` that raises `nomem` again.
4. **The M2 plan, §4.6, lines 256–257:** "`#f` when SQLite gives −1, as it does for an error at
   the end of the SQL (measured)". And **ADR-0013, lines 147–148:** "SQLite's −1, which it answers
   for an error at the end of the SQL, gives `#f`". The rule, −1 to `#f`, stands. The reason is
   incomplete ([trap-first-prepare-offset-guix-3.53.1.txt](trap-first-prepare-offset-guix-3.53.1.txt)):
   - −1 also comes for `select 1 from nosuch_table where 1`, mid-SQL, on both libraries;
   - on 3.53.1, `select ?0` answers −1 or 7 by whether it is the connection's first prepare.

   This is slice 3's ground, not slice 4's.

No measurement here contradicts the existing research. Each earlier result these probes touched
gave the same answer again: `-0.0` and NaN weren't re-run; the refused bind's NULL, MISUSE while a
row is ready, and errcode 100 after a row were.
