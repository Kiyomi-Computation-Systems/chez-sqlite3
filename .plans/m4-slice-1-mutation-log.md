# M4 slice 1 mutation log

Evidence that each rule slice 1's rows claim to guard fails through the property it names
([the M4 plan](2026-11-17-m4-plan.md) §5, item 1, and §4.7). Format of
[the M3 slice 6 log](m3-slice-6-mutation-log.md). An Opus agent built the slice from the lead's
brief, in the worktree `chez-sqlite3-wt-m4s1`, on `m4-slice-1-core`. Its base is `87e762c`,
`main`, whose tree, `e2e99d2`, is that of slice 0's head `fd4831c`, on which the slice was built;
`fd4831c` is reachable from no ref now. Part B holds the fixes of the slice's review (Opus,
read-only).

## What the slice adds

- **`(chez-sqlite3 private settings)`:** the four `db_config` settings (ADR-0021, decisions 1
  to 3 and 5; ADR-0018, amended for M4), exported beside `setting-names` and not in it. No
  foreign code; every procedure answers data for any argument and raises nothing, so slice 3 may
  call each inside a critical section:

  ```scheme
  ;; db-config-settings : (Listof (List Symbol Natural (Listof Boolean)))
  ;; db-config-setting-names : (Listof Symbol)
  ;; db-config-sentinel : Integer
  ;; Db-Config-Step = (List Symbol Natural (U 0 1) Boolean)
  ;; db-config-step : Any Any -> (U Db-Config-Step 'no-call 'out-of-domain 'not-db-config)
  ;; db-config-verdict : Any Any Any Any
  ;;                     -> (U 'match (List 'mismatch Any Any Any) (List 'error Any))
  ```

  - **The table,** in the plan's order: `(enable-load-extension 1005 (#t #f))`,
    `(defensive 1010 (#t #f))`, `(dqs-dml 1013 (#t #f))`, `(dqs-ddl 1014 (#t #f))`. The names
    are the table's `car`s.
  - **The step,** `(db-config-step name value)`: `(name op written expected)`, written 1 for
    `#t` and 0 for `#f`, expected the value given; `no-call` for `(enable-load-extension . #f)`
    (Q15); `out-of-domain` for any value but `#t` and `#f`; `not-db-config` for any name but the
    four, at any value, the name told before the value. Its `car` is the name and its `cadddr`
    the value expected, as in a PRAGMA's step, `(name set-sql read-sql expected)`; the `cadr`, an
    integer op or a string of SQL, tells them apart.
  - **The verdict,** `(db-config-verdict name expected code cell)`: any code but an exact 0 is
    `(error code)`, whatever the cell; code 0 and the cell the value written is `match`; code 0
    and any other cell is `(mismatch name expected actual)`, the fields of
    `&sqlite-setting-mismatch`, `actual` `()` for the sentinel, `#t` for 1, `#f` for 0, anything
    else as itself. An expected value that is no boolean matches no cell.
  - **The sentinel,** `-1`: below.
- **`(chez-sqlite3 private conditions)`:** `&sqlite-extensions-unavailable` under
  `&chez-sqlite3-error`, no field (ADR-0021, decision 10; ADR-0013, amended for M4), and a raise
  helper beside its maker and predicate, as each fieldless type has one:

  ```scheme
  ;; make-sqlite-extensions-unavailable : -> &sqlite-extensions-unavailable
  ;; sqlite-extensions-unavailable? : Any -> Boolean
  ;; raise-extensions-unavailable : Symbol -> Nothing
  ```

  `raise-extensions-unavailable` compounds the type with `&who` WHO and a fixed `&message`, and
  refuses a WHO that is no symbol, as `raise-transaction-ended` does. Nothing is exported from
  `(chez-sqlite3)`: slice 3 does that.
- **The suites:** `test-settings`, 15 rows and its exports row; `test-conditions`, 10 rows, a
  fifteenth column in the matrix, and the rows that read it; `test-open-settings`, 2 rows.

`open.sls`, `connection.sls`, `native.sls`, `(chez-sqlite3)`, the Makefile, CI and `docs/` are
unchanged. No suite is new.

### The sentinel: the core's constant

