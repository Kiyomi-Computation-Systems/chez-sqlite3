# The memory job's shards: measured input for M3 slice 6's part C

Prepared by the M2 session, 2026-11-16, from six CI runs' `memory` job logs and step timings. Read-only: no file in the tree was changed. The design is part C's (chez-curl ADR-0014's, the maintainer's "Shard in slice 6"). This is its input: per-suite times, a projection, and a split.

## The runs

| Run | Head | Job | `test-check-ci` | Runner factor | Suites | Sum of suites | `check-memory-gate` step | Setup |
|---|---|---|---|---|---|---|---|---|
| 43957085196 | `b4a403a` | 40.5 min | 85 s | 1.00 | 68 | 2054 s | 293 s | 82 s |
| 43972607735 | `36a8901` | 28.7 min | 95 s | 0.96 | 58 | 1390 s | 295 s | 33 s |
| 43947660260 | `5c295c1` | 35.1 min | 124 s | 1.19 | 58 | 1698 s | 363 s | 43 s |
| 43941964004 | `052c130` | 31.4 min | 85 s | 1.00 | 58 | 1521 s | 292 s | 67 s |
| 43966422723 | `b940f55` | 34.0 min | 121 s | 1.27 | 54 | 1644 s | 369 s | 26 s |
| 43961994023 | `2c4c889` | 17.0 min | 64 s | 0.67 | 44 | 768 s | 220 s | 30 s |

- **The runner factor** is the median, over the suites both runs share (10 s or more, `test-transaction-interrupt` left out), of this run's time over run 43957085196's (`b4a403a`, slice 5, the fast class).
- `test-check-ci`'s own ratio overstates the factor: 1.42 and 1.46 where the median suite reads 1.27 and 1.19. Don't normalise by it alone.
- Setup is the job's time outside the two make steps: package install, the Chez cache, the Chez check.

## Per suite, normalised to the fast class

