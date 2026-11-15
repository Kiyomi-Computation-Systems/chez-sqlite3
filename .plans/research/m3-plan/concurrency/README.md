# What M3's plan measured: interrupt, the busy timeout and contention

Measured 2026-11-15 in the Guix container (Chez 10.4.0 threaded, gcc 16.2.0), on an Intel Core
Ultra 5 125H (x86_64, 18 logical CPUs). Another agent's probes shared the machine, so every timing
is a distribution of 21 runs (min, median, max) and none is a single number. C probes with
pthreads measure SQLite's own semantics. A Chez program with bare `foreign-procedure` measures
this binding's architecture. Revised the same day after an adversarial review:
- the timer's reading (C3) was corrected: its ticks don't elapse during a foreign call;
- I5 gained the rule from the source, and a case with a function call;
- `busy_timeout(-1)`, `sqlite3_exec` and the busy cases' codes (B11) were measured;
- the contradictions section was narrowed, and questions 17 and 18 were added.

Three builds:

- **Guix's 3.53.1,** the container's own (`…-guix-3.53.1.txt`): `THREADSAFE=1`, 46 compile
  options ([options-guix-3.53.1.txt](options-guix-3.53.1.txt));
- **the floor, 3.45.1,** `build/m3-floor/`, CI's `floor` lane build: the pinned autoconf
  amalgamation, `$CC -shared -fPIC -O2 -DSQLITE_THREADSAFE=1 -Wl,-z,defs` (`…-floor-3.45.1.txt`):
  `THREADSAFE=1`, 37 options ([options-floor-3.45.1.txt](options-floor-3.45.1.txt));
- **one variant, for B3 alone:** the floor's `sqlite3.c` built the same way, plus
  `-DHAVE_NANOSLEEP=0` (`busy-…-floor-3.45.1-nanosleep0.txt`).

Every output prints `sqlite3_libversion()` and `sqlite3_sourceid()` as read at run time. Each C
probe is compiled against its library's own header and linked to that `.so` by `-rpath`. It
refuses to run unless the runtime version number and source id equal the header's. The Chez probe
refuses unless the runtime source id equals the header's. Connections open as chez-sqlite3 opens
them: `READWRITE | CREATE | EXRESCODE | FULLMUTEX` (ADR-0010), or `NOMUTEX` where a case says so.

```
$ scripts/guix-env sh .plans/research/m3-plan/concurrency/run.sh guix
$ scripts/guix-env sh .plans/research/m3-plan/concurrency/run.sh floor
$ scripts/guix-env sh .plans/research/m3-plan/concurrency/run.sh floor-nanosleep0
$ scripts/guix-env sh .plans/research/m3-plan/concurrency/run.sh guix check
```

`run.sh` builds each probe and runs it with a fresh scratch directory under the git-ignored
`build/m3rc/`, then writes its outputs beside itself. A run takes about 5 minutes per library.
With `check`, the outputs go to a fresh directory instead. Each output that isn't a timing is then
compared byte for byte with the committed one, and the script exits 1 on a difference. One probe
by hand, as `run.sh` builds it:

```
$ scripts/guix-env sh -c 'd=$(mktemp -d $PWD/build/m3rc/hand.XXXXXX) && i=$GUIX_ENVIRONMENT/include \
    l=$GUIX_ENVIRONMENT/lib && $CC -O2 -I$i -o $d/busy .plans/research/m3-plan/concurrency/busy.c \
    -L$l -l:libsqlite3.so.0 -Wl,-rpath,$l -lpthread && mkdir $d/s && $d/busy $d/s $d/timing.txt'
```

| Probe | Measures | Outputs, per build |
|---|---|---|
| [options.c](options.c) | version, threading mode, every compile option | `options-…` |
| [interrupt.c](interrupt.c) | A1: I1 to I8 | `interrupt-…`, `interrupt-timing-…` |
| [busy.c](busy.c) | A2: B1 to B11, and A4's busy claims | `busy-…`, `busy-timing-…` |
| [sweep.c](sweep.c) | A4: S1 to S6 | `sweep-…`, `sweep-timing-…` |
| [chez-interrupt.sps](chez-interrupt.sps) | A3: C1 to C3 | `chez-interrupt-…`, `chez-interrupt-timing-…` |
| `trap-*.c` | the five traps, each run twice on fresh files | `trap-…` |

**Reruns.** Each timed case prints its first run's facts and how many of its 21 runs gave the same
facts: 21 of 21 in every case, on both libraries. `run.sh LIB check` reran every probe from fresh
scratch on each build, and every non-timing output matched byte for byte. That was 10 of 10 files
for Guix's library, 10 of 10 for the floor, and 1 of 1 for the variant.

## The two libraries differ in these, and nothing else

1. **Their version, source id and compile options.** Guix's has `ENABLE_COLUMN_METADATA`,
   `ENABLE_DBSTAT_VTAB`, `ENABLE_FTS3`, `ENABLE_FTS4`, `ENABLE_FTS5`, `ENABLE_MATH_FUNCTIONS`,
   `ENABLE_PERCENTILE`, `ENABLE_UNLOCK_NOTIFY` and `SECURE_DELETE`, which the floor lacks.
   `MAX_FUNCTION_ARG` is 1000 against 127, and `COMPILER` is gcc-14.3.0 against gcc-16.2.0.
   Neither has `ENABLE_SETLK_TIMEOUT`, `ENABLE_API_ARMOR` or `DEFAULT_FOREIGN_KEYS`.
