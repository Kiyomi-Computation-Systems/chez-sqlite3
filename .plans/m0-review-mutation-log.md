# M0 closing review mutation log

Evidence that the fixes for M0's closing review fail through the property each one claims to
guard ([harness plan](2026-11-13-harness-plan.md) §6, which ends M0 with the review).

The review ran read-only, on Opus, over a snapshot of `main` at `37bb4c4`. Every reproduction
below was rerun here before it was fixed, each in a fresh copy of that snapshot, through the
copy's own `scripts/guix-env`.

Sonnet agents built the fixes, in parallel on disjoint files, and the `check-test-fails` case after
them, since it copies the whole tree. Every mutation ran in its own copy of the working tree, made
in the session scratchpad without `.git`, `build/` or `.claude/`, and the counts below are read from
the outputs. The final runs and the mutations marked *rerun here* were repeated here.

## The helper suite (`test-chez-sqlite3-testing`), finding 10

Two rows, rewritten:

- **"remove-temp-directory: it removes a directory and what is in it, and a path that is gone is
  no error".** Its second call was an argument to `list`, beside the `file-exists?` check, so what
  the row asserted depended on the order Chez evaluates arguments in. It is now a `let*`.
- **"capture-command: its directory is the only one in the scratch directory, with mode 700".**
  It compared the first 10 characters of `ls -ld` over a glob, so a second directory matching the
  glob passed. It now lists every entry in the scratch directory, with each one's mode, and
  compares that whole output with the one name and mode it expects.

Baseline: 60 passed, before and after.

| Mutation | Guards | New suite | The old suite, same mutation |
|---|---|---|---|
| H1 | the second removal of a path that is gone raises no error: `remove-temp-directory` raises when the path is gone | 59 passed, 1 failed: that row | the same row fails |
| H2 | the capture directory is the only one: `make-capture-directory` makes a second, its name with `x` appended | 53 passed, 7 failed, the mode row among them. *Rerun here*: 53 and 7 | 54 passed, 6 failed, and **the old mode row passed**: the glob matched both directories, and the real one sorts first |
| H3 | its mode is 700: made `#o755` | 59 passed, 1 failed: the mode row | the old mode row fails |

H1 shows the `let*` changed no meaning: the old row failed under it too. H2 is the hole the review
named.

## The floors' numeric forms (`test-check-floors`), finding 1