`db-config-sentinel` is a constant the core owns, not an argument. The sentinel's whole job is a
fact about `db_config`: the call writes 0 or 1 to the cell whatever it is given (M4's research,
D6), so a cell still holding anything else was left by it. The shell fills the cell with it and
the verdict reads it, so the two are one value by construction: given an argument, the verdict
would hold whatever value a caller passed, and the fill could be another. And a verdict that takes
no sentinel can't be handed a 0 or a 1, so it needs no refusal of its own, which a total
procedure could only answer as data for slice 3 to raise. The rule a sentinel keeps is held
instead by a row, `s-sentinel`: an exact integer a C int holds, −2³¹ to 2³¹−1, so the counted
`int` block holds it as written and `foreign-set!` can't raise inside the section, and neither 0
nor 1. Z0, Z1, Z2 and Z3 fail it, and Z0 and Z1 fail three verdict rows besides.

## How the mutants ran

Every mutation ran in a copy of the worktree of its own, made by
`tar --exclude=./build --exclude=./.git`, its edits each checked to match its file's text exactly
once before it was written: `build/mut/NAME/` at first, and `build/mut-r2/NAME/` for the counts
below, every mutant run again on the reviewed suites. Each copy ran `make deps` and its suites through
`$CHEZ --libdirs src:tests:build/scheme-libs --program`, each under `timeout 300`, inside one
`scripts/guix-env` run from the worktree, six copies at a time by `xargs -P 6`, on Guix's
3.53.1. The counts are read from the suites' own output (`# of unexpected failures`), never by
eye; no mutant died or hung, and red A's two deaths are its finding. Each mutant ran `test-settings`, `test-conditions` and
`test-open-settings` unless the table names its suites.

The driver is kept in [research/m4-slice-1/scripts/](research/m4-slice-1/scripts/): `mut.py`
makes the copies and their `run.sh`, and reads their counts; `mutants.py` holds every plant's
edits; `labels.py` names each copy's failing rows by this log's labels; `table.py` writes the
table below from them; `all-names.txt` lists the mutants. Each runs from the worktree's root,
the tree its working directory, `-B` so that no bytecode is left beside them:

```sh
D=.plans/research/m4-slice-1/scripts
python3 -I -B $D/mut.py --into build/mut-r2 prepare $(cat $D/all-names.txt)
python3 -I -B $D/mut.py --into build/mut-r2 red 87e762c       # REDA and REDB, from git
python3 -I -B $D/mut.py --into build/mut-r2 before 87e762c    # BEFORE, for the gate's times
python3 -I -B $D/mut.py --into build/mut-r2 scripts $(cat $D/all-names.txt) REDA REDB
scripts/guix-env sh -c 'ls build/mut-r2/*/run.sh | xargs -P 6 -n 1 sh'
python3 -I -B $D/labels.py --into build/mut-r2 $(cat $D/all-names.txt) REDA REDB
```

## The red runs

The rows were written first. Two red runs, each on a copy holding the tree's suites:

- **Red A,** the base's `settings.sls` and `conditions.sls`, the code as it stands;
- **Red B,** the same with the new exports stubbed, each present and wrong: the table and the
  names `'()`, the sentinel 0, the step and the verdict raising, the type under `&error`, its
  raise `(raise 'stub)`. So every new row runs, and fails by name or not.

| Suite | The base's own | Red A | Red B | Green |
|---|---|---|---|---|
| `test-settings` | 59 passed | died at expansion, no row run: "attempt to reference unbound identifier db-config-step" | 62 passed, 12 failed | 74 passed |
| `test-conditions` | 83 passed | died at expansion, no row run: "… make-sqlite-extensions-unavailable" | 84 passed, 9 failed | 93 passed |
| `test-open-settings` | 23 passed | 25 passed | 25 passed | 25 passed |

Red B's failures, by the labels of the mutation table below: `test-settings`' `s-table`,
`s-names`, `s-steps`, `s-domain`, `s-complement`, `s-every`, `s-sentinel`, `s-verdict`,
`s-left`, `s-outside`, `s-matrix` and `s-total`; `test-conditions`' `c-matrix`, `c-parent`,
`c-kind`, `c-raise`, `c-who`, `c-simple`, `c-message`, `c-messages` and `c-refuse`.

Against red A, a suite that names the new exports dies at expansion, before its first row: Chez
refuses a reference to a name no import binds even inside a procedure body never called (the
trap below). So red A names no row of those two suites, and red B is what shows each row failing
by name. `test-open-settings`' two rows pass on the code as it stands, as the plan says the
`:memory:` row does: they hold the four out of the live list. J1, J2 and J3 fail both, and J5
the file's.

