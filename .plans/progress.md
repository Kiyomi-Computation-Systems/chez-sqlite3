# Progress ledger

Where chez-sqlite3 stands. Read it with [global-constraints.md](global-constraints.md) before
starting slice work. When a slice merges, update **Now** and add a close-out under **Close-outs**,
newest first.

## Now

- **M0 slice 0, the records,** merged as PR #1. ADR-0001 to ADR-0009 are all accepted.
- **M0 slice 1, the container,** merged as PR #2.
- **M0 slice 2, the test harness,** merged as PR #3.
- **M0 slice 3, the memory gate,** is built on `m0-slice-3-memory-gate`, waiting for its PR's
  review:
  - **Measured first** ([research/memory-gate/](research/memory-gate/)): Valgrind on Chez, opening
    and closing databases through bare FFI, loses nothing and suppresses nothing, so the gate
    passes no suppression. A forgotten handle is definitely lost when Chez holds it as an
    integer, and passes when it is wrapped in an ftype pointer: an input to M1's design.
  - **Built:** `make test-memory`, the two plants, and `make check-memory-gate`, 36 cases, each in
    a private copy of the tree. A Sonnet agent adapted the check from chez-curl's.
  - **Watched failing:** [the log](memory-gate-mutation-log.md).
  - **Reviewed** (Opus, read-only): no blocker, two major findings, both reproduced.
    - Nothing held `test-memory`'s default to every suite: chez-curl's case for it went with the
      shards. Now g all, and g environment refuses a `MEMORY_SUITES` from the environment.
    - Valgrind follows no child process, and the records didn't say so. ADR-0005 now lists what
      the gate doesn't cover, and the harness plan gives M1 the children that reach native code.
    - Also fixed: `b fails` compares its lines whole; o is a tripwire until slice 4; the research
      table lacked possibly-lost figures.
- **M0 slice 4, CI,** is built on `m0-slice-4-ci`, stacked on slice 3's branch:
  - **Built:** `.github/workflows/ci.yml` with three jobs, `main`, `memory` and `nothreads`, on
    Ubuntu 24.04; `scripts/ci/` (`build-chez.sh`, `floor.sh`, `check-action-pins.sh`,
    `report-sqlite.sh`); `packaging/debian-prereqs.txt`; the floors' workflow rules;
    `check-nothreads`, over every library under `src/`; and `check-memory-gate`'s case o.
  - **Pins checked:** each action's commit and the Chez tarball's sha256, against GitHub.
  - **Two Sonnet agents** built the workflow rules with the CI scripts' tests, and
    `check-nothreads`, in parallel.
  - **Watched failing:** [the log](ci-mutation-log.md). 39 mutations, every one failing its
    check.
  - **CI's first run passed** in all three jobs, building Chez from a cold cache. The runner's
    SQLite is 3.45.1, the floor itself, with a matching header
    ([research/ci-runner/](research/ci-runner/)). On the real `--nothreads` Chez, both libraries
    were refused by name.
  - **Reviewed** (Opus, read-only): no blocker, three major findings, all reproduced. Each was a
    hole a later edit to the workflow could pass through, not a fault in what ran:
    - Case o ran only in the job it guards, and nothing read the `nothreads` job or the pin step.
    - Case o read keys as text, so `"if": false`, `? if`, aliases, `needs:`, `defaults: shell:`,
      path filters and `GITHUB_ENV` writes passed it.
    - Dropping chez-curl's spelling rules reopened `? uses`, which hid an unpinned action from
      the pin check. The reason recorded for dropping them was wrong.
  - **Fixed:**
    - `make check-ci` (a Sonnet agent, test-first: 1 passed, 125 failed, then 128 passed) holds
      the workflow's whole shape, and `make test` runs it.
    - Case o runs it. `scripts/ci/check-chez.sh` re-checks a Chez restored from the cache.
    - The cache keys hash every script, and `MEMORY_TIMEOUT` is 600 s.
    - Smaller fixes: an open double-quoted string fails `check-floors`; new rows for an
      unreadable workflow file and for `check-chez.sh`; the launcher's tests run in `main`.
