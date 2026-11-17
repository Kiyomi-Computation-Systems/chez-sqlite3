# Research: M4's plan, `db_config` at open, extension loading, FTS5 and JSON

Written and run 2026-11-17, for [the M4 plan](../../2026-11-17-m4-plan.md), on `main` at
`e590fdc`. Every run was in the Guix container: Chez 10.4.0 (`ta6le`, threaded), gcc 16.2.0,
Valgrind 3.27.0, x86_64, so every fact here is Linux's: where Apple's differs by SQLite's source
or Apple's documentation, the text says so, and nothing here measured it. Nothing here ships. The
pre-work's measurements, the variadic binding and the census, are
[research/m4-prework/](../m4-prework/README.md), cited here as "pre-work". The plan's read-only
review (Opus) wrote three probes of its own; they are here, credited "M4's plan review", rerun
here twice before anything cites them.

## The files

| File | What it is |
|---|---|
| [d1-db-config-open.c](d1-db-config-open.c) | `sqlite3_db_config`'s four v1 ops on a fresh connection: expiry, the error state, a lock, the connections an open makes |
| [l1-load-extension.c](l1-load-extension.c) | `sqlite3_load_extension`, called as v1's verb would call it; an optional last argument names the files' suffix, `so` when not given ([research/m4-mac/](../m4-mac/README.md)) |
| [ext.c](ext.c) | The smallest loadable extension, in four variants by `-D` |
| [noentry.c](noentry.c) | A shared object with no entry point SQLite looks for |
| [f1-fts5-json.c](f1-fts5-json.c) | What an FTS5 suite and a JSON suite would assert |
| [run.sh](run.sh) | Builds and runs the three C probes on each library |
| [x1-ffi-load.sps](x1-ffi-load.sps) | The load through Chez's FFI: under the gate, and on a FIFO, plain and `__collect_safe`; the same optional suffix |
| [run-x1.sh](run-x1.sh) | Runs `x1-ffi-load.sps` on one library |
| [rv1.c](rv1.c) | M4's plan review's: a failed load's error state after an earlier error; a replacing load beside a held row; ADR-0018's six PRAGMAs with the ops at their start and changed |
| [rv2.sps](rv2.sps) | M4's plan review's: what `raise-sqlite-error` does with the connection's code after a refused set |
| [rv3.c](rv3.c) | M4's plan review's: a bare name, from another working directory, with and without `LD_LIBRARY_PATH` |
| [run-review.sh](run-review.sh) | Runs the review's three, and `check-sqlite.sh --current` on both 3.54.1 builds |
| [out/](out/) | Every output, whole, by probe and library label; timings in `*-timing-*` files |

The C probes follow M3's slice-0 probes: each is compiled against its library's own header and
linked to that library by path, with an rpath, and refuses to run unless the runtime version
number and source id equal the header's. Every connection opens as chez-sqlite3 opens one,
`READWRITE | CREATE | EXRESCODE | FULLMUTEX`, unless a case says otherwise. No call with a side
effect stands beside another in one argument list. `x1-ffi-load.sps` is standalone, as the
pre-work's probes are: it loads the library with `load-shared-object` and none of chez-sqlite3's
libraries, and passes no Scheme object to C (ADR-0011).

## How to rerun it

From the worktree's root, with the libraries below in place:

```
scripts/guix-env sh -c 'd=$(mktemp -d "$PWD/build/m4plan/run.XXXXXX") && \
  sh .plans/research/m4-plan/run.sh "$d" "$d/out"'
scripts/guix-env sh -c 'g=$(readlink -f "$CHEZ_SQLITE3_LIBRARY"); i=$(dirname "$(dirname "$g")")/include
  for l in "guix-3.53.1 $CHEZ_SQLITE3_LIBRARY $i" \
           "floor-3.45.1 $PWD/build/m3-floor/lib/libsqlite3.so.0 $PWD/build/m3-floor/include" \
           "current-3.54.1 $PWD/build/m4plan/current/lib/libsqlite3.so.0 $PWD/build/m4plan/current/include"; do
    set -- $l; d=$(mktemp -d "$PWD/build/m4plan/x1.XXXXXX")
    sh .plans/research/m4-plan/run-x1.sh "$d" "$1" "$2" "$3" "$PWD/build/m4plan/x1out"; done'
scripts/guix-env sh -c 'make deps && d=$(mktemp -d "$PWD/build/m4plan/review.XXXXXX") && \
  sh .plans/research/m4-plan/run-review.sh "$d" "$PWD/build/m4plan/review-out"'
```