The rows that passed red B each failed against a plant (the table below): `s-exports` (E2),
`s-ops` (F1), `s-out` (J1), `s-plan-ops` (J4); `c-exports` (E3), `c-false8` and `c-false`
(C14), `c-fields` (C5), `c-return` (C10), `c-accessors` (C1, C2), and the four rows that read
the matrix's new column, `c-col` (C4, C14).

## Green, the floor and the gate

`make test` ran 73 and passed 73 on Guix's 3.53.1, as before the slice, on the suites as built
and again on the reviewed ones. At the floor, 3.45.1, through `CHEZ_SQLITE3_LIBRARY` and
`C_INCLUDE_PATH` set to `build/m3-floor`, `make test` with the three suites ran 3 and passed 3,
each at its count above, both times. Under `make test-memory`, each suite passed with 0 errors
and nothing definitely lost, none `SLOW`, by the gate's `time:` lines and its Valgrind logs. The
plain times are a suite's whole run, measured around it, twice on each library; each cell gives
the run on the suites as built, then the run on the reviewed suites:

| Suite | Rows | Plain, 3.53.1 | Plain, 3.45.1 | Gate, 3.53.1 | Gate, 3.45.1 | Gate before, the base, 3.53.1 |
|---|---|---|---|---|---|---|
| `test-settings` | 74 | 0.28, 0.29 s; 0.30, 0.29 s | 0.27, 0.29 s; 0.27, 0.28 s | 10 s; 10 s | 10 s; 10 s | 10 s; 10 s |
| `test-conditions` | 92; 93 | 0.25, 0.26 s; 0.25, 0.28 s | 0.25, 0.26 s; 0.24, 0.24 s | 9 s; 9 s | 9 s; 9 s | 8 s; 11 s |
| `test-open-settings` | 25 | 2.14, 2.16 s; 2.14, 2.16 s | 2.15, 2.15 s; 2.13, 2.13 s | 14 s; 14 s | 14 s; 14 s | 14 s; 16 s |

So the slice moves no suite's gate time beyond the gate's own spread, the base's suites
themselves 8 to 11 s and 14 to 16 s from one run to the next, and no shard line changes.

## The mutations

The rows, by label. `test-settings`: `s-exports` the library's exports; `s-table` and
`s-names` the table and the names written out; `s-ops` the headers' 24 ops, the suite's own
fixture; `s-out` the four out of `setting-names` and refused by `settings-plan`; `s-steps` each
step written out; `s-domain` each of the four against the universe; `s-complement` every other
name at `#t` and `#f`; `s-every` other names at every value; `s-plan-ops` every other op
refused by `settings-plan`; `s-sentinel` the sentinel's shape; `s-verdict` the verdict written
out; `s-left` a cell left at the sentinel; `s-outside` a value asked outside the domain;
`s-matrix` the verdict over every code and cell; `s-total` nothing raised. M3's `s-setting-names`
and `s-no-row` read `setting-names` too. `test-conditions`: `c-exports`; `c-matrix`; `c-false8`
the eight predicates on non-conditions; `c-false` the new predicate against every other value
and condition; `c-parent`; `c-fields`; `c-kind` the made condition's kinds; `c-raise` the
raise's whole compound; `c-who`; `c-simple` its three simple conditions; `c-message` its message
the same from both verbs; `c-messages` each fixed-message raise helper's message a string, not
empty, and no other helper's; `c-refuse` a who that is no symbol; `c-return` non-continuable;
`c-accessors` other types' accessors refuse it; `c-col` the four M3 rows that read the matrix's
new column. `test-open-settings`: `o-memory` the four refused on `:memory:`, nothing counted;
`o-file` the same on a file, no file made; M3's `o-refusals` and `o-order`.

