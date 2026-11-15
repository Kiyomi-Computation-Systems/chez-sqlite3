# M1's closing review mutation log

Evidence that the closing review's fixes fail through the property each claims to hold. Format of
[slice 4's log](m1-slice-4-mutation-log.md).

**The review** ran on `main` at `497d45b`, on Opus and read-only. It found no blocker, 3 major findings
and 6 minor ones:
- **Major 1:** raises inside critical sections, at eight sites.
- **Major 2:** `open-database` and `sqlite-compile-option?` refused under engines.
- **Major 3:** `test-ci-sqlite`'s build rows failing on a bare `CHEZ`. The maintainer's Mac found it
  first.
- **Minors:**
  - the CI scripts' execute bits not held;
  - the ledger's stale Now section;
  - status lines missing their newest amendments;
  - stale comments;
  - strict branch protection off;
  - `sqlite-library-unavailable-detail`'s documentation.

**Where each was fixed:**
- **Majors 1 and 2:** an Opus builder.
- **Minors 1, 4 and 6:** a Sonnet builder, in a worktree of its own.
- **By the caller:**
  - Major 3;
  - `CHECK_CI_ROOT` among the banned words;
  - the records: minors 2 and 3;
  - strict protection, minor 5, turned on with the maintainer's approval.

## Major 3: the build rows get the Chez by its path

- **Before:** with `CHEZ=scheme` in the container, `test-ci-sqlite` ran 77 passed and 2 failed: the
  two `build-sqlite.sh` success rows, with `scheme: command not found`. The maintainer's Mac failed
  the same two, with `chez`.
- **After:** the suite resolves `CHEZ` with `command -v`, as it resolves `CC`. A row holds the
  answer to an absolute path, and the build rows get that path. It passes 80 of 80, with `CHEZ` bare
  and with it absolute. `make test` with `CHEZ=scheme` ran 26 suites and passed 26.

## Majors 1 and 2: measured first (Guix container: Chez 10.4.0, SQLite 3.53.1)

- **The review's probes, reproduced at `9fd795a`.** `cs-probe.sps`: a handler ran at depth 2 for
  `call-with-open-handle`'s not-a-database, closed, wrong-thread (on the forked thread) and PROC's
  raise; for `call-with-database`'s failed open and U+0000; for `free-foreign-block!`'s
  not-a-live-block; and for `close-database!`'s double free. A guard clause ran at depth 1 for each.
  `cs-probe2.sps`: `(handler 2 call-with-database busy)` for a failed close, and
  `(handler 2 probe)` for a re-entry. `engine-probe.sps 20 50 ":memory:"`: all 50 opens refused,
  "re-entered after its block was freed". `engine-probe2.sps`: `sqlite-compile-option?` refused
  at fuel 10, 20 and 40, answered `#t` at 80. No count was left in any run.
- **Today's ticks.** In one slice of 10,000,000 ticks, an open and close of `:memory:` took 91
  ticks, and `sqlite-compile-option?` 56. Over fuel 1 to 400 the open was refused at 73 sizes, and
  `sqlite-compile-option?` at every size from 1 to 56.
- **An engine spends no ticks inside a critical section.** A loop of 1,000 iterations, at 10 ticks
  a slice: plain, it expired 100 times; inside `critical-section`, never, 8 ticks left. The same
  loop then 50 plain iterations: 5 expiries. So once the open holds its string in a section, an
  engine of more than a few ticks never expires inside the call at all. The engine rows assert the
  answer at every fuel, and an expiry at fuel 1 only.
- **`foreign-alloc` never answers 0.** Asked for 2^46 bytes, and for `(greatest-fixnum)`, it raised
  an assertion violation whose who is the string `"foreign-alloc"` and whose irritant is
  `"Cannot allocate memory"`; 2^62 is "not a positive fixnum". So memory's `(eqv? address 0)`
  branch was dead. Under the gate's Valgrind, `(foreign-block (greatest-fixnum))` raised the same
  and Valgrind reported `ERROR SUMMARY: 0 errors from 0 contexts`, with no fishy-argument warning.
  `vm.overcommit_memory` was 0; no address space holds 2^60 bytes whatever it is.
- **`critical-section` is `(dynamic-wind disable-interrupts (lambda () …) enable-interrupts)`** on
  10.4.0 (`expand`). A guard inside a section caught a raise at depth 2, and the depth after the
  section was 1.
- **Where the re-entry refusal sits.** F's text puts it in a plain before thunk around the block's
  whole extent. That thunk would also refuse a resume between the free and the end of that
  extent, though PROC had returned. An engine sweep of `call-with-c-string` with a PROC that does
  nothing, fuel 1 to 300, both shapes: every refusal came before PROC had finished, none after
  (`mut-window.txt`). The extra wind that would close that window bought nothing measurable, so
  the fix keeps F's shape, and its comment says so.

## The red runs

The rows were written first, and run against the code at `9fd795a`: HEAD's `connection.sls`,
`memory.sls`, `native.sls`, `report.sls` and `tests/chez-sqlite3-testing.sls`, with the new suites.
Each row's handler reads `(let ((n (disable-interrupts))) (enable-interrupts) n)` first, written
`depth-N` so no thread id is taken for it, then what was raised by who and irritants. It escapes,
and its no-raise sentinel is `(no-raise VALUE)`.

| Suite | Red run | Each row's failure | Final |
|---|---|---|---|
| `test-connection` | 49 passed, 8 failed | the six depth rows at `depth-2`, one of them holding two sites; the warning row resumed, `(proc-went-on handled)`; the engine row refused at fuel 1 to 44 and 60 | 57 |
| `test-blocks` | 8 passed, 3 failed | each at `depth-2` | 11 |
| `test-native` | 44 passed, 2 failed | re-entry at `depth-2`, both helpers; the freed-by-PROC free at `depth-3`, through `call-with-c-string` | 46 |
| `test-public` | 18 passed, 1 failed | the engine row refused at every fuel, 1 to 40 | 19 |
| `test-chez-sqlite3-testing` | 75 passed, 1 failed | `depth-2` | 76 |

Baselines before the rows: 47, 8, 44, 17 and 75. Three new rows passed red, by design: they hold
guards the fix adds where today's raises were already outside a section. They are
`open-database`'s failed open and U+0000 at depth 1 (`B2` fails it), `sqlite-compile-option?`'s
refusals at depth 1 (`G1`), and `call-with-open-handle` answering every value of its procedure.

How each site was reached from a suite:

| Site | Row's suite | Reached by |
|---|---|---|
| 1. `call-with-open-handle`: not a database, closed, wrong thread, PROC's raise | `test-connection` | its own calls; the wrong thread from a forked thread, every wait bounded |
| 2. `call-with-database`'s open: CANTOPEN and U+0000 | `test-connection` | a missing directory; a name holding U+0000 |
| 3. `call-with-database`'s critical after thunk | `test-connection` | an untracked statement made with a raw `sqlite3_prepare_v2`, on a return and on an escape |
| 4. `close-connection`'s count-down | `test-connection` | the suite's own `(count-down! 'connection)` before the close: the review's plant, made from a suite |
| 5. `free-foreign-block!`: not live, and its count-down | `test-blocks` | `(free-foreign-block! 'x)`; a `(count-down! 'block)` before the free |
| 6. `foreign-block`'s malloc | `test-blocks` | `(foreign-block (greatest-fixnum))` |
| 7. `call-with-block`'s re-entry | `test-native` | a continuation into PROC, through `call-with-c-string` and `call-with-out-pointer` |
| 8. `make-capture-directory`'s refusal | `test-chez-sqlite3-testing` | `TMPDIR` at a missing directory |
| 9 (new). `call-with-block`'s free, in its critical after thunk | `test-native` | a PROC that frees its own block, so the free on the way out finds none: through `call-with-c-string` only (below) |
| Major 2 | `test-connection`, `test-public` | engines of every fuel from 1 to 60, and 1 to 40 |

**Reached only by a plant:** an allocation failure inside `call-with-block`'s critical before
thunk. Its sizes are a string's length plus one and a pointer's, so no suite can make malloc fail
there. The plant made `call-with-out-pointer` ask for `(greatest-fixnum)` bytes, and a probe read
the depth for three calls (`mut-plant.txt`):

| Run | `call-with-out-pointer` | `open-database` | `call-with-database` |
|---|---|---|---|
| the plant | depth 1 | depth 1 | depth 1 |
| the plant, and F3: the before thunk's guard dropped | **depth 2** | depth 1, the open's own guard catching it | depth 1 |
| the plant, and B2: the open's guard dropped | depth 1 | **depth 2** | **depth 3** |

Every count was zero after each run: the string's block was freed when the slot's could not be made.

## The fixes

| Fix | Where | What changed |
|---|---|---|
| A | `connection.sls`, `call-with-open-handle` | `check-owned` before the section; the section reads the handle and runs PROC under a guard, answering `(answered . values)`, `(raised c)` or `(closed)`; after it, `apply values`, `(raise c)` or `raise-closed` |
| B | `connection.sls`, `open-outcome`, `opened-database` | one section holds `call-with-c-string`'s whole extent, under a guard, and answers `(opened db)`, `(failed code message)` or `(raised c)`; `opened-database` raises after it. `open-connection` is the two composed |
| C | `connection.sls`, `call-with-database` | the body opens in a section that sets `db` and answers the outcome, raised after; the critical after thunk closes and records `close-failure`; a new plain outer `dynamic-wind`'s after thunk raises it unless `raising` |
| D | `connection.sls`, `close-connection`; `memory.sls`, `free-foreign-block!` | `count-down!` runs under a guard in the section, answering `(double-free c)`, raised after |
| E | `memory.sls` | `free-foreign-block!` answers `(not-live)`, refused after; `foreign-block` catches `foreign-alloc`'s raise in its section and raises it after; the dead `(eqv? address 0)` branch is gone |
| F | `native.sls`, `call-with-block` | a plain outer `dynamic-wind`: its before thunk refuses a re-entry; its after thunk raises a free's failure that the critical after thunk recorded. The critical before thunk records an allocation failure, and the body raises it before FILL! |
| F, callers | `report.sls`, `sqlite-compile-option?` | the C string's whole extent in one section, under a guard, raised after; imports `critical-section`, already on the seam's allowlist |
| site 8 | `tests/chez-sqlite3-testing.sls` | `make-capture-directory` answers `(made DIR)` or `(failed DIR)`; `capture-command` raises after the section |

**Three changes of mechanism from the review's design**, each keeping its contract and every row:

1. **D adds no `count-down`.** `test-counters` holds the counters' exports exactly, so a new export
   fails an existing row. Each section instead runs `count-down!` under a guard and raises its
   condition after the section. That is the same object, with the same who and irritants, and A's
   own pattern.
2. **B adds no U+0000 check to `prepared-open`.** A guard in the open's section catches
   `call-with-c-string`'s refusal and raises it after, with the same who and irritants. The guard is
   needed anyway: under F, an allocation failure is raised by `call-with-block`'s body, which is
   inside the open's section (the plant's B2 row). With the guard, a second U+0000 check would be
   one no row could tell from its absence. `sqlite-compile-option?` takes the same guard, since its
   U+0000 refusal would otherwise be raised inside its new section.
