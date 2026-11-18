# M4 slice 3 mutation log

Evidence that each rule slice 3's rows claim to guard fails through the property it names
([the M4 plan](2026-11-17-m4-plan.md) §4.1, §4.3, §4.7 and §5 item 3). Format of
[the M4 slice 1 log](m4-slice-1-mutation-log.md). An Opus agent built the slice from the lead's
brief, in the worktree `chez-sqlite3-wt-m4s3`, on `m4-slice-3-settings` from `main` at
`1735a66`, slices 1 and 2 and the close fix merged there, beside slice 5 in a worktree of its own.

## What the slice adds

- **`(chez-sqlite3 private settings)`, the join:**
  - `setting-names` gains the four after ADR-0018's seven, in the M4 plan's table order:
    `enable-load-extension defensive dqs-dml dqs-ddl`. `db-config-settings` takes its ops from
    `constants.sls`' `sqlite-dbconfig-*`, which `test-constants` holds to `sqlite3.h`.
  - `settings-plan` plans each of the four by `db-config-step`, among the PRAGMAs' steps in the
    list's order, `busy-timeout`'s still first: a value outside `#t` and `#f` is
    `setting-out-of-domain`; `(enable-load-extension . #f)`'s `no-call` plans no step, yet marks
    the name seen, so a second is `setting-given-twice`. The answer keeps M3's shape,
    `(settings CAPACITY STEPS)`, so M3's rows on it stand.
  - Two new readers, total, called inside the checks' section:

    ```scheme
    ;; db-config-step? : Any -> Boolean
    ;; steps-opt-in? : Any -> Boolean
    ```

    `db-config-step?` holds db_config's shape, `(name op written expected)`, a symbol and two
    exact integers first, where a PRAGMA's step has strings. `steps-opt-in?` answers whether a
    plan's steps hold the opt-in's own step, `(enable-load-extension 1005 1 #t)` as
    `db-config-step` makes it: from the step, never the name, so `#f`, which plans no step, holds
    none.
  - `unknown-setting`'s and `setting-out-of-domain`'s messages name the eleven.
- **The two shapes are not tagged.** Slice 1's ledger said to tag them "if a stand-in could hand
  the wrong kind". A stand-in replaces the binding, not the steps; the shapes are disjoint by
  their second field, a string or an exact integer, and `db-config-step?` decides between them,
  held by two rows against every PRAGMA step the plan makes and against every other value.
  Tagging would change M3's `Setting-Step`, which `test-settings`' plan rows and
  `test-open-settings`' and `test-interrupt-database`'s crafted steps write out.
- **`(chez-sqlite3 private open)`:**
  - `checked-open` answers a fifth value, the opt-in, `steps-opt-in?` of the plan's steps, and
    makes the fifth check after the list's own rules: the opt-in on a library whose native
    `load-extension-available?` is `#f` raises `&sqlite-extensions-unavailable` from the verb,
    inside the checks' section, caught there and raised after it, as every refusal of the
    checks is.
  - `configured`, a db_config step's one section, at the next claimed position: inside
    `in-section`, `call-with-open-handle`, then native's `call-with-int-cell` filled with the
    core's `db-config-sentinel`, the call, and `db-config-verdict` of its answer and cell; for a
    code that names an error, `sqlite3_errstr`'s text copied in the same section. A code whose
    low byte is 0, 100 or 101, or that is no exact integer, is `not-an-error`, tested here, before
    `raise-sqlite-error`.
  - `settled` closes the connection in the next section, then raises: a set's failure by
    `raise-sqlite-error` from the verb, its code the call's own, its message the errstr text, no
    SQL and no offset; a code that names no error as an assertion violation from the verb,
    `(not-an-error CODE)`; a mismatch by `raise-setting-mismatch`.
  - `applied-settings/with`, `applied-settings!`'s form that takes the binding, for the suites'
    stand-in, as `interrupt-database/with` takes its foreign call:

    ```scheme
    ;; applied-settings/with : Symbol Database (Listof Step) DbConfig -> Void
    ;; DbConfig = (Positive-Integer Integer Integer Positive-Integer -> Any)
    ```

    `applied-settings!` keeps its signature and is now `applied-settings/with` given native's
    `sqlite3-db-config`.
