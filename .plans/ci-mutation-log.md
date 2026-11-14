# CI mutation log (M0 slice 4)

Evidence that the checks M0 slice 4 added fail through the property each one claims to guard
([harness plan](2026-11-13-harness-plan.md) §5 and §6, [ADR-0001](decisions/0001-bind-libsqlite3-directly.md),
[ADR-0005](decisions/0005-memory-gate.md), [ADR-0008](decisions/0008-floors-have-one-source.md)).

Every mutation was applied to a fresh copy of the working tree, made in the session scratchpad
without `.git`, `build/` or `.claude/`. The working tree was never edited. A driver applied each
mutation, refused any whose text didn't occur exactly once, ran the check that guards it through
the copy's own `scripts/guix-env`, six copies at a time, and kept each output whole. The counts
below are read from those outputs. Each mutation ran in its own copy, so the clean rerun after each
one is the baseline itself.

Two Sonnet agents built the floors' workflow rules, with the tests of `floor.sh` and
`check-action-pins.sh`, and `check-nothreads` with its suite, in parallel, on disjoint files. Their
red runs are summarised below, and each final run was repeated here. The rest of the slice was
built here, and the mutations were all run here.

## How the red runs were made

- **The workflow rules were written test-first.** The floors agent wrote the rows and fixtures
  before the rules: `test-check-floors` gave **173 passed, 110 failed**, every README row among
  them, since `check-floors` then took fewer arguments.
- **`check-nothreads` was written test-first.** Before the program existed, its suite gave **3
  passed, 15 failed**. The three passes were rows that run no program: `CHEZ` is set, the fixture
  trees are written, and the usage line for two arguments.
- **`check-nothreads` fails on a threaded Chez,** naming both libraries under `src/`. One row of
  its suite requires that, and it is the program's red run on every `make test`.
- **`floor.sh` and `check-action-pins.sh` came before their tests.** The scripts are chez-curl's,
  adapted; their rows passed at once. Their red runs are mutations F1 to F6 and A1 to A5.
- **Group o of `check-memory-gate` came after `ci.yml`.** Its red runs are mutations O1 to O9.

**Baselines:**
- `check-floors` on the tree: `README.org and .github/workflows (ci.yml) hold the floors in
  packaging/floors.sexp (chez 10.4.0, sqlite 3.45.1)`.
- `test-check-floors`: 283 passed. Two runs at once both passed 283, here.
- `test-check-nothreads`: 18 passed. Two runs at once both passed, as its agent reported.
- `check-memory-gate`: all 36 cases, `o` among them.

## Group o: CI's memory job (`check-memory-gate`)

Each mutation of `.github/workflows/ci.yml` failed `check-memory-gate` with exit 2, in case `o`
alone, with this problem:

| Mutation | Guards | Problem named |
|---|---|---|
| O1 | no job-level `continue-on-error:` | job memory has a job-level `continue-on-error:` |
| O2 | no `if:` on the `test-memory` step | job memory's "make test-memory" step has `if:` |
| O3 | no `continue-on-error:` on the `check-memory-gate` step | that step has `continue-on-error:` |
| O4 | the whole run line, with no arguments | three: the line names `MEMORY_SUITES`; it names the gate other than as a whole run line; 0 steps run "make test-memory" |
| O5 | `check-memory-gate` runs at all | 0 steps run "make check-memory-gate" |
| O6 | `check-memory-gate` runs before `test-memory` | job memory runs "make test-memory" with no "make check-memory-gate" step before it |
| O7 | no `MAKEFLAGS` in the job's `env:` | the line names `MAKEFLAGS` |
| O8 | no run block that names the gate | the line names the gate other than as one step's whole run line |
| O9 | no variable written through `GITHUB_ENV`, by its whole name | the line names `VALGRIND_OPTS`. A split name, `"MAKE""FLAGS"`, passed case o as first built; `check-ci` now refuses any line naming `GITHUB_ENV` |

## `check-nothreads` (`test-check-nothreads`)

Each failed the suite with exit 1:

| Mutation | Guards | Rows that failed |
|---|---|---|
| N1 | the refusal's who is `chez-sqlite3` | 1: wrong-who |
| N2 | the refusal's message starts with the marker | 1: wrong-message |
| N3 | the refusal is a syntax violation | 1: not-syntax |
| N4 | the walk goes into subdirectories | 11 |
| N5 | a link to a directory is named, not followed | 1: dir-symlink |
| N6 | an unreadable source is named | 2: unreadable among them |
| N7 | no library is a failure | 2: empty among them |
| N8 | a library that loads is named | 3: mixed among them |
| N9 | private libraries are checked too | 11 |
| N10 | a failure exits 1 | 12 |

