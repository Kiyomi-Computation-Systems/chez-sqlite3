# M5 slice 3 mutation log

Evidence that each rule slice 3's checks claim to guard fails through the property it names
([the M5 plan](2026-11-20-m5-plan.md) §5, slice 3, §4.4 and §4.10's `check-ci` items; probe P5,
§8). Format of [the M5 slice 2 log](m5-slice-2-mutation-log.md).

An Opus agent built the slice from the lead's brief, in its worktree, on `m5-slice-3` from `main`
at `8c18272`, beside slice 4 in a worktree of its own. Builds and suites ran in the Guix container:
Chez 10.4.0 (`ta6le`, threaded), GNU Awk 5.3.0, x86_64. P5 and the mawk run were in Docker, in
`ubuntu:24.04` (`sha256:9c7f200c…`, Ubuntu 24.04.5 LTS, mawk 1.3.4 20240123), on the host, as
were `check-action-pins.sh` and the pins' `git ls-remote`. The drivers are in
[research/m5-slice-3/](research/m5-slice-3/); their logs were written under the worktree's
`build/m5s3/`, and their results are quoted here.

## What the slice adds

- **`ci.yml`'s seventh job, `site`,** chez-curl's at `fa9750d`, in `check-ci`'s shape:
  `ubuntu-24.04`, `timeout-minutes: 10`, the checkout with `submodules: recursive`; the install
  step's form reading `packaging/debian-site-prereqs.txt`; then `make check-site-deps`, `make
  site-deps`, `make check-site` and `make site`, each a step's whole run line with `env: CHEZ:
  chezscheme`. No cache, no `if:`, no `SITE_REF`. Changed from chez-curl's: `CHEZ` by `env:`, where
  chez-curl's run lines pass `CHEZ=chezscheme` to make; no `persist-credentials: false`, a with
  key `check-ci` refuses and no other job of ours sets; the packages from a list, not a line; and
  the step that names the fetcher no longer names `scripts/`, which `check-ci` holds to run lines.
  The header names the job and seven jobs, and the site's own package list.
- **`pages.yml`,** chez-curl's, 77 lines there, 98 here: the names (ADR-0022, `libsqlite3`,
  `(chez-sqlite3 private require-threaded)`); the install step's form and list, where chez-curl's
  names three packages on a line; `CHEZ` and `SITE_REF` by `env:`, `SITE_REF` `${{ github.ref_name
  }}`, the tag, where chez-curl's run lines pass `SITE_REF="${GITHUB_REF_NAME}"`, so its steps
  read as the site job's; and a header paragraph saying `check-ci` holds it. Its three actions are
  chez-curl's pins, each resolved again on the host by `git ls-remote`: `checkout` `v7.0.1`
  `3d3c42e5…`, `upload-pages-artifact` `v5.0.0` `fc324d35…`, `deploy-pages` `v5.0.1` `368f8252…`,
  each tag lightweight.
- **`packaging/debian-site-prereqs.txt`:** `chezscheme`, `cmark-gfm`, `ca-certificates`, `curl`,
  `make` and `xz-utils`, the last four for a bare machine, as `debian-prereqs.txt` lists `curl`.
  chez-curl has no such file: its site job and `pages.yml` each name three packages in the step.
  **`packaging/debian-prereqs.txt`'s header** says every job but `site` installs from it.
- **`tests/check-ci.sh`:**
  - the directory holds `ci.yml` and `pages.yml` alone, each a regular file and no link;
  - seven jobs; in `site`, the checkout with submodules first, the four checks in order, each
    with `env` `CHEZ` `chezscheme`, no action but the checkout, and no `if:`;
  - `SITE_REF` and `CHEZ_CMARK_GFM_LIBS` join the names no line of `ci.yml` may hold;
  - the text rules on every line of `ci.yml`, a comment's included, where comments were skipped;
  - every line of `pages.yml` but a comment or a blank one equals the check's copy, line for
    line and in order, the first that differs named alone; the text rules on its every line.

  The pass line is unchanged, since `check-memory-gate`'s case o compares it whole.
- **`tests/test-check-ci.sps`:** 496 rows to 573. Each row writes both workflows; a fifth element
  holds `pages.yml`'s edits, `prow` makes a row of them, and `(P anchor)` names a line of it. 47
  rows for the `site` job, 20 for `pages.yml`, 3 for `ci.yml`'s comments, 4 for the directory, 2
  banned names, 1 `test-assert`. Changed: the directory rows' message; "a directory with neither
  workflow", two problems; the no-load rows' `five`, and "the current job deleted", which read to
  the file's end, where `site` now stands.
- **The Makefile:** `check-ci`'s help line names both files.

## Found on the way

- **chez-curl has no `tests/check-ci.sh`, no `tests/test-check-ci.sps` and no
  `packaging/debian-site-prereqs.txt`** at `fa9750d`, which the brief listed to read. It holds no
  workflow's shape; `pages.yml`'s rule is this repository's own, from S3.
- **On Ubuntu, a site step that loses its `CHEZ` still runs Ubuntu's Chez, and passes.**
  `chezscheme` makes `/usr/bin/scheme` an alternative for `/usr/bin/chezscheme`, and the
  Makefile's default `CHEZ` is `scheme` when there is one. So only `check-ci` sees the `env:` gone.
  P5's first run showed it: a fault of the driver's own left every step with no env, and all nine
  passed. Reproduce on the host:

  ```
  docker run --rm ubuntu:24.04 sh -c 'apt-get update -qq >/dev/null 2>&1 &&
    apt-get install -y -qq --no-install-recommends chezscheme >/dev/null 2>&1;
    readlink -f "$(command -v scheme)"'
  ```

  It printed `/usr/bin/chezscheme`.
- **The driver's fault:** `run_step` emptied its arguments with `set --` before a heredoc read
  `$2`; under `set -u` dash printed `parameter not set` and went on, the loop that built the env
  never ran, and `pages.yml`'s copy linked `blob/main/` with `SITE_REF` the tag. Fixed, the step's
  shell now prints the `CHEZ` and `SITE_REF` it sees, and the host driver fails on any line of the
  inside script's own errors; the first run's log holds 9 such lines.
- **The Makefile's comment above `check-ci`** still says "its six jobs", and names `ci.yml`
  alone. The brief let this slice touch the help line only (for the lead).

## The red runs

- **The new suite on `HEAD`'s `check-ci.sh`:** 5 passed, 568 failed. The 5: the two
  `test-assert`s, the two usage rows, and the directory that isn't there. `HEAD`'s check refuses
  the real tree, `site` an unknown job and `pages.yml` a second file, so every row on a copy
  fails; the mutants below are where each rule is watched failing alone. No row's construction
  raised.
- **`HEAD`'s `check-ci.sh` on the new workflows:** exit 1, two problems: `.github/workflows:
  pages.yml is not ci.yml: the directory must hold ci.yml alone`, and `ci.yml:638: job "site" is
  not one of main, memory-1, memory-2, nothreads, floor, current`.

## The mutants (`mutants.sh`, 22 of 22 killed, the control passing 573 rows)

Each loosens one rule in a copy of `tests/check-ci.sh`, and a copy of the suite runs against it,
its execute-bit rows pointed at the real `scripts/ci` by `CHECK_CI_ROOT`. Each must fail the row it
names, and every one did.

| Mutant | What it loosens | Rows failed |
|---|---|---|
| `dir-any` | any name in the directory passes | 6, the stray-entry rows |
| `pages-link` | `pages.yml` may be a link | 1 |
| `pages-missing` | `pages.yml` may be missing | 5, the link, missing, directory and `.yaml` rows |
| `pages-no-compare` | a held line is never compared | 13 |
| `pages-no-early` | a file that ends early passes | 2, the last line and every line dropped |
| `pages-no-extra` | a line past the copy's end is named as a difference | 1 |
| `pages-every-line` | each line past the first difference named too | 6, each drop, add, move |
| `pages-any-hash` | any line holding `#` is a comment | 559: the pins' tag comments are held |
| `pages-comment-tab` | a comment's tab passes | 1 |
| `pages-comment-odd` | a comment's character beyond ASCII passes | 1 |
| `pages-no-odd` | no line's character beyond ASCII is named | 2 |
| `ci-comment-skipped` | `ci.yml`'s comments skipped, as before | 3, the three comment rows |
| `site-not-missed` | a missing `site` job passes | 2, deleted and renamed |
| `site-no-checks` | `site` must run nothing | 21 |
| `site-any-order` | `site`'s checks in any order | 4, the four moves |
| `site-no-env` | a check without `CHEZ` passes | 4 |
| `site-any-chez` | a check's `CHEZ` is not held | 4 |
| `site-if-ok` | an `if:` in `site` passes | 6 |
| `site-cache-ok` | `site` may use the cache actions | 2, the restore and the save |
| `site-no-checkout` | `site`'s first step is not held | 1 |
| `site-key-held` | a cache key in `site` is held, a second problem | 2 |
| `site-names-free` | `SITE_REF` and `CHEZ_CMARK_GFM_LIBS` may be named | 5 |

