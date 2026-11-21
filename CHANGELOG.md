# Changelog

All notable changes to chez-sqlite3 are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-20

The first release: SQLite for Chez Scheme, bound to SQLite's own C
library, which is found and loaded when a program starts. Nothing is
built: put the clone's `src` on Chez's library path.

### Added

- **Connections:** `open-database` and `call-with-database`, with the
  open's options and a settings list, and `close-database!`, which
  finalizes the connection's statements first. A connection belongs to
  the thread that opened it, and `interrupt-database!` may be called from
  any thread. See the [quick start](docs/quickstart.md) and the
  [reference](docs/reference.md#connections).
- **Statements and values:** prepare, bind, step, read columns, reset,
  clear bindings and finalize, with a statement cache per connection and
  `sql-null` for SQL's NULL ([Statements](docs/reference.md#statements),
  [Values](docs/reference.md#values)).
- **Conveniences:** `execute!`, `query`, `query-row`, `query-fold` and
  `execute-script!`, and the change counters
  ([Conveniences and counters](docs/reference.md#conveniences-and-counters)).
- **Transactions:** `with-transaction`, nested as savepoints, rolled back
  on a raise ([Transactions](docs/reference.md#transactions)).
- **Extensions and settings:** `load-extension!` behind an opt-in at
  open, and four of `sqlite3_db_config`'s settings
  ([Extensions](docs/reference.md#extensions)).
- **Finding SQLite:** a list of candidates for each system, or
  `CHEZ_SQLITE3_LIBRARY` to name one, and refusals that say what to do
  ([Finding SQLite](docs/finding-sqlite.md)).
- **Conditions:** one condition type for each kind of failure, with
  SQLite's code, message and SQL ([Conditions](docs/reference.md#conditions)).
- **The library:** SQLite's version, its compile options, and where it
  was loaded from ([The library](docs/reference.md#the-library)).

### Known limitations

- **Platforms:** the suites have run on Linux on x86_64 and on macOS 26
  on arm64. Linux on arm64, macOS on amd64, and macOS 14 and 15 have not
  run them. Windows is not supported.
- **Older systems** whose SQLite is below the floor in README.org's
  Requirements refuse it as `below-floor`, and need a newer one named by
  `CHEZ_SQLITE3_LIBRARY` ([who needs the override](docs/finding-sqlite.md#who-needs-the-override)).
- **What varies by library,** such as extension loading, defensive mode,
  full-text search and double-quoted words, is on
  [its page](docs/libraries.md).
- **Left out of this version:** anything SQLite calls back into Scheme,
  such as custom functions, aggregates, collations, hooks, authorizers
  and trace; and `sqlite3_config`, shared cache, the backup API,
  incremental blob I/O, sessions, serialize and unlock-notify.
- **Not prevented:** on a Mac, `DYLD_LIBRARY_PATH` can redirect the file
  an absolute path loads; `interrupt-database!` doesn't stop a busy wait;
  and `close-database!` is refused when something other than
  chez-sqlite3, such as an extension, left a statement open.

[Unreleased]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Kiyomi-Computation-Systems/chez-sqlite3/releases/tag/v0.1.0
