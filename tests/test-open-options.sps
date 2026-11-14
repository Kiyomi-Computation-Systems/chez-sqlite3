#!r6rs
;;; The suite for (chez-sqlite3 private open-options): the pure core of
;;; open-database's options, and of its file: refusal (ADR-0012, decision 3).
;;; It loads no libsqlite3: the library is pure, and the shell that turns
;;; its answers into flags passed to SQLite and into assertion violations is
;;; tests/test-connection.sps's.
;;;
;;;   the table      ADR-0012's mode table and extras, written out here as
;;;                  sqlite3.h's numbers, never read from the library: none,
;;;                  each option alone, each pair, then every set of distinct
;;;                  options in every order
;;;   refusals       an option given twice at every position, an unknown
;;;                  option against the whole complement this suite can
;;;                  name, a contradiction in every order with every set of
;;;                  extras, and which refusal comes first
;;;   uri-filename?  "file:" at position 0, byte for byte and case-sensitive
;;;                  as SQLite's own test: true for it, false for every
;;;                  5-character string that differs from it in one place,
;;;                  and for "file:" anywhere but the start
;;;
;;; parse-open-options answers data, never a raise, so no row here needs a
;;; guard but the ones that call it on what could make it raise; every call is
;;; under one all the same, each with a sentinel of its own. No expected
;;; value is #f: a boolean answer is compared as the symbol yes or no.
(import (rnrs)
        (rnrs mutable-strings)
        (srfi :64)
        (only (chezscheme) environment environment-symbols library-exports)
        (chez-sqlite3-testing)
        (chez-sqlite3 private open-options))

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

;; --- sqlite3.h's numbers, written out ----------------------------------------------------