Reproduced first: the review's two lines, `curl -fsSLO …/sqlite-amalgamation-3450100.zip` and
`echo want-libversion-number-3045001`, in the `main` job's versions step, passed `make
check-floors check-ci` with exit 0.

- **Red run,** the new rows against the old rule: 301 passed, 17 failed.
- **Final run:** 318 passed. *Rerun here*: 318. `check-floors` on the tree passes with its usual
  line.
- **The review's two lines,** in a copy with the new rule: `check-floors: FAILED (problems: 2)`,
  naming line 273's `3450100` as the amalgamation form and line 274's `3045001` as the
  version-number form. That copy appended them at the file's end, inside the `nothreads` job, not
  in `main`'s versions block, as the fixes' review noticed. *Rerun here* where the review planted
  them, after the block's `kernel` line: refused as lines 132 and 133, exit 2.

Each mutation of `tests/floors.sls` failed the suite with exit 1:

| Mutation | Guards | Rows that failed |
|---|---|---|
| F7 | the version-number form is refused | 12: its three position rows, and the `workflow-sqlite-number` and `workflow-other-floor` fixtures among them |
| F8 | the amalgamation form is refused | 10: its three position rows, and the `workflow-sqlite-amalgamation` and `workflow-other-floor` fixtures among them |
| F9 | a form beside a letter or digit on its left is not found | 5, the `workflow-sqlite-digits` fixture among them. *Rerun here*: 313 and 5 |
| F10 | a form beside a letter or digit on its right is not found | the same 5 |
| F11 | the forms come from the floor in the file, not a fixed version | 1: the `workflow-other-floor` fixture, whose floor is 3.46.0. *Rerun here*: 317 and 1 |

F9 and F10 fail the same rows. Each of them holds a digit or letter on each side, in separate
cases, so each side's test is needed, but no row tells which side failed.

## The report steps (`test-check-ci`), finding 7

Reproduced first: with both of `main`'s report steps deleted, `check-ci` passed with exit 0, so
nothing held ADR-0006's "each run records the versions it used".

`check-ci` now requires, in job `main`, between its check-chez step and its make step and in this
order: "Report the versions this run uses", with its `run: |` block exactly its five lines; and
"Report the runner's SQLite", with `env: CHEZ` and its run line `scripts/ci/report-sqlite.sh`.
Each must occur once. A blank line added to the block is not seen, since `check-ci` skips blank
lines everywhere, and it changes nothing the shell runs.

- **Red run,** 21 new rows against `HEAD`'s `check-ci.sh`: 128 passed, 21 failed, every new row
  among the failures.
- **Final run:** 149 passed. *Rerun here*: 149. `check-ci` on the tree passes with its usual line.
- **The review's three workflows,** each in a copy with the new `check-ci.sh` (*rerun here*):
  - both report steps deleted: exit 1, `job main has 0 steps named "…", not one`, for each;
  - the floor's two numeric forms, and the split `GITHUB_ENV` write, each planted in the versions
    block: exit 1, `… has a run line that differs from the one check-ci holds`. That closes those
    two reproductions where they were planted, not the holes: ADR-0008's amendment closes the
    first, and ADR-0005's says why no text check closes the second.
- **Rows moved:** 24 rows planted their edits after the versions block's `kernel` line, from 10
  call sites, two of them `map`s over 13 banned words and 3 gates. The fixes' review counted them:
  with the new anchor's end marker broken, exactly 24 failed, 125 passed (*rerun here*). Each would
  now gain a second problem, since that block is held line for line. That is also why one of them
  failed by accident in the review, 127 and 1, when a line was added there. They now plant in
  `main`'s "Identify the runner image" block, which `check-ci` holds to no line.
- **Here, after the hand-back:** the order checks found the check-chez and make steps by their
  places in the list of required runs, `rq[1]` and `rq[2]`. A new entry ahead of them would have
  compared against the wrong steps. They are now found by their run lines. The suite passes 149.

Each mutation of `tests/check-ci.sh` failed the suite with exit 1:

| Mutation | Guards | Rows that failed |
|---|---|---|
| C10 | the versions step is required | 16: deleted, renamed, written twice, swapped, moved either way, and all 9 block rows |
| C11 | the SQLite step is required | 8: deleted, renamed, swapped, moved, its run line changed, its `env:` dropped |
| C12 | the order: after check-chez, before the make step, versions first | 4: swapped, the versions step moved after "Checks and suites" or before "Check the Chez", the SQLite step moved after "Checks and suites". *Rerun here* against the line-keyed version: 145 and 4 |
| C13 | no line added to the block | 2: a line, and a comment, at the block's end. *Rerun here*: 147 and 2 |
| C14 | no line changed | 5: a line at the start, one in the middle, one removed, one changed, one re-indented |

## A top-level raise (`test-check-ci`), finding 9

`(define base (make-process-temp-directory))` had no guard. With `TMPDIR=/no/such/dir`, the
suite exited 255, printing `Exception in capture-command: could not make a directory for the
command's output …`, and named no test. It is now guarded as `test-check-nothreads`' is: exit 1,
having printed `test-check-ci: no temporary directory for the rows' copies: Exception in
capture-command: …` on stdout, before any row. *Rerun here.* `TMPDIR` is set inside the container:
set before `scripts/guix-env`, it fails Guix itself.

## `check-ci` in `make test` (`check-test-fails`), finding 2

Reproduced by the review: with `check-ci` removed from `make test`'s prerequisites, `check-help`,
`check-test-fails` (all 10 cases) and `make test` (7 passed) all passed, and no `check-ci:` line
appeared.

