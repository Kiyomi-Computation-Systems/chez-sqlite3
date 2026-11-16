# M3 slice 1 mutation log

Evidence that each rule slice 1's six suites claim to guard fails through the property it names
([M3 plan](2026-11-15-m3-plan.md) §5, slice 1: the pure core). Format of
[the M2 slice 1 log](m2-slice-1-mutation-log.md).

Two Opus agents built the slice test first, in parallel, each in its own worktree and on disjoint
files, and each kept its own part of this log, merged here unchanged but for its headings:

- **Part A:** `(chez-sqlite3 private settings)`, `transaction-plan` and `statement-cache`, new, with
  `test-settings`, `test-transaction-plan` and `test-statement-cache`. 159 mutations, 155 caught,
  4 survivors argued equivalent.
- **Part B:** `(chez-sqlite3 private conditions)`, extended, and `script` and `interrupt`, new, with
  `test-conditions`, `test-script` and `test-interrupt`. 100 mutations, 95 caught, 5 survivors
  argued equivalent.

In all, 259 mutations, 250 caught, and 9 survivors, each argued below. *Changed by the review's
fixes (the last section): 249 caught and 10 survivors, S79 now equivalent.*


## Part A: the settings, the transaction plan and the cache

Evidence that each rule part A's three suites claim to guard fails through the property it names
([M3 plan](2026-11-15-m3-plan.md) §5, slice 1: the pure core). Format of
[the M2 slice 1 log](m2-slice-1-mutation-log.md).

Part A is `(chez-sqlite3 private settings)`, `transaction-plan` and `statement-cache`, all new, with
their suites `test-settings`, `test-transaction-plan` and `test-statement-cache`. An Opus agent
built it test first from the lead's brief, in its own worktree, on files disjoint from part B's.
Every mutation ran in its own copy of the working tree, made in the session scratchpad without
`.git` or `build/`, through that copy's own `scripts/guix-env`, after `make deps` in the copy. A
mutation changes one place in one library under `src/`, and the driver checks that the old text
occurs the stated number of times (each did). The three suites then run, each under `timeout 60`.
The counts below are read from the suites' own output (`# of unexpected failures`), never by eye;
a suite that died with no count would be marked `died` (none did), and one that timed out `hung`.
The driver and the mutation definitions are in the session scratchpad, not the repository.

### The red runs

Each suite was written first and run against a stub library with the same exports: every
procedure answered the symbol `stub`, and so did each exported list. The stubs were then
replaced. The red runs below are of the final suites against the stubs, in a copy of the tree.

| Suite | Red run, against the stub | Green run |
|---|---|---|
| `test-settings` | 10 passed, 46 failed | 56 passed |
| `test-transaction-plan` | 5 passed, 31 failed | 36 passed |
| `test-statement-cache` | 6 passed, 22 failed | 28 passed |

The rows that passed against a stub are rows a stub can satisfy:

- **each suite's exports row:** the stub has the same exports;
- **the suites' own fixtures:** the universe of 71 values, SQLite's 79 PRAGMAs and the 146 names
  left out, the bad entries as `shown-value` shows them, the 13,700 orderings, the 576 exits of
  24 begins, the 720 orders, 9,331 sequences, 2,801 sequences with a clear and the 400-move
  sequence, the cache's model checked by hand, and `(chezscheme)`'s names counted;
- **the rows that the library changes nothing:** the split and the plan leave their lists as they
  were;
- **the totality rows:** the stub raises nothing, as the libraries mustn't;
- **one cross-check:** "a failed commit's rollback is the raise's rollback at the same level". The
  two stub answers agree. T30, T31, T34 and T35 watch the plans themselves fail.

### The mutations

