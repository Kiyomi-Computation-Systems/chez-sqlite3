# ADR-0017: `with-transaction` reads autocommit to nest, and again to learn whether its transaction survived

- **Status:** Accepted (the maintainer, 2026-11-15), proposed in M3 slice 0. The maintainer's own choices, the same day
  ([the M3 plan](../2026-11-15-m3-plan.md), §3): decision 2's mode, "Mode arg, immediate" (Q5);
  decision 6's failed `COMMIT`, "Roll back, raise" (Q6), and its ended transaction, "Raise a new
  condition" (Q7). The consequences' sticky interrupt and refused `BEGIN` are measured by slice
  0's research (P7, P9, P12). Revised the same day after the plan's adversarial review: decisions
  5 to 7 for the re-entry pattern and the rollback's failures, and decision 1's refusal beside a
  held row, the maintainer's answer to the plan's Q14. Revised again after the plan's second
  review: decision 7's exits decided by flags of M3's own, with the begin inside the wind, and
  decision 1's refusal naming the states `row` and `failed`. Amended 2026-11-15 in M3 slice 1, and
  accepted by the maintainer that day: the flags read inside the section of the step they guard, the
  savepoints' N, and the engine row's bound
  ([amendment](#amendment-2026-11-15-the-flags-read-where-the-step-is-taken-m3-slice-1)).
  Amended 2026-11-16 in M3 slice 3, and accepted by the maintainer that day: a failed commit's
  rollback tried once, and N following the calls' extents, the maintainer's choices that day
  ("Once", "Reuse N"); the context's `failed` and NOMEM bullets narrowed
  ([amendment](#amendment-2026-11-16-a-failed-commits-rollback-and-the-savepoints-n-m3-slice-3)).
  Amended 2026-11-16 in M3 slice 4, and accepted by the maintainer that day ("Accept all"): `with-transaction`
  as built, `ended` as the check-out's check, one section a statement, the builder's choices the
  maintainer confirmed that day ("Confirm, and name the SQL"; "Document it"; "One section per
  statement"), and four consequences found by the slice's review
  ([amendment](#amendment-2026-11-16-with-transaction-as-built-m3-slice-4)). Amended 2026-11-16
  in M3 slice 6, proposed: a deferred transaction's first write, and the default under contention
  ([amendment](#amendment-2026-11-16-a-deferred-transactions-first-write-m3-slice-6)).
- **Date:** 2026-11-15
- **Scope:** chez-sqlite3 v1: `with-transaction`
- **Settles:** brief §4's "`with-transaction` with nested savepoints, and rollback on a raise"
- **Related:** [ADR-0012](0012-explicit-close-and-the-handle.md) (`call-with-database`'s shape) ·
  [ADR-0013](0013-errors-are-condition-types.md) (`&sqlite-transaction-ended`) ·
  [ADR-0014](0014-statements-belong-to-their-connection.md) (a column read's NOMEM, amended) ·
  [ADR-0016](0016-the-conveniences-and-the-counters.md) (the conveniences) ·
  [ADR-0019](0019-interrupt-and-close.md) (an interrupted write) ·
  [research/m3-plan/](../research/m3-plan/README.md) · [the M3 plan](../2026-11-15-m3-plan.md), §4.2

## Context

Measured on Guix's 3.53.1 and at the floor, 3.45.1, alike (M3's research, "single" and
"concurrency" its halves):

- **The statements** (single B1, "State at each step"):
  - a deferred `BEGIN` sets autocommit to 0 before anything is read; `SAVEPOINT` outside a
    transaction begins a deferred one, and takes no mode (S1);
  - inside `BEGIN`, `RELEASE` of the outermost savepoint commits nothing (S5);
  - `ROLLBACK TO` leaves its savepoint open, and the transaction too, so a level is rolled back by
    `ROLLBACK TO` then `RELEASE` (S2 to S4);
  - savepoint names fold ASCII case only, accept string literals and keywords, and a reused name
    reaches the most recent (S8, S9);
  - a refused `BEGIN IMMEDIATE` still takes its lock (txn X1, T1).
- **Whether a failure ended the transaction can't be told from its code or its SQL** (single B1,
  "Which errors end the transaction" and "NOMEM, FULL and INTERRUPT"):
  - constraint and runtime errors undo only their statement (E1 to E3, E9, E12, E14), but
    `OR ROLLBACK` and `RAISE(ROLLBACK)` end the transaction (E4, E5, E7, E8);
  - the same NOMEM or FULL undid only its statement, or ended the transaction, by one function
    call, one constraint, one row, or whether a table was read (F1 to F8, N1 to N4, M1 to M5, T8);
  - an interrupted write ends the transaction and its savepoints, and an interrupted SELECT
    doesn't (concurrency I5, trap 3; single txn-special I1 to I4);
  - a column read's NOMEM ends it at the reset or finalize after it (single G2, G3), which M2
    raises nothing for (ADR-0014's slice 3 amendment, the maintainer's).

  After the transaction has ended, `ROLLBACK` answers "no transaction is active" and `RELEASE` or
  `ROLLBACK TO` "no such savepoint" (single E5). **The one test is `sqlite3_get_autocommit`, read
  after the failure.**
- **A body that catches such an error and carries on** autocommits each later write, which
  another connection sees at once; the closing `COMMIT` answers "cannot commit - no transaction is
  active" (single L1).
- **A `COMMIT` can fail and leave the transaction open:** a deferred foreign key, 787 (single
  E13); BUSY under the connection's own unfinished write (single O7; concurrency B11); BUSY under
  another's read in rollback-journal mode, after the busy timeout has waited, while no other
  connection can start reading (concurrency B7).
- **Contention:** the busy timeout covers `BEGIN IMMEDIATE`, but a deferred transaction's first
  write after a read answers BUSY at once, and in WAL 517 once the other has committed
  (concurrency B2, B5, B6, trap 4).
- **`ROLLBACK` succeeds with a statement mid-row,** which goes on answering rows (single O2, O7b,
  T2), or 516 after a rolled-back schema change (O4b). DDL rolls back (D1, D2).
- **An interrupt sticks** while any statement of the connection holds a row: every new prepare
  answers 9 (concurrency I3, I4b). `ROLLBACK`, `COMMIT`, `ROLLBACK TO` and `RELEASE` each answered
  9 at prepare then, and a `ROLLBACK` prepared before the interrupt answered 9 at its step; the
  transaction stayed open until the held statement was reset (M3 slice 0's research, P7).
- **A connection's own held read defeats the busy timeout for its `BEGIN`.** With its SELECT
  held at a row, under another's `BEGIN IMMEDIATE` and write, its `BEGIN IMMEDIATE` and an
  autocommit INSERT answered BUSY at once, where without the held read they waited out a 1500 ms
  timeout, in WAL and rollback-journal mode alike. With `BEGIN IMMEDIATE` taken first and the
  SELECT held after it, an INSERT and a savepoint ran at once (slice 0's research, P12). In WAL,
  with the held SELECT and another connection's commit after it, `BEGIN IMMEDIATE` and
  `BEGIN EXCLUSIVE` answered 517 at once with a 300 ms timeout, beginning nothing, and a deferred
  `BEGIN`'s first write answered 517 (P9). Autocommit is 1 in that state (single B1, item 2).
- **`query-fold` holds such a read while its procedure runs** ([ADR-0016](0016-the-conveniences-and-the-counters.md),
  decision 6).
- **M2's `failed` state covers statements SQLite still holds active.** Measured on both libraries
  by the M3 plan's second review. After a column read's NOMEM, which slice 4's `read-outcome` turns
  into `failed`, and after a step that answered BUSY, `sqlite3_stmt_busy` read 1, and after an
  interrupt a prepare answered 9. Beside the NOMEM one, a `BEGIN IMMEDIATE` answered 5 at once
  against a 600 ms timeout. The controls, a step failing on a constraint and a statement at
  done, read 0, the `BEGIN` waited, and the prepare answered 0.
- **A guard whose clauses don't match re-enters the raise's extent to raise again,** so a
  before thunk that refuses a re-entry replaces the caller's condition. M2's
  `call-with-database` and `call-with-statement` let the re-entry through, and keep their after
  thunks contained (`connection.sls:465–470`, `statement.sls:436`); measured on Chez 10.4.0 by the
  plan's review.

## Decision

1. **The surface:**

   ```scheme
   ;; with-transaction : (case-> (Database (-> A ...) -> A ...) (Database Mode (-> A ...) -> A ...))
   ;; Mode = (U 'deferred 'immediate 'exclusive)
   (with-transaction db (lambda () (execute! db "insert into t values (?)" 1)))
   (with-transaction db 'deferred (lambda () (query db "select * from t")))
   ```

   The thunk is last, as `call-with-database`'s procedure is (ADR-0012, decision 8). It is checked,
   and the mode, before anything reaches C: a thunk that is no procedure, or a mode that is no
   mode, is an assertion violation. Then the database, its owner and that it is open, as every
   verb checks. The signature is one line, as `test-reference` reads it.
   - **It refuses to begin while any statement of its connection is `row` or `failed`** (the
     plan's Q14): a fold's, or a statement's of the caller's. The states are M2's, read through
     `tracked-statements` and `statement-state`, a pass in Scheme that reaches no C, made first in
     the section that then reads autocommit, inside `call-with-open-handle`'s, on the owner's
     thread; so it is race-free, and nested levels are refused with the rest. The refusal is an
     assertion violation, raised after that section, before anything reaches C. Beside a held read
     its `BEGIN` can't wait under the busy timeout, and once an interrupt sticks behind the row its
     rollback can't be prepared, so decision 6's promise couldn't hold. `failed` is among them
     because M2's `failed` covers statements SQLite still holds active (the context).
2. **Outer or nested is read from `sqlite3_get_autocommit`.** At 1, it issues `BEGIN` with its
   mode, `immediate` when none is given (Q5). At 0, it issues a savepoint, and the mode
   has no effect, since `SAVEPOINT` takes none. A transaction the caller began with `execute!`
   nests the same way, and stays the caller's. No `BEGIN` is ever issued inside a transaction, so a
   refused one never takes its lock.
3. **Its savepoints are its own,** named `chez_sqlite3_N`, N their depth on the connection, kept in
   the connection's record. The name is an ASCII identifier that needs no quoting, and the caller
   never gives one.
4. **The statements it issues,** each through the conveniences' path and the cache
   ([ADR-0020](0020-the-statement-cache.md)), or prepared afresh at a `statement-cache` of 0:

   | Level | Begin | Commit | Roll back |
   |---|---|---|---|
   | outer | `BEGIN DEFERRED`, `BEGIN IMMEDIATE` or `BEGIN EXCLUSIVE` | `COMMIT` | `ROLLBACK` |
   | nested | `SAVEPOINT chez_sqlite3_N` | `RELEASE chez_sqlite3_N` | `ROLLBACK TO chez_sqlite3_N`, then `RELEASE chez_sqlite3_N` |

5. **When the body raises, or leaves through a continuation, the first time,** it reads
   autocommit. The
   conveniences have finished their statements by then (ADR-0016, decision 5), so a column read's
   NOMEM has already ended the transaction if it was going to. If the transaction is still there,
   it rolls its own level back; if not, it issues nothing. Then the body's condition reaches the
   caller unchanged. A failure of the rollback isn't raised over it, as `call-with-database`'s
   close isn't. **On an escape that isn't a raise** there is no condition to keep, so the
   rollback's failure is raised from the plain after thunk, as `call-with-statement` raises its
   finalize's. Under an engine's expiry that loses the engine, as ADR-0012's amendment measured for
   `call-with-database`'s close.
6. **When the body returns, the first time,** it reads autocommit again. If the transaction has
   ended, it raises
   `&sqlite-transaction-ended` and issues nothing (Q7). Otherwise it issues `COMMIT` or
   `RELEASE`, and answers the body's values. **A `COMMIT` that fails and leaves the transaction
   open is rolled back, and then its failure is raised** (Q6): the transaction never
   outlives `with-transaction`. A `COMMIT` that fails with the transaction already ended raises its
   failure alone. **A `RELEASE` that fails with its savepoint still open is a failed `COMMIT`
   too:** the level is rolled back, `ROLLBACK TO` then `RELEASE`, then the first `RELEASE`'s
   failure is raised. A sticky interrupt makes one, and then the rollback fails the same way, so
   the savepoint and its transaction stay open, which `in-transaction?` tells (slice 0's P7).
7. **The exits are decided by flags, never by autocommit alone.** The shape is M2's
   `call-with-database` (`connection.sls:478–520`) where M2's holds:
   - a plain `dynamic-wind` around a critical one. The plain winder's before thunk does nothing, so
     a re-entry goes through (the context). The critical winder's after thunk does the rollback,
     with interrupts disabled, under a guard that records any failure and raises nothing; the plain
     winder's after thunk raises that failure, unless a raise is under way;
   - a handler records a raise and hands it on in place, with `raise-continuable`, as M2's does;
     here it covers the wind's whole body, the begin and the commit as well as the body, so their
     own failures count as raises too;
   - **the begin sits inside the wind's body, after decision 1's refusal,** as M2 puts its open
     inside the winder (`connection.sls:470–473`), so an escaping interrupt after the `BEGIN`
     still reaches the after thunk.

   **And two flags of M3's own, where M2's shape doesn't hold.** M2's close is idempotent through
   its resource, a closed connection; a rollback isn't. A second `ROLLBACK TO chez_sqlite3_N` on
   a level already ended answers "no such savepoint", or, with the outer transaction still open,
   rolls back a newer savepoint at the same depth. So:
   - `begun` is set inside the section of the step that answered the `BEGIN` or `SAVEPOINT`, as
     `call-with-statement`'s prepare hands its statement over inside its own section
     (`statement.sls:437–438`), so no interrupt falls between them. `ended` is set inside the
     section of the step that commits, releases, or completes the rollback;
   - **the commit runs in the wind's body, after the body returns,** by decision 6, when `ended`
     is unset. Its raises, a failed commit's and `&sqlite-transaction-ended`, are made there, in
     the body, never inside a critical section;
   - **the critical after thunk acts only when `begun` is set and `ended` isn't,** by decision 5,
     and sets `ended`;
   - **a later exit issues nothing.** A body that returns after its level ended raises
     `&sqlite-transaction-ended` from the wind's body, decision 6's rule applied to its own earlier
     exit, never a second `COMMIT` or `RELEASE`. A later raise or escape does nothing more. The
     cases:
     - a body resumed by an outer handler that returned to a `raise-continuable` past a guard that
       re-entered: its first exit rolled back, its later statements autocommit, as single L1
       measured, and its return raises;
     - a continuation captured in the body and called after the commit: the body returns again, and
       raises;
     - an engine that expires inside the extent and is resumed: an expiry before `begun` is set
       does nothing, and the resume begins and commits as usual; one after it rolls back, and the
       resumed body's return raises. So at every fuel the call either commits once or raises, and
       never commits silently what an expiry rolled back. M3 slice 4 sweeps fuel 1 to 60.

     The M3 plan's second review modelled the shape without these rules: each such return
     answered the body's values silently, `(body-returned-after-resume 42)`, `(body-returned time
     2)`, and a return after 400 expiries;
   - so it doesn't survive an engine's preemption: an expiry after the begin rolls back.
8. **Everything raised names `with-transaction`,** and is raised after every critical section
   (ADR-0012, amended).

### Rejected

- **Counting depth in Scheme alone, to choose `BEGIN` or a savepoint.** A transaction the caller
  began with SQL would then get a `BEGIN` inside it, which is refused, and a refused
  `BEGIN IMMEDIATE` takes its lock.
- **Rolling back without reading autocommit first.** After `OR ROLLBACK`, an interrupted write or
  a FULL in a statement with no statement journal, the rollback answers "no transaction is active",
  and a rule that raised it would hide the body's condition.
- **Telling an ended transaction from the error's code.** The same code ended it or didn't.
- **Names the caller gives.** Quoting, ASCII-only folding and a reused name's reach would all
  become the caller's concern.
- **Committing on an escape.** Work the body left half done would be committed.
- **A before thunk that refuses a re-entry,** as a draft of this record had: under a guard whose
  clauses don't match, the caller would get `re-entered` in place of its own condition.
- **Leaving a failed `COMMIT`'s transaction open, or retrying it,** declined in Q6: the busy
  timeout has already waited.
- **Defaulting to `deferred`, or taking no mode,** declined in Q5.
- **Issuing the `COMMIT` after the transaction ended and raising SQLite's `error`, or returning
  normally,** declined in Q7.

## Consequences

- **`with-transaction` doesn't survive an engine's preemption;** a program under engines issues
  `BEGIN` and `COMMIT` itself. M3 slice 4 measures it.
- **A sticky interrupt makes the rollback fail.** While a statement on the connection holds a row
  after an interrupt, the rollback answers 9 (slice 0's P7). The body's condition is raised and
  the transaction stays open; `in-transaction?` tells. A `COMMIT` failing so is rolled back by
  decision 6, whose rollback fails the same way, and the commit's failure is raised with the
  transaction open. Both a statement of the caller's and `query-fold`'s own, while its procedure
  runs, hold such a row. Decision 1's refusal keeps `with-transaction` from beginning beside
  either, so only a row taken inside the body, by the statement tier, still
  reaches this. `docs/reference.md` says to reset such a statement first.
- **Beside a held read, `with-transaction`'s `BEGIN` would answer BUSY at once,** or 517 in WAL
  after another's commit, where Q5's default otherwise waits (slice 0's P9, P12). Decision 1's
  refusal stops it first. `docs/reference.md` says to run a fold that writes
  inside `with-transaction`, which takes the lock before the fold's read.
- **A deferred transaction's write under contention fails at once:** with no timeout, and with
  1500 and 2000 ms timeouts, where measured (concurrency B2, B5, trap 4). `docs/reference.md`
  says so beside the mode.
- **A nested call's mode has no effect,** and `docs/reference.md` says so.
- **A statement left at a row makes every later `with-transaction` on its connection refuse.** A
  timer's or a keyboard handler's escape, or an abandoned engine, can leave a convenience's
  statement checked out at its row until the close ([ADR-0016](0016-the-conveniences-and-the-counters.md),
  decision 6). The caller can't reset it, since `tracked-statements` is private, so the remedy is
  to close the connection, and `docs/reference.md` says so beside the refusal.
- **Writes the body made after its transaction ended stand,** autocommitted; nothing at the end
  can take them back. `&sqlite-transaction-ended` tells the caller they weren't atomic.

## Amendment, 2026-11-15: the flags read where the step is taken (M3 slice 1)

Accepted by the maintainer on 2026-11-15 ("Accept all"), proposed in M3 slice 1, from its
adversarial review, which modelled decision 7's shape over slice 1's transaction plan and a stand-in
connection ([research/m3-slice-1/](../research/m3-slice-1/README.md), `tx-toctou.sps`).

- **The hole.** Decision 6 reads autocommit after the body in one section, and decision 7 sets
  `ended` inside the section of the step that commits: two sections, with the commit's check-out
  and bind between them. An engine's expiry between the read and the `COMMIT`'s or `RELEASE`'s
  step runs the critical after thunk, which finds `begun` set and `ended` not, rolls the level
  back and sets `ended`. The resumed body then stepped the `COMMIT` or `RELEASE` it had planned:
  - at the outer level, SQLite's "cannot commit - no transaction is active" was raised, in place
    of `&sqlite-transaction-ended`;
  - at a nested level, the `RELEASE` failed, "no such savepoint", and decision 6 took it for a
    failed commit, so `ROLLBACK TO` and `RELEASE` ran again on a level already ended;
  - with another engine's savepoint at the same depth opened meanwhile, the resumed `RELEASE`
    released that one, and the call answered its body's value, 42, though its own insert had been
    rolled back.

  In the model the window opened at fuel 138 and closed at 174, past decision 7's sweep of 1 to 60.
- **So every step that ends the level reads `ended` inside its own section, before it steps:** the
  `COMMIT` or `RELEASE`, and each step of a failed commit's rollback. With `ended` set it steps
  nothing and answers so, as data, and the wind's body raises `&sqlite-transaction-ended`, decision
  7's rule for a later return. The check sits in the step's section because that is the one that
  acts: the check-out and the bind before it are sections of their own.
- **A failed commit's rollback is planned only while `ended` is unset:** slice 1's
  `failed-commit-plan` takes the flag.
- **The begin's read and its step are two sections too.** With one engine at a time on the
  connection nothing runs between them, and decision 2's "no `BEGIN` is ever issued inside a
  transaction" holds. Two engines sharing a connection can both read autocommit 1; the second's
  `BEGIN` then answers "cannot start a transaction within a transaction", raised with `begun`
  unset, so nothing is rolled back. Decision 2's promise is for one engine at a time.
- **Decision 3's N is the number of `with-transaction` levels open outside the savepoint on the
  connection, from 0.** So the first savepoint inside a caller's own `BEGIN` is `chez_sqlite3_0`.
- **M3 slice 4's engine row sweeps fuel from 1 until a fuel at which the call completes without
  expiring,** not to 60, at the outer level and nested, and asserts at every fuel that the call
  commits once or raises `&sqlite-transaction-ended`, and never steps a `COMMIT`, `RELEASE` or
  rollback after `ended` is set. A mutant that checks `ended` outside the step's section fails it.

## Amendment, 2026-11-16: a failed commit's rollback, and the savepoints' N (M3 slice 3)

Accepted by the maintainer on 2026-11-16 ("Accept all"), proposed in M3 slice 3, from M3 slice 4's
groundwork in M2's session, which ran its probes on 3.53.1 and 3.45.1. M3's session checked the
outputs this amendment cites. The second and third bullets are the maintainer's choices, 2026-11-16
("Once", "Reuse N"). The probes, `levels.c` and `failed-active.c`, land with M3 slice 4's research.

- **A second way a failed commit's rollback fails.** At a nested level, with the connection's own
  `INSERT … RETURNING` held at a row:
  - `RELEASE chez_sqlite3_1` answered 5, "cannot release savepoint - SQL statements in progress";
  - by decision 6, `ROLLBACK TO chez_sqlite3_1` answered 101;
  - the rollback's own `RELEASE` answered 5 again, so the savepoint stayed open, rolled back to
    its start;
  - the caller's outer `COMMIT` then answered 5 too, and only its `ROLLBACK` ended the
    transaction.

  Decision 6 named only the sticky interrupt.
- **A failed commit's rollback is tried once ("Once").** `ended` is set in the section of the
  rollback's last step, the `ROLLBACK`, or the `RELEASE` after `ROLLBACK TO`, whatever that step
  answered. So the critical after thunk issues nothing more, and the commit's failure is raised.
  - By slice 1's amendment `ended` was set only when the rollback completed. The after thunk
    would then have rolled back a second time, and failed the same way: here, and after slice 0's
    P7, the sticky interrupt.
  - A retry can't succeed: the row that refused the first attempt is still held.
  - What stays open, `in-transaction?` tells at the outer level. At a nested level the level's
    writes are undone once its `ROLLBACK TO` has succeeded.
- **Decision 3's N follows `with-transaction`'s own extents ("Reuse N").** It drops when the call
  exits, whatever SQLite kept. A sibling at the same depth issues `SAVEPOINT chez_sqlite3_N`
  above a savepoint left open so. SQLite's `ROLLBACK TO` and `RELEASE` reach the most recent
  savepoint of a name (S9), so the sibling acts only on its own. The one left open ends with its
  transaction.
- **The context's `failed` bullet is narrowed: "after an interrupt a prepare answered 9" held only
  while another statement held a row** (concurrency I4b).
  - An interrupted statement alone, after a first step or a later one, read `sqlite3_stmt_busy` 0,
    and the next prepare answered 0 (`failed-active.c`, F3 to F5).
  - With another statement still at a row, the prepare answered 9 (F6).
  - The step that answered BUSY read `stmt_busy` 1, but held no read: a `BEGIN IMMEDIATE` beside
    it waited out its 1500 ms timeout (F2).
  - Only the statement a column read's NOMEM failed answered 5 at once (F1).

  Decision 1's refusal of `failed` stands. The statement a column read's NOMEM failed still held a
  read (F1), and a failed statement wants `reset!` anyway (the M3 plan's §4.2).
- **"A column read's NOMEM ends it at the reset or finalize after it" holds for a statement that
  reads a table** (single txn-special G2, G3). One reading no table, as `select ?1`, kept the
  transaction open through the reset and the finalize alike (G4, G5).
- **M3's records' "single T1", "T6", "T7" and "T12" are `traps.c`'s sections,** "single traps T1"
  as the context's "(txn X1, T1)" means it. `txn.c` numbers sections T1 to T7 of its own, so its
  T1 to T7 collide: ADR-0016's and `traps.md`'s "T7", `last_insert_rowid` after rolled-back rows,
  is `traps.c`'s.

- **Line citations,** read at `0913468`, now stand elsewhere, M3 slice 3 having grown both files:
  `connection.sls:478–520` at `:606–648`, `connection.sls:470–473` at about `:598–601`, and
  `statement.sls:437–438` at `:595–596`.
- **For slice 4:** `with-transaction`'s own statements go through `checked-out`, whose check is
  the call's flag (ADR-0016, amended in M3 slice 3). Whether `ended` is passed as that check, so a
  second resume of its remainder touches none of its statements, is slice 4's to decide, with a
  row.

## Amendment, 2026-11-16: `with-transaction` as built (M3 slice 4)

Accepted by the maintainer on 2026-11-16 ("Accept all").

M3 slice 4 built `with-transaction` in `(chez-sqlite3 private transaction)`, over slice 1's plan,
and settled what the records left to it. The evidence is in
[research/m3-slice-4/](../research/m3-slice-4/README.md) and
[the slice's log](../m3-slice-4-mutation-log.md). The groundwork's probes, `levels.c` and
`failed-active.c` among them, are in
[research/m3-slice-4/groundwork/](../research/m3-slice-4/groundwork/README.md). Each point is held by a row, watched failing
against a plant.

- **`ended` is the check-out's check** (slice 3's question, settled by a row). A remainder taken
  once `ended` is set and resumed a second time touched none of the call's statements, on either
  library: at the final text, 303 and 306 remainders, outer and nested, each answering 42, the
  re-entry's refusal or `&sqlite-transaction-ended`. With a check-out that read nothing, a second
  resume's `COMMIT` or `RELEASE` reached SQLite and answered an error; under the three sections
  first built, one that read only the use's own flag checked out `COMMIT` or `RELEASE` again in 6
  of 381 remainders a level.
- **Each of its own statements is taken from the cache, stepped and given back in one critical
  section** (the maintainer, 2026-11-16: "One section per statement"). In three sections, an engine
  that expired between a failed `RELEASE`'s step and its return, and was then lost, left that
  statement tracked as `failed`, so every later `with-transaction` on the connection was refused,
  with no statement of the caller's to reset.
- **A failed commit's rollback runs with its plan in one critical section.** With the plan and
  each step in sections of their own, an expiry between `ROLLBACK TO` and `RELEASE` let the
  critical after thunk issue the `ROLLBACK TO` again, against slice 3's "Once". Recording how far
  the rollback had gone, step by step, failed the engine sweep while each statement took three
  sections. With one section a statement, that design passes the sweep, but a timer's handler
  that re-enters the body from inside the call still ran the `ROLLBACK TO` twice under it, and
  never with the plan and the rollback in one section, which leaves no window at all. A row
  holds both.
- **A rollback stops at its first failed step** (the maintainer, 2026-11-16: "Confirm, and name
  the SQL"). After a failed `ROLLBACK TO`, no `RELEASE` is issued: it can undo nothing, and it
  fails the same way. `ended` is set in the section of the last step taken, so slice 3's "the
  `RELEASE` after `ROLLBACK TO`" reads "the last step taken".
- **A failure in giving one of its own statements back to the cache is dropped,** and the step's
  outcome is the answer (confirmed the same day). The review found no path where it happens.
- **Decision 1's refusal carries the held statement's state and SQL** (the maintainer, the same
  day): its irritants are `(statement-not-finished STATE SQL)`, STATE `row` or `failed`, both read
  in the section that refuses.
- **A remainder resumed again while an earlier resume of it is pending** (the schedule M3
  slice 5's review found) leaves the level whole. In about 2,090 trials a level, each
  with a fresh connection and engine, the depth was restored, none of the call's statements was
  left behind or outside the cache, and a later call committed. `ended` and `begun` are set
  in the section of the step that decides them, never when the call ends.
- **The savepoints' names are built inside `call-with-open-handle`'s section,** where no expiry
  lands. Under a remainder resumed a second time, Chez's `number->string` answered "", and a plant
  that built the name outside the section handed SQLite `SAVEPOINT chez_sqlite3_`, which it took
  as a savepoint of that name.
- **Consequences,** each a sentence in `docs/reference.md`'s Transactions:
  - **A handler that runs before the unwind is part of the body** (the maintainer, 2026-11-16:
    "Document it"). A `with-exception-handler` handler of the body's raise runs inside the call:
    whatever it leaves open is committed or rolled back with the rest of the level, as the body's
    own SQL is, since autocommit can't tell one transaction from another. A handler that escapes
    has it rolled back; one that resumes the body has it committed by the body's return. A `guard`'s clause runs after the unwind
    and isn't affected. Once the call has ended its own level, as when a return after the
    transaction ended raises `&sqlite-transaction-ended`, it issues nothing more, and a
    transaction a handler begins then stays open.
  - **Resuming an engine, or calling a continuation, taken outside the call from inside it leaves
    the call.** Chez runs the call's after thunk and then its before thunk, so the level rolls
    back, and its return raises `&sqlite-transaction-ended`. The depth and the savepoints' names
    hold ("Reuse N").
  - **An expiry whose rollback fails loses the engine:** its caller gets an assertion violation,
    "no engine active", as for the conveniences (ADR-0016, amended in M3 slice 3).
  - **A second resume of a remainder commits nothing again.** It may answer as the first did,
    raise `&sqlite-transaction-ended`, or refuse the re-entry.
- **The engine sweep runs to completion,** past the plan's "fuel from 1 to 60", as the global
  constraints ask. At the final text it completes at fuel 112, and slice 1's plant fails at fuels
  106 to 109, against the model's 138 to 174. A fuel is the suite's as well as the code's: rows
  added elsewhere in the suite moved every sweep by two fuels.

## Amendment, 2026-11-16: a deferred transaction's first write (M3 slice 6)

Proposed in M3 slice 6, from part B's builder's report and the lead's checks (the slice's
[mutation log](../m3-slice-6-mutation-log.md), part B;
[research/m3-slice-6/](../research/m3-slice-6/README.md)).

- **The consequences' "a deferred transaction's write under contention fails at once" holds only
  once the transaction has read,** as the context says. Measured alike on both libraries
  (`deferred-first-write.sps`), under a 1500 ms busy timeout, beside another connection's open
  write:
  - a deferred transaction's first write, with nothing read, waited 1501 to 1502 ms, then
    answered `busy`, extended `busy`;
  - the same write after a `select` answered `busy` in 0 ms;
  - each left the transaction open, `in-transaction?` true.

  SQLite calls the busy handler only while no read transaction is open (concurrency B2).
  `docs/reference.md`'s `'deferred` sentence now says "once it has read".
- **The default, `immediate`, under contention,** in `test-contention`. Two threads each run a
  body that reads, then writes: the second's `BEGIN IMMEDIATE` waits for the first's commit, and
  both commit. The same bodies under `'deferred` meet `busy-snapshot`.
- **`with-transaction`'s own `BEGIN` waits out its timeout once,** with no retry in Scheme
  (ADR-0019, decisions 8 and 11). `test-contention`'s row T waits 1502 ms under another's write
  lock, then raises `&sqlite-busy` with nothing begun. A plant that retried the `BEGIN` once
  waited 3004 ms, and only T failed it.
