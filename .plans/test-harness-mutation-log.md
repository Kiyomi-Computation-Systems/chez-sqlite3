# Test harness mutation log (M0 slice 2)

Evidence that the checks M0 slice 2 added fail through the property each one claims to guard
([harness plan](2026-11-13-harness-plan.md) §6, [ADR-0005](decisions/0005-memory-gate.md),
[ADR-0007](decisions/0007-test-harness-and-scheme-dependencies.md),
[ADR-0008](decisions/0008-floors-have-one-source.md)).

Every mutation was applied to a fresh copy of the working tree, made in the session scratchpad,
without `.git` except where a case needs git. The working tree was never edited. The suites and
checks are adapted from chez-curl's, and its logs are the model.

Three Sonnet agents built the floors, `test-manifest`, and the suites for the verdict and the
counters, in parallel, each on its own files. Their tables are summarised below. Four of the floors
agent's results were reproduced here, one of `test-manifest`'s and three of the suites agent's,
through `scripts/guix-env` from the copy's own launcher; every reproduction matched. The slice's
review reproduced thirteen more, all matching. The rest of the slice, and the mutations in the last
section, were built and run here.

## How the red runs were made

- **The core went in before its suites.** The Makefile targets, `(chez-sqlite3-testing)`, the
  counters and `require-threaded` were copied from chez-curl first, smoke-tested, and committed
  (`8e85539`). Their suites came after them. So each suite's red run is against a stubbed copy of
  the code, or the mutations themselves, not against code that didn't exist yet.
- **`test-manifest` was written whole before it ran,** as its agent reported. Its red runs are its
  mutations.
- **The floors were written test-first.** `(floors)` was missing at first, and the suites died at
  import. Then the files were missing: `test-check-floors` gave 145 passed, 15 failed, and
  `test-require-threaded` gave 25 passed, 15 failed. Then README.org was empty.
- **The host-side M2 and T10 cases came after the Makefile code they test,** and are watched
  failing through mutations G1 and TO1 to TO3.

## `tests/test-chez-sqlite3-testing.sps` and `tests/test-counters.sps`

**Red runs:**

- Against a stubbed `(chez-sqlite3-testing)`, whose exit form was `'()`, whose verdict was always
  0, and whose `describe` returned `""`: the verdict suite gave 2 passed, 16 failed.
- Against stubbed counters: the counters suite gave 1 passed, 12 failed.

**Baseline:** 18 passed and 14 passed, both exit 0.

| Mutation | Guards | Result |
|---|---|---|
| M1 | a suite needs a pass | 2 fail: "no pass", "no test" |
| M2 | no unexpected pass | 1 fail |
| M3 | no failure | 3 fail |
| M4 | the native counts | 6 fail |
| M5 | the verdict is 0 or 1, never a count | 9 fail, the 256-failure row among them. **Reproduced here.** |
| M6 | a non-runner is refused | 1 fail |
| M7 | the order of the counts line | 2 fail |
| M8 | any nonzero count fails | 6 fail |
| M9, M10 | `describe` on conditions, and its guard | 1 fail each |
| M11, M13 | the runner line, and the counts line, are printed | 6 fail each |
| M12 | the exit form | 1 fail |
| C1, C2 | a count can't go below zero, and that raises | 8 fail; 4 fail |
| C3 | an unknown kind raises | 1 fail |
| C4, C5 | `native-counts` and `native-kinds` order | 11 and 12 fail |
| C6 | the mutex | the 8-thread test fails, 5 runs of 5. **Reproduced here.** It is caught by a race, so in principle a run could miss it. |
| C7, C8, C10 | `count-up!` adds one, validates, and `count-down!` hits its own slot | 10, 9 and 11 fail |
| C9 | `count-down!` validates its kind | **survived at first.** With every count at 0, the kind fell to slot 0, which still raised. A test that holds each count at 1 now fails 7 tests. **Reproduced here.** |

## `tests/test-manifest.sps`

**Baseline:** 74 passed, exit 0. 25 mutations, every one failing it:

- **Akku.manifest:** a `depends` or `scripts` clause; a changed or second dev dependency; the
  name; the license; a second package.
- **Akku.lock:** its version; no or a short sha256; a second project.
- **CHANGELOG.md:** a bad date in two forms; releases out of order; no `[Unreleased]`, or one below
  a release; another title; `[YANKED]`; a `###` release heading; the same version twice; a
  release with the manifest left at 0.0.0.