`pages-no-extra` shows the row holds the extra line's own message: without it the line is
still named, as a difference from an empty line. `site-key-held` holds a choice, not a rule: a
cache step in `site` is one problem, its action, not two.

## The plants

§4.10's `check-ci` plants are the suite's rows: each copies both workflows, plants one fault, and
asserts the whole output. They are listed with what caught them.

- **A third file in the directory:** "a third workflow in the directory", other.yml; a hidden
  file; a subdirectory. Each: `NAME is neither ci.yml nor pages.yml: the directory must hold those
  two alone`. And "pages.yml is named pages.yaml": `pages.yml: is not a regular file ...`, then
  `pages.yaml is neither ...`.
- **`pages.yml` a link:** `pages.yml: is not a regular file: a link, a directory or nothing
  there`, then the link's target named as a stray entry. Missing, or a directory: the first alone.
- **A line changed:** the trigger widened to every tag; the permissions widened; the deploy action
  unpinned; the site built for `main`; white space at a line's end. Each: `pages.yml differs from
  the copy check-ci holds: expected "...", found "..."`, at that line.
- **A line dropped:** the deploy job's `needs`; the checkout's `persist-credentials`. Each:
  `differs`, at the next held line. The last line: `pages.yml ends early: expected "..."`, at the
  file's last line; every line: the same, on the file, expecting `name: Pages`.
- **A line added:** a step of its own; `contents: write` in the deploy job's permissions. Each:
  `differs`, at the line added. At the end: `pages.yml has a line the copy check-ci holds does
  not: "..."`.
- **A line moved:** the deploy job's two permissions swapped; the site built before it is gated.
  Each: `differs`, at the first, and only there.
- **The `site` job dropped:** deleted, or renamed `docs`: `job "site" is missing`, after `job
  "docs" is not one of ...` for the second.
- **A check of it moved:** each adjacent pair swapped, and `make site` put first: `job site runs
  "X" before "Y", and must run it after`, at the step out of its place.
- **A check of it dropped:** each of the four deleted, or written twice: `job site has 0 steps that
  run "X", not one`, or 2.
- **Given another `CHEZ`:** the built Chez's path, `scheme`, `/usr/bin/chezscheme` and
  `chezscheme9.5`, one per check: `env CHEZ in job site is not chezscheme`. Each check without its
  `CHEZ`: `job site's step that runs "X" has no env CHEZ`.
