# M2 slice 1 mutation log

Evidence that each rule the slice's five suites claim to guard fails through the property it names
([M2 plan](2026-11-14-m2-plan.md) section 5, slice 1: the pure core). Format of
[the M1 slice 1 log](m1-slice-1-mutation-log.md).

The slice is `(chez-sqlite3 private values)`, `utf8`, `statement-state` and `sql-tail`, new, and
`conditions`, extended, with their suites `test-values`, `test-utf8`, `test-statement-state`,
`test-sql-tail` and `test-conditions`. A Sonnet agent built it test first from the maintainer's
brief. Every mutation ran in its own copy of the working tree, made in the session scratchpad
without `.git`, `build/` or `.claude/`, through that copy's own `scripts/guix-env`, after
`make deps` in the copy. A mutation changes one place in one library under `src/`, the driver
checks that the old text occurs the stated number of times (each did), and the five suites then
run. The counts below are read from the suites' own output (`# of unexpected failures`), never by
eye, and a suite that died with no count would be marked `died` (none did). The driver and the
mutation definitions are in the session scratchpad, not the repository.

## The red runs

Each suite was written first and run against a stub library with the same exports: every
procedure answered the symbol `stub`, and the condition types were real. The stubs were then
replaced. The red runs below are of the final suites against their stubs. After the review's
fixes (below) they were rerun against stubs with the new `read-column-bytes` arity and the
`sql-null-type` name; `test-conditions` changed no count (one row moved).

| Suite | Red run, against the stub | Green run |
|---|---|---|
| `test-conditions` | 52 passed, 18 failed | 70 passed |
| `test-values` | 4 passed, 37 failed | 41 passed |
| `test-utf8` | 9 passed, 34 failed | 43 passed |
| `test-statement-state` | 2 passed, 21 failed | 23 passed |
| `test-sql-tail` | 7 passed, 26 failed | 33 passed |

The rows that passed against a stub are rows a stub can satisfy:

- `test-conditions`: M1's 43 rows, which the stub left alone, and 9 new ones that read only the
  table or the real types: the exports row, the three table-size rows (108, 31 and 103 codes),
  `make-sqlite-error`'s check-order row, the subtype-keeps-its-fields row (the stub built plain
  errors, which keep them), the four predicates false for non-conditions, and the two rows that
  read the types' parents and fields. The subtype rows that matter are the ones that failed, and
  C01 to C17 watch them.
- `test-values`: the exports row; `sql-null` is one value and no record; `record-rtd` refuses it
  (the stub's null was opaque too); and the secret row, whose stub raises nothing, so no text
  holds the secret. Mutants V42 (the value shown) and V49 (a parameter name shown) are what watch that
  last one fail.
- `test-utf8`: the exports row and eight rows that check the suite's own oracles (the 1,920-form
  set, the 2-byte count, the edge-set sizes, the oracle against the 2-byte set, the form lists,
  the 11-byte string). They hold the oracles the other rows use, and need no library.
- `test-statement-state`: the exports row, and the row that an answer is one of the five states,
  which the stub's one-element list satisfies.
- `test-sql-tail`: the exports row and six rows that count the suite's own fixtures (SQLite's
  list, SQLite's 3-byte list, the NUL inputs, the SQL lengths, the insertion points).

## The mutations

Baselines, from the green runs: conditions 70, values 41, utf8 43, statement-state 23, sql-tail
33. Each row names the suites that failed and how many rows failed in each. A mutation counts as
caught when at least one row failed.

**470 mutations, 461 caught, 9 survived;** each survivor is argued below. This is the whole set
rerun after the review's fixes: the first 437 with the old texts adapted where a fix changed
them (the reader's, the record type's name, the message's, `strict-utf8->string`'s), and 33 new
(N04 to N36). U120, a survivor before, is now caught.

### Conditions: the subtype mapping

| Mutation | Guards | Failed |
|---|---|---|
| C01 | locked no longer busy | conditions 5 |
| C02 | busy no longer busy (locked only) | conditions 8 |
| C03 | constraint unclassed | conditions 6 |
| C04 | readonly unclassed | conditions 5 |
| C05 | busy classed as constraint | conditions 9 |
| C06 | constraint classed as read-only | conditions 6 |
| C07 | readonly classed as busy | conditions 5 |
| C08 | every other value classed busy | conditions 8 |
| C09 | a non-symbol raises (totality) | conditions 4 |
| C10 | extended-name classing: an extended code name classed busy | conditions 3 |
| C11 | an integer code 5 classed busy | conditions 2 |

### Conditions: make-sqlite-error builds the subtype

| Mutation | Guards | Failed |
|---|---|---|
| C12 | classes by the extended code, not the primary | conditions 4 |
| C13 | busy built plain | conditions 6 |
| C14 | constraint built plain | conditions 4 |
| C15 | read-only built plain | conditions 3 |
| C16 | busy built as constraint | conditions 6 |
| C17 | plain code built busy | conditions 4 |
| C18 | the subtype built before the checks (offset unchecked) | conditions 2 |

### Conditions: the types and their parents

| Mutation | Guards | Failed |
|---|---|---|
| C19 | &sqlite-busy under the root | conditions 13 |
| C20 | &sqlite-constraint under &error | conditions 7 |
| C21 | &sqlite-read-only under &sqlite-busy | conditions 4 |
| C22 | &sqlite-invalid-text under &sqlite-error | conditions 6 |
| C23 | &sqlite-invalid-text under &error, no root | conditions 3 |

### Conditions: &sqlite-invalid-text

