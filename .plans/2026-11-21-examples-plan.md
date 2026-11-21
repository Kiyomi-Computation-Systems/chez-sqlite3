# The examples: five programs and their page

- **Status:** the maintainer's task, asked on 2026-11-20 for after the release, and planned with
  them the same day ("Sounds good"). The picker answers: all four everyday examples (basics,
  transactions and errors, prepared statements, a file database), built-in JSON only (no
  `load-extension!` example), and a docs page as well as the folder. Started 2026-11-21, once
  `v0.1.0` was released ([the release](research/m5-release/README.md)).
- **Built by** the M4 session, on the branch `examples` from `21b3e1b`, moved to `16f1787` before
  its PR, as one PR with a mutation log ([examples-mutation-log.md](examples-mutation-log.md)) and
  an Opus review. **Checked read-only by** the M3 session. **Merged** as PR #62, `7d762c2`, on
  2026-11-21, with CI passing in every job.

## 1. What a reader gets

- **`examples/`**, five whole programs, each run as
  `scheme --libdirs chez-sqlite3/src --program chez-sqlite3/examples/NAME.sps` beside a clone:
  - `basics.sps`: a table in memory; inserts with `?`; `query` and `query-row`, and `#f` for no
    row; NULL as `sql-null`; a BLOB as a bytevector; `last-insert-rowid`; `changes` after an
    update and a delete; an upsert with `RETURNING`;
  - `transactions.sps`: `with-transaction` for a batch; a transfer, both updates or neither; a
    CHECK refusing one, after its first update ran, and the rollback undoing it; a UNIQUE column
    refusing a duplicate, each caught by `sqlite-constraint?` and named by its extended code;
  - `prepared.sps`: a statement prepared once, bound by name, stepped and reset for a thousand
    rows in one transaction; `query-fold` summing without a list; `call-with-statement` stepping
    and reading columns by hand;
  - `file-database.sps`: a file opened with `journal-mode`, `foreign-keys` and `busy-timeout`;
    migrations through `execute-script!`, each in a transaction with its `user_version`; a
    foreign key refusing a note. Run again, it prints the same;
  - `json.sps`, SQLite's built-in JSON: a `json_valid` CHECK; `->` and `->>`, and an index on
    `doc ->> '$.kind'`; `json_each`; `json_object` and `json_group_array`; `json_set` and
    `json_remove`; `jsonb`.
- **`docs/examples.md`**, the page: a section for each, its program in full, linked to its file,
  and what it prints. It is the fifth page, second in the nav, after the quick start; the quick
  start's Next list links it.
- **CHANGELOG.md** gains an `[Unreleased]` entry: Added, the examples and their page.
- **The quick start's clone line** gains a note: git 2.54 warns that the tag "is not a commit!"
  and that the clone is a detached HEAD, both expected. The ledger's open item; the maintainer's
  "Fold it in" (2026-11-21).

No example prints a query plan, a version or a path: across libraries, only those differed
(the probe, below).

## 2. The rules, `test-docs`

The examples are the docs' whole programs, which `test-docs` already runs as written, through
`gated-command`: each exits 0 with nothing on stderr, and prints the text block after it, line for
line. New:

1. **The twins.** Each `.sps` file of `examples/` is, line for line, all of a whole program of
   `docs/examples.md`, and each whole program there is its file's: the file the page links last
   before it, after the Scheme block before it, by a link written
   `` [`examples/NAME.sps`](../examples/NAME.sps) ``. A file no block links, a block that links
   no file or one not there, a block that is not its file's text, a link whose text is not its
   file's path, and a file two blocks link each fail, by name. So the files run, through their
   blocks. A name beginning with a dot, an editor's lock file, is no example.
2. **Each whole program of `docs/examples.md` has its text block,** what it prints; and its `sh`
   blocks run a file from beside a clone, `chez-sqlite3/examples/NAME.sps`, each file there.
3. **No whole program names a `(chez-sqlite3 private …)` library,** in any of its data: no list,
   at any depth, begins `chez-sqlite3 private`. So neither its import form, a second `import` in
   its body, an `environment` nor a quoted name reaches one. The reader's library path, `src`
   alone, finds those too, so nothing else would refuse one.
4. **Each child runs in its temporary directory,** with `src` named by its absolute path, and a
   relative `CHEZ` made absolute, so a program's files land there, not in the checkout. Under
   `make test-memory` the gate's log path is absolute already.
5. **A whole program that leaves a file in its directory runs again there,** and exits 0 with
   nothing on stderr, printing the same. `file-database.sps` is the one that does.

Rules 1 and 2 hold `docs/examples.md` and `examples/` to exist and hold at least one twin, so no
row passes on nothing.

## 3. Where else it shows

- `site/pages.sls` and README.org's `** Documentation` list gain the page, second, in one order,
  which `check-site` holds; README.org links it, which `test-docs` holds.
- The live check's fixed page list,
  [research/m5-closing-review/live-check.sh](research/m5-closing-review/live-check.sh), gains
  `examples.html`.
- **ADR-0022, decision 2, amended:** five pages, the fifth the examples, whose programs are
  `examples/`' files, held by `test-docs`. ADR-0022 rejected "`examples/*.sps` run by a suite" for
  README.org's example (Q8): that stands, and these files run through their page's blocks, with no
  suite or wrapper of their own. `global-constraints.md`'s line on the release says the same. The
  maintainer accepted both on 2026-11-21 ("Accept it").

## 4. The probe

Each draft ran on three libraries, from a fresh directory, twice: 3.45.1, the floor's build;
Guix's 3.53.1; and 3.54.1, a current build
([research/examples/run-drafts.sh](research/examples/run-drafts.sh)).
All five exited 0 with nothing on stderr, printed the same on all three, and printed the same the
second time. Only `file-database.sps` left a file, `notes.db`. In planning, the JSON probe's query
plan said `USING INDEX` on one library and `USING COVERING INDEX` on another, and `json_pretty` is
missing at 3.45.1: neither is shown. The Mac's libraries, Apple's 3.51.0 and Homebrew's, run at the
next release's Mac walk.

## 5. Plants

Each is watched failing by name, against a copy of the tree, then put back (the mutation log):

- a line of a text block changed;
- a file edited without its block, and a block without its file;
- a file no block links, and a block that links no file;
- two blocks' links swapped;
- a whole program with no text block after it;
- a private import, in a block and its file;
- a write to stderr, and a nonzero exit;
- the children run in the checkout's directory, not their own;
- the file example printing more on its second run;
- the page left out of `site/pages.sls`, and out of README.org.

## 6. Cost

`test-docs` runs in `memory-1`. On the tag's run, 44924721168, it took 68 s under the gate, its
limit 450 s, and the shard's suites 1,871 s together. The examples add six children, the file
example's second run among them. The PR's CI run, 44944425019, gave 125 s, and the shard's
suites 1,923 s; a suite of their own comes only if it nears the limit.

## 7. Not in it

- A `load-extension!` example (the maintainer's "Built-in JSON only").
