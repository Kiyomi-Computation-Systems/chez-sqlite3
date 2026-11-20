# M5 slice 2 mutation log

Evidence that each rule slice 2's checks claim to guard fails through the property it names
([the M5 plan](2026-11-20-m5-plan.md) §5, slice 2, §4.3, §4.5, §4.6 and §4.10's slice 2 items;
probe P4, §8). Format of [the M4 slice 5 log](m4-slice-5-mutation-log.md).

An Opus agent built the slice from the lead's brief, in its worktree, on `m5-slice-2` from slice
0's head `fb4e183`, beside slice 1 in a session of its own. Builds and suites ran in the Guix
container: Chez 10.4.0 (`ta6le`, threaded), x86_64, cmark-gfm 0.29.0.gfm.13 once the manifest
gained it. `make site-deps`, `make check-guix`, `make check-pins` and the GitHub fetch for P4 ran
on the host. The drivers are in [research/m5-slice-2/](research/m5-slice-2/); their logs were
written under the worktree's `build/m5s2/`, and their results are quoted here.

## What the slice adds

- **The generator, copied from chez-curl's** at `fa9750d`: `build-site.sps`, `site/`'s eight
  libraries and stylesheet. Changed: the names (the wordmark, the meta description and keywords,
  the stylesheet's header); the blob URL, `.../chez-sqlite3/blob/`; the nav; and Q11's home rule:
  - `(site pages)`: `pages` is README.org's list, the home its first; `page-file-name` writes the
    first as `index.html`, where chez-curl's tested for `README.md`. Today it holds one entry,
    `("reference.md" . "API reference")`, README.org's one link to `docs/` and its label;
  - `(site links)`: a `.md` link is written as `page-file-name` names its page, so a link to the
    home is rewritten to `index.html`; chez-curl's rewrote `README` by name;
  - `(site render)`: the nav is `pages` whole, the home among them. chez-curl's left
    `README.md` out of the nav; here the home is a page of the docs, and with one page the nav
    would be empty without it. `neighbors` takes the nav and is exported, so its order is
    tested on a fixture nav whatever `docs/` holds.
- **The suites, copied and adapted:** `tests/site-testing.sls`, `tests/test-site-testing.sps`
  (importing `(chez-sqlite3-testing)`), `tests/site-unit.sps`, `tests/site-render-unit.sps`.
  - Every row that named `README.md` as the home now reads the home from `pages`, and names
    fixture pages docs/ never holds (`handlers.md`, `bodies.md`, `guide.md`). New rows: a link to
    `README.md` is no page's, written `README.html` and dangling; the home's nav entry links
    `index.html`, marked on the home page; GitHub's anchors from this repository's reference,
    `sql-null` then `sql-null?` giving `sql-null` and `sql-null-1` among them (P4).
  - chez-curl's row holding `pages` to a list of its own is dropped: check-site's seventh
    invariant holds `pages` to README.org, and slice 4, which writes the nav, doesn't own
    `site-unit.sps`.
  - chez-curl's three footer rows rendered pages its nav named; with one page they can't run.
    In their place, four rows on `neighbors` over a three-page fixture nav, and one rendered row
    over every page of the real nav, each footer held to the one its place calls for.
  - Each top-level definition that can raise answers what it raised instead, so a failed load
    or render fails rows by name, as the Tests rules require; chez-curl's "Left" this.
- **`tests/check-site.sps`, chez-curl's seven invariants.** Invariant 1 names no `README.md`.
  Invariant 7 reads README.org's list of the pages: every `[[file:docs/PAGE.md][LABEL]]` link of
  its `** Documentation` section, up to the next heading; a README.org with no such section
  lists them by every such link it holds. `pages` must equal that list, in order, labels and
  all. A link with no label, or one no `]]` closes on its line, dies by name.
- **`tests/check-suites.sps`,** chez-curl's: a `tests/site-*.sps` ends with `site-exit-form`,
  every other suite with `suite-exit-form`. The Makefile names `$(SITE_SUITES)` to it.
- **`tests/check-test-fails.sh`:** check-suites' line names the site suites, counted from the
  copy; two cases, `site-exit-line` and `site-no-exit`, a site suite planted beside the tree's.
  16 cases to 18.
- **`scripts/fetch-akku-lock` and `tests/fetch-akku-lock.sh`,** chez-curl's, but for one change:
  `fetch` copies a `file://` URL with `cp` (below, "Found on the way").
- **`Akku.manifest`** gains `("chez-cmark-gfm" "^2.0.0")` in `depends/dev`; **`Akku.lock`** is
  chez-curl's, byte for byte (`cmp` on the host), chez-cmark-gfm first. **`.gitattributes`**,
  chez-curl's two lines, its comment citing ADR-0022.
- **`tests/test-manifest.sps`:** 79 rows to 84. Changed: `depends/dev` exactly both; the lock
  exactly two projects, chez-cmark-gfm then chez-srfi; the sha256 row over every project. New:
  chez-cmark-gfm's url holds the manifest's version and `_2.0.0_repack`; its project whole, as
  `make site-deps` fetches it; `attribute-lines` held on the suite's own text, twice; and
  `.gitattributes` exactly `(("/.plans" "export-ignore") ("/AGENTS.md" "export-ignore"))`.
  `manifest-version` became `dev-version NAME`, which finds an entry by name.
- **The container:** `manifest.scm` gains `cmark-gfm`, `tar` and `xz`, each with its need;
  `scripts/guix-env-enter` needs both cmark-gfm libraries and exports `CHEZ_CMARK_GFM_LIBS`, the
  core first; the self-test's tool paths gain `tar` and `xz`, and assertion 9 holds the variable
  and both loads; `tests/guix-env-launcher.sh` gains T7a's fifth field and T7f to T7i.
- **The Makefile:** `site-deps`, `site`, `check-site` and `check-site-deps`, each in `make help`
  and on `.PHONY`; `SITE_CMARK`, `SITE_LIBDIRS`, `SITE_REF` and `SITE_SUITES`; check-suites'
  help and recipe; `tests/test-site-testing.sps` in `MEMORY_SUITES_2`. chez-curl's `site-deps`
  took an `akku install` tree first when `.akku/lib` held one; ADR-0007's amendment names
  `fetch-akku-lock` alone, and `akku` isn't installed here, so that branch is left out.

## Found on the way

- **The container has no downloader.** `tests/fetch-akku-lock.sh`, as copied, failed 27 of its
  30 rows in the container: its locks name `file://` archives, and `fetch` ran `wget`, there
  being no `curl`; neither is in the profile. chez-curl's container has `curl` for libcurl, so
  its test passes there by that accident. ADR-0006's amendment lists cmark-gfm, tar and xz
  alone, and says `make check-site-deps` runs offline in the container, so the script copies a
  `file://` URL itself, and the test needs no downloader. Every other URL is still `curl`'s, or
  `wget`'s. Reproduce, from the worktree root, with the script's `fetch` as chez-curl's:

  ```
  scripts/guix-env sh -c 'command -v curl wget; sh tests/fetch-akku-lock.sh | tail -1'
  ```

- **`load-shared-object ""` loads nothing and answers as if it had loaded something.** With
  `CHEZ_CMARK_GFM_LIBS` unset or empty, chez-curl's assertion 9, as copied, read
  `cmark-gfm-loads` ok: the empty parts were each loaded as `""`, which glibc's `dlopen` takes as
  the program itself. Only the variable's own assertion failed. Here the loads count only for
  two absolute paths, and the plants below fail both assertions. Reproduce, in the container:

  ```
  scripts/guix-env sh -c 'echo "(display (guard (e (#t (quote raised))) \
    (load-shared-object \"\") (quote loaded)))" | $CHEZ -q'
  ```

  It printed `loaded`. chez-curl's self-test has the same hole.
- **README.org has no Documentation section yet,** so invariant 7 reads its links to `docs/`
  wherever they stand while it has none, and the section once slice 4 writes it. Slice 4's
  files don't include `tests/check-site.sps`; read only the section, the check would fail on
  `main` from this slice's merge to slice 4's.
- **chez-curl's copied comments carried one date** (`site-unit.sps`, circuit's anchors, "as
  GitHub rendered it on" a day); it is gone, by the comment rule.

## The red runs

- **`test-manifest`, its new rows on the old manifest and lock, no `.gitattributes`:** 78
  passed, 6 failed: `depends/dev`, the two projects, chez-cmark-gfm's url (`()`), its project
  whole (`()`), the sha256 row (`(#t)`), and `.gitattributes` (`raised ... No such file`). Green:
  84 of 84.
- **The launcher test on the old entry script:** 83 passed, 13 failed: T7a's
  `CHEZ_CMARK_GFM_LIBS`, and T7f to T7i, three checks each (exit 2, the path named, nothing run).
  Green: 96 of 96.
- **The new self-test in the old container,** built from `fb4e183`'s manifest and entry script:
  `tool-path` failed for `tar` and `xz` in both shells, `cmark-gfm-variable` and
  `cmark-gfm-loads` failed, the variable unset.
- **`check-site-deps` in the container with chez-curl's `fetch`:** 27 of 30 failed; green, 30.
- **`check-memory-shards` with `test-site-testing` in neither list:** it named it, "in neither
  `MEMORY_SUITES_1` nor `MEMORY_SUITES_2`", `FAILED (problems: 1)`.
- **`check-help`:** `check-site-deps` off `.PHONY` was named, "not in .PHONY"; `site` without
  its `## ` text was named, "does not list .PHONY target 'site'".

## Green

| Check | Where | Last line |
|---|---|---|
| `make test`, Guix's 3.53.1 | container | `test: ran 93, passed 93, failed 0, hung 0` |
| `make test`, `build/m3-floor` | container | `test: ran 93, passed 93, failed 0, hung 0` |
| `make check-site` | container | `check-site: nav, anchors, ... -- all green` |
| `make check-site-deps` | container, host | `fetch-akku-lock: all checks passed` |
| `make check-test-fails` | container | `... failed, as it must, in all 18 cases` |
| `make check-clean` | container | `check-clean: ok: make clean removes build/, ...` |
| `make site` | container | `site: build/site ready (open build/site/index.html)` |
| `make site-deps` | host | `... unpacked to build/akku/chez-cmark-gfm` |
| `make site-deps`, again | host | `... chez-cmark-gfm is up to date (...)` |
| `make check-guix` | host | `check-guix: ALL CHECKS PASSED` |
| `make check-pins` | host | `check-pins: chez-srfi 7879b52: ... agree` |

The floor run set `CHEZ_SQLITE3_LIBRARY` and `C_INCLUDE_PATH` to `build/m3-floor`'s, inside the
`sh -c`; its busy row named SQLite 3.45.1. Each `make test` took 2 min 42 s to 2 min 45 s.
check-site ran `site-render-unit` (18 rows) and `site-unit` (89) before the invariants.
`check-guix`'s self-test ran `make test` inside, 93 of 93.

**Under the gate:** `make test-memory MEMORY_SUITES=tests/test-site-testing.sps`, twice: 6 s and
6 s, passing. It is in `MEMORY_SUITES_2`, the lighter shard by the suites' `time:` lines on three
CI runs: 1372 s, 1735 s and 1540 s against `MEMORY_SUITES_1`'s 1808 s, 1800 s and 1666 s (runs
44721260654, 44723103963 and 44728344123).

