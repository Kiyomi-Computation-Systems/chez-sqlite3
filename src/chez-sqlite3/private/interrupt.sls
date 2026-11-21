#!r6rs
;;; (chez-sqlite3 private interrupt): the exclusion between
;;; interrupt-database!, the one verb any thread may call, and the close
;;; (ADR-0019). SQLite calls sqlite3_interrupt unsafe on a connection that is
;;; closed, or might close before it returns, so no interrupt may be in
;;; flight once sqlite3_close starts, and none may start after.
;;;
;;; A latch is the state the connection record keeps for it: a mutex, and a
;;; flag that says the connection is interruptible. The procedures here take
;;; the foreign calls as arguments, so a suite runs them on stand-ins:
;;;
;;;   the open       interrupt-latch-open!: sets the flag, once the record
;;;                  exists
;;;   the interrupt  interrupt-latch-interrupt!: in one critical section,
;;;                  takes the mutex, calls its INTERRUPT only if the flag is
;;;                  set, and lets the mutex go
;;;   the close      interrupt-latch-close!: in one critical section, takes
;;;                  the mutex, clears the flag and lets it go; then does its
;;;                  WORK, the finalizes and sqlite3_close, with the mutex
;;;                  released; then, when the work left the connection open,
;;;                  sets the flag again the same way
;;;   the shut       interrupt-latch-shut!: in one critical section, takes
;;;                  the mutex, reads the flag, clears it and lets it go;
;;;                  then does its WORK with the mutex released; then puts
;;;                  the flag back as it read it, the same way, whatever the
;;;                  work did. with-transaction's exits use it, so an
;;;                  interrupt sent while their ROLLBACK, or ROLLBACK TO and
;;;                  RELEASE, runs is dropped
;;;
;;; The interrupt calls INTERRUPT holding the mutex, and the close clears the
;;; flag holding it, so an interrupt in flight when the close begins ends
;;; before the flag is cleared, and none starts after: none is in flight once
;;; the work starts.
;;;
;;; The mutex is held only inside a critical section, for constant time:
;;; across one read or write of the flag, and across INTERRUPT, which is
;;; sqlite3_interrupt, bound plain, which only sets SQLite's own interrupt
;;; flag on the connection and returns. Never across the close's work, which
;;; can write a checkpoint, nor the shut's, which steps a statement. A
;;; section keeps out only this thread's engines, timers and interrupts: the
;;; mutex is the exclusion between threads, and the section keeps this thread
;;; from being stopped, by an engine's expiry above all, between reading the
;;; flag and calling INTERRUPT, or while it holds the mutex.
;;;
;;; Nothing raises inside a section here. A raise from INTERRUPT, from the
;;; close's WORK or from its LEFT-OPEN?, or from the shut's WORK, is caught
;;; inside, and raised again after the section with raise, the same object,
;;; so it cannot be resumed. The flag stays clear after a raise from the
;;; close's work or the predicate: a close that did not say the connection
;;; is open never makes it interruptible. After a raise from the shut's
;;; work it is put back, as after its answer: the shut closes nothing. No
;;; argument is checked: these are private, given the record's own latch and
;;; the library's own procedures.
(library (chez-sqlite3 private interrupt)
  (export make-interrupt-latch interrupt-latch-open! interrupt-latch-interrupt!
          interrupt-latch-close! interrupt-latch-shut!)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (only (chezscheme) critical-section make-mutex with-mutex))

  ;; The latch: its mutex, and whether its connection is interruptible.
  ;; Sealed and opaque, as the connection record that holds it is.
  (define-record-type (interrupt-latch new-interrupt-latch interrupt-latch?)
    (fields (immutable mutex latch-mutex)
            (mutable interruptible latch-interruptible set-latch-interruptible!))
    (sealed #t)
    (opaque #t))

  ;; make-interrupt-latch : -> Interrupt-Latch
  ;; A latch whose connection is not interruptible yet: the open makes it so.
  (define (make-interrupt-latch)
    (new-interrupt-latch (make-mutex) #f))

  ;; set-interruptible! : Interrupt-Latch Boolean -> Void
  ;; LATCH's flag set to ON?, holding its mutex, in a critical section.
  (define (set-interruptible! latch on?)
    (critical-section
     (with-mutex (latch-mutex latch)
       (set-latch-interruptible! latch on?))))

  ;; interrupt-latch-open! : Interrupt-Latch -> Void
  ;; LATCH's connection interruptible: the open calls it once the record
  ;; exists (ADR-0019).
  (define (interrupt-latch-open! latch)
    (set-interruptible! latch #t))

  ;; interrupt-latch-interrupt! : Interrupt-Latch (-> Any) -> Boolean
  ;; In one critical section, holding LATCH's mutex: INTERRUPT called when
  ;; the flag is set, its answer dropped. #t when it was called, #f when the
  ;; connection is closed or closing, which is no error (ADR-0019). A raise
  ;; from INTERRUPT is raised after the section, the same object.
  (define (interrupt-latch-interrupt! latch interrupt)
    (let ((outcome
           (critical-section
            (with-mutex (latch-mutex latch)
              (if (latch-interruptible latch)
                  (guard (c (#t (list 'raised c)))
                    (interrupt)
                    '(called))
                  '(not-interruptible))))))
      (case (car outcome)
        ((called) #t)
        ((not-interruptible) #f)
        (else (raise (cadr outcome))))))

  ;; interrupt-latch-close! : Interrupt-Latch (-> A) (A -> Any) -> A
  ;; WORK's answer. In one critical section: LATCH's flag cleared, holding
  ;; its mutex; then WORK called, with the mutex released; then, when
  ;; (LEFT-OPEN? answer) is true, the flag set again, holding the mutex.
  ;; WORK is the close's: the finalizes and sqlite3_close, answering data. A
  ;; raise from WORK or from LEFT-OPEN? leaves the flag clear, and is raised
  ;; after the section, the same object.
  (define (interrupt-latch-close! latch work left-open?)
    (let ((outcome
           (critical-section
            (set-interruptible! latch #f)
            (guard (c (#t (list 'raised c)))
              (let ((answer (work)))
                (when (left-open? answer)
                  (set-interruptible! latch #t))
                (list 'answered answer))))))
      (if (eq? (car outcome) 'answered)
          (cadr outcome)
          (raise (cadr outcome)))))

  ;; interrupt-latch-shut! : Interrupt-Latch (-> A) -> A
  ;; WORK's answer. In one critical section: LATCH's flag read and cleared,
  ;; holding its mutex; then WORK called, with the mutex released, so an
  ;; interrupt tried meanwhile calls nothing and waits for nothing; then the
  ;; flag put back as it was read, holding the mutex. A raise from WORK puts
  ;; it back too, and is raised after the section, the same object. WORK is
  ;; with-transaction's ROLLBACK, or ROLLBACK TO then RELEASE, answering
  ;; data. The flag put back is the one read, never set: a shut of a
  ;; connection not interruptible, closed, closing, or inside another shut,
  ;; leaves it so.
  (define (interrupt-latch-shut! latch work)
    (let ((outcome
           (critical-section
            (let* ((found (critical-section
                           (with-mutex (latch-mutex latch)
                             (let ((was (latch-interruptible latch)))
                               (set-latch-interruptible! latch #f)
                               was))))
                   (answer (guard (c (#t (list 'raised c)))
                             (list 'answered (work)))))
              (set-interruptible! latch found)
              answer))))
      (if (eq? (car outcome) 'answered)
          (cadr outcome)
          (raise (cadr outcome))))))
