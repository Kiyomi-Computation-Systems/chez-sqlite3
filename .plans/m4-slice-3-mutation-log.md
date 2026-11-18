# M4 slice 3 mutation log

Evidence that each rule slice 3's rows claim to guard fails through the property it names
([the M4 plan](2026-11-17-m4-plan.md) §4.1, §4.3, §4.7 and §5 item 3). Format of
[the M4 slice 1 log](m4-slice-1-mutation-log.md). An Opus agent built the slice from the lead's
brief, in the worktree `chez-sqlite3-wt-m4s3`, on `m4-slice-3-settings` from `main` at
`1735a66`, slices 1 and 2 and the close fix merged there, beside slice 5 in a worktree of its own.
The lead committed it, as first built, and rebased it onto `main` at `7dac918`, slice 5's merge, which
adds `test-fts5` and `test-json`: there `make test` runs 79 suites, and ran 77 before this slice.
The slice's read-only Opus review then found two majors and five smaller items, fixed in a second
round ([below](#round-2-the-reviews-findings)); every count from "Green" on is the second
round's, on `7dac918`.

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
  - `tests/test-open-db-config.sps`, new, 26 rows, 30 after round 2: the sets at open, the starts, the opt-in's
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
  - Both new suites were put in `MEMORY_SUITES_2`, as the brief said, and moved to
    `MEMORY_SUITES_1` in round 3, the lighter shard on CI's last runs (below).

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

The rows were written first. In the first round they ran against `1735a66`'s code twice:
red A, on the suites as first built, in the worktree before any code changed; then on that
round's final suites, in a copy whose `src/` files and `docs/reference.md` are `1735a66`'s
(`build/mut-red/REDA/`). After the rebase and the second round, every suite ran again against
`7dac918`'s `src/` and docs, the base the branch now sits on (`build/mut-red2/RED/`). No suite
died: every new name is reached through `eval` under a name of the suite's own, as M3 slice 5's
suites reach theirs, so a library that lacks it fails the rows that use it, by name ([the M4
slice 1 log](m4-slice-1-mutation-log.md)'s trap).

| Suite | The base's own | Red as first built, `1735a66` | Round 1's final, `1735a66` | Round 2's, `7dac918` | Green |
|---|---|---|---|---|---|
| `test-settings` | 74 passed | 73 passed, 13 failed | 73 passed, 13 failed | 73 passed, 13 failed | 86 passed |
| `test-open-settings` | 25 passed | 23 passed, 2 failed | 23 passed, 2 failed | 23 passed, 2 failed | 25 passed |
| `test-open-db-config` | new | 6 passed, 19 failed | 6 passed, 20 failed | 8 passed, 22 failed | 30 passed |
| `test-open-db-config-engines` | new | 4 passed, 8 failed | 4 passed, 8 failed | 4 passed, 8 failed | 12 passed |
| `test-public` | 22 passed | 17 passed, 5 failed | 17 passed, 5 failed | 17 passed, 5 failed | 22 passed |
| `test-reference` | 20 passed | 20 passed, 1 failed | 20 passed, 1 failed | 20 passed, 1 failed | 21 passed |
| `test-library-loading-real` | 48 passed | 48 passed, 3 failed | 48 passed, 3 failed | 48 passed, 3 failed | 51 passed |
| `test-docs` | 101 passed | not run | 101 passed, the base page | 101 passed, the base page | 105 passed |

`test-open-db-config`'s twentieth failure in round 1 is `c-switch-on`, the row added after the
first round of plants (below); round 2 adds `c-start-one`'s wider lists and the four moved-start
rows, two of which pass red (round 2, below). The rows that pass red, each watched failing against
a plant instead:

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

`make test` ran 79 and passed 79 on each library on `7dac918`, after round 2, inside the
container, `CHEZ_SQLITE3_LIBRARY`
and `C_INCLUDE_PATH` set there (the first trap below), each lane's version read from its own P4
line: Guix's 3.53.1, the floor's 3.45.1 (`build/m3-floor/`), the `current` lane's 3.54.1
(`build/m4-current/`), and the lead's `build/m4s5-lib-defensive/`, 3.54.1 built
`-DSQLITE_DEFAULT_DEFENSIVE`, which the lead offered for the starts. M4 slice 5's review built it;
the library isn't kept, and [research/m4-slice-3/lib-defensive.sh](research/m4-slice-3/lib-defensive.sh)
rebuilds it from the pinned release byte for byte (md5 `9b072bda…`). `make test` ran 77 there
before the slice; before the rebase, on `1735a66`, it ran 77 with the slice and 75 without. The
starts, as `test-open-db-config` read them through the op, `enable-load-extension`,
`defensive`, `dqs-dml`, `dqs-ddl`, each `(code cell)`:

| Library | Starts |
|---|---|
| Guix's 3.53.1, the floor's 3.45.1, the current lane's 3.54.1 | `(0 0) (0 0) (0 1) (0 1)` |
| `m4s5-lib-defensive`, 3.54.1 | `(0 0) (0 1) (0 1) (0 1)` |

On the defensive library, the native −1 read and open-database's read both gave 1, and
`(defensive . #f)` read back 0, as the lead's note predicted; its compile options list no
`DEFAULT_DEFENSIVE` (the third trap below), so only the op tells.

Under `make test-memory`, on Guix's 3.53.1, each suite the slice touched passed, 0 errors and
nothing definitely lost, none `SLOW`, each time from the gate's `time:` line, round 1's on
`1735a66` and round 2's on `7dac918`:

| Suite | Shard | Rows | Round 1 | Round 2 |
|---|---|---|---|---|
| `test-settings` | 1 | 86 | 11 s | 10 s |
| `test-open-settings` | 1 | 25 | 13 s | 14 s |
| `test-open-db-config`, new | 1, from round 3 | 26, then 30 | 12 s | 12 s |
| `test-open-db-config-engines`, new | 1, from round 3 | 12 | 56 s | 56 s |
| `test-public` | 2 | 22 | 10 s | 10 s |
| `test-reference` | 2 | 21 | 10 s | 10 s |
| `test-docs` | 1 | 105 | 34 s | 33 s |
| `test-library-loading-real` | 1 | 51 | 177 s | 177 s |

Both new suites went into `MEMORY_SUITES_2` first, as the brief said, and round 3 moved them to
`MEMORY_SUITES_1` (below): on three CI runs the shards' sums
read 900 and 986 s, 1186 and 1268 s, 915 and 874 s, shard 1 against shard 2, and since then
shard 1 has gained `test-check-variadic`, about 10 s, and slice 5's PR #40 adds `test-fts5` and
`test-json`, about 10 s each, there. The two add about 68 s here to shard 2. Shard 1 grows too:
`test-library-loading-real`'s three new children, run under the gate's Valgrind, took it from
the 145 to 160 s slice 2 measured here to 177 s, where CI read 142 and 143 s on its last two
runs of `main`; and the dispatch's ticks lengthen `test-open-interleave`'s sweeps, in shard 2, by
about a third of its trials, where CI read 33 and 39 s. Each stays far inside the 450 s bound;
read the new suites' times from more than one CI run before moving either. Round 3's move rests
on `main`'s last three CI runs at the layout before it, the lead's reading: shard 1 at 1012, 1023
and 1005 s against shard 2's 836, 1091 and 1441 s (runs 44305936182, 44298034354 and
44293661574), so shard 1 is the lighter on two of three, by about 110 s on average.

The engine rows, the same on Guix's 3.53.1, the floor's 3.45.1 and 3.54.1, by their own printed
lines:

| Row | Completes unexpired at | What the sweep saw |
|---|---|---|
| `e-fuel`, open-database, the six PRAGMAs, `statement-cache` and the four, on a file | fuel 289 | a PRAGMA's statement held at 39 or 40 expiries, by run (round 3, item N6) |
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

**51 plants: all caught** in the second round; with the review's five and the builder's G1
after it, 57 plants, 56 caught, R4 argued (round 2, below). The M4 plan's §4.7 names P-nocell and P-nocode (a set held without its
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

## Round 2: the review's findings

The slice's read-only Opus review, of the first round's tree rebased onto `7dac918`, found no blocker, two
majors and five smaller items. Each is fixed or answered here, test first.

1. **Major: an op set unasked beside the opt-in survived.** `c-start-one` held lists of one op
   for `defensive`, `dqs-dml` and `dqs-ddl` alone, so the review's R3, `checked-open` adding
   `(defensive 1010 1 #t)` when the opt-in is present and `defensive` isn't named, passed every
   suite on Guix's library and the floor. The row now takes every list of one op,
   `single-lists`: each of the four at `#t` and at `#f`, the opt-in's `#t` where `available` is
   `#t`, and compares each list's other three with `raw-starts`. R3 fails it on Guix's 3.53.1,
   the floor's 3.45.1 and 3.54.1.
2. **Major: a set that writes a lane's start can't be seen on that lane,** a flaw the lead's
   brief shared: "a plant that sets an op unasked fails on every lane" holds only for a plant that
   moves an op off its start. R1, `defensive` set to 0 at every open, passed every suite on Guix's
   library; R2, `dqs-dml` set to 1 at every open, passed on Guix's and on `m4s5-lib-defensive`;
   R6, `configured` skipping `defensive`'s `#f` and answering a match, passed every suite on
   Guix's library, since `c-held`'s `#f` reads 0 whether or not the call is made. Four new rows,
   by `c-switch-on`'s method: an entry point `sqlite3_auto_extension` runs at every open,
   `move-starts`, sets each of the four ops to 1 less this library's start, read through
   `raw-starts` first;
   - `c-moved`: the suite's own connection reads every op at its moved value, the control;
   - `c-moved-unasked`: open-database with no setting and with `()`, and call-with-database with
     none, keep every moved value;
   - `c-moved-held`: each list of one op reads its own op back as asked over the moved start, so
     each value of each op is set off its start in this row or in `c-held`; the opt-in's `#f`
     keeps the moved value;
   - `c-moved-others`: each list of one op leaves the other three at their moved values.
   Where `sqlite3_auto_extension` is refused, Apple's 21, each prints UNAVAILABLE and asserts 21.
   The start rows stay: they hold each start where nothing moves it.
3. **Minor: `e-failing`'s guard counted one trial.** It passed on one refusal past a set. It now
   requires refusals at a third of the fuels at least, some past a set, as `test-open-interleave`
   counts its own: 17 refused and 9 past a set, 26 of 67. The builder's plant G1, a refused
   section's run raising the set's error at the call's first section instead of
   `&sqlite-closed`, left 18 refusals of 67, 9 past a set, and passed the old guard; the new one
   fails it, `(refused 18 past-a-set 9 of 67)`.
4. **Minor: the docs' starts table wasn't true on every library.** `m4s5-lib-defensive` starts
   `defensive` on, and a build `SQLITE_DQS=0`, as SQLite's docs advise, starts DQS off. It now
   reads "stays as the library was built": `defensive` "off in most libraries; on in Apple's",
   DQS "on in every library measured", and the sentence that tells a program to name the setting
   stays after it.
5. **Minor: the log was stale since the rebase.** The header and "Green" now give `7dac918` and
   79 suites, 77 before; the first round's red table keeps `1735a66`, which it ran against, and
   this round's red ran against `7dac918` (below).
6. **Nit: no row holds the errstr message copied inside the set's section.** The review's R4,
   rebuilt here, copies it after the section: it survives every suite, and is argued below.
7. **Nit: `e-once`'s "both remainders past" was R's alone,** `r1-past` bound to `r-past`. Each
   trial now reads R1's position at R1's own expiry too: both past the first section, or R before
   it and R1 past it, a straddle, which races R's second run against R1 at that section itself,
   or neither. The two interleave rows print both counts and require a straddle in some trial, as
   well as both past in one a fuel: `e-interleave` 5,050 both past and 1,717 straddling of 7,021
   trials; `e-once` 1,653 and 986 of 2,850.

### The review's plants, rebuilt

Each rebuilt from the review's description into `build/mut-review/NAME/`, by `mutants.py`, then
run on Guix's 3.53.1 against every slice suite, and `test-open-db-config` against the floor's
3.45.1, 3.54.1 and `m4s5-lib-defensive`; each also ran the first round's `test-open-db-config` and
`test-open-db-config-engines`, the rows before this round, to reproduce the finding.

| Plant | What it plants | Before this round's rows | With them |
|---|---|---|---|
| R1 | `defensive` set to 0 at every open | survived on Guix's, the floor and 3.54.1; failed `c-start`, `c-start-one` on `m4s5-lib-defensive` | `c-moved-unasked`, `c-moved-others` on all three; `c-start`, `c-start-one` on `m4s5-lib-defensive` |
| R2 | `dqs-dml` set to 1 at every open | survived on all four libraries | `c-moved-unasked`, `c-moved-others` on all four |
| R3 | `(defensive 1010 1 #t)` added beside the opt-in when `defensive` isn't named | survived on all four | `c-start-one` on Guix's, the floor and 3.54.1; `c-moved-others` on `m4s5-lib-defensive` |
| R4 | the errstr message copied after the set's section | survived | survived: below |
| R6 | `configured` skipping `defensive`'s `#f`, answering a match | survived on Guix's, the floor and 3.54.1; failed `c-held`, `c-held-cwd`, `c-writable` on `m4s5-lib-defensive` | `c-moved-held` on all three; the same three on `m4s5-lib-defensive` |
| G1 | a refused run raising the set's error at the call's first section | `e-once` | `e-once`, `e-failing` |

R4 survives, and is harmless: `sqlite3_errstr` answers a static string, the same address and
text for a code whatever the connection does, so its copy after the section reads what it would
have read inside. No expiry or timer between the two can change it, and the plant changes no
answer of any row, on any library. Should a later SQLite free or reuse that text, a row would
need a stand-in errstr; the binding is native's, so none is cheap and real today.

### The third round

Every plant, the 51 and the six above, ran again on this round's suites, in `build/mut-r3/`, on
Guix's 3.53.1: **57 plants, 56 caught, R4 survived, argued above.** The new rows added these
failures to the second round's: P-defensive-skipped, J-op-wrong and O-steps-dropped `c-moved-held`;
P-false-call `c-moved-held`; P-opt-in-inverted, J-names, O-value-bool and O-expected-written
`c-start-one`, `c-moved-held` and `c-moved-others` where they lacked them; no plant's failures
fell. The P-unasked four fail `c-start` and `c-start-one` alone, as before: each writes the
value the moved rows move to on Guix's library, the complement of what R1 and R2 write.

### This round's red and green

On `7dac918`'s `src/` and docs, the final suites, in `build/mut-red2/RED/`:
`test-open-db-config` 8 passed, 22 failed of 30; `test-open-db-config-engines` 4 passed, 8
failed. Of the new rows, `c-moved-held` and `c-moved-others` fail red, and so do the changed
`c-start-one` and every engine row; `c-moved`, the suite's own reading, and `c-moved-unasked`
pass, since `7dac918` sets nothing at open: R1 and R2 watched it fail. The changed `e-failing`
guard was watched failing against G1, and the straddle counts against nothing: they are
counted, not planted.

After the round, on `7dac918`: `make test` ran 79 and passed 79 on Guix's 3.53.1, the floor's
3.45.1, 3.54.1 and `m4s5-lib-defensive`, each library's variables set inside the container's
`sh -c` and its version read from its P4 line; `test-open-db-config` passed 30 rows on each,
printing its moves: `(0 1) (0 1) (0 0) (0 0)` on the first three, `(0 1) (0 0) (0 0) (0 0)` on
`m4s5-lib-defensive`. Under `make test-memory` on Guix's library all eight slice suites passed,
none `SLOW`: the round's times are the "Round 2" column of "Green" above; the four moved-start
rows cost `test-open-db-config` nothing measurable, 12 s either way.

## Round 3: the M4 session's check of PR #44

The M4 session's read-only check of PR #44, on `435cc78`, rebased onto `main` at `7c6d536`,
against the plan found no blocker and no major; three minors are the review's major 2 in a
narrower shape. Each item is fixed or answered here, test first, each new row watched failing
against a plant in `build/mut-review3/NAME/`, rebuilt from the check's description by
`mutants.py`, and each also run against `435cc78`'s own `test-open-db-config` and
`test-open-db-config-engines` to reproduce the finding.

- **M1, a set that writes the start beside a PRAGMA.** The moved starts held `()`,
  call-with-database with none and lists of one op only; the six PRAGMAs' list was judged against
  the unmoved start alone. The check's plant, `(dqs-dml 1013 1 #t)` consed onto the steps
  whenever one is a PRAGMA's and the list doesn't name `dqs-dml`, passed every slice suite, and so
  did the builder's V-def0-beside-pragma, `(defensive 1010 0 #f)` the same way. A new row,
  `c-moved-beside`, judges every list of more than one setting over the moved starts, each on a
  file of its own, since `journal-mode` mismatches on `:memory:`: the six PRAGMAs and
  `statement-cache`, every op at its moved value; each PRAGMA beside each list of one op, the
  opt-in's `#t` and `#f` among them, 48 lists with the opt-in, its op as asked, the opt-in's `#f`
  keeping its moved value, and the other three moved; and the six, `statement-cache` and the four
  together, each op as asked.
- **M2, nothing held the moves to moving.** `c-moved`'s expected values came from `move-to`, the
  same list the entry point writes, so the check's identity plant in the suite,
  `(- 1 (cadr (car cells)))` made `(cadr (car cells))`, passed all 30 rows, and with R1 on top
  still passed 30 on Guix's library, the floor and 3.54.1 (reproduced here; only
  `m4s5-lib-defensive`'s unmoved start rows caught it). Now `moves-expected` is computed apart,
  from a fresh `raw-starts` read, 1 for a start of 0 and 0 for one of 1, every moved row's
  expected values come from it, and `c-moved` asserts too that each op's moved read differs from
  its start.
- **M3, nothing held the order across PRAGMAs and sets.** The check's plant, `settled`'s loop
  taking every PRAGMA's step first, then the four's, passed every slice suite. A new row,
  `c-order`: through applied-settings/with, the steps `settings-plan`'s, a stand-in notes at each
  set the cells of `ENABLE_FKEY` (1002) and `TRUSTED_SCHEMA` (1017), the flags `foreign_keys` and
  `trusted_schema` set, read by -1 reads through native's binding on the handle it is given, then
  passes the call on. Two lists interleave the two PRAGMAs with three sets, each PRAGMA asked off
  the connection's own start, `busy-timeout` among them, so each note shows which PRAGMAs had
  applied when the set was made.
- **N1, `e-once` counted applied answers as whole calls.** A run taken past the last set answers
  applied again and makes no call, as open-database's past its last section answers the same
  connection; the check's plant, three idle loop turns after `settled`, made such runs reachable
  and the row failed falsely, `(new-where-the-control-made-none 2)` at fuel 76 (reproduced:
  `435cc78`'s `e-once` fails it). Whole calls are now counted from the stand-in's notes, each the
  first set's call: a whole call makes every set once, a refused run none, a run past the sets
  none. The plant, Q-idle-turns, now passes every suite, as an equivalent mutant must.
- **N2, the non-integer code had no row.** `c-failures` gains two cases: a stand-in answering an
  inexact 1.0, from `open-database`, and the symbol `oops`, from `call-with-database`, each the
  assertion violation from the who given, `(not-an-error X)`, with the connection closed first
  and every count 0. The check's plant, `names-error?`'s exact-integer test dropped, fails it:
  `bitwise-and` refuses 1.0 inside the section, and its own violation, named `bitwise-and`, is
  raised instead.
- **N3, `database-extension-loading?`'s owner check wasn't held.** A new row, `c-opt-in-thread`:
  called from another thread, on a connection that opted in and on one that did not, it raises
  `&sqlite-wrong-thread`, naming itself; on the owner's thread it answers. The thread's answer is
  whatever it raised, and the wait is bounded, 120 s. The check's plant, the reader checking
  `database?` alone, fails it.
- **N4, the entry points dropped their answers.** `switch-on` notes each call's code and cell, and
  `move-starts` each open's four, a raise noted as `(raised TEXT)`; `c-switch-on` asserts every
  call answered `(0 1)`, and `c-moved` every open's four answers are `moves-expected`. Q-switch-raises
  and Q-move-raises, a cell fill no C int holds, so the entry point's call raises inside it, fail
  them by name.
- **N5, `s-messages` checks the names by containment.** It stays so. ADR-0013, decision 9, has
  tests assert a condition's type, its reason or code and its fields, never its message, and the
  M4 slice 1 review's `c-messages` held fixed messages only as strings, not empty and unlike each
  other, never against a text of the suite's. A row that asserts the whole message writes the
  message into the suite, which that rule forbids; what the brief asked, that the two refusals
  name the eleven, is a property of the text, and containment of each of the suite's own eleven
  names is the check that asserts it and nothing the rule leaves free. AGENTS.md's "assert whole
  outputs" is met where the output is the library's data, as every other row here does.
- **N6, `e-fuel`'s held count.** The log said 40; the check measured 39 on four libraries. The
  sweep's fuels begin with no collection, so a collect request can move an expiry by a tick: this
  slice's runs printed 40 on every library in rounds 1 and 3 and on Guix's in round 2, and 39 on
  the floor, 3.54.1 and `m4s5-lib-defensive` in round 2; round 3's gate run printed 40. The table under "Green" now says 39 or 40.
- **The shards.** Both new suites move from `MEMORY_SUITES_2` to `MEMORY_SUITES_1`, in the list's
  order, by the CI times under "Green".

| Plant | What it plants | `435cc78`'s rows | This round's rows |
|---|---|---|---|
| Q-dqs-beside-pragma | the check's M1: `(dqs-dml 1013 1 #t)` beside any PRAGMA, unasked | survived on all four libraries | `c-moved-beside` on all four |
| V-def0-beside-pragma | `(defensive 1010 0 #f)` beside any PRAGMA, unasked | `c-start` on `m4s5-lib-defensive` alone | `c-moved-beside` on Guix's, the floor and 3.54.1; `c-start` on `m4s5-lib-defensive` |
| Q-identity | the check's M2, in the suite: each move the start itself | survived on all four | `c-moved`, `c-moved-unasked`, `c-moved-held`, `c-moved-others`, `c-moved-beside` on all four |
| Q-identity-R1 | the same, with R1 | survived on Guix's, the floor and 3.54.1 | the same five on all four, and `c-start`, `c-start-one` on `m4s5-lib-defensive` |
| Q-reorder | the check's M3: every PRAGMA's step before the four's | survived | `c-order` on all four |
| Q-idle-turns | the check's N1: three idle loop turns after `settled` | `e-once` failed falsely | passes, equivalent |
| Q-not-integer | the check's N2: the exact-integer test dropped | survived | `c-failures` on all four |
| Q-owner-unchecked | the check's N3: the reader checks `database?` alone | survived | `c-opt-in-thread` on all four |
| Q-move-raises | `move-starts`' `dqs-dml` call given a fill no C int holds | `c-moved`, `c-moved-unasked`, `c-moved-others` by their reads, on all four | `c-moved` by its answers too, and the moved rows, `c-moved-beside` among them, on all four |
| Q-switch-raises | `switch-on`'s call given a fill no C int holds | `c-switch-on` by its reads, on all four | `c-switch-on` by its answers too, on all four |

The committed driver ran every plant again on the final tree, in `build/mut-r4/`, on Guix's
3.53.1: **67 plants, 65 caught; R4 survives, argued in round 2, and Q-idle-turns, which changes
nothing a caller can see.** The new rows added these failures to the third round's: R1 and R2
`c-moved-beside`; R6 `c-moved-beside`.

This round's red, the final suites on `7c6d536`'s `src/` and docs (`build/mut-red3/RED/`):
`test-open-db-config` 8 passed, 25 failed of 33, the new `c-moved-beside`, `c-order` and
`c-opt-in-thread` among the failures; `test-open-db-config-engines` 4 passed, 8 failed.

After the round, on `435cc78`'s tree with its changes: `make test` ran 79 and passed 79 on Guix's
3.53.1, the floor's 3.45.1, 3.54.1 and `m4s5-lib-defensive`, each library's variables set inside
the container's `sh -c` and its version read from its P4 line; `test-open-db-config` passed 33
rows on each. Under `make test-memory` on Guix's library the two suites this round touched
passed, none `SLOW`: `test-open-db-config` 14 s, from 12, its three new rows, `c-moved-beside`'s 50 file opens among them; and
`test-open-db-config-engines` 55 s.

## The lead's verification

The lead reran each round's checks itself, every library's variables set inside the container's
`sh -c`. It also planted mutants of its own, written from their descriptions, never the
builder's copies. Its plants are kept in [research/m4-slice-3/lead/](research/m4-slice-3/lead/),
for `plant.py`, each run from the copy it makes on Guix's library, and on the floor and 3.54.1
where noted.

| Round | Plant | Guards | Failed |
|---|---|---|---|
| 1 | M1 | the DQS ops (swapped) | `test-open-db-config` 4, `test-settings` 8 |
| 1 | M2 | the opt-in from its step (any set) | the record's row, and two `steps-opt-in?` rows |
| 1 | M3 | the refusal's `who` (fixed to `open-database`) | `test-library-loading-real`'s decoy row alone: every in-process library has the entry point |
| 1 | M4 | a mismatch's fields (expected and actual swapped) | `test-open-db-config` 4 |
| 1 | M5 | the record's opt-in (always `#t`) | the record's row |
| 2 | N1 | `defensive` set to 0 at every open, unless named (the review's R1) | the moved-start rows, on Guix's, the floor and 3.54.1; the first round's suite passes it 26 of 26 |
| 2 | N2 | `dqs-dml` set to 1 at every open (R2) | the moved-start rows, on all three |
| 2 | N3 | `defensive` set to 1 beside the opt-in (R3) | "a list naming one op", on all three |
| 2 | N4 | `(defensive . #f)` skipped and answered a match (R6) | the moved-start rows, on all three |
| 3 | K1 | `dqs-dml` set to 1 beside any PRAGMA (the check's M1) | "settings beside PRAGMAs", on all three |
| 3 | K2 | the moves held on their own (the entry point moving each op to its start) | five moved-start rows, on all three; with N1's code too, the same five |
| 3 | K3 | the order across PRAGMAs and sets (PRAGMAs first) | the order row, on all three |
| 3 | K4 | a code that is no exact integer (its test dropped) | the stand-in row |
| 3 | K5 | the reader's owner check (only `database?`) | the reader's two rows |

M1 to M5 and N1 to N4 were planted again on round 3's tree, and each was still caught. Two of the
builder's traps were reproduced from their plants: `trap-two-whole.json` fails 522 trials of
correct code under a sequential judge, and `trap-idle-turns.json`'s equivalent plant fails the
first round's `e-once` at fuel 76, `(new-where-the-control-made-none 2)`, and passes this round's.
The host-variable trap was reproduced by its command, and the unlisted option by the FFI, `(0 0)`
of `DEFAULT_DEFENSIVE` and its prefixed name among 39 options.

| Round | `make test`, each of four libraries | Under the gate, Guix's library |
|---|---|---|
| 1, on `7dac918` | 79 of 79 | `test-open-db-config` 12 s, its engines suite 56 s, `test-settings` 10 s, `test-open-settings` 14 s, `test-public` 10 s, `test-reference` 10 s, `test-docs` 34 s, `test-library-loading-real` 175 s, `test-open-engines` 23 s, `test-open-interleave` 37 s |
| 2, on `7dac918` | 79 of 79 | `test-open-db-config` 12 s, its engines suite 56 s, `test-docs` 34 s |
| 3, on `7c6d536` | 79 of 79 | `test-open-db-config` 13 s, its engines suite 56 s |

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
- **The M4 plan's §4.7** (the lead's edit): its "op set unasked" bullet says each plant is set
  "the opposite way from the start where CI's libraries start it, so a Linux lane sees it"; it
  should also record that a row comparing against a library's start cannot see a plant that
  writes the start's own value, nor a set skipped where the value asked is the start (the
  review's R1, R2 and R6), and that this slice holds those by moving every start first, through
  an entry point `sqlite3_auto_extension` runs at every open (round 2, item 2).
- **ADR-0018 and ADR-0021's slice 3 amendment, round 2:** the moved starts' four rows, and the
  sweeps' straddle count; `e-failing`'s guard counted against the fuels.
- **Round 3, for the lead's records:**
  - the M4 plan's §4.7 note above holds for lists of more than one setting too: a start row
    judges only the lists it opens, so every shape of list a plant can key on, a PRAGMA beside an
    op among them, is judged over moved starts (M1);
  - an expected value must not come from the code under test's own list, the suite's included:
    `moves-expected` is computed apart from `move-to` (M2);
  - ADR-0018, decision 5's order across PRAGMAs and the four is held by `c-order` (M3);
  - ADR-0021's "a code that is no exact integer is `not-an-error`" is held by `c-failures`' two
    new cases (N2), and `database-extension-loading?`'s owner check by `c-opt-in-thread` (N3);
  - a sweep counts whole calls by their effects, never by how many runs answered: a run past the
    call's last section answers again (N1); traps.md may want the line, beside the merge trap;
  - the shards: both new suites in `MEMORY_SUITES_1`.
- **traps.md:** the four traps below; the third confirms an entry M4's pre-work made for
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
- **A compile option a library is built with can be unlisted.** The lead's
  `build/m4s5-lib-defensive/`, 3.54.1 built `-DSQLITE_DEFAULT_DEFENSIVE`, lists no
  `DEFAULT_DEFENSIVE` in `sqlite3_compileoption_get`, and `sqlite3_compileoption_used` of it
  answers 0; its -1 read of `DEFENSIVE` answers `(0 1)`. As Apple's (traps.md, M4's pre-work), so
  a start is read through the op, never from the options.
- **A row that compares with a start cannot see a set that writes the start.** Slice 3's start
  rows read each op on the suite's own connection, then on open-database's, and compared them:
  they held every plant that moves an op off its start, and none that writes the start's own
  value. On Guix's 3.53.1, `defensive` set to 0 at every open (R1) and `dqs-dml` set to 1 (R2)
  passed every suite, and so did `defensive`'s `#f` skipped and answered a match (R6), since
  `c-held`'s read of 0 is the start too. Move each start first, by an entry point
  `sqlite3_auto_extension` runs at every open, then compare: `c-moved-unasked` and
  `c-moved-held` fail them. Reproduce: `mut.py --into build/mut-review prepare R1`, from
  [the driver](research/m4-slice-3/scripts/); its copy passes the first round's `test-open-db-config` on
  Guix's library, and fails this round's.
