#!r6rs
;;; (chez-sqlite3 private memory): counted foreign blocks (ADR-0005,
;;; ADR-0011). The only library check-seam lets import foreign-alloc and
;;; foreign-free.
;;;
;;; A block is malloc'd memory, where Valgrind sees an overrun or a leak.
;;; Each one is counted as a block in (chez-sqlite3 private counters) while it
;;; lives, and kept in a table of live blocks, behind a mutex, so that freeing
;;; an address that is not a live block, twice or never allocated here,
;;; raises before anything reaches free.
;;;
;;; Each block's malloc, its entry in the table and its count happen in one
;;; critical section, and so do its removal, free and count down: an
;;; interrupt that escapes, a keyboard or timer handler that invokes a
;;; continuation, cannot fall between them and leave a block no table and no
;;; count sees, nor leave the table's mutex held.
;;;
;;; Nothing raises inside those sections. Each answers data, and the refusal
;;; it decided is raised after it: a raise inside one would reach a
;;; with-exception-handler handler with interrupts still disabled, where an
;;; engine never expires and another thread's collection waits for the
;;; handler. A raise from a call made in a section, foreign-alloc's or
;;; count-down!'s, is caught there and raised again, the same object, after
;;; it.
;;;
;;; A refusal names the value it refused by shown-value: a number as itself,
;;; a string by its kind, never its text (ADR-0013).
;;;
;;; It never loads libsqlite3.
(library (chez-sqlite3 private memory)
  (export foreign-block free-foreign-block!)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (only (chezscheme) critical-section foreign-alloc foreign-free make-mutex with-mutex)
          (chez-sqlite3 private counters)
          (chez-sqlite3 private conditions))

  ;; The live blocks, by address, each with its size, and the mutex every
  ;; read and write holds.
  (define live (make-eqv-hashtable))
  (define lock (make-mutex))

  ;; locked : Mutex (-> Any) -> Any
  ;; THUNK's value, run holding LOCK, in a critical section. Chez's
  ;; with-mutex is a dynamic-wind whose before thunk takes the mutex, so an
  ;; interrupt that escapes between the take and the wind would leave it
  ;; held, with no after thunk to release it, and block every other thread.
  ;; Every mutex here is held through locked.
  (define (locked lock thunk)
    (critical-section (with-mutex lock (thunk))))

  ;; foreign-block : Positive-Integer -> Positive-Integer
  ;; A fresh block of SIZE bytes, uninitialised, counted: its address. An
  ;; assertion violation for a SIZE that is not a positive exact integer.
  ;; foreign-alloc never answers 0: a malloc that fails is its own
  ;; assertion violation, raised again after the section, and nothing is
  ;; counted.
  (define (foreign-block size)
    (unless (and (integer? size) (exact? size) (positive? size))
      (assertion-violation 'foreign-block "a block's size is a positive exact integer"
                           (shown-value size)))
    (let ((outcome
           (critical-section
            (let ((allocated (guard (c (#t (list 'failed c)))
                               (list 'allocated (foreign-alloc size)))))
              (when (eq? (car allocated) 'allocated)
                (locked lock (lambda () (hashtable-set! live (cadr allocated) size)))
                (count-up! 'block))
              allocated))))
      (if (eq? (car outcome) 'allocated)
          (cadr outcome)
          (raise (cadr outcome)))))

  ;; free-foreign-block! : Positive-Integer -> Void
  ;; Frees the live block at ADDRESS, and counts it down. An address that
  ;; is not a live block raises an assertion violation, and nothing is
  ;; freed. A count-down that finds the count at zero is count-down!'s
  ;; double free, raised once the block is freed.
  (define (free-foreign-block! address)
    (let ((outcome
           (critical-section
            (let ((was-live (locked lock
                              (lambda ()
                                (and (hashtable-contains? live address)
                                     (begin (hashtable-delete! live address) #t))))))
              (if (not was-live)
                  '(not-live)
                  (begin
                    (foreign-free address)
                    (guard (c (#t (list 'double-free c)))
                      (count-down! 'block)
                      '(freed))))))))
      (case (car outcome)
        ((not-live)
         (assertion-violation 'free-foreign-block! "not a live block" (shown-value address)))
        ((double-free) (raise (cadr outcome)))
        (else (if #f #f))))))
