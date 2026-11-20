#!r6rs
;;; The suite for (chez-sqlite3 private statement-cache): the table of the
;;; statement cache (ADR-0020), over opaque keys and opaque statements. It
;;; loads no libsqlite3: the table holds no foreign code, calls nothing of its
;;; caller's, and finalizes nothing; it answers what its caller must
;;; finalize, and the statement layer does.
;;;
;;;   the table      its capacity, fixed when it is made, 0 to 1024
;;;   check-out      a statement filed under the key, removed, or a miss
;;;   return         the statement filed as the most recent, answering what
;;;                  to finalize: the least recently used, evicted when the
;;;                  table is full; the statement itself at capacity 0 or
;;;                  when a different one is held under its key, and none
;;;                  for the very one held
;;;   clear          every statement held, least recently used first
;;;   the model      a list in this suite, most recent first: every order of
;;;                  the six moves of three keys at capacities 0 to 3, and
;;;                  every sequence of up to five of them, against the table
;;;   capacities     0 (it keeps nothing), 1, 32 and 1024, written out
;;;
;;; The table raises nothing for the inputs its caller checks, so every call
;;; is made under a guard with a sentinel of its own, (raised TEXT). A
;;; statement here is a fresh list naming its key and a serial number, so
;;; every one differs from every other under equal?, and eq? rows hold that
;;; the table hands back the very object filed.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) library-exports)
        (chez-sqlite3-testing)
        (chez-sqlite3 private statement-cache))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (write (test-result-ref r 'expected-value))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r 'actual-value))
        (newline)))))

;; --- helpers -----------------------------------------------------------------------------