| Plant | What it plants | Failed |
|---|---|---|
| D1 | the four's domain loosened: each `(#t #f)` in the table made `(#t #f 0 1)` | settings 2 of 74: `s-table`, `s-domain` |
| D2 | the step's domain check dropped: any value a step, written by its truth | settings 1 of 74: `s-domain` |
| S1 | a step made for `(enable-load-extension . #f)`: the no-call clause dropped | settings 2 of 74: `s-steps`, `s-domain` |
| V1 | the verdict ignores the code: its error clause dropped | settings 3 of 74: `s-verdict`, `s-outside`, `s-matrix` |
| V2 | the verdict ignores the cell: code 0 always a match | settings 4 of 74: `s-verdict`, `s-left`, `s-outside`, `s-matrix` |
| Z0 | a sentinel of 0 | settings 4 of 74: `s-sentinel`, `s-verdict`, `s-left`, `s-outside` |
| Z1 | a sentinel of 1 | settings 4 of 74: `s-sentinel`, `s-verdict`, `s-left`, `s-outside` |
| J1 | the four joined to `setting-names` early | settings 3 of 74: `s-setting-names` (M3), `s-no-row` (M3), `s-out`; open-settings 2 of 25: `o-memory`, `o-file` |
| C1 | the condition made an `&sqlite-error`, its maker filling the fields | conditions 5 of 93: `c-matrix`, `c-parent`, `c-kind`, `c-raise`, `c-accessors` |
| C2 | the condition made an `&sqlite-library-unavailable`, its maker filling the fields | conditions 5 of 93: `c-matrix`, `c-parent`, `c-kind`, `c-raise`, `c-accessors` |
| T1 | `dqs-dml`'s and `dqs-ddl`'s ops swapped | settings 3 of 74: `s-table`, `s-steps`, `s-domain` |
| T2 | `enable-load-extension`'s op 1017, `TRUSTED_SCHEMA`'s | settings 3 of 74: `s-table`, `s-steps`, `s-domain` |
| T3 | the table's order: `defensive` first | settings 2 of 74: `s-table`, `s-names` |
| T4 | a fifth entry, `(trusted-schema 1017 (#t #f))`, the op Q7 declined | settings 5 of 74: `s-table`, `s-names`, `s-out`, `s-complement`, `s-every` |
| T5 | a name misspelt, `enable-load-extensions` | settings 5 of 74: `s-table`, `s-names`, `s-steps`, `s-domain`, `s-complement` |
| T6 | `defensive`'s domain narrowed to `(#t)` | settings 3 of 74: `s-table`, `s-steps`, `s-domain` |
| N1 | the names written out, `dqs-ddl` missing | settings 1 of 74: `s-names` |
| S2 | no call for every `#f`, Q15's rule over all four | settings 2 of 74: `s-steps`, `s-domain` |
| S3 | no call for `enable-load-extension` at all, its `#t` too | settings 2 of 74: `s-steps`, `s-domain` |
| S4 | the value written inverted, 0 for `#t` | settings 2 of 74: `s-steps`, `s-domain` |
| S5 | the step's expected the integer written, not the value | settings 2 of 74: `s-steps`, `s-domain` |
| S6 | a name none of the four answered `out-of-domain` | settings 2 of 74: `s-complement`, `s-every` |
| S7 | a value outside the domain answered `no-call` | settings 1 of 74: `s-domain` |
| S8 | every step's op 1005 | settings 2 of 74: `s-steps`, `s-domain` |
| S9 | the opt-in's no-call for any value but `#t`, before the domain check | settings 1 of 74: `s-domain` |
| Z2 | a sentinel of 2^31, past a C int | settings 1 of 74: `s-sentinel` |
| Z3 | a sentinel of -1.0, inexact | settings 1 of 74: `s-sentinel` |
| Z4 | the verdict's sentinel -2, the export's -1: the fill and the reading apart | settings 4 of 74: `s-verdict`, `s-left`, `s-outside`, `s-matrix` |
| V3 | the code tested by `=`, so a non-number raises and 0.0 is 0 | settings 2 of 74: `s-matrix`, `s-total` |
| V4 | the code's low byte tested, so 256 is ok | settings 1 of 74: `s-matrix` |
| V5 | the match's boolean guard dropped | settings 1 of 74: `s-outside` |
| V6 | the cell compared with the value asked, not the value written | settings 3 of 74: `s-verdict`, `s-outside`, `s-matrix` |
| V7 | a cell left at the sentinel read as itself, not `()` | settings 3 of 74: `s-left`, `s-outside`, `s-matrix` |
| V8 | 1 and 0 read as themselves, not `#t` and `#f` | settings 3 of 74: `s-verdict`, `s-outside`, `s-matrix` |
| V9 | 1 read as `#f` and 0 as `#t` | settings 3 of 74: `s-verdict`, `s-outside`, `s-matrix` |
| V10 | any other cell read as `()` | settings 3 of 74: `s-verdict`, `s-outside`, `s-matrix` |
| V11 | the mismatch's expected the integer written | settings 4 of 74: `s-verdict`, `s-left`, `s-outside`, `s-matrix` |
| V12 | the mismatch's setting `db-config`, not the name | settings 4 of 74: `s-verdict`, `s-left`, `s-outside`, `s-matrix` |
| V13 | the error's code the cell | settings 2 of 74: `s-verdict`, `s-matrix` |
| V14 | the match tested before the code | settings 5 of 74: `s-verdict`, `s-left`, `s-outside`, `s-matrix`, `s-total` |
| V15 | the sentinel tested after 0 and 1 | **survived** |
| J2 | J1, and each of the four given a PRAGMA in `enumerated-settings`: the open runs `PRAGMA defensive = 1` as SQL | settings 3 of 74: `s-setting-names` (M3), `s-no-row` (M3), `s-out`; open-settings 2 of 25: `o-memory`, `o-file` |
| J3 | the four accepted by `settings-plan` and dropped, no step: the open succeeds and sets nothing | settings 1 of 74: `s-out`; open-settings 2 of 25: `o-memory`, `o-file` |
| J4 | `enable-fkey`, another op's name, joined to `setting-names` | settings 3 of 74: `s-setting-names` (M3), `s-no-row` (M3), `s-plan-ops` |
| C3 | the type's parent `&error`, not the root | conditions 5 of 93: `c-matrix`, `c-parent`, `c-kind`, `c-raise`, `c-who` |
| C4 | the predicate the root's, `chez-sqlite3-error?` | conditions 5 of 93: `c-matrix`, `c-col` |
| C5 | a field, `library`, its maker filling it | conditions 1 of 93: `c-fields` |
| C6 | the raise's `&message` made `&irritants` | conditions 4 of 93: `c-raise`, `c-simple`, `c-message`, `c-messages` |
| C7 | the raise's `&who` dropped | conditions 3 of 93: `c-raise`, `c-who`, `c-simple` |
| C8 | the raise's who always `open-database` | conditions 1 of 93: `c-who` |
| C9 | the raise's who check dropped | conditions 1 of 93: `c-refuse` |
| C10 | `raise-continuable` for `raise` | conditions 1 of 93: `c-return` |
| C11 | the message led by the who, so not fixed | conditions 1 of 93: `c-message` |
| C12 | an `&irritants` of the who compounded too | conditions 2 of 93: `c-raise`, `c-simple` |
| C13 | the raise makes an `&sqlite-transaction-ended` | conditions 2 of 93: `c-raise`, `c-simple` |
| E1 | `(chez-sqlite3)` exports `sqlite-extensions-unavailable?` early, signature comment and all | public 2 of 22: `public-count`, `public-list`; reference 2 of 20: `reference-entries`, `reference-exports` |
| E2 | settings.sls exports `step-for` too | settings 1 of 74: `s-exports` |
| E3 | conditions.sls exports `check-raise-who` too | conditions 1 of 93: `c-exports` |
| F1 | in the copy's `test-settings`, the suite's own fixture: `fp-digits` dropped from the headers' ops | settings 1 of 74: `s-ops` |
| S10 | the domain checked before the name, against a fixed `(#t #f)` | settings 1 of 74: `s-every` |
| J5 | in a copy of `open.sls`, the open made before the checks' refusal and closed before it is raised | open-settings 3 of 25: `o-refusals` (M3), `o-file`, `o-order` (M3) |
| C14 | the predicate `condition?` | conditions 8 of 93: `c-matrix`, `c-false8`, `c-false`, `c-col`, `c-simple` |
| P-TOP | the review's: `setting-names` made improper, `(... trusted-schema . statement-cache)` | settings 18 of 74: `s-setting-names` (M3), `s-no-row` (M3), `s-out`, `s-plan-ops`, and 14 of M3's rows that plan a list; open-settings 9 of 25: `o-refusals` (M3), `o-memory`, `o-file`, and 6 of M3's rows that open with a list; no suite died |
| P-MSG | the review's: the new type's fixed message `""` | conditions 1 of 93: `c-messages` |
| P-MSG2 | the review's: the new type's fixed message `&sqlite-closed`'s | conditions 1 of 93: `c-messages` |
| P-MSG3 | `raise-transaction-ended`'s fixed message `""` | conditions 1 of 93: `c-messages` |
| P-MSG4 | `raise-transaction-ended`'s fixed message `&sqlite-closed`'s | conditions 1 of 93: `c-messages` |

