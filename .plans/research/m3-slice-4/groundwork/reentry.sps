#!r6rs
;;; reentry.sps: the Chez behaviour with-transaction's exits rest on, which
;;; the M3 plan cites to its reviews (H1; section 4.2's re-entries) and the
;;; research holds no file for. No SQLite: a stand-in body and winders.
;;;
;;;   $CHEZ --program reentry.sps
;;;
;;; Each case logs every before and after thunk run, and the body's events,
;;; in order, through let* and explicit sequencing (AGENTS.md).
;;;
;;;   H1    a guard whose clauses don't match, inside one that catches
;;;         everything, around a dynamic-wind whose before thunk refuses a
;;;         second entry, and around one whose before thunk lets it through
;;;   L     a raise-continuable that an outer handler returns from, past a
;;;         non-matching guard: the body resumed after its first exit
;;;   K     a continuation captured in the body, called after the wind
;;;         returned: the body returns again
;;;   E     an engine around the wind, at fuels 1 to 10: its expiries
(import (chezscheme))

(define events-log '())
(define (note! x) (set! events-log (cons x events-log)))
(define (take-log!) (let ((l (reverse events-log))) (set! events-log '()) l))

;; permissive : (-> Any) -> Any
;; M2's shape: a plain dynamic-wind whose before thunk does nothing.
(define (permissive body)
  (dynamic-wind
    (lambda () (note! 'before))
    body
    (lambda () (note! 'after))))

;; refusing : (-> Any) -> Any
;; A draft's shape: a before thunk that raises re-entered on a second entry.
(define (refusing body)
  (let ((entered #f))
    (dynamic-wind
      (lambda ()
        (note! 'before)
        (when entered (note! 'refused) (raise 're-entered))
        (set! entered #t))
      body
      (lambda () (note! 'after)))))

(define (h1 wind)
  (let* ((answer
          (guard (e (#t (list 'the-outer-guard-caught e)))
            (guard (e ((eq? e 'no-such-condition) 'the-inner-guard-caught))
              (wind (lambda () (note! 'body) (raise 'the-body-condition))))))
         (events (take-log!)))
    (list answer events)))

(define (resumed wind)
  (let* ((answer
          (with-exception-handler
           (lambda (c) (note! (list 'outer-handler-returns-from c)) 42)
           (lambda ()
             (guard (e ((eq? e 'no-such-condition) 'the-guard-caught))
               (wind (lambda ()
                       (note! 'body)
                       (let ((v (raise-continuable 'the-body-condition)))
                         (note! (list 'body-resumed-with v))
                         (list 'body-returned v))))))))
         (events (take-log!)))
    (list answer events)))

(define (continuation-after wind)
  (let* ((k #f)
         (calls 0)
         (answer (wind (lambda ()
                         (note! 'body)
                         (call/cc (lambda (c) (set! k c)))
                         (list 'body-returned))))
         (again (begin
                  (set! calls (+ calls 1))
                  (when (= calls 1) (k #f))
                  'continued))
         (events (take-log!)))
    (list answer again events)))

(define (engine-at fuel)
  (let* ((e (make-engine (lambda () (permissive (lambda () (let loop ((i 0)) (if (< i 2000) (loop (+ i 1)) 'done)))))))
         (expiries 0))
    (let run ((e e) (f fuel))
      (e f
         (lambda (left v)
           (let ((events (take-log!)))
             (list (list 'fuel fuel) (list 'expiries expiries) v
                   (list 'befores (length (filter (lambda (x) (eq? x 'before)) events)))
                   (list 'afters (length (filter (lambda (x) (eq? x 'after)) events))))))
         (lambda (next) (set! expiries (+ expiries 1)) (run next 1000))))))

(define (show label x)
  (display label) (display ": ") (write x) (newline))

(show "H1, a refusing before thunk" (h1 refusing))
(show "H1, a permissive before thunk" (h1 permissive))
(show "L, a resumed body, permissive" (resumed permissive))
(show "K, a continuation called after the return, permissive" (continuation-after permissive))
(for-each (lambda (fuel) (show "E" (engine-at fuel))) '(1 2 3 5 10))
(exit 0)
