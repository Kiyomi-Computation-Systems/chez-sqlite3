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
| [memory-management.sh](memory-management.sh) | S3's Mac case, reproduced on Linux: 3.54.1 built four ways |
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
fault in a test, not in the library. The library behaved correctly in every failing row.

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
- **Fourteen rows passed there without testing anything.** The timer rows, the reset rows and
  `test-open-interleave`'s failing-call sweeps read the tell's notes too, and an empty tell
  satisfies them: a prepare count of 0 is at most any bound.
- **The fix, in this PR:** where registration is refused, each of the 33 rows that need the tell
  prints `UNAVAILABLE` and is skipped, never passed, as the memory check is on the same library
  (ADR-0005, amended). The sweeps are still run on the Mac by Homebrew's library. The plants are
  in [the mutation log](../../m3-mac-mutation-log.md).

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
  - 3.54.1's amalgamation, checked against the `current` lane's pins, was compiled four ways
    with the lane's line: as it is; plus every option Homebrew's lists and the lane's lacks
    (M4's pre-work, `census-mac-brew-3.54.1.txt`); plus `-DSQLITE_ENABLE_MEMORY_MANAGEMENT`
    alone; plus `-DSQLITE_ENABLE_STAT4` alone.
  - S3's NOMEM left the transaction open in the second and third builds, and ended it in the
    first and fourth.
  - `main`'s suite failed S3 on those two builds as it did on the Mac, with the same actual
    values, and passed on the other two. The fixed suite passed on all four.
- **The fault:** the row fixed S3's case, ended, as the default builds showed it. AGENTS.md
  already says a failure's reach can't be told from its code or its SQL. It can't be told from
  the version either: one compile option, at the same release, gives the other case.
- **The fix, in this PR:** S3 takes the case its body's autocommit shows, and holds
  `with-transaction`'s exit to that case's whole outcome. It prints the case it met. S1, S2 and
  S4 passed with Homebrew's, so the suite still holds both cases on every library measured. The
  plants are in [the mutation log](../../m3-mac-mutation-log.md).

## Still to run

- **The eight suites, again on the Mac,** with both libraries, once this PR's fixes are on a
  branch: `make test SUITES="…"` with the eight names.
- **M4's pre-work probes,** [mac.md](../m4-prework/mac.md): `m4pre-mac.tgz` isn't in yet.