| Mutation | Guards | Failed |
|---|---|---|
| C24 | column accessor reads the offset | conditions 3 |
| C25 | offset accessor reads the column | conditions 3 |
| C26 | constructor skips the column check | conditions 2 |
| C27 | constructor skips the offset check | conditions 2 |
| C28 | column refusal names the offset field | conditions 2 |
| C29 | offset refusal names the column field | conditions 2 |
| C30 | column refusal shows the value raw | conditions 1 |
| C31 | constructor swaps the fields | conditions 3 |
| C32 | constructor accepts any integer for the column (negative) | conditions 2 |

### Conditions: raise-invalid-text

| Mutation | Guards | Failed |
|---|---|---|
| C33 | who not checked | conditions 1 |
| C34 | no &who in the compound | conditions 2 |
| C35 | no &message in the compound | conditions 1 |
| C36 | continuable raise | conditions 1 |
| C37 | fields swapped on the way in | conditions 2 |
| C38 | irritants added | conditions 1 |
| C39 | who replaced by a fixed symbol | conditions 1 |

### Conditions: raise-sqlite-error still classes

| Mutation | Guards | Failed |
|---|---|---|
| C40 | raise-sqlite-error builds a plain error (make-sqlite-error bypassed) | conditions 3 |
| C41 | raise-sqlite-error classes by the extended name | conditions 4 |

### Values: the integer boundary

| Mutation | Guards | Failed |
|---|---|---|
| V01 | 2^63 accepted | values 2 |
| V02 | 2^63-1 refused | values 1 |
| V03 | -2^63 refused | values 1 |
| V04 | -2^63-1 accepted | values 1 |
| V05 | upper bound 2^64 (unsigned) | values 2 |
| V06 | range refusal named not-a-value | values 1 |
| V07 | range refusal named nan | values 1 |
| V08 | an inexact integer counts as an exact one | values 3 |
| V09 | an integer plan holds the wrapped value | SURVIVED |

### Values: doubles

| Mutation | Guards | Failed |
|---|---|---|
| V10 | NaN accepted | values 2 |
| V11 | NaN refused as not-a-value | values 1 |
| V12 | infinities refused | values 1 |
| V13 | +inf.0 refused alone | values 1 |
| V14 | -0.0 normalised to 0.0 | values 1 |
| V15 | a flonum rounded to an integer | values 1 |
| V16 | a double plan tagged int64 | values 2 |
| V17 | a non-flonum real accepted as a double | values 1 |

### Values: text

| Mutation | Guards | Failed |
|---|---|---|
| V18 | text plan tagged blob | values 2 |
| V19 | U+0000 dropped from text | values 1 |
| V20 | text cut at the first U+0000 | values 1 |
| V21 | text encoded as UTF-16 | values 2 |
| V22 | text refused (a string is not-a-value) | values 2 |

### Values: blobs

| Mutation | Guards | Failed |
|---|---|---|
| V23 | blob not copied | values 2 |
| V24 | blob plan tagged text | values 2 |
| V25 | blob truncated by one byte | values 2 |
| V26 | blob refused | values 3 |

### Values: null and the rest

| Mutation | Guards | Failed |
|---|---|---|
| V27 | null plan refused | values 1 |
| V28 | null plan carries a payload | values 1 |
| V29 | a boolean refused as not-a-value | values 1 |
| V30 | a boolean bound as 1 or 0 | values 2 |
| V31 | #f bound as null | values 1 |
| V32 | anything else bound as null | values 2 |
| V33 | anything else refused as boolean | values 1 |
| V34 | a symbol bound as text | values 2 |
| V35 | a char bound as an integer | values 1 |
| V36 | an exact rational bound as a double | values 1 |
| V37 | bind-plan raises on a pair (totality) | values 2 |

### Values: the rule list

| Mutation | Guards | Failed |
|---|---|---|
| V38 | rules in another order | values 1 |
| V39 | a rule dropped from the list | values 4 |
| V40 | a rule renamed in the list | values 4 |

### Values: raise-bind-refusal

| Mutation | Guards | Failed |
|---|---|---|
| V41 | the rule left out of the irritants | values 5 |
| V42 | the value shown, not its kind | values 6 |
| V43 | the value's kind taken from the parameter | values 5 |
| V44 | the parameter always shown by kind | values 3 |
| V45 | the parameter always shown itself | values 2 |
| V46 | 0 shown as a position | values 1 |
| V47 | an inexact whole number shown as a position | values 1 |
| V48 | a negative number shown as a position | values 1 |
| V49 | a parameter name shown itself (a string) | values 2 |
| V50 | the parameter's kind taken from the value | values 1 |
| V51 | the rule check dropped | values 1 |
| V52 | a bad rule not led by not-a-rule | values 1 |
| V53 | a bad rule shown raw | values 1 |
| V54 | a bad rule raised from the caller | values 1 |
| V55 | the refusal raised from raise-bind-refusal, not WHO | values 4 |
| V56 | a bad rule accepted when it is a symbol | values 1 |
| V57 | a bad rule check on the wrong list (accepts none) | values 1 |
| V58 | the refusal is continuable (a returning handler gets a value) | values 5 |

### Values: sql-null

| Mutation | Guards | Failed |
|---|---|---|
| V59 | sql-null? true for () too | values 2 |
| V60 | sql-null? true for everything | values 16 |
| V61 | sql-null? true for the symbol sql-null | values 2 |
| V62 | sql-null? true for any record of the type name (records of any type) | values 3 |
| V63 | not opaque: record-rtd opens it | values 3 |
| V64 | not sealed | SURVIVED |
| V65 | nongenerative (a fixed uid) | SURVIVED |
| V66 | sql-null a fresh instance per reference (a procedure result) | values 2 |

### Values: read-column-bytes