## The plants

Each runs in a copy under `build/m5s2/`, and must fail by the message given.

### check-site and the home's rule (`plants.sh`, 36 of 36, three controls passing)

Controls: the tree as it is; a two-page site (`second.md` in `docs/`, the nav and README.org);
and a two-page site whose README.org intro links the pages in the other order, with a
Documentation section listing them in the nav's, and a License section linking a page.

| Plant | Invariant | Caught by |
|---|---|---|
| c1, a page on disk the nav lacks | 1 | `missing-from-site/pages.sls=(new.md)` |
| c2, a page dropped from the nav | 1 | `missing-from-site/pages.sls=(second.md)` |
| c3, a label changed in the nav alone | 7 | `the nav is not README.org's list ...` |
| c4, two pages swapped in the nav | 7 | the same, both lists named |
| c5, a README link with no label | 7 | `README.org links docs/reference.md with no label` |
| c6, a label no `]]` closes | 7 | `... no ]] closes on its line` |
| c7, the section in the other order | 7 | `the nav is not ...`, the section's order |
| c8, the section leaving a page out | 7 | `the nav is not ...` |
| c15, no section and no link | 7 | `listed=() nav=(...)` |
| c16, the section run past its end | 7 | the License link listed third |
| c17, the whole file read beside a section | 7 | the intro's links listed first |
| c9, a same-page anchor no heading has | 2 | `danglers=((reference.md . #nonesuch))` |
| c10, another page's missing anchor | 2 | `danglers=((second.md . reference.md#nonesuch))` |
| c11, every `.md` link left as it is | 3 | `leaked into reference.md: (second.md)` |
| c12, the serializer reindents each line | 4 | `check-site: <pre> reflow FAILED` |
| c13, the wordmark naming `home.html` | 5 | `does not write, in reference.md: (home.html)` |
| c14, a `../` link to no file | 6 | `names no file in it, in reference.md` |
| h1, a link to the home left as its `.md` | 3 | `leaked into reference.md: (reference.md)` |
| h1u, the same, no page linking the home | site-unit | `FAIL a link to the home page ...` |
| h2, the home written under its own name | 5 | `does not write, in reference.md: (index.html)` |
| h2u, the same | site-unit | `FAIL the home page ... is written as index.html` |

