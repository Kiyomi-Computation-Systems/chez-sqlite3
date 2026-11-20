# Research: M5's pre-work, the release

Written 2026-11-17, before M5 has a plan, on `main` at `fa7a222`, while M4's slices 2 to 5 were
unmerged; every fact then was read from the file named beside it. **Refreshed 2026-11-19, on
`main` at `79fa1ac`, once M4 was done:** each figure re-read there, §6 rewritten as what M4
settled, §8 for what the refresh ran, §9 for an audit of the records' promises to the reference,
and Q9 and Q10 added. chez-curl was read at `fa9750d`, its `main` after v0.1.2's close-outs, and
still its head on GitHub on 2026-11-19. Nothing here ships.

M5 is "the release" ([the brief](../../2026-11-13-chez-sqlite3-project-brief.md), §6). This note
gathers what its plan will need: what our records ask of it, what the tree holds today, what
chez-curl did on its way to 0.1.0 and after, and the decisions only the maintainer can make. It
designs no slice.

## 1. What M5 must deliver, by our records

- **`/docs` finished, README, CHANGELOG, 0.1.0** (brief §6, lines 194–195). The brief names no
  page but `docs/reference.md`, which "grows from M1's first export on" (the harness plan, §4,
  line 98).
- **Install instructions, and their check.** "`test-manifest`'s checks of install instructions
  wait for the first release, which writes them" (the harness plan, §6, slice 2, lines 135–138).
- **The version, held three ways.** `tests/test-manifest.sps` holds `Akku.manifest`, `Akku.lock`
  and CHANGELOG.md's latest version to each other
  ([ADR-0007](../../decisions/0007-test-harness-and-scheme-dependencies.md), decision 2).
  CHANGELOG.md follows Keep a Changelog 1.1.0 and semver (the harness plan, §1, line 39), and
  AGENTS.md says "Add entries to `CHANGELOG.md` for each release" (line 62).
- **README.org's Requirements states the floors** of `packaging/floors.sexp`, held by
  `make check-floors`, and `check-test-fails` plants a README that disagrees
  ([ADR-0008](../../decisions/0008-floors-have-one-source.md), decisions 2 and 5). No other house
  document restates a floor ([global constraints](../../global-constraints.md), Platforms).
- **The docs' rules** (AGENTS.md): `/docs` is for users alone, "very concise, focused, to the
  point, ELI5 style" (lines 63–64). Every export carries a Typed Racket signature comment (line
  19), and `test-reference` holds the reference's signatures to them, the one test that reads a
  comment (lines 82–85).
- **The records' promises to the reference.** 36 lines in ADR-0012 and ADR-0014 to ADR-0021 name
  `docs/reference.md`, most as "`docs/reference.md` says so". ADR-0019 adds "The docs give each
  busy case's remedy" (line 313). §9 audits each against the reference.
