# What M2 slice 1 measured

Measured 2026-11-14 in the Guix container through bare FFI, on two libraries, with the same
results apart from the version line:

- **Guix's 3.53.1,** the container's own ([tail-guix-3.53.1.txt](tail-guix-3.53.1.txt));
- **the floor, 3.45.1** ([tail-floor-3.45.1.txt](tail-floor-3.45.1.txt)), built as the M2 plan's
  probes built it: `sqlite3.c` from `sqlite-amalgamation-3450100.zip`, SHA-256
  `1a206854aa9fe0ccc1b609f5cfce67eb52ac0a8f5aa2f5e853f7c3ed84c710ab`, compiled with
  `$CC -shared -fPIC -O1 -DSQLITE_THREADSAFE=1` under the git-ignored `build/m2s1-floor/`, and
  loaded through `CHEZ_SQLITE3_LIBRARY`.

```
$ scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-slice-1/tail.sps'
$ scripts/guix-env sh -c 'CHEZ_SQLITE3_LIBRARY=$PWD/build/m2s1-floor/libsqlite3-floor.so \
    $CHEZ --script .plans/research/m2-slice-1/tail.sps'
```

## The tail scan's whitespace ([tail.sps](tail.sps))

Every SQL of 1, 2 and 3 bytes, and every one of 4 to 6 bytes over the 14 bytes the rules name
(space, `\t`, `\n`, `\v`, `\f`, `\r`, `;`, `-`, `/`, `*`, `EF`, `BB`, `BF` and `A`), was prepared
alone, with its byte length. "Empty" is `SQLITE_OK` with a NULL statement. Each answer was compared
with two models of ADR-0014 decision 4's scan:

| Inputs | Checked | As accepted: mismatches | Amended: mismatches |
|---|---|---|---|
| 1 and 2 bytes | 65,792 | 5 | 0 |
| 3 bytes | 16,777,216 | 66 | 0 |
| 4 to 6 bytes, over 14 bytes | 8,105,776 | 56,354 | 0 |

Inputs holding a NUL are counted apart (263, and 67,114 of 3 bytes): a NUL ends SQLite's parse,
and SQL holding U+0000 is refused before it is scanned (ADR-0011, amended).

1. **`\v` continues a whitespace run.** As accepted, the model's whitespace was exactly space,
   `\t`, `\n`, `\f` and `\r`. SQLite found `" \v"`, `"\t\v;"` and every such run empty. `"\v"`
   alone, and `";\v"`, are errors, as the M2 review measured. The floor's `sqlite3GetToken`
   shows why: a whitespace token starts on one of the five (`aiClass` class 7), then runs while
   `sqlite3Isspace` holds, and `sqlite3CtypeMap` marks `09` to `0D`, `\v` among them, as
   spaces.
2. **U+FEFF, `EF BB BF`, is a whitespace token wherever it stands.** It was the one 3-byte
   mismatch left once `\v` was amended. The tokenizer's `CC_BOM` case answers `TK_SPACE` for the
   three bytes, at any position, not only at the start.
3. **The amended model:** a run that starts with space, `\t`, `\n`, `\f` or `\r` and continues on
   any of those or `\v`; `EF BB BF`; `--` to the next `\n` or the end; `/*` with at least one byte
   after it, to the first `*/` that starts at or after the byte following `/*`, or to the end;
   semicolons. Nothing else. It agrees with SQLite on every input above.
4. **The tail starts after the first statement's semicolon:** 9 for `select 1; select 2` and for
   `select 1;;`, 10 for `select 1 ; x`, 15 for `select 1 -- c\n; x`, 16 for
   `select 1/* c */; x`; 8 for `select 1`. So the scan starts on a fresh token, as SQLite's own
   prepare of the tail would.

The maintainer chose, 2026-11-14, to match SQLite: "`\v` continues a whitespace run, as SQLite's
tokenizer does. ADR-0014 decision 4 and the constraint get an amendment with this measurement.
The scanner then agrees with prepare over the whole complement, as R2 asked, with no exceptions."
U+FEFF was found by the same probe afterwards and follows the same choice
([ADR-0014, amended](../../decisions/0014-statements-belong-to-their-connection.md)).