`run.sh` takes about 15 s, most of it D4's 1500 ms wait and the compiles; `run-x1.sh` about 4
minutes a library, most of it Valgrind; `run-review.sh` about 10 s.

**Every C probe ran twice from fresh scratch, on every library,** and all 10 outputs that aren't
timings matched byte for byte. `x1-ffi-load.sps`'s `gate` and `gate-leak` modes ran three times
on Guix's library and the floor and twice on 3.54.1, and its `gate-none` mode once on each, every
non-Valgrind output the same each time; its FIFO modes, once their race was fixed (below), three
times on the first two and twice on 3.54.1. **`run-review.sh` ran twice,** and its 9 outputs
matched byte for byte, and rv1's matched the review's own outputs. The outputs here are the last
run's.

## The libraries

| Label | Library | How it was obtained |
|---|---|---|
| `guix-3.53.1` | The container's | The profile's, as `CHEZ_SQLITE3_LIBRARY` names it (ADR-0006) |
| `floor-3.45.1` | `build/m3-floor` | CI's `floor` lane build, from M3 (sha256 `a36320cb…`) |
| `current-3.54.1` | `build/m4plan/current` | `sqlite-autoconf-3540100.tar.gz`, downloaded on the host. Its SHA3-256 and its `sqlite3.c`'s matched `build-sqlite.sh`'s `current_archive` and `current_source` pins. Compiled in the container with `build-sqlite.sh`'s line. `check-sqlite.sh --current` passed on it, 38 options ([out](out/check-sqlite-current-3.54.1.txt), written by `run-review.sh`) |
| `current-fts5-3.54.1` | `build/m4plan/current-fts5` | The same source and line, plus `-DSQLITE_ENABLE_FTS5`: the `current` lane as Q1's answer builds it |

## Results: `db_config` at open (D1)

[out/d1-db-config-open-*.txt](out/). Alike on all three libraries but for their version lines and
one DQS message, below.

- **D1. A set that changes a flag expires the connection's other statements; one that changes
  nothing doesn't.** A `PERSISTENT` SELECT, run to done and reset, re-prepared once at its next
  run after `ENABLE_LOAD_EXTENSION` 0 → 1, `DEFENSIVE` 0 → 1, `DQS_DML` 1 → 0 and `DQS_DDL` 1 → 0.
  After the same value set again, or a read (−1), it didn't. So the source's
  `if( oldFlags!=db->flags ) sqlite3ExpirePreparedStatements(db, 0)` is what runs.
- **D1b. A statement running across the set isn't stopped.** Held at its first row across a
  change, the SELECT ran to done with no re-prepare, and re-prepared at its next run after its
  reset.
- **D2. A re-prepare under the new flag can fail.** `select "no_such_column"`, prepared and run
  with DQS on, answered 1 at its next step once `DQS_DML` was turned off: its re-prepare failed,
  `no such column`, and its reset answered 1. The DDL case, `create index if not exists`,
  re-prepared and ran.
- **D3. `db_config` leaves the connection's error state alone.** After a failed prepare, an
  unknown op (1999) answered 1 and left the cell untouched, and `sqlite3_errcode` and
  `sqlite3_errmsg` still gave the prepare's 1 and "no such column: nosuch". A set that succeeded
  didn't clear them either. On a fresh connection they stayed 0 and "not an error". So a refused
  set's message is `sqlite3_errstr` of its code, "SQL logic error" for 1, never `sqlite3_errmsg`.
- **D4. A set never waits.** Under another connection's `BEGIN EXCLUSIVE` and write, with a
  1500 ms busy timeout, each of the eight sets answered 0 with its value, in 0.000 to 0.001 ms. A
  SELECT's prepare there, the control, waited 1501.6 to 1501.7 ms and answered 5.
