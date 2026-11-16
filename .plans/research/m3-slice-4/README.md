# What M3 slice 4 measured

Measured 2026-11-16 in the Guix container on Chez 10.4.0, on Guix's libsqlite3 3.53.1 and at the
floor, 3.45.1, alike: every fuel below is the same on both. Engine fuel is spent by Scheme
between critical sections, where no SQLite call runs, so no figure here depends on the library.
The figures are the suites' own printed lines, from `tests/test-transaction-engine.sps`, and the
runs of two plants against it, each in a copy of the tree. Their output is in
[output.txt](output.txt).

```
$ scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program tests/test-transaction-engine.sps'
```

At the floor, with the floor's library and headers:

```
$ scripts/guix-env sh -c 'CHEZ_SQLITE3_LIBRARY=$PWD/build/m3-floor/lib/libsqlite3.so.0 C_INCLUDE_PATH=$PWD/build/m3-floor/include $CHEZ --libdirs src:tests:build/scheme-libs --program tests/test-transaction-engine.sps'
```

## The engine sweep (ADR-0017, amended in M3 slice 1)

An engine around `with-transaction`, deferred, whose body inserts a row and answers 42, run at
every fuel from 1, resumed with that fuel after each expiry, until a fuel completes without
expiring. Nested, the engine runs inside an outer `with-transaction` its caller opened.

| Fuels, outer and nested alike | Outcome |
|---|---|
| 1 to 101 | `&sqlite-transaction-ended`, the row **present**: an expiry after the begin rolled back, and the body's insert, after it, autocommitted (single L1's shape) |
| 102 to 114 | `&sqlite-transaction-ended`, the row absent: an expiry after the insert rolled it back |
| 115 to 117 | committed: the call expired only once its level had committed |
| 118 | completes without expiring |

At every fuel the level began once, and either committed once or was rolled back once: BEGIN
and COMMIT ran once each, or BEGIN and ROLLBACK, read by `sqlite3_stmt_status`'s run count; and
the extended code was 0.

**The window,** the fuels whose expiry fell between the autocommit read after the body and the
`COMMIT`'s or `RELEASE`'s step, is the one a plant that reads `ended` only in the earlier read
fails: **fuels 110 to 114, at the outer level and nested, on both libraries.** There the plant
stepped `COMMIT` after the after thunk's rollback, "cannot commit - no transaction is active"
(1), or `RELEASE` on a released savepoint, in place of `&sqlite-transaction-ended`. The
model's window was 138 to 174 ([research/m3-slice-1/](../m3-slice-1/README.md)); the real
code's is earlier, and narrower.

**Before begun:** fuels 1 to 28 expire before the begin's step answers, at both levels. Each,
resumed with fuel to spare, begins once and commits, with no rollback.

## A remainder resumed a second time (ADR-0017, amended in M3 slice 3)

The amendment left open whether `ended` is passed as `checked-out`'s check, "so a second resume
of its remainder touches none of its statements". The row: with the cache warm, a
`with-transaction` whose body answers 42, at every fuel until it completes unexpired (42). Where
the first slice began the level, every expiry from there on falls with `ended` set: the first
one's after thunk rolled back, or the commit had set it. The call is resumed one tick a slice to
its end, and every remainder it made is resumed again, one tick a slice, with the cache's count
read between every slice and each statement's state and runs, and the extended code, at the end.

| Design | Fuels whose first slice began the level | Remainders resumed twice | That checked out a statement |
|---|---|---|---|
| `ended` passed as the check (taken) | 13 at each level | 373 at each level | **0** |
| the use's own flag alone | 13 at each level | 381 at each level | **6 at each level** |

The fuels, and the zero, held in every run. The count of remainders did not: four runs of the
suite on Guix's library gave 373 nested remainders three times and 405 once, the outer level 373
each time; the floor's run gave 373. Where the extra expiries come from was not measured: a
collection between two slices is one guess. The plant's 381 is one run's.

In the second design the six remainders' second resumes each checked out `COMMIT`, or the
nested `RELEASE`, which the cache's count showed one lower for two slices, then gave it back
unstepped. They had been captured between the autocommit read and the `COMMIT`'s check-out, and
the expiry's rollback had set `ended`. The second answers, in both designs: 42 (captured after
the commit's return), `&sqlite-transaction-ended`, or `call-with-open-handle`'s `re-entered`
(captured inside its wind). A remainder captured before the call bound its flags makes a whole
new call when resumed (`traps.md`), so the row takes no fuel whose first slice did not begin the
level.