Baselines, from the green runs: settings 56, transaction-plan 36, statement-cache 28. *(Changed by
the review's fixes: 59, 37 and 32.)* Each row
names the suites that failed and how many rows failed in each. A mutation counts as caught when
at least one row failed, or its suite hung.

**159 mutations: 155 caught, one of them by a hang, and 4 survived;** each survivor is argued
below. *(Changed by the review's fixes: 154 caught and 5 survived, S79 added; see the last
section.)* The whole set was run twice, the second time after the last edit to the libraries, which
was to their comments alone. Both runs gave the same answer for every mutation. In both, every
suite a mutation left passing ran at its green count, and every failing run counted all its rows.

#### Settings: the split

| Mutation | Guards | Failed |
|---|---|---|
| S01 | () is no settings list | settings 3 |
| S02 | an improper pair is no settings list | settings 1 |
| S03 | a second list replaces the first | settings 3 |
| S04 | a second list ignored, the first kept | settings 3 |
| S05 | the options reversed | settings 4 |
| S06 | no list gives #f, not () | settings 2 |
| S07 | the settings list copied, not the caller's own | settings 3 |
| S08 | the second list's rule misnamed | settings 3 |

#### Settings: the list's shape

| Mutation | Guards | Failed |
|---|---|---|
| S09 | a proper list not required: the cyclic list loops | settings hung |
| S10 | a name need not be a symbol | settings 1 |
| S11 | an entry need not be a pair | settings 4 |
| S12 | the shape refusal shown raw | settings 2 |
| S13 | no shape check | settings 5 |
| S14 | the shape rule misnamed | settings 4 |

#### Settings: names and repeats

| Mutation | Guards | Failed |
|---|---|---|
| S15 | an unknown name not refused | settings 5 |
| S16 | a name twice not refused | settings 5 |
| S17 | twice checked before unknown | SURVIVED |
| S19 | statement-cache not remembered as seen | settings 2 |
| S20 | busy-timeout not remembered as seen | settings 4 |
| S21 | the other settings not remembered as seen | settings 5 |
| S22 | the unknown rule misnamed | settings 5 |
| S23 | the twice rule misnamed | settings 5 |

S18 was dropped before the first run: no one-place edit made the domain check run before the
repeat check without changing other rules too.

#### Settings: the domain refusal

| Mutation | Guards | Failed |
|---|---|---|
| S24 | statement-cache's domain rule misnamed | settings 2 |
| S25 | a step's domain rule misnamed | settings 6 |
| S26 | statement-cache's refused value shown raw | settings 2 |
| S27 | a step's refused value shown raw | settings 5 |
| S28 | a step's refusal names no setting | settings 6 |

#### Settings: the capacity and the integer domains

| Mutation | Guards | Failed |
|---|---|---|
| S29 | the default capacity 33 | settings 8 |
| S30 | statement-cache's largest 1025 | settings 2 |
| S31 | statement-cache's largest 1023 | settings 2 |
| S32 | an inexact integer accepted | settings 2 |
| S33 | an exact rational accepted | settings 1 |
| S34 | 0 refused | settings 5 |
| S35 | the largest refused | settings 5 |
| S36 | negatives accepted | settings 5 |
| S37 | statement-cache's value not the capacity | settings 5 |
| S38 | busy-timeout's largest 2^31 | settings 2 |
| S39 | busy-timeout's largest 2^31-2 | settings 4 |
| S40 | busy-timeout's domain unchecked | settings 4 |

#### Settings: the order and the SQL

| Mutation | Guards | Failed |
|---|---|---|
| S41 | busy-timeout planned in the list's order | settings 2 |
| S42 | the steps reversed | settings 2 |
| S43 | busy-timeout last | settings 2 |
| S44 | busy-timeout written in hexadecimal | settings 6 |
| S45 | the set SQL without its spaces | settings 6 |
| S46 | the read SQL in lower case | settings 6 |
| S47 | busy_timeout's PRAGMA misspelt | settings 6 |
| S48 | the expected value dropped from a step | settings 7 |
| S49 | the name dropped from a step | settings 7 |
| S50 | busy-timeout planned as an enumerated setting | settings 12 |

#### Settings: the enumerated table

| Mutation | Guards | Failed |
|---|---|---|
| S51 | foreign-keys written swapped | settings 4 |
| S52 | trusted-schema written swapped | settings 4 |
| S53 | foreign-keys read back swapped | settings 4 |
| S54 | journal-mode memory accepted | settings 5 |
| S55 | journal-mode persist refused | settings 5 |
| S56 | wal written WAL | settings 4 |
| S57 | extra read back as 4 | settings 5 |
| S58 | off written 1 | settings 2 |
| S59 | temp-store memory read back as 1 | settings 3 |
| S60 | temp_store's PRAGMA misspelt | settings 4 |
| S61 | journal_mode's PRAGMA misspelt | settings 4 |
| S62 | an enumerated value matched by equal? | SURVIVED |
| S63 | any value of an enumerated setting accepted | settings 8 |
| S64 | trusted-schema not a setting | settings 9 |
| S65 | cache-size a setting name | settings 3 |
| S66 | the rules list without setting-given-twice | settings 1 |

#### Settings: raise-setting-refusal

| Mutation | Guards | Failed |
|---|---|---|
| S67 | who unchecked | settings 1 |
| S68 | who shown raw | settings 1 |
| S69 | the refusal unchecked | settings 2 |
| S70 | a refusal of any rule accepted | settings 1 |
| S71 | a name rule's refusal with more details accepted | settings 1 |
| S72 | a second-list refusal with details accepted | settings 1 |
| S73 | a domain refusal with more details accepted | settings 1 |
| S74 | the rule dropped from the irritants | settings 1 |
| S75 | a fixed who | settings 1 |
| S76 | a continuable raise | settings 1 |
| S77 | not-a-refusal shown raw | settings 1 |

#### Settings: the read-back and the comparison

| Mutation | Guards | Failed |
|---|---|---|
| S78 | an outsider read as #f | settings 8 |
| S79 | a read-back matched by eqv?, so TEXT never | settings 3 |
| S80 | a name no setting has read through foreign-keys' table | settings 5 |
| S81 | the comparison by equal? | SURVIVED |
| S82 | the mismatch's actual raw | settings 2 |
| S83 | the mismatch's fields swapped | settings 2 |
| S84 | always a match | settings 2 |

#### Transaction-plan: the mode

| Mutation | Guards | Failed |
|---|---|---|
| T01 | exclusive no mode | transaction-plan 10 |
| T02 | savepoint a mode | transaction-plan 2 |
| T03 | an unknown mode shown raw | transaction-plan 3 |
| T04 | the unknown mode's rule misnamed | transaction-plan 6 |
| T05 | every mode answered as immediate | transaction-plan 1 |

#### Transaction-plan: the begin

| Mutation | Guards | Failed |
|---|---|---|
| T06 | deferred begun as plain BEGIN | transaction-plan 4 |
| T07 | immediate begun exclusive | transaction-plan 6 |
| T08 | exclusive begun immediate | transaction-plan 4 |
| T09 | the default mode deferred | transaction-plan 4 |
| T10 | the begin's autocommit inverted | transaction-plan 11 |
| T11 | the begin reads only 1 as autocommit | transaction-plan 1 |
| T12 | the mode unchecked at autocommit 0 | transaction-plan 1 |
| T13 | the mode unchecked by the begin | transaction-plan 3 |
| T14 | the savepoint's name without its underscore | transaction-plan 10 |
| T15 | the savepoint named one deeper than its level | transaction-plan 6 |
| T16 | the level one deeper than its name | transaction-plan 6 |
| T17 | SAVEPOINT without its space | transaction-plan 6 |

#### Transaction-plan: the statements

| Mutation | Guards | Failed |
|---|---|---|
| T18 | COMMIT spelt END | transaction-plan 6 |
| T19 | RELEASE SAVEPOINT | transaction-plan 5 |
| T20 | ROLLBACK TRANSACTION | transaction-plan 7 |
| T21 | a savepoint's rollback without its RELEASE | transaction-plan 5 |
| T22 | a savepoint's rollback in the wrong order | transaction-plan 5 |
| T23 | a savepoint committed by COMMIT | transaction-plan 10 |

#### Transaction-plan: the exits

| Mutation | Guards | Failed |
|---|---|---|
| T24 | begun ignored | transaction-plan 2 |
| T25 | ended ignored | transaction-plan 7 |
| T26 | a later return does nothing, told nothing | transaction-plan 7 |
| T27 | a later escape told the transaction ended | transaction-plan 3 |
| T28 | a return commits after its transaction ended | transaction-plan 4 |
| T29 | a return's autocommit inverted | transaction-plan 8 |
| T30 | a raise rolls back a level gone | transaction-plan 5 |
| T31 | a raise rolls nothing back | transaction-plan 7 |
| T32 | an escape commits | transaction-plan 4 |
| T33 | a return with none begun answered as nothing | transaction-plan 2 |

#### Transaction-plan: a failed commit

| Mutation | Guards | Failed |
|---|---|---|
| T34 | a failed commit rolls back a level gone | transaction-plan 2 |
| T35 | a failed commit rolls nothing back | transaction-plan 4 |
| T36 | a failed commit committed again | transaction-plan 4 |

#### Transaction-plan: raise-transaction-refusal

| Mutation | Guards | Failed |
|---|---|---|
| T37 | who unchecked | transaction-plan 1 |
| T38 | who shown raw | transaction-plan 1 |
| T39 | a refusal with more details accepted | transaction-plan 1 |
| T40 | a refusal of any rule accepted | transaction-plan 1 |
| T41 | the rule dropped from the irritants | transaction-plan 2 |
| T42 | a fixed who | transaction-plan 1 |
| T43 | not-a-refusal shown raw | transaction-plan 1 |
| T44 | a continuable raise | transaction-plan 1 |

#### Statement-cache: return

| Mutation | Guards | Failed |
|---|---|---|
| C01 | capacity 0 not special: it keeps one | statement-cache 6 |
| C02 | a held key filed again | statement-cache 6 |
| C03 | a duplicate return answers the held one | statement-cache 6 |
| C04 | full one too late | statement-cache 11 |
| C05 | full one too early | statement-cache 11 |
| C06 | the newest evicted | statement-cache 9 |
| C07 | an eviction not answered | statement-cache 10 |
| C08 | an evicted key left in the hashtable | statement-cache 9 |
| C09 | an evicted entry left in the list | statement-cache 7 |
| C10 | a returned entry not linked | statement-cache 12 |
| C11 | capacity 0 answers nothing | statement-cache 6 |
| C12 | a duplicate return touches the held one | statement-cache 4 |

#### Statement-cache: check-out

| Mutation | Guards | Failed |
|---|---|---|
| C13 | a check-out left in the hashtable | statement-cache 11 |
| C14 | a check-out left in the list | statement-cache 7 |
| C15 | a miss answered as a hit | statement-cache 12 |
| C16 | a hit answers its key | statement-cache 11 |

#### Statement-cache: the list

| Mutation | Guards | Failed |
|---|---|---|
| C17 | unlink loses the newest end | statement-cache 4 |
| C18 | unlink loses the oldest end | statement-cache 8 |
| C19 | unlink drops the newer's link | statement-cache 2 |
| C20 | unlink drops the older's link | statement-cache 3 |
| C21 | push links nothing older | statement-cache 4 |
| C22 | push never sets the oldest | statement-cache 10 |
| C23 | push leaves a newer link | SURVIVED |

#### Statement-cache: clear, make and count

| Mutation | Guards | Failed |
|---|---|---|
| C24 | clear answers newest first | statement-cache 5 |
| C25 | clear leaves the hashtable | statement-cache 4 |
| C26 | clear leaves the oldest end | statement-cache 2 |
| C27 | clear leaves the newest end | statement-cache 1 |
| C28 | clear walks from the newest | statement-cache 5 |
| C29 | clear walks toward the older | statement-cache 5 |
| C30 | keys matched by eqv? | statement-cache 13 |
| C31 | the count one high | statement-cache 14 |
| C32 | the capacity one high | statement-cache 15 |

C26 and C27 leave the table's ends after a clear. The model's sequences first ended with their
one clear, so they never used a table cleared midway. The 2,801 sequences of up to four moves with a
clear among them were added before the first run for these two. They are the one row that
catches C27; C26 fails them and the double-clear row.

### The survivors

No row catches these four, and none can: each is equivalent to the code at every value its
callers can pass.

| Mutation | Why it is equivalent |
|---|---|
| S17 | The repeat check before the name check. `seen` holds only names that passed the name check, so an unknown name is never in it, and a known name passes the name check either way. |
| S62 | An enumerated value matched by `equal?` for `eq?`. Every value of the table is a symbol or a boolean, and `equal?` agrees with `eq?` whenever one side is one. |
| S81 | The comparison by `equal?` for `eqv?`. EXPECTED is a step's expected value: an exact integer below 2^31, a boolean or a symbol. `equal?` agrees with `eqv?` whenever one side is one. A string or a list as EXPECTED would tell them apart, and no plan answers one. |
| C23 | `push-newest!` without its clearing of the entry's newer link. It is called only on a fresh entry, made with both links `#f`. |

### Rules the mutants do not cover

- **The refusals' messages** are not asserted, by ADR-0013 decision 9, so a mutant that changes
  only their text survives by design. None was run.
- **The cache's records are sealed and opaque.** That is observable only through Chez's
  internals, which no suite uses, as M2 slice 1's V64 argued. None was run.
- **Totality inside a critical section.** The libraries hold none. The totality rows call every
  procedure on junk under a guard, and slices 3 to 5 hold the sections.

### Findings

- **`make check-suites` reads quoted data as exit forms.** The transaction suite's first draft
  tagged its walk's events `(exit return 0)`. As data, these are `(exit ...)` forms before the
  last datum, and `check-suites` refused all 17 of them and the `case` clause `((exit) …)`. The
  check holds by its own rule, which reads every datum. The tag is now `leave`, and the suite's
  comment says why.
- **Chez's `map` calls its procedure in pairs from the end.** On 10.4.0, in a `--program`,
  `(map f '(0 1 2 3 4 5))` called `f` on 4, 5, 2, 3, 0, then 1; over 0 to 31 it called 30 first,
  and over 0 to 1023, 1022. Two cache rows first filled the table through `map` and failed: the
  33rd return evicted `select 30`, not `select 0`. That is AGENTS.md's rule ("`map` calls its
  procedure in no fixed order"), met here; the rows fill through a loop now. Reproduced with
  `build/probe/map-order.sps` in the worktree, not kept.
- **SQLite's own PRAGMA table and its documentation differ.** The floor's `aPragmaName`, in
  `sqlite3.c` of `sqlite-amalgamation-3450100.zip`, holds 78 names. The "List Of PRAGMAs" of
  sqlite.org/pragma.html, read on 2026-11-15, holds 74. The table adds `activate_extensions`,
  `lock_proxy_file`, `lock_status`, `sql_trace` and `vdbe_eqp`, and the page adds
  `legacy_file_format`. `test-settings` refuses the union, 79 names, in both spellings.
- **Six PRAGMA names have no underscore:** `encoding`, `fullfsync`, `optimize`, `stats`,
  `synchronous` and `threads`. So SQLite's spelling of `synchronous` is also ours, and the
  complement is 146 names, not 152. The suite's first count missed it.


## Part B: the conditions, the script's offsets and the interrupt

Evidence that each rule part B's three suites claim to guard fails through the property it names
([M3 plan](2026-11-15-m3-plan.md) §5, slice 1: the pure core). Format of
[the M2 slice 1 log](m2-slice-1-mutation-log.md).

Part B is `(chez-sqlite3 private conditions)`, extended with `&sqlite-interrupt`,
`&sqlite-setting-mismatch` and `&sqlite-transaction-ended` (ADR-0013, amended for M3), and two new
libraries, `(chez-sqlite3 private script)`, a script's error offsets (§4.1, ADR-0016 decision 7),
and `(chez-sqlite3 private interrupt)`, the interrupt's exclusion (§4.4, ADR-0019), with their
suites `test-conditions`, `test-script` and `test-interrupt`. Every mutation ran in its own copy of
the working tree, made in the session scratchpad without `.git`, `build/` or `.claude/`, through
that copy's own `scripts/guix-env`, after `make deps` in the copy. A mutation changes one place in
one library under `src/`, the driver checks that the old text occurs the stated number of times
(each occurred once), and the three suites then run, each under `timeout 120`. The counts below are
read from the suites' own output (`# of unexpected failures`), never by eye; a suite that died with
no count, or hung, would be marked so (none did). The driver and the mutation definitions are in the
session scratchpad, not the repository.

### The red runs

Each suite was written first and run against a stub library with the same exports: every new
procedure answered the symbol `stub`. In `conditions` the three new condition types were real, and
the procedures M2 built, `sqlite-error-subtype` and `make-sqlite-error`, kept M2's behaviour, which
classes no interrupt. The stubs were then replaced.

| Suite | Red run, against the stub | Green run |
|---|---|---|
| `test-conditions` | 63 passed, 20 failed | 83 passed |
| `test-script` | 3 passed, 17 failed | 20 passed |
| `test-interrupt` | 1 passed, 18 failed | 19 passed |

The rows that passed against a stub are rows a stub can satisfy:

- `test-conditions`: M2's 70 rows, widened, less the 7 the new class changes, which failed; all 13
  new rows failed. The widened rows that passed read only the real types or what M2 already did:
  the exports row (the stub has the exports), the row that a subtype keeps every field (the stub
  built a plain error, which keeps them), locked's row, the predicates false for non-conditions,
  the parents and fields rows, the integers and non-symbols classed none, and the invalid-text
  compound read through the wider matrix. C01 to C45 watch those that matter fail.
- `test-script`: the exports row and two that check the suite's own fixture: the script's 37
  characters and 44 bytes with tables of 45 entries, and its encoding at the bytes the layout
  names.
- `test-interrupt`: the exports row.

The interrupt suite's opacity row was added after its first red run (1 passed, 17 failed), and
the suite was run red again against the same stub: the 18 failures above. The opacity row fails
against the stub, whose answer is no latch; I35 watches its opacity half fail.

### The mutations

Baselines, from the green runs: conditions 83, script 20, interrupt 19. Each row names the suites
that failed and how many rows failed in each. A mutation counts as caught when at least one row
failed.

**100 mutations, 95 caught, 5 survived;** each survivor is argued below. The conditions and script
mutations ran against the final suites. The interrupt mutations ran twice, before and after the
engine rows' fuels were narrowed from 1 to 30 to 1 to 10; the table is the second run, and every
verdict and count was the same in both.

#### Conditions: `&sqlite-interrupt`'s class

| Mutation | Guards | Failed |
|---|---|---|
| C01 | interrupt unclassed by sqlite-error-subtype | conditions 9 |
| C02 | interrupt classed as busy | conditions 9 |
| C03 | busy and locked classed as interrupt | conditions 10 |
| C04 | interrupt joins busy's clause | conditions 9 |
| C05 | the integer 9 classed interrupt | conditions 2 |
| C06 | readonly classed as interrupt | conditions 6 |
| C07 | every other value classed interrupt | conditions 9 |
| C08 | make-sqlite-error builds interrupt plain | conditions 6 |
| C09 | interrupt built as busy | conditions 6 |
| C10 | busy built as interrupt | conditions 7 |
| C11 | a plain code built interrupt | conditions 5 |
| C12 | classed by the extended code | conditions 4 |
| C13 | &sqlite-interrupt under the root | conditions 8 |
| C14 | &sqlite-interrupt under &sqlite-busy | conditions 6 |
| C15 | &sqlite-interrupt given a field | conditions 8 |

#### Conditions: the types under the root

| Mutation | Guards | Failed |
|---|---|---|
| C16 | &sqlite-setting-mismatch under &error, no root | conditions 3 |
| C17 | &sqlite-setting-mismatch under &sqlite-closed | conditions 3 |
| C18 | &sqlite-transaction-ended under &error, no root | conditions 4 |
| C19 | &sqlite-transaction-ended under &sqlite-closed | conditions 4 |
| C20 | &sqlite-transaction-ended given a field | conditions 5 |

#### Conditions: `&sqlite-setting-mismatch`'s fields and refusals

| Mutation | Guards | Failed |
|---|---|---|
| C21 | setting accessor reads expected | conditions 3 |
| C22 | expected accessor reads actual | conditions 3 |
| C23 | actual accessor reads setting | conditions 3 |
| C24 | constructor swaps expected and actual | conditions 3 |
| C25 | constructor skips the setting check | conditions 2 |
| C26 | constructor takes a string setting | conditions 2 |
| C27 | setting refusal names the wrong field | conditions 2 |
| C28 | setting refusal shows the value raw | conditions 2 |
| C29 | setting refusal from the wrong who | conditions 2 |
| C30 | setting accessor unchecked | conditions 2 |
| C31 | expected accessor refuses from the wrong who | conditions 1 |
| C32 | actual accessor's predicate too wide | conditions 1 |

#### Conditions: the raisers

| Mutation | Guards | Failed |
|---|---|---|
| C33 | raise-setting-mismatch skips the who check | conditions 1 |
| C34 | raise-setting-mismatch's who refusal names the constructor | conditions 1 |
| C35 | raise-setting-mismatch drops the who | conditions 1 |
| C36 | raise-setting-mismatch adds irritants | conditions 1 |
| C37 | raise-setting-mismatch drops the message | conditions 1 |
| C38 | raise-setting-mismatch can be resumed | conditions 1 |
| C39 | raise-setting-mismatch swaps expected and actual | conditions 1 |
| C40 | raise-transaction-ended skips the who check | conditions 1 |
| C41 | raise-transaction-ended drops the who | conditions 1 |
| C42 | raise-transaction-ended can be resumed | conditions 1 |
| C43 | raise-transaction-ended adds irritants | conditions 1 |
| C44 | raise-transaction-ended raises a closed | conditions 1 |
| C45 | raise-transaction-ended drops the message | conditions 1 |

#### Script: a prepare's offset

| Mutation | Guards | Failed |
|---|---|---|
| S01 | the prepare's START ignored | script 3 |
| S02 | the prepare's byte offset answered, not the character | script 2 |
| S03 | -1 answers the byte before START | script 2 |
| S04 | no lower bound on OFFSET | script 3 |
| S05 | the prepare one byte late | script 4 |
| S06 | no upper bound on START + OFFSET | survived |
| S07 | OFFSET's type unchecked | script 1 |
| S08 | the prepare answers START's character | script 3 |
| S09 | START's type unchecked | script 2 |
| S10 | BYTES' type unchecked | script 2 |
| S11 | START past the end allowed | survived |
| S12 | START below 0 allowed | script 2 |

#### Script: a step's offset

| Mutation | Guards | Failed |
|---|---|---|
| S13 | the step answers START's character, no scan | script 9 |
| S14 | the step scans from the script's start | script 6 |
| S15 | the step's byte offset answered | script 5 |
| S16 | the step one byte late | script 8 |
| S17 | the step's START and BYTES unchecked | script 1 |
| S18 | the step scans from START + 1 | script 6 |
| S19 | the step answers START's character after the scan | script 8 |

#### Interrupt: the exclusion

| Mutation | Guards | Failed |
|---|---|---|
| I01 | the interrupt without the mutex (required) | interrupt 1 |
| I02 | the close clears the flag after its work (required) | interrupt 3 |
| I03 | the close's clear without the mutex | interrupt 1 |
| I04 | the interrupt without its critical section | interrupt 1 |
| I05 | the close without its critical section | interrupt 1 |
| I06 | the flag's set without its critical section | survived |
| I07 | the flag's set without the mutex | interrupt 1 |
| I10 | the interrupt reads the flag under the mutex, then calls with it released | interrupt 1 |
| I20 | the mutex held across the close's work | interrupt 1 |
| I31 | the flag's set under a mutex of its own | interrupt 1 |
| I32 | the interrupt under a mutex of its own | interrupt 1 |
| I34 | the close's set again without the mutex | survived |

#### Interrupt: the flag

| Mutation | Guards | Failed |
|---|---|---|
| I08 | the interrupt whatever the flag | interrupt 11 |
| I09 | the interrupt only when the flag is clear | interrupt 17 |
| I14 | the interrupt answers #t when it called nothing | interrupt 10 |
| I15 | the interrupt answers #f when it called | interrupt 11 |
| I16 | the interrupt calls twice | interrupt 12 |
| I17 | a close left open never sets the flag again | interrupt 5 |
| I18 | every close sets the flag again | interrupt 8 |
| I19 | the flag set again when the close closed | interrupt 9 |
| I27 | a fresh latch interruptible | interrupt 1 |
| I28 | the open does nothing | interrupt 10 |
| I29 | the open clears the flag | interrupt 10 |
| I30 | the close sets the flag where it clears it | interrupt 10 |
| I33 | the flag's set ignores its value | interrupt 10 |

#### Interrupt: the close's answer and its raises

| Mutation | Guards | Failed |
|---|---|---|
| I11 | the interrupt's raise inside the section | interrupt 3 |
| I12 | the interrupt's raise resumable | interrupt 1 |
| I13 | the interrupt answers its raise | interrupt 3 |
| I21 | the close answers its predicate's answer | interrupt 2 |
| I22 | the close's work called twice | interrupt 4 |
| I23 | the close's raise inside the section | interrupt 3 |
| I24 | the close's raise resumable | interrupt 1 |
| I25 | the close answers its raise | interrupt 3 |
| I26 | a raising close sets the flag again | interrupt 2 |

#### Interrupt: the record

| Mutation | Guards | Failed |
|---|---|---|
| I35 | the latch not opaque | interrupt 1 |
| I36 | the latch not sealed | survived |

#### What catches the exclusion

The brief's two mutants fail the two-thread row, the one the latch exists for:

- **I01, the interrupt without the mutex:** the notes came out `(interrupt-start work-start
  work-end interrupt-end)`. The close cleared the flag while the interrupt was in flight, and its
  work started before the interrupt ended.
- **I02, the flag cleared after the close's work:** `(interrupt-start work-start interrupt-end
  late-interrupt work-end)`, the late try answering `#t`: the work started while the interrupt
  was in flight, and an interrupt tried during the work called its stand-in. Two one-thread rows
  fail too: the flag read inside the work, and a raising work's latch left interruptible.