h1 and h2 are Q11's two plants. The plan's "held by invariants 1, 2, 3 and 5": a link to the
home left as its `.md` reaches invariant 3 only when a page links the home, and today none does,
so h1 adds the link; site-unit's rows catch the same mutant with none (h1u).

| Plant | Suite | Caught by |
|---|---|---|
| r1, a page's neighbours swapped | site-render-unit | `FAIL the first page's neighbours ...` |
| r2, the home left out of the nav | site-render-unit | `FAIL on the home page, index.html ...` |
| r3, the first page its own previous | site-render-unit | `FAIL each page's footer ...` |
| r4, no page's neighbours asked, two pages | site-render-unit | `FAIL each page's footer ...` |
| s1, `(site slug)` importing `(cmark gfm)` | site-unit | exit 255, `(cmark gfm)` not found |
| s2, slugify keeping `!` | site-unit | `FAIL close-database!` |
| s3, site-unit importing the testing library | site-unit | exit 255, its counters not found |
| s9, `(site-testing)` importing the testing library | site-unit | the same |
| s4, `site-exit-status` ignoring an xpass | test-site-testing | `FAIL an unexpected pass ...` |
| s5, `site-exit-form` the test suites' form | test-site-testing | `FAIL a site suite ends ...` |
| s6, a new site suite that fails | `make check-site` | `site-exit-status: exit 1 (...)` |
| s7, a new site suite ending `(exit 0)` | `make check-suites` | `its last datum is (exit 0) ...` |
| s8, no site suite at all | `make check-site` | `check-site: no suites: ...` |
| t1, the Makefile naming no site suite | check-test-fails | both site cases, `make test exited 0` |
| t2, check-suites holding a site suite to the test form | check-test-fails | every case |

s6 also shows that check-site never reached `check-site.sps`. In t1 every other case fails too,
since check-suites' line counts the tree's site suites.

### test-manifest (`manifest-plants.sh`, 19 of 19, the control passing)

Each must fail exactly the rows named, in order.

| Plant | Rows failing |
|---|---|
| m1 the file gone; m2 its `/.plans` line a comment; m3 its `/AGENTS.md` line gone | the file's |
| m4 a third line; m5 the two swapped; m6 `export-subst`; m7 `-diff`; m8 `/.plans/` | the file's |
| m9 the reader keeping comments | the reader's first row, and the file's |
| m10 the reader splitting on spaces alone | the reader's first row |
| m11 the reader reading any `#` as a comment | the reader's second row |
| l1 chez-cmark-gfm's sha256 a digit off | its project whole |
| l2 its sha256 cut short | its project whole; every sha256 |
| l3 its url naming 2.0.1 | its url; its project whole |
| l4 the manifest asking for ^2.0.1 | `depends/dev`; its url |
| l5 the manifest asking for none | `depends/dev`; its url |
| l6 the lock's two projects swapped | the two projects |
| l7 a third project | the two projects; every sha256 |
| l8 the manifest and lock before this slice | the five red rows above |