2. **A fresh connection's `SELECT 1` under another connection's `BEGIN EXCLUSIVE` and write** (B10,
   and I6e's follow-up). On 3.53.1 its prepare answers 5 (BUSY). On 3.45.1 it prepares and steps
   to a row. Every other statement B10 tries answers alike on both. The container holds no 3.53.1
   source, so why isn't read here.
3. **Timings agree within noise,** with two unexplained medians: I1 under `NOMUTEX`, the interrupt
   to the step's return, 0.089 ms on 3.53.1 against 0.003 ms (each max under 0.14 ms); and I7, the
   interrupt to the prepare's return, 3.6 ms against 5.0 ms.

## A1. `sqlite3_interrupt` from a second thread ([interrupt.c](interrupt.c))

[interrupt-guix-3.53.1.txt](interrupt-guix-3.53.1.txt),
[interrupt-floor-3.45.1.txt](interrupt-floor-3.45.1.txt); timings in `interrupt-timing-…`. Each
statement here runs on the main thread, and a pthread interrupts it.

1. **A long step stops at once** (I1). The step is a recursive CTE counting to 2×10⁹. Interrupted
   after 100 ms, it answered 9 (`SQLITE_INTERRUPT`), `sqlite3_errcode` 9, extended 9, message
   `"interrupted"`. `sqlite3_stmt_busy` then read 0, `sqlite3_reset` answered 9 again, and
   `sqlite3_finalize` after it answered 0. The same held under `NOMUTEX`.

   | ms from the interrupt call to the step's return | 3.53.1 | 3.45.1 |
   |---|---|---|
   | `FULLMUTEX` | 0.011 [0.004–0.107] | 0.005 [0.002–0.112] |
   | `NOMUTEX` | 0.089 [0.013–0.132] | 0.003 [0.002–0.021] |
   | **the `sqlite3_interrupt` call itself, µs,** during the step, `FULLMUTEX` | 0.59 [0.32–7.19] | 0.48 [0.34–5.38] |
   | the same, `NOMUTEX` | 0.60 [0.32–12.22] | 0.45 [0.31–0.63] |

2. **`sqlite3_is_interrupted`:** 0 on a fresh connection and after prepare; 0 just before the
   interrupt and 1 just after it, both while the step ran. **It still read 1 after the step
   returned, after the reset and after the finalize.** It went to 0 only when the next statement
   started: at its prepare, or at its first step when it had been prepared earlier (I1, I2).
3. **An interrupt while nothing runs is a no-op for what follows, but it sets the flag** (I2). Each
   of these read `is_interrupted` 1 after the interrupt, and then a new statement ran normally
   (`SQLITE_ROW`) and cleared it: a fresh connection that had prepared nothing (I2a); a statement
   prepared and not yet stepped (I2b); after a step and a reset, rerunning the same statement
   (I2c); after a finalize (I2d); and after a statement ran to `DONE` with no reset (I2e).
   **So an interrupt that lands between two statements is lost.** The next statement's start
   clears it, one prepared before the interrupt and not yet stepped included (I2b). The floor's
   `sqlite3.h` says the same (lines 2733 to 2735): an interrupt with no running statement "is a
   no-op and has no effect on SQL statements that are started after" it returns.
4. **A statement held at a row counts as running** (I3). With statement A stepped once and left at
   its row (`stmt_busy` 1), an interrupt made both `prepare("SELECT 2")` and `prepare("SELECT(2)")`
   answer 9 with a NULL statement, and made A's next step answer 9. A's reset answered 9. After
   that reset, a new statement and A itself each stepped to a row. The floor's source shows why: a
   statement start clears the flag only when `db->nVdbeActive == 0`. Both `sqlite3Step` and
   `sqlite3RunParser` do this, and the VDBE checks the flag on entry (`sqlite3.c` 3.45.1, lines
   90603, 177441 and 93417).
5. **A second statement started before the first is reset** (I4). If the interrupted S1 is the only
   active statement, its halt ends it, so S2 (`SELECT 1` and `SELECT(1)`) prepares and steps
   normally (I4a). **If another statement H holds a row, S2's prepare answers 9, and so does H's
   next step,** until H is finalized (I4b).
6. **Inside transactions** (I5). Table `t` holds 2000 committed rows. A trigger makes every row
   written cost a 100,000-row scan, so each write was still writing when interrupted at 100 ms.
   Each case first wrote a marker row inside the transaction.
   - **An interrupted INSERT, UPDATE or DELETE rolls the whole transaction back** before its step
     returns. The step answered 9, then `autocommit` read 1. The marker was gone, the 2000 rows
     unchanged, and `sum(y)` 0, from the same connection and a new one. COMMIT answered 1,
     `"cannot commit - no transaction is active"`, and ROLLBACK answered
     `"cannot rollback - no transaction is active"`.
   - **Savepoints go with it:** under `SAVEPOINT a`, a marker, then `SAVEPOINT b`, an interrupted
     UPDATE left `autocommit` 1. `ROLLBACK TO b` answered `"no such savepoint: b"`, `RELEASE a`
     answered `"no such savepoint: a"`, and the marker was gone.
   - **An interrupted SELECT leaves the transaction open.** After the marker write, `autocommit`
     read 0 and `txn_state` 2; COMMIT answered 101 and the marker persisted. In a transaction that
     had only read, `txn_state` stayed 1 and COMMIT answered 101.
   - **A statement journal doesn't change it.** The last two I5 cases drop trigger `ti`, then run
     BEGIN, a marker row and R, then an `INSERT INTO t(x, y) WITH RECURSIVE c(i) AS (…) SELECT
     abs(i), 1 FROM c`, a recursive CTE counting to 2×10⁹, interrupted at 100 ms. Calling `abs`
     gives the statement a statement journal (see below). It answered 9, extended 9, and
     `autocommit` read 1. The marker was gone and the 2000 rows unchanged. COMMIT answered
     `"cannot commit - no transaction is active"`. The same case with `SELECT i, 1` (no function)
     gave the same facts. Both libraries answered alike.
   - **Another statement R on the same connection,** stepped once before the interrupted one,
     answered 9 at its next step in every case. While it is active the flag stays set, so this run
     can't show whether the rollback also aborted it. **Every I5 case had R active,** the new
     ones too, so none shows an interrupted write with no other statement active.
   - **The source's rule** is in the floor's `sqlite3VdbeHalt` (`sqlite3.c` lines 87638 to
     87661). For a statement that reads a database (`bIsReader`), NOMEM, IOERR, INTERRUPT and
     FULL are "special" errors. A read-only statement interrupted needs no rollback (line 87651:
     `!p->readOnly || mrc!=SQLITE_INTERRUPT`), which is why an interrupted SELECT leaves the
     transaction open. Every other statement rolls back. NOMEM and FULL roll back only the
     statement when it has a statement journal (line 87652, `usesStmtJournal`). **INTERRUPT has
     no such branch,** so it ignores any statement journal: it calls `sqlite3RollbackAll` and
     `sqlite3CloseSavepoints` and sets `autoCommit = 1`, whatever the statement could have
     rolled back alone. A function call gives a statement a statement journal:
     `sqlite3VdbeAddFunctionCall` calls `sqlite3MayAbort` (line 84787), and the journal is used
     when the statement also writes more than one row (line 86980). The `abs` case shows the
     transaction ended all the same.
7. **An interrupt doesn't end a wait in the busy timeout** (I6). Each blocked call has a 600 ms
   busy timeout and is interrupted at 100 ms. Every call answered 5 (BUSY), extended 5, `"database
   is locked"`, at the timeout's end. `is_interrupted` then read 1, until the next statement
   cleared it. The calls:
   - I6a: BEGIN IMMEDIATE under another's BEGIN IMMEDIATE, rollback journal;
   - I6b: an autocommit INSERT under another's BEGIN IMMEDIATE;
   - I6c: BEGIN IMMEDIATE under another's in WAL mode;
   - I6d: a COMMIT under another connection's read, which left the transaction open: autocommit 0,
     `txn_state` 2. The COMMIT succeeded once the reader finalized;
   - I6e: a fresh connection's prepare under another's BEGIN EXCLUSIVE.

   | I6, ms from the call to its return | 3.53.1 | 3.45.1 |
   |---|---|---|
   | a | 601.17 [600.92–603.12] | 601.23 [601.14–601.75] |
   | b | 601.59 [601.15–601.72] | 601.26 [601.14–601.64] |
   | c | 601.10 [600.93–601.94] | 601.12 [601.03–601.41] |
   | d | 601.07 [600.88–601.35] | 601.03 [600.89–601.29] |
   | e | 601.02 [600.87–601.30] | 601.10 [600.97–601.28] |

   The floor's busy loop in `btreeBeginTrans`, and `sqliteDefaultBusyCallback`, never read the
   interrupt flag.
8. **An interrupt ends a long prepare** (I7). `prepare_v2` was given `"SELECT 1"` and 20,000,000
   empty comments, 100,000,008 bytes. Interrupted at 50 ms, it answered 9 with a NULL statement.
   `is_interrupted` then read 1, and `SELECT 1` afterwards stepped to a row. The tokenizer checks
   the flag on each whitespace token (`sqlite3RunParser`).

   | I7, ms | 3.53.1 | 3.45.1 |
   |---|---|---|
   | the prepare, not interrupted | 303.2 [288.4–311.0] | 286.8 [283.0–303.4] |
   | from the interrupt to the prepare's return | 3.64 [3.24–5.62] | 5.04 [4.57–6.03] |

9. **Under `FULLMUTEX`, another thread's `sqlite3_errmsg` waits for a running step; its
   `sqlite3_interrupt` doesn't** (I8). One thread called `sqlite3_errmsg` 100 ms into a long step,
   and another called `sqlite3_interrupt` at 300 ms. `errmsg` returned only after the interrupt
   was made, having waited 200.11 [199.96–200.25] ms on 3.53.1 and 200.12 [200.03–200.23] ms on
   3.45.1. The interrupt returned before the step did.

## A2. The busy timeout and contention ([busy.c](busy.c))

[busy-guix-3.53.1.txt](busy-guix-3.53.1.txt), [busy-floor-3.45.1.txt](busy-floor-3.45.1.txt);
timings in `busy-timing-…`. Each case uses two connections in one process on a temporary file. To
see whether a busy handler ran, a case installs a counting one with `sqlite3_busy_handler`. It
retries 3 times, sleeping 1 ms each, then gives up, so under a lock that is never released it is
called 4 times.

1. **`sqlite3_busy_timeout` and `PRAGMA busy_timeout` are one setting** (B1). A new connection
   reads 0. After `sqlite3_busy_timeout(db, 1234)`, the pragma reads 1234. `PRAGMA busy_timeout =
   4321` answers a row, `4321`, and reads back 4321. There is no C getter.
   - Installing a handler with `sqlite3_busy_handler` makes the pragma read 0.
   - Setting the pragma replaces that handler: the counter then saw 0 calls.
   - **`sqlite3_busy_timeout(db, 0)` and `(db, -1)` each removed a handler installed before.**
     For each, the counting handler was installed first, then the call answered 0 and the pragma
     read 0. A BEGIN IMMEDIATE under another's BEGIN IMMEDIATE then answered 5 (BUSY), extended
     5, with 0 handler calls. Both libraries, both values.
   - A second connection to the same file, and the first one reopened, read 0.
   - **The pragma never refuses a value.** Its row is what it applied:

   | `PRAGMA busy_timeout = …` | `-5` | `0` | `2147483647` | `2147483648` | `1.9` | `'250'` | `' 250'` | `abc` | `0x10` | `1e3` |
   |---|---|---|---|---|---|---|---|---|---|---|
   | its row, and the read-back | 0 | 0 | 2147483647 | 0 | 1 | 250 | 0 | 0 | 16 | 1 |

2. **No timeout, while c1 holds BEGIN IMMEDIATE and has written** (B2). This held in rollback
   journal and WAL alike:
   - c2's BEGIN IMMEDIATE, BEGIN EXCLUSIVE and autocommit INSERT each answered 5 (BUSY), extended
     5, and left c2 in autocommit;
   - c2's deferred BEGIN answered 101, and its SELECT read the 3 committed rows. Its first write
     answered 5, and **the transaction stayed open, `txn_state` 1;**
   - with the counting handler, BEGIN IMMEDIATE and the autocommit INSERT called it 4 times, but
     **the deferred transaction's write, its read transaction open, called it 0 times.** The
     floor's `btreeBeginTrans` (line 73667) invokes the handler only while
     `inTransaction == TRANS_NONE`.
3. **How long a blocked BEGIN IMMEDIATE waits before BUSY** (B3), with c1 holding the lock
   throughout. Every run answered 5, in ms:

   | Timeout | 3.53.1 | 3.45.1 | 3.45.1, `HAVE_NANOSLEEP=0` | the floor's source predicts: ms build, `HAVE_NANOSLEEP=0` |
   |---|---|---|---|---|
   | 0 | 0.001 [0.001–0.002] | 0.001 [0.001–0.002] | 0.001 [0.001–0.002] | 0; 0 |
   | 1 | 1.056 [1.054–1.068] | 1.055 [1.033–1.067] | 0.002 [0.001–0.003] | 1 sleep, 1; 0 |
   | 10 | 10.240 [10.202–10.250] | 10.237 [10.223–10.252] | 0.002 [0.002–0.087] | 4 sleeps, 10; 0 |
   | 50 | 50.483 [50.369–50.537] | 50.549 [50.399–50.728] | 0.001 [0.001–0.002] | 6 sleeps, 50; 0 |
   | 250 | 250.983 [250.868–251.095] | 250.946 [250.843–251.290] | 0.001 [0.001–0.002] | 12 sleeps, 250; 0 |
   | 1500 | 1502.508 [1501.975–1503.834] | 1502.064 [1501.851–1502.880] | 1000.094 [1000.074–1000.180] | 24 sleeps, 1500; 1 sleep, 1000 |
   | 250, set by the pragma | 251.222 [250.895–251.483] | 250.969 [250.840–251.407] | 0.001 [0.001–0.002] | as 250 |
   | 250, WAL | 251.156 [250.820–251.350] | 251.086 [250.766–251.157] | 0.000 [0.000–0.002] | as 250 |

   - **What decides the sleep's grain:** `sqliteDefaultBusyCallback` (`sqlite3.c` 3.45.1, lines
     179813 to 179854). When `SQLITE_OS_WIN || !defined(HAVE_NANOSLEEP) || HAVE_NANOSLEEP`, it
     sleeps on a schedule of 1, 2, 5, 10, 15, 20, 25, 25, 25, 50, 50, then 100 ms. It clips the
     last sleep so the total equals the timeout. Otherwise it sleeps whole seconds and gives up
     once `(count+1)*1000 > timeout`. So any timeout under 1000 ms answers BUSY at once, and 1500
     waits 1000.
   - `unixSleep` (lines 44810 to 44835) takes `nanosleep` unless `HAVE_NANOSLEEP` is 0, then
     `usleep` if `HAVE_USLEEP`, else `sleep`. **The build macros are `HAVE_NANOSLEEP` and
     `HAVE_USLEEP`.** In 3.45.1 the busy callback itself reads `HAVE_NANOSLEEP` alone.
     `SQLITE_ENABLE_SETLK_TIMEOUT` changes WAL's write lock to a blocking `fcntl` instead.
   - **Which applies:** `sqlite3_compileoption_get` lists neither macro, and neither library has
     `ENABLE_SETLK_TIMEOUT`, so only behaviour tells. Both libraries match the millisecond schedule
     to within 4 ms. The variant matches the whole-second rule exactly. So both libraries
     sleep in milliseconds. The floor gets that because CI compiles the amalgamation with no
     `HAVE_NANOSLEEP`, which counts as present.
