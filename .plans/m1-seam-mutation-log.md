# M1 seam mutation log

Evidence that `make check-seam` and its suite (`tests/test-check-seam.sps`) fail through the property
each rule claims to guard ([M1 plan](2026-11-13-m1-plan.md) §3.5, §4;
[ADR-0009](decisions/0009-written-fresh-as-chez-sqlite3.md), amended).

The program is chez-curl's `check-seam` at `79c6ced`, trimmed to one family: rules (c), (d) as the
boundary, (e) to (i) kept, (a), (b) and (j) dropped with chez-curl's two families and its hatch, and
(k) new (a macro that carries a library-only name out). The copy table, with each dropped piece and
what it protected, was reviewed before the code. Rules (k) and the matrices are this slice's own.

Each mutation was applied to its own copy of the working tree, made in the session scratchpad
without `.git`, `build/` or `.claude/`, and run through that copy's own `scripts/guix-env`. A driver
refused any edit whose text did not occur exactly once. The working tree was never edited by a
mutation. The counts below are read from the outputs.

## The suite

- **Red run,** `tests/test-check-seam.sps` against a stub `tests/check-seam.sps` that only exits 2:
  `# of expected passes 4`, `# of unexpected failures 63`, `suite-exit-status: exit 1 (pass 4, fail
  63, xpass 0)`. Every row that runs the program failed.
- **Final run:** 67 passed, 0 failed, in 5 s.
- **Rows:** 67: 42 fixture cases over 41 fixture directories (`names-refused` runs on both tables;
  6 cases run the variant program), the directory-of-cases row, 8 rows of the exact lists, 10 generated
  runs (the two complements, the positions, the two matrices), 2 empty and missing directory rows, 2
  usage rows, and 2 setup rows. The chez-curl fixtures that were dropped are named in the copy table.
- **`make test`:** 8 suites passed, `check-seam: the seam holds (2 libraries in 2 files checked)`.
- **`make check-test-fails`:** `make test failed, as it must, in all 12 cases`, the new `seam` case
  among them.

### The variant program

Only the names `src/` imports are allowed today (`allowed-chez-names`, six), and neither `(chez-sqlite3
private memory)` nor `(chez-sqlite3 private native)` exists. The names that rule (f) and rule (k) read
are not allowed yet, so through the real table they are refused as unlisted and no case could reach
those rules. The suite therefore also runs the program's own text, read as data, with
`allowed-chez-names` widened by every name in `library-only-chez-names`: the state the tables reach
when those libraries land. Rows on the variant say so in their names.

## Mutations

Every mutation failed the suite (exit 1), or `check-test-fails` (exit 2), by the rows named.