3. **F keeps its outer before thunk,** after an inner one was tried and measured (above).

## The mutations

Baselines, from the fixed tree: `test-connection` 57, `test-blocks` 11, `test-native` 46,
`test-public` 19, `test-chez-sqlite3-testing` 76. 18 mutations, every one caught, every caught
suite exiting 1. Each puts its site's raise back inside its section, or undoes its fix, and
`mut-NAME.txt` holds its diff and the suite's whole output. The table is the final run, against
the final tree.

| Mutation | Guards | Passed, failed | Failed rows, and what they saw |
|---|---|---|---|
| A1 | `call-with-open-handle`: the database and owner checks before the section (`check-owned` moved inside) | 55, 2 | not-a-database `depth-2` (closed stays `depth-1`); wrong thread `depth-2` |
| A2 | the closed refusal answered as data (`raise-closed` inside) | 56, 1 | closed `depth-2` |
| A3 | PROC's raise caught in the section (the guard dropped) | 55, 2 | PROC's raise `depth-2`; the warning resumed, `(proc-went-on handled)` |
| B1 | `call-with-database`'s open outcome raised after its section (`opened-database` inside) | 56, 1 | CANTOPEN and U+0000 `depth-2` |
| B2 | the open's section catches what it raises (its guard dropped) | 55, 2 | `open-database`'s U+0000 `depth-2`; `call-with-database`'s `depth-3` |
| B3 | the open's section holds the C string's whole extent (moved back inside its PROC) | 56, 1 | the engine row: refused at 47 of 60 fuels |
| C1 | `call-with-database`'s critical after thunk records the close's failure (raised there again) | 56, 1 | return and escape `depth-2` |
| C2 | while PROC raises, the close's failure is not raised over it (the outer after thunk raises always) | 55, 2 | raise-then-fail, plain and under an inner guard: the close's `untracked-statements` reached the caller |
| C3 | on a return or an escape, the close's failure raises (the outer after thunk never raises) | 54, 3 | return-then-fail and escape-then-fail answered `returned` and `escaped`; the depth row `(no-raise returned)` and `(no-raise escaped)` |
| D1 | `close-connection`'s double free caught in its section (the guard dropped) | 56, 1 | `depth-2` |
| E1 | `free-foreign-block!`'s not-live answered as data (the refusal inside) | 10, 1 | `depth-2` |
| E2 | `free-foreign-block!`'s double free caught in its section (the guard dropped) | 10, 1 | `depth-2` |
| E3 | `foreign-block`'s malloc failure caught in its section (the guard dropped) | 10, 1 | `depth-2` |
| F1 | `call-with-block`'s re-entry refused from a plain thunk (moved into the critical before thunk) | 45, 1 | both helpers `depth-2` |
| F2 | `call-with-block`'s failed free recorded in the critical after thunk (raised there) | 45, 1 | `depth-2` |
| G1 | `sqlite-compile-option?`'s section catches what it raises (its guard dropped) | 18, 1 | U+0000 `depth-2` (not-a-string stays `depth-1`) |
| G2 | `sqlite-compile-option?` holds the C string's whole extent in a section (the section dropped) | 18, 1 | the engine row: refused at all 40 fuels |
| H1 | `make-capture-directory` answers its failure (the `error` back inside the section) | 75, 1 | `depth-2` |

