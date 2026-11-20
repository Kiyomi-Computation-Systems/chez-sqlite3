# M5 slice 5: the comment sweep's log

The comments of `src/` and of `tests/`' `.sps`, `.sls`, `.sh` and `.c` files, but `tests/fixtures/`,
swept of the build's history before the first release (ADR-0022, decision 9; the M5 plan, §4.7 and
slice 5). The base is `main` at `9728bed`, after slices 1 to 4. 156 files are in scope: 106 `.sps`,
38 `.sls`, 9 `.sh` and 3 `.c`.

## The checker

[research/m5-slice-5/](research/m5-slice-5/) holds three files. `extract-base.sh`, run on the host,
unpacks the base's `src/` and `tests/`. `sweep-check.sh`, run in the container, holds every file
of the tree against it, with `datums.sps` for the Scheme files:

- **a `.sps` or `.sls`** reads, by Chez's `read`, as the same datums, `equal?`; a file that can't be
  read whole is a difference, so two unreadable files never pass as alike;
- **every line a `.sh` changes** is a whole-line comment or blank, before and after;
- **a `.c`** reads the same with its comments stripped by `-fpreprocessed -dD -E -P` and its white
  space folded, so a token changed in a branch no build compiles is seen; and it compiles, without
  `-g`, to the same object code, each copy from a file of the same name, with the four values
  `tests/decoy-libsqlite3.c` requires;
- **a file added, removed, or of another kind** is a problem.

### Its plants, each in a copy of `src/` and `tests/`

| Plant | What it changes | The checker |
|---|---|---|
| control | nothing | ok, 0 of 156 changed |
| comments | a `;;` line of `test-docs`, a `#` line of `check-ci.sh`, and `extension.c`'s first comment grown to two lines | ok, 3 changed |
| datum | `"index.html"` to `"Index.html"` in `site-unit.sps` | datum 44 differs |
| shcode2 | `dir=$1` to `dir=${1:-.}` in `check-ci.sh` | a changed line is no comment |
| ctoken2 | an argument `0` to `1` in `extension.c` | its code, comments stripped, differs; its object code differs |
| added | a new `tests/new-file.sps` | added |
| unread | `(unclosed` appended to `site-unit.sps` | unreadable |
| cA | a comment of the decoy reworded | ok, 1 changed |
| cB | `return 1` to `return 2` in the decoy's `DECOY_MARKER` branch, which no build compiles | its code, comments stripped, differs; the object code alone matched |
| cC | the swept decoy | ok, 1 changed |

The first form compiled a changed C file with no values and compared its object alone: the decoy
didn't compile, and cB would have passed. The sweeper of the group holding the C files found the
first, and the lead the second.

## The sweep

Four sweepers, each in a worktree of its own on disjoint files, each running the checker:

| Group | Files | Changed | Model |
|---|---|---|---|
| G1, `src/` | 30 | 28 | Opus |
| G2, `tests/` from `check-ci.sh` to `test-constants.sps` | 48 | 36 | Sonnet |
| G3, from `test-contention.sps` to `test-load-state.sps` | 42 | 39 | Sonnet |
| G4, from `test-manifest.sps` to `test-verify.sps` | 36 | 32 | Sonnet |

`src/chez-sqlite3.sls` is unchanged, its signature comments with it. The four diffs applied to one
tree with no file in two: 135 files changed, 2,018 lines added and 2,279 removed, every one a
comment line.

## The checks on the combined tree

In the container, on Guix's library:

- `sweep-check.sh`: ok, 135 of 156 files changed, each in its comments alone;
- `make test`: 93 of 93;
- `check-test-fails`: all 18 cases;
- `check-variadic`: all 7 steps;
- `check-dev` and `check-clean`: ok;
- `check-memory-gate`: all 67 cases.

No Mac step: no code changes.

## Round 2: the review's findings

The read-only review found no blocker. It found seven plants the checker passed, and about
fifteen comments false, inverted or broken, with provenance left behind. One fixer, Opus, took
both parts in the sweep's worktree.

### The checker, hardened

`sweep-check.sh` now also runs `lines.awk`, a judge of each changed line on both sides, and
`variants.sps`, which reads the suites' C builds from their own definitions. Its rules now:

- **every file keeps its mode**, as `ls -l` prints it, changed or not;
- **a `.sh`**: a changed line is a whole-line comment or blank, outside every quoted string
  and heredoc, and not line 1; or a `#` line in a heredoc the checker names, by file and
  delimiter, whose body awk reads: only `tests/check-ci.sh`'s `AWKPROGRAM`. No changed line
  follows one that ends in a backslash. The scanner tracks quotes, comments and heredocs, and a
  file it ends inside one of is a problem;