(define READONLY #x00000001)
(define READWRITE #x00000002)
(define CREATE #x00000004)
(define URI #x00000040)
(define MEMORY #x00000080)
(define NOMUTEX #x00008000)
(define FULLMUTEX #x00010000)
(define NOFOLLOW #x01000000)
(define EXRESCODE #x02000000)

(define options '(read-only read-write create uri memory no-follow no-mutex))

;; expected : (Listof Symbol) -> Any
;; ADR-0012's table for a set of distinct options, as parse-open-options must
;; answer it: the mode row, each extra, the mutex and EXRESCODE.
(define (expected set)
  (let ((ro (memq 'read-only set)) (rw (memq 'read-write set)) (cr (memq 'create set)))
    (cond
      ((and ro (or rw cr))
       (cons 'contradiction
             (append '(read-only) (if rw '(read-write) '()) (if cr '(create) '()))))
      (else
       (cons 'flags
             (bitwise-ior (cond (ro READONLY) ((and rw (not cr)) READWRITE) (else (bitwise-ior READWRITE CREATE)))
                          (if (memq 'uri set) URI 0)
                          (if (memq 'memory set) MEMORY 0)
                          (if (memq 'no-follow set) NOFOLLOW 0)
                          (if (memq 'no-mutex set) NOMUTEX FULLMUTEX)
                          EXRESCODE))))))

;; parsed : Any -> Any
;; parse-open-options' answer for GIVEN, or (raised TEXT).
(define (parsed given)
  (guard (e (#t (list 'raised (describe e))))
    (parse-open-options given)))

(define (sorted-names names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

;; subsets : (Listof A) -> (Listof (Listof A))
(define (subsets items)
  (if (null? items)
      '(())
      (let ((rest (subsets (cdr items))))
        (append rest (map (lambda (s) (cons (car items) s)) rest)))))

;; permutations : (Listof A) -> (Listof (Listof A))
(define (permutations items)
  (if (null? items)
      '(())
      (apply append
             (map (lambda (x)
                    (map (lambda (p) (cons x p)) (permutations (remq x items))))
                  items))))

;; list-head* : (Listof A) Natural -> (Listof A)
;; The first N of ITEMS, or all of them when there are fewer.
(define (list-head* items n) (if (or (= n 0) (null? items)) '() (cons (car items) (list-head* (cdr items) (- n 1)))))

;; insert-at : A Natural (Listof A) -> (Listof A)
(define (insert-at x i items)
  (if (= i 0) (cons x items) (cons (car items) (insert-at x (- i 1) (cdr items)))))

(test-begin "open-options")

(test-equal "(chez-sqlite3 private open-options) exports exactly the option names, the parser and uri-filename?"
  (sorted-names '(open-option-names parse-open-options uri-filename?))
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3 private open-options)))))

(test-equal "open-option-names, written out, in ADR-0012's order"
  '(read-only read-write create uri memory no-follow no-mutex)
  open-option-names)

;; --- the table: none, alone, pairs, written out ----------------------------------------

(test-equal "no option: READWRITE|CREATE, FULLMUTEX and EXRESCODE"
  (cons 'flags #x2010006)
  (parsed '()))

(test-equal "each option alone"
  (list (cons 'flags (bitwise-ior READONLY FULLMUTEX EXRESCODE))
        (cons 'flags (bitwise-ior READWRITE FULLMUTEX EXRESCODE))
        (cons 'flags (bitwise-ior READWRITE CREATE FULLMUTEX EXRESCODE))
        (cons 'flags (bitwise-ior READWRITE CREATE URI FULLMUTEX EXRESCODE))
        (cons 'flags (bitwise-ior READWRITE CREATE MEMORY FULLMUTEX EXRESCODE))
        (cons 'flags (bitwise-ior READWRITE CREATE NOFOLLOW FULLMUTEX EXRESCODE))
        (cons 'flags (bitwise-ior READWRITE CREATE NOMUTEX EXRESCODE)))
  (list (parsed '(read-only)) (parsed '(read-write)) (parsed '(create)) (parsed '(uri))
        (parsed '(memory)) (parsed '(no-follow)) (parsed '(no-mutex))))

(test-equal "each pair, in the order open-option-names gives them"
  (list (list '(read-only read-write) 'contradiction 'read-only 'read-write)
        (list '(read-only create) 'contradiction 'read-only 'create)
        (cons '(read-only uri) (bitwise-ior READONLY URI FULLMUTEX EXRESCODE))
        (cons '(read-only memory) (bitwise-ior READONLY MEMORY FULLMUTEX EXRESCODE))
        (cons '(read-only no-follow) (bitwise-ior READONLY NOFOLLOW FULLMUTEX EXRESCODE))
        (cons '(read-only no-mutex) (bitwise-ior READONLY NOMUTEX EXRESCODE))
        (cons '(read-write create) (bitwise-ior READWRITE CREATE FULLMUTEX EXRESCODE))
        (cons '(read-write uri) (bitwise-ior READWRITE URI FULLMUTEX EXRESCODE))
        (cons '(read-write memory) (bitwise-ior READWRITE MEMORY FULLMUTEX EXRESCODE))
        (cons '(read-write no-follow) (bitwise-ior READWRITE NOFOLLOW FULLMUTEX EXRESCODE))
        (cons '(read-write no-mutex) (bitwise-ior READWRITE NOMUTEX EXRESCODE))
        (cons '(create uri) (bitwise-ior READWRITE CREATE URI FULLMUTEX EXRESCODE))
        (cons '(create memory) (bitwise-ior READWRITE CREATE MEMORY FULLMUTEX EXRESCODE))
        (cons '(create no-follow) (bitwise-ior READWRITE CREATE NOFOLLOW FULLMUTEX EXRESCODE))
        (cons '(create no-mutex) (bitwise-ior READWRITE CREATE NOMUTEX EXRESCODE))
        (cons '(uri memory) (bitwise-ior READWRITE CREATE URI MEMORY FULLMUTEX EXRESCODE))
        (cons '(uri no-follow) (bitwise-ior READWRITE CREATE URI NOFOLLOW FULLMUTEX EXRESCODE))
        (cons '(uri no-mutex) (bitwise-ior READWRITE CREATE URI NOMUTEX EXRESCODE))
        (cons '(memory no-follow) (bitwise-ior READWRITE CREATE MEMORY NOFOLLOW FULLMUTEX EXRESCODE))
        (cons '(memory no-mutex) (bitwise-ior READWRITE CREATE MEMORY NOMUTEX EXRESCODE))
        (cons '(no-follow no-mutex) (bitwise-ior READWRITE CREATE NOFOLLOW NOMUTEX EXRESCODE)))
  (let loop ((rest options) (found '()))
    (if (null? rest)
        (reverse found)
        (loop (cdr rest)
              (append (reverse (map (lambda (other)
                                      (let ((pair (list (car rest) other)))
                                        (cons pair (let ((p (parsed pair)))
                                                     (if (and (pair? p) (eq? (car p) 'flags)) (cdr p) p)))))
                                    (cdr rest)))
                      found)))))

;; --- every set, in every order ---------------------------------------------------------

;; every-ordering : (Listof (Listof Symbol))
;; Every ordering of every set of distinct options: 13,700 lists.
(define every-ordering (apply append (map permutations (subsets options))))

(test-equal "there are 13,700 orderings of the sets of distinct options"
  13700
  (length every-ordering))

(test-equal "every ordering of every set of distinct options answers its set's row of ADR-0012's table: no list differs"
  '()
  (filter (lambda (row) row)
          (map (lambda (given)
                 (let ((want (expected given)) (got (parsed given)))
                   (and (not (equal? want got)) (cons given got))))
               every-ordering)))

(test-equal "the contradictions, whole, in every order and with every set of extras: read-only with read-write, with create, and with both"
  '((contradiction read-only read-write)
    (contradiction read-only create)
    (contradiction read-only read-write create))
  (map (lambda (modes)
         (let ((answers (apply append
                               (map (lambda (extras)
                                      (map parsed (permutations (append modes extras))))
                                    (subsets '(uri memory no-follow no-mutex))))))
           (if (for-all (lambda (a) (equal? a (car answers))) answers)
               (car answers)
               (list 'differs answers))))
       '((read-only read-write) (read-only create) (read-only read-write create))))

;; --- an option twice ---------------------------------------------------------------------

(test-equal "each option given twice, alone, is refused as twice, naming it"
  (map (lambda (o) (list 'twice o)) options)
  (map (lambda (o) (parsed (list o o))) options))

(test-equal "each option given twice, at every position beside two others, is refused as twice, naming it"
  (apply append (map (lambda (o) (map (lambda (i) (list 'twice o)) '(0 1 2 3))) options))
  (apply append
         (map (lambda (o)
                (let ((others (remq o '(uri memory no-follow no-mutex create))))
                  (map (lambda (i) (parsed (insert-at o i (cons o (list-head* others 2)))))
                       '(0 1 2 3))))
              options)))

(test-equal "an option three times is refused as twice; the first option repeated is the one named"
  '((twice uri) (twice memory) (twice create))
  (list (parsed '(uri uri uri))
        (parsed '(memory uri memory uri))
        (parsed '(read-only create no-mutex create read-only))))

;; --- unknown options, against the complement -----------------------------------------------

;; Every name (chezscheme) exports: none is an option, and some are near
;; ones (exit, open, read, ...).
(define chez-names
  (guard (e (#t (list 'raised (describe e))))
    (remp (lambda (s) (memq s options)) (environment-symbols (environment '(chezscheme))))))

(test-equal "(chezscheme) gives names to refuse, in the hundreds"
  'many
  (if (and (list? chez-names) (> (length chez-names) 500)) 'many chez-names))

(test-equal "every name (chezscheme) exports is refused as unknown, naming it"
  '()
  (if (list? chez-names)
      (filter (lambda (row) row)
              (map (lambda (s)
                     (let ((got (parsed (list s))))
                       (and (not (equal? got (list 'unknown s))) (cons s got))))
                   chez-names))
      chez-names))

;; Near names: SQLite's other open flags in this spelling, the flags of the
;; options without their hyphen, case and separator variants, and plurals.
(define near-options
  (append
   '(readonly readwrite nomutex fullmutex full-mutex nofollow exrescode exclusive autoproxy
     deleteonclose delete-on-close main-db temp-db transient-db main-journal temp-journal
     subjournal super-journal sharedcache shared-cache privatecache private-cache wal vfs
     READ-ONLY Read-Only READ-WRITE CREATE URI MEMORY NO-FOLLOW NO-MUTEX
     read_only read_write no_follow no_mutex read-only? read-onl ead-only creates uris
     memory! :memory:)
   ;; #!r6rs has no |...| symbols: an option with a space on either side.
   (map string->symbol '("read-only " " read-only" "no mutex"))))

(test-equal "every near name is refused as unknown, naming it"
  (map (lambda (s) (list 'unknown s)) near-options)
  (map (lambda (s) (parsed (list s))) near-options))

(test-equal "an option that is no symbol is refused as unknown, naming it by shown-value: a string by its kind, a list holding one by its kind, a number, a flag's own number, a boolean, (), a char, a list, a vector and a procedure"
  '((unknown (kind string)) (unknown (kind list)) (unknown 1) (unknown 65536) (unknown #t)
    (unknown ()) (unknown #\r) (unknown (read-only)) (unknown (kind vector))
    (unknown (kind procedure)))
  (map (lambda (x) (parsed (list x)))
       (list "read-only" (list "read-only") 1 FULLMUTEX #t '() #\r '(read-only)
             (vector 'read-only) car)))

(test-equal "an unknown option at every position among known ones is the one named"
  '((unknown foo) (unknown foo) (unknown foo) (unknown foo))
  (map (lambda (i) (parsed (insert-at 'foo i '(read-only uri no-mutex)))) '(0 1 2 3)))

;; --- which refusal comes first ----------------------------------------------------------------

(test-equal "one pass, left to right: the first unknown or repeated option is named, and a contradiction only when every option is known and given once"
  '((unknown foo) (twice read-only) (unknown foo) (twice create) (unknown foo) (twice create))
  (list (parsed '(read-only create foo))
        (parsed '(read-only read-only foo))
        (parsed '(foo read-only read-only))
        (parsed '(read-only create create))
        (parsed '(read-only read-write foo foo))
        (parsed '(read-only create create foo))))

(test-equal "the parser leaves its list as it was"
  '(read-only no-mutex)
  (let ((given (list 'read-only 'no-mutex)))
    (parsed given)
    given))

;; --- uri-filename? -----------------------------------------------------------------------------

(define (yes-no x) (if (eq? x #t) 'yes (if (eq? x #f) 'no (list 'neither x))))

(define (uri? s)
  (guard (e (#t (list 'raised (describe e))))
    (yes-no (uri-filename? s))))

(test-equal "uri-filename? is true for a name that starts file:"
  '(yes yes yes yes yes)
  (map uri? '("file:" "file:x.db" "file:///tmp/x.db" "file::memory:" "file:x.db?mode=ro")))

;; Every 5-character string that differs from file: in exactly one place, by
;; every ASCII character: the scan at each position, against its complement,
;; FILE:'s case variants among them.
(define one-off
  (apply append
         (map (lambda (i)
                (let loop ((c 0) (found '()))
                  (if (= c 128)
                      (reverse found)
                      (loop (+ c 1)
                            (if (char=? (integer->char c) (string-ref "file:" i))
                                found
                                (let ((s (string-copy "file:")))
                                  (string-set! s i (integer->char c))
                                  (cons (string-append s "x.db") found)))))))
              '(0 1 2 3 4))))

(test-equal "there are 635 one-off variants of file:"
  635
  (length one-off))

(test-equal "uri-filename? is false for every name whose first five characters differ from file: in one place, by any ASCII character, FILE:, File: and file; among them"
  '()
  (filter (lambda (row) row)
          (map (lambda (s) (and (not (eq? (uri? s) 'no)) (cons s (uri? s)))) one-off)))

(test-equal "uri-filename? is false for file: anywhere but the start, and for names too short to hold it"
  '(no no no no no no no no no)
  (map uri? '("" "f" "file" "./file:x.db" "/tmp/file:x.db" " file:x.db" "xfile:x.db"
              "FILE:x.db" "File:x.db")))

(test-equal "uri-filename? is false for file: at every position after the start"
  '(no no no no no no)
  (map (lambda (i) (uri? (string-append (make-string i #\a) "file:x"))) '(1 2 3 4 5 6)))

(test-end "open-options")

(exit (suite-exit-status runner))
