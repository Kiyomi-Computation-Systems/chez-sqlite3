# Guix development container mutation log (M0 slice 1)

Evidence that the checks M0 slice 1 added fail through the property each one claims to guard
([harness plan](2026-11-13-harness-plan.md) §6, [ADR-0006](decisions/0006-pinned-guix-container.md)).
Every mutation was applied to a fresh copy of the working tree, made without `.git` in the
session scratchpad. The working tree was never edited. A driver applied each mutation, refused
any whose text didn't occur exactly once, and kept the failures verbatim.

The checks are copied from chez-curl's, whose log (chez-curl `.plans/guix-env-mutation-log.md`)
this follows case for case. The changes are SQLite's library and header, no Node, a loopback probe
in bash, and four fixes from the slice's review (L11, N1 to N3), which chez-curl lacks.

`/bin/sh` is dash on the host, Pop!_OS 22.04, so the scripts and the host-side tests ran under a
strict POSIX shell. Inside the container, `sh` is bash. Each mutation ran in its own copy, so the
clean rerun after each one is the baseline itself. Every result below comes from one run of the
whole set after the review's fixes, and a run of the working tree after it gave both baselines
again.

## Host side (`tests/guix-env-launcher.sh`)

**Red run, before any script or the Makefile existed:** `23 passed, 37 failed`, exit 1, of the 60
checks there were then. The first failure was `FAIL T1 no-args exits 0`. The 23 that passed were:

- **The absence checks** (`lacks`, `! -s`, `! -e`), which a missing script satisfies.
- **R2, R4, R5 and R6's "exit 2".** dash exits 2 when it cannot open a script. Each case also
  asserts its exact stderr, and that assertion failed.
- **`M1 … fails` and `M1 … runs no test`.** make fails without a Makefile too, and runs nothing.

**Red run of T9, added after the review, against the launcher of `90c8734`:** `61 passed,
2 failed`: `FAIL T9 GUIX_ENV_DRY_RUN=0: runs guix`, `FAIL T9 GUIX_ENV_DRY_RUN=0: prints no dry
run`. On that launcher, `GUIX_ENV_DRY_RUN=0 make check-guix` printed the guix command and exited
0, with no container run.

Each check that passed in a red run has a mutation below that fails it.

**Baseline:** `63 passed, 0 failed`, exit 0.

