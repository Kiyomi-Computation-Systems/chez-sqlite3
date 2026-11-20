# M4's Mac run after the closing review

M4's closing review (PR #48) added rows no Mac has run. Its ledger's Open list owes this run:

- **The low passes' timer.** 29 low rows read the engine's timer through Chez's internal
  `$tc-field`, which the maintainer kept for the tests alone ("Keep it, tests only", ADR-0016,
  amended in M4's closing review). CI and Guix run Chez 10.4.0; the Mac runs 10.4.1.
- **The forcing VFS.** `test-open-engines` and `test-open-db-config-engines` register a copy of
  SQLite's default VFS, since Apple's library refuses `sqlite3_auto_extension`. No run has had
  Apple's or Homebrew's library take it.
- **The nine loading suites,** split from one in the review, which hold the Mac's dyld rows.
- **The owner compared inside the section,** in `call-with-open-handle` and `close-database!`
  (ADR-0010, amended in M4's closing review), on Apple's `THREADSAFE=2` build.

It ran on 2026-11-19: both libraries passed 92 of 92 on Chez 10.4.1, the probes printed what
Linux's did, and every figure below held. The results are in [README.md](README.md), "The
closing review's Mac run", and the files in [out/closing-review/](out/closing-review/).

These are its commands, for zsh, in your chez-sqlite3 clone, on `main`, which has PR #48. They
carry no comments, and they write only under `build/m4cr-mac/`, which git ignores. Each
`make test` runs every suite: one took 164 s on the 18-core Linux machine these steps were
written on.

## 1. Get `main`, with the closing review in it

Start from a clean tree: `git status --short` should print nothing that git tracks. The
`git merge-base` command should print `has-48`: the review's merge, `79fa1ac`, is in your tree.

```
git status --short
git switch main
git pull --ff-only
git merge-base --is-ancestor 79fa1ac HEAD && echo has-48
mkdir -p build/m4cr-mac
```

## 2. Chez's timer, by itself

Each probe takes about a second and needs no SQLite.

```
CHEZ=$(command -v chez || command -v scheme)
$CHEZ --version 2>&1 | tee build/m4cr-mac/chez-version.txt
$CHEZ --program .plans/research/m4-closing-review/sweeps/chunk-probe.sps 2>&1 | tee build/m4cr-mac/chunk-probe.txt
$CHEZ --script .plans/research/m4-closing-review/sweeps/timer-probe.sps 2>&1 | tee build/m4cr-mac/timer-probe.txt
$CHEZ --script .plans/research/m4-closing-review/sweeps/exit-probe.sps 2>&1 | tee build/m4cr-mac/exit-probe.txt
```

## 3. Apple's library

```
unset CHEZ_SQLITE3_LIBRARY C_INCLUDE_PATH
make test 2>&1 | tee build/m4cr-mac/apple-test.txt
```

## 4. Homebrew's library

```
export CHEZ_SQLITE3_LIBRARY=/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib
export C_INCLUDE_PATH=/opt/homebrew/opt/sqlite/include
make test 2>&1 | tee build/m4cr-mac/brew-test.txt
unset CHEZ_SQLITE3_LIBRARY C_INCLUDE_PATH
```

## 5. Send back

```
tar czf m4cr-mac.tgz build/m4cr-mac/*.txt
```

Send `m4cr-mac.tgz`. A step that fails is a result too: carry on to the next one.

## What we will read

- **The probes,** against what Guix's Chez 10.4.0 printed:
  - `chunk-probe`: 32000 bytes and more meet a collect request at the section's exit in 100 of
    100. Each suite's forcing allocates 32 KiB on that. If fewer do on the Mac, the low rows'
    check that every forced section met its request fails by name;
  - `timer-probe`: every `EXIT` fuel's last reading is `#f`, and every later fuel's a number. If
    `$tc-field` can't be reached on 10.4.1, the probe raises at once, and every low row fails
    `taken-at-a-forced-exit` by name in steps 3 and 4;
  - `exit-probe`: at a trip of 256 bytes, some fuels expire at a section's exit, and at 2^27 and
    at 256 KiB none. The fuels themselves may move on arm64; the shape may not.
- **With both:** each `make test` ends with `test: ran 92, passed 92`, as on Linux: the Makefile
  has no branch for the Mac. A passing row prints no name, but each sweep prints its tally,
  `forced sections N, unmet U; a first slice's forced sections K, remainders at the exit of
  (…)`. A low-trip tally must show `unmet 0` and a list that isn't empty. On Linux, 32 did, in
  14 suites: `test-conveniences-resumed` 9, `test-open-db-config-engines` and
  `test-open-interleave` 4 each, `test-transaction-engine` 3, `test-open-engines` and
  `test-conveniences-pending-query` 2 each, and one each in seven other pending suites and
  `test-conveniences-reentry`.
- **With Apple's library:**
  - Apple's refusal of `sqlite3_auto_extension` turns the tell's rows UNAVAILABLE, naming the
    refusal, the pending suites' low rows among them. On Linux, a stand-in for the refusal,
    [tell-refused.py](tell-refused.py), printed 58 such lines over 14 suites and failed none
    ([out/closing-review/tell-refused-linux.txt](out/closing-review/tell-refused-linux.txt)).
    A suite whose count differs reads the tell another way on Apple's library, and we will
    say why;
  - so 19 low-trip tallies should remain with exits: those of `test-open-engines` and
    `test-open-db-config-engines`, forced through the VFS, and of `test-conveniences-resumed`,
    `test-conveniences-reentry` and `test-transaction-engine`, forced through the trace and
    an authorizer set on the connection. `test-open-interleave` keeps two low tallies, their
    forcing UNAVAILABLE, so they read `forced sections 0` and an empty list, as the stand-in's
    did;
  - the VFS rows: registered, then removed and freed, in both open suites;
  - the nine `test-library-loading-*` suites, and `test-connection`'s owner rows.
- **With Homebrew's library,** which takes the tell: the 32 low-trip tallies, as on Linux, and
  no line naming a refused `sqlite3_auto_extension`.