| Mutation | Guards | Failed |
|---|---|---|
| R01 | ERRCODE called before POINTER | values 8 |
| R02 | ERRCODE called after a non-zero pointer | values 3 |
| R03 | BYTES called before ERRCODE on a zero pointer | values 5 |
| R04 | ERRCODE called twice on a zero pointer | values 5 |
| R05 | COPY called on a zero pointer | values 3 |
| R06 | COPY before BYTES | values 3 |
| R07 | COPY called with the length for the pointer | values 3 |
| R08 | COPY called with one byte too many | values 3 |
| R09 | COPY answer not returned | values 3 |
| R10 | POINTER called twice | values 8 |
| R11 | BYTES called twice | values 3 |
| R12 | NOMEM tested on the whole code | values 2 |
| R13 | NOMEM tested against ioerr-nomem low byte 10 | values 4 |
| R14 | NOMEM tested on 7 low bits | values 1 |
| R15 | NOMEM tested on 4 low bits | values 1 |
| R16 | NOMEM tested on 9 low bits | values 2 |
| R17 | NOMEM is any code up to 7 | values 2 |
| R18 | NOMEM is any non-zero code | values 3 |
| R19 | NOMEM is 100 (row) too | values 2 |
| R20 | the nomem answer holds 7, not the code | values 2 |
| R21 | the nomem answer holds only the symbol | values 3 |
| R22 | the nomem answer holds the masked code | values 2 |
| R23 | the empty answer is one byte | values 3 |
| R24 | the empty answer is #f | values 3 |
| R25 | the zero test is for 1 | values 6 |
| R26 | the zero test inverted | values 8 |
| R27 | the zero test is for any non-positive pointer | SURVIVED |

### Values: read-column-name

| Mutation | Guards | Failed |
|---|---|---|
| R28 | a zero pointer answers the empty name | values 1 |
| R29 | a zero pointer still calls COPY-C-STRING | values 1 |
| R30 | the pointer passed to COPY-C-STRING is off by one | values 1 |
| R31 | NAME called twice | values 2 |
| R32 | the zero test is for 1 | values 1 |
| R33 | the zero test inverted | values 2 |
| R34 | COPY-C-STRING answer replaced | values 1 |
| R35 | the nomem answer misspelt | values 1 |

### Utf8: Table 3-7, each row's bounds

| Mutation | Guards | Failed |
|---|---|---|
| U01 | two byte 1: lower bound + 1 (min refused) | utf8 10 |
| U02 | two byte 1: lower bound - 1 (min-1 accepted) | utf8 5 |
| U03 | two byte 1: upper bound + 1 (max+1 accepted) | utf8 5 |
| U04 | two byte 1: upper bound - 1 (max refused) | utf8 10 |
| U05 | E0 byte 1: lower bound + 1 (min refused) | utf8 10 |
| U06 | E0 byte 1: lower bound - 1 (min-1 accepted) | utf8 5 |
| U07 | E0 byte 1: upper bound + 1 (max+1 accepted) | utf8 1 |
| U08 | E0 byte 1: upper bound - 1 (max refused) | utf8 6 |
| U09 | E0 byte 2: lower bound + 1 (min refused) | utf8 9 |
| U10 | E0 byte 2: lower bound - 1 (min-1 accepted) | utf8 1 |
| U11 | E0 byte 2: upper bound + 1 (max+1 accepted) | utf8 1 |
| U12 | E0 byte 2: upper bound - 1 (max refused) | utf8 6 |
| U13 | ED byte 1: lower bound + 1 (min refused) | utf8 6 |
| U14 | ED byte 1: lower bound - 1 (min-1 accepted) | utf8 1 |
| U15 | ED byte 1: upper bound + 1 (max+1 accepted) | utf8 6 |
| U16 | ED byte 1: upper bound - 1 (max refused) | utf8 10 |
| U17 | ED byte 2: lower bound + 1 (min refused) | utf8 6 |
| U18 | ED byte 2: lower bound - 1 (min-1 accepted) | utf8 1 |
| U19 | ED byte 2: upper bound + 1 (max+1 accepted) | utf8 1 |
| U20 | ED byte 2: upper bound - 1 (max refused) | utf8 9 |
| U21 | E1-EF byte 1: lower bound + 1 (min refused) | utf8 10 |
| U22 | E1-EF byte 1: lower bound - 1 (min-1 accepted) | utf8 4 |
| U23 | E1-EF byte 1: upper bound + 1 (max+1 accepted) | utf8 4 |
| U24 | E1-EF byte 1: upper bound - 1 (max refused) | utf8 10 |
| U25 | E1-EF byte 2: lower bound + 1 (min refused) | utf8 10 |
| U26 | E1-EF byte 2: lower bound - 1 (min-1 accepted) | utf8 1 |
| U27 | E1-EF byte 2: upper bound + 1 (max+1 accepted) | utf8 4 |
| U28 | E1-EF byte 2: upper bound - 1 (max refused) | utf8 12 |
| U29 | F0 byte 1: lower bound + 1 (min refused) | utf8 10 |
| U30 | F0 byte 1: lower bound - 1 (min-1 accepted) | utf8 5 |
| U31 | F0 byte 1: upper bound + 1 (max+1 accepted) | utf8 1 |
| U32 | F0 byte 1: upper bound - 1 (max refused) | utf8 7 |
| U33 | F0 byte 2: lower bound + 1 (min refused) | utf8 10 |
| U34 | F0 byte 2: lower bound - 1 (min-1 accepted) | utf8 1 |
| U35 | F0 byte 2: upper bound + 1 (max+1 accepted) | utf8 1 |
| U36 | F0 byte 2: upper bound - 1 (max refused) | utf8 7 |
| U37 | F0 byte 3: lower bound + 1 (min refused) | utf8 10 |
| U38 | F0 byte 3: lower bound - 1 (min-1 accepted) | utf8 1 |
| U39 | F0 byte 3: upper bound + 1 (max+1 accepted) | utf8 1 |
| U40 | F0 byte 3: upper bound - 1 (max refused) | utf8 7 |
| U41 | F1-F3 byte 1: lower bound + 1 (min refused) | utf8 7 |
| U42 | F1-F3 byte 1: lower bound - 1 (min-1 accepted) | utf8 1 |
| U43 | F1-F3 byte 1: upper bound + 1 (max+1 accepted) | utf8 1 |
| U44 | F1-F3 byte 1: upper bound - 1 (max refused) | utf8 7 |
| U45 | F1-F3 byte 2: lower bound + 1 (min refused) | utf8 7 |
| U46 | F1-F3 byte 2: lower bound - 1 (min-1 accepted) | utf8 1 |
| U47 | F1-F3 byte 2: upper bound + 1 (max+1 accepted) | utf8 1 |
| U48 | F1-F3 byte 2: upper bound - 1 (max refused) | utf8 7 |
| U49 | F1-F3 byte 3: lower bound + 1 (min refused) | utf8 7 |
| U50 | F1-F3 byte 3: lower bound - 1 (min-1 accepted) | utf8 1 |
| U51 | F1-F3 byte 3: upper bound + 1 (max+1 accepted) | utf8 1 |
| U52 | F1-F3 byte 3: upper bound - 1 (max refused) | utf8 7 |
| U53 | F4 byte 1: lower bound + 1 (min refused) | utf8 7 |
| U54 | F4 byte 1: lower bound - 1 (min-1 accepted) | utf8 1 |
| U55 | F4 byte 1: upper bound + 1 (max+1 accepted) | utf8 5 |
| U56 | F4 byte 1: upper bound - 1 (max refused) | utf8 11 |
| U57 | F4 byte 2: lower bound + 1 (min refused) | utf8 7 |
| U58 | F4 byte 2: lower bound - 1 (min-1 accepted) | utf8 1 |
| U59 | F4 byte 2: upper bound + 1 (max+1 accepted) | utf8 1 |
| U60 | F4 byte 2: upper bound - 1 (max refused) | utf8 11 |
| U61 | F4 byte 3: lower bound + 1 (min refused) | utf8 7 |
| U62 | F4 byte 3: lower bound - 1 (min-1 accepted) | utf8 1 |
| U63 | F4 byte 3: upper bound + 1 (max+1 accepted) | utf8 4 |
| U64 | F4 byte 3: upper bound - 1 (max refused) | utf8 11 |

