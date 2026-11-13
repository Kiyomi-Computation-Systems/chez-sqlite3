# Guix development container mutation log (M0 slice 1)

Evidence that the checks M0 slice 1 added fail through the property each one claims to guard
([harness plan](2026-11-13-harness-plan.md) §6, [ADR-0006](decisions/0006-pinned-guix-container.md)).
Every mutation was applied to a fresh copy of the working tree, made without `.git` in the
session scratchpad. The working tree was never edited. A driver applied each mutation, refused
any whose text didn't occur exactly once, and kept the failures verbatim.

The checks are copied from chez-curl's, whose log (chez-curl `.plans/guix-env-mutation-log.md`)
this follows case for case. The changes are SQLite's library and header, no Node, and the
loopback probe (S2, S13).

`/bin/sh` is dash on the host, Pop!_OS 22.04, so the scripts and the host-side tests ran under a
strict POSIX shell. Inside the container, `sh` is bash. Each mutation ran in its own copy, so the
clean rerun after each one is the baseline itself. A last run of the working tree, after every
mutation, gave both baselines again.

## Host side (`tests/guix-env-launcher.sh`)

**Red run, before any script or the Makefile existed:** `23 passed, 37 failed`, exit 1. The first
failure was `FAIL T1 no-args exits 0`. The 23 that passed were:

- **The absence checks** (`lacks`, `! -s`, `! -e`), which a missing script satisfies.
- **R2, R4, R5 and R6's "exit 2".** dash exits 2 when it cannot open a script. Each case also
  asserts its exact stderr, and that assertion failed.
- **`M1 … fails` and `M1 … runs no test`.** make fails without a Makefile too, and runs nothing.

Each check that passed in the red run has a mutation below that fails it.

**Baseline:** `60 passed, 0 failed`, exit 0, on `4460967` plus this slice.

| Mutation | Change | Result |
|---|---|---|
| L1 | `--network` added after `--container` | 58/2: `T1 no network flag`, `T1 the whole command` |
| L2 | `--emulate-fhs` added | 58/2: `T1 no emulate-fhs flag`, `T1 the whole command` |
| L3a | `SSH_AUTH_SOCK` added to `--preserve`'s pattern | 56/4: `T1 preserves only …`, `T1 the whole command`, both T3 `no agent socket` |
| L3b | a second flag, `'--preserve=^HOME$'` | 58/2: `T1 preserves only …`, `T1 the whole command` |
| L4a | `"--share=$HOME/.ssh"` added | 55/5: `T1 the whole command`, both T3 `no --share` and `nothing from HOME` |
| L4b | `"--expose=$HOME/.gitconfig"` added | 55/5: `T1 the whole command`, both T3 `no --expose` and `nothing from HOME` |
| L5 | the nesting refusal deleted | 57/3: T4's `exit 2`, `names GUIX_ENVIRONMENT`, `prints no command` |
| L6 | `cd "$root"` deleted | 59/1: `T5 subdirectory: runs from the repo root` |
| L7 | `"$@"` unquoted in the guix command | 59/1: `T2 args pass through verbatim` |
| L8 | `set -- bash` changed to `set -- sh` | 58/2: `T1 enters through guix-env-enter`, `T1 the whole command` |
| L9 | `-C channels.scm` dropped | 57/3: `T1 pins guix via channels.scm`, `T1 uses manifest.scm`, `T1 the whole command` |
| L10 | `--container` dropped | 58/2: `T1 container flag`, `T1 the whole command` |
| E1 | the entry script's host refusal deleted | 58/2: T6's `exit 2`, `says why, and what to use` |
| E2 | `export LD_LIBRARY_PATH="$GUIX_ENVIRONMENT/lib"` before the `exec` | 59/1: `T7a no LD_LIBRARY_PATH` |
| E3 | `CHEZ_SQLITE3_LIBRARY` set to `$(readlink -f …)` | 59/1: `T7a CHEZ_SQLITE3_LIBRARY is the profile's libsqlite3.so.0` |
| E4 | `need …/lib/libsqlite3.so.0` deleted | 54/6: `exit 2`, `names …/lib/libsqlite3.so.0`, `runs nothing`, for T7b and T7c |
| E5 | `need` widened to `{ [ -f "$1" ] \|\| [ -L "$1" ]; }` | 57/3: T7c's `exit 2`, `names …`, `runs nothing` |
| E6a | `need …/bin/scheme` deleted | 57/3: T7d's three checks |
| E6b | `need …/bin/gcc` deleted | 57/3: T7e's three checks |
| E7 | `mkdir -p "$PWD/.guix-env"` before the `exec` | 59/1: `T7a no state directory` |
| E8 | `exec "$@"` unquoted | 54/6: T7a's five checks, since its command is one `sh -c` argument that splits, and `T8 enter passes args verbatim` |
| E9a | `CC=gcc` | 59/1: `T7a CC is the profile's gcc` |
| E9b | `CHEZ=scheme` | 59/1: `T7a CHEZ is the profile's scheme` |
| E10 | `exec "$@"` right after `set -eu` | 42/18, including `T6 enter on host: runs nothing` and the `runs nothing` check of T7b to T7e |
| Q1 | `&& [ -z "${GUIX_ENVIRONMENT:-}" ]` dropped from the hint's condition | 59/1: `R4 inside an environment: install hint` |
| Q2 | `break` after the first missing tool | 59/1: `R3 two missing: both named, then one hint` |
| Q3 | the usage test `-lt 2` changed to `-lt 1` | 58/2: R6's `exit 2` and `usage` |
| Q4 | `echo "all found"` before the success exit | 59/1: `R1 all found: silent` |
| Q5 | `exit 0` right after `set -eu` | 49/11: every `exit 2` and stderr check of R2 to R6, and M1's `names the goal` and `runs no test` |
| Q6 | the recipe's `require-tools … guix` line deleted | 58/2: M1's `names the goal` and `runs no test`; the stub `sh` ran |
| Q7 | `$goal` dropped from the container hint | 58/2: R2's and R3's stderr checks |
| Q8 | each `check-guix` recipe line prefixed with `-` | 58/2: M1's `fails` and `runs no test` |

