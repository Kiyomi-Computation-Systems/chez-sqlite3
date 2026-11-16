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
  ADR-0020, the same day ("Accept all").
- **Branch protection is on for `main`** (the maintainer asked, 2026-11-14). All five jobs are
  required: `main`, `memory` and `nothreads`, and, since slice 5 merged, `floor` and `current`.
  Since M1's closing review, it is strict too: a PR must be up to date with `main` before it
  merges. Force pushes and deletion are refused. Admins can override.
- **Now: M3 slice 1, the pure core, is PR #22 on `m3-slice-1-core`.** Slice 2, the bindings, is
  PR #23 on `m3-slice-2-bindings`, built beside it by the M2 session and stacked on it. The maintainer's
  order, 2026-11-15: slices 1 and 2 in parallel, then 3, then 4 (the M2 session) and 5 in
  parallel, then 6, each its own PR, stacked on the one before
  ([the M3 plan](2026-11-15-m3-plan.md), §5). M2's slices ran in the stacked order of 2026-11-14
  too, and M2's Mac run is done, below.
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
- **Open:** the M3 plan's probes P4, P5, P6 and P8, each in the slice it names (its §7, §8).
  Brief D3 to D6 are settled (the M2 plan, §2), and M2 split `test-library-loading` in #19
  (ADR-0005, amended).

## Close-outs

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
- **Records,** proposed in this PR:
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
  against 22m04s on `main` at `3e2460b`.
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
