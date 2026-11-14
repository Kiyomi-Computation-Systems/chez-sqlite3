# Memory gate mutation log (M0 slice 3)

Evidence that `make check-memory-gate` fails when `make test-memory` or a plant loses the
property it claims ([harness plan](2026-11-13-harness-plan.md) §3 and §6,
[ADR-0005](decisions/0005-memory-gate.md)).

Every mutation was applied to a fresh copy of the working tree, made in the session scratchpad
without `.git`, `build/` or `.claude/`. The working tree was never edited. A driver applied each
mutation, refused any whose text didn't occur exactly once, ran `make check-memory-gate` through
the copy's own `scripts/guix-env`, six copies at a time, and kept each output whole. The counts
below are read from those outputs. Each mutation ran in its own copy, and `check-memory-gate` runs
every case in a private copy of its own, so the clean rerun after each one is the baseline itself.

The Makefile's `test-memory` is chez-curl's, less the shards and the Guix suppression, plus two
refusals: a `MEMORY_TIMEOUT` that isn't a positive whole number, and a `MEMORY_SUITES` from the
environment. `tests/check-memory-gate.sh` is chez-curl's too, adapted by a Sonnet agent: cases a,
b and e to m, then g timeout of its own. The review added g all, g environment and o's tripwire.

## How the red run was made

The core went in before its check: `test-memory` and the plants were written and run first
(`91b7383`), and the measurement before them ([research/memory-gate/](research/memory-gate/)). The
check's red run is against a copy whose `test-memory` ran each suite under Chez alone, with no
Valgrind, and printed a pass for each: **31 of the 33 cases there were then failed.** The two that
passed are the `a plain` cases, which run each plant without Valgrind and never call
`test-memory`. The agent ran it, and its output was checked here: 31 `FAILED` lines, and `ok` for
the two `a` cases.

The review's three cases were watched failing through mutations T26 to T28 and O1, below.

**Baseline, after the review's fixes:** `check-memory-gate: the memory gate failed, as it must,
and its refusals held, in all 36 cases`, exit 0, 1 min 32 s. Before them, 33 cases passed, and
the agent ran two at once, and one beside `make test-memory`: all passed. The review reran both,
and one beside `make test` too.

## Mutations of `test-memory`

Each failed `check-memory-gate` with exit 2, against the tree after the review's fixes. The cases
it failed:

| Mutation | Guards | Cases that failed |
|---|---|---|
| T1 | the refusal of any `VALGRIND_` variable | the three `h` cases for `VALGRIND_OPTS`, `VALGRIND_LIB` and `VALGRIND_LAUNCHER` |
| T2 | the refusal of a `.valgrindrc` | the two `h` cases for `$HOME/.valgrindrc` and `./.valgrindrc` |
| T3 | `--command-line-only=yes` | both `e`, the `h` mid-run rc file, both `i`, and four `k` (the options list changed) |
| T4 | the refusal of two suites with one name | `l names` |
| T5 | the `Command:` line rule | `j`, a Valgrind that runs another program |
| T6 | the options rule | both `i` and four `k`: added, dropped, changed and order |
| T7 | the first-program rule | both `j` cases with a `CHEZ` script |
| T8 | the error-summary rule | `j` exec'ing script, `j` execs away, `l forged` |
| T9 | the suppressions rule | both `i` |
| T10 | the awk's exit status | `m fails` and `m ok-fails` |
| T11 | an empty evidence line | `m silent` |
| T12 | each run removes its logs first | `l stale` |
| T13 | `timeout` wraps Valgrind and never sits between it and Chez | 19 cases: every `b`, `e`, `i`, `j` and `k`, the `h` mid-run rc file, and `l forged` and `l stale` |
| T14 | `--error-exitcode=9` | 12 cases: both plant `b` cases, both `e`, the `h` mid-run rc file, both `i`, five `k` |
| T15 | `--leak-check=full` | 10 cases: `b leak`, both `e`, the `h` mid-run rc file, both `i`, four `k` |
| T16 | `--errors-for-leak-kinds=definite` | the same 10 as T15 |
| T17 | a hang is named HUNG | `f hangs` |
| T18 | the refusal of no suites | `g none` |
| T19 | the refusal of `MEMORY_TIMEOUT=0` | `g timeout` |
| T20 | Valgrind's first error in a FAIL's report | `b overrun` |
| T21 | the suite's FAIL lines in a FAIL's report | `b fails` |
| T22 | the loop goes on after a failure | all three `b`, `g all` and `k undef` |
| T23 | the verdict | 24 cases: every case that runs a suite. The other 12 are both `a`, which run no `test-memory`, the refusals, which exit before the verdict (`g none`, `g timeout`, `g environment`, five `h`, `l names`), and `o` |
| T24 | the suppressions allowed are Valgrind's own `default.supp` alone | 16 cases: every clean program now fails |
| T25 | a pass needs Valgrind's log | both `e`, `g all` and `l stale` |
| T26 | with no `MEMORY_SUITES`, every suite runs | `g all` |
| T27 | a FAIL's tail is the suite's last 10 lines | `b fails` |
| T28 | the refusal of a `MEMORY_SUITES` from the environment | `g environment` |

**T26 and T27 survived the check as the agent wrote it:** run against the tree before the
review's fixes, each gave `in all 33 cases`, exit 0. They are the review's two reproductions, of
its major finding (nothing held the default to every suite) and of a minor one (`b fails` checked
one line where its header promised the whole block).

## Mutations of the plants and the tree

| Mutation | Guards | Cases that failed |
|---|---|---|
| P1 | the leak plant leaks: the block is freed | `b leak`, and the `h` mid-run rc file, which leaks through it |
| P2 | the overrun plant overruns: the write moves inside the block | `b overrun` |
| O1 | no workflow exists until slice 4 writes o: a `ci.yml` whose memory job has `continue-on-error: true` is planted | `o ci` |

The `i`, `j` and `k` cases that use the leak plant passed under P1, as they should. Each one fails
by a rule that fires whether or not the plant leaks: a suppressions file, the first program, or the
options. `b leak` is their control: it shows that the plant leaks when nothing hides it.

## Not mutated

- **The failure report's definite-loss and summary lines.** `b leak` asserts the loss record,
  which T20's awk prints with the first error; the loss and summary lines are printed by the same
  program and weren't mutated one by one.
- **`require-tools` at the head of each recipe.** Its own checks are slice 1's.

## Not covered

What the gate doesn't see is in ADR-0005's amendment and the Makefile: a child process, which
Valgrind doesn't follow; the programs `VALGRIND`, `TIMEOUT` and `CHEZ` name; a suite that writes
its own log; `make -i`; and two runs in one tree, which fail closed. The review reproduced the
first three. No case here holds them, because nothing in the gate does.
