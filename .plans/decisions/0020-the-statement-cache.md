# ADR-0020: The statement cache keeps a set number of reset statements per connection, prepared persistent, and lets a failed one go

- **Status:** Accepted (the maintainer, 2026-11-15), proposed in M3 slice 0. Decision 1's size is the maintainer's own
  choice, the same day: "32, configurable", 32 by default and a `statement-cache` setting from 0
  (off) up ([the M3 plan](../2026-11-15-m3-plan.md), §3, Q11), not the recommendation, which was 32
  fixed. Its largest value, 1024, is the maintainer's too, "Cap at 1024" (Q13). Decision 8 is
  settled by slice 0's research (P1). Revised the same day after the plan's adversarial review:
  decisions 5, 7 and 9, for a return into a full cache, a reset's failure, the section, and a close
  that fails. Amended 2026-11-15 in M3 slice 1, and accepted by the maintainer that day: the table
  keyed by `string=?`, a statement returned twice, and the engine row's bound
  ([amendment](#amendment-2026-11-15-what-m3-slice-1-settled)). Amended 2026-11-16 in M3 slice 3,
  and accepted by the maintainer that day: the cache as built, decision 7's section, and the
  call's flag ([amendment](#amendment-2026-11-16-what-m3-slice-3-built)). Amended 2026-11-16
  in M3 slice 5, and accepted by the maintainer that day: the setting reaches the record
  ([amendment](#amendment-2026-11-16-the-setting-reaches-the-record-m3-slice-5)). Amended
  2026-11-16 in M3 slice 5's part D, and accepted by the maintainer that day: the check-out and
  the return claim
  ([amendment](#amendment-2026-11-16-the-check-out-and-the-return-claim-m3-slice-5-part-d)).
  Amended 2026-11-17 in M3's closing review: decision 7's check of the SQL is inside the section
  ([amendment](#amendment-2026-11-17-where-the-sql-is-checked-m3s-closing-review)).
- **Date:** 2026-11-15
- **Scope:** chez-sqlite3 v1: the statements the conveniences reuse
- **Settles:** brief D3 (the maintainer, 2026-11-14: in M3), and its leaning, "bounded and cleared
  by close"
- **Related:** [ADR-0014](0014-statements-belong-to-their-connection.md) (statements, tracking) ·
  [ADR-0016](0016-the-conveniences-and-the-counters.md) (the conveniences) ·
  [ADR-0017](0017-with-transaction-and-savepoints.md) (its statements) ·
  [ADR-0018](0018-the-settings-list.md) (the `statement-cache` setting) ·
  [research/m3-plan/single/](../research/m3-plan/single/README.md), B4 ·
  [the M3 plan](../2026-11-15-m3-plan.md), §4.6

## Context

Measured on Guix's 3.53.1 and at the floor, 3.45.1, alike but for sizes (M3's research, single;
"concurrency" names its other half):

- **Lookaside** (K1): 50 held statements of a small SELECT, prepared with flags 0, filled the
  connection's 123 lookaside slots, and `LOOKASIDE_MISS_FULL` grew. Prepared with
  `SQLITE_PREPARE_PERSISTENT`, a held statement took no lookaside, and 2,280 bytes of heap on
  3.53.1, 1,752 at the floor. A running statement still takes lookaside.
- **The cost** (cost): through bare FFI, reusing a statement saved 1.9 to 2.3 µs a round against
  preparing it, a lower bound for the library, whose prepare and finalize add critical sections,
  checks, counters and scans. `PERSISTENT` made a prepare 0.36 to 0.81 µs dearer, and a reuse
  within 50 ns either way.
- **A schema change** (K2): after `CREATE INDEX`, a held statement re-prepares at its next step
  and keeps its bindings (K2.1, K2.6). After a column is added, by its own connection or another,
  its column count changes at that step, never before, and not while it holds a row (K2.2, K2.3,
  K2.7). After `DROP TABLE` its step answers 1, "no such table", and it runs again in the new
  shape if the table comes back (K2.4, K2.8). **A held INSERT whose re-prepare failed reports a
  stale schema** until another statement on its connection reads the table (K2.10, T6).
- **`sqlite3_stmt_busy` reads 1 after an `EXPLAIN` answers done** (K3, T11).
- **A held statement makes `sqlite3_close` answer BUSY** (single b5 V2); ADR-0014's close
  finalizes every tracked statement first.
- **A statement left at a row keeps an interrupt in force** (concurrency I3, I4b).
- **Most PRAGMAs apply at prepare** (single P3). **A PRAGMA statement reset and stepped again,
  with no prepare, applied its setting again,** for each of the six settings, `cache_size` and
  `user_version`, with flags 0 and with `PERSISTENT`: SQLite re-prepared it at that step, its
  `SQLITE_STMTSTATUS_REPREPARE` count going from 0 to 1. It did so with nothing run between its
  two steps, and after a change the C call `sqlite3_busy_timeout` made (M3 slice 0's research, P1,
  P1b, P1c). The control, a SELECT stepped twice with nothing between, didn't re-prepare (P1d).
- **Any set of two PRAGMAs expires every other statement:** run between a held SELECT's two
  steps, `foreign_keys = 1`, `= 0` and `= off`, and `trusted_schema = 0` and `= 1`, each made it
  re-prepare at its next step, with the value changed or not. No read form of the six settings
  did, no set of the other four, nor `cache_size`, `SELECT 1` or nothing (slice 0's P13, P13b).
  The plan's two reviews found these first.

## Decision

1. **One cache per connection, in its record, keyed by the SQL's exact text** (`string=?`), by
   a copy the caller can't reach: a statement is filed under its own SQL copy, the one M2's
   record holds and never changes, and a lookup uses a copy of the caller's string made before the
   section, so a caller changing its string can't corrupt the table (ADR-0011, decision 2). It
   holds at most N statements, the least recently used out first. An evicted statement is
   finalized. **N is the connection's `statement-cache` setting,** 32 when its settings give none,
   an exact integer from 0 to 1024 ([ADR-0018](0018-the-settings-list.md),
   decision 3). It is fixed when the record is made, at open, so the cache never shrinks under the
   statements it holds.
2. **At 0 the cache is off.** Every user of decision 3's list prepares its statement afresh, with
   no flags, as `prepare-statement` does, and finalizes it when done, on every path. Nothing else
   changes: each convenience answers and raises as it would with a cache, and only its cost
   differs.
3. **Who uses it:** `execute!`, `query`, `query-row`, `query-fold`, and `with-transaction`'s own
   statements. **Never** `prepare-statement` or `call-with-statement`, whose statements are the
   caller's, nor `execute-script!` or the settings, whose statements run once.
4. **While N is above 0, its statements are prepared with `SQLITE_PREPARE_PERSISTENT`,** so the
   statements it holds leave lookaside to those running. It costs at a miss only.
5. **A statement is checked out while in use,** and out of the cache meanwhile, so a fold's
   procedure that runs the same SQL prepares another. **When it comes back,** it is reset and its
   bindings cleared, and it becomes the most recent. **A return into a full cache evicts the least
   recently used statement,** and the returned one stays. The returned one is finalized instead
   only when:
   - N is 0;
   - it is `query-fold`'s, leaving by any exit but a normal return
     ([ADR-0016](0016-the-conveniences-and-the-counters.md), decision 6);
   - the cache already holds that SQL, returned meanwhile;
   - its step or a read left it `failed`, so the next call prepares afresh and reads the schema
     then;
   - its reset or its clearing raised. **That failure is raised,** after the convenience's own
     work, unless the convenience is already raising a condition of its own, which reaches the
     caller unchanged. `query-row` on a multi-row `insert … returning` in autocommit commits at
     that reset, which can answer BUSY and roll the insert back (ADR-0014's context).
   **A finalized statement is a miss,** in the cache or checked out: it is never handed out.
6. **The cache trusts ADR-0014's states, never `sqlite3_stmt_busy`,** and holds only statements
   in `ready`.
7. **Every change to the cache is made in a critical section that raises nothing and answers
   data,** so two engines sharing a connection can't interleave a check-out with a return. A
   section isn't a lock between threads, which M2's closing review measured; none is needed here,
   since only the connection's owner thread reaches its cache (ADR-0010, decision 1), and the
   section keeps out that thread's own engines and interrupts:
   - **before the section,** the database is checked to be one, on its owner's thread, and the SQL
     to be a string, and copied, so the lookup can't raise and its key can't change;
   - **in the section,** inside `call-with-open-handle`'s, the connection is checked open, and the
     table is only read and changed: a check-out answers a statement or a miss, and a return
     answers the statement it evicted, if any;
   - **after it,** an evicted statement is finalized by M2's finalize. It is reset, so its finalize
     has nothing to commit, but a failure of its own is raised, under decision 5's rule;
   - a row sweeps two engines sharing a connection over fuel 1 to 60, each running the same
     conveniences on the same SQL, as M1's closing review swept `call-with-open-handle`: no
     statement is handed out twice, finalized twice or lost, each answer is right, and the
     `statement` count ends where it began. A mutant without the section fails it (M3 slice 3).
8. **A PRAGMA statement is cached like any other** (P1): reused, it applied its setting again, and
   the cache needs no rule of its own for it. Caching one saved no prepare at its second step,
   since SQLite prepared it again there. **Any set of `foreign_keys` or `trusted_schema` makes
   every other cached statement re-prepare once at its next use** (P13, P13b): right, never stale,
   and a prepare's cost each, which `docs/reference.md` names. The cost probe sets neither.
9. **The close empties the cache, whether or not the connection closes.** The cache's statements
   are tracked by their connection, so `close-database!` finalizes them, oldest first, before
   `sqlite3_close` (ADR-0014, decision 8). They are reset, with nothing pending, so their finalize
   answers `SQLITE_OK`. The same section clears the record's cache. A close that leaves the
   connection open, on a statement found untracked (`connection.sls:417`) or `sqlite3_close`
   failing (`connection.sls:428`), has finalized them all the same, so a cache kept through it
   would hold freed statements. With decision 5's miss, no convenience is ever handed one.

### Rejected

- **Flags 0, as `prepare-statement` passes:** held statements fill lookaside, which the statements
  actually running then miss.
- **Keeping a statement whose step failed:** a stale re-prepare goes on failing.
- **`sqlite3_stmt_busy` to tell a statement in use:** it reads 1 after an `EXPLAIN` is done.
- **Keying the table on the caller's own string:** a caller that changed its string after the call
  would change a key the hashtable had already filed.
- **A cache that `prepare-statement` shares:** a caller's statement would then be one the cache
  could reset or finalize under it.
- **Unbounded:** each held statement keeps heap, and a long-lived connection that runs generated SQL
  would grow without end. The setting is bounded for the same reason (the plan's Q13).
- **A fixed size,** the recommendation, declined in Q11; so were 128 and off by default.
- **Keeping PRAGMA statements out,** the contingency drafted before P1: a reused one re-applies.
- **Resizing after open:** a cache that shrank would have to finalize statements it holds, and
  the settings run only at open (ADR-0018, decision 6).
- **Clearing nothing on return:** a statement holding a large bound value would keep its copy for
  as long as it stays cached.

## Consequences

- **A cached statement counts in the `statement` counter** while its connection is open, and the
  close counts it down. A suite that runs a convenience and closes its connection still exits at
  zero.
- **What the cache saves through the library is measured in M3 slice 3** (the M3 plan's probe P8),
  against the same calls at a capacity of 0, with no `foreign_keys` or `trusted_schema` set in its
  loops (decision 8). It is a research probe, never a suite row under the gate.
- **Slice 3 sets the capacity privately.** It builds the record's capacity, with a private way
  for the suites to make a connection of a given capacity, so its rows at 0, its cost probe and
  the plan's 50-statement lookaside plant need no settings list. Slice 5 adds the public
  `statement-cache` setting, which reaches the same field.
- **How the size is tested:** the pure table at capacities 0 to 3, over every order of check-outs
  and returns of three keys, and at 32 (M3 slice 1); through the public surface, the `statement`
  count after 33 distinct statements is 32 at the default, 0 at 0 and 1 at 1, and at 2 the
  statements A, B, A, C leave A and C, read through `tracked-statements` (M3 slice 5). A mutant
  that ignores the setting, or evicts one too early or too late, fails those rows.
- **A failed close leaves the cache empty** (decision 9), held by a row that makes the close fail
  both ways, through the suite's own `sqlite3_backup_init` as M2's suites do for the close, and
  through a planted untracked statement, then runs a convenience on the still-open connection.
- **A held statement re-prepares at its next step after a schema change,** as any prepared
  statement does, and `query` reads its columns after the step (ADR-0016, decision 3).

## Amendment, 2026-11-15: what M3 slice 1 settled

Accepted by the maintainer on 2026-11-15 ("Accept all"), proposed in M3 slice 1, from its
adversarial review (`(chez-sqlite3 private statement-cache)`).

- **The table is keyed by `string-hash` and `string=?`,** decision 1's exact text. The plan's §5
  had asked for opaque keys, and the first build matched them by `equal?`. The review showed a
  record key running its type's own hash and equality procedures inside the section, and raising
  there. The caller passes its copy of the SQL, checked to be a string before the section.
- **A return of the very statement already held under its key** answers nothing to finalize, and
  the table keeps it where it stood. A different statement returned under a held key is the one
  finalized, by decision 6.
- **A finalized statement is a miss** (decision 9) is checked by the caller, slice 3, in the
  section that checks out or returns, from the statement's own state: the table calls nothing of
  its caller's.
- **Every engine row of M3 sweeps fuel from 1 until a fuel at which the call completes without
  expiring,** not to a fixed 60, and names that fuel. Slice 1's review modelled `with-transaction`
  and found its one window at fuels 138 to 174, past 60, and two engines' conveniences through the
  cache can lie past 60 too ([ADR-0017](0017-with-transaction-and-savepoints.md), amended).

## Amendment, 2026-11-16: what M3 slice 3 built

Accepted by the maintainer on 2026-11-16 ("Accept all"), proposed in M3 slice 3, from its builders'
reports and its adversarial review ([research/m3-slice-3/](../research/m3-slice-3/README.md)).

- **The record holds its table,** its capacity fixed at open.
  - `open-database-with-cache-capacity` is the suites' opener until slice 5's setting. It checks
    the capacity by the settings' own rule, `setting-out-of-domain statement-cache`.
  - The default, 32, is read from slice 1's settings plan, so it is written once.
  - `database-cache-check-out!`, `database-cache-return!`, `database-cache-capacity` and
    `database-cache-count` reach the table, the first two only inside a verb's section.
- **Decision 7's section, as built,** does more than read and change the table, and still raises
  nothing:
  - the return's section also resets the statement, clears its bindings and files it;
  - it finalizes there a statement whose step failed, or whose reset or clear failed;
  - what the table answers, an evicted statement or the returned one, is finalized after.
- **The check-out's and the return's sections read the call's flag first** (ADR-0016, amended
  in M3 slice 3, "Guard every call"). So a second resume of a convenience's remainder can't hand
  a statement out twice, nor file it twice. `checked-out` takes the check, `#f` for none.
- **A cached statement that is live but not ready,** moved privately through
  `tracked-statements`, is a miss: dropped from the cache, still tracked.
- **Measured, alike on both libraries:**
  - ten held statements took 70 lookaside slots with no flags, and none with `PERSISTENT`;
  - one 200-column `select` took 123 against 0.
- **Slice 5's rows, which slice 3 already holds,** set privately:
  - after 33 distinct statements, the `statement` count is 32 at the default, 1 at 1 and 0 at 0;
  - at 2, A, B, A, C leaves A and C.
- **The eviction's finalize fails only for a statement moved to its row privately:** a cached
  `insert … returning` so moved failed busy at its eviction, under another's read.
- **The consequences' failed-close rows** use `checked-out`, not a convenience.
- **The two-engine sweep, through the conveniences,** completes unexpired at fuel 259.
- **Line citations:** decision 9's `connection.sls:417` and `:428`, read at `0913468`, are now at
  `:509` and `:520`.

## Amendment, 2026-11-16: the setting reaches the record (M3 slice 5)

Accepted by the maintainer on 2026-11-16 ("Accept all"), proposed in M3 slice 5
([ADR-0018](0018-the-settings-list.md), amended in M3 slice 5).

- **The open verbs pass the list's `statement-cache` to the record,** through
  `connection-outcome`, before any PRAGMA runs (decision 1). The default, 32, is still read from
  slice 1's settings plan, so it is written once.
- **`open-database-with-cache-capacity`, the suites' opener until this slice, is gone.** Slice 3's
  suites open with `'((statement-cache . N))`.
- **§4.8's cache plants are caught:** the cache ignoring its setting, or evicting one too early or
  too late, each fails the rows that count statements after 33 distinct ones through `query`, at
  0, 1, 2 and the default (the slice's [mutation log](../m3-slice-5-mutation-log.md), part B).

## Amendment, 2026-11-16: the check-out and the return claim (M3 slice 5, part D)

Accepted by the maintainer on 2026-11-16 ("Accept all"), proposed in M3 slice 5's part D
([ADR-0016](0016-the-conveniences-and-the-counters.md), amended the same day).

- **For `execute!`, `query` and `query-row`, the check-out and a miss's prepare are one section,
  the call's first claimed, and the return is its last.** They pass `checked-out` no check, `#f`:
  the claim decides, in the section around it. Slice 3's flag, read by the check-out's and the
  return's sections, could not tell one pending run of a call from another: a run found the
  statement another run held out of the cache, and prepared a second.
- **The statement is noted inside the check-out's section,** by `checked-out`'s on-made, so a
  raise just after the section still gives it back.
- **`query-fold` still passes its flag** to `checked-out`, as slice 3 built it.

## Amendment, 2026-11-17: where the SQL is checked (M3's closing review)

Proposed in M3's closing review, from reviewer A's reading, which the lead checked against the
code.

- **Decision 7 says the SQL is checked to be a string, and copied, before the section.** That held
  until slice 5's part D. Since then, for `execute!`, `query` and `query-row`, the check-out and a
  miss's prepare are one section, the call's first claimed (the part D amendment, above).
  `checked-out`, and `checked-sql` within it, now run inside that section.
- **So the check, the copy and its UTF-8 run inside the section,** where the thread's engines,
  timers and interrupts wait on them. A refusal raised there is caught inside the section and
  raised after it, as every raise in the conveniences is (ADR-0016). For a long SQL, `execute!`
  holds its thread for the copy and its encoding as well as the prepare, where
  `prepare-statement` holds it for the prepare alone.
- **Nothing changes in the code.** The decision's text now says what is built.