The plant's F3 (above) is the nineteenth: F's allocation failure, reachable only by a plant.

**One row's own misuse, caught by the gate.** Site 9's row first asked both helpers. Under
`make test-memory`, `test-native` failed with one error: `Invalid read of size 8`, `0 bytes inside a
block of size 8 free'd`. That was `call-with-out-pointer` reading its slot with `foreign-ref` once
PROC returned, after the row's PROC had freed it. `make test` passed, since nothing in-process
sees a read after free. The site is `call-with-block`'s, which both helpers share, so the row now
asks `call-with-c-string` alone, which reads nothing after PROC. Under the gate, `test-native`
then passed alone (`ERROR SUMMARY: 0 errors from 0 contexts`), and F1 and F2 were rerun against it,
as was its red run. The table above is from that rerun.

**One driver slip, caught by reading the output.** C1's first run had one close parenthesis too
many: `Exception in read: unexpected close parenthesis`, exit 255, no test run. A driver that took
any failing exit for a caught mutation would have counted it. Every mutation's failing rows were
read for the depth or the refusal they name; C1 was rerun with the parenthesis fixed.

## Not covered

- **An allocation failure, from a suite.** No suite can make malloc fail for a string's block or a
  slot. The plant above holds both guards that catch one.
- **A double free in the failed open's count-down.** `open-outcome` counts a failed open's handle
  up and down in one section, so only another thread's count-down in between could make it a
  double free. No row can schedule that. The open's guard catches it, as it catches anything raised
  in that section.
