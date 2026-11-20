# What varies by library

chez-sqlite3 hands your SQL to the SQLite library it loaded, so a few
things depend on which library that is. This page lists each one seen
between the libraries the tests ran on. "The floor" is the oldest SQLite
[README.org's Requirements](../README.org) allow.

| Library | Ran on |
|---|---|
| Ubuntu 24.04's | Linux, x86_64 |
| SQLite's own, at the floor, built with its defaults | Linux, x86_64 |
| SQLite's own 3.54.1, built with FTS5, and again without extension loading | Linux, x86_64 |
| Guix's 3.53.1 | Linux, x86_64 |
| Apple's 3.51.0 | macOS 26, arm64 |
| Homebrew's 3.54.1 | macOS 26, arm64 |

## Extension loading

- **Apple's library has none,** nor the 3.54.1 built without it. There,
  an open that asks for `(enable-load-extension . #t)` raises a condition
  that `sqlite-extensions-unavailable?` holds, and nothing opens.
- **Ubuntu 24.04's library opens every connection with SQLite's own
  switch for loading already on.** The others measured that can load start
  it off. chez-sqlite3 doesn't rely on that switch: on every library,
  `load-extension!` refuses a connection that didn't opt in.
- **SQL's own `load_extension()` is refused,** as an `sqlite-error?`, code
  `error`: Apple's library has no such function, and every library that can
  load refuses to run it.

## Defensive mode

Apple's library starts `defensive` on, and the others measured start it
off. On, SQL can't write the schema itself: `PRAGMA writable_schema = 1`
runs, and does nothing. For one behaviour on every library, name the
setting: `(defensive . #t)` or `(defensive . #f)`.

## Full-text search

SQLite compiled from its source with no options leaves FTS5 out, as the
floor's build the tests use does. Ubuntu 24.04's,
Guix's, Apple's and Homebrew's have it, and so does SQLite's own 3.54.1,
built with it. Without it, `create virtual table ... using fts5` prepares,
then raises an `sqlite-error?`, code `error`, when it is stepped. So check
first, with [`sqlite-compile-option?`](reference.md#sqlite-compile-option).

## Double-quoted words

Every library measured starts `dqs-dml` and `dqs-ddl` on. Turned off, a
double-quoted word that names no column fails as the statement is
prepared, code `error`, on every library. SQLite's message for it differs
by version, so test the code, never the message:

| Library | The message for `select "no_such_column"` |
|---|---|
| Ubuntu 24.04's, and the floor's | `no such column: no_such_column` |
| Guix's, Apple's, Homebrew's, and 3.54.1 | `no such column: "no_such_column" - should this be a string literal in single-quotes?` |

## Out of memory in a transaction

When a statement runs out of memory, code `nomem`, whether its transaction
is still open depends on the statement, and on how the library was built,
not only on its version. An `insert ... select` that ran out left its
transaction open on Homebrew's library, which is built with
`ENABLE_MEMORY_MANAGEMENT`, and ended it on Guix's and on SQLite's own
built with its defaults. So after a `nomem`, ask
[`in-transaction?`](reference.md#in-transaction). `with-transaction` asks
for you, and rolls back only what is still there.

## Threads

Apple's library is built `THREADSAFE=2`, where the others are built
`THREADSAFE=1`. chez-sqlite3 opens every connection with SQLite's lock on
it, unless you give `no-mutex`, so a connection has one on both kinds.

## On a Mac

- **`load-extension!` retries a path with `.dylib` appended,** where Linux
  appends `.so`.
- **A failed load's message is the Mac's loader's,** worded otherwise than
  Linux's. It can be long, and SQLite cuts it at 298 bytes past the path's
  length.
- **`DYLD_LIBRARY_PATH` can load another file** in place of the one asked
  for, the SQLite library's and an extension's alike: see
  [Finding SQLite](finding-sqlite.md#dyld_library_path-on-a-mac).

## Running the tests on Apple's library

Apple's library keeps no count of SQLite's memory, has no extension
loading, and refuses `sqlite3_auto_extension`, a C call some tests use. So
`make test` there says which checks are unavailable, such as the memory
check and the out-of-memory rows, and passes on the rest. With Homebrew's
library, every check runs. Name its headers too, since the tests compile C
against the first `sqlite3.h` they find:

```sh
export CHEZ_SQLITE3_LIBRARY=/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib
export C_INCLUDE_PATH=/opt/homebrew/opt/sqlite/include
```
