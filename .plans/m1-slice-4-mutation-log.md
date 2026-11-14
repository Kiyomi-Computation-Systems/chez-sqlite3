# M1 slice 4 mutation log: conditions, connections and the first `(chez-sqlite3)`

Evidence that slice 4's first part (4a) fails through the property each rule claims to guard
([M1 plan](2026-11-13-m1-plan.md) §3.1, §5 slice 4; [ADR-0010](decisions/0010-a-connection-belongs-to-its-thread.md),
[ADR-0012](decisions/0012-explicit-close-and-the-handle.md),
[ADR-0013](decisions/0013-errors-are-condition-types.md)). Format of
[the M0 closing review's log](m0-review-mutation-log.md).

4a is:
- three condition types in `(chez-sqlite3 private conditions)`: `&sqlite-error`,
  `&sqlite-wrong-thread` and `&sqlite-closed`;
- three new private libraries: `(chez-sqlite3 private open-options)`, the pure core of the options;
  `(chez-sqlite3 private connection)`; and `(chez-sqlite3 private report)`;
- the public `(chez-sqlite3)`, which re-exports 28 names and defines nothing;
- the seam's tables, extended with `get-thread-id`;
- four suites: `test-open-options`, `test-connection`, `test-public`, and new rows in
  `test-conditions`.

An Opus agent designed and built it, test first, from a design the coordinator ruled on. The
memory exit check, the leaks plant through `open-database`, the docs and the check that the
testing library loads no libsqlite3 are later parts of the slice, by other agents.

Each mutation ran in its own copy of the working tree, made in the session scratchpad without `.git`
or `build/`. It ran through that copy's own `scripts/guix-env`, after `make deps` in the copy. A
driver refused any edit whose old text did not occur exactly once, or that changed nothing; all 53
were checked against the tree first. The working tree was never edited by a mutation. The counts
below are read from the suites' own output (`# of expected passes`, `# of unexpected failures`),
never by eye. The driver and its list are in the session scratchpad, not the repository.

## Measured first (Guix container: Chez 10.4.0, SQLite 3.53.1)

Probes ran in a scratch copy through bare FFI before any code was written. Each fact below is
what a probe printed.

- **The mutex (ADR-0010, decision 5).** This build is `THREADSAFE=1`. `sqlite3_db_mutex` answered:
  - with no mutex flag: non-NULL;
  - with `SQLITE_OPEN_FULLMUTEX`: non-NULL;
  - with `SQLITE_OPEN_NOMUTEX`: NULL.

  So on this build the default row tells `FULLMUTEX` from `NOMUTEX`, but not from no flag at all.
  `test-open-options` holds the bit itself, and the Mac's Apple library, `THREADSAFE=2`, is where
  the default row tells the two apart.
- **Guix's 3.53.1 is not built with `USE_URI`.** `sqlite3_compileoption_used("USE_URI")` answered
  0. Opened without `SQLITE_OPEN_URI`, `"file:nu.db?mode=rwc"` made a file of that literal name, not
  `nu.db`. ADR-0012's consequences name Ubuntu's, Apple's and Homebrew's builds as `USE_URI`; on
  Guix's, a `file:` name is a plain one. The refusal is ours, so its test is the same on every build.
- **SQLite's `file:` test is case-sensitive.** With `SQLITE_OPEN_URI`, `"FILE:up.db"` made a
  literal `FILE:up.db`. The refusal matches the five bytes `file:` at position 0, as SQLite does.
- **Failed opens.** Each answered a non-NULL handle, and each handle's close answered 0. The codes
  were:

  | Open | Code | Extended code |
  |---|---|---|
  | missing directory | 14 | 14 |
  | a directory | 14 | 14 |
  | `READWRITE` on a missing file | 14 | 14, and no file made |
  | `READONLY` on a missing file | 14 | 14 |
  | a symlink with `NOFOLLOW` | 1550 (`cantopen-symlink`) | 1550 |
  | the same, without `EXRESCODE` | 14 | 1550 |
- **`EXRESCODE` is visible through `sqlite3_exec`.**
  - `SELECT 'a' < 'b' COLLATE no_such_collation` answered 257 with the flag and 1 without, on every
    connection, read-only ones too.
  - A second `INSERT` into a `UNIQUE` column answered 2067 and 19.
  - `sqlite3_errcode` is masked the same way. `sqlite3_extended_errcode` answered the extended
    code either way.
- **SQLite refuses a close with no statement open.** Once `sqlite3_backup_init(B, "main", A,
  "main")` has run, `sqlite3_close(A)` answers 5 (`BUSY`), with `next_stmt` finding none. Closing B
  succeeds. After `sqlite3_backup_finish`, A closes with 0.
- **An untracked statement.** `next_stmt(h, 0)` finds it, `sqlite3_close` answers 5, and after the
  finalize, 0.
- **`MEMORY` on a path:** it opens, and no file is made.
- **An opaque, sealed record prints `#<database>`,** with `write` and `display` alike, and
  `record?` answers `#f`. No address is shown.
- **Thread ids were monotonic.** Six threads forked one after another, each finished before the
  next, got `(1 2 3 4 5 6)`, with main 0. CSUG doesn't promise this. If a later Chez reused ids, a
  new thread could pass a dead owner's check.
- **A `guard` whose clauses don't match re-enters the extent.** An inner one inside an outer one
  logged `(before after before after (outer boom))`.
- **An engine's expiry runs `dynamic-wind`'s thunks.** A 2,000-expiry engine logged 4,002 before
  and after entries. So `call-with-database`'s connection closes at the first preemption, as
  ADR-0012 decision 8 has it for any escape, and a resumed procedure finds it closed. Engine users
  open with `open-database`.
- **Interrupts come back on after a raise.** `critical-section` and Chez's critical
  `(dynamic-wind #t …)` each restore them after a raise from the body, the before thunk or the
  after thunk, and after an escape: `disable-interrupts` answered 1 after each.
- **Re-export:** a program that referenced only a name library B re-exports from C ran C's body
  alone, not B's. So `(chez-sqlite3)`, which defines nothing, loads no libsqlite3 when a condition
  predicate is referenced.
- **A model of `call-with-database`,** with the close made to fail:
  - a raise: the raise was caught, after 1 close;
  - the same under an inner guard that doesn't match: caught after 2 closes, both contained;
  - a return, or an escape: the close's assertion was raised.

## The red runs

Each suite was written first and run against stubs with the real exports, every procedure
answering the symbol `stub`. The stubs were under `build/stubs/`, first on the library path, never
under `src/`: one for each new library, and a copy of `conditions.sls` with the new names as
stubs. The stubs were then removed.

| Suite | Red run | First green run | Final |
|---|---|---|---|
| `test-open-options` | 5 passed, 18 failed | 23 passed | 23 |
| `test-conditions` | 28 passed (the old rows), 15 failed (every new one) | 42 passed, 1 failed | 43 |
| `test-connection` | 3 passed, 41 failed | 44 passed | 45 |
| `test-public` | 5 passed, 12 failed | 17 passed | 17 |
| `check-seam` | — | `the seam holds (14 libraries in 14 files checked)` | the same |
| `test-check-seam` | — | 67 passed | 67 |

The rows that passed against a stub are rows a stub can satisfy:
- **`test-open-options`:** the export list; the counts of orderings (13,700) and one-off names
  (635); `(chezscheme)` giving names to refuse; and the list left unchanged.
- **`test-connection`:** the load, which a stub makes, and the counts after it and at the end.
- **`test-public`:** the load; the 28 names; connection's and report's export lists, which the
  stubs copy; and native listing options.

**Fixed after the first green runs:**
- **`test-conditions`' one failure was the row's own mistake.** A handler that returns from a
  non-continuable raise makes R6RS raise a `&non-continuable`, and that, not the original condition,
  is what the next handler gets. The row now asserts `non-continuable-violation?`.
- **`test-connection` gained a 45th row,** for `call-with-open-handle`'s own argument checks.
- **`at-raise` now closes a database it is handed.** The first mutation run showed why: a refusal
  that failed to refuse, in O8 and N13, left a connection open, and every later count row failed with
  it, 23 and 26 rows. Those mutations were then rerun with every other mutation that runs
  `test-connection`, in fresh copies, and the counts below are from that rerun.

## The mutations

Baselines, from the green runs: `test-conditions` 43, `test-open-options` 23, `test-connection` 45,
`test-public` 17, `test-check-seam` 67. Each row names the suites that failed and how many of their
rows failed. A mutation counts as caught when at least one row failed. Every one caught also exited
1. 53 mutations; **every one was caught.**

### Conditions (`test-conditions`)

| Mutation | Guards | Failed |
|---|---|---|
| C1 | `raise-sqlite-error`'s names: code and extended code swapped | 2: the whole condition, the names row |
| C2 | `&who` is the WHO given: fixed at `chez-sqlite3` | 1: the whole condition |
| C3 | `&sqlite-error` carries a `&message`: dropped | 1: the whole condition (`no-message`, `message-differs`) |
| C4 | each accessor reads its own field: `sqlite-error-sql` reads the message | 3: both field rows, the whole condition |
| C5 | accessors are checked: `sqlite-error-message` is Chez's own | 1: the accessors' refusals (Chez's who and the value itself) |
| C6 | `SQLITE_OK` is no error: 0 accepted | 1: the refusals row |
| C7 | `&sqlite-error` is under the root: put under `&error` | 3: the kinds matrix, the whole condition, the names row |
| C8 | owner and caller: swapped in `raise-wrong-thread` | 2: the wrong-thread compound, and the refusal (`(caller -2)`, not `(owner -2)`) |
| C9 | `raise-closed` refuses a WHO that is no symbol: its check dropped | 1: the who refusals |

### The options (`test-open-options`, then `test-connection`)

| Mutation | Guards | Failed |
|---|---|---|
| O1 | `'read-write` alone doesn't create: it creates | options 3: alone, pairs, every ordering; connection 1: `'read-write` on a missing file made one |
| O2 | `'create` alone gives `READWRITE` too | options 3; connection 1: the `'create` row (CANTOPEN) |
| O3 | `'no-mutex` takes `FULLMUTEX`'s place: both set | options 3. Not run through SQLite: `NOMUTEX` wins over `FULLMUTEX` there, and no row could see it |
| O4 | `EXRESCODE` always: dropped | options 4, the default row among them; connection 12: every open row's `extended` column |
| O5 | an option given twice is refused: accepted | options 4: the three twice rows, the precedence row |
| O6 | `'read-only 'create` is a contradiction: accepted as read-only | options 3: pairs, every ordering, the contradictions |
| O7 | names match exactly: matched without case | options 1: the near names (`READ-ONLY` and the rest) |
| O8 | `'no-follow` adds `NOFOLLOW`: adds 0 | options 3; connection 2: both symlink rows opened the link |
| O9 | `file:` is case-sensitive: `string-ci=?` | options 2: the one-off complement (`FILE:`, `File:`, …), and the row of names elsewhere (`FILE:x.db`, `File:x.db`) |
| O10 | the colon is part of it: `file` alone | options 2: the one-off complement (`file;`, `filex`, …), and the row of names elsewhere (`"file"` itself) |
| O11 | at position 0 only: found anywhere | options 2: `./file:`, `/d/file:` and every later position |

### Connections (`test-connection`)

**The flags SQLite got:**

| Mutation | Guards | Failed |
|---|---|---|
| N1 | the shell passes the parser's flags: `EXRESCODE` masked off | 12: every open row's `extended` column |
| N2 | the options reach SQLite: the default flags always | 9: `read-write`, `read-only`, `uri` (`mode=ro`), `memory`, `no-follow`, `no-mutex`, the `:memory:` row, the symlink failure, the pass-through row |
| N13 | `file:` without `'uri` is refused: not | 2: the refusal row (on this build, CANTOPEN instead), and `call-with-database`'s checks |
| N30 | the filename is checked to be a string: not | 2: that row, and `call-with-database`'s checks. Chez's own `string-copy` refused instead, naming the value itself: `(("a.db"))` for a list holding a string, which ADR-0013 decision 7 forbids |
| N31 | a refusal's irritants name the rule: the contradiction's dropped | 1: the options row |

**Failed opens, the count, and the assessment's leaks.** Each plant is a copy of a defect the
assessment lists (ADR-0009):

| Mutation | Guards | Failed |
|---|---|---|
| N3 | **planted:** a failed open's handle is closed (Thunderchez left it open) | 36: every row from the first failed open on, the counts never back at zero, and the closing counts |
| N4 | it is closed **before** the raise: closed by an after thunk once the raise has left | 3: both failed-open rows and `call-with-database`'s, each with connection 1 **at the raise** and 0 after |
| N5 | a failed open's handle is counted too: counted only on success | 6: every failed-open row; the close's count-down raised at zero |
| N6 | **planted:** the out-pointer is freed (Thunderchez leaked one per open): a counted block, never freed | 38: every row that reads a count (block 1, 2, …) |
| N24 | a NULL handle takes errstr, calling no other reader: the branch dropped | 1: `failure-details`' stub row |

**Closing:**

| Mutation | Guards | Failed |
|---|---|---|
| N7 | **planted:** a close clears the record (Thunderchez kept the address) | 6: the second close called `sqlite3_close` on the freed handle and got `misuse` back, and `call-with-open-handle` ran its procedure on the freed address (`415704120`); then every `call-with-database` row that reads the handle after |
| N8 | `sqlite3_next_stmt` before `sqlite3_close`: not asked | 4: both untracked rows (`&sqlite-error busy` in place of the assertion), and both `call-with-database` rows whose close must fail |
| N9 | the walk counts every statement: one at most | 1: two statements, named `(untracked-statements 1)` |
| N22 | a close SQLite refuses is raised: not | 1: the backup row |
| N23 | a second close does nothing: it raises | 3: the second close, the re-entry row, and the procedure that closes its own connection |
| N28 | `call-with-open-handle` checks the connection is open: not | 5: the second close's row, and every `call-with-database` row that reads the handle after |

**Threads.** Each wait is bounded; no mutation hung.

| Mutation | Guards | Failed |
|---|---|---|
| N11 | the owner check: none | 4: every thread row |
| N10 | the thread is checked before the open state: only for an open connection | 1: another thread's close of a closed connection |
| N12 | the owner is the opener: every connection owned by thread 0 | 1: the forked opener's row (main's close succeeded; the owner thread's then raised, owner 0, caller 4) |

**`call-with-database`:**

| Mutation | Guards | Failed |
|---|---|---|
| N14 | while raising, the close's failure is contained: raised | 2: raise-then-fail, plain and under the inner guard |
| N15 | the before thunk never clears the raise: it does | 1: the inner guard's row alone. The guard re-enters, the flag goes, and the second close's failure is raised over the procedure's condition |
| N16 | on a return or an escape the close's failure raises: contained | 2: return-then-fail, escape-then-fail |
| N17 | the procedure is checked first: not | 1: the checks row. `'read-only` was taken as the procedure: the file was made, and Chez's "not a procedure" was raised with connection 1 at the raise |
| N18 | re-entry finds it closed: reopened | 1: the re-entry row (connection 1 on the second run) |
| N19 | everything it raises names `call-with-database`: the open names `open-database` | 2: the failed open, and the U+0000 refusal in the checks row |

### The report and the public library (`test-public`)

| Mutation | Guards | Failed |
|---|---|---|
| N20 | each string is a fresh copy: `sqlite-version` answers the report's own | 1: the copies row |
| N25 | `sqlite-compile-option?` answers SQLite's 1: the opposite | 2: both option rows |
| N26 | `sqlite-compile-options` in SQLite's order: reversed | 2: the list row, the fresh-list row |
| N27 | the export list, whole: `sqlite-library-unavailable-library` exported too | 1: the export list |
| N21 | nothing is wrapped: a public `sqlite-error?` of its own | public 2: the no-body row, the `eq?` row. `test-connection` passed 45, as it must: the wrapper behaves the same |

### The seam

| Mutation | Guards | Failed |
|---|---|---|
| S1 | `get-thread-id` is connection's alone: its library-only entry dropped | `check-seam` passes; `test-check-seam` 2: the written-out table, the rule (f) matrix |
| S2 | `get-thread-id` is allowed: dropped from `allowed-chez-names` | `check-seam` names connection's import (problems: 1); `test-check-seam` 3: both allowlist rows, the library-only row |
| S3 | no other library asks for thread ids: report imports `get-thread-id` | `check-seam` names report's import, "allows it only in (chez-sqlite3 private connection)" (problems: 1) |

## Not covered

No row here can see these, by design or by measurement:

- **The critical sections against an interrupt or an engine.** These are the open with its count,
  the close with its clear and count, `call-with-open-handle`'s checks with their procedure, and
  `call-with-database`'s open with its variable. No suite can make an interrupt land between two
  calls on demand. Review holds them, and the counters would see a lost connection.
- **The filename copied before it is checked.** A second thread changing it between the check and
  the open is a race no row can schedule. ADR-0011 decision 2's rule, held by review as for
  call-with-c-string's NUL.
- **`FULLMUTEX` against no flag**, end to end, on a `THREADSAFE=1` library (above). The parser rows
  hold the bit.
- **A NULL handle from a real open.** It needs SQLite to fail an allocation, and v1 never calls
  `sqlite3_config`. `failure-details`' stub row holds the branch.
- **A failed open whose own close fails.** It is not reachable with SQLite, so nothing is counted
  down, and the gate would see the handle.

## Final runs

- **`scripts/guix-env make test`:** `ran 20, passed 20, failed 0, hung 0`, with:
  - `check-seam: the seam holds (14 libraries in 14 files checked)`;
  - `check-suites`: 20 checked.
- **`scripts/guix-env make test-memory`:** `ran 20, passed 20, failed 0, hung 0`. The new suites'
  Valgrind logs:

  | Suite | Errors | Lost | Still reachable |
  |---|---|---|---|
  | `test-connection` | 0, from 0 contexts | 0 definitely, indirectly or possibly | 8,784 bytes in 13 blocks |
  | `test-public` | 0 | 0 | 1,920 bytes in 8 blocks |
  | `test-open-options` | 0 | 0 | 168 bytes in 3 blocks |
  | `test-conditions` | 0 | 0 | 168 bytes in 3 blocks |

  No suppression was used.
- **`scripts/guix-env make check-test-fails`:** `make test failed, as it must, in all 12 cases`.
- **`scripts/guix-env make check-memory-gate`:** `the memory gate failed, as it must, and its refusals held, in all 36 cases`. Its `g all` case reads the suites from the glob, so the three new suites joined it with no edit.