| Mutation | Guards | Change | Result |
|---|---|---|---|
| L1 | no network (ADR-0006 §1) | `--network` added after `--container` | 61/2: `T1 no network flag`, `T1 the whole command` |
| L2 | no FHS emulation (§4) | `--emulate-fhs` added | 61/2: `T1 no emulate-fhs flag`, `T1 the whole command` |
| L3a | only `TERM`, `COLORTERM` and `LANG` let in (§1) | `SSH_AUTH_SOCK` added to `--preserve`'s pattern | 59/4: `T1 preserves only …`, `T1 the whole command`, both T3 `no agent socket` |
| L3b | one `--preserve` flag | a second flag, `'--preserve=^HOME$'` | 61/2: `T1 preserves only …`, `T1 the whole command` |
| L4a | nothing of HOME shared | `"--share=$HOME/.ssh"` added | 58/5: `T1 the whole command`, both T3 `no --share` and `nothing from HOME` |
| L4b | nothing of HOME exposed | `"--expose=$HOME/.gitconfig"` added | 58/5: `T1 the whole command`, both T3 `no --expose` and `nothing from HOME` |
| L5 | nesting refused (§1) | the nesting refusal deleted | 60/3: T4's `exit 2`, `names GUIX_ENVIRONMENT`, `prints no command` |
| L6 | the container gets the repo root from any directory | `cd "$root"` deleted | 62/1: `T5 subdirectory: runs from the repo root` |
| L7 | arguments pass through verbatim | `"$@"` unquoted in the guix command | 62/1: `T2 args pass through verbatim` |
| L8 | no arguments means bash | `set -- bash` changed to `set -- sh` | 61/2: `T1 enters through guix-env-enter`, `T1 the whole command` |
| L9 | Guix is pinned (§2) | `-C channels.scm` dropped | 60/3: `T1 pins guix via channels.scm`, `T1 uses manifest.scm`, `T1 the whole command` |
| L10 | the container flag | `--container` dropped | 61/2: `T1 container flag`, `T1 the whole command` |
| L11 | only `GUIX_ENV_DRY_RUN=1` is a dry run (the review's amendment) | the test put back to `[ -n "${GUIX_ENV_DRY_RUN:-}" ]` | 61/2: T9's `runs guix` and `prints no dry run` |
| E1 | the entry script refuses to run on the host | its host refusal deleted | 61/2: T6's `exit 2`, `says why, and what to use` |
| E2 | no `LD_LIBRARY_PATH` (§4) | `export LD_LIBRARY_PATH="$GUIX_ENVIRONMENT/lib"` before the `exec` | 62/1: `T7a no LD_LIBRARY_PATH` |
| E3 | the override names the profile's entry, not the store file | `CHEZ_SQLITE3_LIBRARY` set to `$(readlink -f …)` | 62/1: `T7a CHEZ_SQLITE3_LIBRARY is the profile's libsqlite3.so.0` |
| E4 | a profile without libsqlite3 is refused (§4) | `need …/lib/libsqlite3.so.0` deleted | 57/6: `exit 2`, `names …/lib/libsqlite3.so.0`, `runs nothing`, for T7b and T7c |
| E5 | a dangling symlink is not a library | `need` widened to `{ [ -f "$1" ] \|\| [ -L "$1" ]; }` | 60/3: T7c's `exit 2`, `names …`, `runs nothing` |
| E6a | a profile without Chez is refused | `need …/bin/scheme` deleted | 60/3: T7d's three checks |
| E6b | a profile without gcc is refused | `need …/bin/gcc` deleted | 60/3: T7e's three checks |
| E7 | no state directory (§4) | `mkdir -p "$PWD/.guix-env"` before the `exec` | 62/1: `T7a no state directory` |
| E8 | the command runs verbatim | `exec "$@"` unquoted | 57/6: T7a's five checks, since its command is one `sh -c` argument that splits, and `T8 enter passes args verbatim` |
| E9a | `CC` is the profile's path | `CC=gcc` | 62/1: `T7a CC is the profile's gcc` |
| E9b | `CHEZ` is the profile's path | `CHEZ=scheme` | 62/1: `T7a CHEZ is the profile's scheme` |
| E10 | nothing runs before the checks | `exec "$@"` right after `set -eu` | 45/18, including `T6 enter on host: runs nothing` and the `runs nothing` check of T7b to T7e |
| Q1 | inside an environment, the hint is not the container | `&& [ -z "${GUIX_ENVIRONMENT:-}" ]` dropped from the hint's condition | 62/1: `R4 inside an environment: install hint` |
| Q2 | every missing tool is named | `break` after the first missing tool | 62/1: `R3 two missing: both named, then one hint` |
| Q3 | a goal with no tools is a usage error | `-lt 2` changed to `-lt 1` | 61/2: R6's `exit 2` and `usage` |
| Q4 | silent when every tool is found | `echo "all found"` before the success exit | 62/1: `R1 all found: silent` |
| Q5 | `require-tools` can fail | `exit 0` right after `set -eu` | 52/11: every `exit 2` and stderr check of R2 to R6, and M1's `names the goal` and `runs no test` |
| Q6 | `check-guix` requires guix | the recipe's `require-tools … guix` line deleted | 61/2: M1's `names the goal` and `runs no test`; the stub `sh` ran |
| Q7 | the hint names the goal | `$goal` dropped from the container hint | 61/2: R2's and R3's stderr checks |
| Q8 | `check-guix` fails when its recipe does | each recipe line prefixed with `-` | 61/2: M1's `fails` and `runs no test` |

E1 alone leaves `T6 … runs nothing` passing: with the refusal gone, `set -u` stops the script at
the first `need`. E10 fails it.

## `make check-help`

**Baseline:** exit 0, silent.

| Mutation | Guards | Change | Result (exit 2 each) |
|---|---|---|---|
| H1 | every `.PHONY` target is listed | `## ` removed from `check-guix`'s line | `make help does not list .PHONY target 'check-guix'` |
| H2 | every listed target is in `.PHONY` | `check-guix-inside` removed from `.PHONY` | `make help lists 'check-guix-inside', which is not in .PHONY` |
| H3 | `.PHONY` on one line | `.PHONY` continued over two lines | `the .PHONY line ends in a backslash; keep it on one line`, then `'\'` not listed, and `check-guix` and `check-guix-inside` listed but not in `.PHONY` |
| H4 | the listing is what is checked, not the Makefile's text | `help`'s awk pattern narrowed to `/^[a-z]+:.*?## /` | `check-help`, `check-guix` and `check-guix-inside` not listed |
| H5 | a broken `make help` is reported as such | `## ` removed from `help`'s own line | `check-help: make help failed`, after make's `No rule to make target 'Show'` |

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

**Red run of the review's three fixes, against the self-test of `90c8734`:** each of N1, N2 and
N3 printed `check-guix: ALL CHECKS PASSED`. A fake 3.37.2 header passed, `petite` passed as
`CHEZ`, and so did a container with a network on a host with no default route.

**Baseline:** `check-guix: ALL CHECKS PASSED`, exit 0. `make check-guix` ran end to end in 1.4 s.

| Mutation | Guards | Change | Result |
|---|---|---|---|
| S1 | the container itself | `--container` dropped, so plain `guix shell` runs in the host's environment | exit 2: 47 `FAILED isolated-home: … is visible` lines, among them `.ssh`, `.gnupg` and `.gitconfig`; `interfaces`, listing the host's eleven; `loopback-only`, with 192.0.2.1 timing out (`exit 124`); and `no-git`, finding the host's git. `tool-path` passed; S12 fails it. |
| S2 | no network but loopback | `--network` added | exit 2: `interfaces` (the host's eleven) and `loopback-only` (`192.0.2.1 gave 'exit 124'`) |
| S3 | no FHS emulation | `--emulate-fhs` added | **survived:** exit 0. Guix's loader searches no FHS path, so the bare-name load is still refused, and the property this flag would break holds either way, as chez-curl found. L2 guards the flag. |
| S4 | no bare-name load | `export LD_LIBRARY_PATH="$GUIX_ENVIRONMENT/lib"` in the entry script | exit 2: `FAILED no-bare-name-load: Chez loaded libsqlite3.so.0 by bare name (LD_LIBRARY_PATH=/gnu/store/…-profile/lib)` |
| S5a | `CHEZ` is not a wrapper | `CHEZ` pointed at a script that `exec`s the profile's `scheme` | exit 2: `chez-variable`, `chez-is-elf` (`starts with '23212f62'`), `valgrind-instruments-chez` |
| S5b | the same | the same script, without `exec` | exit 2: `chez-variable`, `chez-is-elf`. `valgrind-instruments-chez` passed: Valgrind reported on the shell. |
| S6 | `CHEZ` is not a symlink named `chez` | `CHEZ` pointed at a `chez` symlink to the profile's `scheme` | exit 2: `chez-variable`; `header-matches-library` (`… says 'nothing'`) and `no-bare-name-load` (`exited 134`), since Chez aborted looking for `chez.boot` |
| S7 | the override is the profile's own file | `libsqlite3.so.0` copied out of the profile, and the override pointed at the copy | exit 2: `FAILED sqlite-override: CHEZ_SQLITE3_LIBRARY is '…/.mut/libsqlite3.so.0', expected …` |
| S8 | the compiler finds SQLite's header | `unset C_INCLUDE_PATH` in the entry script | exit 2: `sqlite-header` (`fatal error: sqlite3.h: No such file or directory`), and `header-matches-library` (`sqlite3.h says 'nothing'`). gcc still found `stdio.h`. |
| S9 | `CC` is the profile's gcc | `export CC=gcc` | exit 2: `FAILED cc-variable: CC is 'gcc', expected under …` |
| S10 | the Makefile's checks run inside | `## ` removed from `help`'s line | exit 2: `FAILED check-help` |
| S11 | nothing of HOME is visible | `"--expose=$HOME/.gitconfig"` added | exit 2: `FAILED isolated-home: …/.gitconfig is visible inside the container`, and nothing else |
| S12 | a login shell runs the profile's tools | a stub `gcc` put ahead of the profile on `PATH` | exit 2: `tool-path[-lc]` and `tool-path[-lic]` for `gcc`, each naming the stub |
| S13 | the probe's loopback half can fail | the probe pointed at `192.0.2.2`, a sabotage of the check itself | exit 2: `FAILED loopback-only: 127.0.0.1 gave '… Network is unreachable …'` |
| S14 | no git | `"git"` added to the manifest | exit 2: `FAILED no-git: git is at /gnu/store/…-profile/bin/git` |
| N1 | the header is the library's | a header saying 3.37.2 put first on `C_INCLUDE_PATH` | exit 2: `FAILED header-matches-library: sqlite3.h says '3037002', …/lib/libsqlite3.so.0 says '3053001'` |
| N2 | `CHEZ` is the profile's `scheme`, not another binary there | `CHEZ=$GUIX_ENVIRONMENT/bin/petite` | exit 2: `chez-variable` (`… resolves to '…/petite', not the profile's scheme`), and `header-matches-library`, since petite couldn't read the library's number |
| N3 | the only interface is `lo`, even with no route out | `--network` added, run in a user network namespace (`unshare -rn`) holding `lo` and a dummy `d0` at 10.9.9.1/24, with no default route | exit 2: `FAILED interfaces: /proc/net/dev lists 'lo d0 ', expected lo alone`, and nothing else. `loopback-only` passed, as the review showed it would. |

## Not covered

- **`GOAL`'s `MAKECMDGOALS` branch.** No target in this slice reaches `require-tools` through a
  prerequisite, so `GOAL`, `$@` and `MAKECMDGOALS` agree in every run. A mutation replacing
  `$(GOAL)` with `$@` would survive. Slice 2's `test` is the first case that can tell them apart,
  and its host-side tests (chez-curl's M2) come with it.
- **The `TIMEOUT` fallback** (chez-curl's T9). `TIMEOUT` arrives with `make test` in slice 2.
- **The probe's `LC_ALL=C`.** The review reported that under a German `LANG`, bash's messages
  were German and failed the probe's patterns. It wasn't reproduced here: `localedef` in the
  container failed for want of a character map. `LC_ALL=C` went in anyway, since it can only keep
  the messages in English. No mutation removes it, because nothing here can show a translated
  message.
- **`loopback-only` shows loopback is up by a refused connection, not an accepted one.** Nothing
  here listens, and nothing in chez-sqlite3 needs a loopback server. It probes one outside IPv4
  address, and no IPv6; `interfaces` is the check that bounds the network.
- **`isolated-home` reads only HOME's direct entries,** and allows those that lead to the
  repository. Sharing one of them whole (`--share=$HOME/src`) passes, and so does exposing any
  other entry beneath one (`--expose=$HOME/src/other-repo`). The second wasn't reproduced: it
  needs a run from under HOME. This is inherited from chez-curl.
- **`--emulate-fhs` inside the container** (S3). Only L2 catches it.
- **`T1 uses manifest.scm` is positional.** L9 failed it because the lines shifted. `T1 the whole
  command` is the check that pins the manifest's place.