**67 mutations: 66 caught, one survived, equivalent.** The brief's are D1 and D2 (the domain
loosened), S1 (a step for `(enable-load-extension . #f)`), V1 and V2 (a verdict that ignores the
code, the cell), Z0 and Z1, J1, C1 and C2. P-TOP, P-MSG and P-MSG2 are the slice's review's,
P-MSG3 and P-MSG4 the builder's beside them (part B). The table's counts are the second run's,
on the reviewed suites; the first, on the suites as built, differed only where part B says.

Which rows: a plant at the table fails `s-table` and what reads the entry it changed. A step's
plants fail `s-steps` when they change a step of `#t` or `#f`, and `s-domain` always; S7 and S9
change only values outside the domain, and D2 a refusal into a step, so `s-domain` alone holds
them. S6 and S10 change only names that are none of the four; S10, the domain checked first
against a fixed `(#t #f)`, answers right at `#t` and `#f`, so only `s-every`, which tries other
names at every value, holds it. A verdict's plants fail `s-matrix` and the written rows; V4
(256's low byte taken as ok) only `s-matrix`, whose codes hold 256, and V5 (the boolean guard
dropped) only `s-outside`. Z2 and Z3 fail `s-sentinel` alone: the suite reads the sentinel from
the library and hands it back as the cell, so a sentinel a C int can't hold as written, 2³¹ or
−1.0, still matches itself there. In slice 3's shell neither could come back from an `int` cell
as itself, so a left cell would never answer `()`, or the write would raise inside the section:
not measured, since the shell isn't built. The shape row is what holds it. J5, a copy of `open.sls`
whose open is made before the checks' refusal and closed before it is raised, passes `o-memory`:
the counts are zero at the raise and `:memory:` leaves nothing. `o-file` fails it, the file made,
as M3's `o-refusals` does; `o-file` was added for it.

