# M1 slice 3 mutation log: refusals end to end

This log is the evidence that each new check fails through the property it claims to guard. The
new checks are:

- the decoy;
- the refusal probe and `tests/test-library-loading.sps`;
- preflight's counts;
- `gated-command` and the gate's children;
- `make dev` and `check-dev`;
- CI's install check and the rules `check-ci` adds.

The records behind them are the [M1 plan](2026-11-13-m1-plan.md) (§3.3, §3.4, §3.8, and slice 3
in §5), [ADR-0002](decisions/0002-runtime-libsqlite3-discovery.md), amended, and
[ADR-0005](decisions/0005-memory-gate.md), amended. The format is
[slice 2's log](m1-slice-2-mutation-log.md).

An Opus agent built the slice, test first, from the copy table the coordinator ruled on. The
sources are chez-curl's `decoy-libcurl.c`, `refusal-probe.sps`, `test-library-loading.sps`,
`check-dev.sh`, its fixture `raising/curl.sls`, and its Makefile's `dev` and `check-dev`, at
`79c6ced`.

**How each mutation ran:**

- In its own copy of the working tree, in the session scratchpad, without `.git`, `build/` or
  vendor's `.git` files.
- Through that copy's own `scripts/guix-env`, after `make deps` in the copy.
- Through a driver that refused any edit whose text did not occur exactly the stated number of
  times, and any edit that changed nothing. A move cut the text between two unique markers and
  put it back before a third.
- The working tree was never edited by a mutation.
- Counts are read from the suites' own output (`# of expected passes`,
  `# of unexpected failures`), never by eye.
- The drivers are in the session scratchpad, not the repository.

## The red runs

| Check | Red run | Green run |
|---|---|---|
| `test-library-loading` | No probe, no decoy, no fixture, and HEAD's preflight: 7 passed, 53 failed. The passes are rows nothing missing can reach: CHEZ, CC, mktemp, the floors, the oracle's own guard, this process, and the scratch directory's removal | 60 passed |
| `test-library-loading` | Against a stub native, every export answering `stub`: 9 passed, 51 failed. The two more are the raising fixture's rows, which shadow native | 60 |
| `test-chez-sqlite3-testing` | Against a stub `gated-command` that returns the command unchanged: 61 passed, 3 failed (set, blank, not a command). The unset row is one a stub can satisfy | 64 |
| `test-check-ci` | The new suite against HEAD's `check-ci.sh`: 7 passed, 159 failed, since the new workflow fails the old script | 166 |
| `check-ci.sh` | The new script on HEAD's `ci.yml`: `job main has 0 steps that run "make build", not one`, and the same for the new make line. FAILED (problems: 2) | the one-line pass |
| `check-ci.sh` | The new banned names with the loop's literal bound, 11, kept: 157 passed, 9 failed. The seven new words' rows failed, and so did `an env key CC on main's install check`. So did `the CHEZ path of nothreads swapped to main's`, whose anchor named the sixth `CHEZ:` line, and the install step had made it the seventh. The anchor is now 7, with a comment saying why | 166 |
| `check-memory-gate` | The new cases on HEAD's gate, which exports no child prefix and reads no child log: 39 passed, 9 failed: p leak, p overrun, p clean, q options, q other, both q oracle, q forged, q stale. The three that passed need no gate: p plain twice, and q unwrapped | all 48 cases |
| `check-dev` | Against HEAD's Makefile, which has no `dev`: both cases, `make: *** No rule to make target 'dev'.` | ok |

## The mutations

### The load, by behaviour (`test-library-loading`; baseline 60)

Slice 2's data rows in `test-native` hold the load's order as text. These rows hold it by
behaviour, in a fresh process per row.

| Mutation | Guards | Failed |
|---|---|---|
| N1 | the floor before threadsafe: step 4 moved after step 5 | 4: `below-floor` (its log gained `sqlite3_threadsafe()`), lacks-open_v2 and lacks-threadsafe under `below-floor`, the kept refusal |
| N2 | the floor before the rest: the ten bindings moved before step 4 | 14: the ten lacks-rest rows, lacks-rest, and the three lacks-open_v2 order rows |
| N3 | eager binding: `sqlite3_errstr` bound at each call | 1: lacks-errstr, which loaded |
| N19 | initialize before the rest: step 6 moved after step 7 | 12: the ten lacks-rest rows, lacks-rest, and lacks-open_v2 under `initialize-fails` |
| N20 | `missing-api` carries the report: `sqlite3_close` bound with `#f` | 1: lacks-close |
| **N21** | `foreign-entry?` asked: `required-entry` asks nothing | **17**: every lacks row and not-sqlite, each `(raised . "Exception in foreign-procedure: no entry for \"…\"")`, exit 2. `test-native` still passed 43 here, as in slice 2: the survivor is killed |
| N26 | initialize's code read: taken as 0 | 2: both `initialize-fails` rows |
| N27 | threadsafe's answer read: handed 1 | 8: every loaded control row (`threadsafe` 1, not 2), and the three `not-threadsafe` rows, which loaded |
| N10 | the override read: discovery's getenv hides `CHEZ_SQLITE3_LIBRARY` | 41: every row through the override |
| L1 | step 0's re-raise: `(when #f (raise failure))` | 33: every refusal row, whose second reference ran the load again and raised a fresh refusal (`again` not `same`), and the kept refusal |
| L2 | `answered-null` names its entry point: libversion's named as sourceid's | 1: `libversion-null` |