- **Open:** brief D2 to D7. D7 (the Mac's SQLite) is due in M1.

## Close-outs

### 2026-11-13 — M0 slice 2: the test harness (PR #3, `d23cab1`)

- **Built:**
  - chez-srfi pinned three ways, and `check-pins`;
  - the suite loop, `check-suites`, `check-test-fails`, `clean` and `check-clean`;
  - the verdict and the counters; `require-threaded`;
  - the floors, `check-floors` and README.org's Requirements;
  - `test-manifest` and the CHANGELOG.
- **Brief D1 settled:** a threaded Chez is required (ADR-0001's amendment).
- **Watched failing:** the floors were written test-first; the verdict, counters and manifest
  suites ran red against stubs or through their mutations, as
  [the log](test-harness-mutation-log.md) records. One agent mutation survived: an equivalent one.
- **Reviewed** (Opus, read-only): no blocker, two major findings, both reproduced and fixed.
  - The import scan read `.sls` only, and Chez loads a `.ss` beside it first.
  - The suites wrote stand-ins at fixed paths, so concurrent runs collided: 3 of 6 failed, and
    6 of 6 passed after the fix.
  - Also fixed: `TEST_TIMEOUT=0` ran with no limit, messages were checked by prefix only, and
    records overstated their evidence.
- **CI:** none yet.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | The floors and `test-require-threaded` | Sonnet | about 144k | 35 | 9 min |
  | `test-manifest` | Sonnet | about 64k | 10 | 2 min |
  | The verdict and counters suites | Sonnet | about 93k | 20 | 4 min |
  | The adversarial review | Opus | about 288k | 70 | 19 min |
  | The review's fixes to the test files | Sonnet | about 161k | 46 | 8 min |

  Two agents claimed the container couldn't run scratch copies; it can. One worked around a
  safety check to remove `.git` from its scratch copies; the repository's own `.git` was checked
  intact.
- **Learned:**
  - A rule added to the plan goes into every brief it binds. "Each helper comes with its first
    consumer" was in the plan and not in the briefs, and three agents wrote fixed-path stand-ins.
  - A harness that can run concurrently is tested concurrently.
  - Trimming a copy, list what each dropped piece protected and where that protection now lives.
    `check-seam`'s rule against library files that aren't `.sls` was dropped with nothing in its
    place.
  - Counts in the records come from the evidence. Reproductions were first written as three per
    agent; they were four, one and three.
  - A brief that wants a test written first asks for the red run's output in the hand-back. Two of
    the three agents wrote their code first, and said so.

### 2026-11-13 — M0 slice 1: the pinned Guix container (PR #2, `efe89b3`)

- **Measured first:** chez-curl's Guix pin gives Chez 10.4.0, SQLite 3.53.1 with `sqlite3.h`,
  gcc 16.2.0 and Valgrind 3.27.0, so the pin is kept ([research/guix-pin/](research/guix-pin/)).
  Two findings came with it:
  - Guix's `sqlite3` command carries its own SQLite, which had led the brief to record the
    command's options as the library's;
  - AGENTS.md's inherited evaluation-order rule was wrong on this Chez
    ([research/evaluation-order/](research/evaluation-order/)).
- **Built:**
  - `channels.scm` and `manifest.scm`;
  - the launcher, the entry script, the self-test and `require-tools`;
  - 63 host-side checks;
  - `help`, `check-help` and `check-guix`.
- **Watched failing:** the host-side tests ran red before any script existed, and the self-test
  ran red in a bare container. Then 56 mutations: every one fails by name except S3,
  `--emulate-fhs`, which L2 guards ([the log](guix-env-mutation-log.md)).
- **Reviewed** (Opus, read-only): no blocker.
  - **One major finding, reproduced and fixed:** the network check passed with a network on a
    host with no default route. The self-test now requires `lo` alone in `/proc/net/dev`.
  - **Also fixed:** `petite` passed as `CHEZ`; a header below the floor passed; and
    `GUIX_ENV_DRY_RUN=0` made `make check-guix` pass with no container.
  - **The evaluation-order account was corrected again.** The mixed orders came from the
    interpreter path for simple forms, not from compiled code.
  - **chez-curl shares four of the gaps.**
- **CI:** none yet.
- **Subagents:** one, Opus: the adversarial review, about 163k tokens, 53 tool calls, 13 min.
  Each finding was reproduced before it was fixed, except the locale one, which couldn't be.
- **Learned** ([traps.md](traps.md)):
  - Checks copied from a sibling bring its blind spots, and mutations derived from the same
    source can't find them.
  - Before rewriting a rule a measurement contradicts, find the mechanism. A table of results
    isn't an explanation.
  - A claim that something is absent needs its evidence recorded unabridged.
  - A reviewer's suggested fix is checked like the finding. `/sys/class/net` doesn't exist in
    the case it was meant to catch.

### 2026-11-13 — M0 slice 0: the records (PR #1, `d998b3e`)

- **Measured first:** on the host, Guix's Chez can't load the system's `libsqlite3.so.0` by its
  soname, and that library is 3.37.2, below the floor. Binding NaN returns `SQLITE_OK` and stores
  NULL. `utf8->string` replaces invalid bytes with U+FFFD without raising. What the Guix pin gives
  is slice 1's first measurement.
- **Built:**
  - the brief and the harness plan;
  - ADR-0001 to ADR-0009, with 0001 and 0002 accepted after the maintainer reviewed them;
  - `global-constraints.md` and this ledger;
  - AGENTS.md, cleaned of chez-curl's leftovers.
- **Checked:** every relative link in `.plans` resolves, and every record number cited exists.
  The check flagged one citation of a sibling's record that read as ours, and a read found three
  more.
- **Reviewed:** by the maintainer. M0's adversarial review comes at its end (harness plan §6).
- **CI:** none yet.
- **Subagents:** one, Sonnet: an inventory of chez-curl's harness, 171k tokens, 30 tool calls,
  4 min. Its claims were checked against the files before the harness plan used them, and they
  held: the Makefile's targets, `.gitignore`, the container's exports, the counters, the suite
  count, and `.github`.
- **Learned** ([traps.md](traps.md)):
  - A probe follows the test rules. The value probe's first run saw `step` before `bind`.
    Measuring why showed that AGENTS.md's inherited rule on evaluation order was wrong on this
    Chez; slice 1 corrects it.
  - A global replace hits the sentence that defines its marker.
  - Name the repository in every citation of a sibling's record.
