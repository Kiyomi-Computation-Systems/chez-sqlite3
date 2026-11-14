# chez-sqlite3: SQLite bindings for Chez Scheme — project brief

Date: 2026-11-13
Status: accepted 2026-11-13. §2 was settled by the maintainer on 2026-11-13. §3a, b, h and i
are now ADR-0001, ADR-0002, ADR-0004 and ADR-0006, all accepted. The rest of §3 becomes records
with the M1 and M2 plans. Where a record and this brief disagree, the record wins.
Background: [the Thunderchez assessment](chez-sqlite-thunderchez-assessment.org), which
audited Thunderchez's `sqlite3.sls` and recommended a project-owned library.
Consumers: Chez applications that want an embedded database, used the way the maintainer uses
SQLite elsewhere: long-lived connections in WAL mode, FTS5 and JSON, and the occasional
loadable extension.
Dependencies: SQLite ≥ 3.45.1, found and loaded at runtime (§2). Chez ≥ 10.4.0. No C shim
(§3).

Evidence, measured on the Linux development host on 2026-11-13:

- Chez 10.4.0, `ta6le`, `(threaded?)` → `#t`.
- Guix's SQLite 3.53.1, read through Chez's FFI: `THREADSAFE=1`, `ENABLE_FTS5`, and
  `sqlite3_load_extension` present. `sqlite3.h` is in the profile. Through the library,
  `jsonb('{}')` is a blob and an FTS5 table can be created. The first version of this brief read
  these options from the `sqlite3` command instead. That command carries its own copy of SQLite,
  with other options such as `DQS=0` (corrected in M0 slice 1; ADR-0006's amendment).
- The host's system `libsqlite3.so.0` is 3.37.2: `ENABLE_FTS5`, `ENABLE_JSON1`,
  `ENABLE_LOAD_EXTENSION`. Guix's Chez **cannot** load it by its soname
  (`libsqlite3.so.0: cannot open shared object file`), but loads it by absolute path. The
  assessment's loader, which names the soname alone, would fail here.
- `sqlite3_bind_double` with `+nan.0` returns `SQLITE_OK` and stores `NULL`.
- Chez's `utf8->string` replaces invalid bytes with U+FFFD without raising, and keeps an
  embedded NUL.

Not measured here: any macOS SQLite. The assessment reports `/usr/lib/libsqlite3.dylib` at
3.51.0 on the maintainer's Mac.

## 1. Goal

A small, safe binding that reads like a Scheme library, not like `sqlite3.h`, without hiding
what SQLite does.

```
   application: (call-with-database "app.db" settings
                  (lambda (db) (query db "select … where id = ?" 42)))
                               │
        ┌──────────────────────┴───────────────────────┐
        │  (chez-sqlite3)                              │
        │    conveniences: execute!, query, query-row, │
        │      fold, with-transaction (savepoints)     │
        │    statements: prepare, bind, step, columns, │
        │      reset, finalize                         │
        ├──────────────────────────────────────────────┤
        │  (chez-sqlite3 private …)                    │
        │    discovery, loading, foreign procedures,   │
        │    conditions, values, handles, counters     │
        └──────────────────────┬───────────────────────┘
                        libsqlite3 ≥ 3.45.1
```

One public library with two tiers. The statement tier is public from the start: bulk inserts
need prepared statements, and the conveniences are built on them. Nothing private escapes.

## 2. What is settled (the maintainer, 2026-11-13)

1. **The public library is `(chez-sqlite3)`;** internals live under
   `(chez-sqlite3 private …)`. The name avoids Thunderchez's `(sqlite3)`.
2. **The floor is SQLite 3.45.1,** Ubuntu 24.04's, and the first with JSONB. Discovery
   refuses an older library and says why. Ubuntu 22.04 (3.37.2) and Debian 12 (3.40.1) need the
   override. macOS 14 and 15 are believed to ship 3.43.x, so they'd need it too; M1 measures
   this on the Mac.
3. **Written fresh.** Thunderchez is a reference for API ideas only. None of its code is copied:
   it is Apache-2.0, and this project is BSD-3.
4. **The harness is a trimmed copy of chez-curl's** (the harness plan, M0). The memory gate has
   four parts: `sqlite3_memory_used` returns to its baseline; `sqlite3_next_stmt` finds no
   statement before a close; a counter of the library's own foreign allocations returns to zero;
   and Valgrind on Linux catches what the counters can't see.
5. **Loadable extensions are in v1, opt-in per connection.** Opting in turns on the C call
   alone (`SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION`), never SQL's `load_extension()`, so SQL text
   can never load a library. A library built without extension loading raises a named
   condition. Apple's system SQLite is believed to be one; M1 measures it.
6. **FTS5 and JSON are compiled in, not loaded.** Tests use both on every SQLite they run
   against, and a compile-option query (`sqlite3_compileoption_used`) is exported so an
   application can check at startup.
7. **PRAGMAs are SQL.** They run through the ordinary statement path. Opening a connection
   also takes a checked list of per-connection settings, run on every open, because
   `foreign_keys` and `busy_timeout` reset with each connection. A PRAGMA's value can't be a
   bound parameter, so each name and value is validated before it reaches SQL text.
8. **`sqlite3_config` stays out:** it is process-wide and legal only before SQLite
   initialises. `sqlite3_db_config` is reached through a few named, checked options:
   extension loading, defensive mode, double-quoted strings.

## 3. Proposed, for decision records in M0

| # | Proposal | Precedent |
|---|---|---|
| a | **No C shim.** Foreign procedures bind libsqlite3 directly. The one variadic call we need, `sqlite3_db_config`, is bound with Chez 10's `(__varargs_after n)`. Constants are Scheme definitions, checked against `sqlite3.h` by a C program compiled at test time: the compiler is a test oracle, never an install dependency. `SQLITE_TRANSIENT` is `(void*)-1`. | chez-curl ADR-0001 |
| b | **Runtime discovery.** An override (`CHEZ_SQLITE3_LIBRARY`), else one candidate list per world (Guix, the system, macOS), loaded once by absolute path. Discovery is a pure function tested on synthetic listings; a failure carries a reason symbol. | chez-curl ADR-0002 |
| c | **A connection belongs to the thread that opened it.** A verb called from another thread raises `&sqlite-wrong-thread`. `sqlite3_interrupt` is the one call another thread may make. | chez-curl ADR-0012, chez-libuv ADR-0019 |
| d | **Calls that can block are `__collect_safe`:** `sqlite3_step`, `sqlite3_prepare_v3`, `sqlite3_exec` if bound, and `sqlite3_close`. They can wait on disk or sleep in the busy timeout, and a blocked call would otherwise hold every other thread's collection. Their arguments are copies in foreign memory, never Scheme objects. | chez-curl ADR-0013, chez-libuv ADR-0009 |
| e | **Closing is explicit, with no guardians.** `open-database` and `close-database!` are public; `call-with-database` wraps them. A connection tracks its statements, and closing it finalizes them, then calls `sqlite3_close`, not `close_v2`, so a leak fails loudly instead of leaving a half-closed connection. A closed handle refuses every verb. | chez-libuv ADR-0007 |
| f | **Values.** INTEGER ↔ exact integer; binding one outside 64 bits raises. REAL ↔ flonum. TEXT ↔ string, read by byte length so an embedded NUL survives. BLOB ↔ bytevector. NULL ↔ a distinct `sql-null`. Parameters are 1-based, as in SQLite, or named with their sigil (`:name`). No type is guessed from a column's declared type. | the assessment |
| g | **Errors are condition types.** A base `&sqlite-error` carries the primary code, the extended code, the message, the SQL, and the error offset. Codes are symbols. Subtypes exist only for errors callers catch: busy/locked, constraint, read-only. Connections open with `SQLITE_OPEN_EXRESCODE`. | chez-curl ADR-0022, chez-libuv ADR-0006 |
| h | **Windows is not supported.** | chez-curl ADR-0004 |
| i | **Builds and tests run in a pinned, toolchain-only Guix container with no network.** | chez-curl ADR-0006 |

## 4. Scope

In v1:

- Opening with `sqlite3_open_v2`: read-only, read-write, create, URI, memory, no-follow,
  extended codes. Closing. The settings list (§2.7).
- Statements: prepare (`sqlite3_prepare_v3`), bind, step, column values and names, reset,
  clear bindings, finalize. The statement count per connection.
- Conveniences: `execute!`, `query`, `query-row`, a fold, `with-transaction` with nested
  savepoints, and rollback on a raise.
- `sqlite3_changes64`, `sqlite3_last_insert_rowid`, `sqlite3_total_changes64`, the busy timeout,
  `sqlite3_interrupt`.
- `sqlite3_libversion`, compile-option queries, loadable extensions (§2.5), the named
  `db_config` options (§2.8).

Out of v1:

- Anything SQLite calls back into Scheme: custom functions and aggregates, collations, commit,
  update and progress hooks, authorizers, trace. Each needs a `foreign-callable` design that
  obeys §3d's rule for callbacks.
- `sqlite3_config`, shared cache, the backup API, incremental blob I/O, sessions,
  serialize/deserialize, unlock-notify.

## 5. Open questions

| # | Question | Leaning |
|---|---|---|
| D1 | Is a threaded Chez required, as in chez-curl? | **Settled 2026-11-13: required** (ADR-0001's amendment). The counters need a mutex. |
| D2 | The connection's mutex mode under §3c: `NOMUTEX` (one thread uses it anyway) or `FULLMUTEX` (defence if our check has a gap). | `FULLMUTEX`; the cost is small. |
| D3 | A per-connection cache of prepared statements for `query` and `execute!`, as Python's `sqlite3` keeps. | v1, in M3, bounded and cleared by close. |
| D4 | Binding `+nan.0`: SQLite stores NULL without complaint (measured). | Refuse it with a condition. |
| D5 | Binding `#t` and `#f`. | Refuse them: 1 in, 1 out is asymmetric. Callers pass 1 or 0. |
| D6 | TEXT that isn't valid UTF-8: `utf8->string` replaces bytes silently (measured). | Raise a named condition; a column can always be read as bytes instead. |
| D7 | macOS versions and extension loading on Apple's SQLite. | Measure on the Mac in M1. |

## 6. Milestones

- **M0, the harness.** Trimmed from chez-curl, by [the harness
  plan](2026-11-13-harness-plan.md): the decision records, the ledger and the global
  constraints, the Guix container, the Makefile, SRFI-64 from vendored chez-srfi, the suite
  checks and the pin checks, the counters, the Valgrind gate, and Linux CI's `main`, `memory`
  and `nothreads` jobs.
- **M1, loading.** Discovery, the floor check, conditions, open and close, the settings list,
  `sqlite3_libversion`, compile options. SQLite's two memory checks join the gate; the `floor`
  and `current` CI lanes arrive. The Mac measurements (D7).
- **M2, statements and values.** Prepare, bind, step, columns, reset, finalize, statement
  tracking, §3f's mapping, §3g's conditions.
- **M3, the conveniences.** `execute!`, `query`, `query-row`, the fold, transactions and
  savepoints, the busy timeout, interrupt, the change counters, the statement cache (D3). Two
  connections in WAL mode contending under a busy timeout.
- **M4, extensions and `db_config`.** Loadable extensions opt-in, defensive mode, DQS. FTS5
  and JSON suites.
- **M5, the release.** `/docs` finished, README, CHANGELOG, 0.1.0. `docs/reference.md` grows
  from M1's first export on (the harness plan, §4).

## 7. The test instrument

- **No network.** Tests use `:memory:` databases and temporary files in a directory of the
  process's own, under `$TMPDIR` (ADR-0007, amended): fixed paths under `build/` collided when
  two runs shared a tree.
- **Every suite checks the gate** (§2.4) around what it opens.
- **Three SQLites in CI.** `main` loads the runner's own through discovery; on
  `ubuntu-24.04` that is 3.45.1, the floor (M0 verifies this). `floor` and `current` compile
  SQLite's amalgamation, a single C file, at 3.45.1 and at a pinned current release, each
  checked against a pinned checksum, and load it through the override. Locally, the Guix
  container gives what its pin gives, measured in M0.
- **Build differences are tested, not assumed.** Builds differ in their compile options, and the
  `sqlite3` command can differ from the library beside it, so a library's options are read
  through the FFI. No test may depend on an option it hasn't checked; double-quoted string
  literals (`DQS`) are one example.
