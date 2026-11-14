# M1 slice 1 mutation log

Evidence that each rule the slice's five suites claim to guard fails through the property it names
([M1 plan](2026-11-13-m1-plan.md) §5, slice 1: the pure core). Format of
[the M0 closing review's log](m0-review-mutation-log.md).

The slice is `(chez-sqlite3 private libsqlite3-info)`, `conditions`, `load-state`, `discovery` and
`verify`, and their suites. A Sonnet agent built it from the copy table the maintainer corrected, test
first. Every mutation ran in its own copy of the working tree, made in the session scratchpad without
`.git`, `build/` or `.claude/`, through that copy's own `scripts/guix-env`, after `make deps` in the
copy. A mutation changes one place in one library under `src/`, the driver checks that the old text
occurs the stated number of times, and every one of the five suites then runs. The counts below are
read from the suites' own output (`# of unexpected failures`), never by eye. The driver and the
mutation definitions are in the session scratchpad, not the repository.

## The red runs

Each suite was written first and run against a stub library with the same exports: every procedure
answered the symbol `stub`, and the condition types were real. The stubs were then replaced.

| Suite | Red run, against the stub | Green run |
|---|---|---|
| `test-libsqlite3-info` | 1 passed, 8 failed | 9 passed |
| `test-conditions` | 2 passed, 16 failed | 18 passed |
| `test-load-state` | 1 passed, 13 failed | 14 passed |
| `test-discovery` | 2 passed, 57 failed | 59 passed |
| `test-verify` | 0 passed, 16 failed | 16 passed |

The rows that passed against a stub are rows a stub can satisfy. In `test-libsqlite3-info`, the one
row is the opacity row: `record-rtd` of the symbol the stub answers for a report raises, as it does
of an opaque report. In `test-conditions`, they are the root condition's rows, which use the real
type. In `test-discovery`, one is the real-maps row that only reads `/proc/self/maps`. A no-secret
row answers `no-raise` against a stub that raises nothing, which its expected value never equals,
so it fails there. The mutations below are what watch each of those rows fail: I1 for opacity, I4
and K10 for the secret.

## The mutations

Baselines, from the green runs: info 9, conditions 18, load-state 14, discovery 59, verify 16.
Each row names the suites that failed and how many rows failed in each. A mutation counts as
caught when at least one row failed.


### Discovery: candidate paths and their order

| Mutation | Guards | Failed |
|---|---|---|
| D1 | FHS: /usr/local/lib candidate dropped | discovery 9 |
| D2 | FHS: the triple directory dropped | discovery 9 |
| D3 | FHS: /usr/lib64 dropped | discovery 9 |
| D4 | FHS: /usr/lib dropped | discovery 10 |
| D5 | FHS: /usr/lib64 and /usr/lib in the wrong order | discovery 9 |
| D6 | FHS: the triple directory after /usr/lib64 | discovery 8 |
| D7 | FHS: /usr/local/lib after the triple directory | discovery 8 |
| D8 | FHS: a Guix profile appended to the FHS list | discovery 6 |
| D9 | FHS: soname libsqlite3.so, no .0 | discovery 9 |

### Discovery: Guix profiles

| Mutation | Guards | Failed |
|---|---|---|
| G1 | Guix: GUIX_ENVIRONMENT and GUIX_PROFILE swapped | discovery 6 |
| G2 | Guix: the home profile dropped | discovery 10 |
| G3 | Guix: ~/.guix-profile dropped | discovery 9 |
| G4 | Guix: /run/current-system/profile dropped | discovery 12 |
| G5 | Guix: ~/.guix-home and ~/.guix-profile swapped | discovery 9 |
| G6 | Guix: the system profile first | discovery 12 |
| G7 | Guix: a relative variable is accepted (absolute-or-false takes any) | discovery 4 |
| G8 | Guix: a standard directory appended to the Guix list | discovery 10 |
| G9 | Guix: GUIX_PROFILE not read | discovery 11 |
| G10 | Guix: HOME read after an unrelated LD_LIBRARY_PATH read | discovery 1 |

### Discovery: macOS

| Mutation | Guards | Failed |
|---|---|---|
| M1 | macOS: candidate has .0 in its name | discovery 4 |
| M2 | macOS: the candidate is asked exists? | discovery 1 |
| M3 | macOS: source symbol is system | discovery 5 |
| M4 | macOS: osx suffix not recognised | discovery 2 |

### Discovery: the platform

| Mutation | Guards | Failed |
|---|---|---|
| P1 | platform: a Linux machine type ending 6le only | discovery 4 |
| P2 | platform: an unknown platform gets the FHS list | discovery 1 |
| P3 | platform: choose on an unknown platform takes the FHS list | discovery 1 |

### Discovery: the world

| Mutation | Guards | Failed |
|---|---|---|
| W1 | world: the libc basename is not checked | discovery 3 |
| W2 | world: libc need not be under /gnu/store/ | discovery 12 |
| W3 | world: unreadable maps is guix | discovery 2 |
| W4 | world: only the first line is scanned | discovery 9 |
| W5 | world: the last line is not scanned | discovery 1 |
| W6 | world: the first line is not scanned | discovery 1 |
| W7 | world: a basename that ends with libc.so.6 is taken | discovery 1 |
| W8 | world: /gnu/store/ anywhere in the path is taken | discovery 12 |
| W9 | world: the world is guix on Linux whatever the text | discovery 15 |

### Discovery: the override

| Mutation | Guards | Failed |
|---|---|---|
| O1 | override: a slash anywhere makes a path absolute | discovery 4 |
| O2 | override: the empty string is absolute | discovery 2 |
| O3 | override: it is checked with exists? | discovery 2 |
| O4 | override: an invalid one falls back to the candidates | discovery 5 |
| O5 | override: the variable is chez-curl's | discovery 13 |
| O6 | override: the source is system | discovery 6 |
| O7 | override: a leading space is skipped | discovery 1 |

### Discovery: the triple table

| Mutation | Guards | Failed |
|---|---|---|
| T1 | triple: a6le unmapped | discovery 2 |
| T2 | triple: arm64le unmapped | discovery 2 |
| T3 | triple: the two triples swapped | discovery 10 |
| T4 | triple: a Linux riscv gets the x86 triple | discovery 2 |

### Discovery: not-found, precedence, sources, refusals

| Mutation | Guards | Failed |
|---|---|---|
| N1 | not-found: lists only the first candidate | discovery 4 |
| N2 | not-found: lists the candidates in reverse | discovery 4 |
| N3 | precedence: the last existing candidate wins | discovery 6 |
| N4 | not-found: raised with a path | discovery 6 |
| S1 | sources: macos-system missing | discovery 2 |
| S2 | sources: a candidate source misspelt (guix-home) | discovery 9 |
| S3 | sources: override first moved last | discovery 1 |
| R1 | refusal: who is chez-curl | discovery 1 |
| R2 | refusal: no message | discovery 1 |
| R3 | refusal: raised as a plain error, not the library-unavailable | discovery 12 |
| R4 | world check: libsqlite3-candidates accepts world #f on Linux | discovery 1 |

### Verify: the floor, threadsafe, the decoder

| Mutation | Guards | Failed |
|---|---|---|
| V1 | floor is 3045000 | verify 6 |
| V2 | floor is 3045002 | verify 6 |
| V3 | floor boundary: <= instead of < | verify 4 |
| V4 | floor boundary: > instead of < | verify 6 |
| V5 | floor compared on its last six digits only | verify 2 |
| V6 | floor compared on its millions digit only | verify 5 |
| V7 | floor compared with the units digit ignored | verify 4 |
| V8 | version number: no natural check | verify 1 |
| V9 | version number: an inexact one is a natural | verify 1 |
| V10 | threadsafe: a truthiness test, so 0 passes | verify 3 |
| V11 | threadsafe: 1 refused instead of 0 | verify 4 |
| V12 | threadsafe: 2 refused instead of 0 | verify 4 |
| V13 | threadsafe: 0 and 1 refused | verify 2 |
| V14 | threadsafe: 0 and 2 accepted-ness inverted: only 2 and above pass | verify 2 |
| V15 | threadsafe: a negative answer refused | verify 1 |
| V16 | threadsafe: no integer check | verify 1 |
| V17 | threadsafe: an inexact integer is an answer | verify 1 |
| V18 | threadsafe: detail is 1 | verify 2 |
| V19 | refusal drops the library (check-version and check-threadsafe) | verify 5 |
| V20 | refusal who is chez-curl | verify 1 |
| V21 | refusal: below-floor carries no detail | verify 4 |
| V22 | decoder: millions divisor wrong | verify 1 |
| V23 | decoder: thousands part not reduced | verify 1 |
| V24 | decoder: units part mod 100 | verify 1 |
| V25 | decoder: no natural check | verify 1 |

### Conditions: reasons, constructor, accessors, shown-value

| Mutation | Guards | Failed |
|---|---|---|
| K-invalid-override | reasons list lacks invalid-override | conditions 3, discovery 6 |
| K-not-found | reasons list lacks not-found | conditions 4, discovery 7 |
| K-load-failed | reasons list lacks load-failed | conditions 3 |
| K-below-floor | reasons list lacks below-floor | conditions 6, verify 5 |
| K-not-threadsafe | reasons list lacks not-threadsafe | conditions 3, verify 3 |
| K-missing-api | reasons list lacks missing-api | conditions 3 |
| K7 | reasons list has no-ssl in place of not-threadsafe | conditions 4, verify 3 |
| K8 | constructor takes any reason | conditions 2 |
| K9 | constructor takes any library | conditions 1 |
| K10 | checked-accessor names the value, not its kind | conditions 4 |
| K11 | checked-accessor does not check | conditions 4 |
| K12 | shown-value shows a string as itself | conditions 5 |
| K13 | shown-value shows any list as itself | conditions 2 |
| K14 | root is under &serious, not &error | conditions 2, load-state 3, discovery 1 |
| K15 | library-unavailable is under &error, not the root | conditions 1, discovery 1, verify 1 |
| K16 | reason accessor reads the path field | conditions 3, discovery 11, verify 5 |
| K17 | candidates accessor reads the detail field | conditions 2, discovery 11, verify 5 |
| K18 | kind-of: a string is other | conditions 5 |
| K19 | kind-of: () is other | conditions 1 |
| K20 | accessor refuses with the wrong who | conditions 2 |

### The report

| Mutation | Guards | Failed |
|---|---|---|
| I1 | the report is not opaque | info 1 |
| I2 | the report is not sealed | **none: survived** |
| I3 | info accessors do not check | info 4, conditions 1 |
| I4 | info accessors name the value | info 4, conditions 1 |
| I5 | info shown: a string shown as itself | info 2, conditions 1 |
| I6 | info shown: any list as itself | info 1, conditions 1 |
| I7 | info: path accessor reads the source field | info 2 |
| I8 | info: source-id accessor reads the version field | info 2 |

### Load-state

| Mutation | Guards | Failed |
|---|---|---|
| L1 | as-serious answers a non-serious object itself | load-state 7 |
| L2 | as-serious builds a plain &error | load-state 4 |
| L3 | load-step does not raise again | load-state 6 |
| L4 | load-step does not record | load-state 3 |
| L5 | a later failure replaces the first | load-state 2 |
| L6 | record-load-failure! takes a non-serious condition | load-state 1 |
| L7 | load-step raises the original object, not the serious one | load-state 6 |
| L8 | as-serious who is chez-curl | load-state 3 |
| L9 | load-step catches conditions only | load-state 5 |
| L10 | as-serious drops the object from the irritants | load-state 4 |
| L11 | load-failure answers a fresh #f | load-state 3 |

## Result

121 mutations, each in its own copy of the tree. 120 fail at least one row.
1 survives: I2.

- **I2 (the report is not sealed) cannot be caught from here.** `opaque` hides the record's type, and
  nothing without the type can name it as a parent, so no row can build a subtype of a report. The
  library keeps `(sealed #t)` as chez-curl's does, and says "sealed" only in a comment about opacity. A
  record that wants it held must make its type reachable to a test, which would undo opacity. Left as
  an unguarded claim.
- **Floor boundary.** V1 and V2 move the constant by one each way, V3 to V7 compare the wrong
  quantity (`<=`, `>`, the last six digits, the millions digit, the units digit ignored), and each
  fails.
- **threadsafe.** V10 (a truthiness test), V11 and V12 (the wrong value refused), V13 and V14 (a
  range), V15 (a negative refused), V16 and V17 (no integer check, an inexact one) each fail.
- **Order.** D5, D6, D7, G1, G5, G6 and N3 are order mutations of the lists and of the first-existing
  rule; each fails.
- **`checked-accessor` that names a string's value (K10)** fails the conditions suite, and I4 does the
  same for the report's accessors.

## What the records need

- **ADR-0013, decision 2:** a refusal at load, which no one procedure raises, names `chez-sqlite3` in
  its `&who` (done: the maintainer amended it).
- **ADR-0002, decision 4,** lists five reasons before its amendment; the amendment adds the sixth.
  The code's list is the amended one, in the order `invalid-override not-found load-failed below-floor
  not-threadsafe missing-api`.
- **Owed to slice 2,** since slice 1 cannot hold them: `native`'s first definition re-raising a
  recorded failure; the order floor, then threadsafe, then every other entry point; and
  `load-failed` and `missing-api`, which slice 1 only constructs.

## The review's fixes

An adversarial review of this slice ran further mutations of its own, in its own driver, and found
that many of them survived all five suites. The fixes below
are tests, and a few lines of source: one shared refusal builder, `raise-library-unavailable`, in
`conditions`, which `discovery` and `verify` now use in place of their private `refuse`; the
constructor's refusals name both irritants through `shown-value`; `check-version` takes any exact integer.
Each mutant ran again through the reviewer's driver, in its own copy of the fixed tree, and every one
of the five suites ran. A mutant of the review's names `x-...`; a control is `ctl-...`. Counts are
failed rows, read from the suites' own output (`# of unexpected failures`). "Before" is the tree
at the commit before the fixes, "after" the fixed tree.

Baselines, after: discovery 66, load-state 16, conditions 28, libsqlite3-info 9, verify 20 (before:
59, 14, 18, 9, 16).

| Mutant | What it changes | Before | After |
|---|---|---|---|
| `x-bare-override-searches-ldpath` | a non-absolute override is searched for in `LD_LIBRARY_PATH` | none | discovery 6 |
| `x-reads-ldpath-with-override` | the override branch also reads `LD_LIBRARY_PATH` | none | discovery 1 |
| `x-accessor-pair` | `checked-accessor` names a refused pair as itself | none | conditions 3 |
| `x-reason-ci` | a reason matched case-insensitively | none | conditions 1 |
| `x-reason-prefix` | a symbol starting with a reason's name is taken | none | conditions 1 |
| `x-library-boolean` | a refusal's library may be `#t` | none | conditions 1 |
| `x-gnu-prefix` | libc under `/gnu/` is Guix | none | discovery 1 |
| `x-gnu-noslash` | prefix `/gnu/store` without its slash | none | discovery 1 |
| `x-first-libc` | the first `libc.so.6` line alone decides | none | discovery 1 |
| `x-arm32-triple` | 32-bit ARM given the aarch64 triple | none | discovery 2 |
| `x-i3-triple` | `i3le` given the x86_64 triple | none | discovery 2 |
| `x-nt-linux` | a `...nt` machine type gets the FHS list | none | discovery 1 |
| `x-message-wording` | reworded messages only | conditions 7, info 3 (ten rows asserted text) | none: all five pass, as wanted |
| `x-version-negative-refused` | the review's: a negative number is `below-floor` (now the code's own rule), so redefined here as the old natural check restored | the review's original: verify 1, since the old row expected an assertion violation | verify 1 |
| `x-shown-pair` | `shown-value` tests `pair?` for `list?` | conditions: the suite died, 255, no test named | conditions 1, named |
| `x-ctor-raises` | the report constructor raises | conditions, info and verify died: 255, no test named | conditions 5, info 3, verify 8, named |
| `x-later-refusal-replaces` | a later `&sqlite-library-unavailable` replaces the first failure | none | load-state 2 |
| `x-as-serious-own-who` | `as-serious` keeps a non-serious condition's own `&who` | none | load-state 1 |
| `x-raise-continuable` | `load-step` raises again with `raise-continuable` | none | load-state 1 |
| `x-verify-source-from-report` | `check-version` takes the source from the report | verify 3 | verify 5 |
| `ctl-V3` | floor boundary `<=` | verify 4 | verify 4 |
| `ctl-W8` | `/gnu/store/` anywhere in the path | discovery 12 | discovery 14 |

