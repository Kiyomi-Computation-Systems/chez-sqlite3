# ADR-0022: The first release: four pages and a site, a signed tag and its Release, what ran

- **Status:** Proposed in M5 slice 0 ([the M5 plan](../2026-11-20-m5-plan.md), §4). Built on the
  maintainer's answers of 2026-11-20 to the pre-work's ten questions, each the recommended option
  ([research/m5-prework/](../research/m5-prework/README.md#the-maintainers-answers-2026-11-20)):
  decision 4's site, "Site from v0.1.0" (Q1); decision 5's Releases, "Every tag from v0.1.0"
  (Q2); decision 6's archive, "Exclude .plans/ and AGENTS.md" (Q3); decision 7, "Not at 0.1.0"
  (Q4); decision 2's pages, "Four pages" (Q5), and its README example, "Fragment held to a docs
  twin" (Q8); decision 8's claim, "What ran" (Q6); decision 9's sweep, "Sweep src/ and tests/"
  (Q7); decision 10's timeout, "timeout-minutes 120" (Q9); decision 1's signature, "Signed with
  chez-curl's key" (Q10); decision 2's home page, "The quick start is home" (the plan's Q11).
- **Date:** 2026-11-20
- **Scope:** chez-sqlite3 M5, the release: the docs, the site, the archive, CI's margin, the
  comments, and v0.1.0 with its Release
- **Settles:** brief §6's M5; the harness plan's owed check of install instructions (its §6, slice
  2)
- **Related:** [ADR-0004](0004-windows-not-supported.md) (the platforms) ·
  [ADR-0005](0005-memory-gate.md) (the workflow's shape, the memory jobs) ·
  [ADR-0006](0006-pinned-guix-container.md) (the container) ·
  [ADR-0007](0007-test-harness-and-scheme-dependencies.md) (the dependencies, `test-manifest`) ·
  [ADR-0008](0008-floors-have-one-source.md) (the floors) ·
  chez-curl ADR-0038 and chez-curl ADR-0042, which this follows ·
  [research/m5-prework/](../research/m5-prework/README.md)

## Context

Read on `main` at `79fa1ac`, after M4, by the pre-work, and at `95d0cc1` by the plan:

- **The library is finished:** 70 exports, each with its entry in `docs/reference.md`, 1,707
  lines, which `test-reference` holds to the signature comments, and whose 38 `scheme run`
  blocks `test-docs` runs. The records make 36 promises to the reference: 32 kept, 3 partly, 1
  superseded and its replacement kept (pre-work §9).
- **Nothing else a release needs is written:** README.org is 15 lines and "in development";
  CHANGELOG.md holds an empty `[Unreleased]`; `Akku.manifest` names 0.0.0; there is no tag, no
  `.gitattributes`, and no page but the reference. `test-manifest` trips on any `git clone` line,
  "no clone-line check exists yet, so none may be written" (pre-work §2).
- **A program runs against a bare archive's `src`,** its submodule empty and nothing built, with
  the override and by discovery (pre-work §8). So installing needs no build.
- **The suites have run on Linux x86_64,** in CI on Ubuntu 24.04's library, the floor and 3.54.1
  built from source, and 3.54.1 without extension loading, and in the container on Guix's
  3.53.1; **and on macOS arm64,** by the maintainer's hand, on Apple's 3.51.0 and Homebrew's
  3.54.1, 92 of 92 with each after M4's closing review. **Never on Linux arm64, on macOS amd64,
  or on macOS 14 or 15** (pre-work §5).
- **The memory jobs near their limit:** `memory-1` took 42 and 44 of its 60 minutes on two runs,
  and 42 min 38 s on PR #50's, its suites' sum 1.6 to one over the same tree; CI's runners differ
  about two to one (pre-work §8).
- **The comments carry the build's history:** a crude search for slices, milestones, research
  paths, `traps.md` and "the maintainer" matches 165 lines in 22 of `src/`'s 30 files, and 1,048
  in 94 of the top of `tests/`' 120 (pre-work §2).
- **A source archive would carry the records:** 802 of 1,229 tracked files are under `.plans/`,
  at `95d0cc1`. `git archive` reads `export-ignore` from the tree it archives (the M5 plan, P1).
- **chez-curl released 0.1.0 as a tag alone,** then cut 0.1.2 to deploy a site an older tag
  couldn't, made Releases for its first two tags afterwards, and left the records out of its
  archives from 0.1.2 on (chez-curl ADR-0038, amended; chez-curl ADR-0042). Its 0.1.1 fixed a quick
  start that cloned `main` and a Status that named a version (pre-work §3 and §4).

## Decision

1. **v0.1.0 is a signed, annotated tag** on the squash of the release's PR, made, signed and
   pushed by the maintainer with the release key that signs chez-curl's tags. `git tag -v v0.1.0`
   is read before the push (Q10).
2. **The docs are four pages and a thin README.org** (Q5):
   - `docs/` holds a quick start, finding SQLite, what varies by library, and the reference, each
     linked from README.org, as `test-docs` requires. The quick start is the site's home, with
     no index page (the plan's Q11);
   - README.org follows the siblings' order: what it is, the AI disclosure, Status, Requirements,
     Installing, a taste, the pages and the site, the licence. Its Status names the platforms and
     the libraries the suites ran on, and those they haven't, and no version;
   - **its one Scheme block is a twin** (Q8): a new `test-docs` rule holds each Scheme block of
     README.org equal, line for line, to the whole of a `scheme run` block of a page, so it runs
     through its twin;
   - **no page restates a floor:** `check-floors` reads `docs/` and README.org beyond its
     Requirements ([ADR-0008](0008-floors-have-one-source.md), amended);
   - the reference closes the three gaps of the pre-work's §9, and is read against the code by a
     review that plants faults in the pages.
3. **Installing is a clone of the tag,** with its `src` on Chez's library path and nothing built.
   Every `git clone` line of README.org and of any file under `docs/` names the manifest's
   version's tag, or, at 0.0.0, no branch; `test-manifest` holds it, in place of the tripwire
   ([ADR-0007](0007-test-harness-and-scheme-dependencies.md), amended).
4. **A docs site on GitHub Pages from v0.1.0** (Q1), copied from chez-curl's, itself circuit's:
   - the generator, `build-site.sps` and `site/`, its suites and `check-site`, and four targets,
     `site-deps`, `site`, `check-site` and `check-site-deps`. The generator imports nothing under
     `src/`, and its suites import `(site-testing)`, so both run on Ubuntu's Chez, below the
     floor;
   - chez-cmark-gfm, a second `depends/dev`, from its locked archive (ADR-0007, amended); and
     cmark-gfm in the container (ADR-0006, amended);
   - a seventh CI job, `site`, and a second workflow, `pages.yml`, which deploys on a `v*` tag's
     push; `check-ci` holds `ci.yml`'s shape and `pages.yml` line for line (ADR-0005, amended);
   - Pages is on, built from GitHub Actions, and its `github-pages` environment takes `main` and
     `v*`, set before the tag, so v0.1.0's push deploys the first site, its links to repository
     files naming `blob/v0.1.0/`.
5. **A GitHub Release for every tag from v0.1.0** (Q2), made on the host with `gh` after the tag
   is pushed, by chez-curl ADR-0042's decision 8: from the tag with `--verify-tag`, first as a
   draft; titled by the tag message's subject; its notes the tag's CHANGELOG entry as the tag
   holds it, intro to last bullet; the stored body read back and compared byte for byte, then
   published, then read again. Nothing in the tree changes.
6. **A release archive leaves out `.plans/` and `AGENTS.md`** (Q3), by a `.gitattributes` marking
   both `export-ignore`, which `test-manifest` holds, written before the tag. Each tag's archive
   is listed after its push.
7. **No Akku publish at 0.1.0** (Q4): `Akku.manifest`'s 0.1.0 is for `test-manifest`; publishing,
   and `.akkuignore`, stay a later decision, as chez-curl ADR-0042's decision 10 has it.
8. **0.1.0 claims what ran** (Q6): Linux on x86_64 and macOS on arm64, with their SQLites. Linux
   on arm64, macOS on amd64, and macOS 14 and 15 are named as not run, in README.org and the
   changelog's Known limitations. ADR-0004's aim stands, and no job is added
   ([ADR-0004](0004-windows-not-supported.md), amended).
9. **The comments of `src/` and `tests/` are swept before the tag** (Q7), in one PR, as
   chez-curl's PR #56 was:
   - milestones, slices, plan sections, reviews as provenance, research and build paths, pointers
     to `traps.md` and AGENTS.md, dates, "the maintainer", the Mac as a machine, and a citation's
     "amended …" and "decision N" go; a bare `ADR-NNNN` stays, as a pointer to why;
   - strings and data stay, test names and messages among them; so do the signature comments
     `test-reference` holds, character for character, and the convention table's citations,
     which are strings;
   - `tests/fixtures/` isn't swept: a fixture's comment can be a row's input;
   - every edited Scheme file reads as the same datums as before; every changed line of a shell
     file is a whole-line comment; every C file compiles to the same code. Each check is watched
     failing first.
10. **`memory-1` and `memory-2` take `timeout-minutes: 120`** (Q9). Each suite keeps its own
    bounds, and `check-ci` holds a whole number there (ADR-0005, amended).
11. **CHANGELOG.md's `[0.1.0]` entry,** in Keep a Changelog's form: an intro; Added, by area,
    linking each page; Known limitations, the platforms not run, the systems that need the
    override, what varies by library, what v1 leaves out, and what it doesn't prevent; link
    references closing the file. It is dated by the release branch's local day, and held to the
    suites, not to the docs it sums up. `Akku.manifest` names 0.1.0 and the clone lines its tag,
    so `test-manifest` fails a release that moves one alone.
12. **The release's steps, in order,** each recorded in its close-out: CI on the release branch;
    the Mac's `make test` there, with Apple's library and Homebrew's; the squash merge; `main`'s
    push run read; the squash's tree compared with the branch's; Pages' settings read; the tag;
    the tag's CI and Pages runs read; the site checked live, the check watched failing before the
    deploy; the Release; the tag's archives listed; the README's clone line run verbatim (the M5
    plan, §4.9).

### Rejected

The answers' other options, each weighed in the pre-work's §7:

- **No site, with GitHub rendering `docs/`** (Q1): a later site deploys only from a later tag, a
  release of its own, as chez-curl's 0.1.2 was.
- **The tag alone, with no Release** (Q2): a later change of mind makes Releases for old tags.
- **An archive with everything** (Q3): v0.1.0's carries every record for good, since a tag fixes
  its archive.
- **An Akku publish from v0.1.0** (Q4): a publish can't be taken back.
- **The reference alone,** and **a page per topic, as chez-curl's** (Q5): the first leaves
  installing and the libraries' differences to README.org or to nothing; the second restates much
  of the reference's 1,707 lines, each page to be held and reviewed.
- **A Linux arm64 job before the tag,** and **a hand run on a Linux arm64 machine** (Q6): a
  seventh job of its own, changing the required checks, or a claim resting on a machine no record
  names.
- **No sweep** (Q7): the release's comments keep the build's history.
- **No example in README.org,** and **`examples/*.sps` run by a suite** (Q8): the first shows a
  reader nothing; the second needs a suite and a wrapper for programs no server needs.
- **A third memory shard,** **splitting the heaviest suites,** and **leaving it** (Q9): a seventh
  job and a new split; time moved between the shards, never their sum; a rerun by hand on a slow
  runner.
- **An annotated, unsigned tag** (Q10): a signature can't be added once the tag is pushed without
  moving it.

And the plan's own:

- **An index page, `docs/README.md`, as the siblings have** (the plan's Q11): a fifth file, and a
  second list of the pages beside README.org's, with nothing holding the two in one order.

- **Clone lines naming `v0.1.0` before the release slice:** they would name a tag that doesn't
  exist, on `main`, until the release. At 0.0.0 they name no branch, as the version's own rule
  reads 0.0.0 as no release.
- **The site's packages in `packaging/debian-prereqs.txt`:** Ubuntu's Chez would be installed
  beside the Chez every other job builds.
- **`pages.yml` held by `ci.yml`'s rules:** they refuse `needs:`, a job's own `permissions:` and
  `environment:`, and the Pages actions, each of which it needs.
- **A first deploy from `main`, by hand:** its links would name `blob/main/`, which moves
  (chez-curl ADR-0042, Rejected).
- **Decision numbers kept in the swept comments:** chez-curl's sweep, which Q7's answer names,
  kept a bare ADR number alone.

## Consequences

- **A pull request runs seven jobs,** `site` among them, required by branch protection; chez-curl's
  took about 43 s.
- **The container gains cmark-gfm, tar and xz,** and exports `CHEZ_CMARK_GFM_LIBS`; the site's
  dependency is fetched on the host, or in CI, never in the container.
- **Two copies of GitHub's anchor rule,** `test-docs`' and the site's, each held to give GitHub's
  anchor for every heading of `docs/`, as chez-curl measured its own.
- **A release archive is no test tree:** no `.plans/`, which `test-conventions` reads, and an empty
  submodule, which `make deps` refuses. The suites run from a clone. A released comment's
  `ADR-NNNN` names a record in the repository, not in the archive.
- **A release moves three things together,** the manifest, the changelog's entry and the clone
  lines, or `test-manifest` fails it.
- **A page names the floor by a link to README.org's Requirements,** and a library whose version
  is a floor's text by whose library it is.
- **The release's steps gain four of chez-curl's 0.1.2:** read the Pages run, check the site live,
  make the Release and read it back, list the archives.
- **ADR-0004, ADR-0005, ADR-0006, ADR-0007 and ADR-0008, and the brief's §6,** are amended in the
  same slice.
