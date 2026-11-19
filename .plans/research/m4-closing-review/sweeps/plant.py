#!/usr/bin/env python3
# plant.py TREE NAME: applies plant NAME to TREE's src/, each edit's old text
# required exactly once. Reviewer B's three, P-open-advance-after,
# P-conv-advance-after and P-tx-take-after, copied from its scripts/plant.py
# unchanged; then builder D's: its two of Proposal 1 D, P-fold-left-after and
# P-script-claim-after, and the controls that watch each changed high row fail.
import sys, pathlib
tree, name = sys.argv[1], sys.argv[2]

OPEN = "src/chez-sqlite3/private/open.sls"
CONV = "src/chez-sqlite3/private/conveniences.sls"
TXF = "src/chez-sqlite3/private/transaction.sls"

PLANTS = {
 # Each section's claim compared inside the section, and advanced just
 # after it, inline: no procedure call between the section's exit and the
 # advance, so only an expiry at the exit itself splits them.
 "P-open-advance-after": [(OPEN,
"""  (define (made-claim)
    (let ((at 0))
      (lambda (n)
        (and (eqv? at n)
             (begin (set! at (+ n 1)) #t)))))
""",
"""  (define claim-cells (make-eq-hashtable))
  (define (made-claim)
    (let* ((cell (vector 0))
           (claim (lambda (n)
                    (and (eqv? (vector-ref cell 0) n)
                         (begin (vector-set! cell 0 (+ n 1)) #t)))))
      (hashtable-set! claim-cells claim cell)
      claim))
"""),(OPEN,
"""  (define (in-section claim n thunk)
    (critical-section
     (if (claim n)
         (guard (c (#t (list 'raised (+ n 1) c)))
           (call-with-values thunk (lambda answers (cons 'answered (cons (+ n 1) answers)))))
         '(refused))))
""",
"""  (define (in-section claim n thunk)
    (let* ((cell (hashtable-ref claim-cells claim #f))
           (s (critical-section
               (if (eqv? (vector-ref cell 0) n)
                   (guard (c (#t (list 'raised (+ n 1) c)))
                     (call-with-values thunk (lambda answers (cons 'answered (cons (+ n 1) answers)))))
                   '(refused)))))
      (if (eq? (car s) 'refused) s (begin (vector-set! cell 0 (+ n 1)) s))))
""")],
 "P-conv-advance-after": [(CONV,
"""  (define (made-claim)
    (let ((at 0))
      (lambda (n last?)
        (and at
             (or (not n) (eqv? at n))
             (begin (set! at (if last? #f (+ at 1))) #t)))))
""",
"""  (define claim-cells (make-eq-hashtable))
  (define (made-claim)
    (let* ((cell (vector 0))
           (claim (lambda (n last?)
                    (let ((at (vector-ref cell 0)))
                      (and at
                           (or (not n) (eqv? at n))
                           (begin (vector-set! cell 0 (if last? #f (+ at 1))) #t))))))
      (hashtable-set! claim-cells claim cell)
      claim))
"""),(CONV,
"""  (define (in-section claim n last? thunk)
    (critical-section
     (if (claim n last?)
         (let ((next (and n (+ n 1))))
           (guard (c (#t (list 'raised next c)))
             (call-with-values thunk (lambda answers (cons 'answered (cons next answers))))))
         '(refused))))
""",
"""  (define (in-section claim n last? thunk)
    (let* ((cell (hashtable-ref claim-cells claim #f))
           (s (critical-section
               (let ((at (vector-ref cell 0)))
                 (if (and at (or (not n) (eqv? at n)))
                     (let ((next (and n (+ n 1))))
                       (guard (c (#t (list 'raised next c)))
                         (call-with-values thunk (lambda answers (cons 'answered (cons next answers))))))
                     '(refused))))))
      (if (eq? (car s) 'refused)
          s
          (begin
            (vector-set! cell 0 (cond (last? #f) (n (+ n 1)) (else (let ((a (vector-ref cell 0))) (and a (+ a 1))))))
            s))))
""")],
}

 # with-transaction's claim read inside the BEGIN's section and taken just
 # after it, inline.
PLANTS["P-tx-take-after"] = [(TXF,
"""           (claim! (lambda () (and (not taken) (begin (set! taken #t) #t)))))""",
"""           (claim! (vector #f)))"""),
(TXF,
"""        (let ((outcome
               (critical-section
                (if (not (claim!))
                    '(claimed)""",
"""        (let ((outcome
               (critical-section
                (if (vector-ref claim! 0)
                    '(claimed)"""),
(TXF,
"""          (cond ((eq? outcome 'stepped) (if #f #f))
                ((eq? outcome 'ended) (raise-transaction-ended who))
                ((eq? (car outcome) 'claimed) (raise-transaction-ended who))""",
"""          (unless (and (pair? outcome) (eq? (car outcome) 'claimed)) (vector-set! claim! 0 #t))
          (cond ((eq? outcome 'stepped) (if #f #f))
                ((eq? outcome 'ended) (raise-transaction-ended who))
                ((eq? (car outcome) 'claimed) (raise-transaction-ended who))""")]

IMPORTS_OLD = """          (only (chezscheme) critical-section dynamic-wind)
          (only (chez-sqlite3 private native) call-with-c-string)"""
IMPORTS_NEW = """          (only (chezscheme) critical-section dynamic-wind enable-interrupts disable-interrupts)
          (only (chez-sqlite3 private native) call-with-c-string)"""

