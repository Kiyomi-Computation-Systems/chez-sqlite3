# Research: M4's pre-work, the variadic `db_config` probe and the compile-option census

Written and run 2026-11-16, before M4 has a plan, on `main` at `cc8c60d`. Every Linux run was in
the Guix container: Chez 10.4.0 (`ta6le`, threaded), gcc 16.2.0, Valgrind 3.27.0, x86_64. The
Mac step is [mac.md](mac.md). The maintainer ran it on 2026-11-17: [its
results](#results-the-mac-step-on-apple-arm64). Nothing here ships.

## The files

| File | What it is |
|---|---|
| [varargs.sps](varargs.sps) | The variadic probe: `sqlite3_db_config` bound with `(__varargs_after 2)`, and plain |
| [varargs.c](varargs.c) | Its C oracle: the same calls in C, printed the same way under the label `c` |
| [constants.c](constants.c) | Holds each probe's numbers to one `sqlite3.h` |
| [census.sps](census.sps) | The census: version, every compile option, FTS5, JSON, DQS, each op's start, `load_extension` |
| [run.sh](run.sh) | Runs all of the above on one library |
| [valgrind.sh](valgrind.sh) | `varargs.sps` under Valgrind, with the memory gate's flags |
| [mac.md](mac.md) | The maintainer's commands for Apple's and Homebrew's SQLite |
| [out/](out/) | Every output, whole: `varargs-`, `census-`, `constants-`, `oracle-`, `compare-` and `valgrind-` per library |

Both `.sps` files are standalone. Each takes a library path, loads it with `load-shared-object`,
binds what it needs with `foreign-procedure`, and loads none of chez-sqlite3's libraries. Neither
passes a Scheme object to C: strings go in foreign blocks and come back as addresses
(ADR-0011). Every database is `:memory:`. Each prints one datum per line and flushes it, so a
crash keeps the lines before it.

## What each probe does

**`varargs.sps LIBRARY [all | varargs | plain]`:**

- **Its numbers first.** It prints `(constant NAME VALUE)` for every number from `sqlite3.h` it
  uses, and the unknown op it tries, 1999, before it loads anything. They are written once, in
  the file, and every use reads them from that one table.
- **`varargs`:** `sqlite3_db_config` bound with `(__varargs_after 2)` in the shape
  `(db op int int*)`, for `ENABLE_LOAD_EXTENSION`, `DEFENSIVE`, `DQS_DML`, `DQS_DDL` and
  `TRUSTED_SCHEMA`.
  - **The round trip,** on a connection of its own for each op: read with −1, set 0, read, set 1,
    read, set back to the start, read. Each call's int cell starts at a sentinel of its own,
    printed `untouched` if the call left it. Every return code and value is printed, then a
    verdict: `ok` when every call answered 0 and every value was the one it should be.
  - **An unknown op,** 1999.
  - **Behaviour,** with the op at 0 and at 1, on a fresh connection each:
    - `DEFENSIVE`: `PRAGMA writable_schema = 1`, reading it back, then
      `update sqlite_schema set sql = sql where name = 't'`;
    - `DQS_DML`: `select "no_such_column"`;
    - `DQS_DDL`: `create index i on t("no_such_column")`;
    - `ENABLE_LOAD_EXTENSION`: `select load_extension('x')`.
  - **The shape `LOOKASIDE` takes,** `(db op void* int int)`, bound separately: a NULL buffer with
    (120, 7), (120, 5), (200, 7) and (0, 0); a small workload; each lookaside counter from
    `sqlite3_db_status`; then `LOOKASIDE` again while a statement is held at a row, and after its
    finalize.
- **`plain`:** the `(db op int int*)` shape bound with no convention, with the same round trips
  and the unknown op, under its own label. It runs last, since on Apple arm64 it is expected to
  hand C garbage.
- `all`, the default, runs `varargs` then `plain`.

**`varargs.c`** makes the `varargs` calls in C, where the compiler knows the call is variadic.
`run.sh` compares the probe's `(varargs …)` lines with its `(c …)` lines, and the probe's
`(plain …)` lines with its round trips, verdicts and unknown op. The two print bytes the same way:
printable ASCII as itself, anything else as `%HH`.

**`constants.c`,** compiled against one header, reads a probe's output and checks every
`(constant …)` line against that header, and the unknown op against `SQLITE_DBCONFIG_MAX`. It
holds names only, never values. It fails on a mismatch, an unknown name, or input with no
constant.

**`census.sps LIBRARY`** prints:

- its constants;
- `sqlite3_libversion`, its number, `sqlite3_sourceid`, `sqlite3_threadsafe`, and every option
  from `sqlite3_compileoption_get` until it answers NULL;
- whether `sqlite3_load_extension` and `sqlite3_enable_load_extension` resolve, by
  `foreign-entry?`;
- FTS5: an `fts5` table, a row, and a `MATCH` query;
- JSON: `json('{}')`, and `jsonb('{}')` with its column type and bytes;
- DQS: `select "x"`, with nothing changed;
- each op's starting value, read with −1 through the `(__varargs_after 2)` binding.

## How to rerun it

The libraries must exist first; [The libraries](#the-libraries) says how each was made. Then,
from the repository's root:

```
scripts/guix-env sh -c 'P=.plans/research/m4-prework
  g=$(readlink -f "$CHEZ_SQLITE3_LIBRARY"); ginc=$(dirname "$(dirname "$g")")/include
  sh $P/run.sh guix-3.53.1 "$CHEZ_SQLITE3_LIBRARY" "$ginc"
  sh $P/run.sh floor-3.45.1 build/m3-floor/lib/libsqlite3.so.0 build/m3-floor/include
  sh $P/run.sh current-3.54.1 build/m4pre/current/lib/libsqlite3.so.0 build/m4pre/current/include
  sh $P/run.sh ubuntu-noble-3.45.1 build/m4pre/ubuntu/usr/lib/x86_64-linux-gnu/libsqlite3.so.0
  sh $P/run.sh floor-omit-load-3.45.1 build/m4pre/floor-omit-load/lib/libsqlite3.so.0 build/m3-floor/include
  sh $P/valgrind.sh guix-3.53.1 "$CHEZ_SQLITE3_LIBRARY"
  sh $P/valgrind.sh floor-3.45.1 build/m3-floor/lib/libsqlite3.so.0
  sh $P/valgrind.sh current-3.54.1 build/m4pre/current/lib/libsqlite3.so.0
  sh $P/valgrind.sh ubuntu-noble-3.45.1 build/m4pre/ubuntu/usr/lib/x86_64-linux-gnu/libsqlite3.so.0'
```

Paths are relative to the root, so no output names a home directory. Each script exits non-zero
when a probe, a check or a comparison fails. Every one exited 0.

## The libraries

| Label | Library | How it was obtained, and checked |
|---|---|---|
| `guix-3.53.1` | The container's, `/gnu/store/vi2anm0…-sqlite-3.53.1` | The profile's, as `CHEZ_SQLITE3_LIBRARY` names it (ADR-0006) |
| `floor-3.45.1` | `build/m3-floor` | Built in M3 as CI's `floor` lane builds it (sha256 `a36320cb…`). `scripts/ci/check-sqlite.sh` passed on it again today: version, source id and its 37 options, line for line |
| `current-3.54.1` | `build/m4pre/current` | `sqlite-autoconf-3540100.tar.gz` downloaded on the host. Its SHA3-256 and its `sqlite3.c`'s matched `build-sqlite.sh`'s `current_archive` and `current_source` pins. Compiled in the container with `build-sqlite.sh`'s line: `-shared -fPIC -O2 -DSQLITE_THREADSAFE=1 -Wl,-z,defs … -lpthread -lm`. `check-sqlite.sh --current` passed on it: 38 options, line for line |
| `ubuntu-noble-3.45.1` | `build/m4pre/ubuntu/…/libsqlite3.so.0` | `libsqlite3-0_3.45.1-1ubuntu2.9_amd64.deb`, noble-updates' newest. The chain was checked on the host: `gpgv` against `ubuntu-archive-keyring.gpg` passed on `InRelease`; the `Packages.xz` sha256 matched it; the `.deb`'s sha256, `e04c9d3c…92e5`, matched `Packages`. Extracted with `dpkg-deb -x` |
| `floor-omit-load-3.45.1` | `build/m4pre/floor-omit-load` | **An extra**, for question 4 below: the floor's amalgamation with the same line plus `-DSQLITE_OMIT_LOAD_EXTENSION` |

**Ubuntu's library loads in the container,** by absolute path. It needs glibc 2.38, and the
process runs Guix's 2.41. So its census was read **through the FFI**, not statically. It is the
`main` lane's library:

- Its 58 options are, line for line, the ones CI's `main` job printed through
  `report-sqlite.sh` on 2026-11-16 (run 43977146841, `libsqlite3-dev` 3.45.1-1ubuntu2.9).
- So is its source id, which ends `…ccalt1`, not hex. Debian changed it, as Apple changed
  theirs to `…dcaapl`.

No Ubuntu header was fetched, so the Ubuntu row has no `constants-` or `oracle-` file.

## Results: the census

| | guix 3.53.1 | floor 3.45.1 | current 3.54.1 | Ubuntu 3.45.1 (`main`) | floor, OMIT_LOAD_EXTENSION |
|---|---|---|---|---|---|
| Options | 46 | 37 | 38 | 58 | 38 |
| FTS5 | yes | **no** | **no** | yes | no |
| `json('{}')` | `{}` | `{}` | `{}` | `{}` | `{}` |
| `jsonb('{}')` | blob `0C` | blob `0C` | blob `0C` | blob `0C` | blob `0C` |
| `select "x"` (DQS) | row `x` | row `x` | row `x` | row `x` | row `x` |
| `ENABLE_LOAD_EXTENSION` start | 0 | 0 | 0 | **1** | 0 |
| `DEFENSIVE` start | 0 | 0 | 0 | 0 | 0 |
| `DQS_DML` start | 1 | 1 | 1 | 1 | 1 |
| `DQS_DDL` start | 1 | 1 | 1 | 1 | 1 |
| `TRUSTED_SCHEMA` start | 1 | 1 | 1 | 1 | 1 |
| `sqlite3_load_extension` | present | present | present | present | **missing** |
| `sqlite3_threadsafe` | 1 | 1 | 1 | 1 | 1 |

- **The options that differ.**
  - Guix's has `ENABLE_FTS3`, `ENABLE_FTS4`, `ENABLE_FTS5`, `SECURE_DELETE`, `ENABLE_DBSTAT_VTAB`
    and others.
  - Ubuntu's adds, among others, `ENABLE_FTS3_TOKENIZER`, `ENABLE_LOAD_EXTENSION`, `ENABLE_RTREE`,
    `ENABLE_SESSION`, `USE_URI` and `MAX_VARIABLE_NUMBER=250000`.
  - The floor and current lanes have SQLite's defaults alone: no `ENABLE_*` option.
  - The lists are whole in `out/census-*.txt`.
- **No library lists `DQS`,** so each has SQLite's default, both kinds on. Apple's lists `DQS=3`,
  the same (M1's [mac-d7](../mac-d7/)).
- **An FTS5 table on a library without it fails at step, not at prepare.**
  `create virtual table f using fts5(body)` prepared, then answered 1, "no such module: fts5",
  at its step, on the floor and on 3.54.1.

## Results: the variadic probe, on x86_64

- **`(__varargs_after 2)` round-trips every op on every library:** all five verdicts `ok` on all
  five builds. Every call answered 0. Each set's own cell held the new value, and each read gave
  it back.
- **The plain binding round-trips every op too, on x86_64.** Its 41 lines are identical to the C
  oracle's round trips on guix, floor, current and the OMIT build, and its verdicts are `ok` on
  Ubuntu's. So on this machine nothing tells the two bindings apart. Linux arm64 wasn't measured.
- **The C oracle agrees with the probe.** All 103 `varargs` lines are identical on guix, floor,
  current and the OMIT build. Each oracle printed its header's version and its library's, which
  matched. `ldd` showed it linked the probe's own file.
- **An unknown op, 1999, answers 1 (`SQLITE_ERROR`)** and leaves the cell untouched, under both
  bindings. 1999 is above `SQLITE_DBCONFIG_MAX`: 1019 in 3.45.1's header, 1023 in 3.53.1's and
  3.54.1's.
- **The `LOOKASIDE` shape delivers its three arguments:**
  - the slots used peaked at the count given: 7, 5, 7, and 0 when off;
  - the misses for size moved with the size: 31 at 120 bytes and 18 at 200, at the floor;
  - with a statement held at a row, a second `LOOKASIDE` answered 5 (`SQLITE_BUSY`), and 0 after
    the finalize. It answered 0 while held when lookaside was off.
- **Behaviour, the same on all five builds** but where noted:

  | Op | At 0 | At 1 |
  |---|---|---|
  | `DEFENSIVE` | `writable_schema = 1` reads back 1; the `sqlite_schema` update runs | `writable_schema = 1` answers done, but reads back **0**; the update fails at prepare, 1, "table sqlite_master may not be modified" |
  | `DQS_DML` | prepare fails, 1, "no such column" | row `no_such_column` |
  | `DQS_DDL` | the `create index` fails at prepare, 1, "no such column" | done |
  | `ENABLE_LOAD_EXTENSION` | `select load_extension('x')` prepares, then answers 1, "not authorized", at step | the same: SQL stays refused |

  - **The OMIT build** refuses `load_extension('x')` at prepare instead: 1, "no such function:
    load_extension". It still round-trips `ENABLE_LOAD_EXTENSION`, answering 0, though the
    setting does nothing there.
  - **The DQS message differs by version.** 3.45.1 says `no such column: no_such_column`. 3.53.1
    and 3.54.1 say `no such column: "no_such_column" - should this be a string literal in
    single-quotes?`.
- **The constants:** 19 for `varargs.sps` and 15 for `census.sps`, against the headers of 3.45.1,
  3.53.1 and 3.54.1. No fault.
- **Valgrind, with the gate's flags** (`--error-exitcode=9 --leak-check=full
  --show-leak-kinds=definite --errors-for-leak-kinds=definite`, and `--command-line-only=yes`):
  - on guix, floor, current and Ubuntu: 0 errors, 0 bytes definitely lost, exit 0;
  - between 1,697 and 1,892 bytes in 5 blocks still reachable, as the four logs show;
  - the output under Valgrind was the same as without it, byte for byte;
  - the logs are `out/valgrind-*.txt`.

### Watched failing

Each check was run once against a planted fault, on the floor, in `build/m4pre/controls/`:

1. **Valgrind:** a copy of `varargs.sps` whose blocks are never freed exited 9. It showed 2,556
   bytes definitely lost in 228 blocks, and `ERROR SUMMARY: 1 errors`.
2. **`constants.c`:** output with `DEFENSIVE` as 1011, a name changed to `SQLITE_BUSYX`, and the
   unknown op as 1019 gave three `FAULT` lines and exit 1. Empty input gave exit 1 too.
3. **The verdict and the comparison:** a copy that sets 0 where it should set 1 gave `fails` for
   every op, under both bindings. Its `varargs` lines differed from the oracle's on 30 lines.
4. **The comparison across libraries:** the floor's probe against 3.53.1's oracle differs, in
   the DQS messages and the lookaside counts. So the oracle comparison reads the library, not only
   the code.

## Results: the Mac step, on Apple arm64

Run 2026-11-17 by the maintainer, by [mac.md](mac.md), from PR #29's branch: macOS 26.7.1,
arm64 (`tarm64osx`), Chez 10.4.1. The libraries are Apple's `/usr/lib/libsqlite3.dylib` (3.51.0)
and Homebrew's 3.54.1. The files are `out/*-mac-apple-3.51.0.txt` and `out/*-mac-brew-3.54.1.txt`.
Step 3's `system.txt` didn't come back; the maintainer gave the machine's details by hand.

- **The plain binding crashes on Apple arm64, with both libraries:** "Exception: invalid memory
  reference", exit 255.
  - With Homebrew's, it crashed at its first call.
  - With Apple's, `ENABLE_LOAD_EXTENSION` came first and answered 21 on every call, leaving the
    cell untouched, as it does under the variadic binding. The crash came after it.
  - So ADR-0001's decision is measured: without `(__varargs_after 2)`, `db_config` doesn't
    receive its variadic arguments on Apple arm64. Only question 9's check can hold this on Linux.
- **`(__varargs_after 2)` works on Apple arm64.**
  - With Homebrew's, all five verdicts are `ok`.
  - With Apple's, four are `ok`. `ENABLE_LOAD_EXTENSION` fails because Apple's answers 21 to every
    call and leaves the cell untouched ([mac-d7](../mac-d7/)).
  - On both, every `varargs` line is identical to the C oracle's, compiled by the Mac's `cc`
    against each library's header.
- **The `LOOKASIDE` shape delivers its three arguments on both:** the slots used peaked at 7, 5, 7,
  and 0 when off. With a statement held at a row, a second `LOOKASIDE` answered 5.
- **Behaviour is as on Linux, but for SQL's `load_extension('x')` on Apple's.** There it fails at
  prepare, 1, "no such function: load_extension", as the OMIT build's does. On Homebrew's it
  prepares, then answers 1, "not authorized", at step, with the C call on or off. Both
  libraries' DQS messages are the longer form, as 3.53.1's are.
- **The census:**

  | | Apple's 3.51.0 | Homebrew's 3.54.1 |
  |---|---|---|
  | Options | 71 | 54 |
  | FTS5 | yes | yes |
  | `json('{}')` | `{}` | `{}` |
  | `jsonb('{}')` | blob `0C` | blob `0C` |
  | `select "x"` (DQS) | row `x` | row `x` |
  | `ENABLE_LOAD_EXTENSION` start | **21**, cell untouched | 0 |
  | `DEFENSIVE` start | **1** | 0 |
  | `DQS_DML` start | 1 | 1 |
  | `DQS_DDL` start | 1 | 1 |
  | `TRUSTED_SCHEMA` start | 1 | 1 |
  | `sqlite3_load_extension` | **missing** | present |
  | `sqlite3_enable_load_extension` | **missing** | present |
  | `sqlite3_threadsafe` | 2 | 1 |

  - Apple's lists `OMIT_LOAD_EXTENSION`, `DEFAULT_MEMSTATUS=0` and `DQS=3`, as M1 found.
  - Homebrew's lists `ENABLE_FTS5`, `ENABLE_MEMORY_MANAGEMENT`, `ENABLE_STAT4` and
    `ENABLE_API_ARMOR`, among others.
  - The lists are whole in the two `census-mac-*` files.
- **Apple's library starts `DEFENSIVE` on.** Every other library measured, six of them, starts it
  off. No option in Apple's list names it, so it's Apple's change, like its 21s.
- **The constants:** 19, against Homebrew's header, with no fault. Step 5 doesn't check Apple's
  header.
- **No Valgrind run on the Mac,** and none was asked for.

What it adds to the questions below:

- **Question 9:** the plain binding's crash is measured. A Linux check of the convention is all
  that would catch a binding that loses it.
- **Question 12:**
  - Apple's other four ops answer 0.
  - Only `ENABLE_LOAD_EXTENSION` answers 21, and question 3's opt-in never reaches that call on
    Apple's library. It has no `sqlite3_load_extension`, so the entry-point check refuses first.
- **Question 3:** Homebrew's starts `ENABLE_LOAD_EXTENSION` at 0, as upstream's defaults do, and
  Ubuntu's starts it at 1.
- **New: `DEFENSIVE`'s start differs by library.** Under question 5's answer, a connection starts
  as its library does. So on Apple's library a caller's `writable_schema` set does nothing by
  default, and on the rest it works. The maintainer answered it as question 13, [below](#the-maintainers-answers-2026-11-16).

## The questions M4's plan must settle

The maintainer answered nine of them on 2026-11-16: [the answers](#the-maintainers-answers-2026-11-16).

1. **FTS5 on CI's compiled lanes.** `build-sqlite.sh` compiles with SQLite's defaults, and so the
   `floor` and `current` lanes have no FTS5: "no such module: fts5". Guix's, Ubuntu's (the `main`
   lane), Apple's and Homebrew's all have it. The choices:
   - add `-DSQLITE_ENABLE_FTS5` to the compile line, which moves `check-sqlite.sh`'s two option
     lists, its comments ("SQLite's defaults") and the caches' keys with it;
   - or leave the lanes alone, and decide how a suite treats a library without FTS5 (question 2).
2. **A suite on a library without FTS5.** The memory check's answer to `DEFAULT_MEMSTATUS=0` is a
   precedent: the suite names the check unavailable and passes on its other checks, never
   silently (ADR-0005, amended).
   - Without FTS5 a row can still test something. It can assert the refusal's code, which
     arrives at step, not prepare.
   - It can choose the row from `sqlite3_compileoption_used("ENABLE_FTS5")`.
   - Either way, `floor` and `current` would test FTS5 nowhere unless question 1 adds it.
3. **Extension loading's starting value differs by build.** On Ubuntu's library, the `main`
   lane's, every connection opens with `ENABLE_LOAD_EXTENSION` at 1.
   - SQLite's `openDatabase` sets `SQLITE_LoadExtension` when it is compiled
     `-DSQLITE_ENABLE_LOAD_EXTENSION` (3.45.1's amalgamation), and Ubuntu's lists that option.
   - So on Ubuntu's library, a connection that never opted in can already make the C call.
   - Does `open-database` set the op on every open, 0 unless the connection opts in, and read it
     back?
   - SQL's `load_extension()` stays refused everywhere measured: "not authorized", at step. Only
     `sqlite3_enable_load_extension`, never bound, sets the flag that allows it
     (`SQLITE_LoadExtFunc`).
4. **A library without extension loading.**
   - **Telling one:** `db_config`'s answer can't tell it.
     - Upstream's `OMIT_LOAD_EXTENSION` build answers 0 and round-trips a setting that does
       nothing.
     - Apple's answered 21, `SQLITE_MISUSE`, and left the cell untouched (mac-d7). That is
       Apple's change. In 3.45.1's and 3.54.1's source, `db_config` gives 21 only from the
       API-armor check of the handle itself, and the op is in its table unconditionally.
     - So the opt-in tells by `foreign-entry? "sqlite3_load_extension"`, as ADR-0002 already
       says, or by `sqlite3_compileoption_used("OMIT_LOAD_EXTENSION")`.
   - **Testing one:** no CI lane lacks extension loading. A suite reaching the named condition on
     Linux needs either:
     - the decoy library (`tests/decoy-libsqlite3.c` already builds one without a named entry
       point, `DECOY_LACKS_<entry>`), which runs no SQL;
     - or a real build with `-DSQLITE_OMIT_LOAD_EXTENSION`, about 21 s to compile here.
5. **DQS's default.** Both kinds start on in every library measured, Apple's included. Does M4
   keep SQLite's default or turn DQS off by default, as SQLite's documentation recommends? A row
   asserts the code, 1, never the message, which changed between 3.45.1 and 3.53.1.
6. **`DEFENSIVE` hides `writable_schema` silently.** Under it, `PRAGMA writable_schema = 1`
   answers done and reads back 0. That matches M3's finding that a PRAGMA never refuses a value
   ([traps](../../traps.md)). `writable_schema` isn't in the settings list (ADR-0018), so only a
   caller's own SQL can set it. Should M4's documentation of `DEFENSIVE` say that such a set does
   nothing?
7. **`TRUSTED_SCHEMA` has two ways in.** The settings list already has a `trusted-schema` PRAGMA
   (ADR-0018), which sets the same flag.
   - Does M4 add the `db_config` op as well?
   - By the source, `db_config` expires prepared statements only when a flag changes, where the
     PRAGMA expired them on any set (M3's trap). Not measured here.
   - No behaviour row was written for it. Built-in functions aren't marked unsafe. A row needs
     an application-defined function, which v1 excludes (brief §4), or a virtual table that isn't
     innocuous in a view, such as FTS5's, which questions 1 and 2 decide.
8. **The read-back comes free.** `db_config`'s `int*` gets the state after every call, a set as
   well as a read. Measured: each set's cell held the new value on every op and library. So a set
   needs no second call, unlike ADR-0018's second statement. Does M4 hold the set's own answer, or
   read again with −1?
9. **Holding the convention on Linux.** On x86_64 the plain binding agrees with the variadic one
   everywhere, so no Linux behaviour row can tell them apart.
   - `tests/foreign-conventions.sls` and `test-conventions` have no variadic convention yet.
   - chez-curl holds it with a binder whose template carries `(__varargs_after 2)`, and a
     `check-variadic` target that removes it in a copy to watch that fail.
   - v1 needs one shape, `(db op int int*)`, for its ops. `LOOKASIDE` isn't in v1 (brief §2.8).
10. **When a set runs.** At open, inside the settings' sections, or as a verb on an open
    connection?
    - By the source, a set that changes a flag expires every prepared statement, the statement
      cache's (ADR-0020) among them. Not measured here.
    - A call made at open would sit under the open's claims, whose engine rules ADR-0018's
      amendment sets.
11. **Plain, by ADR-0011's rule.** `db_config` takes the connection's mutex and does no I/O (by
    the source), so nothing shows it waiting. Not measured.
12. **The codes to map.** Measured so far: 0; 1 for an unknown op; 21 from Apple's for
    `ENABLE_LOAD_EXTENSION`. All five ops exist at the floor, so 1 means a mistake of ours. The
    Mac step shows what Apple's answers for the other four.

## The maintainer's answers, 2026-11-16

Each was chosen from a picker whose first option was the recommendation. M4's plan builds on
them, and its slice 0 writes them into the records each one names.

| Q | Answer | What it means for M4 |
|---|---|---|
| 1 | "FTS5 on current only" | `build-sqlite.sh --current` adds `-DSQLITE_ENABLE_FTS5`. `floor` keeps SQLite's defaults, so it runs the no-FTS5 path on a real library. `check-sqlite.sh`'s `current` options and that lane's cache key move with it. Brief §2.6 is amended. |
| 3 | "Refuse in Scheme" | The load verb refuses a connection that didn't opt in, before any C call. An open that doesn't opt in makes no `db_config` call, so the library's starting value (1 on Ubuntu's) is never reached: only that verb calls `sqlite3_load_extension`. Brief §2.5 and ADR-0002 are amended to say where the guarantee lives. |
| 4 | "The decoy" | `DECOY_LACKS_sqlite3_load_extension`. A suite opens the decoy with the opt-in, asserts the named condition, and reads the call log to show that no `db_config` call was made. No real `OMIT_LOAD_EXTENSION` build. |
| 5 | "SQLite's default, settable" | Connections start with DQS on, as every library measured does. A caller turns `DQS_DML` and `DQS_DDL` off by name. |
| 6 | "Document it, with a row" | The reference for `defensive` says a caller's `PRAGMA writable_schema = 1` does nothing under it. A row asserts that the set answers done and reads back 0, and is watched failing with defensive off. |
| 7 | "PRAGMA only" | ADR-0018's `trusted-schema` stays the one way in to that flag. No `TRUSTED_SCHEMA` op: brief §2.8's three options stand. |
| 8 | "Hold the set's answer" | One call per set. The cell holds a sentinel before the call, the code is asserted, and a cell other than the value asked raises `&sqlite-setting-mismatch`. |
| 9 | "Check plus check-variadic" | `test-conventions` asserts that the binding carries `(__varargs_after 2)` in the shape `(db op int int*)`. A `check-variadic` target removes it in a copy and watches that check fail, as chez-curl's does. |
| 10 | "In the settings list" | The extension opt-in, `defensive` and the two DQS options join `open-database`'s settings list (ADR-0018) as new names, set at every open and checked by the set's own answer (Q8), with engine rows like M3 slice 5's. |

**Question 13, from the Mac step, answered 2026-11-17:** `DEFENSIVE`'s start differs by library,
1 on Apple's and 0 on the six others. The answer is **"Library's start, documented"**, the same
rule as question 5's. `defensive` is set only where a caller names it in the settings list. The
reference says Apple's library starts it on, so a caller who needs one behaviour everywhere names
it. No call is added to an open.

Not put to the maintainer:

- **Q2** follows from Q1: `floor` has no FTS5, so a suite must pass there. The precedent is the
  memory check's (ADR-0005, amended): choose the rows by `sqlite-compile-option? "ENABLE_FTS5"`,
  name FTS5 unavailable, never silently, and assert the refusal's code instead. The plan
  confirms it.
- **Q11:** plain, by ADR-0011's rule, unless the plan measures a wait.
- **Q12** waits for the Mac step.

## What a record says that a run contradicts

- **Brief §2.6, "Tests use both on every SQLite they run against":** FTS5 isn't in the `floor` or
  `current` lane's build, so no suite can use it there today. ADR-0003's consequence, "FTS5 is
  wherever the build enables it", agrees with the runs. The brief's sentence is the one that
  can't hold as the lanes are built (questions 1 and 2).
- **Brief §2.5's "Opting in turns on the C call alone" and ADR-0002's amendment, "M4 turns on the
  C call alone":** both assume the C call starts off. On the `main` lane's library it starts on,
  at every open (question 3). The rest of §2.5 holds everywhere measured: SQL's `load_extension()`
  stays refused, with the C call on or off.
- **No contradiction of ADR-0001's consequence** that a binding without `__varargs_after` works on
  x86_64 and fails on Apple arm64. It worked on every x86_64 library. On Apple arm64 it crashed,
  with both libraries (the Mac step). Linux arm64 is unmeasured.
- **mac-d7's "For M4" line** holds: Apple's answer of 21 isn't a refusal SQLite names. The
  OMIT build shows that upstream doesn't give it at all.

## Not run

- **Valgrind on the Mac:** none was asked for. Neither was the constants check on Apple's header.
- **Linux arm64:** no such machine here.
- **The C oracle and `constants.c` on Ubuntu's library:** no Ubuntu header was fetched. Its
  `varargs.sps` verdicts and Valgrind run are here.
- **A loadable extension:** out of scope, by the maintainer's choice.
