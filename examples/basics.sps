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
