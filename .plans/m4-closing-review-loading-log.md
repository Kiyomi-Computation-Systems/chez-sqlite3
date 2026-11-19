# M4's closing review: the loading suites' split (builder E2)

The findings file's B4 and Proposal 3. On `main`'s last two CI runs `test-library-loading-real`
took 258 s and 264 s, over half the 450 s at which `make test-memory` names a suite `SLOW`. An
Opus agent split the three loading suites into nine, from the lead's brief, in the worktree
`chez-sqlite3-wt-m4cr-e2`, on `m4cr-loading` from `main` at `34721b4`, beside builders C, D and
E1 on disjoint files. The drivers are under
[research/m4-closing-review/loading/](research/m4-closing-review/loading/), each run from the
worktree's root, the suites in the container. Nothing was committed.

## The layout

Each suite runs at most 11 children. The rows are the old ones, moved: no row's name or expected
value changed but the partition's four (below).

| Suite | Rows | Children | Builds compiled | Holds |
|---|---|---|---|---|
| `-missing-1` | 20 | 11 | 11 | missing-api rows of its part, and the partition's four rows |
| `-missing-2` | 20 | 11 | 11 | the same |
| `-missing-3` | 20 | 11 | 11 | the same |
| `-missing-4` | 19 | 10 | 10 | the same |
| `-real` | 26 | 11 | none | the real libsqlite3, its oracle, the override, the oracle's own guard; the refusals no decoy reaches; discovery and not-found by world; preflight on the real libsqlite3 |
| `-preflight` | 14 | 9 | control | preflight on the control, below the floor, a bare name, the raising fixture and Guix's not-found; the probe on the raising fixture |
| `-extension` | 12 | 7 | control, lacks-load_extension | M4's seven decoy rows: the optional entry point, the opt-in's check, `load-extension!` |
| `-decoys` | 18 | 11 | control | the eleven switch rows; the `CC` row; the entry lists against the convention table |
| `-combined` | 14 | 9 | 7 | lacks-rest, not-sqlite, the five order rows, the kept refusal, the marker |
| **nine** | **163** | **90** | | |

Before: `-real` 53 rows and 35 children, `-decoys` 40 and 29, `-missing` 35 and 26: 128 rows,
90 children. Children counted from the gate's per-child logs, `build/memory/<suite>.children/`.

**One move beyond Proposal 3's table.** Its `-preflight` held all nine preflight children, but
"preflight, the real libsqlite3" needs the real library's path, which `-real`'s ambient probe
finds, and that path's oracle report: in `-preflight` that is two more children, 11. So that row
went to `-real`, beside the two it reads, and the probe's raising-fixture row went to
`-preflight`, beside preflight's raising row, which shares its fixture. `-real` 11 and
`-preflight` 9, as the table counted.

**The partition.** `deal-pattern` is now four names, `-missing-1` to `-4`, by position mod 4: 11,
11, 11 and 10 of the 43 required entry points. The report's three fall to suites 1, 2 and 3,
`sqlite3_threadsafe` to 4 and `sqlite3_initialize` to 1, so each of `missing-api-rows`' four
branches runs. `decoy-parts` is written out. `sqlite3_load_extension` would be dealt to
`-missing-4` were it joined to `every-entry`, and its rows run in `-extension`.