### Utf8: Table 3-7, each row's lengths

| Mutation | Guards | Failed |
|---|---|---|
| U65 | two: answers length 3, not 2 | utf8 12 |
| U66 | E0: answers length 4, not 3 | utf8 9 |
| U67 | ED: answers length 4, not 3 | utf8 9 |
| U68 | E1-EF: answers length 4, not 3 | utf8 13 |
| U69 | F0: answers length 5, not 4 | utf8 10 |
| U70 | F1-F3: answers length 5, not 4 | utf8 7 |
| U71 | F4: answers length 5, not 4 | utf8 10 |

### Utf8: Table 3-7, the lead bytes

| Mutation | Guards | Failed |
|---|---|---|
| U72 | 7F no longer ASCII | utf8 10 |
| U73 | 80 accepted as ASCII | utf8 9 |
| U74 | C0 and C1 accepted as leads | utf8 7 |
| U75 | C2 refused as a lead | utf8 10 |
| U76 | C1 accepted as a lead | utf8 6 |
| U77 | DF refused as a 2-byte lead | utf8 10 |
| U78 | E0 taken as a 2-byte lead | utf8 14 |
| U79 | E0 row taken by DF (E0 falls to the wide 3-byte row) | utf8 6 |
| U80 | E1 taken by the E0 row, E0 by the wide one | utf8 9 |
| U81 | ED falls to the wide 3-byte row | utf8 9 |
| U82 | EE taken by the ED row | utf8 8 |
| U83 | EF refused as a 3-byte lead | utf8 12 |
| U84 | F0 taken as a 3-byte lead | utf8 12 |
| U85 | F0 row taken by EF | utf8 5 |
| U86 | F1 taken by the F0 row | utf8 8 |
| U87 | F3 refused as a 4-byte lead | utf8 7 |
| U88 | F4 taken by the wide 4-byte row | utf8 5 |
| U89 | F4 row taken by F3 | utf8 11 |
| U90 | F5 taken by the F4 row | utf8 12 |
| U91 | F5 to FF accepted as one byte | utf8 10 |

### Utf8: the offset rule

| Mutation | Guards | Failed |
|---|---|---|
| U92 | the offset one past the failing sequence | utf8 13 |
| U93 | the offset always 0 | utf8 11 |
| U94 | the offset one before the failing sequence | utf8 10 |
| U95 | the offset the last byte | utf8 12 |
| U96 | a sequence advances one byte, not its length | utf8 15 |
| U97 | a sequence advances one byte short | utf8 15 |
| U98 | the scan starts at byte 1 | utf8 22 |
| U99 | the last byte is never checked | utf8 22 |
| U100 | well-formed answers 0 | utf8 17 |
| U101 | a continuation read one past the end (raises) | utf8 7 |
| U102 | U+0000 refused | utf8 12 |

### Utf8: strict-utf8->string

| Mutation | Guards | Failed |
|---|---|---|
| U103 | the offset in the refusal always 0 | utf8 2 |
| U104 | never refuses | utf8 2 |
| U105 | always refuses | utf8 9 |
| U106 | the refusal tag misspelt | utf8 2 |
| U107 | the refusal is the bare offset | utf8 2 |
| U108 | the last character dropped | utf8 8 |