### The paths slice 2's review found, which passed every slice 2 suite

| Mutation | Path | Failed |
|---|---|---|
| R4 | `check-version` fed 3045001, not the report's number | 5: `below-floor`, the two order rows under it, the kept refusal, preflight below the floor |
| R5 | `sqlite3_initialize`'s answer never checked | 2: both `initialize-fails` rows |
| R6 | the NULL-`sqlite3_libversion` refusal dropped | 1: `libversion-null` |
| R7 | `missing-api` always carrying library `#f` | 13: the twelve lacks rows after the report, and lacks-rest |
| R8 | `not-threadsafe` never raised: `threadsafe-checked` defined as `#t` | 3: the three `not-threadsafe` rows |
| R9 | the loader's `load-failed`: the guard never matches, so the loader's own raise escapes | 3: the text file, the missing path, and the broken Guix candidate |
| R10 | `invalid-override` through native: discovery takes any override as given | 2: the bare-name row and preflight's |
| R11 | `not-found` through native: discovery takes the first candidate, existing or not | 2: the Guix not-found row and preflight's |

### The probe, the decoy and preflight

| Mutation | Guards | Failed |
|---|---|---|
| P1 | the probe reaches native by `eval` inside its guard: it imports `loaded-libsqlite3` instead | 36: every refusal row. The body ran before the guard, and the probe died in Chez's handler |
| P2 | `again` compares by `eq?`: always `same` | 1: the raising fixture's row, whose later references raise fresh errors |
| D1 | only an exact value is a switch: an empty value taken for unset | 1: the empty-value row (`decoy(control)`, not `decoy(?)`) |
| D2 | the decoy answers below the floor: its number left at the floor | 5: `below-floor`, both order rows under it, the kept refusal, preflight below the floor |
| F1 | preflight prints its counts on a refusal: the line dropped | 3: preflight below the floor, the bare name, and Guix not-found |
| F2 | preflight's remedy is the refusal's message: `format` of the detail, unimported | 6: every preflight row. The edit broke the whole program, so it was rerun as F2b |
| F2b | the same, as preflight's own fallback text | 3: the three refusal rows of preflight |

### The worlds

| Mutation | Guards | Failed |
|---|---|---|
| W1 | the FHS branch, faked in the container: `world` forced to `fhs` | 2: `discovery (fhs world)` and `not-found (fhs world)`. The child loaded `$GUIX_ENVIRONMENT`'s library, source `guix-environment`, where no FHS candidate exists. The Guix branch's rows did not run, as their name says |
| W2 | the Guix branch: `/run/current-system/profile` dropped from the candidates | 2: `not-found (guix world)` and its preflight row |

### The gate's children (`check-memory-gate`, baseline 48 cases; G1 under `make test-memory`)

| Mutation | Guards | Failed |
|---|---|---|
| G1 | `gated-command` puts the gate's prefix first: it returns the command unchanged | `test-memory: FAIL tests/test-library-loading.sps (exit 1)`, 19 passed and 41 failed, every child row on `(valgrind . no)`. `test-blocks` passed: no row of its own holds its child |
| G2 | the gate exports the prefix: dropped | 9 cases, the red run's nine |
| G3 | the gate reads each child log: none read | 7: p leak, p overrun, q options, q other, q oracle (leak), q forged, q stale |
| G4 | a child log an earlier run left is removed | 1: q stale |
| G5 | a child's `Command:` line read: never | 3: q other, both q oracle (each child then had to be Chez) |
| G6 | the oracle is held to its own program: Valgrind taken to have run CHEZ | 2: both q oracle |

### `make dev` (`check-dev`)

| Mutation | Guards | Failed |
|---|---|---|
| K2 | `dev` runs build first: `dev: deps` | repl: `build's report appears 0 times, not once`; refused: `make dev passed with CHEZ_SQLITE3_LIBRARY naming no file` |
| K3 | the REPL has the suites' library path: `--libdirs src` | repl: `the line "check-dev: ok version VERSION (NUMBER)" appears 0 times` |
| K4 | a refusal stops the REPL: build run in the recipe with `\|\| true` | refused: `make dev passed with CHEZ_SQLITE3_LIBRARY naming no file` |

## Not caught here

- **A child started without `gated-command`** runs outside Valgrind. Case q unwrapped passes: it
  is the gap ADR-0005 records. `test-library-loading`'s children each say whether memcheck mapped
  them, which catches G1 there. `test-blocks`' child and the oracle are held by no row: G1 left
  `test-blocks` passing.
