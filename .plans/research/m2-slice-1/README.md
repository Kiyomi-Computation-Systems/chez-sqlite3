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

## The strict decoder's cost ([utf8-cost.sps](utf8-cost.sps))

Measured 2026-11-14 in the Guix container (Chez 10.4.0), not under Valgrind, on an Intel Core Ultra
5 125H (x86_64, 18 logical CPUs). The decoder is the byte-by-byte one:
`utf8-ill-formed-offset`, then `utf8->string`. Each row is the median of 5 runs, each run a
collection and then 20 calls (10 passes for the values), reported as ms per call:

```
$ scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs \
    --program .plans/research/m2-slice-1/utf8-cost.sps'
```

| Input | `utf8->string` | `strict-utf8->string` | Ratio |
|---|---|---|---|
| 1 MiB of ASCII (1,048,576 bytes) | 2.9 ms | 4.4 ms | 1.52 |
| about 1 MiB of mixed 2-, 3- and 4-byte text (1,048,572 bytes) | 2.95 ms | 5.2 ms | 1.76 |
| 100,000 values of 16 bytes (ASCII) | 1.9 ms | 4.4 ms | 2.32 |

Three runs of the script agreed within 5% (ratios 1.52 to 1.79 for the megabyte rows, 2.25 to 2.32
for the values). So the check adds about 1.5 ms per MiB, and 14 to 25 ns per 16-byte value. No
wider-read path was built; the decision is the maintainer's.

## The decoder against Python ([utf8-dump.sps](utf8-dump.sps), [utf8-check.py](utf8-check.py))

`utf8-dump.sps` writes `utf8-ill-formed-offset`'s answer for every 1-byte input (256), every 2-byte
input (65,536) and the range edges of Table 3-7's 3- and 4-byte rows (104), under `build/`, in the
container, which has no `python3`. On the host, `utf8-check.py` compares each line with
`bytes.decode('utf-8')`, whose `UnicodeDecodeError.start` is the same offset: 65,896 lines, 65,896
agreed, none disagreed. The check was watched failing: one answer changed in the dump gave
`65,895 agreed, 1 disagreed`.

```
$ scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs \
    --program .plans/research/m2-slice-1/utf8-dump.sps build/utf8-dump.txt'
$ python3 -I .plans/research/m2-slice-1/utf8-check.py build/utf8-dump.txt
```

## Which 1-, 2- and 3-byte SQL SQLite leaves empty ([tail-accepted.sps](tail-accepted.sps))

On Guix's 3.53.1, 6 NUL-free inputs of 1 byte, 42 of 2 bytes (65,280 tried) and 798 of 3 bytes
(16,581,375 tried) come out of `sqlite3_prepare_v3` empty: `SQLITE_OK` and a NULL statement. Of the
798, 1 is `EF BB BF` and 255 are `2F 2A` and a byte (a `/*` with one byte after it). On the floor,
3.45.1 (`build/m2s1-floor/libsqlite3-floor.so`, through `CHEZ_SQLITE3_LIBRARY`), the lists of all
three lengths are identical. `tests/test-sql-tail.sps` holds the 1- and 2-byte lists as one
literal and the 3-byte list as a second, and holds the scanner to them: every listed 3-byte input
is accepted, and every 3-byte input over the 14 bytes of `tail.sps`' alphabet (2,744) is accepted
exactly when it is listed.

```
$ scripts/guix-env sh -c '$CHEZ --script .plans/research/m2-slice-1/tail-accepted.sps'
$ scripts/guix-env sh -c 'CHEZ_SQLITE3_LIBRARY=$PWD/build/m2s1-floor/libsqlite3-floor.so $CHEZ --script .plans/research/m2-slice-1/tail-accepted.sps'
```

The pass takes about 5 s. Its output is the 1- and 2-byte lines, a `3-byte` marker line, the
3-byte lines, and the counts.
