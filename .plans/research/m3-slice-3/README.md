# What M3 slice 3 measured

Eight probes, run 2026-11-16 in the Guix container on Chez 10.4.0, from the repository's root,
on Guix's libsqlite3 3.53.1 and at the floor, 3.45.1. Their output is in
[output.txt](output.txt): P8 twice on each library, the others once each. Each imports the
library's private libraries, with the suites' library path.

```
$ scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-3/p8-cost.sps'
$ scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-3/lookaside-tails.sps'
$ scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-3/busy-reset.sps'
```

At the floor, each command runs with the floor's library and headers, as a local floor run must
([traps.md](../../traps.md)):

```
$ scripts/guix-env sh -c 'CHEZ_SQLITE3_LIBRARY=$PWD/build/m3-floor/lib/libsqlite3.so.0 C_INCLUDE_PATH=$PWD/build/m3-floor/include $CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-3/p8-cost.sps'
```

## P8. The conveniences' cost through the library ([p8-cost.sps](p8-cost.sps))

The M3 plan's probe P8 (§8; ADR-0020's consequences; Q15). A research probe, never a suite row,
so it runs outside the memory gate. Each figure below is the range of four medians, two runs on
each library; each median is of 7 samples, each a loop of 5,000 calls (part 1) or 100,000 values
(part 2), with a collection before each. The libraries agreed within that range, so they are not
told apart here. No set of `foreign_keys` or `trusted_schema` runs in its loops (ADR-0020,
decision 8).

### Part 1: cached, uncached and at capacity 0

One SELECT of one row by its key, `select v + J from t where k = ?1`, on a `:memory:` table of 100
rows. *Cached* is capacity 32 and one SQL, every call a hit; *uncached* is capacity 32 and 64 SQL
texts in turn, every call a miss prepared `SQLITE_PREPARE_PERSISTENT`, every return evicting one;
*off* is capacity 0, prepared with no flags and finalized each call. The probe checked each answer,
and that the caches ended holding 1, 32 and 0 statements. µs a call:

| | cached | uncached | off |
|---|---|---|---|
| `execute!` | 1.92 to 2.02 | 7.99 to 8.20 | 6.53 to 6.75 |
| `query-row` | 2.03 to 2.12 | 8.19 to 8.37 | 6.61 to 6.88 |
| `query` | 2.26 to 2.40 | 8.47 to 8.61 | 6.97 to 7.28 |
| `query-fold` | 2.65 to 2.71 | 8.84 to 9.06 | 7.34 to 7.54 |

The statement tier by hand, for scale: a fresh statement each call (prepare, `bind-all!`, `step!`,
`column-value`, finalize) 5.62 to 5.77, and one held statement (`reset!`, `bind-all!`, `step!`,
`column-value`) 1.13 to 1.20.

- **A hit saves 4.5 to 5.0 µs a call against capacity 0,** 63 to 71% of the call, each run's
  cached median against its own off median. Through bare FFI, reuse saved 1.9 to 2.3 µs
  (single cost): the library's prepare and finalize add their checks, sections, counters and
  scans, as that lower bound foresaw.
- **A miss at capacity 32 costs 1.3 to 1.7 µs more than capacity 0:** the `PERSISTENT` prepare,
  the eviction's finalize and the table's work. Distinct SQL that never repeats within the
  capacity pays it every call.
- **A convenience costs 0.7 to 1.9 µs over the statement tier by hand,** cached against one held
  statement and off against a fresh one: `execute!` the least, 0.7 to 1.1, and `query-fold` the
  most, 1.5 to 1.9, with its two winds and its handler. The rest is the check-out and the return,
  their sections, and the clearing of the bindings.

### Part 2: a section a value against a section a row

