#!r6rs
;;; (chez-sqlite3 private statement-state): the state table of ADR-0014, as
;;; pure functions. A statement's record keeps its state in Scheme, so that
;;; SQLite's undefined cases, a column read without a row and a bind while a
;;; row is ready, never reach C: each verb is checked against the state first.
;;;
;;;   state      reached by                    allowed
;;;   ready      prepare, reset!               bind!, bind-all!, clear-bindings!,
;;;                                            step!, reset!
;;;   row        step! answering a row         column-value, column-bytevector,
;;;                                            step!, reset!
;;;   done       step! answering done          reset!
;;;   failed     a step answering an error     reset!
;;;   finalized  finalize-statement!, close    nothing
;;;
;;; finalize-statement! is allowed in every state, and does nothing on a
;;; finalized statement; column-count, column-name, statement-sql and
;;; parameter-count work in every state but finalized.
;;;
;;; Every function answers data for any argument, so the verbs call them
;;; inside critical sections, and raise the refusals after the section.
(library (chez-sqlite3 private statement-state)
  (export statement-states statement-verbs statement-verb-check state-after-step
          finish-failure)
  (import (chez-sqlite3 private require-threaded)
          (rnrs)
          (only (chez-sqlite3 private constants) sqlite-result-codes))

  ;; statement-states : (Listof Symbol)
  (define statement-states '(ready row done failed finalized))

  ;; statement-verbs : (Listof Symbol)
  (define statement-verbs
    '(bind! bind-all! clear-bindings! step! reset! column-value column-bytevector
      column-count column-name statement-sql parameter-count finalize-statement!))

  ;; statement-verb-check : Any Any
  ;;   -> (U 'allowed 'no-op 'closed (List 'refused Symbol) 'unknown)
  ;; What VERB does in STATE: allowed; no-op (finalize-statement! on a
  ;; finalized statement); closed (any other verb on a finalized statement);
  ;; (refused STATE) when the state's table does not allow it; unknown when
  ;; VERB is no verb or STATE no state. Total.
  (define (statement-verb-check verb state)
    (cond ((not (and (symbol? verb) (memq verb statement-verbs))) 'unknown)
          ((not (and (symbol? state) (memq state statement-states))) 'unknown)
          ((eq? state 'finalized) (if (eq? verb 'finalize-statement!) 'no-op 'closed))
          ((memq state (allowed-states verb)) 'allowed)
          (else (list 'refused state))))

  ;; allowed-states : Symbol -> (Listof Symbol)
  ;; The states, finalized apart, in which a verb is allowed.
  (define (allowed-states verb)
    (case verb
      ((bind! bind-all! clear-bindings!) '(ready))
      ((step!) '(ready row))
      ((column-value column-bytevector) '(row))
      (else '(ready row done failed))))

  ;; sqlite-code : Symbol -> Natural
  ;; The number constants' table gives a result code's name.
  (define (sqlite-code name) (cdr (assq name sqlite-result-codes)))

  ;; state-after-step : Any -> Symbol
  ;; The state a step leaves: row for exactly SQLITE_ROW (100), done for
  ;; exactly SQLITE_DONE (101), and failed for anything else. That includes a
  ;; code whose low byte is 0, 100 or 101 but that is not exactly 100 or 101
  ;; (0, 256, 356, 357): SQLite's step answers none of them, and
  ;; raise-sqlite-error refuses them, so a step that ever did would end in an
  ;; assertion violation, not a silent pass. Total.
  (define (state-after-step answer)
    (cond ((eqv? answer (sqlite-code 'row)) 'row)
          ((eqv? answer (sqlite-code 'done)) 'done)
          (else 'failed)))

  ;; finish-failure : Any Integer -> (U Integer #f)
  ;; What a reset! or finalize-statement! in STATE raises when SQLite answers
  ;; ANSWER: #f when ANSWER's low byte is 0, 100 or 101, for raise-sqlite-error
  ;; refuses those as no errors; #f when STATE is failed, for the answer
  ;; repeats the step's code, raised already; else ANSWER, a failure of
  ;; reset's or finalize's own (ADR-0014). Total.
  (define (finish-failure state answer)
    (cond ((not (and (integer? answer) (exact? answer))) #f)
          ((memv (bitwise-and answer 255) (list 0 (sqlite-code 'row) (sqlite-code 'done))) #f)
          ((eq? state 'failed) #f)
          (else answer))))
