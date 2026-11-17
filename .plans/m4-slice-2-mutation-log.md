# M4 slice 2 mutation log

Evidence that each rule slice 2's suites claim to guard fails through the property it names
([the M4 plan](2026-11-17-m4-plan.md) §4.2, §4.3, §4.6, §4.7 and §5 item 2). Format of
[the M3 slice 6 log](m3-slice-6-mutation-log.md). An Opus agent built the slice from the lead's
brief, in the worktree `chez-sqlite3-wt-m4s2`, on `m4-slice-2-bindings` from slice 0's head
`fd4831c`, beside slice 1 and slice 5 in worktrees of their own; the branch was later moved onto
`main` at `87e762c`, whose tree is `fd4831c`'s. The coordinator added two items during the
build: a counted int cell for slice 3, and, after the slice's read-only Opus review, the review's
seven fixes. The seventh, a fourth entry point, `sqlite3_stmt_busy`, was built and then taken out
again, when the maintainer chose "Vouch only for ours" for the close (below). Every count below
is from the third round, run on the tree as it now stands; the earlier rounds' survivors, and what
they changed, are in their own section.

## What the slice adds

- **`(chez-sqlite3 private native)`,** native's seventh step after M3's five, M4's two
  required entry points, then its optional one:
  - `sqlite3-db-config : Positive-Integer Integer Integer Positive-Integer -> Integer`, the
    plan's §4.2 form, `(bind-required report (foreign-procedure (__varargs_after 2)
    "sqlite3_db_config" (uptr int int uptr) int))`, plain;
  - `sqlite3-free : Natural -> Void`, required, plain;
  - `sqlite3-load-extension : (U (Positive-Integer Positive-Integer Natural Positive-Integer ->
    Integer) #f)`, `__collect_safe`, through a new binder, `bind-optional`, which answers the
    form's procedure when `foreign-entry?` finds the entry point and `#f` when not, and never
    refuses;
  - `load-extension-available? : Boolean`, `(if (procedure? sqlite3-load-extension) #t #f)`,
    defined right after that step, so the record and the binding can't disagree;
  - `call-with-int-cell : Symbol Integer (Positive-Integer -> A) -> (Values A Integer)`, the
    coordinator's first item: a counted int block written with the caller's fill, PROC given
    its address, the int read after PROC returns; a fill no C int holds, `c-int?` by
    `(foreign-sizeof 'int)`, refused from WHO before anything is allocated.
  The convention's text, `(__varargs_after 2)`, stands in `native.sls` once, in the form: no
  comment writes it, since `check-variadic` counts its lines, and `test-check-variadic` holds the
  count to one.
- **`(chez-sqlite3 private constants)`:** `sqlite-dbconfig-enable-load-extension` 1005,
  `sqlite-dbconfig-defensive` 1010, `sqlite-dbconfig-dqs-dml` 1013 and
  `sqlite-dbconfig-dqs-ddl` 1014, each `Natural`.
- **`tests/foreign-conventions.sls`:** three rows, `sqlite3_db_config` `variadic` with the
  prototype `("int" ("sqlite3*" "int" "..."))`, `sqlite3_free` plain, and
  `sqlite3_load_extension` collect-safe, whose records alone say "an optional entry point";
  `convention-forms`, the one place the conventions' text is written, `variadic` exactly
  `((__varargs_after 2))`, and `convention-of` read from it, both exported; one fender mention
  allowed for each binder, `bind-required` and `bind-optional`.
- **`tests/library-loading.sls`:** `sqlite3_db_config` and `sqlite3_free` at the end of
  `rest-entries`, so `every-entry` holds 43; `optional-entries`, `("sqlite3_load_extension")`;
  the parts, by position in `every-entry`, `sqlite3_db_config` at 41 to `-decoys` and
  `sqlite3_free` at 42 to `-missing`, no earlier entry moving; a lacking build for each optional
  entry point too.
- **`tests/decoy-libsqlite3.c`:** the three, `DECOY_LACKS_` each, so the control has 44 entry
  points; its `sqlite3_db_config` is defined variadic and reads its two variadic arguments with
  `va_arg`.
- **`tests/refusal-probe.sps`:** `--extension-loading yes` prints
  `(load-extension-available? . BOOLEAN)` after a load's threadsafe line.
- **`tests/test-constants.sps`:** the optional entry point's prototype asked in a compile of its
  own (below), and the one compile asking the 43 required rows.
- **`tests/check-variadic.sh`,** written from the plan's §4.2 (below); its suite
  `tests/test-check-variadic.sps`; the Makefile's `check-variadic` target, `.PHONY` entry and help
  line, and the suite in `MEMORY_SUITES_1`.
- **CI:** `ci.yml`'s `main` "Checks and suites" line gains `check-variadic` after
  `check-test-fails`; `tests/check-ci.sh`'s `MAKELINE` and `tests/test-check-ci.sps`' copy, and
  its list of the line's words, move with it.

## How the mutants ran

Every mutation ran in a copy of the worktree of its own, `build/mut3/NAME/`, made by
`tar --exclude=./build --exclude=./.git --exclude=./.plans/research`, with exact-text edits, each
checked to occur as often as expected before it was written. The copies ran inside the
worktree's container, after `make deps` in each, each suite under `timeout 300`, on Guix's
3.53.1; a copy's `.env`, where it has one, puts the review's stand-in header first on
`C_INCLUDE_PATH`. The counts are read from the suites' own `# of unexpected failures` lines, never
by eye. The drivers, `mutants.py`, `mutants2.py`, `mutants3.py`, `describe.py` and `run-mutants.sh`,
are kept in [research/m4-slice-2/scripts/](research/m4-slice-2/scripts/), run from the
worktree's root; the copies, the results and every log are made under the git-ignored
`build/mut3/`. The first round's were under `build/mut/`, the second's, with
`sqlite3_stmt_busy`, under `build/mut2/`.

## The red runs

The rows, and the test helpers that state what they expect (the convention table,
`(library-loading)`'s lists, the probe's option, `check-variadic`'s suite), were written first.
The red copy, `build/mut3/red-final`, is the tree as it now stands with `fd4831c`'s `native.sls`,
`constants.sls`, decoy, probe, Makefile, `ci.yml` and `check-ci.sh`, and no `check-variadic.sh`.
Every row that reaches new code fails by name: `test-native` reaches native through `eval`, and
the ops through `op-of`, an `eval` too, so the suite runs where an import would die unnamed.

| Suite | Red | Green, Guix's 3.53.1 |
|---|---|---|
| `test-conventions` | 53 passed, 11 failed | 64 passed |
| `test-constants` | 51 passed, 3 failed | 54 passed |
| `test-native` | 97 passed, 20 failed | 117 passed |
| `test-library-loading-decoys` | 39 passed, 1 failed | 40 passed |
| `test-library-loading-real` | 46 passed, 2 failed | 48 passed |
| `test-library-loading-missing` | 34 passed, 1 failed | 35 passed |
| `test-check-ci` | 426 passed, 14 failed | 440 passed |
| `test-check-variadic` | 1 passed, 38 failed | 39 passed |

- **`test-native`'s 20** are every new or changed row: the exports, the three steps rows, the
  three round trips, the unknown op, the free of NULL, the record,
  the seven `call-with-int-cell` rows, and the three load rows in their UNAVAILABLE form, since
  native's record could not be read. Their available forms fail by the plants below.
- **`test-conventions`' 11** are `src:`'s two rows and its nine sweeps: native had no form for the
  three new rows. The rest of its new rows are the reader's and the table's, which the red code
  doesn't touch; each fails by a plant below.
- **`test-constants`' 3** are the exports row, the values row and the four ops written out. Its
  variadic map rule, its near-miss rows and the optional prototype's own compile test the suite's
  own rules against the table, and fail by plants.
- **`test-library-loading-real`'s 2** are the two optional rows.
- **`test-check-variadic`'s one pass** is its first row, that a real `sed` is on PATH.
- In the first round the first red run of `test-native` died at compile twice, a `round-trip`
  defined twice, then an import of the four ops that `fd4831c` lacks; `op-of` fixed the second.

**Green:** `make test` ran 74 and passed 74, against the baseline's 73 of 73, the new suite added,
on Guix's 3.53.1, at the floor's 3.45.1 and on the `current` lane's 3.54.1, each with
`CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH` naming the lane's build. No suite printed UNAVAILABLE
on any of the three: each has `sqlite3_load_extension`. `make check-test-fails` failed make test
in all 16 of its cases, as it must, in the second round; the Makefile, the workflow and
`check-ci.sh` are untouched since.

### The touched suites' times

Plain, each alone in the container, one run a library, by `date` around it; and under
`make test-memory` on Guix's 3.53.1, the seven `sqlite3_stmt_busy`'s removal touched in one run,
by the gate's `time:` lines, none `SLOW`; `test-check-ci`'s are the second round's.

| Suite | Guix's 3.53.1 | Floor's 3.45.1 | `current`'s 3.54.1 | Under the gate |
|---|---|---|---|---|
| `test-conventions` | 2.2 s | 1.8 s | 2.3 s | 36 s |
| `test-constants` | 1.1 s | 1.1 s | 1.1 s | 11 s |
| `test-native` | 2.9 s | 2.9 s | 2.9 s | 19 s |
| `test-check-ci` | 18.1 s | 18.2 s | 18.3 s | 101 s, second round; untouched since |
| `test-check-variadic` | 2.1 s | 2.4 s | 2.3 s | 12 s |
| `test-library-loading-decoys` | 4.6 s | 4.5 s | 4.4 s | 160 s |
| `test-library-loading-real` | 4.1 s | 4.2 s | 4.1 s | 153 s |
| `test-library-loading-missing` | 4.8 s | 4.9 s | 4.7 s | 145 s |

The slice adds one gated child to `-decoys` (`sqlite3_db_config`'s missing-api row), one to
`-missing` (`sqlite3_free`'s) and two to `-real` (the build without `sqlite3_load_extension`,
and the control with `--extension-loading`). No baseline of the three
under the gate was taken at `fd4831c`, and one local run is one sample: CI's runs are the times
the records want.

## `make check-variadic`

On Guix's library, all seven steps ok, 11 s and 10 s by `date` around `make check-variadic`
inside the container, `make deps` included:

```
check-variadic: ok copy: src/, tests/ and .plans/decisions/ copied to a scratch tree
check-variadic: ok machine: Chez's machine type is ta6le
check-variadic: ok control: tests/test-conventions.sps passes on the unchanged copy (exit 0)
check-variadic: ok control: tests/test-native.sps passes on the unchanged copy (exit 0)
check-variadic: ok mutant: (__varargs_after 2) stood on one line of src/chez-sqlite3/private/native.sls; removed, it stands on none, and no other line changed
check-variadic: ok static: tests/test-conventions.sps fails on the mutant (exit 1), naming exactly the ten tests that hold the table to src/, its violations exactly ((mismatch "sqlite3_db_config" convention variadic plain))
check-variadic: ok other: on ta6le, tests/test-native.sps passes on the mutant (exit 0), as expected: this ABI passes variadic arguments as it passes named ones, so only Apple arm64 (arm64osx, tarm64osx) can show the mutation by behaviour
check-variadic: all 7 steps ok, on ta6le
```

- **Written from §4.2, none of chez-curl's code.** The review measured the first version: 82 of
  its 150 distinct non-comment lines stood verbatim in chez-curl's `tests/check-variadic.sh`. The
  script was written again from the plan's four steps, without that file open, in a structure of
  its own: a scratch tree whose path the suite's stand-in can tell from the tree's, a `suite`
  runner, `failures`, `counted`, `actual_for`, `holding` and `changed_between` as the evidence,
  `account` for a run in words, the static step's reasons gathered in a file and compared with
  `cmp`, and the arm64 decision through a flag. Measured the review's way, both files with
  leading and trailing space stripped, comment and blank lines dropped, `sort -u`, then
  `comm -12`: of its 167 distinct lines, six stand in chez-curl's 229, `}`, `done`, `else`,
  `esac`, `exit 1` and `fi`.
- **"Its only failing tests those that read the variadic row"** (the plan, §4.2) are written out
  in the script's `expected_failures`, ten names, compared whole and in order: `src: no
  violation` and the nine sweeps that hold the whole table, the variadic row among it, to the real
  `src/`. Every sweep reads `src/`, so every sweep sees the mutant. **`make test` holds the list
  to the tree:** a row of `test-check-variadic` reads `test-conventions.sps` as data and requires
  the list to be exactly the names of its `test-equal` forms that call `violations` on `"src"`, in
  order; another requires `native.sls` to hold the convention's text on one line, its comments
  counted. The review renamed one sweep and only CI's step caught it; now `make test` does (M73).
- **The arm64 step needs the binding:** a failing test of `test-native`'s that names
  `sqlite3_db_config`, or a death; a failure naming only other tests fails the step (V12).
- **The machine is Chez's own answer** to `(display (machine-type))`, through `--script`, never
  `uname`. `test-check-variadic` holds the decision on a Linux host: its stand-in CHEZ answers
  `arm64osx` and `tarm64osx`, and the plant that reads `uname` instead fails 9 rows (V07).
- **The suite runs the real script** in trees of its own, with stand-ins for CHEZ, TIMEOUT and,
  in one row, `sed`, and asserts every exit status, stdout and stderr whole, and the stand-ins'
  log of the calls in one: the question, then each suite in the copy, never the tree, with the
  tree's `build/scheme-libs`, under `TIMEOUT --foreground TEST_TIMEOUT`. No Chez runs, so it
  takes 2 s plain and no child of it reaches native code.

## The optional entry point's own compile

The review's second item. `test-constants` asked every row's prototype in one compile, and that
came to include the optional `sqlite3_load_extension`, which Apple's SDK `sqlite3.h` is believed
to mark unavailable on macOS: the review's stand-in header,
`.plans/research/m4-slice-2/stand-in/sqlite3.h`, the review's,, `#include_next` and a redeclaration with
`__attribute__((unavailable))`, failed the one compile and nine header rows with it.

- **The one compile** now asks the 43 required rows, and a row says so: 43, and
  `sqlite3_load_extension` apart.
- **Each optional row is asked in a compile of its own,** with its near miss. `optional-verdict`
  decides, native's record read only when the compile failed, through `eval`: the compile ran and
  declares it, `declared`; it ran and answers otherwise, `not-declared`; it failed and native
  records the library without the entry point, `unavailable`, printed UNAVAILABLE, and the row
  asserts, in place of the prototype, that the compile step failed and the record is `#f`; it
  failed and the library has the entry point, or the record can't be read, `compile-failed`, and
  the row fails. A row holds the rule on facts and records written there, native asked or not
  asked as it should be. So on Linux, where every compile runs, `test-constants` still loads no
  libsqlite3.
- **Watched,** in the container, with `C_INCLUDE_PATH` naming the stand-in first and the
  profile's include after it, as `#include_next` needs: on Guix's library, 53 passed and 1 failed,
  the optional row, `((compile-failed the-library-has-it compile) (near-miss compile))`, where the
  first version had failed nine; with `CHEZ_SQLITE3_LIBRARY` naming a decoy built
  `DECOY_LACKS_sqlite3_load_extension`, the row printed UNAVAILABLE and all 54 passed, the suite
  exiting 1 only by the decoy's memory check, whose control open the decoy refuses, `cantopen`.
  Against the real headers of the three libraries, the row is `declared`, and its near miss 0.
  The plants M63 to M68 hold it.

## The load's FIFO row, and the loader's lock

The row follows the open's (ADR-0011's M1 slice 2 amendment): the connection's
`ENABLE_LOAD_EXTENSION` set to 1 through the new binding, a load of a FIFO on one thread, a
collection on another a second after the loader called, and the collector, its collection done,
opening the FIFO for writing, which releases the loader. A watchdog shell outside the process does
the same after 30 s, leaving a marker first. **The verdict is who released the loader:** with the
load bound plain the collection, and the collector with it, waits for the load, and only the
watchdog can end it, so the row fails `released-by-the-watchdog` (M04 and M05). The loader also
notes whether the collection had finished when its call returned: a load that never waited, as
one that never opened the FIFO would, fails the row too. The brief's "the watchdog, not the
collector, releases the load" is read as the plan's §4.7 has it, the plain plant's outcome by the
open row's method; a row whose watchdog released every load would wait out its delay on every
run, under the gate too, where the collector's release takes about 1 s.

**Its hung branch is bounded end to end** (the review's sixth item): a loader still waiting once
its bound has passed is released there, the FIFO opened for writing, and waited for again, 30 s
at most, before the connection's close, which would otherwise wait for the load holding the
connection's mutex. The row then fails by name, `the-loader-hung`, and the suite goes on. With
the loader's bound planted at one 10 ms wait and the collector's release taken out, M71, the
row failed by name, `(the-loader-hung released (0 "" "") then satisfied)`, and the suite ended in
3 s; without the branch's release too, M72, the close waited for the watchdog, and the suite took
32 s.

**The trap:** while `dlopen` waits on the FIFO, glibc's dynamic loader holds its lock, and a
thread made then waits for it. The first version forked the collector after the loader, and its
collection finished a second after the load, released by the 15 s watchdog, under the
`__collect_safe` binding. Measured with `.plans/research/m4-slice-2/fifo-thread.sps` in the container (glibc
2.41): a `fork-thread` called 0.5 s into a blocked load returned at 3957 ms, when the load did.
So the row forks the collector first, and the loader, the last thread it makes, after it;
`capture-command`'s shell, which the collector starts, doesn't wait. Reproduced by:

```
scripts/guix-env sh -c 'd=$(mktemp -d); mkfifo $d/f.fifo; (sleep 4; exec 3<>$d/f.fifo) & \
  $CHEZ --script .plans/research/m4-slice-2/fifo-thread.sps "$CHEZ_SQLITE3_LIBRARY" $d/f.fifo; wait'
```

which prints `fork-thread called 501, returned 3957; new thread ran 3957; load returned 3957`.

## The mutations

The suites: `test-conventions` (conventions), `test-constants` (constants), `test-native`
(native), the three `test-library-loading-*` (decoys, real, missing), `test-check-ci` (check-ci)
and `test-check-variadic` (check-variadic); and, for the Makefile and workflow, the make target
named. Baselines: 64, 54, 117, 40, 48, 35, 440 and 39. Each cell names a suite, how many of its
rows failed, and the run's time; one that passed reads "(exit 0)" with 0. A mutation counts as
caught when one row, or one make target, failed.

| Mutation | Guards | Failed rows, and time |
|---|---|---|
| M01 | check-variadic's own mutant: the convention removed from `sqlite3_db_config`'s form | conventions 10, 2s; native 0 (exit 0), 3s; constants 0 (exit 0), 1s |
| M02 | the table's `sqlite3_db_config` row made plain | conventions 17, 2s; constants 1, 1s |
| M03 | the same row made collect-safe | conventions 17, 2s; constants 1, 1s |
| M04 | the load bound plain, in `native.sls` alone | conventions 10, 2s; native 1, 32s |
| M05 | the load bound plain, its row made plain too | conventions 5, 2s; native 1, 32s |
| M06 | `bind-optional` refusing an absent entry point, `missing-api` | real 1, 5s; native 0 (exit 0), 3s |
| M07 | `load-extension-available?` always `#t` | real 1, 5s; native 1, 2s |
| M08 | `load-extension-available?` always `#f` | real 1, 4s; native 5, 2s |
| M09 | the decoy's `DECOY_LACKS_sqlite3_db_config` inverted | decoys 7, 5s; real 3, 4s; missing 1, 5s |
| M10 | the decoy's `DECOY_LACKS_sqlite3_free` inverted | decoys 6, 5s; real 3, 4s; missing 1, 5s |
| M11 | the decoy's `DECOY_LACKS_sqlite3_load_extension` inverted | real 2, 4s |
| M12 | `optional-entries` joined to `every-entry`, moved (`optional-entries` empty) | conventions 1, 2s; decoys 2, 5s; real 3, 4s; missing 2, 5s |
| M13 | `optional-entries` joined to `every-entry`, appended (kept in both) | conventions 1, 2s; decoys 3, 5s; real 2, 4s; missing 2, 5s |
| M14 | `sqlite-dbconfig-defensive` 1011 | constants 2, 1s; native 0 (exit 0), 3s |
| M15 | `sqlite-dbconfig-enable-load-extension` 1006 | constants 2, 1s; native 2, 3s |
| M16 | `DQS_DML` and `DQS_DDL` swapped | constants 2, 2s; native 0 (exit 0), 3s |
| M17 | `sqlite3_db_config`'s arguments `(uptr int uptr uptr)` | conventions 10, 2s; native 0 (exit 0), 3s |
| M18 | `sqlite3_db_config` with a count of 3 | conventions 10, 2s; native 0 (exit 0), 3s |
| M19 | a count of 3 in native and in `convention-forms` | conventions 5, 2s; constants 4, 1s |
| M20 | `sqlite3_db_config` `__collect_safe` beside its count | conventions 10, 2s; native 0 (exit 0), 3s |
| M21 | `sqlite3_free` `__collect_safe` | conventions 10, 2s |
| M22 | `sqlite3_free` doing nothing | native 2, 3s |
| M23 | `bind-optional` without its `foreign-entry?` | real 1, 4s; native 0 (exit 0), 3s |
| M24 | `load-extension-available?` from a second `foreign-entry?` | native 1, 3s; real 0 (exit 0), 4s |
| M25 | `sqlite3_free` bound before `sqlite3_db_config` | native 2, 3s |
| M26 | the optional entry point bound before the required ones | native 3, 3s; real 0 (exit 0), 4s |
| M27 | the optional row's records without "an optional entry point" | conventions 1, 1s |
| M28 | the prototype with the variadic tail's `int` and `int*` for `...` | constants 2, 2s; conventions 1, 1s |
| M29 | the prototype with three named parameters | constants 2, 1s; conventions 1, 2s |
| M30 | `convention-forms` without `variadic` | conventions 13, 2s; constants 4, 1s |
| M31 | `convention-of` reading any list headed `__varargs_after` as variadic | conventions 5, 2s |
| M32 | `convention-of` ignoring `__collect_safe` beside the count | conventions 3, 2s |
| M33 | the fender allowance for `bind-required` alone | conventions 12, 1s |
| M34 | two fender mentions allowed a binder | conventions 2, 2s |
| M35 | the reader skipping forms inside `bind-optional` | conventions 14, 2s |
| M36 | the convention not compared for plain rows | conventions 5, 2s |
| M37 | the convention not compared for variadic rows | conventions 5, 2s |
| M38 | the map rule's variadic convention dropped | constants 1, 2s |
| M39 | the map rule's count dropped | constants 2, 1s |
| M40 | the map rule's `variadic-without-ellipsis` dropped | constants 1, 1s |
| M41 | the map rule's argument after the named ones dropped | constants 1, 1s |
| M42 | the map rule's convention test inverted | constants 4, 1s |
| M43 | `_Generic`'s default answering 1 | constants 7, 1s |
| M44 | a constant's row dropped from `test-constants` | constants 3, 1s |
| M45 | the parts: `sqlite3_db_config` moved to `-real` | decoys 1, 4s; real 1, 4s; missing 1, 5s |
| M46 | the probe printing `#t` whatever native records | real 1, 4s |
| M47 | the probe ignoring `--extension-loading` | real 2, 4s |
| M48 | no lacking build for the optional entry points | real 1, 4s |
| M49 | the decoy's `sqlite3_db_config` defined with named `int` and `int*` | decoys 26, 4s |
| M50 | `check-variadic` dropped from `ci.yml`'s line | `make check-ci` exit 2 |
| M51 | dropped from `ci.yml` and `check-ci.sh` together | check-ci 14, 18s; `make check-ci` exit 0 |
| M52 | `check-variadic` before `check-test-fails` in `ci.yml` | `make check-ci` exit 2 |
| M53 | `check-variadic` out of `.PHONY` | `make check-help` exit 2 |
| M54 | its help line dropped | `make check-help` exit 2 |
| M55 | `test-check-variadic` in neither shard | `make check-memory-shards` exit 2 |
| M56 | `call-with-int-cell`'s fill always 0 | native 3, 2s |
| M57 | its cell never freed | native 41, 3s |
| M58 | its cell read before PROC runs | native 7, 3s |
| M59 | its range Chez's foreign int's, to 2^32-1 | native 2, 3s |
| M60 | its range check dropped | native 2, 3s |
| M61 | an inexact integer fill taken | native 1, 3s |
| M62 | the fill checked inside the block's extent | native 1, 3s |
| M63 | the optional prototype asked in the one compile again | constants 1, 1s |
| M64 | the same, with the review's stand-in header first on the path | constants 10, 1s |
| M65 | no plant: the stand-in header first, on Guix's library, which has the entry point | constants 1, 1s |
| M66 | the rule: a failed compile unavailable where native records the entry point there | constants 1, 1s |
| M67 | the same, with the stand-in header first | constants 2, 1s |
| M68 | the rule asking native whatever the compile did | constants 1, 1s |
| M69 | the FIFO row's loader bound one 10 ms wait: its hung branch | native 1, 3s |
| M70 | the same, without the release before the close | native 1, 3s |
| M71 | the hung branch, the collector never releasing the FIFO | native 1, 3s |
| M72 | the same, without the hung branch's release | native 1, 32s |
| M73 | a sweep of `test-conventions` renamed | check-variadic 1, 3s |
| M74 | a comment in `native.sls` writing the convention's text | check-variadic 1, 3s |
| M75 | the script's list naming a stale count, 74 arguments | check-variadic 21, 2s |

| Mutation | Guards | Failed rows of check-variadic, and time |
|---|---|---|
| V01 | "exactly once" dropped | check-variadic 2, 3s |
| V02 | "stands on none after" dropped | check-variadic 1, 3s |
| V03 | "one line changed" dropped | check-variadic 1, 2s |
| V04 | the static step taking any failing status | check-variadic 1, 2s |
| V05 | the failing tests' names not compared | check-variadic 4, 2s |
| V06 | the violations not compared | check-variadic 3, 3s |
| V07 | the machine from `uname` | check-variadic 9, 2s |
| V08 | `tarm64osx` not Apple arm64 | check-variadic 3, 2s |
| V09 | arm64: no evidence asked, a named test or a death | check-variadic 2, 3s |
| V10 | arm64: exit 0 taken, with a FAIL line | check-variadic 1, 3s |
| V11 | arm64: a hang taken, after a FAIL line | check-variadic 1, 3s |
| V12 | arm64: any failing name taken, not only one through `sqlite3_db_config` | check-variadic 1, 2s |
| V13 | the control without the runner's count | check-variadic 1, 2s |
| V14 | the control without the FAIL check | check-variadic 1, 2s |
| V15 | the control without its status | check-variadic 1, 2s |
| V16 | `build/scheme-libs/srfi` unchecked | check-variadic 1, 2s |
| V17 | the suites run in the tree, not the copy | check-variadic 20, 3s |
| V18 | the suites run without TIMEOUT | check-variadic 1, 2s |
| V19 | another machine's failure failed, not reported | check-variadic 1, 3s |
| V20 | the machine question's status unread | check-variadic 1, 2s |
| V21 | the machine read loosely, its last line | check-variadic 1, 2s |
| V22 | the usage check dropped | check-variadic 1, 2s |
| V23 | a failing run exiting 0 | check-variadic 13, 3s |
| V24 | the mutation not written to the copy | check-variadic 23, 2s |
| V25 | the static step running `test-native` | check-variadic 21, 3s |

## The survivors, argued

Each is a suite that passed a plant another suite caught, never a plant nothing caught.

- **M01, M17, M18 and M20 pass `test-native`,** and M01 `test-constants`: on x86-64 a
  variadic `int` and `int*` go where named ones do, and `sqlite3_db_config` answers alike bound
  without the convention, with a count of 3, with the value as a `uptr` or `__collect_safe`
  (ADR-0001, amended: "no Linux behaviour row can see the convention lost"). `test-constants`
  reads the table, not `native.sls`. Only `test-conventions` can hold the form on Linux, and
  `check-variadic`'s arm64 step is what holds it by behaviour, on the maintainer's Mac.
- **M06 and M23 pass `test-native`:** every Linux library has `sqlite3_load_extension`, so
  `bind-optional`'s absent branch is never reached there. The decoy built without it is the input
  that reaches it, in `test-library-loading-real`: M06 refuses it `missing-api`, and M23 binds a
  missing entry point, Chez's "no entry for", `load-failed`.
- **M14 and M16 pass `test-native`:** 1011, `WRITABLE_SCHEMA`, round-trips as `DEFENSIVE` does,
  and `DQS_DML` and `DQS_DDL` round-trip each other. A round trip holds the binding, not which op
  a name is; `test-constants` holds the names to the header, and failed both.
- **M24 and M26 pass `test-library-loading-real`:** a second `foreign-entry?` answers what
  `bind-optional`'s did in a process holding one SQLite, and binding the optional entry point
  first changes no refusal, since the lacking build loads either way. `test-native`'s body rows
  hold where the record comes from and the step's place; both failed.
- **M51 passes `make check-ci`:** the workflow and the rule moved together, as a deliberate edit
  would. `test-check-ci`'s copy of the line holds it, 14 rows.
- **M70 ends in 3 s, as M69 does:** the collector releases the FIFO after its collection whatever
  the hung branch does, so the branch's own release matters only when nothing else releases the
  loader. M71 and M72 take the collector's release out too: with the branch's release the row
  fails by name in 3 s, without it the close waits for the watchdog, 32 s.
- **M65 is no plant:** the stand-in header on a library that has the entry point is the rule's
  failing case, the one row failing.
- **No row reaches the decoy's three:** native binds them and the load calls none, and the
  decoy's open always fails (the plan, §4.3). A decoy `sqlite3_db_config` that reads no
  argument, or a `sqlite3_load_extension` that writes no message, passes every suite. Defined
  with named arguments, M49, it fails the compile against `sqlite3.h`, every row of the suite.

## The earlier rounds' survivors

The first round ran on the tree before the review, in `build/mut/`: 77 plants and 8 for the int
cell. Two survived their first run, and the suites were fixed:

- **The optional row's records** (M27 here) passed `test-conventions` as first written: its row
  looked for "optional" in a record, which `bind-optional` holds too. It now looks for "an
  optional entry point".
- **The control without its status** (V15 here) passed `test-check-variadic`: no control row
  exited non-zero with no FAIL line and the runner's count. A suite does exactly that when its
  exit check fails, as `test-native`'s memory check did under the free plant. A row now has
  `test-native`'s control do so.

**Two survived the second round's first run,** V10 and V11, the arm64 step taking exit 0, and a
hang, after a FAIL line. Item 5 of the review below made the step need a failing test naming
`sqlite3_db_config`, and the two rows' failing test was named "a row", so the step refused them
whatever their status. Their failing test is now `sqlite3_db_config round-trips DEFENSIVE`, so
only the status can fail them, and V10 and V11 each fail one row; the table holds the rerun.

Four rows were added, or rewritten, before any plant ran, when reading a planned plant against
the suite showed no row it could fail; none of these was run against the earlier suite:
`test-check-variadic`'s arm64 rows of exit 0 after a FAIL line and of a hang after one, since its
other rows name no test and fail the named-or-dying test either way; its row of Chez printing a
machine type and exiting 3, since its other rows' answers were empty too; and `test-native`'s
file load, which first asserted one load's code and message, which a set that did not take
passes, "not authorized" being a failure with a message too. It now loads with the call set off,
then on, and asserts the two messages differ, which M15 fails.

## The review's fixes

The slice's read-only Opus review found no blocker; its seven items, each fixed:

1. **The script copied chez-curl's code.** Written again (above); six syntactic lines shared.
2. **Apple's SDK header could break `test-constants`.** The optional prototype in a compile of
   its own (above).
3. **Nothing in `make test` held the script's list to the tree.** Two rows of
   `test-check-variadic` (above); M73 to M75.
4. **A row's name said 2^32−1 where its value was 2^33−1.** The refusal row asserts 2^32−1, the
   top of what Chez's foreign `int` takes, and 2^32 beyond it, with 2^31, −2^31−1 and 2^63.
5. **The arm64 step passed on any named failure.** It now needs one naming `sqlite3_db_config`,
   or a death, and a row holds it.
6. **The FIFO row's hung branch could block to TEST_TIMEOUT.** Released before the close (above).
7. **`sqlite3_stmt_busy`, added, then taken out.** Asked for the maintainer's first choice for
   `close-database!`, "Refuse busy statements first", it was built: required and plain, its
   convention row, its prototype and near miss, a decoy switch and `missing-api` row dealt to
   `-real` at 43, and a `test-native` row, each held by plants. The close fix's measurement then
   found RTREE, and FTS5 at 3.45.1, keeping a busy read-only blob of their own inside an open
   write transaction, so refusing busy statements would bring back the can't-close defect. The
   maintainer chose "Vouch only for ours": the close finalizes what chez-sqlite3 tracks and
   judges no statement it didn't make, so nothing would use the binding. It is gone from every
   file, `every-entry` holds 43 again, the decoy's control 44, and no count says otherwise; the
   third round's plants run without its five.

## The coordinator's item: `call-with-int-cell`

Asked during the build, after slice 1's review: slice 3 needs a counted int cell, and only
`native.sls` may touch foreign memory (check-seam's rule (f)); `call-with-out-pointer`'s slot is
pointer-sized and zeroed, and 0 is what a set writes.

- **The shape:** `(call-with-int-cell WHO FILL PROC)` answers `(values (PROC cell) (the cell's
  int after PROC))`, as `call-with-out-pointer` answers its slot. The fill is the caller's alone:
  slice 3 passes slice 1's sentinel. The block comes from `call-with-block`, so it is counted,
  freed on return, raise and escape, and a re-entry raises from WHO. WHO, then FILL, then PROC are
  checked before anything is allocated.
- **The range is a C int's,** computed from `(foreign-sizeof 'int)`, −2^31 to 2^31−1 on every
  platform v1 runs on; Chez's foreign `int` also takes 2^31 to 2^32−1, and the plant that widened
  the check to that failed the refusal rows. An inexact `1.0` is refused.
- **Used** by `test-native`'s db_config rows, every call's cell a sentinel of the row's.
- **Rows:** each fill read back when PROC writes nothing, −1, 7, 255 and an int's two bounds, one
  block counted while PROC runs and none after; PROC's last write read after it; a raise and an
  escape freeing the cell; a re-entry refused; nine fills refused by `shown-value`, nothing
  allocated at the raise, PROC never run; PROC and WHO refused; and its refusals raised outside
  its critical thunks, at depth 1. Plants M56 to M62 each fail one or more.

## For the records

- **ADR-0002's and ADR-0005's M4 amendments,** and the plan's §4.6, stand as written:
  `every-entry` holds 43, the decoy's control 44 entry points, and `optional-entries`, joined to
  `every-entry`, would stand at 43 and go to `-real`. `sqlite3_stmt_busy` is not bound; the
  close's record is the maintainer's "Vouch only for ours".
- **ADR-0011's M4 amendment** might say how the FIFO row is built: the C call turned on through
  the binding first, the collector forked before the loader, and why, and the hung branch's
  release. The trap is `traps.md`'s, beside the FIFO's other entries.
- **ADR-0003's and ADR-0002's amendments, or the plan's §4.6:** an optional entry point's
  prototype is asked in a compile of its own, and a failed compile is unavailable only where
  native records the entry point absent.
- **The plan's §4.2 and ADR-0001's amendment:** `check-variadic`'s expected failing tests are
  written out in the script, ten of them, and `make test` holds them to `test-conventions`'
  tests; the arm64 step needs a failing test naming `sqlite3_db_config`. An AGENTS.md line might
  say that renaming one of those tests moves the script's list.
- **`check-variadic`'s cost on CI** is read from this slice's `main` job (the plan, §7). Here it
  took 10 s to 11 s in the container.
- **The three loading suites' times from more than one CI run** (ADR-0005's M4 amendment) are
  owed by the slice's CI runs; here, under the gate, decoys 160 s, real 153 s and missing 145 s.
- **The ops' names** are `constants.sls`'s, `sqlite-dbconfig-*`, for slices 1 and 3 to import;
  the int cell is `call-with-int-cell`.
- **`test-native` asserts no op's start,** only that each read answers 0 or 1: the starts differ
  by library, and slice 3's rows read them (the plan, §4.7).

## The Mac step

Owed by ADR-0001's consequence, whenever the variadic binding changes (the plan, §5 item 2): on
the maintainer's Mac, on `main` after this slice merges, `make test` and `make check-variadic`, with
Apple's library and with Homebrew's.

- With Apple's, by discovery: `test-native` prints UNAVAILABLE for `ENABLE_LOAD_EXTENSION`'s round
  trip, the file load and the FIFO load, and asserts `(#f #f)` in their place; DEFENSIVE, DQS_DML
  and DQS_DDL round-trip through the variadic binding. `test-constants` asks
  `sqlite3_load_extension`'s prototype in its own compile against the SDK's header: where that
  header marks it unavailable, the row prints UNAVAILABLE and asserts the failed compile and
  native's `#f`; where it declares it, the row is `declared`. Either is a measurement the Mac step
  should report.
- With Homebrew's, `CHEZ_SQLITE3_LIBRARY=/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib` and
  `C_INCLUDE_PATH=/opt/homebrew/opt/sqlite/include`: every load row runs. The FIFO load is the
  first measurement of `dlopen` on a FIFO on macOS: a load that never waits fails the row,
  `returned-before-the-collection`, which would be a finding, not a fault.
- `make check-variadic` must end "all 7 steps ok, on tarm64osx" (or `arm64osx`), its arm64 step
  naming `test-native`'s failures through `sqlite3_db_config` on the mutant, or its death.
