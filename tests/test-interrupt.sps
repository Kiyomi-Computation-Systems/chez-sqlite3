#!r6rs
;;; The suite for (chez-sqlite3 private interrupt): the exclusion between
;;; interrupt-database!, which any thread may call, and close-database!
;;; (ADR-0019, decisions 2 to 4; the M3 plan, section 4.4). The latch is a
;;; mutex and an interruptible flag; slice 6 puts one in the connection
;;; record. Its procedures take the foreign calls as arguments, so this
;;; suite runs them on stand-ins, with no libsqlite3:
;;;
;;;   the interrupt  in one critical section, holding the mutex, calls its
;;;                  stand-in only while the flag is set
;;;   the close      clears the flag under the mutex before its work, does
;;;                  the work with the mutex released, and sets the flag
;;;                  again when the work left the connection open
;;;   the open       sets the flag
;;;
;;; The rows:
;;;
;;;   one thread     the flag's life: a fresh latch, the open, a close that
;;;                  closed, a close that left the connection open, on both
;;;                  of slice 6's paths; the flag clear while the work runs;
;;;                  the close's answer and its calls
;;;   raises         a stand-in's raise, a work's and a predicate's, each
;;;                  raised after the section, the very object, to a handler
;;;                  at interrupt depth 1, and never resumed
;;;   engines        at every fuel, an interrupt split by an expiry never
;;;                  calls its stand-in after a close that ran in the gap;
;;;                  a close abandoned at an expiry ran all or nothing
;;;   two threads    the race the record exists for: an interrupt in flight
;;;                  when the close begins ends before the close's work
;;;                  starts, an interrupt tried during the work calls
;;;                  nothing and does not wait for the work to end
;;;
;;; Every wait is bounded: condition-wait with a timeout against a deadline,
;;; and a thread is joined only once it has answered. A thread's raise is its
;;; answer. Effects are ordered by let* and for-each, never by a call's
;;; arguments. SRFI-64 turns a raise in the actual expression into #f, so
;;; no expected value is #f: an answer of #f is read as none.
(import (rnrs)
        (rnrs records inspection)
        (srfi :64)
        (only (chezscheme) library-exports fork-thread thread-join make-mutex with-mutex
              make-condition condition-wait condition-broadcast make-time current-time
              time-difference add-duration time>=? make-engine critical-section
              disable-interrupts enable-interrupts)
        (chez-sqlite3-testing)
        (chez-sqlite3 private interrupt))

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