- **A cache step in it:** a Chez cache restored before the install step: `job site has a step that
  uses "actions/cache/restore@...", which is not actions/checkout@: it has no cache`, alone. The
  site saved to a cache, under the cache's `if`: `job site takes no if: it has no cache`, then the
  same for the save.

Beside them: an `if:` on each check and on the install step; `pages.yml`'s upload action in the
job; `SITE_REF` on `make site`'s run line and in `make check-site`'s env; `CHEZ_CMARK_GFM_LIBS` in
an env; the checkout without submodules; no `timeout-minutes`; `runs-on` another; each of the
eleven refused job keys. Two rows hold what is not held: comments added, changed and dropped and
blank lines added pass, and so does a comment line inside a run block. A tab, and U+2028, in a
comment of each file, and a tab and an `é` in a held line of `pages.yml`, are each named.

**Under two awks** (`awk-plants.sh`): fourteen of the plants, in copies built with GNU sed, run
through `tests/check-ci.sh` by the container's gawk 5.3.0 and by mawk 1.3.4 in `ubuntu:24.04`.
Every plant failed, the control passed, and the two awks wrote the same bytes, all 15: "every
plant failed, the control passed, gawk and mawk agree".

## P5: the site job's steps in `ubuntu:24.04`

`p5-site-job.sh` copied the tree as a checkout holds it, the files git tracks or would and
chez-srfi's, and `p5-inside.sh` ran, in a fresh `ubuntu:24.04` as a user `runner` with sudo, each
step of `ci.yml`'s `site` job, then of `pages.yml`'s `build` job in a second copy, read from the
copied workflow: its env, and its run text given to `bash -e`. Before the install step the image
had no `curl`, `wget`, `make`, `xz`, `chezscheme` or `cmark-gfm`; it installed 23 packages.