**The partition's four rows**, in each missing suite (they were in each of the three):
- "the four missing suites' entry lists partition the required entry points…" (was "the three
  suites'…"), expected `every-entry`;
- "each suite's part is the entries the pattern deals it…", the same name, expected the new parts;
- "the pattern deals positions 0, 1, 2 and 3 of every four to the missing suites 1, 2, 3 and 4"
  (was "…0, 2 and 4 of every five…"), the pattern written out;
- "this suite runs its own part of the partition…", the same name, expected the suite's own name
  and the four files present.

The five other suites hold no part, so no partition row.

## What moved into `(library-loading)`

From `-real`, since `-real` and `-preflight` both use them, each with its type comment:

```scheme
;; field : Any Symbol -> Pair
;; make-directory : String -> (U 'made (List 'not-made Any))
;; machine-platform : -> (U 'linux 'macos 'other)
;; process-world : -> (U 'guix 'fhs (List 'raised String))
;; unset-override : (Listof String)
;; no-profiles-env : String -> (Listof String)
;; guix-candidates-in : String -> (Listof String)
;; lines-of : String -> (Listof String)
;; text : Any ... -> (U String (List 'unbuildable Any))
;; counts-line : String
;; accepted-text : Any Symbol Report -> (U String (List 'unbuildable Any))
;; preflight-in : String (Listof String) -> (List Integer String String Pair)
;; preflight : (Listof String) -> (List Integer String String Pair)
```

`platform`, `world`, `no-profiles` and `guix-not-found-candidates` were values in `-real`; each
suite now defines them by these procedures, so nothing runs at import but the two environment
reads the header names. `gate-log-dir`, `gate-logs`, `command-of-log` and `command-line-of` moved
too, unexported. The library imports `(chez-sqlite3 private discovery)` for `libsqlite3-world`,
and `directory-list`, `file-directory?` and `machine-type` from Chez. `deal-pattern` and
`decoy-parts` keep their signatures.

## The red and green runs

Outside the gate, each suite run from the worktree's root in the container, Guix's 3.53.1.

| Run | Against | Result |
|---|---|---|
| red 1 | the nine suites written, `(library-loading)`'s `deal-pattern` and `decoy-parts` still the three's | each missing suite 7 passed, 2 failed: the written-out pattern (`("test-library-loading-missing.sps" "…-decoys.sps" …)` for the four new names) and its own part (`(unlisted ("tests/test-library-loading-missing-1.sps"))`, `-missing.sps` `absent`). The merge row and the dealing row passed: the old parts still partition the table, as the old pattern deals them. The five other suites passed, 26, 14, 12, 18 and 14 |
| red 2 | `deal-pattern` the new four, `decoy-parts` still the three | `-missing-1` and `-4` each 2 failed: the dealing row and its own part; the written-out pattern now passed |
| green | `decoy-parts` the new four | 20, 20, 20, 19, 26, 14, 12, 18 and 14 passed, none failed: 163 |

The merge row is watched failing by the plants S1 and S2 (below), and each moved row by the plants
that fail it on both layouts.

## Every old row, held after

Each suite's on-test-end hook was made to print every row's kind, name and expected value
(`dump-copy.sh`), in a copy of `main`'s tree and a copy of this one, and the rows compared with the
scratch directory's random name masked (`rows.py`; the whole mapping, old suites to new, is
[rows-guix.txt](research/m4-closing-review/loading/rows-guix.txt)).

- **Old:** 128 rows run, 112 distinct by name and expected value. **New:** 163 run, 113 distinct.
  Every row passes in both.
- **106 distinct rows are held whole,** each with its name and its expected value, so with the same
  verdict: every missing-api row (43), the switches (11), the combinations and the marker (9), M4's
  seven, the real libsqlite3, the refusals, discovery and the preflight rows, the oracle's and
  the message probes' Valgrind rows, and the setup and teardown rows each suite runs.
- **The changed six are the partition's four** (three of them `this suite runs its own part…`,
  one expected value per old suite), replaced by seven, the same four in each missing suite, as
  listed above.
- **Where each went:** the 43 missing-api rows to the four missing suites, as `decoy-parts` deals
  them; `-decoys`' combinations and marker to `-combined`; `-real`'s M4 rows to `-extension`, its
  raising probe and five of its six preflight rows to `-preflight`; the rest stays. The setup rows
  (CHEZ, mktemp, the floors, the world, the empty HOME) and the two teardown rows are held in each
  suite that needs them: the floors' row in the eight that compile a decoy, so not in `-real`; the
  world's and HOME's in `-real` and `-preflight`.

## The times

`make test-memory` on Guix's 3.53.1 (`make build`'s version line read first), the nine suites,
then main's three in a copy of `main`'s tree, run twice on the shared host. The first run was
unpinned; the second pinned to the P-cores (`taskset -c 0-7`), and during its first two suites a
plant run of mine shared the host. Other builders ran throughout (load 4 to 11). The host is an
Intel Core Ultra 5 125H, whose E-cores are slower, so a lone run is no reading of a cost. Children
are the gate's per-child logs.

