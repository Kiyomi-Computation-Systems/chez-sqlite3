# ADR-0005: The memory gate is Valgrind on Linux, our counters, and SQLite's own checks

- **Status:** Accepted (the maintainer, 2026-11-13). The two SQLite checks are built in M1.
  Amended 2026-11-13: what M0 slice 3 measured and built
  ([amendment](#amendment-2026-11-13-what-m0-slice-3-measured-and-built)).
- **Date:** 2026-11-13
- **Scope:** every suite, and CI's `memory` job
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