4. **A4: an autocommit INSERT under another connection's read waits the timeout out and loses its
   row** (B3). Rollback journal, 1500 ms: every run answered 5, after 1502.359 [1501.761–1503.270] ms
   on 3.53.1 and 1501.886 [1501.571–1502.940] ms on 3.45.1, or 1000.393 [1000.188–1011.021] ms on
   the variant. The table kept 3 rows, and the connection was left in autocommit.
5. **WAL, a reader and a writer** (B4). A reader during a writer's open transaction stepped to a row
   and counted the 3 committed rows, not the writer's 4th. A writer during a reader's open
   transaction committed twice, autocommit and BEGIN IMMEDIATE, each answering 101. The reader
   still counted 4 until its COMMIT, then 6. A writer also committed while another statement held a
   row. In the rollback journal contrast, a reader during a writer's open transaction also read
   the committed rows.
6. **A deferred transaction that reads, then writes after another's commit** (B5, WAL). The write
   answered **517, `SQLITE_BUSY_SNAPSHOT`,** with the message `"database is locked"`. **The busy
   handler was called 0 times.** The transaction stayed open (`autocommit` 0, `txn_state` 1), still
   saw its old snapshot, and answered 517 again on a retried write. A new transaction's write
   succeeded. If c1's write is still open, c2's write answers 5 with 0 handler calls; after c1
   commits, it answers 517. With `sqlite3_busy_timeout(c2, 1500)` restored (the pragma read 1500),
   the waits were:

   | ms, busy timeout 1500 | 3.53.1 | 3.45.1 |
   |---|---|---|
   | the upgrade after another's commit, 517 | 0.003 [0.002–0.015] | 0.004 [0.002–0.008] |
   | the upgrade while another's write is open, 5 | 0.001 [0.001–0.001] | 0.001 [0.000–0.006] |