### Utf8: utf8-offset->index

| Mutation | Guards | Failed |
|---|---|---|
| U109 | -1 accepted (raises) | utf8 2 |
| U110 | 0 refused | utf8 6 |
| U111 | the length refused | utf8 7 |
| U112 | length+1 accepted (raises) | utf8 2 |
| U113 | an inexact offset accepted | utf8 1 |
| U114 | a non-number raises | utf8 1 |
| U115 | no upper bound (raises past the end) | utf8 2 |
| U116 | a continuation byte answers the next index | utf8 5 |
| U117 | a continuation byte answers two back | utf8 5 |
| U118 | a continuation byte never recognised at the offset | utf8 6 |
| U119 | the end read as a byte (raises) | utf8 7 |
| U120 | offset 0 never a continuation (survived before m5; the lone 80 row catches it) | utf8 1 |
| U121 | bytes counted, not characters | utf8 6 |
| U122 | continuations counted, not leads | utf8 7 |
| U123 | only ASCII counted | utf8 5 |
| U124 | ASCII not counted | utf8 3 |
| U125 | the count starts at 1 | utf8 8 |
| U126 | every non-ASCII byte a continuation | utf8 5 |
| U127 | only 80..9F a continuation | utf8 5 |
| U128 | leads taken for continuations | utf8 6 |
| U129 | every byte from 80 a continuation | utf8 5 |
| U130 | BF not a continuation | utf8 2 |

### Sql-tail: whitespace

| Mutation | Guards | Failed |
|---|---|---|
| T_ws20 | 20 no longer starts a run | tail 18 |
| T_ws09 | 09 no longer starts a run | tail 9 |
| T_ws0a | 0A no longer starts a run | tail 16 |
| T_ws0c | 0C no longer starts a run | tail 9 |
| T_ws0d | 0D no longer starts a run | tail 10 |
| T_ws0b | 0B starts a run | tail 7 |
| T_ws85 | 85 starts a run | tail 3 |
| T_ws00 | NUL starts a run | tail 2 |
| T_wsA0 | A0 starts a run | tail 3 |
| T_wc0b | 0B no longer continues a run | tail 5 |
| T_wcall | every byte continues a run | tail 13 |
| T_wcx | 0E continues a run | tail 1 |
| T_wc00 | NUL continues a run | tail 2 |
| T_wc85 | 85 continues a run | tail 1 |
| T_wcA0 | A0 continues a run | tail 1 |
| T_wcsemi | a semicolon continues a run (same offsets) | tail 3 |
| T_run1 | a run skips the byte after its start | tail 13 |
| T_run2 | a run ends one byte late | tail 14 |
| T_run3 | a run reads past the end (raises) | tail 11 |
| T_run4 | a run steps two bytes | tail 7 |
| T_run5 | a run is one byte long | tail 5 |

### Sql-tail: the semicolon

| Mutation | Guards | Failed |
|---|---|---|
| T_semi1 | a semicolon is anything else | tail 16 |
| T_semi2 | a semicolon swallows the next byte | tail 13 |
| T_semi3 | a colon is a semicolon | tail 3 |
| T_semi4 | a semicolon ends the scan | tail 11 |

### Sql-tail: EF BB BF

| Mutation | Guards | Failed |
|---|---|---|
| T_bom1 | first byte EE | tail 7 |
| T_bom2 | second byte BA | tail 7 |
| T_bom3 | third byte BE | tail 7 |
| T_bom4 | the bound allows a short tail (raises) | tail 1 |
| T_bom5 | the bound refuses BOM at the very end | tail 4 |
| T_bom6 | BOM advances two bytes | tail 7 |
| T_bom7 | BOM advances four bytes | tail 3 |
| T_bom8 | BOM only at the start (not wherever it stands) | tail 4 |
| T_bom9 | BOM not recognised at all | tail 7 |
| T_bom10 | EF BB alone accepted | tail 8 |

### Sql-tail: the -- comment

| Mutation | Guards | Failed |
|---|---|---|
| T_line1 | second byte not - | tail 14 |
| T_line2 | - alone accepted | tail 7 |
| T_line3 | -- as the last two bytes refused | tail 4 |
| T_line4 | the comment swallows the newline (to the end) | tail 5 |
| T_line5 | the comment ends at CR, not LF | tail 5 |
| T_line6 | the newline consumed | tail 2 |
| T_line7 | the comment ends at any whitespace | tail 7 |
| T_line8 | the comment ends at LF or NUL | tail 2 |
| T_line9 | the comment ends at LF or 0B | tail 3 |
| T_line10 | the end of the SQL ends it as an error | tail 6 |
| T_line11 | the body starts at i+3 (a -- with the newline right after, "--\n") | tail 6 |
| T_line12 | the body starts at i+1 (equivalent: the byte there is -) | SURVIVED |

### Sql-tail: the /* comment

| Mutation | Guards | Failed |
|---|---|---|
| T_blk1 | first byte not / | tail 12 |
| T_blk2 | second byte not * | tail 12 |
| T_blk3 | /* as the last two bytes accepted | tail 3 |
| T_blk4 | /* needs two bytes after it | tail 5 |
| T_blk5 | the body starts one byte late (/**/ unclosed) | tail 4 |
| T_blk6 | the body starts at the * (/*/ closes) | tail 1 |
| T_blk7 | an unterminated comment is an error | tail 8 |
| T_blk8 | the end test reads past the end (raises) | tail 3 |
| T_blk9 | the end test is one byte early (a closing */ at the last two bytes missed) | SURVIVED |
| T_blk10 | closing * is a + | tail 7 |
| T_blk11 | closing / is a . | tail 7 |
| T_blk12 | the comment ends one byte after the close | tail 6 |
| T_blk13 | the comment ends one byte before the close | tail 8 |
| T_blk14 | the scan after a comment goes on one byte back | tail 6 |
| T_blk15 | comments nest | tail 1 |

