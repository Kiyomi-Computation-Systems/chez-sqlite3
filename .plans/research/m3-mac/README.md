# Research: M3's hand run on the Mac

Run 2026-11-17 by the maintainer, on PR #29's branch (`m3-slice-6-interrupt`), as the M3 plan's §6
and ADR-0004 ask. The machine: macOS 26.7.1, arm64, Chez 10.4.1. The libraries: Apple's
`/usr/lib/libsqlite3.dylib`, 3.51.0, which discovery finds, and Homebrew's 3.54.1, through
`CHEZ_SQLITE3_LIBRARY`.

## The files

| File | What it is |
|---|---|
| [mac-apple.txt](mac-apple.txt) | `make test`, whole, with Apple's library |
| [mac-brew.txt](mac-brew.txt) | `make test`, whole, with Homebrew's |
| [memory-management.sh](memory-management.sh) | S3's Mac case, reproduced on Linux: 3.54.1 built six ways |
| [memory-management.txt](memory-management.txt) | Its output, for the fixed suite and for `main`'s |

`make check-dev` and `make check-test-fails` ran with Apple's library and passed. `check-dev`
printed its `ok` line, and `check-test-fails` printed "make test failed, as it must, in all 16
cases". The maintainer pasted those outputs in the session; they aren't kept here.

## Results

| | Apple's 3.51.0 | Homebrew's 3.54.1 |
|---|---|---|
| `make test` | ran 73, passed 66, failed 7 | ran 73, passed 72, failed 1 |
| The memory check | unavailable: no memory count | passed |
| The NOMEM rows | `UNAVAILABLE`, skipped | ran |
| Slice 6's suites: `test-interrupt-*`, `test-contention`, `test-transaction-interrupt` | pass | pass |
| The long prepare, in `test-interrupt-reach` | pass | pass |
| P4, the busy wait's grain | milliseconds: a 250 ms timeout answered busy after 284 ms | milliseconds: 288 ms |

None of the eight failing suites is slice 6's. All are on `main`, from slices 3 to 5. Each is a
fault in a test. No failing row showed a fault in the library. On Apple's library the sweeps
couldn't judge what they saw, since only the tell can tell a whole new call from a re-entry;
they passed in full on Homebrew's library, on the same Mac.

## Apple's library refuses `sqlite3_auto_extension`

- **The failure:** seven suites fail, `test-conveniences-pending-*` and `test-open-interleave`,
  and each failure follows from one row. Their tell registers an authorizer for every new
  connection through `sqlite3_auto_extension`, which answered 21, `SQLITE_MISUSE`.
- **It's Apple's change.** Upstream answers 21 there only for a NULL entry point under API armor
  (3.45.1's `sqlite3.c`, `sqlite3_auto_extension`), and the tell passes a real one. Homebrew's
  library, on the same Mac, registered it, and all seven suites passed in full. That matches
  [mac-d7](../mac-d7/README.md)'s 21 for `ENABLE_LOAD_EXTENSION`: Apple's library refuses both
  ways in for code a caller supplies.
- **What failed after it:** with no authorizer, nothing was noted. The tells' prepare counts read
  0; the sweeps found no interleaving (`too-few-interleavings past 0`); the rows that raise
  SIGINT from the authorizer never raised.
- **Some checks passed there without testing anything.** An empty tell satisfies them:
  - the seven reset rows, which read only the tell;
  - the prepare bound in the five timer rows, since a count of 0 is at most any bound;
  - the whole-new-call checks in `test-open-interleave`'s two failing-call sweeps.

  The rest of the timer rows and of those sweeps tested real properties on Apple's library, and
  still do.
- **The fix, in this PR:** where the registration is refused with 21, 33 rows report what they
  can't check, as the memory check does on the same library (ADR-0005, amended: the suite passes
  on its other checks).
  - **18 rows need the tell whole:** the nine sweeps, query-row's check-out row, the escape row
    and the seven reset rows. Each prints `UNAVAILABLE` and is skipped, never passed. The sweeps
    still run on the Mac with Homebrew's library.
  - **15 rows mix checks:** the eight tell rows, the five timer rows and the two failing-call
    sweeps. Each runs, and drops only the check that reads the tell, printing `UNAVAILABLE` with
    that check's name. Each still asserts its whole output, with the dropped part as
    `unavailable` on both sides.
  - **Any other code fails the registration row,** with nothing skipped. Upstream also answers 7
    from a failed realloc, or whatever `sqlite3_initialize` failed with.
  - **The callbacks stay locked after a refusal.** Chez 10.4.0's `Sunlock_object` decrements the
    segment's count whether or not the object was locked (`c/gcwrapper.c`), so an extra unlock
    can unpin another object.
  - The plants are in [the mutation log](../../m3-mac-mutation-log.md).

