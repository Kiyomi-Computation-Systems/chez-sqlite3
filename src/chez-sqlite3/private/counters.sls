#!r6rs
;;; (chez-sqlite3 private counters): a count of every native object
;;; chez-sqlite3 holds, by kind (ADR-0005).
;;;
;;; Each count rises when an object of its kind is made, and falls when it
;;; is freed. The counts are per process. They sit behind one mutex,
;;; since two threads may each make and free objects at once. There is no
;;; reset: a suite compares the counts before and after, and
;;; (chez-sqlite3-testing)'s suite-exit-status fails a suite whose counts are
;;; not all zero at its end. They are the leak gate for native objects a Chez
;;; object held, which Valgrind sees as still reachable.
;;;
;;; Each count is read and written under the mutex, inside a critical
;;; section (locked, below): no interrupt that escapes can leave the mutex
;;; held.
;;;
;;; It never loads libsqlite3, so any suite can import it. R6RS forbids
;;; assigning an exported variable, so the counts are reached through
;;; procedures.
(library (chez-sqlite3 private counters)
  (export native-kinds count-up! count-down! native-counts)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (only (chezscheme) critical-section make-mutex with-mutex))

  ;; native-kinds : (Listof Symbol)
  ;; The kinds of native object counted, in the order native-counts
  ;; answers them:
  ;;
  ;;   block       a foreign block chez-sqlite3 allocated itself
  ;;   connection  a connection, from sqlite3_open_v2
  ;;   statement   a prepared statement, from sqlite3_prepare_v3
  (define native-kinds '(block connection statement))

  ;; The counts, one per kind, in native-kinds order, and the mutex every
  ;; read and write holds.
  (define counts (make-vector (length native-kinds) 0))
  (define lock (make-mutex))

  ;; locked : Mutex (-> Any) -> Any
  ;; THUNK's value, run holding LOCK, in a critical section. Chez's
  ;; with-mutex is a dynamic-wind whose before thunk takes the mutex, so an
  ;; interrupt that escapes between the take and the wind would leave it
  ;; held, with no after thunk to release it, and block every other thread.
  ;; Every mutex here is held through locked.
  (define (locked lock thunk)
    (critical-section (with-mutex lock (thunk))))

  ;; kind-index : Symbol Symbol -> Natural
  ;; Where KIND's count stands; an assertion violation from WHO for a
  ;; symbol that is not a kind.
  (define (kind-index who kind)
    (let loop ((kinds native-kinds) (i 0))
      (cond ((null? kinds)
             (assertion-violation who "not a kind of native object chez-sqlite3 counts" kind))
            ((eq? (car kinds) kind) i)
            (else (loop (cdr kinds) (+ i 1))))))

  ;; count-up! : Symbol -> Void
  ;; One more object of KIND.
  (define (count-up! kind)
    (let ((i (kind-index 'count-up! kind)))
      (locked lock
        (lambda () (vector-set! counts i (+ (vector-ref counts i) 1))))))

  ;; count-down! : Symbol -> Void
  ;; One object of KIND fewer. A count at zero stays at zero, and the call
  ;; raises an assertion violation: one more object freed than was made is
  ;; a double free.
  (define (count-down! kind)
    (let* ((i (kind-index 'count-down! kind))
           (was (locked lock
                  (lambda ()
                    (let ((n (vector-ref counts i)))
                      (when (> n 0)
                        (vector-set! counts i (- n 1)))
                      n)))))
      (when (= was 0)
        (assertion-violation 'count-down!
                             "more objects of this kind freed than made: a double free"
                             kind))))

  ;; native-counts : -> (Listof (Pairof Symbol Natural))
  ;; Every kind with its count, in native-kinds order, read at one moment.
  (define (native-counts)
    (let ((now (locked lock (lambda () (vector->list counts)))))
      (map cons native-kinds now))))
