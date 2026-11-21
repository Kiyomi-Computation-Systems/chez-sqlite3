# Examples

Five programs for everyday work with a database, each a file of the
clone's `examples/`. Each section shows a program in full, and what it
prints.

Run one from beside the clone, as the [quick start](quickstart.md) runs
`app.sps`:

```sh
scheme --libdirs chez-sqlite3/src --program chez-sqlite3/examples/basics.sps
```

## Basics

[`examples/basics.sps`](../examples/basics.sps) makes a table in memory,
adds rows, reads them back, and changes them. It shows the `?` marks,
SQL's NULL, a BLOB, the new row's id, how many rows changed, and an
upsert.

```scheme
(import (rnrs) (chez-sqlite3))

;; show : String Any -> Void
;; Prints the label, then the value as write writes it.
(define (show label value)
  (display label)
  (display ": ")
  (write value)
  (newline))

(define db (open-database ":memory:"))

(execute! db "create table books
              (id integer primary key, title text not null, year integer, cover blob)")

;; Each ? takes the next value after the SQL.
(execute! db "insert into books (title, year) values (?, ?)" "Dune" 1965)
(show "new id" (last-insert-rowid db))
(execute! db "insert into books (title, year) values (?, ?)" "Neuromancer" 1984)
(execute! db "insert into books (title, year) values (?, ?)" "Untitled" sql-null)

;; query gives every row, each a vector; query-row gives the first, or #f.
(show "all" (query db "select id, title, year from books order by id"))
(show "one" (query-row db "select title from books where year = ?" 1984))
(show "none" (query-row db "select title from books where year = ?" 2001))

;; SQL's NULL is sql-null, both ways.
(show "null?" (sql-null? (vector-ref (query-row db "select year from books where id = ?" 3) 0)))

;; A bytevector is a BLOB.
(execute! db "update books set cover = ? where id = ?" #vu8(137 80 78 71) 1)
(show "cover" (query-row db "select cover from books where id = ?" 1))

;; changes counts the rows the last statement changed.
(execute! db "update books set year = year + 1 where year < ?" 2000)
(show "updated" (changes db))
(execute! db "delete from books where year is null")
(show "deleted" (changes db))

;; An upsert: insert the row, or update the one already there.
;; RETURNING gives the rows it wrote.
(show "upsert"
      (query db "insert into books (id, title, year) values (?, ?, ?)
                 on conflict (id) do update set title = excluded.title, year = excluded.year
                 returning id, title, year"
             1 "Dune Messiah" 1969))

(close-database! db)
```

It prints:

```text
new id: 1
all: (#(1 "Dune" 1965) #(2 "Neuromancer" 1984) #(3 "Untitled" #<sql-null-type>))
one: #("Neuromancer")
none: #f
null?: #t
cover: #(#vu8(137 80 78 71))
updated: 2
deleted: 1
upsert: (#(1 "Dune Messiah" 1969))
```

## Transactions and errors

[`examples/transactions.sps`](../examples/transactions.sps) groups
writes with `with-transaction`: they all happen, or, when one raises,
none does. A constraint's refusal is a condition that
`sqlite-constraint?` holds, and its extended code names the kind of
constraint.

```scheme
(import (rnrs) (chez-sqlite3))

;; show : String Any -> Void
;; Prints the label, then the value as write writes it.
(define (show label value)
  (display label)
  (display ": ")
  (write value)
  (newline))

(define db (open-database ":memory:"))

(execute! db "create table accounts
              (name text not null unique, balance integer not null check (balance >= 0))")

;; balances : -> (Listof Row)
(define (balances) (query db "select name, balance from accounts order by name"))

;; with-transaction commits when its procedure returns: here, a batch of
;; inserts, all at once.
(with-transaction db
  (lambda ()
    (for-each (lambda (name balance)
                (execute! db "insert into accounts values (?, ?)" name balance))
              '("alice" "bob" "carol")
              '(100 50 0))))
(show "opened" (balances))

;; transfer! : String String Integer -> Void
;; Moves the amount from one account to another: both, or neither.
(define (transfer! from to amount)
  (with-transaction db
    (lambda ()
      (execute! db "update accounts set balance = balance + ? where name = ?" amount to)
      (execute! db "update accounts set balance = balance - ? where name = ?" amount from))))

(transfer! "alice" "bob" 30)
(show "moved 30" (balances))

;; A raise rolls the transaction back. Here the CHECK refuses alice's
;; balance below 0, after bob's update has run: bob's is undone too.
(show "refused"
      (guard (e ((sqlite-constraint? e) (sqlite-error-extended-code e)))
        (transfer! "alice" "bob" 500)
        'moved))
(show "unchanged" (balances))

;; A UNIQUE column refuses a second row with its value.
(show "duplicate"
      (guard (e ((sqlite-constraint? e) (sqlite-error-extended-code e)))
        (execute! db "insert into accounts values (?, ?)" "bob" 10)
        'inserted))

(close-database! db)
```