### Sql-tail: the answer

| Mutation | Guards | Failed |
|---|---|---|
| T_else1 | the answer is one byte late | tail 16 |
| T_else2 | the answer is 0 | tail 14 |
| T_else3 | anything else is accepted | tail 19 |

### Sql-tail: START and the end

| Mutation | Guards | Failed |
|---|---|---|
| T_end1 | START at the length reads past it (raises) | tail 22 |
| T_end2 | the last byte unscanned | tail 18 |
| T_end3 | START ignored | tail 6 |
| T_end4 | START one byte late | tail 21 |
| T_end5 | the end answers 0 | tail 23 |
| T_end6 | a START past the length answers the length | tail 2 |

### Statement-state: the cells of the matrix

| Mutation | Guards | Failed |
|---|---|---|
| S01 | bind! no longer allowed in ready | state 3 |
| S02 | bind-all! no longer allowed in ready | state 3 |
| S03 | clear-bindings! no longer allowed in ready | state 2 |
| S04 | binds allowed in row | state 3 |
| S05 | binds allowed in done | state 3 |
| S06 | binds allowed in failed | state 2 |
| S07 | binds allowed in row, not ready | state 3 |
| S08 | binds allowed nowhere | state 2 |
| S09 | parameter-count only in ready | state 2 |
| S10 | statement-sql only in ready | state 2 |
| S11 | column-count only in ready | state 2 |
| S12 | reset! only in ready | state 2 |
| S13 | finalize-statement! only in ready | state 2 |
| S14 | step! not allowed in row | state 2 |
| S15 | step! not allowed in ready | state 2 |
| S16 | step! allowed in done | state 2 |
| S17 | step! allowed in failed | state 3 |
| S18 | step! allowed in done, not row | state 2 |
| S19 | step! allowed everywhere | state 3 |
| S20 | reset! limited to ready and row | state 2 |
| S21 | column-count limited to ready and row | state 2 |
| S22 | finalize-statement! limited to ready and row | state 2 |
| S23 | column reads allowed in ready | state 3 |
| S24 | column reads allowed in done | state 2 |
| S25 | column reads allowed in failed | state 2 |
| S26 | column reads allowed in ready only | state 3 |
| S27 | column reads allowed nowhere | state 2 |
| S28 | column-bytevector allowed in row via else (ready too) | state 2 |
| S29 | column-value allowed via else (all states) | state 3 |
| S30 | column-name only in row | state 2 |
| S31 | column-count only in row | state 2 |
| S32 | statement-sql only in row | state 2 |
| S33 | parameter-count only in row | state 2 |
| S34 | the rest not allowed in failed | state 2 |
| S35 | the rest not allowed in done | state 2 |
| S36 | the rest not allowed in row | state 2 |
| S37 | the rest not allowed in ready | state 2 |
| S38 | finalized allowed (equivalent: finalized is answered earlier) | SURVIVED |
| S39 | the rest allowed nowhere | state 2 |
| S40 | the rest allowed in ready only | state 2 |

### Statement-state: the checks, transitions and finish-failure

| Mutation | Guards | Failed |
|---|---|---|
| S41 | finalize-statement! closed in finalized | state 2 |
| S42 | every verb no-op in finalized | state 2 |
| S43 | reset! no-op in finalized | state 2 |
| S44 | finalize allowed in finalized | state 2 |
| S45 | closed refused as a state refusal | state 2 |
| S46 | closed answered unknown | state 2 |
| S47 | allowed misspelt | state 2 |
| S48 | refusal names the verb | state 3 |
| S49 | refusal names nothing | state 3 |
| S50 | refusal tag misspelt | state 3 |
| S51 | unknown verb answers closed | state 2 |
| S52 | an unknown verb not recognised | state 2 |
| S53 | an unknown state not recognised | state 2 |
| S54 | unknown state refused | state 2 |
| S55 | verb symbol? dropped (equivalent: memq of a non-symbol never matches) | SURVIVED |
| S56 | state symbol? dropped (equivalent: memq of a non-symbol never matches) | SURVIVED |
| S57 | finalized dropped from the states | state 6 |
| S58 | states reordered | state 3 |
| S59 | finalized misspelt | state 4 |
| S60 | finalize-statement! dropped from the verbs | state 4 |
| S61 | verbs reordered | state 2 |
| S62 | column-bytevector dropped from the verbs | state 4 |
| S63 | row is code 0 | state 3 |
| S64 | row answers done | state 1 |
| S65 | done is code 0 | state 3 |
| S66 | done answers row | state 1 |
| S67 | done is 102 | state 2 |
| S68 | row is 99 | state 2 |
| S69 | row compared with = (100.0 is row; non-numbers raise) | state 1 |
| S70 | row compared on the low byte (356 is row) | state 4 |
| S71 | done compared on the low byte (357 is done) | state 4 |
| S72 | anything else is done | state 4 |
| S73 | anything else is ready | state 4 |
| S74 | ok is ready | state 2 |
| S75 | extended codes are row | state 3 |
| S76 | a non-integer answer raises (totality) | state 1 |
| S77 | an inexact answer accepted (5.0 is the answer) | state 1 |
| S78 | code 0 raised | state 2 |
| S79 | row code raised | state 2 |
| S80 | done code raised | state 2 |
| S81 | code 1 not raised | state 2 |
| S82 | low byte taken to 7 bits | state 1 |
| S83 | the whole answer tested, not its low byte | state 2 |
| S84 | low byte taken to 9 bits | state 2 |
| S85 | done not raised instead of failed | state 4 |
| S86 | done also not raised | state 2 |
| S87 | row also not raised | state 2 |
| S88 | ready also not raised | state 3 |
| S89 | finalized also not raised | state 2 |
| S90 | only ready raised | state 3 |
| S91 | failed raised again | state 3 |
| S92 | the low byte answered, not the answer | state 3 |
| S93 | the answer wrapped | state 4 |
| S94 | no error ever answered | state 4 |

