# API reference

Every name `(chez-sqlite3)` exports, one entry each. Import it with
`(import (chez-sqlite3))`.

- [Connections](#connections)
- [The library](#the-library)
- [Conditions](#conditions)

Types are written as Typed Racket writes them: `(U a b)` is either one,
`a -> b` is a procedure, `A ...` is any number more, `(Listof a)` is a list,
and `#f` is false. These names stand for:

```text
Database               a connection, made by open-database
Void                   no useful value
Natural                an exact integer, 0 or more
SqliteError            a condition that sqlite-error? holds
SqliteLibraryUnavailable  a condition that sqlite-library-unavailable? holds
SqliteWrongThread      a condition that sqlite-wrong-thread? holds
```

A code block marked `scheme run` is run by the tests, and its last line says
what it gives.

## Connections

A connection belongs to the thread that opened it. Any other thread that
uses it gets a wrong-thread condition. Nothing closes a connection for you:
close it, or open it with `call-with-database`.

### `open-database`

```text
open-database : String Symbol ... -> Database
```

Opens the database file named by the string, and gives its connection. Each
symbol after the name is an option, given at most once, in any order.

| Option | What it does |
|---|---|
| `read-only` | Opens for reading only. |
| `read-write` | Opens for reading and writing. The file must exist. |
| `create` | Opens for reading and writing, and creates the file if it is missing. |
| `uri` | Reads the name as a URI. |
| `memory` | Opens a database in memory. |
| `no-follow` | Refuses a name that is a symbolic link. |
| `no-mutex` | Skips SQLite's lock on the connection. Only one thread may ever use it, as always. |

With no mode option, you get `read-write` and `create`. `read-write` alone
does not create the file. `read-only` cannot be given with `read-write` or
`create`.

Three mistakes are assertion violations, and nothing is opened: an option
that is not in the table, an option given twice, and `read-only` with
`read-write` or `create`. So is a name that is not a string.

A name that starts with `file:` is a URI, so it needs the `uri` option, and
is refused without it. To open a file really named `file:x.db`, write
`./file:x.db`.

```scheme run
(guard (e ((assertion-violation? e) 'refused))
  (open-database "file:x.db"))
;; => refused
```

```scheme
(open-database "app.db")                          ; read-write, creating
(open-database "app.db" 'read-only)
(open-database "file:app.db?mode=ro" 'uri 'read-only)
(open-database "./file:x.db")                     ; a file named file:x.db
```

When SQLite cannot open the file, it raises a condition that
`sqlite-error?` holds, and leaves nothing open.

```scheme run
(guard (e ((sqlite-error? e) (sqlite-error-code e)))
  (open-database "/no/such/directory/app.db" 'read-only))
;; => cantopen
```

### `close-database!`

```text
close-database! : Database -> Void
```

Closes the connection. A second close does nothing. Once closed, a
connection refuses every other verb with a condition that `sqlite-closed?`
holds. Closing from another thread raises a wrong-thread condition, closed
or not.

```scheme run
(let ((db (open-database ":memory:")))
  (close-database! db)
  (close-database! db)
  (database? db))
;; => #t
```

### `call-with-database`

```text
call-with-database : String Symbol ... (Database -> A ...) -> A ...
```

Opens a database as `open-database` does, calls the procedure, last of the
arguments, with the connection, and gives the procedure's answers. The
connection is closed when the procedure returns, raises, or leaves through a
continuation. A raise reaches the caller unchanged.

```scheme run
(call-with-database ":memory:" (lambda (db) (database? db)))
;; => #t
```

```scheme run
(guard (e ((symbol? e) e))
  (call-with-database ":memory:" (lambda (db) (raise 'boom))))
;; => boom
```

It does not survive an engine's preemption: an engine that runs out of
fuel leaves the procedure, and the connection is closed under it. If you
use engines, use `open-database` and close it yourself.

### `database?`

```text
database? : Any -> Boolean
```

Whether the value is a connection, open or closed.

```scheme run
(list (database? 'x) (call-with-database ":memory:" database?))
;; => (#f #t)
```

## The library

These report on the SQLite library that was found and loaded. The first one
you call loads it. If none can be loaded, it raises a condition that
`sqlite-library-unavailable?` holds.

### `sqlite-version`

```text
sqlite-version : -> String
```

The library's version, as `"3.53.1"`.

### `sqlite-version-number`

```text
sqlite-version-number : -> Natural
```

The version as one number: 3.53.1 is `3053001`.

```scheme run
(>= (sqlite-version-number) 3045001)
;; => #t
```

### `sqlite-source-id`

```text
sqlite-source-id : -> String
```

The library's source id: its date and check-in hash.

### `sqlite-library-path`

```text
sqlite-library-path : -> String
```

The absolute path the library was loaded from.

### `sqlite-library-source`

```text
sqlite-library-source : -> Symbol
```

Where that path came from, such as `override` for `CHEZ_SQLITE3_LIBRARY`.

### `sqlite-compile-option?`

```text
sqlite-compile-option? : String -> Boolean
```

Whether the library was compiled with the option. The name may have its
`SQLITE_` prefix or not, and any case. A name that is not a string is an
assertion violation.

```scheme run
(sqlite-compile-option? "THREADSAFE")
;; => #t
```

### `sqlite-compile-options`

```text
sqlite-compile-options : -> (Listof String)
```

Every option the library was compiled with, as SQLite lists them. Each call
gives a fresh list.

## Conditions

Everything this library raises on purpose is one of four conditions, and
each is a `chez-sqlite3-error?`. Catch the family with it, or one kind with
its own predicate:

| Predicate | Raised when |
|---|---|
| `sqlite-library-unavailable?` | SQLite could not be loaded: not found, too old, not threadsafe, or missing a function. |
| `sqlite-error?` | SQLite answered with an error code. |
| `sqlite-wrong-thread?` | A connection is used by a thread that did not open it. |
| `sqlite-closed?` | A connection is used after it was closed. |

A caller's mistake is not one of these. A name that is not a string, a bad
option, a value that is not a connection, or an accessor given the wrong
kind of condition is an assertion violation, the usual `&assertion`
condition of Scheme. Test for it with `assertion-violation?`.

Each accessor takes the condition its predicate holds, and refuses
anything else with an assertion violation.

### `chez-sqlite3-error?`

```text
chez-sqlite3-error? : Any -> Boolean
```

Whether the value is any condition of this library.

```scheme run
(list (chez-sqlite3-error? 'x)
      (guard (e ((chez-sqlite3-error? e) (sqlite-error? e)))
        (open-database "/no/such/directory/app.db" 'read-only)))
;; => (#f #t)
```

### `sqlite-error?`

```text
sqlite-error? : Any -> Boolean
```

Whether the value is SQLite's answer of an error code.

### `sqlite-error-code`

```text
sqlite-error-code : SqliteError -> (U Symbol Integer)
```

The primary result code's name: SQLite's C name without `SQLITE_`, in lower
case, with `-` for `_`, as `cantopen` or `busy`. It is the integer when the
name is unknown.

### `sqlite-error-extended-code`

```text
sqlite-error-extended-code : SqliteError -> (U Symbol Integer)
```

The extended result code, named the same way. A code with no extension is its
own.

### `sqlite-error-message`

```text
sqlite-error-message : SqliteError -> String
```

SQLite's own text for the error.

### `sqlite-error-sql`

```text
sqlite-error-sql : SqliteError -> (U String #f)
```

The SQL text the error came from, or `#f` when it came from no statement,
as an open does.

### `sqlite-error-offset`

```text
sqlite-error-offset : SqliteError -> (U Natural #f)
```

Where in the SQL SQLite found the error, or `#f` when it gives none.

### `sqlite-library-unavailable?`

```text
sqlite-library-unavailable? : Any -> Boolean
```

Whether the value says SQLite could not be loaded. It loads nothing itself,
so a program can use it to test for a missing library.

### `sqlite-library-unavailable-reason`

```text
sqlite-library-unavailable-reason : SqliteLibraryUnavailable -> Symbol
```

Why: one of `invalid-override`, `not-found`, `load-failed`, `below-floor`,
`not-threadsafe` or `missing-api`.

### `sqlite-library-unavailable-path`

```text
sqlite-library-unavailable-path : SqliteLibraryUnavailable -> (U String #f)
```

The path of the library that was refused, or `#f` when none was chosen.

### `sqlite-library-unavailable-source`

```text
sqlite-library-unavailable-source : SqliteLibraryUnavailable -> (U Symbol #f)
```

Where that path came from, or `#f` when there is none.

### `sqlite-library-unavailable-detail`

```text
sqlite-library-unavailable-detail : SqliteLibraryUnavailable -> Any
```

More about the reason: the bad override, the loader's message, the version
found, or the name of the missing function. It is `#f` for `not-found`.

### `sqlite-library-unavailable-candidates`

```text
sqlite-library-unavailable-candidates : SqliteLibraryUnavailable -> (Listof String)
```

Every path that was looked at, in order, for `not-found`.

### `sqlite-wrong-thread?`

```text
sqlite-wrong-thread? : Any -> Boolean
```

Whether the value says a connection was used off its thread.

### `sqlite-wrong-thread-owner`

```text
sqlite-wrong-thread-owner : SqliteWrongThread -> Natural
```

The id of the thread that opened the connection.

### `sqlite-wrong-thread-caller`

```text
sqlite-wrong-thread-caller : SqliteWrongThread -> Natural
```

The id of the thread that used it.

### `sqlite-closed?`

```text
sqlite-closed? : Any -> Boolean
```

Whether the value says a connection was used after it was closed.
