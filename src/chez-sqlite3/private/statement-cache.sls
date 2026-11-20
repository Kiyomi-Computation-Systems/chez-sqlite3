#!r6rs
;;; (chez-sqlite3 private statement-cache): the statement cache's table
;;; (ADR-0020). Pure Scheme: no foreign code, and nothing here loads
;;; libsqlite3. A table of string keys, the SQL's exact text (ADR-0020),
;;; matched by string=? and hashed by string-hash, and opaque
;;; statements, with a capacity fixed when it is made. The caller passes a
;;; string it has copied and checked: a key that is no string is outside the
;;; table's domain, and string-hash raises on it; a string changed after it
;;; is filed is the caller's to avoid. It finalizes nothing: each change
;;; answers what its caller must finalize, and the caller does, after its
;;; critical section.
;;;
;;;   make-statement-cache         a table of capacity N, 0 to 1024
;;;   statement-cache-check-out!   the statement filed under a key, removed,
;;;                                or a miss
;;;   statement-cache-return!      a statement filed as the most recent, and
;;;                                what to finalize: the least recently used
;;;                                one, evicted from a full table, or the
;;;                                statement itself at capacity 0 or when a
;;;                                different one is held under its key; none
;;;                                for the very one held
;;;   statement-cache-clear!       every statement held, for the close
;;;
;;; The table only reads and changes itself: it calls nothing of its caller's,
;;; neither a key nor a statement, and it raises nothing for a table, a string
;;; key and any statement, so the connection calls it inside a critical section.
;;; It holds no state of a statement's: a finalized statement is a miss by the
;;; connection's check of the statement's own state, made after a check-out
;;; answers it and before a return, in the same section (ADR-0020), never here.
;;;
;;; The table is a hashtable from key to entry, for a lookup in constant time,
;;; and the entries a doubly linked list, newest to oldest, for an eviction in
;;; constant time.
(library (chez-sqlite3 private statement-cache)
  (export make-statement-cache statement-cache? statement-cache-capacity
          statement-cache-count statement-cache-check-out! statement-cache-return!
          statement-cache-clear!)
  (import (chez-sqlite3 private require-threaded)
          (rnrs))

  ;; An entry: a key, its statement, and its neighbours in the list, the
  ;; newer and the older, #f at either end.
  (define-record-type entry
    (sealed #t) (opaque #t)
    (fields key statement (mutable newer) (mutable older)))

  ;; statement-cache? : Any -> Boolean
  ;; statement-cache-capacity : Statement-Cache -> Natural
  (define-record-type (statement-cache new-statement-cache statement-cache?)
    (sealed #t) (opaque #t)
    (fields (immutable capacity statement-cache-capacity)
            (immutable table cache-table)
            (mutable newest cache-newest set-cache-newest!)
            (mutable oldest cache-oldest set-cache-oldest!)))

  ;; make-statement-cache : Natural -> Statement-Cache
  ;; An empty table of CAPACITY, an exact integer from 0 to 1024 that the
  ;; settings' plan has checked, fixed for the table's life (ADR-0020).
  ;; Raises nothing for such a CAPACITY.
  (define (make-statement-cache capacity)
    (new-statement-cache capacity (make-hashtable string-hash string=?) #f #f))

  ;; statement-cache-count : Statement-Cache -> Natural
  ;; How many statements CACHE holds.
  (define (statement-cache-count cache)
    (hashtable-size (cache-table cache)))

  ;; unlink! : Statement-Cache Entry -> Void
  ;; E out of CACHE's list, its neighbours joined.
  (define (unlink! cache e)
    (let ((newer (entry-newer e)) (older (entry-older e)))
      (if newer (entry-older-set! newer older) (set-cache-newest! cache older))
      (if older (entry-newer-set! older newer) (set-cache-oldest! cache newer))))

  ;; push-newest! : Statement-Cache Entry -> Void
  ;; E, unlinked, at the newest end of CACHE's list.
  (define (push-newest! cache e)
    (let ((newest (cache-newest cache)))
      (entry-newer-set! e #f)
      (entry-older-set! e newest)
      (if newest (entry-newer-set! newest e) (set-cache-oldest! cache e))
      (set-cache-newest! cache e)))

  ;; statement-cache-check-out! : Statement-Cache String -> (U (List 'hit Any) (List 'miss))
  ;; The statement CACHE holds under KEY, removed from the table, as (hit S),
  ;; or (miss) when it holds none. Raises nothing.
  (define (statement-cache-check-out! cache key)
    (let ((e (hashtable-ref (cache-table cache) key #f)))
      (if e
          (begin
            (hashtable-delete! (cache-table cache) key)
            (unlink! cache e)
            (list 'hit (entry-statement e)))
          (list 'miss))))

  ;; statement-cache-return! : Statement-Cache String Any -> (Listof Any)
  ;; STATEMENT, filed under KEY, the statement's own SQL copy, as CACHE's most
  ;; recent; the answer is what the caller must finalize (ADR-0020): at
  ;; capacity 0, (STATEMENT), the table unchanged; when CACHE holds KEY
  ;; already, returned meanwhile, the held one kept where it stood, and
  ;; (STATEMENT) to finalize, or () when STATEMENT is the very one held
  ;; (eq?), the same statement returned twice, finalized by neither; when
  ;; CACHE is full, the least recently used one, evicted, as (S); else ().
  ;; Raises nothing.
  (define (statement-cache-return! cache key statement)
    (let ((table (cache-table cache)) (capacity (statement-cache-capacity cache)))
      (cond ((= capacity 0) (list statement))
            ((hashtable-ref table key #f)
             => (lambda (held)
                  (if (eq? (entry-statement held) statement) '() (list statement))))
            (else
             (let ((evicted (and (>= (hashtable-size table) capacity) (cache-oldest cache)))
                   (e (make-entry key statement #f #f)))
               (when evicted
                 (hashtable-delete! table (entry-key evicted))
                 (unlink! cache evicted))
               (hashtable-set! table key e)
               (push-newest! cache e)
               (if evicted (list (entry-statement evicted)) '()))))))

  ;; statement-cache-clear! : Statement-Cache -> (Listof Any)
  ;; Every statement CACHE holds, least recently used first, the table left
  ;; empty, its capacity kept (ADR-0020). Raises nothing.
  (define (statement-cache-clear! cache)
    (let loop ((e (cache-oldest cache)) (held '()))
      (if e
          (loop (entry-newer e) (cons (entry-statement e) held))
          (begin
            (hashtable-clear! (cache-table cache))
            (set-cache-newest! cache #f)
            (set-cache-oldest! cache #f)
            (reverse held))))))
