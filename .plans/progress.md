# Progress ledger

Where chez-sqlite3 stands. Read it with [global-constraints.md](global-constraints.md) before
starting slice work. When a slice merges, update **Now** and add a close-out under **Close-outs**,
newest first.

## Now

- **M0 slice 0, the records,** merged as PR #1. ADR-0001 to ADR-0009 are all accepted.
- **M0 slice 1, the container,** merged as PR #2.
- **M0 slice 2, the test harness,** merged as PR #3.
- **M0 slice 3, the memory gate,** merged as PR #4.
- **M0 slice 4, CI,** merged as PR #5. CI on `main` passed in all three jobs.
- **M0's closing review** (harness plan §6) ran: Opus, read-only, over the five slices and the
  harness plan, on a snapshot of `main` at `37bb4c4`. No blocker, four major findings, every one
  reproduced here. `m0-review-fixes` fixes M0's share ([the log](m0-review-mutation-log.md)):
  - **`check-floors` refuses SQLite's floor in its numeric forms,** `3045001` and `3450100`,
    which held no `3.45.1` and passed (finding 1, ADR-0008).
  - **`check-test-fails` holds `check-ci`'s place in `make test`.** Removing it passed every check
    (finding 2, ADR-0005 and ADR-0007).
  - **`check-ci` holds the version reports,** which could be deleted unseen (finding 7,
    ADR-0006). `test-check-ci`'s top-level raise is guarded (9), and two rows of the helper suite
    assert in a fixed order and whole (10).
  - **The records say what holds and what doesn't:** `check-ci` holds against accident, not
    intent (5); a variable carried in `MAKEFLAGS` is not covered (6); "no suppression" was
    measured in the container only (8). Stale and conflicting records are fixed (11).
    `remove-temp-directory` stays exported: its suite tests the refusals that
    `call-with-temp-directory` can't reach, a relative path and `/`.
  - **Findings 3 and 4 are about what M1 builds:** where SQLite's two checks run, and how
    `check-ci` loosens for new jobs. ADR-0005's amendment records both, and M1's plan takes them.
  - **The fixes were reviewed too** (Opus, read-only): no blocker, two major findings, both
    reproduced and fixed. A third row of the helper suite still depended on argument order, and
    passed interpreted under a mutation it failed compiled. `check-floors`' boundary wasn't held
    against its complement: a range that took `=` for a letter passed every row. The records now
    say what still passes `check-floors`.
- **M1's plan comes next.** The maintainer settled four of its questions on 2026-11-13, and
  approved its slicing and the open surface; the plan records them.
- **Open:** brief D2 to D7. D2's answer and D7's measurement go in with M1's plan.

## Close-outs

### 2026-11-13 — M0 slice 4: CI (PR #5, `37bb4c4`)

- **Built:**
  - `.github/workflows/ci.yml`, with three jobs on Ubuntu 24.04: `main`, `memory` and
    `nothreads`;
  - `scripts/ci/`: `build-chez.sh`, `check-chez.sh`, `floor.sh`, `check-action-pins.sh` and
    `report-sqlite.sh`;
  - `packaging/debian-prereqs.txt`;
  - the floors' workflow rules;
  - `check-nothreads`, over every library under `src/`;
  - `check-memory-gate`'s case o;
  - after the review, `make check-ci`, which `make test` runs, holding the workflow to its shape.
- **Pins checked:** each action's commit and the Chez tarball's sha256, against GitHub.
- **Watched failing:** 53 mutations, every one failing its check, and three of them rerun against
  `check-ci` ([the log](ci-mutation-log.md)). Red runs: the workflow rules 173 passed and 110
  failed; `check-nothreads` 3 and 15; `check-ci` 1 and 125.