- **A free that fails on the way out of `call-with-out-pointer` after `sqlite3_open_v2` returned a
  handle.** That handle would be lost, as at `9fd795a`. It needs PROC to free the slot it was
  given, and the open's PROC does not.
- **A PROC that frees `call-with-out-pointer`'s slot.** The helper then reads freed memory, which
  only Valgrind sees (above). It is a misuse of a private helper that no caller makes, and nothing
  refuses it.
- **The window F's outer before thunk leaves,** between the free and the end of the outer extent:
  never hit in the sweep above.
- **What a depth-2 handler costs.** The review measured it (`cs-probe3.sps`): an engine in such a
  handler never expired, and another thread's `collect-rendezvous` waited more than 11 s. The rows
  hold the depth, which is the cause, not those costs.

## Final runs

In the container, on the worktree, all six in one run, after site 9's row was narrowed. The first
`make test-memory` before that answered `ran 26, passed 25, failed 1, hung 0` (above).

- **`make test`:** `test: ran 26, passed 26, failed 0, hung 0`, with
  `check-seam: the seam holds (15 libraries in 15 files checked)`.
- **`make check-test-fails`:** `check-test-fails: make test failed, as it must, in all 13 cases`.
- **`make check-clean`:** `check-clean: ok: make clean removes build/, follows no link out of it,
  changes nothing else, passes again, and make deps works after it`.
