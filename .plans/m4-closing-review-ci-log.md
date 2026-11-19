# M4's closing review: the no-load CI lane (builder E1's log)

Evidence for the findings file's Proposal 2 and the maintainer's "In CI's current job" and "The
whole make test" (2026-11-18): job `current` builds the pinned release a second time with
`-DSQLITE_OMIT_LOAD_EXTENSION`, checks it, and runs the whole `make test` against it. Format of
[the M4 slice 5 log](m4-slice-5-mutation-log.md).

An Opus agent built it from the lead's brief, in its worktree, on `m4cr-ci` from `main` at
`34721b4`, beside builders C, D and E2 in worktrees of their own. Every run was in the Guix
container: Chez 10.4.0 (`ta6le`, threaded), gcc 16.2.0, x86_64. The drivers are in
[research/m4-closing-review/ci/](research/m4-closing-review/ci/).

## The FTS5 question: the no-load build keeps FTS5

Proposal 2 asks whether the no-load build keeps the `current` lane's `-DSQLITE_ENABLE_FTS5`, one
flag from it, or drops it, as reviewer B's measured build did. **It keeps it.** The build is
`current`'s flags and `-DSQLITE_OMIT_LOAD_EXTENSION`, 40 options: `current`'s 39 and
`OMIT_LOAD_EXTENSION` between `MUTEX_PTHREADS` and `SYSTEM_MALLOC`.

- **One variable.** The job's two `make test` runs then differ by one flag, so whatever differs
  between them comes from extension loading alone. B's build differed from `current`'s in two.
- **Apple's combination.** Apple's 3.51.0 lists both `ENABLE_FTS5` and `OMIT_LOAD_EXTENSION`
  ([census-mac-apple-3.51.0.txt](research/m4-prework/out/census-mac-apple-3.51.0.txt), lines 55
  and 89). It is the library users meet without `sqlite3_load_extension`, and the one CI can't run
  (ADR-0004). The Mac run after slice 5 found its fault there, FTS5 19 and the load rows
  unavailable, and this lane is CI's copy of that library's two choices.