(define (sorted-names names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

(define-syntax safely
  (syntax-rules ()
    ((_ e) (guard (c (#t (list 'raised (describe c)))) e))))

(define (make n) (safely (make-statement-cache n)))
(define (out! c k) (safely (statement-cache-check-out! c k)))
(define (ret! c k s) (safely (statement-cache-return! c k s)))
(define (clear! c) (safely (statement-cache-clear! c)))
(define (count c) (safely (statement-cache-count c)))
(define (capacity c) (safely (statement-cache-capacity c)))

;; iota : Natural -> (Listof Natural)
(define (iota n)
  (let loop ((i (- n 1)) (acc '()))
    (if (< i 0) acc (loop (- i 1) (cons i acc)))))

;; permutations : (Listof A) -> (Listof (Listof A))
(define (permutations items)
  (if (null? items)
      '(())
      (apply append
             (map (lambda (x)
                    (map (lambda (p) (cons x p)) (permutations (remove x items))))
                  items))))

;; sequences : (Listof A) Natural -> (Listof (Listof A))
;; Every sequence of ITEMS of length N.
(define (sequences items n)
  (if (= n 0)
      '(())
      (let ((shorter (sequences items (- n 1))))
        (apply append (map (lambda (x) (map (lambda (s) (cons x s)) shorter)) items)))))

;; key-name : Natural -> String
(define (key-name i) (string-append "select " (number->string i)))

;; fill! : Statement-Cache Natural -> (Listof Any)
;; Keys 0 to N-1 returned to C in that order, each with its name as its
;; statement, and each return's answer, in order. A loop, never map, whose
;; calls Chez makes in no fixed order.
(define (fill! c n)
  (let loop ((i 0) (answers '()))
    (if (= i n)
        (reverse answers)
        (let ((a (ret! c (key-name i) (key-name i))))
          (loop (+ i 1) (cons a answers))))))

(define-record-type a-thing (fields x))

;; --- the model ---------------------------------------------------------------------------

;; assoc-string : String (Listof (Pairof String Any)) -> (U (Pairof String Any) #f)
;; The first entry whose key is string=? to K: keys are the SQL's exact text.
(define (assoc-string k entries)
  (find (lambda (e) (string=? (car e) k)) entries))

;; A model table is (capacity . entries), entries a list of (key . statement),
;; most recent first. Each move answers the model's next table and its answer.

(define (model-out m k)
  (let ((hit (assoc-string k (cdr m))))
    (if hit
        (values (cons (car m) (remp (lambda (e) (eq? e hit)) (cdr m))) (list 'hit (cdr hit)))
        (values m '(miss)))))

(define (model-ret m k s)
  (let ((cap (car m)) (entries (cdr m)))
    (cond ((= cap 0) (values m (list s)))
          ((assoc-string k entries)
           => (lambda (held) (values m (if (eq? (cdr held) s) '() (list s)))))
          ((< (length entries) cap) (values (cons cap (cons (cons k s) entries)) '()))
          (else
           (let ((kept (list-head* entries (- cap 1)))
                 (evicted (list-ref entries (- cap 1))))
             (values (cons cap (cons (cons k s) kept)) (list (cdr evicted))))))))

(define (model-clear m)
  (values (cons (car m) '()) (reverse (map cdr (cdr m)))))

(define (list-head* items n)
  (if (or (= n 0) (null? items)) '() (cons (car items) (list-head* (cdr items) (- n 1)))))

;; run : Natural (Listof (Pairof Symbol String)) -> (Values (Listof Any) (Listof Any))
;; MOVES, each (out . KEY), (ret . KEY) or (clear . #f), made on a fresh
;; table of CAPACITY and on the model, then a clear: each move's answer and
;; the count after it, from the table and from the model. A return files a
;; fresh statement.
(define (run cap moves)
  (let ((table (make cap)))
    (let loop ((moves moves) (m (cons cap '())) (serial 0) (got '()) (want '()))
      (if (null? moves)
          (let-values (((m2 w) (model-clear m)))
            (let* ((g (clear! table))
                   (n (count table)))
              (values (reverse (cons (list 'clear g n) got))
                      (reverse (cons (list 'clear w 0) want)))))
          (let ((move (car moves)))
            (cond
              ((eq? (car move) 'clear)
               (let-values (((m2 w) (model-clear m)))
                 (let* ((g (clear! table))
                        (n (count table)))
                   (loop (cdr moves) m2 serial
                         (cons (list move g n) got)
                         (cons (list move w (length (cdr m2))) want)))))
              ((eq? (car move) 'out)
                (let-values (((m2 w) (model-out m (cdr move))))
                  (let* ((g (out! table (cdr move)))
                         (n (count table)))
                    (loop (cdr moves) m2 serial
                          (cons (list move g n) got)
                          (cons (list move w (length (cdr m2))) want)))))
              (else
                (let ((s (list 'statement (cdr move) serial)))
                  (let-values (((m2 w) (model-ret m (cdr move) s)))
                    (let* ((g (ret! table (cdr move) s))
                           (n (count table)))
                      (loop (cdr moves) m2 (+ serial 1)
                            (cons (list move g n) got)
                            (cons (list move w (length (cdr m2))) want))))))))))))

;; mismatches : (Listof Natural) (Listof (Listof Move)) -> (Listof Any)
;; Each capacity and moves where the table and the model differ, with both.
(define (mismatches caps runs)
  (apply append
         (map (lambda (cap)
                (filter (lambda (x) x)
                        (map (lambda (moves)
                               (let-values (((got want) (run cap moves)))
                                 (and (not (equal? got want)) (list cap moves got want))))
                             runs)))
              caps)))

(define keys '("select a" "select b" "select c"))

(define the-moves
  (apply append (map (lambda (k) (list (cons 'out k) (cons 'ret k))) keys)))

(test-begin "statement-cache")

(test-equal "(chez-sqlite3 private statement-cache) exports exactly the table's maker, predicate, capacity, count, check-out, return and clear"
  (sorted-names '(make-statement-cache statement-cache? statement-cache-capacity
                  statement-cache-count statement-cache-check-out! statement-cache-return!
                  statement-cache-clear!))
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3 private statement-cache)))))

;; --- the model, checked by hand ------------------------------------------------------------

(test-equal "the model, by hand at capacity 2: a, b filed; a out and back; c evicts b; a duplicate return of c answers itself; clear answers a then c"
  '(((ret . "a") () 1) ((ret . "b") () 2) ((out . "a") (hit (statement "a" 0)) 1)
    ((ret . "a") () 2) ((ret . "c") ((statement "b" 1)) 2) ((ret . "c") ((statement "c" 4)) 2)
    (clear ((statement "a" 2) (statement "c" 3)) 0))
  (let-values (((got want) (run 2 '((ret . "a") (ret . "b") (out . "a") (ret . "a") (ret . "c")
                                    (ret . "c")))))
    want))

;; --- making a table ---------------------------------------------------------------------------

(test-equal "a table keeps the capacity it is made with, 0 to 1024, and starts empty"
  '((0 0) (1 0) (2 0) (3 0) (32 0) (1023 0) (1024 0))
  (map (lambda (n) (let ((c (make n))) (list (capacity c) (count c)))) '(0 1 2 3 32 1023 1024)))

(test-equal "statement-cache? holds for a table, and for nothing else, as yes and no"
  '(yes no no no no no no)
  (map (lambda (x) (safely (if (statement-cache? x) 'yes 'no)))
       (list (make 3) 3 '() (vector) (make-a-thing 1) "cache" car)))

;; --- capacity 0 -----------------------------------------------------------------------------

(test-equal "at capacity 0 the table keeps nothing: every return answers the statement itself, every check-out misses, the count stays 0 and a clear answers nothing"
  '((("s1") 0) (("s2") 0) (("s1b") 0) ((miss) 0) ((miss) 0) (() 0))
  (let ((c (make 0)))
    (let* ((a (list (ret! c "select 1" "s1") (count c)))
           (b (list (ret! c "select 2" "s2") (count c)))
           (d (list (ret! c "select 1" "s1b") (count c)))
           (e (list (out! c "select 1") (count c)))
           (f (list (out! c "select 2") (count c)))
           (g (list (clear! c) (count c))))
      (list a b d e f g))))

;; --- capacity 1 -----------------------------------------------------------------------------

(test-equal "at capacity 1: a statement filed; a second key evicts it; the first then misses and the second hits, removed by its check-out"
  '(() ("s1") (miss) (hit "s2") (miss) 0 () ("s3b") (hit "s3"))
  (let ((c (make 1)))
    (let* ((a (ret! c "select 1" "s1"))
           (b (ret! c "select 2" "s2"))
           (d (out! c "select 1"))
           (e (out! c "select 2"))
           (f (out! c "select 2"))
           (g (count c))
           (h (ret! c "select 3" "s3"))
           (i (ret! c "select 3" "s3b"))
           (j (out! c "select 3")))
      (list a b d e f g h i j))))

(test-equal "a hit hands back the very statement filed, eq?"
  'same
  (let ((c (make 1)) (s (list 'statement)))
    (ret! c "select 1" s)
    (let ((h (out! c "select 1")))
      (if (and (pair? h) (eq? (car h) 'hit) (eq? (cadr h) s)) 'same (list 'differs h)))))

(test-equal "an eviction and a duplicate return hand back the very statement, eq?"
  '(same same)
  (let ((c (make 1)) (s1 (list 1)) (s2 (list 2)) (s3 (list 3)))
    (ret! c "select 1" s1)
    (let* ((evicted (ret! c "select 2" s2))
           (dup (ret! c "select 2" s3)))
      (list (if (and (pair? evicted) (eq? (car evicted) s1)) 'same (list 'differs evicted))
            (if (and (pair? dup) (eq? (car dup) s3)) 'same (list 'differs dup))))))

;; --- the very statement returned twice ---------------------------------------------------------

(test-equal "the very statement already held under its key, returned again (eq?), answers () and the table keeps it where it stood: filed first and returned again after a second, it is still the oldest and the next evicted, and the count never grew"
  (list '() '() '() 2 'same 'same 1)
  (let ((c (make 2)) (s (list 'held)) (t (list 'other)))
    (let* ((r1 (ret! c "a" s))
           (r2 (ret! c "b" t))
           (again (ret! c "a" s))
           (n (count c))
           (r4 (ret! c "c" (list 'newest)))
           (h (out! c "b")))
      (list r1 r2 again n
            (if (and (pair? r4) (null? (cdr r4)) (eq? (car r4) s)) 'same (list 'differs r4))
            (if (and (pair? h) (eq? (cadr h) t)) 'same (list 'differs h))
            (count c)))))

(test-equal "a different statement returned under a held key answers itself, to finalize, and the held one stays, still its entry's statement: it is the one a check-out hands back"
  '(same same 1)
  (let ((c (make 2)) (held (list 'held)) (other (list 'other)))
    (ret! c "k" held)
    (let* ((r (ret! c "k" other))
           (n (count c))
           (o (out! c "k")))
      (list (if (and (pair? r) (null? (cdr r)) (eq? (car r) other)) 'same (list 'differs r))
            (if (and (pair? o) (eq? (cadr o) held)) 'same (list 'differs o))
            n))))

;; Two statements that are equal? and not eq? are two statements: the held one is the one
;; the table holds by its identity.
(test-equal "a statement equal? to the held one and not eq? is a different statement: returned under the held key it answers itself, to finalize, and the held one stays"
  '(same same)
  (let* ((c (make 2)) (held (list 'stmt)) (copy (list 'stmt)))
    (ret! c "k" held)
    (let* ((r (ret! c "k" copy))
           (o (out! c "k")))
      (list (if (and (pair? r) (null? (cdr r)) (eq? (car r) copy)) 'same (list 'differs r))
            (if (and (pair? o) (eq? (cadr o) held)) 'same (list 'differs o))))))

;; --- the order out ------------------------------------------------------------------------

(test-equal "at capacity 3, the least recently used out first: a, b, c filed; a out and back makes b the oldest; d evicts b, then e evicts c"
  '(() () () (hit "a") () ("b") ("c") 3)
  (let ((c (make 3)))
    (let* ((r1 (ret! c "a" "a")) (r2 (ret! c "b" "b")) (r3 (ret! c "c" "c"))
           (o (out! c "a")) (r4 (ret! c "a" "a"))
           (r5 (ret! c "d" "d")) (r6 (ret! c "e" "e")))
      (list r1 r2 r3 o r4 r5 r6 (count c)))))

(test-equal "a duplicate return answers the returned statement and leaves the held one where it stood: still the oldest, it is the next evicted"
  '(() () ("a2") () ("a1") (hit "b") 2)
  (let ((c (make 3)))
    (let* ((r1 (ret! c "a" "a1")) (r2 (ret! c "b" "b"))
           (dup (ret! c "a" "a2"))
           (r3 (ret! c "c" "c")) (r4 (ret! c "d" "d"))
           (o (out! c "b")))
      (list r1 r2 dup r3 r4 o (count c)))))

(test-equal "a check-out removes: a second one misses, and the count falls, until the statement is returned"
  '((hit "s") 0 (miss) () 1 (hit "s"))
  (let ((c (make 2)))
    (ret! c "k" "s")
    (let* ((a (out! c "k")) (n (count c)) (b (out! c "k"))
           (r (ret! c "k" "s")) (m (count c)) (d (out! c "k")))
      (list a n b r m d))))

(test-equal "a clear answers every statement held, least recently used first, and leaves the table empty, its capacity kept, and usable"
  '(("b" "c" "a") 0 3 (miss) (miss) (miss) () 1 (hit "d"))
  (let ((c (make 3)))
    (ret! c "a" "a") (ret! c "b" "b") (ret! c "c" "c")
    (out! c "a") (ret! c "a" "a")
    (let* ((cleared (clear! c)) (n (count c)) (cap (capacity c))
           (x (out! c "a")) (y (out! c "b")) (z (out! c "c"))
           (r (ret! c "d" "d")) (m (count c)))
      (list cleared n cap x y z r m (out! c "d")))))

(test-equal "a clear of an empty table answers nothing, and a second clear nothing more"
  '(() () ())
  (let* ((c (make 4))
         (a (clear! c))
         (b (begin (ret! c "a" "a") (clear! c) (clear! c)))
         (d (clear! (make 0))))
    (list a b d)))

;; --- capacity 32 and 1024 ---------------------------------------------------------------------

(test-equal "at capacity 32: 32 statements filed, none evicted; the 33rd evicts the first; touching the second keeps it, so the 34th evicts the third"
  (list (map (lambda (i) '()) (iota 32)) 32 (list (key-name 0)) '(hit "select 1") '()
        (list (key-name 2)) 32)
  (let ((c (make 32)))
    (let* ((filled (fill! c 32))
           (n (count c))
           (e33 (ret! c (key-name 32) (key-name 32)))
           (touch (out! c (key-name 1)))
           (back (ret! c (key-name 1) (key-name 1)))
           (e34 (ret! c (key-name 33) (key-name 33))))
      (list filled n e33 touch back e34 (count c)))))

(test-equal "at capacity 32, a clear answers the 32 held, least recently used first"
  (append (map key-name (cdr (iota 33))) '())
  (let ((c (make 32)))
    (for-each (lambda (i) (ret! c (key-name i) (key-name i))) (iota 33))
    (clear! c)))

(test-equal "at capacity 1024: 1024 filed, none evicted; the 1025th evicts the first, and the count stays 1024"
  (list '() 1024 (list (key-name 0)) 1024 '(miss) (list 'hit (key-name 1)))
  (let ((c (make 1024)))
    (let* ((filled (filter pair? (fill! c 1024)))
           (n (count c))
           (e (ret! c (key-name 1024) (key-name 1024)))
           (m (count c))
           (first-out (out! c (key-name 0)))
           (second-out (out! c (key-name 1))))
      (list filled n e m first-out second-out))))

;; --- keys and statements are opaque -----------------------------------------------------------

(test-equal "a key is matched by its contents: a fresh copy of the text hits, and text differing by case, by a space or by length misses"
  '((hit "s") (miss) (miss) (miss) (miss))
  (let ((c (make 4)))
    (ret! c (string-copy "select 1") "s")
    (let* ((a (out! c (string-copy "select 1")))
           (b (begin (ret! c "select 1" "s") (out! c "SELECT 1")))
           (d (out! c "select 1 "))
           (e (out! c "select"))
           (f (out! c "")))
      (list a b d e f))))

;; Each near spelling is tried while the table holds all four keys, its own
;; among them, and the exact keys after: a check-out removes what it hits,
;; so a near spelling tried after its key's check-out misses even in a table
;; that would match it. let*, since Chez fixes no order for a call's
;; arguments.
(test-equal "string keys of other shapes: the empty string, one with a NUL, a long one and non-ASCII text, each its own key, told apart from its near spellings, each tried while the table holds all four"
  '((miss) (miss) (miss) 4 (hit "e") (hit "nul") (hit "long") (hit "uni") 0)
  (let* ((c (make 8)) (long (make-string 5000 #\a)))
    (ret! c "" "e") (ret! c "a\x0;b" "nul") (ret! c long "long") (ret! c "caf\xe9;" "uni")
    (let* ((near-nul (out! c "a"))
           (near-uni (out! c "cafe"))
           (near-long (out! c (string-append (make-string 4999 #\a) "b")))
           (held (count c))
           (empty (out! c ""))
           (nul (out! c (string-copy "a\x0;b")))
           (long-hit (out! c (string-copy long)))
           (uni (out! c (string-copy "caf\xe9;")))
           (left (count c)))
      (list near-nul near-uni near-long held empty nul long-hit uni left))))

(test-equal "a key that is no string is outside the table's domain and raises, whatever it is, at a check-out and at a return: the table's keys are the SQL's text"
  '(raised raised raised raised raised raised)
  (let ((c (make 2)))
    (map (lambda (r) (if (and (pair? r) (eq? (car r) 'raised)) 'raised r))
         (list (out! c 1) (out! c 'sym) (out! c (list "a")) (ret! c 1 "s") (ret! c 'sym "s")
               (ret! c (list "a") "s")))))

(test-equal "any value is a statement, #f, () and a procedure among them; the table never calls one"
  '((hit #f) (hit ()) (hit called-never) never (proc))
  (let* ((c (make 2)) (called 'never)
         (proc (lambda args (set! called 'called) 'called)))
    (ret! c "f" #f) (ret! c "n" '())
    (let* ((a (out! c "f")) (b (out! c "n"))
           (r (ret! c "p" proc))
           (h (out! c "p"))
           (z (begin (ret! c "x" 1) (ret! c "y" 2) (ret! (make 0) "z" proc)))
           (after called))
      (list a b (if (and (pair? h) (eq? (cadr h) proc)) '(hit called-never) h) after
            (if (and (pair? z) (eq? (car z) proc)) '(proc) z)))))

(test-equal "two tables share nothing"
  '((hit "a") (miss) 0 1)
  (let ((c (make 2)) (d (make 2)))
    (ret! c "k" "a") (ret! d "j" "b")
    (let* ((a (out! c "k")) (b (out! c "j")) (n (count c)) (m (count d)))
      (list a b n m))))

;; --- every order, against the model -----------------------------------------------------------

(test-equal "the six moves of three keys, a check-out and a return each, in all 720 orders"
  720
  (length (permutations the-moves)))

(test-equal "every order of the six moves at capacities 0 to 3: each answer, each count and the clear's answer, the table against the model"
  '()
  (mismatches '(0 1 2 3) (permutations the-moves)))

(define every-sequence
  (apply append (map (lambda (n) (sequences the-moves n)) '(0 1 2 3 4 5))))

(test-equal "9,331 sequences of up to five of the six moves, repeats among them"
  9331
  (length every-sequence))

(test-equal "every sequence of up to five moves at capacities 0 to 3: the table against the model"
  '()
  (mismatches '(0 1 2 3) every-sequence))

;; The six moves and a clear, for the table's state after a clear.
(define moves-and-clear (append the-moves (list (cons 'clear #f))))

(define every-sequence-with-clear
  (apply append (map (lambda (n) (sequences moves-and-clear n)) '(0 1 2 3 4))))

(test-equal "2,801 sequences of up to four of the six moves and a clear"
  2801
  (length every-sequence-with-clear))

(test-equal "every sequence of up to four moves and clears at capacities 0 to 3: the table against the model, a table cleared midway among them"
  '()
  (mismatches '(0 1 2 3) every-sequence-with-clear))

;; lcg-moves : Natural -> (Listof Move)
;; N of the six moves, drawn by a linear congruential generator from a fixed
;; seed, so the sequence is the same on every run.
(define (lcg-moves n)
  (let loop ((i 0) (x 12345) (acc '()))
    (if (= i n)
        (reverse acc)
        (let ((x2 (mod (+ (* x 1103515245) 12345) 2147483648)))
          (loop (+ i 1) x2 (cons (list-ref the-moves (mod (div x2 65536) 6)) acc))))))

(test-equal "the long sequence holds every one of the six moves"
  '(6 400)
  (let ((moves (lcg-moves 400)))
    (list (length (filter (lambda (m) (member m moves)) the-moves)) (length moves))))

(test-equal "a long sequence of 400 moves at capacities 0 to 4, against the model"
  '()
  (mismatches '(0 1 2 3 4) (list (lcg-moves 400))))

(test-end "statement-cache")

(exit (suite-exit-status runner))
