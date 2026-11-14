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
- **Refusal paths one good library never reaches**, found by the adversarial review (R5 to R7, and the
  paths it named beside them). Each is owed to M1 slice 3's decoy, which drives them by behaviour:
  - **R5, `initialize`'s answer unchecked:** `(unless (eqv? code 0)` read `(unless #t`. 44 passed.
  - **R6, the NULL-libversion refusal dropped:** `(or (c-string->string (raw-libversion)) (answered-null ...))`
    read `(c-string->string (raw-libversion))`. 44 passed.
  - **R7, `missing-api` always with library `#f`:** `required-entry` raising with `#f` where it was given
    the report. 44 passed.
  - **The loader's `load-failed`**, from `load-shared-object` refusing a path: no suite loads a bad file.
  - **Step 0's re-raise** of a failure an earlier run of the body recorded: it needs a second reference to
    a body that raised, in one process, which a good library never gives. The suite reads that step's
    shape as data, and no more.
  - **`invalid-override` and `not-found` through native:** `test-discovery` holds the choice, and
    native's use of it is a `call-with-values` the load-steps row reads as data.
  - **`not-threadsafe` at the call site:** `check-threadsafe` is `test-verify`'s, and that the call site
    passes the one answer `loaded-threadsafe` gives is held as data (the load-steps row and the
    `loaded-threadsafe` row), not by a refusal.

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

## Conventions

The convention suite (`tests/test-conventions.sps`, with `tests/foreign-conventions.sls` and
`tests/fixtures/conventions/`) and the prototype rows of `tests/test-constants.sps` (ADR-0011,
decision 6; [M1 plan](2026-11-13-m1-plan.md) §4). Each mutation ran in its own copy of the tree
under `/tmp/claude-1000/-home-kishu-src-chez-sqlite3/2a34ce20-2ac8-4a34-9128-3ab6746e1074/scratchpad/conv/`,
without `.git` or `build/`, through that copy's `scripts/guix-env`, on the one suite named. Counts are
read from the suite's output. Unmutated: `test-conventions` passes 34, `test-constants` 39 (9 of them
the prototype rows).

### The red runs

Each suite, run before any mutation against a stub table with one wrong row:

| Suite | The wrong row | Result |
|---|---|---|
| `test-conventions` | `sqlite3_close` plain | pass 25, fail 9: the collect-safe table row, `src: no violation` (`(mismatch "sqlite3_close" convention plain collect-safe)`), the plain-close fixture, and the six sweeps, each of which holds the unmutated rows to the real `src/` |
| `test-constants` | `sqlite3_open_v2`'s `sqlite3 **` written `sqlite3 *` | pass 38, fail 1: the header row, `actual: ("sqlite3_open_v2")`. The map passes, as it must: both are pointers, and only the header can tell them apart |

### The mutations