- **Nothing is lost.** The `floor` lane already runs the no-FTS5 path on a real library (the M4
  plan's Q1). The one combination left out, neither FTS5 nor loading, is one nothing tells apart:
  `test-fts5` chooses its rows by the compile option, the loading suites by native's record of
  `sqlite3_load_extension`, and neither reads the other. `src/` uses no FTS5.
- **Proposal 2's own figures.** Its `check-sqlite.sh --no-load` is "current's 39 plus
  `OMIT_LOAD_EXTENSION` …, 40 in all", which is FTS5 kept. Only its measurement used a build
  without FTS5.
- **The cost is the same:** one compile of the same amalgamation.

B's 39-option build, `build/m4-noload`, stays in the stop condition's list, and `make test` passes
on it (below). `check-sqlite.sh --no-load` refuses it, naming `ENABLE_FTS5`.

## What changed

- **`scripts/ci/build-sqlite.sh PREFIX [--current | --no-load]`:** `--no-load` builds by the
  current release's version, year and pins, and names them `current_archive` and `current_source`
  when one fails; it compiles `current`'s line with `-DSQLITE_OMIT_LOAD_EXTENSION` besides, then
  runs `check-sqlite.sh PREFIX --no-load`. A third argument, both flags, or another flag is a usage
  error, as before.
- **`scripts/ci/check-sqlite.sh PREFIX [--current | --no-load]`:** `--no-load` checks the current
  release's version, number and source id, header and library, and `no_load_options`, the 40
  lines written out; it names itself "the pinned no-load SQLite".
- **`.github/workflows/ci.yml`, job `current`,** after its `make test`: the restore, id
  `sqlite-no-load`, path `${{ runner.temp }}/sqlite-no-load`, key `sqlite-no-load-` and the
  current lane's `hashFiles(` list, image and compiler; the build and the save under
  `if: steps.sqlite-no-load.outputs.cache-hit != 'true'`, the save keyed by that id's
  `cache-primary-key`; the check; and `make test`. The check and `make test` carry `CHEZ`,
  `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH` with this build's paths. The comments say so. No
  `make build` step: Proposal 2's five, and `make test` doesn't run `build`.
- **`tests/check-ci.sh`,** keyed by build, not by job: the tables `laneflag`, `lanehash`, `sqp`,
  `lanelib`, `laneinc`, `lanebld`, `lanechk`, `lanekey`, and new `sqid`, `ifsql` and `label`,
  each by the build's name; `floor` makes `floor`, and `current` makes `current`, then `no-load`.
  The rules:
  - **the run lines:** after the compiler step, each build's build, check, `make build` (the
    first build's alone) and `make test`, in order. A line required twice, `make test` in
    `current`, must be the run line of two steps, the kth requirement the kth step, and a wrong
    count says "not two";
  - **the env:** each required check, `make build` and `make test` carries `CHEZ` and both names,
    each with its own build's value, held at the job's end. `CHEZ` is still held at its line;
  - **each build's cache:** one restore and one save, by path; the restore's id (`sqlite`, or
    `sqlite-no-load`) and key; the save keyed by that id; each build's if only on the step that
    builds into its directory or on its own save; each restore after the compiler step, and a
    later build's after the earlier build's `make test`; and the save after its build and before
    its check, both told by the directory they name;
  - **the names a lane's problems list:** its own ifs and paths, three each in `current`;
  - **an out-of-order line** is named against the last line found in order, where it was named
    against the line required before it, which the line may follow.
  The header says each.
- **`tests/test-check-ci.sps`:** 440 rows to 496. 56 new: 46 for the no-load build, and 5 of each
  lane's own cache (its restore deleted or written twice, its save deleted, its restore's id
  dropped or another). 25 rows moved:
  - twelve reach a new rule: each lane's "the build into another directory" (its if guards no
    build of a cache), and in each lane the five that leave it without its one restore or save,
    or with two, three of `current`'s also listing its three paths;
  - eight name `current`'s new shape alone: "not two", and its three ifs;
  - five are anchored by text the new steps changed: "the current job deleted" runs to the
    file's end; "a seventh job" goes after the file's last step; "no jobs key" refuses the no-load
    steps' four lines too; and the two execute-bit rows name the two new script steps;
  - `del-step` deletes the file's last step, now the no-load `make test`, by the blank line before
    it.
- **`tests/test-ci-sqlite.sps`:** 81 rows to 99. The 40-line copy, written by hand, and a row that
  it is the current copy and `OMIT_LOAD_EXTENSION`, that one line apart; the count row, 37, 39 and
  40. For `check-sqlite.sh --no-load`: passes, with and without a floors file; the `current`
  lane's 39 refused, naming `OMIT_LOAD_EXTENSION`; a no-load build without FTS5 refused, naming
  `ENABLE_FTS5`; the floor's library and header refused at the header; a source id one character
  off refused at the library; and `--current` refusing the 40. For `build-sqlite.sh --no-load`:
  the pinned release reached, with no floors file and with one; both digest refusals naming
  `current_*`; the compile line; and the success row, built and checked with `--no-load`, exit 0.
  Both scripts' usage line names `--no-load`, and both flags, or `--noload`, are a usage error.
- **`packaging/floors.sexp`:** unchanged. No floor moves, and `check-floors` passes: the no-load
  build writes no floor.

## Red, then green