- **The version:** set to 0.1.0 with no release. **Reproduced here.**

A control, a release of 0.1.0 with the manifest at 0.1.0, passed as it should.

## `tests/test-check-floors.sps` and `tests/test-require-threaded.sps`

**Baseline:** 161 passed and 40 passed, both exit 0. `check-floors` on the real files prints
`README.org holds the floors in packaging/floors.sexp (chez 10.4.0, sqlite 3.45.1)`.

**A bug found on the way, in chez-curl's `file-text`.** `get-string-all` returns the eof object for
an empty file, so an empty README.org crashed the program instead of being reported. Confirmed
here on Chez 10.4.0. `(floors)` returns `""` instead, and a fixture covers it. chez-curl has the
same code, harmless there because its README is never empty.

The agent's report lists 50 mutations, all but one failing a test. Its summary line said "28 of
29" for its first table, which lists 31; the rows are what's recorded here.

- **The floors file:**
  - key order, a missing key, a leading zero (**reproduced here**), and two datums;
  - a floor raised, which also fails `test-require-threaded` for the Chez floor.
- **README.org:**
  - a changed Requirements line (**reproduced here**): `list line 2 under "** Requirements" is "- SQLite 3.45.0 or later", but packaging/floors.sexp gives "- SQLite 3.45.1 or later"`;
  - a missing, extra or swapped line;
  - the section renamed;
  - the file emptied.
- **`require-threaded.sls`:**
  - the minimum lowered or raised;
  - the threaded check removed or inverted;
  - the pre-release handling broken four ways, `pre` always `#f` among them (**reproduced here**,
    7 fail);
  - `older?` flipped;
  - the message, the `who`, the exports.
- **`counters.sls`'s imports:** `require-threaded` second (**reproduced here**, 1 fail), or gone.
- **`(floors)` and `check-floors.sps`:** every rule removed in turn, the empty-file fix reverted,
  and the program's exit status and argument check.
- **Mutations of `require-threaded.sls` that would refuse this Chez itself:** they make the
  suites die at import, unnamed. That still fails `make test` and `check-suites`. It can't be
  helped on a 10.4.0 Chez.

**The survivor:** dropping `(file-symbolic-link? path)` from `lock-file?`. It is an equivalent
mutant: a directory entry that isn't a link and doesn't exist can't be listed. It is kept as
chez-curl has it.

## This slice's own checks

The checks below are this slice's own. Each mutation ran under `check-test-fails`, `check-clean`,
the host-side tests, `check-pins` or the self-test, as its row says. The mutation driver kept the
lines that name each failure.

**Baselines, on the whole tree:**

- `make test` ran 5, passed 5.
- `check-test-fails` passed in all 10 cases, in 15 s with `check-clean`.
- `check-clean` passed.
- `tests/guix-env-launcher.sh` gave 70 passed, 0 failed.
- `make check-guix` printed `ALL CHECKS PASSED`, its self-test now running `make test`.
- `make check-pins` on the host passed.