| # | Mutation | Guards | Result |
|---|---|---|---|
| M1 | `(chezscheme)` imported whole is passed | rule (c): the whole-library import | 61 passed, 6 failed: `chez-whole`, `second-library`, `lock-regular`, `lock-directory`, the first/middle/last import-clause row, the library complement |
| M2 | `(scheme)` no longer an alias of `(chezscheme)` | rule (c): the alias | 64 passed, 3 failed: `scheme-alias`, `chez-wrapped`, the library complement |
| M3 | `(rnrs eval)` passes | rule (c): `(rnrs eval)` | 65 passed, 2 failed: `rnrs-eval`, the library complement |
| M4 | an `only` over any library, not just `(chezscheme)`, is read as the allowed form | rule (c): wrappers over `(chezscheme)` | 66 passed, 1 failed: `chez-wrapped` |
| M5 | `eval` added to `allowed-chez-names` | the allowlist is exact | 60 passed, 7 failed: `names-several`, `names-denylisted`, `ftype-with-unlisted`, allowed equals `src/`'s imports, allowed written out, the name complement, the position row |
| M6 | the allowed-names test is skipped | the allowlist is read | 57 passed, 10 failed: 5 name fixtures, `names-refused` on both tables, `ftype-with-unlisted`, the name complement, the position row |
| M7 | rule (d) reads only the first identifier | the boundary: `(chez-sqlite3 util)` and the near names | 65 passed, 2 failed: `outside-family`, `outside-imports` |
| M8 | `(chez-sqlite3 private)`, with nothing after `private`, counts as private | the boundary: the bare private name | 66 passed, 1 failed: `outside-family` |
| M9 | any `(chez-sqlite3 x)` counts as public | the boundary: the one public library | 65 passed, 2 failed: `outside-family`, `outside-imports` |
| M10 | any unlisted library is imported freely | rule (e): the import allowlist | 64 passed, 3 failed: `outside-imports`, `unlisted-libraries`, the library complement |
| M11 | rule (f) no longer compares the library with the entry | rule (f): library-only names | 65 passed, 2 failed: `ftype-with-unlisted`, the name-by-library matrix (variant) |
| M12 | rule (g) sees plain exports only | rule (g): renamed exports | 65 passed, 2 failed: `export-chez` (variant), the re-export matrix (variant) |
| M13 | rule (g) sees renamed exports only | rule (g): plain exports | 64 passed, 3 failed: `export-chez`, the export-position row, the re-export matrix |
| M14 | rule (h) finds every import defined | rule (h): imports no library defines | 65 passed, 2 failed: `import-undefined`, `outside-imports` |
| M15 | rule (i) allows several libraries in a file | rule (i): one library per file | 65 passed, 2 failed: `second-library`, `off-path` |
| M16 | rule (i) allows a library off its name's path | rule (i): the path | 64 passed, 3 failed: `second-library`, `off-path`, `lock-symlink-live` |
| M17 | rule (k) is off | rule (k): macros exported by a library that imports a library-only name | 66 passed, 1 failed: `macro-export` |
| M18 | rule (k) refuses any exported macro | rule (k): a macro is legal in a library that imports no library-only name | 66 passed, 1 failed: `macro-internal` |
| M19 | rule (k) does not read a `begin` at the top of the body | rule (k): `define-syntax` inside `begin` | 66 passed, 1 failed: `macro-export` |
| M20 | rule (k) reads plain exports only | rule (k): a renamed macro | 66 passed, 1 failed: `macro-export` |
| M21 | a file with an unread extension is not named | `.ss`, `.scm`, `.sch`, `.so` and the rest | 64 passed, 3 failed: `unread-ss`, `unread-so`, `unread-extensions` |
| M22 | a `.#` link is skipped whether or not it dangles | the lock-file skip is for a dangling link only | 66 passed, 1 failed: `lock-symlink-live` |
| M23 | a symbolic link to a directory is read as a file | the link to a directory is named | 66 passed, 1 failed: `dir-symlink` |
| M24 | an `#!eof` literal ends the reading unnoticed | reading fails closed on `#!eof` | 66 passed, 1 failed: `eof-literal` |
| M25 | a file with no datum passes | no datum fails | 66 passed, 1 failed: `no-datum` |
| M26 | a directory with no library passes | no library fails | 65 passed, 2 failed: the empty-directory and missing-directory rows |
| M27 | an import that is no symbol is not named | the unreadable-import branch of rule (c) | 66 passed, 1 failed: `names-not-symbols` |
| M28 | `foreign-free` dropped from the table | the table, written out whole | 63 passed, 4 failed: `memory-native-listed`, the table row, the name-by-library matrix, the re-export matrix |
| M29 | `foreign-alloc` also allowed in native | the table, written out whole | 64 passed, 3 failed: `ftype-with-unlisted`, the table row, the name-by-library matrix |
| M30 | `foreign-alloc` added to `allowed-chez-names` with no library importing it | the allowlist is exactly what `src/` imports | 64 passed, 3 failed: allowed equals `src/`'s imports, allowed written out, the name complement |
| M31 | `check-seam` removed from `make test`'s prerequisites | `make test` runs it (`check-test-fails`, `seam` case) | `check-test-fails` exit 2: 11 cases ok, the `seam` case FAILED (`make test` exited 0) |
| M32 | the `check-seam` target reads `tests`, not `src` | `make test` reads `src/` (`check-test-fails`) | `check-test-fails` exit 2: 8 of 12 cases FAILED, each by `check-seam`'s count, 265 problems; the four cases that stop at `check-suites` are unaffected |

One row per rule at least: (c) M1 to M6 and M27; (d) M7 to M9; (e) M10; (f) M11, M28, M29; (g) M12, M13;
(h) M14; (i) M15, M16; (k) M17 to M20; the fail-closed rules M21 to M26; the allowed list M5, M6, M30;
and the prerequisite M31, M32.

## What the rows do not hold

- **A mutation that dropped a name from `allowed-chez-names`** needs no row: the exactness row names
  it, and M5 and M30 show the row fails.
- **Rule (k) reads `define-syntax` at the top of a body, and inside `begin`.** A `let-syntax`, or a
  macro-defining macro, binds syntax the program does not read. The program's header says so, and
  such a library is held by review.
- **`foreign-ref` and `foreign-set!` are native's alone.** If the string copy of ADR-0011 ends up
  in `memory`, the table is one entry to change.