- **`make check-dev`:** `check-dev: ok: in a fresh copy, make dev runs deps and build, then a REPL
  with the suites' library path and build's libsqlite3; a refused libsqlite3 stops it`.
- **`make check-memory-gate`:** `check-memory-gate: the memory gate failed, as it must, and its
  refusals held, in all 56 cases`.
- **`make test-memory`:** `test-memory: ran 26, passed 26, failed 0, hung 0`. The changed suites'
  Valgrind logs:

  | Suite | Errors | Lost | Still reachable | Children |
  |---|---|---|---|---|
  | `test-connection` | 0, from 0 contexts | 0 definitely, indirectly or possibly | 8,896 bytes in 15 blocks | none |
  | `test-blocks` | 0 | 0 | 224 bytes in 4 blocks | 1, 0 errors |
  | `test-native` | 0 | 0 | 15,256 bytes in 11 blocks | 1, 0 errors |
  | `test-public` | 0 | 0 | 1,920 bytes in 8 blocks | none |
  | `test-chez-sqlite3-testing` | 0 | 0 | 13,504 bytes in 6 blocks | 4, 0 errors |

  No suppression was used. The new rows start no child: the engine rows, the forked-thread row and
  the malloc row run in each suite's own process, under the suite's Valgrind.


Suite: tests/test-check-ci.sps, run as `make test SUITES=tests/test-check-ci.sps` in the container.

## Minor 1: a step that runs scripts/ci/NAME by its path needs NAME there and executable

Rows added: base (real scripts copied), 6 scripts without the bit, 2 scripts missing, floor.sh without the bit (passes).

- Red, against check-ci.sh before the rule: 375 passed, 8 failed (the six "without its execute bit" rows, the two "missing" rows). Base and floor.sh rows passed.
- Green with the rule: 383 passed, 0 failed.
- Mutation 1: the test `[ ! -f ... ] || [ ! -x ... ]` replaced by `false` (checked with git diff). Result: 375 passed, 8 failed, the same eight rows. Reverted.
- Mutation 2: the `-x` half of the test removed (git diff checked). Result: 377 passed, 6 failed, the six execute-bit rows; the two missing rows still passed, as they must. Reverted.
- check-ci.sh compared byte for byte with the good copy after the mutations.

### `CHECK_CI_ROOT` banned in workflow lines (the caller)

The new rule reads the scripts under `CHECK_CI_ROOT`, so a workflow line that set it would point
the rule at another tree.
- `CHECK_CI_ROOT` joined `test-check-ci`'s `banned-words`. The row it makes, "a block scalar names
  CHECK_CI_ROOT", failed: 383 passed, 1 failed.
- The word was then added to `check-ci.sh`'s list: 384 passed.

## The caller's checks of the builders' work

- **The review's own probes, rerun on the fixed tree:**
  - every site's handler is at depth 1, the failing close included;
  - `engine-probe.sps` at fuel 20, 40 and 200: 50 of 50 opened and closed, where all 50 were
    refused before;
  - `engine-probe2.sps` at fuel 10, 20 and 40: `#t`, where it was refused before.
- **A mutation of the caller's own:** `call-with-open-handle` raising its procedure's condition
  wrapped, as `(list 'wrapped c)`. `test-connection` ran 55 passed and 2 failed: the
  same-object row and the warning row.
- **The docs' detail list,** checked line by line against `discovery.sls`, `verify.sls` and
  `native.sls`.

## The review of the fixes, and its fixes

The fixes were reviewed by Opus, read-only. It found one major finding and six minor ones, and
each was reproduced. The caller reran its share probe: `()` on the fixed tree and `(8)` on
`mut-A-narrow`. The fixes were made by a Sonnet builder, then by the caller.