| Mutation | Guards | Change | Run under | Result |
|---|---|---|---|---|
| CS1 | a suite's last datum is the shared form | the last-datum rule always holds | `check-test-fails` | exit-line: `make test exited 0` |
| CS2 | an exit nested in a form is found | `early-exits` visits no element | `check-test-fails` | nested-exit: `make test exited 0` |
| CS3 | only `(exit 1)` may come early | no exit counts as early | `check-test-fails` | early-exit and nested-exit: `make test exited 0` |
| CS4 | an empty suite is named | an empty file passes | `check-test-fails` | empty: `make test's lines differ` |
| MT1 | every suite runs after a failure | `break` after the first failure | `check-test-fails` | fails, no-tests and leaks: the after-suite's pass line missing |
| MT2 | each suite runs under `timeout` | `timeout` dropped | `check-test-fails` | hangs: `make test did not finish within 70s` |
| MT3 | a hang is named HUNG | exit 124 classed as FAIL | `check-test-fails` | hangs: `make test's lines differ` |
| MT4 | a failure or hang fails `make test` | the final test replaced by `true` | `check-test-fails` | fails, no-tests, hangs and leaks: `make test exited 0` |
| MT5 | no suites is an error | the empty-glob refusal skipped | `check-test-fails` | no-suites: `make test exited 0` |
| MT6 | `check-suites` runs first | dropped from `test`'s prerequisites | `check-test-fails` | every case's lines differ, and the four check-suites cases exit 0 |
| MT7 | `check-floors` runs first | dropped from `test`'s prerequisites | `check-test-fails` | floors: `make test exited 0` |
| V1 | the verdict reads the counts, end to end | `left` always empty | `check-test-fails` | leaks: `make test exited 0` |
| CL1 | `clean` removes `build/` | the recipe is `true` | `check-clean` | `make clean left build/ in place` |
| CL2 | `clean` follows no link | it removes `build/to-outside-dir/*` first | `check-clean` | `make clean followed a link out of build/` |
| CL3 | `clean` removes nothing else | it removes `tests/fixtures` too | `check-clean` | `make clean changed the tree outside build/` |
| CL4 | `clean` passes with no `build/` | `rm -r`, without `-f` | `check-clean` | `make clean failed with no build/` |
| D1 | `deps` links the decoded names | no decoded link | `check-clean` | `make deps linked no build/scheme-libs/srfi/:64.sls in the copy` |
| G1 | `GOAL` names what the user typed | `GOAL = $@` | host-side | 69/1: `M2 … the prerequisite's hint names test`. Slice 1's log listed this as not covered. |
| TO1 | `timeout` before `gtimeout` | the order swapped | host-side | 69/1: `T10a` |
| TO2 | `gtimeout` as the fallback | dropped | host-side | 69/1: `T10b` |
| TO3 | the bare name as the last resort | dropped | host-side | 69/1: `T10c` |
| P1 | the lock and the pin agree | `Akku.lock` names `7879b53` | `check-pins`, a copy with `.git` | exit 2: `PIN DRIFT: Akku.lock names 7879b53, but the superproject records 7879b527…`, and the checkout too |
| P2 | the checkout and the pin agree | the submodule checked out at `HEAD~1` | `check-pins` | exit 2: `… vendor/chez-srfi is checked out at f09bad78…` |
| P3 | the gitlink and the pin agree | the gitlink set to `000…001` | `check-pins` | exit 2: `… the superproject records 000…001 …` |
| P4 | a lock prefix shorter than seven digits is not read | `akku.181.7879b5` | `check-pins` | exit 2: `could not read a chez-srfi commit from Akku.lock` |
| P5 | the submodule is checked out | an empty directory in its place | `check-pins` | exit 2: `vendor/chez-srfi is not checked out. …` |
| SF1 | the self-test runs `make test` | a failing suite added | `check-guix-inside` | exit 2: `FAILED test` |

## Not covered

- **`deps`' refusal of an empty submodule.** No case runs `make deps` on one; P5 shows only
  `check-pins` naming it.
- **`check-pins` has no suite.** Its five cases above are state mutations run by the driver, as
  chez-curl's were. It needs git, so it can't run under `make test`.
- **The mutex** (C6) is caught by a race, five runs of five. In principle a run could miss it.
- **The leaks plant raises a count itself.** A library that leaks a real statement comes in M1,
  with the first native object.
- **`--foreground`,** which keeps Ctrl-C reaching a suite, isn't checked.
- **`test-manifest`:** the lock's URL is checked for its version alone, and its sha256 for its
  shape alone. An extra clause in the manifest passes.
- **The floors:**
  - the SQLite floor isn't enforced by code yet, so ADR-0008's rows (3.45.1 accepted, 3.45.0
    refused) come with the floor check in M1;
  - the workflow rules come with CI, in slice 4;
  - a mutation of `require-threaded.sls` that refuses this Chez makes the suites die unnamed.

## After the slice's review

The read-only Opus review found no blocker, two major findings, and seven numbered minor ones;
its summary said nine. It reproduced thirteen of the results above, and all matched. Its main
findings were reproduced here before anything was fixed.

- **Major: the import-order scan read only `.sls` files.** Chez's `(library-extensions)` here is
  `.chezscheme.sls .ss .sls .scm .sch`, and it loads a `.ss` ahead of the `.sls` beside it.
  Reproduced: a `counters.ss` beside `counters.sls`, without the refusal import, was the file
  Chez loaded (`import: found source file "src/chez-sqlite3/private/counters.ss"`), and `make
  test` ran 5, passed 5.