### Utf8: the leading U+FEFF (B1)

| Mutation | Guards | Failed |
|---|---|---|
| N04 | every leading U+FEFF dropped (the unfixed code) | utf8 5 |
| N05 | one U+FEFF put back, but two leading ones both lost (put back only when exactly one leads) | utf8 1 |
| N06 | the rule tested on the first two bytes only (EF BB xx put a FEFF back) | utf8 2 |
| N07 | the rule tested on a first byte of EF only (every EF-led text gains a FEFF) | utf8 4 |
| N08 | the length guard dropped (a 2-byte input raises) | utf8 1 |
| N09 | a U+FEFF put back at the front of every string | utf8 8 |
| N10 | the FEFF put back after the string, not before | utf8 2 |

### Utf8: utf8-offset->index (m5)

| Mutation | Guards | Failed |
|---|---|---|
| N11 | a continuation byte with no lead answers -1 again | utf8 1 |
| N12 | a continuation byte with no lead answers 0 | utf8 1 |

### Values: raise-bind-refusal WHO (m9)

| Mutation | Guards | Failed |
|---|---|---|
| N13 | the WHO check dropped | values 1 |
| N14 | the WHO check after the rule check | values 1 |
| N15 | the WHO irritant shown raw | values 1 |
| N16 | the WHO check names the wrong field | values 1 |
| N17 | the WHO check raised from WHO | values 1 |

### Values: read-column-bytes ERRMSG (interface)

| Mutation | Guards | Failed |
|---|---|---|
| N18 | ERRMSG called on a non-NOMEM path (zero pointer, any code) | values 3 |
| N19 | ERRMSG called before ERRCODE on a zero pointer | values 5 |
| N20 | ERRMSG called on a non-zero pointer | values 3 |
| N21 | ERRMSG called twice on NOMEM | values 3 |
| N22 | the message dropped from the nomem answer | values 3 |
| N23 | the message and the code swapped | values 3 |
| N24 | ERRMSG called before POINTER | values 8 |
| N25 | ERRMSG called before BYTES on a non-zero pointer (as a stand-in for a wrong order) | values 3 |

### Values: sql-null (m6)

| Mutation | Guards | Failed |
|---|---|---|
| N26 | the record type named null-type again | values 1 |

### Statement-state: state-after-step (m1)

| Mutation | Guards | Failed |
|---|---|---|
| N27 | 256 (low byte 0) answers ready | state 2 |
| N28 | 0 answers done | state 2 |
| N29 | 357 answers done (the low byte 101) | state 3 |
| N30 | 356 answers row (the low byte 100) | state 3 |
| N31 | 0 answers failed no more: 0 answers ready | state 2 |

### Sql-tail: the 3-byte list (m7)

| Mutation | Guards | Failed |
|---|---|---|
| N32 | the EF BB BF rule dropped | tail 7 |
| N33 | the /* rule dropped | tail 12 |
| N34 | the /* rule needs two bytes after it (a /* with one byte after it refused) | tail 5 |
| N35 | the EF BB BF rule only at the end of the input | tail 4 |
| N36 | the -- rule dropped | tail 14 |

## The survivors

No row catches these nine, and none can: each is equivalent to the code, at every value its stated
type allows, or unobservable from a test.

| Mutation | Why it is equivalent or unobservable |
|---|---|
| V09 | In the integer branch `v` is already below 2^63, so the wrapped value `v - 2^64` is never taken. |
| V64 | `sealed` removed. A sealed type cannot be inherited from, and that is observable only through Chez's internals (`#%$record-type-descriptor`, whose answer `record-type-sealed?` reads), which no suite uses: the type is opaque and its name is not exported, so no caller can name it as a parent. `sql-null?` is `eq?` to the one instance, so a subtype's instance would be no `sql-null` anyway. |
| V65 | `(nongenerative <uid>)` added, with a uid no test can guess. A forged instance of the same type is no `sql-null`, since `sql-null?` is `eq?` to the one instance. Generativity is defence in depth: with it, no other definition can even make an instance of the type. |
| R27 | `(<= p 0)` for `(eqv? p 0)` in `read-column-bytes`: POINTER answers a Natural, which is never below 0. |
| T_line12 | The `--` comment's body scan starts at `i+1`, not `i+2`. The byte at `i+1` is the second `-`, which is never the newline that ends the comment, so the scan lands on the same answers. |
| T_blk9 | The `/*` body's end test fires one byte early, at `j+2 >= n`. A `*/` in the last two bytes then closes nothing and the comment runs to the end, which is where closing it would leave the scan: both answer `#f`. |
| S38 | `finalized` added to the states the generic verbs allow. `statement-verb-check` answers every finalized pair first, so the table is never read for it. |
| S55 | `symbol?` dropped from the verb test. `memq` of a non-symbol never finds a symbol, so it answers `unknown` just the same. |
| S56 | The same, for the state test. |