- **`(chez-sqlite3 private connection)`:** the record's seventh field, `opt-in`, fixed when it is
  made; `connection-outcome` takes it, `Symbol String Natural Natural Boolean (U (-> Any) #f)`;
  and the reader, for the suites and for slice 4:

  ```scheme
  ;; database-extension-loading? : Database -> Boolean
  ```

  It makes `check-owned`'s two checks, as `database-cache-capacity` does, and reads the field,
  open or closed. Slice 4's `load-extension!` reads it last of its six checks, after its own
  database and owner checks, so the reader's never fire there.
- **`(chez-sqlite3)`** exports `sqlite-extensions-unavailable?`, 69 names, its signature
  comment `;; sqlite-extensions-unavailable? : Any -> Boolean`.
- **`docs/reference.md`:** the Settings table's four rows; the starts by library, Apple's
  `defensive` on; `writable_schema` under `defensive`, a `scheme run` block; DQS's failure at
  prepare, a `scheme run` block; the opt-in's refusal, a plain block; Conditions' row and entry
  for the predicate, eight conditions now.
- **The suites:**
  - `tests/test-open-db-config.sps`, new, 26 rows: the sets at open, the starts, the opt-in's
    `#f` beside a switch that starts on, `defensive`, DQS, the stand-in's failures and
    mismatches, the code and the message, once and in order, a failing close, the record's
    opt-in, the refusals and the complement, the four among the six, the depth;
  - `tests/test-open-db-config-engines.sps`, new, 12 rows: the engine rows;
  - `tests/test-settings.sps`, 86 rows, from 74: the join's;
  - `tests/test-open-settings.sps`, 25: two rows replaced;
  - `tests/test-public.sps`, 22, and `tests/test-reference.sps`, 21: the export;
  - `tests/test-library-loading-real.sps`, 51, from 48: the decoy's opt-in rows, through
    `tests/refusal-probe.sps`' new `--opens` and `tests/library-loading.sls`' `opens-arg` and
    `open-calls`.
  - Both new suites are in `MEMORY_SUITES_2`, as the brief says (below).

## How the mutants ran

Every plant ran in a copy of the worktree of its own, made by
`tar --exclude=./build --exclude=./.git`, each edit checked to match its file's text exactly once
before it was written: `build/mut/NAME/` for the first round, on the suites as first built, and
`build/mut-r2/NAME/` for the counts below, every plant run again on the final suites. Each copy
ran `make deps` and its suites through `$CHEZ --libdirs src:tests:build/scheme-libs --program`,
each under `timeout 600`, inside one `scripts/guix-env` run from the worktree, six copies at a
time by `xargs -P 6`, on Guix's 3.53.1; `scripts/guix-env` starts at the worktree's root, so each
`run.sh` changes into its copy first. Every plant ran all eight of the slice's suites:
`test-settings`, `test-open-settings`, `test-open-db-config`, `test-open-db-config-engines`,
`test-public`, `test-reference`, `test-docs` and `test-library-loading-real`. The counts are read
from the suites' own output (`# of unexpected failures`), never by eye, and the failing rows
named by this log's labels.

The driver is kept in [research/m4-slice-3/scripts/](research/m4-slice-3/scripts/): `mut.py`
makes the copies and their `run.sh`, and reports each copy's failing rows; `mutants.py` holds
every plant's edits; `labels.py` names the rows; `all-names.txt` lists the plants. Each runs from
the worktree's root, `-B` so that no bytecode is left beside them:

```sh
D=.plans/research/m4-slice-3/scripts
python3 -I -B $D/mut.py --into build/mut-r2 prepare all
python3 -I -B $D/mut.py --into build/mut-r2 scripts all
scripts/guix-env sh -c 'ls build/mut-r2/*/run.sh | xargs -P 6 -n 1 sh'
python3 -I -B $D/mut.py --into build/mut-r2 report all
```

## The red runs