7. **BEGIN IMMEDIATE in the same race** (B6, WAL). c2's BEGIN IMMEDIATE answered 101, and c1's
   autocommit INSERT answered 5 after 4 handler calls. c2's write and COMMIT answered 101, and c1's
   retry then answered 101. If c1 commits first, c2's BEGIN IMMEDIATE sees c1's row. If c1 holds an
   open write, c2's BEGIN IMMEDIATE answers 5 after 4 handler calls and leaves c2 in autocommit.
   In the rollback journal contrast, with c2 in a deferred read, **c1's autocommit INSERT was the one
   to fail** (5, 4 calls, its row lost). c2's own write then succeeded.
8. **Rollback journal, a reader holding SHARED during a COMMIT** (B7):
   - COMMIT answered 5, extended 5. **The transaction stayed open:** `autocommit` 0, `txn_state` 2;
   - **while it is open, other connections can't start reading.** c3 had read before, and its
     SELECT answered 5. A new connection's prepare answered 5. The reader that already held SHARED
     stepped on (`SQLITE_ROW`);
   - a retried COMMIT called the counting handler 4 times and answered 5. Once the reader
     finalized, the retry answered 101, autocommit came back, and c3 counted 4 rows;
   - with a 250 ms busy timeout, COMMIT waited 250.862 [250.667–251.099] ms on 3.53.1 and 250.817
     [250.751–250.902] ms on 3.45.1, or 0.001 [0.001–0.002] ms on the variant;
   - an autocommit INSERT under the same reader answered 5 after 4 calls, and its row was lost.
9. **`PRAGMA journal_mode` on a file** (B8):
   - **set to WAL:** it answers a row, `wal`. A connection opened afterwards, and a new one after
     every connection closed, each read `wal`. The mode persists in the file;
   - **an idle connection that had already read the file read `delete`** until its next read, then
     `wal` (see the traps);
   - **inside a transaction:** `PRAGMA journal_mode=wal` answered no row and step 1 (ERROR),
     `"cannot change into wal mode from within a transaction"`. That held after a bare BEGIN
     (`txn_state` 0) and after a read (`txn_state` 1), and the transaction stayed open. Going out
     of WAL answered `"cannot change out of wal mode from within a transaction"`. A change between
     two non-WAL modes, to `truncate`, answered its row inside the transaction, and it stood after
     ROLLBACK;
   - **another connection holding a row, rollback journal:** setting WAL answered step 5 (BUSY),
     no row, and the mode stayed `delete`. It succeeded once the reader finalized;
   - **WAL back to `delete`, another connection open and idle:** this answered step 5. It
     succeeded once the other closed.