- **I03, I07, I10, I31 and I32** fail the same row as I01, each a way for the close's clear not to
  wait for an interrupt in flight. **I20**, the mutex held across the close's work, fails it
  through the late try: the work's bounded wait for it timed out, `work-end-with-the-try-unended`.
- **I04, the interrupt without its critical section,** fails the engine row at fuels 5 to 10, each
  `(work interrupt-start interrupt-end)`: the expiry fell after the flag was read, its unwind let
  the mutex go, the close ran in the gap, and the resume took the mutex again and called the
  stand-in after the close's work. **I05, the close without its section,** fails the abandoned
  close's row at fuels 4 to 10: the flag cleared and nothing else done, or the work begun and
  never finished, with the connection left open and the latch not interruptible.

The row is one run of three threads. It is deterministic, not a race sampled many times: the
stand-in in flight waits, bounded, for the close's work to start, which only a broken exclusion
lets happen, and the late try is asked for from inside the work. So one iteration is the fewest at
which the mutants fail, and the stand-in's wait, 200 ms, is the row's whole cost when the latch is
right. Every other wait is 5 s or 15 s and elapses only when something is wrong.

### The survivors

No row catches these five, and none can: each is equivalent to the code at every value its stated
type allows, or unobservable from a test.

| Mutation | Why it is equivalent or unobservable |
|---|---|
| S06 | The upper bound on START + OFFSET dropped. `utf8-offset->index` answers `#f` for an offset past the length by its own check, so the bound is made twice, and dropping one changes no answer. |
| S11 | A START past the end allowed. In the prepare, OFFSET is at least 0, so START + OFFSET is past the end too, and the upper bound refuses it; in the step, `sql-tail-statement` answers `#f` for a START at or past the length. No value reaches another answer. |
| I06 | The section around the flag's set removed. Inside the close, the close's own section holds the clear and the set again; I05 removes that one and fails. That leaves the open, whose body under the mutex is one write of the flag. An engine's expiry inside `with-mutex` runs its after thunk and lets the mutex go, and the resume takes it again before the write (measured, `probe-engine-mutex.sps` below), so no thread waits on a suspended holder, and the write is whole or not made either way. A timer's or keyboard handler could run holding the mutex only at an event check between the take and the write, and no row can put one there. Slice 6's open also runs it inside its own section. |
| I34 | The close's set again without the mutex. The write makes the flag true on a connection the work left open. An interrupter reads the flag only under the mutex: before the write it calls nothing, dropping an interrupt on an open connection, and after it, it interrupts an open connection, so no interleaving reaches a closed one. The mutex adds the ordering that lets a later reader see the write, which no test on amd64 can tell from a plain store. It stays for ADR-0019 decision 2's "sets the flag again the same way". |
| I36 | `sealed` removed from the latch's type, as M2 slice 1's V64. The type's name, constructor and predicate are not exported, so no code outside the library can name it as a parent; sealing is observable only through Chez's internals (`#%$record-type-descriptor`), which no suite uses. Opacity, I35, is held by a row. |