- **Major: the suites wrote stand-ins instead of taking the shared helpers,** at fixed paths
  under `build/`, against the slice's own rule that a helper comes with its first consumer.
  Reproduced: of six `make test` runs, two at a time in one copy, three failed, each on a scratch
  path the other was using.
- **Minor, reproduced:**
  - `TEST_TIMEOUT=0`, which GNU `timeout` reads as no limit, passed;
  - the non-threaded refusal's message cut to its first words passed every suite.

A Sonnet agent fixed the test files:
- the helpers `capture-command`, the temporary directories and `run-until` joined
  `(chez-sqlite3-testing)`, with chez-curl's tests for them, and the three suites use them;
- a rule that `src/` holds no library file Chez could load but a plain `.sls`;
- whole messages compared;
- the dropped `.#`-link row restored;
- a distinct no-raise sentinel in `test-manifest`;
- tripwires: `check-floors` refuses while `.github/workflows` exists, and `test-manifest` refuses
  a `git clone` line, until slice 4 and the first release write their rules.

Some of its new rows were written after the code they test, and were watched failing through
mutations only.

**Baselines after the fixes:**
- `make test` ran 5, passed 5, at 164, 60, 14, 79 and 50 passes;
- six concurrent runs, two at a time, all passed;
- `check-test-fails` (10 cases), `check-clean`, `check-guix` (83 host-side), `check-pins` and
  `check-help` all passed.

| Mutation | Guards | Change | Result |
|---|---|---|---|
| stray `.ss` | `src/` holds plain `.sls` files only | a `counters.ss` without the refusal import, beside `counters.sls` | `FAIL src/ holds no file Chez could load as a library but a .sls: …`. **Reproduced here.** |
| stray, each other ending | the same | `.scm`, `.sch`, `.so`, `.chezscheme.sls`, `.chezscheme.so` | 1 failure each; `.chezscheme.sls` 2 |
| the stray rule off | the per-ending rows | the ending test always false | 7 failures |
| cut refusal message | the whole message | the message cut to its first words | `FAIL where (threaded?) is #f, the refusal raises its whole message at expansion`. **Reproduced here.** |
| counters' messages cut | the whole message | each message shortened | 2 and 4 failures |
| `lock-file?` without its existence test | the restored row | `(not (file-exists? path))` made `#t` | `FAIL the scan reads a .# link that resolves, which is no lock file`. **Reproduced here.** |
| unquoted arguments | `capture-command` quotes | words joined unquoted | 9 failures |
| a fixed directory | `capture-command`'s own directory | a fixed name | 3 failures, the two-thread row among them |
| no removal | `call-with-temp-directory` removes | its after-thunk a no-op | 5 failures |
| the absolute-path guard | `remove-temp-directory` refuses a relative path | the guard removed | 1 failure |
| a workflow directory | the workflows tripwire | `.github/workflows/ci.yml` added | `check-floors: .github/workflows: it exists, but the workflow rules are not written yet (M0 slice 4)`. **Reproduced here.** |
| the tripwire off | its rows | `workflows-problems` answers nothing | 3 failures |
| a `git clone` line | the clone-line tripwire | `docs/install.md` with one | 1 failure |
| the sentinel | a row that expects a raise | its thunk returns the expected value | the old `refusal` passed it; the new one fails it |
| TT1 | `make test` refuses a bad `TEST_TIMEOUT` | the check removed | host-side 73/10: with 0 and 007, `make test` ran and passed, 0 meaning no limit; 1.5 and empty failed at the suite, not with the refusal. Written with the check, so this is its red run. |

## Not covered, after the review

- **The mutex's `critical-section`, and `native-counts` reading without the lock:** removing
  either passed every suite, three runs of three (the review). An interrupt between taking the
  mutex and winding, or a torn read, is not something a suite here can make happen on demand.
- **`suite-exit-status`'s two `flush-output-port` calls:** removing both passed. They order the
  runner's summary before the verdict's lines in a terminal, which no check reads.
- **`run-until`'s wait in the counters' thread test is not mutated.** A wait that never ends would
  run for its full two minutes.
- **The stray rule reads names only,** so a `.so` that is a link to a directory is skipped.

**The whole set rerun.** The 27 mutations of this slice's own checks, and TT1, were rerun on
the fixed tree. All 28 applied, and each exited non-zero with the failures recorded above. G1
now reads 82/1, and the host-side tests have grown from 70 to 83 checks.
