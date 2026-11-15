# ADR-0020: The statement cache keeps a set number of reset statements per connection, prepared persistent, and lets a failed one go

- **Status:** Accepted (the maintainer, 2026-11-15), proposed in M3 slice 0. Decision 1's size is the maintainer's own
  choice, the same day: "32, configurable", 32 by default and a `statement-cache` setting from 0
  (off) up ([the M3 plan](../2026-11-15-m3-plan.md), §3, Q11), not the recommendation, which was 32
  fixed. Its largest value, 1024, is the maintainer's too, "Cap at 1024" (Q13). Decision 8 is
  settled by slice 0's research (P1). Revised the same day after the plan's adversarial review:
  decisions 5, 7 and 9, for a return into a full cache, a reset's failure, the section, and a close
  that fails.
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
