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


## The closing review's sweep of the build files

M5's closing review read `c3df9de` and found the release archive's build files carrying the
history `src/` and `tests/` were swept of: milestones, slices, plan sections, dates, "amended" and
"decision N" after an ADR, and pointers into the `.plans/` and `AGENTS.md` the archive leaves out.
The maintainer's answer: sweep the Makefile, `scripts/` and `packaging/` in the fix PR, by slice
5's rules. `.gitignore` and `.gitattributes` joined them. The base is `main` at `c3df9de`; one
builder, Opus, in the fix's worktree, which also took the review's `src/` comment findings and
its page findings.

### The checker, extended

`extract-base.sh` now unpacks the base's Makefile, `scripts/`, `packaging/`, `.gitignore` and
`.gitattributes` beside `src/` and `tests/`, still on the host, and `sweep-check.sh` lists them
too: 174 files, where it read 156. Its new rules, each on both sides of every changed line, in
`lines.awk`:

- **the Makefile** (`make`): a changed line is a comment with `#` at column 0, or empty: never a
  recipe line, which a tab begins and the shell reads, nor one a space begins; it lies in no
  `define ... endef` block, whose lines are a variable's value; it ends in no backslash, which
  carries a make comment on to the next line; and it follows no line that ends in one. The
  scanner counts `define` and `endef`, and a file it ends inside a block of is a problem;
- **every file of `scripts/`**: a `.sh`, or a file whose line 1 names `sh`, `bash` or `dash` on
  both sides, takes the shell rule; any other changed file there is a problem;
- **`packaging/*.txt`, `.gitignore` and `.gitattributes`** (`hash`): a changed line is a comment
  with `#` at column 0, or empty. CI's install step drops only `^#` and `^$` lines, so an
  indented `#` line is a package, and git's ignore rules read one as a pattern;
- **`packaging/*.sexp`** (`semi`): a changed line is a `;` comment or blank, and the file reads,
  by `datums.sps`, as the same datums;
- **modes**, for all of them, as for `src/` and `tests/`.

### Its plants, each a copy of the base

`build/fix1/plants/run.sh` makes each plant in a fresh copy of the base under
`build/fix1/plants/t/` and runs the checker from the copy's root. The old checker passed every
build-file plant: it read none of those files, and answered "ok, 0 of 156" on mkcode and gaout.
The new checker:

| Plant | What it changes | The new checker |
|---|---|---|
| bcomments | a comment line of the Makefile, `scripts/guix-env`, `scripts/ci/floor.sh`, `debian-prereqs.txt`, `floors.sexp`, `.gitignore` and `.gitattributes` | ok, 7 of 174 changed |
| mkcode | `TEST_TIMEOUT ?= 300` to `301` | line 37 is no comment at column 0, on both sides |
| mkrecipe | a tab-led `# ...` line after `deps`' last recipe line | line 255 is a recipe line |
| mkspace | the Makefile's line 2, `#`, made ` # an indented line` | line 2 is no comment at column 0 |
| mkcontin | a `#` line after `MEMORY_SUITES_1 := \` | line 79 follows a line ending in a backslash |
| mkendslash | ` \` added to the comment above `CHEZ ?=`, which would swallow it | line 9 ends in a backslash |
| mkdefine | a `#` line inside a `define` block, both sides given the block | line 927 lies in a define block |
| mkopen | a comment reworded, both sides given a `define` with no `endef` | each side's scanner ends inside a define block |
| shnoext | `set -eu` to `set -u` in `scripts/guix-env`, which has no suffix | line 15 is no comment, on both sides |
| shkind | `scripts/require-tools`' line 1 made `#!/usr/bin/env python3` | its line 1 names no shell on both sides |
| shciheredoc | a `# note` line inside `check-sqlite.sh`'s C heredoc | line 332 lies in the heredoc EOF |
| txtcode | a package line, `git`, added to `debian-prereqs.txt` | line 30 is no comment at column 0 |
| txtindent | `debian-site-prereqs.txt`'s line 1 indented by a space | line 1 is no comment at column 0 |
| gicode | `.gitignore`'s `/build/` made `/build` | line 7 is no comment at column 0, on both sides |
| gaout | `.gitattributes`' `/AGENTS.md` rule commented out | BASE's line 5 is no comment at column 0 |
| sexpdatum | the SQLite floor's `3.45.1` made `3.45.2` | datum 0 differs; line 4 is no `;` comment, on both sides |
| sexphash | `#;(chez "9.5.8")` added to `floors.sexp`, which `read` passes over | line 3 is no `;` comment; the datums alone matched |
| modeci | the exec bit dropped from `scripts/ci/floor.sh` | its mode was `-rwxrwxr-x`, and is `-rw-rw-r--` |
| modemk | the exec bit added to the Makefile | its mode was `-rw-rw-r--`, and is `-rwxrwxr-x` |
| addedci | a new `scripts/ci/new.sh` | added |
| removedpkg | `packaging/debian-site-prereqs.txt` removed | removed |