| Suite | Children | Run 1 | Run 2 | Per child, run 1 | Slow CI, `(children + 2) × 11.5` | Slow CI, worse run `× 11.5 / 5.8` |
|---|---|---|---|---|---|---|
| `-missing-1` | 11 | 68 s | 84 s | 6.2 s | 150 s | 167 s |
| `-missing-2` | 11 | 67 s | 85 s | 6.1 s | 150 s | 169 s |
| `-missing-3` | 11 | 68 s | 72 s | 6.2 s | 150 s | 143 s |
| `-missing-4` | 10 | 61 s | 63 s | 6.1 s | 138 s | 125 s |
| `-real` | 11 | 57 s | 59 s | 5.2 s | 150 s | 117 s |
| `-preflight` | 9 | 52 s | 55 s | 5.8 s | 127 s | 109 s |
| `-extension` | 7 | 56 s | 59 s | 8.0 s | 104 s | 117 s |
| `-decoys` | 11 | 67 s | 71 s | 6.1 s | 150 s | 141 s |
| `-combined` | 9 | 57 s | 60 s | 6.3 s | 127 s | 119 s |
| old `-real` | 35 | 248 s | 205 s | 7.1 s | | |
| old `-decoys` | 29 | 170 s | 169 s | 5.9 s | | |
| old `-missing` | 26 | 159 s | 157 s | 6.1 s | | |

- **Each new suite is well under half the bound** at a slow runner's 11.5 s a child (the findings'
  figure, B's): at most 150 s by children, two more for the parent (B: each parent costs about
  10 s here, two children's worth); at most 169 s scaling the worse run by 11.5 over 5.8, the
  lowest of the old suites' own rates here, parent included. Half of 450 s is 225 s. The
  largest, 11 children, is the bound the split chose.
- **The old suites here,** 205 to 248 s for `-real`, against B's 195 s: the same code, so the
  spread is the host's.
- **The sum** of the nine is 553 s and 608 s, against the three's 577 s and 531 s: each new suite
  pays for its own parent, scratch directory and compiles, about six parents more.
- `-extension`'s children cost the most each: they open and load through the probe.

## The shards

By AGENTS.md's rule, a new suite goes in the shard whose suites take less time on CI. Read from
`main`'s latest three runs, `gh run view --job ID --log` on the host, each memory job's `time:`
lines ([ci-times.txt](research/m4-closing-review/loading/ci-times.txt)):

| Run | Head | Shard 1 | Shard 2 | Old loading suites on CI |
|---|---|---|---|---|
| 44418373153 | `a795fa2` | 1153 s | 1161 s | `-real` 204, `-missing` 171; `-decoys` 190 |
| 44423636001 | `ec48a9d` | 1469 s | 1540 s | 264, 221; 250 |
| 44432932562 | `34721b4` | 1428 s | 906 s | 258, 216; 140 |
| **three runs** | | **4050 s** | **3607 s** | |

`shards.py` ([shards.txt](research/m4-closing-review/loading/shards.txt)):
- takes the old loading suites out: shard 1 2716 s, shard 2 3027 s over the three runs;
- keeps `-real` in 1 and `-decoys` in 2, as now, the suites that keep their names;
- estimates each new suite's CI time on a run's shard as its time here, the two runs' mean, times
  that shard's rate on that run: the old loading suites' CI time there over their time here, 0.83
  to 1.47;
- places each new suite, largest first, in the shard whose three-run total is less.

| Suite, largest first | Here | Shard | Totals after |
|---|---|---|---|
| `-real`, `-decoys` (kept) | 58, 69 s | 1, 2 | 2917, 3263 |
| `-missing-1` | 76 s | 1 | 3181, 3263 |
| `-missing-2` | 76 s | 1 | 3445, 3263 |
| `-missing-3` | 70 s | 2 | 3445, 3503 |
| `-missing-4` | 62 s | 1 | 3660, 3503 |
| `-combined` | 58.5 s | 2 | 3660, 3703 |
| `-extension` | 57.5 s | 1 | 3859, 3703 |
| `-preflight` | 53.5 s | 2 | 3859, 3886 |