- **a `.c`**: its `-fpreprocessed` output is compared with each line's ends trimmed and blank
  lines dropped, never folded inside a literal; no changed line ends in a backslash or follows
  one; and its object is compared once for each build the suites make of it, by
  `variants.sps` from `tests/extension-build.sls`'s `extension-variants` and
  `tests/library-loading.sls`'s `all-builds`: 6 of `extension.c`, 48 of the decoy, and 1 plain
  build of the oracle, which the suites build no variant of;
- **a `.sps` or `.sls`**: no changed line holds `#!` or `#;`, which `read` passes over.

### Its new plants, each a copy of the base

The old checker passed the first nine. awkcode it refused too, the base's line being no
comment; it holds the allowlist to `#` lines. The new checker refuses each:

| Plant | What it changes | The new checker |
|---|---|---|
| heredoc (a) | a `#;` line above `(capture-command '("true"))` in `check-memory-gate.sh`'s forkclean.sps heredoc | line 501 lies in the heredoc EOF |
| contin (b) | a blank line after `check-ci.sh:1000`'s backslash | line 1001 follows a line ending in a backslash |
| shebang (c) | `guix-env-launcher.sh`'s line 1 made `#!/bin/false` | line 1 changed, on both sides |
| mode (d) | the exec bit dropped from `guix-env-launcher.sh` | its mode was `-rwxrwxr-x`, and is `-rw-rw-r--` |
| cslash (e) | `// ... answers \` above `return registered(...)` in `EXT_NAMED`'s branch | the line ends in a backslash; the object differs, built as named |
| cspace (f) | `"chez_failing  refused"`, two spaces, in `EXT_FAILING`'s branch | its code, comments stripped, differs; the object differs, built as failing |
| rnrs (g) | `check-suites.sps`'s `#!r6rs` made `#!chezscheme` | line 1 holds `#!`, on both sides |
| hashsemi | `#;(exit 1)` added to `check-suites.sps`, a datum of its own dropped | line 2 holds `#;` |
| squote | a `#;` line inside `check-dev.sh`'s single-quoted `forms`, a Scheme program | line 108 lies in a single-quoted string |
| awkcode | an awk statement of `AWKPROGRAM` turned into a `#` line | line 764 lies in the heredoc and is no `#` line |

squote is a hole the review did not name: a `#` line inside a quoted string spanning lines is
data. The heredoc rule's allowlist was also mutated, emptied, and the sweep then fails at
`check-ci.sh:776-777`, so the scanner reaches the lines the allowlist admits. The C rules each
fire alone on a plant: (e) by the backslash and by the named build, (f) by the token compare
and by the failing build.

The earlier plants keep their results: control and comments ok, cA and cC ok over 48 builds;
datum, shcode2, ctoken2, added and unread refused as before. cB now fails twice: its token
compare as before, and its object too, built as marked, where the one plain build matched.

### The comments

Every major and minor of the findings is fixed, and the nits. The groups of entry points have
one set of names: the load's 15, the statement tier's 21, the change counters, autocommit and
interrupt, and the settings and extension calls; the identifiers `m3-five` and `m4-three`, and
strings, keep theirs. Then a script refilled at 78 columns each paragraph, a list item's
continuation lines among them, that held a changed line wider than 80 or ragged, mid-sentence,
keeping each signature line, each table and each break the base made at a sentence's end, and
checking that every file's words stayed the same; and each changed heading rule took its base
counterpart's width, at most 100. The refill showed one period the base lacked, after
`check-memory-gate.sh`'s "(clean)", now added.

### The checks, after round 2

In the container, on Guix's library:

- `sweep-check.sh`: ok, 135 of 156 files changed, each in its comments alone, 55 C builds
  compared;
- `make test`: 93 of 93;
- `check-test-fails`: all 18 cases.

## Round 3: the M4 session's check

The M4 session's read-only check of `f68d602` found no blocker. It found three comment slips, now
fixed:
- `test-open-db-config.sps`: a past result made false by the present tense, now "every start row
  above";
- `test-check-seam.sps`: an "amended" left after an ADR;
- `conditions.sls`: a clause without its verb.

Two nits are fixed too: `require-threaded.sls`'s measurement is chez-libuv's again, and
`test-connection.sps`' expiry is a "would".

**One limit of the checker, which the tree doesn't reach:** inside a double-quoted shell string,
`$( … )` opens a quoting context of its own, and `lines.awk` doesn't model it. So
`x="$(printf '%s' "a # b")`, then a line `# inner`, closes the outer string at the inner `"` and
passes the next line as a comment, though bash reads it as the string's data. The check's plant
passed with "ok", where a plain multi-line double-quoted string beside it was refused.

As an oracle independent of the checker, the check read each of the nine `.sh` files through bash's
own parser with the comments dropped (`__w() { <file> }; declare -f __w`). Eight read the same as
the base, and `check-ci.sh` differs only in the two `#` lines of its quoted `AWKPROGRAM` heredoc,
which are awk's comments and which the allowlist admits.

After round 3, the checker reports "ok, 136 of 156 files changed, each in its comments alone
(55 C builds compared)", and `make test` passes 93 of 93.

