# M5 slice 4 mutation log

Evidence that each rule slice 4's checks claim to guard fails through the property it names, and
that what the pages say of the code was run against it ([the M5 plan](2026-11-20-m5-plan.md) §5,
slice 4, §4.1, §4.2 and §4.10's twin, clone and floors items; probes P4 and P6, §8). Format of
[the slice 2 log](m5-slice-2-mutation-log.md).

The M4 session built the slice, as the maintainer's split has it, on `m5-slice-4` from slice 2's
merge `8c18272`, beside slice 3 in the M3 session. Three Opus agents worked in worktrees of their
own, on disjoint files: the pages and README.org; the reference's gaps and wordings; the checks.
The lead read each hand-back, reran its checks, and joined their files. Builds and suites ran in
the Guix container: Chez 10.4.0 (`ta6le`, threaded), x86_64, Guix's SQLite 3.53.1. The drivers are
in [research/m5-slice-4/](research/m5-slice-4/), their outputs beside them as `.out`.

## What the slice adds

- **Three pages,** beside the reference, each ELI5 and linked from README.org, which lists them in
  the nav's order:
  - `docs/quickstart.md`, "Quick start", the site's home (Q11): the clone line, the library path,
    Homebrew's `chez`, a first program shown whole, its body as a `scheme run` block, what a Mac
    meets, a program that says which library loaded or why one was refused, the tests, and the
    other pages;
  - `docs/finding-sqlite.md`, "Finding SQLite": the override, discovery's candidates by system
    with each candidate's source, the six refusals, who needs the override, `DYLD_LIBRARY_PATH`;
  - `docs/libraries.md`, "What varies by library": the six libraries the suites ran on, then
    extension loading, defensive, FTS5, DQS's messages, out of memory in a transaction, threads,
    the Mac's loader, and the tests on Apple's library.
- **README.org, thin, in chez-curl's order:** the title, the CI badge, one line, the AI
  disclosure, what it is, Status (the platforms and SQLites run, those not run, Windows, the API
  before 1.0, CHANGELOG.md by name alone), Requirements (the two floor lines, then the tests'
  needs in prose), Installing, A taste (the one Scheme block), Documentation, License.
- **`site/pages.sls`:** the four pages, the quick start first, each labelled by its H1.
- **The reference** (below): three gaps closed, three wordings fixed, and `wal` on `""`.
- **`tests/test-docs.sps`, the twin rule:** README.org holds a Scheme block, and each of its
  Scheme blocks is, line for line, all of a `scheme run` block of a page of `docs/`, the `;; =>`
  line included. `twin-problems`, held on the suite's own texts first in 8 rows, then the real
  tree in 1; and `nested-blocks`, since the Org reader reads no block inside another, so a
  Scheme block inside a quote would escape every block rule: 1 row on the suite's own texts, 1
  on README.org. 107 passes to 120, to 151 with the maintainer's three checks, and to 161 with
  the cross-check's fixes (below).
- **`tests/test-manifest.sps`, the clone check in place of its tripwire:** `clone-problems ROOT
  VERSION`. Every line of README.org, or of a file under `docs/`, that holds `git clone` is, past
  its leading spaces,
  `git clone --branch vX.Y.Z https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git`,
  X.Y.Z the manifest's version, or at 0.0.0 the same without `--branch vX.Y.Z`; README.org and
  `docs/quickstart.md` hold one each, as ADR-0007's amendment says, and another page any number.
  Held on ten fixture
  trees under `tests/fixtures/clone-lines/` first (12 rows, and one that every tree is read),
  then the real tree. 84 passes to 93.
- **`check-floors` reads `docs`,** a fifth argument (the Makefile's recipe, comment and help):
  `docs-problems`, every file under the directory and its name, line by line, a code block's
  lines among them; and `readme-line-problems`, every line of README.org but the list lines of
  its one Requirements section. `tests/test-check-floors.sps`: 461 passes to 541, with fixtures
  under `tests/fixtures/floors/`, two of them symbolic links.
- **`tests/check-site.sps`, invariant 7 without its fallback:** a README.org with no
  `** Documentation` section, or with two, dies, naming it; and an eighth invariant, each page's
  H1 its nav label.

## The reference, run against the code

Each run in the container; the probes are in
[research/m5-slice-4/reference/](research/m5-slice-4/reference/).

| Item | What the code did | Reference |
|---|---|---|
| Gap 1, ADR-0014 | A step's NOMEM ended the transaction at once in a `select` reading a table, an `insert … select` and a one-row insert; it stayed open for `select randomblob(100000)`. A column read's NOMEM ended it at the next `reset!` (`gap1-nomem-ends`); `test-transaction-nomem`'s S and R rows hold the same | `with-transaction`'s failures that end a transaction gain out of memory, at the step or the next reset or finalize, and `in-transaction?` to tell; `step!` points there |
| Gap 2, ADR-0016 | An expiry past the fold's last step answered the fold's sum on resume; one before it raised closed (`gap2-fold-expiry`, every fuel to completion, cold and warm) | `query-fold`'s preemption paragraph tells both; its continuation paragraph gains "from past the last step, gives the fold's answer again", which `test-conveniences-resumed` holds |
| Gap 3, ADR-0018 | `delete`, `truncate`, `persist` and `wal` each mismatch on `":memory:"` and on a file opened `memory`, reading back `memory`; `wal` on `""` reads back `delete` (`gap3-journal-memory`; `test-open-settings`, two rows) | Any `journal-mode` on an in-memory database; and `wal` on `""` |
| ADR-0012's close at an expiry | The caller got `&assertion` "no engine active", `error?` `#f`; the close's own condition reached only a guard inside the engine; the connection stayed open (`wording-ab-lost-engine`) | The record was right: "the engine is lost: its caller gets Chez's own assertion violation, … and the connection stays open" |
| ADR-0017's rollback at an expiry | The same assertion violation; the `busy` reached only an inner guard | The record was right: "Chez's own assertion violation", in `with-transaction` and `query-fold` alike |
| ADR-0018's `wal` beside a reserved lock | `begin immediate` with nothing written answered busy at once, as with a write; a read and `begin exclusive` waited the 1500 ms out (`wording-c-wal-reserved`, the grain read first) | The record was right: the table's row is "in `begin immediate`, or in `begin` and has written" |

## The red runs

Each check, first as a stub that never fires: the twin rule's six own-text rows failed; the clone
check's ten fixture rows; `docs-problems`' 31 rows. Then green (the checks agent's
`*-stub.log` and `final-*.log`).

## The plants

The checks agent's, on stand-in pages ([research/m5-slice-4/checks/](research/m5-slice-4/checks/));
line numbers are the stand-ins'.

**The twin rule** (`plants-twin.sh`):

| Plant | Caught by |
|---|---|
| Any Scheme block a twin, not only `run` | "…the same lines in a block not marked run are no twin…" |
| Lines trimmed; a prefix a twin | "…a twin is all of a runnable block's lines, as written…" |
| Only the first block held | "…two Scheme blocks, each held…" |
| README's block one char off; its twin's fence plain `scheme`; the twin deleted | the real row, `(("README.org" 26 no-twin))` |
| No Scheme block | `(("README.org" no-scheme-block))` |
| A second block with no twin | `(("README.org" 35 no-twin))` |

**The clone check** (`plants-clone.sh`):

| Plant | Caught by |
|---|---|
| The count rule dropped | `extra-lines`, `missing-lines` |
| Containment for equality | `spacing` |
| Every page a home | the fixtures, and the real row: "docs/reference.md: it holds no git clone line, but must hold one" |
| The version ignored | `released` |
| A missing quick start allowed | `no-quickstart` |
| Another version; another URL; `--branch` at 0.0.0 | the real row, naming the line and the line its version calls for |
| A second line in the quick start; none in the quick start | the real row, naming the file and its lines |
| A wrong line in another page | the real row, naming the line and the line its version calls for |
| None at 0.1.0, the manifest and changelog bumped | both lines named; with all four bumped, a control, it passed |
| `Akku.manifest` bumped alone | the version row, and the clone row naming both lines |

**`check-floors`' docs input** (`plants-floors.sh`): ten library mutants, each failing 1 to 31
rows, among them `docs-problems` never firing (31), README.org's other lines not held (24),
Requirements' prose exempt (4), a list line exempt anywhere (2), names not held (5), an empty
`docs` passing (1), lines joined at a backslash (1), YAML's rules applied (20); three program
mutants (docs not held, 7; an unreadable page not named, 6; four arguments taken, 1); the
Makefile without `docs`, a usage error. On the tree: a page naming the SQLite floor in each of its
three forms at the start, middle and end of a line and beside each kind of neighbour gave the 17
lines expected, byte for byte; README.org's Status naming the Chez floor; a floor in a page's
code block.

**check-site** (`plants-site.sh`): with `** Documentation` deleted, main's check-site failed on
another invariant, the new one by name; with main's README.org, main's passed by the fallback, the
new one failed by name.

**On the real pages,** the lead's ([research/m5-slice-4/plants/](research/m5-slice-4/plants/),
`real.sh`), each in a fresh copy:

| Plant | Caught by |
|---|---|
| README.org's block one char off | test-docs, the twin row |
| The quick start's twin fenced `scheme` | test-docs, the twin row |
| The quick start's line `--branch v0.1.0` at 0.0.0 | test-manifest, the clone row |
| A second clone line, in the quick start | test-manifest, the clone row |
| `docs/libraries.md` naming 3.45.1 | check-floors: "docs/libraries.md: line 100 contains the SQLite floor …" |
| `docs/finding-sqlite.md` naming 3045001 | check-floors: "… contains 3045001, the version-number form …" |
| README.org's Status naming Chez's 10.4.0 | check-floors: "README.org: line 28 contains the Chez floor 10.4.0, which only the list lines under \"** Requirements\" may write …" |
| `** Documentation` renamed | check-site: "README.org has no \"** Documentation\" section …" |

**Slice 2's survivor, r4** (`r4.sh`): render-site asking each page's neighbours of a page no nav
holds. On the four pages, site-render-unit failed "each page's footer links its neighbours in the
nav, or is absent with none". On one page it had passed.

**Slice 2's review's site plants** (the M3 session's review of slice 2; `plants/site-review.sh`),
on the four pages, each in a fresh copy, `make check-site`:

| Plant | Caught by |
|---|---|
| R-a, the nav reversed; R-b, neighbours of the reversed nav; R-c, the nav the home alone | site-render-unit, "each page's footer links its neighbours in the nav, or is absent with none" |
| R-d, the home the last page; P1, every page written `index.html` | site-render-unit, "a link to the home page is written as index.html…" and "on the home page, index.html is linked by the wordmark…" |
| R-f, every page after the home written `pages.html` | survived before slice 3 merged: invariant 5 takes its names from `page-file-name`, the code it checks. On this slice's rebase onto slice 3's merge, `047ee91`, site-unit's new row caught it: "every page of pages is written to a file of its own: the first index.html, each other its base name and .html" |

## The checks' review

An Opus agent, read-only, at `ef4ba1e`, its mutants and plants in copies. No verdict on the tree
was wrong; six gaps, each taken, and each mutant or plant rerun against the fix
(`plants/review-fixes.sh` and `plants/twinA2-exact.sh`, in a fresh copy each):

| Finding | Before | The fix, and after |
|---|---|---|
| The twin rule's rows held one position: the twin last among a page's runnable blocks, and in the last page | A2, each page's last runnable block alone, passed all 117; A1, the last page alone, only the real row caught | A row with the twin first, between and last among a page's runnable blocks, and in each of three pages: A2 exactly, A1, and a first-block mutant each fail it |
| The clone check refused a right line in any page but the two, which ADR-0007's amendment doesn't say | an editor's `docs/quickstart.md~` failed | Another page's lines are each held to the version, in any number; the two homes hold one each. A right line in `docs/libraries.md` passes; a wrong one is named |
| Invariant 7 read the first `** Documentation` section alone | a second, stale section passed check-site | Two sections die by name |
| `site/pages.sls` said each label is its page's H1, which nothing holds | | The clause is gone |
| A Scheme block inside an Org quote escaped every block rule: the reader reads no block inside another | a quoted block with no twin passed test-docs | `nested-blocks` and its rows: README.org holds no block inside another |
| The slice's records were uncommitted at `ef4ba1e` | | Committed with the fixes |

## The docs review

An Opus agent, read-only, at `ef4ba1e`: every page against `src/`, every measured claim against
its source, 36 plants in the pages, and the records' promises to the reference again. The quick
start's two programs ran as written: the first printed `(#("bird" 2) #("cat" 4))`; the second
named the override's library and source, then `guix-environment` with the override unset, and
refused as `invalid-override` for a bare name and `""`, `load-failed` for a missing file, and
`not-found` with no candidate.

**The promises:** the 36 all kept, the three partly kept now kept (ADR-0014:301 at the reference's
`with-transaction` and `step!`; ADR-0016:349 at `query-fold`; ADR-0018:175 at the settings), the
superseded one's replacement kept; the five more kept; and the three wordings now match their
records, the reviewer's own probe agreeing that a lost engine is `&assertion`, "no engine
active", `error?` `#f`.

**Its findings, each fixed in the pages:**

| Finding | The fix |
|---|---|
| The quick start's tests ran outside the clone: `make test` beside it found no rule | `cd chez-sqlite3` first |
| finding-sqlite said a Mac needs no override for Apple's library; only macOS 26's was measured, and ADR-0003 says Macs below the floor need it | macOS 26's alone; an older macOS's may be below the floor, and is then refused |
| No page said to point the compiler at another SQLite's headers, which every Homebrew run set | `C_INCLUDE_PATH` in the quick start's tests and libraries.md's |
| "The library loads when your program starts", unconditionally; the page's own program loads it in `eval` | Only a program that names a loading procedure; the conditions' accessors load nothing |
| "The fix is always one of two"; discovery never tries past the first file found | Name one, or install one where the list looks before the file refused |
| "SQLite's own build leaves FTS5 out"; 3.45.1's own `./configure` takes it by default | "compiled from its source with no options", here and in the reference |
| An override "is loaded as given: no search"; on a Mac `DYLD_LIBRARY_PATH` can swap it | The Mac's exception named, linked |
| Low: the reasons the conditions table names; the fold's "as in the procedure"; "your own build"; an override naming no file is `load-failed`; Ubuntu with its package; other systems; a link's label | Each reworded |

`load_extension()`'s refusal no longer says "every library": the 3.54.1 built without loading
skips that row as unavailable, so it is said of Apple's, by the Mac step, and of every library
that can load, by the suite.

**Below the plan's bar, kept:** three facts the M4 pre-work's census measured on Ubuntu's own
package in the container, which no suite asserts on a lane: Ubuntu's loading switch on at open
(m4-prework, the census, line 91, and its README, 108 and 131); the short DQS message on Ubuntu's
and the floor's (its README, 183 to 185); `defensive` off on the Linux libraries. The maintainer
chose "Keep, census named" (the plan's amendment).

**Its plants:** 36, each in a fresh copy at `ef4ba1e`, each replacement counted. 16 were caught:
an anchor's typo, a link to the right anchor on the wrong page, a heading renamed, a nav entry
or label changed, a run block's result, a README block and its twin wrong alike, three code
spans, a floor, a signature. 20 survived. The maintainer chose three checks for 14 of them
(below); the rest are reader-only: a Homebrew path, the DQS rows moved, macOS 26 to 15, Guix's
version, the busy table's columns swapped, `""` read as unset, `chez` to `chezscheme`, a code
span `call-with-db`, a bare name in prose; and 3.54.1, which the picker's fourth option would
have held.

## The maintainer's three checks

From the docs review's survivors, the maintainer chose "Run whole programs", "Tables held to
code" and "Small text rules" (2026-11-20). An Opus agent built them in its worktree from
`2bbf99e`; `tests/test-docs.sps` 120 passes to 151, `tests/check-site.sps` an eighth invariant.

- **Whole programs:** a Markdown `scheme` fragment whose first non-blank line begins `(import` runs
  as written, through `gated-command`, and must exit 0 with nothing on stderr; when the next block
  of its page is a `text` block, its stdout is that block's lines. One whose guard tests
  `sqlite-library-unavailable?` runs again with `CHEZ_SQLITE3_LIBRARY` naming a missing file,
  and must print one datum, as `write` writes it, a list whose first element is `refused`. A row
  fails unless the pages hold one of each.
- **finding-sqlite.md's tables:** the reasons table's first column, one code span a cell, is
  `sqlite-library-unavailable-reasons`, in order; the discovery table's four rows, Guix, other
  Linux, macOS and any other system, each name `libsqlite3-candidates`' paths and sources, in
  order, on x86_64 and on arm64, asked with a stand-in environment; the prose's override source is
  `choose-libsqlite3`'s; and the sources together are `libsqlite3-sources`.
- **Small rules:** every word of the pages that holds `CHEZ_` is `CHEZ_SQLITE3_LIBRARY`; every
  `export CHEZ_SQLITE3_LIBRARY=` gives an absolute path; and check-site's eighth invariant, each
  page's first line `# ` and its nav label.

`checks2/plants.sh`, rerun by the lead from the slice's worktree: the control passed; the
review's 14 plants each failed by name (p01, p28, p02, p08, p25 the tables; p03, p24, p32 the
words and exports; p19b check-site's eighth invariant; p04, p06, p07, p17, p29 the whole programs,
p17 at the run with the library missing alone); 8 more page plants and 20 mutants of the suite's
own readers each failed. Under the memory gate test-docs took 57 s, 35 s before: the three
programs' runs under Valgrind.

## The cross-check's fixes

The M3 session's read-only check of the PR, an Opus checker at `24c2f5e`, found that an ordinary
edit turned the whole-program rows off: `#!r6rs` or a comment first, or a block between a program
and its output, and a wrong stated output passed. An Opus agent fixed it and four smaller holes,
in `tests/test-docs.sps` alone, 151 passes to 161:

- a whole program is a fragment whose first datum, as Chez's `read` reads it, is headed `import`;
  its output block is the first `text` block after it before the next Scheme block; and a row
  fails unless some whole program's output is held;
- whole programs run with `--libdirs src`, the reader's path;
- the "which SQLite" program, with the library there, prints exactly the list the suite reads
  itself, `(list (sqlite-version) (sqlite-library-path) (sqlite-library-source))`;
- every `CHEZ_SQLITE3_LIBRARY=` at a line's start or after a blank gives an absolute path, an
  `env` or bare assignment as well as an `export`;
- the discovery table's labels each name their world;
- each page has one level-1 heading, its first line.

`checks3/plants.sh`, rerun by the lead from the slice's worktree, 64 runs: the control passed;
the cross-check's plants and the agent's own, n01 to n12, each failed by name (the `;; app.sps`
line, `#!r6rs`, an `sh` block between, each with the output `#("cat" 5)`; `(srfi :64)` imported;
`sqlite-library-source` read as `sqlite-source-id`; a relative bare assignment; two labels
swapped; a second H1; a blank line before an H1; the output block made `sh`; a relative `env`
assignment; the Mac row labelled `macOS`), and every earlier plant and mutant still failed. Under
the memory gate test-docs took 59 s. A setext heading, a line underlined with `===`, is read as
no heading by test-docs' reader; the pages use none.

## P4: the two anchor rules on the four pages

Slice 2's `anchors/probe.sps` and `compare.py`, against GitHub's rendering of each page at
`24c2f5e`, fetched on the host with `gh api` (`application/vnd.github.html`): **4 pages, 105
headings on GitHub; 0 page-rule pairs differ** ([p4/probe.out](research/m5-slice-4/p4/probe.out)).
With one of the site rule's anchors for `libraries.md` changed in a copy of the probe's output,
`compare.py` named `DIFFERS site libraries.md`.

## P6 on Linux: the walk as a reader

On the host, a fresh clone of the repository by the quick start's own line, checked out at
`24c2f5e` in place of the tag; the two whole programs lifted from the clone's own page (lines 37
to 46 and 95 to 104), and run with the host's Chez 10.4.0:

- `scheme --libdirs chez-sqlite3/src --program app.sps` printed `(#("bird" 2) #("cat" 4))`, the
  page's `text` block;
- the "which SQLite" program printed
  `("3.53.1" "/home/…/.guix-home/profile/lib/libsqlite3.so.0" guix-profile)`, discovery's pick
  on a host whose `GUIX_PROFILE` names the Guix Home profile; with the override naming a missing
  file, `(refused load-failed "/no/such/libsqlite3.so.0")`;
- **"Running the tests", verbatim from inside the clone:** `make test` ran 93, passed 80: the 13
  failures each named `sqlite3.h: No such file or directory`. The host has a C compiler and no
  SQLite headers, which README.org's Requirements call for. With `C_INCLUDE_PATH` naming the
  loaded library's headers, as the page now says for that case, it passed 91. The two left are
  the host's mixed toolchain: the distro's gcc, glibc 2.35, built the C oracle, which loads
  Guix's library and its glibc 2.41, and failed "version `GLIBC_2.36' not found"
  (`test-library-loading-real`, `test-native`). AGENTS.md runs a Guix host's tests through
  `scripts/guix-env`, where the same tree passed 93.

The page's tests paragraph first said `C_INCLUDE_PATH` was for another SQLite alone; it now names
the loaded library's headers too, when the compiler can't find them.

## P6 on the Mac: the maintainer's walk

The maintainer's Mac, arm64, Homebrew's Chez as `chez` (2026-11-20): a fresh clone by the quick
start's line, checked out at `ef357a2`; the two programs lifted from the clone's page (its lines
37 to 46 and 95 to 104, which no later commit of the slice moves).

| Step | Printed |
|---|---|
| `chez --libdirs chez-sqlite3/src --program app.sps` | `(#("bird" 2) #("cat" 4))`, the page's `text` block |
| the "which SQLite" program, by discovery | `("3.51.0" "/usr/lib/libsqlite3.dylib" macos-system)` |
| the same, `CHEZ_SQLITE3_LIBRARY` naming Homebrew's | `("3.54.1" "/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib" override)` |
| the same, the override naming Apple's path, `DYLD_LIBRARY_PATH` naming Homebrew's folder | `("3.54.1" "/usr/lib/libsqlite3.dylib" override)`: the override's path swapped by its leaf name, the first run of that case |
| an open with `(enable-load-extension . #t)`, by discovery | `unavailable`: `sqlite-extensions-unavailable?` held it |
| the same, on Homebrew's | `opened` |
| `make test`, Apple's library | ran 93, passed 93; 140 UNAVAILABLE lines, the checks Apple's library can't run |
| `make test`, Homebrew's, with `C_INCLUDE_PATH` naming its headers | ran 93, passed 93; no UNAVAILABLE line |
| `make site-deps`, then `make check-site`, Homebrew's cmark-gfm | up to date; all green, each page's H1 its label |

On Apple's library test-docs passed 151, its whole programs among them; the busy timeout's
grain read milliseconds (a 250 ms timeout answered busy after 280 ms); and the library's starts
read `defensive` on, as `docs/libraries.md` says.

## Found on the way

- **A plant's marker inside its own definition.** `r4.sh`'s first `sed` swapped
  `(neighbors nav name)`, which `(define (neighbors nav name)` holds too, and the copy failed to
  read, a failure that would have passed for a catch. It swaps the whole call now, and counts the
  definition after (AGENTS.md: predict a global replace's count).
- **A fold's expiry past its last step is held only where the statement goes back to the cache.**
  `test-conveniences-engines`' sweep takes the sum or closed at every fuel, and
  `fold-resumed-twice` asks the sum only when the statement went back to the cache; no row fails a
  fold that raised closed after an expiry that finalized it past its last step (cold 112–113, warm
  105–106 in `gap2-fold-expiry`). Not in this slice's files: an Open item.

## For the records

- **ADR-0016, an amendment,** where its 2026-11-16 amendment's "What it doesn't cover" says the
  expiry "finalizes", written into the record as proposed: "an expiry past the fold's last step,
  before its return, finishes the statement, finalizing it, or giving it back to the cache once
  the fold's body has answered, and the resume answers the fold."
