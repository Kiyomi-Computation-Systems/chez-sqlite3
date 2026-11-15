# What M3's slice 0 probes measured

Measured 2026-11-15 in the Guix container, for [the M3 plan](../../../2026-11-15-m3-plan.md)'s
probes P1, P2, P3, P7, P9 and P11 (its §8), after the maintainer's answers to Q1 to Q12. P10 isn't
needed, since Q8 is "Six". After the plan's adversarial review, the same day: P1's control, P1d,
and three probes the review measured first, P12, P13 and P14, written here in the research's form.
After its second review: P13b, the other values of the two PRAGMAs that expire statements.
Two libraries, as the rest of [M3's research](../README.md):

- **Guix's 3.53.1,** the container's own (`$GUIX_ENVIRONMENT/lib/libsqlite3.so.0`, its header in
  `$GUIX_ENVIRONMENT/include`);
- **the floor, 3.45.1** (`build/m3-floor/lib/libsqlite3.so.0`, its header in
  `build/m3-floor/include/`), CI's `floor` lane build of the pinned amalgamation, the same bytes
  as the research's (SHA-256 `a36320cba88bfe5b5ef7dad8b7525abfdeb8cda0f9296edbc6f70eb4f85af433`).

Every probe is C, compiled against its library's own header and linked to that library by path,
with an rpath. It refuses to run unless `sqlite3_libversion_number()` and `sqlite3_sourceid()`
equal the header's, and every output starts with both, read at run time. Every connection opens
as chez-sqlite3 opens one: `READWRITE | CREATE | EXRESCODE | FULLMUTEX` (ADR-0010). No call with a
side effect stands beside another call in one argument list: each answer is read into a variable
first (AGENTS.md).

## Running the probes

From the worktree's root, every probe on both libraries, into a fresh directory:

```
mkdir -p build/m3plan
scripts/guix-env sh -c 'd=$(mktemp -d build/m3plan/run.XXXXXX) && \
  sh .plans/research/m3-plan/slice-0/run.sh "$d" "$d/out"'
```

Name probes after `"$d/out"` to run only those, such as `p7-rollback-sticky`. A run takes about 8
minutes, most of it P2's and P12's busy waits.

**Each probe was run twice from fresh scratch on both libraries,** by the command above, twice
over:
- **before the review,** the first six, with scratch under `build/m3plan/final1.…` and
  `build/m3plan/final2.…`: all 12 outputs that aren't timings matched byte for byte. The
  comparison was watched failing twice: on a Guix output against its floor twin, and on a copy of
  `p9-begin-beside-read-guix-3.53.1.txt` with one line changed (`BEGIN 517` to `BEGIN 5`). A
  first planting missed: its `sed` named a line that held no match and changed nothing, and the
  comparison said "same". The plant was checked to have changed one line before it was compared
  again;
- **after it,** all nine, with scratch under `build/m3plan/p3final1.…` and
  `build/m3plan/p3final2.…`: all 18 outputs that aren't timings matched byte for byte. The
  comparison was watched failing again, on a Guix output against its floor twin, and on a copy of
  `p12-held-read-guix-3.53.1.txt` with one `(at once)` changed to `(waited)`, the plant checked to
  have changed one line. The outputs of P2, P3, P7, P9 and P11 were byte for byte the ones from
  before the review; P1's differed only by P1d's added lines.

- **after the second review,** all nine again, P13 with P13b, with scratch under
  `build/m3plan/p4final1.…` and `build/m3plan/p4final2.…`: all 18 outputs that aren't timings
  matched byte for byte. The comparison was watched failing again, on a Guix output against its
  floor twin, and on a copy of `p13-pragma-expire-guix-3.53.1.txt` with one `then 1` changed to
  `then 0`, the plant checked to have changed one line. Every output but P13's was byte for byte
  the one before; P13's differed only by P13b's added lines.

The files here are the last run.

| Probe | Measures | Outputs, per library |
|---|---|---|
| [run.sh](run.sh) | builds and runs the rest, on both libraries | |
| [p1-pragma-reuse.c](p1-pragma-reuse.c) | P1: a PRAGMA statement reset and stepped again, with no prepare | `p1-pragma-reuse-…` |
| [p2-settings-locks.c](p2-settings-locks.c) | P2: the six settings on a fresh connection under another's lock, with a busy timeout set first | `p2-settings-locks-…`, `p2-settings-locks-timing-…` |
| [p3-wait-release.c](p3-wait-release.c) | P3: a busy wait the other connection ends by letting go mid-wait | `p3-wait-release-…`, `p3-wait-release-timing-…` |
| [p7-rollback-sticky.c](p7-rollback-sticky.c) | P7: ending a transaction while an interrupt sticks behind a held row | `p7-rollback-sticky-…` |
| [p9-begin-beside-read.c](p9-begin-beside-read.c) | P9: `BEGIN` while the connection's own SELECT holds a read | `p9-begin-beside-read-…`, `p9-begin-beside-read-timing-…` |
| [p11-null-tail.c](p11-null-tail.c) | P11: what a prepare's tail leaves, a NULL statement's above all | `p11-null-tail-…` |
| [p12-held-read.c](p12-held-read.c) | P12: a write beside the connection's own held read | `p12-held-read-…`, `p12-held-read-timing-…` |
| [p13-pragma-expire.c](p13-pragma-expire.c) | P13: what a PRAGMA does to the other statements on its connection | `p13-pragma-expire-…` |
| [p14-wal-on-wal.c](p14-wal-on-wal.c) | P14: `journal_mode = wal` on a file already in WAL, beside each lock | `p14-wal-on-wal-…`, `p14-wal-on-wal-timing-…` |

Timings are distributions, min, median and max over the runs each case says. The machine is the
research's, an Intel Core Ultra 5 125H, shared. A timed case's facts tell a wait from none by
thresholds well clear of both: each wait measured 200.6 to 205.4 ms for a 200 ms timeout, and each
"at once" under 1 ms.

## P1. A PRAGMA statement reused ([p1-pragma-reuse.c](p1-pragma-reuse.c))

Alike on both libraries. For each of the six settings, `cache_size` and `user_version`, on a file
holding a table, with prepare flags 0 and `SQLITE_PREPARE_PERSISTENT`: S = `PRAGMA name = A`
prepared, stepped, reset; T = `PRAGMA name = B` run; S stepped again with no prepare.

1. **S's second step applied A again, in all 16 cases.** Read straight after, the value was A,
   and S's `SQLITE_STMTSTATUS_REPREPARE` count had gone from 0 to 1: SQLite re-prepared S at that
   step.
2. **Prepare and step, as before** (single P3): `foreign_keys`, `busy_timeout`, `synchronous`,
   `temp_store`, `trusted_schema` and `cache_size` changed when S was prepared, unstepped;
   `journal_mode` and `user_version` changed at its step.
3. **P1b: S re-prepares on its own.** Stepped twice with nothing between, each of the eight
   re-prepared at its second step, the count going from 0 to 1.
4. **P1c: a change no PRAGMA made.** With `busy_timeout` set to 100 by the C call
   `sqlite3_busy_timeout` between S's steps, S's second step re-prepared and read back 250.
5. **P1d, the control: a SELECT doesn't re-prepare.** `SELECT x FROM t`, stepped to done, reset
   and stepped again with nothing between, kept its re-prepare count at 0, with flags 0 and with
   `PERSISTENT`. So P1b's re-prepare is the PRAGMA's own.

So a statement cache can hold a PRAGMA statement like any other. It applied its setting again at
its second step, the one measured, and saved no prepare there.

## P2. The six settings under another's lock ([p2-settings-locks.c](p2-settings-locks.c))

Alike on both libraries. A fresh file in rollback-journal ("delete") or WAL mode; c1 holds a lock,
or none; c2 opens fresh, runs `PRAGMA busy_timeout = 200`, then one statement, timed. 7 runs a
case, 7 of 7 alike in every case.

| | delete: none | delete: read | delete: reserved | delete: exclusive | WAL: any lock, or none |
|---|---|---|---|---|---|
| `busy_timeout = 200`, first | ran | ran | ran | ran | ran |
| `foreign_keys`, `temp_store`, `trusted_schema`, `busy_timeout`: set and read | ran | ran | ran | ran | ran |
| `PRAGMA journal_mode`; `synchronous`, set and read; `SELECT count(*)` | ran | ran | ran | **prepare waited, then 5** | ran |
| `journal_mode = wal` (delete file) | `wal` | **step waited, then 5** | **step 5 at once** | **prepare waited, then 5** | — |
| `journal_mode = delete` (WAL file) | — | — | — | — | **step 5 at once,** even with c1 idle |

Each wait was 200.6 to 205.4 ms; each "ran" and "at once" under 1 ms
([p2-settings-locks-timing-guix-3.53.1.txt](p2-settings-locks-timing-guix-3.53.1.txt),
[p2-settings-locks-timing-floor-3.45.1.txt](p2-settings-locks-timing-floor-3.45.1.txt)).

- **Under an exclusive lock, the prepares that waited are the slow ones without a lock.** With
  no lock, `PRAGMA journal_mode`, both forms of `synchronous` and the SELECT took 0.02 to 0.16 ms
  to prepare, against 0.001 to 0.006 ms for the others, on both libraries: by that, they read the
  file, as a SELECT's prepare does. The reason in SQLite's source isn't read here. Concurrency B10
  measured the same statements with no timeout: BUSY at prepare.
- **Two refusals came at once, with the 200 ms timeout:** `journal_mode = wal` under a reserved lock,
  and leaving WAL while any other connection is open.
- **In WAL mode nothing else waited:** a reader or a writer blocks none of the six.

## P3. A wait ended by the other's release ([p3-wait-release.c](p3-wait-release.c))

Alike on both libraries. A holder thread takes a lock on its own connection and lets go after
150 ms; the main thread's fresh connection, with a 1500 ms busy timeout, makes the call. 21 runs a
case, 21 of 21 alike in every case.

| Case | The call | Answer | From the release to the call's return, ms: 3.53.1 | 3.45.1 |
|---|---|---|---|---|
| P3.1, WAL, c1 in `BEGIN IMMEDIATE` and a write, let go by `COMMIT` | `BEGIN IMMEDIATE` | done; then counts 4, seeing c1's row | 28.87 [28.67–29.85] | 28.68 [28.61–28.90] |
| P3.1, rollback journal, the same | `BEGIN IMMEDIATE` | done; then counts 4 | 29.09 [28.56–29.28] | 28.85 [28.58–29.03] |
| P3.2, rollback journal, c1 in `BEGIN` and a SELECT at its row | `PRAGMA journal_mode = wal` | row `wal` | 34.39 [32.18–38.07] | 34.65 [32.69–38.02] |
| P3.3, rollback journal, c1 in `BEGIN EXCLUSIVE` and a write | `PRAGMA journal_mode` | row `delete` | 28.70 [28.59–29.05] | 28.97 [28.64–29.14] |

- **Each wait ended after the release and before the timeout,** and the call succeeded. c1's
  `COMMIT` answered 0 in every run, so the waiter held nothing c1 needed.
- **It ended at the busy handler's next retry, not at the release.** The schedule concurrency B3
  read from the floor's source sleeps 1, 2, 5, 10, 15, 20, 25, 25, 25, 50 ms, so retries fall at
  103, 128 and 178 ms; a release at 150 ms is seen at 178 ms, 28 ms later. That is inferred from
  the schedule, not measured on its own.

## P7. Ending a transaction while an interrupt sticks ([p7-rollback-sticky.c](p7-rollback-sticky.c))

Alike on both libraries. A file holding 3 committed rows; inside a transaction a marker row, then
H = `SELECT x FROM t` stepped once and held; `sqlite3_interrupt`, while no step runs.

| Case | With H held at its row | After H's reset |
|---|---|---|
| P7.1 `BEGIN`, then `ROLLBACK` | prepare 9, no statement; autocommit 0 | ran; autocommit 1; the other counts 3 |
| P7.2 `BEGIN`, then `COMMIT` | prepare 9, no statement; autocommit 0; the other counts 3 | ran; autocommit 1; the other counts 4 |
| P7.3 `SAVEPOINT s` in `BEGIN`, then `ROLLBACK TO s` and `RELEASE s` | each prepare 9, no statement | each ran; autocommit 0 |
| P7.4 `ROLLBACK` prepared before the interrupt | its step 9, "interrupted"; its reset 9 | its step ran; autocommit 1 |

- **While a statement holds a row, every way of ending the transaction fails with
  `SQLITE_INTERRUPT`,** and the transaction stays open. Concurrency I3 measured it for `SELECT 2`;
  this confirms it for the statements `with-transaction` issues.
- **`sqlite3_is_interrupted` stayed 1 after H's reset,** until the next statement ran, which then
  ran normally and cleared it (concurrency I2).
- H's own reset answered 0: it hadn't been stepped since the interrupt.

## P9. `BEGIN` beside the connection's own read ([p9-begin-beside-read.c](p9-begin-beside-read.c))

Alike on both libraries. A file holding 3 committed rows; c1 holds `SELECT x FROM t` at its row
(autocommit 1); c2, with no busy timeout, inserts a row in autocommit, or does nothing; then c1,
with a 300 ms busy timeout, runs `BEGIN` in a mode, an INSERT and `COMMIT`. 11 runs a case, 11 of
11 alike in every case. Codes are extended.

| Journal, c2 | `BEGIN DEFERRED` | `BEGIN IMMEDIATE` or `BEGIN EXCLUSIVE` |
|---|---|---|
| WAL, c2 idle | 0; INSERT 0; `COMMIT` 0 | 0; INSERT 0; `COMMIT` 0 |
| WAL, after c2's commit (0) | 0, autocommit 0; **INSERT 517**; `COMMIT` 0 | **517 at once**, autocommit 1, no transaction begun; INSERT 517; `COMMIT` 1 |
| rollback journal, c2 idle | 0; INSERT 0; `COMMIT` 0 | 0; INSERT 0; `COMMIT` 0 |
| rollback journal, c2 tried (5, BUSY, beside c1's read) | 0; INSERT 0; `COMMIT` 0 | 0; INSERT 0; `COMMIT` 0 |

- **In WAL, a connection holding an old snapshot can't start a write transaction:** `BEGIN
  IMMEDIATE` and `BEGIN EXCLUSIVE` answered `SQLITE_BUSY_SNAPSHOT` at once, every `BEGIN` under
  1 ms, with a 300 ms busy timeout. With `BEGIN DEFERRED`, the first write answered it instead.
- **H went on answering rows** after every case, and finalized with 0.
- In rollback-journal mode, c1's read kept c2 from committing, so no newer snapshot arose.

## P11. What a prepare's tail leaves ([p11-null-tail.c](p11-null-tail.c))

Alike on both libraries, and alike by `sqlite3_prepare_v3` with flags 0 and by
`sqlite3_prepare_v2`.

- **A NULL statement came only when nothing but semicolons, whitespace and comments was left:**
  `;`, `;;`, ` ; `. Its tail was the input's end every time.
- **Leading semicolons and comments go into the next statement:** `;; select 2`, `; ;select 2`,
  `/* c */ ; select 2`, `-- c\n; select 2`, and U+FEFF then `; select 2`, each gave a statement whose
  `sqlite3_sql` is the whole input, the tail at its end. In
  `;;; -- c\n /* d */ ; select 2 ; select 3`, the first statement's text ran from byte 0 to its
  semicolon, and its tail was at byte 30.
- `select 1;; select 2` left its tail at byte 9, after the first semicolon, as `select 1; select
  2` does (ADR-0014's measurement).

So a script loop ends at its first NULL statement and never skips SQL by doing so.

## P12. A write beside the connection's own held read ([p12-held-read.c](p12-held-read.c))

Alike on both libraries. A fresh file holding 3 rows, in WAL or rollback-journal mode; c1 has a
1500 ms busy timeout. c2 holds `BEGIN IMMEDIATE` and an INSERT, unless c1 took the lock first. 5
runs a case, 5 of 5 alike in every case. Codes are extended
([p12-held-read-timing-guix-3.53.1.txt](p12-held-read-timing-guix-3.53.1.txt),
[p12-held-read-timing-floor-3.45.1.txt](p12-held-read-timing-floor-3.45.1.txt)).

| c1 holds | c1's call | WAL | rollback journal |
|---|---|---|---|
| nothing | `BEGIN IMMEDIATE` | 5, waited: 1501.7 to 1502.2 ms | 5, waited: 1501.8 to 1503.3 ms |
| its SELECT at a row | `BEGIN IMMEDIATE` | **5 at once**: 0.001 to 0.002 ms | **5 at once**: 0.001 to 0.004 ms |
| nothing | an autocommit INSERT | 5, waited: 1501.6 to 1502.2 ms | 5, waited: 1501.9 to 1502.5 ms |
| its SELECT at a row | an autocommit INSERT | **5 at once**: 0.002 to 0.003 ms | **5 at once**: 0.002 to 0.003 ms |
| `BEGIN IMMEDIATE`, then its SELECT at a row; c2 runs nothing | an INSERT | 0, at once | 0, at once |
| the same | `SAVEPOINT s`, an INSERT, `RELEASE s` | 0, at once | 0, at once |

The ranges are both libraries' min to max. Each held SELECT went on answering rows after the call,
and finalized with 0; each locked case committed with 0.

- **A connection's own held read defeats the busy timeout for its writes,** in both journal
  modes. The adversarial review of the plan measured it first, with 3 runs a case and the same
  facts.
- **A write lock taken before the read keeps writes and savepoints working beside it,** as a fold
  run inside `with-transaction` would have it.

## P13. What a PRAGMA does to the connection's other statements ([p13-pragma-expire.c](p13-pragma-expire.c))

Alike on both libraries. S = `SELECT x FROM t`, prepared `PERSISTENT`, stepped to done and reset;
then T; then S stepped again, its re-prepare count read before and after.

- **P13: `PRAGMA foreign_keys = 1` and `PRAGMA trusted_schema = 0` made S re-prepare at its next step,**
  its count going from 0 to 1, both with the value changed and with it already so.
- **P13b: so did every other value of the two.** `foreign_keys = 0` and `= off`, and
  `trusted_schema = 1`, each changed and each set to the value it already had, made S re-prepare
  at its next step. The plan's second review found the first of these with a probe of its own.
- **None of these did:** nothing, the control; `SELECT 1`; the set forms of `busy_timeout`,
  `journal_mode = wal`, `synchronous`, `temp_store` and `cache_size`, changed or not; and the read
  form of each of the six and of `cache_size`. Each left S's count at 0.

So any set of `foreign_keys` or `trusted_schema`, whatever its value, makes every statement a
cache holds re-prepare once at its next use. P1 measured that a PRAGMA statement re-prepares
itself at its reuse; this measures what it does to the others. The reviews measured the two that
expire first.

## P14. `journal_mode = wal` on a file already in WAL ([p14-wal-on-wal.c](p14-wal-on-wal.c))

Alike on both libraries. c1 holds nothing, a read, `BEGIN IMMEDIATE` and a write, or
`BEGIN EXCLUSIVE` and a write, on a WAL file; c2 opens fresh, sets a 200 ms busy timeout, then
`journal_mode = wal` and its read-back. 7 runs a case, 7 of 7 alike.

- **Beside every lock, the set answered a row, `wal`, and the read-back `wal`, each at once,**
  under 1 ms ([p14-wal-on-wal-timing-guix-3.53.1.txt](p14-wal-on-wal-timing-guix-3.53.1.txt),
  [p14-wal-on-wal-timing-floor-3.45.1.txt](p14-wal-on-wal-timing-floor-3.45.1.txt)).

So every connection to a WAL file can carry `(journal-mode . wal)` and open while the others
hold locks. P2's WAL column left this case out; the review measured it first, with 3 runs a case.

## Every difference between the two libraries

None, apart from the version lines and the timings, which agree within noise. Every output's lines
after the first two are identical between the libraries.

## Not measured

- **The busy wait's grain on CI's `main` lane library and on Apple's** (the plan's P4): measured
  by slice 6's rows on CI and by the Mac's hand run.
- **Valgrind on an interrupt of a closed connection** (P5): undefined behaviour, measured only as
  a planted copy in slice 6.
- **The engine rows and the library's cost** (P6, P8): slice 3's.
- **Why a PRAGMA statement re-prepares at every reuse:** P1 measured that it does, not the
  mechanism in SQLite's source.

## Where this contradicts the records

No accepted record. Two drafts of the M3 plan's, since fixed:
- **P12 against the plan's draft,** which said the conveniences hold no row and that Q5's default
  waits under contention. `query-fold`'s statement holds a read while its procedure runs, and
  beside such a read a write didn't wait (P12). The plan's §4.1, §4.2 and Q5's reason, and ADR-0016,
  ADR-0017 and ADR-0019, now say so, and the plan's Q14 settled what follows: `with-transaction`
  is refused beside a held row.
- **P13 adds to P1:** two PRAGMAs also expire the connection's other statements, which the plan's
  draft didn't account for in the cache or in reading its cost figures.

P7 confirms the plan's inference about the rollback's prepare. P1 resolves ADR-0020's
PRAGMA rule, drafted to wait on it: its first branch holds, and it is now that record's decision
8.