- **CI** ([research/ci-runner/](research/ci-runner/)):
  - **The first run passed** in all three jobs, building Chez from a cold cache. The runner's
    SQLite is 3.45.1, the floor itself, with a matching header and 58 compile options. On the real
    `--nothreads` Chez, both libraries were refused by name.
  - **The second run failed in `main`,** at the launcher's tests: T11b ran `make test` under
    `env -i`, which dropped `CHEZ`, and the runner has no `scheme` on `PATH`. It was reproduced in
    the container and fixed.
  - **The third run passed** on Chez restored from the cache and checked again, and so did `main`'s
    first run after the merge.
- **Reviewed** (Opus, read-only): no blocker, three major findings, all reproduced. Each was a hole
  a later edit to the workflow could pass through, not a fault in what ran:
  - Case o ran only in the job it guards, and nothing read the `nothreads` job or the pin step.
  - Case o read keys as text, so `"if": false`, `? if`, aliases, `needs:`, `defaults: shell:`,
    path filters and `GITHUB_ENV` writes passed it.
  - Dropping chez-curl's spelling rules reopened `? uses`, which hid an unpinned action from the
    pin check. The reason recorded for dropping them was wrong.

  Also fixed: the cache keys hash every script; a Chez restored from the cache is checked again;
  `MEMORY_TIMEOUT` is 600 s; an open double-quoted string fails `check-floors`; and there are new
  rows for an unreadable workflow file and for `check-chez.sh`.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | The workflow rules and the CI scripts' tests | Sonnet | about 159k | 37 | 5 min |
  | `check-nothreads` | Sonnet | about 86k | 16 | 3 min |
  | The adversarial review | Opus | about 266k | 92 | 20 min |
  | `check-ci` | Sonnet | about 182k | 25 | 14 min |

  The first two ran in parallel, on disjoint files.
- **Learned** (the first and third are in [traps.md](traps.md)):
  - A reason for dropping a copied rule is checked against every rule the copy keeps, before it
    goes into a brief. "They protected rules about keys, and we have none" was wrong: `uses` is a
    key. It is the third slice running where trimming a copy removed a protection.
  - A check must not live inside what it guards. Case o ran in the memory job, so deleting the job
    deleted its check; `check-ci` runs from `make test`.
  - `env -i` in a test drops the variables that name its tools. Every local run had `scheme` on
    `PATH`, and the runner didn't.
  - Reading an agent's code catches rule breaks its passing tests don't: `check-nothreads` first
    imported inside `map`, against AGENTS.md.

### 2026-11-13 — M0 slice 3: the memory gate (PR #4, `3c8cff9`)

- **Measured first** ([research/memory-gate/](research/memory-gate/)): Valgrind on Chez, opening and
  closing databases through bare FFI, loses nothing and suppresses nothing, so the gate passes no
  suppression. A connection left open is definitely lost when Chez holds its handle as an
  integer, even in a live variable, and passes when it is wrapped in an ftype pointer: an input to
  M1's design.
- **Built:** `make test-memory`, its evidence read from Valgrind's log alone; the two plants; and
  `make check-memory-gate`, 36 cases, each in a private copy of the tree.
- **Watched failing:** a red run, 31 of 33 cases against a `test-memory` with no Valgrind, then 31
  mutations, every one failing the check ([the log](memory-gate-mutation-log.md)).
- **Reviewed** (Opus, read-only): no blocker, two major findings, both reproduced and fixed.
  - Nothing held the default to every suite: chez-curl's case for it went with the shards.
  - Valgrind follows no child process, and the records didn't say so. ADR-0005 now lists what the
    gate doesn't cover, and M1 owns the children that reach native code. chez-curl issue #60
    files the same gap there.
- **CI:** none on this branch; slice 4's CI runs the gate.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Adapting `check-memory-gate.sh` | Sonnet | about 128k | 24 | 9 min |
  | The adversarial review | Opus | about 229k | 45 | 22 min |

- **Learned** ([traps.md](traps.md)):
  - A pattern written against a tool's padding misses a line padded otherwise: the first
    research table had no possibly-lost column.
  - Dropping chez-curl's shards dropped `n all` with them: slice 2's lesson again, that a dropped
    piece takes its protection with it.
  - Two counts in the mutation log were first written by eye, and both were wrong. They are now
    read from the outputs.

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