The earlier plants were rebuilt on `c3df9de`, the slice's own scripts being gone with its
worktree, and keep their results: control ok, 0 of 174; comments ok, 3 changed, 6 C builds; cA
and cC ok over 48 builds; datum (datum 44), shcode2, ctoken2, added, unread, cB (its tokens, and
its object built as marked), heredoc, contin, shebang, mode, cslash (the backslash, and built as
named), cspace (the tokens, and built as failing), rnrs, hashsemi, squote and awkcode (BASE's line
170 lies in the heredoc and is no `#` line) each refused as before. The allowlist plant, an
`AWKPROGRAM` `#` line reworded, passes, and with the allowlist emptied in a copy of the checker
fails at line 168 on both sides.

### The files swept

Every comment of the eighteen build files read. Ten changed, each in its comments alone:

- the Makefile: the memory gate's timings and their history, the shards' balance and its runs,
  "amended" after an ADR eleven times, "decision 4", "the M4 plan, section 4.2", chez-curl's
  measurements, given as the behaviour they showed, `--trace-children`'s reason, chez-curl as
  the site's precedent, and four paragraphs reflowed;
- `scripts/ci/build-chez.sh`, `build-sqlite.sh`, `check-sqlite.sh` and `report-sqlite.sh`: "M4's
  closing review", "M1", "decision 3", "amended", "(AGENTS.md)", "harness plan, section 5", and
  `current_version`'s date and plan section;
- `scripts/fetch-akku-lock`: a measurement put in the present tense;
- `packaging/debian-prereqs.txt` and `debian-site-prereqs.txt`: the harness plan, "from M1",
  chez-curl's measurement and "decision 4";
- `.gitignore`: the ledger's path and `AGENTS.md`, and `/build/`'s comment, which named `make
  deps` alone, now what the Makefile writes there;
- `.gitattributes`: says what its rules do, naming nothing the archive drops.

`scripts/ci/check-action-pins.sh`, `check-chez.sh`, `floor.sh`, `scripts/guix-env`,
`guix-env-enter`, `guix-env-selftest`, `require-tools` and `packaging/floors.sexp` needed nothing.

The same tree holds the review's `src/` findings, 14 files, comments alone, and its page
findings, `docs/quickstart.md` and `docs/reference.md`, which the checker doesn't read.

As in round 3, bash's own parser, the comments dropped, reads each of the five changed shell
scripts as the base does, and reads the shnoext plant's `scripts/guix-env` as different.

### The checks, on the swept tree

In the container, on Guix's library:

- `sweep-check.sh`: ok, 24 of 174 files changed, each in its comments alone;
- `make test`: 93 of 93. Its first run failed `test-manifest`, whose clone-line rule refuses any
  line holding "git clone": the quick start's new "The tests run from a git clone" was one. It
  now says "from a clone";
- `check-site`: all green;
- `check-floors`: every file holds the floors file;
- `check-test-fails`: all 18 cases.