## The survivor, argued

- **V15, the sentinel's test moved after 0's and 1's in the verdict's mapping,** is equivalent
  while the sentinel is neither 0 nor 1: the three tests are then disjoint, so no cell meets two
  and their order can't change an answer. Tried against concrete input: this program, run with
  `--libdirs src` in the tree and in V15's copy, printed ten lines, identical in both,
  `(#t -1 (mismatch defensive #t ()))` first:

  ```scheme
  (import (rnrs) (chez-sqlite3 private settings))
  (for-each (lambda (value)
              (for-each (lambda (cell)
                          (write (list value cell (db-config-verdict 'defensive value 0 cell)))
                          (newline))
                        (list db-config-sentinel 0 1 2 -2)))
            '(#t #f))
  ```

  Only a sentinel of 0 or 1 makes the order matter, and Z0 and Z1 fail `s-sentinel` whatever the
  order.

## Part B: the review's fixes

The slice's review (Opus, read-only) found three faults. Each is fixed in the tree, and every
mutant ran again on the reviewed suites, in `build/mut-r2/`.

1. **A top-level definition read the library outside a guard.** `test-settings`'
   `not-db-config-names` appended the library's `setting-names` at top level, so the review's
   P-TOP, `setting-names` made improper, ended the suite with exit 255, naming no row, its last
   ten rows never run: AGENTS.md's rule on a suite's top-level definitions, broken. And
   `s-complement` and `s-every` took the list's seven from `setting-names`, so slice 3's correct
   join, which puts the four there, would fail both: J1 and J2 failed them in the first run. Both
   now take the seven from the suite's own `names`, written out, and the suite's top-level
   definitions read the library only by a variable reference or under a guard. Against P-TOP the
   suite now runs all 74 rows and fails 18 by name; J1 and J2 no longer fail `s-complement` or
   `s-every`, and fail `s-out`, the hold-out row slice 3 replaces, M3's two rows that read
   `setting-names`, and the two open rows.
2. **The new type's one payload, its fixed `&message`, was held by no row.** `c-message` held only
   that both verbs get the same string, so P-MSG, the message `""`, and P-MSG2, `&sqlite-closed`'s
   text, passed all three suites. `c-messages` holds the message of each of the six helpers whose
   message is fixed, `raise-invalid-text`, `raise-wrong-thread`, `raise-closed`,
   `raise-setting-mismatch`, `raise-transaction-ended` and `raise-extensions-unavailable`: a
   string, not empty, and equal to no other helper's, never compared with a text of the suite's
   (ADR-0013, decision 9). It fails P-MSG and P-MSG2, and P-MSG3 and P-MSG4, the same two plants
   on `raise-transaction-ended`, which had the same gap; C6, the message made `&irritants`, fails
   it too, and so does red B.
