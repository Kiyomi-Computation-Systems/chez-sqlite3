# M1 slice 2 mutation log: the native load

Evidence that the load of libsqlite3, its counted memory and their suites fail through the property
each rule claims to guard ([M1 plan](2026-11-13-m1-plan.md) §3.3, §3.5, §5 slice 2;
[ADR-0002](decisions/0002-runtime-libsqlite3-discovery.md), amended;
[ADR-0011](decisions/0011-collect-safe-and-no-scheme-memory.md)). Format of
[the M0 closing review's log](m0-review-mutation-log.md).

The slice is `(chez-sqlite3 private memory)` and `(chez-sqlite3 private native)`, their suites
`tests/test-blocks.sps` and `tests/test-native.sps`, the C oracle (`tests/libsqlite3-oracle.c` and
`(libsqlite3-oracle)`), `tests/preflight.sps` and `make build`, and the seam's tables. An Opus agent
built it from the copy table the coordinator checked and ruled on, test first. The sources are
chez-curl's `memory.sls`, `native.sls`, `test-memory-safety.sps`, `test-native.sps`,
`libcurl-oracle.c` and `.sls`, and `preflight.sps`, at `79c6ced`.

Every mutation ran in its own copy of the working tree, made in the session scratchpad without
`.git` or `build/`, through that copy's own `scripts/guix-env`, after `make deps` in the copy. A
driver refused any edit whose text did not occur exactly the stated number of times, and any that
changed nothing. The working tree was never edited by a mutation. The counts below are read from the
suites' own output (`# of expected passes`, `# of unexpected failures`), never by eye. The driver is
in the session scratchpad, not the repository.

## The red runs

Each suite was written first and run against a stub with the real exports, every procedure
answering the symbol `stub`, under `build/stubs/` on the library path, never under `src/`. The stubs
were then removed.

| Check | Red run | Green run |
|---|---|---|
| `test-blocks` | against a stub memory: 2 passed, 6 failed | 8 passed |
| `test-native` | against a stub native: 7 passed, 36 failed | 43 passed |
| `check-seam` | `HEAD`'s program, with the old tables, on the new `src/`: `FAILED (problems: 14)`, one line per name memory and native import | `the seam holds (10 libraries in 10 files checked)` |
| `test-check-seam` | the old suite against the new tables: 63 passed, 4 failed (`names-several`, both written-out tables, the complement row) | 67 passed |
| `check-test-fails` | the old seam case against the new tables: `FAILED seam`, wanting rule (c)'s "allowed-chez-names … does not list it", getting rule (f)'s "library-only-chez-names … allows it only in (chez-sqlite3 private memory)" | `make test failed, as it must, in all 12 cases` |
| `make build` | before the target existed: `make: Nothing to be done for 'build'.`, exit 0, since `build/` is a directory | names the library, exit 0 |

The rows that passed against a stub are rows a stub can satisfy:
- `test-blocks`: the export list, and the closing counts.
- `test-native`:
  - "native loads", since the stub loads;
  - the counts after the load;
  - the export list;
  - the opacity row, where `record-rtd` of a symbol raises as it does of an opaque report;
  - the suite's own choice of path;
  - the oracle's read, which never touches native;
  - the closing counts.

The three `test-check-seam` rows that put every allowed name in one plain library did not fail in
the red run: they read the suite's own `table-allowed`, still the old one. S1 below watches the
changed row fail.

The first green run of `test-native` failed one row, 42 and 1: the eagerness row counted 16
`foreign-procedure` forms, not 15. The scanner walked cdr tails, and the binder's fender,
`#'foreign-procedure`, reads as `(syntax foreign-procedure)`, whose tail is `(foreign-procedure)`. The
scanner now looks at the elements of each list, never at a tail. The convention suite's scanner has
the same trap, and the import clause holds a second: `(only (chezscheme) … foreign-procedure
foreign-ref …)` has a tail headed by `foreign-procedure`.

## The mutations

Baselines, from the green runs: `test-native` 43, `test-blocks` 8, `test-check-seam` 67. Each row
names the suites that failed and how many rows failed in each. A mutation counts as caught when at
least one row failed; every caught one also failed `suite-exit-status`, exit 1. `test-blocks` passed
8 in every N mutation, and `test-native` 43 in every B mutation but B2.

### The load's order and eagerness (the body, read as data)

With one good library in one process, neither the order of the steps nor eagerness can be seen
by behaviour: the load runs once, and every check passes. The data rows hold them until M1 slice 3's
decoy holds them by behaviour.

| Mutation | Guards | Failed |
|---|---|---|
| N1 | the floor before threadsafe: steps 4 and 5 swapped | native 1: the order row |
| N2 | the floor before the rest: the ten bindings moved before step 4 | native 2: the order row and the eagerness row |
| N3 | eager binding: `sqlite3_errstr` bound at each call, by a procedure | native 2: the order and eagerness rows |
| N3b | eager binding: `sqlite3_errstr`'s `load-step` inside a `lambda` | native 2: the same |
| N19 | `sqlite3_initialize` before the rest: step 6 moved after step 7 | native 2: the same |
| N20 | `missing-api` carries the report: `sqlite3_close` bound with `#f` | native 2: the same (the report column) |
| N26 | `sqlite3_initialize` is called: its code taken as 0 | native 1: the order row's names column |
| N27 | the threadsafe check reads the library's answer: handed 1 | native 1: the order row's names column |

N26 and N27 passed the order row as first written, which held each step's name and head alone. Its
third column, the load's names each step's expression uses, was added for them, before this run.

### The report and the oracle

| Mutation | Guards | Failed |
|---|---|---|
| N10 | the override is loaded: discovery's `getenv` hides `CHEZ_SQLITE3_LIBRARY` | native 1: the path and source row (`guix-environment`, not `override`; the path is the same file) |
| N9 | the report's fields: version and source id swapped | native 2: the version and source-id oracle rows |
| N8 | the oracle comparison: weakened to the field's name | none: 43 passed, as a weakened test does |
| N8+N9 | the oracle comparison is what catches N9 | none: 43 passed. With the comparison weakened, the swap goes unseen: no other row holds the report's strings |

By hand, not mutated: with `CC=/nonexistent/cc`, 35 passed and 8 failed, the oracle-read row, the
six field rows and the compile-option row, exit 1. A missing compiler never skips.

### `__collect_safe`, by behaviour

| Mutation | Guards | Failed |
|---|---|---|
| N4 | `sqlite3_open_v2` is `__collect_safe`: the convention dropped | native 1, after 32 s: the FIFO row, `released-by-the-watchdog`. The collection waited for the plain call until the watchdog shell, 30 s on, released it |
| N4b | `sqlite3_close` is `__collect_safe`: the convention dropped | **none: 43 passed.** No behaviour here makes `sqlite3_close` block. The convention suite holds it |

### Counted blocks: freed on every path

| Mutation | Guards | Failed |
|---|---|---|
| N5 | a block freed on raise and escape: `call-with-block` without its `dynamic-wind` | native 10: both raise rows, both escape rows, both re-entry rows, both refusal rows, the FIFO row, the closing counts; `suite-exit-status`: native objects left, block 4 |
| N12 | re-entry after the free refused: the before thunk's check dropped | native 2: both re-entry rows |
| N11 | the out-pointer zeroed first | native 1: the zeroed-slot row, on a block that held `#xFF` |
| N15 | the out-pointer read after PROC: read before it | native 4: both raw-open rows, the answer-and-pointer row, the FIFO row |

### C strings

| Mutation | Guards | Failed |
|---|---|---|
| N6 | U+0000 refused before anything is allocated: the check moved after the allocation | native 7: every position row, one block counted at the raise |
| N13 | the refusal names its WHO: it names `call-with-c-string` | native 7: every position row |
| N14 | the refusal names the string by its kind: it names the string | native 7: every position row |
| N16 | the NUL written: not written | native 4: the compile-option-used row, the UTF-8 row, the round trip, the NUL-written row |
| N17 | the writer: one byte short | native 5: the same four, and the FIFO row (the FIFO's path lost its last byte) |
| N7 | the reader: it stops one byte early | native 6: the version, source-id, compile-options and errstr oracle rows, the UTF-8 row, the round trip |
| N25 | the reader refuses what is no address | native 1: the reader's refusal row |

### Memory (`test-blocks`)

| Mutation | Guards | Failed |
|---|---|---|
| B1 | the live table consulted on free | blocks 2: the non-address row, and the dead-address child, which freed a freed block |
| B2 | a block counted | blocks 4 and native 14: every row that reads a count, and `count-down!`'s double-free refusal at each free |
| B3 | a refused size named by `shown-value` | blocks 1: the size row (`"8"` named as itself) |

### The seam

| Mutation | Guards | Failed |
|---|---|---|
| S1 | `test-check-seam`'s one-library row holds only names no entry keeps: put back to every allowed name | check-seam passes; test-check-seam 1: that row, refused by rule (f) |
| S3 | `format` is native's alone: its library-only entry dropped | check-seam passes; test-check-seam 3: `names-several`, the written-out table, the rule (f) matrix |
| S4 | `foreign-sizeof` allowed: dropped from `allowed-chez-names` | check-seam fails, naming native's import; test-check-seam 3: both rows holding the list to `src/`'s imports, and the library-only row |

### `make build`

| Mutation | Guards | Failed |
|---|---|---|
| K1 | `build` is in `.PHONY`: dropped | `check-help` fails: "make help lists 'build', which is not in .PHONY". The copy has no `build/`, so `make build` itself ran; in a tree with `build/`, it does nothing and exits 0 (the red run above) |

### Not caught here

- **N21, `foreign-entry?` not asked:** 43 passed. With a good library every entry point is present.
  M1 slice 3's decoy, with one switch per entry point, catches it.
- **N4b, `sqlite3_close` plain:** the convention suite's.
- **The copy made before the check** in `call-with-c-string` was not mutated. Seeing it needs another
  thread to change the string between a check and an encoding.

## The final runs

In the working tree, through `scripts/guix-env`, after every change above:

- **`make test`:** ran 16, passed 16, 988 rows: `test-native` 43, `test-blocks` 8,
  `test-check-seam` 67, and `test-require-threaded` 58, two more than before, one import-order row per
  new library. `check-seam: the seam holds (10 libraries in 10 files checked)`.
- **`make test-memory`:** ran 16, passed 16, in about 2.5 minutes. `test-native`, the first suite to
  load libsqlite3 under the gate, passed 43 under Valgrind: 0 errors from 0 contexts, 0 bytes
  definitely, indirectly or possibly lost, 15,256 bytes in 11 blocks still reachable, no suppression.
  `test-blocks`: 8, 0 errors, 224 bytes in 4 blocks still reachable.
- **`make check-test-fails`:** `make test failed, as it must, in all 12 cases`.
- **`make build`:** names Guix's 3.53.1 by the override, exit 0. With the override unset, it names
  the same file by discovery, source `guix-environment`. A relative override prints
  `(reason . invalid-override)`, and a missing file `(reason . load-failed)` with the loader's message,
  each exit 1.
- **`test-native` with the override unset:** 43 passed, both sides choosing by discovery.

## Measured before the code

In a scratch tree of the launcher, `channels.scm` and `manifest.scm`, SQLite 3.53.1:

- **P1:** `load-shared-object` raises a format condition, `"(while loading ~a) ~a"`, whose irritants
  are the path and dlerror's text: so `loader-message` renders it.
- **P3:** `sqlite3_open_v2` on a FIFO, read-only, blocks until a writer opens it.
  - Bound plain, another thread's `collect-rendezvous` deadlocked the whole process, the thread
    that would have opened the writer included.
  - Bound `__collect_safe`, the collection finished while the call blocked, also from inside
    `critical-section`.
  - The open answers 10, SQLITE_IOERR: a pipe cannot `pread` the header.
- **P4:** the oracle compiles under `-Wall -Werror` with `__typeof__` pointers from `sqlite3.h`.
- **P5:** `(rnrs)`'s `dynamic-wind` is not Chez's, and refuses the critical form. `(rnrs)`'s
  `file-exists?` follows a link, is false on a dangling one, and true on a directory.
- **P6:** a raise from a critical `dynamic-wind`'s before thunk, caught by a guard, leaves the
  interrupt disable count at 0, so the re-entry refusal there is safe.