Each suite's time in each run is divided by that run's factor, then the median taken. "Max seen" is the largest raw time in any run. Slice 6's four suites are from the M3 session's local gate times, divided by 0.775 (local runs at 0.75 to 0.8 of CI's fast class). Their "max" is set at three times nominal, since every one uses threads and `test-transaction-interrupt` swung from 20 to 149 s on CI.

| Suite | Normalised | Max seen | Runs | Proposed shard |
|---|---|---|---|---|
| `test-library-loading-decoys.sps` | 177 s | 225 s | 6 | 2 |
| `test-library-loading-missing.sps` | 160 s | 204 s | 6 | 1 |
| `test-conveniences-pending-script-odd.sps` | 148 s | 148 s | 1 | 2 |
| `test-library-loading-real.sps` | 146 s | 186 s | 6 | 1 |
| `test-conveniences-pending-script-even.sps` | 145 s | 145 s | 1 | 2 |
| `test-check-ci.sps` | 96 s | 124 s | 6 | 1 |
| `test-transaction-interrupt.sps` | 82 s | 149 s | 4 | 1 |
| `test-conveniences-pending-fold.sps` | 72 s | 72 s | 1 | 1 |
| `test-transaction-engine.sps` | 64 s | 71 s | 4 | 2 |
| `test-chez-sqlite3-testing.sps` | 52 s | 67 s | 6 | 1 |
| `test-conveniences-pending-query.sps` | 45 s | 45 s | 1 | 2 |
| `test-open-interleave.sps` | 40 s | 40 s | 1 | 1 |
| `test-conventions.sps` | 36 s | 46 s | 6 | 2 |
| `test-docs.sps` | 36 s | 44 s | 6 | 1 |
| `test-conveniences-resumed.sps` | 28 s | 35 s | 5 | 2 |
| `test-statement-block.sps` | 27 s | 31 s | 6 | 2 |
| `test-open-engines.sps` | 25 s | 25 s | 1 | 1 |
| `test-check-floors.sps` | 24 s | 30 s | 6 | 1 |
| `test-statement-tail.sps` | 24 s | 31 s | 6 | 2 |
| `test-ci-sqlite.sps` | 22 s | 28 s | 6 | 1 |
| `test-statement.sps` | 22 s | 27 s | 6 | 2 |
| `test-native.sps` | 20 s | 25 s | 6 | 1 |
| `test-transaction.sps` | 20 s | 24 s | 4 | 2 |
| `test-contention.sps` (part B, local about 16 s) | 20 s | 60 s | local | 2 |
| `test-interrupt-reach.sps` (part A, local 15 s) | 19 s | 57 s | local | 2 |
| `test-conveniences-pending-query-row.sps` | 18 s | 18 s | 1 | 1 |
| `test-open-locks.sps` | 18 s | 18 s | 1 | 2 |
| `test-conveniences-pending-execute.sps` | 17 s | 17 s | 1 | 1 |
| `test-connection.sps` | 15 s | 19 s | 6 | 2 |
| `test-conveniences-who.sps` | 15 s | 19 s | 5 | 2 |
| `test-open-settings.sps` | 15 s | 15 s | 1 | 1 |
| `test-statement-values.sps` | 15 s | 20 s | 6 | 2 |
| `test-check-seam.sps` | 14 s | 18 s | 6 | 1 |
| `test-conveniences-engines.sps` | 14 s | 18 s | 5 | 2 |
| `test-statement-who.sps` | 14 s | 18 s | 5 | 1 |
| `test-blocks.sps` | 13 s | 16 s | 6 | 2 |
| `test-change-counters.sps` | 13 s | 17 s | 5 | 1 |
| `test-connection-cache.sps` | 13 s | 16 s | 5 | 2 |
| `test-conveniences-counters.sps` | 13 s | 16 s | 5 | 1 |
| `test-conveniences.sps` | 13 s | 16 s | 5 | 2 |
| `test-statement-values-nomem.sps` | 13 s | 17 s | 6 | 1 |
| `test-statement-values-sections.sps` | 13 s | 16 s | 6 | 2 |
| `test-transaction-nomem.sps` | 13 s | 17 s | 4 | 1 |
| `test-utf8.sps` | 13 s | 16 s | 6 | 2 |
| `test-interrupt-database.sps` (part A, local 10 s) | 13 s | 39 s | local | 1 |
| `test-interrupt-close.sps` (part A, local 10 s) | 13 s | 39 s | local | 2 |
| `test-conveniences-reentry.sps` | 12 s | 15 s | 5 | 1 |
| `test-execute-script.sps` | 12 s | 16 s | 5 | 1 |
| `test-public.sps` | 11 s | 14 s | 6 | 2 |
| `test-reference.sps` | 11 s | 14 s | 6 | 2 |
| `test-settings.sps` | 11 s | 15 s | 6 | 1 |
| `test-statement-cache.sps` | 11 s | 14 s | 6 | 2 |
| `test-statement-sections.sps` | 11 s | 14 s | 6 | 1 |
| `test-conditions.sps` | 10 s | 13 s | 6 | 2 |
| `test-constants.sps` | 10 s | 12 s | 6 | 1 |
| `test-check-nothreads.sps` | 9 s | 11 s | 6 | 2 |
| `test-counters.sps` | 9 s | 11 s | 6 | 1 |
| `test-discovery.sps` | 9 s | 12 s | 6 | 2 |
| `test-require-threaded.sps` | 9 s | 12 s | 6 | 1 |
| `test-transaction-plan.sps` | 9 s | 11 s | 6 | 2 |
| `test-verify.sps` | 9 s | 11 s | 6 | 1 |
| `test-interrupt.sps` | 8 s | 10 s | 6 | 2 |
| `test-load-state.sps` | 8 s | 10 s | 6 | 1 |
| `test-manifest.sps` | 8 s | 10 s | 6 | 2 |
| `test-never-loads.sps` | 8 s | 10 s | 6 | 1 |
| `test-open-options.sps` | 8 s | 11 s | 6 | 2 |
| `test-script.sps` | 8 s | 10 s | 6 | 1 |
| `test-sql-tail.sps` | 8 s | 10 s | 6 | 2 |
| `test-values.sps` | 8 s | 12 s | 6 | 1 |
| `test-libsqlite3-info.sps` | 7 s | 9 s | 6 | 2 |
| `test-memory-check.sps` | 7 s | 9 s | 6 | 1 |
| `test-statement-state.sps` | 7 s | 9 s | 6 | 2 |

## The projection

- **The suites in all:** about 2086 s on the fast class, 72 suites with slice 6's four (68 at `b4a403a`).
- **As one job,** with setup 30 to 80 s and `check-memory-gate` 290 s:
  - **Fast class:** about 41 min, near run 43957085196's 40m31s plus slice 6's suites.
  - **Slow class:** about 52 min, with the suites and the gate at the slowest factor seen, 1.27. That is past ADR-0005's 45 minutes and near the job's 60-minute `timeout-minutes`.
- **As two shards,** each running setup, then `check-memory-gate`, then its own suites (the chez-curl design):
  - **Shard 1:** 1040 s of suites. About 23 min on the fast class, and about 29 min at factor 1.27. With every suite at its worst seen, about 30 min.
  - **Shard 2:** 1046 s of suites, about 23, 29 and 29 min the same ways.
- **The duplicated gate step** costs each shard about 5 minutes: 290 s on the fast class and 370 s on the slow. Running it in only one shard would make that the shorter one, but `check-ci` holds today that the job running `test-memory` runs `check-memory-gate` first. That's part C's to weigh, not a recommendation.
- **The flake's exposure doubles.** `check-memory-gate`'s case b once missed its plant, in slice 2's run, and was never reproduced. With the gate in both shards, it runs twice a run.

## The split

Balanced greedily by the normalised times. The threaded suites are dealt first, alternating, so the noisy ones spread (`test-transaction-interrupt`, and slice 6's interrupt and contention suites). Then the rest, largest first, each to the lighter shard. Where the big siblings land:
- `-missing` and `-real` go to shard 1, and `-decoys` to shard 2;
- the script's two pending halves both go to shard 2, since together they balance shard 1's two library-loading suites.

Slice 5's suites were measured in one run each (`b4a403a`). Slice 6's four are local estimates, and its final suite list may hold more.

**Shard 1** (35 suites, 1040 s nominal):

```
MEMORY_SUITES_1 = \
  tests/test-change-counters.sps \
  tests/test-check-ci.sps \
  tests/test-check-floors.sps \
  tests/test-check-seam.sps \
  tests/test-chez-sqlite3-testing.sps \
  tests/test-ci-sqlite.sps \
  tests/test-constants.sps \
  tests/test-conveniences-counters.sps \
  tests/test-conveniences-pending-execute.sps \
  tests/test-conveniences-pending-fold.sps \
  tests/test-conveniences-pending-query-row.sps \
  tests/test-conveniences-reentry.sps \
  tests/test-counters.sps \
  tests/test-docs.sps \
  tests/test-execute-script.sps \
  tests/test-interrupt-database.sps \
  tests/test-library-loading-missing.sps \
  tests/test-library-loading-real.sps \
  tests/test-load-state.sps \
  tests/test-memory-check.sps \
  tests/test-native.sps \
  tests/test-never-loads.sps \
  tests/test-open-engines.sps \
  tests/test-open-interleave.sps \
  tests/test-open-settings.sps \
  tests/test-require-threaded.sps \
  tests/test-script.sps \
  tests/test-settings.sps \
  tests/test-statement-sections.sps \
  tests/test-statement-values-nomem.sps \
  tests/test-statement-who.sps \
  tests/test-transaction-interrupt.sps \
  tests/test-transaction-nomem.sps \
  tests/test-values.sps \
  tests/test-verify.sps
```

**Shard 2** (37 suites, 1046 s nominal):

```
MEMORY_SUITES_2 = \
  tests/test-blocks.sps \
  tests/test-check-nothreads.sps \
  tests/test-conditions.sps \
  tests/test-connection-cache.sps \
  tests/test-connection.sps \
  tests/test-contention.sps \
  tests/test-conveniences-engines.sps \
  tests/test-conveniences-pending-query.sps \
  tests/test-conveniences-pending-script-even.sps \
  tests/test-conveniences-pending-script-odd.sps \
  tests/test-conveniences-resumed.sps \
  tests/test-conveniences-who.sps \
  tests/test-conveniences.sps \
  tests/test-conventions.sps \
  tests/test-discovery.sps \
  tests/test-interrupt-close.sps \
  tests/test-interrupt-reach.sps \
  tests/test-interrupt.sps \
  tests/test-library-loading-decoys.sps \
  tests/test-libsqlite3-info.sps \
  tests/test-manifest.sps \
  tests/test-open-locks.sps \
  tests/test-open-options.sps \
  tests/test-public.sps \
  tests/test-reference.sps \
  tests/test-sql-tail.sps \
  tests/test-statement-block.sps \
  tests/test-statement-cache.sps \
  tests/test-statement-state.sps \
  tests/test-statement-tail.sps \
  tests/test-statement-values-sections.sps \
  tests/test-statement-values.sps \
  tests/test-statement.sps \
  tests/test-transaction-engine.sps \
  tests/test-transaction-plan.sps \
  tests/test-transaction.sps \
  tests/test-utf8.sps
```

Any suite added later should go to the lighter shard by its first CI time. If a record cites this file, copy it into the slice's research first: it lives in a scratch directory. Every suite's time is read from the runs above; read them again on slice 6's own CI before trusting the balance.