E1 alone leaves `T6 … runs nothing` passing: with the refusal gone, `set -u` stops the script at
the first `need`. E10 fails it.

## `make check-help`

**Baseline:** exit 0, silent.

| Mutation | Change | Result (exit 2 each) |
|---|---|---|
| H1 | `## ` removed from `check-guix`'s line | `make help does not list .PHONY target 'check-guix'` |
| H2 | `check-guix-inside` removed from `.PHONY` | `make help lists 'check-guix-inside', which is not in .PHONY` |
| H3 | `.PHONY` continued over two lines | `the .PHONY line ends in a backslash; keep it on one line`, then `'\'` not listed, and `check-guix` and `check-guix-inside` listed but not in `.PHONY` |
| H4 | `help`'s awk pattern narrowed to `/^[a-z]+:.*?## /` | `check-help`, `check-guix` and `check-guix-inside` not listed |
| H5 | `## ` removed from `help`'s own line | `check-help: make help failed`, after make's `No rule to make target 'Show'` |

## Container (`make check-guix-inside`)

**Red run, before `scripts/guix-env-enter` was used:** the self-test was run in the bare pinned
container, `guix time-machine -C channels.scm -- shell -m manifest.scm --container -- sh scripts/guix-env-selftest`.
It exited 1, with seven assertions failing:

- `chez-variable`, `chez-is-elf`, `valgrind-instruments-chez`;
- `cc-variable`, `sqlite-header`;
- `sqlite-override`;
- `no-bare-name-load` (`'unset' exited 127, expected 3`).

`isolated-home`, the eight `tool-path` checks, `loopback-only`, `no-git` and `check-help` passed.
They test the container, not the entry script, and each has a mutation below.

**Baseline:** `check-guix: ALL CHECKS PASSED`, exit 0. `make check-guix` ran end to end in 1.4 s.