The rows were written first, and run against `1735a66`'s code twice: first, red A, on the
suites as first built, in the worktree before any code changed; then on the final suites, in a
copy whose `src/` files and `docs/reference.md` are `1735a66`'s (`build/mut-red/REDA/`). No suite
died: every new name is reached through `eval` under a name of the suite's own, as M3 slice 5's
suites reach theirs, so a library that lacks it fails the rows that use it, by name ([the M4
slice 1 log](m4-slice-1-mutation-log.md)'s trap).

| Suite | `1735a66`'s own | Red, as first built | Red, final | Green |
|---|---|---|---|---|
| `test-settings` | 74 passed | 73 passed, 13 failed | 73 passed, 13 failed | 86 passed |
| `test-open-settings` | 25 passed | 23 passed, 2 failed | 23 passed, 2 failed | 25 passed |
| `test-open-db-config` | new | 6 passed, 19 failed | 6 passed, 20 failed | 26 passed |
| `test-open-db-config-engines` | new | 4 passed, 8 failed | 4 passed, 8 failed | 12 passed |
| `test-public` | 22 passed | 17 passed, 5 failed | 17 passed, 5 failed | 22 passed |
| `test-reference` | 20 passed | 20 passed, 1 failed | 20 passed, 1 failed | 21 passed |
| `test-library-loading-real` | 48 passed | 48 passed, 3 failed | 48 passed, 3 failed | 51 passed |
| `test-docs` | 101 passed | not run | 101 passed, the base page | 105 passed |

`test-open-db-config`'s twentieth failure is `c-switch-on`, the row added after the first round
of plants (below). The rows that pass red, each watched failing against a plant instead:

- `test-settings`: `s-ops-const` (J-op-wrong); `s-join-count`, the suite's own fixture
  (F-join-sample); `s-no-row`, M3's row made to read the suite's eleven, which reads `()` for the
  four on the old library too (J-no-row);
- `test-open-db-config`: its load, its two count rows, and `c-start-read`, the suite's own
  reading of the library's starts, are preconditions; `c-sentinel` (P-literal, J-sentinel);
  `c-complement`, every other op refused, true of the old library too (J-extra-op);
- `test-open-db-config-engines`: its load, its two count rows and its availability row are
  preconditions;
- `test-docs`: the page's new `scheme run` blocks (X-docs, P-defensive-skipped, O-value-bool).

The rows replaced, each named:

- `test-settings`: slice 1's `s-out`, "the four stay out of the live list until slice 3", is now
  `s-in`, "the four are in the live list, after the seven"; M3's `s-setting-names`, "setting-names,
  written out", now writes the eleven; M3's `s-no-row`, "a read-back that answered no row", reads
  the suite's own eleven, `all-names`, where it read the library's `setting-names`; and
  `s-exports` names the two new exports.
- `test-open-settings`: slice 1's two hold-out rows, "each of db_config's four, #t and #f, is
  refused by open-database on :memory: as an unknown setting" and "is refused the same on a
  file", are now `o-accept` and `o-accept-file`: each accepted and opened, on `:memory:` and on a
  file of its own, the file made, the opt-in's `#t` refused instead where the library lacks
  `sqlite3_load_extension`.
- `test-public`: "(chez-sqlite3) exports 68 names" is 69; the public list gains
  `sqlite-extensions-unavailable?`; the connection's export row gains
  `database-extension-loading?` and the open's `applied-settings/with`.

## Green, the libraries and the gate

`make test` ran 77 and passed 77 on each library, inside the container, `CHEZ_SQLITE3_LIBRARY`
and `C_INCLUDE_PATH` set there (the first trap below), each lane's version read from its own P4
line: Guix's 3.53.1, the floor's 3.45.1 (`build/m3-floor/`), the `current` lane's 3.54.1
(`build/m4-current/`), and the coordinator's `build/m4s5-lib-defensive/`, 3.54.1 built
`-DSQLITE_DEFAULT_DEFENSIVE`, which the lead offered for the starts. `make test` ran 75 before the
slice. The starts, as `test-open-db-config` read them through the op, `enable-load-extension`,
`defensive`, `dqs-dml`, `dqs-ddl`, each `(code cell)`:

| Library | Starts |
|---|---|
| Guix's 3.53.1, the floor's 3.45.1, the current lane's 3.54.1 | `(0 0) (0 0) (0 1) (0 1)` |
| `m4s5-lib-defensive`, 3.54.1 | `(0 0) (0 1) (0 1) (0 1)` |

On the defensive library, the native −1 read and open-database's read both gave 1, and
`(defensive . #f)` read back 0, as the lead's note predicted; its compile options list no
`DEFAULT_DEFENSIVE` (the third trap below), so only the op tells.

Under `make test-memory`, on Guix's 3.53.1, each suite the slice touched passed, 0 errors and
nothing definitely lost, none `SLOW`, each time from the gate's `time:` line:

| Suite | Shard | Rows | Gate |
|---|---|---|---|
| `test-settings` | 1 | 86 | 11 s |
| `test-open-settings` | 1 | 25 | 13 s |
| `test-open-db-config`, new | 2 | 26 | 12 s |
| `test-open-db-config-engines`, new | 2 | 12 | 56 s |
| `test-public` | 2 | 22 | 10 s |
| `test-reference` | 2 | 21 | 10 s |
| `test-docs` | 1 | 105 | 34 s |
| `test-library-loading-real` | 1 | 51 | 177 s |

Both new suites are in `MEMORY_SUITES_2`, as the brief says: on three CI runs the shards' sums
read 900 and 986 s, 1186 and 1268 s, 915 and 874 s, shard 1 against shard 2, and since then
shard 1 has gained `test-check-variadic`, about 10 s, and slice 5's PR #40 adds `test-fts5` and
`test-json`, about 10 s each, there. The two add about 68 s here to shard 2. Shard 1 grows too:
`test-library-loading-real`'s three new children, run under the gate's Valgrind, took it from
the 145 to 160 s slice 2 measured here to 177 s, where CI read 142 and 143 s on its last two
runs of `main`; and the dispatch's ticks lengthen `test-open-interleave`'s sweeps, in shard 2, by
about a third of its trials, where CI read 33 and 39 s. Each stays far inside the 450 s bound;
read the new suites' times from more than one CI run before moving either.

The engine rows, the same on Guix's 3.53.1, the floor's 3.45.1 and 3.54.1, by their own printed
lines:

| Row | Completes unexpired at | What the sweep saw |
|---|---|---|
| `e-fuel`, open-database, the six PRAGMAs, `statement-cache` and the four, on a file | fuel 289 | a PRAGMA's statement held at 40 expiries |
| `e-twice`, the same resumed twice | fuel 289 | refused 258, the same connection 21, a whole new call 9; refused before the open first at fuel 10 |
| `e-reentry`, call-with-database re-entered from a timer's continuation | tick 301, the procedure's start | refused 270, the procedure again 22, a whole new call 8; refused before the open first at tick 9 |
| `e-cwd`, call-with-database under an engine | fuel 563 | as asked 55, closed 249, closed inside the procedure 259 |
| `e-interleave`, open-database, `foreign-keys`, `busy-timeout` and the four on `:memory:` | fuel 119 | 7,021 trials, all answering; both remainders past the open in 5,050; whole new calls only below fuel 10 |
| `e-once`, applied-settings/with, the four and a PRAGMA, counted | fuel 76 | 2,850 trials; both past the first set in 1,653; whole new calls only below fuel 10 |
| `e-failing`, applied-settings/with, its second set failed, resumed twice | fuel 67 | refused 17, refused after a set 9, the error again 40 |

The slice moved M3's own sweeps, whose suites it left as they were: `test-open-engines`' open
with the six PRAGMAs completed at fuel 221 on `1735a66`, and at 257 now. `step-applied`'s
dispatch between the two kinds of step, `db-config-step?` and a call more, runs outside any
section for every step, and an engine spends ticks there; not measured further.
`test-open-interleave`'s two sweeps went from fuels 73 and 97, 2,628 and 5,599 trials, to 85 and
109, 3,570 and 6,643. Every whole new call came below the first refusal its own sweep saw before
the call's first section, the bound AGENTS.md asks: never a refused call's fuel, a control on
another call, or a caller's count.

## The mutations

The rows, by label. `test-settings`: `s-exports`; `s-setting-names`; `s-in` the four in the live
list and planned alone; `s-ops-const` the table's ops `constants.sls`'; `s-join-count` the
orderings' count, the suite's fixture; `s-join-order` every ordering of two mixed sets;
`s-join-whole` all eleven written out; `s-join-domain` each of the four through the plan against
the universe; `s-join-twice` a name given twice, the opt-in's `#f` among them; `s-join-pass` the
one pass's order; `s-step?` and `s-step?-not` `db-config-step?` for and against; `s-opt-in` and
`s-opt-in-only` `steps-opt-in?` for plans and against crafted steps; `s-messages` the two
messages name the eleven; `s-no-row`, `s-table`, `s-steps` and `s-domain` M3's and slice 1's.
`test-open-settings`: `o-accept`, `o-accept-file`; `o-depth` M3's. `test-open-db-config`:
`c-sentinel` the availability and the sentinel, -1; `c-held`, `c-held-cwd` and `c-held-kinds`
each set read back, through each verb and on each kind of connection; `c-start-read`,
`c-start` and `c-start-one` the starts unasked; `c-switch-on` the opt-in's `#f` beside a switch
that starts on; `c-writable`; `c-dqs`; `c-match` a stand-in that matches; `c-failures` the
stand-in's ten failures and mismatches; `c-code` the code on a fresh connection; `c-message` the
code and message after a constraint's failure; `c-once` and `c-once-fail` once, in order;
`c-close-fails`; `c-opt-in` and `c-opt-in-check` the record's opt-in and its reader's check;
`c-refusals`; `c-complement`; `c-six` the four among the six; `c-depth`; `c-end`.
`test-open-db-config-engines`: `e-clean`, `e-fuel`, `e-twice`, `e-reentry`, `e-cwd`,
`e-interleave` open-database's runs interleaved, `e-once` applied-settings/with's sets counted,
interleaved, `e-failing` a failing set resumed twice. `test-public`: `p-count`, `p-list`,
`p-conn`, `p-open`, `p-eq`. `test-reference`: `r-line`. `test-library-loading-real`:
`l-lacking` the lacking decoy's opt-in and the order; `l-control` the control's; `l-false` the
opt-in's `#f` on the lacking build. A row named in quotes is M3's or slice 1's, by its title's
start.

| Plant | What it plants | Failed |
|---|---|---|
| P-nocell | a set held without its cell: code 0 always reads as the value written | open-db-config 4 of 26: `c-failures`, `c-once-fail`, `c-close-fails`, `c-depth` |
| P-nocode | a set that reads the cell but not the code: the verdict given code 0 | open-db-config 5: `c-failures`, `c-code`, `c-message`, `c-close-fails`, `c-depth`; engines 1 of 12: `e-failing` |
| P-fill0 | the cell filled with 0 | open-db-config 6: `c-match`, `c-failures`, `c-once`, `c-once-fail`, `c-close-fails`, `c-depth` |
| P-fill1 | the cell filled with 1 | open-db-config 6: the same |
| P-literal | the shell fills with a literal -1, the core's sentinel -3 | open-db-config 7: `c-sentinel` and P-fill0's six |
| P-code-conn | a failure's code read from the connection, `sqlite3_extended_errcode` | open-db-config 5: `c-failures`, `c-code`, `c-message`, `c-close-fails`, `c-depth`; engines 1: `e-failing` |
| P-errmsg | a set's message from `sqlite3_errmsg` | open-db-config 4: `c-failures`, `c-code`, `c-message`, `c-close-fails` |
| P-unasked-defensive | `defensive` set to 1 at every open | open-db-config 2: `c-start`, `c-start-one` |
| P-unasked-load | `enable-load-extension`'s op set to 1 at every open, the mutation Q3 is about | open-db-config 3: `c-start`, `c-start-one`, `c-switch-on` |
| P-unasked-dqs-dml | `dqs-dml` set to 0 at every open | open-db-config 3: `c-start`, `c-start-one`, `c-dqs` |
| P-unasked-dqs-ddl | `dqs-ddl` set to 0 at every open | open-db-config 3: the same |
| P-defensive-skipped | `defensive`'s step dropped from the plan | settings 4 of 86: `s-in`, `s-join-order`, `s-join-whole`, `s-join-domain`; open-db-config 5: `c-held`, `c-held-cwd`, `c-held-kinds`, `c-writable`, `c-six`; engines 6: `e-clean`, `e-fuel`, `e-twice`, `e-reentry`, `e-cwd`, `e-interleave`; docs 1 of 105: the `writable_schema` block |
| P-opt-in-check | the opt-in's check dropped | loading-real 1 of 51: `l-lacking` |
| P-opt-in-inverted | the check refuses where the entry point is found | open-settings 2 of 25: `o-accept`, `o-accept-file`; open-db-config 6: `c-held`, `c-held-cwd`, `c-held-kinds`, `c-switch-on`, `c-opt-in`, `c-six`; engines 6: as P-defensive-skipped's; loading-real 2: `l-lacking`, `l-control` |
| P-false-call | `(enable-load-extension . #f)` makes a call, the op's 0 sent | open-db-config 1: `c-switch-on`; **survived the first round**, below |
| J-order | the four's steps planned before the PRAGMAs' | settings 2: `s-join-order`, `s-join-whole` |
| J-seen | the opt-in's `#f` not marked seen | settings 1: `s-join-twice`; open-db-config 1: `c-refusals` |
| J-unknown | a value outside the four's domain refused as `unknown-setting` | settings 2: `s-join-domain`, `s-join-pass`; open-db-config 1: `c-refusals`; loading-real 1: `l-lacking` |
| J-names | `dqs-ddl` left out of `setting-names` | settings 6: `s-setting-names`, `s-in`, `s-join-order`, `s-join-whole`, `s-join-domain`, `s-join-twice`; open-settings 2: `o-accept`, `o-accept-file`; open-db-config 8: `c-held`, `c-held-cwd`, `c-held-kinds`, `c-start-one`, `c-dqs`, `c-opt-in`, `c-refusals`, `c-six`; engines 6 |
| J-names-order | `dqs-ddl` before `dqs-dml` in `setting-names` | settings 2: `s-setting-names`, `s-in` |
| J-extra-op | `enable-fkey`, another op's name, joined to `setting-names` | settings 3: `s-setting-names`, `s-in`, 'every other op of the headers'; open-db-config 1: `c-complement` |
| J-step-loose | `db-config-step?` takes any second field | settings 1: `s-step?-not` |
| J-opt-in-name | `steps-opt-in?` reads a step's name, not the step | settings 1: `s-opt-in-only` |
| J-opt-in-list | the opt-in read from the list's name, not the plan's step | open-db-config 1: `c-opt-in`; loading-real 1: `l-false` |
| J-messages | `unknown-setting`'s message without the four | settings 1: `s-messages` |
| J-messages-domain | `setting-out-of-domain`'s message without the four | settings 1: `s-messages` |
| J-op-wrong | `dqs-ddl`'s op a literal 1015 in the table | settings 8: `s-table`, `s-in`, `s-ops-const`, `s-steps`, `s-domain`, `s-join-order`, `s-join-whole`, `s-join-domain`; open-db-config 5: `c-held`, `c-held-cwd`, `c-held-kinds`, `c-dqs`, `c-six`; engines 6 |
| J-sentinel | the core's sentinel -3, the shell filling with it | open-db-config 1: `c-sentinel` |
| J-no-row | a read-back of no row reads `nothing` for the four | settings 1: `s-no-row` |
| F-join-sample | in the copy's `test-settings`, the fixture: `statement-cache` dropped from a mixed set | settings 1: `s-join-count` |
| O-noclaim | the set's section given a claim that always answers yes, never advancing | open-db-config 9; engines 9: every row but the three preconditions |
| O-claim-unchecked | the set's section claims, but runs whatever the claim answers | engines 2: `e-twice`, `e-once` |
| O-split-claim | the claim in a section of its own, the call in the next, unclaimed | engines 2: `e-twice`, `e-once` |
| O-all-errors | every code but 0 raised by `raise-sqlite-error`, 100 among them | open-db-config 2: `c-failures`, `c-depth` |
| O-low-zero | only a low byte of 0 names no error | open-db-config 2: `c-failures`, `c-depth` |
| O-whole-code | the code itself, not its low byte, tested against 0, 100 and 101 | open-db-config 1: `c-failures` |
| O-not-error-who | the assertion violation's who `settled`, not the verb | open-db-config 2: `c-failures`, `c-depth` |
| O-no-close | a set's failure or any mismatch raised without the close | open-settings 8: six of M3's and `o-depth`, 'every count is zero at the end'; open-db-config 2: `c-failures`, `c-once-fail`; engines 1: `e-failing`; docs 35: the blocks after the first left-open connection |
| O-value-bool | the value written always 1 | open-settings 2; open-db-config 9; engines 7; docs 1: the DQS block |
| O-expected-written | the verdict given the integer written as the value expected | open-settings 2; open-db-config 15; engines 8; docs 2 |
| O-opt-in-f | open-database's record made without the opt-in | open-db-config 2: `c-opt-in`, `c-six`; engines 4: `e-clean`, `e-fuel`, `e-twice`, `e-interleave` |
| O-cwd-opt-in-f | call-with-database's record made without it | open-db-config 1: `c-opt-in`; engines 3: `e-clean`, `e-reentry`, `e-cwd` |
| O-errstr-1 | the message always `sqlite3_errstr(1)`'s | open-db-config 1: `c-failures` |
| O-steps-dropped | open-database's plan stripped of the four's steps | open-db-config 6: `c-held`, `c-held-cwd`, `c-held-kinds`, `c-writable`, `c-dqs`, `c-six`; engines 6; docs 2 |
| O-check-first | the opt-in's check, by the list's name, before the list's own rules | loading-real 1: `l-lacking` |
| O-check-before-m2 | the opt-in's check before M2's checks | loading-real 1: `l-lacking` |
| O-export-extra | `open.sls` exports `configured` too | public 1 of 22: `p-open` |
| C-unchecked | `database-extension-loading?` without `check-owned` | open-db-config 1: `c-opt-in-check` |
| C-field-f | the record's opt-in always `#f` | open-db-config 2: `c-opt-in`, `c-six`; engines 6 |
| X-export | `(chez-sqlite3)` without `sqlite-extensions-unavailable?` | public 3: `p-count`, `p-list`, `p-eq`; reference 3 of 21: 'every entry is an export', 'the entries are the exports', `r-line`; docs 1: the code-span rule |
| X-docs | the `writable_schema` block's stated result `#(1)` | docs 1 |

**51 plants: all caught.** The M4 plan's §4.7 names P-nocell and P-nocode (a set held without its
cell, or its code), P-fill0 and P-fill1 (a sentinel of 0 or 1), P-code-conn (the code from the
connection), P-errmsg (the message from `sqlite3_errmsg`), the four P-unasked (an op set
unasked), P-defensive-skipped (`defensive` without effect) and P-opt-in-check (the check
dropped). The rest are the builder's, at every site the slice changed. 46 ran in the second
round, `build/mut-r2/`, on the final suites; J-messages-domain, J-names-order, J-extra-op,
J-no-row and F-join-sample were added after it and ran on the same suites, in
`build/mut-r2-extra/`.