### Rules the mutants do not cover

- **Message texts.** No row reads one (ADR-0013, decision 9), so a mutant that rewords the fixed
  `&message` of `raise-setting-mismatch` or `raise-transaction-ended` survives by design. None was
  run; C37 and C45 drop the message, and fail.
- **The latch's procedures check no argument.** They are private, given the connection record's
  own latch and the library's own procedures, and the close runs inside a caller's section, where
  a refusal could not be raised.
- **M1's and M2's conditions** are held by their own rows, unchanged in what they assert; the rows
  this slice widened assert the new predicates' columns beside the old ones. The M2 log's
  mutations of the other classes were not rerun.

### Findings

- **An engine's expiry inside `with-mutex` lets the mutex go, and the resume takes it again**
  (Chez 10.4.0). An expiry runs a `dynamic-wind`'s after thunk, and `with-mutex` is one. So a
  mutex held by `with-mutex` is never left held across an engine's suspension, but `with-mutex`
  alone doesn't keep a read and a call together against this thread's engine: I04 split them at
  every fuel from 5 to 10. The critical section does. Reproduced by
  `build/m3s1b-probes/probe-engine-mutex.sps` in the part B worktree (git-ignored):
  `expired; log (before after); mutex free`, then `resumed to done; log (before after before
  after)`, and inside a critical section no expiry until it ends.
