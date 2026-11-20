# Quick start

From a clone to a first query.

## What you need

A Chez Scheme built with threads, and SQLite's library, `libsqlite3`, at
the versions [README.org's Requirements](../README.org) name. A program
needs nothing else: no compiler, and no build step.

## Get it

```sh
git clone https://github.com/Kiyomi-Computation-Systems/chez-sqlite3.git
```

There is nothing to build. chez-sqlite3 is Scheme source, and it loads
SQLite's library when your program runs. `src/` holds the library you
import, `(chez-sqlite3)`.

## Put it on the library path

Put `src` on Chez's library path, and run your program:

```sh
scheme --libdirs chez-sqlite3/src --program app.sps
```

Homebrew installs Chez as `chez`: on a Mac with Homebrew's Chez, type
`chez` where these pages type `scheme`.

## A first program

Save this as `app.sps`, beside the clone:

```scheme
(import (rnrs) (chez-sqlite3))

(write
 (call-with-database ":memory:"
   (lambda (db)
     (execute! db "create table pets (name text, legs integer)")
     (execute! db "insert into pets values (?, ?)" "cat" 4)
     (execute! db "insert into pets values (?, ?)" "bird" 2)
     (query db "select name, legs from pets order by legs"))))
(newline)
```

Run it with the command above. It prints:

```text
(#("bird" 2) #("cat" 4))
```

- `call-with-database` opens the database, here one in memory, hands its
  connection to your procedure, and closes it after.
- `execute!` runs SQL. The values after the SQL fill its `?` marks, in
  order.
- `query` gives every row, each a vector of its values.

The examples on these pages leave out the `import` and the `write`. A
block marked `scheme run` is a program's body, which the tests run, and its
last line says what it gives. This is the same query:

```scheme run
(call-with-database ":memory:"
  (lambda (db)
    (execute! db "create table pets (name text, legs integer)")
    (execute! db "insert into pets values (?, ?)" "cat" 4)
    (execute! db "insert into pets values (?, ?)" "bird" 2)
    (query db "select name, legs from pets order by legs")))
;; => (#("bird" 2) #("cat" 4))
```

## On a Mac

- **Apple's library is found by itself:** `/usr/lib/libsqlite3.dylib`.
- **Homebrew's SQLite is not.** Name it with `CHEZ_SQLITE3_LIBRARY`, by
  its absolute path. On an arm64 Mac it is here:

  ```sh
  export CHEZ_SQLITE3_LIBRARY=/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib
  ```

- **Apple's library has no extension loading.** An open that asks for it
  raises a condition that `sqlite-extensions-unavailable?` holds. To load
  [extensions](reference.md#extensions), name another library, such as
  Homebrew's.

## Which SQLite did it load?

This program says which library it loaded, or why it refused one:

```scheme
(import (rnrs) (rnrs eval) (chez-sqlite3))

(write
 (guard (e ((sqlite-library-unavailable? e)
            (list 'refused
                  (sqlite-library-unavailable-reason e)
                  (sqlite-library-unavailable-path e))))
   (eval '(list (sqlite-version) (sqlite-library-path) (sqlite-library-source))
         (environment '(rnrs) '(chez-sqlite3)))))
(newline)
```

- **Loaded:** the version, the path, and where the path came from:
  `override` for `CHEZ_SQLITE3_LIBRARY`, or the place it was found, such as
  `system` or `macos-system`.
- **Refused:** `refused`, the reason, such as `not-found` or
  `below-floor`, and the path, or `#f` when none was chosen.
  [Finding SQLite](finding-sqlite.md#when-it-is-refused) says what each
  reason means.

A program that names a procedure that loads SQLite loads it as it starts,
before any `guard` in it is in place. So this program names them only
inside `eval`, within the `guard`; the conditions' predicates and
accessors load nothing ([The library](reference.md#the-library)).

## Running the tests

The tests need a pinned submodule, fetched once, and the tools
[README.org's Requirements](../README.org) list. From the folder you cloned
into:

```sh
cd chez-sqlite3
git submodule update --init --recursive
make test
```

The tests compile C against the first `sqlite3.h` the compiler finds, and
nothing checks that it is the loaded library's. So set `C_INCLUDE_PATH` to
the folder of the library's `sqlite3.h` when the compiler can't find it, or
to test another SQLite, which `CHEZ_SQLITE3_LIBRARY` names. `make help`
lists every target.

## Next

- [Finding SQLite](finding-sqlite.md): which library is loaded, and how to
  name another.
- [What varies by library](libraries.md): what differs between the SQLites
  the tests ran on.
- [API reference](reference.md): every name `(chez-sqlite3)` exports.
