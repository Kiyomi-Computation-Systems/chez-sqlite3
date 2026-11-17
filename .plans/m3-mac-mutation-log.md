# M3's Mac run: mutation log

Evidence that the two fixes the Mac run asked for fail through the property each names. The
run and its findings are in [research/m3-mac/](research/m3-mac/README.md). Built on `main` at
`fcc9e7c`, in the worktree of branch `m3-mac-fixes`.
- **The tell's gate:** an Opus agent, from the lead's brief.
- **S3:** the lead.
- **The rerun:** the lead reran plant P1 and every unplanted run below.

Each plant was made in a copy of the tree, or in the worktree and copied back, then checked
with `cmp`. All runs used Guix's 3.53.1 unless a row names another library.

## What the PR changes

- **`tests/conveniences-pending.sls`:**
  - `tell-registered` unlocks its two callbacks when the registration is refused.
  - `tell-answered?` and `tell-available!` are new. The gate prints `UNAVAILABLE` and calls
    `test-skip`, where `sqlite3_auto_extension` answered a nonzero code.
- **The six `test-conveniences-pending-*` suites and `test-open-interleave`:**
  - The registration row passes on `registered` or on a refusal with its code, and fails on a
    raise.
  - Every row that reads the tell's notes goes through the gate. `test-open-interleave` has its
    own gate in the same shape, since it doesn't import the helper.
- **`tests/test-transaction-nomem.sps`:**
  - S3's row is `either`. It carries both cases' records, and `either-case` holds the outcome,
    whole, to the case the body's record shows.
  - It prints which case it met.

## The gate

**Which rows it gates: 33 in seven suites.** Every row that failed on Apple's library is gated.
So are 14 rows that passed there only because they read an empty tell:
- **The timer rows (5):** `timer-trial` holds `(<= prepares (call-prepares c))` with `prepares`
  from the tell's `noted-count`, and 0 is at most anything. The lead checked this in the code.
- **The reset rows (7):** they read the notes, and `(reset 0)` holds with nothing registered.
- **`test-open-interleave`'s two failing-call sweeps:** with no notes, no whole new call is ever
  counted as new.

So on a library that refuses the registration, those rows passed without testing anything. Now
they are named `UNAVAILABLE`.

| Plant | Edit | Outcome |
|---|---|---|
| P1, a refusal | `(let ((rc (auto-extension …)))` → `(let ((rc 21))`, in both registrations | All seven pass, with 33 `UNAVAILABLE` lines, the gated set exactly. Pass/skip: execute 4/4, fold 4/4, query-row 6/5, query 5/6, script-even 4/3, script-odd 4/4, open-interleave 4/7. **The lead reran it:** 33 lines, every suite passing. |
| P2, a gate that never skips | P1, and `(when rc` → `(when #f` in both gates | All seven fail by name: the rows that failed on Apple's, less the registration row. The deviation counts match Apple's log exactly (862, 11988, 1036, 2557, 3487, 944, 948, 2775). |
| P3, the code ignored | P1, and `(if (eqv? rc 0)` → `(if #t` | The registration row passes, and the gate doesn't skip. The 19 rows P2 fails fail again: the tells on a prepare count of 0, the sweeps on `too-few-interleavings past 0`, query-row's check-out, and the escape. |
| P3b, the code dropped | P1, and `(list 'auto-extension-answered rc)` → `(list 'auto-extension-answered)` | The registration row fails in all seven, its actual `(auto-extension-answered)`. The tell rows fail too. |
| P4, a gate that skips while registered | `(tell-refused answer)` → `(or (tell-refused answer) 21)` | Every suite exits 1, through the memory check: "the count is 8 bytes after the control's :memory: open and close". The skipped reset row never freed SQLite's list of entry points. This catch is a side effect, and works only where the library keeps a memory count. |
| P4b, the same, sparing the reset row | Skip all but the rows named `the entry…` | **Survives:** all seven pass, with 26 `UNAVAILABLE` lines on a library that registered. It's the gap the memory check has (ADR-0005, amended): an `UNAVAILABLE` line on a Linux lane is seen only by reading the log. Nothing new was built for it. |

A missing library, outside the plants: the registration raises. Its row fails and shows the
raise, the gate doesn't skip, and the tell rows fail.

## S3

| Plant | Edit | Outcome |
|---|---|---|
| M0, the old suite on a MEMORY_MANAGEMENT build | `main`'s suite, on 3.54.1 with `-DSQLITE_ENABLE_MEMORY_MANAGEMENT` ([memory-management.txt](research/m3-mac/memory-management.txt)) | S3 fails, outer and nested, with the Mac's actual values: autocommit 0 and 0. Homebrew's build reproduced on Linux. |
| M1, the records swapped | S3's two records in each other's place | S3 fails, outer and nested. |
| M2, the exit reads autocommit 0 | `transaction.sls`'s `autocommit-plan`: `(sqlite3-get-autocommit handle)` → `0` | **Survives this suite.** Beside an ended transaction the exit issues a ROLLBACK that fails, and a failed statement isn't tracked, so `issued` can't see it. `test-transaction` catches it, through the extended code, in rows [A] and [pE4]. |
| M3, the open case on this build | S3's SQL → S2's, `select randomblob(100000)` | S3 passes, printing "left the transaction open". The open branch passes on its own case. |
| M4, the open case with a wrong exit | M3, and `autocommit-plan`'s read → `1` | S3 fails, with S2, R3, R4 and R1u. The open branch catches an exit that issues nothing. |
| M5, the old row on the open case | `main`'s suite, with M3's SQL | S3 fails, as on the Mac. |

**Unplanted:**
- **The fixed suite passed with each library:**
  - at the floor and with Guix's 3.53.1, where S3 ended the transaction;
  - on four builds of 3.54.1: defaults, Homebrew's options, `ENABLE_MEMORY_MANAGEMENT` alone, and
    `ENABLE_STAT4` alone. S3 left the transaction open on the second and third, and ended it on
    the others.
- **The eight changed suites,** run together: `test: ran 8, passed 8, failed 0, hung 0` with
  Guix's 3.53.1 and at the floor, with no `UNAVAILABLE` line.