10. **`SQLITE_LOCKED` against `SQLITE_BUSY`** (B9). A statement on `t` held at a row:
    - **its own connection's `DROP TABLE t`, and `DROP TABLE u`, answered 6 (`SQLITE_LOCKED`),
      extended 6, `"database table is locked"`, with 0 handler calls.** With a 1500 ms busy
      timeout, the DROP answered in 0.054 [0.052–0.079] ms on 3.53.1 and 0.030 [0.025–0.043] ms on
      3.45.1;
    - that connection's `CREATE TABLE v` and `INSERT INTO t` succeeded, and once the reader
      finalized, `DROP TABLE u` did too;
    - **against another connection's read, the same DROP answered 5 (BUSY) after 4 handler
      calls.**
11. **A fresh connection's first statements under another's lock** (B10), with no busy timeout,
    each on a connection that has read nothing:
    - **under BEGIN EXCLUSIVE and a write:** `PRAGMA busy_timeout = 100` (row `100`), `PRAGMA
      foreign_keys = 1` and `PRAGMA foreign_keys` ran. `PRAGMA journal_mode`, `PRAGMA
      journal_mode=wal`, `PRAGMA synchronous` and `SELECT count(*) FROM t` answered 5 at prepare.
      `SELECT 1` differs between the libraries (above);
    - **under BEGIN IMMEDIATE and a write, or a statement holding a row:** everything ran, except
      that `PRAGMA journal_mode=wal` answered step 5;
    - **every BUSY here is extended 5 as well:** each prepare that answered 5 read extended 5
      (`sqlite3_extended_errcode`), and so did the `journal_mode=wal` step.
12. **A COMMIT while the connection's own statement is unfinished** (B11). One connection, no
    other: BEGIN, an `INSERT … RETURNING` stepped once (a row), then COMMIT answered 5 (BUSY),
    extended 5, `"cannot commit transaction - SQL statements in progress"`. **The transaction
    stayed open:** `autocommit` 0, `txn_state` 2. After the INSERT was finalized, COMMIT answered
    101, and the table kept the 4 rows. Both libraries alike.

## A3. Through Chez: this binding's architecture ([chez-interrupt.sps](chez-interrupt.sps))

[chez-interrupt-guix-3.53.1.txt](chez-interrupt-guix-3.53.1.txt),
[chez-interrupt-floor-3.45.1.txt](chez-interrupt-floor-3.45.1.txt); timings in
`chez-interrupt-timing-…`.
- **The owner,** a forked Chez thread, opens the connection and steps a `__collect_safe`
  `sqlite3_step` inside `critical-section`, as M2's verbs run it.
- **The main thread** waits 200 ms, then collects and allocates 1 MB. It then calls a plain
  `sqlite3_interrupt` on the owner's handle and waits up to 10 s for the owner's answer.
- **The owner closes only after the interrupt has been made,** so no interrupt reaches a closed
  connection.
- **Every wait is bounded,** and whatever the owner raises is its answer. **One isn't:** C1's
  `(collect)` and `(collect-rendezvous)` themselves have no bound. Each returned in every run,
  but a collection that never finished would hang the probe, which only its section's alarm ends.

1. **The interrupting thread runs, and collects, while the step is blocked** (C1, C2): with
   `(collect)` and with `(collect-rendezvous)`, in a long step and in a busy wait, 21 of 21 on
   both libraries. Each collection returned with the step still blocked, and `(collections)` rose
   by 1.
2. **A long step answers `SQLITE_INTERRUPT` promptly** (C1): 9, extended 9, `"interrupted"`. The
   finalize then answered 9.
3. **A step blocked in the busy timeout doesn't** (C2): 1000 ms timeout, interrupted 200 ms in. It
   answered 5, `"database is locked"`, at the timeout's end, and the finalize answered 5.
4. **A Chez timer doesn't count down during a foreign call** (C3). A 100,000-tick timer armed on
   the owner, outside any critical section, just before the step fired only after the step
   returned, 21 of 21. Its handler ran 0.714 ms after the step's return on 3.53.1 and 0.712 ms
   on 3.45.1. The control arms the same timer on a thread running a 200 ms loop of Scheme code:
   its handler ran 0.703 ms (3.53.1) and 0.742 ms (3.45.1) after arming, during the loop, 21 of
   21. So the same tick budget cost about 0.7 ms of Scheme code either way, and the 200 ms the
   step spent inside SQLite used none of it. The timer doesn't wait for the call and then fire:
   ticks don't elapse during it. **So neither an engine's fuel nor a timer can bound time spent
   inside SQLite.**

| ms | 3.53.1 | 3.45.1 |
|---|---|---|
| C1a `(collect)` during the long step | 0.050 [0.035–2.133] | 0.059 [0.041–3.288] |
| C1a interrupt to the step's return | 0.017 [0.012–0.021] | 0.013 [0.007–0.021] |
| C1b `(collect-rendezvous)` during the long step | 0.060 [0.049–0.101] | 0.063 [0.043–0.190] |
| C1b interrupt to the step's return | 0.017 [0.010–0.020] | 0.016 [0.006–0.076] |
| C2a `(collect)` during the busy wait | 0.065 [0.040–0.182] | 0.059 [0.047–0.312] |
| C2a interrupt to the step's return | 801.58 [801.35–802.04] | 801.76 [801.11–804.02] |
| C2a the whole step | 1001.90 [1001.60–1002.34] | 1002.13 [1001.58–1004.30] |
| C2b `(collect-rendezvous)` during the busy wait | 0.069 [0.046–0.131] | 0.066 [0.055–0.079] |
| C2b interrupt to the step's return | 801.73 [801.45–802.19] | 801.53 [801.26–802.36] |
| C3 the step's return to the timer handler | 0.714 [0.664–0.799] | 0.712 [0.693–0.795] |
| C3 control: arming to the handler, in Scheme code | 0.703 [0.662–1.044] | 0.742 [0.695–1.657] |

