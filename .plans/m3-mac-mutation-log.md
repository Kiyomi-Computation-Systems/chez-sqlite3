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
  - `tell-answered?`, `tell-available!`, `tell-kept?` and `tell-noted` are new.
  - Where `sqlite3_auto_extension` answered 21, `tell-available!` prints `UNAVAILABLE` and skips a
    row that needs the tell whole. `tell-kept?` and `tell-noted` drop only the one check of a
    row that reads it.
  - `clean-call`, `timer-sweep` and `timer-trial` take the check's flag.
- **The six `test-conveniences-pending-*` suites and `test-open-interleave`:**
  - The registration row passes on `registered` or on a refusal with its code, and fails on a
    raise.
  - Every row that reads the tell's notes goes through a gate. `test-open-interleave` has its
    own gate in the same shape, since it doesn't import the helper.
- **`tests/test-transaction-nomem.sps`:**
  - S3's row is `either`. It carries both cases' records, and `either-case` holds the outcome,
    whole, to the case the body's record shows.
  - It prints which case it met.

## The gate

The first build gated 33 rows whole. PR #30's read-only review found three faults in it:
- 15 of those rows mix checks, and skipping them whole lost the checks that don't read the tell;
- every nonzero code counted as a refusal;
- the refusal path unlocked the callbacks, which Chez 10.4.0 doesn't make safe.

The agent fixed all three, and reran every plant against the final suites. The table holds that
rerun.
- **18 rows are skipped whole:** the nine sweeps, query-row's check-out row, the escape row and the
  seven reset rows.
- **15 rows run with one check dropped:** the eight tell rows drop the noted count; the five timer
  rows drop the prepare bound; the two failing-call sweeps drop `new`, `not-the-plan` and the
  "notes nothing" half of `quiet`.
- **What passed on Apple's without testing anything:** the seven reset rows, the five timer rows'
  prepare bound, and the failing sweeps' whole-new-call checks. The 19 rows that failed there are
  the eight tell rows, the nine sweeps, the check-out row and the escape row.

Counts are per suite, in this order: execute, fold, query-row, query, script-even, script-odd,
open-interleave.

| Plant | Edit | Outcome |
|---|---|---|
| P1, a refusal | `(let ((rc (auto-extension …)))` → `(let ((rc 21))`, in both registrations | All seven pass. Skips 2/2/3/3/2/2/4; `UNAVAILABLE` lines 4/4/5/6/3/4/7, 33 in all; no fail. The timer rows and the failing sweeps run their other checks, the sweeps' second resumes as in Apple's log. **The lead reran it:** 33 lines, every suite passing. |
| P2, a gate that never decides | P1, and `unavailable!`'s `(tell-refused? answer)` → `#f`, in both files | All seven fail by name. The 19 fails are Apple's fails, less the registration row (diffed), and the deviation counts match Apple's log. |
| P3, the code ignored | P1, and `(if (eqv? rc 0) 'registered …)` → `(if #t …)` | The registration row passes, and the gate decides nothing. The same 19 rows fail. |
| P3b, the code dropped | P1, and `(list 'auto-extension-answered rc)` → `(list 'auto-extension-answered)` | The registration row fails in all seven, its actual `(auto-extension-answered)`. The other fails are P2's. |
| P5, another code | `(let ((rc 7))`, SQLITE_NOMEM | The registration row fails in all seven, its actual `(auto-extension-answered 7)`. Nothing is skipped or dropped, and the other fails are P2's. **The lead reran it:** 26 fails, in all seven suites. |
| P6, a library fault under a refusal | P1, and `conveniences.sls`:275 `(when held` → `(when #f`, the escaped give-back dropped | `execute!`'s timer row fails (`left (("insert into t values (?)" . ready)) 0`), and so do query-row's and query's timer and taken rows. Under the first build's gate, no row of execute's caught it. **The lead reran it:** those five rows fail, in three suites. |
| P7, the timer bound kept | P1, and the bound's `(not prepares?)` → `#f` | **Can't fail:** with no tell `prepares` is 0, and `(<= 0 N)` holds. So two plants stand in for it. |
| P7t, the noted count kept | P1, and `tell-noted`'s `(if kept? …)` → `(if #t …)`, in both files | Exactly the eight tell rows fail, each in its noted slot alone, `1` expected against `0`. The noted count is the one part dropped. |
| P7b, the bound live | On a library that registers: `(<= prepares …)` → `(< prepares …)`; then the same with the drop forced | All five timer rows fail, on `prepares` deviations alone. With the drop forced, all seven pass. The bound is live where registered, and the drop removes exactly it. |
| P4, a gate that refuses while registered | The first build: `(tell-refused answer)` → `(or (tell-refused answer) 21)` | Every suite exits 1, through the memory check: "the count is 8 bytes after the control's :memory: open and close". The skipped reset row never freed SQLite's list of entry points. This catch is a side effect, and works only where the library keeps a memory count. |
| P4b, the same, sparing the reset row | Refuse for every row not named `the entry…` | **Survives,** on both builds: all seven pass, with 26 `UNAVAILABLE` lines on a library that registered. An `UNAVAILABLE` line on a Linux lane is seen only by reading the log. This line first called that the gap the memory check has, but M3's closing review found the memory check's availability held, and the tell's not: the suites now register an idle entry point straight through the FFI, and hold the gate to its answer ([M3's closing review's log](m3-closing-review-mutation-log.md), part C). |

A missing library, outside the plants: the registration raises. Its row fails and shows the
raise, the gate decides nothing, and the tell rows fail.

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
  - on five builds of 3.54.1: defaults; Homebrew's options; Homebrew's options without
    `ENABLE_MEMORY_MANAGEMENT`; `ENABLE_MEMORY_MANAGEMENT` alone; and `ENABLE_STAT4` alone. S3
    left the transaction open on exactly the two builds with `ENABLE_MEMORY_MANAGEMENT`, and
    ended it on the other three.
- **A sixth build, `ENABLE_MEMORY_MANAGEMENT` with a 64 KiB default page size,** fails S2, R3, R4
  and [F] by name: they get no NOMEM. PR #30's review found it, and the lead reproduced it. It's
  recorded in the research README, and the suite doesn't change for it.
- **The eight changed suites,** run together: `test: ran 8, passed 8, failed 0, hung 0` with
  Guix's 3.53.1 and at the floor, with no `UNAVAILABLE` line. On Guix's, the seven gated suites'
  output is byte-identical to a run taken before any change.
- **`make test`,** Guix's 3.53.1: `test: ran 68, passed 68, failed 0, hung 0`.
