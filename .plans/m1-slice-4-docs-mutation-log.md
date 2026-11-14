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