## A4. The sweep: claims about interrupt, busy and blocking

The rows below are SQLite behaviour that the brief's M3 line and §2.7, and ADR-0010, ADR-0011 and
ADR-0014, state as fact. Each row gives the claim's file:line and its status, measured on both
libraries unless it says otherwise. [sweep.c](sweep.c)'s outputs are
[sweep-guix-3.53.1.txt](sweep-guix-3.53.1.txt) and [sweep-floor-3.45.1.txt](sweep-floor-3.45.1.txt).

| Claim | Where | Status |
|---|---|---|
| "`foreign_keys` and `busy_timeout` reset with each connection" | brief:87–88 | **Measured now** (S1, B1): set on c1, a second connection and c1 reopened read 0 and 0. |
| "A PRAGMA's value can't be a bound parameter" | brief:88–89 | **Measured now** (S2): `PRAGMA busy_timeout = ?`, `= :ms`, `(?)`, `journal_mode = ?` and `foreign_keys = ?` answer 1 at prepare, `near "?": syntax error`. |
| "a setting is checked by reading its row back" | brief:90–91 | **Measured now** (S3, B1). `busy_timeout = 250` and `journal_mode = wal` answer a row; **`foreign_keys = 1` answers no row** (DONE), so it is read back by a second statement. **`foreign_keys = 1` inside a transaction is a silent no-op**: no row, and the read-back is 0. A busy timeout set inside a transaction takes effect. |
| "`journal_mode=wal` on a `:memory:` database answers `memory` while every call succeeds" | brief:91–92 | **Measured before** on 3.53.1 ([m1-plan](../../m1-plan/README.md), lines 24 to 31), which didn't reach the floor. **Measured now on both** (S4): `memory`, and open and close answered 0. A temporary database (filename `""`) answers `delete`. |
| "`sqlite3_interrupt` is the one call another thread may make" | brief:103; ADR-0010:43–44 | **Measured now:** it works from another thread under `FULLMUTEX` and `NOMUTEX` (I1, C1), and doesn't wait for the connection's mutex, where `sqlite3_errmsg` does (I8). |
| step, prepare and close "can wait on disk or sleep in the busy timeout"; exec "if bound" | brief:104 | **Step: measured now** (B3, I6, B7). **Prepare: measured before** ([m2-review](../../m2-review/README.md), item 15) and now (I6e, B10). **Close: measured now** (S5): it writes a checkpoint but never sleeps in the busy timeout. **Exec: measured now in C** (S6), though M2 doesn't bind it. `sqlite3_exec` of an INSERT under another connection's BEGIN IMMEDIATE, with a 250 ms busy timeout, answered 5, extended 5, `"database is locked"` (the out-parameter message and `sqlite3_errmsg` alike) after 250.895 [250.838–251.189] ms on 3.53.1 and 250.871 [250.782–251.103] ms on 3.45.1, 21 of 21, and the row was lost. Interrupted by another thread at 50 ms (the interrupt was sent while the exec ran), it answered the same, after 250.869 [250.717–251.233] ms and 250.902 [250.842–251.245] ms: **the interrupt didn't end the wait,** and `is_interrupted` then read 1. |
| "Two connections in WAL mode contending under a busy timeout" | brief:160–161 | A plan item, not a claim; measured now (B2 to B6). |
| "SQLite says it is unsafe on a connection that is closed, or might close before it returns" | ADR-0010:44–45 | **Confirmed in the text, not measurable:** both headers say "it is not safe to call this routine with a database connection that is closed or might close before sqlite3_interrupt() returns" (the floor's `sqlite3.h` lines 2712 to 2715; Guix's 2925 to 2928). Calling it so is undefined behaviour, so it isn't probed. |
| "in serialized mode another thread's error can land between a failed call and the read of its message" | ADR-0010:27–30 | **Not measurable here:** it needs one connection used from two threads, which ADR-0010 forbids. I8 measured the adjacent fact: under `FULLMUTEX` another thread's `sqlite3_errmsg` waits for a running step. |
| "`sqlite3_close` can write, a WAL checkpoint among other things" | ADR-0011:35 | **Measured now** (S5). The last connection's close after 1000 rows of 4000 bytes, with autocheckpoint off, grew the database file from 4096 to 4112384 bytes and removed the 4144752-byte WAL. With another connection open, idle or holding a row, the close left the WAL as it was, and the counting handler saw 0 calls. That close took 5.351 [4.797–13.970] ms on 3.53.1 and 6.014 [4.831–12.770] ms on 3.45.1. With the WAL truncated first, it took 0.039 [0.033–0.072] ms and 0.049 [0.029–0.096] ms. |
| "`sqlite3_prepare_v3` can read the schema from disk, and `sqlite3_step` can … sleep in the busy timeout" | ADR-0011:36–37 | Prepare **measured before** ([m2-review](../../m2-review/README.md), item 15); step **measured now** (B3). |
| "A plain `sqlite3_close` can't be made to block on demand" | ADR-0011:94–95 | **Measured now, consistent** (S5): no close waited on a lock or a busy handler; its time is the checkpoint's I/O. |
| reset and finalize waited 1502 ms with `busy_timeout = 1500` | ADR-0011:131–134; ADR-0014:35–36 | **Measured before** ([m2-review](../../m2-review/README.md), item 2). |
| a plain reset holds another thread's collection; a `__collect_safe` one doesn't | ADR-0011:135–143 | **Measured before** ([m2-review](../../m2-review/README.md), item 14). |
| a plain insert's step under another's read "expected to block the same way, not yet measured" | ADR-0011:148–149 | **Measured now** (B3, B7): it waits the timeout out, 1501.9 to 1502.4 ms median for 1500, answers 5, and loses its row. |
| a prepare blocks only on a fresh connection | ADR-0011:150–152 | **Measured before** ([m2-review](../../m2-review/README.md), item 15); again now (I6e). |
| "a `__collect_safe` open … holds even when the call sits inside `critical-section`" | ADR-0011:86–90 | Measured before for the open; **measured now for the step** (C1, C2). |
| a failed step's code is extended | ADR-0014:144–147 | **Consistent now:** with `EXRESCODE`, a step answered 517 itself (B5). |
| reset and finalize repeat a failed step's code | ADR-0014:151–152 | **Consistent now:** after a step answered 9, reset answered 9 (I1), and finalize with no reset answered 9 (C1). After a BUSY step, finalize answered 5 (C2). |
| prepare, step, reset and finalize "are `__collect_safe`, so other threads collect meanwhile" | ADR-0014:197–199 | **Measured now for the step** (C1, C2); reset measured before ([m2-review](../../m2-review/README.md), item 14). |
| "A blocking call holds its own thread's interrupts: … a keyboard interrupt, a timer or an engine's expiry waits too. Other threads run and collect." | ADR-0014:222–224 | **The timer: measured now** (C3, with its control), and it doesn't "wait" for the call: its ticks don't elapse during it, so the whole tick budget ran after the 200 ms step returned (0.714 ms after on 3.53.1, 0.712 ms on 3.45.1; the control, in Scheme code, 0.703 and 0.742 ms). Neither a timer nor an engine's fuel can bound time spent inside SQLite. **Other threads run and collect: measured now** (C1, C2). **The keyboard interrupt and an engine's expiry: not measured.** The first needs SIGINT delivered to the container's process; the second is built on the same timer, but wasn't run. |
| "M3's interrupt is how another thread stops a long one" | ADR-0014:224 | **Measured now, and only partly true:** see the next section. |
| "SQLite refuses a close when a backup reads from the connection, with `SQLITE_BUSY` and no statement open" | ADR-0012:165–166 | **Measured before** by M1 slice 4 ([its mutation log](../../../m1-slice-4-mutation-log.md), lines 66 to 68: after `sqlite3_backup_init`, `sqlite3_close` answered 5 with `next_stmt` finding none, and 0 after `sqlite3_backup_finish`). **Not re-measured here.** |
| "calls return extended codes" (`EXRESCODE`) | ADR-0013:19–20 | **Consistent now, and no sub-code to show.** A prepare that answered BUSY under another connection's lock (B10's cases) read extended 5 by `sqlite3_extended_errcode`, as did a step answering BUSY in B2's case (BEGIN IMMEDIATE and an autocommit INSERT: 5, extended 5). BUSY here has no sub-code, so extended and primary are the same number. Where a sub-code exists the call carried it: 517 from a step (B5), and M1's 2067 and 257 through `sqlite3_exec` ([mutation log](../../../m1-slice-4-mutation-log.md), lines 60 to 64). Both libraries alike. |