A statement held at its row of N small columns, all `1` or all `'a'`, read whole again and again.
*A section a value* reads as the conveniences do: `column-count/who`, then `column-value/who` for
each column, each in a critical section of its own (Q15's "One value each"). *A section a row* is
the probe's own reader, the row reader Q15 declined: one `call-with-statement-handle`, the count
read once and each column's type and value inside it, TEXT decoded after. The probe checked that
the two read every row alike. ns a value:

| Row | a section a value | a section a row | `query-row`, cached, the whole call |
|---|---|---|---|
| 1 integer | 372 to 391 | 191 to 193 | 1442 to 1488 |
| 10 integers | 199 to 213 | 47 to 49 | 332 to 357 |
| 100 integers | 184 to 196 | 32 to 33 | 221 to 228 |
| 1 TEXT | 423 to 450 | 255 to 262 | 1562 to 1607 |
| 10 TEXT | 279 to 288 | 108 to 110 | 441 to 448 |
| 100 TEXT | 259 to 266 | 93 to 98 | 303 to 312 |

- **A section a value costs 150 to 200 ns a value more than a section a row,** at every width
  and for both kinds. For a row of 100 small integers that is 15 to 16 µs of `query-row`'s 22 to
  23: about three quarters of the call.
- **The section itself is not the cost.** An empty `critical-section` took 8.7 to 9.4 ns a call,
  against 1.2 to 1.3 ns for the loop alone, so about 8 ns of the 150 to 200. The rest, by the
  code and not measured apart, is each value's way through `call-with-statement-handle`: its
  checks of the who, the verb, the procedure and the statement, `call-with-open-handle`'s thread
  and open checks, the state's check, the column count read again, and the outcome built and
  read after.
- Q15 says a section a value's cost is what P8 measures, and that its option C can replace B by an
  amendment if it shows. It shows for wide rows of small values; whether that is enough to change
  B is the maintainer's to decide.

## Part A's probes

Run while part A was built, from the worktree's git-ignored `build/m3s3-probes/`, as
`probe1.sps` and `probe2.sps`, and kept here. `busy-reset.sps` removes its database with
`delete-file`, in `build/`, where the first draft ran `rm -f` through `system`.

### Lookaside by flags, and `prepare_v3`'s tails ([lookaside-tails.sps](lookaside-tails.sps))

Alike on both libraries:

- **Ten held statements of `select 1, 2 where ?1` took 70 lookaside slots prepared with no flags,
  and none prepared `SQLITE_PREPARE_PERSISTENT`;** all were back after their finalize. M3's
  research found the same pattern for 50 (single K1). Part A's lookaside rows assert it through
  the suites' own `sqlite3_db_status`.
- **The tail's byte offset:** empty SQL, no statement, 0; `;`, none, 1; `select 1`, 8;
  `select 1;`, 9; `select 1; select 2`, 9, so the rest begins at the space; ` -- c`, none, 5;
  `;; select 2`, one statement to its end, 11; `select 1 -- c\n; x`, 15, past the semicolon; and
  `select λ; select 2`, a failed prepare, rc 1, its tail at 10. So a NULL statement's tail is the
  input's end, as slice 0's P11 measured, and a prepare that fails still answers a tail.

### A reset's own BUSY ([busy-reset.sps](busy-reset.sps))

An `insert into t values (1), (2) returning x`, stepped once while another connection holds a
read. Alike on both libraries: `sqlite3_reset` answered 5, BUSY; `sqlite3_clear_bindings` then
answered 0; `finalize-statement!` raised nothing; and the table held its one row, so the insert
was rolled back. So `returned` finalizes such a statement and raises the reset's failure, the only
one there is (ADR-0020, decision 5).

## Part B's probes

Run while part B was built, from the worktree's git-ignored `build/b/probes/`, as `p1.sps` to
`p6.sps`, and kept here under the names below, after the fix of the slice's review: run again on
both libraries then, through `prepared-at`'s new check, which `lookaside-by-flags.sps` passes
as `#f`. Each command runs from the repository's root, and at the floor with the floor's
library and headers, as above.

```
$ scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-3/conveniences-answers.sps'
$ scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-3/expiries-unpadded.sps'
$ scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-3/script-offset-and-returning.sps'
$ scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-3/section-ticks.sps'
$ scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-3/lookaside-by-flags.sps'
```

`p6.sps` is not kept: it measured, as the engines suite's row "execute!, query and query-row
bind one value a section …" does, the expiries at fuel 1 of 50 values against 1 in SQL padded
to one length, and that row holds its finding.

### What the conveniences answer ([conveniences-answers.sps](conveniences-answers.sps))

Alike on both libraries, and as `test-conveniences` and `test-execute-script` assert:

- **The shapes:** `execute!` answers no value; `query` its rows, each a vector, in order;
  `query-row` the first row, or `#f`; `query-fold` `(proc acc row)` in order, `(2 1)` for
  `cons` over 1 and 2.
- **Refusals and failures:** a unique violation, `constraint-unique` from `execute!`; a boolean
  value, `execute!`'s assertion violation, `(boolean 2 (kind boolean))`; `query-row` never steps
  to a second row that overflows, where `query` raises the overflow. Five statements are then
  cached, each `ready`.
- **A script's rebuilt errors** carry the whole script, and point at the failing statement's
  first token, character 30 here, for `SELEKT`, a missing table and a step's overflow alike, and
  at character 12 after a two-byte character. Empty SQL, only semicolons and only a comment
  run nothing; incomplete input points at its statement, 30. A closed connection refuses an
  empty script, `&sqlite-closed` from `execute-script!`.

### Expiries in SQL of different lengths ([expiries-unpadded.sps](expiries-unpadded.sps))

At fuel 1, through `query`: 979 expiries for 50 parameters against 75 for 1, and 499 for 50
columns against 64 for 1, alike on both libraries. The one-value SQL is shorter, and
`checked-sql` reads each character outside any section, so a row comparing them measures the
SQL's length as well as the sections: the engines suite pads its one-value SQL to its twin's
length (the slice's log, part B, "Mutants that proved nothing at first").

### A script's offset past its first token, and a returning insert's constraint ([script-offset-and-returning.sps](script-offset-and-returning.sps))

Alike on both libraries: `insert into s values (2); select 1, nosuchcol` raises "no such column",
its offset 36, at the column, the insert before it standing; and `query-row` of `insert into s
values (1), (2) returning x`, with 2 held already, raises `constraint-unique` with no offset, the
insert's every row run at its first step.

### No ticks inside a critical section ([section-ticks.sps](section-ticks.sps))

An engine of fuel 1 expired 1000 times over a 1000-iteration loop, and twice over the same loop
inside one `critical-section`; 1100 times over 100 calls of a ten-iteration loop, and twice
inside a section. So an engine spends no ticks inside a section, and every expiry falls between
sections, as the engine rows and `.plans/traps.md` have it. Pure Chez, so alike on both
libraries.

### Lookaside by a prepare's flags ([lookaside-by-flags.sps](lookaside-by-flags.sps))

Alike on both libraries, the current and high-water `LOOKASIDE_USED` after each: a select of 200
columns run by `execute-script!`, once or twice, `(0 123)`, so its prepare with no flags fills
the connection's 123 slots at its high-water mark; `prepared-at` with no flags, `(0 123)`, and
with `SQLITE_PREPARE_PERSISTENT`, `(0 0)`, never stepped; `query`'s miss at the default capacity,
prepared `PERSISTENT`, stepped and read, `(0 0)`; and at capacity 0, with no flags, `(0 123)`.
`test-execute-script`'s lookaside row asserts it.

## The review's probe: an engine's remainder resumed twice ([engine-twice.sps](engine-twice.sps))

From M3 slice 3's adversarial review, run 2026-11-16 in the Guix container on Chez 10.4.0. It
loads no SQLite.

```
$ scripts/guix-env sh -c '$CHEZ --program .plans/research/m3-slice-3/engine-twice.sps'
```

An engine counting to 2000 expires after 9 counts. Its remainder, resumed, completes at 2000.
**Resumed again, the same remainder runs again from where it expired, to 3991:** Chez's engine
remainders are multi-shot. So a convenience's call can be resumed twice past the same point, which
the review's schedules turned into a statement handed out twice. The guard on every call holds
it (ADR-0016, amended in M3 slice 3; `tests/test-conveniences-resumed.sps`).
