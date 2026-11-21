# The release of 0.1.0

The M5 plan's §4.9, steps 1 to 10, as they ran on 2026-11-21, by the M3 session (the lead), the
M4 session checking each PR read-only. `v0.1.0` is the signed tag object `cfaf268` on `21b3e1b`,
the squash of PR #60.

## The two PRs

- **PR #59, `2c761d4`:** CHANGELOG.md's `[0.1.0]` entry, `Akku.manifest` at 0.1.0 and both clone
  lines at `--branch v0.1.0` (step 1). CI passed in all seven jobs on `10a9569`, whose tree is the
  squash's (step 3), and `main`'s push run passed too.
- **The lead's Opus review of `2c761d4`, after its merge and before the tag:** no blocker, one
  major. The entry's Engines limitation named 3 of the 5 verbs that don't survive an engine's
  preemption, leaving out `with-transaction` and `call-with-statement`. Its minors were the
  reference's "use the statement verbs", the close refusal's blobs, backups and full-text tables,
  and the older systems' second remedy.
- **The maintainer's answer** (2026-11-21): "Fix first, then tag", and "Skip the Mac rerun" for a
  text-only fix, so step 2 stands on `10a9569`.
- **PR #60, `21b3e1b`:** the fixes, then a second Opus review's, on its first head:
  - `call-with-statement`'s entry warns that a finalize failing at an expiry loses the engine;
  - `execute-script!`'s engine advice is to split the script and run each statement with
    `execute!`, since `prepare-statement` takes one statement;
  - the install remedy is Linux's, a Mac's list holding Apple's file alone.

  The M4 session checked both heads, and its engine probes found no sixth verb. CI passed in all
  seven jobs on `9cd055b`, and `main`'s push run on `21b3e1b`.

The probes behind the reference's new warning are in [probes/](probes/). Run each from the
repository's root inside `scripts/guix-env`, after `make deps` and `mkdir -p build/m5fixrev`:
`$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m5-release/probes/NAME.sps`.

- **`cws-lost.sps`:** the fault itself. `call-with-statement` answers
  `(caller-got (assertion "no engine active" ()))`, where the same work through
  `prepare-statement` answers `(done 2003 ((body-got (busy busy))))`.
- **`fold-lost.sps`:** `query-fold`'s sweep.
- **`window.sps` and `window2.sps`:** every other verb, which survives.

## The steps

| Step | What ran | Result |
|---|---|---|
| 1 | The release branch, CI | 7 of 7 on `10a9569`, and on `9cd055b` for #60 |
| 2 | The maintainer's Mac `make test` on `10a9569` | 93 of 93 with Apple's 3.51.0 and Homebrew's 3.54.1 ([outputs](../m5-mac/out/release/)) |
| 3 | The squashes, `main`'s push runs | `2c761d4` and `21b3e1b`, each 7 of 7, each tree the tested head's |
| 4 | Pages, the environment, the ruleset; the live check on loopback | as set; `SITE_REF=v0.1.0` exits 0, `SITE_REF=main` exits 1 on links |
| 5 | The tag, signed and pushed alone | `git tag -v`: a good signature, key `…8EAC5130`; read back |
| 6 | The tag's CI and Pages runs | 44924721168, 7 of 7; 44924721201, build and deploy |
| 7 | The live check at the site | exits 0; as `v0.2.0`, exits 1 on links and clone |
| 8 | The GitHub Release, 453822480 | draft, body byte-equal, published as the latest, read back |
| 9 | The archives, listed | 820 entries each, no `.plans/` or `AGENTS.md` |
| 10 | The README's clone line, verbatim; the first program | clones `21b3e1b`; prints `(#("bird" 2) #("cat" 4))` |

- **Step 2, the Mac:** Apple's run named the same 140 rows unavailable as the run after M4's
  closing review, line for line. The one suite added since is `test-site-testing`. Homebrew's run
  named none.
- **Step 4:**
  - The render is `SITE_REF=v0.1.0 make site` in the container, served by
    `python3 -m http.server --bind 127.0.0.1` from a folder holding it as `chez-sqlite3/`.
  - It ran on `2c761d4` and again on `21b3e1b`.
  - Outputs: [live-loopback-v0.1.0.txt](out/live-loopback-v0.1.0.txt) and
    [live-loopback-main.txt](out/live-loopback-main.txt).
- **Step 5:** `git ls-remote origin 'refs/tags/v0.1.0*'` listed `cfaf268` at `refs/tags/v0.1.0` and
  `21b3e1b` at `refs/tags/v0.1.0^{}`, as `git rev-parse` does locally. The tagger is the releases
  identity that signs chez-curl's tags. The key's passphrase came through GNOME's prompt.
- **Step 7:**
  - Outputs: [live-site.txt](out/live-site.txt) and
    [live-site-v0.2.0.txt](out/live-site-v0.2.0.txt).
  - The live `reference.html` compared equal, byte for byte, to step 4's render of `21b3e1b`.
  - The Pages API's `pages/builds/latest` answers 404 for a workflow deploy; that's expected.
- **Step 8, chez-curl ADR-0042's recipe:**
  - **The notes:** chez-curl's `extract.py v0.1.0 0.1.0` gave
    [notes-v0.1.0.md](out/notes-v0.1.0.md), 4486 bytes. That's the entry from its intro to its
    last bullet, with no link reference.
  - **The draft:** `gh release create v0.1.0 --verify-tag --draft`, titled with the tag message's
    subject.
  - **The checks:** [check.py](check.py) found the body equal to the notes, as a draft
    ([check-draft.txt](out/check-draft.txt)) and once published with `--latest`
    ([check-published.txt](out/check-published.txt)).
  - **The links:** all 22 rendered links name `blob/v0.1.0/`, none `untagged-` or `blob/main`, and
    each file exists at the tag.
- **Step 9:**
  - The listings: [github-tarball.txt](out/github-tarball.txt) and
    [git-archive.txt](out/git-archive.txt).
  - They're the same entries but the tarball's `chez-sqlite3-0.1.0/` prefix.
  - The watched failure is `git archive d23cfc5 | tar -t | grep -c -E '^(\.plans/.|AGENTS\.md$)'`,
    which gives the plan's 879. Without the `.` after `.plans/` the same command gives 880, since
    it counts the directory `.plans/` itself.
- **Step 10:**
  - The first program ran on the host's Guix Chez and in the container's floor Chez.
  - **The clone printed `warning: refs/tags/v0.1.0 cfaf268… is not a commit!`.** That's git 2.54's
    warning on any annotated tag given to `--branch`, since chez-curl's `v0.1.0` gives it too. The
    clone is right, detached at the tag (Open, in the ledger).