# query-fold's flag set just after the give-back's section, inline: on a
# normal return the critical after thunk gives the statement back and
# leaves LEFT unset, and the wind's body sets it once the critical wind
# returns, with no procedure call between, so only an expiry at that
# section's exit splits the two. Any other exit, which finalizes the
# statement, sets LEFT inside the section, as the code does.
PLANTS["P-fold-left-after"] = [(CONV,
"""          (lambda ()
            (dynamic-wind #t
              (lambda () #f)
              (lambda ()
                (with-exception-handler
                 (lambda (c)
                   (set! raising (list c))
                   (call-with-values
                    (lambda () (raise-continuable c))
                    (lambda answers (set! raising #f) (apply values answers))))
                 (lambda ()
                   (call-with-values
                    (lambda ()
                      (checked-out who db sql (lambda (made) (set! st made)) left?)""",
"""          (lambda ()
           (let ((v
            (dynamic-wind #t
              (lambda () #f)
              (lambda ()
                (with-exception-handler
                 (lambda (c)
                   (set! raising (list c))
                   (call-with-values
                    (lambda () (raise-continuable c))
                    (lambda answers (set! raising #f) (apply values answers))))
                 (lambda ()
                   (call-with-values
                    (lambda ()
                      (checked-out who db sql (lambda (made) (set! st made)) left?)"""),
(CONV,
"""              (lambda ()
                (when (and st (not left))
                  (set! left #t)
                  (set! finish-failure
                        (guard (e (#t (list e)))
                          (if normal (returned who st) (finalized who st))
                          #f))))))""",
"""              (lambda ()
                (when (and st (not left))
                  (unless normal (set! left #t))
                  (set! finish-failure
                        (guard (e (#t (list e)))
                          (if normal (returned who st) (finalized who st))
                          #f)))))))
             (set! left #t)
             v))""")]

# execute-script!'s claim compared inside the prepare's section, and set
# just after it: by ON-MADE, the section's last work, once the section is
# left, interrupts enabled and disabled again, inline.
PLANTS["P-script-claim-after"] = [(CONV, IMPORTS_OLD, IMPORTS_NEW),
(CONV,
"""      (define (claim! start)
        (and (> start claimed)
             (begin (set! claimed start) #t)))""",
"""      (define claim!
        (case-lambda
          ((start) (> start claimed))
          ((start set) (set! claimed start))))"""),
(CONV,
"""          (let ((made (prepared-at who db sql bytes block start 0 (lambda (s) (set! st s))
                                   (lambda () (not (claim! start))))))""",
"""          (let ((made (prepared-at who db sql bytes block start 0
                                   (lambda (s)
                                     (set! st s)
                                     (enable-interrupts)
                                     (disable-interrupts)
                                     (claim! start 'set))
                                   (lambda () (not (claim! start))))))""")]

# Controls, each to watch a changed high row fail. The open's claim never
# refuses a setting's section: the claim made, its answer dropped.
PLANTS["C-open-settings-unclaimed"] = [(OPEN,
"""  (define (in-section claim n thunk)
    (critical-section
     (if (claim n)""",
"""  (define (in-section claim n thunk)
    (critical-section
     (if (begin (claim n) #t)""")]

# The open's own section never refuses: a run past the call's first
# expression and before the open opens a connection of its own.
PLANTS["C-open-open-unclaimed"] = [(OPEN,
"""        (let ((db (opened-database who (connection-outcome who name flags capacity opt-in
                                                           (lambda () (not (claim 0)))))))""",
"""        (let ((db (opened-database who (connection-outcome who name flags capacity opt-in
                                                           (lambda () (claim 0) #f)))))"""),
(OPEN,
"""                                                         who name flags capacity opt-in
                                                         (lambda () (not (claim 0))))))""",
"""                                                         who name flags capacity opt-in
                                                         (lambda () (claim 0) #f))))""")]

# The conveniences' claim never refuses: claimed, its answer dropped.
PLANTS["C-conv-unclaimed"] = [(CONV,
"""  (define (in-section claim n last? thunk)
    (critical-section
     (if (claim n last?)""",
"""  (define (in-section claim n last? thunk)
    (critical-section
     (if (begin (claim n last?) #t)""")]

# with-transaction's claim never refuses: taken, its answer dropped.
PLANTS["C-tx-unclaimed"] = [(TXF,
"""                (if (not (claim!))
                    '(claimed)""",
"""                (if (not (begin (claim!) #t))
                    '(claimed)""")]

# query-fold's flag never read: every section of the fold's touches the
# statement whatever the flag says.
PLANTS["C-fold-unflagged"] = [(CONV,
"""        (define (left?) left)""",
"""        (define (left?) #f)""")]

# execute-script!'s claim never refuses: claimed, whatever the offset.
PLANTS["C-script-unclaimed"] = [(CONV,
"""      (define (claim! start)
        (and (> start claimed)
             (begin (set! claimed start) #t)))""",
"""      (define (claim! start)
        (set! claimed start)
        #t)""")]

# with-transaction's claim never refuses, and the BEGIN's step no longer
# reads ENDED: a second run of the call begins a level of its own.
PLANTS["C-tx-unclaimed-unended"] = PLANTS["C-tx-unclaimed"] + [(TXF,
"""                      (if (eq? (car plan) 'begin)
                          (issued who db (caddr plan) ended?""",
"""                      (if (eq? (car plan) 'begin)
                          (issued who db (caddr plan) (lambda () #f)""")]

for path, old, new in PLANTS[name]:
    p = pathlib.Path(tree) / path
    text = p.read_text()
    n = text.count(old)
    if n != 1:
        sys.exit(f"{name}: {path}: the old text occurs {n} times")
    p.write_text(text.replace(old, new))
print(f"{name} planted in {tree}")