| Step | Env the step saw | Last line |
|---|---|---|
| 1 the install step | none | `Processing triggers for libc-bin (2.39-0ubuntu8.9) ...` |
| 2 `make check-site-deps` | `CHEZ=chezscheme` | `fetch-akku-lock: all checks passed` (30 checks) |
| 3 `make site-deps` | `CHEZ=chezscheme` | `... unpacked to build/akku/chez-cmark-gfm` |
| 4 `make check-site` | `CHEZ=chezscheme` | `check-site: nav, anchors, ... -- all green` |
| 5 `make site` | `CHEZ=chezscheme` | `site: build/site ready (open build/site/index.html)` |
| `pages.yml` 6, the install step | none | `0 upgraded, 0 newly installed, ...` |
| 7 `make site-deps` | `CHEZ=chezscheme` | `... unpacked to build/akku/chez-cmark-gfm` |
| 8 `make check-site` | `CHEZ=chezscheme SITE_REF=v0.1.0` | `check-site: ... -- all green` |
| 9 `make site` | `CHEZ=chezscheme SITE_REF=v0.1.0` | `site: build/site ready ...` |

- **The downloader was curl:** `make site-deps` reached `fetch-akku-lock`'s download branch twice,
  once per copy, with `/usr/bin/curl`, curl 8.5.0-2ubuntu10.16, and no `wget` on the machine; the
  script takes curl when there is one.
- Chez Scheme 9.5.8 (`chezscheme 9.5.8+dfsg-1`); `cmark-gfm 0.29.0.gfm.6-6build1` with its two
  libraries, which chez-cmark-gfm found by itself; check-site ran `site-render-unit` (18 rows) and
  `site-unit` (89) before the invariants.
- `build/site` held 2 files, its one page and the stylesheet. The site job's one link to a
  repository file named `blob/main/`; `pages.yml`'s, `blob/v0.1.0/`.
- `sh tests/check-ci.sh .github/workflows` under the image's mawk passed, with its usual line.

Nothing failed in Ubuntu that passed in the container, so nothing was fixed for P5.

## Green

| Check | Where | Last line |
|---|---|---|
| `make test` | container | `test: ran 93, passed 93, failed 0, hung 0` |
| `test-check-ci`, in it | container | `# of expected passes 573` |
| `make check-ci` | container | `check-ci: .../ci.yml has the one shape check-ci reads` |
| `make check-test-fails` | container | `... failed, as it must, in all 18 cases` |
| `make check-floors`, in `make test` | container | `... (ci.yml, pages.yml) ... hold the floors` |
| `make check-help` | container | exit 0 |
| `check-action-pins.sh .github/workflows` | host | `... all 28 lines with a uses key ...` |
| `mutants.sh` | container | `mutants: 22 killed, 0 survived; control ok` |
| `awk-plants.sh compare` | container | `... the control passed, gawk and mawk agree` |
| P5, `p5-site-job.sh` | host, Docker | `=== p5: 9 steps run, 0 failed` |

The 28 lines with a uses key: `ci.yml`'s 24, the `site` job's checkout, and `pages.yml`'s three.
`check-memory-gate`'s case o compares `check-ci`'s pass line whole; the line is unchanged, and
`sh tests/check-ci.sh .github/workflows` from the root printed it. `make test-memory` was not run.
P5, the awk plants and most of the mutants ran before the `site` job's comment gained its last
three lines, on `/usr/bin/scheme`; its steps are unchanged since, and `make test`, `check-ci`,
`check-test-fails` and the pin check ran after.

## For the records

- **AGENTS.md,** the plan's §10.8 slice 3 line: the `check-ci` bullet's "holds
  `.github/workflows/ci.yml` to one shape" becomes "holds `.github/workflows/ci.yml` to one shape,
  and `pages.yml` to its copy, line for line".
