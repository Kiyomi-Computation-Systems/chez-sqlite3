# M1 owed fixes mutation log: counters' irritants, and the whitespace refusal

Evidence that two owed fixes fail through the property each claims to hold. Format of
[the slice 4 log](m1-slice-4-mutation-log.md).

The fixes:
- **A.** `(chez-sqlite3 private counters)` refuses with irritants that begin with a rule symbol,
  `not-a-kind` or `double-free`, then the kind, as `register-exit-check!` does. `tests/test-counters.sps`
  asserts who and irritants through `refused`, never the message text. The `raised` helper and the two
  message strings are gone.
- **B.** `make test-memory` refuses, exit 2, when `$(CURDIR)` holds whitespace: the gate's child prefix
  (`CHEZ_SQLITE3_GATE_CHILD`) is cut at whitespace by `gated-command` and `gate-log-dir`, so its absolute
  `--log-file` path would split. `tests/check-memory-gate.sh` has `g whitespace`, a space and a tab, each
  in a real directory. The two readers are unchanged.

Each mutation was applied to the working tree, checked with `git diff`, run, and reverted from a saved
copy. The counts are read from the suites' own output (`# of expected passes`, `# of unexpected
failures`) and the gate's own `ok` and `FAILED` lines.

## Measured first (Guix container: Chez 10.4.0)

- **`deps` and the other prerequisites do not fail in a path holding a space.** In a copy at
  `build/probe sp/tree`, `make test-memory MEMORY_SUITES=tests/test-counters.sps` ran `deps`,
  `scripts/require-tools` and the suite, and passed. So the refusal in the recipe fires first, after
  `require-tools` and the `MEMORY_TIMEOUT` check, and needs no earlier place.
- **CURDIR is the physical path.** From a symlink named `link sp` to `tree` (inside a directory holding a
  space), CURDIR was `.../probe sp/tree`. From a symlink named `link sp2` to a real directory with no
  space, CURDIR was `.../probe-real`: no space. A symlink whose name holds a space never puts one in
  CURDIR, so `g whitespace` copies the tree into real directories.
- **A path holding whitespace passes `test-memory` today.** The same copy ran a suite to a pass. The
  split bites only a child run through `gated-command`, so nothing refused it before this.

## Item A: test-counters

Run: `$CHEZ --libdirs src:tests:build/scheme-libs --program tests/test-counters.sps`. Unmutated: 17 passed,
0 failed.

| # | Mutation | Passed | Failed | Rows that failed |
|---|---|---|---|---|
| A1 | both message strings reworded | 17 | 0 | none: no row reads the text |
| A2a | `'not-a-kind` to `'not-a-kin` | 15 | 2 | the two `not-a-kind` rows: "refuse a symbol that is no kind", "leave every count where it stood" |
| A2b | `'double-free` to `'double-fre` | 13 | 4 | "a count-down below zero" and the three per-kind "at zero raises" rows |
| A3 | the two rule symbols swapped | 11 | 6 | all six rows of A2a and A2b |
| A4a | `'not-a-kind kind` to `'not-a-kind` | 15 | 2 | the same two as A2a |
| A4b | `'double-free kind` to `'double-free` | 13 | 4 | the same four as A2b |

## Item B: the whitespace refusal

Run: `make check-memory-gate`. Unmutated: 56 `ok`, 0 `FAILED`.

| # | Mutation | ok | FAILED | Which |
|---|---|---|---|---|
| B1 | the refusal removed | 54 | 2 | both `g whitespace` rows: the run's lines were a pass of the stand-in's suite ("Valgrind wrote no log"), not the message, and a suite ran |
| B2 | message "holds whitespace," to "holds blanks," | 54 | 2 | both `g whitespace` rows: wanted and got differ in that word |
| B3 | the refusal fires for every path (`*)`) | 9 | 47 | every case that runs `test-memory` past the refusal |
| B4 | tests for a space only (`*" "*)`) | 55 | 1 | the tab row of `g whitespace`; the space row passes |

B4's first try, `* *`, was a shell syntax error and failed 49 rows; it was not the mutation meant, and
was redone as `*" "*`. The tab row exists, so no row had to be added.