| Mutation | Change | Result |
|---|---|---|
| S1 | `--container` dropped, so plain `guix shell` runs in the host's environment | exit 2: 47 `FAILED isolated-home: … is visible` lines, among them `.ssh`, `.gnupg` and `.gitconfig`; `loopback-only`, with 192.0.2.1 timing out (`exit 124`); and `no-git`, finding the host's git. `tool-path` passed; S12 fails it. |
| S2 | `--network` added | exit 2: `FAILED loopback-only: 127.0.0.1 gave '… Connection refused … exit 1'; 192.0.2.1 gave 'exit 124'` |
| S3 | `--emulate-fhs` added | **survived:** exit 0, every assertion passed. Guix's loader searches no FHS path, so the bare-name load is still refused, and the property this flag would break holds either way, as chez-curl found. L2 guards the flag. |
| S4 | `export LD_LIBRARY_PATH="$GUIX_ENVIRONMENT/lib"` in the entry script | exit 2: `FAILED no-bare-name-load: Chez loaded libsqlite3.so.0 by bare name (LD_LIBRARY_PATH=/gnu/store/…-profile/lib)` |
| S5a | `CHEZ` pointed at a script that `exec`s the profile's `scheme` | exit 2: `chez-variable`, `chez-is-elf` (`starts with '23212f62'`), `valgrind-instruments-chez` |
| S5b | the same script, without `exec` | exit 2: `chez-variable`, `chez-is-elf`. `valgrind-instruments-chez` passed: Valgrind reported on the shell. `chez-is-elf` is the check that catches this one. |
| S6 | `CHEZ` pointed at a `chez` symlink to the profile's `scheme` | exit 2: `chez-variable`, and `no-bare-name-load: … exited 134, expected 3`: Chez aborted looking for `chez.boot` |
| S7 | `libsqlite3.so.0` copied out of the profile, and the override pointed at the copy | exit 2: `FAILED sqlite-override: CHEZ_SQLITE3_LIBRARY is '…/.mut/libsqlite3.so.0', expected …` |
| S8 | `unset C_INCLUDE_PATH` in the entry script | exit 2: `FAILED sqlite-header: … fatal error: sqlite3.h: No such file or directory`. gcc still found `stdio.h`. |
| S9 | `export CC=gcc` | exit 2: `FAILED cc-variable: CC is 'gcc', expected under …` |
| S10 | `## ` removed from `help`'s line | exit 2: `FAILED check-help` |
| S11 | `"--expose=$HOME/.gitconfig"` added | exit 2: `FAILED isolated-home: …/.gitconfig is visible inside the container`, and nothing else |
| S12 | a stub `gcc` put ahead of the profile on `PATH` | exit 2: `tool-path[-lc]` and `tool-path[-lic]` for `gcc`, each naming the stub |
| S13 | the loopback probe pointed at `192.0.2.2`, a sabotage of the check itself | exit 2: `FAILED loopback-only: 127.0.0.1 gave '… Network is unreachable …'`. The loopback half can fail. |
| S14 | `"git"` added to the manifest | exit 2: `FAILED no-git: git is at /gnu/store/…-profile/bin/git` |

## Not covered

- **`GOAL`'s `MAKECMDGOALS` branch.** No target in this slice reaches `require-tools` through a
  prerequisite, so `GOAL`, `$@` and `MAKECMDGOALS` agree in every run. A mutation replacing
  `$(GOAL)` with `$@` would survive. Slice 2's `test` is the first case that can tell them apart,
  and its host-side tests (chez-curl's M2) come with it.
- **The `TIMEOUT` fallback** (chez-curl's T9). `TIMEOUT` arrives with `make test` in slice 2.
- **`loopback-only` shows loopback is up by a refused connection, not an accepted one.** Nothing
  here listens, and nothing in chez-sqlite3 needs a loopback server. It probes one outside IPv4
  address, and no IPv6.
- **`isolated-home` allows the directories that lead to the repository.** Sharing one of them
  whole, such as `--share=$HOME/src`, would pass. This is inherited from chez-curl.
- **`--emulate-fhs` inside the container** (S3). Only L2 catches it.
- **`T1 uses manifest.scm` is positional.** L9 failed it because the lines shifted. `T1 the whole
  command` is the check that pins the manifest's place.
