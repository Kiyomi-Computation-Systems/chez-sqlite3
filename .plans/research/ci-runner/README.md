# Research: what CI's runner gives, on the workflow's first run

Date: 2026-11-13 (M0 slice 4), GitHub Actions run 43540404918, on PR #5, the workflow's first.
It settles the harness plan's "Ubuntu 24.04's is 3.45.1; slice 4 verifies this on the runner".

## The runner

From the `main` job's "Report the versions this run uses" step:

```
10.4.0
cc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0
valgrind-3.22.0
image: ubuntu24 20261111.127.1
kernel: 7.0.0-1014-aws
```

The first line is the Chez that `scripts/ci/build-chez.sh` built at the floor. Its own check
printed, in the `nothreads` job, `Chez 10.4.0 built --nothreads into …/chez-nothreads: (10 4 0
no)`.

## The runner's SQLite

From `scripts/ci/report-sqlite.sh`, read through the FFI. The whole report is in
[report-sqlite.txt](report-sqlite.txt):

```
libsqlite3: /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 -> /usr/lib/x86_64-linux-gnu/libsqlite3.so.0.8.6
version: 3.45.1 (3045001)
sqlite3.h: 3.45.1 (3045001)
floor: 3.45.1
```

and 58 compile options.

## The jobs

All three passed on the first run, each building Chez from a cold cache:

| Job | Time | What it showed |
|---|---|---|
| `main` | 4 min 23 s | 9 `uses` lines pinned; `check-suites`, `check-pins` and `check-floors` passed; `make test` ran 6, passed 6; `check-test-fails` failed, as it must, in all 10 cases; `check-clean` passed |
| `memory` | 9 min 17 s | `check-memory-gate` in all 36 cases, about 2 min; then `test-memory` ran 6, passed 6, about 1 min 20 s |
| `nothreads` | 3 min 55 s | `(chez-sqlite3 private counters)` and `(chez-sqlite3 private require-threaded)` each refused by name |

The `nothreads` job is the one place the refusal meets a real non-threaded Chez. Each import
raised `require-threaded`'s own refusal, not chez-libuv's bare "missing import", so the import
order holds on a real `--nothreads` build.

## What it settles

- **The runner's SQLite is the floor itself, 3.45.1, and its header matches it.** The `main` lane
  tests the floor as Ubuntu builds it. M1's `floor` lane tests it as we build it, with known flags
  (harness plan, section 5).
- **Ubuntu's build differs from Guix's,** read the same way in the container (M0 slice 1's
  [research/guix-pin/](../guix-pin/)). Only Ubuntu's:
  - `ENABLE_LOAD_EXTENSION`, `ENABLE_RTREE`, `ENABLE_SESSION`, `ENABLE_PREUPDATE_HOOK`,
    `ENABLE_STMTVTAB`, `ENABLE_UPDATE_DELETE_LIMIT`, `ENABLE_FTS3_PARENTHESIS`,
    `ENABLE_FTS3_TOKENIZER`;
  - `USE_URI`, `SOUNDEX`, `LIKE_DOESNT_MATCH_BLOBS` and `HAVE_ISNAN`;
  - `MAX_VARIABLE_NUMBER=250000`, `MAX_FUNCTION_ARG=127`, `MAX_DEFAULT_PAGE_SIZE=32768` and
    `MAX_SCHEMA_RETRY=25`.

  Only Guix's: `ENABLE_PERCENTILE`, `MAX_VARIABLE_NUMBER=32766`, `MAX_FUNCTION_ARG=1000` and
  `MAX_DEFAULT_PAGE_SIZE=8192`. Both have `ENABLE_FTS5`, and neither has `OMIT_LOAD_EXTENSION`
  or `OMIT_JSON`; JSON is built in unless omitted, since 3.38. Only the container's library has
  run JSON here (M0 slice 1); this run executed no SQL.

  So a test that depends on a compile option holds in one lane and not the other: `USE_URI`
  decides whether a `file:` name is a URI, and the variable limit decides how many parameters a
  statement may bind. M1 reads options through the FFI, never assumes them.

## The second run

Run 43544889798, after the review's fixes, rebuilt Chez cold: the cache keys now hash every script
that reads, builds or checks it. `memory` and `nothreads` passed, and `check-chez.sh` passed on
each Chez, restored or built. `main`'s checks and suites passed, `check-ci` and the new suite
among them, and then its new step, the launcher's host-side tests, failed: 79 passed, 4 failed,
each of T11b's "says why". T11b ran `make test` under `env -i`, which dropped `CHEZ`, and the
runner has no `scheme` on `PATH` (`.plans/traps.md`). T11b now passes `CHEZ` through.

## The third run

Run 43545759140, with T11b fixed, restored every Chez from the cache the second run saved, and
passed in all three jobs. Each restored Chez was asked again before anything ran on it:
`check-chez.sh` answered `(10 4 0 yes)` in `main` and `memory`, and `(10 4 0 no)` in `nothreads`.
The launcher's tests passed 83 of 83. With warm caches, `main` and `nothreads` took about a minute
each, and `memory` 3 min 44 s.