Evidence that each row added in the worktree `chez-sqlite3-wt-m1close` (branch `m1-closing-review`, base `41068a5`)
fails through the property it claims to guard. Format of `.plans/m1-slice-4-mutation-log.md`: each mutation was
applied to the worktree's file in place (a saved copy restored after, checked with `cmp`), shown with `git diff -U0`
to have landed where meant, run through `scripts/guix-env make test SUITES=<suite>`, and reverted. Counts are the
suite's own `# of expected passes` and `# of unexpected failures`. Chez 10.4.0, Guix container.

Rows added to tests/test-connection.sps: 63 passes on the fixed tree (60 before this work).

## Reds before the fix

| Run | Passed | Failed | Failing rows |
|---|---|---|---|
| test-connection, connection.sls as at 41068a5 (no dynamic-wind), re-entry rows only | 61 | 2 | "refuses a continuation of its procedure re-entered ..." (actual: `not-reentered`); "runs its procedure once when its continuation is re-entered ..." (actual: 2) |
| test-check-ci, check-ci.sh as at HEAD (no stray rule) | 384 | 11 | every stray row but the existing-rule ones: double-quoted, single-quoted, two spaces, `run: \|`, `run: >-`, `./scripts/ci/`, `scripts/ci//`, `scripts/ci/sub/`, `;true`, `&&true`, `true && ...` |

The engine sweep (fuel 1 to 60) passed before the fix: it guards the fix against an expiry, see M5 and M6.

## Mutations, on the fixed tree (src/chez-sqlite3/private/connection.sls)

| # | Mutation | Passed | Failed | Rows that failed |
|---|---|---|---|---|
| M1 | the critical-section of `call-with-open-handle` replaced by `begin` | 62 | 1 | the close-in-another-engine sweep (on the pre-fix tree the failing fuels were 8 to 12: the procedure ran on a closed connection) |
| M2 | the handle read before the section (`early`), the section's `handle` bound to it | 62 | 1 | the same sweep (on the pre-fix tree: fuel 8) |
| M3 | the guard in the section narrowed to `((condition? c) ...)` | 61 | 2 | the fresh-symbol row and the fresh-pair row: handler depth 2, not 1 |
| M4 | the same two, on the pre-fix tree, when the sweep was first written | 59 | 1 each | the same sweep |
| M5 | `finished` set in the dynamic-wind's after thunk | 61 | 2 | the close-in-another-engine sweep (fuels 9 and 10 refused as re-entered) and the engine sweep of `call-with-open-handle` (fuels 1, 2, 3, 5, ...) |
| M6 | `finished` set before the section | 61 | 2 | the same two sweeps (fuel 10 refused in the first; 1, 2, 5, 10 ... in the second) |

M3's "depth 2" is the raise from inside the section, a handler running with interrupts disabled: the failure the row guards.

## Reached by hand (check-ci's Makefile recipe)

Copy of the tree under the scratchpad, `chmod a-x scripts/ci/check-chez.sh`, host `sh`:

- fixed Makefile, `CHECK_CI_ROOT=/elsewhere make check-ci`: 5 problems, rc 2, as plain `make check-ci`;
- old Makefile, `CHECK_CI_ROOT=<an intact tree> make -f Makefile.old check-ci`: "has the one shape check-ci reads", rc 0 (a pass that should be a failure);
- fixed Makefile, the same variable: "FAILED (problems: 5)", rc 2.


### The caller's additions

- **The stray-path rule now reads `scripts/`, not only `scripts/ci/`.** `run: scripts/./ci/extra.sh`
  passed, since it holds no `scripts/ci/`.
  - Two rows plant `scripts/./ci/` and `scripts//ci/`, with the message naming `scripts/`. Red, 13
    rows failed: the 11 old rows on their new message, and the two new spellings.
  - With the rule widened, `test-check-ci` passed 397, and the real workflow passed `check-ci`.
    Today's workflow names `scripts/` only in comments, its run lines and its cache keys.
- **The re-entry flag's residual window:** `call-with-open-handle` under engines, 20 calls a
  slice, over fuel 1 to 3000. All 60,000 calls ran, and every count was 0.
- **The re-entry and share probes, rerun:** `reenter-handle.sps` is refused with `re-entered`, and
  `share.sps 200` gives `()`.
