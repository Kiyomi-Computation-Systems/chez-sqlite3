# Progress ledger

Where chez-sqlite3 stands. Read it with [global-constraints.md](global-constraints.md) before
starting slice work. When a slice merges, update **Now** and add a close-out under **Close-outs**,
newest first.

## Now

- **M0 slice 0, the records,** merged as PR #1. ADR-0001 to ADR-0009 are all accepted.
- **M0 slice 1, the container,** merged as PR #2.
- **M0 slice 2, the test harness,** is built on `m0-slice-2-test-harness`, waiting for its review:
  - **Built:** chez-srfi pinned three ways and checked by `check-pins`; the suite loop,
    `check-suites`, `check-test-fails`, `clean` and `check-clean`; the verdict and the counters;
    `require-threaded`; the floors, `check-floors` and README.org's Requirements;
    `test-manifest`; and the CHANGELOG.
  - **Brief D1 settled:** a threaded Chez is required (ADR-0001's amendment).
  - **Each test helper comes with its first consumer** (harness plan, amended).
  - **Three Sonnet agents** built the floors, `test-manifest`, and the verdict and counters
    suites, in parallel. Their results were reproduced here.
  - **Watched failing:** see [the log](test-harness-mutation-log.md). One agent mutation
    survived: an equivalent one.
- **Open:** brief D1 to D7. D1 (threaded Chez) and D7 (the Mac's SQLite) are due in M1.

## Close-outs

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
