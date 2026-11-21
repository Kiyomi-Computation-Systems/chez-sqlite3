The first release: SQLite for Chez Scheme, bound to SQLite's own C
library, which is found and loaded the first time a program needs it.
Nothing is built: put the clone's `src` on Chez's library path.

### Added

- **Connections:** `open-database` and `call-with-database`, with the
  open's options and a settings list, and `close-database!`, which
  finalizes the connection's statements first. A connection belongs to
  the thread that opened it, and `interrupt-database!` may be called
  from any thread. See the [quick start](docs/quickstart.md) and the
  [reference](docs/reference.md#connections).
- **Statements and values:** prepare, bind, step, read columns, reset,
  clear bindings and finalize, and `sql-null` for SQL's NULL
  ([Statements](docs/reference.md#statements),
  [Values](docs/reference.md#values)).
- **Conveniences:** `execute!`, `query`, `query-row` and `query-fold`,
  each through a statement cache per connection; `execute-script!`,
  uncached; the counters `changes`, `total-changes` and
  `last-insert-rowid`; and `in-transaction?`
  ([Conveniences and counters](docs/reference.md#conveniences-and-counters)).
- **Transactions:** `with-transaction`, nested as savepoints, rolled
  back on a raise ([Transactions](docs/reference.md#transactions)).
- **Extensions:** `load-extension!`, behind an opt-in at open
  ([Extensions](docs/reference.md#extensions)).
- **Settings:** eleven, set as a connection opens, among them the busy
  timeout, the journal mode, the statement cache's size, and four of
  `sqlite3_db_config`'s: `enable-load-extension`, `defensive`,
  `dqs-dml` and `dqs-ddl` ([Settings](docs/reference.md#settings)).
- **Finding SQLite:** a list of candidates for each system, or
  `CHEZ_SQLITE3_LIBRARY` to name one, and refusals that say what to do
  ([Finding SQLite](docs/finding-sqlite.md)).
- **Conditions:** one condition type for each kind of failure, with
  SQLite's code, message and SQL
  ([Conditions](docs/reference.md#conditions)).
- **The library:** SQLite's version, its compile options, and where it
  was loaded from ([The library](docs/reference.md#the-library)).

### Known limitations

- **The API may change** in any release before 1.0.
- **Platforms:** the suites have run on Linux on x86_64 and on macOS 26
  on arm64. Linux on arm64, macOS on amd64, and macOS 14 and 15 have
  not run them. Windows is not supported.
- **Older systems:** chez-sqlite3 refuses a SQLite below the floor in
  README.org's Requirements as `below-floor`, as an older macOS's may
  be. Name a newer one with `CHEZ_SQLITE3_LIBRARY`, or, on Linux,
  install one where discovery looks before the file it refused
  ([when it is refused](docs/finding-sqlite.md#when-it-is-refused),
  [who needs the override](docs/finding-sqlite.md#who-needs-the-override)).
  Ubuntu 24.04's own `chezscheme` package is too old as well: build
  Chez from its source, or use Guix's or Homebrew's
  ([what you need](docs/quickstart.md#what-you-need)).
- **What varies by library,** such as extension loading, defensive
  mode, full-text search and double-quoted words, is on
  [its page](docs/libraries.md).
- **Left out of this version:** anything SQLite calls back into Scheme,
  such as custom functions, aggregates, collations, hooks, authorizers
  and trace; and `sqlite3_config`, shared cache, the backup API,
  incremental blob I/O, sessions, serialize and unlock-notify.
- **Engines:** `call-with-database`, `call-with-statement`,
  `with-transaction`, `query-fold` and `execute-script!` don't survive
  an engine's preemption; each one's entry says what to use instead
  ([`call-with-database`](docs/reference.md#call-with-database),
  [`call-with-statement`](docs/reference.md#call-with-statement),
  [`with-transaction`](docs/reference.md#with-transaction),
  [`query-fold`](docs/reference.md#query-fold),
  [`execute-script!`](docs/reference.md#execute-script)).
- **Not prevented:** on a Mac, `DYLD_LIBRARY_PATH` can redirect the
  file an absolute path loads; `interrupt-database!` doesn't stop a
  busy wait; and `close-database!` is refused when something other
  than chez-sqlite3, such as an extension, left a statement, a blob or
  a backup open. By then full-text tables have lost their unsaved
  changes, so roll back, never commit
  ([`close-database!`](docs/reference.md#close-database)).
- **The tests run from a clone,** not from a release's archive, which
  is no git repository
  ([the quick start](docs/quickstart.md#running-the-tests)).