## The traps (`trap-*.c`)

Each trap is minimal and runs its case twice on fresh files. Both libraries gave the same output.

1. **[trap-interrupt-busy-wait.c](trap-interrupt-busy-wait.c): an interrupt doesn't end a busy
   wait.** With a 1000 ms timeout, interrupted at 100 ms, the call answered 5 after waiting the
   timeout out. The probe checks and prints that the interrupt was sent while the call was still
   running (yes, in both repetitions). `is_interrupted` then read 1 until the next statement.
2. **[trap-interrupt-sticks.c](trap-interrupt-sticks.c): an interrupt sticks while any statement
   holds a row.** Three new prepares in turn answered 9 `"interrupted"`. Resetting the held
   statement cleared it.
3. **[trap-interrupt-rollback.c](trap-interrupt-rollback.c): an interrupted write ends the
   transaction and its savepoints.** `ROLLBACK TO s` answered `"no such savepoint: s"`, and
   `ROLLBACK` answered `"cannot rollback - no transaction is active"`.
4. **[trap-deferred-upgrade.c](trap-deferred-upgrade.c): a busy timeout doesn't cover a read
   transaction's first write.** In rollback journal and WAL, with a 2000 ms timeout, c2's
   autocommit INSERT waited the timeout out and answered 5. After `BEGIN` and a read, its INSERT
   answered 5 at once, with the transaction left open. The setup's return codes are checked, and
   each run prints the `journal_mode` read on both connections: `delete` and `delete` in the
   rollback-journal runs, `wal` and `wal` in the WAL runs.
5. **[trap-journal-mode-stale.c](trap-journal-mode-stale.c): a connection's `PRAGMA journal_mode`
   can be stale.** After c1 set WAL, c2, which had read before, answered `delete`. After a read, it
   answered `wal`.

## Where this contradicts the records

- **ADR-0014:224,** in its consequences: "M3's interrupt is how another thread stops a long one."
  **The 2026-11-14 M2 plan, lines 155 to 156:** "this thread's interrupts wait for it, and M3's
  interrupt is how another thread stops a long one."
  - **Measured:** it stops a long-running step (I1, C1: 0.005 to 0.017 ms median) and a long
    prepare (I7: 3.6 to 5.0 ms).
  - **It doesn't stop a call waiting in the busy timeout.** BEGIN IMMEDIATE, an autocommit INSERT,
    a COMMIT and a fresh connection's prepare each waited the timeout out and answered BUSY: I6a to
    I6e, C2a and C2b, S6b (`sqlite3_exec`) and trap 1. The calls ADR-0011 names that wait in the
    busy handler are the ones the interrupt can't reach. ADR-0011's other waits weren't measured
    against an interrupt: its own example, an open blocked on a FIFO (ADR-0011:86), and
    `sqlite3_close`'s checkpoint, which is I/O (S5). Both wait outside the busy handler and run no
    statement. By I2, an interrupt with no statement running is discarded, so it isn't expected
    to reach them either; that is inferred, not measured.
- **Soft cases,** imprecise rather than wrong:
  - **ADR-0014:223,** "a timer or an engine's expiry waits too". A timer doesn't wait for the
    blocked call and then fire. Its ticks don't elapse during the call, and its whole budget ran
    after the call returned (C3). So neither can bound time spent inside SQLite.
  - **The brief, line 104,** lists close among the calls that "can … sleep in the busy timeout".
    S5 shows close didn't call the busy handler: with another connection's statement holding a
    row, a counting handler saw 0 calls on both libraries, though close does write.
  - **ADR-0010, line 22,** "each connection takes a mutex around every call". I8 shows
    `sqlite3_interrupt` and `sqlite3_is_interrupted` don't wait for it under `FULLMUTEX`, while
    `sqlite3_errmsg` does.
- No other record's text is contradicted. Rows above marked "measured now" confirm what they
  check. The brief's "checked by reading its row back" (§2.7, lines 90 to 91) is narrower in fact:
  `foreign_keys`' set form has no row (S3).

## Questions for M3's plan