"Before" for `x-bare-override-searches-ldpath`, `x-reads-ldpath-with-override`, `x-message-wording`,
`ctl-V3`, `ctl-W8` and `x-accessor-pair` was measured again here on the commit before the fixes; the
others are the review's own batch outputs. A rise is the new rows that also hold the rule.

New mutants, for what the fixes added; each fails at least one row:

| Mutant | What it changes | Before | After |
|---|---|---|---|
| `x-version-string-unchecked` | `check-version` does not check its version string | not a rule | verify 2 |
| `x-rlu-no-who` | `raise-library-unavailable` has no `&who` | not built | discovery 1, conditions 2, verify 1 |
| `x-rlu-who-curl` | its `&who` is `chez-curl` | not built | discovery 1, conditions 2, verify 1 |
| `x-rlu-no-message` | it has no `&message` | not built | discovery 1, conditions 2, verify 1 |
| `x-rlu-library-dropped` | it drops the report | not built | conditions 2, verify 6 |
| `x-rlu-irritants-dropped` | it drops the irritants | not built | conditions 1 |
| `x-rlu-raise-continuable` | it raises continuably | not built | conditions 1 |
| `x-ctor-reason-raw` | the constructor names the raw reason | not built | conditions 3 |
| `x-ctor-irritant-raw` | the constructor names the raw library | not built | conditions 3 |

