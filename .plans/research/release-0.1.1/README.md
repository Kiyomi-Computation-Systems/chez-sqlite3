# The release of 0.1.1

The M5 plan's §4.9, steps 1 to 10, as they ran on 2026-11-22, by the M3 session, the lead. The
M4 session was offline throughout, so PR #64 had no read-only check. `v0.1.1` is the signed tag
object `a0f55a4` on `960d9f0`, the squash of PR #64.

## Why a release

The maintainer's Pages run from `main`, 45029901884, stopped at the `github-pages` environment's
gate. That's by design: the environment takes the tag rule `v*` alone ("Drop main, keep v\*",
ADR-0022, amended in M5's closing review), so the site deploys from tags only. The maintainer
chose "Release 0.1.1", which carries the examples (PR #62) to the site and to README.org's clone
line.

## The PR

- **PR #64:**
  - `b5a3109` is the bump. It holds CHANGELOG.md's `[0.1.1]` entry, dated 2026-11-22, with an
    Added entry for the examples and a Changed one for the quick start's clone note. It also
    puts `Akku.manifest` at 0.1.1, both clone lines at `--branch v0.1.1`, and the Mac steps
    ([mac.md](mac.md)).
  - `91c5ccc` holds the review's fixes. CI passed in all seven jobs on it (run 45033938606).
- **`test-manifest` watched failing,** each time by name:
  - with CHANGELOG.md bumped alone, the manifest's row failed
    ([tm-changelog-only.txt](out/tm-changelog-only.txt));
  - with the clone lines left at `v0.1.0`, the clone lines' row failed, naming both lines
    ([tm-no-clone.txt](out/tm-no-clone.txt));
  - with `[0.1.1]` written in the first release's form, `releases/tag/v0.1.1`, the entry's row
    failed ([tm-plant-ref.txt](out/tm-plant-ref.txt)).

  The whole bump passed 107 ([tm-all.txt](out/tm-all.txt)), and `make test` passed 93 of 93
  in the container, on `b5a3109` ([make-test.txt](out/make-test.txt), its `test:` lines).
- **The lead's Opus review of `b5a3109`,** read-only, found no blocker or major. It found three
  minors, all fixed in `91c5ccc`:
  - the Mac steps now read `test-docs`' count, 191;
  - they read the two SQLite versions from the P4 lines, and macOS's from `sw_vers`;
  - the entry links 0.1.0's known limitations, since a Release's body stands alone.

  It also found four nits. Two were in mac.md and are fixed. The other two are in the records,
  and they are ADR-0022's amendment of 2026-11-25, which the maintainer accepted:
  - the ADR's wording of a release's link reference fits only the first release;
  - §4.9 names `v0.1.0` throughout, and its fallback tag `v0.1.1`.

## The steps

| Step | What ran | Result |
|---|---|---|
| 1 | The release branch, CI | 7 of 7 on `91c5ccc` |
| 2 | The maintainer's Mac `make test` on `91c5ccc` | 93 of 93 with Apple's 3.51.0 and Homebrew's 3.54.1 ([outputs](out/mac/)) |
| 3 | The squash, `main`'s push run | `960d9f0`, its tree `43a4cbc…` the tested head's; 45037754109, 7 of 7 |
| 4 | Pages, the environment, the ruleset; the live check on loopback | as set; `v0.1.1`'s render exits 0, `main`'s exits 1 on links |
| 5 | The tag, signed and pushed alone | `git tag -v`: a good signature, key `…8EAC5130`; read back |
| 6 | The tag's Pages and CI runs | 45054908550, build and deploy; 45054908565, 7 of 7 |
| 7 | The live check at the site | exits 0; as `v0.1.2`, exits 1 on links and clone |
| 8 | The GitHub Release, 454682795 | draft, body byte-equal, published as the latest, read back |
| 9 | The archives, listed | the same 827 entries, no `.plans/` or `AGENTS.md` |
| 10 | README's clone line, verbatim; the first program | clones `960d9f0`; prints `(#("bird" 2) #("cat" 4))` |

- **Step 2, the Mac** (macOS 26.7.1, [macos.txt](out/mac/macos.txt)):
  - Each run ended `test: ran 93, passed 93, failed 0, hung 0`, and `test-docs` gave 191 on
    each, as on Linux. That is the examples' first run on a Mac.
  - The P4 lines named SQLite 3.51.0 for Apple's library and 3.54.1 for Homebrew's, the
    versions README.org's Status names.
  - Apple's run named the same rows unavailable as 0.1.0's, line for line. Homebrew's named
    none. `test-manifest` passed on both.
  - The run was on `91c5ccc`, the tested head, whose tree is the tag's. No output names the
    head, but `macos.txt` exists, and only `91c5ccc`'s steps ask for it; it was written at
    09:40, after `91c5ccc`'s commit at 09:38.
- **Step 4:**
  - Pages builds from workflows, over HTTPS. The `github-pages` environment holds one policy,
    `tag:v*`. The ruleset "release tags" is active on `refs/tags/v*`, with the rules `update`
    and `deletion` and no bypass actor.
  - The renders are `SITE_REF=v0.1.1 make site` and `SITE_REF=main make site`, run in the
    container on `960d9f0`. Each was served by `python3 -m http.server --bind 127.0.0.1`.
  - `live-check.sh` was given `v0.1.1` as its tag. It exited 0 against `v0.1.1`'s render
    ([live-loopback-v0.1.1.txt](out/live-loopback-v0.1.1.txt)), and 1 against `main`'s, on links
    alone ([live-loopback-main.txt](out/live-loopback-main.txt)).
  - The check against the live 0.1.0 site, before the tag, exited 1 on all three clauses
    ([live-site-before-tag.txt](out/live-site-before-tag.txt)). That's step 7's watched failure.
- **Step 5:** the tag was absent locally and on `origin` first. `git ls-remote origin
  'refs/tags/v0.1.1*'` then listed `a0f55a4` at `refs/tags/v0.1.1`, and `960d9f0` at
  `refs/tags/v0.1.1^{}`, as `git rev-parse` does locally. The tagger is the releases identity,
  as for `v0.1.0`.
- **Step 7:** the check exited 0 at the site ([live-site.txt](out/live-site.txt)), and 1 given
  `v0.1.2` ([live-site-v0.1.2.txt](out/live-site-v0.1.2.txt)). The five pages and the
  stylesheet, fetched from the site, are each byte-equal to step 4's `v0.1.1` render.
- **Step 8, chez-curl ADR-0042's recipe:**
  - **The notes:** chez-curl's `extract.py v0.1.1 0.1.1` gave
    [notes-v0.1.1.md](out/notes-v0.1.1.md), 655 bytes. That's the entry from its intro to its
    last bullet.
  - **The draft:** `gh release create v0.1.1 --verify-tag --draft`, titled with the tag
    message's subject, "chez-sqlite3 v0.1.1 — the examples".
  - **The checks:** 0.1.0's [check.py](../m5-release/check.py) found the body equal to the notes
    as a draft ([check-draft.txt](out/check-draft.txt)), and again once published with
    `--latest` ([check-published.txt](out/check-published.txt)).
  - **The links:** the published body, rendered ([body.html](out/body.html)), has two links,
    `blob/v0.1.1/docs/examples.md` and `blob/v0.1.0/CHANGELOG.md#known-limitations`. Each
    answers 200.
- **Step 9:**
  - The listings: GitHub's tarball, from `gh api repos/…/tarball/v0.1.1`
    ([github-tarball.txt](out/github-tarball.txt)), and `git archive v0.1.1`
    ([git-archive.txt](out/git-archive.txt)).
  - The tarball lists 828: its first entry is its folder, `…-chez-sqlite3-a0f55a4/`, and the
    other 827 are `git archive`'s, once that prefix is stripped. 0.1.0 listed 820.
  - 0.1.0's tarball came by the Release page's route, `archive/refs/tags/`, whose folder is
    `chez-sqlite3-0.1.0/`. The review listed that route for `v0.1.1` too: 828 entries, the
    folder `chez-sqlite3-0.1.1/`, and the same 827 under it.
  - Each holds `src/`, `docs/` with `examples.md`, `examples/`, README.org, `LICENSE` and
    CHANGELOG.md. `vendor/chez-srfi/` is the last entry, with nothing under it. The tag's
    `Akku.manifest` names 0.1.1.
  - The watched failure is 0.1.0's, run again:
    `git archive d23cfc5 | tar -t | grep -c -E '^(\.plans/.|AGENTS\.md$)'` gives 879.
- **Step 10:**
  - README.org's clone line ran verbatim on the host, with git 2.55.0
    ([clone.txt](out/clone.txt)). It printed git's "is not a commit!" warning and cloned a
    detached HEAD at `960d9f0`, as the quick start says it will.
  - In the clone, with the host's Chez 10.4.0, the quick start's first program printed
    `(#("bird" 2) #("cat" 4))`. `examples/basics.sps` printed its page's text block. Neither
    wrote anything on stderr.
