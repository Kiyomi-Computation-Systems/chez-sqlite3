# M2 closing review mutation log

Evidence that each new row or check of the review's minor fixes fails through the property it names.
Format of [the M2 slice 4 log](m2-slice-4-mutation-log.md).

Every mutation ran in a whole copy of the tree (no `build/`, `.git` or `vendor/`), made under the
worktree's git-ignored `build/m2cr-fix/`, and its suite ran from inside the copy, with the
worktree's SRFI libraries. The row mutants ran on both libraries: the container's, and the floor
library `build/m2s1-floor/libsqlite3-floor.so`. Counts are the suites' own `# of expected passes`
and `# of unexpected failures`. None of it is in the repository.

## The red runs

| Suite or check | Red run | Against | Green run |
|---|---|---|---|
| `check-seam` rule (l), `test-check-seam` | 67 passed, 1 failed | the program without rule (l), the new `utf8-string` row alone | 68 passed |
| `test-statement`, the no-flags row | 75 passed, 1 failed, on each library | `prepare-statement` passing `SQLITE_PREPARE_NO_VTAB` (4) | 76 passed, on each library |

## 1. "No prepare flags": the row

`test-statement` has a row that prepares `select name from pragma_table_info('t')` through
`prepare-statement`, steps it three times, finalizes it, reads `select count(*)` from the same
function, and asserts the whole outcome: `((#t #t #f) 2 one-connection)`. Its first draft expected
`zero-counts` with the connection still open and failed on the real tree; the expectation was
corrected to `one-connection`, and the mutant was run again from a fresh copy.

| Mutant | Edit | Result, each library |
|---|---|---|
| `novtab` | the prepare's flags argument `0` becomes `4` | 75 passed, 1 failed: the row, which raised `sqlite-error` from `prepare-statement` |

## 2. "Never `utf8->string`": rule (l)

Rule (l) of `tests/check-seam.sps`: a library but `(chez-sqlite3 private native)` and `(chez-sqlite3
private utf8)` that holds the identifier `utf8->string` in its export, import or body forms is
named, once. The fixture tree `tests/fixtures/seam/utf8-string/` holds the three faults (a body, an
import with a rename export, a vector literal), the two libraries that pass, and a library of near
names, a string and a comment. `(chezscheme)` exports `utf8->string`, so the complement row, which
imports every name that is not allowed, now expects rule (l)'s line after its import lines.
The reader makes a cyclic datum in a fixture (`export-unreadable`), so the walk marks each pair and
vector it has seen.

| Mutant | Edit | Result |
|---|---|---|
| `seam-off` | rule (l) never runs | 66 passed, 2 failed: the `utf8-string` row and the complement row |
| `seam-wide` | `a-body` joins the allowed libraries | 67 passed, 1 failed |
| `seam-nonative` | native leaves the allowed libraries | 67 passed, 1 failed |
| `seam-noutf8` | utf8 leaves the allowed libraries | 67 passed, 1 failed |
| `seam-novec` | the walk skips vectors | 67 passed, 1 failed |
| `seam-nocycle` | the walk marks nothing seen | no verdict: the suite hung on the cyclic fixtures, and `timeout 200` killed it, exit 124 |
| `utf8seam` (the review's, on the real `src/`) | `statement-values.sls` decodes with `utf8->string` | `check-seam` exits 1, one problem naming `(chez-sqlite3 private statement-values)`; the real tree passes it |

`native.sls`'s comment on `sqlite3_column_name` now says the address is read by
`c-string->bytevector`. A comment: no row.

## 3. `finalize-handle!`

The handle is cleared straight after `sqlite3_finalize`, before the failure's message is read. The
raise it guards against, a read of the message that raises, cannot be caused on demand, so no row
can fail on it, and none was written. Every existing row passes: `make test` on both libraries.

## 4. `call-with-block`'s before thunk

A comment beside the thunk, saying that its refusal is latent while the catch-all guard of
`call-with-open-handle` is there. No row.

## 5 and 6. The docs and the README

`docs/reference.md` and `README.org` changed in prose only. `test-reference` (the signatures),
`test-docs` (every `scheme run` block) and `make check-floors` pass.

## Totals

- Row and check mutants: 8 (`novtab`, run on 2 libraries, and 7 for rule (l)), all failed by their
  row or check; `seam-nocycle` by a hang.
- `make test`: 38 suites passed, on each library. `test-statement` 76 passed, `test-check-seam` 68.
- `make test-memory MEMORY_SUITES='tests/test-statement.sps tests/test-check-seam.sps'`: 2 passed,
  `test-statement` 18 s, `test-check-seam` 13 s under the gate.
