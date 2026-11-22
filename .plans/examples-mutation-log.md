# The examples' mutation log

Evidence that each rule the examples task adds to `test-docs` fails through the property it names,
and that what the examples print was run on more than one library
([the plan](2026-11-21-examples-plan.md), §2, §4 and §5). Format of
[slice 4's log](m5-slice-4-mutation-log.md).

The M4 session built it on `examples`, from `21b3e1b`, the squash of PR #60 that `v0.1.0` tags,
once the release was cut, and moved it to `16f1787`, the close-out's squash, before its PR.
Builds and suites ran in the Guix container: Chez 10.4.0 (`ta6le`, threaded), x86_64, Guix's
SQLite 3.53.1. The plant driver is in
[research/examples/](research/examples/), its output in
[research/examples/out/](research/examples/out/).

## What it adds

- **`examples/`, five whole programs:** `basics.sps`, `transactions.sps`, `prepared.sps`,
  `file-database.sps` and `json.sps` (the plan, §1).
- **`docs/examples.md`, "Examples":** a section for each, the file linked, its program in full,
  and what it prints. It is second in `site/pages.sls` and in README.org's Documentation list,
  and the quick start's Next list links it first.
- **`tests/test-docs.sps`:**
  - `program-session` and `run-in`: each child runs from its own temporary directory, through
    `/bin/sh`'s `cd`, with `src` named by its absolute path and a relative `CHEZ` made absolute;
    the files it left there are read, and a whole program that left one runs again there.
    `program-run` is its first run;
  - `private-names`: each list of a program's data, at any depth, that begins `chez-sqlite3
    private`, a list's tail never one. 1 row on 22 of the suite's own texts;
  - `example-problems`, through `lines-between`, `linked-example` and `written-link`: the page's
    whole programs against the files of `examples/`, and each program's link as written. 10 rows
    on the suite's own texts;
  - `run-line-problems`: the page's `sh` blocks name a file of `examples/` from beside a clone,
    and each is there. 1 row;
  - on the real tree, 6 rows: the twins; the run line; each of the page's programs has a text
    block; no whole program names a private library; a program writes beside itself, not in the
    checkout; and some whole program leaves a file and runs again. Then, for the five programs,
    11: each exits 0 with nothing on stderr and prints its text block, and the file example's
    second run prints the same.
  - **The counts:** 162 passes on `21b3e1b`, 191 with the examples, 29 rows more: 12 on the
    suite's own texts, 6 on the tree, and 11 for the programs.
- **CHANGELOG.md:** an `[Unreleased]` Added entry.
- **The quick start:** a note under its clone line on git's "is not a commit!" and detached HEAD
  (the maintainer's "Fold it in").
- **The live check's page list** gains `examples.html`. A run against `v0.1.0`'s site now fails
  its pages clause, as it should: that site has no such page.
- **ADR-0022's decision 2 and `global-constraints.md`'s line on the pages,** amended: five pages.
  Proposed, and accepted by the maintainer on 2026-11-21 ("Accept it").

## The rules watched failing

`plants.py build` copied the working tree, `git ls-files -co --exclude-standard`, with
`build/akku` and `build/scheme-libs`, into a tree per plant, and planted it;
`run-plants.sh` ran each tree's suite, `test-docs` or `check-site`'s last check; `plants.py
report` read each log's failing rows against the rows the plant must fail, and none other
([out/plants.txt](research/examples/out/plants.txt)). 30 trees, every one as expected:

| Plant | What failed, by name |
|---|---|
| control, none | nothing; 191 passes |
| a line of json's text block changed | `docs/examples.md:311`, prints the text block |
| `basics.sps` changed, its block not | the twins: `(docs/examples.md 21 not-its-file examples/basics.sps)` |
| a comment of basics' block changed, its file not | the twins: the same |
| `examples/extra.sps`, no block links it | the twins: `(examples/extra.sps no-block)` |
| a whole program with a text block and no link | the twins: `(docs/examples.md 306 no-file-link)` |
| basics' and transactions' links swapped | the twins: each block `not-its-file` the other's |
| prepared's text block removed | `(docs/examples.md 167 no-text-block)` |
| `(chez-sqlite3 private utf8)` imported, block and file | the private names: `(docs/examples.md 21 ((chez-sqlite3 private utf8)))` |
| a second `import` in basics' body, of the private library | the same |
| an `environment` of it in transactions | the same, at line 94 |
| transactions' link text naming basics | the twins: `(docs/examples.md 94 link-not-written examples/transactions.sps)` |
| the run line naming `examples/basic.sps` | the run line: `(docs/examples.md 10 no-such-file examples/basic.sps)` |
| an editor's lock file, `examples/.#basics.sps` | nothing; 191 passes |
| transactions writes to stderr | `docs/examples.md:94`, exits 0 with nothing on stderr |
| prepared exits 3 | `docs/examples.md:167`, the same |
| `run-in`'s `cd` dropped | the relative write lands in the checkout; no program leaves a file, so none runs again; `notes.db` lands in the tree's root |
| `reader-libdirs` relative again | every whole program and both guard children: 18 rows |
| no second run | some whole program leaves a file and runs again |
| `file-database.sps` adds a note each run, `notes: #(1)` shown | `docs/examples.md:231`, run again, prints the same |
| `linked-example` takes the first link, not the last | the row on the last of two links |
| `linked-example` reads links before the Scheme block before | that row, and the row on a program that links no file |
| a file held to its block's lines, not their text | the row on a missing last newline, among others |
| `private-names` walks a list's first element alone | `private-names` on the suite's texts |
| `private-names` walks tails too | the same |
| `private-names` not into vectors | the same |
| `private-names` keeps a name twice | the same |
| any link counts as written | the row on a link's text |
| the page out of `site/pages.sls` | `check-site`: `missing-from-site/pages.sls=(examples.md)` |
| the page out of README.org's list | README.org links every page of `docs/` |

- **The private import** ran and printed its text block, exiting 0: only the new row failed.
  So did the body import and the environment, the review's.
  `src`, the reader's library path, holds the private libraries too, so nothing else refuses one.
- **The rows on the suite's own texts** first failed once on a wrong expectation, a runnable
  block's four lines counted as three (line 9 for 10), which was fixed. Each helper's rows were
  then watched failing against a planted helper (below).

## The review

One Opus reviewer, read-only, on the worktree before its PR: no blocker, no major, five minors and
five nits. It ran `test-docs` on 3.45.1, 3.53.1 and 3.54.1, 187 passes each, and planted three
trees of its own that passed. The lead reran its body-import tree and its two probes (both exited
0, and the tree passed 187), and took every finding but the two under **Left**:

- **A private library reached past the import form passed:** a second `(import …)` in the body,
  `(only (chezscheme) import)` first, and `(environment '(chez-sqlite3 private utf8))`. The rule
  now walks every datum, `private-names`, in place of reading the first one's import sets.
- **A link whose text names another file passed** (its plant B), and **a run line naming a file
  that is not there passed** (plant C). Each now fails: `link-not-written`, and the run-line row.
- **`json_group_array`'s order came from a subquery's `ORDER BY`,** which SQLite doesn't promise.
  It is now `json_group_array(… order by id)`, an aggregate's own `ORDER BY`, which 3.45.1 has;
  the three libraries print the same as before.
- **The constraint line** was marked *(provisional)*, as the file's header asks, until the
  amendment was accepted.
- **An editor's lock file, `examples/.#basics.sps`,** would have been read as an example; a name
  beginning with a dot no longer is. **A relative `CHEZ`** would have failed every child after
  the `cd`; it is made absolute.
- **The counts** were 173 against 187; they are 162 against 191, above. **Prose:** "names the
  kind of constraint"; `jsonb` "gives", not "stores"; "shows a program in full".
- **Left:** on `main`, the page runs `chez-sqlite3/examples/…` while README.org's clone line names
  `v0.1.0`, which has no `examples/`; the next release's tag closes it. A checkout path holding
  `:` would split `--libdirs`, as it would `make test`'s own.

| Agent | Model | Tokens | Tool calls | Time |
|---|---|---|---|---|
| Reviewer | Opus | 210k | 56 | 13 min |

## The probe

[run-drafts.sh](research/examples/run-drafts.sh) ran each program on three libraries, from a fresh
directory, twice: 3.45.1, the floor's build; Guix's 3.53.1; and 3.54.1. All 30 runs exited 0
with nothing on stderr. Each program printed the same on all three, and the same the second time.
Only `file-database.sps` left a file, `notes.db`. Its output, `sql-null` as `#<sql-null-type>`
and the constraints' extended codes, came out alike on all three; so did the constraints'
messages, which no program prints. Apple's 3.51.0 and Homebrew's run at the next release's Mac
walk.

## Cost

`make test-memory MEMORY_SUITES=tests/test-docs.sps`, in the container on the same machine: 57 s
on `21b3e1b`, 106 s with the examples, each within the limit of 450 s. On CI, `memory-1` gave
`test-docs` 68 s on the tag's run, 44924721168; by the same ratio, about 127 s. The PR's CI run,
44944425019 on `7389bcc`, gave 125 s. Its `memory-1` shard's 48 suites took 1,923 s together, up
from 1,871 s, the slowest 167 s and none slow, and the job 37 min 45 s of its 120.