`check-test-fails` gains a case, `ci`: the copy's workflow gives job `memory` a job-level
`continue-on-error: true`, which would let the gate fail and the run pass. `make test` must fail
with exactly these lines, the line number read from the planted file, and run no suite:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (1 checked)
check-ci: .github/workflows/ci.yml:164: job memory has the key "continue-on-error", which is not one of name, runs-on, timeout-minutes, steps
check-ci: FAILED (problems: 1)
```

- **Final run:** `make test failed, as it must, in all 11 cases`. *Rerun here*, with `make test`
  (7 passed), `check-clean`, and `check-memory-gate` in all 36 cases.

| Mutation | Guards | Result |
|---|---|---|
| T29 | `make test` runs `check-ci`: dropped from the `test:` prerequisites | exit 2, naming `ci`: `make test exited 0`, and its lines differ. The other 10 cases passed. *Rerun here*: exit 2 |
| T30 | the plant changes the workflow: its `sed` replaced by `cat` | exit 2: `ci: the plant did not change .github/workflows/ci.yml, so it plants nothing` |

`check-help` is the one prerequisite of `make test` with no case here. CI's `main` job runs it by
name, as its make line's first target, and `check-ci` holds that line whole.

## The fixes' review

The commit was reviewed read-only, on Opus, against a snapshot of it. No blocker, two major
findings and eleven minor, every one checked here. Every fix closed its original reproduction, and
the full harness passed in the reviewer's copy.

**Major, both reproduced here, then fixed by Sonnet agents on disjoint files:**

- **Finding 10 was half closed.** The row "remove-temp-directory: only an absolute path other
  than /, and it runs no rm for any other" built a `list` whose fourth argument checks for
  `rm-log`, beside the three refusals whose effect it observes. Under the reviewer's mutation,
  where `remove-temp-directory` runs `rm --version` first, `--program` gave 59 passed and 1
  failed, and `interpret` gave **60 passed**. *Rerun here.* The row is now a `let*`. The agent
  read the whole file for any other call or `let` whose arguments both act and observe, and found
  none.
- **Finding 1's boundary was not held against its complement.** With `digit-or-letter?` written
  as `0..Z ∪ a..z`, which takes `: ; < = > ? @` for letters, the suite passed 318 of 318, and
  `check-floors` passed `echo SQLITE_VERSION_NUMBER=3045001`. *Rerun here.* Four rows now put
  every character from U+0001 to U+007F but the newline, and `é`, `α`, U+00A0 and U+1F600, beside
  each form on each side. Each asserts the whole list of characters for which the form is not
  found: the 62 ASCII letters and digits. The final run passed 322.

| Mutation | Guards | Result |
|---|---|---|
| H4 | the third `remove-temp-directory` row observes after it acts: `rm --version` runs before the refusals | 59 passed, 1 failed, compiled and interpreted. *Rerun here*, both ways |
| F12 | the boundary is the ASCII letters and digits: `0..Z ∪ a..z` | 318 passed, 4 failed: the four boundary rows. *Rerun here* |
| F13 | the upper-case range is in the boundary: dropped | 317 passed, 5 failed: the four, and "an upper-case letter beside a form is a letter too" |
| F14 | `_` is not in the boundary: added | 317 passed, 5 failed: the four, and "a form beside a dot, a dash, an underscore or a space is found" |
| C15 | the SQLite step not before the check-chez step: line 248's check deleted | before the new row, 149 of 149 passed. Now 149 passed, 1 failed: "the SQLite step moved before Check the Chez". *Rerun here* |

C15 was the one survivor of a sweep: each of `mainsteps`' five order checks was deleted in turn,
and the other four each failed at least one row. The new row's whole output holds line 248's
problem line, which the other checks' lines don't stand in for.

**Minor, fixed in the records:**

- "Refuses a floor in any form" overstated. These pass `check-floors` and `check-ci`: a form
  beside a letter (`v3450100`, `3045001L`, `sqlite3450100`), by the boundary's design; other
  spellings of the dotted text (`3_45_1`, `3,45,1`, `(>= 3.45)`); and anything outside
  `.github/workflows`. ADR-0008 and `global-constraints.md` now say so, and M1's plan extends
  `check-floors` to `scripts/ci/` before the script that fetches the amalgamation is written.
- ADR-0006's report steps are held, not what `report-sqlite.sh` prints: replaced by `exit 0`, it
  passed `check-ci`.
- Finding 4's conclusion, that `check-ci` loosens per job and never for the whole file, is now in
  ADR-0005, not only in M1's plan to come.
- This log's "15 rows moved" was 24; and the rerun of the review's two floor lines had appended
  them at the file's end, inside `nothreads`. Both are corrected above.
- ADR-0005's "GNU Make 4.3" was the host's. The container's is 4.4.1, and gives the same origin.
- The harness plan's table still listed three prerequisites of `make test` and ten plants.
- `workflows-problems`' comment in `tests/floors.sls` named two of its rules; it names them all.

**Not settled by a run here:** the suites under mawk, which CI's runner uses. The host's `awk` is
mawk 1.3.4. Under it, `tests/check-ci.sh` passes the real workflow, and refuses the review's
three planted workflows, each with exit 1. The suites themselves run in the container, where awk is
gawk, so CI's first run on this branch is their first under mawk.
