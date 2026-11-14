# M1 slice 5 mutation log: the `floor` and `current` lanes

Evidence that slice 5's checks fail through the property each claims to hold. Format of
[slice 4's log](m1-slice-4-mutation-log.md).

The slice was built in two phases.
- **Phase 1** (Opus) read the records, measured and planned. It changed no tracked file.
- **Phase 2** was three parts, each in a worktree of its own:
  - **B,** the SQLite scripts and their suite (Opus);
  - **A,** `check-floors` over `scripts/ci/` (Sonnet);
  - **C,** the workflow and `check-ci` (Sonnet).

Each part's counts are read from its suites' own output. The parts were then combined on
`m1-slice-5-lanes` and run together.

## Phase 1's open questions, as answered on 2026-11-14

1. **`check-floors` holds both floors in `scripts/ci/`,** since the global constraints already
   say CI writes none.
2. **The lanes build from the autoconf tarball.** It holds the same `sqlite3.c` and `sqlite3.h` as
   the zip, byte for byte, and needs only `tar`, an Essential package.
3. **The suite's rows shim `openssl`:** the Guix container has no SHA3-256 tool. The real digests
   are checked on the host, below, and on CI.
4. **`build-sqlite.sh` ran end to end on the host,** as a measurement.
5. **No lane builds a non-default mode** (`THREADSAFE=0` or `2`, `OMIT_AUTOINIT`). The lanes test
   SQLite's defaults.
6. **`check-floors` gains no `GITHUB_ENV` rule.** That is `check-ci`'s concern, and the gap ADR-0005
   records stands.
7. **No pins file.** The current version is written in both scripts and in the suite, and a
   mismatch fails the build's own check.

## Measured first (phase 1)

Every file fetched or built is under the slice worktree's git-ignored `build/s5/`.

### 2a. The published SHA3-256 values

Fetched on the host, from sqlite.org only, with curl's default user agent:

```
cd build/s5/pages
curl -fsS --retry 2 -o download.html          https://sqlite.org/download.html
curl -fsS --retry 2 -o releaselog_3_45_1.html https://sqlite.org/releaselog/3_45_1.html
curl -fsS --retry 2 -o releaselog_3_54_1.html https://sqlite.org/releaselog/3_54_1.html
cd ../dl
curl -fsS --retry 2 -o sqlite-amalgamation-3450100.zip https://sqlite.org/2024/sqlite-amalgamation-3450100.zip
curl -fsS --retry 2 -o sqlite-amalgamation-3540100.zip https://sqlite.org/2026/sqlite-amalgamation-3540100.zip
curl -fsS --retry 2 -o sqlite-autoconf-3450100.tar.gz  https://sqlite.org/2024/sqlite-autoconf-3450100.tar.gz
curl -fsS --retry 2 -o sqlite-autoconf-3540100.tar.gz  https://sqlite.org/2026/sqlite-autoconf-3540100.tar.gz
```

What sqlite.org publishes:

- **The floor, 3.45.1:** `https://sqlite.org/releaselog/3_45_1.html`, lines 188–189:
  `SQLITE_SOURCE_ID: 2024-01-30 16:01:20 e876e51a0ed5c5b3126f52e532044363a014bc594cfefa87ffb5b82257cc467a`
  and `SHA3-256 for sqlite3.c: 0474604df9e1b69a5544295dd046aad954749279780d557da80f44b958100295`.
  No page I could reach publishes the 3.45.1 archives' digests: the download page lists only the
  current release.
- **The current release, 3.54.1:** `https://sqlite.org/download.html`, in its machine-readable
  block (lines 206–209):
  `PRODUCT,3.54.1,2026/sqlite-amalgamation-3540100.zip,2990966,92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30`
  and `PRODUCT,3.54.1,2026/sqlite-autoconf-3540100.tar.gz,3332984,b6ced585c750916b1052667239a12c25a7ff34e7f06e1e6e01ecb0427657d9c4`.
  `https://sqlite.org/releaselog/3_54_1.html`, lines 216–217:
  `SQLITE_SOURCE_ID: 2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76`
  and `SHA3-256 for sqlite3.c: e2b869d3003b33c942b7dd7063604fbc53553e1b66609570df39b9b7b558ee81`.
  **The brief's value for the zip is confirmed:** `92281c86…8e30`.

Checked with two independent implementations, `openssl dgst -sha3-256 -r FILE` (OpenSSL 3.0.2 on
the host) and `python3 -I -c 'hashlib.sha3_256(...)'`. They agreed on every file:

| File | Size | SHA3-256 (ours) | Published | Agrees |
|---|---|---|---|---|
| `sqlite-amalgamation-3450100.zip` | 2,730,697 | `e311198775d5d5b2889d5fabe1d9a490567a14e605591d6a9e4c833804a8b4cb` | none reachable | — |
| `sqlite-autoconf-3450100.tar.gz` | 3,232,682 | `a54395aa2cf76b5b973fa420715b6108afedc4d8c0209c763fd2c1b517f8ad9f` | none reachable | — |
| its `sqlite3.c`, from either archive | 9,018,109 | `0474604df9e1b69a5544295dd046aad954749279780d557da80f44b958100295` | release log | **yes** |
| `sqlite-amalgamation-3540100.zip` | 2,990,966 | `92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30` | download page | **yes** |
| `sqlite-autoconf-3540100.tar.gz` | 3,332,984 | `b6ced585c750916b1052667239a12c25a7ff34e7f06e1e6e01ecb0427657d9c4` | download page | **yes** |
| its `sqlite3.c`, from either archive | 9,582,521 | `e2b869d3003b33c942b7dd7063604fbc53553e1b66609570df39b9b7b558ee81` | release log | **yes** |

- Both sizes on the download page match the downloads.
- **The zip and the tarball hold byte-identical sources.** For each version, `sqlite3.c` and
  `sqlite3.h` from the zip and from the tarball have the same SHA3-256. 3.45.1's `sqlite3.h` is
  `1e74881d…734a`; 3.54.1's is `15ef3f5d…2af8`.
- **The source ids in the headers match the release logs**, and so do the ones the built
  libraries answer (§2c).
- **A cross-check with slice 4:** 3.45.1's `sqlite3.c` has SHA-256
  `1a206854aa9fe0ccc1b609f5cfce67eb52ac0a8f5aa2f5e853f7c3ed84c710ab`, the `1a206854…c710ab` that
  slice 4's mutation log recorded.
- **No pin trips `check-floors`.** None of the digests, source ids or option lines below holds
  `3.45.1`, `10.4.0`, or `3045001` or `3450100` as a whole run of digits:
  `grep -E '(^|[^A-Za-z0-9])(3045001|3450100)($|[^A-Za-z0-9])|3\.45\.1|10\.4\.0'` over
  `probe/pins-and-options.txt` found nothing.

**So the floor's archive pin is our own reading, and what ties it to sqlite.org is `sqlite3.c`'s
published digest.** Hence the second sum in §1.1.

### 2b. The tools the script can rely on

| Tool | Host (Pop!_OS 22.04) | Bare `ubuntu:24.04` (local Docker image, `--network none`) | The Guix container | Only CI can confirm |
|---|---|---|---|---|
| `openssl dgst -sha3-256` | OpenSSL 3.0.2: works, agrees with Python | **absent** (`libssl3t64 3.0.13` is there, the library only) | **absent** | that the runner has the CLI after the package step, and its `-r` output format on 3.0.13 |
| `unzip` | 6.0, Priority optional | **absent** | **absent** | whether GitHub's image has it; a bare machine doesn't |
| `tar`, `gzip` | Essential | **tar 1.35, gzip 1.12, both Essential** | **absent** (not in `manifest.scm`) | — |
| coreutils `cksum -a sha3` | 8.32: no | **9.4: no** (`invalid argument 'sha3'`) | — | — |
| `python3` | yes | **absent** | absent | — |

- **Commands:** `docker run --rm --network none ubuntu:24.04 sh -c '…command -v …; dpkg-query -W …'`,
  then `cksum -a sha3` in the same image, and on the host
  `apt-cache show ca-certificates | grep Depends`.
- **`openssl` on a bare noble comes with `ca-certificates`,** already in `debian-prereqs.txt`. On
  the host's 22.04, `ca-certificates` Depends `openssl (>= 1.1.1)`. I can't read noble's metadata
  from here, so that it holds on 24.04 is inferred. The file is meant to be "the whole truth about
  a bare machine", so phase 2 lists `openssl` in it explicitly, with its reason.
- **The autoconf tarball needs nothing beyond `tar` and `gzip`, both Essential;** the zip needs
  `unzip`, a new package (Q2). Extracting only the three members took 0.06 s.
- **The container has no SHA3-256 tool at all,** so no `make test` row there can run a real
  digest. Phase 2's rows shim `openssl` (Q3).

### 2c. The flags, the builds and their compile options

**The proposed command**, one per version, run in the container through `scripts/guix-env`:

```
$CC -shared -fPIC -O2 -DSQLITE_THREADSAFE=1 -Wl,-z,defs \
    -o PREFIX/lib/libsqlite3.so.0 sqlite3.c -lpthread -lm
cp sqlite3.h sqlite3ext.h PREFIX/include/
```

Each flag and its reason:

| Flag | Reason |
|---|---|
| `-shared -fPIC` | A shared object for `load-shared-object`, named as discovery would name it. |
| `-O2` | SQLite's usual optimisation, and Ubuntu's. It changes no compile option (measured: a `-O2` build with no `-D` gave the same list). |
| `-DSQLITE_THREADSAFE=1` | Serialized: SQLite's default, Ubuntu's, and what the load needs, since it refuses 0 (ADR-0010). Written so the build depends on no default, and checked: `THREADSAFE=1` is always listed, and `sqlite3_threadsafe()` answers 1. Dropping the flag is an equivalent mutant, since the default is 1. |
| `-Wl,-z,defs` | An unresolved symbol fails the build, not a suite's load. Measured: `sqlite3.o` links under it with `-lpthread -lm`, and with no library at all on Guix's glibc. |
| `-lpthread -lm` | SQLite's documented link line. Harmless on glibc 2.34 and later, where both live in libc. |

- **No `-DSQLITE_DEFAULT_MEMSTATUS=1`.** Measured, and confirmed in the source (`ctime.c`, at
  line 21900 of 3.45.1's `sqlite3.c`): SQLite lists `DEFAULT_MEMSTATUS` only when it is not 1.
  The build with `-DSQLITE_THREADSAFE=1 -DSQLITE_DEFAULT_MEMSTATUS=1` answered exactly the same
  list as the build with no `-D` at all. So passing 1 is invisible. ADR-0005's rule, that the lane
  must not set `DEFAULT_MEMSTATUS=0`, is held by the whole-list check: slice 4's `=0` build
  listed `DEFAULT_MEMSTATUS=0`.
- **No other `-DSQLITE_*` flag.** The lanes test SQLite's defaults, compiled by us: "ours, with
  known flags" (harness plan §5). Ubuntu's build in `main` differs from ours by 22 options
  (`USE_URI`, FTS3/4/5, RTREE, SESSION, `MAX_VARIABLE_NUMBER=250000` among them). That is the
  point of having both lanes.
- **`HAVE_USLEEP` isn't needed.** Both versions use `nanosleep` unless `HAVE_NANOSLEEP=0`
  (3.45.1's line 44811), so the busy handler isn't left at one-second sleeps. That matters to
  M3's busy-timeout suites.

**Read back through the FFI**, as `report-sqlite.sh` reads, with `sqlite3_sourceid` and
`sqlite3_threadsafe` added (`build/s5/probe/read.ss`):

```
scripts/guix-env sh -c 'cd build/s5 && "$CHEZ" -q --script probe/read.ss "$PWD/lib/proposed-3450100/lib/libsqlite3.so.0"'
```

| | 3.45.1 | 3.54.1 |
|---|---|---|
| `sqlite3_libversion`, `_number` | `3.45.1`, `3045001` | `3.54.1`, `3054001` |
| `sqlite3_sourceid` | `2024-01-30 16:01:20 e876e51a…c467a`, the release log's | `2026-10-16 14:45:20 555e07ef…ca76`, the release log's |
| `sqlite3_threadsafe` | 1 | 1 |
| compile options | 37 | 38 |
| build time, `-O2`, gcc 16.2.0 | 19.3 s | 20.6 s |
| `libsqlite3.so.0` | 1,178,312 bytes | 1,252,800 bytes |

**3.45.1's whole list**, in SQLite's order:

```
ATOMIC_INTRINSICS=1
COMPILER=gcc-16.2.0
DEFAULT_AUTOVACUUM
DEFAULT_CACHE_SIZE=-2000
DEFAULT_FILE_FORMAT=4
DEFAULT_JOURNAL_SIZE_LIMIT=-1
DEFAULT_MMAP_SIZE=0
DEFAULT_PAGE_SIZE=4096
DEFAULT_PCACHE_INITSZ=20
DEFAULT_RECURSIVE_TRIGGERS
DEFAULT_SECTOR_SIZE=4096
DEFAULT_SYNCHRONOUS=2
DEFAULT_WAL_AUTOCHECKPOINT=1000
DEFAULT_WAL_SYNCHRONOUS=2
DEFAULT_WORKER_THREADS=0
DIRECT_OVERFLOW_READ
MALLOC_SOFT_LIMIT=1024
MAX_ATTACHED=10
MAX_COLUMN=2000
MAX_COMPOUND_SELECT=500
MAX_DEFAULT_PAGE_SIZE=8192
MAX_EXPR_DEPTH=1000
MAX_FUNCTION_ARG=127
MAX_LENGTH=1000000000
MAX_LIKE_PATTERN_LENGTH=50000
MAX_MMAP_SIZE=0x7fff0000
MAX_PAGE_COUNT=0xfffffffe
MAX_PAGE_SIZE=65536
MAX_SQL_LENGTH=1000000000
MAX_TRIGGER_DEPTH=1000
MAX_VARIABLE_NUMBER=32766
MAX_VDBE_OP=250000000
MAX_WORKER_THREADS=8
MUTEX_PTHREADS
SYSTEM_MALLOC
TEMP_STORE=1
THREADSAFE=1
```

**3.54.1's whole list** is 3.45.1's with two differences: `MAX_FUNCTION_ARG=1000` in place of
`=127`, and `MAX_SCHEMA=10000000` added after `MAX_PAGE_SIZE=65536` (`diff` of the two
`probe/proposed-*.txt`).

**The entries that depend on the machine:**

- **`COMPILER=gcc-16.2.0`** is `"COMPILER=gcc-" __VERSION__` (`ctime.c`, line 21862), so it
  differs between the container (gcc 16.2.0) and the runner (gcc 13.3.0, Ubuntu's `cc`, per
  `research/ci-runner/`). It is the one entry that differs between our two environments.
- **`ATOMIC_INTRINSICS=1`** comes from `GCC_VERSION>=4007000 || __has_extension(c_atomic)`
  (line 13919). It is 1 for gcc 13 and 16 alike.
- **`MUTEX_PTHREADS`** is set on Unix, and **`MAX_MMAP_SIZE=0x7fff0000`** on Linux, macOS and
  BSD. Both are fixed for CI.

**How the whole-list assertion handles `COMPILER=`:** `check-sqlite.sh` computes the expected
entry from the same compiler the build used, `${CC:-cc}`, by running SQLite's own preprocessor
test (clang first, then gcc, as `ctime.c` does) through `-E`. It then compares the whole list,
that entry included. A cache hit must never meet a different compiler, so the SQLite cache key
includes the compiler, `cc --version | head -n 1`, through a new step (§3.4). Without it, an
image update that moves gcc would leave a stale library under an unchanged key, and the check
would fail the lane, closed but falsely. The alternative, holding every entry whole but
`COMPILER=`, which would only have to match `gcc-<x.y.z>`, would need no new step; I don't
propose it.

### 2d. The suites against each built library

```
scripts/guix-env sh build/s5/probe/run-suites.sh
```

For each version that ran, from the worktree root:
`CHEZ_SQLITE3_LIBRARY=$PWD/build/s5/lib/proposed-$v/lib/libsqlite3.so.0` and
`C_INCLUDE_PATH=$PWD/build/s5/lib/proposed-$v/include:$C_INCLUDE_PATH`, then `make build && make
test`. The container's own `C_INCLUDE_PATH` is the profile's `include`, which also holds libc's
headers and Guix's 3.53.1 `sqlite3.h`, so the build's directory goes first. Before each run,
`$CC -E -M` resolved `<sqlite3.h>` to the build's own header.

| | 3.45.1 | 3.54.1 |
|---|---|---|
| `make build` | accepted: path (override), `3.45.1 (3045001)`, the release log's source id, counts all 0 | accepted: `3.54.1 (3054001)`, the release log's source id, counts all 0 |
| `make test` | **ran 25, passed 25, failed 0, hung 0** | **ran 25, passed 25, failed 0, hung 0** |
| SRFI-64 passes, summed | 1,337 | 1,337 |
| `test-constants` | 39 passed, completeness exact | 39 passed: "completeness checked against a subset only: header 3054001 is newer than the floor 3045001" |
| memory check | passed in all 5 suites that print it: "the count is back at its baseline, 0 bytes" | the same, 5 of 5 |
| time, `make build` and `make test` | 29 s | 30 s |

**No failure in either run,** so there is nothing to quote. A grep of both logs for `unexpected`,
`fail`, `unavailable`, `error` and `warning`, past the count lines, found nothing.

### 2e. How long one build takes

- **Compile, `-O2`, gcc 16.2.0, one core of an Intel Core Ultra 5 125H:** 19.3 s for 3.45.1 and
  20.6 s for 3.54.1, the same with or without the `-D` flags.
- **The rest is under a second:** each download took 0.30–0.35 s from here, the SHA3-256 of a
  3 MB archive 0.01 s, and extracting three members 0.06 s.
- **On CI it is unmeasured.** The compile is one process on one core, so the runner's core speed
  decides it; I'd expect 20–60 s. Phase 2's first CI run records it, cold and warm.
- **So the cache saves under a minute per lane per run,** against minutes for Chez. It is decided
  (item 2), and it also spares sqlite.org a download per run.


## The SQLite build and its check: `build-sqlite.sh`, `check-sqlite.sh`, `test-ci-sqlite`

Evidence that the slice's SQLite scripts fail through the property each rule claims to guard
(the slice's plan, §3.1, §3.2 and §4's steps 2 to 4; [ADR-0003](decisions/0003-sqlite-floor-3-45-1.md)
decision 3, [ADR-0005](decisions/0005-memory-gate.md), [ADR-0008](decisions/0008-floors-have-one-source.md)).
Format of [slice 4's log](m1-slice-4-mutation-log.md).

This part is:
- `scripts/ci/check-sqlite.sh PREFIX [--current]`, new: the five checks of the plan's §3.2;
- `scripts/ci/build-sqlite.sh PREFIX [--current]`, new: the plan's §3.1, from the autoconf tarball
  (Q2), with its pins keyed by role;
- `tests/test-ci-sqlite.sps`, new: 76 rows (40 for the check, 29 for the build, one for both
  scripts' execute bits, 6 preconditions);
- `packaging/debian-prereqs.txt`: `openssl`, with its reason.

The Makefile picks the suite up by its wildcard: `make test` ran 26 suites, up from 25, with no
Makefile change.

**How the mutations ran.** In the worktree itself, one at a time; the two scripts are untracked, so
each mutant was confirmed with `git diff --no-index` against a pristine copy kept in
`build/s5b/pristine/`. A driver wrote each mutant from the pristine copy and refused any edit whose
old text did not occur exactly once, or that changed nothing. Each ran through the worktree's
`scripts/guix-env`, then the pristine file was copied back and `cmp` checked it. The counts below are
read from the suite's own output (`# of expected passes`, `# of unexpected failures`), never by eye.
The driver and the runner are in the session scratchpad, not the repository. Every mutant exited 1.

## Measured first (Guix container: Chez 10.4.0, gcc 16.2.0, GNU diff 3.12)

- **`gcc -E` puts a system header's macro expansion on lines of its own.** A marker line after
  `#include <sqlite3.h>`, `chez_sqlite3_version SQLITE_VERSION`, came out as
  `chez_sqlite3_version ` with nothing after it. The value followed on the next line, after a
  linemarker `# 3 "header.c" 3`. `C_INCLUDE_PATH`'s directories count as system ones. `-E -P`
  kept the line whole. `-dM -E` listed `#define SQLITE_VERSION "3.53.1"` directly. So the check reads
  the header's three macros with `-dM -E`, and runs its compiler test with `-E -P`.
- **`-M` lists a `C_INCLUDE_PATH` header, `-MM` does not:** mutant K17 below, which fails 30 rows.
- **GNU diff shows two adjacent lines swapped as `-d`, ` e`, `+d`:** it keeps the second line. The
  swap row accepts that and the other minimal diff, which keeps the first, since another diff may
  choose it.
- **The container has no `openssl`, `tar`, `gzip` or `curl`,** as phase 1 found. So the build rows
  run on shims, and the real digests ran on the host (below).

## The red runs

Each part of the suite was written first, then run against a stub `scripts/ci/check-sqlite.sh` or
`build-sqlite.sh` that ran `exit 0`, then one that ran `exit 1`.

| Rows | Stub | Passed | Failed |
|---|---|---|---|
| the check's 40 (suite of 45) | `exit 0` | 5 | 40 |
| | `exit 1` | 5 | 40 |
| the build's 29 (suite of 75) | `exit 0` | 46 | 29 |
| | `exit 1` | 46 | 29 |
| the execute bits (suite of 76) | `check-sqlite.sh` at mode 644 | 75 | 1: `("scripts/ci/check-sqlite.sh" . 1)` |
| | `build-sqlite.sh` at mode 644 | 75 | 1: `("scripts/ci/build-sqlite.sh" . 1)` |

- **The rows that passed against a stub are the preconditions:** CHEZ is set; CC is one word; CC's
  macros give a COMPILER= entry; the copies hold 37 and 38 lines; the COMPILER= row has an entry to
  change; sh is a file on PATH.
- **Every row of each part failed against both stubs.** The pass rows assert the whole stdout, so
  no stub can pass them.
- **The execute-bit row came last.** Both new scripts were first written at mode 644, while CI runs
  each by its name. With `check-sqlite.sh` at 644, the 75 rows before it passed: 75 passed, 0
  failed. The script was set to 755, and the row added.
- **First green runs:** the check's rows passed 45 of 45 on the script's first run; with the build's,
  75 of 75 on its first run. Final: 76 of 76.

## The mutations

The baseline is 75, the suite before the execute-bit row, which reads no script's text. A mutation
counts as caught when at least one row failed. **39 mutations: every one was caught.**

### `check-sqlite.sh` (K1 to K15 are the plan's; K12a and K14b to K18 are added)

| Mutation | Guards | Failed |
|---|---|---|
| K1 | the library's version compared whole: a prefix match, `${lib_version#"$version"}` | 1: 8.1.23 |
| K2 | the number checked: dropped | 1: the number one more |
| K3 | the source id checked: dropped | 1: the source id one character off |
| K4 | `sqlite3_threadsafe()` is 1: unchecked | 2: answers 0, answers 2 |
| K5 | the options compared whole: as a subset, the expected lines among the library's | 4: `DEFAULT_MEMSTATUS=0` added, one added first, one added last, two swapped |
| K6 | as a superset, the library's lines among the expected | 4: the first, a middle and the last dropped; two swapped |
| K7 | in order: compared as sorted sets | 1: two swapped |
| K8 | the COMPILER= entry held: removed from both lists | 1: `COMPILER=gcc-0.0.0` |
| K9 | COMPILER= computed from CC: written as `gcc-13.3.0` | 14: all four passes, every options row |
| K10 | the override is exactly PREFIX's library: both tests made `true` | 3: unset, relative, a copy elsewhere |
| K11 | the compiler finds PREFIX's header: unchecked | 2: the decoy alone on `C_INCLUDE_PATH`, the decoy first |
| K12 | the header's identity: the refusal skipped | 5: the header's three rows; `--current` on the floor's header (refused at the library instead); the env row |
| K12a | `SQLITE_VERSION` alone unchecked. This was the first K12: `if false && A \|\| B \|\| C` binds as `(false && A) \|\| B \|\| C`, so it disabled only A | 1: the header's 8.1.3 |
| K13 | `--current` reads no floors file: it runs `floor.sh` first | 5: the `--current` pass with no floors file, three `--current` refusals (each now `floor.sh`'s), the build's `--current` row |
| K14 | the env moves no version: `current_version=${current_version:-3.54.1}` | 1: `--current` with `current_version` and `version` set to the floor's |
| K14b | the same, for the floor: `version=${version:-$(sh floor.sh …)}` | 1: the floor with `version=8.1.3` and the rest in the env |
| K15 | `--current` expects its own options: the floor's list | 3: both `--current` passes, the current identity with the floor's 37 options (now passes) |
| K16 | 1 exactly: `!= 0` | 1: answers 2 |
| K17 | `-M`: `-MM` | 30: every row that reaches check 3, and the build's two rows that do |
| K18 | `SQLITE_VERSION_NUMBER` alone unchecked | 1: the header's number |

### `build-sqlite.sh` (B1 to B12 are the plan's; B9b and B13 to B18 are added)

| Mutation | Guards | Failed |
|---|---|---|
| B1 | the floor read through `floor.sh`: written as a constant | 11: every floor row with 8.1.2 or 8.12.3 that gets past the arguments. The real floors file's row passes, as it must |
| B2 | `--current` reads no floors file | 5: every `--current` row with no floors file |
| B3 | the env moves no version: `version=${version:-…}` | 1: the env row |
| B4 | the number padded: `printf '%d%d%d00'` | 18: every row that reaches the download |
| B5 | the archive's digest before `tar`: `tar` moved first | 10: every row past the download (each call log has `tar` second) |
| B6 | the archive's digest checked: `true \|\|` | 3: the wrong archive, the env's `floor_archive`, `--current` with the floor's digest |
| B7 | `sqlite3.c`'s digest checked | 2: the wrong `sqlite3.c`, for each role |
| B8 | `--current` uses its own pins: the floor's | 3: the three `--current` rows past the download |
| B9 | the plan's flags: `-Wl,-z,defs` dropped | 5: every row that reaches the compile (its argv, whole) |
| B9b | `-DSQLITE_THREADSAFE=1` dropped | 5: the same rows. At the options level this mutant is equivalent: SQLite's default is 1, and phase 1's `defaults-*` builds, made with no `-D` flag at all, pass `check-sqlite.sh` (below) |
| B10 | exactly three members unpacked: the whole tarball | 7: every row from `tar` on (the shim then makes nothing, so `sqlite3.c`'s digest fails too) |
| B11 | `check-sqlite.sh` runs at the end: not called | 5: every row that reaches the compile (exit 0 and the "built into" line) |
| B12 | the tools named before any download: after it | 5: every missing-tool row (each call log holds `curl`) |
| B13 | `--current`'s check is `--current`: dropped | 1: `--current` with no floors file (the check then fails at `floor.sh`) |
| B14 | the check gets `C_INCLUDE_PATH`: dropped | 2: the two rows where cc writes the library (the check's compiler call shows no `C_INCLUDE_PATH`) |
| B15 | the check gets `CHEZ_SQLITE3_LIBRARY`: dropped | 2: the same two (the check refuses the override unset) |
| B16 | `C_INCLUDE_PATH` prepended, not replaced | 1: `C_INCLUDE_PATH` in the env |
| B17 | the work directory removed: no trap | 18: every row that reaches `mktemp` (`tmp/` left non-empty) |
| B18 | `--current` uses its own year: the floor's | 7: every `--current` row that reaches the download |

**Before B13 was written,** a hand reading of the rows found that the `--current` build row passed
whether the check got `--current` or not: check 1 refuses the missing library the same way for both
roles. The row now runs in a tree with no floors file, so a check without `--current` fails at
`floor.sh`. B13 shows the fix.

## By hand, on real libraries (in the container)

The check, run from the worktree root, so the real floors file gives the floor:

```
scripts/guix-env sh -c 'sh build/s5b/probe/byhand.sh PREFIX[:current]...'
# byhand.sh runs, for each PREFIX:
env -u CPATH CHEZ_SQLITE3_LIBRARY="$prefix/lib/libsqlite3.so.0" C_INCLUDE_PATH="$prefix/include" \
  sh scripts/ci/check-sqlite.sh "$prefix" [--current]
```

**Step 2, on phase 1's builds** (`build/s5/lib/`), and three bad 3.45.1 builds made with the plan's
line changed by one flag each (`build/s5b/probe/bad-builds.sh`, 21 s for three in parallel):

| Library | As | Exit | What it printed |
|---|---|---|---|
| `proposed-3450100` | the floor | 0 | `… is SQLite 3.45.1 (3045001), source id 2024-01-30 16:01:20 e876…c467a: the SQLite floor`, 37 options (equal to phase 1's `proposed-3450100.txt`), the header line |
| `proposed-3540100` | `--current` | 0 | `… 3.54.1 (3054001) … 555e…ca76: the pinned current SQLite`, 38 options |
| `defaults-3450100` (no `-D`) | the floor | 0 | the same as `proposed-3450100`: the equivalence of B9b |
| `defaults-3540100` (no `-D`) | `--current` | 0 | the same as `proposed-3540100` |
| `-DSQLITE_DEFAULT_MEMSTATUS=0` | the floor | 1 | `…'s compile options are not the 37 of the SQLite floor, line for line:`, then `@@ -4,6 +4,7 @@` with `+DEFAULT_MEMSTATUS=0` alone |
| `-DSQLITE_THREADSAFE=0` | the floor | 1 | `… answers 0 to sqlite3_threadsafe(), but a lane's SQLite must answer 1: serialized, SQLite's default` |
| `-DSQLITE_THREADSAFE=2` | the floor | 1 | `… answers 2 to sqlite3_threadsafe(), …` |
| `proposed-3540100` | the floor | 1 | `…/include/sqlite3.h defines SQLITE_VERSION "3.54.1", SQLITE_VERSION_NUMBER 3054001 and SQLITE_SOURCE_ID "2026-10-16 …", but the SQLite floor is "3.45.1", 3045001 and "2024-01-30 …"` |
| `proposed-3450100` | `--current` | 1 | the same, the other way |
| Guix's 3.53.1, `$GUIX_ENVIRONMENT` | the floor, and `--current` | 1, 1 | the header's `"3.53.1"`, 3053001, `"2026-05-05 10:34:17 c88b…e9"` against each role's |

**Step 4, again, through `build-sqlite.sh`'s own lines** (`build/s5b/probe/exact-builds.sh`). The
probe reads the compile command and the `cp` line out of the script with `sed`, and `eval`s them.
The bad builds are the same lines with one `sed` edit each. Five builds in parallel took 28 s. Every
row of the table above came out the same, plus two more:

| Library | As | Exit | What it printed |
|---|---|---|---|
| Guix's 3.53.1 library behind the floor's own header | the floor | 1 | `… answers "3.53.1", 3053001 and "2026-05-05 …" to sqlite3_libversion(), sqlite3_libversion_number() and sqlite3_sourceid(), but the SQLite floor is "3.45.1", 3045001 and "2024-01-30 …"`: the library check, on a real library |
| the floor's build with the container's own `C_INCLUDE_PATH` | the floor | 1 | `…/bin/gcc finds <sqlite3.h> at /gnu/store/…-profile/include/sqlite3.h, not …/exact/floor/include/sqlite3.h: C_INCLUDE_PATH must name …/exact/floor/include first, …` |

## The host run (decision 4)

`build-sqlite.sh` ran end to end on the host (Pop!_OS 22.04), reaching sqlite.org only, writing only
under `build/s5b/host/`. `/bin/sh` is dash there, so both scripts ran under a second shell.

```
sh build/s5b/probe/host-run.sh "$PWD" "$HOME/.guix-home/profile/bin/scheme"
# each run:
env -u CHEZ_SQLITE3_LIBRARY -u C_INCLUDE_PATH -u CPATH -u CC \
  HOST_CALLS=… PATH="build/s5b/host/wrap:$PATH" TMPDIR=build/s5b/host/tmp CHEZ=~/.guix-home/profile/bin/scheme \
  sh scripts/ci/build-sqlite.sh PREFIX [--current]
```

- **The tools:** `curl` from the Guix home profile, `/usr/bin/openssl` (OpenSSL 3.0.2), `/usr/bin/tar`,
  `/usr/bin/cc` (gcc 11.4.0), dash. **The Chez:** the Guix home profile's `scheme`, 10.4.0. It loaded
  the host-built library with no complaint. Each of `curl`, `openssl` and `tar` was wrapped: the
  wrapper logs its call, then `exec`s the real tool.

| Run | Exit | Time | Calls | What it printed |
|---|---|---|---|---|
| the floor | 0 | 14 s | `curl` of `https://sqlite.org/2024/sqlite-autoconf-3450100.tar.gz`, `openssl` of it, `tar` of the three members, `openssl` of `sqlite3.c` | the check's three lines and its 37 options with `COMPILER=gcc-11.4.0`, then `build-sqlite.sh: SQLite 3.45.1 built into …/host/floor` |
| `--current` | 0 | 14 s | the same for `https://sqlite.org/2026/sqlite-autoconf-3540100.tar.gz` | 38 options with `COMPILER=gcc-11.4.0`, then `… SQLite 3.54.1 built into …/host/current` |
| a copy with `floor_archive`'s last digit `f` made `e` | 1 | 1 s | `curl`, then `openssl` of the archive: **no `tar`** | `build-sqlite.sh: sqlite-autoconf-3450100.tar.gz has SHA3-256 a54395aa…8ad9f, but floor_archive in this script pins a54395aa…8ad9e`. No prefix was made |

- **The real `openssl dgst -sha3-256 -r` agreed with all four pins,** the archive's and `sqlite3.c`'s
  for each role.
- **The host's floor build lists the container's 37 options but one:** `COMPILER=gcc-11.4.0` in
  place of `gcc-16.2.0`, which the check computed from the host's compiler.
- **`tmp/` was empty after each run:** the trap removed each work directory.

## The memory gate

- **Its children run ungated, as `test-check-floors`' `check-chez.sh` rows do.** They are sh, the
  compiler, the shims and, through `check-sqlite.sh`, a Chez that runs the script's own probe on a
  stub. None reaches chez-sqlite3's code. And a shell cannot run under the gate: a child log's
  `Command:` must be Chez or the oracle.
- **`make test-memory MEMORY_SUITES=tests/test-ci-sqlite.sps`:** passed, 25.0 s wall in the container
  (with 75 rows; plain, the suite takes 6.4 s). The log shows 0 errors from 0 contexts, nothing
  definitely, indirectly or possibly lost, 168 bytes in 3 blocks still reachable, and no child log.
  Rerun with the 76th row: passed, 76 passes, 0 errors.

## The clean rerun (in the container, after the last mutation was restored)

```
make test:  check-suites: every suite ends with (exit (suite-exit-status runner)) (26 checked)
            check-seam: the seam holds (15 libraries in 15 files checked)
            check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, sqlite 3.45.1)
            check-ci: .github/workflows/ci.yml has the one shape check-ci reads
            tests/test-ci-sqlite.sps: # of expected passes 76
            test: ran 26, passed 26, failed 0, hung 0
make test-memory MEMORY_SUITES=tests/test-ci-sqlite.sps:  test-memory: ran 1, passed 1, failed 0, hung 0
make check-test-fails:  check-test-fails: make test failed, as it must, in all 12 cases
make check-clean:       check-clean: ok: make clean removes build/, follows no link out of it, changes nothing else, passes again, and make deps works after it
make check-dev:         check-dev: ok: in a fresh copy, make dev runs deps and build, then a REPL with the suites' library path and build's libsqlite3; a refused libsqlite3 stops it
```

`check-test-fails`, `check-clean` and `check-dev` ran with the 75-row suite. None runs
`test-ci-sqlite`, and the scripts were the same. After every mutation run, `build-sqlite.sh`'s header
comment was corrected: it read "It reads no other variable", but the script also reads TMPDIR and
`C_INCLUDE_PATH`. That was a comment-only diff. `make test` then ran once more, with the same lines:
`test: ran 26, passed 26, failed 0, hung 0`, and `test-ci-sqlite` passed 76.

**`check-floors`' rule, by hand** (the plan's §2a regex):
`grep -n -E '(^|[^A-Za-z0-9])(3045001|3450100)($|[^A-Za-z0-9])|3\.45\.1|10\.4\.0'` found nothing in
`scripts/ci/build-sqlite.sh`, `scripts/ci/check-sqlite.sh` or `packaging/debian-prereqs.txt`. Over all
of `scripts/ci/` it finds the two lines that were there before: `floor.sh:5`'s comment, `"10.4.0"`,
and `build-chez.sh:57`'s pin key, `10.4.0)` (Q1's).

## Not covered

- **The shims ran under the container's sh alone** (bash). Both scripts ran under dash on the host,
  and `dash -n` passed both. No row ran on macOS. Its `diff` is assumed to write a single change as
  GNU's does. The swap row is the one with two minimal answers, and it takes either.
- **What a real `tar`, `openssl` and `curl` do is not in `make test`:** the container has none (Q3).
  The host run is the evidence, and CI's first run will be the second.
- **The suite does not hold that the copies of the pins and options match the script's,** except
  through behaviour: the base rows pass only if they agree, and K9 and K15 show a changed list
  failing.
- **A runner mistake during the mutations:** the runner copied every file of a mutant's directory
  into `scripts/ci/`. On the K rerun, that included the previous run's `suite.log`. It sat in
  `scripts/ci/` during that rerun and one `make test`, then was found by `git status`, removed, and
  the runner fixed (`*.sh` only). No script reads it. The K rerun was repeated with the fixed runner
  (the counts above, unchanged), and the clean rerun came after.

## Part A: `check-floors` reads `scripts/ci/` (ADR-0008, amended)

Built test first in `/home/kishu/src/chez-sqlite3-wt-s5a` (branch `m1-s5-part-a`), through its own
`scripts/guix-env`. Counts are read from the suite's own output (`# of expected passes`,
`# of unexpected failures`); each mutation was applied by a one-shot edit that died unless its old
text occurred exactly once, its landing checked with `diff` against a snapshot of the three files it
touches, then reverted from the snapshot (the three files were `cmp`-clean again before the final
runs). The suite is `tests/test-check-floors.sps`.

### What the rows guard

- **Pure `scripts-problems` on texts (`scripts: ...`):**
  - the SQLite floor's dotted text, and the Chez floor's, at the start, middle and end of a line;
  - each numeric form at the same positions;
  - the first, a middle and a last line with no newline;
  - the boundary against its whole complement (`scripts boundary:`, four rows, U+0001 to U+007F but
    newline plus four beyond ASCII, each form, each side);
  - a hex digest, a form past an unfound one, a form twice (named once);
  - the fixtures' floors found and the real ones (3.45.1, 10.4.0) not, and 3.46.0's found from another
    floors file;
  - the YAML rules do not apply: `"\x38"`, an odd quote, and floor.sh's own three lines that
    hold them (hand-copied) each report nothing;
  - every file: a subdirectory, a hidden file, a file with no `.sh`, files in path order whatever
    order they come in; no file; no `floor.sh`; `floor.sh` only in a subdirectory; names that only
    look like it; an unreadable (`#f`) floor.sh is no missing floor.sh.
- **The program (`program: ...`):** fixtures `scripts-sqlite-literal` (lib/fetch.sh),
  `scripts-sqlite-number` (a hidden `.pins`), `scripts-chez-literal`, `scripts-no-floor-sh`,
  `scripts-self-link`; every older case now takes the shared clean scripts directory
  `legal/scripts`, whose floor.sh holds a backslash after a double quote and odd quotes. Also:
  SCRIPTS missing, a file, empty, and the usage rows at three and five arguments.
- **`build-chez.sh` and `floor.sh` (`scripts/ci: build-chez.sh: ...`):** with a fake `curl` first on
  the PATH: the real floor reaches its URL (and `--nothreads` the same); a floor of 9.9.9 reaches
  `.../v9.9.9/csv9.9.9.tar.gz`; a tarball that is not the pinned one fails its sum, naming both; the
  env cannot move the version; a malformed floor, a floor twice and no floors file fail before any
  download; the usage rows and the relative prefix.
- **`check-test-fails.sh`'s `floors-script` case:** a plant `scripts/ci/plant.sh` writing the SQLite
  floor, `make test` must fail on check-floors' lines, whole, and no suite runs.

### The red runs

| Run | Passed | Failed |
|---|---|---|
| The pure and program rows, against `scripts-problems` as a stub answering `()` and today's three-argument program | 301 | 77 |
| The same rows against the real code | 378 | 0 |
| The `build-chez.sh` rows added, against today's `build-chez.sh` and `floor.sh` | 387 | 3 |
| After the `build-chez.sh` and `floor.sh` change | 390 | 0 |

The three red rows were the 9.9.9 floor reaching its URL, its sum failing, and the env row: today's
script fails "no sha256 is pinned for Chez 9.9.9". The other nine `build-chez.sh` rows passed at once:
they are guard rows for code that was already right, as chez-curl's were. The rows that report nothing
(the YAML-exemption rows, the real floors, the hex digests) passed against the stub, which is the
vacuous direction: S1 to S13 are what hold them. `make check-floors` on the real tree against the new
rule, before the `build-chez.sh` and `floor.sh` change, named exactly the two lines (build-chez.sh
line 57, floor.sh line 5) and `FAILED (problems: 2)`.

### Mutations

| # | Mutation | Passed | Failed | What failed |
|---|---|---|---|---|
| S1 | scripts read, not compared (`scripts-problems` call replaced by `()`) | 385 | 5 | program rows scripts-sqlite-literal, scripts-sqlite-number, scripts-chez-literal, scripts-no-floor-sh, empty scripts directory |
| S2 | version number skipped for scripts only | 377 | 13 | the version-number rows at three positions, the mixed rows, boundary rows left and right |
| S3 | amalgamation number skipped for scripts only | 380 | 10 | the amalgamation rows, the mixed rows, the first/last-line row, boundary rows |
| S4 | dotted text skipped for scripts only (both floors) | 355 | 35 | every dotted row, the program rows that name one |
| S5 | backslash-after-quote rule applied to scripts | 358 | 32 | 4 pure rows and every passing program case (the clean floor.sh holds a backslash after a quote); `make check-floors` on the real tree exit 2, naming build-chez.sh:71, check-action-pins.sh:67 and :109, floor.sh:61 and :62 among others |
| S6 | odd-quote rule applied to scripts | 359 | 31 | 3 pure rows and every passing program case; `make check-floors` on the real tree exit 2 |
| S7 | subdirectories not walked (the walk is shared with the workflows) | 388 | 2 | program rows workflows-nested and scripts-sqlite-literal |
| S8 | a linked SCRIPTS followed (the check is shared with the workflows) | 388 | 2 | program rows workflows-self-link and scripts-self-link |
| S9 | an empty SCRIPTS passes | 388 | 2 | the pure "no file at all" row and the program's empty scripts directory |
| S10 | no `floor.sh` passes | 386 | 4 | three pure rows (no floor.sh, subdirectory only, look-alike names) and program scripts-no-floor-sh |
| S11 | boundary loosened for scripts only (a letter beside a form counts) | 384 | 6 | the hex-digest row, the neighbours row, and the four boundary rows |
| S12 | Makefile passes `.github/workflows` twice, not `scripts/ci` | `check-test-fails`: 5 ok | 8 cases FAILED | fails, no-tests, hangs, leaks, floors, floors-script, ci, no-suites: check-floors itself fails ("it holds no floor.sh") in a tree that has none |
| S12b | Makefile passes a clean fixture scripts directory, which the real check-floors passes | `check-test-fails`: 12 ok | 1 case FAILED | floors-script alone ("make test exited 0"): this is the case's own proof |
| S13 | the Chez floor not held in scripts | 378 | 12 | the Chez rows at three positions and in a case pattern, the longer-number row, the both-floors rows, the program row scripts-chez-literal |

Mutations S7 and S8 edit code the workflows share, so they fail the workflows' rows too; the
scripts' rows are the second row named. S11 is confined to scripts: the loosened scan is used only
under the scripts' message, so no workflow row moves.

### The clean rerun

After the 14 reverts: `make test`: `test: ran 25, passed 25, failed 0, hung 0`;
`make check-test-fails`: `make test failed, as it must, in all 13 cases`; `make check-clean`: ok.
`tests/test-check-floors.sps`: 390 passes, 0 failures.

## Slice 5, part C: `check-ci` holds the `floor` and `current` jobs

Each mutation edited `tests/check-ci.sh` in place, ran `tests/test-check-ci.sps` through the
container, then restored the file from a clean copy (`cmp` confirmed). Each edit was diffed against
the clean copy to confirm it landed where intended. Counts are the suite's own `# of expected passes`
and `# of unexpected failures`. Clean suite: 357 passed, 0 failed.

### The red runs

| Run | Result |
|---|---|
| New `ci.yml` against the old `check-ci` | 14 problems: `floor` and `current` unknown jobs, and 12 lines naming the two names |
| New suite against the old `check-ci` | 7 passed, 350 failed |

The 7 that passed against the old script: the file-is-there row, `no jobs key` (the old script already
refuses those lines), `ci.yml is a link`, and the four argument/directory rows. All new rows failed.
The old script also fails the unedited new file, so every row fails red for that reason too; the
meaningful red evidence is the mutations below.

### Mutations

| # | Guards | Mutation | Passed | Failed | Failing rows (first) |
|---|---|---|---|---|---|
| L1 | `main` tests discovery | names allowed on an env line of `main` | 355 | 2 | main's install check gains either name |
| L2 | names only as env keys | names allowed on any line of the lanes | 347 | 10 | run block, GITHUB_ENV, step name, with value, run line, in both lanes |
| L3 | env values exact | value comparison removed | 347 | 10 | CHEZ swaps (main, nothreads), library other lane's, second include dir, relative library |
| L4 | three steps carry both keys | `needenv` for the two keys removed | 351 | 6 | make test without include path, make build without library, check without env, both lanes |
| L5 | SQLite if only on its build and save | SQLite if allowed on the Chez build | 355 | 2 | the SQLite if on the Chez build, both lanes |
| L6 | SQLite key held whole | key's tail not held | 355 | 2 | the key has a tail, both lanes |
| L7 | each lane its own key | either lane's key accepted | 355 | 2 | the other lane's whole key, both lanes |
| L8 | job list | missing `floor` not named | 356 | 1 | the floor job deleted |
| L9 | check before make build | order not enforced for make build | 355 | 2 | the check after make build, both lanes |
| L10 | `--current` only in `current` | `--current` accepted on the check line | 356 | 1 | floor: the check with --current |
| L11 | no if on make test | if allowed on make test | 351 | 6 | always(), SQLite if, Chez if on make test, both lanes |
| L12 | lanes' checkout | first-step check dropped for lanes | 353 | 4 | checkout without submodules or false, both lanes |
| L13 | build step carries its if | "has no if" not reported in lanes | 355 | 2 | the SQLite build without its if, both lanes |

L13's first attempt dropped the `if` requirement and the allowance together, so the unedited file
failed (7 passed, 350 failed); it was redone as above.

### Clean rerun

`tests/test-check-ci.sps`: 357 passed, 0 failed. `make test`: ran 25, passed 25, failed 0, hung 0.
`check-action-pins`: 19 lines. `check-floors`: passes.

### Not mutated

- Rows for `id: cc`, the path rules and the wrong-step rule were each watched failing red (old script)
  but have no named mutation.

## The parts combined

The three parts' commits were combined on `m1-slice-5-lanes` and rebased onto `main` at
`2579a0d`. Every run below went through the worktree's `scripts/guix-env`:

- `make check-suites`: 26 checked.
- `make check-floors`: `README.org, .github/workflows (ci.yml) and scripts/ci (build-chez.sh,
  build-sqlite.sh, check-action-pins.sh, check-chez.sh, check-sqlite.sh, floor.sh,
  report-sqlite.sh) hold the floors`. That is the new rule, over the new scripts.
- `make check-ci`: the one shape.
- `make test`: `ran 26, passed 26, failed 0, hung 0`.
- `make check-test-fails`: all 13 cases.
- `make check-clean` and `make check-dev`: ok.
- `check-action-pins.sh`: 19 lines.

The caller also ran three mutations of their own, each in a copy of a part's tree and each
caught:
- Part A's walk skipping hidden files: 389 passed, 1 failed.
- Part C's check step no longer required to carry the two SQLite env keys: 355 passed, 2 failed.
- Part B's threadsafe test accepting 2: 75 passed, 1 failed.
