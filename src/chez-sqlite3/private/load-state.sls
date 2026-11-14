#!r6rs
;;; (chez-sqlite3 private load-state): the load's first failure, kept for the
;;; life of the process (ADR-0002).
;;;
;;; (chez-sqlite3 private native)'s body is the load. Chez runs a library body
;;; that raised a serious condition again at every later reference, so
;;; without a memory each reference would load and probe afresh, and a
;;; CHEZ_SQLITE3_LIBRARY changed in between would load a second libsqlite3
;;; into the process. So every step of the load runs inside load-step, which
;;; records the first failure here, and the first definition of native's body
;;; raises a recorded failure again.
;;;
;;; After a raise of anything but a serious condition, Chez wedges the library
;;; instead: every later reference raises "cyclic dependency involving
;;; invocation of library". So load-step makes every raise serious before it
;;; records it (tests/test-load-state.sps measures both).
;;;
;;; This library's own body defines one variable and some procedures, so it
;;; cannot raise, and Chez runs it once. R6RS forbids assigning an exported
;;; variable, so the failure is reached through procedures.
(library (chez-sqlite3 private load-state)
  (export load-failure record-load-failure! as-serious load-step)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (chez-sqlite3 private conditions))

  ;; The first failure, or #f.
  (define failure #f)

  ;; load-failure : -> (U Condition #f)
  ;; The load's first failure, a serious condition, or #f when none is
  ;; recorded.
  (define (load-failure) failure)

  ;; record-load-failure! : Condition -> Void
  ;; Records C as the load's failure, unless one is recorded already: the
  ;; first stays. C must be serious, since it will be raised again from a
  ;; library body; anything else is an assertion violation.
  (define (record-load-failure! c)
    (unless (serious-condition? c)
      (assertion-violation 'record-load-failure!
                           "only a serious condition may be recorded as the load's failure"
                           c))
    (unless failure
      (set! failure c)))

  ;; as-serious : Any -> Condition
  ;; OBJ when it is a serious condition. Anything else, a symbol, a number,
  ;; a &warning or a bare &message, comes back as a &chez-sqlite3-error from
  ;; chez-sqlite3 whose one irritant is OBJ.
  (define (as-serious obj)
    (if (serious-condition? obj)
        obj
        (condition (make-chez-sqlite3-error)
                   (make-who-condition 'chez-sqlite3)
                   (make-message-condition
                    "loading libsqlite3 raised something other than a serious condition")
                   (make-irritants-condition (list obj)))))

  ;; load-step : Expr[A] -> A   (syntax)
  ;; (load-step EXPR): EXPR's value. When EXPR raises, the raised object is
  ;; made serious with as-serious, recorded with record-load-failure!, and
  ;; raised again.
  (define-syntax load-step
    (syntax-rules ()
      ((_ expr)
       (guard (e (#t (let ((c (as-serious e)))
                       (record-load-failure! c)
                       (raise c))))
         expr)))))