- **The Ubuntu path of CI's install check** is read from CI's log, not asserted (the
  coordinator's ruling).

## Measured before the code

All of this was measured in the container: Valgrind 3.27.0, Guix's SQLite 3.53.1, 18 cores.

- **P1: under `--trace-children=yes`, the static bash breaks every child.**
  - Chez's `system` runs `/gnu/store/…-bash-static-5.2.37/bin/bash -c --`.
  - Traced, that bash reports 295 to 311 errors from 29 to 34 contexts, every one "Conditional
    jump or move depends on uninitialised value(s)" in the stripped static binary. It exits 9.
  - So a clean Chez child and a leaking one both answered 9.
- **P2: a redirected command makes bash fork**, so a capture traces two processes. An exec chain
  in one pid leaves one `%p` log, the last program's.
- **P3: the tools are not clean under the gate's flags.**
  - `mktemp -d` loses 44 bytes in 2 blocks definitely.
  - gcc reports 10 errors in the driver and 31 in cc1.
  - Both exit 9.
- **P4: a traced Chez child shows its own 777-byte leak.** Untraced, today's gate passed the same
  parent.
- **M4: a child under the gate's Valgrind maps `vgpreload_memcheck` into its `/proc/self/maps`.**
  The probe reads `(valgrind . yes)` there, and `no` without it.
- **M5: `%p` gave each child its own log.** 53 children left 53 logs in one suite.

## The children: option (a) against option (b)

Each variant of (a) ran Valgrind with the gate's flags, `--trace-children=yes` and a `%p` log,
directly on the suites. The skip list was
`*/gcc,*/cc,*/mktemp,*/rm,*/mkdir,*/mkfifo,*/sleep,*/kill,*/readlink,*/ln,*/touch,*/awk`. The
planted child is a parent that runs `tests/memory-plant-leak.sps` as a plain child.

| Variant | test-blocks | test-native | test-library-loading | The planted child leak |
|---|---|---|---|---|
| a1: tools skipped | 7 passed, 1 failed | 33 passed, 10 failed | died at its scratch directory: mktemp's bash exited 9 | seen, but its bash exited 9 too |
| a2: a1, plus `*/bash` | 8 passed | 43 passed | 60 passed in 14 s. 87 logs, 86 of them with no summary: no child traced | **not seen** |
| a3: a1, plus a suppression of `Memcheck:Cond` in `obj:*-bash-static-*/bin/bash`, container only | 8 passed, in 11 s | 43 passed, in 13 s | 253 s and 173 logs, 52 of them Chez's, all clean. Its 41 failures were its own `(valgrind . no)` expectations: every probe ran traced | seen |
| **b: `gated-command`** | 8 passed, in 11 s (7 s before); 1 child log | 43 passed, in 10 s; 1 child log, the oracle | 60 passed, in 223 s (14 s before); 53 child logs: 51 Chez children and 2 oracle runs | seen: case p leak |

The first try at a3's suppression wrote `obj:*/bash-static-*`. The store directory is
`…-bash-static-5.2.37`, with no `/` before `bash-static`, so it suppressed nothing; the corrected
pattern did.

(b) was chosen.

- **It needs no suppression and no skip list kept by hand.**
- **It costs about the same as a3:** about 4.1 s per Chez child, 209 s over 51 children, and
  about 0.25 s per oracle run.
- **The whole `make test-memory`:**

  | Tree | Gate | Suites | Time |
  |---|---|---|---|
  | HEAD | today's | 16 | 155 s |
  | this slice | today's | 17 | 171 s |
  | this slice | (b) | 17 | 409 s |

- **The oracle under the gate's options** ran with 0 errors from 0 contexts. It lost nothing
  definitely, indirectly or possibly, left 3,732 bytes in 9 blocks still reachable from its
  dlopen, and took 253 ms. So it is wrapped.

## The final runs

In the working tree, through `scripts/guix-env`, after every change above:

- **`make test`:** ran 17, passed 17.
  - `test-library-loading` 60, `test-chez-sqlite3-testing` 64, `test-check-ci` 166, `test-native`
    43, `test-blocks` 8.
  - `check-seam`: the seam holds, 10 libraries in 10 files.
  - `check-ci` passes.
- **`make test-memory`:** ran 17, passed 17, in 409 s. Child logs: `test-library-loading` 53,
  `test-blocks` 1, `test-native` 1.
- **`make check-memory-gate`:** "failed, as it must, and its refusals held, in all 48 cases".
- **`make check-test-fails`:** "make test failed, as it must, in all 12 cases".
- **`make check-dev`:** ok.
- **`make check-clean`:** ok.
- **`make build`:**
  - Names Guix's 3.53.1 by the override, then `  counts:     ((block . 0) (connection . 0)
    (statement . 0))`, exit 0.
  - With the override unset, it names the same file, source `guix-environment`.
  - With a bare name, it prints `(reason . invalid-override)` and its counts, exit 1.
