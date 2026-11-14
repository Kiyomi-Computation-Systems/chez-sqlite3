# M1 slice 4: the docs' mutation log

Each mutation ran in its own copy of the worktree (no `.git`), under
`/tmp/claude-1000/-home-kishu-src-chez-sqlite3/2a34ce20-2ac8-4a34-9128-3ab6746e1074/scratchpad/s4docs/NAME/`,
with `scripts/guix-env make test` run from the copy. Each ran after the
unmutated tree passed `make test` (22 suites, 0 failed). `tests/test-docs.sps`
holds 45 passing tests and `tests/test-reference.sps` 16.

## Red first

Before `docs/reference.md` was written, or with it empty or partial:

| Run | Suite | Summary |
|---|---|---|
| empty `reference.md` | test-reference | `pass 13, fail 3`: every export has an entry; the entries are the exports, whole; the signatures, whole |
| empty `reference.md` | test-docs | `pass 26, fail 1`: the docs have runnable examples at all |
| first two sections only, plus a planted `(+ 1 1) ;; => 3` block | test-reference | `pass 13, fail 3`, the same three |
| the same | test-docs | `pass 33, fail 2`: the planted example gives 2, not 3; the links `#the-library` and `#conditions` have no heading |

## Mutations

| Mutation | Copy | Failing tests | Summary |
|---|---|---|---|
| An entry dropped: `### sqlite-source-id` and its text removed | `dropped` | test-reference: every export has an entry; the entries are the exports, whole; the signatures, whole | `pass 13, fail 3`; `make test` ran 22, failed 1 |
| An extra entry: `### sqlite-bogus`, with a signature block, added | `extra` | test-reference: every entry is an export; the entries are the exports, whole. test-docs: the code-span name check (`sqlite-bogus` is no export) | reference `pass 14, fail 2`; docs `pass 44, fail 1`; failed 2 |
| A signature changed by one character: `sqlite-version : -> String` to `-> Strin` | `signature` | test-reference: the entries that differ, each with both; the signatures, whole | `pass 14, fail 2`; failed 1 |
| A broken link: README.org's `file:docs/reference.md` to `file:docs/referenc.md` | `badlink` | test-docs: every relative link resolves; README.org links every page of docs/ | `pass 43, fail 2`; failed 1 |
| A broken anchor: `(#the-library)` to `(#the-librar)` | `badanchor` | test-docs: every relative link resolves (names `#the-librar`, `no-such-anchor`) | `pass 44, fail 1`; failed 1 |
| A runnable example with a wrong result: `;; => (#f #t)` to `;; => (#t #t)` | `wrongresult` | test-docs: the runnable example at line 138 and at line 247 each give the result they state (two blocks share the text) | `pass 43, fail 2`; failed 1 |

Every mutation made `make test` exit 2, and each was caught by the suite
that owns the rule, as the table names. The extra entry is caught by both
suites, since its name sits in a heading's code span.

## A trap

`make test` does not need `.git` or the submodule's git state: a copy made
with `tar --exclude=.git` runs every suite.

## The review's fixes: test-reference no longer reads comments

`tests/test-reference.sps` compared each entry's signature with the comment above the export in
`src/chez-sqlite3.sls`, against AGENTS.md. It now follows chez-curl's `tests/test-reference.sps`: the
exports are what Chez's `library-exports` lists for `(chez-sqlite3)`, what each name is comes from
`eval` in the library's environment (procedure or value), every export has one entry and every
entry is an export, and a procedure's `NAME : TYPE` line has a `->` in its TYPE, a value's none.
The suite holds 14 tests now (it held 16), `test-docs` 49 (it held 45: four rows for the load).
`test-docs` also runs its examples in order, through a named let, and `reference.md` no longer
states the floor, nor says a guard catches a load.

Each mutation of the table above was rerun in a copy, on `test-reference` and `test-docs`:

| Mutation | Copy | Result |
|---|---|---|
| An entry dropped | `d-dropped` | test-reference: 2 failed (every export has an entry; the entries are the exports); test-docs passed |
| An extra entry | `d-extra` | test-reference: 2 failed; test-docs: 1 failed (the code-span name check) |
| A broken link | `d-badlink` | test-docs: 2 failed |
| A broken anchor | `d-badanchor` | test-docs: 1 failed |
| A wrong stated result (`;; => refused` to `refusedx`) | `d-wrongresult` | test-docs: 1 failed |
| A signature changed by one character, `-> String` to `-> Strin` | `d-signature-one-char` | **no longer applies**: passes in both suites. The type text is not compared with anything now, since the only oracle was the source's comment. Held instead by the two rows below |
| The arrow removed from a procedure's type | `d-no-arrow` | test-reference: 1 failed (new) |
| The line's name changed (`sqlite-versio : ...`) | `d-wrong-name` | test-reference: 1 failed (new) |
| The docs' guard around a direct call | `d-guard-direct` | test-docs: 2 failed (new) |
| The docs' guard answering another symbol | `d-guard-answer` | test-docs: 2 failed (new) |

The remaining out-of-reach case: a type that is wrong while its arrow is where it should be.

## The signature check, restored

The maintainer ruled on 2026-11-14 that the reference's signatures are held to the source's
`;; NAME : TYPE` comments, which are the contract (an exception in AGENTS.md). `tests/test-reference.sps`
reads them again, as text, up to the source's `(import` clause. Every earlier check stays; the export
names are still Chez's `library-exports`. Added: one reader test (`signature-comments`), and four tests:
the source is read and holds signature comments; every export has exactly one comment; no comment is
for a name that is not exported; and each entry's line equals its export's comment whole, the
differences listed with both texts. The suite holds 19 tests (it held 14), all passing; `make test`
ran 25 suites, 25 passed.

Each mutation ran in its own copy under the scratchpad's `s4sig/`, through the copy's `scripts/guix-env`.
Each failed the one test named, and no other (18 passed, 1 failed, in `test-reference`).

| Mutation | Copy | Result |
|---|---|---|
| The page's `sqlite-version : -> String` to `-> Strin` (the one-character mutation of the table above) | `page` | 1 failed: each entry's line is its source comment |
| The same change in the source comment alone | `src` | 1 failed: the same test, the page now being the one that differs |
| The comment of `sqlite-version-number` removed | `dropped` | 1 failed: every export has exactly one signature comment |
| A comment `;; ghost-name : -> String` for a name not exported, added in the export clause | `extra` | 1 failed: no signature comment is for a name that is not exported |

A comment for a name that is not exported should fail: the comments before the import clause are
the export clause's contract, so one for no export is stale (an export renamed or removed) or
misspelt, and the check on the exports alone would never see it. Comments past the import clause
are not scanned. The remaining out-of-reach case: a signature comment that is itself wrong.
