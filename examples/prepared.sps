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