Notes on rows the review's list left out:

- `x-message-wording` passes all five suites, so no row asserts message text any more (ADR-0013,
  decision 9). Presence of a `&message` is a type, and stays asserted.
- The review's `log-...` rebuilds of this log's own rows were not rerun: each already failed a row in
  its batch, and the fixed suites are those rows plus more.
- `x-version-negative-refused` of the review is the old design (a negative number refused as an
  assertion violation) turned the other way; after the fix `check-version` refuses it as `below-floor`,
  and the mutant here restores the old natural check, which fails verify 1.

### Red run, corrected

The red run of `test-libsqlite3-info` against the stub was rebuilt as the section above describes
(every procedure answers `stub`; the stub is `s1/stubs/red-info-head` for the suite at the commit
before the fixes, `red-info-fixed` for the fixed one): **1 passed, 8 failed**, for both. The row that
passes is the opacity row. The table above says so now; it said 2 and 7.

### What the records need

- ADR-0013, decision 2: done. The maintainer amended it, and the line above says so.
- ADR-0013, decision 9 holds in the suites now: no test of this slice reads message text.
- Slice 2's native load uses `raise-library-unavailable` and refuses a library whose
  `sqlite3_libversion` or `sqlite3_sourceid` answers NULL as `load-failed`, with the entry point's C
  name as detail. A missing report entry point is `missing-api` with library `#f`, since the report
  does not exist yet.
