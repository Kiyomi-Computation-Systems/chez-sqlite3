# What M3 slice 1's review measured

Two probes from M3 slice 1's adversarial review, run 2026-11-15 in the Guix container on Chez
10.4.0. Neither loads libsqlite3. Their output is in [output.txt](output.txt).

```
$ scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m3-slice-1/tx-toctou.sps'
$ scripts/guix-env sh -c '$CHEZ --program .plans/research/m3-slice-1/engine-mutex.sps'
```

## An engine's expiry inside `with-mutex` ([engine-mutex.sps](engine-mutex.sps))

An engine with fuel 20 runs `(with-mutex m …)` around a long loop, and expires inside it. While
it is suspended, another thread takes and releases `m`: `mutex free from another thread: #t`. The
expiry ran `with-mutex`'s after thunk, and the resume runs its before thunk again. So `with-mutex`
alone doesn't keep a check and the act it guards together; the interrupt latch holds both inside
one `critical-section` too ([traps.md](../../traps.md)).

## `with-transaction`'s exits under an engine ([tx-toctou.sps](tx-toctou.sps))

A model of `with-transaction` as ADR-0017 decision 7 and the M3 plan's §4.2 shape it, driven by
slice 1's `(chez-sqlite3 private transaction-plan)` over a stand-in connection. Each statement
does some plain work, as `execute!`'s check-out and checks will, then steps in a critical section
of its own, which sets `begun` or `ended` when asked. An engine runs the call at each fuel, and at
its first expiry is resumed to the end.

- **At fuels 138 to 174, outer and nested alike, an expiry fell between the autocommit read and
  the `COMMIT`'s or `RELEASE`'s step.** The after thunk rolled the level back and set `ended`;
  the resumed body then stepped the `COMMIT` or `RELEASE` it had planned, and raised SQLite's
  error, "cannot commit - no transaction is active" or "no such savepoint", in place of
  `&sqlite-transaction-ended`.
- **With another engine's savepoint at the same depth opened meanwhile,** at fuel 140, the resumed
  `RELEASE` released that savepoint, and the call answered its body's value, 42, though its own
  insert had been rolled back.
- **At the review's commit, `7e5f40c`,** `failed-commit-plan` took no `ended`, so at a nested
  level the failed `RELEASE` was planned as a failed commit, and `ROLLBACK TO` and `RELEASE` ran
  again on the level already ended. The probe here passes `ended`, as the fixed plan takes it, and
  that second rollback is gone. The rest is the model's shape, which slice 4 changes: each step
  that ends the level reads `ended` in its own section (ADR-0017, amended in M3 slice 1).
- Fuels 1 to 40 expired before `begun` was set, and the resume began and committed. 60 to 120
  rolled back and raised `&sqlite-transaction-ended`. 200 completed unexpired. So a sweep of 1 to
  60 never reached the window, and slice 4's sweeps fuel until the call completes unexpired.

This is a model of slice 4, not slice 4's code: its fuel numbers are the model's.
