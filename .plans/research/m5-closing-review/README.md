# M5's closing review: the live check, the changelog rows and the fold row

Run on `c3df9de`: the suites and renders in the container (Chez 10.4.0, Guix's SQLite 3.53.1),
the live check and its loopback server on the host (dash, curl, `python3 -m http.server --bind
127.0.0.1`). Scratch lived under the worktree's `build/`.

## The live check

[`live-check.sh`](live-check.sh)` BASE [TAG]` asks whether the site at `BASE` is `TAG`'s,
`v0.1.0` unless given, by three clauses, each named when it fails: **pages**, each page and the
stylesheet answer 200; **links**, a link names a repository file at `blob/TAG/`, and every link
into the repository is one, or its home, or its clone URL; **clone**, every `git clone` of the
quick start, cut at the next tag, is `--branch TAG`'s line. Exit 0, 1, or 2 for a usage error.

Seven renders, each served as `serve-NAME/chez-sqlite3/`, as Pages serves a project site. The
release copy is `git archive c3df9de` with the release's edits from the review's dry run:
CHANGELOG.md's `[0.1.0]` entry, `Akku.manifest` at 0.1.0, both clone lines `--branch v0.1.0`.

| Serve | Render | Failed |
|---|---|---|
| `main` | `c3df9de`, `SITE_REF=main` | links, clone |
| `unbumped` | `c3df9de`, `SITE_REF=v0.1.0` | clone |
| `ref-main` | the release copy, `SITE_REF=main` | links |
| `missing` | `rel` without `libraries.html` and `style.css` | pages |
| `one-ref` | `rel` with one link made `blob/main/` | links |
| `two-clones` | `rel` with a second clone line, no `--branch` | clone |
| `rel` | the release copy, `SITE_REF=v0.1.0` | none: exit 0 |

Also: no argument, a base without its last `/` and a tag without its `v` each exit 2; a port
with no server fails every clause; `rel` checked for `v0.2.0` fails links and clone. Every run's
output is in [live-check-runs.out](live-check-runs.out).

## The changelog rows

`tests/test-manifest.sps` gains `changelog-problems` and its parts, and fourteen rows, 93 to 107:
`link-label`, `body-line?` and `latest-entry` on the suite's own lines, then `changelog-problems`
on its own changelogs, then on CHANGELOG.md. Watched failing:

- **On trees** holding what the suite reads, each run with its root as the working directory:
  today's and the release copy's pass; `bare-entry` (the review's plant: a bare
  `## [0.1.0] - 2099-12-31`, the manifest and clone lines at 0.1.0), the release copy without
  `[Unreleased]:`, with `[0.1.0]:` a compare, with its entry's body removed, and today's tree
  with an `[Unreleased]:` line each fail the CHANGELOG.md row by name. `c3df9de`'s suite passed
  `bare-entry`, 93 of 93.
- **On the helpers,** eleven plants in copies of the suite, each failing at least one row by
  name: `body-line?` always true, taking a link reference, or blind to a tab; `link-label`
  without the colon's space; `latest-entry` blind to a fence before the release, or inside the
  entry, or not stopping at the next `##`; no complaint before a release; a duplicate taken as
  one; a later release's link as a first's; `[Unreleased]` against `main`.

## The fold row

[`fold-past-last-step.sps`](fold-past-last-step.sps) sweeps `query-fold` as
`test-conveniences-engines` does, at the cache's default, cold then warm, and at the cache 0
([its output](fold-past-last-step.out)). Cold, fuels 109 to 111 expire between the last row's
procedure and the last step, and the resume raises closed; 112 and 113 expire past the last step,
before the fold's body has answered, and finalize the statement; 114 and 115 expire after it,
and give the statement back to the cache; each of 112 to 115 answers 6. At the cache 0 the
same four fuels finalize, so nothing seen tells them apart.

Three plants of `src/chez-sqlite3/private/conveniences.sls`, each reading the flag after the
last step and raising closed: in the loop's done branch, at the start of the body's consumer,
and after it sets `normal`. Each turned the finalized runs, cold 112 and 113 and warm 105 and
106, to closed, and left the cached ones, 114 and 115, and at the cache 0 the same two, answering
6. So an assertion at the cache 0 passes all three. The row holds the cache's default instead:
the fold sweep fails unless some run, cold or warm, expired, answered 6, and ended with its
statement finalized. It printed fuels `(105 106 112 113)` on the code and failed by name on each
plant; `c3df9de`'s suite passed the second plant, 14 of 14.
