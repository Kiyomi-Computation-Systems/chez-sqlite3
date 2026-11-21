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