- **The global constraints,** "CI's workflow has one shape…": its "six jobs" is seven now; the
  banned names gain `SITE_REF` and `CHEZ_CMARK_GFM_LIBS`; and the text rules hold on a comment's
  line of `ci.yml` too, where comments were skipped.
- **traps.md:** Ubuntu's `/usr/bin/scheme` is an alternative for `chezscheme`, so a site step that
  loses its `CHEZ` passes; only `check-ci` holds it. The command is above.
- **The Makefile's comment above `check-ci`:** "its six jobs" and `ci.yml` alone; the help line
  names both files.
- **The plan:** §4.4's "the text rules ... on every line of both" was built as written, so
  `ci.yml`'s comments are now held to them; and chez-curl has no `check-ci` nor a site package
  list to copy, so `pages.yml`'s rule and the list are this slice's own.
- **After the merge** (the maintainer's, §5): branch protection gains `site`; then Pages is turned
  on, built from GitHub Actions, and its `github-pages` environment takes `main` and `v*`, read
  back by the lead. The PR's CI run's `site` job is read for the download branch on a runner.

## Round 2: the review's findings

The slice was committed as `3f68b33`, PR #55. Its read-only Opus review found no blocker, one
major and three minors; the lead's brief added the wording. The same agent fixed them in the same
worktree, the lead's own uncommitted edits to `tests/site-unit.sps`, `tests/site-render-unit.sps`
and the records under `.plans/` left alone. The review's plants, mutants and tried fix are in its
worktree's `build/rv/`, and were read there; this round's drivers are
`review-plants-extra.py`, `review-plants-run.sh` and `mutants.sh`, extended.

### What changed

- **Major 1, a run block's comment and blank lines.** `pages.yml`'s reader skipped every line
  that was blank or began with `#`, inside the install step's run block too, where each is the
  script's text: `# a note` at column 0 there passed, and PyYAML could not parse the file. The
  reader is now one awk file, `copy.awk`, that both checks run, and it holds a block scalar's
  content whole. A line is content when the copy's next line is, so a line that cuts the copy's
  block is held; or when it is blank or indented deeper than the key of a block the file holds
  open, so a line after the block's last one, indented as its content, is held too. A blank line
  there is held when content follows it, and dropped, as YAML drops it, when none does. The copy
  gains the block's `# shellcheck disable=SC2086`.
- **Minor 2, three survivors.** Rows for a run-block line changed (`exit 1` to `true`), a held
  line's indent changed (`   contents: read`), and U+0085 and U+2028 in a comment line of
  `ci.yml`'s run block.
- **Minor 3, the site job's other steps.** Its install step, the second, is held from its first
  line to the next step's, by the same reader, to `$tmp/install`, the one text `pages.yml`'s
  copy also takes its install step from, so the two cannot drift. The job is held at six steps.
- **Minor 4, a name holding a newline.** The directory is read by a glob, the review's, not by
  lines of `ls`; a name is shown with a `?` for each byte that is not printable ASCII, so its
  problem stays one line.
- **The wording:** `check-ci.sh`'s "the names no line may hold" is "no line but a comment";
  `debian-prereqs.txt` says the site's Chez is one it leaves out, since every job installing from
  it builds its own; the Makefile's `check-ci` comment is plural and reflowed.
- **Beyond the brief:**
  - In `ci.yml`, a line of a block scalar's content that begins with `#` was freed from the
    names, the gates and the `scripts/` rule, where the header said "a block scalar's content
    included": the comment branch ran first. It is no comment, and GitHub expands its
    expressions: `x-main-expr-in-block` put `${{ fromJSON(...) }}`, a string holding a newline
    and `echo MAKEFLAGS=-n >> "$GITHUB_ENV"`, in main's runner-image block, and `3f68b33`'s check
    passed it. Such a line now goes through every content rule, and the awk names a `scripts/` on
    it, which the shell's grep, reading no line that begins with `#`, never saw.
  - `debian-site-prereqs.txt` said "nothing else does" install from it, and that no other job
    "may have" Ubuntu's Chez; neither is held. It now says what `check-ci` holds.
  - The site job's comment in `ci.yml`, and `pages.yml`'s header, name the six steps and the run
    block's lines.

### Found on the way

- **The review's tried fix holds a run block's comment line only while the copy expects more of
  the block.** A comment line after the block's last line, indented as its content, passes it:
  `x-pg-expr-after-block` adds the expression above there, the review's `fix/check-ci.sh` passed
  it, and PyYAML reads it as the run script's last line. This round's reader refuses it.
- **The six plants that still pass** are not this round's: `main-make-no-env`, main's make line
  without `CHEZ`, which only floor, current and site hold, and which a runner with no `scheme`
  would fail; `main-reads-site-list`, main's install step reading the site's list, which no rule
  holds; `site-checkout-path` and `site-checkout-key`, a `with` key on the site's checkout, which
  every job's checkout may carry; `site-timeout-0`, which `check-ci` holds to a whole number
  only; and `site-name-changed`, a job's free name. `site-checkout-tag` passes `check-ci` and
  fails `check-action-pins.sh`, as every unpinned action does.

### The red runs

- **The new rows on `3f68b33`'s `check-ci.sh`:** 568 passed, 35 failed, every one new or changed:
  the twelve site rows that gain the count or the install step's problem; the nine new site rows;
  the row that held the hole, now a refusal, and eight of the twelve new `pages.yml` rows; the
  three `ci.yml` rows that name a gate, `scripts/` and the expression's names; and the two newline
  names. Of the new rows, those that passed are the four controls, and the four that kill a
  survivor (`exit 1`, the indent, U+0085 and U+2028), whose rules `3f68b33`'s check already had.
  No row's construction raised.

### The mutants (`mutants.sh`, 36 of 36 killed, the control passing 603 rows)

Round 1's 22, retargeted where the reader they mutated is now `copy.awk`'s (`pages-no-compare`,
`-no-early`, `-no-extra`, `-every-line`, `-any-hash`, and `ci-comment-skipped`), each killed by
its row again. The new 14, each run against the final check:

| Mutant | What it loosens | Rows failed |
|---|---|---|
| `run-block-free` | a block's line is never compared (the review's) | 12 |
| `indent-free` | leading spaces ignored (the review's) | 1, the indent row |
| `content-comment-free` | a block's `#` line skips every rule (the review's) | 6 |
| `content-names-free` | a block's `#` line skips the names, as at `3f68b33` | 4 |
| `content-scripts-free` | a block's `#` line may name `scripts/` | 1 |
| `block-by-copy-only` | a block held only where the copy's runs (the review's fix) | 2 |
| `block-by-file-only` | a block held only where the file's YAML runs | 2 |
| `blanks-never-held` | a blank line in a block never held | 1 |
| `blanks-always-held` | a blank line after a block held too | 577 |
| `literal-blind` | `|` opens no block | 597 |
| `site-any-count` | `site` at any number of steps | 13 |
| `site-install-free` | the site's install step not held | 9 |
| `name-raw` | a stray name shown raw, its newline splitting the line | 2 |
| `dir-ls` | the directory read by lines of `ls`, as at `3f68b33` | 2, the newline rows |

