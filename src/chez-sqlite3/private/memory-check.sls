#!r6rs
;;; (chez-sqlite3 private memory-check): the sqlite3_memory_used check a
;;; suite's end runs, with its positive control (ADR-0005, decision 5 and the
;;; amendment for a library that keeps no memory count).
;;;
;;; The baseline is the count once libsqlite3 is loaded and initialised,
;;; before anything is opened: (chez-sqlite3 private native) reads it there,
;;; makes the check with it and registers the check with the counters. At a
;;; suite's end, every connection closed, SQLite must hold what it held then.
;;; Measured on Guix's 3.53.1 and a 3.45.1 built from the amalgamation: 0 once
;;; loaded, and back at 0 after every open and close, of :memory:, of a WAL
;;; file with a query, and of a failed open alike.
;;;
;;; A build with SQLITE_DEFAULT_MEMSTATUS=0, as Apple's is, answers 0 always,
;;; and a check of it would pass without testing anything. So the check opens
;;; a :memory: connection of its own, the control, and reads the count while
;;; it is open: a count that did not rise means the library keeps none, and
;;; the check is unavailable, never a pass. Read, not the compile option,
;;; which sqlite3_config could override at run time. A suite that opens
;;; nothing still runs the control.
;;;
;;;   memory-check-outcome  the verdict, from the counts: pure
;;;   make-memory-check     the check, given native's bindings: the shell
;;;
;;; It imports no native binding: native imports it, and hands it the ones
;;; the control calls, so a suite runs the control on stubs.
(library (chez-sqlite3 private memory-check)
  (export memory-check-outcome make-memory-check)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (only (chez-sqlite3 private constants)
                sqlite-open-readwrite sqlite-open-create sqlite-result-codes))

  (define sqlite-ok (cdr (assq 'ok sqlite-result-codes)))

  ;; The control opens :memory: read-write and create, as open-database does
  ;; by default, and with no other flag.
  (define control-flags (bitwise-ior sqlite-open-readwrite sqlite-open-create))

  ;; memory-check-outcome : Integer Integer Integer Integer -> (List Symbol String)
  ;; The verdict from BASELINE, the count once libsqlite3 was loaded, and the
  ;; counts the control read: BEFORE its open, while it was OPEN, and AFTER
  ;; its close:
  ;;   (unavailable TEXT)  OPEN is not above BEFORE: the library keeps no count
  ;;   (pass TEXT)         else AFTER is BASELINE
  ;;   (fail TEXT)         else: SQLite holds more, or less, than it did
  ;; TEXT names the counts that decided it.
  (define (memory-check-outcome baseline before open after)
    (cond
      ((<= open before)
       (list 'unavailable
             (string-append "the count was " (number->string before)
                            " bytes before the control's :memory: open and " (number->string open)
                            " while it was open, so this libsqlite3 keeps no memory count")))
      ((= after baseline)
       (list 'pass
             (string-append "the count is back at its baseline, " (number->string baseline)
                            " bytes, after the control's :memory: open and close")))
      (else
       (list 'fail
             (string-append "the count is " (number->string after)
                            " bytes after the control's :memory: open and close, not its baseline, "
                            (number->string baseline)
                            " bytes: SQLite still holds memory that a suite's end must have freed")))))

  ;; make-memory-check : Integer (-> Integer)
  ;;                     (Symbol String (Natural -> A) -> A)
  ;;                     (Symbol (Natural -> B) -> (Values B Natural))
  ;;                     (Natural Natural Integer Natural -> Integer)
  ;;                     (Natural -> Integer)
  ;;                     -> (-> (List Symbol String))
  ;; The check against BASELINE, through native's sqlite3-memory-used,
  ;; call-with-c-string, call-with-out-pointer, sqlite3-open-v2 and
  ;; sqlite3-close. Each call runs the control afresh: the count, the open of
  ;; :memory:, the count while open, the close, the count after, each after
  ;; the one before; then memory-check-outcome. A control whose open fails
  ;; closes the handle it was given, if any, reads no more, and fails, naming
  ;; the code; one whose close fails fails, naming that code.
  (define (make-memory-check baseline memory-used with-c-string with-out-pointer open-v2 close)
    (lambda ()
      (let* ((before (memory-used))
             (opened (with-c-string 'memory-check ":memory:"
                       (lambda (name)
                         (call-with-values
                          (lambda ()
                            (with-out-pointer 'memory-check
                              (lambda (slot) (open-v2 name slot control-flags 0))))
                          cons))))
             (rc (car opened))
             (handle (cdr opened)))
        (cond
          ((eqv? handle 0)
           (list 'fail (string-append "the control's open of :memory: answered code "
                                      (number->string rc) " and no handle")))
          ((not (eqv? rc sqlite-ok))
           (close handle)
           (list 'fail (string-append "the control's open of :memory: answered code "
                                      (number->string rc))))
          (else
           (let* ((open (memory-used))
                  (closed (close handle))
                  (after (memory-used)))
             (if (eqv? closed sqlite-ok)
                 (memory-check-outcome baseline before open after)
                 (list 'fail (string-append "the control's close of :memory: answered code "
                                            (number->string closed)))))))))))
