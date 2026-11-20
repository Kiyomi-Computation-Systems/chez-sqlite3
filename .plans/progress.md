# Progress ledger

Where chez-sqlite3 stands. Read it with [global-constraints.md](global-constraints.md) before
starting slice work. When a slice merges, update **Now** and add a close-out under **Close-outs**,
newest first.

## Now

- **M0 is done:** PRs #1 to #6.
- **M1 is done:** its slices 0 to 5 are PRs #7 to #11 and #13, its owed fixes PR #12, and its
  closing review PR #15, `1b2f688`, each squash-merged in order with CI passing in every job.
- **M2 is done,** each PR squash-merged in order with CI passing in every job:
  - slice 0, as PR #14, `3d24cce`: the M2 plan, ADR-0014 and ADR-0015, and their amendments to the
    older records;
  - slice 1, the pure core, as PR #16, `e6b2462`;
  - slice 2, the bindings, as PR #17, `f2ffa0e`;
  - slice 3, statements, as PR #18, `0572267`;
  - slice 4, values, as PR #19, `00ab0c8`;
  - its closing review, as PR #20, `bb7feaa`.
- **The maintainer accepted ADR-0010 to ADR-0015 and their amendments:**
  - on 2026-11-14, all of them to that day;
  - on 2026-11-15, ADR-0015's slice 1 and slice 4 amendments, ADR-0005's and ADR-0011's slice 2
    amendments, and ADR-0014's slice 3 amendment.

  ADR-0014's slice 1 amendment and ADR-0005's split record the maintainer's own choices ("Match
  SQLite"; "Split in #19, rest after").
- **M3 slice 0 is done:** the M3 plan, ADR-0016 to ADR-0020 and the plan's amendments to the
  older records, as PR #21, `3e2460b`, squash-merged with CI passing in every job.
- **The maintainer accepted ADR-0016 to ADR-0020** on 2026-11-15, with the M3 plan's Q1 to Q15
  settled, and the plan's amendments to the older records (its §10), applied in M3 slice 0, the
  same day ("Accept all"); and M3 slice 1's amendments to ADR-0016, ADR-0017, ADR-0018 and
  ADR-0020, the same day ("Accept all"); and M3 slice 3's amendments to ADR-0014, ADR-0016,
  ADR-0017 and ADR-0020, on 2026-11-16 ("Accept all"); and, the same day, slice 2's to ADR-0002
  and ADR-0005, slice 4's to ADR-0017, and slice 5's to ADR-0012, ADR-0016, ADR-0018 and
  ADR-0020 ("Accept all"), and to ADR-0019's decision 11 ("Keep, amend"); and slice 6's to
  ADR-0005, ADR-0017 and ADR-0019, on 2026-11-17 ("Accept all"); and M3's closing review's to
  ADR-0005 and ADR-0016 to ADR-0020, the same day ("Accept all").