- **D5. Each op round-trips on every connection an open can make:** `:memory:`, a file whose
  schema no statement has read, `READONLY`, `NOMUTEX`, inside a transaction that wrote, and beside
  a statement at a row. Each answered 0 and its cell held the value set.
- **D6. Values v1 never passes.** 2 sets the flag on; −2 changes nothing and reads it, as −1 does.
  The cell is always 0 or 1: the source writes `(db->flags & mask)!=0`.
- **The DQS message differs by version,** as the pre-work found: 3.45.1's D2 line says `no such
  column: no_such_column`, 3.53.1's and 3.54.1's add `- should this be a string literal in
  single-quotes?`.

What it decides (the plan, §4.1): a set at open needs nothing the PRAGMAs don't, and can't wait
(Q11: plain). At open the connection holds no statement of its own, so no expiry reaches the
settings' statements or the cache's; a set after open could re-prepare a cached statement into a
failure (D2), one more reason Q10 put the sets at open. A refused set raises with `sqlite3_errstr`'s
message (D3).

## Results: `sqlite3_load_extension` (L1)

[out/l1-load-extension-*.txt](out/). Byte for byte alike on the three libraries but for their
version lines. Each path is printed with the probe's directory as `DIR`. Linux's `dlopen`
throughout: the suffix and the search below are Linux's.

| Case | Code | `pzErrMsg` |
|---|---|---|
| C call off (every library here starts it at 0) | 1 | "not authorized" |
| a path that doesn't exist | 1 | "DIR/nosuch.so**.so**: cannot open shared object file: …" |
| an empty file; a directory | 1 | "DIR/empty.so.so: cannot open …"; "DIR/dir.so.so: cannot open …" |
| no entry point, NULL given | 1 | "DIR/noentry.so: undefined symbol: sqlite3_noentry_init" |
| no entry point, one named | 1 | "…: undefined symbol: chez_nothing_init" |
| an init that fails, setting its message | 1 | "error during initialization: chez_failing refused" |
| `ext-named.so`, NULL given | 1 | "…: undefined symbol: sqlite3_extnamed_init" |
| `ext-named.so`, `chez_named_init` named | 0 | NULL |
| `ext.so`, NULL: `sqlite3_extension_init` | 0 | NULL |
| `libchezext.so`, NULL: the derived `sqlite3_chezext_init` | 0 | NULL |
| `DIR/ext`, no suffix | 0 | NULL |
| `ext.so`, a bare name, the working directory `DIR` | 1 | "ext.so.so: cannot open shared object file: …" |
| `./ext.so`, relative, the working directory `DIR` | 0 | NULL |

- **The slot.** Set to a sentinel address first, it held NULL after every success and a message
  after every failure: SQLite writes it on every call. Freed with `sqlite3_free` each time.
- **A failure's message names the last path `dlopen` tried.** SQLite tries the path, then the
  path with a suffix appended, and reports the second failure. So a missing `nosuch.so` reads
  `nosuch.so.so`, and an empty file's and a directory's real causes are hidden behind "cannot
  open". A path without the suffix loads (`DIR/ext`). The suffix is `.so` on Linux; under
  `__APPLE__` it is `.dylib`, by 3.45.1's own `azEndings`, not measured here.
- **With no entry point named,** SQLite tries `sqlite3_extension_init`, then a name derived from
  the file: `sqlite3_`, the letters of its base name after a leading `lib` and before the first
  `.`, lower-cased, then `_init` (`libchezext.so` → `sqlite3_chezext_init`, `ext-named.so` →
  `sqlite3_extnamed_init`). A failure names the derived one.
- **A bare name is `dlopen`'s search, never the working directory.** `ext.so` with the working
  directory holding it wasn't found; `./ext.so` was. That the search reads `LD_LIBRARY_PATH` is
  rv3's, below. macOS's dlopen(3) documents a leaf name searched in the working directory too,
  for an unrestricted process: not measured.
- **L3. A failed load of SQLite's own leaves the connection's error state alone,** as a failed
  `db_config` does: `sqlite3_errcode` 0 and `sqlite3_errmsg` "not an error" after it, on a fresh
  connection. The message is only in the slot. With the slot NULL, the call answered 1 and said
  nothing. rv1's part A holds it after an earlier error too, and its part B finds where it fails:
  an init's own failing call (below).
- **L4. Every load runs the extension's init again,** and a close unloads it. Loaded twice into
  one connection, and once into a second, `chez_inits()` counted 1, 2, 3, every load answering 0;
  the second connection had no `chez_half` until its own load. With both closed, a third
  connection's load counted 1 again: the file had been unloaded and loaded afresh.
- **L5. SQLite lets another thread load.** A connection opened on the main thread was loaded from
  a second thread: 0, and the functions worked on the first. Only ADR-0010's check refuses it.
- **L6. The call can block.** On a FIFO, it returned 500.3 to 500.5 ms later, when a helper
  thread opened the FIFO for writing, then failed: `dlopen`'s `open` waits for a writer.
- **L7.** SQL's `load_extension('DIR/ext.so')` answered 1, "not authorized", at its step, with
  the C call on, as the pre-work measured.
- **L8. A load beside the connection's own statements.** With a statement held at a row, the
  first load answered 0. The second, whose init replaces the functions the first registered,
  answered 1, "error during initialization: ", and the connection's extended code read 5:
  `sqlite3_create_function` refuses to replace a function while a statement is active, and the
  init returned that without a message. With nothing held, a third load answered 0, and a
  `PERSISTENT` statement re-prepared once at its next step: replacing a function expires every
  statement, the cache's among them.

What it decides (the plan, §4.4): the verb's failure is `&sqlite-error`, its code the call's
answer, its message the slot's text, and the connection's after it when an init's call set one
(L3; rv1); the slot is freed with `sqlite3_free` inside the call's section; the binding is
`__collect_safe` (L6, and X1 below); the owner-thread checks, the verb's and
`call-with-open-handle`'s, are what stop another thread (L5); the opt-in's check is the only thing
that stops a connection whose library starts the C call on (pre-work Q3, L1).

## Results: the load through Chez's FFI (X1)

[out/x1-*.txt](out/), on Guix's 3.53.1, the floor and 3.54.1.

- **A suite can build and load an extension in the container.** `ext.c` compiled in 50 to 52 ms
  with `$CC -O2 -Wall -Werror -shared -fPIC`, against each library's own `sqlite3ext.h`, which
  Guix's profile, the floor's build and `build-sqlite.sh`'s builds all install. It links no
  libsqlite3: it calls SQLite through the routines the loading library hands it.
- **Under the gate, a load, a call and the close leave nothing:** Valgrind with the gate's flags,
  `--error-exitcode=9 --leak-check=full --show-leak-kinds=definite
  --errors-for-leak-kinds=definite --command-line-only=yes`, exited 0, 0 errors, 0 bytes
  definitely lost. `sqlite3_memory_used` was 0 before the open and 0 after the close. `ext.so`'s
  `chez_half(5)` answered 2.5; `ext-failing.so`'s and a missing file's failures each gave their
  message, freed by `sqlite3_free`.
- **A load leaves nothing still reachable either.** The same program in its `gate-none` mode,
  the same open, `db_config` call and close with no load, left exactly the blocks the `gate` mode
  left, on each library: 1,752 bytes in 5 on Guix's, 1,686 at the floor, 1,704 on 3.54.1.
- **An unfreed message is seen twice.** The same run without the two `sqlite3_free` calls exited
  9: 448 bytes definitely lost in 2 blocks, 2 errors, and `sqlite3_memory_used` read 432 after
  the close. So both Valgrind and the memory check (ADR-0005) catch a verb that forgets it.
- **A plain binding holds every thread's collection for the whole wait.** The load of a FIFO
  blocked until a writer outside the process opened it, 1.5 s after the start. A second thread
  asked for a collection at 300 ms:

  | Binding | The load returned at | The collection was done at |
  |---|---|---|
  | plain | 1451 to 1454 ms | 1451 to 1454 ms: it waited for the load |
  | `__collect_safe` | 1449 to 1454 ms | 301 ms |

  The writer has to be outside the process: a thread of the process that opens the FIFO waits
  for the pending collection too, so with the plain binding nothing would ever release it.

What it decides (the plan, §4.4 and §4.6): `sqlite3_load_extension` is `__collect_safe` by
ADR-0011's rule; the suites compile their extension at test time, as the decoy is compiled; the
gate needs no suppression for it.

## Results: FTS5 and JSON (F1)

[out/f1-fts5-json-*.txt](out/), on all four libraries.

- **F0. The options:** `ENABLE_FTS5` is 1 on Guix's and the FTS5 build, 0 on the floor and
  today's `current`. `OMIT_JSON` and `ENABLE_JSON1` are 0 everywhere: JSON is built in by default
  since 3.38.0.
- **The `current` lane with FTS5 lists one more option.** `check-sqlite.sh --current` on the FTS5
  build failed, naming exactly one line, `ENABLE_FTS5`, after `DIRECT_OVERFLOW_READ`: 39 options
  for its 38 ([out](out/check-sqlite-current-fts5-3.54.1.txt), written by `run-review.sh`, with
  the lane's env for that call alone, as `build-sqlite.sh` calls it).
- **F1. FTS5's refusal, where it's absent, comes at step:** `create virtual table probe using
  fts5(body)` prepared, then answered 1, extended 1, "no such module: fts5". `select count(*) from
  pragma_module_list where name = 'fts5'` answers 0 there and 1 where FTS5 is: a second way to
  tell, from SQL. `fts5_source_id()` is "no such function" at prepare.
- **F2. FTS5's behaviour, the same on Guix's 3.53.1 and the FTS5 build of 3.54.1,** byte for byte
  but for their version lines and FTS3/FTS4's options: `MATCH` with `order by rank`; `bm25()`
  (negative reals); `unicode61`'s default folding of diacritics, so `cafe`, `café` and `creme`
  match `café` and `crème`, and `remove_diacritics 0` turns it off; `highlight()` and `snippet()`
  over UTF-8; prefix, phrase, `NEAR`, `NOT` and column filters; a bound `MATCH` parameter;
  delete and update; `optimize` and `integrity-check`; `fts5vocab`; the `porter` tokenizer.
  Every query error, an unterminated string, an unknown column, a bare `AND`, came at step with
  code 1. An unknown tokenizer fails at the `create`'s step, 1.
- **F3. JSON's behaviour is the same on all four,** byte for byte, but for `json_pretty`, which
  3.45.1 lacks ("no such function", at prepare; it arrived in 3.46.0). Among the rows:
  - `json(' { "a" : [1, 2.5, "x", null, true] } ')` answers the minified TEXT;
  - `jsonb('{"a":1}')` is the BLOB `4C17611331`, `json(jsonb(…))` round-trips UTF-8, and a bound
    BLOB `0C` reads as `{}`;
  - malformed JSON, text or BLOB, fails at step, 1, "malformed JSON"; a bad path is 1 too;
  - `->` answers JSON TEXT (`"é"`, quoted), `->>` the SQL value (`é`, 2.5, 8);
  - `json_extract('[1e400]', '$[0]')` is REAL infinity, and `9223372036854775808` a REAL, where
    `9223372036854775807` stays INTEGER.

What it decides (the plan, §4.5): Q2's rule, rows chosen by `sqlite-compile-option?
"ENABLE_FTS5"`, cross-checked by `pragma_module_list`, and the refusal asserted at step; Q1's
lane change moves one line of `check-sqlite.sh`'s list; the JSON suite's rows stay at the
floor's functions.

## Results: M4's plan review's probes (rv1 to rv3)

[out/rv1-*.txt](out/), [out/rv2.txt](out/rv2.txt), [out/rv3-*.txt](out/). Each probe is the
review's, rerun here by `run-review.sh`; rv1's outputs match the review's own byte for byte, and
its three are alike but for their version lines. rv1 and rv3 follow the C probes' rules above.

- **rv1, part A. A failed load keeps the connection's earlier error.** After `select nosuch`
  failed at prepare, 1, "no such column: nosuch", a load of a missing file answered 1, and the
  connection still said 1, "no such column: nosuch"; so it did after a load that succeeded. So
  L3's claim holds for SQLite's own failures, whatever the connection held before.
- **rv1, part B. An init's own failing call leaves its error on the connection.** With a
  statement held at a row, the connection said 100, "another row available". A second load of
  `ext.so`, whose init replaces the functions the first registered, answered 1, its slot "error
  during initialization: ", and then the connection said 5, "unable to delete/modify
  user-function due to active statements": the reason, which the slot lost. The call's answer, 1,
  and the connection's code, 5, differ.
- **rv1, part C. The ops change none of ADR-0018's six PRAGMAs.** On a fresh file holding a table,
  each value of `busy_timeout`, `foreign_keys`, `synchronous`, `temp_store`, `trusted_schema` and
  the four `journal_mode`s read back as written, with the ops at the library's start and with
  `DEFENSIVE` 1, `DQS_DML` 0 and `DQS_DDL` 0. The controls outside the list: `journal_mode = off`
  read back `off`, then `delete` under `DEFENSIVE`; `writable_schema = 1` read back 1, then 0.
- **rv2. `raise-sqlite-error` refuses the connection's 0.** Given 0, what the connection's extended
  code reads after a refused set on a fresh connection (D3), it raised an assertion violation,
  `(not-an-error 0)`; given 1, 5 and 261, `&sqlite-error` `error`, `busy`, and `busy` with
  `busy-recovery`. It loads no libsqlite3: `(chez-sqlite3 private conditions)` imports none.
- **rv3. A bare name loads through `LD_LIBRARY_PATH`.** From a working directory that doesn't hold
  it, `ext.so` and `ext` each answered 1 without `LD_LIBRARY_PATH`, "cannot open shared object
  file", and 0 with it naming the directory that holds it.

What they decide (the plan, §2's Q12, §4.1, §4.4 and Q16): a failure's code is the call's answer,
never the connection's; a load's message is the slot's, and the connection's after it when the
connection's code changed across the call; the four ops can sit anywhere in the list's order; a
bare name is refused.

## Watched failing

- **The version guard:** `l1-load-extension.c` compiled against the floor's header and linked to
  Guix's library refused to run, exit 2, naming both versions.
- **The gate:** `x1-ffi-load.sps`'s `gate-leak` mode is the planted fault: Valgrind exit 9, 448
  bytes definitely lost, where `gate` exits 0.
- **The FIFO measure:** its plain mode is the planted fault for `__collect_safe`: the collection
  waits 1.15 s, where the safe mode's takes 1 ms. A first version of the probe set its verdict by
  reading a flag the two threads raced for, and called the floor's plain run "finished before";
  the times are what it now compares.
- **`check-sqlite.sh`:** the FTS5 build fails it, by its one line; the plain build passes.
- **rv1's part B is the plant for the load's message:** the slot alone loses the reason, which
  part A shows the connection's message can't be trusted for unconditionally.
- **The comparison across libraries reads the library:** D1's floor output differs from 3.53.1's
  in the DQS message alone, and F1's in `json_pretty` and the FTS5 rows.

## Not run

- **The Mac.** No Apple or Homebrew library here. The pre-work's Mac step measured Apple's
  `db_config` answers; a load on Homebrew's, a `.dylib` compiled by the Mac's `cc`, SQLite's
  `.dylib` retry, and the named condition on Apple's are the slices' Mac steps (the plan, §5).
  macOS's leaf-name search of the working directory, which its dlopen(3) documents, isn't
  measured, and the verb never reaches it: it takes absolute paths alone (the plan's Q16).
- **Linux arm64:** no such machine.
- **Ubuntu's library** (the `main` lane's) wasn't loaded here: the pre-work read its census
  through the FFI, `ENABLE_LOAD_EXTENSION` starting at 1. Its load rows run on CI's `main` lane.
- **`check-variadic`'s cost:** it needs the slice's suite. The review measured about 7 s for its
  steps here; slice 2 reads it from CI's `main` job, where it runs as a step (the plan, §4.2).