V64 and V65 are the "sealing" and "generativity" the brief asked this log to cover: V64 is
observable only through Chez's internals and V65 not from a test. `sql-null`'s opacity (V63), its
type's name (N26) and its predicate (V59 to V62, V66) can be watched failing.

## The review's fixes

An adversarial review of the slice found the following; each was fixed test first (the row was
written or changed and watched failing against the code as it stood, or against a mutant that
restores the old behaviour), and the whole mutation set above was rerun after.

| Finding | What it was | Rows that catch it now | Mutants |
|---|---|---|---|
| B1 (blocker) | Chez 10.4.0's `utf8->string` strips one leading `EF BB BF`, so `strict-utf8->string` answered `"id"` for U+FEFF followed by `id`, and `""` for U+FEFF alone; of two leading ones the first was lost. The fix puts the character back. | `test-utf8`: the round trips of each boundary value alone (now with U+FEFF and U+FFFE), at the start, middle and end of a string; U+FEFF alone, repeated, first, last and apart; `EF BB BF` alone is one character; every scalar value alone, U+0000 to U+10FFFF, surrogates excluded (about 1.1 million, within the gate: the suite takes 11 s there) | N04 (the unfixed code, and the reviewer's mutant) fails 5 rows; N05 to N10 |
| m9 | `raise-bind-refusal` did not check WHO. It now does, first, as `check-raise-who` does: an assertion violation from `raise-bind-refusal`, irritants `(who V)`, V by `shown-value`. | `test-values`: the WHO row (a string, 5, #f with a bogus rule so the order shows, a list) | N13 to N17 |
| m5 | `utf8-offset->index` answered -1 for a continuation byte with no lead before it (`#vu8(#x80)` at 0). It answers `#f`. | `test-utf8`: the lone `80`, `80 80` and `BF` row | N11, N12; U120 (a survivor before) |
| Interface | `read-column-bytes` also reads the message: a fifth procedure ERRMSG, called only on the NOMEM path, right after ERRCODE, the answer `(nomem CODE MESSAGE)`. | `test-values`: every call-log row now holds ERRMSG's place (`errmsg` after `errcode` on NOMEM, absent on every other path) | N18 to N25; R20 to R22 adapted |
| m4 | `raise-invalid-text`'s message named `column-bytevector` alone, which cannot read a column name. | No row reads message text (ADR-0013, decision 9). | C35 adapted |
| m6 | The record type was `null-type`, printing `#<null-type>`. It is `sql-null-type`. | `test-values`: the "same name" row now defines a type named `sql-null-type`, shows its instances are not `sql-null?`, and shows that `sql-null` prints as `#<sql-null-type>` | N26 |
| m1 | `state-after-step`'s comment now says a code whose low byte is 0, 100 or 101 that is not exactly 100 or 101 gives `failed` too, and why it stays. | `test-statement-state`: 0, 256, 356 and 357 are `failed` | N27 to N31 |
| m7 | SQLite's accepted 3-byte tails. 798 NUL-free inputs come out of prepare empty, 1 of them U+FEFF and 255 `2F 2A x`: identical on Guix's 3.53.1 and on the floor's 3.45.1. | `test-sql-tail`: the list's counts; every listed input is accepted; every 3-byte input over the 14-byte alphabet (2,744) is accepted exactly when listed | N32 (the `EF BB BF` rule dropped) fails 7 rows, of which 2 are the new ones; N33 (the `/*` rule dropped) fails 12, 2 of them new; N34 to N36 |
| m8 | `test-conditions`' header listed M1's types alone, and its "exports exactly" row sat before `test-begin`. | The header lists M2's types, and the row is inside the suite. | None: no behaviour |
| m3 | The argument for V64 said sealing cannot be watched failing from a test. | It can, through Chez's internals (`#%$record-type-descriptor`), which no suite uses; no row uses `#%$`. | V64's argument, above |

## Rules the mutants do not cover

- **`make-sqlite-error`'s argument checks, order and signature** are M1's: C18 drops the offset
  check and is caught by the suite's existing row.
- **`raise-closed`'s message** is slice 3's, and no row reads message text, by ADR-0013 decision 9.
  The refusal messages of `raise-bind-refusal` are not asserted either (the brief says so), so a
  mutant that changes only the advice text survives by design. It was not run.

## Findings

- **A brief's example was wrong.** Section 3's `"select é from"` would put its last token at byte
  10, not 13. The measured SQL is `select 'é', nosuchcol` (`research/m2-plan/probe.sps`), which
  the suite uses: byte 13, character 12, 22 bytes and 21 characters.
- **`make-bytevector 0` is one object in Chez.** `(eq? (make-bytevector 0 0) (make-bytevector 0 0))`
  and `(eq? (bytevector-copy #vu8()) #vu8())` are both `#t` on 10.4.0, so "a fresh empty
  bytevector" cannot be told from a shared one, and no row asserts freshness for the empty case.
  Freshness is asserted for non-empty text and blob plans, where `eq?` tells.
- **Chez 10.4.0's `utf8->string` drops one leading U+FEFF** (`EF BB BF`): `(utf8->string #vu8(#xef #xbb #xbf #x69 #x64))` is `"id"`, and `EF BB BF` alone is `""`. Found by the review, not by this log's first run: a boundary value in the round trips was missing, and the exhaustive set that would have caught it was not built until then.
- **`(rnrs)` has no `bytevector`, `iota`, `quotient`, `list-head` or `set-cdr!`** (that last is
  `(rnrs mutable-pairs)`), and `number->string` prints hex in upper case. The suites define what
  they need.
- **A condition type's `&name` is syntax, not a record-type descriptor.** `record-type-parent` of
  `&sqlite-busy` raises "invalid syntax"; the suite uses `(record-type-descriptor &sqlite-busy)`.