The review's fourth, `dir-glob`, was its proposed fix, and is the code now: `dir-ls` is it
reverted.

### The plants, under two awks

The review's builder, its `tools/plant.py`, run on the final workflows (35), and
`review-plants-extra.py` (5), each run by `review-plants-run.sh` under the container's gawk 5.3.0
and mawk 1.3.4 in `ubuntu:24.04`: the two answered the same bytes for all 40.

| Plant | Now caught by |
|---|---|
| `pg-run-comment-col0`, `-col8`, `-expr` | `pages.yml differs ...`, at the line planted |
| `pg-run-first-deep-comment`, `-deep-blank` | `pages.yml differs ...`, expected the block's first |
| `x-pg-expr-after-block` | `pages.yml differs ...`, expected the next step's first line |
| `p2-run-exit-true`, `pg-indent-only` | `pages.yml differs ...`, at the line |
| `site-install-drift`, `-reads-main-list`, `-chez-env-install` | `job site's install step ...` |
| `site-run-comment-expr` | `names GITHUB_ENV ...`, `names MAKEFLAGS ...`, then the install step |
| `site-true-chez`, `site-second-checkout` | `job site has 7 steps, not six: ...` |
| `x-main-expr-in-block` | `names GITHUB_ENV ...`, `names MAKEFLAGS ...` |
| `p3-nel-content-comment`, `-last` | `holds a character beyond ASCII ...` (as at `3f68b33`) |
| `dir-newline-name`, `-name2` | `pages.yml?ci.yml is neither ...`, `ci.yml?pages.yml ...` |