;; sorted-names : (Listof Symbol) -> (Listof Symbol)
(define (sorted-names names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

;; iota-from : Natural Natural -> (Listof Natural)
;; FROM to TO, both included.
(define (iota-from from to)
  (let loop ((i to) (acc '()))
    (if (< i from) acc (loop (- i 1) (cons i acc)))))

;; none-if-false : Any -> Any
(define (none-if-false x) (if (eq? x #f) 'none x))

;; answer-of : (-> Any) -> Any
;; THUNK's answer, #f as none, or (raised TEXT).
(define (answer-of thunk)
  (guard (e (#t (list 'raised (describe e)))) (none-if-false (thunk))))

;; spin : Natural -> Void
;; N turns of a loop, each a tick an engine counts outside a critical
;; section.
(define (spin n) (let loop ((i 0)) (when (< i n) (loop (+ i 1)))))

;; counter : -> (Values (-> Void) (-> Natural))
;; A stand-in that counts its calls, and a reader of the count.
(define (counter)
  (let ((n 0))
    (values (lambda () (set! n (+ n 1))) (lambda () n))))

;; an-opened-latch : -> Interrupt-Latch
(define (an-opened-latch)
  (let ((latch (make-interrupt-latch)))
    (interrupt-latch-open! latch)
    latch))

;; interruptible? : Interrupt-Latch -> (U 'interruptible 'not-interruptible (raised ...))
;; Whether an interrupt now calls its stand-in, read by calling one that
;; counts: interruptible when it was called once, as interrupt-latch-interrupt!
;; answered #t.
(define (interruptible? latch)
  (let-values (((stand-in calls) (counter)))
    (let* ((answer (answer-of (lambda () (interrupt-latch-interrupt! latch stand-in))))
           (n (calls)))
      (cond ((and (eq? answer #t) (= n 1)) 'interruptible)
            ((and (eq? answer 'none) (= n 0)) 'not-interruptible)
            (else (list 'inconsistent answer n))))))

;; interrupt-depth : -> Positive-Integer
;; How many critical sections this thread is inside, plus one: what
;; disable-interrupts answers, put back at once. 1 outside any section.
(define (interrupt-depth)
  (let ((n (disable-interrupts)))
    (enable-interrupts)
    n))

;; handler-depth : (-> Any) Any -> (U (List 'raised-at-depth Symbol Symbol) (List 'no-raise Any))
;; The depth a with-exception-handler handler runs at for the first thing
;; THUNK raises, read before anything else, as depth-N, and whether that is
;; the very object EXPECTED; the handler escapes, so nothing returns into
;; the raise. (no-raise VALUE) when THUNK raises nothing.
(define (handler-depth thunk expected)
  (call/cc
   (lambda (k)
     (with-exception-handler
      (lambda (c)
        (let ((depth (interrupt-depth)))
          (k (list 'raised-at-depth
                   (string->symbol (string-append "depth-" (number->string depth)))
                   (if (eq? c expected) 'the-very-object 'another-object)))))
      (lambda () (list 'no-raise (thunk)))))))

;; resumed? : (-> Any) -> Symbol
;; Whether a handler that returns resumes THUNK's raise: non-continuable
;; when R6RS refuses it, returned when THUNK returned instead.
(define (resumed? thunk)
  (guard (e ((non-continuable-violation? e) 'non-continuable)
            (#t (list 'other-raise (describe e))))
    (with-exception-handler (lambda (c) 'handled) thunk)
    'returned))

(test-begin "interrupt")

(test-equal "(chez-sqlite3 private interrupt) exports exactly the latch's four procedures"
  '(interrupt-latch-close! interrupt-latch-interrupt! interrupt-latch-open! make-interrupt-latch)
  (guard (e (#t (list 'raised (describe e))))
    (sorted-names (library-exports '(chez-sqlite3 private interrupt)))))

(test-equal "a latch works, and is opaque, as the connection record holding it is: no record to record?, and record-rtd refuses it"
  '(interruptible not-a-record refused)
  (let ((latch (an-opened-latch)))
    (list (interruptible? latch)
          (if (guard (e (#t 'raised)) (record? latch)) 'a-record 'not-a-record)
          (guard (e (#t 'refused)) (record-rtd latch) 'an-rtd))))

;; --- the flag's life, on one thread --------------------------------------------------------

(test-equal "a fresh latch is not interruptible: an interrupt calls nothing and answers none; the open makes it interruptible, and each interrupt then calls its stand-in once and answers #t"
  '(none 0 #t 1 #t 2)
  (let-values (((stand-in calls) (counter)))
    (let* ((latch (make-interrupt-latch))
           (before (answer-of (lambda () (interrupt-latch-interrupt! latch stand-in))))
           (calls-before (calls))
           (opened (begin (interrupt-latch-open! latch) 'opened))
           (first (answer-of (lambda () (interrupt-latch-interrupt! latch stand-in))))
           (calls-first (calls))
           (second (answer-of (lambda () (interrupt-latch-interrupt! latch stand-in))))
           (calls-second (calls)))
      (list before calls-before first calls-first second calls-second))))

(test-equal "an interrupt on a latch whose close closed the connection does nothing and raises nothing, however often, and a second close changes nothing"
  '(not-interruptible not-interruptible not-interruptible not-interruptible)
  (let* ((latch (an-opened-latch))
         (closed (interrupt-latch-close! latch (lambda () '(closed)) (lambda (outcome) #f)))
         (first (interruptible? latch))
         (second (interruptible? latch))
         (third (interruptible? latch))
         (again (interrupt-latch-close! latch (lambda () '(already-closed)) (lambda (outcome) #f)))
         (fourth (interruptible? latch)))
    (list first second third fourth)))

;; left-open? : (List Symbol Any ...) -> Boolean
;; Slice 6's reading of its close's outcome: a statement found untracked, or
;; sqlite3_close failing, leaves the connection open (ADR-0019, decision 2).
(define (left-open? outcome) (and (memq (car outcome) '(untracked failed)) #t))

(test-equal "a close is told whether it left the connection open by its predicate: untracked and failed, slice 6's two paths, leave the latch interruptible; closed, finalize-failed and already-closed do not"
  '(interruptible interruptible not-interruptible not-interruptible not-interruptible)
  (map (lambda (outcome)
         (let ((latch (an-opened-latch)))
           (interrupt-latch-close! latch (lambda () outcome) left-open?)
           (interruptible? latch)))
       (list '(untracked 1) '(failed 5 "unable to close") '(closed) '(finalize-failed c)
             '(already-closed))))

(test-equal "a failed close leaves the latch interruptible each time, and a close that then succeeds clears it: failed, failed, closed"
  '(interruptible interruptible not-interruptible)
  (let* ((latch (an-opened-latch))
         (one (begin (interrupt-latch-close! latch (lambda () '(failed 5 "m")) left-open?)
                     (interruptible? latch)))
         (two (begin (interrupt-latch-close! latch (lambda () '(untracked 2)) left-open?)
                     (interruptible? latch)))
         (three (begin (interrupt-latch-close! latch (lambda () '(closed)) left-open?)
                       (interruptible? latch))))
    (list one two three)))

(test-equal "a close of a latch never opened leaves it not interruptible when it closes, and interruptible when it is left open"
  '(not-interruptible interruptible)
  (let ((a (make-interrupt-latch)) (b (make-interrupt-latch)))
    (interrupt-latch-close! a (lambda () '(closed)) left-open?)
    (interrupt-latch-close! b (lambda () '(failed 5 "m")) left-open?)
    (list (interruptible? a) (interruptible? b))))

(test-equal "the close answers its work's answer, the very object; it calls the work once and its predicate once, after the work, with that answer"
  '(the-very-object (work (left-open? the-very-object)))
  (let* ((latch (an-opened-latch))
         (outcome (list 'failed 5 "m"))
         (calls '())
         (answer (interrupt-latch-close!
                  latch
                  (lambda () (set! calls (cons 'work calls)) outcome)
                  (lambda (a)
                    (set! calls (cons (list 'left-open? (if (eq? a outcome) 'the-very-object a))
                                      calls))
                    #t))))
    (list (if (eq? answer outcome) 'the-very-object answer) (reverse calls))))

(test-equal "the flag is clear while the close's work runs: an interrupt tried inside the work calls nothing, whether the close then leaves the connection open or closes it"
  '((not-interruptible interruptible) (not-interruptible not-interruptible))
  (map (lambda (outcome)
         (let* ((latch (an-opened-latch))
                (during #f))
           (interrupt-latch-close! latch
                                   (lambda () (set! during (interruptible? latch)) outcome)
                                   left-open?)
           (list during (interruptible? latch))))
       (list '(failed 5 "m") '(closed))))

(test-equal "the open of an open latch keeps it interruptible, and an open after a close that closed makes it interruptible again"
  '(interruptible interruptible)
  (let* ((a (an-opened-latch))
         (one (begin (interrupt-latch-open! a) (interruptible? a)))
         (b (an-opened-latch))
         (two (begin (interrupt-latch-close! b (lambda () '(closed)) left-open?)
                     (interrupt-latch-open! b)
                     (interruptible? b))))
    (list one two)))

;; --- raises: after the section, the very object, never resumed ---------------------------------

(test-equal "a stand-in's raise reaches the caller's handler at interrupt depth 1, the very object, and the latch stays interruptible"
  '((raised-at-depth depth-1 the-very-object) interruptible)
  (let* ((latch (an-opened-latch))
         (c (make-error))
         (raised (handler-depth (lambda () (interrupt-latch-interrupt! latch (lambda () (raise c)))) c)))
    (list raised (interruptible? latch))))

(test-equal "a raise of a non-condition from a stand-in reaches the caller as the very object, at depth 1"
  '(raised-at-depth depth-1 the-very-object)
  (let ((latch (an-opened-latch)) (x (list 'not-a-condition)))
    (handler-depth (lambda () (interrupt-latch-interrupt! latch (lambda () (raise x)))) x)))

(test-equal "a work's raise reaches the caller's handler at interrupt depth 1, the very object, and leaves the latch not interruptible, whatever its predicate would say"
  '((raised-at-depth depth-1 the-very-object) not-interruptible)
  (let* ((latch (an-opened-latch))
         (c (make-error))
         (raised (handler-depth (lambda ()
                                  (interrupt-latch-close! latch (lambda () (raise c))
                                                          (lambda (a) #t)))
                                c)))
    (list raised (interruptible? latch))))

(test-equal "a predicate's raise reaches the caller's handler at interrupt depth 1, the very object, and leaves the latch not interruptible"
  '((raised-at-depth depth-1 the-very-object) not-interruptible)
  (let* ((latch (an-opened-latch))
         (c (make-error))
         (raised (handler-depth (lambda ()
                                  (interrupt-latch-close! latch (lambda () '(failed 5 "m"))
                                                          (lambda (a) (raise c))))
                                c)))
    (list raised (interruptible? latch))))

(test-equal "no raise is resumed: a stand-in's, a work's or a predicate's raise-continuable, whose handler returns, gets the &non-continuable R6RS raises for it"
  '(non-continuable non-continuable non-continuable)
  (map resumed?
       (list (lambda ()
               (interrupt-latch-interrupt! (an-opened-latch)
                                           (lambda () (raise-continuable (make-warning)))))
             (lambda ()
               (interrupt-latch-close! (an-opened-latch)
                                       (lambda () (raise-continuable (make-warning)))
                                       (lambda (a) #t)))
             (lambda ()
               (interrupt-latch-close! (an-opened-latch) (lambda () '(closed))
                                       (lambda (a) (raise-continuable (make-warning))))))))

(test-equal "inside a caller's critical section, as slice 6's close and open call them, the procedures do the same and leave the caller's depth as it was"
  '(not-interruptible interruptible 2)
  (critical-section
   (let* ((latch (an-opened-latch))
          (closed (begin (interrupt-latch-close! latch (lambda () '(closed)) left-open?)
                         (interruptible? latch)))
          (reopened (begin (interrupt-latch-open! latch) (interruptible? latch))))
     (list closed reopened (interrupt-depth)))))

;; --- engines: an expiry splits nothing ------------------------------------------------------
;; An engine spends no ticks inside a critical section (.plans/traps.md), and
;; an expiry runs a dynamic-wind's after thunk, so it lets go of a mutex that
;; with-mutex holds, and the resume takes it again. So each outcome is
;; asserted at every fuel, never an expiry at a given one.
;;
;; The fuels are 1 to 10. On Chez 10.4.0 the correct code expires before its
;; section up to fuel 3 and completes from fuel 4, and the mutants without a
;; section fail from fuel 4 and 5 (the slice's mutation log); the rest is
;; margin for a build whose calls cost other ticks. Each row also asserts
;; that both outcomes are seen, so a boundary that moved past 10 fails the
;; row rather than leaving it vacuous.

;; interrupt-split-at : Positive-Integer -> (Listof Symbol)
;; An interrupt of an opened latch run in an engine of FUEL ticks, its
;; stand-in noting its start, spinning, then noting its end. At the engine's
;; first expiry a close runs, noting its work, then the engine is resumed to
;; its end; an engine that completes first is followed by the same close.
;; The notes, in order.
(define (interrupt-split-at fuel)
  (let* ((latch (an-opened-latch))
         (notes '())
         (note! (lambda (n) (set! notes (cons n notes))))
         (close! (lambda ()
                   (interrupt-latch-close! latch (lambda () (note! 'work) '(closed)) left-open?))))
    ((make-engine (lambda ()
                    (interrupt-latch-interrupt! latch
                                                (lambda ()
                                                  (note! 'interrupt-start)
                                                  (spin 200)
                                                  (note! 'interrupt-end)))))
     fuel
     (lambda (left . answers) (close!))
     (lambda (next)
       (close!)
       (next 100000000 (lambda (left . answers) 'resumed) (lambda (again) 'expired-again))))
    (reverse notes)))

(test-equal "an interrupt in an engine, at every fuel from 1 to 10, a close run at its expiry: the stand-in ran whole before the close's work, or not at all, never after it; both are seen"
  '(() #t #t)
  (let* ((runs (map (lambda (fuel) (cons fuel (interrupt-split-at fuel))) (iota-from 1 10)))
         (whole '(interrupt-start interrupt-end work))
         (none '(work)))
    (list (filter (lambda (run) (not (or (equal? (cdr run) whole) (equal? (cdr run) none)))) runs)
          (exists (lambda (run) (equal? (cdr run) whole)) runs)
          (exists (lambda (run) (equal? (cdr run) none)) runs))))

;; close-abandoned-at : Positive-Integer -> (List (Listof Symbol) Symbol)
;; A close of an opened latch, its work noting its start, spinning, noting
;; its end, and its predicate saying left open, run in an engine of FUEL
;; ticks, abandoned at its first expiry: the notes, and whether the latch is
;; interruptible then.
(define (close-abandoned-at fuel)
  (let* ((latch (an-opened-latch))
         (notes '())
         (note! (lambda (n) (set! notes (cons n notes)))))
    ((make-engine (lambda ()
                    (interrupt-latch-close! latch
                                            (lambda ()
                                              (note! 'work-start)
                                              (spin 200)
                                              (note! 'work-end)
                                              '(failed 5 "m"))
                                            left-open?)))
     fuel
     (lambda (left . answers) 'completed)
     (lambda (next) 'abandoned))
    (list (reverse notes) (interruptible? latch))))

(test-equal "a close that leaves the connection open, in an engine abandoned at its first expiry, at every fuel from 1 to 10: nothing ran and the latch is interruptible, or the whole close ran and it is interruptible again; both are seen"
  '(() #t #t)
  (let* ((runs (map (lambda (fuel) (cons fuel (close-abandoned-at fuel))) (iota-from 1 10)))
         (whole '((work-start work-end) interruptible))
         (none '(() interruptible)))
    (list (filter (lambda (run) (not (or (equal? (cdr run) whole) (equal? (cdr run) none)))) runs)
          (exists (lambda (run) (equal? (cdr run) whole)) runs)
          (exists (lambda (run) (equal? (cdr run) none)) runs))))

;; --- two threads: the race the latch exists for ---------------------------------------------

;; duration : Natural -> Time
;; MS milliseconds as a time-duration, its nanoseconds below 10^9.
(define (duration ms)
  (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000)))

;; await : Mutex Condition (-> Boolean) Natural -> Boolean
;; With MUTEX held: wait on CONDITION until READY? holds, #t, or MS
;; milliseconds have passed, #f. Every wait is bounded by the deadline.
(define (await mutex condition ready? ms)
  (let ((deadline (add-duration (current-time 'time-monotonic) (duration ms))))
    (let loop ()
      (let ((now (current-time 'time-monotonic)))
        (cond ((ready?) #t)
              ((time>=? now deadline) #f)
              (else (condition-wait condition mutex (time-difference deadline now))
                    (loop)))))))

;; start-thread : (-> Any) -> (Natural -> Any)
;; THUNK run on a thread of its own. Its answer, or (raised TEXT) for what it
;; raised, is the thread's answer. Answers a procedure that waits up to MS
;; milliseconds for that answer, joins the thread once it has answered and
;; answers it, or answers unfinished, joining nothing.
(define (start-thread thunk)
  (let* ((m (make-mutex))
         (c (make-condition))
         (done #f)
         (answer 'unfinished)
         (thread (fork-thread
                  (lambda ()
                    (let ((a (guard (e (#t (list 'raised (describe e)))) (thunk))))
                      (with-mutex m
                        (set! answer a)
                        (set! done #t)
                        (condition-broadcast c)))))))
    (lambda (ms)
      (if (with-mutex m (await m c (lambda () done) ms))
          (begin (thread-join thread) (with-mutex m answer))
          'unfinished))))

;; The waits: in-flight, the stand-in's wait for the close's work to start,
;; elapses whole when the latch is right, so it is short; the others elapse
;; only when something is wrong.
(define in-flight-ms 200)
(define long-ms 5000)
(define answer-ms 15000)

;; race : -> (List (Listof Symbol) Any Any Any Symbol)
;; Three threads on an opened latch, with one board of notes:
;;   - the interrupter calls interrupt-latch-interrupt!, whose stand-in notes
;;     its start, says it is in flight, waits up to long-ms for the closer to
;;     say it is calling close, and only then up to in-flight-ms for the
;;     close's work to start, then notes its end, so how long the closer
;;     takes to get to its close changes nothing;
;;   - the closer waits for the stand-in to be in flight, says it is calling
;;     close, just before it does, and closes, its work noting its start,
;;     asking the late interrupter to try now, and waiting for that try to
;;     end before it notes its own end; its predicate says closed;
;;   - the late interrupter waits to be asked, then calls
;;     interrupt-latch-interrupt!, whose stand-in notes late-interrupt, and
;;     says its try has ended.
;; The notes, in order; the three threads' answers, #f as none; and whether
;; the latch is interruptible after them.
(define (race)
  (let* ((latch (an-opened-latch))
         (m (make-mutex))
         (c (make-condition))
         (notes '())
         (in-flight #f)
         (calling-close #f)
         (work-started #f)
         (try-now #f)
         (try-ended #f)
         (note! (lambda (n) (set! notes (cons n notes))))
         (interrupter
          (start-thread
           (lambda ()
             (interrupt-latch-interrupt!
              latch
              (lambda ()
                (with-mutex m
                  (note! 'interrupt-start)
                  (set! in-flight #t)
                  (condition-broadcast c)
                  (await m c (lambda () calling-close) long-ms)
                  (await m c (lambda () work-started) in-flight-ms)
                  (note! 'interrupt-end)))))))
         (closer
          (start-thread
           (lambda ()
             (with-mutex m (await m c (lambda () in-flight) long-ms))
             (with-mutex m
               (set! calling-close #t)
               (condition-broadcast c))
             (interrupt-latch-close!
              latch
              (lambda ()
                (with-mutex m
                  (note! 'work-start)
                  (set! work-started #t)
                  (set! try-now #t)
                  (condition-broadcast c)
                  (note! (if (await m c (lambda () try-ended) long-ms)
                             'work-end
                             'work-end-with-the-try-unended)))
                'closed)
              (lambda (outcome) #f)))))
         (late
          (start-thread
           (lambda ()
             (with-mutex m (await m c (lambda () try-now) long-ms))
             (let ((answer (interrupt-latch-interrupt!
                            latch
                            (lambda () (with-mutex m (note! 'late-interrupt))))))
               (with-mutex m
                 (set! try-ended #t)
                 (condition-broadcast c))
               answer))))
         (interrupted (interrupter answer-ms))
         (closed (closer answer-ms))
         (late-answer (late answer-ms)))
    (list (with-mutex m (reverse notes)) (none-if-false interrupted) (none-if-false closed)
          (none-if-false late-answer) (interruptible? latch))))

(test-equal "two threads against a close on a third: the interrupt in flight when the close began ended before the close's work started; the one tried during the work called nothing and ended before the work did; the latch ends not interruptible"
  '((interrupt-start interrupt-end work-start work-end) #t closed none not-interruptible)
  (race))

(test-end "interrupt")

(exit (suite-exit-status runner))