- **A prepare's −1 says nothing of which statement failed.** ADR-0016 decision 7 gives `#f` for
  it, and the library follows it; ADR-0013's M3 amendment says the offset "says which statement
  failed". The two agree once "the token SQLite points at" is read as "if it points at one", but
  for single script X6's missing table and X8's incomplete input the error then carries the whole
  script and no offset. `script-step-offset` would give the failing statement's first token
  there instead: a choice for slice 3's loop, and the records', not this library's. *(Decided
  afterwards, the maintainer, 2026-11-15, "Point at the statement": -1 answers it. See the last
  section.)*
- **Chez 10.4.0 has `thread-join`, and it answers no value.** A thread's answer is posted to a
  slot under a mutex instead, and the thread joined only once it has answered, so no join waits
  without a bound.
- **`condition-wait` works inside a critical section,** and waits out its timeout there. The
  two-thread row's stand-in waits so, holding the latch's mutex, as no real `sqlite3_interrupt`
  would; Chez deactivates a thread blocked in `condition-wait` or on a contended mutex, so no
  collection waits on it beyond its bound.


## The review's fixes

Evidence for the six fixes the slice's review asked for, made in the same worktree on the same
files and given the same treatment: each new or changed row watched failing, against a copy of the
library as it was before the fix (a red run) or against a mutant that undoes the fix. Every run was
in its own copy of the tree under `build/fixes/` (git-ignored), made without `.git` or `build/`,
through the copy's own `scripts/guix-env` after `make deps` in it. Counts are read from the
suites' own output. The driver and the mutation definitions are in the session scratchpad, not the
repository. Suites now: settings 59 rows, transaction-plan 37, statement-cache 32, script 22,
interrupt 19, all green, and `make test` passes (43 suites).