## `number->string` resumed twice (the lead's addition)

A remainder resumed a second time from inside `number->string` answers `""` on Chez 10.4.0 (the
lead's probe). `test-transaction-engine`'s no-cut-SQL row runs every fuel's first remainder to its
end and then again, at both levels, and reads the connection's tracked SQL and extended code
after each: no SQL but with-transaction's own, its savepoints named in full, and the code 0, at
fuels 1 to 41 on both libraries. The shell's plans, which build the names, run inside
`call-with-open-handle`'s sections. A plant that builds the names outside them fails it: at
fuel 35 the second resume handed SQLite `SAVEPOINT chez_sqlite3_`, and SQLite took it as a
savepoint of that name, so the error alone would never have shown it.

## After the review's fix

The fix added rows to `test-transaction-engine`, and every sweep's fuels moved by two, on both
libraries alike. The library's path through the sweeps did not change: the review's copy of the
suite, run over the final code, still reads the figures above. So a fuel belongs to the suite's
text as well as the code. The suite then read as follows; this table is superseded by the one
under "After one section per statement", which holds the final figures:

| Row | Fuels, outer and nested alike, both libraries |
|---|---|
| the sweeps | ended after a later write 1 to 99; rolled back 100 to 112; committed 113 to 115; completes at 116 |
| slice 1's window, its plant | 108 to 112 |
| before begun | 1 to 26 |
| the second resume | fuels 1 to 40, 13 that began the level, 383 remainders, none touching a statement |
| no cut SQL | fuels 1 to 39 |
| O7 nested under an engine (new) | ended 1 to 187, lost 188 to 202, busy 203 to 252; completes at 253 |
| the siblings (new) | A's first slice expires at 1 to 114, completes at 115 |

## After one section per statement

The maintainer chose, on 2026-11-16, that `with-transaction` take, step and give back each of
its own statements in one critical section ("One section per statement"). Under three sections,
an engine lost between a failed `RELEASE`'s step and its return left that statement tracked,
`failed`, and every later `with-transaction` on the connection was refused. With fewer sections,
each sweep needs fewer fuels. Read at the slice's final text, identical on 3.53.1 and 3.45.1
(slice 1's window from its plant, run at the floor):

| Row | Fuels, outer and nested alike |
|---|---|
| the sweeps | ended after a later write 1 to 97; rolled back 98 to 109; committed 110 to 111; completes at 112 |
| slice 1's window, its plant | 106 to 109 |
| the second resume | fuels 1 to 36, 10 that began the level, 303 and 306 remainders, none touching a statement |
| no cut SQL | fuels 1 to 35 |
| O7 nested under an engine | ended 1 to 185, lost 186 to 198, busy 199 to 248; completes at 249 |
| O7 nested, nothing left behind (new) | the same fuels; every fuel leaves nothing behind |
| the siblings | A's first slice expires at 1 to 110, completes at 111 |

The O7 row and its two designs are in [the mutation log](../../m3-slice-4-mutation-log.md),
under M9.

## After the second review

Rows added to `test-transaction-engine` and a watchdog that retries moved no sweep's fuels: the
fuels of the table above read the same at the final text, on 3.53.1 and 3.45.1 (the siblings
1 to 110, completing at 111; the O7 rows ended 1 to 185, lost 186 to 198, busy 199 to 248,
completing at 249). The new rows' own figures, the same on both libraries:

| Row | Figures |
|---|---|
| the second resume, second answers | 42, the `re-entered` refusal, `&sqlite-transaction-ended`; never an `&sqlite-error` |
| the timer re-entry | the handler fires at 59 of 63 ticks on the final code; no tick runs `ROLLBACK TO chez_sqlite3_1` twice. Against design A and the code before the fix, ticks 28 to 30 do, at 80 of 84 |
| a failed nested begin | 600 cases of a begin failed by a sticky interrupt, `T1` 13 to 24 and about 50 values of `T2` each; none leaves a `ROLLBACK TO`, and the extended code is 0 or 9 |
| a remainder resumed while an earlier resume is pending | G steps by 4: 2,091 or 2,092 trials at each level (it varies by one between runs), at fuels 1 to 108; the call completes unexpired at fuel 109. The full sweep, G by 1, made 8,210 at each level and cost the engine suite 100 s under the gate, 46 s with the stride |
