# ADR-0016: The conveniences run one statement each and finish it on every path, and the counters are read as SQLite keeps them

- **Status:** Accepted (the maintainer, 2026-11-15), proposed in M3 slice 0. The maintainer's own choices, the same day
  ([the M3 plan](../2026-11-15-m3-plan.md), §3): decisions 1 and 8's names, "Short names" (Q1);
  decision 3's row, "A vector" (Q2); decision 4's `query-row`, "#f, or the first" (Q3); decisions
  4 and 7's two verbs, "Two verbs" (Q4). Decision 7's NULL statement is measured by slice 0's
  research (P11). Revised the same day after the plan's adversarial review: decisions 3, 5, 6, 7
  and 9, for the re-entry pattern, the held read, the row reader, the who, and a script's step
  error. Decision 6's refusal of `with-transaction` is the maintainer's answer to the plan's Q14.
  Revised again after the plan's second review: decision 6's fold, for a re-entry after a normal
  return, its flag as M3's own, and its raise record over the whole body; decision 7's errors,
  rebuilt with the script. Decision 3's section per value is the maintainer's "One value each" (the
  plan's Q15), from M2's closing review.
- **Date:** 2026-11-15
- **Scope:** chez-sqlite3 v1: `execute!`, `execute-script!`, `query`, `query-row`, `query-fold`,
  `changes`, `total-changes`, `last-insert-rowid`, `in-transaction?`
- **Settles:** brief §4's conveniences and counters
- **Related:** [ADR-0014](0014-statements-belong-to-their-connection.md) (statements) ·
  [ADR-0015](0015-values.md) (values) ·
  [ADR-0017](0017-with-transaction-and-savepoints.md) (transactions) ·
  [ADR-0020](0020-the-statement-cache.md) (the cache) ·
  [research/m3-plan/](../research/m3-plan/README.md) (the measurements) ·
  [the M3 plan](../2026-11-15-m3-plan.md), §4.1

## Context

- **M2's statement tier** prepares one statement (ADR-0014, decision 4), keeps its state in Scheme
  (decision 5), binds every parameter at once with `bind-all!` (ADR-0015, decision 6), and reads a
  column only in the `row` state. The conveniences are built on it.
- **Measured** on Guix's 3.53.1 and at the floor, 3.45.1, alike (M3's research; "single" and
  "concurrency" name its two halves):
  - **a statement left at a row costs its connection.** While one holds a row, an interrupt
    sticks, and every new prepare and step answers 9 until it is reset (concurrency I3, I4b, trap
    2), the statements that end a transaction among them (M3 slice 0's research, P7). `COMMIT`
    answers BUSY while the connection's own write is unfinished, such as an `insert … returning`
    that has answered a row (single O7; concurrency B11; M2's wording, PR #19). With the
    connection's own SELECT held at a row, its `BEGIN IMMEDIATE` and an autocommit INSERT
    answered BUSY at once under another's write lock, where without the held read they waited out
    a 1500 ms timeout (slice 0's P12). `sqlite3_close` answers BUSY while one is unfinalized
    (single b5 V2);
  - a statement's column count changes at the step that re-prepares it, never before (single K2.1,
    K2.2, K2.7);
  - `sqlite3_exec` runs statements that answer rows and drops the rows (single script X7), and a
    PRAGMA's set can answer a row (single P1);
  - **a script:** `sqlite3_exec` and a loop of prepares both stop at the first error, the
    statements before it standing, and neither begins, ends or rolls back a transaction (single
    script X1 to X4, X16). Empty SQL, only semicolons, only comments are no error (X9 to X12). The
    loop's prepare gives an error's offset from where it started; `sqlite3_exec`'s counts from the
    failing statement, its whitespace skipped (X5, T10). Preparing a PRAGMA applies it (single
    P3), so a runner prepares each statement only after the one before it has run, as both do;
  - **the counters** (single B2): `sqlite3_changes64` is the last INSERT, UPDATE or DELETE's, and
    DDL, SELECT, PRAGMA, `BEGIN` and `COMMIT` leave it unchanged (C3, C4). A `RETURNING` statement
    moves it only at done or reset (C12, C12b, C12c). `sqlite3_total_changes64` counts trigger and
    cascade rows, and rows later rolled back (C9, C10, C15). `sqlite3_last_insert_rowid` can name
    a row a failure or a `ROLLBACK` undid (C5, C15, T7), and doesn't move for a WITHOUT ROWID table
    or an upsert's DO UPDATE (C8, C11). Another connection's writes move none of them (C13);
  - `sqlite3_get_autocommit` is 0 after a deferred `BEGIN` that has read nothing, and 1 while an
    autocommit SELECT holds a read (single B1, items 1 and 2);
  - column names can repeat: `select 1 as a, 2 as a` names `a` twice (M2 slice 4's research, §4).
- **Engines:** an expiry runs `dynamic-wind`'s after thunk (ADR-0012, amended), so
  `call-with-statement` doesn't survive one, while prepare, step, reset and finalize complete at
  every fuel from 1 to 60 (ADR-0014's slice 3 amendment).
- **A guard whose clauses don't match re-enters the raise's extent to raise again,** running a
  `dynamic-wind`'s before thunk a second time. A before thunk that refuses a re-entry then
  replaces the caller's condition with its own: measured on Chez 10.4.0 by the M3 plan's review,
  for a refusing wind and for M1's `call-with-c-string`, whose `call-with-block` refuses one. M2's
  `call-with-statement` and `call-with-database`, whose before thunks do nothing, delivered the
  caller's condition (`connection.sls:465–470`, `statement.sls:434`).
- **Slice 4's values** (PR #19): `statement-values.sls`'s private `read-outcome` reads a column's
  data inside a section, and `finish` decodes and raises after it; a NULL pointer's code 7 is NOMEM
  only when the column's type has turned NULL (ADR-0015's slice 4 amendment).
- **A value is copied byte by byte with this thread's interrupts off.** M2's closing review
  measured a 64 MiB BLOB `column-value` at 1932 ms and a 64 MiB `bind!` at 2000 ms, about 30 ns a
  byte; an engine reading one ran 1.8 s with no expiry, while another thread's
  `collect-rendezvous` waited 0 to 7 ms. ADR-0015 records it, in M2's closing-review PR.

## Decision

1. **The surface,** in the maintainer's names (Q1):

   ```scheme
   ;; execute! : Database String Value ... -> Void
   ;; execute-script! : Database String -> Void
   ;; query : Database String Value ... -> (Listof Row)
   ;; query-row : Database String Value ... -> (U Row #f)
   ;; query-fold : Database String (A Row -> A) A Value ... -> A
   ;; changes : Database -> Natural
   ;; total-changes : Database -> Natural
   ;; last-insert-rowid : Database -> Integer
   ;; in-transaction? : Database -> Boolean
   ;; Row = (Vectorof Value)
   ```

   Each signature is one line with nothing after it, as `test-reference` reads them.

   ```scheme
   (execute! db "insert into t (id, name) values (?, ?)" 1 "a")
   (query db "select id, name from t where id > ?" 0)        ; => (#(1 "a"))
   (query-row db "select name from t where id = ?" 2)        ; => #f
   (query-fold db "select id from t" (lambda (acc row) (+ acc (vector-ref row 0))) 0)
   ```

2. **Parameters are positional, after the SQL,** bound by `bind-all!`'s rule: every parameter, 1
   to n, from n values, each checked before any is bound (ADR-0015, decision 6). A named
   parameter binds by its index; binding by name stays `bind!`'s.
3. **A row is a vector of its values, in column order** (Q2). Each is read at the row, after its
   step, by ADR-0015's rules, its count read once then and never at prepare. **Each value is
   copied in a critical section of its own, read or bound** (the plan's Q15): a column
   through M2's who-taking column read, and a parameter through its who-taking bind, every value
   checked in Scheme before any is bound, as `bind-all!`'s rule has it. A value's copy takes about
   30 ns a byte with this thread's interrupts off (M2's closing review; ADR-0015, in its
   closing-review PR), so a section never holds more than one. A row read across sections stays
   consistent, since nothing but its convenience steps a checked-out statement, on the owner's
   thread, and a column count changes only at a step (the context). `query-fold` calls
   `(proc acc row)`, as R6RS `fold-left` calls its procedure.
4. **One statement each.** The SQL is prepared by ADR-0014's rules, through the cache
   ([ADR-0020](0020-the-statement-cache.md)), or afresh each time when the connection's
   `statement-cache` setting is 0. So SQL holding none or more than one is refused as
   `prepare-statement` refuses it.
   - **`execute!` steps to done, drops any rows, and answers nothing** (Q4). No counter
     answers "the rows this statement changed" for every statement, so the caller reads `changes`
     knowing what it counts.
   - **`query`** answers every row, in order. **`query-row`** answers the first row, or `#f` when
     there is none, and reads no further (Q3).
5. **Each finishes its statement on every path before it returns or raises:** back to the cache,
   reset with its bindings cleared, or finalized (ADR-0020), as it always is at a
   `statement-cache` of 0. None is left at a row once it has returned or raised; `query-fold`
   holds its row while its procedure runs (decision 6).
   - **A reset's own failure, on the way back to the cache, is raised:** the statement is
     finalized, not kept, and the failure raised after, unless the convenience is already raising
     a condition of its own, which reaches the caller unchanged. `query-row` on a multi-row
     `insert … returning` in autocommit commits at that reset, which can answer BUSY and roll the
     insert back (ADR-0014's context).
6. **The ways out.**
   - **`execute!`, `query` and `query-row` call no procedure of the caller's and hold no
     `dynamic-wind`:** a raise inside them is caught, the statement finished, and the raise made
     again after, the same object. So each is expected to complete under an engine, as prepare and
     step do; M3 slice 3 measures it at every fuel from 1 to 60. **A way out that isn't a raise**,
     a timer's or a keyboard interrupt's handler that escapes, or an engine that expires inside one
     and is never resumed, leaves the checked-out statement at its row: out of the cache, tracked
     and counted until the close finalizes it, keeping an interrupt in force on its connection,
     for a write making its `COMMIT` answer BUSY, and making every `with-transaction` on the
     connection refuse ([ADR-0017](0017-with-transaction-and-savepoints.md), decision 1). The
     caller can't reset a statement it never held, since `tracked-statements` is private, so the
     remedy is to close the connection. `docs/reference.md` says so.
   - **`query-fold` calls the caller's procedure with its statement at a row.** Its shape is
     M2's `call-with-statement` (`statement.sls:442–475`) where M2's holds:
     - a plain `dynamic-wind` around a critical one. The plain winder's before thunk does nothing,
       so a re-entry goes through (the context). The critical winder's after thunk finishes the
       statement with interrupts disabled, under a guard that records a failure and raises
       nothing, and the plain winder's after thunk raises that failure unless a raise is under way;
     - the statement, a cache hit or a fresh prepare, reaches the fold's variable inside the
       section that checks it out or prepares it, as `call-with-statement`'s prepare hands its
       statement over inside its own section (`statement.sls:435–436`), so no escaping interrupt
       falls between the check-out and the after thunk's knowing of it;
     - a handler records a raise and hands it on in place, as M2's does. It covers the wind's whole
       body, the fold's own check-out, binds, steps and row reads as well as the procedure, so a
       failure of the fold's own counts as a raise, and a finish's failure is never raised over it.

     **And a flag of M3's own, where M2's shape doesn't hold.** M2's finish is idempotent through
     its resource: a finalized statement, or a closed connection, makes a second do nothing. The
     fold's isn't, since a statement given back to the cache may be another caller's by then. So:
     - the critical after thunk finishes only on the first exit, and sets the flag;
     - on a normal return the statement is at done, and goes back to the cache. On any other exit,
       a raise or an escape, it is finalized, never kept;
     - **the loop reads the flag before every step and every row read, and after every call of the
       procedure, and once it is set raises `&sqlite-closed` from `query-fold`, never touching the
       statement.** So a fold re-entered after any exit is refused at once: a continuation captured
       in the procedure and called after the fold returned, or a procedure resumed by an outer
       handler returning to a `raise-continuable` past a guard that re-entered. It never restarts
       from the first row. The M3 plan's second review measured the shape without this read,
       re-entered after a normal return: it stepped the cached statement from its first row again,
       answered 4 rows after 6, and left it in the cache at done, so the next check-out's `step!`
       was refused;
     - an escape that isn't a raise raises the finish's failure from the plain after thunk, as
       `call-with-statement` raises its finalize's. Under an engine's expiry that loses the engine,
       as ADR-0012's amendment measured for `call-with-database`; and an expiry finalizes the
       statement, so the resumed loop raises `&sqlite-closed`. `query-fold` doesn't survive an
       engine's preemption.
   - **While the procedure runs, its connection holds the fold's read,** so a write in it answers
     BUSY at once under contention (slice 0's P12), and an interrupt then sticks until the fold
     ends. `with-transaction` there is refused ([ADR-0017](0017-with-transaction-and-savepoints.md);
     the M3 plan's Q14).
7. **`execute-script!` runs a script with no parameters** (Q4):
   - **a loop of prepares, never `sqlite3_exec`.** M2's prepare, where more SQL follows the first
     statement, finalizes that statement and refuses (`made-outcome`, `statement.sls:380–386`). So
     M3 adds a private prepare beside it that hands back the first statement, live, and the tail's
     byte offset instead, by ADR-0014's checks in ADR-0014's section, with no flags. Each
     statement is stepped to done, its rows dropped, and finalized; then the loop prepares from the
     tail, and ends at the script's end. **A NULL statement ends it too.** A NULL statement's
     tail was the input's end in every case measured, and leading semicolons and comments went
     into the next statement instead: `;; select 2`, `-- c\n; select 2` and a U+FEFF then
     `; select 2` each prepared as one statement, its tail at the end (M3 slice 0's research, P11;
     single script X9 to X12). So the loop never skips SQL by stopping there;
   - **it stops at the first error,** and begins, ends or rolls back no transaction: the
     statements before it stand;
   - **SQL holding no statement is no error;**
   - **its `&sqlite-error` carries the whole script as `sql`, and an offset into it that says which
     statement failed,** in characters by ADR-0013's conversion:
     - for a prepare's error, the statement's start in the script plus SQLite's offset, so the
       token SQLite points at. SQLite's −1 gives `#f`;
     - for a step's error, which SQLite gives no offset, the failing statement's first token, past
       the whitespace, comments and semicolons before it, by ADR-0014's scan. This is the reason
       `sqlite3_exec` is rejected below: it can't say which statement failed, and the loop can;
     - **both are rebuilt, never raised as they came:** the loop takes the prepare's and the
       step's answers as data, the extended code and the message read straight after the call,
       through M2's who-taking internals (decision 9). It makes a new `&sqlite-error` from them,
       with the script and the offset, by `raise-sqlite-error`, which recomputes its class from the
       primary code (ADR-0013, amended), so a BUSY is still `&sqlite-busy`;
   - **a script holding U+0000 is refused** before anything is allocated (ADR-0011, amended). It is
     encoded once, into one counted block held for the loop by `call-with-c-string`, and each
     prepare passes the address of its statement's start, so a script of n statements is copied
     once, not n times. **Nothing raises out of the block's extent:** `call-with-block` refuses a
     re-entry, so a non-matching guard's re-raise would be replaced by its refusal. Every raise in
     the loop is caught inside the extent, answered as data, and raised after `call-with-c-string`
     returns: SQLite's failures rebuilt, as above, and anything else, an assertion violation of
     M2's checks among them, as the same object. The one re-entry left is an engine's resume after an expiry has
     freed the block, which `call-with-block` refuses, so `execute-script!` doesn't survive an
     engine's preemption;
   - it uses no cache.
8. **The counters,** in the maintainer's names (Q1): `changes` answers `sqlite3_changes64`, `total-changes`
   `sqlite3_total_changes64`, `last-insert-rowid` `sqlite3_last_insert_rowid`, and
   `in-transaction?` whether `sqlite3_get_autocommit` answers 0. Each checks its database, its
   owner and that it is open (ADR-0012, decision 7), and makes its one plain call through
   `call-with-open-handle`. `docs/reference.md` gives what each counts, by the context's
   measurements.
9. **Everything raised is raised after its critical section,** its `&who` the convenience's own
   name (ADR-0013, decision 2; ADR-0012, amended). M2's statement verbs name themselves, so M3
   reaches them through private procedures that take a who, for step, reset, finalize, bind, clear
   and the column reads, each on `call-with-statement-handle`, with M2's public verbs as thin
   wrappers passing their own names. M2's session agreed the shape, and M3 slice 3 builds it in
   M2's two libraries (the M3 plan, finding F11).

### Rejected

- **`sqlite3_exec` for scripts.** It would bypass ADR-0014's checked prepare, its offset counts
  from the failing statement (single T10), and with no callback it can't say which statement
  failed.
- **`execute!` answering `changes`,** declined in Q4: stale after any statement SQLite doesn't
  count. So were `execute!` taking a script when given no parameters, and no script runner.
- **Rows as association lists by column name,** declined in Q2: names repeat. So were lists, and
  the fold given the columns as its arguments.
- **`query-row` raising for no row, or refusing a second,** declined in Q3.
- **Refusing a statement that answers rows in `execute!`:** a PRAGMA's set answers one.
- **Leaving a convenience's statement at a row for a later call:** the context's three costs.
- **A `dynamic-wind` in `execute!`, `query` and `query-row`.** They call no code of the caller's,
  but a timer's or a keyboard handler's escape, or an abandoned engine, can still leave them
  (decision 6). A wind would finish the statement then, but also at every engine expiry, and the
  resume would step a statement reset under it. Without one, those escapes leave the statement at
  its row until the close, which `docs/reference.md` says.
- **A before thunk that refuses a re-entry,** in `query-fold` or around `execute-script!`'s
  block: under a guard whose clauses don't match, it replaces the caller's condition (the context).
- **Returning `query-fold`'s statement to the cache on an escape:** a procedure resumed after the
  extent finished would step it again from its first row, or step one the cache had handed on.
- **A fold whose loop trusts its variable after a normal return,** with no read of the flag: a
  continuation re-entered then steps the statement the cache holds (the M3 plan's second review).
- **The flag credited to M2:** M2's winders need none, being idempotent through their resource;
  the fold's finish isn't.

## Consequences

- **A caller who wants the rows a write changed** reads `changes` after `execute!`, and
  `docs/reference.md` gives what it counts.
- **`last-insert-rowid` can name a row that doesn't exist,** and `docs/reference.md` says so.
- **`query-fold` and `execute-script!` don't survive an engine's preemption;** a program under
  engines takes the statement tier, as ADR-0012's amendment has it take `open-database`.
- **A script's statements run one by one, each in its own transaction unless the script holds
  one,** as SQLite runs them. A caller who wants it atomic wraps it in `with-transaction`.