1. **Interrupt against close.** SQLite calls `sqlite3_interrupt` unsafe on a connection that is
   closed or might close before it returns (ADR-0010:44–45; both headers). A3's probe kept it safe
   only by making the owner wait for the interrupter before closing. How does `close-database!`,
   on the owner's thread, exclude another thread's interrupt in flight? And what does an interrupt
   do on a closed `database` record?
2. **Does the interrupt promise to end a busy wait?** It can't (I6, C2, trap 1). Is the documented
   behaviour "a busy wait ends at its timeout, interrupt or not"? Or does M3 give interrupt and the
   busy timeout one story, such as short timeouts retried in Scheme, given that the brief's §4
   keeps callbacks, a busy handler among them, out of v1?
3. **What does "interrupted" mean afterwards?** The flag reads 1 after an interrupt that reached
   nothing (I2), and after the step returns, at a reset or a finalize, until the next statement
   starts (I1, I6). Does M3 export `sqlite3_is_interrupted`, and if so with what promise?
4. **Statements left active.** While any statement holds a row, an interrupt stays in effect, and
   every new prepare and step answers 9 until that statement is reset (I3, I4b, trap 2). What do
   the fold, `query` and D3's statement cache reset, and when? Does a cached statement return to
   the cache reset, so that none is left active?
5. **`with-transaction` after an interrupted write.** SQLite has already rolled the transaction and
   its savepoints back (I5, trap 3). ROLLBACK, ROLLBACK TO and RELEASE then answer errors. Does
   `with-transaction`'s rollback on a raise check `sqlite3_get_autocommit` first? And which
   condition reaches the caller: the interrupt, or the failed rollback?
6. **Deferred or immediate.** A transaction that has read gets BUSY at once on its first write
   under another writer, whatever the timeout. In WAL it gets 517 once the other has committed,
   and no retry of the statement can succeed (B2, B5, trap 4). Does `with-transaction` begin with
   BEGIN IMMEDIATE when it will write, or take a mode?
7. **What a busy failure means.** ADR-0013 classes `busy` and `locked` together as `&sqlite-busy`
   (ADR-0013:76, :132). But:
   - `SQLITE_LOCKED` (6) is the connection's own conflict, and no wait helps (B9);
   - BUSY from BEGIN IMMEDIATE or an autocommit write has already waited the timeout;
   - `SQLITE_BUSY_SNAPSHOT` (517) needs the transaction restarted.

   Does M3 retry any of them, and should the condition tell them apart by extended code? **The
   extended code can't tell the BUSY cases apart.** All of these answer 5, extended 5:
   - BUSY at once from deadlock avoidance (B2);
   - BUSY after waiting out the timeout (B3);
   - a COMMIT under another connection's read (B7);
   - a COMMIT while the connection's own `INSERT … RETURNING` is unfinished (B11).

   Only 517 (B5) and 6 (B9) differ.
8. **A COMMIT that answers BUSY.** In rollback-journal mode it leaves the transaction open, and
   blocks every other connection's new reads until it is retried or rolled back (B7). Does
   `with-transaction` retry it, roll back, or raise with the transaction still open?
9. **The settings list's values.** `PRAGMA busy_timeout` refuses nothing: `-5`, `2147483648`,
   `' 250'` and `abc` apply 0, `1e3` and `1.9` apply 1, and `0x10` applies 16 (B1). Is each value
   checked in Scheme as an exact integer in a range before it reaches SQL text? Does the read-back
   compare the row with the requested value? That comparison would catch `wal` answering `memory`,
   `delete` on a temporary database (S4), and a `foreign_keys` set inside a transaction (S3).
10. **The settings list's order and its locks.** A fresh connection can set `busy_timeout` and
    `foreign_keys` under another's EXCLUSIVE lock. `journal_mode` can't, and on 3.53.1 even
    `SELECT 1` can't (B10). Does open apply the busy timeout first, so that the settings after it
    wait under it? By `sqlite3_busy_timeout` or by the pragma? The C call can't be read back
    (B1). What does open do when `journal_mode=wal` answers BUSY because another connection is
    reading, or ERROR inside a transaction (B8)?
11. **Reading `journal_mode` from another connection.** A connection that read the file before
    another switched it to WAL answers `delete` until its next read (B8, trap 5). Do the settings
    and their tests read the mode only on the connection that set it?
12. **The busy wait's grain.** On a build with `HAVE_NANOSLEEP=0`, any timeout under 1000 ms
    answers BUSY at once, and 1500 waits 1000 (B3's variant). No compile option shows it. Do M3's
    tests assert a wait's length, and if so do they first check the grain, or use timeouts of a
    second or more? Apple's and Ubuntu's builds weren't measured here.
13. **What the interrupt verb may call.** Under `FULLMUTEX`, any call that takes the connection's
    mutex, such as `sqlite3_errmsg`, waits for a running step; `sqlite3_interrupt` and
    `sqlite3_is_interrupted` don't (I8). So does the verb call `sqlite3_interrupt` alone, bound
    plain, and read nothing else of the connection?
14. **A condition for interruption?** An interrupt answers 9 from a step or a prepare (I1, I7), and
    callers who asked for it will catch it. ADR-0013 makes subtypes "only for errors callers
    catch". Does M3 add one?
15. **No default busy timeout.** A new connection's is 0 (B1, S1). Does `open-database` set one,
    or leave it to the settings list?
16. **Preemption.** A timer's ticks don't elapse during a blocked call (C3), so neither a timer
    nor an engine's fuel can bound time spent inside SQLite; only another thread's interrupt ends
    a long step. Does M3 offer a deadline, a watchdog thread that interrupts, or leave that to
    callers?
17. **An interrupt that lands between statements is lost.** One that arrives while no statement
    is active is discarded when the next statement starts, a statement prepared before it and
    not yet stepped included (I2a to I2e; the floor's `sqlite3.h` lines 2733 to 2735). So an
    interrupt aimed at `execute!`'s script, at a `with-transaction` body, or at a cached
    statement's bind step is silently lost if it falls between two statements. (A statement
    held at a row counts as active, and the interrupt then sticks: I3.) How does a watchdog stop
    such work reliably?
18. **Is any wall-clock deadline possible other than another thread's interrupt?** Engines and
    timers can't bound time spent in SQLite (C3). Another thread's interrupt ends a long step
    and a long prepare (I1, I7), but not a busy wait (I6, S6b, C2, trap 1) nor a call between
    statements (I2). Nothing measured here bounds a busy wait except its own timeout.