- **Branch protection is on for `main`** (the maintainer asked, 2026-11-14). All six jobs are
  required: `main`, `memory-1`, `memory-2` and `nothreads`, and, since M1 slice 5 merged, `floor`
  and `current`. M3 slice 6 replaced `memory` with `memory-1` and `memory-2`, and the required checks
  were swapped as it merged, 2026-11-17 (the maintainer's, ADR-0005, amended).
  Since M1's closing review, it is strict too: a PR must be up to date with `main` before it
  merges. Force pushes and deletion are refused. Admins can override.
- **M3 slice 1 is done:** the pure core, as PR #22, `d91ae72`, squash-merged with CI passing in
  every job.
- **M3 slice 2 is done:** the bindings, as PR #23, `599a43d`, built beside slice 1 by the M2
  session, squash-merged with CI passing in every job.
- **M3 slice 3 is done:** the conveniences, the counters and the cache, as PR #24, `f496cf5`,
  squash-merged with CI passing in every job.
- **M3 slice 4 is done:** transactions, as PR #25, `aa89dde`, by the M2 session, squash-merged
  with CI passing in every job. Slices 1 to 4 merged in order, each rebased onto the squash before
  it (the maintainer, 2026-11-16: "Run all four").
- **M3 slice 5 is done:** the settings, with part D's fix of slice 3's conveniences, as PR #26,
  `cc8c60d`, squash-merged with CI passing in every job.
- **M4's pre-work is merged:** the variadic `db_config` probe and the census, research only, as
  PR #27, `fcc9e7c`, by the M4 session
  ([research/m4-prework/](research/m4-prework/README.md)).
- **M3 slice 6 is done:** the interrupt, contention and the memory job's shards, as PR #29,
  `988cf2b`, squash-merged with CI passing in all six jobs. The maintainer's order, 2026-11-15:
  slices 1 and 2 in parallel, then 3, then 4 (the M2 session) and 5 in parallel, then 6, each its
  own PR, stacked on the one before.
- **The Mac run's fixes are merged,** as PR #30, `c0a5408`, by the M4 session: two faults in the
  suites, below. **M4 pre-work's answers are merged,** as PR #28, `e590fdc`, by the M4 session: the
  maintainer's answers to Q1, Q3 to Q10 and Q13, and the Mac step's results
  ([research/m4-prework/](research/m4-prework/README.md)).
- **M3's closing review is done,** the last of M3's done conditions
  ([the M3 plan](2026-11-15-m3-plan.md), §6), as PR #32, by the M3 session, squash-merged with CI
  passing in every job. **M3 is done.**
- **M4 slice 0 is done:** the plan, ADR-0021 and their amendments, as PR #31, `87e762c`, by the
  M4 session, written beside M3's closing review, plans and records only, squash-merged with CI
  passing in every job (the maintainer, 2026-11-17).
  - **The plan's questions:** the maintainer settled Q14 to Q16 on 2026-11-17, each the
    recommendation: "The rule's names", "Same as leaving it out" and "An absolute path". Asked
    again about Q14 and Q15 together, from a user's side, the answer was "Yes, as shown".
  - **The records:** the maintainer accepted ADR-0021 and the plan's amendments the same day
    ("Accept all").
- **M4,** extensions and `db_config`, its slices led by the M3 session (the maintainer,
  2026-11-17: "This session leads"). Slices 1, 2 and 5 were built side by side, each in a worktree
  of its own ("1, 2 and 5 together"); slice 3 follows 1 and 2, and slice 4 follows 3.
  - **M4 slice 1 is done:** the pure core of the four `db_config` settings and
    `&sqlite-extensions-unavailable`, as PR #35, `d1792e4`, squash-merged with CI passing in every
    job. The maintainer accepted its ADR-0021
    amendment ("Accept"), with a code that names no error raising an assertion violation
    ("Assertion violation"), 2026-11-17.
  - **Slice 2,** the bindings and `check-variadic`, is done, as PR #37, `1735a66`, below; the
    maintainer accepted its amendments to ADR-0001, ADR-0002 and ADR-0011 (2026-11-17, "Accept
    all"). **Slice 5,** FTS5 and JSON, is done, as PR #40, `7dac918`, below. **Slice 3,** the
    four settings at open and the opt-in's check, is done, as PR #44, `c92d397`, below. **Slice
    4,** `load-extension!`, is done, as PR #45, `a795fa2`, below. **The maintainer's Mac run for
    slices 3 to 5** ran on 2026-11-18, below, and its one fault, a row of the suites, is fixed in
    PR #47, `34721b4`. **M4's closing review is done,** the last of M4's done conditions
    ([the M4 plan](2026-11-17-m4-plan.md), §6), as PR #48, `79fa1ac`, by the M3 session,
    squash-merged with CI passing in every job, and the Mac run after it passed, PR #49, below.
    **M4 is done.**
  - **M5's pre-work** is merged, by the M4 session, as PR #41, `2102131`: the release's facts and
    the maintainer's questions.
  - **The close fix is done,** as PR #36, `3488963`, below: slice 5's FTS5 suite found
    `close-database!` refusing every connection that had used an FTS5 table, FTS5's own statements
    counted as untracked. The maintainer chose "Close first, count on failure", in a PR of its own
    before slice 5, then "Document it, with a row" and "Vouch only for ours" (2026-11-17), and
    accepted its amendments to ADR-0005, ADR-0012, ADR-0014 and ADR-0019 to ADR-0021 ("Accept
    all").
- **Now: M5,** the release. Its pre-work is merged, as PR #41, `2102131`, by the M4 session
  ([research/m5-prework/](research/m5-prework/README.md)), and refreshed at M4's end as PR #50,
  the maintainer's "Refresh + audit, one PR" (2026-11-19). **Its ten questions are answered**
  (the maintainer, 2026-11-20), each the recommendation
  ([the answers](research/m5-prework/README.md#the-maintainers-answers-2026-11-20)): a site from
  v0.1.0, a Release for every tag, `.plans/` and AGENTS.md left out of the archive, no Akku at
  0.1.0, four pages, the platforms that ran, a comment sweep, a README fragment held to a docs
  twin, `timeout-minutes: 120` for the memory jobs, and the tag signed with chez-curl's key.
  **M5's plan is next,** written by the M3 session and checked read-only by the M4 session (the
  maintainer, 2026-11-20: "This session: answers, then plan").
  - **The refresh ran:** a program against a bare archive's `src`, with nothing built; the
    changelog reader on link references, with a control that fails by name; and four CI runs'
    memory jobs, `memory-1` at 42 and 44 of its 60 minutes on the last two (Q9).
  - **The records' 36 promises to the reference:** 32 kept, 3 partly and 1 superseded, its
    replacement kept. The three gaps are the docs slice's (the note, §9).
- **The maintainer's hand runs on the Mac** (macOS 26.7.1, 2026-11-14):
  - **On slice 4's tree:**
    - The first runs failed six `check-chez.sh` rows that assumed `…/bin/scheme`.
    - Then seven rows failed, from two causes: no `/proc`, and Apple's library answering
      `SQLITE_CANTOPEN` to an open of a FIFO.
    - All were fixed in slice 4's branch ([traps.md](traps.md)).
    - The rerun passed 25 of 25 suites with Apple's 3.51.0, found by discovery; each suite that
      loads libsqlite3 named the memory check unavailable. With Homebrew's 3.54.1 through the
      override, it passed 25 of 25, the check passing.
    - `check-dev` passed. `FULLMUTEX` serializes a connection on Apple's `THREADSAFE=2` build
      (ADR-0010, amended).
  - **On `main` at `497d45b`,** after slice 5:
    - 25 of 26 suites passed, with Apple's library and with Homebrew's.
    - `test-ci-sqlite`'s two rows for `build-sqlite.sh`'s success failed on both: "chez: command
      not found". The Makefile's default `CHEZ` there is the bare name `chez`, and those rows
      narrow `PATH` to their shims.
    - The rows now get the Chez by its path, on this branch ([traps.md](traps.md)).
    - `check-dev` passed, and `check-test-fails` held in all 13 cases.
  - **On `m1-closing-review` at `0c2aad2`,** after the closing review's fixes, 26 of 26 suites
    passed with Apple's library and with Homebrew's. `test-ci-sqlite` passed 80, its build rows
    included, and so did the new depth and engine rows.
  - **On `m1-closing-review` at `594ef6a`,** after the second review's fixes, 26 of 26 suites
    passed with Apple's 3.51.0 and with Homebrew's 3.54.1. `test-connection` passed 63, its
    re-entry rows included, and `test-check-ci` passed 397, so BSD grep reads the new rules as
    GNU grep does.
- **The maintainer's Mac run after M4's closing review** (arm64, Chez 10.4.1, 2026-11-19), on
  `main` at `79fa1ac` by [research/m4-mac/closing-review.md](research/m4-mac/closing-review.md),
  the maintainer's "Write it up now": `make test` passed 92 of 92 with Apple's 3.51.0 and with
  Homebrew's 3.54.1.
  - The timer's probes printed what Chez 10.4.0 printed, so `$tc-field` reads the same there.
  - Homebrew's run read all 32 low-trip tallies, as Linux does. Apple's read the 19 that need no
    `sqlite3_auto_extension`, through the forcing VFS and the trace, and named the rest
    unavailable, matching a Linux stand-in for its refusal suite by suite but one, explained.
  - A missing `$tc-field`, stood in on Linux, failed exactly the 29 low rows by name.
- **The maintainer's Mac run for M4's slices 3 to 5** (macOS 26.7.1, arm64, 2026-11-18), on
  `main` at `ec48a9d`, by the M4 session's
  [research/m4-mac/slices-3-5.md](research/m4-mac/slices-3-5.md)
  ([its results](research/m4-mac/README.md)):
  - **With Homebrew's 3.54.1,** `make test` ran 81 and passed 81: the extension built by Apple
    clang with `-Wall -Werror -dynamiclib`, the load suites 44 and 14, dyld's failure messages the
    same across two loads, every op moved off its start, FTS5 19 and JSON 16.
  - **With Apple's 3.51.0,** 80 of 81 passed: `defensive` on at start, the load rows unavailable
    and the opt-in's refusal asserted, FTS5 19 and JSON 16. `test-load-extension-engines`' build
    row read `#f`: its `assq` raised on the build's `(unavailable)` ([traps.md](traps.md)). A
    SQLite built `-DSQLITE_OMIT_LOAD_EXTENSION` reproduced it on Linux, and PR #47, `34721b4`,
    fixes the row, by the M4 session, as PR #30 fixed M3's run's faults.
  - **`run-dyld.sh`:** `DYLD_LIBRARY_PATH` redirected both absolute paths by their leaf names, the
    library discovery found, `sqlite-library-path` still naming Apple's, and an extension's; the
    fallback variable didn't. On Linux `LD_LIBRARY_PATH` redirected neither (Open, below).
- **The maintainer's Mac run for M3** (macOS 26.7.1, arm64, Chez 10.4.1, 2026-11-17), on PR #29's
  branch ([research/m3-mac/](research/m3-mac/README.md)):
  - **With Apple's 3.51.0,** `make test` ran 73, passed 66 and failed 7: the six
    `test-conveniences-pending-*` suites and `test-open-interleave`. Apple's library refuses
    `sqlite3_auto_extension` (21), so the suites' tell never noted a prepare.
  - **With Homebrew's 3.54.1,** 72 of 73 passed. `test-transaction-nomem`'s S3 expected its NOMEM
    to end the transaction; under `-DSQLITE_ENABLE_MEMORY_MANAGEMENT`, Homebrew's build among
    them, it leaves the transaction open. The M4 session reproduced that on Linux.
  - Both were faults in the suites, fixed in PR #30: where the tell is refused, 33 rows report
    what they can't check, and S3 takes the case its autocommit shows. The maintainer's rerun of
    the eight suites from #30's branch passed with both libraries.
  - Slice 6's suites passed with both libraries. **P4,** the busy wait's grain, read 284 ms on
    Apple's library and 288 ms on Homebrew's, for a 250 ms timeout: both sleep in milliseconds.
- **The maintainer's Mac run for M2** (macOS, arm64, 2026-11-15):
  - **On `m2-slice-4-values` at `7f9225f`, with Apple's 3.51.0,** 36 of 37 suites passed.
    `test-statement`'s row for a refused SQL's prepare-time effect expected `cache_size` to start at
    `-2000`, Guix's default, and Apple's library starts at 2000. The row now sets its own base
    first ([traps.md](traps.md)). `check-dev` passed, and `check-test-fails` held in all 13 cases.
    Homebrew's run didn't happen: the command block's `#` comments held apostrophes, and zsh read
    them as a quote ([traps.md](traps.md)).
  - **On `23aa075`, 37 of 37 passed with Apple's 3.51.0, and 37 of 37 with Homebrew's 3.54.1:**
    - with Apple's, which keeps no memory count, each suite named the memory check unavailable,
      and `test-statement-values-nomem` named its 9 NOMEM rows unavailable and passed 4;
    - with Homebrew's, the memory check passed in every suite that loads libsqlite3, and the NOMEM
      suite passed all 13;
    - so what CI can't reach held on the Mac: `sqlite3_bind_text64`'s `unsigned-8` on Apple's
      arm64 ABI (`test-native`, 82 of 82), the busy-timeout waits, the two-engine sweeps, and NOMEM
      caused for real.
- **Open:**
  - **M4's closing review settled its four open items** (below):
    - the DYLD redirect, documented, the maintainer's "Document it";
    - the no-load lane, in CI's `current` job;
    - the loading suites, split into nine;
    - the sweeps' low passes, with no control run.
  - **Linux arm64** stays open from the M4 plan's §7: the variadic binding there is chez-curl's
    measurement, not ours.
  - **`check-ci` passes a cache save, or a Chez build, with its `if:` removed:** the no-load save,
    current's SQLite save and current's Chez save (the M4 session's check of PR #48). It did so at
    `34721b4` too, so it predates the no-load lane. A save without its `if:` only saves again.
  - **"At most 11 children" a loading suite is a count, not a check:** nothing fails a suite that
    grows past it. The gate's `SLOW` line is the only bound.
  - **The memory jobs' margin:** with the low passes and the split, each shard projects at about 30
    suite-minutes a run against its 60-minute timeout. Read the first runs of `memory-1` and
    `memory-2` before calling it safe.
  - **`test-transaction-interrupt`'s cost is settled.** It took 318 s on CI on `main` at
    `c0a5408` (run 44083802043), past the 150 s that ADR-0005's slice 6 amendment made a finding.
    On the memory-mutex device, from M3's closing review, it took 11 s on PR #32's CI, and 15, 11,
    12 and 12 s on `main`'s runs 44325663052, 44305936182, 44298034354 and 44293661574. The risk
    is closed.
  - Brief D3 to D6 are settled (the M2 plan, §2), and M2 split `test-library-loading` in #19
    (ADR-0005, amended).

## Close-outs

### 2026-11-18 — M4's closing review and its fixes (PR #48)

- **Reviewed** by two Opus reviewers, read-only, on `34721b4`, all of M4, on disjoint dimensions:
  A the code and its seams, B the tests, the gate, CI and the records. No blocker. The lead
  reproduced each finding before any fix was briefed (the four logs `m4-closing-review-*-log.md`).
  - **The code (A):**
    - `call-with-open-handle`'s owner check, M1's, ran outside its section, and Chez resumes an
      engine's remainder on any thread: the C call's section ran on threads 8, 9 and 10 in 3 of
      12 trials;
    - `load-extension!`'s wrong-thread refusal named `database-extension-loading?`;
    - a refused close inside `call-with-database` loses an engine, which has been documented since
      M1's closing review; M4 adds an extension's leftover statement as a way to reach it;
    - an init failing twice beside a held row loses its reason the second time;
    - the records' and docs' sentences that macOS's `DYLD_LIBRARY_PATH` makes untrue;
    - for every claim-holding call, M3's and M4's, the code after its last section is harmless.
  - **The tests, the gate and the records (B):**
    - three plants that advance a claim just after its section passed every sweep, and did real
      harm with collect requests falling: settings applied twice, a row inserted twice;
    - eight suites judged an interleave trial by a control run, which AGENTS.md forbids;
    - `test-conveniences-resumed` bounded by `last-held`, across fuels;
    - `test-library-loading-real` at 258 and 264 s on CI;
    - the records' lags: the global constraints, the plan's §6 to §8, the ledger's hashes, and
      about 50 commits squash merges dropped.
- **Decided by the maintainer** (2026-11-18), each from a picker: "Plan it now"; DYLD, "Document
  it"; the no-load lane, "In CI's current job" and "The whole make test"; the lost engine, "Keep
  it, document M4's case"; the Mac recheck, "Accept the Linux reproduction"; the twice-failing init,
  "Document it".
- **Fixed here,** by four Opus builders in parallel, each in its own worktree, on disjoint files:
  - **C, the code and the docs:** the owner compared inside `call-with-open-handle`'s section,
    seven rows; the opt-in read with the caller's `who`, three rows; the reference's "Which
    SQLite", the DYLD caveat, an extension's leftover statement and the twice-failing init;
    `test-native`'s round trip chosen by the op's own answer;
  - **D, the sweeps:** a low pass in every claim-holding sweep of M3's and slice 3's, a 32 KiB
    allocation where a pass must reach an exit, bounds by the sweep's own clean trials, no control
    run; five new suites for the pending fold's and script's low passes. No fault in `src/`;
  - **E1, the no-load lane:** `build-sqlite.sh` and `check-sqlite.sh --no-load`, FTS5 kept, 40
    options; five steps in `current`; `check-ci` keyed by build;
  - **E2, the loading suites:** three into nine, at most 11 children each, every row kept;
  - **the lead:** the merge; the old layout's comments outside the builders' files; the preflight
    row's expected value under a guard, which E2's plant H7 had killed the suite through; the
    records.
- **Watched failing:** each builder's new or changed rows, against `34721b4` or a plant:
  - C's 11 plants;
  - D's: B's three, two of its own and six controls;
  - E1's 50 plants;
  - E2's 240, of which 67 are caught by both layouts, and none lost.

  The lead's own: 3 of C's, B's two against D's suites, 3 on the workflow, 2 on the dealing, and H7
  against the guard, all caught. `with-transaction`'s claim taken just after the BEGIN's section is
  equivalent: the BEGIN's step reads the ended flag in its own section.
- **Libraries:** on the merged tree, `make test` 92 of 92 on Guix's 3.53.1, the floor (3.45.1),
  3.54.1, and 3.54.1 built without extension loading; `check-variadic` all 7 steps. After the
  check's second round, the same on all four, with `check-variadic` and `check-ci` passing.
- **CI** (run 44460844478, at `a323224`): every job passed. The no-load lane's first run built in
  22 s and passed 92 of 92; `memory-1` took 31 min and `memory-2` 35 min, under the 60-minute
  timeout, the largest suite 161 s.
- **Times** under the gate, Guix's library:
  - the nine loading suites 52 to 85 s, against the old `-real`'s 195 to 248 s;
  - `test-open-db-config-engines` 136 to 138 s here and 161 s on CI, up from 57 s;
  - the pending script's low passes about 92 s each.

  Each memory job projects at about 30 suite-minutes a run, under its 60-minute timeout.
- **Checked by the M4 session** against the plan, read-only, at `a323224`: no blocker. Fixed after
  it, in a second round:
  - **`close-database!` compared its owner outside its section,** F2's defect in the one verb the
    first fix missed: a close resumed on another thread closed the connection there. It now
    compares inside a section around the latch's close (builder C);
  - **ten low rows asked nothing of their reach,** and some reach checks the high pass met too, so
    a trip slipped to 256 KiB passed every suite. Each low row now proves its reach through the
    engine's timer and a forced allocation, and the slipped trip fails all 29 and no other row
    (builder D, the maintainer's "Keep it, tests only" for `$tc-field`);
  - **two claim-holding sweeps had no low pass,** and `with-transaction`'s claim rows used a fixed
    window, a caller's count (builder D);
  - **five records were missing from the PR,** written after the records branch was merged and
    never committed: the lead's error, now merged;
  - **the shards were unbalanced,** 1,507 s against 1,763 s, since D and E2 placed their suites
    apart; two suites move to shard 1, which with both follow-ups projects about 1,770 s against
    1,750 s;
  - and the docs' twice-failing init, the override's "no search", and the records' figures and
    citations.
- **Rechecked by the M4 session** at `6fe29c8`: one major. `test-transaction-engine`'s pending low
  row caught its plant, a claim advanced just after its section, in 11 of 21 runs, and its reach
  checks passed either way; `script-low-3` caught its plant in 11 of 15. Fixed in builder D's third
  round:
  - the timer's credit had counted sections an expiry's unwinding forced, with the timer off, at
    exits no run stopped at; it now credits a section only where its own callback saw the timer
    running;
  - the pending row judges each run's answer, which showed the plant in 27 to 35 trials a run where
    the state showed it in 1 or 2, and counts the interleaving the plant needs, R holding the body's
    statement, R1 at the step's forced exit, R's second run refused;
  - the script low suites force each prepare and count R1 at the first prepare's exit, R's second
    run refused;
  - each proven in 20 runs, 10 at once and 10 one after another: both plants caught 20 of 20,
    correct code passing 20 of 20, rerun by the lead.
- **The records,** accepted by the maintainer, 2026-11-19 ("Accept all"), and refined after the M4
  session's check: ADR-0010's amendment gains the close, ADR-0016's the reach checks, `$tc-field`
  and the claim window, and AGENTS.md's low-pass bullet how a low row proves its reach:
  - ADR-0002: DYLD;
  - ADR-0005: the no-load lane, the split and the low passes' cost;
  - ADR-0010: the owner in the section;
  - ADR-0016: every claim-holding sweep's low pass, and no control run;
  - ADR-0021: what the review corrected;
  - the plan: §6 to §8 settled, and Q16's reason;
  - AGENTS.md: three bullets, the low pass, the chunk and the owner's thread;
  - the global constraints;
  - `traps.md`: four entries, the dropped commits among them;
  - this ledger.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Review A, the code, and its follow-up | Opus | 387k and 456k | 105 and 32 | 29 and 14 min |
  | Review B, the tests and the records | Opus | 441k | 152 | 44 min |
  | Review B's helper, the records | Opus | 322k | 114 | 20 min |
  | Builder C, the code and docs | Opus | 398k | 185 | 47 min |
  | Builder D, the sweeps | Opus | 886k | 265 | 146 min |
  | Builder E1, the no-load lane | Opus | 451k | 125 | 55 min |
  | Builder E2, the loading split | Opus | 501k | 261 | 74 min |
  | Builder C, after the check | Opus | 443k | 35 | 15 min |
  | Builder D, after the check | Opus | 434k | 184 | 93 min |
  | Builder D, after the recheck | Opus | 619k | 278 | 223 min |

- **Learned:**
  - **A check of the calling thread vouches only for the section it is made in.** Engines make a
    thread a property of a section, not of a call.
  - **A low pass needs both a low trip and an allocation big enough to trip it.** The trip is read
    a chunk at a time, so a small call meets its requests at the same point at every fuel.
  - **A plant that reaches a branch but fails for an expected reason hides a crash there;** the
    no-load lane runs each such branch green on every run.

### 2026-11-18 — M4 slice 4: `load-extension!` (PR #45)

- **Built** by an Opus builder from `c92d397`:
  - `(chez-sqlite3 private extension)`: `load-extension!`, exported from `(chez-sqlite3)` (70
    names), and `load-extension/with`, for a stand-in load and copy;
  - `tests/extension.c`, the research's four variants with `chez_half` and `chez_inits`, built by
    `tests/extension-build.sls` with `$CC -Wall -Werror -shared -fPIC`, or `-dynamiclib` and
    `.dylib` on a Mac;
  - new `test-load-extension` (44 rows) and `test-load-extension-engines` (14), in
    `MEMORY_SUITES_2`. Shard 2 was the lighter over `main`'s last three runs, 3,041 s against
    3,406 s, and on the latest, `c92d397`'s, the only one at the current layout (1,114 s against
    1,371 s);
  - `refusal-probe.sps`' `--loads`, for the decoy's two load rows; `test-public`,
    `test-reference` and `test-never-loads`;
  - the docs' Extensions: the method, the opt-in and its fix, the default entry point's search,
    and what a load does to the connection.
- **Watched failing:** against `c92d397`'s sources:
  - `test-load-extension` 38 of 44, the engines suite 12 of 14;
  - `test-public` 4, `test-library-loading-real` 2, `test-reference` 1 and `test-never-loads` 1;
  - each row that passes there was watched failing against a plant.

  The builder's 65 plants, on the final tree: 63 caught. S07, the claim not marked last, and R02,
  a failure raised inside the section, are equivalent. `research/m4-slice-4/scripts/red.sh`
  rebuilds the red trees. My 15, written from their descriptions, all caught:
  - the opt-in check dropped, caught on every lane by the row that turns the C switch on through
    `sqlite3_auto_extension`;
  - the code from the connection;
  - the message unfreed when its copy raises;
  - the claim not compared, or taken after the section, or made only before it;
  - the owner check after the arguments;
  - `./` paths let through;
  - the join always `": "`;
  - `""` taken as no entry point;
  - the caller's path, and its entry point, handed to C;
  - the connection's message appended on any change of code;
  - the slot's text dropped when an entry point is given;
  - the close's count of untracked statements dropped, beside an extension's leftover statement.
- **Reviewed** (Opus, read-only): the verb's code sound, no blocker.

  **Two majors,** fixed:
  - S03, a flag set after the section, wasn't equivalent, and the builder's first trap was false.
    A collect request due inside a section costs ticks at its exit, so the sweeps' raised trip hid
    every remainder past the section. Each sweep now runs a pass with collect requests falling
    (ADR-0016, amended);
  - C08, the caller's path handed to C, wasn't equivalent either, nor was its entry point's twin.
    The caller can change its strings between an expiry and the resume, so two rows now do.

  **Five minors,** fixed:
  - the interleave was bounded by a control run;
  - the memory rows had no positive control, and the raw codes weren't asserted;
  - four statements in the docs weren't true of every library;
  - the Apple build was unmeasured, which the maintainer settled as "Build named unavailable
    there" (ADR-0001, amended);
  - the suites mapped calls of the verb.
- **Checked by the M4 session** against the plan, read-only: no blocker, no major.
  - **Three minors,** fixed:
    - an init whose last call succeeded had ": not an error" appended, so the connection's message
      now follows only when the code after the call names an error (ADR-0021, amended);
    - the dlsym cases' text is now compared exactly off a Mac;
    - the log's build-only trees are now rebuilt by `red.sh`, or said not to be kept.
  - **Six nits,** fixed or recorded:
    - an argument order;
    - a row in which an extension's leftover statement makes the close refuse;
    - the constraint's reach over older sweeps;
    - §4.8's one `scheme run` block;
    - C08e's wording;
    - the engine fuels' dependence on `TMPDIR`.
  - **Its CI reading** is an open item for M4's closing review: the loading suites' cost is
    climbing.
- **The records,** accepted by the maintainer, 2026-11-18 ("Accept all"): ADR-0021's amendment,
  ADR-0001's, ADR-0016's and the M4 plan's. Since the acceptance, after the check, the join's
  condition and the fuels' `TMPDIR` note were refined.
- **Libraries:** `make test` 81 of 81 on Guix's 3.53.1, the floor (3.45.1) and 3.54.1, each
  library set inside the container.
- **Times** under the gate, on Guix's library:
  - `test-load-extension` 13 to 14 s;
  - its engines suite 31 s, from 16 s with the second passes;
  - `test-library-loading-real` 188 to 193 s, the lead's run and the log's, from 175 to 177 s
    with two more children.
- **The engine rows' figures:** ADR-0021, amended 2026-11-18.
- **For the Mac run** (slices 3 to 5):
  - with Apple's library, the build and the load rows print UNAVAILABLE, and the opt-in's
    refusal is asserted instead;
  - with Homebrew's, the extension is a `.dylib`, and every row asserts codes, never the Mac's
    messages.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | The builder, three rounds | Opus | 614k, 729k and 777k | 175, 57 and 29 | 69, 49 and 24 min |
  | The review | Opus | 330k | 98 | 25 min |

- **Learned:**
  - **A sweep's quieting is a setup, not a fact about Chez.** The raised trip that makes runs
    comparable also hides a remainder past the last section, so a straddle count of 0 measured the
    setup.
  - **The caller is code too.** Between an expiry and its resume it can change what it passed,
    so a check of an argument binds only the copy C is handed.

### 2026-11-18 — M4 slice 3: the four `db_config` settings at open (PR #44)

- **Built** by an Opus builder from `1735a66`, rebased onto `7c6d536`:
  - **`settings.sls`:**
    - `setting-names` holds eleven names: the seven, then the four in the plan's order;
    - `db-config-settings` takes its ops from `constants.sls`;
    - `settings-plan` gains them, a `no-call` marking `(enable-load-extension . #f)` seen and
      planning no step;
    - new `db-config-step?` and `steps-opt-in?`, both total;
    - both refusal messages list the eleven.
  - **`open.sls`:**
    - each set is one section at the next claimed position: the cell filled with
      `db-config-sentinel` through `call-with-int-cell`, the call, the verdict, and the
      `sqlite3_errstr` message copied there;
    - a refusal closes the connection first, then raises from the verb;
    - `checked-open` makes the fifth check after the list's own rules, inside the checks'
      section, and answers the opt-in;
    - new `applied-settings/with`, for a stand-in binding.
  - **`connection.sls`:** the record's immutable opt-in, and `database-extension-loading?`, which
    runs `check-owned`, then reads it.
  - **`(chez-sqlite3)`** exports `sqlite-extensions-unavailable?`, 69 names.
  - **The docs' Settings:**
    - the four rows, and the starts "as the library was built", Apple's `defensive` on;
    - `writable_schema` doing nothing under `defensive`, and DQS failing at prepare, each a
      `scheme run` block;
    - the opt-in's refusal;
    - in Conditions, the predicate.
  - **The suites:**
    - new `test-open-db-config` (33 rows) and `test-open-db-config-engines` (12), in
      `MEMORY_SUITES_1`, the lighter shard on `main`'s last three runs at the current layout:
      1012, 1023 and 1005 s against shard 2's 836, 1091 and 1441 s (44305936182, 44298034354,
      44293661574). #40's close-out had sent them to shard 2, on runs from before its own suites
      and `test-check-variadic` went into shard 1;
    - `test-settings` 74 to 86, `test-library-loading-real`'s three decoy rows, and
      `refusal-probe.sps`' `--opens`.
- **Replaced rows,** named in the log:
  - `test-settings`' held-out row becomes the four in the live list;
  - M3's names row and no-row row write out the eleven;
  - `test-open-settings`' two hold-out rows become accept rows;
  - `test-public`'s count goes from 68 to 69.
- **Watched failing:** against the base's sources, `7c6d536`'s for the final suites:
  - `test-open-db-config` 25 of 33 fail, and the engines suite 8 of 12;
  - `test-settings` 13, `test-public` 5, `test-library-loading-real` 3, `test-open-settings` 2
    and `test-reference` 1;
  - each row that passes there was watched failing against a plant.

  The builder's 67 plants, rerun on the final suites: 65 caught. R4, the message copied after
  the section, survives harmlessly, since `sqlite3_errstr`'s text is static; and the idle-turns
  plant is equivalent and must pass. Its round-1 survivor, `(enable-load-extension . #f)` sending
  a 0, brought the row that turns the switch on at every open through `sqlite3_auto_extension`.
  My 14, written from their descriptions, all caught (the log's "The lead's verification"):
  - the DQS ops swapped;
  - the opt-in taken from any set;
  - the refusal's `who` fixed, seen only by the decoy;
  - a mismatch's fields swapped;
  - the record's opt-in always `#t`;
  - the review's R1, R2, R3 and R6;
  - the check's five: a set beside a PRAGMA, the moves made identities, PRAGMAs before sets, a
    code that is no exact integer, the reader unowned.
- **Reviewed** (Opus, read-only), no blocker. **Two majors,** fixed:
  - an op set unasked beside the opt-in survived, so each single-op list, the opt-in's among
    them, now leaves the other three at their starts;
  - a set that writes a lane's start can't be seen there, partly a flaw in the brief and in the
    plan's §4.7. An `sqlite3_auto_extension` entry point now moves every op off its start first
    (the plan, amended).

  **Three minors,** fixed: a failing sweep's guard counted one trial; the docs' starts weren't
  true of every library; the log was stale since the rebase. Two nits: one answered (R4), one
  fixed (the straddle count).
- **Checked by the M4 session** against the plan, read-only: no blocker, no major. Five minors,
  fixed:
  - M1, a set that writes the start beside a PRAGMA, unseen, since only the empty and single-op
    lists were judged over moved starts;
  - M2, no row holding the moves to moving, since the expected values came from the entry point's
    own list;
  - M3, nothing holding the order across PRAGMAs and sets;
  - M4, the defensive build's recipe uncommitted, now
    `research/m4-slice-3/lib-defensive.sh`, which rebuilds it byte for byte;
  - M5, ledger claims the log didn't hold, now in its "The lead's verification".

  Six nits: five fixed (the whole-call count, the non-integer code, the reader's owner check,
  the entry points' answers, the held count), and one answered (the messages' containment,
  ADR-0013's decision 9).
- **Libraries:** `make test` 79 of 79 on Guix's 3.53.1, the floor (3.45.1), 3.54.1, and 3.54.1
  built `DEFAULT_DEFENSIVE`, which starts `defensive` on, as Apple's does. Each library was set
  inside the container (`traps.md`).
- **Times** under the gate, on Guix's library:
  - `test-open-db-config` 12 to 14 s, its engines suite 55 to 56 s;
  - `test-library-loading-real` 175 to 177 s, the lead's run and the builder's, up from 145 to
    160 s with three new children;
  - M3's `test-open-engines` 23 s and `test-open-interleave` 37 s, their sweeps longer (ADR-0018,
    amended);
  - the rest 10 to 34 s.
- **The engine rows' fuels:** ADR-0021, amended 2026-11-18.
- **The records,** accepted by the maintainer, 2026-11-18 ("Accept all"): ADR-0021's amendment,
  ADR-0018's, the M4 plan's, and four traps. After the check: each amendment's additions, and a
  fifth trap, whole calls counted by their effects. The maintainer accepted the additions the same day ("Accept all").
- **For slice 4:**
  - `load-extension!` reads `database-extension-loading?` last of its checks;
  - `refusal-probe.sps`' `--opens` serves the decoy's load rows;
  - where a load row's plant could write a value a start already holds, judge it over a moved
    start (the plan, amended).
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | The builder, three rounds | Opus | 714k, 808k and 891k | 376, 223 and 150 | 70, 26 and 22 min |
  | The review | Opus | 329k | 82 | 18 min |

- **Learned:**
  - **A comparison with a start sees a move, never a write of the start itself.** Hold a setter
    from a value it would have to change, in every list shape, and with expected values that
    never come from the code that writes them.
  - **Read the lane before trusting the green.** A host variable didn't reach the container, and a
    floor run passed on Guix's library.

### 2026-11-17 — M4 slice 5: FTS5 and JSON (PR #40)

- **Built** by an Opus builder from slice 0's head, beside slices 1 and 2:
  - the `current` lane compiles FTS5 in (ADR-0003, amended; the maintainer's Q1):
    `build-sqlite.sh`'s compile line by role, `-DSQLITE_ENABLE_FTS5` on the current role's alone;
    `check-sqlite.sh`'s `current_options`, 39 lines, `ENABLE_FTS5` after `DIRECT_OVERFLOW_READ`;
    the `current` job's comment in `ci.yml`; `test-ci-sqlite`, 80 rows to 81;
  - `tests/test-fts5.sps`: 19 rows where FTS5 is, chosen by `sqlite-compile-option?
    "ENABLE_FTS5"` held to `pragma_module_list`, and 5 where it isn't, the refusal asserted and
    FTS5 named unavailable;
  - `tests/test-json.sps`: 16 rows on every library;
  - both suites in `MEMORY_SUITES_1`, the shard whose suites took less time on two of three CI
    runs: 900 s against 986 s (44112097972), 1186 s against 1268 s (44204326637), and 915 s,
    without the two, against 874 s on this PR's run 44211896445. The margin is narrow, so slice 3's
    new suites go in shard 2;
  - the docs' note under `sqlite-compile-option?`.
- **Found:** `close-database!` refused every connection that had used an FTS5 table, which
  became the close fix (PR #36, below).
- **Rebased onto the close fix** (the lead): the drops before each close and the expected-failure
  row are gone, and the close's row is an ordinary row. Against `d1792e4`'s close, `test-fts5`
  fails 15 rows on Guix's library, on 3.54.1 with FTS5, and on 3.45.1 with every module.
- **Watched failing:** both suites' rows, and the lane's scripts, against the builder's 53 plants
  on its own tree, and the 50 that still apply rerun by the lead on the head, on `1735a66`, their
  anchors moved to the rows the review left: 49 caught. F07, the path chosen by the option alone,
  is equivalent: where the option and the module disagree, the agreement row fails by name
  either way. V02, a string bound as a BLOB, survived the builder's run on Guix's library, whose
  JSON and FTS5 read a BLOB as text; both bound rows now assert its `typeof`, and catch it. The
  lead's five plants of the review's fixes, and the old close, were caught on the head too
  (`research/m4-slice-5/`).
- **Reviewed** (Opus, read-only), no blocker. **One major,** fixed: the rank rows ranked 2 then 3,
  which is rowid order too, so `order by rowid` passed them; they now query `sqlite OR rank`,
  which ranks 3 first. **Nine minors,** fixed: a phrase row that an AND passed; the agreement row's
  complement; `json_each`'s key order, which was the document's; V02's argument at the floor; and
  the log's and the ledger's accuracy. Four values the rows assert are the review's measurements,
  not the research's, as each suite's header says.
- **Checked by the M4 session** against the plan and the records, read-only: no blocker, no
  major. Its three minors, fixed: the committed plant evidence was the pre-review tree's, the CI
  run's lines weren't read, and records cited files only `build/` held. Of its five nits, three
  are fixed (the agreement row's `(#f 2)`, the bound `MATCH`'s `typeof`, the FV table's values)
  and two answered in the log.
- **Libraries:** on the head, `make test` 77 of 77 on Guix's 3.53.1, the floor, 3.54.1 with
  FTS5, and 3.45.1 with every module. `test-fts5` passes 19 where FTS5 is and 5 on the floor and
  the plain 3.54.1; `test-json` 16 everywhere. Under the gate each takes 9 to 11 s here, and on
  CI's `memory-1` 11 s and 10 s.
- **CI read** (run 44211896445, both SQLite caches rebuilt): `current`'s `check-sqlite.sh` passed
  39 compile options, `ENABLE_FTS5` among them, and `test-fts5` ran its 19 rows; `floor`'s passed
  37, and `test-fts5` printed "FTS5 unavailable" and ran 5; `main` ran the 19 on Ubuntu's 3.45.1,
  their first run on that library.
- **F0, the lane's check:** `check-sqlite.sh --current` fails the plain 3.54.1 on the missing
  `ENABLE_FTS5` and passes the FTS5 build. `build-sqlite.sh --current`, run end to end through
  replay shims, built that library byte for byte and passed its own check.
- **After PR #37,** rebased onto `1735a66`: both add to `MEMORY_SUITES_1`, in different
  hunks, and edit the Now line, resolved by hand.
- **The Mac run** (the plan, §5) passed FTS5 and JSON with Apple's library and with Homebrew's,
  19 and 16 rows each, in the hand run after slices 3 to 5 (Now, 2026-11-18).
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | The builder | Opus | 425k | 165 | 42 min |
  | The review | Opus | 280k | 95 | 20 min |

- **Learned:**
  - **A suite for a feature the library only carries can find the library's defects:** the FTS5
    rows asserted nothing new about chez-sqlite3's values, and found its close.
  - **A workaround in a suite needs its own way out.** The expected-failure mark turned the fix
    into a failing suite, so the drops couldn't outlive it.

### 2026-11-17 — M4 slice 2: the bindings and `check-variadic` (PR #37)

- **Built:**
  - `native.sls`'s seventh step: `sqlite3_db_config`, bound `(__varargs_after 2)` as the plan's
    §4.2 writes it, and `sqlite3_free`, both required and plain; then `sqlite3_load_extension`,
    optional and `__collect_safe`, through a new `bind-optional`, which answers the procedure or
    `#f` and never refuses; `load-extension-available?`, read from that binding once;
  - `call-with-int-cell`, the counted `int` cell a `db_config` set needs, filled by its caller,
    read back signed, freed on every path: added after slice 1's review found no slice gave it;
  - `constants.sls`' four ops, `sqlite-dbconfig-*`, held to `sqlite3.h`;
  - the convention table's `variadic`, read from exactly `((__varargs_after 2))`, and the
    constants' map rule for a prototype ending `"..."`; the optional entry point's prototype in a
    compile of its own (ADR-0002, amended);
  - the decoy's three switches: `sqlite3_db_config` and `sqlite3_free` dealt by the pattern of five,
    to `-decoys` and `-missing`, and the lacking build of `sqlite3_load_extension` loading, with
    `load-extension-available?` `#f`;
  - `test-native`: each op's round trip with a sentinel per call, the unknown op, `sqlite3_free` of
    NULL, the int cell's range and frees, and the load's FIFO row (ADR-0011, amended);
  - `make check-variadic`, `tests/check-variadic.sh` and `test-check-variadic`, run as a step of
    CI's `main` job, not by `make test`, with `check-ci`'s `MAKELINE` and `test-check-ci` moved.
- **Watched failing:** the final suites against `87e762c`'s code failed every new row, 20 in
  `test-native`, 38 in `test-check-variadic`; rows that test a helper's own rule were watched
  failing against plants. The builder's 100 plants are all caught by some suite or target; the
  survivors in one suite are argued, each caught by another. My 6: all caught, among them the int
  range's edges, `sqlite3_free` bound `__collect_safe`, the value passed as `uptr`, an op off by one,
  and a renamed sweep, which `make test` now sees.
- **Reviewed** (Opus, read-only), no blocker:
  - **two majors,** fixed: the script copied 82 of its 150 distinct lines from chez-curl's,
    against ADR-0001's amendment, and is rewritten, six trivial lines shared; and a header that
    marks `sqlite3_load_extension` unavailable, as Apple's SDK may, would have failed
    `test-constants`' one compile;
  - **five minors,** fixed: `make test` holds the script's ten names and its one form; the range
    row asserts 2^32−1 itself; the arm64 step needs `sqlite3_db_config`'s own failure; the FIFO
    row's hung branch releases the FIFO before any close; the ops' two sources go to slice 3.
- **Built and taken out:** `sqlite3_stmt_busy`, for "Refuse busy statements first", which the
  maintainer replaced with "Vouch only for ours" (PR #36's close-out).
- **Times:** under the gate on Guix's library, `test-conventions` 46 s, `test-native` 24 s,
  `test-check-variadic` 16 s, `test-constants` 13 s, and the three loading suites 145 to 160 s,
  where CI's last run read 136 to 165 s. `make check-variadic` takes 10 to 11 s here, and about
  11 s in CI's `main` job (run 44189788123). On this PR's CI (run 44193211947): `test-conventions`
  43 s, `test-native` 22 s, `test-check-variadic` 10 s, and the loading suites 155, 163 and 174 s,
  `-real`, `-missing` and `-decoys`, within the 450 s bound.
- **The Mac step passed** (ADR-0001's consequence), on 2026-11-18, on `main` at `1735a66`, by the
  M4 session's [research/m4-mac/slice-2.md](research/m4-mac/slice-2.md)
  ([README](research/m4-mac/README.md), its results): `make test` and `make check-variadic` with
  Apple's library and with Homebrew's. Each `make test` passed 75 of 75, and each `check-variadic`
  ended "all 7 steps ok, on tarm64osx", its mutant failing 3 `test-native` rows with Apple's and 6
  with Homebrew's, whose load rows set `ENABLE_LOAD_EXTENSION` through the binding. With Apple's,
  `test-native` named the load rows unavailable, and `test-constants`' optional prototype row found
  no `sqlite3_load_extension` in the SDK's header. With Homebrew's, the FIFO row passed, its first
  run on macOS, released by the collector through `release-until`. macOS's dyld opens a FIFO twice,
  each open waiting for a writer (the M4 session's Mac run 2, PR #38), so the row's collector, its
  fallback and its watchdog release the FIFO until the load answers, ten times at most, a second
  apart. One release would have left the Mac's load to the watchdog.
  `research/m4-slice-2/fifo-double-open.sps` shows one release leaving an opener that opens twice
  waiting, on Linux too, and the repeated release freeing it.
- **For slice 3:** import the ops from `constants.sls` and hold slice 1's table to them; fill the
  cell with `db-config-sentinel` through `call-with-int-cell`; `load-extension-available?` is the
  opt-in's check.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | The builder, four rounds | Opus | about 860k | 276 | 264 min, its own runs among it |
  | The review | Opus | 307k | 76 | 21 min |

- **Learned:**
  - **"Copy none of its code" needs a check, not a reminder.** The brief said it; the builder
    copied anyway, and only the review's line count found it.
  - **A test that compiles against a header can be broken by a platform's header,** even for an
    entry point the code treats as optional. Ask each optional thing in a compile of its own.

### 2026-11-17 — M4's close fix: close first, and vouch only for ours (PR #36)

- **Found** by M4 slice 5's FTS5 suite: a connection that had created or queried an FTS5 table
  couldn't close. `close-connection` counted `sqlite3_next_stmt`'s statements before
  `sqlite3_close`, and a virtual table's module keeps statements of its own there until
  `sqlite3_close` disconnects it. FTS3, FTS4, FTS5 and RTREE all did it, 2 to 10 statements, and
  on a file the only way out was to drop the table.
- **Built:**
  - `connection.sls`: the tracked statements finalized and the cache emptied, then
    `sqlite3_close`; only a refusal counts what is left: the assertion violation if any, else
    `sqlite3_close`'s `&sqlite-error`. Comments state the boundary;
  - `tests/test-connection-close.sps`, 22 rows, in `MEMORY_SUITES_1`: each module's close, after a
    create, a write and a search, and on a reopened file, each chosen by what the library reports
    and the refusal asserted where it lacks one; an untracked statement still refused, and a
    second close after its finalize; the latch on both left-open paths; a backup's refusal; a
    virtual table written again after a refused close; and SQLite's measured behaviour on a
    refused close, as rows that document it;
  - `docs/reference.md`: what a refused close means, and what to do about a full-text index.
- **Decided by the maintainer** (2026-11-17), each from a picker:
  - "Close first, count on failure";
  - "Document it, with a row": a refused close inside a transaction has already rolled back the
    virtual tables' unflushed changes, so roll back, never commit;
  - "Refuse busy statements first", after the review found an untracked write stepped partway
    corrupting an FTS index in autocommit, then reopened when the measurement showed RTREE's blob,
    and FTS5's at 3.45.1, busy in an open write transaction. Asked for one consistent path across
    extensions and closing, the maintainer chose "Vouch only for ours": the close vouches only for
    what chez-sqlite3 tracks, and a refusal belongs to whatever left work open, a bug or foreign
    code.
- **Watched failing:** against the old order the suite failed 16 of 22 on Guix's library and 18
  on the two builds with every module. The builder's 21 plants: 18 caught plain, p03, a count made
  after a successful close, caught only under the gate (an invalid read at `sqlite3_next_stmt`),
  and two equivalent. My 5 plants: 4 caught; Q5, the cache emptied after `sqlite3_close`, is
  equivalent, since the clear is Scheme alone and its statements were finalized first.
- **Libraries:** `make test` 74 of 74 on Guix's 3.53.1, the floor, 3.54.1 with FTS5, and two
  builds made for this, 3.45.1 and 3.54.1 with FTS3, FTS4, FTS5 and RTREE, as Ubuntu's 3.45.1 lists
  them. The suite takes 0.3 s plain and 11 to 12 s under the gate.
- **Reviewed** (Opus, read-only): one major, the autocommit corruption, decided above; seven
  minors fixed: the docs' text, three log claims, the refusal rows' prepare and step, a row that
  writes after a refused close, and the comments.
- **The records,** accepted by the maintainer, 2026-11-17 ("Accept all"): ADR-0012's amendment,
  with notes in ADR-0005, ADR-0014, ADR-0019, ADR-0020 and ADR-0021; the global constraints' two
  close rules and the boundary; six traps.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | The builder, three rounds | Opus | 441k, 476k and 570k | 176, 11 and 41 | 39, 4 and 11 min |
  | The review | Opus | 251k | 62 | 15 min |

- **Learned:**
  - **M4 is the first milestone where other code works on the connection:** compiled-in modules,
    and soon extensions. A rule that judges what isn't ours fails on whichever module comes next;
    the boundary, what the library made, holds for all of them.
  - **Measure a rule against every case before asking for it.** "Refuse busy statements" was put
    to the maintainer before the modules' own statements had been read, and had to be reopened.

### 2026-11-17 — M4 slice 1: the pure core (PR #35)

- **Built,** with no foreign code and no new suite:
  - `settings.sls`: the four `db_config` settings as a table and procedures of their own, beside
    `setting-names` and not in it, so nothing reaches `open.sls`'s SQL path before slice 3:
    `db-config-settings` (each name, op and domain), `db-config-setting-names`,
    `db-config-sentinel`, -1, `db-config-step`, `(name op written expected)` or `no-call` for
    `(enable-load-extension . #f)`, and `db-config-verdict`, a match, a mismatch's fields or an
    error's code. Each is total, so slice 3 can call it inside a critical section: the review
    made 13,689 hostile calls inside `critical-section`, and none raised;
  - `conditions.sls`: `&sqlite-extensions-unavailable` under `&chez-sqlite3-error`, its maker,
    its predicate, and `raise-extensions-unavailable`, which gives the `&who` and the fixed
    `&message`;
  - rows in `test-settings` (74), `test-conditions` (93) and `test-open-settings` (25): the four
    refused by `open-database` as `unknown-setting`, on `:memory:` and on a file, nothing opened,
    until slice 3 joins them; each domain against every kind of value; the verdict over every code
    and cell; the complement against the other 20 ops of 3.45.1's and 3.54.1's headers; every
    fixed `&message` a non-empty string of its own.
- **Watched failing:** against `87e762c`'s libraries the two suites died at expansion, naming no
  test, so their rows were watched failing against the exports stubbed and wrong: 12 and 9
  failures. The builder's 67 plants caught all but V15, which reorders the verdict's disjoint
  cell tests and is equivalent. My 10 plants were all caught, among them a code of 0.0 read as 0,
  the DQS ops swapped, a partial join and the `&who` dropped.
- **Reviewed** (Opus, read-only), seven findings, no blocker:
  - fixed: a top-level definition and two rows that read the library's `setting-names`, which
    slice 3's correct join would have failed (P-TOP killed the suite); the fixed `&message` held by
    no row (P-MSG, P-MSG2); the log's base and its driver, now in
    [research/m4-slice-1/scripts/](research/m4-slice-1/scripts/). The review's plants now fail by
    name;
  - decided: a code that names no error, in ADR-0021's amendment;
  - moved to slice 2: the counted `int` cell, which only `native.sls` may make;
  - moved to slice 3: the ops checked against `sqlite3.h`, and the join's changes, below.

  The M4 session's conformance check of the PR (Opus, read-only), seven findings, no blocker:
  the amendment's raise named `raise-sqlite-error`, not the verb called, so the amendment now has
  the open test the code itself; the global constraints carry the amendment; slice 3's list gains
  `test-settings`' three rows and the stand-in row; and the log's nits are fixed.
- **Times:** 0.3 s, 0.3 s and 2.1 s plain on Guix's 3.53.1 and the floor; 10 s, 9 s and 14 s
  under the gate on both, none `SLOW`.
- **For slice 3:**
  - fill the cell with `db-config-sentinel`, through slice 2's `call-with-int-cell`, which reads
    it back as a signed C `int`, never a literal;
  - take the ops from `constants.sls`'s four, which `test-constants` holds to the header, or hold
    `db-config-settings`' ops to them by a row: today only the suite's copies back them;
  - the join: `settings-plan` maps `db-config-step`'s answers onto its refusals, and a `no-call`
    still marks the name seen, for `setting-given-twice`. The two step shapes are told apart only
    by the `cadr`, an integer op or a string of SQL, so tag them if a stand-in could hand the
    wrong kind. `unknown-setting`'s and `setting-out-of-domain`'s messages list the seven;
  - replace `test-open-settings`' two hold-out rows with the sets' rows, and in `test-settings`,
    which the plan's §5 item 3 leaves out of slice 3's files, `s-out`, the hold-out row, and M3's
    `s-setting-names` and `s-no-row`, which hold `setting-names` whole: the join, done right,
    fails all three (J1). If the plan's answer gains the opt-in, M3's `(settings capacity steps)`
    rows there move too;
  - a code that names no error: test it before `raise-sqlite-error`, and raise from the verb
    called. The stand-in row answers 100 and asserts the verb's `&who` and `(not-an-error 100)`
    (ADR-0021, amended);
  - derive the record's opt-in from the step `(enable-load-extension 1005 1 #t)`, not from the
    name, so `#f`, which makes no step, holds none (the M4 session's check of PR #35).
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | The builder, two rounds | Opus | 417k and 473k | 132 and 36 | 34 and 9 min |
  | The review | Opus | 252k | 66 | 14 min |

- **Learned:**
  - **A pure core can need a primitive only the shell may make.** The plan named a counted `int`
    cell for the set, and only `native.sls` may touch foreign memory, which no slice's file list
    gave it. The review found it before slice 3 met it.
  - **A complement from the library's own list fails a later slice's correct change** (traps.md).
  - **A row for a new export can't fail against the old library:** the program dies at
    expansion. Stub the exports, present and wrong (traps.md).

### 2026-11-17 — M4 slice 0: the plan and the records (PR #31)

- **Built:**
  - [the M4 plan](2026-11-17-m4-plan.md);
  - ADR-0021, accepted by the maintainer with the plan's Q14 to Q16, on top of the pre-work's Q1
    to Q13 ([research/m4-prework/](research/m4-prework/README.md));
  - the plan's owed amendments (§10), applied and accepted ("Accept all"): the brief, ADR-0001,
    ADR-0002, ADR-0003, ADR-0005, ADR-0011, ADR-0012, ADR-0013 and ADR-0018, the global
    constraints, AGENTS.md and `traps.md`.
- **Measured** on Guix's 3.53.1, the floor's 3.45.1, and 3.54.1 plain and with FTS5
  ([research/m4-plan/](research/m4-plan/README.md)):
  - a `db_config` set that changes a flag expires the connection's statements, and one that
    changes nothing doesn't;
  - a set never waited, so it is bound plain;
  - a load can block, on a FIFO, so it is bound `__collect_safe`: plain, it held another thread's
    collection 1.15 s;
  - a load's message is in its own slot, and a failure's code is the call's own answer;
  - a test extension compiles in about 50 ms and loads clean under the gate;
  - FTS5 and JSON behave alike on every build that has them.
- **Watched failing:**
  - the gate, on an unfreed load message: Valgrind exit 9, 448 bytes lost;
  - the FIFO measure's plain mode;
  - `check-sqlite.sh`, on the FTS5 build;
  - the probes' version guard.
- **Reviewed** (Opus, read-only). Twelve findings, all fixed, the review's three probes rerun in
  the research:
  - a slice 1 that would have reached `open-database` through `settings-plan`;
  - an error code read from the connection, not the call;
  - a load's init failure that leaves its reason only on the connection;
  - the optional entry point in the pattern of five;
  - `check-variadic`'s cost inside `make test`, now a CI step;
  - plants that couldn't fail;
  - slices called parallel that share files;
  - Linux facts written as general ones;
  - quotes, citations and counts.

  It also found that Q14 and Q15 pulled against each other. Asked again, from a user's side, the
  maintainer confirmed the method: Python's `sqlite3`'s shape, with the refusal naming
  `(enable-load-extension . #t)`.
- **Rebased** onto #32: three conflicts, each two end-appends or two Status clauses, resolved by
  keeping both, #32's first. The plan now names the hold of its FTS5 gate, against ADR-0005's
  amendment of that day.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | The planner, two rounds | Opus | about 598k | 149 | 47 min |
  | The plan's review | Opus | about 350k | 92 | 24 min |

- **Learned:**
  - **Put questions to the maintainer with their interactions named.** Q14 and Q15 were asked
    side by side, and each answer was right alone; together they named a setting after a C flag
    its `#f` doesn't set. Asking again from what a user can observe settled it.
  - **A pure core isn't pure if the live path reads its tables.** Slice 1's names would have
    reached `open-database` through `settings-plan`'s steps.
  - **A failure's code is the call's,** whenever the call answers one. The connection's error
    state is another call's more often than not.

### 2026-11-17 — M3's closing review and its fixes (PR #32)

Merged as `6b44154`; its builders' drivers followed in PR #33, `a3edef1`, kept with the log.

- **Reviewed** by two Opus reviewers, read-only, on `c0a5408`, all of M3, on disjoint dimensions:
  A the code and its seams, B the tests, the gate and the records. No blocker; nine majors and
  about fifteen minors, each reproduced by the lead before any fix was briefed
  ([the log](m3-closing-review-mutation-log.md), "The review").
  - **The code (A):**
    - `execute-script!` ran statements again when a timer's continuation jumped back inside its
      block: 629 of 2804 trials.
    - `with-transaction`'s flags came after its plan, so a second resume committed again, at
      fuels 9 to 11, 15 and 16. Its BEGIN's plan was read a section early, at fuels 14 to 25.
    - A watchdog that kept interrupting stopped `with-transaction`'s own ROLLBACK and COMMIT, and
      left the transaction open: 351 of 20,000 calls, and a later write lost.
  - **The tests and the gate (B):**
    - three mutants passed all 73 suites: a claim of 0 taken again after the end (N1), a failed
      commit raised inside a critical section (B8), and a cache keyed by a 4096-character
      prefix (N3);
    - `test-transaction-interrupt` took 318 s on CI, past ADR-0005's 150 s line;
    - the tell's gate, from #30, was held by nothing;
    - the README said transactions were "not here yet".
- **Decided by the maintainer:** "Shut the latch on exit" (2026-11-17), for the watchdog finding,
  over documenting the race.
- **Fixed here,** by three Opus builders in parallel, each in its own worktree, on disjoint files:
  - **`with-transaction`:** the call's claim, made by its first expression and taken first in the
    BEGIN's section, which also reads the plan; the exits' rollback with the interrupt latch shut,
    `interrupt-latch-shut!`; depth rows at every raise site.
  - **The conveniences and the open:** `execute-script!` claims each statement's byte offset;
    `made-claim` held whole by pure rows; the sweeps bound a whole new call by a refusal they see
    themselves; the tell held to a direct registration; the sweeps' guards counted against the
    fuels swept.
  - **The suites:**
    - `test-transaction-interrupt` on the memory-mutex device: 10 to 16 s under the gate;
    - the device's first round a handshake;
    - the cache's rows by `let*`;
    - the contention window;
    - the grain read by every timed wait;
    - NOMEM's `memory-kept` held to the memory check;
    - a watchdog's raise letting SQLite's mutex go.
  - **The records:**
    - ADR-0005, ADR-0016, ADR-0017, ADR-0018, ADR-0019 and ADR-0020 amended;
    - `global-constraints.md`, AGENTS.md and `traps.md`;
    - `docs/reference.md`'s load, WAL, `execute-script!`, `with-transaction` and interrupt text;
    - `README.org`, which `test-docs` now holds to no "yet";
    - the plan's §5;
    - the Mac log's P4b line;
    - ten absolute local paths in seven older records, which the M4 session found.
- **Found while the fixes ran:** `main`'s run 44087748537, on `e590fdc`, failed `memory-2`.
  `test-interrupt-reach`'s 3 MB prepare ran unstopped, as one of 27 local gate runs had. The
  device's first round could land before the parse cleared it. The handshake closes that window:
  with the prepare called 200 ms late, 15 of 40 suite runs failed before, and none after.
- **Watched failing:**
  - every part's new or changed row, against `e590fdc` or a plant;
  - part T's 34 plants, all caught;
  - part C's and part S's, each caught or argued in the log;
  - the lead's 10, all caught but K2, which is equivalent.
- **CI:** run 44112097972 on `17a975c`: all six jobs passed. `memory-1` took 20m37s and `memory-2`
  22m0s, their suites 900 s and 986 s. `test-transaction-interrupt` took 11 s, against 318 s on
  `c0a5408`, and `test-interrupt-reach` 17 s.
- **The maintainer accepted** the review's amendments to ADR-0005 and ADR-0016 to ADR-0020, on
  2026-11-17 ("Accept all").
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Reviewer A, the code | Opus | about 408k | 87 | 27 min |
  | Reviewer B, the tests, the gate and the records | Opus | about 426k | 183 | 39 min |
  | Reviewer B's three helpers: the docs, two of the suites' mechanics | Opus | about 1034k, its estimates | 151 | 51 min |
  | Builder T, `with-transaction` and the latch | Opus | about 571k | 160 | 70 min |
  | Builder C, the conveniences and the open | Opus | about 571k | 185 | 66 min |
  | Builder S, the suites | Opus | about 497k | 210 | 52 min |
  | Builder S, the long prepare's handshake | Opus | about 615k | 71 | 41 min |

- **Learned:**
  - **Wiring hides in more places than a stand-in.** The script's flag was read in one section of
    several, and `with-transaction`'s claim came a section late. Both passed every engine sweep,
    and a timer's continuation, called from inside the call, found both.
  - **A sweep's bound computed from the code under test bounds nothing:** it moves with the
    mutant.
  - **A gate's `UNAVAILABLE` lines need a hold of their own:** CI prints nothing of a passing
    suite.
  - **One failure in 27 gate runs was a finding, not noise.** It was left as one-off until
    `main`'s CI failed on it.

### M3 is done

M3's slices 1 to 6 (PRs #22 to #26 and #29), the Mac run's fixes (PR #30) and its closing review
(PR #32) are merged, with CI passing in every job. The maintainer's Mac ran the suites on both
libraries, and read P4 on Apple's. Next is M4, whose plan, with ADR-0021, is PR #31, by the M4
session.

### 2026-11-17 — M3 slice 6: the interrupt, contention and the memory job's shards (PR #29)

- **Built** by the M3 session on slice 5's head, then rebased onto `fcc9e7c`, by builders in turn:
  - **Part A,** `interrupt-database!` and the close's exclusion, in
    `(chez-sqlite3 private connection)`:
    - the record holds slice 1's latch; the open sets its flag, and the close clears it before it
      finalizes anything, setting it again only when the connection stays open;
    - `interrupt-database!` and `sqlite-interrupt?` exported, 68 names;
    - `test-interrupt-database`, `-reach` (the watchdog device under Valgrind) and `-close` (the
      race, 20 rounds);
  - **Part B,** contention: `test-contention`, two WAL connections on two threads, under a
    1500 ms busy timeout, and P4's grain row; the docs' `sqlite-busy?` remedies;
  - **Part C,** CI's memory job in two shards, `memory-1` and `memory-2`, with
    `make check-memory-shards` in `make test`;
  - **Follow-up 2, from the review:** `interrupt-database/with`, and rows that hold the call
    inside the latch.
- **Decided by the maintainer:** "Shard in slice 6" (2026-11-16); "Accept all" (2026-11-17),
  slice 6's amendments to ADR-0005, ADR-0017 and ADR-0019.
- **Watched failing:** every new row, red against the code before it. Part A ran 16 mutations, 15
  caught, one equivalent; part B 15 plants, all caught; part C 53, 51 caught, two equivalent;
  follow-up 2 9 plants, 8 caught, one of them only under the gate, one equivalent. The lead's own
  plants:
  - K1, K2 and J3 survived at first, and each got a row; K5 is equivalent;
  - 9 in part C and 3 in follow-up 2 were each caught.

  Every survivor is argued in [the log](m3-slice-6-mutation-log.md).
- **Reviewed** (Opus, read-only), every finding reproduced before it was fixed:
  - **No row held that the call is made inside the latch.** A plant that read the handle there
    and called after the latch returned passed every suite, plain and under the gate. Yet a probe
    closing the connection at an engine's expiry had Valgrind report the write into the freed
    connection. The brief had asked for no engine row for this verb, and slice 1's rows hold the
    latch alone. Fixed by follow-up 2.
  - **The records:** a plant named two ways, a suite 16 s from `SLOW` recorded only in the log,
    evidence only in a git-ignored `build/`, and counts that disagreed.
- **The lead's own finds:**
  - `make test SUITES=<suite>` failed once part C's check read the run's `SUITES`. The check reads
    the tree's suites now, held by `check-test-fails`' `shards-narrowed`.
  - The busy wait's row failed 2 plain runs of 30: the watchdog's first interrupt raced the
    statement's start, and an interrupt landing there stops a statement before its wait. Its
    watchdog now stays quiet for 200 ms, and the suite passed 60 of 60.
- **Measured** ([research/m3-slice-6/](research/m3-slice-6/README.md)):
  - P5: an interrupt on a freed connection is an invalid write to Valgrind, but the gate's race
    row can't see a missing exclusion;
  - the watchdog under Valgrind: a plain one stopped none of 15 prepares; the device stopped 3 of
    3, each in its first round;
  - a deferred transaction's first write waits out the timeout unless it has read, 1501 to 1502 ms
    against 0;
  - P4 on four libraries, each in milliseconds.
- **Records,** accepted by the maintainer on 2026-11-17 ("Accept all"):
  - ADR-0005, ADR-0017 and ADR-0019 amended;
  - the plan's §4.7, §4.8, §5 item 6, §7 and §8's P4 and P5;
  - constraints: the call inside the latch, the grain row's exception, and the memory gate's two
    jobs;
  - AGENTS.md rules on the watchdog, the grain exception, the shards and a sweep's stand-in; and
    their traps.
- **CI:** run 44064945277 on `6bae240`: all six jobs passed.
  - `memory-1` took 23m33s and `memory-2` 23m28s, against slice 5's one job at 40m31s. Each
    ran its gate in about 5 min and its shard in 17m37s and 17m35s. The two shards' suites
    took 1055 s and 1054 s.
  - The slowest suites were `test-library-loading-decoys`, 171 s of 450, and
    `test-library-loading-missing`, 156 s. `test-transaction-interrupt` took 139 s.
  - `test-check-ci`, at 439 rows, took 97 s.
  - The `P4:` lines read 252 ms on the `main` lane's Ubuntu 3.45.1, 251 ms at the floor and 251 ms
    on the current lane's 3.54.1, each for a 250 ms timeout.
  - **The rerun,** 44069173851 on `721a698`, passed all six. `memory-1` took 27m44s on a slower
    runner, its suites 1270 s, `test-check-ci` 140 s and `test-transaction-interrupt` 87 s;
    `memory-2` took 23m32s.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Builder, part A | Opus | about 511k | 151 | 55 min |
  | Part A's follow-up | Opus | about 581k | 38 | 19 min |
  | Builder, part B | Opus | about 367k | 128 | 40 min |
  | Part B's follow-up | Opus | about 412k | 42 | 23 min |
  | Builder, part C | Opus | about 551k | 182 | 101 min |
  | Adversarial review | Opus | about 368k | 91 | 25 min |
  | Follow-up 2 | Opus | about 350k | 132 | 37 min |

- **Learned** ([traps.md](traps.md)):
  - Under Valgrind a watchdog thread may not run at all while the owner runs C. Taking SQLite's
    memory mutex makes the owner block inside SQLite, and the interrupt lands there.
  - A stand-in that only notes its call may cost an engine no tick, so no fuel splits it from the
    code before it.
  - An interrupt sent as a statement starts stops it before its busy wait.
  - A comma inside a make function's arguments splits them.
  - A forked thread's uncaught raise runs the base exception handler, which removes
    `make-process-temp-directory`'s directory.
  - A review read the record's wiring, which every row had passed by. Rows that hold a library's
    parts on stand-ins say nothing of how a caller hands the parts its real call.

### 2026-11-16 — M3 slice 5: the settings (PR #26)

- **Built** by the M3 session, beside slice 4 from slice 3's `9deda02`, then rebased onto slice 4's
  `5c295c1`, by four builders in turn:
  - **Part A,** `(chez-sqlite3 private open)`:
    - `open-database` and `call-with-database` take a settings list among their options;
    - the list is checked before anything opens, and `busy-timeout` is set first;
    - each of SQLite's six settings is set once and read back;
    - `statement-cache` is fixed in the record, and the private opener of slice 3 is gone;
    - `sqlite-setting-mismatch?` and its three accessors are exported;
  - **Part B:** the lock rows, `test-open-locks`, and the plants;
  - **The review's fixes:**
    - every open call holds a claim, each section one-shot;
    - the checks run in one critical section;
    - a wait's upper bound;
  - **Part D,** the conveniences' claim: `execute!`, `query` and `query-row` hold the same claim
    on every section, and `query-fold` and `execute-script!` keep slice 3's flag.
  - **On the rebase,** slice 4's pending row in `test-transaction-engine` now sweeps every G, is
    guarded a fuel on average, and asserts the body's stray, which slice 4 could only observe.
- **Decided by the maintainer** (2026-11-16):
  - when the close after a failed setting fails too, the setting's condition is raised ("Setting's
    error wins"; ADR-0018, decision 7, amended);
  - a row asserts a wait under twice its timeout ("Keep, amend"; ADR-0019, decision 11);
  - slice 3's defect fixed here, as part D, with slice 4 unmoved ("In slice 5's PR").
- **Watched failing:** each suite red against the code before it. Part A ran 41 mutations, 40
  caught; part B 8 lock mutations and 6 plants, all caught; the fixes 29, 24 caught; part D 33, 29
  caught, and 5 plants of its shared rows, all caught. Every survivor is argued in
  [the log](m3-slice-5-mutation-log.md). The lead's own mutants, eleven across the parts, were
  each caught by named rows.
- **Reviewed** (Opus, read-only), every finding reproduced before it was fixed:
  - **The open verbs under a remainder resumed while an earlier resume of it was pending:** R
    taken before the open, R1 pending past it, R to its end, then R1. `open-database` left a
    connection open, counted and unreachable, and applied the settings twice. The brief had
    modelled "resumed twice" only as one resume run to its end before the next. Fixed by the
    claim.
  - **A survivor's argument was false:** the close after a failed setting can fail, through an
    untracked statement and a timer's re-entry of `call-with-database`'s wind.
  - **No row bounded a wait from above,** so a retry in Scheme passed. Now every timed wait is
    under twice its timeout.
  - **Minors:** the failure path's flag, the list's order through the verbs, an option and a list
    together, no engine row for `call-with-database`, and a dangling traps citation.
  - **Not reproduced:** the review's "`call-with-open-handle`'s window is reachable". There were
    no hits in 7,200 single-shot trials, nor in 1,116 of `call-with-database`. Its hits with
    multi-shot resumes are refusals by design. M1's comment stands.
- **The M2 session's finding,** sweeping slice 4 under the same schedule: slice 3's `execute!`,
  `query` and `query-row` left their statement outside the cache. Before part D, that happened in
  1,360 of 3,910, 3,655 of 10,147 and 1,849 of 5,044 trials, at a row in 1,935 and 602 of them.
  Two runs also shared one statement, so `query` answered rows the other had stepped past. Part
  D's fix leaves none. It also closed a second hole: a timer's raise just past the check-out
  lost the statement.
- **Measured** ([research/m3-slice-5/](research/m3-slice-5/README.md)), alike on 3.53.1 and
  3.45.1:
  - the open verbs' engine and interleaving sweeps (ADR-0018, amended in M3 slice 5);
  - the lock rows: each wait 1502 to 1503 ms plain, and 1509 to 1526 ms under Valgrind at the
    floor; at once, 0 to 4 ms; released mid-wait, 529 to 530 ms;
  - part D's sweeps, and P6's fuels again, about half of slice 3's for the three (ADR-0016,
    amended in M3 slice 5's part D);
  - SQLite's unix VFS keeps a closed connection's descriptor while another connection holds a
    lock on the file.
- **Records,** accepted by the maintainer on 2026-11-16:
  - ADR-0012, ADR-0018 and ADR-0020 amended ("Accept all");
  - ADR-0019's decision 11 ("Keep, amend");
  - part D's ADR-0016 and ADR-0020 ("Accept all");
  - the plan's §4.3, §4.5, §5 item 5 and §8 P2;
  - constraints: the open verbs' claim, the conveniences' claim and flag, text built in a
    section, a failed setting's close, and a wait's upper bound;
  - AGENTS.md rules on interleaved runs, file descriptors under a lock, a collect request's
    ticks, a wait's bounds and a sweep of remainders; and their traps.
- **CI:** run 43957085196 on `b4a403a`: all five jobs passed, and `memory` took 40m31s,
  against slice 4's 31m22s on a runner of the same class, where `test-check-ci` took 85 s. The
  gate ran 68 suites, none slow:
  - part D's six took 445 s: the script's halves 148 s and 145 s, the fold's 72 s;
  - the open verbs' four took 98 s;
  - the slowest was still `test-library-loading-decoys`, at 176 s of 450;
  - `test-transaction-engine`, sweeping every G, took 65 s, against 64 s at every fourth.

  On the slower class, where slice 4's run took 35m07s, this one would come near ADR-0005's 45
  minutes.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Builder, part A | Opus | about 498k | 145 | 48 min |
  | Builder, part B | Opus | about 398k | 103 | 32 min |
  | Adversarial review | Opus | about 318k | 95 | 21 min |
  | The review's fixes | Opus | about 565k | 189 | 63 min |
  | Builder, part D | Opus | about 601k | 179 | 84 min |

- **Learned** ([traps.md](traps.md)):
  - A remainder can be resumed while an earlier resume of it is pending. A flag set once a call
    ends lets both runs act; a claim each section compares with the run's own position holds.
  - A sweep that reuses one remainder across its trials sweeps nothing past the first. My first
    sweep of slice 3's `query` called it clean in 3,876 trials, and its fold passed the seed for
    the procedure. Take a fresh remainder a trial, check the clean answer first, and guard
    against a trivial sweep by the fuels swept, not by a fixed total.
  - An engine's fuel names no fixed point in the code, so a sweep covers every (F, G).
  - Chez's `number->string`, resumed from inside, answered `""` or the digits twice.
  - A finding from the other session's sweep reached code two slices back. Slices stacked on one
    another share their defects, so a sweep in one is worth running over the others.

### 2026-11-16 — M3 slice 4: transactions (PR #25)

- **Built** by the M2 session, stacked on slice 3's `9deda02`, from the M3 session's brief once
  slice 3 was final (the maintainer's order of 2026-11-15):
  - **groundwork first,** read-only, while slice 3 was being built (the maintainer's choice in the
    M2 session's pane, "Slice 4 groundwork"): every case the slice cites, measured on both
    libraries, its gaps closed by probes, the NOMEM rig tried, and the builder's brief drafted.
    Its findings went to slice 3's records, and the heap limit's trap here;
  - **`(chez-sqlite3 private transaction)`:** `with-transaction` over slice 1's plan. Each of its
    own statements goes through slice 3's cache, taken, stepped and given back in one critical
    section, with `ended` as the check-out's check. The connection record gains its depth;
  - **`with-transaction` and `sqlite-transaction-ended?`,** exported (62 names), and a
    Transactions section in `docs/reference.md`;
  - **four suites:** `test-transaction` (48 rows), `-nomem` (25), `-engine` (15) and
    `-interrupt` (8); and the heap limit lifted hard then soft in `test-statement-values-nomem`,
    with a second connection's read to hold it.
- **Decided by the maintainer** (2026-11-16, in the M2 session's pane):
  - the builder's three choices confirmed, and the refusal naming the held statement's SQL
    ("Confirm, and name the SQL");
  - a handler that runs before the unwind counts as part of the body ("Document it");
  - each statement used in one critical section ("One section per statement").

  "Once" and "Reuse N", from the groundwork, were decided in the M3 session's pane and are in
  slice 3's records.
- **Watched failing:**
  - each new suite red against a stub that calls the body plainly;
  - 50 plants in [the log](m3-slice-4-mutation-log.md): §4.8's, the builder's, both reviews' and
    the fixes'. Every one is caught. Two more are argued equivalent there: `begun-on-failure` at
    the outer level, and `pending-begun-on-ended`.
- **Reviewed** (Opus, read-only), every finding reproduced before it was fixed. No blocker; nine
  majors and seven minors:
  - **four rules no row held,** each mutant passing every suite: an escape past a failed rollback,
    the same after a resumed raise, a failed `BEGIN`, and the level a return had already ended;
  - **"Once" broken under an engine:** an expiry between `ROLLBACK TO` and `RELEASE` let the after
    thunk issue the `ROLLBACK TO` again. Fixed by running the failed commit's rollback with its
    plan in one section; recording progress step by step failed the same row;
  - **a handler's transaction rolled back by the exit,** kept as documented behaviour;
  - **an engine taken outside the call, resumed inside it,** leaves the call: documented, with a
    row;
  - **the interrupt suite's time,** Valgrind's one thread at a time: the watchdog bounded by a
    deadline that never fails a row;
  - **records:** the log's stale counts, and the docs overclaiming a second resume;
  - **minors:** the run-count sensor's reach, two NOMEM headers, a `[B]` row's false premise, a
    missing NOMEM refusal row, a comment, and a docs sentence on a lost engine.

  The fixes found one more: an engine lost between a failed `RELEASE`'s step and its return left
  it tracked as `failed`, so every later `with-transaction` on that connection was refused. Fixed
  by "One section per statement".

  **The closing review** (Opus, read-only) of the fixes and the records found no blocker, and two
  majors:
  - the second-resume row could no longer fail the design it settled, since one section a
    statement hid the stray `COMMIT` from its snapshot. It now asserts the second answers too;
  - the records called the step-by-step rollback equivalent, where a timer's handler re-entering
    the body still ran `ROLLBACK TO` twice under it. That's now a row.

  Its minors were:
  - three docs sentences;
  - the once row's allowance for a lost engine;
  - a stale comment and stale figures;
  - a nested `SAVEPOINT` failure no row made, now made by a timer;
  - a watchdog whose raise hung the suite.
- **Slice 5's schedule,** a remainder resumed again while an earlier resume of it is pending (the
  M3 session, from its own review): `with-transaction` stays whole under it, the depth restored,
  none of its statements left behind, and a later call committing, in a row of about 2,090
  trials a level. The same sweep found slice 3's conveniences leaving a statement outside the
  cache; the maintainer chose to fix that in slice 5.
- **Measured** ([research/m3-slice-4/](research/m3-slice-4/README.md)), alike on 3.53.1 and
  3.45.1:
  - the engine sweep completes at fuel 112, and slice 1's plant fails at fuels 106 to 109,
    against the model's 138 to 174;
  - a remainder resumed a second time once `ended` was set touched no statement;
  - the NOMEM rig, a step and a column read each under the limit alone;
  - the interrupt suite, 11 to 109 s under the gate: Valgrind's scheduling, not the code.
- **Records,** accepted by the maintainer on 2026-11-16 ("Accept all"):
  - ADR-0017's amendment, "`with-transaction` as built";
  - four traps: the hard heap limit lifted alone; a run count blind to a step that failed at
    entry; a lost engine; and a watchdog under Valgrind.
- **CI:** run 43941964004 on `052c130`: all five jobs passed, and `memory` took 31m22s, against
  slice 3's 27m01s. Under the gate, on a runner where `test-check-ci` took 85 s:
  - the slowest was `test-library-loading-decoys`, at 176 s of 450;
  - `test-transaction-interrupt` took 149 s, against 71 to 109 s locally: the watchdog's latency
    is Valgrind's scheduling, so this suite's time is the one to read again on a slower runner;
  - `test-transaction-engine` took 64 s, and the other transaction suites 9 to 20 s.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Groundwork, read-only | Opus | about 475k | 114 | 32 min |
  | Builder | Opus | about 602k | 153 | 57 min |
  | Adversarial review | Opus | about 356k | 84 | 25 min |
  | The review's fixes | Opus | about 431k | 137 | 40 min |
  | One section per statement | Sonnet | about 120k | 46 | 15 min |
  | Closing review | Opus | about 282k | 73 | 22 min |
  | The closing review's fixes | Sonnet | about 200k | 80 | 25 min |

- **Learned** ([traps.md](traps.md)):
  - A brief's assertion can be false on green code. "No statement of its own tracked" forgot that
    the cache tracks what it keeps. Read what the green code leaves before writing the row.
  - A plant worded after the brief can be masked. "The after thunk without its `ended` check"
    passed every row, since each step reads `ended` itself; the plant that acts twice must also
    clear it.
  - Tracked statements can't see a cached statement stepped twice; only a run count can, and a
    run count can't see a step that failed at entry. A row that counts needs both.
  - A fuel is the suite's as well as the code's: rows added to the engine suite moved every sweep.
    Cite a window with the text it was read at.
  - Groundwork run while the base was being built meant the maintainer's decisions were settled
    before the builder started.
  - **Research kept only in a git-ignored scratch directory dies with its worktree.** The
    groundwork's probes, which ADR-0017 cites, were lost when the slice 2 worktree was removed
    after #23 merged. They were recovered from the agent's transcript, run again, and committed
    under [research/m3-slice-4/groundwork/](research/m3-slice-4/groundwork/README.md). Before
    removing a worktree, check whether any record cites a file only its `build/` holds.
  - **Deleting a stacked PR's base branch closes the PR, not retargets it** ([traps.md](traps.md)).
    #23 was closed that way, then reopened.

### 2026-11-16 — M3 slice 3: the conveniences, the counters and the cache (PR #24)

- **Built** on slices 1 and 2, stacked on slice 2's `0913468`, by three builders in turn:
  - **Part A,** in M2's `statement.sls`, `statement-values.sls` and `connection.sls`:
    - the internals that take a who, M2's verbs made wrappers over them;
    - the script's prepare with flags and its tail, `prepared-at`;
    - the cache in the connection record, its check-out and return each in one section, and a
      private opener of a given capacity;
    - the counters `changes`, `total-changes`, `last-insert-rowid` and `in-transaction?`;
  - **Part B,** `(chez-sqlite3 private conveniences)`: `execute!`, `query`, `query-row`,
    `query-fold` and `execute-script!`, with their who, re-entry, cache, counter and engine rows;
  - **Part C:** §4.8's plants for the slice, P8, and the nine public names with their
    `docs/reference.md` entries.
- **Decided by the maintainer** (2026-11-16):
  - every convenience's call guarded by a flag of its own, read in every section that touches its
    statement ("Guard every call"; ADR-0016 and ADR-0020, amended);
  - one section a value kept, after P8 measured its cost ("Keep one value each"; the plan's Q15);
  - for slice 4, from its groundwork in the M2 session: a failed commit's rollback tried once
    ("Once"), and a savepoint's N following the calls' extents ("Reuse N"; ADR-0017, amended).
- **Watched failing:** each suite red against a stub first. Part A ran 87 mutations, all caught;
  part B 63, 59 caught; part C 21 plants, all caught; the fixes 36, 31 caught. Every survivor is
  argued in [the log](m3-slice-3-mutation-log.md). The lead's own mutants, seven across the
  parts and the fixes, were each caught by named rows.
- **Reviewed** (Opus, read-only), every finding reproduced before it was fixed:
  - **A statement could be handed out twice.** Chez's engine remainders are multi-shot, and a
    timer's handler can capture a continuation between any two sections. A second resume of
    `query`'s remainder stepped and refiled a statement another engine had checked out since.
    Fixed by the flag on every call.
  - **`query-fold`'s flag guarded neither its check-out nor its binds:** 93 re-entries of a
    finished fold, from its timer handler's continuations, left 31 statements tracked and in no
    cache. Fixed by the same flag.
  - **A survivor's argument was false:** the fold's read in the step's section isn't redundant,
    since a timer handler runs between the read after the procedure and the next step. A timer
    row now kills it.
  - **The docs promised a closed condition where the engine can be lost,** when the fold's finish
    fails during an expiry. The docs now say so.
  - **Minors:** an unreached branch of `code-number`, an engine row that didn't print its fuel,
    a docs claim about `trusted_schema` that no row held, and part B's probes left git-ignored.
    Each is fixed.
- **Measured:**
  - P6: each convenience completes under an engine at every fuel, first unexpired at 84 to 640;
  - P8: a cache hit saves 4.5 to 5.0 µs a call; a section a value costs 150 to 200 ns a value
    more than one a row ([research/m3-slice-3/](research/m3-slice-3/README.md)).
- **Records,** accepted by the maintainer on 2026-11-16 ("Accept all"):
  - ADR-0014, ADR-0016, ADR-0017 and ADR-0020 amended;
  - the plan's §1, §4.2, §4.6, §4.7, §4.8, §5 item 4, §8 and §9;
  - a constraint each on the conveniences' flag and `with-transaction`'s refusal;
  - an AGENTS.md rule and a trap, on multi-shot remainders and handlers between sections.

  From slice 4's groundwork, by the M2 session and checked here against its outputs:
  - a failed commit's second way to fail;
  - the `failed` evidence and a column read's NOMEM narrowed;
  - the T-numbered citations;
  - the heap limits lifted hard then soft, a trap slice 4 records.
- **CI:** passed in all five jobs on `9deda02` (run 43903012495); `memory` took 27m01s, its
  slowest suite `test-library-loading-decoys` at 175 s of 450, on a runner where `test-check-ci`
  took 84 s.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Builder, part A | Opus | about 554k | 160 | 44 min |
  | Builder, part B | Opus | about 559k | 121 | 50 min |
  | Builder, part C | Opus | about 436k | 116 | 31 min |
  | Adversarial review | Opus | about 438k | 112 | 27 min |
  | The review's fixes | Opus | about 538k | 140 | 53 min |

- **Learned** ([traps.md](traps.md)):
  - A remainder runs twice when resumed twice, and a timer's handler is the caller's code between
    any two sections. A flag that guards only around the caller's procedure guards nothing there.
  - A survivor called redundant by an argument that names the only way in is wrong whenever
    there is another way in. Try to break each argument with a schedule.
  - Splitting one large part into two kept each builder's scope narrow, and the third read the
    second's code fresh.
  - A tick-count row compares whole calls: a longer SQL's scan alone cleared the threshold, until
    the SQL was padded to one length.

### 2026-11-16 — M3 slice 2: the bindings (PR #23)

- **Built** by the M2 session, beside slice 1 and stacked on it (the maintainer's order of
  2026-11-15, relayed by the M3 session and confirmed in this session's pane, "Yes, push and open
  it"):
  - **native's five bindings,** after M2's 21, in ADR-0002's M3 order and its seventh step. Each
    is checked with `foreign-entry?`, and all are plain:
    - `sqlite3-changes64`, `sqlite3-total-changes64` and `sqlite3-last-insert-rowid`, `integer-64`;
    - `sqlite3-get-autocommit`, `int`;
    - `sqlite3-interrupt`, `void`;
  - `sqlite-prepare-persistent`, held to `sqlite3.h`;
  - the convention table's five rows, and a `result-type` in `test-constants` for a `void` result,
    held against the map's whole list of C types;
  - **`test-native`'s rows:**
    - the four counters after each statement of a 14-statement script, held to a new
      `--counters` mode of the C oracle and to a written literal, with a trigger to separate the
      changes from the total;
    - the rowids at 2⁶³−1, −2⁶³ and 2³²+1, whole;
    - the autocommit flag in each state;
    - the interrupt, on one thread;
    - the oracle's modes and `run-statement` refusing a statement with a tail;
  - a decoy switch and a `missing-api` row per entry point.
- **Measured,** on 3.53.1 and 3.45.1 alike: with a statement held at a row, `sqlite3_interrupt`
  makes its next step and its finalize answer 9. With none running, or after one ran to DONE, the
  interrupt is lost.
- **The gate, split in three** (ADR-0005, amended 2026-11-16):
  - **Why:** on slice 2's slow run, M3's five entry points brought the halves to 319 s and 272 s,
    against the 450 s `SLOW` line. On the same class of runner on `main` they had taken 288 s and
    250 s. The maintainer chose to split now ("Split into thirds now").
  - **The new suite:** `test-library-loading-missing` holds only missing-api rows.
  - **The dealing:** a pattern of five deals native's order. Positions 0, 2 and 4 go to
    `-missing`, 1 to `-decoys` and 3 to `-real`.
  - **Children,** 25, 28 and 28, since the other two hold about 20 children of their own.
  - **The partition is held in each suite:** the merge, the dealing, the pattern written out, and
    the files.

  | Run | Commit | `test-check-ci` | Decoys | Real | Missing | `memory` |
  |---|---|---|---|---|---|---|
  | 43768337291 | `bb7feaa`, `main` | 117 s | 288 s | 250 s | | 27m32s |
  | 43783905101 | `2e844f1` | 90 s | 264 s | 225 s | | 24m32s |
  | 43794568875 | `3e9a506` | 117 s | 319 s | 272 s | | 29m38s |
  | 43854418185 | `d6c58d0`, split | 84 s | 174 s | 144 s | 158 s | 24m02s |
  | 43858091596 | `24b426e`, split | 83 s | 172 s | 143 s | 154 s | 23m36s |

  Both runs of the split landed on fast runners. On the slow class, by how the halves grew
  between `785234b`'s run and `bb7feaa`'s, the largest would take about 225 s.

- **Decided by the maintainer:**
  - 2026-11-15: the push and the PR ("Yes, push and open it");
  - 2026-11-16: the split ("Split into thirds now");
  - 2026-11-16: the floor's header recorded as a trap, with no check ("Record a trap only").
- **Watched failing:** each suite was run red first ([the log](m3-slice-2-mutation-log.md)).
  - the build's 62 mutants, all caught;
  - each of the review fixes' rows, on its mutant;
  - the review's own 15: 11 caught, 2 argued equivalent (O1, O2), and 2 surviving by the decoy's
    design (D1, D2), whose answers no row reads;
  - the split's 7, all caught;
  - the split review's 10, all caught once each suite wrote the pattern out.
- **Reviewed** (Opus, read-only), twice. Each finding was reproduced before it was fixed.
  - **The slice:** no blocker, 1 major and 10 minors.
    - **The major:** the PR body said the `int` plants and the order swaps were caught by form
      alone. `last_insert_rowid`'s `int` is caught by behaviour too, and the order only by
      `test-native`'s body rows.
    - **The minors:**
      - the record strings cited records that don't say the claim, after my first correction too;
      - `result-type`'s `void` map was untested against its complement;
      - the oracle leaked its connection on bad hex;
      - the oracle and `run-statement` dropped a statement's tail, both sides agreeing;
      - the log's gate table was of the pre-rebase tree, and two of its red-run figures matched
        no run;
      - the briefs' floor command never set the floor's header;
      - the slice's CI times weren't yet read;
      - the decoy's five answers are never observed;
      - two nits.
  - **The split:** no blocker, 1 major and 5 minors.
    - **The major:** ADR-0002's M3 amendment still said the entry points alternate.
    - **The minors:**
      - nothing held the pattern itself;
      - the decoy's header named two suites;
      - the ADR's thirds arithmetic was wrong;
      - the log's build count left out `initialize`;
      - an unused import.
- **Records,** accepted by the maintainer on 2026-11-16 ("Accept all"):
  - ADR-0005's amendment "the halves split in three";
  - a pointer in ADR-0002's M3 amendment;
  - a trap and an AGENTS.md line on a floor run's header.
- **Unreproduced:** `check-memory-gate`'s case b missed the statement plant's leak once, in a full
  run of the checks straight after `make test`: "make test-memory exited 0 … got: test-memory:
  pass tests/memory-plant-statement.sps". Fifteen isolated runs of the plant and two full reruns
  of the check caught it. It is M2 slice 3's plant, and this slice changes nothing it reaches.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Builder | Sonnet | about 288k | 99 | 60 min |
  | Adversarial review | Opus | about 329k | 122 | 37 min |
  | The review's fixes | Sonnet | about 136k | 75 | 45 min |
  | The split | Sonnet | about 122k | 50 | 34 min |
  | The split's review | Opus | about 194k | 56 | 16.5 min |

- **Learned** ([traps.md](traps.md)):
  - A floor run that sets only the library compiles its C against another header.
  - A record string's citation is checked only for the record's existence. Twice this slice cited
    a record for a claim it doesn't make. Read the decision before citing it.
  - Balance a split by children, not by entry points: each half held about 20 children of its
    own, so dealing by thirds would have left 34, 33 and 14.
  - `test-check-ci`'s ratio overstates the halves' growth on a slower runner: between two runs it
    rose 39%, and the halves 28%.
  - A rule read from the file it holds holds nothing: the dealing row read the pattern from the
    parts' own file, until each suite wrote it out.

### 2026-11-15 — M3 slice 1: the pure core (PR #22)

- **Built,** in pure Scheme on synthetic inputs, with no foreign code, by two builders in parallel
  on disjoint files. Slices 3 to 6 call much of it inside critical sections, so each procedure that
  runs there answers data, and only the `raise-…` procedures raise.
  - **Part A:**
    - `(chez-sqlite3 private settings)`: open's arguments split into the options and at most one
      settings list; ADR-0018's five refusals; each setting's set and read-back SQL, its expected
      read-back, its reader and the comparison; `statement-cache`'s capacity, 32 when absent;
    - `(chez-sqlite3 private transaction-plan)`: the begin from autocommit, depth and mode, and
      each exit's plan from `begun`, `ended` and autocommit after the body;
    - `(chez-sqlite3 private statement-cache)`: the cache's table, the least recently used out
      first, keyed by `string=?`.
  - **Part B:**
    - `(chez-sqlite3 private conditions)`: `&sqlite-interrupt`, classed by primary code;
      `&sqlite-setting-mismatch`; `&sqlite-transaction-ended`;
    - `(chez-sqlite3 private script)`: `execute-script!`'s error offsets, in characters into the
      whole script;
    - `(chez-sqlite3 private interrupt)`: the interrupt's exclusion against the close, on
      stand-ins for the foreign calls.
- **Decided by the maintainer** (2026-11-15):
  - the order: slices 1 and 2 in parallel, 2 by the M2 session, then 3, then 4 and 5 in parallel,
    then 6, each its own PR stacked on the one before;
  - a script's prepare error with no offset points at the failing statement ("Point at the
    statement"; ADR-0016, amended);
  - the slice's amendments, accepted ("Accept all").
- **Watched failing:** each suite red against a stub first. 259 mutations, 249 caught, and 10
  survivors argued equivalent. The review's fixes added 33, all caught, and the earlier ones were
  rerun over the changed libraries ([the log](m3-slice-1-mutation-log.md)).
- **Reviewed** (Opus, read-only): no blocker in the slice's code, 1 major and 7 minors, each
  reproduced before it was fixed.
  - **The major was in the records:** ADR-0017's shape reads autocommit in one section and steps
    the `COMMIT` in another. Modelled over slice 1's plan, an engine's expiry between them rolled
    back, and the resumed body stepped the `COMMIT` anyway. With another engine's savepoint at the
    same depth, the call answered as committed though its insert was rolled back. The window was
    at fuels 138 to 174, past the plan's sweep of 1 to 60
    ([research/m3-slice-1/](research/m3-slice-1/README.md)). ADR-0017 is amended so each step
    that ends the level reads `ended` in its own section, and every M3 engine row sweeps until the
    call completes unexpired. `failed-commit-plan` takes `ended`.
  - **The minors:**
    - the interrupt row caught six mutants only by timing: a closer 1 s late let them pass;
    - a read-back with no row matched a setting of `#f`;
    - `equal?` keys ran a record key's own hash and equality inside the section;
    - the very statement returned twice was handed back to be finalized while the cache kept it;
    - the script's −1 contradicted ADR-0013's amendment, which the maintainer settled;
    - the exit row's model copied `exit-plan` line for line;
    - `settings-plan` reads the caller's list twice, now said in its header.
- **Records,** accepted by the maintainer on 2026-11-15 ("Accept all"):
  - ADR-0016, ADR-0017, ADR-0018 and ADR-0020 amended;
  - the plan's §4.2, §4.9 and the engine rows of slices 3 to 5;
  - a constraint and an AGENTS.md rule, on a flag read in the section of the step it guards and a
    sweep's bound;
  - five traps.
- **CI:** passed in all five jobs on `7e5f40c`, before the review's fixes; `memory` took 22m45s,
  against 22m04s on `main` at `3e2460b`. It passed in all five again on `0505ff5`, the final
  commit (run 43783755123), `memory` taking 23m03s.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Builder, part A | Opus | about 405k | 96 | 42.5 min |
  | Builder, part B | Opus | about 438k | 142 | 38.4 min |
  | Adversarial review | Opus | about 339k | 82 | 20.5 min |
  | The review's fixes | Sonnet | about 179k | 56 | 14.5 min |

- **Learned** ([traps.md](traps.md)):
  - A flag checked in one section guards nothing in the next: an engine's expiry between them runs
    the after thunk. The records had the shape, so every builder would have inherited it, and only
    a model of the later slice, built on this one's plan, showed it.
  - A sweep to a fixed fuel tests only the path's start. The window lay past 60.
  - A two-thread row's bounded wait must start after the other thread says it is about to act,
    or a late thread passes the mutant.
  - Two builders in parallel, on disjoint files, halved the wall time, and their hand-backs merged
    without a conflict.

### 2026-11-15 — M3 slice 0: the plan and the records (PR #21)

- **Built:** [the M3 plan](2026-11-15-m3-plan.md), and ADR-0016 to ADR-0020, accepted by the
  maintainer with the plan's Q1 to Q15. The plan's owed amendments are applied, and the maintainer
  accepted them ("Accept all"): the brief, ADR-0002, ADR-0005, ADR-0010 to ADR-0014, the global
  constraints, AGENTS.md and `traps.md`.
- **Measured** on Guix's 3.53.1 and at the floor, 3.45.1: M3's research, in two halves, while M2
  was being built, and slice 0's probes P1, P2, P3, P7, P9, P11, P12, P13 and P14
  ([research/m3-plan/](research/m3-plan/README.md)).
- **Reviewed** (Opus, adversarial): the research once, its findings measured again and fixed in
  place; the plan twice, a first review and a focused one of its fixes. Each high finding was
  reproduced by a probe before it was fixed. Then a third review read only the delta, the re-read
  and the applied amendments, against what M2 merged. Its one high finding: ADR-0005's split
  amendment had M3's entry points "add to one half", and M3's amendment had them alternate, with
  no row holding either. Now both say each goes to one half, three to the decoys suite and two to
  the real one. It found 13 lesser slips too: stale cites, a misnamed section, and a 1024 credited
  to Q11 that is Q13's. Each was checked against the tree, and each was fixed.
- **Findings for M2,** F1 to F13 (the plan, §9), went to M2's session, which answered F8, F11, F12
  and F13: F12 fixed in #19, F13 commented in #20, and F8 and F11 settled as M3's work.
- **Re-read** against #19 and #20 before the amendments were applied: the plan's account of the
  split was corrected, and 30 line cites moved, then six more into ADR-0005, ADR-0014 and
  `traps.md` once slice 0's amendments lengthened them. Every other quote and anchor held.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Concurrency research | Opus | about 395k | 93 | 49 min |
  | Single-connection research | Opus | about 451k | 76 | 35 min |
  | The research's review | Opus | about 420k | 77 | 22 min |
  | The planner, four passes | Opus | about 928k | 336 | 84 min |
  | The plan's first review | Opus | about 463k | 80 | 28 min |
  | The focused review of its fixes | Opus | about 294k | 60 | 21 min |
  | The delta's review | Opus | about 275k | 98 | 17 min |

- **Learned:**
  - Re-read a line cite from the commit it was read at. The first re-read, after #19, compared
    `native.sls` from #19's head to its merge, found it unchanged, and missed that #19 itself had
    moved `call-with-block`, cited from `0572267`. The re-read after #20 mapped every cite from its
    own commit.
  - Read a partition from its table, not its name: the plan had M3's entry points joining "the
    half that holds the rows per entry point", where `decoy-halves` alternates them.
  - A record's amendment moves the lines a plan cites in it. Applying §10 moved six of the
    plan's own cites, so the cites are re-read after the records change, not before.

### 2026-11-15 — M2's closing review and its fixes (PR #20)

- **Reviewed** (Opus, read-only, on `1a53b13`, all of M2): no blocker, 2 majors and 7 minors, each
  reproduced.
  - **The gate:** `test-library-loading` took 562.2 s on #19's own run, past the 450 s line and
    38 s from the timeout. Slice 2 had settled from one 409 s run that it stays whole. Split in #19,
    by the maintainer's choice ("Split in #19, rest after"), with a check that fails any suite past
    three quarters of `MEMORY_TIMEOUT` (ADR-0005, amended).
  - **For M3:** a critical section isn't a lock between threads, so M3's interrupt and the close
    share a mutex. Sent to the M3 session with the minors that bear on M3: big copies, WHO-taking
    internals, and a prepare that hands back its tail.
- **Fixed here:**
  - a row prepares a table-valued function, so "no prepare flags" is held: a `NO_VTAB` mutant had
    passed every suite;
  - `check-seam`'s rule (l): only `utf8` and `native` reference `utf8->string`;
  - `finalize-handle!` clears its handle straight after `sqlite3_finalize`;
  - comments on `call-with-block`'s re-entry and on `sqlite3_column_name`'s reader;
  - the docs: a normal return can raise a finalize's own failure; `column-bytevector` refuses by
    storage class; the wrong-thread condition covers statements; and big copies hold this thread's
    interrupts. `README.org` says what M2 gives;
  - records: ADR-0015's copies reworded, and the big-copy cost recorded, accepted by the
    maintainer ("Accept it"); the CI times of the split; stale lines of this ledger and
    `traps.md`.
- **Watched failing:** 8 mutants, all caught ([the log](m2-closing-review-mutation-log.md)).
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | M2's closing review | Opus | about 390k | 120 | 30 min |
  | The gate split, in #19 | Opus | about 403k | 121 | 76 min |
  | The minor fixes | Sonnet | about 146k | 85 | 20 min |

- **Learned:**
  - One CI run is one sample: runners differ about two to one. The check now holds the line.
  - A review of the whole milestone found what five slice reviews couldn't: a cost read from one
    run, and a rule two slices shared that no row held.

### M2 is done

M2's slices 0 to 4 (PRs #14, #16 to #19) and its closing review (PR #20) are merged, with CI
passing in every job. The maintainer's Mac ran the suites on both libraries. Next is M3, whose plan,
ADR-0016 to ADR-0020, is drafted on `m3-plan`.

### 2026-11-15 — M2 slice 4: values (PR #19, `00ab0c8`)

- **Built:**
  - `(chez-sqlite3 private statement-values)`: `bind!`, `bind-all!`, `clear-bindings!`,
    `column-value`, `column-bytevector` and `column-name`, each through slice 3's accessor, in one
    critical section, raising after it;
  - native's byte helpers: `call-with-bytes`, `foreign-bytes` and `c-string->bytevector`;
  - the public names, `sql-null`, the invalid-text condition, and the docs' Values section. The
    public surface is now 51 names.
- **Measured first,** by the M1 session, for this slice, and checked by it
  ([research/m2-slice-4/](research/m2-slice-4/)):
  - a refused bind's own message;
  - `SQLITE_LIMIT_LENGTH`'s smallest values;
  - byte-exact parameter names;
  - running out of memory caused on demand by the heap limit;
  - the sticky NOMEM after a read, and its rollback of a transaction.
- **Every row of the plan's §4.3 and §4.4 on a real library,** on both libraries. Out-of-memory was
  caused for real, for the value reads and for `column-name`.
- **Decided by the maintainer** (2026-11-15):
  - a NOMEM read moves the statement to `failed`, and is raised once (ADR-0014's slice 3
    amendment);
  - ADR-0015's slice 4 amendment, accepted ("Accept it").
- **Watched failing:** each suite red first. Part A and the review's fixes: 97 mutations, 90
  caught, 7 argued. Part B: 39, all caught ([the log](m2-slice-4-mutation-log.md)).
- **The plants:**
  - `clear-bindings!` while a row is ready: Valgrind reported 5,000 invalid reads in a freed
    5,008-byte block, on both libraries;
  - a boolean guessed from a declared type;
  - parameters numbered from 0.
- **Reviewed** (Opus, read-only): 1 blocker, 1 major and 5 minors, each reproduced, all fixed.
  - **The blocker:** a NULL pointer read the connection's last code, so after another
    statement's NOMEM a healthy empty-BLOB read raised `nomem` and failed its statement. The reader
    now reads the column's type too (ADR-0015, amended).
  - **The major:** no row held that an index is exact, so `1.0` would have reached C.
- **CI:** passed in all five jobs on `7a8ea47`, before the review's fixes, `memory` taking 20m43s,
  and on `1a53b13` after them, `memory` taking 28m51s.
- **The gate split, in this PR** (the maintainer's choice after M2's closing review, "Split in
  #19, rest after"):
  - `test-library-loading` took 562.2 s on `1a53b13`'s run, 38 s from the timeout. It is now two
    suites, 196 s and 184 s in the container.
  - `make test-memory` fails any suite past three quarters of `MEMORY_TIMEOUT`, as `SLOW`
    (ADR-0005, amended).
  - The split's 8 mutants and the check's 7 were all caught.
  - The builder: Opus, about 403k tokens, 121 calls, 76 min. The closing review: Opus, about 390k
    tokens, 120 calls, 30 min; its other findings go to M2's closing-review PR.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Part A, two runs: the brief's contradiction, then the build | Opus | about 598k | 179 | 49 min |
  | Part B: the public names and docs | Sonnet | about 143k | 37 | 8 min |
  | Adversarial review | Opus | about 300k | 83 | 19 min |
  | The review's fixes | Sonnet | about 148k | 69 | 24 min |

- **Learned** ([traps.md](traps.md)):
  - A code read "at once" can still be another statement's. Read what the call itself changed: here,
    the column's type.
  - Slice 1's readers took copy procedures no slice was given, and the brief put the one file that
    could hold them off limits. Before a brief puts files off limits, check the work's every need
    against them. The builder stopped and said so, as the brief told it to.
  - Measurements made for a slice by another session, and checked by it, saved the build its first
    hour.

### 2026-11-15 — M2 slice 3: statements (PR #18, `0572267`)

- **Built:**
  - `(chez-sqlite3 private statement)`: a statement is an integer handle in an opaque, sealed
    record. Its verbs are `prepare-statement`, `finalize-statement!`, `call-with-statement`,
    `step!`, `reset!`, `statement-sql`, `parameter-count` and `column-count`;
  - each verb makes decision 3's checks, then the state's, in one critical section, and raises
    after it;
  - `call-with-statement-handle`, the one accessor of a statement's handle, for slice 4. Its
    procedure gets both handles and the SQL, and may move the state;
  - the connection's live statements, and the close that finalizes them oldest first, then
    raises the first failure with the connection closed (R1);
  - the public names, the three subtypes' predicates, and their docs;
  - `c-string->string` keeps a leading U+FEFF, for a trigger's message.
- **Measured,** on 3.53.1 and 3.45.1 alike ([research/m2-slice-3/](research/m2-slice-3/)):
  - the four blocking calls each wait 1502 ms, then answer BUSY. Bound `__collect_safe`, another
    thread's collection ends in 0 to 1 ms, against 1402 ms;
  - nothing in M2's own surface can make the close fail once its statements are finalized;
  - SQLite's −1 offset also comes for a missing table, a missing collation and a busy prepare;
  - `call-with-statement` doesn't survive an engine's preemption;
  - the tail scan agrees with SQLite's own prepare on 20,602 inputs.
- **From M3's research,** found by the M1 session and reproduced here:
  - an interrupt doesn't end a lock wait;
  - COMMIT answers BUSY while the connection's own write is unfinished. Slice 4 corrected "mid-row":
    a SELECT mid-row doesn't stop it;
  - an `ALTER TABLE` on the statement's own connection changes its column count at its next step;
  - inside a transaction, a NOMEM read rolls the transaction back at the next reset or finalize.
- **Decided by the maintainer** (2026-11-15):
  - a column read's NOMEM moves the statement to `failed` ("Move it to `failed`");
  - asked again with the rollback measured, the choice stands ("Keep it: no second raise");
  - ADR-0014's slice 3 amendment accepted ("Accept it").
- **Watched failing:** each suite red first. Part A and the review's fixes: 92 mutations, 88
  caught, 4 argued. Part B: 37, all caught ([the log](m2-slice-3-mutation-log.md)).
- **Reviewed** (Opus, read-only): no blocker, 3 majors and 5 minors, each reproduced, all fixed.
  - **The majors:**
    - decision 10's "change together" was held by no row: with the state set after its section,
      two engines ran a done insert twice;
    - nothing held the record's opacity;
    - the accessor gave its procedure no SQL for slice 4's errors.
  - **The minors:**
    - N02's survivor wasn't equivalent;
    - the tail oracle re-decoded the tail;
    - a docs fact;
    - two comments that claimed checks the rows didn't make.
- **CI:** passed in all five jobs on `1eff5be`, before the review's fixes; `memory` took 20m32s.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Part A: the library and its suites | Opus | about 593k | 174 | 53 min |
  | Part B: the public names and docs | Sonnet | about 138k | 56 | 14 min |
  | Adversarial review | Opus | about 308k | 80 | 19 min |
  | The review's fixes | Sonnet | about 210k | 83 | 28 min |

- **Learned** ([traps.md](traps.md)):
  - A rule two engines can break needs a two-engine row. Every "change together" passed the
    suites until the sweeps came.
  - A flag set by a blocked thread can't show that its call returned before a collection.
  - An error message can be the user's own text.
  - An interrupt doesn't end a wait in the busy handler.
  - Another session's research, checked before it was used, found two record gaps and a design
    question the slice had missed.

### 2026-11-15 — M2 slice 2: the bindings (PR #17, `f2ffa0e`)

- **Built:**
  - native's 21 new bindings, ADR-0002's M2 amendment in its order, each checked with
    `foreign-entry?` before it is bound. Prepare, step, reset and finalize are `__collect_safe`,
    and every pointer is a `uptr`;
  - `sqlite-transient`, all ones at a pointer's width;
  - the constants `SQLITE_ROW`, `SQLITE_DONE`, the five type codes and `SQLITE_UTF8`;
  - the convention table's 21 rows, with their prototypes held to `sqlite3.h`;
  - a decoy switch and a `missing-api` row per entry point, with the list held to the table;
  - `test-native`'s rows:
    - prepare and its tail, and failed prepares' offsets;
    - binds round-tripped through SQLite at the boundaries a narrower type breaks, `SQLITE_TOOBIG`
      for a length past 32 bits among them;
    - SQLite's copy of TEXT and BLOB;
    - every column held whole to a new mode of the C oracle, and to a written literal.
- **Measured,** on 3.53.1 and 3.45.1 alike:
  - prepare's error offsets: 10 and 13 bytes for an unknown column, 0 for an unknown keyword, and
    −1 for an error at the end of the SQL;
  - `select :alpha, ?7, $beta` has 8 parameters, at indexes 1, 7 and 8.
- **The gate:** `test-library-loading` took 409.3 s on CI, against 308 s before, so it wasn't split.
  That was one fast run: on slower runners it reached 562 s, and slice 4 split it (ADR-0005,
  amended). Every child grew about 0.3 s, since each compiles native under Valgrind.
- **Decided by the maintainer:** on 2026-11-14, the stacked order, each slice opened as a PR and
  the next begun on it; on 2026-11-15, ADR-0005's and ADR-0011's amendments accepted
  ("Accept both").
- **Watched failing:** each suite red first; 62 mutations, 60 caught, and the 2 survivors argued
  equivalent ([the log](m2-slice-2-mutation-log.md)).
- **Reviewed** (Opus, read-only): no blocker, 3 majors and 5 minors, each reproduced.
  - **The majors:**
    - the decoy's entry list was held to nothing;
    - the gate's cost model, which CI's measurement settled;
    - Chez's `int` range, which slice 3's prepare must check (ADR-0011, amended).
  - **The minors:**
    - the columns row's coverage rested on SQL nothing asserted;
    - two length types were held only by form;
    - the constraints' wording of `SQLITE_TRANSIENT`;
    - the oracle's comment.
- **CI:** passed in all five jobs on `811db14`; `memory` took 19m1s.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Builder | Opus | about 470k | 131 | 44.6 min |
  | Adversarial review | Opus | about 330k | 106 | 28 min |
  | The review's fixes | Sonnet | about 122k | 43 | 12.2 min |

- **Learned** ([traps.md](traps.md)):
  - Chez's `int` isn't C's, and a raise can come from the call itself, inside its section.
  - A list that makes rows makes no row for what it drops.
  - A REAL's text differs between SQLite versions.
  - A planted library must sit in a whole copy of the tree.
  - Arithmetic missed the gate both ways: the plan's 430 s and the review's 500 s against CI's
    409 s. The cost is CI's to say, and one run isn't CI: the closing review found 562 s.

### 2026-11-14 — M2 slice 1: the pure core (PR #16, `e6b2462`)

- **Built,** in pure Scheme on synthetic inputs, with no foreign code. Slices 3 and 4 call much of
  it inside critical sections, so every classifier, reader and scanner answers data, and only the
  `raise-…` procedures raise.
  - `(chez-sqlite3 private conditions)`: `&sqlite-busy`, `&sqlite-constraint` and
    `&sqlite-read-only`, classed by primary code in `make-sqlite-error`, so M1's raises get them
    unchanged; `&sqlite-invalid-text` and its raiser.
  - `(chez-sqlite3 private values)`: `sql-null`; `bind-plan`, with its four refusal rules;
    `raise-bind-refusal`, which names a value by its kind only; the NULL-pointer readers of a
    column's bytes and name, which take their foreign calls as procedures.
  - `(chez-sqlite3 private utf8)`: the strict decoder, by Unicode's Table 3-7, with the maximal
    ill-formed subpart's offset (D6); byte offsets into character indexes (Q6).
  - `(chez-sqlite3 private statement-state)`: the verb × state table, the state a step leaves, and
    which reset or finalize answers are failures of their own.
  - `(chez-sqlite3 private sql-tail)`: the tail scan (R2).
- **Measured first** ([research/m2-slice-1/](research/m2-slice-1/)):
  - **the tail:** every SQL of 1 to 3 bytes, and 8.1M of 4 to 6, prepared alone on 3.53.1 and the
    floor alike. The scan as accepted disagreed with SQLite on 56,425 of them; amended, on none;
  - **the decoder's cost:** 1.5 to 2.3 times `utf8->string`, about 1.5 ms per MiB, so TEXT is
    checked byte by byte, as ADR-0015 says;
  - **the decoder against Python's:** 65,896 of 65,896 inputs agree.
- **Decided by the maintainer** (2026-11-14): to start slice 1 before #15 merged, on files #15
  didn't touch ("Start slice 1 now"); and the tail's whitespace, "Match SQLite": `\v` continues a
  run, and U+FEFF followed under the same choice (ADR-0014, amended); ADR-0015's amendment
  accepted ("Accept it"); and the merge.
- **Watched failing:** each suite red against a stub first; 470 mutations, 461 caught, and the 9
  survivors argued equivalent ([the log](m2-slice-1-mutation-log.md)).
- **Reviewed** (Opus, read-only): 1 blocker and 9 minor findings, each reproduced before it was
  fixed.
  - **The blocker:** Chez's `utf8->string` drops a leading U+FEFF, so a TEXT value starting with
    one read back changed. The round trips sampled every 257th scalar value and skipped it. The
    decoder restores it, and a row round-trips every scalar value alone.
  - **The minor findings:** the NULL-pointer reader reads the message too, keeping the order in
    tested code; `utf8-offset->index` no longer answers −1; `raise-bind-refusal` checks its who;
    SQLite's 798 accepted 3-byte tails became a second literal; and comments, a message, a row's
    name and the log's wording.
- **Records:** ADR-0014 amended by the maintainer's choice; ADR-0015 amended, and accepted; the
  plan's §4 and §7; the constraints' tail rule. After the rebase onto #15: this
  ledger, the traps, and ADR-0012's citation of #15.
- **CI:** passed in all five jobs on `cd95ac1`, before the rebase; `memory` took 16m23s.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Builder | Sonnet | about 288k | 94 | 38.5 min |
  | Adversarial review | Opus | about 314k | 76 | 17.6 min |
  | The review's fixes | Sonnet | about 177k | 77 | 17.6 min |

- **Learned** ([traps.md](traps.md)):
  - Chez's `utf8->string` drops a leading U+FEFF, and the brief had called it exact. A round trip
    over a sample skipped the one value that mattered: where the whole set is small enough, take
    all of it.
  - A record's model of SQLite's tokenizer disagreed with prepare on 56,425 short inputs. Measured
    over the whole complement before the build, it cost an amendment, not a rewrite.
  - A condition type's name is syntax, not a record type, and Chez shares its empty bytevector.
  - ADR-0015's amendment gave a false reason, that M1 doesn't bind `sqlite3_errcode`, and the
    maintainer accepted it so. It was found reading the records for slice 2, and corrected before
    the merge. A record's claim about the code is checked against the code, like any other.

### 2026-11-14 — M1's closing review and its fixes (PR #15, `1b2f688`)

- **Reviewed** (Opus, read-only, on `497d45b`): no blocker, 3 major, 6 minor, all reproduced:
  - **Raises inside critical sections at eight sites,** not the ledger's two. A
    `with-exception-handler` handler of one runs with interrupts disabled, where an engine never
    expires and another thread's collection waited more than 11 s.
  - **`open-database` and `sqlite-compile-option?` refused under engines,** at fuel 20 every time.
  - **`test-ci-sqlite`'s build rows failing on a bare `CHEZ`,** which the Mac found first.
- **Built** (decided by the maintainer, 2026-11-14: the scope, all sites, and the procedure's
  contract):
  - **The rule:** nothing raises inside `critical-section` or a critical `dynamic-wind` thunk, in
    `src/` or the testing library. Nine sites now answer data and raise after their sections.
  - **`call-with-open-handle`** checks the database and its owner before its section. Its
    procedure answers data, its raise isn't resumable, and a re-entry is refused.
  - **The open and `sqlite-compile-option?`** hold their C string in one section, and complete
    under engines.
  - **`check-ci`** holds the CI scripts' execute bits, and refuses a line naming `scripts/` in any
    other spelling. `make check-ci` clears `CHECK_CI_ROOT`.
  - **Stale comments,** and the detail's docs.
  - **Strict branch protection.**
- **Reviewed again** (Opus, read-only, the fixes): no blocker, 1 major, 6 minor.
  - The major: no row held the section's purpose, so two mutants handed the procedure a freed
    handle.
  - All were fixed or recorded. Most of the minors were older than the fixes.
- **Watched failing:** every new row first, the builders' 25 mutations, and the caller's own
  ([the log](m1-closing-review-mutation-log.md)).
- **Records:** amendments to ADR-0012, ADR-0011 and ADR-0005, which the maintainer accepted on
  2026-11-14. Also the acceptance of slice 5's and PR #12's amendments, and the rule in
  `AGENTS.md` and the constraints, approved by the maintainer that day.
- **The Mac:** 26 of 26, on both libraries, on `0c2aad2` and again on `594ef6a`.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | M1's closing review | Opus | about 452k | 124 | 28 min |
  | Critical sections and engines | Opus | about 448k | 170 | 60 min |
  | The minor findings | Sonnet | about 106k | 42 | 16 min |
  | Review of the fixes | Opus | about 308k | 81 | 26 min |
  | That review's fixes | Sonnet | about 148k | 86 | 11 min |

  The minor findings were fixed in a worktree of their own, beside the critical-section builder.
- **Learned** ([traps.md](traps.md)):
  - A `guard` hides what a `with-exception-handler` handler sees. Every depth row reads the
    depth in a handler.
  - A rule's purpose needs a row of its own. The section existed so that no close falls between
    a check and its use, and nothing held that until the second review.
  - An engine spends no ticks inside a section.

### M1 is done

M1's slices 0 to 5 (PRs #7 to #11 and #13), its owed fixes (PR #12) and its closing review
(PR #15) are merged, with CI passing in every job. The maintainer's Mac ran the suites on both
libraries. Next is M2, whose plan is ADR-0014 and `.plans/2026-11-14-m2-plan.md`.

### 2026-11-14 — M2 slice 0: the plan and the records (PR #14, `3d24cce`)

It merged before M1's closing review, while that ran in another session, so its close-out is
written here, in M2 slice 1's branch, after #15 had rewritten this ledger.

- **Built:** [the M2 plan](2026-11-14-m2-plan.md); ADR-0014, statements, and ADR-0015, values;
  amendments to ADR-0002, ADR-0005, ADR-0011, ADR-0012 and ADR-0013; brief D3 to D6 settled; the
  global constraints' "Statements and values"; [research/m2-plan/](research/m2-plan/) and
  [research/m2-review/](research/m2-review/).
- **Decided by the maintainer** (2026-11-14): D3 to D6, Q1 to Q8, R1 and R2 (the plan, §2 and §3);
  the records accepted, and the slicing approved.
- **Measured,** on 3.53.1 and 3.45.1 alike:
  - autoreset reruns a finished insert;
  - prepare drops a second statement;
  - a once-stepped `insert … returning` loses its rows at a reset or finalize under a reader;
  - reset and finalize block in the busy handler (1502 ms);
  - `clear_bindings` while a row is ready is a use-after-free, which Valgrind sees only with values
    bigger than lookaside;
  - preparing a PRAGMA has side effects;
  - `integer-64` wraps at 2⁶³.
- **Reviewed** twice (Opus, read-only), each finding reproduced before it was fixed:
  - the records: 2 blockers, 7 majors, 14 minors;
  - the fixes: no blocker, 2 majors, 8 minors.
- **Handed to M1:** the two raises inside `connection.sls`'s critical sections, agreed with the M1
  session. Its closing review fixed them in #15, with seven more sites (ADR-0012, amended).
- **CI:** passed on every run; `memory` took 14m35s, 18m56s and 14m58s. `main` moved twice under
  the branch, with #12 and #13, and ADR-0005 conflicted each time, since both sides appended an
  amendment; M2's went last. The first merge attempt failed DIRTY after CI had passed.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Slice 0's adversarial review | Opus | about 305k | 71 | 24 min |
  | The review of the fixes | Opus | about 274k | 60 | 19 min |

- **Learned:**
  - A rule drawn from one measured answer ("reset and finalize only repeat a step's code") doesn't
    bound what a call can answer: read the call's documented failure paths too.
  - A test modelled on a block that never ends by itself (the FIFO) passes a binding that blocks
    until a timeout ends it.
  - Unsetting `CHEZ_SQLITE3_LIBRARY` inside the container leaves a probe with no library, and its
    Valgrind log reads clean.
  - Valgrind logs carry the checkout's absolute path: scrub them before committing.
  - Status lines overclaimed again, as in M1 slice 0: quote the option the maintainer picked.

### 2026-11-14 — M1 slice 5: the `floor` and `current` lanes (PR #13, `497d45b`)

- **Built:**
  - `scripts/ci/build-sqlite.sh`, which builds SQLite from sqlite.org's autoconf tarball:
    - it checks the archive's SHA3-256 before anything is unpacked, then `sqlite3.c`'s against
      the release log's;
    - it compiles with SQLite's defaults and fixed flags;
    - its pins are keyed by role.
  - `scripts/ci/check-sqlite.sh`, which holds what a lane loads:
    - the override, and the header the compiler finds;
    - the version, number and source id;
    - `threadsafe` 1;
    - every compile option, whole and in order.
  - `test-ci-sqlite`, the suite for both.
  - The `floor` and `current` jobs, and `check-ci` holding five jobs: the lanes' two env keys,
    only the checkout and cache actions, and each cache restored before its build.
  - `check-floors` over `scripts/ci/`: both floors, file names, and lines joined at a trailing
    backslash. `build-chez.sh` now pins by role.
- **Measured first:**
  - sqlite.org's published digests, which match. 3.45.1's archive digest is no longer published,
    only its `sqlite3.c`'s.
  - 37 and 38 compile options. `DEFAULT_MEMSTATUS` is unlisted at 1, so the whole list is what
    refuses `=0`.
  - The suites passed 25 of 25 against both builds.
  - A bare Ubuntu 24.04 has no `openssl` or `unzip`, so the lanes take the tarball, and
    `openssl` is listed.
- **Watched failing:** every logged mutation, and three run by the caller
  ([the log](m1-slice-5-mutation-log.md)).
- **Reviewed** (Opus, read-only): no blocker, 2 major, 7 minor, all reproduced, and each fixed or
  answered (the required checks; the warm run):
  - `check-ci` held no cache step order, and passed another cache action;
  - `check-floors` read no file names;
  - a floor split at a trailing backslash passed;
  - no row reached the build's success path;
  - part C's red runs proved nothing.
- **CI:**
  - **The cold run passed in all five jobs.**
    - The floor built in 17 s, and its check passed 37 options with `COMPILER=gcc-13.3.0`; the
      current release built in 23 s, with 38 options.
    - Every job built Chez again, once, since `build-chez.sh` changed.
  - **The warm run** restored both SQLite caches and checked them again: `floor` took 1 min 20 s
    and `current` 1 min 5 s.
- **Decided by the maintainer** (2026-11-14): the merge, and `floor` and `current` as required
  checks.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Phase 1: table and measurements | Opus | about 397k | 93 | 27 min |
  | Part A: `check-floors` over `scripts/ci/` | Sonnet | about 185k | 56 | 11 min |
  | Part B: the SQLite scripts and their suite | Opus | about 420k | 114 | 50 min |
  | Part C: the workflow and `check-ci` | Sonnet | about 216k | 45 | 16 min |
  | Adversarial review | Opus | about 347k | 88 | 22 min |
  | The review's fixes | Sonnet | about 228k | 65 | 19 min |

  Parts A, B and C ran in worktrees of their own, on disjoint files.
- **Learned** ([traps.md](traps.md)):
  - A rule that says "writes none" needs a check that reads everywhere it covers: `build-chez.sh`
    had written the Chez floor since M0, unseen.
  - A red run against a check that refuses the whole input proves no row.
  - A row that narrows `PATH` must hand each tool it names over by its path. The Mac found that.

### 2026-11-14 — M1's owed fixes (PR #12, `2579a0d`)

- **Built:** the counters' refusals lead their irritants with `not-a-kind` or `double-free`, and
  `test-counters` asserts who and irritants only. `make test-memory` refuses a checkout whose path
  holds whitespace, and `check-memory-gate` has `g whitespace`, a space and a tab in real
  directories (ADR-0005, amended).
- **Watched failing:** each message reworded, each rule symbol misspelt, swapped and dropped; the
  refusal removed, reworded, widened to every path, and narrowed to a space
  ([the log](m1-owed-fixes-mutation-log.md)).
- **CI:** passed in all three jobs, on the PR and on `main`.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | The two fixes | Sonnet | about 102k | 40 | 24 min |
  | The scratch worktrees removed | Haiku | about 40k | 23 | under 1 min |

### 2026-11-14 — M1 slice 4: the public library and connections (PR #11, `2f1c62d`)

- **Built:** `(chez-sqlite3)`, re-exporting 28 names: the report, the version and compile
  options, `open-database`, `close-database!`, `call-with-database`, `database?` and every
  condition's predicate and accessors. Connections owned by the thread that opened them, the
  open options with the mutex mode, and the connection counter. The memory check at a suite's
  exit, `sqlite3_memory_used` against a baseline, with an uncounted open and close as its
  control. The connection plant through `open-database`; `sqlite3_next_stmt` in
  `close-database!`; `docs/reference.md`, with `test-reference` and `test-docs`.
- **Measured first:** on CI's runner, Ubuntu's 3.45.1 came back to its 0-byte baseline after a
  full open and close (ADR-0005, amended).
- **Watched failing:** every logged mutation, with the gate's and the docs' in logs of their own
  ([the log](m1-slice-4-mutation-log.md), [the docs'](m1-slice-4-docs-mutation-log.md)).
- **Reviewed** (Opus, read-only): no blocker, 1 major, 10 minor. The fixes answer the major and
  the mutants the log reproduces. The docs promised that a `guard` catches a load that fails,
  which it can't in a program; `test-never-loads` checked imports only, not what referencing
  every export loads.
- **The maintainer's Mac** found four portability bugs CI couldn't: a Chez not named `scheme`, no
  `/proc` (two suites), and Apple's library answering `CANTOPEN` where the others answer
  `IOERR`. All fixed before the merge; the rerun passed 25 of 25 on Apple's and Homebrew's
  libraries.
- **Decided by the maintainer** (2026-11-14): the records accepted;
  `sqlite-library-unavailable-library` left unexported; `test-reference` holds the docs'
  signatures to the source's, AGENTS.md's one exception to the rule on comments; branch
  protection on `main`.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Connections and the public library (table, then build) | Opus | about 890k | 128 | 48 min |
  | The docs | Sonnet | about 141k | 32 | 10 min |
  | The memory check and the connection plant | Opus | about 385k | 125 | 33 min |
  | Integration with slice 3 | Sonnet | about 123k | 60 | 23 min |
  | Adversarial review | Opus | about 333k | 85 | 20 min |
  | The review's fixes | Sonnet | about 192k | 70 | 20 min |
  | The signature check restored | Sonnet | about 59k | 11 | 3.9 min |

  The docs and the gate's work ran in worktrees of their own, beside the builder.
- **Learned** ([traps.md](traps.md)): macOS has no `/proc`; a test can't take `CHEZ`'s file name
  for the Chez binary's; one failure can answer different codes on different builds. And the
  Mac run belongs before a slice's review, not after it: it found what CI never could.

### 2026-11-14 — M1 slice 3: refusals end to end (PR #10, `7c7d321`)

- **Built:** a decoy libsqlite3, compiled at test time, one build per missing entry point, its
  behaviour chosen by `CHEZ_SQLITE3_DECOY`; the refusal probe; `test-library-loading`, one fresh
  process per case, every outcome asserted whole, the step order held by behaviour; `make dev` and
  `check-dev`; children under the gate's own Valgrind through `gated-command`; CI's install check
  by discovery, and `check-dev` on the make line.
- **Measured first:** `--trace-children` can't gate Chez's children: traced, its static bash
  makes every child exit 9, and skipping the shell untraces everything below it (ADR-0005,
  amended).
- **Watched failing:** every logged mutation, the paths slice 2 couldn't reach among them
  ([the log](m1-slice-3-mutation-log.md)).
- **Reviewed** (Opus, read-only): no blocker, 3 major, 11 minor, all reproduced and fixed. A gated
  child that forked failed the gate though clean; 12 of 53 children asserted nothing about the
  gate; the log's timings came from an older tree.
- **CI:** the install check found `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0 (system)`, 3.45.1.
  `test-library-loading` takes 308 s of `MEMORY_TIMEOUT`'s 600 under the gate, and the memory
  job 11 to 14 minutes.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Builder (table and measurements, then build) | Opus | about 975k | 232 | 93 min |
  | Adversarial review | Opus | about 277k | 101 | 23 min |
  | The review's fixes | Sonnet | about 217k | 103 | 45 min |

- **Learned** ([traps.md](traps.md)): a skip list under `--trace-children` hides all below it;
  GNU `env` reads `-u` only before its first assignment; a row anchored by an occurrence count
  breaks when the file gains one. And a claim of coverage is checked row by row: "every child
  says it ran under memcheck" was 41 of 53.

### 2026-11-14 — M1 slice 2: the load and the checks of the FFI (PR #9, `b0ffbae`)

- **Built:** `check-seam`; the constants, every result code at the floor's header, checked against
  `sqlite3.h`; `(chez-sqlite3 private memory)` and `native`, the load in seven steps with
  `sqlite3_initialize` among them; `test-native` against a C oracle that `dlopen`s the same file;
  the convention table and suite; `make build`.
- **Measured:** a plain blocking `sqlite3_open_v2` hangs every thread's collection;
  `__collect_safe` doesn't, even inside `critical-section` (ADR-0011, amended).
- **Watched failing:** seam 32, constants 6 on two headers, native 33, conventions 16, then the
  review's ([the logs](m1-slice-2-mutation-log.md)).
- **Reviewed** (Opus, read-only): no blocker, 2 major, 10 minor, all fixed. Message-text
  assertions had come back; a keyword alias of `foreign-procedure` hid a `string`-typed binding
  from every check.
- **CI:** the exact result-code check ran against the runner's 3.45.1 header; `test-native` passed
  under Valgrind 3.22 with Ubuntu's 3.45.1, the closing review's unmeasured case.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | `check-seam` (table, then build) | Sonnet | about 415k | 84 | 25 min |
  | Constants and test-constants | Sonnet | about 116k | 26 | 5.6 min |
  | Native load and oracle (table, then build) | Opus | about 831k | 199 | 46 min |
  | Convention suite and prototypes | Sonnet | about 178k | 52 | 11 min |
  | Adversarial review | Opus | about 326k | 71 | 20 min |
  | The review's fixes | Sonnet | about 173k | 60 | 11 min |

  The seam and constants agents worked in worktrees of their own, beside the native builder.
- **Learned** ([traps.md](traps.md)): a scanner of forms reads elements, never tails; a probe that
  blocks a plain call can't release itself. And a rule fixed in one slice's suites is restated in
  the next slice's briefs: message text came back.

### 2026-11-14 — M1 slice 1: the pure core (PR #8, `f70b5ee`)

- **Built:** `(chez-sqlite3 private discovery)`, `load-state`, `conditions` (the root and
  `&sqlite-library-unavailable`), `libsqlite3-info` and `verify`, with five suites, all on
  synthetic inputs.
- **Watched failing:** each suite red against a stub first; 121 mutations, 120 caught, the survivor
  unreachable ([the log](m1-slice-1-mutation-log.md)).
- **Reviewed** (Opus, read-only): the code sound; 17 mutations every suite passed, one of them an
  override that searched `LD_LIBRARY_PATH`. All now caught, against complements, not samples.
- **CI:** passed in all three jobs; `nothreads` refused every new library by name.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | Builder (copy table, then build) | Sonnet | about 402k | 75 | 24 min |
  | Adversarial review | Opus | about 219k | 37 | 15 min |
  | The review's fixes | Sonnet | about 152k | 37 | 7.4 min |

- **Learned:** a copy's table of what it drops, checked before the build, caught two of the
  builder's own questions early. An allowlist is tested against its complement in every slice,
  however small it looks.

### 2026-11-14 — M1 slice 0: the plan and the records (PR #7, `6bed21c`)

- **Built:** the M1 plan; ADR-0010 to ADR-0013; amendments to ADR-0002, ADR-0005, ADR-0009, the
  brief and the constraints; brief D7, measured on the maintainer's Mac.
- **Decided by the maintainer:** eight questions on 2026-11-13 and 2026-11-14, and on 2026-11-14
  every record of the slice accepted.
- **Reviewed** (Opus, read-only): no blocker, 8 major, 15 minor, all fixed. No record said which
  entry points are required, so Apple's library would have been refused; the status lines claimed
  more acceptance than the maintainer had given; the plan's probe depended on argument order.
- **Subagents:** one, Opus: the review, about 210k tokens, 55 tool calls, 16 min.
- **Learned:** a status line says only what the maintainer approved; the rest is proposed, and
  its constraints provisional, until accepted.

### 2026-11-13 — M0's closing review and its fixes (PR #6, `d85c28c`)

- **The review** (harness plan §6) ran on Opus, read-only, over the five slices and the harness
  plan, on a snapshot of `main` at `37bb4c4`. It found no blocker and four major findings. Every
  finding was reproduced before it was fixed.
- **Fixed** ([the log](m0-review-mutation-log.md)):
  - **`check-floors` refuses SQLite's floor in its numeric forms,** `3045001` and `3450100`, as
    whole runs of digits (finding 1, ADR-0008).
  - **`check-test-fails`' case `ci` holds `check-ci`'s place in `make test`.** Removing the
    prerequisite had passed every check (finding 2, ADR-0005 and ADR-0007).
  - **`check-ci` holds the version reports** (finding 7, ADR-0006). `test-check-ci`'s top-level
    raise is guarded (9), and the helper suite's rows assert in no fixed order, and whole (10).
  - **The records say what holds and what doesn't** (5, 6, 8, 11).
  - **Findings 3 and 4 shaped M1's plan:** where SQLite's two checks run, and how `check-ci`
    loosens for new jobs (ADR-0005, amended).
- **Watched failing:** 20 mutations, H1 to H4, F7 to F14, C10 to C15, T29 and T30, each failing
  its check. Final runs: `test-check-floors` 322 passed, `test-check-ci` 150, the helper suite 60
  compiled and interpreted, and `check-test-fails` 11 cases.
- **The fixes were reviewed too** (Opus, read-only): no blocker, two major findings, both
  reproduced and fixed. A third helper-suite row still depended on argument order, and passed
  interpreted under a mutation it failed compiled. `check-floors`' boundary wasn't tested against
  its complement: a range that took `=` for a letter passed every row.
- **CI:** the PR's run passed in all three jobs, with the same counts as the container, and so
  did `main`'s after the merge.
- **Subagents:**

  | Agent | Model | Tokens | Tool calls | Time |
  |---|---|---|---|---|
  | M0's closing review | Opus | about 372k | 73 | 17 min |
  | The floors' numeric forms | Sonnet | about 81k | 18 | 3 min |
  | `check-ci`'s report steps | Sonnet | about 102k | 18 | 4.5 min |
  | The helper suite's rows | Sonnet | about 51k | 9 | 1.3 min |
  | `check-test-fails`' case `ci` | Sonnet | about 56k | 10 | 1.8 min |
  | The fixes' review | Opus | about 233k | 57 | 15 min |
  | The boundary's complement | Sonnet | about 56k | 8 | 1.3 min |
  | The last order-dependent row | Sonnet | about 63k | 16 | 1.5 min |
  | The order checks | Sonnet | about 57k | 10 | 1.5 min |

  The builders ran in parallel on disjoint files, and the `check-test-fails` agent after them,
  since it copies the whole tree.
- **Learned:**
  - A brief quotes every AGENTS.md rule that binds what it builds. The boundary's brief gave
    sample characters, not "an allowlist against its whole complement", and a looser range passed
    every row.
  - A finding names one instance; a brief names its class and asks for a sweep. Finding 10 named
    one order-dependent row, and its sibling 30 lines below had the same defect.
  - A record says what a check holds, what still passes, and the run that shows it. "Any form",
    "the whole shape" and "is now a check" each claimed more than the check held.
  - Where a mutation landed is checked, not only its verdict. A plant recorded as inside `main`
    had been appended at the file's end; rerun inside `main`, it was refused.

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