So shard 1 holds `-real`, `-missing-1`, `-2`, `-4` and `-extension`; shard 2 `-decoys`, `-missing-3`,
`-combined` and `-preflight`. The first stays a little lighter, as the Makefile's comment says.
Proposal 3's placement differed in `-missing-4` and `-preflight`, which swap: each run alone moved
two or three suites between shards, so the mean is the reading, and the totals differ by 1%.

## The plants, against both layouts

`plants.py` makes each plant in two whole copies, one of `main`'s tree (old: three suites) and
one of this (new: nine), each with the row-printing hook, and `one-plant.sh` runs every loading
suite of the layout from inside its copy, outside the gate, on Guix's 3.53.1; a plant with a make
target runs that alone. `compare.py` reads each copy's exit codes and failing rows
([plants-compare.txt](research/m4-closing-review/loading/plants-compare.txt)). A plant whose old
text didn't occur exactly as often as it says is stale and was never applied in part: none was.

The plants (240):
- **the records' loading mutants:** M1 slice 3's load by behaviour (N1, N2, N3, N10, N19, N20,
  N21, N26, N27, L1, L2, R4 to R11, W2, P1, P2, D1, D2, F1, F2b; rebuilt on today's code), M2
  slice 2's review's list trap (T1, T2), M3 slice 2's partition (S1 to S6), M4 slice 2's round
  three where it ran a loading suite (16), M4 slice 3's 67 and its lead's round three's 15, M4
  slice 4's 65 and its lead's 15;
- **the split's own:** a control (C0); the exit line dropped from each new suite (S6, nine);
  each new suite left out of the shards (S7, nine, and old `-missing` once); and a fault in each
  helper that moved into `(library-loading)`, at its place in each layout (H1 to H9).

A plant of the partition is the same fault on each layout's text: an entry dropped from a part
(S1), in two parts (S2), moved to the front of another with the merge's order kept (S3), two of
the pattern's places swapped (S4), a missing suite finding its part by another's name (S5);
`M4s2-decoy-parts-moved` gets the new partition's text for the same move.

**The rule held: every plant the old layout caught, the new caught,** and with the same number of
distinct failing rows, by the same names but the partition's renamed rows:

| Result | Plants |
|---|---|
| caught by both | 67, S6 on `-missing` and `-missing-1` among them |
| caught, one layout only | S6 on the eight other new suites and S7 on all nine, 17, and S7 on old `-missing`: each by its make target, `check-suites` or `check-memory-shards`, naming the suite |
| caught by old, passed by new | **0** |
| passed by both | 6: C0; H2 (`make-directory` answers made whatever mkdir did), H6 (`GUIX_PROFILE` left set), H8 (`lines-of` drops a last line with no newline); `M4s2-available-by-entry` and `M4s2-order-optional-first`, slice 2's recorded survivors |
| passed by old, so not run on new | 149 of slice 3's and 4's 162: plants of code the loading suites never reach, held by their own suites |

The partition's rows: S1, S2, T1 and the two `optional-` plants fail the merge row on each layout,
"the three suites'…" there and "the four missing suites'…" here; S3 and `decoy-parts-moved`
fail the dealing row alone; S4 fails the dealing row and the written-out pattern; S5 fails the
part's own row. So each of the four changed rows is watched failing.

Where the old layout's catch moved: `-real`'s M4 catches (the optional entry point, the opt-in's
check, `load-extension!`'s first check; 21 plants of slices 2 to 4) are `-extension`'s;
preflight's and the raising probe's (F1, F2b, D2, R4, P2) are `-preflight`'s; the order rows'
(N1, N26, R5, R8) `-combined`'s beside `-decoys`'; each missing-api plant falls to the suite whose
part holds the entry, N3 to `-missing-3`, N20 to `-missing-1`.

### Under the gate

Two plants need the gate's own Valgrind, run with `make test-memory` in each layout's copy:

| Plant | Old | New |
|---|---|---|
| G1, `gated-command` returns the command unchanged, every loading suite | 3 of 3 FAIL, 87 rows: `-real` 32, `-decoys` 29, `-missing` 26 | 9 of 9 FAIL, 87 rows: the missing suites 11, 11, 11 and 10, `-real` 10, `-preflight` 7, `-extension` 7, `-decoys` 11, `-combined` 9 |
| G2, the child of `lacks-sqlite3_sourceid` alone run without it | `-missing` FAIL, 1 row, that one's | `-missing-3` FAIL, 1 row, that one's |

Under G1 each child's row fails on its Valgrind line, on both layouts the same 87, among them
preflight's raising row, which no plant outside the gate fails on either layout.

`test-conventions` and `test-constants`, which import `(library-loading)`'s lists, passed under
`make test-memory` too, 41 s and 11 s.

## make test

From the worktree's root, each lane's library and headers set inside the container, its version
line (`make build`'s) read first:

| Lane | Version | `make test` |
|---|---|---|
| Guix's | 3.53.1 | 87 of 87 |
| `m3-floor` | 3.45.1 | 87 of 87 |
| `m4-current` | 3.54.1 | 87 of 87 |
| `m4-noload` | 3.54.1, `OMIT_LOAD_EXTENSION` | 87 of 87, 51 UNAVAILABLE lines |

87 is `main`'s 81 suites, less `-missing`, plus seven.

## What the records need

- **ADR-0005 (amended):** the three loading suites split into nine of at most 11 children, in M4's
  closing review, `-real` at 258 s and 264 s on CI; the shard placement by the rule, from `main`'s
  latest three runs. The suites and the library cite "ADR-0005, amended".
- **`global-constraints.md`:161-164:** "`test-library-loading` was split in two in M2, at 562 s on
  a slow runner" could add M4's split into nine.
- **`progress.md`:** the close-out.
- **Comments in files outside my list that name the old layout:**
  - `tests/refusal-probe.sps`:4-5, "for tests/test-library-loading-decoys.sps, -real.sps and
    -missing.sps"; :31, "test-library-loading-real compares preflight's remedy line" (now
    `-preflight`); :58, "the three test-library-loading suites" (nine);
  - `tests/check-memory-gate.sh`:144-145, "tests/test-library-loading-decoys.sps, -real.sps and
    -missing.sps close it";
  - `tests/preflight.sps`:13, "tests/test-library-loading-real.sps runs it" (`-real` and
    `-preflight`);
  - `tests/decoy-libsqlite3.c`:2, "for tests/test-library-loading-decoys.sps, -real.sps and
    -missing.sps only";
  - `tests/fixtures/raising/chez-sqlite3/private/native.sls`:4, "for
    tests/test-library-loading-real.sps only" (now `-preflight` only);
  - `tests/test-conventions.sps`:248, "what the pattern of five deals" (four);
  - `tests/test-open-db-config.sps`:74-75, "its rows are test-library-loading-real's" (`-extension`'s);
  - the `Makefile`'s `build` comment, :252, "tests/test-library-loading-real.sps holds the whole
    output" (`-preflight`, and `-real` for the real library): outside the shard lists' comment,
    so left.
- **The findings' m2:** the opt-in's availability refusal is held in-process by
  `test-library-loading-extension`'s decoy row now, not `-real`'s.

## Found on the way

- **Preflight's not-found row can kill its suite, on both layouts.** Its expected value takes
  `(caddr guix-not-found-candidates)` unguarded, so H7 (the list one short) raised in the expected
  expression and `-real` (old) and `-preflight` (new) died, naming no test, as AGENTS.md's SRFI-64
  rule warns. Caught either way (exit 1), and only by a plant of the suite's own expected list;
  left as it was, since the split moves rows unchanged. Reproduce: H7's copies.
- **A gate time here is one sample.** The host's E-cores and the other builders' runs moved old
  `-real` from 195 s (B's run) to 248 s (unpinned) and 205 s (pinned to the P-cores), and
  `-missing-2` from 67 s to 85 s while a plant run shared the host. Read a cost from more than one
  run, here as on CI.
- **Survivors on both layouts, unchanged by the split:** H2, H6 and H8 are faults in the suites'
  own helpers that this container never exercises: mkdir never fails here, the container sets no
  `GUIX_PROFILE`, so unsetting it does nothing, and every text `lines-of` reads ends in a newline.
