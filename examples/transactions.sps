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