### The self-test (`selftest-plants.sh`, from the host)

A copy of the self-test without its last assertion, so each run takes seconds. Under each planted
`CHEZ_CMARK_GFM_LIBS`, `cmark-gfm-variable` failed; `cmark-gfm-loads` failed too, but in the
other order, where both files load:

- unset; empty; `/nonexistent/...` twice (the loads naming both paths); the two in the other
  order; the core alone; three paths; the core then nothing.

The control passed, `ALL CHECKS PASSED`. Before the loads counted only two absolute paths,
unset and empty passed `cmark-gfm-loads` (above).

### P4's comparison

A site anchor and a test-docs anchor each changed in a copy of the probe's output: `compare.py`
named `DIFFERS site reference.md`, then `DIFFERS test-docs reference.md`.

## P4: the two anchor rules on every heading of `docs/`

`anchors/probe.sps` prints, for each `docs/*.md`, the anchors of `(site render)`'s registry and
of `test-docs`' own `markdown` and `anchors`, its definitions read from `tests/test-docs.sps`
and evaluated. `anchors/compare.py` reads them beside GitHub's rendering of the page at
`fb4e183`, fetched on the host with `gh api` (`application/vnd.github.html`): **1 page, 81
headings on GitHub; 0 page-rule pairs differ.** Each rule gives GitHub's anchor for every
heading, `sql-null?` after `sql-null` as `sql-null-1` among them. Slice 4 runs it again on the
new pages.

## The survivor, argued

- **r4 on one page:** render-site asking no page's neighbours draws no footer, and with today's
  one page there is none to draw, so the rendered footer row passes it (`r4one`). On two pages
  it fails (r4), and the four `neighbors` rows hold the order itself. Slice 4's four pages make
  the row catch it on the real nav.

## For the records

- **AGENTS.md,** the plan's §10.8 slice 2 lines: the Dependencies bullet, and the container
  bullets' `CHEZ_CMARK_GFM_LIBS` and `make site-deps`.
- **traps.md:** the two findings above, each with its command.
- **The plan:** invariant 7's reading while README.org has no Documentation section, and
  slice 4's file list without `tests/check-site.sps`.
