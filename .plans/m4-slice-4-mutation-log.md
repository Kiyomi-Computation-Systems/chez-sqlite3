# M4 slice 4 mutation log

Evidence that each rule slice 4's rows claim to guard fails through the property it names
([the M4 plan](2026-11-17-m4-plan.md) §4.4, §4.6, §4.7, §4.8 and §5 item 4). Format of
[the M4 slice 3 log](m4-slice-3-mutation-log.md). An Opus agent built the slice from the lead's
brief, in the worktree `chez-sqlite3-wt-m4s4`, on `m4-slice-4-load` from `main` at `c92d397`,
slices 1, 2, 3 and 5 and the close fix merged there. `make test` ran 79 suites there before the
slice, 79 passing on Guix's 3.53.1, and runs 81 with it. The lead committed the first round as
`ebc9b14`. The slice's read-only Opus review then found two majors, which overturned two survivor
arguments and a trap, and five minors, all fixed in a second round
([below](#round-2-the-reviews-findings)). Every figure below is from the second round's tree,
the final one, unless a line names another.

## What the slice adds

- **`(chez-sqlite3 private extension)`, new:** `load-extension!` and, for the suites,
  `load-extension/with`:

  ```scheme
  ;; load-extension! : (case-> (Database String -> Void) (Database String String -> Void))
  ;; load-extension/with : (case-> (LoadBinding Copy Database String -> Void)
  ;;                               (LoadBinding Copy Database String String -> Void))
  ;; LoadBinding = (Positive-Integer Positive-Integer Natural Positive-Integer -> Any)
  ;; Copy = (Natural -> Any)
  ```

  - **The checks, in the plan's order,** each refusal from `load-extension!`: a database,
    `not-a-database`; the owning thread, `&sqlite-wrong-thread`; open, `&sqlite-closed`; the
    path a string, `path-not-a-string`, holding no U+0000, `path-holds-nul`, and absolute, its
    first character `/`, `path-not-absolute`; the entry point, when given, a string,
    `entry-point-not-a-string`, holding no U+0000, `entry-point-holds-nul`; then the record's
    opt-in, read by `database-extension-loading?` last, `extension-loading-not-enabled`, whose
    message names `(enable-load-extension . #t)`. Each string is copied first and the copy
    checked and handed to C; each value named by `shown-value`.
  - **The first three are one `call-with-open-handle`,** its procedure answering nothing,
    inside a critical section of its own, what it raises caught there and raised after it. Its
    `check-owned` is the verb's own owner check, made before the argument checks, and the load's
    section goes through `call-with-open-handle` again, so the owner is checked twice, as §4.4
    asks. Without the critical section, an engine's expiry inside `call-with-open-handle`'s wind
    gave a second resume its `re-entered` refusal, an assertion violation, in place of
    `&sqlite-closed` (C19 below).
  - **The claim** is the call's first expression, the conveniences' `made-claim`. The one
    section, a critical section around `call-with-open-handle`, compares it first, position 0,
    the call's last; then the path's C string, the entry point's or NULL, the slot by
    `call-with-out-pointer`, the extended code read before and after the call, the call; then
    the slot's message, when there is one, copied under a guard and freed with `sqlite3_free`
    whatever the copy did; then, for a failure, `sqlite3_errstr`'s text when the slot held none,
    and the connection's `sqlite3_errmsg` when its extended code changed. It answers data; the
    raise comes after it.
  - **A failure** is `raise-sqlite-error` of the call's own code, never the connection's. Its
    message is the slot's text, or `sqlite3_errstr`'s, then the connection's when its code
    changed: joined as they stand where the first ends in a space, as SQLite's "error during
    initialization: " does, else with ": " between them. rv1's part B reads, whole, "error during
    initialization: unable to delete/modify user-function due to active statements".
  - **A code that names no error,** its low byte 0, 100 or 101 but not 0, or no exact integer,
    which only a stand-in answers, is an assertion violation from the verb, `(not-an-error
    CODE)`, as the open's sets are (ADR-0021, amended in M4 slice 1). Decision 7 says nothing of
    it; below, for the records.
- **`(chez-sqlite3)`** exports `load-extension!`, 70 names, its signature comment
  `;; load-extension! : (case-> (Database String -> Void) (Database String String -> Void))`.
- **`docs/reference.md`:** a section, Extensions, after Connections, and the index's line: the
  method, open with the setting and load by an absolute path; the refusal without it, a
  `scheme run` block that reaches no C, so it gives `(extension-loading-not-enabled)` on every
  library, Apple's among them; the entry `load-extension!`: the absolute path and the suffix's
  retry, the entry point's search with `libgeo.so`'s `sqlite3_geo_init`, a failure's code and
  message, what a load does to the connection, the close's refusal over an extension's leftover
  work (ADR-0021's close-fix amendment), and the library without extension loading.
- **The extension,** `tests/extension.c`, the research's `ext.c`'s four variants: the default
  init, `chez_named_init`, `sqlite3_chezext_init` in `libchezext`, and the failing init; its
  functions `chez_half` and `chez_inits`. `tests/extension-build.sls`, `(extension-build)`,
  compiles it with `$CC -Wall -Werror -shared -fPIC`, `-dynamiclib` and `.dylib` on a Mac by
  Chez's machine type, against the lane's `sqlite3ext.h`. Where native records
  `sqlite3_load_extension`, a missing compiler or header fails the build's row and every load
  row after it; where it records none, as on Apple's library, `built-where-loadable` names the
  build unavailable, compiles nothing, and the suites assert the opt-in's refusal in its place
  (the maintainer's "Build named unavailable there", round 2).
- **The suites:**
  - `tests/test-load-extension.sps`, new, 42 rows: the build and its decision; every check, every kind of value,
    U+0000 at every position, every first character but `/` from U+0001 to U+007F and four
    beyond, the order; the opt-in, its message, and the opt-in with the C switch on; the
    default, named and derived entry points and the suffix's retry; the init counted, the close
    unloading; each failure's code and message; the code after a constraint's failure; the held
    row, its message whole; the ": " join; SQL's `load_extension()`; the stand-in's rows; the
    wrong thread and a closed connection; the memory; the depth;
  - `tests/test-load-extension-engines.sps`, new, 14 rows: clean, every fuel; resumed twice,
    interleaved and a timer's continuation re-entered, each in two passes, with no collect
    request and under a collect trip of 256 bytes; the caller's path and entry point changed
    between an expiry and its resume; a refused run's depth;
  - `tests/test-public.sps`, 23 rows from 22: the count 70, the list, and the new library's
    exports; `tests/test-reference.sps`, 22 from 21: the signature;
    `tests/test-never-loads.sps`: the loaders gain `(chez-sqlite3 private extension)`;
  - `tests/test-library-loading-real.sps`, 53 from 51: the decoy's two load rows, through
    `tests/refusal-probe.sps`' new `--loads` and `tests/library-loading.sls`' `loads-arg`;
  - `tests/test-docs.sps` holds the new `scheme run` block, 107 rows.

## The decoy's load rows

The decoy's open always fails, so no connection of it reaches a load: what `--opens` serves for
the opt-in, a load needs a case of its own. `--loads CASES` runs each case through
`(chez-sqlite3)`'s `load-extension!` after the opens, and prints what each did as `--opens`
prints an open. Cases are data, so none holds a database, and each refuses at the first check.
What the two rows hold, on the build without `sqlite3_load_extension` and on the control: the
verb is reached, its library loading where native binds no load; its refusal is raised after
its section, depth 1, every count zero; and the log holds the load's entries alone, nothing of
SQLite's called, `sqlite3_load_extension` least of all on the control. On Linux they are the only
rows that run the verb's library where the entry point is absent: D01, a library body that
touches the binding at its load, fails nothing else.

## How the mutants ran

Every plant ran in a copy of the worktree of its own, made by
`tar --exclude=./build --exclude=./.git`, each edit checked to match its file's text exactly once
before it was written, under `build/mut/r1/NAME/` for the first round and `build/mut/final/NAME/`
for the figures below, on the final tree. Each copy ran `make deps` and its suites through
`$CHEZ --libdirs src:tests:build/scheme-libs --program`, each under `timeout 600`, inside one
`scripts/guix-env` run from the worktree, six copies at a time by `xargs -P 6`, on Guix's 3.53.1;
`scripts/guix-env` starts at the worktree's root, so each `run.sh` changes into its copy first.
A plant marked "gate" ran its suite under `make test-memory` in its copy too. The default suites
are the seven the slice touched: `test-load-extension`, `test-load-extension-engines`,
`test-public`, `test-reference`, `test-never-loads`, `test-docs` and `test-library-loading-real`.
The counts are read from the suites' own output, `# of unexpected failures` and the exit
checks' lines, never by eye.

The driver is kept in [research/m4-slice-4/scripts/](research/m4-slice-4/scripts/): `mut.py`
makes the copies and their `run.sh`, and reports each copy's failing rows; `mutants.py` holds
every plant's edits. From the worktree's root:

```sh
D=.plans/research/m4-slice-4/scripts
python3 -I -B $D/mut.py --into build/mut/final prepare all
python3 -I -B $D/mut.py --into build/mut/final scripts all
scripts/guix-env sh -c 'ls build/mut/final/*/run.sh | xargs -P 6 -n 1 sh'
python3 -I -B $D/mut.py --into build/mut/final report all
```

## The red runs

The rows were written against the plan's §4.4 and §5 item 4, then run against the base,
`c92d397`, in a copy whose `src/` and `docs/` are the base's and whose `tests/` are the final
tree's (`build/mut/red/`), on Guix's 3.53.1. No suite died: the verb, `load-extension/with` and
every private name a suite needs are reached through `eval` under a guard, so a library that
lacks one fails the rows that use it, by name. The base's own suites ran in a copy of `c92d397`
whole (`build/mut/base-own/`).

| Suite | The base's own | Red, the base's `src/` and `docs/` | Green |
|---|---|---|---|
| `test-load-extension` | new | 6 passed, 36 failed | 42 passed |
| `test-load-extension-engines` | new | 2 passed, 12 failed | 14 passed |
| `test-public` | 22 passed | 19 passed, 4 failed | 23 passed |
| `test-reference` | 21 passed | 21 passed, 1 failed | 22 passed |
| `test-never-loads` | 5 passed | 4 passed, 1 failed | 5 passed |
| `test-library-loading-real` | 51 passed | 51 passed, 2 failed | 53 passed |
| `test-docs` | 105 passed | 105 passed, the base's page | 107 passed |

`test-docs` and `test-reference` ran red with the base's page too: with the first round's page
and the base's `src/` (`build/mut/base/`), `test-docs` failed 1 of 107, the new block, its
`load-extension!` unbound, and `test-reference` 3 of 22, the entry with no export and the
signature row. The rows that pass red, each a precondition or watched failing against a plant
instead:

- `test-load-extension`: its load and its two count rows; `x-available`, native's record,
  slice 2's, which every load row chooses by; `x-build`, the compile, which X01 (no compiler),
  X02 (no header) and X04 (the build skipped everywhere) fail, with every load row after it;
  `x-decision`, the build's decision, a helper of the suite's, which X04 and X05 fail;
- `test-load-extension-engines`: its load, and the pin's close with every count zero;
- `x-sql`, SQL's `load_extension()` refused on a connection that opted in, a property of
  SQLite's that the docs promise: Q01, `sqlite3_enable_load_extension` called at every open that
  opts in, fails it.

`x-freed` passed red in the first round's first version, which judged any raise as a failure's:
on the base, "could not be reached" was a raise, and the count stayed. It requires the load's own
`&sqlite-error`, from `load-extension!`, since, and fails red.

The rows changed, each named:

- `test-public`: "(chez-sqlite3) exports 69 names" is 70; the public list gains
  `load-extension!`; the whole-list row's title names the extensions' load; a new row holds
  `(chez-sqlite3 private extension)`'s two exports.
- `test-reference`: a new row holds the entry's signature to the plan's §4.8.
- `test-never-loads`: the loaders gain `(chez-sqlite3 private extension)`.
- `test-library-loading-real`: two new decoy rows, `l-load-lacking` and `l-load-control`.

## Green, the libraries and the gate

`make test` ran 81 and passed 81 on each library, on the final tree, inside the container,
`CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH` set there, each lane's version read first by a
program of its own: Guix's 3.53.1, the default; the floor's 3.45.1 (`build/m3-floor/`); and the
`current` lane's 3.54.1 (`build/m4-current/`). The extension compiled against each lane's own
`sqlite3ext.h`, the floor's and the current lane's by `C_INCLUDE_PATH`. Ubuntu's library, the
`main` lane's, and its `libsqlite3-dev` header are CI's to show (the plan's §7).

Under `make test-memory`, on Guix's 3.53.1, each suite the slice touched passed, 0 errors and
nothing definitely lost, none `SLOW`, each time from the gate's `time:` line, the first round's
and the final tree's:

| Suite | Shard | Rows | Round 1 | Final |
|---|---|---|---|---|
| `test-load-extension`, new | 2 | 42 | 13 s | 13 s |
| `test-load-extension-engines`, new | 2 | 14 | 16 s | 31 s |
| `test-public` | 2 | 23 | 10 s | 10 s |
| `test-reference` | 2 | 22 | 10 s | 10 s |
| `test-never-loads` | 1 | 5 | 6 s | 6 s |
| `test-docs` | 1 | 107 | 34 s | 34 s |
| `test-library-loading-real` | 1 | 53 | 192 s | 191 s, from slice 3's 175 to 177 s, two more children |

**The shard.** Both new suites are in `MEMORY_SUITES_2`. The memory jobs of `main`'s latest three
CI runs, each shard's `time:` lines summed from `gh run view RUN --log --job JOB` on the host:

| Run | Commit | `memory-1` | `memory-2` |
|---|---|---|---|
| 44325663052 | `c92d397`, slice 3 | 1371 s, 41 suites | 1114 s, 38 suites |
| 44305936182 | `7c6d536` | 1012 s, 39 suites | 836 s, 38 suites |
| 44298034354 | `2102131` | 1023 s, 39 suites | 1091 s, 38 suites |
| the three | | 3406 s | 3041 s |

Shard 2 is the lighter on two runs of three, in total, and on the latest run, the only one at the
current layout, whose shard 1 holds slice 3's two suites (78 s and 18 s there). The two new
suites add about 44 s here.

**The engine rows' figures,** alike on the three libraries:

| Row | No collect request in a trial | Under a collect trip of 256 bytes |
|---|---|---|
| `e-fuel`, the load resumed at its fuel | completes unexpired at fuel 60 | |
| `e-twice`, resumed twice | fuels 1 to 8 a whole new call; 51 refused, taken before the section, from fuel 9; none taken past it | completes at 66; 8 whole new calls; 54 refused from fuel 9; 3 taken past the section, answering again |
| `e-interleave` | 1759 trials; refusals at 51 fuels; 444 whole new calls, all at fuels up to 8, below the sweep's first refusal at 9; no remainder past the section | 2134 trials; refusals at 54 fuels; 492 whole new calls, up to fuel 8, below the first refusal at 9; both remainders past the section in 3, R before it and R1 past it in 186 |
| `e-reentry`, a timer's continuation called after the call | ends before tick 53; 7 whole new calls, 45 refused from tick 8 | ends before tick 59; 7 new, 48 refused from tick 8, 3 taken past the section |
| `e-caller-path`, the path's `/` made `x` between expiry and resume | completes at 62; refused path-not-absolute at 16 fuels, loaded at 45 | |
| `e-caller-entry`, the entry point's last character made U+0000 | completes at 89; refused entry-point-holds-nul at 70 fuels, loaded at 18 | |
| `e-depth` | the refused run's handler at depth 1 | |

With no collect request in a trial, no remainder is taken past the section: the section is the
call's last work, and no procedure call follows it. Under the low trip, a collect request falls
due inside the section and is handled at its exit, costing the engine ticks there, and remainders
past it appear (the first trap below).

## The mutations

The rows, by label. `test-load-extension`: `x-build`; `x-decision` the build's decision;
`x-available`; `x-database` every kind of value that is no database; `x-path-kinds`; `x-path-nul`
U+0000 at every position; `x-absolute` the first character, every one but `/` from U+0001 to
U+007F and four beyond, and paths let through; `x-relative-opted` a relative path that dlopen
loads, refused; `x-entry-kinds`; `x-entry-nul`; `x-order`; `x-opt-in` no setting, `#f`, through
both verbs; `x-opt-in-message`; `x-switch-on` the opt-in with the C switch on; `x-default`,
`x-named`, `x-derived`, `x-bare` the suffix's retry; `x-inits` counted across loads and
connections; `x-failures` each failure's code and message, the raw call's code asserted;
`x-constraint` the code after a constraint's failure; `x-held` the load beside a held row;
`x-held-whole` its message whole; `x-colon` the ": " join; `x-sql`; `x-close` the close
unloading; `x-stand-in` the stand-in's calls; `x-empty-slot`; `x-not-an-error`;
`x-success-freed`, the real load's code and message asserted; `x-copy-raises`; `x-thread` another
thread, no opt-in, every argument; `x-thread-valid` another thread, everything valid; `x-closed`;
`x-memory` a load, a call and the close; `x-freed` each failure's message; `x-depth`,
`x-depth-thread`, `x-depth-failures`; `x-end`. The four memory rows assert the count higher while
the message, or the extension, was held, and back after: their positive control, named
unavailable where the library keeps no count. `test-load-extension-engines`: `e-build`, `e-clean`,
`e-fuel`; `e-twice`, `e-interleave`, `e-reentry`, each with its low pass, `e-twice-low`,
`e-interleave-low`, `e-reentry-low`; `e-caller-path`, `e-caller-entry`; `e-depth`; `e-end`.
`test-library-loading-real`: `l-load-lacking`, `l-load-control`. `test-public`: `p-count`,
`p-list`, `p-eq`, `p-extension`. `test-reference`: `r-line`, and its whole-page rows. `test-docs`:
the new block.

| Plant | What it plants | Failed |
|---|---|---|
| C01 | the first three checks' section dropped, §4.7's "the verb's owner check dropped" | load-extension 6 of 42: `x-database`, `x-thread`, `x-thread-valid`, `x-closed`, `x-depth`, `x-depth-thread`; loading-real 2 of 53: `l-load-lacking`, `l-load-control` |
| C02 | that section after the argument checks | load-extension 3: `x-database`, `x-thread`, `x-closed`; loading-real 2 |
| C03 | that section's refusal raised inside it, its guard dropped | load-extension 2: `x-depth`, `x-depth-thread`; loading-real 2 |
| C19 | that section's `call-with-open-handle` outside a critical section | engines 6 of 14: `e-twice`, `e-interleave`, `e-reentry` and their low passes, each a second run refused `re-entered` (the second trap below) |
| O01 | both owner checks dropped, `call-with-open-handle`'s `check-owned` cut to a database's check | load-extension 3: `x-thread`, `x-thread-valid`, chez_half present after another thread's load, `x-depth-thread` |
| C04 | the path's string check dropped | load-extension 3: `x-path-kinds`, `x-order`, `x-depth` |
| C05 | the path's U+0000 check dropped, left to `call-with-c-string` | load-extension 3: `x-path-nul`, `x-order`, `x-depth`; engines 2: `e-reentry`, `e-reentry-low` |
| C06 | the absolute check dropped | load-extension 4: `x-absolute`, `x-relative-opted`, `x-order`, `x-depth`; engines 1: `e-caller-path` |
| C07 | the absolute check lets a leading `.` through | load-extension 2: `x-absolute`, `x-relative-opted` |
| C08 | the path's copy unused: C handed the caller's string | engines 1: `e-caller-path`, `&sqlite-error` at 45 fuels, a relative path reaching C; **survived the first round** |
| C08e | the entry point's copy unused | engines 1: `e-caller-entry`, `call-with-c-string`'s refusal at 18 fuels; added in round 2 |
| C09 | `""` let through as absolute | load-extension 2: `x-absolute`, `x-relative-opted` |
| C09b | U+0000 checked after absolute | load-extension 2: `x-path-nul`, `x-order` |
| C09c | the U+0000 scan skips the last character | load-extension 4: `x-path-nul`, `x-entry-nul`, `x-order`, `x-depth`; engines 1: `e-caller-entry` |
| C18 | the path's refusal from another who | load-extension 3: `x-path-kinds`, `x-order`, `x-depth` |
| C10 | the entry point's string check dropped | load-extension 3: `x-entry-kinds`, `x-order`, `x-depth` |
| C11 | the entry point's U+0000 check dropped | load-extension 3: `x-entry-nul`, `x-order`, `x-depth`; engines 1: `e-caller-entry` |
| C12 | an entry point that is no string ignored, SQLite's search run | load-extension 3: `x-entry-kinds`, `x-order`, `x-depth` |
| O02 | the entry point checked before the path | load-extension 2: `x-path-kinds`, `x-order` |
| C13 | the opt-in's check dropped, §4.7's Q3 plant | load-extension 6: `x-absolute`, `x-entry-nul`, `x-opt-in`, `x-opt-in-message`, `x-switch-on`, `x-depth`; docs 1 of 107: the new block |
| C14 | the opt-in checked before the arguments | load-extension 7: `x-path-kinds`, `x-path-nul`, `x-absolute`, `x-entry-kinds`, `x-entry-nul`, `x-order`, `x-depth` |
| C15 | the opt-in's refusal raised inside a critical section | load-extension 1: `x-depth` |
| C16 | the opt-in's message without the fix | load-extension 1: `x-opt-in-message` |
| C17 | the opt-in's rule renamed | load-extension 5: `x-absolute`, `x-entry-nul`, `x-opt-in`, `x-switch-on`, `x-depth`; docs 1 |
| S01 | the claim dropped, §4.7's "the load's claim dropped" | engines 7 of 14: `e-twice`, `e-interleave`, `e-reentry`, their low passes, `e-depth` |
| S02 | the claim compared before the critical section | engines 6: `e-twice`, `e-interleave`, `e-reentry` and their low passes |
| S03 | a flag set after the section in place of the claim | engines 1: `e-interleave-low`, 655 trials ran two inits where 492 are whole new calls, at fuels 9 to 62, past the sweep's first refusal at 9; **survived the first round** |
| S04 | the claim made after the checks, not by the first expression | engines 6: `e-twice`, `e-interleave`, `e-reentry` and their low passes, each refused at too few fuels: `e-interleave` at 1 of 60, its whole new calls all below its one refusal at 59 |
| S05 | the claim in a section of its own, the call outside it | engines 6: the same |
| S10 | the section's critical section dropped, the claim compared outside one | engines 6: the same |
| S06 | the claim at position 1, never made | load-extension 20; engines 11 |
| S07 | the claim not the call's last | **survived**, below |
| S08 | a refused run answers nothing | engines 7: `e-twice`, `e-interleave`, `e-reentry`, their low passes, `e-depth` |
| S09 | a refused run raises an assertion violation | engines 7: the same |
| K01 | NULL passed for every entry point | load-extension 4: `x-named`, `x-failures`, `x-stand-in`, `x-freed`; engines 1: `e-caller-entry` |
| K02 | the path's C string passed as the entry point when none is given | load-extension 12; engines 10 |
| K03 | a failure's code read from the connection, §4.7's plant | load-extension 8: `x-named`, `x-failures`, `x-constraint`, `x-held`, `x-empty-slot`, `x-not-an-error`, `x-freed`, `x-depth-failures` |
| K04 | the extended code "before" read after the call | load-extension 3: `x-held`, `x-held-whole`, `x-colon` |
| K05 | the connection's message dropped, §4.7's plant | load-extension 3: `x-held`, `x-held-whole`, `x-colon` |
| K06 | the connection's message always appended | load-extension 3: `x-failures`, `x-constraint`, `x-empty-slot` |
| K07 | the message from `sqlite3_errmsg`, not the slot | load-extension 5: `x-failures`, `x-constraint`, `x-held-whole`, `x-colon`, `x-empty-slot` |
| K08 | an empty slot's message "", no `sqlite3_errstr` | load-extension 1: `x-empty-slot` |
| K09 | the two messages always joined as they stand | load-extension 1: `x-colon` |
| K10 | the two always joined with ": " | load-extension 1: `x-held-whole` |
| K11 | a code that names no error left to `raise-sqlite-error` | load-extension 2: `x-not-an-error`, `x-depth-failures` |
| K12 | a code that names no error taken as success | load-extension 2: the same |
| F01 | the message never freed, §4.7's plant; gate | load-extension 3: `x-success-freed`, `x-copy-raises`, `x-freed`, and the exit's memory check, 7232 bytes; the gate's Valgrind, 7,080 bytes in 24 blocks definitely lost |
| F02 | freed only on a failure, a message on the success path left; gate | load-extension 1: `x-success-freed`, and the memory check, 344 bytes; the gate, 352 bytes in 1 block |
| F03 | not freed when the copy raises, §4.7's plant; gate | load-extension 1: `x-copy-raises`, and the memory check, 688 bytes; the gate, 704 bytes in 2 blocks |
| F04 | the copy unguarded, its raise skipping the free | load-extension 1: `x-copy-raises`, and the memory check |
| F05 | the message freed before the copy; gate | load-extension 6: `x-failures`, `x-constraint`, `x-held-whole`, `x-colon`, `x-copy-raises`, `x-freed`, their held counts read after the free; the gate, 3789 errors from 1 context |
| R02 | a failure raised inside the section | **survived**, below |
| N01 | `sqlite3_load_extension` bound plain, §4.7's plant | native 1 of 117: the load's FIFO row |
| D01 | the verb's library touching the binding at its load | loading-real 1: `l-load-lacking` |
| P01 | `load-extension!` not exported | load-extension 29; engines 12; public 4 of 23; reference 3; docs 1; loading-real 2 |
| P02 | the signature comment changed | reference 2 of 22: the whole-page row, `r-line` |
| Q01 | `sqlite3_enable_load_extension` called at every open that opts in | load-extension 1: `x-sql` |
| X01 | `CC=false`: no compiler | load-extension 14: `x-build`, `x-decision`'s build, every load row after them, `x-end`; engines 11 |
| X02 | `C_INCLUDE_PATH` and `CPATH` unset: no `sqlite3ext.h` | load-extension 14 and engines 11, the same |
| X03 | the suites told the library has no `sqlite3_load_extension` | the unavailable branch reached: load-extension prints 25 UNAVAILABLE lines, the build among them, engines 12; the refusals they assert in place fail, load-extension 24 of 42 and engines 12 of 14, since this library lets the open opt in |
| X04 | the build skipped everywhere, `built-where-loadable` always unavailable | load-extension 14: `x-build`, `x-decision` and the load rows; engines 11 |
| X05 | the build made everywhere, the decision ignored | load-extension 1: `x-decision`, its directory written |

**62 plants: 60 caught, 2 survived, each argued below.** All 62 ran on the final tree,
`build/mut/final/`. The first round, `build/mut/r1/`, ran 58 on the first round's suites, with C08
and S03 surviving too, and the arguments the review overturned (round 2). The M4 plan's §4.7
names C13 (the verb's refusal dropped), C01 with O01 (the owner checks), K03 (the code), K05 and
F01 to F03 (the messages, unfreed), N01 (the load bound plain) and S01 (the claim). The rest are
the builder's, one at least at every site of `(chez-sqlite3 private extension)` and of
`(extension-build)`'s decision.

## The survivors, argued

- **S07, the claim not the call's last.** `made-claim`'s `last?` decides whether a later claim
  of `#f`, the conveniences' give-back after a raise, can still land; the verb makes one claim,
  of position 0, and never one of `#f`. With the call's position advanced to 1, a second run's
  claim of 0 is refused either way. Equivalent.
- **R02, a failure raised inside the section.** `load-section`'s own guard, inside the critical
  section, is the innermost handler, so it catches the raise there, the same object, and the
  verb raises it after the section: a caller's `with-exception-handler` never runs inside.
  Equivalent while that guard catches everything; the rule, answer data and raise after, stays,
  since a narrowed guard would expose it, as C03 and C15 show for the checks.

## Round 2: the review's findings

The slice's read-only Opus review of `ebc9b14` found the verb's code sound, and two majors and five
minors in the suites, the docs and this log. The lead reproduced both majors. Each is fixed here,
test first, each new row watched failing against a plant in a copy under `build/`.

- **Major 1: S03 was not equivalent, and the first round's first trap was false.** The first
  round argued no tick falls after the load's section, so a flag set just after it could not be
  split from it. But a collect request that falls due inside a critical section is handled at the
  section's exit, and costs the engine ticks there, so an engine can expire just past the
  section, though no call follows it. The sweeps' `quieted!` raised `collect-trip-bytes` to
  2^27, so no request fell in a trial: that is why the straddle count read 0. Now `e-twice`,
  `e-interleave` and `e-reentry` each run a second pass whose trials collect first, then set the
  trip to 256 bytes, below what one call allocates, until the trial ends. Each trial is judged by
  its own inits, each bound is a refusal the sweep saw itself, and each low pass fails by name
  unless it reaches past the section: `e-interleave-low` asserts a trial with R before the section
  and R1 past it, 186 of 2134, and `e-twice-low` and `e-reentry-low` a remainder and a
  continuation taken past it, 3 each. S03 fails `e-interleave-low`: 655 trials ran two inits, 163
  of them past the sweep's first refusal, at fuel 9. The trap is corrected below.
- **Major 2: C08 was not equivalent, and the entry point's copy survived too.** The caller's own
  code runs between an engine's expiry and its resume, so it can change the string it handed the
  verb there, on its own thread. The review's probe did that at each fuel. Its sweep is now two
  rows: `e-caller-path` makes the path's `/` an `x`, `e-caller-entry` the entry point's last
  character U+0000; each fuel must load with chez_half present, the change made after the check,
  or be refused by the check's own rule, the change made before it, and both must be seen. C08
  raises `&sqlite-error` at 45 fuels, a relative path handed to C; C08e, a new plant handing C the
  caller's entry point, raises `call-with-c-string`'s refusal at 18.
- **Minor 1: the interleave's bound moved with the code.** `e-interleave` let a trial run two
  inits where `interleaved-control`, run on the code under test at the same fuel, had made a whole
  new call, and its `was-new` let one through at the control's first refused fuel too, which
  AGENTS.md and ADR-0016 forbid. The control is gone: a trial's two inits must come below the
  first fuel at which a trial of the sweep was refused, R taken before the section, and the sweep
  must see refusals at half its fuels. S04, the claim made after the checks, passed the old row;
  it fails the new one by the count, refused at 1 fuel of 60, its whole new calls all below that
  one refusal, at 59. The bound alone can't see S04, which moves its own first refusal.
- **Minor 2: the memory rows had no positive control, and two rows asserted no code.**
  `x-success-freed`, `x-copy-raises`, `x-memory` and `x-freed` now read `sqlite3_memory_used`
  while the message, or the extension, is held, by the stand-in, the copy or the suite, and assert
  it higher there and back after; where the library keeps no count, a row of the suite's own
  reading, they print UNAVAILABLE and assert the three alike. `x-success-freed` asserts its
  precondition, the real load's answer 1 and a message in the slot; `x-failures` and
  `x-constraint` assert the raw call's code, 1. `x-freed` now runs the verb's work through
  `load-extension/with` with native's binding and a copy that reads the count, then copies.
- **Minor 3: the docs' Extensions said four things not true on every library.** A failure's
  message names the path tried last only when the file can't be opened; out of memory gives
  `nomem`; an init answering `SQLITE_OK_LOAD_PERMANENTLY` stays loaded past the close; and a
  loaded extension can turn SQL's `load_extension()` on. The page now says each as it is.
- **Minor 4: the build where nothing can load it** (the maintainer's "Build named unavailable
  there"). Where native records no `sqlite3_load_extension`, `built-where-loadable` answers
  `(unavailable)` and compiles nothing; both suites print the build UNAVAILABLE and assert the
  opt-in's refusal in its place. Everywhere else a missing compiler or header still fails.
  `x-decision` holds both branches of the helper, and X03, the suites told the library lacks the
  entry point, reaches their unavailable branch here; X04, the build skipped everywhere, fails on
  this library, and X05, the decision ignored, fails `x-decision`.
- **Minor 5: the suites mapped calls of the verb.** Each call of the verb, `load-extension/with`
  or a thread is now made in order by `in-order`, a named let, or the suites' own loops.

## For the records

- **ADR-0021, slice 4's amendment (proposed):**
  - the verb's library, `(chez-sqlite3 private extension)`, exporting `load-extension!` and, for
    the suites, `load-extension/with`, which takes the load's binding and the message's copy, as
    `interrupt-database/with` and `applied-settings/with` take theirs;
  - the refusals' rules: `not-a-database`, `path-not-a-string`, `path-holds-nul`,
    `path-not-absolute`, `entry-point-not-a-string`, `entry-point-holds-nul` and
    `extension-loading-not-enabled`, each value by `shown-value`;
  - the first three checks are one `call-with-open-handle` in a critical section of its own,
    whose `check-owned` is the verb's own owner check; the load's section checks the owner again;
  - each string is copied, the copy checked and handed to C: `e-caller-path` and
    `e-caller-entry` hold it against the caller's own code between an expiry and its resume;
  - the claim is the conveniences' `made-claim`, position 0, the call's last, compared first in
    a critical section around `call-with-open-handle`;
  - **a code that names no error,** its low byte 0, 100 or 101 but not 0, or no exact integer,
    is an assertion violation from the verb, `(not-an-error CODE)`. Decision 7 says nothing of
    it; only a stand-in answers one, and it follows decision 3's amendment of M4 slice 1;
  - **the message's join:** the slot's text, or `sqlite3_errstr`'s, then the connection's,
    joined as they stand where the first is empty or ends in a space, else with ": ". Decision 7
    says "followed by"; rv1's part B's text is the first case;
  - a message in the slot is freed on the success path too: the real binding leaves NULL there,
    a stand-in can leave one (`x-success-freed`);
  - the engine rows' figures, the table above, both passes.
- **ADR-0001, decision 3, narrowed** (the maintainer's "Build named unavailable there"), as
  ADR-0002's amendment did for the optional prototype: the suites' extension is compiled only
  where native records `sqlite3_load_extension`; where it records none, the build is named
  unavailable and the opt-in's refusal asserted in its place. Everywhere else a missing compiler
  or `sqlite3ext.h` still fails the suite. ADR-0021's consequences say the build always fails
  without them, and want the same line.
- **ADR-0016, or AGENTS.md's sweep rules:** a sweep that holds a claim inside a section runs a
  pass with collect requests in its trials, `collect-trip-bytes` below what a call allocates;
  without it, no remainder lands just past a call's last section (the first trap below).
- **ADR-0013's M4 amendment:** the refusal names above, under its "M4's refusals of a caller's
  mistake".
- **The M4 plan's §4.7:** "the verb's owner check dropped" is C01, the first section dropped,
  since the verb's owner check is that section's `check-owned`; "the message left unfreed ...
  after a copy that raises" is reached through `load-extension/with`'s stand-in copy, since
  `c-string->string` never raises on SQLite's message; and the decoy's load rows need
  `refusal-probe.sps`' `--loads`, not `--opens`: no connection of the decoy reaches a load.
- **ADR-0005 and the Makefile's shards:** both new suites in `MEMORY_SUITES_2`, by the sums above;
  `test-library-loading-real` 191 s under the gate here, two more children.
- **The global constraints' "`db_config` and extensions":** the `load-extension!` bullet could
  add the code that names no error, and that the message is freed whatever the call answered;
  "Environment and tests" could name the build's exception.
- **traps.md:** the two traps below.
- **The Mac step,** owed by the plan's §5 after slices 3 to 5: `test-load-extension` and its
  engines suite with Apple's library, whose load rows and build print unavailable; and with
  Homebrew's, the extension a `.dylib` built `-dynamiclib`, the suffix's retry `.dylib`,
  `x-failures`' dlsym cases compared by kind alone, since macOS's dlsym message names a handle
  (research/m4-mac/, run 1).

## The traps the slice found

- **A collect request due inside a critical section is handled at its exit, and costs an
  engine's ticks there.** So an engine can expire just past a call's last section, though no
  procedure call follows it, and a sweep that raises `collect-trip-bytes` to keep requests out of
  its trials never sees a remainder there. The first round's sweeps did, read a straddle count of
  0, and called a flag set just after the section (S03) equivalent; the review found it fails.
  Hold a claim inside its section, and sweep a pass with the trip below what one call allocates.
  Reproduce: `test-load-extension-engines`' `e-interleave` reads "both past the section in 0; R
  before it and R1 past it in 0", and `e-interleave-low`, the same sweep under a trip of 256
  bytes, "in 3" and "in 186"; `mut.py --into build/mut/x prepare S03-flag-set-after-the-section`,
  from [the driver](research/m4-slice-4/scripts/), fails `e-interleave-low` alone.
- **`call-with-open-handle` called outside a critical section exposes its wind to an expiry.**
  A remainder taken inside its `dynamic-wind`, before its section, and resumed a second time,
  meets its before thunk's refusal, `re-entered`, an assertion violation, where the claim would
  have raised `&sqlite-closed`. open.sls's `in-section` and the conveniences' wrap it in a
  critical section; the verb's open check does too. Reproduce: C19's copy, whose `e-twice` reads
  `(second (raised (assertion-violation load-extension! (re-entered))) 0)` at fuels 15 to 17.