It prints:

```text
opened: (#("alice" 100) #("bob" 50) #("carol" 0))
moved 30: (#("alice" 70) #("bob" 80) #("carol" 0))
refused: constraint-check
unchanged: (#("alice" 70) #("bob" 80) #("carol" 0))
duplicate: constraint-unique
```

## Prepared statements

[`examples/prepared.sps`](../examples/prepared.sps) prepares an insert
once and runs it a thousand times, folds over rows one at a time, and
steps a statement by hand.

```scheme
(import (rnrs) (chez-sqlite3))

;; show : String Any -> Void
;; Prints the label, then the value as write writes it.
(define (show label value)
  (display label)
  (display ": ")
  (write value)
  (newline))

(define db (open-database ":memory:"))

(execute! db "create table squares (n integer primary key, square integer not null)")

;; Prepare the insert once, then bind, step and reset it for each row.
;; In one transaction, the thousand inserts commit once, not a thousand times.
(define insert (prepare-statement db "insert into squares values (:n, :square)"))
(with-transaction db
  (lambda ()
    (let loop ((n 1))
      (when (<= n 1000)
        (bind! insert ":n" n)
        (bind! insert ":square" (* n n))
        (step! insert)
        (reset! insert)
        (loop (+ n 1))))))
(finalize-statement! insert)
(show "rows" (query-row db "select count(*) from squares"))

;; query-fold hands each row to the procedure, one at a time, with no list
;; of them all.
(show "sum"
      (query-fold db "select square from squares"
                  (lambda (sum row) (+ sum (vector-ref row 0)))
                  0))

;; Step a statement yourself, and read its columns.
(show "last three"
      (call-with-statement db "select n, square from squares where n > ? order by n"
        (lambda (st)
          (bind! st 1 997)
          (let loop ((rows '()))
            (if (step! st)
                (loop (cons (list (column-value st 0) (column-value st 1)) rows))
                (reverse rows))))))

(close-database! db)
```

It prints:

```text
rows: #(1000)
sum: 333833500
last three: ((998 996004) (999 998001) (1000 1000000))
```

## A database file

[`examples/file-database.sps`](../examples/file-database.sps) opens
`notes.db`, in the directory you run it from, with three common
settings, and brings its tables up to date with migrations.

```scheme
(import (rnrs) (chez-sqlite3))

;; show : String Any -> Void
;; Prints the label, then the value as write writes it.
(define (show label value)
  (display label)
  (display ": ")
  (write value)
  (newline))

;; The file is made in the directory you run this from, the first time.
;; The settings are set each time it opens.
(define db
  (open-database "notes.db"
                 '((journal-mode . wal)
                   (foreign-keys . #t)
                   (busy-timeout . 5000))))

;; Each migration runs once, in order. The file's user_version says how
;; many have run.
(define migrations
  '("create table notebooks (id integer primary key, name text not null unique);
     create table notes (id integer primary key,
                         notebook integer not null references notebooks (id),
                         body text not null);"
    "create index notes_by_notebook on notes (notebook);
     insert into notebooks (name) values ('inbox');"))

;; schema-version : -> Integer
(define (schema-version) (vector-ref (query-row db "pragma user_version") 0))

;; migrate! : -> Void
;; Runs each migration the file has not had, each in a transaction with
;; its new user_version, so a failed one leaves the file as it was.
(define (migrate!)
  (let loop ((version (schema-version)))
    (when (< version (length migrations))
      (with-transaction db
        (lambda ()
          (execute-script! db (list-ref migrations version))
          (execute! db (string-append "pragma user_version = "
                                      (number->string (+ version 1))))))
      (loop (+ version 1)))))

(migrate!)
(show "version" (schema-version))
(show "journal" (query-row db "pragma journal_mode"))
(show "busy timeout" (query-row db "pragma busy_timeout"))

;; With foreign keys on, a note must name a notebook that is there.
(show "no such notebook"
      (guard (e ((sqlite-constraint? e) (sqlite-error-extended-code e)))
        (execute! db "insert into notes (notebook, body) values (?, ?)" 99 "lost")
        'inserted))
(show "notebooks" (query db "select id, name from notebooks"))

(close-database! db)
```

