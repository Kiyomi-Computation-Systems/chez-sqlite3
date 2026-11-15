# API reference

Every name `(chez-sqlite3)` exports, one entry each. Import it with
`(import (chez-sqlite3))`.

- [Connections](#connections)
- [Statements](#statements)
- [The library](#the-library)
- [Conditions](#conditions)

Types are written as Typed Racket writes them: `(U a b)` is either one,
`a -> b` is a procedure, `A ...` is any number more, `(Listof a)` is a list,
and `#f` is false. These names stand for:

```text
Database               a connection, made by open-database
Statement              a prepared statement, made by prepare-statement
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
`read-write` or `create`. So is a name that is not a string, or one that
holds U+0000.

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

Closing finalizes the connection's live statements first, oldest first. If
one of those finalizes failed, the connection is closed all the same, and
the first failure is raised after.

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
continuation, and its live statements are finalized as `close-database!`
does. A raise reaches the caller unchanged. Its refusals are
`open-database`'s: a name that is not a string or holds U+0000, and a bad
option, are assertion violations, and nothing is opened.

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
fuel leaves the procedure, and the connection is closed under it. If that
close fails, its error is raised out of the engine, and the engine is
lost. If you use engines, use `open-database` and close it yourself.

### `database?`

```text
database? : Any -> Boolean
```

Whether the value is a connection, open or closed.

```scheme run
(list (database? 'x) (call-with-database ":memory:" database?))
;; => (#f #t)
```

## Statements

A statement is one piece of SQL, prepared on a connection. It belongs to that
connection and to the thread that owns it. Parameters count from 1 and
columns from 0.

A statement is always in one state. `prepare-statement` and `reset!` leave it
ready. `step!` leaves it on a row, done, or failed. Only `reset!` takes a
done or failed statement back to ready: `step!` on one is an assertion
violation, and the state is kept.

SQL holds exactly one statement. SQL that holds none, such as `""`, or more
than one, is an assertion violation. The first of two is prepared before the
second is found, so its effect stands: after
`pragma cache_size = 7; select 1` is refused, the cache size is 7. SQL that
holds U+0000, or is longer than 2^31-2 bytes of UTF-8, is an assertion
violation too, and nothing is prepared.

A statement that is finalized, or whose connection is closed, refuses every
verb but `finalize-statement!` with a condition that `sqlite-closed?` holds,
and a second `finalize-statement!` does nothing. Used from a thread that does
not own its connection, a statement raises a wrong-thread condition.

Prepare, step, reset and finalize can wait in SQLite's busy handler. Other
threads collect meanwhile, but this thread's interrupts wait.

### `prepare-statement`

```text
prepare-statement : Database String -> Statement
```

Prepares the SQL on the connection, and gives the statement, ready. It stays
the connection's until it is finalized. If SQLite refuses the SQL, it raises
a condition that `sqlite-error?` holds, with the SQL and, where SQLite names
one, the place.

```scheme run
(call-with-database ":memory:"
  (lambda (db)
    (let ((st (prepare-statement db "select ?1, ?2")))
      (let ((n (parameter-count st)))
        (finalize-statement! st)
        n))))
;; => 2
```

```scheme run
(call-with-database ":memory:"
  (lambda (db)
    (guard (e ((assertion-violation? e) 'refused))
      (prepare-statement db "select 1; select 2"))))
;; => refused
```

### `finalize-statement!`

```text
finalize-statement! : Statement -> Void
```

Finalizes the statement, in any state, and frees it. A second finalize does
nothing. It raises a condition that `sqlite-error?` holds when the finalize
fails on its own, as when the commit of an `insert ... returning` that was
stepped once is lost. The statement is finalized all the same.

### `call-with-statement`

```text
call-with-statement : Database String (Statement -> A ...) -> A ...
```

Prepares the SQL as `prepare-statement` does, calls the procedure, last of
the arguments, with the statement, and gives the procedure's answers. The
statement is finalized when the procedure returns, raises, or leaves through
a continuation. A raise reaches the caller unchanged.

```scheme run
(call-with-database ":memory:"
  (lambda (db)
    (call-with-statement db "select 1, 2"
      (lambda (st)
        (let* ((row (step! st))
               (columns (column-count st))
               (done (step! st)))
          (list row columns done))))))
;; => (#t 2 #f)
```

It does not survive an engine's preemption: an engine that runs out of fuel
leaves the procedure, and the statement is finalized under it. If you use
engines, use `prepare-statement` and finalize it yourself.

### `statement?`

```text
statement? : Any -> Boolean
```

Whether the value is a statement, finalized or not.

### `statement-sql`

```text
statement-sql : Statement -> String
```

The SQL the statement was prepared from. Each call gives a fresh copy.

### `parameter-count`

```text
parameter-count : Statement -> Natural
```

The statement's largest parameter index: 2 for `select ?1, ?2`, and 0 for
a statement with none.

### `step!`

```text
step! : Statement -> Boolean
```

Runs the statement to its next row. It gives `#t` when a row is ready, and
`#f` when the statement is done. When SQLite fails, the statement is failed,
and it raises a condition that `sqlite-error?` holds, with the statement's
SQL and no place.

```scheme run
(call-with-database ":memory:"
  (lambda (db)
    (call-with-statement db "select 1"
      (lambda (st)
        (let* ((first (step! st))
               (second (step! st)))
          (reset! st)
          (list first second (step! st)))))))
;; => (#t #f #t)
```

### `reset!`

```text
reset! : Statement -> Void
```

Rewinds the statement, ready again, with the values bound to it kept. A
statement that is done or failed needs this before it steps again. It raises
a condition that `sqlite-error?` holds when the reset fails on its own, as
a finalize can. The statement is ready all the same. A step that failed
raised already, and its reset does not raise it again.

### `column-count`

```text
column-count : Statement -> Natural
```

How many columns the statement's rows have: 0 for a statement that gives
none, such as a `create table`. It is read afresh at each call. After an
`alter table` on any connection, its own included, a held `select *` still
answers the old count until its next `step!`, then the new one.

## The library

These report on the SQLite library that was found and loaded. The load runs
once, when the first of them, or `open-database` or `call-with-database`, is
first used. If no library can be loaded, the load raises a condition that
`sqlite-library-unavailable?` holds.

That load runs when your program starts, or when the form that names one of
those procedures is evaluated: before any `guard` in that form is in place.
So a `guard` around a direct call cannot catch it, and the program dies. To
catch it, call through `eval` inside the `guard`, which needs `(rnrs eval)`:

```scheme
(guard (e ((sqlite-library-unavailable? e) 'no-sqlite))
  (eval '(sqlite-version) (environment '(chez-sqlite3))))
```

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
(> (sqlite-version-number) 3000000)
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
`SQLITE_` prefix or not, and any case. A name that is not a string, or one
that holds U+0000, is an assertion violation.

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
each is a `chez-sqlite3-error?`. An `sqlite-error?` can also be a busy, a
constraint or a read-only one. Catch the family with it, or one kind with
its own predicate:

| Predicate | Raised when |
|---|---|
| `sqlite-library-unavailable?` | SQLite could not be loaded: not found, too old, not threadsafe, or missing a function. |
| `sqlite-error?` | SQLite answered with an error code. |
| `sqlite-busy?`, `sqlite-constraint?`, `sqlite-read-only?` | An `sqlite-error?` of one kind: see below. |
| `sqlite-wrong-thread?` | A connection is used by a thread that did not open it. |
| `sqlite-closed?` | A connection, or a statement, is used after it was closed or finalized. |

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

Where in the SQL SQLite found the error, as a character index into
`sqlite-error-sql`, or `#f` when it gives none. It gives none for an error at
the end of the SQL, nor for some errors in the middle, such as a missing
table. Only a failed prepare has one, `prepare-statement`'s or
`call-with-statement`'s; a failed step, reset or finalize has none.

### `sqlite-library-unavailable?`

```text
sqlite-library-unavailable? : Any -> Boolean
```

Whether the value says SQLite could not be loaded. It loads nothing itself,
so naming it starts no load. Use it in a `guard` around an `eval` of the call
that loads, as [The library](#the-library) shows.

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

More about the reason, by reason:

- `invalid-override`: the bad value of `CHEZ_SQLITE3_LIBRARY`.
- `load-failed`: the loader's message. Or, when SQLite loaded but misbehaved,
  the name of the function that answered NULL, or the code
  `sqlite3_initialize` answered instead of OK.
- `below-floor`: the version found.
- `not-threadsafe`: `0`, what `sqlite3_threadsafe` answered.
- `missing-api`: the name of the missing function.
- `not-found`: `#f`.

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

Whether the value says a connection was used after it was closed, or a
statement after it was finalized or its connection was closed.

### `sqlite-busy?`

```text
sqlite-busy? : Any -> Boolean
```

Whether the value is an `sqlite-error?` whose primary code is `busy` or
`locked`: another connection holds what this one needs. A `commit` refused
while the connection's own statement is mid-row is `busy` too, and no wait
fixes it: `reset!` or finalize that statement first.

### `sqlite-constraint?`

```text
sqlite-constraint? : Any -> Boolean
```

Whether the value is an `sqlite-error?` whose primary code is `constraint`,
as a unique or not-null violation.

### `sqlite-read-only?`

```text
sqlite-read-only? : Any -> Boolean
```

Whether the value is an `sqlite-error?` whose primary code is `readonly`:
the database cannot be written.