## The workflow rules (`check-floors`, `test-check-floors`)

Each failed `test-check-floors` with exit 1. `check-floors` on the real tree still passed under
each, as it should: the real workflow breaks no rule.

| Mutation | Guards | Rows that failed |
|---|---|---|
| W1 | a floor's version text is found in a line | 23 |
| W2 | a backslash after a double quote is named | 9 |
| W3 | `ci.yml` must be directly in the directory | 3 |
| W4 | a directory with no file is named, once | 2 |
| W5 | every floor is held, not only the first | 13 |
| W6 | files are held in path order | 1 |
| W7 | the directory itself must not be a symbolic link | 1: workflows-self-link |
| W8 | subdirectories are held | 1: workflows-nested |
| W9 | an unreadable workflow file is named | 1: workflows-dir-link |

## `floor.sh` and `check-action-pins.sh` (`test-check-floors`)

| Mutation | Guards | Rows that failed |
|---|---|---|
| F1 | a `#` outside a comment is refused | 3 |
| F2 | two entries for a name are refused | 2 |
| F3 | a version with a leading zero is refused | 2 |
| F4 | only `chez` and `sqlite` are names | 2 |
| F5 | the file is one list of entries | 7 |
| F6 | comments are dropped before reading | 2 |
| A1 | a full 40-digit commit | 1: a short commit |
| A2 | nothing checked is a failure | 2 |
| A3 | a quoted key is a key | 3 |
| A4 | a tag in a comment after the commit | 3 |
| A5 | a directory with no file is a failure | 1 |

## After the review: `check-ci`, `check-chez.sh` and two rules

The slice's review found the workflow's shape held by nothing outside the memory job, and keys
read as text (ADR-0005's slice 4 amendment). `make check-ci` now holds the shape; a Sonnet agent
wrote it test-first: **1 passed, 125 failed** before the script existed, then 128 passed, and two
runs at once both passed 128 here. Case o now runs it. O1, O7 and O9 were rerun against it: each
still fails case o, now naming `check-ci`'s problem (O1: job memory has the key
`continue-on-error`; O7: the key `env`; O9: the line names `GITHUB_ENV`).

Each mutation below failed its suite with exit 1:

| Mutation | Guards | Rows that failed |
|---|---|---|
| C1 | `ci.yml` alone in the workflow directory | 4: a second workflow among them |
| C2 | an explicit key, `?`, is refused | 2 |
| C3 | an anchor or alias where a key goes is refused | 3 |
| C4 | a quoted key is refused | 2 |
| C5 | no line names `GITHUB_ENV` | 2: `"MAKE""FLAGS"` written to it among them |
| C6 | a job holds only its four keys | 12 |
| C7 | the `nothreads` job runs its build, `check-chez.sh` and `check-nothreads` | 5 |
| C8 | the trigger, permission and concurrency blocks, line for line | 3: a path filter among them |
| C9 | a block scalar ends at the first line no deeper than its key | 121: the unedited file among them |
| K1 | `check-chez.sh` compares the answer whole | 2 |
| K2 | `check-chez.sh --nothreads` asks for a Chez without threads | 1 |
| K3 | `check-chez.sh` needs `PREFIX/bin/scheme` | 1 |
| W10 | a double-quoted string left open fails `check-floors` | 3 |
| A6 | a workflow file `check-action-pins.sh` cannot read is named | 1 |

K1 to K3, W10 and A6 failed `test-check-floors`; C1 to C9 failed `test-check-ci`.

## Not mutated

- **`scripts/ci/build-chez.sh`.** It checks its own result: the tarball's sha256 before
  unpacking, and the installed Chez's version and `(threaded?)` after. It runs only in CI, where
  its first run is its test. The pinned sum was checked against the digest GitHub's releases API
  lists for the asset. *(M1 slice 5: it now pins by role, and chez-curl's tree rows for it are
  back in `test-check-floors`; see [slice 5's log](m1-slice-5-mutation-log.md).)*
- **`scripts/ci/report-sqlite.sh`.** It reports and checks nothing.
- **The workflow's jobs themselves.** Their first run on CI was green in all three
  ([research/ci-runner/](research/ci-runner/)). No job has been seen to fail there: each job's
  checks were watched failing locally, and `check-ci` holds the jobs to the shape that runs
  them.
