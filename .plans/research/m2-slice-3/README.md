# M2 slice 3: what statements were measured to do

Probes behind M2 slice 3 (statements) and its records. Each was run on Guix's 3.53.1 and at the
floor, 3.45.1. Unless a line says otherwise, the two libraries agree, except for a millisecond or
two of timing. Every output begins with the version it loaded.

Run a Scheme probe from the worktree root:

```sh
scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m2-slice-3/PROBE.sps'
```

For the floor, add `CHEZ_SQLITE3_LIBRARY=$PWD/build/m2s1-floor/libsqlite3-floor.so`. The
builder's probes, `probe-*.sps`, reach the raw bindings; the rest go through the statement
library.

## Blocking calls ([probe-block.sps](probe-block.sps))

Another connection holds a read, the busy timeout is 1500 ms, and each call is bound both plain
and `__collect_safe`:

| Call | Answer | Waited | Another thread's collection, plain | `__collect_safe` |
|---|---|---|---|---|
| step of a plain `insert` | 5, "database is locked" | 1502 ms | 1402 ms, ending after the call | 0 to 1 ms |
| prepare, on a fresh connection under `begin exclusive` | 5 | 1502 ms | 1402 ms | 0 ms |
| reset of an `insert … returning` stepped once | 5 | 1502 ms | 1402 ms | 0 ms |
| finalize of the same | 5, the statement freed | 1502 ms | 1402 ms | 0 ms |

The step's block was expected and unmeasured until now (ADR-0011's M2 amendment). After it, the
finalize answers 5 again, and the table keeps its one row.

## The close ([probe-close.sps](probe-close.sps))

- **With M2's entry points, nothing makes `sqlite3_close` fail once every statement is
  finalized.** SQLite's close names unfinalized statements, backups and BLOB handles, and M2 binds
  none of the last two. A backup reading from the connection makes the close answer 5, and 0 once
  it is finished.
- **Two inserts stepped once under a read:** whichever is finalized second answers 5, in either
  order. So the failure's SQL shows which statement the close finalized last.

## Codes and offsets ([probe-codes.sps](probe-codes.sps))

- **A unique violation** steps 2067. Then reset answers 2067, a second reset 0, and the finalize 0.
- **A read-only connection's insert** prepares (0), steps 8, and finalizes 8.
- **Prepare answers extended codes:** 257 for a missing collation.
- **SQLite's −1 offset:** for an error at the end of the SQL (`select 1 +`, `select (`), a missing
  table, a missing collation, and a busy prepare. Each is the same on a connection's first prepare
  and on a used one. Offsets otherwise: 10 for `select 1, nosuchcol`; 13 bytes, character 12, for
  `select 'é', nosuchcol`; 0 for `selectx 1`.
- **Counts:** `select :a, ?7, $b` has 8 parameters and 3 columns, and `create table u (a, b)` has
  0 columns.

## The tail oracle's cost ([probe-cost.sps](probe-cost.sps))

2,000 pairs of prepares took 3 ms plainly and 323 ms under Valgrind. That sized
`test-statement-tail`'s 20,602 inputs: 0.4 s plainly, about 21 s under the gate. The probe printed
no file of its own; the numbers are the builder's.

## A trigger's message ([feff-errmsg.sps](feff-errmsg.sps))

`RAISE(ABORT, '\xFEFF;boom')` in a trigger reached the raised `&sqlite-error`'s message as
`"boom"`: M1's `c-string->string` decoded it with `utf8->string`, which drops a leading U+FEFF. A
message can be the user's own text, so the slice's review fixes restore it.
[feff-errmsg-guix-3.53.1.txt](feff-errmsg-guix-3.53.1.txt) is the run before that fix.

## Two findings of M3's research, reproduced here ([m3-items.sps](m3-items.sps))

The M1 session found these while measuring M3's ground on 2026-11-15. This probe reproduces them
through the statement library:

- **A held statement's column count changes at its next step, after an `ALTER TABLE` on any
  connection, its own included:** a held `select *` read 2 before the ALTER, 2 after it, and 3
  after its step. ADR-0014's context had another connection only.
- **COMMIT answers `busy`** ("cannot commit transaction - SQL statements in progress") while the
  connection's own `insert … returning` has answered a row and isn't finished. No wait fixes it.

## An interrupt doesn't end a lock wait ([interrupt-wait.c](interrupt-wait.c))

Also from M3's research, reproduced here in C, since M2 binds no `sqlite3_interrupt`:

- `begin immediate`, under another connection's exclusive lock with a 600 ms busy timeout, and
  interrupted at 100 ms, still waited 601 ms, then answered 5, `is_interrupted` left at 1.
- A long computation, interrupted at 100 ms, answered 9 at 100 ms.

So an interrupt stops a long computation, and a lock wait ends only at its timeout.

```sh
scripts/guix-env sh -c '$CC -O1 -Wall -Werror -pthread -I$GUIX_ENVIRONMENT/include \
    -o build/iw .plans/research/m2-slice-3/interrupt-wait.c \
    $GUIX_ENVIRONMENT/lib/libsqlite3.so.0 -Wl,-rpath,$GUIX_ENVIRONMENT/lib && build/iw build/iw.db'
```

## A column read's NOMEM inside a transaction ([colnomem-transaction.c](colnomem-transaction.c), [colnomem-no-table.c](colnomem-no-table.c))

The M1 session's probes, from M3's research, rerun here unchanged on both libraries. Each takes
a scratch directory as its argument. The heap limit is in force for the one column call:

- **BEGIN, a marker row inserted, then `select hex(x) from src`** over a 100,000-byte blob, stepped
  once. `sqlite3_column_text16` answers NULL with 7. Then `sqlite3_reset` answers 7, autocommit
  becomes 1, and the marker row is gone: the transaction was rolled back. A finalize in place of
  the reset does the same.
- **The control, `select ?1`,** which reads no table: the reset answers 7, autocommit stays 0,
  and the marker survives.

By the floor's `sqlite3VdbeHalt`, a reset or finalize halts the statement with its NOMEM. A
statement that reads a database and has no statement journal then rolls back everything, and a
SELECT has none.

## COMMIT and the connection's own statements ([commit-busy.sps](commit-busy.sps))

Added in M2 slice 4, to correct slice 3's "mid-row". Run on both libraries
([commit-busy-guix-3.53.1.txt](commit-busy-guix-3.53.1.txt),
[commit-busy-floor-3.45.1.txt](commit-busy-floor-3.45.1.txt)):

- **Inside BEGIN, with a SELECT on the same connection stepped to a row,** COMMIT succeeds. The
  step answers done, and a ROLLBACK after it finds no transaction.
- **With an `insert … returning` stepped once and unfinished,** COMMIT answers `busy`, "cannot
  commit transaction - SQL statements in progress".