- **What a reader must be told, by the records:**
  - how SQLite is found: `CHEZ_SQLITE3_LIBRARY`, else one candidate list per world. On macOS the
    one candidate is `/usr/lib/libsqlite3.dylib`, and Homebrew's is reached by the override
    ([ADR-0002](../../decisions/0002-runtime-libsqlite3-discovery.md), decision 2 and its M1
    amendment);
  - which systems need the override: Ubuntu 22.04 (3.37.2), Debian 12 (3.40.1), and macOS 14 and
    15, believed 3.43.x (brief §2.2; ADR-0003's table);
  - the compile-option query, exported "so an application can check at startup" (brief §2.6);
  - the platforms: Linux and macOS, amd64 and arm64, never Windows; CI on Linux alone, macOS by
    hand (ADR-0004; AGENTS.md lines 12–15).
- **No record settles anything else about a release.** A grep of `.plans/decisions/` for release,
  version, CHANGELOG, Akku, README and `docs/` found the rules above and nothing on a site, a
  GitHub Release, what an archive holds, or publishing to Akku.

## 2. What exists today

At `79fa1ac`. No M4 commit touched README.org, CHANGELOG.md, `Akku.manifest`, `Akku.lock` or
`tests/test-manifest.sps` (`git log fa7a222..79fa1ac` on them lists none), so their rows stand as
first written.

| Path | Size | What it holds |
|---|---|---|
| `README.org` | 15 lines | A title; "It is in development" (line 5); a link to the reference (line 10); `** Requirements`, the two floor lines (12–15). No status, platforms, install, example or licence. |
| `CHANGELOG.md` | 7 lines | The header, naming Keep a Changelog 1.1.0 and semver (3–5); `## [Unreleased]`, empty (7). |
| `Akku.manifest` | 24 lines | `("chez-sqlite3" "0.0.0")` (19); no `depends` and no `scripts`, each explained (4–15); "The version stays 0.0.0 until the first release" (17); `depends/dev` chez-srfi alone (24). |
| `Akku.lock` | 9 lines | chez-srfi alone. |
| `docs/` | 1 page | `reference.md`. |
| `packaging/` | 2 files | `floors.sexp`, 4 lines, Chez 10.4.0 and SQLite 3.45.1; `debian-prereqs.txt`, 51 lines, CI's packages. Nothing about a release. |
| `.github/workflows/` | 1 file | `ci.yml`, 617 lines. |
| `.gitattributes`, `.akkuignore` | none | |
| Tags | none | `git tag -l` lists none. |

**`tests/test-manifest.sps`,** 582 lines:

- the package is chez-sqlite3, BSD-3-Clause, with no `depends` and no `scripts`, and its
  `depends/dev` exactly chez-srfi in the pinned range (rows 365–389); `Akku.lock` holds that one
  project, with its url and a sha256 (391–410);
- `latest-release` (line 270) reads CHANGELOG.md as Keep a Changelog writes it: `## [Unreleased]`
  first, then `## [X.Y.Z] - YYYY-MM-DD`, newest first by number and by date. It refuses any other
  heading shape, a release below an older one and `[YANKED]`, and reads no heading inside a fence
  (header lines 24–32; rows 414–537). It was copied from chez-curl's (the harness plan, line 36);
- **the version:** `Akku.manifest`'s is CHANGELOG.md's latest release, or 0.0.0 while there is
  none (549–553), so a release that bumps one alone fails;
- **a tripwire for install lines:** a line holding "git clone" in README.org, or in any file under
  `docs/`, fails the suite, "no clone-line check exists yet, so none may be written" (555–580).
  M5's install steps trip it, so M5 replaces it with the check the harness plan owes.

**`tests/test-reference.sps`,** 525 lines (header, lines 1–48): `docs/reference.md` has one `###`
entry per export of `(chez-sqlite3)`, as Chez's `library-exports` lists them, and no other. Each
holds one `text` block, `NAME : TYPE`, equal character for character to that export's signature
comment in `src/chez-sqlite3.sls`. A procedure's type holds `->`, and a value's doesn't.

**`tests/test-docs.sps`,** 1,020 lines, for README.org and every `docs/*.md` (header, lines 1–55):

- every block names `scheme`, `sh` or `text`, and every Scheme block is a fragment that Chez's
  `read` reads, or a runnable example;
- a Markdown block fenced `scheme run` is evaluated, and its last line, `;; => DATUM`, asserted,
  with every native count zero after. The convention is Markdown's: a Scheme block in README.org
  can only be a fragment;
- every relative link and anchor resolves, anchors by GitHub's rule, and none points into
  `.plans/`;
- README.org links every page of `docs/`;
- no page says `ADR-`, `TODO`, any "yet", "unreleased", "slice", a `.plans` path, or a date
  written `YYYY-MM-DD`;
- a code span that is one name beginning `sqlite-` or `chez-sqlite3-` is an export.

**`docs/reference.md`,** 1,707 lines: an intro (1–41) with the import, the contents and the type
names; then eight `##` sections and 70 `###` entries, one per export, which `test-reference`
holds to `src/chez-sqlite3.sls`'s 70 signature comments. M4 added the Extensions section and two
exports, `load-extension!` and `sqlite-extensions-unavailable?`.

| Section | Line | Entries |
|---|---|---|
| Connections | 42 | 5, and `#### Settings` at line 110 |
| Extensions | 379 | 1 |
| Conveniences and counters | 467 | 9 |
| Transactions | 703 | 2 |
| Statements | 841 | 9 |
| Values | 1013 | 8 |
| The library | 1223 | 7, and `#### Which SQLite` at line 1243 |
| Conditions | 1362 | 29 |

- 46 Scheme blocks, 38 of them `scheme run`.
- It says nothing of installing. How SQLite is found is now `#### Which SQLite` (1243):
  `CHEZ_SQLITE3_LIBRARY` first, then discovery's candidates for Guix's C library, other Linux and
  a Mac (1253–1259). `CHEZ_SQLITE3_LIBRARY` is on 4 lines. Apple's library is named where it
  differs: `defensive` starts on (163), and it has no extension loading (193, 463 and 1704).
  `DYLD_LIBRARY_PATH`'s redirect, the maintainer's "Document it" (ADR-0002, amended), is told for
  extensions (420 and 462) and for the library (1269–1276 and 1313). Homebrew and Ubuntu are
  named nowhere.

**The Makefile,** 858 lines: 22 targets on its `.PHONY` line (179), M4 slice 2 adding
`check-variadic`, each listed by `make help` (184), and `check-help` holds the two equal. None
renders docs or makes a release. The docs are two suites that `make test` runs, `test-docs` and
`test-reference` (`SUITES`, line 32). The nearest to a release are `check-floors` (392),
`check-ci` (419) and `check-pins` (303, on the host alone). chez-curl's docs survey found no
release target in any sibling either (its `.plans/research/m8/surveys/docs.md`, §4).

**`.github/workflows/ci.yml`:**

- it runs on a push to `main` or to a `v*` tag, on every pull request, and by hand (lines 53–58),
  so a tag's push runs every job;
- `permissions: contents: read` (60–61);
- six jobs, each on `ubuntu-24.04` with `timeout-minutes: 60`: `main` (86), `memory-1` (195),
  `memory-2` (257), `nothreads` (319), `floor` (379) and `current` (490). Since M4's closing
  review, `current` builds a second 3.54.1 without extension loading, as Apple's has none, and
  runs the whole `make test` again against it (482–489, 586–616). Branch protection requires all
  six (progress.md, line 38);
- `tests/check-ci.sh`, 858 lines, holds it. The directory must hold `ci.yml` alone (lines 6 and
  127–130), its `on`, `permissions` and `concurrency` blocks line for line (133–146), and its
  six jobs by name, each with a whole-number `timeout-minutes` (581–582 and 784). `check-floors`
  reads every file in the directory too. So a second workflow, such as one for Pages, changes
  `check-ci.sh` first (AGENTS.md, lines 16–18);
- no CI file names an architecture: a search of `scripts/ci/`, `ci.yml` and `check-ci.sh` for
  `ta6le`, `x86_64`, `amd64`, `arm64` and `aarch64` found none.

**What a source archive would carry:** 1,218 tracked files, 791 of them under `.plans/`, and
`AGENTS.md` (`git ls-files`). An archive is no test tree: its `vendor/chez-srfi` is empty, which
`make deps` refuses (ADR-0007, decision 3), and `tests/test-conventions.sps` reads
`.plans/decisions` (lines 321–323). It is a library, though: §8 ran a program against one.

**Comments written for the build, not a reader.** A crude search of `src/` for "slice", a
milestone (`M` and a digit), `research/`, `traps.md` and "the maintainer" matches 165 lines in 22
of its 30 files, 162 of them lines that begin as a comment; of `tests/` (`.sps`, `.sls`, `.sh`,
`.c`), 1,048 lines in 94 of 120 files, 773 of them comment lines. It was 137 in 17 and 589 in 78
at `fa7a222`: M4 nearly doubled the tests' share. It counts comments and strings alike.

**Stale at 0.1.0, outside `test-docs`' reach:** `Akku.manifest:17` ("until the first release") and
`tests/test-manifest.sps:19–22` (the tripwire's "yet"). README.org's "It is in development" passes
`test-docs`.

**What the suites need besides Chez and SQLite:** a C compiler and `sqlite3.h`, whose absence
fails a suite (global constraints, Native code); GNU `timeout`, or Homebrew's `gtimeout` on the
Mac (`Makefile:40`); Valgrind, for `make test-memory`; and, from M4 slice 4, `sqlite3ext.h`
(ADR-0021's consequences). README.org's Requirements can't list them as list lines:
`check-floors` compares that section's list lines with the two floor lines, whole
(`tests/floors.sls`, lines 44–50 and 353–357). Prose there, or a list
under another heading, isn't compared.

**What varies by library, measured.** At `fa7a222` no page told any of it. M4 put three items in
the reference, marked "(the reference)" below; the rest is still in no page.

- Apple's 3.51.0 is `THREADSAFE=2`, keeps no memory count (`DEFAULT_MEMSTATUS=0`), and has no
  extension loading (`OMIT_LOAD_EXTENSION`) ([mac-d7](../mac-d7/README.md)); the last is in the
  reference (193, 463, 1704). It starts `defensive` on, where the six other libraries measured
  start it off ([m4-prework](../m4-prework/README.md), the Mac step) (the reference, 163).
- SQLite's default build has no FTS5, and a table using it fails at step, "no such module: fts5".
  Guix's, Ubuntu's, Apple's and Homebrew's have it (m4-prework).
- Ubuntu's 3.45.1 opens every connection with the C call that loads extensions already on
  (m4-prework, Q3). `load-extension!`'s refusal is what keeps it out of reach (brief §2.5).
- DQS's error message changed between 3.45.1 and 3.53.1 (m4-prework).
- Under `ENABLE_MEMORY_MANAGEMENT`, Homebrew's build among them, a statement's out-of-memory
  leaves its transaction open, where other builds end it ([m3-mac](../m3-mac/README.md);
  AGENTS.md).
- A build without `nanosleep` waits whole seconds in the busy timeout (AGENTS.md). Both Mac
  libraries waited in milliseconds (m3-mac, P4).
- On the Mac a load retries a path with `.dylib` appended, and its failure messages are dyld's, cut
  at the path's length plus 298 bytes ([m4-mac](../m4-mac/README.md)).
- On the Mac, `DYLD_LIBRARY_PATH` redirects an absolute path by its leaf name, the library's and an
  extension's alike, where Linux's `LD_LIBRARY_PATH` redirected neither (m4-mac, the run after
  slice 5) (the reference, 420, 462 and 1269–1276).

## 3. What chez-curl did

chez-curl's 0.1.0 was its M8 slice 6, tagged 2026-11-11. 0.1.1 (2026-11-13) and 0.1.2
(2026-11-14) were documentation releases, their libraries unchanged (chez-curl's `CHANGELOG.md`,
lines 9–48). Each item below is marked for us.

### The docs (chez-curl ADR-0038, decision 3; chez-curl's M8 plan, §3.5)

- **A thin README.org in the siblings' order,** 115 lines: a CI badge; an AI disclosure; what it
  is; Status, naming the platforms the suites ran on and "The API may change in any release before
  1.0"; Requirements; Installing, by cloning a release's tag and putting `src` on the library path;
  a taste; the docs' pages; the licence. **Transfers,** but for two parts:
  - **Requirements differs.** chez-curl's floors file names Node, so its list has three lines. Ours
    compares exactly the two floor lines, so what the suites need goes in prose (§2).
  - **The taste differs.** chez-curl's README block names an example file and is held to it. A
    README.org block here is read, never run (§2). **Needs a decision** (Q8).
- **Markdown pages in `docs/`, ELI5:** an index; a quick start; a page per topic; errors; "TLS and
  the environment", which tells how libcurl is found; "What varies by libcurl", 363 lines; the
  hatch; and the reference. 16 pages, 3,547 lines. **Needs a decision** (Q5): the brief names no
  page, and the reference is the only one.
- **A hand-written `docs/reference.md`, held to the exports.** **Transfers, built,** and
  **differs:** chez-curl's check reads no comment, and its review compared the types with the code.
  Ours holds each signature to its comment (AGENTS.md, lines 82–85).
- **Examples run by a test:** `examples/*.sps` run as children against its Node test server, by
  `test-examples`, through a wrapper that prints the native counts, their output held to
  `examples/expected/`. **Differs:** a database needs no server. Our `scheme run` blocks run inside
  `test-docs` on `:memory:`, the counts held at zero, 35 of them in the reference.
- **The docs' rules held by `test-docs`:** block languages, examples, links and anchors by
  GitHub's rule, no link into `.plans/`. **Transfers, built** (§2). Ours also refuses history words
  and dates.
- **The records' promises listed, each kept or marked superseded:** 45 from its survey and 23 from
  M8 (chez-curl ADR-0038, amended 2026-11-08). **Transfers:** our 36 lines (§1).
- **A search of every shipped file for "not yet", "unreleased" and "on main"** before the review.
  **Transfers:** `test-docs` already refuses them in the docs, and two lines outside it are stale
  (§2).
- **A review that read every page against the code,** and planted faults to ask what wrong docs
  pass. It found seven majors that the structural checks had passed (chez-curl's
  `.plans/progress.md`, M8 slice 4's close-out). **Transfers.**

### The 0.1.0 release (chez-curl ADR-0038, decisions 4 and 5, amended 2026-11-10; its M8 plan, §3.6)

- **CHANGELOG.md's `[0.1.0]`:** an intro; Added, by area, each linking its page; and Known
  limitations: the platforms not run, older distributions and the override, what varies by
  version, what isn't supported, and what it doesn't prevent (lines 50–255). Link references close
  the file (257–260). **Transfers.** Ours has the form (§2). Whether our reader takes link
  references wasn't run here; they begin with `[`, and its rules are about lines that begin `#`.
- **`Akku.manifest` at 0.1.0, held to the changelog by `test-manifest`.** **Transfers, built**
  (`test-manifest.sps:549–553`).
- **The release's steps, in order, recorded in the close-out:** the entry dated on the release
  branch; the Mac's `make test` on that branch; the squash merge; `main`'s push run read; the
  squash's tree compared with the tested branch's (`git rev-parse HEAD^{tree}`); a signed,
  annotated `v0.1.0` tag on the squash, made and pushed by the maintainer, or on their ask; CI's
  run on the tag read. **Transfers.** Our `ci.yml` already runs every job on a tag's push, and
  ADR-0004 already asks for the Mac's hand run.
- **The platforms that ran, and no others** (decision 5): Linux amd64 and macOS arm64 claimed;
  Linux arm64 and macOS amd64 named untested. **Transfers** (§5, Q6).
- **No Linux arm64 lane.** At first rejected for its cost and because the repository was private;
  once it was public, GitHub's `ubuntu-24.04-arm` runners were free, and the lane was carried past
  M8 (the amendment of 2026-11-10). chez-curl still has none: all 11 `runs-on` lines in its two
  workflows are `ubuntu-24.04`. **Needs a decision** (Q6).
- **A comment sweep before the tag** (chez-curl's PR #56): every comment in `src/` and `tests/`
  written for a developer, with milestones, slices, research paths and dates gone and a bare ADR
  number kept. It was checked by reading each Scheme file's datums before and after. Test names,
  printed messages and the comments in `scripts/`, the Makefile and `.github/` were left.
  **Needs a decision** (Q7).
- **Nothing more published at 0.1.0:** no GitHub Release, no Akku, nothing left out of the archive,
  each "a later decision of its own" (decision 4, amended). Three of them were decided four days
  later, below.

### After 0.1.0

- **0.1.1** (chez-curl's `.plans/progress.md`, its close-out and PR #58's): the quick start cloned
  `main`, not the tag; README.org's Status named a version; and the docs didn't say to start the
  examples' test server, which of its three addresses to take, or that one example needs a second
  library path. The maintainer found the last two by following the docs on the Mac. A signed tag in
  a public repository isn't moved, so the fix was a release. `test-manifest` then held each
  `git clone` line of README.org and the quick start, one in each, to the manifest's version's tag.
  **Transfers:** our tripwire waits for that check, over README.org and every page of `docs/`, a
  wider reach than chez-curl's two files.
- **0.1.2, by chez-curl ADR-0042:**
  - **A docs site:** circuit's generator (`build-site.sps`, `site/`); chez-cmark-gfm a second
    `depends/dev`, from its locked archive (`make site-deps`); cmark-gfm in the container; a `site`
    job in `ci.yml`, and `pages.yml`, 77 lines, deploying on a `v*` tag with links to repository
    files pinned to the tag; four targets, `site-deps`, `site`, `check-site` and
    `check-site-deps`. **Needs a decision** (Q1). It **differs** in what it would cost here:
    `check-ci.sh` refuses a second workflow and holds `permissions` line for line; `test-manifest`
    holds `depends/dev` to chez-srfi alone and `Akku.lock` to one project; ADR-0007 names
    chez-srfi the only development dependency; and ADR-0006's container would gain cmark-gfm.
  - **A GitHub Release for every tag:** titled by the tag message's subject, made from the tag with
    `--verify-tag` as a draft, its notes the CHANGELOG entry as the tag holds it, the stored body
    read back byte for byte, then published (decision 8). `v0.1.0`'s and `v0.1.1`'s were made
    afterwards. **Needs a decision** (Q2). It changes nothing in the tree.
  - **Archives without `.plans/` and `AGENTS.md`,** by `.gitattributes` `export-ignore`, each tag's
    tarball listed to check it (decision 9). v0.1.2's held 933 entries, where v0.1.1's held 3,822
    under `.plans/` alone (the 0.1.2 close-out). `v0.1.0`'s and `v0.1.1`'s keep both for good.
    **Needs a decision** (Q3).
  - **Akku stays out:** "a publish cannot be taken back" (decision 10). **Needs a decision** (Q4).
    Our `Akku.manifest` has no `depends` and no `scripts` already.

## 4. What chez-curl's follow-ups teach our 0.1.0

Each follow-up fixed something its tag had fixed in place. Done before our tag, none is needed:

1. **Hold every clone line to the tag** (0.1.1). The tripwire becomes the check: each `git clone`
   line of README.org and `docs/` clones `v` and the manifest's version. A release then bumps the
   manifest, the changelog and the clone lines together, or fails.
2. **Name no version in the Status** (0.1.1), so the next release can't leave it stale.
3. **Walk the docs as a reader, on Linux and on the Mac, before the tag.** chez-curl's lesson:
   "walk run instructions as a reader would, and try the plausible wrong picks" (the close-out of
   chez-curl's PR #58). Ours has no server to start, but a reader still meets the clone of the tag, the
   library path, Homebrew's Chez named `chez` (chez-curl's `docs/quickstart.md`), Homebrew's SQLite
   reached by the override alone (ADR-0002), and Apple's library without extension loading.
4. **Decide the site, the Releases and the archives before the tag** (0.1.2). A tag fixes each: a
   run of `pages.yml` by hand takes the tag's own workflow files, so a tag without one can't deploy
   (chez-curl ADR-0042, its rejected options); an archive follows its tag's `.gitattributes`; and a
   Release made later is made for an old tag.
5. **If there is a site, set Pages and its `github-pages` environment's `v*` rule before the tag.**
   Creating Pages through the API made the environment take `main` alone, and the tag's deploy
   needed the rule added (the 0.1.2 close-out).
6. **If there are Releases, read the body once published.** A draft's links name `untagged-…`, and
   each newline renders as a line break, so the entry renders as wrapped (chez-curl ADR-0042,
   decision 8).
7. **Expect the gate's timing to break on slow runners, with no code changed.** 0.1.1's CI took
   three attempts. `test-transaction-interrupt`'s 318 s, open when this note was written, is
   settled (progress.md). The memory jobs' totals are not: `memory-1` took 42, then 44, of its
   60 minutes on the last two runs (§8, Q9).
8. **Hold the changelog to the suites, not to the docs it sums up** ("a summary inherits its
   sources' overreach", the 0.1.0 close-out), and date a record by the commits' local day, never
   CI's UTC day.

## 5. Platform claims for the README

**Measured:**

- **Linux x86_64, in CI:** six jobs on `ubuntu-24.04`, all required, whose library is
  `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0` ([ci-runner](../ci-runner/README.md), line 28). Chez
  10.4.0, built from its tarball. The suites run against:
  - Ubuntu 24.04's 3.45.1, found by discovery, in `main`, and under Valgrind in `memory-1` and
    `memory-2`;
  - 3.45.1 built from SQLite's source with its defaults, in `floor`;
  - 3.54.1 built from source, in `current` (`scripts/ci/build-sqlite.sh`, line 86), and, since
    M4's closing review, 3.54.1 built again without extension loading, in the same job;
  - and `nothreads` holds that a Chez built without threads is refused.
- **Linux x86_64, the Guix container:** Chez 10.4.0 and Guix's SQLite 3.53.1, in every slice's
  `make test` (ADR-0006; m4-prework's header).
- **macOS 26.7.1 on arm64,** by the maintainer's hand runs, with Homebrew's Chez 10.4.1
  (`tarm64osx`), Apple's 3.51.0 found by discovery, and Homebrew's 3.54.1 through the override:
  - M1's measurements and runs ([mac-d7](../mac-d7/README.md); progress.md, lines 93–117);
  - M2's, on an arm64 Mac whose macOS version the ledger doesn't give (progress.md, lines
    131–145);
  - M3's whole `make test`, its eight failing suites faults in the tests, fixed in PR #30 and
    passing on a rerun ([m3-mac](../m3-mac/README.md));
  - M4's pre-work Mac step and two load runs (m4-prework; [m4-mac](../m4-mac/README.md));
  - M4's three `make test` runs, each with both libraries: after slice 2, 75 of 75 (PR #43);
    after slice 5, Homebrew's 81 of 81 and Apple's 80, its one fault a row of the suites, fixed in
    PR #47; and after the closing review, 92 of 92 with each (PR #49), the timer's probes printing
    what Linux's Chez 10.4.0 prints (m4-mac).

**Not measured:**

- **Linux arm64.** No run. That a binding without `__varargs_after` works there is chez-curl's
  measurement, not ours (ADR-0001, amended; the M4 plan, §7). Discovery's `aarch64-linux-gnu`
  directory (ADR-0002, decision 2) has never been reached.
- **macOS 14 and 15.** Brief D7 leaves them unmeasured. Their SQLite is "believed 3.43.x", below
  the floor, so discovery would refuse it as `below-floor`, with the override as the remedy (brief
  §2.2; ADR-0002's consequences; ADR-0003's table).
- **macOS on amd64.** No record names a run. D7 doesn't list it, though AGENTS.md promises it.

**Promised:** Linux and macOS, on amd64 and arm64; Windows not supported (AGENTS.md, lines 12–14;
ADR-0004). No macOS CI runner: CI is Linux only (AGENTS.md, line 15). A Linux arm64 runner, such
as GitHub's `ubuntu-24.04-arm`, is still Linux, so that rule doesn't bar one. It would be a seventh
job, though, and `check-ci.sh`'s six-job shape and the six required checks would change with it
(ADR-0005, amended). chez-curl found those runners free in a public repository (chez-curl
ADR-0038, amended 2026-11-10), and this one is public too (`gh repo view`, read 2026-11-17).

So the README can say what chez-curl's says: the suites run on Linux x86_64 and macOS arm64,
naming the SQLites on each; Linux arm64 and macOS amd64 haven't run them; Windows isn't
supported. "Supported" stays ADR-0004's aim (Q6).

## 6. What M4 settled

This section first listed what the M5 plan had to wait for. M4 is done: its five slices, the
close fix, its three Mac runs with the one fix they needed, and its closing review are merged,
the last as PR #48, `79fa1ac` (the M4 plan, §6; progress.md). What each wait came to:

- **The exports:** 70, adding `load-extension!` (slice 4) and `sqlite-extensions-unavailable?`
  (slice 3). The reference holds one entry each (§2), and the changelog's Added follows them.
- **The reference's text:** the four settings and their starts by library, under `#### Settings`
  (110), Apple's `defensive` among them; the Extensions section (379); the new condition (1697);
  and checking for FTS5 in The library (1344–1350).
- **The Makefile and the workflow:** `check-variadic` runs in `main`'s step (`ci.yml`, 168–174);
  `current` builds and runs a library without extension loading (§2); the new suites are in the
  shard lists (`MEMORY_SUITES_1` at `Makefile:78`, `MEMORY_SUITES_2` at 127). Still six jobs, and
  still `ci.yml` alone, so a site or a Linux arm64 job changes `check-ci.sh` first.
- **Where FTS5 is:** on the `current` lane, not on `floor` (slice 5; ADR-0003, amended
  2026-11-17). Both Mac libraries have it: `test-fts5` passed 19 with each (m4-mac).
- **The Mac's facts for the docs,** from the run after slice 5 (m4-mac): Apple's library refused
  the opt-in by `&sqlite-extensions-unavailable`, `test-load-extension` asserting it in place of
  the load rows; Homebrew's loaded the suites' extension as a `.dylib`; and `DYLD_LIBRARY_PATH`
  redirects a load by its leaf name, which the maintainer chose to document ("Document it",
  ADR-0002, amended), and the reference now does (§2).
- **The closing review** amended ADR-0002, ADR-0005, ADR-0010, ADR-0016 and ADR-0021
  (`git show --stat 79fa1ac`). §9 reads the reference against the records as they now stand.

No M4 commit touched README.org, CHANGELOG.md, `Akku.manifest` or `tests/test-manifest.sps`
(§2), as the M4 plan's file lists said.

## 7. Questions for the maintainer

Each is one decision, its recommended option first. "The M5 record" is a new ADR of M5's scope,
as chez-curl ADR-0038 and ADR-0042 are for chez-curl.

**Q1. A docs site at 0.1.0.** chez-curl cut 0.1.2 to deploy one, since an older tag couldn't (§3,
§4 item 4). Settles: the M5 record, amending ADR-0005 (the workflow's shape), ADR-0006 (the
container) and ADR-0007 (a second development dependency).

- **A site from v0.1.0, copied from chez-curl's (recommended):** a `site` job, `pages.yml`,
  chez-cmark-gfm and cmark-gfm, four targets, and Pages set before the tag; no release follows for
  it.
- **No site; GitHub renders `docs/`:** no workflow changes now, and a later site can deploy only
  from a later tag, a release of its own.

**Q2. A GitHub Release for each tag.** chez-curl made its first two afterwards (chez-curl
ADR-0042, decision 8). Settles: the M5 record.

- **For every tag from v0.1.0, by chez-curl's recipe (recommended):** made on the host with `gh`
  after the tag, its notes the tag's CHANGELOG entry, read back byte for byte; nothing in the tree
  changes.
- **The tag alone:** the Releases page stays empty, and a later change of mind makes Releases for
  old tags.

**Q3. What a release archive leaves out.** 791 of the 1,218 tracked files are under `.plans/`, and
a tag fixes its archive (§2). Settles: the M5 record.

- **`.plans/` and `AGENTS.md`, by `.gitattributes`, from v0.1.0 (recommended):** the archive holds
  the library, its docs and its tests; it was never a test tree, and `test-conventions` needs
  `.plans/` besides.
- **Nothing:** v0.1.0's archive carries every record for good, and a later `.gitattributes` reaches
  later tags alone.

**Q4. Akku.** `Akku.manifest` is ready, with no `depends` and no `scripts`, and names 0.0.0 "until
the first release". Settles: the M5 record.

- **Not at 0.1.0 (recommended):** installing is a clone of the tag; the manifest's 0.1.0 is for
  `test-manifest`; publishing stays a later decision, as chez-curl ADR-0042, decision 10, has it.
- **Published from the v0.1.0 tag:** `akku publish` from a fresh clone at the tag, signed with the
  release key and its signature checked (chez-curl's docs survey, §5), and an `.akkuignore`; a
  publish can't be taken back.

**Q5. The pages of `docs/`.** The brief names none but the reference, and the reference says
nothing of installing, of finding SQLite, or of any library by name (§2). Settles: the M5 record.

- **Four: a quick start, finding SQLite, what varies by library, and the reference
  (recommended):** each linked from README.org, as `test-docs` requires; their facts are measured
  already (§2's last list).
- **The reference alone:** README.org tells installing and finding SQLite, and what varies by
  library has no page.
- **chez-curl's shape, a page per topic beside the reference:** about a dozen pages, much of them
  restating the reference's 1,707 lines, each to be held and reviewed.

**Q6. The platforms 0.1.0 claims.** Linux arm64, macOS amd64, and macOS 14 and 15 have never run
the suites (§5). Settles: the M5 record, as chez-curl ADR-0038's decision 5, and ADR-0005 if a job
is added.

- **What ran (recommended):** Linux x86_64 and macOS arm64, with their SQLites; the rest named as
  not run in the README and the changelog's Known limitations; ADR-0004's aim stands, CI unchanged.
- **A Linux arm64 job before the tag:** a seventh job, so `check-ci.sh` and the required checks
  change; discovery's `aarch64` directory and the variadic binding run on Linux arm64 for the first
  time; free, as chez-curl found them, since the repository is public.
- **A hand run on a Linux arm64 machine:** the claim rests on one run, as the Mac's do; no record
  names such a machine.

**Q7. A comment sweep before the tag.** 165 lines in 22 of `src/`'s 30 files carry the build's
history, by a crude search, and 1,048 lines in 94 of `tests/`' 120 (§2). Settles: the M5
record; chez-curl recorded its sweep in its ledger alone.

- **The comments of `src/` and `tests/`, before the tag (recommended):** one PR, checked by
  reading each Scheme file's datums before and after, as chez-curl's PR #56 was; the signature
  comments `test-reference` holds stay character for character, and so do the ADR citations
  `test-conventions` checks (`tests/test-conventions.sps`, from line 246).
- **No sweep:** the release's comments keep the build's history, and nothing else changes.

**Q8. An example in README.org.** `test-docs` runs Markdown's `scheme run` blocks alone, so a
Scheme block in README.org is read, never run (§2). Settles: the M5 record.

- **A fragment in README.org, held equal to a `scheme run` block in `docs/` (recommended):** one
  new `test-docs` rule, watched failing; the README's example runs through its twin.
- **No example in README.org:** it links a page's instead, and nothing new is checked.
- **`examples/*.sps`, run by a new suite, as chez-curl's:** a suite, a wrapper for the native
  counts and expected outputs, for programs that need no server.

**Q9. The memory jobs' margin.** A tag's push runs every job, and on the last two runs
`memory-1` took 42 and 44 of its 60 minutes (§8). Each suite is bounded already: `test-memory`
fails one past 450 s as `SLOW`, and stops one at `MEMORY_TIMEOUT`'s 600 s (ADR-0005, amended).
Only the job's `timeout-minutes` bounds a shard's sum. Settles: ADR-0005, amended, which left
the margin to be read from the first runs (line 822).

- **A longer `timeout-minutes` for `memory-1` and `memory-2`, such as 120 (recommended):** two
  lines of `ci.yml`. `check-ci.sh` holds only that the value is a whole number (581–582 and 784),
  so its suite stands. Each suite keeps its own bounds, so a hang still ends as `HUNG`, inside the
  job. A slow runner's run takes longer to read.
- **A third shard, `memory-3`:** each shard about two thirds of today's. A seventh job, so
  `check-ci.sh`'s six-job shape, `check-memory-shards`, the Makefile's shard lists and branch
  protection's required checks all change, and M3 slice 6's split is redone for three.
- **Split the heaviest suites:** it moves time between the shards, never their sum, and which
  shard was heavier changed between the three runs (§8).
- **Leave it:** a job that times out is rerun by hand. chez-curl's 0.1.1 took three attempts on
  CI with no code changed (§4).

**Q10. The tag's signature.** chez-curl's three tags are each annotated and signed with a PGP key
(`git cat-file -p v0.1.0` in its clone, read 2026-11-19), "by the release key" in its records. No
record here names a key. Settles: the M5 record's release steps.

- **Signed with the key that signs chez-curl's tags (recommended):** the maintainer makes and
  pushes the tag, as chez-curl's were; `git tag -v v0.1.0` is read before the push.
- **Annotated, unsigned:** no key is needed, and a signature can't be added to a tag once it is
  pushed without moving the tag.

## 8. What the refresh ran

On 2026-11-19, at `main` `79fa1ac`, on Guix's 3.53.1 and Chez 10.4.0, inside `scripts/guix-env`.
Each folder was under `build/` of the checkout, since the container sees nothing else, and was
removed afterwards.

**A program runs against a bare archive's `src`.** `git archive` of `79fa1ac`, unpacked into an
empty folder, its `vendor/chez-srfi` empty, nothing built. In another folder, this program:

```scheme
(import (rnrs) (chez-sqlite3))
(call-with-database ":memory:"
  (lambda (db)
    (execute! db "create table t (x)")
    (execute! db "insert into t values (42)")
    (write (query-row db "select x from t"))
    (newline)))
```

`$CHEZ --libdirs ARCHIVE/src --program app.sps` printed `#(42)` and exited 0, with
`CHEZ_SQLITE3_LIBRARY` unset and with it set. Unset, discovery found the profile's library, its
source `guix-environment`; set, the source was `override`. So installing needs no `make`, no
submodule and no build: the library is its `src`. Not run: a clone of a real tag (none exists),
Ubuntu's discovery outside CI, and the Mac. §4's item 3, the walk as a reader, still owes those.

**The changelog reader takes link references.** In that archive, CHANGELOG.md was given a
`## [0.1.0] - 2026-11-20` entry and two link references closing the file, `[Unreleased]: …` and
`[0.1.0]: …`, and `Akku.manifest` 0.1.0. `test-manifest` passed 79 of 79. With the manifest left
at 0.0.0, it failed one row, by name: "Akku.manifest's version is CHANGELOG.md's latest release, or
0.0.0 with none", expected `"0.1.0"`, actual `"0.0.0"`. A link reference begins `[`, and
`section-headings` judges only lines that begin `#` (`tests/test-manifest.sps`, 247–262).

**The memory jobs' times on CI,** the first four runs with M4's closing review's suites and
shards. A job's time is the API's start to end; its suites' time is the sum of its log's
`time: Ns under the gate` lines.

| Run | At | `memory-1` | its suites | `memory-2` | its suites | Slowest suite |
|---|---|---|---|---|---|---|
| 44460844478 | `a323224`, PR #48 | 31 min | 1,507 s | 35 min | 1,763 s | 161 s |
| 44544215035 | `3090e3e`, PR #48 | 28 min | 1,408 s | 36 min | 1,714 s | 151 s |
| 44555738428 | `79fa1ac`, `main`'s push | 42 min | 2,117 s | 32 min | 1,605 s | 177 s |
| 44658201510 | `02429fc`, PR #49 | 44 min | 2,237 s | 33 min | 1,612 s | 195 s |

- The slowest suite was `test-open-db-config-engines` or `test-conveniences-pending-script-odd`,
  each under half the 450 s `SLOW` line.
- A job spent about 5 to 8 minutes beyond its suites, 285 to 457 s.
- `memory-1`'s suites took 1,408 to 2,237 s, 1.6 to one, over the same suites: `3090e3e`'s and
  `79fa1ac`'s trees are the same (`git rev-parse` of each `^{tree}`), and `02429fc` changed only
  `.plans/`. The heavier shard changed between runs.
- CI's runners differ about two to one (AGENTS.md). `memory-1` at twice its fastest sum here takes
  about 54 minutes, and at twice its slowest about 81, past its 60-minute timeout (Q9).

**chez-curl** was still at `fa9750d` on GitHub, its tags `v0.1.0` to `v0.1.2`, each annotated and
signed with a PGP key (Q10).

## 9. The records' promises to the reference

Each of the 36 lines of §1, and every other line of `.plans/decisions/` that promises what the
reference says, was read against `docs/reference.md` at `79fa1ac`, by an Opus reviewer, read-only.
The lead read each verdict that isn't plainly kept against both files. Whether the reference is
true of the code wasn't asked: that is M5's docs review.

- **Of the 36:** 32 kept; 3 partly kept; 1 superseded, its replacement kept (ADR-0017's deferred
  write, which now fails at once "once it has read", reference 719).
- **Beyond the 36:** 5 more kept. ADR-0019's busy remedies (line 313), ADR-0002's
  `DYLD_LIBRARY_PATH` under Which SQLite (304), ADR-0021's load message (467–468), an extension's
  leftover statement refusing the close (329), and an extension's path redirect (460). None names
  the file, so a grep for it misses them: they say "the docs", "the reference" (once split
  across a line), "Extensions entry" or "Document it".

**The three partly kept,** each a gap M5's docs slice closes:

- **ADR-0014, line 301:** the reference says a read's out-of-memory can end a transaction, at the
  next reset or finalize (1141–1144). It never says a step's can. Its list of failures that end a
  transaction (753–756) names `insert or rollback`, a full disk and an interrupted write.
- **ADR-0016, line 349:** of three things the per-call guard doesn't cover, the reference tells
  two (502–504). The third, an expiry past the fold's last step whose resume answers the fold, is
  missing, and the reference's "the resumed fold raises a closed condition" (595–597) reads as if
  every expiry raises.
- **ADR-0018, line 175:** "a list that sets `journal-mode` can't open `:memory:`". The reference
  shows `wal` alone, with its reason (142–143). All four values the list takes mismatch there:
  `delete`, `truncate`, `persist` and `wal` each read back `memory`, run for this note.

**Wording to check against the code in M5's review,** each outside a promise's verdict:

- ADR-0012 (306–310) says a failed close at an expiry leaves the caller "no engine active" and the
  connection open; the reference (295–297) says the error "is raised out of the engine, and the
  engine is lost".
- ADR-0017 (422) says a failed rollback at an expiry gives the caller an assertion violation; the
  reference (808–812) says Chez's own error, "no engine active".
- ADR-0018 (71 and 167) says `journal_mode = wal` fails at once "under a reserved lock"; the
  reference's table (204–212) says when the other connection "is in `begin immediate` and has
  written".

## What the files couldn't settle, and where it stands

- **Whether the install line runs from a fresh clone of a tag,** `scheme --libdirs …/src --program
  app.sps`, as chez-curl's does: it runs from a bare archive of `main` on Linux, needing no build
  (§8). A real tag's clone, and the Mac, wait for §4's walk as a reader. `make dev` is no install
  step: it puts the suites' libraries on the path too, after `make build` (`Makefile:275`).
- **The release key.** chez-curl's tags are signed "by the release key"; no record here names one
  (Q10).
- **Whether each of the 36 reference promises is kept** (§1): 32 are, 3 partly, and 1 was
  superseded, its replacement kept (§9). **Whether our changelog reader takes link references**
  (§3): it does (§8).

## Not done

- At first no command but reading ran. The refresh ran §8's commands, read CI's logs and
  chez-curl's head through `gh`, and changed no file outside this note and the ledger.
- No M5 slice is designed. By what they would cover, the likely ones are: the docs (the pages,
  README.org, and §9's three gaps); the release (the changelog's entry, the manifest, the
  clone-line check, the tag, and what Q2 to Q4 and Q10 add); and, by the answers, a site, a
  comment sweep, a Linux arm64 job or Q9's remedy, each a PR of its own.