The others failed as at `3f68b33`, by its rules: the NUL plants and the held lines of `pages.yml`,
and the site job's refused keys. Round 1's `awk-plants.sh`, rerun on the final check: every
plant failed, the control passed, and gawk and mawk agreed, all 15; `site-cache` now names the
seventh step before the action.

### PyYAML

PyYAML 5.4.1 on the host loads both real workflows: `ci.yml`'s seven jobs, `site` with 6 steps;
`pages.yml`'s `build` with 6 and `deploy` with 1; and the two install steps load as equal
objects. The review's `pg-run-comment-col0` fails to parse, a `ParserError` at its line 53.

### Green (round 2)

| Check | Where | Last line |
|---|---|---|
| `make test` | container | `test: ran 93, passed 93, failed 0, hung 0` |
| `test-check-ci`, in it | container | `# of expected passes 603` |
| `make check-ci` | container | `check-ci: .../ci.yml has the one shape check-ci reads` |
| `make check-test-fails` | container | `... failed, as it must, in all 18 cases` |
| `make check-floors`, in `make test` | container | `... (ci.yml, pages.yml) ... hold the floors` |
| `check-action-pins.sh .github/workflows` | host | `... all 28 lines with a uses key ...` |
| `test-check-ci` under mawk | host | `# of expected passes 603` |
| the red run under mawk | host | 568 passed, 35 failed: the same rows as under gawk |
| `mutants.sh` under gawk | container | `mutants: 36 killed, 0 survived; control ok` |
| `mutants.sh` under mawk | host | the same: 36 killed, each failing the same rows |
| the review's plants and the extra | both awks | the two `out-` trees equal, all 40 |
| `awk-plants.sh compare` | container | `... the control passed, gawk and mawk agree` |
| P5, `p5-site-job.sh` | host, Docker | `=== p5: 9 steps run, 0 failed` |

`test-check-ci` and the mutants ran under mawk on the host, with Guix's Chez 10.4.0 (threaded),
since the suite needs a Chez at the floor and the container has no mawk; the lead's brief allowed
the host's mawk. P5 ran again on the final tree: the same nine steps, envs and links; its copy took
the working tree, the lead's uncommitted site suites among it (`site-unit` 90 rows).

### For the records (round 2)

- **The global constraints,** "CI's workflow has one shape…": the site job is held at six steps,
  its install step line for line to the text `pages.yml`'s install step is held to; a block
  scalar's lines are held whole in `pages.yml`, a comment's and a blank one's among them; in
  `ci.yml` a block's line that begins with `#` keeps every content rule; and the directory is
  read by a glob.
- **traps.md:**
  - A line of a YAML block scalar that begins with `#` is the script's text, not a comment:
    GitHub expands its `${{ }}`, and a string holding a newline puts a command on a line of its
    own. `3f68b33`'s check passed `x-main-expr-in-block`; reproduce, from the repository root,
    with the plants built as above, `git show` on the host and the run in the container:

    ```
    git show 3f68b33:tests/check-ci.sh >build/m5s3/r2/old.sh
    scripts/guix-env sh -c '(cd build/m5s3/r2/rvp/p &&
      CHECK_CI_ROOT=$OLDPWD sh "$OLDPWD/build/m5s3/r2/old.sh" x-main-expr-in-block)'
    ```

    It printed the pass line, exit 0.
  - A block held to a copy only where the copy's block runs frees the lines after it that YAML
    still reads as the block's: the review's tried fix passed `x-pg-expr-after-block`. The same
    run, with the review's `fix/check-ci.sh` as `old.sh` and that plant, printed the pass line;
    the final check names its line 63.
  - A directory read by lines of `ls` splits a name that holds a newline: `pages.yml`, a
    newline, `ci.yml`, passed as two allowed names.
- **AGENTS.md:** nothing new beyond round 1's bullet.
- **The ledger:** round 2's close-out lines: the four findings and the wording fixed, the
  review's tried fix and the case it missed, the content-line rule beyond the brief, the six
  plants left with their reasons, the counts below.