## A NOMEM's reach differs by build, at one version

- **The failure:** `test-transaction-nomem`'s S3, outer and nested, with Homebrew's 3.54.1. S3 is
  `insert into b select randomblob(100000) from src limit 3`, stepped under a hard heap limit.
- **What differed:** at the floor, with Guix's 3.53.1, and in CI's `current` lane at 3.54.1,
  its NOMEM ends the transaction: autocommit reads 1 straight after the step. With Homebrew's
  3.54.1 it left the transaction open: autocommit 0. `with-transaction` then rolled the level
  back, ROLLBACK at the outer level, and ROLLBACK TO and RELEASE nested, the outer committing.
  That's what ADR-0017 asks of a raise beside an open transaction.
- **The cause is one compile option, `ENABLE_MEMORY_MANAGEMENT`,** reproduced on Linux
  ([memory-management.sh](memory-management.sh), its output in
  [memory-management.txt](memory-management.txt)):
  - 3.54.1's amalgamation, checked against the `current` lane's pins, was compiled with the
    lane's line in these ways:
    - as it is;
    - plus every option Homebrew's lists and the lane's lacks
      (`../m4-prework/out/census-mac-brew-3.54.1.txt`, in PR #28);
    - that set without `-DSQLITE_ENABLE_MEMORY_MANAGEMENT`;
    - plus `-DSQLITE_ENABLE_MEMORY_MANAGEMENT` alone;
    - plus `-DSQLITE_ENABLE_STAT4` alone.
  - S3's NOMEM left the transaction open in exactly the two builds with the option, and ended it
    in the other three. So within Homebrew's set the option is necessary as well as sufficient.
  - `main`'s suite failed S3 on those two builds as it did on the Mac, with the same actual
    values, and passed on the other three. The fixed suite passed on all five.
- **Why only S3, in 3.54.1's source:**
  - A statement gets a statement journal only when it's a multi-row write that may abort:
    `usesStmtJournal = isMultiWrite && mayAbort`. Among the NOMEM rows only S3, an
    `insert … select` of three rows, is a multi-row write.
  - On a NOMEM, `sqlite3VdbeHalt` rolls back just the statement when it has a statement
    journal. If that rollback fails, SQLite rolls back the whole transaction and autocommit
    reads 1.
  - When an allocation passes the heap limit, SQLite calls `sqlite3_release_memory`. Built with
    `ENABLE_MEMORY_MANAGEMENT`, that frees page cache; without it, it does nothing.
  - So S3's statement rollback can succeed only in a build with the option, and that leaves the
    transaction open. S1, S2, S4 and the R rows have no statement journal. Each kept its case on
    every build where it met a NOMEM.
- **A second premise depends on the build.** With `ENABLE_MEMORY_MANAGEMENT` and
  `-DSQLITE_DEFAULT_PAGE_SIZE=65536`, S2, R3, R4 and [F] get no NOMEM at all: their call returns
  its value, and the rows fail by name. This was found by PR #30's review and reproduced here.
  It isn't a false pass, so nothing in the suite changes for it.
- **The fault:** the row fixed S3's case, ended, as the default builds showed it. AGENTS.md
  already says a failure's reach can't be told from its code or its SQL. It can't be told from
  the version either: one compile option, at the same release, gives the other case.
- **The fix, in this PR:** S3 takes the case its body's autocommit shows, and holds
  `with-transaction`'s exit to that case's whole outcome. It prints the case it met. S1, S2 and
  S4 kept their cases with Homebrew's library and on every build above, so the suite still holds
  both cases everywhere it was run. The plants are in
  [the mutation log](../../m3-mac-mutation-log.md).

## Still to run

- **The eight suites, again on the Mac,** with both libraries, once this PR's fixes are on a
  branch: `make test SUITES="…"` with the eight names.
- **M4's pre-work probes** ran on the Mac the same day. Their results are in PR #28, in
  `../m4-prework/`.
