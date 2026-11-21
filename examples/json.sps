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