Which rows: the stand-in's rows hold every plant inside a set's section, and the §4.7 plants each
fail the stand-in row the plan names: P-nocell `c-failures`' "left" cases, P-nocode its answer
of 1, P-fill0 and P-fill1 its "left" and `c-match`'s sentinel, P-code-conn `c-code` (`(not-an-error
0)` on a fresh connection, as rv2 measured, and `constraint` after `c-message`'s failure),
P-errmsg `c-message` (the constraint's text) and `c-failures` ("not an error", a fresh
connection's). The start rows hold the P-unasked four by the comparison with the suite's own
connection: on Guix's library, where the opt-in's switch starts at 0 and `defensive` at 0, each
plant moves a start; and `c-switch-on`, where it starts at 1. The claim's plants fail only the
engine rows, which are their only reach: O-claim-unchecked and O-split-claim change nothing on a
single run, and `e-twice` sees the first connection's ops set back as asked, `e-once` the
stand-in called twice for one op. The opt-in's order plants, O-check-first and O-check-before-m2,
fail only `l-lacking`, the decoy's: no library this process loads lacks the entry point.

## The survivor, argued, and the row it brought

- **P-false-call survived the first round,** run on Guix's 3.53.1 on the suites as first built.
  The start rows compare a library's start with open-database's, and on Guix's library, the
  floor's and 3.54.1 the C switch starts at 0, the value the plant writes: in its copy, `c-start`
  passed, its `(open-database ":memory:" '((enable-load-extension . #f)))` reading the suite's own
  connection's `(0 0)`. Only Ubuntu's library, CI's `main` lane, starts it at 1, and only there
  would `c-start` have caught it. Q15's "the op's 0 is never sent" was then held on one lane of
  four, so the slice added `c-switch-on`: an entry point that `sqlite3_auto_extension` runs at
  every open sets the switch to 1, through native's binding, and the row asserts the suite's own
  connection reads 1, and open-database's and call-with-database's with `#f` read 1 too.
  P-false-call fails it on Guix's 3.53.1, the floor's 3.45.1 and 3.54.1, each run in its copy; the
  unplanted tree passes it on all four libraries. Where a library refuses the registration,
  Apple's 21, the row prints UNAVAILABLE and asserts 21.
- No other plant survived either round.

## For the records

- **ADR-0018 and ADR-0021, slice 3's amendment (proposed):**
  - the join: the four in `setting-names` after the seven, in the plan's table order; their ops
    `constants.sls`', held to the header by `test-constants` and to the table by a row;
  - the two step shapes are told apart by `db-config-step?`, not tagged (above);
  - the record's opt-in is `steps-opt-in?` of the plan's steps, `(enable-load-extension 1005 1
    #t)`'s presence, so `#f` holds none; the fifth check reads the same answer;
  - a set's message is `sqlite3_errstr`'s, copied inside the set's own section; a code that is no
    exact integer, which only a stand-in can answer, is `not-an-error` with those whose low byte
    is 0, 100 or 101: the amendment of M4 slice 1 names the low bytes alone;
  - `applied-settings/with` is exported for the suites, as `interrupt-database/with` is, and
    `database-extension-loading?` from `(chez-sqlite3 private connection)`, for the suites and
    slice 4;
  - the engine rows' fuels, alike on the three libraries: the table under "Green" above;
  - M3's open sweeps moved with the dispatch: `test-open-engines`' 221 to 257, `test-open-interleave`'s
    73 and 97 to 85 and 109 (above), which ADR-0018's slice 5 table records at 221 and 75 and 99.
- **ADR-0012, the opt-in's amendment:** done as written; slice 4 reads
  `database-extension-loading?` last of its six checks.
- **The global constraints' "`db_config` and extensions":** no rule changes; a set's message is
  read in its section, which the second bullet's "its message `sqlite3_errstr`'s" covers.
- **The ledger's close-out** (progress.md): the files and signatures above; the rows replaced;
  the counts; the times; for slice 4: `database-extension-loading?`, and `refusal-probe.sps`'
  `--opens`, which a load's rows on the decoy can reuse.
- **traps.md:** the three traps below; the third confirms an entry M4's pre-work made for
  Apple's library.

## The traps the slice found

- **A variable set on the host does not reach `scripts/guix-env`'s container.** The container
  keeps only `TERM`, `COLORTERM` and `LANG`, and exports its own `CHEZ_SQLITE3_LIBRARY`, the
  profile's. So `CHEZ_SQLITE3_LIBRARY=$PWD/build/m3-floor/lib/libsqlite3.so.0 scripts/guix-env
  sh -c 'make test'` ran on Guix's 3.53.1, 77 of 77, a green on the wrong library; only its P4
  line, "SQLite 3.53.1 sleeps in milliseconds", said so. Set both variables inside the
  container's `sh -c`, and read the version a suite prints before trusting a lane. Reproduce,
  from the root: `CHEZ_SQLITE3_LIBRARY=$PWD/build/m3-floor/lib/libsqlite3.so.0 scripts/guix-env
  sh -c 'echo "$CHEZ_SQLITE3_LIBRARY"'` prints the profile's `/gnu/store/…/lib/libsqlite3.so.0`.
- **A whole new call's sets interleave with the first run's.** In `e-once`'s first version, a
  trial at fuel 1 took R before `applied-settings/with`'s claim, R1 from R's resume after its
  first set, then ran R, a whole new call, to its end, then R1: the stand-in noted
  `(1005 1) (1005 1) (1010 1) (1013 0) (1014 0) (1010 1) (1013 0) (1014 0)`, two whole calls each
  in order, merged. A row that expects two whole calls one after the other fails 522 trials of
  the correct code. Judge a merge: with distinct calls, each noted exactly twice, the first of
  each pair in the call's order, and the second too.
- **A compile option a library is built with can be unlisted.** The coordinator's
  `build/m4s5-lib-defensive/`, 3.54.1 built `-DSQLITE_DEFAULT_DEFENSIVE`, lists no
  `DEFAULT_DEFENSIVE` in `sqlite3_compileoption_get`, and `sqlite3_compileoption_used` of it
  answers 0; its -1 read of `DEFENSIVE` answers `(0 1)`. As Apple's (traps.md, M4's pre-work), so
  a start is read through the op, never from the options.