- **`test-ci-sqlite`,** the new rows against the scripts as they stood: 24 of 99 failed, 75
  passed. The changed scripts: 99 of 99. The rows that passed against the old scripts (the
  `--current` refusal of the 40, and the two rows on the suite's own copies) were watched failing
  by plants S02, S14 and S15, below.
- **`check-ci` on the new workflow,** before `check-ci.sh` changed: 12 problems, among them "job
  current has 2 steps that run "make test", not one" and the no-load env read as `current`'s.
  After: it passes. The old workflow, minus `floor`'s SQLite restore, now fails with 6.
- **`test-check-ci`,** the new check and workflow with the suite as it stood: 25 of 440 failed,
  each read and found to be a rule above. The suite after: 496 of 496.
- **Every new or changed row was watched failing.** A run of each suite printed every row's name;
  the names `main` at `34721b4` lacks are the new rows. Each new or changed row is among the
  failures of a plant that leaves the unedited workflow passing: 81 of 81 in `test-check-ci`, and
  in `test-ci-sqlite` 19 of 19, from the red run or a plant.

## A gap the rules close: a lane without its SQLite restore passed

At `34721b4`, `check-ci` passed the workflow with `floor`'s step "Restore SQLite at its floor"
deleted, and with `floor`'s "Restore Chez" deleted. On a runner the first leaves the build's
`steps.sqlite.outputs.cache-hit` empty, so it always builds, and the save's key empty, which fails
the save. The rule "each build's cache has one restore and one save" now refuses the SQLite case,
in both lanes and the no-load build. **The Chez caches' restores and saves are still not counted,
in any job:** out of this brief, for the records.

## The plants

Each plant is one rule taken out, or turned, in a copy of the worktree under `build/e1/plants/`,
made by [plants.py](research/m4-closing-review/ci/plants.py), each edit checked to match its file
exactly once, and its suite run there by Chez directly, six at once, by
[run-plants.sh](research/m4-closing-review/ci/run-plants.sh). A plant of `check-ci.sh` runs
`test-check-ci` (496 rows), and one of the scripts or their suite `test-ci-sqlite` (99). The rows
are read by [summarize.py](research/m4-closing-review/ci/summarize.py) from the FAIL lines and
counts; its whole output is [plants-summary.txt](research/m4-closing-review/ci/plants-summary.txt).
Every plant failed its suite. Two, C02 and C04, fail the unedited workflow too, so they point at
no row: C02 leaves the no-load check's env on a step the lane doesn't require, and C04 reads the
first `make test` twice, against both builds' values. C29 to C35 were added for the eight rows the
first 28 left unwatched: three old rules the no-load steps now reach, and the five rows anchored
anew. A ninth looked unwatched only because its name ends in a space, which the cross-check had
stripped; C13 fails it.

| Plant | Guards | Passed, failed | Failed rows |
|---|---|---|---|
| C01 | the no-load build's run line is required (only the first build's) | 486, 10 | "no-load: the build deleted"; "no-load: the build written twice"; "no-load: the build with --current"; and 7 more |
| C02 | the no-load check's run line is required (only the first build's) | 8, 488 | every row with the unedited file: the base fails |
| C03 | a line required n times is run by n steps (n or more) | 481, 15 | "main's install check written twice"; "floor: the step that runs scripts/ci/check-chez.sh "$RUNNER_TEMP/chez-threads" written twice"; "floor: the step that runs echo "id=$(cc --version \| head -n 1 \| tr -c '[:alnum:].' '-')" >> "$GITHUB_OUTPUT" written twice"; and 12 more |
| C04 | the kth time a line is required is its kth step (always the first) | 15, 481 | every row with the unedited file: the base fails |
| C05 | each build's env values are held (the second build's not) | 492, 4 | "no-load: the check's header directory is the current build's"; "no-load: the make test with the current build's library"; "no-load: the two make tests' env blocks swapped"; "no-load: the five steps before the current build's make test" |
| C06 | each build's env values are held (none) | 485, 11 | "floor: the check's library is the other lane's"; "floor: the suites' header directory has a second directory"; "floor: the library's value is relative"; and 8 more |
| C07 | the second build's steps must carry the two names (not held) | 495, 1 | "no-load: the make test without its env" |
| C08 | the second build's steps must carry CHEZ (not held) | 493, 3 | "no-load: the build without CHEZ"; "no-load: the check without CHEZ"; "no-load: the make test without its env" |
| C09 | a build's if stands on the step that names its directory (on any build-sqlite.sh step, as before) | 490, 6 | "floor: the build into another directory"; "current: the build into another directory"; "no-load: the build into the current build's directory"; and 3 more |
| C10 | a build's if stands on its own save (on any save) | 491, 5 | "floor: the SQLite if on the Chez save"; "floor: the SQLite save's path is the other lane's"; "current: the SQLite if on the Chez save"; and 2 more |
| C11 | the second build's step has its if (not held) | 495, 1 | "no-load: the build without its if" |
| C12 | a SQLite restore's id is held (not held) | 488, 8 | "floor: the SQLite restore without its id"; "floor: the SQLite restore's id is another"; "floor: the Chez cache's path is the SQLite cache's"; and 5 more |
| C13 | the second build's restore key is held (not held) | 488, 8 | "no-load: the restore's key drops 'scripts/ci/build-sqlite.sh',"; "no-load: the restore's key drops , 'scripts/ci/check-sqlite.sh'"; "no-load: the restore's key drops -${{ steps.image.outputs.id }}"; and 5 more |
| C14 | a save is keyed by its own restore's id (or by sqlite's) | 493, 3 | "floor: the Chez save is keyed by the SQLite cache"; "current: the Chez save is keyed by the SQLite cache"; "no-load: the save keyed by the current build's restore" |
| C15 | each build's cache has one restore (not counted) | 479, 17 | "floor: the SQLite restore's path is the other lane's"; "floor: the SQLite restore deleted"; "floor: the SQLite restore written twice"; and 14 more |
| C16 | each build's cache has one save (not counted) | 488, 8 | "floor: the SQLite save's path is the other lane's"; "floor: the SQLite save deleted"; "current: the SQLite save's path is the other lane's"; and 5 more |
| C17 | the second build's cache is held in order (skipped) | 491, 5 | "no-load: the save before its build"; "no-load: the save after its check"; "no-load: the restore before the current build's make test"; and 2 more |
| C18 | a later build's restore comes after the build before it's make test (not held) | 493, 3 | "no-load: the restore before the current build's make test"; "no-load: the restore before the compiler step"; "no-load: the five steps before the current build's make test" |
| C19 | each build's restore comes after the compiler step (the first build's only) | 495, 1 | "no-load: the restore before the compiler step" |
| C20 | the two names stand only on the steps of a build's check, make build and make test (on any step after the first make test) | 493, 3 | "no-load: the build's env gains C_INCLUDE_PATH"; "no-load: the restore's env names the library"; "no-load: the check with --current" |
| C21 | a lane's cache paths are its own builds' (any build's) | 495, 1 | "no-load: the five steps in job floor" |
| C22 | a lane's ifs are its own builds' (any build's) | 495, 1 | "no-load: the five steps in job floor" |
| C23 | an out-of-order line is named against the last line in order (the line required before it) | 495, 1 | "no-load: the five steps before the current build's make test" |
| C24 | a line required twice says not two (not one) | 489, 7 | "current: the step that runs make test deleted"; "current: the step that runs make test written twice"; "current: make test X"; and 4 more |
| C25 | current's problems list its three ifs and three paths (with or between each) | 486, 10 | "current: an if with another value on the SQLite build"; "current: an if: always() on the SQLite check"; "current: an if: always() on make build"; and 7 more |
| C26 | a no-load cache is a SQLite cache (the old path pattern) | 491, 5 | "no-load: the save before its build"; "no-load: the save after its check"; "no-load: the restore before the current build's make test"; and 2 more |
| C27 | a step names a build's directory only when nothing but a space follows it (anything may) | 495, 1 | "no-load: the build into a directory below its cache's, sqlite-no-load/x" |
| C28 | CHEZ is held at its line (not held) | 490, 6 | "the CHEZ path of main swapped to nothreads's"; "the CHEZ path of nothreads swapped to main's"; "memory-1: the shard's CHEZ is the nothreads Chez"; and 3 more |
| C29 | the Chez cache's if stands only on the Chez build and save, in a lane (anywhere) | 489, 7 | "floor: the Chez if on the SQLite build"; "floor: the Chez if on the SQLite save"; "floor: the Chez if on make test"; and 4 more |
| C30 | the second build's save is keyed exactly (not held) | 494, 2 | "no-load: the save keyed by the current build's restore"; "no-load: the save keyed as its restore is" |
| C31 | the second build's check is counted (its count not told) | 492, 4 | "no-load: the check deleted"; "no-load: the check with --current"; "no-load: the five steps in job floor"; "no-load: the five steps in job main" |
| C32 | every job is there (current not held) | 495, 1 | "the current job deleted" |
| C33 | no job but the six (any job) | 493, 3 | "a job added"; "a third shard, in a job of its own, memory-3"; "a seventh job" |
| C34 | every step that runs a script by its path is read for its execute bit (the first 560 lines only) | 494, 2 | "build-sqlite.sh without its execute bit: every step that runs it is named"; "check-sqlite.sh without its execute bit: every step that runs it is named" |
| C35 | C_INCLUDE_PATH is a name no line may hold (it may) | 484, 12 | "a block scalar names C_INCLUDE_PATH"; "no jobs key"; "main's install check gains C_INCLUDE_PATH, with floor's exact value"; and 9 more |
| S01 | check --no-load holds the no-load list (current's) | 94, 5 | "check-sqlite.sh: --no-load: the pinned release built without extension loading passes, with its 40 lines, in a tree with no floors file"; "check-sqlite.sh: --no-load: it passes whatever floor the tree has: the floors file is not read"; "check-sqlite.sh: --no-load: the current lane's build, its 39 options, is refused, naming OMIT_LOAD_EXTENSION"; and 2 more |
| S02 | check --current holds current's list (the no-load one) | 93, 6 | "check-sqlite.sh: --current: the pinned release's library passes, with its 39 lines, in a tree with no floors file"; "check-sqlite.sh: --current: it passes whatever floor the tree has: the floors file is not read"; "check-sqlite.sh: --current: the pinned release's identity with the floor's 37 options is refused"; and 3 more |
| S03 | check --no-load names its own role (current's) | 92, 7 | "check-sqlite.sh: --no-load: the pinned release built without extension loading passes, with its 40 lines, in a tree with no floors file"; "check-sqlite.sh: --no-load: it passes whatever floor the tree has: the floors file is not read"; "check-sqlite.sh: --no-load: the current lane's build, its 39 options, is refused, naming OMIT_LOAD_EXTENSION"; and 4 more |
| S04 | check --no-load holds the current release's identity (the floor's source id) | 92, 7 | "check-sqlite.sh: --no-load: the pinned release built without extension loading passes, with its 40 lines, in a tree with no floors file"; "check-sqlite.sh: --no-load: it passes whatever floor the tree has: the floors file is not read"; "check-sqlite.sh: --no-load: the current lane's build, its 39 options, is refused, naming OMIT_LOAD_EXTENSION"; and 4 more |
| S05 | check --no-load's list holds OMIT_LOAD_EXTENSION (dropped) | 94, 5 | "check-sqlite.sh: --no-load: the pinned release built without extension loading passes, with its 40 lines, in a tree with no floors file"; "check-sqlite.sh: --no-load: it passes whatever floor the tree has: the floors file is not read"; "check-sqlite.sh: --no-load: the current lane's build, its 39 options, is refused, naming OMIT_LOAD_EXTENSION"; and 2 more |
| S06 | check takes --no-load alone (--noload too) | 98, 1 | "check-sqlite.sh: --noload, a misspelling, is a usage error" |
| S07 | build --no-load compiles without extension loading (the flag dropped) | 97, 2 | "build-sqlite.sh: --no-load, both digests right, in a tree with no floors file: the pinned release compiled with FTS5 and without extension loading, then checked"; "build-sqlite.sh: --no-load, both digests right and a library that is the no-load build's: built, checked with --no-load, and the last line printed, exit 0" |
| S08 | build --no-load keeps FTS5 (dropped) | 97, 2 | "build-sqlite.sh: --no-load, both digests right, in a tree with no floors file: the pinned release compiled with FTS5 and without extension loading, then checked"; "build-sqlite.sh: --no-load, both digests right and a library that is the no-load build's: built, checked with --no-load, and the last line printed, exit 0" |
| S09 | build --no-load checks with --no-load (--current) | 98, 1 | "build-sqlite.sh: --no-load, both digests right and a library that is the no-load build's: built, checked with --no-load, and the last line printed, exit 0" |
| S10 | build --no-load names the current release's pins (by its role, no-load_archive) | 97, 2 | "build-sqlite.sh: --no-load: the current archive with the floor's digest is refused, naming current_archive"; "build-sqlite.sh: --no-load: the current archive's pin with the floor's sqlite3.c digest is refused, naming current_source, before the compiler runs" |
| S11 | build --no-load builds the current release (the floor, by floors.sexp) | 93, 6 | "build-sqlite.sh: --no-load reaches the pinned current release, 3540100 from 2026, with no floors file: its pins are the current release's"; "build-sqlite.sh: --no-load reaches the pinned current release with a floor of 8.1.2"; "build-sqlite.sh: --no-load: the current archive with the floor's digest is refused, naming current_archive"; and 3 more |
| S12 | build --no-load's download failure names the current release's pins (the floor's) | 97, 2 | "build-sqlite.sh: --no-load reaches the pinned current release, 3540100 from 2026, with no floors file: its pins are the current release's"; "build-sqlite.sh: --no-load reaches the pinned current release with a floor of 8.1.2" |
| S13 | build takes --no-load alone (--noload too) | 98, 1 | "build-sqlite.sh: --noload, a misspelling, is a usage error" |
| S14 | the suite's no-load copy holds OMIT_LOAD_EXTENSION (dropped from the copy) | 92, 7 | "the copies hold 37, 39 and 40 lines, the COMPILER= entry among them when SQLite lists one"; "the no-load copy is the current copy with OMIT_LOAD_EXTENSION, and the only difference"; "check-sqlite.sh: --no-load: the pinned release built without extension loading passes, with its 40 lines, in a tree with no floors file"; and 4 more |
| S15 | the suite's no-load copy is current's and one line (a second extra line) | 97, 2 | "the copies hold 37, 39 and 40 lines, the COMPILER= entry among them when SQLite lists one"; "the no-load copy is the current copy with OMIT_LOAD_EXTENSION, and the only difference" |

## Run as CI would

**The build.** The container has no network, `tar` or `openssl`, so
[replay-build.sh](research/m4-closing-review/ci/replay-build.sh) ran `build-sqlite.sh --no-load`
through M4 slice 5's three shims ([research/m4-slice-5/replay/](research/m4-slice-5/replay/)):
`curl` copies `build/m4-dl`'s archive, `openssl` answers the host's digests only for a file byte
for byte the one they were computed of, and `tar` copies the host's extraction. On the host first,
the host's `openssl` 3.0.2 read `b6ced585…57d9c4` of the archive and `e2b869d3…b558ee81` of its
`sqlite3.c`, `current_archive` and `current_source`, and a fresh extraction by the host's `tar`
was byte for byte `build/m4-dl`'s, all three members. The compile and the check were the real
ones, with the container's gcc. It built, passed its own `check-sqlite.sh --no-load` with 40
options, the lines as `test-ci-sqlite` writes them, and printed its last line, exit 0, in 26 s
([replay-build.txt](research/m4-closing-review/ci/replay-build.txt)). `nm -D` finds no
`load_extension` symbol in it, where `build/m4-current-fts5` exports `sqlite3_load_extension` and
`sqlite3_enable_load_extension`.

**The check, as CI's step runs it**
([replay-checks.txt](research/m4-closing-review/ci/replay-checks.txt)), each with
`CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH` naming the build:

| Build | Flag | Exit | What it names |
|---|---|---|---|
| `build/e1/sqlite-no-load`, the replay | `--no-load` | 0 | 3.54.1, its source id, 40 options |
| `build/m4-current`, plain 3.54.1 | `--no-load` | 1 | `-ENABLE_FTS5` and `-OMIT_LOAD_EXTENSION`, two hunks |
| `build/m4-current-fts5`, the `current` lane's | `--no-load` | 1 | `-OMIT_LOAD_EXTENSION` |
| `build/m4-noload`, B's, without FTS5 | `--no-load` | 1 | `-ENABLE_FTS5` |
| `build/e1/sqlite-no-load`, the replay | `--current` | 1 | `+OMIT_LOAD_EXTENSION` |

**The whole `make test`, on six libraries,** one after another in this worktree, each after `make
build`, whose lines name the library loaded, by
[run-lanes.sh](research/m4-closing-review/ci/run-lanes.sh)
([lanes.txt](research/m4-closing-review/ci/lanes.txt)). Each ran `check-floors` and `check-ci`
first, and both passed:

| Library | Version | `make test` | Time |
|---|---|---|---|
| the replay, FTS5 and no loading | 3.54.1 | 81 of 81 | 151 s |
| Guix's | 3.53.1 | 81 of 81 | 147 s |
| `m3-floor` | 3.45.1 | 81 of 81 | 142 s |
| `m4-current`, plain | 3.54.1 | 81 of 81 | 156 s |
| `m4-noload`, B's, without FTS5 | 3.54.1 | 81 of 81 | 161 s |
| `m4-current-fts5`, the `current` lane's | 3.54.1 | 81 of 81 | 136 s |

On the replay, 51 UNAVAILABLE lines in 6 suites, as reviewer B counted on that build:
`test-load-extension` 27, `test-load-extension-engines` 12, `test-open-db-config` 7, `test-native`
3, `test-open-db-config-engines` 1 and `test-open-settings` 1. `test-fts5` ran its 19 FTS5 rows
there, and its 5 rows of the refusal on `m4-noload`. On Guix's and the FTS5 build, no UNAVAILABLE
line.

**Under the gate,** on Guix's library, `make test-memory` with the two touched suites:
`test-check-ci` 134 s and `test-ci-sqlite` 34 s, each within 450 s. At `main`'s `34721b4`, the same
run took 108 s and 38 s: the 56 rows cost `test-check-ci` 26 s here. Both are in `MEMORY_SUITES_1`.

**CI's cost,** from these runs: the `current` job gains a restore of about 2 s on a hit, and on a
miss a download and the 26 s build; then one more `make test`, about 2.5 minutes here, inside the
job's 60 minutes and below the memory jobs' wall time.

## What the records need (the lead's)

- **`global-constraints.md`, under "Memory and the test harness":** "`CHEZ_SQLITE3_LIBRARY` and
  `C_INCLUDE_PATH` stand only in `floor` and `current`, as exact env keys of the three steps that
  name the lane's build" is now the steps that name a SQLite build: `floor`'s three, and
  `current`'s five, its own build's check, `make build` and `make test`, and the no-load build's
  check and `make test`, each with its own build's value. Add that each lane's SQLite cache has one
  restore, its id held, and one save, and that `current` runs `make test` twice, for its two
  builds in turn.
- **`global-constraints.md`, under "`db_config` and extensions":** after "The `current` lane
  compiles with `ENABLE_FTS5`, the `floor` lane with SQLite's defaults", add that job `current`
  then builds the pinned release a second time, `build-sqlite.sh --no-load`, the `current` lane's
  flags and `-DSQLITE_OMIT_LOAD_EXTENSION`, FTS5 kept, checks it with `check-sqlite.sh --no-load`,
  40 options, and runs the whole `make test` against it (M4's closing review).
- **ADR-0005,** an amendment to its "`floor` and `current` lanes" one: the second build in job
  `current`, the shape `check-ci` holds by build, and the rules above.
- **ADR-0003,** an amendment after "FTS5 on the current lane": the no-load build, and why it keeps
  FTS5 (the first section above).
- **ADR-0002 or ADR-0021, consequences:** CI now runs a library without
  `sqlite3_load_extension` on every run, so the suites' unavailable branches no longer wait for
  the Mac.
- **`progress.md`, Open:** "no CI lane has a library without `sqlite3_load_extension`" closes
  once CI runs this; the findings' m2, the opt-in's availability refusal held in-process only by a
  decoy row, gains this lane's cover.
- **For the records, out of this brief:** no job's Chez cache is counted. At `34721b4`, and still,
  `check-ci` passes a job whose "Restore Chez" is deleted (`floor`'s, measured); its build then
  always runs, and its save's key is empty. A rule like the SQLite one, a restore and a save in
  each job, would close it.

## Traps

None new to the project's code. One for the record of `check-ci`:

- **An out-of-order line was named against the wrong line.** `check-ci` said "runs X before Y"
  with Y the line required just before X, whatever came first. With the no-load build's steps
  moved before `current`'s `make test`, the no-load check was named as running before the no-load
  build, which it follows. It now names the last line found in order. Plant C23 holds it.
