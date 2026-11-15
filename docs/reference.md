# API reference

Every name `(chez-sqlite3)` exports, one entry each. Import it with
`(import (chez-sqlite3))`.

- [Connections](#connections)
- [Statements](#statements)
- [Values](#values)
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
Positive-Integer       an exact integer, 1 or more
Value                  an exact integer, a flonum, a string, a bytevector or sql-null
SqlNull                the one value sql-null
Bytevector             a bytevector
SqliteError            a condition that sqlite-error? holds
SqliteLibraryUnavailable  a condition that sqlite-library-unavailable? holds
SqliteWrongThread      a condition that sqlite-wrong-thread? holds
SqliteInvalidText      a condition that sqlite-invalid-text? holds
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
does. A raise reaches the caller unchanged. A normal return can still raise
the close's own failure, as a commit that was lost, and then you get no
answers. Its refusals are
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
columns from 0. Bind values to its parameters, and read its columns, with the
verbs in [Values](#values).

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

So do the copies of a value, which run byte by byte with this thread's
interrupts off: a `column-value` or `bind!` of 64 MiB takes about 2 seconds,
and a keyboard interrupt, a timer or an engine waits that long. Other threads
collect meanwhile.

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
a continuation. A raise reaches the caller unchanged. A normal return can
still raise the finalize's own failure, as a commit that was lost, and then
you get no answers.

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

## Values

A value is an exact integer, a flonum, a string, a bytevector or `sql-null`.
You bind one to a parameter, and read one from a column.

| You bind | SQLite stores it as |
|---|---|
| an exact integer from -2^63 to 2^63-1 | INTEGER |
| a flonum that is not a NaN, `+inf.0`, `-inf.0` and `-0.0` too | REAL |
| a string | TEXT, as its UTF-8 |
| a bytevector | BLOB, a copy of its bytes |
| `sql-null` | NULL |

Anything else is an assertion violation, and nothing is bound: an integer
outside 64 bits, `+nan.0`, `#t` and `#f` (write 1 and 0), and any other
object, such as `1/2` or a symbol. The condition names the value's kind, never
the value.

A parameter is a number from 1, or a name with its sigil exactly as the SQL
writes it, byte for byte and case-sensitive: `":a"`, `"@a"`, `"$a"`. `?5`
sits at index 5. A name used twice is one parameter. A number outside 1 to
`parameter-count`, a name the SQL does not have, and a name holding U+0000
are assertion violations too.

An empty string binds as TEXT and an empty bytevector as BLOB, never as NULL.
A string holding U+0000 is bound whole, but SQLite leaves SQL on such a
string undefined.

`bind!`, `bind-all!` and `clear-bindings!` need a ready statement: before the
first `step!`, or after `reset!`. `column-value` and `column-bytevector` need
a row. `column-name` works in every state but finalized. In any other state a
verb is an assertion violation, and the state is kept. A finalized statement
raises a condition that `sqlite-closed?` holds.

### `bind!`

```text
bind! : Statement (U Positive-Integer String) Value -> Void
```

Binds the value to one parameter, by number or by name.

SQLite can refuse a bind: a string or bytevector over its length limit raises
a condition that `sqlite-error?` holds, code `toobig`, with the statement's
SQL and no place. The parameter is then NULL, and the statement stays ready.

```scheme run
(call-with-database ":memory:"
  (lambda (db)
    (call-with-statement db "select :a, :a, ?3"
      (lambda (st)
        (bind! st ":a" 7)
        (bind! st 3 "hi")
        (step! st)
        (list (parameter-count st)
              (column-value st 0)
              (column-value st 1)
              (column-value st 2))))))
;; => (3 7 7 "hi")
```

### `bind-all!`

```text
bind-all! : Statement Value ... -> Void
```

Binds one value to each parameter, from 1 to `parameter-count`. It takes
exactly that many values, and checks the count and every value before it
binds any, so a refusal of ours binds nothing. If SQLite refuses one midway,
the ones before it stay bound.

```scheme run
(call-with-database ":memory:"
  (lambda (db)
    (call-with-statement db "select ?1, ?2, ?3"
      (lambda (st)
        (bind-all! st 42 (u8-list->bytevector (list 1 2)) sql-null)
        (step! st)
        (list (column-value st 0)
              (column-value st 1)
              (sql-null? (column-value st 2)))))))
;; => (42 #vu8(1 2) #t)
```

### `clear-bindings!`

```text
clear-bindings! : Statement -> Void
```

Makes every parameter NULL again. Only a ready statement allows it: before
the first `step!`, or after `reset!`.

```scheme run
(call-with-database ":memory:"
  (lambda (db)
    (call-with-statement db "select ?1"
      (lambda (st)
        (bind! st 1 5)
        (clear-bindings! st)
        (step! st)
        (sql-null? (column-value st 0))))))
;; => #t
```

### `column-value`

```text
column-value : Statement Natural -> Value
```

Reads a column of the row, counted from 0. You get what SQLite stored, never
the declared type: INTEGER is an exact integer, REAL a flonum, TEXT a string,
BLOB a fresh bytevector, and NULL is `sql-null`. A column declared `BOOLEAN`
holds 1 and 0, so it reads back 1 and 0. `-0.0` stored in a REAL column
reads back `0.0`.

TEXT that is not well-formed UTF-8 raises a condition that
`sqlite-invalid-text?` holds. `column-bytevector` reads its bytes instead.
A UTF-16 database converts its text to UTF-8 first, so this check guards UTF-8
databases.

A column number is checked against the column count each time you read, so a
column that another connection dropped is refused after the next `step!`.
A number outside 0 to `column-count` less 1, or not an exact integer, is an
assertion violation.

If SQLite runs out of memory during the read, it raises a condition that
`sqlite-error?` holds, code `nomem`, once, and the statement is failed:
reads and `step!` are refused until `reset!`. Inside a transaction, that
`reset!` or `finalize-statement!` may roll the transaction back.

```scheme run
(call-with-database ":memory:"
  (lambda (db)
    (call-with-statement db "select 1, 2.5, 'a', x'ff', null"
      (lambda (st)
        (step! st)
        (list (column-value st 0)
              (column-value st 1)
              (column-value st 2)
              (column-value st 3)
              (sql-null? (column-value st 4)))))))
;; => (1 2.5 "a" #vu8(255) #t)
```

### `column-bytevector`

```text
column-bytevector : Statement Natural -> (U Bytevector SqlNull)
```

Reads a TEXT or BLOB column as bytes, as a fresh bytevector. A TEXT column
gives its UTF-8 bytes undecoded, so it reads text that `column-value` refuses.
NULL gives `sql-null`. A value stored as INTEGER or REAL is an assertion
violation, whatever its column is declared: read it with `column-value`. Its column number and out-of-memory are
`column-value`'s.

```scheme run
(call-with-database ":memory:"
  (lambda (db)
    (call-with-statement db "select cast(x'61ff' as text)"
      (lambda (st)
        (step! st)
        (guard (e ((sqlite-invalid-text? e)
                   (list (sqlite-invalid-text-column e)
                         (sqlite-invalid-text-offset e)
                         (column-bytevector st 0))))
          (column-value st 0))))))
;; => (0 1 #vu8(97 255))
```

### `column-name`

```text
column-name : Statement Natural -> String
```

The name of a column, counted from 0, as SQLite gives it. It decodes strictly
too: a name that is not well-formed UTF-8 raises a condition that
`sqlite-invalid-text?` holds. If SQLite runs out of memory, it raises
`sqlite-error?` code `nomem`, and leaves the statement's state alone.

```scheme run
(call-with-database ":memory:"
  (lambda (db)
    (call-with-statement db "select 1 as one, 2 as two"
      (lambda (st)
        (list (column-name st 0) (column-name st 1))))))
;; => ("one" "two")
```

### `sql-null`

```text
sql-null : SqlNull
```

SQL's NULL. It is the one value of its kind, so `eq?` finds it. It is no
boolean, no empty list, and no `#f`.

### `sql-null?`

```text
sql-null? : Any -> Boolean
```

Whether the value is `sql-null`.

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

Everything this library raises on purpose is one of five conditions, and
each is a `chez-sqlite3-error?`. An `sqlite-error?` can also be a busy, a
constraint or a read-only one. Catch the family with it, or one kind with
its own predicate:

| Predicate | Raised when |
|---|---|
| `sqlite-library-unavailable?` | SQLite could not be loaded: not found, too old, not threadsafe, or missing a function. |
| `sqlite-error?` | SQLite answered with an error code. |
| `sqlite-busy?`, `sqlite-constraint?`, `sqlite-read-only?` | An `sqlite-error?` of one kind: see below. |
| `sqlite-wrong-thread?` | A connection, or a statement of one, is used by a thread that did not open it. |
| `sqlite-closed?` | A connection, or a statement, is used after it was closed or finalized. |
| `sqlite-invalid-text?` | TEXT, or a column's name, that is not well-formed UTF-8. |

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

Whether the value says a connection, or a statement of one, was used off its
thread.

### `sqlite-wrong-thread-owner`

```text
sqlite-wrong-thread-owner : SqliteWrongThread -> Natural
```

The id of the thread that opened the connection, which owns its statements
too.

### `sqlite-wrong-thread-caller`

```text
sqlite-wrong-thread-caller : SqliteWrongThread -> Natural
```

The id of the thread that used the connection or the statement.

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
while the connection's own write is unfinished, such as an
`insert … returning` that has answered a row, is `busy` too, and no wait
fixes it: `reset!` or finalize that statement first. A `select` mid-row
doesn't stop a `commit`.

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

### `sqlite-invalid-text?`

```text
sqlite-invalid-text? : Any -> Boolean
```

Whether the value says a TEXT column, or a column's name, is not well-formed
UTF-8. It is a `chez-sqlite3-error?`, but no `sqlite-error?`.

### `sqlite-invalid-text-column`

```text
sqlite-invalid-text-column : SqliteInvalidText -> Natural
```

The column, counted from 0.

### `sqlite-invalid-text-offset`

```text
sqlite-invalid-text-offset : SqliteInvalidText -> Natural
```

The byte offset, in the text's UTF-8, of its first ill-formed part.