It prints:

```text
version: 2
journal: #("wal")
busy timeout: #(5000)
no such notebook: constraint-foreignkey
notebooks: (#(1 "inbox"))
```

Run it again and it prints the same: the file has had both migrations,
so none runs.

## JSON

[`examples/json.sps`](../examples/json.sps) keeps JSON documents in a
text column, and reads, indexes, builds and changes them with SQLite's
own JSON functions. They are built into SQLite, unless a library was
built without them.

```scheme
(import (rnrs) (chez-sqlite3))

;; show : String Any -> Void
;; Prints the label, then the value as write writes it.
(define (show label value)
  (display label)
  (display ": ")
  (write value)
  (newline))

(define db (open-database ":memory:"))

;; A JSON document is text. The CHECK refuses text that is no JSON.
(execute! db "create table events
              (id integer primary key, doc text not null check (json_valid(doc)))")

;; An index on one field of the documents.
(execute! db "create index events_by_kind on events (doc ->> '$.kind')")

(for-each (lambda (doc) (execute! db "insert into events (doc) values (?)" doc))
          '("{\"kind\": \"signup\", \"user\": \"ana\", \"tags\": [\"web\", \"promo\"]}"
            "{\"kind\": \"login\", \"user\": \"ana\", \"tags\": [\"web\"]}"
            "{\"kind\": \"signup\", \"user\": \"bo\", \"tags\": [\"app\"], \"score\": 2.5}"))

(show "not JSON"
      (guard (e ((sqlite-constraint? e) (sqlite-error-extended-code e)))
        (execute! db "insert into events (doc) values (?)" "{oops")
        'inserted))

;; ->> gives a field as an SQL value, -> as JSON text.
(show "signups"
      (query db "select id, doc ->> '$.user', doc -> '$.tags', doc ->> '$.score'
                 from events where doc ->> '$.kind' = ? order by id"
             "signup"))

;; json_each makes a row of each element of an array.
(show "tags"
      (query db "select tag.value, count(*)
                 from events, json_each(events.doc, '$.tags') as tag
                 group by tag.value order by tag.value"))

;; json_object and json_group_array build JSON from rows.
(show "users"
      (query-row db "select json_group_array(json_object('id', id, 'user', doc ->> '$.user')
                                             order by id)
                     from events"))

;; json_set and json_remove give a changed copy of a document.
(execute! db "update events set doc = json_set(doc, '$.seen', json('true')) where id = ?" 2)
(show "set" (query-row db "select doc from events where id = ?" 2))
(show "removed" (query-row db "select json_remove(doc, '$.tags') from events where id = ?" 2))

;; jsonb gives the same document in SQLite's binary JSON, a BLOB, which
;; json turns back into text.
(show "jsonb"
      (query-row db "select typeof(jsonb(doc)), json(jsonb(doc)) = json(doc)
                     from events where id = ?"
                 1))

(close-database! db)
```

It prints:

```text
not JSON: constraint-check
signups: (#(1 "ana" "[\"web\",\"promo\"]" #<sql-null-type>) #(3 "bo" "[\"app\"]" 2.5))
tags: (#("app" 1) #("promo" 1) #("web" 2))
users: #("[{\"id\":1,\"user\":\"ana\"},{\"id\":2,\"user\":\"ana\"},{\"id\":3,\"user\":\"bo\"}]")
set: #("{\"kind\":\"login\",\"user\":\"ana\",\"tags\":[\"web\"],\"seen\":true}")
removed: #("{\"kind\":\"login\",\"user\":\"ana\",\"seen\":true}")
jsonb: #("blob" 1)
```