3. **The log's records:** the base is cited as `87e762c`, `main`, whose tree is `fd4831c`'s; the
   driver is kept in [research/m4-slice-1/scripts/](research/m4-slice-1/scripts/), with no local
   path, the directory of its copies an option, so the first run's `build/mut/` is left as it was.

| Suite | Rows as built | Reviewed |
|---|---|---|
| `test-settings` | 74 | 74: `not-db-config-names` and `s-every` changed |
| `test-conditions` | 92 | 93: `c-messages` added |
| `test-open-settings` | 25 | 25 |

## For the records

- **The sentinel's choice,** above, is the slice's own: ADR-0021's decision 3 and ADR-0018's
  amendment say only "neither 0 nor 1". Slice 3 fills the cell with `db-config-sentinel`, never
  a literal of its own, or Z4's split returns: a left cell would read as itself, not `()`.
- **Codes `raise-sqlite-error` refuses.** `db-config-verdict` answers `(error C)` for every code
  but an exact 0, so for 100, 101 and any code whose low byte is 0, such as 256, too. M2's
  `raise-sqlite-error` refuses those as `not-an-error`, an assertion violation, so decision 3's
  "any other code raises `&sqlite-error`" can't hold for them through the one procedure. No
  library measured answers one (0, 1, and Apple's 21); slice 3, or a line in ADR-0021, says what
  such an answer raises.
- **`raise-extensions-unavailable` is the slice's addition** beside the type, its maker and its
  predicate, which the brief named: the fixed `&message` and the `&who` that ADR-0013's
  amendment gives the type live there, as `raise-transaction-ended`'s do. Slice 3 calls it inside
  the checks' critical section, where `checked` catches and raises it again after.
- **The step's shape** for slice 3's join: `(name op written expected)` beside
  `(name set-sql read-sql expected)`, told apart by the `cadr`. `no-call` adds no step but is a
  setting given: the join still marks the name seen, so `setting-given-twice` holds for it.
- **The complement, so far:** the step and `settings-plan` are held against every other op of
  3.45.1's and 3.54.1's headers, 20 names by ADR-0021's rule, `trusted-schema` among them, which
  `settings-plan` accepts as ADR-0018's PRAGMA. 3.54.1 adds `ENABLE_ATTACH_CREATE` (1020),
  `ENABLE_ATTACH_WRITE` (1021), `ENABLE_COMMENTS` (1022) and `FP_DIGITS` (1023). The headers'
  sha256s are in the suite. The open's own row over them is slice 3's.
- **`test-open-settings` holds the four out with two rows,** `:memory:`, the brief's, and a file,
  added for J5. Slice 3 replaces both with its sets' rows.
- **The plan's §4.7 sentinel plant** is held here in the core (`s-sentinel`, `s-left`); its
  stand-in row, a call that answers 0 and leaves the cell, is slice 3's.
- **A complement built from the library's own list** breaks when a later slice changes that list
  rightly: `s-complement` and `s-every` would have failed slice 3's join (part B). A row's
  complement is built from the suite's list, written out, as AGENTS.md has a suite build its
  base; a line there, or in `traps.md`, could say so.
- **`raise-transaction-ended`'s fixed message** is now held by `c-messages` with the new type's,
  and so are the other four fixed messages; before, no row held any of them but by its presence.

## The trap the slice found

- **Chez refuses a program that names an identifier no import binds, at expansion, even inside
  a procedure body never called.** So a suite run against a library that lacks a new export dies
  before its first row and names none: red A. Reproduced in the container with this program,
  `unbound.sps`, run by `scheme --program unbound.sps`:

  ```scheme
  (import (rnrs))
  (display "before\n")
  (define (f) (nosuch-variable 1))
  (display (guard (e (#t 'caught)) (f)))
  ```

  It printed only `Exception: attempt to reference unbound identifier nosuch-variable at line 3,
  char 14 of unbound.sps`, exit 255: never `before`, and the guard caught nothing. To watch new
  rows fail by name, run them against the exports stubbed, each present and wrong, as red B did.
  Reaching them through `eval` under a local name of their own is the other way: the same name,
  defined beside a whole import that has it, is "multiple definitions" ([traps.md](traps.md), M3
  slice 5).