### The red runs

Each is the final suite against the library as the slice's first commit left it, in a copy.

| Fix | Suite | Red run | The rows that failed |
|---|---|---|---|
| 1, `failed-commit-plan` takes `ended` | `test-transaction-plan` | 30 passed, 7 failed | the failed-commit rows (the new three-argument call), the new "ended set" row, the cross-check with the raise's rollback, the walks of a failed commit and of a release, every-statement, totality |
| 3, the read-back's `(row V)` or `none`, journal-mode's symbol | `test-settings` | 48 passed, 11 failed | the table's read-back, outsiders, busy-timeout's and statement-cache's, journal-mode's TEXT and its integers and BLOBs, the new no-row rows (the reader and the comparison), the comparison's sweep, the Q9 mismatches, each step's own expected value |
| 4, string keys, the `eq?` return | `test-statement-cache` | 30 passed, 2 failed | the very statement returned again; a key that is no string raises |
| 5, -1 points at the statement | `test-script` | 20 passed, 2 failed | -1 at every START, 0 to 44; X5, X6 and X8 |

Fix 2 (the exit row's model as an explicit table) changes a test's oracle, not a library: its
evidence is the T1 to T8 mutants below. Fix 6 (the interrupt row) is the I-mutants' table, which
also holds the row's own red run.

Rows that passed in a red run, though new: in `test-statement-cache`, "a different statement
returned under a held key" and "a statement equal? and not eq? to the held one". The library
already answered `(S)` there, and the rows hold that it still does (K7, K8, K5 fail them).

### Fix 1 to 5: the mutants

Each row names the suites that failed and how many rows failed in each.

| Mutation | Guards | Failed |
|---|---|---|
| F1a | `failed-commit-plan` ignores `ended` | transaction-plan 1 |
| F1b | `failed-commit-plan` ignores autocommit | transaction-plan 2 |
| F1c | `failed-commit-plan` rolls back only when ended | transaction-plan 5 |
| T1 | the table: a raise after the end rolls back | transaction-plan 1 |
| T2 | the table: a return after the transaction ended answers nothing | transaction-plan 1 |
| T3 | the table: a return never begun commits | transaction-plan 1 |
| T4 | the table: an escape at autocommit 0 does nothing | transaction-plan 1 |
| T5 | the table: a first return rolls back | transaction-plan 1 |
| T6 | `exit-plan`: never begun treated as begun | transaction-plan 2 |
| T7 | `exit-plan`: a return after the end answers nothing | transaction-plan 7 |
| T8 | `exit-plan`: a raise rolls back at any autocommit | transaction-plan 5 |
| R1 | `none` read as a match, when expected is `()` | settings 1 |
| R2 | none's actual is `none`, not `()` | settings 2 |
| R3 | journal-mode text left a string | settings 4 |
| R4 | every setting's text read as a symbol | settings 4 |
| R5 | journal-mode text folded to lower case | settings 3 |
| R6 | any pair read as `(row V)` | settings 2 |
| R7 | `(row V W)` read as a row | settings 1 |
| R8 | only `()` read as no row | settings 3 |
| K1 | `equal?` keys | statement-cache 1 |
| K2 | keys folded by case | statement-cache 1 |
| K3 | the `eq?` return finalized | statement-cache 1 |
| K4 | the `eq?` test inverted | statement-cache 9 |
| K5 | `equal?` for `eq?` in the held test | statement-cache 1 |
| K6 | the `eq?` return moves the held one to newest | statement-cache 1 |
| K7 | a different statement under a held key removes the held one | statement-cache 7 |
| K8 | the `eq?` return answers the held statement to finalize | statement-cache 1 |
| P1 | -1 answers `#f` | script 2 |
| P2 | -1 points at START, not the first token | script 4 |
| P3 | every negative offset points at the statement | script 1 |
| P4 | -1 scans from byte 0, not START | script 2 |
| P5 | -1 with no first token answers 0 | script 3 |
| P6 | no START check | script 1 |

**33 mutations, 33 caught, none survived.** T1 to T5 mutate the table in the suite and fail it
against the unchanged `exit-plan`: the table is an oracle that can be wrong, and is checked. T6 to
T8 mutate `exit-plan` and fail against the table.

- **K6 survived the first draft of the `eq?` row,** which returned the held statement again with
  nothing filed after it; moving it to newest changed no answer. The row now files a second
  statement first and returns the first again, then checks that the next eviction is still the
  first. K6 fails it.
- **K1, `equal?` keys, is equivalent over strings,** so the suite's string rows cannot tell it. What
  tells it is the row that a key that is no string raises, from `string-hash`: the table's domain,
  which the header now says in so many words. It is a behaviour the header states and no caller
  reaches (the caller passes a string it has copied and checked), and a reviewer may prefer the
  row dropped and K1 left as a survivor.

### Fix 6: the interrupt row, the four ways it was run

The six I-mutants that the row catches by the stand-in's wait. "old" is the row as the slice's
first commit left it, "new" the fixed row; "delay" adds a 1 s `sleep` to the closer, before it says
it is calling close (the old row: before it calls close), as `test-interrupt-delayed.sps` did.
Each cell is the number of rows that failed, or SURVIVED when the suite passed.

| Mutation | Guards | old | old, delay | new | new, delay |
|---|---|---|---|---|---|
| I01 | the interrupt without the mutex | 1 | SURVIVED | 1 | 1 |
| I03 | the close's clear without the mutex | 1 | SURVIVED | 1 | 1 |
| I07 | the flag's set without the mutex | 1 | SURVIVED | 1 | 1 |
| I10 | the interrupt reads the flag under the mutex, then calls with it released | 1 | SURVIVED | 1 | 1 |
| I31 | the flag's set under a mutex of its own | 1 | SURVIVED | 1 | 1 |
| I32 | the interrupt under a mutex of its own | 1 | SURVIVED | 1 | 1 |
| correct code | | passes | passes | passes | passes |

The "old, delay" column is the review's finding, six survivors, and the red run of the fix. The
new row fails every one, plain and delayed, and the correct code passes all four. The suite's run
on the correct code, wall time with the container's start and the library's load: 372 ms old and
372 ms new; with the delay, 1377 ms. The row's own cost is the stand-in's 200 ms wait when the
latch is right, unchanged. A mutant failing the new row alone takes 170 ms: it fails without waiting
the 200 ms out.

**What the fix does not cover.** The closer's note comes just before its call. A closer descheduled
between the two, for longer than the stand-in's 200 ms wait, would still let a mutant through. That
window is two calls wide and holds no lock; the delay the review measured, before the closer's
wait, is covered.

### The earlier mutations, rerun

The 214 mutations of part A (159) and part B's script (19) and interrupt (36) libraries, against
the changed libraries and suites; part B's 45 `conditions` mutations were not rerun, for
`conditions.sls` and its suite are unchanged. Each ran its library's suites: part A's three, or
`test-script`, or `test-interrupt`. In every run, each suite a mutation left passing ran at its
new green count.

**214 mutations: 204 caught and 10 survived.** 194 ran as defined, 186 caught (S09 by a hang, as
before) and 8 survived. 20 no longer applied to the text, and are restated below.

- **Survivors as before, 7:** S17, S62, C23 (part A), S11, I06, I34 and I36 (part B). Each is argued
  in its part's survivors.
- **S79 is new, and equivalent.** "A read-back matched by `eqv?`, so TEXT never": the table's TEXT
  words are lower-case journal-mode names, and the new reader turns any other TEXT into
  `string->symbol` of it, so "wal" read as the symbol `wal` either way. No answer differs. It was
  caught before the fix, by the string staying a string.
- **S82 no longer compiles** (`raw` is no variable now) and is restated as S82b.

The 20 that no longer applied, restated for the new text, each the same change in the new code:

| Mutation | Guards | Failed |
|---|---|---|
| S78b | an outsider read as `#f` (S78) | settings 8 |
| S80b | a name no setting has read through foreign-keys' table (S80) | settings 5 |
| S81b | the comparison by `equal?` (S81) | SURVIVED |
| S82b | the mismatch's actual raw (S82) | settings 3 |
| S84b | always a match (S84) | settings 3 |
| T34b | a failed commit rolls back a level gone (T34) | transaction-plan 3 |
| T35b | a failed commit rolls nothing back (T35) | transaction-plan 4 |
| T36b | a failed commit committed again (T36) | transaction-plan 4 |
| C01b | capacity 0 not special: it keeps one (C01) | statement-cache 6 |
| C02b | a held key filed again (C02) | statement-cache 9 |
| C03b | a duplicate return answers the held one (C03) | statement-cache 9 |
| C12b | a duplicate return touches the held one (C12) | statement-cache 5 |
| C30b | keys matched by `eqv?` (C30) | statement-cache 17 |
| script S01b | the prepare's START ignored | script 3 |
| script S02b | the prepare's byte offset answered, not the character | script 2 |
| script S03b | -1 answers the byte before START (it answered it before the fix) | script 3 |
| script S04b | no lower bound on OFFSET | script 1 |
| script S05b | the prepare one byte late | script 4 |
| script S06b | no upper bound on START + OFFSET | SURVIVED |
| script S08b | the prepare answers START's character | script 3 |

S81b survives as S81 did: the expected value is an exact integer, a boolean or a symbol, and
`equal?` agrees with `eqv?` whenever one side is one. S06b survives as S06 did: `utf8-offset->index`
answers `#f` for an offset past the length. Script S07, which ran unchanged, still fails 1 row.

### The totals, as they stand

- **Part A: 159 mutations, 154 caught, 5 survivors:** S17, S62, S79, S81 (as S81b), C23.
- **Part B's script and interrupt: 55 mutations, 50 caught, 5 survivors,** the same five as before:
  S06 (as S06b), S11, I06, I34, I36. Its 45 conditions mutations: unchanged, 45 run, all caught.
- **All: 259 mutations, 249 caught, 10 survivors.** The fixes' own 33 mutations and the 28 runs of the
  interrupt row, above, are not among the 259.

### Findings

- **The `none` read-back needed a rule of its own.** With the read-back's input a raw value, a
  statement that answered no row had no spelling: `()` would have matched an expected `()`, and
  nothing in the domain is `()`, but "never a match" is stronger than "no setting expects `()`".
  The comparison checks the row first. R1 shows the check is load-bearing.
- **`journal-mode` as a symbol makes the table's TEXT rows redundant for the words in the table,**
  S79's equivalence. They stay: the table is the contract, and the symbol rule is the fallback.
- **The old exit-row model was the code.** T1 to T5, mutants of the table itself, fail the suite, which
  the copied `cond` could not have shown: a wrong line in both would have agreed with itself.

