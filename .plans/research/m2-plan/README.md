# What the M2 plan's questions rest on

Measured 2026-11-14 in the Guix container through bare FFI ([probe.sps](probe.sps)), on two
libraries:

- **Guix's 3.53.1,** the container's own ([guix-3.53.1.txt](guix-3.53.1.txt));
- **the floor, 3.45.1** ([floor-3.45.1.txt](floor-3.45.1.txt)), built as M1 slice 4 built it:
  `sqlite3.c` from `sqlite-amalgamation-3450100.zip`, SHA-256 `1a206854…c710ab`, the same file
  slice 4 recorded, compiled with `$CC -shared -fPIC -O1 -DSQLITE_THREADSAFE=1` (gcc 16.2.0)
  under the git-ignored `build/m2-probe/`, and loaded through `CHEZ_SQLITE3_LIBRARY`.

The two outputs differ in their first line alone, the version (`diff guix-3.53.1.txt
floor-3.45.1.txt`). Guix's:

```
$ scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-plan/probe.sps'
libversion: "3.53.1"
1. step, step again without reset (101 is DONE): (101 101)
1. rows after two steps of one insert: 2
2/9. failed step's code (2067 is CONSTRAINT_UNIQUE, 19 CONSTRAINT): 2067
2. reset, reset again, step again, finalize: (2067 0 2067 2067)
3. bind rcs: (0 0 0 0)
3. typeof: NULL-pointer text, NULL-pointer blob, empty text, empty blob: ("null" "null" "text" "blob")
4. -0.0 through a REAL column: type (2 FLOAT), value: (2 0.0)
4. -0.0 through select ?: type, value: (2 -0.0)
5. prepare: ("select 1; select 2" rc 0 stmt-null? #f tail-at 9)
5. prepare: ("select 1;   -- a comment" rc 0 stmt-null? #f tail-at 9)
5. prepare: ("select 1;" rc 0 stmt-null? #f tail-at 9)
5. prepare: ("" rc 0 stmt-null? #t tail-at 0)
5. prepare: ("   -- only a comment" rc 0 stmt-null? #t tail-at 20)
6. rc (1 ERROR), offset: (1 13)
6. nosuchcol's index in characters, in bytes: (12 13)
7. 'select 1' NUL ' garbage': rc, stmt-null?, tail-at, length: (0 #f 8 17)
8. bind index 2 of 1 (25 RANGE), bind 1, step, bind while a row is ready (21 MISUSE): (25 0 100 21)
10. cast(x'ff41' as text): type (3 TEXT), bytes: (3 (255 65))
10. 'yes' in a BOOLEAN column: type (3 TEXT): 3
11. '': type, pointer null?, bytes: (3 #f 0)
11. x'': type (4 BLOB), pointer null?, bytes: (4 #t 0)
```

What it shows:

1. **A step after `SQLITE_DONE` runs the statement again.** One `insert` stepped twice, with no
   reset between, made two rows. SQLite resets a finished statement itself unless it is built
   with `SQLITE_OMIT_AUTORESET`, where the second step answers `SQLITE_MISUSE` instead.
2. **`sqlite3_reset` and `sqlite3_finalize` answer the failed step's code again.** After a step
   failed with 2067, the first reset answered 2067, the second 0. A step after that ran the
   insert again and failed again, and finalize answered 2067 once more.
3. **A NULL pointer binds NULL,** for text and for a blob, measured with length 0; SQLite's
   documentation for `sqlite3_bind_blob` says the length is then ignored. A non-NULL pointer with
   length 0 binds an empty TEXT and an empty BLOB.
4. **`-0.0` loses its sign in a REAL column,** and keeps it through `select ?`. SQLite stores a
   REAL with an integer value as an integer on disk.
5. **`sqlite3_prepare_v3` compiles the first statement and leaves the rest,** answering
   `SQLITE_OK`. The tail is not checked: `select 1; select 2` and `select 1; -- a comment` both
   leave their tail at byte 9. Empty SQL and SQL that is only a comment answer `SQLITE_OK` with a
   NULL statement.
6. **`sqlite3_error_offset` counts bytes.** It answered 13 for `nosuchcol`, which starts at
   character 12, after a two-byte `é`.
7. **A NUL ends the SQL, even with its byte length given.** `select 1`, a NUL, then ` garbage`,
   17 bytes in all, compiled `select 1` and left its tail at the NUL. Preparing the tail from there
   would stop at the same NUL, so a check of the tail alone can't see the garbage.
8. **A bind out of range answers `SQLITE_RANGE` (25); a bind while a row is ready answers
   `SQLITE_MISUSE` (21).**
9. **A failed step answers the extended code itself,** 2067, on a connection opened with
   `SQLITE_OPEN_EXRESCODE`.
10. **SQLite stores bytes that aren't UTF-8 as TEXT.** `cast(x'ff41' as text)` is TEXT holding
    the bytes 255 and 65. A column declared `BOOLEAN` holds the text `'yes'` as TEXT: a declared
    type is an affinity, not a check.
11. **An empty TEXT reads back as a non-NULL pointer; an empty BLOB as a NULL one,** each with 0
    bytes, as SQLite's documentation for `sqlite3_column_blob` says.

**Every entry point the plan requires is in the floor's build.** `nm -D --defined-only` on the
3.45.1 library above found all 21 of the M2 plan's §4.7 list (run in the container, 2026-11-14).

M2 slice 0's review measured more, in [research/m2-review/](../m2-review/).
