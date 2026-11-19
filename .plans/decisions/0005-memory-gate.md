# ADR-0005: The memory gate is Valgrind on Linux, our counters, and SQLite's own checks

- **Status:** Accepted (the maintainer, 2026-11-13). The two SQLite checks are built in M1.
  Amended 2026-11-13: what M0 slice 3 measured and built
  ([amendment](#amendment-2026-11-13-what-m0-slice-3-measured-and-built)), CI's memory job
  (M0 slice 4, [amendment](#amendment-2026-11-13-cis-memory-job-m0-slice-4)), and M0's closing
  review ([amendment](#amendment-2026-11-13-m0s-closing-review)). Amended 2026-11-14: a library
  that keeps no memory count (M1's plan,
  [amendment](#amendment-2026-11-14-a-library-that-keeps-no-memory-count-m1s-plan)), and the first
  suite that loads libsqlite3 (M1 slice 2,
  [amendment](#amendment-2026-11-14-the-first-suite-that-loads-libsqlite3-m1-slice-2)), and the
  children under the gate (M1 slice 3,
  [amendment](#amendment-2026-11-14-children-under-the-gate-m1-slice-3)), and SQLite's memory check
  (M1 slice 4, [amendment](#amendment-2026-11-14-sqlites-memory-check-m1-slice-4)). Amended 2026-11-14:
  statements, and the decoy's cost (M2's plan, [amendment](#amendment-2026-11-14-statements-and-the-decoys-cost-m2s-plan)).
  Amended 2026-11-14, and accepted by the maintainer that day: a checkout path holding whitespace
  ([amendment](#amendment-2026-11-14-a-checkout-path-holding-whitespace-owed-to-m1s-closing-review)),
  and the `floor` and `current` lanes (M1 slice 5,
  [amendment](#amendment-2026-11-14-the-floor-and-current-lanes-m1-slice-5)). Amended 2026-11-14,
  and accepted by the maintainer that day: the CI scripts' execute bits (M1's closing review,
  [amendment](#amendment-2026-11-14-the-ci-scripts-execute-bits-m1s-closing-review)). Amended
  2026-11-15, and accepted by the maintainer that day: the decoy's cost, measured (M2 slice 2,
  [amendment](#amendment-2026-11-15-the-decoys-cost-measured-m2-slice-2)). Amended 2026-11-15
  by the maintainer's choice, "Split in #19, rest after": one run was one sample, and the suite
  is split, with a check that holds the rule (M2's closing review,
  [amendment](#amendment-2026-11-15-the-split-and-its-check-m2s-closing-review)). Amended
  2026-11-15, and accepted by the maintainer that day: M3's entry points and suites (M3's plan,
  [amendment](#amendment-2026-11-15-m3s-entry-points-and-suites-m3s-plan)). Amended 2026-11-16
  by the maintainer's choice, "Split into thirds now", and accepted that day ("Accept all"): the
  halves split in three (M3 slice 2,
  [amendment](#amendment-2026-11-16-the-halves-split-in-three-m3-slice-2)). Amended 2026-11-16
  by the maintainer's choice, "Shard in slice 6": the memory job split in two (M3 slice 6,
  [amendment](#amendment-2026-11-16-the-memory-job-split-in-two-m3-slice-6)), and accepted on
  2026-11-17 ("Accept all"). Amended 2026-11-17 in M3's closing review, and accepted by the maintainer that day: the open risk met and
  closed, the watchdog's handshake, and the gates no row read
  ([amendment](#amendment-2026-11-17-the-open-risk-met-and-the-gates-no-row-read-m3s-closing-review)).
  Amended 2026-11-17 in M4's plan, and accepted by the maintainer that day: M4's entry points, suites and extension
  ([amendment](#amendment-2026-11-17-m4s-entry-points-suites-and-extension-m4s-plan)).
  Amended 2026-11-17 in M4's close fix, and accepted by the maintainer that day ("Accept all"): decision 5's statements check after a refused close
  ([amendment](#amendment-2026-11-17-the-statements-check-after-a-refused-close-m4s-close-fix)).
  Amended 2026-11-18 in M4's closing review, and accepted by the maintainer on 2026-11-19 ("Accept all"): the no-load lane, the loading suites split,
  and the sweeps' low passes
  ([amendment](#amendment-2026-11-18-the-no-load-lane-the-loading-suites-split-and-the-sweeps-low-passes-m4s-closing-review)).
- **Date:** 2026-11-13
- **Scope:** every suite, and CI's `memory` job, two since M3 slice 6: `memory-1` and `memory-2`
- **Settles:** brief §2.4
- **Related:** chez-curl ADR-0014, whose Valgrind gate this copies ·
  [the harness plan](../2026-11-13-harness-plan.md) §3 ·
  [ADR-0007](0007-test-harness-and-scheme-dependencies.md) (`suite-exit-status`)

## Context

- **Thunderchez's worst defects were leaks that pass every functional test** (the assessment): an
  out-parameter block allocated per open and per prepare and never freed; a handle left open after
  a failed open; a close loop that stopped early and never reached `sqlite3_close`.
- **Valgrind can't see Chez's heap.** chez-curl measured that a dropped `foreign-alloc` block,
  still wrapped in an ftype pointer, passes clean, and so does an overrun into a bytevector
  (chez-curl ADR-0014, amended 2026-10-16). A handle Scheme forgot is still "reachable" to Valgrind.
- **SQLite counts for itself.** `sqlite3_memory_used` reports what SQLite holds, unless the build
  turns memory statistics off; neither build measured on the host does. `sqlite3_next_stmt` walks
  a connection's open statements.

## Decision

1. **The gate has four parts,** because each sees what the others miss:

   | Part | Sees | Blind to |
   |---|---|---|
   | Valgrind | overruns and lost blocks in C, SQLite's included | memory Chez's heap still points to |
   | our counters | a block, connection or statement Scheme didn't release | anything inside C |
   | `sqlite3_next_stmt(db, NULL)` | a statement left open on a connection | memory |
   | `sqlite3_memory_used` | SQLite memory still held after every connection closes | our own allocations |

2. **Valgrind runs each suite as chez-curl's gate does:**
   `timeout --foreground $MEMORY_TIMEOUT valgrind -v --command-line-only=yes --log-file=… --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $CHEZ --libdirs … --program <suite>`.
   - **Placement:** `timeout` wraps Valgrind and never sits between it and Chez. `CHEZ` is the real
     binary, never a wrapper or a symlink.
   - **Evidence comes from Valgrind's log alone,** never from the suite's output, which could forge
     it. The log must exist fresh. Its command line and options block must be exactly the gate's.
     The first program it read symbols from must be `$CHEZ`'s file. It must report 0 errors from
     0 contexts, and read no suppression file the gate didn't pass.
   - **Refusals before any suite runs:** any `VALGRIND_*` variable, a `.valgrindrc` in `$HOME` or
     the working directory, and two suites with one name.
   - **No suppressions.** One comes in only with a recorded run that needs it, and only in the
     environment that needs it. `--undef-value-errors=no` stays off on the same terms.
3. **`make check-memory-gate` proves the gate can fail.** It plants a 777-byte leak and a one-byte
   overrun of a 23-byte block, sizes nothing else produces, and each must fail with Valgrind's
   marker. It also plants a broken copy of each evidence rule and each refusal. CI runs it before
   `make test-memory`.
4. **The counters live in `(chez-sqlite3 private counters)`,** with three kinds: `block` (our
   `foreign-alloc`), `connection` and `statement`. The counts sit behind one mutex, taken inside
   `critical-section`. There is no reset, and a count below zero raises. `suite-exit-status` fails
   a suite whose counts aren't zero, naming each count. A child process that reaches native code
   prints its counts, and its parent asserts that they are zero.
5. **SQLite's checks join in M1,** once there is a loaded library to ask.
   - **Statements:** before each close, `sqlite3_next_stmt` must find no statement the connection
     doesn't track. Closing finalizes the tracked ones (brief §3e).
   - **Memory:** after every connection closes, `sqlite3_memory_used` must return to a baseline.
     M1 measures first whether it returns to its value before the first open, or whether SQLite
     keeps something global after the first cycle.
6. **CI's `memory` job runs on every event.** Neither the job nor its steps carry `if:` or
   `continue-on-error:`, and `check-memory-gate` checks that.

### Rejected

- **Valgrind alone.** It can't see a handle Chez's heap still holds.
- **Counters alone.** They can't see inside C.
- **A macOS gate.** There is no macOS CI (AGENTS.md). Apple's tools stay a local supplement.

## Consequences

- **Every suite that opens something closes it,** or its exit status fails.
- **A test that raises a count on purpose lowers it again,** under `dynamic-wind`.
- **The `memory` job will get slow.** It is split into shards when it does, as chez-curl's was.

## Amendment, 2026-11-13: what M0 slice 3 measured and built

Measured in the pinned container before the gate was built
([research/memory-gate/](../research/memory-gate/)), then built and reviewed.

- **Decision 2's "no suppressions" holds with nothing to add.** Loading libsqlite3, a WAL file
  database, `:memory:`, and an open that fails and is closed lose nothing under the gate's
  command, and Valgrind suppressed nothing, not even from its own `default.supp`. So
  `test-memory` passes no suppression file in any environment, and allows exactly Valgrind's own
  `default.supp`.
- **The context's "a handle Scheme forgot is still reachable" holds only for some shapes.** A
  `:memory:` connection never closed, its handle kept as an integer, is definitely lost to
  Valgrind (840 bytes, and 75,168 indirectly), even while a live variable holds the integer: a
  fixnum holds an address shifted, so Valgrind finds no pointer to it. Wrapped in an ftype
  pointer that is then dropped, what the handle holds is still reachable or possibly lost, which
  the gate counts neither of, and the run passes. So Valgrind sees a connection left open only if
  M1 holds handles as integers. Decision 4's counters see it either way, and remain the gate for
  what Scheme forgets.
- **`MEMORY_TIMEOUT` must be a positive whole number,** as `TEST_TIMEOUT` must: GNU `timeout`
  reads 0 as no limit.
- **Built:** `make test-memory`, the two plants, and `make check-memory-gate`, with chez-curl's
  cases a, b and e to m, and four of its own:
  - **g timeout:** a `MEMORY_TIMEOUT` of 0, of nothing, or not a number is refused.
  - **g all:** with no `MEMORY_SUITES`, every suite runs, in order. chez-curl's n held this
    beside its shards; the review found it dropped with them.
  - **g environment:** a `MEMORY_SUITES` from the environment is refused, since one left
    exported would narrow every run unseen. It is given on make's command line.
  - **o:** a tripwire. It fails while `.github/workflows` exists, until M0 slice 4 writes the case
    that holds CI's memory job to decisions 3 and 6.

  Every case runs in a private copy of the tree, so two runs, or one beside `make test-memory`,
  share nothing.
- **Not covered,** as in chez-curl's gate:
  - **A child process a suite starts runs outside Valgrind,** which follows none. Decision 4 has
    children that reach native code from M1; each must run under the gate itself, with its own
    log, or the gate must follow children and read every process's log (harness plan, section 4).
  - **The gate trusts the programs `VALGRIND`, `TIMEOUT` and `CHEZ` name.** A compiled `CHEZ`
    that runs Chez as a child passes the leak plant: the first program Valgrind read is the file
    `CHEZ` names, as decision 2 requires, and Chez runs outside it.
  - **The evidence holds against accident, not against a suite that means harm.** A suite can
    write its own Valgrind log, at a path it can guess.
  - **`make -i`,** on the command line or in `MAKEFLAGS`, ignores a failing recipe, this one's as
    any other's.
  - **Two runs in one tree** remove each other's logs and fail, naming the wrong reason. They fail
    closed.

## Amendment, 2026-11-13: CI's memory job (M0 slice 4)

- **Decision 6 is narrowed to what it protects.** "Neither the job nor its steps carry `if:`"
  can't hold as written: the job restores Chez from a cache, and its build and save steps run only
  on a miss, through `if:`, as chez-curl's do. The rule is now that neither the job nor its two
  gate steps, `make check-memory-gate` and `make test-memory`, carry `if:` or
  `continue-on-error:`.
- **`make check-ci` holds it, and the rest of the workflow with it** (`tests/check-ci.sh`).
  `make test` runs it, so CI's `main` job and the container's self-test do too, and
  `check-memory-gate`'s case o requires it to pass. It holds `.github/workflows/ci.yml` to the one
  shape it reads:
  - the triggers, the permissions and the concurrency group, line for line, with no filters;
  - the three jobs and only these keys in each, so no job-level `if:`, `needs:`,
    `continue-on-error:`, `strategy:`, `container:`, `defaults:` or `env:`;
  - only known keys in each step, so no `shell:` and no `working-directory:`;
  - `if:` only as the cache's own test, on the build and save steps;
  - each job's checks, each as a step's whole run line, in order. Among them are the memory
    job's `make check-memory-gate` then `make test-memory`, the `nothreads` job's
    `make check-nothreads`, and the pin check as `main`'s second step;
  - no line naming `GITHUB_ENV`, `GITHUB_PATH`, or a variable that would steer a check:
    `MAKEFLAGS`, the `VALGRIND` names, `MEMORY_SUITES`, `MEMORY_TIMEOUT`, `CHEZ_SQLITE3_LIBRARY`
    and the like;
  - no key spelled so that a text check would miss it: quoted, explicit (`?`), an anchor or
    alias, a space before its colon, a flow mapping, a tab, or a character beyond ASCII.
- **Why a shape, and why in `make test`.** As first built, case o was an awk of its own that ran
  only in the memory job, and read keys as text. The slice's review showed what that let
  through:
  - deleting the memory job, which deleted case o with it;
  - deleting the `nothreads` job or the pin step, which nothing read;
  - `"if": false`, `? if`, an alias key, `needs:` on a skipped job, `defaults: run: shell: true
    {0}`, a path filter on `pull_request`, and a variable written through `GITHUB_ENV` under a
    split name. Each passed case o.
- **What no check here can hold:** a change that deletes the workflow, or `main` and `memory`
  with it, runs no check at all. GitHub's branch protection, requiring these jobs, is the
  maintainer's lever for that.
- **`MEMORY_TIMEOUT` is now 600 s.** At 3600 s, a hang would have outlived the job's 60-minute
  limit, ending as a job timeout with no HUNG line.
- **The job runs on every event,** on Ubuntu 24.04, against Chez built at its floor from the
  release tarball. Outside the container, as inside it, the gate passes no suppression.

## Amendment, 2026-11-13: M0's closing review

- **`check-ci` holds the workflow against accident, not intent.** The review wrote `MAKEFLAGS=-i`
  to `GITHUB_ENV` through a name split across shell variables (`v=GITHUB_; … ${v}ENV`), and
  `check-ci` and every suite passed. Under `-i`, `make test` exits 0 with suites failing. No text
  check closes that, since a step can compute any name. The slice 4 amendment's "a variable
  written through `GITHUB_ENV` under a split name" is stopped only in the spelling the review first
  used: any line naming `GITHUB_ENV`. As with a hostile suite's log, `check-ci` holds against a
  mistaken edit, and review and branch protection hold against a deliberate one.
- **That `make test` runs `check-ci` is now held.** Removing the prerequisite passed every check,
  and the two workflow edits it let through passed too: dropping `check-ci` from `main`'s make
  line, and deleting the `memory` job, case o with it. `check-test-fails`' case `ci` plants a
  job-level `continue-on-error` and requires `make test` to fail on `check-ci`'s lines, whole
  ([the log](../m0-review-mutation-log.md)).
- **Not covered, added: a variable carried in an exported `MAKEFLAGS`.**
  `MAKEFLAGS="MEMORY_SUITES=tests/test-counters.sps" make test-memory` ran one suite and said
  nothing. GNU Make gives such a variable the origin `command line`, the same as a real
  command-line assignment: measured with 4.3 on the host, which is Ubuntu 24.04's too, and 4.4.1 in
  the container, so the refusal can't tell them apart. It matters locally only: the
  workflow bans `MAKEFLAGS`.
- **"No suppression" is measured in the container only:** Valgrind 3.27 and SQLite 3.53.1
  ([research/memory-gate/](../research/memory-gate/)). CI's memory job, with Valgrind 3.22 and
  Ubuntu's 3.45.1, has not yet run a suite that loads libsqlite3. So the slice 4 amendment's "as
  inside it, the gate passes no suppression" is policy there until M1's first such suite runs.
- **`check-ci` is loosened per job, never for the whole file.** M1's `floor` and `current` jobs
  need what `check-ci` refuses today: `CHEZ_SQLITE3_LIBRARY`, `C_INCLUDE_PATH`, more jobs, cache
  steps. `main` is the one job that tests discovery, since the container always sets the
  override, so `CHEZ_SQLITE3_LIBRARY` stays banned there. And `CC`, `C_INCLUDE_PATH`, `CPATH`,
  `LD_LIBRARY_PATH` and `LD_PRELOAD` join the banned names before any job gains an `env:` key
  beyond `CHEZ`: each can steer `test-constants` or the load.
- **Where SQLite's two checks run.** Decision 5 puts `sqlite3_next_stmt` before each close, where
  a connection is still open. The harness plan had put both checks in `suite-exit-status`, whose
  library never loads libsqlite3, so that `check-suites`, `check-test-fails`' copy and the
  launcher's `env -i` runs can import it. The plan now follows decision 5. `sqlite3_memory_used`
  is asked only in a process that loaded the library, as M1 decides.

## Amendment, 2026-11-14: a library that keeps no memory count (M1's plan)

- **Apple's SQLite keeps no memory count.** It is built with `DEFAULT_MEMSTATUS=0`, and
  `sqlite3_memory_used` answered 0 before an open, while a database was open, and after the close
  ([research/mac-d7/](../research/mac-d7/)). A check that the count returns to its baseline would
  pass there without testing anything.
- **So the memory check has a positive control, and the control is the check's own** (proposed
  in M1 slice 0; accepted by the maintainer, 2026-11-14). At a suite's exit, in a process that loaded
  libsqlite3, the check opens a `:memory:` connection of its own, reads the count while it is
  open, and closes it. If the count rose, the library counts, and the check runs: the count must
  be back at its baseline. If it didn't rise, the check is unavailable. A suite that opens
  nothing still runs the control, so on Linux the check is never unavailable for want of an
  open. The control is read, not the compile option, which `sqlite3_config` could override at
  runtime.
- **A suite that finds the check unavailable reports it, by name, and passes on its other checks**
  (the maintainer, 2026-11-14). Its verdict line names the check as unavailable, so the result is
  never a silent pass. On the Mac, the hand runs reach Apple's library through discovery and are
  read that way.
- **Which libraries count.** Guix's 3.53.1 was seen to: 0, then 61,360 while open, then 0
  ([control-guix.txt](../research/mac-d7/control-guix.txt)). So was Homebrew's 3.54.1: 0, 66,848,
  0. Ubuntu's 3.45.1, CI's `main` and `memory` library, is only inferred to: `DEFAULT_MEMSTATUS`
  isn't among its 58 options ([research/ci-runner/](../research/ci-runner/)), and it has never
  opened a connection under a suite. The `floor` and `current` lanes of slice 5 must not set
  `DEFAULT_MEMSTATUS=0`, and their assertion of the options they built checks that.
- **Where it runs:** only in a process that loaded libsqlite3 (the closing review's amendment).
  Slice 4 of M1 builds it. On 3.53.1 and 3.54.1 the count came back to its value before the first
  open after one open, query and close (above). Whether 3.45.1's does, or needs a baseline taken
  after the first cycle (decision 5), is measured on CI's runner first.

## Amendment, 2026-11-14: the first suite that loads libsqlite3 (M1 slice 2)

- **`test-native` loads libsqlite3 under the gate,** opening and closing `:memory:` and a failed
  open through the raw bindings. In the container (Valgrind 3.27, SQLite 3.53.1): 0 errors,
  nothing definitely, indirectly or possibly lost, 15,256 bytes in 11 blocks still reachable, and
  no suppression. Its first run in CI's `memory` job is the first measurement with Valgrind 3.22
  and Ubuntu's 3.45.1 (the closing review's amendment).
- **Its children run outside Valgrind:** the C oracle, which loads the same libsqlite3, and gcc,
  sh and mkfifo. So does `test-blocks`' dead-address child, which reaches malloc and free only.
  Slice 3 decides how the gate covers children.
- **Measured on CI** (PR #9's run, 2026-11-14): `test-native` passed in the `memory` job, Valgrind
  3.22 with Ubuntu's 3.45.1, with no suppression. The closing review's unmeasured case is now
  measured, clean.

## Amendment, 2026-11-14: children under the gate (M1 slice 3)

- **Each child that reaches native code runs under the gate's own Valgrind, with its own log**
  (the closing review's amendment, its first choice). `make test-memory` exports
  `CHEZ_SQLITE3_GATE_CHILD` to each suite: `$(VALGRIND)` and the gate's own options, with
  `--log-file=$(CURDIR)/build/memory/<suite>.children/%p.valgrind`, absolute so a child run from
  another directory still writes it. A suite runs each such child through
  `(chez-sqlite3-testing)`'s `gated-command`: the refusal probes, preflight, `test-blocks`'
  dead-address child and `test-native`'s C oracle. Before each suite its old child logs are
  removed; after it, every child log is held to the parent's rules:
  - the options are exactly the child's;
  - `Command:` begins with `$(CHEZ) `, or names the program `libsqlite3-oracle`, and the first
    program Valgrind read is that file, both paths resolved with `readlink -f`;
  - 0 errors from 0 contexts;
  - no suppression file but Valgrind's own `default.supp`.

  A child log that fails fails its suite, naming the log.
- **Why not `--trace-children=yes`** (measured in the container, Valgrind 3.27):
  - Chez's `system` runs a static bash. Traced, it reports about 300 uninitialised-value errors and
    exits 9, so every child, clean or leaking, answers 9.
  - `mktemp` loses 44 bytes definitely, and gcc reports 41 errors.
  - Skipping the shell with `--trace-children-skip` untraces everything the shell starts, so no
    child is seen. Tracing with a suppression for the static bash worked, but needs a suppression
    and a skip list kept by hand, against decision 2.
- **What it costs:** about 4.1 s per Chez child and 0.25 s per oracle run. Measured on the
  review's fixed tree, in the container and on CI (run 43609564593):

  | What | Container | CI |
  |---|---|---|
  | `test-library-loading`, plain | 6.7 s | 6 s |
  | `test-library-loading`, under the gate | 230 s, 55 child logs | 308 s |
  | `make test-memory` | 404 s | 556 s |
  | `make check-memory-gate` | 221 s | 262 s |
  | the `memory` job, warm | | 14 min 3 s of 60 |

  `test-library-loading` uses half of `MEMORY_TIMEOUT`'s 600 s on CI: room for about 50 more gated
  children. Decision 5's consequence, shards, is the remedy when it grows.
- **`check-memory-gate` gains cases p and q** (52 cases after the review's fixes): a child's planted leak (777 bytes) and
  overrun (23 bytes) fail the gate; options dropped for children, another program, the oracle
  leaking, a forged log and a stale one each fail; and a child run without `gated-command`
  passes, which is the gap that remains. After the review: a child that forks passes clean and
  still fails on a planted leak, a child run from another directory is found, and the oracle run
  through a symlinked directory passes.
- **Not covered:**
  - **A child started without `gated-command`** runs outside Valgrind, unseen. So does one started
    through `gated-command` with a `getenv` that hides `CHEZ_SQLITE3_GATE_CHILD`, since the helper
    takes `getenv` as an argument.
  - **Which wrapped children say they ran under memcheck.** A child reads `/proc/self/maps` for
    `vgpreload_memcheck` and prints the answer. As first built, 41 of `test-library-loading`'s 53
    children asserted it. The preflight runs, the `message-of` probes, the ambient probe, the
    oracle and `test-blocks`' child didn't, and each passed ungated (slice 3's review). Now every
    wrapped child asserts it. Preflight prints no such line, since `make build` runs it, so its
    caller requires the one new log in the child-log directory to name its whole command.
  - **`check-ci` doesn't read `scripts/ci/*.sh`.** A script that runs before the install check
    and writes `GITHUB_ENV` would let the check pass through an override. Review holds that.
- **A gated child that forks** got a second log from Valgrind, with a `Command:` line and no
  summary, and failed the gate though clean (slice 3's review). The gate passes
  `--child-silent-after-fork=yes`, parent and child alike.

## Amendment, 2026-11-14: SQLite's memory check (M1 slice 4)

- **Decision 5's memory check is built, where the M1 plan leaned.** Native's last step reads
  `sqlite3_memory_used` right after its bindings, so after `sqlite3_initialize` with no SQLite
  call between, and registers the check with the counters, which load nothing. A load refused
  earlier registers nothing, so a suite that never loaded libsqlite3 has no check to run.
  `suite-exit-status` runs every registered check before it reads the counts, and names each
  outcome on its own line:

  ```
  suite-exit-status: the sqlite3_memory_used check passed: the count is back at its baseline, 0 bytes, after the control's :memory: open and close
  suite-exit-status: exit 1 (the sqlite3_memory_used check failed): the count is 61360 bytes after the control's :memory: open and close, not its baseline, 0 bytes: SQLite still holds memory that a suite's end must have freed
  suite-exit-status: the sqlite3_memory_used check is unavailable: the count was 0 bytes before the control's :memory: open and 0 while it was open, so this libsqlite3 keeps no memory count
  ```
- **The control** is a raw, uncounted `:memory:` open and close, the count read before, while
  open, and after. No rise while open is unavailable; otherwise the count after must equal the
  baseline exactly. A failed control open or close fails the check.
- **No first-cycle baseline is needed.** On Guix's 3.53.1 and on 3.45.1 built from its
  amalgamation, the count came back to its value after `sqlite3_initialize`, 0, after every open
  and close measured: `:memory:` (61,360 and 57,232 bytes while open), a WAL file with a blob
  (154,472 and 150,272), and a failed open (1,376 and 1,304). A 3.45.1 build with
  `DEFAULT_MEMSTATUS=0` never moved, and every suite named the check unavailable and passed. On
  CI, Ubuntu's 3.45.1 passed it in every suite that loads libsqlite3: "the count is back at its
  baseline, 0 bytes" (PR #11's run, 2026-11-14).
- **The testing library never loads libsqlite3, and a check holds it:** `test-never-loads` holds
  `(chez-sqlite3-testing)`'s and the counters' imports to exact allowlists, works out which
  libraries load libsqlite3 from `src/`'s imports, and checks what the testing library can reach.
  It passed before the registration landed. A route through a name the testing library already
  imports, `system` say, is held by review.
- **The leaks plant goes through `open-database`:** `check-test-fails`' leaks case fails on the
  counters (`connection 1`) and the memory check; `check-memory-gate`'s connection plant fails
  under Valgrind, its loss record's stack through libsqlite3. A 3.45.1 build with symbols shows
  `sqlite3_open_v2` there; Guix's stripped library shows `???` frames inside `libsqlite3.so`, and
  the gate accepts either.
- **On the maintainer's Mac** (2026-11-14), every suite that loads Apple's 3.51.0 named the check
  unavailable and passed on its other checks, as designed; with Homebrew's 3.54.1 through the
  override, the check passed, the count back at 0 after 66,848 bytes while open.


## Amendment, 2026-11-14: a checkout path holding whitespace (owed to M1's closing review)

- **Found at slice 3's review fixes:** `CHEZ_SQLITE3_GATE_CHILD` holds each child's absolute
  `--log-file`, under `$(CURDIR)`. Its two readers, `gated-command` and `test-library-loading`'s
  `gate-log-dir`, cut it at whitespace, as make cuts `VALGRIND`. In a checkout whose path held a
  space, the log path became two words, and nothing refused it.
- **Measured:** `deps` and `require-tools` pass in such a path, and so does a suite that starts no
  gated child. Only a gated child meets the split. `CURDIR` is the physical path: a symlink whose
  name holds a space never puts one there.
- **`make test-memory` refuses such a checkout,** exit 2, after the `MEMORY_TIMEOUT` check and
  before any suite runs, naming the path and why. The two readers are unchanged.
  `check-memory-gate`'s `g whitespace` copies the tree into a real directory named with a space,
  and one named with a tab, and asserts the whole message, the exit and that no suite ran
  ([the log](../m1-owed-fixes-mutation-log.md)).
- **Rejected:** carrying such a path through the prefix. The prefix is a string of words, as
  `VALGRIND` is, and a quoting of its own would be a second rule for both readers to keep.

## Amendment, 2026-11-14: the `floor` and `current` lanes (M1 slice 5)

- **The lanes' compile options are held whole.** `check-sqlite.sh` compares every
  `sqlite3_compileoption_get` answer, in SQLite's order, with its role's list: 37 options for the
  floor and 38 for 3.54.1. `COMPILER=` is computed from the compiler, by SQLite's own
  preprocessor test.
- **That whole list is what keeps `DEFAULT_MEMSTATUS=0` out.** SQLite lists `DEFAULT_MEMSTATUS`
  only when it isn't 1 (`# if SQLITE_DEFAULT_MEMSTATUS != 1`), so the rule above, that the lanes
  must not set it to 0, has nothing else to read. A floor build with
  `-DSQLITE_DEFAULT_MEMSTATUS=0` was refused by one line, `+DEFAULT_MEMSTATUS=0`.
- **`check-ci` holds five jobs.**
  - In `floor` and `current` only, `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH` may stand, as env
    keys with exactly the job's values.
  - They stand on the three steps that run `check-sqlite.sh`, `make build` and `make test`, and
    each of those steps must carry both, and `CHEZ`.
  - `main`, `memory` and `nothreads` still refuse both names: `main` is the one job that tests
    discovery.
  - The SQLite cache keys are held whole, the compiler step must carry `id: cc`, and only the
    SQLite build and its save may carry the SQLite cache's `if`.
  - **Since the review's fixes, in every job:**
    - a `uses:` step may only be `actions/checkout@`, `actions/cache/restore@` or
      `actions/cache/save@`;
    - each cache, told apart by its path, is restored before its build and saved after the build
      and before its check;
    - in the lanes, the SQLite restore also comes after the `id: cc` step.

    Before these fixes, an `actions/cache@` step escaped the key rules. And a restore moved below
    `check-sqlite.sh` would have served the suites a library the job never checked.
- **`test-ci-sqlite`'s children run outside the gate,** as `test-check-floors`' `check-chez.sh`
  rows do.
  - They are CI scripts. Their Chez reads a stub or a built libsqlite3 through a probe of their
    own, and runs none of chez-sqlite3's code.
  - A shell child can't meet the gate's `Command:` rule.
  - So the rule that sends children that reach native code through `gated-command` covers a
    child that runs chez-sqlite3's code. `test-blocks`' dead-address child is one: it loads no
    libsqlite3, but reaches `malloc` and `free` through chez-sqlite3's memory library. A child
    that runs none of chez-sqlite3's code may run outside the gate.
  - Under `make test-memory`, the suite took 25 s, with 0 errors and no child log.

## Amendment, 2026-11-14: statements, and the decoy's cost (M2's plan)

Accepted by the maintainer on 2026-11-14, proposed in M2 slice 0
([the M2 plan](../2026-11-14-m2-plan.md), §4.1 and §4.7).

- **The `statement` counter gets its counts** ([ADR-0014](0014-statements-belong-to-their-connection.md),
  decision 9): up for every statement `sqlite3_prepare_v3` hands back, down at its finalize. A
  suite exits with it at zero, like the others.
- **`sqlite3_next_stmt` now has something to miss.** `close-database!` finalizes the connection's
  live statements first (ADR-0012, amended), so the check finds a statement only through a hole in
  that tracking: a defect of chez-sqlite3's, refused as M1 refuses it.
- **Valgrind sees a leaked statement only through its connection.** SQLite links every statement
  from its connection, so one never finalized on an open connection stays reachable through it.
  The leaks plant through `prepare-statement` drops both unclosed: the counters see the statement,
  and Valgrind the connection. M2 slice 3 records what Valgrind reports.
- **A plant meant for Valgrind uses values bigger than SQLite's lookaside slots.** Clearing a
  statement's bindings while a row is ready frees what the row reads. With a 5,000-byte BLOB,
  Valgrind reported the invalid read of the freed block, on both libraries; with 200 bytes it saw
  nothing, though the bytes read back were wrong. Lookaside is why: with it turned off, the same
  200-byte case reported an invalid read inside a freed 208-byte block, on both
  ([research/m2-review/](../research/m2-review/)). Turning it off takes `sqlite3_db_config`, M4's
  variadic binding, so M2's plants use big values instead.
- **The decoy's rows grow by 21** (ADR-0002, amended). Each is a gated child, about 5.6 s on CI
  (308 s for `test-library-loading`'s 55 child logs, M1 slice 3's amendment), so M2 adds about
  120 s, to about 430 s of `MEMORY_TIMEOUT`'s 600, with M3's and M4's entry points still to come.
  That is arithmetic, not a measurement: M2 slice 2 measures it on CI. Past 450 s, three quarters
  of the limit, the suite is split in two, each under the limit alone. The consequences' shards
  answer the job's total time, 14 minutes of 60 so far, which this doesn't approach.

## Amendment, 2026-11-14: the CI scripts' execute bits (M1's closing review)

Accepted by the maintainer on 2026-11-14, proposed in M1's closing review.

- **`check-ci` refuses a step whose whole run line begins `scripts/ci/NAME`,** unless that file is
  there and executable.
  - The workflow runs each such script by its path. A row that runs a script with `sh` never sees
    a lost bit.
  - At the review, `chmod -x` on four of them passed every check and every suite.
  - `floor.sh` is run with `sh` by the other scripts, so it isn't held.
- **The files are read under `CHECK_CI_ROOT`,** the repository root when it is unset, so that
  `test-check-ci`'s rows can point it at a copy. The name joins the words no workflow line may
  hold, since it would point the rule at another tree.

## Amendment, 2026-11-15: the decoy's cost, measured (M2 slice 2)

Accepted by the maintainer on 2026-11-15 ("Accept both"), proposed in M2 slice 2, from its build,
its Opus review and its CI run. It replaces the M2 plan amendment's estimate with a measurement, and keeps
its rule.

- **On CI, `test-library-loading` took 409.3 s under the gate,** with 76 child logs, up from 308 s
  with 55. That is the gap between its line and the next in the `memory` job's timestamped log, on
  PR #17's run at `811db14`. It was 252 s, then 373 s, alone in the container.
- **That is below 450 s, three quarters of `MEMORY_TIMEOUT`'s 600,** so the suite stays whole in
  M2. Slices 3 and 4 add no entry point. The `memory` job took 19 minutes of its 60. *This was
  one run, on a fast runner, and wrong for M2: the suite reached 562 s on a slow one. It is split
  (the amendment below).*
- **Every child grew, not only the new ones.** A child compiles native from source under Valgrind,
  so each binding native gains costs every child. One gated control child took 4.53 to 4.58 s on
  `main` and 4.83 to 4.89 s with the slice. Put back to `main`'s `native.sls`, it took 4.57 to
  4.58 s. So the cost grows with children times bindings: each new entry point adds a child of
  about 5 s, and about 15 ms to each of the others. The M2 plan's 5.6 s per new child, at a fixed
  cost for the rest, missed this.
- **M3's entry points cross the line.** With 41 s left under it, about seven more children reach
  450 s, so M3's plan splits the suite in two, each under the limit alone, as the rule above says.

## Amendment, 2026-11-15: the split, and its check (M2's closing review)

The maintainer's choice, 2026-11-15, put with M2's closing review's measurement: "Split in #19,
rest after". The split and a check that holds the rule land in PR #19, before it merges.

- **One CI run is one sample.** M2 slice 2's amendment above read 409.3 s from one run and settled
  that the suite stays whole. M2's closing review read the `memory` job's log of each M2 run:
  - 409.3 s at `811db14`, 404.2 s at `018b28a`, 411.0 s at `1eff5be` and 391.4 s at `7a8ea47`;
  - **520.9 s at `14c4825`, 555.1 s at `5dd3af0`, and 562.2 s at `1a53b13`,** #19's head, 38 s from
    `MEMORY_TIMEOUT`;
  - 284.8 s at `0572267`.

  `5dd3af0` and `0572267` hold the same code, at 555.1 s and 284.8 s. CI's runners differ about
  two to one, and `test-check-ci` shows the same gap.
- **The suite is split in two:** `test-library-loading-decoys` and `test-library-loading-real`,
  sharing `(library-loading)` under `tests/`.
  - The 36 entry points alternate between them, 18 each, and every old row runs in one of them.
  - A row in each holds that the two halves partition the convention table: merged in its order,
    each entry once.
  - Another row holds that each suite runs its own half, found by its file name.
  - In the container they took 196 s and 184 s, against 374 s whole. At CI's slow ratio, that is
    about 295 s and 277 s, each well under 450 s.
- **The rule now has a check.**
  - `make test-memory` prints each suite's time under the gate.
  - It fails a suite past three quarters of `MEMORY_TIMEOUT` by name, as `SLOW`, counted beside
    `HUNG`. The threshold is taken from `MEMORY_TIMEOUT` alone.
  - `make check-memory-gate`'s case r holds the check. It plants a suite past the threshold, which
    must be named `SLOW`, and one just under it, which must pass. Each of seven mutants of the check
    fails case r.
  - The check adds two `date` calls a suite, and case r about 20 s to the job.
- **On CI,** on `785234b`, the halves took 225 s and 195 s, on a runner where `test-check-ci`
  took 84 s, between the fast runners' 65 s and the slow ones' 135 s. So on the slowest runner seen
  they would take about 360 s and 310 s. The `memory` job took 21m55s, and named no suite `SLOW`.
- **So M3's entry points add to one half,** and the check names a half before it nears the
  timeout.

## Amendment, 2026-11-15: M3's entry points and suites (M3's plan)

Accepted by the maintainer on 2026-11-15 ("Accept all"), proposed in M3 slice 0
([the M3 plan](../2026-11-15-m3-plan.md), §4.7). M2 split `test-library-loading` in PR #19, its 36
entry points alternating between two halves, and `make test-memory` fails a suite past three
quarters of `MEMORY_TIMEOUT` as `SLOW` (the split's amendment, above). This amendment adds only what
M3 brings.

- **M3's five entry points add five decoy children,** each to one half, as the split amendment
  says, continuing the alternation: three to `test-library-loading-decoys` and two to
  `test-library-loading-real`. Each adds a child of about 5 s, and about 15 ms more for each of
  the others, by the slice 2 amendment's arithmetic, near 30 s across the halves where it was
  measured. M3 slice 2 reads both halves' times from more than one CI run, naming each, since one
  run is one sample. A half M3's rows bring near the threshold is split again in that slice, as M2
  split the whole.
- **M3's own suites** are held by the same check. The `memory` job's total is read in every M3
  slice's CI run; past 45 minutes, three quarters of its 60, the job is sharded, as this record's
  consequences foresee, with an amendment then.
- **A row that causes NOMEM sets `sqlite3_hard_heap_limit64` around one call** and lifts it
  straight after (M3's research, single T12). The limit is process-wide, so the row restores it on
  every path, and it needs the memory count on: where it is off, as on Apple's build, the row is
  named unavailable, as the memory check is.

## Amendment, 2026-11-16: the halves split in three (M3 slice 2)

Accepted by the maintainer on 2026-11-16 ("Accept all"). By the maintainer's choice of that day,
"Split into thirds now", in M3 slice 2 (PR #23). It
replaces the M3 amendment's "three to `test-library-loading-decoys` and two to
`test-library-loading-real`", and the alternation ADR-0002's M3 amendment continues.

- **Measured:** M3's five entry points brought the halves to these times under the gate on CI:

  | Run | Commit | `test-check-ci` | Decoys | Real |
  |---|---|---|---|---|
  | 43768337291 | `bb7feaa`, `main` before M3 | 117 s | 288 s | 250 s |
  | 43783905101 | `2e844f1`, slice 2 | 90 s | 264 s | 225 s |
  | 43794568875 | `3e9a506`, slice 2 | 117 s | 319 s | 272 s |

  On the same class of runner as `main`'s, the decoys half grew 31 s. The slowest runner seen ran
  `test-check-ci` in 135 s. Scaled by `test-check-ci`'s ratio, the split amendment's method, the
  decoys half would take 368 s there. Scaled by how the halves themselves grew with the runner,
  28% for `test-check-ci`'s 39% between `785234b`'s run and `bb7feaa`'s, it would take about
  355 s, 79% of the threshold. The maintainer chose to split now, since slice 2 is the only M3
  slice that owns these suites.
- **Three suites:** `test-library-loading-decoys`, `test-library-loading-real`, and a new
  `test-library-loading-missing`, which holds only missing-api rows.
- **Dealt by children, not by entry points:**
  - Each of the first two holds about 20 children beside its missing-api rows: the decoy's
    behaviours, or the real library, the refusals no decoy reaches, discovery and preflight.
  - So entry points are dealt in native's order by a pattern of five that repeats,
    `deal-pattern` in `(library-loading)`. Positions 0, 2 and 4 go to `-missing`, 1 to
    `-decoys` and 3 to `-real`.
  - Of the 41 entry points, that is 25, 8 and 8, and 25, 28 and 28 children. Dealing by thirds
    would have given 14, 34 and 33 children.
- **The partition is held in each of the three suites,** so any one alone holds it:
  - the parts, merged in the convention table's order, are its names, each once;
  - each part is what the pattern deals it;
  - each suite the partition names is a file, and a suite finds its part by its own file's name.
- **Measured in the container,** under `make test-memory`, on Guix's 3.53.1, with other runs
  beside it:
  - the halves took 224 s and 206 s at `3e9a506`;
  - the three took 155 s, 142 s and 140 s, 437 s in all against 430 s;
  - the 7 s more is the third suite's own setup;
  - the floor, 3.45.1, read the same to a second or two.
- **On CI,** both runs of the split landed on fast runners, where `test-check-ci` took 84 s and
  83 s:

  | Run | Commit | Decoys | Real | Missing | `memory` |
  |---|---|---|---|---|---|
  | 43854418185 | `d6c58d0` | 174 s | 144 s | 158 s | 24m02s |
  | 43858091596 | `24b426e` | 172 s | 143 s | 154 s | 23m36s |

  The halves had taken 264 s and 225 s on a runner of about that speed (43783905101). On the slow
  class, by how the halves grew between `785234b`'s run and `bb7feaa`'s, the largest would take
  about 225 s.
- **A later entry point is dealt by the same pattern,** three of every five to `-missing`, so
  `-missing` grows fastest and is the next to near the threshold: by the M2 slice 2 amendment's
  arithmetic, after about 35 more entry points on the slowest runner seen. A suite the `SLOW`
  check names is split again in its slice, as before.
- **Each suite writes the pattern out in a row,** so a pattern and parts changed together, which
  the merge and the dealing rows pass, still fail.

## Amendment, 2026-11-16: the memory job split in two (M3 slice 6)

Accepted by the maintainer on 2026-11-17 ("Accept all"). Proposed in M3 slice 6, by the
maintainer's choice of 2026-11-16, "Shard in slice 6". It carries
out the M3 amendment's rule, "past 45 minutes, three quarters of its 60, the job is sharded", and
makes decision 6's one `memory` job two. chez-curl ADR-0014's amendment "the memory job is split
in two" is the design. Its job names are kept, so the two repositories' required checks read
alike; none of its code is copied.

- **Why now:**
  - slice 5's `memory` job took 40m31s on a fast runner (run 43957085196, `test-check-ci` 85 s),
    where slice 4's took 31m22s on that class and 35m07s on a slower one;
  - the M2 session normalised six runs' suite times by each run's median suite ratio
    ([research/m3-slice-6/memory-shard-input.md](../research/m3-slice-6/memory-shard-input.md)),
    since `test-check-ci`'s own ratio overstates a runner's factor: 1.42 and 1.46, where the
    median suite read 1.27 and 1.19;
  - with slice 6's suites, one job would take about 41 min on the fast class and about 52 min at
    the slowest factor seen, 1.27. That is past the 45 minutes, and near the job's 60.
- **Two jobs, `memory-1` and `memory-2`,** in place of `memory`:
  - their check names are `memory-1 (the Valgrind gate, shard 1 of 2)` and
    `memory-2 (the Valgrind gate, shard 2 of 2)`, where the old one's was
    `memory (the Valgrind gate)`;
  - each runs the old job's setup, then `make check-memory-gate`, then
    `make test-memory MEMORY_SHARD=1` or `=2`;
  - the shard's number is the run line's argument. No `env:` names a shard or a list;
  - decision 6, as the M0 slice 4 amendment narrowed it, holds for each: neither job nor its two
    gate steps carries `if:` or `continue-on-error:`.
- **The gate runs in both jobs:**
  - each job has its own runner, with Valgrind installed there and Chez restored or built there,
    so a proof on one runner says nothing of the other's;
  - the jobs run side by side, so a run grows by one gate, about 5 minutes, not by two;
  - case b's flake, seen once in slice 2's run and never reproduced, now has two chances a run. It
    fails red, and hides nothing.
- **The Makefile writes out both lists,** `MEMORY_SUITES_1` (35 suites) and `MEMORY_SUITES_2`
  (38).
  - With no `MEMORY_SHARD`, `make test-memory` runs every suite, in order, as case g all requires.
    chez-curl ADR-0014's n held this beside its shards, and its review found it dropped with them.
  - Before any suite runs, `make test-memory` refuses, by name:
    - a `MEMORY_SHARD` but 1 or 2, and one from the environment, as it refuses `MEMORY_SUITES` there;
    - a shard beside a `MEMORY_SUITES` on its command line, which the shard would ignore;
    - a shard's list set on the command line, or from the environment under `make -e`;
    - an empty list, and two suites of one name in the list that runs.
  - `check-memory-gate`'s case n holds each refusal, and that each shard runs its own list.
- **`make check-memory-shards`, which `make test` runs,** fails unless the two lists run every
  `tests/test-*.sps` in the tree once between them.
  - It names a suite in neither, one in both, one written twice in a list, and a path in a list
    that is no suite.
  - So a new suite fails `make test` until it is placed in a shard: the one whose suites take less
    time.
  - It reads the tree's suites, not a run's `SUITES`. So `make test SUITES=…` still narrows a run,
    as the M1 closing review's log ran it, and a narrowed run still holds the shards to the whole
    tree.
  - `check-test-fails`'s cases `shards-neither`, `shards-both` and `shards-narrowed` hold that
    `make test` runs it, on the tree's suites.
- **`check-ci` holds six jobs.**
  - Each memory job runs check-chez, then the gate, then its own shard, each as a step's whole run
    line.
  - It refuses a third shard, a job running the other's shard, a shard missing or given through an
    `env:`, and every word `MEMORY_*`, as it refuses `VALGRIND_*`. The one exception is
    `MEMORY_SHARD` on a memory job's own shard line.
  - `test-check-ci` holds each rule, in 439 rows.
- **The split** starts from the M2 session's greedy one, with the threaded suites dealt first.
  `test-check-memory-shards` is added to shard 1, and `test-open-interleave` moved to shard 2
  after the local runs. Slice 5's suites rest on one CI run each and slice 6's on local times, so
  the times are estimates:

  | | Shard 1 | Shard 2 |
  |---|---|---|
  | Suites, fast class | 1018 s; 1085 s with `test-transaction-interrupt` at its worst seen, 149 s | 1086 s |
  | Job, fast class | 22.6–23.4 min; 24.5 at worst | 23.7–24.5 min |
  | Job, slow class (×1.27) | 28.5–29.3 min; 30.7 at worst | 29.9–30.7 min |
  | Measured in the container, side by side | 21m27s | 15m13s |

  - Each job counts setup, 30–80 s, and the gate, about 305 s fast and 385 s slow.
  - Local times don't predict CI's balance: suites that start many children run relatively slower
    here.
  - Slice 6's CI run reads every suite's `time:` line in both jobs. Shards that drift apart are
    rebalanced in the slice that sees it.
- **An open risk, `test-transaction-interrupt`:**
  - under the gate here it took 434 s alone and 429 s in shard 1, of the 450 s threshold, and
    225 s once. On CI it has taken 20 s to 149 s in four runs;
  - its watchdog is slice 4's, a plain thread interrupting every 5 ms. Under Valgrind, which runs
    one thread at a time, how soon it runs is the scheduler's;
  - the remedies are slice 6's watchdog device, which takes SQLite's memory mutex each round
    (ADR-0019's slice 6 amendment), or a split. The device binds the owner to calls that are
    `__collect_safe` or take none of SQLite's memory while the mutex may be held, and this suite's
    owner runs inserts that allocate, so it is no drop-in;
  - slice 6's CI run reads the suite's time in shard 1. A time on CI past a third of the
    threshold, 150 s, is a finding for M3's closing review.
- **What no check holds:**
  - an empty shard list passes `check-memory-shards` when the other holds every suite. Only its CI
    job fails, through `test-memory`'s refusal;
  - nothing fails when one shard grows far past the other. The `SLOW` line holds each suite, and the
    60-minute limit each job;
  - a change that deletes the workflow, or `main` with the memory jobs, runs no check at all, as
    the M0 slice 4 amendment says. Branch protection, requiring both new check names, is the
    maintainer's lever. Until it names them, the old required check, `memory (the Valgrind gate)`,
    never reports, and no PR can merge.

## Amendment, 2026-11-17: the open risk met, and the gates no row read (M3's closing review)

Accepted by the maintainer on 2026-11-17 ("Accept all"), proposed in M3's closing review, from reviewer B's findings and the fixes' measurements
([the review's log](../m3-closing-review-mutation-log.md)).

- **The open risk was met.** `test-transaction-interrupt` took 318 s in `memory-1` on `main` at
  `c0a5408` (run 44083802043), past the slice 6 amendment's 150 s, and 71% of `SLOW`. Over seven
  two-shard runs it took 31 to 318 s.
  - **The cause:** its watchdog was still slice 4's plain thread, interrupting every 5 ms, which
    under Valgrind runs only when the scheduler lets it. Locally its time was the host's: 18 to
    77 s on 18 cores, 11 to 15 s pinned to two, and 429 to 434 s in slice 6.
  - **The fix:** the suite now uses the memory-mutex device (ADR-0019, amended the same day), with
    its statements prepared before the watched call. It took 10 to 16 s under the gate in every
    local run, on both libraries, so no split was needed. On PR #32's CI, run 44112097972, it
    took 11 s.
- **The device's first round is a handshake.** `main`'s run 44087748537, on `e590fdc`, failed
  `memory-2` on `test-interrupt-reach`'s 3 MB prepare, which ran unstopped: the first round's
  interrupt landed before the parse cleared it (ADR-0019, amended the same day). The handshake
  closes that window in the three suites that use the device.
- **A gate's `UNAVAILABLE` lines need a hold of their own.** `make test-memory` prints nothing of a
  passing suite but its verdict and time, so a suite's `UNAVAILABLE` lines are read only in
  `build/memory/<suite>.log`. The memory check's availability was held all along: by
  `test-memory-check`'s rows, `check-test-fails`' leaks case, and the lanes' compile-option
  lists. PR #30's tell, and `test-transaction-nomem`'s `memory-kept`, were held by nothing:
  either could have skipped its rows on every Linux lane, and passed.
  - **The tell** is now held to an idle entry point registered straight through the FFI.
  - **`memory-kept`** is now held to the memory check's own control.

## Amendment, 2026-11-17: M4's entry points, suites and extension (M4's plan)

Accepted by the maintainer on 2026-11-17 ("Accept all"), proposed in M4 slice 0 ([the M4 plan](../2026-11-17-m4-plan.md), §4.6).

- **Three decoy children,** one for each of M4's entry points. `sqlite3_db_config` and
  `sqlite3_free` are dealt by the pattern of five (the amendment "the halves split in three");
  the optional `sqlite3_load_extension` stays out of it, its rows named in
  `test-library-loading-real` ([ADR-0002](0002-runtime-libsqlite3-discovery.md), amended
  2026-11-17). Each adds a child of about 5 s under the gate. Slice 2 reads the three suites'
  times from more than one CI run, naming each.
- **M4's new suites** each go in a shard, as `make check-memory-shards` requires, and by the
  shards' amendment in the one whose suites take less time.
- **`make check-variadic` runs in CI's `main` job,** in its "Checks and suites" run line, after
  `check-test-fails`, never inside `make test`, whose `check-test-fails` cases each run under a
  5 s suite timeout and a 70 s bound. `check-ci`'s line for that step moves with it
  ([ADR-0001](0001-bind-libsqlite3-directly.md), amended 2026-11-17).
- **A loaded extension leaves the gate clean.** An extension compiled at test time, loaded,
  called and closed under the gate's Valgrind flags gave 0 errors and nothing definitely lost,
  and `sqlite3_memory_used` came back to 0. The same program, with the same open and close and no
  load, left the same still reachable blocks, byte for byte in count and size, on each of three
  libraries (M4's research, X1). The gate needs no suppression for one.
- **A load's message is SQLite's memory,** freed by `sqlite3_free`. Left unfreed, two messages
  were 448 bytes definitely lost, and 432 bytes above the memory check's baseline: both parts of
  the gate see it (X1).
- **On a library without extension loading,** as Apple's is, the suites name their load rows
  unavailable, never silently, as the memory check names itself where the count is off. They
  choose them by native's record of `sqlite3_load_extension`, and assert the named condition
  there for real.

## Amendment, 2026-11-17: the statements check after a refused close (M4's close fix)

Accepted by the maintainer on 2026-11-17 ("Accept all"), proposed in M4's close fix ([its mutation log](../m4-close-fix-mutation-log.md)), from M4 slice 5's FTS5 suite, its review and the fix's own (Opus). Decision 5's `sqlite3_next_stmt` check runs after a refused `sqlite3_close`, not before each
close ([ADR-0012](0012-explicit-close-and-the-handle.md), amended). The gate keeps its property:
SQLite refuses a close while any statement is left, so no close succeeds beside a leaked one, and
the refusal names the count. `test-connection-close` is in `MEMORY_SUITES_1`.

## Amendment, 2026-11-18: the no-load lane, the loading suites split, and the sweeps' low passes (M4's closing review)

Accepted by the maintainer on 2026-11-19 ("Accept all"), proposed in M4's closing review ([the CI log](../m4-closing-review-ci-log.md),
[the loading log](../m4-closing-review-loading-log.md), [the sweeps log](../m4-closing-review-sweeps-log.md)).

- **The `current` job builds a second SQLite, `--no-load`:**
  - the same release and flags, FTS5 among them, with `-DSQLITE_OMIT_LOAD_EXTENSION`, so it lacks
    `sqlite3_load_extension` as Apple's library does, and keeps FTS5 as Apple's does;
  - five steps after the job's `make test`: its cache's restore, build and save, keyed and guarded
    by their own id, `sqlite-no-load`; then `check-sqlite.sh --no-load`, which holds its 40
    compile options line for line; then the whole `make test` again, with this build's env.

  The maintainer chose "In CI's current job" and "The whole make test" (2026-11-18). A suite's
  branch for a library without extension loading runs on every run, not only on the Mac, where
  one first crashed (#47). It costs about 2 s a run, about 30 s to compile on a cache miss, and
  about 2 min of runner time, but no wall time.
- **`check-ci` is keyed by build, not by job:** `floor` makes one build and `current` two. Each
  build has one restore, with its id held, and one save. Each build's `if` stands only on the
  step naming its directory, or on its save. `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH` are held
  per step to that step's build, and a line required twice, current's `make test`, must be the
  run line of two steps.
- **The loading suites split, three into nine, at most 11 children each.** A child under the gate
  costs about 5 s here and up to about 11.5 s on a slow CI runner, so 35 children made
  `test-library-loading-real` 258 and 264 s on `main`'s runs, over half the 450 s bound:
  - `-missing-1` to `-4` deal the 43 missing-api entries by position mod 4, 11, 11, 11 and 10;
  - `-real` keeps the override and discovery, 11; `-preflight` the preflight, 9; `-extension`
    M4's load rows, 7; `-decoys` the control's switches, 11; `-combined` the combinations and
    the marker, 9.

  Every old row is kept with its expected value but the partition's, whose four rows each
  missing suite holds; no plant the old layout caught gets past the new one. Each new suite took
  52 to 85 s under the gate here, so at most about 169 s on a slow runner. Shard 1 holds `-real`,
  `-missing-1`, `-2` and `-4`, and `-extension`; shard 2 `-decoys`, `-missing-3`, `-combined` and
  `-preflight`, by the lighter shard over `main`'s last three runs.
- **The sweeps' low passes cost gate time:** M3's and slice 3's sweeps each gain a pass with collect
  requests falling (ADR-0016, amended the same day). Under the gate here, `test-open-db-config-engines`
  went from 57 to 138 s, `test-open-interleave` from 37 to 93 s, `test-transaction-engine` from 47
  to 92 s and `test-conveniences-pending-query` from 37 to 87 s. The pending fold's and script's
  low passes are suites of their own, `test-conveniences-pending-fold-low` and
  `-script-low-0` to `-3`, the script's dealt by fuel mod 4, about 90 s each, so none nears half
  the bound on a slow runner. Each memory job then runs about 30 suite-minutes, under its
  60-minute timeout; read the first runs' times before calling the margin safe.