| Mutation | Guards | Failed |
|---|---|---|
| C1 | `sqlite3_close` plain in `native.sls` (this log's N4b) | `test-conventions` 7 of 34: `src: no violation` names `(mismatch "sqlite3_close" convention plain collect-safe)`, and the six sweeps. `test-native` still passes 43, as N4b recorded |
| C2 | one argument type: `sqlite3_errcode` takes `int` in `native.sls` | `test-conventions` 7 of 34: `(mismatch "sqlite3_errcode" arguments (uptr) (int))` |
| C3 | `sqlite3_errmsg` bound `__collect_safe` in `native.sls` | `test-conventions` 7 of 34: `(mismatch "sqlite3_errmsg" convention plain collect-safe)` |
| C4 | `sqlite3_errstr` returns `string` in `native.sls` | `test-conventions` 7 of 34: `(type-refused "sqlite3_errstr" result string)` and the result mismatch |
| C5 | a binding added with no row: `sqlite3_changes` in `native.sls` | `test-conventions` 8 of 34: `(no-row "sqlite3_changes")`, and the row that holds `src/`'s 15 names |
| C6 | a row removed: `sqlite3_errcode` from the table | `test-conventions` 13 of 34: `(no-row "sqlite3_errcode")`, the 15-names row, the collect-safe row, the four fixtures that use the row, six sweeps |
| C7 | the scanner walks tails: `foreign-forms` recurses on `cdr` | `test-conventions` 20 of 34: `src` reads the import clause's tail and `(syntax foreign-procedure)`'s, `(entry-not-literal ... (foreign-procedure foreign-ref ...))` and `(foreign-procedure)`; the decoys fixture and every other fixture fail |
| C8 | the allowlist gains `string` (arguments and results) | `test-conventions` 5 of 34: the allowlist row, the used-types row, the complement row naming `string`, the positions fixture, the whole-complement fixture. `src` still passes: no binding uses `string` |
| C9 | the allowlist gains `void` as an argument | `test-conventions` 4 of 34: the allowlist row, the used-types row, the positions fixture, the whole-complement fixture |
| C10 | the convention comparison dropped from `form-violations` | `test-conventions` 4 of 34: the plain-open, plain-close and safe-other fixtures, and the convention sweep. `src` passes, which is why the fixtures exist |
| C11 | the outside-native check dropped | `test-conventions` 2 of 34: the outside and outside-no-library fixtures |
| C12 | the bound-twice check dropped | `test-conventions` 2 of 34: both bound-twice fixtures |
| C13 | the scanner skips vectors | first run, with a fixture that wrote `(vector (foreign-procedure ...))`, a call and not a vector: **none, 34 passed.** The fixture is now `'#(...)`; then `test-conventions` 1 of 34: the decoys fixture's count of three forms |
| C14 | the complement short by one type: `wstring` out of the suite's list | `test-conventions` 1 of 34: the whole-complement fixture, which binds `wstring` and has no row for it |
| C15 | a prototype row with a wrong parameter type: `sqlite3_compileoption_used`'s `const char *` written `char *` | `test-constants` 1 of 39: `actual: ("sqlite3_compileoption_used")`. The map passes, as both are pointers |
| C16 | the map's pointer rule gives `int` | `test-constants` 3 of 39: the map-against-rows row (every pointer row named), the written-out map row, the planted-map row |

Where a mutation also fails the six sweeps, they are counted. The sweeps hold the real `src/` to the
table with one row changed in turn, so any real fault in `src/` or the table breaks them as well as
`src: no violation`.

### Not caught here

- **C13's first run** shows what a fixture must do: the form it hides must be the shape the scanner
  claims to read, here a literal vector. A call whose operand is a form is just a list.
- **A Chez type a later Chez adds** is outside the complement list until someone adds it. The suite
  asks Chez 10.4 that each listed type is accepted, so the list can't hold a type this Chez lacks, but
  it can't enumerate one it lacks a name for.

## The review's fixes

An adversarial review of this slice found its test findings, and these are the fixes. Each reviewer
mutant ran again, in a copy of the fixed tree under
`/tmp/claude-1000/-home-kishu-src-chez-sqlite3/2a34ce20-2ac8-4a34-9128-3ab6746e1074/scratchpad/s2-fix/`
(`R1` to `R11`, `N11`, `N16`; each has its `.old`, `.new` and `.log`, and `R11` and `R10` are built by a
script and have their own copy only), through that copy's `scripts/guix-env`, on the suites named.
Counts are read from the outputs. The reviewer's copies, with the "before" logs, are in `s2-review/`.
Unmutated, after the fixes: `test-native` 44, `test-blocks` 8, `test-conventions` 40 (before: 43, 8, 34).

### The fixes

- **Messages are never asserted** (ADR-0013, decision 9). `test-native` and `test-blocks` compare a
  refusal by its kind, who and irritants. The six messages of `test-native` and the two of `test-blocks`
  are gone, the dead-address child's expected output included: it prints who and irritants only. No row
  lost its power: every refusal in them already differed by who or by irritants (the NUL refusal's
  `((kind string))` from `call-with-c-string`'s own who; a re-entry's `()` from every other; `c-string->string`'s
  three by their irritants `x`, `-1`, `1.5`; the two `foreign-block` and two `free-foreign-block!` ones by
  who and irritants).
- **A keyword alias hides a binding.** `tests/foreign-conventions.sls` counts every occurrence of the
  symbol `foreign-procedure` in each file, quoted or not, and allows three: the head of a form it reads,
  the one `(only (chezscheme) ...)` import entry, and the one `(syntax foreign-procedure)` in a fender of
  `bind-required`'s `syntax-case`. Each other is a `(stray-reference FILE)`, and `violations` lists them
  after the per-form violations. Six new fixtures: `stray-alias`, `stray-define`, `stray-quoted`,
  `stray-syntax` (a second mention in the fender), `stray-other-macro` (the mention in another macro's
  fender), and `permitted` (the three allowed places, no violation); and the `decoys` fixture now names
  three strays, the syntax mention outside `bind-required`, the quoted symbol and a list's last element.
- **Step names.** The load-steps row's data reads the report's `libsqlite3-info-version` and
  `libsqlite3-info-version-number` too, so a floor check fed a constant changes a row. A new row holds
  `loaded-threadsafe`'s body to the threadsafe step's variable, found as the step whose expression is
  `(raw-threadsafe)`.
- **Top-level code.** `code-of` answers `(no-code NAME)` under a `guard`, so `ok`, `cantopen` and `ioerr`
  cannot end the suite unnamed.
- **Two rows that relied on malloc's reuse.** The NUL-written row and the zeroed-slot row take the
  address of the block they free, and assert that the new block is at it. Where it is not (Valgrind never
  reuses a block at once) the row prints `UNAVAILABLE`, its name and why, and is skipped with `test-skip`:
  a skip is its own result, and `suite-exit-status` counts it neither way. It is never a pass.
- **`constants.sls`** begins `#!r6rs`.

### The mutants

| Mutant | Before | After |
|---|---|---|
| R1: `loaded-threadsafe` answers 1 | `test-native` 43 passed | `test-native` 43 passed, 1 failed: the `loaded-threadsafe` row |
| R2: `(define-syntax fp (identifier-syntax foreign-procedure))` and a binding through it | `test-conventions` 34, `test-native` 43, `check-seam` holds: all pass | `test-conventions` 33 passed, 7 failed: `src: no violation`, `actual: ((stray-reference "chez-sqlite3/private/native.sls"))`, and the six sweeps. `test-native` 44 and `check-seam` (10 libraries) still pass: the convention suite is the rule's |
| R3: the NUL message reworded | `test-native` 7 failed (the seven U+0000 rows) | `test-native` 44 passed |
| R4: the floor check fed `3045001` | `test-native` 43 passed | `test-native` 43 passed, 1 failed: the load-steps row |
| R5: `initialize`'s answer unchecked | passes | passes: owed to slice 3 (above) |
| R6: the NULL-libversion refusal dropped | passes | passes: owed to slice 3 |
| R7: `missing-api` always with library `#f` | passes | passes: owed to slice 3 |
| R8: `cantopen` renamed `cant-open` in constants | `test-native` died, `Exception in cdr: #f is not a pair`, exit 255, no row named | `test-native` 43 passed, 1 failed: the missing-directory open row, `actual: (raised "Exception in sqlite3_errstr: invalid foreign-procedure argument (no-code cantopen)")`. `test-constants` 35 passed, 4 failed (the header rows) |
| R9: `foreign-free` dropped from `free-foreign-block!` | `test-blocks` 8, `test-native` 43 passed | `test-blocks` 8 passed, `test-native` 42 passed with the two reuse rows skipped (the block is never freed, so it is never handed back). A block never freed is the memory gate's to see; this mutant was not run under it |
| R10: `critical-section` around the blocked open, in the test | not rebuilt by the reviewer's log | `test-native` 44 passed: P3 (above) found the call safe in a critical section; not a defect |
| R10b: `sqlite3_open_v2` plain | `test-native` 1 failed, the FIFO row (LN4) | `test-native` 43 passed, 1 failed: the FIFO row. `test-conventions` 33 passed, 7 failed: `src: no violation` and six sweeps |
| R11: every assertion message reworded (nine) | `test-native` 12 failed, `test-blocks` 3 failed | `test-native` 44, `test-blocks` 8 and `test-conventions` 40 passed |
| N11: the out-pointer not zeroed | `test-native` 1 failed | `test-native` 43 passed, 1 failed: the zeroed-slot row, on Linux where the reuse holds |
| N16: the NUL not written | `test-native` 4 failed | `test-native` 40 passed, 4 failed: the same four, the NUL-written row among them |

### The checks of the logs

- **The seam log's final run** said 8 suites and 2 libraries in 2 files. A copy of `857df95` (its
  `git archive`, with `vendor/chez-srfi` copied in), run on 2026-11-14 through `scripts/guix-env`:
  `make test` ran 13, passed 13; `check-seam: the seam holds (7 libraries in 7 files checked)`;
  `test-check-seam` 67; `make check-test-fails` all 12 cases. The seam log's line is corrected.
- **The constants log**, one row, in a copy of `d4be824`: the unmutated `test-constants` passes 30
  (the 3.53.1 header, the subset note printed), and C1, `ioerr-short-read` 523, passes 26 and fails 4:
  the values row, the unique-values row, the extended-code row and the name-of-code row. As logged.

### The final runs

- **`make test`:** ran 17, passed 17. `test-native` 44, `test-blocks` 8, `test-conventions` 40; every other
  suite unchanged. `check-seam: the seam holds (10 libraries in 10 files checked)`.
- **`make check-test-fails`:** `make test failed, as it must, in all 12 cases`.
- **`make test-memory`:** ran 17, passed 17. `test-native` passed 42 under Valgrind: 0 errors from 0 contexts, 0 bytes definitely lost, 15,256 bytes in 11 blocks still reachable, as before. Its two reuse rows printed `UNAVAILABLE` and were skipped, as they must be where Valgrind never hands back the block just freed. `test-blocks` 8, 0 errors, 224 bytes in 4 blocks.
